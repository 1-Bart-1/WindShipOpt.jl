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

# kite down, parked aloft or flying patterns, as the mode of an edge
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

wind(forecast::ForecastWeather, lat, lon, time) =
    wind(forecast.weather, lat, lon, forecast_time(forecast, time))
waves(forecast::ForecastWeather, lat, lon, time) =
    waves(forecast.weather, lat, lon, forecast_time(forecast, time))

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
    EdgeSample(table, (east, north), (wave_height, wave_period, wave_from), course)

[`EdgeSample`](@ref) for the [`PerformanceTable`](@ref) `table` of a 10 m wind [m/s] and
the [`waves`](@ref) on `course` [rad from north].
"""
function EdgeSample(table::PerformanceTable, (east, north), (wave_height, wave_period,
            wave_from), course)
    wind_speed = hypot(east, north)
    angle = true_wind_angle(east, north, wind_speed, course)
    condition = SeaCondition(table, wind_speed, angle, wave_height, wave_period,
        wave_heading(wave_from, course))
    crosswind, headwind = kite_wind(table, wind_speed) .* (sin(angle), cos(angle))
    return EdgeSample(condition, headwind, crosswind)
end

"""
    EdgeSample(table, weather, corridor, stage, lateral, step, share, time)

[`EdgeSample`](@ref) at `share` (0 to 1) along edge `step` of node (`stage`, `lateral`) of
`corridor` at `time` [h], on the course the edge starts on, in `weather`.
"""
function EdgeSample(table::PerformanceTable, weather, corridor, stage, lateral, step,
        share, time)
    lat, lon = edge_point(corridor, stage, lateral, next_lateral(lateral, step), share)
    return EdgeSample(table, wind(weather, lat, lon, time), waves(weather, lat, lon, time),
        corridor.edge_course[stage, lateral, step])
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

One [`EdgeSample`](@ref) of an edge as sailed, with what a kite needs to know of it.
"""
struct SailedPoint
    "true wind at the kite's reference height from ahead [m/s]"
    headwind::Float64
    "true wind at the kite's reference height from abeam [m/s]"
    crosswind::Float64
    "significant wave height [m]"
    wave_height::Float64
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
    return SailedPoint(sample.headwind, sample.crosswind, sample.condition.wave_height,
        held, flown, stowed, hours)
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
        allowed = kite_aloft(table.table, table.speeds[point.speed_index], point.headwind,
            point.crosswind, point.wave_height)
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
    summary_mode(tally, hours)

Mode in which the kite spent the most of the `hours` [h] of an edge.
"""
function summary_mode(tally::EdgeTally, hours)
    stowed_hours = hours - tally.flight_hours - tally.parked_hours
    tally.flight_hours >= max(tally.parked_hours, stowed_hours) && return FLYING
    return tally.parked_hours > stowed_hours ? PARKED : STOWED
end

"""
    nearest_lateral(corridor, stage, lat, lon)

Lateral node of `stage` closest to the point (`lat`, `lon`).
"""
nearest_lateral(corridor::Corridor, stage, lat, lon) =
    argmin([distance(lat, lon, corridor.lat[stage, j], corridor.lon[stage, j])
            for j in axes(corridor.lat, 2)])

"time between the knots of a [`CostToGo`](@ref) [h]"
const COST_TO_GO_STEP = 48.0

"routing speeds a [`CostToGo`](@ref) skips between those it commands, plus one"
const COST_TO_GO_SPEED_STRIDE = 2

"how far above the [`CostToGo`](@ref) of the departure the states searched may reach [-]"
const SEARCH_MARGINS = (0.03, 0.15)

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
end

function (to_go::CostToGo)(lateral, aloft, stage, time)
    position = time / COST_TO_GO_STEP + 1
    knot = floor(Int, position)
    knot < size(to_go.values, 2) || return Inf
    @inbounds lower, upper = to_go.values[lateral, knot, aloft, stage],
    to_go.values[lateral, knot + 1, aloft, stage]
    isfinite(lower) && isfinite(upper) && return lower + (position - knot) * (upper - lower)
    isfinite(lower) && return lower
    isfinite(upper) && return upper
    return isnan(lower) || isnan(upper) ? NaN : Inf
end

"""
    CostToGo(corridor, table, weather, departure; time_cost, first_stage, coastal_penalty)

