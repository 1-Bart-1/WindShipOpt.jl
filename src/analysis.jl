# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""
    LegTrace

What happens on each stage of a routed leg: time [h], speed held [m/s], true wind angle
[rad], apparent wind speed [m/s] and angle off the bow [rad] at the rig's height, rig thrust
[N], the thrust the rig would give flown at its best trim where it can be up [N], whether a
kite flies and fuel power [W].
"""
struct LegTrace
    time::Vector{Float64}
    speed::Vector{Float64}
    true_wind_angle::Vector{Float64}
    apparent_wind::Vector{Float64}
    apparent_angle::Vector{Float64}
    rig_thrust::Vector{Float64}
    available_thrust::Vector{Float64}
    flying::Vector{Bool}
    fuel_power::Vector{Float64}
end

"""
    LegTrace(table, leg, weather, departure; interval=Inf)

Re-evaluate the ship models along the path of `leg` at the start of every edge and every
`interval` [h] along it, with positions interpolated along the edge and the weather at
that time and place. The ship holds the edge's commanded speed where it can and the
[`held_speed`](@ref) elsewhere; a kite flies where [`kite_aloft`](@ref) allows and the
edge's mode is flying or only a flying kite holds the speed, and the
[`standing_rig`](@ref) always stands. It can differ from the router's edge
cost: the [`sail_edge!`](@ref) points with the kite managed per point.
"""
function LegTrace(table::PerformanceTable, leg::Leg, weather, departure; interval=Inf)
    route_table = RouteTable(table)
    trace = LegTrace((Float64[] for _ in 1:7)..., Bool[], Float64[])
    for i in 1:(length(leg.path) - 1)
        lat, lon, time, _ = leg.path[i]
        next_lat, next_lon, next_time, speed, mode = leg.path[i + 1]
        course = bearing(lat, lon, next_lat, next_lon)
        samples = isfinite(interval) ? (time:interval:prevfloat(next_time)) : (time,)
        for sample_time in samples
            share = (sample_time - time) / (next_time - time)
            push_trace_point!(trace, route_table, weather, departure,
                lat + share * (next_lat - lat), lon + share * (next_lon - lon), sample_time,
                searchsortedfirst(route_table.speeds, speed), course, mode)
        end
    end
    return trace
end

"""
    push_trace_point!(trace, table, weather, departure, lat, lon, time, speed_index,
                      course, mode)

Append to `trace` the ship models at one point of a leg at commanded speed number
`speed_index` of the [`RouteTable`](@ref) `table`, with a kite in the edge's `mode` where
it can stay aloft there.
"""
function push_trace_point!(trace, table::RouteTable, weather, departure, lat, lon, time,
        speed_index, course, mode)
    (; ship) = table.table
    east, north = wind(weather, lat, lon, departure + time)
    wind_speed = hypot(east, north)
    angle = true_wind_angle(east, north, wind_speed, course)
    sea = waves(weather, lat, lon, departure + time)
    sample = EdgeSample(table.table, (east, north), sea, course,
        is_daylight(lon, departure + time))
    held, flown_power, stowed_power = held_speed(table, speed_index, sample)
    speed = table.speeds[max(held, 1)]
    standing = standing_rig(ship.rig)
    aloft = kite_aloft(table.table, speed, sample.headwind, sample.crosswind)
    flown = standing === ship.rig || (mode == FLYING || !isfinite(stowed_power)) &&
            isfinite(flown_power) && aloft
    slice = SpeedSlice(table.table, KnotWeight(table.table.speeds, speed))
    added = trim_resistance(table.table, sea_resistance(slice, sample.condition))
    force = last(best_trim(ship, flown ? ship.rig : standing, speed, wind_speed, angle,
        added))
    available = standing === ship.rig || aloft ?
                last(best_trim(ship, ship.rig, speed, wind_speed, angle, added)).thrust :
                0.0
    apparent, apparent_angle = apparent_wind(
        wind_at_height(ship.env, wind_speed, rig_height(ship.rig)), angle, speed)
    push!(trace.time, time)
    push!(trace.speed, speed)
    push!(trace.true_wind_angle, angle)
    push!(trace.apparent_wind, apparent)
    push!(trace.apparent_angle, apparent_angle)
    push!(trace.rig_thrust, force.thrust)
    push!(trace.available_thrust, available)
    push!(trace.flying, flown && standing !== ship.rig)
    push!(trace.fuel_power, flown ? flown_power : stowed_power)
end

"""
    share_at_cost(shares, costs, cost)

Share [-] at which the rising `costs` over ascending `shares` reach `cost`, linearly between
the points; `NaN` if they never do, and the first share if they start above it.
"""
function share_at_cost(shares, costs, cost)
    costs[1] >= cost && return shares[1]
    k = findfirst(>=(cost), costs)
    isnothing(k) && return NaN
    return shares[k - 1] +
           (shares[k] - shares[k - 1]) * (cost - costs[k - 1]) / (costs[k] - costs[k - 1])
end

"""
    price_at_cost(prices, costs, cost)

Price at which the rising `costs` over ascending `prices` reach `cost`, linearly between the
points; `NaN` if within none of `prices`.
"""
price_at_cost(prices, costs, cost) =
    costs[1] < cost ? share_at_cost(prices, costs, cost) : NaN

"""
    ranked_rivals(costs)

The rigs of the dictionary `costs`, cheapest first, each with its rival, the cheapest of the
other rigs, that rival's cost and the cost of the rig just ahead, `NaN` for the first.
"""
function ranked_rivals(costs)
    ranked = sort(collect(keys(costs)); by=rig -> costs[rig])
    return map(enumerate(ranked)) do (rank, rig)
        rival = ranked[rank == 1 ? 2 : 1]
        return (; rig, rival, rival_cost=costs[rival],
            ahead=rank == 1 ? NaN : costs[ranked[rank - 1]])
    end
end

"""
    sizes_around(rig, area, largest)

Sizes [m^2] of `rig` to sweep around `area`, none above `largest`: a quarter to four times
`area` in doublings for a kite, half, once and twice `area` for the others.
"""
function sizes_around(rig, area, largest)
    factors = rig == "kite" ? (0.25, 0.5, 1.0, 2.0, 4.0) : (0.5, 1.0, 2.0)
    return unique(min.(factors .* area, largest))
end

"""
    check_goal_cost(ship, sweep, goal, swept)

Raise an error unless each rig of the dictionary `swept`, the costs at the goals in `sweep`
on `ship`, has its cost of `goal`.
"""
function check_goal_cost(ship, sweep, goal, swept)
    for (rig, cost) in swept
        cost == goal[rig] || error("$sweep sweep on $ship has $rig at $cost at the goals, ",
            "not the $(goal[rig]) of the size sweep")
    end
end

"""
    events_to_cost(cost, target_cost, yearly_work, event_cost)

Events a year, each costing `event_cost` [USD], that raise a transport `cost` [USD per
tonne-km] to `target_cost` at `yearly_work` [tonne-km]; zero if it is already above.
"""
events_to_cost(cost, target_cost, yearly_work, event_cost) =
    max(target_cost - cost, 0.0) * yearly_work / event_cost

"""
    life_at_cost(lives, costs, cost)

Life at which the `costs` over `lives`, falling with the life, reach `cost`, linear in the
inverse of the life, which wear follows; `NaN` if within none of `lives`.
"""
function life_at_cost(lives, costs, cost)
    order = sortperm(lives; rev=true)
    costs[first(order)] > cost && return NaN
    return 1 / share_at_cost(1 ./ lives[order], costs[order], cost)
end
