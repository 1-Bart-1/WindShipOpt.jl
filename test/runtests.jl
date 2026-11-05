using Test
using WindShipOpt
using WindShipOpt: correlation_allowance, bulb_resistance, friction_coefficient

# Numerical example of Holtrop & Mennen (1982), components unchanged in Holtrop (1984).
const PAPER_ENV = Environment(; water_density=1025.0, water_viscosity=1.1883e-6)
const PAPER_HULL = Hull(; length=205.0, beam=32.0, draft=10.0, displacement_volume=37500.0,
    midship_coefficient=0.98, waterplane_coefficient=0.75, centre_of_buoyancy=-0.75,
    bulb_area=20.0, bulb_height=4.0, transom_area=16.0, stern_shape=10.0,
    appendage_area=50.0, appendage_form_factor=1.5)

assumptions = Assumptions()

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

# ~3500 dwt coasters install ~1.5 MW for 12.5 kn, about 1 MW at 11 kn by the cube law.
@testset "coaster resistance and power are in the range of real coasters" begin
    ship = Ship(ShipDesign(:vlsfo, 85.0), assumptions)
    effective_power = resistance(ship.hull, ship.env, 11KNOT) * 11KNOT
    @test 350e3 < effective_power < 800e3
    @test 700 < ship.powertrain.installed_power / 1e3 < 1500
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
    model, max_force, _ = WindShipOpt.kite_model(800.0, 3.0, assumptions)
    pattern = WindShipOpt.SteeringPattern(π / 2, 0.4, 1.3, deg2rad(15))
    path = WindShipOpt.PatternStep[]
    force = WindShipOpt.PatternForce(model, pattern, 12.0, max_force; path)
    load = 0.5model.air_density * 12.0^2 * model.area
    period = sum(step.time for step in path)
    pull_along(axis) = sum(step.tension * step.time * step.radial[axis] for step in path)
    pull = ntuple(pull_along, 3)
    @test all(pull ./ (period * load) .≈ force.force)
    @test maximum(step.tension for step in path) ≈ force.peak_tension * load
    @test maximum(step.tension for step in path) <= max_force
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

@testset "heavier canopy cloth raises the minimum flight wind" begin
    light, heavy = (with_value(assumptions, :canopy_cloth_weight, weight)
                    for weight in (40.0, 160.0))
    light_wind, heavy_wind = (
        WindShipOpt.min_flight_wind(first(WindShipOpt.kite_model(800.0, 3.0, cloth)), cloth)
        for cloth in (light, heavy))
    @test heavy_wind > light_wind
end

@testset "canopy life is the goal input, whatever the cloth weight" begin
    @test WindShipOpt.Canopy(assumptions).lifetime == 4000
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
    held, flown, stowed = WindShipOpt.held_speed(table, speed_index, sample)
    return WindShipOpt.SailedPoint(sample, held, flown, stowed, hours)
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
    corridor, _ = route_corridors(:caribbean, north_atlantic_mask(); scale=8)
    leg = route(corridor, table, SteadyWind(), 0.0; time_cost=prices.time,
        first_stage=size(corridor.lat, 1) - 1, first_aloft=true)
    @test leg.flight_hours > 0
    @test leg.flight_hours < leg.duration
    @test leg.launches == 0
end

@testset "cycle cost sums crew, tear, loss, retry and turn" begin
    rig = uniform_kite(Hull(140.0, assumptions), assumptions)
    canopy, tether = WindShipOpt.consumable_costs(rig, assumptions)
    control_unit = assumptions[:market_price_factor] *
                   WindShipOpt.rig_price_parts(rig, assumptions).control_unit
    @test WindShipOpt.cycle_cost(rig, assumptions) ≈
          1.05 * (85 + 0.00005canopy + 0.00005 * (canopy + tether + control_unit)) + 130
    @test WindShipOpt.forced_landing_cost(rig, assumptions) ≈
          0.05 * (canopy + tether + control_unit)
    @test WindShipOpt.cycle_cost(nothing, assumptions) == 0
end

@testset "a canopy costs its goal price, and USD 234 as built today" begin
    @test WindShipOpt.canopy_price(assumptions) ≈ 149.8
    @test WindShipOpt.canopy_price_today(assumptions) ≈ 234.4
    rig = uniform_kite(Hull(140.0, assumptions), assumptions)
    @test first(WindShipOpt.consumable_costs(rig, assumptions)) ≈ 149.8rig.area
