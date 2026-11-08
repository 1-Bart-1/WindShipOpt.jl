# Data step of the companion explorer in site/: the designs of the class study with the
# cost model recorded over the inputs a reader changes, for the browser to evaluate at
# other values on the same routes. Included by paper.jl after paper_data.jl; run it in
# the run of the class study, `paper(:classes, :explorer; fidelity)`, to reuse its trips.

"inputs of data/assumptions.yaml a reader of the explorer changes"
explorer_inputs = (:vlsfo_price, :e_methanol_price, :hydrogen_price, :carbon_price,
    :carbon_coverage, :canopy_life, :canopy_making_cost_per_area, :canopy_cloth_base_price,
    :canopy_cloth_price_per_weight, :tether_price, :tether_lifetime, :kite_cycle_crew_cost,
    :kite_cycle_damage_probability, :kite_cycle_loss_probability,
    :kite_forced_landing_loss_probability, :kite_out_of_service, :wing_out_of_service,
    :rotor_out_of_service, :kite_crash_rate, :wing_loss_rate, :rotor_loss_rate,
    :market_price_factor, :kite_lifetime, :wing_lifetime, :rotor_lifetime, :discount_rate,
    :availability)

"ships (class, drive, route) whose cheapest design of each rig is rerun at other inputs"
explorer_check_ships = (("general cargo coaster", :methanol, :caribbean),
    ("MR product tanker", :vlsfo, :bilbao), ("Kamsarmax bulk carrier", :vlsfo, :tubarao),
    ("Neo-Panamax container ship", :methanol, :new_york))

"""
    explorer_changes()

Changes at which the checked designs are rerun, as (label, values by input name, factor
on the cargo value of the class).
"""
function explorer_changes()
    entry(name) = assumptions.entries[name]
    canopy_today = NamedTuple(name => assumptions[Symbol(name, :_today)]
                              for name in WindShipOpt.canopy_price_inputs)
    return [("canopy life ×2", (canopy_life=2assumptions[:canopy_life],), 1.0),
        ("canopy price as built today", canopy_today, 1.0),
        ("fuel −30 %", fuel_prices(0.7), 1.0), ("fuel +30 %", fuel_prices(1.3), 1.0),
        ("carbon price on VLSFO", (carbon_coverage=1.0,), 1.0),
        ("discount rate low", (discount_rate=entry(:discount_rate).low,), 1.0),
        ("discount rate high", (discount_rate=entry(:discount_rate).high,), 1.0),
        ("cargo value ×2", (;), 2.0),
        ("rig prices high", (market_price_factor=entry(:market_price_factor).high,), 1.0),
        ("out of service high", NamedTuple(name => entry(name).high
                                          for name in (:kite_out_of_service,
                                              :wing_out_of_service, :rotor_out_of_service)),
            1.0),
        ("one crash or loss per unit and year",
            (kite_crash_rate=1.0, wing_loss_rate=1.0, rotor_loss_rate=1.0), 1.0)]
end

"""
    fuel_prices(factor)

VLSFO, e-methanol and hydrogen prices at `factor` times their base, by input name.
"""
fuel_prices(factor) = NamedTuple(name => factor * assumptions[name]
                                 for name in (:vlsfo_price, :e_methanol_price,
                                     :hydrogen_price))

"""
    explorer_data()

Every design of classes.csv with its cost per tonne-km and its saving against the ship
without a rig on its own fuel, on e-methanol and on VLSFO, recorded over
[`explorer_inputs`](@ref) and the cargo value of each class; and the cheapest design of
each rig on [`explorer_check_ships`](@ref) at each of [`explorer_changes`](@ref), costed
on its base routes and rerouted: explorer.json.
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
    names = sort(unique(case.class for case in cases); by=name -> classes[name].deadweight)
    recording = WindShipOpt.Recording()
    outputs = WindShipOpt.record(recording) do
        recorded_designs(cases, trips, names)
    end
    document = (; fidelity=string(paper_run.fidelity),
        git_commit=paper_run.record["git_commit"],
        departures=length(sampled_departures()), weather=weather_name,
        inputs=explorer_input_entries(classes, names),
        classes=[explorer_class(classes[name]) for name in names],
        routes=[(; name=string(name), label=route_label(name)) for name in route_names],
        canopy_price=(node=outputs.canopy_price - 1,
            value=WindShipOpt.canopy_price(assumptions)),
        designs=[explorer_design(case, trip, design, names)
                 for (case, trip, design) in zip(cases, trips, outputs.designs)],
        nodes=recording.nodes, checks=explorer_checks(cases, trips))
    open(io -> write_json(io, document), run_file("explorer.json"), "w")
end

"""
    recorded_designs(cases, trips, class_names)

