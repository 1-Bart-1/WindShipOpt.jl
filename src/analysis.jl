"""
    LegTrace

What happens on each stage of a routed leg: time [h], speed held [m/s], true wind angle
[rad], rig thrust [N] and fuel power [W].
"""
struct LegTrace
    time::Vector{Float64}
    speed::Vector{Float64}
    true_wind_angle::Vector{Float64}
    rig_thrust::Vector{Float64}
    fuel_power::Vector{Float64}
end

"""
    LegTrace(table, leg, weather, departure; interval=Inf)

Re-evaluate the ship models along the path of `leg` at the start of every edge and every
`interval` [h] along it, with positions interpolated along the edge and the weather at
that time and place. The ship holds the edge's commanded speed where it can and the
[`held_speed`](@ref) elsewhere; a kite flies where [`kite_aloft`](@ref) allows and the
edge's mode is flying or only a flying kite holds the speed, and the
[`standing_rig`](@ref) always stands. It can differ from the router's edge cost: the
[`sail_edge!`](@ref) points with the kite managed per point.
"""
function LegTrace(table::PerformanceTable, leg::Leg, weather, departure; interval=Inf)
    route_table = RouteTable(table)
    trace = LegTrace((Float64[] for _ in 1:5)...)
    for i in 1:(length(leg.path) - 1)
        lat, lon, time, _ = leg.path[i]
        next_lat, next_lon, next_time, speed, mode = leg.path[i + 1]
        course = bearing(lat, lon, next_lat, next_lon)
        samples = isfinite(interval) ? (time:interval:prevfloat(next_time)) : (time,)
        for sample_time in samples
            share = (sample_time - time) / (next_time - time)
            push_trace_point!(trace, route_table, weather, departure,
                lat + share * (next_lat - lat), lon + share * (next_lon - lon), sample_time,
                searchsortedfirst(route_table.speeds, speed), course, mode == FLYING)
        end
    end
    return trace
end

"""
    push_trace_point!(trace, table, weather, departure, lat, lon, time, speed_index,
                      course, kite_flying)

Append to `trace` the ship models at one point of a leg at commanded speed number
`speed_index` of the [`RouteTable`](@ref) `table`, with a kite flown if `kite_flying` and
it can stay aloft there.
"""
function push_trace_point!(trace, table::RouteTable, weather, departure, lat, lon, time,
        speed_index, course, kite_flying)
    (; ship) = table.table
    east, north = wind(weather, lat, lon, departure + time)
    wind_speed = hypot(east, north)
    angle = true_wind_angle(east, north, wind_speed, course)
    sea = waves(weather, lat, lon, departure + time)
    sample = EdgeSample(table.table, (east, north), sea, course)
    held, flown_power, stowed_power = held_speed(table, speed_index, sample)
    speed = table.speeds[max(held, 1)]
    standing = standing_rig(ship.rig)
    flown = standing === ship.rig || (kite_flying || !isfinite(stowed_power)) &&
            isfinite(flown_power) &&
            kite_aloft(table.table, speed, sample.headwind, sample.crosswind, first(sea))
    force = last(best_trim(ship, flown ? ship.rig : standing, speed, wind_speed, angle))
    push!(trace.time, time)
    push!(trace.speed, speed)
    push!(trace.true_wind_angle, angle)
    push!(trace.rig_thrust, force.thrust)
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
    life_at_cost(lives, costs, cost)

Life at which the `costs` over `lives`, falling with the life, reach `cost`, linear in the
inverse of the life, which wear follows; `NaN` if within none of `lives`.
"""
function life_at_cost(lives, costs, cost)
    order = sortperm(lives; rev=true)
    costs[first(order)] > cost && return NaN
    return 1 / share_at_cost(1 ./ lives[order], costs[order], cost)
end