end

@testset "a flown kite wears canopy and tether by their lives" begin
    rig = uniform_kite(Hull(140.0, assumptions), assumptions)
    canopy, tether = WindShipOpt.consumable_costs(rig, assumptions)
    flown = WindShipOpt.wear_cost(rig, assumptions)
    @test flown ≈
          canopy / assumptions[:canopy_life] + tether / assumptions[:tether_lifetime]
    shorter = with_value(assumptions, :canopy_life, 2000.0)
    @test WindShipOpt.wear_cost(rig, shorter) - flown ≈ canopy / 4000
end

@testset "maintenance charges a rig's capital but not the parts wear replaces" begin
    maintenance_of(ship) = ShipCosts(ship, with_value(assumptions, :maintenance_fraction,
        0.04)).fixed_annual - ShipCosts(ship, assumptions).fixed_annual
    kite = Ship(ShipDesign(:methanol, 140.0; kite_area=3200.0), assumptions)
    worn = sum(WindShipOpt.consumable_costs(kite.rig, assumptions))
    @test maintenance_of(kite) ≈ 0.01 * (ShipCosts(kite, assumptions).capital - worn)
    both = Ship(ShipDesign(:methanol, 140.0; kite_area=3200.0, rotor_area=400.0),
        assumptions)
    @test maintenance_of(both) ≈ 0.01 * (ShipCosts(both, assumptions).capital - worn)
    rotors = Ship(ShipDesign(:methanol, 140.0; rotor_area=400.0), assumptions)
    @test maintenance_of(rotors) ≈ 0.01 * ShipCosts(rotors, assumptions).capital
end

# Worked by hand from the true wind: 10 m/s at 10 m, shear exponent 0.05, 5.4 m/s of ship
# speed. Wing mid height 20.73 m gives 10.371 m/s; 90 deg gives 5.40 ahead and 10.371 abeam,
# so 11.692 m/s at 62.49 deg; 45 deg gives 12.733 ahead, 7.333 abeam, 14.694 m/s at
# 29.94 deg; 180 deg gives 4.971 m/s from dead astern. CL 1, CD 0.17631, 800 m^2, array factor 0.95904.
@testset "wing force follows true wind, shear and ship speed as worked by hand" begin
    env = Environment(assumptions)
    wings = WingRig(800.0, Hull(140.0, assumptions), assumptions)
    setting = (1.0, WindShipOpt.drag_coefficient(wings, 1.0))
    force(angle) = rig_force(wings, env, 10.0, deg2rad(angle), 5.4, setting)
    @test force(90).thrust ≈ 51756 rtol = 1e-3
    @test force(90).side ≈ 41416 rtol = 1e-3
    @test force(45).thrust ≈ 35138 rtol = 1e-3
    @test force(45).side ≈ 100995 rtol = 1e-3
    @test force(180).thrust ≈ 2048 rtol = 1e-3
    @test force(0).thrust < 0 < force(0).side
end

# Worked by hand: rotor mid height 23.91 m gives 10.446 m/s, so 11.76 m/s at 62.66 deg and
# 84.7 Pa on 400 m^2. At spin ratio 3 the fit gives CL 9.517, CD 2.634, CP 0.297.
@testset "rotor force and spin power follow the apparent wind as worked by hand" begin
    env = Environment(assumptions)
    rotors = WindShipOpt.RotorRig(400.0, Hull(140.0, assumptions), assumptions)
    beam = rig_force(rotors, env, 10.0, π / 2, 5.4, 3.0)
    @test beam.thrust ≈ 243775 rtol = 1e-3
    @test beam.side ≈ 227311 rtol = 1e-3
    @test beam.power ≈ 118305 rtol = 1e-3
    @test rig_force(rotors, env, 10.0, 0.0, 5.4, 3.0) == WindShipOpt.NO_RIG_FORCE
end

# At rest on the edge of the wind window the massless kite sees the full wind, tan(angle off
# downwind) = G, and T = q A sqrt(CL^2 + CD^2): 70.56 kN x 0.9073 at 12 m/s on 800 m^2.
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

