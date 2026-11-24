# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Data steps of the paper: each runs one study and writes its data files to the directory
# of the run in use. Included by paper.jl.

"drives compared where the drive is a dimension of the study"
study_drives = (:vlsfo, :ammonia)

"projected aspect ratio of the kite of every design that names none"
design_aspect_ratio = assumptions[:kite_aspect_ratio]

"""
    trip_case(design; assumptions, route, scale, forecast, held_knots, part, labels...)

One round trip to compute: `design` under `assumptions` on the corridors of `route` at
corridor `scale`, with perfect foresight where `forecast` is false and otherwise re-planned
daily on what [`forecast_source`](@ref) gives for it, holding `held_knots` [kn] or with
speed set by cost where `nothing`, with the model `part` switched off by
[`simplified_ship`](@ref), tagged with `labels` for the output. With `paths`, the outbound
and return corridors of one fixed course, named `course`, in place of those of `route`.
"""
function trip_case(design; assumptions=assumptions, route=:caribbean,
        scale=run_settings().corridor_scale, forecast=false, held_knots=nothing, part=:none,
        paths=nothing, course=:routed, labels...)
    return (; labels..., design, assumptions, route, scale, course,
        corridors=isnothing(paths) ? corridors(route, scale) : paths, forecast, held_knots,
        part)
end

"""
    case_trip(case, departures)

Round trip of `case` over `departures`, or `nothing` where its ship does not exist or a
passage fails.
"""
function case_trip(case, departures)
    routing = case_routing(case)
    departed = fetch.([Threads.@spawn departure_trip(routing, case, departure)
                       for departure in departures])
    return combined_trip(case, departures, departed)
end

"""
    case_ship(case)

The ship of `case` with its model part switched off, or `nothing` where it does not exist.
"""
function case_ship(case)
    ship = Ship(case.design, case.assumptions; case.route)
    return isnothing(ship) ? nothing : simplified_ship(ship, case.part)
end

"""
    case_routing(case)

What routing one departure of `case` takes: the [`DepartureRouting`](@ref) of its ship and
what it plans on; `nothing` where its ship does not exist.
"""
function case_routing(case)
    ship = case_ship(case)
    isnothing(ship) && return nothing
    routing = WindShipOpt.DepartureRouting(ship, first(case.corridors), case.assumptions;
        case.held_knots)
    return (; routing, forecast=forecast_source(case.forecast))
end

"""
    departure_trip(routing, case, departure)

The [`departure_passages`](@ref) of `case` from `departure` [h] by its
[`case_routing`](@ref) `routing`; `nothing` where its ship does not exist or a passage
fails.
"""
departure_trip(routing, case, departure) = isnothing(routing) ? nothing :
    WindShipOpt.departure_passages(routing.routing, case.corridors..., weather, departure;
        routing.forecast)

"""
    combined_trip(case, departures, departed)

Round trip of `case` from the [`departure_trip`](@ref) `departed` of each of `departures`,
or `nothing` where its ship does not exist or a passage failed.
"""
function combined_trip(case, departures, departed)
    ship = case_ship(case)
    isnothing(ship) && return nothing
    return WindShipOpt.combine_departures(ship, case.corridors..., departures,
        case.assumptions, departed)
end

"""
    forecast_source(plan)

What a case plans on: nothing where `plan` is false (perfect foresight), and where it is
`:live` the control forecast weighing its wind error, re-planned daily and sailed live,
choosing speed and kite hour by hour on the weather met.
"""
function forecast_source(plan)
    plan === false && return nothing
    plan === :live || throw(ArgumentError("no forecast plan $plan"))
    return ReplannedForecast(expected_forecast(); live=true)
end

"the control forecast weighing its wind error ([`forecast_error`](@ref))"
expected_forecast() = ExpectedForecast(forecast_archive, forecast_error())

"""
    round_trips(cases, departures)

Round trips of all `cases`, taking those the case store holds for the run in use
([`stored_entry`](@ref)) and combining the others from their departures, which the jobs of
`case_jobs` route where [`handed_out`](@ref) says so, else this process
([`compute_trips`](@ref)).
"""
function round_trips(cases, departures)
    directories = [case_directory(case, departures) for case in cases]
    entries = Any[stored_entry(directory, case)
                  for (case, directory) in zip(cases, directories)]
    computed = findall(ismissing, entries)
    handed_out(case_jobs, length(computed) * length(departures)) &&
        job_trips(case_jobs, cases, directories, departures)
    entries[computed] = compute_trips(cases[computed], directories[computed], departures)
    foreach(tally_case!, cases, directories, entries)
    trips = [entry.trip for entry in entries]
    older = count(entry -> entry.model != paper_run.trip_model, entries)
    println("  ", count(!isnothing, trips), " of ", length(cases), " round trips, ",
        length(cases) - length(computed), " stored",
        older > 0 ? ", $older by older code" : "")
    return trips
end

"""
    compute_trips(cases, directories, departures)

Case-store entries of the round trips of `cases` over `departures`, combined on the threads
of this process from their departures ([`departure_entries`](@ref)) and stored in
`directories`.
"""
function compute_trips(cases, directories, departures)
    entries = Vector{Any}(undef, length(cases))
    Threads.@threads :greedy for k in eachindex(cases)
        departed = departure_entries(cases[k], departures,
            departure_directory.(directories[k], departures))
        entries[k] = stored_trip(directories[k], cases[k];
            seconds=sum(entry.seconds for entry in departed)) do
            foreach(entry -> replay_reads(entry, cases[k]), departed)
            combined_trip(cases[k], departures, [entry.trip for entry in departed])
        end
    end
    return entries
end

"""
    departure_entries(case, departures, directories)

Case-store entries of the [`departure_trip`](@ref) of `case` from each of `departures`,
taking those the case store holds in `directories` for the run in use and routing the
others in parallel, each stored as it ends with the inputs and files its routing read.
"""
function departure_entries(case, departures, directories)
    entries = Any[departure_entry(directory, case) for directory in directories]
    missed = findall(ismissing, entries)
    isempty(missed) && return entries
    routing, reads = with_reads(() -> case_routing(case), case)
    entries[missed] = fetch.([Threads.@spawn stored_trip(directories[k], case) do
                                  replay_reads(reads, case)
                                  departure_trip(routing, case, departures[k])
                              end for k in missed])
    return entries
end

"""
    write_trips(name, cases, trips, columns...)

Write `name` to the directory of the run in use with the given label `columns` of each
case and the cost [USD/tkm], fuel [MJ/tkm], CO2 [g/tkm], round-trip days, kite flight
share, kite launches and forced landings per round trip, cargo [t], whether the rig
retracts and the [`cost_columns`](@ref), of each feasible trip.
"""
function write_trips(name, cases, trips, columns...)
    open(run_file(name), "w") do io
        println(io, join([collect(string.(columns)); ["cost", "fuel", "carbon", "days",
            "flight_share", "launches", "forced_landings", "cargo", "retractable"];
            cost_columns], ","))
        for (case, trip) in zip(cases, trips)
            isnothing(trip) && continue
            labels = [csv_value(getproperty(case, column)) for column in columns]
            @printf(io, "%s,%.6f,%.5f,%.3f,%.2f,%.3f,%.2f,%.2f,%.0f,%s",
                join(labels, ","), trip.cost_per_tonne_km, trip.fuel_per_tonne_km,
                trip.carbon_per_tonne_km, trip.outbound_days + trip.return_days,
                trip.flight_share, trip.launches, trip.forced_landings, trip.cargo,
                trip.retractable)
            write_costs(io, case, trip, trip.cargo * tonne_km_per_tonne(case.corridors...))
        end
    end
end

"""
    csv_value(value)

`value` as a CSV field: quoted if it holds a space, integers without a decimal point.
"""
csv_value(value::AbstractString) = occursin(' ', value) ? "\"$value\"" : value
csv_value(value::Real) = isinteger(value) ? string(Int(value)) : string(value)
csv_value(value) = string(value)

"""
    one_at_a_time(inputs, names, entries=[assumptions.entries[name] for name in names])

`inputs` with each input of `names` in turn at the low and at the high bound of its entry
of `entries`.
"""
one_at_a_time(inputs, names, entries=[assumptions.entries[name] for name in names]) =
    [with_value(inputs, name, bound) for (name, entry) in zip(names, entries)
     for bound in (entry.low, entry.high)]

"the ship classes of the sea effect study, in order of length"
sea_effect_classes = ("general cargo coaster", "feeder container ship",
    "Kamsarmax bulk carrier", "VLCC", "Neo-Panamax container ship")

"""
    sea_effect_data()

On every route on e-ammonia, the 140 m ship with the 3,200 m^2 kite and each of
[`sea_effect_classes`](@ref) with the kite the class study found cheapest on fuel oil,
without a rig, with the kite as modelled and with no extra launch wind from the sea:
sea_effect.csv.
"""
function sea_effect_data()
    classes_table = read_table(data_file("classes.csv"))
    no_sea = with_value(assumptions, :kite_launch_sea_wind, 0.0)
    ships = Any[("140 m", 140.0),
        ((name, ship_classes()[name]) for name in sea_effect_classes)...]
    cases = []
    for route in route_names, (ship, build) in ships
        area = sea_effect_area(classes_table, ship, route)
        bare = ShipDesign(:ammonia, build)
        push!(cases, trip_case(bare; route, ship, rig="none", area=0.0, sea="none"))
        rigged = ShipDesign(:ammonia, build; rig_size("kite", area)...)
        kite = (; route, ship, rig="kite", area)
        push!(cases, trip_case(rigged; kite..., sea="model"))
        push!(cases, trip_case(rigged; kite..., sea="none", assumptions=no_sea))
    end
    write_trips("sea_effect.csv", cases, round_trips(cases, sampled_departures()), :ship,
        :route, :rig, :area, :sea)
end

"kite area [m^2] of `ship` in the sea effect study on `route`, read from `classes_table`"
sea_effect_area(classes_table, ship, route) = ship == "140 m" ? 3200.0 :
    best_area(classes_table, ship, string(route), "vlsfo", "kite")

"""
    patterns_data()

Optimal flight patterns and still kites of the base 800 m^2 kite over the ship's course off
the apparent downwind direction in light and strong apparent wind: patterns.csv (path
points) and pattern_forces.csv.
"""
function patterns_data()
    model, max_force, _ = WindShipOpt.kite_model(800.0, 3.0, assumptions)
    min_elevation = deg2rad(assumptions[:kite_min_elevation])
    open(run_file("patterns.csv"), "w") do paths
        open(run_file("pattern_forces.csv"), "w") do forces
            println(paths, "wind,course,side_weight,azimuth,elevation")
            println(forces, "wind,course,side_weight,thrust,side")
            for wind in (6.0, 12.0), course in 0:30:180, side_weight in (0.0, 1.0)
                write_pattern(paths, forces, model, max_force, min_elevation, wind,
                    course, side_weight)
            end
        end
    end
end

"""
    best_pattern_cycle(model, max_force, min_elevation, wind, course, side_weight)

Force of the kite's best state at apparent wind `wind` [m/s] and `course` [°], a pattern or
a still kite ([`WindShipOpt.kite_state`](@ref)), and the steps of its cycle, one step
where it is held still.
"""
function best_pattern_cycle(model, max_force, min_elevation, wind, course, side_weight)
    problem = WindShipOpt.PatternProblem(model, max_force, min_elevation, wind,
        deg2rad(course), side_weight)
    flown, parameters = WindShipOpt.optimal_pattern(problem,
        WindShipOpt.pattern_starts(deg2rad(course)))
    force, state = WindShipOpt.kite_state(problem, flown, parameters)
    path = WindShipOpt.PatternStep[]
    WindShipOpt.PatternForce(model, state, wind, max_force; path)
    return force, path
end

"""
    write_pattern(paths, forces, model, max_force, min_elevation, wind, course,
                  side_weight)

Optimise the kite's state and write its force and its path; nothing where the kite neither
flies a pattern nor holds still.
"""
function write_pattern(paths, forces, model, max_force, min_elevation, wind, course,
        side_weight)
    force, path = best_pattern_cycle(model, max_force, min_elevation, wind, course,
        side_weight)
    isempty(path) && return
    load = 0.5model.air_density * wind^2 * model.area
    downwind, crosswind, _ = load .* force.force
    thrust = downwind * cosd(course) + crosswind * sind(course)
    side = -downwind * sind(course) + crosswind * cosd(course)
    @printf(forces, "%.0f,%.0f,%.1f,%.1f,%.1f\n", wind, course, side_weight, thrust, side)
    for (x, y, z) in getfield.([path; path[1:1]], :radial)
        @printf(paths, "%.0f,%.0f,%.1f,%.5f,%.5f\n", wind, course, side_weight,
            atan(y, x), asin(z))
    end
end

"""
    changed_assumptions(changes)

The base assumptions with the inputs of the named tuple `changes` at its values.
"""
function changed_assumptions(changes)
    changed = assumptions
    for (name, value) in pairs(changes)
        changed = with_value(changed, name, value)
    end
    return changed
end


"design keyword of each rig"
rig_keywords = Dict("kite" => :kite_area, "wings" => :wing_area, "rotors" => :rotor_area,
    "vtol" => :rigid_kite_area, "suction" => :suction_area, "lei" => :lei_kite_area)

"""
    rig_size(rig, area)

Design keywords for `area` [m^2] of `rig`; none for "none". Throws on an `area` that is not
finite, as [`best_area`](@ref) gives where the rig was not run.
"""
function rig_size(rig, area)
    rig == "none" && return (;)
    isfinite(area) || throw(ArgumentError("no size for the $rig: area $area"))
    return NamedTuple{(rig_keywords[rig],)}((area,))
end

"""
    study_hull(ship)

Length of the 140 m reference ship, or the ship class of name `ship`, for a design.
"""
study_hull(ship) = ship == "140 m" ? 140.0 : ship_classes()[ship]

"reference size of each rig on the 140 m ship"
reference_rigs = [("kite", 3200.0), ("wings", 1500.0), ("rotors", 800.0),
    ("suction", 800.0), ("vtol", 200.0), ("lei", 700.0)]

"the 140 m ship without a rig, then each of the [`reference_rigs`](@ref)"
reference_rigs_and_none = [("none", 0.0); reference_rigs]

"projected area [m^2] and aspect ratio at `inputs` of the reference kite of the 140 m ship"
reference_kite_shape(inputs) = (Dict(reference_rigs)["kite"], inputs[:kite_aspect_ratio])

"canopy price [USD/m^2] at `inputs` of the reference kite of the 140 m ship"
reference_canopy_price(inputs) =
    WindShipOpt.canopy_price(inputs, reference_kite_shape(inputs)...)

"the rigs, as named in the output"
rig_names = ("kite", "wings", "rotors", "suction", "vtol", "lei")

"index in `rig_names` and name of each rig that the study table `table` has"
study_rigs(table) = [(j, rig) for (j, rig) in enumerate(rig_names) if rig in table["rig"]]

"the rigs that stand on deck, as named in the output"
deck_rig_names = ("wings", "rotors", "suction")

"the ship without a rig and the rigs, as named in the output"
all_rigs = ("none", rig_names...)

"""
    scaled(names, factor)

The assumptions with each input in `names` at `factor` times its base value.
"""
function scaled(names, factor)
    return changed_assumptions(NamedTuple(name => factor * assumptions[name]
                                          for name in names))
end

"inputs of the situation study that stand for a factor on several assumptions at once"
scaled_inputs = Dict(:wing_price => (:wing_unit_cost, :wing_cost_per_mass))

"""
    situation_assumptions(input, value)

The assumptions with `input` at `value`, a factor on its assumptions for an input of
`scaled_inputs`; the base assumptions for `:base`.
"""
function situation_assumptions(input, value)
    input == :base && return assumptions
    haskey(scaled_inputs, input) && return scaled(scaled_inputs[input], value)
    return with_value(assumptions, input, value)
end

"""
    base_value(input)

Value of `input` in the base assumptions; 1 for an input of `scaled_inputs`.
"""
base_value(input) = haskey(scaled_inputs, input) ? 1.0 : assumptions[input]

"""
Values besides the base of each input of the situation study, and the rigs whose cost
it changes. Fuel prices are in USD/GJ, cargo value in USD/t, lifetimes in years, the rotor
surface speed in m/s; the wing price is a factor.
"""
situation_inputs = Dict(:vlsfo_price => ((8.0, 12.0, 22.0, 30.0), all_rigs),
    :e_ammonia_price => ((30.0, 40.0, 60.0, 82.0, 120.0), all_rigs),
    :e_methanol_price => ((40.0, 90.0, 120.0), all_rigs),
    :cargo_value => ((1000.0, 5000.0, 10000.0, 20000.0), all_rigs),
    :discount_rate => ((0.04, 0.06, 0.1, 0.12, 0.16), all_rigs),
    :wing_lifetime => ((10.0, 15.0, 25.0, 30.0), ("wings",)),
    :wing_price => ((0.25, 0.5, 0.75, 1.5), ("wings",)),
    :rotor_max_surface_speed => ((35.0, 40.0, 55.0, 65.0), ("rotors",)))

"rig sizes [m^2] of each ship of the situation study"
situation_sizes = Dict(
    "140 m" => Dict("kite" => (800.0, 1600.0, 3200.0, 6400.0),
        "wings" => (800.0, 1500.0, 2400.0), "rotors" => (400.0, 800.0, 1600.0),
        "suction" => (400.0, 800.0, 1600.0), "vtol" => (100.0, 200.0, 400.0),
        "lei" => (350.0, 700.0, 1400.0)),
    "Kamsarmax bulk carrier" => Dict("kite" => (1600.0, 3200.0, 6400.0),
        "wings" => (1600.0, 2400.0, 3600.0), "rotors" => (850.0, 1200.0, 1890.0),
        "suction" => (850.0, 1200.0, 1890.0), "vtol" => (200.0, 400.0, 800.0),
        "lei" => (700.0, 1400.0, 2800.0)))

"""
Ship, route, drive and inputs of each part of the situation study: every input on the
140 m reference ship to Guadeloupe and all but the cargo value on a Kamsarmax to Tubarão,
and on both the price of each fuel on its own drive.
"""
situation_studies = [("140 m", :caribbean, :vlsfo, [:vlsfo_price]),
    ("140 m", :caribbean, :ammonia, [:e_ammonia_price, :cargo_value, :discount_rate,
        :wing_lifetime, :wing_price, :rotor_max_surface_speed]),
    ("Kamsarmax bulk carrier", :tubarao, :vlsfo, [:vlsfo_price]),
    ("Kamsarmax bulk carrier", :tubarao, :ammonia, [:e_ammonia_price, :discount_rate,
        :wing_lifetime, :wing_price, :rotor_max_surface_speed])]

"""
    situation_cases(ship, route, drive, input)

Cases of one input of the situation study: every size in `situation_sizes` of each rig
the input changes, and the ship without a rig if it changes that too, at each value of
`situation_inputs`; at the base inputs every rig for `:base`, with value 0.
"""
function situation_cases(ship, route, drive, input)
    values, rigs = input == :base ? ((0.0,), all_rigs) : situation_inputs[input]
    hull = study_hull(ship)
    cases = []
    for value in values, rig in rigs
        for area in (rig == "none" ? (0.0,) : situation_sizes[ship][rig])
            push!(cases, trip_case(ShipDesign(drive, hull; rig_size(rig, area)...);
                assumptions=situation_assumptions(input, value), route, ship, drive, input,
                value, rig, area))
        end
    end
    return cases
end

"""
    situations_data()

The situation study: the cost of every rig size of [`situation_cases`](@ref) at the
base inputs and with one input of each part of `situation_studies` changed at a time:
situations.csv.
"""
function situations_data()
    inputs = Dict{Tuple, Vector{Symbol}}()
    for (ship, route, drive, names) in situation_studies
        append!(get!(inputs, (ship, route, drive), [:base]), names)
    end
    cases = [case for ((ship, route, drive), names) in inputs for input in names
             for case in situation_cases(ship, route, drive, input)]
    write_trips("situations.csv", cases, round_trips(cases, sampled_departures()), :ship,
        :route, :drive, :input, :value, :rig, :area)
