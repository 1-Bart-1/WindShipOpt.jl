# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Data steps of the paper: each runs one study and writes its data files to the directory
# of the run in use. Included by paper.jl.

"drives compared where the drive is a dimension of the study"
study_drives = (:vlsfo, :ammonia)

"projected aspect ratio of the kite of every design that names none"
design_aspect_ratio = ShipDesign(:vlsfo, 100.0).kite_aspect_ratio

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
    ship = Ship(case.design, case.assumptions)
    isnothing(ship) && return nothing
    ship = simplified_ship(ship, case.part)
    return round_trip(ship, case.corridors..., weather, departures, case.assumptions;
        forecast=forecast_source(case.forecast), held_knots=case.held_knots)
end

"""
    forecast_source(plan)

What a case plans on: nothing where `plan` is false (perfect foresight), the control
forecast where it is true, the same with the kite held to the plan where `:held_kite` or
knowing the real weather ahead where `:foresight_kite`, the shortest lead of the control
forecast at every time where `:shortest_lead`, the real weather re-planned daily where
`:perfect_replan`, or the [`forecast_plans`](@ref) entry `plan`.
"""
forecast_source(plan) =
    plan === false ? nothing : plan === true ? forecast_archive :
    plan === :held_kite ? PlannedKite(forecast_archive) :
    plan === :foresight_kite ? ForesightKite(forecast_archive) :
    plan === :shortest_lead ? ShortestLead(forecast_archive) :
    plan === :perfect_replan ? PerfectForecast() : forecast_plans[plan]

"""
    round_trips(cases, departures)

Round trips of all `cases`, threaded, reusing those cached in the run in use under the same
value of every input they read; the kite pattern tables of the others are computed first,
one kite at a time.
"""
function round_trips(cases, departures)
    directories = [case_directory(case, departures) for case in cases]
    trips = Any[cached_trip(directory, case.assumptions)
                for (case, directory) in zip(cases, directories)]
    computed = findall(ismissing, trips)
    for case in cases[computed]
        max(case.design.kite_area, case.design.rigid_kite_area) > 0 &&
            Ship(case.design, case.assumptions)
    end
    Threads.@threads :greedy for k in computed
        trips[k] = stored_trip(() -> case_trip(cases[k], departures), directories[k],
            cases[k].assumptions)
    end
    feasible = count(!isnothing, trips)
    paper_run.cases += length(cases)
    paper_run.trips += feasible
    println("  ", feasible, " of ", length(cases), " round trips, ",
        length(cases) - length(computed), " cached")
    return trips
end

"""
    write_trips(name, cases, trips, columns...)

Write `name` to the directory of the run in use with the given label `columns` of each
case and the cost [USD/tkm], fuel [MJ/tkm], CO2 [kg/tkm], round-trip days, kite flight
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

The 140 m e-ammonia ship on every route without a rig, with the reference wings and
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
            design = ShipDesign(:ammonia, 140.0; rig_size(rig, area)...)
            push!(cases, trip_case(design; labels..., route, rig, area))
            rig == "none" && continue
            push!(cases, trip_case(design; labels..., assumptions=always_in_service, route,
                rig, area, service=false))
        end
        for area in (800.0, 1600.0, 3200.0)
            design = ShipDesign(:ammonia, 140.0; rig_size("kite", area)...)
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

Optimise one pattern and write its force and its path; nothing where no pattern flies.
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
rig_keywords = Dict("kite" => :kite_area, "wings" => :wing_area, "rotors" => :rotor_area,
    "rigid kite" => :rigid_kite_area)

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
        "wings" => (800.0, 1500.0, 2400.0), "rotors" => (400.0, 800.0, 1600.0)),
    "Kamsarmax bulk carrier" => Dict("kite" => (1600.0, 3200.0, 6400.0),
        "wings" => (1600.0, 2400.0, 3600.0), "rotors" => (850.0, 1200.0, 1890.0)))

"""
Ship, route, drive and inputs of each part of the situation study: every input on the
140 m reference ship to Guadeloupe and all but the cargo value on a Kamsarmax to Tubarão,
and on both the price of each fuel on its own drive, e-methanol included as the other
e-fuel.
"""
situation_studies = [("140 m", :caribbean, :vlsfo, [:vlsfo_price]),
    ("140 m", :caribbean, :ammonia, [:e_ammonia_price, :cargo_value, :discount_rate,
        :wing_lifetime, :wing_price, :rotor_max_surface_speed]),
    ("140 m", :caribbean, :methanol, [:e_methanol_price]),
    ("Kamsarmax bulk carrier", :tubarao, :vlsfo, [:vlsfo_price]),
    ("Kamsarmax bulk carrier", :tubarao, :methanol, [:e_methanol_price]),
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

Routed round trips over the sampled departures of a 140 m e-ammonia ship with `area`
[m^2] of `rig` on route `name`, as hours, thrust-hours [kN h] and rig work [GJ] per
direction and true-wind-angle band, and the rig cost per hour at sea [USD/h].
"""
function angle_sums(name, rig, area)
    ship = Ship(ShipDesign(:ammonia, 140.0; rig_size(rig, area)...), assumptions)
    bare = Ship(ShipDesign(:ammonia, 140.0), assumptions)
    table = PerformanceTable(ship, assumptions)
    out_hourly, back_hourly = WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions),
        assumptions)
    route_table = RouteTable(table)
    out_corridor, back_corridor = run_corridors(name)
    port_hours = 24assumptions[:port_time_per_call]
    sums, legs = Dict{Tuple{String, String}, NTuple{3, Float64}}(), []
    for departure in sampled_departures()
        out = route(out_corridor, route_table, weather, departure; time_cost=out_hourly)
        isnothing(out) && continue
        back_departure = departure + out.duration + port_hours
        back = route(back_corridor, route_table, weather, back_departure;
            time_cost=back_hourly)
        isnothing(back) && continue
        add_leg!(sums, out, LegTrace(table, out, weather, departure), "out")
        add_leg!(sums, back, LegTrace(table, back, weather, back_departure), "home")
        push!(legs, (out, back))
    end
    return sums, rig_cost_per_hour(ship, bare, legs, assumptions)
end

