"""
    KnotWeight

Interval of a knot vector that holds a value: the index of its lower knot and the
linear interpolation weights of the lower and the upper knot.
"""
struct KnotWeight
    index::Int
    lower::Float64
    upper::Float64
end

"""
    KnotWeight(knots, value)

Weights of `value` in the sorted `knots`, held at the end knot beyond the grid; a value
on an interior knot lies at the top of the interval below it.
"""
function KnotWeight(knots::Vector{Float64}, value)
    value = min(max(first(knots), value), last(knots))
    i = interval_index(knots, value)
    lower, upper = knots[i], knots[i + 1]
    fraction = (value - lower) / (upper - lower)
    return KnotWeight(i, 1 - fraction, fraction)
end

"""
    interval_index(knots, value)

Number of `knots` below `value`, clamped to the intervals of `knots`: the index
`searchsortedfirst(knots, value) - 1` would give.
"""
function interval_index(knots::Vector{Float64}, value)
    last_interval = length(knots) - 1
    spacing = (last(knots) - first(knots)) / last_interval
    i = clamp(unsafe_trunc(Int, (value - first(knots)) / spacing) + 1, 1, last_interval)
    while i < last_interval && knots[i + 1] < value
        i += 1
    end
    while i > 1 && knots[i] >= value
        i -= 1
    end
    return i
end

"""
    LinearTable

Values on a three-dimensional grid of knot vectors, interpolated trilinearly and held
flat beyond the grid. Called on three coordinates or on their [`KnotWeight`](@ref)s.
"""
struct LinearTable
    knots::NTuple{3, Vector{Float64}}
    values::Array{Float64, 3}
end

(table::LinearTable)(x, y, z) = table(KnotWeight(table.knots[1], x),
    KnotWeight(table.knots[2], y), KnotWeight(table.knots[3], z))

function (table::LinearTable)(x::KnotWeight, y::KnotWeight, z::KnotWeight)
    (; values) = table
    return x.upper * plane_value(view(values, x.index + 1, :, :), y, z) +
           x.lower * plane_value(view(values, x.index, :, :), y, z)
end

"""
    plane_value(values, y, z)

Bilinear interpolation of the matrix `values` at the [`KnotWeight`](@ref)s `y` and `z`
of its rows and columns; its entries are numbers or tuples of numbers.
"""
plane_value(values, y::KnotWeight, z::KnotWeight) = y.upper .*
    line_value(values, y.index + 1, z) .+ y.lower .* line_value(values, y.index, z)

line_value(values, j, z::KnotWeight) =
    @inbounds z.upper .* values[j, z.index + 1] .+ z.lower .* values[j, z.index]

"""
    PerformanceTable

Propeller thrust a ship needs, tabulated for fast lookup during routing: in calm water
over (speed through the water, 10 m true wind, true wind angle) with the rig flown at its
best trim and with any kite stowed, the [`standing_rig`](@ref) then at its best trim, and
the added resistance in waves per unit significant wave height squared over (speed, peak
period, wave heading). Calm thrust and wave resistance add up, assuming waves do not
change the rig forces.
"""
struct PerformanceTable{S}
    ship::S
    "required thrust with the rig flown [N] at (speed [m/s], wind [m/s], angle [rad])"
    flown_thrust::LinearTable
    "required thrust with the kite stowed [N], same grid"
    stowed_thrust::LinearTable
    "power the flown rig draws from the engines [W], same grid"
    rig_power::LinearTable
    "power the rig draws from the engines with the kite stowed [W], same grid"
    stowed_power::LinearTable
    "added resistance over H_s^2 [N/m^2] at (speed [m/s], peak period [s], heading [rad])"
    wave_resistance::LinearTable
    "wear cost of flying the rig [USD/h]"
    wear_cost::Float64
    "cost of one launch and landing of a kite [USD]"
    cycle_cost::Float64
    "time one launch and landing of a kite gives no force on the ship [h]"
    handling_hours::Float64
    "expected cost of one landing outside the landing limits [USD]"
    forced_landing_cost::Float64
    speeds::Vector{Float64}
    max_wind::Float64
    "highest significant wave height at which a kite stays up [m]"
    max_wave_height::Float64
end

"thrust stored for infeasible conditions [N]"
const INFEASIBLE_THRUST = 1e9