end

"ship class and route of each panel of the fuel study: a small ship, a bulk carrier and a
container ship, each on a route of its trade"
fuel_ships = [("general cargo coaster", :bilbao), ("Kamsarmax bulk carrier", :tubarao),
    ("Panamax container ship", :new_york)]

"e-fuels of the fuel study as (price input, drive)"
fuel_drives = [(:e_ammonia_price, :ammonia), (:e_methanol_price, :methanol)]

"""
    swept_values(input)

Values of `input` in the situation study, its base value included, in ascending order.
"""
swept_values(input) = sort([base_value(input); collect(first(situation_inputs[input]))])

"""
    fuel_sizes(classes, class_name, route)

Area [m^2] of each rig of `all_rigs` on `class_name` and `route` in the fuel study: the size
that costs least on e-ammonia in `classes`, the class study's table, and 0 for "none".
"""
fuel_sizes(classes, class_name, route) = Dict(rig => rig == "none" ? 0.0 :
    classes["area"][cheapest_row(classes, class_name, string(route), "ammonia", rig)]
                                              for rig in all_rigs)

"""
    fuel_cases(classes, class, route)

Cases of the fuel study on `class` and `route`: the ship without a rig and with each rig at
its [`fuel_sizes`](@ref), at every [`swept_values`](@ref) of the price of each e-fuel of
`fuel_drives` on its own drive.
"""
function fuel_cases(classes, class, route)
    areas = fuel_sizes(classes, class.name, route)
    return [class_case(class, drive, rig, areas[rig], route;
                assumptions=situation_assumptions(input, value), input, value)
            for (input, drive) in fuel_drives for value in swept_values(input)
            for rig in all_rigs]
end

"""
    fuels_data()

The fuel study: the cost of every case of [`fuel_cases`](@ref) on each ship of
`fuel_ships`: fuels.csv.
"""
function fuels_data()
    classes = read_table(data_file("classes.csv"))
    cases = [case for (name, route) in fuel_ships
             for case in fuel_cases(classes, ship_classes()[name], route)]
    write_trips("fuels.csv", cases, round_trips(cases, sampled_departures()), :class,
        :route, :drive, :input, :value, :rig, :area)
end

"true wind angle bands [deg] of the wind angle study, as (name, lowest, highest)"
angle_bands = (("upwind", 0.0, 60.0), ("beam", 60.0, 120.0), ("downwind", 120.0, 180.0))

"""
    band_name(angle)

Name of the band of `angle_bands` that holds the true wind angle `angle` [rad].
"""
function band_name(angle)
    degrees = rad2deg(angle)
    for (name, _, highest) in angle_bands
        degrees <= highest && return name
    end
    return first(last(angle_bands))
end

"""
    add_leg!(sums, trace, direction)

Add the hours, thrust-hours [kN h] and rig work [GJ] of each point of the `trace` of a
routed leg to `sums`, keyed by `direction` and true-wind-angle band.
"""
function add_leg!(sums, trace, direction)
    for (i, hours) in enumerate(trace.hours)
        thrust = max(trace.rig_thrust[i], 0.0) / 1e3
        key = (direction, band_name(trace.true_wind_angle[i]))
        old = get(sums, key, (0.0, 0.0, 0.0))
        sums[key] = old .+ (hours, thrust * hours, thrust * trace.speed[i] * hours * 3.6e-3)
    end
end

"""
    rig_cost_per_hour(ship, bare, legs, case_assumptions)

Cost of the rig of `ship` per hour at sea [USD/h] over the round trips `legs`: the fixed
annual cost it adds to the `bare` ship, spread over the round trips with their port
calls, plus kite wear and launches; cargo lost to the rig's mass is left out.
"""
function rig_cost_per_hour(ship, bare, legs, case_assumptions)
    port_hours = 24case_assumptions[:port_time_per_call]
    sea_hours = sum(out.duration + back.duration for (out, back) in legs)
    hours = sea_hours + 2port_hours * length(legs)
    fixed = ShipCosts(ship, case_assumptions).fixed_annual -
            ShipCosts(bare, case_assumptions).fixed_annual
    (; rig) = ship
    wear = sum(WindShipOpt.wear_cost(rig, case_assumptions) * leg.flight_hours +
               WindShipOpt.cycle_cost(rig, case_assumptions) * leg.launches
               for pair in legs for leg in pair)
    return (fixed / (8760case_assumptions[:availability]) * hours + wear) / sea_hours
end

"""
    angle_sums(name, rig, area)

Routed round trips over the sampled departures of a 140 m e-ammonia ship with `area`
[m^2] of `rig` on route `name`, as hours, thrust-hours [kN h] and rig work [GJ] per
direction and true-wind-angle band, the rig cost per hour at sea [USD/h], and by departure
number its legs with their [`LegTrace`](@ref)s, `nothing` where a leg fails.
"""
function angle_sums(name, rig, area)
    ship = Ship(ShipDesign(:ammonia, 140.0; rig_size(rig, area)...), assumptions;
        route=name)
    bare = Ship(ShipDesign(:ammonia, 140.0), assumptions; route=name)
    table = PerformanceTable(ship, assumptions)
    out_hourly, back_hourly = WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions),
        assumptions)
    route_table = RouteTable(table)
    sums, legs = Dict{Tuple{String, String}, NTuple{3, Float64}}(), []
    traced = map(sampled_departures()) do departure
        trip = out_and_back(route_table, name, departure, (out_hourly, back_hourly))
        isnothing(trip) && return nothing
        out_trace = LegTrace(table, trip.out, weather, departure)
        back_trace = LegTrace(table, trip.back, weather, trip.back_departure)
        add_leg!(sums, out_trace, "out")
        add_leg!(sums, back_trace, "home")
        push!(legs, (trip.out, trip.back))
        return (; trip..., departure, out_trace, back_trace)
    end
    return sums, rig_cost_per_hour(ship, bare, legs, assumptions), traced
end

"""
    out_and_back(route_table, name, departure, hourly)

The legs `out` and `back` routed on the true weather on route `name` from `departure` [h]
and after the [`turnaround`](@ref), at time costs `hourly` [USD/h] out and back, and the time
`back_departure` [h] the return leaves; `nothing` if either leg fails.
"""
function out_and_back(route_table, name, departure, hourly)
    out_corridor, back_corridor = run_corridors(name)
    out = route(out_corridor, route_table, weather, departure; time_cost=first(hourly))
    isnothing(out) && return nothing
    back_departure = departure + turnaround(route_table, out_corridor)
    back = route(back_corridor, route_table, weather, back_departure;
        time_cost=last(hourly))
    isnothing(back) && return nothing
    return (; out, back, back_departure)
end

"""
    wind_angle_data()

The 140 m e-ammonia ship without a rig and with the reference size of each rig, routed
out and home on every route: hours at sea, thrust-hours [kN h] and rig work [GJ] per
true-wind-angle band summed over the sampled departures, and the rig cost per hour at
sea [USD/h]: wind_angle.csv; and the site's passages of these round trips
([`write_passages`](@ref)).
"""
function wind_angle_data()
    cases = vec([(name, rig, area) for name in route_names,
                 (rig, area) in reference_rigs_and_none])
    results = Vector{Any}(undef, length(cases))
    Threads.@threads :greedy for k in eachindex(cases)
        results[k] = angle_sums(cases[k]...)
    end
    open(run_file("wind_angle.csv"), "w") do io
        println(io, "route,rig,area,direction,band,hours,thrust_hours,work,rig_cost")
        for ((name, rig, area), (sums, rig_cost)) in zip(cases, results)
            for ((direction, band), (hours, thrust_hours, work)) in sort(collect(sums))
                @printf(io, "%s,%s,%.0f,%s,%s,%.2f,%.1f,%.4f,%.2f\n", name, rig, area,
                    direction, band, hours, thrust_hours, work, rig_cost)
            end
        end
    end
    write_passages(cases, last.(results))
end

"""
    track_seasons()

The winter and the summer departure [h] of the routes figure's tracks, by season.
"""
track_seasons() = ("winter" => departures[1],
    "summer" => departures[findfirst(>=(24 * 181), departures)])

"""
    route_tracks_data()

The 140 m e-ammonia ship without a rig and with the reference kite routed out and home on
every route from the [`track_seasons`](@ref): latitude and longitude [°] of each stage of
each leg, in order: route_tracks.csv. Errors where a leg cannot be routed.
"""
function route_tracks_data()
    kite_area = Dict(reference_rigs)["kite"]
    cases = vec([(season, name, area) for season in track_seasons(), name in route_names,
                 area in (0.0, kite_area)])
    trips = Vector{Any}(undef, length(cases))
    Threads.@threads :greedy for k in eachindex(cases)
        (_, departure), name, area = cases[k]
        ship = Ship(ShipDesign(:ammonia, 140.0; kite_area=area), assumptions; route=name)
        hourly = WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions), assumptions)
        trips[k] = out_and_back(RouteTable(PerformanceTable(ship, assumptions)), name,
            departure, hourly)
        isnothing(trips[k]) &&
            error("no round trip on $name from $departure h with $area m^2 of kite")
    end
    open(run_file("route_tracks.csv"), "w") do io
        println(io, "season,departure,route,kite_area,direction,lat,lon")
        for (((season, departure), name, area), trip) in zip(cases, trips)
            for (direction, leg) in (("out", trip.out), ("back", trip.back))
                for (lat, lon) in leg.path
                    @printf(io, "%s,%.0f,%s,%.0f,%s,%.4f,%.4f\n", season, departure,
                        name, area, direction, lat, lon)
                end
            end
        end
    end
end

"""
    passage_data()

The passage ship with each of the [`reference_rigs_and_none`](@ref) routed out to
Guadeloupe from the first departure: latitude and longitude [°] of each stage of its track,
passage_tracks.csv, and time [h], speed [kn], rig thrust [kN] and fuel power [MW] at each
sample of its [`LegTrace`](@ref), passage_traces.csv. Errors where a passage fails.
"""
function passage_data()
    rigs = reference_rigs_and_none
    ships = [Ship(passage_ship_design(rig, area), assumptions) for (rig, area) in rigs]
    outbound = first(run_corridors(:caribbean))
    departure = departures[1]
    legs = Vector{Any}(undef, length(rigs))
    Threads.@threads :greedy for k in eachindex(rigs)
        table = PerformanceTable(ships[k], assumptions)
        hourly = first(WindShipOpt.leg_time_costs(ShipCosts(ships[k], assumptions),
            assumptions))
        leg = route(outbound, table, weather, departure; time_cost=hourly)
        isnothing(leg) && error("no passage to Guadeloupe with the $(rigs[k])")
        legs[k] = (; leg, trace=LegTrace(table, leg, weather, departure))
    end
    open(run_file("passage_tracks.csv"), "w") do io
        println(io, "rig,area,lat,lon")
        for ((rig, area), (; leg)) in zip(rigs, legs), (lat, lon) in leg.path
            @printf(io, "%s,%.0f,%.4f,%.4f\n", rig, area, lat, lon)
        end
    end
    open(run_file("passage_traces.csv"), "w") do io
        println(io, "rig,area,time,speed,rig_thrust,fuel_power")
        for ((rig, area), (; trace)) in zip(rigs, legs), i in eachindex(trace.time)
            @printf(io, "%s,%.0f,%.4f,%.4f,%.4f,%.5f\n", rig, area, trace.time[i],
                trace.speed[i] / KNOT, trace.rig_thrust[i] / 1e3,
                trace.fuel_power[i] / 1e6)
        end
    end
end

"""
    canopy_tension_data()

Tether tension [N] and duration [s] of each step of one optimal cycle of the reference kite
at apparent wind `wind` and `course` without side force: canopy_tension_history.csv.
"""
function canopy_tension_data(; wind=12.0, course=90.0)
    area = Dict(reference_rigs)["kite"]
    model, max_force, _ = WindShipOpt.kite_model(area, 3.0, assumptions)
    min_elevation = deg2rad(assumptions[:kite_min_elevation])
    _, path = best_pattern_cycle(model, max_force, min_elevation, wind, course, 0.0)
    open(run_file("canopy_tension_history.csv"), "w") do io
        println(io, "wind,course,time,duration,tension")
        time = 0.0
        for step in path
            @printf(io, "%.0f,%.0f,%.2f,%.3f,%.0f\n", wind, course, time, step.time,
                step.tension)
            time += step.time
        end
    end
end

"""
    call_hours(ship, trip, case_assumptions)

Hours [h] of one port call of `ship` on `trip`, with the delay of a rig fixed on deck.
"""
function call_hours(ship, trip, case_assumptions)
    hours = 24case_assumptions[:port_time_per_call]
    trip.retractable && return hours
    return hours + WindShipOpt.fixed_rig_port_hours(ship.rig, ship.design.class,
        case_assumptions)
end

"""
    trip_hours(ship, trip, case_assumptions)

Hours [h] of the round trip `trip` of `ship`, at sea and in its two port calls.
"""
trip_hours(ship, trip, case_assumptions) = 24(trip.outbound_days + trip.return_days) +
                                         2call_hours(ship, trip, case_assumptions)

"""
    cost_parts(ship, trip, case_assumptions)

Fuel, kite wear, port, crew, capital and maintenance with the fuel store, and cargo
interest per round trip [USD] of `trip`.
"""
function cost_parts(ship, trip, case_assumptions)
    costs = WindShipOpt.ShipCosts(ship, case_assumptions; trip.retractable)
    port_hours = call_hours(ship, trip, case_assumptions)
    sea_hours = 24(trip.outbound_days + trip.return_days)
    hours = trip_hours(ship, trip, case_assumptions)
    trading_hours = 8760case_assumptions[:availability]
    store = WindShipOpt.store_round_trip_cost(trip.capital - costs.capital,
        sea_hours + 48case_assumptions[:port_time_per_call], case_assumptions)
    size = costs.hold.deadweight / case_assumptions[:newbuild_reference_deadweight]
    crew = case_assumptions[:crew_cost] * size^case_assumptions[:crew_cost_exponent]
    passages = (24trip.outbound_days, 24trip.return_days, port_hours)
    interest = WindShipOpt.voyage_time_cost(costs, case_assumptions, trip.cargo,
                   passages...) -
               WindShipOpt.voyage_time_cost(costs, case_assumptions, 0.0, passages...)
    return (fuel=1e9trip.fuel_energy * ship.fuel.price,
        wear=WindShipOpt.wear_cost(ship.rig, case_assumptions) * trip.flight_share *
             sea_hours +
             WindShipOpt.cycle_cost(ship.rig, case_assumptions) * trip.launches,
        port=WindShipOpt.port_costs(ship.hull, case_assumptions),
        crew=crew / trading_hours * hours,
        capital=(costs.fixed_annual - crew) / trading_hours * hours + store,
        interest)
end

"columns [`write_costs`](@ref) writes: round-trip hours and the cost parts [USD/tkm]"
cost_columns = ["hours", "fuel_cost", "wear_cost", "port_cost", "crew_cost",
    "capital_cost", "interest_cost"]

"""
    write_costs(io, case, trip, tonne_km)

The [`cost_columns`](@ref) of `trip` of `case` over its `tonne_km`, each after a comma,
ending the row.
"""
function write_costs(io, case, trip, tonne_km)
    ship = Ship(case.design, case.assumptions; case.route)
    @printf(io, ",%.2f", trip_hours(ship, trip, case.assumptions))
    for part in cost_parts(ship, trip, case.assumptions)
        @printf(io, ",%.6f", part / tonne_km)
    end
    println(io)
end

"""
    tonne_km_per_tonne(outbound, inbound)
    tonne_km_per_tonne(name)

Tonne-km per tonne of outbound cargo of a round trip out along `outbound` and back along
`inbound`, or on route `name`, with the backhaul share of the return leg.
"""
function tonne_km_per_tonne(outbound, inbound)
    return (outbound.track_length +
            assumptions[:backhaul_fraction] * inbound.track_length) / 1e3
end

tonne_km_per_tonne(name) = tonne_km_per_tonne(run_corridors(name)...)

"""
    designs_data()

The design grid on the route to Guadeloupe: length, the [`study_drives`](@ref) and size of
each rig, and kites without flight drag, with the cost per tonne-km split into its parts:
designs.csv.
"""
function designs_data()
    rigid = with_value(assumptions, :kite_flight_drag, 0.0)
    cases = []
    for length in (85.0, 110.0, 140.0, 170.0, 200.0), drive in study_drives,
        area in (0.0, 400.0, 800.0, 1600.0, 3200.0, 6400.0)

        push!(cases, trip_case(ShipDesign(drive, length; kite_area=area); scenario="base"))
    end
    for length in (85.0, 140.0, 200.0), drive in study_drives,
        (rig, areas) in (("wings", (400.0, 800.0, 1500.0, 3000.0)),
            ("rotors", (200.0, 400.0, 800.0, 1600.0))), area in areas

        push!(cases, trip_case(ShipDesign(drive, length; rig_size(rig, area)...);
            scenario="base"))
    end
    for length in (140.0, 200.0), drive in (:vlsfo, :ammonia), area in (800.0, 3200.0)
        push!(cases, trip_case(ShipDesign(drive, length; kite_area=area);
            assumptions=rigid, scenario="rigid"))
    end
    trips = round_trips(cases, sampled_departures())
    work_per_tonne = tonne_km_per_tonne(:caribbean)
    open(run_file("designs.csv"), "w") do io
        println(io, "scenario,drive,length,kite_area,kite_aspect_ratio,wing_area,",
            "rotor_area,cost,fuel,carbon,outbound_days,return_days,cargo,capital,",
            "flight_share,launches,", join(cost_columns, ","))
        for (case, trip) in zip(cases, trips)
            isnothing(trip) && continue
            write_design(io, case, trip, work_per_tonne)
        end
    end
end

"""
    write_design(io, case, trip, work_per_tonne)

One row of designs.csv, with the tonne-km per tonne of cargo `work_per_tonne`.
"""
function write_design(io, case, trip, work_per_tonne)
    (; design) = case
    @printf(io, "%s,%s,%.0f,%.0f,%.0f,%.0f,%.0f,%.6f,%.5f,%.3f,%.2f,%.2f,%.0f,%.0f,",
        case.scenario, design.drive, design.length, design.kite_area,
        WindShipOpt.kite_aspect_ratio(design, case.assumptions), design.wing_area,
        design.rotor_area,
        trip.cost_per_tonne_km, trip.fuel_per_tonne_km, trip.carbon_per_tonne_km,
        trip.outbound_days, trip.return_days, trip.cargo, trip.capital)
    @printf(io, "%.3f,%.2f", trip.flight_share, trip.launches)
    write_costs(io, case, trip, trip.cargo * work_per_tonne)
end

"""
    routes_data()

Ships of three lengths and the [`study_drives`](@ref) without a rig and with two sizes of
each rig on every route: routes.csv, and each departure of them: route_departures.csv.
"""
function routes_data()
    rigs = [("none", 0.0), ("kite", 800.0), ("kite", 3200.0), ("wings", 800.0),
        ("wings", 1500.0), ("rotors", 400.0), ("rotors", 800.0)]
    cases = vec([trip_case(ShipDesign(drive, length; rig_size(rig, area)...); route=name,
                     drive, length, rig, area)
                 for length in (85.0, 140.0, 200.0), drive in study_drives,
                     (rig, area) in rigs, name in route_names])
    trips = round_trips(cases, sampled_departures())
    labels = (:route, :drive, :length, :rig, :area)
    write_trips("routes.csv", cases, trips, labels...)
    write_departures("route_departures.csv", cases, trips, labels...)
end

"""
    write_departures(name, cases, trips, columns...)

Write `name` to the directory of the run in use with the given label `columns` of each
case and the date, cost [USD/tkm], fuel [MJ/tkm] and kite flight share of each departure of
each feasible trip, with the ship and cargo of the whole trip.
"""
function write_departures(name, cases, trips, columns...)
    open(run_file(name), "w") do io
        println(io, join([collect(string.(columns)); ["date", "cost", "fuel",
            "flight_share"]], ","))
        for (case, trip) in zip(cases, trips)
            isnothing(trip) && continue
            labels = join([csv_value(getproperty(case, column)) for column in columns], ",")
            for outcome in trip.departures
                date = Date(weather_origin + Hour(round(Int, outcome.departure)))
                @printf(io, "%s,%s,%.6f,%.5f,%.3f\n", labels, date,
                    outcome.cost_per_tonne_km, outcome.fuel_per_tonne_km,
                    outcome.flight_share)
            end
        end
    end
