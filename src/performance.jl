"""
    PerformanceTable

Fuel energy rate of one ship tabulated over speed through the water, 10 m true wind
speed and true wind angle, for fast lookup during routing.
"""
struct PerformanceTable{I}
    "fuel power [W] as a function of (speed [m/s], wind [m/s], true wind angle [rad])"
    fuel_power::I
    speeds::Vector{Float64}
    max_wind::Float64
end

"fuel power stored for infeasible conditions, so interpolation stays finite [W]"
const INFEASIBLE_POWER = 1e12

"""
    PerformanceTable(ship; speeds, winds=0:1.0:30, angles=0:7.5:180)

Tabulate [`fuel_power`](@ref) of `ship`; `speeds` in m/s default to 0.25 m/s steps up to
the ship's maximum speed, `angles` are in degrees.
"""
function PerformanceTable(ship::Ship; speeds=range(1.5, ship.max_speed; step=0.25),
        winds=0:1.0:30, angles=0:7.5:180)
    speeds = collect(Float64, speeds)
    angles_rad = deg2rad.(collect(Float64, angles))
    winds = collect(Float64, winds)
    table = [min(fuel_power(ship, speed, wind, angle), INFEASIBLE_POWER)
             for speed in speeds, wind in winds, angle in angles_rad]
    interpolant = extrapolate(
        interpolate((speeds, winds, angles_rad), table, Gridded(Linear())), Flat())
    return PerformanceTable(interpolant, speeds, last(winds))
end

"""
    lookup(table, speed, wind, angle)

Interpolated fuel power [W], or `Inf` where any neighbouring table entry is infeasible.
"""
function lookup(table::PerformanceTable, speed, wind, angle)
    power = table.fuel_power(speed, min(wind, table.max_wind), angle)
    return power < 1e-3INFEASIBLE_POWER ? power : Inf
end
