# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Convergence of sailing the forecast result's plan live, at the router's live settings and
# with the time between choices and the speeds skipped halved twice: on the development
# case, the 140 m e-ammonia ship to Guadeloupe without a rig, with the kite and with the
# rotors over its 12 departures; and on the full check, the router gate's ships, routes and
# rigs over four of them, at the live settings and the finest.
#
#   julia --project=scripts -t auto scripts/live_convergence.jl <out_dir>
#
# Writes live_convergence.csv, a line per round trip, and prints per check, ship, route and
# setting each rig's mean cost saving, its change from the finest setting and the largest
# change of a gap between two rigs, over the departures where every case has a trip.
include("paper.jl")
include("router_gate.jl")

"live settings compared, as (name, time between choices [h], speeds skipped plus one)"
LIVE_SETTINGS = (("hourly", 1.0, 4), ("half", 0.5, 2), ("quarter", 0.25, 1))

"""
    live_cases()

Per check, setting of `LIVE_SETTINGS`, ship, route, rig and departure, the case sailing the
forecast result's plan live, as (check, setting, step, stride, ship, route, departure,
case).
"""
function live_cases()
    development = [(; check="development", ship="140m_ammonia", route=:caribbean, rig,
                       design=ShipDesign(:ammonia, 140.0; rig_size(rig, area)...),
                       departure)
                   for (rig, area) in [("none", 0.0); reference_rigs]
                   if rig in ("none", "kite", "rotors")
                   for departure in ensemble_departures]
    full = [(; check="full", case.ship, case.route, case.rig, case.design, departure)
            for case in gate_cases(1.0) for departure in ensemble_departures[1:3:end]]
    settings = [(; setting, step, stride) for (setting, step, stride) in LIVE_SETTINGS]
    return [(; entry..., setting...,
                case=trip_case(entry.design; forecast=:grid_live, entry.route,
                    entry.rig, entry.departure,
                    paths=route_corridors(entry.route, mask; grid_spacing...)))
            for entry in [development; full] for setting in settings
            if entry.check == "development" || setting.setting != "half"]
end

"cost per tonne-kilometre [USD/tkm] of each of `cases`, `NaN` where its trip fails"
function live_costs(cases)
    costs = fill(NaN, length(cases))
    Threads.@threads :greedy for k in eachindex(cases)
        (; step, stride, departure, case) = cases[k]
        settings = WindShipOpt.RouterSettings(live_step_hours=step,
            live_speed_stride=stride)
        trip = WindShipOpt.with_router_settings(() -> case_trip(case, [departure]),
            settings)
        isnothing(trip) || (costs[k] = trip.cost_per_tonne_km)
    end
    return costs
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
    print_convergence(cases, costs)

Per check, ship, route and setting, each rig's mean saving [%], its mean change from the
finest setting and the largest change of a gap between two rigs [points].
"""
function print_convergence(cases, costs)
    cost = Dict((entry.check, entry.setting, entry.ship, entry.route, entry.rig,
                    entry.departure) => value for (entry, value) in zip(cases, costs))
    finest = first(last(LIVE_SETTINGS))
    for (check, ship, route) in unique((entry.check, entry.ship, entry.route)
                                       for entry in cases)
        group = filter(entry -> (entry.check, entry.ship, entry.route) ==
                                (check, ship, route), cases)
        rigs = filter(!=("none"), unique(entry.rig for entry in group))
        departures = unique(entry.departure for entry in group)
        saving(setting, rig) = [100 * (1 - cost[(check, setting, ship, route, rig,
                                                 departure)] /
                                           cost[(check, setting, ship, route, "none",
                                                 departure)])
                                for departure in departures]
        settings = unique(entry.setting for entry in group)
        usable = findall(i -> all(isfinite(saving(setting, rig)[i])
                                  for setting in settings, rig in rigs),
            eachindex(departures))
        mean_saving(setting, rig) = mean(saving(setting, rig)[usable])
        for setting in settings
            change = Dict(rig => mean_saving(setting, rig) - mean_saving(finest, rig)
                          for rig in rigs)
            gap = maximum((abs(change[first] - change[second])
                           for first in rigs, second in rigs); init=0.0)
            @printf("%-11s %-12s %-9s %-7s %d deps: %s; gap change %.2f\n", check, ship,
                route, setting, length(usable),
                join((@sprintf("%s %.2f (%+.2f)", rig, mean_saving(setting, rig),
                          change[rig]) for rig in rigs), ", "), gap)
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    global paper_run = PaperRun(nothing, :draft, Dict{String, Any}(), 0, 0)
    cases = live_cases()
    costs = live_costs(cases)
    write_live_costs(joinpath(mkpath(first(ARGS)), "live_convergence.csv"), cases, costs)
    print_convergence(cases, costs)
end
