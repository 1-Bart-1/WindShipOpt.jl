dot3(a, b) = a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
norm3(a) = sqrt(dot3(a, a))

"""
    KitePolar

Rigid-shape lift and drag coefficient of a kite on its projected area over angle of
attack [rad], as written by `kite_polars/wing_polars.jl`.
"""
struct KitePolar
    angle_of_attack::Vector{Float64}
    lift::Vector{Float64}
    drag::Vector{Float64}
end

"""
    KitePolar(aspect_ratio)

Polar of the kite with projected `aspect_ratio` from `data/kite_polars/`.
"""
function KitePolar(aspect_ratio::Real)
    name = "kite_ar$(round(Int, aspect_ratio)).csv"
    path = joinpath(pkgdir(@__MODULE__), "data", "kite_polars", name)
    rows = [parse.(Float64, split(line, ',')) for line in readlines(path)[2:end]]
    return KitePolar(deg2rad.(getindex.(rows, 1)), getindex.(rows, 2), getindex.(rows, 3))
end

"""
    polar_value(polar, values, angle)

`values` of `polar` linearly interpolated at angle of attack `angle` [rad].
"""
function polar_value(polar::KitePolar, values, angle)
    angles = polar.angle_of_attack
    i = clamp(searchsortedlast(angles, angle), 1, length(angles) - 1)
    weight = (angle - angles[i]) / (angles[i + 1] - angles[i])
    return (1 - weight) * values[i] + weight * values[i + 1]
end

"""
    KiteModel

A kite on a fixed-length tether as the quasi-steady model sees it: projected area
[m^2], flying mass [kg], tether length [m], air density [kg/m^3], gravity [m/s^2], its
polar, the bridle and tether drag added to the polar, the angles of attack it depowers
down to and stalls at [rad], the smallest radius it can turn on through the air [m], and
whether it flies loops ([`LoopPattern`](@ref)) rather than steered sweeps.
"""
struct KiteModel
    area::Float64
    mass::Float64
    tether_length::Float64
    air_density::Float64
    gravity::Float64
    polar::KitePolar
    extra_drag::Float64
    lowest_angle::Float64
    stall_angle::Float64
    min_turn_radius::Float64
    flies_loops::Bool
end

"""
    KiteAero

Aerodynamic state of a kite at one angle of attack: projected area [m^2], lift and total
drag coefficient, flying mass [kg], air density [kg/m^3] and gravity [m/s^2].
"""
struct KiteAero
    area::Float64
    lift::Float64
    drag::Float64
    mass::Float64
    air_density::Float64
    gravity::Float64
end

"""
    KiteAero(model, angle)

`model` flying at angle of attack `angle` [rad].
"""
KiteAero(model::KiteModel, angle) = KiteAero(model.area,
    polar_value(model.polar, model.polar.lift, angle),
    polar_value(model.polar, model.polar.drag, angle) + model.extra_drag, model.mass,
    model.air_density, model.gravity)

const NO_ACCELERATION = (0.0, 0.0, 0.0)

"""
    balance_residual(kite, airflow, radial, acceleration)

Excess of the lift the force balance needs over the lift the kite makes in the relative
`airflow` [m/s] at unit `radial` position with ground `acceleration` [m/s^2], and the
tether tension [N] of that balance.
"""
function balance_residual(kite::KiteAero, airflow, radial, acceleration)
    airspeed = norm3(airflow)
    drag_direction = airflow ./ airspeed
    load = 0.5kite.air_density * airspeed^2 * kite.area
    inertia = kite.mass .* (acceleration .+ (0.0, 0.0, kite.gravity))
    tension = (load * kite.drag - dot3(inertia, drag_direction)) /
              dot3(radial, drag_direction)
    force = inertia .+ tension .* radial
    normal = force .- dot3(force, drag_direction) .* drag_direction
    return norm3(normal) - load * kite.lift, tension
end

