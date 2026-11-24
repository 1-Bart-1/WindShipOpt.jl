# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Site step of the companion explorer in site/: the designs of the class study with the
# cost model recorded over the inputs a reader changes, for the browser to recost on the
# class study's stored round trips. Included by paper.jl after paper_data.jl.

"inputs of data/assumptions.yaml a reader of the explorer changes"
explorer_inputs = (:vlsfo_price, :e_ammonia_price, :carbon_price, :canopy_life,
    :canopy_structure_cost, :canopy_cloth_price_per_weight, :tether_price, :tether_lifetime,
    :kite_cycle_crew_cost, :kite_launch_loss_probability, :kite_out_of_service,
    :wing_out_of_service, :rotor_out_of_service, :suction_out_of_service, :wing_loss_rate,
    :rotor_loss_rate, :market_price_factor, :kite_lifetime, :wing_lifetime, :rotor_lifetime,
    :suction_lifetime, :discount_rate, :availability)

"""
    explorer_data()

Every design of the [`compared_table`](@ref) of the class study with its cost per tonne-km
and its saving against the ship without a rig on its own fuel, on e-ammonia and on VLSFO,
recorded over [`explorer_inputs`](@ref) and the cargo value of each class on its stored
round trips, and their [`explorer_check`](@ref): explorer.json.
"""
function explorer_data()
    classes = ship_classes()
    cases = class_cases(compared_table())
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
            value=reference_canopy_price(assumptions)),
        designs=[explorer_design(case, trip, design, names)
                 for (case, trip, design) in zip(cases, trips, outputs.designs)],
        nodes=recording.nodes, check=explorer_check(cases, trips))
    open(io -> write_json(io, document), run_file("explorer.json"), "w")
end

"""
    recorded_designs(cases, trips, class_names)

Inside a recording: the node of the canopy price [USD/m^2], and for each design the nodes
of its cost per tonne-km and its savings [%] against the ship without a rig on the same
fuel, on e-ammonia and on VLSFO, `nothing` where that ship cannot sail the route.
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
                   ammonia_saving=saving_node(bare, case, cost, :ammonia),
                   vlsfo_saving=saving_node(bare, case, cost, :vlsfo))
               for (case, cost) in zip(cases, costs)]
    return (; canopy_price=reference_canopy_price(inputs).node, designs)
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
    ship = Ship(case.design, assumptions; case.route)
    costs = [WindShipOpt.ShipCosts(costs.capital, costs.fixed_annual, costs.hold,
                 cargo_value) for costs in WindShipOpt.ship_costs(ship, inputs)]
    return recosted(ship, costs, trip, case, inputs)
end

"""
    explorer_check(cases, trips)

Each of [`explorer_inputs`](@ref) at its high bound, with the cost per tonne-km [USD] the
model gives each of `cases` there on its round trip of `trips`.
"""
function explorer_check(cases, trips)
    changes = NamedTuple(name => assumptions.entries[name].high for name in explorer_inputs)
    changed = changed_assumptions(changes)
    return (; changes, costs=[changed_cost(merge(case, (; assumptions=changed)), trip)
                              for (case, trip) in zip(cases, trips)])
end

"""
    explorer_input_entries(classes, class_names)

The base, low and high values, the unit and the value known today of each of
[`explorer_inputs`](@ref) by name, and of the cargo value of each of `class_names`, its
range that of the input `cargo_value` in proportion.
"""
function explorer_input_entries(classes, class_names)
    entries = Dict{String, Any}(string(name) => assumptions.entries[name]
                                for name in explorer_inputs)
    cargo = assumptions.entries[:cargo_value]
    for name in class_names
        value = classes[name].cargo_value
        entries[cargo_input(name)] = Assumption(value, value * cargo.low / cargo.value,
            value * cargo.high / cargo.value, "USD/t", "cargo value of the class", value,
            cargo.estimate)
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
    value.unit, value.today))
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
