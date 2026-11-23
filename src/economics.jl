# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

capital_recovery(rate, years) = rate / (1 - (1 + rate)^-years)

"""
    CargoUnit

Unit a ship's cargo capacity is counted in, from the assumptions: `:teu`, `:ceu`, or
`:tonne` for a ship that fills its deadweight. A TEU slot carries the mean box, loaded or
empty.
"""
struct CargoUnit
    "cargo in one occupied unit [t]"
    cargo::Float64
    "deadweight one occupied unit takes, cargo and container tare [t]"
    mass::Float64
    "hold or deck space of one unit [m^3]"
    volume::Float64
end

CargoUnit(name::Symbol, assumptions::Assumptions) = CargoUnit(Val(name), assumptions)
CargoUnit(::Val{:tonne}, assumptions) = CargoUnit(1.0, 1.0, Inf)
function CargoUnit(::Val{:teu}, assumptions)
    cargo = (1 - assumptions[:empty_container_share]) * assumptions[:cargo_per_teu]
    return CargoUnit(cargo, cargo + assumptions[:teu_tare_mass], assumptions[:teu_volume])
end
CargoUnit(::Val{:ceu}, assumptions) = CargoUnit(assumptions[:cargo_per_ceu],
    assumptions[:cargo_per_ceu], assumptions[:ceu_volume])

"""
    CargoHold

What a ship can load beside its rig and stores: the deadweight left and the cargo units
left, whichever limit binds.
"""
struct CargoHold
    "deadweight at the scantling draught [t]"
    deadweight::Float64
    "deadweight left after the rig and the stores [t]"
    payload::Float64
    "cargo units left beside the rig"
    slots::Float64
    unit::CargoUnit
end

"""
    unit_limits(hold, store_mass=0, store_volume=0)

Cargo units `hold` takes with a fuel store of `store_mass` [t] and `store_volume` [m^3]:
by the deadweight left and by the units left, as a named tuple `(deadweight, space)`.
"""
unit_limits(hold::CargoHold, store_mass=0.0, store_volume=0.0) =
    (deadweight=(hold.payload - store_mass) / hold.unit.mass,
        space=hold.slots - store_volume / hold.unit.volume)

"""
    cargo_mass(hold, store_mass=0, store_volume=0)

Cargo [t] that `hold` carries with a fuel store of `store_mass` [t] and `store_volume`
[m^3] taken from it: the deadweight or the units left, whichever is less.
"""
cargo_mass(hold::CargoHold, store_mass=0.0, store_volume=0.0) =
    minimum(unit_limits(hold, store_mass, store_volume)) * hold.unit.cargo

"""
    cargo_limit(hold)

`:deadweight` where `hold` fills its deadweight before its units, `:space` otherwise.
"""
function cargo_limit(hold::CargoHold)
    (; deadweight, space) = unit_limits(hold)
    return deadweight <= space ? :deadweight : :space
end

"""
    cargo_limit(class, assumptions)

The limit `class` fills first without a rig or fuel store, as `cargo_limit(hold)`.
"""
cargo_limit(class::ShipClass, assumptions::Assumptions) =
    cargo_limit(CargoHold(Ship(ShipDesign(:vlsfo, class), assumptions), assumptions))

"""
    CargoHold(ship, assumptions)

Hold of `ship`: its class's deadweight less the rig mass and the stores, and its class's
unit capacity less the [`blocked_slots`](@ref) of its rig; the reference coaster family
fills its deadweight.
"""
function CargoHold(ship::Ship, assumptions::Assumptions)
    (; class) = ship.design
    rig_mass = rig_costs(ship.rig, assumptions)[2]
    if isnothing(class)
        deadweight = (1 - assumptions[:lightship_fraction]) *
                     displacement_mass(ship.hull, ship.env) / 1e3
        unit, slots = CargoUnit(:tonne, assumptions), Inf
    else
        deadweight = class.deadweight
        unit = CargoUnit(class.cargo_unit, assumptions)
        slots = class.unit_capacity - blocked_slots(ship.rig, class, assumptions)
    end
    payload = deadweight - rig_mass - assumptions[:stores_mass]
    return CargoHold(deadweight, payload, slots, unit)
end

"""
    ShipCosts

Capital, fixed annual cost and cargo hold of a ship, excluding fuel and its store.
"""
struct ShipCosts{T <: Real}
    "capital cost [USD]"
    capital::T
    "annuity, crew and maintenance [USD/year]"
    fixed_annual::T
    hold::CargoHold
    "value of the cargo [USD/t]"
    cargo_value::T
end

ShipCosts(capital, fixed_annual, hold, cargo_value) = ShipCosts{promote_type(
    typeof(capital), typeof(fixed_annual), typeof(cargo_value))}(capital, fixed_annual,
    hold, cargo_value)

"""
    ShipCosts(ship, assumptions; retractable=true)

Costs of `ship`; its [`standing_rig`](@ref) pays the retractable rig premium unless
`retractable` is false.
"""
function ShipCosts(ship::Ship, assumptions::Assumptions; retractable=true)
    rate = assumptions[:discount_rate]
    (; class) = ship.design
    hold = CargoHold(ship, assumptions)
    size = hold.deadweight / assumptions[:newbuild_reference_deadweight]
    hull = isnothing(class) ?
           assumptions[:newbuild_price] * size^assumptions[:newbuild_price_exponent] :
           class.newbuild_price
    drive_premium = (Drive(ship.design.drive, assumptions).power_cost -
                     assumptions[:mechanical_propulsion_cost]) *
                    ship.powertrain.installed_power / 1e3
    annuity = capital_recovery(rate, assumptions[:hull_lifetime]) * (hull + drive_premium)
    rig_capital, _, rig_annual = rig_costs(ship.rig, assumptions)
    if retractable
        standing_capital, _, standing_annual = rig_costs(standing_rig(ship.rig),
            assumptions)
        rig_capital += assumptions[:retractable_rig_premium] * standing_capital
        rig_annual += assumptions[:retractable_rig_premium] * standing_annual
    end
    capital = hull + drive_premium + rig_capital
    crew = assumptions[:crew_cost] * size^assumptions[:crew_cost_exponent]
    fixed_annual = annuity + rig_annual + crew +
                   assumptions[:maintenance_fraction] * (hull + drive_premium) +
                   rig_maintenance(ship.rig, rig_capital, assumptions)
    cargo_value = isnothing(class) ? assumptions[:cargo_value] : class.cargo_value
    return ShipCosts(capital, fixed_annual, hold, cargo_value)
end

"""
    ship_costs(ship, assumptions)

[`ShipCosts`](@ref) of `ship` with its wings or rotors retractable and fixed.
"""
ship_costs(ship::Ship, assumptions::Assumptions) =
    (ShipCosts(ship, assumptions), ShipCosts(ship, assumptions; retractable=false))

"""
    layout_score(ship, rig, assumptions)

Yearly cost [USD/year] of the wings, rotors or suction sails of `rig` on `ship` over the
mean power [W] they save: their annuity and maintenance, with the retractable rig premium
where a fixed rig would cost the ship port time, and the [`lost_cargo_cost`](@ref), over
the mean of their thrust times the service speed less the power they draw, at the best trim
in the [`layout_winds`](@ref). Inf where they save none.
"""
function layout_score(ship::Ship, rig, assumptions::Assumptions)
    standing = standing_rig(rig)
    capital, _, annuity = rig_costs(standing, assumptions)
    fixed_delay = fixed_rig_port_hours(standing, ship.design.class, assumptions) > 0
    price_factor = 1 + fixed_delay * assumptions[:retractable_rig_premium]
    yearly = price_factor * annuity +
             rig_maintenance(standing, price_factor * capital, assumptions) +
             lost_cargo_cost(ship, standing, assumptions)
    speed = service_speed(ship, assumptions)
    winds = layout_winds(assumptions)
    saved = sum(winds) do (wind_10m, true_angle)
        _, force = best_trim(ship, standing, speed, wind_10m, true_angle)
        return force.thrust * speed - force.power
    end / length(winds)
    return saved > 0 ? yearly / saved : Inf
