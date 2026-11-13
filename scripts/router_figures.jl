# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Figures of what the weather router saw and did on real routed passages: the corridor and
# the nodes its search kept, the weather met, the states searched and pruned and the
# passage with its speeds and kite flights.

"""
    routed_case(design, name, departure; scale, weather=weather, label="")

The outbound passage of `design` on route `name` leaving at `departure` [h], routed in
`weather` on the corridor at `scale` (8 for a draft, 1 for a final run), as a named tuple
of `label`, `corridor`, `departure`, `weather`, the [`Leg`](@ref) `leg`, its
[`SearchRecord`](@ref) `record`, its [`LegTrace`](@ref) `trace` and the `seconds` it took to
route.
"""
function routed_case(design, name, departure; scale, weather=weather, label="")
    ship = Ship(design, assumptions)
    table = PerformanceTable(ship, assumptions)
    hourly = first(WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions), assumptions))
    corridor = first(corridors(name, scale))
    record = SearchRecord()
    seconds = @elapsed leg = route(corridor, table, weather, departure; time_cost=hourly,
        record)
    trace = LegTrace(table, leg, weather, departure)
    return (; label, corridor, departure, weather, leg, record, trace, seconds)
end

"""
    path_laterals(corridor, leg)

Lateral node of `corridor` at each stage of the path of `leg`.
"""
path_laterals(corridor, leg) =
    [WindShipOpt.nearest_lateral(corridor, stage, point[1], point[2])
     for (stage, point) in enumerate(leg.path)]

"""
    node_excess(case)

Least objective of a passage through each water node of the corridor of `case`, as the
search estimated it, in percent above the objective of the path it found, stage × lateral;
`NaN` where no state was reached or none has an estimate onward.
"""
function node_excess(case)
    through = through_node(case.record)
    excess = 100 .* (through ./ case.record.found.objective .- 1)
    excess[.!isfinite.(through)] .= NaN
    return excess
end

"limit of a search in percent above the objective of the path it found"
limit_excess(record) = 100 * (record.limit / record.found.objective - 1)

"""
    search_levels(record, dims)

Whether the states of `record` grouped over `dims` held none (0), only states the search
pruned (1) or a state it searched on (2), stage last.
"""
function search_levels(record, dims)
    kept = any(kept_states(record); dims)
    reached = any(isfinite.(record.cost); dims)
    return permutedims(dropdims(reached .+ kept; dims))
end

"[`search_levels`](@ref) of each node of `record`, stage × lateral"
node_map(record) = search_levels(record, (2, 3))

"""
    draw_search_map!(axis, case; colorrange)

The water nodes of the corridor of `case` on a longitude-latitude `axis`, coloured by [`node_excess`](@ref) within `colorrange` where the
search kept a state, dark where it kept one with no estimate onward, open where it pruned
all, faint where it reached none; the edges allowed from each node of the passage; the
10 m wind at a share of the nodes when the passage reached their stage; and the passage, in
the kite's colour where the kite flies. Returns the plot of the coloured nodes.
"""
function draw_search_map!(axis, case; colorrange)
    (; corridor, leg, record) = case
    excess = node_excess(case)
    level = node_map(record)
    water = findall(corridor.water)
    unreached, pruned, kept = [filter(index -> level[index] == value, water)
                               for value in 0:2]
    dot = node_dot(corridor)
    scatter!(axis, node_points(corridor, unreached); color=:gray80, markersize=0.5dot)
    scatter!(axis, node_points(corridor, pruned); color=:transparent, strokecolor=:gray45,
        strokewidth=pt(0.3), markersize=dot)
    nodes = scatter!(axis, node_points(corridor, kept); color=excess[kept],
        colormap=:viridis, colorrange, nan_color=no_estimate_shade, markersize=dot)
    draw_edge_fans!(axis, corridor, leg)
    draw_met_wind!(axis, case)
    track = track_points(leg.path)
    lines!(axis, track; color=:black, linewidth=line_width)
    flying = [point[5] == WindShipOpt.FLYING for point in leg.path]
    for i in 2:length(track)
        flying[i] && lines!(axis, track[(i - 1):i]; color=palette[1],
            linewidth=2line_width)
    end
    return nodes
