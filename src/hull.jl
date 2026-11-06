"""
    Environment

Fluid properties shared by all force models.
"""
Base.@kwdef struct Environment
    "sea water density [kg/m^3]"
    water_density::Float64 = 1025.0
    "sea water kinematic viscosity [m^2/s]"
    water_viscosity::Float64 = 1.19e-6
    "air density [kg/m^3]"
    air_density::Float64 = 1.225
    "exponent of the power-law wind profile over the sea [-]"
    shear_exponent::Float64 = 0.05
    "gravitational acceleration [m/s^2]"
    gravity::Float64 = 9.81
end

function Environment(assumptions::Assumptions)
    return Environment(; water_density=assumptions[:water_density],
        water_viscosity=assumptions[:water_viscosity],
        air_density=assumptions[:air_density],
        shear_exponent=assumptions[:wind_shear_exponent])
end

"""
    Hull

Main dimensions and form coefficients of a single-screw hull, as used by Holtrop–Mennen.
"""
Base.@kwdef struct Hull
    "waterline length [m]"
    length::Float64
    "moulded breadth [m]"
    beam::Float64
    "moulded draft, even keel [m]"
    draft::Float64
    "displacement volume [m^3]"
    displacement_volume::Float64
    "midship section coefficient [-]"
    midship_coefficient::Float64
    "waterplane area coefficient, estimated at the capped prismatic coefficient [-]"
    waterplane_coefficient::Float64
    "longitudinal centre of buoyancy forward of midships [% of length]"
    centre_of_buoyancy::Float64
    "transverse bulb area [m^2]"
    bulb_area::Float64
    "height of the bulb area centre above the keel [m]"
    bulb_height::Float64
    "immersed transom area [m^2]"
    transom_area::Float64 = 0.0
    "Holtrop stern shape parameter, 0 for normal sections [-]"
    stern_shape::Float64 = 0.0
    "wetted appendage area [m^2]"
    appendage_area::Float64
    "appendage form factor 1+k2 [-]"
    appendage_form_factor::Float64
    "factor on the Holtrop calm-water resistance calibrating it to a source design [-]"
    resistance_factor::Float64 = 1.0
    "largest prismatic coefficient the Holtrop formulas are evaluated at [-]"
    max_prismatic::Float64 = 1.0
end

"""
    Hull(length, assumptions)

Reference coaster of `assumptions`, scaled geometrically to waterline `length` [m].
"""
function Hull(length::Real, assumptions::Assumptions)
    scale = length / assumptions[:reference_length]
    return Hull(length, assumptions[:reference_beam] * scale,
        assumptions[:reference_draft] * scale, assumptions[:block_coefficient], assumptions)
end

"""
    Hull(length, beam, draft, block, assumptions; centre_of_buoyancy, resistance_factor=1)

Hull of the given main dimensions [m] and block coefficient, with the form ratios of the
reference coaster, its centre of buoyancy [% of length] unless given, and the factor on
its calm-water resistance. Its form terms stop at the prismatic coefficient
`holtrop_max_prismatic`, while its displacement stays that of `block`.
"""
function Hull(length, beam, draft, block, assumptions::Assumptions;
        centre_of_buoyancy=assumptions[:centre_of_buoyancy], resistance_factor=1.0)
    midship = assumptions[:midship_coefficient]
    max_prismatic = assumptions[:holtrop_max_prismatic]
    prismatic = prismatic_coefficient(block, midship, max_prismatic)
    return Hull(; length, beam, draft,
        displacement_volume=length * beam * draft * block,
        midship_coefficient=midship,
        waterplane_coefficient=0.763 * (prismatic + 0.34),
        centre_of_buoyancy, resistance_factor, max_prismatic,
        bulb_area=assumptions[:bulb_area_ratio] * beam * draft * midship,
        bulb_height=assumptions[:bulb_height_ratio] * draft,
        appendage_area=assumptions[:appendage_area_ratio] * length * draft,
        appendage_form_factor=assumptions[:appendage_form_factor])
end

block_coefficient(hull::Hull) =
    hull.displacement_volume / (hull.length * hull.beam * hull.draft)
prismatic_coefficient(block, midship, max_prismatic) = min(block / midship, max_prismatic)
prismatic_coefficient(hull::Hull) = prismatic_coefficient(block_coefficient(hull),
    hull.midship_coefficient, hull.max_prismatic)
