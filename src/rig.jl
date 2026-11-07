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

"sum of two rig forces acting on one ship, field by field"
Base.:+(a::RigForce, b::RigForce) = RigForce(a.thrust + b.thrust, a.side + b.side,
    a.heeling_moment + b.heeling_moment, a.yaw_moment + b.yaw_moment, a.power + b.power)

"rig force scaled by a share [-], field by field"
Base.:*(share::Real, force::RigForce) = RigForce(share * force.thrust, share * force.side,
    share * force.heeling_moment, share * force.yaw_moment, share * force.power)

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

Set of identical rigid wing sails on deck.
"""
Base.@kwdef struct WingRig
    "number of wings"
    count::Int
    "planform area of one wing [m^2]"
    area::Float64
    "height of one wing [m]"
    height::Float64
    "height of the wing foot above the waterline [m]"
    foot_height::Float64
    "centre of effort forward of midship [m]"
    centre_position::Float64
    "effective aspect ratio including the deck mirror effect [-]"
    effective_aspect_ratio::Float64
    max_lift_coefficient::Float64
    profile_drag_coefficient::Float64
    separation_drag_factor::Float64
    span_efficiency::Float64
    "normal-force coefficient of the stalled wing across the flow [-]"
    stalled_drag_coefficient::Float64
    interference_factor::Float64
end

"""
    deck_row(total_area, aspect_ratio, max_height, spacing, hull, assumptions,
             forward_reserve)

