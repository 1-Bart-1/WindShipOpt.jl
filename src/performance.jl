"""
    PerformanceTable

Propeller thrust a ship needs, tabulated for fast lookup during routing: in calm water
over (speed through the water, 10 m true wind, true wind angle) with the rig flown at its
best trim and with the rig stowed, and the added resistance in waves per unit significant
wave height squared over (speed, peak period, wave heading). Calm thrust and wave
resistance add up, assuming waves do not change the rig forces.
"""
struct PerformanceTable{S, C, W}
    ship::S
    "required thrust with the rig flown [N] at (speed [m/s], wind [m/s], angle [rad])"
    flown_thrust::C
    "required thrust with the rig stowed [N], same grid"
    stowed_thrust::C
    "added resistance over H_s^2 [N/m^2] at (speed [m/s], peak period [s], heading [rad])"
    wave_resistance::W
    "wear cost of flying the rig [USD/h]"
    wear_cost::Float64
    speeds::Vector{Float64}
    max_wind::Float64
end

"thrust stored for infeasible conditions, so interpolation stays finite [N]"
const INFEASIBLE_THRUST = 1e9

"""
    PerformanceTable(ship, assumptions; speeds, winds=0:1.0:30, angles=0:7.5:180,
                     periods=3:1.0:18, headings=0:15:180)

Tabulate the thrust of `ship`; `speeds` in m/s default to 0.25 m/s steps up to the ship's
maximum speed, `angles` and `headings` are in degrees, `periods` in seconds.
"""
function PerformanceTable(ship::Ship, assumptions::Assumptions;
        speeds=range(1.5, ship.max_speed; step=0.25), winds=0:1.0:30, angles=0:7.5:180,
        periods=3:1.0:18, headings=0:15:180)
    speeds = collect(Float64, speeds)
    winds = collect(Float64, winds)
    angles = deg2rad.(collect(Float64, angles))
    periods = collect(Float64, periods)
    headings = deg2rad.(collect(Float64, headings))
    flown = [min(best_thrust(ship, speed, wind, angle), INFEASIBLE_THRUST)
             for speed in speeds, wind in winds, angle in angles]
    stowed = [min(stowed_thrust(ship, speed, wind, angle), INFEASIBLE_THRUST)
              for speed in speeds, wind in winds, angle in angles]
    waves = [added_resistance(ship.seakeeping, ship.env, speed, 1.0, period, heading)
             for speed in speeds, period in periods, heading in headings]
    calm_grid = (speeds, winds, angles)
    return PerformanceTable(ship,
        extrapolate(interpolate(calm_grid, flown, Gridded(Linear())), Flat()),
        extrapolate(interpolate(calm_grid, stowed, Gridded(Linear())), Flat()),
        extrapolate(interpolate((speeds, periods, headings), waves, Gridded(Linear())),
            Flat()),
        wear_cost(ship.rig, assumptions), speeds, last(winds))
end

"""
    stowed_thrust(ship, speed, wind_10m, true_angle)

Required thrust [N] with a kite stowed; a wing cannot be stowed and stays at its best trim.
"""
stowed_thrust(ship::Ship{KiteRig}, speed, wind_10m, true_angle) =
    required_thrust(ship, speed, wind_10m, true_angle, NO_RIG_FORCE)
stowed_thrust(ship::Ship, speed, wind_10m, true_angle) =
    best_thrust(ship, speed, wind_10m, true_angle)

"""
    OperatingPoint

Fuel power [W] at a tabulated condition and whether the rig is flown there.
"""
struct OperatingPoint
    fuel_power::Float64
    flying::Bool
end

"""
    lookup(table, speed, wind, angle, wave_height, wave_period, wave_heading)

Cheapest [`OperatingPoint`](@ref): the rig is flown only where the fuel it saves is worth
more than its wear. Fuel power is `Inf` where neither option is feasible.
"""
function lookup(table::PerformanceTable, speed, wind, angle, wave_height=0.0,
        wave_period=0.0, wave_heading=0.0)
    wind = min(wind, table.max_wind)
    waves = wave_height > 0 ?
            wave_height^2 * table.wave_resistance(speed, wave_period, wave_heading) : 0.0
    flown = fuel_power(table, speed, table.flown_thrust(speed, wind, angle) + waves)
    stowed = fuel_power(table, speed, table.stowed_thrust(speed, wind, angle) + waves)
    price = table.ship.fuel.price * 3600
    flown_cost = flown * price + table.wear_cost
    return flown_cost < stowed * price ? OperatingPoint(flown, true) :
           OperatingPoint(stowed, false)
end

function fuel_power(table::PerformanceTable, speed, thrust)
    thrust < 1e-3INFEASIBLE_THRUST || return Inf
    (; ship) = table
    return fuel_power(ship.powertrain, delivered_power(ship.propeller, ship.env, speed, thrust))
end

max_knots(table::PerformanceTable) = floor(Int, last(table.speeds) / KNOT)
