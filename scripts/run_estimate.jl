# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# What a final and a draft paper run take: the round trips of each data step of the draft
# run with the most steps, scaled to each fidelity, times the core seconds this machine
# takes for a sample of round trips at this commit. Included by cluster.jl for
# `bin/cluster estimate`.

using Printf

"""
Setting of `fidelities` that samples the departures of each data step's round trips, where
it is not `departure_step`; nothing for a step sailing the same departures at every fidelity
"""
step_departure_settings = Dict("sensitivity" => :sensitivity_departure_step,
    "forecast_result" => nothing)

"mean sizes the class study's search routes for a rig on one ship and route"
search_sizes = 3.3

"""
    rig_share(rig)

Share of the cases of the size search of the reference rigs that carry `rig`, "none" for
the ship without one.
"""
rig_share(rig) = (rig == "none" ? 1 : search_sizes) /
                 (1 + search_sizes * length(reference_rigs))

"CPU seconds, user and system, this process has used on all its threads; 64-bit Linux"
function cpu_seconds()
    usage = zeros(Int64, 18)
    ccall(:getrusage, Cint, (Cint, Ptr{Int64}), 0, usage)
    return usage[1] + usage[2] / 1e6 + usage[3] + usage[4] / 1e6
end

"""
    sample_cost(cases, departures)

Core seconds per departure of the round trips of `cases` over `departures`, the ships and
kite pattern tables built beforehand, stored apart from the case store.
"""
function sample_cost(cases, departures)
    foreach(case -> Ship(case.design, case.assumptions), cases)
    start = cpu_seconds()
    compute_trips(cases, [mktempdir() for _ in cases], departures)
    return (cpu_seconds() - start) / (length(cases) * length(departures))
end

"""
    measure_trip_costs()

Core seconds per departure of a sample of round trips on this machine: one case of each
ship class with each rig at the draft's departures (`class`), the 140 m e-ammonia ship to
Guadeloupe with each rig at the final run's departures (`development`), and that ship's
plan sailed live (`live`).
"""
function measure_trip_costs()
    global paper_run = PaperRun(mktempdir(), :draft,
        Dict{String, Any}("git_commit" => git_output("rev-parse", "HEAD"),
            "git_dirty" => true), nothing, Dict{Symbol, Vector{Any}}(), "estimate",
        StepTally())
    sampled(fidelity) = departures[1:fidelities[fidelity].departure_step:end]
    development(rig, area; plan=false) = trip_case(
        ShipDesign(:ammonia, 140.0; rig_size(rig, area)...); route=:caribbean,
        forecast=plan)
    classes = collect(values(ship_classes()))
    rigs = reference_rigs_and_none
    costs = Dict{String, Any}("processor" => processor(), "threads" => Threads.nthreads())
    sample_cost([development("none", 0.0)], departures[1:1])
    for (rig, area) in rigs
        cases = map(enumerate(classes)) do (i, class)
            bounds = rig == "none" ? (0.0, 0.0) : size_bounds(class)[rig]
            class_case(class, study_drives[mod1(i, 2)], rig, sqrt(prod(bounds)),
                route_names[mod1(i, length(route_names))])
        end
        costs["class_$rig"] = sample_cost(cases, sampled(:draft))
        costs["development_$rig"] = sample_cost([development(rig, area)], sampled(:final))
        costs["live_$rig"] = sample_cost([development(rig, area; plan=:live)],
            departures[1:1])
    end
    return costs
end

"""
    trip_costs()

[`measure_trip_costs`](@ref) for this round-trip code on this processor, measured once and
kept in output/estimates/.
"""
function trip_costs()
    name = string(trip_model(script_definitions(script_files())), "-",
        content_hash(processor()), ".toml")
    path = joinpath(mkpath(joinpath(root, "output", "estimates")), name)
    isfile(path) && return TOML.parsefile(path)
    costs = measure_trip_costs()
    open(io -> TOML.print(io, costs), path, "w")
    return costs
end

"""
    weighted_cost(costs, sample)

Core seconds per departure of a round trip of `sample` in `costs`, its rigs weighted by
their [`rig_share`](@ref) in the size search.
"""
weighted_cost(costs, sample) =
    sum(rig_share(rig) * costs["$(sample)_$rig"]
        for rig in ["none"; first.(reference_rigs)])

"""
    step_departures(name, fidelity)

Departures each round trip of data step `name` sails over at `fidelity`.
"""
function step_departures(name, fidelity)
    setting = get(step_departure_settings, name, :departure_step)
    isnothing(setting) && return 1
    return length(departures[1:getproperty(fidelities[fidelity], setting):end])
end

"""
    run_counts(record)

For each data step of the draft run `record` with round trips: its name and its cases,
the same at every fidelity.
"""
run_counts(record) = [(name=step["name"], cases=step["cases"])
                      for step in record["steps"] if haskey(step, "cases")]

"""
    counted_run(runs)

The finished run of `runs`, newest first, with the most data steps; the newest of equals.
"""
counted_run(runs) = argmax(run -> count(haskey.(last(run)["steps"], "cases")),
    filter(run -> is_finished(last(run)), runs))

"""
    cost_line(costs)

The core seconds per departure of each sample in `costs`, by sample name.
"""
cost_line(costs) = join([@sprintf("%s %.0f", key, value)
                         for (key, value) in sort(collect(costs); by=first)
                         if value isa Number && key != "threads"], ", ")

"""
    print_estimate(; box_cores=20)

Print what a final and a draft run take in core hours on this machine and in days on the
cluster's jobs of cluster.toml, on one of those jobs alone, and on `box_cores` cores here,
from the cases of the [`counted_run`](@ref) of the draft runs and [`trip_costs`](@ref): the
class study at the class sample, the forecast result at the mean of its plan sailed live and
with perfect foresight, every other step between the development and the class sample.
"""
function print_estimate(; box_cores=20)
    directory, record = counted_run(fidelity_runs(:draft))
    costs = trip_costs()
    settings = cluster_settings()
    println("cases of draft run ", basename(directory), "; core seconds per departure on ",
        costs["processor"], ": ", cost_line(costs))
    cost(sample) = weighted_cost(costs, sample)
    between = extrema(cost.(("class", "development")))
    forecast = (cost("live") + cost("development")) / 2
    for fidelity in (:final, :draft)
        @printf("\n%s run\n%-20s %8s %12s %12s\n", fidelity, "step", "cases",
            "departures", "core hours")
        hours = zeros(2)
        for (name, cases) in run_counts(record)
            trips = cases * step_departures(name, fidelity)
            low, high = name == "forecast_result" ? (forecast, forecast) :
                        name == "classes" ? (cost("class"), cost("class")) : between
            step_hours = trips .* (low, high) ./ 3600
            hours .+= step_hours
            @printf("%-20s %8.0f %12.0f %5.0f to %5.0f\n", name, cases, trips,
                step_hours...)
        end
        @printf("%-20s %34.0f to %5.0f\n", "total", hours...)
        for (place, cores) in (("cluster, jobs of cluster.toml",
                                   settings["jobs"] * settings["cores"]),
            ("cluster, one job", settings["cores"]), ("$box_cores cores here", box_cores))
            @printf("  on %-32s %5.1f to %5.1f days\n", place, (hours ./ cores ./ 24)...)
        end
    end
end
