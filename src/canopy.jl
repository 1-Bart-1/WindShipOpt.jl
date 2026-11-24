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
    force_rating(assumptions, force_per_area=assumptions[:kite_max_force_per_area])

Force limit `force_per_area` [kN/m^2] over the `canopy_cloth_reference_force` that the
canopy's cloth weight and mass overhead are stated at [-].
"""
force_rating(assumptions::Assumptions,
    force_per_area=assumptions[:kite_max_force_per_area]) =
    force_per_area / assumptions[:canopy_cloth_reference_force]

"""
    cloth_weight(assumptions, rating=force_rating(assumptions))

Weight [g/m^2] of the canopy cloth: `canopy_cloth_weight` times the force `rating`, so
that the cloth carries the same tension per weight at any force limit.
"""
cloth_weight(assumptions::Assumptions, rating=force_rating(assumptions)) =
    assumptions[:canopy_cloth_weight] * rating

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
[`sewing_cost`](@ref) and its own [`cloth_area_ratio`](@ref) of [`cloth_weight`](@ref) at
its [`cloth_price`](@ref).
"""
canopy_cost(assumptions::Assumptions, chord) = sewing_cost(assumptions) +
    cloth_area_ratio(assumptions, chord) * cloth_price(assumptions, cloth_weight(assumptions))

"""
    sewing_cost(assumptions)

Cost [USD/m^2] per projected m^2 of a soft kite besides its cloth: the surveyed
`canopy_structure_cost` less the cloth of a ram-air kite of `canopy_structure_chord` in
`canopy_cloth_weight`.
"""
function sewing_cost(assumptions::Assumptions)
    surveyed = assumptions[:usd_per_eur] * SURVEY_FLAT_AREA_RATIO *
               assumptions[:canopy_structure_cost]
    return surveyed -
           cloth_area_ratio(assumptions, assumptions[:canopy_structure_chord]) *
           cloth_price(assumptions, assumptions[:canopy_cloth_weight])
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

"""
    TubeFrame

The inflated leading-edge tube and struts that hold the shape of a leading-edge inflatable
kite, whose canopy is a single skin.
"""
struct TubeFrame end

"""
    tube_mass(assumptions, area)

Mass [kg/m^2] per projected m^2 of the tubes of a leading-edge inflatable kite of projected
`area` [m^2]: those of the reference kite, grown with the square root of the area and in
proportion to the force limit per area, as a kite of one shape needs a pressure in
proportion to its force per area and a tube wall in proportion to pressure times diameter.
"""
tube_mass(assumptions::Assumptions, area) = assumptions[:lei_tube_mass] *
    sqrt(area / assumptions[:lei_reference_area]) *
    assumptions[:lei_max_force_per_area] / assumptions[:lei_reference_force_per_area]

"""
    Canopy(assumptions, area, ::TubeFrame)

[`Canopy`](@ref) of a leading-edge inflatable kite of projected `area` [m^2]: one skin of
[`cloth_weight`](@ref) for its force limit with the mass overhead of a ram-air canopy, and
its [`tube_mass`](@ref) spread over `lei_tube_surface`, at the [`sewing_cost`](@ref) of a
soft kite and the [`cloth_price`](@ref) of each.
"""
function Canopy(assumptions::Assumptions, area, ::TubeFrame)
    rating = force_rating(assumptions, assumptions[:lei_max_force_per_area])
    skin, skin_weight = assumptions[:lei_flat_area_ratio], cloth_weight(assumptions, rating)
    tubes, surface = tube_mass(assumptions, area), assumptions[:lei_tube_surface]
    mass = 1e-3skin * skin_weight + assumptions[:canopy_mass_overhead] * rating + tubes
    return Canopy(mass,
        sewing_cost(assumptions) + skin * cloth_price(assumptions, skin_weight) +
        surface * cloth_price(assumptions, 1e3tubes / surface))
end
