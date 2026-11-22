# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

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

"""
    Propeller(hull, diameter_ratio, assumptions)
    Propeller(hull, assumptions)

Propeller behind `hull` of `diameter_ratio` times its draft, by default the reference
coaster's, with the wake and thrust deduction of its block coefficient (MAN ES 2023).
"""
function Propeller(hull::Hull, diameter_ratio, assumptions::Assumptions)
    diameter = diameter_ratio * hull.draft
    wake_fraction = 0.5block_coefficient(hull) - 0.05
    return Propeller(; disk_area=π * diameter^2 / 4, wake_fraction,
        thrust_deduction=assumptions[:thrust_deduction_ratio] * wake_fraction,
        viscous_efficiency=assumptions[:propeller_viscous_efficiency])
end

Propeller(hull::Hull, assumptions::Assumptions) =
    Propeller(hull, assumptions[:propeller_diameter_ratio], assumptions)

"""
    delivered_power(propeller, env, speed, required_thrust)

Power [W] delivered to the propeller to make the ship produce a net forward force of
`required_thrust` [N] at `speed` [m/s]; zero when the rig alone is enough.
"""
delivered_power(propeller::Propeller, env::Environment, speed, required_thrust) =
    delivered_power(PropellerLoad(propeller, env, speed), required_thrust)

"""
    PropellerLoad(propeller, env, speed)

What [`delivered_power`](@ref) needs of `propeller` at ship `speed` [m/s].
"""
struct PropellerLoad
    "propeller thrust per unit of net forward force [-]"
    thrust_factor::Float64
    "reciprocal of the dynamic pressure of the inflow times the disk area [1/N]"
    inverse_disk_load::Float64
    "inflow speed over twice the viscous efficiency [m/s]"
    ideal_power_factor::Float64
end

function PropellerLoad(propeller::Propeller, env::Environment, speed)
    inflow = speed * (1 - propeller.wake_fraction)
    return PropellerLoad(1 / (1 - propeller.thrust_deduction),
        1 / (0.5env.water_density * propeller.disk_area * inflow^2),
        inflow / (2propeller.viscous_efficiency))
end

"""
    delivered_power(load, required_thrust)

[`delivered_power`](@ref) of the [`PropellerLoad`](@ref) `load`.
"""
function delivered_power(load::PropellerLoad, required_thrust)
    required_thrust > 0 || return 0.0
    thrust = required_thrust * load.thrust_factor
    loading = thrust * load.inverse_disk_load
    return thrust * load.ideal_power_factor * (1 + sqrt(1 + loading))
end

"""
    delivered_thrust(propeller, env, speed, power)

Net forward force [N] that `power` [W] delivered to the propeller makes at `speed` [m/s]:
the inverse of [`delivered_power`](@ref), the real root of its cubic in propeller thrust.
"""
function delivered_thrust(propeller::Propeller, env::Environment, speed, power)
    inflow = speed * (1 - propeller.wake_fraction)
    disk_load = 0.5env.water_density * propeller.disk_area * inflow^2
    ideal_thrust = 2propeller.viscous_efficiency * power / inflow
    linear = 2disk_load * ideal_thrust
    constant = disk_load * ideal_thrust^2
    root = cbrt(constant / 2 + sqrt(constant^2 / 4 + linear^3 / 27))
    return (root - linear / (3root)) * (1 - propeller.thrust_deduction)
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
    "lowest load a running unit holds unless one unit alone carries less [-]"
    min_load::Float64 = 0.0
end

"""
    fuel_power(powertrain, delivered)

Fuel energy rate [W] to supply `delivered` propeller power [W] plus the hotel load with
the most efficient number of running units that carry the load at no less than their
minimum load, or `Inf` above the installed power.
"""
function fuel_power(powertrain::Powertrain, delivered)
    output = delivered / powertrain.transmission_efficiency + powertrain.hotel_load
    output <= powertrain.installed_power || return Inf
    units = output * powertrain.unit_count / powertrain.installed_power
    fewest = ceil(units)
    fewest <= powertrain.unit_count || return Inf
    return output / unit_efficiency(powertrain, units / fewest)
end

unit_efficiency(powertrain::Powertrain, load) =
    powertrain.peak_efficiency * (1 - powertrain.part_load_penalty * (1 - load)^2)
