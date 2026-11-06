# Drawings of the model for the paper's method section: each saves one PDF to paper/figures/,
# with its sizes and forces from the model and its inputs. Included by paper.jl.

"""
    hull_outline(length, beam)

Points of a hull seen from above, bow up along +y and midship at the origin: a transom
stern, parallel sides and a bow over the forward quarter of the length [m].
"""
function hull_outline(length, beam)
    half = beam / 2
    shoulder = length / 4
    bow = [Point2f(half * cos(angle), length / 2 - shoulder + shoulder * sin(angle))
           for angle in range(0, π / 2; length=12)]
    port = [Point2f(-point[1], point[2]) for point in reverse(bow)]
    return vcat([Point2f(0.8half, -length / 2)], bow, port, [Point2f(-0.8half, -length / 2)])
end

"""
    force_arrow!(axis, origin, force, label; scale, color, align, offset, at_tail)

Arrow of `force` [kN, x and y] from `origin` [m], `scale` metres per kN, labelled with its
magnitude at its tip, or at its tail when `at_tail`.
"""
function force_arrow!(axis, origin, force, label; scale, color, align=(:center, :center),
        offset=(0, 0), at_tail=false)
    vector = Vec2f(force .* scale)
    arrows2d!(axis, [Point2f(origin)], [vector]; color, shaftwidth=1.3, tipwidth=6,
        tiplength=6)
    text!(axis, at_tail ? Point2f(origin) : Point2f(origin) + vector;
        text=@sprintf("%s %.0f kN", label, hypot(force...)), align, offset, fontsize=8,
        color)
end

"""
    force_balance_figure()

Forces on the 140 m ship at 10.5 kn in a 10 m/s beam wind, seen from above, for a kite,
wings and rotors at their best trim: the rig force, the hull's side force at its lateral
centre, the rudder force, the resistance and the propeller thrust, to scale.
"""
function force_balance_figure()
    speed, wind, angle = 10.5KNOT, 10.0, deg2rad(90)
    rigs = (("(a) kite 800 m²", (kite_area=800.0,)), ("(b) wings 800 m²",
        (wing_area=800.0,)), ("(c) rotors 400 m²", (rotor_area=400.0,)))
    figure = Figure(size=(page_width, 270))
    scale = 0.18
    for (column, (title, area)) in enumerate(rigs)
        ship = Ship(ShipDesign(:vlsfo, 140.0; area...), assumptions)
        (; hull) = ship
        thrust, force = WindShipOpt.best_trim(ship, ship.rig, speed, wind, angle)
        balance = WindShipOpt.HullBalance(ship, speed, force)
        centre = WindShipOpt.lateral_centre(hull)
        leeward = -sign(force.side)
        rudder = (force.side * centre - force.yaw_moment) / (-hull.length / 2 - centre)
        resistance = thrust + force.thrust
        axis = Axis(figure[1, column]; aspect=DataAspect(), title=@sprintf(
            "%s\nleeway %.1f°, heel %.1f°", title, rad2deg(balance.leeway),
            rad2deg(balance.heel)))
        hidedecorations!(axis)
        hidespines!(axis)
        poly!(axis, hull_outline(hull.length, hull.beam); color=:gray90,
            strokecolor=:black, strokewidth=0.75)
        side = leeward * force.side / 1e3
        draw_rig!(axis, ship.rig, hull, Vec2f(side, force.thrust / 1e3))
        rig_origin = (0.0, force.yaw_moment / force.side)
        force_arrow!(axis, rig_origin, (side, force.thrust / 1e3), "rig"; scale,
            color=palette[1], align=(:center, :bottom), offset=(0, 2))
        force_arrow!(axis, (hull.beam / 2, centre), (-side - leeward * rudder / 1e3, 0.0),
            "hull"; scale, color=palette[6], align=(:left, :bottom), offset=(2, 2),
            at_tail=true)
        abs(rudder) > 1 && force_arrow!(axis, (0.0, -hull.length / 2),
            (leeward * rudder / 1e3, 0.0), "rudder"; scale, color=palette[3],
            align=(:left, :center), offset=(3, 0))
        stern = -hull.length / 2
        force_arrow!(axis, (hull.beam / 4, stern), (0.0, -resistance / 1e3), "drag";
            scale, color=:gray30, align=(:left, :top), offset=(0, -2))
        force_arrow!(axis, (-hull.beam / 4, stern - thrust * scale / 1e3),
            (0.0, thrust / 1e3), "propeller"; scale, color=palette[2],
            align=(:right, :top), offset=(0, -2), at_tail=true)
        arrows2d!(axis, [Point2f(88, -15)], [Vec2f(-25, 0)]; color=:gray50,
            shaftwidth=1.3, tipwidth=6, tiplength=6)
        text!(axis, 88, -15; text=@sprintf("true wind\n%.0f m/s", wind),
            align=(:right, :bottom), offset=(0, 3), fontsize=8, color=:gray50)
        limits!(axis, -90, 90, stern - 62, hull.length / 2 + 25)
    end
    save(joinpath(figures, "force_balance.pdf"), figure; pt_per_unit=print_scale)
