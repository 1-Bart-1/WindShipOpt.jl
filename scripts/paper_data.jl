# Data steps of the paper: each runs one study and writes its data files to the directory
# of the run in use. Included by paper.jl.

"drives compared where the drive is a dimension of the study"
study_drives = (:vlsfo, :methanol, :hydrogen)

"projected aspect ratio of the kite of every design that names none"
design_aspect_ratio = ShipDesign(:vlsfo, 100.0).kite_aspect_ratio

"""
    trip_case(design; assumptions, route, scale, horizon, held_knots, labels...)

One round trip to compute: `design` under `assumptions` on the corridors of `route` at
corridor `scale`, with a forecast `horizon` [h], holding `held_knots` [kn] or with speed set
by cost where `nothing`, tagged with `labels` for the output.
"""
function trip_case(design; assumptions=assumptions, route=:caribbean,
        scale=run_settings().corridor_scale, horizon=Inf, held_knots=nothing, labels...)
    return (; labels..., design, assumptions, route, scale,
        corridors=corridors(route, scale), horizon, held_knots)
end

"""
    case_trip(case, departures)

Round trip of `case` over `departures`, or `nothing` where its ship does not exist or a
passage fails.
"""
function case_trip(case, departures)
    ship = Ship(case.design, case.assumptions)
    isnothing(ship) && return nothing
    return round_trip(ship, case.corridors..., weather, departures, case.assumptions;
        horizon=case.horizon, held_knots=case.held_knots)
end

"""
    round_trips(cases, departures)

Round trips of all `cases`, threaded, reusing those cached in the run in use; the kite
pattern tables of the others are computed first, one kite at a time.
"""
function round_trips(cases, departures)
    paths = [case_path(case, departures) for case in cases]
    isempty(paths) || mkpath(dirname(first(paths)))
    cached = isfile.(paths)
    for (case, is_cached) in zip(cases, cached)
        !is_cached && case.design.kite_area > 0 && Ship(case.design, case.assumptions)
    end
    trips = Vector{Any}(nothing, length(cases))
    Threads.@threads :greedy for k in eachindex(cases)
        trips[k] = stored_trip(cases[k], departures, paths[k])
    end
    feasible = count(!isnothing, trips)
    paper_run.cases += length(cases)
    paper_run.trips += feasible
    println("  ", feasible, " of ", length(cases), " round trips, ", count(cached),
        " cached")
    return trips
end

"""
    write_trips(name, cases, trips, columns...)

Write `name` to the directory of the run in use with the given label `columns` of each
case and the cost [USD/tkm], fuel [MJ/tkm], CO2 [kg/tkm], round-trip days, kite flight
share, kite launches and forced landings per round trip, cargo [t] and whether the
rig retracts, of each feasible trip.
"""
function write_trips(name, cases, trips, columns...)
    open(run_file(name), "w") do io
        println(io, join([collect(string.(columns)); ["cost", "fuel", "carbon", "days",
            "flight_share", "launches", "forced_landings", "cargo", "retractable"]], ","))
        for (case, trip) in zip(cases, trips)
            isnothing(trip) && continue
            labels = [csv_value(getproperty(case, column)) for column in columns]
            @printf(io, "%s,%.6f,%.5f,%.3f,%.2f,%.3f,%.2f,%.2f,%.0f,%s\n",
                join(labels, ","), trip.cost_per_tonne_km, trip.fuel_per_tonne_km,
                trip.carbon_per_tonne_km, trip.outbound_days + trip.return_days,
                trip.flight_share, trip.launches, trip.forced_landings, trip.cargo,
                trip.retractable)
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

"inputs that together make up the cost of one launch and landing of a kite"
launch_cost_inputs = (:kite_cycle_crew_cost, :kite_cycle_damage_probability,
    :kite_cycle_loss_probability, :kite_launch_retry_probability, :kite_cycle_course_cost,
    :kite_launch_minutes, :kite_landing_minutes)

"""
    launch_cost_assumptions(bound)

Inputs with every one of `launch_cost_inputs` at its `bound` (`:low`, `:high` or `:value`).
"""
launch_cost_assumptions(bound) = foldl(launch_cost_inputs; init=assumptions) do inputs, name
    with_value(inputs, name, getfield(assumptions.entries[name], bound))
end

"""
    launch_data()

The 140 m e-methanol ship on every route without a rig, with the reference wings and
rotors, and with kites of 800, 1,600 and 3,200 m^2 at the low, base and high launch cost,
with launches by day only and with no rig ever out of service: launch.csv.
"""
function launch_data()
    always_in_service = reduce((changed, input) -> with_value(changed, input, 0.0),
        Symbol.(values(out_of_service_inputs)); init=assumptions)
    day_only = with_value(assumptions, :kite_night_launch, 0.0)
    cases = []
    labels = (; launch_cost="value", night=true, service=true)
    for route in route_names
        for (rig, area) in (("none", 0.0), ("wings", 1500.0), ("rotors", 800.0))
            design = ShipDesign(:methanol, 140.0; rig_size(rig, area)...)
            push!(cases, trip_case(design; labels..., route, rig, area))
            rig == "none" && continue
            push!(cases, trip_case(design; labels..., assumptions=always_in_service, route,
                rig, area, service=false))
        end
        for area in (800.0, 1600.0, 3200.0)
            design = ShipDesign(:methanol, 140.0; rig_size("kite", area)...)
            kite = (; labels..., route, rig="kite", area)
            for launch_cost in (:low, :value, :high)
                push!(cases, trip_case(design; kite...,
                    assumptions=launch_cost_assumptions(launch_cost),
                    launch_cost=string(launch_cost)))
            end
            push!(cases, trip_case(design; kite..., assumptions=day_only, night=false))
            push!(cases, trip_case(design; kite..., assumptions=always_in_service,
                service=false))
        end
    end
    write_trips("launch.csv", cases, round_trips(cases, sampled_departures()), :route, :rig,
        :area, :launch_cost, :night, :service)
end