end

"""
    lost_cargo_cost(ship, rig, assumptions)

Yearly cost [USD/year] of the cargo that the class of `ship` no longer carries beside the
[`blocked_slots`](@ref) of `rig`: the fixed annual cost of its ship without a rig times the
share of its cargo they take, none where it fills its deadweight first.
"""
function lost_cargo_cost(ship::Ship, rig, assumptions::Assumptions)
    (; drive, class) = ship.design
    isnothing(class) && return 0.0
    blocked = blocked_slots(rig, class, assumptions)
    blocked > 0 || return 0.0
    costs = ShipCosts(Ship(ShipDesign(drive, class), assumptions), assumptions)
    (; deadweight, payload, slots, unit) = costs.hold
    left = cargo_mass(CargoHold(deadweight, payload, slots - blocked, unit))
    return costs.fixed_annual * (1 - left / cargo_mass(costs.hold))
end

"""
    layout_winds(assumptions)

True winds at 10 m [m/s] and their angles off the bow [rad] a layout is scored in: the
midpoints of four equal quarters of a Rayleigh distribution of mean `layout_mean_wind`, each
from six directions evenly spread from ahead to astern.
"""
function layout_winds(assumptions::Assumptions)
    scale = assumptions[:layout_mean_wind] / sqrt(π / 2)
    quarters = (0.125, 0.375, 0.625, 0.875)
    speeds = [scale * sqrt(-2log(1 - quantile)) for quantile in quarters]
    return [(speed, deg2rad(angle)) for speed in speeds for angle in 15:30:165]
end

"""
    cheapest_layout(ship, assumptions)

Rig of the design of `ship` in the layout of its [`layout_counts`](@ref) with the lowest
[`layout_score`](@ref) on `ship`, which carries no rig yet; for each count of columns more
units are tried until two in a row score worse than the fewest scored best. `nothing` where
no layout fits; the design's rig as it is where it has no wings, rotors or suction sails.
"""
function cheapest_layout(ship::Ship, assumptions::Assumptions)
    (; design, hull) = ship
    first(standing_unit(design)) > 0 || return design_rig(design, hull, assumptions)
    counts = layout_counts(design, hull, assumptions)
    best, lowest = nothing, Inf
    for columns in 1:2
        rig, score = cheapest_in_columns(ship, columns,
            [last(count) for count in counts if first(count) == columns], assumptions)
        score < lowest && ((best, lowest) = (rig, score))
    end
    return best
end

"""
    cheapest_in_columns(ship, columns, in_columns, assumptions)

Rig of the design of `ship` in `columns` columns of the count of `in_columns`, tried in
order, raised units on the [`cheapest_pedestal`](@ref), with the lowest
[`layout_score`](@ref), and that score; the search stops once two counts in a row fit and
score worse than the best.
"""
function cheapest_in_columns(ship::Ship, columns, in_columns, assumptions::Assumptions)
    best, lowest, worse = nothing, Inf, 0
    for in_column in in_columns
        rig = design_rig(ship.design, ship.hull, assumptions; columns, in_column)
        isnothing(rig) && continue
        rig, score = cheapest_pedestal(ship, rig, assumptions)
        if score < lowest || isnothing(best)
            best, lowest, worse = rig, score, 0
        else
            worse += 1
            worse == 2 && break
        end
    end
    return best, lowest
end

"""
    cheapest_pedestal(ship, rig, assumptions)

`rig` on whichever of a column, a frame or, where [`container_holds`](@ref), a container
gives its raised units the lower [`layout_score`](@ref) on `ship`, and that score; `rig` as
it is where it stands on deck.
"""
function cheapest_pedestal(ship::Ship, rig, assumptions::Assumptions)
    rig isa Union{WingRig, RotorRig} && raised(rig) ||
        return rig, layout_score(ship, rig, assumptions)
    supports = [with_pedestal(rig, pedestal) for pedestal in (:column, :frame, :container)
                if pedestal != :container || container_holds(rig, assumptions)]
    scores = [layout_score(ship, support, assumptions) for support in supports]
    return supports[argmin(scores)], minimum(scores)
end

"""
    fixed_rig_port_hours(rig, class, assumptions)

Mean extra time per port call [h] of a `rig` fixed on deck: the cargo-handling delay of
`class`, plus the lost calls of a ship whose air draft in ballast exceeds the class
limit. Inf where a fixed rig prevents cargo handling, as on the reference coaster when
`class` is `nothing` and for units raised above the stacks on a column or frame, which
stand in the cranes' way; zero for kites, ships without a rig and units in containers,
which are lifted like a box, and that of the [`standing_rig`](@ref) for a kite over a
standing rig.
"""
fixed_rig_port_hours(rig, class, assumptions) = 0.0
fixed_rig_port_hours(rig::CombinedRig, class, assumptions) =
    fixed_rig_port_hours(rig.standing, class, assumptions)
fixed_rig_port_hours(::Union{WingRig, RotorRig}, ::Nothing, assumptions) = Inf

function fixed_rig_port_hours(rig::Union{WingRig, RotorRig}, class::ShipClass,
        assumptions)
    raised(rig) && return rig.pedestal == :container ? 0.0 : Inf
    ballast_rise = (1 - assumptions[:ballast_draft_fraction]) * class.draft
    air_draft = rig.foot_height + rig.height + ballast_rise
    air_draft > class.air_draft_limit || return class.fixed_rig_port_hours
    return class.fixed_rig_port_hours + 24class.restricted_call_share *
                                         assumptions[:restricted_call_days]
end

"whether the units of `rig` stand on pedestals above the deck cargo"
raised(rig::Union{WingRig, RotorRig}) = rig.pedestal_height > 0

"units a rig stands on deck: wings, rotors, kites and their sum over a combined rig"
deck_units(rig::Union{WingRig, RotorRig}) = rig.count
deck_units(rig::KiteRig) = 1
deck_units(rig::CombinedRig) = deck_units(rig.kite) + deck_units(rig.standing)
deck_units(::Nothing) = 0

"""
    gross_tonnage(hull, assumptions)

Gross tonnage by the 1969 Tonnage Convention, K1 V, from the moulded hull volume up to
the depth; deckhouses are not counted.
"""
function gross_tonnage(hull::Hull, assumptions::Assumptions)
    volume = hull.displacement_volume * assumptions[:depth_draft_ratio]
    return (0.2 + 0.02log10(volume)) * volume
end

"""
    carbon_coverage(hull, route, assumptions)

Share of the emissions of a ship of `hull` on `route` that the carbon price is paid on:
the route's [`EU_ETS_SHARES`](@ref) from a gross tonnage of `ets_gross_tonnage` up, none
below it or where `route` is nothing.
"""
carbon_coverage(hull::Hull, ::Nothing, assumptions::Assumptions) = 0.0
carbon_coverage(hull::Hull, route::Symbol, assumptions::Assumptions) =
    gross_tonnage(hull, assumptions) >= assumptions[:ets_gross_tonnage] ?
    EU_ETS_SHARES[route] : 0.0

"""
    port_costs(hull, assumptions)

Dues and services [USD] of one call at the loading port, charged per gross tonnage, and
one at the discharge port, charged per m^3 of length times beam times draft.
"""
function port_costs(hull::Hull, assumptions::Assumptions)
    dues = assumptions[:loading_port_dues] * gross_tonnage(hull, assumptions) +
           assumptions[:discharge_port_dues] * hull.length * hull.beam * hull.draft
    return assumptions[:usd_per_eur] * dues + 2assumptions[:port_service_cost]
