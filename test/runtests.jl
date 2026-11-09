# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

using Statistics: mean
using Test
using WindShipOpt
using WindShipOpt: correlation_allowance, bulb_resistance, friction_coefficient

# Numerical example of Holtrop & Mennen (1982).
const PAPER_ENV = Environment(; water_density=1025.0, water_viscosity=1.1883e-6)
const PAPER_HULL = Hull(; length=205.0, beam=32.0, draft=10.0, displacement_volume=37500.0,
    midship_coefficient=0.98, waterplane_coefficient=0.75, centre_of_buoyancy=-0.75,
    bulb_area=20.0, bulb_height=4.0, transom_area=16.0, stern_shape=10.0,
    appendage_area=50.0, appendage_form_factor=1.5)

assumptions = Assumptions()
corridors = route_corridors(:caribbean, north_atlantic_mask(); scale=16)

# The study's search is too coarse for the small route differences tested here.
WindShipOpt.ROUTER_SETTINGS[] = WindShipOpt.RouterSettings(time_step=1.5,
    search_speed_stride=2, search_margins=(0.12, 0.2), kite_search_margins=(0.25, 0.5))

@testset "Holtrop components match the published example at 25 kn" begin
    speed = 25KNOT
    coefficients = WaveCoefficients(PAPER_HULL)
    @test wetted_surface(PAPER_HULL) ≈ 7381.45 rtol = 1e-3
    reynolds = speed * 205 / PAPER_ENV.water_viscosity
    @test friction_coefficient(reynolds) ≈ 0.001390 rtol = 2e-3
    @test coefficients.c2 ≈ 0.7595 rtol = 1e-3
    @test coefficients.c5 ≈ 0.9592 rtol = 1e-3
    @test coefficients.m1 ≈ -2.1274 rtol = 1e-3
    @test coefficients.lambda ≈ 0.6513 rtol = 1e-3
    @test bulb_resistance(PAPER_HULL, PAPER_ENV, speed) ≈ 49.0 rtol = 0.05
    @test correlation_allowance(PAPER_HULL, coefficients) ≈ 0.000352 rtol = 5e-3
end

# The 3830 t Damen Combi Freighter 3850 makes 11.8 kn on 1104 kW.
@testset "coaster resistance and power are in the range of real coasters" begin
    ship = Ship(ShipDesign(:vlsfo, 85.0), assumptions)
    effective_power = resistance(ship.hull, ship.env, 11KNOT) * 11KNOT
    @test 350e3 < effective_power < 800e3
    @test 700 < ship.powertrain.installed_power / 1e3 < 1500
end

@testset "hull wind load follows Blendermann's loading functions" begin
    env = Environment(assumptions)
    windage = WindShipOpt.Windage("vehicle carrier", 180.0, 30.0, 0.0, assumptions)
    @test windage.lateral_area ≈ 4584.16 && windage.frontal_area ≈ 811.68
    load = 0.5env.air_density * 100.0
    head = WindShipOpt.wind_force(windage, env, 0.0, 0.0, 10.0)
    @test head.thrust ≈ -load * 0.55 * windage.frontal_area
    @test head.side ≈ 0 atol = 1e-6
    beam = WindShipOpt.wind_force(windage, env, 10.0, π / 2, 0.0)
    @test beam.side ≈ load * 0.95 * windage.lateral_area
    @test beam.heeling_moment ≈ beam.side * 1.2 * 12.56
    @test beam.yaw_moment ≈ beam.side * -8.98
end

@testset "container tiers above the measured ship's add to its windage" begin
    measured = WindShipOpt.wind_load_types()["container"]
    alone = WindShipOpt.Windage("container", 2measured.length, 2measured.beam,
        2measured.deck_tiers, assumptions)
    stacked = WindShipOpt.Windage("container", 2measured.length, 2measured.beam,
        2measured.deck_tiers + 2, assumptions)
    @test alone.lateral_area ≈ 4measured.lateral_area
    @test alone.frontal_area ≈ 4measured.frontal_area
    added = 2assumptions[:container_tier_height]
    @test stacked.frontal_area - alone.frontal_area ≈ 2measured.beam * added
    @test stacked.lateral_area - alone.lateral_area ≈
          assumptions[:container_stowage_fraction] * 2measured.length * added
    @test stacked.centre_height > alone.centre_height
    @test stacked.centre_position * stacked.lateral_area ≈
          alone.centre_position * alone.lateral_area
end

@testset "wind on the hull costs leeway and adds to the rig's side force" begin
    class = ship_classes()["PCTC car carrier"]
    bare = Ship(ShipDesign(:vlsfo, class), assumptions)
    calm = WindShipOpt.required_thrust(bare, 7.0, 0.0, 0.0, WindShipOpt.NO_RIG_FORCE)
    beam = WindShipOpt.required_thrust(bare, 7.0, 15.0, π / 2, WindShipOpt.NO_RIG_FORCE)
    @test beam > calm
    hull_force = WindShipOpt.wind_force(bare.windage, bare.env, 15.0, π / 2, 7.0)
    rig = RigForce(0.0, 2e5, 2e6, 0.0)
    together = WindShipOpt.HullBalance(bare, 7.0, rig + hull_force)
    @test together.leeway > WindShipOpt.HullBalance(bare, 7.0, rig).leeway
    @test WindShipOpt.required_thrust(bare, 7.0, 15.0, π / 2, rig) ≈
          WindShipOpt.resistance(bare.hull, bare.env, 7.0;
              coefficients=bare.wave_coefficients) + together.drag - hull_force.thrust
end

# DNV Rules for Ships, January 2000, Pt. 3 Ch. 3 Sec. 2, guidance note, p. 9.
@testset "rudder area follows the DNV 2000 guidance and grows with block coefficient" begin
    hull = Hull(85.0, assumptions)
    @test (hull.length, hull.beam, hull.draft) == (85.0, 13.2, 5.5)
    @test WindShipOpt.block_coefficient(hull) ≈ 0.83
    @test WindShipOpt.rudder_area(hull) ≈ 8.56 atol = 0.005
    @test WindShipOpt.rudder_area(Hull(85.0, 13.2, 5.5, 0.60, assumptions)) <
          WindShipOpt.rudder_area(hull)
end

# Mittendorf et al. (2022), Fig. 3: C_AW of C_B ≥ 0.70 hulls peaks at ~5-10 in head waves
# near λ/L = 1-1.3 and stays within about ±2 in following waves.
@testset "SNNM added resistance has the measured head and following wave magnitudes" begin
    env = Environment(assumptions)
    seakeeping = SeakeepingHull(Hull(85.0, assumptions), assumptions)
    coefficient(ratio, heading) = added_resistance_coefficient(seakeeping, env, 10KNOT,
        sqrt(2π * env.gravity / (ratio * 85.0)), heading)
    head_peak = maximum(coefficient(ratio, π) for ratio in 0.8:0.05:1.5)
    @test 5 < head_peak < 10
    @test all(abs(coefficient(ratio, 0.0)) < 2 for ratio in 0.3:0.1:3.0)
end

# Without mass the quasi-steady kite carries ½ρA C_R v_r² (1 + G²) for the radial wind
# speed v_r (Loyd 1980, no reeling).
@testset "massless steered kite matches the crosswind tether force" begin
    kite = WindShipOpt.KiteAero(100.0, 1.0, 0.2, 0.0, 1.225, 9.81)
    elevation = deg2rad(25)
    radial = (cos(elevation), 0.0, sin(elevation))
    heading = (0.0, 1.0, 0.0)
    _, tension, _ = WindShipOpt.steering_point(kite, (10.0, 0.0, 0.0), radial, heading,
        (0.0, 0.0, 0.0), Inf)
    radial_wind = 10.0 * cos(elevation)
    crosswind_tension = 0.5 * 1.225 * 100.0 * hypot(1.0, 0.2) * radial_wind^2 * (1 + 25)
    @test tension ≈ crosswind_tension rtol = 1e-6
end

"""
    best_pattern_path(model, max_force, assumptions, course)

The steps of the best steered cycle of the kite `model` in a 12 m/s apparent wind on
`course` [rad].
"""
function best_pattern_path(model, max_force, assumptions, course)
    problem = WindShipOpt.PatternProblem(model, max_force,
        deg2rad(assumptions[:kite_min_elevation]), 12.0, course, 0.0)
    _, parameters = WindShipOpt.optimal_pattern(problem, WindShipOpt.pattern_starts(course))
    path = WindShipOpt.PatternStep[]
    WindShipOpt.PatternForce(model, WindShipOpt.pattern_of(parameters), 12.0, max_force;
        path)
    return path
end

@testset "steps of a flown cycle give the pattern's force and peak" begin
    soft, soft_force, _ = WindShipOpt.kite_model(800.0, 3.0, assumptions)
    rigid, rigid_force, = WindShipOpt.rigid_kite_model(54.0, 1, assumptions)
    steered = WindShipOpt.SteeringPattern(π / 2, 0.4, 1.3, deg2rad(15))
    loop = WindShipOpt.LoopPattern(π / 2, 0.8, 0.3, deg2rad(8))
    for (model, max_force, pattern, wind) in
        ((soft, soft_force, steered, 12.0), (rigid, rigid_force, loop, 30.0))
        path = WindShipOpt.PatternStep[]
        force = WindShipOpt.PatternForce(model, pattern, wind, max_force; path)
        load = 0.5model.air_density * wind^2 * model.area
        period = sum(step.time for step in path)
        pull_along(axis) = sum(step.tension * step.time * step.radial[axis]
        for step in path)
        pull = ntuple(pull_along, 3)
        @test all(pull ./ (period * load) .≈ force.force)
        @test maximum(step.tension for step in path) ≈ force.peak_tension * load
        @test maximum(step.tension for step in path) <= max_force
    end
end

"least angle [rad] of a pattern's `path` off the apparent downwind direction"
least_off_wind(path) = minimum(acos(first(step.radial)) for step in path)

# A sweep keeps the kite in the outer half of the wind window, more than 45° off the
# apparent downwind direction; a figure eight crosses the window's centre.
@testset "upwind the kite sweeps along the window edge, downwind it flies eights" begin
    model, max_force, _ = WindShipOpt.kite_model(800.0, 3.0, assumptions)
    upwind = best_pattern_path(model, max_force, assumptions, deg2rad(120))
    @test least_off_wind(upwind) > π / 4
    downwind = best_pattern_path(model, max_force, assumptions, 0.0)
    @test least_off_wind(downwind) < π / 4
end

@testset "a heavy wing flies crosswind though it cannot hang at rest" begin
    wing = WindShipOpt.KiteAero(60.0, 1.25, 0.15, 1500.0, 1.225, 9.81)
    off_wind, wind = 1.3, (14.0, 0.0, 0.0)
    radial = WindShipOpt.window_position(off_wind, π / 2)
    heading = (0.0, -1.0, 0.0)
    still = (0.0, 0.0, 0.0)
    @test first(WindShipOpt.steering_residual(wing, wind, radial, heading, still, 300.0,
        1e-3)) > 0
    airspeed, tension, _ = WindShipOpt.steering_point(wing, wind, radial, heading, still,
        300.0)
    @test airspeed > 15 && tension > 0
end

@testset "heavier canopy cloth raises the minimum flight wind" begin
    light, heavy = (with_value(assumptions, :canopy_cloth_weight, weight)
                    for weight in (40.0, 160.0))
    light_wind, heavy_wind = (
        WindShipOpt.min_flight_wind(first(WindShipOpt.kite_model(800.0, 3.0, cloth)), cloth)
        for cloth in (light, heavy))
    @test heavy_wind > light_wind
end

@testset "a kite built for more force is heavier and dearer at the same life" begin
    stronger = with_value(assumptions, :kite_max_force_per_area, 1.0)
    @test WindShipOpt.cloth_weight(assumptions) == 200
    @test WindShipOpt.cloth_weight(stronger) ≈ 200 * 2^0.27
    base_canopy, strong_canopy = WindShipOpt.Canopy.((assumptions, stronger))
    @test strong_canopy.mass_per_area > base_canopy.mass_per_area
    @test strong_canopy.cost_per_area > base_canopy.cost_per_area
    @test strong_canopy.lifetime == base_canopy.lifetime
    base_model, _, base_tether = WindShipOpt.kite_model(800.0, 3.0, assumptions)
    strong_model, _, strong_tether = WindShipOpt.kite_model(800.0, 3.0, stronger)
    @test strong_model.mass > base_model.mass
    @test strong_tether ≈ sqrt(2) * base_tether
end

@testset "the control unit weighs in proportion to the tether force limit" begin
    extra = with_value(assumptions, :control_unit_mass_per_force,
        assumptions[:control_unit_mass_per_force] + 0.1)
    for area in (800.0, 3200.0)
        base, max_force, _ = WindShipOpt.kite_model(area, 3.0, assumptions)
        heavier = first(WindShipOpt.kite_model(area, 3.0, extra))
        @test heavier.mass - base.mass ≈ 0.1e-3max_force
    end
end

@testset "canopy life is the goal input, whatever the cloth weight" begin
    @test WindShipOpt.Canopy(assumptions).lifetime == 3000
    @test assumptions[:canopy_cloth_weight] == 200
    goal = with_value(assumptions, :canopy_life, 1200.0)
    @test WindShipOpt.Canopy(goal).lifetime == 1200
    @test WindShipOpt.Canopy(with_value(goal, :canopy_cloth_weight, 60.0)).lifetime == 1200
end

@testset "hulls fuller than Holtrop's range use the formulas at its limit" begin
    env = Environment(assumptions)
    classes = ship_classes()
    uncapped = with_value(assumptions, :holtrop_max_prismatic, 1.0)
    full = classes["Kamsarmax bulk carrier"]
    capped_hull, free_hull = (Hull(full, values) for values in (assumptions, uncapped))
    @test WindShipOpt.prismatic_coefficient(capped_hull) == 0.85
    @test WindShipOpt.prismatic_coefficient(free_hull) ≈ 0.88 / 0.99
    # the true displacement stays, and the calibration still meets the source design
    @test capped_hull.displacement_volume == free_hull.displacement_volume
    service = full.service_speed * WindShipOpt.KNOT
    @test resistance(capped_hull, env, service) ≈ resistance(free_hull, env, service)
    @test capped_hull.resistance_factor > free_hull.resistance_factor
    # less of the excess wave resistance at service speed means more resistance when slow
    slow = 0.7service
    @test resistance(capped_hull, env, slow) > 1.05resistance(free_hull, env, slow)
    # a class inside the range does not move
    inside = classes["VLCC"]
    @test resistance(Hull(inside, assumptions), env, 6.0) ==
          resistance(Hull(inside, uncapped), env, 6.0)
end

# Tillig & Ringsberg (2020) give a lift coefficient of about 9.5 at spin ratio 3.
@testset "rotor coefficients reproduce the ShipCLEAN lift at spin ratio 3" begin
    lift, drag, power = WindShipOpt.rotor_coefficients(3.0)
    @test lift ≈ 9.5 atol = 0.1
    @test 2 < drag < 3
    @test 0 < power < 0.5
end

"""
    uniform_kite(hull, assumptions)

800 m^2 kite whose pattern table holds one force everywhere, towing from the launch mast.
"""
function uniform_kite(hull, assumptions)
    pattern = WindShipOpt.PatternForce((0.3, 0.8, 0.2), 1.0, 0.3)
    return KiteRig(; area=800.0, tether_diameter=0.05, tether_length=300.0,
        reference_height=120.0, max_wind=30.0, min_flight_wind=4.0, launch_min_wind=5.0,
        launch_max_wind=17.0,
        launch_max_wave_height=assumptions[:kite_launch_max_wave_height],
        night_launch=assumptions[:kite_night_launch] > 0, landing_max_wind=20.0,
        landing_max_wave_height=assumptions[:kite_landing_max_wave_height], max_force=1e6,
        attach_height=10.0,
        attach_position=WindShipOpt.launch_mast_position(hull, assumptions),
        wind_speeds=collect(3.0:3.0:30.0), courses=deg2rad.(0.0:15.0:180.0),
        side_weights=[0.0, 1.0], forces=fill(pattern, 10, 13, 2))
