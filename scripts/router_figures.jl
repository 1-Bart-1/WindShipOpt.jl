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

"longitude and latitude [deg] of the nodes of `corridor` at `indices`, as points"
node_points(corridor, indices) = Point2f.(corridor.lon[indices], corridor.lat[indices])

"""
    node_dot(corridor)

Diameter [deg] of the nodes of `corridor` on a longitude-latitude map: 0.8 of the spacing
of its rows in degrees of latitude, so at most that share of their spacing on the map.
"""
node_dot(corridor) = 0.8 * corridor.lateral_spacing / 60NAUTICAL_MILE

"""
    stage_dot(corridor)

Diameter [deg] of the nodes of `corridor` on a map too small to tell them apart: 0.8 of the
median spacing of its stages in degrees of latitude, so the nodes join into one field.
"""
stage_dot(corridor) = 0.8 * median(diff(corridor.along_centre)) / 60NAUTICAL_MILE

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
    draw_met_wind!(axis, case; spacing)

Arrows of the wind 10 m above the sea at the water nodes of the corridor of `case` about
`spacing` [nmi] apart, each at the hour the passage reached its stage and at the
[`met_wind_scale`](@ref) of `spacing`, those whose tip stays within the limits of `axis`.
"""
function draw_met_wind!(axis, case; spacing)
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
    vectors .*= Float32(met_wind_scale(spacing))
    inside = [within(axis.limits[], tip...) for tip in points .+ vectors]
    arrows2d!(axis, points[inside], vectors[inside]; met_wind_style...)
end

"style of the arrows of [`draw_met_wind!`](@ref) and of their key"
met_wind_style = (; color=style_colour("wind"), shaftwidth=rule_width, minshaftlength=0)

"scale [deg per m/s] of wind arrows `spacing` [nmi] apart: 15 m/s as long as `spacing`"
met_wind_scale(spacing) = spacing / 60 / 15

"spacing [nmi] of the wind arrows in a zoom into `window` (west, east, south, north) [deg]"
met_wind_spacing(window) = 6 * (window[2] - window[1])

"""
    draw_passage!(speed_axis, wind_axis, case; window_days)

Speed held and 10 m wind speed along the passage of `case` by days since departure, with
the hours the kite flies shaded and the first and last of `window_days` marked.
"""
function draw_passage!(speed_axis, wind_axis, case; window_days)
    (; trace) = case
    days = trace.time ./ 24
    for axis in (speed_axis, wind_axis)
        draw_flights!(axis, days, trace.flying)
        vlines!(axis, collect(window_days); color=window_colour, linewidth=line_width)
        xlims!(axis, 0, last(days))
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

"colour of the frame of the zoomed window and of its days on the time axis"
window_colour = style_colour("accent")

"""
    draw_search_map!(axis, case; colorrange, dot=node_dot(case.corridor))

The water nodes of the corridor of `case` within the limits of a longitude-latitude `axis`,
`dot` [deg] across, coloured by [`node_excess`](@ref) within `colorrange` on a square-root
scale where the search kept a state, dark where it kept one with no estimate onward, open
where it pruned all, faint where it reached none, and over them the passage, in the kite's
colour where the kite flies. Returns the plot of the coloured nodes and whether any
`no_estimate`, `pruned` or `unreached` node is drawn, as a named tuple.
"""
function draw_search_map!(axis, case; colorrange, dot=node_dot(case.corridor))
    (; corridor, excess, level, path) = case
    water = filter(index -> within(axis.limits[], corridor.lon[index], corridor.lat[index]),
        findall(corridor.water))
    unreached, pruned, kept = [filter(index -> level[index] == value, water)
                               for value in 0:2]
    scatter!(axis, node_points(corridor, unreached); color=unreached_shade,
        markersize=unreached_dot * dot, markerspace=:data)
    scatter!(axis, node_points(corridor, pruned); color=:transparent, strokecolor=:gray45,
        strokewidth=pt(0.3), markersize=dot, markerspace=:data)
    nodes = scatter!(axis, node_points(corridor, kept); color=excess[kept],
        colormap=:viridis, colorscale=sqrt, colorrange, nan_color=no_estimate_shade,
        markersize=dot,
        markerspace=:data)
    draw_track!(axis, path)
    drawn = (; no_estimate=any(isnan, excess[kept]), pruned=!isempty(pruned),
        unreached=!isempty(unreached))
    return nodes, drawn
end

"""
    draw_track!(axis, path)

