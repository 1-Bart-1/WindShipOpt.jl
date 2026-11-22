# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""
    wind_at_height(env, wind_10m, height)

Power-law wind speed [m/s] at `height` [m] from the 10 m wind speed.
"""
wind_at_height(env::Environment, wind_10m, height) =
    wind_10m * (height / 10)^env.shear_exponent

"""
    apparent_wind(true_speed, true_angle, ship_speed)

Apparent wind speed [m/s] and angle off the bow [rad, 0..π] for a true wind of
`true_speed` [m/s] coming from `true_angle` [rad] off the bow.
"""
function apparent_wind(true_speed, true_angle, ship_speed)
    ahead = true_speed * cos(true_angle) + ship_speed
    abeam = true_speed * sin(true_angle)
    return hypot(ahead, abeam), atan(abeam, ahead)
end

"""
    RigForce

Rig force on the ship in the ship frame: forward thrust [N], side force [N], heeling
moment about the waterline [N m], yaw moment about midship [N m], positive when the side
force acts forward of midship, and the power the rig draws from the engines [W].
"""
struct RigForce
    thrust::Float64
    side::Float64
    heeling_moment::Float64
    yaw_moment::Float64
    power::Float64
end

RigForce(thrust, side, heeling_moment, yaw_moment) =
    RigForce(thrust, side, heeling_moment, yaw_moment, 0.0)

const NO_RIG_FORCE = RigForce(0.0, 0.0, 0.0, 0.0)

"force of a setting the rig cannot hold, which no trim search keeps"
const UNREACHABLE_RIG_FORCE = RigForce(-Inf, 0.0, 0.0, 0.0)

"sum of two rig forces acting on one ship, field by field"
Base.:+(a::RigForce, b::RigForce) = RigForce(a.thrust + b.thrust, a.side + b.side,
    a.heeling_moment + b.heeling_moment, a.yaw_moment + b.yaw_moment, a.power + b.power)

"rig force scaled by a share [-], field by field"
Base.:*(share::Real, force::RigForce) = RigForce(share * force.thrust, share * force.side,
    share * force.heeling_moment, share * force.yaw_moment, share * force.power)

"""
    TrimRange

Interval from `low` to `high` of one continuous trim variable of a rig, of the family of
settings numbered `branch`, scanned at `points` evenly spaced values before its best value
is refined.
"""
struct TrimRange
    low::Float64
    high::Float64
    points::Int
    branch::Int
end

"""
    centre_wind(rig, env, wind_10m, true_angle, ship_speed)

Height of the centre of effort of a deck rig of wings or rotors above the waterline [m],
and the apparent wind speed [m/s] and angle [rad] there.
"""
function centre_wind(rig, env::Environment, wind_10m, true_angle, ship_speed)
    centre_height = rig_height(rig)
    wind = wind_at_height(env, wind_10m, centre_height)
    return centre_height, apparent_wind(wind, true_angle, ship_speed)...
end

"""
    array_factor(count, spacing, amplitude, decay)

Thrust of `count` units in a row over `count` times that of one unit alone, for units
`spacing` sizes apart (diameters or chords): 1 - (1 - 1/count) amplitude exp(-spacing /
decay), fitted to CFD and wind-tunnel data averaged over wind angles.
"""
array_factor(count, spacing, amplitude, decay) =
    1 - (1 - 1 / count) * amplitude * exp(-spacing / decay)

"""
    WingRig

Set of identical rigid wing sails on deck: plain wing sails, or suction sails whose fan
holds the flow attached to a higher lift.
"""
Base.@kwdef struct WingRig
    "`:wing` for wing sails, `:suction` for suction sails, naming their assumptions"
    unit::Symbol = :wing
    "number of wings"
    count::Int
    "columns the wings stand in, one on the centreline or two abreast [-]"
    columns::Int
    "planform area of one wing [m^2]"
    area::Float64
    "height of one wing [m]"
    height::Float64
    "height of the wing foot above the waterline [m]"
    foot_height::Float64
    "centre of effort forward of midship [m]"
    centre_position::Float64
    "distance of each column from the centreline [m]"
    column_offset::Float64
    "effective aspect ratio including the deck mirror effect [-]"
    effective_aspect_ratio::Float64
    max_lift_coefficient::Float64
    profile_drag_coefficient::Float64
    "drag coefficient per lift coefficient squared, above the profile drag [-]"
    lift_drag_factor::Float64
    "normal-force coefficient of the stalled wing across the flow [-]"
    stalled_drag_coefficient::Float64
    interference_factor::Float64
    "fan power per m^2 of wing at the highest apparent wind the wings work in [W/m^2]"
    fan_power_per_area::Float64 = 0.0
    "highest apparent wind the wings work in, above which they lie down [m/s]"
    max_wind::Float64 = Inf
    "share of their wind load the wings keep in the shadow of deck cargo [-]"
    shadow_share::Float64 = 1.0
    "apparent wind angle off the bow beyond which deck cargo shades the wings [rad]"
    shadow_angle::Float64 = π
    "wings watched by a camera system for the view they hide from the bridge [-]"
    camera_units::Int = 0
end

"""
    deck_layout(total_area, unit, hull, assumptions, forward_reserve, columns, in_column)

Layout of `columns` times `in_column` identical `unit`s, `:wing`, `:suction` or `:rotor`, of
`total_area` [m^2] on `hull`: [`column_layout`](@ref) where no containers stand on its deck;
there one unit at the bow, [`bow_layout`](@ref), or rotors in pairs above the stacks,
[`raised_layout`](@ref), and `nothing` for other units in pairs.
"""
function deck_layout(total_area, unit, hull::Hull, assumptions::Assumptions,
        forward_reserve, columns, in_column)
    hull.deck_cargo_height > 0 || return column_layout(columns, in_column, total_area, unit,
        hull, assumptions, forward_reserve)
    columns == 1 && return bow_layout(total_area, unit, hull, assumptions)
    unit == :rotor || return nothing
    return raised_layout(in_column, total_area, hull, assumptions, forward_reserve)
end

"""
    unit_size(total_area, count, unit, assumptions)