[`CostToGo`](@ref) of a passage leaving at `departure` [h], by a backward programme over
the states at each stage at knots `COST_TO_GO_STEP` apart that a ship can reach between
its highest and lowest routing speed, on every `COST_TO_GO_SPEED_STRIDE`-th commanded
speed.
"""
function CostToGo(corridor::Corridor, table::RouteTable, weather, departure; time_cost,
        first_stage, coastal_penalty)
    stage_count, lateral_count = size(corridor.lat)
    centre = centre_index(corridor)
    along = cumsum([0.0; [distance(corridor.lat[stage, centre], corridor.lon[stage, centre],
                              corridor.lat[stage + 1, centre],
                              corridor.lon[stage + 1, centre])
                          for stage in 1:(stage_count - 1)]])
    slowest, fastest = first(table.speeds), last(table.speeds)
    knots = ceil(Int, (last(along) / slowest / 3600 + REACH_SLACK) / COST_TO_GO_STEP) + 2
    values = fill(Inf, lateral_count, knots, 2, stage_count)
    values[centre, :, :, stage_count] .= 0.0
    to_go = CostToGo(values)
    prices = (; fuel=table.table.ship.fuel.price, time=time_cost)
    for stage in (stage_count - 1):-1:first_stage, lateral in 1:lateral_count
        corridor.water[stage, lateral] || continue
        sailed = along[stage] - along[first_stage]
        earliest = 0.8sailed / fastest / 3600
        latest = sailed / slowest / 3600 + REACH_SLACK
        for knot in max(1, floor(Int, earliest / COST_TO_GO_STEP)):min(knots,
            ceil(Int, latest / COST_TO_GO_STEP) + 1)

            fill_knot!(to_go, corridor, table, weather, departure, prices, coastal_penalty,
                stage, lateral, knot)
        end
    end
    return to_go
end

"hours a [`CostToGo`](@ref) searches beyond the arrival at the lowest routing speed [h]"
const REACH_SLACK = 96.0

"""
    fill_knot!(to_go, corridor, table, weather, departure, prices, coastal_penalty, stage,
               lateral, knot)

Set the values of `to_go` at node (`stage`, `lateral`) and `knot`, kite down and aloft,
from those of the next stage.
"""
function fill_knot!(to_go, corridor, table, weather, departure, prices, coastal_penalty,
        stage, lateral, knot)
    time = (knot - 1) * COST_TO_GO_STEP
    lat, lon = corridor.lat[stage, lateral], corridor.lon[stage, lateral]
    node_wind = wind(weather, lat, lon, departure + time)
    node_waves = waves(weather, lat, lon, departure + time)
    points = SailedPoint[]
    for aloft in 1:(table.table.stowed_thrust === table.table.flown_thrust ? 1 : 2)
        best = Inf
        for step in 1:(2MAX_LATERAL_STEP + 1)
            isnan(corridor.edge_course[stage, lateral, step]) && continue
            next = next_lateral(lateral, step)
            penalty = edge_penalty(corridor, stage, next, coastal_penalty)
            start = EdgeSample(table.table, node_wind, node_waves,
                corridor.edge_course[stage, lateral, step])
            for speed_index in 1:COST_TO_GO_SPEED_STRIDE:length(table.speeds)
                first = first_point(table, start, corridor, stage, lateral, step,
                    speed_index)
                hours = sail_edge!(points, first, table, weather, corridor, stage, lateral,
                    step, departure + time, speed_index)
                isfinite(hours) || continue
                down, up = kite_passage(table, points, aloft == 2, prices)
                arrival = time + hours
                for (tally, next_aloft) in ((down, 1), (up, 2))
                    isfinite(tally.cost) || continue
                    ahead = to_go(next, next_aloft, stage + 1, arrival)
                    isnan(ahead) && continue
                    best = min(best, edge_objective(penalty, tally.cost, hours, prices) +
                                     ahead)
                end
            end
        end
        to_go.values[lateral, knot, aloft, stage] = isfinite(best) ? best : NaN
    end
end

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

The states searched are those within the `SEARCH_MARGINS` of a [`CostToGo`](@ref), wider
where that leaves no path, then all of them. Returns `nothing` if no path arrives within
1200 h.
"""
function route(corridor::Corridor, table::RouteTable, weather, departure; time_cost,
        first_stage=1, first_lateral=centre_index(corridor), first_aloft=false,
        coastal_penalty=1.0)
    time_step, max_duration = 3.0, 1200.0
    options = (; time_step, time_cost, first_stage, first_lateral, first_aloft,
        coastal_penalty)
    workspace = acquire_workspace(size(corridor.lat, 2), ceil(Int, max_duration / time_step),
        size(corridor.lat, 1))
    try
        to_go = CostToGo(corridor, table, weather, departure; time_cost, first_stage,
            coastal_penalty)
        estimate = to_go(first_lateral, first_aloft + 1, first_stage, 0.0)
        for margin in SEARCH_MARGINS
            leg = route_pass(workspace, corridor, table, weather, departure, to_go,
                (1 + margin) * estimate; options...)
            isnothing(leg) || return leg
        end
        return route_pass(workspace, corridor, table, weather, departure; options...)
    finally
        release_workspace(workspace)
    end
