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
unit capacity less the slots the rig blocks; the reference coaster family fills its
deadweight.
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
    fixed_rig_port_hours(rig, class, assumptions)

Mean extra time per port call [h] of a `rig` fixed on deck: the cargo-handling delay of
`class`, plus the lost calls of a ship whose air draft in ballast exceeds the class
limit. Inf where a fixed rig prevents cargo handling, as on the reference coaster when
`class` is `nothing`; zero for kites and ships without a rig, and that of the
[`standing_rig`](@ref) for a kite over a standing rig.
"""
fixed_rig_port_hours(rig, class, assumptions) = 0.0
fixed_rig_port_hours(rig::CombinedRig, class, assumptions) =
    fixed_rig_port_hours(rig.standing, class, assumptions)
fixed_rig_port_hours(::Union{WingRig, RotorRig}, ::Nothing, assumptions) = Inf

function fixed_rig_port_hours(rig::Union{WingRig, RotorRig}, class::ShipClass,
        assumptions)
    ballast_rise = (1 - assumptions[:ballast_draft_fraction]) * class.draft
    air_draft = rig.foot_height + rig.height + ballast_rise
    air_draft > class.air_draft_limit || return class.fixed_rig_port_hours
    return class.fixed_rig_port_hours + 24class.restricted_call_share *
                                         assumptions[:restricted_call_days]
end

"""
    blocked_slots(rig, class, assumptions)

TEU slots that a rig takes from the deck of a container ship: every wing, rotor or kite
mast blocks the on-deck stack of the rows it covers over one 40 ft bay, all tiers up,
while the holds below stay in use; a kite over a standing rig blocks both.
"""
function blocked_slots(rig, class::ShipClass, assumptions)
    footprint = deck_footprint(rig, assumptions)
    rows = ceil((footprint + assumptions[:deck_rig_clearance]) /
                assumptions[:container_row_pitch])
    return deck_units(rig) * bay_slots(rows, class)
end

"TEU slots in `rows` rows of the deck stack of `class` over one 40 ft bay, all tiers up"
bay_slots(rows, class::ShipClass) = 2rows * class.deck_tiers

blocked_slots(rig::CombinedRig, class::ShipClass, assumptions) =
    blocked_slots(rig.kite, class, assumptions) +
    blocked_slots(rig.standing, class, assumptions)

deck_footprint(rig::RotorRig, assumptions) = rig.diameter
deck_footprint(::WingRig, assumptions) = assumptions[:wing_pedestal_width]
deck_footprint(::KiteRig, assumptions) = assumptions[:launch_mast_width]
deck_footprint(::KiteRig{RigidAirframe}, assumptions) = assumptions[:rigid_perch_width]
deck_units(rig::Union{WingRig, RotorRig}) = rig.count
deck_units(rig::KiteRig) = kite_count(rig)
deck_units(rig::CombinedRig) = deck_units(rig.kite) + deck_units(rig.standing)
deck_footprint(::Nothing, assumptions) = 0.0
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

rig_costs(rig::WingRig, assumptions) =
    deck_rig_costs(rig, assumptions, :wing_lifetime, :wing_mass_per_area)
rig_costs(rig::RotorRig, assumptions) =
    deck_rig_costs(rig, assumptions, :rotor_lifetime, :rotor_mass_per_area)

"""
    deck_rig_costs(rig, assumptions, lifetime, mass_per_area)

