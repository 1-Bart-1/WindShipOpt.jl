# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Paper runs on a Slurm cluster, with the settings of cluster.toml; bin/cluster calls it.
# A submitted run is one job running `paper`, which hands each batch of missing round trips
# to jobs of its own and waits for them. The jobs call this script as `run` and `shard`.
using Printf

command = isempty(ARGS) ? "help" : popfirst!(ARGS)
if command in ("run", "shard")
    include(joinpath(@__DIR__, "paper.jl"))
else
    root = joinpath(@__DIR__, "..")
    include(joinpath(@__DIR__, "paper_runs.jl"))
end

"""
    submit_run(fidelity, steps)

Submit the job running `paper(steps...; fidelity, resume=true)` with jobs computing its
round trips, unless a job of a paper run is queued or running already.
"""
function submit_run(fidelity, steps)
    queued = read(`squeue --me --noheader --name=windship-run,windship-cases --format=%i`,
        String)
    isempty(strip(queued)) || error("jobs of a paper run are queued or running already: ",
        join(split(queued), ", "))
    settings = cluster_settings()
    log = joinpath(mkpath(joinpath(root, "output", "slurm")), "run-%j.log")
    job = job_command(settings["cores"], "run", fidelity, steps...)
    id = strip(read(slurm_command(settings, "windship-run", settings["run_time"], log, job),
        String))
    println("submitted job ", id, "; its log is ", replace(log, "%j" => id))
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
    todo = shard_missing(batch, shard, shards)
    println(length(todo), " round trips to compute")
    compute_trips(batch.cases[todo], batch.directories[todo], batch.departures)
end

if command == "submit"
    submit_run(ARGS[1], ARGS[2:end])
elseif command == "status"
    print_jobs_status()
elseif command == "run"
    case_jobs = SlurmJobs(cluster_settings())
    paper(Symbol.(ARGS[2:end])...; fidelity=Symbol(ARGS[1]), resume=true)
elseif command == "shard"
    compute_shard(ARGS[1], parse(Int, ARGS[2]), parse(Int, ARGS[3]))
else
    println("usage: bin/cluster submit draft|final [step ...] | bin/cluster status")
end
