# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Paper runs on a Slurm cluster, with the settings of cluster.toml; bin/cluster calls it.
#
#     bin/cluster submit draft            # submit a draft run of every step
#     bin/cluster submit final classes    # a final run of the class study alone
#     bin/cluster status                  # jobs queued, and what each latest run has done
#
# A submitted run is one job running `paper`, which hands each batch of missing round trips
# to jobs of its own and waits for them. The jobs call this script as `run` and `shard`.
using Dates
using Printf
using Serialization
using TOML

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
round trips, unless such a job is queued or running already.
"""
function submit_run(fidelity, steps)
    queued = read(`squeue --me --noheader --name=windship-run --format=%i`, String)
    isempty(strip(queued)) || error("a paper run is queued or running already: job ",
        strip(queued))
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

Print for each batch summary in `directory` ([`write_batch`](@ref)) how many of its round
trips the case store holds by its code.
"""
function print_batches(directory)
    isdir(directory) || return
    for file in filter(endswith(".toml"), readdir(directory; join=true))
        batch = TOML.parsefile(file)
        stored = count(batch["cases"]) do case
            isdir(case) && any(startswith(batch["trip_model"]), readdir(case))
        end
        @printf("  batch of %s: %d of %d round trips stored\n", batch["started"], stored,
            length(batch["cases"]))
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
