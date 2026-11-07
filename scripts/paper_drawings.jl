# Drawings of the model for the paper's method section: each saves one PDF to
# paper/figures/, with its sizes and forces from the model and its inputs. Included by
# paper.jl.

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
    stern = -length / 2
    return vcat([Point2f(0.8half, stern)], bow, port, [Point2f(-0.8half, stern)])
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
        text=@sprintf("%s %.0f kN", label, hypot(force...)), align, offset, fontsize=pt(8),
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
        rudder = WindShipOpt.rudder_side_force(hull, force)
        resistance = thrust + force.thrust
        stern = -hull.length / 2
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
        abs(rudder) > 1 && force_arrow!(axis, (0.0, stern),
            (leeward * rudder / 1e3, 0.0), "rudder"; scale, color=palette[3],
            align=(:left, :center), offset=(3, 0))
        force_arrow!(axis, (hull.beam / 4, stern), (0.0, -resistance / 1e3), "drag";
            scale, color=:gray30, align=(:left, :top), offset=(0, -2))
        force_arrow!(axis, (-hull.beam / 4, stern - thrust * scale / 1e3),
            (0.0, thrust / 1e3), "propeller"; scale, color=palette[2],
            align=(:right, :top), offset=(0, -2), at_tail=true)
        arrows2d!(axis, [Point2f(88, -15)], [Vec2f(-25, 0)]; color=:gray50,
            shaftwidth=1.3, tipwidth=6, tiplength=6)
        text!(axis, 88, -15; text=@sprintf("true wind\n%.0f m/s", wind),
            align=(:right, :bottom), offset=(0, 3), fontsize=pt(8), color=:gray50)
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
        linewidth=0.75, linestyle=:dash)
    scatter!(axis, [attach]; color=:black, markersize=4)
end

function draw_rig!(axis, rig::WingRig, hull, force)
    chord = rig.height / assumptions[:wing_aspect_ratio]
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

Side view of `hull` shifted by `offset` [m]: hull and deckhouse aft, with the deck at the
height above the waterline at which the model stands rigs on it.
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
end

"""
    draw_side_rig!(axis, rig, hull, offset)

Side view of the wing or rotor `rig` on `hull` shifted by `offset` [m]: each unit as its
height times its chord or diameter, standing at its foot height.
"""
function draw_side_rig!(axis, rig, hull, offset)
    width = rig isa WingRig ? rig.height / assumptions[:wing_aspect_ratio] : rig.diameter
    for position in WindShipOpt.unit_positions(rig, hull, assumptions)
        poly!(axis, Rect2f(Point2f(offset) + Point2f(position - width / 2,
                    rig.foot_height), Vec2f(width, rig.height)); color=palette[1],
            strokewidth=0)
    end
end

"""
    side_kite(area, hull)

Heights [m] above the waterline and span [m] of the side view of a kite of projected
`area` [m^2] at the design aspect ratio on `hull`: its deck, launch mast top, the sag of the
canopy's arc and the canopy's top, drawn just above the mast.
"""
function side_kite(area, hull)
    span = sqrt(area * design_aspect_ratio)
    deck = assumptions[:deck_mount_height] * hull.length / assumptions[:reference_length]
    mast_top = deck + assumptions[:launch_mast_height_ratio] * sqrt(area)
    sag = 0.15span
    return (; span, deck, mast_top, sag, top=mast_top + 20 + sag)
end

