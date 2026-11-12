# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"rows an edge of a corridor of stages 1.5 times as far apart as its rows may shift by"
const MAX_LATERAL_STEP = 2

"largest tangent of the angle between an edge and its corridor [-]"
const MAX_HEADING_TANGENT = 2MAX_LATERAL_STEP / 3

"step of an edge between nodes of the same lateral number, on a corridor of one row"
const STRAIGHT_ON = MAX_LATERAL_STEP + 1

"rows an edge of `stage_spacing` along a corridor of `lateral_spacing` may shift by"
lateral_reach(stage_spacing, lateral_spacing) =
    max(1, floor(Int, MAX_HEADING_TANGENT * stage_spacing / lateral_spacing + 1e-6))

"stages on each side over which the lateral direction is averaged"
const NORMAL_SMOOTHING = 8

"""
    Corridor

Graph for weather routing: stages along a reference track, each with a row of lateral
nodes; edges join a node to nodes up to `reach` rows away in the next stage.
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
    "node within the coastal clearance of land, where the router pays a penalty"
    near_coast::BitMatrix
    "distance from the first stage along the centre line, per stage [m]"
    along_centre::Vector{Float64}
    "rows an edge may shift by, on each side"
    reach::Int
    "distance between the rows of a stage [m]"
    lateral_spacing::Float64
    "longest time between the weather samples along the edges of each stage that a plan may
    use [h]; 0 keeps the plan's own"
    sample_hours::Vector{Float64}
end

"edges leaving each node of `corridor`"
step_count(corridor::Corridor) = 2corridor.reach + 1

"lateral node that edge `step` of node `lateral` of `corridor` leads to"
next_lateral(corridor::Corridor, lateral, step) = lateral + step - corridor.reach - 1

"edge of node `lateral` of `corridor` that leads to lateral node `next`"
lateral_step(corridor::Corridor, lateral, next) = next - lateral + corridor.reach + 1

"index of the centre lateral node of a corridor whose nodes are at `lat`"
centre_index(lat::AbstractMatrix) = (size(lat, 2) + 1) ÷ 2
centre_index(corridor::Corridor) = centre_index(corridor.lat)

"distance from land within which the wind grid does not resolve the coast [m]"
const COASTAL_CLEARANCE = 50 * NAUTICAL_MILE

"""
    near_land(mask, lat, lon, clearance)

Whether land lies within `clearance` [m] of the point, sampled on two rings of 16
bearings.
"""
function near_land(mask, lat, lon, clearance)
    for radius in (clearance / 2, clearance), course in range(0, 2π; length=17)[1:16]
        is_land(mask, destination(lat, lon, course, radius)...) && return true
    end
    return false
end

"""
    Corridor(coastal, ocean, mask; ocean_spacing, lateral_spacing, lateral_count)

Corridor that follows the fixed `coastal` waypoints (lat, lon) without lateral freedom,
then opens into a band around the `ocean` waypoints, the last of which is the
destination. Coastal stages lie 30 nautical miles apart; spacings in nautical miles.
"""
function Corridor(coastal::Vector{NTuple{2, Float64}}, ocean::Vector{NTuple{2, Float64}},
        mask; ocean_spacing, lateral_spacing, lateral_count)
    track = resample(coastal, 30.0 * NAUTICAL_MILE)
    coastal_stages = length(track)
    append!(track, resample([last(coastal); ocean], ocean_spacing * NAUTICAL_MILE)[2:end])
    stage_count = length(track)
    along = cumsum([0.0; [distance(track[i]..., track[i + 1]...)
                          for i in 1:(stage_count - 1)]])
    track_end = last(along)
    half = (lateral_count - 1) ÷ 2
    lat = zeros(stage_count, lateral_count)
    lon = zeros(stage_count, lateral_count)
    water = falses(stage_count, lateral_count)
    for (stage, (stage_lat, stage_lon)) in enumerate(track)
        course = bearing(track[max(stage - NORMAL_SMOOTHING, 1)]...,
            track[min(stage + NORMAL_SMOOTHING, stage_count)]...)
        width = stage <= coastal_stages ? 0 : half
        for lateral in 1:lateral_count
            offset = (lateral - half - 1) * lateral_spacing * NAUTICAL_MILE
            point = destination_point(stage_lat, stage_lon, course + π / 2, offset)
            lat[stage, lateral], lon[stage, lateral] = point
            water[stage, lateral] = abs(lateral - half - 1) <= width &&
                                    !is_land(mask, point...)
        end
    end
    near_coast = [near_land(mask, lat[i], lon[i], COASTAL_CLEARANCE)
                  for i in eachindex(lat)]
    reach = lateral_reach(ocean_spacing, lateral_spacing)
    return Corridor(lat, lon, leading_to_port(lat, lon, water, mask, reach)..., track_end,
        reshape(BitVector(near_coast), size(lat)), along_centre_line(lat, lon), reach,
        lateral_spacing * NAUTICAL_MILE, zeros(stage_count))
end

"""
    along_centre_line(lat, lon)

Distance [m] from the first stage along the centre line of nodes at `lat`, `lon`, per stage.
"""
function along_centre_line(lat, lon)
    centre = centre_index(lat)
    return cumsum([0.0; [distance(lat[stage, centre], lon[stage, centre],
                             lat[stage + 1, centre], lon[stage + 1, centre])
                         for stage in 1:(size(lat, 1) - 1)]])
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

"""
    crosses_land(mask, from, to)

Whether the great circle between two points (latitude, longitude) [deg] touches land,
sampled every `EDGE_SAMPLING` along it.
"""
function crosses_land(mask, from, to)
    length = distance(from..., to...)
    course = bearing(from..., to...)
    samples = ceil(Int, length / EDGE_SAMPLING)
    for k in 1:(samples - 1)
        is_land(mask, destination(from..., course, k * length / samples)...) && return true
    end
    return false
end

"spacing of the land checks along an edge [m]"
const EDGE_SAMPLING = 20 * NAUTICAL_MILE

"""
    edges(lat, lon, water, mask, reach, stage_reach=Returns(reach))

Edge lengths [m] and courses [rad from north] of the nodes at `lat`, `lon`, stage × lateral
× step, of edges shifting up to `stage_reach(stage)` rows and clear of land by `mask`.
"""
function edges(lat, lon, water, mask, reach, stage_reach=Returns(reach))
    stage_count, lateral_count = size(lat)
    steps = 2reach + 1
    edge_length = zeros(stage_count - 1, lateral_count, steps)
    edge_course = fill(NaN, stage_count - 1, lateral_count, steps)
    for stage in 1:(stage_count - 1), lateral in 1:lateral_count, step in 1:steps
        next = lateral + step - reach - 1
        1 <= next <= lateral_count && abs(next - lateral) <= stage_reach(stage) || continue
        water[stage, lateral] && water[stage + 1, next] || continue
        from = (lat[stage, lateral], lon[stage, lateral])
        to = (lat[stage + 1, next], lon[stage + 1, next])
        crosses_land(mask, from, to) && continue
        edge_length[stage, lateral, step] = distance(from..., to...)
        edge_course[stage, lateral, step] = bearing(from..., to...)
    end
    return edge_length, edge_course
end

"""
    leading_to_port(lat, lon, water, mask, reach, stage_reach=Returns(reach))

The nodes of `water` from which [`edges`](@ref) lead to the port, the centre of the last
stage, and those edges.
"""
function leading_to_port(lat, lon, water, mask, reach, stage_reach=Returns(reach))
    edge_length, edge_course = edges(lat, lon, water, mask, reach, stage_reach)
    open = copy(water)
    port = centre_index(lat)
    open[end, :] .= false
    open[end, port] = water[end, port]
    for stage in (size(water, 1) - 1):-1:1, lateral in axes(water, 2)
        for step in axes(edge_course, 3)
            isnan(edge_course[stage, lateral, step]) && continue
            open[stage + 1, lateral + step - reach - 1] && continue
            edge_length[stage, lateral, step] = 0.0
            edge_course[stage, lateral, step] = NaN
        end
        open[stage, lateral] &= any(!isnan, view(edge_course, stage, lateral, :))
    end
    return open, edge_length, edge_course
end

"""
    return_corridor(corridor, mask)

The same corridor sailed from its last stage to its first.
"""
function return_corridor(corridor::Corridor, mask)
    lat = reverse(corridor.lat; dims=1)
    lon = reverse(corridor.lon; dims=1)
    water = reverse(corridor.water; dims=1)
    return Corridor(lat, lon, leading_to_port(lat, lon, water, mask, corridor.reach)...,
        corridor.track_length, reverse(corridor.near_coast; dims=1),
        along_centre_line(lat, lon), corridor.reach, corridor.lateral_spacing,
        reverse(corridor.sample_hours))
end

"""
    Leg

Optimal passage along a corridor: fuel energy [J], fuel cost [USD], hours a kite flew
patterns, its launches and forced landings, duration [h], the objective the router
minimises [USD], the path as (latitude, longitude, time [h], commanded speed [m/s], mode)
per stage, the mode of the edge into the stage being the one the kite spent most of the
edge in: 0 down and 1 flying, and whether the kite is aloft on arrival at each stage.
"""
struct Leg
    fuel_energy::Float64
    fuel_cost::Float64
    flight_hours::Float64
    launches::Int
    forced_landings::Int
    duration::Float64
    objective::Float64
    path::Vector{NTuple{5, Float64}}
    aloft::Vector{Bool}
end

# kite down or flying patterns, as the mode of an edge
const STOWED, FLYING = 0, 1

"""
    ForecastWeather(weather, issue_time, horizon)

What a router knows at `issue_time` [h]: `weather` up to `horizon` [h] ahead, and beyond
that the weather of the same date in another year.
"""
struct ForecastWeather{W}
    weather::W
    issue_time::Float64
    horizon::Float64
end

"hours between the forecasts a ship plans on, and that it holds when no plan leaves it [h]"
const FORECAST_INTERVAL = 6.0

"longest a ship on a forecast holds at one node before its passage fails [h]"
const LONGEST_HOLD = 72.0

"hours in the year by which a forecast beyond its horizon shifts the time [h]"
const FORECAST_SHIFT = 8760.0

function forecast_time(forecast::ForecastWeather, time)
    time - forecast.issue_time <= forecast.horizon && return time
    shifted = time + FORECAST_SHIFT
    return shifted <= duration(forecast.weather) ? shifted : time - FORECAST_SHIFT
end

wind(forecast::ForecastWeather, lat, lon, time) =
    wind(forecast.weather, lat, lon, forecast_time(forecast, time))
waves(forecast::ForecastWeather, lat, lon, time) =
    waves(forecast.weather, lat, lon, forecast_time(forecast, time))

"""
    MetWeather(known, weather, lat, lon, time)

What a ship at (`lat`, `lon`) at `time` [h] expects along its next edge: the forecast
`known` plus the error of its wind and wave height against the real `weather` there and
then, kept for the whole edge.
"""
struct MetWeather{K}
    known::K
    east_error::Float64
    north_error::Float64
    height_error::Float64
end

function MetWeather(known, weather, lat, lon, time)
    east, north = wind(weather, lat, lon, time)
    known_east, known_north = wind(known, lat, lon, time)
    height = first(waves(weather, lat, lon, time))
    return MetWeather(known, east - known_east, north - known_north,
        height - first(waves(known, lat, lon, time)))
end

function wind(met::MetWeather, lat, lon, time)
    east, north = wind(met.known, lat, lon, time)
    return east + met.east_error, north + met.north_error
end

function waves(met::MetWeather, lat, lon, time)
    height, period, direction = waves(met.known, lat, lon, time)
    return max(height + met.height_error, 0.0), period, direction
end

"""
    edge_point(corridor, stage, lateral, next, share)

Latitude and longitude [deg] at `share` (0 to 1) along the straight line in latitude and
longitude from node (`stage`, `lateral`) to node (`stage + 1`, `next`).
"""
function edge_point(corridor::Corridor, stage, lateral, next, share)
    lat, lon = corridor.lat[stage, lateral], corridor.lon[stage, lateral]
    return lat + share * (corridor.lat[stage + 1, next] - lat),
    lon + share * (corridor.lon[stage + 1, next] - lon)
end

"""
    RouterSettings

