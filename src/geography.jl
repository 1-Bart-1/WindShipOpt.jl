# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"mean Earth radius [m]"
const EARTH_RADIUS = 6.371e6

const NAUTICAL_MILE = 1852.0

"""
    distance(lat1, lon1, lat2, lon2)

Great-circle distance [m] between two points given in degrees.
"""
function distance(lat1, lon1, lat2, lon2)
    φ1, φ2 = deg2rad(lat1), deg2rad(lat2)
    Δφ, Δλ = φ2 - φ1, deg2rad(lon2 - lon1)
    a = sin(Δφ / 2)^2 + cos(φ1) * cos(φ2) * sin(Δλ / 2)^2
    return 2EARTH_RADIUS * asin(sqrt(min(a, 1.0)))
end

"""
    bearing(lat1, lon1, lat2, lon2)

Initial great-circle course [rad, clockwise from north] from point 1 to point 2.
"""
function bearing(lat1, lon1, lat2, lon2)
    φ1, φ2 = deg2rad(lat1), deg2rad(lat2)
    Δλ = deg2rad(lon2 - lon1)
    return atan(sin(Δλ) * cos(φ2), cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ))
end

"""
    destination(lat, lon, course, range)

Point [deg] reached after `range` [m] along the great circle leaving at `course` [rad].
"""
function destination(lat, lon, course, range)
    φ1, λ1 = deg2rad(lat), deg2rad(lon)
    δ = range / EARTH_RADIUS
    φ2 = asin(sin(φ1) * cos(δ) + cos(φ1) * sin(δ) * cos(course))
    λ2 = λ1 + atan(sin(course) * sin(δ) * cos(φ1), cos(δ) - sin(φ1) * sin(φ2))
    return rad2deg(φ2), rad2deg(λ2)
end

"""
    Island

Land approximated as a disk.
"""
struct Island
    lat::Float64
    lon::Float64
    "radius including a safety margin [m]"
    radius::Float64
end

"""
    LandMask

Coarse land mask for the eastern North Atlantic: islands as disks, and the European
and African coast as the longitude east of which everything is land, per latitude.
"""
struct LandMask
    islands::Vector{Island}
    "coast latitudes [deg], ascending"
    coast_lats::Vector{Float64}
    coast_lons::Vector{Float64}
    function LandMask(islands, coast_lats, coast_lons)
        issorted(coast_lats) || throw(ArgumentError("coast latitudes must ascend"))
        return new(islands, coast_lats, coast_lons)
    end
end

"""
    north_atlantic_mask()

Coarse mask of the Atlantic islands and the coast from Brittany to Guinea, with about
20 nm of margin.
"""
function north_atlantic_mask()
    islands = [Island(39.4, -31.2, 60e3), Island(38.6, -28.0, 110e3),
        Island(37.8, -25.4, 70e3), Island(32.7, -16.9, 60e3), Island(28.3, -16.6, 140e3),
        Island(28.6, -13.9, 120e3), Island(16.0, -24.0, 240e3), Island(32.3, -64.8, 50e3)]
    coast = [(10.0, -15.0), (15.0, -17.5), (21.0, -17.3), (28.0, -13.0), (33.0, -9.0),
        (36.0, -6.5), (37.0, -9.2), (43.0, -9.6), (43.4, -8.2), (43.5, -2.0),
        (46.0, -1.4), (47.4, -2.8), (48.3, -4.9), (48.5, -5.2)]
    return LandMask(islands, first.(coast), last.(coast))
end

function on_island(islands, lat, lon)
    for island in islands
        distance(lat, lon, island.lat, island.lon) < island.radius && return true
    end
    return false
end

function is_land(mask::LandMask, lat, lon)
    on_island(mask.islands, lat, lon) && return true
    first(mask.coast_lats) <= lat <= last(mask.coast_lats) || return false
    i = searchsortedlast(mask.coast_lats, lat)
    i == length(mask.coast_lats) && return lon > last(mask.coast_lons)
    weight = (lat - mask.coast_lats[i]) / (mask.coast_lats[i + 1] - mask.coast_lats[i])
    coast_lon = (1 - weight) * mask.coast_lons[i] + weight * mask.coast_lons[i + 1]
    return lon > coast_lon - 0.3
end