"""
    wind_angle_data()

The 140 m e-ammonia ship without a rig and with the reference size of each rig, routed
out and home on every route: hours at sea, thrust-hours [kN h] and rig work [GJ] per
true-wind-angle band summed over the sampled departures, and the rig cost per hour at
sea [USD/h]: wind_angle.csv.
"""
function wind_angle_data()
    cases = vec([(name, rig, area) for name in route_names,
                 (rig, area) in [("none", 0.0); reference_rigs]])
    Ship(ShipDesign(:ammonia, 140.0; kite_area=Dict(reference_rigs)["kite"]), assumptions)
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
             WindShipOpt.cycle_cost(ship.rig, case_assumptions) * trip.launches +
             WindShipOpt.forced_landing_cost(ship.rig, case_assumptions) *
             trip.forced_landings,
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
    ship = Ship(case.design, case.assumptions)
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
    for length in (140.0, 200.0), drive in (:vlsfo, :ammonia), area in (800.0, 3200.0)
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
        design.kite_aspect_ratio, design.wing_area, design.rotor_area,
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
    return Dict("kite" => (500.0, largest_rig_area("kite", hull)),
        (rig => (0.2largest_rig_area(rig, hull), largest_rig_area(rig, hull))
         for rig in ("wings", "rotors"))...)
end

"""
    largest_rig_area(rig, hull)

Largest area [m^2] of `rig` on `hull`: what fits on deck, for a kite the search bound.
"""
function largest_rig_area(rig, hull)
    rig == "kite" && return 16000.0
    return largest_area(rig == "wings" ? WingRig : WindShipOpt.RotorRig, hull)
end

"""
    class_case(class, drive, rig, area, route; labels...)

Round-trip case of `class` with `drive` and `area` [m^2] of `rig` ("none" for no rig)
on `route`, tagged with `labels`.
"""
function class_case(class::ShipClass, drive, rig, area, route; labels...)
    design = ShipDesign(drive, class; rig_size(rig, area)...)
    return trip_case(design; class=class.name, route, drive, rig, area,
        units=WindShipOpt.deck_units(Ship(design, assumptions).rig), labels...)
end

"""
    classes_data()

The standard ship classes on every route with the [`study_drives`](@ref) without a rig,
and with the cheapest size of each rig found by [`searched_sizes`](@ref) in `size_rounds`
rounds: classes.csv.
"""
function classes_data()
    ships = [(class, drive, route)
             for class in values(ship_classes()), drive in study_drives,
                 route in route_names]
    cases, trips = searched_sizes(vec(ships), run_settings().size_rounds)
    write_trips("classes.csv", cases, trips, :class, :route, :drive, :rig, :area, :units)
end

"""
    searched_sizes(ships, rounds)

Cases and round trips of each (class, drive, route) of `ships` without a rig and of the
search for the cheapest size of each rig: three starting sizes, then `rounds` more sizes
from [`next_size`](@ref). Each case is tagged with the `round` that added it, 0 for the
starting sizes.
"""
function searched_sizes(ships, rounds)
    sampled = sampled_departures()
    cases, searches = [], Dict{Tuple, Vector{Tuple{Float64, Float64}}}()
    for (class, drive, route) in ships
        push!(cases, class_case(class, drive, "none", 0.0, route; round=0))
        for (rig, (lower, upper)) in size_bounds(class)
            searches[(class.name, drive, rig, route)] = Tuple{Float64, Float64}[]
            for area in (lower, sqrt(lower * upper), upper)
                push!(cases, class_case(class, drive, rig, area, route; round=0))
            end
        end
    end
    trips = round_trips(cases, sampled)
    classes = ship_classes()
    for round in 1:rounds
        record_sizes!(searches, cases, trips)
        batch = []
        for ((name, drive, rig, route), points) in searches
            count(point -> isfinite(last(point)), points) >= 2 || continue
            area = next_size(points, size_bounds(classes[name])[rig]...)
            any(point -> first(point) ≈ area, points) && continue
            push!(batch, class_case(classes[name], drive, rig, area, route; round))
        end
        append!(trips, round_trips(batch, sampled))
        append!(cases, batch)
    end
    return cases, trips
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

A 140 m e-ammonia ship to Guadeloupe without a rig and with each rig, routed with
perfect foresight and re-planned daily on the archived forecasts: forecast.csv; and the
error of those forecasts along its route: forecast_error.csv.
"""
function forecast_data()
    cases = vec([trip_case(ShipDesign(:ammonia, 140.0; rig_size(rig, area)...); forecast,
                     rig, knowledge=forecast ? "forecast" : "perfect")
                 for (rig, area) in [("none", 0.0); reference_rigs],
                     forecast in (false, true)])
    write_trips("forecast.csv", cases, round_trips(cases, sampled_departures()), :rig,
        :knowledge)
    write_forecast_error("forecast_error.csv", run_corridors(:caribbean)...)
end

"plans of the forecast study, each as the `forecast` of its [`trip_case`](@ref)"
forecast_study_plans = (false, true, :mean, :margin, :members, :held_kite)

"""
    forecast_plans_data()

The 140 m e-ammonia ship to Guadeloupe without a rig and with each rig, per departure of
`ensemble_departures`, for each of the [`forecast_study_plans`](@ref): forecast_plans.csv;
the share of its perfect-foresight saving each rig keeps per plan with the jackknife
standard error over the departures: forecast_plans_kept.csv; and the launches and landings
of a kite that flies in the weather met and of one held to the plan on three passages,
forecast_rule.csv; and where those two kites differ on every passage of the kite ship:
forecast_rule_steps.csv.
"""
function forecast_plans_data()
    rigs = [("none", 0.0); reference_rigs]
    cases, trips = [], []
    for departure in ensemble_departures
        step_cases = vec([trip_case(ShipDesign(:ammonia, 140.0; rig_size(rig, area)...);
                              forecast=plan, rig, plan=string(plan), departure)
                          for (rig, area) in rigs, plan in forecast_study_plans
                              if plan !== :held_kite || rig == "kite"])
        append!(cases, step_cases)
        append!(trips, round_trips(step_cases, [departure]))
    end
    write_trips("forecast_plans.csv", cases, trips, :rig, :plan, :departure)
    write_kept_shares("forecast_plans_kept.csv", cases, trips)
    write_kite_rule_records("forecast_rule_steps.csv", "forecast_rule.csv",
        ensemble_departures, ensemble_departures[begin:4:end])
end

"""
    write_kept_shares(name, cases, trips)

