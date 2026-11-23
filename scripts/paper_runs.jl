# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Runs of the paper: each data-making call of `paper` keeps its data files and its record
# run.toml in output/runs/<start time>/, and every round trip it computes in the case store
# output/cases/ that all runs share, so that a run cut short resumes where it stopped and
# a rerun computes only the round trips a change touched. Included by paper.jl.
using Base.ScopedValues: ScopedValue, with
using Dates
using Serialization
using TOML
using WindShipOpt: inputs_read

include("step_code.jl")
include("case_jobs.jl")

"""
Settings of each fidelity of the paper: the corridor scale, the step between sampled
departures and that step in the sensitivity study.
"""
fidelities = Dict(
    :draft => (corridor_scale=1.0, departure_step=36, sensitivity_departure_step=12),
    :final => (corridor_scale=1.0, departure_step=6, sensitivity_departure_step=6))

"""
Spread of a draft result about the final run's on the 140 m e-ammonia ship to Guadeloupe,
one standard deviation [percentage points]: of the kite's and the rotors' cost savings and
of the kite's lead over the rotors
"""
DRAFT_SPREAD = (kite=4.9, rotors=3.7, gap=2.8)

"text of the paper's draft marker: what a draft run leaves out and how far it may lie off"
function draft_marker()
    ratio = fidelities[:draft].departure_step ÷ fidelities[:final].departure_step
    kite, rotors, gap = round.(Int, values(DRAFT_SPREAD))
    illustrative_saving = 23
    return "\\tbd{These are draft results from a quick run on one in $ratio of the " *
           "final run's departures. On the 140\\,m e-ammonia ship to Guadeloupe, two " *
           "times in three a draft cost saving lies within $kite percentage points of " *
           "the final run's for the kite and $rotors for the rotors, as often above as " *
           "below, so a $illustrative_saving\\,\\% kite saving may read " *
           "$(illustrative_saving - kite) to $(illustrative_saving + kite)\\,\\%. The " *
           "kite's lead over the rotors lies within $gap percentage points of the final " *
           "run's lead, so a smaller lead between two rigs is not yet settled.}\n"
end

"""
    mark_fidelity(path, fidelity, steps, figures)

Keep the paper's draft marker at `path` true of its `figures`: a draft call drawing any of
them sets it, a final call drawing them all clears it, and any other call of `steps` leaves
it alone.
"""
function mark_fidelity(path, fidelity, steps, figures)
    drawn = intersect(steps, figures)
    if fidelity == :final
        issetequal(drawn, figures) && write(path, "")
    elseif !isempty(drawn)
        write(path, draft_marker())
    end
end

"""
    number_macro(name, text, draft)

LaTeX definition of the macro `\\Num<name>` that prints `text`, marked as a draft result
where `draft` is true.
"""
number_macro(name, text, draft) = string("\\newcommand{\\Num", name, "}{",
    draft ? "\\tbd{$text}" : text, "}\n")

"directory with one directory per run, named by the time the run started"
runs_directory = normpath(joinpath(root, "output", "runs"))

"directory of the round trips every run stores and reuses, one directory per case"
cases_directory = normpath(joinpath(root, "output", "cases"))

"""
    StepTally

What the step in progress computed and rests on, for its entry in run.toml.
"""
mutable struct StepTally
    "feasible round trips"
    trips::Int
    "cases kept from code older than the run's"
    older::Int
    "cases carrying the labels of the run's `only`"
    sliced::Int
    "each case's labels, store directory, commit, dirty tree, round-trip code and processor"
    made::Vector{NamedTuple}
    "names of the inputs its round trips read"
    inputs::Set{Symbol}
    "data files it read, each with its content hash and run"
    reads::Dict{String, Dict{String, String}}
    "content hash of each data file read, by name"
    file_hashes::Dict{String, String}
    "lock guarding the tally against the threads of a step"
    lock::ReentrantLock
end

StepTally() = StepTally(0, 0, 0, NamedTuple[], Set{Symbol}(),
    Dict{String, Dict{String, String}}(), Dict{String, String}(), ReentrantLock())