"""
    steering_residual(kite, wind, radial, heading, turn, tether_length, airspeed,
                      along_path=NO_ACCELERATION)

[`balance_residual`](@ref) of a kite flying through the air at `airspeed` [m/s] along unit
`heading` in the tangent plane of the tether sphere at unit `radial` position, in the
uniform `wind` [m/s], while turning with curvature vector `turn` [1/m] and accelerating at
`along_path` [m/s^2]; also returns its ground velocity [m/s].
"""
function steering_residual(kite::KiteAero, wind, radial, heading, turn, tether_length,
        airspeed, along_path=NO_ACCELERATION)
    radial_wind = dot3(wind, radial)
    ground = wind .- radial_wind .* radial .+ airspeed .* heading
    acceleration = airspeed^2 .* turn .- (dot3(ground, ground) / tether_length) .* radial .+
                   along_path
    residual, tension = balance_residual(kite, radial_wind .* radial .- airspeed .* heading,
        radial, acceleration)
    return residual, tension, ground
end

"""
    flying_airspeed(residual)

Lowest airspeed [m/s] on a rising scan where `residual` says the kite makes more lift than
its balance needs, or `nothing` where it never does: a heavy wing makes too little at rest
and flies only once it is moving fast enough.
"""
function flying_airspeed(residual)
    first(residual(1e-3)) < 0 && return 1e-3
    speed = 1.0
    while speed < 400
        first(residual(speed)) < 0 && return speed
        speed *= 1.25
    end
    return nothing
end

"""
    steering_point(kite, wind, radial, heading, turn, tether_length,
                   along_path=NO_ACCELERATION)

Quasi-steady airspeed [m/s], tether tension [N] and ground velocity [m/s] of a kite held
at `heading` (see [`steering_residual`](@ref)), or `nothing` where it cannot fly with a
taut tether.
"""
function steering_point(kite::KiteAero, wind, radial, heading, turn, tether_length,
        along_path=NO_ACCELERATION)
    dot3(wind, radial) > 0 || return nothing
    residual(airspeed) = steering_residual(kite, wind, radial, heading, turn, tether_length,
        airspeed, along_path)
    low = flying_airspeed(residual)
    isnothing(low) && return nothing
    high = 2low
    point = residual(high)
    while first(point) < 0
        high *= 2
        high > 1e3 && return nothing
        point = residual(high)
    end
    for _ in 1:25
        middle = (low + high) / 2
        trial = residual(middle)
        first(trial) < 0 ? (low = middle) : ((high, point) = (middle, trial))
    end
    _, tension, ground = point
    return tension > 0 ? (high, tension, ground) : nothing
end

"""
    limited_point(model, angle, wind, radial, heading, turn, max_tension,
                  along_path=NO_ACCELERATION)

[`steering_point`](@ref) of `model` at angle of attack `angle` [rad], depowered towards
its lowest angle where the tension would exceed `max_tension` [N], keeping the most lift
that stays within the limit.
"""
function limited_point(model::KiteModel, angle, wind, radial, heading, turn, max_tension,
        along_path=NO_ACCELERATION)
    solve(angle) = steering_point(KiteAero(model, angle), wind, radial, heading, turn,
        model.tether_length, along_path)
    point = solve(angle)
    isnothing(point) || point[2] <= max_tension && return point
    low, high = model.lowest_angle, angle
    point = nothing
    for _ in 1:12
        middle = (low + high) / 2
        trial = solve(middle)
        if isnothing(trial)
            low = middle
        elseif trial[2] > max_tension
            high = middle
        else
            low = middle
            point = trial
        end
    end
    return point
end

"""
    SteeringPattern

Kite steered by its heading through the air, as the SkySails autopilot flies it (Erhard
and Strauch 2013): it holds `heading` [rad] to one side of the direction towards the edge
of the wind window, turns on its smallest radius through the edge direction to the same
heading on the other side when its roll angle about the apparent wind axis leaves
`centre` ± `half_width` [rad] (zero is horizontal towards positive crosswind, π/2 straight
up), and flies at `angle_of_attack` [rad] before depowering. A small heading sweeps the
kite slowly along the edge of the window, a large one flies figure eights through it.
"""
struct SteeringPattern
    centre::Float64
    half_width::Float64
    heading::Float64
    angle_of_attack::Float64
