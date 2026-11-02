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

[`Canopy`](@ref) of cloth weight `canopy_cloth_weight`: cloth plus a fixed overhead for
mass and cost. Its life combines, as rates, the wear life without sunlight and the UV
life, the dose over which the strength, decaying as exp(-D/D0) with D0 in proportion to
the cloth weight, falls to the strength factor times the skin tension at the force limit.
"""
function Canopy(assumptions::Assumptions)
    weight = assumptions[:canopy_cloth_weight]
    cloth_area = assumptions[:canopy_cloth_area_ratio]
    cloth_price = assumptions[:canopy_cloth_base_price] +
                  assumptions[:canopy_cloth_price_per_weight] * weight
    tension = 1e3assumptions[:kite_max_force_per_area] * assumptions[:canopy_panel_radius]
    margin = assumptions[:cloth_specific_strength] * weight /
             (assumptions[:canopy_strength_factor] * tension)
    margin > 1 || error("canopy cloth of $weight g/m^2 is too weak for the force limit")
    uv_lifetime = assumptions[:cloth_uv_dose_per_weight] * weight * log(margin) /
                  assumptions[:canopy_uv_dose_rate]
    lifetime = 1 / (1 / uv_lifetime + 1 / assumptions[:canopy_wear_lifetime])
    return Canopy(1e-3cloth_area * weight + assumptions[:canopy_mass_overhead],
        assumptions[:canopy_making_cost_per_area] + cloth_area * cloth_price, lifetime)
end
