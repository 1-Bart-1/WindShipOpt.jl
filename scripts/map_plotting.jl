# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Map layers shared by the route figures: land from the land mask, wind arrows and their
# key, the nodes of routed tracks and great circles.
using WindShipOpt: is_land

"""
    draw_land!(axis, mask; lons=-75:0.25:10, lats=5:0.25:56)

Grey land of `mask` at the grid points `lons` and `lats` [deg] on a longitude-latitude
`axis`.
"""
function draw_land!(axis, mask; lons=-75:0.25:10, lats=5:0.25:56)
    land = [is_land(mask, lat, lon) for lon in lons, lat in lats]
    heatmap!(axis, lons, lats, land; colormap=[:transparent, (:grey, 0.55)],
        colorrange=(0, 1), rasterize=4)
end

"style of the arrows of [`draw_wind!`](@ref) and of their [`wind_key!`](@ref)"
wind_arrow_style = (; color=(:black, 0.35), shaftwidth=0.6, tiplength=2.8, tipwidth=2.6)

"""
    draw_wind!(axis, weather, time; scale, lons=-74:4:8, lats=8:4:54)

Arrows of the wind 10 m above the sea of `weather` at `time` [h] at the grid points `lons`
and `lats` [deg].
"""
function draw_wind!(axis, weather, time; scale, lons=-74:4:8, lats=8:4:54)
    points = [Point2f(lon, lat) for lon in lons for lat in lats]
    vectors = [Vec2f(wind(weather, point[2], point[1], time)...) for point in points]
    arrows2d!(axis, points, vectors .* Float32(scale); wind_arrow_style...,
        minshaftlength=0)
end

"""
    wind_key!(axis, corner, speed, scale, height; style=wind_arrow_style)

A white box of `height` [deg] with its lower left at `corner` [deg] in the map `axis`,
holding a wind arrow of `speed` [m/s] in `style` at `scale` [deg per m/s], labelled with
that speed.
"""
function wind_key!(axis, corner, speed, scale, height; style=wind_arrow_style)
    poly!(axis, Rect2f(corner, Vec2f(speed * scale + 2.8height, height)); color=:white,
        strokecolor=:gray55, strokewidth=rule_width)
    start = corner .+ Point2f(height / 3, height / 2)
    arrows2d!(axis, [start], [Vec2f(speed * scale, 0)]; style...)
    text!(axis, start .+ Point2f(speed * scale, 0); text="$speed m/s",
        align=(:left, :center), offset=clear_offset((:left, :center), pt(2.5)),
        fontsize=note_size)
end

"""
    track_points(path)

Longitude and latitude [deg] of the nodes of a routed `path`, as points.
"""
track_points(path) = Point2f.(getindex.(path, 2), getindex.(path, 1))

"""
    great_circle(start, finish)

Longitudes and latitudes [deg] of the shortest path over the sphere between two path
points given as (lat, lon, ...).
"""
function great_circle(start, finish)
    start_vector = unit_vector(start[1], start[2])
    finish_vector = unit_vector(finish[1], finish[2])
    angle = acos(clamp(sum(start_vector .* finish_vector), -1, 1))
    lons, lats = Float64[], Float64[]
    for fraction in range(0, 1; length=100)
        position = (sin((1 - fraction) * angle) .* start_vector .+
                    sin(fraction * angle) .* finish_vector) ./ sin(angle)
        push!(lons, atand(position[2], position[1]))
        push!(lats, asind(position[3]))
    end
    return lons, lats
end

"""
    unit_vector(lat, lon)

Earth-centred unit vector of a point at `lat` and `lon` [deg].
"""
unit_vector(lat, lon) = (cosd(lat) * cosd(lon), cosd(lat) * sind(lon), sind(lat))
