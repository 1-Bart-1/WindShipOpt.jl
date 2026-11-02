"lateral neighbours an edge may shift by, on each side"
const MAX_LATERAL_STEP = 3

"lateral node that edge `step` of node `lateral` leads to"
next_lateral(lateral, step) = lateral + step - MAX_LATERAL_STEP - 1

"stages on each side over which the lateral direction is averaged"
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
    "node within the coastal clearance of land, where the router pays a penalty"
    near_coast::BitMatrix
end

centre_index(corridor::Corridor) = (size(corridor.lat, 2) + 1) ÷ 2

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
    return Corridor(lat, lon, water, edges(lat, lon, water, mask)..., track_end,
        reshape(BitVector(near_coast), size(lat)))
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

function edges(lat, lon, water, mask)
    stage_count, lateral_count = size(lat)
    steps = 2MAX_LATERAL_STEP + 1
    edge_length = zeros(stage_count - 1, lateral_count, steps)
    edge_course = fill(NaN, stage_count - 1, lateral_count, steps)
    for stage in 1:(stage_count - 1), lateral in 1:lateral_count, step in 1:steps
        next = next_lateral(lateral, step)
        1 <= next <= lateral_count || continue
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
    return_corridor(corridor, mask)

The same corridor sailed from its last stage to its first.
"""
function return_corridor(corridor::Corridor, mask)
    lat = reverse(corridor.lat; dims=1)
    lon = reverse(corridor.lon; dims=1)
    water = reverse(corridor.water; dims=1)
    return Corridor(lat, lon, water, edges(lat, lon, water, mask)...,
        corridor.track_length, reverse(corridor.near_coast; dims=1))
end

"""
    Leg

Optimal passage along a corridor: fuel energy [J], fuel cost [USD], hours a kite flew
patterns and hours it was parked aloft, its launches, duration [h], the objective the
router minimises [USD] and the path as (latitude, longitude, time [h], commanded speed
[m/s], mode) per stage, the mode of the edge into the stage being the one the kite spent
most of the edge in: 0 down, 1 parked and 2 flying.
"""
struct Leg
    fuel_energy::Float64
    fuel_cost::Float64
    flight_hours::Float64
    parked_hours::Float64
    launches::Int
    duration::Float64
    objective::Float64
    path::Vector{NTuple{5, Float64}}
end

"kite down, parked aloft or flying patterns, as the mode of an edge"
const STOWED, PARKED, FLYING = 0, 1, 2

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
    "hours of kite parked aloft up to the arrival [h]"
    parked_hours::Array{Float64, 4}
    "kite launches up to the arrival"
    launches::Array{Int32, 4}
    "state of the previous stage, as the linear index of (bin, lateral, aloft)"
    parent::Array{Int32, 4}
    "routing speed number of the edge into the state"
    speed_index::Array{Int8, 4}
    "mode of the edge into the state"
    mode::Array{Int8, 4}
end

"""
    RouteWorkspace(lateral_count, bins, stage_count)

Workspace for corridors of `lateral_count` nodes per stage, `bins` time bins and up to
`stage_count` stages.
"""
function RouteWorkspace(lateral_count, bins, stage_count)
    shape = (lateral_count, bins, 2, stage_count)
    return RouteWorkspace(fill(Inf, shape), zeros(shape), zeros(shape), zeros(shape),
        zeros(shape), zeros(Int32, shape), zeros(Int32, shape), zeros(Int8, shape),
        zeros(Int8, shape))
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

"hours in the year by which a forecast beyond its horizon shifts the time [h]"
const FORECAST_SHIFT = 8760.0

function forecast_time(forecast::ForecastWeather, time)
    time - forecast.issue_time <= forecast.horizon && return time
    shifted = time + FORECAST_SHIFT
    return shifted <= duration(forecast.weather) ? shifted : time - FORECAST_SHIFT
end

"""
    NodeSeries

Fields at the nodes of a corridor at the stored times of a weather grid, (time, lateral,
stage), with the hours [h] of the first stored time and between stored times.
"""
struct NodeSeries{N}
    fields::NTuple{N, Array{Float64, 3}}
    time_offset::Float64
    step_hours::Float64
end

"""
    NodeSeries(grid, arrays, corridor)

Spatial interpolation of each array in the tuple `arrays` of the gridded fields `grid`
at every water node of `corridor` and every stored time.
"""
function NodeSeries(grid::GriddedFields, arrays::NTuple{N}, corridor) where {N}
    steps = step_count(grid)
    stage_count, lateral_count = size(corridor.lat)
    fields = ntuple(_ -> zeros(steps, lateral_count, stage_count), N)
    for stage in 1:stage_count, lateral in 1:lateral_count, step in 1:steps
        corridor.water[stage, lateral] || continue
        time = grid.time_offset + (step - 1) * grid.step_hours
        values = sample(grid, arrays, corridor.lat[stage, lateral],
            corridor.lon[stage, lateral], time)
        for (field, value) in zip(fields, values)
            field[step, lateral, stage] = value
        end
    end
    return NodeSeries(fields, grid.time_offset, grid.step_hours)
end

"""
    window_steps(series, departure, hours)