"""
    PaperRun

A call of `paper`, with the code it runs and the tally of the step in progress.
"""
mutable struct PaperRun
    "directory of the run; nothing when only figure and table steps run"
    directory::Union{Nothing, String}
    "fidelity of the run, a key of `fidelities`"
    fidelity::Symbol
    "contents of run.toml"
    record::Dict{String, Any}
    "labels a case must carry to be computed with the run's code, or nothing for every case"
    only::Union{Nothing, NamedTuple}
    "top-level definitions of the scripts ([`script_definitions`](@ref))"
    definitions::Dict{Symbol, Vector{Any}}
    "hash of the code a round trip runs ([`trip_model`](@ref))"
    trip_model::String
    "what the step in progress computed and read"
    tally::StepTally
    "directory of the run read before any other, or nothing"
    source::Union{Nothing, String}
end

"the run in `directory` with nothing read before it"
PaperRun(directory, fidelity, record, only, definitions, trip_model, tally) =
    PaperRun(directory, fidelity, record, only, definitions, trip_model, tally, nothing)

"""
    PaperRun(fidelity; source=nothing)

A run at `fidelity` with no directory, for figure and table steps alone, reading the run
named `source` first where one is given.
"""
function PaperRun(fidelity; source=nothing)
    directory = isnothing(source) ? nothing : joinpath(runs_directory, source)
    record = isnothing(directory) ? Dict{String, Any}() :
             TOML.parsefile(joinpath(directory, "run.toml"))
    return PaperRun(nothing, fidelity, record, nothing, Dict{Symbol, Vector{Any}}(), "",
        StepTally(), directory)
end

"the run in use, set by `paper`"
paper_run = nothing

"""
    run_settings()

Settings of [`fidelities`](@ref) at the fidelity of the run in use.
"""
run_settings() = fidelities[paper_run.fidelity]

"""
    sampled_departures()

The departures the studies average over: every `departure_step`-th one of the run's
fidelity.
"""
sampled_departures() = departures[1:run_settings().departure_step:end]

"""
    sensitivity_departures()

The departures the sensitivity study averages over: every `sensitivity_departure_step`-th
one of the run's fidelity.
"""
sensitivity_departures() = departures[1:run_settings().sensitivity_departure_step:end]

"""
    run_corridors(name)

Outbound and return corridors of route `name` at the corridor scale of the run in use.
"""
run_corridors(name) = corridors(name, run_settings().corridor_scale)

"""
    run_file(name)

Path in the directory of the run in use of the data file `name` a step writes; forgets the
content hash the step in progress found for it.
"""
function run_file(name)
    @lock paper_run.tally.lock delete!(paper_run.tally.file_hashes, name)
    return joinpath(paper_run.directory, name)
end

"the data files a round trip computing in this task has read, or nothing outside one"
files_read_scope = ScopedValue{Union{Nothing, Dict{String, String}}}(nothing)

"""
    data_file(name)

Path of the data file `name` a step reads: in the run in use, else in the latest finished
run of its fidelity that has it, this branch's before any other's, else in the latest
unfinished one. Records the file and its content hash as read by the step in progress and
by the round trip computing.
"""
function data_file(name)
    path = resolved_data_file(name)
    directory = dirname(path)
    directory == paper_run.directory || println("  ", name, " of run ", basename(directory))
    tally = paper_run.tally
    trip_files = files_read_scope[]
    @lock tally.lock begin
        tally.reads[name] = Dict("hash" => read_hash(name), "run" => basename(directory))
        isnothing(trip_files) || (trip_files[name] = read_hash(name))
    end
    return path
end

"""
    read_hash(name)

Content hash of the data file `name` as [`resolved_data_file`](@ref) finds it, found once
per step until it writes the file ([`run_file`](@ref)).
"""
read_hash(name) = @lock paper_run.tally.lock get!(paper_run.tally.file_hashes, name) do
    file_hash(resolved_data_file(name))
end

"""
    resolved_data_file(name)

Path [`data_file`](@ref) gives for `name`, without recording it.
"""
function resolved_data_file(name)
    for (directory, _) in reading_order()
        path = joinpath(directory, name)
        isfile(path) && return path
    end
    error("no $(paper_run.fidelity) run has $name")
end