end

"""
    window_position(off_wind, roll)

Unit position on the tether sphere at angle `off_wind` [rad] from the apparent downwind
direction and `roll` [rad] about it, in the wind frame (downwind, crosswind, up).
"""
window_position(off_wind, roll) =
    (cos(off_wind), sin(off_wind) * cos(roll), sin(off_wind) * sin(roll))

"""
    PatternForce

Time-averaged tether force on the ship over one pattern in the wind frame over the
dynamic pressure times area [-], the peak tension over the same [-], and the lowest
tether elevation reached [rad]; `NaN` where the kite cannot fly the pattern.
"""
struct PatternForce
    force::NTuple{3, Float64}
    peak_tension::Float64
    lowest_elevation::Float64
end

const NO_PATTERN = PatternForce((NaN, NaN, NaN), NaN, NaN)

"maximum integration steps before a pattern counts as not settling into a cycle"
const MAX_PATTERN_STEPS = 2000

"change over one cycle of the distance from the window edge [rad] that counts as settled"
const CYCLE_TOLERANCE = deg2rad(0.1)

"""
    PatternForce(model, pattern, wind_speed, max_tension; path=nothing)

Fly `pattern` quasi-steadily in a uniform apparent wind of `wind_speed` [m/s] from its
centre until a full sweep cycle returns to within `CYCLE_TOLERANCE` of where it began,
and average over that closed cycle, depowering by [`limited_point`](@ref) wherever the
tension would exceed `max_tension` [N]; `NO_PATTERN` if it never settles. Steps are a
third of the smallest turn radius through the air. Positions of the averaged cycle are
pushed to `path` when given.
"""
function PatternForce(model::KiteModel, pattern::SteeringPattern, wind_speed, max_tension;
        path=nothing)
    wind = (wind_speed, 0.0, 0.0)
    radius = model.tether_length
    step = model.min_turn_radius / 3
    off_wind = clamp(atan(4cos(pattern.heading)), 0.3, 1.4)
    roll = pattern.centre
    heading = target = pattern.heading
    switches = 0
    cycle_start = NaN
    total = (0.0, 0.0, 0.0)
    duration = peak = 0.0
    lowest = Inf
    cycle = NTuple{3, Float64}[]
    for _ in 1:MAX_PATTERN_STEPS
        radial = window_position(off_wind, roll)
        edge = (-sin(off_wind), cos(off_wind) * cos(roll), cos(off_wind) * sin(roll))
        around = (0.0, -sin(roll), cos(roll))
        direction = cos(heading) .* edge .+ sin(heading) .* around
        left = cos(heading) .* around .- sin(heading) .* edge
        turn = (sign(target - heading) / model.min_turn_radius) .* left
        point = limited_point(model, pattern.angle_of_attack, wind, radial, direction,
            turn, max_tension)
        isnothing(point) && return NO_PATTERN
        airspeed, tension, ground = point
        time = step / airspeed
        total = total .+ (tension * time) .* radial
        duration += time
        peak = max(peak, tension)
        lowest = min(lowest, asin(radial[3]))
        isnothing(path) || push!(cycle, radial)
        turned = step / model.min_turn_radius
        heading = clamp(target, heading - turned, heading + turned)
        off_wind += dot3(ground, edge) * time / radius
        roll += dot3(ground, around) * time / (radius * sin(off_wind))
        0 < off_wind < π / 2 || return NO_PATTERN
        if target > 0 && roll > pattern.centre + pattern.half_width ||
           target < 0 && roll < pattern.centre - pattern.half_width
            target = -target
            switches += 1
            iseven(switches) || continue
            if abs(off_wind - cycle_start) < CYCLE_TOLERANCE
                isnothing(path) || append!(path, cycle)
                load = 0.5model.air_density * wind_speed^2 * model.area
                return PatternForce(total ./ (duration * load), peak / load, lowest)
            end
            cycle_start = off_wind
            total, duration, peak, lowest = (0.0, 0.0, 0.0), 0.0, 0.0, Inf
            empty!(cycle)
        end
    end
    return NO_PATTERN