"""
    patterns_data()

Optimal flight patterns of the base 800 m^2 kite over the ship's course off the apparent
downwind direction in light and strong apparent wind: patterns.csv (path points) and
pattern_forces.csv.
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

Force of the optimal pattern at apparent wind `wind` [m/s] and `course` [°], and the steps
of its steered cycle.
"""
function best_pattern_cycle(model, max_force, min_elevation, wind, course, side_weight)
    problem = WindShipOpt.PatternProblem(model, max_force, min_elevation, wind,
        deg2rad(course), side_weight)
    force, parameters = WindShipOpt.optimal_pattern(problem,
        WindShipOpt.pattern_starts(deg2rad(course)))
    path = WindShipOpt.PatternStep[]
    WindShipOpt.PatternForce(model, WindShipOpt.pattern_of(parameters), wind, max_force;
        path)
    return force, path
end

"""
    write_pattern(paths, forces, model, max_force, min_elevation, wind, course,
                  side_weight)

Optimise one pattern and write its force and its path.
"""
function write_pattern(paths, forces, model, max_force, min_elevation, wind, course,
        side_weight)
    force, path = best_pattern_cycle(model, max_force, min_elevation, wind, course,
        side_weight)
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

"""
    kite_market_prices()

The assumptions with every kite hardware and canopy price and the market price factor at
their high bounds.
"""
function kite_market_prices()
    names = (:winch_fixed_cost, :winch_cost_per_force, :launch_mast_mass_coefficient,
        :docking_head_cost, :control_unit_cost, :control_unit_cost_per_area,
        :kite_integration_fraction, :canopy_making_cost_per_area,
        :canopy_cloth_base_price, :canopy_cloth_price_per_weight, :market_price_factor)
    return changed_assumptions(NamedTuple(name => assumptions.entries[name].high
                                          for name in names))
end

"design keyword of each rig"
rig_keywords = Dict("kite" => :kite_area, "wings" => :wing_area, "rotors" => :rotor_area)

"""
    rig_size(rig, area)

Design keywords for `area` [m^2] of `rig`; none for "none".
"""
rig_size(rig, area) = rig == "none" ? (;) : NamedTuple{(rig_keywords[rig],)}((area,))

"""
    study_hull(ship)

Length of the 140 m reference ship, or the ship class of name `ship`, for a design.
"""
study_hull(ship) = ship == "140 m" ? 140.0 : ship_classes()[ship]

"reference size of each rig on the 140 m ship"
reference_rigs = [("kite", 3200.0), ("wings", 1500.0), ("rotors", 800.0)]

"the rigs, as named in the output"
rig_names = ("kite", "wings", "rotors")

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
scaled_inputs = Dict(:wing_price => (:wing_unit_cost, :wing_cost_per_area))

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
it changes. Prices are in USD/GJ, cargo value in USD/t, lifetimes in years, the rotor
surface speed in m/s; the wing price is a factor.
"""
situation_inputs = Dict(:vlsfo_price => ((8.0, 12.0, 22.0, 30.0), all_rigs),
    :e_methanol_price => ((30.0, 40.0, 90.0, 120.0), all_rigs),
    :cargo_value => ((1000.0, 5000.0, 10000.0, 20000.0), all_rigs),
    :discount_rate => ((0.04, 0.06, 0.1, 0.12, 0.16), all_rigs),
    :wing_lifetime => ((10.0, 15.0, 25.0, 30.0), ("wings",)),
    :wing_price => ((0.25, 0.5, 0.75, 1.5), ("wings",)),
    :rotor_max_surface_speed => ((35.0, 40.0, 55.0, 65.0), ("rotors",)))

"rig sizes [m^2] of each ship of the situation study"
situation_sizes = Dict(
    "140 m" => Dict("kite" => (800.0, 1600.0, 3200.0, 6400.0),
        "wings" => (800.0, 1500.0, 2400.0), "rotors" => (400.0, 800.0, 1600.0)),
    "Kamsarmax bulk carrier" => Dict("kite" => (1600.0, 3200.0, 6400.0),
        "wings" => (1600.0, 2400.0, 3600.0), "rotors" => (850.0, 1200.0, 1890.0)))

"""
Ship, route, drive and inputs of each part of the situation study: every input on the
140 m reference ship to Guadeloupe and all but the cargo value on a Kamsarmax to Tubarão.
"""
situation_studies = [("140 m", :caribbean, :vlsfo, [:vlsfo_price]),
    ("140 m", :caribbean, :methanol, [:e_methanol_price, :cargo_value, :discount_rate,
        :wing_lifetime, :wing_price, :rotor_max_surface_speed]),
    ("Kamsarmax bulk carrier", :tubarao, :vlsfo, [:vlsfo_price]),
    ("Kamsarmax bulk carrier", :tubarao, :methanol, [:e_methanol_price, :discount_rate,
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
    add_leg!(sums, leg, trace, direction)

Add the hours, thrust-hours [kN h] and rig work [GJ] of each edge of a routed `leg` and
its `trace` to `sums`, keyed by `direction` and true-wind-angle band.
"""
function add_leg!(sums, leg, trace, direction)
    for i in eachindex(trace.time)
        hours = leg.path[i + 1][3] - leg.path[i][3]
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
               WindShipOpt.cycle_cost(rig, case_assumptions) * leg.launches +
               WindShipOpt.forced_landing_cost(rig, case_assumptions) * leg.forced_landings
               for pair in legs for leg in pair)
    return (fixed / (8760case_assumptions[:availability]) * hours + wear) / sea_hours
end

"""
    angle_sums(name, rig, area)

Routed round trips over the sampled departures of a 140 m e-methanol ship with `area`
[m^2] of `rig` on route `name`, as hours, thrust-hours [kN h] and rig work [GJ] per
direction and true-wind-angle band, and the rig cost per hour at sea [USD/h].
"""
function angle_sums(name, rig, area)
    ship = Ship(ShipDesign(:methanol, 140.0; rig_size(rig, area)...), assumptions)
    bare = Ship(ShipDesign(:methanol, 140.0), assumptions)
    table = PerformanceTable(ship, assumptions)
    out_hourly, back_hourly = WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions),
        assumptions)
    route_table = RouteTable(table)
    out_corridor, back_corridor = run_corridors(name)
    port_hours = 24assumptions[:port_time_per_call]
    sums, legs = Dict{Tuple{String, String}, NTuple{3, Float64}}(), []
    for departure in sampled_departures()
        out = route(out_corridor, route_table, weather, departure; time_cost=out_hourly)
        back_departure = departure + out.duration + port_hours
        back = route(back_corridor, route_table, weather, back_departure;
            time_cost=back_hourly)
        add_leg!(sums, out, LegTrace(table, out, weather, departure), "out")
        add_leg!(sums, back, LegTrace(table, back, weather, back_departure), "home")
        push!(legs, (out, back))
    end
    return sums, rig_cost_per_hour(ship, bare, legs, assumptions)