end

"unit of the wings, suction sails or rotors `rig`, as the model names it"
deck_unit(rig) = rig == "rotors" ? :rotor : rig == "suction" ? :suction : :wing

"""
    deck_rig(rig, area, hull; forward_reserve=0, columns=1, in_column=1)

The wings, suction sails or rotors `rig` of `area` [m^2] in all on `hull` behind
`forward_reserve` [m] of deck, `columns` times `in_column` units, or `nothing` where they do
not fit.
"""
function deck_rig(rig, area, hull; forward_reserve=0.0, columns=1, in_column=1)
    layout = (; forward_reserve, columns, in_column)
    rig == "rotors" && return WindShipOpt.RotorRig(area, hull, assumptions; layout...)
    return WingRig(area, hull, assumptions; unit=deck_unit(rig), layout...)
end

"""
    deck_rig_fits(rig, area, hull; forward_reserve=0)

Whether the wings, suction sails or rotors `rig` of `area` [m^2] in all fit on `hull`
behind `forward_reserve` [m] of deck in any of their [`layout_counts`](@ref).
"""
deck_rig_fits(rig, area, hull; forward_reserve=0.0) =
    any(!isnothing(deck_rig(rig, area, hull; forward_reserve, columns, in_column))
        for (columns, in_column) in WindShipOpt.layout_counts(area, deck_unit(rig), hull,
            assumptions, forward_reserve))

"""
    largest_area(rig, hull; forward_reserve=0)

Largest total area [m^2], up to 20,000 m^2, of the wings, suction sails or rotors `rig`
that fit on `hull` behind `forward_reserve` [m] of deck ([`deck_rig_fits`](@ref)), to the
nearest 10 m^2.
"""
function largest_area(rig, hull; forward_reserve=0.0)
    low, high = 0.0, 20000.0
    while high - low > 10
        middle = (low + high) / 2
        deck_rig_fits(rig, middle, hull; forward_reserve) ? (low = middle) : (high = middle)
    end
    return low
end

"smallest area [m^2] of wings, suction sails or rotors a size search tries"
smallest_deck_rig_area = 50.0

"""
    size_bounds(class)

Smallest and largest area [m^2] searched for each rig on `class`: kites of 500 to
64,000 m^2, VTOL kites of 20 m^2 to the largest whose perch fits, leading-edge inflatable
kites of 20 m^2 to the largest that can be launched, deck rigs from
`smallest_deck_rig_area` to all of what fits on deck, and none of a rig where not even its
smallest size fits.
"""
function size_bounds(class)
    hull = Hull(class, assumptions)
    smallest = Dict("vtol" => 20.0, "lei" => 20.0,
        (rig => smallest_deck_rig_area for rig in deck_rig_names)...)
    bounds = (rig => (area, largest_rig_area(rig, hull)) for (rig, area) in smallest)
    return Dict("kite" => (500.0, largest_rig_area("kite", hull)),
        (rig => (lower, upper) for (rig, (lower, upper)) in bounds if lower <= upper)...)
end

"guessed cheapest rig sizes of the class study, data/size_guesses.csv"
size_guess_file = joinpath(@__DIR__, "..", "data", "size_guesses.csv")

"""
    size_guesses()

Guessed cheapest area [m^2] of each rig on each ship class and route, keyed by class name,
rig and route, from `size_guess_file`.
"""
function size_guesses()
    table = read_table(size_guess_file)
    return Dict((class, rig, Symbol(route)) => area for (class, rig, route, area) in
                zip(table["class"], table["rig"], table["route"], table["area"]))
end

"""
    write_size_guesses(table)

Write to `size_guess_file` the cheapest area of each rig on each class and route on the
headline drive, the last of [`study_drives`](@ref), in the class table `table`.
"""
function write_size_guesses(table)
    drive = string(last(study_drives))
    searches = unique(zip(table["class"], table["rig"], table["route"]))
    open(size_guess_file, "w") do io
        println(io, "class,rig,route,area")
        for (class, rig, route) in sort(filter(search -> search[2] != "none", searches))
            row = cheapest_row(table, class, route, drive, rig)
            isnothing(row) || println(io, csv_value(class), ",", rig, ",", route, ",",
                table["area"][row])
        end
    end
end

"""
    largest_rig_area(rig, hull)

Largest area [m^2] of `rig` on `hull`: what fits on deck, for a kite the search bound, for
a leading-edge inflatable kite the largest that can be launched.
"""
function largest_rig_area(rig, hull)
    rig == "kite" && return 64000.0
    rig == "vtol" && return WindShipOpt.largest_rigid_kite_area(hull, assumptions)
    rig == "lei" && return WindShipOpt.largest_lei_kite_area(assumptions)
    return largest_area(rig, hull)
end

"""
    class_case(class, drive, rig, area, route; labels...)

Round-trip case of `class` with `drive` and `area` [m^2] of `rig` ("none" for no rig)
on `route`, tagged with `labels`.
"""
function class_case(class::ShipClass, drive, rig, area, route; labels...)
    design = ShipDesign(drive, class; rig_size(rig, area)...)
    built = Ship(design, assumptions; route).rig
    return trip_case(design; class=class.name, route, drive, rig, area,
        units=WindShipOpt.deck_units(built), columns=deck_columns(built), labels...)
end

"name in the output of the wings, suction sails or rotors `rig`"
deck_rig_name(rig::WingRig) = rig.unit == :suction ? "suction" : "wings"
deck_rig_name(::WindShipOpt.RotorRig) = "rotors"

"columns the wings or rotors of `rig` stand in, 0 for a rig without them"
deck_columns(rig::Union{WingRig, WindShipOpt.RotorRig}) = rig.columns
deck_columns(::Union{WindShipOpt.KiteRig, Nothing}) = 0

"""
    classes_data()

The standard ship classes on every route with the [`study_drives`](@ref) without a rig,
and with the cheapest size of each rig found by [`searched_sizes`](@ref): classes.csv, and
each departure of them: class_departures.csv.
"""
function classes_data()
    ships = [(class, drive, route)
             for class in values(ship_classes()), drive in study_drives,
                 route in route_names]
    cases, trips = searched_sizes(vec(ships))
    labels = (:class, :route, :drive, :rig, :area, :units)
    write_trips("classes.csv", cases, trips, labels...)
    write_departures("class_departures.csv", cases, trips, labels...)
end

"""
    class_cases(table)

Round-trip case of each row of a class table `table`.
"""
function class_cases(table)
    classes = ship_classes()
    return [class_case(classes[table["class"][k]], Symbol(table["drive"][k]),
                table["rig"][k], table["area"][k], Symbol(table["route"][k]))
            for k in eachindex(table["class"])]
end

"""
    today_data()

The cost [USD/tkm] of every design of classes.csv with each goal at its value known today,
on the routes the class study found at the goals: classes_today.csv.
"""
function today_data()
    cases = class_cases(read_table(data_file("classes.csv")))
    trips = round_trips(cases, sampled_departures())
    today = at_today(assumptions)
    labels = (:class, :route, :drive, :rig, :area)
    open(run_file("classes_today.csv"), "w") do io
        println(io, join([collect(string.(labels)); "cost"], ","))
        for (case, trip) in zip(cases, trips)
            isnothing(trip) && continue
            cost = changed_cost(merge(case, (; assumptions=today)), trip)
            fields = [csv_value(getproperty(case, label)) for label in labels]
            println(io, join(fields, ","), @sprintf(",%.6f", cost))
        end
    end
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
    changed_cost(case, trip)

Cost per tonne-km [USD] of `case` at its inputs on the routes of `trip`, routed at the
base inputs, its ship laid out as it was routed.
"""
function changed_cost(case, trip)
    ship = Ship(case.design, assumptions; case.route)
    costs = WindShipOpt.ship_costs(ship, case.assumptions)
    return recosted(ship, costs, trip, case, case.assumptions)
end

"""
    class_table()

Columns of classes.csv with the cost [USD/tkm] of each departure of each row, in date order,
as the column `"departure_costs"`, from the class_departures.csv of the same run.
"""
function class_table()
    path = data_file("classes.csv")
    table = read_table(path)
    departures = read_table(joinpath(dirname(path), "class_departures.csv"))
    key(columns, i) = Tuple(columns[name][i] for name in ("class", "route", "drive", "rig",
        "area"))
    dated = Dict{Tuple, Vector{Tuple{String, Float64}}}()
    for i in eachindex(departures["cost"])
        push!(get!(dated, key(departures, i), []), (departures["date"][i],
            departures["cost"][i]))
    end
    table["departure_costs"] = [last.(sort(dated[key(table, i)]))
                                for i in eachindex(table["cost"])]
    return table
end

"""
    rows(table, conditions...)

Indices of the rows of `table` where each `column => value` condition holds, `value`
being a value to equal or a predicate to meet.
"""
function rows(table, conditions...)
    chosen = trues(length(first(values(table))))
    for (column, value) in conditions
        chosen .&= value isa Function ? value.(table[column]) : table[column] .== value
    end
    return findall(chosen)
end

"""
    percent_saving(cost, reference)

Saving [%] of `cost` against `reference`.
"""
percent_saving(cost, reference) = 100 * (1 - cost / reference)

"""
    rig_savings(table, rigs, conditions...)

Cost saving [%] of the best size of each of `rigs` against no rig among the rows of
`table` where the `conditions` hold, as a Dict of rig name to saving; missing rigs are
left out.
"""
function rig_savings(table, rigs, conditions...)
    base = rows(table, conditions..., "rig" => "none")
    savings = Dict{String, Float64}()
    isempty(base) && return savings
    reference = only(table["cost"][base])
    for rig in rigs
        chosen = rows(table, conditions..., "rig" => rig)
        isempty(chosen) && continue
        savings[rig] = percent_saving(minimum(table["cost"][chosen]), reference)
    end
    return savings
end

"""
    cheapest_row(table, filters::Pair...)
    cheapest_row(table, class, route, drive, rig)

Row of `table` with the lowest cost among those matching `filters`, column => value, or of
`rig` for one class, route and drive; `nothing` where none was run.
"""
function cheapest_row(table, filters::Pair...)
    chosen = rows(table, filters...)
    return isempty(chosen) ? nothing : chosen[argmin(table["cost"][chosen])]
end

cheapest_row(table, class, route, drive, rig) = cheapest_row(table, "class" => class,
    "route" => route, "drive" => drive, "rig" => rig)

"""
Points by which the router understates the kite's cost saving against a deck rig's: the
kite's lead over the rotors at the results' grid against the converged grid, extrapolated
on the development case, the same on either fuel
"""
kite_gap_bias = 1.6

"""
    lead_factor(n)

Quantile of Student's t with `n - 1` degrees of freedom at the coverage of one standard
deviation, by the expansion of Abramowitz and Stegun (1964), 26.7.5.
"""
function lead_factor(n)
    ν = n - 1
    return 1 + 1 / 2ν + 1 / 4ν^2 + 1 / 16ν^3 - 11 / 1920ν^4
end

"""
    leads(rig, rival, gap, (error, n))

Whether `rig` saves clearly more than `rival` ("none" for no rig): its `gap` [points] of
cost saving over it exceeds the `error` [points] of that gap over `n` departures times the
[`lead_factor`](@ref), plus the [`kite_gap_bias`](@ref) where `rival` is the kite.
"""
function leads(rig, rival, gap, (error, n))
    return gap > lead_factor(n) * error + (rival == "kite" ? kite_gap_bias : 0.0)
end

"""
    departure_saving(cell, rig, departures)

Cost saving [%] of `rig` on the fleet `cell` over the indices `departures` of its
departures; zero for `"none"`.
"""
function departure_saving(cell, rig, departures)
    rig == "none" && return 0.0
    costs = cell.departures
    return percent_saving(sum(costs[rig][departures]), sum(costs["none"][departures]))
end

"""
    gap_error(cells, weights, rig, rival)

Jackknife standard error [points] over the shared departures of fleet `cells` of the
`weights`-weighted mean over them of the cost saving of `rig` less that of `rival`, and the
number of departures.
"""
function gap_error(cells, weights, rig, rival)
    n = length(first(cells).departures["none"])
    gap(departures) = sum(weight * (departure_saving(cell, rig, departures) -
                                    departure_saving(cell, rival, departures))
                          for (cell, weight) in zip(cells, weights)) / sum(weights)
    return jackknife_error(gap, n), n
end

"bands of the fleet's cost split by rig, in the order drawn"
fleet_bands = ("kite", "level", "rotors", "wings", "suction", "vtol", "lei", "none")

"""
    fleet_leaders(savings, cells, weights=ones(length(cells)))

Rigs of the cost `savings` [%], each the `weights`-weighted mean over fleet `cells`, that
are level with the best: the best and each rig it does not clearly [`leads`](@ref); none
where the best does not clearly save.
"""
function fleet_leaders(savings, cells, weights=ones(length(cells)))
    best = argmax(rig -> savings[rig], keys(savings))
    clear(rival) = leads(best, rival, savings[best] - get(savings, rival, 0.0),
        gap_error(cells, weights, best, rival))
    clear("none") || return String[]
    return [rig for rig in keys(savings) if rig == best || !clear(rig)]
end

"""
    fleet_band(cell)

Band of [`fleet_bands`](@ref) of a fleet `cell`: its one [`fleet_leaders`](@ref) rig,
`"level"` where there are more and `"none"` where there are none.
"""
function fleet_band(cell)
    leaders = fleet_leaders(cell.savings, [cell])
    isempty(leaders) && return "none"
    return length(leaders) > 1 ? "level" : only(leaders)
end

"""
    fleet_split(cells)

Cost and saving [USD a year] of each band of [`fleet_bands`](@ref) over fleet `cells`.
A cell in the band `"none"` saves nothing, as no rig is fitted.
"""
function fleet_split(cells)
    split = Dict(band => (bill=0.0, saved=0.0) for band in fleet_bands)
    for cell in cells
        band = fleet_band(cell)
        best = argmax(rig -> cell.savings[rig], keys(cell.savings))
        saved = band == "none" ? 0.0 : cell_saved(cell, best)
        split[band] = (bill=split[band].bill + cell.bill, saved=split[band].saved + saved)
    end
    return split
end

"""
    cell_saved(cell, rig)

Yearly cost [USD] `rig` saves on a fleet cell with the `bill` [USD a year] of the cell
without a rig and the cost `savings` [%] of its rigs.
"""
cell_saved(cell, rig) = cell.bill * cell.savings[rig] / 100

"each rig with its area column in designs.csv"
rig_area_columns = (("kite", "kite_area"), ("wings", "wing_area"), ("rotors", "rotor_area"))

"""
    best_cost(designs, drive, length, column_name)

Lowest cost per tonne-km on the route to Guadeloupe of the base designs of one drive and
length with the rig of `column_name` (any size), or without a rig for `nothing`; `NaN`
where none was run.
"""
function best_cost(designs, drive, length, column_name)
    k = cheapest_design(designs, drive, length, column_name)
    return isnothing(k) ? NaN : designs["cost"][k]
end

"""
    fuel_premium(designs, drive, length, column_name)

How much more [%] the best design of `drive` with the rig of `column_name`, or without a
rig for `nothing`, costs per tonne-km than the one on VLSFO without a rig, at one length.
"""
function fuel_premium(designs, drive, length, column_name)
    fossil = best_cost(designs, "vlsfo", length, nothing)
    return 100 * (best_cost(designs, drive, length, column_name) / fossil - 1)
end

"""
    premium_closed(designs, drive, length, column_name)

Share [%] of the [`fuel_premium`](@ref) of `drive` without a rig, at one ship length, that
the best size of the rig of `column_name` closes.
"""
premium_closed(designs, drive, length, column_name) =
    100 * (1 - fuel_premium(designs, drive, length, column_name) /
               fuel_premium(designs, drive, length, nothing))

"""
    cheapest_design(designs, drive, length, column)

Row of designs.csv with the lowest cost among the base designs of `drive` and `length`
that carry only the rig of area `column`, or none for `nothing`; `nothing` if there is
none.
"""
function cheapest_design(designs, drive, length, column)
    chosen = [k for k in rows(designs, "scenario" => "base", "drive" => drive,
                  "length" => length)
              if all((name == column) == (designs[name][k] > 0)
                     for (_, name) in rig_area_columns)]
    isempty(chosen) && return nothing
    return chosen[argmin(designs["cost"][chosen])]
end

"""
    write_table(name; columns...)

Write the equal-length `columns` to `name` in the directory of the run in use, headed by
their names; integers and booleans as integers, other numbers to four decimals.
"""
function write_table(name; columns...)
    open(run_file(name), "w") do io
        println(io, join(keys(columns), ","))
        for row in zip(values(columns)...)
            println(io, join(table_field.(row), ","))
        end
    end
end

"`value` as a field of [`write_table`](@ref)"
table_field(value::Integer) = string(Int(value))
table_field(value::Real) = @sprintf("%.4f", value)

"""
    read_table(path)

Columns of a CSV file with a header line, as a Dict of name to vector; numbers parsed
and quotes removed.
"""
function read_table(path)
    lines = readlines(path)
    names = WindShipOpt.csv_fields(first(lines))
    rows = [WindShipOpt.csv_fields(line) for line in lines[2:end]]
    table = Dict{String, Vector}()
    for (k, name) in enumerate(names)
        values = getindex.(rows, k)
        numbers = tryparse.(Float64, values)
        table[name] = any(isnothing, numbers) ? String.(values) : Float64.(numbers)
    end
    return table
end

"""
    fleet_total(split, measure)

Sum over the [`fleet_bands`](@ref) of `measure` (`:bill` or `:saved`) of a
[`fleet_split`](@ref).
"""
fleet_total(split, measure) = sum(getfield(split[band], measure) for band in fleet_bands)

"""
    fleet_work()

The 2018 transport work [tonne-km a year] of each ship class from its IMO size bins, and
the part of the work of all IMO bins in data/market that these carry.
"""
function fleet_work()
    market = joinpath(pkgdir(WindShipOpt), "data", "market")
    imo = read_table(joinpath(market, "imo_ghg4_transport_work_by_type_size.csv"))
    work = Dict(zip(zip(imo["ship_type"], imo["size_bin"]), imo["transport_work"]))
    bins = read_table(joinpath(market, "fleet_work_bins.csv"))
    classes = Dict{String, Float64}()
    for (class, bin) in zip(bins["class"], zip(bins["ship_type"], bins["size_bin"]))
        classes[class] = get(classes, class, 0.0) + work[bin]
    end
    share = sum(values(classes)) / sum(values(work))
    return Dict(class => WindShipOpt.NAUTICAL_MILE * 1e6 * billion
                for (class, billion) in classes), share
end

"""
    fleet_ships()

Ships of each class in its IMO size bins in 2018, the `fleet` of data/ship_classes.csv.
"""
function fleet_ships()
    classes = read_table(joinpath(pkgdir(WindShipOpt), "data", "ship_classes.csv"))
    return Dict(zip(classes["name"], classes["fleet"]))
end

"""
    fleet_cells(table, drive)

