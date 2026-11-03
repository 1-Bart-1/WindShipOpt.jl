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
down to and stalls at [rad], and the smallest radius it can turn on through the air [m].
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
    steering_residual(kite, wind, radial, heading, turn, tether_length, airspeed)

[`balance_residual`](@ref) of a kite flying through the air at `airspeed` [m/s] along unit
`heading` in the tangent plane of the tether sphere at unit `radial` position, in the
uniform `wind` [m/s], while turning with curvature vector `turn` [1/m]; also returns its
ground velocity [m/s].
"""
function steering_residual(kite::KiteAero, wind, radial, heading, turn, tether_length,
        airspeed)
    radial_wind = dot3(wind, radial)
    ground = wind .- radial_wind .* radial .+ airspeed .* heading
    acceleration = airspeed^2 .* turn .- (dot3(ground, ground) / tether_length) .* radial
    residual, tension = balance_residual(kite, radial_wind .* radial .- airspeed .* heading,
        radial, acceleration)
    return residual, tension, ground
end

"""
    steering_point(kite, wind, radial, heading, turn, tether_length)

Quasi-steady airspeed [m/s], tether tension [N] and ground velocity [m/s] of a kite held
at `heading` (see [`steering_residual`](@ref)), or `nothing` where it cannot fly with a
taut tether.
"""
function steering_point(kite::KiteAero, wind, radial, heading, turn, tether_length)
    dot3(wind, radial) > 0 || return nothing
    residual(airspeed) = steering_residual(kite, wind, radial, heading, turn, tether_length,
        airspeed)
    first(residual(1e-3)) < 0 || return nothing
    low, high = 1e-3, 1.0
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
    limited_point(model, angle, wind, radial, heading, turn, max_tension)

[`steering_point`](@ref) of `model` at angle of attack `angle` [rad], depowered towards
its lowest angle where the tension would exceed `max_tension` [N], keeping the most lift
that stays within the limit.
"""
function limited_point(model::KiteModel, angle, wind, radial, heading, turn, max_tension)
    solve(angle) = steering_point(KiteAero(model, angle), wind, radial, heading, turn,
        model.tether_length)
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
    pattern = pattern_of(parameters)
    (; model) = problem
    outside = max(model.lowest_angle - pattern.angle_of_attack,
        pattern.angle_of_attack - model.stall_angle, 0.0) +
              max(MIN_HALF_WIDTH - pattern.half_width, pattern.heading - MAX_HEADING, 0.0)
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

"""
    optimal_pattern(problem, starts)

Best steered pattern from Nelder-Mead runs from each parameter vector in `starts`; returns
its [`PatternForce`](@ref), `NO_PATTERN` where nothing flies, and its parameters for warm
starts.
"""
function optimal_pattern(problem::PatternProblem, starts)
    (; model) = problem
    best_force, best_value, best_parameters = NO_PATTERN, Inf, first(starts)
    for start in starts
        result = Optim.optimize(problem, start, Optim.NelderMead(),
            Optim.Options(iterations=200))
        Optim.minimum(result) < min(best_value, 10) || continue
        parameters = Optim.minimizer(result)
        force = PatternForce(model, pattern_of(parameters), problem.wind_speed,
            problem.max_tension)
        value = objective(problem, force)
        value < best_value || continue
        best_force, best_value, best_parameters = force, value, parameters
    end
    return best_force, best_parameters
end

"""
    parked_angles(model, depower)

Angles of attack [rad] a parked kite of [`KiteModel`](@ref) `model` can hold: those whose
force coefficient is at least the fraction `depower` of the one just below stall.
"""
function parked_angles(model::KiteModel, depower)
    coefficient(angle) = hypot(KiteAero(model, angle).lift, KiteAero(model, angle).drag)
    least = depower * coefficient(model.stall_angle)
    return [angle for angle in range(model.lowest_angle, model.stall_angle; length=12)
            if coefficient(angle) >= least]
end

"""
    parked_positions(model, angles, max_tension, min_elevation, wind_speed)

Every [`parked_force`](@ref) of `model` at the `angles` of attack [rad], along the edge of
the wind window from `min_elevation` [rad] to overhead on both sides, in a uniform apparent
wind of `wind_speed` [m/s] within the tether limit `max_tension` [N].
"""
function parked_positions(model::KiteModel, angles, max_tension, min_elevation, wind_speed)
    load = 0.5model.air_density * wind_speed^2 * model.area
    forces = [parked_force(KiteAero(model, angle), elevation, side, wind_speed)
              for angle in angles, elevation in deg2rad.(10:5:85), side in (-1, 1)]
    return filter(forces) do force
        load * force.peak_tension <= max_tension && force.lowest_elevation >= min_elevation
    end
end

"""
    parked_table(model, max_force, assumptions, wind_speeds, courses, side_weights)

Force of the best parked position for each apparent wind speed, course and side weight, by
the same [`objective`](@ref) as a flight pattern. A wind speed in which no position holds
takes the force coefficients of the next stronger one.
"""
function parked_table(model::KiteModel, max_force, assumptions::Assumptions, wind_speeds,
        courses, side_weights)
    angles = parked_angles(model, assumptions[:kite_parked_depower])
    min_elevation = deg2rad(assumptions[:kite_min_elevation])
    forces = fill(NO_PATTERN, length(wind_speeds), length(courses), length(side_weights))
    for i in reverse(eachindex(wind_speeds))
        positions = parked_positions(model, angles, max_force, min_elevation,
            wind_speeds[i])
        for j in eachindex(courses), k in eachindex(side_weights)
            problem = PatternProblem(model, max_force, min_elevation, wind_speeds[i],
                courses[j], side_weights[k])
            forces[i, j, k] = isempty(positions) ?
                              forces[min(i + 1, length(wind_speeds)), j, k] :
                              argmin(force -> objective(problem, force), positions)
        end
    end
    return forces
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
        starts = pattern_starts(courses[j])
        for (i, wind_speed) in enumerate(wind_speeds)
            problem = PatternProblem(model, max_force, min_elevation, wind_speed,
                courses[j], side_weights[k])
            forces[i, j, k], best = optimal_pattern(problem, starts)
            starts = vcat([best], pattern_starts(courses[j]))
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