Numerical settings of [`route`](@ref).
"""
Base.@kwdef struct RouterSettings
    "longest time between the weather samples along an edge [h]"
    edge_sample_hours::Float64 = 3.0
    "length of the time bins of the programme [h]"
    time_step::Float64 = 3.0
    "how far above the [`CostToGo`](@ref) of the departure the states searched reach, on
    the first try and where that leaves no path [-]; `Inf` searches them all"
    search_margins::NTuple{2, Float64} = (0.03, 0.06)
    "`search_margins` of a ship that can fly a kite [-]"
    kite_search_margins::NTuple{2, Float64} = (0.2, 0.4)
    "routing speeds, from the lowest routing speed to the ship's top speed"
    routing_speeds::Int = 49
    "speeds the search skips between those it commands, plus one"
    search_speed_stride::Int = 4
    "time between the knots of the [`CostToGo`](@ref) [h]"
    to_go_step::Float64 = 24.0
    "length of the time bins of the final pass along the path found [h]"
    final_time_step::Float64 = 0.25
    "how far the final pass strays in time from the path found [h]"
    final_time_band::Float64 = 24.0
end

"[`RouterSettings`](@ref) in force"
const ROUTER_SETTINGS = Ref(RouterSettings())

"""
    with_router_settings(call, settings)

The result of `call()` with the [`RouterSettings`](@ref) `settings` in force, and those in
force before it afterwards.
"""
function with_router_settings(call, settings::RouterSettings)
    earlier = ROUTER_SETTINGS[]
    ROUTER_SETTINGS[] = settings
    try
        return call()
    finally
        ROUTER_SETTINGS[] = earlier
    end
end

"""
    EdgeSample

Wind and waves at one point of an edge.
"""
struct EdgeSample
    "conditions on the edge's course"
    condition::SeaCondition
    "true wind at the kite's reference height from ahead [m/s]"
    headwind::Float64
    "true wind at the kite's reference height from abeam [m/s]"
    crosswind::Float64
    "whether the sun is up there"
    daylight::Bool
    "10 m true wind speed [m/s]"
    wind_speed::Float64
    "standard error of that speed the plan weighs [m/s]; 0 for a wind taken as known"
    spread::Float64
end

EdgeSample(condition::SeaCondition, headwind, crosswind, daylight) =
    EdgeSample(condition, headwind, crosswind, daylight, 0.0, 0.0)

"""
    is_daylight(lon, time)

Whether `time` [h from midnight UTC] falls between 06:00 and 18:00 local solar time at
longitude `lon` [deg].
"""
is_daylight(lon, time) = 6 <= mod(time + lon / 15, 24) < 18

"""
    EdgeSample(table, (east, north), (wave_height, wave_period, wave_from), course,
               daylight, spread=0.0)

[`EdgeSample`](@ref) for the [`PerformanceTable`](@ref) `table` of a 10 m wind [m/s] and
the [`waves`](@ref) on `course` [rad from north], `daylight` saying whether the sun is up
and `spread` the standard error of the wind speed [m/s].
"""
function EdgeSample(table::PerformanceTable, (east, north), (wave_height, wave_period,
            wave_from), course, daylight, spread=0.0)
    wind_speed = hypot(east, north)
    angle = true_wind_angle(east, north, wind_speed, course)
    condition = SeaCondition(table, wind_speed, angle, wave_height, wave_period,
        wave_heading(wave_from, course))
    table.kite_wind_factor > 0 ||
        return EdgeSample(condition, 0.0, 0.0, daylight, wind_speed, spread)
    crosswind, headwind = table.kite_wind_factor * wind_speed .* sincos(angle)
    return EdgeSample(condition, headwind, crosswind, daylight, wind_speed, spread)
end

"""
    EdgeSample(table, weather, corridor, stage, lateral, step, share, time)

[`EdgeSample`](@ref) at `share` (0 to 1) along edge `step` of node (`stage`, `lateral`) of
`corridor` at `time` [h], on the course the edge starts on, in `weather`.
"""
function EdgeSample(table::PerformanceTable, weather, corridor, stage, lateral, step,
        share, time)
    lat, lon = edge_point(corridor, stage, lateral, next_lateral(corridor, lateral, step),
        share)
    return EdgeSample(table, wind(weather, lat, lon, time), waves(weather, lat, lon, time),
        corridor.edge_course[stage, lateral, step], is_daylight(lon, time),
        wind_spread(weather, time))
end

"""
    edge_intervals(hours, sample_hours)

Number of intervals of at most `sample_hours` [h] between the [`EdgeSample`](@ref)s of an
edge sailed in `hours` [h].
"""
edge_intervals(hours, sample_hours) = max(1, ceil(Int, hours / sample_hours))

"""
    trapezoid_weight(k, count)

Weight of the `k`-th of `count` equally spaced samples in the trapezoidal mean over them.
"""
trapezoid_weight(k, count) = (k == 1 || k == count ? 0.5 : 1.0) / (count - 1)

"""
    held_speed(table, speed_index, sample)

Highest routing speed number up to `speed_index` of the [`RouteTable`](@ref) `table`
that the ship can hold at the [`EdgeSample`](@ref) `sample` with the rig stowed, or with
a kite flying where it can, with the [`expected_fuels`](@ref) and chance of flying there;
speed number 0 if it cannot hold the lowest.
"""
function held_speed(table::RouteTable, speed_index, sample::EdgeSample)
    for i in speed_index:-1:1
        flown, stowed, chance = expected_fuels(table, i, sample)
        (isfinite(stowed) || (isfinite(flown) && chance > 0)) &&
            return i, flown, stowed, chance
    end
    return 0, Inf, Inf, 0.0
end

"nodes of the three-point Gauss rule for a standard normal variable, and their weights"
const SPREAD_NODES, SPREAD_WEIGHTS = (-sqrt(3.0), 0.0, sqrt(3.0)), (1 / 6, 2 / 3, 1 / 6)

"""
    expected_fuels(table, speed_index, sample)

Fuel power [W] with the rig flown and with any kite stowed at routing speed number
`speed_index` of the [`RouteTable`](@ref) `table`, and the chance a kite can stay up there,
over the error of the wind speed of the [`EdgeSample`](@ref) `sample`. A kite that cannot
stay up in one of the winds burns the stowed fuel there.
"""
function expected_fuels(table::RouteTable, speed_index, sample::EdgeSample)
    flown, stowed = edge_fuels(table, speed_index, sample.condition)
    performance, speed = table.table, table.speeds[speed_index]
    (; spread, wind_speed) = sample
    spread > 0 || return flown, stowed, Float64(kite_aloft(performance, speed,
        sample.headwind, sample.crosswind))
    expected_flown, expected_stowed, chance = 0.0, 0.0, 0.0
    for (node, weight) in zip(SPREAD_NODES, SPREAD_WEIGHTS)
        wind = max(wind_speed + node * spread, 0.0)
        scale = wind_speed > 0 ? wind / wind_speed : 1.0
        condition = with_wind(performance, sample.condition, wind)
        node_flown, node_stowed = edge_fuels(table, speed_index, condition)
        isfinite(node_stowed) || (node_stowed = stowed)
        up = isfinite(node_flown) && kite_aloft(performance, speed,
            scale * sample.headwind, scale * sample.crosswind)
        expected_stowed += weight * node_stowed
        expected_flown += weight * (up ? node_flown : node_stowed)
        chance += weight * up
    end
    return expected_flown, expected_stowed, chance
end

"""
    SailedPoint

One [`EdgeSample`](@ref) of an edge as sailed, with what a kite needs to know of it.
"""
struct SailedPoint
    "true wind at the kite's reference height from ahead [m/s]"
    headwind::Float64
    "true wind at the kite's reference height from abeam [m/s]"
    crosswind::Float64
    "sea condition there"
    condition::SeaCondition
    "whether the sun is up there"
    daylight::Bool
    "routing speed number held there; 0 where not even the lowest can be held"
    speed_index::Int
    "fuel power with the rig flown at the held speed [W]; on an uncertain wind its expected
    value, the stowed fuel where the kite proves unable to stay up"
    flown::Float64
    "fuel power with the rig stowed at the held speed [W]; `Inf` where only a flying kite
    holds it"
    stowed::Float64
    "hours of the edge the point stands for [h]"
    hours::Float64
    "time the ship reaches the point [h]"
    time::Float64
    "chance a kite can stay up there [-]; 0 or 1 where the wind is taken as known"
    chance::Float64
end

"""
    SailedPoint(sample, held, flown, stowed, hours, time, chance)

[`SailedPoint`](@ref) of the [`EdgeSample`](@ref) `sample`.
"""
SailedPoint(sample::EdgeSample, held, flown, stowed, hours, time, chance) =
    SailedPoint(sample.headwind, sample.crosswind, sample.condition, sample.daylight,
        held, flown, stowed, hours, time, chance)

"""
    SailedPoint(table, sample, speed_index, distance, time)

[`SailedPoint`](@ref) of `sample` at commanded routing speed number `speed_index` of
`table`, at the [`held_speed`](@ref), standing for `distance` [m] of the edge, reached at
`time` [h].
"""
function SailedPoint(table::RouteTable, sample::EdgeSample, speed_index, distance, time)
    held, flown, stowed, chance = held_speed(table, speed_index, sample)
    hours = held == 0 ? Inf : distance / table.speeds[held] / 3600
    return SailedPoint(sample, held, flown, stowed, hours, time, chance)
end

"""
    sail_edge!(points, start, table, weather, corridor, stage, lateral, step, time,
               speed_index, sample_hours=ROUTER_SETTINGS[].edge_sample_hours)

Fill `points` with the [`SailedPoint`](@ref)s of edge `step` of node (`stage`, `lateral`)
left at `time` [h] at commanded routing speed number `speed_index` of `table`, the first
from the [`EdgeSample`](@ref) `start`: equally spaced in distance, at most
`sample_hours` [h] apart at the commanded speed, each standing for its trapezoidal share
of the distance at the speed held there, and each taken when the ship would reach it at
the speed held at the point before. Returns the hours of the edge, the sum of those
shares, or `Inf` if a point cannot hold the lowest routing speed.
"""
function sail_edge!(points, start, table::RouteTable, weather, corridor, stage, lateral,
        step, time, speed_index, sample_hours=ROUTER_SETTINGS[].edge_sample_hours)
    distance = corridor.edge_length[stage, lateral, step]
    intervals = edge_intervals(distance / table.speeds[speed_index] / 3600, sample_hours)
    resize!(points, intervals + 1)
    points[1] = SailedPoint(table, start, speed_index,
        trapezoid_weight(1, intervals + 1) * distance, time)
    hours, sample_time = points[1].hours, time
    for k in 1:intervals
        isfinite(hours) || return Inf
        sample_time += distance / intervals / table.speeds[points[k].speed_index] / 3600
        sample = EdgeSample(table.table, weather, corridor, stage, lateral, step,
            k / intervals, sample_time)
        points[k + 1] = SailedPoint(table, sample, speed_index,
            trapezoid_weight(k + 1, intervals + 1) * distance, sample_time)
        hours += points[k + 1].hours
    end
    return hours
end

"""
    EdgeTally

A way through the [`SailedPoint`](@ref)s of an edge: fuel and rig cost [USD], fuel
energy [J], hours of kite flight [h], kite launches and landings outside the landing
limits.
"""
struct EdgeTally
    cost::Float64
    energy::Float64
    flight_hours::Float64
    launches::Int
    forced_landings::Int
end

"no way through an edge"
const NO_TALLY = EdgeTally(Inf, 0.0, 0.0, 0, 0)

"""
    extend(tally, power, hours, wear, mode, launched, prices, cycle_cost)

`tally` followed by `hours` [h] at fuel `power` [W] with rig `wear` [USD/h] in kite
`mode`, after a launch at `cycle_cost` [USD] if `launched`.
"""
function extend(tally::EdgeTally, power, hours, wear, mode, launched, prices, cycle_cost)
    energy = hours != 0 ? power * hours * 3600 : 0.0
    return EdgeTally(tally.cost + energy * prices.fuel + wear * hours +
                     launched * cycle_cost, tally.energy + energy,
        tally.flight_hours + (mode == FLYING) * hours, tally.launches + launched,
        tally.forced_landings)
end

"""
    forced_landing(tally, cost)

`tally` followed by a landing outside the landing limits at `cost` [USD].
"""
forced_landing(tally::EdgeTally, cost) = EdgeTally(tally.cost + cost, tally.energy,
    tally.flight_hours, tally.launches, tally.forced_landings + 1)

"the cheaper of two [`EdgeTally`](@ref)s, the first if they cost the same"
cheaper(a::EdgeTally, b::EdgeTally) = a.cost <= b.cost ? a : b

"""
    kite_passage(table, points, aloft, prices)