Each class and route of class table `table` on `drive`, with the class's transport work
[tonne-km a year] from [`fleet_work`](@ref) and its ships from [`fleet_ships`](@ref) shared
equally over the table's routes, the yearly cost `bill` [USD] of that work without a rig,
the row of the ship without a rig and of the best size of each rig the table holds, their cost
`savings` [%] and the cost of each of their `departures` by rig, `"none"` included, or
nothing where the table holds no departures.
Errors naming every class and route of `drive` the table lacks a result of a rig for.
"""
function fleet_cells(table, drive)
    work, _ = fleet_work()
    ships = fleet_ships()
    routes = unique(table["route"])
    cells, absent = [], String[]
    for class in keys(work), route in routes
        bare = cheapest_row(table, class, route, drive, "none")
        best = Dict(rig => cheapest_row(table, class, route, drive, rig)
                    for (_, rig) in study_rigs(table))
        if isnothing(bare) || any(isnothing, values(best))
            push!(absent, "$class on $route")
            continue
        end
        share = work[class] / length(routes)
        reference = table["cost"][bare]
        savings = Dict(rig => percent_saving(table["cost"][row], reference)
                       for (rig, row) in best)
        departures = haskey(table, "departure_costs") ?
                     Dict(rig => table["departure_costs"][row]
                          for (rig, row) in ("none" => bare, best...)) : nothing
        push!(cells, (; class, route, work=share, ships=ships[class] / length(routes),
            bill=share * reference, bare, best, savings, departures))
    end
    isempty(absent) || throw(ArgumentError("no $drive results for " * join(absent, ", ")))
    return cells
end

"""
    fleet_split_of(table, drive)

The [`fleet_split`](@ref) of the [`fleet_cells`](@ref) of class table `table` on `drive`.
"""
fleet_split_of(table, drive) = fleet_split(fleet_cells(table, drive))

"""
    shown_rigs(cells)

Rigs, in the order of [`rig_names`](@ref), among the [`fleet_leaders`](@ref) of at least
one of fleet `cells`.
"""
function shown_rigs(cells)
    leaders = union(String[], (fleet_leaders(cell.savings, [cell]) for cell in cells)...)
    return [rig for rig in rig_names if rig in leaders]
end

"""
    trailing_rigs(cells)

Each rig of fleet `cells` not among their [`shown_rigs`](@ref), in the order of
[`rig_names`](@ref), with its highest cost `saving` [%] over them and its smallest `gap`
[points] to the best rig of a cell.
"""
function trailing_rigs(cells)
    shown = shown_rigs(cells)
    return [(; rig, saving=maximum(cell.savings[rig] for cell in cells),
                gap=minimum(maximum(values(cell.savings)) - cell.savings[rig]
                            for cell in cells))
            for rig in rig_names if haskey(first(cells).savings, rig) && rig ∉ shown]
end

"[`fleet_cells`](@ref) of class table `table` on each drive it holds"
all_fleet_cells(table) =
    reduce(vcat, [fleet_cells(table, drive) for drive in unique(table["drive"])])

"""
    compared_table(table=class_table())

Rows of class table `table` of the ship without a rig and of the [`shown_rigs`](@ref) of
its fleet cells on every drive.
"""
function compared_table(table=class_table())
    shown = ("none", shown_rigs(all_fleet_cells(table))...)
    return table_rows(table, rows(table, "rig" => in(shown)))
end

"""
    searched_sizes(ships)

Cases and round trips of each (class, drive, route) of `ships` without a rig and of the
search for the cheapest size of each rig ([`searched_rigs!`](@ref)): on the headline drive,
the last of [`study_drives`](@ref), from its [`size_guesses`](@ref); on another drive from
the cheapest size the headline drive's search found for the same ship, rig and route,
where `ships` holds it, else from the guess as well.
"""
function searched_sizes(ships)
    headline = last(study_drives)
    on_headline = Set((class, route)
                      for (class, drive, route) in ships if drive == headline)
    follows = [drive != headline && (class, route) in on_headline
               for (class, drive, route) in ships]
    cases = Any[class_case(class, drive, "none", 0.0, route; round=0)
                for (class, drive, route) in ships]
    trips = round_trips(cases, sampled_departures())
    guesses = size_guesses()
    found = searched_rigs!(cases, trips, ships[.!follows],
        key -> guessed_size(guesses, key...))
    searched_rigs!(cases, trips, ships[follows],
        ((class, drive, rig, route),) -> found[(class, headline, rig, route)])
    return cases, trips
end

"""
    guessed_size(guesses, class, drive, rig, route)

Area [m^2] of `rig` on `class` and `route` in `guesses` of [`size_guesses`](@ref), or the
geometric middle of its [`size_bounds`](@ref) where they hold none.
"""
guessed_size(guesses, class, drive, rig, route) =
    get(() -> sqrt(prod(size_bounds(class)[rig])), guesses, (class.name, rig, route))

"""
    searched_rigs!(cases, trips, ships, guess)

Search the cheapest size of each rig of [`size_bounds`](@ref) on each (class, drive, route)
of `ships`, adding the cases tried and their round trips to `cases` and `trips`: the
[`start_sizes`](@ref) about the area `guess` gives for each (class, drive, rig, route),
then in rounds the [`next_size`](@ref) of every search until each is confirmed. Each case
is tagged with the `round` that added it, 0 for the starting sizes. Returns the cheapest
area [m^2] of each search.
"""
function searched_rigs!(cases, trips, ships, guess)
    grids = Dict((class, drive, rig, route) => size_grid(bounds...)
                 for (class, drive, route) in ships for (rig, bounds) in size_bounds(class))
    batch = [class_case(key[1:3]..., area, key[4]; round=0)
             for (key, grid) in grids for area in start_sizes(guess(key), grid)]
    searches = Dict(key => Tuple{Float64, Float64}[] for key in keys(grids))
    round = 0
    while !isempty(batch)
        append!(trips, round_trips(batch, sampled_departures()))
        append!(cases, batch)
        record_sizes!(searches, cases, trips)
        round += 1
        batch = []
        for (key, points) in searches
            area = next_size(points, grids[key])
            isnothing(area) || push!(batch, class_case(key[1:3]..., area, key[4]; round))
        end
    end
    return Dict(key => first(points[argmin(last.(points))]) for (key, points) in searches)
end

"""
    record_sizes!(searches, cases, trips)

Fill each size search, keyed by ship class, drive, rig and route, with the (area, cost)
of every case run for it; infeasible trips cost `Inf`.
"""
function record_sizes!(searches, cases, trips)
    foreach(empty!, values(searches))
    for (case, trip) in zip(cases, trips)
        key = (case.design.class, case.drive, case.rig, case.route)
        haskey(searches, key) || continue
        push!(searches[key], (case.area, isnothing(trip) ? Inf : trip.cost_per_tonne_km))
    end
end

"""
Cargo values [USD/t] of the cargo value sweep, those of the classes' iron ore, crude oil,
general cargo, containers and cars, and the deadweight-limited and the space-limited class
that carry each of them in turn.
"""
cargo_value_sweep = (
    values=Tuple(ship_classes()[name].cargo_value for name in ("Capesize bulk carrier",
        "Aframax tanker", "general cargo coaster", "Neo-Panamax container ship",
        "PCTC car carrier")),
    classes=("Kamsarmax bulk carrier", "Neo-Panamax container ship"))

"""
    swept_cargo_values(table)

Cargo values [USD/t] of the cargo value sweep in the cargo_interest.csv `table`: those
that every class of [`cargo_value_sweep`](@ref) carries.
"""
function swept_cargo_values(table)
    carried = [table["cargo_value"][rows(table, "class" => class)]
               for class in cargo_value_sweep.classes]
    return sort(intersect(carried...))
end

"""
    with_cargo_value(class, value)

Ship `class` carrying cargo of `value` [USD/t].
"""
function with_cargo_value(class, value)
    return ShipClass(; (name => getfield(class, name) for name in fieldnames(ShipClass))...,
        cargo_value=value)
end

"""
    cargo_interest_factors()

Factors on a class's cargo value, `low` and `high`, that price the interest on its cargo
at the low and the high bound of the discount rate.
"""
function cargo_interest_factors()
    rate = assumptions.entries[:discount_rate]
    return (low=rate.low / rate.value, high=rate.high / rate.value)
end

"""
    interest_level_rows(table, factor)

The rows of `table`, a cargo_interest.csv, of each class carrying cargo worth its own
value times `factor`.
"""
function interest_level_rows(table, factor)
    classes = ship_classes()
    kept = [k for (k, class) in enumerate(table["class"])
            if isapprox(table["cargo_value"][k], classes[class].cargo_value * factor;
                rtol=1e-6)]
    return table_rows(table, kept)
end

"""
    table_rows(table, kept)

The table of the rows `kept` of `table`.
"""
table_rows(table, kept) =
    Dict{String, Vector}(column => values[kept] for (column, values) in table)

"""
    speed_along_track(sailed_km, days)

Speed [kn] of a ship that covers `sailed_km` along its track in `days` at sea.
"""
speed_along_track(sailed_km, days) = 1e3sailed_km / (3600 * 24days) / KNOT

"""
    cargo_interest_data()

The ship classes on the zero-emission drive of [`study_drives`](@ref) on every route
without a rig and with the cheapest size of each rig from [`searched_sizes`](@ref): each
class at the [`cargo_interest_factors`](@ref) of its own cargo value, and each class of
[`cargo_value_sweep`](@ref) carrying cargo of each of its values, with the distance sailed
[km]: cargo_interest.csv.
"""
function cargo_interest_data()
    classes = ship_classes()
    own = [with_cargo_value(class, class.cargo_value * factor)
           for class in values(classes), factor in cargo_interest_factors()]
    swept = [with_cargo_value(classes[name], value)
             for name in cargo_value_sweep.classes, value in cargo_value_sweep.values]
    ships = [(class, last(study_drives), route) for class in [vec(own); vec(swept)],
                 route in route_names]
    cases, trips = searched_sizes(vec(ships))
    labelled = [merge(case, (; cargo_value=case.design.class.cargo_value,
                    sailed_km=sum(corridor -> corridor.track_length, case.corridors) / 1e3))
                for case in cases]
    write_trips("cargo_interest.csv", labelled, trips, :class, :cargo_value, :sailed_km,
        :route, :drive, :rig, :area, :units)
end

"""
    forecast_data()

The error of the archived forecasts along the route of the 140 m ship to Guadeloupe:
forecast_error.csv.
"""
forecast_data() = write_forecast_error("forecast_error.csv", run_corridors(:caribbean)...)

"""
    forecast_error()

The [`ForecastError`](@ref) of the wind the router plans on, the forecast blended with the
climatology, in the forecast_error.csv of [`forecast_data`](@ref).
"""
function forecast_error()
    table = read_table(data_file("forecast_error.csv"))
    leads = 24 * table["lead_days"]
    leads ≈ first(leads) * eachindex(leads) ||
        error("the leads of forecast_error.csv are not evenly spaced from the first")
    return ForecastError(first(leads), table["wind_blend"])
end

"plans of the paper's forecast result: perfect foresight, and the plan the results use,
sailed live"
forecast_result_plans = (false, :live)

"""
    forecast_result_data()

The paper's forecast result: the 140 m e-ammonia ship to Guadeloupe without a rig and with
each rig, per departure of `forecast_departures`, for each of the
[`forecast_result_plans`](@ref): forecast_result.csv; the seconds each round trip took to
compute: forecast_result_seconds.csv; and per rig the share of its perfect-foresight saving
it keeps on the live plan with its jackknife standard error over the departures:
forecast_result_kept.csv.
"""
function forecast_result_data()
    rigs = reference_rigs_and_none
    cases, trips = [], []
    for departure in forecast_departures
        step_cases = vec([trip_case(ShipDesign(:ammonia, 140.0; rig_size(rig, area)...);
                              forecast=plan, rig, plan=string(plan), departure)
                          for (rig, area) in rigs, plan in forecast_result_plans])
        append!(cases, step_cases)
        append!(trips, round_trips(step_cases, [departure]))
    end
    write_trips("forecast_result.csv", cases, trips, :rig, :plan, :departure)
    open(run_file("forecast_result_seconds.csv"), "w") do io
        println(io, "rig,plan,departure,seconds")
        for case in cases
            println(io, join(csv_value.((case.rig, case.plan, case.departure,
                trip_seconds(case, [case.departure]))), ","))
        end
    end
    write_kept_shares("forecast_result_kept.csv", cases, trips)
end

"""
    write_kept_shares(name, cases, trips)

Write `name`: per rig, the share of its perfect-foresight saving it keeps on the live plan,
the ratio of the mean savings over the `forecast_departures` where all trips exist, with
its jackknife standard error.
"""
function write_kept_shares(name, cases, trips)
    open(run_file(name), "w") do io
        println(io, "rig,plan,kept,kept_error")
        for (rig, _) in reference_rigs
            all_saved = [plan_savings(cases, trips, rig, plan, forecast_departures)
                         for plan in (:live, false)]
            usable = complete_departures(all_saved)
            saved, perfect = [saved[usable] for saved in all_saved]
            n = length(usable)
            value = kept_share(saved, perfect, 1:n)
            spread = jackknife_error(index -> kept_share(saved, perfect, index), n)
            @printf(io, "%s,%s,%.3f,%.3f\n", rig, :live, value, spread)
        end
    end
end

"""
cost per tonne-kilometre of `rig` on `plan` from `departure` among `cases` and `trips`,
`NaN` where that trip failed
"""
function plan_cost(cases, trips, rig, plan, departure)
    index = findfirst(i -> cases[i].rig == rig && cases[i].forecast === plan &&
                               cases[i].departure == departure, eachindex(cases))
    return isnothing(trips[index]) ? NaN : trips[index].cost_per_tonne_km
end

"cost saving of `rig` on `plan` per departure of `departures`, against no rig on the same
plan"
plan_savings(cases, trips, rig, plan, departures) =
    [1 - plan_cost(cases, trips, rig, plan, departure) /
         plan_cost(cases, trips, "none", plan, departure)
     for departure in departures]

"indices of the departures at which every one of the per-departure `series` is finite"
complete_departures(series) =
    findall(i -> all(isfinite(values[i]) for values in series), eachindex(first(series)))

"share of the mean saving of `perfect` that `saved` keeps over the departures `indices`"
kept_share(saved, perfect, indices) = mean(saved[indices]) / mean(perfect[indices])

"jackknife standard error over `n` departures of `statistic` of the departures kept"
function jackknife_error(statistic, n)
    leave_out = [statistic(setdiff(1:n, i)) for i in 1:n]
    return sqrt((n - 1) / n * sum(abs2, leave_out .- mean(leave_out)))
end

"hours a ship spends per port call [h]"
port_hours() = 24assumptions[:port_time_per_call]

"[`turnaround_hours`](@ref) [h] of the ship of `route_table` through `outbound`"
turnaround(route_table, outbound) =
    WindShipOpt.turnaround_hours(route_table.table.ship, outbound, assumptions)

"columns of forecast_error.csv after the lead, in the order `add_forecast_errors!` adds"
forecast_error_columns = Tuple("$(quantity)_$kind" for quantity in ("wind", "height")
                               for kind in ("forecast", "blend", "climate", "weight"))

"""
    write_forecast_error(name, corridors...)

Write `name` to the directory of the run in use: per lead day, the root mean square error
against ERA5 of the vector wind [m/s] and the wave height [m] of the archived forecasts
less their bias, of their blend with the climatology that the router plans on and of that
climatology alone, and the mean weight of the forecast in the blend, over the nodes of
`corridors` and every forecast in the archive.
"""
function write_forecast_error(name, corridors...)
    points = unique(vcat([vec(collect(zip(corridor.lat, corridor.lon)))
                          for corridor in corridors]...))
    leads = 6.0:6.0:384.0
    issues = [Threads.@spawn issue_forecast_errors(weather, forecast_archive, issue, points,
                  leads) for issue in 1:WindShipOpt.issue_count(forecast_archive.wind)]
    totals, counts = reduce(.+, fetch.(issues))
    open(run_file(name), "w") do io
        println(io, join(("lead_days", forecast_error_columns...), ","))
        for (row, lead) in enumerate(leads)
            averages = totals[row, :] ./ counts[row, :]
            printed = [endswith(column, "weight") ? average : sqrt(average)
                       for (column, average) in zip(forecast_error_columns, averages)]
            @printf(io, "%.2f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f\n", lead / 24,
                printed...)
        end
    end
end

"""
    issue_forecast_errors(weather, archive, issue, points, leads)

Totals and counts per lead of `leads` [h] and column of [`forecast_error_columns`](@ref),
as [`add_forecast_errors!`](@ref) adds them over `points`, of forecast `issue` of `archive`
against `weather`; none where that issue is not the one known as it reaches the ship, or
for a lead past the end of `weather`.
"""
function issue_forecast_errors(weather, archive, issue, points, leads)
    shape = (length(leads), length(forecast_error_columns))
    totals, counts = zeros(shape), zeros(Int, shape)
    issued = WindShipOpt.issue_time(archive, issue)
    known = ArchivedForecast(archive, issued + WindShipOpt.FORECAST_LATENCY)
    known.issue == issue || return totals, counts
    for (row, lead) in enumerate(leads)
        issued + lead <= WindShipOpt.duration(weather) || continue
        add_forecast_errors!(view(totals, row, :), view(counts, row, :), weather, known,
            points, issued + lead)
    end
    return totals, counts
end

"""
    add_forecast_errors!(totals, counts, weather, known, points, time)

Add to `totals` over `points`, and count in `counts`, the squared error against `weather`
at `time` of the vector wind of the forecast `known` less its bias, of its blend and of the
climatology, then the forecast's weight, and the same four for the wave height, leaving
out a value the forecast does not hold.
"""
function add_forecast_errors!(totals, counts, weather, known, points, time)
    climate = known.archive.climate
    for (lat, lon) in points
        truth_wind, truth_height = wind(weather, lat, lon, time),
        first(waves(weather, lat, lon, time))
        east, north, wind_weight = WindShipOpt.corrected_wind(known, lat, lon, time)
        height, _, _, _, height_weight = WindShipOpt.corrected_waves(known, lat, lon, time)
        climatology_wind = wind(climate, lat, lon, time)
        climatology_height = first(waves(climate, lat, lon, time))
        errors = (sum(abs2, (east, north) .- truth_wind),
            sum(abs2, wind(known, lat, lon, time) .- truth_wind),
            sum(abs2, climatology_wind .- truth_wind), wind_weight,
            (height - truth_height)^2,
            (first(waves(known, lat, lon, time)) - truth_height)^2,
            (climatology_height - truth_height)^2, height_weight)
        for (column, value) in enumerate(errors)
            isnan(value) && continue
            totals[column] += value
            counts[column] += 1
        end
    end
end

"""
Inputs of the development study that move several assumptions together, each with the
end of every assumption's range that its high bound takes.
"""
joint_inputs = (rig_out_of_service=(wing_out_of_service=:high, rotor_out_of_service=:high,
        suction_out_of_service=:high),
    fuel_price=(e_ammonia_price=:high, vlsfo_price=:high))

"the assumptions an input `name` of the development study moves together, else itself"
input_members(name) = haskey(joint_inputs, name) ? keys(joint_inputs[name]) : (name,)

"""
    bound_assumptions(name, bound)

The assumptions with input `name` at its `bound` (:low or :high), and each of
[`joint_inputs`](@ref) by [`moved_together`](@ref).
"""
function bound_assumptions(name, bound)
    haskey(joint_inputs, name) && return moved_together(joint_inputs[name], bound)
    entry = assumptions.entries[name]
    return with_value(assumptions, name, bound == :low ? entry.low : entry.high)
end

"""
    moved_together(high_ends, bound)

The assumptions with each one named in `high_ends` at the end of its range given there
where `bound` is `:high`, and at the other end where it is `:low`.
"""
function moved_together(high_ends, bound)
    other_end = Dict(:low => :high, :high => :low)
    moved = assumptions
    for (name, high_end) in pairs(high_ends)
        end_of_range = bound == :high ? high_end : other_end[high_end]
        moved = with_value(moved, name, getfield(assumptions.entries[name], end_of_range))
    end
    return moved
end

"class ships of the development study, each with its drive and route"
study_classes = (("Kamsarmax bulk carrier", :vlsfo, :tubarao),
    ("Neo-Panamax container ship", :ammonia, :new_york))

"""
    sensitivity_ships()