end

"""
    LoopPattern

Wing flying circles at `angle_of_attack` [rad] on a cone of half angle `cone` [rad] whose
axis stands `axis_off_wind` [rad] from the apparent downwind direction at roll `axis_roll`
[rad] about it, with the angles as in [`window_position`](@ref).
"""
struct LoopPattern
    axis_roll::Float64
    axis_off_wind::Float64
    cone::Float64
    angle_of_attack::Float64
end

"points per loop at which [`LoopPattern`](@ref) is balanced"
const LOOP_POINTS = 36

"""
    holds_speed(model, airspeed, height_range)

Whether `model`, flying at `airspeed` [m/s] about the middle of a climb of `height_range`
[m] that its speed pays for, stays above its stall speed at the top.
"""
function holds_speed(model::KiteModel, airspeed, height_range)
    stall_load = 2model.mass * model.gravity /
                 (model.air_density * model.area * maximum(model.polar.lift))
    return airspeed^2 - model.gravity * height_range >= stall_load
end

"""
    PatternForce(model, pattern::LoopPattern, wind_speed, max_tension; path=nothing)

Average over one loop of `pattern` in a uniform apparent wind of `wind_speed` [m/s], time
weighted, with the speed of the wing paying for the weight along its path and depowering
by [`limited_point`](@ref) wherever the tension would exceed `max_tension` [N];
`NO_PATTERN` where a point has no balance or the wing stalls at the top. Positions are
pushed to `path` when given.
"""
function PatternForce(model::KiteModel, pattern::LoopPattern, wind_speed, max_tension;
        path=nothing)
    wind = (wind_speed, 0.0, 0.0)
    (; axis_off_wind, axis_roll, cone) = pattern
    axis = window_position(axis_off_wind, axis_roll)
    outward = (-sin(axis_off_wind), cos(axis_off_wind) * cos(axis_roll),
        cos(axis_off_wind) * sin(axis_roll))
    around = (0.0, -sin(axis_roll), cos(axis_roll))
    segment = 2π * model.tether_length * sin(cone) / LOOP_POINTS
    total = (0.0, 0.0, 0.0)
    duration = peak = 0.0
    lowest, highest = Inf, -Inf
    for i in 1:LOOP_POINTS
        phase = 2π * i / LOOP_POINTS
        spoke = cos(phase) .* outward .+ sin(phase) .* around
        radial = cos(cone) .* axis .+ sin(cone) .* spoke
        heading = cos(phase) .* around .- sin(phase) .* outward
        inward = sin(cone) .* axis .- cos(cone) .* spoke
        turn = (cot(cone) / model.tether_length) .* inward
        along_path = (-model.gravity * heading[3]) .* heading
        point = limited_point(model, pattern.angle_of_attack, wind, radial, heading, turn,
            max_tension, along_path)
        isnothing(point) && return NO_PATTERN
        airspeed, tension, _ = point
        time = segment / airspeed
        total = total .+ (tension * time) .* radial
        duration += time
        peak = max(peak, tension)
        lowest, highest = min(lowest, radial[3]), max(highest, radial[3])
        isnothing(path) || push!(path, radial)
    end
    mean_speed = LOOP_POINTS * segment / duration
    holds_speed(model, mean_speed, model.tether_length * (highest - lowest)) ||
        return NO_PATTERN
    load = 0.5model.air_density * wind_speed^2 * model.area
    return PatternForce(total ./ (duration * load), peak / load, asin(lowest))
end

