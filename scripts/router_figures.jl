# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# What the weather router saw and did on one routed passage: a data step routes it and
# saves the nodes its search reached, kept and pruned and the passage with its speeds and
# kite flights, and the figure draws them on the corridor with the weather met.

"""
    router_search_data()

Route the first departure to Guadeloupe of a 140 m e-ammonia ship with a 3200 m^2 kite on
the corridor of the run in use, recording its search, and save in the run's directory:

  - router_nodes.csv: per node, its stage, lateral, latitude and longitude [°], whether
    the search reached none of its states (0), pruned all (1) or searched on one (2), and
    its [`node_excess`](@ref);
  - router_search.csv: the departure [h] and the [`limit_excess`](@ref) of the search;
  - router_path.csv: latitude, longitude [°], hours after departure and whether the kite
    flies, at each stage of the path;
  - router_trace.csv: hours after departure, speed held [m/s], 10 m wind east and north
    [m/s] and whether the kite flies, along the path.

Errors where no passage is found.
"""
function router_search_data()
    ship = Ship(ShipDesign(:ammonia, 140.0; kite_area=3200.0), assumptions)
    table = PerformanceTable(ship, assumptions)
    hourly = first(WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions), assumptions))
    corridor, departure = first(run_corridors(:caribbean)), departures[1]
    record = SearchRecord()
    leg = route(corridor, table, weather, departure; time_cost=hourly, record)
    isnothing(leg) && error("no passage to Guadeloupe from $departure h")
    nodes = vec(CartesianIndices(corridor.water))
    write_table("router_nodes.csv"; stage=getindex.(nodes, 1),
        lateral=getindex.(nodes, 2), lat=corridor.lat[nodes], lon=corridor.lon[nodes],
        level=node_map(record)[nodes], excess=node_excess(record)[nodes])
    write_table("router_search.csv"; departure=[departure],
        limit_excess=[limit_excess(record)])
    write_table("router_path.csv"; lat=getindex.(leg.path, 1), lon=getindex.(leg.path, 2),
        hour=getindex.(leg.path, 3), flying=getindex.(leg.path, 5) .== WindShipOpt.FLYING)
    trace = LegTrace(table, leg, weather, departure)
    write_table("router_trace.csv"; hour=trace.time, trace.speed, trace.wind_east,
        trace.wind_north, trace.flying)
end

"""
    router_case()

The passage of [`router_search_data`](@ref) as its files hold it, on the corridor of the
run in use: a named tuple of `corridor`, `departure` [h], the `weather`, `excess` and
`level` stage × lateral, `limit_excess` [%], `path`, a vector of named tuples of `lat`,
`lon` [°], `hour` and `flying`, and `trace`, of `time` [h], `speed` [m/s], `wind_east`,
`wind_north` [m/s] and `flying`. Errors where the nodes are not those of the corridor.
"""
function router_case()
    corridor = first(run_corridors(:caribbean))
    nodes = read_table(data_file("router_nodes.csv"))
    check_router_nodes(nodes, corridor)
    at = CartesianIndex.(Int.(nodes["stage"]), Int.(nodes["lateral"]))
    excess, level = fill(NaN, size(corridor.water)), zeros(Int, size(corridor.water))
    excess[at], level[at] = nodes["excess"], nodes["level"]
    search = read_table(data_file("router_search.csv"))
    stops = read_table(data_file("router_path.csv"))
    path = [(; lat, lon, hour, flying=flying == 1)
            for (lat, lon, hour, flying) in
                zip(stops["lat"], stops["lon"], stops["hour"], stops["flying"])]
    samples = read_table(data_file("router_trace.csv"))
    trace = (; time=samples["hour"], speed=samples["speed"],
        wind_east=samples["wind_east"], wind_north=samples["wind_north"],
        flying=samples["flying"] .== 1)
    return (; corridor, departure=only(search["departure"]), weather, excess, level,
        limit_excess=only(search["limit_excess"]), path, trace)