Height [m] and width [m] of each of `count` identical `unit`s of `total_area` [m^2] in all,
at the unit's aspect ratio.
"""
function unit_size(total_area, count, unit, assumptions::Assumptions)
    aspect_ratio = assumptions[Symbol(unit, :_aspect_ratio)]
    height = sqrt(aspect_ratio * total_area / count)
    return height, height / aspect_ratio
end

"deck mount height [m] above the waterline of a deck rig on `hull`"
foot_height(hull::Hull, assumptions::Assumptions) =
    assumptions[:deck_mount_height] * hull.length / assumptions[:reference_length]

"""
    bow_layout(total_area, unit, hull, assumptions)

One `unit` of `total_area` [m^2] on the forecastle of `hull`, ahead of the containers on its
deck, blocking none: its centre `bow_unit_position` times the length aft of the bow, in the
middle of the free forecastle length `bow_room` times the hull length that ends at the first
bay. The stacks shade it in apparent winds from astern whose line to it crosses them, and
it keeps the [`shadow_share`](@ref) of its load there. A camera system watches the view it
hides from the bridge where [`camera_units`](@ref) counts it. `nothing` where the circle it
sweeps, the width of a rotor or 1.5 chords of a wing turning about its quarter chord,
exceeds the free length.
"""
function bow_layout(total_area, unit, hull::Hull, assumptions::Assumptions)
    height, width = unit_size(total_area, 1, unit, assumptions)
    room = assumptions[:bow_room] * hull.length
    sweep = unit == :rotor ? width : assumptions[:wing_spacing] * width
    sweep <= room || return nothing
    centre_position = hull.length / 2 - assumptions[:bow_unit_position] * hull.length
    return (; count=1, columns=1, height, foot_height=foot_height(hull, assumptions),
        centre_position, column_offset=0.0, interference_factor=1.0,
        shadow_share=shadow_share(height / hull.deck_cargo_height, assumptions),
        shadow_angle=π - atan(hull.beam / 2, room / 2), pedestal_height=0.0,
        camera_units=camera_units([(centre_position, 0.0)], width, hull, assumptions))
end

"""
    raised_layout(in_column, total_area, hull, assumptions, forward_reserve)

`in_column` pairs of rotors of `total_area` [m^2] in all on `hull`, abreast and spread along
the deck as in [`column_layout`](@ref), each on a pedestal in the gap between two bays of
containers whose top stands `pedestal_clearance` above the stacks, in their free wind. A
camera system watches the view each rotor that [`camera_units`](@ref) counts hides.
"""
function raised_layout(in_column, total_area, hull::Hull, assumptions::Assumptions,
        forward_reserve)
    layout = column_layout(2, in_column, total_area, :rotor, hull, assumptions,
        forward_reserve)
    isnothing(layout) && return nothing
    pedestal_height = hull.deck_cargo_height + assumptions[:pedestal_clearance]
    diameter = layout.height / assumptions[:rotor_aspect_ratio]
    return (; layout..., foot_height=layout.foot_height + pedestal_height, pedestal_height,
        camera_units=camera_units(unit_positions(layout, hull, assumptions), diameter,
            hull, assumptions))
end

"""
    camera_units(positions, width, hull, assumptions)

Number of units of `width` [m] at `positions`, [m] forward of midship and off the
centreline, that stand forward of the bridge of `hull` and hide more than
`blind_sector_limit` [deg] of its view, each watched by a camera system.
"""
function camera_units(positions, width, hull::Hull, assumptions::Assumptions)
    bridge = hull.length / 2 - hull.bridge_distance
    limit = deg2rad(assumptions[:blind_sector_limit])
    return count(positions) do (along, across)
        along > bridge && 2atan(width / 2, hypot(along - bridge, across)) > limit
    end
end

"""
    shadow_share(relative_height, assumptions)

Share [-] of its wind load a unit `relative_height` times as tall as the container stacks
behind it keeps in their lee: the wind there is still below `shadow_calm_height` times the
stack height and rises linearly to the free wind at `shadow_free_height` times it, and the
load follows its square averaged over the unit's height.
"""
function shadow_share(relative_height, assumptions::Assumptions)
    calm, free = assumptions[:shadow_calm_height], assumptions[:shadow_free_height]
    top = clamp(relative_height, calm, free)
    ramp = (top - calm)^3 / (3(free - calm)^2)
    return (ramp + max(relative_height - free, 0.0)) / relative_height
end

"unit whose spacing and interference `unit` takes: suction sails those of wing sails"
arrangement_unit(unit) = unit == :suction ? :wing : unit

"deck length [m] for rigs on `hull`, less `forward_reserve` [m] at its forward end"
rig_deck_length(hull::Hull, assumptions::Assumptions, forward_reserve) =
    assumptions[:deck_length_fraction] * hull.length - forward_reserve

"""
    most_in_column(columns, total_area, unit, hull, assumptions, forward_reserve)

Most identical `unit`s of `total_area` [m^2] in all, in each of `columns` columns, that
stand the closest spacing apart along the [`rig_deck_length`](@ref): `in_column` units of
width w = sqrt(A / (AR columns in_column)) fit while in_column spacing w <= deck length.
"""
function most_in_column(columns, total_area, unit, hull::Hull, assumptions::Assumptions,
        forward_reserve)
    spacing = assumptions[Symbol(arrangement_unit(unit), :_spacing)]
    deck_length = rig_deck_length(hull, assumptions, forward_reserve)
    deck_length > 0 || return 0
    return floor(Int, deck_length^2 * assumptions[Symbol(unit, :_aspect_ratio)] * columns /
                      (spacing^2 * total_area))
end

"""
    layout_counts(total_area, unit, hull, assumptions, forward_reserve)

Columns and units per column of every layout [`deck_layout`](@ref) may give `unit`s of
`total_area` [m^2] on `hull`, fewest units first for each count of columns: up to
[`most_in_column`](@ref) in one row or two columns; where containers stand on its deck one
unit at the bow, and for rotors also pairs above the stacks.
"""
function layout_counts(total_area, unit, hull::Hull, assumptions::Assumptions,
        forward_reserve)
    on_deck(columns) = [(columns, in_column)
                        for in_column in 1:most_in_column(columns, total_area, unit, hull,
                            assumptions, forward_reserve)]
    hull.deck_cargo_height > 0 || return [on_deck(1); on_deck(2)]
    return unit == :rotor ? [(1, 1); on_deck(2)] : [(1, 1)]
end

"""
    column_layout(columns, in_column, total_area, unit, hull, assumptions, forward_reserve)

