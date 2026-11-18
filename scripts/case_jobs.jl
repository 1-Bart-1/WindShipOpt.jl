# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Hands the round trips a run is missing to Slurm jobs that compute them into the case
# store. The run waits for the store, launches a job again that ended with round trips
# missing, and stops naming the cases still missing once it has tried enough. Included by
# paper_runs.jl; cluster.jl starts the jobs.

"""
    SlurmJobs

Round trips computed by Slurm jobs, with the settings of cluster.toml ([`cluster_settings`]
(@ref)).
"""
struct SlurmJobs
    "settings read from cluster.toml"
    settings::Dict{String, Any}
end

"where the run in use hands its missing round trips, or nothing to compute them itself"
case_jobs = nothing

cores(jobs::SlurmJobs) = jobs.settings["cores"]
job_count(jobs::SlurmJobs) = jobs.settings["jobs"] - 1
retries(jobs::SlurmJobs) = jobs.settings["retries"]
poll_seconds(::SlurmJobs) = 60.0

"""
    cluster_settings(path=joinpath(@__DIR__, "cluster.toml"))

The Slurm settings of the paper runs on a cluster, from `path`.
"""
cluster_settings(path=joinpath(@__DIR__, "cluster.toml")) = TOML.parsefile(path)

"""
    handed_out(jobs, count)

Whether `count` missing round trips go to `jobs`: there are jobs, and more round trips than
the run has threads.
"""
handed_out(jobs, count) = !isnothing(jobs) && count > Threads.nthreads()

"""
    shard_count(jobs, count)

Shards `count` round trips are split into: one per `cores(jobs)` of them, at most
`job_count(jobs)`.
"""
shard_count(jobs, count) = clamp(cld(count, cores(jobs)), 1, job_count(jobs))

"""
    write_batch(cases, directories, departures)

Write the `cases` with their case-store `directories` over `departures`, and what a job
needs of the run in use to store their round trips as it would, to a batch file in the run's
[`jobs_directory`](@ref); return its path.
"""
function write_batch(cases, directories, departures)
    run = paper_run
    path = joinpath(mkpath(jobs_directory(run.directory)),
        content_hash(directories) * ".bin")
    record = Dict("git_commit" => run.record["git_commit"],
        "git_dirty" => run.record["git_dirty"])
    serialize(path, (; run.directory, run.fidelity, record, run.only, run.trip_model, cases,
        directories, departures))
    return path
end

"""
    jobs_directory(run_directory)

Directory of the batches and job logs of the run in `run_directory`, beside the runs.
"""
jobs_directory(run_directory) =
    joinpath(dirname(runs_directory), "jobs", basename(run_directory))

"""
    batch_run(batch)

The run a job computes the round trips of `batch` ([`write_batch`](@ref)) in: the run that
wrote it, without its definitions.
"""
batch_run(batch) = PaperRun(batch.directory, batch.fidelity, batch.record, batch.only,
    Dict{Symbol, Vector{Any}}(), batch.trip_model, StepTally())

"""
    stored_count(path)

Number of the round trips of the batch file `path` ([`write_batch`](@ref)) that the run
which wrote it finds in the case store.
"""
function stored_count(path)
    batch = deserialize(path)
    global paper_run = batch_run(batch)
    return length(batch.cases) - length(shard_missing(batch, 1, 1))
end

"""
    shard_missing(batch, shard, shards)

Indices of the cases of `batch` in shard `shard` of `shards` whose round trip the run in use
does not find in the case store.
"""
shard_missing(batch, shard, shards) =
    filter(k -> ismissing(stored_entry(batch.directories[k], batch.cases[k])),
        shard:shards:length(batch.cases))

"""
    job_trips(jobs, cases, directories, departures)

Case-store entries of the round trips of `cases` in `directories` over `departures`,
computed by `jobs`: one shard of the cases per job, every `k`-th case to the `k`-th job.
Throws an error naming the cases still missing once every job has ended and those missing a
round trip have been launched `retries(jobs)` times more.
"""
function job_trips(jobs, cases, directories, departures)
    batch = write_batch(cases, directories, departures)
    shards = shard_count(jobs, length(cases))
    handles = Any[launch(jobs, batch, shard, shards) for shard in 1:shards]
    launches = ones(Int, shards)
    println("  ", length(cases), " round trips handed to ", shards, " jobs")
    lacking = Int[]
    while any(!isnothing, handles)
        sleep(poll_seconds(jobs))
        alive = running(jobs, filter(!isnothing, handles))
        for shard in 1:shards
            handle = handles[shard]
            (isnothing(handle) || handle in alive) && continue
            missed = shard_missing((; cases, directories), shard, shards)
            handles[shard] = isempty(missed) || launches[shard] > retries(jobs) ? nothing :
                             launch(jobs, batch, shard, shards)
            launches[shard] += !isnothing(handles[shard])
            isnothing(handles[shard]) && append!(lacking, missed)
        end
    end
    isempty(lacking) || error("no round trip in the case store for ",
        length(lacking), " cases of batch ", batch, ":\n",
        join(case_labels.(cases[sort(lacking)]), "\n"))
    return Any[stored_entry(directory, case)
               for (case, directory) in zip(cases, directories)]
end

"""
    job_command(cores, arguments...)

Command running cluster.jl with `arguments` on this Julia and the scripts environment with
`cores` threads.
"""
job_command(cores, arguments...) = `$(Base.julia_cmd()) --project=$(@__DIR__) -t $cores
    $(joinpath(@__DIR__, "cluster.jl")) $arguments`

"""
    launch(jobs, batch, shard, shards)

Start a job computing the missing round trips of shard `shard` of `shards` of the batch
file `batch`; return its handle.
"""
function launch(jobs::SlurmJobs, batch, shard, shards)
    log = string(batch, "-", shard, "-%j.log")
    command = slurm_command(jobs.settings, "windship-cases", jobs.settings["case_time"],
        log, job_command(cores(jobs), "shard", batch, shard, shards))
    return strip(read(command, String))
end

"""
    running(jobs, handles)

Those of `handles` whose jobs have not ended; all of them while the queue cannot be read.
"""
function running(::SlurmJobs, handles)
    queue = IOBuffer()
    if !success(pipeline(`squeue --me --noheader --format=%i`; stdout=queue))
        println("  squeue failed at ", floor(now(), Second), "; waiting for every job")
        return handles
    end
    return filter(in(split(String(take!(queue)))), handles)
end

"""
    slurm_command(settings, name, time, log, command)

The `sbatch` call submitting `command` as one task named `name` of wall time `time` with the
cores, memory, account and partition of `settings`, writing to `log`, which prints its job
id.
"""
function slurm_command(settings, name, time, log, command)
    for setting in ("account", "partition")
        isempty(settings[setting]) && error("set the $setting in scripts/cluster.toml")
    end
    return `sbatch --parsable --job-name=$name --account=$(settings["account"])
        --partition=$(settings["partition"]) --time=$time --ntasks=1
        --cpus-per-task=$(settings["cores"]) --mem-per-cpu=$(settings["memory_per_core"])
        --output=$log --wrap=$(Base.shell_escape(command.exec...))`
end
