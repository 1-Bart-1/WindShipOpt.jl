# Round trip Rotterdam - Guadeloupe for VLSFO and e-methanol ships with and without a rig
# over a small design grid.
using Printf
include("setup.jl")

outbound, inbound = corridors(:caribbean, 8)

lengths = [60.0, 85.0, 110.0]
designs = ShipDesign[]
for length in lengths
    push!(designs, ShipDesign(:vlsfo, length), ShipDesign(:methanol, length))
    for area in (400.0, 800.0, 1500.0)
        push!(designs, ShipDesign(:methanol, length; wing_area=area))
    end
    for area in (100.0, 200.0, 400.0)
        push!(designs, ShipDesign(:methanol, length; kite_area=area))
    end
end

results = Vector{Any}(nothing, length(designs))
Threads.@threads for i in eachindex(designs)
    ship = Ship(designs[i], assumptions)
    isnothing(ship) && continue
    results[i] = round_trip(ship, outbound, inbound, weather, departures, assumptions)
end

@printf("%-9s %6s %6s %6s | %8s %8s %8s %6s %6s %7s %7s %6s\n", "drive", "L [m]", "wing",
    "kite", "USD/tkm", "MJ/tkm", "gCO2/tkm", "out d", "back d", "cargo t", "P kW", "flown")
for (design, result) in zip(designs, results)
    @printf("%-9s %6.0f %6.0f %6.0f | ", design.drive, design.length, design.wing_area,
        design.kite_area)
    if isnothing(result)
        println("infeasible")
        continue
    end
    @printf("%8.4f %8.4f %8.2f %6.1f %6.1f %7.0f %7.0f %5.0f%%\n", result.cost_per_tonne_km,
        result.fuel_per_tonne_km, result.carbon_per_tonne_km, result.outbound_days,
        result.return_days, result.cargo, result.installed_power, 100result.flight_share)
end
