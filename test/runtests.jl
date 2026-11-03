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

Whether the best pattern of the kite `model` in a 12 m/s apparent wind on `course` [rad]
is steered rather than parked, and the positions of its steered cycle.
"""
function best_pattern_path(model, max_force, assumptions, course)
    problem = WindShipOpt.PatternProblem(model, max_force,
        deg2rad(assumptions[:kite_min_elevation]), 12.0, course, 0.0)
    force, parameters = WindShipOpt.optimal_pattern(problem,
        WindShipOpt.pattern_starts(course))
    path = WindShipOpt.PatternStep[]
    steered = WindShipOpt.PatternForce(model, WindShipOpt.pattern_of(parameters), 12.0,
        max_force; path)
    return WindShipOpt.objective(problem, steered) ≈
           WindShipOpt.objective(problem, force), path
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
@testset "upwind the kite sweeps along the window edge rather than parking" begin
    model, max_force, _ = WindShipOpt.kite_model(800.0, 3.0, assumptions)
    upwind_steered, upwind = best_pattern_path(model, max_force, assumptions, deg2rad(120))
    @test upwind_steered
    @test least_off_wind(upwind) > π / 4
    downwind_steered, downwind = best_pattern_path(model, max_force, assumptions, 0.0)
    @test downwind_steered && least_off_wind(downwind) < π / 4
end

@testset "heavier canopy cloth raises the minimum flight wind and the canopy life" begin
    light, heavy = (with_value(assumptions, :canopy_cloth_weight, weight)
                    for weight in (40.0, 160.0))
    light_wind, heavy_wind = (
        WindShipOpt.min_flight_wind(first(WindShipOpt.kite_model(800.0, 3.0, cloth)), cloth)
        for cloth in (light, heavy))
    @test heavy_wind > light_wind
    @test WindShipOpt.Canopy(heavy).lifetime > WindShipOpt.Canopy(light).lifetime
end

@testset "canopy life follows the wear law and its sensitivities" begin
    canopy(changes...) = WindShipOpt.Canopy(foldl((values, change) -> with_value(values,
            change...), changes; init=with_value(assumptions, :canopy_cloth_weight, 100.0)))
    uv_rate = assumptions[:canopy_uv_dose_rate] / assumptions[:cloth_uv_dose_per_weight]
    wear_rate = assumptions[:canopy_wear_rate]
    tension = 1e3assumptions[:kite_max_force_per_area] * assumptions[:canopy_panel_radius]
    margin(weight) = assumptions[:cloth_specific_strength] * weight /
                     (assumptions[:canopy_strength_factor] * tension)
    # the lives the paper's derivation quotes at its base inputs
    @test canopy(:canopy_cloth_weight => 200.0).lifetime ≈ 3812 atol = 1
    @test canopy().lifetime ≈ 1646 atol = 1
    # at the normalising weight the exponents do not matter
    @test canopy().lifetime ≈ 100log(margin(100)) / (uv_rate + wear_rate)
    @test canopy(:canopy_uv_weight_exponent => 1.0).lifetime ≈ canopy().lifetime
    # UV life grows with weight^0.4, mechanical life with weight^1
    heavy = canopy(:canopy_cloth_weight => 200.0)
    @test heavy.uv_lifetime ≈ 100 * 2^0.4 * log(margin(200)) / uv_rate
    @test heavy.wear_lifetime ≈ 200log(margin(200)) / wear_rate
    @test 1 / heavy.lifetime ≈ 1 / heavy.uv_lifetime + 1 / heavy.wear_lifetime
    steep = canopy(:canopy_cloth_weight => 200.0, :canopy_wear_weight_exponent => 1.5)
    @test steep.wear_lifetime ≈ 100 * 2^1.5 * log(margin(200)) / wear_rate
    # a fixed mechanical life replaces the wear law and leaves the UV life alone
    fixed = canopy(:canopy_wear_lifetime => 2000.0)
    @test fixed.wear_lifetime == 2000
    @test fixed.uv_lifetime ≈ canopy().uv_lifetime
    # retirement shortens the UV clock and keeps the observed wear life at 100 g/m^2
    retired = canopy(:canopy_retirement_strength => 0.5)
    @test retired.uv_lifetime ≈ canopy().uv_lifetime * log(2) / log(margin(100))
    @test retired.wear_lifetime ≈ canopy().wear_lifetime
    for (share, life) in ((0.7, 770), (0.46, 1155), (0.27, 1396))
        @test canopy(:canopy_retirement_strength => share).lifetime ≈ life atol = 1
    end
    # cloth whose force limit comes before the retirement share flies to the force limit
    light, light_retired = (canopy(:canopy_cloth_weight => 20.0,
            :canopy_retirement_strength => share) for share in (0.0, 0.27))
    @test light_retired.uv_lifetime ≈ light.uv_lifetime
    # the life factor scales the whole life, a fixed wear life included
    @test canopy(:canopy_life_factor => 2.0).lifetime ≈ 2canopy().lifetime
    @test canopy(:canopy_wear_lifetime => 2000.0,
        :canopy_life_factor => 2.0).wear_lifetime == 4000
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
        reference_height=120.0, max_wind=30.0, min_flight_wind=4.0, max_force=1e6,
        attach_height=10.0,
        attach_position=WindShipOpt.launch_mast_position(hull, assumptions),
        wind_speeds=collect(3.0:3.0:30.0), courses=deg2rad.(0.0:15.0:180.0),
        side_weights=[0.0, 1.0], forces=fill(pattern, 10, 13, 2))
end

@testset "a parked kite ages in the sun at the full rate and wears less" begin
    rig = uniform_kite(Hull(140.0, assumptions), assumptions)
    canopy, tether = WindShipOpt.consumable_costs(rig, assumptions)
    life = WindShipOpt.Canopy(assumptions)
    fraction = assumptions[:kite_parked_wear_fraction]
    @test WindShipOpt.parked_wear_cost(rig, assumptions) ≈
          canopy * (1 / life.uv_lifetime + fraction / life.wear_lifetime) +
          fraction * tether / assumptions[:tether_lifetime]
    @test WindShipOpt.wear_cost(rig, assumptions) ≈
          canopy / life.lifetime + tether / assumptions[:tether_lifetime]
    still = with_value(assumptions, :kite_parked_wear_fraction, 0.0)
    @test WindShipOpt.parked_wear_cost(rig, still) ≈ canopy / life.uv_lifetime
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