end

"""
    kite_coaster(; kwargs...)

Route table of an 85 m e-methanol coaster towed by a [`uniform_kite`](@ref), with inputs of
`assumptions` changed by `kwargs`, and hourly cost and fuel price as router prices.
"""
function kite_coaster(; kwargs...)
    inputs = foldl((case, input) -> with_value(case, first(input), last(input)), kwargs;
        init=assumptions)
    bare = Ship(ShipDesign(:methanol, 85.0), inputs)
    kite = uniform_kite(bare.hull, inputs)
    ship = WindShipOpt.with_rig(bare, kite)
    table = RouteTable(PerformanceTable(ship, inputs))
    return table, (; fuel=ship.fuel.price, time=500.0)
end

"""
    kite_point(table, wave_height, hours; speed_index=6, headwind=12.0, daylight=true)

[`SailedPoint`](@ref) of `hours` [h] at routing speed number `speed_index` in a 12 m/s wind
across the ship with `headwind` [m/s] from ahead and waves of `wave_height` [m].
"""
function kite_point(table, wave_height, hours; speed_index=6, headwind=12.0, daylight=true)
    condition = WindShipOpt.SeaCondition(table.table, 12.0, π / 2, wave_height, 8.0,
        π / 2)
    sample = WindShipOpt.EdgeSample(condition, headwind, 0.0, daylight)
    held, flown, stowed, same_through = WindShipOpt.held_speed(table, speed_index, sample)
    return WindShipOpt.SailedPoint(sample, held, flown, stowed, hours, same_through)
end

"""
    lowest_steady_wind(model, radial, heading)

Lowest apparent wind [m/s], by bisection, in which `model` holds a straight steady flight
along `heading` at unit `radial` position at some flying angle of attack.
"""
function lowest_steady_wind(model, radial, heading)
    angles = range(model.lowest_angle, model.stall_angle; length=48)
    flies(wind) = any(angles) do angle
        kite = WindShipOpt.KiteAero(model, angle)
        return !isnothing(WindShipOpt.steering_point(kite, (wind, 0.0, 0.0), radial,
            heading, (0.0, 0.0, 0.0), model.tether_length))
    end
    low, high = 0.1, 20.0
    for _ in 1:30
        middle = (low + high) / 2
        flies(middle) ? (high = middle) : (low = middle)
    end
    return high
end

@testset "the closed forms for the lowest wind match the steady force balance" begin
    model, _, _ = WindShipOpt.kite_model(800.0, 3.0, assumptions)
    elevation = deg2rad(25.0)
    radial = (cos(elevation), 0.0, sin(elevation))
    level = lowest_steady_wind(model, radial, (0.0, 1.0, 0.0))
    @test WindShipOpt.crosswind_min_wind(model, elevation) ≈ level rtol = 0.03
    climbing = lowest_steady_wind(model, radial, (-sin(elevation), 0.0, cos(elevation)))
    @test WindShipOpt.climbing_min_wind(model, elevation) ≈ climbing rtol = 0.03
    @test level < WindShipOpt.static_wind(model.mass, model) < climbing
end

@testset "a heavy kite that cannot hang at rest still flies once moving" begin
    model, _, _ = WindShipOpt.kite_model(800.0, 3.0, assumptions)
    wind = 0.8WindShipOpt.static_wind(model.mass, model)
    kite = WindShipOpt.KiteAero(model, model.stall_angle)
    elevation = deg2rad(25.0)
    point = WindShipOpt.steering_point(kite, (wind, 0.0, 0.0),
        (cos(elevation), 0.0, sin(elevation)), (0.0, 1.0, 0.0), (0.0, 0.0, 0.0),
        model.tether_length)
    @test !isnothing(point) && point[1] > wind
end

@testset "a kite gives force only between table rows that both hold a pattern" begin
    rig = uniform_kite(Hull(140.0, assumptions), assumptions)
    rig.forces[1, :, :] .= Ref(WindShipOpt.NO_PATTERN)
    env = Environment(assumptions)
    force_at(speed) = WindShipOpt.rig_force(rig, env,
        speed / WindShipOpt.wind_at_height(env, 1.0, rig.reference_height), π / 2, 0.0,
        0.0)
    @test force_at(3.9) === WindShipOpt.NO_RIG_FORCE
    @test force_at(5.9) === WindShipOpt.NO_RIG_FORCE
    @test force_at(6.1).thrust != 0
end

@testset "no pattern gives force under the launch wind" begin
    for area in (800.0, 3200.0)
        model, max_force, tether_diameter = WindShipOpt.kite_model(area, 3.0, assumptions)
        tether = WindShipOpt.rope_mass(tether_diameter, model.tether_length, assumptions)
        launch = WindShipOpt.launch_min_wind(model, tether, assumptions)
        @test launch >= WindShipOpt.min_flight_wind(model, assumptions)
        @test launch >= assumptions[:kite_launch_min_wind]
        forces = WindShipOpt.compute_pattern_table(model, max_force, assumptions,
            [launch - 0.5], deg2rad.(0.0:15.0:180.0), [0.0])
        @test all(force -> !isfinite(force.force[1]), forces)
    end
end

@testset "a kite flies a pattern in light wind that pulls the ship along" begin
    model, max_force, _ = WindShipOpt.kite_model(800.0, 3.0, assumptions)
    course = deg2rad(60.0)
    winds = [6.0, 9.0]
    flown = WindShipOpt.compute_pattern_table(model, max_force, assumptions, winds,
        [course], [0.0])
    thrust(force) = force.force[1] * cos(course) + force.force[2] * sin(course)
    @test isfinite(flown[1].peak_tension)
    @test thrust(flown[1]) > 0
end

@testset "a kite launches inside its limits and stays up above its landing limit" begin
    table, prices = kite_coaster()
    launch_sea, stay_sea, over_sea = 2.0, 3.5, 5.5
    passage(points, aloft) = WindShipOpt.kite_passage(table, points, aloft, prices)
    _, launched = passage([kite_point(table, launch_sea, 4.0)], false)
    @test launched.launches == 1
    _, too_rough = passage([kite_point(table, stay_sea, 4.0)], false)
    @test !isfinite(too_rough.cost)
    _, stayed = passage([kite_point(table, stay_sea, 4.0)], true)
    @test isfinite(stayed.cost) && stayed.launches == 0
    down, gone = passage([kite_point(table, over_sea, 4.0)], true)
    @test !isfinite(gone.cost) && isfinite(down.cost) && down.launches == 0
    _, in_gale = passage([kite_point(table, launch_sea, 4.0; headwind=20.0)], false)
    @test !isfinite(in_gale.cost)
    _, kept_up = passage([kite_point(table, launch_sea, 4.0; headwind=20.0)], true)
    @test isfinite(kept_up.cost)
end

@testset "launch and landing give no force while they last and the launch pays both" begin
    table, prices = kite_coaster()
    ship_table = table.table
    @test ship_table.handling_hours ≈
          (1.05 * assumptions[:kite_launch_minutes] +
           assumptions[:kite_landing_minutes]) / 60
    point = kite_point(table, 2.0, 4.0)
    start = WindShipOpt.EdgeTally(0.0, 0.0, 0.0, 0, 0)
    launched = WindShipOpt.aloft_tally(ship_table, start, point, true, prices)
    stayed = WindShipOpt.aloft_tally(ship_table, start, point, false, prices)
    @test launched.flight_hours ≈ 4.0 - ship_table.handling_hours
    @test stayed.flight_hours ≈ 4.0
    @test launched.cost > stayed.cost + ship_table.cycle_cost
    short = kite_point(table, 2.0, ship_table.handling_hours / 2)
    brief = WindShipOpt.aloft_tally(ship_table, start, short, true, prices)
    @test brief.flight_hours ≈ -ship_table.handling_hours / 2
    @test isfinite(brief.cost)
end

@testset "a landing outside the landing limits is charged as forced, and only then" begin
    table, prices = kite_coaster()
    forced = table.table.forced_landing_cost
    passage(points) = first(WindShipOpt.kite_passage(table, points, true, prices))
    calm = kite_point(table, 2.0, 1.0; speed_index=3)
    rising = kite_point(table, 4.5, 1.0; speed_index=3)
    storm = kite_point(table, 5.5, 1.0; speed_index=3)
    gale = kite_point(table, 2.0, 1.0; speed_index=3, headwind=22.0)
    @test isfinite(rising.stowed)
    @test passage([calm]).forced_landings == 0
    @test passage([rising]).forced_landings == 1
    @test passage([gale]).forced_landings == 1
    @test passage([rising]).cost ≈ rising.stowed * 3600 * prices.fuel + forced
    down = passage([calm, rising, storm])
    @test isfinite(down.cost) && down.forced_landings == 0
    @test passage([rising, storm]).forced_landings == 1
end

@testset "with night launches off a kite launches by day and still lands at night" begin
    table, prices = kite_coaster(kite_night_launch=0.0)
    day = kite_point(table, 2.0, 4.0)
    night = kite_point(table, 2.0, 4.0; daylight=false)
    @test WindShipOpt.kite_passage(table, [day], false, prices)[2].launches == 1
    @test !isfinite(WindShipOpt.kite_passage(table, [night], false, prices)[2].cost)
    @test WindShipOpt.kite_passage(table, [night], true, prices)[1].forced_landings == 0
    always, _ = kite_coaster()
    @test WindShipOpt.kite_passage(always, [night], false, prices)[2].launches == 1
    @test WindShipOpt.is_daylight(0.0, 12.0) && !WindShipOpt.is_daylight(180.0, 12.0)
end

"steady 12 m/s northerly over a flat sea"
struct SteadyWind end
WindShipOpt.wind(::SteadyWind, lat, lon, time) = (0.0, -12.0)
WindShipOpt.waves(::SteadyWind, lat, lon, time) = (0.0, 0.0, 0.0)

@testset "a kite aloft is down by the time the ship arrives" begin
    table, prices = kite_coaster()
    corridor, _ = corridors
    leg = route(corridor, table, SteadyWind(), 0.0; time_cost=prices.time,
        first_stage=size(corridor.lat, 1) - 1, first_aloft=true)
    @test leg.flight_hours > 0
    @test leg.flight_hours < leg.duration
    @test leg.launches == 0
end

@testset "cycle cost sums crew, tear, loss, retry, turn and tether bends" begin
    rig = uniform_kite(Hull(140.0, assumptions), assumptions)
    canopy, tether = WindShipOpt.consumable_costs(rig, assumptions)
    control_unit = assumptions[:market_price_factor] *
                   WindShipOpt.rig_price_parts(rig, assumptions).control_unit
    @test WindShipOpt.cycle_cost(rig, assumptions) ≈
          1.05 * (85 + 0.00005canopy + 0.00005 * (canopy + tether + control_unit)) + 130 +
          4 / 400_000 * tether
    @test WindShipOpt.forced_landing_cost(rig, assumptions) ≈
          0.05 * (canopy + tether + control_unit)
    @test WindShipOpt.cycle_cost(nothing, assumptions) == 0
end

@testset "a canopy costs its goal price, and USD 234 as built today" begin
    @test WindShipOpt.canopy_price(assumptions) ≈ 149.8
    @test WindShipOpt.canopy_price_today(assumptions) ≈ 234.4
    cloth = (:canopy_cloth_base_price, :canopy_cloth_price_per_weight)
    today_cloth = WindShipOpt.with_today(assumptions, cloth)
    @test all(today_cloth[name] == assumptions[Symbol(name, :_today)] for name in cloth)
    @test today_cloth[:canopy_making_cost_per_area] ==
          assumptions[:canopy_making_cost_per_area]
    weight = WindShipOpt.cloth_weight(assumptions)
    @test WindShipOpt.sewn_cloth_price(assumptions, weight) ≈ 9.4
    @test WindShipOpt.sewn_cloth_price(today_cloth, weight) ≈ 17.2
    rig = uniform_kite(Hull(140.0, assumptions), assumptions)
    @test first(WindShipOpt.consumable_costs(rig, assumptions)) ≈ 149.8rig.area
end

@testset "a flown kite wears canopy and tether by their lives" begin
    rig = uniform_kite(Hull(140.0, assumptions), assumptions)
    canopy, tether = WindShipOpt.consumable_costs(rig, assumptions)
    flown = WindShipOpt.wear_cost(rig, assumptions)
    @test flown ≈
          canopy / assumptions[:canopy_life] + tether / assumptions[:tether_lifetime]
    shorter = with_value(assumptions, :canopy_life, assumptions[:canopy_life] / 2)
    @test WindShipOpt.wear_cost(rig, shorter) - flown ≈ canopy / assumptions[:canopy_life]
end

# Expected forces are the hand calculation of tab:hand in paper/sections/checks.tex.
@testset "wing force follows true wind, shear and ship speed as worked by hand" begin
    env = Environment(assumptions)
    wings = WingRig(800.0, Hull(140.0, assumptions), assumptions)
    setting = (1.0, WindShipOpt.drag_coefficient(wings, 1.0))
    force(angle) = rig_force(wings, env, 10.0, deg2rad(angle), 5.4, setting)
    @test force(90).thrust ≈ 51756 rtol = 1e-3
    @test force(90).side ≈ 41416 rtol = 1e-3
    @test force(45).thrust ≈ 35138 rtol = 1e-3
    @test force(45).side ≈ 100995 rtol = 1e-3
    @test force(150).thrust ≈ 17228 rtol = 1e-3
    @test force(150).side ≈ -8238 rtol = 1e-3
    @test force(180).thrust ≈ 2048 rtol = 1e-3
    @test force(180).side ≈ -12109 rtol = 1e-3
    @test force(0).thrust < 0 < force(0).side
end

# Expected forces are the hand calculation of tab:hand in paper/sections/checks.tex.
@testset "rotor force and spin power follow the apparent wind as worked by hand" begin
    env = Environment(assumptions)
    rotors = WindShipOpt.RotorRig(400.0, Hull(140.0, assumptions), assumptions)
    beam = rig_force(rotors, env, 10.0, π / 2, 5.4, 3.0)
    @test beam.thrust ≈ 243775 rtol = 1e-3
    @test beam.side ≈ 227311 rtol = 1e-3
    @test beam.power ≈ 118305 rtol = 1e-3
    close_hauled = rig_force(rotors, env, 10.0, π / 4, 5.4, 3.0)
    @test close_hauled.thrust ≈ 131591 rtol = 1e-3
    @test close_hauled.side ≈ 510601 rtol = 1e-3
    broad = rig_force(rotors, env, 10.0, 5π / 6, 5.4, 3.0)
    @test broad.thrust ≈ 91931 rtol = 1e-3
    @test broad.side ≈ -32685 rtol = 1e-3
    @test rig_force(rotors, env, 10.0, 0.0, 5.4, 3.0) == WindShipOpt.UNREACHABLE_RIG_FORCE
end

# Expected forces are the hand calculation of tab:hand in paper/sections/checks.tex.
@testset "kite force turns from the wind's frame onto the course as worked by hand" begin
    env = Environment(assumptions)
    kite = Ship(ShipDesign(:methanol, 140.0; kite_area=800.0), assumptions).rig
    force(wind, angle) = rig_force(kite, env, wind, deg2rad(angle), 5.4, 0.0)
    @test force(5.8751, 26.6411).thrust ≈ -34 atol = 5
    @test force(5.8751, 26.6411).side ≈ 63733 rtol = 1e-3
    @test force(6.6205, 50.2378).thrust ≈ 19482 rtol = 1e-3
    @test force(6.6205, 50.2378).side ≈ 105998 rtol = 1e-3
    @test force(8.82947, 86.695695).thrust ≈ 113451 rtol = 1e-3
    @test force(8.82947, 86.695695).side ≈ 249728 rtol = 1e-3
    @test force(11.161535, 114.227745).thrust ≈ 241072 rtol = 1e-3
    @test force(11.161535, 114.227745).side ≈ 216840 rtol = 1e-3
    @test force(13.802571, 148.57094).thrust ≈ 337744 rtol = 1e-3
    @test force(13.802571, 148.57094).side ≈ 77976 rtol = 1e-3