end

"""
    wind_angle_data()

The 140 m e-methanol ship without a rig and with the reference size of each rig, routed
out and home on every route: hours at sea, thrust-hours [kN h] and rig work [GJ] per
true-wind-angle band summed over the sampled departures, and the rig cost per hour at
sea [USD/h]: wind_angle.csv.
"""
function wind_angle_data()
    cases = vec([(name, rig, area) for name in route_names,
                 (rig, area) in [("none", 0.0); reference_rigs]])
    Ship(ShipDesign(:methanol, 140.0; kite_area=Dict(reference_rigs)["kite"]), assumptions)
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
    cost_parts(ship, trip, case_assumptions)

Fuel, kite wear, port, crew, capital and maintenance with the fuel store, and cargo
interest per round trip [USD] of `trip`.
"""
function cost_parts(ship, trip, case_assumptions)
    costs = WindShipOpt.ShipCosts(ship, case_assumptions; trip.retractable)
    port_hours = 24case_assumptions[:port_time_per_call]
    if !trip.retractable
        port_hours += WindShipOpt.fixed_rig_port_hours(ship.rig, ship.design.class,
            case_assumptions)
    end
    sea_hours = 24(trip.outbound_days + trip.return_days)
    hours = sea_hours + 2port_hours
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
             WindShipOpt.cycle_cost(ship.rig, case_assumptions) * trip.launches +
             WindShipOpt.forced_landing_cost(ship.rig, case_assumptions) *
             trip.forced_landings,
        port=WindShipOpt.port_costs(ship.hull, case_assumptions),
        crew=crew / trading_hours * hours,
        capital=(costs.fixed_annual - crew) / trading_hours * hours + store,
        interest)
end

"""
    tonne_km_per_tonne(name)

Tonne-km per tonne of outbound cargo of a round trip on route `name`, with the backhaul
share of the return leg.
"""
function tonne_km_per_tonne(name)
    outbound, inbound = run_corridors(name)
    return (outbound.track_length +
            assumptions[:backhaul_fraction] * inbound.track_length) / 1e3
end

"""
    designs_data()

The design grid on the route to Guadeloupe: length, the [`study_drives`](@ref) and size of
each rig, a carbon price on VLSFO, and kites without flight drag and at market prices, with
the cost per tonne-km split into its parts: designs.csv.
"""
function designs_data()
    taxed = with_value(assumptions, :carbon_coverage, 1.0)
    rigid = with_value(assumptions, :kite_flight_drag, 0.0)
    market = kite_market_prices()
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
    for length in (85.0, 140.0, 170.0, 200.0), area in (0.0, 1600.0, 3200.0)
        push!(cases, trip_case(ShipDesign(:vlsfo, length; kite_area=area);
            assumptions=taxed, scenario="carbon"))
    end
    for length in (140.0, 200.0), drive in (:vlsfo, :methanol), area in (800.0, 3200.0)
        push!(cases, trip_case(ShipDesign(drive, length; kite_area=area);
            assumptions=rigid, scenario="rigid"))
        push!(cases, trip_case(ShipDesign(drive, length; kite_area=area);
            assumptions=market, scenario="kite_market"))
    end
    trips = round_trips(cases, sampled_departures())
    work_per_tonne = tonne_km_per_tonne(:caribbean)
    open(run_file("designs.csv"), "w") do io
        println(io, "scenario,drive,length,kite_area,kite_aspect_ratio,wing_area,",
            "rotor_area,cost,fuel,carbon,outbound_days,return_days,cargo,capital,",
            "flight_share,launches,fuel_cost,wear_cost,port_cost,crew_cost,",
            "capital_cost,interest_cost")
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
    parts = cost_parts(Ship(design, case.assumptions), trip, case.assumptions)
    tonne_km = trip.cargo * work_per_tonne
    @printf(io, "%s,%s,%.0f,%.0f,%.0f,%.0f,%.0f,%.6f,%.5f,%.3f,%.2f,%.2f,%.0f,%.0f,",
        case.scenario, design.drive, design.length, design.kite_area,
        design.kite_aspect_ratio, design.wing_area, design.rotor_area,
        trip.cost_per_tonne_km, trip.fuel_per_tonne_km, trip.carbon_per_tonne_km,
        trip.outbound_days, trip.return_days, trip.cargo, trip.capital)
    @printf(io, "%.3f,%.2f", trip.flight_share, trip.launches)
    for part in parts
        @printf(io, ",%.6f", part / tonne_km)
    end
    println(io)
end

"""
    routes_data()

Ships of three lengths and the [`study_drives`](@ref) without a rig and with two sizes of
each rig on every route: routes.csv.
"""
function routes_data()
    rigs = [("none", 0.0), ("kite", 800.0), ("kite", 3200.0), ("wings", 800.0),
        ("wings", 1500.0), ("rotors", 400.0), ("rotors", 800.0)]
    cases = vec([trip_case(ShipDesign(drive, length; rig_size(rig, area)...); route=name,
                     drive, length, rig, area)
                 for length in (85.0, 140.0, 200.0), drive in study_drives,
                     (rig, area) in rigs, name in route_names])
    write_trips("routes.csv", cases, round_trips(cases, sampled_departures()), :route,
        :drive, :length, :rig, :area)
end

"""
    largest_area(rig_type, hull; forward_reserve=0)