Write `name`: per rig and plan, the share of the perfect-foresight saving kept, the ratio
of the mean savings over the departures, with its jackknife standard error and that of the
difference from the control plan.
"""
function write_kept_shares(name, cases, trips)
    n = length(ensemble_departures)
    open(run_file(name), "w") do io
        println(io, "rig,plan,kept,kept_error,difference_from_control,difference_error")
        for (rig, _) in reference_rigs, plan in forecast_study_plans[2:end]
            plan === :held_kite && rig != "kite" && continue
            saved, perfect = plan_savings(cases, trips, rig, plan),
            plan_savings(cases, trips, rig, false)
            control = plan_savings(cases, trips, rig, true)
            value = kept_share(saved, perfect, 1:n)
            spread = jackknife_error(index -> kept_share(saved, perfect, index), n)
            difference = value - kept_share(control, perfect, 1:n)
            difference_spread = jackknife_error(n) do index
                kept_share(saved, perfect, index) - kept_share(control, perfect, index)
            end
            @printf(io, "%s,%s,%.3f,%.3f,%.3f,%.3f\n", rig, plan, value, spread, difference,
                difference_spread)
        end
    end
end

"cost per tonne-kilometre of `rig` on `plan` from `departure` among `cases` and `trips`"
function plan_cost(cases, trips, rig, plan, departure)
    index = findfirst(i -> cases[i].rig == rig && cases[i].forecast === plan &&
                               cases[i].departure == departure, eachindex(cases))
    return trips[index].cost_per_tonne_km
end

"cost saving of `rig` on `plan` per departure, against no rig on the same forecast"
plan_savings(cases, trips, rig, plan) =
    [1 - plan_cost(cases, trips, rig, plan, departure) /
         plan_cost(cases, trips, "none", plan === :held_kite ? true : plan, departure)
     for departure in ensemble_departures]

"share of the mean saving of `perfect` that `saved` keeps over the departures `indices`"
kept_share(saved, perfect, indices) = mean(saved[indices]) / mean(perfect[indices])

"jackknife standard error over `n` departures of `statistic` of the departures kept"
function jackknife_error(statistic, n)
    leave_out = [statistic(setdiff(1:n, i)) for i in 1:n]
    return sqrt((n - 1) / n * sum(abs2, leave_out .- mean(leave_out)))
end

"""
    write_kite_rule_records(steps_name, trace_name, departures, example_departures)

Write `steps_name`: per outbound and return passage of the 140 m e-ammonia kite ship from
each of `departures` on the control forecast, the steps and samples sailed, those whose
kite state differs from a kite held to the plan, and the cost of those two kites on the
same steps; and `trace_name`: per sample of the outbound passages from
`example_departures`, under each rule, the kite state and the state the plan wants.
"""
function write_kite_rule_records(steps_name, trace_name, departures, example_departures)
    table, hourly = routing_inputs("kite")
    legs = zip(("out", "back"), run_corridors(:caribbean), hourly)
    open(run_file(steps_name), "w") do steps
        println(steps, "departure,leg,edges,different_ends,different_edge_cost,samples,",
            "different_samples,cost,held_cost")
        for departure in departures, (leg, corridor, time_cost) in legs
            record = WindShipOpt.KiteRecord()
            forecast_route(corridor, table, weather, departure; time_cost,
                forecast=forecast_archive, record)
            write_kite_rule_steps(steps, departure, leg, record.edges)
        end
    end
    open(run_file(trace_name), "w") do trace
        println(trace, "departure,rule,hours,lat,lon,aloft,planned,wind_speed,wave_height")
        for departure in example_departures,
            (rule, source) in (("weather", forecast_archive),
                ("plan", PlannedKite(forecast_archive)))
            record = WindShipOpt.KiteRecord()
            forecast_route(first(run_corridors(:caribbean)), table, weather, departure;
                time_cost=first(hourly), forecast=source, record)
            for sample in record.samples
                @printf(trace, "%g,%s,%.2f,%.3f,%.3f,%d,%d,%.2f,%.2f\n", departure, rule,
                    sample.hours, sample.lat, sample.lon, sample.aloft, sample.planned,
                    sample.wind_speed, sample.wave_height)
            end
        end
    end
end

"""
    routing_inputs(rig)

[`RouteTable`](@ref) of the 140 m e-ammonia ship with the [`reference_rigs`](@ref) entry
`rig`, or none where `rig` is "none", and its hourly time cost of each leg [USD/h].
"""
function routing_inputs(rig)
    ship = Ship(forecast_study_design(rig), assumptions)
    return RouteTable(PerformanceTable(ship, assumptions)),
    WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions), assumptions)
end

"the 140 m e-ammonia ship with the [`reference_rigs`](@ref) entry `rig`; none for \"none\""
forecast_study_design(rig) = ShipDesign(:ammonia, 140.0;
    rig_size(rig, rig == "none" ? 0.0 : Dict(reference_rigs)[rig])...)

"""
    write_kite_rule_steps(io, departure, leg, edges)

Write to `io` the steps sailed on a passage and those whose kite state differs from a kite
held to the plan, from its [`WindShipOpt.KiteRuleEdge`](@ref)s `edges`.
"""
function write_kite_rule_steps(io, departure, leg, edges)
    different = filter(edge -> edge.ends_aloft != edge.held_ends_aloft, edges)
    @printf(io, "%g,%s,%d,%d,%.2f,%d,%d,%.2f,%.2f\n", departure, leg, length(edges),
        length(different), sum(edge -> edge.held_cost - edge.cost, different; init=0.0),
        sum(edge.samples for edge in edges), sum(edge.different_samples for edge in edges),
        sum(edge.cost for edge in edges), sum(edge.held_cost for edge in edges))
end

"""
    write_forecast_error(name, corridors...)

Write `name` to the directory of the run in use: per lead day, the root mean square error
against ERA5 of the vector wind [m/s] and the wave height [m] of the archived forecasts
and of the same date in another year, over the nodes of `corridors` and every forecast
in the archive.
"""
function write_forecast_error(name, corridors...)
    points = unique(vcat([vec(collect(zip(corridor.lat, corridor.lon)))
                          for corridor in corridors]...))
    leads = 6.0:6.0:384.0
    totals, samples = zeros(length(leads), 4), zeros(Int, length(leads))
    for issue in 1:WindShipOpt.issue_count(forecast_archive.wind)
        issued = WindShipOpt.issue_time(forecast_archive, issue)
        known = ArchivedForecast(forecast_archive, weather,
            issued + WindShipOpt.FORECAST_LATENCY)
        known.issue == issue || continue
        other_year = ForecastWeather(weather, issued, 0.0)
        for (row, lead) in enumerate(leads)
            issued + lead <= WindShipOpt.duration(weather) || continue
            totals[row, :] .+= forecast_errors(known, other_year, points, issued + lead)
            samples[row] += length(points)
        end
    end
    open(run_file(name), "w") do io
        println(io, "lead_days,wind_forecast,wind_other_year,height_forecast,",
            "height_other_year")
        for (row, lead) in enumerate(leads)
            rms = sqrt.(totals[row, :] ./ samples[row])
            @printf(io, "%.2f,%.3f,%.3f,%.3f,%.3f\n", lead / 24, rms...)
        end
    end
end

"""
    forecast_errors(known, other_year, points, time)

