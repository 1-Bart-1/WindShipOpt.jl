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
    "life if sunlight alone aged the cloth [h]"
    uv_lifetime::Float64
    "life if flexing, flutter, chafe and seam wear alone aged the cloth [h]"
    wear_lifetime::Float64
end

"cloth weight at which the UV dose per weight and the wear rate hold [g/m^2]"
const CLOTH_REFERENCE_WEIGHT = 100.0

"""
    Canopy(assumptions)

[`Canopy`](@ref) of cloth weight `canopy_cloth_weight`: cloth plus a fixed overhead for
mass and cost. Its life combines, as rates, a UV life and a wear life. In each the strength
decays exponentially, at a rate falling with the cloth weight to a power of its own, until
it reaches the strength factor times the skin tension at the force limit, or the
retirement share of the new strength where that is higher. A nonzero
`canopy_wear_lifetime` replaces the wear life by that fixed span.
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
    retirement = assumptions[:canopy_retirement_strength]
    strength_loss = log(retirement > 0 ? min(margin, 1 / retirement) : margin)
    life_factor = assumptions[:canopy_life_factor]
    decay_life(rate, exponent) = life_factor * CLOTH_REFERENCE_WEIGHT *
                                 (weight / CLOTH_REFERENCE_WEIGHT)^exponent *
                                 strength_loss / rate
    uv_lifetime = decay_life(
        assumptions[:canopy_uv_dose_rate] / assumptions[:cloth_uv_dose_per_weight],
        assumptions[:canopy_uv_weight_exponent])
    fixed_lifetime = assumptions[:canopy_wear_lifetime]
    wear_lifetime = fixed_lifetime > 0 ? life_factor * fixed_lifetime :
                    decay_life(assumptions[:canopy_wear_rate],
        assumptions[:canopy_wear_weight_exponent])
    lifetime = 1 / (1 / uv_lifetime + 1 / wear_lifetime)
    return Canopy(1e-3cloth_area * weight + assumptions[:canopy_mass_overhead],
        assumptions[:canopy_making_cost_per_area] + cloth_area * cloth_price, lifetime,
        uv_lifetime, wear_lifetime)
end