end

"""
    check_router_nodes(nodes, corridor)

Error unless the columns `nodes` of router_nodes.csv hold every node of `corridor` once,
each at its latitude and longitude [°] to the four decimals saved.
"""
function check_router_nodes(nodes, corridor)
    at = CartesianIndex.(Int.(nodes["stage"]), Int.(nodes["lateral"]))
    sort(at) == vec(CartesianIndices(corridor.water)) ||
        error("router_nodes.csv holds other nodes than the run's corridor")
    moved = max(maximum(abs, nodes["lat"] .- corridor.lat[at]),
        maximum(abs, nodes["lon"] .- corridor.lon[at]))
    moved <= 1e-4 ||
        error("router_nodes.csv places nodes up to $(moved)° from the run's corridor")
end

"""
    path_laterals(corridor, path)

Lateral node of `corridor` at each stage of `path`.
"""
path_laterals(corridor, path) =
    [WindShipOpt.nearest_lateral(corridor, stage, point.lat, point.lon)
     for (stage, point) in enumerate(path)]

"""
    node_excess(record)

Least objective of a passage through each node of the search of `record`, as it estimated
it, in percent above the objective of the path it found, stage × lateral; `NaN` where no
state was reached or none has an estimate onward.
"""
function node_excess(record)
    through = through_node(record)
    excess = 100 .* (through ./ record.found.objective .- 1)
    excess[.!isfinite.(through)] .= NaN
    return excess
end

"limit of a search in percent above the objective of the path it found"
limit_excess(record) = 100 * (record.limit / record.found.objective - 1)

"""
    node_map(record)

Whether the states of `record` at each node held none (0), only states the search pruned
(1) or a state it searched on (2), stage × lateral.
"""
function node_map(record)
    dims = (2, 3)
    kept = any(kept_states(record); dims)
    reached = any(isfinite.(record.cost); dims)
    return permutedims(dropdims(reached .+ kept; dims))
end

"""
    draw_search_map!(axis, case; colorrange)

The water nodes of the corridor of `case` on a longitude-latitude `axis`, coloured by
[`node_excess`](@ref) within `colorrange` where the search kept a state, dark where it kept
one with no estimate onward, open where it pruned all, faint where it reached none; the
edges allowed from each node of the passage; the 10 m wind at a share of the nodes when the
passage reached their stage; and the passage, in the kite's colour where the kite flies.
Returns the plot of the coloured nodes.
"""
function draw_search_map!(axis, case; colorrange)
    (; corridor, excess, level, path) = case
    water = findall(corridor.water)
    unreached, pruned, kept = [filter(index -> level[index] == value, water)
                               for value in 0:2]
    dot = node_dot(corridor)
    scatter!(axis, node_points(corridor, unreached); color=unreached_shade,
        markersize=unreached_dot * dot, markerspace=:data)
    scatter!(axis, node_points(corridor, pruned); color=:transparent, strokecolor=:gray45,
        strokewidth=pt(0.3), markersize=dot, markerspace=:data)
    nodes = scatter!(axis, node_points(corridor, kept); color=excess[kept],
        colormap=:viridis, colorrange, nan_color=no_estimate_shade, markersize=dot,
        markerspace=:data)
    draw_edge_fans!(axis, corridor, path)
    draw_met_wind!(axis, case)
    track = track_points(path)
    lines!(axis, track; color=:black, linewidth=line_width)
    for i in 2:length(track)
        path[i].flying && lines!(axis, track[(i - 1):i]; color=palette[1],
            linewidth=2line_width)
    end
    return nodes
end

"longitude and latitude [deg] of the nodes of `corridor` at `indices`, as points"
node_points(corridor, indices) = Point2f.(corridor.lon[indices], corridor.lat[indices])

"""
    node_dot(corridor)

Diameter [deg] of the nodes of `corridor` on a longitude-latitude map: 0.8 of the spacing
of its rows in degrees of latitude, so at most that share of their spacing on the map.
"""
node_dot(corridor) = 0.8 * corridor.lateral_spacing / 60NAUTICAL_MILE

