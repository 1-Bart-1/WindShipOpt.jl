# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"SNNM parameters x1…x29 for hulls with C_B ≥ 0.70 (Mittendorf et al. 2022, Table 2)"
const SNNM_FULL = (6.99, 0.425, 70.92, 2.0, 3.013, 0.9, 3.726, 0.281, 1.388, 3.869, 17.963,
    11.5, 5.589, 473.743, 2.214, 153.646, 2.433, 0.0557, 2.410, 0.813, 0.3, 1.008, 1.076,
    0.778, 19.241, 3.029, 3.845, 3.123, 4.527)

"SNNM parameters x1…x29 for hulls with C_B < 0.70 (Mittendorf et al. 2022, Table 2)"
const SNNM_FINE = (4.06, 0.705, 56.23, 1.185, 4.057, 0.65, 2.25, 0.134, 1.626, 3.585,
    29.107, 10.868, 9.878, 480.961, 2.62, 123.163, 1.745, 0.107, 3.5, 0.825, 0.125, 1.03,
    1.201, 0.723, 13.630, 5.0, 3.15, 2.897, 5.552)

"""
    SeakeepingHull

Hull properties the added-resistance formula needs beyond the calm-water ones.
"""
struct SeakeepingHull
    hull::Hull
    "length of entrance and of run [m]"
    entrance_length::Float64
    run_length::Float64
    "pitch radius of gyration over length [-]"
    pitch_gyration::Float64
    "SNNM parameter set for the block coefficient"
    x::NTuple{29, Float64}
    "JONSWAP peak enhancement factor of the sea it meets [-]"
    peakedness::Float64
end

function SeakeepingHull(hull::Hull, assumptions::Assumptions)
    return SeakeepingHull(hull, assumptions[:entrance_length_ratio] * hull.length,
        run_length(hull), assumptions[:pitch_gyration_ratio],
        block_coefficient(hull) >= 0.70 ? SNNM_FULL : SNNM_FINE,
        assumptions[:wave_peakedness])
end

"""
    added_resistance_coefficient(seakeeping, env, speed, frequency, heading)

Non-dimensional added resistance C_AW = R_AW L / (ρ g ζ² B²) in regular deep-water waves
of `frequency` [rad/s] by the SNNM method (Liu & Papanikolaou 2020, recalibrated by
Mittendorf et al. 2022); `heading` [rad] is π in head and 0 in following waves.
"""
function added_resistance_coefficient(seakeeping::SeakeepingHull, env::Environment, speed,
        frequency, heading)
    g = env.gravity
    froude = speed / sqrt(g * seakeeping.hull.length)
    wavelength = 2π * g / frequency^2
    reflection = reflection_coefficient(seakeeping, froude, speed, frequency, wavelength,
        heading, g)
    motion = heading >= π / 2 ?
             motion_coefficient(seakeeping, froude, wavelength, heading) :
             following_motion(seakeeping, froude, speed, frequency, wavelength, heading, g)
    return motion + reflection
end

"""
    motion_coefficient(seakeeping, froude, wavelength, heading)

SNNM motion part of C_AW for waves from beam to head (Mittendorf et al. 2022, Eq. 11-17).
"""
function motion_coefficient(seakeeping::SeakeepingHull, froude, wavelength, heading)
    (; hull, x) = seakeeping
    length, beam, draft = hull.length, hull.beam, hull.draft
    block = block_coefficient(hull)
    frequency_factor = x[17] * cbrt(seakeeping.pitch_gyration) *
                       sqrt(length / wavelength) *
                       (1 - x[18] / block * (log(beam / draft) - log(x[19]))) *
                       (block / x[20])^x[21] *
                       ((-x[22] * froude^2 + x[23] * froude) * abs(cos(heading)) +
                        x[24] * (13 + cos(2heading)) / x[25])
    below = frequency_factor < 1
    b1 = below ? x[12] : -x[13]
    d1 = (below ? 1.0 : -4.0) * x[14] * (length * block / beam)^-x[15]
    a2 = froude < 0.12 ? 0.0072 + x[8] * froude : froude^x[9] * exp(-x[10] * froude)
    a1 = x[3] * block^x[4] * (x[5] * seakeeping.pitch_gyration)^2 *
         (x[6] / block)^(-(1 + froude) * cos(heading)) / log(beam / draft) *
         (1 - 2cos(heading)) / x[7]
    return x[1] * a1 * a2 * frequency_factor^b1 * exp(b1 / d1 * (1 - frequency_factor^d1))
