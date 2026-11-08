# Data step of the route view of the companion explorer in site/: the routed passages of
# the passage figure's ship, each with the state of its ship and rig at every point the
# router sailed. Included by paper.jl after paper_data.jl; run it as
# `paper(:passages; fidelity)`.

"the ship whose passages the site shows: the passage figure's"
passage_ship = (drive=:methanol, length=140.0)

"the rigs and sizes [m²] the site shows, each size the passage figure draws among them"
passage_rigs = [("none", 0.0), ("kite", 800.0), ("kite", 1600.0), ("kite", 3200.0),
    ("kite", 6400.0), ("wings", 500.0), ("wings", 1000.0), ("wings", 1500.0),
    ("wings", 2000.0), ("rotors", 200.0), ("rotors", 400.0), ("rotors", 800.0),
    ("rotors", 1200.0)]

"samples along the closed cycle of a recorded kite pattern, equal in time"
pattern_samples = 16

"spacing of the exported wind field [deg] and its time step [h]"
wind_field = (spacing=5.0, hours=12.0)

"""
    wind_side(east, north, course)

+1 where the wind comes from starboard of `course` [rad from north], -1 from port.
"""
function wind_side(east, north, course)
    return sin(atan(-east, -north) - course) >= 0 ? 1 : -1
end

"""
    wing_incidence(rig, (lift, drag))

Angle [rad] between the chord and the apparent wind of a wing at the trim `(lift, drag)` of
[`trim_settings`](@ref): from the lift slope of its aspect ratio while attached, from the
force direction when stalled.
"""
function wing_incidence(rig::WindShipOpt.WingRig, (lift, drag))
    stalled = drag > WindShipOpt.drag_coefficient(rig, lift) + 1e-9
    stalled && return atan(drag - rig.profile_drag_coefficient, lift)
    ratio = rig.effective_aspect_ratio
    return lift * (ratio + 2) / (2π * ratio)
end

"""
    ship_frame_position(radial, apparent_angle, side)

Azimuth [deg, 0 ahead, positive to starboard] and elevation [deg] of a kite at the unit
`radial` of [`PatternStep`](@ref) (apparent downwind, crosswind, up) for an apparent wind
`apparent_angle` [rad] off the bow on `side`.
"""
function ship_frame_position(radial, apparent_angle, side)
    downwind, crosswind, up = radial
    sine, cosine = sincos(apparent_angle)
    ahead = crosswind * sine - downwind * cosine
    starboard = side * (-crosswind * cosine - downwind * sine)
    return atand(starboard, ahead), asind(clamp(up, -1.0, 1.0))
end

"""
    resampled_cycle(path)

The closed cycle `path` of [`PatternStep`](@ref)s as unit positions at
[`pattern_samples`](@ref) equal fractions of its duration, and its duration [s].
"""
function resampled_cycle(path)
    period = sum(step.time for step in path)
    times = cumsum(step.time for step in path) .- first(path).time
    closed = [path; path[1]]
    return [begin
                t = (k - 1) * period / pattern_samples
                i = clamp(searchsortedlast(times, t), 1, length(path))
                share = clamp((t - times[i]) / path[i].time, 0.0, 1.0)
                a, b = closed[i].radial, closed[i + 1].radial
                a .+ share .* (b .- a)
            end for k in 1:pattern_samples], period
end

"""
    kite_patterns(ship, model)

For the kite rig of `ship` flown as `model`: the unit positions and period [s] of the cycle
of each pattern of its table, by index (wind speed, course, side weight); `nothing` where
no pattern flies.
"""
function kite_patterns(ship, model)
    rig = ship.rig
    forces, parameters = WindShipOpt.solved_patterns(model, rig.max_force, assumptions,
        rig.wind_speeds, rig.courses, rig.side_weights)
    return map(CartesianIndices(forces)) do index
        isfinite(forces[index].force[1]) || return nothing
        path = WindShipOpt.PatternStep[]
        WindShipOpt.PatternForce(model, WindShipOpt.pattern_of(parameters[index]),
            rig.wind_speeds[index[1]], rig.max_force; path)
        return isempty(path) ? nothing : resampled_cycle(path)
    end
end

"""
    recorded_pattern(case, trace, i)

Azimuths and elevations [0.1 deg] of the [`pattern_samples`](@ref) points of the table
pattern nearest the apparent wind and course of sample `i` of `trace` at its trim, then its
period [0.1 s]; `nothing` where the kite is down.
"""
function recorded_pattern(case, trace, i)
    trace.flying[i] || return nothing
    rig = case.ship.rig
    pattern = case.patterns[argmin(abs.(rig.wind_speeds .- trace.apparent_wind[i])),
        argmin(abs.(rig.courses .- (π - trace.apparent_angle[i]))), trace.trim[i]]
    isnothing(pattern) && return nothing
    points, period = pattern
    side = wind_side(trace.wind_east[i], trace.wind_north[i], trace.course[i])
    azimuths = [ship_frame_position(point, trace.apparent_angle[i], side) for point in points]
    return [round.(Int, 10 .* first.(azimuths)); round.(Int, 10 .* last.(azimuths));
            round(Int, 10 * period)]
