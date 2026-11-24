# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

using Statistics: mean
using Test
using WindShipOpt
using WindShipOpt: Optim
using WindShipOpt: correlation_allowance, bulb_resistance, friction_coefficient

# Numerical example of Holtrop & Mennen (1982).
const PAPER_ENV = Environment(; water_density=1025.0, water_viscosity=1.1883e-6)
const PAPER_HULL = Hull(; length=205.0, beam=32.0, draft=10.0, displacement_volume=37500.0,
    midship_coefficient=0.98, waterplane_coefficient=0.75, centre_of_buoyancy=-0.75,
    bulb_area=20.0, bulb_height=4.0, transom_area=16.0, stern_shape=10.0,
    appendage_area=50.0, appendage_form_factor=1.5)

assumptions = Assumptions()
corridors = route_corridors(:caribbean, north_atlantic_mask(); ocean_spacing=1440.0,
    lateral_spacing=960.0)

# The study's search is too coarse for the small route differences tested here.
WindShipOpt.ROUTER_SETTINGS[] = WindShipOpt.RouterSettings(time_step=1.5,
    search_speed_stride=2, search_margins=(0.12, 0.2))

route_tables = Dict{Any, RouteTable}()

"""
    shared_route_table(design)

[`RouteTable`](@ref) of `design` under `assumptions` and the router settings in force, built
once for each and shared by every set that asks for it.
"""
shared_route_table(design) =
    get!(route_tables, (design, WindShipOpt.ROUTER_SETTINGS[])) do
        RouteTable(PerformanceTable(Ship(design, assumptions), assumptions))
    end

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

@testset "the coaster family's resistance is evaluated on its waterline length" begin
    for length in (85.0, 140.0)
        hull = Hull(length, assumptions)
        @test hull.waterline_length ≈ assumptions[:waterline_length_ratio] * length
        @test WindShipOpt.block_coefficient(hull) ≈ assumptions[:block_coefficient]
    end
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
              coefficients=bare.wave_coefficients) + together.leeway_drag +
          together.rudder_drag - hull_force.thrust
end

@testset "hull and rudder cancel the side force and yaw moment of rig and wind" begin
    ship = Ship(ShipDesign(:vlsfo, 140.0; kite_area=800.0), assumptions)
    force = RigForce(1e5, 2e5, 2e6, 3e6)
    balance = WindShipOpt.HullBalance(ship, 5.4, force)
    centre = WindShipOpt.lateral_centre(ship.hull)
    @test force.side + balance.rudder_side_force + balance.hull_side_force ≈ 0 atol = 1e-6
    @test force.yaw_moment + balance.rudder_side_force * -ship.hull.length / 2 +
          balance.hull_side_force * centre ≈ 0 atol = 1e-3
end

@testset "a weaker hull side-force slope drifts and costs more, an infinite one nothing" begin
    hull = Hull(140.0, assumptions)
    weak = Hull(; (name => getfield(hull, name) for name in fieldnames(Hull))...,
        side_force_factor=0.5)
    free = Hull(; (name => getfield(hull, name) for name in fieldnames(Hull))...,
        side_force_factor=Inf)
    env = Environment(assumptions)
    leeway, drag = WindShipOpt.leeway_drag(hull, env, 6.0, 3e5)
    @test all(WindShipOpt.leeway_drag(weak, env, 6.0, 3e5) .≈ (2leeway, 2drag))
    @test WindShipOpt.leeway_drag(free, env, 6.0, 3e5) == (0.0, 0.0)
    @test WindShipOpt.lateral_centre(weak) == WindShipOpt.lateral_centre(hull)
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

@testset "steps of a flown cycle give its force and peak and its own apparent wind" begin
    soft, soft_force, _ = WindShipOpt.kite_model(800.0, 3.0, assumptions)
    rigid, rigid_force, = WindShipOpt.rigid_kite_model(54.0, assumptions)
    straight = WindShipOpt.SteeringPattern(π / 2, 0.4, 1.3, deg2rad(15), 0.0)
    weaving = WindShipOpt.SteeringPattern(π / 2, 0.4, 1.3, deg2rad(15), deg2rad(20))
    loop = WindShipOpt.LoopPattern(π / 2, 0.8, 0.3, deg2rad(8))
    for (model, max_force, pattern, wind) in ((soft, soft_force, straight, 12.0),
        (soft, soft_force, weaving, 12.0), (rigid, rigid_force, loop, 30.0))
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
        @test all(WindShipOpt.dot3(step.apparent_wind, step.radial) ≈ wind * step.radial[1]
                  for step in path)
        @test all(model.lowest_angle - 1e-9 <= step.angle_of_attack <=
                  pattern.angle_of_attack + 1e-9 for step in path)
    end
end

@testset "a still kite rests where lift, drag, weight and tether tension balance" begin
    model, max_force, _ = WindShipOpt.kite_model(1600.0, 3.0, assumptions)
    wind = 10.5
    problem = WindShipOpt.PatternProblem(model, max_force,
        deg2rad(assumptions[:kite_min_elevation]), wind, π, 0.0)
    force, still = WindShipOpt.still_kite(problem)
    path = WindShipOpt.PatternStep[]
    WindShipOpt.PatternForce(model, still, wind, max_force; path)
    (; radial, tension) = only(path)
    (; lift, drag) = WindShipOpt.KiteAero(model, still.angle_of_attack)
    load = 0.5model.air_density * wind^2 * model.area
    lift_force = tension .* radial .- (load * drag, 0.0, 0.0) .+
                 (0.0, 0.0, model.mass * model.gravity)
    @test abs(lift_force[1]) < 1e-3 * load * lift
    @test hypot(lift_force...) ≈ load * lift rtol = 1e-4
    @test all(force.force .* load .≈ tension .* radial)
    @test force.lowest_elevation >= deg2rad(assumptions[:kite_min_elevation]) - 1e-6
end

@testset "upwind a kite no pattern pulls forward is held still, pulling back less" begin
    model, max_force, _ = WindShipOpt.kite_model(1600.0, 3.0, assumptions)
    problem = WindShipOpt.PatternProblem(model, max_force,
        deg2rad(assumptions[:kite_min_elevation]), 10.5, π, 0.0)
    swept, parameters = WindShipOpt.optimal_pattern(problem,
        WindShipOpt.pattern_starts(model, π))
    @test first(WindShipOpt.course_force(problem, swept)) < 0
    held, state = WindShipOpt.kite_state(problem, swept, parameters)
    @test state isa WindShipOpt.StillKite
    @test first(WindShipOpt.course_force(problem, swept)) <
          first(WindShipOpt.course_force(problem, held)) < 0
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

@testset "a kite weaves its legs where weaving pulls harder than straight legs" begin
    model, max_force, _ = WindShipOpt.kite_model(800.0, 3.0, assumptions)
    course = deg2rad(120)
    problem = WindShipOpt.PatternProblem(model, max_force,
        deg2rad(assumptions[:kite_min_elevation]), 12.0, course, 0.0)
    _, parameters = WindShipOpt.optimal_pattern(problem, WindShipOpt.pattern_starts(course))
    @test WindShipOpt.pattern_of(parameters).weave > deg2rad(10)
    straight_legs(legs) = problem([legs; 0.0])
    flyable = WindShipOpt.flyable_patterns(problem)
    starts = flyable[partialsortperm(problem.(flyable), 1:3)]
    best_straight = minimum(Optim.minimum(Optim.optimize(straight_legs, start[1:4],
        Optim.NelderMead(), Optim.Options(iterations=200))) for start in starts)
    @test problem(parameters) < best_straight
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

@testset "a kite built for more force gets cloth and reinforcements in proportion" begin
    stronger = with_value(assumptions, :kite_max_force_per_area,
        2assumptions[:kite_max_force_per_area])
    base_canopy, strong_canopy = WindShipOpt.Canopy.((assumptions, stronger), 800.0, 3.0)
    @test WindShipOpt.cloth_weight(stronger) ≈ 2WindShipOpt.cloth_weight(assumptions)
    @test strong_canopy.mass_per_area ≈ 2base_canopy.mass_per_area
    @test strong_canopy.cost_per_area > base_canopy.cost_per_area
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

@testset "the part-load law burns 1 to 7 % more than MAN L21/31 curves at half to 85 % load" begin
    # Specific fuel at 100, 85, 75, 50 and 25 % load [g/kWh], MAN L21/31, p. 137, Tables 1-4.
    curves = ([192.1, 188.9, 188.8, 192.5, 206.2], [197.1, 194.6, 195.2, 201.7, 223.0],
        [189.1, 185.4, 182.6, 186.5, 202.0], [192.7, 189.5, 187.1, 193.0, 214.0],
        [193.1, 190.9, 191.7, 195.5, 215.3], [198.1, 196.6, 198.2, 204.8, 232.9],
        [199.9, 197.6, 196.7, 198.2, 214.9])
    loads = [1.0, 0.85, 0.75, 0.5, 0.25]
    engine = WindShipOpt.Powertrain(; installed_power=1e6, unit_count=1,
        peak_efficiency=0.44, part_load_penalty=assumptions[:part_load_penalty],
        transmission_efficiency=1.0, hotel_load=0.0)
    model = [1 / WindShipOpt.unit_efficiency(engine, load) for load in loads]
    gaps = [100 * (model ./ model[1]) ./ (curve ./ curve[1]) .- 100 for curve in curves]
    middle = [gap[load] for gap in gaps for load in 2:4]
    @test 1 < minimum(middle) && maximum(middle) < 7
    @test all(gap -> -4.5 < gap[5] < 6, gaps)
end

@testset "a soft kite weighs within 5 % of the two SkySails kites" begin
    # Projected area [m^2] and mass with lines [kg], data/kite_masses.csv.
    for (area, built) in ((176.0, 120.0), (312.5, 250.0))
        max_force = 1e3assumptions[:kite_max_force_per_area] * area
        mass = WindShipOpt.soft_kite_mass(area, assumptions[:kite_aspect_ratio], max_force,
            assumptions)
        @test abs(mass / built - 1) < 0.05
    end
end

@testset "hulls fuller than Holtrop's range use the formulas at its limit" begin
    env = Environment(assumptions)
    classes = ship_classes()
    uncapped = with_value(assumptions, :holtrop_max_prismatic, 1.0)
    full = classes["Kamsarmax bulk carrier"]
    capped_hull, free_hull = (Hull(full, values) for values in (assumptions, uncapped))
    @test WindShipOpt.prismatic_coefficient(capped_hull) == 0.85
    @test WindShipOpt.prismatic_coefficient(free_hull) ≈
          0.88 / assumptions[:waterline_length_ratio] / 0.99
    # the true displacement stays, and the calibration still meets the source design
    @test capped_hull.displacement_volume == free_hull.displacement_volume
    service = full.service_speed * WindShipOpt.KNOT
    @test resistance(capped_hull, env, service) ≈ resistance(free_hull, env, service)
    @test capped_hull.resistance_factor > free_hull.resistance_factor
    # less of the excess wave resistance at service speed means more resistance when slow
    slow = 0.7service
    @test resistance(capped_hull, env, slow) > 1.02resistance(free_hull, env, slow)
    # a class inside the range does not move
    inside = classes["VLCC"]
    @test resistance(Hull(inside, assumptions), env, 6.0) ==
          resistance(Hull(inside, uncapped), env, 6.0)
end

# MAN ES (2019, Tables 2-4) power its MR tanker by Holtrop & Mennen with a 6.7 m propeller:
# 90 % SMCR with a 15 % sea margin and a 0.99 shaft at each speed.
@testset "an uncalibrated class hull meets MAN's Holtrop-Mennen power of its source at \
          every speed" begin
    env = Environment(assumptions)
    class = ship_classes()["MR product tanker"]
    hull = Hull(class, assumptions)
    propeller = WindShipOpt.Propeller(hull, 6.7 / class.draft, assumptions)
    ratios = map(((14.0, 6230), (14.5, 7155), (15.1, 8380))) do (knots, rating)
        speed = knots * KNOT
        uncalibrated = resistance(hull, env, speed) / hull.resistance_factor
        delivered_power(propeller, env, speed, uncalibrated) /
        (1e3rating / 1.15 * 0.99)
    end
    @test all(ratio -> 0.95 < ratio < 1.06, ratios)
    @test maximum(ratios) - minimum(ratios) < 0.015
end

# Tillig & Ringsberg (2020) give a lift coefficient of about 9.5 at spin ratio 3.
@testset "rotor coefficients reproduce the ShipCLEAN lift at spin ratio 3" begin
    lift, drag, power = WindShipOpt.rotor_coefficients(3.0)
    @test lift ≈ 9.5 atol = 0.1
    @test 2 < drag < 3
    @test 0 < power < 0.5
end

# Han et al. (2025, Table 1): CFD of a rotor of aspect ratio 6 with an end disc gives 7.70.
@testset "a rotor lifts as CFD of its shape gives at spin ratio 2.5" begin
    rotors = WindShipOpt.RotorRig(800.0, Hull(140.0, assumptions), assumptions)
    lift, _, _ = WindShipOpt.rotor_coefficients(2.5)
    @test rotors.lift_factor * lift ≈ 7.70 rtol = 0.01
end

