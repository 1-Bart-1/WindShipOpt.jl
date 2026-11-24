# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"rows an edge of a corridor of stages 1.5 times as far apart as its rows may shift by"
const MAX_LATERAL_STEP = 2

"largest tangent of the angle between an edge and its corridor [-]"
const MAX_HEADING_TANGENT = 2MAX_LATERAL_STEP / 3

"step of an edge between nodes of the same lateral number, on a corridor of one row"
const STRAIGHT_ON = MAX_LATERAL_STEP + 1

"rows an edge of `stage_spacing` along a corridor of `lateral_spacing` may shift by"
lateral_reach(stage_spacing, lateral_spacing) = max(1,
    floor(Int, MAX_HEADING_TANGENT * stage_spacing / lateral_spacing + ROW_TOLERANCE))

"rows by which a reach short of a whole number of rows still counts as reaching it"
const ROW_TOLERANCE = 1e-6

"distance between the stages of a fixed coastal path [nmi]"
const COASTAL_SPACING = 30.0

"""
    Corridor

Graph for weather routing: stages along a reference track, each with a row of lateral
nodes; edges join a node to nodes up to `reach` rows away in the next stage.
"""
struct Corridor{M}
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
    "distance from the first stage along the centre line, per stage [m]"
    along_centre::Vector{Float64}
    "rows an edge may shift by, on each side"
    reach::Int
    "distance between the rows of a stage [m]"
    lateral_spacing::Float64
    "longest time between the weather samples along the edges of each stage that a plan may
    use [h]; 0 keeps the plan's own"
    sample_hours::Vector{Float64}
    "land the corridor's edges keep clear of, `nothing` for one whose edges are given"
    mask::M
end

"edges leaving each node of `corridor`"
step_count(corridor::Corridor) = 2corridor.reach + 1

"lateral node that edge `step` of node `lateral` leads to, on edges of up to `reach` rows"
next_lateral(lateral, step, reach) = lateral + step - reach - 1
next_lateral(corridor::Corridor, lateral, step) =
    next_lateral(lateral, step, corridor.reach)

"edge of node `lateral` of `corridor` that leads to lateral node `next`"
lateral_step(corridor::Corridor, lateral, next) = next - lateral + corridor.reach + 1

"index of the centre lateral node of a corridor whose nodes are at `lat`"
centre_index(lat::AbstractMatrix) = (size(lat, 2) + 1) ÷ 2
centre_index(corridor::Corridor) = centre_index(corridor.lat)

"latitude north and south of which a corridor has no usable node [deg]"
const SAILABLE_LATITUDE = 60.0

"""
distance from land within which every wind value the router reads mixes in land [m]: half
the 1.5° spacing of the wind grid, in latitude
"""
const COASTAL_CLEARANCE = 45 * NAUTICAL_MILE

"""
distance from the end of a fixed coastal path, or from a port, within which a corridor
keeps open-sea nodes near land [m]: one spacing of the wind grid
"""
const APPROACH_RADIUS = 2COASTAL_CLEARANCE

"""
    near_land(mask, lat, lon, clearance)

Whether land lies within `clearance` [m] of the point, sampled on two rings of 16
bearings; the edge of the grid of `mask` is no land.
"""
function near_land(mask, lat, lon, clearance)
    for radius in (clearance / 2, clearance), course in range(0, 2π; length=17)[1:16]
        sample = destination(lat, lon, course, radius)
        on_grid(mask, sample...) && is_land(mask, sample...) && return true
    end
    return false
end

"""
    approaches(paths)

Where the open sea meets the fixed coastal `paths` (lat, lon) [deg]: the end of each path
but the last and the start of each but the first.
"""
approaches(paths) = [last.(paths[1:(end - 1)]); first.(paths[2:end])]

"""
    approached(point, ends)

Whether `point` (lat, lon) [deg] lies within `APPROACH_RADIUS` of one of the `ends`.
"""
approached(point, ends) =
    any(end_point -> distance(point..., end_point...) <= APPROACH_RADIUS, ends)

"""
    Corridor(paths, mask; ocean_spacing, lateral_spacing, lateral_count)

Corridor that follows the fixed coastal `paths` (lat, lon) in turn and crosses the open sea
between each path and the next on the great circle from the end of one to the start of the
next, the port the last point of the last path. Only the open-sea stages have lateral
nodes, on rows perpendicular to their great circle and within `SAILABLE_LATITUDE`, none
within `COASTAL_CLEARANCE` of land unless within `APPROACH_RADIUS` of a path's end or start.
Fixed stages lie `COASTAL_SPACING` apart; spacings in nautical miles.
"""
function Corridor(paths::Vector{Vector{NTuple{2, Float64}}}, mask; ocean_spacing,
        lateral_spacing, lateral_count)
    track = resample(first(paths), COASTAL_SPACING * NAUTICAL_MILE)
    open_sea = falses(length(track))
    ends = approaches(paths)
    for (from, to) in zip(paths[1:(end - 1)], paths[2:end])
        crossing = resample([last(from), first(to)], ocean_spacing * NAUTICAL_MILE)
        coastal = resample(to, COASTAL_SPACING * NAUTICAL_MILE)
        append!(track, crossing[2:(end - 1)], coastal)
        append!(open_sea, trues(length(crossing) - 2), falses(length(coastal)))
    end
    stage_count = length(track)
    half = (lateral_count - 1) ÷ 2
    lat = zeros(stage_count, lateral_count)
    lon = zeros(stage_count, lateral_count)
    water = falses(stage_count, lateral_count)
    for (stage, (stage_lat, stage_lon)) in enumerate(track)
        incoming = stage == stage_count || stage > 1 && open_sea[stage - 1]
        course = incoming ? bearing(track[stage]..., track[stage - 1]...) + π :
                 bearing(track[stage]..., track[stage + 1]...)
        width = open_sea[stage] ? half : 0
        for lateral in 1:lateral_count
            offset = (lateral - half - 1) * lateral_spacing * NAUTICAL_MILE
            point = destination_point(stage_lat, stage_lon, course + π / 2, offset)
            lat[stage, lateral], lon[stage, lateral] = point
            water[stage, lateral] = abs(lateral - half - 1) <= width &&
                                    abs(first(point)) <= SAILABLE_LATITUDE &&
                                    !is_land(mask, point...) &&
                                    (!open_sea[stage] || approached(point, ends) ||
                                     !near_land(mask, point..., COASTAL_CLEARANCE))
        end
    end
    reach = lateral_reach(ocean_spacing, lateral_spacing)
    track_length = sum(distance(track[i]..., track[i + 1]...) for i in 1:(stage_count - 1))
    return Corridor(lat, lon, on_passage(lat, lon, water, mask, reach)...,
        track_length, along_centre_line(lat, lon), reach, lateral_spacing * NAUTICAL_MILE,
        zeros(stage_count), mask)
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
        next = next_lateral(lateral, step, reach)
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
    on_passage(lat, lon, water, mask, reach, start=centre_index(lat),
               stage_reach=Returns(reach))

The nodes of `water` that [`edges`](@ref) join to both node `start` of the first stage and
the port, the centre of the last stage, and the edges between those nodes.
"""
function on_passage(lat, lon, water, mask, reach, start=centre_index(lat),
        stage_reach=Returns(reach))
    edge_length, edge_course = edges(lat, lon, water, mask, reach, stage_reach)
    stage_count = size(water, 1)
    leads_on = falses(size(water))
    leads_on[end, centre_index(lat)] = water[end, centre_index(lat)]
    for stage in (stage_count - 1):-1:1, lateral in axes(water, 2)
        for step in axes(edge_course, 3)
            isnan(edge_course[stage, lateral, step]) && continue
            leads_on[stage + 1, next_lateral(lateral, step, reach)] && continue
            edge_length[stage, lateral, step] = 0.0
            edge_course[stage, lateral, step] = NaN
        end
        leads_on[stage, lateral] = any(!isnan, view(edge_course, stage, lateral, :))
    end
    reached = falses(size(water))
    reached[1, start] = leads_on[1, start]
    for stage in 1:(stage_count - 1), lateral in axes(water, 2)
        if !reached[stage, lateral]
            edge_length[stage, lateral, :] .= 0.0
            edge_course[stage, lateral, :] .= NaN
        end
        for step in axes(edge_course, 3)
            isnan(edge_course[stage, lateral, step]) && continue
            reached[stage + 1, next_lateral(lateral, step, reach)] = true
        end
    end
    return reached, edge_length, edge_course
end

"""
    return_corridor(corridor, mask)

The same corridor sailed from its last stage to its first, clear of land by `mask`.
"""
function return_corridor(corridor::Corridor, mask)
    lat = reverse(corridor.lat; dims=1)
    lon = reverse(corridor.lon; dims=1)
    water = reverse(corridor.water; dims=1)
    return Corridor(lat, lon, on_passage(lat, lon, water, mask, corridor.reach)...,
        corridor.track_length, along_centre_line(lat, lon), corridor.reach,
        corridor.lateral_spacing, reverse(corridor.sample_hours), mask)
end

"""
    Leg

Optimal passage along a corridor: fuel energy [J], hours a kite flew patterns, its
launches and forced landings, duration [h], the objective the router minimises [USD], the
path as (latitude, longitude, time [h], commanded speed [m/s], mode) per stage, the mode of
the edge into the stage being the one the kite spent most of the edge in: 0 down and 1
flying, and whether the kite is aloft on arrival at each stage.
"""
struct Leg
    fuel_energy::Float64
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

"hours between the forecasts a ship plans on, and that it holds when no plan leaves it [h]"
const FORECAST_INTERVAL = 6.0

"longest a ship on a forecast holds at one node before its passage fails [h]"
const LONGEST_HOLD = 72.0

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

Numerical settings of the planner: the search of [`route`](@ref) and the grid
[`forecast_route`](@ref) plans each stretch on by [`planning_corridor`](@ref).
"""
Base.@kwdef struct RouterSettings
    "longest time between the weather samples along an edge [h]"
    edge_sample_hours::Float64 = 3.0
    "length of the time bins of the programme [h]"
    time_step::Float64 = 3.0
    "how far above the [`CostToGo`](@ref) of the departure the states searched reach, on
    the first try and where that leaves no path [-]; `Inf` searches them all"
    search_margins::NTuple{2, Float64} = (0.03, 0.06)
    "whether the search of a ship that can fly a kite keeps an arrival with it down and one
    aloft at each node and time bin, the reference its [`KiteRule`](@ref) is checked
    against, rather than the one that rule prefers"
    kite_states_searched::Bool = false
    "routing speeds, from the lowest routing speed to the ship's top speed"
    routing_speeds::Int = 49
    "speeds the search skips between those it commands, plus one, where that moves the
    arrival by no more than a time bin"
    search_speed_stride::Int = 8
    "time between the knots of the [`CostToGo`](@ref) [h]"
    to_go_step::Float64 = 24.0
    "hours past its re-plan interval within which a ship sailing live computes the
    [`CostToGo`](@ref) of each plan on its forecast, reading it beyond them from that of
    the plan before [h]; `Inf` computes it all"
    to_go_near_hours::Float64 = 72.0
    "length of the time bins of the final pass along the path found [h]"
    final_time_step::Float64 = 0.25
    "`final_time_step` of a plan that weighs the wind error of its forecast [h]"
    weighed_final_time_step::Float64 = 1.0
    "how far the final pass strays in time from the path found [h]"
    final_time_band::Float64 = 6.0
    "longest time between the weather samples along an edge of the [`CostToGo`](@ref) [h]"
    to_go_sample_hours::Float64 = 6.0
    "how far ahead of the ship a plan keeps every stage and row of its corridor [nmi]"
    near_distance::Float64 = 240.0
    "rows a plan keeps just beyond `near_distance`: every `far_row_stride`-th from the
    centre, on stages far enough apart for an edge to shift by that many rows"
    far_row_stride::Int = 4
    "growth of the distance ahead over which the rows a plan keeps beyond `near_distance`
    double in spacing [-]; `Inf` keeps every `far_row_stride`-th row to the end"
    row_doubling_ratio::Float64 = 2.0
    "longest time between the weather samples along an edge beyond `near_distance` [h]"
    far_sample_hours::Float64 = 6.0
    "time between the choices of speed and kite of a ship sailing live [h]"
    live_step_hours::Float64 = 1.0
    "speeds a ship sailing live skips between those it weighs, plus one"
    live_speed_stride::Int = 4
end

