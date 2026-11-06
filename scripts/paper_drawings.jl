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
