# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

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

Values on a grid of three or four knot vectors, interpolated linearly in each dimension and
held flat beyond the grid. Called on as many coordinates or on their
[`KnotWeight`](@ref)s.
"""
struct LinearTable{N}
    knots::NTuple{N, Vector{Float64}}
    values::Array{Float64, N}
end

(table::LinearTable)(coordinates::Real...) =
    table(map(KnotWeight, table.knots, coordinates)...)

function (table::LinearTable{3})(x::KnotWeight, y::KnotWeight, z::KnotWeight)
    (; values) = table
    return x.upper * plane_value(view(values, x.index + 1, :, :), y, z) +
           x.lower * plane_value(view(values, x.index, :, :), y, z)
end

function (table::LinearTable{4})(x::KnotWeight, y::KnotWeight, z::KnotWeight,
        layer::KnotWeight)
    (; values) = table
    return x.upper * layer_value(view(values, x.index + 1, :, :, :), y, z, layer) +
           x.lower * layer_value(view(values, x.index, :, :, :), y, z, layer)
end

"""
    layer_value(values, y, z, layer)

Trilinear interpolation of the three-dimensional array `values` at the
[`KnotWeight`](@ref)s `y`, `z` and `layer` of its dimensions, by [`plane_value`](@ref) on
the two layers around `layer`; its entries are numbers or tuples of numbers.
"""
layer_value(values, y::KnotWeight, z::KnotWeight, layer::KnotWeight) =
    map((upper, lower) -> layer.upper * upper + layer.lower * lower,
        plane_value(values, y, z, layer.index + 1), plane_value(values, y, z, layer.index))

"""
    plane_value(values, y, z, layer...)

Bilinear interpolation of the matrix `values`, or of its `layer` along a third dimension,
at the [`KnotWeight`](@ref)s `y` and `z` of its rows and columns; its entries are numbers
or tuples of numbers.
"""
function plane_value(values, y::KnotWeight, z::KnotWeight, layer...)
    j, k = y.index, z.index
    corners = @inbounds (values[j + 1, k + 1, layer...], values[j + 1, k, layer...],
        values[j, k + 1, layer...], values[j, k, layer...])
    return map((upper_upper, upper_lower, lower_upper, lower_lower) ->
            y.upper * (z.upper * upper_upper + z.lower * upper_lower) +
            y.lower * (z.upper * lower_upper + z.lower * lower_lower), corners...)
end

"""
    PerformanceTable

Propeller thrust a ship needs, tabulated for fast lookup during routing: over (speed
through the water, 10 m true wind, true wind angle, added resistance of waves) with the rig
flown at its best trim and with any kite stowed, the [`standing_rig`](@ref) then at its
best trim, and the added resistance in waves per unit significant wave height squared over
(speed, peak period, wave heading). The trim works against the added resistance as well
as the calm-water one, so a rig with thrust to spare puts it against the waves; waves do
not change the rig forces themselves.
"""
struct PerformanceTable{S}
    ship::S
    "required thrust with the rig flown [N] at (speed [m/s], wind [m/s], angle [rad],
    added resistance [N])"
    flown_thrust::LinearTable{4}
    "required thrust with the kite stowed [N], same grid"
    stowed_thrust::LinearTable{4}
    "power the flown rig draws from the engines [W], same grid"
    rig_power::LinearTable{4}
    "power the rig draws from the engines with the kite stowed [W], same grid"
    stowed_power::LinearTable{4}
    "added resistance over H_s^2 [N/m^2] at (speed [m/s], peak period [s], heading [rad])"
    wave_resistance::LinearTable{3}
    "apparent wind a kite launch needs beyond calm sea, per metre of significant wave height
    [(m/s)/m], at (speed, peak period, wave heading) knots"
    sea_launch_wind::LinearTable{3}
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
    "true wind at a kite's reference height per unit of 10 m wind [-]; zero without a kite"
    kite_wind_factor::Float64
end

"lowest speed of a [`PerformanceTable`](@ref) [m/s]"
const LOWEST_TABLE_SPEED = 1.5

"thrust stored for infeasible conditions, far above what any engine delivers [N]"
const INFEASIBLE_THRUST = 1e12

"""
added resistance of waves at the knots of the trim tables of a [`PerformanceTable`](@ref),
over the calm-water resistance at the ship's top speed [-]; outside them, as the negative
added resistance of following seas, the trim of the nearest knot holds and the propeller
takes up the rest
"""
const ADDED_RESISTANCE_SHARES = [0.0; 2.0 .^ (-6:0)]

"lowest routing speed of any ship [kn]"
const LOWEST_ROUTING_KNOTS = 4.0

"""
    table_speeds(max_speed, routing_speeds)

