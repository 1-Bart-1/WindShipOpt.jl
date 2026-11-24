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
unit capacity; the reference coaster family fills its deadweight.
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
        slots = class.unit_capacity
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
    LayoutPrices(ship, route, assumptions)

What fuel and cargo are worth to `ship` on `route`, `nothing` meaning the mean route, in
the year it sails at its service speed for its [`sailing_hours`](@ref), for scoring the
layout of a deck rig.
"""
struct LayoutPrices
    "fuel saved per watt of thrust times service speed over a year [USD/(W year)]"
    thrust_power::Float64
    "fuel burnt per watt of power drawn by the rig over a year [USD/(W year)]"
    rig_power::Float64
    "fixed annual cost and calm-water fuel of the ship without a rig [USD/year]"
    ship_yearly::Float64
end

function LayoutPrices(ship::Ship, route, assumptions::Assumptions)
    (; drive, length, class) = ship.design
    bare = Ship(ShipDesign(drive, length; class), assumptions; route)
    (; powertrain, fuel) = bare
    speed = service_speed(bare, assumptions)
    calm = best_trim(bare, nothing, speed, 0.0, 0.0).thrust
    delivered = delivered_power(bare.propeller, bare.env, speed, calm)
    fuel_year = 3600sailing_hours(bare, route, assumptions) * fuel.price
    rig_power = fuel_year / powertrain.peak_efficiency
    thrust_power = rig_power * delivered / (calm * speed * powertrain.transmission_efficiency)
    ship_yearly = ShipCosts(bare, assumptions).fixed_annual +
                  fuel_year * fuel_power(powertrain, delivered)
    return LayoutPrices(thrust_power, rig_power, ship_yearly)
end

"""
    sailing_hours(ship, route, assumptions)

Hours a year [h] `ship` sails at its service speed on `route`: its trading hours less a
port call at each end of the passages of [`route_length`](@ref); the mean over the routes
where `route` is nothing.
"""
function sailing_hours(ship::Ship, route::Symbol, assumptions::Assumptions)
    passages = 2route_length(route) / service_speed(ship, assumptions) / 3600
    return 8760assumptions[:availability] * passages /
           (passages + 48assumptions[:port_time_per_call])
end

sailing_hours(ship::Ship, ::Nothing, assumptions::Assumptions) =
    mean(sailing_hours(ship, route, assumptions) for route in keys(COASTAL_PATHS))

"""
    layout_score(ship, rig, prices, assumptions)

Yearly cost [USD/year] of the wings, rotors or suction sails of `rig` on `ship` less the
fuel they save at `prices`, a [`LayoutPrices`](@ref): their annuity and maintenance, with
the retractable rig premium where a fixed rig would cost the ship port time, and the
[`lost_cargo_cost`](@ref), less the mean of their thrust times the service speed and the
power they draw, each at its price, at the best trim in the [`layout_winds`](@ref).
"""
function layout_score(ship::Ship, rig, prices::LayoutPrices, assumptions::Assumptions)
    standing = standing_rig(rig)
    capital, _, annuity = rig_costs(standing, assumptions)
    fixed_delay = fixed_rig_port_hours(standing, ship.design.class, assumptions) > 0
    price_factor = 1 + fixed_delay * assumptions[:retractable_rig_premium]
    yearly = price_factor * annuity +
             rig_maintenance(standing, price_factor * capital, assumptions) +
             lost_cargo_cost(ship, standing, prices, assumptions)
    speed = service_speed(ship, assumptions)
    winds = layout_winds(assumptions)
    saved = sum(winds) do (wind_10m, true_angle)
        _, force = best_trim(ship, standing, speed, wind_10m, true_angle)
        return prices.thrust_power * force.thrust * speed - prices.rig_power * force.power
    end / length(winds)
    return yearly - saved
end

"""
    lost_cargo_cost(ship, rig, prices, assumptions)

