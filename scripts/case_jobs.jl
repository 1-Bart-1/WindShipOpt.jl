# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Hands the departures of a run's round trips to Slurm jobs that route them into the case
# store. The run waits for the store, launches a job again that ended with departures
# missing, takes over the jobs a stopped run left running, and stops naming the departures
# still missing once jobs store nothing more. Included by paper_runs.jl; cluster.jl starts
# the jobs.

"""
    SlurmJobs

Round trips computed by Slurm jobs, with the settings of cluster.toml ([`cluster_settings`]
(@ref)).
"""
struct SlurmJobs
    "settings read from cluster.toml"
    settings::Dict{String, Any}
end

"where the run in use hands the departures of its missing round trips, or nothing"
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

Whether `count` departures go to `jobs`: there are jobs, and more departures than the run
has threads.
"""
handed_out(jobs, count) = !isnothing(jobs) && count > Threads.nthreads()

"""
    shard_count(jobs, count)

Shards `count` departures are split into: one per `cores(jobs)` of them, at most one per
job of `job_count(jobs)` besides the run's own.
"""
shard_count(jobs, count) = clamp(cld(count, cores(jobs)), 1, job_count(jobs) - 1)

"""
    write_batch(cases, directories, departures)

Write the `cases` with their case-store `directories` over `departures`, and what a job
needs of the run in use to store their departures as it would, to a batch file in the run's
[`jobs_directory`](@ref), unless a stopped run on the same commit and round-trip code wrote
it already; return its path.
"""
function write_batch(cases, directories, departures)
    run = paper_run
    path = joinpath(mkpath(jobs_directory(run.directory)),
        content_hash((directories, run.record["git_commit"], run.trip_model)) * ".bin")
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

The run a job routes the departures of `batch` ([`write_batch`](@ref)) in: the run that
wrote it, without its definitions.
"""
batch_run(batch) = PaperRun(batch.directory, batch.fidelity, batch.record, batch.only,
    Dict{Symbol, Vector{Any}}(), batch.trip_model, StepTally())

"""
    stored_count(path)

Number of the departures of the batch file `path` ([`write_batch`](@ref)) that the run
which wrote it no longer has to route.
"""
function stored_count(path)
    batch = deserialize(path)
    global paper_run = batch_run(batch)
    return departure_count(batch) - length(shard_missing(batch, 1, 1))
end

"number of departures of the round trips of `batch`, those of each case in turn"
departure_count(batch) = length(batch.cases) * length(batch.departures)

"index in `batch` of the case and of the departure of its `k`-th departure"
departure_case(batch, k) = divrem(k - 1, length(batch.departures)) .+ 1

"""
    shard_departures(batch, shard, shards)

The departures of `batch` in shard `shard` of `shards`: one run of them in turn, so that a
shard holds the departures of few cases.
"""
shard_departures(batch, shard, shards) =
    (div((shard - 1) * departure_count(batch), shards) + 1):div(
        shard * departure_count(batch), shards)

"""
    shard_missing(batch, shard, shards)

Those departures of `batch` in shard `shard` of `shards` that the run in use still has to
route: of a case whose round trip it does not find in the case store, with no entry of its
own there.
"""
shard_missing(batch, shard, shards) = filter(shard_departures(batch, shard, shards)) do k
    case, departure = departure_case(batch, k)
    directory = batch.directories[case]
    return ismissing(stored_entry(directory, batch.cases[case])) &&
           ismissing(departure_entry(departure_directory(directory,
               batch.departures[departure]), batch.cases[case]))
end

"labels of the case of the `k`-th departure of `batch`, and the departure [h]"
function departure_labels(batch, k)
    case, departure = departure_case(batch, k)
    return string(case_labels(batch.cases[case]), " departure=",
        batch.departures[departure])
end

"""
    shard_trips(path, shard, shards)

Route into the case store, in the run in use, the missing departures of shard `shard` of
`shards` of the batch file `path`, those of each case on one routing.
"""
function shard_trips(path, shard, shards)
    batch = deserialize(path)
    todo = shard_missing(batch, shard, shards)
    println(length(todo), " departures to route")
    by_case = Dict{Int, Vector{Float64}}()
    for k in todo
        case, departure = departure_case(batch, k)
        push!(get!(by_case, case, Float64[]), batch.departures[departure])
    end
    Threads.@threads :greedy for (case, picked) in collect(by_case)
        departure_entries(batch.cases[case], picked,
            departure_directory.(batch.directories[case], picked))
    end
end