Speeds [m/s] of a [`PerformanceTable`](@ref): the last `routing_speeds` are equally spaced
from `LOWEST_ROUTING_KNOTS` to `max_speed`, and the same step continues down towards
`LOWEST_TABLE_SPEED`.
"""
function table_speeds(max_speed, routing_speeds)
    lowest = LOWEST_ROUTING_KNOTS * KNOT
    speed_step = (max_speed - lowest) / (routing_speeds - 1)
    below = floor(Int, (lowest - LOWEST_TABLE_SPEED) / speed_step)
    return collect(range(lowest - below * speed_step, max_speed;
        length=routing_speeds + below))
end

"""
    PerformanceTable(ship, assumptions)

Tabulate the thrust of `ship`, at its [`table_speeds`](@ref).
"""
function PerformanceTable(ship::Ship, assumptions::Assumptions)
    speeds = table_speeds(ship.max_speed, ROUTER_SETTINGS[].routing_speeds)
    winds = collect(Float64, 0:1.0:30)
    angles = deg2rad.(collect(Float64, 0:7.5:180))
    periods = collect(Float64, 3:1.0:18)
    headings = deg2rad.(collect(Float64, 0:15:180))
    top_resistance = resistance(ship.hull, ship.env, ship.max_speed;
        coefficients=ship.wave_coefficients)
    trim_grid = (speeds, winds, angles, top_resistance .* ADDED_RESISTANCE_SHARES)
    flown_thrust, rig_power = trim_tables(ship, ship.rig, trim_grid)
    standing = standing_rig(ship.rig)
    stowed_thrust, stowed_power = standing === ship.rig ? (flown_thrust, rig_power) :
                                  trim_tables(ship, standing, trim_grid)
    waves = [added_resistance(ship.seakeeping, ship.env, speed, 1.0, period, heading)
             for speed in speeds, period in periods, heading in headings]
    wind_per_mast_speed = launch_wind_per_mast_speed(ship.rig, assumptions)
    mast_position = launch_mast_position(ship.hull, assumptions)
    sea_winds = [iszero(wind_per_mast_speed) ? 0.0 :
                 wind_per_mast_speed * mast_speed(ship.seakeeping, ship.env, speed, 1.0,
                     period, heading, mast_position)
                 for speed in speeds, period in periods, heading in headings]
    return PerformanceTable(ship, flown_thrust, stowed_thrust, rig_power, stowed_power,
        LinearTable((speeds, periods, headings), waves),
        LinearTable((speeds, periods, headings), sea_winds),
        wear_cost(ship.rig, assumptions),
        cycle_cost(ship.rig, assumptions), handling_hours(ship.rig, assumptions),
        forced_landing_cost(ship.rig, assumptions), speeds, last(winds),
        kite_wind_factor(ship.rig, ship.env))
end

"""
    trim_tables(ship, rig, trim_grid)

Required thrust [N] and rig power [W] of `ship` carrying `rig` at its
[`best_trim`](@ref) over `trim_grid`, the (speed, wind, angle, added resistance) knots.
"""
function trim_tables(ship::Ship, rig, trim_grid)
    trims = [best_trim(ship, rig, speed, wind, angle, added)
             for speed in trim_grid[1], wind in trim_grid[2], angle in trim_grid[3],
             added in trim_grid[4]]
    return LinearTable(trim_grid, min.(first.(trims), INFEASIBLE_THRUST)),
    LinearTable(trim_grid, [force.power for (_, force) in trims])
end

"""
    launch_wind_per_mast_speed(rig, assumptions)

Apparent wind a launch of the kite of `rig` needs per unit of [`mast_speed`](@ref) [-],
scaled so that the reference ship in the reference sea, over headings, needs
`:kite_launch_sea_wind`; zero for a rig without a soft kite.
"""
launch_wind_per_mast_speed(rig, assumptions) = 0.0
launch_wind_per_mast_speed(rig::CombinedRig, assumptions) =
    launch_wind_per_mast_speed(rig.kite, assumptions)
launch_wind_per_mast_speed(::KiteRig{RigidAirframe}, assumptions) = 0.0
launch_wind_per_mast_speed(::KiteRig, assumptions) =
    assumptions[:kite_launch_sea_wind] / reference_mast_speed(assumptions)

"""
    reference_mast_speed(assumptions)

