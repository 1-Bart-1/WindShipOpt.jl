# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# What the planner does on the development case, as figures: its planning grid and routes on
# one passage, each rig's saving against a finer grid per departure, and the time a round
# trip takes to plan and to sail live.
#
#   julia +1.12 --project=scripts -t auto scripts/planner_figures.jl <out_dir>
#   julia +1.12 --project=scripts scripts/planner_figures.jl --plot <out_dir> <study_dir>
#
# `draw_outliers` routes and draws each departure a gate comparison flags.
# The first routes into <out_dir>; the second draws from it and from the gate files of the
# grid study in <study_dir> into <out_dir>/*.png.
using CairoMakie
include(joinpath(@__DIR__, "router_grid_study.jl"))
include(joinpath(@__DIR__, "map_plotting.jl"))

"departure of the passage drawn on the map [h]"
MAP_DEPARTURE = 10080.0

"departures timed [h]"
TIMED_DEPARTURES = (0.0, 10080.0, 20160.0)

"""
(label, study entry) of the settings timed: the old full-corridor search, 60/15, and 45/11
with far rows a fixed stride apart and graded
"""
TIMED = (("full corridor 240/60", "whole_240"), ("60/15", "grid_60"),
    ("45/11 two zones", "two_zone"), ("45/11 graded", "base"))

"(label, study entry) of the settings whose tracks the map draws"
TRACKED = (("60/15", "grid_60"), ("45/11 two zones", "two_zone"),
    ("45/11 graded", "base"), ("30/7.5 steps halved", "grid_30_steps_half"))

"""
    planned_trip(case, departure, fidelity; live=false)

Round trip of `case` leaving at `departure` [h] at the grid study's `fidelity`, sailed live
where `live`: the two `Leg`s, or `nothing`, and the seconds it took.
"""
function planned_trip(case, departure, fidelity; live=false)
    ship = Ship(case.design, assumptions)
    hourly = WindShipOpt.leg_time_costs(first(WindShipOpt.ship_costs(ship, assumptions)),
        assumptions)
    table = WindShipOpt.RouteTable(WindShipOpt.PerformanceTable(ship, assumptions))
    forecast = live ? ReplannedForecast(PerfectForecast(); adapts=:live) : nothing
    port = 24assumptions[:port_time_per_call]
    trip = nothing
    seconds = @elapsed trip = WindShipOpt.route_round_trip(table,
        corridors(case.route, fidelity.scale)..., weather, departure, port, hourly, Inf,
        forecast)
    return trip, seconds
end

"write the nodes `(lat, lon)` of `corridor` where `kept` to `path` as CSV"
write_nodes(path, corridor, kept) = open(path, "w") do io
    println(io, "lat,lon")
    foreach(i -> println(io, corridor.lat[i], ",", corridor.lon[i]), findall(kept))
end

"hours after departure of the re-plan whose grid the map draws"
MAP_PLAN_HOURS = 72.0

"""
    write_planning_grid(out_dir, trip)

Nodes of the outbound and return corridors at the default fidelity that the plan made
[`MAP_PLAN_HOURS`](@ref) into each leg of `trip` keeps near the ship and far from it, and
every node of the corridor, to `out_dir`/grid_<leg>_<near|far|all>.csv.
"""
function write_planning_grid(out_dir, trip)
    for (leg, corridor, sailed) in zip(("out", "back"), corridors(:caribbean, 1), trip)
        stage = findfirst(point -> point[3] >= MAP_PLAN_HOURS, sailed.path)
        lat, lon = sailed.path[stage][1:2]
        planning, first_stage, near = WindShipOpt.planning_corridor(corridor, stage,
            WindShipOpt.nearest_lateral(corridor, stage, lat, lon))
        kept = axes(planning.water, 1) .- first_stage
        write_nodes(joinpath(out_dir, "grid_$(leg)_near.csv"), planning,
            planning.water .& (0 .<= kept .< near))
        write_nodes(joinpath(out_dir, "grid_$(leg)_far.csv"), planning,
            planning.water .& (kept .>= near))
        write_nodes(joinpath(out_dir, "grid_$(leg)_all.csv"), corridor, corridor.water)
    end
end

