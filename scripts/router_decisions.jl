# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# What deciding the rig inside the route search is worth: the router's cost of each passage
# of the router gate's cases at corridor scale 4 for the search as it is, for a path found
# without the rig and then sailed with it, and for a kite searched as if launches were free.
#
#   julia +1.12 --project=. -t auto scripts/router_decisions.jl <out_dir>
#
# Writes passages.csv, a line per passage, and prints the reduction of each rig.
using Printf
include("router_gate.jl")

"band in time around the path that a path found without the rig is searched in [h]"
DECIDED_ALONE_BAND = 240.0

"`table` with kite launches and landings free"
function free_launch_table(table)
    fields = [name == :cycle_cost ? 0.0 : getfield(table, name)
              for name in fieldnames(typeof(table))]
    return WindShipOpt.RouteTable(typeof(table)(fields...))
end

"The ship of `case` with its rig and without it, and the rig's hourly time cost per leg."
function case_ships(case)
    ship = Ship(case.design, assumptions)
    bare_case = only(filter(other -> other.ship == case.ship && other.route == case.route &&
                                     other.rig == "none", gate_cases(case.scale)))
    hourly = WindShipOpt.leg_time_costs(first(WindShipOpt.ship_costs(ship, assumptions)),
        assumptions)
    return ship, Ship(bare_case.design, assumptions), hourly
end

"Each passage of `case` on `sampled` departures: bare, as searched and blind to launches."
function searched_passages(case, sampled)
    ship, bare, hourly = case_ships(case)
    kite_table = WindShipOpt.PerformanceTable(ship, assumptions)
    table = WindShipOpt.RouteTable(kite_table)
    bare_table = WindShipOpt.RouteTable(WindShipOpt.PerformanceTable(bare, assumptions))
    free_table = case.rig == "kite" ? free_launch_table(kite_table) : nothing
    port_hours = 24assumptions[:port_time_per_call]
    outbound, inbound = corridors(case.route, case.scale)
    rows = []
    for departure in sampled
        leg_start = departure
        for (leg, corridor, time_cost) in (("out", outbound, first(hourly)),
            ("back", inbound, last(hourly)))
            searched = route(corridor, table, weather, leg_start; time_cost)
            without = route(corridor, bare_table, weather, leg_start; time_cost)
            free = isnothing(free_table) ? nothing :
                   route(corridor, free_table, weather, leg_start; time_cost)
            (isnothing(searched) || isnothing(without)) && break
            push!(rows, (; case, departure, leg, corridor, table, leg_start, time_cost,
                searched, without, free, cycle_cost=kite_table.cycle_cost))
            leg_start += searched.duration + port_hours
        end
    end
    return rows
end

"Cost of the path of the ship without a rig when the rig sails it, choosing speed and kite."
function path_alone(row)
    (; without, corridor, table, leg_start, time_cost) = row
    unpriced = WindShipOpt.Leg(without.fuel_energy, without.fuel_cost, without.flight_hours,
        without.launches, without.forced_landings, without.duration, Inf, without.path,
        without.aloft)
    return WindShipOpt.final_pass(unpriced, corridor, table, weather, leg_start; time_cost,
        first_stage=1, first_aloft=false, coastal_penalty=1.0).objective
end

"Print the mean reduction of the router's cost per rig; `rows` are the lines of the file."
function report(rows)
    for rig in ("kite", "wings", "rotors")
        chosen = filter(row -> row.rig == rig, rows)
        isempty(chosen) && continue
        total(name) = sum(getproperty(row, name) for row in chosen)
        reduction(name) = 100 * (1 - total(name) / total(:without))
        @printf("%-7s %3d passages: searched %.2f %%, path without rig %.2f %%", rig,
            length(chosen), reduction(:searched), reduction(:alone))
        rig == "kite" && @printf(", free launches %.2f %%", reduction(:free))
        println()
    end
end

"Route every passage and write `out_dir`/passages.csv."
function router_decisions(out_dir;
        cases=filter(case -> case.rig != "none", gate_cases(4.0)),
        sampled=departures[1:6:end])
    mkpath(out_dir)
    found = fill(Any[], length(cases))
    Threads.@threads :greedy for i in eachindex(cases)
        found[i] = searched_passages(cases[i], sampled)
    end
    passages = reduce(vcat, found)
    alone = WindShipOpt.with_router_settings(WindShipOpt.RouterSettings(;
        final_time_band=DECIDED_ALONE_BAND)) do
        fetch.([Threads.@spawn path_alone(row) for row in passages])
    end
    rows = map(zip(passages, alone)) do (row, sailed)
        free = isnothing(row.free) ? NaN :
               row.free.objective + row.free.launches * row.cycle_cost
        launches = isnothing(row.free) ? -1 : row.free.launches
        (; row.case.ship, row.case.rig, row.case.route, row.departure, row.leg,
            without=row.without.objective, searched=row.searched.objective, alone=sailed,
            free, searched_launches=row.searched.launches, free_launches=launches)
    end
    open(joinpath(out_dir, "passages.csv"), "w") do io
        println(io, join(keys(first(rows)), ","))
        foreach(row -> println(io, join(values(row), ",")), rows)
    end
    report(rows)
    return rows
end

if abspath(PROGRAM_FILE) == @__FILE__
    router_decisions(only(ARGS))
end
