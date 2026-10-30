"""
    Propeller

Single screw behind the hull, modelled as an actuator disk with a viscous loss factor.
"""
Base.@kwdef struct Propeller
    "disk area [m^2]"
    disk_area::Float64
    "Taylor wake fraction [-]"
    wake_fraction::Float64
    "thrust deduction fraction [-]"
    thrust_deduction::Float64
    "real over ideal open-water efficiency [-]"
    viscous_efficiency::Float64
end

function Propeller(hull::Hull, assumptions::Assumptions)
    diameter = assumptions[:propeller_diameter_ratio] * hull.draft
    wake_fraction = 0.5block_coefficient(hull) - 0.05
    return Propeller(; disk_area=π * diameter^2 / 4, wake_fraction,
        thrust_deduction=assumptions[:thrust_deduction_ratio] * wake_fraction,
        viscous_efficiency=assumptions[:propeller_viscous_efficiency])
end

"""
    delivered_power(propeller, env, speed, required_thrust)

Power [W] delivered to the propeller to make the ship produce a net forward force of
`required_thrust` [N] at `speed` [m/s]; zero when the rig alone is enough.
"""
function delivered_power(propeller::Propeller, env::Environment, speed, required_thrust)
    required_thrust > 0 || return 0.0
    thrust = required_thrust / (1 - propeller.thrust_deduction)
    inflow = speed * (1 - propeller.wake_fraction)
    loading = thrust / (0.5env.water_density * propeller.disk_area * inflow^2)
    efficiency = propeller.viscous_efficiency * 2 / (1 + sqrt(1 + loading))
    return thrust * inflow / efficiency
end

"""
    Powertrain

Engines or gensets turning fuel into delivered propeller power and hotel power.
"""
Base.@kwdef struct Powertrain
    "maximum continuous rating of all units together [W]"
    installed_power::Float64
    "number of identical units that can be switched on and off"
    unit_count::Int
    "peak fuel-to-output efficiency of one unit [-]"
    peak_efficiency::Float64
    "efficiency loss coefficient at part load [-]"
    part_load_penalty::Float64
    "efficiency from unit output to propeller shaft [-]"
    transmission_efficiency::Float64
    "constant electrical consumption on board [W]"
    hotel_load::Float64
end

"""
    fuel_power(powertrain, delivered)

Fuel energy rate [W] to supply `delivered` propeller power [W] plus the hotel load with
the most efficient number of running units, or `Inf` above the installed power.
"""
function fuel_power(powertrain::Powertrain, delivered)
    output = delivered / powertrain.transmission_efficiency + powertrain.hotel_load
    output <= powertrain.installed_power || return Inf
    unit_power = powertrain.installed_power / powertrain.unit_count
    best = Inf
    for running in ceil(Int, output / unit_power):powertrain.unit_count
        load = output / (running * unit_power)
        efficiency = powertrain.peak_efficiency *
                     (1 - powertrain.part_load_penalty * (1 - load)^2)
        best = min(best, output / efficiency)
    end
    return best
end