"""
    reading_order()

Directories and records of the runs data are read from, in the order they are looked in:
the run in use or its source, then the finished runs of its fidelity, this branch's before
any other's, latest first, then the unfinished ones.
"""
function reading_order()
    branch = git_output("rev-parse", "--abbrev-ref", "HEAD")
    runs = sort(fidelity_runs(paper_run.fidelity);
        by=run -> get(last(run), "git_branch", "") != branch)
    directory = something(paper_run.directory, paper_run.source, missing)
    current = ismissing(directory) ? [] : [(directory, paper_run.record)]
    return [current; filter(is_finished ∘ last, runs);
            filter(!is_finished ∘ last, runs)]
end

"""
    latest_step(name)

Directory of the run and entry of step `name` whose data files are read, the first in
[`reading_order`](@ref) holding every file the step wrote, or nothing.
"""
function latest_step(name)
    for (directory, record) in reading_order()
        entry = step_entry(record, name)
        isnothing(entry) && continue
        all(isfile(joinpath(directory, file)) for file in entry["files"]) &&
            return directory, entry
    end
    return nothing
end

"""
    file_hash(path)

Hash in hex of the contents of the file at `path`.
"""
file_hash(path) = content_hash(read(path, String))

"record of the run each method study's tables and figures come from"
study_runs_path = joinpath(root, "paper", "study_runs.toml")

"""
    study_file(study, name)

Path of the data file `name` of method study `study` in the run recorded for it in
paper/study_runs.toml.
"""
study_file(study, name) =
    joinpath(runs_directory, TOML.parsefile(study_runs_path)[string(study)]["run"], name)

"""
    record_study(study)

Record the run in use, its fidelity and the commit of its step `study` as the run of
method study `study` in paper/study_runs.toml, and write [`study_sources`](@ref).
"""
function record_study(study)
    step = only(filter(step -> step["name"] == string(study), paper_run.record["steps"]))
    runs = TOML.parsefile(study_runs_path)
    runs[string(study)] = Dict("run" => basename(paper_run.directory),
        "fidelity" => string(paper_run.fidelity), "commit" => step["git_commit"])
    open(io -> TOML.print(io, runs; sorted=true), study_runs_path, "w")
    study_sources(runs)
end

"""
    study_sources(runs)

Write to paper/sections/study_runs.tex, for each method study in `runs`, the run, fidelity
and commit it comes from, as the `\\studyrunis` definitions captions read.
"""
function study_sources(runs)
    open(joinpath(sections, "study_runs.tex"), "w") do io
        for (study, run) in sort(collect(runs); by=first)
            println(io, "\\studyrunis{", study, "}{",
                run_words(run["run"], run["fidelity"], run["commit"]), "}")
        end
    end
end

"""
    run_words(run, fidelity, commit)

The run `run`, its `fidelity` and the short hash of `commit` as the paper names them.
"""
run_words(run, fidelity, commit) =
    string("run ", run, " at ", fidelity, " fidelity, commit ", first(commit, 7))

"""
    results_run_words()

[`run_words`](@ref) of the run whose class study the results read.
"""
function results_run_words()
    directory, record = results_run()
    commit = step_entry(record, "classes")["git_commit"]
    return run_words(basename(directory), record["fidelity"], commit)
end

"""
    counts_by_score(record)

Whether the run of `record` picked the number of each deck rig's units by the layout score:
whether its class step read the score's mean wind.
"""
counts_by_score(record) =
    haskey(step_entry(record, "classes")["inputs"], "layout_mean_wind")

"""
    results_count_bias()

The [`rotor_count_bias`](@ref) where the run whose class study the results read picked the
number of rotors by the layout score ([`counts_by_score`](@ref)); else zero.
"""
results_count_bias() = counts_by_score(last(results_run())) ? rotor_count_bias : 0.0

"""
    results_run()

Directory and record of the run whose class study the results read.
"""
function results_run()
    directory = dirname(resolved_data_file("classes.csv"))
    return directory, TOML.parsefile(joinpath(directory, "run.toml"))
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
    files_in(directories...)

Paths of the Julia and CSV files directly in `directories`.
"""
files_in(directories...) = [joinpath(directory, name) for directory in directories
                            for name in readdir(directory) if endswith(name, r"\.(jl|csv)")]

"""
    code_files()