"""
    draw_side_kite!(axis, area, hull, offset)

Side view of the kite of [`side_kite`](@ref) towed by `hull` shifted by `offset` [m]: its
launch mast at the towing point and the canopy, to scale across its span, on a tether not
drawn to length.
"""
function draw_side_kite!(axis, area, hull, offset)
    (; span, deck, mast_top, sag, top) = side_kite(area, hull)
    foot = Point2f(offset) + Point2f(WindShipOpt.kite_tow_point(hull, assumptions), deck)
    mast = foot + Point2f(0, mast_top - deck)
    lines!(axis, [foot, mast]; color=:black, linewidth=1)
    centre = Point2f(foot[1], offset[2] + top)
    arc = [centre + Point2f(span / 2 * sin(t), sag * cos(t) - sag)
           for t in range(-π / 2, π / 2; length=24)]
    lines!(axis, arc; color=palette[2], linewidth=2)
    lines!(axis, [mast, centre]; color=:gray50, linewidth=0.6, linestyle=:dash)
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
                fontsize=pt(7), color=:gray40)
        end
        text!(axis, -0.03longest, y; text=name, align=(:right, :center), fontsize=pt(8))
    end
    for (column, kind) in enumerate(rig_kinds)
        text!(axis, (column - 1) * (longest + gap) + longest / 2, 10; text=kind,
            align=(:center, :bottom), fontsize=pt(9))
    end
    bar = Point2f(-0.25width, -last(tops) + 10)
    lines!(axis, [bar, bar + Point2f(100, 0)]; color=:black, linewidth=1.5)
    text!(axis, bar + Point2f(50, 0); text="100 m", align=(:center, :bottom),
        offset=(0, 2), fontsize=pt(8))
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
    return max(side_kite(kite_area, hull).top, assumptions[:max_air_draft])
end

"""
    kite_frames_figure()

(a) The wind window seen looking downwind: the kite at its roll angle and its angle off
downwind, the band of roll angles of a pattern, and the heading in the tangent plane. (b)
Seen from the side, the angle off downwind. (c) Seen from above, the mean tether force
resolved along and across the ship's course.
"""
function kite_frames_figure()
    figure = Figure(size=(page_width, 160))
    titles = ("(a) looking downwind", "(b) from the side", "(c) from above")
    axes = [Axis(figure[1, k]; aspect=DataAspect(), title) for (k, title) in
            enumerate(titles)]
    for axis in axes
        hidedecorations!(axis)
        hidespines!(axis)
    end
    colsize!(figure.layout, 1, Auto(1.55))
    colsize!(figure.layout, 3, Auto(1.15))
    draw_window!(axes[1])
    draw_side_sphere!(axes[2])
    draw_course_plan!(axes[3])
    save(joinpath(figures, "kite_frames.pdf"), figure; pt_per_unit=print_scale)
end

"point at `radius` and `angle` [rad] from the +x axis of a figure, counterclockwise"
polar_point(radius, angle) = Point2f(radius * cos(angle), radius * sin(angle))

"""
    small_arrow!(axis, origin, vector, label; color, align)

A thin arrow of `vector` from `origin` with `label` at its tip.
"""
function small_arrow!(axis, origin, vector, label; color=:black, align=(:left, :center))
    arrows2d!(axis, [Point2f(origin)], [Vec2f(vector)]; color, shaftwidth=0.8,
        tipwidth=5, tiplength=5)
    text!(axis, Point2f(origin) + Vec2f(vector); text=label, align, offset=(2, 0),
        fontsize=pt(10), color)
end

"point of the window seen looking downwind at `radius` and `roll` [rad], `y` to the left"
window_point(radius, roll) = polar_point(radius, π - roll)