end

# On the window edge tan(angle off downwind) = G and T = q A sqrt(CL^2 + CD^2).
@testset "massless kite rests where the whole-system glide ratio puts the window edge" begin
    model, _, _ = WindShipOpt.kite_model(800.0, 3.0, assumptions)
    flying = model.polar.lift .> 0
    wing_alone = maximum(model.polar.lift[flying] ./ model.polar.drag[flying])
    best = argmax(model.polar.lift ./ (model.polar.drag .+ model.extra_drag))
    aero = WindShipOpt.KiteAero(model.area, model.polar.lift[best],
        model.polar.drag[best] + model.extra_drag, 0.0, 1.225, 0.0)
    glide = aero.lift / aero.drag
    @test 3.5 < glide < 5 < wing_alone
    angle = atan(glide)
    radial = WindShipOpt.window_position(angle, 0.5)
    towards_edge = (-sin(angle), cos(angle) * cos(0.5), cos(angle) * sin(0.5))
    airspeed, tension, ground = WindShipOpt.steering_point(aero, (12.0, 0.0, 0.0), radial,
        towards_edge, (0.0, 0.0, 0.0), model.tether_length)
    @test airspeed ≈ 12sin(angle) rtol = 1e-4
    @test tension ≈ 70560 * hypot(aero.lift, aero.drag) rtol = 1e-4
    @test WindShipOpt.norm3(ground) < 1e-3
end

"""
    kite_rigs_by_area()

Pairs of area [m^2] and kite rig: 800 m^2 on the full table, and 3200 m^2 on courses
from beam reach to head to wind.
"""
kite_rigs_by_area() =
    ((800.0, Ship(ShipDesign(:methanol, 140.0; kite_area=800.0), assumptions).rig),
    (3200.0, KiteRig(3200.0, 3.0, Hull(140.0, assumptions), assumptions;
        courses=deg2rad.([90.0, 135.0, 150.0, 165.0, 180.0]))))

@testset "no flight pattern pulls beyond the window edge of the system glide ratio" begin
    for (area, rig) in kite_rigs_by_area()
        model, _, _ = WindShipOpt.kite_model(area, 3.0, assumptions)
        edge = atand(WindShipOpt.best_over_angles((lift, drag) -> lift / drag, model))
        flown = filter(force -> isfinite(force.peak_tension), rig.forces)
        @test maximum(atand(hypot(force.force[2], force.force[3]), force.force[1])
                      for force in flown) <= edge
    end
end

"""
    scanned_output(ship, rig, speed, wind, angle, settings)

Least engine output [W] of `ship` carrying `rig` over the trim `settings`.
"""
function scanned_output(ship, rig, speed, wind, angle, settings)
    return minimum(settings) do setting
        force = rig_force(rig, ship.env, wind, angle, speed, setting)
        thrust = WindShipOpt.required_thrust(ship, speed, wind, angle, force)
        return engine_output(ship, speed, (thrust, force))
    end
end

"""
    reachable_spins(rotors, env, speed, wind, angle, steps)

`steps` spin ratios from 0 to 4 that `rotors` can reach in that wind at ship `speed`.
"""
function reachable_spins(rotors, env, speed, wind, angle, steps)
    spins = range(0.0, 4.0; length=steps)
    forces = [rig_force(rotors, env, wind, angle, speed, spin) for spin in spins]
    return [spin for (spin, force) in zip(spins, forces)
            if iszero(spin) || force != WindShipOpt.NO_RIG_FORCE]
end

"""
    wing_settings(rig, steps)

Lift and drag coefficient pairs of `rig` at `steps` lift coefficients attached and `steps`
angles of attack from 25 to 90 degrees stalled.
"""
function wing_settings(rig, steps)
    normal = rig.stalled_drag_coefficient
    attached = [(lift, WindShipOpt.drag_coefficient(rig, lift))
                for lift in range(0.0, rig.max_lift_coefficient; length=steps)]
    stalled = [(normal * sind(angle) * cosd(angle),
                   rig.profile_drag_coefficient + normal * sind(angle)^2)
               for angle in range(25.0, 90.0; length=steps)]
    return [attached; stalled]
end

@testset "wings and rotors pull forward only above their own upwind limit" begin
    env = Environment(assumptions)
    hull = Hull(140.0, assumptions)
    wings = WingRig(800.0, hull, assumptions)
    rotors = WindShipOpt.RotorRig(400.0, hull, assumptions)
    coefficients(::WingRig, setting) = setting
    function coefficients(rig::WindShipOpt.RotorRig, spin_ratio)
        lift, drag, _ = WindShipOpt.rotor_coefficients(spin_ratio)
        return rig.lift_factor * lift, drag
    end
    for rig in (wings, rotors)
        settings = rig === wings ? wing_settings(rig, 201) :
                   reachable_spins(rig, env, 0.0, 10.0, π / 2, 161)
        limit = minimum(settings) do setting
            lift, drag = coefficients(rig, setting)
            return lift > 0 ? atan(drag / lift) : Inf
        end
        thrust(angle, setting) = rig_force(rig, env, 10.0, angle, 0.0, setting).thrust
        @test all(thrust(angle, setting) <= 0
                  for angle in range(0.0, limit - 1e-3; length=20), setting in settings)
        @test any(thrust(limit + deg2rad(1), setting) > 0 for setting in settings)
    end
end

@testset "kite pulls the ship forward only above the upwind limit of its glide ratio" begin
    env = Environment(assumptions)
    for (area, rig) in kite_rigs_by_area()
        model, _, _ = WindShipOpt.kite_model(area, 3.0, assumptions)
        limit = atan(1 / WindShipOpt.best_over_angles(/, model))
        for apparent in deg2rad.(1.0:2.0:(rad2deg(limit) - 2)), wind in (8.0, 12.0, 20.0),
            trim in range(0.0, last(rig.side_weights); length=31)

            @test rig_force(rig, env, wind, apparent, 0.0, trim).thrust <= 0
        end
        @test rig_force(rig, env, 12.0, deg2rad(40), 0.0, 0.0).thrust > 0
    end
end

@testset "kite, wings and rotors push the same way across the ship" begin
    env = Environment(assumptions)
    hull = Hull(140.0, assumptions)
    kite = uniform_kite(hull, assumptions)
    wings = WingRig(800.0, hull, assumptions)
    rotors = WindShipOpt.RotorRig(400.0, hull, assumptions)
    for angle in deg2rad.((45, 90, 110))
        @test rig_force(kite, env, 12.0, angle, 5.4, 0.0).side > 0
        @test rig_force(wings, env, 12.0, angle, 5.4,
            (1.0, WindShipOpt.drag_coefficient(wings, 1.0))).side > 0
        @test rig_force(rotors, env, 12.0, angle, 5.4, 2.0).side > 0
    end
end

@testset "combined rig force is the sum of kite and rotor forces at a fixed trim" begin
    env = Environment(assumptions)
    hull = Hull(140.0, assumptions)
    kite = uniform_kite(hull, assumptions)
    rotors = WindShipOpt.RotorRig(800.0, hull, assumptions)
    combined = WindShipOpt.CombinedRig(kite, rotors)
    sum_force = rig_force(kite, env, 12.0, π / 2, 6.0, 0.5) +
                rig_force(rotors, env, 12.0, π / 2, 6.0, 3.0)
    force = rig_force(combined, env, 12.0, π / 2, 6.0, (0.5, 3.0))
    @test force.power > 0 && force.yaw_moment != 0
    @test all(getfield(force, name) ≈ getfield(sum_force, name)
              for name in fieldnames(RigForce))
end

"""
    engine_output(ship, speed, (thrust, force))

Engine output [W] of `ship` for a required propeller `thrust` [N] and rig `force`, as
`best_trim` weighs a trim; `Inf` for infinite thrust.
"""
function engine_output(ship, speed, (thrust, force))
    isfinite(thrust) || return Inf
    return WindShipOpt.delivered_power(ship.propeller, ship.env, speed, thrust) /
           ship.powertrain.transmission_efficiency + force.power
end

@testset "wings and rotors trim to the least engine output of a fine scan" begin
    speed = 10.5KNOT
    rotors = Ship(ShipDesign(:methanol, 140.0; rotor_area=800.0), assumptions)
    wings = Ship(ShipDesign(:methanol, 140.0; wing_area=1500.0), assumptions)
    for ship in (rotors, wings), wind in (8.0, 14.0), angle in deg2rad.(30:10:170)
        settings = ship === wings ? wing_settings(ship.rig, 4001) :
                   reachable_spins(ship.rig, ship.env, speed, wind, angle, 4001)
        bare = engine_output(ship, speed,
            WindShipOpt.best_trim(ship, nothing, speed, wind, angle))
        scanned = scanned_output(ship, ship.rig, speed, wind, angle, settings)
        trimmed = engine_output(ship, speed,
            WindShipOpt.best_trim(ship, ship.rig, speed, wind, angle))
        @test trimmed <= scanned + 1e-5bare
    end
end

@testset "a kite and the rotors beside it trim jointly to the least engine output" begin
    ship = Ship(ShipDesign(:methanol, 85.0; kite_area=800.0, rotor_area=200.0), assumptions)
    speed = 10.5KNOT
    weights = range(0.0, 3.0; length=31)
    for wind in (10.0, 16.0), angle in deg2rad.(45:15:165)
        spins = reachable_spins(ship.rig.standing, ship.env, speed, wind, angle, 201)
        bare = engine_output(ship, speed,
            WindShipOpt.best_trim(ship, nothing, speed, wind, angle))
        scanned = scanned_output(ship, ship.rig, speed, wind, angle,
            Iterators.product(weights, spins))
        trimmed = engine_output(ship, speed,
            WindShipOpt.best_trim(ship, ship.rig, speed, wind, angle))
        @test trimmed <= scanned + 1e-5bare
    end
end

@testset "a kite's force runs linearly in side weight between its table's weights" begin
    env = Environment(assumptions)
    uniform = uniform_kite(Hull(140.0, assumptions), assumptions)
    weighted = WindShipOpt.PatternForce((0.1, 0.5, 0.2), 1.0, 0.3)
    forces = cat(uniform.forces[:, :, 1], fill(weighted, 10, 13); dims=3)
    kite = KiteRig(; (name => getfield(uniform, name) for name in fieldnames(KiteRig)
                      if name != :forces)..., forces)
    low, high = kite.side_weights[1], kite.side_weights[2]
    at_low = rig_force(kite, env, 12.0, π / 2, 6.0, low)
    at_high = rig_force(kite, env, 12.0, π / 2, 6.0, high)
    middle = rig_force(kite, env, 12.0, π / 2, 6.0, (low + high) / 2)
    @test at_low.thrust != at_high.thrust
    @test middle.thrust ≈ (at_low.thrust + at_high.thrust) / 2
    @test middle.side ≈ (at_low.side + at_high.side) / 2
end

@testset "kite launch mast takes the forward deck from the rotor row" begin
    hull = Hull(140.0, assumptions)
    reserve = WindShipOpt.launch_mast_reserve(assumptions)
    alone = WindShipOpt.RotorRig(800.0, hull, assumptions)
    behind = WindShipOpt.RotorRig(800.0, hull, assumptions; forward_reserve=reserve)
    @test behind.count == alone.count > 1
    @test behind.centre_position ≈ alone.centre_position - reserve / 2
    @test behind.interference_factor < alone.interference_factor
    row_end = behind.centre_position +
              (assumptions[:deck_length_fraction] * hull.length - reserve) / 2
    @test WindShipOpt.launch_mast_position(hull, assumptions) ≈ row_end + reserve / 2
    @test_throws ArgumentError Ship(ShipDesign(:vlsfo, 140.0; wing_area=800.0,
        rotor_area=400.0), assumptions)
end

@testset "deck units stand evenly over their row, centred on it" begin
    hull = Hull(140.0, assumptions)
    reserve = WindShipOpt.launch_mast_reserve(assumptions)
    deck = assumptions[:deck_length_fraction] * hull.length
    for (rig, row_length) in ((WingRig(800.0, hull, assumptions), deck),
        (WindShipOpt.RotorRig(800.0, hull, assumptions; forward_reserve=reserve),
            deck - reserve))
        positions = WindShipOpt.unit_positions(rig, hull, assumptions)
        @test length(positions) == rig.count > 1
        @test sum(positions) / rig.count ≈ rig.centre_position
        @test all(diff(positions) .≈ row_length / rig.count)
    end
    single = WingRig(100.0, hull, assumptions)
    @test WindShipOpt.unit_positions(single, hull, assumptions) == [single.centre_position]
end

@testset "the rudder cancels the yaw moment about the hull's lateral centre" begin
    hull = Hull(140.0, assumptions)
    centre = WindShipOpt.lateral_centre(hull)
    at_centre = WindShipOpt.RigForce(1e5, 2e5, 0.0, 2e5 * centre)
    @test WindShipOpt.rudder_side_force(hull, at_centre) ≈ 0 atol = 1e-6
    at_midship = WindShipOpt.RigForce(1e5, 2e5, 0.0, 0.0)
    rudder = WindShipOpt.rudder_side_force(hull, at_midship)
    @test 2e5 * (0 - centre) + rudder * (-hull.length / 2 - centre) ≈ 0 atol = 1e-3
end

@testset "a kite tows from its bow mast, and towing midship loads the rudder more" begin
    hull = Hull(140.0, assumptions)
    design = ShipDesign(:methanol, 140.0; kite_area=800.0)
    bow = Ship(design, assumptions)
    midship = Ship(design, WindShipOpt.with_value(assumptions, :kite_tow_position, 0.0))
    @test bow.rig.attach_position ≈ WindShipOpt.launch_mast_position(hull, assumptions)
    @test midship.rig.attach_position == 0
    wind_speed, wind_angle, ship_speed = 8.8295, 86.6957, 5.4 # hand check's beam reach
    balance(ship) = WindShipOpt.HullBalance(ship, ship_speed,
        rig_force(ship.rig, ship.env, wind_speed, deg2rad(wind_angle), ship_speed, 1))
    # midship lies 47 m aft of the lateral centre, the bow mast 4 m ahead of it
    @test balance(midship).rudder_lift_coefficient >
          3balance(bow).rudder_lift_coefficient > 0
    @test balance(midship).drag > balance(bow).drag
end

@testset "a rig ship is sized near the bare ship in calm water" begin
    bare = Ship(ShipDesign(:vlsfo, 140.0), assumptions)
    rotors = Ship(ShipDesign(:vlsfo, 140.0; rotor_area=300.0), assumptions)
    @test rotors.powertrain.installed_power ≈ bare.powertrain.installed_power rtol = 0.02
end

@testset "rotor ships pay for the spin power in the routing lookup" begin
    ship = Ship(ShipDesign(:vlsfo, 140.0; rotor_area=300.0), assumptions)
    table = PerformanceTable(ship, assumptions)
    speed, wind, angle = 5.0, 12.0, π / 2
    power = table.rig_power(speed, wind, angle, 0.0)
    @test power > 0
    @test lookup(table, speed, wind, angle).fuel_power ≈
          WindShipOpt.fuel_power(table, speed, table.flown_thrust(speed, wind, angle, 0.0),
              power)
end