[`rig_costs`](@ref) of wings or rotors, with the names of their assumptions.
"""
function deck_rig_costs(rig, assumptions, lifetime, mass_per_area)
    capital = assumptions[:market_price_factor] * sum(rig_price_parts(rig, assumptions))
    annuity = capital_recovery(assumptions[:discount_rate], assumptions[lifetime]) * capital
    return capital, assumptions[mass_per_area] * total_area(rig), annuity
end

function rig_costs(rig::KiteRig, assumptions)
    canopy, tether = consumable_costs(rig, assumptions)
    hardware = assumptions[:market_price_factor] * sum(rig_price_parts(rig, assumptions))
    annuity = capital_recovery(assumptions[:discount_rate], assumptions[:kite_lifetime]) *
              hardware
    return hardware + canopy + tether, assumptions[:kite_mass_per_area] * rig.area, annuity
end

function rig_costs(rig::KiteRig{RigidAirframe}, assumptions)
    _, tether = consumable_costs(rig, assumptions)
    (; count, mass) = rig.airframe
    ship_side = assumptions[:market_price_factor] * sum(rig_price_parts(rig, assumptions))
    airframe = rigid_airframe_price(rig, assumptions)
    recovery = capital_recovery(assumptions[:discount_rate], assumptions[:rigid_lifetime])
    tonnes = count * (assumptions[:rigid_station_mass] + 1e-3 * mass)
    return ship_side + airframe + tether, tonnes, recovery * (ship_side + airframe)
end

"""
    rig_price_parts(rig, assumptions)

Price [USD] of each part of the hardware of `rig` at a market price factor of one: the
units, their surface and the installation of wings or rotors; the winch, launch mast,
docking head, control unit and integration of a kite, without its canopy and tether.
"""
rig_price_parts(::Nothing, assumptions) = (;)

rig_price_parts(rig::WingRig, assumptions) = deck_price_parts(rig, assumptions,
    :wing_unit_cost, :wing_cost_per_area, :wing_installation_fraction)
rig_price_parts(rig::RotorRig, assumptions) = deck_price_parts(rig, assumptions,
    :rotor_unit_cost, :rotor_cost_per_area, :rotor_installation_fraction)

"""
    deck_price_parts(rig, assumptions, unit_cost, cost_per_area, fraction)

[`rig_price_parts`](@ref) of wings or rotors, with the names of their assumptions.
"""
function deck_price_parts(rig, assumptions, unit_cost, cost_per_area, fraction)
    units = rig.count * assumptions[unit_cost]
    surface = assumptions[cost_per_area] * total_area(rig)
    return (; units, surface, installation=assumptions[fraction] * (units + surface))
end

"""
    launch_mast_height(area, assumptions)

Height [m] of the launch mast of a kite of projected `area` [m^2].
"""
launch_mast_height(area, assumptions) = min(
    assumptions[:launch_mast_height_ratio] * sqrt(area),
    assumptions[:launch_mast_max_height])

function rig_price_parts(rig::KiteRig, assumptions)
    mast_height = launch_mast_height(rig.area, assumptions)
    mast_mass = 1e3 * (assumptions[:launch_mast_base_mass] +
                 assumptions[:launch_mast_mass_coefficient] * rig.area^(2 / 3) *
                 mast_height^(5 / 3))
    parts = (winch=assumptions[:winch_fixed_cost] +
                   assumptions[:winch_cost_per_force] * rig.max_force,
        mast=assumptions[:launch_mast_steel_cost] *
             assumptions[:launch_mast_telescope_factor] * mast_mass,
        docking_head=assumptions[:docking_head_cost] *
                     (rig.area / assumptions[:docking_head_reference_area])^
                     assumptions[:docking_head_area_exponent],
        control_unit=assumptions[:control_unit_cost] +
                     assumptions[:control_unit_cost_per_area] * rig.area)
    return (; parts..., integration=assumptions[:kite_integration_fraction] * sum(parts))
end

function rig_price_parts(rig::KiteRig{RigidAirframe}, assumptions)
    (; count, hover_power) = rig.airframe
    parts = (winch=count * (assumptions[:winch_fixed_cost] +
                  assumptions[:winch_cost_per_force] * rig.max_force),
        perch=count * assumptions[:rigid_perch_cost],
        ship_power=count * assumptions[:rigid_ship_power_cost] * hover_power)
    return (; parts..., integration=assumptions[:kite_integration_fraction] * sum(parts))
end

"""
    canopy_price(assumptions)

Price of a canopy per m^2 of projected area [USD/m^2]: its manufacturing cost times the
market price factor.
"""
canopy_price(assumptions) = assumptions[:market_price_factor] *
                            Canopy(assumptions).cost_per_area

"inputs that together make the canopy price, the goal's; each has a `_today` counterpart"
canopy_price_inputs = (:canopy_making_cost_per_area, :canopy_cloth_base_price,
    :canopy_cloth_price_per_weight)

"""
    canopy_price_today(assumptions)

