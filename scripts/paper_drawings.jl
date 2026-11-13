# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

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
    force_arrow!(axis, point, force, label; scale, color, align, push=false, at_point=false)

Arrow of `force` [kN, x and y], `scale` metres per kN, from `point` [m], or onto it when
it pushes there, or a ring at `point` when the force is zero, labelled with `label` and
its magnitude at its free end, or at `point` when `at_point`, aligned by `align`; returns
the arrow's two ends [m].
"""
function force_arrow!(axis, point, force, label; scale, color, align, push=false,
        at_point=false)
    magnitude = hypot(force...)
    vector = magnitude < 0.5 ? Vec2f(0, 0) : Vec2f(force .* scale)
    tail = push ? Point2f(point) - vector : Point2f(point)
    if iszero(vector)
        scatter!(axis, [tail]; color=:white, strokecolor=color, strokewidth=rule_width,
            markersize=pt(5))
    else
        arrows2d!(axis, [tail], [vector]; color, shaftwidth=force_width, minshaftlength=0)
    end
    free = push ? tail : tail + vector
    text!(axis, at_point ? Point2f(point) : free; align, fontsize=note_size, color,
        text=@sprintf("%s %.0f kN", label, magnitude),
        offset=clear_offset(align, pt(iszero(vector) || at_point ? 4.5 : 3.5)))
    return [tail, tail + vector]
end

"""
    force_balance_figure()

Forces on the 140 m ship at 10.5 kn in a 10 m/s beam wind, seen from above with the bow
to the right, for a kite, wings and rotors at their best trim, each where it acts and to
one scale: the rig force, the wind load, the hull's side force and leeway drag at its
lateral centre, the rudder's side force and drag, the calm-water resistance and the
propeller thrust.
"""
function force_balance_figure()
    speed, wind, angle = 10.5KNOT, 10.0, deg2rad(90)
    span = (-222.0, 208.0)
    width = page_width - pt(9)
    figure = Figure(size=(page_width, 300))
    for (row, (rig, area)) in enumerate(trim_rigs)
        ship = Ship(ShipDesign(:vlsfo, 140.0; rig_size(rig, area)...), assumptions)
        letter = 'a' + row - 1
        title = L"(%$letter) %$(rig_label(rig)) $%$(round(Int, area))\,\mathrm{m^2}$"
        thrust, force = WindShipOpt.best_trim(ship, ship.rig, speed, wind, angle)
        wind_load = WindShipOpt.wind_force(ship.windage, ship.env, wind, angle, speed)
        balance = WindShipOpt.HullBalance(ship, speed, force + wind_load)
        axis = Axis(figure[row, 1]; width)
        hidedecorations!(axis)
        hidespines!(axis)
        ends = draw_force_balance!(axis, ship, (speed, wind, angle), thrust, force,
            wind_load, palette[row])
        low, high = extrema(last.(ends)) .+ (-13, 13)
        limits!(axis, span..., low, high)
        axis.height = width * (high - low) / (span[2] - span[1])
        text!(axis, span[1], high; text=title, align=(:left, :top))
        leeway, heel = round.(rad2deg.((balance.leeway, balance.heel)); digits=1)
        text!(axis, span[1], high; align=(:left, :top), offset=(0, -pt(11)),
            text=L"leeway $\itbeta = %$(leeway)^\circ$, heel $\itphi = %$(heel)^\circ$",
            fontsize=note_size)
    end
    wind_arrow = content(figure[1, 1])
    arrows2d!(wind_arrow, [Point2f(span[2] - 4, 40)], [Vec2f(0, -24)];
        color=style_colour("wind"), shaftwidth=force_width)
    text!(wind_arrow, Point2f(span[2] - 4, 28); text="true wind 10 m/s",
        align=(:right, :center), offset=(-pt(4), 0), fontsize=note_size,
        color=style_colour("wind"))
    resize_to_layout!(figure)
    save_figure("force_balance", figure)
end

"""
    draw_force_balance!(axis, ship, (speed, wind, angle), thrust, force, wind_load, colour)