end

"longitude and latitude [deg] of the nodes of `corridor` at `indices`, as points"
node_points(corridor, indices) = Point2f.(corridor.lon[indices], corridor.lat[indices])

"marker size of the nodes of `corridor` on a map, smaller on a finer grid"
node_dot(corridor) = pt(clamp(2.5 * corridor.lateral_spacing / 60NAUTICAL_MILE, 1.6, 4))

"""
    draw_edge_fans!(axis, corridor, leg)

The edges `corridor` allows out of each node of the path of `leg`.
"""
function draw_edge_fans!(axis, corridor, leg)
    segments = Point2f[]
    for (stage, lateral) in enumerate(path_laterals(corridor, leg)[1:(end - 1)])
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
each at the hour the passage reached its stage.
"""
function draw_met_wind!(axis, case; spacing=240)
    (; corridor, leg, departure, weather) = case
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
        push!(vectors, Vec2f(wind(weather, lat, lon, departure + leg.path[stage][3])...))
    end
    arrows2d!(axis, points, vectors .* 0.3f0; color=(:black, 0.55), shaftwidth=rule_width,
        minshaftlength=0)
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
    excess_range(cases)

Colour range of the [`node_excess`](@ref) of `cases` [%]: from the least, or zero, to the
widest limit of their searches, or the greatest excess of a search over all states.
"""
function excess_range(cases)
    excesses = [filter(isfinite, node_excess(case)) for case in cases]
    tops = [isfinite(case.record.limit) ? limit_excess(case.record) : maximum(excess)
            for (case, excess) in zip(cases, excesses)]
    return (min(0, minimum(minimum.(excesses))), maximum(tops))
end

"""
    router_legend_entries()

Legend entries and labels of the marks of [`router_panels!`](@ref).
"""
function router_legend_entries()
    entries = [LineElement(color=:black, linewidth=line_width),
        [PolyElement(color=flight_shade),
            LineElement(color=palette[1], linewidth=2line_width)],
        LineElement(; edge_style...),
        MarkerElement(marker=:circle, color=no_estimate_shade, markersize=pt(3)),
        MarkerElement(marker=:circle, color=:transparent, strokecolor=:gray45,
            strokewidth=pt(0.3), markersize=pt(3)),
        MarkerElement(marker=:circle, color=:gray80, markersize=pt(1.5))]
    labels = ["passage", "kite flying", "edges allowed", "node kept, no estimate",
        "node pruned", "node not reached"]
    return entries, labels
end

"""
    map_limits(cases; pad=1)

Longitude and latitude limits (west, east, south, north) [deg] around the water nodes of
the corridors of `cases`, `pad` [deg] wider on each side.
"""
function map_limits(cases; pad=1)
    lons = reduce(vcat, [case.corridor.lon[case.corridor.water] for case in cases])
    lats = reduce(vcat, [case.corridor.lat[case.corridor.water] for case in cases])
    return (floor(minimum(lons)) - pad, ceil(maximum(lons)) + pad,
        floor(minimum(lats)) - pad, ceil(maximum(lats)) + pad)
end

"""
    router_figure()

The [`router_panels!`](@ref) of one winter passage to Guadeloupe of a
140 m e-ammonia ship with a 3200 m^2 kite, on the corridor of the run in use.
"""
function router_figure()
    case = routed_case(ShipDesign(:ammonia, 140.0; kite_area=3200.0), :caribbean,
        departures[1]; scale=run_settings().corridor_scale)
    figure = Figure(size=(page_width, 280))
    nodes = router_panels!((; map=figure[1:2, 1], speed=figure[1, 3],
            wind=figure[2, 3]), case;
        limits=map_limits([case]), colorrange=excess_range([case]),
        titles=(; map="(a) nodes searched and the passage", speed="(b) speed held",
            wind="(c) wind met"))
    Colorbar(figure[1:2, 2], nodes; label=excess_label)
    Legend(figure[3, 1:3], router_legend_entries()...;
        orientation=:horizontal, nbanks=2)
    colsize!(figure.layout, 1, Auto(1.25))
    save_figure("router", figure)
end
