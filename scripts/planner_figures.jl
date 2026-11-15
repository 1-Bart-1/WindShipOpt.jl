# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# What the planner does on the development case, as figures: its planning grid and routes on
# one passage, each rig's saving against a finer grid per departure, and the time a round
# trip takes to plan and to sail live.
#
#   julia +1.12 --project=scripts -t auto scripts/planner_figures.jl <out_dir>
#   julia +1.12 --project=scripts scripts/planner_figures.jl --plot <out_dir> <study_dir>
#
# The first routes into <out_dir>; the second draws from it and from the gate files of the
# grid study in <study_dir> into <out_dir>/*.png.
using CairoMakie
include(joinpath(@__DIR__, "router_grid_study.jl"))
include(joinpath(@__DIR__, "map_plotting.jl"))

"departure of the passage drawn on the map [h]"
MAP_DEPARTURE = 10080.0

"departures timed [h]"
TIMED_DEPARTURES = (0.0, 10080.0, 20160.0)

"(label, study entry) of the settings timed: the old full-corridor search, 60/15 and 45/11"
TIMED = (("full corridor, 240/60", "whole_240"), ("60/15", "grid_60"), ("45/11", "base"))

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
        corridors(:caribbean, fidelity.scale)..., weather, departure, port, hourly, Inf,
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
    route_figures(out_dir)

Route what the figures draw into `out_dir`: the planning grid, the kite's tracks at
[`MAP_DEPARTURE`](@ref) on 60/15, on 45/11 and on the reference grid, and the seconds of
each round trip of [`TIMED_DEPARTURES`](@ref) at each of [`TIMED`](@ref), planned and sailed
edge by edge and sailed live.
"""
function route_figures(out_dir)
    mkpath(out_dir)
    kite = only(filter(case -> case.rig == "kite", development_cases()))
    Ship(kite.design, assumptions)
    open(joinpath(out_dir, "tracks.csv"), "w") do io
        println(io, "setting,leg,lat,lon,aloft")
        for (label, name) in (("60/15", "grid_60"), ("45/11", "base"),
            ("30/7.5, steps halved", "grid_30_steps_half"))
            fidelity = STUDY[name]
            WindShipOpt.with_router_settings(fidelity.settings) do
                trip, _ = planned_trip(kite, MAP_DEPARTURE, fidelity)
                write_track(io, label, trip)
                name == "base" && write_planning_grid(out_dir, trip)
            end
        end
    end
    open(joinpath(out_dir, "seconds.csv"), "w") do io
        println(io, "setting,rig,departure,live,seconds")
        for (label, name) in TIMED
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
    end
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
    ("45/11", :black, :solid), ("30/7.5, steps halved", Makie.wong_colors()[1], :dash))

"""
    map_figure(out_dir)

The outbound and return passages of the kite at [`MAP_DEPARTURE`](@ref): the corridor, the
nodes the first plan keeps near the ship and far from it, and the tracks on each grid.
"""
function map_figure(out_dir)
    tracks = read_rows(joinpath(out_dir, "tracks.csv"))
    fig = Figure(size=(1000, 430))
    for (k, (leg, title)) in enumerate((("out", "(a) Ushant to Guadeloupe"),
        ("back", "(b) Guadeloupe to Ushant")))
        axis = Axis(fig[1, k]; title, aspect=DataAspect(), xlabel="longitude [°]",
            ylabel=k == 1 ? "latitude [°]" : "", limits=(-66, 0, 10, 52))
        draw_land!(axis, mask)
        grid(part) = row_points(read_rows(joinpath(out_dir, "grid_$(leg)_$(part).csv")))
        scatter!(axis, grid("all"); color=(:grey, 0.25), markersize=1.2,
            label="corridor, 45/11 nmi")
        scatter!(axis, grid("far"); color=:grey35, markersize=3.5,
            label="far nodes of the first plan")
        scatter!(axis, grid("near"); color=:darkorange, markersize=2.5,
            label="near nodes of the first plan")
        for (label, color, linestyle) in TRACK_STYLES
            points = row_points(filter(row -> row.setting == label && row.leg == leg,
                tracks))
            lines!(axis, points; color, linestyle, linewidth=2, label="track, $label")
        end
        k == 1 && axislegend(axis; position=:lb, framevisible=true, backgroundcolor=:white,
            labelsize=11, markersize=8)
    end
    save(joinpath(out_dir, "planning_grid.png"), fig)
end

"(label, study entry, colour, marker) of each setting judged against the reference"
JUDGED = (("60/15", "grid_60", Makie.wong_colors()[2], :rect),
    ("45/11", "base", :black, :circle))

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
        axis = Axis(fig[1, k]; title, xlabel="departure [day of year]",
            ylabel=k == 1 ? "change against reference [points]" : "",
            xticks=0:30:360)
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
        k == 1 && axislegend(axis; position=:lb, labelsize=10, backgroundcolor=:white)
    end
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
    fig = Figure(size=(800, 380))
    axis = Axis(fig[1, 1]; ylabel="seconds per round trip, one rig and departure",
        xticks=(1:length(TIMED), first.(TIMED)))
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