Paths of the source in src/, the scripts, the data tables and the kite polars.
"""
code_files() = files_in(joinpath(root, "src"), @__DIR__, joinpath(root, "data"),
    joinpath(root, "data", "kite_polars"))

"""
    model_files()

Paths of what every step and round trip runs on: the source in src/, the data tables, the
kite polars, the weather and corridor setup and the package versions.
"""
model_files() = [files_in(joinpath(root, "src"), joinpath(root, "data"),
    joinpath(root, "data", "kite_polars")); joinpath(@__DIR__, "setup.jl");
    joinpath(root, "Manifest-v$(VERSION.major).$(VERSION.minor).toml.default");
    joinpath(@__DIR__, "Manifest-v$(VERSION.major).$(VERSION.minor).toml.default")]

"""
    file_contents(files)

The name of each of `files` with its contents.
"""
file_contents(files) = [basename(file) => read(file, String) for file in files]

"""
    code_hash()

Hash in hex of the contents of [`code_files`](@ref).
"""
code_hash() = content_hash(file_contents(code_files()))

"""
    model_hash()

Hash in hex of the contents of [`model_files`](@ref) and the Julia version.
"""
model_hash() = content_hash((file_contents(model_files()), VERSION))

"""
    script_files()

Paths of the Julia scripts, whose definitions steps reach.
"""
script_files() = filter(endswith(".jl"), readdir(@__DIR__; join=true))

"""
    step_code(definitions, step)

The code step function `step` runs: `"model"` with the [`model_hash`](@ref), and each
definition of `definitions` it reaches with the hash of its expressions.
"""
step_code(definitions, step) =
    merge(Dict("model" => model_hash()), code_hashes(definitions, [nameof(step)]))

"""
    trip_model(definitions)

Hash in hex of the code of a round trip: the [`model_hash`](@ref) and the definitions of
`definitions` that [`trip_case`](@ref) and [`case_trip`](@ref) reach.
"""
trip_model(definitions) = string(hash((model_hash(),
    sort(collect(code_hashes(definitions, [:trip_case, :case_trip]))))); base=16)

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
    open_run(fidelity, names, resume; only=nothing)

The run to make steps `names` in: the latest unfinished run at `fidelity` on this git branch
if `resume` is true, or nothing and confirmed on stdin; otherwise, or without one, a new
run. A final run needs a clean tree on a pushed commit and computes every case; a draft
computes with its code only the cases whose labels match `only`, where given.
"""
function open_run(fidelity, names, resume; only=nothing)
    if fidelity == :final
        isnothing(only) || throw(ArgumentError("a final run computes every case"))
        check_final_commit()
    end
    branch = git_output("rev-parse", "--abbrev-ref", "HEAD")
    runs = filter(run -> !is_finished(last(run)) && last(run)["git_branch"] == branch,
        fidelity_runs(fidelity))
    resumed = !isempty(runs) && resume != false &&
              (resume == true || confirm_resume(first(runs)...))
    code = code_hash()
    directory, record = resumed ? first(runs) : new_run(fidelity, code)
    record["code_hash"] = code
    record["julia"] = string(VERSION)
    record["git_commit"] = git_output("rev-parse", "HEAD")
    record["git_branch"] = branch
    record["git_dirty"] = !isempty(changed_files())
    record["requested"] = union(record["requested"], string.(names))
    definitions = script_definitions(script_files())
    run = PaperRun(directory, fidelity, record, only, definitions,
        trip_model(definitions), StepTally())
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
        "started" => string(started), "finished" => "", "code_hash" => code,
        "requested" => String[], "steps" => Dict{String, Any}[])
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
    entry = step_entry(run.record, name)
    return !isnothing(entry) &&
           all(isfile(joinpath(run.directory, file)) for file in entry["files"])
end

"""
    step_entry(record, name)

The entry of step `name` in run record `record`, or nothing.
"""
function step_entry(record, name)
    index = findfirst(step -> step["name"] == string(name), get(record, "steps", []))
    return isnothing(index) ? nothing : record["steps"][index]
end

