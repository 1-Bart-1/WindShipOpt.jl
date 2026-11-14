# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Accuracy gate of the planner: routes cases departure by departure at a planner fidelity
# and compares each rig's cost saving against the same ship without a rig with the saving
# extrapolated from it and a reference run, by the repository's accuracy-for-speed standard.
#
#   julia +1.12 --project=. -t auto scripts/router_gate.jl [--reference] <out_dir> \
#       [reference_dir]
#
# Runs `gate_cases` at the default fidelity into <out_dir>/gate.csv, a line per departure of
# each finished case, and its CPU time into <out_dir>/times.csv; a rerun routes only the
# cases missing there. `--reference` routes on a grid twice as fine. Given a reference
# directory, it prints each rig's saving against the saving extrapolated from the two and
# exits 1 where the standard fails.
using Printf, Statistics
include(joinpath(@__DIR__, "setup.jl"))

"largest change of a rig's saving against the reference that passes [points]"
SAVING_TOLERANCE = 3.0

"largest change of the gap between two rigs' savings against the reference that passes
[points]"
GAP_TOLERANCE = 1.0

"first line of a gate file"
GATE_HEADER = "ship,rig,route,departure,cost,fuel,flight"

"departures of the gate: every sixth of the paper's, twelve on ERA5"
gate_departures() = departures[1:6:end]

"""
    planner_fidelity(factor=1; scale=1, settings=RouterSettings())

Corridor scale and router settings of the planner `factor` times as fine as `scale` and
`settings` in every spacing and step: stage and row spacing, and with them the far stages',
time bins, weather samples along edges and the cost to go's knots, with `factor` times as
many speeds.
"""
function planner_fidelity(factor=1; scale=1, settings=WindShipOpt.RouterSettings())
    finer(name) = getfield(settings, name) / factor
    steps = (:edge_sample_hours, :time_step, :to_go_step, :final_time_step,
        :weighed_final_time_step, :to_go_sample_hours, :far_sample_hours)
    speeds = round(Int, (settings.routing_speeds - 1) * factor) + 1
    return (; scale=scale / factor,
        settings=WindShipOpt.with_changed(settings; routing_speeds=speeds,
            (name => finer(name) for name in steps)...))
end

"`ShipDesign` of the gate's ship `ship` with `rig` of the size `sizes` gives it"
function gate_design(ship, rig, sizes)
    hull = ship == "140m" ? 140.0 : ship_classes()["Kamsarmax bulk carrier"]
    rig == "none" && return ShipDesign(:ammonia, hull)
    keyword = Dict("kite" => :kite_area, "wings" => :wing_area,
        "rotors" => :rotor_area)[rig]
    return ShipDesign(:ammonia, hull; NamedTuple{(keyword,)}((sizes[rig],))...)
end

"rig sizes of the gate's ships [m^2]"
gate_sizes = Dict("140m" => Dict("kite" => 3200.0, "wings" => 1500.0, "rotors" => 800.0),
    "kamsarmax" => Dict("kite" => 3200.0, "wings" => 3000.0, "rotors" => 1600.0))

"cases of each (ship, route, rigs), each a NamedTuple of ship, rig, route and design"
gate_case_list(entries) =
    [(; ship, rig, route, design=gate_design(ship, rig, gate_sizes[ship]))
     for (ship, route, rigs) in entries for rig in rigs]

"""
    development_cases()

The 140 m e-ammonia ship to Guadeloupe without a rig, with a kite and with rotors, on which
every planner setting is chosen.
"""
development_cases() = gate_case_list([("140m", :caribbean, ("none", "kite", "rotors"))])

"""
    gate_cases()

The full check: every rig on the 140 m e-ammonia ship to Guadeloupe, to Houston, whose
approach through the Florida Strait is the hardest, to New York and to Bilbao, whose short
crossing only the floor on open-ocean stages gives a grid, and on an e-ammonia Kamsarmax to
Tubarão.
"""
function gate_cases()
    every_rig = ("none", "kite", "wings", "rotors")
    return gate_case_list([("140m", route, every_rig)
                           for route in (:caribbean, :houston, :new_york, :bilbao)]) ∪
           gate_case_list([("kamsarmax", :tubarao, every_rig)])
end

"CPU time this process has used, over all its threads [s]"
cpu_seconds() = sum(parse.(Float64, split(read("/proc/self/stat", String))[14:15])) / 100

"""
    gate_trips(out_dir, cases, fidelity)

Route the round trip over the [`gate_departures`](@ref) of each of `cases` not yet in
`out_dir`/gate.csv at `fidelity`, threaded, adding a line per departure as its case
finishes, and the CPU time of the cases routed to `out_dir`/times.csv.
"""
function gate_trips(out_dir, cases, fidelity)
    mkpath(out_dir)
    path, times = joinpath(out_dir, "gate.csv"), joinpath(out_dir, "times.csv")
    isfile(path) || write(path, GATE_HEADER * "\n")
    isfile(times) || write(times, "cases,wall_seconds,cpu_seconds\n")
    finished = Set((row.ship, row.rig, row.route) for row in read_gate(path))
    waiting = filter(case -> (case.ship, case.rig, String(case.route)) ∉ finished, cases)
    isempty(waiting) && return
    sampled = gate_departures()
    for case in waiting
        case.design.kite_area > 0 && Ship(case.design, assumptions)
        corridors(case.route, fidelity.scale)
    end
    file_lock = ReentrantLock()
    cpu = cpu_seconds()
    wall = @elapsed WindShipOpt.with_router_settings(fidelity.settings) do
        Threads.@threads :greedy for case in waiting
            ship = Ship(case.design, assumptions)
            trip = isnothing(ship) ? nothing : round_trip(ship,
                corridors(case.route, fidelity.scale)..., weather, sampled, assumptions)
            lines = gate_lines(case, trip, sampled)
            lock(() -> open(io -> foreach(line -> println(io, line), lines), path, "a"),
                file_lock)
        end
    end
    line = join((length(waiting), round(wall; digits=1), round(cpu_seconds() - cpu;
            digits=1)), ",")
    open(io -> println(io, line), times, "a")