Indices of the stored times of `series` whose linear interpolation covers `departure` to
`departure + hours` [h].
"""
function window_steps(series::NodeSeries, departure, hours)
    steps = size(first(series.fields), 1)
    first_step = floor(Int, (departure - series.time_offset) / series.step_hours) + 1
    last_step = ceil(Int, (departure + hours - series.time_offset) / series.step_hours)
    return clamp(first_step, 1, steps):clamp(last_step + 1, 1, steps)
end

"""
    CorridorWeather(weather, corridor)

ERA5 `weather` interpolated in space once to the nodes of `corridor`, for the
[`node_extremes`](@ref) of a [`cost_to_go_bound`](@ref): wind (east, north) and waves
(height, period, direction east and north components) as [`NodeSeries`](@ref).
"""
struct CorridorWeather
    weather::ERA5Weather
    wind::NodeSeries{2}
    waves::NodeSeries{4}
end

CorridorWeather(weather::ERA5Weather, corridor::Corridor) = CorridorWeather(weather,
    NodeSeries(weather.wind, weather.wind_arrays, corridor),
    NodeSeries(weather.waves, weather.wave_arrays, corridor))

duration(weather::CorridorWeather) = duration(weather.weather)

"corridor weather already computed in this session, by weather and corridor"
const CORRIDOR_WEATHERS = Dict{Tuple{ERA5Weather, Corridor}, CorridorWeather}()
const CORRIDOR_WEATHER_LOCK = ReentrantLock()

"""
    corridor_weather(weather, corridor)

`weather` as the router reads it on `corridor`: ERA5 weather, also inside a
[`ForecastWeather`](@ref), as the [`CorridorWeather`](@ref) of the corridor, computed
once per session; other weather as it is.
"""
corridor_weather(weather, corridor) = weather
corridor_weather(forecast::ForecastWeather, corridor) = ForecastWeather(
    corridor_weather(forecast.weather, corridor), forecast.issue_time, forecast.horizon)
corridor_weather(weather::ERA5Weather, corridor::Corridor) =
    @lock CORRIDOR_WEATHER_LOCK get!(() -> CorridorWeather(weather, corridor),
        CORRIDOR_WEATHERS, (weather, corridor))

"""
    edge_wind(weather, corridor, stage, lateral, next, share, time)
    edge_waves(weather, corridor, stage, lateral, next, share, time)

`wind` and `waves` at `share` (0 to 1) along the edge of `corridor` from node (`stage`,
`lateral`) to node (`stage + 1`, `next`) at `time` [h], at the point that far along the
straight line in latitude and longitude.
"""
edge_wind(weather, corridor, stage, lateral, next, share, time) =
    wind(weather, edge_point(corridor, stage, lateral, next, share)..., time)
edge_waves(weather, corridor, stage, lateral, next, share, time) =
    waves(weather, edge_point(corridor, stage, lateral, next, share)..., time)

edge_wind(forecast::ForecastWeather, corridor, stage, lateral, next, share, time) =
    edge_wind(forecast.weather, corridor, stage, lateral, next, share,
        forecast_time(forecast, time))
edge_waves(forecast::ForecastWeather, corridor, stage, lateral, next, share, time) =
    edge_waves(forecast.weather, corridor, stage, lateral, next, share,
        forecast_time(forecast, time))

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

"longest time between the weather samples along an edge [h]"
const EDGE_SAMPLE_HOURS = 6.0

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
end

"""
    EdgeSample(table, weather, corridor, stage, lateral, step, share, time)

[`EdgeSample`](@ref) for the [`PerformanceTable`](@ref) `table` at `share` (0 to 1)
along edge `step` of node (`stage`, `lateral`) of `corridor` at `time` [h], on the
course the edge starts on, in the weather of [`edge_wind`](@ref) and
[`edge_waves`](@ref).
"""
function EdgeSample(table::PerformanceTable, weather, corridor, stage, lateral, step,
        share, time)
    next = next_lateral(lateral, step)
    course = corridor.edge_course[stage, lateral, step]
    east, north = edge_wind(weather, corridor, stage, lateral, next, share, time)
    wind_speed = hypot(east, north)
    angle = true_wind_angle(east, north, wind_speed, course)
    wave_height, wave_period, wave_from = edge_waves(weather, corridor, stage, lateral,
        next, share, time)
    condition = SeaCondition(table, wind_speed, angle, wave_height, wave_period,
        wave_heading(wave_from, course))
    crosswind, headwind = kite_wind(table, wind_speed) .* sincos(angle)
    return EdgeSample(condition, headwind, crosswind)
end

"""
    edge_intervals(hours)

Number of intervals between the [`EdgeSample`](@ref)s of an edge sailed in `hours` [h].
"""
edge_intervals(hours) = max(1, ceil(Int, hours / EDGE_SAMPLE_HOURS))

"""
    trapezoid_weight(k, count)

