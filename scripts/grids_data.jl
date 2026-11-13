# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Data step of the grid page of the companion website in site/: the outbound corridor of
# every route at draft and final spacing, its nodes and the edges the router may take.
# Included by paper.jl after explorer_data.jl; run it as `paper(:grids; fidelity)`.

"""
    off_course(course, reference)

Angle [rad, 0..π] between the courses `course` and `reference` [rad from north].
"""
off_course(course, reference) = abs(rem2pi(course - reference, RoundNearest))

"""
    centre_course(corridor, stage)

Course [rad from north] of the centre line of `corridor` from `stage` to the next.
"""
function centre_course(corridor, stage)
    centre = centre_index(corridor)
    return WindShipOpt.bearing(corridor.lat[stage, centre], corridor.lon[stage, centre],
        corridor.lat[stage + 1, centre], corridor.lon[stage + 1, centre])
end

"""
    grid_node_columns(corridor)

Per node of `corridor`, stage after stage: the bits of the steps of its usable edges, the
bits of those running more than 90° off the course of the centre line, and whether its row
line runs that far off to the next stage.
"""
function grid_node_columns(corridor)
    stage_count, lateral_count = size(corridor.lat)
    edges = zeros(Int, lateral_count, stage_count)
    backward = zeros(Int, lateral_count, stage_count)
    row_backward = zeros(Int, lateral_count, stage_count)
    for stage in 1:(stage_count - 1)
        reference = centre_course(corridor, stage)
        for lateral in 1:lateral_count
            row_course = WindShipOpt.bearing(corridor.lat[stage, lateral],
                corridor.lon[stage, lateral], corridor.lat[stage + 1, lateral],
                corridor.lon[stage + 1, lateral])
            row_backward[lateral, stage] = off_course(row_course, reference) > π / 2
            for (step, course) in enumerate(view(corridor.edge_course, stage, lateral, :))
                isnan(course) && continue
                edges[lateral, stage] |= 1 << (step - 1)
                off_course(course, reference) > π / 2 || continue
                backward[lateral, stage] |= 1 << (step - 1)
            end
        end
    end
    return (; edges=vec(edges), backward=vec(backward), row_backward=vec(row_backward))
end

"""
    grid_data(corridor, scale)

The nodes of `corridor`, built at corridor `scale`, for the site, stage after stage:
positions [deg ×100], kinds (`w` water, `c` near the coast, `x` unusable) and the
[`grid_node_columns`](@ref); its stage and row spacing [nmi].
"""
function grid_data(corridor, scale)
    stage_count, lateral_count = size(corridor.lat)
    kind = [!corridor.water[stage, lateral] ? 'x' :
            corridor.near_coast[stage, lateral] ? 'c' : 'w'
            for lateral in 1:lateral_count, stage in 1:stage_count]
    return (; stages=stage_count, laterals=lateral_count, corridor.reach,
        stage_spacing=WindShipOpt.OCEAN_SPACING * scale,
        lateral_spacing=corridor.lateral_spacing / NAUTICAL_MILE,
        lat=vec(round.(Int, 100 .* permutedims(corridor.lat))),
        lon=vec(round.(Int, 100 .* permutedims(corridor.lon))), kind=String(vec(kind)),
        grid_node_columns(corridor)...)
end

"""
    grids_data()

Write grids.json: the [`grid_data`](@ref) of the outbound corridor of every route at the
corridor scale of each fidelity.
"""
function grids_data()
    spacings = [:final, :draft]
    scales = Dict(spacing => fidelities[spacing].corridor_scale for spacing in spacings)
    grids = Dict(string(spacing) => Dict(string(name) =>
                     grid_data(first(corridors(name, scales[spacing])), scales[spacing])
                 for name in route_names) for spacing in spacings)
    document = (; git_commit=paper_run.record["git_commit"], weather=weather_name,
        routes=[(; name=string(name), label=route_label(name)) for name in route_names],
        spacings=string.(spacings), grids)
    write_named_json("grids.json", document)
    println("grids: ", filesize(run_file("grids.json")) ÷ 1000, " kB")
end