"""
    run_step!(run, name, step)

Run `step` and record in the record of `run` its name, start, duration, the files it wrote,
the commit, the Julia version and the code it ran ([`step_code`](@ref)), the base value of
every input it read and the data files it read; and, where it computed round trips, their
number, the feasible ones, the code of a round trip, the commits and processors that
computed them, how many are kept from older code and the list of them
([`write_cases`](@ref)). Raise an error where the run has an `only` that none of the step's
round trips carries.
"""
function run_step!(run, name, step)
    println("step ", name)
    run.tally = StepTally()
    started, before = floor(now(), Second), file_times(run)
    seconds = round(@elapsed((_, names) = inputs_read(step)); digits=1)
    println("  ", seconds, " s")
    isnothing(run.directory) && return
    tally = run.tally
    cases = length(tally.made)
    isnothing(run.only) || cases == 0 || tally.sliced > 0 ||
        throw(ArgumentError("no case of step $name carries the labels only=$(run.only)"))
    entry = Dict{String, Any}("name" => string(name), "started" => string(started),
        "seconds" => seconds, "files" => first.(setdiff(file_times(run), before)),
        "code_hash" => run.record["code_hash"], "git_commit" => run.record["git_commit"],
        "git_dirty" => run.record["git_dirty"], "julia" => string(VERSION),
        "code" => step_code(run.definitions, step),
        "inputs" => Dict(string(input) => assumptions[input]
                         for input in union(names, tally.inputs)),
        "reads" => tally.reads)
    cases > 0 && merge!(entry, Dict("cases" => cases, "trips" => tally.trips,
        "trip_model" => run.trip_model,
        "case_commits" => counts(commit_label(made.commit, made.dirty)
                                 for made in tally.made),
        "case_processors" => counts(made.processor for made in tally.made),
        "older_cases" => tally.older,
        "case_record" => write_cases(run, name, tally.made)))
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

Mark `run` finished at the current time in its record, once every step asked of it is done.
"""
function finish_run!(run)
    isnothing(run.directory) && return
    all(name -> step_done(run, name), run.record["requested"]) || return
    run.record["finished"] = string(floor(now(), Second))
    write_record(run)
end

"""
    case_directory(case, departures)

Directory in the case store of the round trips of `case` over `departures`, named by a hash
of the inputs of the trip other than its assumptions and the code.
"""
case_directory(case, departures) = joinpath(cases_directory,
    content_hash((case.design, case.route, case.scale, case.course, case.forecast,
        case.held_knots, case.part, departures, weather_name)))

"""
    in_slice(case, only)

Whether `case` carries every label of `only` at one of its given values, compared as text.
"""
in_slice(case, only) = isnothing(only) || all(pairs(only)) do (label, values)
    hasproperty(case, label) &&
        string(getproperty(case, label)) in string.(values isa Tuple ? values : (values,))
end

"""
    stored_entry(directory, case)

Entry of the case store `directory` the run in use takes for `case`, or `missing`: one its
code computed under the values of `case.assumptions` in every input it read and from the
data files it read as they are now, and of its commit, a clean tree and this processor in a
final run. In a draft, a case outside its `only` takes the latest such entry of any code
where none is.
"""
function stored_entry(directory, case)
    isdir(directory) || return missing
    entries = [deserialize(file) for file in readdir(directory; join=true)
               if endswith(file, ".bin")]
    filter!(entry -> reads_unchanged(entry, case), entries)
    current = filter(entry -> entry.model == paper_run.trip_model, entries)
    if paper_run.fidelity == :final
        filter!(entry -> entry.commit == paper_run.record["git_commit"] && !entry.dirty &&
                         entry.processor == processor(), current)
    end
    isempty(current) || return first(current)
    (paper_run.fidelity == :final || in_slice(case, paper_run.only)) && return missing
    isempty(entries) && return missing
    return entries[argmax([entry.made for entry in entries])]
end

"""
    reads_unchanged(entry, case)

Whether every input the stored `entry` read is still an input of `case.assumptions` with
the same value, and every data file it read has the same contents now.
"""
reads_unchanged(entry, case) =
    all(haskey(case.assumptions, name) && case.assumptions[name] == value
        for (name, value) in entry.inputs) &&
    all(read_hash(name) == hash for (name, hash) in entry.files)

"""
    stored_trip(compute, directory, case)