@testset "a bare ship's routing fuel adds the waves' resistance, following seas' negative too" begin
    ship = Ship(ShipDesign(:methanol, 140.0), assumptions)
    table = PerformanceTable(ship, assumptions)
    speed, wind, angle, height, period = 2.47, 6.2, 1.0, 5.6, 7.5
    for heading in (0.33, π)
        waves = height^2 * table.wave_resistance(speed, period, heading)
        @test (waves < 0) == (heading < π / 2)
        @test lookup(table, speed, wind, angle, height, period, heading).fuel_power ≈
              WindShipOpt.fuel_power(table, speed,
                  table.flown_thrust(speed, wind, angle, 0.0) + waves, 0.0)
    end
end

@testset "rotors that cannot spin still stand as drag" begin
    ship = Ship(ShipDesign(:vlsfo, 140.0; rotor_area=300.0), assumptions)
    speed = 5.0
    for wind in (22.0, 30.0)
        stopped = rig_force(ship.rig, ship.env, wind, 0.0, speed, 0.0)
        thrust, force = WindShipOpt.best_trim(ship, ship.rig, speed, wind, 0.0)
        @test stopped.thrust < 0
        @test force.thrust ≈ stopped.thrust
    end
end

@testset "fixed rigs cost port time where they block cargo or bridges" begin
    classes = ship_classes()
    rotors(class) = WindShipOpt.RotorRig(800.0, Hull(classes[class], assumptions),
        assumptions)
    port_hours(class) = WindShipOpt.fixed_rig_port_hours(rotors(class), classes[class],
        assumptions)
    @test port_hours("Panamax container ship") == Inf
    @test port_hours("Kamsarmax bulk carrier") > port_hours("Ultramax bulk carrier") > 0
    @test port_hours("VLCC") == 0
    @test WindShipOpt.fixed_rig_port_hours(nothing, classes["VLCC"], assumptions) == 0
end

@testset "a volume-limited ship's cargo ignores rig mass below the mass limit" begin
    teu = WindShipOpt.CargoUnit(:teu, assumptions)
    feeder(rig_mass) = WindShipOpt.CargoHold(21000.0, 21000.0 - rig_mass, 1600.0, teu)
    full = 1600 * teu.cargo
    @test WindShipOpt.cargo_mass(feeder(0.0)) ≈ full
    @test WindShipOpt.cargo_mass(feeder(500.0)) ≈ full
    @test WindShipOpt.cargo_mass(feeder(5000.0)) ≈ 16000 / teu.mass * teu.cargo
    tonne = WindShipOpt.CargoUnit(:tonne, assumptions)
    bulk = WindShipOpt.CargoHold(21000.0, 20500.0, Inf, tonne)
    @test WindShipOpt.cargo_mass(bulk) ≈ 20500
end

@testset "bulk carriers, tankers and the Megamax fill their deadweight first" begin
    classes = ship_classes()
    hold(name) = WindShipOpt.CargoHold(Ship(ShipDesign(:vlsfo, classes[name]),
            assumptions), assumptions)
    limit(name) = WindShipOpt.cargo_limit(classes[name], assumptions)
    @test all(limit(name) == :deadweight for name in ("general cargo coaster", "VLCC",
        "Kamsarmax bulk carrier", "MR product tanker", "Megamax container ship"))
    @test all(limit(name) == :space for name in ("feeder container ship",
        "Neo-Panamax container ship", "PCTC car carrier"))
    megamax = WindShipOpt.unit_limits(hold("Megamax container ship"))
    @test 0.9 < megamax.deadweight / megamax.space < 1
end

@testset "empty boxes take container slots and tare but carry no cargo" begin
    teu = WindShipOpt.CargoUnit(:teu, assumptions)
    loaded = 1 - assumptions[:empty_container_share]
    @test teu.cargo ≈ loaded * assumptions[:cargo_per_teu]
    @test teu.mass - teu.cargo ≈ assumptions[:teu_tare_mass]
end

@testset "a class ship's drive delivers the shaft power of its source engine" begin
    class = ship_classes()["feeder container ship"]
    shaft = 1e3class.power * assumptions[:shaft_efficiency]
    for drive in (:vlsfo, :methanol, :ammonia)
        powertrain = Ship(ShipDesign(drive, class), assumptions).powertrain
        output = powertrain.installed_power - powertrain.hotel_load
        @test output * powertrain.transmission_efficiency ≈ shaft
    end
end

@testset "a class hull's calm-water delivered power at service speed matches its \
          source design" begin
    for class in values(ship_classes())
        isnan(class.source_load) && continue
        ship = Ship(ShipDesign(:vlsfo, class), assumptions)
        speed = class.service_speed * KNOT
        thrust = resistance(ship.hull, ship.env, speed)
        source = 1e3class.power * class.source_load * assumptions[:shaft_efficiency] /
                 (1 + assumptions[:source_sea_margin])
        delivered = delivered_power(ship.propeller, ship.env, speed, thrust)
        @test delivered ≈ source rtol = 1e-6
    end
end

@testset "a class ship's table reaches its service speed in calm water, and an infeasible \
          knot stays infeasible next to it" begin
    for class in values(ship_classes())
        table = PerformanceTable(Ship(ShipDesign(:vlsfo, class), assumptions), assumptions)
        speed = class.service_speed * KNOT
        @test isfinite(lookup(table, speed, 0.0, 0.0).fuel_power)
        next_to_infeasible = 1e-3WindShipOpt.INFEASIBLE_THRUST
        @test isinf(WindShipOpt.fuel_power(table, speed, next_to_infeasible, 0.0))
    end
end

@testset "an ammonia ship's tank volume and mass follow its largest leg" begin
    class = ship_classes()["feeder container ship"]
    ship = Ship(ShipDesign(:ammonia, class), assumptions)
    leg = 2e12
    store = WindShipOpt.fuel_store(ship, leg, assumptions)
    fuel = assumptions[:fuel_reserve_factor] * leg / ship.fuel.heating_value
    @test store.volume ≈ fuel / assumptions[:ammonia_tank_volumetric_density]
    @test store.mass ≈ fuel / assumptions[:ammonia_tank_gravimetric_density] / 1e3
    @test WindShipOpt.fuel_store(ship, 2leg, assumptions).volume ≈ 2store.volume
    hold = ShipCosts(ship, assumptions).hold
    carried = WindShipOpt.cargo_mass(hold, store.mass, store.volume) / hold.unit.cargo
    @test hold.slots - carried ≈ store.volume / hold.unit.volume
    vlsfo = Ship(ShipDesign(:vlsfo, class), assumptions)
    @test WindShipOpt.fuel_store(vlsfo, leg, assumptions).volume == 0
end

@testset "an ammonia ship pays for its pilot oil and emits only its pilot's CO2" begin
    pilot = assumptions[:ammonia_pilot_share]
    oil = Ship(ShipDesign(:vlsfo, 140.0), assumptions).fuel
    ammonia = Ship(ShipDesign(:ammonia, 140.0), assumptions).fuel
    @test ammonia.carbon_intensity ≈ pilot * oil.carbon_intensity
    @test ammonia.price ≈
          (1 - pilot) * 1e-9assumptions[:e_ammonia_price] + pilot * oil.price
end

"""
    wing_coaster_routing()

Caribbean outbound corridor at scale 16 with the route table and hourly cost of an 85 m
e-methanol coaster with 400 m^2 of wings.
"""
function wing_coaster_routing()
    corridor, _ = corridors
    ship = Ship(ShipDesign(:methanol, 85.0; wing_area=400.0), assumptions)
    table = RouteTable(PerformanceTable(ship, assumptions))
    return corridor, table,
    first(WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions), assumptions))
end

corridor, table, hourly = wing_coaster_routing()

"""
    trip_with_share(design, name, share, base=assumptions)

Round trip of `design` in synthetic weather with the input `name` of `base` at `share`.
"""
function trip_with_share(design, name, share, base=assumptions)
    changed = with_value(base, name, share)
    return round_trip(Ship(design, changed), corridors..., SyntheticWeather(),
        [24.0 * 31, 24.0 * 200], changed)
end

@testset "a longer span at the same area costs the same to buy, fly and launch" begin
    base = uniform_kite(Hull(140.0, assumptions), assumptions)
    ratio = 8 / 3
    slender = KiteRig(; (name => getfield(base, name) for name in fieldnames(KiteRig))...,
        tether_length=base.tether_length * sqrt(ratio))
    prices = WindShipOpt.base_aspect_ratio_prices(assumptions, ratio)
    @test WindShipOpt.rig_price_parts(slender, prices) ==
          WindShipOpt.rig_price_parts(base, assumptions)
    @test WindShipOpt.wear_cost(slender, prices) ≈ WindShipOpt.wear_cost(base, assumptions)
    @test WindShipOpt.cycle_cost(slender, prices) ≈
          WindShipOpt.cycle_cost(base, assumptions)
    @test WindShipOpt.handling_hours(slender, prices) ==
          WindShipOpt.handling_hours(base, assumptions)
end

@testset "kite inputs give the SkySails kites at their projected areas" begin
    @test WindShipOpt.launch_mast_height(125.0, assumptions) ≈ 15.0 rtol = 0.05
    small, = WindShipOpt.kite_model(125.0, 3.0, assumptions)
    @test small.min_turn_radius ≈ 45.0 rtol = 0.05
    large, = WindShipOpt.kite_model(250.0, 3.0, assumptions)
    @test large.tether_length ≈ 360.0 rtol = 0.05
end

@testset "a kite at a fractional aspect ratio flies its own polar" begin
    lower, base = WindShipOpt.KitePolar(2.5), WindShipOpt.KitePolar(3)
    alpha = deg2rad(8.0)
    @test WindShipOpt.polar_value(lower, lower.lift, alpha) <
          WindShipOpt.polar_value(base, base.lift, alpha)
    @test all(>(0), lower.drag)
end

@testset "recalibrated flight drag keeps the base kite's glide ratio" begin
    drag = WindShipOpt.recalibrated_flight_drag(2.5, 3.0, assumptions)
    recalibrated = WindShipOpt.with_value(assumptions, :kite_flight_drag, drag)
    @test drag < assumptions[:kite_flight_drag]
    @test WindShipOpt.total_drag_at_lift(2.5, 0.8, recalibrated) ≈
          WindShipOpt.total_drag_at_lift(3.0, 0.8, assumptions)
    @test WindShipOpt.recalibrated_flight_drag(3.0, 3.0, assumptions) ≈
          assumptions[:kite_flight_drag]
end

@testset "launch cost at the loss goal is mostly crew and turn" begin
    kite = Ship(ShipDesign(:methanol, 140.0; kite_area=800.0), assumptions).rig
    crew_and_turn = (1 + assumptions[:kite_launch_retry_probability]) *
                    assumptions[:kite_cycle_crew_cost] +
                    assumptions[:kite_cycle_course_cost]
    @test crew_and_turn < WindShipOpt.cycle_cost(kite, assumptions) < 1.2crew_and_turn
end

@testset "a rig out of service keeps its cost and saves no fuel while down" begin
    bare_trip = round_trip(Ship(ShipDesign(:methanol, 85.0), assumptions), corridors...,
        SyntheticWeather(), [24.0 * 31, 24.0 * 200], assumptions)
    for (design, name) in ((ShipDesign(:methanol, 85.0; wing_area=400.0),
            :wing_out_of_service),
        (ShipDesign(:methanol, 85.0; rotor_area=200.0), :rotor_out_of_service),
        (ShipDesign(:methanol, 85.0; kite_area=800.0), :kite_out_of_service))
        low, high, down = [trip_with_share(design, name, share)
                           for share in (0.1, 0.5, 1.0)]
        @test low.fuel_energy < high.fuel_energy < down.fuel_energy
        @test low.cost_per_tonne_km < high.cost_per_tonne_km < down.cost_per_tonne_km
        @test down.cost_per_tonne_km > bare_trip.cost_per_tonne_km
        @test down.fuel_energy >= 0.999bare_trip.fuel_energy
        @test down.launches == 0
    end
end

@testset "a kite out of service sails as a bare ship at the same price of time" begin
    outbound, inbound = corridors
    bare = Ship(ShipDesign(:methanol, 85.0), assumptions)
    changed = with_value(assumptions, :kite_out_of_service, 1.0)
    kite = Ship(ShipDesign(:methanol, 85.0; kite_area=800.0), changed)
    states = WindShipOpt.service_states(kite.rig, changed)
    @test first.(states) == [0, 1]
    down = last(last(states))
    hourly = WindShipOpt.leg_time_costs(WindShipOpt.ShipCosts(bare, assumptions),
        assumptions)
    passages = [WindShipOpt.service_passages(ship, outbound, inbound, SyntheticWeather(),
                    [24.0 * 31, 24.0 * 200], assumptions, hourly,
                    24assumptions[:port_time_per_call], Inf, nothing, nothing)
                for ship in (bare, WindShipOpt.with_rig(kite, down))]
    @test first(passages) == last(passages)
    kite_hourly = WindShipOpt.leg_time_costs(WindShipOpt.ShipCosts(kite, changed), changed)
    @test all(kite_hourly .> hourly)
end

@testset "departure costs with the year's ship average to the round trip's cost" begin
    departures = [24.0 * 31, 24.0 * 200]
    for design in (ShipDesign(:methanol, 85.0),
        ShipDesign(:methanol, 85.0; kite_area=800.0))
        trip = round_trip(Ship(design, assumptions), corridors..., SyntheticWeather(),
            departures, assumptions)
        outcomes = trip.departures
        @test getfield.(outcomes, :departure) == departures
        @test mean(getfield.(outcomes, :cost_per_tonne_km)) ≈ trip.cost_per_tonne_km
        @test mean(getfield.(outcomes, :fuel_per_tonne_km)) ≈ trip.fuel_per_tonne_km
        @test allunique(getfield.(outcomes, :fuel_per_tonne_km))
        @test all(0 .<= getfield.(outcomes, :flight_share) .<= 1)
    end
end

@testset "a kite out of service makes and pays launches and forced landings pro rata" begin
    kite = ShipDesign(:methanol, 85.0; kite_area=800.0)
    hard = with_value(assumptions, :kite_landing_max_wind, 0.0)
    cheap = with_value(hard, :kite_forced_landing_loss_probability, 1e-5)
    working = trip_with_share(kite, :kite_out_of_service, 0.0, cheap)
    half = trip_with_share(kite, :kite_out_of_service, 0.5, cheap)
    @test working.forced_landings > 0
    @test half.forced_landings ≈ working.forced_landings / 2
    @test half.launches ≈ working.launches / 2
    dearer = with_value(hard, :kite_forced_landing_loss_probability, 2e-5)
    @test trip_with_share(kite, :kite_out_of_service, 0.5, dearer).cost_per_tonne_km >
          half.cost_per_tonne_km
end

@testset "stopped rotors and feathered wings are only drag in a head wind" begin
    for design in (ShipDesign(:methanol, 85.0; wing_area=400.0),
        ShipDesign(:methanol, 85.0; rotor_area=200.0))
        ship = Ship(design, assumptions)
        down = WindShipOpt.DownRig(ship.rig, 0.0)
        bare_thrust = first(WindShipOpt.best_trim(ship, nothing, 5.0, 10.0, 0.0))
        down_thrust, force = WindShipOpt.best_trim(ship, down, 5.0, 10.0, 0.0)
        @test down_thrust > bare_thrust
        @test force.thrust < 0
        @test force.power == 0
    end
end

