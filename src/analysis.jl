# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""
    LegTrace

The ship models at each point the router sailed along a leg: time [h since departure],
position [deg], course [rad from north], 10 m wind east and north [m/s], speed held [m/s],
true wind angle [rad], apparent wind speed [m/s] and angle off the bow [rad] at the rig's
height, rig thrust [N], the thrust the rig would give flown at its best trim where it can
be up [N], fuel power [W], whether a kite flies, launches or lands at the point and whether
the landing was forced, and the trim setting of the rig carried there.
"""
struct LegTrace
    time::Vector{Float64}
    lat::Vector{Float64}
    lon::Vector{Float64}
    course::Vector{Float64}
    wind_east::Vector{Float64}
    wind_north::Vector{Float64}
    speed::Vector{Float64}
    true_wind_angle::Vector{Float64}
    apparent_wind::Vector{Float64}
    apparent_angle::Vector{Float64}
    rig_thrust::Vector{Float64}
    available_thrust::Vector{Float64}
    fuel_power::Vector{Float64}
    flying::Vector{Bool}
    launched::Vector{Bool}
    landed::Vector{Bool}
    forced::Vector{Bool}
    trim::Vector{Any}
end

"""
    LegTrace(table, leg, weather, departure)

Re-evaluate the ship models along the path of `leg`: at the points [`sail_edge!`](@ref)
sails its edges in, with the kite flying where [`kite_flights`](@ref) has it; the last
point of an edge is the first of the next, so it is left out except on the last edge.
"""
function LegTrace(table::PerformanceTable, leg::Leg, weather, departure)
    route_table = RouteTable(table)
    corridor = leg_corridor(leg)
    prices = (; fuel=table.ship.fuel.price, time=0.0)
    trace = LegTrace((Float64[] for _ in 1:13)..., (Bool[] for _ in 1:4)..., Any[])
    points = SailedPoint[]
    edges = length(leg.path) - 1
    carried = (launched=false, landed=false, forced=false)
    for i in 1:edges
        lat, lon, time = leg.path[i]
        next_lat, next_lon, _, speed = leg.path[i + 1]
        course = corridor.edge_course[i, 1, STRAIGHT_ON]
        start = EdgeSample(table, wind(weather, lat, lon, departure + time),
            waves(weather, lat, lon, departure + time), course,
            is_daylight(lon, departure + time))
        sail_edge!(points, start, route_table, weather, corridor, i, 1, STRAIGHT_ON,
            departure + time, searchsortedfirst(route_table.speeds, speed))
        flights = kite_flights(route_table, points, leg.aloft[i], leg.aloft[i + 1], prices)
        for (k, point) in enumerate(points)
            flight = flights[k]
            k == length(points) && i < edges && (carried = flight; continue)
            share = (k - 1) / (length(points) - 1)
            push_trace_point!(trace, route_table, weather, departure,
                lat + share * (next_lat - lat), lon + share * (next_lon - lon), course,
                point, flight.flying, flight.launched || carried.launched,
                flight.landed || carried.landed, flight.forced || carried.forced)
            carried = (launched=false, landed=false, forced=false)
        end
    end
    return trace
end

"""
    push_trace_point!(trace, table, weather, departure, lat, lon, course, point, flying,
                      launched, landed, forced)

Append to `trace` the ship models at the [`SailedPoint`](@ref) `point`, at position (`lat`,
`lon`) on `course` of a leg left at `departure`, with a kite `flying` or not and having
`launched` or `landed`, the landing `forced` or not, there.
"""
function push_trace_point!(trace, table::RouteTable, weather, departure, lat, lon, course,
        point, flying, launched, landed, forced)
    (; ship) = table.table
    east, north = wind(weather, lat, lon, point.time)
    wind_speed = hypot(east, north)
    angle = true_wind_angle(east, north, wind_speed, course)
    speed = table.speeds[max(point.speed_index, 1)]
    standing = standing_rig(ship.rig)
    flown = flying || standing === ship.rig
    sample = EdgeSample(table.table, (east, north), waves(weather, lat, lon, point.time),
        course, is_daylight(lon, point.time))
    slice = SpeedSlice(table.table, KnotWeight(table.table.speeds, speed))
    added = trim_resistance(table.table, sea_resistance(slice, sample.condition))
    _, force, trim = trimmed_force(ship, flown ? ship.rig : standing, speed, wind_speed,
        angle, added)
    aloft = kite_aloft(table.table, speed, point.headwind, point.crosswind,
        point.condition.wave_height)
    available = standing === ship.rig || aloft ?
                last(best_trim(ship, ship.rig, speed, wind_speed, angle, added)).thrust :
                0.0
    apparent, apparent_angle = apparent_wind(
        wind_at_height(ship.env, wind_speed, rig_height(ship.rig)), angle, speed)
    push!(trace.time, point.time - departure)
    push!(trace.lat, lat)
    push!(trace.lon, lon)
    push!(trace.course, course)
    push!(trace.wind_east, east)
    push!(trace.wind_north, north)
    push!(trace.speed, speed)
    push!(trace.true_wind_angle, angle)
    push!(trace.apparent_wind, apparent)
    push!(trace.apparent_angle, apparent_angle)
    push!(trace.rig_thrust, force.thrust)
    push!(trace.available_thrust, available)
    push!(trace.fuel_power, flown ? point.flown : point.stowed)
    push!(trace.flying, flying)
    push!(trace.launched, launched)
    push!(trace.landed, landed)
    push!(trace.forced, forced)
    push!(trace.trim, trim)
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
