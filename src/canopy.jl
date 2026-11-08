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
    cloth_weight(assumptions)

Cloth weight [g/m^2] of a canopy built for the force limit: `canopy_cloth_weight` times the
[`force_rating`](@ref) to the power `canopy_cloth_force_exponent`.
"""
cloth_weight(assumptions::Assumptions) = assumptions[:canopy_cloth_weight] *
    force_rating(assumptions)^assumptions[:canopy_cloth_force_exponent]

"""
    sewn_cloth_price(assumptions, weight)

Price [USD] of one square metre of canopy cloth of `weight` [g/m^2], as sewn into a canopy.
"""
sewn_cloth_price(assumptions::Assumptions, weight) = assumptions[:canopy_cloth_base_price] +
    assumptions[:canopy_cloth_price_per_weight] * weight

"""
    Canopy(assumptions)

[`Canopy`](@ref) of [`cloth_weight`](@ref), cloth plus an overhead for mass and cost, with
the mass overhead of seams, tapes and reinforcements in proportion to the force limit,
lasting the goal `canopy_life`.
"""
function Canopy(assumptions::Assumptions)
    weight = cloth_weight(assumptions)
    cloth_area = assumptions[:canopy_cloth_area_ratio]
    return Canopy(1e-3cloth_area * weight +
                  assumptions[:canopy_mass_overhead] * force_rating(assumptions),
        assumptions[:canopy_making_cost_per_area] +
        cloth_area * sewn_cloth_price(assumptions, weight),
        assumptions[:canopy_life])
end
