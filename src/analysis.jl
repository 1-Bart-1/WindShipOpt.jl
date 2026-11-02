"""
    LegTrace

What happens on each stage of a routed leg: position [deg], time [h], speed held [m/s],
course [rad from north], 10 m wind [m/s], true wind angle [rad], significant wave height
[m], added resistance in waves [N], rig thrust [N], leeway [rad], drag of leeway and
rudder [N] and fuel power [W].
"""
struct LegTrace
    lat::Vector{Float64}
    lon::Vector{Float64}
    time::Vector{Float64}
    speed::Vector{Float64}
    course::Vector{Float64}
    wind_speed::Vector{Float64}
    true_wind_angle::Vector{Float64}
    wave_height::Vector{Float64}
    added_resistance::Vector{Float64}
    rig_thrust::Vector{Float64}
    leeway::Vector{Float64}
    balance_drag::Vector{Float64}
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
    trace = LegTrace((Float64[] for _ in 1:13)...)
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
    wave_height, wave_period, wave_from = waves(weather, lat, lon, departure + time)
    heading = wave_heading(wave_from, course)
    condition = SeaCondition(table.table, wind_speed, angle, wave_height, wave_period,
        heading)
    crosswind, headwind = kite_wind(table.table, wind_speed) .* sincos(angle)
    held, flown_power, stowed_power = held_speed(table, speed_index,
        EdgeSample(condition, headwind, crosswind))
    speed = table.speeds[max(held, 1)]
    standing = standing_rig(ship.rig)
    flown = standing === ship.rig || (kite_flying || !isfinite(stowed_power)) &&
            isfinite(flown_power) &&
            kite_aloft(table.table, speed, headwind, crosswind, wave_height)
    added = added_resistance(ship.seakeeping, ship.env, speed, wave_height, wave_period,
        heading)
    force = last(best_trim(ship, flown ? ship.rig : standing, speed, wind_speed, angle))
    balance = HullBalance(ship, speed, force)
    for (field, value) in ((:lat, lat), (:lon, lon), (:time, time), (:speed, speed),
        (:course, course), (:wind_speed, wind_speed), (:true_wind_angle, angle),
        (:wave_height, wave_height), (:added_resistance, added),
        (:rig_thrust, force.thrust), (:leeway, balance.leeway),
        (:balance_drag, balance.drag), (:fuel_power, flown ? flown_power : stowed_power))

        push!(getfield(trace, field), value)
    end
end

"""
    sailing_speed(ship, wind_10m, true_angle)

Highest speed through the water [m/s] at which the rig alone balances the resistance.
"""
function sailing_speed(ship::Ship, wind_10m, true_angle)
    best = 0.0
    for speed in 0.25:0.05:ship.max_speed
        best_thrust(ship, speed, wind_10m, true_angle) <= 0 && (best = speed)
    end
    return best
end
