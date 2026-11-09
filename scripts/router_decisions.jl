# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# What deciding the rig inside the route search is worth: the router's cost of each passage
# of the router gate's cases at corridor scale 4 for the search as it is, for a path found
# without the rig and then sailed with it, for a kite searched as if launches were free, and
# for a kite searched with no state to carry, as a router that tabulates its force would.
#
#   julia +1.12 --project=. -t auto scripts/router_decisions.jl <out_dir>
#
# Writes passages.csv, a line per passage, and prints the reduction of each rig.
using Printf
include("router_gate.jl")

"band in time around the path that a path found without the rig is searched in [h]"
DECIDED_ALONE_BAND = 240.0

"`object` with the fields named in `changes` replaced"
function with_fields(object; changes...)
    fields = [get(changes, name, getfield(object, name))
              for name in fieldnames(typeof(object))]
    return typeof(object)(fields...)
end

"`table` with kite launches and landings free"
free_launch_table(table) = WindShipOpt.RouteTable(with_fields(table; cycle_cost=0.0))

"`table` of a kite up wherever that pays: launches free, instant and open to any wind or sea"
function stateless_table(table)
    rig = with_fields(table.ship.rig; launch_min_wind=0.0, launch_max_wind=Inf,
        launch_max_wave_height=Inf, night_launch=true)
    return WindShipOpt.RouteTable(with_fields(table; ship=with_fields(table.ship; rig),
        cycle_cost=0.0, handling_hours=0.0, forced_landing_cost=0.0))
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

"Each passage of `case` on `sampled` departures: bare, as searched, and the two blind ones."
function searched_passages(case, sampled)
    ship, bare, hourly = case_ships(case)
    kite_table = WindShipOpt.PerformanceTable(ship, assumptions)
    table = WindShipOpt.RouteTable(kite_table)
    bare_table = WindShipOpt.RouteTable(WindShipOpt.PerformanceTable(bare, assumptions))
    free_table = case.rig == "kite" ? free_launch_table(kite_table) : nothing
    blind_table = case.rig == "kite" ? stateless_table(kite_table) : nothing
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
            blind = isnothing(blind_table) ? nothing :
                    route(corridor, blind_table, weather, leg_start; time_cost)
            (isnothing(searched) || isnothing(without)) && break
            push!(rows, (; case, departure, leg, corridor, table, leg_start, time_cost,
                searched, without, free, blind, cycle_cost=kite_table.cycle_cost))
            leg_start += searched.duration + port_hours
        end
    end
    return rows
end

"Cost of the path of `found` when the real rig sails it, choosing speed and kite."
function sailed_path(found, row)
    (; corridor, table, leg_start, time_cost) = row
    unpriced = WindShipOpt.Leg(found.fuel_energy, found.fuel_cost, found.flight_hours,
        found.launches, found.forced_landings, found.duration, Inf, found.path, found.aloft)
    return WindShipOpt.final_pass(unpriced, corridor, table, weather, leg_start; time_cost,
        first_stage=1, first_aloft=false, coastal_penalty=1.0).objective
end

"Reduction [%] against the ship without a rig of the column `name` of `rows`"
reduction(rows, name) =
    100 * (1 - sum(getproperty(row, name) for row in rows) /
               sum(row.without for row in rows))

"Print the mean reduction of the router's cost per rig; `rows` are the lines of the file."
function report(rows)
    for rig in ("kite", "wings", "rotors")
        chosen = filter(row -> row.rig == rig, rows)
        isempty(chosen) && continue
        @printf("%-7s %3d passages: searched %.2f %%, path without rig %.2f %%", rig,
            length(chosen), reduction(chosen, :searched), reduction(chosen, :alone))
        rig == "kite" && @printf(", free launches %.2f %%, stateless reported %.2f %%, \
            stateless path sailed %.2f %%", reduction(chosen, :free),
            reduction(chosen, :stateless), reduction(chosen, :stateless_sailed))
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
    alone, blind_sailed = WindShipOpt.with_router_settings(WindShipOpt.RouterSettings(;
        final_time_band=DECIDED_ALONE_BAND)) do
        pairs = fetch.([Threads.@spawn (sailed_path(row.without, row),
            isnothing(row.blind) ? NaN : sailed_path(row.blind, row))
                        for row in passages])
        return first.(pairs), last.(pairs)
    end
    rows = map(zip(passages, alone, blind_sailed)) do (row, sailed, blind_path)
        free = isnothing(row.free) ? NaN :
               row.free.objective + row.free.launches * row.cycle_cost
        launches = isnothing(row.free) ? -1 : row.free.launches
        (; row.case.ship, row.case.rig, row.case.route, row.departure, row.leg,
            without=row.without.objective, searched=row.searched.objective, alone=sailed,
            free, stateless=isnothing(row.blind) ? NaN : row.blind.objective,
            stateless_sailed=blind_path, searched_launches=row.searched.launches,
            free_launches=launches)
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