Inside a recording: the node of the canopy price [USD/m^2], and for each design the nodes
of its cost per tonne-km and its savings [%] against the ship without a rig on the same
fuel, on e-methanol and on VLSFO, `nothing` where that ship cannot sail the route.
"""
function recorded_designs(cases, trips, class_names)
    inputs = WindShipOpt.recorded_inputs(assumptions, explorer_inputs)
    classes = ship_classes()
    cargo_values = Dict(name => WindShipOpt.recorded_input(cargo_input(name),
                            classes[name].cargo_value) for name in class_names)
    costs = [recorded_cost(case, trip, inputs, cargo_values[case.class])
             for (case, trip) in zip(cases, trips)]
    bare = Dict((case.class, case.route, case.drive) => cost
                for (case, cost) in zip(cases, costs) if case.rig == "none")
    designs = [(cost=cost.node, saving=saving_node(bare, case, cost, case.drive),
                   methanol_saving=saving_node(bare, case, cost, :methanol),
                   vlsfo_saving=saving_node(bare, case, cost, :vlsfo))
               for (case, cost) in zip(cases, costs)]
    return (; canopy_price=WindShipOpt.canopy_price(inputs).node, designs)
end

"""
    saving_node(bare, case, cost, drive)

Node of the saving [%] of `case` at the recorded `cost` against the ship without a rig
of its class on its route with `drive`, of recorded cost in `bare`; `nothing` without one.
"""
function saving_node(bare, case, cost, drive)
    reference = get(bare, (case.class, case.route, drive), nothing)
    return isnothing(reference) ? nothing : percent_saving(cost, reference).node
end

"name of the recorded input of the cargo value [USD/t] of class `name`"
cargo_input(name) = "cargo_value:" * name

"""
    recorded_cost(case, trip, inputs, cargo_value)

Cost per tonne-km [USD] of `case` on the routes of its `trip` at the recorded `inputs`,
with the class's cargo value replaced by `cargo_value`.
"""
function recorded_cost(case, trip, inputs, cargo_value)
    ship = Ship(case.design, assumptions)
    costs = [WindShipOpt.ShipCosts(costs.capital, costs.fixed_annual, costs.hold,
                 cargo_value) for costs in WindShipOpt.ship_costs(ship, inputs)]
    return recosted(ship, costs, trip, case, inputs)
end

"""
    recosted(ship, costs, trip, case, inputs)

Cost per tonne-km [USD] of `ship` with [`ShipCosts`](@ref) `costs` on the routes of its
`trip` for `case`, at `inputs`.
"""
recosted(ship, costs, trip, case, inputs) = WindShipOpt.voyage_costs(ship, costs,
    WindShipOpt.state_rigs(ship.rig, assumptions), trip.passages, case.corridors...,
    inputs).cheaper

"""
    explorer_checks(cases, trips)

The cheapest design of each rig and the ship without a rig on each of
[`explorer_check_ships`](@ref), at each of [`explorer_changes`](@ref): its index into
`cases` from zero, the label, the changed inputs and cargo factor, its cost per tonne-km
on its base routes and rerouted.
"""
function explorer_checks(cases, trips)
    checks = [(k, change...) for k in checked_designs(cases, trips)
              for change in explorer_changes()]
    changed = [checked_case(cases[k], changes, factor)
               for (k, _, changes, factor) in checks]
    rerouted = round_trips(changed, sampled_departures())
    return [(design=k - 1, label, changes, cargo_factor=factor,
                recosted=changed_cost(case, trips[k]), rerouted=trip.cost_per_tonne_km)
            for ((k, label, changes, factor), case, trip) in zip(checks, changed, rerouted)
            if !isnothing(trip)]
end

"""
    changed_cost(case, trip)