"[`RouterSettings`](@ref) in force, in every task"
const ROUTER_SETTINGS = Ref(RouterSettings())

"held by the task whose [`with_router_settings`](@ref) call is running"
const ROUTER_SETTINGS_LOCK = ReentrantLock()

"""
    with_router_settings(call, settings)

The result of `call()` with the [`RouterSettings`](@ref) `settings` in force, and those in
force before it afterwards. Throws while a call from another task is running.
"""
function with_router_settings(call, settings::RouterSettings)
    trylock(ROUTER_SETTINGS_LOCK) ||
        error("router settings hold in every task: set them outside a threaded loop")
    earlier = ROUTER_SETTINGS[]
    ROUTER_SETTINGS[] = settings
    try
        return call()
    finally
        ROUTER_SETTINGS[] = earlier
        unlock(ROUTER_SETTINGS_LOCK)
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
    "true wind speed on the table's wind axis [m/s]: the 10 m wind, or with a kite the 10 m
    wind that gives the kite its wind on the table's profile"
    wind_speed::Float64
    "standard error of that speed the plan weighs [m/s]; 0 for a wind taken as known"
    spread::Float64
end

"""
    EdgeSample(table, (east, north), (wave_height, wave_period, wave_from), course,
               spread=0.0; kite_wind=table.kite_wind_factor * hypot(east, north))

[`EdgeSample`](@ref) for the [`PerformanceTable`](@ref) `table` of a 10 m wind [m/s], the
[`waves`](@ref) on `course` [rad from north] and a true wind `kite_wind` [m/s] at the
kite's reference height from the same direction, `spread` the standard error of the wind
speed [m/s]. A kite's ship takes its whole table at the 10 m wind that gives `kite_wind`.
"""
function EdgeSample(table::PerformanceTable, wind_10m, (wave_height, wave_period,
            wave_from), course, spread=0.0;
        kite_wind=table.kite_wind_factor * hypot(wind_10m...))
    east, north = wind_10m
    wind_speed = hypot(east, north)
    cosine = true_wind_cosine(east, north, wind_speed, course)
    table_wind = table.kite_wind_factor > 0 ? kite_wind / table.kite_wind_factor :
                 wind_speed
    condition = SeaCondition(table, table_wind, acos(cosine), wave_height, wave_period,
        wave_heading(wave_from, course))
    crosswind, headwind = kite_wind * sqrt(1 - cosine^2), kite_wind * cosine
    return EdgeSample(condition, headwind, crosswind, table_wind, spread)
end

"""
    kite_wind(weather, table, lat, lon, time, (east, north))

True wind speed [m/s] at the reference height of the kite of the [`PerformanceTable`](@ref)
`table` at (`lat`, `lon`) and `time` [h]: the ERA5 wind aloft where `weather` holds it, else
the 10 m wind (`east`, `north`) on the table's profile; zero without a kite.
"""
kite_wind(weather, table::PerformanceTable, lat, lon, time, (east, north)) =
    table.kite_wind_factor * hypot(east, north)
kite_wind(weather::ERA5Weather, table::PerformanceTable, lat, lon, time, wind_10m) =
    table.kite_height > 0 ? wind_aloft(weather, lat, lon, time, table.kite_height) : 0.0

"""
    EdgeSample(table, weather, lat, lon, time, course, spread=wind_spread(weather, time))

[`EdgeSample`](@ref) for `table` at (`lat`, `lon`) and `time` [h] on `course` [rad from
north] in `weather`.
"""
function EdgeSample(table::PerformanceTable, weather, lat, lon, time, course,
        spread=wind_spread(weather, time))
    wind_10m = wind(weather, lat, lon, time)
    return EdgeSample(table, wind_10m, waves(weather, lat, lon, time), course, spread;
        kite_wind=kite_wind(weather, table, lat, lon, time, wind_10m))
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
    return EdgeSample(table, weather, lat, lon, time,
        corridor.edge_course[stage, lateral, step])
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
    held_speed(table, speed_index, sample, aloft)

Highest routing speed number up to `speed_index` of the [`RouteTable`](@ref) `table`
that the ship can hold at the [`EdgeSample`](@ref) or [`SharedStart`](@ref) `sample` with
the rig stowed or, on an edge begun with a kite `aloft`, with a kite flying where it can;
begun with it down, a flying kite holds a speed only where the stowed rig holds none.
Returns it with the [`expected_fuels`](@ref) and chance of flying there; speed number 0 if
none holds.
"""
function held_speed(table::RouteTable, speed_index, sample, aloft)
    condition = sea_condition(sample)
    for i in speed_index:-1:1
        aloft || !screened_out(table, i, condition; stowed=true) || continue
        flown, stowed, chance = expected_fuels(table, i, sample)
        isfinite(stowed) && return i, flown, stowed, chance
        aloft && isfinite(flown) && chance > 0 && return i, flown, stowed, chance
    end
    (aloft || !has_kite(table)) && return 0, Inf, Inf, 0.0
    for i in speed_index:-1:1
        flown, stowed, chance = expected_fuels(table, i, sample)
        isfinite(flown) && chance > 0 && return i, flown, stowed, chance
    end
    return 0, Inf, Inf, 0.0
end

"""
    certain_fuels(table, speed_index, condition, headwind, crosswind,
                  sea=sea_layer(table, speed_index, condition))

Fuel power [W] with the rig flown and with any kite stowed at routing speed number
`speed_index` of the [`RouteTable`](@ref) `table` in the [`SeaCondition`](@ref)
`condition`, whose [`sea_layer`](@ref) is `sea`, and 1.0 where a kite can stay up in that
wind, else 0.0.
"""
function certain_fuels(table::RouteTable, speed_index, condition, headwind, crosswind,
        sea...)
    flown, stowed = edge_fuels(table, speed_index, condition, sea...)
    aloft = kite_aloft(table.table, table.speeds[speed_index], headwind, crosswind)
    return flown, stowed, Float64(aloft)
end

"nodes of the three-point Gauss rule for a standard normal variable"
const SPREAD_NODES = (-sqrt(3.0), 0.0, sqrt(3.0))
"weights of the [`SPREAD_NODES`](@ref)"
const SPREAD_WEIGHTS = (1 / 6, 2 / 3, 1 / 6)

"""
    expected_fuels(table, speed_index, sample)

Fuel power [W] with the rig flown and with any kite stowed at routing speed number
`speed_index` of the [`RouteTable`](@ref) `table`, and the chance a kite can stay up there,
over the error of the wind speed of the [`EdgeSample`](@ref) `sample`. A kite that cannot
stay up in one of the winds burns the stowed fuel there.
"""
function expected_fuels(table::RouteTable, speed_index, sample::EdgeSample)
    (; spread, wind_speed, condition, headwind, crosswind) = sample
    spread > 0 ||
        return certain_fuels(table, speed_index, condition, headwind, crosswind)
    sea = sea_layer(table, speed_index, condition)
    flown, stowed, aloft = certain_fuels(table, speed_index, condition, headwind,
        crosswind, sea)
    expected_flown, expected_stowed, chance = 0.0, 0.0, 0.0
    for (node, weight) in zip(SPREAD_NODES, SPREAD_WEIGHTS)
        wind = max(wind_speed + node * spread, 0.0)
        scale = wind_speed > 0 ? wind / wind_speed : 1.0
        node_flown, node_stowed, node_aloft = node == 0 ? (flown, stowed, aloft) :
            certain_fuels(table, speed_index, with_wind(table.table, condition, wind),
                scale * headwind, scale * crosswind, sea)
        isfinite(node_stowed) || (node_stowed = stowed)
        up = isfinite(node_flown) && node_aloft > 0
        expected_stowed += weight * node_stowed
        expected_flown += weight * (up ? node_flown : node_stowed)
        chance += weight * up
    end
    return expected_flown, expected_stowed, chance
end

"""
    StartFuels()

The [`expected_fuels`](@ref) found so far at each routing speed of one
[`EdgeSample`](@ref), for the edges that start from it to share.
"""
struct StartFuels
    "fuel power flown and stowed [W] and chance of flying [-] at each routing speed number,
    where `found`"
    fuels::Vector{NTuple{3, Float64}}
    found::Vector{Bool}
end

StartFuels() = StartFuels(NTuple{3, Float64}[], Bool[])

"""
    SharedStart(fuels, table, sample)

The [`EdgeSample`](@ref) `sample` the edges from a node start from, with the
[`StartFuels`](@ref) `fuels` they share there, cleared for the speeds of the
[`RouteTable`](@ref) `table`.
"""
struct SharedStart
    sample::EdgeSample
    fuels::StartFuels
    function SharedStart(fuels::StartFuels, table::RouteTable, sample::EdgeSample)
        resize!(fuels.fuels, length(table.speeds))
        fill!(resize!(fuels.found, length(table.speeds)), false)
        return new(sample, fuels)
    end
end

"[`SeaCondition`](@ref) of an [`EdgeSample`](@ref) or [`SharedStart`](@ref)"
sea_condition(sample::EdgeSample) = sample.condition
sea_condition(start::SharedStart) = start.sample.condition

function expected_fuels(table::RouteTable, speed_index, start::SharedStart)
    (; fuels, found) = start.fuels
    found[speed_index] && return fuels[speed_index]
    found[speed_index] = true
    return fuels[speed_index] = expected_fuels(table, speed_index, start.sample)
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
    SailedPoint(sample.headwind, sample.crosswind, sample.condition, held, flown, stowed,
        hours, time, chance)
SailedPoint(start::SharedStart, held, flown, stowed, hours, time, chance) =
    SailedPoint(start.sample, held, flown, stowed, hours, time, chance)

"""
    SailedPoint(table, sample, speed_index, aloft, distance, time)

[`SailedPoint`](@ref) of `sample` at commanded routing speed number `speed_index` of
`table`, at the [`held_speed`](@ref) of an edge begun with a kite `aloft` or down, standing
for `distance` [m] of the edge, reached at `time` [h].
"""
function SailedPoint(table::RouteTable, sample, speed_index, aloft, distance, time)
    held, flown, stowed, chance = held_speed(table, speed_index, sample, aloft)
    hours = held == 0 ? Inf : distance / table.speeds[held] / 3600
    return SailedPoint(sample, held, flown, stowed, hours, time, chance)
end

"""
    sail_edge!(points, start, table, weather, corridor, stage, lateral, step, time,
               speed_index, aloft, sample_hours=ROUTER_SETTINGS[].edge_sample_hours;
               from=0.0)

Fill `points` with the [`SailedPoint`](@ref)s of edge `step` of node (`stage`, `lateral`)
from share `from` (0 to 1) of it, left at `time` [h] with a kite `aloft` or down at
commanded routing speed number `speed_index` of `table`, the first from the
[`EdgeSample`](@ref) `start`: equally spaced in distance, at most `sample_hours` [h] apart
at the commanded speed, each standing for its trapezoidal share of the distance at the
speed held there, and each taken when the ship would reach it at the speed held at the
point before. Returns the hours to the end of the edge, the sum of those shares, or `Inf`
if a point cannot hold the lowest routing speed.
"""
function sail_edge!(points, start, table::RouteTable, weather, corridor, stage, lateral,
        step, time, speed_index, aloft, sample_hours=ROUTER_SETTINGS[].edge_sample_hours;
        from=0.0)
    distance = (1 - from) * corridor.edge_length[stage, lateral, step]
    intervals = edge_intervals(distance / table.speeds[speed_index] / 3600, sample_hours)
    resize!(points, intervals + 1)
    points[1] = SailedPoint(table, start, speed_index, aloft,
        trapezoid_weight(1, intervals + 1) * distance, time)
    hours, sample_time = points[1].hours, time
    for k in 1:intervals
        isfinite(hours) || return Inf
        sample_time += distance / intervals / table.speeds[points[k].speed_index] / 3600
        sample = EdgeSample(table.table, weather, corridor, stage, lateral, step,
            from + (1 - from) * k / intervals, sample_time)
        points[k + 1] = SailedPoint(table, sample, speed_index, aloft,
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
    forced_landing(tally)

`tally` followed by a landing outside the landing limits.
"""
forced_landing(tally::EdgeTally) = EdgeTally(tally.cost, tally.energy, tally.flight_hours,
    tally.launches, tally.forced_landings + 1)

"speed [m/s] of `table` held at [`SailedPoint`](@ref) `point`, zero where none is"
sailed_speed(table::RouteTable, point) =
    point.speed_index == 0 ? 0.0 : table.speeds[point.speed_index]