end

"""
    draw_rig!(axis, rig, hull, force)

Plan view of `rig` on `hull`: a kite's tether along its horizontal `force` [x and y], wings
as their chords, rotors as circles.
"""
function draw_rig!(axis, rig::KiteRig, hull, force)
    attach = Point2f(0, rig.attach_position)
    lines!(axis, [attach, attach + 200 * force / hypot(force...)]; color=:gray60,
        linewidth=0.75,
        linestyle=:dash)
    scatter!(axis, [attach]; color=:black, markersize=4)
end

function draw_rig!(axis, rig::WingRig, hull, force)
    chord = sqrt(rig.area / assumptions[:wing_aspect_ratio])
    for position in WindShipOpt.unit_positions(rig, hull, assumptions)
        lines!(axis, [Point2f(0, position + chord / 2), Point2f(0, position - chord / 2)];
            color=:black, linewidth=2.5)
    end
end

function draw_rig!(axis, rig::WindShipOpt.RotorRig, hull, force)
    for position in WindShipOpt.unit_positions(rig, hull, assumptions)
        poly!(axis, Circle(Point2f(0, position), rig.diameter / 2); color=:white,
            strokecolor=:black, strokewidth=0.75)
    end
end

"""
    hull_profile(hull, deck_height)

Points of `hull` seen from the side, bow to the right and midship at the origin: keel at
the draft below the waterline, deck at `deck_height` [m] above it, a raked bow and a
transom stern.
"""
function hull_profile(hull, deck_height)
    half = hull.length / 2
    return Point2f[(-half, deck_height), (half + 0.03hull.length, deck_height),
        (half, 0), (half - 0.02hull.length, -hull.draft), (-half + 0.04hull.length,
            -hull.draft), (-half, -0.3hull.draft)]
end

"""
    draw_ship!(axis, hull, offset)

Side view of `hull` shifted by `offset` [m]: hull, deckhouse aft and waterline, and the
height of its deck above the waterline [m] as the model places rigs on it.
"""
function draw_ship!(axis, hull, offset)
    scale = hull.length / assumptions[:reference_length]
    deck = assumptions[:deck_mount_height] * scale
    house = assumptions[:superstructure_height] * scale
    poly!(axis, hull_profile(hull, deck) .+ Point2f(offset); color=:gray80,
        strokecolor=:black, strokewidth=0.5)
    half = hull.length / 2
    poly!(axis, Rect2f(Point2f(offset) + Point2f(-half + 0.02hull.length, deck),
            Vec2f(0.08hull.length, house)); color=:gray80, strokecolor=:black,
        strokewidth=0.5)
    return deck
end

"""
    draw_side_rig!(axis, rig, hull, offset)

Side view of the wing or rotor `rig` on `hull` shifted by `offset` [m]: each unit as its
height times its chord or diameter, standing at its foot height.
"""
function draw_side_rig!(axis, rig, hull, offset)
    width = rig isa WingRig ? sqrt(rig.area / assumptions[:wing_aspect_ratio]) :
            rig.diameter
    for position in WindShipOpt.unit_positions(rig, hull, assumptions)
        poly!(axis, Rect2f(Point2f(offset) + Point2f(position - width / 2,
                    rig.foot_height), Vec2f(width, rig.height)); color=palette[1],
            strokewidth=0)
    end
end

"""
    draw_side_kite!(axis, area, hull, offset)

Side view of a kite of projected `area` [m^2] at the design aspect ratio towed by `hull`
shifted by `offset` [m]: its launch mast at the towing point and the canopy, to scale
across its span, just above the mast on a tether not drawn to length. Returns the height
of the canopy's top above the waterline [m].
"""
function draw_side_kite!(axis, area, hull, offset)
    span = sqrt(area * design_aspect_ratio)
    scale = hull.length / assumptions[:reference_length]
    deck = assumptions[:deck_mount_height] * scale
    mast = assumptions[:launch_mast_height_ratio] * sqrt(area)
    foot = Point2f(offset) + Point2f(WindShipOpt.lateral_centre(hull), deck)
    lines!(axis, [foot, foot + Point2f(0, mast)]; color=:black, linewidth=1)
    sag = 0.15span
    top = deck + mast + 20 + sag
    centre = Point2f(foot[1], offset[2] + top)
    arc = [centre + Point2f(span / 2 * sin(t), sag * cos(t) - sag)
           for t in range(-π / 2, π / 2; length=24)]
    lines!(axis, arc; color=palette[2], linewidth=2)
    lines!(axis, [foot + Point2f(0, mast), centre]; color=:gray50, linewidth=0.6,
        linestyle=:dash)
    return top