@testset "a rig with one unit down keeps its mean capacity and half the force" begin
    ship = Ship(ShipDesign(:methanol, 140.0; rotor_area=800.0), assumptions)
    changed = with_value(assumptions, :rotor_out_of_service, 0.1)
    units = ship.rig.count
    states = WindShipOpt.service_states(ship.rig, changed)
    @test first(first(states)) ≈ 0.9^units
    @test sum(first, states) ≈ 1
    @test first(last(states)) * (1 - last(states)[2].working_share) ≈ 0.1
    half = WindShipOpt.DownRig(ship.rig, 0.5)
    stopped = rig_force(half.rig, ship.env, 10.0, deg2rad(90), 5.0, 0.0)
    spinning = rig_force(half.rig, ship.env, 10.0, deg2rad(90), 5.0, 2.0)
    @test rig_force(half, ship.env, 10.0, deg2rad(90), 5.0, 2.0).thrust ≈
          (stopped.thrust + spinning.thrust) / 2
    kite = Ship(ShipDesign(:methanol, 85.0; kite_area=800.0), assumptions)
    kite_down = last(WindShipOpt.service_states(kite.rig,
        with_value(assumptions, :kite_out_of_service, 0.1)))
    @test isnothing(last(kite_down))
    @test first(kite_down) ≈ 0.1
end

@testset "a kite and the rotors beside it fail independently of each other" begin
    hull = Hull(140.0, assumptions)
    rotors = WindShipOpt.RotorRig(800.0, hull, assumptions)
    rig = WindShipOpt.CombinedRig(uniform_kite(hull, assumptions), rotors)
    changed = with_value(with_value(assumptions, :kite_out_of_service, 0.5),
        :rotor_out_of_service, 0.03)
    states = WindShipOpt.service_states(rig, changed)
    both_up = 0.97^rotors.count
    @test length(states) == 4
    @test sum(first, states) ≈ 1
    @test first(states[1]) ≈ 0.5both_up
    @test first(states[2]) ≈ 0.5both_up
    @test first(states[4]) ≈ 0.5 * (1 - both_up)
    @test states[2][2] === rotors
    @test states[4][2] isa WindShipOpt.DownRig
end

@testset "the store holds the working leg with its reserve, a leg rig-down without" begin
    design = ShipDesign(:methanol, 85.0; rotor_area=200.0)
    cargo(share, reserve) = trip_with_share(design, :rotor_out_of_service, share,
        with_value(assumptions, :fuel_reserve_factor, reserve)).cargo
    @test cargo(0.0, 2.0) < cargo(0.0, 1.1)
    @test cargo(1.0, 2.0) ≈ cargo(1.0, 1.1)
end

@testset "a rig's break-even share lies where its cost curve reaches the level" begin
    shares, costs = [0.0, 0.5, 1.0], [1.0, 2.0, 4.0]
    @test WindShipOpt.share_at_cost(shares, costs, 1.5) ≈ 0.25
    @test WindShipOpt.share_at_cost(shares, costs, 3.0) ≈ 0.75
    @test WindShipOpt.share_at_cost(shares, costs, 0.5) == 0.0
    @test isnan(WindShipOpt.share_at_cost(shares, costs, 5.0))
end

@testset "a canopy price limit lies where the cost reaches the level, and only there" begin
    prices, costs = [75.0, 150.0, 300.0], [1.0, 1.5, 2.5]
    @test WindShipOpt.price_at_cost(prices, costs, 2.0) ≈ 225
    @test isnan(WindShipOpt.price_at_cost(prices, costs, 1.0))
    @test isnan(WindShipOpt.price_at_cost(prices, costs, 3.0))
    @test isnan(WindShipOpt.price_at_cost(prices, costs, NaN))
end

@testset "a canopy life limit lies where the cost reaches the level, and only there" begin
    lives, costs = [4000.0, 1000.0, 2000.0], [1.25, 2.0, 1.5]
    @test WindShipOpt.life_at_cost(lives, costs, 1.75) ≈ 4000 / 3
    @test isnan(WindShipOpt.life_at_cost(lives, costs, 3.0))
    @test isnan(WindShipOpt.life_at_cost(lives, costs, 1.0))
    @test isnan(WindShipOpt.life_at_cost(lives, costs, NaN))
end

@testset "route guided by a cost to go equals the full dynamic programme" begin
    weather, departure = SyntheticWeather(), 24.0 * 31
    (; time_step, search_speed_stride) = WindShipOpt.ROUTER_SETTINGS[]
    workspace = WindShipOpt.RouteWorkspace(size(corridor.lat, 2),
        ceil(Int, 1200 / time_step), size(corridor.lat, 1))
    for coastal_penalty in (0.0, 1.0)
        leg = route(corridor, table, weather, departure; time_cost=hourly, coastal_penalty)
        searched = WindShipOpt.route_pass(workspace, corridor, table, weather, departure;
            time_cost=hourly, time_step, first_stage=1,
            first_lateral=centre_index(corridor), first_aloft=false, coastal_penalty,
            speed_stride=search_speed_stride)
        full = WindShipOpt.final_pass(searched, corridor, table, weather, departure;
            time_cost=hourly, first_stage=1, first_aloft=false, coastal_penalty)
        @test leg.objective == full.objective
        @test leg.path == full.path
    end
end

"""
    HeadSeas(centre, radius, wave_from, height, period)

Calm air with waves of `height` [m] and `period` [s] from `wave_from` [rad] within
`radius` [m] of `centre` (latitude, longitude) [deg], and a flat sea elsewhere.
"""
struct HeadSeas
    centre::NTuple{2, Float64}
    radius::Float64
    wave_from::Float64
    height::Float64
    period::Float64
end

WindShipOpt.wind(::HeadSeas, lat, lon, time) = (0.0, 0.0)
WindShipOpt.waves(seas::HeadSeas, lat, lon, time) =
    WindShipOpt.distance(lat, lon, seas.centre...) < seas.radius ?
    (seas.height, seas.period, seas.wave_from) : (0.0, 0.0, 0.0)

@testset "the ship slows where it cannot hold the commanded speed" begin
    last_stage, centre = size(corridor.lat, 1), centre_index(corridor)
    destination = (corridor.lat[last_stage, centre], corridor.lon[last_stage, centre])
    stage, step = last_stage - 1, WindShipOpt.MAX_LATERAL_STEP + 1
    wave_from = corridor.edge_course[stage, centre, step]
    seas = HeadSeas(destination, 60NAUTICAL_MILE, wave_from, 3.5, 9.0)
    commanded = searchsortedfirst(table.speeds, 8KNOT)
    start = WindShipOpt.EdgeSample(table.table, seas, corridor, stage, centre, step, 0.0,
        0.0)
    points = WindShipOpt.SailedPoint[]
    hours = WindShipOpt.sail_edge!(points, start, table, seas, corridor, stage, centre,
        step, 0.0, commanded)
    @test 0 < last(points).speed_index < commanded
    @test hours > corridor.edge_length[stage, centre, step] / table.speeds[commanded] / 3600
    storm = HeadSeas(destination, 60NAUTICAL_MILE, wave_from, 8.0, 9.0)
    @test isnothing(route(corridor, table, storm, 0.0; time_cost=hourly))
end

@testset "a round trip at a held speed takes that speed's time and is costed as usual" begin
    distance = sum(corridor.track_length for corridor in corridors)
    ship = Ship(ShipDesign(:methanol, 85.0), assumptions)
    held = [round_trip(ship, corridors..., SyntheticWeather(), [24.0 * 31, 24.0 * 200],
                assumptions; held_knots=knots) for knots in (6.0, 8.0)]
    hours = [24 * (trip.outbound_days + trip.return_days) for trip in held]
    @test first(hours) / last(hours) ≈ 8 / 6 rtol = 0.01
    @test last(hours) ≈ distance / (8KNOT) / 3600 rtol = 0.05
    @test first(held).fuel_energy < last(held).fuel_energy
    chosen = round_trip(ship, corridors..., SyntheticWeather(), [24.0 * 31, 24.0 * 200],
        assumptions)
    @test chosen.cost_per_tonne_km <= minimum(trip.cost_per_tonne_km for trip in held)
end

@testset "an edge is sampled at most the asked hours apart at the commanded speed" begin
    weather, stage, centre = SyntheticWeather(), 1, centre_index(corridor)
    step = WindShipOpt.MAX_LATERAL_STEP + 1
    start = WindShipOpt.EdgeSample(table.table, weather, corridor, stage, centre, step, 0.0,
        24.0)
    speed_index = length(table.speeds)
    commanded = corridor.edge_length[stage, centre, step] / table.speeds[speed_index] / 3600
    points = WindShipOpt.SailedPoint[]
    for sample_hours in (commanded / 4, commanded / 2)
        WindShipOpt.sail_edge!(points, start, table, weather, corridor, stage, centre, step,
            24.0, speed_index, sample_hours * 1.001)
        @test length(points) == round(Int, commanded / sample_hours) + 1
    end
end

@testset "a passage from a later stage continues the optimal path" begin
    weather, departure = SyntheticWeather(), 24.0 * 31
    leg = route(corridor, table, weather, departure; time_cost=hourly)
    stage = (length(leg.path) + 1) ÷ 2
    lat, lon, time = leg.path[stage]
    rest = route(corridor, table, weather, departure + time; time_cost=hourly,
        first_stage=stage,
        first_lateral=WindShipOpt.nearest_lateral(corridor, stage, lat, lon))
    @test length(rest.path) == size(corridor.lat, 1) - stage + 1
    @test rest.path[1][1:2] == (lat, lon)
    @test rest.duration + time ≈ leg.duration rtol = 0.05
    @test rest.fuel_energy < leg.fuel_energy
end

@testset "a ship re-planning on a long forecast sails close to perfect foresight" begin
    weather, departure = SyntheticWeather(), 24.0 * 31
    leg = route(corridor, table, weather, departure; time_cost=hourly)
    sailed = forecast_route(corridor, table, weather, departure; time_cost=hourly,
        horizon=24.0 * 100)
    @test length(sailed.path) == size(corridor.lat, 1)
    @test sailed.path[end][1:2] == leg.path[end][1:2]
    @test sailed.objective ≈ leg.objective rtol = 0.01
    @test sailed.duration > 0 && sailed.fuel_energy > 0
end

@testset "a ship on a long forecast flies its kite about as the plan does" begin
    ship = Ship(ShipDesign(:methanol, 85.0; kite_area=800.0), assumptions)
    kite_table = RouteTable(PerformanceTable(ship, assumptions))
    kite_hourly = first(WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions),
        assumptions))
    weather, departure = SyntheticWeather(), 24.0 * 121
    leg = route(corridor, kite_table, weather, departure; time_cost=kite_hourly)
    sailed = forecast_route(corridor, kite_table, weather, departure;
        time_cost=kite_hourly, horizon=24.0 * 100)
    @test leg.launches > 0
    @test sailed.launches == leg.launches
    @test sailed.flight_hours ≈ leg.flight_hours rtol = 0.02
    @test sailed.objective ≈ leg.objective rtol = 1e-3
end

@testset "a kite flying in good wind stays up unless the plan ahead needs it stowed" begin
    ship = Ship(ShipDesign(:methanol, 85.0; kite_area=800.0), assumptions)
    kite_table = RouteTable(PerformanceTable(ship, assumptions))
    kite_hourly = first(WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions),
        assumptions))
    weather, departure = SyntheticWeather(), 24.0 * 121
    leg = route(corridor, kite_table, weather, departure; time_cost=kite_hourly)
    i = findfirst(i -> leg.aloft[i] && leg.aloft[i + 1], 1:(length(leg.path) - 1))
    lateral = WindShipOpt.nearest_lateral(corridor, i, leg.path[i][1], leg.path[i][2])
    next = WindShipOpt.nearest_lateral(corridor, i + 1, leg.path[i + 1][1],
        leg.path[i + 1][2])
    prices = (; fuel=kite_table.table.ship.fuel.price, time=kite_hourly)
    sail(ahead) = WindShipOpt.sail_planned_edge!(WindShipOpt.SailedPoint[], kite_table,
        weather, corridor, i, lateral, WindShipOpt.lateral_step(lateral, next),
        departure + leg.path[i][3], leg.path[i + 1][4], true, ahead, prices)
    @test sail((0.0, 0.0))[3]
    @test !sail((0.0, Inf))[3]
end

"Synthetic weather with a gale from the south-west no ship can sail in before `calm_from`."
struct GaleWeather
    calm::SyntheticWeather
    calm_from::Float64
end
WindShipOpt.duration(::GaleWeather) = Inf
WindShipOpt.wind(weather::GaleWeather, lat, lon, time) =
    time < weather.calm_from ? (45.0, 45.0) : WindShipOpt.wind(weather.calm, lat, lon, time)
WindShipOpt.waves(weather::GaleWeather, lat, lon, time) =
    time < weather.calm_from ? (16.0, 14.0, 1.25π) : (0.0, 0.0, 0.0)

"Steady wind from the south on a sea whose waves push a ship heading east along."
struct FollowingSeaWeather end
WindShipOpt.duration(::FollowingSeaWeather) = Inf
WindShipOpt.wind(::FollowingSeaWeather, lat, lon, time) = (0.0, 14.0)
WindShipOpt.waves(::FollowingSeaWeather, lat, lon, time) = (16.0, 14.0, 1.25π)

@testset "a leg's trace shows the trim the router priced where waves leave the table" begin
    ship = Ship(ShipDesign(:vlsfo, 140.0; rotor_area=400.0), assumptions)
    table = RouteTable(PerformanceTable(ship, assumptions))
    trace = WindShipOpt.LegTrace((Float64[] for _ in 1:7)..., Bool[], Float64[])
    WindShipOpt.push_trace_point!(trace, table, FollowingSeaWeather(), 24.0 * 31, 30.0,
        -30.0, 0.0, searchsortedfirst(table.speeds, 5.0), π / 2, WindShipOpt.FLYING)
    first_knot = first(table.table.flown_thrust.knots[4])
    priced = last(WindShipOpt.best_trim(ship, ship.rig, only(trace.speed), 14.0,
        only(trace.true_wind_angle), first_knot))
    @test only(trace.rig_thrust) == priced.thrust
end

@testset "a ship on a forecast holds through a gale it cannot sail in" begin
    corridor, _ = route_corridors(:caribbean, north_atlantic_mask(); scale=8)
    departure = 24.0 * 31
    weather = GaleWeather(SyntheticWeather(), departure + 10.0)
    @test isnothing(route(corridor, table, weather, departure; time_cost=hourly))
    after = route(corridor, table, weather, departure + 12.0; time_cost=hourly)
    ship = table.table.ship
    hotel = 3600WindShipOpt.fuel_power(ship.powertrain, 0.0) * ship.fuel.price
    held = 12.0 * (hotel + hourly)
    for horizon in (72.0, 0.0)
        sailed = forecast_route(corridor, table, weather, departure; time_cost=hourly,
            horizon)
        @test length(sailed.path) == size(corridor.lat, 1)
        @test sailed.path[2][3] > 12.0
        @test sailed.objective - held ≈ after.objective rtol = 0.015
    end
    endless = GaleWeather(SyntheticWeather(), Inf)
    @test isnothing(forecast_route(corridor, table, endless, departure; time_cost=hourly,
        horizon=72.0))
end

"""
Synthetic weather with the gale of `GaleWeather` within a nautical mile of `place`
(latitude, longitude) [deg] from `from` until `until` [h], and calm elsewhere.
"""
struct PassingGale
    calm::SyntheticWeather
    place::NTuple{2, Float64}
    from::Float64
    until::Float64
end
WindShipOpt.duration(::PassingGale) = Inf
gale_at(weather::PassingGale, lat, lon, time) = weather.from <= time < weather.until &&
    WindShipOpt.distance(lat, lon, weather.place...) < NAUTICAL_MILE
WindShipOpt.wind(weather::PassingGale, lat, lon, time) =
    gale_at(weather, lat, lon, time) ? (45.0, 45.0) :
    WindShipOpt.wind(weather.calm, lat, lon, time)