Sums over `points` of the squared error against the weather at `time` of the vector wind
and the wave height of the forecast `known` and of the weather `other_year`.
"""
function forecast_errors(known, other_year, points, time)
    sums = zeros(4)
    for (lat, lon) in points
        truth_wind, truth_height = wind(weather, lat, lon, time),
        first(waves(weather, lat, lon, time))
        for (column, guess) in ((1, known), (2, other_year))
            sums[column] += sum(abs2, wind(guess, lat, lon, time) .- truth_wind)
            sums[column + 2] += (first(waves(guess, lat, lon, time)) - truth_height)^2
        end
    end
    return sums
end

"cases of [`forecast_causes_data`](@ref) sailed on the study's corridors, as (name, plan)"
forecast_cause_plans = ((:perfect, false), (:replanned, :perfect_replan), (:forecast, true),
    (:shortest_lead, :shortest_lead), (:foresight_kite, :foresight_kite))

"""
    forecast_causes_data()

The 140 m e-ammonia ship to Guadeloupe without a rig and with each rig, per departure of
`ensemble_departures`, split into what the loss on the control forecast comes from:
forecast_causes.csv with each [`forecast_cause_cases`](@ref), which
[`forecast_causes_table`](@ref) turns into losses; and how near the kite's limits passages
fly, forecast_margins.csv ([`write_kite_margins`](@ref)).
"""
function forecast_causes_data()
    inputs = Dict(rig => routing_inputs(rig) for rig in ("none", first.(reference_rigs)...))
    cases, trips = [], []
    for departure in ensemble_departures
        step_cases = forecast_cause_cases(departure, inputs)
        append!(cases, step_cases)
        append!(trips, round_trips(step_cases, [departure]))
    end
    write_trips("forecast_causes.csv", cases, trips, :rig, :plan, :departure)
    write_kite_margins("forecast_margins.csv", ensemble_departures)
end

"""
    forecast_cause_cases(departure, inputs)

Round trips from `departure` of the ship with no rig and each rig: the
[`forecast_cause_plans`](@ref) on the study's corridors (`:foresight_kite` for the kite
only), and on fixed courses: the course of the same rig on the control forecast with speed
and kite known perfectly, its course with perfect foresight planned on the control
forecast, and the perfect-foresight course of the ship with no rig both with perfect
foresight and on the control forecast. `inputs` holds each rig's [`routing_inputs`](@ref).
"""
function forecast_cause_cases(departure, inputs)
    rigs = ["none"; first.(reference_rigs)]
    bare_course = course_corridors(inputs["none"], false, departure)
    cases = []
    for rig in rigs
        design = forecast_study_design(rig)
        for (name, plan) in forecast_cause_plans
            plan === :foresight_kite && rig != "kite" && continue
            push!(cases, trip_case(design; forecast=plan, rig, plan=name, departure))
        end
        fixed = ((:forecast_course, course_corridors(inputs[rig], true, departure), false),
            (:perfect_course, course_corridors(inputs[rig], false, departure), true),
            (:common_perfect, bare_course, false), (:common_forecast, bare_course, true))
        for (name, paths, plan) in fixed
            push!(cases, trip_case(design; forecast=plan, paths, course=name, rig,
                plan=name, departure))
        end
    end
    return cases
end

"""
    course_corridors((table, hourly), plan, departure)

Corridors of one node per stage along the courses out and back of the ship with the
[`routing_inputs`](@ref) `(table, hourly)` from `departure` with perfect foresight where
`plan` is false and on the control forecast where true.
"""
function course_corridors((table, hourly), plan, departure)
    return map(run_corridors(:caribbean), hourly) do corridor, time_cost
        leg = plan === false ? route(corridor, table, weather, departure; time_cost) :
              forecast_route(corridor, table, weather, departure; time_cost,
            forecast=forecast_source(plan))
        return WindShipOpt.path_corridor(leg, corridor, 1)
    end
end

"""
    forecast_cause_savings(table, rig)

Cost saving [%] of `rig` against the ship with no rig on the same plan, per case of
forecast_causes.csv read into `table` and per departure, `NaN` where a trip is missing. The
kite with its decisions foreseen is set against the ship's forecast plan, and for a deck
rig that case is its forecast plan.
"""
function forecast_cause_savings(table, rig)
    costs = Dict(zip(zip(table["rig"], table["plan"], table["departure"]), table["cost"]))
    departures = sort(unique(table["departure"]))
    cost(name, plan) = [get(costs, (name, string(plan), departure), NaN)
                        for departure in departures]
    saving(plan, bare) = (1 .- cost(rig, plan) ./ cost("none", bare)) .* 100
    plans = (:perfect, :replanned, :forecast, :shortest_lead, :forecast_course,
        :perfect_course, :common_perfect, :common_forecast)
    saved = Dict(plan => saving(plan, plan) for plan in plans)
    saved[:foresight_kite] = rig == "kite" ? saving(:foresight_kite, :forecast) :
                             saved[:forecast]
    return saved
end

"statistic of savings per case over some departures: points lost from `earlier` to `later`"
cause_loss(earlier, later) = (saved, indices) ->
    mean(saved[earlier][indices]) - mean(saved[later][indices])

"statistic of savings per case over some departures: the mean saving [%] of `plan`"
cause_saving(plan) = (saved, indices) -> mean(saved[plan][indices])

"statistic of savings per case over some departures: share [%] of `perfect` kept by `kept`"
cause_kept(kept, perfect) = (saved, indices) ->
    100kept_share(saved[kept], saved[perfect], indices)

"statistic of savings per case over some departures: `statistic` less `other`"
cause_difference(statistic, other) = (saved, indices) ->
    statistic(saved, indices) - other(saved, indices)

"""
    cause_estimate(statistic, saved, against=nothing)

Value of `statistic` on the savings per case `saved`, or its excess over the rig `against`
paired per departure, with the jackknife standard error over the departures where every
case has a trip, as (value, error, departures).
"""
function cause_estimate(statistic, saved, against=nothing)
    rigs = isnothing(against) ? (saved,) : (saved, against)
    usable = findall(i -> all(!isnan(case[i]) for rig in rigs for case in values(rig)),
        eachindex(first(values(saved))))
    excess(indices) = statistic(saved, usable[indices]) -
                      (isnothing(against) ? 0.0 : statistic(against, usable[indices]))
    n = length(usable)
    return (value=excess(1:n), error=jackknife_error(excess, n), departures=n)
end

"""
    write_kite_margins(name, departures)