Cost per tonne-km [USD] of `case` at its inputs on the routes of `trip`, routed at the
base inputs.
"""
function changed_cost(case, trip)
    ship = Ship(case.design, case.assumptions)
    costs = WindShipOpt.ship_costs(ship, case.assumptions)
    return recosted(ship, costs, trip, case, case.assumptions)
end

"""
    checked_case(case, changes, cargo_factor)

`case` with the inputs `changes` and its class's cargo value times `cargo_factor`.
"""
function checked_case(case, changes, cargo_factor)
    (; class) = case.design
    changed_class = ShipClass(; (name => getfield(class, name)
                                 for name in fieldnames(ShipClass))...,
        cargo_value=cargo_factor * class.cargo_value)
    design = ShipDesign(; (name => getfield(case.design, name)
                           for name in fieldnames(ShipDesign))..., class=changed_class)
    return trip_case(design; assumptions=changed_assumptions(changes), case.route)
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
    explorer_input_entries(classes, class_names)

The base, low and high values and the unit of each of [`explorer_inputs`](@ref) and of
the canopy price inputs as built today by name, and of the cargo value of each of
`class_names`.
"""
function explorer_input_entries(classes, class_names)
    today = (Symbol(name, :_today) for name in WindShipOpt.canopy_price_inputs)
    entries = Dict{String, Any}(string(name) => assumptions.entries[name]
                                for name in (explorer_inputs..., today...))
    for name in class_names
        value = classes[name].cargo_value
        entries[cargo_input(name)] = Assumption(value, value, value, "USD/t",
            "cargo value of the class")
    end
    return entries
end

"""
    explorer_class(class)

Name, kind and deadweight [t] of `class`.
"""
explorer_class(class) = (; class.name, class.type, class.deadweight)

"""
    explorer_design(case, trip, design, class_names)

One design of explorer.json: its class as an index into `class_names` and its route as
one into `route_names`, both from zero, its drive, rig, area and units, its cost per
tonne-km and its recorded nodes `design`, from zero.
"""
explorer_design(case, trip, design, class_names) = (;
    class=findfirst(==(case.class), class_names) - 1,
    route=findfirst(==(case.route), route_names) - 1, drive=string(case.drive), case.rig,
    case.area, case.units, cost=trip.cost_per_tonne_km,
    nodes=map(node -> isnothing(node) ? nothing : node - 1, design))

"""
    write_json(io, value)

Write `value` as JSON: named tuples, dicts and assumptions as objects, vectors and
tuples as arrays, the nodes of a recording as arrays of their operation and operands
from zero, numbers to full precision, infinities as 1e999, which parses as one, and NaN
as null.
"""
write_json(io, value::AbstractString) = print(io, '"', escape_string(value), '"')
write_json(io, value::Symbol) = write_json(io, string(value))
write_json(io, value::Bool) = print(io, value)
write_json(io, ::Nothing) = print(io, "null")
write_json(io, value::Integer) = print(io, value)
write_json(io, value::Real) = isnan(value) ? print(io, "null") :
                              isinf(value) ? print(io, value > 0 ? "1e999" : "-1e999") :
                              print(io, Float64(value))
write_json(io, value::Assumption) = write_json(io, (; value.value, value.low, value.high,
    value.unit))
write_json(io, value::Union{NamedTuple, AbstractDict}) =
    write_json_entries(io, '{', '}', pairs(value))
write_json(io, value::Union{AbstractVector, Tuple}) =
    write_json_entries(io, '[', ']', value)
write_json(io, nodes::Vector{Tuple{Symbol, Tuple}}) = write_json_entries(io, '[', ']',
    [operation in (:input, :constant) ? [operation, operands...] :
     [operation, (operands .- 1)...] for (operation, operands) in nodes])

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