"append the track of each leg of `trip` to `io` as lines `label,leg,lat,lon,aloft`"
function write_track(io, label, trip)
    for (leg, sailed) in zip(("out", "back"), trip), (point, aloft) in
                                                       zip(sailed.path, sailed.aloft)
        println(io, join((label, leg, point[1], point[2], aloft), ","))
    end
end

"""
    open_rows(path, header)

`path` opened to append, with the line `header` written where it is new, and the settings
named in the first column of its rows.
"""
function open_rows(path, header)
    isfile(path) || write(path, header * "\n")
    return open(path, "a"), Set(first.(split.(readlines(path)[2:end], ",")))
end

"""
    route_figures(out_dir)

Route what the figures draw into `out_dir`: the planning grid at the default settings, the
kite's tracks at [`MAP_DEPARTURE`](@ref) at each of [`TRACKED`](@ref), and the seconds of
each round trip of [`TIMED_DEPARTURES`](@ref) at each of [`TIMED`](@ref), planned and sailed
edge by edge and sailed live; settings already in its files are skipped.
"""
function route_figures(out_dir)
    mkpath(out_dir)
    kite = only(filter(case -> case.rig == "kite", development_cases()))
    Ship(kite.design, assumptions)
    io, done = open_rows(joinpath(out_dir, "tracks.csv"), "setting,leg,lat,lon,aloft")
    for (label, name) in TRACKED
        label in done && continue
        fidelity = STUDY[name]
        WindShipOpt.with_router_settings(fidelity.settings) do
            trip, _ = planned_trip(kite, MAP_DEPARTURE, fidelity)
            write_track(io, label, trip)
            name == "base" && write_planning_grid(out_dir, trip)
        end
        flush(io)
    end
    close(io)
    io, done = open_rows(joinpath(out_dir, "seconds.csv"),
        "setting,rig,departure,live,seconds")
    for (label, name) in TIMED
        label in done && continue
        fidelity = STUDY[name]
        corridors(:caribbean, fidelity.scale)
        jobs = [(case, departure, live) for case in development_cases()
                for departure in TIMED_DEPARTURES for live in (false, true)]
        lines = Vector{String}(undef, length(jobs))
        WindShipOpt.with_router_settings(fidelity.settings) do
            Threads.@threads :greedy for k in eachindex(jobs)
                case, departure, live = jobs[k]
                _, seconds = planned_trip(case, departure, fidelity; live)
                lines[k] = join((label, case.rig, departure, live, seconds), ",")
            end
        end
        foreach(line -> println(io, line), lines)
        flush(io)
    end
    close(io)
end

"rows of the CSV file at `path` as named tuples of strings"
function read_rows(path)
    header, lines... = readlines(path)
    names = Tuple(Symbol.(split(header, ",")))
    return [NamedTuple{names}(Tuple(split(line, ","))) for line in lines]
end

"longitude-latitude points of the rows of `rows`"
row_points(rows) =
    [Point2f(parse(Float64, row.lon), parse(Float64, row.lat)) for row in rows]

"(label, colour, line style) of each track on the map"
TRACK_STYLES = (("60/15", Makie.wong_colors()[2], :solid),
    ("45/11 two zones", Makie.wong_colors()[3], :solid), ("45/11 graded", :black, :solid),
    ("30/7.5 steps halved", Makie.wong_colors()[1], :dash))

"""
    track_figure(path, tracks, styles; grid=nothing, titles, limits)

Save to `path` the outbound and return passages of the rows `tracks` (setting, leg, lat,
lon), one line per (label, colour, line style) of `styles`, over land, in panels titled
`titles` with axis `limits`; where `grid(leg, part)` gives the "all", "far" and "near"
nodes of a plan, those as well.
"""
function track_figure(path, tracks, styles; grid=nothing, titles, limits)
    fig = Figure(size=(1000, 430))
    for (k, (leg, title)) in enumerate(zip(("out", "back"), titles))
        axis = Axis(fig[1, k]; title, aspect=DataAspect(), xlabel="longitude [°]",
            ylabel=k == 1 ? "latitude [°]" : "", limits)
        draw_land!(axis, mask)
        if !isnothing(grid)
            scatter!(axis, grid(leg, "all"); color=(:grey, 0.25), markersize=1.2,
                label="corridor, 45/11 nmi")
            scatter!(axis, grid(leg, "far"); color=:grey35, markersize=3.5,
                label="far nodes of the plan")
            scatter!(axis, grid(leg, "near"); color=:darkorange, markersize=2.5,
                label="near nodes of the plan")
        end
        for (label, color, linestyle) in styles
            points = row_points(filter(row -> row.setting == label && row.leg == leg,
                tracks))
            lines!(axis, points; color, linestyle, linewidth=2, label="track, $label")
        end
        k == 1 && Legend(fig[2, 1:2], axis; orientation=:horizontal, nbanks=2,
            labelsize=11, markersize=8, framevisible=false)
    end
    resize_to_layout!(fig)
    save(path, fig)