Cheapest ways through the [`SailedPoint`](@ref)s of an edge on the [`RouteTable`](@ref)
`table` that end with the kite down and with it aloft, for a kite aloft before the first
point if `aloft`, as [`EdgeTally`](@ref)s. At each point a kite down burns the stowed
fuel, and cannot be down where only a flying kite holds the speed; where
[`kite_aloft`](@ref) allows, a kite aloft flies, and where [`kite_launchable`](@ref)
allows, a kite down may launch. A kite aloft can come down at any point: its cost is part
of the launch, and outside [`kite_landable`](@ref) it is a [`forced_landing`](@ref). Wings
and rotors stay down, burning their fuel with the rig standing.
"""
function kite_passage(table::RouteTable, points, aloft, prices)
    down, up = kite_start(aloft)
    for point in points
        down, up = kite_step(table, point, down, up, prices)
    end
    return down, up
end

"tallies of a kite down and aloft before the first point of an edge, left `aloft` or down"
function kite_start(aloft)
    start = EdgeTally(0.0, 0.0, 0.0, 0, 0)
    return aloft ? (NO_TALLY, start) : (start, NO_TALLY)
end

"""
    kite_step(table, point, down, up, prices)

The way down and the way aloft through [`SailedPoint`](@ref) `point` after the
[`EdgeTally`](@ref)s
`down` and `up`, as in [`kite_passage`](@ref), with whether the way down lands the kite
there, whether the way aloft launches it there and whether a landing there is forced.
"""
function kite_step(table::RouteTable, point, down, up, prices)
    speed = table.speeds[point.speed_index]
    (; headwind, crosswind, daylight, condition) = point
    forced = !kite_landable(table.table, speed, headwind, crosswind, condition)
    landing = forced ? forced_landing(up, table.table.forced_landing_cost) : up
    landed = landing.cost < down.cost
    next_down = extend(landed ? landing : down, point.stowed, point.hours, 0.0, STOWED,
        false, prices, table.table.cycle_cost)
    stays = point.chance > 0 ?
            aloft_tally(table.table, up, point, false, prices) : NO_TALLY
    launches = kite_launchable(table.table, speed, headwind, crosswind, condition,
        daylight) ? aloft_tally(table.table, down, point, true, prices) : NO_TALLY
    launched = launches.cost < stays.cost
    return next_down, launched ? launches : stays, landed, launched, forced
end

"""
    kite_flights(table, points, aloft, ends_aloft, prices)

The way [`kite_passage`](@ref) takes through the [`SailedPoint`](@ref)s `points` from a
kite left `aloft` to the end state `ends_aloft`, or to the other end state if that one
cannot be reached: for each point whether the kite flies there, launches at it and lands
at it, and whether that landing was forced.
"""
function kite_flights(table::RouteTable, points, aloft, ends_aloft, prices)
    down, up = kite_start(aloft)
    landed, launched, forced = (falses(length(points)) for _ in 1:3)
    for (k, point) in enumerate(points)
        down, up, landed[k], launched[k], forced[k] =
            kite_step(table, point, down, up, prices)
    end
    state_up = ends_aloft ? isfinite(up.cost) : !isfinite(down.cost)
    flights = Vector{@NamedTuple{flying::Bool, launched::Bool, landed::Bool,
        forced::Bool}}(undef, length(points))
    for k in reverse(eachindex(points))
        launch = state_up && launched[k]
        landing = !state_up && landed[k]
        flights[k] = (; flying=state_up, launched=launch, landed=landing,
            forced=landing && forced[k])
        state_up = state_up ? !launched[k] : landed[k]
    end
    return flights
end

"""
    kite_way(table, points, aloft, ends_aloft, prices)

Whether the kite is up at each of `points` on the way of [`kite_flights`](@ref).
"""
function kite_way(table::RouteTable, points, aloft, ends_aloft, prices)
    flights = kite_flights(table, points, aloft, ends_aloft, prices)
    return [flight.flying for flight in flights]
end

"share (0 to 1) of an edge sampled at `count` points that lies before point `k`"
point_share(k, count) = count == 1 ? 0.0 : (k - 1) / (count - 1)

"the state in `targets`, those along an edge, nearest `share` (0 to 1) of the edge"
target_at(targets, share) = targets[1 + round(Int, share * (length(targets) - 1))]

"""
    held_kite_passage(table, points, aloft, targets, prices)

The way through `points` of a kite left `aloft` or down that stays up or down as
`targets`, the state wanted along the edge, says wherever the limits of [`kite_step`](@ref)
allow it: the tallies of the way down and aloft, one of them `NO_TALLY`, and whether the
kite is up at each point.
"""
function held_kite_passage(table::RouteTable, points, aloft, targets, prices)
    down, up = kite_start(aloft)
    states = Vector{Bool}(undef, length(points))
    for (k, point) in enumerate(points)
        share = point_share(k, length(points))
        wanted = target_at(targets, share)
        next_down, next_up = kite_step(table, point, down, up, prices)
        states[k] = wanted ? isfinite(next_up.cost) : !isfinite(next_down.cost)
        down, up = states[k] ? (NO_TALLY, next_up) : (next_down, NO_TALLY)
    end
    return down, up, states
end

"""
    aloft_tally(table, tally, point, launched, prices)

`tally` followed by the [`SailedPoint`](@ref) `point` with the kite flying, `NO_TALLY` where
it cannot. If `launched`, the point starts with the launch and landing of the flight at
stowed fuel; where they outlast the point, the excess comes off its flying hours, which then
count negative against the hours that follow. Wear is paid for the chance the kite flies.
"""
function aloft_tally(table::PerformanceTable, tally, point, launched, prices)
    isfinite(point.flown) && point.flown !== point.stowed || return NO_TALLY
    handling = launched ? table.handling_hours : 0.0
    handled = extend(tally, point.stowed, handling, 0.0, STOWED, launched, prices,
        table.cycle_cost)
    return extend(handled, point.flown, point.hours - handling,
        table.wear_cost * point.chance, FLYING, false, prices, table.cycle_cost)
end

"""
    summary_mode(tally, hours)

Mode in which the kite spent the most of the `hours` [h] of an edge.
"""
summary_mode(tally::EdgeTally, hours) =
    tally.flight_hours >= hours - tally.flight_hours ? FLYING : STOWED

"""
    SailedEdge

An edge sailed at one commanded speed.
"""
struct SailedEdge
    "edge hours [h]; `Inf` where a point cannot hold the lowest speed, `NaN` unsailed"
    hours::Float64
    "cheapest way through the edge that ends with the kite down"
    down::EdgeTally
    "cheapest way through the edge that ends with the kite aloft"
    up::EdgeTally
    "highest routing speed number whose command sails it the same; 0 where unknown"
    same_through::Int
end

"an edge not sailed"
const UNSAILED = SailedEdge(NaN, NO_TALLY, NO_TALLY, 0)

"""
    SailedEdge(table, points, hours, aloft, prices, through)

[`SailedEdge`](@ref) of `hours` [h] through the [`SailedPoint`](@ref)s `points` by
[`kite_passage`](@ref), for a kite aloft before it if `aloft`, sailing the same through
routing speed number `through`.
"""
function SailedEdge(table::RouteTable, points, hours, aloft, prices, through)
    isfinite(hours) || return SailedEdge(hours, NO_TALLY, NO_TALLY, 0)
    return SailedEdge(hours, kite_passage(table, points, aloft, prices)..., through)
end

"""
    unpowered(table, speed_index, condition)

Whether the engines cannot power routing speed number `speed_index` of the
[`RouteTable`](@ref) `table` in the [`SeaCondition`](@ref) `condition`, with the rig stowed
or flown.
"""
function unpowered(table::RouteTable, speed_index, condition::SeaCondition)
    flown, stowed = edge_fuels(table, speed_index, condition)
    return !isfinite(flown) && !isfinite(stowed)
end

"""
    same_through(table, points, speed_index, distance, sample_hours)

Highest routing speed number whose command sails the [`SailedPoint`](@ref)s `points` of an
edge of `distance` [m], sailed at commanded routing speed number `speed_index` with samples
at most `sample_hours` [h] apart, the same at the same sample points: `speed_index` unless
every point held a lower speed and each faster command up to that one is sampled alike and
powered at no point.
"""
function same_through(table::RouteTable, points, speed_index, distance, sample_hours)
    any(point -> point.speed_index == speed_index, points) && return speed_index
    intervals = edge_intervals(distance / table.speeds[speed_index] / 3600, sample_hours)
    for i in (speed_index + 1):length(table.speeds)
        edge_intervals(distance / table.speeds[i] / 3600, sample_hours) == intervals &&
            all(point -> unpowered(table, i, point.condition), points) || return i - 1
    end
    return length(table.speeds)
end

"""
    nearest_lateral(corridor, stage, lat, lon)

Lateral node of `stage` closest to the point (`lat`, `lon`).
"""
nearest_lateral(corridor::Corridor, stage, lat, lon) =
    argmin(j -> distance(lat, lon, corridor.lat[stage, j], corridor.lon[stage, j]),
        axes(corridor.lat, 2))

"""
    RouteWorkspace

States of the routing dynamic programme, indexed (lateral, time bin, kite down 1 or aloft
2, stage).
"""
struct RouteWorkspace
    "objective of the best arrival [USD]"
    cost::Array{Float64, 4}
    "hours from departure to the arrival [h]"
    elapsed::Array{Float64, 4}
    "fuel energy up to the arrival [J]"
    energy::Array{Float64, 4}
    "hours of kite flight up to the arrival [h]"
    flight_hours::Array{Float64, 4}
    "kite launches up to the arrival"
    launches::Array{Int32, 4}
    "kite landings outside the landing limits up to the arrival"
    forced_landings::Array{Int32, 4}
    "state of the previous stage, as the linear index of (bin, lateral, aloft)"
    parent::Array{Int32, 4}
    "routing speed number of the edge into the state"
    speed_index::Array{Int8, 4}
    "mode of the edge into the state"
    mode::Array{Int8, 4}
    "the points of the edge in hand"
    points::Vector{SailedPoint}
    "values of the latest [`CostToGo`](@ref), grown to the most time knots asked of it"
    to_go_values::Base.RefValue{Array{Float64, 4}}
    "edges sailed from a node with the kite down for its state aloft at the same time"
    shared::Vector{SailedEdge}
    "index in `shared` before the edges of each time bin, -1 where it holds none"
    shared_from::Vector{Int}
end

"""
    RouteWorkspace(lateral_count, bins, stage_count)

Workspace for corridors of `lateral_count` nodes per stage, `bins` time bins and up to
`stage_count` stages.
"""
function RouteWorkspace(lateral_count, bins, stage_count)
    shape = (lateral_count, bins, 2, stage_count)
    return RouteWorkspace(fill(Inf, shape), zeros(shape), zeros(shape), zeros(shape),
        zeros(Int32, shape), zeros(Int32, shape), zeros(Int32, shape), zeros(Int8, shape),
        zeros(Int8, shape), SailedPoint[], Ref(zeros(lateral_count, 0, 2, stage_count)),
        SailedEdge[], fill(-1, bins))
end

"workspaces not in use, by (lateral count, time bins), shared by the threads that route"
const FREE_WORKSPACES = Dict{NTuple{2, Int}, Vector{RouteWorkspace}}()
const WORKSPACE_LOCK = ReentrantLock()

"""
    acquire_workspace(lateral_count, bins, stage_count)

A free [`RouteWorkspace`](@ref) of this shape, or a new one; hand it back with
[`release_workspace`](@ref).
"""
function acquire_workspace(lateral_count, bins, stage_count)
    workspace = @lock WORKSPACE_LOCK begin
        free = get!(Vector{RouteWorkspace}, FREE_WORKSPACES, (lateral_count, bins))
        isempty(free) ? nothing : pop!(free)
    end
    isnothing(workspace) || size(workspace.cost, 4) < stage_count || return workspace
    return RouteWorkspace(lateral_count, bins, stage_count)
end

"""
    release_workspace(workspace)

Return `workspace` to the free workspaces.
"""
release_workspace(workspace::RouteWorkspace) = @lock WORKSPACE_LOCK push!(
    FREE_WORKSPACES[size(workspace.cost)[1:2]], workspace)

"commanded speeds of the search a [`CostToGo`](@ref) skips between its own, plus one"
const COST_TO_GO_SPEED_STRIDE = 2

"Indices of every `stride`-th of `count` ascending speeds, ending at the fastest"
commanded_speeds(count, stride) = (1 + (count - 1) % stride):stride:count

"longest time between the weather samples along an edge of a [`CostToGo`](@ref) [h]"
const COST_TO_GO_SAMPLE_HOURS = 6.0

"""
    CostToGo