Ships of the development study as (name, design without a rig, route, rig areas): the
140 m e-ammonia reference ship to Guadeloupe, a Kamsarmax on VLSFO to Tubarão and a
Neo-Panamax container ship on e-ammonia to New York, the classes with the best rig sizes
of the class study.
"""
function sensitivity_ships()
    classes_table = read_table(data_file("classes.csv"))
    classes = ship_classes()
    reference = NamedTuple(Symbol(rig) => rig_size(rig, area)
                           for (rig, area) in reference_rigs)
    ships = [("140 m", ShipDesign(:ammonia, 140.0), :caribbean, reference)]
    for (name, drive, route) in study_classes
        areas = study_areas(classes_table, name, route, drive)
        push!(ships, (name, ShipDesign(drive, classes[name]), route, areas))
    end
    return ships
end

"""
    study_areas(table, class, route, drive)

Rig sizes of each rig of [`rig_names`](@ref) on `class`, cheapest in the class study
`table`, as the keyword arguments of its design; an error where a rig has none.
"""
function study_areas(table, class, route, drive)
    return NamedTuple(map(rig_names) do rig
        area = best_area(table, class, string(route), string(drive), rig)
        isnan(area) &&
            error("the class study has no $rig size for $class on $drive to $route")
        return Symbol(rig) => rig_size(rig, area)
    end)
end

"""
    development_inputs

The inputs of the development study as (input, label, rig, lever, reason): the input,
its name in the paper, the rig whose developer can change it (`"soft kites"` for both
soft kites, `"every rig"` for all, `"condition"` for a condition it is judged against),
what kind of lever it is, and the reason it is in the study.
"""
development_inputs = [
    (input=:canopy_life, label="canopy life", rig="soft kites", lever="life",
        reason="What a flight hour of the canopy costs; unmeasured, so what development " *
               "has to prove."),
    (input=:launch_mast_mass_per_size, label="kite launch mast mass", rig="soft kites",
        lever="price", reason="Its design sets the mass of the launch mast and docking " *
                              "head, the largest part of the kite's hardware price."),
    (input=:kite_launch_loss_probability, label="kites lost per launch", rig="soft kites",
        lever="availability",
        reason="What its launch and landing system's reliability is worth: from today's " *
               "record to the goal."),
    (input=:kite_max_force_per_area, label="kite force limit per area", rig="kite",
        lever="force",
        reason=string("Its structure decides the force each m\\textsuperscript{2} may ",
            "carry; cloth, seams, tether and winch grow with it.")),
    (input=:lei_max_force_per_area, label="LEI kite force limit per area", rig="lei",
        lever="force",
        reason=string("Its structure decides the force each m\\textsuperscript{2} may ",
            "carry; cloth, seams, tubes, tether and winch grow with it.")),
    (input=:kite_min_turn_radius, label="kite smallest turn radius", rig="soft kites",
        lever="force", reason="Steering and control decide how tight, and so how " *
                              "powerful, a pattern can be."),
    (input=:wing_max_lift_coefficient, label="wing sail maximum lift", rig="wings",
        lever="force", reason="Flap and section design decide a wing's force."),
    (input=:suction_max_lift_coefficient, label="suction sail maximum lift",
        rig="suction", lever="force",
        reason="Section, slots and fan decide how far the flow stays attached."),
    (input=:rotor_lift_factor, label="rotor lift", rig="rotors", lever="force",
        reason="Rotor design sets the lift at a given spin; CFD and full-scale data " *
               "bound it."),
    (input=:rotor_max_wind, label="rotor highest wind", rig="rotors", lever="weather",
        reason="Up to which wind its drive and structure let a rotor keep spinning."),
    (input=:rigid_mass, label="VTOL kite mass", rig="vtol", lever="price",
        reason="Structure sets the airframe's mass, and with it its price, its hover " *
               "power and the drives and supply that hover needs."),
    (input=:rigid_drag, label="VTOL kite drag", rig="vtol", lever="force",
        reason="The drag of its body, feathered propellers and tether, the largest open " *
               "risk of its force."),
    (input=:rig_out_of_service, label="out of service", rig="every rig",
        lever="availability",
        reason="What a maker's reliability work is worth: one goal for every rig, moved " *
               "for all at once from what operators record to what makers state."),
    (input=:fuel_price, label="fuel price", rig="condition", lever="condition",
        reason="Not for a developer to change: the fuel bill a rig cuts, with the prices " *
               "of e-ammonia and fuel oil moved together."),
    (input=:wind_shear_exponent, label="wind shear exponent", rig="condition",
        lever="condition",
        reason="Not for a developer to change: how much stronger the wind blows at a " *
               "kite's height than on deck, which sets what flying high is worth."),
]

"""
    rig_cases(ship, bare, route, areas; labels...)

Cases of a ship of [`sensitivity_ships`](@ref) without a rig and with each rig, tagged
with `labels`, which may set the case's assumptions and model part.
"""
function rig_cases(ship, bare, route, areas; labels...)
    cases = [trip_case(bare; route, ship, rig="none", labels...)]
    for rig in rig_names
        design = ShipDesign(; bare.drive, bare.length, bare.class,
            getproperty(areas, Symbol(rig))...)
        push!(cases, trip_case(design; route, ship, rig, labels...))
    end
    return cases
end

"""
inputs that change only what a route costs, not what the ship or rig can do: a case moving
only these is recosted on the routes of its design at the base inputs
"""
cost_only_inputs = Set([WindShipOpt.canopy_price_inputs...; :canopy_life; :tether_price;
    :tether_lifetime; :kite_cycle_crew_cost; :kite_launch_loss_probability;
    :kite_out_of_service; :wing_loss_rate; :rotor_loss_rate; :wing_cost_per_mass;
    :suction_fan_cost_per_power; :rotor_cost_per_area; :market_price_factor; :kite_lifetime;
    :wing_lifetime; :rotor_lifetime; :suction_lifetime; :discount_rate; :cargo_value])

"names of the inputs `inputs` holds at another value than the base assumptions"
changed_inputs(inputs) =
    [name for name in keys(assumptions.entries) if inputs[name] != assumptions[name]]

"whether `inputs` move only [`cost_only_inputs`](@ref) from the base assumptions"
cost_only(inputs) = all(in(cost_only_inputs), changed_inputs(inputs))

"""
    recosted_trips(cases, departures)

Round trips of `cases`, each moving only [`cost_only_inputs`](@ref): the design of each
routed once at the base inputs over `departures`, then costed at the case's inputs on those
routes ([`recosted_trip`](@ref)). Errors on a case moving any other input.
"""
function recosted_trips(cases, departures)
    all(case -> cost_only(case.assumptions), cases) ||
        throw(ArgumentError("a recosted case moves an input that changes the ship or rig"))
    bases = [merge(case, (; assumptions)) for case in cases]
    directories = [case_directory(case, departures) for case in bases]
    routed = unique(i -> directories[i], eachindex(bases))
    trips = Dict(zip(directories[routed], round_trips(bases[routed], departures)))
    return [recosted_trip(case, trips[directory])
            for (case, directory) in zip(cases, directories)]
end

"""
    recosted_trip(case, trip)

`trip` with its cost per tonne-km at the inputs of `case` on its routes
([`changed_cost`](@ref)), its fuel, CO2 and times as routed and no outcome per departure;
`nothing` where `trip` is.
"""
recosted_trip(case, trip) = isnothing(trip) ? nothing :
    rebuilt(trip; cost_per_tonne_km=changed_cost(case, trip),
    departures=empty(trip.departures))

"""
    swept_trips(cases, departures)

Round trips of `cases` over `departures`: recosted on the routes at the base inputs
([`recosted_trips`](@ref)) where a case moves only [`cost_only_inputs`](@ref), routed anew
where it moves any other.
"""
function swept_trips(cases, departures)
    recosted = findall(case -> cost_only(case.assumptions), cases)
    rerouted = setdiff(eachindex(cases), recosted)
    trips = Vector{Any}(nothing, length(cases))
    trips[rerouted] = round_trips(cases[rerouted], departures)
    trips[recosted] = recosted_trips(cases[recosted], departures)
    return trips
end

"""
    sensitivity_data()

Every ship of [`sensitivity_ships`](@ref) without a rig and with each rig, at the base
inputs and with each of [`development_inputs`](@ref) at its low and high bound, over the
[`sensitivity_departures`](@ref): sensitivity.csv. A bound moving only
[`cost_only_inputs`](@ref) is recosted on the base routes, any other routed anew
([`swept_trips`](@ref)); the base trips are routed first, so a changed case whose trip
never reads its input reuses them.
"""
function sensitivity_data()
    cases = []
    for ship in sensitivity_ships()
        append!(cases, rig_cases(ship...; input=:none, bound=:value))
        for entry in development_inputs, bound in (:low, :high)
            append!(cases, rig_cases(ship...;
                assumptions=bound_assumptions(entry.input, bound), entry.input, bound))
        end
    end
    base = findall(case -> case.input == :none, cases)
    changed = setdiff(eachindex(cases), base)
    trips = Vector{Any}(nothing, length(cases))
    trips[base] = round_trips(cases[base], sensitivity_departures())
    trips[changed] = swept_trips(cases[changed], sensitivity_departures())
    write_trips("sensitivity.csv", cases, trips, :ship, :rig, :input, :bound)
end

"""
    noise_variants(tether_length_ratio, kite_min_turn_radius)

Variants of the base kite with the tether and the turn radius each about 2 % off the given
base values, too little to change the kite: their spread is the noise of the routing.
"""
function noise_variants(tether_length_ratio, kite_min_turn_radius)
    return [(string("noise_", name, "_", factor), design_aspect_ratio,
                NamedTuple{(name,)}((factor * value,)))
            for (name, value) in ((:tether_length_ratio, tether_length_ratio),
                (:kite_min_turn_radius, kite_min_turn_radius)) for factor in (0.98, 1.02)]
end

"""
    base_kite_variants()

Variants of the base kite on the ships of the area basis study as (name, projected aspect
ratio, changed inputs): the base, at aspect ratio 2.5 with the flight drag held and
recalibrated, at the other readings of its inputs, and those of [`noise_variants`](@ref).
"""
function base_kite_variants()
    low_aspect_ratio = 2.5
    recalibrated = WindShipOpt.recalibrated_flight_drag(low_aspect_ratio,
        design_aspect_ratio, assumptions)
    return [("base", design_aspect_ratio, (;)); ("held", low_aspect_ratio, (;));
        ("recalibrated", low_aspect_ratio, (; kite_flight_drag=recalibrated));
        ("tether_15.5", design_aspect_ratio, (; tether_length_ratio=15.5));
        ("tether_19.7", design_aspect_ratio, (; tether_length_ratio=19.7));
        ("overhead_0.19", design_aspect_ratio, (; canopy_mass_overhead=0.19));
        noise_variants(assumptions[:tether_length_ratio],
            assumptions[:kite_min_turn_radius])]
end

"""
    cargo_kite_variants()

Variants of the kite that flew on cargo ships, as (name, projected area [m^2], changed
inputs): the base, its flat size read as projected, no flight drag, and canopy wear and
launches free, with those of [`noise_variants`](@ref).
"""
function cargo_kite_variants()
    free = (; canopy_life=1e9, tether_lifetime=1e9, kite_cycle_crew_cost=0.0,
        kite_launch_loss_probability=0.0, kite_cycle_course_cost=0.0)
    return [("base", 125.0, (;)); ("flat_as_projected", 160.0, (;));
        ("no_flight_drag", 125.0, (; kite_flight_drag=0.0));
        ("free_operation", 125.0, free);
        [(name, 125.0, changes)
         for (name, _, changes) in noise_variants(assumptions[:tether_length_ratio],
            assumptions[:kite_min_turn_radius])]]
end

"""
    base_kite_data(ships=sensitivity_ships())

The base kite of `ships`, as those of [`sensitivity_ships`](@ref), at each of
[`base_kite_variants`](@ref), and a 130 m VLSFO ship at each of
[`cargo_kite_variants`](@ref), each with the ship without a rig: base_kite.csv.
"""
function base_kite_data(ships=sensitivity_ships())
    cases = []
    for (ship, bare, route, areas) in ships
        push!(cases, trip_case(bare; route, ship, variant="bare"))
        for (variant, aspect_ratio, changes) in base_kite_variants()
            design = ShipDesign(; bare.drive, bare.length, bare.class, areas.kite...,
                kite_aspect_ratio=aspect_ratio)
            push!(cases, trip_case(design; route, ship, variant,
                assumptions=changed_assumptions(changes)))
        end
    end
    push!(cases, trip_case(ShipDesign(:vlsfo, 130.0); ship="130 m", variant="bare"))
    for (variant, area, changes) in cargo_kite_variants()
        push!(cases, trip_case(ShipDesign(:vlsfo, 130.0; kite_area=area); ship="130 m",
            variant, assumptions=changed_assumptions(changes)))
    end
    write_trips("base_kite.csv", cases, round_trips(cases, sampled_departures()), :ship,
        :variant)
end

"input of each rig holding the share of its units' round trips out of service"
out_of_service_inputs = Dict("kite" => "kite_out_of_service",
    "wings" => "wing_out_of_service", "rotors" => "rotor_out_of_service",
    "suction" => "suction_out_of_service", "vtol" => "kite_out_of_service",
    "lei" => "kite_out_of_service")

"""
    service_shares(rig)

Shares of its units' round trips [-] that `rig` is routed at: none, the low bound, base and
high bound of its input, and up to all of them for the limits past its range.
"""
function service_shares(rig)
    entry = assumptions.entries[Symbol(out_of_service_inputs[rig])]
    return sort(unique([0.0, entry.low, entry.value, entry.high, 0.25, 0.5, 0.75, 1.0]))
end

"""
    availability_data()

Each ship of [`goal_limit_ships`](@ref) with each rig at its [`service_shares`](@ref),
the kite recosted on its routes at the base inputs and the deck rigs, whose units down
change what the rest can do, routed anew ([`swept_trips`](@ref)): availability.csv.
"""
function availability_data()
    cases = []
    for (ship, bare, route, areas) in goal_limit_ships()
        for rig in rig_names, share in service_shares(rig)
            input = Symbol(out_of_service_inputs[rig])
            design = ShipDesign(; bare.drive, bare.length, bare.class,
                getproperty(areas, Symbol(rig))...)
            push!(cases, trip_case(design;
                assumptions=with_value(assumptions, input, share), route, ship, rig, share))
        end
    end
    write_trips("availability.csv", cases, swept_trips(cases, sampled_departures()),
        :ship, :rig, :share)
end

"""
    swept_sizes(rig, areas, hull)

Sizes [m^2] of `rig` in the size sweep at the goals: the [`sizes_around`](@ref) its size in
`areas`, as far as it fits on `hull`.
"""
function swept_sizes(rig, areas, hull)
    best = only(values(getproperty(areas, Symbol(rig))))
    return WindShipOpt.sizes_around(rig, best, largest_rig_area(rig, hull))
end

"""
    goal_size_data()

Each ship of [`sensitivity_ships`](@ref) without a rig and with each rig at its
[`swept_sizes`](@ref), at the goals: goal_sizes.csv.
"""
function goal_size_data()
    cases = []
    for (ship, bare, route, areas) in sensitivity_ships()
        push!(cases, trip_case(bare; route, ship, bare.drive, rig="none", area=0.0))
        hull = Ship(bare, assumptions).hull
        for rig in rig_names
            for area in swept_sizes(rig, areas, hull)
                design = ShipDesign(; bare.drive, bare.length, bare.class,
                    rig_size(rig, area)...)
                push!(cases, trip_case(design; route, ship, bare.drive, rig, area))
            end
        end
    end
    write_trips("goal_sizes.csv", cases, round_trips(cases, sampled_departures()), :ship,
        :route, :drive, :rig, :area)
end

"""
    goal_limit_ships()

The ships of [`sensitivity_ships`](@ref) with each rig at its cheapest size in
goal_sizes.csv.
"""
function goal_limit_ships()
    table = read_table(data_file("goal_sizes.csv"))
    return [(ship, bare, route,
                NamedTuple(Symbol(rig) => rig_size(rig, table["area"][cheapest_size(table,
                    ship, rig)]) for rig in rig_names))
            for (ship, bare, route, _) in sensitivity_ships()]
end

"row of the cheapest size of `rig` on `ship` in the goal_sizes.csv `table`"
cheapest_size(table, ship, rig) = cheapest_row(table, "ship" => ship, "rig" => rig)

"canopy lives [flight hours] the kite is routed at for the missed-goal table"
canopy_lives = (500.0, 750.0, 1000.0, 1500.0, 2000.0, 3000.0, 4000.0, 6000.0, 8000.0,
    16000.0)

"""
    canopy_life_data()

The kite of each ship of [`goal_limit_ships`](@ref) at each of `canopy_lives`, its size
and every other input held, recosted on its routes at the base inputs: canopy_life.csv.
"""
function canopy_life_data()
    cases = [trip_case(ShipDesign(; bare.drive, bare.length, bare.class, areas.kite...);
                 assumptions=with_value(assumptions, :canopy_life, life), route, ship, life)
             for (ship, bare, route, areas) in goal_limit_ships(), life in canopy_lives]
    write_trips("canopy_life.csv", vec(cases),
        recosted_trips(vec(cases), sampled_departures()), :ship, :life)
end

"""
    canopy_prices()

Canopy prices [USD/m^2] the kite is routed at for the missed-goal table: the base price and
either side of it, up to where the kite stops paying on every ship.
"""
canopy_prices() =
    reference_canopy_price(assumptions) .* [0.5, 0.75, 1.0, 1.25, 1.5, 2.5, 3.5, 5.0, 7.0]

"""
    at_canopy_price(price)

The assumptions with the canopy's cost inputs scaled together until the
[`reference_canopy_price`](@ref) is `price` [USD/m^2].
"""
function at_canopy_price(price)
    low, high = 0.0, 20.0
    for _ in 1:60
        middle = (low + high) / 2
        cost = reference_canopy_price(scaled(WindShipOpt.canopy_price_inputs, middle))
        cost < price ? (low = middle) : (high = middle)
    end
    return scaled(WindShipOpt.canopy_price_inputs, high)
end

"""
    canopy_price_data()

The kite of each ship of [`goal_limit_ships`](@ref) at each of [`canopy_prices`](@ref), its
size and every other input held, recosted on its routes at the base inputs:
canopy_price.csv.
"""
function canopy_price_data()
    cases = [trip_case(ShipDesign(; bare.drive, bare.length, bare.class, areas.kite...);
                 assumptions=at_canopy_price(price), route, ship, price)
             for (ship, bare, route, areas) in goal_limit_ships(), price in canopy_prices()]
    write_trips("canopy_price.csv", vec(cases),
        recosted_trips(vec(cases), sampled_departures()), :ship, :price)
end

"ships of the abatement study as (name, route)"
abatement_ships = (("140 m", :caribbean), ("Kamsarmax bulk carrier", :tubarao))

"""
    abatement_data()

Each ship of `abatement_ships` on each drive without a rig and with every rig over its
range of sizes, kites from 400 to 12,800 m^2 and deck rigs from 100 to 3,200 m^2 as far as
they fit on deck: abatement.csv.
"""
function abatement_data()
    cases = []
    for (ship, route) in abatement_ships, drive in study_drives
        hull = Ship(ShipDesign(drive, study_hull(ship)), assumptions).hull
        sizes = Dict("none" => [0.0], "kite" => [400.0 * 2^(k / 2) for k in 0:10],
            (rig => filter(<=(largest_area(rig, hull)), [100.0 * 2^(k / 2) for k in 0:10])
             for rig in deck_rig_names)...)
        for rig in all_rigs, area in sizes[rig]
            design = ShipDesign(drive, study_hull(ship); rig_size(rig, area)...)
            push!(cases, trip_case(design; route, ship, drive, rig, area))
        end
    end
    write_trips("abatement.csv", cases, round_trips(cases, sampled_departures()), :ship,
        :drive, :rig, :area)
end

"corridor scales of the convergence study"
convergence_scales = (2.0, 1.0, 0.5)

"""
    convergence_data()