The track of `path`, twice as wide in the kite's colour where it flies.
"""
function draw_track!(axis, path)
    track = track_points(path)
    lines!(axis, track; color=:black, linewidth=line_width)
    for i in 2:length(track)
        path[i].flying && lines!(axis, track[(i - 1):i]; color=palette[1],
            linewidth=2line_width)
    end
end

"""
    map_axis(position, limits, title)

A longitude-latitude axis at `position` within `limits` (west, east, south, north) [deg],
with land drawn.
"""
function map_axis(position, limits, title)
    axis = Axis(position; aspect=DataAspect(), limits, title, xlabel="longitude [°]",
        ylabel="latitude [°]")
    draw_land!(axis, mask; lons=limits[1]:0.25:limits[2], lats=limits[3]:0.25:limits[4])
    return axis
end

"""
    router_panels!(positions, case; window, colorrange, titles)

Axes at the grid `positions` of a figure, a named tuple of `overview`, `zoom`, `speed` and
`wind`, with the `titles` named alike: the [`draw_search_map!`](@ref) of `case` over its
whole corridor with the frame of `window` (west, east, south, north) [deg], and within
`window` with the edges and the wind met, both within `colorrange`; and its
[`draw_passage!`](@ref) with the [`window_days`](@ref) marked. Returns the plot of the
coloured nodes, what both maps drew, as [`draw_search_map!`](@ref) names it, and the zoomed
axis.
"""
function router_panels!(positions, case; window, colorrange, titles)
    whole = search_limits(case)
    overview = map_axis(positions.overview, whole, titles.overview)
    overview.xticks = WilkinsonTicks(4)
    nodes, overview_drawn = draw_search_map!(overview, case; colorrange,
        dot=stage_dot(case.corridor))
    west, east, south, north = window
    poly!(overview, Rect2f(west, south, east - west, north - south); color=:transparent,
        strokecolor=window_colour, strokewidth=line_width)
    zoom = map_axis(positions.zoom, window, titles.zoom)
    zoom.yticks = WilkinsonTicks(4; Q=[(1, 1.0), (2, 1.0), (5, 1.0)])
    zoom.leftspinecolor = zoom.rightspinecolor = zoom.topspinecolor =
        zoom.bottomspinecolor = window_colour
    draw_edge_fans!(zoom, case.corridor, case.path)
    _, zoom_drawn = draw_search_map!(zoom, case; colorrange)
    draw_met_wind!(zoom, case; spacing=met_wind_spacing(window))
    speed_axis = Axis(positions.speed; title=titles.speed, ylabel="speed [kn]",
        xticklabelsvisible=false, yticks=WilkinsonTicks(3))
    wind_axis = Axis(positions.wind; title=titles.wind, xlabel="days since departure",
        ylabel="wind [m/s]", yticks=WilkinsonTicks(3))
    linkxaxes!(speed_axis, wind_axis)
    draw_passage!(speed_axis, wind_axis, case; window_days=window_days(case.path, window))
    drawn = map(|, overview_drawn, zoom_drawn)
    return nodes, drawn, zoom
end

"""
    met_wind_key!(position, scale)

