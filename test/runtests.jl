using Test
using WindShipOpt
using WindShipOpt: correlation_allowance, bulb_resistance, friction_coefficient

# Numerical example of Holtrop & Mennen (1982), components unchanged in Holtrop (1984).
const PAPER_ENV = Environment(; water_density=1025.0, water_viscosity=1.1883e-6)
const PAPER_HULL = Hull(; length=205.0, beam=32.0, draft=10.0, displacement_volume=37500.0,
    midship_coefficient=0.98, waterplane_coefficient=0.75, centre_of_buoyancy=-0.75,
    bulb_area=20.0, bulb_height=4.0, transom_area=16.0, stern_shape=10.0,
    appendage_area=50.0, appendage_form_factor=1.5)

@testset "Holtrop components match the published example at 25 kn" begin
    speed = 25KNOT
    coefficients = WaveCoefficients(PAPER_HULL)
    @test wetted_surface(PAPER_HULL) ≈ 7381.45 rtol = 1e-3
    @test friction_coefficient(speed * 205 / PAPER_ENV.water_viscosity) ≈ 0.001390 rtol = 2e-3
    @test coefficients.c2 ≈ 0.7595 rtol = 1e-3
    @test coefficients.c5 ≈ 0.9592 rtol = 1e-3
    @test coefficients.m1 ≈ -2.1274 rtol = 1e-3
    @test coefficients.lambda ≈ 0.6513 rtol = 1e-3
    @test bulb_resistance(PAPER_HULL, PAPER_ENV, speed) ≈ 49.0 rtol = 0.05
    @test correlation_allowance(PAPER_HULL, coefficients) ≈ 0.000352 rtol = 5e-3
end

# ~3500 dwt coasters install ~1.5 MW for 12.5 kn, about 1 MW at 11 kn by the cube law.
@testset "coaster resistance and power are in the range of real coasters" begin
    assumptions = Assumptions()
    ship = Ship(ShipDesign(:vlsfo, 85.0), assumptions)
    effective_power = resistance(ship.hull, ship.env, 11KNOT) * 11KNOT
    @test 350e3 < effective_power < 800e3
    @test 700 < ship.powertrain.installed_power / 1e3 < 1500
end