"""
    parked_force(kite, elevation, side, wind_speed)

Tether force of the kite parked at `elevation` [rad] on the `side` (+1 or -1) of the
apparent wind of `wind_speed` [m/s], where its aerodynamic force, weight and tether
balance at rest.
"""
function parked_force(kite::KiteAero, elevation, side, wind_speed)
    wind = (wind_speed, 0.0, 0.0)
    still = (0.0, 0.0, 0.0)
    downwind = sphere_position(0.0, elevation)
    first(balance_residual(kite, wind, downwind, still)) < 0 || return NO_PATTERN
    low, high = 0.0, π / 2 - 1e-3
    for _ in 1:40
        middle = (low + high) / 2
        radial = sphere_position(side * middle, elevation)
        residual, tension = balance_residual(kite, wind, radial, still)
        residual < 0 && tension > 0 ? (low = middle) : (high = middle)
    end
    radial = sphere_position(side * low, elevation)
    _, tension = balance_residual(kite, wind, radial, still)
    tension > 0 || return NO_PATTERN
    load = 0.5kite.air_density * wind_speed^2 * kite.area
    return PatternForce(tension / load .* radial, tension / load, elevation)
end

"""
    sphere_position(azimuth, elevation)

Unit position at `azimuth` and `elevation` [rad] in the wind frame (apparent downwind,
crosswind towards positive azimuth, up).
"""
sphere_position(azimuth, elevation) =
    (cos(elevation) * cos(azimuth), cos(elevation) * sin(azimuth), sin(elevation))

"""
    PatternProblem

Choice of the flight pattern for one condition: the kite, its tether force limit [N],
the lowest tether elevation [rad], the uniform apparent wind speed [m/s], the ship's
course as an azimuth in the wind frame [rad] and the weight of side force against
thrust. Called on the pattern parameters, it returns the objective to minimise.
"""
struct PatternProblem
    model::KiteModel
    max_tension::Float64
    min_elevation::Float64
    wind_speed::Float64
    course::Float64
    side_weight::Float64
end

"""
    pattern_of(parameters)

[`SteeringPattern`](@ref) from the optimisation `parameters`: centre and half width of
the roll angle, heading and angle of attack [rad].
"""
pattern_of(parameters) = SteeringPattern(parameters[1], abs(parameters[2]),
    abs(parameters[3]), parameters[4])

"""
    flight_pattern(model, parameters)

Pattern of the kind `model` flies from the four optimisation `parameters`.
"""
flight_pattern(model::KiteModel, parameters) =
    model.flies_loops ? LoopPattern(parameters...) : pattern_of(parameters)

"""
    outside_limits(model, pattern)

How far [rad] `pattern` lies outside what `model` can fly, zero where it lies inside.
"""
function outside_limits(model::KiteModel, pattern::SteeringPattern)
    return max(model.lowest_angle - pattern.angle_of_attack,
        pattern.angle_of_attack - model.stall_angle, 0.0) +
           max(MIN_HALF_WIDTH - pattern.half_width, pattern.heading - MAX_HEADING, 0.0)
end

function outside_limits(model::KiteModel, pattern::LoopPattern)
    smallest = asin(min(model.min_turn_radius / model.tether_length, 1.0))
    return max(model.lowest_angle - pattern.angle_of_attack,
        pattern.angle_of_attack - model.stall_angle, 0.0) +
           max(smallest - pattern.cone, pattern.cone - MAX_CONE, 0.0) +
           max(-pattern.axis_off_wind, pattern.axis_off_wind + pattern.cone - π / 2, 0.0)
end

"""
    objective(problem, force)

Minus the thrust along the course plus the weighted side force across it, over the
tether force limit; `Inf` where the kite cannot fly.
"""
function objective(problem::PatternProblem, force::PatternForce)
    isfinite(force.peak_tension) || return Inf
    load = 0.5problem.model.air_density * problem.wind_speed^2 * problem.model.area
    downwind, crosswind, _ = load .* force.force
    thrust = downwind * cos(problem.course) + crosswind * sin(problem.course)
    side = -downwind * sin(problem.course) + crosswind * cos(problem.course)
    return -(thrust - problem.side_weight * abs(side)) / problem.max_tension