Largest total area [m^2] of `rig_type` (WingRig or RotorRig) that fits on `hull` behind
`forward_reserve` [m] of deck, to the nearest 10 m^2.
"""
function largest_area(rig_type, hull; forward_reserve=0.0)
    low, high = 0.0, 20000.0
    while high - low > 10
        middle = (low + high) / 2
        rig = rig_type(middle, hull, assumptions; forward_reserve)
        isnothing(rig) ? (high = middle) : (low = middle)
    end
    return low
end

"""
    size_bounds(class)

Smallest and largest area [m^2] searched for each rig on `class`: kites of 500 to
16,000 m^2, wings and rotors of a fifth to all of what fits on deck.
"""
function size_bounds(class)
    hull = Hull(class, assumptions)
    wings = largest_area(WingRig, hull)
    rotors = largest_area(WindShipOpt.RotorRig, hull)
    return Dict("kite" => (500.0, 16000.0), "wings" => (0.2wings, wings),
        "rotors" => (0.2rotors, rotors))
end

"""
    class_case(class, drive, rig, area, route)

Round-trip case of `class` with `drive` and `area` [m^2] of `rig` ("none" for no rig)
on `route`.
"""
function class_case(class::ShipClass, drive, rig, area, route)
    design = ShipDesign(drive, class; rig_size(rig, area)...)
    return trip_case(design; class=class.name, route, drive, rig, area,
        units=WindShipOpt.deck_units(Ship(design, assumptions).rig))
end

"""
    next_size(points, lower, upper)

Next area [m^2] to try in the search for the cheapest rig size, from the (area, cost)
`points` tried so far within `lower` and `upper`: the vertex of the parabola in log area
through the best point and its neighbours, or a golden-section step into the wider side
where that vertex is no new point; halfway towards the neighbour when the best is a
bound; rounded by [`snap_area`](@ref).
"""
function next_size(points, lower, upper)
    sorted = sort(filter(point -> isfinite(last(point)), points); by=first)
    x = [log(first(point)) for point in sorted]
    cost = [last(point) for point in sorted]
    k = argmin(cost)
    k == 1 && return clamp(snap_area(exp((x[1] + x[2]) / 2)), lower, upper)
    k == length(x) && return clamp(snap_area(exp((x[k - 1] + x[k]) / 2)), lower, upper)
    left, right = x[k] - x[k - 1], x[k + 1] - x[k]
    rise_left, rise_right = cost[k - 1] - cost[k], cost[k + 1] - cost[k]
    vertex = x[k] + (right^2 * rise_left - left^2 * rise_right) /
                    (2(left * rise_right + right * rise_left))
    close = minimum(abs.(x .- vertex)) < 0.05(left + right)
    if close || !(x[k - 1] < vertex < x[k + 1])
        vertex = right > left ? x[k] + 0.382right : x[k] - 0.382left
    end
    return clamp(snap_area(exp(vertex)), lower, upper)
end

"""
    snap_area(area)

`area` [m^2] rounded to the nearest step of a fourth power of two.
"""
snap_area(area) = 2.0^(round(4log2(area)) / 4)

"""
    classes_data()

The standard ship classes on every route with the [`study_drives`](@ref) without a rig,
and with the cheapest size of each rig found by a search over three starting sizes and
`size_rounds` more sizes from [`next_size`](@ref): classes.csv.
"""
function classes_data()
    sampled = sampled_departures()
    cases, searches = [], Dict{Tuple, Vector{Tuple{Float64, Float64}}}()
    for class in values(ship_classes()), drive in study_drives, route in route_names
        push!(cases, class_case(class, drive, "none", 0.0, route))
        for (rig, (lower, upper)) in size_bounds(class)
            searches[(class.name, drive, rig, route)] = Tuple{Float64, Float64}[]
            for area in (lower, sqrt(lower * upper), upper)
                push!(cases, class_case(class, drive, rig, area, route))
            end
        end
    end
    trips = round_trips(cases, sampled)
    for _ in 1:run_settings().size_rounds
        record_sizes!(searches, cases, trips)
        classes = ship_classes()
        batch = []
        for ((name, drive, rig, route), points) in searches
            count(point -> isfinite(last(point)), points) >= 2 || continue
            area = next_size(points, size_bounds(classes[name])[rig]...)
            any(point -> first(point) ≈ area, points) && continue
            push!(batch, class_case(classes[name], drive, rig, area, route))
        end
        append!(trips, round_trips(batch, sampled))
        append!(cases, batch)
    end
    write_trips("classes.csv", cases, trips, :class, :route, :drive, :rig, :area, :units)
end

"""
    record_sizes!(searches, cases, trips)

Fill each size search, keyed by class, drive, rig and route, with the (area, cost) of
every case run for it; infeasible trips cost `Inf`.
"""
function record_sizes!(searches, cases, trips)
    foreach(empty!, values(searches))
    for (case, trip) in zip(cases, trips)
        key = (case.class, case.drive, case.rig, case.route)
        haskey(searches, key) || continue
        push!(searches[key], (case.area, isnothing(trip) ? Inf : trip.cost_per_tonne_km))
    end
end

"""
    forecast_data()

A 140 m e-methanol ship to Guadeloupe without a rig and with each rig, routed with
perfect foresight and with daily re-planning on forecasts of 7 and 3 days: forecast.csv.
"""
function forecast_data()
    cases = vec([trip_case(ShipDesign(:methanol, 140.0; rig_size(rig, area)...); horizon,
                     rig, horizon_days=isfinite(horizon) ? horizon / 24 : 0.0)
                 for (rig, area) in [("none", 0.0); reference_rigs],
                     horizon in (Inf, 24.0 * 7, 24.0 * 3)])
    write_trips("forecast.csv", cases, round_trips(cases, sampled_departures()), :rig,
        :horizon_days)
end

"""
    bound_assumptions(name, bound)

The assumptions with input `name` at its `bound` (:low or :high), or unchanged for
`:none`.
"""
function bound_assumptions(name, bound)
    name == :none && return assumptions
    entry = assumptions.entries[name]
    return with_value(assumptions, name, bound == :low ? entry.low : entry.high)
end

"""
    sensitivity_ships()