Yearly cost [USD/year] of the cargo `ship` no longer carries for the mass of `rig`: the
yearly cost of the ship without a rig at `prices`, a [`LayoutPrices`](@ref), times the
share of its cargo the rig takes.
"""
function lost_cargo_cost(ship::Ship, rig, prices::LayoutPrices, assumptions::Assumptions)
    left, full = (cargo_mass(CargoHold(with_rig(ship, held), assumptions))
                  for held in (rig, nothing))
    return prices.ship_yearly * (1 - left / full)
end

"""
    layout_winds(assumptions)

True winds at 10 m [m/s] and their angles off the bow [rad] a layout is scored in: the
midpoints of eight equal parts of a Rayleigh distribution of mean `layout_mean_wind`, each
from six directions evenly spread from ahead to astern.
"""
function layout_winds(assumptions::Assumptions)
    scale = assumptions[:layout_mean_wind] / sqrt(π / 2)
    eighths = (1:2:15) ./ 16
    speeds = [scale * sqrt(-2log(1 - quantile)) for quantile in eighths]
    return [(speed, deg2rad(angle)) for speed in speeds for angle in 15:30:165]
end

"""
    cheapest_layout(ship, route, assumptions)

Rig of the design of `ship` in the layout of its [`layout_counts`](@ref) with the lowest
[`layout_score`](@ref) on `ship`, which carries no rig yet, at its [`LayoutPrices`](@ref)
on `route`; for each count of columns more units are tried until two in a row score worse
than the fewest scored best. `nothing` where no layout fits; the design's rig as it is
where it has no wings, rotors or suction sails.
"""
function cheapest_layout(ship::Ship, route, assumptions::Assumptions)
    (; design, hull) = ship
    first(standing_unit(design)) > 0 || return design_rig(design, hull, assumptions)
    counts = layout_counts(design, hull, assumptions)
    prices = LayoutPrices(ship, route, assumptions)
    best, lowest = nothing, Inf
    for columns in 1:2
        rig, score = cheapest_in_columns(ship, columns,
            [last(count) for count in counts if first(count) == columns], prices,
            assumptions)
        score < lowest && ((best, lowest) = (rig, score))
    end
    return best
end

"""
    cheapest_in_columns(ship, columns, in_columns, prices, assumptions)

Rig of the design of `ship` in `columns` columns of the count of `in_columns`, tried in
order, with the lowest [`layout_score`](@ref) at `prices`, and that score; the search
stops once two counts in a row fit and score worse than the best.
"""
function cheapest_in_columns(ship::Ship, columns, in_columns, prices::LayoutPrices,
        assumptions::Assumptions)
    best, lowest, worse = nothing, Inf, 0
    for in_column in in_columns
        rig = design_rig(ship.design, ship.hull, assumptions; columns, in_column)
        isnothing(rig) && continue
        score = layout_score(ship, rig, prices, assumptions)
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
    fixed_rig_port_hours(rig, class, assumptions)

Mean extra time per port call [h] of a `rig` fixed on deck: the cargo-handling delay of
`class`, plus the lost calls of a ship whose air draft in ballast exceeds the class
limit. Inf where a fixed rig prevents cargo handling, as on the reference coaster when
`class` is `nothing` and for units raised above the stacks, which stand in the cranes' way;
zero for kites and ships without a rig, and that of the [`standing_rig`](@ref) for a kite
over a standing rig.
"""
fixed_rig_port_hours(rig, class, assumptions) = 0.0
fixed_rig_port_hours(rig::CombinedRig, class, assumptions) =
    fixed_rig_port_hours(rig.standing, class, assumptions)
fixed_rig_port_hours(::Union{WingRig, RotorRig}, ::Nothing, assumptions) = Inf

function fixed_rig_port_hours(rig::Union{WingRig, RotorRig}, class::ShipClass,
        assumptions)
    raised(rig) && return Inf
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
    mass = unit_mass(rig, assumptions) + pedestal_mass(rig, assumptions) +
           foundation_mass(rig, assumptions)
    return capital, rig.count * mass, annuity
end