end

"""
    map_figure(out_dir)

The outbound and return passages of the kite at [`MAP_DEPARTURE`](@ref): the corridor, the
nodes the plan [`MAP_PLAN_HOURS`](@ref) into each leg keeps near the ship and far from it,
and the tracks on each grid.
"""
map_figure(out_dir) = track_figure(joinpath(out_dir, "planning_grid.png"),
    read_rows(joinpath(out_dir, "tracks.csv")), TRACK_STYLES;
    grid=(leg, part) -> row_points(read_rows(joinpath(out_dir, "grid_$(leg)_$(part).csv"))),
    titles=("(a) Ushant to Guadeloupe", "(b) Guadeloupe to Ushant"),
    limits=(-66, 0, 10, 52))

"""
    outlier_figure(out_dir, case, departure, settings)

Route the round trip of the gate `case` leaving at `departure` [h] at each (label,
fidelity) of `settings`, the first drawn in black and the second dashed, and draw both legs
to `out_dir`/outlier_<route>_<rig>_<departure>.png.
"""
function outlier_figure(out_dir, case, departure, settings)
    name = "outlier_$(case.route)_$(case.rig)_$(round(Int, departure))"
    mkpath(out_dir)
    Ship(case.design, assumptions)
    rows = String[]
    for (label, fidelity) in settings
        WindShipOpt.with_router_settings(fidelity.settings) do
            trip, _ = planned_trip(case, departure, fidelity)
            io = IOBuffer()
            write_track(io, label, trip)
            append!(rows, split(String(take!(io)), "\n"; keepempty=false))
        end
    end
    tracks = [NamedTuple{(:setting, :leg, :lat, :lon, :aloft)}(Tuple(split(row, ",")))
              for row in rows]
    lats = [parse(Float64, row.lat) for row in tracks]
    lons = [parse(Float64, row.lon) for row in tracks]
    styles = ((first(settings[1]), :black, :solid),
        (first(settings[2]), Makie.wong_colors()[1], :dash))
    track_figure(joinpath(out_dir, "$name.png"), tracks, styles;
        titles=("(a) outbound, $(case.route), $(case.rig), " *
                "departure $(round(Int, departure)) h",
            "(b) return"),
        limits=(minimum(lons) - 3, maximum(lons) + 3, minimum(lats) - 3, maximum(lats) + 3))
end

"""
    draw_outliers(out_dir, new_dir, reference_dir, settings)

Draw by [`outlier_figure`](@ref), at the two (label, fidelity) of `settings` that made them,
every departure the gate files in `new_dir` and `reference_dir` flag as an outlier.
"""
function draw_outliers(out_dir, new_dir, reference_dir, settings)
    changes = saving_changes(read_gate(joinpath(new_dir, "gate.csv")),
        read_gate(joinpath(reference_dir, "gate.csv")))
    cases = Dict((case.ship, case.rig, String(case.route)) => case for case in gate_cases())
    for (key, found) in changes
        for (departure, _) in something(found, (; outliers=())).outliers
            outlier_figure(out_dir, cases[key], departure, settings)
        end
    end
end

"(label, study entry, colour, marker) of each setting judged against the reference"
JUDGED = (("60/15", "grid_60", Makie.wong_colors()[2], :rect),
    ("45/11 two zones", "two_zone", Makie.wong_colors()[3], :diamond),
    ("45/11 graded", "base", :black, :circle))