Estimate of the objective [USD] from a state to the destination, from a coarser programme:
it can lie on either side of the true value. Called on (lateral, aloft 1 or 2, stage,
hours after departure), interpolating in time; `NaN` where no path was found although
the time was searched, `Inf` beyond the times searched.
"""
struct CostToGo
    "objective to the destination [USD], lateral × knot × aloft × stage"
    values::Array{Float64, 4}
    "time knots in use"
    knots::Int
    "time between the knots [h]"
    step::Float64
end

CostToGo(values::Array{Float64, 4}, step) = CostToGo(values, size(values, 2), step)

function (to_go::CostToGo)(lateral, aloft, stage, time)
    position = time / to_go.step + 1
    knot = floor(Int, position)
    knot < to_go.knots || return Inf
    @inbounds lower, upper = to_go.values[lateral, knot, aloft, stage],
    to_go.values[lateral, knot + 1, aloft, stage]
    isfinite(lower) && isfinite(upper) && return lower + (position - knot) * (upper - lower)
    isfinite(lower) && return lower
    isfinite(upper) && return upper
    return isnan(lower) || isnan(upper) ? NaN : Inf
end

"""
    CostToGo(workspace, corridor, table, weather, departure; time_cost, first_stage,
             coastal_penalty)

[`CostToGo`](@ref) of a passage leaving at `departure` [h], held in `workspace`, by a
backward programme over the states at each stage that a ship can reach between its highest
and lowest routing speed, at the knots of `ROUTER_SETTINGS`, on every
`COST_TO_GO_SPEED_STRIDE`-th speed the search commands.
"""
function CostToGo(workspace::RouteWorkspace, corridor::Corridor, table::RouteTable, weather,
        departure; time_cost, first_stage, coastal_penalty)
    stage_count, lateral_count = size(corridor.lat)
    along = corridor.along_centre
    slowest, fastest = first(table.speeds), last(table.speeds)
    (; to_go_step) = ROUTER_SETTINGS[]
    knots = ceil(Int, (last(along) / slowest / 3600 + REACH_SLACK) / to_go_step) + 2
    to_go = CostToGo(cleared_to_go_values!(workspace, knots), knots, to_go_step)
    to_go.values[centre_index(corridor), 1:knots, 1, stage_count] .= 0.0
    prices = (; fuel=table.table.ship.fuel.price, time=time_cost)
    for stage in (stage_count - 1):-1:first_stage, lateral in 1:lateral_count
        corridor.water[stage, lateral] || continue
        sailed = along[stage] - along[first_stage]
        earliest = SHORTEST_SAILED_SHARE * sailed / fastest / 3600
        latest = sailed / slowest / 3600 + REACH_SLACK
        for knot in max(1, floor(Int, earliest / to_go_step)):min(knots,
            ceil(Int, latest / to_go_step) + 1)

            fill_knot!(to_go, workspace.points, corridor, table, weather, departure, prices,
                coastal_penalty, stage, lateral, knot)
        end
    end
    return to_go
end

"""
    cleared_to_go_values!(workspace, knots)

The [`CostToGo`](@ref) values of `workspace`, with room for `knots` time knots, all `Inf`.
"""
function cleared_to_go_values!(workspace::RouteWorkspace, knots)
    lateral_count, held, aloft, stage_count = size(workspace.to_go_values[])
    held < knots &&
        (workspace.to_go_values[] = Array{Float64}(undef, lateral_count, knots, aloft,
            stage_count))
    return fill!(workspace.to_go_values[], Inf)
end

"hours a [`CostToGo`](@ref) searches beyond the arrival at the lowest routing speed [h]"
const REACH_SLACK = 96.0

"least distance sailed to a stage, as a share of the distance along the centre line [-]"
const SHORTEST_SAILED_SHARE = 0.8

"""
    fill_knot!(to_go, points, corridor, table, weather, departure, prices, coastal_penalty,
               stage, lateral, knot)

Set the values of `to_go` at node (`stage`, `lateral`) and `knot`, kite down and aloft,
from those of the next stage, with `points` to hold those of the edges.
"""
function fill_knot!(to_go, points, corridor, table, weather, departure, prices,
        coastal_penalty, stage, lateral, knot)
    time = (knot - 1) * to_go.step
    lat, lon = corridor.lat[stage, lateral], corridor.lon[stage, lateral]
    node_wind = wind(weather, lat, lon, departure + time)
    node_waves = waves(weather, lat, lon, departure + time)
    daylight = is_daylight(lon, departure + time)
    kite = has_kite(table)
    speed_stride = COST_TO_GO_SPEED_STRIDE * ROUTER_SETTINGS[].search_speed_stride
    sample_hours = max(COST_TO_GO_SAMPLE_HOURS, corridor.sample_hours[stage])
    best_down, best_up = Inf, Inf
    for step in 1:step_count(corridor)
        isnan(corridor.edge_course[stage, lateral, step]) && continue
        next = next_lateral(corridor, lateral, step)
        penalty = edge_penalty(corridor, stage, next, coastal_penalty)
        start = EdgeSample(table.table, node_wind, node_waves,
            corridor.edge_course[stage, lateral, step], daylight,
            wind_spread(weather, departure + time))
        distance = corridor.edge_length[stage, lateral, step]
        through = 0
        for speed_index in commanded_speeds(length(table.speeds), speed_stride)
            speed_index <= through && continue
            hours = sail_edge!(points, start, table, weather, corridor, stage, lateral,
                step, departure + time, speed_index, sample_hours)
            isfinite(hours) || continue
            arrival = (; penalty, hours, prices, next, stage=stage + 1, time=time + hours)
            best_down = min(best_down, best_arrival(to_go, table, points, false, arrival))
            kite && (best_up = min(best_up,
                best_arrival(to_go, table, points, true, arrival)))
            through = same_through(table, points, speed_index, distance,
                sample_hours)
        end
    end
    to_go.values[lateral, knot, 1, stage] = isfinite(best_down) ? best_down : NaN
    kite && (to_go.values[lateral, knot, 2, stage] = isfinite(best_up) ? best_up : NaN)
end

"""
    best_arrival(to_go, table, points, aloft, arrival)

Least objective [USD] to the destination through the [`SailedPoint`](@ref)s `points` of
an edge for a kite aloft before it if `aloft`, then by `to_go` from the node and time of
`arrival`.
"""
function best_arrival(to_go, table, points, aloft, (; penalty, hours, prices, next, stage,
        time))
    down, up = kite_passage(table, points, aloft, prices)
    best = Inf
    for (tally, next_aloft) in ((down, 1), (up, 2))
        isfinite(tally.cost) || continue
        ahead = to_go(next, next_aloft, stage, time)
        isnan(ahead) && continue
        best = min(best, edge_objective(penalty, tally.cost, hours, prices) + ahead)
    end
    return best
end

"longest passage a route searches [h]"
const MAX_LEG_HOURS = 1200.0

"""
    route(corridor, table, weather, departure; time_cost, first_stage=1, first_lateral,
          first_aloft=false, coastal_penalty=1.0)

Weather routing by forward dynamic programming over (stage, lateral node, arrival time
bin, kite aloft) on the routing speeds of the [`RouteTable`](@ref) `table`, or of a
[`PerformanceTable`](@ref). Minimises fuel cost plus rig wear and kite launches plus
`time_cost` [USD/h] times duration for a departure at `departure` [h]; times in hours.
Each edge is sailed at a commanded speed by [`sail_edge!`](@ref), slowing where the
engine cannot hold it, with the kite managed along it by [`kite_passage`](@ref); it is
infeasible only where the lowest routing speed cannot be held. The passage starts at node
`first_lateral` of stage `first_stage` with the kite aloft if `first_aloft`. Edges into
nodes near land cost `coastal_penalty` more in the objective, not in the fuel and time the
leg reports.

The time bins, the speeds commanded and the states searched follow `ROUTER_SETTINGS`: those
within a margin of a [`CostToGo`](@ref), wider where that leaves no path within the margin,
then all of them. A [`final_pass`](@ref) then refines the speeds along the path found.
Returns `nothing` if no path arrives within `MAX_LEG_HOURS`.
"""
function route(corridor::Corridor, table::RouteTable, weather, departure; time_cost,
        first_stage=1, first_lateral=centre_index(corridor), first_aloft=false,
        coastal_penalty=1.0)
    (; time_step) = ROUTER_SETTINGS[]
    options = (; time_step, time_cost, first_stage, first_lateral, first_aloft,
        coastal_penalty, speed_stride=ROUTER_SETTINGS[].search_speed_stride)
    workspace = acquire_workspace(size(corridor.lat, 2),
        ceil(Int, MAX_LEG_HOURS / time_step), size(corridor.lat, 1))
    try
        to_go = CostToGo(workspace, corridor, table, weather, departure; time_cost,
            first_stage, coastal_penalty)
        estimate = to_go(first_lateral, first_aloft + 1, first_stage, 0.0)
        leg = searched_leg(workspace, corridor, table, weather, departure, to_go,
            (1 .+ margins_searched(table, ROUTER_SETTINGS[])) .* estimate; options...)
        isnothing(leg) && return nothing
        return final_pass(leg, corridor, table, weather, departure; time_cost, first_stage,
            first_aloft, coastal_penalty)
    finally
        release_workspace(workspace)
    end
end

route(corridor::Corridor, table::PerformanceTable, weather, departure; options...) =
    route(corridor, RouteTable(table), weather, departure; options...)

"The margins of `settings` that the search of a ship with `table` uses [-]"
margins_searched(table::RouteTable, settings::RouterSettings) =
    has_kite(table) ? settings.kite_search_margins : settings.search_margins

"""
    PassageBand(elapsed, width)

The states within `width` [h] of the hours `elapsed` at each stage of a path.
"""
struct PassageBand
    "hours from departure at each stage of the path [h]"
    elapsed::Vector{Float64}
    "half-width of the band [h]"
    width::Float64
end

"""
    leg_corridor(leg)

[`Corridor`](@ref) of one node per stage along the path of `leg`, nowhere near a coast.
"""
function leg_corridor(leg::Leg)
    stage_count = length(leg.path)
    lat = reshape([point[1] for point in leg.path], stage_count, 1)
    lon = reshape([point[2] for point in leg.path], stage_count, 1)
    edge_length = zeros(stage_count - 1, 1, 2MAX_LATERAL_STEP + 1)
    edge_course = fill(NaN, stage_count - 1, 1, 2MAX_LATERAL_STEP + 1)
    for i in 1:(stage_count - 1)
        edge_length[i, 1, STRAIGHT_ON] = distance(lat[i], lon[i], lat[i + 1], lon[i + 1])
        edge_course[i, 1, STRAIGHT_ON] = bearing(lat[i], lon[i], lat[i + 1], lon[i + 1])
    end
    return Corridor(lat, lon, trues(stage_count, 1), edge_length, edge_course, 0.0,
        falses(stage_count, 1), along_centre_line(lat, lon), MAX_LATERAL_STEP, 0.0,
        zeros(stage_count))
end

"""
    path_corridor(leg, corridor, first_stage)

[`Corridor`](@ref) of one node per stage along the path of `leg` through `corridor`, stage 1
being its `first_stage`.
"""
function path_corridor(leg::Leg, corridor::Corridor, first_stage)
    stage_count = length(leg.path)
    lat = reshape([point[1] for point in leg.path], stage_count, 1)
    lon = reshape([point[2] for point in leg.path], stage_count, 1)
    near_coast = falses(stage_count, 1)
    edge_length = zeros(stage_count - 1, 1, 2MAX_LATERAL_STEP + 1)
    edge_course = fill(NaN, stage_count - 1, 1, 2MAX_LATERAL_STEP + 1)
    for i in 1:stage_count
        stage = first_stage + i - 1
        lateral = nearest_lateral(corridor, stage, lat[i], lon[i])
        near_coast[i] = corridor.near_coast[stage, lateral]
        i == stage_count && break
        next = nearest_lateral(corridor, stage + 1, lat[i + 1], lon[i + 1])
        step = lateral_step(corridor, lateral, next)
        edge_length[i, 1, STRAIGHT_ON] = corridor.edge_length[stage, lateral, step]
        edge_course[i, 1, STRAIGHT_ON] = corridor.edge_course[stage, lateral, step]
    end
    return Corridor(lat, lon, trues(stage_count, 1), edge_length, edge_course,
        corridor.track_length, near_coast, along_centre_line(lat, lon), MAX_LATERAL_STEP,
        0.0, zeros(stage_count))
end

"""
    final_pass(leg, corridor, table, weather, departure; time_cost, first_stage,
               first_aloft, coastal_penalty)