A 140 m e-ammonia ship to Guadeloupe without a rig and with each rig, routed at each of
`convergence_scales`: convergence.csv.
"""
function convergence_data()
    rigs = [("none", 0.0), ("kite", 1600.0), ("wings", 1500.0), ("rotors", 800.0)]
    cases = vec([trip_case(ShipDesign(:ammonia, 140.0; rig_size(rig, area)...); rig, scale)
                 for (rig, area) in rigs, scale in convergence_scales])
    write_trips("convergence.csv", cases, round_trips(cases, sampled_departures()), :rig,
        :scale)
end

"model parts the model-part study switches off, one at a time"
simplified_parts = (:calibration, :waves, :windage, :limits, :rudder, :side_force,
    :weak_hull)

"""
    rebuilt(object; changes...)

A new object of the type of `object` with its fields, those named in `changes` replaced.
"""
function rebuilt(object; changes...)
    unknown = setdiff(keys(changes), fieldnames(typeof(object)))
    isempty(unknown) ||
        throw(ArgumentError("$(typeof(object)) has no field $(first(unknown))"))
    fields = (get(changes, name, getfield(object, name))
              for name in fieldnames(typeof(object)))
    return typeof(object).name.wrapper(fields...)
end

"""
    simplified_ship(ship, part)

`ship` with model `part` switched off: `:none` keeps it whole, `:calibration` drops the
calibration of the hull's calm-water resistance, `:waves` the added resistance in waves,
`:windage` the air drag of the superstructure, `:limits` the heel, leeway and rudder
limits, `:rudder` the drag of the rudder, `:side_force` the drag of leeway and rudder
together, and `:weak_hull` takes the hull's side-force slope at the low bound of
`hull_side_force_factor`.
"""
function simplified_ship(ship, part)
    part == :none && return ship
    part == :calibration &&
        return rebuilt(ship; hull=rebuilt(ship.hull; resistance_factor=1.0))
    if part == :waves
        # the first two SNNM constants scale the motion and the reflection part
        x = (0.0, 0.0, ship.seakeeping.x[3:end]...)
        return rebuilt(ship; seakeeping=rebuilt(ship.seakeeping; x))
    end
    part == :windage &&
        return rebuilt(ship;
            windage=rebuilt(ship.windage; frontal_area=0.0, lateral_area=eps()))
    part == :limits &&
        return rebuilt(ship; heel_limit=Inf, leeway_limit=Inf, rudder_max_lift=Inf)
    part == :rudder && return rebuilt(ship; rudder_aspect_ratio=Inf)
    part == :side_force &&
        return rebuilt(ship; hull=rebuilt(ship.hull; side_force_factor=Inf),
            rudder_aspect_ratio=Inf)
    part == :weak_hull &&
        return rebuilt(ship;
            hull=rebuilt(ship.hull;
                side_force_factor=assumptions.entries[:hull_side_force_factor].low))
    throw(ArgumentError("no model part $part"))
end

"""
    year_departures(year)

Every second departure in weather year `year`, counted from 1.
"""
year_departures(year) =
    filter(hour -> 8760(year - 1) <= hour < 8760year, departures)[1:2:end]

"""
    model_parts_data()

Each ship of [`sensitivity_ships`](@ref) without a rig and with each rig, whole and with
each of [`simplified_parts`](@ref) switched off: model_parts.csv; the leeway each rig sails
at, by [`write_leeway`](@ref): leeway.csv; and whole over the
[`year_departures`](@ref) of each weather year: weather_years.csv.
"""
function model_parts_data()
    cases = [case for ship_case in sensitivity_ships(), part in (:none, simplified_parts...)
             for case in rig_cases(ship_case...; part)]
    write_leeway("leeway.csv")
    write_trips("model_parts.csv", cases, round_trips(cases, sampled_departures()), :ship,
        :rig, :part)
    cases, trips = [], []
    for year in 1:ceil(Int, last(departures) / 8760)
        batch = [case for ship_case in sensitivity_ships()
                 for case in rig_cases(ship_case...; year)]
        append!(trips, round_trips(batch, year_departures(year)))
        append!(cases, batch)
    end
    write_trips("weather_years.csv", cases, trips, :ship, :rig, :year)
end

"""
    write_leeway(name)

Write `name` with the leeway of each rigged ship of [`sensitivity_ships`](@ref), whole, over
the hours of its [`traced_legs`](@ref): the median and 95th percentile [deg] and the share
of hours within half a degree of `leeway_limit` [-].
"""
function write_leeway(name)
    cases = [case for ship_case in sensitivity_ships() for case in rig_cases(ship_case...)
             if case.rig != "none"]
    traces = fetch.([Threads.@spawn last.(traced_legs(Ship(case.design, assumptions),
                         case.route)) for case in cases])
    limit = assumptions[:leeway_limit]
    open(run_file(name), "w") do io
        println(io, "ship,rig,median,high,at_limit")
        for (case, legs) in zip(cases, traces)
            leeway = rad2deg.(reduce(vcat, (trace.leeway for trace in legs)))
            hours = reduce(vcat, (trace.hours for trace in legs))
            @printf(io, "%s,%s,%.2f,%.2f,%.4f\n", case.ship, case.rig,
                weighted_quantile(leeway, hours, 0.5),
                weighted_quantile(leeway, hours, 0.95),
                sum(hours[leeway .>= limit - 0.5]) / sum(hours))
        end
    end
end

"""
    weighted_quantile(values, weights, share)

The smallest of `values` below which at least `share` of the total `weights` lies.
"""
function weighted_quantile(values, weights, share)
    order = sortperm(values)
    k = findfirst(>=(share * sum(weights)), cumsum(weights[order]))
    return values[order[k]]
end

"""
    size_search_data()

Each ship of [`study_classes`](@ref) with the search of [`searched_sizes`](@ref), and with
each rig at every size of the [`size_grid`](@ref) of its [`size_bounds`](@ref), tagged
round -1: size_search.csv.
"""
function size_search_data()
    classes = ship_classes()
    ships = [(classes[name], drive, route) for (name, drive, route) in study_classes]
    cases, trips = searched_sizes(ships)
    grid = []
    for (class, drive, route) in ships, (rig, (lower, upper)) in size_bounds(class)
        for area in size_grid(lower, upper)
            push!(grid, class_case(class, drive, rig, area, route; round=-1))
        end
    end
    append!(trips, round_trips(grid, sampled_departures()))
    append!(cases, grid)
    write_trips("size_search.csv", cases, trips, :class, :route, :drive, :rig, :area,
        :columns, :round)
end

"ship classes of the kite-and-rotors study"
pair_classes = ("Handysize bulk carrier", "Kamsarmax bulk carrier")

"routes of that study: the kite's largest saving and both rigs' smallest in classes.csv"
pair_routes = (:caribbean, :bilbao)

"""
    nearest_area(areas, area)

The one of `areas` nearest `area` on a log scale.
"""
nearest_area(areas, area) = areas[argmin(abs.(log.(areas ./ area)))]

"""
    pair_sizes(kite, rotors, kites, rotor_bounds)

Sizes as (rig, kite area, rotor area) [m^2] around the best single `kite` and `rotors`: each
alone and three pairs, their kite the one of the areas `kites` nearest half or a quarter of
`kite` and their rotors `rotors` or half of it, held to `rotor_bounds`.
"""
function pair_sizes(kite, rotors, kites, rotor_bounds)
    pairs = unique([(nearest_area(kites, kite_area), clamp(rotor_area, rotor_bounds...))
                    for (kite_area, rotor_area) in
                        ((kite / 2, rotors), (kite / 4, rotors), (kite / 2, rotors / 2))])
    return [("kite", kite, 0.0); ("rotors", 0.0, rotors);
        [("kite+rotors", pair...) for pair in pairs]]
end

"""
    pair_gain_errors(table)

Jackknife standard error [% points] over the departures of the extra saving of the best
kite-and-rotor pair over the better single rig, per ship, drive and route of the
per-departure `table` of combination_departures.csv.
"""
function pair_gain_errors(table)
    errors = Float64[]
    for (ship, drive, route) in unique(zip(table["ship"], table["drive"], table["route"]))
        costs = design_costs(table, "ship" => ship, "drive" => drive, "route" => route)
        "none" in first.(costs) && allequal(length.(last.(costs))) ||
            throw(ArgumentError("$ship, $drive, $route lacks a design or a departure"))
        push!(errors, jackknife_error(indices -> departure_pair_gain(costs, indices),
            length(last(first(costs)))))
    end
    return errors
end

"(rig, cost per departure) of each design among the rows of `table` matching `conditions`"
function design_costs(table, conditions...)
    group = rows(table, conditions...)
    designs = unique(zip(table["rig"][group], table["kite_area"][group],
        table["rotor_area"][group]))
    return [(rig, table["cost"][rows(table, conditions..., "rig" => rig,
                "kite_area" => kite_area, "rotor_area" => rotor_area)])
            for (rig, kite_area, rotor_area) in designs]
end

"""
    pair_gain(saving)

Extra saving [% points] of the best pair over the better single rig, from a Dict `saving`
of the savings [%] of "kite", "rotors" and "kite+rotors".
"""
pair_gain(saving) = saving["kite+rotors"] - max(saving["kite"], saving["rotors"])

"""
    departure_pair_gain(costs, indices)

[`pair_gain`](@ref) on the mean cost over the departures `indices`, from `costs`, (rig,
cost per departure) of each design including the ship without a rig.
"""
function departure_pair_gain(costs, indices)
    reference = mean(only(cost for (rig, cost) in costs if rig == "none")[indices])
    savings = Dict{String, Float64}()
    for (rig, cost) in costs
        saving = percent_saving(mean(cost[indices]), reference)
        savings[rig] = max(get(savings, rig, -Inf), saving)
    end
    return pair_gain(savings)
end

"""
    combination_data()

Each class of `pair_classes` on each of `pair_routes` on VLSFO and e-ammonia without a rig
and at each of its [`pair_sizes`](@ref) from classes.csv: combination_pairs.csv per round
trip and combination_departures.csv per departure.
"""
function combination_data()
    classes_table = read_table(data_file("classes.csv"))
    kites = unique(classes_table["area"][rows(classes_table, "rig" => "kite")])
    cases = []
    for name in pair_classes, drive in (:vlsfo, :ammonia), route in pair_routes
        class = ship_classes()[name]
        hull = Hull(class, assumptions)
        kite = best_area(classes_table, name, string(route), string(drive), "kite")
        rotors = best_area(classes_table, name, string(route), string(drive), "rotors")
        room = largest_area("rotors", hull;
            forward_reserve=WindShipOpt.launch_mast_reserve(assumptions))
        for (rig, kite_area, rotor_area) in
            [("none", 0.0, 0.0);
             pair_sizes(kite, rotors, kites, (smallest_deck_rig_area, room))]
            design = ShipDesign(drive, class; kite_area, rotor_area)
            push!(cases, trip_case(design; route, ship=name, drive, rig, kite_area,
                rotor_area))
        end
    end
    trips = round_trips(cases, sampled_departures())
    labels = (:ship, :route, :drive, :rig, :kite_area, :rotor_area)
    write_trips("combination_pairs.csv", cases, trips, labels...)
    write_departures("combination_departures.csv", cases, trips, labels...)
end

"""
    traced_round_trip(table, route_table, name, departure, hourly)

The legs `out` and `back` [`route_round_trip`](@ref) finds on route `name` from `departure`
[h] at time costs `hourly` [USD/h], the time `back_departure` [h] the return leaves and the
[`LegTrace`](@ref) of each leg; `nothing` if either leg fails.
"""
function traced_round_trip(table, route_table, name, departure, hourly)
    outbound, inbound = run_corridors(name)
    hours = turnaround(route_table, outbound)
    trip = WindShipOpt.route_round_trip(route_table, outbound, inbound, weather, departure,
        hours, hourly, nothing)
    isnothing(trip) && return nothing
    out, back = trip
    back_departure = departure + hours
    return (; out, back, back_departure, out_trace=LegTrace(table, out, weather, departure),
        back_trace=LegTrace(table, back, weather, back_departure))
end

"""
    traced_legs(ship, name)

Routed round trips of `ship` on route `name` over the sampled departures, as a list of
each leg and its [`LegTrace`](@ref), with hours priced at the ship's time cost.
"""
function traced_legs(ship, name)
    table = PerformanceTable(ship, assumptions)
    route_table = RouteTable(table)
    hourly = WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions), assumptions)
    legs = []
    for departure in sampled_departures()
        trip = traced_round_trip(table, route_table, name, departure, hourly)
        isnothing(trip) && continue
        push!(legs, (trip.out, trip.out_trace), (trip.back, trip.back_trace))
    end
    return legs
end

"an empty band of [`add_flight_hours!`](@ref), in the order of the columns of flight.csv"
empty_flight_bin = (hours=0.0, flying=0.0, available=0.0, pulling=0.0, thrust_hours=0.0,
    distance=0.0, lowest_angle=Inf)

"""
    add_flight_hours!(bins, trace)

Add every point of the `trace` of a routed leg to `bins`, keyed by true wind angle band and
ship speed band: hours, flying hours, hours in which the rig could pull, hours in which it
pulled, net thrust-hours worked [kN h], distance [nmi] and the lowest apparent angle at
which it pulled [deg].
"""
function add_flight_hours!(bins, trace)
    for (i, hours) in enumerate(trace.hours)
        knots = trace.speed[i] / KNOT
        band = (min(floor(Int, rad2deg(trace.true_wind_angle[i]) / 30), 5) * 30,
            knots < 10 ? 8 : knots < 12 ? 10 : knots < 14 ? 12 : 14)
        pulling = trace.rig_thrust[i] > 0
        working = trace.flying[i] || pulling
        angle = pulling ? rad2deg(trace.apparent_angle[i]) : Inf
        old = get(bins, band, empty_flight_bin)
        bins[band] = (hours=old.hours + hours,
            flying=old.flying + trace.flying[i] * hours,
            available=old.available + (trace.available_thrust[i] > 0) * hours,
            pulling=old.pulling + pulling * hours,
            thrust_hours=old.thrust_hours + working * trace.rig_thrust[i] * hours / 1e3,
            distance=old.distance + knots * hours,
            lowest_angle=min(old.lowest_angle, angle))
    end
end

"""
    flight_bins(case)

Hours of a case of [`flight_data`](@ref) by band of true wind angle and ship speed (see
[`add_flight_hours!`](@ref)).
"""
function flight_bins(case)
    ship = Ship(ShipDesign(case.drive, case.length; rig_size(case.rig, case.area)...),
        assumptions; case.route)
    bins = Dict{Tuple{Int, Int}, typeof(empty_flight_bin)}()
    for (_, trace) in traced_legs(ship, case.route)
        add_flight_hours!(bins, trace)
    end
    return bins
end

"""
    flight_data()

Where the cheapest size of each rig of routes.csv works, over the ship lengths, drives and
routes of that study, without a rig as well: flight.csv, by band of true wind angle and of
ship speed.
"""
function flight_data()
    table = read_table(data_file("routes.csv"))
    cases = []
    for route in route_names, drive in study_drives, ship_length in (85.0, 140.0, 200.0),
        rig in ("none", "kite", "wings", "rotors")

        best = cheapest_row(table, "route" => string(route), "drive" => string(drive),
            "length" => ship_length, "rig" => rig)
        isnothing(best) || push!(cases, (; route, drive, length=ship_length, rig,
            area=table["area"][best]))
    end
    results = Vector{Any}(undef, length(cases))
    Threads.@threads :greedy for k in eachindex(cases)
        results[k] = flight_bins(cases[k])
    end
    open(run_file("flight.csv"), "w") do io
        println(io, "route,drive,length,rig,area,angle,speed,hours,flying,available,",
            "pulling,thrust_hours,distance,lowest_angle")
        for (case, bins) in zip(cases, results), (band, values) in sort(collect(bins))
            println(io, join((case.route, case.drive, case.length, case.rig, case.area,
                    band..., values...), ","))
        end
    end
end

"""
    mile_cost(ship, knots, hourly, wind_10m, angle, force, wear)

Cost [USD] of a nautical mile at `knots` [kn] by fuel, `wear` and `hourly` time cost
[USD/h], in a steady wind of `wind_10m` [m/s] from `angle` [rad], with the rig at its best
trim, or with its force held at `force` where that is not `nothing`.
"""
function mile_cost(ship, knots, hourly, wind_10m, angle, force, wear)
    speed = knots * KNOT
    thrust, pull = isnothing(force) ?
                   WindShipOpt.best_trim(ship, ship.rig, speed, wind_10m, angle) :
                   (WindShipOpt.required_thrust(ship, speed, wind_10m, angle, force), force)
    isfinite(thrust) || return Inf
    delivered = delivered_power(ship.propeller, ship.env, speed, thrust) +
                pull.power * ship.powertrain.transmission_efficiency
    fuel_cost = fuel_power(ship.powertrain, delivered) * 3600ship.fuel.price
    return (fuel_cost + hourly + wear) / knots
end

"""
    speed_range(ship)

Range of speeds [kn] from 4 kn to the top speed of `ship`, scanned about every knot.
"""
function speed_range(ship)
    top = ship.max_speed / KNOT
    return WindShipOpt.TrimRange(4.0, top, ceil(Int, top - 4.0) + 1, 1)
end

"""
    economic_speed(ship, hourly, wind_10m, angle; force=nothing,
                   wear=wear_cost(ship.rig, assumptions))

Speed [kn] on [`speed_range`](@ref) with the least [`mile_cost`](@ref).
"""
function economic_speed(ship, hourly, wind_10m, angle; force=nothing,
        wear=WindShipOpt.wear_cost(ship.rig, assumptions))
    return first(WindShipOpt.best_on_range(
        knots -> mile_cost(ship, knots, hourly, wind_10m, angle, force, wear),
        speed_range(ship)))
end

"""
    sailing_speed(ship, force, wind_10m, angle)

Highest speed [kn] on [`speed_range`](@ref) at which `ship` needs no propeller thrust with
the rig force held at `force`, in a steady wind of `wind_10m` [m/s] from `angle` [rad];
zero if none.
"""
function sailing_speed(ship, force, wind_10m, angle)
    thrust(knots) = WindShipOpt.required_thrust(ship, knots * KNOT, wind_10m, angle, force)
    span = speed_range(ship)
    thrust(span.high) <= 0 && return span.high
    sailing, least_thrust = WindShipOpt.best_on_range(thrust, span)
    least_thrust > 0 && return 0.0
    return first(WindShipOpt.sign_change(thrust, sailing, span.high, least_thrust,
        thrust(span.high), 1e-5))
end

"""
    speed_choice_data()

Cost-optimal speed of a 140 m ship without and with the reference rigs in steady winds, with
the rig force following the speed, the same without the rig's capital and wear in the cost,
with the force held at its value at the speed without a rig, and the speed at which that
held force alone moves the ship: speed_choice.csv.
"""
function speed_choice_data()
    open(run_file("speed_choice.csv"), "w") do io
        println(io, "drive,rig,area,wind,angle,bare,free,free_of_rig_cost,held,sailing")
        for drive in (:ammonia, :vlsfo)
            bare = Ship(ShipDesign(drive, 140.0), assumptions; route=:caribbean)
            hourly = first(WindShipOpt.leg_time_costs(ShipCosts(bare, assumptions),
                assumptions))
            for (rig, area) in reference_rigs, wind in (6.0, 10.0, 14.0),
                angle in (60, 90, 120, 150)

                ship = Ship(ShipDesign(drive, 140.0; rig_size(rig, area)...), assumptions;
                    route=:caribbean)
                ship_hourly = first(WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions),
                    assumptions))
                base = economic_speed(bare, hourly, wind, deg2rad(angle))
                force = WindShipOpt.best_trim(ship, ship.rig, base * KNOT, wind,
                    deg2rad(angle)).force
                println(io, join((drive, rig, area, wind, angle, base,
                        economic_speed(ship, ship_hourly, wind, deg2rad(angle)),
                        economic_speed(ship, hourly, wind, deg2rad(angle); wear=0.0),
                        economic_speed(ship, ship_hourly, wind, deg2rad(angle); force),
                        sailing_speed(ship, force, wind, deg2rad(angle))), ","))
            end
        end
    end
end

"""
    fixed_speed_sums(table, knots, name, hourly)