@testset "no flight pattern pulls beyond the window edge of the system glide ratio" begin
    for area in (800.0, 3200.0)
        rig = Ship(ShipDesign(:methanol, 140.0; kite_area=area), assumptions).rig
        model, _, _ = WindShipOpt.kite_model(area, 3.0, assumptions)
        edge = atand(WindShipOpt.best_over_angles((lift, drag) -> lift / drag, model))
        flown = filter(force -> isfinite(force.peak_tension), rig.forces)
        @test maximum(atand(hypot(force.force[2], force.force[3]), force.force[1])
                      for force in flown) <= edge
    end
end

@testset "kite pulls the ship forward only above the upwind limit of its glide ratio" begin
    env = Environment(assumptions)
    for area in (800.0, 3200.0)
        rig = Ship(ShipDesign(:methanol, 140.0; kite_area=area), assumptions).rig
        model, _, _ = WindShipOpt.kite_model(area, 3.0, assumptions)
        limit = WindShipOpt.least_pulling_angle(model, 0.0)
        @test rad2deg(limit) ≈ atand(1 / WindShipOpt.best_over_angles(/, model))
        @test WindShipOpt.least_pulling_angle(model, deg2rad(25)) > limit
        for apparent in deg2rad.(1.0:2.0:(rad2deg(limit) - 2)), wind in (8.0, 12.0, 20.0),
            trim in WindShipOpt.trim_settings(rig)

            @test rig_force(rig, env, wind, apparent, 0.0, trim).thrust <= 0
        end
        @test rig_force(rig, env, 12.0, deg2rad(40), 0.0, 1).thrust > 0
    end
end

@testset "kite, wings and rotors push the same way across the ship" begin
    env = Environment(assumptions)
    hull = Hull(140.0, assumptions)
    kite = uniform_kite(hull, assumptions)
    wings = WingRig(800.0, hull, assumptions)
    rotors = WindShipOpt.RotorRig(400.0, hull, assumptions)
    for angle in deg2rad.((45, 90, 110))
        @test rig_force(kite, env, 12.0, angle, 5.4, 1).side > 0
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
    @test length(WindShipOpt.trim_settings(combined)) ==
          length(WindShipOpt.trim_settings(kite)) *
          length(WindShipOpt.trim_settings(rotors))
    sum_force = rig_force(kite, env, 12.0, π / 2, 6.0, 2) +
                rig_force(rotors, env, 12.0, π / 2, 6.0, 3.0)
    force = rig_force(combined, env, 12.0, π / 2, 6.0, (2, 3.0))
    @test force.power > 0 && force.yaw_moment != 0
    @test all(getfield(force, name) ≈ getfield(sum_force, name)
              for name in fieldnames(RigForce))
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

@testset "a rig ship is sized near the bare ship in calm water" begin
    bare = Ship(ShipDesign(:vlsfo, 140.0), assumptions)
    rotors = Ship(ShipDesign(:vlsfo, 140.0; rotor_area=300.0), assumptions)
    @test rotors.powertrain.installed_power ≈ bare.powertrain.installed_power rtol = 0.02
end

@testset "rotor ships pay for the spin power in the routing lookup" begin
    ship = Ship(ShipDesign(:vlsfo, 140.0; rotor_area=300.0), assumptions)
    table = PerformanceTable(ship, assumptions)
    speed, wind, angle = 5.0, 12.0, π / 2
    power = table.rig_power(speed, wind, angle)
    @test power > 0
    @test lookup(table, speed, wind, angle).fuel_power ≈
          WindShipOpt.fuel_power(table, speed, table.flown_thrust(speed, wind, angle),
              power)
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

@testset "empty boxes take container slots and tare but carry no cargo" begin
    teu = WindShipOpt.CargoUnit(:teu, assumptions)
    loaded = 1 - assumptions[:empty_container_share]
    @test teu.cargo ≈ loaded * assumptions[:cargo_per_teu]
    @test teu.mass - teu.cargo ≈ assumptions[:teu_tare_mass]
end

@testset "a class ship's drive delivers the shaft power of its source engine" begin
    class = ship_classes()["feeder container ship"]
    shaft = 1e3class.power * assumptions[:shaft_efficiency]
    for drive in (:vlsfo, :methanol, :hydrogen)
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

