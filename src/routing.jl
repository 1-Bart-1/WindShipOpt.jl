"lateral neighbours an edge may shift by, on each side"
const MAX_LATERAL_STEP = 3

"""
    Corridor

Graph for weather routing: stages along a reference track, each with a row of lateral
nodes; edges join a node to nodes up to `MAX_LATERAL_STEP` rows away in the next stage.
"""
struct Corridor
    "node latitude [deg], stage × lateral"
    lat::Matrix{Float64}
    "node longitude [deg], stage × lateral"
    lon::Matrix{Float64}
    "node usable"
    water::BitMatrix
    "edge length [m], stage × lateral × step"
    edge_length::Array{Float64, 3}
    "edge course [rad from north], stage × lateral × step; NaN for unusable edges"
    edge_course::Array{Float64, 3}
    "length of the reference track [m]"
    track_length::Float64
end

centre(corridor::Corridor) = (size(corridor.lat, 2) + 1) ÷ 2

"""
    Corridor(coastal, destination, mask; coastal_spacing, ocean_spacing,
             lateral_spacing, lateral_count)

Corridor that follows the fixed `coastal` waypoints (lat, lon) without lateral freedom,
then opens into a band around the great circle from the last waypoint to `destination`.
The band widens and narrows at 45° near its ends. Spacings in nautical miles.
"""
function Corridor(coastal::Vector{NTuple{2, Float64}}, destination::NTuple{2, Float64},
        mask::LandMask; coastal_spacing=30.0, ocean_spacing=60.0, lateral_spacing=45.0,
        lateral_count=41)
    track = resample(coastal, coastal_spacing * NAUTICAL_MILE)
    coastal_stages = length(track)
    ocean = resample([last(coastal), destination], ocean_spacing * NAUTICAL_MILE)
    append!(track, ocean[2:end])
    stage_count = length(track)
    half = (lateral_count - 1) ÷ 2
    lat = zeros(stage_count, lateral_count)
    lon = zeros(stage_count, lateral_count)
    water = falses(stage_count, lateral_count)
    ocean_length = distance(last(coastal)..., destination...)
    for (stage, (stage_lat, stage_lon)) in enumerate(track)
        neighbour = track[min(stage + 1, stage_count)]
        previous = track[max(stage - 1, 1)]
        course = bearing(previous..., neighbour...)
        along = distance(last(coastal)..., stage_lat, stage_lon)
        width = stage <= coastal_stages ? 0 :
                min(half, floor(Int, min(along, ocean_length - along) /
                                     (lateral_spacing * NAUTICAL_MILE)))
        for lateral in 1:lateral_count
            offset = (lateral - half - 1) * lateral_spacing * NAUTICAL_MILE
            point = destination_point(stage_lat, stage_lon, course + π / 2, offset)
            lat[stage, lateral], lon[stage, lateral] = point
            water[stage, lateral] = abs(lateral - half - 1) <= width &&
                                    !is_land(mask, point...)
        end
    end
    edge_length, edge_course = edges(lat, lon, water, mask)
    track_length = sum(distance(track[i]..., track[i + 1]...) for i in 1:(stage_count - 1))
    return Corridor(lat, lon, water, edge_length, edge_course, track_length)
end

destination_point(lat, lon, course, offset) =
    offset >= 0 ? destination(lat, lon, course, offset) :
    destination(lat, lon, course + π, -offset)

function resample(waypoints, spacing)
    points = [first(waypoints)]
    for (from, to) in zip(waypoints[1:(end - 1)], waypoints[2:end])
        leg = distance(from..., to...)
        course = bearing(from..., to...)
        steps = max(1, round(Int, leg / spacing))
        for step in 1:steps
            push!(points, destination(from..., course, step * leg / steps))
        end
    end
    return points
end

function edges(lat, lon, water, mask)
    stage_count, lateral_count = size(lat)
    steps = 2MAX_LATERAL_STEP + 1
    edge_length = zeros(stage_count - 1, lateral_count, steps)
    edge_course = fill(NaN, stage_count - 1, lateral_count, steps)
    for stage in 1:(stage_count - 1), lateral in 1:lateral_count, step in 1:steps
        next = lateral + step - MAX_LATERAL_STEP - 1
        1 <= next <= lateral_count || continue
        water[stage, lateral] && water[stage + 1, next] || continue
        from = (lat[stage, lateral], lon[stage, lateral])
        to = (lat[stage + 1, next], lon[stage + 1, next])
        midpoint = destination(from..., bearing(from..., to...), distance(from..., to...) / 2)
        is_land(mask, midpoint...) && continue
        edge_length[stage, lateral, step] = distance(from..., to...)
        edge_course[stage, lateral, step] = bearing(from..., to...)
    end
    return edge_length, edge_course
end