[`canopy_price`](@ref) [USD/m^2] of the canopy as built today, from the `_today` inputs.
"""
canopy_price_today(assumptions) = canopy_price(with_today(assumptions,
    canopy_price_inputs))

"""
    with_today(assumptions, names)

Fresh `Assumptions` with each of `names` set to the value of its `_today` counterpart.
"""
with_today(assumptions, names) = reduce(
    (inputs, name) -> with_value(inputs, name, assumptions[Symbol(name, :_today)]),
    names; init=assumptions)

"""
    consumable_costs(rig, assumptions)

Price of one canopy and one tether [USD]: the canopy at its manufacturing cost times the
market price factor, the tether at its purchase price.
"""
function consumable_costs(rig::KiteRig, assumptions)
    tether_mass = rope_mass(rig.tether_diameter, rig.tether_length, assumptions)
    return canopy_price(assumptions) * rig.area, assumptions[:tether_price] * tether_mass
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
    worn_part_price(rig, assumptions) + rigid_airframe_price(rig, assumptions)

"""
    wear_cost(rig, assumptions)

Canopy wear and tether creep per hour the rig is flown [USD/h]; zero for rigs that do not
wear.
"""
wear_cost(rig, assumptions) = 0.0
wear_cost(rig::CombinedRig, assumptions) = wear_cost(rig.kite, assumptions)

function wear_cost(rig::KiteRig, assumptions)
    canopy, tether = consumable_costs(rig, assumptions)
    return canopy / Canopy(assumptions).lifetime + tether / assumptions[:tether_lifetime]
end

"""
    base_aspect_ratio_prices(assumptions, aspect_ratio_factor)

`assumptions` with the tether, the only priced part that follows span, cheaper per kg so
that a kite of `aspect_ratio_factor` times the base aspect ratio pays what the base pays.
"""
base_aspect_ratio_prices(assumptions::Assumptions, aspect_ratio_factor) =
    with_value(assumptions, :tether_price,
        assumptions[:tether_price] / sqrt(aspect_ratio_factor))

"""
    cycle_cost(rig, assumptions)

Cost of one launch and landing of a kite [USD]: per launch attempt the crew time, the
expected canopy torn beyond repair and the expected loss at sea of canopy, tether and
control unit, plus any turn for the launch and the [`tether_bending_cost`](@ref); zero for
other rigs.
"""
cycle_cost(rig, assumptions) = 0.0
cycle_cost(rig::CombinedRig, assumptions) = cycle_cost(rig.kite, assumptions)

function cycle_cost(rig::KiteRig, assumptions)
    canopy, tether = consumable_costs(rig, assumptions)
    attempt = assumptions[:kite_cycle_crew_cost] +
              assumptions[:kite_cycle_damage_probability] * canopy +
              assumptions[:kite_cycle_loss_probability] * lost_kite_cost(rig, assumptions)
    return (1 + assumptions[:kite_launch_retry_probability]) * attempt +
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

Market price of the kites of `rig` alone: structure by mass and area, avionics and
on-board drive [USD].
"""
function rigid_airframe_price(rig::KiteRig{RigidAirframe}, assumptions)
    (; count, mass, hover_power) = rig.airframe
    one = assumptions[:rigid_structure_cost_per_mass] * mass +
          assumptions[:rigid_structure_cost_per_area] * rig.area +
          assumptions[:rigid_avionics_cost] +
          assumptions[:rigid_drive_cost] * assumptions[:rigid_drive_margin] * hover_power
    return assumptions[:market_price_factor] * count * one
end

function consumable_costs(rig::KiteRig{RigidAirframe}, assumptions)
    (; count, tether_mass) = rig.airframe
    return 0.0, count * assumptions[:rigid_tether_price] * tether_mass
end

function wear_cost(rig::KiteRig{RigidAirframe}, assumptions)
    _, tether = consumable_costs(rig, assumptions)
    upkeep = assumptions[:rigid_upkeep_per_area] * rig.area * rig.airframe.count
    return tether / assumptions[:tether_lifetime] + upkeep