@testset "a hydrogen ship's tank volume and mass follow its largest leg" begin
    class = ship_classes()["feeder container ship"]
    ship = Ship(ShipDesign(:hydrogen, class), assumptions)
    leg = 2e12
    store = WindShipOpt.fuel_store(ship, leg, assumptions)
    fuel = assumptions[:fuel_reserve_factor] * leg / ship.fuel.heating_value
    @test store.volume ≈ fuel / assumptions[:lh2_tank_volumetric_density]
    @test store.mass ≈ fuel / assumptions[:lh2_tank_gravimetric_density] / 1e3
    @test WindShipOpt.fuel_store(ship, 2leg, assumptions).volume ≈ 2store.volume
    hold = ShipCosts(ship, assumptions).hold
    carried = WindShipOpt.cargo_mass(hold, store.mass, store.volume) / hold.unit.cargo
    @test hold.slots - carried ≈ store.volume / hold.unit.volume
    vlsfo = Ship(ShipDesign(:vlsfo, class), assumptions)
    @test WindShipOpt.fuel_store(vlsfo, leg, assumptions).volume == 0
end

"""
    wing_coaster_routing()

Caribbean outbound corridor at scale 8 with the route table and hourly cost of an 85 m
e-methanol coaster with 400 m^2 of wings.
"""
function wing_coaster_routing()
    corridor, _ = route_corridors(:caribbean, north_atlantic_mask(); scale=8)
    ship = Ship(ShipDesign(:methanol, 85.0; wing_area=400.0), assumptions)
    table = RouteTable(PerformanceTable(ship, assumptions))
    return corridor, table,
    first(WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions), assumptions))
end

corridor, table, hourly = wing_coaster_routing()

"""
    trip_with_share(design, name, share, corridors, base=assumptions)

Round trip of `design` in synthetic weather with the input `name` of `base` at `share`.
"""
function trip_with_share(design, name, share, corridors, base=assumptions)
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

@testset "launch cost at the loss goal is mostly crew and turn" begin
    kite = Ship(ShipDesign(:methanol, 140.0; kite_area=800.0), assumptions).rig
    crew_and_turn = (1 + assumptions[:kite_launch_retry_probability]) *
                    assumptions[:kite_cycle_crew_cost] +
                    assumptions[:kite_cycle_course_cost]
    @test crew_and_turn < WindShipOpt.cycle_cost(kite, assumptions) < 1.2crew_and_turn
end

@testset "a rig out of service keeps its cost and saves no fuel while down" begin
    corridors = route_corridors(:caribbean, north_atlantic_mask(); scale=8)
    bare_trip = round_trip(Ship(ShipDesign(:methanol, 85.0), assumptions), corridors...,
        SyntheticWeather(), [24.0 * 31, 24.0 * 200], assumptions)
    for (design, name) in ((ShipDesign(:methanol, 85.0; wing_area=400.0),
            :wing_out_of_service),
        (ShipDesign(:methanol, 85.0; rotor_area=200.0), :rotor_out_of_service),
        (ShipDesign(:methanol, 85.0; kite_area=400.0), :kite_out_of_service))
        low, high, down = [trip_with_share(design, name, share, corridors)
                           for share in (0.1, 0.5, 1.0)]
        @test low.fuel_energy < high.fuel_energy < down.fuel_energy
        @test low.cost_per_tonne_km < high.cost_per_tonne_km < down.cost_per_tonne_km
        @test down.cost_per_tonne_km > bare_trip.cost_per_tonne_km
        @test down.fuel_energy >= 0.999bare_trip.fuel_energy
        @test down.launches == 0
    end
    kite = ShipDesign(:methanol, 85.0; kite_area=400.0)
    @test trip_with_share(kite, :kite_out_of_service, 1.0, corridors).fuel_energy ≈
          bare_trip.fuel_energy rtol = 1e-3
end