Write `name`: for the kite ship re-planning daily on the real weather and on the control
forecast, over the outbound and return passages from `departures`, the samples at sea and
aloft, and the share of those aloft with apparent wind within 1.25 and 4 m/s of the
lowest it flies in and with waves within 0.5 and 1 m of the highest.
"""
function write_kite_margins(name, departures)
    table, hourly = routing_inputs("kite")
    max_wave_height = table.table.max_wave_height
    min_flight_wind = table.table.ship.rig.min_flight_wind
    sources = (("perfect", PerfectForecast()), ("forecast", forecast_archive))
    open(run_file(name), "w") do io
        println(io, "knowledge,samples,aloft,wind_within_1.25,wind_within_4,",
            "waves_within_0.5,waves_within_1")
        for (knowledge, source) in sources
            samples = reduce(vcat, [sailed_samples(table, hourly, source, departure)
                                    for departure in departures])
            margins = kite_margin_shares(samples, min_flight_wind, max_wave_height)
            @printf(io, "%s,%d,%d,%.3f,%.3f,%.3f,%.3f\n", knowledge, margins.samples,
                margins.aloft, margins.wind_within_1p25, margins.wind_within_4,
                margins.waves_within_0p5, margins.waves_within_1)
        end
    end
end

"""
    sailed_samples(table, hourly, source, departure)

Every sample ([`KiteRecord`](@ref)) of the passages out and back from `departure` of the
kite ship of `table` re-planning daily on `source`, with `hourly` its time cost per leg.
"""
function sailed_samples(table, hourly, source, departure)
    record = WindShipOpt.KiteRecord()
    for (corridor, time_cost) in zip(run_corridors(:caribbean), hourly)
        forecast_route(corridor, table, weather, departure; time_cost, forecast=source,
            record)
    end
    return record.samples
end

"""
    kite_margin_shares(samples, min_flight_wind, max_wave_height)

Of the [`KiteRecord`](@ref) `samples`, how many there are, how many aloft, and the share
of those aloft with apparent wind within 1.25 and 4 m/s of `min_flight_wind` [m/s] and with
waves within 0.5 and 1 m of `max_wave_height` [m].
"""
function kite_margin_shares(samples, min_flight_wind, max_wave_height)
    aloft = filter(sample -> sample.aloft, samples)
    wind_margins = [sample.apparent_wind - min_flight_wind for sample in aloft]
    wave_margins = [max_wave_height - sample.wave_height for sample in aloft]
    share_within(margins, limit) = count(<=(limit), margins) / max(length(margins), 1)
    return (; samples=length(samples), aloft=length(aloft),
        wind_within_1p25=share_within(wind_margins, 1.25),
        wind_within_4=share_within(wind_margins, 4.0),
        waves_within_0p5=share_within(wave_margins, 0.5),
        waves_within_1=share_within(wave_margins, 1.0))
end

"""
    bound_assumptions(name, bound)

The assumptions with input `name` at its `bound` (:low or :high).
"""
function bound_assumptions(name, bound)
    entry = assumptions.entries[name]
    return with_value(assumptions, name, bound == :low ? entry.low : entry.high)
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
        isnan(area) && error("the class study has no $rig size for $class on $drive to $route")
        return Symbol(rig) => rig_size(rig, area)
    end)
end

"""
    development_inputs

The inputs of the development study as (input, label, rig, lever, reason): the input,
its name in the paper, the rig whose developer can change it (or `"all"` for every rig
and `"condition"` for a condition it is judged against), what kind of lever it is, and
the reason it is in the study.
"""
development_inputs = [
    (input=:canopy_making_cost_per_area, label="canopy making cost", rig="kite",
        lever="price", reason="Sewing, lines and fittings; a maker lowers them by series " *
                              "production and by design for making."),
    (input=:canopy_cloth_base_price, label="canopy cloth price", rig="kite", lever="price",
        reason="The canopy's other cost; a maker chooses the cloth and how it is bought."),
    (input=:canopy_life, label="canopy life", rig="kite", lever="life",
        reason="What a flight hour of the canopy costs; unmeasured, so what development " *
               "has to prove."),
    (input=:kite_out_of_service, label="kite out of service", rig="kite",
        lever="availability",
        reason="What a maker's reliability work is worth; the same lever for every rig."),
    (input=:kite_max_force_per_area, label="kite force limit per area", rig="kite",
        lever="force",
        reason="Its structure decides the force each m\\textsuperscript{2} may carry."),
    (input=:kite_min_turn_radius, label="kite smallest turn radius", rig="kite",
        lever="force", reason="Steering and control decide how tight, and so how " *
                              "powerful, a pattern can be."),
    (input=:kite_flight_drag, label="kite flight drag", rig="kite", lever="force",
        reason="Deformation, control unit and steering; the low bound, a kite that keeps " *
               "its design shape, is the most a better design can recover."),
    (input=:kite_launch_max_wave_height, label="kite highest wave for launch", rig="kite",
        lever="weather", reason="The tightest of the kite's limits, and the launch " *
                                "system its developer builds."),
    (input=:kite_max_wave_height, label="kite highest wave in flight", rig="kite",
        lever="weather", reason="Depends on how the launch mast, winch and tether " *
                                "take up the ship's motion."),
    (input=:wing_cost_per_area, label="wing sail cost per area", rig="wings", lever="price",
        reason="Structure and series production set a wing's price."),
    (input=:wing_max_lift_coefficient, label="wing sail maximum lift", rig="wings",
        lever="force", reason="Flap and section design decide a wing's force."),
    (input=:wing_out_of_service, label="wing sail out of service", rig="wings",
        lever="availability", reason="The same reliability lever as for every rig."),
    (input=:rotor_cost_per_area, label="rotor cost per area", rig="rotors", lever="price",
        reason="Structure and series production set a rotor's price."),
    (input=:rotor_lift_factor, label="rotor lift", rig="rotors", lever="force",
        reason="Rotor design sets the lift at a given spin; the base is the full-scale " *
               "fit, so the range only reaches down to the CFD value."),
    (input=:rotor_max_wind, label="rotor highest wind", rig="rotors", lever="weather",
        reason="Up to which wind its drive and structure let a rotor keep spinning."),
    (input=:rotor_out_of_service, label="rotor out of service", rig="rotors",
        lever="availability", reason="The same reliability lever as for every rig."),
    (input=:rig_maintenance_fraction, label="rig maintenance share", rig="all",
        lever="price", reason="A maker designs for what its rig costs to keep running."),
    (input=:e_ammonia_price, label="e-ammonia price", rig="condition", lever="condition",
        reason="Not for a developer to change: the fuel bill a rig cuts on the zero-" *
               "emission fuel."),
    (input=:vlsfo_price, label="fuel oil price", rig="condition", lever="condition",
        reason="Not for a developer to change: the fuel bill a rig cuts on fuel oil."),
    (input=:carbon_coverage, label="carbon cost coverage", rig="condition",
        lever="condition", reason="Not for a developer to change: whether the ship pays " *
                                  "for its CO\\textsubscript{2}."),
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
    sensitivity_data()

Every ship of [`sensitivity_ships`](@ref) without a rig and with each rig, at the base
inputs and with each of [`development_inputs`](@ref) at its low and high bound:
sensitivity.csv. The base trips are routed first, so a changed case whose trip never reads
its input reuses them.
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
    trips[base] = round_trips(cases[base], sampled_departures())
    trips[changed] = round_trips(cases[changed], sampled_departures())
    write_trips("sensitivity.csv", cases, trips, :ship, :rig, :input, :bound)
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

"force limits of the kite in the force rating study [kN/m^2]"
study_force_ratings = (0.3, 0.5, 0.7, 1.0)

"kite areas of the force rating study [m^2]"
study_kite_areas = [1600.0 * sqrt(2.0)^k for k in 0:6]

"""
    nearby_kite_areas(kite_area, reach)

