# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Convergence of sailing the forecast result's plan live, at the given live settings: on
# the development check, the 140 m e-ammonia ship to Guadeloupe without a rig, with the
# kite and with the rotors over its 12 departures; or on the full check, the router gate's
# ships, routes and rigs over four of them.
#
#   julia --project=scripts -t auto scripts/live_convergence.jl <out_dir> <check> <setting>...
#       [--rigs=<rig>,...] [--every=<n>]
#
# with <check> development or full and each <setting> a name of LIVE_SETTINGS; --rigs keeps
# only those rigs besides no rig, and --every every n-th of the check's departures. Writes
# live_convergence.csv, a line per round trip, and prints per ship, route and setting each
# rig's mean cost saving, its change from the finest setting and the largest change of a
# gap between two rigs, over the departures where every case has a trip.
include("paper.jl")
include("router_gate.jl")

"live settings compared, as (name, time between choices [h], speeds skipped plus one)"
LIVE_SETTINGS = (("hourly", 1.0, 4), ("half", 0.5, 2), ("quarter", 0.25, 1),
    ("eighth", 0.125, 1))

"""
    check_designs(check)

Ship, route, rig and design of each case of `check`, and the departures it sails.
"""
function check_designs(check)
    check == "development" && return (
        [(; check, ship="140m_ammonia", route=:caribbean, rig,
             design=ShipDesign(:ammonia, 140.0; rig_size(rig, area)...))
         for (rig, area) in [("none", 0.0); reference_rigs]
         if rig in ("none", "kite", "rotors")], ensemble_departures)
    check == "full" && return (
        [(; check, case.ship, case.route, case.rig, case.design)
         for case in gate_cases(1.0)], ensemble_departures[1:3:end])
    throw(ArgumentError("check is development or full, not $check"))
end

"""
    live_cases(check, names; rigs=nothing, every=1)

Per setting of `LIVE_SETTINGS` named in `names`, ship, route, rig and departure of `check`,
the case sailing the forecast result's plan live, as (check, setting, step, stride, ship,
route, departure, case); with `rigs`, only those rigs and no rig, and only every `every`-th
of the check's departures.
"""
function live_cases(check, names; rigs=nothing, every=1)
    unknown = setdiff(names, first.(LIVE_SETTINGS))
    isempty(unknown) ||
        throw(ArgumentError("unknown live settings: $(join(unknown, ", "))"))
    designs, departures = check_designs(check)
    unknown = setdiff(something(rigs, String[]), (design.rig for design in designs))
    isempty(unknown) ||
        throw(ArgumentError("not in the $check check: $(join(unknown, ", "))"))
    entries = [(; design..., departure)
               for design in designs
               if isnothing(rigs) || design.rig == "none" || design.rig in rigs
               for departure in departures[1:every:end]]
    corridors = Dict(route => route_corridors(route, mask; grid_spacing...)
                     for route in unique(entry.route for entry in entries))
    settings = [(; setting, step, stride) for (setting, step, stride) in LIVE_SETTINGS
                if setting in names]
    return [(; entry..., setting...,
                case=trip_case(entry.design; forecast=:grid_live, entry.route,
                    entry.rig, entry.departure, paths=corridors[entry.route]))
            for entry in entries for setting in settings]
end

"cost per tonne-kilometre [USD/tkm] of each of `cases`, `NaN` where its trip fails"
function live_costs(cases)
    costs = fill(NaN, length(cases))
    for (step, stride) in unique((entry.step, entry.stride) for entry in cases)
        settings = WindShipOpt.RouterSettings(live_step_hours=step,
            live_speed_stride=stride)
        members = findall(entry -> (entry.step, entry.stride) == (step, stride), cases)
        WindShipOpt.with_router_settings(() -> trip_costs!(costs, cases, members), settings)
    end
    return costs
end

"set `costs` at `members` of `cases` to each trip's cost per tonne-kilometre [USD/tkm]"
function trip_costs!(costs, cases, members)
    Threads.@threads :greedy for k in members
        (; departure, case) = cases[k]
        trip = case_trip(case, [departure])
        isnothing(trip) || (costs[k] = trip.cost_per_tonne_km)
    end
end

"write `cases` and their `costs` to the CSV file `path`"
function write_live_costs(path, cases, costs)
    open(path, "w") do io
        println(io, "check,setting,ship,route,rig,departure,cost")
        for (entry, cost) in zip(cases, costs)
            println(io, join((entry.check, entry.setting, entry.ship, entry.route,
                entry.rig, entry.departure, cost), ","))
        end
    end
end

"""
    live_savings(cost, (check, ship, route), setting, rig, departures)

Cost saving [%] of `rig` against no rig per departure of `departures` on `check`, `ship`,
`route` and `setting`, from `cost` keyed as in [`print_convergence`](@ref).
"""
live_savings(cost, (check, ship, route), setting, rig, departures) =
    [100 * (1 - cost[(check, setting, ship, route, rig, departure)] /
                cost[(check, setting, ship, route, "none", departure)])
     for departure in departures]

"""
    print_convergence(cases, costs)

Per check, ship, route and setting, each rig's mean saving [%], its mean change from the
finest setting among them and the largest change of a gap between two rigs [points].
"""
function print_convergence(cases, costs)
    cost = Dict((entry.check, entry.setting, entry.ship, entry.route, entry.rig,
                    entry.departure) => value for (entry, value) in zip(cases, costs))
    finest = argmin(entry -> entry.step, cases).setting
    for group in unique((entry.check, entry.ship, entry.route) for entry in cases)
        members = filter(entry -> (entry.check, entry.ship, entry.route) == group, cases)
        rigs = filter(!=("none"), unique(entry.rig for entry in members))
        departures = unique(entry.departure for entry in members)
        settings = unique(entry.setting for entry in members)
        savings = Dict((setting, rig) => live_savings(cost, group, setting, rig, departures)
                       for setting in settings for rig in rigs)
        usable = complete_departures(collect(values(savings)))
        means = Dict(key => mean(saving[usable]) for (key, saving) in savings)
        for setting in settings
            change = Dict(rig => means[(setting, rig)] - means[(finest, rig)]
                          for rig in rigs)
            gap = maximum((abs(change[first] - change[second])
                           for first in rigs, second in rigs); init=0.0)
            @printf("%-11s %-12s %-9s %-7s %d deps: %s; gap change %.2f\n", group...,
                setting, length(usable),
                join((@sprintf("%s %.2f (%+.2f)", rig, means[(setting, rig)], change[rig])
                      for rig in rigs), ", "), gap)
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    global paper_run = PaperRun(nothing, :draft, Dict{String, Any}(), 0, 0)
    options = Dict(split(arg, '=') for arg in ARGS[3:end] if startswith(arg, "--"))
    cases = live_cases(ARGS[2], filter(!startswith("--"), ARGS[3:end]);
        rigs=haskey(options, "--rigs") ? split(options["--rigs"], ',') : nothing,
        every=parse(Int, get(options, "--every", "1")))
    costs = live_costs(cases)
    write_live_costs(joinpath(mkpath(first(ARGS)), "live_convergence.csv"), cases, costs)
    print_convergence(cases, costs)
end