"mass [t] of one wing, rotor or suction sail of `rig` with its foundation on deck"
unit_mass(rig::Union{WingRig, RotorRig}, assumptions) =
    assumptions[Symbol(deck_unit(rig), :_mass_per_area)] * size_factor(rig, assumptions) *
    total_area(rig) / rig.count

"""
    unit_loads(rig, assumptions)

Factored loads [N] on each unit of `rig` at its mid height: its [`peak_force`](@ref)
times `rig_wind_load_factor` and its mass in the design acceleration across the ship times
`rig_inertia_load_factor`; and the unit's mass [kg].
"""
function unit_loads(rig, assumptions)
    mass = 1e3unit_mass(rig, assumptions)
    inertia_factor = assumptions[:rig_inertia_load_factor]
    wind = assumptions[:rig_wind_load_factor] * peak_force(rig, assumptions)
    roll = inertia_factor * mass * assumptions[:rig_design_acceleration]
    return (; wind, roll, mass)
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

Wall thickness [m] at which a unit of `mass` [kg], `arm` [m] above the top of a cantilever
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

"mass [kg] per m of height and m of wall thickness of a stiffened box of `perimeter` [m]"
box_wall_mass(perimeter, assumptions) =
    (1 + assumptions[:pedestal_stiffener_share]) * assumptions[:steel_density] * perimeter

"""
    pedestal_mass(rig, assumptions)

Steel mass [t] of the column under each raised unit of `rig`, zero on deck: a stiffened box
`bay_gap` deep along the ship and as wide as the unit, from the deck to the unit's foot, of
the [`pedestal_wall`](@ref) thickness.
"""
function pedestal_mass(rig::Union{WingRig, RotorRig}, assumptions)
    raised(rig) || return 0.0
    perimeter = box_moduli(assumptions[:bay_gap], unit_width(rig)).perimeter
    return 1e-3box_wall_mass(perimeter, assumptions) *
           rig.pedestal_height * pedestal_wall(rig, assumptions)
end

"""
    pedestal_wall(rig, assumptions)

Wall thickness [m] of the column under each raised unit of `rig`, the thickest of two:
the [`steel_wall`](@ref) under its [`deck_stress_load`](@ref); and the
[`sway_wall`](@ref) along the ship, with the unit on top.
"""
function pedestal_wall(rig::Union{WingRig, RotorRig}, assumptions)
    box = foot_box(rig, assumptions)
    bending = assumptions[:bay_gap] * box.along / 2
    return max(steel_wall(deck_stress_load(rig, assumptions), assumptions),
        sway_wall(unit_loads(rig, assumptions).mass, rig.pedestal_height, rig.height / 2,
            bending, box_wall_mass(box.perimeter, assumptions), assumptions))
end

"""
    foot_box(rig, assumptions)

[`box_moduli`](@ref) of the foot of each unit of `rig` at the deck: the column, `bay_gap`
along the ship, under a raised unit, and a square as wide as the unit on deck.
"""
foot_box(rig::Union{WingRig, RotorRig}, assumptions) = box_moduli(
    raised(rig) ? assumptions[:bay_gap] : unit_width(rig), unit_width(rig))

"""
    deck_stress_load(rig, assumptions)

Stress load [N/m] at a corner of the [`foot_box`](@ref) of each unit of `rig` at the deck:
the moments about the unit's mid height of its factored wind force along the ship and roll
across it.
"""
function deck_stress_load(rig::Union{WingRig, RotorRig}, assumptions)
    (; wind, roll) = unit_loads(rig, assumptions)
    box = foot_box(rig, assumptions)
    arm = rig.pedestal_height + rig.height / 2
    return wind * arm / box.along + roll * arm / box.across
end

"""
    foundation_mass(rig, assumptions)

Steel mass [t] of the foundation in the hull under each unit of `rig`: its
[`foot_box`](@ref) carried `hull_foundation_depth` below the deck, of the
[`steel_wall`](@ref) under its [`deck_stress_load`](@ref) times
`hull_foundation_load_factor`.
"""
function foundation_mass(rig::Union{WingRig, RotorRig}, assumptions)
    stress_load = assumptions[:hull_foundation_load_factor] *
                  deck_stress_load(rig, assumptions)
    return 1e-3box_wall_mass(foot_box(rig, assumptions).perimeter, assumptions) *
           assumptions[:hull_foundation_depth] * steel_wall(stress_load, assumptions)
