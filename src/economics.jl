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
    cargo_mass(hold, store_mass=0, store_volume=0)

Cargo [t] that `hold` carries with a fuel store of `store_mass` [t] and `store_volume`
[m^3] taken from it: the deadweight or the units left, whichever is less.
"""
function cargo_mass(hold::CargoHold, store_mass=0.0, store_volume=0.0)
    units = min((hold.payload - store_mass) / hold.unit.mass,
        hold.slots - store_volume / hold.unit.volume)
    return units * hold.unit.cargo
end

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
struct ShipCosts
    "capital cost [USD]"
    capital::Float64
    "annuity, crew and maintenance [USD/year]"
    fixed_annual::Float64
    hold::CargoHold
    "value of the cargo [USD/t]"
    cargo_value::Float64
end

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
                   assumptions[:maintenance_fraction] *
                   (capital - worn_part_price(ship.rig, assumptions))
    cargo_value = isnothing(class) ? assumptions[:cargo_value] : class.cargo_value
    return ShipCosts(capital, fixed_annual, hold, cargo_value)
end

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
    return deck_units(rig) * 2rows * class.deck_tiers
end

blocked_slots(rig::CombinedRig, class::ShipClass, assumptions) =
    blocked_slots(rig.kite, class, assumptions) +
    blocked_slots(rig.standing, class, assumptions)

deck_footprint(rig::RotorRig, assumptions) = rig.diameter
deck_footprint(::WingRig, assumptions) = assumptions[:wing_pedestal_width]
deck_footprint(::KiteRig, assumptions) = assumptions[:launch_mast_width]
deck_units(rig::Union{WingRig, RotorRig}) = rig.count
deck_units(::KiteRig) = 1
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
canopy_price_today(assumptions) = canopy_price(reduce(
    (inputs, name) -> with_value(inputs, name, assumptions[Symbol(name, :_today)]),
    canopy_price_inputs; init=assumptions))

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
    wear_cost(rig, assumptions)

Canopy and tether wear per hour the rig is flown [USD/h]; zero for rigs that do not wear.
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
control unit, plus any turn for the launch; zero for other rigs.
"""
cycle_cost(rig, assumptions) = 0.0
cycle_cost(rig::CombinedRig, assumptions) = cycle_cost(rig.kite, assumptions)

function cycle_cost(rig::KiteRig, assumptions)
    canopy, _ = consumable_costs(rig, assumptions)
    attempt = assumptions[:kite_cycle_crew_cost] +
              assumptions[:kite_cycle_damage_probability] * canopy +
              assumptions[:kite_cycle_loss_probability] * lost_kite_cost(rig, assumptions)
    return (1 + assumptions[:kite_launch_retry_probability]) * attempt +
           assumptions[:kite_cycle_course_cost]
end

"""
    lost_kite_cost(rig, assumptions)

Cost of a kite lost in the water with its tether and control unit [USD], at market prices.
"""
function lost_kite_cost(rig::KiteRig, assumptions)
    canopy, tether = consumable_costs(rig, assumptions)
    control_unit = rig_price_parts(rig, assumptions).control_unit
    return canopy + tether + assumptions[:market_price_factor] * control_unit
end

"""
    crash_cost(rig, assumptions)

Cost [USD] of one kite crashed or one wing or rotor lost, beyond the wear already charged:
a kite's control unit and half of its canopy and tether, on average halfway through their
life when lost, or the price of one wing or rotor with its installation.
"""
function crash_cost(rig::KiteRig, assumptions)
    canopy, tether = consumable_costs(rig, assumptions)
    return lost_kite_cost(rig, assumptions) - (canopy + tether) / 2
end

crash_cost(rig::Union{WingRig, RotorRig}, assumptions) =
    first(rig_costs(rig, assumptions)) / deck_units(rig)

"""
    forced_landing_cost(rig, assumptions)

Expected cost of one kite landing outside the landing limits [USD], the chance of losing
the kite then times its cost; zero for other rigs.
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
end

"""
    route_round_trip(table, outbound, inbound, weather, departure, port_hours, hourly,
                     horizon)

Outbound and return [`Leg`](@ref) on the [`RouteTable`](@ref) `table` for one departure
at the outbound and return time costs `hourly` [USD/h], or `nothing` if either fails;
with a finite forecast `horizon` [h] the ship re-plans daily by
[`forecast_route`](@ref).
"""
function route_round_trip(table, outbound, inbound, weather, departure, port_hours, hourly,
        horizon)
    out = sail(outbound, table, weather, departure, first(hourly), horizon)
    isnothing(out) && return nothing
    back = sail(inbound, table, weather, departure + out.duration + port_hours,
        last(hourly), horizon)
    isnothing(back) && return nothing
    return out, back
end

sail(corridor, table, weather, departure, hourly, horizon) = isfinite(horizon) ?
    forecast_route(corridor, table, weather, departure; time_cost=hourly, horizon) :
    route(corridor, table, weather, departure; time_cost=hourly)

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
    unit_outage(rig, assumptions)

Share of the round trips with any of the units of `rig` out of service [-], each out for
the share given by its input and independent of the others, and the mean share of the
units still working on those trips [-].
"""
function unit_outage(rig, assumptions)
    share = out_of_service_share(rig, assumptions)
    any_down = 1 - (1 - share)^deck_units(rig)
    return any_down, any_down > 0 ? 1 - share / any_down : 1.0
end

down_rig(rig::Union{WingRig, RotorRig}, working_share) = DownRig(rig, working_share)
down_rig(::KiteRig, working_share) = nothing