Weight of the `k`-th of `count` equally spaced samples in the trapezoidal mean over them.
"""
trapezoid_weight(k, count) = (k == 1 || k == count ? 0.5 : 1.0) / (count - 1)

"""
    held_speed(table, speed_index, sample)

Highest routing speed number up to `speed_index` of the [`RouteTable`](@ref) `table`
that the ship can hold at the [`EdgeSample`](@ref) `sample` with the rig stowed, or with
a kite flying where [`kite_aloft`](@ref) allows, with the fuel power [W] flown and stowed
there; speed number 0 if it cannot hold the lowest.
"""
function held_speed(table::RouteTable, speed_index, sample::EdgeSample)
    for i in speed_index:-1:1
        flown, stowed = edge_fuels(table, i, sample.condition)
        isfinite(stowed) && return i, flown, stowed
        isfinite(flown) && kite_aloft(table.table, table.speeds[i], sample.headwind,
            sample.crosswind, sample.condition.wave_height) && return i, flown, stowed
    end
    return 0, Inf, Inf
end

"""
    SailedPoint

One [`EdgeSample`](@ref) of an edge as sailed.
"""
struct SailedPoint
    sample::EdgeSample
    "routing speed number held there; 0 where not even the lowest can be held"
    speed_index::Int
    "fuel power with the rig flown at the held speed [W]"
    flown::Float64
    "fuel power with the rig stowed at the held speed [W]; `Inf` where only a flying kite
    holds it"
    stowed::Float64
    "hours of the edge the point stands for [h]"
    hours::Float64
end

"""
    SailedPoint(table, sample, speed_index, distance)

[`SailedPoint`](@ref) of `sample` at commanded routing speed number `speed_index` of
`table`, at the [`held_speed`](@ref), standing for `distance` [m] of the edge.
"""
function SailedPoint(table::RouteTable, sample::EdgeSample, speed_index, distance)
    held, flown, stowed = held_speed(table, speed_index, sample)
    hours = held == 0 ? Inf : distance / table.speeds[held] / 3600
    return SailedPoint(sample, held, flown, stowed, hours)
end

"""
    first_point(table, start, corridor, stage, lateral, step, speed_index)

[`SailedPoint`](@ref) of the [`EdgeSample`](@ref) `start` at the start of edge `step` of
node (`stage`, `lateral`) of `corridor` at commanded routing speed number `speed_index`
of `table`, standing for its trapezoidal share of the edge.
"""
function first_point(table::RouteTable, start, corridor, stage, lateral, step,
        speed_index)
    distance = corridor.edge_length[stage, lateral, step]
    intervals = edge_intervals(distance / table.speeds[speed_index] / 3600)
    return SailedPoint(table, start, speed_index,
        trapezoid_weight(1, intervals + 1) * distance)
end

"""
    sail_edge!(points, first, table, weather, corridor, stage, lateral, step, time,
               speed_index)

Fill `points` with the [`SailedPoint`](@ref)s of edge `step` of node (`stage`,
`lateral`) left at `time` [h] at commanded routing speed number `speed_index` of `table`,
the first being the [`first_point`](@ref) `first`: equally spaced in distance, at most
`EDGE_SAMPLE_HOURS` apart at the commanded speed, each standing for its trapezoidal
share of the distance at the speed held there, and each taken when the ship would reach
it at the speed held at the point before. Returns the hours of the edge, the sum of
those shares, or `Inf` if a point cannot hold the lowest routing speed.
"""
function sail_edge!(points, first, table::RouteTable, weather, corridor, stage, lateral,
        step, time, speed_index)
    distance = corridor.edge_length[stage, lateral, step]
    intervals = edge_intervals(distance / table.speeds[speed_index] / 3600)
    resize!(points, intervals + 1)
    points[1] = first
    hours, sample_time = first.hours, time
    for k in 1:intervals
        isfinite(hours) || return Inf
        sample_time += distance / intervals / table.speeds[points[k].speed_index] / 3600
        sample = EdgeSample(table.table, weather, corridor, stage, lateral, step,
            k / intervals, sample_time)
        points[k + 1] = SailedPoint(table, sample, speed_index,
            trapezoid_weight(k + 1, intervals + 1) * distance)
        hours += points[k + 1].hours
    end
    return hours
end

"""
    EdgeTally

A way through the [`SailedPoint`](@ref)s of an edge: fuel and rig cost [USD], fuel
energy [J], hours of kite flight and of kite parked aloft [h], and kite launches.
"""
struct EdgeTally
    cost::Float64
    energy::Float64
    flight_hours::Float64
    parked_hours::Float64
    launches::Int
end

"no way through an edge"
const NO_TALLY = EdgeTally(Inf, 0.0, 0.0, 0.0, 0)

"""
    extend(tally, power, hours, wear, mode, launched, prices, cycle_cost)

