# Door-to-door cost per tonne from Rotterdam to a small Eastern Caribbean island (Roseau,
# Dominica) over the island's annual import volume, for three delivery chains:
# - direct: a coaster, with or without kite, straight to the island
# - direct, largest: the largest ship the island quay takes, straight to the island
# - hub: the largest ship Jarry takes, transshipment at Jarry, a coaster feeder to Roseau
# The ocean legs use the Guadeloupe corridors; Roseau lies 105 km south of Jarry. Prints
# the comparison and writes output/chains.csv.
using Printf
include("setup.jl")

outbound, inbound = corridors(:caribbean, 8)

"""
    length_for_draft(depth, assumptions)

Length [m] of the scaled reference hull whose draft fits `depth` [m] with clearance.
"""
length_for_draft(depth, assumptions) = assumptions[:reference_length] *
    (depth - assumptions[:under_keel_clearance]) / assumptions[:reference_draft]

"""
    feeder_cost(ship, distance, assumptions)

Cost per tonne [USD/t] of a full feeder round trip over `distance` [m] each way at service
speed in calm water, returning empty, with a port call at each end.
"""
function feeder_cost(ship, distance, assumptions)
    costs = ShipCosts(ship, assumptions)
    speed = assumptions[:service_speed] * KNOT
    thrust = WindShipOpt.best_thrust(ship, speed, 0.0, 0.0)
    power = fuel_power(ship.powertrain,
        delivered_power(ship.propeller, ship.env, speed, thrust))
    sailing_hours = 2distance / speed / 3600
    hours = sailing_hours + 2 * 24assumptions[:port_time_per_call]
    cargo = WindShipOpt.cargo_mass(costs.hold)
    cost = WindShipOpt.time_cost(costs, assumptions, cargo) * hours +
           power * sailing_hours * 3600 * ship.fuel.price +
           WindShipOpt.port_costs(ship.hull, assumptions)
    return cost / cargo
end

"""
    holding_cost(lot, volume, assumptions)

Interest [USD/t] on the stock the island holds between deliveries of `lot` [t] at an
annual import `volume` [t/year].
"""
holding_cost(lot, volume, assumptions) =
    assumptions[:cargo_value] * assumptions[:discount_rate] * lot / volume / 2

"""
    transshipment_cost(assumptions)

Hub handling and the interest on cargo waiting at the hub [USD/t].
"""
transshipment_cost(assumptions) =
    assumptions[:transshipment_lifts] * assumptions[:transshipment_lift_cost] /
    assumptions[:cargo_per_teu] +
    assumptions[:hub_dwell] * assumptions[:cargo_value] * assumptions[:discount_rate] / 365

island_length = length_for_draft(assumptions[:island_quay_depth], assumptions)
hub_length = length_for_draft(assumptions[:hub_draft_limit], assumptions)
feeder_distance = WindShipOpt.distance(16.24, -61.55, 15.30, -61.39)
sampled_departures = departures[1:6:end]
crew_scenarios = [("crewed", assumptions),
    ("crewless", with_value(assumptions, :crew_cost, 0.0))]
designs = [("coaster", ShipDesign(:vlsfo, 85.0)),
    ("coaster + kite 800", ShipDesign(:vlsfo, 85.0; kite_area=800.0)),
    ("island max", ShipDesign(:vlsfo, island_length)),
    ("island max + kite 3200", ShipDesign(:vlsfo, island_length; kite_area=3200.0)),
    ("hub max", ShipDesign(:vlsfo, hub_length))]
cases = [(scenario, name, design) for (scenario, _) in crew_scenarios
         for (name, design) in designs]

trips = Vector{Any}(nothing, length(cases))
Threads.@threads for i in eachindex(cases)
    scenario, _, design = cases[i]
    case_assumptions = Dict(crew_scenarios)[scenario]
    trips[i] = round_trip(Ship(design, case_assumptions), outbound, inbound, weather,
        sampled_departures, case_assumptions)
end

tonne_km_per_tonne = (outbound.track_length +
                      assumptions[:backhaul_fraction] * inbound.track_length) / 1e3
println(length(sampled_departures), " departures; island length ",
    round(island_length; digits=1), " m, hub length ", round(hub_length; digits=1), " m")
println("transshipment ", round(transshipment_cost(assumptions); digits=1), " USD/t, ",
    "feeder market price ",
    round(assumptions[:feeder_market_price] / assumptions[:cargo_per_teu]; digits=1),
    " USD/t, feeder distance ", round(feeder_distance / 1e3; digits=0), " km")
chains = open(joinpath(mkpath(joinpath(@__DIR__, "..", "output")), "chains.csv"), "w")
println(chains, "crew,volume,coaster,coaster_kite,island,island_kite,hub,hub_market")
for (scenario, scenario_assumptions) in crew_scenarios
    println("\n", scenario)
    sea = Dict(name => trips[i].cost_per_tonne_km * tonne_km_per_tonne
               for (i, (case_scenario, name, _)) in enumerate(cases)
               if case_scenario == scenario)
    lot = Dict(name => trips[i].cargo for (i, (case_scenario, name, _)) in enumerate(cases)
               if case_scenario == scenario)
    feeder = feeder_cost(Ship(ShipDesign(:vlsfo, 85.0), scenario_assumptions),
        feeder_distance, scenario_assumptions)
    @printf("%-24s %8s %8s\n", "sea leg [USD/t]", "", "lot [t]")
    for (name, _) in designs
        @printf("%-24s %8.1f %8.0f\n", name, sea[name], lot[name])
    end
    @printf("feeder cost %.1f USD/t\n", feeder)
    @printf("%10s | %9s %9s %9s %9s | %9s %9s\n", "t/year", "coaster", "+kite",
        "island", "+kite", "hub cost", "hub mkt")
    for volume in (2e4, 5e4, 1e5, 3e5, 1e6)
        direct = [sea[name] + holding_cost(lot[name], volume, scenario_assumptions)
                  for name in ("coaster", "coaster + kite 800", "island max",
                      "island max + kite 3200")]
        hub = sea["hub max"] + transshipment_cost(scenario_assumptions) +
              holding_cost(lot["coaster"], volume, scenario_assumptions)
        market = hub + scenario_assumptions[:feeder_market_price] /
                       scenario_assumptions[:cargo_per_teu]
        @printf("%10.0f | %9.1f %9.1f %9.1f %9.1f | %9.1f %9.1f\n", volume, direct...,
            hub + feeder, market)
        @printf(chains, "%s,%.0f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f\n", scenario, volume,
            direct..., hub + feeder, market)
    end
end
close(chains)
