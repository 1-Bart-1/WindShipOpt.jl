# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Hands the round trips of a run to Slurm jobs that compute them into the case store, the
# run's own job computing one share. The run waits for the store, launches a job again that
# ended with round trips missing, takes over the jobs a stopped run left running, and stops
# naming the cases still missing once jobs store nothing more. Included by paper_runs.jl;
# cluster.jl starts the jobs.

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
job_count(jobs::SlurmJobs) = jobs.settings["jobs"]
retries(jobs::SlurmJobs) = jobs.settings["retries"]
poll_seconds(::SlurmJobs) = 60.0

"""
    cluster_settings(path=joinpath(@__DIR__, "cluster.toml"))

The Slurm settings of the paper runs on a cluster, from `path`.
"""
cluster_settings(path=joinpath(@__DIR__, "cluster.toml")) = TOML.parsefile(path)

"""
    handed_out(jobs, count)

Whether `count` round trips go to `jobs`: there are jobs, and more round trips than the run
has threads.
"""
handed_out(jobs, count) = !isnothing(jobs) && count > Threads.nthreads()

"""
    shard_count(jobs, count)

Shards `count` round trips are split into: one per `cores(jobs)` of them, at most
`job_count(jobs)`, the run's own job included.
"""
shard_count(jobs, count) = clamp(cld(count, cores(jobs)), 1, job_count(jobs))

"""
    write_batch(cases, directories, departures)

Write the `cases` with their case-store `directories` over `departures`, and what a job
needs of the run in use to store their round trips as it would, to a batch file in the run's
[`jobs_directory`](@ref), unless a stopped run wrote it already; return its path.
"""
function write_batch(cases, directories, departures)
    run = paper_run
    path = joinpath(mkpath(jobs_directory(run.directory)),
        content_hash(directories) * ".bin")
    isfile(path) && return path
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
    shard_trips(path, shard, shards)

Compute into the case store, in the run in use, the missing round trips of shard `shard` of
`shards` of the batch file `path`.
"""
function shard_trips(path, shard, shards)
    batch = deserialize(path)
    todo = shard_missing(batch, shard, shards)
    println(length(todo), " round trips to compute")
    compute_trips(batch.cases[todo], batch.directories[todo], batch.departures)
end

"""
    job_trips(jobs, cases, directories, departures)

Case-store entries of the round trips of `cases` in `directories` over `departures`,
computed by `jobs`: one shard of the cases per job, every `k`-th case to the `k`-th job, a
job that a stopped run left on a shard waited for rather than launched again. A job that
ends with round trips of its shard missing is launched again until `retries(jobs)` launches
in a row stored none; then this throws an error naming the cases still missing.
"""
function job_trips(jobs, cases, directories, departures)
    batch = write_batch(cases, directories, departures)
    shards = shard_count(jobs, length(cases))
    todo = [shard_missing((; cases, directories), shard, shards) for shard in 1:shards]
    handles = Any[isempty(todo[shard]) ? nothing : take_over(jobs, batch, shard, shards)
                  for shard in 1:shards]
    fruitless = zeros(Int, shards)
    println("  ", sum(length, todo), " of ", length(cases), " round trips handed to ",
        count(!isnothing, handles), " jobs")
    lacking = Int[]
    while any(!isnothing, handles)
        sleep(poll_seconds(jobs))
        alive = running(jobs, filter(!isnothing, handles))
        for shard in 1:shards
            handle = handles[shard]
            (isnothing(handle) || handle in alive) && continue
            missed = shard_missing((; cases, directories), shard, shards)
            fruitless[shard] = length(missed) < length(todo[shard]) ? 0 : fruitless[shard] + 1
            todo[shard] = missed
            handles[shard] = isempty(missed) || fruitless[shard] > retries(jobs) ? nothing :
                             launch(jobs, batch, shard, shards)
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
    take_over(jobs, batch, shard, shards)

Handle of the job a stopped run left on shard `shard` of the batch file `batch`
([`left_running`](@ref)), else of one launched on it.
"""
function take_over(jobs, batch, shard, shards)
    handle = left_running(jobs, batch, shard)
    return isnothing(handle) ? launch(jobs, batch, shard, shards) : handle
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

Start computing the missing round trips of shard `shard` of `shards` of the batch file
`batch`: the first shard in a task of this process, the run's own job, every other in a job
of its own whose id goes to its [`job_file`](@ref); return the task or job id.
"""
function launch(jobs::SlurmJobs, batch, shard, shards)
    shard == 1 && return Threads.@spawn shard_trips(batch, shard, shards)
    log = string(batch, "-", shard, "-%j.log")
    command = slurm_command(jobs.settings, "windship-cases", log,
        job_command(cores(jobs), "shard", batch, shard, shards))
    id = strip(read(command, String))
    write(job_file(batch, shard), id)
    return id
end

"file holding the id of the last job launched on shard `shard` of the batch file `batch`"
job_file(batch, shard) = string(batch, "-", shard, ".job")

"""
    left_running(jobs, batch, shard)

Id of the job last launched on shard `shard` of the batch file `batch` while it is queued or
running, else nothing.
"""
function left_running(jobs::SlurmJobs, batch, shard)
    isfile(job_file(batch, shard)) || return nothing
    id = read(job_file(batch, shard), String)
    return isempty(running(jobs, [id])) ? nothing : id
end

"""
    running(jobs, handles)

Those of `handles` whose task or job has not ended, every job while the queue cannot be
read. Throws the error of a task that failed.
"""
function running(::SlurmJobs, handles)
    tasks = filter(handle -> handle isa Task, handles)
    foreach(wait, filter(istaskdone, tasks))
    ids = filter(handle -> !(handle isa Task), handles)
    queue = IOBuffer()
    if success(pipeline(`squeue --me --noheader --format=%i`; stdout=queue))
        ids = filter(in(split(String(take!(queue)))), ids)
    else
        println("  squeue failed at ", floor(now(), Second), "; waiting for every job")
    end
    return [filter(!istaskdone, tasks); ids]
end

"""
    slurm_command(settings, name, log, command; after=nothing)

The `sbatch` call submitting `command` as one task named `name` with the wall time, cores,
memory, account and partition of `settings`, writing to `log`, which prints its job id; with
`after` a job id, the task starts once that job has ended.
"""
function slurm_command(settings, name, log, command; after=nothing)
    for setting in ("account", "partition")
        isempty(settings[setting]) && error("set the $setting in scripts/cluster.toml")
    end
    dependency = isnothing(after) ? `` : `--dependency=afterany:$after`
    return `sbatch --parsable --job-name=$name --account=$(settings["account"])
        --partition=$(settings["partition"]) --time=$(settings["wall_time"]) $dependency
        --ntasks=1 --cpus-per-task=$(settings["cores"])
        --mem-per-cpu=$(settings["memory_per_core"]) --output=$log
        --wrap=$(Base.shell_escape(command.exec...))`
end
