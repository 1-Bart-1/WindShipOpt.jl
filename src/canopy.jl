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
    billow_radius(chord, assumptions)

Area-averaged radius [m] the skin billows to between the ribs of a kite of mean `chord` [m].
"""
billow_radius(chord, assumptions) = assumptions[:canopy_billow_ratio] * chord

"""
    strength_margin(weight, chord, assumptions)

New strength of cloth of `weight` [g/m^2] over the strength the force limit needs on a kite
of mean `chord` [m] [-].
"""
function strength_margin(weight, chord, assumptions)
    tension = 1e3assumptions[:kite_max_force_per_area] * billow_radius(chord, assumptions)
    return assumptions[:cloth_specific_strength] * weight /
           (assumptions[:canopy_strength_factor] * tension)
end

"""
    strength_loss(margin, retirement)

Logarithm of the strength a canopy may lose: down to the force limit `margin` below new,
or to the share `retirement` of new strength where that is higher; 0 retires on no share.
"""
strength_loss(margin, retirement) =
    log(retirement > 0 ? min(margin, 1 / retirement) : margin)

"""
    decay_life(weight, exponent, loss, rate)

Hours for cloth of `weight` [g/m^2] to lose the strength `loss`, at `rate` [g/m^2/h] at the
reference weight, the life growing with weight to the power `exponent`.
"""
decay_life(weight, exponent, loss, rate) =
    CLOTH_REFERENCE_WEIGHT * (weight / CLOTH_REFERENCE_WEIGHT)^exponent * loss / rate

"""
    Canopy(assumptions, chord)

[`Canopy`](@ref) of cloth weight `canopy_cloth_weight` on a kite of mean `chord` [m]: cloth plus a fixed overhead for
mass and cost. Its life combines, as rates, a UV life and a wear life, each a
[`decay_life`](@ref) to the [`strength_loss`](@ref). A retirement share rescales the wear
rate so that the wear life at the reference weight stays as observed; a nonzero
`canopy_wear_lifetime` replaces the wear life by that fixed span.
"""
function Canopy(assumptions::Assumptions, chord)
    weight = assumptions[:canopy_cloth_weight]
    cloth_area = assumptions[:canopy_cloth_area_ratio]
    cloth_price = assumptions[:canopy_cloth_base_price] +
                  assumptions[:canopy_cloth_price_per_weight] * weight
    margin = strength_margin(weight, chord, assumptions)
    margin > 1 || error("cloth of $weight g/m^2 is too weak for a $chord m chord")
    retirement = assumptions[:canopy_retirement_strength]
    loss = strength_loss(margin, retirement)
    life_factor = assumptions[:canopy_life_factor]
    uv_lifetime = life_factor * decay_life(weight, assumptions[:canopy_uv_weight_exponent],
        loss, assumptions[:canopy_uv_dose_rate] / assumptions[:cloth_uv_dose_per_weight])
    reference_margin = strength_margin(CLOTH_REFERENCE_WEIGHT, chord, assumptions)
    wear_rate = assumptions[:canopy_wear_rate] *
                strength_loss(reference_margin, retirement) / log(reference_margin)
    fixed_lifetime = assumptions[:canopy_wear_lifetime]
    wear_lifetime = life_factor * (fixed_lifetime > 0 ? fixed_lifetime :
                     decay_life(weight, assumptions[:canopy_wear_weight_exponent], loss,
                        wear_rate))
    lifetime = 1 / (1 / uv_lifetime + 1 / wear_lifetime)
    return Canopy(1e-3cloth_area * weight + assumptions[:canopy_mass_overhead],
        assumptions[:canopy_making_cost_per_area] + cloth_area * cloth_price, lifetime,
        uv_lifetime, wear_lifetime)
end