end

"""
    following_motion(seakeeping, froude, speed, frequency, wavelength, heading, g)

Motion part of C_AW from beam to following waves. In following waves it follows the
energy-exchange rule of Liu & Papanikolaou (2020) as summarised by Mittendorf et al.
(2022), applied to the whole motion term: minus the zero-speed head-wave value at rest,
zero at a quarter of the wave phase speed, the zero-speed head-wave value at half of it,
and beyond that the head-wave value at the relative Froude number. Between beam and
following waves the whole motion term is interpolated linearly in heading, a
simplification of Mittendorf et al. (2022), who interpolate only a1.
"""
function following_motion(seakeeping::SeakeepingHull, froude, speed, frequency, wavelength,
        heading, g)
    phase_speed = g / frequency
    ratio = speed / phase_speed
    following = ratio <= 0.5 ?
                (4ratio - 1) * motion_coefficient(seakeeping, 0.0, wavelength, π) :
                motion_coefficient(seakeeping,
        (speed - phase_speed / 2) / sqrt(g * seakeeping.hull.length), wavelength, π)
    beam = motion_coefficient(seakeeping, froude, wavelength, π / 2)
    return following + (beam - following) * heading / (π / 2)
end

"""
    draft_coefficient(x, effective_draft, wavelength, length)

SNNM draft coefficient α_T* for the share of the wave reflected by a hull of this draft.
"""
draft_coefficient(x, effective_draft, wavelength, length) =
    1 - exp(-x[26] * π *
            (effective_draft / wavelength - effective_draft / (x[27] * length)))

"""
    segment_reflection(entrance_angle, shifted_angle, speed_term, heading)

Faltinsen-type reflection of one bow or stern segment, before scaling.
"""
segment_reflection(entrance_angle, shifted_angle, speed_term, heading) =
    sin(shifted_angle)^2 +
    speed_term * (cos(entrance_angle) * cos(shifted_angle) - cos(heading))

"""
    reflection_coefficient(seakeeping, froude, speed, frequency, wavelength, heading, g)

SNNM reflection part of C_AW from the four bow and stern segments (Mittendorf et al.
2022, Eq. 4-10, 18-20).
"""
function reflection_coefficient(seakeeping::SeakeepingHull, froude, speed, frequency,
        wavelength, heading, g)
    (; hull, x) = seakeeping
    length, beam, draft = hull.length, hull.beam, hull.draft
    bow_angle = atan(0.99beam / 2 / seakeeping.entrance_length)
    stern_angle = atan(0.99beam / 2 / seakeeping.run_length)
    shoulder = heading >= π - bow_angle ? -cos(heading) : 0.0
    form = (0.87 / block_coefficient(hull))^((1 + 4sqrt(froude)) * shoulder)
    speed_term = 2frequency * speed / g
    scale = x[2] * length / beam
    bow = scale * draft_coefficient(x, draft, wavelength, length) * form
    stern_draft = draft * (x[28] + sqrt(abs(cos(heading)))) / x[29]
    stern = -scale * draft_coefficient(x, stern_draft, wavelength, length)
    total = 0.0
    if bow_angle <= heading <= π
        total += bow *
                 segment_reflection(bow_angle, bow_angle - heading, speed_term, heading)
    end
    if π - bow_angle <= heading <= π
        total += bow *
                 segment_reflection(bow_angle, bow_angle + heading, speed_term, heading)
    end
    if 0 <= heading <= π - stern_angle
        total += stern *
                 segment_reflection(stern_angle, stern_angle + heading, speed_term, heading)
    end
    if 0 <= heading <= stern_angle
        total += stern *
                 segment_reflection(stern_angle, stern_angle - heading, speed_term, heading)
    end
    return total
end

