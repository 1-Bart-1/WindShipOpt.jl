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

"""
    decay_life(assumptions, weight, force_per_area)

Flight hours [h] until cloth of `weight` [g/m^2] loses to UV and wear the strength above
`canopy_strength_kept` times its skin tension at the force limit `force_per_area`
[kN/m^2].
"""
function decay_life(assumptions::Assumptions, weight, force_per_area)
    reference_weight = assumptions[:canopy_decay_reference_weight]
    relative_weight = weight / reference_weight
    tension = 1e3force_per_area * assumptions[:canopy_skin_radius]
    margin = assumptions[:canopy_cloth_specific_strength] * weight /
             (assumptions[:canopy_strength_kept] * tension)
    uv_life = assumptions[:canopy_uv_reference_dose] / assumptions[:canopy_uv_dose_rate] *
              relative_weight^assumptions[:canopy_uv_weight_exponent]
    wear_life = reference_weight / assumptions[:canopy_wear_rate] *
                relative_weight^assumptions[:canopy_wear_weight_exponent]
    return log(margin) / (1 / uv_life + 1 / wear_life)
end

"""
    reference_decay_life(assumptions)

[`decay_life`](@ref) [h] of the canopy the goal `canopy_life` is stated for, cloth of
`canopy_cloth_reference_weight` at `canopy_cloth_reference_force`.
"""
reference_decay_life(assumptions::Assumptions) =
    decay_life(assumptions, assumptions[:canopy_cloth_reference_weight],
        assumptions[:canopy_cloth_reference_force])

"""
    canopy_lifetime(assumptions)

Flight hours [h] of a canopy of `canopy_cloth_weight` built for `kite_max_force_per_area`:
the goal `canopy_life` scaled by [`decay_life`](@ref) over [`reference_decay_life`](@ref).
"""
canopy_lifetime(assumptions::Assumptions) = assumptions[:canopy_life] *
    decay_life(assumptions, assumptions[:canopy_cloth_weight],
        assumptions[:kite_max_force_per_area]) / reference_decay_life(assumptions)

"""
    chord_over_cell_width(assumptions, chord)

Chord over cell width [-] of a ram-air canopy of mean `chord` [m]: `canopy_chord_cells` at
`canopy_reference_chord`, the cell width growing with the chord to the power
`canopy_cell_width_exponent`.
"""
chord_over_cell_width(assumptions::Assumptions, chord) = assumptions[:canopy_chord_cells] *
    (chord / assumptions[:canopy_reference_chord])^
    (1 - assumptions[:canopy_cell_width_exponent])

"""
    cloth_area_ratio(assumptions, area, aspect_ratio)

Cloth [m^2] sewn into a ram-air canopy of projected `area` [m^2] and projected
`aspect_ratio` per m^2 of projected area: on each flat m^2 two skins, and ribs and diagonals
in proportion to the [`chord_over_cell_width`](@ref) at its mean chord.
"""
function cloth_area_ratio(assumptions::Assumptions, area, aspect_ratio)
    cells = chord_over_cell_width(assumptions, sqrt(area / aspect_ratio))
    return assumptions[:canopy_flat_area_ratio] * (assumptions[:canopy_skin_cloth_ratio] +
            assumptions[:canopy_rib_cloth_ratio] * cells)
end

"flat over projected area at which `canopy_structure_cost` is stated"
const SURVEY_FLAT_AREA_RATIO = 25 / 18

"""
    canopy_cost(assumptions, area, aspect_ratio)

Cost [USD/m^2] per projected m^2 of the canopy of `canopy_cloth_weight` of a kite of
projected `area` [m^2] and projected `aspect_ratio`: the surveyed `canopy_structure_cost`
plus the cloth of its [`cloth_area_ratio`](@ref) priced from `canopy_structure_cloth_weight`
up to its own weight.
"""
function canopy_cost(assumptions::Assumptions, area, aspect_ratio)
    surveyed = assumptions[:usd_per_eur] * SURVEY_FLAT_AREA_RATIO *
               assumptions[:canopy_structure_cost]
    heavier = assumptions[:canopy_cloth_weight] -
              assumptions[:canopy_structure_cloth_weight]
    cloth = cloth_area_ratio(assumptions, area, aspect_ratio) *
            assumptions[:canopy_cloth_price_per_weight] * heavier
    return surveyed + cloth
end

"""
    Canopy(assumptions, area, aspect_ratio)

[`Canopy`](@ref) of a kite of projected `area` [m^2] and projected `aspect_ratio`, sewn from
`canopy_cloth_weight` in its [`cloth_area_ratio`](@ref): its cloth plus the mass overhead of
seams, tapes and reinforcements in proportion to the force limit, at its
[`canopy_cost`](@ref), lasting [`canopy_lifetime`](@ref).
"""
function Canopy(assumptions::Assumptions, area, aspect_ratio)
    weight = assumptions[:canopy_cloth_weight]
    cloth_area = cloth_area_ratio(assumptions, area, aspect_ratio)
    return Canopy(1e-3cloth_area * weight +
                  assumptions[:canopy_mass_overhead] * force_rating(assumptions),
        canopy_cost(assumptions, area, aspect_ratio), canopy_lifetime(assumptions))
end