"""
    draw_window!(axis)

The wind window seen looking downwind: its edge, circles of equal angle off downwind,
the band of roll angles a pattern sweeps, the elevation below the lowest of the
assumptions, and a kite with its tangent-plane unit vectors and heading.
"""
function draw_window!(axis)
    band = deg2rad.((35, 75))
    poly!(axis, vcat([Point2f(0, 0)], [window_point(1, roll) for roll in range(band...;
        length=30)]); color=(palette[2], 0.15))
    for polar in (30, 60)
        lines!(axis, [window_point(sind(polar), roll) for roll in range(0, π; length=60)];
            color=:gray70, linewidth=0.5)
        text!(axis, window_point(sind(polar), deg2rad(150));
            text=L"\vartheta = %$(polar)°", align=(:left, :bottom), offset=(1, 0),
            fontsize=pt(7), color=:gray50)
    end
    lines!(axis, [window_point(1, roll) for roll in range(0, π; length=90)];
        color=:black)
    lowest = sind(assumptions[:kite_min_elevation])
    poly!(axis, Point2f[(-sqrt(1 - lowest^2), lowest), (sqrt(1 - lowest^2), lowest),
        (1, 0), (-1, 0)]; color=(:gray50, 0.3))
    lines!(axis, Point2f[(-1.15, 0), (1.15, 0)]; color=:black, linewidth=0.6)
    text!(axis, window_point(1, deg2rad(130)); text="edge of\nthe window",
        align=(:left, :bottom), offset=(2, 0), fontsize=pt(8))
    text!(axis, 1.03, lowest / 2;
        text="below $(round(Int, assumptions[:kite_min_elevation]))°",
        align=(:left, :center), fontsize=pt(7), color=:gray40)
    polar, roll = deg2rad(33), deg2rad(62)
    kite = window_point(sin(polar), roll)
    lines!(axis, [Point2f(0, 0), kite]; color=:gray50, linewidth=0.6, linestyle=:dash)
    lines!(axis, [window_point(0.22, angle) for angle in range(0, roll; length=20)];
        color=palette[3])
    text!(axis, window_point(0.26, roll / 2); text=L"\phi", align=(:right, :center),
        fontsize=pt(10), color=palette[3])
    outward = Vec2f(kite / hypot(kite...))
    along = Vec2f(outward[2], -outward[1])
    heading = deg2rad(65)
    small_arrow!(axis, kite, 0.3outward, L"\hat{\mathbf{e}}_\vartheta";
        align=(:right, :bottom))
    small_arrow!(axis, kite, 0.3along, L"\hat{\mathbf{e}}_\phi"; align=(:left, :top))
    small_arrow!(axis, kite, 0.38 * (cos(heading) * outward + sin(heading) * along),
        L"\hat{\mathbf{h}}"; color=palette[6])
    lines!(axis, [kite + 0.14 * (cos(angle) * outward + sin(angle) * along)
                  for angle in range(0, heading; length=12)]; color=palette[6])
    text!(axis, kite + 0.2 * (cos(heading / 2) * outward + sin(heading / 2) * along);
        text=L"\psi", align=(:center, :center), fontsize=pt(10), color=palette[6])
    scatter!(axis, [kite]; color=palette[2], markersize=8)
    small_arrow!(axis, (1.5, 0.28), (-0.2, 0), L"y"; align=(:right, :bottom))
    small_arrow!(axis, (1.5, 0.28), (0, 0.2), L"z"; align=(:center, :bottom))
    limits!(axis, -1.2, 1.6, -0.08, 1.12)
end

"""
    draw_side_sphere!(axis)

Section of the tether sphere through the kite seen from the side, apparent wind to the
right: the tether at the angle off downwind.
"""
function draw_side_sphere!(axis)
    lines!(axis, [polar_point(1, angle) for angle in range(0, π / 2; length=40)];
        color=:black)
    lines!(axis, Point2f[(-0.1, 0), (1.25, 0)]; color=:black, linewidth=0.6)
    small_arrow!(axis, (0.55, -0.15), (0.45, 0), L"x"; align=(:left, :center))
    text!(axis, 0.75, -0.18; text="apparent wind", align=(:center, :top), fontsize=pt(8))
    polar = deg2rad(50)
    kite = polar_point(1, polar)
    lines!(axis, [Point2f(0, 0), kite]; color=palette[2], linewidth=1.5)
    scatter!(axis, [kite]; color=palette[2], markersize=8)
    text!(axis, kite / 2; text=L"r\,\hat{\mathbf{e}}_r", align=(:right, :bottom),
        fontsize=pt(10), color=palette[2])
    lines!(axis, [polar_point(0.3, angle) for angle in range(0, polar; length=20)];
        color=palette[1])
    text!(axis, polar_point(0.36, polar / 2); text=L"\vartheta", align=(:left, :center),
        fontsize=pt(10), color=palette[1])
    scatter!(axis, [Point2f(0, 0)]; color=:black, markersize=4)
    text!(axis, 0, 0; text="tow point", align=(:right, :bottom), offset=(-2, 2),
        fontsize=pt(8))
    limits!(axis, -0.65, 1.3, -0.4, 1.1)
end

"`point` turned clockwise by `angle` [rad] about the origin"
rotated(point, angle) = Point2f(point[1] * cos(angle) + point[2] * sin(angle),
    -point[1] * sin(angle) + point[2] * cos(angle))