`tally` followed by `hours` [h] at fuel `power` [W] with rig `wear` [USD/h] in kite
`mode`, after a launch at `cycle_cost` [USD] if `launched`.
"""
function extend(tally::EdgeTally, power, hours, wear, mode, launched, prices, cycle_cost)
    energy = power * hours * 3600
    return EdgeTally(tally.cost + energy * prices.fuel + wear * hours +
                     launched * cycle_cost, tally.energy + energy,
        tally.flight_hours + (mode == FLYING) * hours,
        tally.parked_hours + (mode == PARKED) * hours, tally.launches + launched)
end

"the cheaper of two [`EdgeTally`](@ref)s, the first if they cost the same"
cheaper(a::EdgeTally, b::EdgeTally) = a.cost <= b.cost ? a : b

"""
    kite_passage(table, points, aloft, prices)

Cheapest ways through the [`SailedPoint`](@ref)s of an edge on the [`RouteTable`](@ref)
`table` that end with the kite down and with it aloft, for a kite aloft before the first
point if `aloft`, as [`EdgeTally`](@ref)s. At each point a kite down burns the stowed
fuel, and cannot be down where only a flying kite holds the speed; where
[`kite_aloft`](@ref) allows, a kite aloft flies or parks, whichever is cheaper there, and
a kite down may launch; landing is free. Wings and rotors stay down,
burning their fuel with the rig standing.
"""
function kite_passage(table::RouteTable, points, aloft, prices)
    start = EdgeTally(0.0, 0.0, 0.0, 0.0, 0)
    down, up = aloft ? (NO_TALLY, start) : (start, NO_TALLY)
    for point in points
        allowed = kite_aloft(table.table, table.speeds[point.speed_index],
            point.sample.headwind, point.sample.crosswind,
            point.sample.condition.wave_height)
        next_down = extend(cheaper(down, up), point.stowed, point.hours, 0.0, STOWED,
            false, prices, table.table.cycle_cost)
        up = allowed ? cheaper(aloft_tally(table.table, up, point, false, prices),
            aloft_tally(table.table, down, point, true, prices)) : NO_TALLY
        down = next_down
    end
    return down, up
end

"""
    aloft_tally(table, tally, point, launched, prices)

`tally` followed by the [`SailedPoint`](@ref) `point` with the kite flying or parked,
whichever is cheaper there, after a launch if `launched`.
"""
function aloft_tally(table::PerformanceTable, tally, point, launched, prices)
    parked = extend(tally, point.stowed, point.hours, table.parked_wear_cost, PARKED,
        launched, prices, table.cycle_cost)
    isfinite(point.flown) && point.flown !== point.stowed || return parked
    return cheaper(parked, extend(tally, point.flown, point.hours, table.wear_cost, FLYING,
        launched, prices, table.cycle_cost))
end

"""
    may_improve(here, penalty, first, rate, distance, commanded, prices, budget)

Whether an edge of `distance` [m] from a state of objective `here` [USD], commanded to
take `commanded` hours [h] and starting with the [`SailedPoint`](@ref) `first`, can stay
within `budget` [USD] at the coastal `penalty` and the fuel and time `prices`: the first
point at its least fuel, the rest at no less than `rate` [USD/m].
"""
function may_improve(here, penalty, first::SailedPoint, rate, distance, commanded, prices,
        budget)
    isfinite(first.hours) || return false
    first_cost = min(first.flown, first.stowed) * first.hours * 3600 * prices.fuel
    rest = distance * (1 - trapezoid_weight(1, edge_intervals(commanded) + 1))
    least_cost = here + edge_objective(penalty, first_cost, first.hours, prices) +
                 rate * rest
    return least_cost <= budget
end

"""
    no_cost_to_go(corridor, table)

Bounds of a [`cost_to_go_bound`](@ref) that bound nothing: zero everywhere.
"""
no_cost_to_go(corridor::Corridor, table::RouteTable) = (; node=zeros(size(corridor.lat)),
    edge=zeros(size(corridor.edge_length)..., length(table.speeds)))

"""
    summary_mode(tally, hours)

Mode in which the kite spent the most of the `hours` [h] of an edge.
"""
function summary_mode(tally::EdgeTally, hours)
    stowed_hours = hours - tally.flight_hours - tally.parked_hours
    tally.flight_hours >= max(tally.parked_hours, stowed_hours) && return FLYING
    return tally.parked_hours > stowed_hours ? PARKED : STOWED
end

"""
    node_extremes(weather, corridor, stage, lateral, departure, hours)

Strongest wind [m/s], lowest and highest significant wave height [m] at a node from
`departure` to `departure + hours` [h]; any wind and sea for weather without stored
times.
"""
node_extremes(weather, corridor, stage, lateral, departure, hours) = (Inf, 0.0, Inf)

function node_extremes(weather::CorridorWeather, corridor, stage, lateral, departure,
        hours)
    strongest = 0.0
    east, north = weather.wind.fields
    for k in window_steps(weather.wind, departure, hours)
        strongest = max(strongest, hypot(east[k, lateral, stage], north[k, lateral, stage]))
    end
    lowest, highest = Inf, 0.0
    heights = first(weather.waves.fields)
    for k in window_steps(weather.waves, departure, hours)
        height = isnan(heights[k, lateral, stage]) ? 0.0 : heights[k, lateral, stage]
        lowest, highest = min(lowest, height), max(highest, height)
    end
    return strongest, lowest, highest
end

"""
    node_extremes(forecast::ForecastWeather, corridor, stage, lateral, departure, hours)