A borderless axis at the grid `position`, at its left, holding the [`wind_key!`](@ref)
of a 10 m/s wind at the `scale` [deg per m/s] of [`draw_met_wind!`](@ref), 0.5° high; its
width and height are yet to be set to its limits at the scale of the map it keys.
"""
function met_wind_key!(position, scale)
    speed, height = 10, 0.5
    key = Axis(position; tellwidth=false, halign=:left,
        limits=(-0.05, speed * scale + 2.8height + 0.05, -0.05, height + 0.05))
    hidedecorations!(key)
    hidespines!(key)
    wind_key!(key, Point2f(0, 0), speed, scale, height; style=met_wind_style)
    return key
end

"label of the colour bar of [`node_excess`](@ref)"
excess_label = "best passage through node,\n% above the one found"

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
    router_legend_entries(drawn)

Legend entries and labels of the marks of [`router_panels!`](@ref), of the kinds of node
only those `drawn` names as drawn, the nodes enlarged from the map but in its proportions.
"""
function router_legend_entries(drawn)
    dot = pt(3)
    entries = [LineElement(color=:black, linewidth=line_width),
        [PolyElement(color=flight_shade),
            LineElement(color=palette[1], linewidth=2line_width)],
        LineElement(; edge_style...),
        LineElement(color=window_colour, linewidth=line_width),
        MarkerElement(marker='→', color=style_colour("wind"), markersize=pt(9)),
        MarkerElement(marker=:circle, color=no_estimate_shade, markersize=dot),
        MarkerElement(marker=:circle, color=:transparent, strokecolor=:gray45,
            strokewidth=pt(0.3), markersize=dot),
        MarkerElement(marker=:circle, color=unreached_shade,
            markersize=unreached_dot * dot)]
    labels = ["passage", "kite flying", "edges allowed", "zoomed window",
        "wind at 10 m height, as met", "node kept, no estimate", "node pruned",
        "node not reached"]
    shown = [true, true, true, true, true, drawn.no_estimate, drawn.pruned,
        drawn.unreached]
    return entries[shown], labels[shown]
end

"""
    search_limits(case; pad=1)

Longitude and latitude limits (west, east, south, north) [deg] around the nodes of the
corridor of `case` its search reached, `pad` [deg] wider on each side.
"""
function search_limits(case; pad=1)
    (; corridor, level) = case
    reached = findall(level .> 0)
    lons, lats = corridor.lon[reached], corridor.lat[reached]
    return (floor(minimum(lons)) - pad, ceil(maximum(lons)) + pad,
        floor(minimum(lats)) - pad, ceil(maximum(lats)) + pad)
end

"""
    window_days(path, window)

First and last days since departure at which `path` stops within `window` (west, east,
south, north) [deg].
"""
function window_days(path, window)
    inside = filter(stop -> within(window, stop.lon, stop.lat), path)
    return extrema(stop.hour / 24 for stop in inside)
end

"whether longitude `lon` and latitude `lat` [deg] lie within `window` (west, east, south,
north) [deg]"
within(window, lon, lat) = window[1] <= lon <= window[2] && window[3] <= lat <= window[4]

"height over width of `limits` (west, east, south, north) [deg]"
map_height(limits) = (limits[4] - limits[3]) / (limits[2] - limits[1])

"""
    router_figure(; window=(-59, -41, 24, 31))

The [`router_panels!`](@ref) of the [`router_case`](@ref): the overview of its search beside
the legend, the key of the wind arrows and the colour bar, the zoom into `window` (west,
east, south, north) [deg] across the page, and speed and wind beneath them on one time axis.
"""
function router_figure(; window=(-59, -41, 24, 31))
    case = router_case()
    colorrange = excess_range(case)
    figure = Figure(size=(page_width, 605))
    top = GridLayout(figure[1, 1])
    nodes, drawn, zoom = router_panels!((; overview=top[1:3, 1], zoom=figure[2, 1],
            speed=figure[3, 1], wind=figure[4, 1]), case;
        window, colorrange,
        titles=(; overview="(a) the corridor searched",
            zoom="(b) its nodes, edges and wind",
            speed="(c) speed held", wind="(d) wind met at 10 m height"))
    Legend(top[1, 2], router_legend_entries(drawn)...; valign=:top)
    key = met_wind_key!(top[2, 2], met_wind_scale(met_wind_spacing(window)))
    Colorbar(top[3, 2], nodes; label=excess_label, vertical=false, flipaxis=false,
        valign=:bottom, ticks=filter(<=(colorrange[2]), [0, 1, 3, 6, 10, 15, 20, 30, 50]))
    rowgap!(top, 2, pt(3))
    rowsize!(figure.layout, 1, Fixed(130))
    rowsize!(figure.layout, 2, Aspect(1, map_height(window)))
    foreach(row -> rowsize!(figure.layout, row, Fixed(42)), 3:4)
    Makie.colorbuffer(figure)
    map_scale = widths(zoom.scene.viewport[])[1] / widths(zoom.finallimits[])[1]
    west, east, south, north = key.limits[]
    key.width, key.height = (east - west, north - south) .* map_scale
    save_figure("router", figure)
end