[`speed_term_sums`](@ref) of a ship that holds `knots` [kn] by
[`held_speed_table`](@ref WindShipOpt.held_speed_table) on the fastest track, with `hourly`
the cost [USD/h] of each leg on the [`PerformanceTable`](@ref) `table`.
"""
fixed_speed_sums(table, knots, name, hourly) = speed_term_sums(
    WindShipOpt.held_speed_table(table, knots), name,
    WindShipOpt.HELD_SPEED_TIME_FACTOR .* hourly, nothing)

"""
    speed_term_sums(table, name, hourly, durations)

Fuel energy [GJ], hours, kite flight hours and the leg durations of round trips on route
`name` over the sampled departures on the [`RouteTable`](@ref) `table`, each leg arriving
by its time in `durations` where given; `nothing` if a passage fails.
"""
function speed_term_sums(table, name, hourly, durations)
    corridors_of_route = run_corridors(name)
    legs = []
    for (k, departure) in enumerate(sampled_departures())
        schedule = isnothing(durations) ? (Inf, Inf) :
                   (durations[2k - 1], durations[2k])
        pair = WindShipOpt.route_round_trip(table, corridors_of_route..., weather,
            departure, turnaround(table, first(corridors_of_route)), hourly, nothing;
            schedule)
        isnothing(pair) && return nothing
        append!(legs, pair)
    end
    return sum(leg.fuel_energy for leg in legs) / 1e9, sum(leg.duration for leg in legs),
    sum(leg.flight_hours for leg in legs), [leg.duration for leg in legs]
end

"""
    speed_terms_data()

Fuel energy and hours of a 140 m ship without and with the reference rigs on two routes on
the terms the literature uses and on ours: routed for cost, in the same time as the ship
without a rig, and at 8, 9 and 10 kn: speed_terms.csv.
"""
function speed_terms_data()
    cases = vec([(; route, drive, rig, area) for route in (:caribbean, :new_york),
                 drive in (:ammonia, :vlsfo),
                 (rig, area) in reference_rigs_and_none])
    results = Vector{Any}(undef, length(cases))
    Threads.@threads :greedy for k in eachindex(cases)
        results[k] = speed_terms(cases[k])
    end
    open(run_file("speed_terms.csv"), "w") do io
        println(io, "route,drive,rig,area,terms,fuel,hours,flight_hours")
        for (case, rows_of_case) in zip(cases, results), (terms, sums) in rows_of_case
            isnothing(sums) && continue
            println(io, join((case.route, case.drive, case.rig, case.area, terms,
                    sums[1:3]...), ","))
        end
    end
end

"""
    speed_terms(case)

Rows of [`speed_terms_data`](@ref) for one case: the terms and their
[`speed_term_sums`](@ref).
"""
function speed_terms(case)
    ship = Ship(ShipDesign(case.drive, 140.0; rig_size(case.rig, case.area)...),
        assumptions; case.route)
    table = PerformanceTable(ship, assumptions)
    hourly = WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions), assumptions)
    free = RouteTable(table)
    rows_of_case = Any[("cost", speed_term_sums(free, case.route, hourly, nothing))]
    for knots in (8.0, 9.0, 10.0)
        push!(rows_of_case, (string(Int(knots), "kn"),
            fixed_speed_sums(table, knots, case.route, hourly)))
    end
    case.rig == "none" && return rows_of_case
    bare = Ship(ShipDesign(case.drive, 140.0), assumptions)
    bare_sums = speed_term_sums(RouteTable(PerformanceTable(bare, assumptions)), case.route,
        WindShipOpt.leg_time_costs(ShipCosts(bare, assumptions), assumptions), nothing)
    isnothing(bare_sums) || push!(rows_of_case, ("same_time",
        speed_term_sums(free, case.route, hourly, last(bare_sums))))
    return rows_of_case
end

"""
    routing_value_ships()

Ships of the routing value study, each as its name, its hull length [m] or class and its
route: the 140 m ship to Guadeloupe and the tramp and the liner of [`study_classes`](@ref).
"""
function routing_value_ships()
    ships = [("140 m", :caribbean); [(name, route) for (name, _, route) in study_classes]]
    return [(ship, study_hull(ship), route) for (ship, route) in ships]
end

"""
    routing_value_data()

The [`routing_value_ships`](@ref) on each of the [`study_drives`](@ref) without a rig,
routed for cost and on the shortest path through the corridors of their route at each of
their [`held_speeds`](@ref), and the 140 m ship with each of the [`reference_rigs`](@ref), routed,
each ship and drive over the [`sailable_departures`](@ref) of its ship on the shortest
route: routing_value.csv, and the cost of each departure: routing_value_departures.csv.
"""
function routing_value_data()
    groups = [(; ship, build, route, drive)
              for (ship, build, route) in routing_value_ships() for drive in study_drives]
    cases, trips = routing_value_trips(groups, sampled_departures())
    reruns = Dict{Any, Vector{Any}}()
    for group in groups
        failed = [case for (case, trip) in zip(cases, trips)
                  if isnothing(trip) && in_group(case, group)]
        isempty(failed) && continue
        push!(get!(reruns, sailable_departures(failed, sampled_departures()), []), group)
    end
    for (departures, rerun) in reruns
        kept = [!any(group -> in_group(case, group), rerun) for case in cases]
        again = routing_value_trips(rerun, departures)
        cases, trips = [cases[kept]; first(again)], [trips[kept]; last(again)]
    end
    labels = (:ship, :drive, :rig, :area, :course, :speed, :held_knots)
    write_trips("routing_value.csv", cases, trips, labels...)
    open(run_file("routing_value_departures.csv"), "w") do io
        println(io, join([collect(string.(labels)); ["departure", "cost"]], ","))
        for (case, trip) in zip(cases, trips)
            isnothing(trip) && continue
            fields = [csv_value(getproperty(case, label)) for label in labels]
            for outcome in trip.departures
                println(io, join([fields; csv_value(outcome.departure);
                        string(outcome.cost_per_tonne_km)], ","))
            end
        end
    end
end

"whether `case` is of the ship and drive of `group`"
in_group(case, group) = (case.ship, case.drive) == (group.ship, group.drive)

"""
    routing_value_trips(groups, departures)

Cases and round trips over `departures` of each ship, with its build, route and drive, in
`groups`: without a rig, and for the 140 m ship with each of the [`reference_rigs`](@ref),
routed, then without a rig on the shortest path through their corridors at each
[`held_speeds`](@ref).
"""
function routing_value_trips(groups, departures)
    routed = []
    for (; ship, build, route, drive) in groups
        for (rig, area) in [("none", 0.0); ship == "140 m" ? reference_rigs : []]
            design = ShipDesign(drive, build; rig_size(rig, area)...)
            push!(routed, trip_case(design; route, ship, drive, rig, area, speed="cost"))
        end
    end
    routed_trips = round_trips(routed, departures)
    held = []
    for (case, trip) in zip(routed, routed_trips)
        (case.rig == "none" && !isnothing(trip)) || continue
        paths = WindShipOpt.shortest_corridor.(case.corridors)
        for (speed, knots) in held_speeds(case, trip)
            push!(held, trip_case(case.design; case.route, case.ship, case.drive, case.rig,
                case.area, speed, paths, course=:shortest, held_knots=knots))
        end
    end
    return [routed; held], [routed_trips; round_trips(held, departures)]
end

"""
    sailable_departures(cases, departures)

The `departures` on which the round trip of each of `cases` succeeds alone.
"""
function sailable_departures(cases, departures)
    sails = fetch.([Threads.@spawn all(!isnothing(case_trip(case, [departure]))
                                       for case in cases) for departure in departures])
    return departures[sails]
end

"""
    held_speeds(case, trip)

Name and speed [kn] of each speed the ship of `case`, routed in `trip`, holds on the
shortest route: `same_time`, which sails its track in the routed ship's time at sea, and
for a class `operating`, the fleet's mean operating speed in data/ship_classes.csv.
"""
function held_speeds(case, trip)
    track = sum(corridor.track_length for corridor in case.corridors)
    hours = 24(trip.outbound_days + trip.return_days)
    speeds = ["same_time" => round(track / 3600hours / WindShipOpt.KNOT; digits=2)]
    case.ship == "140 m" && return speeds
    return push!(speeds, "operating" => operating_speed(case.ship))
end

"fleet's mean operating speed [kn] of the class named `ship` in data/ship_classes.csv"
function operating_speed(ship)
    classes = read_table(joinpath(root, "data", "ship_classes.csv"))
    return classes["operating_speed"][only(rows(classes, "name" => ship))]
end

"""
Conditions of published fixed-speed kite studies, each on the nearest ship of ours, on
VLSFO: the citation key, our ship, the kite area [m^2], the speeds [kn] and the route.
"""
published_voyages = [
    ("podeur2016", "feeder container ship", 800.0, (16.0, 19.0), :new_york),
    ("bentin2018", "Handysize bulk carrier", 800.0, (13.0,), :new_york),
    ("leloup2013", "MR product tanker", 320.0, (8.0, 15.5), :new_york),
    ("cedelft2016", "Handysize bulk carrier", 400.0, (10.5, 12.3), :new_york),
    ("traut2014", "Handysize bulk carrier", 500.0, (11.2,), :new_york)]

"""
Inputs with the kite flown free of canopy, tether and handling costs, which the published
fixed-speed studies leave out, so that it flies wherever that saves fuel.
"""
kite_without_running_cost = foldl((inputs, key) -> with_value(inputs, key, 0.0),
    (:market_price_factor, :tether_price, :kite_cycle_crew_cost, :kite_cycle_course_cost,
        :kite_launch_loss_probability);
    init=assumptions)

"""
    fixed_speed_voyage(hull, kite_area, inputs, knots, name)

[`fixed_speed_sums`](@ref) of the VLSFO ship on `hull` with `kite_area` [m^2] of kite under
`inputs`, its time priced as in the rest of the paper.
"""
function fixed_speed_voyage(hull, kite_area, inputs, knots, name)
    ship = Ship(ShipDesign(:vlsfo, hull; kite_area), inputs; route=name)
    hourly = WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions), assumptions)
    return fixed_speed_sums(PerformanceTable(ship, inputs), knots, name, hourly)
end

"""
    published_voyage_rows(source, ship_name, area, knots, name)

Row of published_terms.csv: fuel [GJ] of the ship at `knots` [kn] on route `name` without a
kite, with it priced as in our model and free of running cost, hours without and with it and
flight hours of the priced and the free kite; `nothing` if a passage fails.
"""
function published_voyage_rows(source, ship_name, area, knots, name)
    hull = study_hull(ship_name)
    sums = [fixed_speed_voyage(hull, kite_area, inputs, knots, name)
            for (kite_area, inputs) in ((0.0, assumptions), (area, assumptions),
                (area, kite_without_running_cost))]
    any(isnothing, sums) && return nothing
    bare, priced, free = sums
    return (source, ship_name, area, knots, name, bare[1], priced[1], free[1], bare[2],
        priced[2], priced[3], free[3])
end

"""
    published_terms_data()

Our model on the terms of published kite studies, each at its fixed speed on the nearest
of our ships: published_terms.csv.
"""
function published_terms_data()
    cases = [(source, ship, area, knots, name)
             for (source, ship, area, speeds, name) in published_voyages
             for knots in speeds]
    results = Vector{Any}(undef, length(cases))
    Threads.@threads :greedy for k in eachindex(cases)
        results[k] = published_voyage_rows(cases[k]...)
    end
    open(run_file("published_terms.csv"), "w") do io
        println(io, "source,ship,area,speed,route,fuel_bare,fuel_kite,fuel_free,",
            "hours_bare,hours_kite,flight_hours,flight_hours_free")
        foreach(row -> println(io, join(row, ",")), filter(!isnothing, results))
    end
end

"""
Speed trial of the ferry Copenhagen with one 30 m by 5 m rotor (Werner and Nisbet 2023,
SSPA report RE40201042-01-00-B): ship speed [kn], true wind at the rotor's mid-span [m/s],
rotor surface speed at 170 rpm [m/s], rotor area [m^2], its spin power as stated [kW], the
coefficients of its measured thrust coefficient over the apparent wind angle [deg]
(Appendix 1, Fig. 8), and per true wind angle [deg] the gross power saving [kW] and [%] and
the net saving [%] of its Table 9.
"""
copenhagen_trial = (knots=16.0, rotor_wind=11.8, surface_speed=π * 5.0 * 170 / 60,
    area=150.0, spin_power=99.0, thrust_fit=(-2.785, 0.1976, -8.744e-4),
    points=[(78.0, 1440.0, 27.0, 25.0), (102.0, 1366.0, 25.0, 24.0),
        (38.0, 548.0, 10.0, 8.0), (142.0, 557.0, 10.0, 9.0)])

"""
    copenhagen_row(true_angle)

At the true wind angle `true_angle` [deg] of [`copenhagen_trial`](@ref): the apparent wind
angle [deg] and speed [m/s], the spin ratio, the thrust coefficient of our rotor and the one
measured, and the spin power of our rotor [kW], with the rotor turning as on the trial.
"""
function copenhagen_row(true_angle)
    trial = copenhagen_trial
    speed, angle = apparent_wind(trial.rotor_wind, deg2rad(true_angle),
        trial.knots * WindShipOpt.KNOT)
    spin_ratio = min(WindShipOpt.MAX_SPIN_RATIO, trial.surface_speed / speed)
    lift, drag, power = WindShipOpt.rotor_coefficients(spin_ratio)
    model = assumptions[:rotor_lift_factor] * lift * sin(angle) - drag * cos(angle)
    measured = evalpoly(rad2deg(angle), trial.thrust_fit)
    air_density = Environment(assumptions).air_density
    spin_power = 0.5air_density * speed^3 * trial.area * power / 1e3
    return (true_angle, rad2deg(angle), speed, spin_ratio, model, measured, spin_power)
end

"""
Ships whose fuel saving with rotors or wing sails was measured at sea, each on the nearest
of our ships on VLSFO: the citation key, the ship, our ship, its rig, the rig area [m^2]
and our route.
"""
measured_ships = [
    ("lr2025trlady", "TR Lady", "Kamsarmax bulk carrier", "rotors", 360.0, :tubarao),
    ("norsepower2019pelican", "Maersk Pelican", "Aframax tanker", "rotors", 300.0,
        :houston),
    ("gcaptain2024pyxis", "Pyxis Ocean", "Kamsarmax bulk carrier", "wings", 1500.0,
        :tubarao),
    ("mol2024shofu", "Shofu Maru", "Aframax tanker", "wings", 800.0, :tubarao)]

"""
    measured_savings_data()

Our model on the terms of rotors and wing sails measured at sea: the rotor of the ferry
Copenhagen at the conditions of its speed trial, copenhagen.csv, and each of
[`measured_ships`](@ref) with and without its rig on the shortest course at its class's
operating speed, its fuel energy [GJ] per departure and its days at sea per round trip,
measured_savings.csv.
"""
function measured_savings_data()
    open(run_file("copenhagen.csv"), "w") do io
        println(io, "true_angle,apparent_angle,apparent_wind,spin_ratio,thrust_model,",
            "thrust_measured,spin_power")
        for (true_angle, _...) in copenhagen_trial.points
            println(io, join(copenhagen_row(true_angle), ","))
        end
    end
    cases = []
    for (source, name, ship, rig, area, route) in measured_ships
        knots = operating_speed(ship)
        scale = run_settings().corridor_scale
        paths = WindShipOpt.shortest_corridor.(corridors(route, scale))
        for (case_rig, case_area) in (("none", 0.0), (rig, area))
            design = ShipDesign(:vlsfo, study_hull(ship); rig_size(case_rig, case_area)...)
            push!(cases, trip_case(design; route, paths, course=:shortest,
                held_knots=knots, source, name, ship, rig=case_rig, area=case_area))
        end
    end
    trips = round_trips(cases, sampled_departures())
    open(run_file("measured_savings.csv"), "w") do io
        println(io, "source,name,ship,route,rig,area,departure,fuel_energy,days")
        for (case, trip) in zip(cases, trips)
            isnothing(trip) && continue
            tonne_km = trip.cargo * tonne_km_per_tonne(case.corridors...)
            for outcome in trip.departures
                println(io, join((case.source, case.name, case.ship, case.route, case.rig,
                        case.area, outcome.departure,
                        outcome.fuel_per_tonne_km * tonne_km / 1e3,
                        trip.outbound_days + trip.return_days), ","))
            end
        end
    end
end

"""
Ships, speeds and sizes of [`speed_size_data`](@ref): the ship, its drives, the speeds [kn]
it holds, the kite areas [m^2], and the wing and rotor areas [m^2].
"""
speed_size_grid = [
    (ship="140 m", drives=(:vlsfo, :ammonia), speeds=(8.0, 9.0, 10.0, 11.0),
        kites=(400.0, 800.0, 1600.0, 3200.0, 6400.0),
        wings=(750.0, 1500.0), rotors=(400.0, 800.0)),
    (ship="feeder container ship", drives=(:vlsfo,), speeds=(13.0, 16.0, 19.0),
        kites=(800.0, 1600.0, 3200.0, 6400.0, 12800.0),
        wings=(), rotors=())]

"""
    speed_size_routes(table, grid, drive, knots)

Routes of speed_size.csv on which, at `knots` [kn] on `drive`, the ship without a rig and
every kite of `grid` both free and priced have a round trip.
"""
function speed_size_routes(table, grid, drive, knots)
    cases = [("none", 0.0, "priced");
        vec([("kite", area, pricing)
             for area in grid.kites, pricing in ("free", "priced")])]
    sailed = [Set(table["route"][rows(table, "ship" => grid.ship, "drive" => drive,
                  "knots" => knots, "rig" => rig, "area" => area, "pricing" => pricing)])
              for (rig, area, pricing) in cases]
    return collect(intersect(sailed...))
end

"""
    speed_size_saving(table, ship, drive, routes, rig, area, pricing, knots)

Over `routes` of speed_size.csv, what `area` [m^2] of `rig` saves at `knots` [kn] against
the ship without a rig at that speed: fuel [%], fuel [GJ per round trip], cost [%], cost
[USD per 1000 tonne-km], the rig's mean share of sea time flown, and the bare ship's fuel
[GJ per round trip]; `nothing` without a route.
"""
function speed_size_saving(table, ship, drive, routes, rig, area, pricing, knots)
    isempty(routes) && return nothing
    case(rig_name, rig_area, rig_pricing) = filter(i -> table["route"][i] in routes,
        rows(table, "ship" => ship, "drive" => drive, "knots" => knots, "rig" => rig_name,
            "area" => rig_area, "pricing" => rig_pricing))
    rigged, bare = case(rig, area, pricing), case("none", 0.0, "priced")
    fuel_saved = mean(table["fuel"][bare] .- table["fuel"][rigged])
    cost_saved = mean(table["cost"][bare] .- table["cost"][rigged])
    return (fuel_percent=100fuel_saved / mean(table["fuel"][bare]), fuel=fuel_saved,
        cost_percent=100cost_saved / mean(table["cost"][bare]), cost=1e3cost_saved,
        flight=100mean(table["flight_share"][rigged]), bare_fuel=mean(table["fuel"][bare]))
end

"""
    speed_size_case(ship, drive, route, knots, rig, area, pricing)

Round trip of `ship` with `area` [m^2] of `rig`, holding `knots` [kn], or with speed set by
cost where 0; `pricing` "free" takes the kite's running cost out.
"""
function speed_size_case(ship, drive, route, knots, rig, area, pricing)
    design = ShipDesign(drive, study_hull(ship); rig_size(rig, area)...)
    return trip_case(design; ship, drive, route, knots, rig, area, pricing,
        assumptions=pricing == "free" ? kite_without_running_cost : assumptions,
        held_knots=knots > 0 ? knots : nothing)
end

"""
    speed_size_cases()