end

"""
    rig_costs(rig, assumptions)

Capital [USD], mass [t] and annual capital cost [USD/year] of `rig`: its
[`rig_price_parts`](@ref) times the market price factor, plus a kite's canopy and tether,
which are written off by wear instead of an annuity.
"""
rig_costs(::Nothing, assumptions) = (0.0, 0.0, 0.0)
rig_costs(rig::CombinedRig, assumptions) =
    rig_costs(rig.kite, assumptions) .+ rig_costs(rig.standing, assumptions)

function rig_costs(rig::Union{WingRig, RotorRig}, assumptions)
    lifetime = assumptions[Symbol(deck_unit(rig), :_lifetime)]
    capital = assumptions[:market_price_factor] * sum(rig_price_parts(rig, assumptions))
    annuity = capital_recovery(assumptions[:discount_rate], lifetime) * capital
    mass = unit_mass(rig, assumptions) + pedestal_mass(rig, assumptions)
    return capital, rig.count * mass, annuity
end

"mass [t] of one wing, rotor or suction sail of `rig` with its foundation on deck"
unit_mass(rig::Union{WingRig, RotorRig}, assumptions) =
    assumptions[Symbol(deck_unit(rig), :_mass_per_area)] * size_factor(rig, assumptions) *
    total_area(rig) / rig.count

"""
    pedestal_mass(rig, assumptions)

Steel mass [t] of what each raised unit of `rig` stands on, by `rig.pedestal`: a
[`column_mass`](@ref) or a [`frame_mass`](@ref); zero for units on deck and in a container,
which is their own foundation.
"""
function pedestal_mass(rig::Union{WingRig, RotorRig}, assumptions)
    rig.pedestal_height > 0 && rig.pedestal != :container || return 0.0
    return rig.pedestal == :frame ? frame_mass(rig, assumptions) :
           column_mass(rig, assumptions)
end

"length [m] of a 40 ft container, the bay a frame's beam spans"
const FORTY_FOOT = 12.192

"""
    unit_loads(rig, assumptions)

Factored loads [N] on each raised unit of `rig` at its mid height: its [`peak_force`](@ref)
times `rig_wind_load_factor`, its mass in the design acceleration across the ship and its
weight, each times `rig_inertia_load_factor`; and the unit's mass [kg].
"""
function unit_loads(rig, assumptions)
    mass = 1e3unit_mass(rig, assumptions)
    inertia_factor = assumptions[:rig_inertia_load_factor]
    wind = assumptions[:rig_wind_load_factor] * peak_force(rig, assumptions)
    return (; wind, roll=inertia_factor * mass * assumptions[:rig_design_acceleration],
        weight=inertia_factor * mass * Environment(assumptions).gravity, mass)
end

"""
    box_moduli(depth, width)

Section moduli [m^2, per m of wall] of a thin-walled box `depth` [m] along the bending
plane and `width` [m] across it, bent in its depth and in its width, and its perimeter [m].
"""
box_moduli(depth, width) =
    (; along=depth * (depth / 3 + width), across=width * (width / 3 + depth),
        perimeter=2(depth + width))

"""
    steel_wall(stress_load, assumptions)

Wall thickness [m] that carries `stress_load` [N/m], stress times thickness, at the
allowable stress, and whose plating between stiffeners does not buckle under it.
"""
function steel_wall(stress_load, assumptions)
    buckling_stiffness = π^2 * 1e6assumptions[:steel_modulus] / (3(1 - 0.3^2))
    return max(stress_load / (1e6assumptions[:pedestal_allowable_stress]),
        cbrt(stress_load * assumptions[:pedestal_stiffener_spacing]^2 / buckling_stiffness))
end

"""
    sway_wall(mass, height, arm, bending, wall_mass, assumptions)

Wall thickness [m] at which a unit of `mass` [kg], `arm` [m] above the top of cantilevers
`height` [m] tall of bending stiffness `bending` [m^3] times the thickness and of mass
`wall_mass` [kg/m^2] per m of height and of thickness, sways at `pedestal_min_frequency`;
Inf where no wall does.
"""
function sway_wall(mass, height, arm, bending, wall_mass, assumptions)
    omega = 2π * assumptions[:pedestal_min_frequency]
    compliance = pedestal_compliance(height, arm)
    wall = omega^2 * compliance * mass /
           (1e6assumptions[:steel_modulus] * bending -
            omega^2 * compliance * 0.24wall_mass * height)
    return wall > 0 ? wall : Inf
end

"mass [kg] per m of member and m of wall thickness of a stiffened box of `perimeter` [m]"
box_wall_mass(perimeter, assumptions) =
    (1 + assumptions[:pedestal_stiffener_share]) * assumptions[:steel_density] * perimeter

"""
    column_mass(rig, assumptions)

Steel mass [t] of a column under each raised unit of `rig`: a stiffened box `bay_gap` deep
along the ship and as wide as the unit, from the deck to the unit's foot, of the
[`pedestal_wall`](@ref) thickness.
"""
function column_mass(rig::Union{WingRig, RotorRig}, assumptions)
    perimeter = box_moduli(assumptions[:bay_gap], unit_width(rig)).perimeter
    return 1e-3box_wall_mass(perimeter, assumptions) *
           rig.pedestal_height * pedestal_wall(rig, assumptions)
end

"""
    pedestal_wall(rig, assumptions)

Wall thickness [m] of the column under each raised unit of `rig`, the thickest of two:
the [`steel_wall`](@ref) under the moments at the deck about the unit's mid height of its
factored wind force along the ship and roll across it; and the [`sway_wall`](@ref) along
the ship, with the unit on top.
"""
function pedestal_wall(rig::Union{WingRig, RotorRig}, assumptions)
    (; wind, roll, mass) = unit_loads(rig, assumptions)
    box = box_moduli(assumptions[:bay_gap], unit_width(rig))
    arm = rig.pedestal_height + rig.height / 2
    stress_load = wind * arm / box.along + roll * arm / box.across
    bending = assumptions[:bay_gap] * box.along / 2
    return max(steel_wall(stress_load, assumptions),
        sway_wall(mass, rig.pedestal_height, rig.height / 2, bending,
            box_wall_mass(box.perimeter, assumptions), assumptions))
end

"""
    frame_mass(rig, assumptions)

Steel mass [t] of a frame under each raised unit of `rig`: two legs in the gaps at both
ends of a 40 ft bay and a beam across their tops over the stacks that carries the unit at its middle, all stiffened boxes
of the column's section, of the [`frame_walls`](@ref) thicknesses.
"""
function frame_mass(rig::Union{WingRig, RotorRig}, assumptions)
    perimeter = box_moduli(assumptions[:bay_gap], unit_width(rig)).perimeter
    (; leg, beam) = frame_walls(rig, assumptions)
    legs = 2leg * rig.pedestal_height
    return 1e-3box_wall_mass(perimeter, assumptions) *
           (legs + beam * (FORTY_FOOT + assumptions[:bay_gap]))
end

"""
    frame_walls(rig, assumptions)

Wall thicknesses [m] of the legs and the beam of the frame under each raised unit of
`rig`, from the moments at the legs' feet and the beam's middle with the unit's factored
wind force along the ship or across it and its roll across it, its weight on the beam, as a
portal along the ship and two cantilevers across it; the legs also sway across the ship no
slower than `pedestal_min_frequency`.
"""
function frame_walls(rig::Union{WingRig, RotorRig}, assumptions)
    (; wind, roll, weight, mass) = unit_loads(rig, assumptions)
    depth = assumptions[:bay_gap]
    width = unit_width(rig)
    box = box_moduli(depth, width)
    height, arm, span = rig.pedestal_height, rig.height / 2, FORTY_FOOT + depth
    leg_along = wind * (height + arm) / (span * box.perimeter) +
                wind * height / 4box.along + roll * (height + arm) / 2box.across
    leg_across = (wind + roll) * (height + arm) / 2box.across
    bending = width * box.across
    leg = max(steel_wall(max(leg_along, leg_across), assumptions),
        sway_wall(mass, height, arm, bending, 2box_wall_mass(box.perimeter, assumptions),
            assumptions))
    beam_load(along, across) =
        frame_beam_load(along, across, weight, span, arm, box, 2depth * width)
    return (; leg, beam=steel_wall(max(beam_load(wind, roll), beam_load(0.0, wind + roll)),
        assumptions))