WindShipOpt.waves(weather::PassingGale, lat, lon, time) =
    gale_at(weather, lat, lon, time) ? (16.0, 14.0, 1.25π) : (0.0, 0.0, 0.0)

@testset "a ship that would meet a passing gale at its planned speed slows behind it" begin
    centre, step = centre_index(corridor), WindShipOpt.MAX_LATERAL_STEP + 1
    planned = searchsortedfirst(table.speeds, 9KNOT)
    distance = corridor.edge_length[1, centre, step]
    arrival(speed_index) = 24.0 * 31 + distance / table.speeds[speed_index] / 3600
    place = (corridor.lat[2, centre], corridor.lon[2, centre])
    gale = PassingGale(SyntheticWeather(), place, 24.0 * 31,
        (arrival(planned) + arrival(planned - 1)) / 2)
    prices = (; fuel=table.table.ship.fuel.price, time=hourly)
    hours, tally, _, speed = WindShipOpt.sail_planned_edge!(WindShipOpt.SailedPoint[],
        table, gale, corridor, 1, centre, step, 24.0 * 31, table.speeds[planned], false,
        (0.0, Inf), prices)
    @test isfinite(hours) && isfinite(tally.cost)
    @test speed < table.speeds[planned]
end

"""
Synthetic weather with, before the same date a year on, 5 m head seas and a wind 60 degrees
off the bow on the first edge from `start`, in which only a kite flying holds more than
4 kn, yet the seas forbid launching it.
"""
struct KiteOnlySeas
    calm::SyntheticWeather
    start::NTuple{2, Float64}
    course::Float64
end
WindShipOpt.duration(::KiteOnlySeas) = Inf
rough_seas(weather::KiteOnlySeas, lat, lon, time) = time < WindShipOpt.FORECAST_SHIFT &&
    WindShipOpt.distance(lat, lon, weather.start...) < 200NAUTICAL_MILE
WindShipOpt.wind(weather::KiteOnlySeas, lat, lon, time) =
    rough_seas(weather, lat, lon, time) ?
    -8.0 .* sincos(weather.course + deg2rad(60)) :
    WindShipOpt.wind(weather.calm, lat, lon, time)
WindShipOpt.waves(weather::KiteOnlySeas, lat, lon, time) =
    rough_seas(weather, lat, lon, time) ? (5.0, 10.0, weather.course) : (0.0, 0.0, 0.0)

@testset "a ship on a forecast slows where its kite cannot launch as planned" begin
    ship = Ship(ShipDesign(:methanol, 85.0; kite_area=800.0), assumptions)
    kite_table = RouteTable(PerformanceTable(ship, assumptions))
    kite_hourly = first(WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions),
        assumptions))
    centre, step = centre_index(corridor), WindShipOpt.MAX_LATERAL_STEP + 1
    seas = KiteOnlySeas(SyntheticWeather(), (corridor.lat[1, centre],
            corridor.lon[1, centre]), corridor.edge_course[1, centre, step])
    sailed = forecast_route(corridor, kite_table, seas, 24.0 * 31; time_cost=kite_hourly,
        horizon=0.0)
    @test length(sailed.path) == size(corridor.lat, 1)
    @test sailed.path[2][4] < 5KNOT
end

@testset "a forecast beyond its horizon reads the same date in another year" begin
    known = ForecastWeather(SyntheticWeather(), 100.0, 48.0)
    @test WindShipOpt.wind(known, 40.0, -30.0, 120.0) ==
          WindShipOpt.wind(known.weather, 40.0, -30.0, 120.0)
    beyond = 160.0
    @test WindShipOpt.wind(known, 40.0, -30.0, beyond) ==
          WindShipOpt.wind(known.weather, 40.0, -30.0, beyond + WindShipOpt.FORECAST_SHIFT)
    @test WindShipOpt.wind(known, 40.0, -30.0, beyond) !=
          WindShipOpt.wind(known.weather, 40.0, -30.0, beyond)
end

"""
    write_fields(directory, values, steps, grid)

Fields `values(name)` of `steps` stored times each, a (lon, lat) matrix per time, written to
`directory` with `grid` as its `grid.toml`, in the type of the first matrix.
"""
function write_fields(directory, values, steps, grid)
    mkpath(directory)
    open(io -> WindShipOpt.TOML.print(io, grid), joinpath(directory, "grid.toml"), "w")
    for name in grid["variables"]
        extension = eltype(values(name, 1)) == Float16 ? "f16" : "f32"
        open(joinpath(directory, "$name.$extension"), "w") do io
            foreach(step -> write(io, values(name, step)), 1:steps)
        end
    end
end

"ERA5 of steady wind and waves on a 2 by 2 grid from 2017-12-29, the east wind rising."
function small_era5(directory)
    square = (lats=[40.0, 41.0], lons=[-31.0, -30.0])
    truth = Dict("u10" => step -> 5.0f0 + 0.01f0 * step, "v10" => step -> -2.0f0,
        "height" => step -> 2.0f0, "period" => step -> 8.0f0, "direction" => step -> 90.0f0)
    for (group, names, step_hours) in (("wind", ["u10", "v10"], 6),
        ("waves", ["direction", "height", "period"], 12))
        write_fields(joinpath(directory, group),
            (name, step) -> fill(truth[name](step), 2, 2), 2000 ÷ step_hours,
            Dict("lats" => square.lats, "lons" => square.lons, "step_hours" => step_hours,
                "first_time" => "2017-12-29T00:00:00", "variables" => names))
    end
    return ERA5Weather(directory)
end

"""
    small_archive(directory, weather, offset)

Four daily forecasts from 2017-12-30 on the grids of `weather`, each the weather it
forecasts plus `offset(year)` on the east wind and half that on the wave height.
"""
function small_archive(directory, weather, offset)
    first_issue = 24.0
    for (group, observed, names, leads) in (
        ("wind", weather.wind, ["u10", "v10"], 6:6:24),
        ("waves", weather.waves, ["direction_east", "direction_north", "height", "period"],
            12:12:24))
        function field(name, index)
            issue, lead = divrem(index - 1, length(leads)) .+ 1
            time = first_issue + 24.0 * (issue - 1) + leads[lead]
            step = Int((time - observed.time_offset) / observed.step_hours + 1)
            year = issue <= 2 ? 2017 : 2018
            shift = name == "u10" ? offset(year) : name == "height" ? offset(year) / 2 : 0.0
            return Float16.(observed.fields[name][:, :, step] .+ shift)
        end
        write_fields(joinpath(directory, group), field, 4length(leads),
            Dict("lats" => observed.lats, "lons" => observed.lons,
                "first_issue" => "2017-12-30T00:00:00", "issue_hours" => 24,
                "first_lead_hours" => first(leads), "step_hours" => step(leads),
                "leads" => length(leads), "variables" => names))
    end
    write_forecast_bias(directory, weather)
    return ForecastArchive(directory, weather)
end

@testset "a forecast off by a fixed bias reads the weather once that bias is removed" begin
    directory = mktempdir()
    weather = small_era5(joinpath(directory, "era5"))
    archive = small_archive(joinpath(directory, "forecast"), weather, year -> 1.5)
    known = ArchivedForecast(archive, weather, 24.0 * 3 + 7.0)
    for time in known.issued .+ (6.0, 12.0, 21.0)
        @test all(isapprox.(wind(known, 40.5, -30.5, time),
            wind(weather, 40.5, -30.5, time); atol=0.01))
        @test all(isapprox.(waves(known, 40.5, -30.5, time),
            waves(weather, 40.5, -30.5, time); atol=0.01))
    end
end

@testset "a forecast's bias is learnt from the other years only" begin
    directory = mktempdir()
    weather = small_era5(joinpath(directory, "era5"))
    archive = small_archive(joinpath(directory, "forecast"), weather,
        year -> year == 2017 ? 1.0 : 3.0)
    late_2017 = ArchivedForecast(archive, weather, 24.0 * 2 + 7.0)
    @test late_2017.year == 2017
    time = late_2017.issued + 18.0
    @test first(wind(late_2017, 40.5, -30.5, time)) ≈
          first(wind(weather, 40.5, -30.5, time)) + 1.0 - 3.0 atol = 0.02
    @test first(waves(late_2017, 40.5, -30.5, time)) ≈ 2.0 + 0.5 - 1.5 atol = 0.01
end

@testset "a ship reads the last forecast to reach it, beyond its leads another year" begin
    directory = mktempdir()
    weather = small_era5(joinpath(directory, "era5"))
    archive = small_archive(joinpath(directory, "forecast"), weather, year -> 0.0)
    third = 24.0 * 3
    @test ArchivedForecast(archive, weather, third + WindShipOpt.FORECAST_LATENCY).issued ==
          third
    @test ArchivedForecast(archive, weather, third + 5.0).issued == third - 24.0
    known = ArchivedForecast(archive, weather, third + 7.0)
    beyond = third + 30.0
    @test wind(known, 40.5, -30.5, beyond) ==
          wind(ForecastWeather(weather, third, 24.0), 40.5, -30.5, beyond)
end

@testset "a ship whose latest forecast is missing from the archive reads the one before" begin
    directory = mktempdir()
    weather = small_era5(joinpath(directory, "era5"))
    small_archive(joinpath(directory, "forecast"), weather, year -> 0.0)
    for name in ("direction_east", "direction_north", "height", "period")
        open(joinpath(directory, "forecast", "waves", "$name.f16"), "r+") do io
            issue_bytes = filesize(io) ÷ 4
            seek(io, 3issue_bytes)
            write(io, fill(NaN16, issue_bytes ÷ 2))
        end
    end
    archive = ForecastArchive(joinpath(directory, "forecast"), weather)
    fourth = 24.0 * 4
    @test ArchivedForecast(archive, weather, fourth + 7.0).issued == fourth - 24.0
end

@testset "a ship reads another year's waves where its forecast has none" begin
    directory = mktempdir()
    weather = small_era5(joinpath(directory, "era5"))
    small_archive(joinpath(directory, "forecast"), weather, year -> 0.0)
    for name in ("direction_east", "direction_north", "height", "period")
        path = joinpath(directory, "forecast", "waves", "$name.f16")
        values = read!(path, Vector{Float16}(undef, filesize(path) ÷ 2))
        values[1:4:end] .= NaN16
        write(path, values)
    end
    known = ArchivedForecast(ForecastArchive(joinpath(directory, "forecast"), weather),
        weather, 24.0 * 3 + 7.0)
    time = known.issued + 18.0
    @test waves(known, 40.0, -31.0, time) == waves(known.beyond, 40.0, -31.0, time)
    @test first(waves(known, 40.0, -31.0, time)) > 0
end

@testset "a search that cuts off the best path and overruns its limit widens" begin
    weather, departure = SyntheticWeather(), 24.0 * 31
    (; time_step) = WindShipOpt.ROUTER_SETTINGS[]
    stage_count = size(corridor.lat, 1)
    workspace = WindShipOpt.RouteWorkspace(size(corridor.lat, 2),
        ceil(Int, 1200 / time_step), stage_count)
    options = (; time_step, time_cost=hourly, first_stage=1,
        first_lateral=centre_index(corridor), first_aloft=false, coastal_penalty=1.0,
        speed_stride=WindShipOpt.ROUTER_SETTINGS[].search_speed_stride)
    best = WindShipOpt.route_pass(workspace, corridor, table, weather, departure;
        options...)
    stage = stage_count - 2
    best_node = findfirst(==(best.path[stage][2]), view(corridor.lon, stage, :))
    values = zeros(size(corridor.lat, 2), 200, 2, stage_count)
    values[best_node, :, :, stage] .= Inf
    to_go = WindShipOpt.CostToGo(values)
    detour = WindShipOpt.route_pass(workspace, corridor, table, weather, departure, to_go,
        floatmax(); options...)
    @test detour.objective > best.objective
    leg = WindShipOpt.searched_leg(workspace, corridor, table, weather, departure, to_go,
        (prevfloat(detour.objective),); options...)
    @test leg.objective == best.objective
end

@testset "router settings return to those in force after a call under others" begin
    earlier = WindShipOpt.ROUTER_SETTINGS[]
    other = WindShipOpt.RouterSettings(time_step=1.5)
    in_force = WindShipOpt.with_router_settings(() -> WindShipOpt.ROUTER_SETTINGS[], other)
    @test in_force == other
    @test WindShipOpt.ROUTER_SETTINGS[] == earlier
    @test_throws ErrorException WindShipOpt.with_router_settings(() -> error("stop"), other)
    @test WindShipOpt.ROUTER_SETTINGS[] == earlier
end

@testset "a ship that can fly a kite is searched at the kite margins" begin
    settings = WindShipOpt.RouterSettings(search_margins=(0.1, 0.2),
        kite_search_margins=(0.3, 0.4))
    kite_ship = Ship(ShipDesign(:methanol, 85.0; kite_area=800.0), assumptions)
    kite_table = RouteTable(PerformanceTable(kite_ship, assumptions))
    bare_table = RouteTable(PerformanceTable(Ship(ShipDesign(:methanol, 85.0), assumptions),
        assumptions))
    @test WindShipOpt.margins_searched(kite_table, settings) == (0.3, 0.4)
    @test WindShipOpt.margins_searched(bare_table, settings) == (0.1, 0.2)
end

@testset "a kite aloft leaving a node with the kite down at the same time shares its \
          edges" begin
    workspace = WindShipOpt.RouteWorkspace(3, 4, 2)
    down, aloft = (2, 3, 1, 1), (2, 3, 2, 1)
    later_down, later_aloft = (2, 4, 1, 1), (2, 4, 2, 1)
    for (state, cost, time) in ((down, 10.0, 4.0), (aloft, 12.0, 4.0),
        (later_down, 10.0, 5.0), (later_aloft, 12.0, 5.5))
        workspace.cost[state...], workspace.elapsed[state...] = cost, time
    end
    share(state) = WindShipOpt.sharing_edges!(workspace, state, nothing, Inf, 5)
    from = share(down)
    @test from >= 0
    @test length(workspace.shared) == from + 5 * (2WindShipOpt.MAX_LATERAL_STEP + 1)
    @test share(aloft) == from
    @test share(later_down) == share(later_aloft) == -1
end

@testset "a faster command holds the same speed only through speeds no engine \
          powers" begin
    table = RouteTable(PerformanceTable(Ship(ShipDesign(:methanol, 85.0), assumptions),
        assumptions))
    condition = WindShipOpt.SeaCondition(table.table, 0.0, 0.0, 3.0, 6.0, 2π / 3)
    sample = WindShipOpt.EdgeSample(condition, 0.0, 0.0, true)
    powered(i) = isfinite(last(WindShipOpt.edge_fuels(table, i, condition)))
    unpowered = findfirst(!powered, eachindex(table.speeds))
    faster_powered = findnext(powered, eachindex(table.speeds), unpowered)
    held, flown, stowed, same_through = WindShipOpt.held_speed(table, unpowered, sample)
    @test same_through == faster_powered - 1
    for speed_index in unpowered:same_through
        @test WindShipOpt.held_speed(table, speed_index, sample)[1:3] ==
              (held, flown, stowed)
    end
    @test first(WindShipOpt.held_speed(table, faster_powered, sample)) == faster_powered
end

module PaperRuns
root = pkgdir(Main.WindShipOpt)
include(joinpath(root, "scripts", "paper_runs.jl"))
runs_directory = mktempdir()
end

@testset "a run counts as finished only once every step it was asked for is done" begin
    write_data(run, name) = PaperRuns.run_step!(run, name,
        () -> touch(joinpath(run.directory, "$name.csv")))
    is_open() = !PaperRuns.is_finished(last(only(PaperRuns.fidelity_runs(:draft))))
    run = PaperRuns.open_run(:draft, [:designs, :routes], false)
    write_data(run, :designs)
    @test is_open()
    narrower = PaperRuns.open_run(:draft, [:designs], true)
    PaperRuns.finish_run!(narrower)
    @test is_open()
    rest = PaperRuns.open_run(:draft, [:routes], true)
    write_data(rest, :routes)
    rm(joinpath(rest.directory, "designs.csv"))
    PaperRuns.finish_run!(rest)
    @test is_open()
    write_data(rest, :designs)
    PaperRuns.finish_run!(rest)
    @test !is_open()
