# Runs of the paper: each data-making call of `paper` keeps its data files, the round
# trips it has finished and its record run.toml in output/runs/<start time>/, so that a
# run cut short resumes where it stopped. Included by paper.jl.
using Dates
using Serialization
using TOML

"""
Settings of each fidelity of the paper: the corridor scale, the step between sampled
departures and the rounds of the rig size search.
"""
fidelities = Dict(:draft => (corridor_scale=8.0, departure_step=12, size_rounds=1),
    :final => (corridor_scale=4.0, departure_step=6, size_rounds=2))

"directory with one directory per run, named by the time the run started"
runs_directory = normpath(joinpath(root, "output", "runs"))

"""
    PaperRun

A call of `paper` with the counts of the step in progress.
"""
mutable struct PaperRun
    "directory of the run; nothing when only figure and table steps run"
    directory::Union{Nothing, String}
    "fidelity of the run, a key of `fidelities`"
    fidelity::Symbol
    "contents of run.toml"
    record::Dict{String, Any}
    "round-trip cases of the step in progress"
    cases::Int
    "feasible round trips of the step in progress"
    trips::Int
end

"the run in use, set by `paper`"
paper_run = nothing

"""
    run_settings()

Settings of [`fidelities`](@ref) at the fidelity of the run in use.
"""
run_settings() = fidelities[paper_run.fidelity]

"""
    sampled_departures(; screening=false)

The departures the studies average over: every `departure_step`-th one of the run's
fidelity, or half as many for the input `screening`.
"""
sampled_departures(; screening=false) =
    departures[1:(run_settings().departure_step * (screening ? 2 : 1)):end]

"""
    run_corridors(name)

Outbound and return corridors of route `name` at the corridor scale of the run in use.
"""
run_corridors(name) = corridors(name, run_settings().corridor_scale)

"""
    run_file(name)

Path in the directory of the run in use of the data file `name` a step writes.
"""
run_file(name) = joinpath(paper_run.directory, name)

"""
    data_file(name)

Path of the data file `name` a step reads: in the run in use, else in the latest finished
run of its fidelity that has it, else in the latest unfinished one.
"""
function data_file(name)
    runs = fidelity_runs(paper_run.fidelity)
    finished = [directory for (directory, record) in runs if is_finished(record)]
    unfinished = [directory for (directory, record) in runs if !is_finished(record)]
    for directory in filter(!isnothing, [paper_run.directory; finished; unfinished])
        path = joinpath(directory, name)
        isfile(path) || continue
        directory == paper_run.directory || println("  ", name, " of run ",
            basename(directory))
        return path
    end
    error("no $(paper_run.fidelity) run has $name")
end

"""
    fidelity_runs(fidelity)

Directories and records of the runs at `fidelity`, latest first.
"""
function fidelity_runs(fidelity)
    runs = Tuple{String, Dict{String, Any}}[]
    isdir(runs_directory) || return runs
    for name in sort(readdir(runs_directory); rev=true)
        path = joinpath(runs_directory, name, "run.toml")
        isfile(path) || continue
        record = TOML.parsefile(path)
        record["fidelity"] == string(fidelity) && push!(runs, (dirname(path), record))
    end
    return runs
end

"""
    is_finished(record)

Whether the run of `record` finished every step it was asked for.
"""
is_finished(record) = !isempty(record["finished"])

"""
    code_hash()

Hash in hex of the source in src/, the scripts and the kite polars.
"""
function code_hash()
    directories = (joinpath(root, "src"), @__DIR__, joinpath(root, "data", "kite_polars"))
    files = [joinpath(directory, name) for directory in directories
             for name in readdir(directory) if endswith(name, r"\.(jl|csv)")]
    return string(hash(join(basename(file) * read(file, String) for file in files));
        base=16)
end

"""
    git_output(arguments...)

Output of git with `arguments` in the repository of the scripts.
"""
git_output(arguments...) = readchomp(`git -C $root $(collect(arguments))`)

"""
    changed_files()

Status lines of the files that differ from the commit, leaving out paper/, where the
figure and table steps write.
"""
changed_files() = split(git_output("status", "--porcelain", "--", ".", ":!paper"), '\n';
    keepempty=false)

"""
    check_final_commit()

Raise an error unless the tree is clean and its commit is on a remote branch.
"""
function check_final_commit()
    changed = changed_files()
    isempty(changed) || error("a final run needs a clean tree; these files differ from ",
        "the commit: ", join(strip.(changed), "; "))
    commit = git_output("rev-parse", "HEAD")
    isempty(git_output("branch", "--remotes", "--contains", commit)) &&
        error("a final run needs a pushed commit; $commit is on no remote branch")
end