"""
    draw_edge_fans!(axis, corridor, path)

The edges `corridor` allows out of each node of `path`.
"""
function draw_edge_fans!(axis, corridor, path)
    segments = Point2f[]
    for (stage, lateral) in enumerate(path_laterals(corridor, path)[1:(end - 1)])
        for step in 1:WindShipOpt.step_count(corridor)
            isnan(corridor.edge_course[stage, lateral, step]) && continue
            next = WindShipOpt.next_lateral(corridor, lateral, step)
            append!(segments, node_points(corridor,
                [CartesianIndex(stage, lateral), CartesianIndex(stage + 1, next)]))
        end
    end
    linesegments!(axis, segments; edge_style...)
end

"""
    draw_met_wind!(axis, case; spacing=240)

10 m wind arrows at the water nodes of the corridor of `case` about `spacing` [nmi] apart,
each at the hour the passage reached its stage, those whose tip stays within the limits of
`axis`.
"""
function draw_met_wind!(axis, case; spacing=240)
    (; corridor, path, departure, weather) = case
    along = corridor.along_centre ./ NAUTICAL_MILE
    lateral_stride = max(1, round(Int, spacing * NAUTICAL_MILE / corridor.lateral_spacing))
    stages = [1]
    for stage in eachindex(along)
        along[stage] - along[last(stages)] >= spacing && push!(stages, stage)
    end
    points, vectors = Point2f[], Vec2f[]
    for stage in stages, lateral in 1:lateral_stride:size(corridor.lat, 2)
        corridor.water[stage, lateral] || continue
        lat, lon = corridor.lat[stage, lateral], corridor.lon[stage, lateral]
        push!(points, Point2f(lon, lat))
        push!(vectors, Vec2f(wind(weather, lat, lon, departure + path[stage].hour)...))
    end
    vectors .*= 0.3f0
    west, east, south, north = axis.limits[]
    inside = [west <= tip[1] <= east && south <= tip[2] <= north
              for tip in points .+ vectors]
    arrows2d!(axis, points[inside], vectors[inside]; color=style_colour("wind"),
        shaftwidth=rule_width, minshaftlength=0)
end

"""
    draw_passage!(speed_axis, wind_axis, case)

Speed held and 10 m wind speed along the passage of `case` by days since departure, with
the hours the kite flies shaded.
"""
function draw_passage!(speed_axis, wind_axis, case)
    (; trace) = case
    days = trace.time ./ 24
    for axis in (speed_axis, wind_axis)
        draw_flights!(axis, days, trace.flying)
    end
    stairs!(speed_axis, days, trace.speed ./ KNOT; step=:post, color=:black)
    stairs!(wind_axis, days, hypot.(trace.wind_east, trace.wind_north); step=:post,
        color=:black)
end

"""
    draw_flights!(axis, days, flying)

Shade the spans of `days` in which `flying` holds, each sample standing until the next.
"""
function draw_flights!(axis, days, flying)
    starts, stops = Float64[], Float64[]
    for i in 1:(length(days) - 1)
        flying[i] || continue
        if i > 1 && flying[i - 1]
            stops[end] = days[i + 1]
        else
            push!(starts, days[i])
            push!(stops, days[i + 1])
        end
    end
    isempty(starts) || vspan!(axis, starts, stops; color=flight_shade)
end

"line style of the edges of a corridor"
edge_style = (; color=(:black, 0.45), linewidth=style_size("dimension"))

"colour of the nodes a search kept with no estimate onward"
no_estimate_shade = :gray35

"colour of a node the search did not reach"
unreached_shade = :gray55

"diameter of a node the search did not reach, as a share of that of the others"
unreached_dot = 0.5

"colour of the hours a kite flies along a passage"
flight_shade = (palette[1], 0.25)