"""
    jonswap(frequency, significant_height, peak_period; peakedness)

JONSWAP wave spectrum density [m^2 s/rad] at `frequency` [rad/s].
"""
function jonswap(frequency, significant_height, peak_period; peakedness)
    peak = 2π / peak_period
    width = frequency <= peak ? 0.07 : 0.09
    shape = exp(-(frequency - peak)^2 / (2width^2 * peak^2))
    return 5 / 16 * significant_height^2 * peak^4 * frequency^-5 *
           exp(-1.25(peak / frequency)^4) * (1 - 0.287log(peakedness)) * peakedness^shape
end

"""
    added_resistance(seakeeping, env, speed, significant_height, peak_period, heading)

Mean added resistance [N] in long-crested irregular waves with a JONSWAP spectrum.
"""
function added_resistance(seakeeping::SeakeepingHull, env::Environment, speed,
        significant_height, peak_period, heading)
    significant_height > 0 && peak_period > 0 || return 0.0
    (; hull) = seakeeping
    scale = env.water_density * env.gravity * hull.beam^2 / hull.length
    frequencies = range(0.1, 6.0; length=240)
    step = frequencies[2] - frequencies[1]
    total = sum(frequencies) do frequency
        coefficient = added_resistance_coefficient(seakeeping, env, speed, frequency,
            heading)
        return coefficient * jonswap(frequency, significant_height, peak_period;
            peakedness=seakeeping.peakedness)
    end
    return 2scale * total * step
end

"""
    heave_pitch_response(hull, gravity, speed, frequency, heading)

Heave [m/m] and pitch [rad/m] per unit wave amplitude and the encounter frequency [rad/s]
of the box-shaped hull closed-form expressions of Jensen et al. (2004), in regular waves of
`frequency` [rad/s]; `heading` [rad] is π in head and 0 in following waves.
"""
function heave_pitch_response(hull::Hull, gravity, speed, frequency, heading)
    (; length, draft) = hull
    beam = hull.beam * block_coefficient(hull)
    wavenumber = frequency^2 / gravity
    froude = speed / sqrt(gravity * length)
    slowdown = 1 - froude * sqrt(wavenumber * length) * cos(heading)
    encounter = frequency - wavenumber * speed * cos(heading)
    amplitude = 2sin(encounter^2 * beam / 2gravity) * exp(-encounter^2 * draft / gravity)
    forcing = sqrt((1 - wavenumber * draft)^2 +
                   (iszero(slowdown) ? 0.0 :
                    amplitude^2 / (wavenumber * beam * slowdown^3))^2)
    resonance = 1 / sqrt((1 - 2wavenumber * draft * slowdown^2)^2 +
                    (amplitude^2 / (wavenumber * beam * slowdown^2))^2)
    effective_wavenumber = abs(wavenumber * cos(heading))
    half = effective_wavenumber * length / 2
    pressure = exp(-effective_wavenumber * draft) * forcing * resonance
    heave = pressure * abs(sinc(half / π))
    pitch = pressure * abs(half < 1e-4 ? 2half / length :
                           6 * (sin(half) - half * cos(half)) / (half^2 * length))
    return heave, pitch, encounter
end

"""
    mast_speed(seakeeping, env, speed, significant_height, peak_period, heading, position)

Significant vertical speed [m/s], twice the root-mean-square, of a point `position` [m]
forward of midship in long-crested waves with a JONSWAP spectrum, heave and pitch taken
as out of phase.
"""
function mast_speed(seakeeping::SeakeepingHull, env::Environment, speed, significant_height,
        peak_period, heading, position)
    significant_height > 0 && peak_period > 0 || return 0.0
    frequencies = range(0.1, 6.0; length=240)
    step = frequencies[2] - frequencies[1]
    variance = sum(frequencies) do frequency
        heave, pitch, encounter = heave_pitch_response(seakeeping.hull, env.gravity, speed,
            frequency, heading)
        return jonswap(frequency, significant_height, peak_period;
            peakedness=seakeeping.peakedness) * encounter^2 *
               (heave^2 + (pitch * position)^2)
    end
    return 2sqrt(variance * step)
end