Ships of the input screening as (name, design without a rig, route, rig areas): the
140 m e-methanol reference ship to Guadeloupe, a Kamsarmax on VLSFO to Tubarão and a
Neo-Panamax container ship on e-methanol to New York, the classes with the best rig sizes
of the class study.
"""
function sensitivity_ships()
    classes_table = read_table(data_file("classes.csv"))
    classes = ship_classes()
    reference = NamedTuple(Symbol(rig) => rig_size(rig, area)
                           for (rig, area) in reference_rigs)
    ships = [("140 m", ShipDesign(:methanol, 140.0), :caribbean, reference)]
    for (name, drive, route) in (("Kamsarmax bulk carrier", :vlsfo, :tubarao),
        ("Neo-Panamax container ship", :methanol, :new_york))
        areas = NamedTuple(Symbol(rig) => rig_size(rig,
                best_area(classes_table, name, string(route), string(drive), rig))
                           for rig in rig_names)
        push!(ships, (name, ShipDesign(drive, classes[name]), route, areas))
    end
    return ships
end

"""
    screened_inputs()

Every input with a range, except those of studies outside the paper.
"""
screened_inputs() = sort([name for (name, entry) in assumptions.entries
                          if entry.low != entry.high])

"""
    sensitivity_data()

Each ship of [`sensitivity_ships`](@ref) without a rig and with each rig, at the base
inputs and at the low and high bound of every input with a range: sensitivity.csv.
"""
function sensitivity_data()
    cases = []
    for (ship, bare, route, areas) in sensitivity_ships()
        for name in [screened_inputs(); :none]
            for bound in (name == :none ? (:value,) : (:low, :high))
                case_assumptions = bound_assumptions(name, bound)
                push!(cases, trip_case(bare; assumptions=case_assumptions, route, ship,
                    rig="none", input=name, bound))
                for rig in rig_names
                    design = ShipDesign(; bare.drive, bare.length, bare.class,
                        getproperty(areas, Symbol(rig))...)
                    push!(cases, trip_case(design; assumptions=case_assumptions, route,
                        ship, rig, input=name, bound))
                end
            end
        end
    end
    write_trips("sensitivity.csv", cases,
        round_trips(cases, sampled_departures(; screening=true)), :ship,
        :rig, :input, :bound)
end

"projected aspect ratios of the kite in the aspect ratio study, those with a polar"
study_aspect_ratios = (3.0, 4.0, 5.0, 6.0, 8.0)

"""
    aspect_data()

Each ship of [`sensitivity_ships`](@ref) without a rig and with its kite at each of
[`study_aspect_ratios`](@ref), at the same area and the same price: aspect.csv.
"""
function aspect_data()
    cases = []
    for (ship, bare, route, areas) in sensitivity_ships()
        push!(cases, trip_case(bare; route, ship, aspect_ratio=0.0))
        for aspect_ratio in study_aspect_ratios
            design = ShipDesign(; bare.drive, bare.length, bare.class, areas.kite...,
                kite_aspect_ratio=aspect_ratio)
            push!(cases, trip_case(design; route, ship, aspect_ratio,
                assumptions=WindShipOpt.base_aspect_ratio_prices(assumptions,
                    aspect_ratio / design_aspect_ratio)))
        end
    end
    trips = round_trips(cases, sampled_departures())
    open(run_file("aspect.csv"), "w") do io
        println(io, "ship,aspect_ratio,area,cost,flight_share,launches,cargo")
        for (case, trip) in zip(cases, trips)
            isnothing(trip) && continue
            @printf(io, "%s,%.0f,%.0f,%.6f,%.3f,%.2f,%.0f\n", csv_value(case.ship),
                case.aspect_ratio, case.design.kite_area, trip.cost_per_tonne_km,
                trip.flight_share, trip.launches, trip.cargo)
        end
    end
end

"input of each rig holding the share of its units' round trips out of service"
out_of_service_inputs = Dict("kite" => "kite_out_of_service",
    "wings" => "wing_out_of_service", "rotors" => "rotor_out_of_service")

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

Each ship of [`sensitivity_ships`](@ref) without a rig, and with each rig at its
[`service_shares`](@ref): availability.csv.
"""
function availability_data()
    cases = []
    for (ship, bare, route, areas) in sensitivity_ships()
        push!(cases, trip_case(bare; route, ship, rig="none", share=0.0))
        for rig in rig_names, share in service_shares(rig)
            input = Symbol(out_of_service_inputs[rig])
            design = ShipDesign(; bare.drive, bare.length, bare.class,
                getproperty(areas, Symbol(rig))...)
            push!(cases, trip_case(design;
                assumptions=with_value(assumptions, input, share), route, ship, rig, share))
        end
    end
    write_trips("availability.csv", cases,
        round_trips(cases, sampled_departures(; screening=true)), :ship, :rig, :share)
end

"""
    crash_sizes(rig, area, hull)

Sizes [m^2] of `rig` in the crash study: half of `area`, `area` and twice it, wings and
rotors only as far as they fit on `hull`.
"""
function crash_sizes(rig, area, hull)
    rig == "kite" && return [area / 2, area, 2area]
    rig_type = rig == "wings" ? WingRig : WindShipOpt.RotorRig
    return unique([area / 2, area, min(2area, largest_area(rig_type, hull))])
end

"""
    crash_data()

Each ship of [`sensitivity_ships`](@ref) without a rig and with each rig at its
[`crash_sizes`](@ref), at the base inputs: crashes.csv.
"""
function crash_data()
    cases = []
    for (ship, bare, route, areas) in sensitivity_ships()
        push!(cases, trip_case(bare; route, ship, bare.drive, rig="none", area=0.0))
        hull = Ship(bare, assumptions).hull
        for rig in rig_names
            best = only(values(getproperty(areas, Symbol(rig))))
            for area in crash_sizes(rig, best, hull)
                design = ShipDesign(; bare.drive, bare.length, bare.class,
                    rig_size(rig, area)...)
                push!(cases, trip_case(design; route, ship, bare.drive, rig, area))
            end
        end
    end
    write_trips("crashes.csv", cases,
        round_trips(cases, sampled_departures(; screening=true)), :ship, :route, :drive,
        :rig, :area)
end

"canopy lives [flight hours] the kite is routed at for the missed-goal table"
canopy_lives = (500.0, 750.0, 1000.0, 1500.0, 2000.0, 3000.0, 4000.0, 6000.0, 8000.0,
    16000.0)

