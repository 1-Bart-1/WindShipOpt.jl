"""
    LegTrace

What happens on each stage of a routed leg: position [deg], time [h], speed [m/s],
course [rad from north], 10 m wind [m/s], true wind angle [rad], significant wave height
[m], added resistance in waves [N], rig thrust [N], leeway [rad], leeway-induced drag [N]
and fuel power [W].
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
    induced_drag::Vector{Float64}
    fuel_power::Vector{Float64}
end

"""
    LegTrace(table, leg, weather, departure)

Re-evaluate the ship models along the path of `leg`, one entry per edge, with the
weather at the start of the edge and the fly-or-stow choice as the routing saw them.
"""
function LegTrace(table::PerformanceTable, leg::Leg, weather, departure)
    (; ship) = table
    edge_count = length(leg.path) - 1
    trace = LegTrace((zeros(edge_count) for _ in 1:13)...)
    for i in 1:edge_count
        lat, lon, time, _ = leg.path[i]
        next_lat, next_lon, _, speed = leg.path[i + 1]
        course = bearing(lat, lon, next_lat, next_lon)
        east, north = wind(weather, lat, lon, departure + time)
        wind_speed = hypot(east, north)
        angle = true_wind_angle(east, north, wind_speed, course)
        wave_height, wave_period, wave_from = waves(weather, lat, lon, departure + time)
        heading = wave_heading(wave_from, course)
        added = added_resistance(ship.seakeeping, ship.env, speed, wave_height, wave_period,
            heading)
        point = lookup(table, speed, wind_speed, angle, wave_height, wave_period, heading)
        force = point.flying ? last(best_trim(ship, speed, wind_speed, angle)) : NO_RIG_FORCE
        leeway, induced_drag = leeway_drag(ship.hull, ship.env, speed, abs(force.side))
        trace.lat[i], trace.lon[i], trace.time[i], trace.speed[i] = lat, lon, time, speed
        trace.course[i], trace.wind_speed[i] = course, wind_speed
        trace.true_wind_angle[i], trace.rig_thrust[i] = angle, force.thrust
        trace.leeway[i], trace.induced_drag[i] = leeway, induced_drag
        trace.wave_height[i], trace.added_resistance[i] = wave_height, added
        trace.fuel_power[i] = point.fuel_power
    end
    return trace
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