Row of identical units of `total_area` [m^2] of height times width at `aspect_ratio` on
`hull`: as few units as the air draft and `max_height` [m] allow, spread evenly over the
deck length for rigs less `forward_reserve` [m] at its forward end. Returns the count,
unit height [m], foot height above the waterline [m], centre of effort forward of
midship [m] (a single unit stands at the hull's lateral centre) and the spacing in unit
widths, or `nothing` if the units do not fit `spacing` widths apart.
"""
function deck_row(total_area, aspect_ratio, max_height, spacing, hull::Hull,
        assumptions::Assumptions, forward_reserve)
    scale = hull.length / assumptions[:reference_length]
    foot_height = assumptions[:deck_mount_height] * scale
    max_height = min(assumptions[:max_air_draft] - foot_height, max_height)
    count = ceil(Int, total_area / (max_height^2 / aspect_ratio))
    height = sqrt(aspect_ratio * total_area / count)
    width = height / aspect_ratio
    deck_length = assumptions[:deck_length_fraction] * hull.length - forward_reserve
    count * spacing * width <= deck_length || return nothing
    return (; count, height, foot_height,
        centre_position=count == 1 ? lateral_centre(hull) : -forward_reserve / 2,
        spacing=deck_length / count / width)
end

"""
    WingRig(total_area, hull, assumptions; forward_reserve=0)

Wing rig of `total_area` [m^2] on `hull` laid out by [`deck_row`](@ref), or `nothing`
if the wings do not fit at the closest spacing.
"""
function WingRig(total_area::Real, hull::Hull, assumptions::Assumptions;
        forward_reserve=0.0)
    aspect_ratio = assumptions[:wing_aspect_ratio]
    row = deck_row(total_area, aspect_ratio, assumptions[:wing_max_height],
        assumptions[:wing_spacing], hull, assumptions, forward_reserve)
    isnothing(row) && return nothing
    return WingRig(; row.count, area=total_area / row.count, row.height, row.foot_height,
        row.centre_position,
        effective_aspect_ratio=assumptions[:wing_endplate_factor] * aspect_ratio,
        max_lift_coefficient=assumptions[:wing_max_lift_coefficient],
        profile_drag_coefficient=assumptions[:wing_profile_drag_coefficient],
        separation_drag_factor=assumptions[:wing_separation_drag_factor],
        stalled_drag_coefficient=assumptions[:wing_stalled_drag_coefficient],
        span_efficiency=assumptions[:wing_span_efficiency],
        interference_factor=array_factor(row.count, row.spacing,
            assumptions[:wing_interference_amplitude],
            assumptions[:wing_interference_decay]))
end

total_area(rig::WingRig) = rig.count * rig.area

function drag_coefficient(rig::WingRig, lift_coefficient)
    induced = 1 / (π * rig.effective_aspect_ratio * rig.span_efficiency)
    return rig.profile_drag_coefficient +
           (rig.separation_drag_factor + induced) * lift_coefficient^2
end

"""
    rig_force(rig::WingRig, env, wind_10m, true_angle, ship_speed, setting)

Wing force at the trim `setting`, a lift and drag coefficient pair from
[`trim_settings`](@ref), with the apparent wind taken at the wing's mid height.
"""
function rig_force(rig::WingRig, env::Environment, wind_10m, true_angle, ship_speed,
        setting)
    lift, drag = setting
    centre_height = rig_height(rig)
    wind = wind_at_height(env, wind_10m, centre_height)
    speed, angle = apparent_wind(wind, true_angle, ship_speed)
    load = 0.5env.air_density * speed^2 * total_area(rig)
    thrust = load * rig.interference_factor * (lift * sin(angle) - drag * cos(angle))
    side = load * (lift * cos(angle) + drag * sin(angle))
    return RigForce(thrust, side, side * centre_height, side * rig.centre_position)
end

"""
    trim_settings(rig::WingRig)

Lift and drag coefficient pairs of the wing: attached flow up to its highest lift
coefficient, and stalled from 25 to 90 degrees angle of attack, where the force is
normal to the wing.
"""
function trim_settings(rig::WingRig)
    attached = [(lift, drag_coefficient(rig, lift))
                for lift in range(0.0, rig.max_lift_coefficient; length=37)]
    normal = rig.stalled_drag_coefficient
    stalled = [(normal * sind(angle) * cosd(angle),
                   rig.profile_drag_coefficient + normal * sind(angle)^2)
               for angle in 25:5:90]
    return [attached; stalled]
end

"""
    RotorRig

Set of identical Flettner rotors on deck.
"""
Base.@kwdef struct RotorRig
    "number of rotors"
    count::Int
    "rotor height [m]"
    height::Float64
    "rotor diameter [m]"
    diameter::Float64
    "height of the rotor foot above the waterline [m]"
    foot_height::Float64
    "centre of effort forward of midship [m]"
    centre_position::Float64
    "apparent wind above which the rotors stop spinning [m/s]"
    max_wind::Float64
    "highest rotor surface speed [m/s]"
    max_surface_speed::Float64
    "factor on the lift of the ShipCLEAN rotor fit [-]"
    lift_factor::Float64
    "thrust of the set over the sum of single rotors [-]"
    interference_factor::Float64
end

"""
    RotorRig(total_area, hull, assumptions; forward_reserve=0)

Rotors of `total_area` [m^2] of height times diameter on `hull` laid out by
[`deck_row`](@ref), or `nothing` if they do not fit at the closest spacing.
"""
function RotorRig(total_area::Real, hull::Hull, assumptions::Assumptions;
        forward_reserve=0.0)
    aspect_ratio = assumptions[:rotor_aspect_ratio]
    row = deck_row(total_area, aspect_ratio, assumptions[:rotor_max_height],
        assumptions[:rotor_spacing], hull, assumptions, forward_reserve)
    isnothing(row) && return nothing
    return RotorRig(; row.count, row.height, diameter=row.height / aspect_ratio,
        row.foot_height, row.centre_position,
        max_wind=assumptions[:rotor_max_wind],
        max_surface_speed=assumptions[:rotor_max_surface_speed],
        lift_factor=assumptions[:rotor_lift_factor],
        interference_factor=array_factor(row.count, row.spacing,
            assumptions[:rotor_interference_amplitude],
            assumptions[:rotor_interference_decay]))
end

total_area(rig::RotorRig) = rig.count * rig.height * rig.diameter

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
no force where the rotors cannot spin that fast.
"""
function rig_force(rig::RotorRig, env::Environment, wind_10m, true_angle, ship_speed,
        spin_ratio)
    centre_height = rig_height(rig)
    wind = wind_at_height(env, wind_10m, centre_height)
    speed, angle = apparent_wind(wind, true_angle, ship_speed)
    spin_ratio * speed <= rig.max_surface_speed || return NO_RIG_FORCE
    speed > rig.max_wind && spin_ratio > 0 && return NO_RIG_FORCE
    load = 0.5env.air_density * speed^2 * total_area(rig)
    fitted_lift, drag, power = rotor_coefficients(spin_ratio)
    lift = rig.lift_factor * fitted_lift
    thrust = load * rig.interference_factor * (lift * sin(angle) - drag * cos(angle))
    side = load * (lift * cos(angle) + drag * sin(angle))
    return RigForce(thrust, side, side * centre_height, side * rig.centre_position,
        load * speed * power)
end

trim_settings(rig::RotorRig) = 0.0:0.25:4.0

"""
    KiteRig

Towing kite on a fixed-length tether from a mast on the bow, with the force of its best
flight pattern tabulated over apparent wind speed, course off the apparent downwind
direction and the weight given to side force; each weight is one trim. `airframe` is a
[`RigidAirframe`](@ref) for rigid VTOL kites and `nothing` for a soft kite.
"""
Base.@kwdef struct KiteRig{A}
    "projected area of one kite [m^2]"
    area::Float64
    "tether diameter [m]"
    tether_diameter::Float64
    tether_length::Float64
    "height at which the apparent wind of the table is taken [m]"
    reference_height::Float64
    "highest apparent wind at kite altitude in which the kite stays up [m/s]"
    max_wind::Float64
    "lowest apparent wind at kite altitude in which the kite flies a pattern [m/s]"
    min_flight_wind::Float64
    "lowest apparent wind in which the kite is launched [m/s]"
    launch_min_wind::Float64
    "highest apparent wind in which the kite is launched [m/s]"
    launch_max_wind::Float64
    "highest significant wave height in which the kite is launched [m]"
    launch_max_wave_height::Float64
    "whether the kite is launched in the dark as well as by day"
    night_launch::Bool
    "highest apparent wind in which the kite lands without a forced landing [m/s]"
    landing_max_wind::Float64
    "highest significant wave height in which the kite lands without a forced landing [m]"
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
    "weights of side force against thrust, one per trim"
    side_weights::Vector{Float64}
    "best pattern force over dynamic pressure and area per speed, course and weight"
    forces::Array{PatternForce, 3}
    airframe::A = nothing
end

"""
    RigidAirframe

What rigid VTOL kites add to a tether and a pattern table.
"""
struct RigidAirframe
    "kites in service, a mean where some are down, each with tether, winch and perch"
    count::Float64
    "mass of one kite with its rotors, without the tether [kg]"
    mass::Float64
    "mass of one tether [kg]"
    tether_mass::Float64
    "electric power of one kite in hover [W]"
    hover_power::Float64
    "area of the disc of the loop all the kites share [m^2]"
    loop_area::Float64
end

"kites flying from one ship"
kite_count(::KiteRig) = 1
kite_count(rig::KiteRig{RigidAirframe}) = rig.airframe.count

"""
    loop_interaction(rig, force_area)

Force of each kite of `rig` over that of a lone kite, where a lone kite in the free stream
makes `force_area` [m^2], its force over dynamic pressure: momentum theory on the disc of
one shared loop gives each kite (1 - a)^2 of it, with a = C / (4 + C) for the disc's free
stream thrust coefficient C.
"""
loop_interaction(::KiteRig, force_area) = 1.0

function loop_interaction(rig::KiteRig{RigidAirframe}, force_area)
    (; count, loop_area) = rig.airframe
    lone = force_area / loop_area
    return ((4 + lone) / (4 + count * lone))^2
end

"""
    rope_mass(diameter, rope_length, assumptions)

Mass [kg] of `rope_length` [m] of tether rope of `diameter` [m].
"""
rope_mass(diameter, rope_length, assumptions) =
    assumptions[:tether_rope_density] * π * diameter^2 / 4 * rope_length

"""
    bridle_lines(area, aspect_ratio, max_force, assumptions)

Drag coefficient on the projected area and mass [kg] of a bridle whose lines run from
the attachment rows of a kite of `area` [m^2] and projected `aspect_ratio` down to the
control unit, sized for `max_force` [N].
"""
function bridle_lines(area, aspect_ratio, max_force, assumptions::Assumptions)
    span = sqrt(area * aspect_ratio)
    count = assumptions[:bridle_rows] * aspect_ratio / assumptions[:bridle_spacing]
    diameter = sqrt(4max_force / (count * π * assumptions[:tether_stress]))
    line_length = assumptions[:bridle_cascade_factor] * count *
                  assumptions[:bridle_height_ratio] * span
    drag = assumptions[:tether_drag_coefficient] * line_length * diameter / area
    return drag, rope_mass(diameter, line_length, assumptions)
end

"""
    kite_model(area, aspect_ratio, assumptions)

[`KiteModel`](@ref) of a kite of projected `area` [m^2] and `aspect_ratio`, its tether
force limit [N] and tether diameter [m], with tether and bridle sized for that limit.
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
    bridle_drag, bridle_mass = bridle_lines(area, aspect_ratio, max_force, assumptions)
    mass = Canopy(assumptions).mass_per_area * area + bridle_mass +
           1e-3assumptions[:control_unit_mass_per_force] * max_force + tether_mass / 2
    polar = KitePolar(aspect_ratio)
    stall = argmax(polar.lift)
    model = KiteModel(area, mass, tether_length, env.air_density, env.gravity, polar,
        assumptions[:kite_flight_drag] + bridle_drag + tether_drag,
        polar.angle_of_attack[findfirst(>=(0.05), polar.lift)],
        polar.angle_of_attack[stall] - deg2rad(assumptions[:kite_stall_margin]),
        assumptions[:kite_min_turn_radius] * span, false)
    return model, max_force, tether_diameter
end

"""
    total_drag_at_lift(aspect_ratio, lift, assumptions)

Drag coefficient of a kite of `aspect_ratio` with its bridle, tether and flight drag, at the
lowest angle of attack reaching the lift coefficient `lift`. It does not depend on the area.
"""
function total_drag_at_lift(aspect_ratio, lift, assumptions::Assumptions)
    model, = kite_model(1.0, aspect_ratio, assumptions)
    polar = model.polar
    angles = range(extrema(polar.angle_of_attack)...; length=2901)
    angle = angles[findfirst(a -> polar_value(polar, polar.lift, a) >= lift, angles)]
    return polar_value(polar, polar.drag, angle) + model.extra_drag
end

"""
    recalibrated_flight_drag(aspect_ratio, base_aspect_ratio, assumptions; lift=0.8)

Flight drag coefficient giving a kite of `aspect_ratio` the glide ratio at lift coefficient
`lift` that the kite of `base_aspect_ratio` has at the flight drag of `assumptions`.
"""
function recalibrated_flight_drag(aspect_ratio, base_aspect_ratio, assumptions::Assumptions;
    lift=0.8)
    return assumptions[:kite_flight_drag] +
           total_drag_at_lift(base_aspect_ratio, lift, assumptions) -
           total_drag_at_lift(aspect_ratio, lift, assumptions)
end

"""
    static_wind(mass, model)

Apparent wind [m/s] whose lift at rest at the highest lift coefficient of `model` carries
`mass` [kg].
"""
static_wind(mass, model::KiteModel) = sqrt(2mass * model.gravity /
    (model.air_density * model.area * maximum(model.polar.lift)))

"""
    best_over_angles(coefficient, model)

Highest `coefficient(lift, drag)` of `model` over its flying angles of attack.
"""
function best_over_angles(coefficient, model::KiteModel)
    angles = range(model.lowest_angle, model.stall_angle; length=48)
    return maximum(angles) do angle
        (; lift, drag) = KiteAero(model, angle)
        return coefficient(lift, drag)
    end
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
    launch_min_wind(model, tether_mass, assumptions)

Lowest apparent wind [m/s] in which the kite of `model` is launched: the launch margin
times the [`static_wind`](@ref) at lift-off without the tether of `tether_mass` [kg], enough
to fly once the tether is out, and no less than the reported launch wind.
"""
function launch_min_wind(model::KiteModel, tether_mass, assumptions::Assumptions)
    lift_off = static_wind(model.mass - tether_mass / 2, model)
    return max(assumptions[:kite_launch_margin] * lift_off,
        min_flight_wind(model, assumptions), assumptions[:kite_launch_min_wind])
end

"""
    rigid_polar(assumptions)

Polar of a rigid wing against angle of attack from zero lift: lift-curve slope of a finite
wing up to the highest lift coefficient, profile drag plus induced drag.
"""
function rigid_polar(assumptions::Assumptions)
    aspect_ratio = assumptions[:rigid_aspect_ratio]
    slope = 2π / (1 + 2 / aspect_ratio)
    highest = assumptions[:rigid_max_lift]
    angles = collect(range(0.0, highest / slope + deg2rad(2); length=25))
    lift = min.(slope .* angles, highest)
    drag = assumptions[:rigid_profile_drag] .+
           lift .^ 2 ./ (π * aspect_ratio * assumptions[:rigid_span_efficiency])
    return KitePolar(angles, lift, drag)
end

"""
    hover_power(mass, area, assumptions)

Electric power [W] that hovers `mass` [kg] of kite and tether on a wing of `area` [m^2]:
momentum theory at the rotor area, thrust margin and air density of the assumptions.
"""
function hover_power(mass, area, assumptions::Assumptions)
    gravity = Environment(assumptions).gravity
    thrust = assumptions[:rigid_hover_thrust_ratio] * gravity * mass
    disc = assumptions[:rigid_rotor_area_ratio] * area
    return sqrt(thrust^3 /
                (2assumptions[:rigid_hover_air_density] *
                 assumptions[:rigid_rotor_fill] * disc)) /
           assumptions[:rigid_hover_efficiency]
end

"""
    rigid_kite_model(area, count, assumptions)

[`KiteModel`](@ref) of one rigid VTOL kite of `area` [m^2], its tether force limit [N],
tether diameter [m] and the [`RigidAirframe`](@ref) of `count` such kites.
"""
function rigid_kite_model(area, count, assumptions::Assumptions)
    env = Environment(assumptions)
    max_force = 1e3assumptions[:rigid_max_force_per_area] * area
    tether_diameter = sqrt(4max_force / (π * assumptions[:rigid_tether_stress]))
    span = sqrt(area * assumptions[:rigid_aspect_ratio])
    tether_length = assumptions[:rigid_tether_length_ratio] * span
    tether_mass = assumptions[:rigid_tether_density] * π * tether_diameter^2 / 4 *
                  tether_length
    mass = assumptions[:rigid_reference_mass] *
           (area / assumptions[:rigid_reference_area])^
           (assumptions[:rigid_mass_exponent] / 2)
    drag = assumptions[:rigid_idle_rotor_drag] +
           assumptions[:rigid_tether_drag_coefficient] * tether_diameter * tether_length /
           (4area)
    polar = rigid_polar(assumptions)
    model = KiteModel(area, mass + tether_mass / 2, tether_length, env.air_density,
        env.gravity, polar, drag, polar.angle_of_attack[findfirst(>=(0.05), polar.lift)],
        polar.angle_of_attack[argmax(polar.lift)] -
        deg2rad(assumptions[:kite_stall_margin]),
        assumptions[:rigid_min_turn_radius] * span, true)
    airframe = RigidAirframe(count, mass, tether_mass,
        hover_power(mass + tether_mass, area, assumptions), π * model.min_turn_radius^2)
    return model, max_force, tether_diameter, airframe
end

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
launch there too, since its rotors lift it from rest, and hovers within its own limits on
wind and sea in launch and landing.
"""
function rigid_wind_limits(lowest_wind, assumptions::Assumptions)
    hover_wind = assumptions[:rigid_hover_max_wind]
    hover_waves = assumptions[:rigid_hover_max_wave_height]
    return (; max_wind=assumptions[:rigid_max_wind], min_flight_wind=lowest_wind,
        launch_min_wind=lowest_wind, launch_max_wind=hover_wind,
        launch_max_wave_height=hover_waves, night_launch=assumptions[:kite_night_launch] > 0,
        landing_max_wind=hover_wind, landing_max_wave_height=hover_waves)
end

"""
    rigid_kites_fit(count, hull, assumptions)

Whether `count` perches of rigid kites of the unit area of the assumptions stand one span
apart along the deck of `hull`.
"""
function rigid_kites_fit(count, hull::Hull, assumptions::Assumptions)
    span = sqrt(assumptions[:rigid_unit_area] * assumptions[:rigid_aspect_ratio])
    return count * span <= assumptions[:deck_length_fraction] * hull.length
end

"""
    rigid_kite_rig(total_area, hull, assumptions; courses, side_weights)

Rigid VTOL kites of about `total_area` [m^2] together on `hull`, each of the unit area of
the assumptions and with a pattern table over `courses` [rad] and `side_weights`, or
`nothing` where they do not fit ([`rigid_kites_fit`](@ref)).
"""
function rigid_kite_rig(total_area, hull::Hull, assumptions::Assumptions;
        courses=deg2rad.(0.0:15.0:180.0), side_weights=[0.0, 0.5, 1.0, 3.0])
    area = assumptions[:rigid_unit_area]
    count = max(round(Int, total_area / area), 1)
    rigid_kites_fit(count, hull, assumptions) || return nothing
    model, max_force, tether_diameter, airframe = rigid_kite_model(area, count, assumptions)
    forces = pattern_table(model, max_force, assumptions, RIGID_WIND_SPEEDS, courses,
        side_weights)
    lowest_wind = max(lowest_flying_wind(RIGID_WIND_SPEEDS, forces),
        crosswind_min_wind(model, deg2rad(assumptions[:kite_min_elevation])))
    return KiteRig(; area, tether_diameter, model.tether_length,
        reference_height=model.tether_length * sin(deg2rad(25)),
        rigid_wind_limits(lowest_wind, assumptions)..., max_force,
        attach_height=assumptions[:kite_attach_height] * hull.length /
                      assumptions[:reference_length],
        attach_position=lateral_centre(hull), wind_speeds=RIGID_WIND_SPEEDS, courses,
        side_weights, forces, airframe)
end

"""
    KiteRig(area, aspect_ratio, hull, assumptions;
            attach_position=kite_tow_point(hull, assumptions))

Kite of projected `area` [m^2] and `aspect_ratio` with its pattern table, towing from
`attach_position` [m] forward of midship.
"""
function KiteRig(area::Real, aspect_ratio::Real, hull::Hull, assumptions::Assumptions;
        attach_position=kite_tow_point(hull, assumptions))
    scale = hull.length / assumptions[:reference_length]
    model, max_force, tether_diameter = kite_model(area, aspect_ratio, assumptions)
    tether_length = model.tether_length
    wind_speeds = [3.0:1.0:9.0; 10.5; 12.0:3.0:30.0]
    courses = deg2rad.(0.0:15.0:180.0)
    side_weights = [0.0, 0.5, 1.0, 3.0]
    return KiteRig(; area, tether_diameter, tether_length,
        reference_height=tether_length * sin(deg2rad(25)),
        max_wind=assumptions[:kite_max_wind],
        min_flight_wind=min_flight_wind(model, assumptions),
        launch_min_wind=launch_min_wind(model,
            rope_mass(tether_diameter, tether_length, assumptions), assumptions),
        launch_max_wind=assumptions[:kite_launch_max_wind],
        launch_max_wave_height=assumptions[:kite_launch_max_wave_height],
        night_launch=assumptions[:kite_night_launch] > 0,
        landing_max_wind=assumptions[:kite_landing_max_wind],
        landing_max_wave_height=assumptions[:kite_landing_max_wave_height], max_force,
        attach_height=assumptions[:kite_attach_height] * scale,
        attach_position, wind_speeds, courses, side_weights,
        forces=pattern_table(model, max_force, assumptions, wind_speeds, courses,
            side_weights))
end

"""
    table_weights(grid, value)

Index of the grid interval holding `value` and the weight of its upper end.
"""
function table_weights(grid, value)
    i = clamp(searchsortedlast(grid, value), 1, length(grid) - 1)
    return i, clamp((value - grid[i]) / (grid[i + 1] - grid[i]), 0.0, 1.0)
end

"""
    rig_force(rig::KiteRig, env, wind_10m, true_angle, ship_speed, trim)

Force of the best pattern for side weight number `trim`, interpolated in newtons over
apparent wind speed and course, reduced by [`loop_interaction`](@ref), held to the tether
limit and summed over the kites; no force where the kite cannot fly or the wind is below
the table.
"""
function rig_force(rig::KiteRig, env::Environment, wind_10m, true_angle, ship_speed, trim)
    wind = wind_at_height(env, wind_10m, rig.reference_height)
    speed, angle = apparent_wind(wind, true_angle, ship_speed)
    max(rig.min_flight_wind, first(rig.wind_speeds)) <= speed <= rig.max_wind ||
        return NO_RIG_FORCE
    i, speed_weight = table_weights(rig.wind_speeds, speed)
    j, course_weight = table_weights(rig.courses, π - angle)
    downwind, crosswind = 0.0, 0.0
    for (row, row_weight) in ((i, 1 - speed_weight), (i + 1, speed_weight)),
        (column, column_weight) in ((j, 1 - course_weight), (j + 1, course_weight))

        force = rig.forces[row, column, trim].force
        isfinite(force[1]) || return NO_RIG_FORCE
        load = 0.5env.air_density * rig.wind_speeds[row]^2 * rig.area
        downwind += row_weight * column_weight * load * force[1]
        crosswind += row_weight * column_weight * load * force[2]
    end
    lone = hypot(downwind, crosswind)
    interaction = loop_interaction(rig, lone / (0.5env.air_density * speed^2))
    limit = kite_count(rig) * min(interaction, rig.max_force / lone)
    thrust = limit * (crosswind * sin(angle) - downwind * cos(angle))
    side = limit * (crosswind * cos(angle) + downwind * sin(angle))
    return RigForce(thrust, side, side * rig.attach_height, side * rig.attach_position)
end

trim_settings(rig::KiteRig) = eachindex(rig.side_weights)

"""
    CombinedRig{S}

Towing kite flown over a standing rig of wings or rotors, of type `S`; the standing rig
works whether or not the kite flies.
"""
struct CombinedRig{S}
    kite::KiteRig
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

Distance [m] forward of midship of the launch mast at the middle of its
[`launch_mast_reserve`](@ref) at the forward end of the deck for rigs.
"""
function launch_mast_position(hull::Hull, assumptions::Assumptions)
    deck_length = assumptions[:deck_length_fraction] * hull.length
    return (deck_length - launch_mast_reserve(assumptions)) / 2
end

"""
    kite_tow_point(hull, assumptions)

Distance [m] forward of midship of a soft kite's tow point when it flies alone:
the share `kite_tow_position` of the way from midship to the [`launch_mast_position`](@ref).
"""
kite_tow_point(hull::Hull, assumptions::Assumptions) =
    assumptions[:kite_tow_position] * launch_mast_position(hull, assumptions)

"""
    CombinedRig(kite_area, kite_aspect_ratio, standing_type, standing_area, hull,
                assumptions)

Kite of projected `kite_area` [m^2] and `kite_aspect_ratio` towing from a launch mast at
the forward end of the deck for rigs, over `standing_area` [m^2] of `standing_type`
(`WingRig` or `RotorRig`) on the deck behind it, or `nothing` if those do not fit.
"""
function CombinedRig(kite_area, kite_aspect_ratio, standing_type, standing_area,
        hull::Hull, assumptions::Assumptions)
    standing = standing_type(standing_area, hull, assumptions;
        forward_reserve=launch_mast_reserve(assumptions))
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

"every pair of kite trim and standing rig trim, chosen jointly"
trim_settings(rig::CombinedRig) =
    vec(collect(Iterators.product(trim_settings(rig.kite), trim_settings(rig.standing))))

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

trim_settings(down::DownRig) = down.working_share > 0 ? trim_settings(down.rig) :
                               [stopped_setting(down.rig)]

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