"""
    canopy_life_data()

The kite of each ship of [`sensitivity_ships`](@ref) at each of `canopy_lives`, its size
and every other input held: canopy_life.csv.
"""
function canopy_life_data()
    cases = [trip_case(ShipDesign(; bare.drive, bare.length, bare.class, areas.kite...);
                 assumptions=with_value(assumptions, :canopy_life, life), route, ship, life)
             for (ship, bare, route, areas) in sensitivity_ships(), life in canopy_lives]
    write_trips("canopy_life.csv", vec(cases),
        round_trips(vec(cases), sampled_departures(; screening=true)), :ship, :life)
end

"""
    canopy_prices()

Canopy prices [USD/m^2] the kite is routed at for the missed-goal table: the goal, today's
and either side of them, up to where the kite stops paying on every ship.
"""
function canopy_prices()
    goal = WindShipOpt.canopy_price(assumptions)
    return sort([goal .* [0.5, 0.75, 1.0, 1.25, 2.5, 3.5, 5.0, 7.0];
                  WindShipOpt.canopy_price_today(assumptions)])
end

"""
    canopy_price_data()

The kite of each ship of [`sensitivity_ships`](@ref) at each of [`canopy_prices`](@ref), its
size and every other input held: canopy_price.csv.
"""
function canopy_price_data()
    goal = WindShipOpt.canopy_price(assumptions)
    inputs = WindShipOpt.canopy_price_inputs
    cases = [trip_case(ShipDesign(; bare.drive, bare.length, bare.class, areas.kite...);
                 assumptions=scaled(inputs, price / goal), route, ship, price)
             for (ship, bare, route, areas) in sensitivity_ships(),
    price in canopy_prices()]
    write_trips("canopy_price.csv", vec(cases),
        round_trips(vec(cases), sampled_departures(; screening=true)), :ship, :price)
end

"ships of the abatement study as (name, route)"
abatement_ships = (("140 m", :caribbean), ("Kamsarmax bulk carrier", :tubarao))

"""
    abatement_data()

Each ship of `abatement_ships` on each drive without a rig and with every rig over its
range of sizes, kites from 400 to 12,800 m^2 and wings and rotors from a tenth to all of
the deck capacity: abatement.csv.
"""
function abatement_data()
    cases = []
    for (ship, route) in abatement_ships, drive in study_drives
        hull = Ship(ShipDesign(drive, study_hull(ship)), assumptions).hull
        fractions = [0.1, 0.2, 0.35, 0.5, 0.7, 1.0]
        sizes = Dict("none" => [0.0], "kite" => [400.0 * 2^(k / 2) for k in 0:10],
            "wings" => fractions .* largest_area(WingRig, hull),
            "rotors" => fractions .* largest_area(WindShipOpt.RotorRig, hull))
        for rig in all_rigs, area in sizes[rig]
            design = ShipDesign(drive, study_hull(ship); rig_size(rig, area)...)
            push!(cases, trip_case(design; route, ship, drive, rig, area))
        end
    end
    write_trips("abatement.csv", cases, round_trips(cases, sampled_departures()), :ship,
        :drive, :rig, :area)
end

"""
    components_data()

Each rig on a 140 m e-methanol ship to Guadeloupe with the price of one of its components
50 % lower and higher, or one of its lifetimes halved and doubled: components.csv.
"""
function components_data()
    components = Dict("kite" => [:winch_fixed_cost, :winch_cost_per_force,
            :launch_mast_mass_coefficient, :launch_mast_telescope_factor,
            :docking_head_cost, :control_unit_cost,
            :control_unit_cost_per_area, :kite_integration_fraction,
            :canopy_making_cost_per_area, :tether_price, :canopy_life, :tether_lifetime],
        "wings" => [:wing_unit_cost, :wing_cost_per_area, :wing_installation_fraction,
            :retractable_rig_premium, :wing_lifetime],
        "rotors" => [:rotor_unit_cost, :rotor_cost_per_area, :rotor_installation_fraction,
            :retractable_rig_premium, :rotor_lifetime])
    cases = [trip_case(ShipDesign(:methanol, 140.0); rig="none", input=:none, factor=1.0)]
    for (rig, area) in reference_rigs
        design = ShipDesign(:methanol, 140.0; rig_size(rig, area)...)
        push!(cases, trip_case(design; rig, input=:none, factor=1.0))
        for name in components[rig], factor in component_factors(name)
            push!(cases, trip_case(design; assumptions=scaled((name,), factor), rig,
                input=name, factor))
        end
    end
    write_trips("components.csv", cases, round_trips(cases, sampled_departures()), :rig,
        :input, :factor)
end

"""
    component_factors(name)

Factors on input `name` of the component study: half and twice a lifetime, half and
1.5 times a price.
"""
component_factors(name) = endswith(string(name), "lifetime") ? (0.5, 2.0) : (0.5, 1.5)

"""
    convergence_data()

A 140 m e-methanol ship to Guadeloupe without a rig and with each rig, routed at corridor
resolutions of 8, 4 and 2 times the base spacing: convergence.csv.
"""
function convergence_data()
    rigs = [("none", 0.0), ("kite", 1600.0), ("wings", 1500.0), ("rotors", 800.0)]
    cases = vec([trip_case(ShipDesign(:methanol, 140.0; rig_size(rig, area)...); rig, scale)
                 for (rig, area) in rigs, scale in (8.0, 4.0, 2.0)])
    write_trips("convergence.csv", cases, round_trips(cases, sampled_departures()), :rig,
        :scale)
end

"ships of the combination study"
combination_ships = ("140 m", "Kamsarmax bulk carrier")

"kite areas [m^2] flown alone in the combination study"
combination_kites = (400.0, 800.0, 1600.0, 3200.0)

"kite areas [m^2] flown with rotors in the combination study"
combination_paired_kites = (400.0, 800.0, 1600.0)

