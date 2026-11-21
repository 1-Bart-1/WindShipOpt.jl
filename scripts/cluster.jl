# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Paper runs on a Slurm cluster, with the settings of cluster.toml; bin/cluster calls it.
# A submitted run is one job running `paper`, which computes a share of each batch of round
# trips and hands the rest to jobs of its own. A run job ended by its wall time leaves a
# successor that resumes it. The jobs call this script as `run` and `shard`. Compute nodes
# reach no internet, so the login node fetches a run kept in its commit's release before
# submitting it, and `keep` uploads the runs from there while their jobs run.
using Printf

command = isempty(ARGS) ? "help" : popfirst!(ARGS)
if command in ("run", "shard", "estimate")
    include(joinpath(@__DIR__, "paper.jl"))
    include(joinpath(@__DIR__, "run_estimate.jl"))
else
    root = joinpath(@__DIR__, "..")
    include(joinpath(@__DIR__, "paper_runs.jl"))
    include(joinpath(@__DIR__, "github_releases.jl"))
end

"""
    submit_run(fidelity, steps)

Submit the job running `paper(steps...; fidelity, resume=true)` with jobs computing its
round trips, unless a job of a paper run is queued or running already, once the runs kept
in the release of this commit are fetched ([`fetch_runs`](@ref)).
"""
function submit_run(fidelity, steps)
    queued = paper_jobs()
    isempty(queued) || error("jobs of a paper run are queued or running already: ",
        join(queued, ", "))
    fetch_runs(default_releases(), Symbol(fidelity))
    id = submit_run_job(fidelity, steps)
    println("submitted job ", id, "; its log is ", run_log(id))
end

"""
    submit_run_job(fidelity, steps; after=nothing)

Submit a job running `paper(steps...; fidelity, resume=true)`, starting once the job `after`
has ended where one is given; return its id.
"""
function submit_run_job(fidelity, steps; after=nothing)
    settings = cluster_settings()
    job = job_command(settings["cores"], "run", fidelity, steps...)
    return strip(read(slurm_command(settings, "windship-run", run_log("%j"), job; after),
        String))
end

"ids of this user's jobs of paper runs queued or running"
paper_jobs() =
    split(read(`squeue --me --noheader --name=windship-run,windship-cases --format=%i`,
        String))

"""
    keep_cluster_runs()

Keep the latest run at each fidelity in the releases of its commit ([`keep_commit`](@ref))
every [`KEEP_MINUTES`](@ref) while jobs of a paper run are queued or running, and once more
when they have ended.
"""
function keep_cluster_runs()
    releases = default_releases()
    while true
        running = !isempty(paper_jobs())
        for fidelity in keys(fidelities)
            runs = fidelity_runs(fidelity)
            isempty(runs) && continue
            record = last(first(runs))
            keep_commit(releases, fidelity, record["git_commit"], record["git_dirty"])
        end
        running || return
        sleep(60 * KEEP_MINUTES)
    end
end

"log file of the run job `id`"
run_log(id) = joinpath(mkpath(joinpath(root, "output", "slurm")), "run-$id.log")

"""
    run_job(fidelity, steps)

Run `paper(steps...; fidelity, resume=true)` in this Slurm job, handing round trips to jobs
of its own, with a successor job queued that resumes the run should this job be ended at
its wall time, and cancelled once the run finishes or fails. Stops before that once more
run jobs in a row than the `retries` of cluster.toml found the run with nothing new done.
"""
function run_job(fidelity, steps)
    settings = cluster_settings()
    stalled = stalled_run_jobs(Symbol(fidelity))
    stalled > settings["retries"] && error(stalled, " run jobs in a row found the ",
        fidelity, " run with no step done and no round trip stored since the one before")
    successor = submit_run_job(fidelity, steps; after=ENV["SLURM_JOB_ID"])
    global case_jobs = SlurmJobs(settings)
    try
        paper(Symbol.(steps)...; fidelity=Symbol(fidelity), resume=true)
    finally
        success(`scancel $successor`) || println("could not cancel job ", successor)
    end
end

"""
    print_jobs_status()

Print the paper-run jobs queued or running, and for the latest run at each fidelity the
steps it has done and how many round trips of each of its batches are stored.
"""
function print_jobs_status()
    run(`squeue --me --name=windship-run,windship-cases`)
    for fidelity in keys(fidelities)
        runs = fidelity_runs(fidelity)
        isempty(runs) && continue
        directory, record = first(runs)
        done = [step["name"] for step in record["steps"]]
        println("\n", fidelity, " run ", basename(directory), ", commit ",
            first(record["git_commit"], 7), is_finished(record) ? ", finished" : "")
        println("  done: ", isempty(done) ? "none" : join(done, ", "))
        println("  still to do: ", join(setdiff(record["requested"], done), ", "))
        print_batches(jobs_directory(directory))
    end
end

"""
    print_batches(directory)

Print for each batch file in `directory` ([`write_batch`](@ref)) how many of its round
trips its run finds in the case store ([`stored_count`](@ref)).
"""
function print_batches(directory)
    isdir(directory) || return
    for file in filter(endswith(".bin"), readdir(directory; join=true))
        started = floor(unix2datetime(mtime(file)), Second)
        @printf("  batch of %s UTC: %d of %d round trips stored\n", started,
            stored_count(file), length(deserialize(file).cases))
    end
end

"""
    compute_shard(path, shard, shards)

Compute into the case store the missing round trips of shard `shard` of `shards` of the
batch file `path`, as the run that wrote it would.
"""
function compute_shard(path, shard, shards)
    batch = deserialize(path)
    global paper_run = batch_run(batch)
    model = trip_model(script_definitions(script_files()))
    model == batch.trip_model || error("this checkout's round-trip code ", model,
        " is not the run's ", batch.trip_model)
    shard_trips(path, shard, shards)
end

if command == "submit"
    submit_run(ARGS[1], ARGS[2:end])
elseif command == "status"
    print_jobs_status()
elseif command == "keep"
    keep_cluster_runs()
elseif command == "run"
    run_job(ARGS[1], ARGS[2:end])
elseif command == "shard"
    compute_shard(ARGS[1], parse(Int, ARGS[2]), parse(Int, ARGS[3]))
elseif command == "estimate"
    print_estimate(; box_cores=isempty(ARGS) ? 20 : parse(Int, only(ARGS)))
else
    println("usage: bin/cluster submit draft|final [step ...] | bin/cluster keep | ",
        "bin/cluster status | bin/cluster estimate [box cores]")
end