end

@testset "a round trip at a held speed or with a model part off is stored apart" begin
    @eval PaperRuns weather_name = "synthetic"
    PaperRuns.paper_run = PaperRuns.PaperRun(mktempdir(), :draft,
        Dict{String, Any}("code_hash" => "held"), 0, 0)
    case_at(held_knots, part) = (; design=ShipDesign(:vlsfo, 100.0), assumptions,
        route=:caribbean, scale=8.0, forecast=false, held_knots, part)
    @test allunique(PaperRuns.case_directory(case_at(held_knots, :none), [24.0])
                    for held_knots in (nothing, 8.0, 9.0))
    @test allunique(PaperRuns.case_directory(case_at(nothing, part), [24.0])
                    for part in (:none, :waves, :windage))
end

@testset "the code hash keying stored trips covers the ship data tables" begin
    files = normpath.(PaperRuns.code_files())
    @test joinpath(pkgdir(WindShipOpt), "data", "ship_classes.csv") in files
    @test joinpath(pkgdir(WindShipOpt), "data", "ship_categories.csv") in files
end

@testset "resuming never takes over another branch's unfinished run" begin
    @eval PaperRuns runs_directory = mktempdir()
    other_branch = joinpath(PaperRuns.runs_directory, "2000-01-01T0000")
    mkpath(other_branch)
    open(joinpath(other_branch, "run.toml"), "w") do io
        PaperRuns.TOML.print(io, Dict("fidelity" => "draft", "finished" => "",
            "git_branch" => "other", "code_hash" => "", "requested" => String[],
            "steps" => Dict{String, Any}[]))
    end
    @test PaperRuns.open_run(:draft, [:designs], true).directory != other_branch
    @test isempty(PaperRuns.TOML.parsefile(joinpath(other_branch, "run.toml"))["requested"])
end

@testset "a table reads its own branch's study before a newer one of another branch" begin
    function finished_run(name, branch)
        directory = joinpath(PaperRuns.runs_directory, name)
        mkpath(directory)
        touch(joinpath(directory, "study.csv"))
        record = Dict("fidelity" => "final", "finished" => "done", "git_branch" => branch)
        open(io -> PaperRuns.TOML.print(io, record), joinpath(directory, "run.toml"), "w")
        return joinpath(directory, "study.csv")
    end
    branch = PaperRuns.git_output("rev-parse", "--abbrev-ref", "HEAD")
    own = finished_run("2026-01-01T0000", branch)
    other = finished_run("2026-01-01T0001", "another-branch")
    @eval PaperRuns paper_run = PaperRun(nothing, :final, Dict{String, Any}(), 0, 0)
    @test PaperRuns.data_file("study.csv") == own
    rm(own)
    @test PaperRuns.data_file("study.csv") == other
end

@testset "a rig's stored trip serves an input it never reads, and no other" begin
    rotors = ShipDesign(:methanol, 85.0; rotor_area=200.0)
    routed(inputs) = round_trip(Ship(rotors, inputs), corridors..., SyntheticWeather(),
        [24.0 * 31, 24.0 * 200], inputs)
    at_high(name) = with_value(assumptions, name, assumptions.entries[name].high)
    directory = mktempdir()
    PaperRuns.stored_trip(() -> routed(assumptions), directory, assumptions)
    dearer_canopy = at_high(:canopy_cloth_base_price)
    reused = PaperRuns.cached_trip(directory, dearer_canopy)
    rerouted = routed(dearer_canopy)
    @test reused.cost_per_tonne_km == rerouted.cost_per_tonne_km
    @test reused.fuel_energy == rerouted.fuel_energy
    @test ismissing(PaperRuns.cached_trip(directory, at_high(:rotor_unit_cost)))
    @test ismissing(PaperRuns.cached_trip(directory, at_high(:market_price_factor)))
end

@testset "an input read in a task spawned while recording is recorded" begin
    value, names = inputs_read(() -> fetch(Threads.@spawn assumptions[:discount_rate]))
    @test value == assumptions[:discount_rate]
    @test names == Set([:discount_rate])
end

module SizeSearch
include(joinpath(pkgdir(Main.WindShipOpt), "scripts", "size_search.jl"))
end

@testset "a size search whose best is a bound next tries the size just inside it" begin
    step = 2^0.25
    @test SizeSearch.next_size([(500.0, 3.0), (2828.0, 2.0), (16000.0, 1.0)], 500.0,
        16000.0) ≈ SizeSearch.snap_area(16000 / step)
    @test SizeSearch.next_size([(500.0, 1.0), (2828.0, 2.0), (16000.0, 3.0)], 500.0,
        16000.0) ≈ SizeSearch.snap_area(500 * step)
    @test SizeSearch.next_size([(13777.0, 2.0), (16000.0, 1.0)], 500.0, 16000.0) ≈
          SizeSearch.snap_area(sqrt(13777 * 16000))
end

@testset "the paper's draft marker stays until a final call redraws every figure" begin
    marker = tempname()
    write(marker, "")
    figures = [:capital, :premium]
    is_marked(fidelity, steps) = begin
        PaperRuns.mark_fidelity(marker, fidelity, steps, figures)
        !isempty(read(marker, String))
    end
    @test !is_marked(:draft, [:designs])
    @test is_marked(:draft, [:premium])
    @test is_marked(:final, [:designs])
    @test is_marked(:final, [:capital])
    @test !is_marked(:final, [:designs, :capital, :premium])
end

@testset "every ship has the same speeds, on the knots of its table, from 4 kn up" begin
    classes = ship_classes()
    designs = (ShipDesign(:methanol, 85.0), ShipDesign(:methanol, 140.0),
        ShipDesign(:vlsfo, classes["Kamsarmax bulk carrier"]))
    (; routing_speeds, search_speed_stride) = WindShipOpt.ROUTER_SETTINGS[]
    for design in designs
        ship = Ship(design, assumptions)
        table = PerformanceTable(ship, assumptions)
        route_table = RouteTable(table)
        @test length(route_table.speeds) == routing_speeds
        @test first(route_table.speeds) ≈ 4KNOT
        @test last(route_table.speeds) == ship.max_speed
        @test route_table.speeds ⊆ table.speeds
        @test first(table.speeds) >= WindShipOpt.LOWEST_TABLE_SPEED
    end
    coarser = WindShipOpt.with_router_settings(WindShipOpt.RouterSettings(
        routing_speeds=25, search_speed_stride=2)) do
        PerformanceTable(Ship(first(designs), assumptions), assumptions)
    end
    @test first(RouteTable(coarser).speeds) ≈ 4KNOT
    @test length(RouteTable(coarser).speeds) == 25
    stride = WindShipOpt.COST_TO_GO_SPEED_STRIDE * search_speed_stride
    @test mod(routing_speeds - 1, stride) == 0
end

@testset "the final pass keeps the path, refines its speeds and never costs more" begin
    outbound, _ = corridors
    for design in (ShipDesign(:methanol, 85.0),
        ShipDesign(:methanol, 85.0; kite_area=800.0))

        table = RouteTable(PerformanceTable(Ship(design, assumptions), assumptions))
        passage() = route(outbound, table, SyntheticWeather(), 24.0 * 31; time_cost=300.0)
        no_room_in_time = WindShipOpt.RouterSettings(final_time_band=-1.0)
        searched = WindShipOpt.with_router_settings(passage, no_room_in_time)
        final = passage()
        @test final.objective < searched.objective
        @test [point[1:2] for point in final.path] ==
              [point[1:2] for point in searched.path]
        searched_speeds = [point[4] for point in searched.path[2:end]]
        final_speeds = [point[4] for point in final.path[2:end]]
        commanded = table.speeds[1:WindShipOpt.ROUTER_SETTINGS[].search_speed_stride:end]
        @test searched_speeds ⊆ commanded
        @test final_speeds ⊆ table.speeds
        @test !(final_speeds ⊆ commanded)
    end
end

@testset "every rig's route costs what a search at every speed finds" begin
    _, back = corridors
    every_speed = WindShipOpt.RouterSettings(search_speed_stride=1)
    for (design, departure) in ((ShipDesign(:methanol, 85.0; wing_area=400.0), 24.0 * 91),
        (ShipDesign(:methanol, 85.0; kite_area=800.0), 24.0 * 211))

        table = RouteTable(PerformanceTable(Ship(design, assumptions), assumptions))
        passage() = route(back, table, SyntheticWeather(), departure; time_cost=300.0)
        full = WindShipOpt.with_router_settings(passage, every_speed)
        @test passage().objective <= full.objective * (1 + 1e-4)
    end
end

@testset "a held speed steps down through the ship's own speeds, and is commanded" begin
    table = PerformanceTable(Ship(ShipDesign(:methanol, 85.0), assumptions), assumptions)
    held = WindShipOpt.held_speed_table(table, 11.3)
    @test last(held.speeds) ≈ 11.3KNOT
    @test held.speeds[1:(end - 1)] == filter(<(11.3KNOT), RouteTable(table).speeds)
    for count in 1:12, stride in 1:4
        indices = WindShipOpt.commanded_speeds(count, stride)
        @test last(indices) == count && step(indices) == stride && first(indices) <= stride
    end
end

@testset "soft and rigid kites both stop depowering where their lift reaches 0.05" begin
    soft = first(WindShipOpt.kite_model(800.0, 3.0, assumptions))
    rigid = first(WindShipOpt.rigid_kite_model(54.0, 1, assumptions))
    for model in (soft, rigid)
        @test WindShipOpt.polar_value(model.polar, model.polar.lift, model.lowest_angle) ≈
              0.05
    end
end

@testset "a number of the paper prints as a draft result until the final run" begin
    @test PaperRuns.number_macro("SavingOilKite", "4", true) ==
          "\\newcommand{\\NumSavingOilKite}{\\tbd{4}}\n"
    @test PaperRuns.number_macro("SavingOilKite", "4", false) ==
          "\\newcommand{\\NumSavingOilKite}{4}\n"
    @test PaperRuns.whole_number(-0.4) == "0"
    @test PaperRuns.whole_number(12.6) == "13"
end

@testset "every number the paper and its extended abstract print from the numbers step \
          is one it wrote" begin
    paper = joinpath(PaperRuns.root, "paper")
    texts = [joinpath(directory, name) for directory in (paper, joinpath(paper, "sections"))
             for name in readdir(directory) if endswith(name, ".tex")]
    used = Set(m.match for text in texts
               for m in eachmatch(r"\\Num[A-Za-z]+", read(text, String)))
    defined = Set(m[1] for m in eachmatch(r"\\newcommand\{(\\Num[A-Za-z]+)\}",
        read(joinpath(paper, "sections", "numbers.tex"), String)))
    @test !isempty(used)
    @test used ⊆ defined
end

@testset "a rigid wing of the MX2 design matches its published numbers" begin
    model, force, diameter, airframe = WindShipOpt.rigid_kite_model(54.0, 1, assumptions)
    @test diameter ≈ 0.0294 rtol=0.01
    @test airframe.tether_mass ≈ 275 rtol=0.05
    @test airframe.mass ≈ 1852
    @test force ≈ 300e3 rtol=0.01
    makani_hover = with_value(with_value(assumptions, :rigid_hover_air_density, 0.95),
        :rigid_hover_efficiency, 0.71)
    @test WindShipOpt.hover_power(2180.0, 54.0, makani_hover) ≈ 900e3 rtol=0.05
    tether_drag = assumptions[:rigid_tether_drag_coefficient] * diameter *
                  model.tether_length / (4 * 54.0)
    @test tether_drag ≈ 0.152 - 0.123 rtol=0.05
    polar = WindShipOpt.rigid_polar(assumptions)
    lift = 1.81
    angle = lift / (polar.lift[2] / polar.angle_of_attack[2])
    @test WindShipOpt.polar_value(polar, polar.drag, angle) ≈ 0.123 rtol=0.02
end

"""
    best_thrust(model, force, wind_speed)

Thrust [N] of the best pattern of `model` under tension limit `force` [N] on a beam course
in `wind_speed` [m/s], zero where nothing flies, with its pattern force.
"""
function best_thrust(model, force, wind_speed)
    problem = WindShipOpt.PatternProblem(model, force, deg2rad(8), wind_speed, π / 2, 0.0)
    pattern_force, _ = WindShipOpt.optimal_pattern(problem,
        WindShipOpt.pattern_starts(model, π / 2))
    isfinite(pattern_force.peak_tension) || return 0.0, pattern_force
    return 0.5model.air_density * wind_speed^2 * model.area * pattern_force.force[2],
    pattern_force
end

@testset "a rigid wing loops within its tether limit and needs more wind as it grows" begin
    small, small_force, = WindShipOpt.rigid_kite_model(30.0, 1, assumptions)
    large, large_force, = WindShipOpt.rigid_kite_model(300.0, 1, assumptions)
    @test first(best_thrust(small, small_force, 6.0)) > 0
    @test first(best_thrust(large, large_force, 6.0)) == 0
    thrust, pattern_force = best_thrust(large, large_force, 14.0)
    @test thrust > 0
    load = 0.5large.air_density * 14.0^2 * large.area
    @test pattern_force.peak_tension * load <= large_force * 1.001
    @test rad2deg(pattern_force.lowest_elevation) >= 8 - 0.01
end

@testset "a wing stalling at the top of its loop does not fly the loop" begin
    model, = WindShipOpt.rigid_kite_model(54.0, 1, assumptions)
    stall = sqrt(2model.mass * model.gravity /
                 (model.air_density * model.area * maximum(model.polar.lift)))
    @test WindShipOpt.holds_speed(model, 2stall, 0.0)
    @test !WindShipOpt.holds_speed(model, 2stall, 4stall^2 / model.gravity)
end

"""
    rigid_fleet(count, assumptions)

Rigid kites of 54 m^2 with a two-point force table of 100 kN downwind per kite at every
wind speed.
"""
function rigid_fleet(count, assumptions)
    model, max_force, tether_diameter, airframe = WindShipOpt.rigid_kite_model(54.0, count,
        assumptions)
    wind_speeds = [5.0, 30.0]
    courses = [0.0, π]
    side_weights = [0.0]
    forces = [WindShipOpt.PatternForce(
                  (1e5 / (0.5 * model.air_density * speed^2 * 54.0), 0.0, 0.0), 1.0, 0.5)
              for speed in wind_speeds, _ in courses, _ in side_weights]
    return KiteRig(; area=54.0, tether_diameter, model.tether_length, reference_height=10.0,
        WindShipOpt.rigid_wind_limits(5.0, assumptions)..., max_force, attach_height=10.0,
        attach_position=0.0, wind_speeds, courses, side_weights, forces, airframe)
end

@testset "rigid kites stand one span apart within the deck" begin
    hull = PAPER_HULL
    span = sqrt(54.0 * assumptions[:rigid_aspect_ratio])
    room = floor(Int, assumptions[:deck_length_fraction] * hull.length / span)
    @test WindShipOpt.rigid_kites_fit(room, hull, assumptions)
    @test !WindShipOpt.rigid_kites_fit(room + 1, hull, assumptions)
    @test isnothing(WindShipOpt.rigid_kite_rig((room + 1) * 54.0, hull, assumptions))
end

"lone kite's force over dynamic pressure [m^2] at 12 m/s true wind dead astern at 5 m/s"
function lone_force_area(rig, env)
    wind = WindShipOpt.wind_at_height(env, 12.0, rig.reference_height)
    speed = first(WindShipOpt.apparent_wind(wind, π, 5.0))
    return rig_force(rig, env, 12.0, π, 5.0, 0.0).thrust / (0.5env.air_density * speed^2)