"""
    savings_figure(out_dir, study_dir)

The change of each rig's saving and of the kite's gap to the rotors against the 30/7.5 grid
with halved time steps, per departure, for each of [`JUDGED`](@ref), with the bounds of the
standard and the mean of each.
"""
function savings_figure(out_dir, study_dir)
    savings(name) = departure_savings(read_gate(joinpath(study_dir, name, "gate.csv")))
    reference = savings("grid_30_steps_half")
    key(rig) = ("140m", rig, "caribbean")
    change(by, rig, departure) = by[key(rig)][departure] - reference[key(rig)][departure]
    departures = sort(collect(keys(reference[key("kite")])))
    panels = (("(a) kite", 3.0, (by, d) -> change(by, "kite", d)),
        ("(b) rotors", 3.0, (by, d) -> change(by, "rotors", d)),
        ("(c) gap kite − rotors", 1.0,
            (by, d) -> change(by, "kite", d) - change(by, "rotors", d)))
    fig = Figure(size=(1000, 330))
    for (k, (title, bound, value)) in enumerate(panels)
        axis = Axis(fig[1, k]; title, xlabel="departure [days from 1 January 2017]",
            ylabel=k == 1 ? "change against reference [points]" : "")
        hspan!(axis, -bound, bound; color=(:green, 0.08))
        hlines!(axis, [-bound, bound]; color=:green, linestyle=:dot, linewidth=1.5,
            label="bound of the standard on the mean")
        hlines!(axis, [0]; color=:grey60, linewidth=0.8)
        for (label, name, color, marker) in JUDGED
            by = savings(name)
            values = [value(by, d) for d in departures]
            scatter!(axis, departures ./ 24, values; color, marker, markersize=9,
                label="$label, per departure")
            hlines!(axis, [sum(values) / length(values)]; color, linewidth=1.5,
                label="$label, mean")
        end
        k == 1 && Legend(fig[2, 1:3], axis; orientation=:horizontal, nbanks=2,
            labelsize=10, framevisible=false)
    end
    resize_to_layout!(fig)
    save(joinpath(out_dir, "savings.png"), fig)
end

"""
    seconds_figure(out_dir)

Seconds a round trip takes per rig and setting of [`TIMED`](@ref), mean over
[`TIMED_DEPARTURES`](@ref): planned and sailed edge by edge, and the extra of sailing it
live hour by hour.
"""
function seconds_figure(out_dir)
    rows = read_rows(joinpath(out_dir, "seconds.csv"))
    rigs = ("none", "kite", "rotors")
    mean_seconds(setting, rig, live) = (found = [parse(Float64, row.seconds) for row in rows
        if row.setting == setting && row.rig == rig && row.live == string(live)];
        sum(found) / length(found))
    fig = Figure(size=(900, 380))
    axis = Axis(fig[1, 1]; ylabel="seconds per round trip, one rig and departure",
        xticks=(1:length(TIMED), collect(first.(TIMED))))
    width = 0.8 / length(rigs)
    for (j, rig) in enumerate(rigs), (i, (setting, _)) in enumerate(TIMED)
        x = i + (j - (length(rigs) + 1) / 2) * width
        planning = mean_seconds(setting, rig, false)
        live = mean_seconds(setting, rig, true) - planning
        barplot!(axis, [x, x], [planning, live]; stack=[1, 2], width=width * 0.9,
            color=[Makie.wong_colors()[j], (Makie.wong_colors()[j], 0.35)],
            strokecolor=:black, strokewidth=0.5)
        text!(axis, x, planning + live; text=rig, align=(:center, :bottom), fontsize=10)
    end
    Legend(fig[1, 2], [PolyElement(color=:grey40), PolyElement(color=(:grey40, 0.35))],
        ["planning, sailed edge by edge", "extra to sail live, hour by hour"])
    save(joinpath(out_dir, "seconds.png"), fig)
end

if abspath(PROGRAM_FILE) == @__FILE__
    if ARGS[1] == "--plot"
        map_figure(ARGS[2])
        savings_figure(ARGS[2], ARGS[3])
        seconds_figure(ARGS[2])
    else
        route_figures(ARGS[1])
    end
end