"""
    kite_passage(table, points, aloft, prices)

Cheapest ways through the [`SailedPoint`](@ref)s of an edge on the [`RouteTable`](@ref)
`table` that end with the kite down and with it aloft, for a kite aloft before the first
point if `aloft`, as [`EdgeTally`](@ref)s. At each point a kite down burns the stowed
fuel, and cannot be down where only a flying kite holds the speed; where
[`kite_aloft`](@ref) allows, a kite aloft flies, and where [`kite_launchable`](@ref)
allows, a kite down may launch. A kite aloft can come down wherever [`kite_landable`](@ref)
allows, its cost being part of the launch; outside it only as a [`forced_landing`](@ref),
where the kite can neither stay up nor have come down earlier on the edge. Wings and rotors
stay down, burning their fuel with the rig standing.
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
    speed = sailed_speed(table, point)
    (; headwind, crosswind) = point
    (; wave_height) = point.condition
    stays = point.chance > 0 ?
            aloft_tally(table.table, up, point, false, prices) : NO_TALLY
    forced = !kite_landable(table.table, speed, headwind, crosswind, wave_height)
    stranded = !isfinite(down.cost) && !isfinite(stays.cost)
    landing = !forced ? up : stranded ? forced_landing(up) : NO_TALLY
    landed = landing.cost < down.cost
    next_down = extend(landed ? landing : down, point.stowed, point.hours, 0.0, STOWED,
        false, prices, table.table.cycle_cost)
    launches = kite_launchable(table.table, speed, headwind, crosswind, wave_height) ?
               aloft_tally(table.table, down, point, true, prices) : NO_TALLY
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
    StateRows

Which rows of states, the lateral nodes of one (time bin, aloft, stage), the
[`StateArray`](@ref)s of one [`RouteWorkspace`](@ref) hold.
"""
struct StateRows
    "number of the row of each (time bin, aloft, stage), 0 where it is not held"
    row::Array{Int32, 3}
    "rows held"
    count::Base.RefValue{Int}
    "lateral nodes of a row"
    lateral_count::Int
end

"""
    StateArray{T}

A value per state of the routing dynamic programme, indexed (lateral, time bin, kite down
1 or aloft 2, stage), that holds only the rows of `rows` written to: every other state
reads `unset`, and writing `unset` to a row not held holds nothing.
"""
struct StateArray{T} <: AbstractArray{T, 4}
    rows::StateRows
    "values of the rows held, row after row, as far as this array was written to"
    values::Vector{T}
    "value of a state not written to"
    unset::T
end

StateArray(rows::StateRows, unset) = StateArray(rows, typeof(unset)[], unset)

Base.size(states::StateArray) = (states.rows.lateral_count, size(states.rows.row)...)

function Base.getindex(states::StateArray, lateral::Int, bin::Int, aloft::Int, stage::Int)
    @boundscheck checkbounds(states, lateral, bin, aloft, stage)
    (; rows, values) = states
    index = (rows.row[bin, aloft, stage] - 1) * rows.lateral_count + lateral
    return 0 < index <= length(values) ? values[index] : states.unset
end

function Base.setindex!(states::StateArray, value, lateral::Int, bin::Int, aloft::Int,
        stage::Int)
    @boundscheck checkbounds(states, lateral, bin, aloft, stage)
    (; rows, values, unset) = states
    row = rows.row[bin, aloft, stage]
    if row == 0
        isequal(value, unset) && return states
        row = rows.row[bin, aloft, stage] = (rows.count[] += 1)
    end
    held = length(values)
    if held < row * rows.lateral_count
        resize!(values, rows.count[] * rows.lateral_count)
        fill!(view(values, (held + 1):length(values)), unset)
    end
    values[(row - 1) * rows.lateral_count + lateral] = value
    return states
end

"""
    RouteWorkspace

States of the routing dynamic programme, indexed (lateral, time bin, kite down 1 or aloft
2, stage).
"""
struct RouteWorkspace
    "objective of the best arrival [USD], `Inf` where there is none"
    cost::StateArray{Float64}
    "hours from departure to the arrival [h]"
    elapsed::StateArray{Float64}
    "fuel energy up to the arrival [J]"
    energy::StateArray{Float64}
    "hours of kite flight up to the arrival [h]"
    flight_hours::StateArray{Float64}
    "kite launches up to the arrival"
    launches::StateArray{Int32}
    "kite landings outside the landing limits up to the arrival"
    forced_landings::StateArray{Int32}
    "state of the previous stage, as the linear index of (bin, lateral, aloft)"
    parent::StateArray{Int32}
    "routing speed number of the edge into the state"
    speed_index::StateArray{Int16}
    "mode of the edge into the state"
    mode::StateArray{Int8}
    "the points of the edge in hand"
    points::Vector{SailedPoint}
    "values of the latest [`CostToGo`](@ref), grown to the most time knots asked of it"
    to_go_values::Base.RefValue{Array{Float64, 4}}
    "whether each knot of the latest [`CostToGo`](@ref) is still to compute, grown as
    `to_go_values`"
    pending_knots::Base.RefValue{BitArray{3}}
    "buffers for the points of an edge of the [`CostToGo`](@ref), not in use"
    spare_points::Vector{Vector{SailedPoint}}
    "edges sailed from a node with the kite down for its state aloft at the same time"
    shared::Vector{SailedEdge}
    "index in `shared` before the edges of each time bin, -1 where it holds none"
    shared_from::Vector{Int}
    "routing speed numbers commanded on the edges from the node in hand, step by step"
    commanded::Vector{Int}
    "index in `commanded` before the speeds of each step"
    commanded_from::Vector{Int}
    "fuels found at the start of the edges from the node in hand"
    start_fuels::StartFuels
end

"""
    RouteWorkspace(lateral_count, bins, stage_count)

Workspace for corridors of `lateral_count` nodes per stage, `bins` time bins and up to
`stage_count` stages, holding no state.
"""
function RouteWorkspace(lateral_count, bins, stage_count)
    rows = StateRows(zeros(Int32, bins, 2, stage_count), Ref(0), lateral_count)
    unset = (Inf, 0.0, 0.0, 0.0, Int32(0), Int32(0), Int32(0), Int16(0), Int8(0))
    return RouteWorkspace(StateArray.(Ref(rows), unset)..., SailedPoint[],
        Ref(zeros(lateral_count, 0, 2, stage_count)),
        Ref(falses(lateral_count, 0, stage_count)), Vector{SailedPoint}[], SailedEdge[],
        fill(-1, bins), Int[], Int[], StartFuels())
end

"""
    empty_states!(workspace)

Hold no state in `workspace`.
"""
function empty_states!(workspace::RouteWorkspace)
    (; cost, elapsed, energy, flight_hours, launches, forced_landings, parent, speed_index,
        mode) = workspace
    fill!(cost.rows.row, 0)
    cost.rows.count[] = 0
    foreach(states -> empty!(states.values), (cost, elapsed, energy, flight_hours,
        launches, forced_landings, parent, speed_index, mode))
    return workspace
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

"""
    commanded_speeds!(commanded, speeds, stride, distance, time_step)

Append to `commanded` the ascending [`commanded_speeds`](@ref) of `speeds` [m/s] at
`stride` on an edge of `distance` [m] and the fewest speeds between them that bring
their arrivals within `time_step` [h] of each other, or as near as neighbouring speeds go.
"""
function commanded_speeds!(commanded, speeds, stride, distance, time_step)
    start = length(commanded)
    for speed_index in commanded_speeds(length(speeds), stride)
        while length(commanded) > start && last(commanded) < speed_index - 1 &&
            arrival_gap(distance, speeds[last(commanded)], speeds[speed_index]) > time_step
            slower, faster = last(commanded), last(commanded) + 1
            while arrival_gap(distance, speeds[slower], speeds[faster + 1]) <= time_step
                faster += 1
            end
            push!(commanded, faster)
        end
        push!(commanded, speed_index)
    end
    return commanded
end

"hours [h] by which an edge of `distance` [m] at speed `faster` arrives before one at
`slower` [m/s]"
arrival_gap(distance, slower, faster) = distance * (1 / slower - 1 / faster) / 3600

"""
    CostToGo

Estimate of the objective [USD] from a state to the destination, from a coarser programme:
it can lie on either side of the true value. Called on (lateral, aloft 1 or 2, stage,
hours after departure), interpolating in time; `NaN` where no path was found although
the time was searched, `Inf` beyond the times searched. A value its [`KnotFiller`](@ref)
holds pending is computed when first asked.
"""
struct CostToGo{F}
    "objective to the destination [USD], lateral × knot × aloft × stage"
    values::Array{Float64, 4}
    "time knots in use"
    knots::Int
    "time between the knots [h]"
    step::Float64
    "the [`KnotFiller`](@ref) of the values not yet computed, `nothing` where all are"
    filler::F
end

CostToGo(values::Array{Float64, 4}, knots, step) = CostToGo(values, knots, step, nothing)
CostToGo(values::Array{Float64, 4}, step) = CostToGo(values, size(values, 2), step)

"""
    KnotFiller

What [`fill_knot!`](@ref) needs to compute the values of a [`CostToGo`](@ref) still
pending: the passage it estimates, the knots still to compute, buffers for the points of
an edge, and the earlier estimate its values beyond `near_hours` are read from.
"""
struct KnotFiller{C, T, W, P}
    corridor::C
    table::T
    weather::W
    "departure of the passage [h]"
    departure::Float64
    "fuel price [USD/J] and time cost [USD/h], as `fuel` and `time`"
    prices::P
    "whether each knot is still to compute, lateral × knot × stage"
    pending::BitArray{3}
    "buffers for the points of an edge, not in use"
    spare_points::Vector{Vector{SailedPoint}}
    "the [`CostToGo`](@ref) of an earlier plan its values beyond `near_hours` are read
    from, or `nothing`"
    previous::Union{Nothing, CostToGo{KnotFiller{C, T, W, P}}}
    "hours after `departure` within which the values are computed [h]"
    near_hours::Float64
end

function (to_go::CostToGo)(lateral, aloft, stage, time)
    position = time / to_go.step + 1
    knot = floor(Int, position)
    knot < to_go.knots || return Inf
    filled!(to_go, lateral, knot, stage)
    filled!(to_go, lateral, knot + 1, stage)
    @inbounds lower, upper = to_go.values[lateral, knot, aloft, stage],
    to_go.values[lateral, knot + 1, aloft, stage]
    isfinite(lower) && isfinite(upper) && return lower + (position - knot) * (upper - lower)
    isfinite(lower) && return lower
    isfinite(upper) && return upper
    return isnan(lower) || isnan(upper) ? NaN : Inf
end

"""
    CostToGo(held, corridor, table, weather, departure; time_cost, first_stage,
             previous=nothing, near_hours=Inf)

[`CostToGo`](@ref) of a passage leaving at `departure` [h], its values held in `held`, a
[`RouteWorkspace`](@ref) or a reference to an array, by a backward programme over the
states at each stage that a ship can reach between its highest and lowest routing speed,
at the knots of `ROUTER_SETTINGS`, on every `COST_TO_GO_SPEED_STRIDE`-th speed the search
commands. Each value is computed when first asked; with a [`CostToGo`](@ref) `previous`
of an earlier plan, those more than `near_hours` [h] ahead are read from it where it has
them.
"""
function CostToGo(held, corridor::Corridor, table::RouteTable, weather, departure;
        time_cost, first_stage, previous=nothing, near_hours=Inf)
    stage_count = size(corridor.lat, 1)
    along = corridor.along_centre
    slowest, fastest = first(table.speeds), last(table.speeds)
    (; to_go_step) = ROUTER_SETTINGS[]
    knots = ceil(Int, (last(along) / slowest / 3600 + REACH_SLACK) / to_go_step) + 2
    values = cleared_to_go_values!(held, knots)
    values[centre_index(corridor), 1:knots, 1, stage_count] .= 0.0
    pending = cleared_pending_knots!(held, knots)
    for stage in first_stage:(stage_count - 1)
        sailed = along[stage] - along[first_stage]
        earliest = SHORTEST_SAILED_SHARE * sailed / fastest / 3600
        latest = sailed / slowest / 3600 + REACH_SLACK
        searched = max(1, floor(Int, earliest / to_go_step)):min(knots,
            ceil(Int, latest / to_go_step) + 1)
        pending[:, searched, stage] .= view(corridor.water, stage, :)
    end
    prices = (; fuel=table.table.ship.fuel.price, time=time_cost)
    filler = KnotFiller(corridor, table, weather, Float64(departure), prices, pending,
        spare_points(held), isfinite(near_hours) ? previous : nothing, near_hours)
    return CostToGo(values, knots, to_go_step, filler)
