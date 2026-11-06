"""
    Canopy

Mass, price and life of a ram-air canopy sewn from polyester ripstop of one cloth
weight, per m^2 of projected kite area.
"""
struct Canopy
    "canopy mass per projected area [kg/m^2]"
    mass_per_area::Float64
    "manufacturing cost per projected area [USD/m^2]"
    cost_per_area::Float64
    "flight hours before replacement [h]"
    lifetime::Float64
end

"""
    Canopy(assumptions)

[`Canopy`](@ref) of cloth weight `canopy_cloth_weight`, cloth plus a fixed overhead for mass
and cost, lasting the goal `canopy_life`.
"""
function Canopy(assumptions::Assumptions)
    weight = assumptions[:canopy_cloth_weight]
    cloth_area = assumptions[:canopy_cloth_area_ratio]
    cloth_price = assumptions[:canopy_cloth_base_price] +
                  assumptions[:canopy_cloth_price_per_weight] * weight
    return Canopy(1e-3cloth_area * weight + assumptions[:canopy_mass_overhead],
        assumptions[:canopy_making_cost_per_area] + cloth_area * cloth_price,
        assumptions[:canopy_life])
end