end

"""
    frame_beam_load(along, across, weight, span, arm, box, shear_area)

Stress times thickness [N/m] at the middle of a frame's beam of `span` [m] and section `box`
([`box_moduli`](@ref)) under a unit of `weight` [N] and forces `along` and `across` the
ship [N] `arm` [m] above it: bending and, as von Mises adds it, the torsion of the force
across on the box's enclosed `shear_area` [m^2] twice over.
"""
frame_beam_load(along, across, weight, span, arm, box, shear_area) = hypot(
    (weight * span / 4 + along * arm / 2) / box.along + across * span / 4box.across,
    sqrt(3) * across * arm / 2shear_area)

"""
    blocked_slots(rig, class, assumptions)

TEU slots on the deck of `class` that `rig` takes from cargo: below each frame's beam, the
rows the unit's width covers over one 40 ft bay through all deck tiers, which the cranes
cannot work; the 40 ft slot of the top tier each container stands in; none for other rigs.
"""
blocked_slots(rig, class, assumptions) = 0.0

function blocked_slots(rig::Union{WingRig, RotorRig}, class::ShipClass, assumptions)
    raised(rig) || return 0.0
    rig.pedestal == :container && return 2.0rig.count
    rig.pedestal == :frame || return 0.0
    rows = ceil(unit_width(rig) / assumptions[:container_row_pitch])
    return rig.count * 2rows * class.deck_tiers
end

"""
    container_holds(rig, assumptions)

Whether each unit of `rig` may stand in a 40 ft container on the stacks, held by its four
twistlocks: suction sails alone, where the factored moment of their wind force and roll
across the 8 ft box, from their mid height above the twistlocks, less the weight of the
unit with its container, pulls each twistlock on one side by no more than
`twistlock_working_load`.
"""
function container_holds(rig, assumptions)
    rig isa WingRig && rig.unit == :suction || return false
    (; wind, roll, mass) = unit_loads(rig, assumptions)
    arm = assumptions[:pedestal_clearance] + rig.height / 2
    weight = mass * Environment(assumptions).gravity
    pull = (wind + roll) * arm / 2EIGHT_FOOT - weight / 4
    return pull <= 1e3assumptions[:twistlock_working_load]
end

"width [m] of a standard container, 8 ft"
const EIGHT_FOOT = 2.438

"""
    pedestal_compliance(height, arm)

Deflection [m^4, times the bending stiffness EI] of a cantilever column `height` [m] tall
under a unit force on a rigid extension `arm` [m] above its top, at that force.
"""
pedestal_compliance(height, arm) = height^3 / 3 + arm * height^2 + arm^2 * height

"unit of the wings, rotors or suction sails of `rig`, naming their assumptions"
deck_unit(rig::WingRig) = rig.unit
deck_unit(::RotorRig) = :rotor

"""
    size_factor(rig, assumptions)

Growth [-] of the mass and price per m^2 of the units of the wings, rotors or suction sails
`rig` over those of the tallest built, their reference height h0: (h / h0)^(k - 2) for
units of height h above it, k their mass exponent, and 1 up to it.
"""
function size_factor(rig::Union{WingRig, RotorRig}, assumptions)
    setting(name) = assumptions[Symbol(deck_unit(rig), name)]
    return max(rig.height / setting(:_reference_height), 1.0)^(setting(:_mass_exponent) - 2)
end

function rig_costs(rig::KiteRig, assumptions)
    canopy, tether = consumable_costs(rig, assumptions)
    hardware = assumptions[:market_price_factor] * sum(rig_price_parts(rig, assumptions))
    annuity = capital_recovery(assumptions[:discount_rate], assumptions[:kite_lifetime]) *
              hardware
    return hardware + canopy + tether, 1e-3kite_rig_mass(rig, assumptions), annuity
end

"""
    kite_rig_mass(rig, assumptions)

Mass [kg] of a kite `rig` on the ship: its deck system, the kite with its control unit or
airframe, and its tether.
"""
kite_rig_mass(rig::KiteRig, assumptions) =
    sum(kite_deck_masses(rig.area, rig.max_force, assumptions)) +
    kite_mass(rig, assumptions) + tether_mass(rig, assumptions)

"""
    tether_mass(rig, assumptions)

Mass [kg] of the tether of a kite `rig`: rope of its diameter and length, or for VTOL kites
an electrified tether at its mass per force limit and length.
"""
tether_mass(rig::KiteRig, assumptions) =
    rope_mass(rig.tether_diameter, rig.tether_length, assumptions)
tether_mass(rig::KiteRig{RigidAirframe}, assumptions) =
    assumptions[:rigid_tether_mass_per_force_length] * rig.max_force * rig.tether_length /
    1e6

"mass [kg] of the kite of `rig` without its tether"
kite_mass(rig::KiteRig, assumptions) =
    soft_kite_mass(rig.area, rig.aspect_ratio, rig.max_force, assumptions)
kite_mass(rig::KiteRig{RigidAirframe}, assumptions) = rig.airframe.mass

"""
    kite_deck_masses(area, max_force, assumptions)

Masses [kg] of the deck system of a kite of projected `area` [m^2] and tether force limit
`max_force` [N]: its winch with the tow point, which hold that force, and its launch mast
and docking head with their seats, which grow with the kite's size.
"""
kite_deck_masses(area, max_force, assumptions) =
    (winch=1e-3assumptions[:winch_mass_per_force] * max_force,
        launch_mast=1e3assumptions[:launch_mast_mass_per_size] * sqrt(area))

"""
    kite_deck_price(area, max_force, assumptions)

Cost [USD] of the [`kite_deck_masses`](@ref), each at its cost per kg.
"""
function kite_deck_price(area, max_force, assumptions)
    (; winch, launch_mast) = kite_deck_masses(area, max_force, assumptions)
    return assumptions[:winch_cost_per_mass] * winch +
           assumptions[:welded_steel_cost_per_mass] * launch_mast
end

function rig_costs(rig::KiteRig{RigidAirframe}, assumptions)
    _, tether = consumable_costs(rig, assumptions)
    hardware = assumptions[:market_price_factor] * sum(rig_price_parts(rig, assumptions)) +
               rigid_airframe_price(rig, assumptions)
    annuity = capital_recovery(assumptions[:discount_rate], assumptions[:kite_lifetime]) *
              hardware
    return hardware + tether, 1e-3kite_rig_mass(rig, assumptions), annuity
end

"""
    rig_price_parts(rig, assumptions)

Manufacturing cost [USD] of each part of the hardware of `rig`: the units, their surface,
the installation, the supports of raised units and the camera systems of wings or rotors;
the deck system, control unit, ship-side controls and integration of a kite, without its
canopy and tether; the deck system, supply for the hover, ship-side controls and
integration of VTOL kites, without their airframes and tethers.
"""
rig_price_parts(::Nothing, assumptions) = (;)

rig_price_parts(rig::WingRig, assumptions) = (;
    deck_price_parts(rig.count, total_area(rig), assumptions, :wing_unit_cost,
        size_factor(rig, assumptions) * surface_cost(rig, assumptions),
        :wing_installation_fraction)...,
    raised_parts(rig, assumptions)...)
