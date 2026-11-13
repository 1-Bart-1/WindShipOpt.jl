# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Figures of what the weather router saw and did on real routed passages: the corridor and
# the nodes its search kept, the weather met, the states searched and pruned and the
# passage with its speeds and kite flights. Included by paper.jl, after paper_figures.jl.
#
#     case = routed_case(ShipDesign(:ammonia, 140.0; kite_area=3200.0), :caribbean,
#         departures[1]; scale=1.0)
#     router_view([case], ".agent/scratch/kite.png")

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
`NaN` where no state was reached.
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
    state_map(record)

Whether each time bin of each stage of `record` held no state (0), only states the search
pruned (1) or a state it searched on (2), stage × bin.
"""
function state_map(record)
    kept = dropdims(any(kept_states(record); dims=(1, 3)); dims=(1, 3))
    reached = dropdims(any(isfinite.(record.cost); dims=(1, 3)); dims=(1, 3))
    return permutedims(reached .+ kept)
end

"""
    draw_search_map!(axis, case; colorrange)

The water nodes of the corridor of `case` on a longitude-latitude `axis`, coloured by
[`node_excess`](@ref) within `colorrange` where the search kept a state, open where it
pruned all, faint where it reached none; the edges allowed from each node of the passage;
the 10 m wind at a share of the nodes when the passage reached their stage; and the passage,
in the kite's colour where the kite flies. Returns the plot of the coloured nodes.
"""
function draw_search_map!(axis, case; colorrange)
    (; corridor, leg, record) = case
    excess = node_excess(case)
    water = findall(corridor.water)
    kept = filter(index -> excess[index] <= limit_excess(record), water)
    pruned = filter(index -> excess[index] > limit_excess(record), water)
    unreached = filter(index -> isnan(excess[index]), water)
    dot = node_dot(corridor)
    scatter!(axis, node_points(corridor, unreached); color=:gray80, markersize=0.5dot)
    scatter!(axis, node_points(corridor, pruned); color=:transparent, strokecolor=:gray45,
        strokewidth=pt(0.3), markersize=dot)
    nodes = scatter!(axis, node_points(corridor, kept); color=excess[kept],
        colormap=:viridis, colorrange, markersize=dot)
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
days since departure: searched on, only pruned, or never reached; with the passage found.
"""
function draw_states!(axis, case)
    (; corridor, record) = case
    states = state_map(record)
    along = corridor.along_centre ./ NAUTICAL_MILE ./ 1000
    edges = [along[1]; (along[1:(end - 1)] .+ along[2:end]) ./ 2; along[end]]
    days = (0:size(states, 2)) .* record.time_step ./ 24
    used = findlast(any(>(0), states; dims=1)[:])
    heatmap!(axis, edges, days[1:(used + 1)], states[:, 1:used]; colorrange=(0, 2),
        colormap=[:white, :gray75, :gray35])
    lines!(axis, along, [point[3] / 24 for point in record.found.path]; color=:black,
        linewidth=pt(1.2))
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
edge_style = (; color=(:black, 0.45), linewidth=pt(0.4))

"colour of the hours a kite flies along a passage"
flight_shade = (palette[1], 0.25)

"""
    case_title(case)

Title of a column of [`router_view`](@ref): the label of `case`, the corridor spacings, the
margin kept and the time routing took.
"""
function case_title(case)
    (; corridor, record) = case
    open_stages = findall(>(1), vec(count(corridor.water; dims=2)))
    stage_spacing = median(diff(corridor.along_centre)[open_stages[1:(end - 1)]]) /
                    NAUTICAL_MILE
    pass = isfinite(record.limit) ?
           @sprintf("margin %.0f %%", 100 * (record.limit / record.estimate - 1)) :
           "every state"
    return @sprintf("%s\n%.0f × %.0f nmi grid, %s, %.0f s", case.label, stage_spacing,
        corridor.lateral_spacing / NAUTICAL_MILE, pass, case.seconds)
end

