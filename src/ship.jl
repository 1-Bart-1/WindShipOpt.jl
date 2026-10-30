"""
    Fuel

Fuel burned on board, with its price including any carbon charge.
"""
struct Fuel
    name::Symbol
    "price including carbon charge [USD/J]"
    price::Float64
    "lower heating value [J/kg]"
    heating_value::Float64
    "tank-to-wake CO2 [kg/J]"
    carbon_intensity::Float64
end

function vlsfo(assumptions::Assumptions)
    intensity = assumptions[:vlsfo_carbon_intensity]
    carbon_charge = assumptions[:carbon_price] * assumptions[:carbon_coverage] * intensity
    return Fuel(:vlsfo, (assumptions[:vlsfo_price] + carbon_charge) / 1e9,
        1e6assumptions[:vlsfo_heating_value], intensity * 1e3 / 1e9)
end

e_methanol(assumptions::Assumptions) = Fuel(:e_methanol,
    assumptions[:e_methanol_price] / 1e9, 1e6assumptions[:methanol_heating_value], 0.0)

"""
    ShipDesign(kind, length; wing_area=0, kite_area=0)

Design point of the optimization. `kind` is one of
- `:vlsfo`: mechanical drive on VLSFO, no rig (the traditional baseline)
- `:methanol`: diesel-electric on e-methanol, no rig
- `:wing`: diesel-electric on e-methanol with rigid wings of total `wing_area` [m^2]
- `:kite`: diesel-electric on e-methanol with a towing kite of `kite_area` [m^2]
"""
Base.@kwdef struct ShipDesign
    kind::Symbol
    "waterline length [m]"
    length::Float64
    wing_area::Float64 = 0.0
    kite_area::Float64 = 0.0
end

ShipDesign(kind::Symbol, length::Real; kwargs...) = ShipDesign(; kind, length, kwargs...)

"""
    Ship

A design turned into the models that the performance table and the cost model use.
"""
struct Ship{R}
    design::ShipDesign
    env::Environment
    hull::Hull
    wave_coefficients::WaveCoefficients
    propeller::Propeller
    powertrain::Powertrain
    rig::R
    fuel::Fuel
    "frontal windage area [m^2]"
    windage_area::Float64
    windage_drag_coefficient::Float64
    "righting moment per radian of heel [N m/rad]"
    righting_stiffness::Float64
    heel_limit::Float64
    leeway_limit::Float64
    "highest speed through the water [m/s]"
    max_speed::Float64
end

"""
    Ship(design, assumptions)

Ship for `design`, or `nothing` if its rig does not fit on the hull. Installed power
is sized for the service speed in calm water plus the sea margin.
"""
function Ship(design::ShipDesign, assumptions::Assumptions)
    env = Environment(assumptions)
    hull = Hull(design.length, assumptions)
    rig = design_rig(design, hull, assumptions)
    isnothing(rig) && design.kind in (:wing, :kite) && return nothing
    scale = hull.length / assumptions[:reference_length]
    stiffness = displacement_mass(hull, env) * env.gravity *
                assumptions[:metacentric_height_ratio] * hull.beam
    electric = design.kind != :vlsfo
    sizing_powertrain = Powertrain(; installed_power=Inf, unit_count=1,
        peak_efficiency=1.0, part_load_penalty=0.0,
        transmission_efficiency=electric ? assumptions[:electric_chain_efficiency] :
                                assumptions[:shaft_efficiency],
        hotel_load=1e3assumptions[:hotel_load])
    ship = Ship(design, env, hull, WaveCoefficients(hull), Propeller(hull, assumptions),
        sizing_powertrain, rig, electric ? e_methanol(assumptions) : vlsfo(assumptions),
        hull.beam * assumptions[:superstructure_height] * scale,
        assumptions[:windage_drag_coefficient], stiffness,
        deg2rad(assumptions[:heel_limit]), deg2rad(assumptions[:leeway_limit]),
        assumptions[:max_froude_number] * sqrt(env.gravity * hull.length))
    service_speed = assumptions[:service_speed] * KNOT
    service_output = calm_output_power(ship, service_speed)
    installed_power = service_output * (1 + assumptions[:sea_margin]) /
                      assumptions[:engine_rating_fraction]
    powertrain = Powertrain(; installed_power,
        unit_count=electric ? Int(assumptions[:genset_count]) : 1,
        peak_efficiency=electric ? assumptions[:methanol_genset_efficiency] :
                        assumptions[:vlsfo_engine_efficiency],
        part_load_penalty=assumptions[:part_load_penalty],
        transmission_efficiency=sizing_powertrain.transmission_efficiency,
        hotel_load=sizing_powertrain.hotel_load)
    return Ship(design, env, hull, ship.wave_coefficients, ship.propeller, powertrain, rig,
        ship.fuel, ship.windage_area, ship.windage_drag_coefficient, stiffness,
        ship.heel_limit, ship.leeway_limit, ship.max_speed)