end

"""
    cycle_cost(rig::KiteRig{RigidAirframe}, assumptions)

Cost of launching and landing all kites of `rig` once [USD]: crew time, the expected loss
of a kite, the energy of the hover and the [`tether_bending_cost`](@ref) of their tethers.
"""
function cycle_cost(rig::KiteRig{RigidAirframe}, assumptions)
    (; count, hover_power) = rig.airframe
    energy = hover_power * assumptions[:rigid_hover_minutes] / 60 / 1e3
    _, tethers = consumable_costs(rig, assumptions)
    return count * (assumptions[:kite_cycle_crew_cost] +
            assumptions[:rigid_hover_energy_price] * energy) +
           assumptions[:rigid_cycle_loss_probability] * lost_kite_cost(rig, assumptions) +
           tether_bending_cost(tethers, assumptions)
end

"""
    lost_kite_cost(rig, assumptions)

Cost of the kites of `rig` lost in the water with their tethers and, on a soft kite, its
control unit, at market prices [USD].
"""
function lost_kite_cost(rig::KiteRig, assumptions)
    canopy, tether = consumable_costs(rig, assumptions)
    control_unit = rig_price_parts(rig, assumptions).control_unit
    return canopy + tether + assumptions[:market_price_factor] * control_unit
end

lost_kite_cost(rig::KiteRig{RigidAirframe}, assumptions) =
    rigid_airframe_price(rig, assumptions) + last(consumable_costs(rig, assumptions))

"""
    crash_cost(rig, assumptions)

Cost [USD] of one kite crashed or one wing or rotor lost, beyond the wear already charged:
a kite's control unit or airframe and half of its canopy and tether, on average halfway
through their life when lost, or the price of one wing or rotor with its installation.
"""
crash_cost(rig::KiteRig, assumptions) =
    (lost_kite_cost(rig, assumptions) - sum(consumable_costs(rig, assumptions)) / 2) /
    kite_count(rig)

crash_cost(rig::Union{WingRig, RotorRig}, assumptions) =
    first(rig_costs(rig, assumptions)) / deck_units(rig)

"""
    forced_landing_cost(rig, assumptions)

Expected cost of the kites of `rig` landing once outside the landing limits [USD], the
chance of losing them then times their cost; zero for other rigs.
"""
forced_landing_cost(rig, assumptions) = 0.0
forced_landing_cost(rig::CombinedRig, assumptions) =
    forced_landing_cost(rig.kite, assumptions)
forced_landing_cost(rig::KiteRig, assumptions) =
    assumptions[:kite_forced_landing_loss_probability] * lost_kite_cost(rig, assumptions)

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
                     horizon, forecast)

Outbound and return [`Leg`](@ref) on the [`RouteTable`](@ref) `table` for one departure
at the outbound and return time costs `hourly` [USD/h], or `nothing` if either fails;
with a finite forecast `horizon` [h] or a [`ForecastArchive`](@ref) `forecast` the ship
re-plans daily by [`forecast_route`](@ref).
"""
function route_round_trip(table, outbound, inbound, weather, departure, port_hours, hourly,
        horizon, forecast)
    out = sail(outbound, table, weather, departure, first(hourly), horizon, forecast)
    isnothing(out) && return nothing
    back = sail(inbound, table, weather, departure + out.duration + port_hours,
        last(hourly), horizon, forecast)
    isnothing(back) && return nothing
    return out, back
end

sail(corridor, table, weather, departure, hourly, horizon, forecast) =
    isfinite(horizon) || !isnothing(forecast) ?
    forecast_route(corridor, table, weather, departure; time_cost=hourly, horizon,
        forecast) : route(corridor, table, weather, departure; time_cost=hourly)

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
out_of_service_share(::WingRig, assumptions) = assumptions[:wing_out_of_service]
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

function down_rig(rig::KiteRig{RigidAirframe}, working_share)
    deck_units(rig) > 1 || return nothing
    (; count, mass, tether_mass, hover_power, loop_area) = rig.airframe
    airframe = RigidAirframe(working_share * count, mass, tether_mass, hover_power,
        loop_area)
    parts = (getfield(rig, name) for name in fieldnames(KiteRig) if name != :airframe)
    return KiteRig(parts..., airframe)
end

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
                     port_hours, horizon, forecast, held_knots)

[`Passages`](@ref) of `ship` on the round trip of each of `departures`; `nothing` if any
passage is infeasible. The router holds `held_knots` [kn] by [`held_speed_table`](@ref),
or chooses speed where `nothing`.
"""
function service_passages(ship::Ship, outbound, inbound, weather, departures, assumptions,
        hourly, port_hours, horizon, forecast, held_knots)
    table = PerformanceTable(ship, assumptions)
    route_table = isnothing(held_knots) ? RouteTable(table) :
                  held_speed_table(table, held_knots)
    legs = fetch.([Threads.@spawn route_round_trip(route_table, outbound, inbound, weather,
                       departure, port_hours, hourly, horizon, forecast)
                   for departure in departures])
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