end

function (problem::PatternProblem)(parameters)
    (; model) = problem
    pattern = flight_pattern(model, parameters)
    outside = outside_limits(model, pattern)
    outside > 0 && return 10 + 100outside
    force = PatternForce(model, pattern, problem.wind_speed, problem.max_tension)
    isfinite(force.peak_tension) || return 10.0
    low = max(problem.min_elevation - force.lowest_elevation, 0.0)
    low > 0 && return 10 + 100low
    return objective(problem, force)
end

"smallest half width of a sweep [rad]"
const MIN_HALF_WIDTH = deg2rad(2)
"largest heading off the direction towards the edge of the wind window [rad]"
const MAX_HEADING = deg2rad(170)
"largest half angle of a loop's cone [rad]"
const MAX_CONE = deg2rad(40)

"""
    search_starts(problem, starts)

The `starts` worth a search: all of them for a steered kite, whose patterns nearly all fly,
and the best three for a wing, most of whose loops do not.
"""
function search_starts(problem::PatternProblem, starts)
    problem.model.flies_loops || return starts
    return starts[partialsortperm(problem.(starts), 1:min(3, length(starts)))]
end

"""
    optimal_pattern(problem, starts)

Best steered pattern from Nelder-Mead runs from each parameter vector in `starts`, or the
best parked kite when that is better; returns its [`PatternForce`](@ref), `NO_PATTERN`
where nothing flies, and the parameters of the best steered pattern for warm starts.
"""
function optimal_pattern(problem::PatternProblem, starts)
    (; model) = problem
    best_force, best_value, best_parameters = NO_PATTERN, Inf, first(starts)
    for start in search_starts(problem, starts)
        result = Optim.optimize(problem, start, Optim.NelderMead(),
            Optim.Options(iterations=200))
        Optim.minimum(result) < min(best_value, 10) || continue
        parameters = Optim.minimizer(result)
        force = PatternForce(model, flight_pattern(model, parameters), problem.wind_speed,
            problem.max_tension)
        value = objective(problem, force)
        value < best_value || continue
        best_force, best_value, best_parameters = force, value, parameters
    end
    load = 0.5model.air_density * problem.wind_speed^2 * model.area
    for angle in range(model.lowest_angle, model.stall_angle; length=12),
        elevation in deg2rad.(10:5:70), side in (-1, 1)

        force = parked_force(KiteAero(model, angle), elevation, side, problem.wind_speed)
        load * force.peak_tension <= problem.max_tension || continue
        value = objective(problem, force)
        value < best_value || continue
        best_force, best_value = force, value
    end
    return best_force, best_parameters
end

"""
    pattern_starts(course)

Starting [`SteeringPattern`](@ref) parameters for the search: figure eights through the
wind window at the roll angle facing the `course` [rad] and halfway to it, and a slow
sweep along the edge of the window facing the course.
"""
function pattern_starts(course)
    facing = max(π / 2 - course, 0.5)
    halfway = max(π / 2 - course / 2, 0.5)
    return [[facing, 0.4, 1.3, deg2rad(15)], [halfway, 0.1, 1.5, deg2rad(15)],
        [facing, 0.3, 0.3, deg2rad(15)]]
end

"""
    pattern_starts(model, course)

Starting parameters of the search for `model`: [`pattern_starts`](@ref) of the course for a
steered kite, and for a wing, loops on the smallest cone it can turn on and on a wider one,
at axes facing the `course` [rad], halfway to it and straight up, at three distances from
the downwind axis.
"""
function pattern_starts(model::KiteModel, course)
    model.flies_loops || return pattern_starts(course)
    smallest = asin(min(1.1model.min_turn_radius / model.tether_length, 0.9))
    facing = max(π / 2 - course, 0.5)
    halfway = max(π / 2 - course / 2, 0.5)
    return [[roll, off_wind, cone, angle]
            for roll in (facing, halfway, π / 2), off_wind in (0.4, 0.7, 1.0),
                cone in (smallest, 1.3smallest), angle in (model.stall_angle - 0.02, 0.05)][:]