Cases of [`speed_size_data`](@ref): every ship, drive, route, rig size and speed of
[`speed_size_grid`](@ref), with speed also set by cost, priced as in the rest of the paper,
and at held speeds the kite also free of its running cost.
"""
function speed_size_cases()
    cases = NamedTuple[]
    for grid in speed_size_grid, drive in grid.drives, route in (:caribbean, :new_york),
        knots in (0.0, grid.speeds...)

        base = (grid.ship, drive, route, knots)
        push!(cases, speed_size_case(base..., "none", 0.0, "priced"))
        for area in grid.kites, pricing in (knots > 0 ? ("priced", "free") : ("priced",))
            push!(cases, speed_size_case(base..., "kite", area, pricing))
        end
        for (rig, areas) in (("wings", grid.wings), ("rotors", grid.rotors)), area in areas
            push!(cases, speed_size_case(base..., rig, area, "priced"))
        end
    end
    return cases
end

"""
    speed_size_data()

Fuel energy, cost, time and kite flight of round trips over ship speed and rig size on the
same terms, without a rig and with it: speed_size.csv.
"""
function speed_size_data()
    cases = speed_size_cases()
    trips = round_trips(cases, sampled_departures())
    open(run_file("speed_size.csv"), "w") do io
        println(io, "ship,drive,route,knots,rig,area,pricing,fuel,cost,tonne_km,days,",
            "flight_share,launches,cargo")
        for (case, trip) in zip(cases, trips)
            isnothing(trip) && continue
            println(io, join((case.ship, case.drive, case.route, case.knots, case.rig,
                    case.area, case.pricing, trip.fuel_energy, trip.cost_per_tonne_km,
                    1e3trip.fuel_energy / trip.fuel_per_tonne_km,
                    trip.outbound_days + trip.return_days, trip.flight_share, trip.launches,
                    trip.cargo), ","))
        end
    end
end

"ship, drive, and kite, wing sail and rotor areas [m^2] of the router decisions study"
router_decision_ships = (("140 m", :ammonia, (1600.0, 1500.0, 800.0)),
    ("Kamsarmax bulk carrier", :vlsfo, (3200.0, 3000.0, 1600.0)))

"""
    router_decision_case(ship, drive, rig, area, route)

The route tables of `ship` on `drive` with `area` [m^2] of `rig` and without a rig, the
time price [USD/h] of each leg of the ship with the rig, and the corridors of `route`.
"""
function router_decision_case(ship, drive, rig, area, route)
    rigged = Ship(ShipDesign(drive, study_hull(ship); rig_size(rig, area)...), assumptions;
        route)
    bare = Ship(ShipDesign(drive, study_hull(ship)), assumptions; route)
    hourly = WindShipOpt.leg_time_costs(first(WindShipOpt.ship_costs(rigged, assumptions)),
        assumptions)
    table = RouteTable(PerformanceTable(rigged, assumptions))
    return (; ship, rig, area, route, table, hourly, corridors=run_corridors(route),
        bare=RouteTable(PerformanceTable(bare, assumptions)))
end

"`table` with the kite's launches and landings free"
free_launch_table(table::RouteTable) = WindShipOpt.with_changed(table;
    table=WindShipOpt.with_changed(table.table; cycle_cost=0.0))

"""
    stateless_table(table)

`table` with the kite up wherever that pays: its launches and landings free, instant and
open to any wind, sea and hour, so its state carries nothing.
"""
function stateless_table(table::RouteTable)
    performance = table.table
    rig = WindShipOpt.with_changed(performance.ship.rig; launch_min_wind=0.0,
        launch_max_wind=Inf, launch_max_wave_height=Inf, landing_max_wind=Inf,
        landing_max_wave_height=Inf, rough_sea_launch_wind=0.0)
    return WindShipOpt.with_changed(table; table=WindShipOpt.with_changed(performance;
        ship=WindShipOpt.with_changed(performance.ship; rig), cycle_cost=0.0,
        handling_hours=0.0))
end

"""
    router_decision_passages(case, departure)

Each leg of the round trip of `case` from `departure`, planned as in the results: its cost
for the ship without a rig, for the rig, and for the rig held to the path planned without
it; for a kite also its free-launch plan charged for each launch it makes, and the plan of
[`stateless_table`](@ref) as reported and with the real kite held to its path. Every
variant of the return leaves after the [`turnaround`](@ref). Stops at a leg the planner
cannot sail.
"""
function router_decision_passages(case, departure)
    rows = NamedTuple[]
    kite = case.rig == "kite"
    for (leg, corridor, time_cost, start) in zip(("out", "back"), case.corridors,
        case.hourly, (departure, departure + turnaround(case.table, first(case.corridors))))
        searched = leg_plan(case.table, corridor, start, time_cost)
        without = leg_plan(case.bare, corridor, start, time_cost)
        (isnothing(searched) || isnothing(without)) && break
        free, stateless = kite ?
            (leg_plan(free_launch_table(case.table), corridor, start, time_cost),
             leg_plan(stateless_table(case.table), corridor, start, time_cost)) :
            (nothing, nothing)
        push!(rows, (; case.ship, case.rig, case.area, case.route, departure, leg,
            without=without.objective, searched=searched.objective,
            alone=held_objective(without, corridor, case.table, start, time_cost),
            free=isnothing(free) ? NaN :
                 free.objective + free.launches * case.table.table.cycle_cost,
            stateless=leg_objective(stateless),
            stateless_sailed=held_objective(stateless, corridor, case.table, start,
                time_cost),
            searched_launches=searched.launches,
            free_launches=isnothing(free) ? -1 : free.launches))
    end
    return rows
end

"[`forecast_route`](@ref) of `table` through `corridor` from `start` [h] at `time_cost`"
leg_plan(table, corridor, start, time_cost) =
    forecast_route(corridor, table, weather, start; time_cost)

"objective of `leg`, NaN where there is none"
leg_objective(leg) = isnothing(leg) ? NaN : leg.objective

"""
    held_objective(leg, corridor, table, start, time_cost)

Objective of the ship of `table` planned from `start` [h] along the path of `leg` through
`corridor`, NaN where there is no `leg` or no passage along it.
"""
function held_objective(leg, corridor, table, start, time_cost)
    isnothing(leg) && return NaN
    path = WindShipOpt.path_corridor(leg, corridor, 1)
    return leg_objective(leg_plan(table, path, start, time_cost))
end

"""
    router_decisions_data()

What planning with the rig is worth: on the routes to Guadeloupe, New York and Tubarão,
each rig of [`router_decision_ships`](@ref) planned per leg by
[`router_decision_passages`](@ref): router_decisions.csv.
"""
function router_decisions_data()
    cases = [router_decision_case(ship, drive, rig, area, route)
             for (ship, drive, areas) in router_decision_ships
             for (rig, area) in zip(("kite", "wings", "rotors"), areas)
             for route in (:caribbean, :new_york, :tubarao)]
    passages = vec(collect(Iterators.product(cases, sampled_departures())))
    found = Vector{Vector{NamedTuple}}(undef, length(passages))
    Threads.@threads :greedy for k in eachindex(passages)
        found[k] = router_decision_passages(passages[k]...)
    end
    rows = reduce(vcat, found)
    open(run_file("router_decisions.csv"), "w") do io
        println(io, join(keys(first(rows)), ","))
        foreach(row -> println(io, join(csv_value.(values(row)), ",")), rows)
    end
end

"""
    today_routing_data()

The 140 m e-ammonia ship to Guadeloupe without a rig and with the kite and the rotors at
their reference sizes, on each departure of a final run alone: its cost [USD/tkm] with each
goal at its value known today, costed on the route found at the goals and routed anew:
today_routing.csv.
"""
function today_routing_data()
    rigs = filter(((rig, _),) -> rig != "wings", reference_rigs)
    goals = [trip_case(ShipDesign(:ammonia, 140.0; rig_size(rig, area)...); rig, area)
             for (rig, area) in [("none", 0.0); rigs]]
    today = at_today(assumptions)
    cases = [goals; [merge(case, (; assumptions=today)) for case in goals]]
    chosen = departures[1:fidelities[:final].departure_step:end]
    trips = fetch.([Threads.@spawn round_trips(cases, [departure]) for departure in chosen])
    open(run_file("today_routing.csv"), "w") do io
        println(io, "rig,area,departure,recosted,rerouted")
        for (departure, routed) in zip(chosen, trips), (k, case) in enumerate(goals)
            found, again = routed[k], routed[length(goals) + k]
            (isnothing(found) || isnothing(again)) && continue
            println(io, join([case.rig, csv_value(case.area), csv_value(departure),
                    @sprintf("%.6f", changed_cost(cases[length(goals) + k], found)),
                    @sprintf("%.6f", again.cost_per_tonne_km)], ","))
        end
    end
end

"""
    ProfileWind(weather)

`weather` without its wind aloft: a kite takes the 10 m wind on the power-law profile of
its ship's table.
"""
struct ProfileWind
    weather::ERA5Weather
end

WindShipOpt.wind(profile::ProfileWind, lat, lon, time) =
    wind(profile.weather, lat, lon, time)
WindShipOpt.waves(profile::ProfileWind, lat, lon, time) =
    waves(profile.weather, lat, lon, time)
WindShipOpt.duration(profile::ProfileWind) = WindShipOpt.duration(profile.weather)

"heights [m] of ERA5's wind aloft that the kite's patterns span, to fit a profile over"
shear_fit_heights = 100:100:700

"""
    shear_fit(cells, times)

Over the wind grid's `cells` (longitude and latitude index) and time steps `times`: the
ERA5 mean wind speed at 100 and 500 m per unit of the mean 10 m wind [-], and the exponents
[-] of the power law through 10 m fitted, by least squares in the logarithms, to that ratio
over [`shear_fit_heights`](@ref) and to the ratio of the cube roots of the mean cubes.
"""
function shear_fit(cells, times)
    levels = [findfirst(==(height), weather.aloft_heights) for height in shear_fit_heights]
    speeds, cubes = zeros(length(levels) + 1), zeros(length(levels) + 1)
    for (i, j) in cells, t in times
        for (k, speed) in enumerate((hypot(weather.wind_arrays[1][i, j, t],
                    weather.wind_arrays[2][i, j, t]),
                (weather.aloft_arrays[level][i, j, t] for level in levels)...))
            speeds[k] += speed
            cubes[k] += speed^3
        end
    end
    logs = log.(shear_fit_heights ./ 10)
    exponent(ratios) = sum(logs .* log.(ratios)) / sum(abs2, logs)
    ratios = speeds[2:end] ./ speeds[1]
    return (ratio_100=ratios[1], ratio_500=ratios[findfirst(==(500), shear_fit_heights)],
        exponent=exponent(ratios), cube_exponent=exponent(cbrt.(cubes[2:end] ./ cubes[1])))
end

"whether the wind grid's cell at longitude index `i` and latitude index `j` lies at sea"
at_sea(i, j) = !isnan(first(WindShipOpt.sample(weather.waves, (weather.wave_arrays[1],),
    weather.wind.lats[j], weather.wind.lons[i], 0.0)))

"""
    route_cells(route)

Wind grid cells (longitude and latitude index) at sea nearest the centre line of the
outbound corridor of `route`.
"""
function route_cells(route)
    outbound = first(corridors(route, run_settings().corridor_scale))
    centre = centre_index(outbound)
    nearest(grid, value) = argmin(abs.(grid .- value))
    cells = unique((nearest(weather.wind.lons, outbound.lon[stage, centre]),
                    nearest(weather.wind.lats, outbound.lat[stage, centre]))
                   for stage in axes(outbound.lat, 1))
    return filter(cell -> at_sea(cell...), cells)
end

"""
    wind_shear_rows()

[`shear_fit`](@ref) over 2017-2019 at sea in the whole region, in its trade-wind belt
(10-25 deg N) and north of 40 deg N, along all routes, along each, and along all routes in
each season.
"""
function wind_shear_rows()
    lons, lats = eachindex(weather.wind.lons), eachindex(weather.wind.lats)
    sea = [(i, j) for i in lons, j in lats if at_sea(i, j)]
    band(low, high) = filter(((i, j),) -> low <= weather.wind.lats[j] <= high, sea)
    along = Dict(route => route_cells(route) for route in route_names)
    routes = unique(reduce(vcat, values(along)))
    times = axes(first(weather.wind_arrays), 3)
    month(t) = Dates.month(weather.origin + Hour(weather.wind.step_hours * (t - 1)))
    seasons = ("winter" => (12, 1, 2), "spring" => (3, 4, 5), "summer" => (6, 7, 8),
        "autumn" => (9, 10, 11))
    places = ["sea" => (sea, times), "trade winds" => (band(10, 25), times),
        "north of 40" => (band(40, 90), times), "routes" => (routes, times),
        [string(route) => (along[route], times) for route in route_names]...,
        [season => (routes, filter(t -> month(t) in months, times))
         for (season, months) in seasons]...]
    return [(; place, shear_fit(cells, chosen)...) for (place, (cells, chosen)) in places]
end

"""
    wind_height_data()

How a kite's wind at its height bears on its saving. ERA5's shear by [`wind_shear_rows`]
(@ref): wind_shear.csv. The 140 m e-ammonia ship to Guadeloupe without a rig, with the kite
and with the rotors at their reference sizes, on each departure of a final run alone, with
the kite on ERA5's hourly wind at its height and on the power laws of the exponent fitted
along the routes, that plus 0.01 and the one fitted to the cubes: its cost [USD/tkm] and
share of the time aloft, wind_height.csv.
"""
function wind_height_data()
    shear = wind_shear_rows()
    open(run_file("wind_shear.csv"), "w") do io
        println(io, join(keys(first(shear)), ","))
        foreach(row -> println(io, join(csv_value.(values(row)), ",")), shear)
    end
    fit = only(filter(row -> row.place == "routes", shear))
    exponents = round.([fit.exponent, fit.exponent + 0.01, fit.cube_exponent]; digits=3)
    design(rig) = ShipDesign(:ammonia, 140.0;
        rig_size(rig, Dict(reference_rigs_and_none)[rig])...)
    arms = [[("hourly", 0.0, rig, assumptions, weather) for rig in ("none", "kite", "rotors")];
        [("profile", exponent, "kite",
          with_value(assumptions, :wind_shear_exponent, exponent), ProfileWind(weather))
         for exponent in exponents]]
    chosen = departures[1:fidelities[:final].departure_step:end]
    jobs = [(arm, departure) for arm in arms for departure in chosen]
    outcomes = fetch.([Threads.@spawn wind_height_outcome(arm, departure, design)
                       for (arm, departure) in jobs])
    open(run_file("wind_height.csv"), "w") do io
        println(io, "wind,exponent,rig,departure,cost,flight_share")
        for (((wind, exponent, rig), departure), outcome) in zip(jobs, outcomes)
            isnothing(outcome) && continue
            println(io, join([wind, csv_value(exponent), rig, csv_value(departure),
                    @sprintf("%.6f", outcome.cost_per_tonne_km),
                    @sprintf("%.4f", outcome.flight_share)], ","))
        end
    end
end

"""
    wind_height_outcome((wind, exponent, rig, assumptions, weather), departure, design)

Outcome of the round trip to Guadeloupe from `departure` [h] of the ship `design(rig)`
under `assumptions` in `weather`; `nothing` where it fails.
"""
function wind_height_outcome((_, _, rig, assumptions, weather), departure, design)
    ship = Ship(design(rig), assumptions; route=:caribbean)
    trip = round_trip(ship, corridors(:caribbean, run_settings().corridor_scale)...,
        weather, [departure], assumptions)
    return isnothing(trip) ? nothing : only(trip.departures)
end

"""
    bound_change(name, bound)

Relative change [-] of input `name` of [`development_inputs`](@ref) at `bound`, of the first
of its inputs where it moves several.
"""
function bound_change(name, bound)
    measure = haskey(joint_inputs, name) ? first(keys(joint_inputs[name])) : name
    return bound_assumptions(name, bound)[measure] / assumptions[measure] - 1
end

"""
    recosting_changes()

Each change the paper recosts rather than routes anew, at the end of its range where its
recosting bias is measured, as (name, relative change [-], assumptions): each of the
[`development_inputs`](@ref) moving only [`cost_only_inputs`](@ref) at the bound farther
from its base, and the kite's share out of service and the canopy price at the top of
their ranges.
"""
function recosting_changes()
    changes = []
    for entry in development_inputs
        bounds = [(bound_change(entry.input, bound), bound_assumptions(entry.input, bound))
                  for bound in (:low, :high)]
        all(cost_only ∘ last, bounds) || continue
        push!(changes, (string(entry.input), argmax(abs ∘ first, bounds)...))
    end
    service = assumptions.entries[:kite_out_of_service]
    push!(changes, ("kite_out_of_service", service.high / service.value - 1,
        with_value(assumptions, :kite_out_of_service, service.high)))
    price = canopy_price_at(:high)
    push!(changes, ("canopy_price", price / reference_canopy_price(assumptions) - 1,
        at_canopy_price(price)))
    return changes
end

"""
    recosting_departures()

The three departures [h] the recosting bias is measured on: the first of the winter, of the
spring and of the summer.
"""
recosting_departures() = [departures[findfirst(>=(24.0 * day), departures)]
                          for day in (0, 90, 181)]

"""
    recosting_bias_data()

The 140 m e-ammonia ship to Guadeloupe without a rig and with each of the
[`reference_rigs`](@ref), at the base inputs and at each of [`recosting_changes`](@ref), on
each of the [`recosting_departures`](@ref) alone: its cost [USD/tkm] and CO2 [g/tkm] costed
on the routes at the base inputs and routed anew, recosting_bias.csv.
"""
function recosting_bias_data()
    designs = [(ShipDesign(:ammonia, 140.0; rig_size(rig, area)...), rig)
               for (rig, area) in reference_rigs_and_none]
    base = [trip_case(design; rig, change="base", relative=0.0)
            for (design, rig) in designs]
    changed = [trip_case(design; assumptions=inputs, rig, change=name, relative)
               for (name, relative, inputs) in recosting_changes()
               for (design, rig) in designs]
    cases = [base; changed]
    chosen = recosting_departures()
    routed = fetch.([Threads.@spawn (round_trips(cases, [departure]),
                         recosted_trips(changed, [departure])) for departure in chosen])
    open(run_file("recosting_bias.csv"), "w") do io
        println(io, "change,relative,rig,departure,cost_recosted,cost_rerouted,",
            "carbon_recosted,carbon_rerouted")
        for (departure, (rerouted, recosted)) in zip(chosen, routed)
            kept = [rerouted[eachindex(base)]; recosted]
            for (case, again, trip) in zip(cases, rerouted, kept)
                (isnothing(again) || isnothing(trip)) && continue
                @printf(io, "%s,%.6f,%s,%.0f,%.6f,%.6f,%.4f,%.4f\n", case.change,
                    case.relative, case.rig, departure, trip.cost_per_tonne_km,
                    again.cost_per_tonne_km, trip.carbon_per_tonne_km,
                    again.carbon_per_tonne_km)
            end
        end
    end
end

"""
    recosting_gap(table, change, rig; column="cost")

Points of saving of `column` (`"cost"` or `"carbon"`) per tonne-km that routing anew gains
`rig` over recosting at `change` in the recosting_bias.csv `table`, on each departure the
table holds both for `rig` and the ship without a rig, in its order.
"""
function recosting_gap(table, change, rig; column="cost")
    days(name) = rows(table, "change" => change, "rig" => name)
    bare = Dict(table["departure"][row] => row for row in days("none"))
    saving(row, kind) = percent_saving(table["$(column)_$kind"][row],
        table["$(column)_$kind"][bare[table["departure"][row]]])
    return [saving(row, "rerouted") - saving(row, "recosted")
            for row in days(rig) if haskey(bare, table["departure"][row])]
end

"""
    recosting_error(table, change, relative, rig; column="cost")

Error [points] of the saving of `rig` recosted at `relative` change [-] of `change`: the
mean over the departures of its [`recosting_gap`](@ref), at least zero for the cost, scaled
by the square of `relative` over the change the table measured it at; zero for a change the
table does not hold.
"""
function recosting_error(table, change, relative, rig; column="cost")
    gaps = recosting_gap(table, change, rig; column)
    isempty(gaps) && return 0.0
    measured = table["relative"][first(rows(table, "change" => change))]
    gain = column == "cost" ? max(mean(gaps), 0.0) : mean(gaps)
    return gain * (relative / measured)^2
end