Those of [`study_kite_areas`](@ref) within `reach` grid steps of the one nearest `kite_area`.
"""
function nearby_kite_areas(kite_area, reach)
    nearest = argmin(abs.(log.(study_kite_areas ./ kite_area)))
    return study_kite_areas[max(1, nearest - reach):min(end, nearest + reach)]
end

"""
    force_rating_case(bare, route, ship, rating, exponent, area)

Trip case of the ship `bare` with a kite of `area` built for the force limit `rating`, its
cloth following the limit to the power `exponent`.
"""
function force_rating_case(bare, route, ship, rating, exponent, area)
    rated = changed_assumptions((; kite_max_force_per_area=rating,
        canopy_cloth_force_exponent=exponent))
    design = ShipDesign(; bare.drive, bare.length, bare.class, kite_area=area)
    return trip_case(design; assumptions=rated, route, ship, rating, exponent, area)
end

"""
    force_rating_cases(bare, route, ship, kite_area)

Cases of one ship in the force rating study: without a rig; with its kite at each of
[`study_force_ratings`](@ref) and two area steps around `kite_area`; and at the lowest and
highest limit and one area step with cloth that follows the limit in proportion or not at
all.
"""
function force_rating_cases(bare, route, ship, kite_area)
    base = assumptions[:canopy_cloth_force_exponent]
    return [trip_case(bare; route, ship, rating=0.0, exponent=base, area=0.0);
            vec([force_rating_case(bare, route, ship, rating, base, area)
                 for rating in study_force_ratings, area in nearby_kite_areas(kite_area, 2)]);
            vec([force_rating_case(bare, route, ship, rating, exponent, area)
                 for rating in extrema(study_force_ratings), exponent in (0.0, 1.0),
                 area in nearby_kite_areas(kite_area, 1)])]
end

"""
    force_rating_data()

Each ship of [`sensitivity_ships`](@ref) with the cases of [`force_rating_cases`](@ref):
force_rating.csv.
"""
function force_rating_data()
    cases = reduce(vcat, [force_rating_cases(bare, route, ship, areas.kite.kite_area)
                          for (ship, bare, route, areas) in sensitivity_ships()])
    write_trips("force_rating.csv", cases, round_trips(cases, sampled_departures()), :ship,
        :rating, :exponent, :area)
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
        ("force_0.9", design_aspect_ratio, (; kite_max_force_per_area=0.9));
        ("overhead_0.19", design_aspect_ratio, (; canopy_mass_overhead=0.19));
        noise_variants(assumptions[:tether_length_ratio],
            assumptions[:kite_min_turn_radius])]
end

"""
    cargo_kite_variants()

Variants of the kite that flew on cargo ships, as (name, projected area [m^2], changed
inputs): the base, its flat size read as projected, the force limit of its design load, no
flight drag, and canopy wear and launches free, with those of [`noise_variants`](@ref).
"""
function cargo_kite_variants()
    free = (; canopy_life=1e9, tether_lifetime=1e9, kite_cycle_crew_cost=0.0,
        kite_cycle_damage_probability=0.0, kite_cycle_loss_probability=0.0,
        kite_cycle_course_cost=0.0, kite_forced_landing_loss_probability=0.0)
    return [("base", 125.0, (;)); ("flat_as_projected", 160.0, (;));
        ("force_0.9", 125.0, (; kite_max_force_per_area=0.9));
        ("no_flight_drag", 125.0, (; kite_flight_drag=0.0)); ("free_operation", 125.0, free);
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

Each ship of [`goal_limit_ships`](@ref) with each rig at its [`service_shares`](@ref):
availability.csv.
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
    write_trips("availability.csv", cases, round_trips(cases, sampled_departures()), :ship,
        :rig, :share)
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
and every other input held: canopy_life.csv.
"""
function canopy_life_data()
    cases = [trip_case(ShipDesign(; bare.drive, bare.length, bare.class, areas.kite...);
                 assumptions=with_value(assumptions, :canopy_life, life), route, ship, life)
             for (ship, bare, route, areas) in goal_limit_ships(), life in canopy_lives]
    write_trips("canopy_life.csv", vec(cases),
        round_trips(vec(cases), sampled_departures()), :ship, :life)
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

The kite of each ship of [`goal_limit_ships`](@ref) at each of [`canopy_prices`](@ref), its
size and every other input held: canopy_price.csv.
"""
function canopy_price_data()
    goal = WindShipOpt.canopy_price(assumptions)
    inputs = WindShipOpt.canopy_price_inputs
    cases = [trip_case(ShipDesign(; bare.drive, bare.length, bare.class, areas.kite...);
                 assumptions=scaled(inputs, price / goal), route, ship, price)
             for (ship, bare, route, areas) in goal_limit_ships(), price in canopy_prices()]
    write_trips("canopy_price.csv", vec(cases),
        round_trips(vec(cases), sampled_departures()), :ship, :price)
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
    convergence_data()

A 140 m e-ammonia ship to Guadeloupe without a rig and with each rig, routed at corridor
resolutions of 8, 4 and 2 times the base spacing: convergence.csv.
"""
function convergence_data()
    rigs = [("none", 0.0), ("kite", 1600.0), ("wings", 1500.0), ("rotors", 800.0)]
    cases = vec([trip_case(ShipDesign(:ammonia, 140.0; rig_size(rig, area)...); rig, scale)
                 for (rig, area) in rigs, scale in (8.0, 4.0, 2.0)])
    write_trips("convergence.csv", cases, round_trips(cases, sampled_departures()), :rig,
        :scale)