end

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
function kite_rig_mass(rig::KiteRig, assumptions)
    tether = rope_mass(rig.tether_diameter, rig.tether_length, assumptions)
    return sum(kite_deck_masses(rig.area, rig.max_force, assumptions)) +
           kite_mass(rig, assumptions) + tether
end

"mass [kg] of the kite of `rig` without its tether"
kite_mass(rig::KiteRig, assumptions) =
    soft_kite_mass(rig.area, rig.aspect_ratio, rig.max_force, assumptions, rig.airframe)
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
    capital = assumptions[:market_price_factor] * sum(rig_price_parts(rig, assumptions)) +
              rigid_airframe_price(rig, assumptions)
    recovery = capital_recovery(assumptions[:discount_rate], assumptions[:kite_lifetime])
    return capital, 1e-3kite_rig_mass(rig, assumptions), recovery * capital
end

"""
    rig_price_parts(rig, assumptions)

Manufacturing cost [USD] of each part of the hardware of `rig`: the units, their surface,
the supports of raised units, the foundations in the hull and the camera systems of wings
or rotors; the deck system, control unit and ship-side controls of a kite, without its
canopy and tether; the deck system, tether, supply for the hover and ship-side controls of
VTOL kites, without their airframes; each rig with its installation.
"""
rig_price_parts(::Nothing, assumptions) = (;)

rig_price_parts(rig::Union{WingRig, RotorRig}, assumptions) = installed((;
    units=rig.count * assumptions[Symbol(rig isa RotorRig ? :rotor : :wing, :_unit_cost)],
    surface=surface_cost(rig, assumptions) * total_area(rig),
    pedestals=1e3rig.count * pedestal_mass(rig, assumptions) *
              assumptions[:welded_steel_cost_per_mass],
    foundations=1e3rig.count * foundation_mass(rig, assumptions) *
                assumptions[:welded_steel_cost_per_mass],
    cameras=rig.camera_units * assumptions[:camera_system_cost]), assumptions)

"`parts` [USD] of a rig with their installation at the yard, a fraction of their sum"
installed(parts, assumptions) =
    (; parts..., installation=assumptions[:installation_fraction] * sum(parts))

"""
    surface_cost(rig, assumptions)

Manufacturing cost [USD/m^2] of the units of `rig` per m^2, grown by their
[`size_factor`](@ref): rotors at their cost per m^2; wing and suction sails at their mass
per m^2 at the wing sail's cost per kg, with a suction sail's fans at their cost per kW.
"""
surface_cost(rig::RotorRig, assumptions) =
    size_factor(rig, assumptions) * assumptions[:rotor_cost_per_area]

function surface_cost(rig::WingRig, assumptions)
    structure = 1e3assumptions[Symbol(rig.unit, :_mass_per_area)] *
                size_factor(rig, assumptions) * assumptions[:wing_cost_per_mass]
    rig.unit == :suction || return structure
    return structure + 1e-3assumptions[:suction_fan_power_per_area] *
                       assumptions[:suction_fan_cost_per_power]
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
    return installed(parts, assumptions)
end

function rig_price_parts(rig::KiteRig{RigidAirframe}, assumptions)
    parts = (deck=kite_deck_price(rig.area, rig.max_force, assumptions),
        tether=rigid_tether_cost(rig.area, assumptions),
        ship_power=assumptions[:rigid_ship_power_cost] * rig.airframe.hover_power,
        controls=assumptions[:kite_controls_cost])
    return installed(parts, assumptions)
end

"""
    canopy_price(assumptions, area, aspect_ratio, frame=nothing)

Price of the canopy of a soft kite of projected `area` [m^2], projected `aspect_ratio` and
`frame` per m^2 of projected area [USD/m^2]: the cost of its [`kite_canopy`](@ref) times
the market price factor.
"""
canopy_price(assumptions, area, aspect_ratio, frame=nothing) =
    assumptions[:market_price_factor] *
    kite_canopy(assumptions, area, aspect_ratio, frame).cost_per_area