end

"""
    cleared_to_go_values!(held, knots)

The [`CostToGo`](@ref) values of the [`RouteWorkspace`](@ref) or array reference `held`,
with room for `knots` time knots, all `Inf`.
"""
cleared_to_go_values!(workspace::RouteWorkspace, knots) =
    cleared_to_go_values!(workspace.to_go_values, knots)

function cleared_to_go_values!(held::Base.RefValue{Array{Float64, 4}}, knots)
    lateral_count, room, aloft, stage_count = size(held[])
    room < knots &&
        (held[] = Array{Float64}(undef, lateral_count, knots, aloft, stage_count))
    return fill!(held[], Inf)
end

"""
    cleared_pending_knots!(held, knots)

Whether each knot of the [`CostToGo`](@ref) whose values `held` holds is still to compute,
lateral × knot × stage, with room for `knots` time knots, all `false`.
"""
function cleared_pending_knots!(workspace::RouteWorkspace, knots)
    lateral_count, room, stage_count = size(workspace.pending_knots[])
    room < knots && (workspace.pending_knots[] = falses(lateral_count, knots, stage_count))
    return fill!(workspace.pending_knots[], false)
end

cleared_pending_knots!(held::Base.RefValue{Array{Float64, 4}}, knots) =
    falses(size(held[], 1), knots, size(held[], 4))

"buffers for the points of an edge not in use, kept in `held` where it is a workspace"
spare_points(workspace::RouteWorkspace) = workspace.spare_points
spare_points(::Base.RefValue{Array{Float64, 4}}) = Vector{SailedPoint}[]

"""
    filled!(to_go, lateral, knot, stage)

Compute the values of `to_go` at node (`stage`, `lateral`) and `knot` where they are still
pending.
"""
filled!(::CostToGo{Nothing}, lateral, knot, stage) = nothing

function filled!(to_go::CostToGo{<:KnotFiller}, lateral, knot, stage)
    filler = to_go.filler
    filler.pending[lateral, knot, stage] || return nothing
    filler.pending[lateral, knot, stage] = false
    read_earlier!(to_go, filler.previous, lateral, knot, stage) && return nothing
    points = isempty(filler.spare_points) ? SailedPoint[] : pop!(filler.spare_points)
    fill_knot!(to_go, points, filler.corridor, filler.table, filler.weather,
        filler.departure, filler.prices, stage, lateral, knot)
    push!(filler.spare_points, points)
    return nothing
end

"""
    read_earlier!(to_go, previous, lateral, knot, stage)

Whether the values of `to_go` at node (`stage`, `lateral`) and `knot` are set from the
[`CostToGo`](@ref) `previous` of an earlier plan at the same time, interpolated between
its knots, as they are beyond the filler's `near_hours` where `previous` has a value there.
"""
read_earlier!(to_go, ::Nothing, lateral, knot, stage) = false

function read_earlier!(to_go, previous::CostToGo, lateral, knot, stage)
    time = (knot - 1) * to_go.step
    time > to_go.filler.near_hours || return false
    earlier = time + to_go.filler.departure - previous.filler.departure
    down = previous(lateral, 1, stage, earlier)
    down == Inf && return false
    to_go.values[lateral, knot, 1, stage] = down
    to_go.values[lateral, knot, 2, stage] = previous(lateral, 2, stage, earlier)
    return true
end

"""
    all_filled!(to_go)

`to_go` with every value it holds pending computed.
"""
all_filled!(to_go::CostToGo{Nothing}) = to_go

function all_filled!(to_go::CostToGo{<:KnotFiller})
    laterals, knots, stages = axes(to_go.filler.pending)
    for stage in reverse(stages), lateral in laterals, knot in knots
        filled!(to_go, lateral, knot, stage)
    end
    return to_go
end

"hours a [`CostToGo`](@ref) searches beyond the arrival at the lowest routing speed [h]"
const REACH_SLACK = 96.0

"least distance sailed to a stage, as a share of the distance along the centre line [-]"
const SHORTEST_SAILED_SHARE = 0.8

"""
    fill_knot!(to_go, points, corridor, table, weather, departure, prices, stage, lateral,
               knot)

Set the values of `to_go` at node (`stage`, `lateral`) and `knot`, kite down and aloft,
from those of the next stage, with `points` to hold those of the edges.
"""
function fill_knot!(to_go, points, corridor, table, weather, departure, prices, stage,
        lateral, knot)
    time = (knot - 1) * to_go.step
    lat, lon = corridor.lat[stage, lateral], corridor.lon[stage, lateral]
    node_wind = wind(weather, lat, lon, departure + time)
    node_waves = waves(weather, lat, lon, departure + time)
    node_kite = kite_wind(weather, table.table, lat, lon, departure + time, node_wind)
    kite = has_kite(table)
    speed_stride = COST_TO_GO_SPEED_STRIDE * ROUTER_SETTINGS[].search_speed_stride
    sample_hours = max(ROUTER_SETTINGS[].to_go_sample_hours, corridor.sample_hours[stage])
    best_down, best_up = Inf, Inf
    for step in 1:step_count(corridor)
        isnan(corridor.edge_course[stage, lateral, step]) && continue
        next = next_lateral(corridor, lateral, step)
        start = EdgeSample(table.table, node_wind, node_waves,
            corridor.edge_course[stage, lateral, step],
            wind_spread(weather, departure + time); kite_wind=node_kite)
        arrival = (; prices, next, stage=stage + 1, time)
        through = 0
        for speed_index in commanded_speeds(length(table.speeds), speed_stride)
            speed_index <= through && continue
            edge = (; start, weather, corridor, stage, lateral, step, speed_index,
                sample_hours, time=departure + time)
            hours, through = sailed_hours!(points, table, edge, kite)
            if kite
                isfinite(hours) && (best_up = min(best_up,
                    best_arrival(to_go, table, points, true, hours, arrival)))
                hours, down_through = sailed_down!(points, table, edge, hours, through)
                through = min(through, down_through)
            end
            isfinite(hours) || continue
            best_down = min(best_down, best_arrival(to_go, table, points, false, hours,
                arrival))
        end
    end
    to_go.values[lateral, knot, 1, stage] = isfinite(best_down) ? best_down : NaN
    kite && (to_go.values[lateral, knot, 2, stage] = isfinite(best_up) ? best_up : NaN)
end

"""
    best_arrival(to_go, table, points, aloft, hours, edge)

Least objective [USD] to the destination through the [`SailedPoint`](@ref)s `points` of
an edge sailed in `hours` [h] for a kite aloft before it if `aloft`, then by `to_go` from
the node `next` of stage `stage` that `edge`, left at `time` [h], arrives at.
"""
function best_arrival(to_go, table, points, aloft, hours, (; prices, next, stage, time))
    down, up = kite_passage(table, points, aloft, prices)
    best = Inf
    for (tally, next_aloft) in ((down, 1), (up, 2))
        isfinite(tally.cost) || continue
        ahead = to_go(next, next_aloft, stage, time + hours)
        isnan(ahead) && continue
        best = min(best, edge_objective(tally.cost, hours, prices) + ahead)
    end
    return best
end

"longest passage a route searches [h]"
const MAX_LEG_HOURS = 1200.0

"""
    route(corridor, table, weather, departure; time_cost, arrival_by=Inf, first_stage=1,
          first_lateral, first_aloft=false, record=nothing)

Weather routing by forward dynamic programming over (stage, lateral node, arrival time
bin, kite aloft) on the routing speeds of the [`RouteTable`](@ref) `table`, or of a
[`PerformanceTable`](@ref). Minimises fuel cost plus rig wear and kite launches plus
`time_cost` [USD/h] times duration for a departure at `departure` [h]; times in hours.
With a finite `arrival_by` [h] it arrives by then, charged that time, or as early as it can
where no path does.
Each edge is sailed at a commanded speed by [`sail_edge!`](@ref), slowing where the
engine cannot hold it, with the kite managed along it by [`kite_passage`](@ref); it is
infeasible only where the lowest routing speed cannot be held. The passage starts at node
`first_lateral` of stage `first_stage` with the kite aloft if `first_aloft`.

The time bins, the speeds commanded and the states searched follow `ROUTER_SETTINGS`: those
within a margin of a [`CostToGo`](@ref), wider where that leaves no path within the margin,
then all of them. A [`final_pass`](@ref) then refines the speeds along the path found.
A [`SearchRecord`](@ref) `record` receives what the search kept. Returns `nothing` if no
path arrives within `MAX_LEG_HOURS`.
"""
function route(corridor::Corridor, table::RouteTable, weather, departure; time_cost,
        arrival_by=Inf, first_stage=1, first_lateral=centre_index(corridor),
        first_aloft=false, record=nothing)
    (; time_step) = ROUTER_SETTINGS[]
    options = (; time_step, time_cost, arrival_by, first_stage, first_lateral, first_aloft,
        speed_stride=ROUTER_SETTINGS[].search_speed_stride)
    workspace = acquire_workspace(size(corridor.lat, 2), bin_count(time_step),
        size(corridor.lat, 1))
    try
        to_go = CostToGo(workspace, corridor, table, weather, departure; time_cost,
            first_stage)
        estimate = to_go(first_lateral, first_aloft + 1, first_stage, 0.0)
        limits = (1 .+ ROUTER_SETTINGS[].search_margins) .* estimate
        kite = has_kite(table) && !ROUTER_SETTINGS[].kite_states_searched ?
               KiteRule(table.table.cycle_cost, size(corridor.lat, 1)) : nothing
        leg, limit = searched_leg(workspace, corridor, table, weather, departure, to_go,
            limits, kite; options...)
        isnothing(record) || record!(record, workspace, size(corridor.lat, 1),
            (; to_go, estimate, limits, limit, found=leg))
        isnothing(leg) && return nothing
        return final_pass(leg, corridor, table, weather, departure; time_cost, arrival_by,
            first_stage, first_aloft)
    finally
        release_workspace(workspace)
    end
end

route(corridor::Corridor, table::PerformanceTable, weather, departure; options...) =
    route(corridor, RouteTable(table), weather, departure; options...)

"""
    KiteRule(relaunch, last_stage)

How a search that keeps one kite state per node and time bin values an arrival with the
kite aloft against one with it down: as worth the cost `relaunch` [USD] of a launch, except
at `last_stage`, where the kite must be down.
"""
struct KiteRule
    relaunch::Float64
    last_stage::Int
end

"""
    arrival_value(rule, aloft, stage)

Value [USD] the [`KiteRule`](@ref) `rule` adds to an arrival at `stage` with the kite down
(`aloft` 1) or aloft (2); `Inf` where it cannot go on.
"""
function arrival_value(rule::KiteRule, aloft, stage)
    aloft == 1 && return 0.0
    return stage == rule.last_stage ? Inf : -rule.relaunch
end

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
        along_centre_line(lat, lon), MAX_LATERAL_STEP, 0.0,
        zeros(stage_count), nothing)
end

"""
    path_corridor(leg, corridor, first_stage)

[`Corridor`](@ref) of one node per stage along the path of `leg` through `corridor`, stage 1
being its `first_stage`.
"""
function path_corridor(leg::Leg, corridor::Corridor, first_stage)
    lat = [point[1] for point in leg.path]
    lon = [point[2] for point in leg.path]
    laterals = [nearest_lateral(corridor, first_stage + i - 1, lat[i], lon[i])
                for i in eachindex(lat)]
    return path_corridor(corridor, first_stage, laterals, lat, lon)
end