"""
    return_corridor(corridor, mask)

The same corridor sailed from its last stage to its first.
"""
function return_corridor(corridor::Corridor, mask::LandMask)
    lat = reverse(corridor.lat; dims=1)
    lon = reverse(corridor.lon; dims=1)
    water = reverse(corridor.water; dims=1)
    return Corridor(lat, lon, water, edges(lat, lon, water, mask)...,
        corridor.track_length)
end

"""
    Leg

Optimal passage along a corridor: fuel energy [J], fuel cost [USD], duration [h] and
the path as (latitude, longitude, time [h], speed [m/s]) per stage.
"""
struct Leg
    fuel_energy::Float64
    fuel_cost::Float64
    duration::Float64
    path::Vector{NTuple{4, Float64}}
end

"""
    route(corridor, table, fuel, weather, departure; time_cost, speeds, time_step=3.0,
          max_duration=50 * 24.0)

Weather routing by forward dynamic programming over (stage, lateral node, arrival time
bin). Minimises fuel cost plus `time_cost` [USD/h] times duration for a departure at
`departure` [h]; `speeds` in m/s, times in hours. Returns `nothing` if no path arrives
within `max_duration`.
"""
function route(corridor::Corridor, table::PerformanceTable, fuel::Fuel, weather,
        departure; time_cost, speeds=(4:12) .* KNOT, time_step=3.0,
        max_duration=50 * 24.0)
    stage_count, lateral_count = size(corridor.lat)
    bins = ceil(Int, max_duration / time_step)
    cost = fill(Inf, lateral_count, bins, stage_count)
    elapsed = zeros(lateral_count, bins, stage_count)
    energy = zeros(lateral_count, bins, stage_count)
    parent = zeros(Int32, lateral_count, bins, stage_count)
    chosen_speed = zeros(Float32, lateral_count, bins, stage_count)
    start = centre(corridor)
    cost[start, 1, 1] = 0.0
    for stage in 1:(stage_count - 1), lateral in 1:lateral_count
        corridor.water[stage, lateral] || continue
        for bin in 1:bins
            isfinite(cost[lateral, bin, stage]) || continue
            time = elapsed[lateral, bin, stage]
            east, north = wind(weather, corridor.lat[stage, lateral],
                corridor.lon[stage, lateral], departure + time)
            wind_speed = hypot(east, north)
            for step in 1:(2MAX_LATERAL_STEP + 1)
                course = corridor.edge_course[stage, lateral, step]
                isnan(course) && continue
                next = lateral + step - MAX_LATERAL_STEP - 1
                angle = true_wind_angle(east, north, wind_speed, course)
                length = corridor.edge_length[stage, lateral, step]
                for speed in speeds
                    power = lookup(table, speed, wind_speed, angle)
                    isfinite(power) || continue
                    duration = length / speed / 3600
                    arrival = time + duration
                    next_bin = floor(Int, arrival / time_step) + 1
                    next_bin <= bins || continue
                    fuel_energy = power * duration * 3600
                    total = cost[lateral, bin, stage] + fuel_energy * fuel.price +
                            time_cost * duration
                    total < cost[next, next_bin, stage + 1] || continue
                    cost[next, next_bin, stage + 1] = total
                    elapsed[next, next_bin, stage + 1] = arrival
                    energy[next, next_bin, stage + 1] = energy[lateral, bin, stage] +
                                                        fuel_energy
                    parent[next, next_bin, stage + 1] = (lateral - 1) * bins + bin
                    chosen_speed[next, next_bin, stage + 1] = speed
                end
            end
        end
    end
    total, best_bin = findmin(view(cost, start, :, stage_count))
    isfinite(total) || return nothing
    path = trace_path(corridor, elapsed, parent, chosen_speed, start, best_bin, bins)
    fuel_energy = energy[start, best_bin, stage_count]
    return Leg(fuel_energy, fuel_energy * fuel.price, elapsed[start, best_bin, stage_count],
        path)
end

function trace_path(corridor, elapsed, parent, chosen_speed, lateral, bin, bins)
    stage = size(corridor.lat, 1)
    path = NTuple{4, Float64}[]
    while stage >= 1
        pushfirst!(path, (corridor.lat[stage, lateral], corridor.lon[stage, lateral],
            elapsed[lateral, bin, stage], chosen_speed[lateral, bin, stage]))
        stage == 1 && break
        index = parent[lateral, bin, stage] - 1
        lateral, bin = index ÷ bins + 1, index % bins + 1
        stage -= 1
    end
    return path
end

"""
    true_wind_angle(east, north, wind_speed, course)

Angle [rad, 0..π] between the ship's course and the direction the wind comes from.
"""
function true_wind_angle(east, north, wind_speed, course)
    wind_speed > 0 || return 0.0
    from_east, from_north = -east / wind_speed, -north / wind_speed
    return acos(clamp(from_east * sin(course) + from_north * cos(course), -1.0, 1.0))
end