"inputs that together make the canopy's cost"
canopy_price_inputs = (:canopy_structure_cost, :canopy_cloth_base_price,
    :canopy_cloth_price_per_weight)

"""
    consumable_costs(rig, assumptions)

Price of one canopy and one tether [USD]: the canopy at its [`canopy_price`](@ref), the
tether at its purchase price; none for VTOL kites, whose tethers are in their station.
"""
function consumable_costs(rig::KiteRig, assumptions)
    tether_mass = rope_mass(rig.tether_diameter, rig.tether_length, assumptions)
    canopy = canopy_price(assumptions, rig.area, rig.aspect_ratio, rig.airframe) * rig.area
    return canopy, assumptions[:tether_price] * tether_mass
end

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
    rigid_airframe_price(rig, assumptions)

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

"""
    rigid_tether_cost(area, assumptions)

Manufacturing cost [USD] of the electrified tether of a rigid VTOL kite of `area` [m^2]:
that of MX2, grown with the force it holds times its length.
"""
rigid_tether_cost(area, assumptions) = assumptions[:rigid_tether_cost] *
    (area / assumptions[:rigid_reference_area])^1.5

consumable_costs(::KiteRig{RigidAirframe}, assumptions) = (0.0, 0.0)

wear_cost(rig::KiteRig{RigidAirframe}, assumptions) =
    assumptions[:rigid_upkeep_per_area] * rig.area

"""
    cycle_cost(rig::KiteRig{RigidAirframe}, assumptions)

Cost of launching and landing the kite of `rig` once [USD]: crew time and the expected
loss of a kite.
"""
cycle_cost(rig::KiteRig{RigidAirframe}, assumptions) =
    assumptions[:kite_cycle_crew_cost] +
    assumptions[:rigid_cycle_loss_probability] * lost_kite_cost(rig, assumptions)

"""
    lost_kite_cost(rig, assumptions)

Cost of the kite of `rig` lost in the water with its tether and, on a soft kite, its
control unit, at market prices [USD].
"""
function lost_kite_cost(rig::KiteRig, assumptions)
    canopy, tether = consumable_costs(rig, assumptions)
    control_unit = rig_price_parts(rig, assumptions).control_unit
    return canopy + tether + assumptions[:market_price_factor] * control_unit
end

lost_kite_cost(rig::KiteRig{RigidAirframe}, assumptions) =
    rigid_airframe_price(rig, assumptions)

"""
    crash_cost(rig, assumptions)

Cost [USD] of one kite, wing or rotor lost, beyond the wear already charged:
a kite's control unit or airframe and half of its canopy and tether, on average halfway
through their life when lost, or the price of one wing or rotor with its installation.
"""
crash_cost(rig::KiteRig, assumptions) =
    lost_kite_cost(rig, assumptions) - sum(consumable_costs(rig, assumptions)) / 2

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
    turnaround_hours(ship, outbound, assumptions)

Hours [h] from the departure of a round trip of `ship` to that of its return: the
`outbound` passage at the service speed and one port call, whatever the outbound takes.
"""
turnaround_hours(ship::Ship, outbound, assumptions::Assumptions) =
    outbound.track_length / service_speed(ship, assumptions) / 3600 +
    24assumptions[:port_time_per_call]

"""
    route_round_trip(table, outbound, inbound, weather, departure, turnaround, hourly,
                     forecast; schedule=(Inf, Inf))

