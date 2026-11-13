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

"[`search_levels`](@ref) of each time bin of each stage of `record`, stage × bin"
state_map(record) = search_levels(record, (1, 3))

"[`search_levels`](@ref) of each node of `record`, stage × lateral"
node_map(record) = search_levels(record, (2, 3))

"""
    draw_search_map!(axis, case; colorrange, rows=false)

The water nodes of the corridor of `case` on a longitude-latitude `axis`, with its rows
drawn where `rows` holds, coloured by [`node_excess`](@ref) within `colorrange` where the
search kept a state, dark where it kept one with no estimate onward, open where it pruned
all, faint where it reached none; the edges allowed from each node of the passage; the
10 m wind at a share of the nodes when the passage reached their stage; and the passage, in
the kite's colour where the kite flies. Returns the plot of the coloured nodes.
"""
function draw_search_map!(axis, case; colorrange, rows=false)
    (; corridor, leg, record) = case
    rows && draw_rows!(axis, corridor)
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
    lines!(axis, track; color=:black, linewidth=pt(1.2))
    flying = [point[5] == WindShipOpt.FLYING for point in leg.path]
    for i in 2:length(track)
        flying[i] && lines!(axis, track[(i - 1):i]; color=palette[1],
            linewidth=pt(2.4))
    end
    return nodes
end

"""
    draw_rows!(axis, corridor)

The rows of `corridor`, each a line through its water nodes from stage to stage, so that a
row stepping backwards or crossing another shows.
"""
function draw_rows!(axis, corridor)
    points = Point2f[]
    for lateral in axes(corridor.lat, 2)
        for stage in axes(corridor.lat, 1)
            index = CartesianIndex(stage, lateral)
            push!(points, corridor.water[index] ? only(node_points(corridor, [index])) :
                          Point2f(NaN))
        end
        push!(points, Point2f(NaN))
    end
    lines!(axis, points; row_style...)
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
    arrows2d!(axis, points, vectors .* 0.3f0; color=(:black, 0.55), shaftwidth=pt(0.5),
        tiplength=pt(2.5), tipwidth=pt(2.2), minshaftlength=0)
end

"""
    draw_states!(axis, case)

The time bins of each stage of the search of `case`, by distance along the corridor and
days since departure: searched on, only pruned, or never reached; with the passage the
search found, dashed, and the passage the final pass made of it.
"""
function draw_states!(axis, case)
    (; corridor, record, leg) = case
    states = state_map(record)
    along = corridor.along_centre ./ NAUTICAL_MILE ./ 1000
    edges = [along[1]; (along[1:(end - 1)] .+ along[2:end]) ./ 2; along[end]]
    days = (0:size(states, 2)) .* record.time_step ./ 24
    used = findlast(any(>(0), states; dims=1)[:])
    heatmap!(axis, edges, days[1:(used + 1)], states[:, 1:used]; colorrange=(0, 2),
        colormap=[:white, :gray75, :gray35])
    lines!(axis, along, [point[3] / 24 for point in leg.path]; color=:black,
        linewidth=pt(1.2))
    lines!(axis, along, [point[3] / 24 for point in record.found.path]; found_style...)
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

"line style of the rows of a corridor"
row_style = (; color=(:black, 0.25), linewidth=pt(0.3))

"line style of the edges of a corridor"
edge_style = (; color=(:black, 0.45), linewidth=pt(0.4))

"line style of the passage a search found before its final pass"
found_style = (; color=palette[2], linewidth=pt(1.2), linestyle=:dash)

"colour of the nodes a search kept with no estimate onward"
no_estimate_shade = :gray35

"colour of the hours a kite flies along a passage"
flight_shade = (palette[1], 0.25)

"""
    case_title(case)

Title of a column of [`router_view`](@ref): the label of `case`, the corridor spacings, the
margin kept, what the final pass saved and the time routing took.
"""
function case_title(case)
    (; corridor, record) = case
    open_stages = findall(>(1), vec(count(corridor.water; dims=2)))
    stage_spacing = median(diff(corridor.along_centre)[open_stages[1:(end - 1)]]) /
                    NAUTICAL_MILE
    pass = isfinite(record.limit) ?
           @sprintf("margin %.0f %%", 100 * (record.limit / record.estimate - 1)) :
           "every state"
    saved = 100 * (1 - case.leg.objective / record.found.objective)
    return @sprintf("%s\n%.0f × %.0f nmi grid, %s, final pass %.1f %%, %.0f s", case.label,
        stage_spacing, corridor.lateral_spacing / NAUTICAL_MILE, pass, saved, case.seconds)
end