end

"model parts the model-part study switches off, one at a time"
simplified_parts = (:calibration, :waves, :windage, :limits, :rudder)

"""
    rebuilt(object; changes...)

A new object of the type of `object` with its fields, those named in `changes` replaced.
"""
function rebuilt(object; changes...)
    fields = (get(changes, name, getfield(object, name))
              for name in fieldnames(typeof(object)))
    return typeof(object).name.wrapper(fields...)
end

"""
    simplified_ship(ship, part)

`ship` with model `part` switched off: `:none` keeps it whole, `:calibration` drops the
calibration of the hull's calm-water resistance, `:waves` the added resistance in waves,
`:windage` the air drag of the superstructure, `:limits` the heel, leeway and rudder
limits, and `:rudder` the drag of the rudder.
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
    part == :windage && return rebuilt(ship; windage_drag_coefficient=0.0)
    part == :limits &&
        return rebuilt(ship; heel_limit=Inf, leeway_limit=Inf, rudder_max_lift=Inf)
    part == :rudder && return rebuilt(ship; rudder_aspect_ratio=Inf)
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
each of [`simplified_parts`](@ref) switched off: model_parts.csv; and whole over the
[`year_departures`](@ref) of each weather year: weather_years.csv.
"""
function model_parts_data()
    cases = [case for ship_case in sensitivity_ships(), part in (:none, simplified_parts...)
             for case in rig_cases(ship_case...; part)]
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
    size_search_data()

Each ship of [`study_classes`](@ref) with the search of [`searched_sizes`](@ref) over
two rounds, and with each rig at every size of [`snap_area`](@ref) within its
[`size_bounds`](@ref), tagged round -1: size_search.csv.
"""
function size_search_data()
    classes = ship_classes()
    ships = [(classes[name], drive, route) for (name, drive, route) in study_classes]
    cases, trips = searched_sizes(ships, 2)
    grid = []
    for (class, drive, route) in ships, (rig, (lower, upper)) in size_bounds(class)
        for step in ceil(Int, 4log2(lower)):floor(Int, 4log2(upper))
            push!(grid, class_case(class, drive, rig, 2.0^(step / 4), route; round=-1))
        end
    end
    append!(trips, round_trips(grid, sampled_departures()))
    append!(cases, grid)
    write_trips("size_search.csv", cases, trips, :class, :route, :drive, :rig, :area,
        :round)
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

Each ship of `combination_ships` on every route on VLSFO and e-ammonia without a rig,
with each kite of `combination_kites`, with each rotor area of
[`combination_rotors`](@ref), and with each kite of `combination_paired_kites` flown
together with each rotor area: combination.csv.
"""
function combination_data()
    cases = []
    for ship in combination_ships, drive in (:vlsfo, :ammonia), route in route_names
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

"routes of the tow point study: westerlies ahead out and astern home, and trade winds abeam"
tow_point_routes = (:new_york, :tubarao)

"""
    tow_point_positions(hull)

Tow positions of the tow point study as (name, share of the way from midship to the
launch mast at the forward end of the deck): the bow, the hull's lateral centre and
midship.
"""
tow_point_positions(hull) = (("bow", 1.0),
    ("centre", WindShipOpt.lateral_centre(hull) /
               WindShipOpt.launch_mast_position(hull, assumptions)),
    ("midship", 0.0))

"""
    tow_point_data()

Every ship class on e-ammonia on each of `tow_point_routes` without a rig and with its
cheapest kite of the class study towing from each of [`tow_point_positions`](@ref):
tow_point.csv.
"""
function tow_point_data()
    classes_table = read_table(data_file("classes.csv"))
    cases = []
    for class in values(ship_classes()), route in tow_point_routes
        bare = ShipDesign(:ammonia, class)
        push!(cases, trip_case(bare; class=class.name, route, tow="none", area=0.0))
        area = best_area(classes_table, class.name, string(route), "ammonia", "kite")
        isfinite(area) || continue
        design = ShipDesign(:ammonia, class; kite_area=area)
        for (tow, position) in tow_point_positions(Hull(class, assumptions))
            push!(cases, trip_case(design; class=class.name, route, tow, area,
                assumptions=with_value(assumptions, :kite_tow_position, position)))
        end
    end
    write_trips("tow_point.csv", cases, round_trips(cases, sampled_departures()), :class,
        :route, :tow, :area)
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