Extremes over the up to three spans of the underlying weather that the forecast reads:
the known span up to the horizon, then the span shifted a year ahead and the span
shifted a year back.
"""
function node_extremes(forecast::ForecastWeather, corridor, stage, lateral, departure,
        hours)
    finish = departure + hours
    known = forecast.issue_time + forecast.horizon
    last_ahead = duration(forecast.weather) - FORECAST_SHIFT
    spans = ((departure, min(finish, known), 0.0),
        (max(departure, known), min(finish, last_ahead), FORECAST_SHIFT),
        (max(departure, known, last_ahead), finish, -FORECAST_SHIFT))
    strongest, lowest, highest = 0.0, Inf, 0.0
    for (start, stop, shift) in spans
        start <= stop || continue
        wind_speed, low, high = node_extremes(forecast.weather, corridor, stage, lateral,
            start + shift, stop - start)
        strongest, lowest, highest = max(strongest, wind_speed), min(lowest, low),
        max(highest, high)
    end
    return strongest, lowest, highest
end

"""
    least_rates!(rates, table, wind_cell, lowest, highest, time_cost, penalty)

Fill `rates` with the objective per metre [USD/m] that no edge of the
[`RouteTable`](@ref) `table` commanded at each routing speed undercuts with a 10 m wind
in wind cell `wind_cell` or below and waves from `lowest` to `highest` [m]: the least
over that speed and the slower ones, which it may slow to, of the fuel cost per hour
plus `time_cost` [USD/h] over the distance sailed in an hour, times the coastal
`penalty`.
"""
function least_rates!(rates, table::RouteTable, wind_cell, lowest, highest, time_cost,
        penalty)
    (; bound) = table
    price = table.table.ship.fuel.price
    rate = Inf
    for (i, speed) in enumerate(table.speeds)
        resistance = bound.least_wave_resistance[i]
        height = resistance >= 0 ? lowest : highest
        thrust = bound.least_calm_thrust[i, wind_cell] + height^2 * resistance
        fuel = bound_fuel_power(bound, i, thrust)
        rate = min(rate, penalty * (fuel * 3600 * price + time_cost) / (3600speed))
        rates[i] = rate
    end
    return rates
end

"""
    cost_to_go_bound(corridor, table, weather, departure, hours, time_cost,
                     coastal_penalty)

Lower bounds on the objective [USD]: from each node (stage, lateral) of `corridor` to
the destination, by a backward pass over the edges, and per metre of each edge (stage,
lateral, step) at each commanded routing speed [USD/m], by the [`least_rates!`](@ref)
that the strongest wind and the range of sea at either of its nodes from `departure` to
`departure + hours` [h] allow. Returns them as `(; node, edge)`.
"""
function cost_to_go_bound(corridor::Corridor, table::RouteTable, weather, departure,
        hours, time_cost, coastal_penalty)
    stage_count, lateral_count = size(corridor.lat)
    _, winds, _ = table.table.flown_thrust.knots
    extremes = fill((0.0, Inf, 0.0), stage_count, lateral_count)
    for stage in 1:stage_count, lateral in 1:lateral_count
        corridor.water[stage, lateral] || continue
        extremes[stage, lateral] = node_extremes(weather, corridor, stage, lateral,
            departure, hours)
    end
    to_go = fill(Inf, stage_count, lateral_count)
    to_go[stage_count, centre_index(corridor)] = 0.0
    rates = zeros(size(corridor.edge_length)..., length(table.speeds))
    for stage in (stage_count - 1):-1:1, lateral in 1:lateral_count
        corridor.water[stage, lateral] || continue
        start = extremes[stage, lateral]
        for step in 1:(2MAX_LATERAL_STEP + 1)
            isnan(corridor.edge_course[stage, lateral, step]) && continue
            next = next_lateral(lateral, step)
            finish = extremes[stage + 1, next]
            strongest = max(start[1], finish[1])
            wind_cell = KnotWeight(winds, min(strongest, table.table.max_wind)).index
            penalty = edge_penalty(corridor, stage, next, coastal_penalty)
            edge_rates = least_rates!(view(rates, stage, lateral, step, :), table,
                wind_cell, min(start[2], finish[2]), max(start[3], finish[3]), time_cost,
                penalty)
            edge = last(edge_rates) * corridor.edge_length[stage, lateral, step]
            to_go[stage, lateral] = min(to_go[stage, lateral],
                to_go[stage + 1, next] + edge)
        end
    end
    return (; node=to_go, edge=rates)
end

"""
    nearest_lateral(corridor, stage, lat, lon)