"""
    open_run(fidelity, names, resume)

The run to make steps `names` in: the latest unfinished run at `fidelity` if `resume` is
true, or nothing and confirmed on stdin; otherwise, or without one, a new run. A final
run needs a clean tree on a pushed commit.
"""
function open_run(fidelity, names, resume)
    fidelity == :final && check_final_commit()
    runs = filter(run -> !is_finished(last(run)), fidelity_runs(fidelity))
    resumed = !isempty(runs) && resume != false &&
              (resume == true || confirm_resume(first(runs)...))
    code = code_hash()
    directory, record = resumed ? first(runs) : new_run(fidelity, code)
    record["code_hash"] == code || println("code changed since run ", basename(directory),
        " last ran: cases cached by other code will not be reused")
    record["code_hash"] = code
    record["git_commit"] = git_output("rev-parse", "HEAD")
    record["git_branch"] = git_output("rev-parse", "--abbrev-ref", "HEAD")
    record["git_dirty"] = !isempty(changed_files())
    record["requested"] = string.(names)
    run = PaperRun(directory, fidelity, record, 0, 0)
    write_record(run)
    println(resumed ? "resuming" : "new", " run ", directory)
    return run
end

"""
    confirm_resume(directory, record)

Whether the user answers yes on stdin to resuming the run in `directory`.
"""
function confirm_resume(directory, record)
    done = join([step["name"] for step in record["steps"]], ", ")
    print("Resume run ", basename(directory), " (", record["fidelity"], ", started ",
        record["started"], ", done: ", isempty(done) ? "none" : done, ")? [Y/n] ")
    return lowercase(strip(readline())) in ("", "y", "yes")
end

"""
    new_run(fidelity, code)

Directory and record of a new run at `fidelity` of code hash `code`, named by its start
time.
"""
function new_run(fidelity, code)
    started = floor(now(), Second)
    directory = joinpath(runs_directory, Dates.format(started, "yyyy-mm-ddTHHMM"))
    isdir(directory) && error("run $directory exists; start the next one a minute later")
    mkpath(directory)
    record = Dict{String, Any}("fidelity" => string(fidelity),
        "started" => string(started), "finished" => "", "julia" => string(VERSION),
        "code_hash" => code, "requested" => String[],
        "steps" => Dict{String, Any}[])
    return directory, record
end

"""
    write_record(run)

Write the record of `run` to run.toml in its directory, through a temporary file.
"""
function write_record(run)
    path = joinpath(run.directory, "run.toml")
    open(io -> TOML.print(io, run.record; sorted=true), path * ".tmp", "w")
    mv(path * ".tmp", path; force=true)
end

"""
    step_done(run, name)

Whether `run` has finished step `name` and still has every file it wrote.
"""
function step_done(run, name)
    isnothing(run.directory) && return false
    for step in run.record["steps"]
        step["name"] == string(name) || continue
        return all(isfile(joinpath(run.directory, file)) for file in step["files"])
    end
    return false
end

"""
    run_step!(run, name, step)

Run `step` and record its name, start, duration, the files it wrote and, if it computed
round trips, their number and the feasible ones in the record of `run`.
"""
function run_step!(run, name, step)
    println("step ", name)
    run.cases = run.trips = 0
    started, before = floor(now(), Second), file_times(run)
    seconds = round(@elapsed(step()); digits=1)
    println("  ", seconds, " s")
    isnothing(run.directory) && return
    entry = Dict{String, Any}("name" => string(name), "started" => string(started),
        "seconds" => seconds, "files" => first.(setdiff(file_times(run), before)),
        "code_hash" => run.record["code_hash"], "git_commit" => run.record["git_commit"])
    run.cases > 0 && merge!(entry, Dict("cases" => run.cases, "trips" => run.trips))
    filter!(earlier -> earlier["name"] != string(name), run.record["steps"])
    push!(run.record["steps"], entry)
    write_record(run)
end

"""
    file_times(run)

Each data file in the directory of `run` with its modification time; none without one.
"""
function file_times(run)
    isnothing(run.directory) && return Pair{String, Float64}[]
    paths = filter(isfile, readdir(run.directory; join=true))
    return [basename(path) => mtime(path) for path in paths
            if basename(path) != "run.toml"]
end

"""
    finish_run!(run)

Mark `run` finished at the current time in its record.
"""
function finish_run!(run)
    isnothing(run.directory) && return
    run.record["finished"] = string(floor(now(), Second))
    write_record(run)
end

"""
    case_path(case, departures)

Cache file in the run in use of the round trip of `case` over `departures`, named by a
hash of the inputs of the trip and the code hash of the run.
"""
function case_path(case, departures)
    inputs = sort([name => entry.value for (name, entry) in case.assumptions.entries])
    io = IOBuffer()
    serialize(io, (case.design, inputs, case.route, case.scale, case.horizon, departures,
        weather_name, paper_run.record["code_hash"]))
    name = string(hash(String(take!(io))); base=16)
    return joinpath(paper_run.directory, "cases", name * ".bin")
end

"""
    stored_trip(case, departures, path)

Round trip of `case` over `departures` from the cache file `path`, computed and stored
there through a temporary file when missing.
"""
function stored_trip(case, departures, path)
    isfile(path) && return deserialize(path)
    trip = case_trip(case, departures)
    temporary = tempname(dirname(path); cleanup=false)
    serialize(temporary, trip)
    mv(temporary, path; force=true)
    return trip
end