displacement_mass(hull::Hull, env::Environment) =
    env.water_density * hull.displacement_volume

"""
    wetted_surface(hull)

Holtrop's estimate of the wetted hull surface [m^2].
"""
function wetted_surface(hull::Hull)
    (; length, beam, draft, midship_coefficient, waterplane_coefficient, bulb_area) = hull
    block = block_coefficient(hull)
    return length * (2draft + beam) * sqrt(midship_coefficient) *
           (0.453 + 0.4425block - 0.2862midship_coefficient - 0.003467beam / draft +
            0.3696waterplane_coefficient) + 2.38bulb_area / block
end

function run_length(hull::Hull)
    prismatic = prismatic_coefficient(hull)
    return hull.length * (1 - prismatic +
                          0.06prismatic * hull.centre_of_buoyancy / (4prismatic - 1))
end

"""
    form_factor(hull)

Viscous form factor 1+k1 of Holtrop (1984).
"""
function form_factor(hull::Hull)
    (; length, beam, draft, displacement_volume) = hull
    prismatic = prismatic_coefficient(hull)
    stern = 1 + 0.011hull.stern_shape
    return 0.93 + 0.487118stern * (beam / length)^1.06806 * (draft / length)^0.46106 *
                  (length / run_length(hull))^0.121563 *
                  (length^3 / displacement_volume)^0.36486 * (1 - prismatic)^-0.604247
end

friction_coefficient(reynolds) = 0.075 / (log10(reynolds) - 2)^2

"""
    WaveCoefficients

Speed-independent coefficients of the Holtrop wave resistance formula for Fn ≤ 0.4.
"""
struct WaveCoefficients
    c1::Float64
    c2::Float64
    c5::Float64
    m1::Float64
    c15::Float64
    lambda::Float64
end

function WaveCoefficients(hull::Hull)
    (; length, beam, draft, displacement_volume, bulb_area, bulb_height) = hull
    prismatic = prismatic_coefficient(hull)
    lcb = hull.centre_of_buoyancy
    slenderness = beam / length
    c7 = slenderness < 0.11 ? 0.229577slenderness^(1 / 3) :
         slenderness < 0.25 ? slenderness : 0.5 - 0.0625length / beam
    entrance_angle = 1 + 89exp(-(length / beam)^0.80856 *
                               (1 - hull.waterplane_coefficient)^0.30484 *
                               (1 - prismatic - 0.0225lcb)^0.6367 *
                               (run_length(hull) / beam)^0.34574 *
                               (100displacement_volume / length^3)^0.16302)
    c1 = 2223105c7^3.78613 * (draft / beam)^1.07961 * (90 - entrance_angle)^-1.37565
    c3 = 0.56bulb_area^1.5 /
         (beam * draft * (0.31sqrt(bulb_area) + draft - bulb_height))
    c2 = exp(-1.89sqrt(c3))
    c5 = 1 - 0.8hull.transom_area / (beam * draft * hull.midship_coefficient)
    c16 = prismatic < 0.8 ? 8.07981prismatic - 13.8673prismatic^2 + 6.984388prismatic^3 :
          1.73014 - 0.7067prismatic
    m1 = 0.0140407length / draft - 1.75254displacement_volume^(1 / 3) / length -
         4.79323slenderness - c16
    fullness = length^3 / displacement_volume
    c15 = fullness < 512 ? -1.69385 :
          fullness > 1726.91 ? 0.0 :
          -1.69385 + (length / displacement_volume^(1 / 3) - 8) / 2.36
    lambda = length / beam < 12 ? 1.446prismatic - 0.03length / beam :
             1.446prismatic - 0.36
    return WaveCoefficients(c1, c2, c5, m1, c15, lambda)
end

function wave_resistance(hull::Hull, env::Environment, coefficients::WaveCoefficients,
        froude)
    froude > 0 || return 0.0
    (; c1, c2, c5, m1, c15, lambda) = coefficients
    m4 = 0.4c15 * exp(-0.034froude^-3.29)
    return c1 * c2 * c5 * hull.displacement_volume * env.water_density * env.gravity *
           exp(m1 * froude^-0.9 + m4 * cos(lambda * froude^-2))
end