Plan view of `ship` at `speed` [m/s] in the true `wind` [m/s] from `angle` [rad] off the
bow, bow to the right and the wind from above, with its rig and the forces [N] of
[`force_balance_figure`](@ref): the rig `force` in `colour`, the `wind_load`, and the
hull, rudder, resistance and propeller `thrust` that balance them; returns the ends [m] of
the arrows and of the hull's beam.
"""
function draw_force_balance!(axis, ship, (speed, wind, angle), thrust, force, wind_load,
        colour)
    (; hull, env) = ship
    total = force + wind_load
    scale = 0.12
    windward(side) = -sign(total.side) * side / 1e3
    rudder = WindShipOpt.rudder_side_force(hull, total)
    _, leeway_drag = WindShipOpt.leeway_drag(hull, env, speed, abs(total.side + rudder))
    rudder_drag = WindShipOpt.HullBalance(ship, speed, total).drag - leeway_drag
    resistance = WindShipOpt.resistance(hull, env, speed;
        coefficients=ship.wave_coefficients)
    bow, stern, side = hull.length / 2, -hull.length / 2, hull.beam / 2
    water = style_colour("water")
    poly!(axis, rotated.(hull_outline(hull.length, hull.beam), π / 2);
        color=style_colour("ship"), strokecolor=:black, strokewidth=rule_width)
    draw_rig!(axis, ship.rig, ship, (speed, wind, angle), colour)
    rudder_tip = stern - 6
    lines!(axis, [Point2f(stern, 0), Point2f(rudder_tip, 0)]; color=:black,
        linewidth=pt(1.5))
    arrows = (
        force_arrow!(axis, (force.yaw_moment / force.side, 0),
            (force.thrust / 1e3, windward(force.side)), "rig"; scale, color=colour,
            align=(:left, :top)),
        force_arrow!(axis, (wind_load.yaw_moment / wind_load.side, side),
            (wind_load.thrust / 1e3, windward(wind_load.side)), "wind load"; scale,
            color=style_colour("wind"), push=true, align=(:right, :center)),
        force_arrow!(axis, (WindShipOpt.lateral_centre(hull), 0),
            (-leeway_drag / 1e3, windward(-total.side - rudder)), "hull"; scale,
            color=water, align=(:left, :bottom)),
        force_arrow!(axis, (rudder_tip, 0), (-rudder_drag / 1e3, windward(rudder)),
            "rudder"; scale, color=water, align=(:right, :center)),
        force_arrow!(axis, (stern, 0), (thrust / 1e3, 0.0), "propeller"; scale,
            color=water, align=(:right, :top), at_point=true),
        force_arrow!(axis, (bow, 0), (-resistance / 1e3, 0.0), "calm water"; scale,
            color=water, push=true, align=(:left, :center)))
    return vcat(Point2f(0, side), Point2f(0, -side), arrows...)
end

"""
    draw_rig!(axis, rig, ship, (speed, wind, angle), colour)

Plan view of `rig` on `ship`, bow to the right, in `colour`, at the ship `speed` [m/s] in
the true `wind` [m/s] from `angle` [rad] off the bow, coming from above: a kite's tow
point, rotors as circles, and wings as their chords along the apparent wind at their mid
height.
"""
draw_rig!(axis, rig::KiteRig, ship, conditions, colour) =
    scatter!(axis, [Point2f(rig.attach_position, 0)]; color=colour, markersize=marker_size)

function draw_rig!(axis, rig::WingRig, ship, (speed, wind, angle), colour)
    chord = rig.height / assumptions[:wing_aspect_ratio]
    _, _, apparent = WindShipOpt.centre_wind(rig, ship.env, wind, angle, speed)
    along = chord / 2 * Vec2f(cos(apparent), sin(apparent))
    for position in WindShipOpt.unit_positions(rig, ship.hull, assumptions)
        lines!(axis, [Point2f(position, 0) - along, Point2f(position, 0) + along];
            color=colour, linewidth=pt(2.5))
    end
end

function draw_rig!(axis, rig::WindShipOpt.RotorRig, ship, conditions, colour)
    for position in WindShipOpt.unit_positions(rig, ship.hull, assumptions)
        poly!(axis, Circle(Point2f(position, 0), rig.diameter / 2); color=colour)
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

Side view of `hull` shifted by `offset` [m]: hull and a deckhouse aft, 10 m tall at the
reference length, with the deck at the height above the waterline at which the model
stands rigs on it.
"""
function draw_ship!(axis, hull, offset)
    scale = hull.length / assumptions[:reference_length]
    deck = assumptions[:deck_mount_height] * scale
    house = 10.0scale
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
                    rig.foot_height), Vec2f(width, rig.height));
            color=palette[rig isa WingRig ? 2 : 3],
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
    mast_top = deck + WindShipOpt.launch_mast_height(area, assumptions)
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
    lines!(axis, arc; color=palette[1], linewidth=2)
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
    gap = 0.22longest
    rows = [(name, Hull(classes[name], assumptions), [mean_best_area(table, name,
        routes_seen, kind) for kind in rig_names]) for name in names]
    kite_tops = [draw_height(hull, first(areas)) for (_, hull, areas) in rows]
    margin = 55.0
    tops = cumsum([kite_top + hull.draft + margin
                   for (kite_top, (_, hull, _)) in zip(kite_tops, rows)])
    width = 3longest + 2gap
    figure = Figure(size=(page_width, page_width * (last(tops) + 20) / (1.45width)))
    axis = Axis(figure[1, 1]; aspect=DataAspect())
    hidedecorations!(axis)
    hidespines!(axis)
    for (row, (name, hull, areas)) in enumerate(rows)
        y = -tops[row] + hull.draft + margin
        for (column, (kind, area)) in enumerate(zip(rig_names, areas))
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
                text=area_label(area), align=(:left, :top), offset=(0, -pt(2)),
                fontsize=note_size, color=:gray40)
        end
        text!(axis, -0.06longest, y; text=name, align=(:right, :center))
    end
    for (column, title) in enumerate(rig_label.(rig_names))
        text!(axis, (column - 1) * (longest + gap) + longest / 2, 10; text=title,
            align=(:center, :bottom))
    end
    bar = Point2f(-0.25width, -last(tops) + 10)
    lines!(axis, [bar, bar + Point2f(100, 0)]; color=:black, linewidth=1.5)
    text!(axis, bar + Point2f(50, 0); text="100 m", align=(:center, :bottom),
        offset=(0, 2), fontsize=note_size)
    limits!(axis, -0.36width, 1.02width, -last(tops) - 15, 80)
    save_figure("ship_classes", figure)