[`mast_speed`](@ref) [m/s] of the reference ship of the extra launch wind in its reference
sea, the mean over headings from following to head waves.
"""
function reference_mast_speed(assumptions::Assumptions)
    hull = Hull(assumptions[:kite_launch_sea_length], assumptions)
    seakeeping = SeakeepingHull(hull, assumptions)
    env = Environment(assumptions)
    position = launch_mast_position(hull, assumptions)
    headings = deg2rad.(0:15:180)
    return sum(heading -> mast_speed(seakeeping, env, assumptions[:kite_launch_sea_speed],
            assumptions[:kite_launch_sea_height], assumptions[:kite_launch_sea_period],
            heading, position), headings) / length(headings)
end

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
handling_hours(::KiteRig{RigidAirframe}, assumptions) =
    assumptions[:rigid_hover_minutes] / 60

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
    extra_launch_wind(table, speed, condition)

Apparent wind [m/s] a kite launch needs beyond calm sea in the sea of `condition`.
"""
extra_launch_wind(table::PerformanceTable, speed, condition::SeaCondition) =
    condition.wave_height * table.sea_launch_wind(KnotWeight(table.speeds, speed),
        condition.wave_period, condition.wave_heading)

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

A [`PerformanceTable`](@ref) at one speed, interpolated linearly over the knots of its
other dimensions.
"""
struct SpeedSlice
    "(flown and stowed thrust [N], flown and stowed rig power [W]) at (wind knot, angle
    knot, added resistance knot)"
    trims::Array{NTuple{4, Float64}, 3}
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
    speed_weight.upper .* selectdim(table.values, 1, speed_weight.index + 1) .+
    speed_weight.lower .* selectdim(table.values, 1, speed_weight.index)

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
    waves = sea_resistance(slice, condition)
    outside = waves - trim_resistance(table, waves)
    flown_thrust, stowed_thrust, rig_power, stowed_power = layer_value(slice.trims, wind,
        angle, KnotWeight(table.flown_thrust.knots[4], waves))
    flown = fuel_power(table, speed, flown_thrust + outside, rig_power)
    table.stowed_thrust === table.flown_thrust && return flown, flown
    stowed = fuel_power(table, speed, stowed_thrust + outside, stowed_power)
    return flown, stowed
end

"""
    sea_resistance(slice, condition)

Added resistance [N] of the waves of the [`SeaCondition`](@ref) `condition` at the speed of
the [`SpeedSlice`](@ref) `slice`.
"""
sea_resistance(slice::SpeedSlice, condition::SeaCondition) =
    condition.wave_height > 0 ?
    condition.wave_height^2 *
    plane_value(slice.wave_resistance, condition.wave_period, condition.wave_heading) : 0.0

"""
    trim_resistance(table, waves)

Added resistance [N] of the trim `table` holds for waves adding `waves` [N]: `waves` held
to the range of the table's added-resistance knots.
"""
function trim_resistance(table::PerformanceTable, waves)
    knots = table.flown_thrust.knots[4]
    return clamp(waves, first(knots), last(knots))
end

edge_fuels(table::PerformanceTable, speed, speed_weight::KnotWeight,
    condition::SeaCondition) =
    edge_fuels(table, speed, SpeedSlice(table, speed_weight), condition)

"""
    kite_wind_factor(rig, env)

True wind at the reference height of a kite per unit of 10 m wind [-]; zero for ships
without a kite.
"""
kite_wind_factor(rig, env) = 0.0
kite_wind_factor(rig::KiteRig, env) = wind_at_height(env, 1.0, rig.reference_height)
kite_wind_factor(rig::CombinedRig, env) = kite_wind_factor(rig.kite, env)

"""
    kite_aloft(table, speed, headwind, crosswind)

Whether a kite can stay up at ship `speed` [m/s] in `headwind` and `crosswind` [m/s]: the
apparent wind is inside its flight limits.
"""
kite_aloft(table::PerformanceTable, speed, headwind, crosswind) =
    kite_aloft(table.ship.rig, speed, headwind, crosswind)
kite_aloft(rig, speed, headwind, crosswind) = false
kite_aloft(rig::CombinedRig, speed, headwind, crosswind) =
    kite_aloft(rig.kite, speed, headwind, crosswind)
kite_aloft(rig::KiteRig, speed, headwind, crosswind) =
    rig.min_flight_wind <= hypot(headwind + speed, crosswind) <= rig.max_wind

"""
    kite_launchable(table, speed, headwind, crosswind, condition, daylight)