rig_price_parts(rig::RotorRig, assumptions) = (;
    deck_price_parts(rig.count, total_area(rig), assumptions, :rotor_unit_cost,
        size_factor(rig, assumptions) * assumptions[:rotor_cost_per_area],
        :rotor_installation_fraction)...,
    raised_parts(rig, assumptions)...)

"cost [USD] of the supports of the raised units and of the camera systems of `rig`"
raised_parts(rig::Union{WingRig, RotorRig}, assumptions) = (;
    pedestals=1e3rig.count * pedestal_mass(rig, assumptions) *
              assumptions[:welded_steel_cost_per_mass],
    cameras=rig.camera_units * assumptions[:camera_system_cost])

"""
    surface_cost(rig::WingRig, assumptions)

Manufacturing cost [USD/m^2] of the wings of `rig` per m^2: that of wing sails, or the
mass of suction sails per m^2 at their cost per kg.
"""
surface_cost(rig::WingRig, assumptions) = rig.unit == :suction ?
    1e3assumptions[:suction_mass_per_area] * assumptions[:suction_cost_per_mass] :
    assumptions[:wing_cost_per_area]

"""
    deck_price_parts(count, area, assumptions, unit_cost, cost_per_area, fraction)

[`rig_price_parts`](@ref) of `count` wings or rotors of `area` [m^2] in all at
`cost_per_area` [USD/m^2], with the names of their other assumptions.
"""
function deck_price_parts(count, area, assumptions, unit_cost, cost_per_area, fraction)
    units = count * assumptions[unit_cost]
    surface = cost_per_area * area
    return (; units, surface, installation=assumptions[fraction] * (units + surface))
end

"""
    launch_mast_height(area, assumptions)

Height [m] of the launch mast of a kite of projected `area` [m^2].
"""
launch_mast_height(area, assumptions) = min(
    assumptions[:launch_mast_height_ratio] * sqrt(area),
    assumptions[:launch_mast_max_height])

rig_price_parts(rig::KiteRig, assumptions) =
    kite_price_parts(rig.area, rig.max_force, assumptions)

"""
    kite_price_parts(area, max_force, assumptions)

[`rig_price_parts`](@ref) of a soft kite of projected `area` [m^2] and tether force limit
`max_force` [N]: its [`kite_deck_price`](@ref), its control unit at its cost per kg, and
its ship-side controls.
"""
function kite_price_parts(area, max_force, assumptions)
    control_unit_mass = 1e-3assumptions[:control_unit_mass_per_force] * max_force
    parts = (deck=kite_deck_price(area, max_force, assumptions),
        control_unit=assumptions[:control_unit_cost_per_mass] * control_unit_mass,
        controls=assumptions[:kite_controls_cost])
    return (; parts..., integration=assumptions[:kite_integration_fraction] * sum(parts))
end

function rig_price_parts(rig::KiteRig{RigidAirframe}, assumptions)
    parts = (deck=kite_deck_price(rig.area, rig.max_force, assumptions),
        ship_power=assumptions[:rigid_ship_power_cost] * rig.airframe.hover_power,
        controls=assumptions[:kite_controls_cost])
    return (; parts..., integration=assumptions[:kite_integration_fraction] * sum(parts))
end

"""
    canopy_price(assumptions, area, aspect_ratio)

Price of the canopy of a kite of projected `area` [m^2] and projected `aspect_ratio` per m^2
of projected area [USD/m^2]: its [`canopy_cost`](@ref) times the market price factor.
"""
canopy_price(assumptions, area, aspect_ratio) = assumptions[:market_price_factor] *
    Canopy(assumptions, area, aspect_ratio).cost_per_area

"inputs that together make the canopy's cost"
canopy_price_inputs = (:canopy_structure_cost, :canopy_cloth_base_price,
    :canopy_cloth_price_per_weight)

"""
    consumable_costs(rig, assumptions)

Price of one canopy and one tether [USD]: the canopy at its [`canopy_price`](@ref), the
tether at its purchase price per kg; no canopy for VTOL kites.
"""
function consumable_costs(rig::KiteRig, assumptions)
    canopy = canopy_price(assumptions, rig.area, rig.aspect_ratio) * rig.area
    return canopy, assumptions[:tether_price] * tether_mass(rig, assumptions)
end

consumable_costs(rig::KiteRig{RigidAirframe}, assumptions) =
    (0.0, assumptions[:rigid_tether_price] * tether_mass(rig, assumptions))

"""
    worn_part_price(rig, assumptions)

Price [USD] of the parts of `rig` that wear replaces, which maintenance does not charge:
a kite's canopy and tether; zero for other rigs.
"""
worn_part_price(rig, assumptions) = 0.0
worn_part_price(rig::CombinedRig, assumptions) = worn_part_price(rig.kite, assumptions)
worn_part_price(rig::KiteRig, assumptions) = sum(consumable_costs(rig, assumptions))

"""
    rig_maintenance(rig, capital, assumptions)

Yearly maintenance [USD/year] of `rig` of market price `capital` [USD]: the rig
maintenance fraction of that price without what wear or upkeep per flight hour pays for,
a kite's canopy and tether and a rigid kite's airframe.
"""
rig_maintenance(rig, capital, assumptions) = assumptions[:rig_maintenance_fraction] *
                                             (capital - upkept_price(rig, assumptions))

"""
    upkept_price(rig, assumptions)

Price [USD] of the parts of `rig` that wear or upkeep per flight hour pays for.
"""
upkept_price(rig, assumptions) = worn_part_price(rig, assumptions)
upkept_price(rig::CombinedRig, assumptions) = upkept_price(rig.kite, assumptions)
upkept_price(rig::KiteRig{RigidAirframe}, assumptions) =
    rigid_airframe_price(rig, assumptions) + worn_part_price(rig, assumptions)

"""
    wear_cost(rig, assumptions)

Canopy wear and tether creep, or a VTOL kite's upkeep, per hour the rig is flown [USD/h];
zero for rigs that do not wear.
"""
wear_cost(rig, assumptions) = 0.0
wear_cost(rig::CombinedRig, assumptions) = wear_cost(rig.kite, assumptions)

function wear_cost(rig::KiteRig, assumptions)
    canopy, tether = consumable_costs(rig, assumptions)
    return canopy / assumptions[:canopy_life] + tether / assumptions[:tether_lifetime]
end

"""
    with_kite_aspect_ratio(assumptions, aspect_ratio)

`assumptions` with the kite at projected `aspect_ratio` and the tether, the priced part
that follows span, cheaper per kg so that it pays what a kite of the aspect ratio of
`assumptions` pays.
"""
function with_kite_aspect_ratio(assumptions::Assumptions, aspect_ratio)
    factor = aspect_ratio / assumptions[:kite_aspect_ratio]
    slender = with_value(assumptions, :kite_aspect_ratio, aspect_ratio)
    return with_value(slender, :tether_price, assumptions[:tether_price] / sqrt(factor))
end

"""
    cycle_cost(rig, assumptions)

Cost of one launch and landing of a kite [USD]: the crew time, the canopy life its flogging
uses up, the expected [`crash_cost`](@ref) of a kite lost, any turn for the launch and the
[`tether_bending_cost`](@ref); zero for other rigs.
"""
cycle_cost(rig, assumptions) = 0.0
cycle_cost(rig::CombinedRig, assumptions) = cycle_cost(rig.kite, assumptions)

function cycle_cost(rig::KiteRig, assumptions)
    canopy, tether = consumable_costs(rig, assumptions)
    return assumptions[:kite_cycle_crew_cost] +
           assumptions[:kite_cycle_canopy_hours] / assumptions[:canopy_life] * canopy +
           assumptions[:kite_launch_loss_probability] * crash_cost(rig, assumptions) +
           assumptions[:kite_cycle_course_cost] + tether_bending_cost(tether, assumptions)