"""
    router_panels!(positions, case; limits, colorrange, titles)

Axes at the grid `positions` of a figure, a named tuple of `map`, `speed` and `wind`, with
the `titles` named alike; on them land and the [`draw_search_map!`](@ref) of `case` within
`limits` (west, east, south, north) [deg] and `colorrange`, and its
[`draw_passage!`](@ref). Returns the plot of the coloured nodes.
"""
function router_panels!(positions, case; limits, colorrange, titles)
    map_axis = Axis(positions.map; aspect=DataAspect(), limits, title=titles.map,
        xlabel="longitude [°]", ylabel="latitude [°]")
    speed_axis = Axis(positions.speed; title=titles.speed, ylabel="speed [kn]",
        xticklabelsvisible=false)
    wind_axis = Axis(positions.wind; title=titles.wind, xlabel="days since departure",
        ylabel="10 m wind [m/s]")
    linkxaxes!(speed_axis, wind_axis)
    draw_land!(map_axis, mask; lons=limits[1]:0.25:limits[2],
        lats=limits[3]:0.25:limits[4])
    nodes = draw_search_map!(map_axis, case; colorrange)
    draw_passage!(speed_axis, wind_axis, case)
    return nodes
end

"label of the colour bar of [`node_excess`](@ref)"
excess_label = "best passage through node, % above the one found"

"""
    excess_range(case)

Colour range of the [`node_excess`](@ref) of `case` [%]: from the least, or zero, to the
limit of its search, or the greatest excess of a search over all states.
"""
function excess_range(case)
    excess = filter(isfinite, case.excess)
    top = isfinite(case.limit_excess) ? case.limit_excess : maximum(excess)
    return (min(0, minimum(excess)), top)
end

"""
    router_legend_entries()

Legend entries and labels of the marks of [`router_panels!`](@ref), the nodes enlarged
from the map but in its proportions.
"""
function router_legend_entries()
    dot = pt(3)
    entries = [LineElement(color=:black, linewidth=line_width),
        [PolyElement(color=flight_shade),
            LineElement(color=palette[1], linewidth=2line_width)],
        LineElement(; edge_style...),
        MarkerElement(marker=:circle, color=no_estimate_shade, markersize=dot),
        MarkerElement(marker=:circle, color=:transparent, strokecolor=:gray45,
            strokewidth=pt(0.3), markersize=dot),
        MarkerElement(marker=:circle, color=unreached_shade,
            markersize=unreached_dot * dot)]
    labels = ["passage", "kite flying", "edges allowed", "node kept, no estimate",
        "node pruned", "node not reached"]
    return entries, labels
end

"""
    map_limits(corridor; pad=1)

Longitude and latitude limits (west, east, south, north) [deg] around the water nodes of
`corridor`, `pad` [deg] wider on each side.
"""
function map_limits(corridor; pad=1)
    lons, lats = corridor.lon[corridor.water], corridor.lat[corridor.water]
    return (floor(minimum(lons)) - pad, ceil(maximum(lons)) + pad,
        floor(minimum(lats)) - pad, ceil(maximum(lats)) + pad)
end

"""
    router_figure()

The [`router_panels!`](@ref) of the [`router_case`](@ref): its map across the page, with
speed and wind beneath it on one time axis.
"""
function router_figure()
    case = router_case()
    limits = map_limits(case.corridor)
    west, east, south, north = limits
    figure = Figure(size=(page_width, 560))
    time_panels = GridLayout(figure[2, 1:2])
    nodes = router_panels!((; map=figure[1, 1], speed=time_panels[1, 1],
            wind=time_panels[2, 1]), case;
        limits, colorrange=excess_range(case),
        titles=(; map="(a) nodes searched and the passage", speed="(b) speed held",
            wind="(c) wind met"))
    Colorbar(figure[1, 2], nodes; label=excess_label)
    Legend(time_panels[1:2, 2], router_legend_entries()...)
    rowsize!(figure.layout, 1, Aspect(1, (north - south) / (east - west)))
    save_figure("router", figure)
end
