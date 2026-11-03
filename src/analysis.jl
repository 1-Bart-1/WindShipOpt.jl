"""
    parking_lull(table, speed, wind, angle, recovery_wind)

What parking through a lull costs against landing, for a kite at ship `speed` [m/s] in a
10 m `wind` [m/s] at true wind `angle` [rad] and calm sea, once the wind is back at
`recovery_wind`: `stays_up`, whether it can park there; `parked_cost` and `flown_cost`, the
fuel cost of parked and flying over stowed [USD/h]; `cycle`, a landing and launch with the
flight saving lost while they last [USD]; `hours`, the lull beyond which landing is cheaper,
zero where it cannot park and `Inf` where parking pays by itself.
"""
function parking_lull(table::PerformanceTable, speed, wind, angle, recovery_wind)
    weight = KnotWeight(table.speeds, speed)
    fuels(wind_10m) = edge_fuels(table, speed, weight,
        SeaCondition(table, wind_10m, angle, 0.0, 8.0, 0.0))
    price = table.ship.fuel.price * 3600
    flown, stowed, parked = fuels(wind)
    crosswind, headwind = kite_wind(table, wind) .* sincos(angle)
    stays_up = isfinite(parked) && kite_aloft(table, speed, headwind, crosswind, 0.0) &&
               kite_parkable(table, speed, headwind, crosswind)
    recovered_flown, recovered_stowed = fuels(recovery_wind)
    cycle = table.cycle_cost +
            table.handling_hours * max(recovered_stowed - recovered_flown, 0.0) * price
    hourly = (parked - stowed) * price + table.parked_wear_cost
    hours = !stays_up ? 0.0 : hourly > 0 ? cycle / hourly : Inf
    return (; stays_up, parked_cost=(parked - stowed) * price,
        flown_cost=(flown - stowed) * price, cycle, hours)
end

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
edge's mode is flying or only a flying kite holds the speed, parks where the mode is
parked, and the [`standing_rig`](@ref) always stands. It can differ from the router's edge
cost: the [`sail_edge!`](@ref) points with the kite managed per point.
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
    wave_height, wave_period, wave_from = waves(weather, lat, lon, departure + time)
    heading = wave_heading(wave_from, course)
    condition = SeaCondition(table.table, wind_speed, angle, wave_height, wave_period,
        heading)
    crosswind, headwind = kite_wind(table.table, wind_speed) .* sincos(angle)
    held, flown_power, stowed_power, parked_power = held_speed(table, speed_index,
        EdgeSample(condition, headwind, crosswind, is_daylight(lon, time)))
    speed = table.speeds[max(held, 1)]
    standing = standing_rig(ship.rig)
    aloft = kite_aloft(table.table, speed, headwind, crosswind, wave_height)
    flown = standing === ship.rig || (mode == FLYING || !isfinite(stowed_power)) &&
            isfinite(flown_power) && aloft
    parked = !flown && mode == PARKED && isfinite(parked_power) && aloft
    carried = flown ? ship.rig : parked ? parked_rig(ship.rig) : standing
    force = last(best_trim(ship, carried, speed, wind_speed, angle))
    push!(trace.time, time)
    push!(trace.speed, speed)
    push!(trace.true_wind_angle, angle)
    push!(trace.rig_thrust, force.thrust)
    push!(trace.fuel_power, flown ? flown_power : parked ? parked_power : stowed_power)
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
    ranked_with_next(costs)

The rigs of the dictionary `costs`, cheapest first, as pairs of rig and the cost of the next
rig, `NaN` for the last.
"""
function ranked_with_next(costs)
    ranked = sort(collect(keys(costs)); by=rig -> costs[rig])
    return [rig => (rank < length(ranked) ? costs[ranked[rank + 1]] : NaN)
            for (rank, rig) in enumerate(ranked)]
end

"""
    events_to_cost(cost, target_cost, yearly_work, event_cost)

Events a year, each costing `event_cost` [USD], that raise a transport `cost` [USD per
tonne-km] to `target_cost` at `yearly_work` [tonne-km]; zero if it is already above.
"""
events_to_cost(cost, target_cost, yearly_work, event_cost) =
    max(target_cost - cost, 0.0) * yearly_work / event_cost