end

"""
    tether_bending_cost(tether, assumptions)

Share of the price of a `tether` [USD] used up by its bends over the drum and sheaves while
it is reeled out at one launch and in at the landing [USD].
"""
tether_bending_cost(tether, assumptions) =
    tether * assumptions[:tether_bends_per_launch] / assumptions[:tether_bend_life]

"""
    rigid_airframe_price(rig, assumptions)

Market price of the kite of `rig` alone: the airframe with its propellers and drives by
its mass, and avionics [USD].
"""
rigid_airframe_price(rig::KiteRig{RigidAirframe}, assumptions) =
    assumptions[:market_price_factor] * (assumptions[:rigid_cost_per_mass] *
     rig.airframe.mass + assumptions[:rigid_avionics_cost])

wear_cost(rig::KiteRig{RigidAirframe}, assumptions) =
    assumptions[:rigid_upkeep_per_area] * rig.area +
    last(consumable_costs(rig, assumptions)) / assumptions[:tether_lifetime]

"""
    cycle_cost(rig::KiteRig{RigidAirframe}, assumptions)

Cost of launching and landing the kite of `rig` once [USD]: crew time and the expected
loss of a kite.
"""
cycle_cost(rig::KiteRig{RigidAirframe}, assumptions) =
    assumptions[:kite_cycle_crew_cost] +
    assumptions[:rigid_cycle_loss_probability] * crash_cost(rig, assumptions)

"""
    lost_kite_cost(rig, assumptions)

Cost of the soft kite of `rig` lost in the water with its canopy, tether and control unit,
at market prices [USD].
"""
function lost_kite_cost(rig::KiteRig, assumptions)
    canopy, tether = consumable_costs(rig, assumptions)
    control_unit = rig_price_parts(rig, assumptions).control_unit
    return canopy + tether + assumptions[:market_price_factor] * control_unit
end

"""
    crash_cost(rig, assumptions)

Cost [USD] of one kite, wing or rotor lost, beyond the wear already charged: a soft kite's
control unit and half of its canopy and tether, on average halfway through their life when
lost, a VTOL kite's airframe, or the price of one wing or rotor with its installation.
"""
crash_cost(rig::KiteRig, assumptions) =
    lost_kite_cost(rig, assumptions) - sum(consumable_costs(rig, assumptions)) / 2
crash_cost(rig::KiteRig{RigidAirframe}, assumptions) =
    rigid_airframe_price(rig, assumptions)

crash_cost(rig::Union{WingRig, RotorRig}, assumptions) =
    first(rig_costs(rig, assumptions)) / deck_units(rig)

"""
    time_cost(costs, assumptions, cargo)

Cost of one hour at sea with `cargo` [t] on board [USD/h]: the fixed annual cost spread
over the trading hours plus the interest on the cargo.
"""
time_cost(costs::ShipCosts, assumptions::Assumptions, cargo) =
    costs.fixed_annual / (8760assumptions[:availability]) +
    cargo_interest(costs, assumptions, cargo)

"""
    cargo_interest(costs, assumptions, cargo)

Interest on `cargo` [t] of the value `costs.cargo_value` for one hour [USD/h].
"""
cargo_interest(costs::ShipCosts, assumptions::Assumptions, cargo) =
    cargo * costs.cargo_value * assumptions[:discount_rate] / 8760

"""
    voyage_time_cost(costs, assumptions, cargo, out_hours, back_hours, port_hours)

Time cost of a round trip [USD]: the fixed cost over both passages and two port calls of
`port_hours` [h] each, and the interest on `cargo` [t] for the outbound passage and on
the backhaul share of it for the return, each with one call's time for its loading and
discharge.
"""
function voyage_time_cost(costs::ShipCosts, assumptions::Assumptions, cargo, out_hours,
        back_hours, port_hours)
    fixed = time_cost(costs, assumptions, 0.0) * (out_hours + back_hours + 2port_hours)
    cargo_hours = out_hours + port_hours +
                  assumptions[:backhaul_fraction] * (back_hours + port_hours)
    return fixed + cargo_interest(costs, assumptions, cargo) * cargo_hours
end

"""
    leg_time_costs(costs, assumptions)

Hourly time cost [USD/h] of the outbound and the return leg of a ship loaded to its
hold, for the router.
"""
function leg_time_costs(costs::ShipCosts, assumptions::Assumptions)
    cargo = cargo_mass(costs.hold)
    return time_cost(costs, assumptions, cargo),
           time_cost(costs, assumptions, assumptions[:backhaul_fraction] * cargo)
end

"outcome of the round trip of one departure in a [`RoundTrip`](@ref)"
const DepartureOutcome = @NamedTuple{departure::Float64, cost_per_tonne_km::Float64,
    fuel_per_tonne_km::Float64, flight_share::Float64}

"""
    Passages

What one service state of a design does per round trip, on one departure or averaged over
the departures.
"""
struct Passages
    "fuel energy [J]"
    energy::Float64
    "hours at sea outbound [h]"
    out_hours::Float64
    "hours at sea on the return [h]"
    back_hours::Float64
    "hours a kite flies patterns [h]"
    flight_hours::Float64
    "kite launches"
    launches::Float64
    "kite landings outside the landing limits"
    forced_landings::Float64
    "fuel energy of the largest leg over the departures [J]"
    largest_leg::Float64
end

"""
    RoundTrip

Mean outcome of one design over all departures in the weather sample.
"""
struct RoundTrip
    design::ShipDesign
    "transport cost [USD per tonne-km]"
    cost_per_tonne_km::Float64
    "fuel energy per round trip [GJ]"
    fuel_energy::Float64
    "fuel per tonne-km [MJ]"
    fuel_per_tonne_km::Float64
    "CO2 per tonne-km, tank-to-wake [g]"
    carbon_per_tonne_km::Float64
    outbound_days::Float64
    return_days::Float64
    "cargo carried outbound [t]"
    cargo::Float64
    capital::Float64
    "installed engine or genset power [kW]"
    installed_power::Float64
    "share of sea time a kite flies patterns [-]"
    flight_share::Float64
    "kite launches per round trip"
    launches::Float64
    "kite landings outside the landing limits per round trip"
    forced_landings::Float64
    "whether the wings or rotors are retractable, the cheaper option for the ship"
    retractable::Bool
    "what each of the [`service_states`](@ref) does, `nothing` where it was not routed"
    passages::Vector{Union{Nothing, Passages}}
    "each departure [h] with its cost [USD per tonne-km], fuel per tonne-km [MJ] and kite
    flight share [-], the ship and its cargo as over all departures"
    departures::Vector{DepartureOutcome}
end

"""
    route_round_trip(table, outbound, inbound, weather, departure, port_hours, hourly,
                     forecast; schedule=(Inf, Inf))

Outbound and return [`Leg`](@ref) of [`forecast_route`](@ref) on the [`RouteTable`](@ref)
`table` for one departure at the outbound and return time costs `hourly` [USD/h], each
arriving by its time [h] in `schedule`, or `nothing` if either fails, planned on
`forecast`, or on the real weather where that is `nothing`.
"""
function route_round_trip(table, outbound, inbound, weather, departure, port_hours, hourly,
        forecast; schedule=(Inf, Inf))
    out = forecast_route(outbound, table, weather, departure; time_cost=first(hourly),
        arrival_by=first(schedule), forecast)
    isnothing(out) && return nothing
    back = forecast_route(inbound, table, weather, departure + out.duration + port_hours;
        time_cost=last(hourly), arrival_by=last(schedule), forecast)
    isnothing(back) && return nothing
    return out, back
end