"""
    job_trips(jobs, cases, directories, departures)

Store the departures of the round trips of `cases` in `directories` over `departures` that
the case store lacks, routed by `jobs`: one shard of the departures per job, a run of them
in turn each, a job that a stopped run left on a shard waited for rather than launched
again. A job that ends with departures of its shard missing is launched again until
`retries(jobs)` launches in a row stored none; then this throws an error naming the
departures still missing.
"""
function job_trips(jobs, cases, directories, departures)
    batch = write_batch(cases, directories, departures)
    handed = (; cases, directories, departures)
    shards = shard_count(jobs, departure_count(handed))
    todo = [shard_missing(handed, shard, shards) for shard in 1:shards]
    handles = Any[isempty(todo[shard]) ? nothing : take_over(jobs, batch, shard, shards)
                  for shard in 1:shards]
    fruitless = zeros(Int, shards)
    println("  ", sum(length, todo), " of ", departure_count(handed),
        " departures handed to ", count(!isnothing, handles), " jobs")
    lacking = Int[]
    while any(!isnothing, handles)
        sleep(poll_seconds(jobs))
        alive = running(jobs, filter(!isnothing, handles))
        for shard in 1:shards
            handle = handles[shard]
            (isnothing(handle) || handle in alive) && continue
            missed = shard_missing(handed, shard, shards)
            fruitless[shard] =
                length(missed) < length(todo[shard]) ? 0 : fruitless[shard] + 1
            todo[shard] = missed
            handles[shard] = isempty(missed) || fruitless[shard] > retries(jobs) ? nothing :
                             launch(jobs, batch, shard, shards)
            isnothing(handles[shard]) && append!(lacking, missed)
        end
    end
    isempty(lacking) || error("no entry in the case store for ", length(lacking),
        " departures of batch ", batch, ":\n",
        join(departure_labels.(Ref(handed), sort(lacking)), "\n"))
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

Submit a job routing the missing departures of shard `shard` of `shards` of the batch file
`batch`, its id written to its [`job_file`](@ref); return the id.
"""
function launch(jobs::SlurmJobs, batch, shard, shards)
    log = string(batch, "-", shard, "-%j.log")
    command = slurm_command(jobs.settings, cores(jobs), jobs.settings["memory_per_core"],
        "windship-cases", log, job_command(cores(jobs), "shard", batch, shard, shards))
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

Those of the job ids `handles` whose job is queued or running, every one while the queue
cannot be read.
"""
function running(::SlurmJobs, handles)
    queue = IOBuffer()
    success(pipeline(`squeue --me --noheader --format=%i`; stdout=queue)) &&
        return filter(in(split(String(take!(queue)))), handles)
    println("  squeue failed at ", floor(now(), Second), "; waiting for every job")
    return handles
end

"""
    stalled_run_jobs(fidelity)

Run jobs in a row, the one calling this included, that found the latest unfinished run at
`fidelity` with no more steps done or departures of its batches stored than the run job
before it did; 0 without such a run.
"""
function stalled_run_jobs(fidelity)
    runs = filter(run -> !is_finished(last(run)), fidelity_runs(fidelity))
    isempty(runs) && return 0
    directory, record = first(runs)
    batches = mkpath(jobs_directory(directory))
    progress = length(record["steps"]) +
               sum(stored_count, filter(endswith(".bin"), readdir(batches; join=true));
        init=0)
    path = joinpath(batches, "run_jobs.toml")
    before = isfile(path) ? TOML.parsefile(path) : Dict("progress" => -1, "stalled" => 0)
    stalled = progress > before["progress"] ? 0 : before["stalled"] + 1
    open(io -> TOML.print(io, Dict("progress" => progress, "stalled" => stalled)), path, "w")
    return stalled
end

"""
    slurm_command(settings, cores, memory_per_core, name, log, command; after=nothing)

The `sbatch` call submitting `command` as one task named `name` on `cores` cores with
`memory_per_core` each, as Slurm's `--mem-per-cpu`, and the wall time, account and partition
of `settings`, writing to `log`, which prints its job id; with `after` a job id, the task
starts once that job has ended.
"""
function slurm_command(settings, cores, memory_per_core, name, log, command; after=nothing)
    for setting in ("account", "partition")
        isempty(settings[setting]) && error("set the $setting in scripts/cluster.toml")
    end
    dependency = isnothing(after) ? `` : `--dependency=afterany:$after`
    return `sbatch --parsable --job-name=$name --account=$(settings["account"])
        --partition=$(settings["partition"]) --time=$(settings["wall_time"]) $dependency
        --ntasks=1 --cpus-per-task=$cores --mem-per-cpu=$memory_per_core --output=$log
        --wrap=$(Base.shell_escape(command.exec...))`
end