The cheaper of `leg` and the [`route_pass`](@ref) along its path at all speeds of `table`,
on the bins and within the band in time of `ROUTER_SETTINGS`.
"""
function final_pass(leg::Leg, corridor, table, weather, departure; time_cost, first_stage,
        first_aloft, coastal_penalty)
    (; final_time_step, final_time_band) = ROUTER_SETTINGS[]
    workspace = acquire_workspace(1, ceil(Int, MAX_LEG_HOURS / final_time_step),
        length(leg.path))
    try
        band = PassageBand([point[3] for point in leg.path], final_time_band)
        refined = route_pass(workspace, path_corridor(leg, corridor, first_stage), table,
            weather, departure, band; time_cost, time_step=final_time_step, first_stage=1,
            first_lateral=1, first_aloft, coastal_penalty, speed_stride=1)
        return isnothing(refined) || refined.objective > leg.objective ? leg : refined
    finally
        release_workspace(workspace)
    end
end

"""
    searched_leg(workspace, corridor, table, weather, departure, to_go, limits; options...)

The [`Leg`](@ref) of the first [`route_pass`](@ref) under `limits` [USD] that ends within
its limit, else of a pass over all states, which is `nothing` if no path arrives.
"""
function searched_leg(workspace, corridor, table, weather, departure, to_go, limits;
        options...)
    for limit in limits
        leg = route_pass(workspace, corridor, table, weather, departure, to_go, limit;
            options...)
        !isnothing(leg) && leg.objective <= limit && return leg
    end
    return route_pass(workspace, corridor, table, weather, departure; options...)
end

"""
    route_pass(workspace, corridor, table, weather, departure, to_go=nothing, limit=Inf;
               time_cost, time_step, first_stage, first_lateral, first_aloft,
               coastal_penalty, speed_stride)

The dynamic programme of [`route`](@ref) in `workspace`, whose bins are `time_step` [h]
long, commanding the [`commanded_speeds`](@ref) of `table` at `speed_stride`, skipping
states and commanded edges outside the [`PassageBand`](@ref) `to_go`, or, with a
[`CostToGo`](@ref) `to_go`, those whose objective plus it exceeds `limit` [USD]. Returns the
[`Leg`](@ref) or `nothing`.
"""
function route_pass(workspace::RouteWorkspace, corridor::Corridor, table::RouteTable,
        weather, departure, to_go=nothing, limit=Inf; time_cost, time_step, first_stage,
        first_lateral, first_aloft, coastal_penalty, speed_stride)
    ship_table = table.table
    (; speeds) = table
    (; cost, elapsed) = workspace
    stage_count, lateral_count = size(corridor.lat)
    bins = size(cost, 2)
    prices = (; fuel=ship_table.ship.fuel.price, time=time_cost)
    fill!(view(cost, :, :, :, first_stage:stage_count), Inf)
    start_state!(workspace, (first_lateral, 1, first_aloft + 1, first_stage))
    commanded = commanded_speeds(length(speeds), speed_stride)
    for stage in first_stage:(stage_count - 1), lateral in 1:lateral_count
        corridor.water[stage, lateral] || continue
        sample_hours = max(ROUTER_SETTINGS[].edge_sample_hours,
            corridor.sample_hours[stage])
        lat, lon = corridor.lat[stage, lateral], corridor.lon[stage, lateral]
        empty!(workspace.shared)
        fill!(workspace.shared_from, -1)
        for aloft in 1:2, bin in 1:bins
            here = cost[lateral, bin, aloft, stage]
            isfinite(here) || continue
            time = elapsed[lateral, bin, aloft, stage]
            within_limit(to_go, limit, here, lateral, aloft, stage, time) || continue
            state = (lateral, bin, aloft, stage)
            sharing = sharing_edges!(workspace, state, to_go, limit,
                step_count(corridor) * length(commanded))
            node_wind = wind(weather, lat, lon, departure + time)
            node_waves = waves(weather, lat, lon, departure + time)
            daylight = is_daylight(lon, departure + time)
            for step in 1:step_count(corridor)
                isnan(corridor.edge_course[stage, lateral, step]) && continue
                next = next_lateral(corridor, lateral, step)
                penalty = edge_penalty(corridor, stage, next, coastal_penalty)
                distance = corridor.edge_length[stage, lateral, step]
                start = EdgeSample(ship_table, node_wind, node_waves,
                    corridor.edge_course[stage, lateral, step], daylight,
                    wind_spread(weather, departure + time))
                through = 0
                for (slot, speed_index) in enumerate(commanded)
                    speed_index <= through && continue
                    commanded_hours = distance / speeds[speed_index] / 3600
                    edge_within_limit(to_go, limit,
                        here + penalty * time_cost * commanded_hours, next, stage + 1,
                        time + commanded_hours) || continue
                    shared = shared_slot(sharing, step, slot, length(commanded))
                    sailed = sailed_edge!(workspace, shared, aloft == 2, table, prices,
                        (; start, weather, corridor, stage, lateral, step, speed_index,
                            sample_hours, time=departure + time))
                    relax_sailed!(workspace, state, next, sailed, (; here, penalty,
                        speed_index), time_step, prices)
                    through = sailed.same_through
                end
            end
        end
    end
    objective, bin = findmin(view(cost, centre_index(corridor), :, 1, stage_count))
    isfinite(objective) || return nothing
    return traced_leg(workspace, corridor, table, (centre_index(corridor), bin, 1,
        stage_count), first_stage)
end

"""
    sharing_edges!(workspace, state, to_go, limit, edge_count)

Index in `workspace.shared` before the [`SailedEdge`](@ref)s of `state` (lateral, bin,
aloft, stage) for its state aloft, which then leaves the node at the same time and is
searched, room for `edge_count` edges being made for a kite down; -1 where there is no
such state.
"""
function sharing_edges!(workspace::RouteWorkspace, state, to_go, limit, edge_count)
    lateral, bin, aloft, stage = state
    aloft == 2 && return workspace.shared_from[bin]
    twin = (lateral, bin, 2, stage)
    here = workspace.cost[twin...]
    isfinite(here) && workspace.elapsed[twin...] == workspace.elapsed[state...] &&
        within_limit(to_go, limit, here, lateral, 2, stage, workspace.elapsed[twin...]) ||
        return -1
    from = workspace.shared_from[bin] = length(workspace.shared)
    append!(workspace.shared, Iterators.repeated(UNSAILED, edge_count))
    return from
end

"""
    shared_slot(sharing, step, slot, speed_count)

Index in `workspace.shared` of edge `step` at the commanded speed in place `slot` of
`speed_count`, for a state whose [`sharing_edges!`](@ref) gave `sharing`; 0 where that is
-1.
"""
shared_slot(sharing, step, slot, speed_count) =
    sharing < 0 ? 0 : sharing + (step - 1) * speed_count + slot

"""
    sailed_edge!(workspace, slot, aloft, table, prices, edge)

[`SailedEdge`](@ref) for a kite aloft before it if `aloft` of `edge`, which names the
arguments of [`sail_edge!`](@ref) other than the points and `table`. A state down fills
place `slot` of `workspace.shared` where it is not 0 with the edge for the state aloft,
which reads it there where it was sailed.
"""
function sailed_edge!(workspace::RouteWorkspace, slot, aloft, table::RouteTable, prices,
        edge)
    known = aloft && slot != 0 ? workspace.shared[slot] : UNSAILED
    isnan(known.hours) || return known
    (; points) = workspace
    (; start, weather, corridor, stage, lateral, step, time) = edge
    (; speed_index, sample_hours) = edge
    hours = sail_edge!(points, start, table, weather, corridor, stage, lateral, step, time,
        speed_index, sample_hours)
    through = isfinite(hours) ?
        same_through(table, points, speed_index, corridor.edge_length[stage, lateral, step],
            sample_hours) : 0
    !aloft && slot != 0 && (workspace.shared[slot] =
        SailedEdge(table, points, hours, true, prices, through))
    return SailedEdge(table, points, hours, aloft, prices, through)
end

"""
    relax_sailed!(workspace, state, next, sailed, edge, time_step, prices)

[`relax!`](@ref) the states of node `next` of the next stage, kite down and aloft, from
`state` by the [`SailedEdge`](@ref) `sailed`, where it arrives within the time bins of
`time_step` [h]; `edge` holds the objective `here` [USD] of `state`, the coastal `penalty`
and the commanded `speed_index`.
"""
function relax_sailed!(workspace::RouteWorkspace, state, next, sailed::SailedEdge, edge,
        time_step, prices)
    arrival = workspace.elapsed[state...] + sailed.hours
    arrival < size(workspace.cost, 2) * time_step || return
    next_bin = floor(Int, arrival / time_step) + 1
    edge = (; edge..., sailed.hours)
    relax!(workspace, state, (next, next_bin, 1), sailed.down, edge, prices)
    relax!(workspace, state, (next, next_bin, 2), sailed.up, edge, prices)
end

"""
    within_limit(to_go, limit, here, lateral, aloft, stage, time)
    edge_within_limit(to_go, limit, here, next, stage, time)

Whether a state of objective `here` [USD], or an edge that would reach the node `next` of
`stage` at `time` [h] for at least the objective `here`, lies in the [`PassageBand`](@ref)
`to_go`, or can stay within `limit` [USD] by the [`CostToGo`](@ref) `to_go`; always where
there is none or it found no path.
"""
within_limit(::Nothing, limit, here, lateral, aloft, stage, time) = true
within_limit(to_go::CostToGo, limit, here, lateral, aloft, stage, time) =
    !(here + to_go(lateral, aloft, stage, time) > limit)

edge_within_limit(::Nothing, limit, here, next, stage, time) = true
edge_within_limit(to_go::CostToGo, limit, here, next, stage, time) =
    !(here + min(to_go(next, 1, stage, time), to_go(next, 2, stage, time)) > limit)

within_limit(band::PassageBand, limit, here, lateral, aloft, stage, time) =
    in_band(band, stage, time)
edge_within_limit(band::PassageBand, limit, here, next, stage, time) =
    in_band(band, stage, time)

"whether `time` [h] lies within the [`PassageBand`](@ref) `band` at `stage`"
in_band(band::PassageBand, stage, time) = abs(time - band.elapsed[stage]) <= band.width

"""
    start_state!(workspace, start)

Make state `start` (lateral, bin, aloft, stage) of `workspace` the departure: no cost,
time, fuel or kite use so far.
"""
function start_state!(workspace::RouteWorkspace, start)
    workspace.cost[start...] = workspace.elapsed[start...] = 0.0
    workspace.energy[start...] = workspace.flight_hours[start...] = 0.0
    workspace.launches[start...] = workspace.forced_landings[start...] = 0
    workspace.mode[start...] = 0
end

"""
    edge_penalty(corridor, stage, next, coastal_penalty)

Factor on the objective of an edge into node (`stage + 1`, `next`): one plus the
`coastal_penalty` near land, one elsewhere.
"""
edge_penalty(corridor::Corridor, stage, next, coastal_penalty) =
    corridor.near_coast[stage + 1, next] ? 1 + coastal_penalty : 1.0

"""
    edge_objective(penalty, cost, hours, prices)

Objective [USD] of an edge of `hours` [h] with `cost` [USD] of fuel, rig wear and
launches, at the time `prices` and times the coastal `penalty`.
"""
edge_objective(penalty, cost, hours, prices) = penalty * (cost + prices.time * hours)

"""
    relax!(workspace, origin, arrival, tally, edge, prices)

Arrive at state `arrival` (lateral, bin, aloft) of the next stage from the state
`origin` by an `edge` of `hours` [h] passed as the [`EdgeTally`](@ref) `tally`, if that
is cheaper than the best arrival there so far.
"""
function relax!(workspace, origin, arrival, tally::EdgeTally, edge, prices)
    isfinite(tally.cost) || return
    (; cost, elapsed, energy, flight_hours, launches, forced_landings, parent, speed_index,
        mode) = workspace
    (; hours) = edge
    total = edge.here + edge_objective(edge.penalty, tally.cost, hours, prices)
    lateral, bin, origin_aloft, stage = origin
    arrival = (arrival..., stage + 1)
    total < cost[arrival...] || return
    cost[arrival...] = total
    elapsed[arrival...] = elapsed[origin...] + hours
    energy[arrival...] = energy[origin...] + tally.energy
    flight_hours[arrival...] = flight_hours[origin...] + tally.flight_hours
    launches[arrival...] = launches[origin...] + tally.launches
    forced_landings[arrival...] = forced_landings[origin...] + tally.forced_landings
    parent[arrival...] = ((origin_aloft - 1) * size(cost, 1) + lateral - 1) *
                         size(cost, 2) + bin
    speed_index[arrival...] = edge.speed_index
    mode[arrival...] = summary_mode(tally, hours)
end

"""
    traced_leg(workspace, corridor, table, final, first_stage)