"""
    draw_course_plan!(axis)

Plan view of the wind window as a half disc downwind of the ship, the ship's course `χ`
off the apparent downwind direction, and the mean tether force with its components along
and across the course.
"""
function draw_course_plan!(axis)
    poly!(axis, [Point2f(sin(angle), cos(angle)) for angle in range(-π / 2, π / 2;
        length=60)]; color=(palette[2], 0.12), strokecolor=:black, strokewidth=0.6)
    arrows2d!(axis, [Point2f(0, 0)], [Vec2f(0, 1.2)]; color=:black, shaftwidth=0.8,
        tipwidth=5, tiplength=5)
    text!(axis, 0, 1.2; text="apparent downwind", align=(:left, :top), offset=(3, 0),
        fontsize=pt(8))
    course = deg2rad(110)
    heading = Vec2f(sin(course), cos(course))
    poly!(axis, rotated.(hull_outline(0.5, 0.09), course); color=:gray80,
        strokecolor=:black, strokewidth=0.6)
    lines!(axis, [Point2f(0, 0), Point2f(1.25heading)]; color=:black, linestyle=:dash,
        linewidth=0.6)
    text!(axis, Point2f(1.25heading); text="course", align=(:left, :center), fontsize=pt(8))
    lines!(axis, [0.3Point2f(sin(angle), cos(angle)) for angle in range(0, course;
        length=30)]; color=palette[1])
    text!(axis, 0.36Point2f(sin(course / 2), cos(course / 2)); text=L"\chi",
        align=(:left, :bottom), fontsize=pt(10), color=palette[1])
    force = Vec2f(0.85, 0.35)
    along = sum(force .* heading) * heading
    arrows2d!(axis, [Point2f(0, 0)], [force]; color=palette[2], shaftwidth=1.3,
        tipwidth=6, tiplength=6)
    text!(axis, Point2f(force); text=L"\overline{\mathbf{F}}", align=(:left, :bottom),
        fontsize=pt(10), color=palette[2])
    for (vector, label, origin) in ((along, L"F_\parallel", Point2f(0, 0)),
        (force - along, L"F_\perp", Point2f(along)))
        arrows2d!(axis, [origin], [vector]; color=palette[6], shaftwidth=0.8,
            tipwidth=5, tiplength=5)
        text!(axis, origin + vector / 2; text=label, align=(:left, :top), offset=(3, 0),
            fontsize=pt(10), color=palette[6])
    end
    limits!(axis, -1.1, 1.7, -0.75, 1.3)
end

"""
    router_figure()

(a) The router's grid of stages and lateral nodes along a corridor, the edges one node may
take to the next stage and a chosen passage. (b) The states of a kite ship at the two ends
of an edge: kite down or aloft, each holding arrivals in time bins of the router settings,
and the changes the edge may make.
"""
function router_figure()
    figure = Figure(size=(page_width, 170))
    grid = Axis(figure[1, 1]; aspect=DataAspect(), title="(a) stages and lateral nodes")
    states = Axis(figure[1, 2]; aspect=DataAspect(), title="(b) kite states along an edge")
    colsize!(figure.layout, 1, Auto(1.5))
    for axis in (grid, states)
        hidedecorations!(axis)
        hidespines!(axis)
    end
    draw_router_grid!(grid)
    draw_kite_states!(states)
    save(joinpath(figures, "router.pdf"), figure; pt_per_unit=print_scale)
end