"""
    router_view(cases, file; limits=nothing)

Save to `file` one column per routed case of [`routed_case`](@ref): the
[`draw_search_map!`](@ref) of its corridor within `limits` (west, east, south, north) [deg],
by default that of all the corridors' water nodes, its [`draw_states!`](@ref) and its
[`draw_passage!`](@ref).
"""
function router_view(cases, file; limits=nothing)
    limits = something(limits, map_limits(cases))
    colorrange = excess_range(cases)
    figure = Figure(size=(page_width / 2 * max(2, length(cases)), 540))
    passage_axes = Axis[]
    for (column, case) in enumerate(cases)
        ylabel(label) = column == 1 ? label : ""
        map_axis = Axis(figure[1, column]; aspect=DataAspect(), limits,
            title=case_title(case), xlabel="longitude [°]", ylabel=ylabel("latitude [°]"))
        draw_land!(map_axis, mask; lons=limits[1]:0.25:limits[2],
            lats=limits[3]:0.25:limits[4])
        nodes = draw_search_map!(map_axis, case; colorrange)
        column == length(cases) && Colorbar(figure[1, column + 1], nodes;
            label="best passage through node,\n% above the one found")
        state_axis = Axis(figure[2, column]; xlabel="distance along corridor [1000 nmi]",
            ylabel=ylabel("time [d]"))
        draw_states!(state_axis, case)
        speed_axis = Axis(figure[3, column]; ylabel=ylabel("speed [kn]"),
            xticklabelsvisible=false)
        wind_axis = Axis(figure[4, column]; xlabel="days since departure",
            ylabel=ylabel("10 m wind [m/s]"))
        draw_passage!(speed_axis, wind_axis, case)
        push!(passage_axes, speed_axis, wind_axis)
    end
    linkxaxes!(passage_axes...)
    linkyaxes!(passage_axes[1:2:end]...)
    linkyaxes!(passage_axes[2:2:end]...)
    Legend(figure[5, 1:length(cases)], router_legend_entries()...; orientation=:horizontal,
        nbanks=length(cases) > 2 ? 1 : 2)
    rowsize!(figure.layout, 1, Auto(2.4))
    rowgap!(figure.layout, 3, pt(3))
    save(file, figure; pt_per_unit=print_scale)
    return figure
end

"""
    excess_range(cases)

Colour range of the [`node_excess`](@ref) of `cases` [%]: from the least, or zero, to the
widest limit of their searches.
"""
excess_range(cases) = (
    min(0, minimum(minimum(filter(!isnan, node_excess(case))) for case in cases)),
    maximum(limit_excess(case.record) for case in cases))

"legend entries and labels of the marks of [`router_view`](@ref) and the router figure"
router_legend_entries() = (
    [LineElement(color=:black, linewidth=pt(1.2)),
        [PolyElement(color=flight_shade),
            LineElement(color=palette[1], linewidth=pt(2.4))],
        LineElement(; edge_style...),
        MarkerElement(marker=:circle, color=:transparent, strokecolor=:gray45,
            strokewidth=pt(0.3), markersize=pt(3)),
        MarkerElement(marker=:circle, color=:gray80, markersize=pt(1.5)),
        PolyElement(color=:gray35), PolyElement(color=:gray75)],
    ["passage", "kite flying", "edges allowed", "node pruned", "node not reached",
        "states searched", "states pruned"])

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

The router on one winter passage to Guadeloupe of a 140 m e-ammonia ship with a 3200 m^2
kite, on the corridor of the run in use: (a) the [`draw_search_map!`](@ref) of the search,
(b) its [`draw_states!`](@ref), (c, d) the speed held and the wind met along the passage.
"""
function router_figure()
    case = routed_case(ShipDesign(:ammonia, 140.0; kite_area=3200.0), :caribbean,
        departures[1]; scale=run_settings().corridor_scale)
    figure = Figure(size=(page_width, 300))
    limits = map_limits([case])
    map_axis = Axis(figure[1:3, 1]; aspect=DataAspect(), limits,
        title="(a) nodes searched and the passage", xlabel="longitude [°]",
        ylabel="latitude [°]")
    draw_land!(map_axis, mask; lons=limits[1]:0.25:limits[2], lats=limits[3]:0.25:limits[4])
    nodes = draw_search_map!(map_axis, case; colorrange=excess_range([case]))
    Colorbar(figure[1:3, 2], nodes;
        label="best passage through node, % above the one found")
    state_axis = Axis(figure[1, 3]; title="(b) states searched",
        xlabel="distance along corridor [1000 nmi]", ylabel="time [d]")
    draw_states!(state_axis, case)
    Legend(figure[4, 1:3], router_legend_entries()...; orientation=:horizontal, nbanks=2)
    speed_axis = Axis(figure[2, 3]; title="(c) speed held", ylabel="speed [kn]",
        xticklabelsvisible=false)
    wind_axis = Axis(figure[3, 3]; title="(d) wind met", xlabel="days since departure",
        ylabel="10 m wind [m/s]")
    linkxaxes!(speed_axis, wind_axis)
    draw_passage!(speed_axis, wind_axis, case)
    colsize!(figure.layout, 1, Auto(1.25))
    save(joinpath(figures, "router.pdf"), figure; pt_per_unit=print_scale)
end