"""
    path_corridor(corridor, first_stage, laterals, lat, lon)

[`Corridor`](@ref) of one node per stage, at `lat` and `lon` [deg], along the edges of
`corridor` through lateral node `laterals[i]` of its stage `first_stage + i - 1`; `lat` and
`lon` default to those nodes.
"""
function path_corridor(corridor::Corridor, first_stage, laterals,
        lat=getindex.(Ref(corridor.lat), first_stage - 1 .+ eachindex(laterals), laterals),
        lon=getindex.(Ref(corridor.lon), first_stage - 1 .+ eachindex(laterals), laterals))
    stage_count = length(laterals)
    edge_length = zeros(stage_count - 1, 1, 2MAX_LATERAL_STEP + 1)
    edge_course = fill(NaN, stage_count - 1, 1, 2MAX_LATERAL_STEP + 1)
    for i in 1:(stage_count - 1)
        stage = first_stage + i - 1
        step = lateral_step(corridor, laterals[i], laterals[i + 1])
        edge_length[i, 1, STRAIGHT_ON] = corridor.edge_length[stage, laterals[i], step]
        edge_course[i, 1, STRAIGHT_ON] = corridor.edge_course[stage, laterals[i], step]
    end
    return Corridor(reshape(lat, stage_count, 1), reshape(lon, stage_count, 1),
        trues(stage_count, 1), edge_length, edge_course, corridor.track_length,
        along_centre_line(reshape(lat, stage_count, 1), reshape(lon, stage_count, 1)),
        MAX_LATERAL_STEP, 0.0, zeros(stage_count), nothing)
end

"""
    shortest_corridor(corridor)

[`path_corridor`](@ref) along the shortest path through `corridor` from the centre of its
first stage to the centre of its last.
"""
function shortest_corridor(corridor::Corridor)
    stages, laterals = size(corridor.lat)
    centre = centre_index(corridor)
    distance_to = fill(Inf, stages, laterals)
    previous = zeros(Int, stages, laterals)
    distance_to[1, centre] = 0.0
    for stage in 1:(stages - 1), lateral in 1:laterals, step in 1:step_count(corridor)
        next = next_lateral(corridor, lateral, step)
        (1 <= next <= laterals && !isnan(corridor.edge_course[stage, lateral, step])) ||
            continue
        through = distance_to[stage, lateral] + corridor.edge_length[stage, lateral, step]
        through < distance_to[stage + 1, next] || continue
        distance_to[stage + 1, next] = through
        previous[stage + 1, next] = lateral
    end
    isfinite(distance_to[stages, centre]) || error("no path through the corridor")
    path = [centre]
    for stage in stages:-1:2
        pushfirst!(path, previous[stage, first(path)])
    end
    return path_corridor(corridor, 1, path)
end

"length of the time bins [h] of the [`final_pass`](@ref) of a plan on `weather`"
final_time_step(weather) = ROUTER_SETTINGS[].final_time_step

"""
    final_pass(leg, corridor, table, weather, departure; time_cost, arrival_by=Inf,
               first_stage, first_aloft)

The cheaper of `leg` and the [`route_pass`](@ref) along its path at all speeds of `table`,
on the bins of [`final_time_step`](@ref) and within the band in time of
`ROUTER_SETTINGS`, of those arriving by `arrival_by` [h] or no later than `leg`.
"""
function final_pass(leg::Leg, corridor, table, weather, departure; time_cost,
        arrival_by=Inf, first_stage, first_aloft)
    time_step = final_time_step(weather)
    workspace = acquire_workspace(1, bin_count(time_step), length(leg.path))
    try
        band = PassageBand([point[3] for point in leg.path],
            ROUTER_SETTINGS[].final_time_band)
        refined = route_pass(workspace, path_corridor(leg, corridor, first_stage), table,
            weather, departure, band; time_cost, arrival_by, time_step, first_stage=1,
            first_lateral=1, first_aloft, speed_stride=1)
        isnothing(refined) && return leg
        refined.duration <= arrival_by < leg.duration && return refined
        refined.duration > max(arrival_by, leg.duration) && return leg
        return refined.objective > leg.objective ? leg : refined
    finally
        release_workspace(workspace)
    end
end

"""
    searched_leg(workspace, corridor, table, weather, departure, to_go, limits,
                 kite=nothing; options...)

The [`Leg`](@ref) of the first [`route_pass`](@ref) with the [`KiteRule`](@ref) `kite`
under `limits` [USD] that ends within its limit and by the `arrival_by` of `options`, and
that limit, else of a pass over all states, which is `nothing` if no path arrives, and
`Inf`.
"""
function searched_leg(workspace, corridor, table, weather, departure, to_go, limits,
        kite=nothing; options...)
    for limit in limits
        leg = route_pass(workspace, corridor, table, weather, departure, to_go, limit;
            kite, options...)
        isnothing(leg) && continue
        leg.objective <= limit && leg.duration <= options[:arrival_by] && return leg, limit
    end
    return route_pass(workspace, corridor, table, weather, departure; kite, options...), Inf
end

"""
    SearchRecord()

What a [`route`](@ref) search kept: its [`CostToGo`](@ref) and the estimate it gave at the
departure [USD], the limits tried [USD] and the one whose pass gave the path (`Inf` for a
pass over all states), the objective [USD] and hours after departure of the best arrival
at each state of that pass (lateral × time bin × kite down 1 or aloft 2 × stage; `Inf`
where none arrived), and the [`Leg`](@ref) it found before the [`final_pass`](@ref),
`nothing` where none arrived.
"""
mutable struct SearchRecord
    to_go::CostToGo{Nothing}
    estimate::Float64
    limits::Vector{Float64}
    limit::Float64
    cost::Array{Float64, 4}
    elapsed::Array{Float64, 4}
    found::Union{Leg, Nothing}
    SearchRecord() = new()
end

"""
    record!(record, workspace, stage_count, search)

Copy into the [`SearchRecord`](@ref) `record` the states of the first `stage_count` stages
held in `workspace` and the rest of the `search`, named as its fields.
"""
function record!(record::SearchRecord, workspace, stage_count, search)
    to_go = all_filled!(search.to_go)
    record.to_go = CostToGo(to_go.values[:, :, :, 1:stage_count], to_go.knots, to_go.step)
    record.estimate, record.limit = search.estimate, search.limit
    record.limits = collect(search.limits)
    record.cost = workspace.cost[:, :, :, 1:stage_count]
    record.elapsed = workspace.elapsed[:, :, :, 1:stage_count]
    record.found = search.found
    return record
end

"""
    kept_states(record)

Whether each state of the [`SearchRecord`](@ref) `record` was reached and searched on, its
objective plus the cost to go within the limit; lateral × time bin × aloft × stage.
"""
kept_states(record::SearchRecord) = [isfinite(record.cost[state]) &&
                                     within_limit(record.to_go, record.limit,
                                         record.cost[state], state[1], state[3], state[4],
                                         record.elapsed[state])
                                     for state in CartesianIndices(record.cost)]

"""
    through_node(record)

Least objective [USD] of a passage through each node of the search in the
[`SearchRecord`](@ref) `record`, stage × lateral: the objective of a state reached there
plus its cost to go, the least over its time bins and kite states; `Inf` where no state
was reached or no path found onward.
"""
function through_node(record::SearchRecord)
    lateral_count, _, _, stage_count = size(record.cost)
    through = fill(Inf, stage_count, lateral_count)
    for state in CartesianIndices(record.cost)
        here = record.cost[state]
        isfinite(here) || continue
        lateral, _, aloft, stage = Tuple(state)
        total = here + record.to_go(lateral, aloft, stage, record.elapsed[state])
        isnan(total) || (through[stage, lateral] = min(through[stage, lateral], total))
    end
    return through
end

"""
    route_pass(workspace, corridor, table, weather, departure, to_go=nothing, limit=Inf;
               time_cost, arrival_by=Inf, time_step, first_stage, first_lateral,
               first_aloft, speed_stride, kite=nothing)

The dynamic programme of [`route`](@ref) in `workspace`, whose bins are the
[`time_bin`](@ref)s of `time_step` [h], keeping one kite state per node and time bin by
the [`KiteRule`](@ref) `kite`, or both where it is `nothing`, commanding the
[`commanded_speeds!`](@ref) of `table` at `speed_stride` and `time_step`, skipping states
and commanded edges outside the [`PassageBand`](@ref) `to_go`, or, with a
[`CostToGo`](@ref) `to_go`, those whose objective plus it exceeds `limit` [USD]. Returns
the [`Leg`](@ref) of the [`final_arrival`](@ref) by `arrival_by` [h], or `nothing`.
"""
function route_pass(workspace::RouteWorkspace, corridor::Corridor, table::RouteTable,
        weather, departure, to_go=nothing, limit=Inf; time_cost, arrival_by=Inf, time_step,
        first_stage, first_lateral, first_aloft, speed_stride, kite=nothing)
    ship_table = table.table
    (; speeds) = table
    (; cost, elapsed) = workspace
    stage_count, lateral_count = size(corridor.lat)
    bins = size(cost, 2)
    prices = (; fuel=ship_table.ship.fuel.price, time=time_cost)
    empty_states!(workspace)
    start_state!(workspace, (first_lateral, 1, first_aloft + 1, first_stage))
    for stage in first_stage:(stage_count - 1), lateral in 1:lateral_count
        corridor.water[stage, lateral] || continue
        sample_hours = max(ROUTER_SETTINGS[].edge_sample_hours,
            corridor.sample_hours[stage])
        lat, lon = corridor.lat[stage, lateral], corridor.lon[stage, lateral]
        empty!(workspace.shared)
        fill!(workspace.shared_from, -1)
        commanded_edges!(workspace, corridor, speeds, speed_stride, time_step, stage,
            lateral)
        (; commanded, commanded_from) = workspace
        for aloft in 1:2, bin in 1:bins
            here = cost[lateral, bin, aloft, stage]
            isfinite(here) || continue
            time = elapsed[lateral, bin, aloft, stage]
            within_limit(to_go, limit, here, lateral, aloft, stage, time) || continue
            state = (lateral, bin, aloft, stage)
            sharing = sharing_edges!(workspace, state, to_go, limit, length(commanded))
            node_wind = wind(weather, lat, lon, departure + time)
            node_waves = waves(weather, lat, lon, departure + time)
            node_kite = kite_wind(weather, ship_table, lat, lon, departure + time,
                node_wind)
            for step in 1:step_count(corridor)
                isnan(corridor.edge_course[stage, lateral, step]) && continue
                next = next_lateral(corridor, lateral, step)
                distance = corridor.edge_length[stage, lateral, step]
                start = SharedStart(workspace.start_fuels, table, EdgeSample(ship_table,
                    node_wind, node_waves, corridor.edge_course[stage, lateral, step],
                    wind_spread(weather, departure + time); kite_wind=node_kite))
                through = 0
                for slot in (commanded_from[step] + 1):commanded_from[step + 1]
                    speed_index = commanded[slot]
                    speed_index <= through && continue
                    commanded_hours = distance / speeds[speed_index] / 3600
                    edge_within_limit(to_go, limit,
                        here + time_cost * commanded_hours, next, stage + 1,
                        time + commanded_hours) || continue
                    shared = shared_slot(sharing, slot)
                    sailed = sailed_edge!(workspace, shared, aloft == 2, table, prices,
                        (; start, weather, corridor, stage, lateral, step, speed_index,
                            sample_hours, time=departure + time))
                    relax_sailed!(workspace, state, next, sailed, (; here, speed_index),
                        (; time_step, departure), prices, kite)
                    through = sailed.same_through
                end
            end
        end
    end
    final = (centre_index(corridor), :, 1, stage_count)
    objective, bin = final_arrival(view(cost, final...), view(elapsed, final...),
        time_cost, arrival_by)
    isfinite(objective) || return nothing
    return traced_leg(workspace, corridor, table, (centre_index(corridor), bin, 1,
        stage_count), first_stage, objective)
end

"""
    commanded_edges!(workspace, corridor, speeds, speed_stride, time_step, stage, lateral)

Fill `workspace.commanded` with the [`commanded_speeds!`](@ref) of `speeds` [m/s] at
`speed_stride` and `time_step` [h] on each step from node (`stage`, `lateral`) of
`corridor`, and `workspace.commanded_from` with the index before each step's speeds.
"""
function commanded_edges!(workspace::RouteWorkspace, corridor, speeds, speed_stride,
        time_step, stage, lateral)
    (; commanded, commanded_from) = workspace
    empty!(commanded)
    empty!(commanded_from)
    for step in 1:step_count(corridor)
        push!(commanded_from, length(commanded))
        isnan(corridor.edge_course[stage, lateral, step]) && continue
        commanded_speeds!(commanded, speeds, speed_stride,
            corridor.edge_length[stage, lateral, step], time_step)
    end
    push!(commanded_from, length(commanded))
    return workspace
end