"""
    fuel_store(ship, largest_leg, assumptions)

Fuel store of `ship` sized for its largest leg's fuel energy `largest_leg` [J] times the
reserve factor: the mass with the fuel [t], the hold space [m^3] and the price [USD].
"""
function fuel_store(ship::Ship, largest_leg, assumptions::Assumptions)
    (; store) = Drive(ship.design.drive, assumptions)
    fuel = assumptions[:fuel_reserve_factor] * largest_leg / ship.fuel.heating_value
    return (mass=store.mass_ratio * fuel / 1e3, volume=store.volume * fuel,
        price=store.price * fuel)
end

"""
    store_round_trip_cost(price, hours, assumptions)

Annuity and maintenance [USD] of a fuel store of `price` [USD] over a round trip of
`hours` [h], written off over the hull lifetime.
"""
store_round_trip_cost(price, hours, assumptions::Assumptions) =
    (capital_recovery(assumptions[:discount_rate], assumptions[:hull_lifetime]) +
     assumptions[:maintenance_fraction]) * price * hours / (8760assumptions[:availability])

"""
    out_of_service_share(rig, assumptions)

Share of the round trips [-] that a unit of `rig` sails out of service.
"""
out_of_service_share(rig::WingRig, assumptions) =
    assumptions[Symbol(rig.unit, :_out_of_service)]
out_of_service_share(::RotorRig, assumptions) = assumptions[:rotor_out_of_service]
out_of_service_share(::KiteRig, assumptions) = assumptions[:kite_out_of_service]

"""
    any_unit_down(rig, assumptions)

Share of the round trips [-] with any of the units of `rig` out of service, each out for
the share given by its input and independent of the others.
"""
any_unit_down(rig, assumptions) =
    1 - (1 - out_of_service_share(rig, assumptions))^deck_units(rig)

"""
    working_share(rig, assumptions)

Mean share of the units of `rig` still working on the round trips with any down [-].
"""
function working_share(rig, assumptions)
    any_down = any_unit_down(rig, assumptions)
    return any_down > 0 ? 1 - out_of_service_share(rig, assumptions) / any_down : 1.0
end

down_rig(rig::Union{WingRig, RotorRig}, working_share) = DownRig(rig, working_share)
down_rig(::KiteRig, working_share) = nothing

"""
    service_states(rig, assumptions)

What of `rig` works over a year as (share of the round trips, rig) pairs, the working rig
first, states with no share included: the [`state_shares`](@ref) with the
[`state_rigs`](@ref).
"""
service_states(rig, assumptions) =
    collect(zip(state_shares(rig, assumptions), state_rigs(rig, assumptions)))

"""
    state_shares(rig, assumptions)

Share of the round trips [-] in each state of [`state_rigs`](@ref): of a
[`CombinedRig`](@ref) each part fails on its own.
"""
function state_shares(rig, assumptions)
    any_down = any_unit_down(rig, assumptions)
    return [1 - any_down, any_down]
end

state_shares(::Nothing, assumptions) = [1.0]

function state_shares(rig::CombinedRig, assumptions)
    kite = out_of_service_share(rig.kite, assumptions)
    any_down = any_unit_down(rig.standing, assumptions)
    return [(1 - kite) * (1 - any_down), kite * (1 - any_down), (1 - kite) * any_down,
        kite * any_down]
end

"""
    state_rigs(rig, assumptions)

What of `rig` works with all units in service and with any down. Trips with a unit down
hold the mean of the units working, so the rig keeps its mean capacity. A lone kite out
of service is stowed, of several rigid kites the others fly, and wings or rotors stand
as a [`DownRig`](@ref).
"""
state_rigs(rig, assumptions) = [rig, down_rig(rig, working_share(rig, assumptions))]
state_rigs(::Nothing, assumptions) = [nothing]

function state_rigs(rig::CombinedRig, assumptions)
    down = DownRig(rig.standing, working_share(rig.standing, assumptions))
    return [rig, rig.standing, CombinedRig(rig.kite, down), down]
end

"""
    service_passages(ship, outbound, inbound, weather, departures, assumptions, hourly,
                     port_hours, forecast, held_knots;
                     schedules=Iterators.repeated((Inf, Inf)))

[`Passages`](@ref) of `ship` on the round trip of each of `departures`; `nothing` if any
passage is infeasible. The router holds `held_knots` [kn] by [`held_speed_table`](@ref),
or chooses speed where `nothing`, each round trip keeping its leg times in `schedules`.
"""
function service_passages(ship::Ship, outbound, inbound, weather, departures, assumptions,
        hourly, port_hours, forecast, held_knots;
        schedules=Iterators.repeated((Inf, Inf)))
    table = PerformanceTable(ship, assumptions)
    route_table = isnothing(held_knots) ? RouteTable(table) :
                  held_speed_table(table, held_knots)
    legs = fetch.([Threads.@spawn route_round_trip(route_table, outbound, inbound, weather,
                       departure, port_hours, hourly, forecast; schedule)
                   for (departure, schedule) in zip(departures, schedules)])
    any(isnothing, legs) && return nothing
    largest_leg = maximum(max(out.fuel_energy, back.fuel_energy) for (out, back) in legs)
    return [Passages(out.fuel_energy + back.fuel_energy, out.duration, back.duration,
                out.flight_hours + back.flight_hours, out.launches + back.launches,
                out.forced_landings + back.forced_landings, largest_leg)
            for (out, back) in legs]
end

"""
    mean_passages(departures)

[`Passages`](@ref) averaged over the `departures` of one service state.
"""
mean_passages(departures) = Passages(mean(passage.energy for passage in departures),
    mean(passage.out_hours for passage in departures),
    mean(passage.back_hours for passage in departures),
    mean(passage.flight_hours for passage in departures),
    mean(passage.launches for passage in departures),
    mean(passage.forced_landings for passage in departures),
    maximum(passage.largest_leg for passage in departures))

"""
    state_mean(quantity, shares, passages)

Mean of `quantity(passages)` over the service states, weighted by their `shares`; states
not routed, `nothing` in `passages`, count for nothing.
"""
state_mean(quantity, shares, passages) = sum(share * quantity(passage)
                                             for (share, passage) in zip(shares, passages)
                                             if !isnothing(passage))

"""
    rig_running_cost(rig, passage, assumptions)

Wear and launches of `rig` over the round trip of `passage` [USD].
"""
rig_running_cost(rig, passage::Passages, assumptions) =
    wear_cost(rig, assumptions) * passage.flight_hours +
    cycle_cost(rig, assumptions) * passage.launches

"""
    yearly_crash_cost(rig, assumptions)

Expected cost of lost wings or rotors of `rig` per year [USD/year], at the loss rate of
each unit; a lost kite is charged per launch in [`cycle_cost`](@ref).
"""
yearly_crash_cost(rig, assumptions) = 0.0
yearly_crash_cost(rig::CombinedRig, assumptions) =
    yearly_crash_cost(rig.standing, assumptions)
yearly_crash_cost(rig::Union{WingRig, RotorRig}, assumptions) =
    crash_rate(rig, assumptions) * deck_units(rig) * crash_cost(rig, assumptions)

crash_rate(::WingRig, assumptions) = assumptions[:wing_loss_rate]
crash_rate(::RotorRig, assumptions) = assumptions[:rotor_loss_rate]