"""
    router_panels!(positions, case; limits, colorrange, titles, ylabels=true, rows=false)

Axes at the four grid `positions` of a figure with their `titles`, latitude and other
y labels where `ylabels` holds, and on them land and the [`draw_search_map!`](@ref) of
`case` within `limits` (west, east, south, north) [deg] and `colorrange`, its
[`draw_states!`](@ref) and its [`draw_passage!`](@ref). Returns the axes as `map`, `states`,
`speed` and `wind`, and the plot of the coloured nodes.
"""
function router_panels!(positions, case; limits, colorrange, titles, ylabels=true,
        rows=false)
    ylabel(label) = ylabels ? label : ""
    map_axis = Axis(positions[1]; aspect=DataAspect(), limits, title=titles[1],
        xlabel="longitude [°]", ylabel=ylabel("latitude [°]"))
    state_axis = Axis(positions[2]; title=titles[2],
        xlabel="distance along corridor [1000 nmi]", ylabel=ylabel("time [d]"))
    speed_axis = Axis(positions[3]; title=titles[3], ylabel=ylabel("speed [kn]"),
        xticklabelsvisible=false)
    wind_axis = Axis(positions[4]; title=titles[4], xlabel="days since departure",
        ylabel=ylabel("10 m wind [m/s]"))
    linkxaxes!(speed_axis, wind_axis)
    draw_land!(map_axis, mask; lons=limits[1]:0.25:limits[2],
        lats=limits[3]:0.25:limits[4])
    nodes = draw_search_map!(map_axis, case; colorrange, rows)
    draw_states!(state_axis, case)
    draw_passage!(speed_axis, wind_axis, case)
    return (; map=map_axis, states=state_axis, speed=speed_axis, wind=wind_axis), nodes
end

"""
    router_view(cases, file; limits=nothing)

Save to `file` one column of [`router_panels!`](@ref) per routed case of
[`routed_case`](@ref), with the corridor's rows, its map within `limits` (west, east,
south, north) [deg], by default that of all the corridors' water nodes.
"""
function router_view(cases, file; limits=nothing)
    limits = something(limits, map_limits(cases))
    colorrange = excess_range(cases)
    figure = Figure(size=(page_width / 2 * max(2, length(cases)), 540))
    passage_axes = Axis[]
    for (column, case) in enumerate(cases)
        axes, nodes = router_panels!([figure[row, column] for row in 1:4], case; limits,
            colorrange, titles=(case_title(case), "", "", ""), ylabels=column == 1,
            rows=true)
        column == length(cases) && Colorbar(figure[1, column + 1], nodes;
            label=excess_label)
        push!(passage_axes, axes.speed, axes.wind)
    end
    linkxaxes!(passage_axes...)
    linkyaxes!(passage_axes[1:2:end]...)
    linkyaxes!(passage_axes[2:2:end]...)
    entries, labels = router_legend_entries()
    Legend(figure[5, 1:length(cases)], [entries; LineElement(; row_style...)],
        [labels; "rows"]; orientation=:horizontal, nbanks=length(cases) > 2 ? 2 : 3)
    rowsize!(figure.layout, 1, Auto(2.4))
    rowgap!(figure.layout, 3, pt(3))
    save(file, figure; pt_per_unit=print_scale)
    return figure
end

"label of the colour bar of [`node_excess`](@ref)"
excess_label = "best passage through node,\n% above the one found"

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

"legend entries and labels of the marks of [`router_view`](@ref) and the router figure"
router_legend_entries() = (
    [LineElement(color=:black, linewidth=pt(1.2)),
        LineElement(; found_style...),
        [PolyElement(color=flight_shade),
            LineElement(color=palette[1], linewidth=pt(2.4))],
        LineElement(; edge_style...),
        MarkerElement(marker=:circle, color=no_estimate_shade, markersize=pt(3)),
        MarkerElement(marker=:circle, color=:transparent, strokecolor=:gray45,
            strokewidth=pt(0.3), markersize=pt(3)),
        MarkerElement(marker=:circle, color=:gray80, markersize=pt(1.5)),
        PolyElement(color=:gray35), PolyElement(color=:gray75)],
    ["passage", "before final pass", "kite flying", "edges allowed",
        "node kept, no estimate", "node pruned", "node not reached", "states searched",
        "states pruned"])

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

The [`router_panels!`](@ref) of one winter passage to Guadeloupe of a 140 m e-ammonia ship
with a 3200 m^2 kite, on the corridor of the run in use.
"""
function router_figure()
    case = routed_case(ShipDesign(:ammonia, 140.0; kite_area=3200.0), :caribbean,
        departures[1]; scale=run_settings().corridor_scale)
    figure = Figure(size=(page_width, 300))
    _, nodes = router_panels!(
        [figure[1:3, 1], figure[1, 3], figure[2, 3], figure[3, 3]], case;
        limits=map_limits([case]), colorrange=excess_range([case]),
        titles=("(a) nodes searched and the passage", "(b) states searched",
            "(c) speed held", "(d) wind met"))
    Colorbar(figure[1:3, 2], nodes; label=replace(excess_label, "\n" => " "))
    Legend(figure[4, 1:3], router_legend_entries()...; orientation=:horizontal, nbanks=3)
    colsize!(figure.layout, 1, Auto(1.25))
    save(joinpath(figures, "router.pdf"), figure; pt_per_unit=print_scale)
end