Outbound and return [`Leg`](@ref) of [`forecast_route`](@ref) on the [`RouteTable`](@ref)
`table` for one departure, the return leaving `turnaround` [h] after it, at the outbound
and return time costs `hourly` [USD/h], each arriving by its time [h] in `schedule`, or
`nothing` if either fails, planned on `forecast`, or on the real weather where that is
`nothing`.
"""
function route_round_trip(table, outbound, inbound, weather, departure, turnaround, hourly,
        forecast; schedule=(Inf, Inf))
    out = forecast_route(outbound, table, weather, departure; time_cost=first(hourly),
        arrival_by=first(schedule), forecast)
    isnothing(out) && return nothing
    back = forecast_route(inbound, table, weather, departure + turnaround;
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
    StateRouting(ship, outbound, assumptions, hourly, held_knots)

What routing `ship` in one service state takes: its [`RouteTable`](@ref), holding
`held_knots` [kn] by [`held_speed_table`](@ref) or choosing speed where `nothing`, the
outbound and return time costs `hourly` [USD/h], and the [`turnaround_hours`](@ref) on
`outbound`.
"""
struct StateRouting{T}
    "route table of the ship in this state"
    table::T
    "outbound and return time costs [USD/h]"
    hourly::Tuple{Float64, Float64}
    "hours from a departure to that of its return [h]"
    turnaround::Float64
end

function StateRouting(ship::Ship, outbound, assumptions, hourly, held_knots)
    table = PerformanceTable(ship, assumptions)
    route_table = isnothing(held_knots) ? RouteTable(table) :
                  held_speed_table(table, held_knots)
    return StateRouting(route_table, Tuple(hourly),
        turnaround_hours(ship, outbound, assumptions))
end

"""
    state_passages(routing, outbound, inbound, weather, departure, forecast;
                   schedule=(Inf, Inf))

[`Passages`](@ref) of the round trip from `departure` [h] routed by the
[`StateRouting`](@ref) `routing`, arriving by the times [h] of `schedule`, its largest leg
that of this departure; `nothing` if a passage is infeasible.
"""
function state_passages(routing::StateRouting, outbound, inbound, weather, departure,
        forecast; schedule=(Inf, Inf))
    legs = route_round_trip(routing.table, outbound, inbound, weather, departure,
        routing.turnaround, routing.hourly, forecast; schedule)
    isnothing(legs) && return nothing
    out, back = legs
    return Passages(out.fuel_energy + back.fuel_energy, out.duration, back.duration,
        out.flight_hours + back.flight_hours, out.launches + back.launches,
        out.forced_landings + back.forced_landings, max(out.fuel_energy, back.fuel_energy))
end

"""
    DepartureRouting(ship, outbound, assumptions; held_knots=nothing)

What routing one departure of `ship` out along `outbound` takes: the [`StateRouting`](@ref)
of each of its [`service_states`](@ref) with a share, `nothing` for the others, and where it
keeps a liner schedule ([`keeps_schedule`](@ref)) that of the ship without its rig, routed
for cost, whose times it keeps. The router holds `held_knots` [kn], or chooses speed where
`nothing`, and prices time at the hold's cargo before the fuel store.
"""
struct DepartureRouting
    "routing of each service state, `nothing` for a state without a share"
    states::Vector{Union{Nothing, StateRouting}}
    "routing of the ship without its rig whose times it keeps, or `nothing`"
    schedule::Union{Nothing, StateRouting}
end

function DepartureRouting(ship::Ship, outbound, assumptions; held_knots=nothing)
    hourly = leg_time_costs(first(ship_costs(ship, assumptions)), assumptions)
    router_hourly = isnothing(held_knots) ? hourly : HELD_SPEED_TIME_FACTOR .* hourly
    states = Union{Nothing, StateRouting}[
        share > 0 ? StateRouting(with_rig(ship, rig), outbound, assumptions, router_hourly,
            held_knots) : nothing
        for (share, rig) in service_states(ship.rig, assumptions)]
    isnothing(held_knots) && keeps_schedule(ship) ||
        return DepartureRouting(states, nothing)
    bare = with_rig(ship, nothing)
    bare_hourly = leg_time_costs(ShipCosts(bare, assumptions), assumptions)
    return DepartureRouting(states,
        StateRouting(bare, outbound, assumptions, bare_hourly, nothing))
end