"""
    PerformanceTable(ship, assumptions)

Tabulate the thrust of `ship`.
"""
function PerformanceTable(ship::Ship, assumptions::Assumptions)
    speeds = collect(Float64, range(1.5, ship.max_speed; step=0.25))
    winds = collect(Float64, 0:1.0:30)
    angles = deg2rad.(collect(Float64, 0:7.5:180))
    periods = collect(Float64, 3:1.0:18)
    headings = deg2rad.(collect(Float64, 0:15:180))
    calm_grid = (speeds, winds, angles)
    flown_thrust, rig_power = trim_tables(ship, ship.rig, calm_grid)
    standing = standing_rig(ship.rig)
    stowed_thrust, stowed_power = standing === ship.rig ? (flown_thrust, rig_power) :
                                  trim_tables(ship, standing, calm_grid)
    waves = [added_resistance(ship.seakeeping, ship.env, speed, 1.0, period, heading)
             for speed in speeds, period in periods, heading in headings]
    return PerformanceTable(ship, flown_thrust, stowed_thrust, rig_power, stowed_power,
        LinearTable((speeds, periods, headings), waves), wear_cost(ship.rig, assumptions),
        cycle_cost(ship.rig, assumptions), handling_hours(ship.rig, assumptions),
        forced_landing_cost(ship.rig, assumptions), speeds, last(winds),
        max_wave_height(ship.rig, assumptions))
end

"""
    trim_tables(ship, rig, calm_grid)

Required thrust [N] and rig power [W] of `ship` carrying `rig` at its
[`best_trim`](@ref) over `calm_grid`, the (speed, wind, angle) knots.
"""
function trim_tables(ship::Ship, rig, calm_grid)
    trims = [best_trim(ship, rig, speed, wind, angle)
             for speed in calm_grid[1], wind in calm_grid[2], angle in calm_grid[3]]
    return LinearTable(calm_grid, min.(first.(trims), INFEASIBLE_THRUST)),
    LinearTable(calm_grid, [force.power for (_, force) in trims])
end

"""
    max_wave_height(rig, assumptions)

Highest significant wave height [m] at which a kite stays up; wings and rotors stand in any
sea.
"""
max_wave_height(rig, assumptions) = Inf
max_wave_height(::KiteRig, assumptions) = assumptions[:kite_max_wave_height]
max_wave_height(rig::CombinedRig, assumptions) = max_wave_height(rig.kite, assumptions)

"""
    handling_hours(rig, assumptions)

Time [h] one launch, with its retries, and one landing of a kite give no force on the ship;
zero for other rigs.
"""
handling_hours(rig, assumptions) = 0.0
handling_hours(rig::CombinedRig, assumptions) = handling_hours(rig.kite, assumptions)
handling_hours(::KiteRig, assumptions) =
    ((1 + assumptions[:kite_launch_retry_probability]) * assumptions[:kite_launch_minutes] +
     assumptions[:kite_landing_minutes]) / 60

"""
    OperatingPoint

Fuel power [W] at a tabulated condition and whether the rig is flown there.
"""
struct OperatingPoint
    fuel_power::Float64
    flying::Bool
end

"""
    SeaCondition(table, wind, angle, wave_height, wave_period, wave_heading)

Wind and waves on one course as [`KnotWeight`](@ref)s on the grids of the
[`PerformanceTable`](@ref) `table`: 10 m true wind [m/s], true wind angle [rad],
significant wave height [m], peak period [s] and wave heading [rad].
"""
struct SeaCondition
    wind::KnotWeight
    angle::KnotWeight
    wave_height::Float64
    wave_period::KnotWeight
    wave_heading::KnotWeight
end

function SeaCondition(table::PerformanceTable, wind, angle, wave_height, wave_period,
        wave_heading)
    _, winds, angles = table.flown_thrust.knots
    _, periods, headings = table.wave_resistance.knots
    return SeaCondition(KnotWeight(winds, min(wind, table.max_wind)),
        KnotWeight(angles, angle), wave_height, KnotWeight(periods, wave_period),
        KnotWeight(headings, wave_heading))
end