end

@testset "more rigid kites weigh and cost in proportion and pull less per kite" begin
    env = Environment(assumptions)
    one, three = rigid_fleet(1, assumptions), rigid_fleet(3, assumptions)
    pull(rig) = rig_force(rig, env, 12.0, π, 5.0, 0.0).thrust
    force_area = lone_force_area(one, env)
    @test WindShipOpt.loop_interaction(one, force_area) ≈ 1
    interaction = WindShipOpt.loop_interaction(three, force_area)
    @test interaction < 1
    lone = force_area / three.airframe.loop_area
    induction = 3lone / (4 + 3lone)
    @test 3lone * (1 - induction)^2 ≈ 4induction * (1 - induction)
    @test pull(three) ≈ 3interaction * pull(one)
    @test WindShipOpt.deck_units(three) == 3
    @test WindShipOpt.deck_footprint(one, assumptions) == assumptions[:rigid_perch_width]
    @test all(WindShipOpt.rig_costs(three, assumptions) .≈
              3 .* WindShipOpt.rig_costs(one, assumptions))
    @test WindShipOpt.wear_cost(three, assumptions) ≈
          3WindShipOpt.wear_cost(one, assumptions)
    @test WindShipOpt.cycle_cost(three, assumptions) ≈
          3WindShipOpt.cycle_cost(one, assumptions)
end

@testset "each launch wears the tether by its bends over drum and sheaves" begin
    soft = uniform_kite(Hull(140.0, assumptions), assumptions)
    rigid = rigid_fleet(2, assumptions)
    halved = with_value(assumptions, :tether_bend_life, assumptions[:tether_bend_life] / 2)
    for rig in (soft, rigid)
        _, tether = WindShipOpt.consumable_costs(rig, assumptions)
        added = WindShipOpt.cycle_cost(rig, halved) -
                WindShipOpt.cycle_cost(rig, assumptions)
        @test added ≈
              tether * assumptions[:tether_bends_per_launch] / assumptions[:tether_bend_life]
    end
end

@testset "a rigid kite hovers within its own limits and stays up beyond them" begin
    fleet = rigid_fleet(2, assumptions)
    waves = assumptions[:rigid_hover_max_wave_height]
    @test waves < WindShipOpt.max_wave_height(fleet, assumptions)
    wind = assumptions[:rigid_hover_max_wind]
    @test WindShipOpt.kite_landable(fleet, 0.0, wind - 1, 0.0, waves)
    @test !WindShipOpt.kite_landable(fleet, 0.0, wind + 1, 0.0, waves)
    @test !WindShipOpt.kite_landable(fleet, 0.0, wind - 1, 0.0, waves + 0.5)
    @test fleet.launch_min_wind == fleet.min_flight_wind
    @test WindShipOpt.handling_hours(fleet, assumptions) ≈
          assumptions[:rigid_hover_minutes] / 60
    airframes = WindShipOpt.rigid_airframe_price(fleet, assumptions)
    _, tethers = WindShipOpt.consumable_costs(fleet, assumptions)
    @test WindShipOpt.forced_landing_cost(fleet, assumptions) ≈
          assumptions[:kite_forced_landing_loss_probability] * (airframes + tethers)
end

@testset "a rigid wing flies no lower than its loops or a level sweep allow" begin
    hull = Hull(140.0, assumptions)
    rig = WindShipOpt.rigid_kite_rig(54.0, hull, assumptions; courses=[π / 2],
        side_weights=[0.0])
    model, = WindShipOpt.rigid_kite_model(54.0, 1, assumptions)
    elevation = deg2rad(assumptions[:kite_min_elevation])
    @test rig.min_flight_wind >= WindShipOpt.crosswind_min_wind(model, elevation)
    @test rig.min_flight_wind < WindShipOpt.climbing_min_wind(model, elevation)
    below = findlast(<(rig.min_flight_wind), rig.wind_speeds)
    @test isnothing(below) || !isfinite(rig.forces[below, 1, 1].peak_tension)
end

@testset "a failed rigid kite grounds itself and leaves the others flying" begin
    changed = with_value(assumptions, :kite_out_of_service, 0.1)
    fleet = rigid_fleet(4, changed)
    env = Environment(changed)
    states = WindShipOpt.service_states(fleet, changed)
    @test first(first(states)) ≈ 0.9^4
    share, down = last(states)
    @test share ≈ 1 - 0.9^4
    kites_in_service = sum(first(state) * WindShipOpt.kite_count(last(state))
                           for state in states)
    @test kites_in_service ≈ 0.9 * 4
    flying = WindShipOpt.kite_count(down) / 4
    pull(rig) = rig_force(rig, env, 12.0, π, 5.0, 0.0).thrust
    force_area = lone_force_area(rigid_fleet(1, changed), env)
    @test pull(down) ≈ WindShipOpt.kite_count(down) *
                       WindShipOpt.loop_interaction(down, force_area) *
                       pull(rigid_fleet(1, changed))
    @test WindShipOpt.wear_cost(down, changed) ≈
          flying * WindShipOpt.wear_cost(fleet, changed)
    @test WindShipOpt.cycle_cost(down, changed) ≈
          flying * WindShipOpt.cycle_cost(fleet, changed)
    lone = rigid_fleet(1, changed)
    @test isnothing(last(last(WindShipOpt.service_states(lone, changed))))
end

@testset "one crash costs a control unit, half the wearing parts, or one deck unit" begin
    hull = Hull(140.0, assumptions)
    kite = uniform_kite(hull, assumptions)
    canopy, tether = WindShipOpt.consumable_costs(kite, assumptions)
    control_unit = assumptions[:market_price_factor] *
                   WindShipOpt.rig_price_parts(kite, assumptions).control_unit
    @test WindShipOpt.crash_cost(kite, assumptions) ≈ control_unit + (canopy + tether) / 2
    for rig_type in (WingRig, WindShipOpt.RotorRig)
        rig = rig_type(800.0, hull, assumptions)
        @test rig.count > 1
        @test WindShipOpt.crash_cost(rig, assumptions) * rig.count ≈
              first(WindShipOpt.rig_costs(rig, assumptions))
    end
end

@testset "rigs pay their own maintenance fraction, not on what wear or upkeep pays" begin
    raised(name) = with_value(assumptions, name, assumptions[name] + 0.01)
    costs(ship, inputs) = ShipCosts(ship, inputs; retractable=false)
    maintenance_of(ship, name) = costs(ship, raised(name)).fixed_annual -
                                 costs(ship, assumptions).fixed_annual
    bare = Ship(ShipDesign(:methanol, 140.0), assumptions)
    @test maintenance_of(bare, :rig_maintenance_fraction) == 0
    for rig_area in ((; kite_area=800.0), (; kite_area=800.0, rotor_area=400.0),
        (; rotor_area=400.0))
        ship = Ship(ShipDesign(:methanol, 140.0; rig_area...), assumptions)
        rig_capital = first(WindShipOpt.rig_costs(ship.rig, assumptions))
        worn = WindShipOpt.worn_part_price(ship.rig, assumptions)
        @test maintenance_of(ship, :maintenance_fraction) ≈
              0.01 * (costs(ship, assumptions).capital - rig_capital)
        @test maintenance_of(ship, :rig_maintenance_fraction) ≈ 0.01 * (rig_capital - worn)
    end
    fleet = rigid_fleet(2, assumptions)
    capital = first(WindShipOpt.rig_costs(fleet, assumptions))
    airframes = WindShipOpt.rigid_airframe_price(fleet, assumptions)
    _, tethers = WindShipOpt.consumable_costs(fleet, assumptions)
    @test WindShipOpt.rig_maintenance(fleet, capital, raised(:rig_maintenance_fraction)) -
          WindShipOpt.rig_maintenance(fleet, capital, assumptions) ≈
          0.01 * (capital - airframes - tethers)
    rotors = WindShipOpt.RotorRig(400.0, Hull(140.0, assumptions), assumptions)
    @test WindShipOpt.upkept_price(WindShipOpt.CombinedRig(fleet, rotors), assumptions) ≈
          airframes + tethers
end

@testset "sizes swept stay within what fits and bracket the given size" begin
    @test WindShipOpt.sizes_around("kite", 3200.0, 16000.0) ==
          [800.0, 1600.0, 3200.0, 6400.0, 12800.0]
    @test WindShipOpt.sizes_around("kite", 6400.0, 16000.0) ==
          [1600.0, 3200.0, 6400.0, 12800.0, 16000.0]
    @test WindShipOpt.sizes_around("kite", 16000.0, 16000.0) == [4000.0, 8000.0, 16000.0]
    @test WindShipOpt.sizes_around("rotors", 800.0, 1221.0) == [400.0, 800.0, 1221.0]
end

@testset "a sweep whose goal cost differs from the size sweep is refused" begin
    goal = Dict("kite" => 2.0, "rotors" => 1.0)
    @test isnothing(WindShipOpt.check_goal_cost("ship", "life", goal, Dict("kite" => 2.0)))
    @test_throws ErrorException WindShipOpt.check_goal_cost("ship", "life", goal,
        Dict("kite" => 2.1))
end

@testset "one rigid kite crashing costs one airframe and half of one tether" begin
    fleet = rigid_fleet(3, assumptions)
    airframes = WindShipOpt.rigid_airframe_price(fleet, assumptions)
    _, tethers = WindShipOpt.consumable_costs(fleet, assumptions)
    @test WindShipOpt.crash_cost(fleet, assumptions) ≈ (airframes + tethers / 2) / 3
end

@testset "each rig is measured against the best other, the leader against the second" begin
    costs = Dict("kite" => 2.0, "wings" => 1.0, "rotors" => 3.0)
    ranked = WindShipOpt.ranked_rivals(costs)
    @test getfield.(ranked, :rig) == ["wings", "kite", "rotors"]
    @test getfield.(ranked, :rival) == ["kite", "wings", "wings"]
    @test getfield.(ranked, :rival_cost) == [2.0, 1.0, 1.0]
    @test isnan(ranked[1].ahead)
    @test getfield.(ranked, :ahead)[2:3] == [1.0, 2.0]
end

@testset "the crashes a year at break-even use up the cost gap exactly" begin
    cost, target, work, crash = 0.012, 0.015, 2e9, 4e5
    crashes = WindShipOpt.events_to_cost(cost, target, work, crash)
    @test cost + crashes * crash / work ≈ target
    @test WindShipOpt.events_to_cost(target, cost, work, crash) == 0
end

module PaperData
using Printf, Statistics, WindShipOpt
assumptions = Main.assumptions
include(joinpath(pkgdir(WindShipOpt), "scripts", "paper_data.jl"))
end

"path and force text `PaperData.write_pattern` writes for the base kite in `wind` at `course`"
function written_pattern(wind, course)
    model, max_force, _ = WindShipOpt.kite_model(800.0, 3.0, assumptions)
    min_elevation = deg2rad(assumptions[:kite_min_elevation])
    paths, forces = IOBuffer(), IOBuffer()
    PaperData.write_pattern(paths, forces, model, max_force, min_elevation, wind, course,
        0.0)
    return String(take!(paths)), String(take!(forces))
end

@testset "the economic and sailing speeds are solved between any speed grid's points" begin
    ship = Ship(ShipDesign(:vlsfo, 140.0; rotor_area=400.0), PaperData.assumptions)
    hourly, wind, angle = 1500.0, 10.0, π / 2
    wear = WindShipOpt.wear_cost(ship.rig, PaperData.assumptions)
    cost(knots) = PaperData.mile_cost(ship, knots, hourly, wind, angle, nothing, wear)
    @test cost(PaperData.economic_speed(ship, hourly, wind, angle)) <=
          (1 + 1e-7) * minimum(cost, 4.0:0.01:(ship.max_speed / WindShipOpt.KNOT))
    force = last(WindShipOpt.best_trim(ship, ship.rig, 5.0, wind, angle))
    sailing = PaperData.sailing_speed(ship, force, wind, angle)
    @test sailing > 4
    @test abs(WindShipOpt.required_thrust(ship, sailing * WindShipOpt.KNOT, wind, angle,
        force)) < 10
end

"""
    recorded_names(recording, node)

Names of the recorded inputs that `node` of `recording` depends on.
"""
function recorded_names(recording, node)
    operation, operands = recording.nodes[node]
    operation == :input && return Set([first(operands)])
    operation == :constant && return Set{String}()
    return union((recorded_names(recording, operand) for operand in operands)...)
end

@testset "a recorded cost is the routed cost, depends on its inputs and has no branch" begin
    ship = Ship(ShipDesign(:methanol, 85.0; kite_area=800.0), assumptions)
    trip = round_trip(ship, corridors..., SyntheticWeather(), [24.0 * 31, 24.0 * 200],
        assumptions)
    names = (:canopy_life, :e_methanol_price, :kite_out_of_service, :discount_rate,
        :kite_crash_rate)
    recording = WindShipOpt.Recording()
    cost = WindShipOpt.record(recording) do
        inputs = WindShipOpt.recorded_inputs(assumptions, names)
        return WindShipOpt.voyage_costs(ship, WindShipOpt.ship_costs(ship, inputs),
            WindShipOpt.state_rigs(ship.rig, assumptions), trip.passages, corridors...,
            inputs).cheaper
    end
    @test cost.value == trip.cost_per_tonne_km
    @test recorded_names(recording, cost.node) == Set(string.(names))
    @test_throws ErrorException cost < 1.0
    @test_throws ErrorException Float64(cost)
end

@testset "a unit lost a year costs its share of one unit, and leaves the routes alone" begin
    design = ShipDesign(:vlsfo, 85.0; rotor_area=200.0)
    trip(inputs) = round_trip(Ship(design, inputs), corridors..., SyntheticWeather(),
        [24.0 * 31, 24.0 * 200], inputs)
    base, lossy = trip(assumptions), trip(with_value(assumptions, :rotor_loss_rate, 0.5))
    @test lossy.fuel_energy == base.fuel_energy
    rig = Ship(design, assumptions).rig
    hours = 24(base.outbound_days + base.return_days + 2assumptions[:port_time_per_call])
    tonne_km = base.cargo * PaperData.tonne_km_per_tonne(corridors...)
    @test (lossy.cost_per_tonne_km - base.cost_per_tonne_km) * tonne_km ≈
          0.5rig.count * WindShipOpt.crash_cost(rig, assumptions) * hours /
          (8760assumptions[:availability])
end

@testset "the pattern data has rows only for conditions where a pattern flies" begin
    @test all(isempty, written_pattern(6.0, 120))
    paths, forces = written_pattern(12.0, 90)
    @test !isempty(paths) && !isempty(forces) && !occursin("NaN", paths * forces)
end

@testset "a round trip's cost parts per tonne-km add up to its cost over its hours" begin
    tonne_km_per_tonne = PaperData.tonne_km_per_tonne(corridors...)
    for design in (ShipDesign(:methanol, 85.0),
        ShipDesign(:methanol, 85.0; wing_area=400.0),
        ShipDesign(:methanol, 85.0; kite_area=800.0))

        ship = Ship(design, assumptions)
        trip = round_trip(ship, corridors..., SyntheticWeather(), [24.0 * 31, 24.0 * 200],
            assumptions)
        io = IOBuffer()
        PaperData.write_costs(io, (; design, assumptions), trip,
            trip.cargo * tonne_km_per_tonne)
        hours, parts... = parse.(Float64, split(chomp(String(take!(io))), ',')[2:end])
        @test hours ≈ 24(trip.outbound_days + trip.return_days +
                     2assumptions[:port_time_per_call]) rtol = 1e-5
        @test sum(parts) ≈ trip.cost_per_tonne_km rtol = 1e-3
    end
end

include("hot_path_checks.jl")
