"""
    PerformanceTable

Propeller thrust a ship needs, tabulated for fast lookup during routing: in calm water
over (speed through the water, 10 m true wind, true wind angle) with the best rig trim,
and the added resistance in waves per unit significant wave height squared over (speed,
peak period, wave heading). The two add up, assuming waves do not change the rig forces.
"""
struct PerformanceTable{S, C, W}
    ship::S
    "required thrust [N] at (speed [m/s], wind [m/s], true wind angle [rad])"
    calm_thrust::C
    "added resistance over H_s^2 [N/m^2] at (speed [m/s], peak period [s], heading [rad])"
    wave_resistance::W
    speeds::Vector{Float64}
    max_wind::Float64
end

"thrust stored for infeasible conditions, so interpolation stays finite [N]"
const INFEASIBLE_THRUST = 1e9

"""
    PerformanceTable(ship; speeds, winds=0:1.0:30, angles=0:7.5:180, periods=3:1.0:18,
                     headings=0:15:180)

Tabulate the thrust of `ship`; `speeds` in m/s default to 0.25 m/s steps up to the ship's
maximum speed, `angles` and `headings` are in degrees, `periods` in seconds.
"""
function PerformanceTable(ship::Ship; speeds=range(1.5, ship.max_speed; step=0.25),
        winds=0:1.0:30, angles=0:7.5:180, periods=3:1.0:18, headings=0:15:180)
    speeds = collect(Float64, speeds)
    winds = collect(Float64, winds)
    angles = deg2rad.(collect(Float64, angles))
    periods = collect(Float64, periods)
    headings = deg2rad.(collect(Float64, headings))
    calm = [min(best_thrust(ship, speed, wind, angle), INFEASIBLE_THRUST)
            for speed in speeds, wind in winds, angle in angles]
    waves = [added_resistance(ship.seakeeping, ship.env, speed, 1.0, period, heading)
             for speed in speeds, period in periods, heading in headings]
    calm_thrust = extrapolate(interpolate((speeds, winds, angles), calm, Gridded(Linear())),
        Flat())
    wave_resistance = extrapolate(
        interpolate((speeds, periods, headings), waves, Gridded(Linear())), Flat())
    return PerformanceTable(ship, calm_thrust, wave_resistance, speeds, last(winds))
end

"""
    lookup(table, speed, wind, angle, wave_height, wave_period, wave_heading)

Fuel power [W] from the tabulated thrust, or `Inf` where the rig limits are exceeded
nearby in the table or the installed power is not enough.
"""
function lookup(table::PerformanceTable, speed, wind, angle, wave_height=0.0,
        wave_period=0.0, wave_heading=0.0)
    thrust = table.calm_thrust(speed, min(wind, table.max_wind), angle)
    thrust < 1e-3INFEASIBLE_THRUST || return Inf
    if wave_height > 0
        thrust += wave_height^2 * table.wave_resistance(speed, wave_period, wave_heading)
    end
    (; ship) = table
    return fuel_power(ship.powertrain, delivered_power(ship.propeller, ship.env, speed, thrust))
end

max_knots(table::PerformanceTable) = floor(Int, last(table.speeds) / KNOT)