@testset "a kite out of service makes and pays launches and forced landings pro rata" begin
    corridors = route_corridors(:caribbean, north_atlantic_mask(); scale=8)
    kite = ShipDesign(:methanol, 85.0; kite_area=400.0)
    hard = with_value(assumptions, :kite_landing_max_wave_height, 0.0)
    cheap = with_value(hard, :kite_forced_landing_loss_probability, 1e-5)
    working = trip_with_share(kite, :kite_out_of_service, 0.0, corridors, cheap)
    half = trip_with_share(kite, :kite_out_of_service, 0.5, corridors, cheap)
    @test working.forced_landings > 0
    @test half.forced_landings ≈ working.forced_landings / 2
    @test half.launches ≈ working.launches / 2
    dearer = with_value(hard, :kite_forced_landing_loss_probability, 2e-5)
    @test trip_with_share(kite, :kite_out_of_service, 0.5, corridors,
        dearer).cost_per_tonne_km >
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
    kite = Ship(ShipDesign(:methanol, 85.0; kite_area=400.0), assumptions)
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
    corridors = route_corridors(:caribbean, north_atlantic_mask(); scale=8)
    design = ShipDesign(:methanol, 85.0; rotor_area=200.0)
    cargo(share, reserve) = trip_with_share(design, :rotor_out_of_service, share, corridors,
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

@testset "bounded route equals the unpruned dynamic programme" begin
    weather, departure = SyntheticWeather(), 24.0 * 31
    workspace = WindShipOpt.RouteWorkspace(size(corridor.lat, 2), 400,
        size(corridor.lat, 1))
    for coastal_penalty in (0.0, 1.0)
        leg = route(corridor, table, weather, departure; time_cost=hourly, coastal_penalty)
        full = WindShipOpt.route_pass(workspace, corridor, table, weather, departure,
            corridor.water; time_cost=hourly, time_step=3.0, first_stage=1,
            first_lateral=centre_index(corridor), first_aloft=false, coastal_penalty)
        @test leg.objective == full.objective
        @test leg.path == full.path
    end
end

@testset "search band holds the coarse path and rivals pass it on the asked side" begin
    leg = route(corridor, table, SyntheticWeather(), 24.0 * 31; time_cost=hourly)
    band = WindShipOpt.band_nodes(corridor, leg, 1)
    rows = [WindShipOpt.nearest_lateral(corridor, stage, point[1], point[2])
            for (stage, point) in enumerate(leg.path)]
    @test all(band[stage, rows[stage]] for stage in eachindex(rows))
    @test !any(band .& .!corridor.water)
    for side in (-1, 1)
        rival = WindShipOpt.rival_nodes(corridor, leg, 1, side)
        @test !any(rival .& .!corridor.water)
        blocked = [stage for stage in eachindex(rows)
                   if rival[stage, :] != corridor.water[stage, :]]
        @test length(blocked) == 1
        stage = only(blocked)
        @test all(side * (lateral - rows[stage]) > WindShipOpt.BAND_ROWS
                  for lateral in axes(rival, 2) if rival[stage, lateral])
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
    first = WindShipOpt.first_point(table, start, corridor, stage, centre, step, commanded)
    points = WindShipOpt.SailedPoint[]
    hours = WindShipOpt.sail_edge!(points, first, table, seas, corridor, stage, centre,
        step, 0.0, commanded)
    @test 0 < last(points).speed_index < commanded
    @test hours > corridor.edge_length[stage, centre, step] / table.speeds[commanded] / 3600
    storm = HeadSeas(destination, 60NAUTICAL_MILE, wave_from, 8.0, 9.0)
    @test isnothing(route(corridor, table, storm, 0.0; time_cost=hourly))
end

@testset "a round trip at a held speed takes that speed's time and is costed as usual" begin
    corridors = route_corridors(:caribbean, north_atlantic_mask(); scale=8)
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

@testset "a round trip at a held speed is stored apart from one that chooses its speed" begin
    @eval PaperRuns weather_name = "synthetic"
    PaperRuns.paper_run = PaperRuns.open_run(:draft, [:speed_size], false)
    case_at(held_knots) = (; design=ShipDesign(:vlsfo, 100.0), assumptions, route=:caribbean,
        scale=8.0, horizon=Inf, held_knots)
    @test allunique(PaperRuns.case_path(case_at(held_knots), [24.0])
                    for held_knots in (nothing, 8.0, 9.0))
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

@testset "each rig is measured against its neighbours in cost, the ends against none" begin
    costs = Dict("kite" => 2.0, "wings" => 1.0, "rotors" => 3.0)
    ranked = WindShipOpt.ranked_neighbours(costs)
    @test getfield.(ranked, :rig) == ["wings", "kite", "rotors"]
    @test getfield.(ranked, :next)[1:2] == [2.0, 3.0]
    @test isnan(ranked[3].next)
    @test isnan(ranked[1].ahead)
    @test getfield.(ranked, :ahead)[2:3] == [1.0, 2.0]
end

@testset "the crashes a year at break-even use up the cost gap exactly" begin
    cost, target, work, crash = 0.012, 0.015, 2e9, 4e5
    crashes = WindShipOpt.events_to_cost(cost, target, work, crash)
    @test cost + crashes * crash / work ≈ target
    @test WindShipOpt.events_to_cost(target, cost, work, crash) == 0
end
