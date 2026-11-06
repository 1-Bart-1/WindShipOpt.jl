# Data step of the companion explorer on bart.vandelint.net/windships: the designs of the
# class study with what their round trips do physically, for the browser to recompute the
# cost per tonne-km at other prices on the same routes. Included by paper.jl after
# paper_data.jl, whose class study must have written classes.csv to a run at its fidelity.

"""
inputs the explorer's cost model reads from data/assumptions.yaml; the others are folded
into the exported designs
"""
explorer_inputs = (:vlsfo_price, :vlsfo_carbon_intensity, :e_ammonia_price,
    :carbon_price, :carbon_coverage, :discount_rate, :hull_lifetime, :wing_lifetime,
    :rotor_lifetime, :kite_lifetime, :market_price_factor, :retractable_rig_premium,
    :tether_lifetime, :kite_cycle_crew_cost, :kite_cycle_damage_probability,
    :kite_cycle_loss_probability,
    :kite_launch_retry_probability, :kite_cycle_course_cost, :mechanical_propulsion_cost,
    :electric_propulsion_cost, :newbuild_reference_deadweight, :crew_cost,
    :crew_cost_exponent, :maintenance_fraction, :availability, :port_time_per_call)

"names of the rig hardware prices of [`WindShipOpt.rig_price_parts`](@ref)"
explorer_parts = (:units, :surface, :installation, :winch, :mast, :docking_head,
    :control_unit, :integration)

"columns of each exported design, in order"
explorer_columns = ["class", "route", "drive", "rig", "area", "unit_count",
    "installed_power", "fuel_energy", "sea_hours", "flight_hours",
    "launches", "cargo", "rig_mass", "deck_cargo_loss", "fixed_delay",
    string.(explorer_parts)..., "canopy_area", "tether_price", "cost", "retractable"]

"ships (class, drive, route) whose cheapest design of each rig is rerun at other prices"
explorer_check_ships = (("general cargo coaster", :ammonia, :caribbean),
    ("MR product tanker", :vlsfo, :bilbao), ("Kamsarmax bulk carrier", :vlsfo, :tubarao),
    ("Neo-Panamax container ship", :ammonia, :new_york))

"""
    explorer_changes()

Price changes at which the checked designs are rerun, as (label, values by input name).
"""
function explorer_changes()
    rate = assumptions.entries[:discount_rate]
    return [("canopy life ×2", (canopy_life=2assumptions[:canopy_life],)),
        ("fuel −30 %", fuel_prices(0.7)), ("fuel +30 %", fuel_prices(1.3)),
        ("discount rate low", (discount_rate=rate.low,)),
        ("discount rate high", (discount_rate=rate.high,)),
        ("carbon price on VLSFO", (carbon_coverage=1.0,))]
end

"""
    fuel_prices(factor)

VLSFO and e-ammonia prices [USD/GJ] at `factor` times their base, by input name.
"""
fuel_prices(factor) = (vlsfo_price=factor * assumptions[:vlsfo_price],
    e_ammonia_price=factor * assumptions[:e_ammonia_price])

"""
    explorer_data()

Rerun every design of classes.csv at the base inputs, and the cheapest design of each
rig on [`explorer_check_ships`](@ref) at each of [`explorer_changes`](@ref):
explorer.json, with the class and route data, the base inputs and the checks.
"""
function explorer_data()
    table = read_table(data_file("classes.csv"))
    classes = ship_classes()
    cases = [class_case(classes[table["class"][k]], Symbol(table["drive"][k]),
                 table["rig"][k], table["area"][k], Symbol(table["route"][k]))
             for k in eachindex(table["class"])]
    trips = round_trips(cases, sampled_departures())
    feasible = findall(!isnothing, trips)
    cases, trips = cases[feasible], trips[feasible]
    checks = [(k, label, changes) for k in checked_designs(cases, trips)
              for (label, changes) in explorer_changes()]
    check_cases = [trip_case(cases[k].design; assumptions=changed_assumptions(changes),
                       cases[k].route) for (k, _, changes) in checks]
    check_trips = round_trips(check_cases, sampled_departures())
    names = sort(unique(case.class for case in cases); by=name -> classes[name].deadweight)
    document = (; fidelity=string(paper_run.fidelity),
        departures=length(sampled_departures()), weather=weather_name,
        inputs=explorer_input_entries(),
        classes=[explorer_class(classes[name]) for name in names],
        routes=[explorer_route(name) for name in route_names], columns=explorer_columns,
        designs=[explorer_row(case, trip, names) for (case, trip) in zip(cases, trips)],
        checks=[(design=k - 1, label, changes, cost=trip.cost_per_tonne_km)
                for ((k, label, changes), trip) in zip(checks, check_trips)
                if !isnothing(trip)])
    open(io -> write_json(io, document), run_file("explorer.json"), "w")
end