"""
    uniform_kite(hull, assumptions)

800 m^2 kite whose pattern table holds one force everywhere, towing from the launch mast.
"""
function uniform_kite(hull, assumptions)
    pattern = WindShipOpt.PatternForce((0.3, 0.8, 0.2), 1.0, 0.3)
    return KiteRig(; area=800.0, aspect_ratio=assumptions[:kite_aspect_ratio],
        tether_diameter=0.05, tether_length=300.0,
        reference_height=120.0, max_wind=30.0, min_flight_wind=4.0, launch_min_wind=5.0,
        launch_max_wind=17.0,
        launch_max_wave_height=Inf,
        rough_sea_launch_wind=assumptions[:kite_launch_sea_wind], landing_max_wind=20.0,
        landing_max_wave_height=Inf, max_force=1e6,
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
    kite_point(table, wave_height, hours; speed_index=6, headwind=12.0)

[`SailedPoint`](@ref) of `hours` [h] at routing speed number `speed_index` in a 12 m/s wind
across the ship with `headwind` [m/s] from ahead and waves of `wave_height` [m].
"""
function kite_point(table, wave_height, hours; speed_index=6, headwind=12.0)
    condition = WindShipOpt.SeaCondition(table.table, 12.0, π / 2, wave_height, 8.0,
        π / 2)
    sample = WindShipOpt.EdgeSample(condition, headwind, 0.0, 0.0, 0.0)
    held, flown, stowed, chance = WindShipOpt.held_speed(table, speed_index, sample, true)
    return WindShipOpt.SailedPoint(sample, held, flown, stowed, hours, 0.0, chance)
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
end

@testset "a heavy kite that cannot hang at rest still flies once moving" begin
    model, _, _ = WindShipOpt.kite_model(800.0, 3.0, assumptions)
    at_rest = sqrt(2model.mass * model.gravity /
                   (model.air_density * model.area * maximum(model.polar.lift)))
    wind = 0.8at_rest
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

@testset "no pattern flies under the launch wind" begin
    for area in (800.0, 3200.0)
        model, max_force, _ = WindShipOpt.kite_model(area, 3.0, assumptions)
        launch = WindShipOpt.launch_min_wind(model, assumptions)
        @test launch >= WindShipOpt.min_flight_wind(model, assumptions)
        @test launch >= assumptions[:kite_launch_min_wind]
        for course in deg2rad.(0.0:15.0:180.0)
            problem = WindShipOpt.PatternProblem(model, max_force,
                deg2rad(assumptions[:kite_min_elevation]), launch - 0.5, course, 0.0)
            force, _ = WindShipOpt.optimal_pattern(problem,
                WindShipOpt.pattern_starts(model, course))
            @test !isfinite(force.peak_tension)
        end
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

@testset "threads asking for one kite's pattern table together share one table" begin
    model, max_force, _ = WindShipOpt.kite_model(800.0, 3.0, assumptions)
    winds, courses, side_weights = [7.3], [deg2rad(60.0)], [0.0]
    tables = fetch.([Threads.@spawn WindShipOpt.pattern_table(model, max_force,
                         assumptions, winds, courses, side_weights) for _ in 1:4])
    @test all(table === first(tables) for table in tables)
end

@testset "a pattern table written to disk reads back whole, with no temporary file left" begin
    model, max_force, _ = WindShipOpt.kite_model(800.0, 3.0, assumptions)
    forces = WindShipOpt.pattern_table(model, max_force, assumptions, [7.3],
        [deg2rad(60.0)], [0.0])
    path = joinpath(mktempdir(), "table.bin")
    WindShipOpt.write_pattern_table(path, forces)
    @test readdir(dirname(path)) == ["table.bin"]
    @test WindShipOpt.read_pattern_table(path, size(forces)) == forces
end

@testset "a process asking for a pattern table another is computing reads that one" begin
    model, max_force, _ = WindShipOpt.kite_model(800.0, 3.0, assumptions)
    path = joinpath(mktempdir(), "table.bin")
    other = WindShipOpt.trymkpidlock("$path.pid")
    waiting = Threads.@spawn WindShipOpt.load_pattern_table(model, max_force, assumptions,
        [7.3], [deg2rad(60.0)], [0.0], path)
    sleep(3.0)
    @test !istaskdone(waiting)
    stored = fill(WindShipOpt.PatternForce((1.0, 2.0, 3.0), 4.0, 5.0), 1, 1, 1)
    WindShipOpt.write_pattern_table(path, stored)
    close(other)
    @test fetch(waiting) == stored
end

@testset "a pattern table whose lock a dead node left is computed after all" begin
    model, max_force, _ = WindShipOpt.kite_model(800.0, 3.0, assumptions)
    path = joinpath(mktempdir(), "table.bin")
    write("$path.pid", "4242 a-node-that-died")
    run(`touch -d "10 minutes ago" $path.pid`)
    forces = @test_logs (:warn, r"stale pidfile") WindShipOpt.load_pattern_table(model,
        max_force, assumptions, [7.3], [deg2rad(60.0)], [0.0], path)
    @test isfinite(only(forces).peak_tension)
    @test readdir(dirname(path)) == ["table.bin"]
end

@testset "a kite without flight drag flies where every fixed start misses" begin
    low_drag = WindShipOpt.with_value(assumptions, :kite_flight_drag, 0.0)
    aspect_ratio = assumptions[:kite_aspect_ratio]
    model, max_force, _ = WindShipOpt.kite_model(8000.0, aspect_ratio, low_drag)
    course = deg2rad(120.0)
    flown = only(WindShipOpt.compute_pattern_table(model, max_force, low_drag, [18.0],
        [course], [0.0]))
    thrust = flown.force[1] * cos(course) + flown.force[2] * sin(course)
    @test isfinite(flown.peak_tension)
    @test thrust > 0
    problem = WindShipOpt.PatternProblem(model, max_force,
        deg2rad(low_drag[:kite_min_elevation]), 18.0, course, 0.0)
    starts = WindShipOpt.pattern_starts(course)
    missed, _ = WindShipOpt.optimal_pattern(problem, starts, () -> [])
    @test !isfinite(missed.peak_tension)
    force, _ = WindShipOpt.optimal_pattern(problem, starts)
    @test force.peak_tension == flown.peak_tension
end

@testset "the pattern grid is only searched where no fixed start flies" begin
    aspect_ratio = assumptions[:kite_aspect_ratio]
    model, max_force, _ = WindShipOpt.kite_model(8000.0, aspect_ratio, assumptions)
    course = deg2rad(120.0)
    problem = WindShipOpt.PatternProblem(model, max_force,
        deg2rad(assumptions[:kite_min_elevation]), 15.0, course, 0.0)
    flew, _ = WindShipOpt.optimal_pattern(problem, WindShipOpt.pattern_starts(course),
        () -> error("searched the grid"))
    @test isfinite(flew.peak_tension)
end

@testset "a launch needs the rough-sea wind from a rough sea on, a kite stays up in any sea" begin
    table, prices = kite_coaster()
    passage(points, aloft) = WindShipOpt.kite_passage(table, points, aloft, prices)
    point(sea; speed_index=6, kwargs...) = kite_point(table, sea, 4.0; speed_index,
        kwargs...)
    speed = table.speeds[6]
    rig = table.table.ship.rig
    rough = WindShipOpt.ROUGH_SEA_HEIGHT
    @test WindShipOpt.extra_launch_wind(rig, 0.99rough) == 0
    @test WindShipOpt.extra_launch_wind(rig, rough) == assumptions[:kite_launch_sea_wind]
    _, launched = passage([point(0.0)], false)
    @test launched.launches == 1
    needed = rig.launch_min_wind + assumptions[:kite_launch_sea_wind]
    below = needed - speed - 0.5
    _, too_little = passage([point(rough; headwind=below)], false)
    @test !isfinite(too_little.cost)
    _, below_rough = passage([point(0.99rough; headwind=below)], false)
    @test below_rough.launches == 1
    _, clears = passage([point(rough; headwind=needed - speed + 0.5)], false)
    @test clears.launches == 1
    _, in_gale = passage([point(2.0; headwind=20.0)], false)
    @test !isfinite(in_gale.cost)
    _, kept_up = passage([point(2.0; headwind=20.0)], true)
    @test isfinite(kept_up.cost)
end

@testset "launch and landing give no force while they last and the launch pays both" begin
    table, prices = kite_coaster()
    ship_table = table.table
    @test ship_table.handling_hours ≈
          (assumptions[:kite_launch_minutes] + assumptions[:kite_landing_minutes]) / 60
    point = kite_point(table, 2.0, 4.0)
    start = WindShipOpt.EdgeTally(0.0, 0.0, 0.0, 0, 0)
    launched = WindShipOpt.aloft_tally(ship_table, start, point, true, prices)
    stayed = WindShipOpt.aloft_tally(ship_table, start, point, false, prices)
    @test launched.flight_hours ≈ 4.0 - ship_table.handling_hours
    @test stayed.flight_hours ≈ 4.0
    unworn = ship_table.wear_cost * point.chance * ship_table.handling_hours
    @test launched.cost + unworn > stayed.cost + ship_table.cycle_cost
    short = kite_point(table, 2.0, ship_table.handling_hours / 2)
    brief = WindShipOpt.aloft_tally(ship_table, start, short, true, prices)
    @test brief.flight_hours ≈ -ship_table.handling_hours / 2
    @test isfinite(brief.cost)
end

@testset "a kite lands inside its limits, outside them only when it can neither stay nor \
          have landed" begin
    table, prices = kite_coaster()
    passage(points) = first(WindShipOpt.kite_passage(table, points, true, prices))
    point(headwind) = kite_point(table, 2.0, 1.0; speed_index=3, headwind)
    rig = table.table.ship.rig
    speed = table.speeds[3]
    calm = point(5.0)
    gale = point(rig.landing_max_wind + 2 - speed)
    storm = point(rig.max_wind + 2 - speed)
    @test !WindShipOpt.kite_landable(table.table, speed, gale.headwind, 0.0, 2.0)
    @test WindShipOpt.kite_aloft(table.table, speed, gale.headwind, 0.0)
    @test passage([calm]).forced_landings == 0
    @test !isfinite(passage([gale]).cost)
    stranded = passage([storm])
    @test stranded.forced_landings == 1
    @test stranded.cost ≈ storm.stowed * 3600 * prices.fuel
    landed_first = passage([calm, gale, storm])
    @test isfinite(landed_first.cost) && landed_first.forced_landings == 0
    @test passage([gale, storm]).forced_landings == 1
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

@testset "cycle cost sums crew, flogging, the kite lost, turn and tether bends" begin
    rig = uniform_kite(Hull(140.0, assumptions), assumptions)
    canopy, tether = WindShipOpt.consumable_costs(rig, assumptions)
    control_unit = assumptions[:market_price_factor] *
                   WindShipOpt.rig_price_parts(rig, assumptions).control_unit
    @test WindShipOpt.cycle_cost(rig, assumptions) ≈
          85 + 3.3 / 3000 * canopy + 0.0001 * (control_unit + (canopy + tether) / 2) + 130 +
          8 / 1_000_000 * tether
    @test WindShipOpt.cycle_cost(nothing, assumptions) == 0
end

@testset "every rig's hardware is priced at its bottom-up cost times the market factor" begin
    hull = Hull(140.0, assumptions)
    factor = assumptions[:market_price_factor]
    kite = uniform_kite(hull, assumptions)
    @test first(WindShipOpt.rig_costs(kite, assumptions)) ≈
          factor * sum(WindShipOpt.rig_price_parts(kite, assumptions)) +
          sum(WindShipOpt.consumable_costs(kite, assumptions))
    for rig in (WingRig(800.0, hull, assumptions),
        WingRig(800.0, hull, assumptions; unit=:suction),
        WindShipOpt.RotorRig(800.0, hull, assumptions))
        @test first(WindShipOpt.rig_costs(rig, assumptions)) ≈
              factor * sum(WindShipOpt.rig_price_parts(rig, assumptions))
    end
end

@testset "a kite's winch grows with its force, its cheaper launch mast with its size" begin
    parts(area) = WindShipOpt.kite_price_parts(area, 500area, assumptions)
    deck = WindShipOpt.kite_deck_masses(800.0, 4e5, assumptions)
    @test deck.winch ≈ 400 * assumptions[:winch_mass_per_force]
    @test deck.launch_mast ≈ 1e3assumptions[:launch_mast_mass_per_size] * sqrt(800)
    @test parts(800.0).deck ≈ assumptions[:winch_cost_per_mass] * deck.winch +
                              assumptions[:welded_steel_cost_per_mass] * deck.launch_mast
    @test parts(800.0).control_unit ≈ 400 * assumptions[:control_unit_mass_per_force] *
                                      assumptions[:control_unit_cost_per_mass]
    @test parts(800.0).controls == assumptions[:kite_controls_cost]
    @test parts(800.0).integration ≈ assumptions[:kite_integration_fraction] *
                                     (sum(parts(800.0)) - parts(800.0).integration)
    @test sqrt(5) < parts(16000.0).deck / parts(3200.0).deck < 5
    @test assumptions[:welded_steel_cost_per_mass] <= assumptions[:winch_cost_per_mass]
    skysails = sum(WindShipOpt.kite_deck_masses(600.0, 6e5, assumptions))
    @test skysails ≈ 30e3 rtol = 0.02
    rig = uniform_kite(Hull(140.0, assumptions), assumptions)
    tether = WindShipOpt.rope_mass(rig.tether_diameter, rig.tether_length, assumptions)
    kite = WindShipOpt.soft_kite_mass(rig.area, rig.aspect_ratio, rig.max_force, assumptions)
    @test WindShipOpt.rig_costs(rig, assumptions)[2] ≈ 1e-3(kite + tether +
          sum(WindShipOpt.kite_deck_masses(rig.area, rig.max_force, assumptions)))
end

@testset "the paper's worked example of the 3200 m^2 kite's hardware and tether holds" begin
    area = 3200.0
    force = 1e3assumptions[:kite_max_force_per_area] * area
    @test force ≈ 2.88e6
    hardware = assumptions[:market_price_factor] *
               sum(WindShipOpt.kite_price_parts(area, force, assumptions))
    @test hardware ≈ 1.10e6 rtol = 0.005
    @test sum(WindShipOpt.kite_deck_masses(area, force, assumptions)) ≈ 92e3 rtol = 0.005
    aspect_ratio = assumptions[:kite_aspect_ratio]
    _, _, tether_diameter = WindShipOpt.kite_model(area, aspect_ratio, assumptions)
    tether_length = assumptions[:tether_length_ratio] * sqrt(aspect_ratio * area)
    tether = WindShipOpt.rope_mass(tether_diameter, tether_length, assumptions)
    @test tether ≈ assumptions[:tether_rope_density] * force * tether_length /
                   assumptions[:tether_stress]
    @test tether ≈ 7.6e3 rtol = 0.005
    @test assumptions[:tether_price] * tether ≈ 7.1e5 rtol = 0.005
end

@testset "a rotor price is set against the build-up of the same unit as sold" begin
    folding = only(price for price in WindShipOpt.ROTOR_PRICES if price.retractable)
    fixed = WindShipOpt.RotorPrice(folding.kind, folding.year, folding.height,
        folding.diameter, folding.price, folding.currency, folding.installed, false,
        folding.hicp, folding.source)
    @test WindShipOpt.bottom_up_price(folding, assumptions) ≈
          (1 + assumptions[:retractable_rig_premium]) *
          WindShipOpt.bottom_up_price(fixed, assumptions)
end

@testset "a canopy is the surveyed one with its own cloth, at the market factor" begin
    surveyed = 1.16 * 25 / 18 * 53
    rib_cloth(chord) = 1.17 * 0.101 * (chord - 8.2) / 0.5
    @test WindShipOpt.canopy_cost(assumptions, 8.2) ≈ surveyed
    @test WindShipOpt.canopy_cost(assumptions, 32.0) ≈
          surveyed + (11.0 + 0.031 * 100) * rib_cloth(32.0)
    stronger = with_value(assumptions, :kite_max_force_per_area,
        2assumptions[:kite_max_force_per_area])
    surveyed_cloth = 1.17 * (2.05 + 0.101 * 8.2 / 0.5)
    @test WindShipOpt.canopy_cost(stronger, 32.0) ≈
          surveyed + 0.031 * 100 * surveyed_cloth +
          (11.0 + 0.031 * 200) * rib_cloth(32.0)
    @test WindShipOpt.canopy_price(assumptions, 800.0, 3.0) ≈
          assumptions[:market_price_factor] *
          WindShipOpt.canopy_cost(assumptions, sqrt(800.0 / 3.0))
    rig = uniform_kite(Hull(140.0, assumptions), assumptions)
    @test first(WindShipOpt.consumable_costs(rig, assumptions)) ≈
          WindShipOpt.canopy_price(assumptions, rig.area, rig.aspect_ratio) * rig.area
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

# Expected forces are a hand calculation worked independently of the code.
@testset "wing force follows true wind, shear and ship speed as worked by hand" begin
    env = Environment(assumptions)
    wings = WingRig(800.0, Hull(140.0, assumptions), assumptions)
    setting = (1.0, WindShipOpt.drag_coefficient(wings, 1.0))
    force(angle) = rig_force(wings, env, 10.0, deg2rad(angle), 5.4, setting)
    @test force(90).thrust ≈ 55251 rtol = 1e-3
    @test force(90).side ≈ 41957 rtol = 1e-3
    @test force(45).thrust ≈ 37500 rtol = 1e-3
    @test force(45).side ≈ 102641 rtol = 1e-3
    @test force(150).thrust ≈ 18566 rtol = 1e-3
    @test force(150).side ≈ -8709 rtol = 1e-3
    @test force(180).thrust ≈ 2248 rtol = 1e-3
    @test force(180).side ≈ -12750 rtol = 1e-3
    @test force(0).thrust < 0 < force(0).side
end

"one suction sail of `area` [m^2] on the 140 m ship, at `inputs`"
suction_sail(area, inputs=assumptions) = WingRig(area, Hull(140.0, assumptions), inputs;
    unit=:suction, in_column=ceil(Int, area / 100))

@testset "a suction sail of the VentiFoil's shape holds its published lift, drag and fan \
          power" begin
    pair = suction_sail(32.0)
    @test pair.count == 1
    @test pair.height ≈ sqrt(32.0 * 6.6)
    lift = pair.max_lift_coefficient
    @test lift == 4.9
    @test WindShipOpt.drag_coefficient(pair, lift) ≈ 0.84
    @test WindShipOpt.drag_coefficient(pair, 0.0) ==
          assumptions[:wing_profile_drag_coefficient]
    attached = (lift, WindShipOpt.drag_coefficient(pair, lift))
    @test WindShipOpt.fan_power(pair, attached, 17.0) ≈ 2 * 7.5e3 rtol = 0.01
    @test WindShipOpt.fan_power(pair, attached, 8.5) ≈ 2 * 7.5e3 / 8 rtol = 0.01
end

@testset "a suction sail's fan runs only while its flow is attached and lifts, and it lies \
          down above its highest wind" begin
    env = Environment(assumptions)
    sails = suction_sail(800.0)
    force(setting, wind) = rig_force(sails, env, wind, π / 2, 5.0, setting)
    lifting = (3.0, WindShipOpt.drag_coefficient(sails, 3.0))
    stalled = WindShipOpt.trim_setting(sails, WindShipOpt.TrimRange(25.0, 90.0, 5, 2), 60.0)
    @test force(lifting, 10.0).power > 0
    @test force((0.0, WindShipOpt.drag_coefficient(sails, 0.0)), 10.0).power == 0
    @test force(stalled, 10.0).power == 0
    @test rig_force(WingRig(800.0, Hull(140.0, assumptions), assumptions), env, 10.0,
        π / 2, 5.0, (1.5, 0.1)).power == 0
    calm = WindShipOpt.trim_ranges(sails, env, 8.0, π / 2, 5.0)
    storm = WindShipOpt.trim_ranges(sails, env, 25.0, π / 2, 5.0)
    @test first(calm).high == sails.max_lift_coefficient
    @test only(storm).high == 0
end

@testset "a suction sail is priced and weighed as a wing sail with its own mass and cost \
          per kg" begin
    sails = suction_sail(800.0)
    wings = WingRig(800.0, Hull(140.0, assumptions), assumptions; in_column=2)
    @test sails.height <= assumptions[:suction_reference_height]
    parts = WindShipOpt.rig_price_parts(sails, assumptions)
    @test parts.units == sails.count * assumptions[:wing_unit_cost]
    @test parts.surface ≈ 800 * 1e3assumptions[:suction_mass_per_area] *
                          assumptions[:suction_cost_per_mass]
    @test parts.installation ≈ assumptions[:wing_installation_fraction] *
                               (parts.units + parts.surface)
    @test WindShipOpt.rig_costs(sails, assumptions)[2] ≈
          800 * assumptions[:suction_mass_per_area]
    @test WindShipOpt.rig_price_parts(wings, assumptions).surface ≈
          800 * assumptions[:wing_cost_per_area]
    heavier = with_value(assumptions, :suction_mass_per_area, 0.6)
    @test WindShipOpt.rig_price_parts(suction_sail(800.0, heavier), heavier).surface ≈
          2parts.surface
end

@testset "suction sails stand alone on a design and keep the wing sails' spacing" begin
    hull = Hull(140.0, assumptions)
    ship = Ship(ShipDesign(:ammonia, 140.0; suction_area=800.0), assumptions)
    @test ship.rig isa WingRig && ship.rig.unit == :suction
    @test_throws ArgumentError Ship(ShipDesign(:ammonia, 140.0; suction_area=800.0,
        wing_area=800.0), assumptions)
    most(inputs) = WindShipOpt.most_in_column(1, 800.0, :suction, hull, inputs, 0.0)
    wider = with_value(assumptions, :wing_spacing, 2assumptions[:wing_spacing])
    @test most(wider) == most(assumptions) ÷ 4
    @test isnothing(WingRig(800.0, hull, assumptions; unit=:suction,
        in_column=most(assumptions) + 1))
end

# Expected forces are a hand calculation worked independently of the code.
@testset "rotor force and spin power follow the apparent wind as worked by hand" begin
    env = Environment(assumptions)
    rotors = WindShipOpt.RotorRig(400.0, Hull(140.0, assumptions), assumptions; in_column=2)
    beam = rig_force(rotors, env, 10.0, π / 2, 5.4, 3.0)
    @test beam.thrust ≈ 232396 rtol = 1e-3
    @test beam.side ≈ 221389 rtol = 1e-3
    @test beam.power ≈ 118305 rtol = 1e-3
    close_hauled = rig_force(rotors, env, 10.0, π / 4, 5.4, 3.0)
    @test close_hauled.thrust ≈ 121487 rtol = 1e-3
    @test close_hauled.side ≈ 492992 rtol = 1e-3
    broad = rig_force(rotors, env, 10.0, 5π / 6, 5.4, 3.0)
    @test broad.thrust ≈ 88849 rtol = 1e-3
    @test broad.side ≈ -30519 rtol = 1e-3
    @test rig_force(rotors, env, 10.0, 0.0, 5.4, 3.0) == WindShipOpt.UNREACHABLE_RIG_FORCE
end

# Expected forces are a hand calculation worked independently of the code.
@testset "kite force turns from the wind's frame onto the course as worked by hand" begin
    env = Environment(assumptions)
    kite = Ship(ShipDesign(:methanol, 140.0; kite_area=800.0), assumptions).rig
    force(wind, angle) = rig_force(kite, env, wind, deg2rad(angle), 5.4, 0.0)
    @test force(5.8751, 26.6411).thrust ≈ -177 atol = 5
    @test force(5.8751, 26.6411).side ≈ 63758 rtol = 1e-3
    @test force(6.6205, 50.2378).thrust ≈ 19708 rtol = 1e-3
    @test force(6.6205, 50.2378).side ≈ 77010 rtol = 1e-3
    @test force(8.82947, 86.695695).thrust ≈ 116494 rtol = 1e-3
    @test force(8.82947, 86.695695).side ≈ 320577 rtol = 1e-3
    @test force(11.161535, 114.227745).thrust ≈ 305015 rtol = 1e-3
    @test force(11.161535, 114.227745).side ≈ 346978 rtol = 1e-3
    @test force(13.802571, 148.57094).thrust ≈ 557075 rtol = 1e-3
    @test force(13.802571, 148.57094).side ≈ 184310 rtol = 1e-3
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
    alone = WindShipOpt.RotorRig(800.0, hull, assumptions; in_column=4)
    behind = WindShipOpt.RotorRig(800.0, hull, assumptions; forward_reserve=reserve,
        in_column=4)
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
    for (rig, row_length) in ((WingRig(1500.0, hull, assumptions; in_column=2), deck),
        (WindShipOpt.RotorRig(800.0, hull, assumptions; forward_reserve=reserve,
                in_column=4), deck - reserve))
        positions = first.(WindShipOpt.unit_positions(rig, hull, assumptions))
        @test rig.columns == 1
        @test length(positions) == rig.count > 1
        @test sum(positions) / rig.count ≈ rig.centre_position
        @test all(diff(positions) .≈ row_length / rig.count)
    end
    single = WingRig(100.0, hull, assumptions)
    @test WindShipOpt.unit_positions(single, hull, assumptions) ==
          [(single.centre_position, 0.0)]
end

@testset "rotors stand in two columns near the deck edges where they lose less" begin
    hull = Hull(ship_classes()["Capesize bulk carrier"], assumptions)
    layout(columns, in_column, area) =
        WindShipOpt.column_layout(columns, in_column, area, :rotor, hull, assumptions, 0.0)
    rig = WindShipOpt.RotorRig(3000.0, hull, assumptions; columns=2, in_column=6)
    @test rig.columns == 2 && rig.count == 12
    clearance = assumptions[:rotor_spacing] * rig.diameter
    @test rig.column_offset ≈ (hull.beam - clearance) / 2
    positions = WindShipOpt.unit_positions(rig, hull, assumptions)
    @test length(positions) == rig.count
    @test sort(unique(last.(positions))) ≈ [-rig.column_offset, rig.column_offset]
    @test sum(first.(positions)) / rig.count ≈ rig.centre_position
    @test layout(2, 6, 2000.0).interference_factor >
          layout(1, 12, 2000.0).interference_factor
    @test layout(1, 3, 500.0).interference_factor > layout(2, 3, 500.0).interference_factor
    pair = layout(2, 1, 100.0)
    @test pair.count == 2 && pair.centre_position ≈ WindShipOpt.lateral_centre(hull)
    most = WindShipOpt.most_in_column(1, 3000.0, :rotor, hull, assumptions, 0.0)
    @test !isnothing(layout(1, most, 3000.0)) && isnothing(layout(1, most + 1, 3000.0))
    @test isnothing(layout(2, 1, 20000.0))
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
    midship = WindShipOpt.with_changed(bow;
        rig=WindShipOpt.with_changed(bow.rig; attach_position=0.0))
    @test bow.rig.attach_position ≈ WindShipOpt.launch_mast_position(hull, assumptions)
    @test midship.rig.attach_position == 0
    wind_speed, wind_angle, ship_speed = 8.8295, 86.6957, 5.4 # hand check's beam reach
    balance(ship) = WindShipOpt.HullBalance(ship, ship_speed,
        rig_force(ship.rig, ship.env, wind_speed, deg2rad(wind_angle), ship_speed, 1))
    # midship lies 47 m aft of the lateral centre, the bow mast 4 m ahead of it
    @test balance(midship).rudder_lift_coefficient >
          3balance(bow).rudder_lift_coefficient > 0
    drag(balance) = balance.leeway_drag + balance.rudder_drag
    @test drag(balance(midship)) > drag(balance(bow))
end

@testset "a rig ship is sized near the bare ship in calm water, a kite ship as it" begin
    bare = Ship(ShipDesign(:vlsfo, 140.0), assumptions)
    rotors = Ship(ShipDesign(:vlsfo, 140.0; rotor_area=300.0), assumptions)
    @test rotors.powertrain.installed_power ≈ bare.powertrain.installed_power rtol = 0.02
    kite = Ship(ShipDesign(:methanol, 85.0; kite_area=800.0), assumptions)
    @test kite.powertrain == Ship(ShipDesign(:methanol, 85.0), assumptions).powertrain
end

"""
    table_fuel(table, speed, wind, angle, wave_height=0, wave_period=0, wave_heading=0)

Fuel power [W] the router reads off `table` for a ship without a kite at `speed` [m/s] in
the wind and waves given.
"""
function table_fuel(table, speed, wind, angle, wave_height=0.0, wave_period=0.0,
        wave_heading=0.0)
    slice = WindShipOpt.SpeedSlice(table, speed)
    condition = WindShipOpt.SeaCondition(table, wind, angle, wave_height, wave_period,
        wave_heading)
    return first(WindShipOpt.edge_fuels(table, slice, condition))
end

"Fuel power [W] of the ship of `table` at `speed` [m/s] making `thrust` [N] while its rig
draws `rig_power` [W]"
function speed_fuel(table, speed, thrust, rig_power)
    propeller = WindShipOpt.PropellerLoad(table.ship.propeller, table.ship.env, speed)
    return WindShipOpt.fuel_power(table, propeller, thrust, rig_power)
end

@testset "rotor ships pay for the spin power in the router's edge fuels" begin
    ship = Ship(ShipDesign(:vlsfo, 140.0; rotor_area=300.0), assumptions)
    table = PerformanceTable(ship, assumptions)
    speed, wind, angle = 5.0, 12.0, π / 2
    power = table.rig_power(speed, wind, angle, 0.0)
    @test power > 0
    @test table_fuel(table, speed, wind, angle) ≈
          speed_fuel(table, speed, table.flown_thrust(speed, wind, angle, 0.0), power)
end

@testset "a bare ship's routing fuel adds the waves' resistance, following seas' negative too" begin
    ship = Ship(ShipDesign(:methanol, 140.0), assumptions)
    table = PerformanceTable(ship, assumptions)
    speed, wind, angle, height, period = 2.47, 6.2, 1.0, 5.6, 7.5
    for heading in (0.33, π)
        waves = height^2 * table.wave_resistance(speed, period, heading)
        @test (waves < 0) == (heading < π / 2)
        @test table_fuel(table, speed, wind, angle, height, period, heading) ≈
              speed_fuel(table, speed, table.flown_thrust(speed, wind, angle, 0.0) + waves,
                  0.0)
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
        assumptions; in_column=4)
    port_hours(class) = WindShipOpt.fixed_rig_port_hours(rotors(class), classes[class],
        assumptions)
    coaster = ship_classes()["general cargo coaster"]
    small = WindShipOpt.RotorRig(200.0, Hull(coaster, assumptions), assumptions;
        in_column=2)
    @test WindShipOpt.fixed_rig_port_hours(small, coaster, assumptions) == Inf
    raised = WindShipOpt.RotorRig(150.0, Hull(classes["Panamax container ship"],
            assumptions), assumptions; columns=2)
    @test WindShipOpt.fixed_rig_port_hours(raised, classes["Panamax container ship"],
        assumptions) == Inf
    @test port_hours("Kamsarmax bulk carrier") > port_hours("Ultramax bulk carrier") > 0
    @test port_hours("VLCC") == 0
    @test WindShipOpt.fixed_rig_port_hours(nothing, classes["VLCC"], assumptions) == 0
end

@testset "deck units taller than the tallest built weigh and cost more per m^2 by their \
          size law" begin
    hull = Hull(140.0, assumptions)
    for (unit, area) in ((:wing, 1200.0), (:suction, 400.0), (:rotor, 600.0))
        build(count) = unit == :rotor ?
                       WindShipOpt.RotorRig(area, hull, assumptions; in_column=count) :
                       WingRig(area, hull, assumptions; unit, in_column=count)
        tall, built = build(1), build(4)
        reference = assumptions[Symbol(unit, :_reference_height)]
        exponent = assumptions[Symbol(unit, :_mass_exponent)]
        @test built.height < reference < tall.height
        @test WindShipOpt.size_factor(built, assumptions) == 1
        growth = (tall.height / reference)^(exponent - 2)
        @test WindShipOpt.size_factor(tall, assumptions) ≈ growth
        mass(rig) = WindShipOpt.rig_costs(rig, assumptions)[2]
        @test mass(built) ≈ area * assumptions[Symbol(unit, :_mass_per_area)]
        @test mass(tall) ≈ growth * mass(built)
        surface(rig) = WindShipOpt.rig_price_parts(rig, assumptions).surface
        @test surface(tall) ≈ growth * surface(built)
    end
end

@testset "the EU ETS charges a ship from its threshold tonnage on its route's share" begin
    large, small = Hull(140.0, assumptions), Hull(85.0, assumptions)
    coverage(hull, route) = WindShipOpt.carbon_coverage(hull, route, assumptions)
    @test coverage(large, :caribbean) == coverage(large, :bilbao) == 1
    @test coverage(large, :new_york) == coverage(large, :tubarao) == 0.5
    @test coverage(small, :caribbean) == coverage(large, nothing) == 0
    charge = assumptions[:carbon_price] * assumptions[:vlsfo_carbon_intensity] / 1e9
    price(route) = Ship(ShipDesign(:vlsfo, 140.0), assumptions; route).fuel.price
    @test price(:caribbean) - price(nothing) ≈ charge
    @test price(:new_york) - price(nothing) ≈ charge / 2
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

@testset "a container ship's deck rig stands in raised pairs, and blocks no slot but \
          under a frame or container" begin
    megamax = ship_classes()["Megamax container ship"]
    hull = Hull(megamax, assumptions)
    for unit in (:wing, :suction, :rotor)
        counts = WindShipOpt.layout_counts(400.0, unit, hull, assumptions, 0.0)
        @test !isempty(counts) && all(==(2) ∘ first, counts)
    end
    for design in (ShipDesign(:vlsfo, megamax; suction_area=200.0),
        ShipDesign(:vlsfo, megamax; wing_area=150.0),
        ShipDesign(:vlsfo, megamax; suction_area=600.0),
        ShipDesign(:vlsfo, megamax; wing_area=1600.0))
        raised = Ship(design, assumptions)
        @test WindShipOpt.raised(raised.rig) && raised.rig.columns == 2
        @test WindShipOpt.CargoHold(raised, assumptions).slots == megamax.unit_capacity -
              WindShipOpt.blocked_slots(raised.rig, megamax, assumptions)
    end
    @test WindShipOpt.launch_mast_position(hull, assumptions) ≈
          (0.5 - assumptions[:bow_mast_position]) * megamax.length
    @test WindShipOpt.CargoHold(Ship(ShipDesign(:vlsfo, megamax; kite_area=1000.0),
        assumptions), assumptions).slots == megamax.unit_capacity
    @test_throws ArgumentError Ship(ShipDesign(:vlsfo, megamax; kite_area=1000.0,
        rotor_area=400.0), assumptions)
end

# By hand: 5 degrees seen from 0.31 L aft of the bow by a unit 0.06 L aft of it, L = 398 m.
# Four pairs of 10 m rotors on the Megamax: the forward pair stands 111.9 - 75.6 m ahead of
# the bridge and 15.8 m off the centreline, hiding 2 atan(5 / 39.6) = 14.4 degrees each.
@testset "a unit hiding more of the bridge's view than SOLAS allows carries a camera \
          system" begin
    megamax = ship_classes()["Megamax container ship"]
    hull = Hull(megamax, assumptions)
    widest = 2 * (0.31 - 0.06) * 398 * tand(2.5)
    @test widest ≈ 8.69 atol = 0.01
    ahead = [((0.5 - 0.06) * 398, 0.0)]
    @test WindShipOpt.camera_units(ahead, 0.99widest, hull, assumptions) == 0
    @test WindShipOpt.camera_units(ahead, 1.01widest, hull, assumptions) == 1
    rotors(in_column) = WindShipOpt.RotorRig(1200.0in_column, hull, assumptions;
        columns=2, in_column)
    cameras(rig) = WindShipOpt.rig_price_parts(rig, assumptions).cameras
    @test rotors(4).camera_units == 2
    @test cameras(rotors(4)) == 2assumptions[:camera_system_cost]
    @test rotors(2).camera_units == 0 && cameras(rotors(2)) == 0
    vlcc = Hull(ship_classes()["VLCC"], assumptions)
    @test vlcc.bridge_distance == Inf
    @test WindShipOpt.RotorRig(800.0, vlcc, assumptions; in_column=4).camera_units == 0
end

@testset "raised rotors stand above the stacks on pedestals, in their free wind" begin
    feeder = ship_classes()["feeder container ship"]
    hull = Hull(feeder, assumptions)
    pairs = WindShipOpt.RotorRig(600.0, hull, assumptions; columns=2, in_column=3)
    on_deck = WindShipOpt.RotorRig(600.0, Hull(feeder.length, assumptions), assumptions;
        columns=2, in_column=3)
    @test pairs.count == 6
    @test pairs.pedestal_height ≈
          hull.deck_cargo_height + assumptions[:pedestal_clearance]
    @test pairs.foot_height ≈ on_deck.foot_height + pairs.pedestal_height
    clearance = assumptions[:rotor_spacing] * pairs.diameter
    @test pairs.column_offset ≈ (feeder.beam - clearance) / 2
    @test WindShipOpt.raised(pairs) && !WindShipOpt.raised(on_deck)
    mass(rig) = WindShipOpt.rig_costs(rig, assumptions)[2]
    @test mass(pairs) ≈ mass(on_deck) + 6WindShipOpt.pedestal_mass(pairs, assumptions)
    @test WindShipOpt.pedestal_mass(on_deck, assumptions) == 0
    price = WindShipOpt.rig_price_parts(pairs, assumptions).pedestals
    @test price ≈ 6e3WindShipOpt.pedestal_mass(pairs, assumptions) *
                  assumptions[:welded_steel_cost_per_mass]
end

# By hand, two pairs of 30 x 5 m rotors on the Megamax: at the 20 m/s they stop in, spin
# ratio 47 / 20 = 2.35, lift 0.96 * 7.468 and drag 1.855 give a peak of 0.5 * 1.225 * 20^2 *
# hypot(7.169, 1.855) = 1814 Pa; arm 25.91 + 2.5 + 15 m; wind 1.7 * 1814 * 150 * 43.41 =
# 20.08 MNm on 1.5 * (0.5 + 5) = 8.25 m^2, inertia 1.3 * 69 t * 3 * 43.41 = 11.68 MNm on
# 5 * (5/3 + 1.5) = 15.83 m^2: 3.172 MN/m, an 11.84 mm wall at 268 MPa, which buckles
# between stiffeners 0.76 m apart below cbrt(3.172e6 * 0.76^2 / (pi^2 * 206e9 / 2.73)) =
# 13.50 mm; 1.2 * 7850 * 2 * 6.5 * 0.01350 * 28.41 = 46.97 t. One pair of 60 x 10 m rotors,
# 361.4 t each, at 0.3 Hz: compliance 28.41^3 / 3 + 30 * 28.41^2 + 30^2 * 28.41 = 57427 m^3,
# section 1.5^2 * (5 + 0.25) = 11.81 m^2 per m of wall, (0.6 pi)^2 * 57427 * 361.4e3 /
# (206e9 * 11.81 - (0.6 pi)^2 * 57427 * 0.24 * 216660 * 28.41) = 34.6 mm, thicker than the
# 32.0 mm strength asks.
@testset "a rotor pedestal's wall carries its factored moments without buckling and \
          keeps the rotor's sway above the ship's motions" begin
    hull = Hull(ship_classes()["Megamax container ship"], assumptions)
    rotors = WindShipOpt.RotorRig(600.0, hull, assumptions; columns=2, in_column=2)
    @test rotors.height ≈ 30 && rotors.diameter ≈ 5
    peak = WindShipOpt.rotor_peak_pressure(rotors, assumptions[:air_density])
    @test peak ≈ 1814 rtol = 1e-3
    @test WindShipOpt.pedestal_wall(rotors, assumptions) ≈ 13.50e-3 rtol = 2e-3
    @test WindShipOpt.pedestal_mass(rotors, assumptions) ≈ 46.97 rtol = 2e-3
    tall = WindShipOpt.RotorRig(1200.0, hull, assumptions; columns=2, in_column=1)
    @test tall.height ≈ 60 && tall.diameter ≈ 10
    @test WindShipOpt.pedestal_wall(tall, assumptions) ≈ 34.6e-3 rtol = 2e-3
end

# By hand, the frame under each of the same 30 x 5 m rotors: legs 28.41 m tall and 13.69 m
# apart, arm 15 m; factored wind 1.7 * 1814 * 150 = 462.7 kN, roll 1.3 * 69 t * 3 =
# 269.1 kN, weight 1.3 * 69 t * 9.81 = 880.0 kN. Legs, wind across: (462.7 + 269.1) kN *
# 43.41 / 2 / 15.83 = 1.003 MN/m, above the 0.880 MN/m of wind along; it buckles below
# cbrt(1.003e6 * 0.76^2 / (pi^2 * 206e9 / 2.73)) = 9.20 mm. Beam, wind along: 880.0 kN *
# 13.69 / 4 + 462.7 kN * 15 / 2 = 6.48 MNm on 8.25 m^2, roll 269.1 kN * 13.69 / 4 on
# 15.83 m^2 and its torsion 269.1 kN * 15 / 2 on 2 * 1.5 * 5 m^2: 0.875 MN/m, 8.79 mm;
# 1.2 * 7850 * 13 * (2 * 9.20e-3 * 28.41 + 8.79e-3 * 13.69) = 78.75 t. Its beam spans two
# of the Megamax's 2.5 m rows over the bay, through ten tiers of two TEU: 40 slots a rotor.
@testset "a frame carries a raised rotor over a bay and takes the slots below its beam" begin
    class = ship_classes()["Megamax container ship"]
    hull = Hull(class, assumptions)
    rotors = WindShipOpt.RotorRig(600.0, hull, assumptions; columns=2, in_column=2)
    @test rotors.pedestal == :column
    frame = WindShipOpt.with_pedestal(rotors, :frame)
    walls = WindShipOpt.frame_walls(frame, assumptions)
    @test walls.leg ≈ 9.20e-3 rtol = 2e-3
    @test walls.beam ≈ 8.79e-3 rtol = 2e-3
    @test WindShipOpt.pedestal_mass(frame, assumptions) ≈ 78.75 rtol = 2e-3
    @test WindShipOpt.blocked_slots(frame, class, assumptions) == 4 * 40
    @test WindShipOpt.blocked_slots(rotors, class, assumptions) == 0
    bare = Ship(ShipDesign(:ammonia, class), assumptions)
    hold(rig) = WindShipOpt.CargoHold(WindShipOpt.with_rig(bare, rig), assumptions)
    @test hold(rotors).slots == class.unit_capacity
    @test hold(frame).slots == class.unit_capacity - 160
end

@testset "raised rotors stand on the column or frame of least cost per power saved" begin
    for (name, area) in (("Neo-Panamax container ship", 600.0),
        ("Megamax container ship", 1200.0))
        class = ship_classes()[name]
        bare = Ship(ShipDesign(:ammonia, class), assumptions)
        rotors = WindShipOpt.RotorRig(area, Hull(class, assumptions), assumptions;
            columns=2, in_column=1)
        rig, score = WindShipOpt.cheapest_pedestal(bare, rotors, assumptions)
        scores = [WindShipOpt.layout_score(bare, WindShipOpt.with_pedestal(rotors, pedestal),
                      assumptions) for pedestal in (:column, :frame)]
        @test score == minimum(scores)
        @test rig.pedestal == (:column, :frame)[argmin(scores)]
    end
    neo = ship_classes()["Neo-Panamax container ship"]
    bare = Ship(ShipDesign(:ammonia, neo), assumptions)
    frame = WindShipOpt.with_pedestal(WindShipOpt.RotorRig(600.0, Hull(neo, assumptions),
        assumptions; columns=2, in_column=1), :frame)
    @test WindShipOpt.lost_cargo_cost(bare, frame, assumptions) > 0
    megamax = ship_classes()["Megamax container ship"]
    @test WindShipOpt.lost_cargo_cost(Ship(ShipDesign(:ammonia, megamax), assumptions),
        frame, assumptions) == 0
end

# By hand, a raised wing sail of 400 m^2, 28.3 x 14.1 m, at its highest lift in 20.6 m/s:
# 0.5 * 1.225 * 20.6^2 * 400 * hypot(CL, CD) is its peak force. A containerised suction sail
# of 40 m^2, 16.2 m tall and 12 t: factored wind 66 kN and roll 1.3 * 12 t * 3 = 46.8 kN on
# an arm of 2.5 + 8.1 m pull a twistlock by 112.8 kN * 10.6 / 4.876 - 12 t * 9.81 / 4 = 216
# kN, within its 250 kN; one of 50 m^2, 18.2 m and 15 t, by 298 kN.
@testset "raised wing and suction sails stand on supports sized for their own loads" begin
    class = ship_classes()["Megamax container ship"]
    hull = Hull(class, assumptions)
    wings = WingRig(1600.0, hull, assumptions; columns=2, in_column=2)
    @test WindShipOpt.raised(wings)
    @test WindShipOpt.unit_width(wings) ≈ 14.14 rtol = 1e-3
    lift = wings.max_lift_coefficient
    @test WindShipOpt.peak_force(wings, assumptions) ≈
          0.5assumptions[:air_density] * assumptions[:wing_design_wind]^2 * 400 *
          hypot(lift, WindShipOpt.drag_coefficient(wings, lift))
    rotors = WindShipOpt.RotorRig(1600.0, hull, assumptions; columns=2, in_column=2)
    @test WindShipOpt.pedestal_mass(wings, assumptions) > 0
    @test WindShipOpt.fixed_rig_port_hours(wings, class, assumptions) == Inf
    @test !WindShipOpt.container_holds(wings, assumptions)
    @test !WindShipOpt.container_holds(rotors, assumptions)
    suction(unit_area) = WingRig(4unit_area, Hull(ship_classes()["feeder container ship"],
            assumptions), assumptions; unit=:suction, columns=2, in_column=2)
    @test WindShipOpt.container_holds(suction(40.0), assumptions)
    @test !WindShipOpt.container_holds(suction(50.0), assumptions)
    boxed = WindShipOpt.with_pedestal(suction(40.0), :container)
    feeder = ship_classes()["feeder container ship"]
    @test WindShipOpt.pedestal_mass(boxed, assumptions) == 0
    @test WindShipOpt.blocked_slots(boxed, feeder, assumptions) == 8
    @test WindShipOpt.fixed_rig_port_hours(boxed, feeder, assumptions) == 0
end

# Norsepower's 35 x 5 m rotor gives a maximum continuous thrust of 350 kN.
@testset "a rotor's peak force is that of the largest built rotor" begin
    rotor = WindShipOpt.RotorRig(175.0, Hull(140.0, assumptions), assumptions)
    peak = WindShipOpt.rotor_peak_pressure(rotor, assumptions[:air_density]) * 175
    @test peak ≈ 350e3 rtol = 0.1
end

@testset "a deck rig takes the unit count of least yearly cost per power saved" begin
    class = ship_classes()["Kamsarmax bulk carrier"]
    design = ShipDesign(:vlsfo, class; rotor_area=800.0)
    ship = Ship(design, assumptions)
    score(in_column) = WindShipOpt.layout_score(ship,
        WindShipOpt.design_rig(design, ship.hull, assumptions; in_column), assumptions)
    chosen = ship.rig.count
    @test ship.rig.columns == 1
    @test all(score(chosen) <= score(count) for count in 1:(chosen + 3))
    winds = WindShipOpt.layout_winds(assumptions)
    @test length(winds) == 24
    @test sum(first, winds) / 24 ≈ assumptions[:layout_mean_wind] rtol = 0.05
end

@testset "empty boxes take container slots and tare but carry no cargo" begin
    teu = WindShipOpt.CargoUnit(:teu, assumptions)
    loaded = 1 - assumptions[:empty_container_share]
    @test teu.cargo ≈ loaded * assumptions[:cargo_per_teu]
    @test teu.mass - teu.cargo ≈ assumptions[:teu_tare_mass]
end

@testset "a class ship's drive delivers the shaft power of its source engine" begin
    class = ship_classes()["feeder container ship"]
    shaft = 1e3class.power * assumptions[:direct_shaft_efficiency]
    for drive in (:vlsfo, :methanol, :ammonia)
        powertrain = Ship(ShipDesign(drive, class), assumptions).powertrain
        output = powertrain.installed_power - powertrain.hotel_load
        @test output * powertrain.transmission_efficiency ≈ shaft
    end
end

@testset "a class's two-stroke and the coaster family's four-stroke burn at their own \
          efficiencies" begin
    kamsarmax = ship_classes()["Kamsarmax bulk carrier"]
    for drive in (:vlsfo, :ammonia)
        efficiency(design) = Ship(design, assumptions).powertrain.peak_efficiency
        @test efficiency(ShipDesign(drive, kamsarmax)) ==
              assumptions[:two_stroke_engine_efficiency]
        @test efficiency(ShipDesign(drive, 140.0)) ==
              assumptions[:four_stroke_engine_efficiency]
    end
end

@testset "the coaster class is the reference coaster, engine and power alike" begin
    class = Ship(ShipDesign(:vlsfo, ship_classes()["general cargo coaster"]), assumptions)
    reference = Ship(ShipDesign(:vlsfo, 85.0), assumptions)
    @test class.powertrain.installed_power ≈ reference.powertrain.installed_power
    @test class.powertrain.peak_efficiency == reference.powertrain.peak_efficiency
    @test class.powertrain.transmission_efficiency ==
          reference.powertrain.transmission_efficiency
end

@testset "a class hull's calm-water delivered power at service speed matches its \
          source design" begin
    for class in values(ship_classes())
        isnan(class.source_load) && continue
        ship = Ship(ShipDesign(:vlsfo, class), assumptions)
        speed = class.service_speed * KNOT
        thrust = resistance(ship.hull, ship.env, speed)
        shaft = assumptions[:direct_shaft_efficiency]
        source = 1e3class.power * class.source_load * shaft /
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
        @test isfinite(table_fuel(table, speed, 0.0, 0.0))
        next_to_infeasible = 1e-3WindShipOpt.INFEASIBLE_THRUST
        @test isinf(speed_fuel(table, speed, next_to_infeasible, 0.0))
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
    design = ShipDesign(:methanol, 85.0; wing_area=400.0)
    ship = Ship(design, assumptions)
    table = shared_route_table(design)
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
    ratio = 8 / assumptions[:kite_aspect_ratio]
    slender = KiteRig(; (name => getfield(base, name) for name in fieldnames(KiteRig))...,
        tether_length=base.tether_length * sqrt(ratio))
    prices = WindShipOpt.with_kite_aspect_ratio(assumptions, 8.0)
    @test prices[:kite_aspect_ratio] == 8.0
    @test WindShipOpt.rig_price_parts(slender, prices) ==
          WindShipOpt.rig_price_parts(base, assumptions)
    @test WindShipOpt.wear_cost(slender, prices) ≈ WindShipOpt.wear_cost(base, assumptions)
    @test WindShipOpt.cycle_cost(slender, prices) ≈
          WindShipOpt.cycle_cost(base, assumptions)
    @test WindShipOpt.handling_hours(slender, prices) ==
          WindShipOpt.handling_hours(base, assumptions)
end

@testset "a kite flies the assumed aspect ratio unless its design names its own" begin
    slender = WindShipOpt.with_value(assumptions, :kite_aspect_ratio, 4.0)
    @test WindShipOpt.kite_aspect_ratio(ShipDesign(:vlsfo, 100.0; kite_area=800.0),
        slender) == 4.0
    @test WindShipOpt.kite_aspect_ratio(ShipDesign(:vlsfo, 100.0; kite_area=800.0,
        kite_aspect_ratio=5.0), slender) == 5.0
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

@testset "launch cost at the loss goal is mostly crew, flogging and turn" begin
    kite = Ship(ShipDesign(:methanol, 140.0; kite_area=800.0), assumptions).rig
    flogging = assumptions[:kite_cycle_canopy_hours] / assumptions[:canopy_life] *
               first(WindShipOpt.consumable_costs(kite, assumptions))
    unlost = assumptions[:kite_cycle_crew_cost] + flogging +
             assumptions[:kite_cycle_course_cost]
    @test unlost < WindShipOpt.cycle_cost(kite, assumptions) < 1.2unlost
end

@testset "a rig out of service keeps its cost and saves no fuel while down" begin
    bare_trip = round_trip(Ship(ShipDesign(:methanol, 85.0), assumptions), corridors...,
        SyntheticWeather(), [24.0 * 31, 24.0 * 200], assumptions)
    for (design, name) in ((ShipDesign(:methanol, 85.0; wing_area=400.0),
            :wing_out_of_service),
        (ShipDesign(:methanol, 85.0; rotor_area=200.0), :rotor_out_of_service),
        (ShipDesign(:methanol, 85.0; kite_area=800.0), :kite_out_of_service))
        low, high, down = fetch.([Threads.@spawn trip_with_share(design, name, share)
                                  for share in (0.1, 0.5, 1.0)])
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
                    24assumptions[:port_time_per_call], nothing, nothing)
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

@testset "a kite out of service makes and pays launches pro rata" begin
    kite = ShipDesign(:methanol, 85.0; kite_area=800.0)
    working = trip_with_share(kite, :kite_out_of_service, 0.0)
    half = trip_with_share(kite, :kite_out_of_service, 0.5)
    @test working.launches > 0
    @test half.launches ≈ working.launches / 2
    lossy = with_value(assumptions, :kite_launch_loss_probability, 1e-2)
    @test trip_with_share(kite, :kite_out_of_service, 0.5, lossy).cost_per_tonne_km >
          half.cost_per_tonne_km
end

@testset "stopped rotors and feathered wings are only drag in a head wind" begin
    for design in (ShipDesign(:methanol, 85.0; wing_area=400.0),
        ShipDesign(:methanol, 85.0; rotor_area=200.0))
        ship = Ship(design, assumptions)
        down = WindShipOpt.DownRig(ship.rig, 0.0)
        bare_thrust = WindShipOpt.best_trim(ship, nothing, 5.0, 10.0, 0.0).thrust
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
    @test WindShipOpt.input_at_cost(prices, costs, 2.0) ≈ 225
    @test isnan(WindShipOpt.input_at_cost(prices, costs, 1.0))
    @test isnan(WindShipOpt.input_at_cost(prices, costs, 3.0))
    @test isnan(WindShipOpt.input_at_cost(prices, costs, NaN))
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
    leg = route(corridor, table, weather, departure; time_cost=hourly)
    searched = WindShipOpt.route_pass(workspace, corridor, table, weather, departure;
        time_cost=hourly, time_step, first_stage=1, first_lateral=centre_index(corridor),
        first_aloft=false, speed_stride=search_speed_stride)
    full = WindShipOpt.final_pass(searched, corridor, table, weather, departure;
        time_cost=hourly, first_stage=1, first_aloft=false)
    @test leg.objective == full.objective
    @test leg.path == full.path
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
        step, 0.0, commanded, false)
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

@testset "a liner keeps the time of its ship without a rig and takes the gain as fuel" begin
    liner = ship_classes()["Panamax container ship"]
    tramp = ShipClass(; (name => getfield(liner, name) for name in fieldnames(ShipClass))...,
        liner=false)
    departures = [24.0 * 31, 24.0 * 200]
    trip(class; rig...) = round_trip(Ship(ShipDesign(:ammonia, class; rig...), assumptions),
        corridors..., SyntheticWeather(), departures, assumptions)
    days(trip) = trip.outbound_days + trip.return_days
    # Every speed: on every other one the liner's next slower speed can miss its schedule.
    every_speed = WindShipOpt.RouterSettings(time_step=1.5, search_speed_stride=1,
        search_margins=(0.12, 0.2))
    bare, bare_tramp, scheduled, free = WindShipOpt.with_router_settings(every_speed) do
        return trip(liner), trip(tramp), trip(liner; rotor_area=500.0),
        trip(tramp; rotor_area=500.0)
    end
    @test days(free) < 0.99days(bare)
    @test days(free) < days(scheduled) <= days(bare)
    @test scheduled.fuel_energy < free.fuel_energy
    @test days(bare_tramp) == days(bare)
end

@testset "a leg arrives by its time on the least fuel that does" begin
    ship = Ship(ShipDesign(:ammonia, ship_classes()["Panamax container ship"];
        rotor_area=500.0), assumptions)
    table = RouteTable(PerformanceTable(ship, assumptions))
    time_cost = first(WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions), assumptions))
    sail(arrival_by) = route(first(corridors), table, SyntheticWeather(), 24.0 * 31;
        time_cost, arrival_by)
    free = sail(Inf)
    later, earlier = sail(free.duration + 24), sail(free.duration - 12)
    @test free.duration < later.duration <= free.duration + 24
    @test later.fuel_energy < free.fuel_energy
    @test earlier.duration <= free.duration - 12
    @test earlier.fuel_energy > free.fuel_energy
    @test sail(1.0).duration <= minimum(sail(hours).duration for hours in (Inf, 100.0))
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
            24.0, speed_index, false, sample_hours * 1.001)
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

@testset "a ship re-planning on the real weather sails close to perfect foresight" begin
    weather, departure = SyntheticWeather(), 24.0 * 31
    leg = route(corridor, table, weather, departure; time_cost=hourly)
    sailed = forecast_route(corridor, table, weather, departure; time_cost=hourly)
    @test length(sailed.path) == size(corridor.lat, 1)
    @test sailed.path[end][1:2] == leg.path[end][1:2]
    @test sailed.objective ≈ leg.objective rtol = 0.01
    @test sailed.duration > 0 && sailed.fuel_energy > 0
end

"the result of `call()` by a planner that plans on the whole corridor, as `route` does"
on_whole_corridor(call) = WindShipOpt.with_router_settings(call,
    WindShipOpt.with_changed(WindShipOpt.ROUTER_SETTINGS[]; near_distance=Inf))

"departures [h] a month apart over a year of synthetic weather"
monthly_departures = 24.0 .* (1:30:331)

"routing table and hourly time cost of the 85 m methanol ship with a kite of `kite_area`"
function forecast_kite_routing(kite_area)
    design = ShipDesign(:methanol, 85.0; kite_area)
    ship = Ship(design, assumptions)
    kite_hourly = first(WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions),
        assumptions))
    return shared_route_table(design), kite_hourly
end

"""
the passage sailed from `departure` [h] on `kite_table` re-planning every forecast on the
whole corridor, with the weather it plans on the weather it meets

The default search keeps one kite state per node and time bin by its kite rule, which can
drop an arrival a re-plan from later in the passage keeps: there a re-plan leaves its plan,
and sails cheaper.
"""
sailed_on_planned_weather(kite_table, kite_hourly, weather, departure) =
    on_whole_corridor() do
        forecast_route(corridor, kite_table, weather, departure; time_cost=kite_hourly)
    end

"""
the result of `call()` by a planner whose final pass re-times the path found by up to a day,
the reference its default band is checked against
"""
on_day_wide_final_pass(call) = WindShipOpt.with_router_settings(call,
    WindShipOpt.with_changed(WindShipOpt.ROUTER_SETTINGS[]; final_time_band=24.0))

@testset "a ship on the real weather flies its kite about as the plan does" begin
    kite_table, kite_hourly = forecast_kite_routing(800.0)
    weather = SyntheticWeather()
    on_day_wide_final_pass() do
        for departure in monthly_departures
            leg = route(corridor, kite_table, weather, departure; time_cost=kite_hourly)
            sailed = sailed_on_planned_weather(kite_table, kite_hourly, weather, departure)
            @test leg.launches > 0
            flies_as_planned = sailed.launches == leg.launches &&
                               isapprox(sailed.flight_hours, leg.flight_hours; rtol=0.025)
            @test flies_as_planned || sailed.objective < leg.objective
            @test sailed.objective ≈ leg.objective rtol = 1e-3
        end
    end
end

@testset "a ship re-planning on the weather it planned on keeps the rest of its plan" begin
    kite_table, kite_hourly = forecast_kite_routing(800.0)
    weather = SyntheticWeather()
    for departure in 24.0 .* (301, 331)
        leg = route(corridor, kite_table, weather, departure; time_cost=kite_hourly)
        stage = findfirst(point -> point[3] >= 24, leg.path)
        lat, lon, time = leg.path[stage]
        lateral = WindShipOpt.nearest_lateral(corridor, stage, lat, lon)
        rest = on_whole_corridor() do
            planning, first_stage = WindShipOpt.planning_corridor(corridor, stage, lateral)
            route(planning, kite_table, weather, departure + time; time_cost=kite_hourly,
                first_stage, first_lateral=lateral, first_aloft=leg.aloft[stage])
        end
        keeps_plan = [point[4] for point in rest.path] ==
                     [0.0; [point[4] for point in leg.path[(stage + 1):end]]] &&
                     rest.aloft == leg.aloft[stage:end]
        @test keeps_plan || sailed_on_planned_weather(kite_table, kite_hourly, weather,
            departure).objective < leg.objective
    end
end

@testset "a re-plan weighs the plan a ship holds only where it still arrives in time" begin
    kite_table, kite_hourly = forecast_kite_routing(800.0)
    lateral = centre_index(corridor)
    planning, first_stage = WindShipOpt.planning_corridor(corridor, 1, lateral)
    held = route(planning, kite_table, SyntheticWeather(), 24.0 * 61; time_cost=kite_hourly,
        first_stage, first_lateral=lateral)
    candidates(arrival_by) = WindShipOpt.candidate_plans(nothing, held, planning,
        first_stage, lateral, arrival_by)
    @test candidates(Inf) == candidates(held.duration) == [held]
    @test isempty(candidates(held.duration - 1))
end

@testset "a kite flying in good wind stays up unless the plan ahead needs it stowed" begin
    kite_table, kite_hourly = forecast_kite_routing(800.0)
    _, homeward = corridors
    weather, departure = SyntheticWeather(), 24.0 * 121
    leg = route(homeward, kite_table, weather, departure; time_cost=kite_hourly)
    i = findfirst(i -> leg.aloft[i] && leg.aloft[i + 1], 1:(length(leg.path) - 1))
    lateral = WindShipOpt.nearest_lateral(homeward, i, leg.path[i][1], leg.path[i][2])
    next = WindShipOpt.nearest_lateral(homeward, i + 1, leg.path[i + 1][1],
        leg.path[i + 1][2])
    prices = (; fuel=kite_table.table.ship.fuel.price, time=kite_hourly)
    sail(ahead) = WindShipOpt.sail_planned_edge!(WindShipOpt.SailedPoint[], kite_table,
        weather, homeward, i, lateral, WindShipOpt.lateral_step(homeward, lateral, next),
        departure + leg.path[i][3], leg.path[i + 1][4], true, ahead, prices)
    @test sail((0.0, 0.0))[3]
    @test !sail((0.0, Inf))[3]
end

"Synthetic weather with a gale from the south-west no ship can sail in before `calm_from`."
struct GaleWeather
    calm::SyntheticWeather
    calm_from::Float64
end
WindShipOpt.wind(weather::GaleWeather, lat, lon, time) =
    time < weather.calm_from ? (45.0, 45.0) : WindShipOpt.wind(weather.calm, lat, lon, time)
WindShipOpt.waves(weather::GaleWeather, lat, lon, time) =
    time < weather.calm_from ? (16.0, 14.0, 1.25π) : (0.0, 0.0, 0.0)

"Steady wind from the south on a sea whose waves push a ship heading east along."
struct FollowingSeaWeather end
WindShipOpt.wind(::FollowingSeaWeather, lat, lon, time) = (0.0, 14.0)
WindShipOpt.waves(::FollowingSeaWeather, lat, lon, time) = (16.0, 14.0, 1.25π)

@testset "a leg's trace shows the trim the router priced and the leeway it sails at" begin
    ship = Ship(ShipDesign(:vlsfo, 140.0; rotor_area=400.0), assumptions)
    table = RouteTable(PerformanceTable(ship, assumptions))
    trace = WindShipOpt.LegTrace((Float64[] for _ in 1:15)..., (Bool[] for _ in 1:4)...,
        Any[])
    calm_sea = WindShipOpt.SeaCondition(table.table, 0.0, 0.0, 0.0, 8.0, 0.0)
    point = WindShipOpt.SailedPoint(0.0, 0.0, calm_sea,
        searchsortedfirst(table.speeds, 5.0), 0.0, 0.0, 1.0, 24.0 * 31, 0.0)
    WindShipOpt.push_trace_point!(trace, table, FollowingSeaWeather(), 24.0 * 31, 30.0,
        -30.0, π / 2, point, 1.0, true, false, false, false)
    first_knot = first(table.table.flown_thrust.knots[4])
    priced = WindShipOpt.best_trim(ship, ship.rig, only(trace.speed), 14.0,
        only(trace.true_wind_angle), first_knot).force
    @test only(trace.rig_thrust) == priced.thrust
    windage = WindShipOpt.wind_force(ship.windage, ship.env, 14.0,
        only(trace.true_wind_angle), only(trace.speed))
    @test only(trace.leeway) ==
          WindShipOpt.HullBalance(ship, only(trace.speed), priced + windage).leeway > 0
end

@testset "the stages and the rows of a corridor are spaced apart" begin
    mask = north_atlantic_mask()
    node_spacing(corridor) = WindShipOpt.distance(corridor.lat[end, 1],
        corridor.lon[end, 1], corridor.lat[end, 2], corridor.lon[end, 2]) /
                             WindShipOpt.NAUTICAL_MILE
    coarse = first(route_corridors(:caribbean, mask; ocean_spacing=1440.0,
        lateral_spacing=960.0))
    finer_rows = first(route_corridors(:caribbean, mask; ocean_spacing=1440.0,
        lateral_spacing=480.0))
    finer_stages = first(route_corridors(:caribbean, mask; ocean_spacing=720.0,
        lateral_spacing=960.0))
    @test node_spacing(coarse) ≈ 960.0 rtol=1e-3
    @test node_spacing(finer_rows) ≈ 480.0 rtol=1e-3
    @test node_spacing(finer_stages) ≈ 960.0 rtol=1e-3
    @test size(finer_rows.lat, 1) == size(coarse.lat, 1)
    @test size(finer_rows.lat, 2) > size(coarse.lat, 2)
    @test size(finer_stages.lat, 1) > size(coarse.lat, 1)
    @test size(finer_stages.lat, 2) == size(coarse.lat, 2)
end

"Forecast source that always plans on `weather`, whatever the real weather is."
struct FixedForecast{W}
    weather::W
end
WindShipOpt.known_weather(source::FixedForecast, weather, time) = source.weather

@testset "a ship on a forecast holds through a gale it cannot sail in" begin
    corridor, _ = route_corridors(:caribbean, north_atlantic_mask(); ocean_spacing=720.0,
        lateral_spacing=480.0)
    departure = 24.0 * 31
    weather = GaleWeather(SyntheticWeather(), departure + 10.0)
    @test isnothing(route(corridor, table, weather, departure; time_cost=hourly))
    after = route(corridor, table, weather, departure + 12.0; time_cost=hourly)
    ship = table.table.ship
    hotel = 3600WindShipOpt.fuel_power(ship.powertrain, 0.0) * ship.fuel.price
    held = 12.0 * (hotel + hourly)
    calm = FixedForecast(SyntheticWeather())
    for (forecast, tolerance) in ((nothing, 0.005), (calm, 0.02))
        sailed = forecast_route(corridor, table, weather, departure; time_cost=hourly,
            forecast)
        @test length(sailed.path) == size(corridor.lat, 1)
        @test sailed.path[2][3] > 12.0
        @test sailed.objective - held ≈ after.objective rtol = tolerance
    end
    endless = GaleWeather(SyntheticWeather(), Inf)
    @test isnothing(forecast_route(corridor, table, endless, departure; time_cost=hourly))
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
Synthetic weather with 5 m head seas and a wind 60 degrees off the bow on the first edge
from `start`, in which only a kite flying holds more than 4 kn, yet the seas forbid
launching it.
"""
struct KiteOnlySeas
    calm::SyntheticWeather
    start::NTuple{2, Float64}
    course::Float64
end
rough_seas(weather::KiteOnlySeas, lat, lon, time) =
    WindShipOpt.distance(lat, lon, weather.start...) < 200NAUTICAL_MILE
WindShipOpt.wind(weather::KiteOnlySeas, lat, lon, time) =
    rough_seas(weather, lat, lon, time) ?
    -8.0 .* sincos(weather.course + deg2rad(60)) :
    WindShipOpt.wind(weather.calm, lat, lon, time)
WindShipOpt.waves(weather::KiteOnlySeas, lat, lon, time) =
    rough_seas(weather, lat, lon, time) ? (5.0, 10.0, weather.course) : (0.0, 0.0, 0.0)

@testset "a ship on a forecast slows where its kite cannot launch as planned" begin
    kite_table, kite_hourly = forecast_kite_routing(800.0)
    centre, step = centre_index(corridor), WindShipOpt.MAX_LATERAL_STEP + 1
    seas = KiteOnlySeas(SyntheticWeather(), (corridor.lat[1, centre],
            corridor.lon[1, centre]), corridor.edge_course[1, centre, step])
    sailed = forecast_route(corridor, kite_table, seas, 24.0 * 31; time_cost=kite_hourly,
        forecast=FixedForecast(SyntheticWeather()))
    @test length(sailed.path) == size(corridor.lat, 1)
    edge_hours = sailed.path[2][3] - sailed.path[1][3]
    @test corridor.edge_length[1, centre, step] / (edge_hours * 3600) < 5KNOT
end

@testset "an issue counts as issued only where every field of its archive holds data" begin
    grid = WindShipOpt.GriddedFields([40.0], [-30.0], 6.0, 6.0, 2,
        Dict{String, Array{Float32, 3}}())
    names = ("height", "period", "direction_east", "direction_north")
    issues(hole) = cat(ones(Float16, 2, 2, 2, 1), fill(hole, 2, 2, 2, 1); dims=4)
    for hole in (NaN16, zero(Float16))
        whole = WindShipOpt.ArchiveGroup(grid,
            Dict(name => ones(Float16, 2, 2, 2, 2) for name in names),
            Dict{Int, Dict{String, Array{Float32, 3}}}(),
            Dict{Int, Array{Float32, 3}}(), 0.0, 24.0)
        @test WindShipOpt.issued_in(whole, 2)
        for missing_field in names
            group = WindShipOpt.ArchiveGroup(grid,
                Dict(name => name == missing_field ? issues(hole) :
                             ones(Float16, 2, 2, 2, 2) for name in names),
                Dict{Int, Dict{String, Array{Float32, 3}}}(),
                Dict{Int, Array{Float32, 3}}(), 0.0, 24.0)
            @test WindShipOpt.issued_in(group, 1)
            @test !WindShipOpt.issued_in(group, 2)
        end
    end
end

"""
The real `weather` with `east` [m/s] added to its east wind, as a forecast that errs.
"""
struct BiasedWeather{W}
    weather::W
    east::Float64
end
function WindShipOpt.wind(biased::BiasedWeather, lat, lon, time)
    east, north = WindShipOpt.wind(biased.weather, lat, lon, time)
    return east + biased.east, north
end
WindShipOpt.waves(biased::BiasedWeather, lat, lon, time) =
    WindShipOpt.waves(biased.weather, lat, lon, time)

"""
Forecast source that plans on `error` [m/s] of east wind added to the real weather, and
counts the plans made.
"""
mutable struct CountedForecast
    error::Float64
    plans::Int
end
function WindShipOpt.known_weather(source::CountedForecast, weather, time)
    source.plans += 1
    return BiasedWeather(weather, source.error)
end

@testset "a ship re-plans at the first node its interval after the last plan" begin
    departure, source = 24.0 * 31, CountedForecast(0.0, 0)
    every_node = forecast_route(corridor, table, SyntheticWeather(), departure;
        time_cost=hourly, forecast=ReplannedForecast(source; interval=0.0))
    @test source.plans == size(corridor.lat, 1) - 1
    @test every_node.path[end][3] > 0
    source.plans = 0
    daily = forecast_route(corridor, table, SyntheticWeather(), departure;
        time_cost=hourly, forecast=ReplannedForecast(source))
    @test 1 <= source.plans < size(corridor.lat, 1) - 1
    plain = forecast_route(corridor, table, SyntheticWeather(), departure;
        time_cost=hourly, forecast=CountedForecast(0.0, 0))
    @test daily.objective == plain.objective
end

@testset "the weather a ship expects is the forecast plus the error it meets" begin
    real, biased = SyntheticWeather(), BiasedWeather(SyntheticWeather(), 4.0)
    lat, lon, time = 30.0, -30.0, 24.0 * 40
    met = WindShipOpt.MetWeather(biased, real, lat, lon, time)
    @test all(WindShipOpt.wind(met, lat, lon, time) .≈ WindShipOpt.wind(real, lat, lon, time))
    east, north = WindShipOpt.wind(biased, 33.0, -35.0, time + 6.0)
    @test WindShipOpt.wind(met, 33.0, -35.0, time + 6.0) == (east - 4.0, north)
    @test WindShipOpt.waves(met, lat, lon, time)[1] == WindShipOpt.waves(real, lat, lon, time)[1]
    calmer = WindShipOpt.MetWeather(biased, biased, lat, lon, time)
    @test calmer.east_error == 0.0
end

"""
The 85 m methanol ship with a kite of `area` [m²], on the finer Caribbean corridor, as its
route table, hourly time cost of the outbound leg and that corridor.
"""
function kite_coaster_routing(area)
    kite_table, kite_hourly = forecast_kite_routing(area)
    finer, _ = route_corridors(:caribbean, north_atlantic_mask(); scale=8)
    return kite_table, kite_hourly, finer
end

@testset "a ship sailing live recovers more of a wrong forecast than one holding speed" begin
    kite_table, kite_hourly, finer = kite_coaster_routing(400.0)
    weather, departures = SyntheticWeather(), 24.0 .* (1:45:330)
    trip_costs(live) = sum(forecast_route(finer, kite_table, weather, departure;
        time_cost=kite_hourly,
        forecast=ReplannedForecast(CountedForecast(8.0, 0); interval=48.0, live)).objective
        for departure in departures)
    @test trip_costs(true) < trip_costs(false)
end

@testset "a ship sailing live changes speed within an edge, past the plan's speed" begin
    kite_table, kite_hourly, finer = kite_coaster_routing(400.0)
    steps = []
    forecast_route(finer, kite_table, SyntheticWeather(), 24.0 * 121;
        time_cost=kite_hourly, live_steps=steps,
        forecast=ReplannedForecast(CountedForecast(8.0, 0); live=true))
    speed(step) = WindShipOpt.sailed_speed(kite_table, step.point)
    edge_starts = findall(step -> step.share == 0, steps)
    edges = [steps[first:(last - 1)]
             for (first, last) in zip(edge_starts, [edge_starts[2:end]; length(steps) + 1])]
    @test any(edge -> length(unique(speed.(edge))) > 1, edges)
    @test any(step -> speed(step) > step.planned_speed, steps)
    @test all(step -> step.point.hours <= 1.0 + 1e-9, steps)
end

"""
The real `weather` until `cut` [h], and from then on with its wind turned and its sea
raised.
"""
struct ChangedAfter{W}
    weather::W
    cut::Float64
end
function WindShipOpt.wind(changed::ChangedAfter, lat, lon, time)
    east, north = WindShipOpt.wind(changed.weather, lat, lon, time)
    return time < changed.cut ? (east, north) : (east + 6.0, north - 4.0)
end
function WindShipOpt.waves(changed::ChangedAfter, lat, lon, time)
    height, period, direction = WindShipOpt.waves(changed.weather, lat, lon, time)
    return (time < changed.cut ? height : height + 1.0), period, direction
end

"The real `weather` with its sea raised 15 m from `from` until `until` [h]."
struct StormBetween{W}
    weather::W
    from::Float64
    until::Float64
end
WindShipOpt.wind(storm::StormBetween, lat, lon, time) =
    WindShipOpt.wind(storm.weather, lat, lon, time)
function WindShipOpt.waves(storm::StormBetween, lat, lon, time)
    height, period, direction = WindShipOpt.waves(storm.weather, lat, lon, time)
    return (storm.from <= time < storm.until ? height + 15.0 : height), period, direction
end

"""
The leg the kite coaster sails live in the real `weather` on a fixed forecast, departing
at `live_departure`, and its live steps, each as its hours from departure, speed, kite
state and hours sailed; `routing` is what `kite_coaster_routing` returns.
"""
function live_leg(routing, weather)
    kite_table, kite_hourly, finer = routing
    steps = []
    forecast = ReplannedForecast(FixedForecast(SyntheticWeather(; seed=2)); live=true)
    leg = forecast_route(finer, kite_table, weather, live_departure; time_cost=kite_hourly,
        live_steps=steps, forecast)
    return leg, [(hours=step.point.time - live_departure,
                     speed=WindShipOpt.sailed_speed(kite_table, step.point),
                     aloft=step.aloft, sailed=step.point.hours) for step in steps]
end

"departure of the kite coaster's live legs [h]"
live_departure = 24.0 * 121

"Hours, speed and kite state of each of the live `steps` in the first `cut` [h]."
steps_before(steps, cut) = [(step.hours, step.speed, step.aloft)
                            for step in steps if step.hours < cut]

"`steps_before` `cut` of the kite coaster sailing live by `live_leg`."
live_steps_before(routing, weather, cut) =
    steps_before(last(live_leg(routing, weather)), cut)

@testset "a live ship decides each hour without the weather it has not reached" begin
    cut, routing = 100.0, kite_coaster_routing(400.0)
    steps = live_steps_before(routing, SyntheticWeather(), cut)
    @test length(steps) > 50
    @test any(last, steps)
    changed = ChangedAfter(SyntheticWeather(), 24.0 * 121 + cut)
    @test live_steps_before(routing, changed, cut) == steps
end

@testset "a live ship meeting a storm mid-edge holds there until it can sail on" begin
    routing, departure = kite_coaster_routing(400.0), 24.0 * 121
    storm = StormBetween(SyntheticWeather(), departure + 80.0, departure + 86.0)
    leg, steps = live_leg(routing, storm)
    @test steps_before(steps, 80.0) == live_steps_before(routing, SyntheticWeather(), 80.0)
    held = [step for step in steps if step.speed == 0]
    @test !isnothing(leg)
    @test leg.duration ≈ sum(step -> step.sailed, steps)
    @test all(step -> 80.0 <= step.hours < 86.0, held)
    @test sum(step -> step.sailed, held; init=0.0) ≈ 6.0
    endless = StormBetween(SyntheticWeather(), departure + 80.0,
        departure + 80.0 + 2WindShipOpt.LONGEST_HOLD)
    leg, steps = live_leg(routing, endless)
    @test isnothing(leg)
    @test all(step -> step.hours < 80.0 || step.speed == 0, steps)
end

@testset "a ship sailing live on a true forecast sails about as its plan" begin
    weather, departure = SyntheticWeather(), 24.0 * 31
    planned, live = (forecast_route(corridor, table, weather, departure;
            time_cost=hourly,
            forecast=ReplannedForecast(CountedForecast(0.0, 0); live)).objective
        for live in (false, true))
    @test live ≈ planned rtol = 0.01
end

@testset "the remaining cost of a re-planning ship reads the hours it searched" begin
    departure, weather = 24.0 * 31, SyntheticWeather()
    prices = (; fuel=table.table.ship.fuel.price, time=hourly)
    to_go = WindShipOpt.remaining_cost(corridor, table, weather, departure, prices;
        first_stage=1)
    workspace = WindShipOpt.acquire_workspace(size(corridor.lat, 2),
        ceil(Int, WindShipOpt.MAX_LEG_HOURS / WindShipOpt.ROUTER_SETTINGS[].time_step),
        size(corridor.lat, 1))
    searched = WindShipOpt.CostToGo(workspace, corridor, table, weather, departure;
        time_cost=hourly, first_stage=1)
    centre = WindShipOpt.centre_index(corridor)
    @test all(to_go(centre, 1, 2, hours) ≈ searched(centre, 1, 2, hours)
              for hours in 0.0:7.0:200.0 if isfinite(searched(centre, 1, 2, hours)))
    WindShipOpt.release_workspace(workspace)
end

@testset "the cost to go computes a value when first asked, as a full sweep would" begin
    departure, weather = 24.0 * 31, SyntheticWeather()
    stage_count, lateral_count = size(corridor.lat)
    estimate() = WindShipOpt.CostToGo(Ref(zeros(lateral_count, 0, 2, stage_count)),
        corridor, table, weather, departure; time_cost=hourly, first_stage=1)
    asked, swept = estimate(), WindShipOpt.all_filled!(estimate())
    centre = WindShipOpt.centre_index(corridor)
    pending = count(asked.filler.pending)
    reads = [(lateral, stage, hours) for lateral in (centre - 1, centre, centre + 1)
             for stage in (2, stage_count ÷ 2) for hours in 0.0:7.0:200.0]
    @test all(isequal(asked(lateral, 1, stage, hours), swept(lateral, 1, stage, hours))
              for (lateral, stage, hours) in reads)
    @test 0 < count(asked.filler.pending) < pending
    @test !any(swept.filler.pending)
end

@testset "a re-plan reads the cost to go beyond its near hours from its last plan's" begin
    departure, weather = 24.0 * 31, SyntheticWeather()
    prices = (; fuel=table.table.ship.fuel.price, time=hourly)
    centre, stage = WindShipOpt.centre_index(corridor), size(corridor.lat, 1) ÷ 2
    remaining(start, previous; near_hours=Inf) = WindShipOpt.remaining_cost(corridor,
        table, weather, start, prices; first_stage=2, previous, near_hours)
    last_plan = remaining(departure, nothing)
    near(hours) = remaining(departure + 30.0, last_plan; near_hours=hours)
    alone, all_near, read = remaining(departure + 30.0, nothing), near(Inf), near(48.0)
    reads = [(lateral, hours) for lateral in (centre - 1, centre, centre + 1)
             for hours in 0.0:7.0:200.0]
    @test all(isequal(all_near(lateral, 1, stage, hours), alone(lateral, 1, stage, hours))
              for (lateral, hours) in reads)
    far = [(lateral, hours) for lateral in (centre - 1, centre, centre + 1)
           for hours in 72.0:24.0:168.0
           if isfinite(last_plan(lateral, 1, stage, hours + 30.0))]
    @test !isempty(far)
    @test all(read(lateral, 1, stage, hours) == last_plan(lateral, 1, stage, hours + 30.0)
              for (lateral, hours) in far)
    @test any(read(lateral, 1, stage, hours) != alone(lateral, 1, stage, hours)
              for (lateral, hours) in far)
end

"""
The nodes of `corridor` its edges reach from node `lateral` of stage `from`.
"""
function reached_from(corridor, lateral, from=1)
    reached = falses(size(corridor.water))
    reached[from, lateral] = true
    for stage in from:(size(corridor.lat, 1) - 1), node in findall(reached[stage, :]),
        step in 1:WindShipOpt.step_count(corridor)

        isnan(corridor.edge_course[stage, node, step]) && continue
        reached[stage + 1, WindShipOpt.next_lateral(corridor, node, step)] = true
    end
    return reached
end

"""
Whether edges of `corridor` lead from node `lateral` of stage `from` to its port, the
centre of its last stage.
"""
reaches_port(corridor, lateral, from=1) =
    reached_from(corridor, lateral, from)[end, WindShipOpt.centre_index(corridor)]

"""
The coarse mask with land north-east of Ushant except within 20 nautical miles of the
Channel track.
"""
struct ChannelMask
    open_sea::LandMask
    channel::Vector{NTuple{2, Float64}}
end
ChannelMask() = ChannelMask(north_atlantic_mask(),
    WindShipOpt.resample(WindShipOpt.CHANNEL, 5 * WindShipOpt.NAUTICAL_MILE))
WindShipOpt.is_land(mask::ChannelMask, lat, lon) =
    WindShipOpt.is_land(mask.open_sea, lat, lon) || lat > 48.6 && lon > -6.5 &&
    all(point -> WindShipOpt.distance(lat, lon, point...) > 20 * WindShipOpt.NAUTICAL_MILE,
        mask.channel)

@testset "a ship planning on a coarse far grid can reach port from every node" begin
    mask = ChannelMask()
    for leg in route_corridors(:caribbean, mask; ocean_spacing=240.0, lateral_spacing=60.0)
        @test all(findall(leg.water[1:(end - 1), :])) do node
            stage, lateral = Tuple(node)
            planning, first_stage, _ = WindShipOpt.planning_corridor(leg, stage, lateral)
            reaches_port(planning, lateral, first_stage)
        end
    end
end

@testset "beyond its near part a plan keeps more than one row of the open sea" begin
    mask = north_atlantic_mask()
    for ocean_spacing in (240.0, 120.0)
        leg = first(route_corridors(:caribbean, mask; ocean_spacing, lateral_spacing=60.0))
        stage = findfirst(>(1), vec(sum(leg.water; dims=2)))
        planning, _, near = WindShipOpt.planning_corridor(leg, stage,
            WindShipOpt.centre_index(leg))
        @test any(>(1), sum(planning.water[(near + 1):end, :]; dims=2))
    end
end

@testset "a graded plan keeps rows and stages further apart the further ahead" begin
    leg = first(route_corridors(:caribbean, north_atlantic_mask()))
    stage = findfirst(>(1), vec(sum(leg.water; dims=2)))
    stages, near, strides = WindShipOpt.planning_stages(leg, stage,
        WindShipOpt.ROUTER_SETTINGS[])
    far = (near + 1):length(stages)
    @test issorted(strides[far]) && last(strides) >= 4first(strides[far])
    lengths = diff(leg.along_centre[stages[far]])
    @test maximum(lengths) >= 4minimum(lengths)
    planning, first_stage, _ = WindShipOpt.planning_corridor(leg, stage,
        WindShipOpt.centre_index(leg))
    @test reaches_port(planning, WindShipOpt.centre_index(leg), first_stage)
end

"""
Angles [rad] between the edges leaving node `lateral` of stage `stage` of `corridor` and
the forward direction there, square to the node's row and pointing to the next stage.
"""
function edge_angles(corridor, stage, lateral)
    neighbour = lateral < size(corridor.lat, 2) ? lateral + 1 : lateral - 1
    row = WindShipOpt.bearing(corridor.lat[stage, lateral], corridor.lon[stage, lateral],
        corridor.lat[stage, neighbour], corridor.lon[stage, neighbour])
    ahead = WindShipOpt.bearing(corridor.lat[stage, lateral], corridor.lon[stage, lateral],
        corridor.lat[stage + 1, lateral], corridor.lon[stage + 1, lateral])
    off(course) = abs(mod(course + π, 2π) - π)
    forward = argmin(course -> off(course - ahead), (row - π / 2, row + π / 2))
    courses = filter(!isnan, corridor.edge_course[stage, lateral, :])
    return [off(course - forward) for course in courses]
end

"""
Whether every edge of every node of `corridor` makes progress, and the widest edge of a
node with a choice stays under the design angle plus `tolerance` [rad] and, where land and
the band's edge leave it all its edges, its tangent above half the design tangent.
"""
function headings_even(corridor; tolerance=deg2rad(10))
    design = atan(WindShipOpt.MAX_HEADING_TANGENT)
    for node in findall(corridor.water[1:(end - 1), :])
        angles = edge_angles(corridor, Tuple(node)...)
        all(<(π / 2), angles) || return false
        length(angles) > 1 || continue
        widest, full = maximum(angles), length(angles) == size(corridor.edge_course, 3)
        narrow = tan(widest) < WindShipOpt.MAX_HEADING_TANGENT / 2
        widest < design + tolerance && !(full && narrow) || return false
    end
    return true
end

@testset "every node of every corridor offers an even spread of forward headings" begin
    mask = north_atlantic_mask()
    for route in (:caribbean, :new_york, :bilbao, :dakar, :houston, :tubarao),
        scale in (1, 4), leg in route_corridors(route, mask; scale)

        @test headings_even(leg)
        scale == 1 || continue
        @test any(>(1), sum(leg.water; dims=2))
        @test all(1:6:(size(leg.lat, 1) - 1)) do stage
            centre = WindShipOpt.centre_index(leg)
            leg.water[stage, centre] || return true
            headings_even(first(WindShipOpt.planning_corridor(leg, stage, centre)))
        end
    end
end

@testset "the route to Houston chooses its track across the Gulf of Mexico" begin
    for leg in route_corridors(:houston, north_atlantic_mask())
        centre = WindShipOpt.centre_index(leg)
        gulf = [stage for stage in axes(leg.lat, 1) if leg.lon[stage, centre] < -85]
        rows = [count(leg.water[stage, :]) for stage in gulf]
        @test count(==(1), rows) == 1
        @test (maximum(rows) - 1) * leg.lateral_spacing >= 400 * WindShipOpt.NAUTICAL_MILE
    end
end

@testset "no corridor reaches past the latitudes a ship can sail" begin
    mask = north_atlantic_mask()
    for route in (:caribbean, :new_york, :bilbao, :dakar, :houston, :tubarao),
        scale in (1, 4), leg in route_corridors(route, mask; scale)

        @test all(abs(lat) <= WindShipOpt.SAILABLE_LATITUDE for lat in leg.lat[leg.water])
    end
end

"""
Whether every usable node of `corridor` lies on a path of its edges from node `start` of
its first stage to its port.
"""
on_some_passage(corridor, start=WindShipOpt.centre_index(corridor)) =
    corridor.water == reached_from(corridor, start) &&
    all(reaches_port(corridor, node.I[2], node.I[1]) for node in findall(corridor.water))

@testset "every node of a corridor lies on a passage from departure to port" begin
    mask = north_atlantic_mask()
    for route in (:caribbean, :new_york, :bilbao, :dakar, :houston, :tubarao),
        scale in (1, 4), leg in route_corridors(route, mask; scale)

        @test on_some_passage(leg)
        stage = something(findfirst(>(1), vec(sum(leg.water; dims=2))), 1)
        lateral = findlast(leg.water[stage, :])
        planning = first(WindShipOpt.planning_corridor(leg, stage, lateral))
        @test planning === leg || on_some_passage(planning, lateral)
    end
end

@testset "a corridor's open sea keeps clear of land except in the approaches" begin
    mask = north_atlantic_mask()
    for route in (:caribbean, :new_york, :bilbao, :dakar, :houston, :tubarao),
        leg in route_corridors(route, mask)

        ends = WindShipOpt.approaches(WindShipOpt.route_paths(route))
        open_sea = [node for node in findall(leg.water)
                    if count(leg.water[node.I[1], :]) > 1 &&
                       !WindShipOpt.approached((leg.lat[node], leg.lon[node]), ends)]
        @test !isempty(open_sea)
        @test !any(node -> WindShipOpt.near_land(mask, leg.lat[node], leg.lon[node],
            WindShipOpt.COASTAL_CLEARANCE), open_sea)
    end
end

@testset "the edge of a weather grid bounds the routes but is no coast" begin
    lats, lons = collect(0.0:1.5:30.0), collect(-40.0:1.5:-10.0)
    land = falses(length(lons), length(lats))
    land[findfirst(==(-25.0), lons), findfirst(==(15.0), lats)] = true
    mask = GridMask(lats, lons, land, WindShipOpt.Island[])
    clearance = WindShipOpt.COASTAL_CLEARANCE
    @test WindShipOpt.is_land(mask, 31.0, -25.0)
    @test !WindShipOpt.near_land(mask, 29.7, -25.0, clearance)
    @test !WindShipOpt.near_land(mask, 10.0, -39.7, clearance)
    @test WindShipOpt.near_land(mask, 15.0, -26.0, clearance)
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

"""
ERA5 of steady wind and waves on a 2 by 2 grid from 2017-12-29, the east wind rising, the
wind 6 m/s at 100 m and 12 m/s at 1000 m.
"""
function small_era5(directory)
    square = (lats=[40.0, 41.0], lons=[-31.0, -30.0])
    truth = Dict("u10" => step -> 5.0f0 + 0.01f0 * step, "v10" => step -> -2.0f0,
        "speed_100" => step -> 6.0f0, "speed_1000" => step -> 12.0f0,
        "height" => step -> 2.0f0, "period" => step -> 8.0f0, "direction" => step -> 60.0f0)
    for (group, names, step_hours) in (("wind", ["u10", "v10"], 6),
        ("aloft", ["speed_100", "speed_1000"], 6),
        ("waves", ["direction", "height", "period"], 12))
        write_fields(joinpath(directory, group),
            (name, step) -> fill(truth[name](step), 2, 2), 2000 ÷ step_hours,
            Dict("lats" => square.lats, "lons" => square.lons, "step_hours" => step_hours,
                "first_time" => "2017-12-29T00:00:00", "variables" => names,
                "heights" => [100, 1000]))
    end
    return ERA5Weather(directory)
end

"""
    small_climate(directory, weather)

Monthly means on the grids of `weather`: an east wind of the month's number, a north wind
of -1 m/s and a mean wind speed of 15 m/s; waves of 1.5 m and 7 s from the east.
"""
function small_climate(directory, weather)
    month_values = Dict("u10" => month -> Float32(month), "v10" => month -> -1.0f0,
        "speed" => month -> 15.0f0, "height" => month -> 1.5f0,
        "period" => month -> 7.0f0, "direction_east" => month -> 0.8f0,
        "direction_north" => month -> 0.0f0)
    for (group, fields, names) in (("wind", weather.wind, ["speed", "u10", "v10"]),
        ("waves", weather.waves,
            ["direction_east", "direction_north", "height", "period"]))
        write_fields(joinpath(directory, group),
            (name, month) -> fill(month_values[name](month), 2, 2), 12,
            Dict("lats" => fields.lats, "lons" => fields.lons, "variables" => names))
    end
    return Climatology(directory, weather.origin)
end

"""
    small_archive(directory, weather, offset; noise, wind_schedule, hole)

Four daily forecasts from 2017-12-30 on the grids of `weather`, each the weather it
forecasts plus `offset(year) + noise(issue)` on the east wind and half `offset(year)` on
the wave height, with their bias and blend weights against [`small_climate`](@ref). The
wind of issue `hole` is zero, as an issue never downloaded.
"""
function small_archive(directory, weather, offset; noise=issue -> 0.0,
        wind_schedule=(24.0, "2017-12-30T00:00:00", 24), hole=nothing)
    for (group, observed, names, leads, (first_issue, first_date, issue_hours)) in (
        ("wind", weather.wind, ["u10", "v10"], 6:6:24, wind_schedule),
        ("waves", weather.waves, ["direction_east", "direction_north", "height", "period"],
            12:12:24, (24.0, "2017-12-30T00:00:00", 24)))
        function field(name, index)
            issue, lead = divrem(index - 1, length(leads)) .+ 1
            time = first_issue + issue_hours * (issue - 1) + leads[lead]
            step = Int((time - observed.time_offset) / observed.step_hours + 1)
            year = issue <= 2 ? 2017 : 2018
            shift = name == "u10" ? offset(year) + noise(issue) :
                    name == "height" ? offset(year) / 2 : 0.0
            group == "wind" && issue == hole && return zeros(Float16, 2, 2)
            return Float16.(observed.fields[name][:, :, step] .+ shift)
        end
        write_fields(joinpath(directory, group), field, 4length(leads),
            Dict("lats" => observed.lats, "lons" => observed.lons,
                "first_issue" => first_date, "issue_hours" => issue_hours,
                "first_lead_hours" => first(leads), "step_hours" => step(leads),
                "leads" => length(leads), "variables" => names))
    end
    climate = small_climate(joinpath(directory, "climate"), weather)
    write_forecast_bias(directory, weather)
    write_forecast_weights(directory, weather, climate)
    return ForecastArchive(directory, weather, climate)
end

@testset "an ERA5 archive's wave direction components follow its directions" begin
    directory = mktempdir()
    components = small_era5(directory).wave_arrays[3:4]
    @test all(==(sind(60.0f0)), components[1])
    @test all(==(cosd(60.0f0)), components[2])
    write(joinpath(directory, "waves", "direction.f32"), fill(30.0f0, size(components[1])))
    @test all(==(sind(30.0f0)), ERA5Weather(directory).wave_arrays[3])
end

@testset "a read-only ERA5 archive holds its wave direction components in memory" begin
    waves = joinpath(mktempdir(), "waves")
    small_era5(dirname(waves))
    rm(joinpath(waves, "direction_east.f32"))
    chmod(waves, 0o555)
    @test all(==(sind(60.0f0)), ERA5Weather(dirname(waves)).wave_arrays[3])
    @test isfile(joinpath(waves, "direction_east.f32")) == iswritable(waves)
    chmod(waves, 0o755)
end

@testset "the climatology turns the year halfway between December and January" begin
    directory = mktempdir()
    weather = small_era5(joinpath(directory, "era5"))
    climate = small_climate(joinpath(directory, "climate"), weather)
    new_year = 72.0
    @test WindShipOpt.month_position(weather.origin, new_year) ≈ -0.5
    @test all(WindShipOpt.climate_wind(climate, 40.5, -30.5, new_year) .≈ (6.5, -1, 15))
    @test WindShipOpt.climate_wind(climate, 40.5, -30.5, new_year + 24 * 15.5)[1] ≈ 1.0
end

@testset "a forecast's weight is fitted on the other years, near zero for noise" begin
    directory = mktempdir()
    weather = small_era5(joinpath(directory, "era5"))
    archive = small_archive(joinpath(directory, "forecast"), weather, year -> 0.0;
        noise=issue -> issue <= 2 ? 0.0 : isodd(issue) ? 20.0 : -20.0)
    @test all(isapprox.(archive.wind.weights[2018], 1; atol=0.001))
    @test all(archive.wind.weights[2017] .< 0.02)
    late_2017 = ArchivedForecast(archive, 24.0 * 2 + 7.0)
    time = late_2017.issued + 12.0
    @test all(isapprox.(wind(late_2017, 40.5, -30.5, time),
        wind(archive.climate, 40.5, -30.5, time); atol=0.3))
    @test hypot(wind(late_2017, 40.5, -30.5, time)...) ≈ 15 atol = 0.2
end

@testset "a sparse archive fits its bias on the issues it holds, not on its holes" begin
    directory = mktempdir()
    weather = small_era5(joinpath(directory, "era5"))
    archive = small_archive(joinpath(directory, "forecast"), weather, year -> 1.5; hole=4)
    @test all(isapprox.(archive.wind.bias[2017]["u10"], 1.5; atol=0.01))
end

@testset "wind and waves come from one issue; an archive issued apart is refused" begin
    directory = mktempdir()
    weather = small_era5(joinpath(directory, "era5"))
    known = ArchivedForecast(small_archive(joinpath(directory, "daily"), weather,
            year -> 0.0), 73.0)
    @test known.issue == 2 && known.issued == 48.0
    @test_throws "issued apart" small_archive(joinpath(directory, "forecast"), weather,
        year -> 0.0; wind_schedule=(60.0, "2017-12-31T12:00:00", 6))
end

@testset "a forecast off by a fixed bias reads the weather once that bias is removed" begin
    directory = mktempdir()
    weather = small_era5(joinpath(directory, "era5"))
    archive = small_archive(joinpath(directory, "forecast"), weather, year -> 1.5)
    known = ArchivedForecast(archive, 24.0 * 3 + 7.0)
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
    late_2017 = ArchivedForecast(archive, 24.0 * 2 + 7.0)
    @test late_2017.year == 2017
    time = late_2017.issued + 18.0
    @test first(wind(late_2017, 40.5, -30.5, time)) ≈
          first(wind(weather, 40.5, -30.5, time)) + 1.0 - 3.0 atol = 0.02
    @test first(waves(late_2017, 40.5, -30.5, time)) ≈ 2.0 + 0.5 - 1.5 atol = 0.01
end

@testset "a ship reads the last forecast to reach it, beyond its leads climatology" begin
    directory = mktempdir()
    weather = small_era5(joinpath(directory, "era5"))
    archive = small_archive(joinpath(directory, "forecast"), weather, year -> 0.0)
    third = 24.0 * 3
    @test ArchivedForecast(archive, third + WindShipOpt.FORECAST_LATENCY).issued == third
    @test ArchivedForecast(archive, third + 5.0).issued == third - 24.0
    known = ArchivedForecast(archive, third + 7.0)
    beyond = third + 30.0
    @test wind(known, 40.5, -30.5, beyond) == wind(archive.climate, 40.5, -30.5, beyond)
end

@testset "a ship whose latest forecast is missing from the archive reads the one before" begin
    directory = mktempdir()
    weather = small_era5(joinpath(directory, "era5"))
    control = small_archive(joinpath(directory, "forecast"), weather, year -> 0.0)
    for name in ("direction_east", "direction_north", "height", "period")
        open(joinpath(directory, "forecast", "waves", "$name.f16"), "r+") do io
            issue_bytes = filesize(io) ÷ 4
            seek(io, 3issue_bytes)
            write(io, fill(NaN16, issue_bytes ÷ 2))
        end
    end
    archive = ForecastArchive(joinpath(directory, "forecast"), weather, control.climate)
    fourth = 24.0 * 4
    @test ArchivedForecast(archive, fourth + 7.0).issued == fourth - 24.0
end

@testset "a ship reads the climatology's waves where its forecast has none" begin
    directory = mktempdir()
    weather = small_era5(joinpath(directory, "era5"))
    control = small_archive(joinpath(directory, "forecast"), weather, year -> 0.0)
    for name in ("direction_east", "direction_north", "height", "period")
        path = joinpath(directory, "forecast", "waves", "$name.f16")
        values = read!(path, Vector{Float16}(undef, filesize(path) ÷ 2))
        values[1:4:end] .= NaN16
        write(path, values)
    end
    known = ArchivedForecast(ForecastArchive(joinpath(directory, "forecast"), weather,
            control.climate), 24.0 * 3 + 7.0)
    time = known.issued + 18.0
    @test all(waves(known, 40.0, -31.0, time) .≈ (1.5, 7.0, π / 2))
end

@testset "a ship reads no waves where the climatology has none, whatever its forecast" begin
    directory = mktempdir()
    weather = small_era5(joinpath(directory, "era5"))
    control = small_archive(joinpath(directory, "forecast"), weather, year -> 0.0)
    path = joinpath(directory, "forecast", "climate", "waves", "height.f32")
    write(path, fill(NaN32, filesize(path) ÷ 4))
    climate = Climatology(joinpath(directory, "forecast", "climate"), weather.origin)
    known = ArchivedForecast(ForecastArchive(joinpath(directory, "forecast"), weather,
            climate), 24.0 * 3 + 7.0)
    @test waves(known, 40.5, -30.5, known.issued + 18.0) == (0.0, 0.0, 0.0)
end

@testset "a ship re-planning daily on the real weather costs about what a route does" begin
    kite_table, kite_hourly = forecast_kite_routing(400.0)
    weather, departure = SyntheticWeather(), 24.0 * 121
    routed = route(corridor, kite_table, weather, departure; time_cost=kite_hourly)
    replanned = forecast_route(corridor, kite_table, weather, departure;
        time_cost=kite_hourly)
    @test replanned.objective ≈ routed.objective rtol = 0.02
end

@testset "a ship on one fixed course re-plans along it and leaves no other path" begin
    weather, departure = SyntheticWeather(), 24.0 * 121
    leg = route(corridor, table, weather, departure; time_cost=hourly)
    fixed = WindShipOpt.path_corridor(leg, corridor, 1)
    on_course = forecast_route(fixed, table, weather, departure; time_cost=hourly,
        forecast=FixedForecast(SyntheticWeather(; seed=2)))
    @test [point[1:2] for point in on_course.path] == [point[1:2] for point in leg.path]
    repeated = route(fixed, table, weather, departure; time_cost=hourly)
    @test [point[1:2] for point in repeated.path] == [point[1:2] for point in leg.path]
end

@testset "the shortest path through a corridor joins its centres and is no longer than \
          a routed path" begin
    weather, departure = SyntheticWeather(), 24.0 * 121
    leg = route(corridor, table, weather, departure; time_cost=hourly)
    shortest = WindShipOpt.shortest_corridor(corridor)
    centre = centre_index(corridor)
    @test (shortest.lat[1], shortest.lat[end]) == (corridor.lat[1, centre],
        corridor.lat[end, centre])
    @test shortest.track_length == corridor.track_length
    @test all(isfinite, shortest.edge_length[:, 1, WindShipOpt.STRAIGHT_ON])
    @test sum(shortest.edge_length) <=
          sum(WindShipOpt.path_corridor(leg, corridor, 1).edge_length)
end

@testset "a search that cuts off the best path and overruns its limit widens" begin
    weather, departure = SyntheticWeather(), 24.0 * 31
    (; time_step) = WindShipOpt.ROUTER_SETTINGS[]
    stage_count = size(corridor.lat, 1)
    workspace = WindShipOpt.RouteWorkspace(size(corridor.lat, 2),
        ceil(Int, 1200 / time_step), stage_count)
    options = (; time_step, time_cost=hourly, first_stage=1,
        first_lateral=centre_index(corridor), first_aloft=false,
        speed_stride=WindShipOpt.ROUTER_SETTINGS[].search_speed_stride)
    best = WindShipOpt.route_pass(workspace, corridor, table, weather, departure;
        options...)
    stage = findlast(stage -> count(view(corridor.water, stage, :)) > 1, 1:stage_count)
    best_node = WindShipOpt.nearest_lateral(corridor, stage, best.path[stage][1:2]...)
    values = zeros(size(corridor.lat, 2), 200, 2, stage_count)
    values[best_node, :, :, stage] .= Inf
    to_go = WindShipOpt.CostToGo(values, 48.0)
    detour = WindShipOpt.route_pass(workspace, corridor, table, weather, departure, to_go,
        floatmax(); options...)
    @test detour.objective > best.objective
    leg, limit = WindShipOpt.searched_leg(workspace, corridor, table, weather, departure,
        to_go, (prevfloat(detour.objective),); options...)
    @test leg.objective == best.objective
    @test limit == Inf
end

@testset "a recorded search holds the path it found, the limit it kept and its states" begin
    weather, departure = SyntheticWeather(), 24.0 * 31
    record = SearchRecord()
    leg = route(corridor, table, weather, departure; time_cost=hourly, record)
    @test leg.path == route(corridor, table, weather, departure; time_cost=hourly).path
    @test [point[1:2] for point in record.found.path] == [point[1:2] for point in leg.path]
    @test leg.objective <= record.found.objective <= record.limit
    @test record.limit == first(record.limits)
    centre = centre_index(corridor)
    @test record.estimate == record.to_go(centre, 1, 1, 0.0)
    through = through_node(record)
    @test through[1, centre] == record.estimate
    laterals = [WindShipOpt.nearest_lateral(corridor, stage, point[1:2]...)
                for (stage, point) in enumerate(record.found.path)]
    @test all(through[stage, lateral] <= record.limit
              for (stage, lateral) in enumerate(laterals))
    kept = kept_states(record)
    reached = isfinite.(record.cost)
    @test count(kept) < count(reached)
    @test all(any(kept[lateral, :, :, stage]) for (stage, lateral) in enumerate(laterals))
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

@testset "router settings refuse a second task while a call under others runs" begin
    entered, release = Base.Event(), Base.Event()
    other = WindShipOpt.RouterSettings(live_step_hours=0.5)
    running = Threads.@spawn WindShipOpt.with_router_settings(other) do
        notify(entered)
        wait(release)
        return WindShipOpt.ROUTER_SETTINGS[]
    end
    wait(entered)
    @test_throws ErrorException WindShipOpt.with_router_settings(() -> nothing, other)
    notify(release)
    @test fetch(running) == other
    @test WindShipOpt.with_router_settings(() -> WindShipOpt.ROUTER_SETTINGS[], other) ==
          other
end

@testset "the backward estimate's knots sit the set spacing apart, 24 h by default" begin
    @test WindShipOpt.RouterSettings().to_go_step == 24.0
    stage_count, lateral_count = size(corridor.lat)
    workspace = WindShipOpt.RouteWorkspace(lateral_count, 800, stage_count)
    departure, weather = 24.0 * 31, SyntheticWeather()
    estimate(step) = WindShipOpt.with_router_settings(
        WindShipOpt.RouterSettings(to_go_step=step)) do
        WindShipOpt.CostToGo(workspace, corridor, table, weather, departure;
            time_cost=hourly, first_stage=1)
    end
    fine, coarse = estimate(12.0), estimate(48.0)
    @test fine.step == 12.0 && coarse.step == 48.0
    @test fine.knots > 3 * coarse.knots

    centre, stage = centre_index(corridor), stage_count - 1
    function knot_value(step, knot)
        to_go = WindShipOpt.CostToGo(zeros(lateral_count, 30, 2, stage_count), step)
        prices = (; fuel=table.table.ship.fuel.price, time=hourly)
        WindShipOpt.fill_knot!(to_go, workspace.points, corridor, table, weather, departure,
            prices, stage, centre, knot)
        return to_go.values[centre, knot, 1, stage]
    end
    @test knot_value(12.0, 3) == knot_value(24.0, 2) != knot_value(12.0, 2)

    rising = WindShipOpt.CostToGo(reshape([0.0, 10.0, 40.0], 1, 3, 1, 1), 12.0)
    @test rising(1, 1, 1, 12.0) == 10.0
    @test rising(1, 1, 1, 18.0) == 25.0
end

kite_route_table = shared_route_table(ShipDesign(:methanol, 85.0; kite_area=400.0))

@testset "a kite takes the ERA5 wind aloft at its own height, its ship the table there" begin
    weather = small_era5(mktempdir())
    table = kite_route_table.table
    height = table.kite_height
    expected = 6 + 6 * log(height / 100) / log(10)
    edge = (2, centre_index(corridor), WindShipOpt.STRAIGHT_ON, 0.0, 100.0)
    sample = WindShipOpt.EdgeSample(table, weather, corridor, edge...)
    @test 100 < height < 1000
    @test hypot(sample.headwind, sample.crosswind) ≈ expected
    @test sample.wind_speed ≈ expected / table.kite_wind_factor
    rotors = shared_route_table(ShipDesign(:methanol, 85.0; rotor_area=200.0)).table
    stood = WindShipOpt.EdgeSample(rotors, weather, corridor, edge...)
    @test stood.wind_speed ≈ hypot(wind(weather, 40.5, -30.5, 100.0)...)
    @test stood.headwind == stood.crosswind == 0
end

@testset "a kite ship's search keeps one kite state per node and time, down at port" begin
    weather, departure = SyntheticWeather(), 24.0 * 31
    record = SearchRecord()
    leg = route(corridor, kite_route_table, weather, departure; time_cost=hourly, record)
    reached = isfinite.(record.cost)
    @test any(reached[:, :, 2, :])
    @test !any(reached[:, :, 1, :] .& reached[:, :, 2, :])
    @test !any(reached[:, :, 2, end])
    searched = WindShipOpt.with_router_settings(WindShipOpt.with_changed(
        WindShipOpt.ROUTER_SETTINGS[]; kite_states_searched=true)) do
        route(corridor, kite_route_table, weather, departure; time_cost=hourly)
    end
    @test leg.objective ≈ searched.objective rtol = 0.01
end

@testset "a plan weighing wind error expects a kite that just pulls to fly sometimes" begin
    speed_index = 4
    sample(wind, spread) = WindShipOpt.EdgeSample(kite_route_table.table, (wind, 0.0),
        (1.0, 6.0, 0.0), 0.0, spread)
    fuels(wind, spread) = WindShipOpt.expected_fuels(kite_route_table, speed_index,
        sample(wind, spread))
    winds = 0.5:0.5:20.0
    pulling = winds[findfirst(wind -> fuels(wind, 0.0)[1] < fuels(wind, 0.0)[2] / 2,
        winds)]
    certain_flown, certain_stowed, _ = fuels(pulling, 0.0)
    @test (certain_flown, certain_stowed) == WindShipOpt.edge_fuels(kite_route_table,
        speed_index, sample(pulling, 0.0).condition)
    flown, stowed, chance = fuels(pulling, 2.0)
    @test 0 < chance < 1
    @test certain_flown < flown < stowed
end

@testset "a forecast's wind error at a lead is that of the nearest lead it lists" begin
    error = ForecastError(6.0, [1.0, 2.0, 4.0])
    spread(lead) = WindShipOpt.wind_spread(error, lead) * sqrt(2)
    @test spread(1.0) == 1.0
    @test spread(10.0) == 2.0
    @test spread(17.0) == 4.0
    @test spread(96.0) == 4.0
end

@testset "a plan weighing wind error estimates the rest of its passage on its forecast" begin
    stage_count, lateral_count = size(corridor.lat)
    workspace = WindShipOpt.RouteWorkspace(lateral_count, 800, stage_count)
    known = SyntheticWeather()
    uncertain = WindShipOpt.UncertainForecast(known, 0.0, ForecastError(6.0, [4.0]))
    estimate(weather) = copy(WindShipOpt.all_filled!(WindShipOpt.CostToGo(workspace,
        corridor, kite_route_table, weather, 24.0 * 31; time_cost=hourly,
        first_stage=1)).values)
    @test isequal(estimate(uncertain), estimate(known))
end

@testset "the final pass of a plan weighing wind error runs on its own time bins" begin
    settings = WindShipOpt.RouterSettings(final_time_step=0.5, weighed_final_time_step=2.0)
    uncertain = WindShipOpt.UncertainForecast(SyntheticWeather(), 0.0,
        ForecastError(6.0, [4.0]))
    steps = WindShipOpt.with_router_settings(settings) do
        WindShipOpt.final_time_step.((SyntheticWeather(), uncertain))
    end
    @test steps == (0.5, 2.0)
end

"Value `share` of the way through interval `i` of `knots`"
place_in_cell(knots, i, share) = knots[i] + share * (knots[i + 1] - knots[i])

@testset "a knot weight finds the interval a search finds, on even and doubling \
          knots" begin
    for values in (collect(0.0:0.25:6.0), 1.6e6 .* WindShipOpt.ADDED_RESISTANCE_SHARES)
        knots = WindShipOpt.Knots(values)
        for i in 1:(length(values) - 1), share in (0.0, 0.3, 0.999, 1.0)
            weight = WindShipOpt.KnotWeight(knots, place_in_cell(values, i, share))
            @test weight.index == (share == 0 && i > 1 ? i - 1 : i)
            @test weight.upper ≈ (share == 0 && i > 1 ? 1.0 : share) atol = 1e-12
        end
        @test WindShipOpt.KnotWeight(knots, -1.0).index == 1
        @test WindShipOpt.KnotWeight(knots, 2last(values)).upper == 1.0
    end
end

@testset "a cell the router screens out is unpowered anywhere inside it" begin
    shares = (0.0, 0.5, 1.0)
    for route_table in (table, kite_route_table)
        performance = route_table.table
        winds, angles, resistances = performance.flown_thrust.knots[2:4]
        screened, powered = 0, 0
        for speed_index in eachindex(route_table.speeds)
            slice = route_table.slices[speed_index]
            cells = route_table.unpowered[speed_index].cells
            planes = route_table.unpowered[speed_index].planes
            @test all(.!planes .| dropdims(all(cells; dims=3); dims=3))
            for cell in CartesianIndices(cells)
                cells[cell] || continue
                screened += 1
                j, k, l = Tuple(cell)
                for wind_share in shares, angle_share in shares, layer_share in shares
                    condition = WindShipOpt.SeaCondition(performance,
                        place_in_cell(winds, j, wind_share),
                        place_in_cell(angles, k, angle_share), 0.0, 8.0, 1.0)
                    waves = place_in_cell(resistances, l, layer_share)
                    layer = WindShipOpt.KnotWeight(resistances, waves)
                    powered += WindShipOpt.edge_fuels(performance, slice, condition,
                        waves, layer) != (Inf, Inf)
                end
            end
        end
        @test screened > 0
        @test powered == 0
    end
end

@testset "a wind and angle screened out with the kite stowed leave it unpowered anywhere \
          inside" begin
    shares = (0.0, 0.5, 1.0)
    performance = kite_route_table.table
    winds, angles, resistances = performance.flown_thrust.knots[2:4]
    screened, powered = 0, 0
    for speed_index in eachindex(kite_route_table.speeds)
        slice = kite_route_table.slices[speed_index]
        planes = kite_route_table.unpowered[speed_index].stowed_planes
        for plane in CartesianIndices(planes), layer in 1:(length(resistances) - 1)
            planes[plane] || continue
            screened += 1
            j, k = Tuple(plane)
            for wind_share in shares, angle_share in shares, layer_share in shares
                condition = WindShipOpt.SeaCondition(performance,
                    place_in_cell(winds, j, wind_share),
                    place_in_cell(angles, k, angle_share), 0.0, 8.0, 1.0)
                waves = place_in_cell(resistances, layer, layer_share)
                powered += isfinite(last(WindShipOpt.edge_fuels(performance, slice,
                    condition, waves, WindShipOpt.KnotWeight(resistances, waves))))
            end
        end
    end
    @test screened > 0
    @test powered == 0
end

"""
    tried_held_speed(table, speed_index, sample, aloft)

The [`held_speed`](@ref) found by reading the fuels at every routing speed up to
`speed_index`.
"""
function tried_held_speed(table, speed_index, sample, aloft)
    fuels = [WindShipOpt.expected_fuels(table, i, sample) for i in 1:speed_index]
    stowed = [isfinite(stowed_fuel) for (_, stowed_fuel, _) in fuels]
    flying = [isfinite(flown_fuel) && chance > 0 for (flown_fuel, _, chance) in fuels]
    held = something(findlast(stowed .| aloft .& flying), findlast(flying), 0)
    return held == 0 ? (0, Inf, Inf, 0.0) : (held, fuels[held]...)
end

@testset "the held speed is the fastest the stowed rig holds, or a flying kite where \
          none does or the kite is up" begin
    for route_table in (table, kite_route_table)
        commanded = length(route_table.speeds)
        wrong, passed_over = 0, 0
        for wind in 0.0:3.0:30.0, angle in range(0, π; length=7), wave_height in (0, 3, 7)
            condition = WindShipOpt.SeaCondition(route_table.table, wind, angle,
                wave_height, 8.0, angle)
            sample = WindShipOpt.EdgeSample(condition, wind * cos(angle),
                wind * sin(angle), wind, 0.0)
            for aloft in (false, true)
                held = WindShipOpt.held_speed(route_table, commanded, sample, aloft)
                wrong += !isequal(held, tried_held_speed(route_table, commanded, sample,
                    aloft))
                passed_over += first(held) < first(tried_held_speed(route_table,
                    commanded, sample, true))
            end
        end
        @test wrong == 0
        @test passed_over > 0 || route_table === table
    end
end

@testset "waves marked as resisting add resistance anywhere in their cell" begin
    shares = (0.0, 0.5, 1.0)
    for route_table in (table, kite_route_table)
        performance = route_table.table
        winds, angles = performance.flown_thrust.knots[2:3]
        _, periods, headings = performance.wave_resistance.knots
        lowest = Inf
        for speed_index in eachindex(route_table.speeds)
            resisting = route_table.unpowered[speed_index].resisting_waves
            for cell in CartesianIndices(resisting), period_share in shares,
                    heading_share in shares
                resisting[cell] || continue
                i, j = Tuple(cell)
                condition = WindShipOpt.SeaCondition(performance, first(winds),
                    first(angles), 1.0, place_in_cell(periods, i, period_share),
                    place_in_cell(headings, j, heading_share))
                lowest = min(lowest, WindShipOpt.sea_resistance(
                    route_table.slices[speed_index], condition))
            end
        end
        @test isfinite(lowest)
        @test lowest >= 0
    end
end

@testset "a following sea below the table's added resistance keeps a speed its thrust \
          can reach" begin
    for route_table in (table, kite_route_table)
        performance = route_table.table
        winds, angles = performance.flown_thrust.knots[2:3]
        _, periods, headings = performance.wave_resistance.knots
        rescued, wrong = 0, 0
        for speed_index in eachindex(route_table.speeds)
            slice = route_table.slices[speed_index]
            least, knot = findmin(slice.wave_resistance)
            least < 0 || continue
            cells = route_table.unpowered[speed_index].cells
            for j in axes(cells, 1), k in axes(cells, 2)
                cells[j, k, 1] || continue
                condition = WindShipOpt.SeaCondition(performance,
                    place_in_cell(winds, j, 0.5), place_in_cell(angles, k, 0.5), 12.0,
                    periods[knot[1]], headings[knot[2]])
                full = WindShipOpt.edge_fuels(performance, slice, condition)
                rescued += any(isfinite, full)
                wrong += !isequal(WindShipOpt.edge_fuels(route_table, speed_index,
                    condition), full)
            end
        end
        @test rescued > 0
        @test wrong == 0
    end
end

@testset "the router sails the same routes with cells screened out or not" begin
    weather, departure = SyntheticWeather(), 24.0 * 31
    for route_table in (table, kite_route_table)
        unscreened = RouteTable(route_table.table, route_table.speeds, route_table.slices,
            [WindShipOpt.UnpoweredCells(fill(false, size(marks.cells)),
                 fill(false, size(marks.planes)), fill(false, size(marks.planes)),
                 marks.resisting_waves)
             for marks in route_table.unpowered])
        centre, straight = centre_index(corridor), WindShipOpt.MAX_LATERAL_STEP + 1
        samples = [WindShipOpt.EdgeSample(route_table.table, weather, corridor, stage,
                       centre, straight, 0.5, departure)
                   for stage in 1:(size(corridor.lat, 1) - 1)]
        speeds_and_samples = Iterators.product(eachindex(route_table.speeds), samples)
        screened = count(speeds_and_samples) do (speed_index, sample)
            WindShipOpt.screened_out(route_table, speed_index, sample.condition) ||
                WindShipOpt.screened_out(route_table, speed_index, sample.condition,
                    WindShipOpt.sea_layer(route_table.table,
                        route_table.slices[speed_index], sample.condition)...)
        end
        @test screened > 0
        screened_leg = WindShipOpt.route(corridor, route_table, weather, departure;
            time_cost=hourly)
        full_leg = WindShipOpt.route(corridor, unscreened, weather, departure;
            time_cost=hourly)
        for field in fieldnames(typeof(screened_leg))
            @test isequal(getfield(screened_leg, field), getfield(full_leg, field))
        end
    end
end

@testset "a workspace holds only the rows of states written to" begin
    workspace = WindShipOpt.RouteWorkspace(3, 4, 2)
    workspace.cost[2, 3, 1, 1] = 5.0
    workspace.cost[1, 4, 2, 2] = Inf
    @test workspace.cost[2, 3, 1, 1] == 5.0
    @test workspace.cost[1, 3, 1, 1] == Inf
    @test workspace.elapsed[2, 3, 1, 1] == 0.0
    @test length(workspace.cost.values) == 3
    WindShipOpt.empty_states!(workspace)
    @test all(isinf, workspace.cost)
    @test isempty(workspace.cost.values)
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
    share(state) = WindShipOpt.sharing_edges!(workspace, state, nothing, Inf,
        5 * (2WindShipOpt.MAX_LATERAL_STEP + 1))
    from = share(down)
    @test from >= 0
    @test length(workspace.shared) == from + 5 * (2WindShipOpt.MAX_LATERAL_STEP + 1)
    @test share(aloft) == from
    @test share(later_down) == share(later_aloft) == -1
    edge_count = 5 * (2WindShipOpt.MAX_LATERAL_STEP + 1)
    slots = [WindShipOpt.shared_slot(from, slot) for slot in 1:edge_count]
    @test slots == from .+ (1:edge_count)
    @test WindShipOpt.shared_slot(-1, 3) == 0
end

@testset "a kite aloft reads the edge a state down sailed at the same time as its own" begin
    table = shared_route_table(ShipDesign(:methanol, 85.0; kite_area=400.0))
    weather, stage, centre, slot = SyntheticWeather(), 1, centre_index(corridor), 1
    step = WindShipOpt.MAX_LATERAL_STEP + 1
    prices = (; fuel=table.table.ship.fuel.price, time=0.0)
    start = WindShipOpt.EdgeSample(table.table, weather, corridor, stage, centre, step, 0.0,
        24.0)
    edge = (; start, weather, corridor, stage, lateral=centre, step, time=24.0,
        speed_index=length(table.speeds) ÷ 2, sample_hours=6.0)
    workspace = WindShipOpt.RouteWorkspace(size(corridor.lat, 2), 4, size(corridor.lat, 1))
    push!(workspace.shared, WindShipOpt.UNSAILED)
    alone = WindShipOpt.sailed_edge!(workspace, 0, true, table, prices, edge)
    down = WindShipOpt.sailed_edge!(workspace, slot, false, table, prices, edge)
    @test down != alone
    @test workspace.shared[slot] == alone
    marked = WindShipOpt.SailedEdge(-1.0, WindShipOpt.NO_TALLY, WindShipOpt.NO_TALLY, 0)
    workspace.shared[slot] = marked
    @test WindShipOpt.sailed_edge!(workspace, slot, true, table, prices, edge) === marked
    workspace.shared[slot] = WindShipOpt.UNSAILED
    @test WindShipOpt.sailed_edge!(workspace, slot, true, table, prices, edge) == alone
    @test workspace.shared[slot] === WindShipOpt.UNSAILED
end

"""
    BeamGale(east, north, wave_from)

The same 10 m wind (`east`, `north`) [m/s] and 4 m waves of 8 s from `wave_from` [rad]
everywhere and at all times.
"""
struct BeamGale
    east::Float64
    north::Float64
    wave_from::Float64
end

WindShipOpt.wind(gale::BeamGale, lat, lon, time) = (gale.east, gale.north)
WindShipOpt.waves(gale::BeamGale, lat, lon, time) = (4.0, 8.0, gale.wave_from)

@testset "a state down sharing its edge with a kite aloft sails what the stowed rig \
          holds" begin
    table = shared_route_table(ShipDesign(:methanol, 85.0; kite_area=400.0))
    stage, centre, slot = 1, centre_index(corridor), 1
    step = WindShipOpt.MAX_LATERAL_STEP + 1
    course = corridor.edge_course[stage, centre, step]
    gale = BeamGale(8cos(course), -8sin(course), course + π / 2)
    midnight = mod(-corridor.lon[stage, centre] / 15, 24)
    prices = (; fuel=table.table.ship.fuel.price, time=0.0)
    start = WindShipOpt.EdgeSample(table.table, gale, corridor, stage, centre, step, 0.0,
        midnight)
    edge = (; start, weather=gale, corridor, stage, lateral=centre, step, time=midnight,
        speed_index=length(table.speeds), sample_hours=6.0)
    workspace = WindShipOpt.RouteWorkspace(size(corridor.lat, 2), 4, size(corridor.lat, 1))
    push!(workspace.shared, WindShipOpt.UNSAILED)
    down = WindShipOpt.sailed_edge!(workspace, slot, false, table, prices, edge)
    aloft = workspace.shared[slot]
    @test isfinite(aloft.up.cost)
    @test !isfinite(aloft.down.cost)
    @test isfinite(down.down.cost)
    @test down.hours > aloft.hours
end

@testset "a faster speed counts as sailed the same only where it is sampled alike" begin
    table = shared_route_table(ShipDesign(:methanol, 85.0))
    condition = WindShipOpt.SeaCondition(table.table, 0.0, 0.0, 8.0, 6.0, 2π / 3)
    sample = WindShipOpt.EdgeSample(condition, 0.0, 0.0, 0.0, 0.0)
    unpowered = findfirst(i -> !isfinite(last(WindShipOpt.edge_fuels(table, i, condition))),
        eachindex(table.speeds))
    held, flown, stowed, chance = WindShipOpt.held_speed(table, unpowered, sample, false)
    point = WindShipOpt.SailedPoint(sample, held, flown, stowed, 1.0, 0.0, chance)
    distance = 1e5
    hours(i) = distance / table.speeds[i] / 3600
    @test WindShipOpt.same_through(table, [point], unpowered, distance, 1e6) > unpowered
    between = (hours(unpowered) + hours(unpowered + 1)) / 2
    @test WindShipOpt.same_through(table, [point], unpowered, distance, between) ==
        unpowered
end

@testset "a faster command holds the same speed only through speeds no engine \
          powers" begin
    table = shared_route_table(ShipDesign(:methanol, 85.0))
    condition = WindShipOpt.SeaCondition(table.table, 0.0, 0.0, 3.0, 7.0, π)
    sample = WindShipOpt.EdgeSample(condition, 0.0, 0.0, 0.0, 0.0)
    powered(i) = isfinite(last(WindShipOpt.edge_fuels(table, i, condition)))
    unpowered = findfirst(!powered, eachindex(table.speeds))
    faster_powered = findnext(powered, eachindex(table.speeds), unpowered)
    held, flown, stowed, chance = WindShipOpt.held_speed(table, unpowered, sample, false)
    point = WindShipOpt.SailedPoint(sample, held, flown, stowed, 1.0, 0.0, chance)
    same_through = WindShipOpt.same_through(table, [point], unpowered, 1e5, 1e6)
    @test same_through == faster_powered - 1
    for speed_index in unpowered:same_through
        @test WindShipOpt.held_speed(table, speed_index, sample, false) ==
              (held, flown, stowed, chance)
    end
    calm = WindShipOpt.EdgeSample(WindShipOpt.SeaCondition(table.table, 0.0, 0.0, 0.0, 6.0,
        0.0), 0.0, 0.0, 0.0, 0.0)
    calm_held, calm_flown, calm_stowed, calm_chance = WindShipOpt.held_speed(table,
        unpowered, calm, false)
    calm_point = WindShipOpt.SailedPoint(calm, calm_held, calm_flown, calm_stowed, 1.0, 0.0,
        calm_chance)
    @test WindShipOpt.same_through(table, [point, calm_point], unpowered, 1e5, 1e6) ==
        unpowered
    @test first(WindShipOpt.held_speed(table, faster_powered, sample, false)) ==
          faster_powered
end

@testset "an edge begun with the kite down holds what the stowed rig holds" begin
    table = shared_route_table(ShipDesign(:methanol, 85.0; kite_area=400.0))
    prices = (; fuel=table.table.ship.fuel.price, time=0.0)
    condition = WindShipOpt.SeaCondition(table.table, 8.0, π / 2, 4.0, 8.0, π / 2)
    crosswind, headwind = table.table.kite_wind_factor * 8.0 .* sincos(π / 2)
    sample = WindShipOpt.EdgeSample(condition, headwind, crosswind, 0.0, 0.0)
    fastest = length(table.speeds)
    point(aloft) = WindShipOpt.SailedPoint(table, sample, fastest, aloft, 1e4, 0.0)
    @test point(false).speed_index < point(true).speed_index
    @test isfinite(point(false).stowed)
    @test isfinite(first(WindShipOpt.kite_passage(table, [point(false)], false,
        prices)).cost)
    @test isfinite(last(WindShipOpt.kite_passage(table, [point(true)], true, prices)).cost)
end

module PaperRuns
root = pkgdir(Main.WindShipOpt)
include(joinpath(root, "scripts", "paper_runs.jl"))
include(joinpath(root, "scripts", "run_estimate.jl"))
runs_directory = mktempdir()
end

@testset "a run counts as finished only once every data step it was asked for is done" begin
    write_data(run, name) = PaperRuns.run_step!(run, name,
        () -> touch(joinpath(run.directory, "$name.csv")))
    is_open() = !PaperRuns.is_finished(last(only(PaperRuns.fidelity_runs(:draft))))
    run = PaperRuns.open_run(:draft, [:designs, :routes], false)
    write_data(run, :designs)
    @test is_open()
    narrower = PaperRuns.open_run(:draft, [:designs], true)
    PaperRuns.finish_run!(narrower, [])
    @test is_open()
    rest = PaperRuns.open_run(:draft, [:routes], true)
    write_data(rest, :routes)
    rm(joinpath(rest.directory, "designs.csv"))
    PaperRuns.finish_run!(rest, [])
    @test is_open()
    write_data(rest, :designs)
    PaperRuns.finish_run!(rest, [])
    @test !is_open()
end

@testset "a figure that fails to draw keeps the run's data and the other figures" begin
    @eval PaperRuns runs_directory = mktempdir()  # runs are named by the minute they start
    drawn = Symbol[]
    steps = [:designs => () -> touch(PaperRuns.run_file("designs.csv")),
        :overlap => () -> error("labels of figure overlap: \"a\" overlaps \"b\""),
        :breakdown => () -> push!(drawn, :breakdown)]
    failed = redirect_stdout(devnull) do
        PaperRuns.run_steps(steps, [:overlap, :breakdown]; fidelity=:draft, resume=false)
    end
    @test only(failed) == (:overlap => "labels of figure overlap: \"a\" overlaps \"b\"")
    @test drawn == [:breakdown]
    @test PaperRuns.is_finished(PaperRuns.paper_run.record)
    @test_throws "overlap: labels of figure overlap" PaperRuns.check_drawn(failed)
end

@testset "a step resumed on another Julia records the version it ran on" begin
    @eval PaperRuns runs_directory = mktempdir()
    run = PaperRuns.open_run(:draft, [:designs], false)
    run.record["julia"] = "1.12.7"
    PaperRuns.write_record(run)
    resumed = PaperRuns.open_run(:draft, [:designs], true)
    PaperRuns.run_step!(resumed, :designs, () -> nothing)
    record = PaperRuns.TOML.parsefile(joinpath(resumed.directory, "run.toml"))
    @test record["julia"] == string(VERSION)
    @test only(record["steps"])["julia"] == string(VERSION)
end

@testset "a stored trip that read an input the model no longer has is not reused" begin
    stored(inputs) = (; inputs, files=Pair{String, String}[])
    case = (; assumptions)
    @test PaperRuns.reads_unchanged(stored([:air_density => assumptions[:air_density]]),
        case)
    @test !PaperRuns.reads_unchanged(stored([:retired_input => 1.0]), case)
end

@testset "a round trip at a held speed or with a model part off is stored apart" begin
    @eval PaperRuns weather_name = "synthetic"
    case_at(held_knots, part; course=:routed) = (; design=ShipDesign(:vlsfo, 100.0),
        assumptions, route=:caribbean, scale=8.0, course, forecast=false, held_knots, part)
    @test allunique(PaperRuns.case_directory(case_at(held_knots, :none), [24.0])
                    for held_knots in (nothing, 8.0, 9.0))
    @test allunique(PaperRuns.case_directory(case_at(nothing, part), [24.0])
                    for part in (:none, :waves, :windage))
    @test allunique(PaperRuns.case_directory(case_at(nothing, :none; course), [24.0])
                    for course in (:routed, :common_perfect))
end

@testset "the model every stored trip is keyed by covers the ship data tables" begin
    files = normpath.(PaperRuns.model_files())
    @test joinpath(pkgdir(WindShipOpt), "data", "ship_classes.csv") in files
end

@testset "the draft sensitivity study routes every other one of the final run's departures" begin
    @eval PaperRuns departures = collect(0.0:24.0:(71 * 24.0))
    function routed(fidelity)
        PaperRuns.paper_run = PaperRuns.PaperRun(fidelity)
        return PaperRuns.sensitivity_departures()
    end
    final = routed(:final)
    @test length(final) == 12
    @test routed(:draft) == final[1:2:end]
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
    PaperRuns.paper_run = PaperRuns.PaperRun(:final)
    @test PaperRuns.data_file("study.csv") == own
    rm(own)
    @test PaperRuns.data_file("study.csv") == other
end

@testset "figure and table steps read their source run before a finished one" begin
    function run_with(name, finished)
        directory = joinpath(PaperRuns.runs_directory, name)
        mkpath(directory)
        touch(joinpath(directory, "data.csv"))
        record = Dict("fidelity" => "final", "finished" => finished, "git_branch" => "other")
        open(io -> PaperRuns.TOML.print(io, record), joinpath(directory, "run.toml"), "w")
        return joinpath(directory, "data.csv")
    end
    unfinished = run_with("2026-02-01T0000", "")
    finished = run_with("2026-01-01T0000", "done")
    PaperRuns.paper_run = PaperRuns.PaperRun(:final)
    @test PaperRuns.data_file("data.csv") == finished
    PaperRuns.paper_run = PaperRuns.PaperRun(:final; source="2026-02-01T0000")
    @test PaperRuns.data_file("data.csv") == unfinished
end

"""
    store_run(fidelity, trip_model; commit="a", only=nothing)

A run of the paper at `fidelity` with round-trip code `trip_model` at clean `commit`,
computing only the cases matching `only`, set as the run in use.
"""
store_run(fidelity, trip_model; commit="a", only=nothing) =
    PaperRuns.paper_run = PaperRuns.PaperRun(mktempdir(), fidelity,
        Dict{String, Any}("git_commit" => commit, "git_dirty" => false), only,
        Dict{Symbol, Vector{Any}}(), trip_model, PaperRuns.StepTally())

@testset "a rig's stored trip serves an input it never reads, and no other" begin
    store_run(:draft, "rotor code")
    rotors = ShipDesign(:methanol, 85.0; rotor_area=200.0)
    routed(inputs) = round_trip(Ship(rotors, inputs), corridors..., SyntheticWeather(),
        [24.0 * 31, 24.0 * 200], inputs)
    dearer(name) = (; assumptions=with_value(assumptions, name, 1.5assumptions[name]))
    directory = mktempdir()
    PaperRuns.stored_trip(() -> routed(assumptions), directory, (; assumptions))
    dearer_canopy = dearer(:canopy_structure_cost)
    reused = PaperRuns.stored_entry(directory, dearer_canopy).trip
    rerouted = routed(dearer_canopy.assumptions)
    @test reused.cost_per_tonne_km == rerouted.cost_per_tonne_km
    @test reused.fuel_energy == rerouted.fuel_energy
    @test ismissing(PaperRuns.stored_entry(directory, dearer(:rotor_unit_cost)))
    @test ismissing(PaperRuns.stored_entry(directory, dearer(:market_price_factor)))
end

@testset "only a draft outside its slice keeps round trips of older code" begin
    directory = mktempdir()
    case = (; assumptions, class="handysize")
    store_run(:draft, "older code")
    PaperRuns.stored_trip(() -> assumptions[:discount_rate], directory, case)
    store_run(:draft, "newer code")
    @test ismissing(PaperRuns.stored_entry(directory, case))
    store_run(:draft, "newer code"; only=(class=("panamax", "capesize"),))
    @test PaperRuns.stored_entry(directory, case).model == "older code"
    store_run(:draft, "newer code"; only=(class="handysize",))
    @test ismissing(PaperRuns.stored_entry(directory, case))
    store_run(:final, "older code")
    @test PaperRuns.stored_entry(directory, case).commit == "a"
    store_run(:final, "older code"; commit="b")
    @test ismissing(PaperRuns.stored_entry(directory, case))
end

@testset "a dirty draft never overwrites a clean run's stored round trip" begin
    directory = mktempdir()
    case = (; assumptions)
    store_run(:final, "same code")
    PaperRuns.stored_trip(() -> 1.0, directory, case)
    PaperRuns.paper_run.record["git_dirty"] = true
    PaperRuns.stored_trip(() -> 2.0, directory, case)
    @test count(endswith(".bin"), readdir(directory)) == 2
    store_run(:final, "same code")
    @test PaperRuns.stored_entry(directory, case).trip == 1.0
end

"""
    tallied_step(run, cases)

A step of `run` using a stored round trip for each `(case, commit)` of `cases`.
"""
function tallied_step(run, cases)
    run.record["code_hash"] = "code"
    run.record["steps"] = Dict{String, Any}[]
    stored(commit) =
        (; trip=1.0, commit, dirty=false, model="newer code", processor="cpu", inputs=[])
    return () -> for (case, commit) in cases
        PaperRuns.tally_case!(case, "store-$(case.class)", stored(commit))
    end
end

@testset "a sliced draft records the commit that made each round trip" begin
    run = store_run(:draft, "newer code"; only=(class="handysize",))
    cases = [(; assumptions, class="handysize") => "b",
        (; assumptions, class="panamax") => "a"]
    PaperRuns.run_step!(run, :classes, tallied_step(run, cases))
    entry = PaperRuns.step_entry(run.record, :classes)
    @test readlines(joinpath(run.directory, entry["case_record"]))[2:end] ==
          ["\"class=handysize\",\"store-handysize\",\"b\",\"false\",\"newer code\",\"cpu\"",
           "\"class=panamax\",\"store-panamax\",\"a\",\"false\",\"newer code\",\"cpu\""]
    @test PaperRuns.part_commits([(run.directory, entry)]) == ["a", "b"]
end

@testset "a slice no case of the step carries is refused" begin
    run = store_run(:draft, "newer code"; only=(clas="handysize",))
    step = tallied_step(run, [(; assumptions, class="handysize") => "a"])
    @test_throws ArgumentError PaperRuns.run_step!(run, :classes, step)
    @test isnothing(PaperRuns.step_entry(run.record, :classes))
end

"""
    StubJobs

Jobs computing in tasks of this process the square of each case's `label`: each launch on a
shard in `wall` stores at most that many round trips and ends, as a job at its wall time
does, and a shard in `left` has a task a stopped run left running on it.
"""
struct StubJobs
    wall::Dict{Int, Int}
    retries::Int
    left::Dict{Int, Task}
    launches::Dict{Int, Int}
    computed::Threads.Atomic{Int}
end

StubJobs(wall, retries; left=Dict{Int, Task}()) =
    StubJobs(wall, retries, left, Dict{Int, Int}(), Threads.Atomic{Int}(0))

PaperRuns.cores(::StubJobs) = 3
PaperRuns.job_count(::StubJobs) = 4
PaperRuns.retries(jobs::StubJobs) = jobs.retries
PaperRuns.poll_seconds(::StubJobs) = 0.01
PaperRuns.running(::StubJobs, handles) = filter(!istaskdone, handles)
PaperRuns.left_running(jobs::StubJobs, batch, shard) = get(jobs.left, shard, nothing)

"""
    store_squares(jobs, batch, todo)

Task storing the square of the `label` of the cases `todo` of the batch file `batch`,
counted in `jobs.computed`.
"""
function store_squares(jobs, batch, todo)
    return Threads.@spawn for k in todo
        PaperRuns.stored_trip(() -> batch.cases[k].label^2, batch.directories[k],
            batch.cases[k])
        Threads.atomic_add!(jobs.computed, 1)
    end
end

function PaperRuns.launch(jobs::StubJobs, path, shard, shards)
    jobs.launches[shard] = get(jobs.launches, shard, 0) + 1
    batch = PaperRuns.deserialize(path)
    todo = PaperRuns.shard_missing(batch, shard, shards)
    return store_squares(jobs, batch, first(todo, get(jobs.wall, shard, length(todo))))
end

handed_cases = [(; assumptions, label) for label in 1:10]

@testset "a job ended at its wall time is launched again until its shard is stored" begin
    store_run(:draft, "code")
    jobs = StubJobs(Dict(1 => 1, 3 => 1), 0)
    directories = [mktempdir() for _ in handed_cases]
    entries = PaperRuns.job_trips(jobs, handed_cases, directories, [24.0])
    @test [entry.trip for entry in entries] == (1:10) .^ 2
    @test jobs.launches == Dict(1 => 3, 2 => 1, 3 => 2, 4 => 1)
    batch = only(filter(endswith(".bin"),
        readdir(PaperRuns.jobs_directory(PaperRuns.paper_run.directory); join=true)))
    @test PaperRuns.stored_count(batch) == 10
    foreach(rm, readdir(directories[2]; join=true))
    @test PaperRuns.stored_count(batch) == 9
end

@testset "a batch whose job stores nothing stops the run naming the cases it lacks" begin
    store_run(:draft, "code")
    jobs = StubJobs(Dict(2 => 0), 1)
    directories = [mktempdir() for _ in handed_cases]
    lacking = try
        PaperRuns.job_trips(jobs, handed_cases, directories, [24.0])
    catch error
        error.msg
    end
    @test contains(lacking, "for 3 cases") && contains(lacking, "label=6\nlabel=10")
    @test jobs.launches[2] == 2
end

@testset "a resumed run computes only the round trips its stopped run did not store" begin
    store_run(:draft, "code")
    directories = [mktempdir() for _ in handed_cases]
    @test_throws ErrorException PaperRuns.job_trips(StubJobs(Dict(2 => 0), 0),
        handed_cases, directories, [24.0])
    jobs = StubJobs(Dict{Int, Int}(), 0)
    entries = PaperRuns.job_trips(jobs, handed_cases, directories, [24.0])
    @test [entry.trip for entry in entries] == (1:10) .^ 2
    @test jobs.computed[] == 3 && jobs.launches == Dict(2 => 1)
end

@testset "a job a stopped run left running is waited for rather than launched again" begin
    store_run(:draft, "code")
    directories = [mktempdir() for _ in handed_cases]
    left = StubJobs(Dict{Int, Int}(), 0)
    batch = (; cases=handed_cases, directories)
    jobs = StubJobs(Dict{Int, Int}(), 0;
        left=Dict(3 => store_squares(left, batch, PaperRuns.shard_missing(batch, 3, 4))))
    entries = PaperRuns.job_trips(jobs, handed_cases, directories, [24.0])
    @test [entry.trip for entry in entries] == (1:10) .^ 2
    @test !haskey(jobs.launches, 3) && left.computed[] == 2
end

@testset "a final run takes only round trips computed on its own processor" begin
    directory = mktempdir()
    case = (; assumptions)
    store_run(:final, "code")
    PaperRuns.stored_trip(() -> 1.0, directory, case)
    file = only(readdir(directory; join=true))
    entry = PaperRuns.deserialize(file)
    PaperRuns.serialize(file, merge(entry, (; processor="another processor")))
    @test ismissing(PaperRuns.stored_entry(directory, case))
    store_run(:draft, "code")
    @test PaperRuns.stored_entry(directory, case).trip == 1.0
    @test PaperRuns.entry_file(directory, entry) !=
          PaperRuns.entry_file(directory, merge(entry, (; processor="another processor")))
end

@testset "a Slurm job is submitted only with the account and partition set" begin
    settings = merge(PaperRuns.cluster_settings(), Dict("account" => "", "partition" => ""))
    @test_throws "set the account" PaperRuns.slurm_command(settings, "run", "log", `true`)
    settings = merge(settings, Dict("account" => "research-me", "partition" => "p1"))
    command = PaperRuns.slurm_command(settings, "run", "log", `true`)
    @test "--account=research-me" in command.exec && "--partition=p1" in command.exec
end

@testset "a run resumed on new round-trip code hands out a batch of its own" begin
    directories = [mktempdir() for _ in handed_cases]
    store_run(:draft, "code")
    batch = PaperRuns.write_batch(handed_cases, directories, [24.0])
    @test PaperRuns.write_batch(handed_cases, directories, [24.0]) == batch
    PaperRuns.paper_run = PaperRuns.PaperRun(PaperRuns.paper_run.directory, :draft,
        PaperRuns.paper_run.record, nothing, Dict{Symbol, Vector{Any}}(), "newer code",
        PaperRuns.StepTally())
    newer = PaperRuns.write_batch(handed_cases, directories, [24.0])
    @test newer != batch && PaperRuns.deserialize(newer).trip_model == "newer code"
end

@testset "the run's own share that fails has ended, as a failed job has" begin
    failed = Threads.@spawn error("a trip failed")
    wait(Threads.@spawn try wait(failed) catch end)
    jobs = PaperRuns.SlurmJobs(PaperRuns.cluster_settings())
    @test isempty(PaperRuns.running(jobs, Any[failed]))
end

@testset "run jobs that find their run unmoved are counted until it moves" begin
    @eval PaperRuns runs_directory = joinpath(mktempdir(), "runs")
    @test PaperRuns.stalled_run_jobs(:draft) == 0
    directory = joinpath(PaperRuns.runs_directory, "2026-01-01T0000")
    mkpath(directory)
    record = Dict("fidelity" => "draft", "finished" => "", "git_branch" => "b",
        "steps" => [Dict("name" => "designs")])
    write_record() = open(io -> PaperRuns.TOML.print(io, record),
        joinpath(directory, "run.toml"), "w")
    write_record()
    @test PaperRuns.stalled_run_jobs(:draft) == 0
    @test PaperRuns.stalled_run_jobs(:draft) == 1
    @test PaperRuns.stalled_run_jobs(:draft) == 2
    push!(record["steps"], Dict("name" => "routes"))
    write_record()
    @test PaperRuns.stalled_run_jobs(:draft) == 0
end

@testset "the jobs of a run ask for no more than the cluster allows" begin
    settings = merge(PaperRuns.cluster_settings(),
        Dict("account" => "research-me", "partition" => "p2"))
    command = PaperRuns.slurm_command(settings, "run", "log", `true`; after="7")
    option(name) = only(split(only(filter(startswith("--$name="), command.exec)), "=")[2:end])
    hours, minutes, seconds = parse.(Int, split(option("time"), ":"))
    @test hours * 3600 + minutes * 60 + seconds <= 120 * 3600
    @test parse(Int, option("cpus-per-task")) <= 64
    @test PaperRuns.shard_count(PaperRuns.SlurmJobs(settings), 10^6) <= 64
    @test option("dependency") == "afterany:7"
end

module JobTrips
include(joinpath(pkgdir(Main.WindShipOpt), "scripts", "trips.jl"))
end

@testset "a job computing round trips loads their code without the plotting packages" begin
    @test !any(package -> nameof(package) == :CairoMakie, Base.loaded_modules_array())
    @test all(name -> isdefined(JobTrips, name), (:shard_trips, :trip_case, :case_trip))
end

@testset "a run's estimate counts the cases of each data step of the draft run" begin
    record = Dict("steps" => [Dict("name" => "patterns"),
        Dict("name" => "classes", "cases" => 26), Dict("name" => "routes", "cases" => 10)])
    @test PaperRuns.run_counts(record) == [(name="classes", cases=26),
        (name="routes", cases=10)]
end

@testset "the estimate counts the draft run with the most data steps, not the newest" begin
    run(name, finished, steps...) = (name, Dict{String, Any}("finished" => finished,
        "steps" => [Dict("name" => step, "cases" => 1) for step in steps]))
    runs = [run("rerun", "18 Nov", "routing_value"), run("going", "", "a", "b", "c"),
        run("full", "17 Nov", "classes", "routes"), run("older", "15 Nov", "a", "b")]
    @test first(PaperRuns.counted_run(runs)) == "full"
end

@testset "the estimate prints the sample costs beside the processor it names" begin
    costs = Dict{String, Any}("processor" => "box", "threads" => 12, "class_kite" => 241.9,
        "development_none" => 35.2)
    @test PaperRuns.cost_line(costs) == "class_kite 242, development_none 35"
end

@testset "a final run's parts name every commit and dirty tree they come from" begin
    part(commit, dirty, cases) = ("run", Dict{String, Any}("git_commit" => commit,
        "git_dirty" => dirty, "case_commits" => cases))
    @test PaperRuns.part_commits([part("a", false, Dict("a" => 2))]) == ["a"]
    @test PaperRuns.part_commits([part("a", false, Dict("a" => 2)),
        part("b", true, Dict("a" => 1, "b-dirty" => 1))]) == ["a", "b-dirty"]
end

@testset "a data file a step rewrites is read with its new contents" begin
    run = store_run(:draft, "code")
    write(PaperRuns.run_file("sizes.csv"), "size\n1\n")
    PaperRuns.data_file("sizes.csv")
    before = PaperRuns.read_hash("sizes.csv")
    write(PaperRuns.run_file("sizes.csv"), "size\n2\n")
    @test PaperRuns.read_hash("sizes.csv") != before
    @test PaperRuns.read_hash("sizes.csv") ==
          PaperRuns.file_hash(joinpath(run.directory, "sizes.csv"))
end

@testset "a step's code is what it reaches by name, docstrings and layout aside" begin
    file = tempname() * ".jl"
    hashes(text) = (write(file, text); PaperRuns.code_hashes(
        PaperRuns.script_definitions([file]), [:cost]))
    base = hashes("\"cost\"\ncost(x) = price(x) + 1\nprice(x) = 2x\nspeed(x) = 3\n")
    @test issetequal(keys(base), ["cost", "price"])
    @test hashes("\"cost of x\"\ncost(x) =\n    price(x) + 1\n\nprice(x) = 2x\n") == base
    changed = hashes("cost(x) = price(x) + 1\nprice(x) = 3x\n")
    @test changed["cost"] == base["cost"] && changed["price"] != base["price"]
end

@testset "a step is out of date once an input or file it read changes, and its readers" begin
    @eval PaperRuns assumptions = $assumptions
    @eval PaperRuns runs_directory = mktempdir()
    directory = joinpath(PaperRuns.runs_directory, "2026-01-01T0000")
    mkpath(directory)
    write(joinpath(directory, "classes.csv"), "class,cost\nhandysize,1.0\n")
    open(io -> PaperRuns.TOML.print(io, Dict("fidelity" => "draft", "finished" => "done",
            "git_branch" => "main")), joinpath(directory, "run.toml"), "w")
    PaperRuns.paper_run = PaperRuns.PaperRun(:draft)
    code = Dict("model" => "m", "sensitivity_data" => "s")
    entry = Dict{String, Any}("code" => code,
        "inputs" => Dict("discount_rate" => assumptions[:discount_rate]),
        "reads" => Dict("classes.csv" => Dict("hash" => PaperRuns.file_hash(
            joinpath(directory, "classes.csv")))))
    @test isempty(PaperRuns.step_reasons(entry, code))
    @test PaperRuns.step_reasons(entry, Dict("model" => "m", "sensitivity_data" => "t")) ==
          ["its code changed: sensitivity_data"]
    entry["inputs"]["discount_rate"] += 0.01
    @test PaperRuns.step_reasons(entry, code) == ["inputs changed: discount_rate"]
    entry["inputs"]["discount_rate"] = assumptions[:discount_rate]
    write(joinpath(directory, "classes.csv"), "class,cost\nhandysize,2.0\n")
    @test occursin("classes.csv changed", only(PaperRuns.step_reasons(entry, code)))
    location(files, reads) = (directory, Dict("files" => files,
        "reads" => Dict(read => Dict() for read in reads)))
    found = Dict(:classes => location(["classes.csv"], []),
        :goal_size => location(["goal_sizes.csv"], ["classes.csv"]),
        :availability => location(["availability.csv"], ["goal_sizes.csv"]),
        :speed_size => location(["speed_size.csv"], []))
    reasons = Dict(:classes => ["its code changed: classes_data"], :goal_size => String[],
        :availability => String[], :speed_size => String[])
    makers = Dict(file => name for (name, (_, entry)) in found for file in entry["files"])
    PaperRuns.spread_staleness!(reasons, found, makers)
    @test reasons[:availability] ==
          ["reads goal_sizes.csv of goal_size, which is out of date"]
    @test isempty(reasons[:speed_size])
end

@testset "an input read in a task spawned while recording is recorded" begin
    value, names = inputs_read(() -> fetch(Threads.@spawn assumptions[:discount_rate]))
    @test value == assumptions[:discount_rate]
    @test names == Set([:discount_rate])
end

module SizeSearch
include(joinpath(pkgdir(Main.WindShipOpt), "scripts", "size_search.jl"))
end

@testset "the size grid holds both bounds and no step within half a step of them" begin
    grid = SizeSearch.size_grid(500.0, 2441.4)
    @test first(grid) == 500.0 && last(grid) == 2441.4
    @test all(diff(log2.(grid)) .> 0.125)
    @test 2.0^(45 / 4) ∉ grid
end

@testset "a size search whose best is a bound next tries the size just inside it" begin
    grid = SizeSearch.size_grid(500.0, 16000.0)
    @test SizeSearch.next_size([(500.0, 3.0), (2828.4, 2.0), (16000.0, 1.0)], grid) ≈
          grid[end - 1]
    @test SizeSearch.next_size([(500.0, 1.0), (2828.4, 2.0), (16000.0, 3.0)], grid) ≈
          grid[2]
end

@testset "a size search confirms its cheapest size once both neighbours cost more" begin
    grid = SizeSearch.size_grid(500.0, 16000.0)
    @test isnothing(SizeSearch.next_size([(grid[k], cost) for (k, cost) in
                                          ((7, 2.0), (8, 1.0), (9, 3.0))], grid))
    @test isnothing(SizeSearch.next_size([(grid[1], 1.0), (grid[2], 2.0)], grid))
    @test SizeSearch.next_size([(grid[7], 2.0), (grid[8], 1.0), (grid[11], 3.0)], grid) ∈
          grid[9:10]
    @test isnothing(SizeSearch.next_size([(grid[7], Inf), (grid[8], Inf)], grid))
end

@testset "a size search from a guess far off still finds the cheapest size" begin
    grid = SizeSearch.size_grid(500.0, 64000.0)
    for best in (500.0, 3000.0, 20000.0, 64000.0), guess in (500.0, 4000.0, 64000.0)
        cost(area) = (log(area / best))^2
        points = [(area, cost(area)) for area in SizeSearch.start_sizes(guess, grid)]
        while (area = SizeSearch.next_size(points, grid)) !== nothing
            @test all(point -> !(first(point) ≈ area), points)
            push!(points, (area, cost(area)))
        end
        @test first(points[argmin(last.(points))]) ≈
              grid[SizeSearch.nearest_step(grid, best)]
    end
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

        table = shared_route_table(design)
        passage() = route(outbound, table, SyntheticWeather(), 24.0 * 31; time_cost=300.0)
        no_room_in_time = WindShipOpt.RouterSettings(final_time_band=-1.0)
        searched = WindShipOpt.with_router_settings(passage, no_room_in_time)
        final = passage()
        @test final.objective < searched.objective
        @test [point[1:2] for point in final.path] ==
              [point[1:2] for point in searched.path]
        along = WindShipOpt.path_corridor(searched, outbound, 1)
        lengths = along.edge_length[:, 1, WindShipOpt.STRAIGHT_ON]
        commanded = [table.speeds[WindShipOpt.commanded_speeds!(Int[], table.speeds,
                         no_room_in_time.search_speed_stride, distance,
                         no_room_in_time.time_step)] for distance in lengths]
        searched_speeds = [point[4] for point in searched.path[2:end]]
        final_speeds = [point[4] for point in final.path[2:end]]
        @test all(searched_speeds .∈ commanded)
        @test final_speeds ⊆ table.speeds
        @test !all(final_speeds .∈ commanded)
    end
end

@testset "a trace of a leg replays the kite decisions and the rig trim the router made" begin
    outbound, _ = corridors
    weather = SyntheticWeather()
    departure = 24.0 * 31
    for design in (ShipDesign(:methanol, 85.0; kite_area=800.0),
        ShipDesign(:methanol, 85.0; wing_area=300.0),
        ShipDesign(:methanol, 85.0; rotor_area=100.0))

        routing = shared_route_table(design)
        table = routing.table
        leg = route(outbound, routing, weather, departure; time_cost=300.0)
        trace = LegTrace(table, leg, weather, departure)
        @test first(trace.time) == 0
        @test last(trace.time) ≈ leg.duration rtol=0.02
        @test issorted(trace.time)
        @test (first(trace.lat), first(trace.lon)) == leg.path[1][1:2]
        @test last(trace.lat) ≈ leg.path[end][1] atol=1e-9
        @test last(trace.lon) ≈ leg.path[end][2] atol=1e-9
        @test sum(trace.hours) ≈ leg.duration rtol=1e-9
        # The router books each flight's launch and landing as stowed, the trace as flown.
        handled = leg.flight_hours + leg.launches * table.handling_hours
        @test sum(trace.hours[trace.flying]) ≈ handled rtol=0.02
        @test sum(trace.fuel_power .* trace.hours) ≈ leg.fuel_energy / 3600 rtol=0.05
        @test count(trace.launched) == leg.launches
        @test count(trace.forced) == leg.forced_landings
        rig = table.ship.rig
        if rig isa WindShipOpt.KiteRig
            @test leg.launches > 0
            @test all(isnothing, trace.trim[.!trace.flying])
            @test count(trace.landed) == leg.launches
        end
        trimmed = rig isa WindShipOpt.KiteRig ? findall(trace.flying) :
                  eachindex(trace.time)
        @test all(trimmed) do i
            force = WindShipOpt.rig_force(rig, table.ship.env,
                hypot(trace.wind_east[i], trace.wind_north[i]), trace.true_wind_angle[i],
                trace.speed[i], trace.trim[i])
            force.thrust == trace.rig_thrust[i]
        end
    end
end

"""
    monthly_passages(table, corridors, settings)

Legs of `table` in synthetic weather at 300 USD/h, one along each of `corridors` from the
matching one of `monthly_departures`, routed on threads under the router `settings`.
"""
monthly_passages(table, corridors, settings) =
    WindShipOpt.with_router_settings(settings) do
        fetch.([Threads.@spawn route(corridor, table, SyntheticWeather(), departure;
                    time_cost=300.0)
                for (corridor, departure) in zip(corridors, monthly_departures)])
    end

@testset "every rig's route costs what a search at every speed finds along its path" begin
    _, back = corridors
    backs = fill(back, length(monthly_departures))
    searched = WindShipOpt.ROUTER_SETTINGS[]
    room_in_time = WindShipOpt.with_changed(searched; final_time_band=96.0)
    every_speed = WindShipOpt.with_changed(room_in_time; search_speed_stride=1)
    every_speed_by_default = WindShipOpt.with_changed(searched; search_speed_stride=1)
    for design in (ShipDesign(:methanol, 85.0; wing_area=400.0),
        ShipDesign(:methanol, 85.0; kite_area=800.0))

        table = shared_route_table(design)
        coarse = monthly_passages(table, backs, room_in_time)
        own_paths = [WindShipOpt.path_corridor(leg, back, 1) for leg in coarse]
        along = monthly_passages(table, own_paths, every_speed)
        full = monthly_passages(table, backs, every_speed)
        by_search = monthly_passages(table, backs, searched)
        by_default = monthly_passages(table, backs, every_speed_by_default)
        for k in eachindex(monthly_departures)
            @test coarse[k].objective <= along[k].objective * (1 + 1e-4)
            @test coarse[k].objective <= full[k].objective * (1 + 1e-2)
            @test by_search[k].objective <= by_default[k].objective * (1 + 1e-2)
        end
    end
end

@testset "a route can choose among more routing speeds than a byte counts" begin
    _, back = corridors
    many_speeds = WindShipOpt.RouterSettings(routing_speeds=193)
    leg = WindShipOpt.with_router_settings(many_speeds) do
        table = RouteTable(PerformanceTable(Ship(ShipDesign(:methanol, 85.0), assumptions),
            assumptions))
        @test length(table.speeds) == 193
        route(back, table, SyntheticWeather(), 24.0 * 91; time_cost=300.0)
    end
    @test isfinite(leg.objective)
end

@testset "a held speed steps down through the ship's own speeds, and is commanded" begin
    table = shared_route_table(ShipDesign(:methanol, 85.0)).table
    held = WindShipOpt.held_speed_table(table, 11.3)
    @test last(held.speeds) ≈ 11.3KNOT
    @test held.speeds[1:(end - 1)] == filter(<(11.3KNOT), RouteTable(table).speeds)
    for count in 1:12, stride in (1, 2, 4, 8)
        indices = WindShipOpt.commanded_speeds(count, stride)
        @test last(indices) == count && step(indices) == stride && first(indices) <= stride
    end
end

@testset "by default the search commands 7 of 49 speeds, the lowest and the top" begin
    (; routing_speeds, search_speed_stride) = WindShipOpt.RouterSettings()
    @test WindShipOpt.commanded_speeds(routing_speeds, search_speed_stride) == 1:8:49
end

@testset "the search's speeds on an edge arrive within a time bin or are neighbours" begin
    speeds = collect(range(2.0, 8.0; length=49))
    commanded = Int[]
    for distance in (20e3, 500e3, 3500e3), time_step in (0.25, 1.5, 3.0),
        stride in (1, 2, 4, 8)
        WindShipOpt.commanded_speeds!(empty!(commanded), speeds, stride, distance,
            time_step)
        @test issubset(WindShipOpt.commanded_speeds(length(speeds), stride), commanded)
        @test all(>(0), diff(commanded))
        gaps = -diff(distance ./ speeds[commanded] ./ 3600)
        @test all(gaps .<= time_step .|| diff(commanded) .== 1)
    end
    WindShipOpt.commanded_speeds!(empty!(commanded), speeds, 4, 20e3, 3.0)
    @test commanded == WindShipOpt.commanded_speeds(length(speeds), 4)
    WindShipOpt.commanded_speeds!(commanded, speeds, 4, 3500e3, 3.0)
    @test commanded[1:13] == WindShipOpt.commanded_speeds(length(speeds), 4)
    @test issubset(WindShipOpt.commanded_speeds(length(speeds), 4), commanded[14:end])
end

@testset "soft and rigid kites both stop depowering where their lift reaches 0.05" begin
    soft = first(WindShipOpt.kite_model(800.0, 3.0, assumptions))
    rigid = first(WindShipOpt.rigid_kite_model(54.0, assumptions))
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
end

@testset "every number the paper and its extended abstract print from the numbers steps \
          is one they wrote" begin
    paper = joinpath(PaperRuns.root, "paper")
    texts = [joinpath(directory, name) for directory in (paper, joinpath(paper, "sections"))
             for name in readdir(directory) if endswith(name, ".tex")]
    used = Set(m.match for text in texts
               for m in eachmatch(r"\\Num[A-Za-z]+", read(text, String)))
    sections = joinpath(paper, "sections")
    defined = Set(m[1] for name in readdir(sections) if endswith(name, "numbers.tex")
                  for m in eachmatch(r"\\newcommand\{(\\Num[A-Za-z]+)\}",
                      read(joinpath(sections, name), String)))
    @test !isempty(used)
    @test used ⊆ defined
end

"mass [kg] per projected area of a soft kite of `area` [m^2] without its tether"
soft_mass_per_area(area, inputs) =
    WindShipOpt.soft_kite_mass(area, 3.0, 500area, inputs) / area

@testset "a soft kite's mass per area grows with its chord, in its ribs" begin
    @test soft_mass_per_area(3000.0, assumptions) >
          1.1soft_mass_per_area(200.0, assumptions)
    skins = 1e-3WindShipOpt.cloth_weight(assumptions) *
            assumptions[:canopy_flat_area_ratio] * assumptions[:canopy_skin_cloth_ratio]
    ribs(area) = WindShipOpt.Canopy(assumptions, area, 3.0).mass_per_area -
                 assumptions[:canopy_mass_overhead] - skins
    @test ribs(3200.0) ≈ 2ribs(800.0)
    model, _ = WindShipOpt.kite_model(200.0, 3.0, assumptions)
    @test model.mass > 200soft_mass_per_area(200.0, assumptions)
end

@testset "a ram-air canopy sews ribs for cells of one width at every chord" begin
    for chord in (4.0, 16.0, 40.0)
        @test WindShipOpt.cloth_area_ratio(assumptions, chord) ≈
              1.17 * (2.05 + 0.101 * chord / 0.5)
    end
    @test WindShipOpt.cloth_weight(assumptions) ≈ assumptions[:canopy_cloth_weight]
end

@testset "a rigid wing of the MX2 design matches its published numbers" begin
    model, force, _, airframe = WindShipOpt.rigid_kite_model(54.0, assumptions)
    @test force ≈ 300e3 rtol=0.01
    @test airframe.mass ≈ 1852 rtol=0.01
    @test model.tether_length ≈ 300 rtol=0.01
    @test model.min_turn_radius ≈ 90 rtol=0.01
    @test airframe.hover_power ≈ 0.87e6 rtol=0.02
    polar = model.polar
    angle = 1.81 / (polar.lift[2] / polar.angle_of_attack[2])
    feathered = 0.0036 * 0.61
    @test WindShipOpt.polar_value(polar, polar.drag, angle) ≈ 0.152 + feathered rtol=0.02
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
    small, small_force, = WindShipOpt.rigid_kite_model(30.0, assumptions)
    large, large_force, = WindShipOpt.rigid_kite_model(300.0, assumptions)
    @test first(best_thrust(small, small_force, 6.0)) > 0
    @test first(best_thrust(large, large_force, 6.0)) == 0
    thrust, pattern_force = best_thrust(large, large_force, 14.0)
    @test thrust > 0
    load = 0.5large.air_density * 14.0^2 * large.area
    @test pattern_force.peak_tension * load <= large_force * 1.001
    @test rad2deg(pattern_force.lowest_elevation) >= 8 - 0.01
end

@testset "a wing stalling at the top of its loop does not fly the loop" begin
    model, = WindShipOpt.rigid_kite_model(54.0, assumptions)
    stall = sqrt(2model.mass * model.gravity /
                 (model.air_density * model.area * maximum(model.polar.lift)))
    @test WindShipOpt.holds_speed(model, 2stall, 0.0)
    @test !WindShipOpt.holds_speed(model, 2stall, 4stall^2 / model.gravity)
end

@testset "a VTOL kite's mass grows from MX2's with its span to the mass exponent" begin
    @test WindShipOpt.rigid_kite_mass(54.0, assumptions) == assumptions[:rigid_mass]
    span_doubled = WindShipOpt.rigid_kite_mass(4 * 54.0, assumptions)
    @test span_doubled ≈ 2^assumptions[:rigid_mass_exponent] * assumptions[:rigid_mass]
    cubed = with_value(assumptions, :rigid_mass_exponent, 3.0)
    model, force, _, airframe = WindShipOpt.rigid_kite_model(216.0, cubed)
    @test airframe.mass ≈ 8assumptions[:rigid_mass]
    @test airframe.hover_power ≈ assumptions[:rigid_hover_power_per_mass] * airframe.mass
    @test force ≈ 4e3assumptions[:rigid_max_force_per_area] * 54.0
end

@testset "a VTOL kite's perch fits while its span is within the deck" begin
    hull = PAPER_HULL
    largest = WindShipOpt.largest_rigid_kite_area(hull, assumptions)
    @test sqrt(largest * assumptions[:rigid_aspect_ratio]) ≈
          assumptions[:deck_length_fraction] * hull.length
    rig = WindShipOpt.rigid_kite_rig(largest, hull, assumptions; courses=[π / 2],
        side_weights=[0.0])
    @test rig.area == largest
    @test isnothing(WindShipOpt.rigid_kite_rig(1.01largest, hull, assumptions))
end

"""
    rigid_test_kite(assumptions; area=54.0)

Rigid kite of `area` [m^2] with a two-point force table of 100 kN downwind at every wind
speed.
"""
function rigid_test_kite(assumptions; area=54.0)
    model, max_force, tether_diameter, airframe = WindShipOpt.rigid_kite_model(area,
        assumptions)
    wind_speeds = [5.0, 30.0]
    courses = [0.0, π]
    side_weights = [0.0]
    forces = [WindShipOpt.PatternForce(
                  (1e5 / (0.5 * model.air_density * speed^2 * area), 0.0, 0.0), 1.0, 0.5)
              for speed in wind_speeds, _ in courses, _ in side_weights]
    return KiteRig(; area, aspect_ratio=assumptions[:rigid_aspect_ratio],
        tether_diameter, model.tether_length, reference_height=10.0,
        WindShipOpt.rigid_wind_limits(5.0, assumptions)..., max_force, attach_height=10.0,
        attach_position=0.0, wind_speeds, courses, side_weights, forces, airframe)
end

@testset "a rigid kite's airframe is priced by mass, its supply by hover power" begin
    one = rigid_test_kite(assumptions)
    (; mass, hover_power) = one.airframe
    factor = assumptions[:market_price_factor]
    raised(name) = with_value(assumptions, name, assumptions[name] + 1.0)
    price(inputs) = first(WindShipOpt.rig_costs(one, inputs))
    @test price(raised(:rigid_cost_per_mass)) - price(assumptions) ≈ factor * mass
    @test price(raised(:rigid_ship_power_cost)) - price(assumptions) ≈
          factor * (1 + assumptions[:kite_integration_fraction]) * hover_power
end

@testset "a rigid kite's station is a soft kite's deck system and controls, and its tether" begin
    one, large = rigid_test_kite(assumptions), rigid_test_kite(assumptions; area=216.0)
    parts = WindShipOpt.rig_price_parts(one, assumptions)
    @test parts.deck ≈ WindShipOpt.kite_deck_price(one.area, one.max_force, assumptions)
    @test parts.controls == assumptions[:kite_controls_cost]
    @test parts.tether == assumptions[:rigid_tether_cost]
    @test WindShipOpt.rig_price_parts(large, assumptions).tether ≈ 8parts.tether
    tether = WindShipOpt.rope_mass(large.tether_diameter, large.tether_length, assumptions)
    @test 1e3WindShipOpt.rig_costs(large, assumptions)[2] ≈
          sum(WindShipOpt.kite_deck_masses(large.area, large.max_force, assumptions)) +
          large.airframe.mass + tether
end

@testset "each launch wears the tether by its bends over drum and sheaves" begin
    kite = uniform_kite(Hull(140.0, assumptions), assumptions)
    halved = with_value(assumptions, :tether_bend_life, assumptions[:tether_bend_life] / 2)
    _, tether = WindShipOpt.consumable_costs(kite, assumptions)
    added = WindShipOpt.cycle_cost(kite, halved) - WindShipOpt.cycle_cost(kite, assumptions)
    @test added ≈
          tether * assumptions[:tether_bends_per_launch] / assumptions[:tether_bend_life]
end

@testset "a rigid kite hovers within its own limits and stays up beyond them" begin
    fleet = rigid_test_kite(assumptions)
    waves = assumptions[:rigid_hover_max_wave_height]
    wind = assumptions[:kite_launch_max_wind]
    @test WindShipOpt.kite_landable(fleet, 0.0, wind - 1, 0.0, waves)
    @test !WindShipOpt.kite_landable(fleet, 0.0, wind + 1, 0.0, waves)
    @test !WindShipOpt.kite_landable(fleet, 0.0, wind - 1, 0.0, waves + 0.5)
    @test WindShipOpt.kite_aloft(fleet, 0.0, wind - 1, 0.0)
    @test WindShipOpt.extra_launch_wind(fleet, waves) == 0
    @test isfinite(waves)
    @test fleet.launch_min_wind == fleet.min_flight_wind
    @test WindShipOpt.handling_hours(fleet, assumptions) == 0
end

@testset "a rigid wing flies no lower than its loops or a level sweep allow" begin
    hull = Hull(140.0, assumptions)
    rig = WindShipOpt.rigid_kite_rig(54.0, hull, assumptions; courses=[π / 2],
        side_weights=[0.0])
    model, = WindShipOpt.rigid_kite_model(54.0, assumptions)
    elevation = deg2rad(assumptions[:kite_min_elevation])
    @test rig.min_flight_wind >= WindShipOpt.crosswind_min_wind(model, elevation)
    @test rig.min_flight_wind < WindShipOpt.climbing_min_wind(model, elevation)
    below = findlast(<(rig.min_flight_wind), rig.wind_speeds)
    @test isnothing(below) || !isfinite(rig.forces[below, 1, 1].peak_tension)
end

@testset "a failed VTOL kite leaves the ship sailing without a rig" begin
    changed = with_value(assumptions, :kite_out_of_service, 0.1)
    states = WindShipOpt.service_states(rigid_test_kite(changed), changed)
    @test first(last(states)) ≈ 0.1
    @test isnothing(last(last(states)))
end

@testset "one crash costs a control unit, half the wearing parts, or one deck unit" begin
    hull = Hull(140.0, assumptions)
    kite = uniform_kite(hull, assumptions)
    canopy, tether = WindShipOpt.consumable_costs(kite, assumptions)
    control_unit = assumptions[:market_price_factor] *
                   WindShipOpt.rig_price_parts(kite, assumptions).control_unit
    @test WindShipOpt.crash_cost(kite, assumptions) ≈ control_unit + (canopy + tether) / 2
    for rig in (WingRig(1200.0, hull, assumptions; in_column=2),
        WingRig(1200.0, hull, assumptions; unit=:suction, in_column=2),
        WindShipOpt.RotorRig(1200.0, hull, assumptions; in_column=2))
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
    fleet = rigid_test_kite(assumptions)
    capital = first(WindShipOpt.rig_costs(fleet, assumptions))
    airframes = WindShipOpt.rigid_airframe_price(fleet, assumptions)
    @test WindShipOpt.rig_maintenance(fleet, capital, raised(:rig_maintenance_fraction)) -
          WindShipOpt.rig_maintenance(fleet, capital, assumptions) ≈
          0.01 * (capital - airframes)
    rotors = WindShipOpt.RotorRig(400.0, Hull(140.0, assumptions), assumptions)
    @test WindShipOpt.upkept_price(WindShipOpt.CombinedRig(fleet, rotors), assumptions) ≈
          airframes
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

@testset "a rigid kite crashing costs its airframe" begin
    kite = rigid_test_kite(assumptions)
    @test WindShipOpt.crash_cost(kite, assumptions) ≈
          WindShipOpt.rigid_airframe_price(kite, assumptions)
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

@testset "a kite built for its cost is priced like the one that flies" begin
    area, flying = last(kite_rigs_by_area())
    hull = Hull(140.0, assumptions)
    priced = KiteRig(area, 3.0, hull, assumptions; courses=Float64[])
    @test WindShipOpt.consumable_costs(priced, assumptions) ==
          WindShipOpt.consumable_costs(flying, assumptions)
    @test WindShipOpt.crash_cost(priced, assumptions) ==
          WindShipOpt.crash_cost(flying, assumptions)
end

@testset "a lead over another rig is used up exactly at its life and loss limits" begin
    lead, goal_life, canopy_points, crash_points = 2.0, 4000.0, 8000.0, 1.6
    limits = WindShipOpt.lead_limits(lead, goal_life, canopy_points, crash_points)
    @test canopy_points * (1 / limits.life - 1 / goal_life) ≈ lead
    @test limits.losses * crash_points ≈ lead
    behind = WindShipOpt.lead_limits(-0.5, goal_life, canopy_points, crash_points)
    @test isnan(behind.life) && isnan(behind.losses)
end

module PaperData
using Printf, Statistics, WindShipOpt
assumptions = Main.assumptions
include(joinpath(pkgdir(WindShipOpt), "scripts", "paper_data.jl"))
include(joinpath(pkgdir(WindShipOpt), "scripts", "paper_tables.jl"))
include(joinpath(pkgdir(WindShipOpt), "scripts", "passages_data.jl"))
include(joinpath(pkgdir(WindShipOpt), "scripts", "explorer_data.jl"))
end

@testset "the fuel study sizes each rig as the class study does on e-ammonia" begin
    # route, drive, rig, area, cost; the VLSFO and Bilbao rows must not be chosen
    runs = [("tubarao", "ammonia", "kite", 1600.0, 0.0050),
        ("tubarao", "ammonia", "kite", 3200.0, 0.0048),
        ("tubarao", "vlsfo", "kite", 6400.0, 0.0040),
        ("tubarao", "ammonia", "wings", 3600.0, 0.0049),
        ("tubarao", "ammonia", "suction", 1600.0, 0.0049),
        ("tubarao", "ammonia", "rotors", 1890.0, 0.0047),
        ("tubarao", "ammonia", "vtol", 80.0, 0.0050),
        ("tubarao", "ammonia", "vtol", 160.0, 0.0051),
        ("tubarao", "ammonia", "lei", 400.0, 0.0049),
        ("tubarao", "ammonia", "lei", 800.0, 0.0050),
        ("bilbao", "ammonia", "rotors", 850.0, 0.0045)]
    classes = Dict{String, Vector}("class" => fill("Kamsarmax bulk carrier", length(runs)),
        (name => [run[k] for run in runs]
         for (k, name) in enumerate(("route", "drive", "rig", "area", "cost")))...)
    @test PaperData.fuel_sizes(classes, "Kamsarmax bulk carrier", :tubarao) ==
          Dict("none" => 0.0, "kite" => 3200.0, "wings" => 3600.0, "suction" => 1600.0,
              "rotors" => 1890.0, "vtol" => 80.0, "lei" => 400.0)
    @test PaperData.swept_values(:e_methanol_price) ==
          sort([Main.assumptions[:e_methanol_price], 40.0, 90.0, 120.0])
end

@testset "a table step that fails part way leaves the table it had" begin
    path = joinpath(mktempdir(), "table.tex")
    write(path, "complete table")
    @test_throws ErrorException PaperData.write_whole(path) do io
        println(io, "\\begin{tabular}")
        error("no data for the next row")
    end
    @test read(path, String) == "complete table"
    PaperData.write_whole(io -> print(io, "new table"), path)
    @test read(path, String) == "new table"
end

@testset "routing and a rig save against the unrouted ship without a rig, \
          per departure" begin
    case = ("140 m", "ammonia")
    table = Dict("ship" => fill(case[1], 3), "drive" => fill(case[2], 3),
        "rig" => ["none", "kite", "none"], "course" => ["routed", "routed", "shortest"],
        "speed" => ["cost", "cost", "same_time"], "cost" => [9.0, 7.0, 10.0])
    @test PaperData.routing_saving(table, case..., "none", "same_time") ≈ 10
    @test PaperData.routing_saving(table, case..., "kite", "same_time") ≈ 30
    departures(days) = Dict("ship" => fill(case[1], 4), "drive" => fill(case[2], 4),
        "rig" => fill("none", 4), "course" => ["routed", "routed", "shortest", "shortest"],
        "speed" => ["cost", "cost", "same_time", "same_time"], "departure" => days,
        "cost" => [9.0, 8.0, 10.0, 12.0])
    @test PaperData.routing_error(departures([0, 24, 24, 0]), case..., "same_time") ≈ 2.5
    @test_throws ErrorException PaperData.routing_error(departures([0, 24, 24, 48]),
        case..., "same_time")
end

@testset "a result prints in whole points and a table cell to one decimal, never as -0" begin
    @test PaperData.whole_number(-0.4) == "0"
    @test PaperData.whole_number(12.6) == "13"
    @test PaperData.whole_number(2.5) == "3"
    @test PaperData.whole_points(0.4) == "less than 1 point"
    @test PaperData.whole_points(1.2) == "1 point"
    @test PaperData.whole_points(2.6) == "3 points"
    @test PaperData.one_decimal(-0.04) == "0.0"
    @test PaperData.one_decimal(3.46) == "3.5"
end

@testset "a source note sets a whole power as a superscript, decimals included" begin
    @test PaperData.latex_escape("211 f^-2.25 at 3 %") ==
          "211 f\\textsuperscript{-2.25} at 3 \\%"
    @test PaperData.latex_escape("per m^2. Then") == "per m\\textsuperscript{2}. Then"
end

@testset "an input prints under its name in words, the rigid kite named only as a prefix" begin
    @test PaperData.input_label(:e_ammonia_price) == "e-ammonia price"
    @test PaperData.input_label(:rigid_tether_cost) == "rigid kite tether cost"
    @test PaperData.input_label(:rotor_max_wind) == "rotor max wind"
    @test PaperData.input_label(:cargo_per_teu) == "cargo per TEU"
    @test PaperData.input_label(:mast_rigid_share) == "mast rigid share"
end

@testset "a source note prints each source as a citation of its key" begin
    note = "Kalverla's profile [@kalverla2019, Ch. 2; @schelbergen2020] gives 5 %; @imo2020 too."
    @test PaperData.cited_note(note) == "Kalverla's profile (\\citealp[Ch. 2]{kalverla2019}; " *
        "\\citealp{schelbergen2020}) gives 5\\,\\%; \\citet{imo2020} too."
    @test PaperData.cited_note("@lrumas2020 [Table B21]; @imo2020: two-stroke") ==
          "\\citet[Table B21]{lrumas2020}; \\citet{imo2020}: two-stroke"
    @test PaperData.cited_note("no source, 50 %") == "no source, 50\\,\\%"
    @test PaperData.cited_note("Euroseas 1,800 TEU, 12,000 TEU") ==
          "Euroseas \\num{1800}~TEU, 12\\,000~TEU"
    @test_throws ErrorException PaperData.cited_note("[@a2020; Table 3]")
end

@testset "kite-and-rotor pairs fly only kites already sized, near the best sizes" begin
    kites = [500.0, 1024.0, 1448.0, 2048.0, 4096.0]
    sizes = PaperData.pair_sizes(2000.0, 900.0, kites, (200.0, 800.0))
    @test sizes[1:2] == [("kite", 2000.0, 0.0), ("rotors", 0.0, 900.0)]
    pairs = [size[2:3] for size in sizes if size[1] == "kite+rotors"]
    @test pairs == [(1024.0, 800.0), (500.0, 800.0), (1024.0, 450.0)]
    @test all(pair -> pair[1] in kites, pairs)
    small_kite = PaperData.pair_sizes(500.0, 900.0, kites, (200.0, 800.0))
    @test count(size -> size[1] == "kite+rotors", small_kite) == 2
end

@testset "a ship with an undefined rig area is refused, never sailed with no rig" begin
    @test_throws ArgumentError ShipDesign(:vlsfo, 100.0; kite_area=NaN)
    @test_throws ArgumentError ShipDesign(:vlsfo, 100.0; rotor_area=Inf)
    @test ShipDesign(:vlsfo, 100.0; kite_area=800.0).kite_area == 800
end

@testset "every goal takes its value known today and every other input keeps its own" begin
    today = at_today(assumptions)
    goals = [name for (name, entry) in assumptions.entries if entry.today != entry.value]
    @test :canopy_life in goals && :kite_out_of_service in goals
    @test all(today[name] == assumptions.entries[name].today for name in goals)
    @test all(today[name] == assumptions[name]
              for name in keys(assumptions.entries) if !(name in goals))
end

@testset "a kite costed on its routes at the goals costs what routing found, and more \
          at today's values" begin
    kite = ShipDesign(:methanol, 85.0; kite_area=400.0)
    trip = round_trip(Ship(kite, assumptions; route=:caribbean), corridors...,
        SyntheticWeather(), [24.0 * 31], assumptions)
    case = (; design=kite, assumptions, route=:caribbean, corridors)
    @test PaperData.changed_cost(case, trip) ≈ trip.cost_per_tonne_km
    today = merge(case, (; assumptions=at_today(assumptions)))
    @test PaperData.changed_cost(today, trip) > trip.cost_per_tonne_km
end

@testset "the explorer gives each input its value known today" begin
    io = IOBuffer()
    PaperData.write_json(io, Assumption(3000.0, 1200.0, 6900.0, "h", "", 1200.0, false))
    @test occursin("\"today\":1200.0", String(take!(io)))
end

@testset "routing anew at today's values gains a rig the difference of its savings, \
          departure by departure" begin
    table = Dict("rig" => ["none", "kite", "none", "kite"], "departure" => [0, 0, 24, 24],
        "recosted" => [10.0, 9.0, 10.0, 8.0], "rerouted" => [10.0, 8.0, 9.0, 7.2])
    @test PaperData.rerouting_gains(table, "kite") ≈ [10.0, 0.0]
end

@testset "the fuel premium a rig closes is ranged over the ship lengths it was run at" begin
    rows = [("base", "vlsfo", 85.0, 0, 0, 0, 1.0), ("base", "ammonia", 85.0, 0, 0, 0, 1.5),
        ("base", "ammonia", 85.0, 800, 0, 0, 1.2),
        ("base", "ammonia", 85.0, 1600, 0, 0, 1.25),
        ("high", "ammonia", 85.0, 800, 0, 0, 1.0),
        ("base", "ammonia", 85.0, 0, 0, 400, 1.3),
        ("base", "ammonia", 85.0, 0, 300, 0, 1.4), ("base", "vlsfo", 140.0, 0, 0, 0, 1.0),
        ("base", "ammonia", 140.0, 0, 0, 0, 1.4),
        ("base", "ammonia", 140.0, 800, 0, 0, 1.1)]
    names = ("scenario", "drive", "length", "kite_area", "wing_area", "rotor_area", "cost")
    designs = Dict(name => getindex.(rows, k) for (k, name) in enumerate(names))
    @test Dict(PaperData.design_premium_numbers(designs)) == Dict(
        "DesignPremium" => "40 to 50", "DesignPremiumBestRig" => "20",
        "DesignPremiumClosedKite" => "60 to 75", "DesignPremiumClosedWings" => "20",
        "DesignPremiumClosedRotors" => "40")
end

@testset "a pair's extra saving has its standard error over the departures as noise" begin
    rows = [(route, rig, kite_area, rotor_area, cost)
            for (route, pair_costs) in (("steady", fill(7.0, 4)), ("varying", [7, 8, 7, 8.0]))
            for (rig, kite_area, rotor_area, costs) in (("none", 0.0, 0.0, fill(10.0, 4)),
                ("kite", 900.0, 0.0, fill(9.0, 4)), ("rotors", 0.0, 400.0, fill(8.0, 4)),
                ("kite+rotors", 500.0, 400.0, fill(9.0, 4)),
                ("kite+rotors", 900.0, 200.0, pair_costs))
            for cost in costs]
    column(k) = getindex.(rows, k)
    table = Dict("ship" => fill("Handysize", length(rows)),
        "drive" => fill("ammonia", length(rows)), "route" => column(1), "rig" => column(2),
        "kite_area" => column(3), "rotor_area" => column(4), "cost" => column(5))
    steady, varying = PaperData.pair_gain_errors(table)
    @test steady ≈ 0 atol = 1e-12
    @test varying ≈ sqrt(100 / 3) / 2
    lost = findlast(row -> row[1:2] == ("varying", "kite"), rows)
    @test_throws ArgumentError PaperData.pair_gain_errors(
        Dict(key => deleteat!(copy(values), lost) for (key, values) in table))
end

@testset "the development study keeps 5 to 20 inputs ranged by data or goals, each with a \
          reason" begin
    inputs = PaperData.development_inputs
    @test 5 <= length(inputs) <= 20
    @test allunique(entry.input for entry in inputs)
    for entry in inputs
        low, high = (PaperData.bound_assumptions(entry.input, bound)
                     for bound in (:low, :high))
        moved = filter(name -> low[name] != high[name], collect(keys(assumptions.entries)))
        @test !isempty(moved)
        @test !any(name -> assumptions.entries[name].estimate, moved)
        @test !isempty(entry.reason)
    end
    for rig in PaperData.rig_names
        levers = [entry.lever for entry in inputs if rig in PaperData.lever_rigs(entry)]
        @test "force" in levers && "availability" in levers
    end
end

@testset "the model parts measured by the development study read only its inputs" begin
    PaperData.eval(:(departures = 1:8760))
    @test !isempty(PaperData.fidelity_parts())
end

@testset "holding deck rigs to one row keeps the best size that stands in one row" begin
    hull = Hull(ship_classes()["Capesize bulk carrier"], assumptions)
    columns(count) = PaperData.deck_columns(WindShipOpt.RotorRig(800.0, hull, assumptions;
        columns=count, in_column=2))
    @test columns(2) == 2
    @test columns(1) == 1
    @test PaperData.deck_columns(nothing) == 0
    table = Dict("rig" => ["none", "kite", "rotors", "rotors"], "columns" => [0, 0, 1, 2],
        "cost" => [1.0, 0.85, 0.9, 0.8])
    every, one_row = only(last(PaperData.one_row()))
    @test PaperData.best_costs(table, every)["rotors"] == 0.8
    held = PaperData.best_costs(table, one_row)
    @test held["rotors"] == 0.9 && held["kite"] == 0.85 && held["none"] == 1.0
end

@testset "deck rigs are searched up to what fits on a container ship's deck, and not \
          where their smallest size does not" begin
    class = ship_classes()["feeder container ship"]
    hull = Hull(class, assumptions)
    lower, upper = PaperData.size_bounds(class)["suction"]
    @test lower == PaperData.smallest_deck_rig_area
    @test PaperData.deck_rig_fits("suction", upper, hull)
    @test !PaperData.deck_rig_fits("suction", upper + 20, hull)
    raised = PaperData.deck_rig("suction", 200.0, hull; columns=2)
    @test PaperData.deck_rig_name(raised) == "suction"
    smallest = PaperData.smallest_deck_rig_area
    try
        PaperData.smallest_deck_rig_area = 2upper
        @test !haskey(PaperData.size_bounds(class), "suction")
    finally
        PaperData.smallest_deck_rig_area = smallest
    end
end

@testset "a VTOL kite is searched from 20 m^2 to the largest whose perch fits" begin
    class = ship_classes()["Kamsarmax bulk carrier"]
    lower, upper = PaperData.size_bounds(class)["vtol"]
    @test lower == 20.0
    hull = Hull(class, assumptions)
    @test upper ≈ WindShipOpt.largest_rigid_kite_area(hull, assumptions)
    @test PaperData.rig_size("vtol", upper) == (; rigid_kite_area=upper)
end

@testset "a VTOL kite on a container ship perches across its bow" begin
    hull = Hull(ship_classes()["Neo-Panamax container ship"], assumptions)
    @test WindShipOpt.largest_rigid_kite_area(hull, assumptions) ≈
          hull.beam^2 / assumptions[:rigid_aspect_ratio]
    rig = WindShipOpt.rigid_kite_rig(80.0, hull, assumptions; courses=[π / 2],
        side_weights=[0.0])
    @test rig.attach_position ≈ WindShipOpt.launch_mast_position(hull, assumptions)
end

@testset "an LEI kite's tubes grow as area^1.5 and with its force per area" begin
    reference = assumptions[:lei_reference_area]
    at_reference = with_value(assumptions, :lei_max_force_per_area,
        assumptions[:lei_reference_force_per_area])
    @test WindShipOpt.tube_mass(at_reference, reference) ≈ assumptions[:lei_tube_mass]
    @test 400reference * WindShipOpt.tube_mass(at_reference, 400reference) ≈
          8000reference * assumptions[:lei_tube_mass]
    doubled = with_value(at_reference, :lei_max_force_per_area,
        2assumptions[:lei_reference_force_per_area])
    @test WindShipOpt.tube_mass(doubled, reference) ≈ 2assumptions[:lei_tube_mass]
end

@testset "an LEI canopy is one skin and its tubes, priced as a ram-air canopy" begin
    frame, area = WindShipOpt.TubeFrame(), 200.0
    rating = assumptions[:lei_max_force_per_area] /
             assumptions[:canopy_cloth_reference_force]
    weight = assumptions[:canopy_cloth_weight] * rating
    tubes = WindShipOpt.tube_mass(assumptions, area)
    surface = assumptions[:lei_tube_surface]
    canopy = WindShipOpt.Canopy(assumptions, area, frame)
    @test canopy.mass_per_area ≈ 1e-3assumptions[:lei_flat_area_ratio] * weight +
                                 assumptions[:canopy_mass_overhead] * rating + tubes
    price(weight) = assumptions[:canopy_cloth_base_price] +
                    assumptions[:canopy_cloth_price_per_weight] * weight
    @test canopy.cost_per_area ≈ WindShipOpt.sewing_cost(assumptions) +
                                 assumptions[:lei_flat_area_ratio] * price(weight) +
                                 surface * price(1e3tubes / surface)
    @test WindShipOpt.canopy_price(assumptions, area, 3.0, frame) ≈
          assumptions[:market_price_factor] * canopy.cost_per_area
end

@testset "an LEI kite flies the measured V3 polar at the ram-air kite's glide ratio" begin
    lift = 0.8
    model, force, = WindShipOpt.kite_model(1.0, assumptions[:lei_aspect_ratio], assumptions,
        WindShipOpt.TubeFrame())
    polar = model.polar
    drag = WindShipOpt.polar_value(polar, polar.drag, WindShipOpt.lift_angle(polar, lift))
    @test lift / (drag + model.extra_drag) ≈
          lift / WindShipOpt.total_drag_at_lift(3.0, lift, assumptions) rtol = 0.02
    @test maximum(polar.lift) < maximum(WindShipOpt.KitePolar(3.0).lift)
    @test force ≈ 1e3assumptions[:lei_max_force_per_area]
end

@testset "an LEI kite is built up to the largest size that can still launch" begin
    largest = WindShipOpt.largest_lei_kite_area(assumptions)
    model, = WindShipOpt.kite_model(largest, assumptions[:lei_aspect_ratio], assumptions,
        WindShipOpt.TubeFrame())
    @test WindShipOpt.launch_min_wind(model, assumptions) ≈
          assumptions[:kite_launch_max_wind] rtol = 1e-6
    @test isnothing(WindShipOpt.lei_kite_rig(1.01largest, PAPER_HULL, assumptions))
    @test_throws ArgumentError WindShipOpt.design_rig(
        ShipDesign(:vlsfo, 140.0; lei_kite_area=200.0, kite_area=800.0), PAPER_HULL,
        assumptions)
end

@testset "an LEI kite's station, control unit and tether are a ram-air kite's" begin
    hull = PAPER_HULL
    rig = KiteRig(200.0, assumptions[:lei_aspect_ratio], hull, assumptions;
        courses=[π / 2], frame=WindShipOpt.TubeFrame())
    @test rig.airframe isa WindShipOpt.TubeFrame
    @test WindShipOpt.rig_price_parts(rig, assumptions) ==
          WindShipOpt.kite_price_parts(rig.area, rig.max_force, assumptions)
    canopy, = WindShipOpt.consumable_costs(rig, assumptions)
    @test canopy ≈ WindShipOpt.canopy_price(assumptions, rig.area, rig.aspect_ratio,
        rig.airframe) * rig.area
    @test WindShipOpt.kite_mass(rig, assumptions) ≈
          WindShipOpt.Canopy(assumptions, rig.area, rig.airframe).mass_per_area * rig.area +
          1e-3assumptions[:control_unit_mass_per_force] * rig.max_force
end

@testset "every rig has its name, life and availability inputs" begin
    rigs = Set(PaperData.rig_names)
    for names in (PaperData.rig_keywords, PaperData.lifetime_inputs,
        PaperData.out_of_service_inputs, PaperData.rig_subjects, PaperData.rig_short_names)
        @test issubset(rigs, keys(names))
    end
    @test issubset(PaperData.deck_rig_names, PaperData.rig_names)
    @test issubset(rigs, first.(PaperData.reference_rigs))
end

@testset "a development ship whose rig has no size in the class study stops the run" begin
    PaperData.eval(:(best_area(table, class, route, drive, rig) =
        rig == "wings" ? NaN : 100.0))
    @test_throws ErrorException PaperData.study_areas(nothing, "class", :route, :vlsfo)
end

@testset "a development input's gain and loss are the largest of its rigs with trips" begin
    PaperData.eval(:(bound_changes(table, ship, rig, input; column="cost") =
        rig == "kite" ? (1.0, -2.0) : rig == "wings" ? (NaN, 1.0) : (0.5, 0.0)))
    lever(rig) = PaperData.lever_gain_loss(nothing, "ship", (input=:any, rig))
    @test lever("condition") == (1.0, -2.0)
    @test lever("rotors") == (0.5, 0.0)
    gain, loss = lever("wings")
    @test isnan(gain) && isnan(loss)
end

@testset "the input table gives a range only where data do, and marks each estimate" begin
    row(name) = sprint(PaperData.write_input_row, assumptions.entries[name], name)
    @test occursin("\\textsuperscript{e} &  & ", row(:crew_cost))
    @test occursin(r"& \S+--\S+ &", row(:canopy_life))
    @test !occursin("textsuperscript", row(:canopy_life))
end

@testset "an input has a range only where data give one, and an estimate has none" begin
    for (name, entry) in assumptions.entries
        @test entry.low <= entry.value <= entry.high
        @test !entry.estimate || entry.low == entry.high
        startswith(entry.source, "Authors' estimate") && @test entry.estimate
    end
end

@testset "every input names its source in one short line" begin
    for entry in values(assumptions.entries)
        @test 0 < length(entry.source) <= 80 && !occursin('\n', entry.source)
    end
end

@testset "the input table points only to appendix sections the paper has" begin
    paper_sections = joinpath(pkgdir(WindShipOpt), "paper", "sections")
    labels = Set(found[1] for file in readdir(paper_sections; join=true)
                 for found in eachmatch(r"\\label\{([^}]*)\}", read(file, String)))
    for (name, label) in PaperData.input_derivations
        @test haskey(assumptions, name) && label in labels
    end
end

"""
    fleet_cell(bill, savings, wobble=Dict())

Fleet cell of `bill` with the cost `savings` [%] of its rigs over two departures, each
rig's saving on one departure `wobble[rig]` points below and on the other above it.
"""
function fleet_cell(bill, savings, wobble=Dict())
    costs(rig, saving) = (1 - saving / 100) .+ [1, -1] .* get(wobble, rig, 0.0) ./ 100
    return (; bill, savings, departures=Dict("none" => [1.0, 1.0],
        (rig => costs(rig, saving) for (rig, saving) in savings)...))
end

@testset "a gap's error over departures cancels what the rigs' weather shares" begin
    shared = fleet_cell(1.0, Dict("kite" => 10.0, "rotors" => 8.0),
        Dict("kite" => 3.0, "rotors" => 3.0))
    @test PaperData.gap_error([shared], [1.0], "kite", "rotors") == (0.0, 2)
    error, n = PaperData.gap_error([shared], [1.0], "kite", "none")
    @test error ≈ 3.0 && n == 2
    apart = fleet_cell(1.0, Dict("kite" => 10.0, "rotors" => 8.0),
        Dict("kite" => -3.0, "rotors" => 3.0))
    @test first(PaperData.gap_error([shared, apart], [3.0, 1.0], "kite", "rotors")) ≈ 1.5
end

@testset "a rig leads only by more than its gap's error and the router's bias" begin
    @test PaperData.lead_factor(2) ≈ 1.837 atol=0.04
    @test PaperData.lead_factor(12) ≈ 1.0476 atol=0.001
    @test PaperData.lead_factor(10^6) ≈ 1 atol=1e-5
    bias = PaperData.kite_gap_bias
    @test PaperData.leads("kite", "rotors", 0.5, (0.2, 12))
    @test !PaperData.leads("kite", "rotors", 0.5, (0.5, 12))
    @test !PaperData.leads("rotors", "kite", bias, (0.0, 12))
    @test PaperData.leads("rotors", "kite", bias + 0.1, (0.0, 12))
    @test PaperData.leads("rotors", "wings", 0.1, (0.0, 12))
end

@testset "a fleet's cost goes to the clear leader, or to level within the error" begin
    rigs(kite, wings, rotors) = Dict("kite" => kite, "wings" => wings, "rotors" => rotors)
    band(savings, wobble=Dict()) = PaperData.fleet_band(fleet_cell(1.0, savings, wobble))
    bias = PaperData.kite_gap_bias
    @test band(rigs(5.0, 2.0, 3.0), Dict("kite" => 1.0, "rotors" => 1.0)) == "kite"
    @test band(rigs(5.0, 4.0, 2.0), Dict("kite" => 1.0, "wings" => 0.0)) == "level"
    @test band(rigs(2.0, 2.0, 3.0 + bias)) == "rotors"
    @test band(rigs(3.0, 2.0, 3.0 + bias)) == "level"
    @test band(rigs(1.0, -1.0, 0.0), Dict("kite" => 1.0)) == "none"
    split = PaperData.fleet_split([fleet_cell(100.0, rigs(10.0, 0.0, 2.0)),
        fleet_cell(50.0, rigs(4.0, 0.0, 4.0)),
        fleet_cell(50.0, rigs(-1.0, -2.0, 0.5), Dict("rotors" => 1.0))])
    @test split["kite"] == (bill=100.0, saved=10.0)
    @test split["level"] == (bill=50.0, saved=2.0)
    @test split["none"] == (bill=50.0, saved=0.0)
    @test split["rotors"].bill == split["wings"].bill == 0
end

"rig lead row of the made-up outcome of `rig` against `rival` on ship type `word`"
function lead_row(word, drive, verdict, margin, rig="kite", rival="rotors")
    label = only(label for (type, label, _) in PaperData.ship_types if type == word)
    return (; word, label, name=lowercase(label), where=PaperData.ship_places, drive, rig,
        rival, verdict, margin)
end

"rig lead rows of the draft run: the kite leading or level with the rotors"
draft_leads = [lead_row("Container", "vlsfo", "leads", 4.1),
    lead_row("Container", "ammonia", "leads", 3.8),
    lead_row("CarCarrier", "vlsfo", "level", 0.3),
    lead_row("CarCarrier", "ammonia", "level", 0.2),
    lead_row("BulkCarrier", "vlsfo", "level", 1.2),
    lead_row("BulkCarrier", "ammonia", "level", 0.9),
    lead_row("Tanker", "vlsfo", "level", 1.0), lead_row("Tanker", "ammonia", "leads", 2.3),
    lead_row("GeneralCargo", "vlsfo", "leads", 3.1),
    lead_row("GeneralCargo", "ammonia", "level", 1.1)]

@testset "a verdict states each kind of lead once, with where it holds" begin
    lead = lead_row("Container", "vlsfo", "leads", 2.4)
    @test PaperData.verdict_text([lead]) == "the kite leads the rotors by 2 points"
    @test PaperData.verdict_text([lead_row("Container", "vlsfo", "level", 2.4, "rotors",
        "kite")]) == "the kite and the rotors are level, 2 points apart"
    @test PaperData.verdict_text([lead_row("Container", "vlsfo", "none", 0.1)]) ==
          "no rig clearly saves"
    container = filter(row -> row.word == "Container", draft_leads)
    @test PaperData.verdict_text(container) ==
          "the kite leads the rotors by 4 points on both fuels"
    @test PaperData.verdict_text(draft_leads) ==
          "the kite leads the rotors by 2 to 4 points on container ships on both fuels, " *
          "on tankers on e-ammonia and on general cargo ships on fuel oil, and the kite " *
          "and the rotors are level, at most 1 point apart, on car carriers and bulk " *
          "carriers on both fuels, on tankers on fuel oil and on general cargo ships on " *
          "e-ammonia"
end

@testset "the advice gives the rigs for both fuels once, then where the fuel changes" begin
    @test PaperData.advice_text(draft_leads) ==
          "on both fuels use the kite on container ships, and either the kite or the " *
          "rotors on car carriers and bulk carriers; on tankers use the kite on " *
          "e-ammonia and either the kite or the rotors on fuel oil, and on general cargo " *
          "ships the other way round"
    all_kite = [(; row..., verdict="leads") for row in draft_leads]
    @test PaperData.advice_text(all_kite) == "on both fuels use the kite on every ship type"
    ammonia = filter(row -> row.drive == "ammonia", draft_leads)
    @test PaperData.advice_text(ammonia) ==
          "on e-ammonia use the kite on container ships and tankers, and either the kite " *
          "or the rotors on car carriers, bulk carriers and general cargo ships"
end

@testset "the brief advice names each ship type's rigs on any fuel, most types last" begin
    @test PaperData.brief_advice_text(draft_leads) ==
          "the kite on container ships and the kite or the rotors on the other ship types"
    all_kite = [(; row..., verdict="leads") for row in draft_leads]
    @test PaperData.brief_advice_text(all_kite) == "the kite on every ship type"
    no_cars = [row.word == "CarCarrier" ? (; row..., verdict="none") : row
               for row in draft_leads]
    @test PaperData.brief_advice_text(no_cars) ==
          "the kite on container ships, no rig on car carriers and the kite or the " *
          "rotors on the other ship types"
end

@testset "the answer gives the range of what the rig to fit saves a ship a year" begin
    saved(share, usd, carbon) = (; saved=usd, share, carbon)
    per_ship = Dict("kite" => saved(14.2, 5.3e6, 9.6e9), "wings" => saved(4.5, 1.7e6, 2.9e9),
        "rotors" => saved(13.8, 4.1e6, 9.2e9))
    rows = [(; row..., per_ship) for row in draft_leads if row.drive == "vlsfo"]
    @test isempty(PaperData.advised_savings((; rows[1]..., verdict="none")))
    @test Dict(PaperData.answer_ranges(rows)) == Dict("Shares" => "14",
        "Carbon" => "\\num{9200} to \\num{9600}", "MoneyLow" => "\\num{4.1}",
        "MoneyLowShips" => "car carriers", "MoneyHigh" => "\\num{5.3}",
        "MoneyHighShips" => "container ships")
end

@testset "the forecast lead of the kite over the rotors is signed and paired" begin
    rigs = ["none", "kite", "rotors"]
    costs = Dict("none" => [10.0, 10.0], "kite" => [8.0, 9.0], "rotors" => [9.0, 9.0])
    table = Dict("rig" => repeat(rigs; inner=2), "plan" => fill("live", 6),
        "cost" => reduce(vcat, costs[rig] for rig in rigs))
    @test PaperData.forecast_saving(table, "kite", "live") ≈ 15
    @test PaperData.forecast_lead_cell(table, "live") == "\\(+5 \\pm 5\\)"
    @test isnan(PaperData.forecast_saving(table, "wings", "live"))
end

@testset "the highlight of the advice fits the journal for any kind of advice" begin
    @test PaperData.highlight_text(draft_leads) ==
          "On e-ammonia: kite on container ships and tankers, either kite or rotors " *
          "elsewhere."
    kinds = [("leads", "kite", "rotors"), ("leads", "rotors", "kite"),
        ("leads", "wings", "rotors"), ("level", "kite", "rotors"),
        ("level", "wings", "rotors"), ("none", "kite", "rotors")]
    words = first.(PaperData.ship_types)
    outcome(picks) = [lead_row(word, drive, kinds[kind][1], 2.0, kinds[kind][2:3]...)
                      for (word, pick) in zip(words, picks)
                      for (drive, kind) in (("vlsfo", length(kinds) + 1 - pick),
                          ("ammonia", pick))]
    outcomes = Iterators.product(fill(eachindex(kinds), length(words))...)
    @test all(length(PaperData.highlight_text(outcome(picks))) <= PaperData.highlight_limit
              for picks in outcomes)
end

@testset "a ship type where the best rig does not clearly save has no leader" begin
    savings = Dict("kite" => 1.0, "wings" => 0.2, "rotors" => -0.5, "suction" => 0.1,
        "vtol" => 0.0)
    lead = PaperData.rig_lead([fleet_cell(1.0, savings, Dict("kite" => 2.0))])
    @test lead.verdict == "none"
    @test PaperData.rig_lead([fleet_cell(1.0, savings)]).verdict == "leads"
end

@testset "fleet work takes each class's IMO bins, summing the two of the MR tanker" begin
    work, share = PaperData.fleet_work()
    @test length(work) == 13
    @test work["Kamsarmax bulk carrier"] ≈ 7974.7 * 1.852e9
    @test work["MR product tanker"] ≈ (524.7 + 2186.0) * 1.852e9
    @test share ≈ 0.6218 atol=1e-4
end

@testset "a fleet's cost is each class's work over its routes at its bare cost" begin
    work, _ = PaperData.fleet_work()
    routes, drive = ["caribbean", "dakar", "tubarao"], "vlsfo"
    class, route = "Kamsarmax bulk carrier", first(routes)
    rigs = ("none", PaperData.rig_names...)
    cases = vec([(; class=name, route=leg, rig)
                  for name in keys(work), leg in routes, rig in rigs])
    function cost(case)
        (case.class, case.route) == (class, route) || return 0.01
        return case.rig == "none" ? 0.02 : case.rig == "kite" ? 0.018 : 0.02
    end
    table(kept) = Dict{String, Vector}("class" => getfield.(kept, :class),
        "route" => getfield.(kept, :route), "drive" => fill(drive, length(kept)),
        "rig" => getfield.(kept, :rig), "cost" => cost.(kept),
        "departure_costs" => [fill(cost(case), 2) for case in kept])
    split = PaperData.fleet_split_of(table(cases), drive)
    bill = work[class] / length(routes) * 0.02
    @test split["kite"].bill ≈ bill
    @test split["kite"].saved ≈ bill * 0.1
    @test PaperData.fleet_total(split, :bill) ≈ sum(values(work)) * 0.01 + bill / 2
    without(rig) = filter(cases) do case
        return (case.class, case.route, case.rig) != (class, route, rig)
    end
    for rig in ("none", "rotors")
        @test_throws "$class on $route" PaperData.fleet_split_of(table(without(rig)), drive)
    end
end

"""
    market_class_table()

A class table on VLSFO over three routes in which only the Kamsarmax bulk carrier gains
from a rig: the rotors save 10 % of its cost on one route and 5 % on another, the wing
sails 4.5 % on the second, level with the rotors as the two swap a point over its two
departures. Without a rig the Kamsarmax costs 0.02 per tonne-kilometre and every other
class 0.01. Every rig saves a third of the fuel and a quarter of the CO2.
"""
function market_class_table()
    work, _ = PaperData.fleet_work()
    routes, drive, class = ["caribbean", "dakar", "tubarao"], "vlsfo", "Kamsarmax bulk carrier"
    costs = Dict(("caribbean", "none") => 0.02, ("caribbean", "rotors") => 0.018,
        ("dakar", "none") => 0.02, ("dakar", "rotors") => 0.019,
        ("dakar", "wings") => 0.0191)
    cases = vec([(; class=name, route, rig) for name in keys(work), route in routes,
                 rig in ("none", PaperData.rig_names...)])
    function cost(case)
        case.class == class || return 0.01
        return get(costs, (case.route, case.rig), 0.02)
    end
    swap = Dict("rotors" => 1e-4, "wings" => -1e-4)
    function departure_costs(case)
        (case.class, case.route) == (class, "dakar") || return fill(cost(case), 2)
        return cost(case) .+ [-1, 1] .* get(swap, case.rig, 0.0)
    end
    column(f) = f.(cases)
    table = Dict{String, Vector}("class" => column(case -> case.class),
        "route" => column(case -> case.route), "drive" => fill(drive, length(cases)),
        "rig" => column(case -> case.rig), "cost" => cost.(cases),
        "departure_costs" => departure_costs.(cases),
        "area" => column(case -> case.rig == "wings" ? 1500.0 : 1000.0),
        "units" => column(case -> case.rig == "wings" ? 3.0 : 5.0),
        "fuel" => column(case -> case.rig == "none" ? 0.03 : 0.02),
        "carbon" => column(case -> case.rig == "none" ? 2.0 : 1.5),
        "retractable" => fill("true", length(cases)))
    return (; table, cases, class, drive)
end

@testset "a rig's market counts the cells it leads alone, and up to those it leads level" begin
    work, _ = PaperData.fleet_work()
    ships = PaperData.fleet_ships()
    (; table, cases, class, drive) = market_class_table()
    markets = PaperData.cell_markets(table, drive)
    market = PaperData.fleet_market(markets)
    @test PaperData.fleet_market(filter(cell -> cell.type == "bulk carrier", markets)) ==
          market
    @test all(iszero, PaperData.fleet_market(filter(cell -> cell.type == "container",
        markets))["any"].high)
    cell_ships, cell_work = ships[class] / 3, work[class] / 3
    rotors = market["rotors"]
    @test rotors.low.ships ≈ cell_ships
    @test rotors.high.ships ≈ 2cell_ships
    @test rotors.low.units ≈ 5cell_ships
    @test rotors.low.area ≈ 1000cell_ships
    @test rotors.low.saved ≈ cell_work * 0.02 * 0.1
    heating_value = WindShipOpt.vlsfo(assumptions, 0.0).heating_value
    @test rotors.low.fuel ≈ cell_work * 0.01e6 / heating_value
    @test rotors.low.carbon ≈ cell_work * 0.5
    row = only(i for i in eachindex(cases)
               if cases[i] == (; class, route="caribbean", rig="rotors"))
    price, _ = PaperData.rig_price(table, row)
    @test price > 0
    @test rotors.low.sales ≈ cell_ships * price
    @test all(iszero, market["wings"].low)
    @test market["wings"].high.ships ≈ cell_ships
    @test all(iszero, market["kite"].high)
    @test market["any"] == rotors
end

@testset "a class leads over its routes by its mean gap and that gap's own error" begin
    (; table, class, drive) = market_class_table()
    cells = PaperData.fleet_cells(table, drive)
    lead = PaperData.rig_lead(filter(cell -> cell.class == class, cells))
    @test (lead.rig, lead.rival) == ("rotors", "wings")
    @test lead.margin ≈ (10 + 0.5) / 3
    @test lead.error ≈ 1 / 3
    @test lead.verdict == "leads"
    bands = PaperData.fleet_band.(cells)
    @test count(==("rotors"), bands) == count(==("level"), bands) == 1
    @test count(==("none"), bands) == length(bands) - 2
end

@testset "a run of three rigs leads and sums over those three alone" begin
    (; table, class, drive) = market_class_table()
    held = findall(in(("none", "kite", "wings", "rotors")), table["rig"])
    three = Dict{String, Vector}(name => column[held] for (name, column) in table)
    cells = PaperData.fleet_cells(three, drive)
    @test all(Set(keys(cell.savings)) == Set(("kite", "wings", "rotors")) for cell in cells)
    lead = PaperData.rig_lead(filter(cell -> cell.class == class, cells))
    @test (lead.rig, lead.rival, lead.verdict) == ("rotors", "wings", "leads")
end

@testset "a ship type's saving per ship is what each rig saves it, over its ships" begin
    work, _ = PaperData.fleet_work()
    ships = PaperData.fleet_ships()
    (; table, class, drive) = market_class_table()
    classes = PaperData.ship_classes()
    savings = PaperData.type_savings(table, drive)
    bulk = only(saving for saving in savings if saving.type == "bulk carrier")
    bulk_classes = [name for name in keys(work) if classes[name].type == "bulk carrier"]
    bulk_ships = sum(ships[name] for name in bulk_classes)
    bulk_work = sum(work[name] for name in bulk_classes)
    saved = work[class] / 3 * 0.02 * (0.10 + 0.05)
    bill = 0.01 * bulk_work + 0.01 * work[class]
    rotors = bulk.rigs["rotors"]
    @test rotors.saved * bulk_ships ≈ saved
    @test rotors.share ≈ 100saved / bill
    heating_value = WindShipOpt.vlsfo(assumptions, 0.0).heating_value
    @test rotors.fuel * bulk_ships ≈ bulk_work * 0.01e6 / heating_value
    @test rotors.carbon * bulk_ships ≈ bulk_work * 0.5
    @test iszero(bulk.rigs["kite"].saved)
    @test bulk.rigs["wings"].share < rotors.share
    container = only(saving for saving in savings if saving.type == "container")
    @test isempty(container.leaders)
    @test all(saving -> iszero(saving.rigs["rotors"].saved), filter(!=(bulk), savings))
end

@testset "a rig size the class study did not run is an error, not a ship without a rig" begin
    @test PaperData.rig_size("none", NaN) == (;)
    @test PaperData.rig_size("kite", 1600.0) == (; kite_area=1600.0)
    @test_throws ArgumentError PaperData.rig_size("kite", NaN)
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
    force = WindShipOpt.best_trim(ship, ship.rig, 5.0, wind, angle).force
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

@testset "an exported passage keeps the routed track and the rig's frame" begin
    @test PaperData.wind_side(-10.0, 0.0, 0.0) == 1
    @test PaperData.wind_side(10.0, 0.0, 0.0) == -1
    position(radial, side=1) = PaperData.ship_frame_position(radial, π / 2, side)
    @test all(isapprox.(position((1.0, 0.0, 0.0)), (-90.0, 0.0); atol=1e-9))
    @test all(isapprox.(position((1.0, 0.0, 0.0), -1), (90.0, 0.0); atol=1e-9))
    @test all(isapprox.(position((0.0, 1.0, 0.0)), (0.0, 0.0); atol=1e-9))
    @test all(isapprox.(position((0.0, 0.0, 1.0)), (0.0, 90.0); atol=1e-9))
    chord(direction, side=1) = PaperData.chord_angles((0.0, 1.0, 0.0), direction, π / 2,
        side)
    @test all(isapprox.(chord((0.0, 0.0, 1.0)), (0.0, 0.0); atol=1e-9))
    @test all(isapprox.(chord((1.0, 0.0, 0.0)), (-90.0, 0.0); atol=1e-9))
    @test all(isapprox.(chord((1.0, 0.0, 0.0), -1), (90.0, 0.0); atol=1e-9))
    @test last(chord((0.0, 1.0, 0.0))) ≈ 90 atol=1e-9
    @test all(isapprox.(PaperData.kite_chord((0.0, 0.0, 1.0), (10.0, 0.0, 0.0), 0.2),
        (-cos(0.2), 0.0, sin(0.2)); atol=1e-12))
    wing_ship = Ship(ShipDesign(:methanol, 85.0; wing_area=300.0), assumptions)
    wings = wing_ship.rig
    attached_range, stalled_range = WindShipOpt.trim_ranges(wings, wing_ship.env, 10.0,
        π / 2, 5.0)
    attached = WindShipOpt.trim_setting(wings, attached_range, 0.0)
    stalled = WindShipOpt.trim_setting(wings, stalled_range, 90.0)
    @test PaperData.wing_incidence(wings, attached) == 0.0
    @test rad2deg(PaperData.wing_incidence(wings, stalled)) ≈ 90 atol=1e-6
    design = ShipDesign(:methanol, 85.0; rotor_area=100.0)
    ship = Ship(design, assumptions)
    routing = shared_route_table(design)
    table = routing.table
    outbound, _ = corridors
    weather = SyntheticWeather()
    leg = route(outbound, routing, weather, 24.0 * 31; time_cost=300.0)
    trace = LegTrace(table, leg, weather, 24.0 * 31)
    case = (; index=0, ship, patterns=nothing)
    exported = PaperData.recorded_leg(case, leg, trace, "out", 0, 24.0 * 31)
    @test exported.columns.lat == round.(Int, trace.lat .* 100)
    @test exported.columns.lon == round.(Int, trace.lon .* 100)
    port_of_north = PaperData.wind_side.(trace.wind_east, trace.wind_north, trace.course)
    @test exported.columns.apparent_angle ==
          round.(Int, rad2deg.(port_of_north .* trace.apparent_angle))
    @test any(<(0), exported.columns.apparent_angle) &&
          any(>(0), exported.columns.apparent_angle)
    @test all(abs(spin) <= 400 for spin in exported.columns.trim.spin)
end

@testset "a kite's recorded pattern flies on the lee side in the ship's frame" begin
    model, max_force, _ = WindShipOpt.kite_model(500.0, assumptions[:kite_aspect_ratio],
        assumptions)
    table = (; wind_speeds=[12.0], courses=[deg2rad(90.0)], side_weights=[0.0], max_force)
    cycle = only(PaperData.kite_patterns((; rig=table), model))
    @test length(cycle.radials) == length(cycle.chords) == PaperData.pattern_samples
    @test cycle.period > 0
    azimuths = [first(PaperData.ship_frame_position(radial, deg2rad(90.0), 1))
                for radial in cycle.radials]
    @test all(azimuth < 0 for azimuth in azimuths)
end

@testset "a kite held still upwind is exported as one sample, its nose into the wind" begin
    model, max_force, _ = WindShipOpt.kite_model(500.0, assumptions[:kite_aspect_ratio],
        assumptions)
    table = (; wind_speeds=[10.5], courses=[π], side_weights=[0.0], max_force)
    cycle = only(PaperData.kite_patterns((; rig=table), model))
    @test cycle.period == 0
    @test allequal(cycle.radials) && allequal(cycle.chords)
    @test first(only(unique(cycle.chords))) < 0
end

@testset "a recorded cost is the routed cost, depends on its inputs and has no branch" begin
    ship = Ship(ShipDesign(:methanol, 85.0; kite_area=800.0), assumptions)
    trip = round_trip(ship, corridors..., SyntheticWeather(), [24.0 * 31, 24.0 * 200],
        assumptions)
    names = (:canopy_life, :e_methanol_price, :kite_out_of_service, :discount_rate,
        :kite_launch_loss_probability)
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

@testset "switching windage off removes the wind load, and a misnamed part is refused" begin
    ship = Ship(ShipDesign(:ammonia, 140.0), PaperData.assumptions)
    function force(windage)
        load = WindShipOpt.wind_force(windage, ship.env, 15.0, π / 3, 5.0)
        return [getfield(load, name) for name in fieldnames(typeof(load))]
    end
    @test any(component -> abs(component) > 1.0, force(ship.windage))
    @test all(component -> abs(component) < 1e-6,
        force(PaperData.simplified_ship(ship, :windage).windage))
    @test_throws ArgumentError PaperData.rebuilt(ship.windage; not_a_field=0.0)
end

@testset "a free side force leaves the rig's side force without leeway or rudder drag" begin
    ship = Ship(ShipDesign(:ammonia, 140.0), PaperData.assumptions)
    force = RigForce(1e5, 3e5, 3e6, -2e6)
    drag(balance) = balance.leeway_drag + balance.rudder_drag
    free = PaperData.simplified_ship(ship, :side_force)
    @test drag(WindShipOpt.HullBalance(ship, 6.0, force)) > 0
    @test drag(WindShipOpt.HullBalance(free, 6.0, force)) == 0
    @test WindShipOpt.HullBalance(PaperData.simplified_ship(ship, :weak_hull), 6.0,
        force).leeway ≈ 2WindShipOpt.HullBalance(ship, 6.0, force).leeway
end

@testset "a model part the study's recorded run predates prints stale until it reruns" begin
    run = mktempdir()
    rigs = ["none", PaperData.rig_names...]
    write(joinpath(run, "model_parts.csv"), "ship,rig,part,cost\n",
        join(("140 m,$rig,none,1.0\n" for rig in rigs)))
    @eval PaperData study_file(study, name) = joinpath($run, name)
    @test PaperData.study_holds(PaperData.switched(:none))
    @test !PaperData.study_holds(PaperData.switched(:side_force))
    write(joinpath(run, "model_parts.csv"), "ship,rig,part,cost\n",
        join(("140 m,$rig,none,1.0\n" for rig in rigs[1:(end - 1)])))
    @test !PaperData.study_holds(PaperData.switched(:none))
    @test !PaperData.study_holds((:model_parts, "weather_years.csv", "ship", [[()]]))
    @test all(==("\\stale{model_parts}{}") ∘ last, PaperData.side_force_numbers())
    @test length(PaperData.side_force_numbers()) == 4length(PaperData.rig_names)
    @eval PaperData study_file(study, name) = joinpath($run, "missing", name)
    @test_throws ErrorException PaperData.study_holds(PaperData.switched(:side_force))
end

@testset "a held-speed kite saving and its bare ship use the same routes" begin
    case(route, rig, area, pricing, fuel) = (; ship="ship", drive="vlsfo", knots=10.0, route,
        rig, area, pricing, fuel, cost=fuel / 10, flight_share=0.5)
    kite_cases(area, fuel) = [case("sailed", "kite", area, pricing, fuel)
                              for pricing in ("free", "priced")]
    cases = [case("sailed", "none", 0.0, "priced", 100.0);
        case("no kite trip", "none", 0.0, "priced", 300.0);
        kite_cases(400.0, 90.0); kite_cases(800.0, 80.0)]
    table = Dict(string(name) => getproperty.(cases, name) for name in keys(first(cases)))
    routes = PaperData.speed_size_routes(table, (ship="ship", kites=(400.0, 800.0)),
        "vlsfo", 10.0)
    @test routes == ["sailed"]
    saving = PaperData.speed_size_saving(table, "ship", "vlsfo", routes, "kite", 400.0,
        "free", 10.0)
    @test saving.bare_fuel == 100.0
    @test saving.fuel_percent == 10.0
end

@testset "the pattern data has rows only where the kite flies or holds still" begin
    @test all(isempty, written_pattern(3.0, 120))
    for (wind, course) in ((6.0, 120), (12.0, 90))
        paths, forces = written_pattern(wind, course)
        @test !isempty(paths) && !isempty(forces) && !occursin("NaN", paths * forces)
    end
end

@testset "a round trip's cost parts per tonne-km add up to its cost over its hours" begin
    tonne_km_per_tonne = PaperData.tonne_km_per_tonne(corridors...)
    for design in (ShipDesign(:methanol, 85.0),
        ShipDesign(:methanol, 85.0; wing_area=400.0),
        ShipDesign(:methanol, 85.0; kite_area=800.0))

        ship = Ship(design, assumptions; route=:caribbean)
        trip = round_trip(ship, corridors..., SyntheticWeather(), [24.0 * 31, 24.0 * 200],
            assumptions)
        io = IOBuffer()
        PaperData.write_costs(io, (; design, assumptions, route=:caribbean), trip,
            trip.cargo * tonne_km_per_tonne)
        hours, parts... = parse.(Float64, split(chomp(String(take!(io))), ',')[2:end])
        @test hours ≈ 24(trip.outbound_days + trip.return_days +
                     2assumptions[:port_time_per_call]) rtol = 1e-5
        @test sum(parts) ≈ trip.cost_per_tonne_km rtol = 1e-3
    end
end

@testset "the interest level rows hold each class at its value times the factor" begin
    classes = ship_classes()
    name, other = "Kamsarmax bulk carrier", "Neo-Panamax container ship"
    factors = PaperData.cargo_interest_factors()
    value = classes[name].cargo_value
    table = Dict{String, Vector}("class" => [name, name, name, other],
        "cargo_value" => [value * factors.low, value * factors.high, 15000.0,
            classes[other].cargo_value * factors.low],
        "cost" => [1.0, 2.0, 3.0, 4.0])
    @test factors.low < 1 < factors.high
    @test PaperData.interest_level_rows(table, factors.low)["cost"] == [1.0, 4.0]
    @test PaperData.interest_level_rows(table, factors.high)["cost"] == [2.0]
end

@testset "a size search keeps apart classes of one name with cargo of different value" begin
    class = ship_classes()["Kamsarmax bulk carrier"]
    cheap, dear = (PaperData.with_cargo_value(class, value) for value in (100.0, 15000.0))
    search_key(ship) = (ship, "ammonia", "kite", "tubarao")
    searches = Dict(search_key(ship) => Tuple{Float64, Float64}[] for ship in (cheap, dear))
    cases = [(; design=(; class=ship), class=ship.name, drive="ammonia", rig="kite",
                 route="tubarao", area)
             for (ship, area) in ((cheap, 1000.0), (dear, 2000.0))]
    PaperData.record_sizes!(searches, cases, [(; cost_per_tonne_km=1.0), nothing])
    @test searches[search_key(cheap)] == [(1000.0, 1.0)]
    @test searches[search_key(dear)] == [(2000.0, Inf)]
end

@testset "a ship covering one nautical mile an hour along its track sails at one knot" begin
    @test PaperData.speed_along_track(24 * 1.852, 1.0) ≈ 1.0
    @test PaperData.speed_along_track(24 * 1.852, 2.0) ≈ 0.5
end

include("hot_path_checks.jl")
