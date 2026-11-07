"""
    Windage

Wind load on the hull, deckhouse and deck cargo after Blendermann's loading functions:
the beam-wind drag coefficient on the lateral area, the longitudinal drag coefficients on
the frontal area in head and stern wind, the cross-force parameter δ and the roll-moment
factor κ of the ship type, and the projected areas and the centroid of the lateral area.
"""
Base.@kwdef struct Windage
    "drag coefficient in beam wind on `lateral_area` [-]"
    transverse_drag::Float64
    "longitudinal drag coefficient in head wind on `frontal_area` [-]"
    head_drag::Float64
    "longitudinal drag coefficient in stern wind on `frontal_area` [-]"
    stern_drag::Float64
    "cross-force parameter δ [-]"
    cross_force::Float64
    "roll-moment factor κ: height of the side force over `centre_height` [-]"
    roll_factor::Float64
    "frontal projected area above the waterline [m^2]"
    frontal_area::Float64
    "lateral projected area above the waterline [m^2]"
    lateral_area::Float64
    "length the yaw lever scales with [m]"
    length::Float64
    "centroid of `lateral_area` forward of midship [m]"
    centre_position::Float64
    "centroid of `lateral_area` above the waterline [m]"
    centre_height::Float64
end

"""
    wind_coefficients(windage, angle)

Longitudinal and side force coefficients [-] on the lateral area at the apparent wind
`angle` [rad] off the bow, longitudinal positive forward and side positive to leeward.
"""
function wind_coefficients(windage::Windage, angle)
    longitudinal = (angle < π / 2 ? windage.head_drag : windage.stern_drag) *
                   windage.frontal_area / windage.lateral_area
    transverse = windage.transverse_drag
    denominator = 1 - windage.cross_force / 2 * (1 - longitudinal / transverse) *
                      sin(2angle)^2
    return -longitudinal * cos(angle) / denominator, transverse * sin(angle) / denominator
end

"""
    wind_force(windage, env, wind_10m, true_angle, ship_speed)

Wind force on the ship above the waterline as a [`RigForce`](@ref), from the apparent wind
of the 10 m wind `wind_10m` [m/s] at `true_angle` [rad] on a ship at `ship_speed` [m/s].
"""
function wind_force(windage::Windage, env::Environment, wind_10m, true_angle, ship_speed)
    speed, angle = apparent_wind(wind_10m, true_angle, ship_speed)
    load = 0.5env.air_density * speed^2 * windage.lateral_area
    longitudinal, transverse = wind_coefficients(windage, angle)
    side = load * transverse
    lever = windage.centre_position - 0.18windage.length * (angle - π / 2)
    return RigForce(load * longitudinal, side,
        side * windage.roll_factor * windage.centre_height, side * lever)
end

"""
    Windage(type, length, beam, deck_tiers, assumptions)

Windage of a ship of `type` from `data/wind_loads.csv`: the coefficients of the type and
the areas and centroid of its measured ship scaled to `length` and `beam` [m], with the
container tiers on deck above those of the scaled measured ship added over the stowage
length, centred amidships.
"""
function Windage(type::AbstractString, length, beam, deck_tiers, assumptions::Assumptions)
    measured = wind_load_types()[type]
    scale = length / measured.length
    lateral = measured.lateral_area * scale^2
    added = (deck_tiers - measured.deck_tiers * scale) * assumptions[:container_tier_height]
    stack = assumptions[:container_stowage_fraction] * length * added
    stack_height = measured.deck_cargo_top * scale + added / 2
    return Windage(; measured.transverse_drag, measured.head_drag, measured.stern_drag,
        measured.cross_force, measured.roll_factor, length,
        frontal_area=measured.frontal_area * scale * beam / measured.beam + beam * added,
        lateral_area=lateral + stack,
        centre_position=lateral * measured.centre_position * scale / (lateral + stack),
        centre_height=(lateral * measured.centre_height * scale + stack * stack_height) /
                      (lateral + stack))
end

"""
    wind_load_types()

Wind-load coefficients and measured ship of each ship type, from `data/wind_loads.csv`,
whose rows name the types sharing them separated by `;`.
"""
function wind_load_types()
    lines = readlines(joinpath(pkgdir(@__MODULE__), "data", "wind_loads.csv"))
    header = csv_fields(first(lines))
    numbers = filter(!in(("type", "source")), header)
    types = Dict{String, NamedTuple}()
    for line in lines[2:end]
        row = Dict(zip(header, csv_fields(line)))
        loads = NamedTuple(Symbol(name) => parse(Float64, row[name]) for name in numbers)
        for type in split(row["type"], ';')
            types[type] = loads
        end
    end
    return types
end