"""
    combination_rotors(ship)

Rotor areas [m^2] of the combination study on `ship`: a fifth, half and all of the deck
capacity left behind the kite's launch mast, to the nearest 10 m^2.
"""
function combination_rotors(ship)
    capacity = largest_area(WindShipOpt.RotorRig, Hull(study_hull(ship), assumptions);
        forward_reserve=WindShipOpt.launch_mast_reserve(assumptions))
    return [round(fraction * capacity; digits=-1) for fraction in (0.2, 0.5, 1.0)]
end

"""
    combination_data()

Each ship of `combination_ships` on every route on VLSFO and e-methanol without a rig,
with each kite of `combination_kites`, with each rotor area of
[`combination_rotors`](@ref), and with each kite of `combination_paired_kites` flown
together with each rotor area: combination.csv.
"""
function combination_data()
    cases = []
    for ship in combination_ships, drive in (:vlsfo, :methanol), route in route_names
        rotor_areas = combination_rotors(ship)
        sizes = [("none", 0.0, 0.0); [("kite", kite, 0.0) for kite in combination_kites];
            [("rotors", 0.0, rotor) for rotor in rotor_areas];
            vec([("kite+rotors", kite, rotor)
                 for kite in combination_paired_kites, rotor in rotor_areas])]
        for (rig, kite_area, rotor_area) in sizes
            design = ShipDesign(drive, study_hull(ship); kite_area, rotor_area)
            push!(cases, trip_case(design; route, ship, drive, rig, kite_area, rotor_area))
        end
    end
    write_trips("combination.csv", cases, round_trips(cases, sampled_departures()), :ship,
        :route, :drive, :rig, :kite_area, :rotor_area)
end

"""
    traced_legs(ship, name)

Routed round trips of `ship` on route `name` over the sampled departures, as a list of
each leg and its [`LegTrace`](@ref) every 3 h, with hours priced at the ship's time cost.
"""
function traced_legs(ship, name)
    table = PerformanceTable(ship, assumptions)
    route_table = RouteTable(table)
    hourly = WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions), assumptions)
    port_hours = 24assumptions[:port_time_per_call]
    legs = []
    for departure in sampled_departures()
        trip = WindShipOpt.route_round_trip(route_table, run_corridors(name)..., weather,
            departure, port_hours, hourly, Inf)
        isnothing(trip) && continue
        out, back = trip
        back_departure = departure + out.duration + port_hours
        push!(legs, (out, LegTrace(table, out, weather, departure; interval=3.0)))
        push!(legs, (back, LegTrace(table, back, weather, back_departure; interval=3.0)))
    end
    return legs
end

"""
    add_flight_hours!(bins, leg, trace)

Add every 3 h of a routed `leg` and its `trace` to `bins`, keyed by true wind angle band and
ship speed band: hours, flying hours, hours in which the rig could pull, hours in which it
pulled, net thrust-hours worked [kN h], distance [nmi] and the lowest apparent angle at
which it pulled [deg].
"""
function add_flight_hours!(bins, leg, trace)
    ends = [trace.time[2:end]; leg.duration]
    for (i, finish) in enumerate(ends)
        hours = finish - trace.time[i]
        knots = trace.speed[i] / KNOT
        band = (min(floor(Int, rad2deg(trace.true_wind_angle[i]) / 30), 5) * 30,
            knots < 10 ? 8 : knots < 12 ? 10 : knots < 14 ? 12 : 14)
        pulling = trace.rig_thrust[i] > 0
        working = trace.flying[i] || pulling
        angle = pulling ? rad2deg(trace.apparent_angle[i]) : Inf
        old = get(bins, band, (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, Inf))
        sums = old[1:6] .+ (hours, trace.flying[i] * hours,
            (trace.available_thrust[i] > 0) * hours, pulling * hours,
            working * trace.rig_thrust[i] * hours / 1e3, knots * hours)
        bins[band] = (sums..., min(old[7], angle))
    end
end

