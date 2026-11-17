# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Hands the round trips a run is missing to jobs that compute them into the case store: Slurm
# jobs on a cluster, or processes on this machine. The run waits for the store, launches a
# job again that ended with round trips missing, and stops naming the cases still missing
# once it has tried enough. Included by paper_runs.jl; cluster.jl starts the jobs.

"""
    SlurmJobs

Round trips computed by Slurm jobs, with the settings of cluster.toml ([`cluster_settings`]
(@ref)).
"""
struct SlurmJobs
    "settings read from cluster.toml"
    settings::Dict{String, Any}
end

"""
    LocalJobs

Round trips computed by Julia processes on this machine, each of `cores` threads, at most
`jobs` at once besides the run, each launched again at most `retries` times.
"""
struct LocalJobs
    "threads of each process"
    cores::Int
    "processes at once"
    jobs::Int
    "launches of a shard after its first"
    retries::Int
end

"where the run in use hands its missing round trips, or nothing to compute them itself"
case_jobs = nothing

cores(jobs::LocalJobs) = jobs.cores
cores(jobs::SlurmJobs) = jobs.settings["cores"]
job_count(jobs::LocalJobs) = jobs.jobs
job_count(jobs::SlurmJobs) = jobs.settings["jobs"] - 1
retries(jobs::LocalJobs) = jobs.retries
retries(jobs::SlurmJobs) = jobs.settings["retries"]
poll_seconds(::LocalJobs) = 1.0
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
[`jobs_directory`](@ref), with its summary beside it as TOML; return its path.
"""
function write_batch(cases, directories, departures)
    run = paper_run
    path = joinpath(mkpath(jobs_directory(run.directory)), content_hash(directories))
    record = Dict("git_commit" => run.record["git_commit"],
        "git_dirty" => run.record["git_dirty"])
    serialize(path * ".bin", (; run.directory, run.fidelity, record, run.only,
        run.trip_model, cases, directories, departures))
    open(io -> TOML.print(io, Dict("trip_model" => run.trip_model, "cases" => directories,
            "started" => string(floor(now(), Second)))), path * ".toml", "w")
    return path * ".bin"
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
    return Any[stored_entry(directory, case) for (case, directory) in zip(cases, directories)]
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
function launch(jobs::LocalJobs, batch, shard, shards)
    log = string(batch, "-", shard, ".log")
    command = job_command(cores(jobs), "shard", batch, shard, shards)
    return run(pipeline(command; stdout=log, stderr=log, append=true); wait=false)
end

function launch(jobs::SlurmJobs, batch, shard, shards)
    log = string(batch, "-", shard, "-%j.log")
    command = slurm_command(jobs.settings, "windship-cases", jobs.settings["case_time"],
        log, job_command(cores(jobs), "shard", batch, shard, shards))
    return strip(read(command, String))
end

"""
    running(jobs, handles)

Those of `handles` whose jobs have not ended.
"""
running(::LocalJobs, handles) = filter(process_running, handles)

function running(::SlurmJobs, handles)
    queued = split(read(`squeue --me --noheader --format=%i`, String))
    return filter(in(queued), handles)
end

"""
    slurm_command(settings, name, time, log, command)

The `sbatch` call submitting `command` as one task named `name` of wall time `time` with the
cores, memory, account and partition of `settings`, writing to `log`, which prints its job
id.
"""
function slurm_command(settings, name, time, log, command)
    isempty(settings["partition"]) && error("set the partition in scripts/cluster.toml")
    account = isempty(settings["account"]) ? `` : `--account=$(settings["account"])`
    return `sbatch --parsable --job-name=$name $account
        --partition=$(settings["partition"]) --time=$time --ntasks=1
        --cpus-per-task=$(settings["cores"]) --mem-per-cpu=$(settings["memory_per_core"])
        --output=$log --wrap=$(Base.shell_escape(command.exec...))`
end