Lateral node of `stage` closest to the point (`lat`, `lon`).
"""
nearest_lateral(corridor::Corridor, stage, lat, lon) =
    argmin([distance(lat, lon, corridor.lat[stage, j], corridor.lon[stage, j])
            for j in axes(corridor.lat, 2)])

"time bin of the coarse pass that bounds a route [h]"
const COARSE_TIME_STEP = 48.0

"routing speeds the coarse pass skips between those it commands, plus one"
const COARSE_SPEED_STRIDE = 2

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

Only the nodes of [`pruned_route`](@ref) around a [`coarse_route`](@ref) are searched; where
that leaves no path, the programme runs again on all nodes without the bound. Returns
`nothing` if no path arrives within 1200 h.
"""
function route(corridor::Corridor, table::RouteTable, weather, departure; time_cost,
        first_stage=1, first_lateral=centre_index(corridor), first_aloft=false,
        coastal_penalty=1.0)
    time_step, max_duration = 3.0, 1200.0
    stage_count, lateral_count = size(corridor.lat)
    options = (; time_cost, first_stage, first_lateral, first_aloft, coastal_penalty)
    workspace = acquire_workspace(lateral_count, ceil(Int, max_duration / time_step),
        stage_count)
    try
        bound = coarse_route(corridor, table, weather, departure, max_duration, options)
        leg = isnothing(bound) ? nothing :
              pruned_route(workspace, corridor, table, weather, departure, bound,
            max_duration; time_step, options...)
        return isnothing(leg) ? route_pass(workspace, corridor, table, weather, departure,
            corridor.water; time_step, options...) : leg
    finally
        release_workspace(workspace)
    end
end

route(corridor::Corridor, table::PerformanceTable, weather, departure; options...) =
    route(corridor, RouteTable(table), weather, departure; options...)

"lateral rows on each side of the coarse path that the fine programme searches"
const BAND_ROWS = 3

"""
    band_nodes(corridor, leg, first_stage)

Water nodes of `corridor` within `BAND_ROWS` rows of the path of `leg`, which starts at
stage `first_stage`.
"""
function band_nodes(corridor::Corridor, leg::Leg, first_stage)
    nodes = falses(size(corridor.water))
    for (index, (lat, lon)) in enumerate(leg.path)
        stage = first_stage + index - 1
        centre = nearest_lateral(corridor, stage, lat, lon)
        nodes[stage, max(1, centre - BAND_ROWS):min(end, centre + BAND_ROWS)] .= true
    end
    return nodes .& corridor.water
end

"how much dearer than the coarse path a rival path may be to widen the search [-]"
const RIVAL_MARGIN = 0.25

"""
    rival_nodes(corridor, leg, first_stage, side)

Water nodes of `corridor` without those at the stage halfway along the open ocean of `leg`
that are not more than `BAND_ROWS` rows from its path towards `side` (1 or -1), so that a
path over them passes the path of `leg` on that side.
"""
function rival_nodes(corridor::Corridor, leg::Leg, first_stage, side)
    stages = first_stage:(first_stage + length(leg.path) - 1)
    ocean = filter(stage -> count(view(corridor.water, stage, :)) > 1, stages)
    nodes = copy(corridor.water)
    isempty(ocean) && return nodes
    stage = ocean[(length(ocean) + 1) ÷ 2]
    lat, lon = leg.path[stage - first_stage + 1]
    centre = nearest_lateral(corridor, stage, lat, lon)
    for lateral in axes(nodes, 2)
        side * (lateral - centre) <= BAND_ROWS && (nodes[stage, lateral] = false)
    end
    return nodes
end

"""
    pruned_route(workspace, corridor, table, weather, departure, bound, max_duration;
                 time_step, time_cost, coastal_penalty, first_stage, options...)

[`route_pass`](@ref) over the [`band_nodes`](@ref) of the
[`coarse_route`](@ref) `bound` and of its rivals on either side by [`rival_nodes`](@ref)
and the `BAND_ROWS` around the reference track, skipping the states that cannot beat its
objective by their [`cost_to_go_bound`](@ref) in the [`corridor_weather`](@ref).
"""
function pruned_route(workspace, corridor, table, weather, departure, bound, max_duration;
        time_step, time_cost, coastal_penalty, first_stage, options...)
    rival_limit = (1 + RIVAL_MARGIN) * bound.objective
    bound_weather = corridor_weather(weather, corridor)
    to_go = cost_to_go_bound(corridor, table, bound_weather, departure,
        rival_limit / time_cost, time_cost, coastal_penalty)
    coarse_options = (; time_cost, coastal_penalty, first_stage, options...)
    nodes = band_nodes(corridor, bound, first_stage)
    centre_rows = centre_index(corridor) .+ (-BAND_ROWS:BAND_ROWS)
    nodes[:, centre_rows] .= view(corridor.water, :, centre_rows)
    for side in (-1, 1)
        rival = coarse_route(corridor, table, weather, departure, max_duration,
            coarse_options, rival_nodes(corridor, bound, first_stage, side), to_go,
            rival_limit)
        isnothing(rival) || (nodes .|= band_nodes(corridor, rival, first_stage))
    end
    upper_bound = (1 + 1e-9) * bound.objective
    to_go = cost_to_go_bound(corridor, table, bound_weather, departure,
        upper_bound / time_cost, time_cost, coastal_penalty)
    return route_pass(workspace, corridor, table, weather, departure, nodes, to_go,
        upper_bound; time_step, time_cost, coastal_penalty, first_stage, options...)
