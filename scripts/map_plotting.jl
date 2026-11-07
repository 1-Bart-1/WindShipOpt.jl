# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Map layers shared by the route figures: land from the land mask, wind arrows, smoothed
# tracks and great circles.
using WindShipOpt: is_land

"""
    draw_land!(axis, mask; lons=-75:0.25:10, lats=5:0.25:56)

Grey land of `mask` at the grid points `lons` and `lats` [deg] on a longitude-latitude
`axis`.
"""
function draw_land!(axis, mask; lons=-75:0.25:10, lats=5:0.25:56)
    land = [is_land(mask, lat, lon) for lon in lons, lat in lats]
    heatmap!(axis, lons, lats, land; colormap=[:transparent, (:grey, 0.55)],
        rasterize=4)
end

"""
    draw_wind!(axis, weather, time; scale, lons=-74:4:8, lats=8:4:54)

10 m wind arrows of `weather` at `time` [h] at the grid points `lons` and `lats` [deg].
"""
function draw_wind!(axis, weather, time; scale, lons=-74:4:8, lats=8:4:54)
    points = [Point2f(lon, lat) for lon in lons for lat in lats]
    vectors = [Vec2f(wind(weather, point[2], point[1], time)...) for point in points]
    arrows2d!(axis, points, vectors .* Float32(scale); color=(:black, 0.35))
end

"""
    smooth_track(lons, lats)

Track through the routed nodes with its corners cut three times by Chaikin's scheme, for
display; the end points stay fixed.
"""
function smooth_track(lons, lats)
    points = Point2f.(lons, lats)
    for _ in 1:3
        smoothed = [first(points)]
        for (here, ahead) in zip(points[1:(end - 1)], points[2:end])
            push!(smoothed, 0.75here + 0.25ahead, 0.25here + 0.75ahead)
        end
        push!(smoothed, last(points))
        points = smoothed
    end
    return points
end

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