Layout of `columns` times `in_column` identical `unit`s of `total_area` [m^2] of height
times width on `hull`, in one row on the centreline or two columns abreast with half the
closest spacing clear of the deck edges, each column spread over the deck length for rigs
less `forward_reserve` [m] at its forward end. Returns the count, unit height [m], foot
height above the waterline [m], centre of effort forward of midship [m] (units abreast of
each other alone stand at the hull's lateral centre), column offset from the centreline
[m], interference factor, [`array_factor`](@ref) in line times that of a pair abreast,
which loses the unit's abreast loss times as much, and no shadow. `nothing` where units
stand closer than the closest spacing. Suction sails stand and interfere as wing sails do.
"""
function column_layout(columns, in_column, total_area, unit, hull::Hull,
        assumptions::Assumptions, forward_reserve)
    in_column <= most_in_column(columns, total_area, unit, hull, assumptions,
        forward_reserve) || return nothing
    arrangement(name) = assumptions[Symbol(arrangement_unit(unit), name)]
    deck_length = rig_deck_length(hull, assumptions, forward_reserve)
    count = columns * in_column
    height, width = unit_size(total_area, count, unit, assumptions)
    clearance = arrangement(:_spacing) * width
    column_offset = columns == 1 ? 0.0 : (hull.beam - clearance) / 2
    columns == 1 || 2column_offset >= clearance || return nothing
    amplitude = arrangement(:_interference_amplitude)
    decay = arrangement(:_interference_decay)
    interference_factor =
        array_factor(in_column, deck_length / in_column / width, amplitude, decay) *
        array_factor(columns, 2column_offset / width,
            arrangement(:_abreast_loss) * amplitude, decay)
    centre_position = in_column == 1 ? lateral_centre(hull) : -forward_reserve / 2
    return (; count, columns, height, foot_height=foot_height(hull, assumptions),
        centre_position, column_offset, interference_factor, shadow_share=1.0,
        shadow_angle=float(π), pedestal_height=0.0, camera_units=0)
end

"""
    unit_positions(rig, hull, assumptions)

Positions [m] of the units of the wing or rotor `rig` on `hull`, forward of midship and to
starboard of the centreline, spread evenly over each column as [`deck_layout`](@ref) lays
them out.
"""
function unit_positions(rig, hull::Hull, assumptions::Assumptions)
    in_column = rig.count ÷ rig.columns
    pitch = (assumptions[:deck_length_fraction] * hull.length + 2rig.centre_position) /
            in_column
    across = rig.columns == 1 ? (0.0,) : (-rig.column_offset, rig.column_offset)
    return [(rig.centre_position + (i - (in_column + 1) / 2) * pitch, offset)
            for i in 1:in_column for offset in across]
end

"""
    WingRig(total_area, hull, assumptions; forward_reserve=0, unit=:wing, columns=1,
            in_column=1)

Wing sails, or suction sails for `unit` `:suction`, of `total_area` [m^2] on `hull`,
`columns` times `in_column` of them laid out by [`deck_layout`](@ref), or `nothing` if they
do not fit. A suction sail's drag rises with the square of its lift to its drag at its
highest lift.
"""
function WingRig(total_area::Real, hull::Hull, assumptions::Assumptions;
        forward_reserve=0.0, unit=:wing, columns=1, in_column=1)
    layout = deck_layout(total_area, unit, hull, assumptions, forward_reserve, columns,
        in_column)
    isnothing(layout) && return nothing
    profile = assumptions[:wing_profile_drag_coefficient]
    effective_aspect_ratio =
        assumptions[:wing_endplate_factor] * assumptions[Symbol(unit, :_aspect_ratio)]
    max_lift_coefficient = assumptions[Symbol(unit, :_max_lift_coefficient)]
    suction = unit == :suction
    lift_drag_factor = suction ?
        (assumptions[:suction_drag_coefficient] - profile) / max_lift_coefficient^2 :
        assumptions[:wing_separation_drag_factor] +
        1 / (π * effective_aspect_ratio * assumptions[:wing_span_efficiency])
    return WingRig(; unit, layout.count, layout.columns, area=total_area / layout.count,
        layout.height, layout.foot_height, layout.centre_position, layout.column_offset,
        effective_aspect_ratio, max_lift_coefficient, profile_drag_coefficient=profile,
        lift_drag_factor,
        stalled_drag_coefficient=assumptions[:wing_stalled_drag_coefficient],
        layout.interference_factor,
        fan_power_per_area=suction ? assumptions[:suction_fan_power_per_area] : 0.0,
        max_wind=suction ? assumptions[:suction_max_wind] : Inf, layout.shadow_share,
        layout.shadow_angle, layout.camera_units)
end

total_area(rig::WingRig) = rig.count * rig.area

drag_coefficient(rig::WingRig, lift_coefficient) =
    rig.profile_drag_coefficient + rig.lift_drag_factor * lift_coefficient^2

"""
    stalled(rig::WingRig, (lift, drag))

Whether the trim `(lift, drag)` of [`trim_setting`](@ref) is stalled, not attached.
"""
stalled(rig::WingRig, (lift, drag)) = drag > drag_coefficient(rig, lift) + 1e-9

"""
    fan_power(rig::WingRig, setting, speed)

Power [W] the fans of suction sails draw at the trim `setting` in apparent wind `speed`
[m/s]: their power at the highest wind they work in times the cube of the share of it,
while the flow is attached and lifts; none for wing sails.
"""
function fan_power(rig::WingRig, setting, speed)
    first(setting) > 0 && !stalled(rig, setting) || return 0.0
    return rig.fan_power_per_area * total_area(rig) * min(speed / rig.max_wind, 1.0)^3
end

"""
    rig_force(rig::WingRig, env, wind_10m, true_angle, ship_speed, setting)

Wing force at the trim `setting`, a lift and drag coefficient pair from
[`trim_setting`](@ref), with the apparent wind taken at the wing's mid height, and the
[`fan_power`](@ref) of suction sails.
"""
function rig_force(rig::WingRig, env::Environment, wind_10m, true_angle, ship_speed,
        setting)
    lift, drag = setting
    centre_height, speed, angle = centre_wind(rig, env, wind_10m, true_angle, ship_speed)
    load = 0.5env.air_density * speed^2 * total_area(rig) * shade(rig, angle)
    thrust = load * rig.interference_factor * (lift * sin(angle) - drag * cos(angle))
    side = load * (lift * cos(angle) + drag * sin(angle))
    return RigForce(thrust, side, side * centre_height, side * rig.centre_position,
        fan_power(rig, setting, speed))
end

"""
    trim_ranges(rig, env, wind_10m, true_angle, ship_speed)

[`TrimRange`](@ref)s of the trims `rig` can take in that wind at `ship_speed` [m/s]: for
wings the lift coefficient in attached flow and the angle of attack [deg] stalled, or no
lift where the apparent wind exceeds their highest, for rotors the spin ratio, for a kite
the weight of side force against thrust.
"""
function trim_ranges(rig::WingRig, env, wind_10m, true_angle, ship_speed)
    _, speed, _ = centre_wind(rig, env, wind_10m, true_angle, ship_speed)
    speed > rig.max_wind && return (TrimRange(0.0, 0.0, 1, 1),)
    return (TrimRange(0.0, rig.max_lift_coefficient, 5, 1), TrimRange(25.0, 90.0, 5, 2))
end

"""
    trim_setting(rig, trim_range, value)

Setting [`rig_force`](@ref) takes for `value` of the trim variable of `trim_range`: for
wings the lift and drag coefficient pair, attached or stalled with the force normal to the
wing.
"""
function trim_setting(rig::WingRig, trim_range::TrimRange, value)
    trim_range.branch == 1 && return (value, drag_coefficient(rig, value))
    normal = rig.stalled_drag_coefficient
    return (normal * sind(value) * cosd(value),
        rig.profile_drag_coefficient + normal * sind(value)^2)
end

"""
    RotorRig

Set of identical Flettner rotors on deck.
"""
Base.@kwdef struct RotorRig
    "number of rotors"
    count::Int
    "columns the rotors stand in, one on the centreline or two abreast [-]"
    columns::Int
    "rotor height [m]"
    height::Float64
    "rotor diameter [m]"
    diameter::Float64
    "height of the rotor foot above the waterline [m]"
    foot_height::Float64
    "centre of effort forward of midship [m]"
    centre_position::Float64
    "distance of each column from the centreline [m]"
    column_offset::Float64
    "apparent wind above which the rotors stop spinning [m/s]"
    max_wind::Float64
    "highest rotor surface speed [m/s]"
    max_surface_speed::Float64
    "factor on the lift of the ShipCLEAN rotor fit [-]"
    lift_factor::Float64
    "thrust of the set over the sum of single rotors [-]"
    interference_factor::Float64
    "share of their wind load the rotors keep in the shadow of deck cargo [-]"
    shadow_share::Float64 = 1.0
    "apparent wind angle off the bow beyond which deck cargo shades the rotors [rad]"
    shadow_angle::Float64 = π
    "height of the pedestals the rotors stand on above the deck, zero on deck [m]"
    pedestal_height::Float64 = 0.0
    "rotors watched by a camera system for the view they hide from the bridge [-]"
    camera_units::Int = 0
end

"""
    RotorRig(total_area, hull, assumptions; forward_reserve=0, columns=1, in_column=1)

Rotors of `total_area` [m^2] of height times diameter on `hull`, `columns` times
`in_column` of them laid out by [`deck_layout`](@ref), or `nothing` if they do not fit.
"""
function RotorRig(total_area::Real, hull::Hull, assumptions::Assumptions;
        forward_reserve=0.0, columns=1, in_column=1)
    layout = deck_layout(total_area, :rotor, hull, assumptions, forward_reserve, columns,
        in_column)
    isnothing(layout) && return nothing
    return RotorRig(; layout.count, layout.columns, layout.height,
        diameter=layout.height / assumptions[:rotor_aspect_ratio], layout.foot_height,
        layout.centre_position, layout.column_offset,
        max_wind=assumptions[:rotor_max_wind],
        max_surface_speed=assumptions[:rotor_max_surface_speed],
        lift_factor=assumptions[:rotor_lift_factor], layout.interference_factor,
        layout.shadow_share, layout.shadow_angle, layout.pedestal_height,
        layout.camera_units)
end

total_area(rig::RotorRig) = rig.count * rig.height * rig.diameter

"share [-] of its wind load the deck rig `rig` keeps in an apparent wind from `angle` [rad]"
shade(rig::Union{WingRig, RotorRig}, angle) =
    angle > rig.shadow_angle ? rig.shadow_share : 1.0

"""
    rotor_coefficients(spin_ratio)

Lift, drag and spin power coefficient of a Flettner rotor of aspect ratio 6 with end
discs of twice its diameter, on height times diameter, over the ratio of surface speed to
apparent wind speed: the ShipCLEAN fit to CFD corrected with full-scale measurements
(Tillig and Ringsberg 2020, Ocean Engineering 211).
"""
function rotor_coefficients(spin_ratio)
    x = spin_ratio
    lift = -0.0046x^5 + 0.1145x^4 - 0.9817x^3 + 3.1309x^2 - 0.1039x
    drag = -0.0017x^5 + 0.0464x^4 - 0.4424x^3 + 1.7243x^2 - 1.641x + 0.6375
    power = 0.0001x^5 - 0.0004x^4 + 0.0143x^3 - 0.0168x^2 + 0.0234x
    return lift, drag, power
end

"""
    rig_force(rig::RotorRig, env, wind_10m, true_angle, ship_speed, spin_ratio)

Rotor force at `spin_ratio`, with the apparent wind taken at the rotors' mid height;
[`UNREACHABLE_RIG_FORCE`](@ref) where the rotors cannot spin that fast.
"""
function rig_force(rig::RotorRig, env::Environment, wind_10m, true_angle, ship_speed,
        spin_ratio)
    centre_height, speed, angle = centre_wind(rig, env, wind_10m, true_angle, ship_speed)
    spin_ratio <= max_spin_ratio(rig, speed) || return UNREACHABLE_RIG_FORCE
    load = 0.5env.air_density * speed^2 * total_area(rig) * shade(rig, angle)
    fitted_lift, drag, power = rotor_coefficients(spin_ratio)
    lift = rig.lift_factor * fitted_lift
    thrust = load * rig.interference_factor * (lift * sin(angle) - drag * cos(angle))
    side = load * (lift * cos(angle) + drag * sin(angle))
    return RigForce(thrust, side, side * centre_height, side * rig.centre_position,
        load * speed * power)
end

"highest spin ratio of the rotor fit [-]"
const MAX_SPIN_RATIO = 4.0

"""
    max_spin_ratio(rig, speed)

Highest spin ratio [-] of the rotors of `rig` in an apparent wind of `speed` [m/s]: that of
the fit or of their surface speed limit, zero above the wind they stop in.
"""
max_spin_ratio(rig::RotorRig, speed) =
    speed > rig.max_wind ? 0.0 : min(MAX_SPIN_RATIO, rig.max_surface_speed / speed)

function trim_ranges(rig::RotorRig, env, wind_10m, true_angle, ship_speed)
    _, speed, _ = centre_wind(rig, env, wind_10m, true_angle, ship_speed)
    return (TrimRange(0.0, max_spin_ratio(rig, speed), 17, 1),)
end

trim_setting(::RotorRig, ::TrimRange, value) = value

"""
    rotor_peak_pressure(rig, air_density)

Highest force [N/m^2] on each m^2 of height times diameter of the rotors of `rig` while
they spin, lift and drag together, in apparent winds up to the one they stop in, each at
the highest spin ratio it allows.
"""
rotor_peak_pressure(rig::RotorRig, air_density) =
    maximum(range(0.1, rig.max_wind, 200)) do speed
        lift, drag, _ = rotor_coefficients(max_spin_ratio(rig, speed))
        return 0.5air_density * speed^2 * hypot(rig.lift_factor * lift, drag)
    end

"""
    KiteRig

Towing kite on a fixed-length tether from a mast on the bow, with the force of its best
flight pattern tabulated over apparent wind speed, course off the apparent downwind
direction and the weight given to side force, its trim. `airframe` is a
[`RigidAirframe`](@ref) for rigid VTOL kites and `nothing` for a soft kite.
"""
Base.@kwdef struct KiteRig{A}
    "projected area of one kite [m^2]"
    area::Float64
    "projected aspect ratio of one kite [-]"
    aspect_ratio::Float64
    "tether diameter [m]"
    tether_diameter::Float64
    tether_length::Float64
    "height at which the apparent wind of the table is taken [m]"
    reference_height::Float64
    "highest apparent wind at kite altitude in which the kite stays up [m/s]"
    max_wind::Float64
    "lowest apparent wind at kite altitude in which the kite stays up [m/s]"
    min_flight_wind::Float64
    "lowest apparent wind in which the kite is launched [m/s]"
    launch_min_wind::Float64
    "highest apparent wind in which the kite is launched [m/s]"
    launch_max_wind::Float64
    "highest significant wave height in which the kite is launched [m]; `Inf` where only the
    launch wind limits it"
    launch_max_wave_height::Float64
    "apparent wind a launch needs beyond `launch_min_wind` in a rough sea [m/s]"
    rough_sea_launch_wind::Float64
    "highest apparent wind in which the kite lands without a forced landing [m/s]"
    landing_max_wind::Float64
    "highest significant wave height in which the kite lands without a forced landing [m];
    `Inf` where only the landing wind limits it"
    landing_max_wave_height::Float64
    "depower limit on tether force [N]"
    max_force::Float64
    "tether attachment height above the waterline [m]"
    attach_height::Float64
    "tether attachment distance forward of midship, at the hull's lateral centre [m]"
    attach_position::Float64
    "apparent wind speeds of the pattern table [m/s]"
    wind_speeds::Vector{Float64}
    "courses of the pattern table, azimuth off apparent downwind [rad]"
    courses::Vector{Float64}
    "weights of side force against thrust of the pattern table"
    side_weights::Vector{Float64}
    "best pattern force over dynamic pressure and area per speed, course and weight"
    forces::Array{PatternForce, 3}
    airframe::A = nothing
end

"""
    RigidAirframe

What a rigid VTOL kite adds to a tether and a pattern table.
"""
struct RigidAirframe
    "mass of the kite with its propellers and drives, without the tether [kg]"
    mass::Float64
    "electric power of the kite in hover [W]"
    hover_power::Float64
end

"""
    rope_mass(diameter, rope_length, assumptions)

Mass [kg] of `rope_length` [m] of tether rope of `diameter` [m].
"""
rope_mass(diameter, rope_length, assumptions) =
    assumptions[:tether_rope_density] * π * diameter^2 / 4 * rope_length

"""
    soft_kite_mass(area, aspect_ratio, max_force, assumptions)

Mass [kg] of a soft kite of projected `area` [m^2] and `aspect_ratio` without its tether:
canopy with its bridle and control unit, sized for `max_force` [N].
"""
soft_kite_mass(area, aspect_ratio, max_force, assumptions::Assumptions) =
    Canopy(assumptions, area, aspect_ratio).mass_per_area * area +
    1e-3assumptions[:control_unit_mass_per_force] * max_force

"""
    kite_model(area, aspect_ratio, assumptions)

[`KiteModel`](@ref) of a kite of projected `area` [m^2] and `aspect_ratio`, its tether
force limit [N] and tether diameter [m], with the tether sized for that limit.
"""
function kite_model(area, aspect_ratio, assumptions::Assumptions)
    env = Environment(assumptions)
    max_force = 1e3assumptions[:kite_max_force_per_area] * area
    tether_diameter = sqrt(4max_force / (π * assumptions[:tether_stress]))
    span = sqrt(area * aspect_ratio)
    tether_length = assumptions[:tether_length_ratio] * span
    tether_drag = assumptions[:tether_drag_coefficient] * tether_diameter * tether_length /
                  (4area)
    tether_mass = rope_mass(tether_diameter, tether_length, assumptions)
    mass = soft_kite_mass(area, aspect_ratio, max_force, assumptions) + tether_mass / 2
    polar = KitePolar(aspect_ratio)
    stall = argmax(polar.lift)
    model = KiteModel(area, mass, tether_length, env.air_density, env.gravity, polar,
        assumptions[:kite_flight_drag] + tether_drag,
        lift_angle(polar, 0.05),
        polar.angle_of_attack[stall] - deg2rad(assumptions[:kite_stall_margin]),
        assumptions[:kite_min_turn_radius] * span, false)
    return model, max_force, tether_diameter
end

"""
    lift_angle(polar, lift)

Lowest angle of attack [rad] at which `polar` reaches the lift coefficient `lift`.
"""
function lift_angle(polar::KitePolar, lift)
    i = findfirst(>=(lift), polar.lift)
    i == 1 && return first(polar.angle_of_attack)
    fraction = (lift - polar.lift[i - 1]) / (polar.lift[i] - polar.lift[i - 1])
    return polar.angle_of_attack[i - 1] +
           fraction * (polar.angle_of_attack[i] - polar.angle_of_attack[i - 1])
end

"""
    total_drag_at_lift(aspect_ratio, lift, assumptions)

Drag coefficient of a kite of `aspect_ratio` with its tether and flight drag, at the
lowest angle of attack reaching the lift coefficient `lift`. It does not depend on the area.
"""
function total_drag_at_lift(aspect_ratio, lift, assumptions::Assumptions)
    model, = kite_model(1.0, aspect_ratio, assumptions)
    polar = model.polar
    return polar_value(polar, polar.drag, lift_angle(polar, lift)) + model.extra_drag
end

"""
    recalibrated_flight_drag(aspect_ratio, base_aspect_ratio, assumptions)

Flight drag coefficient giving a kite of `aspect_ratio` the glide ratio at lift coefficient
0.8 that the kite of `base_aspect_ratio` has at the flight drag of `assumptions`.
"""
function recalibrated_flight_drag(aspect_ratio, base_aspect_ratio, assumptions::Assumptions)
    lift = 0.8
    return assumptions[:kite_flight_drag] +
           total_drag_at_lift(base_aspect_ratio, lift, assumptions) -
           total_drag_at_lift(aspect_ratio, lift, assumptions)
end

"""
    best_over_angles(coefficient, model)

Highest `coefficient(lift, drag)` of `model` over its flying angles of attack.
"""
function best_over_angles(coefficient, model::KiteModel)
    angles = TrimRange(model.lowest_angle, model.stall_angle, 9, 1)
    objective = Base.Fix1(Base.Fix1(negative_coefficient, coefficient), model)
    _, lowest = best_on_range(objective, angles)
    return -lowest
end

"minus `coefficient(lift, drag)` of `model` at angle of attack `angle` [rad]"
function negative_coefficient(coefficient, model::KiteModel, angle)
    (; lift, drag) = KiteAero(model, angle)
    return -coefficient(lift, drag)
end

"""
    crosswind_min_wind(model, elevation)

Lowest apparent wind [m/s] in which `model` sweeps level across the wind at `elevation`
[rad], rolled so that its lift carries its weight and its glide ratio sets its airspeed.
"""
function crosswind_min_wind(model::KiteModel, elevation)
    power = best_over_angles(model) do lift, drag
        glide = lift / drag
        return lift * (1 + glide^2)^1.5 / glide
    end
    return sqrt(3sqrt(3) * model.mass * model.gravity /
                (model.air_density * model.area * cos(elevation) * power))
end

"""
    climbing_min_wind(model, elevation)

Lowest apparent wind [m/s] in which `model` holds a steady climb straight up the wind window
at `elevation` [rad], the airspeed that makes most force along its path.
"""
function climbing_min_wind(model::KiteModel, elevation)
    pull = best_over_angles(model) do lift, drag
        glide = lift / drag
        speed = glide^2 > 8 ? (glide + sqrt(glide^2 - 8)) / 4 : 0.0
        return max(lift, sqrt(1 + speed^2) * (lift - drag * speed))
    end
    return sqrt(2model.mass * model.gravity /
                (model.air_density * model.area * cos(elevation) * pull))
end

"""
    min_flight_wind(model, assumptions)

Lowest apparent wind [m/s] in which the kite of `model` flies a pattern of steady points:
[`climbing_min_wind`](@ref) at the lowest elevation.
"""
min_flight_wind(model::KiteModel, assumptions::Assumptions) =
    climbing_min_wind(model, deg2rad(assumptions[:kite_min_elevation]))

"""
    launch_min_wind(model, assumptions)

Lowest apparent wind [m/s] in a calm sea in which the kite of `model` is launched: the
reported launch wind, or the [`min_flight_wind`](@ref) where that is higher.
"""
launch_min_wind(model::KiteModel, assumptions::Assumptions) =
    max(min_flight_wind(model, assumptions), assumptions[:kite_launch_min_wind])

"""
    rigid_polar(assumptions)

Polar of a rigid wing against angle of attack from zero lift: lift-curve slope of a finite
wing up to the highest lift coefficient, a drag coefficient that holds all but the induced
drag plus the induced drag of an elliptic wing.
"""
function rigid_polar(assumptions::Assumptions)
    aspect_ratio = assumptions[:rigid_aspect_ratio]
    slope = 2π / (1 + 2 / aspect_ratio)
    highest = assumptions[:rigid_max_lift]
    angles = collect(range(0.0, highest / slope + deg2rad(2); length=25))
    lift = min.(slope .* angles, highest)
    drag = assumptions[:rigid_drag] .+ lift .^ 2 ./ (π * aspect_ratio)
    return KitePolar(angles, lift, drag)
end

"""
    rigid_kite_mass(area, assumptions)

Mass [kg] of a rigid VTOL kite of `area` [m^2] with its propellers and drives, without the
tether: that of MX2, grown with the span to the power of the mass exponent at a fixed aspect
ratio.
"""
rigid_kite_mass(area, assumptions::Assumptions) = assumptions[:rigid_mass] *
    (area / assumptions[:rigid_reference_area])^(assumptions[:rigid_mass_exponent] / 2)

"span [m] of a rigid VTOL kite of `area` [m^2]"
rigid_span(area, assumptions::Assumptions) = sqrt(area * assumptions[:rigid_aspect_ratio])

"""
    rigid_kite_model(area, assumptions)

[`KiteModel`](@ref) of a rigid VTOL kite of `area` [m^2], its tether force limit [N],
tether diameter [m] at the working stress of the soft kite's rope and its
[`RigidAirframe`](@ref).
"""
function rigid_kite_model(area, assumptions::Assumptions)
    env = Environment(assumptions)
    max_force = 1e3assumptions[:rigid_max_force_per_area] * area
    tether_diameter = sqrt(4max_force / (π * assumptions[:tether_stress]))
    span = rigid_span(area, assumptions)
    mass = rigid_kite_mass(area, assumptions)
    polar = rigid_polar(assumptions)
    model = KiteModel(area, mass, assumptions[:rigid_tether_length_ratio] * span,
        env.air_density, env.gravity, polar, 0.0, lift_angle(polar, 0.05),
        polar.angle_of_attack[argmax(polar.lift)] -
        deg2rad(assumptions[:kite_stall_margin]),
        assumptions[:rigid_min_turn_radius] * span, true)
    airframe = RigidAirframe(mass, assumptions[:rigid_hover_power_per_mass] * mass)
    return model, max_force, tether_diameter, airframe
end

"weights of side force against thrust [-] of a kite's pattern table"
const SIDE_WEIGHTS = [0.0, 0.25, 0.5, 1.0, 1.5, 2.0, 3.0]

"courses [rad] of a kite's full pattern table"
const KITE_COURSES = deg2rad.(0.0:15.0:180.0)

"apparent wind speeds [m/s] of a rigid kite's pattern table"
const RIGID_WIND_SPEEDS = [4.0:1.0:10.0; 12.0; 14.0; 17.0; 20.0; 25.0; 30.0]

"""
    lowest_flying_wind(wind_speeds, forces)

Lowest of `wind_speeds` [m/s] at which the pattern table `forces` flies on any course.
"""
function lowest_flying_wind(wind_speeds, forces)
    flying = findfirst(i -> any(force -> isfinite(force.peak_tension),
            view(forces, i, :, :)), eachindex(wind_speeds))
    return isnothing(flying) ? Inf : wind_speeds[flying]
end

"""
    rigid_wind_limits(lowest_wind, assumptions)

Keywords of [`KiteRig`](@ref) for a rigid kite that flies from `lowest_wind` [m/s]: it can
launch there too, since its propellers lift it from rest, and hovers in launch and landing up
to the soft kite's launch wind and its own wave height.
"""
function rigid_wind_limits(lowest_wind, assumptions::Assumptions)
    hover_wind = assumptions[:kite_launch_max_wind]
    hover_waves = assumptions[:rigid_hover_max_wave_height]
    return (; max_wind=assumptions[:kite_max_wind], min_flight_wind=lowest_wind,
        launch_min_wind=lowest_wind, launch_max_wind=hover_wind,
        launch_max_wave_height=hover_waves, rough_sea_launch_wind=0.0,
        landing_max_wind=hover_wind, landing_max_wave_height=hover_waves)
end

"""
    largest_rigid_kite_area(hull, assumptions)

Area [m^2] of the largest rigid VTOL kite whose perch fits on `hull`: its span the deck
length the rig may use, or the beam where containers stand on its deck and the perch lies
across the forecastle.
"""
function largest_rigid_kite_area(hull::Hull, assumptions::Assumptions)
    span = hull.deck_cargo_height > 0 ? hull.beam :
           assumptions[:deck_length_fraction] * hull.length
    return span^2 / assumptions[:rigid_aspect_ratio]
end

"""
    rigid_kite_rig(area, hull, assumptions; courses=KITE_COURSES, side_weights=SIDE_WEIGHTS)

Rigid VTOL kite of `area` [m^2] on `hull` with a pattern table over `courses` [rad] and
`side_weights`, towing from the hull's lateral centre, or from the bow where containers
stand on its deck; `nothing` where it is larger than [`largest_rigid_kite_area`](@ref).
"""
function rigid_kite_rig(area, hull::Hull, assumptions::Assumptions;
        courses=KITE_COURSES, side_weights=SIDE_WEIGHTS)
    area <= largest_rigid_kite_area(hull, assumptions) || return nothing
    model, max_force, tether_diameter, airframe = rigid_kite_model(area, assumptions)
    forces = pattern_table(model, max_force, assumptions, RIGID_WIND_SPEEDS, courses,
        side_weights)
    lowest_wind = max(lowest_flying_wind(RIGID_WIND_SPEEDS, forces),
        crosswind_min_wind(model, deg2rad(assumptions[:kite_min_elevation])))
    return KiteRig(; area, aspect_ratio=assumptions[:rigid_aspect_ratio], tether_diameter,
        model.tether_length, reference_height=model.tether_length * sin(deg2rad(25)),
        rigid_wind_limits(lowest_wind, assumptions)..., max_force,
        attach_height=assumptions[:kite_attach_height] * hull.length /
                      assumptions[:reference_length],
        attach_position=hull.deck_cargo_height > 0 ?
                        launch_mast_position(hull, assumptions) : lateral_centre(hull),
        wind_speeds=RIGID_WIND_SPEEDS, courses, side_weights, forces, airframe)
end

"""
    KiteRig(area, aspect_ratio, hull, assumptions;
            attach_position=launch_mast_position(hull, assumptions), courses=KITE_COURSES)

Kite of projected `area` [m^2] and `aspect_ratio` with its pattern table over `courses`
[rad], towing from `attach_position` [m] forward of midship.
"""
function KiteRig(area::Real, aspect_ratio::Real, hull::Hull, assumptions::Assumptions;
        attach_position=launch_mast_position(hull, assumptions), courses=KITE_COURSES)
    scale = hull.length / assumptions[:reference_length]
    model, max_force, tether_diameter = kite_model(area, aspect_ratio, assumptions)
    tether_length = model.tether_length
    wind_speeds = [3.0:1.0:9.0; 10.5; 12.0:3.0:30.0]
    forces = pattern_table(model, max_force, assumptions, wind_speeds, courses, SIDE_WEIGHTS)
    return KiteRig(; area, aspect_ratio, tether_diameter, tether_length,
        reference_height=tether_length * sin(deg2rad(25)),
        max_wind=assumptions[:kite_max_wind],
        min_flight_wind=max(min_flight_wind(model, assumptions),
            lowest_flying_wind(wind_speeds, forces)),
        launch_min_wind=launch_min_wind(model, assumptions),
        launch_max_wind=assumptions[:kite_launch_max_wind], launch_max_wave_height=Inf,
        rough_sea_launch_wind=assumptions[:kite_launch_sea_wind],
        landing_max_wind=assumptions[:kite_landing_max_wind],
        landing_max_wave_height=Inf, max_force,
        attach_height=assumptions[:kite_attach_height] * scale,
        attach_position, wind_speeds, courses, side_weights=SIDE_WEIGHTS, forces)
end

"""
    table_weights(grid, value)

Index of the grid interval holding `value` and the weight of its upper end; the one
point and no weight on a grid of one point.
"""
function table_weights(grid, value)
    isone(length(grid)) && return 1, 0.0
    i = clamp(searchsortedlast(grid, value), 1, length(grid) - 1)
    return i, clamp((value - grid[i]) / (grid[i + 1] - grid[i]), 0.0, 1.0)
end

"""
    rig_force(rig::KiteRig, env, wind_10m, true_angle, ship_speed, side_weight)

Force of the best pattern for `side_weight`, interpolated in newtons over apparent wind
speed, course and side weight and held to the tether limit; no force where the kite cannot
fly or the wind is below the table.
"""
function rig_force(rig::KiteRig, env::Environment, wind_10m, true_angle, ship_speed,
        side_weight)
    wind = wind_at_height(env, wind_10m, rig.reference_height)
    speed, angle = apparent_wind(wind, true_angle, ship_speed)
    max(rig.min_flight_wind, first(rig.wind_speeds)) <= speed <= rig.max_wind ||
        return NO_RIG_FORCE
    i, speed_weight = table_weights(rig.wind_speeds, speed)
    j, course_weight = table_weights(rig.courses, π - angle)
    k, side_fraction = table_weights(rig.side_weights, side_weight)
    downwind, crosswind = 0.0, 0.0
    for (row, row_weight) in ((i, 1 - speed_weight), (i + 1, speed_weight)),
        (column, column_weight) in ((j, 1 - course_weight), (j + 1, course_weight)),
        (layer, layer_weight) in ((k, 1 - side_fraction), (k + 1, side_fraction))

        weight = row_weight * column_weight * layer_weight
        iszero(weight) && continue
        force = rig.forces[row, column, layer].force
        isfinite(force[1]) || return NO_RIG_FORCE
        load = 0.5env.air_density * rig.wind_speeds[row]^2 * rig.area
        downwind += weight * load * force[1]
        crosswind += weight * load * force[2]
    end
    limit = min(1.0, rig.max_force / hypot(downwind, crosswind))
    thrust = limit * (crosswind * sin(angle) - downwind * cos(angle))
    side = limit * (crosswind * cos(angle) + downwind * sin(angle))
    return RigForce(thrust, side, side * rig.attach_height, side * rig.attach_position)
end

trim_ranges(rig::KiteRig, env, wind_10m, true_angle, ship_speed) =
    (TrimRange(first(rig.side_weights), last(rig.side_weights), 13, 1),)

trim_setting(::KiteRig, ::TrimRange, value) = value

"""
    CombinedRig{K, S}

Towing kite of type `K` flown over a standing rig of wings or rotors, of type `S`; the
standing rig works whether or not the kite flies.
"""
struct CombinedRig{K <: KiteRig, S}
    kite::K
    standing::S
end

"""
    launch_mast_reserve(assumptions)

Deck length [m] the kite's launch mast takes at the forward end of the deck for rigs.
"""
launch_mast_reserve(assumptions::Assumptions) =
    assumptions[:launch_mast_width] + assumptions[:deck_rig_clearance]

"""
    launch_mast_position(hull, assumptions)

Distance [m] forward of midship of the launch mast: at the bow, where [`bow_layout`](@ref)
stands a unit, on a hull with containers on deck, else at the middle of its
[`launch_mast_reserve`](@ref) at the forward end of the deck for rigs.
"""
function launch_mast_position(hull::Hull, assumptions::Assumptions)
    hull.deck_cargo_height > 0 &&
        return (0.5 - assumptions[:bow_unit_position]) * hull.length
    deck_length = rig_deck_length(hull, assumptions, 0.0)
    return (deck_length - launch_mast_reserve(assumptions)) / 2
end

"""
    CombinedRig(kite_area, kite_aspect_ratio, standing_type, standing_area, hull,
                assumptions; layout...)

Kite of projected `kite_area` [m^2] and `kite_aspect_ratio` towing from a launch mast at
the forward end of the deck for rigs, over `standing_area` [m^2] of `standing_type`
(`WingRig` or `RotorRig`) on the deck behind it in the `layout` of its keywords `columns`
and `in_column`, or `nothing` if those do not fit.
"""
function CombinedRig(kite_area, kite_aspect_ratio, standing_type, standing_area,
        hull::Hull, assumptions::Assumptions; layout...)
    standing = standing_type(standing_area, hull, assumptions;
        forward_reserve=launch_mast_reserve(assumptions), layout...)
    isnothing(standing) && return nothing
    kite = KiteRig(kite_area, kite_aspect_ratio, hull, assumptions;
        attach_position=launch_mast_position(hull, assumptions))
    return CombinedRig(kite, standing)
end

"""
    rig_force(rig::CombinedRig, env, wind_10m, true_angle, ship_speed, trim)

Kite and standing rig force together at the `trim`, a pair of kite trim and standing rig
trim.
"""
rig_force(rig::CombinedRig, env::Environment, wind_10m, true_angle, ship_speed, trim) =
    rig_force(rig.kite, env, wind_10m, true_angle, ship_speed, first(trim)) +
    rig_force(rig.standing, env, wind_10m, true_angle, ship_speed, last(trim))


"""
    standing_rig(rig)

The part of `rig` that stands and works with any kite down: wings and rotors
themselves, the standing rig of a [`CombinedRig`](@ref), `nothing` for a kite alone or
no rig.
"""
standing_rig(rig::Union{WingRig, RotorRig}) = rig
standing_rig(rig::CombinedRig) = rig.standing
standing_rig(::Union{KiteRig, Nothing}) = nothing

"""
    DownRig

Wings or rotors with only the share `working_share` of their units in service, the rest
still on deck: wings feathered at no lift, rotors stopped. The array keeps the interference
of all its units.
"""
struct DownRig{R}
    rig::R
    working_share::Float64
end

stopped_setting(rig::WingRig) = (0.0, drag_coefficient(rig, 0.0))
stopped_setting(::RotorRig) = 0.0

trim_ranges(down::DownRig, env, wind_10m, true_angle, ship_speed) =
    trim_ranges(down.rig, env, wind_10m, true_angle, ship_speed)

trim_setting(down::DownRig, trim_range::TrimRange, value) =
    trim_setting(down.rig, trim_range, value)

function rig_force(down::DownRig, env::Environment, wind_10m, true_angle, ship_speed,
        setting)
    working = rig_force(down.rig, env, wind_10m, true_angle, ship_speed, setting)
    stopped = rig_force(down.rig, env, wind_10m, true_angle, ship_speed,
        stopped_setting(down.rig))
    return down.working_share * working + (1 - down.working_share) * stopped
end

standing_rig(down::DownRig) = down

"""
    rig_height(rig)

Height [m] at which `rig` takes its apparent wind, 10 m without a rig.
"""
rig_height(rig::Union{WingRig, RotorRig}) = rig.foot_height + rig.height / 2
rig_height(rig::KiteRig) = rig.reference_height
rig_height(rig::CombinedRig) = rig_height(rig.kite)
rig_height(down::DownRig) = rig_height(down.rig)
rig_height(::Nothing) = 10.0