[`Leg`](@ref) ending in state `final` (lateral, bin, aloft, stage) of `workspace`, its
path traced back to `first_stage`.
"""
function traced_leg(workspace::RouteWorkspace, corridor, table, final, first_stage)
    (; elapsed, parent, speed_index, mode) = workspace
    lateral_count, bins = size(parent, 1), size(parent, 2)
    lateral, bin, aloft, stage = final
    path = Vector{NTuple{5, Float64}}(undef, stage - first_stage + 1)
    aloft_path = Vector{Bool}(undef, stage - first_stage + 1)
    while stage >= first_stage
        state = (lateral, bin, aloft, stage)
        speed = stage == first_stage ? 0.0 : table.speeds[speed_index[state...]]
        path[stage - first_stage + 1] = (corridor.lat[stage, lateral],
            corridor.lon[stage, lateral], elapsed[state...], speed, mode[state...])
        aloft_path[stage - first_stage + 1] = aloft == 2
        stage == first_stage && break
        index = parent[state...] - 1
        bin = index % bins + 1
        index ÷= bins
        lateral = index % lateral_count + 1
        aloft = index ÷ lateral_count + 1
        stage -= 1
    end
    energy = workspace.energy[final...]
    return Leg(energy, energy * table.table.ship.fuel.price,
        workspace.flight_hours[final...], workspace.launches[final...],
        workspace.forced_landings[final...], elapsed[final...], workspace.cost[final...],
        path, aloft_path)
end

"""
    plan_values(plan, corridor, table, weather, departure, first_stage, prices; slows=false)

Least fuel and rig cost [USD] from each node of `plan`, which leaves stage `first_stage`
of `corridor` at `departure` [h], to its end with the kite stowed (column 1) or aloft
(column 2) at that node, sailing the plan's course, times and speeds in `weather` and
landing the kite by the end; `Inf` where that is not possible. With `slows`, an edge
`weather` stops at the plan's speed is sailed at the highest lower speed that passes, and
the hours lost are added at `prices.time`.
"""
function plan_values(plan::Leg, corridor, table::RouteTable, weather, departure,
        first_stage, prices; slows=false)
    nodes = length(plan.path)
    values = fill(Inf, nodes, 2)
    values[nodes, 1] = 0.0
    points = SailedPoint[]
    for i in (nodes - 1):-1:1
        ahead = (values[i + 1, 1], values[i + 1, 2])
        for aloft in (false, true)
            values[i, aloft + 1] = plan_edge_value(points, plan, corridor, table, weather,
                departure, first_stage, i, aloft, ahead, prices, slows)
        end
    end
    return values
end

"Cost [USD] of edge `i` of `plan` left `aloft` or stowed, and of the `ahead` it ends on."
function plan_edge_value(points, plan::Leg, corridor, table::RouteTable, weather, departure,
        first_stage, i, aloft, ahead, prices, slows)
    stage, lateral, step, time = plan_edge(plan, corridor, departure, first_stage, i)
    planned = plan.path[i + 1][4]
    slowest = slows ? 1 : searchsortedfirst(table.speeds, planned)
    hours, tally, ends_aloft, speed = sail_planned_edge!(points, table, weather, corridor,
        stage, lateral, step, time, planned, aloft, ahead, prices; slowest)
    isfinite(hours) || return Inf
    lost_hours = speed < planned ? hours - (plan.path[i + 1][3] - plan.path[i][3]) : 0.0
    return tally.cost + prices.time * lost_hours + ahead[ends_aloft + 1]
end

"Stage, lateral node, step and time [h] at which edge `i` of `plan` leaves its node."
function plan_edge(plan::Leg, corridor, departure, first_stage, i)
    stage = first_stage + i - 1
    lateral = nearest_lateral(corridor, stage, plan.path[i][1], plan.path[i][2])
    next = nearest_lateral(corridor, stage + 1, plan.path[i + 1][1], plan.path[i + 1][2])
    return stage, lateral, lateral_step(corridor, lateral, next),
    departure + plan.path[i][3]
end

"""
    sail_plan_edge!(points, plan, corridor, table, weather, departure, first_stage, i)

Fill `points` with edge `i` of `plan`, left at `departure` [h] from stage `first_stage` of
`corridor`, sailed at the plan's speed in `weather`. Returns its hours, `Inf` where blocked.
"""
function sail_plan_edge!(points, plan::Leg, corridor, table::RouteTable, weather, departure,
        first_stage, i)
    stage, lateral, step, time = plan_edge(plan, corridor, departure, first_stage, i)
    start = EdgeSample(table.table, weather, corridor, stage, lateral, step, 0.0, time)
    return sail_edge!(points, start, table, weather, corridor, stage, lateral, step, time,
        searchsortedfirst(table.speeds, plan.path[i + 1][4]))
end

"""
    sail_planned_edge!(points, table, weather, corridor, stage, lateral, step, time, speed,
                       aloft, ahead, prices; targets=nothing, slowest=1)

Sail edge `step` of node (`stage`, `lateral`) of `corridor`, left at `time` [h] with the
kite `aloft` or stowed, in the real `weather` at the planned `speed` [m/s], or at the
highest lower speed of the [`RouteTable`](@ref) `table`, down to index `slowest`, the ship
can hold with its kite as it is. The kite ends the edge in the state whose cost on the edge
plus `ahead`, the cost [USD] from the next node with the kite stowed and aloft, is least;
with `targets`, the
state the plan wants along the edge, it stays up or down as they say where it can
([`held_kite_passage`](@ref)). Returns the hours, the [`EdgeTally`](@ref), whether the kite
ends aloft and the speed sailed; `Inf` hours where no speed passes.
"""
function sail_planned_edge!(points, table::RouteTable, weather, corridor, stage, lateral,
        step, time, speed, aloft, ahead, prices; targets=nothing, slowest=1)
    stowed_ahead, aloft_ahead = any(isfinite, ahead) ? ahead : (0.0, 0.0)
    start = EdgeSample(table.table, weather, corridor, stage, lateral, step, 0.0, time)
    for speed_index in searchsortedfirst(table.speeds, speed):-1:slowest
        hours = sail_edge!(points, start, table, weather, corridor, stage, lateral, step,
            time, speed_index)
        isfinite(hours) || continue
        down, up = isnothing(targets) ? kite_passage(table, points, aloft, prices) :
                   held_kite_passage(table, points, aloft, targets, prices)[1:2]
        ends_aloft = up.cost + aloft_ahead < down.cost + stowed_ahead
        tally = ends_aloft ? up : down
        isfinite(tally.cost) && return hours, tally, ends_aloft, table.speeds[speed_index]
    end
    return Inf, NO_TALLY, false, speed
end

"""
    PlannedKite(forecast)

The forecast source `forecast` (`nothing` for a [`ForecastWeather`](@ref) horizon, or a
[`ForecastArchive`](@ref)) of a ship whose kite does not choose its launches and landings
in the weather met: [`forecast_route`](@ref) keeps it up or down as the plan put it,
wherever the real weather allows that.
"""
struct PlannedKite{F}
    forecast::F
end

"""
    ForesightKite(forecast)

The forecast source `forecast` of a ship that takes its course and speed from plans on it,
but whose kite launches and lands as if it knew the real weather along the rest of the plan.
"""
struct ForesightKite{F}
    forecast::F
end

"""
    KiteMargin(forecast, margin)

The forecast source `forecast` of a ship that plans its kite inside limits tightened by the
share `margin` ([`tightened_limits`](@ref)), and sails it within the real ones.
"""
struct KiteMargin{F}
    forecast::F
    margin::Float64
end

"""
    tightened_limits(rig, margin)

The [`KiteRig`](@ref) `rig`, or the kite of a [`CombinedRig`](@ref), with its lowest
flying and launch winds raised, and its highest flying and launch winds and launch wave
limit lowered, by the share `margin` of each.
"""
tightened_limits(rig::KiteRig, margin) = with_changed(rig;
    max_wind=rig.max_wind * (1 - margin),
    min_flight_wind=rig.min_flight_wind * (1 + margin),
    launch_min_wind=rig.launch_min_wind * (1 + margin),
    launch_max_wind=rig.launch_max_wind * (1 - margin),
    launch_max_wave_height=rig.launch_max_wave_height * (1 - margin))
tightened_limits(rig::CombinedRig, margin) =
    CombinedRig(tightened_limits(rig.kite, margin), rig.standing)
tightened_limits(rig, margin) = rig

"""
    with_changed(item; changes...)

An immutable `item` with its fields `changes` replaced.
"""
with_changed(item; changes...) =
    typeof(item).name.wrapper((get(changes, name, getfield(item, name))
                               for name in fieldnames(typeof(item)))...)

"""
    margin_table(table, margin)

The [`RouteTable`](@ref) `table` with the kite limits [`tightened_limits`](@ref) by
`margin` and its extra launch wind in a sea raised by the same share.
"""
function margin_table(table::RouteTable, margin)
    performance = table.table
    rig = tightened_limits(performance.ship.rig, margin)
    ship = with_changed(performance.ship; rig)
    (; knots, values) = performance.sea_launch_wind
    return with_changed(table; table=with_changed(performance; ship,
        sea_launch_wind=LinearTable(knots, values .* (1 + margin))))
end

"""
    PerfectForecast()

Forecast source of a ship that re-plans daily knowing the real weather.
"""
struct PerfectForecast end

known_weather(::Nothing, weather, time, horizon) = ForecastWeather(weather, time, horizon)
known_weather(::PerfectForecast, weather, time, horizon) =
    known_weather(nothing, weather, time, Inf)

"""
    ReplannedForecast(forecast; interval=24.0, adapts=:nothing, grid=nothing)

The forecast source `forecast` of a ship that re-plans at the first node `interval` [h]
or more after its last plan, that between plans chooses each edge's speed (`:speed`)
or also its next node (`:course`) by [`adapted_edge`](@ref), and that plans on the
[`PlanningGrid`](@ref) `grid`, or on its whole corridor where that is `nothing`.
"""
struct ReplannedForecast{F, G}
    forecast::F
    interval::Float64
    adapts::Symbol
    grid::G
    function ReplannedForecast(forecast::F; interval=24.0, adapts=:nothing,
            grid::G=nothing) where {F, G}
        adapts in (:nothing, :speed, :course) ||
            throw(ArgumentError("adapts must be :nothing, :speed or :course, not $adapts"))
        return new{F, G}(forecast, interval, adapts, grid)
    end
end

"""
    PlanningGrid(mask; near_distance=480.0, far_spacing=720.0, far_row_stride=4,
                 far_sample_hours=12.0)

Stages a re-planning ship plans on: those of its corridor within `near_distance` [nmi]
ahead, then stages about `far_spacing` [nmi] apart whose edges may shift as many rows as
their length allows, on every `far_row_stride`-th row, with weather samples at most
`far_sample_hours` [h] apart, clear of land by `mask`.
"""
struct PlanningGrid{M}
    mask::M
    near_distance::Float64
    far_spacing::Float64
    far_row_stride::Int
    far_sample_hours::Float64
end

PlanningGrid(mask; near_distance=480.0, far_spacing=720.0, far_row_stride=4,
    far_sample_hours=12.0) =
    PlanningGrid(mask, near_distance, far_spacing, far_row_stride, far_sample_hours)

"""
    planning_stages(corridor, stage, grid)

Numbers of the stages of `corridor` a ship at `stage` plans on by the
[`PlanningGrid`](@ref) `grid`, and how many of them lie in its near part. Its far part
keeps every stage of the corridor's fixed coastal track and the stage that joins it.
"""
function planning_stages(corridor::Corridor, stage, grid::PlanningGrid)
    along = corridor.along_centre
    stage_count = length(along)
    fixed = [count(view(corridor.water, i, :)) == 1 for i in 1:stage_count]
    near_end = along[stage] + grid.near_distance * NAUTICAL_MILE
    last_near = clamp(searchsortedlast(along, near_end), min(stage + 1, stage_count),
        stage_count)
    stages = collect(stage:last_near)
    spacing = grid.far_spacing * NAUTICAL_MILE
    while last(stages) < stage_count
        previous = last(stages)
        next = max(searchsortedfirst(along, along[previous] + spacing), previous + 1)
        along[stage_count] - along[min(next, stage_count)] < spacing / 2 &&
            (next = stage_count)
        coast = findnext(fixed, previous + 1)
        isnothing(coast) || (next = min(next, max(coast - 1, previous + 1)))
        push!(stages, min(next, stage_count))
    end
    return stages, last_near - stage + 1
end

"""
    planning_corridor(corridor, stage, lateral, grid)