end

"""
    ship_classes_figure()

The standard ship classes in deadweight order, side by side to one scale, each with the
geometric mean over the routes of the best size of a kite, of wings and of rotors on
VLSFO, laid out as the model lays them out.
"""
function ship_classes_figure()
    table = read_table(data_file("classes.csv"))
    names = class_order(table)
    classes = ship_classes()
    routes_seen = unique(table["route"])
    longest = maximum(classes[name].length for name in names)
    gap = 0.15longest
    rig_kinds = ("kite", "wings", "rotors")
    rows = [(name, Hull(classes[name], assumptions), [mean_best_area(table, name,
        routes_seen, kind) for kind in rig_kinds]) for name in names]
    kite_tops = [draw_height(hull, first(areas)) for (_, hull, areas) in rows]
    margin = 30.0
    tops = cumsum([kite_top + hull.draft + margin
                   for (kite_top, (_, hull, _)) in zip(kite_tops, rows)])
    width = 3longest + 2gap
    figure = Figure(size=(page_width, page_width * (last(tops) + 20) / (1.3width)))
    axis = Axis(figure[1, 1]; aspect=DataAspect())
    hidedecorations!(axis)
    hidespines!(axis)
    for (row, (name, hull, areas)) in enumerate(rows)
        y = -tops[row] + hull.draft + margin
        for (column, (kind, area)) in enumerate(zip(rig_kinds, areas))
            offset = ((column - 1) * (longest + gap) + longest / 2, y)
            draw_ship!(axis, hull, offset)
            isfinite(area) || continue
            if kind == "kite"
                draw_side_kite!(axis, area, hull, offset)
            else
                rig = kind == "wings" ? WingRig(area, hull, assumptions) :
                      WindShipOpt.RotorRig(area, hull, assumptions)
                isnothing(rig) || draw_side_rig!(axis, rig, hull, offset)
            end
            text!(axis, offset[1] - hull.length / 2, y - hull.draft;
                text=@sprintf("%.0f m²", area), align=(:left, :top), offset=(0, -1),
                fontsize=7, color=:gray40)
        end
        text!(axis, -0.03longest, y; text=name, align=(:right, :center), fontsize=8)
    end
    for (column, kind) in enumerate(rig_kinds)
        text!(axis, (column - 1) * (longest + gap) + longest / 2, 10; text=kind,
            align=(:center, :bottom), fontsize=9)
    end
    bar = Point2f(-0.25width, -last(tops) + 10)
    lines!(axis, [bar, bar + Point2f(100, 0)]; color=:black, linewidth=1.5)
    text!(axis, bar + Point2f(50, 0); text="100 m", align=(:center, :bottom),
        offset=(0, 2), fontsize=8)
    limits!(axis, -0.3width, width, -last(tops), 40)
    save(joinpath(figures, "ship_classes.pdf"), figure; pt_per_unit=print_scale)
end

"""
    mean_best_area(table, class, routes, rig)

Geometric mean over `routes` of the best area [m^2] of `rig` on `class` on VLSFO in the
class study `table`, or NaN where it has none.
"""
function mean_best_area(table, class, routes, rig)
    areas = filter(isfinite, [best_area(table, class, route, "vlsfo", rig)
                              for route in routes])
    return isempty(areas) ? NaN : exp(sum(log, areas) / length(areas))
end

"""
    draw_height(hull, kite_area)

Height [m] above the waterline of the top of what [`ship_classes_figure`](@ref) draws on
`hull`: the kite of `kite_area` [m^2], or the highest deck rig the air draft allows.
"""
function draw_height(hull, kite_area)
    isfinite(kite_area) || return assumptions[:max_air_draft]
    scale = hull.length / assumptions[:reference_length]
    span = sqrt(kite_area * design_aspect_ratio)
    return max(assumptions[:deck_mount_height] * scale +
               assumptions[:launch_mast_height_ratio] * sqrt(kite_area) + 20 + 0.15span,
        assumptions[:max_air_draft])
end