"""
    lookup(table, speed, wind, angle, wave_height=0.0, wave_period=0.0, wave_heading=0.0)

Cheapest [`OperatingPoint`](@ref): a kite is flown only where the sea allows and the fuel
it saves is worth more than its wear; wings and rotors always stand and draw their power.
Fuel power is `Inf` where no option is feasible.
"""
function lookup(table::PerformanceTable, speed, wind, angle, wave_height=0.0,
        wave_period=0.0, wave_heading=0.0)
    condition = SeaCondition(table, wind, angle, wave_height, wave_period, wave_heading)
    flown, stowed = edge_fuels(table, speed, KnotWeight(table.speeds, speed), condition)
    flown === stowed && return OperatingPoint(flown, false)
    price = table.ship.fuel.price * 3600
    return flown * price + table.wear_cost < stowed * price ? OperatingPoint(flown, true) :
           OperatingPoint(stowed, false)
end

"""
    SpeedSlice

A [`PerformanceTable`](@ref) at one speed, interpolated bilinearly over the knots of its
other two dimensions.
"""
struct SpeedSlice
    "(flown and stowed thrust [N], flown and stowed rig power [W]) at (wind knot, angle
    knot)"
    calm::Matrix{NTuple{4, Float64}}
    "added resistance over H_s^2 [N/m^2] at (period knot, heading knot)"
    wave_resistance::Matrix{Float64}
end

"""
    SpeedSlice(table, speed_weight)

[`SpeedSlice`](@ref) of `table` at the speed of `speed_weight` on `table.speeds`.
"""
SpeedSlice(table::PerformanceTable, speed_weight::KnotWeight) = SpeedSlice(
    tuple.(speed_plane(table.flown_thrust, speed_weight),
        speed_plane(table.stowed_thrust, speed_weight),
        speed_plane(table.rig_power, speed_weight),
        speed_plane(table.stowed_power, speed_weight)),
    speed_plane(table.wave_resistance, speed_weight))

"""
    speed_plane(table, speed_weight)

Values of `table` at the speed of `speed_weight` on the knots of its other two
dimensions.
"""
speed_plane(table::LinearTable, speed_weight::KnotWeight) =
    speed_weight.upper .* table.values[speed_weight.index + 1, :, :] .+
    speed_weight.lower .* table.values[speed_weight.index, :, :]

"""
    edge_fuels(table, speed, slice, condition)
    edge_fuels(table, speed, speed_weight, condition)
    edge_fuels(route_table, speed_index, condition)

Fuel power [W] with the rig flown and with any kite stowed at `speed` [m/s] from its
[`SpeedSlice`](@ref), from its [`KnotWeight`](@ref) on `table.speeds`, or at routing speed
number `speed_index` of a [`RouteTable`](@ref); the same value for a rig without a kite,
which always stands, and `Inf` for a kite up in too high a sea.
"""
function edge_fuels(table::PerformanceTable, speed, slice::SpeedSlice,
        condition::SeaCondition)
    (; wind, angle, wave_height) = condition
    waves = wave_height > 0 ? wave_height^2 * plane_value(slice.wave_resistance,
        condition.wave_period, condition.wave_heading) : 0.0
    flown_thrust, stowed_thrust, rig_power, stowed_power = plane_value(slice.calm, wind,
        angle)
    flown = fuel_power(table, speed, flown_thrust + waves, rig_power)
    table.stowed_thrust === table.flown_thrust && return flown, flown
    stowed = fuel_power(table, speed, stowed_thrust + waves, stowed_power)
    return (wave_height > table.max_wave_height ? Inf : flown), stowed
end

edge_fuels(table::PerformanceTable, speed, speed_weight::KnotWeight,
    condition::SeaCondition) =
    edge_fuels(table, speed, SpeedSlice(table, speed_weight), condition)

"""
    kite_wind(table, wind_10m)

True wind speed [m/s] at the reference height of a kite for a 10 m wind `wind_10m`
[m/s]; zero for ships without a kite.
"""
kite_wind(table::PerformanceTable, wind_10m) = kite_wind(table.ship.rig, table, wind_10m)
kite_wind(rig, table, wind_10m) = 0.0
kite_wind(rig::KiteRig, table, wind_10m) =
    wind_at_height(table.ship.env, wind_10m, rig.reference_height)
kite_wind(rig::CombinedRig, table, wind_10m) = kite_wind(rig.kite, table, wind_10m)