function bulb_resistance(hull::Hull, env::Environment, speed)
    (; bulb_area, bulb_height, draft) = hull
    bulb_area > 0 || return 0.0
    g = env.gravity
    emergence = 0.56sqrt(bulb_area) / (draft - 1.5bulb_height)
    immersion_froude = speed /
                       sqrt(g * (draft - bulb_height - 0.25sqrt(bulb_area)) + 0.15speed^2)
    return 0.11exp(-3emergence^-2) * immersion_froude^3 * bulb_area^1.5 *
           env.water_density * g / (1 + immersion_froude^2)
end

function transom_resistance(hull::Hull, env::Environment, speed)
    (; transom_area, beam) = hull
    transom_area > 0 || return 0.0
    transom_froude = speed / sqrt(2env.gravity * transom_area /
                                  (beam + beam * hull.waterplane_coefficient))
    c6 = transom_froude < 5 ? 0.2(1 - 0.2transom_froude) : 0.0
    return 0.5env.water_density * speed^2 * transom_area * c6
end

"""
    correlation_allowance(hull, coefficients)

Holtrop's model-ship correlation coefficient C_A [-].
"""
function correlation_allowance(hull::Hull, coefficients::WaveCoefficients)
    (; length, draft) = hull
    c4 = min(draft / length, 0.04)
    return 0.006(length + 100)^-0.16 - 0.00205 +
           0.003sqrt(length / 7.5) * block_coefficient(hull)^4 * coefficients.c2 *
           (0.04 - c4)
end

"""
    resistance(hull, env, speed)

Calm-water resistance [N] at `speed` [m/s] by Holtrop–Mennen (1984), valid up to Fn 0.4,
times the hull's `resistance_factor`.
"""
function resistance(hull::Hull, env::Environment, speed;
        coefficients=WaveCoefficients(hull))
    speed > 0 || return 0.0
    froude = speed / sqrt(env.gravity * hull.length)
    froude <= 0.4 || error("Holtrop low-speed formula is invalid at Fn = $froude")
    dynamic_pressure = 0.5env.water_density * speed^2
    cf = friction_coefficient(speed * hull.length / env.water_viscosity)
    surface = wetted_surface(hull)
    friction = dynamic_pressure * surface * cf
    appendages = dynamic_pressure * hull.appendage_area * hull.appendage_form_factor * cf
    correlation = dynamic_pressure * surface * correlation_allowance(hull, coefficients)
    return hull.resistance_factor * (form_factor(hull) * friction + appendages +
            wave_resistance(hull, env, coefficients, froude) +
            bulb_resistance(hull, env, speed) + transom_resistance(hull, env, speed) +
            correlation)
end

"""
    side_force_slope(hull)

Linear hull side-force derivative Y'_β = πT/L + 1.4 C_B B/L over leeway, made
non-dimensional with ½ρV²LT (Kijima et al. 1990).
"""
side_force_slope(hull::Hull) =
    π * hull.draft / hull.length + 1.4block_coefficient(hull) * hull.beam / hull.length

"""
    lateral_centre(hull)

Distance [m] forward of midship at which the hull side force under leeway acts: the
yaw-moment derivative N'_β = 2T/L of Kijima et al. (1990) over [`side_force_slope`](@ref).
"""
lateral_centre(hull::Hull) = 2hull.draft / side_force_slope(hull)

"""
    rudder_area(hull)

Rudder area [m^2]: the minimum the DNV guidance of January 2000 recommends directly behind
a propeller, A = T L / 100 (1 + 50 C_B^2 (B/L)^2).
"""
rudder_area(hull::Hull) =
    hull.draft * hull.length / 100 *
    (1 + 50block_coefficient(hull)^2 * (hull.beam / hull.length)^2)

"""
    leeway_drag(hull, env, speed, side_force)

Leeway angle [rad] and induced drag [N] needed for the hull to carry a side force [N],
from the linear side-force slope: the potential-flow share of the side force costs half
of side force times leeway, as for a slender wing, and the cross-flow share all of it.
"""
function leeway_drag(hull::Hull, env::Environment, speed, side_force)
    reference_force = 0.5env.water_density * speed^2 * hull.length * hull.draft *
                      side_force_slope(hull)
    leeway = side_force / reference_force
    potential = π * hull.draft / hull.length
    induced = (0.5potential + (side_force_slope(hull) - potential)) / side_force_slope(hull)
    return leeway, induced * side_force * leeway
end
