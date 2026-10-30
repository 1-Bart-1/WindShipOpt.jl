capital_recovery(rate, years) = rate / (1 - (1 + rate)^-years)

"""
    ShipCosts

Capital, fixed annual cost and cargo capacity of a ship, excluding fuel.
"""
struct ShipCosts
    "capital cost [USD]"
    capital::Float64
    "annuity, crew, maintenance and kite upkeep [USD/year]"
    fixed_annual::Float64
    "deadweight at design draft [t]"
    deadweight::Float64
    "rig mass [t]"
    rig_mass::Float64
end

function ShipCosts(ship::Ship, assumptions::Assumptions)
    rate = assumptions[:discount_rate]
    displacement = displacement_mass(ship.hull, ship.env) / 1e3
    lightship = assumptions[:lightship_fraction] * displacement
    hull = assumptions[:hull_cost_per_lightship] * lightship
    propulsion_rate = ship.design.kind == :vlsfo ?
                      assumptions[:mechanical_propulsion_cost] :
                      assumptions[:electric_propulsion_cost]
    propulsion = propulsion_rate * ship.powertrain.installed_power / 1e3
    annuity = capital_recovery(rate, assumptions[:hull_lifetime]) * (hull + propulsion)
    rig_capital, rig_mass, rig_annual = rig_costs(ship.rig, assumptions)
    capital = hull + propulsion + rig_capital
    fixed_annual = annuity + rig_annual + assumptions[:crew_cost] +
                   assumptions[:maintenance_fraction] * capital
    return ShipCosts(capital, fixed_annual, displacement - lightship, rig_mass)
end

rig_costs(::Nothing, assumptions) = (0.0, 0.0, 0.0)

function rig_costs(rig::WingRig, assumptions)
    capital = assumptions[:wing_cost_per_area] * total_area(rig)
    annuity = capital_recovery(assumptions[:discount_rate], assumptions[:wing_lifetime]) *
              capital
    return capital, assumptions[:wing_mass_per_area] * total_area(rig), annuity
end

function rig_costs(rig::KiteRig, assumptions)
    capital = assumptions[:kite_cost_per_area] * rig.area
    annuity = capital_recovery(assumptions[:discount_rate], assumptions[:kite_lifetime]) *
              capital
    upkeep = assumptions[:kite_maintenance_per_area] * rig.area
    return capital, assumptions[:kite_mass_per_area] * rig.area, annuity + upkeep
end

"""
    time_cost(costs, assumptions)

Cost of one hour of voyage time [USD/h]: the fixed annual cost spread over the trading
hours, plus interest on the outbound cargo. Minimising fuel cost plus this time cost per
round trip minimises the cost per tonne-kilometre.
"""
function time_cost(costs::ShipCosts, assumptions::Assumptions)
    trading_hours = 8760assumptions[:availability]
    cargo_interest = costs.deadweight * assumptions[:cargo_value] *
                     assumptions[:discount_rate] / 8760
    return costs.fixed_annual / trading_hours + cargo_interest
end

"""
    RoundTrip

Mean outcome of one design over all departures in the weather sample.
"""
struct RoundTrip
    design::ShipDesign
    "transport cost [USD per tonne-km]"
    cost_per_tonne_km::Float64
    "fuel energy per round trip [GJ]"
    fuel_energy::Float64
    "fuel per tonne-km [MJ]"
    fuel_per_tonne_km::Float64
    "CO2 per tonne-km, tank-to-wake [g]"
    carbon_per_tonne_km::Float64
    outbound_days::Float64
    return_days::Float64
    "cargo carried outbound [t]"
    cargo::Float64
    capital::Float64
    "installed engine or genset power [kW]"
    installed_power::Float64
end

"""
    round_trip(ship, outbound, inbound, weather, departures, assumptions)

Route `ship` out along `outbound` and back along `inbound` for each departure time
[h], and turn the mean result into the cost per tonne-km of the transport service.
Returns `nothing` if any passage is infeasible.
"""
function round_trip(ship::Ship, outbound::Corridor, inbound::Corridor, weather,
        departures, assumptions::Assumptions)
    costs = ShipCosts(ship, assumptions)
    hourly = time_cost(costs, assumptions)
    table = PerformanceTable(ship)
    port_hours = 24assumptions[:port_time_per_call]
    legs = map(departures) do departure
        out = route(outbound, table, ship.fuel, weather, departure; time_cost=hourly)
        isnothing(out) && return nothing
        back = route(inbound, table, ship.fuel, weather,
            departure + out.duration + port_hours; time_cost=hourly)
        isnothing(back) && return nothing
        return out, back
    end
    any(isnothing, legs) && return nothing
    out_energy = mean(first(pair).fuel_energy for pair in legs)
    back_energy = mean(last(pair).fuel_energy for pair in legs)
    out_hours = mean(first(pair).duration for pair in legs)
    back_hours = mean(last(pair).duration for pair in legs)
    largest_leg = maximum(max(first(pair).fuel_energy, last(pair).fuel_energy)
                          for pair in legs)
    tank = assumptions[:fuel_reserve_factor] * largest_leg / ship.fuel.heating_value / 1e3
    cargo = costs.deadweight - costs.rig_mass - assumptions[:stores_mass] - tank
    cargo > 0 || return nothing
    energy = out_energy + back_energy
    round_trip_hours = out_hours + back_hours + 2port_hours
    voyage_cost = energy * ship.fuel.price + 2assumptions[:port_cost_per_call] +
                  hourly * round_trip_hours
    tonne_km = cargo * (1 + assumptions[:backhaul_fraction]) *
               outbound.track_length / 1e3
    return RoundTrip(ship.design, voyage_cost / tonne_km, energy / 1e9,
        energy / 1e6 / tonne_km, energy * ship.fuel.carbon_intensity * 1e3 / tonne_km,
        out_hours / 24, back_hours / 24, cargo, costs.capital,
        ship.powertrain.installed_power / 1e3)
end