"""
    final_arrival(costs, hours, time_cost, arrival_by)

Objective [USD] and time bin of the best of the arrivals at objectives `costs` [USD] after
`hours` [h]: the least, or, with a finite `arrival_by` [h], the least of those arriving by
then charged `time_cost` [USD/h] for that time, else the earliest; `Inf` where none arrives.
"""
function final_arrival(costs, hours, time_cost, arrival_by)
    isinf(arrival_by) && return findmin(costs)
    best, bin, earliest = Inf, 0, 0
    for i in axes(costs, 1)
        isfinite(costs[i]) || continue
        (earliest == 0 || hours[i] < hours[earliest]) && (earliest = i)
        hours[i] <= arrival_by || continue
        objective = costs[i] + time_cost * (arrival_by - hours[i])
        objective < best && ((best, bin) = (objective, i))
    end
    bin > 0 && return best, bin
    return earliest == 0 ? (Inf, 1) : (costs[earliest], earliest)
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
    shared_slot(sharing, slot)

Index in `workspace.shared` of the edge at place `slot` of `workspace.commanded`, for a
state whose [`sharing_edges!`](@ref) gave `sharing`; 0 where that is -1.
"""
shared_slot(sharing, slot) = sharing < 0 ? 0 : sharing + slot

"""
    sailed_edge!(workspace, slot, aloft, table, prices, edge)

[`SailedEdge`](@ref) for a kite aloft before it if `aloft` of `edge`, which names the
arguments of [`sail_edge!`](@ref) other than the points, `table` and `aloft`. A state down
fills place `slot` of `workspace.shared` where it is not 0 with the edge for the state
aloft, which reads it there where it was sailed.
"""
function sailed_edge!(workspace::RouteWorkspace, slot, aloft, table::RouteTable, prices,
        edge)
    known = aloft && slot != 0 ? workspace.shared[slot] : UNSAILED
    isnan(known.hours) || return known
    (; points) = workspace
    shares = !aloft && slot != 0
    hours, through = sailed_hours!(points, table, edge, aloft || shares)
    shares || return SailedEdge(table, points, hours, aloft, prices, through)
    workspace.shared[slot] = SailedEdge(table, points, hours, true, prices, through)
    hours, through = sailed_down!(points, table, edge, hours, through)
    return SailedEdge(table, points, hours, false, prices, through)
end

"""
    sailed_hours!(points, table, edge, aloft)

[`sail_edge!`](@ref) into `points` the edge `edge` names, as in [`sailed_edge!`](@ref),
begun with a kite `aloft` or down: its hours and its [`same_through`](@ref), 0 where it
is blocked.
"""
function sailed_hours!(points, table::RouteTable, edge, aloft)
    (; start, weather, corridor, stage, lateral, step, time, speed_index) = edge
    (; sample_hours) = edge
    hours = sail_edge!(points, start, table, weather, corridor, stage, lateral, step, time,
        speed_index, aloft, sample_hours)
    isfinite(hours) || return hours, 0
    return hours, same_through(table, points, speed_index,
        corridor.edge_length[stage, lateral, step], sample_hours)
end

"""
    sailed_down!(points, table, edge, hours, through)

[`sailed_hours!`](@ref) of `edge` begun with the kite down, given the `hours` and
`through` of the `points` it was sailed into with a kite aloft: those, unless that was
blocked or a point held its speed only with a kite flying, when it is sailed again.
"""
function sailed_down!(points, table::RouteTable, edge, hours, through)
    isfinite(hours) && all(point -> isfinite(point.stowed), points) &&
        return hours, through
    return sailed_hours!(points, table, edge, false)
end

"""
    time_bin(elapsed, departure, time_step)

Time bin of `time_step` [h] that holds the time `elapsed` [h] after `departure` [h], the
bins being aligned to the clock and the departure lying in bin 1.
"""
time_bin(elapsed, departure, time_step) =
    floor(Int, (mod(departure, time_step) + elapsed) / time_step) + 1

"Number of [`time_bin`](@ref)s of `time_step` [h] that hold every arrival within
`MAX_LEG_HOURS`, whatever the hour of departure."
bin_count(time_step) = ceil(Int, MAX_LEG_HOURS / time_step) + 1

"""
    relax_sailed!(workspace, state, next, sailed, edge, (; time_step, departure), prices,
                  kite)

[`relax!`](@ref) the states of node `next` of the next stage, kite down and aloft, from
`state` by the [`SailedEdge`](@ref) `sailed`, where it arrives within the
[`time_bin`](@ref)s of `time_step` [h] of a passage left at `departure` [h]; `edge` holds
the objective `here` [USD] of `state` and the commanded `speed_index`. With a
[`KiteRule`](@ref) `kite`, the node and bin keep the one arrival it values least.
"""
function relax_sailed!(workspace::RouteWorkspace, state, next, sailed::SailedEdge, edge,
        (; time_step, departure), prices, kite)
    isfinite(sailed.hours) || return
    arrival = workspace.elapsed[state...] + sailed.hours
    next_bin = time_bin(arrival, departure, time_step)
    next_bin <= size(workspace.cost, 2) || return
    edge = (; edge..., sailed.hours)
    if isnothing(kite)
        relax!(workspace, state, (next, next_bin, 1), sailed.down, edge, prices)
        relax!(workspace, state, (next, next_bin, 2), sailed.up, edge, prices)
    else
        relax_chosen!(workspace, state, (next, next_bin), sailed, edge, prices, kite)
    end
end

"""
    relax_chosen!(workspace, origin, (next, bin), sailed, edge, prices, kite)

Arrive at node `next` of the next stage in time bin `bin` from the state `origin` by the
[`SailedEdge`](@ref) `sailed` with the kite down or aloft, whichever the [`KiteRule`](@ref)
`kite` values less, if that is less than the arrival kept there so far, which it replaces.
"""
function relax_chosen!(workspace, origin, (next, bin), sailed::SailedEdge, edge, prices,
        kite::KiteRule)
    cost = workspace.cost
    stage = origin[4] + 1
    best, aloft, total = Inf, 1, Inf
    for (tally, state) in ((sailed.down, 1), (sailed.up, 2))
        isfinite(tally.cost) || continue
        objective = edge.here + edge_objective(tally.cost, edge.hours, prices)
        value = objective + arrival_value(kite, state, stage)
        value < best && ((best, aloft, total) = (value, state, objective))
    end
    isfinite(best) || return
    for kept in 1:2
        best < cost[next, bin, kept, stage] + arrival_value(kite, kept, stage) || return
    end
    cost[next, bin, 3 - aloft, stage] = Inf
    arrive!(workspace, origin, (next, bin, aloft), aloft == 1 ? sailed.down : sailed.up,
        edge, total)
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
    edge_objective(cost, hours, prices)

Objective [USD] of an edge of `hours` [h] with `cost` [USD] of fuel, rig wear and
launches, at the time `prices`.
"""
edge_objective(cost, hours, prices) = cost + prices.time * hours

"""
    relax!(workspace, origin, arrival, tally, edge, prices)

Arrive at state `arrival` (lateral, bin, aloft) of the next stage from the state
`origin` by an `edge` of `hours` [h] passed as the [`EdgeTally`](@ref) `tally`, if that
is cheaper than the best arrival there so far.
"""
function relax!(workspace, origin, arrival, tally::EdgeTally, edge, prices)
    isfinite(tally.cost) || return
    total = edge.here + edge_objective(tally.cost, edge.hours, prices)
    total < workspace.cost[arrival..., origin[4] + 1] || return
    arrive!(workspace, origin, arrival, tally, edge, total)
end

"""
    arrive!(workspace, origin, arrival, tally, edge, total)

Make state `arrival` (lateral, bin, aloft) of the next stage the arrival from the state
`origin` by an `edge` of `hours` [h] passed as the [`EdgeTally`](@ref) `tally`, at the
objective `total` [USD].
"""
function arrive!(workspace, origin, arrival, tally::EdgeTally, edge, total)
    (; cost, elapsed, energy, flight_hours, launches, forced_landings, parent, speed_index,
        mode) = workspace
    (; hours) = edge
    lateral, bin, origin_aloft, stage = origin
    arrival = (arrival..., stage + 1)
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
    traced_leg(workspace, corridor, table, final, first_stage, objective)

[`Leg`](@ref) of `objective` [USD] ending in state `final` (lateral, bin, aloft, stage) of
`workspace`, its path traced back to `first_stage`.
"""
function traced_leg(workspace::RouteWorkspace, corridor, table, final, first_stage,
        objective)
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
    return Leg(energy, workspace.flight_hours[final...], workspace.launches[final...],
        workspace.forced_landings[final...], elapsed[final...], objective, path, aloft_path)
end

"""
    plan_values(plan, corridor, table, weather, departure, first_stage, prices)

Least fuel and rig cost [USD] from each node of `plan`, which leaves stage `first_stage`
of `corridor` at `departure` [h], to its end with the kite stowed (column 1) or aloft
(column 2) at that node, sailing the plan's course, times and speeds in `weather` and
landing the kite by the end, with the hours an edge takes beyond the plan's added at
`prices.time`; `Inf` where that is not possible.
"""
function plan_values(plan::Leg, corridor, table::RouteTable, weather, departure,
        first_stage, prices)
    nodes = length(plan.path)
    values = fill(Inf, nodes, 2)
    values[nodes, 1] = 0.0
    points = SailedPoint[]
    for i in (nodes - 1):-1:1
        ahead = (values[i + 1, 1], values[i + 1, 2])
        for aloft in (false, true)
            values[i, aloft + 1] = plan_edge_value(points, plan, corridor, table, weather,
                departure, first_stage, i, aloft, ahead, prices)
        end
    end
    return values
end

"Cost [USD] of edge `i` of `plan` left `aloft` or stowed, and of the `ahead` it ends on."
function plan_edge_value(points, plan::Leg, corridor, table::RouteTable, weather, departure,
        first_stage, i, aloft, ahead, prices)
    stage, lateral, step, time = plan_edge(plan, corridor, departure, first_stage, i)
    planned = plan.path[i + 1][4]
    slowest = searchsortedfirst(table.speeds, planned)
    hours, tally, ends_aloft = sail_planned_edge!(points, table, weather, corridor, stage,
        lateral, step, time, planned, aloft, ahead, prices; slowest)
    isfinite(hours) || return Inf
    lost_hours = max(hours - (plan.path[i + 1][3] - plan.path[i][3]), 0.0)
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
    sail_planned_edge!(points, table, weather, corridor, stage, lateral, step, time, speed,
                       aloft, ahead, prices; slowest=1)

Sail edge `step` of node (`stage`, `lateral`) of `corridor`, left at `time` [h] with the
kite `aloft` or stowed, in the real `weather` at the planned `speed` [m/s], or at the
highest lower speed of the [`RouteTable`](@ref) `table`, down to index `slowest`, the ship
can hold with its kite as it is. The kite ends the edge in the state whose cost on the edge
plus `ahead`, the cost [USD] from the next node with the kite stowed and aloft, is least.
Returns the hours, the [`EdgeTally`](@ref), whether the kite ends aloft and the speed
sailed; `Inf` hours where no speed passes.
"""
function sail_planned_edge!(points, table::RouteTable, weather, corridor, stage, lateral,
        step, time, speed, aloft, ahead, prices; slowest=1)
    stowed_ahead, aloft_ahead = any(isfinite, ahead) ? ahead : (0.0, 0.0)
    start = EdgeSample(table.table, weather, corridor, stage, lateral, step, 0.0, time)
    for speed_index in searchsortedfirst(table.speeds, speed):-1:slowest
        hours = sail_edge!(points, start, table, weather, corridor, stage, lateral, step,
            time, speed_index, aloft)
        isfinite(hours) || continue
        down, up = kite_passage(table, points, aloft, prices)
        ends_aloft = up.cost + aloft_ahead < down.cost + stowed_ahead
        tally = ends_aloft ? up : down
        isfinite(tally.cost) && return hours, tally, ends_aloft, table.speeds[speed_index]
    end
    return Inf, NO_TALLY, false, speed
end

"""
    with_changed(item; changes...)

An immutable `item` with its fields `changes` replaced.
"""
with_changed(item; changes...) =
    typeof(item).name.wrapper((get(changes, name, getfield(item, name))
                               for name in fieldnames(typeof(item)))...)

known_weather(::Nothing, weather, time) = weather

"""
    ReplannedForecast(forecast; interval=24.0, live=false)

The forecast source `forecast` of a ship that re-plans at the first node `interval` [h]
or more after its last plan and, where `live`, sails the plan's course choosing speed and
kite every few hours on the weather it meets by [`sail_live_edge!`](@ref).
"""
struct ReplannedForecast{F}
    forecast::F
    interval::Float64
    live::Bool
