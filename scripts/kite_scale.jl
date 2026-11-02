# Cost per tonne-km of VLSFO ships with and without a towing kite over ship length, against
# a Panamax-size VLSFO ship, on a subsample of the departures.
using Printf
include("setup.jl")

outbound, inbound = corridors(:caribbean, 8)

panamax_length = 225.0
lengths = [85.0, 110.0, 140.0, 170.0, 200.0]
kite_areas = [0.0, 400.0, 800.0, 1600.0, 3200.0]
sampled_departures = departures[1:6:end]

designs = [ShipDesign(:vlsfo, panamax_length)]
for length in lengths, area in kite_areas
    push!(designs, ShipDesign(:vlsfo, length; kite_area=area))
end

results = Vector{Any}(nothing, length(designs))
Threads.@threads for i in eachindex(designs)
    ship = Ship(designs[i], assumptions)
    isnothing(ship) && continue
    results[i] = round_trip(ship, outbound, inbound, weather, sampled_departures,
        assumptions)
end

"""
    baseline(designs, results, design)

Result of the design without a rig of the same drive and length as `design`.
"""
function baseline(designs, results, design)
    for (other, result) in zip(designs, results)
        other.drive == design.drive && other.length == design.length &&
            other.kite_area == 0 && return result
    end
end

println(length(sampled_departures),
    " departures; savings against the same ship without kite")
@printf("%6s %6s | %8s %7s %8s %7s %6s %6s %8s %7s %6s\n", "L [m]", "kite", "USD/tkm",
    "saved", "MJ/tkm", "saved", "out d", "back d", "cargo t", "P kW", "flown")
for (design, result) in zip(designs, results)
    @printf("%6.0f %6.0f | ", design.length, design.kite_area)
    if isnothing(result)
        println("infeasible")
        continue
    end
    reference = baseline(designs, results, design)
    @printf("%8.5f %6.1f%% %8.4f %6.1f%% %6.1f %6.1f %8.0f %7.0f %5.0f%%\n",
        result.cost_per_tonne_km,
        100(1 - result.cost_per_tonne_km / reference.cost_per_tonne_km),
        result.fuel_per_tonne_km,
        100(1 - result.fuel_per_tonne_km / reference.fuel_per_tonne_km),
        result.outbound_days, result.return_days, result.cargo, result.installed_power,
        100result.flight_share)
end