The [`Corridor`](@ref) a ship at `stage` and `lateral` of `corridor` plans on, the stage it
starts from there, and how many of its nodes along a plan the ship may sail before planning
again: `corridor` itself where `grid` is `nothing` or leads nowhere from the ship.
"""
planning_corridor(corridor::Corridor, stage, lateral, ::Nothing) =
    corridor, stage, typemax(Int)

function planning_corridor(corridor::Corridor, stage, lateral, grid::PlanningGrid)
    stages, near = planning_stages(corridor, stage, grid)
    lat, lon = corridor.lat[stages, :], corridor.lon[stages, :]
    water = corridor.water[stages, :]
    centre = centre_index(corridor)
    far = (near + 1):length(stages)
    for row in axes(water, 2)
        mod(row - centre, grid.far_row_stride) == 0 || (water[far, row] .= false)
    end
    lengths = diff(corridor.along_centre[stages])
    spacing = corridor.lateral_spacing
    stage_reach(i) = i < near ? min(corridor.reach, lateral_reach(lengths[i], spacing)) :
                     lateral_reach(lengths[i], spacing)
    reach = maximum(stage_reach, eachindex(lengths))
    open, edge_length, edge_course = leading_to_port(lat, lon, water, grid.mask, reach,
        stage_reach)
    open[1, lateral] || return planning_corridor(corridor, stage, lateral, nothing)
    planning = Corridor(lat, lon, open, edge_length, edge_course, corridor.track_length,
        corridor.near_coast[stages, :], along_centre_line(lat, lon), reach, spacing,
        [i < near ? 0.0 : grid.far_sample_hours for i in eachindex(stages)])
    return planning, 1, near
end

"""
    forecast_plan(known, corridor, table, time, prices; first_stage, first_lateral,
                  first_aloft, coastal_penalty)

The plan a ship adopts at `time` [h] on `known`, and the [`plan_values`](@ref) of its nodes
on it, or `(nothing, nothing)` where no plan leaves the node. On a vector of members of an
ensemble, the plan routed on some member with the least mean of fuel, rig and time cost
over all members, valued by the mean over the members of its [`plan_values`](@ref) with
the ship slowing where a member stops it.
"""
function forecast_plan(known, corridor, table::RouteTable, time, prices; first_stage,
        first_lateral, first_aloft, coastal_penalty)
    plan = route(corridor, table, known, time; time_cost=prices.time, first_stage,
        first_lateral, first_aloft, coastal_penalty)
    isnothing(plan) && return nothing, nothing
    return plan, plan_values(plan, corridor, table, known, time, first_stage, prices)
end

function forecast_plan(members::Vector, corridor, table::RouteTable, time, prices;
        first_stage, first_lateral, first_aloft, coastal_penalty)
    plans = unique(plan -> plan.path, filter(!isnothing,
        [route(corridor, table, member, time; time_cost=prices.time, first_stage,
            first_lateral, first_aloft, coastal_penalty) for member in members]))
    isempty(plans) && return nothing, nothing
    values = [mean(plan_values(plan, corridor, table, member, time, first_stage, prices;
                       slows=true) for member in members) for plan in plans]
    best = argmin([plan_value[1, first_aloft + 1] + prices.time * plan.duration
                   for (plan, plan_value) in zip(plans, values)])
    return plans[best], values[best]
end

"the forecast a plan's kite states are read on: of an ensemble, its first member"
one_forecast(known) = known
one_forecast(members::Vector) = first(members)

"""
    remaining_cost(corridor, table, known, departure, prices; first_stage, coastal_penalty)

[`CostToGo`](@ref) of a ship at `first_stage` of `corridor` planning on `known` at
`departure` [h].
"""
function remaining_cost(corridor::Corridor, table::RouteTable, known, departure, prices;
        first_stage, coastal_penalty)
    workspace = acquire_workspace(size(corridor.lat, 2),
        ceil(Int, MAX_LEG_HOURS / ROUTER_SETTINGS[].time_step), size(corridor.lat, 1))
    try
        to_go = CostToGo(workspace, corridor, table, known, departure;
            time_cost=prices.time, first_stage, coastal_penalty)
        return CostToGo(copy(to_go.values), to_go.knots)
    finally
        release_workspace(workspace)
    end
end

"objective [USD] from node `next` of `stage` at `time` by `to_go`, kite down and aloft"
function values_ahead(to_go::CostToGo, next, stage, time)
    down, up = to_go(next, 1, stage, time), to_go(next, 2, stage, time)
    return isnan(down) ? Inf : down, isnan(up) ? Inf : up
end

"""
    adapted_edge(points, corridor, table, met, to_go, at, prices, adapts, coastal_penalty)

Step and speed [m/s] of the edge left from `at` (`stage`, `lateral`, planned `step` and
`speed`, kite `aloft`, `elapsed` hours since the plan, absolute `time`) with the least
objective in the [`MetWeather`](@ref) `met` plus `to_go` at its end, over the planned step
(`adapts` `:speed`) or all steps (`:course`) and the search's commanded speeds and the
planned one, and the values ahead of [`values_ahead`](@ref). Where no edge can be sailed in
`met` it returns the planned speed, the allowed step nearest the plan and `Inf` ahead.
"""
function adapted_edge(points, corridor::Corridor, table::RouteTable, met, to_go, at, prices,
        adapts, coastal_penalty)
    (; stage, lateral, aloft, elapsed, time) = at
    planned_speed = searchsortedfirst(table.speeds, at.speed)
    stride = ROUTER_SETTINGS[].search_speed_stride
    commanded = commanded_speeds(length(table.speeds), stride)
    speeds = sort(unique([planned_speed; commanded]))
    steps = adapts == :course ? (1:step_count(corridor)) : (at.step:at.step)
    best_value, best_step, best_speed, ahead = Inf, clamp(at.step, extrema(steps)...),
    at.speed, (Inf, Inf)
    for step in steps
        isnan(corridor.edge_course[stage, lateral, step]) && continue
        next = next_lateral(corridor, lateral, step)
        penalty = edge_penalty(corridor, stage, next, coastal_penalty)
        start = EdgeSample(table.table, met, corridor, stage, lateral, step, 0.0, time)
        for speed_index in speeds
            hours = sail_edge!(points, start, table, met, corridor, stage, lateral, step,
                time, speed_index)
            isfinite(hours) || continue
            arrival = (; penalty, hours, prices, next, stage=stage + 1,
                time=elapsed + hours)
            value = best_arrival(to_go, table, points, aloft, arrival)
            value < best_value || continue
            best_value, best_step, best_speed = value, step, table.speeds[speed_index]
            ahead = values_ahead(to_go, next, stage + 1, elapsed + hours)
        end
    end
    return best_step, best_speed, ahead
end

"""
    plan_kite_states(plan, corridor, table, known, departure, first_stage, i, prices)

Whether the kite is up at each sample of edge `i` of `plan`, left at `departure` [h] from
stage `first_stage`, on the cheapest way between the states [`Leg`](@ref) `plan` holds at
the two ends of the edge in the forecast `known`.
"""
function plan_kite_states(plan::Leg, corridor, table::RouteTable, known, departure,
        first_stage, i, prices)
    points = SailedPoint[]
    hours = sail_plan_edge!(points, plan, corridor, table, known, departure, first_stage, i)
    isfinite(hours) || return [plan.aloft[i]]
    return kite_way(table, points, plan.aloft[i], plan.aloft[i + 1], prices)
end

"""
    KiteSample

One sample of a passage as sailed: hours from departure [h], latitude and longitude
[deg], whether the kite is up, whether it would be up held to the plan on that edge, true
and apparent wind at its height [m/s], significant wave height [m], the hours [h] and
distance [m] it stands for, the speed the plan commanded and the speed held [m/s], why the
kite is down there, `:up` where it is up ([`kite_down_reason`](@ref)), whether the plan
wants it up there, the fuel power with the rig flown and stowed there [W], and the highest
routing speed a flying kite could hold there in the real weather and in the weather known
to the plan [m/s], the hours from departure [h] at which its edge began, and the
[`SailedPoint`](@ref) it records.
"""
const KiteSample = @NamedTuple{hours::Float64, lat::Float64, lon::Float64, aloft::Bool,
    planned::Bool, wind_speed::Float64, apparent_wind::Float64, wave_height::Float64,
    sample_hours::Float64, distance::Float64, planned_speed::Float64, speed::Float64,
    reason::Symbol, wanted::Bool, flown_power::Float64, stowed_power::Float64,
    fastest_speed::Float64, forecast_fastest::Float64, edge_start::Float64,
    point::SailedPoint}

"""
    KiteRuleEdge

One edge of a passage as sailed, compared with the same edge from the same state with the
kite held to the plan: whether each ends aloft, the samples whose state differs, and the
fuel and rig cost of each [USD].
"""
const KiteRuleEdge = @NamedTuple{ends_aloft::Bool, held_ends_aloft::Bool,
    different_samples::Int, samples::Int, cost::Float64, held_cost::Float64}

"""
    KiteRecord()

What [`forecast_route`](@ref) or [`record_plan!`](@ref) records of a passage: its
[`KiteSample`](@ref)s, per edge its [`KiteRuleEdge`](@ref), and the hours from departure
[h] at which the ship started each hold.
"""
struct KiteRecord
    samples::Vector{KiteSample}
    edges::Vector{KiteRuleEdge}
    holds::Vector{Float64}
end
KiteRecord() = KiteRecord(KiteSample[], KiteRuleEdge[], Float64[])

"""
    kite_down_reason(table, point, prices)

Why a kite is down at [`SailedPoint`](@ref) `point` on the [`RouteTable`](@ref) `table`,
`:no_kite` on a ship without one, else the first that holds of:
`:wind_low_flight`, `:wind_high_flight`, outside the limits it can stay up in;
`:hull_limit`, where the hull or the engine cannot hold the speed with the kite up;
`:wind_low_pull`, where it can stay up but the apparent wind is below
[`lowest_pull_wind`](@ref); `:no_thrust`, in enough wind but with no forward pull at the
course, the wind coming from too far ahead; `:wind_low_launch`, `:wind_high_launch`,
`:sea_launch`, `:night`, outside the limits it can launch in; `:no_saving`, where flying
costs at least as much per hour as staying down; and `:chosen`, where it could launch,
flying would save, and it stayed down.
"""
function kite_down_reason(table::RouteTable, point, prices)
    rig = table.table.ship.rig
    kite = rig isa CombinedRig ? rig.kite : rig
    kite isa KiteRig || return :no_kite
    speed = table.speeds[max(point.speed_index, 1)]
    wind = hypot(point.headwind + speed, point.crosswind)
    wave_height = point.condition.wave_height
    wind < kite.min_flight_wind && return :wind_low_flight
    wind > kite.max_wind && return :wind_high_flight
    isfinite(point.flown) || return :hull_limit
    point.flown !== point.stowed ||
        return wind < lowest_pull_wind(kite) ? :wind_low_pull : :no_thrust
    wind < kite.launch_min_wind && return :wind_low_launch
    wind > kite.launch_max_wind && return :wind_high_launch
    sea_wind = extra_launch_wind(table.table, speed, point.condition)
    (wave_height > kite.launch_max_wave_height || wind < kite.launch_min_wind + sea_wind) &&
        return :sea_launch
    point.daylight || kite.night_launch || return :night
    point.flown * prices.fuel + table.table.wear_cost / 3600 >=
    point.stowed * prices.fuel && return :no_saving
    return :chosen
end

"""
    push_samples!(record, table, points, corridor, stage, lateral, next, start_hours,
                  hours, states, planned, planned_speed, prices, targets, known, departure)