"""
    explorer_input_entries()

The base [`explorer_inputs`](@ref) by name, with the canopy cost per m^2 and life the
explorer's cost model reads, derived from the cloth by [`WindShipOpt.Canopy`](@ref).
"""
function explorer_input_entries()
    entries = Dict(name => assumptions.entries[name] for name in explorer_inputs)
    canopy = WindShipOpt.Canopy(assumptions)
    for (name, value, unit) in ((:canopy_cost_per_area, canopy.cost_per_area, "USD/m^2"),
        (:canopy_lifetime, canopy.lifetime, "flight hours"))
        entries[name] = Assumption(value, value, value, unit,
            "derived from the cloth and the goal")
    end
    return entries
end

"""
    checked_designs(cases, trips)

Indices of the cheapest design of each rig, and of the ship without a rig, on each of
[`explorer_check_ships`](@ref).
"""
function checked_designs(cases, trips)
    chosen = Int[]
    for (class, drive, route) in explorer_check_ships, rig in all_rigs
        best = 0
        for k in eachindex(cases)
            (cases[k].class, cases[k].drive, cases[k].route, cases[k].rig) ==
            (class, drive, route, rig) || continue
            if best == 0 || trips[k].cost_per_tonne_km < trips[best].cost_per_tonne_km
                best = k
            end
        end
        best > 0 && push!(chosen, best)
    end
    return chosen
end

"""
    explorer_class(class)

Name, kind, deadweight [t], newbuild price [USD], cargo value [USD/t] and port costs
per round trip [USD] of `class`.
"""
explorer_class(class) = (; class.name, class.type, class.deadweight, class.newbuild_price,
    class.cargo_value, port_cost=WindShipOpt.port_costs(Hull(class, assumptions),
        assumptions))

"""
    explorer_route(name)

Name, label and tonne-km per tonne of cargo of route `name`, with the backhaul share of
the return leg.
"""
function explorer_route(name)
    return (; name=string(name), label=route_label(name),
        tonne_km_per_tonne=tonne_km_per_tonne(name))
end

"""
    explorer_row(case, trip, class_names)

One design of explorer.json in the order of `explorer_columns`, with its class as an
index into `class_names` and its route as one into `route_names`, both from zero.
"""
function explorer_row(case, trip, class_names)
    ship = Ship(case.design, assumptions)
    (; rig) = ship
    sea_hours = 24(trip.outbound_days + trip.return_days)
    parts = WindShipOpt.rig_price_parts(rig, assumptions)
    return [findfirst(==(case.class), class_names) - 1,
        findfirst(==(case.route), route_names) - 1, string(case.drive), case.rig,
        case.area, case.units, trip.installed_power, trip.fuel_energy, sea_hours,
        trip.flight_share * sea_hours, trip.launches, trip.cargo,
        WindShipOpt.rig_costs(rig, assumptions)[2],
        WindShipOpt.blocked_slots(rig, case.design.class, assumptions) *
        WindShipOpt.CargoUnit(case.design.class.cargo_unit, assumptions).cargo,
        WindShipOpt.fixed_rig_port_hours(rig, case.design.class, assumptions),
        [get(parts, name, 0.0) for name in explorer_parts]..., consumables(rig)...,
        trip.cost_per_tonne_km, trip.retractable]
end

"""
    consumables(rig)

Canopy area [m^2] and tether price [USD] of a kite `rig`; zeros for other rigs.
"""
consumables(rig) = (0.0, 0.0)
consumables(rig::KiteRig) = (rig.area, last(WindShipOpt.consumable_costs(rig,
    assumptions)))

"""
    write_json(io, value)

Write `value` as JSON: named tuples, dicts and assumptions as objects, vectors and
tuples as arrays, numbers to ten significant digits and non-finite ones as null.
"""
write_json(io, value::AbstractString) = print(io, '"', escape_string(value), '"')
write_json(io, value::Symbol) = write_json(io, string(value))
write_json(io, value::Bool) = print(io, value)
write_json(io, value::Integer) = print(io, value)
write_json(io, value::Real) = isfinite(value) ? @printf(io, "%.10g", value) :
                              print(io, "null")
write_json(io, value::Assumption) = write_json(io, (; value.value, value.low, value.high,
    value.unit))
write_json(io, value::Union{NamedTuple, AbstractDict}) =
    write_json_entries(io, '{', '}', pairs(value))
write_json(io, value::Union{AbstractVector, Tuple}) =
    write_json_entries(io, '[', ']', value)

"""
    write_json_entries(io, open, close, entries)

Write `entries` between the brackets `open` and `close`: pairs as object members on
lines of their own, arrays as array elements, also on lines of their own, and other
values as array elements on one line.
"""
function write_json_entries(io, open, close, entries)
    print(io, open)
    for (k, entry) in enumerate(entries)
        k > 1 && print(io, entry isa Union{Pair, AbstractVector, NamedTuple} ? ",\n" : ",")
        write_json_entry(io, entry)
    end
    print(io, close)
end

write_json_entry(io, entry) = write_json(io, entry)

function write_json_entry(io, entry::Pair)
    write_json(io, string(first(entry)))
    print(io, ':')
    write_json(io, last(entry))
end
