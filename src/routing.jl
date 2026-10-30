"lateral neighbours an edge may shift by, on each side"
const MAX_LATERAL_STEP = 3

"stages on each side over which the lateral direction is averaged, so rows do not cross"
const NORMAL_SMOOTHING = 8

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

centre_index(corridor::Corridor) = (size(corridor.lat, 2) + 1) ÷ 2

"""
    Corridor(coastal, ocean, mask; coastal_spacing, ocean_spacing, lateral_spacing,
             lateral_count)

Corridor that follows the fixed `coastal` waypoints (lat, lon) without lateral freedom,
then opens into a band around the `ocean` waypoints, the last of which is the
destination. The band widens and narrows at 45° near its ends. Spacings in nautical
miles.
"""
function Corridor(coastal::Vector{NTuple{2, Float64}}, ocean::Vector{NTuple{2, Float64}},
        mask::LandMask; coastal_spacing=30.0, ocean_spacing=60.0, lateral_spacing=45.0,
        lateral_count=41)
    track = resample(coastal, coastal_spacing * NAUTICAL_MILE)
    coastal_stages = length(track)
    append!(track, resample([last(coastal); ocean], ocean_spacing * NAUTICAL_MILE)[2:end])
    stage_count = length(track)
    along = cumsum([0.0; [distance(track[i]..., track[i + 1]...)
                          for i in 1:(stage_count - 1)]])
    ocean_start, track_end = along[coastal_stages], last(along)
    half = (lateral_count - 1) ÷ 2
    lat = zeros(stage_count, lateral_count)
    lon = zeros(stage_count, lateral_count)
    water = falses(stage_count, lateral_count)
    for (stage, (stage_lat, stage_lon)) in enumerate(track)
        course = bearing(track[max(stage - NORMAL_SMOOTHING, 1)]...,
            track[min(stage + NORMAL_SMOOTHING, stage_count)]...)
        margin = min(along[stage] - ocean_start, track_end - along[stage])
        width = stage <= coastal_stages ? 0 :
                min(half, floor(Int, margin / (lateral_spacing * NAUTICAL_MILE)))
        for lateral in 1:lateral_count
            offset = (lateral - half - 1) * lateral_spacing * NAUTICAL_MILE
            point = destination_point(stage_lat, stage_lon, course + π / 2, offset)
            lat[stage, lateral], lon[stage, lateral] = point
            water[stage, lateral] = abs(lateral - half - 1) <= width &&
                                    !is_land(mask, point...)
        end
    end
    return Corridor(lat, lon, water, edges(lat, lon, water, mask)..., track_end)
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

Optimal passage along a corridor: fuel energy [J], fuel cost [USD], hours the rig was
flown, duration [h] and the path as (latitude, longitude, time [h], speed [m/s]) per stage.
"""
struct Leg
    fuel_energy::Float64
    fuel_cost::Float64
    flight_hours::Float64
    duration::Float64
    path::Vector{NTuple{4, Float64}}
end

"""
    route(corridor, table, weather, departure; time_cost, speeds, time_step=3.0,
          max_duration=50 * 24.0)

Weather routing by forward dynamic programming over (stage, lateral node, arrival time
bin). Minimises fuel cost plus rig wear plus `time_cost` [USD/h] times duration for a
departure at `departure` [h]; `speeds` in m/s default to whole knots up to the ship's
maximum speed, times in hours. Returns `nothing` if no path arrives within
`max_duration`.
"""
function route(corridor::Corridor, table::PerformanceTable, weather, departure; time_cost, speeds=(4:max_knots(table)) .* KNOT, time_step=3.0,
        max_duration=50 * 24.0)
    stage_count, lateral_count = size(corridor.lat)
    bins = ceil(Int, max_duration / time_step)
    cost = fill(Inf, lateral_count, bins, stage_count)
    elapsed = zeros(lateral_count, bins, stage_count)
    energy = zeros(lateral_count, bins, stage_count)
    flight_hours = zeros(lateral_count, bins, stage_count)
    price = table.ship.fuel.price
    parent = zeros(Int32, lateral_count, bins, stage_count)
    chosen_speed = zeros(Float32, lateral_count, bins, stage_count)
    start = centre_index(corridor)
    cost[start, 1, 1] = 0.0
    for stage in 1:(stage_count - 1), lateral in 1:lateral_count
        corridor.water[stage, lateral] || continue
        for bin in 1:bins
            isfinite(cost[lateral, bin, stage]) || continue
            time = elapsed[lateral, bin, stage]
            lat, lon = corridor.lat[stage, lateral], corridor.lon[stage, lateral]
            east, north = wind(weather, lat, lon, departure + time)
            wind_speed = hypot(east, north)
            wave_height, wave_period, wave_from = waves(weather, lat, lon, departure + time)
            for step in 1:(2MAX_LATERAL_STEP + 1)
                course = corridor.edge_course[stage, lateral, step]
                isnan(course) && continue
                next = lateral + step - MAX_LATERAL_STEP - 1
                angle = true_wind_angle(east, north, wind_speed, course)
                heading = wave_heading(wave_from, course)
                length = corridor.edge_length[stage, lateral, step]
                for speed in speeds
                    point = lookup(table, speed, wind_speed, angle, wave_height,
                        wave_period, heading)
                    isfinite(point.fuel_power) || continue
                    duration = length / speed / 3600
                    arrival = time + duration
                    next_bin = floor(Int, arrival / time_step) + 1
                    next_bin <= bins || continue
                    fuel_energy = point.fuel_power * duration * 3600
                    flown = point.flying ? duration : 0.0
                    total = cost[lateral, bin, stage] + fuel_energy * price +
                            table.wear_cost * flown + time_cost * duration
                    total < cost[next, next_bin, stage + 1] || continue
                    cost[next, next_bin, stage + 1] = total
                    elapsed[next, next_bin, stage + 1] = arrival
                    energy[next, next_bin, stage + 1] = energy[lateral, bin, stage] +
                                                        fuel_energy
                    flight_hours[next, next_bin, stage + 1] =
                        flight_hours[lateral, bin, stage] + flown
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
    return Leg(fuel_energy, fuel_energy * price, flight_hours[start, best_bin, stage_count],
        elapsed[start, best_bin, stage_count], path)
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

"""
    caribbean_corridors(mask)

Outbound and return corridors between Rotterdam and Guadeloupe. Both run through the
Channel to Ushant; outbound the band is centred on the trade-wind route via the
Canaries, homeward on the great circle through the westerlies.
"""
function caribbean_corridors(mask::LandMask)
    channel = [(51.98, 4.05), (51.05, 1.60), (50.05, -1.50), (48.80, -6.00)]
    guadeloupe = (16.15, -61.20)
    outbound = Corridor(channel, [(40.0, -14.0), (27.0, -28.0), guadeloupe], mask)
    inbound = return_corridor(Corridor(channel, [guadeloupe], mask), mask)
    return outbound, inbound
end

"""
    wave_heading(wave_from, course)

Wave heading relative to the ship [rad]: π when the waves come from straight ahead, 0
when they come from astern; both angles clockwise from north.
"""
wave_heading(wave_from, course) = π - abs(rem2pi(wave_from - course, RoundNearest))
