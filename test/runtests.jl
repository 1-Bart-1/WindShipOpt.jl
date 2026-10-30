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

# Mittendorf et al. (2022), Fig. 3: C_AW of C_B ≥ 0.70 hulls peaks at ~5-10 in head waves
# near λ/L = 1-1.3 and stays within about ±2 in following waves.
@testset "SNNM added resistance has the measured head and following wave magnitudes" begin
    assumptions = Assumptions()
    env = Environment(assumptions)
    seakeeping = SeakeepingHull(Hull(85.0, assumptions), assumptions)
    coefficient(ratio, heading) = added_resistance_coefficient(seakeeping, env, 10KNOT,
        sqrt(2π * env.gravity / (ratio * 85.0)), heading)
    head_peak = maximum(coefficient(ratio, π) for ratio in 0.8:0.05:1.5)
    @test 5 < head_peak < 10
    @test all(abs(coefficient(ratio, 0.0)) < 2 for ratio in 0.3:0.1:3.0)
end