end

"""
    coarse_route(corridor, table, weather, departure, max_duration, options,
                 nodes=corridor.water, to_go=no_cost_to_go(corridor, table),
                 upper_bound=Inf)

[`route_pass`](@ref) with `COARSE_TIME_STEP` bins and every `COARSE_SPEED_STRIDE`-th
commanded speed, in a workspace of its own.
"""
function coarse_route(corridor, table, weather, departure, max_duration, options,
        nodes=corridor.water, to_go=no_cost_to_go(corridor, table), upper_bound=Inf)
    workspace = acquire_workspace(size(corridor.lat, 2),
        ceil(Int, max_duration / COARSE_TIME_STEP), size(corridor.lat, 1))
    try
        return route_pass(workspace, corridor, table, weather, departure, nodes, to_go,
            upper_bound; time_step=COARSE_TIME_STEP, speed_stride=COARSE_SPEED_STRIDE,
            options...)
    finally
        release_workspace(workspace)
    end
end

"""
    route_pass(workspace, corridor, table, weather, departure, nodes,
               to_go=no_cost_to_go(corridor, table), upper_bound=Inf; time_cost,
               time_step, speed_stride=1, first_stage, first_lateral, first_aloft,
               coastal_penalty)

The dynamic programme of [`route`](@ref) in `workspace`, whose bins are `time_step` [h]
long, over the `nodes` (stage × lateral) of `corridor` and every `speed_stride`-th
commanded speed, skipping states and edges whose objective plus the lower bounds `to_go`
of a [`cost_to_go_bound`](@ref) exceeds `upper_bound` [USD]. Returns the [`Leg`](@ref) or
`nothing`.
"""
function route_pass(workspace::RouteWorkspace, corridor::Corridor, table::RouteTable,
        weather, departure, nodes, to_go=no_cost_to_go(corridor, table), upper_bound=Inf;
        time_cost, time_step, speed_stride=1, first_stage, first_lateral, first_aloft,
        coastal_penalty)
    ship_table = table.table
    (; speeds) = table
    (; cost, elapsed) = workspace
    stage_count, lateral_count = size(corridor.lat)
    bins = size(cost, 2)
    prices = (; fuel=ship_table.ship.fuel.price, time=time_cost)
    durations = zeros(2MAX_LATERAL_STEP + 1, length(speeds))
    points = SailedPoint[]
    fill!(view(cost, :, :, :, first_stage:stage_count), Inf)
    start_state!(workspace, (first_lateral, 1, first_aloft + 1, first_stage))
    for stage in first_stage:(stage_count - 1), lateral in 1:lateral_count
        nodes[stage, lateral] || continue
        for step in axes(durations, 1), speed_index in eachindex(speeds)
            durations[step, speed_index] =
                corridor.edge_length[stage, lateral, step] / speeds[speed_index] / 3600
        end
        budget = upper_bound - to_go.node[stage, lateral]
        for aloft in 1:2, bin in 1:bins
            here = cost[lateral, bin, aloft, stage]
            isfinite(here) && here <= budget || continue
            time = elapsed[lateral, bin, aloft, stage]
            for step in 1:(2MAX_LATERAL_STEP + 1)
                isnan(corridor.edge_course[stage, lateral, step]) && continue
                next = next_lateral(lateral, step)
                nodes[stage + 1, next] || continue
                next_budget = upper_bound - to_go.node[stage + 1, next]
                penalty = edge_penalty(corridor, stage, next, coastal_penalty)
                start = EdgeSample(ship_table, weather, corridor, stage, lateral, step, 0.0,
                    departure + time)
                for speed_index in 1:speed_stride:length(speeds)
                    commanded = durations[step, speed_index]
                    first = first_point(table, start, corridor, stage, lateral, step,
                        speed_index)
                    may_improve(here, penalty, first, to_go.edge[stage, lateral, step,
                        speed_index], corridor.edge_length[stage, lateral, step],
                        commanded, prices, next_budget) || continue
                    hours = sail_edge!(points, first, table, weather, corridor, stage,
                        lateral, step, departure + time, speed_index)
                    time + hours < bins * time_step || continue
                    next_bin = floor(Int, (time + hours) / time_step) + 1
                    down, up = kite_passage(table, points, aloft == 2, prices)
                    origin = (lateral, bin, aloft, stage)
                    edge = (; here, penalty, hours, speed_index)
                    relax!(workspace, origin, (next, next_bin, 1), down, edge, prices)
                    relax!(workspace, origin, (next, next_bin, 2), up, edge, prices)
                end
            end
        end
    end
    objective, best = findmin(view(cost, centre_index(corridor), :, :, stage_count))
    isfinite(objective) || return nothing
    return traced_leg(workspace, corridor, table, (centre_index(corridor), Tuple(best)...,
        stage_count), first_stage)