end

"""
    gate_lines(case, trip, sampled)

A line of a gate file per departure of `sampled` for `case`, `trip` being `nothing` where
it is infeasible.
"""
function gate_lines(case, trip, sampled)
    labels = (case.ship, case.rig, case.route)
    isnothing(trip) && return [join((labels..., departure, "NA", "NA", "NA"), ",")
                               for departure in sampled]
    return [join((labels..., outcome.departure, outcome.cost_per_tonne_km,
                outcome.fuel_per_tonne_km, outcome.flight_share), ",")
            for outcome in trip.departures]
end

"""
    read_gate(path)

The rows of the gate file `path`, each with its ship, rig, route, departure [h] and cost
per tonne-km, `nothing` where infeasible.
"""
read_gate(path) = [(; ship=row[1], rig=row[2], route=row[3],
                       departure=parse(Float64, row[4]), cost=tryparse(Float64, row[5]))
                   for row in split.(readlines(path)[2:end], ",")]

"""
    departure_savings(rows)

Cost saving of each rig against the same ship without a rig on the same route and departure
[points], keyed by (ship, rig, route) and then by departure; `nothing` where either is
infeasible.
"""
function departure_savings(rows)
    cost = Dict((row.ship, row.rig, row.route, row.departure) => row.cost for row in rows)
    savings = Dict{NTuple{3, String}, Dict{Float64, Union{Nothing, Float64}}}()
    for row in rows
        row.rig == "none" && continue
        bare = cost[(row.ship, "none", row.route, row.departure)]
        value = isnothing(bare) || isnothing(row.cost) ? nothing :
                100 * (1 - row.cost / bare)
        get!(savings, (row.ship, row.rig, row.route), Dict())[row.departure] = value
    end
    return savings
end

"""
    saving_changes(new, reference; extrapolated=false)

Per (ship, rig, route) of the gate files' rows `reference`: the mean saving over the
departures in `reference` and in `new` [points], the mean and the standard error of their
paired change [points]; `nothing` for a case that is infeasible in either. With
`extrapolated`, `reference` is a grid twice as fine as `new`, and each departure's reference
saving is extrapolated from the two at first order.
"""
function saving_changes(new, reference; extrapolated=false)
    new_savings, reference_savings = departure_savings(new), departure_savings(reference)
    changes = Dict()
    for (key, by_departure) in reference_savings
        pairs = [(get(new_savings[key], departure, nothing), value)
                 for (departure, value) in by_departure]
        if any(pair -> any(isnothing, pair), pairs)
            changes[key] = nothing
            continue
        end
        extrapolated && (pairs = [(saving, 2 * finer - saving) for (saving, finer) in pairs])
        paired = [first(pair) - last(pair) for pair in pairs]
        changes[key] = (; new=mean(first.(pairs)), reference=mean(last.(pairs)),
            change=mean(paired), error=std(paired) / sqrt(length(paired)))
    end
    return changes
end

"""
    standard_passes(new, reference; extrapolated=false)

Print each rig's saving in the gate files' rows `new` against `reference`, extrapolated as
[`saving_changes`](@ref) says, and the change of the gap between each two rigs; whether
every saving moves by at most `SAVING_TOLERANCE` and every gap by at most `GAP_TOLERANCE` points,
and every case feasible in one is in the other.
"""
function standard_passes(new, reference; extrapolated=false)
    changes = saving_changes(new, reference; extrapolated)
    passed = true
    for key in sort!(collect(keys(changes)))
        found = changes[key]
        if isnothing(found)
            println(join(key, " "), ": infeasible in one of the two")
            passed = false
            continue
        end
        @printf("%-28s saving %6.2f, reference %6.2f, change %+.2f ± %.2f points\n",
            join(key, " "), found.new, found.reference, found.change, found.error)
        passed &= abs(found.change) <= SAVING_TOLERANCE
    end
    for (one, other) in Iterators.product(keys(changes), keys(changes))
        one[1] == other[1] && one[3] == other[3] && one[2] < other[2] || continue
        any(isnothing, (changes[one], changes[other])) && continue
        gap = changes[one].change - changes[other].change
        @printf("%-28s gap to %-6s moves %+.2f points\n", join(one, " "), other[2], gap)
        passed &= abs(gap) <= GAP_TOLERANCE
    end
    return passed
end

"""
    gate_passes(out_dir, reference_dir)

Whether the gate in `out_dir` meets the standard against the savings extrapolated from it
and the one in `reference_dir`, on a grid twice as fine, printing each case.
"""
gate_passes(out_dir, reference_dir) =
    standard_passes(read_gate(joinpath(out_dir, "gate.csv")),
        read_gate(joinpath(reference_dir, "gate.csv")); extrapolated=true)

if abspath(PROGRAM_FILE) == @__FILE__
    directories = filter(!startswith("--"), ARGS)
    fidelity = "--reference" in ARGS ? (; scale=0.5, settings=WindShipOpt.RouterSettings()) :
               planner_fidelity()
    gate_trips(first(directories), gate_cases(), fidelity)
    length(directories) > 1 && exit(gate_passes(directories...) ? 0 : 1)
end