"""
    kite_aloft(table, speed, headwind, crosswind, wave_height)

Whether a kite can stay up at ship `speed` [m/s] in significant wave height `wave_height`
[m], from the components of the true wind at its reference height from ahead and from abeam
[m/s]: the apparent wind carries its weight and neither wind nor sea exceeds the stay-up
limits; never for ships without a kite.
"""
kite_aloft(table::PerformanceTable, speed, headwind, crosswind, wave_height) =
    kite_aloft(table.ship.rig, table, speed, headwind, crosswind, wave_height)
kite_aloft(rig, table, speed, headwind, crosswind, wave_height) = false
kite_aloft(rig::CombinedRig, table, speed, headwind, crosswind, wave_height) =
    kite_aloft(rig.kite, table, speed, headwind, crosswind, wave_height)

function kite_aloft(rig::KiteRig, table, speed, headwind, crosswind, wave_height)
    apparent = hypot(headwind + speed, crosswind)
    return wave_height <= table.max_wave_height &&
           rig.min_flight_wind <= apparent <= rig.max_wind
end

"""
    kite_launchable(table, speed, headwind, crosswind, wave_height, daylight)

Whether a kite can be launched on the ship's course under the arguments of
[`kite_aloft`](@ref): it can stay up there, wind and sea are inside the launch limits, and
it is `daylight` or launches run at night too.
"""
kite_launchable(table::PerformanceTable, speed, headwind, crosswind, wave_height,
    daylight) = kite_launchable(table.ship.rig, table, speed, headwind, crosswind,
    wave_height, daylight)
kite_launchable(rig, table, speed, headwind, crosswind, wave_height, daylight) = false
kite_launchable(rig::CombinedRig, table, speed, headwind, crosswind, wave_height,
    daylight) = kite_launchable(rig.kite, table, speed, headwind, crosswind, wave_height,
    daylight)

function kite_launchable(rig::KiteRig, table, speed, headwind, crosswind, wave_height,
        daylight)
    apparent = hypot(headwind + speed, crosswind)
    return (daylight || rig.night_launch) &&
           kite_aloft(rig, table, speed, headwind, crosswind, wave_height) &&
           wave_height <= rig.launch_max_wave_height &&
           rig.launch_min_wind <= apparent <= rig.launch_max_wind
end

"""
    kite_landable(table, speed, headwind, crosswind, wave_height)

Whether a kite can land inside the landing limits under the arguments of
[`kite_aloft`](@ref); a landing outside them is a forced one.
"""
kite_landable(table::PerformanceTable, speed, headwind, crosswind, wave_height) =
    kite_landable(table.ship.rig, speed, headwind, crosswind, wave_height)
kite_landable(rig, speed, headwind, crosswind, wave_height) = true
kite_landable(rig::CombinedRig, speed, headwind, crosswind, wave_height) =
    kite_landable(rig.kite, speed, headwind, crosswind, wave_height)
kite_landable(rig::KiteRig, speed, headwind, crosswind, wave_height) =
    wave_height <= rig.landing_max_wave_height &&
    hypot(headwind + speed, crosswind) <= rig.landing_max_wind

function fuel_power(table::PerformanceTable, speed, thrust, rig_power)
    thrust < 1e-3INFEASIBLE_THRUST || return Inf
    (; ship) = table
    delivered = delivered_power(ship.propeller, ship.env, speed, thrust)
    return fuel_power(ship.powertrain,
        delivered + rig_power * ship.powertrain.transmission_efficiency)
end

"""
    FuelBound

Lower bound on the fuel power [`lookup`](@ref) returns at each of a set of speeds, from
the least calm thrust and added resistance over the cells of the grids of a
[`PerformanceTable`](@ref).
"""
struct FuelBound
    "fuel power [W] that no larger thrust undercuts, per (thrust step, speed)"
    fuel_power::Matrix{Float64}
    "least calm thrust [N] per (speed, wind cell) over all angles and lower wind cells"
    least_calm_thrust::Matrix{Float64}
    "least added resistance over H_s^2 [N/m^2] per speed over all wave cells"
    least_wave_resistance::Vector{Float64}
end

"thrust step of the fuel power in a [`FuelBound`](@ref) [N]"
const BOUND_THRUST_STEP = 500.0