end

"""
    start_state!(workspace, start)

Make state `start` (lateral, bin, aloft, stage) of `workspace` the departure: no cost,
time, fuel or kite use so far.
"""
function start_state!(workspace::RouteWorkspace, start)
    workspace.cost[start...] = workspace.elapsed[start...] = 0.0
    workspace.energy[start...] = workspace.flight_hours[start...] = 0.0
    workspace.parked_hours[start...] = 0.0
    workspace.launches[start...] = workspace.mode[start...] = 0
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
    (; cost, elapsed, energy, flight_hours, parked_hours, launches, parent, speed_index,
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
    parked_hours[arrival...] = parked_hours[origin...] + tally.parked_hours
    launches[arrival...] = launches[origin...] + tally.launches
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
    path = NTuple{5, Float64}[]
    while stage >= first_stage
        state = (lateral, bin, aloft, stage)
        speed = stage == first_stage ? 0.0 : table.speeds[speed_index[state...]]
        pushfirst!(path, (corridor.lat[stage, lateral], corridor.lon[stage, lateral],
            elapsed[state...], speed, mode[state...]))
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
        workspace.flight_hours[final...], workspace.parked_hours[final...],
        workspace.launches[final...], elapsed[final...], workspace.cost[final...], path)
end

"""
    forecast_route(corridor, table, weather, departure; time_cost, horizon,
                   coastal_penalty=1.0)

Passage of a ship that re-plans every 24 hours by [`route`](@ref) on the
[`RouteTable`](@ref) `table` with a [`ForecastWeather`](@ref) of `horizon` hours and
sails each plan in the real `weather` until the next re-plan; fuel, flight hours and
objective are those of the real weather. Returns `nothing` if a plan fails.
"""
function forecast_route(corridor::Corridor, table::RouteTable, weather, departure;
        time_cost, horizon, coastal_penalty=1.0)
    ship_table = table.table
    prices = (; fuel=ship_table.ship.fuel.price, time=time_cost)
    stage_count = size(corridor.lat, 1)
    stage, lateral, aloft = 1, centre_index(corridor), false
    time, fuel_energy, flight_hours, parked_hours, launches = 0.0, 0.0, 0.0, 0.0, 0
    objective = 0.0
    path = [(corridor.lat[1, lateral], corridor.lon[1, lateral], 0.0, 0.0, 0.0)]
    points = SailedPoint[]
    while stage < stage_count
        forecast = ForecastWeather(weather, departure + time, horizon)
        plan = route(corridor, table, forecast, departure + time; time_cost,
            first_stage=stage, first_lateral=lateral, first_aloft=aloft, coastal_penalty)
        isnothing(plan) && return nothing
        plan_start = time
        for (next_lat, next_lon, _, speed, _) in plan.path[2:end]
            next = nearest_lateral(corridor, stage + 1, next_lat, next_lon)
            step = next - lateral + MAX_LATERAL_STEP + 1
            speed_index = searchsortedfirst(table.speeds, speed)
            start = EdgeSample(ship_table, weather, corridor, stage, lateral, step, 0.0,
                departure + time)
            first = first_point(table, start, corridor, stage, lateral, step, speed_index)
            hours = sail_edge!(points, first, table, weather, corridor, stage, lateral,
                step, departure + time, speed_index)
            isfinite(hours) || return nothing
            down, up = kite_passage(table, points, aloft, prices)
            aloft = up.cost < down.cost
            tally = aloft ? up : down
            penalty = edge_penalty(corridor, stage, next, coastal_penalty)
            objective += edge_objective(penalty, tally.cost, hours, prices)
            fuel_energy += tally.energy
            flight_hours += tally.flight_hours
            parked_hours += tally.parked_hours
            launches += tally.launches
            time += hours
            stage, lateral = stage + 1, next
            push!(path, (next_lat, next_lon, time, speed, summary_mode(tally, hours)))
            time - plan_start >= 24.0 && break
        end
    end
    return Leg(fuel_energy, fuel_energy * prices.fuel, flight_hours, parked_hours,
        launches, time, objective, path)
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
    route_corridors(route, mask; scale=1)

Outbound and return corridors between Rotterdam and the port of `route`: `:caribbean`
(Guadeloupe; outbound via the trade winds, homeward on the great circle), `:new_york`,
`:bilbao`, `:dakar`, `:houston` (through the Florida Strait) or `:tubarao` (Brazil), the
same band both ways. All run through the Channel to Ushant.
`scale` multiplies the stage and node spacing; the band reaches `CORRIDOR_HALF_WIDTH` to
either side.
"""
function route_corridors(route::Symbol, mask; scale=1)
    lateral_spacing = 60.0 * scale
    spacing = (ocean_spacing=90.0 * scale, lateral_spacing,
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
wave_heading(wave_from, course) = π - abs(rem2pi(wave_from - course, RoundNearest))
