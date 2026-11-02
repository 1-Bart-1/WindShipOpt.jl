# Rigid-shape polars of paraglider-like towing kites over projected aspect ratio, from the
# Vortex Step Method: a circular arc, a rounded planform and one cambered airfoil whose 2D
# polar comes from NeuralFoil with transition tripped near the leading edge, plus a
# section drag increment for the cell inlets and canopy wrinkles. The bridle is assumed
# to hold this shape; its drag is added by WindShipOpt. Writes one CSV per aspect ratio
# to output/ with alpha [deg], CL, CD, CS on the projected area, and its section leading
# and trailing edges [m].
using DelimitedFiles
using LinearAlgebra
using Printf
using VortexStepMethod
using VortexStepMethod.AirfoilAero: NeuralFoilSolver, generate_polar_from_coordinates

projected_area = 100.0
aspect_ratios = [3.0, 4.0, 5.0, 6.0, 8.0]
flattening = 0.82
tip_chord_ratio = 0.4
airfoil = (camber=0.04, camber_position=0.4, thickness=0.15)
reynolds = 5e6
transition = 0.05
inlet_drag = 0.015
alphas = -6.0:1.0:22.0
section_count = 25
output = mkpath(joinpath(@__DIR__, "output"))

"""
    naca_four_digit(camber, camber_position, thickness; points=80)

Coordinates of a NACA four-digit airfoil of unit chord, from the trailing edge over the
upper surface to the leading edge and back over the lower surface.
"""
function naca_four_digit(camber, camber_position, thickness; points=80)
    stations = (1 .- cos.(range(0, π; length=points))) ./ 2
    upper_x, upper_y, lower_x, lower_y = (zeros(points) for _ in 1:4)
    for (i, x) in enumerate(stations)
        half = 5thickness * (0.2969sqrt(x) - 0.126x - 0.3516x^2 + 0.2843x^3 - 0.1036x^4)
        front = x < camber_position
        line = front ? camber / camber_position^2 * (2camber_position * x - x^2) :
               camber / (1 - camber_position)^2 *
               (1 - 2camber_position + 2camber_position * x - x^2)
        slope = front ? 2camber / camber_position^2 * (camber_position - x) :
                2camber / (1 - camber_position)^2 * (camber_position - x)
        angle = atan(slope)
        upper_x[i], upper_y[i] = x - half * sin(angle), line + half * cos(angle)
        lower_x[i], lower_y[i] = x + half * sin(angle), line - half * cos(angle)
    end
    return [reverse(upper_x); lower_x[2:end]], [reverse(upper_y); lower_y[2:end]]
end

"""
    arc_angle(flattening)

Half angle [rad] of a circular arc whose chord over arc length is `flattening`.
"""
function arc_angle(flattening)
    low, high = 1e-6, π / 2
    for _ in 1:60
        middle = (low + high) / 2
        sin(middle) / middle > flattening ? (low = middle) : (high = middle)
    end
    return (low + high) / 2
end

"""
    chord_shape(position)

Chord over root chord at spanwise `position` from -1 to 1 along the flat span.
"""
chord_shape(position) =
    tip_chord_ratio + (1 - tip_chord_ratio) * sqrt(max(1 - position^2, 0))

"""
    kite_wing(aspect_ratio, polar; root_chord=1.0)

VSM wing of projected `aspect_ratio` bent on a circular arc with the quarter chord line on
the arc; `polar` is the (alpha [rad], cl, cd, cm) of the airfoil.
"""
function kite_wing(aspect_ratio, polar; root_chord=1.0)
    half_angle = arc_angle(flattening)
    projected_span = sqrt(aspect_ratio * projected_area)
    radius = projected_span / 2 / sin(half_angle)
    wing = Wing(4section_count; spanwise_distribution=LINEAR)
    for position in cos.(range(0, π; length=section_count))
        angle = half_angle * position
        chord = root_chord * chord_shape(position)
        span_point = [0.0, radius * sin(angle), radius * (cos(angle) - 1)]
        add_section!(wing, span_point .+ [-chord / 4, 0, 0],
            span_point .+ [3chord / 4, 0, 0], POLAR_VECTORS, polar)
    end
    refine!(wing)
    return wing
end

"""
    scaled_kite_wing(aspect_ratio, polar)

[`kite_wing`](@ref) with the root chord that gives the projected area.
"""
function scaled_kite_wing(aspect_ratio, polar)
    trial = kite_wing(aspect_ratio, polar)
    root_chord = projected_area / calculate_projected_area(trial)
    return kite_wing(aspect_ratio, polar; root_chord)
end

x, y = naca_four_digit(airfoil.camber, airfoil.camber_position, airfoil.thickness)
sections = generate_polar_from_coordinates(x, y, joinpath(output, "airfoil.csv");
    Re=reynolds, alpha_range=-30:1:30,
    solver=NeuralFoilSolver(n_crit=4.0, xtr_upper=transition, xtr_lower=transition))
polar = ([section.alpha for section in sections], [section.cl for section in sections],
    [section.cd + inlet_drag for section in sections], [section.cm for section in sections])

for aspect_ratio in aspect_ratios
    wing = scaled_kite_wing(aspect_ratio, polar)
    body = BodyAerodynamics([wing])
    solver = Solver(wing.n_panels, wing.n_unrefined_sections; aerodynamic_model_type=VSM)
    rows = zeros(length(alphas), 4)
    for (i, alpha) in enumerate(alphas)
        set_va!(body, apparent_wind(deg2rad(alpha), 0.0, 30.0))
        results = solve(solver, body)
        rows[i, :] = [alpha, results["cl"], results["cd"], results["cs"]]
    end
    open(joinpath(output, @sprintf("geometry_ar%.0f.csv", aspect_ratio)), "w") do io
        println(io, "le_x,le_y,le_z,te_x,te_y,te_z")
        for section in wing.unrefined_sections
            writedlm(io, [section.LE_point; section.TE_point]', ',')
        end
    end
    path = joinpath(output, @sprintf("kite_ar%.0f.csv", aspect_ratio))
    open(path, "w") do io
        println(io, "alpha,cl,cd,cs")
        writedlm(io, rows, ',')
    end
    best = argmax(rows[:, 2] ./ rows[:, 3])
    @printf("AR %.0f: area %.1f m2, max L/D %.1f at alpha %.0f (CL %.2f), CL max %.2f\n",
        aspect_ratio, body.projected_area, rows[best, 2] / rows[best, 3], rows[best, 1],
        rows[best, 2], maximum(rows[:, 2]))
end