end

function design_rig(design::ShipDesign, hull::Hull, assumptions::Assumptions)
    design.kind == :wing && return WingRig(design.wing_area, hull, assumptions)
    design.kind == :kite && return KiteRig(design.kite_area, hull, assumptions)
    return nothing
end

const KNOT = 1852 / 3600

function windage_resistance(ship::Ship, wind_10m, true_angle, speed)
    apparent_speed, apparent_angle = apparent_wind(wind_10m, true_angle, speed)
    return 0.5ship.env.air_density * apparent_speed^2 * ship.windage_area *
           ship.windage_drag_coefficient * cos(apparent_angle)
end

"""
    required_thrust(ship, speed, wind_10m, true_angle, force)

Net propeller thrust [N] the ship needs at `speed` with the rig delivering `force`, or
`Inf` if the rig force exceeds the heel or leeway limit.
"""
function required_thrust(ship::Ship, speed, wind_10m, true_angle, force::RigForce)
    heel = abs(force.heeling_moment) / ship.righting_stiffness
    heel <= ship.heel_limit || return Inf
    leeway, induced_drag = leeway_drag(ship.hull, ship.env, speed, abs(force.side))
    leeway <= ship.leeway_limit || return Inf
    return resistance(ship.hull, ship.env, speed; coefficients=ship.wave_coefficients) +
           windage_resistance(ship, wind_10m, true_angle, speed) + induced_drag -
           force.thrust
end

"""
    best_trim(ship, speed, wind_10m, true_angle)

Lowest required propeller thrust [N] over all rig trims, and the rig force at that trim.
"""
best_trim(ship::Ship{Nothing}, speed, wind_10m, true_angle) =
    required_thrust(ship, speed, wind_10m, true_angle, NO_RIG_FORCE), NO_RIG_FORCE

function best_trim(ship::Ship, speed, wind_10m, true_angle)
    best = (Inf, NO_RIG_FORCE)
    for trim in trim_settings(ship.rig)
        force = rig_force(ship.rig, ship.env, wind_10m, true_angle, speed, trim)
        thrust = required_thrust(ship, speed, wind_10m, true_angle, force)
        thrust < first(best) && (best = (thrust, force))
    end
    return best
end

best_thrust(ship::Ship, speed, wind_10m, true_angle) =
    first(best_trim(ship, speed, wind_10m, true_angle))

function calm_output_power(ship::Ship, speed)
    thrust = best_thrust(ship, speed, 0.0, 0.0)
    delivered = delivered_power(ship.propeller, ship.env, speed, thrust)
    return delivered / ship.powertrain.transmission_efficiency +
           ship.powertrain.hotel_load
end

"""
    fuel_power(ship, speed, wind_10m, true_angle)

Fuel energy rate [W] at `speed` [m/s] through the water in a 10 m wind of `wind_10m`
[m/s] from `true_angle` [rad] off the bow, or `Inf` if infeasible.
"""
function fuel_power(ship::Ship, speed, wind_10m, true_angle)
    thrust = best_thrust(ship, speed, wind_10m, true_angle)
    isfinite(thrust) || return Inf
    delivered = delivered_power(ship.propeller, ship.env, speed, thrust)
    return fuel_power(ship.powertrain, delivered)
end