"""
    flight_bins(case)

Hours of a case of [`flight_data`](@ref) by band of true wind angle and ship speed (see
[`add_flight_hours!`](@ref)).
"""
function flight_bins(case)
    ship = Ship(ShipDesign(case.drive, case.length; rig_size(case.rig, case.area)...),
        assumptions)
    bins = Dict{Tuple{Int, Int}, NTuple{7, Float64}}()
    for (leg, trace) in traced_legs(ship, case.route)
        add_flight_hours!(bins, leg, trace)
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
    for route in route_names, drive in study_drives, length in (85.0, 140.0, 200.0),
        rig in ("none", "kite", "wings", "rotors")

        best = cheapest_row(table, "route" => string(route), "drive" => string(drive),
            "length" => length, "rig" => rig)
        isnothing(best) || push!(cases, (; route, drive, length, rig,
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
    economic_speed(ship, hourly, wind_10m, angle; force=nothing,
                   wear=wear_cost(ship.rig, assumptions))

Speed [kn] on a grid of 0.1 kn with the least [`mile_cost`](@ref).
"""
function economic_speed(ship, hourly, wind_10m, angle; force=nothing,
        wear=WindShipOpt.wear_cost(ship.rig, assumptions))
    return argmin(knots -> mile_cost(ship, knots, hourly, wind_10m, angle, force, wear),
        4.0:0.1:(ship.max_speed / KNOT))
end

"""
    sailing_speed(ship, force, wind_10m, angle)

Highest speed [kn] on a grid of 0.1 kn at which `ship` needs no propeller thrust with the
rig force held at `force`, in a steady wind of `wind_10m` [m/s] from `angle` [rad]; zero if
none.
"""
function sailing_speed(ship, force, wind_10m, angle)
    speeds = 4.0:0.1:(ship.max_speed / KNOT)
    last_sailing = findlast(speeds) do knots
        return WindShipOpt.required_thrust(ship, knots * KNOT, wind_10m, angle, force) <= 0
    end
    return isnothing(last_sailing) ? 0.0 : speeds[last_sailing]
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
        for drive in (:methanol, :vlsfo)
            bare = Ship(ShipDesign(drive, 140.0), assumptions)
            hourly = first(WindShipOpt.leg_time_costs(ShipCosts(bare, assumptions),
                assumptions))
            for (rig, area) in reference_rigs, wind in (6.0, 10.0, 14.0),
                angle in (60, 90, 120, 150)

                ship = Ship(ShipDesign(drive, 140.0; rig_size(rig, area)...), assumptions)
                ship_hourly = first(WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions),
                    assumptions))
                base = economic_speed(bare, hourly, wind, deg2rad(angle))
                force = last(WindShipOpt.best_trim(ship, ship.rig, base * KNOT, wind,
                    deg2rad(angle)))
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
    same_time_leg(corridor, table, weather, departure, hourly, duration)

Routed leg whose time cost is scaled down from `hourly` [USD/h] by bisection until it takes
about `duration` [h], or the fuel-only limit; the leg closest to it.
"""
function same_time_leg(corridor, table, weather, departure, hourly, duration)
    low, high = 0.02, 1.0
    best = route(corridor, table, weather, departure; time_cost=hourly)
    (isnothing(best) || best.duration >= duration) && return best
    for _ in 1:6
        factor = sqrt(low * high)
        leg = route(corridor, table, weather, departure; time_cost=factor * hourly)
        isnothing(leg) && break
        abs(leg.duration - duration) < abs(best.duration - duration) && (best = leg)
        leg.duration < duration ? (high = factor) : (low = factor)
    end
    return best
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
`name` over the sampled departures on the [`RouteTable`](@ref) `table`, each leg taking
about the time in `durations` where given; `nothing` if a passage fails.
"""
function speed_term_sums(table, name, hourly, durations)
    corridors_of_route = run_corridors(name)
    port_hours = 24assumptions[:port_time_per_call]
    legs = []
    for (k, departure) in enumerate(sampled_departures())
        pair = isnothing(durations) ?
               WindShipOpt.route_round_trip(table, corridors_of_route..., weather,
            departure, port_hours, hourly, Inf) :
               same_time_round_trip(table, corridors_of_route, departure, port_hours,
            hourly, durations[(2k - 1):2k])
        isnothing(pair) && return nothing
        append!(legs, pair)
    end
    return sum(leg.fuel_energy for leg in legs) / 1e9, sum(leg.duration for leg in legs),
    sum(leg.flight_hours for leg in legs), [leg.duration for leg in legs]
end

"""
    same_time_round_trip(table, corridors, departure, port_hours, hourly, durations)

Outbound and return [`same_time_leg`](@ref) along the pair of `corridors` from
`departure` [h], each taking about its time in `durations` [h]; `nothing` if either fails.
"""
function same_time_round_trip(table, corridors, departure, port_hours, hourly, durations)
    out = same_time_leg(first(corridors), table, weather, departure, first(hourly),
        first(durations))
    isnothing(out) && return nothing
    back = same_time_leg(last(corridors), table, weather,
        departure + out.duration + port_hours, last(hourly), last(durations))
    isnothing(back) && return nothing
    return out, back
end

"""
    speed_terms_data()

Fuel energy and hours of a 140 m ship without and with the reference rigs on two routes on
the terms the literature uses and on ours: routed for cost, in the same time as the ship
without a rig, and at 8, 9 and 10 kn: speed_terms.csv.
"""
function speed_terms_data()
    cases = vec([(; route, drive, rig, area) for route in (:caribbean, :new_york),
                 drive in (:methanol, :vlsfo),
                 (rig, area) in [("none", 0.0); reference_rigs]])
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
        assumptions)
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
Published kite forces: the citation key, the kite area [m^2], the ship speed [kn], the true
wind angle [deg] and the wind at 10 m [m/s].
"""
published_forces = [("leloup2013", 320.0, 8.0, 180.0, 9.0),
    ("penloup2021", 320.0, 19.0, 60.0, 7.0), ("penloup2021", 320.0, 19.0, 120.0, 7.0),
    ("penloup2021", 320.0, 19.0, 180.0, 7.0), ("penloup2021", 320.0, 19.0, 60.0, 17.0),
    ("penloup2021", 320.0, 19.0, 120.0, 17.0), ("penloup2021", 320.0, 19.0, 180.0, 17.0)]

"""
Inputs with the kite flown free of canopy, tether and handling costs, which the published
fixed-speed studies leave out, so that it flies wherever that saves fuel.
"""
kite_without_running_cost = foldl((inputs, key) -> with_value(inputs, key, 0.0),
    (:market_price_factor, :tether_price, :kite_cycle_crew_cost, :kite_cycle_course_cost,
        :kite_cycle_loss_probability, :kite_forced_landing_loss_probability);
    init=assumptions)

"""
    fixed_speed_voyage(hull, kite_area, inputs, knots, name)

[`fixed_speed_sums`](@ref) of the VLSFO ship on `hull` with `kite_area` [m^2] of kite under
`inputs`, its time priced as in the rest of the paper.
"""
function fixed_speed_voyage(hull, kite_area, inputs, knots, name)
    ship = Ship(ShipDesign(:vlsfo, hull; kite_area), inputs)
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
of our ships, published_terms.csv, and our kite's thrust and side force at the published
conditions, published_forces.csv.
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
    open(run_file("published_forces.csv"), "w") do io
        println(io, "source,area,speed,angle,wind,thrust,side")
        for (source, area, knots, angle, wind) in published_forces
            ship = Ship(ShipDesign(:vlsfo, 140.0; kite_area=area), assumptions)
            force = rig_force(ship.rig, ship.env, wind, deg2rad(angle), knots * KNOT, 1)
            println(io, join((source, area, knots, angle, wind, force.thrust / 1e3,
                    force.side / 1e3), ","))
        end
    end
end

"""
Ships, speeds and sizes of [`speed_size_data`](@ref): the ship, its drives, the speeds [kn]
it holds, the kite areas [m^2], and the wing and rotor areas [m^2].
"""
speed_size_grid = [
    (ship="140 m", drives=(:vlsfo, :methanol), speeds=(8.0, 9.0, 10.0, 11.0),
        kites=(400.0, 800.0, 1600.0, 3200.0, 6400.0),
        wings=(750.0, 1500.0), rotors=(400.0, 800.0)),
    (ship="feeder container ship", drives=(:vlsfo,), speeds=(13.0, 16.0, 19.0),
        kites=(800.0, 1600.0, 3200.0, 6400.0, 12800.0),
        wings=(), rotors=())]

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