end

ReplannedForecast(forecast; interval=24.0, live=false) =
    ReplannedForecast(forecast, interval, live)

"""
    far_row_stride(settings, ahead)

Every how many rows of its corridor a plan keeps at distance `ahead` [nmi] beyond its near
part, by the [`RouterSettings`](@ref) `settings`.
"""
function far_row_stride(settings::RouterSettings, ahead)
    (; near_distance, row_doubling_ratio) = settings
    doublings = floor(Int, log(ahead / near_distance) / log(row_doubling_ratio))
    return settings.far_row_stride * 2^max(0, doublings)
end

"""
    planning_stages(corridor, stage, settings)

Numbers of the stages of `corridor` a ship at `stage` plans on by the
[`RouterSettings`](@ref) `settings`, how many of them lie in its near part, and every how
many rows each keeps: every stage and row within `near_distance` ahead, then rows by
[`far_row_stride`](@ref), on the nearest stages far enough apart for an edge to shift by
that many rows, keeping every stage of the corridor's fixed coastal track and the stage
that joins it.
"""
function planning_stages(corridor::Corridor, stage, settings::RouterSettings)
    along = corridor.along_centre
    stage_count = length(along)
    fixed = [count(view(corridor.water, i, :)) == 1 for i in 1:stage_count]
    near_end = along[stage] + settings.near_distance * NAUTICAL_MILE
    last_near = clamp(searchsortedlast(along, near_end), min(stage + 1, stage_count),
        stage_count)
    stages = collect(stage:last_near)
    ahead(i) = (along[i] - along[stage]) / NAUTICAL_MILE
    while last(stages) < stage_count
        previous = last(stages)
        spacing = far_row_stride(settings, ahead(previous)) * corridor.lateral_spacing /
                  MAX_HEADING_TANGENT
        next = max(searchsortedfirst(along, along[previous] + spacing), previous + 1)
        along[stage_count] - along[min(next, stage_count)] < spacing / 2 &&
            (next = stage_count)
        coast = findnext(fixed, previous + 1)
        isnothing(coast) || (next = min(next, max(coast - 1, previous + 1)))
        push!(stages, min(next, stage_count))
    end
    near = last_near - stage + 1
    strides = [k <= near ? 1 : far_row_stride(settings, ahead(stages[k]))
               for k in eachindex(stages)]
    return stages, near, strides
end

"""
    planning_corridor(corridor, stage, lateral)

The [`Corridor`](@ref) a ship at `stage` and `lateral` of `corridor` plans on, the stage it
starts from there, and how many of its nodes along a plan the ship may sail before planning
again. It keeps the [`planning_stages`](@ref), beyond the near part only their rows, with
edges that may shift as many rows as their length allows and
weather samples at most `far_sample_hours` apart, by the `ROUTER_SETTINGS` in force. Where
that leads nowhere from the ship, or `corridor` has no land mask to keep new edges clear by,
it is `corridor` itself.
"""
function planning_corridor(corridor::Corridor, stage, lateral)
    whole = (corridor, stage, typemax(Int))
    isnothing(corridor.mask) && return whole
    settings = ROUTER_SETTINGS[]
    stages, near, strides = planning_stages(corridor, stage, settings)
    lat, lon = corridor.lat[stages, :], corridor.lon[stages, :]
    water = corridor.water[stages, :]
    centre = centre_index(corridor)
    for k in (near + 1):length(stages), row in axes(water, 2)
        mod(row - centre, strides[k]) == 0 || (water[k, row] = false)
    end
    lengths = diff(corridor.along_centre[stages])
    spacing = corridor.lateral_spacing
    stage_reach(i) = i < near ? min(corridor.reach, lateral_reach(lengths[i], spacing)) :
                     lateral_reach(lengths[i], spacing)
    reach = maximum(stage_reach, eachindex(lengths))
    open, edge_length, edge_course = on_passage(lat, lon, water, corridor.mask, reach,
        lateral, stage_reach)
    open[1, lateral] || return whole
    planning = Corridor(lat, lon, open, edge_length, edge_course, corridor.track_length,
        along_centre_line(lat, lon), reach, spacing,
        [i < near ? 0.0 : settings.far_sample_hours for i in eachindex(stages)],
        corridor.mask)
    return planning, 1, near
end

"""
    rest_of_plan(plan, i)

The path, kite states and duration of the [`Leg`](@ref) `plan` from its node `i` on, its
times counted from there and its first node carrying no speed or mode, as a routed plan's
does; its totals of fuel, flight and objective are `NaN`.
"""
function rest_of_plan(plan::Leg, i)
    first_lat, first_lon, start = plan.path[i]
    path = [(first_lat, first_lon, 0.0, 0.0, 0.0);
            [(lat, lon, time - start, speed, mode)
             for (lat, lon, time, speed, mode) in plan.path[(i + 1):end]]]
    return Leg(NaN, NaN, 0, 0, plan.duration - start, NaN, path, plan.aloft[i:end])
end

"""
    lies_on(plan, corridor, first_stage, first_lateral)

Whether the path of `plan` leaves node (`first_stage`, `first_lateral`) of `corridor` and
runs along its nodes and edges to its last stage.
"""
function lies_on(plan::Leg, corridor::Corridor, first_stage, first_lateral)
    length(plan.path) == size(corridor.lat, 1) - first_stage + 1 || return false
    lateral = first_lateral
    for (k, (lat, lon)) in enumerate(plan.path)
        stage = first_stage + k - 1
        corridor.water[stage, lateral] && corridor.lat[stage, lateral] == lat &&
            corridor.lon[stage, lateral] == lon || return false
        k == length(plan.path) && break
        next_lat, next_lon = plan.path[k + 1]
        next = nearest_lateral(corridor, stage + 1, next_lat, next_lon)
        step = lateral_step(corridor, lateral, next)
        1 <= step <= step_count(corridor) &&
            !isnan(corridor.edge_course[stage, lateral, step]) || return false
        lateral = next
    end
    return true
end

"""
    forecast_plan(known, corridor, table, time, prices; arrival_by=Inf, first_stage,
                  first_lateral, first_aloft, held=nothing)

The plan a ship adopts at `time` [h] on `known` to arrive by `arrival_by` [h], and the
[`plan_values`](@ref) of its nodes on it, or `(nothing, nothing)` where no plan leaves the
node: of the plan [`route`](@ref) finds on `known` and the rest of the plan `held` where
that [`lies_on`](@ref) `corridor` and arrives by `arrival_by`, the one with the least
fuel, rig and time cost on `known`.
"""
function forecast_plan(known, corridor, table::RouteTable, time, prices; arrival_by=Inf,
        first_stage, first_lateral, first_aloft, held=nothing)
    routed = route(corridor, table, known, time; time_cost=prices.time, arrival_by,
        first_stage, first_lateral, first_aloft)
    plans = candidate_plans(routed, held, corridor, first_stage, first_lateral, arrival_by)
    isempty(plans) && return nothing, nothing
    values = [plan_values(plan, corridor, table, known, time, first_stage, prices)
              for plan in plans]
    return cheapest_plan(plans, values, prices, first_aloft)
end

"""
    candidate_plans(routed, held, corridor, first_stage, first_lateral, arrival_by)

The distinct paths among the plan `held`, where it [`lies_on`](@ref) `corridor` and
arrives by `arrival_by` [h], and the plan `routed`, `nothing` where none was found.
"""
function candidate_plans(routed, held, corridor, first_stage, first_lateral, arrival_by)
    kept = !isnothing(held) && held.duration <= arrival_by &&
           lies_on(held, corridor, first_stage, first_lateral)
    return unique(plan -> plan.path, filter(!isnothing, kept ? [held, routed] : [routed]))
end

"""
    cheapest_plan(plans, values, prices, aloft)

Of `plans`, the one, with its [`plan_values`](@ref) in `values`, whose cost from its first
node with the kite `aloft` plus its hours at `prices.time` is least; the first of equals.
"""
function cheapest_plan(plans, values, prices, aloft)
    best = argmin([value[1, aloft + 1] + prices.time * plan.duration
                   for (plan, value) in zip(plans, values)])
    return plans[best], values[best]
end

"""
    remaining_cost(corridor, table, known, departure, prices; first_stage, previous=nothing,
                   near_hours=Inf)

[`CostToGo`](@ref) of a ship at `first_stage` of `corridor` planning on `known` at
`departure` [h], beyond `near_hours` [h] read from the one of its last plan, `previous`,
where there is one.
"""
function remaining_cost(corridor::Corridor, table::RouteTable, known, departure, prices;
        first_stage, previous=nothing, near_hours=Inf)
    values = Ref(Array{Float64}(undef, size(corridor.lat, 2), 0, 2, size(corridor.lat, 1)))
    return CostToGo(values, corridor, table, known, departure; time_cost=prices.time,
        first_stage, previous, near_hours)
end

"""
    LiveStep

One step of an edge sailed live by [`sail_live_edge!`](@ref): the [`SailedPoint`](@ref) of
the weather met at its start, whether the kite is up at its end, and the share (0 to 1) of
the edge at its start.
"""
const LiveStep = @NamedTuple{point::SailedPoint, aloft::Bool, share::Float64}

"""
    sail_live_edge!(steps, points, table, weather, known, beyond, corridor, edge, prices)

Sail `edge` (`stage`, `lateral`, `step` to node `next` of `corridor`, left with the kite
`aloft` at `time` [h], with the plan's `speed` [m/s]) in the real `weather` as a ship
deciding every `live_step_hours` on the weather it meets: at each step's start it holds the
speed and kite state, over every `live_speed_stride`-th speed and the plan's, whose
objective over the step in the weather met, plus the rest of the edge at that speed in the
[`MetWeather`](@ref) of `known` and the cost beyond `next` by the [`NodeToGo`](@ref)
`beyond` is least ([`rest_of_edge`](@ref)). Where no speed holds over the step and the
rest of the edge as it knows them, past the edge's start, it holds there for the step with
the kite down, at the fuel of zero speed. Fills
`steps` with its [`LiveStep`](@ref)s, using `points` for the rest of the edge. Returns the
hours, the [`EdgeTally`](@ref) and whether the kite ends aloft; `Inf` hours where no speed
can be held at the edge's start, and `nothing` after holding `LONGEST_HOLD` on the edge.
"""
function sail_live_edge!(steps, points, table::RouteTable, weather, known, beyond,
        corridor, edge, prices)
    (; stage, lateral, step, next, time) = edge
    (; live_step_hours, live_speed_stride) = ROUTER_SETTINGS[]
    speeds = sort(unique([searchsortedfirst(table.speeds, edge.speed);
        commanded_speeds(length(table.speeds), live_speed_stride)]))
    edge_length = corridor.edge_length[stage, lateral, step]
    idle = fuel_power(table.table.ship.powertrain, 0.0)
    share, hours, held, aloft = 0.0, 0.0, 0.0, edge.aloft
    tally = EdgeTally(0.0, 0.0, 0.0, 0, 0)
    empty!(steps)
    while share < 1
        now = time + hours
        sample = EdgeSample(table.table, weather, corridor, stage, lateral, step, share,
            now)
        met = MetWeather(known, weather, edge_point(corridor, stage, lateral, next,
                share)..., now)
        before = aloft ? (NO_TALLY, tally) : (tally, NO_TALLY)
        hold = SailedPoint(sample, 0, Inf, idle, live_step_hours, now, 0.0)
        best = (; value=Inf, tally=first(kite_step(table, hold, before..., prices)),
            point=hold, aloft=false, after=share)
        for speed_index in speeds
            point, after = live_point(table, sample, speed_index, aloft, share, edge_length,
                live_step_hours, now)
            point.speed_index == 0 && continue
            down, up = kite_step(table, point, before..., prices)
            for (way, ends_aloft) in ((down, false), (up, true))
                isfinite(way.cost) || continue
                value = edge_objective(way.cost, hours + point.hours, prices) +
                        rest_of_edge(points, table, met, beyond, corridor, edge,
                    speed_index, ends_aloft, after, now + point.hours, prices)
                value < best.value || continue
                best = (; value, tally=way, point, aloft=ends_aloft, after)
            end
        end
        if !isfinite(best.value)
            share == 0 && return Inf, NO_TALLY, aloft
            held >= LONGEST_HOLD && return nothing
            held += live_step_hours
        end
        push!(steps, (; point=best.point, aloft=best.aloft, share))
        tally, aloft, share = best.tally, best.aloft, best.after
        hours += best.point.hours
    end
    return hours, tally, aloft