end

"""
    recorded_trim(case, trace)

The rig's recorded state along `trace` for the site: wing chords [deg from the bow,
positive to starboard] and lift coefficients ×100, rotor spin ratios ×100 positive
clockwise from above, or per sample the [`recorded_pattern`](@ref) of the kite.
"""
function recorded_trim(case, trace)
    rig = case.ship.rig
    count = length(trace.time)
    if rig isa WindShipOpt.WingRig
        sides = wind_side.(trace.wind_east, trace.wind_north, trace.course)
        incidences = [wing_incidence(rig, trim) for trim in trace.trim]
        return (; chord=round.(Int,
            rad2deg.(sides .* (trace.apparent_angle .- incidences))),
            lift=[round(Int, 100 * first(trim)) for trim in trace.trim])
    elseif rig isa WindShipOpt.RotorRig
        sides = wind_side.(trace.wind_east, trace.wind_north, trace.course)
        return (; spin=round.(Int, -100 .* sides .* trace.trim))
    elseif rig isa WindShipOpt.KiteRig
        return (; pattern=[recorded_pattern(case, trace, i) for i in 1:count])
    end
    return (;)
end

"""
    recorded_leg(case, leg, trace, direction, departure, start)

The columns of one routed `leg` of `case` for the site, left at `start` [h] on the round
trip of departure number `departure`, with its route nodes; integers in the units of the
site: hours and kilonewtons ×10, degrees ×100 for positions, knots ×10, megawatts ×100,
wind in m/s ×10.
"""
function recorded_leg(case, leg, trace, direction, departure, start)
    columns = (; t=round.(Int, trace.time .* 10), lat=round.(Int, trace.lat .* 100),
        lon=round.(Int, trace.lon .* 100),
        course=round.(Int, rad2deg.(trace.course)),
        east=round.(Int, trace.wind_east .* 10), north=round.(Int, trace.wind_north .* 10),
        speed=round.(Int, trace.speed ./ KNOT .* 10),
        thrust=round.(Int, trace.rig_thrust ./ 100),
        power=round.(Int, trace.fuel_power ./ 1e4),
        apparent_wind=round.(Int, trace.apparent_wind .* 10),
        apparent_angle=round.(Int, rad2deg.(trace.apparent_angle)),
        flying=Int.(trace.flying),
        event=[flight_event(trace, i) for i in eachindex(trace.time)],
        trim=recorded_trim(case, trace))
    return (; design=case.index, direction, departure, start, duration=leg.duration,
        fuel_energy=leg.fuel_energy / 1e12,
        nodes=[(round(point[1]; digits=3), round(point[2]; digits=3)) for point in leg.path],
        columns)
end

"event code of sample `i` of a trace: 0 none, 1 launch, 2 landing, 3 forced landing"
function flight_event(trace, i)
    trace.launched[i] && return 1
    trace.forced[i] && return 3
    trace.landed[i] && return 2
    return 0
end

"""
    passage_cases()

The ships of [`passage_rigs`](@ref) that fit, each with its [`PerformanceTable`](@ref), time
costs and, for a kite, its [`kite_patterns`](@ref).
"""
function passage_cases()
    cases = []
    for (rig, area) in passage_rigs
        design = ShipDesign(passage_ship.drive, passage_ship.length; rig_size(rig, area)...)
        ship = Ship(design, assumptions)
        isnothing(ship) && continue
        patterns = ship.rig isa WindShipOpt.KiteRig ?
                   kite_patterns(ship,
            first(WindShipOpt.kite_model(area, design.kite_aspect_ratio, assumptions))) : nothing
        push!(cases, (; index=length(cases), rig, area, design, ship, patterns,
            table=PerformanceTable(ship, assumptions),
            hourly=WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions), assumptions)))
    end
    return cases
end

"""
    routed_round_trip(case, name, k, departure, port_hours)

The recorded outbound and return legs of `case` on route `name` of departure number `k`,
leaving at `departure` [h], and the times they span [h], or `nothing` if either fails.
"""
function routed_round_trip(case, name, k, departure, port_hours)
    outbound, inbound = run_corridors(name)
    out, out_trace = traced_passage(case.table, outbound, departure, first(case.hourly))
    isnothing(out) && return nothing
    back_departure = departure + out.duration + port_hours
    back, back_trace = traced_passage(case.table, inbound, back_departure, last(case.hourly))
    isnothing(back) && return nothing
    return (; legs=[recorded_leg(case, out, out_trace, "out", k - 1, departure),
            recorded_leg(case, back, back_trace, "back", k - 1, back_departure)],
        span=(departure, back_departure + back.duration))
end