"""
    voyage_costs(ship, costs, rigs, passages, outbound, inbound, assumptions)

Cost of the round trip of `ship` of [`ShipCosts`](@ref) `costs`, with its wings or rotors
retractable and fixed, from the [`Passages`](@ref) of its [`service_states`](@ref) with
`rigs`, `nothing` where a state was not routed: the cost per tonne-km [USD] with each of
the two `costs` and the cheaper, the capital of each [USD], the cargo carried outbound
[t] and the tonne-km; `nothing` if the fuel store leaves no cargo. The store holds the
largest leg, and the largest leg with a unit down without its reserve.
"""
function voyage_costs(ship::Ship, costs, rigs, passages, outbound, inbound, assumptions)
    retractable, fixed = costs
    shares = state_shares(ship.rig, assumptions)
    hours = (out=state_mean(passage -> passage.out_hours, shares, passages),
        back=state_mean(passage -> passage.back_hours, shares, passages),
        port=24assumptions[:port_time_per_call])
    reserve = assumptions[:fuel_reserve_factor]
    largest_leg = maximum(passage.largest_leg / (k == 1 ? 1 : reserve)
                          for (k, passage) in enumerate(passages) if !isnothing(passage))
    store = fuel_store(ship, largest_leg, assumptions)
    cargo = cargo_mass(retractable.hold, store.mass, store.volume)
    cargo > 0 || return nothing
    round_trip_hours = hours.out + hours.back + 2hours.port
    rig_cost = sum(share * rig_running_cost(rig, passage, assumptions)
                   for (share, rig, passage) in zip(shares, rigs, passages)
                   if !isnothing(passage))
    running_cost = state_mean(passage -> passage.energy, shares, passages) *
                   Drive(ship.design.drive, assumptions;
                       ship.fuel.carbon_coverage).fuel.price + rig_cost +
                   port_costs(ship.hull, assumptions) +
                   store_round_trip_cost(store.price, round_trip_hours, assumptions) +
                   yearly_crash_cost(ship.rig, assumptions) * round_trip_hours /
                   (8760assumptions[:availability])
    delay = fixed_rig_port_hours(ship.rig, ship.design.class, assumptions)
    tonne_km = cargo * (outbound.track_length +
                        assumptions[:backhaul_fraction] * inbound.track_length) / 1e3
    retractable_cost = (running_cost + voyage_time_cost(retractable, assumptions, cargo,
        hours.out, hours.back, hours.port)) / tonne_km
    fixed_cost = (running_cost + voyage_time_cost(fixed, assumptions, cargo, hours.out,
        hours.back, hours.port + delay)) / tonne_km
    return (; retractable=retractable_cost, fixed=fixed_cost,
        cheaper=min(retractable_cost, fixed_cost),
        retractable_capital=retractable.capital + store.price,
        fixed_capital=fixed.capital + store.price, cargo, tonne_km)
end

"""
    round_trip(ship, outbound, inbound, weather, departures, assumptions;
               forecast=nothing, held_knots=nothing)

Route `ship` out along `outbound` and back along `inbound` for each departure time
[h] in each of its [`service_states`](@ref) with a share, and turn the result averaged
over the departures and the states into the cost per tonne-km of the transport service
by [`voyage_costs`](@ref), and that of each departure with the same ship by
[`departure_outcome`](@ref). With a [`ForecastArchive`](@ref) `forecast` the router
re-plans daily on its forecasts, and with `held_knots` [kn] the ship holds that speed
instead of choosing by cost. A ship of a liner class keeps the [`liner_schedules`](@ref)
where it chooses its speed. Wings and rotors are fixed or retractable, whichever costs
less. The router prices time at the hold's cargo before the fuel store. Returns `nothing`
if any passage is infeasible or the fuel store leaves no cargo.
"""
function round_trip(ship::Ship, outbound::Corridor, inbound::Corridor, weather,
        departures, assumptions::Assumptions; forecast=nothing, held_knots=nothing)
    port_hours = 24assumptions[:port_time_per_call]
    costs = ship_costs(ship, assumptions)
    hourly = leg_time_costs(first(costs), assumptions)
    router_hourly = isnothing(held_knots) ? hourly : HELD_SPEED_TIME_FACTOR .* hourly
    scheduled = isnothing(held_knots) && keeps_schedule(ship)
    schedules = scheduled ?
                liner_schedules(ship, outbound, inbound, weather, departures, assumptions,
        port_hours, forecast) : Iterators.repeated((Inf, Inf))
    isnothing(schedules) && return nothing
    states = service_states(ship.rig, assumptions)
    services = [share > 0 ?
                service_passages(with_rig(ship, rig), outbound, inbound, weather,
                    departures, assumptions, router_hourly, port_hours, forecast,
                    held_knots; schedules) : nothing
                for (share, rig) in states]
    any(isnothing(service) && share > 0
        for ((share, _), service) in zip(states, services)) && return nothing
    passages = [isnothing(service) ? nothing : mean_passages(service)
                for service in services]
    voyage = voyage_costs(ship, costs, last.(states), passages, outbound, inbound,
        assumptions)
    isnothing(voyage) && return nothing
    shares = first.(states)
    mean_of(quantity) = state_mean(quantity, shares, passages)
    energy = mean_of(passage -> passage.energy)
    sea_hours = mean_of(passage -> passage.out_hours + passage.back_hours)
    retractable = voyage.retractable < voyage.fixed
    outcomes = [departure_outcome(ship, costs, states, services, k, departure,
                    retractable, outbound, inbound, assumptions)
                for (k, departure) in enumerate(departures)]
    return RoundTrip(ship.design, voyage.cheaper, energy / 1e9,
        energy / 1e6 / voyage.tonne_km,
        energy * ship.fuel.carbon_intensity * 1e3 / voyage.tonne_km,
        mean_of(passage -> passage.out_hours) / 24,
        mean_of(passage -> passage.back_hours) / 24, voyage.cargo,
        retractable ? voyage.retractable_capital : voyage.fixed_capital,
        ship.powertrain.installed_power / 1e3,
        mean_of(passage -> passage.flight_hours) / sea_hours,
        mean_of(passage -> passage.launches), mean_of(passage -> passage.forced_landings),
        retractable, passages, outcomes)
end

"""
    keeps_schedule(ship)

Whether `ship` has a rig and is of a liner class, so that it keeps the schedule of the
same ship without its rig.
"""
keeps_schedule(ship::Ship) =
    !isnothing(ship.rig) && !isnothing(ship.design.class) && ship.design.class.liner

"""
    liner_schedules(ship, outbound, inbound, weather, departures, assumptions, port_hours,
                    forecast)

Outbound and return times [h] of each of `departures` of `ship` without its rig, routed
for cost as [`round_trip`](@ref) routes it, or `nothing` if a passage fails.
"""
function liner_schedules(ship, outbound, inbound, weather, departures, assumptions,
        port_hours, forecast)
    bare = with_rig(ship, nothing)
    hourly = leg_time_costs(ShipCosts(bare, assumptions), assumptions)
    passages = service_passages(bare, outbound, inbound, weather, departures, assumptions,
        hourly, port_hours, forecast, nothing)
    isnothing(passages) && return nothing
    return [(passage.out_hours, passage.back_hours) for passage in passages]
end

"""
    departure_outcome(ship, costs, states, services, k, departure, retractable, outbound,
                      inbound, assumptions)

[`DepartureOutcome`](@ref) of the `k`th of the departures, at `departure` [h], of `ship`
with the [`ship_costs`](@ref) `costs` and its [`service_states`](@ref) `states`, from the
[`service_passages`](@ref) `services` of each state, `nothing` where not routed; with the
fuel store, cargo and choice of `retractable` or fixed rig of all departures.
"""
function departure_outcome(ship, costs, states, services, k, departure, retractable,
        outbound, inbound, assumptions)
    passages = [isnothing(service) ? nothing : service[k] for service in services]
    voyage = voyage_costs(ship, costs, last.(states), passages, outbound, inbound,
        assumptions)
    shares = first.(states)
    sea_hours = state_mean(passage -> passage.out_hours + passage.back_hours, shares,
        passages)
    return (; departure,
        cost_per_tonne_km=retractable ? voyage.retractable : voyage.fixed,
        fuel_per_tonne_km=state_mean(passage -> passage.energy, shares, passages) / 1e6 /
                          voyage.tonne_km,
        flight_share=state_mean(passage -> passage.flight_hours, shares, passages) /
                     sea_hours)
end
