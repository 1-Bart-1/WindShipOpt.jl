# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""
    Canopy

Mass and price of a ram-air canopy sewn from polyester ripstop of one cloth weight, per
m^2 of projected kite area.
"""
struct Canopy{C <: Real}
    "canopy mass per projected area [kg/m^2]"
    mass_per_area::Float64
    "manufacturing cost per projected area [USD/m^2]"
    cost_per_area::C
end

"""
    force_rating(assumptions)

Force limit `kite_max_force_per_area` over the `canopy_cloth_reference_force` that the
canopy's cloth weight and mass overhead are stated at [-].
"""
force_rating(assumptions::Assumptions) =
    assumptions[:kite_max_force_per_area] / assumptions[:canopy_cloth_reference_force]

"""
    cloth_weight(assumptions)

Weight [g/m^2] of the canopy cloth: `canopy_cloth_weight` times the
[`force_rating`](@ref), so that the cloth carries the same tension per weight at any force
limit.
"""
cloth_weight(assumptions::Assumptions) =
    assumptions[:canopy_cloth_weight] * force_rating(assumptions)

"""
    cloth_area_ratio(assumptions, chord)

Cloth [m^2] per m^2 of projected area of a ram-air canopy of mean projected `chord` [m]: on
each flat m^2 two skins, and ribs and diagonals in proportion to the chord over
`canopy_cell_width`.
"""
cloth_area_ratio(assumptions::Assumptions, chord) = assumptions[:canopy_flat_area_ratio] *
    (assumptions[:canopy_skin_cloth_ratio] +
     assumptions[:canopy_rib_cloth_ratio] * chord / assumptions[:canopy_cell_width])

"flat over projected area at which `canopy_structure_cost` is stated"
const SURVEY_FLAT_AREA_RATIO = 25 / 18

"""
    cloth_price(assumptions, weight)

Price [USD] of a sewn m^2 of cloth of `weight` [g/m^2], offcuts included.
"""
cloth_price(assumptions::Assumptions, weight) = assumptions[:canopy_cloth_base_price] +
    assumptions[:canopy_cloth_price_per_weight] * weight

"""
    canopy_cost(assumptions, chord)

Cost [USD/m^2] per projected m^2 of the canopy of mean projected `chord` [m]: the surveyed
`canopy_structure_cost` of a kite of `canopy_structure_chord`, its cloth of
`canopy_cloth_weight` replaced by the canopy's own [`cloth_area_ratio`](@ref) of
[`cloth_weight`](@ref) at its [`cloth_price`](@ref).
"""
function canopy_cost(assumptions::Assumptions, chord)
    surveyed = assumptions[:usd_per_eur] * SURVEY_FLAT_AREA_RATIO *
               assumptions[:canopy_structure_cost]
    surveyed_cloth = cloth_area_ratio(assumptions, assumptions[:canopy_structure_chord]) *
                     cloth_price(assumptions, assumptions[:canopy_cloth_weight])
    return surveyed - surveyed_cloth +
           cloth_area_ratio(assumptions, chord) *
           cloth_price(assumptions, cloth_weight(assumptions))
end

"""
    Canopy(assumptions, area, aspect_ratio)

[`Canopy`](@ref) of a kite of projected `area` [m^2] and projected `aspect_ratio`, sewn from
[`cloth_weight`](@ref) in its [`cloth_area_ratio`](@ref) at its mean chord: its cloth plus
the mass overhead of seams, tapes and reinforcements in proportion to the force limit, at
its [`canopy_cost`](@ref).
"""
function Canopy(assumptions::Assumptions, area, aspect_ratio)
    chord = sqrt(area / aspect_ratio)
    return Canopy(1e-3cloth_area_ratio(assumptions, chord) * cloth_weight(assumptions) +
                  assumptions[:canopy_mass_overhead] * force_rating(assumptions),
        canopy_cost(assumptions, chord))
end
