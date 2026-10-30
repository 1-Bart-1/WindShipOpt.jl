# Round trip Rotterdam - Guadeloupe for the four ship kinds over a small design grid,
# on synthetic weather.
using Printf
using WindShipOpt

assumptions = Assumptions()
mask = north_atlantic_mask()
outbound, inbound = caribbean_corridors(mask)
weather = SyntheticWeather()
departures = [24.0 * (30 * month + 1) for month in 0:11]

lengths = [60.0, 85.0, 110.0]
designs = ShipDesign[]
for length in lengths
    push!(designs, ShipDesign(:vlsfo, length), ShipDesign(:methanol, length))
    for area in (400.0, 800.0, 1500.0)
        push!(designs, ShipDesign(:wing, length; wing_area=area))
    end
    for area in (100.0, 200.0, 400.0)
        push!(designs, ShipDesign(:kite, length; kite_area=area))
    end
end

results = Vector{Any}(nothing, length(designs))
Threads.@threads for i in eachindex(designs)
    ship = Ship(designs[i], assumptions)
    isnothing(ship) && continue
    results[i] = round_trip(ship, outbound, inbound, weather, departures, assumptions)
end

@printf("%-9s %6s %6s %6s | %8s %8s %8s %6s %6s %7s %7s\n", "kind", "L [m]", "wing",
    "kite", "USD/tkm", "MJ/tkm", "gCO2/tkm", "out d", "back d", "cargo t", "P kW")
for (design, result) in zip(designs, results)
    @printf("%-9s %6.0f %6.0f %6.0f | ", design.kind, design.length, design.wing_area,
        design.kite_area)
    if isnothing(result)
        println("infeasible")
        continue
    end
    @printf("%8.4f %8.4f %8.2f %6.1f %6.1f %7.0f %7.0f\n", result.cost_per_tonne_km,
        result.fuel_per_tonne_km, result.carbon_per_tonne_km, result.outbound_days,
        result.return_days, result.cargo, result.installed_power)
end