"""
    service_states(rig, assumptions)

What of `rig` works over a year as (share of the round trips, rig) pairs, the working rig
first, leaving out states with no share. Trips with a unit down hold the mean of the units
working, so the rig keeps its mean capacity. A kite out of service is stowed, wings or
rotors stand as a [`DownRig`](@ref), and each part of a [`CombinedRig`](@ref) fails on its
own.
"""
function service_states(rig, assumptions)
    any_down, working_share = unit_outage(rig, assumptions)
    return with_share([(1 - any_down, rig), (any_down, down_rig(rig, working_share))])
end

service_states(::Nothing, assumptions) = [(1.0, nothing)]

function service_states(rig::CombinedRig, assumptions)
    kite = out_of_service_share(rig.kite, assumptions)
    any_down, working_share = unit_outage(rig.standing, assumptions)
    down = DownRig(rig.standing, working_share)
    return with_share([((1 - kite) * (1 - any_down), rig),
        (kite * (1 - any_down), rig.standing),
        ((1 - kite) * any_down, CombinedRig(rig.kite, down)), (kite * any_down, down)])
end

with_share(states) = filter(state -> first(state) > 0, states)

"""
    service_passages(ship, outbound, inbound, weather, departures, assumptions, hourly,
                     port_hours, horizon)

Mean fuel energy [J], outbound and return hours, kite flight hours, launches, forced
landings and rig running cost [USD] of `ship` per round trip over `departures`,
with the largest leg's fuel energy [J]; `nothing` if any passage is infeasible.
"""
function service_passages(ship::Ship, outbound, inbound, weather, departures, assumptions,
        hourly, port_hours, horizon)
    table = PerformanceTable(ship, assumptions)
    route_table = RouteTable(table)
    legs = fetch.([Threads.@spawn route_round_trip(route_table, outbound, inbound, weather,
                       departure, port_hours, hourly, horizon) for departure in departures])
    any(isnothing, legs) && return nothing
    flight_hours = mean(first(pair).flight_hours + last(pair).flight_hours for pair in legs)
    launches = mean(first(pair).launches + last(pair).launches for pair in legs)
    forced_landings = mean(first(pair).forced_landings + last(pair).forced_landings
                           for pair in legs)
    means = (energy=mean(first(pair).fuel_energy + last(pair).fuel_energy for pair in legs),
        out_hours=mean(first(pair).duration for pair in legs),
        back_hours=mean(last(pair).duration for pair in legs),
        flight_hours, launches, forced_landings,
        rig_cost=table.wear_cost * flight_hours + table.cycle_cost * launches +
                 table.forced_landing_cost * forced_landings)
    largest_leg = maximum(max(first(pair).fuel_energy, last(pair).fuel_energy)
                          for pair in legs)
    return (; means, largest_leg)
end

"""
    round_trip(ship, outbound, inbound, weather, departures, assumptions; horizon=Inf)

Route `ship` out along `outbound` and back along `inbound` for each departure time
[h] in each of its [`service_states`](@ref), and turn the result averaged over the
departures and the states into the cost per tonne-km of the transport service. With a
finite forecast `horizon` [h] the router knows the weather only that far ahead. Wings and
rotors are fixed or retractable, whichever costs less. The router prices time at the
hold's cargo before the fuel store, and the store also holds the largest leg with a unit
down, without its reserve. Returns `nothing` if any passage is infeasible or the
fuel store leaves no cargo.
"""
function round_trip(ship::Ship, outbound::Corridor, inbound::Corridor, weather,
        departures, assumptions::Assumptions; horizon=Inf)
    costs = ShipCosts(ship, assumptions)
    port_hours = 24assumptions[:port_time_per_call]
    hourly = leg_time_costs(costs, assumptions)
    states = service_states(ship.rig, assumptions)
    passages = [service_passages(with_rig(ship, rig), outbound, inbound, weather,
                    departures, assumptions, hourly, port_hours, horizon)
                for (_, rig) in states]
    any(isnothing, passages) && return nothing
    shares = first.(states)
    means = map((values...) -> sum(shares .* values), getproperty.(passages, :means)...)
    (; energy, out_hours, back_hours, flight_hours, launches, forced_landings, rig_cost) =
        means
    reserve = assumptions[:fuel_reserve_factor]
    largest_leg = maximum(passage.largest_leg / (rig === ship.rig ? 1 : reserve)
                          for ((_, rig), passage) in zip(states, passages))
    store = fuel_store(ship, largest_leg, assumptions)
    cargo = cargo_mass(costs.hold, store.mass, store.volume)
    cargo > 0 || return nothing
    round_trip_hours = out_hours + back_hours + 2port_hours
    store_cost = store_round_trip_cost(store.price, round_trip_hours, assumptions)
    running_cost = energy * ship.fuel.price + rig_cost +
                   port_costs(ship.hull, assumptions) + store_cost
    retractable_cost = voyage_time_cost(costs, assumptions, cargo, out_hours, back_hours,
        port_hours)
    fixed = ShipCosts(ship, assumptions; retractable=false)
    delay = fixed_rig_port_hours(ship.rig, ship.design.class, assumptions)
    fixed_cost = voyage_time_cost(fixed, assumptions, cargo, out_hours, back_hours,
        port_hours + delay)
    retractable = retractable_cost < fixed_cost
    voyage_cost = running_cost + min(retractable_cost, fixed_cost)
    capital = (retractable ? costs.capital : fixed.capital) + store.price
    tonne_km = cargo * (outbound.track_length +
                        assumptions[:backhaul_fraction] * inbound.track_length) / 1e3
    return RoundTrip(ship.design, voyage_cost / tonne_km, energy / 1e9,
        energy / 1e6 / tonne_km, energy * ship.fuel.carbon_intensity * 1e3 / tonne_km,
        out_hours / 24, back_hours / 24, cargo, capital,
        ship.powertrain.installed_power / 1e3, flight_hours / (out_hours + back_hours),
        launches, forced_landings, retractable)
end