"an empty band of [`add_flight_hours!`](@ref), in the order of the columns of flight.csv"
empty_flight_bin = (hours=0.0, flying=0.0, available=0.0, pulling=0.0, thrust_hours=0.0,
    distance=0.0, lowest_angle=Inf)

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
        assumptions)
    bins = Dict{Tuple{Int, Int}, typeof(empty_flight_bin)}()
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
                 drive in (:ammonia, :vlsfo),
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
            force = rig_force(ship.rig, ship.env, wind, deg2rad(angle), knots * KNOT, 0.0)
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
    (ship="140 m", drives=(:vlsfo, :ammonia), speeds=(8.0, 9.0, 10.0, 11.0),
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

"rigid kites [number, m^2 each] of the rigid kite study"
rigid_kite_fleets = [vec([(count, unit) for count in (1, 2, 3, 4, 6, 8),
                          unit in (30.0, 54.0, 100.0)]);
    [(1, unit) for unit in (200.0, 300.0, 500.0)]]

"inputs where the low bound favours a rigid kite"
rigid_low_favours = (:rigid_tether_price, :rigid_tether_density,
    :rigid_tether_drag_coefficient, :rigid_structure_cost_per_mass,
    :rigid_structure_cost_per_area, :rigid_avionics_cost, :rigid_drive_cost,
    :rigid_drive_margin, :rigid_ship_power_cost, :rigid_perch_cost, :rigid_perch_width,
    :rigid_station_mass, :rigid_upkeep_per_area, :rigid_cycle_loss_probability,
    :rigid_idle_rotor_drag, :rigid_hover_energy_price, :rigid_hover_minutes,
    :rigid_hover_thrust_ratio, :rigid_mass_exponent, :rigid_profile_drag,
    :rigid_min_turn_radius, :kite_out_of_service)

"inputs where the high bound favours a rigid kite"
rigid_high_favours = (:rigid_lifetime, :rigid_hover_max_wave_height, :rigid_hover_max_wind,
    :rigid_max_wind,
    :rigid_max_lift, :rigid_span_efficiency, :rigid_max_force_per_area,
    :rigid_tether_stress, :rigid_rotor_area_ratio, :rigid_rotor_fill,
    :rigid_hover_air_density, :rigid_hover_efficiency)

"""
    rigid_assumptions(scenario, unit)

The assumptions of the rigid kite study at a kite of `unit` [m^2]: at base values for
"base", with the mass going as span cubed for "cubic", and for "optimistic" with every
rigid kite input at the bound that favours it.
"""
function rigid_assumptions(scenario, unit)
    base = with_value(assumptions, :rigid_unit_area, unit)
    scenario == "base" && return base
    scenario == "cubic" && return with_value(base, :rigid_mass_exponent, 3.0)
    for name in rigid_low_favours
        base = with_value(base, name, base.entries[name].low)
    end
    for name in rigid_high_favours
        base = with_value(base, name, base.entries[name].high)
    end
    return base
end

"total areas [m^2] of `rig_type` at the shares of the deck of the rigid kite study"
deck_shares(rig_type, hull) =
    [share * largest_area(rig_type, hull) for share in (0.2, 0.5, 1.0)]

"""
    rigid_kite_data()

Each ship of `combination_ships` on every route on VLSFO and e-ammonia without a rig, with
each soft kite of `combination_kites`, with rotors and wings at each share of the deck, and
with each fleet of `rigid_kite_fleets` that fits at base and optimistic inputs:
rigid_kite.csv.
"""
function rigid_kite_data()
    cases = []
    for ship in combination_ships, drive in (:vlsfo, :ammonia), route in route_names
        hull = Hull(study_hull(ship), assumptions)
        sizes = [("none", (;));
            [("kite", (; kite_area)) for kite_area in combination_kites];
            [("rotors", (; rotor_area))
             for rotor_area in deck_shares(WindShipOpt.RotorRig, hull)];
            [("wings", (; wing_area)) for wing_area in deck_shares(WingRig, hull)]]
        for (rig, size) in sizes
            design = ShipDesign(drive, study_hull(ship); size...)
            push!(cases, trip_case(design; route, ship, drive, rig, count=0, unit=0.0))
        end
        for (count, unit) in rigid_kite_fleets, scenario in ("base", "cubic", "optimistic")
            WindShipOpt.rigid_kites_fit(count, hull,
                with_value(assumptions, :rigid_unit_area, unit)) || continue
            design = ShipDesign(drive, study_hull(ship); rigid_kite_area=count * unit)
            push!(cases, trip_case(design; assumptions=rigid_assumptions(scenario, unit),
                route, ship, drive, rig="rigid " * scenario, count, unit))
        end
    end
    write_trips("rigid_kite.csv", cases, round_trips(cases, sampled_departures()), :ship,
        :route, :drive, :rig, :count, :unit)
end

"wing areas [m^2] and mass exponents of the rigid kite scaling study"
rigid_scaling_areas = (30.0, 54.0, 100.0, 200.0, 300.0, 500.0)
rigid_scaling_exponents = (2.2, 2.75, 3.0, 3.3)

"flight hours and launches a year of the annual cost of a kite"
kite_year = (flight_hours=3000.0, launches=150.0)

"soft kite areas [m^2] the rigid kite scaling study compares with"
rigid_scaling_soft_kites = (500.0, 1000.0, 2000.0, 4000.0)

"""
    annual_kite_cost(rig, assumptions)

Cost of `rig` over a year of [`kite_year`](@ref) [USD]: capital recovery, maintenance,
wear and upkeep, launches and landings, losses among them.
"""
function annual_kite_cost(rig, assumptions)
    capital, _, annuity = WindShipOpt.rig_costs(rig, assumptions)
    return annuity + WindShipOpt.rig_maintenance(rig, capital, assumptions) +
           WindShipOpt.wear_cost(rig, assumptions) * kite_year.flight_hours +
           WindShipOpt.cycle_cost(rig, assumptions) * kite_year.launches
end

"""
    beam_thrust(rig, i)

Thrust [N] of one kite of `rig` on a beam course without side weight at apparent wind speed
number `i` of its table, zero where it does not fly.
"""
function beam_thrust(rig, i)
    force = rig.forces[i, findfirst(≈(π / 2), rig.courses), 1]
    isfinite(force.peak_tension) || return 0.0
    air_density = Environment(assumptions).air_density
    return 0.5air_density * rig.wind_speeds[i]^2 * rig.area * force.force[2]
end

"""
    rigid_scaling_data()

Per wing area and mass exponent of a rigid kite: span, mass, stall speed, hover power,
lowest flying wind, price, annual cost and beam thrust over apparent wind; per area of a
soft kite with the canopy at its goal: the last four: rigid_scaling.csv.
"""
function rigid_scaling_data()
    hull = Hull(study_hull("140 m"), assumptions)
    env = Environment(assumptions)
    open(run_file("rigid_scaling.csv"), "w") do file
        println(file, "kind,area,exponent,span,mass,stall,hover_power,lowest_wind,price,",
            "annual,wind,thrust")
        for area in rigid_scaling_areas, exponent in rigid_scaling_exponents
            changed = with_value(with_value(assumptions, :rigid_unit_area, area),
                :rigid_mass_exponent, exponent)
            rig = WindShipOpt.rigid_kite_rig(area, hull, changed; courses=[π / 2],
                side_weights=[0.0])
            (; mass, hover_power) = rig.airframe
            span = sqrt(area * changed[:rigid_aspect_ratio])
            stall = sqrt(2mass * env.gravity /
                         (env.air_density * area * changed[:rigid_max_lift]))
            price = first(WindShipOpt.rig_costs(rig, changed))
            annual = annual_kite_cost(rig, changed)
            for i in eachindex(rig.wind_speeds)
                println(file, join(("rigid", area, exponent, span, mass, stall, hover_power,
                        rig.min_flight_wind, price, annual, rig.wind_speeds[i],
                        beam_thrust(rig, i)), ","))
            end
        end
        for area in rigid_scaling_soft_kites
            rig = KiteRig(area, 3.0, hull, assumptions)
            price = first(WindShipOpt.rig_costs(rig, assumptions))
            annual = annual_kite_cost(rig, assumptions)
            for i in eachindex(rig.wind_speeds)
                println(file, join(("soft", area, 0.0, 0.0, 0.0, 0.0, 0.0,
                        rig.min_flight_wind, price, annual, rig.wind_speeds[i],
                        beam_thrust(rig, i)), ","))
            end
        end
    end
end