Whether a kite can be launched on the ship's course under the arguments of
[`kite_aloft`](@ref), in the sea of `condition`: it can stay up there, the apparent wind
clears the calm-sea launch wind plus the [`extra_launch_wind`](@ref) and is inside the
launch limits, and it is `daylight` or launches run at night too.
"""
kite_launchable(table::PerformanceTable, speed, headwind, crosswind, condition, daylight) =
    kite_launchable(table.ship.rig, speed, headwind, crosswind, condition.wave_height,
        extra_launch_wind(table, speed, condition), daylight)
kite_launchable(rig, speed, headwind, crosswind, wave_height, sea_wind, daylight) = false
kite_launchable(rig::CombinedRig, speed, headwind, crosswind, wave_height, sea_wind,
    daylight) = kite_launchable(rig.kite, speed, headwind, crosswind, wave_height, sea_wind,
    daylight)

function kite_launchable(rig::KiteRig, speed, headwind, crosswind, wave_height, sea_wind,
        daylight)
    apparent = hypot(headwind + speed, crosswind)
    return (daylight || rig.night_launch) && kite_aloft(rig, speed, headwind, crosswind) &&
           wave_height <= rig.launch_max_wave_height &&
           rig.launch_min_wind + sea_wind <= apparent <= rig.launch_max_wind
end

"""
    kite_landable(table, speed, headwind, crosswind, condition)

Whether a kite can land inside the landing limits under the arguments of
[`kite_launchable`](@ref): the apparent wind is within them and the launch wind the sea of
`condition` calls for has not risen past them; a landing outside them is a forced one.
"""
kite_landable(table::PerformanceTable, speed, headwind, crosswind, condition) =
    kite_landable(table.ship.rig, speed, headwind, crosswind, condition.wave_height,
        extra_launch_wind(table, speed, condition))
kite_landable(rig, speed, headwind, crosswind, wave_height, sea_wind) = true
kite_landable(rig::CombinedRig, speed, headwind, crosswind, wave_height, sea_wind) =
    kite_landable(rig.kite, speed, headwind, crosswind, wave_height, sea_wind)
kite_landable(rig::KiteRig, speed, headwind, crosswind, wave_height, sea_wind) =
    wave_height <= rig.landing_max_wave_height &&
    rig.launch_min_wind + sea_wind <= rig.landing_max_wind &&
    hypot(headwind + speed, crosswind) <= rig.landing_max_wind

function fuel_power(table::PerformanceTable, speed, thrust, rig_power)
    (; ship) = table
    delivered = delivered_power(ship.propeller, ship.env, speed, thrust)
    return fuel_power(ship.powertrain,
        delivered + rig_power * ship.powertrain.transmission_efficiency)
end

"""
    RouteTable

A [`PerformanceTable`](@ref) at the speeds the router tries, with the
[`SpeedSlice`](@ref) at each.
"""
struct RouteTable{T <: PerformanceTable}
    table::T
    "routing speeds [m/s], ascending"
    speeds::Vector{Float64}
    slices::Vector{SpeedSlice}
end

"Whether the ship of `table` can fly a kite"
has_kite(table::RouteTable) = table.table.stowed_thrust !== table.table.flown_thrust

"""
    RouteTable(table, speeds=routing_speeds(table))

[`RouteTable`](@ref) of `table` at `speeds` [m/s], ascending.
"""
function RouteTable(table::PerformanceTable, speeds=routing_speeds(table))
    slices = [SpeedSlice(table, KnotWeight(table.speeds, speed)) for speed in speeds]
    return RouteTable(table, speeds, slices)
end

"The speeds of `table` from `LOWEST_ROUTING_KNOTS` up [m/s]"
function routing_speeds(table::PerformanceTable)
    half_step = (table.speeds[end] - table.speeds[end - 1]) / 2
    return filter(>(LOWEST_ROUTING_KNOTS * KNOT - half_step), table.speeds)
end

"""
    held_speed_table(table, knots)

[`RouteTable`](@ref) of `table` for a ship holding `knots` [kn] wherever it can, and the
highest of its [`routing_speeds`](@ref) below that where it cannot, routed with time at
[`HELD_SPEED_TIME_FACTOR`](@ref) times its cost.
"""
function held_speed_table(table::PerformanceTable, knots)
    held = knots * KNOT
    below = filter(speed -> speed < held && !(speed ≈ held), routing_speeds(table))
    return RouteTable(table, [below; held])
end

"factor on the cost of time that makes the router take the fastest speed it is offered [-]"
const HELD_SPEED_TIME_FACTOR = 20

edge_fuels(table::RouteTable, speed_index, condition::SeaCondition) = edge_fuels(
    table.table, table.speeds[speed_index], table.slices[speed_index], condition)