end

route(corridor::Corridor, table::PerformanceTable, weather, departure; options...) =
    route(corridor, RouteTable(table), weather, departure; options...)

"""
    route_pass(workspace, corridor, table, weather, departure, to_go=nothing, limit=Inf;
               time_cost, time_step, first_stage, first_lateral, first_aloft,
               coastal_penalty)

The dynamic programme of [`route`](@ref) in `workspace`, whose bins are `time_step` [h]
long, skipping states and commanded edges whose objective plus the [`CostToGo`](@ref)
`to_go` exceeds `limit` [USD]. Returns the [`Leg`](@ref) or `nothing`.
"""
function route_pass(workspace::RouteWorkspace, corridor::Corridor, table::RouteTable,
        weather, departure, to_go=nothing, limit=Inf; time_cost, time_step, first_stage,
        first_lateral, first_aloft, coastal_penalty)
    ship_table = table.table
    (; speeds) = table
    (; cost, elapsed) = workspace
    stage_count, lateral_count = size(corridor.lat)
    bins = size(cost, 2)
    prices = (; fuel=ship_table.ship.fuel.price, time=time_cost)
    points = SailedPoint[]
    fill!(view(cost, :, :, :, first_stage:stage_count), Inf)
    start_state!(workspace, (first_lateral, 1, first_aloft + 1, first_stage))
    for stage in first_stage:(stage_count - 1), lateral in 1:lateral_count
        corridor.water[stage, lateral] || continue
        lat, lon = corridor.lat[stage, lateral], corridor.lon[stage, lateral]
        for aloft in 1:2, bin in 1:bins
            here = cost[lateral, bin, aloft, stage]
            isfinite(here) || continue
            time = elapsed[lateral, bin, aloft, stage]
            within_limit(to_go, limit, here, lateral, aloft, stage, time) || continue
            node_wind = wind(weather, lat, lon, departure + time)
            node_waves = waves(weather, lat, lon, departure + time)
            for step in 1:(2MAX_LATERAL_STEP + 1)
                isnan(corridor.edge_course[stage, lateral, step]) && continue
                next = next_lateral(lateral, step)
                penalty = edge_penalty(corridor, stage, next, coastal_penalty)
                distance = corridor.edge_length[stage, lateral, step]
                start = EdgeSample(ship_table, node_wind, node_waves,
                    corridor.edge_course[stage, lateral, step])
                for speed_index in eachindex(speeds)
                    commanded = distance / speeds[speed_index] / 3600
                    edge_within_limit(to_go, limit, here + penalty * time_cost * commanded,
                        next, stage + 1, time + commanded) || continue
                    first = first_point(table, start, corridor, stage, lateral, step,
                        speed_index)
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
    within_limit(to_go, limit, here, lateral, aloft, stage, time)
    edge_within_limit(to_go, limit, here, next, stage, time)

Whether a state of objective `here` [USD], or an edge that would reach the node `next` of
`stage` at `time` [h] for at least the objective `here`, can stay within `limit` [USD] by
the [`CostToGo`](@ref) `to_go`; always where there is none or it found no path.
"""
within_limit(::Nothing, limit, here, lateral, aloft, stage, time) = true
within_limit(to_go::CostToGo, limit, here, lateral, aloft, stage, time) =
    !(here + to_go(lateral, aloft, stage, time) > limit)

edge_within_limit(::Nothing, limit, here, next, stage, time) = true
edge_within_limit(to_go::CostToGo, limit, here, next, stage, time) =
    !(here + min(to_go(next, 1, stage, time), to_go(next, 2, stage, time)) > limit)

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
function wave_heading(wave_from, course)
    difference = wave_from - course
    return π - abs(difference - 2π * round(difference / 2π))
end