Add to `record` the [`KiteSample`](@ref)s of `points`, the edge from node (`stage`,
`lateral`) to `next`, entered `start_hours` [h] after departure and sailed in `hours` [h]
at commanded `planned_speed` [m/s], with the kite up as `states` says, as `planned` would
have it, and as the plan's `targets` want it, and `known` the weather the plan knew, left
at `departure` [h].
"""
function push_samples!(record, table, points, corridor, stage, lateral, next, start_hours,
        hours, states, planned, planned_speed, prices, targets, known, departure)
    step = lateral_step(corridor, lateral, next)
    distance = corridor.edge_length[stage, lateral, step]
    for (k, point) in enumerate(points)
        share = point_share(k, length(points))
        lat, lon = edge_point(corridor, stage, lateral, next, share)
        speed = table.speeds[max(point.speed_index, 1)]
        reached = departure + start_hours + share * hours
        forecast_point = SailedPoint(table, EdgeSample(table.table, known, corridor, stage,
                lateral, step, share, reached), length(table.speeds), 1.0, reached)
        push!(record.samples, (; hours=start_hours + share * hours, lat, lon,
            aloft=states[k], planned=planned[k],
            wind_speed=hypot(point.headwind, point.crosswind),
            apparent_wind=hypot(point.headwind + speed, point.crosswind),
            wave_height=point.condition.wave_height, sample_hours=point.hours,
            distance=trapezoid_weight(k, length(points)) * distance, planned_speed, speed,
            reason=states[k] ? :up : kite_down_reason(table, point, prices),
            wanted=target_at(targets, share), flown_power=point.flown,
            stowed_power=point.stowed, fastest_speed=fastest_flown_speed(table, point),
            forecast_fastest=fastest_flown_speed(table, forecast_point),
            edge_start=start_hours, point))
    end
end

"""
    fastest_flown_speed(table, point)

Highest routing speed of `table` [m/s] a kite flying at the conditions of
[`SailedPoint`](@ref) `point` can hold, zero where none.
"""
function fastest_flown_speed(table::RouteTable, point)
    for i in length(table.speeds):-1:1
        flown, _ = edge_fuels(table, i, point.condition)
        isfinite(flown) && kite_aloft(table.table, table.speeds[i], point.headwind,
            point.crosswind) && return table.speeds[i]
    end
    return 0.0
end

"""
    record_plan!(record, plan, corridor, table, weather, departure, prices)

Add to `record` the [`Leg`](@ref) `plan` of [`route`](@ref), left at `departure` [h] on
`corridor` and sailed in `weather`, with the kite up as it is on that route.
"""
function record_plan!(record, plan::Leg, corridor, table::RouteTable, weather, departure,
        prices)
    points = SailedPoint[]
    for i in 1:(length(plan.path) - 1)
        stage, lateral, step, _ = plan_edge(plan, corridor, departure, 1, i)
        hours = sail_plan_edge!(points, plan, corridor, table, weather, departure, 1, i)
        states = kite_way(table, points, plan.aloft[i], plan.aloft[i + 1], prices)
        next = nearest_lateral(corridor, stage + 1, plan.path[i + 1][1:2]...)
        push_samples!(record, table, points, corridor, stage, lateral, next,
            plan.path[i][3], hours, states, states, plan.path[i + 1][4], prices, states,
            weather, departure)
    end
end

"""
    record_edge!(record, table, points, corridor, stage, lateral, next, start_hours, hours,
                 start_aloft, ends_aloft, targets, prices, cost, keeps_plan, planned_speed,
                 known, departure)

Add to `record` the sailed `points` of the edge from node (`stage`, `lateral`) to `next`,
entered `start_hours` [h] after departure with the kite up if `start_aloft`, and the
comparison of that edge, of fuel and rig `cost` [USD], with the kite held to `targets`;
`planned_speed` [m/s] is the plan's for the edge and `known` what it knew, left at
`departure` [h].
"""
function record_edge!(record, table, points, corridor, stage, lateral, next, start_hours,
        hours, start_aloft, ends_aloft, targets, prices, cost, keeps_plan, planned_speed,
        known, departure)
    held_down, held_up, held_states = held_kite_passage(table, points, start_aloft, targets,
        prices)
    states = keeps_plan ? held_states :
             kite_way(table, points, start_aloft, ends_aloft, prices)
    push_samples!(record, table, points, corridor, stage, lateral, next, start_hours, hours,
        states, held_states, planned_speed, prices, targets, known, departure)
    push!(record.edges, (; ends_aloft, held_ends_aloft=isfinite(held_up.cost),
        different_samples=count(states .!= held_states), samples=length(points), cost,
        held_cost=min(held_down.cost, held_up.cost)))
end

"""
    forecast_route(corridor, table, weather, departure; time_cost, horizon=Inf,
                   forecast=nothing, coastal_penalty=1.0, record=nothing)

Passage of a ship that re-plans by [`forecast_plan`](@ref) on the [`RouteTable`](@ref)
`table` at the first node 24 hours or more after the last plan, on `forecast`: a
[`ForecastArchive`](@ref), a [`ForecastEnsemble`](@ref), a [`ShortestLead`](@ref), a
[`PerfectForecast`](@ref), a [`KiteMargin`](@ref) of one of those, a
[`ForecastParts`](@ref), a [`ForecastWeather`](@ref) of `horizon` hours where `nothing`, or
a [`ReplannedForecast`](@ref) with its own interval and adaptation between plans. It sails
each plan in the real `weather` until the next re-plan by
[`sail_planned_edge!`](@ref), launching and landing the kite where the real weather of an
edge and the [`plan_values`](@ref) ahead make that cheapest, or, with `forecast` a
[`PlannedKite`](@ref), where the plan put it, or with a [`ForesightKite`](@ref), by the
same values in the real weather. Fuel, flight hours and objective are those
of the real weather. Where no plan leaves its node or the real weather stops the next
edge, the ship holds there with the kite stowed on its hotel load until the next forecast,
6 h later, and plans again. A [`KiteRecord`](@ref) `record` receives what was sailed.
Returns `nothing` after holding 72 h at one node.
"""
function forecast_route(corridor::Corridor, table::RouteTable, weather, departure;
        time_cost, horizon=Inf, forecast=nothing, coastal_penalty=1.0, record=nothing)
    ship_table = table.table
    prices = (; fuel=ship_table.ship.fuel.price, time=time_cost)
    stage_count = size(corridor.lat, 1)
    stage, lateral, aloft = 1, centre_index(corridor), false
    time, fuel_energy, flight_hours = 0.0, 0.0, 0.0
    launches, forced_landings = 0, 0
    objective = 0.0
    path = [(corridor.lat[1, lateral], corridor.lon[1, lateral], 0.0, 0.0, 0.0)]
    aloft_path = [false]
    points = SailedPoint[]
    held = 0.0
    replanned = forecast isa ReplannedForecast ? forecast : ReplannedForecast(forecast)
    (; interval, adapts, grid) = replanned
    planned = replanned.forecast
    keeps_plan, foresight = planned isa PlannedKite, planned isa ForesightKite
    with_margin = planned isa KiteMargin
    source = keeps_plan || foresight || with_margin ? planned.forecast : planned
    plan_table = with_margin ? margin_table(table, planned.margin) : table
    while stage < stage_count
        known = known_weather(source, weather, departure + time, horizon)
        planning, plan_stage, sailable = planning_corridor(corridor, stage, lateral, grid)
        plan, values = forecast_plan(known, planning, plan_table, departure + time, prices;
            first_stage=plan_stage, first_lateral=lateral, first_aloft=aloft,
            coastal_penalty)
        blocked = isnothing(plan)
        foresight && !blocked && (values = plan_values(plan, planning, table, weather,
            departure + time, plan_stage, prices))
        plan_start, plan_end = time, blocked ? 1 : min(length(plan.path), sailable)
        to_go = blocked || adapts == :nothing ? nothing :
                remaining_cost(corridor, plan_table, known, departure + time, prices;
            first_stage=stage, coastal_penalty)
        for i in 2:plan_end
            next_lat, next_lon, _, planned_speed, _ = plan.path[i]
            next = nearest_lateral(corridor, stage + 1, next_lat, next_lon)
            step = lateral_step(corridor, lateral, next)
            ahead = keeps_plan ? (0.0, 0.0) : (values[i, 1], values[i, 2])
            if adapts != :nothing
                met = MetWeather(known, weather, corridor.lat[stage, lateral],
                    corridor.lon[stage, lateral], departure + time)
                at = (; stage, lateral, step, speed=planned_speed, aloft,
                    elapsed=time - plan_start, time=departure + time)
                step, planned_speed, ahead = adapted_edge(points, corridor, table, met,
                    to_go, at, prices, adapts, coastal_penalty)
                next = next_lateral(corridor, lateral, step)
                next_lat, next_lon = corridor.lat[stage + 1, next],
                corridor.lon[stage + 1, next]
            end
            targets = keeps_plan || !isnothing(record) ?
                      plan_kite_states(plan, planning, plan_table, one_forecast(known),
                departure + plan_start, plan_stage, i - 1, prices) : nothing
            start_aloft = aloft
            hours, tally, aloft, speed = sail_planned_edge!(points, table, weather,
                corridor, stage, lateral, step, departure + time, planned_speed, aloft,
                ahead, prices;
                targets=keeps_plan ? targets : nothing)
            blocked = !isfinite(hours)
            blocked && break
            isnothing(record) || record_edge!(record, table, points, corridor, stage,
                lateral, next, time, hours, start_aloft, aloft, targets, prices, tally.cost,
                keeps_plan, planned_speed, one_forecast(known), departure)
            penalty = edge_penalty(corridor, stage, next, coastal_penalty)
            objective += edge_objective(penalty, tally.cost, hours, prices)
            fuel_energy += tally.energy
            flight_hours += tally.flight_hours
            launches += tally.launches
            forced_landings += tally.forced_landings
            time += hours
            held = 0.0
            stage, lateral = stage + 1, next
            push!(path, (next_lat, next_lon, time, speed, summary_mode(tally, hours)))
            push!(aloft_path, aloft)
            time - plan_start >= interval && break
        end
        blocked || continue
        held >= LONGEST_HOLD && return nothing
        isnothing(record) || push!(record.holds, time)
        energy = 3600FORECAST_INTERVAL * fuel_power(ship_table.ship.powertrain, 0.0)
        objective += edge_objective(1.0, energy * prices.fuel, FORECAST_INTERVAL, prices)
        fuel_energy += energy
        time += FORECAST_INTERVAL
        held += FORECAST_INTERVAL
        aloft = false
    end
    return Leg(fuel_energy, fuel_energy * prices.fuel, flight_hours, launches,
        forced_landings, time, objective, path, aloft_path)
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

"distance the route may stray to either side of its reference track [nmi]"
const CORRIDOR_HALF_WIDTH = 2400.0

"waypoints from Rotterdam through the Channel to Ushant (latitude, longitude) [deg]"
const CHANNEL = [(51.98, 4.05), (51.05, 1.60), (50.05, -1.50), (48.80, -6.00)]

"""
    route_corridors(route, mask; scale=1, ocean_spacing=90.0 * scale,
                    lateral_spacing=60.0 * scale)

Outbound and return corridors between Rotterdam and the port of `route`: `:caribbean`
(Guadeloupe; outbound via the trade winds, homeward on the great circle), `:new_york`,
`:bilbao`, `:dakar`, `:houston` (through the Florida Strait) or `:tubarao` (Brazil), the
same band both ways. All run through the Channel to Ushant.
`ocean_spacing` and `lateral_spacing` are the stage and row spacing [nmi]; the band reaches
`CORRIDOR_HALF_WIDTH` to either side.
"""
function route_corridors(route::Symbol, mask; scale=1, ocean_spacing=90.0 * scale,
        lateral_spacing=60.0 * scale)
    spacing = (ocean_spacing, lateral_spacing,
        lateral_count=2 * ceil(Int, CORRIDOR_HALF_WIDTH / lateral_spacing) + 1)
    if route == :caribbean
        guadeloupe = (16.15, -61.20)
        outbound = Corridor(CHANNEL, [(40.0, -14.0), (27.0, -28.0), guadeloupe], mask;
            spacing...)
        return outbound,
        return_corridor(Corridor(CHANNEL, [guadeloupe], mask; spacing...), mask)
    end
    ocean = Dict(:new_york => [(40.3, -72.5)], :bilbao => [(43.6, -3.0)],
        :dakar => [(43.5, -11.0), (14.6, -17.6)],
        :houston => [(30.5, -76.0), (23.9, -81.5), (25.5, -86.5), (28.8, -94.5)],
        :tubarao => [(30.0, -22.0), (0.0, -30.0), (-20.4, -39.8)])[route]
    outbound = Corridor(CHANNEL, ocean, mask; spacing...)
    return outbound, return_corridor(outbound, mask)
end

"""
    wave_heading(wave_from, course)

Wave heading relative to the ship [rad]: π when the waves come from straight ahead, 0
when they come from astern; both angles clockwise from north.
"""
function wave_heading(wave_from, course)
    difference = wave_from - course
    return π - abs(difference - 2π * round(difference / 2π))
end
