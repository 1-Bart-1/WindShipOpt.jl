"""
    wind_at_height(env, wind_10m, height)

Log-profile wind speed [m/s] at `height` [m] from the 10 m wind speed.
"""
wind_at_height(env::Environment, wind_10m, height) =
    wind_10m * log(height / env.roughness_length) / log(10 / env.roughness_length)

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

Rig force on the ship in the ship frame: forward thrust [N], side force [N] and heeling
moment about the waterline [N m].
"""
struct RigForce
    thrust::Float64
    side::Float64
    heeling_moment::Float64
end

const NO_RIG_FORCE = RigForce(0.0, 0.0, 0.0)

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
    "effective aspect ratio including the deck mirror effect [-]"
    effective_aspect_ratio::Float64
    max_lift_coefficient::Float64
    profile_drag_coefficient::Float64
    separation_drag_factor::Float64
    span_efficiency::Float64
    interference_factor::Float64
end

"""
    WingRig(total_area, hull, assumptions)

Wing rig of `total_area` [m^2] on `hull`, using as few wings as the air draft allows, or
`nothing` if the wings do not fit on deck.
"""
function WingRig(total_area::Real, hull::Hull, assumptions::Assumptions)
    scale = hull.length / assumptions[:reference_length]
    foot_height = assumptions[:deck_mount_height] * scale
    aspect_ratio = assumptions[:wing_aspect_ratio]
    max_height = assumptions[:max_air_draft] - foot_height
    count = ceil(Int, total_area / (max_height^2 / aspect_ratio))
    area = total_area / count
    height = sqrt(aspect_ratio * area)
    chord = height / aspect_ratio
    deck_needed = count * assumptions[:wing_spacing] * chord
    deck_needed <= assumptions[:deck_length_fraction] * hull.length || return nothing
    return WingRig(; count, area, height, foot_height,
        effective_aspect_ratio=assumptions[:wing_endplate_factor] * aspect_ratio,
        max_lift_coefficient=assumptions[:wing_max_lift_coefficient],
        profile_drag_coefficient=assumptions[:wing_profile_drag_coefficient],
        separation_drag_factor=assumptions[:wing_separation_drag_factor],
        span_efficiency=assumptions[:wing_span_efficiency],
        interference_factor=assumptions[:wing_interference_factor])
end

total_area(rig::WingRig) = rig.count * rig.area

function drag_coefficient(rig::WingRig, lift_coefficient)
    induced = 1 / (π * rig.effective_aspect_ratio * rig.span_efficiency)
    return rig.profile_drag_coefficient +
           (rig.separation_drag_factor + induced) * lift_coefficient^2
end

"""
    rig_force(rig::WingRig, env, wind_10m, true_angle, ship_speed, lift_coefficient)

Wing force at the given trim, with the apparent wind taken at the wing's mid height.
"""
function rig_force(rig::WingRig, env::Environment, wind_10m, true_angle, ship_speed,
        lift_coefficient)
    centre_height = rig.foot_height + rig.height / 2
    wind = wind_at_height(env, wind_10m, centre_height)
    speed, angle = apparent_wind(wind, true_angle, ship_speed)
    load = 0.5env.air_density * speed^2 * total_area(rig)
    drag = drag_coefficient(rig, lift_coefficient)
    thrust = load * rig.interference_factor *
             (lift_coefficient * sin(angle) - drag * cos(angle))
    side = load * (lift_coefficient * cos(angle) + drag * sin(angle))
    return RigForce(thrust, side, side * centre_height)
end

trim_settings(rig::WingRig) = range(0.0, rig.max_lift_coefficient; length=37)

"""
    KiteRig

Towing kite flown in figure-eight patterns from a mast on the bow.
"""
Base.@kwdef struct KiteRig
    "projected kite area [m^2]"
    area::Float64
    lift_coefficient::Float64
    "kite and bridle drag coefficient [-]"
    drag_coefficient::Float64
    "tether drag lumped at the kite, as a coefficient on kite area [-]"
    tether_drag_coefficient::Float64
    tether_length::Float64
    "elevation of the pattern centre [rad]"
    elevation::Float64
    "largest pattern azimuth off downwind [rad]"
    max_azimuth::Float64
    pattern_efficiency::Float64
    "apparent wind range at kite altitude in which the kite flies [m/s]"
    min_wind::Float64
    max_wind::Float64
    "depower limit on tether force [N]"
    max_force::Float64
    "tether attachment height above the waterline [m]"
    attach_height::Float64
end

"""
    KiteRig(area, hull, assumptions)

Kite of `area` [m^2] whose tether is sized for the kite's depower limit.
"""
function KiteRig(area::Real, hull::Hull, assumptions::Assumptions)
    scale = hull.length / assumptions[:reference_length]
    max_force = 1e3assumptions[:kite_max_force_per_area] * area
    tether_diameter = sqrt(4max_force / (π * assumptions[:tether_stress]))
    tether_length = assumptions[:tether_length]
    return KiteRig(; area,
        lift_coefficient=assumptions[:kite_lift_coefficient],
        drag_coefficient=assumptions[:kite_drag_coefficient],
        tether_drag_coefficient=assumptions[:tether_drag_coefficient] * tether_diameter *
                                tether_length / (4area),
        tether_length,
        elevation=deg2rad(assumptions[:kite_elevation]),
        max_azimuth=deg2rad(assumptions[:kite_max_azimuth]),
        pattern_efficiency=assumptions[:kite_pattern_efficiency],
        min_wind=assumptions[:kite_min_wind],
        max_wind=assumptions[:kite_max_wind],
        max_force,
        attach_height=assumptions[:kite_attach_height] * scale)
end

"""
    rig_force(rig::KiteRig, env, wind_10m, true_angle, ship_speed, azimuth)

Cycle-averaged kite force with the pattern centre at `azimuth` [rad] off the apparent
downwind direction, from the quasi-steady crosswind model without reeling.
"""
function rig_force(rig::KiteRig, env::Environment, wind_10m, true_angle, ship_speed,
        azimuth)
    altitude = rig.tether_length * sin(rig.elevation)
    wind = wind_at_height(env, wind_10m, altitude)
    speed, angle = apparent_wind(wind, true_angle, ship_speed)
    rig.min_wind <= speed <= rig.max_wind || return NO_RIG_FORCE
    drag = rig.drag_coefficient + rig.tether_drag_coefficient
    glide_ratio = rig.lift_coefficient / drag
    resultant = hypot(rig.lift_coefficient, drag)
    radial_wind = speed * cos(rig.elevation) * cos(azimuth)
    tether_force = rig.pattern_efficiency * 0.5env.air_density * rig.area * resultant *
                   radial_wind^2 * (1 + glide_ratio^2)
    tether_force = min(tether_force, rig.max_force)
    horizontal = tether_force * cos(rig.elevation)
    direction = angle + π + azimuth
    side = horizontal * sin(direction)
    return RigForce(horizontal * cos(direction), side, side * rig.attach_height)
end

trim_settings(rig::KiteRig) = range(-rig.max_azimuth, rig.max_azimuth; length=25)
