# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""
    Canopy

Mass, price and life of a ram-air canopy sewn from polyester ripstop of one cloth
weight, per m^2 of projected kite area.
"""
struct Canopy{C <: Real, L <: Real}
    "canopy mass per projected area [kg/m^2]"
    mass_per_area::Float64
    "manufacturing cost per projected area [USD/m^2]"
    cost_per_area::C
    "flight hours before replacement [h]"
    lifetime::L
end

"""
    force_rating(assumptions)

Force limit `kite_max_force_per_area` over the `canopy_cloth_reference_force` that the
canopy goals are stated at [-].
"""
force_rating(assumptions::Assumptions) =
    assumptions[:kite_max_force_per_area] / assumptions[:canopy_cloth_reference_force]

"cloth weight [g/m^2] that `canopy_uv_reference_dose` and `canopy_wear_rate` are stated at"
const decay_reference_weight = 100.0

"""
    decay_life(assumptions, weight, force_per_area)

Flight hours [h] until cloth of `weight` [g/m^2] loses to UV and wear the strength above
`canopy_strength_kept` times its skin tension at the force limit `force_per_area`
[kN/m^2].
"""
function decay_life(assumptions::Assumptions, weight, force_per_area)
    relative_weight = weight / decay_reference_weight
    tension = 1e3force_per_area * assumptions[:canopy_skin_radius]
    margin = assumptions[:canopy_cloth_specific_strength] * weight /
             (assumptions[:canopy_strength_kept] * tension)
    uv_life = assumptions[:canopy_uv_reference_dose] / assumptions[:canopy_uv_dose_rate] *
              relative_weight^assumptions[:canopy_uv_weight_exponent]
    wear_life = decay_reference_weight / assumptions[:canopy_wear_rate] *
                relative_weight^assumptions[:canopy_wear_weight_exponent]
    return log(margin) / (1 / uv_life + 1 / wear_life)
end

"""
    canopy_lifetime(assumptions)

Flight hours [h] of a canopy of `canopy_cloth_weight` built for `kite_max_force_per_area`:
the goal `canopy_life`, stated at `canopy_cloth_reference_weight` and
`canopy_cloth_reference_force`, scaled by [`decay_life`](@ref).
"""
canopy_lifetime(assumptions::Assumptions) = assumptions[:canopy_life] *
    decay_life(assumptions, assumptions[:canopy_cloth_weight],
        assumptions[:kite_max_force_per_area]) /
    decay_life(assumptions, assumptions[:canopy_cloth_reference_weight],
        assumptions[:canopy_cloth_reference_force])

"""
    sewn_cloth_price(assumptions, weight)

Price [USD] of one square metre of canopy cloth of `weight` [g/m^2], as sewn into a canopy.
"""
sewn_cloth_price(assumptions::Assumptions, weight) = assumptions[:canopy_cloth_base_price] +
    assumptions[:canopy_cloth_price_per_weight] * weight

"""
    Canopy(assumptions)

[`Canopy`](@ref) of `canopy_cloth_weight`, cloth plus an overhead for mass and cost, with
the mass overhead of seams, tapes and reinforcements in proportion to the force limit,
lasting [`canopy_lifetime`](@ref).
"""
function Canopy(assumptions::Assumptions)
    weight = assumptions[:canopy_cloth_weight]
    cloth_area = assumptions[:canopy_cloth_area_ratio]
    return Canopy(1e-3cloth_area * weight +
                  assumptions[:canopy_mass_overhead] * force_rating(assumptions),
        assumptions[:canopy_making_cost_per_area] +
        cloth_area * sewn_cloth_price(assumptions, weight),
        canopy_lifetime(assumptions))
end