"""
    wind_frames(legs, span)

The 10 m wind [0.1 m/s] on a grid around `legs` over `span` [h] for one departure: the
grid, and per frame the east and north components, row after row.
"""
function wind_frames(legs, span)
    lats = [first(node) for leg in legs for node in leg.nodes]
    lons = [last(node) for leg in legs for node in leg.nodes]
    lat_axis = floor(minimum(lats) - 5):(wind_field.spacing):ceil(maximum(lats) + 5)
    lon_axis = floor(minimum(lons) - 5):(wind_field.spacing):ceil(maximum(lons) + 5)
    times = first(span):(wind_field.hours):last(span)
    frames = [begin
                  winds = [wind(weather, lat, lon, t) for lat in lat_axis, lon in lon_axis]
                  (east=round.(Int, 10 .* first.(winds)),
                      north=round.(Int, 10 .* last.(winds)))
              end for t in times]
    return (; start=first(span), lat0=first(lat_axis), lon0=first(lon_axis), wind_field.spacing,
        nlat=length(lat_axis), nlon=length(lon_axis), wind_field.hours,
        east=[vec(frame.east) for frame in frames],
        north=[vec(frame.north) for frame in frames])
end

"""
    passage_design(case)

The geometry of the ship and rig of `case` the site draws.
"""
function passage_design(case)
    hull = case.ship.hull
    rig = case.ship.rig
    common = (; case.rig, case.area, length=hull.length, beam=hull.beam, draft=hull.draft,
        depth=assumptions[:depth_draft_ratio] * hull.draft)
    positions(unit) = WindShipOpt.unit_positions(unit, hull, assumptions)
    if rig isa WindShipOpt.WingRig
        return (; common..., count=rig.count, height=rig.height,
            foot_height=rig.foot_height, width=rig.height / assumptions[:wing_aspect_ratio],
            positions=positions(rig))
    elseif rig isa WindShipOpt.RotorRig
        return (; common..., count=rig.count, height=rig.height, foot_height=rig.foot_height,
            diameter=rig.diameter, positions=positions(rig))
    elseif rig isa WindShipOpt.KiteRig
        return (; common..., span=sqrt(case.design.kite_aspect_ratio * rig.area),
            tether_length=rig.tether_length, attach_height=rig.attach_height,
            attach_position=rig.attach_position)
    end
    return common
end

"""
    departure_label(hours)

The date of a departure `hours` [h] after the origin of the weather.
"""
departure_label(hours) = hasproperty(weather, :origin) ?
    string(Date(weather.origin + Hour(round(Int, hours)))) : "day $(round(Int, hours / 24))"

"""
    passages_data()

The passages of [`passage_cases`](@ref) on every route over the sampled departures, one
passages-<route>.json each with its winds-<route>.json, and passages.json naming them.
"""
function passages_data()
    cases = passage_cases()
    departure_list = sampled_departures()
    port_hours = 24assumptions[:port_time_per_call]
    work = [(route, case, k) for route in route_names, case in cases
            for k in eachindex(departure_list)]
    results = Vector{Any}(nothing, length(work))
    Threads.@threads :greedy for i in eachindex(work)
        route, case, k = work[i]
        results[i] = routed_round_trip(case, route, k, departure_list[k], port_hours)
    end
    for route in route_names
        write_route_files(route, cases, departure_list, work, results)
    end
    index = (; fidelity=string(paper_run.fidelity),
        git_commit=paper_run.record["git_commit"], weather=weather_name,
        routes=[(; name=string(name), label=route_label(name)) for name in route_names],
        departures=[(; hours, label=departure_label(hours)) for hours in departure_list],
        designs=passage_design.(cases), pattern_samples, port_hours)
    open(io -> write_json(io, index), run_file("passages.json"), "w")
end

"""
    write_route_files(route, cases, departure_list, work, results)

Write passages-<route>.json and winds-<route>.json from the `results` of `work`.
"""
function write_route_files(route, cases, departure_list, work, results)
    routed = [(k, results[i]) for (i, (name, _, k)) in enumerate(work) if name == route &&
              !isnothing(results[i])]
    legs = [leg for (_, result) in routed for leg in result.legs]
    design_count = Set(leg.design for leg in legs)
    open(run_file("passages-$route.json"), "w") do io
        write_json(io, (; route=string(route), legs))
    end
    winds = [begin
                 trips = [r for (k, r) in routed if k == index]
                 isempty(trips) ? nothing :
                 wind_frames([leg for trip in trips for leg in trip.legs],
                     (minimum(first(trip.span) for trip in trips),
                         maximum(last(trip.span) for trip in trips)))
             end for index in eachindex(departure_list)]
    open(io -> write_json(io, (; route=string(route), winds)), run_file("winds-$route.json"),
        "w")
    println("passages of ", route, ": ", length(legs), " legs, ", length(design_count),
        " designs, ", filesize(run_file("passages-$route.json")) ÷ 1000, " kB, winds ",
        filesize(run_file("winds-$route.json")) ÷ 1000, " kB")
end