end

"""
    pattern_table(model, max_force, assumptions, wind_speeds, courses, side_weights)

Best pattern force for each apparent wind speed, course and side weight, warm-starting
each speed from the previous one. A kite seen before reuses its table: from this
session, or from the disk cache in output/pattern_tables/, keyed by every field of the
kite model and the source of this file, so that a change to either computes the tables
afresh.
"""
function pattern_table(model::KiteModel, max_force, assumptions::Assumptions, wind_speeds,
        courses, side_weights)
    key = ((getfield(model, name) for name in fieldnames(KiteModel) if name != :polar)...,
        model.polar.angle_of_attack, model.polar.lift, model.polar.drag, max_force,
        assumptions[:kite_min_elevation], wind_speeds, courses, side_weights)
    cached = lock(() -> get(PATTERN_TABLES, key, nothing), PATTERN_LOCK)
    isnothing(cached) || return cached
    path = pattern_table_path(key)
    size = (length(wind_speeds), length(courses), length(side_weights))
    forces = isfile(path) ? read_pattern_table(path, size) :
             compute_pattern_table(model, max_force, assumptions, wind_speeds, courses,
        side_weights)
    isfile(path) || write_pattern_table(path, forces)
    lock(() -> PATTERN_TABLES[key] = forces, PATTERN_LOCK)
    return forces
end

"""
    compute_pattern_table(model, max_force, assumptions, wind_speeds, courses,
                          side_weights)

The table of [`pattern_table`](@ref), optimised pattern by pattern, threaded over the
courses and side weights.
"""
function compute_pattern_table(model::KiteModel, max_force, assumptions::Assumptions,
        wind_speeds, courses, side_weights)
    forces = fill(NO_PATTERN, length(wind_speeds), length(courses), length(side_weights))
    min_elevation = deg2rad(assumptions[:kite_min_elevation])
    cases = vec(collect(Iterators.product(eachindex(courses), eachindex(side_weights))))
    Threads.@threads :greedy for (j, k) in cases
        starts = pattern_starts(model, courses[j])
        for (i, wind_speed) in enumerate(wind_speeds)
            problem = PatternProblem(model, max_force, min_elevation, wind_speed,
                courses[j], side_weights[k])
            forces[i, j, k], best = optimal_pattern(problem, starts)
            starts = vcat([best], pattern_starts(model, courses[j]))
        end
    end
    return forces
end

"""
    pattern_table_path(key)

File of the disk cache for the pattern table of `key`, named by a hash of the key and of
the source of the pattern model.
"""
function pattern_table_path(key)
    source = read(joinpath(@__DIR__, "pattern.jl"), String)
    name = string(hash((key, source)); base=16)
    return joinpath(pkgdir(@__MODULE__), "output", "pattern_tables", name * ".bin")
end

"""
    write_pattern_table(path, forces)

Store `forces` at `path` as five Float64 per pattern: the force, the peak tension and the
lowest elevation.
"""
function write_pattern_table(path, forces)
    mkpath(dirname(path))
    values = [field for force in forces
              for field in (force.force..., force.peak_tension, force.lowest_elevation)]
    temporary = path * ".$(Threads.threadid()).tmp"
    write(temporary, values)
    mv(temporary, path; force=true)
end

"""
    read_pattern_table(path, size)

Pattern table of `size` stored by [`write_pattern_table`](@ref).
"""
function read_pattern_table(path, size)
    values = reinterpret(Float64, read(path))
    forces = [PatternForce((values[5k - 4], values[5k - 3], values[5k - 2]), values[5k - 1],
                  values[5k]) for k in 1:prod(size)]
    return reshape(forces, size)
end

"pattern tables already computed in this session, by kite and table grid"
const PATTERN_TABLES = Dict{Any, Array{PatternForce, 3}}()
const PATTERN_LOCK = ReentrantLock()