end

"`area` [m^2] as a LaTeX label to three significant digits, its digits grouped"
area_label(area) =
    L"%$(digit_groups(string(Int(round(area; sigdigits=3)))))\,\mathrm{m^2}"

"""
    mean_best_area(table, class, routes, rig)

Geometric mean over `routes` of the best area [m^2] of `rig` on `class` on VLSFO in the
class study `table`, or NaN where it has none.
"""
function mean_best_area(table, class, routes, rig)
    areas = filter(isfinite, [best_area(table, class, route, "vlsfo", rig)
                              for route in routes])
    return isempty(areas) ? NaN : geometric_mean(areas)
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
    figure = Figure(size=(page_width, 135))
    titles = ("(a) looking downwind", "(b) from the side", "(c) from above")
    axes = [Axis(figure[1, k]; autolimitaspect=1, title) for (k, title) in
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
    save_figure("kite_frames", figure)
end

"point at `radius` and `angle` [rad] from the +x axis of a figure, counterclockwise"
polar_point(radius, angle) = Point2f(radius * cos(angle), radius * sin(angle))

"""
    small_arrow!(axis, origin, vector, label; color, align)

A thin arrow of `vector` from `origin` with `label` at its tip.
"""
function small_arrow!(axis, origin, vector, label; color=:black, align=(:left, :center))
    arrows2d!(axis, [Point2f(origin)], [Vec2f(vector)]; color, shaftwidth=flow_width)
    text!(axis, Point2f(origin) + Vec2f(vector); text=label, align,
        offset=clear_offset(align, pt(2)), color)
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
        length=30)]); color=(palette[1], 0.15))
    lowest = sind(assumptions[:kite_min_elevation])
    for polar in (30, 60)
        radius = sind(polar)
        lines!(axis, [window_point(radius, roll) for roll in range(π / 2, π; length=30)];
            color=:gray70, linewidth=0.5)
        text!(axis, radius, 0; text=polar == 30 ? L"\itvartheta = 30°" : L"60°",
            align=(:center, :top),
            offset=clear_offset((:center, :top), pt(2)), fontsize=note_size,
            color=:gray50)
    end
    lines!(axis, [window_point(1, roll) for roll in range(0, π; length=90)];
        color=:black)
    poly!(axis, Point2f[(-sqrt(1 - lowest^2), lowest), (sqrt(1 - lowest^2), lowest),
        (1, 0), (-1, 0)]; color=(:gray50, 0.3))
    lines!(axis, Point2f[(-1.15, 0), (1.15, 0)]; color=:black, linewidth=0.6)
    text!(axis, window_point(1, deg2rad(130)); text="edge of\nthe window",
        align=(:left, :bottom), offset=(2, 0), fontsize=note_size)
    text!(axis, 1.07, lowest;
        text="below $(round(Int, assumptions[:kite_min_elevation]))°",
        align=(:left, :center), fontsize=note_size, color=:gray40)
    polar, roll = deg2rad(33), deg2rad(62)
    kite = window_point(sin(polar), roll)
    lines!(axis, [Point2f(0, 0), kite]; color=:gray50, linewidth=0.6, linestyle=:dash)
    lines!(axis, [window_point(0.3, angle) for angle in range(0, roll; length=20)];
        color=category_colours[2])
    text!(axis, window_point(0.37, 0.6roll); text=L"\itphi", align=(:right, :center),
        color=category_colours[2])
    outward = Vec2f(kite / hypot(kite...))
    along = Vec2f(outward[2], -outward[1])
    heading = deg2rad(65)
    small_arrow!(axis, kite, 0.3outward, L"\hat{\mathbf{e}}_\itvartheta";
        align=(:right, :center))
    small_arrow!(axis, kite, 0.3along, L"\hat{\mathbf{e}}_\itphi"; align=(:left, :center))
    small_arrow!(axis, kite, 0.32 * (cos(heading) * outward + sin(heading) * along),
        L"\hat{\mathbf{h}}"; color=palette[6], align=(:center, :bottom))
    lines!(axis, [kite + 0.12 * (cos(angle) * outward + sin(angle) * along)
                  for angle in range(0, heading; length=12)]; color=palette[6])
    text!(axis, kite + 0.2 * (cos(heading / 2) * outward + sin(heading / 2) * along);
        text=L"\itpsi", align=(:center, :center), color=palette[6])
    scatter!(axis, [kite]; color=palette[1], markersize=8)
    small_arrow!(axis, (1.5, 0.28), (-0.2, 0), L"y"; align=(:right, :bottom))
    small_arrow!(axis, (1.5, 0.28), (0, 0.2), L"z"; align=(:center, :bottom))
    limits!(axis, -1.2, 1.6, -0.16, 1.12)
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
    small_arrow!(axis, (0.55, -0.15), (0.45, 0), ""; align=(:left, :center))
    text!(axis, 0.75, -0.18; text="apparent wind", align=(:center, :top),
        fontsize=note_size)
    small_arrow!(axis, (-0.55, 0.45), (0.2, 0), L"x"; align=(:left, :center))
    small_arrow!(axis, (-0.55, 0.45), (0, 0.2), L"z"; align=(:center, :bottom))
    polar = deg2rad(50)
    kite = polar_point(1, polar)
    lines!(axis, [Point2f(0, 0), kite]; color=palette[1], linewidth=1.5)
    scatter!(axis, [kite]; color=palette[1], markersize=8)
    text!(axis, kite / 2; text=L"r\,\hat{\mathbf{e}}_r", align=(:right, :bottom),
        offset=clear_offset((:right, :bottom), pt(2)), color=palette[1])
    lines!(axis, [polar_point(0.3, angle) for angle in range(0, polar; length=20)];
        color=category_colours[2])
    text!(axis, polar_point(0.36, polar / 2); text=L"\itvartheta", align=(:left, :center),
        color=category_colours[2])
    scatter!(axis, [Point2f(0, 0)]; color=:black, markersize=4)
    text!(axis, 0, 0; text="tow point", align=(:center, :top),
        offset=clear_offset((:center, :top), pt(3)), fontsize=note_size)
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
        length=60)]; color=(palette[1], 0.12), strokecolor=:black, strokewidth=0.6)
    arrows2d!(axis, [Point2f(0, 0)], [Vec2f(0, 1.2)]; color=:black, shaftwidth=flow_width)
    text!(axis, 0, 1.2; text="apparent downwind", align=(:left, :top),
        offset=clear_offset((:left, :center), pt(4)), fontsize=note_size)
    course = deg2rad(110)
    heading = Vec2f(sin(course), cos(course))
    poly!(axis, rotated.(hull_outline(0.36, 0.08) .- Point2f(0, 0.18), course);
        color=:gray80, strokecolor=:black, strokewidth=0.6)
    lines!(axis, [Point2f(0, 0), Point2f(1.25heading)]; color=:black, linestyle=:dash,
        linewidth=0.6)
    text!(axis, Point2f(1.25heading); text="course", align=(:left, :center),
        offset=clear_offset((:left, :center), pt(3)), fontsize=note_size)
    lines!(axis, [0.3Point2f(sin(angle), cos(angle)) for angle in range(0, course;
        length=30)]; color=category_colours[2])
    text!(axis, 0.36Point2f(sin(course / 2), cos(course / 2)); text=L"\chi",
        align=(:left, :bottom), color=category_colours[2])
    force = Vec2f(0.68, 0.3)
    along = sum(force .* heading) * heading
    arrows2d!(axis, [Point2f(0, 0)], [force]; color=palette[1], shaftwidth=force_width)
    text!(axis, Point2f(force); text=L"\overline{\,\mathbf{F}}", align=(:left, :bottom),
        offset=clear_offset((:left, :bottom), pt(2)), color=palette[1])
    for (vector, label, origin, inside) in (
        (along, L"F_\parallel", Point2f(0, 0), force),
        (force - along, L"F_\perp", Point2f(along), Point2f(0, 0)))
        arrows2d!(axis, [origin], [vector]; color=palette[6], shaftwidth=force_width)
        normal = Vec2f(vector[2], -vector[1]) / hypot(vector...)
        middle = origin + 0.75vector
        outward = sum(normal .* (inside - middle)) > 0 ? -normal : normal
        text!(axis, middle + 0.15outward; text=label, align=(:center, :center),
            color=palette[6])
    end
    limits!(axis, -1.1, 1.7, -0.75, 1.3)
end