Round trip `compute()` returns for `case`, stored in the case store `directory` through a
temporary file with the values in `case.assumptions` of the inputs it read, the data files
it read, the seconds it took, the code that computed it, its commit and processor.
"""
function stored_trip(compute, directory, case)
    files = Dict{String, String}()
    seconds = @elapsed (trip, names) = with(() -> inputs_read(compute),
        files_read_scope => files)
    inputs = sort([name => case.assumptions[name] for name in names])
    record = paper_run.record
    entry = (; inputs, files=sort(collect(files)), trip, seconds,
        model=paper_run.trip_model, commit=record["git_commit"], dirty=record["git_dirty"],
        processor=processor(), made=now())
    mkpath(directory)
    temporary = tempname(directory; cleanup=false)
    serialize(temporary, entry)
    mv(temporary, entry_file(directory, entry); force=true)
    return entry
end

"""
    entry_file(directory, entry)

File of the case store `directory` holding `entry`, named by its code and a hash of the
inputs and data files it read, its commit, dirty flag and processor.
"""
entry_file(directory, entry) = joinpath(directory, string(entry.model, "-",
    content_hash((entry.inputs, entry.files, entry.commit, entry.dirty, entry.processor)),
    ".bin"))

"model name of the processor this process runs on"
processor() = strip(Sys.cpu_info()[1].model)

"""
    tally_case!(case, directory, entry)

Count in the tally of the step in progress the stored round-trip `entry` it uses for `case`
from the case store `directory`, and list what made it.
"""
function tally_case!(case, directory, entry)
    tally = paper_run.tally
    made = (case=case_labels(case), store=basename(directory), entry.commit, entry.dirty,
        trip_model=entry.model, entry.processor)
    @lock tally.lock begin
        tally.trips += !isnothing(entry.trip)
        tally.older += entry.model != paper_run.trip_model
        tally.sliced += in_slice(case, paper_run.only)
        push!(tally.made, made)
        union!(tally.inputs, first.(entry.inputs))
    end
end

"""
    case_labels(case)

Each label of `case` with its value, as `label=value` separated by spaces: the fields of its
[`trip_case`](@ref) but the design, assumptions, corridor scale and corridors.
"""
case_labels(case) = join([string(label, "=", value) for (label, value) in pairs(case)
                          if !(label in (:design, :assumptions, :scale, :corridors))], " ")

"""
    commit_label(commit, dirty)

`commit`, with `-dirty` appended where `dirty`, the tree differing from it.
"""
commit_label(commit, dirty) = dirty ? commit * "-dirty" : commit

"""
    counts(values)

Each distinct one of `values` with how often it occurs.
"""
function counts(values)
    tally = Dict{String, Int}()
    for value in values
        tally[value] = get(tally, value, 0) + 1
    end
    return tally
end

"""
    csv_field(text)

`text` as a quoted CSV field.
"""
csv_field(text) = string('"', replace(text, '"' => "\"\""), '"')

"""
    write_cases(run, name, made)

Write to cases/`name`.csv in the directory of `run` a line for each round trip of `made`
([`StepTally`](@ref)) and return its path in the run.
"""
function write_cases(run, name, made)
    path = joinpath("cases", "$name.csv")
    mkpath(joinpath(run.directory, "cases"))
    open(joinpath(run.directory, path), "w") do io
        println(io, "case,store,commit,dirty,trip_model,processor")
        for row in sort(made; by=values)
            println(io, join(csv_field.(string.(values(row))), ","))
        end
    end
    return path
end

"""
    trip_seconds(case, departures)

Seconds [s] the round trip of `case` over `departures` in the case store took to compute.
"""
trip_seconds(case, departures) =
    stored_entry(case_directory(case, departures), case).seconds

"""
    step_reasons(entry, code)

