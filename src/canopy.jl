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
canopy cloth weight and seams are stated at [-].
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
`aspect_ratio` per m^2 of projected area: the [`cell_cloth_ratio`](@ref) of the
[`chord_over_cell_width`](@ref) at its mean chord.
"""
cloth_area_ratio(assumptions::Assumptions, area, aspect_ratio) = cell_cloth_ratio(
    assumptions, chord_over_cell_width(assumptions, sqrt(area / aspect_ratio)))

"""
    cell_cloth_ratio(assumptions, cells)

Cloth [m^2] per m^2 of projected area of a ram-air canopy of `cells` chord over cell width:
on each flat m^2 two skins, and ribs and diagonals in proportion to `cells`.
"""
cell_cloth_ratio(assumptions::Assumptions, cells) = assumptions[:canopy_flat_area_ratio] *
    (assumptions[:canopy_skin_cloth_ratio] + assumptions[:canopy_rib_cloth_ratio] * cells)

"flat over projected area at which `canopy_structure_cost` is stated"
const SURVEY_FLAT_AREA_RATIO = 25 / 18

"""
    cloth_price(assumptions, weight)

Price [USD] of a sewn m^2 of cloth of `weight` [g/m^2], offcuts included.
"""
cloth_price(assumptions::Assumptions, weight) = assumptions[:canopy_cloth_base_price] +
    assumptions[:canopy_cloth_price_per_weight] * weight

"""
    seam_length(assumptions, chord, cells)

Seam [m] per m^2 of chord times span of a ram-air canopy of mean `chord` [m] and `cells`
chord over cell width: `canopy_cell_seams` along the chord per cell, the skins' panel seams
where a cell is wider than `canopy_cloth_width`, and the leading and trailing edges.
"""
function seam_length(assumptions::Assumptions, chord, cells)
    per_cell_width = cells / chord
    panels = 2 * max(0, 1 / assumptions[:canopy_cloth_width] - per_cell_width)
    return assumptions[:canopy_cell_seams] * per_cell_width + panels + 2 / chord
end

"""
    seam_area_ratio(assumptions, area, aspect_ratio)

Seam [m] per m^2 of chord times span of a ram-air canopy of projected `area` [m^2] and
projected `aspect_ratio`: the [`seam_length`](@ref) at its mean chord and
[`chord_over_cell_width`](@ref).
"""
function seam_area_ratio(assumptions::Assumptions, area, aspect_ratio)
    chord = sqrt(area / aspect_ratio)
    return seam_length(assumptions, chord, chord_over_cell_width(assumptions, chord))
end

"""
    canopy_cost(assumptions, area, aspect_ratio)

Cost [USD/m^2] per projected m^2 of the canopy of [`cloth_weight`](@ref) of a kite of
projected `area` [m^2] and projected `aspect_ratio`: the surveyed `canopy_structure_cost`
and `canopy_bridle_cost` of a kite of `canopy_structure_chord` at `canopy_chord_cells`, its
cloth of `canopy_structure_cloth_weight` replaced by the kite's own
[`cloth_area_ratio`](@ref) at its [`cloth_price`](@ref) and the rest, the sewing, grown with
the kite's [`seam_area_ratio`](@ref), or by `canopy_sewing_cloth_share` with its cloth.
"""
function canopy_cost(assumptions::Assumptions, area, aspect_ratio)
    surveyed_cells = assumptions[:canopy_chord_cells]
    cloth = cloth_area_ratio(assumptions, area, aspect_ratio)
    surveyed_cloth = cell_cloth_ratio(assumptions, surveyed_cells)
    seam = seam_area_ratio(assumptions, area, aspect_ratio)
    surveyed_seam = seam_length(assumptions, assumptions[:canopy_structure_chord],
        surveyed_cells)
    share = assumptions[:canopy_sewing_cloth_share]
    per_flat_area = assumptions[:usd_per_eur] * SURVEY_FLAT_AREA_RATIO
    sewing = per_flat_area * assumptions[:canopy_structure_cost] -
             surveyed_cloth * cloth_price(assumptions,
                 assumptions[:canopy_structure_cloth_weight])
    growth = (1 - share) * seam / surveyed_seam + share * cloth / surveyed_cloth
    return sewing * growth + per_flat_area * assumptions[:canopy_bridle_cost] +
           cloth * cloth_price(assumptions, cloth_weight(assumptions))
end

"""
    Canopy(assumptions, area, aspect_ratio)

[`Canopy`](@ref) of a kite of projected `area` [m^2] and projected `aspect_ratio`, sewn from
[`cloth_weight`](@ref) in its [`cloth_area_ratio`](@ref): its cloth plus the mass overhead
of seams, tapes and reinforcements in proportion to the force limit, at its
[`canopy_cost`](@ref).
"""
function Canopy(assumptions::Assumptions, area, aspect_ratio)
    cloth_area = cloth_area_ratio(assumptions, area, aspect_ratio)
    return Canopy(1e-3cloth_area * cloth_weight(assumptions) +
                  assumptions[:canopy_mass_overhead] * force_rating(assumptions),
        canopy_cost(assumptions, area, aspect_ratio))
end