Wear, launches and forced landings of `rig` over the round trip of `passage` [USD].
"""
rig_running_cost(rig, passage::Passages, assumptions) =
    wear_cost(rig, assumptions) * passage.flight_hours +
    cycle_cost(rig, assumptions) * passage.launches +
    forced_landing_cost(rig, assumptions) * passage.forced_landings

"""
    yearly_crash_cost(rig, assumptions)

Expected cost of crashed kites and lost wings or rotors of `rig` per year [USD/year], at
the crash rate of each unit.
"""
yearly_crash_cost(rig, assumptions) = 0.0
yearly_crash_cost(rig::CombinedRig, assumptions) =
    yearly_crash_cost(rig.kite, assumptions) + yearly_crash_cost(rig.standing, assumptions)
yearly_crash_cost(rig::Union{KiteRig, WingRig, RotorRig}, assumptions) =
    crash_rate(rig, assumptions) * deck_units(rig) * crash_cost(rig, assumptions)

crash_rate(::KiteRig, assumptions) = assumptions[:kite_crash_rate]
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
                   Drive(ship.design.drive, assumptions).fuel.price + rig_cost +
                   port_costs(ship.hull, assumptions) +
                   store_round_trip_cost(store.price, round_trip_hours, assumptions) +
                   yearly_crash_cost(ship.rig, assumptions) * round_trip_hours /
                   (8760assumptions[:availability])
    delay = fixed_rig_port_hours(ship.rig, ship.design.class, assumptions)
    tonne_km = cargo * (track_length(outbound) +
                        assumptions[:backhaul_fraction] * track_length(inbound)) / 1e3
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
    round_trip(ship, outbound, inbound, weather, departures, assumptions; horizon=Inf,
               forecast=nothing, held_knots=nothing)

Route `ship` out along `outbound` and back along `inbound` for each departure time
[h] in each of its [`service_states`](@ref) with a share, and turn the result averaged
over the departures and the states into the cost per tonne-km of the transport service
by [`voyage_costs`](@ref), and that of each departure with the same ship by
[`departure_outcome`](@ref). With a finite forecast `horizon` [h] the router knows the
weather only that far ahead, with a [`ForecastArchive`](@ref) `forecast` it re-plans daily
on its forecasts, and with `held_knots` [kn] the ship holds that speed instead of choosing
by cost. Wings and rotors are fixed or retractable, whichever costs less. The router
prices time at the hold's cargo before the fuel store. Returns `nothing` if any passage
is infeasible or the fuel store leaves no cargo.
"""
function round_trip(ship::Ship, outbound, inbound, weather, departures,
        assumptions::Assumptions; horizon=Inf, forecast=nothing, held_knots=nothing)
    port_hours = 24assumptions[:port_time_per_call]
    costs = ship_costs(ship, assumptions)
    hourly = leg_time_costs(first(costs), assumptions)
    router_hourly = isnothing(held_knots) ? hourly : HELD_SPEED_TIME_FACTOR .* hourly
    states = service_states(ship.rig, assumptions)
    services = [share > 0 ?
                service_passages(with_rig(ship, rig), outbound, inbound, weather,
                    departures, assumptions, router_hourly, port_hours, horizon,
                    forecast, held_knots) : nothing
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