Why the step of run-record `entry` is out of date against the code `code` it would run now
([`step_code`](@ref)): each a line naming the code, inputs or data files that changed since
it ran, or the round trips it kept from older code; none where it is current.
"""
function step_reasons(entry, code)
    haskey(entry, "code") || return ["made before runs recorded their code"]
    reasons = String[]
    changed = sort([name for name in union(keys(code), keys(entry["code"]))
                    if get(code, name, "") != get(entry["code"], name, "")])
    "model" in changed &&
        push!(reasons, "the model changed: src/, data/, setup.jl or the packages")
    others = setdiff(changed, ["model"])
    isempty(others) || push!(reasons, "its code changed: " * join(others, ", "))
    inputs = sort([name for (name, value) in entry["inputs"]
                   if !haskey(assumptions.entries, Symbol(name)) ||
                      assumptions[Symbol(name)] != value])
    isempty(inputs) || push!(reasons, "inputs changed: " * join(inputs, ", "))
    for (file, read) in sort(collect(entry["reads"]); by=first)
        now_read = try
            resolved_data_file(file)
        catch
            nothing
        end
        if isnothing(now_read)
            push!(reasons, "no run has $file, which it reads")
        elseif file_hash(now_read) != read["hash"]
            push!(reasons, "$file changed: run $(basename(dirname(now_read))) has another")
        end
    end
    older = get(entry, "older_cases", 0)
    older > 0 && push!(reasons, "$older round trips kept from older code")
    return reasons
end

"""
    step_location(name)

Directory of the run and run-record entry of the data the paper reads from step `name`: of
the run paper/study_runs.toml names for a method study, else [`latest_step`](@ref).
"""
function step_location(name)
    studies = TOML.parsefile(study_runs_path)
    haskey(studies, string(name)) || return latest_step(name)
    directory = joinpath(runs_directory, studies[string(name)]["run"])
    path = joinpath(directory, "run.toml")
    entry = isfile(path) ? step_entry(TOML.parsefile(path), name) : nothing
    return isnothing(entry) ? nothing : (directory, entry)
end

"""
    spread_staleness!(reasons, found, makers)

Add to `reasons` of each step that reads a data file whose maker in `makers` is out of date
a reason naming it, until no step changes.
"""
function spread_staleness!(reasons, found, makers)
    spreading = true
    while spreading
        spreading = false
        for (name, location) in found
            (isnothing(location) || !isempty(reasons[name])) && continue
            for file in keys(get(last(location), "reads", Dict()))
                maker = get(makers, file, name)
                (maker == name || isempty(reasons[maker])) && continue
                push!(reasons[name], "reads $file of $maker, which is out of date")
                spreading = true
            end
        end
    end
end

"""
    print_status(name, location, reasons, current_trips)

Print the line of step `name` of [`paper_status`](@ref): its run, commit and time, and its
`reasons` with whether its round trips recompute under the round-trip code `current_trips`.
"""
function print_status(name, location, reasons, current_trips)
    if isnothing(location)
        println(rpad(name, 22), "out of date: ", only(reasons))
        return
    end
    directory, entry = location
    hours = round(entry["seconds"] / 3600; digits=1)
    println(rpad(name, 22), isempty(reasons) ? "current" : "out of date", ", run ",
        basename(directory), " at ", first(entry["git_commit"], 7),
        get(entry, "git_dirty", false) ? " (dirty)" : "", ", ", hours, " h")
    foreach(reason -> println(" "^24, reason), reasons)
    isempty(reasons) || !haskey(entry, "trip_model") ||
        println(" "^24, entry["trip_model"] == current_trips ?
                        "its round trips are stored but for those reading what changed" :
                        "its $(entry["cases"]) round trips recompute")
end

"""
    part_commits(locations)

The commits that made the steps at `locations`, each a run directory and run-record entry,
and their round trips, with `-dirty` appended where the tree differed from the commit.
"""
function part_commits(locations)
    commits = Set{String}()
    for (_, entry) in locations
        push!(commits, commit_label(entry["git_commit"], get(entry, "git_dirty", false)))
        union!(commits, keys(get(entry, "case_commits", Dict())))
    end
    return sort(collect(commits))
end

"""
    print_commits(commits)

Print whether `commits` ([`part_commits`](@ref)) are one clean commit, or which they are.
"""
function print_commits(commits)
    if isempty(commits)
        println("no step has data at this fidelity")
    elseif length(commits) == 1 && !endswith(only(commits), "-dirty")
        println("every part comes from clean commit ", only(commits))
    else
        println("not one clean commit: parts come from ", join(commits, ", "))
    end
end