"""
    departure_passages(routing, outbound, inbound, weather, departure; forecast=nothing)

[`Passages`](@ref) of the round trip from `departure` [h] in each service state of the
[`DepartureRouting`](@ref) `routing`, `nothing` for a state it does not route, keeping its
liner schedule where it has one; `nothing` if any passage is infeasible. With a
[`ForecastArchive`](@ref) `forecast` the router re-plans daily on its forecasts.
"""
function departure_passages(routing::DepartureRouting, outbound, inbound, weather,
        departure; forecast=nothing)
    schedule = (Inf, Inf)
    if !isnothing(routing.schedule)
        kept = state_passages(routing.schedule, outbound, inbound, weather, departure,
            forecast)
        isnothing(kept) && return nothing
        schedule = (kept.out_hours, kept.back_hours)
    end
    passages = Union{Nothing, Passages}[]
    for state in routing.states
        isnothing(state) && (push!(passages, nothing); continue)
        passage = state_passages(state, outbound, inbound, weather, departure, forecast;
            schedule)
        isnothing(passage) && return nothing
        push!(passages, passage)
    end
    return passages
end

"""
    state_departures(departed, state)

[`Passages`](@ref) of service state `state` on each departure of `departed`
([`departure_passages`](@ref)), each holding the largest leg over all of them; `nothing`
where that state is not routed.
"""
function state_departures(departed, state)
    passages = [passages[state] for passages in departed]
    isnothing(first(passages)) && return nothing
    largest_leg = maximum(passage.largest_leg for passage in passages)
    return [Passages(passage.energy, passage.out_hours, passage.back_hours,
                passage.flight_hours, passage.launches, passage.forced_landings,
                largest_leg) for passage in passages]
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

Route `ship` out along `outbound` and back along `inbound`, leaving a fixed
[`turnaround_hours`](@ref) after the outbound, for each departure time [h] in each of its
[`service_states`](@ref) with a share ([`departure_passages`](@ref)), and turn the result
averaged over the departures and the states into the cost per tonne-km of the transport
service ([`combine_departures`](@ref)). With a [`ForecastArchive`](@ref) `forecast` the
router re-plans daily on its forecasts, and with `held_knots` [kn] the ship holds that
speed instead of choosing by cost. A ship of a liner class keeps the schedule of the same
ship without its rig where it chooses its speed. Returns `nothing` if any passage is
infeasible or the fuel store leaves no cargo.
"""
function round_trip(ship::Ship, outbound::Corridor, inbound::Corridor, weather,
        departures, assumptions::Assumptions; forecast=nothing, held_knots=nothing)
    routing = DepartureRouting(ship, outbound, assumptions; held_knots)
    departed = fetch.([Threads.@spawn departure_passages(routing, outbound, inbound,
                           weather, departure; forecast) for departure in departures])
    return combine_departures(ship, outbound, inbound, departures, assumptions, departed)
end

"""
    combine_departures(ship, outbound, inbound, departures, assumptions, departed)

[`RoundTrip`](@ref) of `ship` from the [`departure_passages`](@ref) `departed` of each of
`departures` [h]: the cost per tonne-km of the transport service by
[`voyage_costs`](@ref), averaged over the departures and the service states, and that of
each departure with the same ship by [`departure_outcome`](@ref). Wings and rotors are
fixed or retractable, whichever costs less. Returns `nothing` if any departure is
infeasible or the fuel store leaves no cargo.
"""
function combine_departures(ship::Ship, outbound::Corridor, inbound::Corridor, departures,
        assumptions::Assumptions, departed)
    any(isnothing, departed) && return nothing
    costs = ship_costs(ship, assumptions)
    states = service_states(ship.rig, assumptions)
    services = [state_departures(departed, state) for state in eachindex(states)]
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
    departure_outcome(ship, costs, states, services, k, departure, retractable, outbound,
                      inbound, assumptions)

[`DepartureOutcome`](@ref) of the `k`th of the departures, at `departure` [h], of `ship`
with the [`ship_costs`](@ref) `costs` and its [`service_states`](@ref) `states`, from the
[`state_departures`](@ref) `services` of each state, `nothing` where not routed; with the
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