end

"""
    live_point(table, sample, speed_index, aloft, share, edge_length, step_hours, time)

The [`SailedPoint`](@ref) of a step of at most `step_hours` [h] from `share` of an edge of
`edge_length` [m] at the [`held_speed`](@ref) of commanded speed number `speed_index` with
the kite `aloft` in the weather met `sample` at `time` [h], and the share the step ends at.
"""
function live_point(table::RouteTable, sample, speed_index, aloft, share, edge_length,
        step_hours, time)
    held, flown, stowed, chance = held_speed(table, speed_index, sample, aloft)
    held == 0 && return SailedPoint(sample, 0, flown, stowed, Inf, time, chance), share
    left = (1 - share) * edge_length
    distance = min(table.speeds[held] * 3600 * step_hours, left)
    after = distance < left ? share + distance / edge_length : 1.0
    point = SailedPoint(sample, held, flown, stowed, distance / table.speeds[held] / 3600,
        time, chance)
    return point, after
end

"""
    rest_of_edge(points, table, met, beyond, corridor, edge, speed_index, aloft, from,
                 time, prices)

Least objective [USD] from share `from` of `edge`, reached at `time` [h] with the kite
`aloft`, sailed at commanded speed number `speed_index` in `met`, plus the cost from its
end by the [`NodeToGo`](@ref) `beyond`; `Inf` where blocked.
"""
function rest_of_edge(points, table::RouteTable, met, beyond, corridor, edge, speed_index,
        aloft, from, time, prices)
    from >= 1 && return ahead_value(beyond, aloft, time)
    (; stage, lateral, step) = edge
    start = EdgeSample(table.table, met, corridor, stage, lateral, step, from, time)
    hours = sail_edge!(points, start, table, met, corridor, stage, lateral, step, time,
        speed_index, aloft; from)
    isfinite(hours) || return Inf
    down, up = kite_passage(table, points, aloft, prices)
    return min(edge_objective(down.cost, hours, prices) +
               ahead_value(beyond, false, time + hours),
        edge_objective(up.cost, hours, prices) +
        ahead_value(beyond, true, time + hours))
end

"""
    NodeToGo(to_go, next, stage, start)

The [`CostToGo`](@ref) `to_go` of a plan made at `start` [h], from node `next` of `stage`.
"""
struct NodeToGo{C <: CostToGo}
    to_go::C
    next::Int
    stage::Int
    start::Float64
end

"""
    ahead_value(beyond, aloft, time)

Cost [USD] by the [`NodeToGo`](@ref) `beyond` from the end of an edge reached at `time` [h]
with the kite `aloft`, `Inf` where it found no path.
"""
function ahead_value(beyond::NodeToGo, aloft, time)
    value = beyond.to_go(beyond.next, aloft + 1, beyond.stage, time - beyond.start)
    return isnan(value) ? Inf : value
end

"""
    forecast_route(corridor, table, weather, departure; time_cost, arrival_by=Inf,
                   forecast=nothing, live_steps=nothing)

Passage of a ship that plans by [`forecast_plan`](@ref), weighing the rest of the plan it
holds, on the [`RouteTable`](@ref) `table` on its [`planning_corridor`](@ref) and re-plans
at the first node 24 hours or more after the last plan or past the plan's near part, on
`forecast`: a [`ForecastArchive`](@ref), an [`ExpectedForecast`](@ref), the real weather
where `nothing`, or a [`ReplannedForecast`](@ref) with its own interval that may sail
live. It sails each plan in the real `weather` until the next re-plan by
[`sail_planned_edge!`](@ref), launching and landing the kite where the real weather of an
edge and the [`plan_values`](@ref) ahead make that cheapest, or live by
[`sail_live_edge!`](@ref). Fuel, flight hours and objective are those of the real weather.
Where no plan leaves its node or the real weather stops the next edge, the ship holds there
with the kite stowed on its hotel load until the next forecast, 6 h later, and plans again;
sailed live, it holds where it is on an edge it has left. Each plan arrives `arrival_by`
[h] after `departure` as [`route`](@ref) does. A vector `live_steps` receives each
[`LiveStep`](@ref) sailed live with its edge's `planned_speed`. Returns `nothing` after
holding 72 h at one node or on one edge.
"""
function forecast_route(corridor::Corridor, table::RouteTable, weather, departure;
        time_cost, arrival_by=Inf, forecast=nothing, live_steps=nothing)
    ship_table = table.table
    prices = (; fuel=ship_table.ship.fuel.price, time=time_cost)
    stage_count = size(corridor.lat, 1)
    stage, lateral, aloft = 1, centre_index(corridor), false
    time, fuel_energy, flight_hours = 0.0, 0.0, 0.0
    launches, forced_landings = 0, 0
    objective = 0.0
    path = [(corridor.lat[1, lateral], corridor.lon[1, lateral], 0.0, 0.0, 0.0)]
    aloft_path = [false]
    points, steps = SailedPoint[], LiveStep[]
    held = 0.0
    replanned = forecast isa ReplannedForecast ? forecast : ReplannedForecast(forecast)
    live = replanned.live
    rest, to_go = nothing, nothing
    while stage < stage_count
        known = known_weather(replanned.forecast, weather, departure + time)
        planning, plan_stage, sailable = planning_corridor(corridor, stage, lateral)
        plan, values = forecast_plan(known, planning, table, departure + time, prices;
            arrival_by=arrival_by - time, first_stage=plan_stage, first_lateral=lateral,
            first_aloft=aloft, held=rest)
        blocked = isnothing(plan)
        plan_start, plan_end = time, blocked ? 1 : min(length(plan.path), sailable)
        to_go = blocked || !live ? nothing :
                remaining_cost(corridor, table, known, departure + time, prices;
            first_stage=stage, previous=to_go,
            near_hours=replanned.interval + ROUTER_SETTINGS[].to_go_near_hours)
        reached = 1
        for i in 2:plan_end
            next_lat, next_lon, _, planned_speed, _ = plan.path[i]
            next = nearest_lateral(corridor, stage + 1, next_lat, next_lon)
            step = lateral_step(corridor, lateral, next)
            if live
                edge = (; stage, lateral, step, next, time=departure + time,
                    speed=planned_speed, aloft)
                beyond = NodeToGo(to_go, next, stage + 1, departure + plan_start)
                sailed = sail_live_edge!(steps, points, table, weather, known, beyond,
                    corridor, edge, prices)
                isnothing(live_steps) || append!(live_steps,
                    ((; live_step..., planned_speed) for live_step in steps))
                isnothing(sailed) && return nothing
                hours, tally, aloft = sailed
                speed = corridor.edge_length[stage, lateral, step] / 3600hours
            else
                hours, tally, aloft, speed = sail_planned_edge!(points, table, weather,
                    corridor, stage, lateral, step, departure + time, planned_speed, aloft,
                    (values[i, 1], values[i, 2]), prices)
            end
            blocked = !isfinite(hours)
            blocked && break
            objective += edge_objective(tally.cost, hours, prices)
            fuel_energy += tally.energy
            flight_hours += tally.flight_hours
            launches += tally.launches
            forced_landings += tally.forced_landings
            time += hours
            held = 0.0
            stage, lateral = stage + 1, next
            push!(path, (next_lat, next_lon, time, speed, summary_mode(tally, hours)))
            push!(aloft_path, aloft)
            reached = i
            time - plan_start >= replanned.interval && break
        end
        isnothing(plan) || (rest = rest_of_plan(plan, reached))
        blocked || continue
        held >= LONGEST_HOLD && return nothing
        energy = 3600FORECAST_INTERVAL * fuel_power(ship_table.ship.powertrain, 0.0)
        objective += edge_objective(energy * prices.fuel, FORECAST_INTERVAL, prices)
        fuel_energy += energy
        time += FORECAST_INTERVAL
        held += FORECAST_INTERVAL
        aloft = false
    end
    return Leg(fuel_energy, flight_hours, launches, forced_landings, time, objective, path,
        aloft_path)
end

"""
    true_wind_angle(east, north, wind_speed, course)

Angle [rad, 0..π] between the ship's course and the direction the wind comes from.
"""
true_wind_angle(east, north, wind_speed, course) =
    acos(true_wind_cosine(east, north, wind_speed, course))

"cosine of the [`true_wind_angle`](@ref); 1 in a calm"
function true_wind_cosine(east, north, wind_speed, course)
    wind_speed > 0 || return 1.0
    sine, cosine = sincos(course)
    return clamp(-(east * sine + north * cosine) / wind_speed, -1.0, 1.0)
end

"distance the route may stray to either side of its reference track [nmi]"
const CORRIDOR_HALF_WIDTH = 2400.0

"waypoints from Rotterdam through the Channel to Ushant (latitude, longitude) [deg]"
const CHANNEL = [(51.98, 4.05), (51.05, 1.60), (50.05, -1.50), (48.80, -6.00)]

"stage spacing of a corridor at scale 1 [nmi]"
const OCEAN_SPACING = 45.0
"row spacing of a corridor at scale 1 [nmi]"
const LATERAL_SPACING = 11.25

"fewest open-ocean stages of a corridor whose stages are `OCEAN_SPACING` apart"
const MIN_OCEAN_STAGES = 10

"fixed path from north of the Bahamas through the Florida Strait into the Gulf of Mexico"
const FLORIDA_STRAIT = [(28.0, -79.5), (26.5, -79.5), (25.5, -79.8), (24.6, -80.3),
    (24.2, -81.5), (24.4, -83.3)]

"""
Fixed coastal paths each route follows after the Channel (latitude, longitude) [deg], the
port last; the route crosses the open sea between one path and the next.
"""
const COASTAL_PATHS = Dict(:caribbean => [[(16.15, -61.20)]],
    :new_york => [[(40.3, -72.5)]], :bilbao => [[(43.6, -3.0)]],
    :dakar => [[(14.6, -17.6)]], :houston => [FLORIDA_STRAIT, [(28.8, -94.5)]],
    :tubarao => [[(-20.4, -39.8)]])

"""
Share of the emissions of a voyage between Rotterdam and the port of each route that the
EU ETS counts: all between ports of Member States, Guadeloupe among them, half to or from a
port outside the Union.
"""
const EU_ETS_SHARES = Dict(:caribbean => 1.0, :bilbao => 1.0, :new_york => 0.5,
    :dakar => 0.5, :houston => 0.5, :tubarao => 0.5)

"""
    route_paths(route)

The fixed coastal paths (lat, lon) [deg] of `route`, the Channel first; see
[`route_corridors`](@ref).
"""
route_paths(route) = [[CHANNEL]; COASTAL_PATHS[route]]

"length [m] of the fixed coastal paths of `route` and the great circles between them"
function route_length(route)
    points = reduce(vcat, route_paths(route))
    return sum(distance(from..., to...)
               for (from, to) in zip(points[1:(end - 1)], points[2:end]))
end

"""
    route_corridors(route, mask; scale=1, ocean_spacing=OCEAN_SPACING * scale,
                    lateral_spacing=LATERAL_SPACING * scale)

Outbound and return corridors between Rotterdam and the port of `route`: `:caribbean`
(Guadeloupe), `:new_york`, `:bilbao`, `:dakar`, `:houston` or `:tubarao` (Brazil), the same
band both ways. Each runs through the Channel to Ushant and on through the route's
`COASTAL_PATHS`, crossing the open sea between them on great circles.
`ocean_spacing` and `lateral_spacing` are the stage and row spacing [nmi], both shrunk
alike where the crossings are shorter than `MIN_OCEAN_STAGES` stages at `OCEAN_SPACING`;
the band reaches `CORRIDOR_HALF_WIDTH` to either side.
"""
function route_corridors(route::Symbol, mask; scale=1, ocean_spacing=OCEAN_SPACING * scale,
        lateral_spacing=LATERAL_SPACING * scale)
    paths = route_paths(route)
    crossings = sum(distance(last(from)..., first(to)...)
                    for (from, to) in zip(paths[1:(end - 1)], paths[2:end])) / NAUTICAL_MILE
    shrink = min(1.0, crossings / (MIN_OCEAN_STAGES * OCEAN_SPACING))
    lateral_spacing *= shrink
    outbound = Corridor(paths, mask; ocean_spacing=ocean_spacing * shrink,
        lateral_spacing,
        lateral_count=2 * ceil(Int, CORRIDOR_HALF_WIDTH / lateral_spacing) + 1)
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