"""
    FuelBound(table, speeds)

[`FuelBound`](@ref) of `table` at `speeds` [m/s].
"""
function FuelBound(table::PerformanceTable, speeds)
    speed_weights = [KnotWeight(table.speeds, speed) for speed in speeds]
    _, winds, angles = table.flown_thrust.knots
    _, periods, headings = table.wave_resistance.knots
    calm = [min(cell_floor(table.flown_thrust, weight, j, k),
                cell_floor(table.stowed_thrust, weight, j, k))
            for weight in speed_weights, j in 1:(length(winds) - 1),
                k in 1:(length(angles) - 1)]
    waves = [cell_floor(table.wave_resistance, weight, j, k)
             for weight in speed_weights, j in 1:(length(periods) - 1),
                 k in 1:(length(headings) - 1)]
    rig_power = min(0.0, value_floor(table.rig_power.values),
        value_floor(table.stowed_power.values))
    thrusts = 0:BOUND_THRUST_STEP:(1e-3INFEASIBLE_THRUST)
    fuel = [(1 - 1e-9) * fuel_power(table, speed, thrust, rig_power)
            for thrust in thrusts, speed in speeds]
    least_calm = accumulate(min, dropdims(minimum(calm; dims=3); dims=3); dims=2)
    return FuelBound(fuel, least_calm, vec(minimum(waves; dims=(2, 3))))
end

"""
    value_floor(values)

Least of `values`, lowered by the rounding error a linear interpolation between them can
make.
"""
value_floor(values) = minimum(values) - 1e-9maximum(abs, values)

"""
    cell_floor(table, speed_weight, j, k)

Least value of `table` at the speed of `speed_weight` over the corners of cell (`j`,
`k`) of the other two dimensions, lowered by the rounding error of interpolating there.
"""
function cell_floor(table::LinearTable, speed_weight::KnotWeight, j, k)
    i = speed_weight.index
    corners = view(table.values, i:(i + 1), j:(j + 1), k:(k + 1))
    least = minimum(
        speed_weight.upper * corners[2, y, z] + speed_weight.lower * corners[1, y, z]
        for y in 1:2, z in 1:2)
    return least - 1e-9maximum(abs, corners)
end

"""
    bound_fuel_power(bound, speed_index, thrust)

Fuel power [W] that no thrust above `thrust` [N] undercuts at speed number `speed_index`
of `bound`.
"""
function bound_fuel_power(bound::FuelBound, speed_index, thrust)
    thrust >= 2BOUND_THRUST_STEP || return bound.fuel_power[1, speed_index]
    knot = min(floor(Int, thrust * (1 / BOUND_THRUST_STEP)), size(bound.fuel_power, 1))
    return bound.fuel_power[knot, speed_index]
end

max_knots(table::PerformanceTable) = floor(Int, last(table.speeds) / KNOT)

"""
    RouteTable

A [`PerformanceTable`](@ref) at the speeds the router tries, with the
[`SpeedSlice`](@ref) and the [`FuelBound`](@ref) at each.
"""
struct RouteTable{T <: PerformanceTable}
    table::T
    "routing speeds [m/s], ascending"
    speeds::Vector{Float64}
    slices::Vector{SpeedSlice}
    bound::FuelBound
end

"""
    RouteTable(table, speeds)

[`RouteTable`](@ref) of `table` at whole knots from 4 up to the ship's maximum speed, or at
the given `speeds` [m/s], ascending.
"""
function RouteTable(table::PerformanceTable,
        speeds=collect(Float64, (4:max_knots(table)) .* KNOT))
    slices = [SpeedSlice(table, KnotWeight(table.speeds, speed)) for speed in speeds]
    return RouteTable(table, speeds, slices, FuelBound(table, speeds))
end

"""
    held_speed_table(table, knots)

[`RouteTable`](@ref) of `table` for a ship holding `knots` [kn] wherever it can, and the
highest whole knot below that where it cannot, routed with time at
[`HELD_SPEED_TIME_FACTOR`](@ref) times its cost.
"""
held_speed_table(table::PerformanceTable, knots) =
    RouteTable(table, unique(KNOT .* [4:floor(Int, knots); knots]))

"factor on the cost of time that makes the router take the fastest speed it is offered [-]"
const HELD_SPEED_TIME_FACTOR = 20

edge_fuels(table::RouteTable, speed_index, condition::SeaCondition) = edge_fuels(
    table.table, table.speeds[speed_index], table.slices[speed_index], condition)