"""
    draw_router_grid!(axis)

Nodes of a corridor of nine stages that widens from the departure and narrows to the
destination, the edges from one node and a passage.
"""
function draw_router_grid!(axis)
    stages = 0:10
    half_width(stage) = min(2stage, 2(last(stages) - stage), 5)
    nodes = [Point2f(stage, lateral) for stage in stages
             for lateral in -half_width(stage):half_width(stage)]
    scatter!(axis, nodes; color=:gray60, markersize=3)
    from = Point2f(4, 1)
    for step in -WindShipOpt.MAX_LATERAL_STEP:WindShipOpt.MAX_LATERAL_STEP
        lines!(axis, [from, from + Point2f(1, step)]; color=palette[1], linewidth=0.7)
    end
    passage = Point2f[(0, 0), (1, 1), (2, 2), (3, 2), (4, 1), (5, -1), (6, -3), (7, -3),
        (8, -2), (9, -1), (10, 0)]
    lines!(axis, passage; color=palette[2], linewidth=2)
    scatter!(axis, [first(passage), last(passage)]; color=:black, markersize=6)
    text!(axis, first(passage); text="departure", align=(:right, :center),
        offset=(-4, 0), fontsize=pt(8))
    text!(axis, last(passage); text="destination", align=(:left, :center),
        offset=(4, 0), fontsize=pt(8))
    settings = WindShipOpt.ROUTER_SETTINGS[]
    speeds = length(WindShipOpt.commanded_speeds(settings.routing_speeds,
        settings.search_speed_stride))
    text!(axis, from + Point2f(1, WindShipOpt.MAX_LATERAL_STEP); text=@sprintf(
        "edges to ±%d nodes,\n%d speeds from %g kn", WindShipOpt.MAX_LATERAL_STEP, speeds,
        WindShipOpt.LOWEST_ROUTING_KNOTS),
        align=(:left, :bottom), offset=(3, 0), fontsize=pt(8), color=palette[1])
    arrows2d!(axis, [Point2f(2, -5.8)], [Vec2f(6, 0)]; color=:black, shaftwidth=0.6,
        tipwidth=4, tiplength=4)
    text!(axis, 5, -5.8; text=L"stage $s$", align=(:center, :top), offset=(0, -2),
        fontsize=pt(8))
    arrows2d!(axis, [Point2f(1.2, 2.5)], [Vec2f(0, 3)]; color=:black, shaftwidth=0.6,
        tipwidth=4, tiplength=4)
    text!(axis, 1.2, 4; text=L"node $j$", align=(:right, :center), offset=(-3, 0),
        fontsize=pt(8))
    limits!(axis, -4.5, 15, -6.8, 6)
end

"""
    draw_kite_states!(axis)

Two states, kite down and kite aloft, at the start and the end of an edge, each with a time
axis of bins, and the four changes between them along the edge.
"""
function draw_kite_states!(axis)
    bin = WindShipOpt.RouterSettings().time_step
    rows = (("aloft", 1.0), ("down", 0.0))
    for x in (0.0, 3.0), (label, y) in rows
        poly!(axis, Rect2f(x - 0.45, y - 0.32, 0.9, 0.64); color=:white,
            strokecolor=:black, strokewidth=0.6)
        for k in 0:4
            lines!(axis, Point2f[(x - 0.35 + 0.175k, y - 0.32), (x - 0.35 + 0.175k,
                y - 0.2)]; color=:gray50, linewidth=0.5)
        end
        scatter!(axis, [Point2f(x - 0.1, y - 0.26)]; color=palette[2], markersize=4)
        text!(axis, x, y; text="kite $label", align=(:center, :bottom), offset=(0, -2),
            fontsize=pt(8))
    end
    changes = ((Point2f(0.5, 1.0), Point2f(2.5, 1.0), "fly"),
        (Point2f(0.5, 0.0), Point2f(2.5, 0.0), "stay down"),
        (Point2f(0.5, 0.15), Point2f(2.5, 0.85), "launch"),
        (Point2f(0.5, 0.85), Point2f(2.5, 0.15), "land"))
    for (start, stop, label) in changes
        arrows2d!(axis, [start], [Vec2f(stop - start)]; color=palette[1],
            shaftwidth=0.7, tipwidth=5, tiplength=5)
        text!(axis, start + 0.22 * (stop - start); text=label, align=(:center, :bottom),
            offset=(0, 2), fontsize=pt(8), color=palette[1])
    end
    text!(axis, 0, -0.45; text=L"stage $s$", align=(:center, :top), fontsize=pt(8))
    text!(axis, 3, -0.45; text=L"stage $s + 1$", align=(:center, :top), fontsize=pt(8))
    text!(axis, 1.5, -0.62; text=@sprintf("ticks: time bins of %.1f h", bin),
        align=(:center, :top), fontsize=pt(7), color=:gray40)
    limits!(axis, -0.6, 3.6, -0.95, 1.5)
end
