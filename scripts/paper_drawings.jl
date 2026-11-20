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
    lever(force)

The distance [m] forward of midship at which the side force of `force` acts; error where
it has a yaw moment and no side force.
"""
function lever(force)
    iszero(force.side) || return force.yaw_moment / force.side
    iszero(force.yaw_moment) || error("a yaw moment without a side force has no lever")
    return 0.0
end

"""
    horizontal_forces(ship, rig, speed, wind, angle; waves=0.0)

Every horizontal force on `ship` with the `rig` of that name at `speed` [m/s] in the true
`wind` [m/s] from `angle` [rad] off the bow and the added resistance `waves` [N], at the
rig's best trim as the model solves it: each with the symbol of the thrust equation, its
component `along` the ship [N, forward] or `across` it [N, to leeward], the distance `at`
[m] forward of midship where it acts and its figure-style colour; with the leeway and heel
[rad] of that trim.
"""
function horizontal_forces(ship, rig, speed, wind, angle; waves=0.0)
    (; hull, env) = ship
    thrust, sail = WindShipOpt.best_trim(ship, ship.rig, speed, wind, angle, waves)
    air = WindShipOpt.wind_force(ship.windage, env, wind, angle, speed)
    total = sail + air
    balance = WindShipOpt.HullBalance(ship, speed, total)
    calm = WindShipOpt.resistance(hull, env, speed; coefficients=ship.wave_coefficients)
    stern = -hull.length / 2
    centre = WindShipOpt.lateral_centre(hull)
    force(symbol, along, across, at, colour) = (; symbol, along, across, at, colour)
    forces = [force(raw"F_x", sail.thrust, 0.0, lever(sail), rig),
        force(raw"F_y", 0.0, sail.side, lever(sail), rig),
        force(raw"R_\mathrm{air}", air.thrust, 0.0, lever(air), "wind"),
        force(raw"Y", 0.0, air.side, lever(air), "wind"),
        force(raw"R_\mathrm{cw}", -calm, 0.0, 0.0, "water"),
        force(raw"R_\mathrm{aw}", -waves, 0.0, 0.0, "water"),
        force(raw"R_\beta", -balance.leeway_drag, 0.0, centre, "water"),
        force(raw"Y_\mathrm{h}", 0.0, balance.hull_side_force, centre, "water"),
        force(raw"R_r", -balance.rudder_drag, 0.0, stern, "water"),
        force(raw"F_r", 0.0, balance.rudder_side_force, stern, "water"),
        force(raw"T_\mathrm{req}", thrust, 0.0, stern + propeller_ahead * hull.length,
            "water")]
    return (; forces, balance.leeway, balance.heel)
end

"share of the length by which [`force_balance_figure`](@ref) draws the propeller ahead of
the rudder"
propeller_ahead = 0.04

"""
    balance_sums(forces)

Sums of the `along` and `across` components [N] of `forces` and of their yaw moments
about midship [N m].
"""
balance_sums(forces) = (along=sum(force.along for force in forces),
    across=sum(force.across for force in forces),
    yaw=sum(force.across * force.at for force in forces))

"""
    check_balance(forces, name)

Error unless the forces, side forces and yaw moments of `forces` on the ship `name` sum to
zero within rounding; return their [`balance_sums`](@ref).
"""
function check_balance(forces, name)
    sums = balance_sums(forces)
    largest = maximum(force -> hypot(force.along, force.across), forces)
    longest = maximum(force -> abs(force.at), forces)
    tolerance = 1e-9largest
    abs(sums.along) < tolerance && abs(sums.across) < tolerance &&
        abs(sums.yaw) < tolerance * longest ||
        error(@sprintf(
            "forces on the %s do not balance: %.3g N along, %.3g N across, %.3g N m yaw",
            name, sums.along, sums.across, sums.yaw))
    return sums
end

"TikZ text of the point `x`, `y` [mm]"
tikz_point(x, y) = @sprintf("(%.2f,%.2f)", x, y)

"TikZ text of a force `value` [N] in kN, to the digits a figure label carries"
kilonewtons_text(value) = abs(value) < 500 ? "0" :
                          abs(value) < 9.95e3 ? @sprintf("%.1f\\,kN", abs(value) / 1e3) :
                          @sprintf("%.0f\\,kN", abs(value) / 1e3)

"millimetres per kilonewton and per metre at which [`force_balance_figure`](@ref) draws"
force_balance_scale = (force=0.1, length=0.5)

"the sections of the paper that give the forces drawn in each colour"
force_sections = Dict("water" => raw"\S\ref{sec:ships}, \S\ref{sec:balance}",
    "wind" => raw"\S\ref{sec:ships}", "kite" => raw"\S\ref{sec:kite}",
    "wings" => raw"\S\ref{sec:deck_rigs}", "rotors" => raw"\S\ref{sec:deck_rigs}")

"""
    force_balance_figure()

Write paper/figures/force_balance.tex: the [`horizontal_forces`](@ref) on the 140 m ship at
10.5 kn in a 10 m/s beam wind and calm water, seen from above with the bow up, for a kite,
wing sails and rotors at their best trim, each where it acts and all to one scale, with
the hull and rig to scale; error unless each set [`check_balance`](@ref)s.
"""
function force_balance_figure()
    speed, wind, angle = 10.5KNOT, 10.0, deg2rad(90)
    panels = map(collect(trim_rigs)) do (rig, area)
        ship = Ship(ShipDesign(:vlsfo, 140.0; rig_size(rig, area)...), assumptions)
        solution = horizontal_forces(ship, rig, speed, wind, angle)
        sums = check_balance(solution.forces, "ship with $(rig_label(rig))")
        @printf("%s: %.2g N along, %.2g N across, %.2g N m yaw\n", rig, sums...)
        (; rig, area, ship, solution..., conditions=(speed, wind, angle))
    end
    write_whole(joinpath(figures, "force_balance.tex")) do io
        println(io, "% Written by the force_balance step of scripts/paper.jl.")
        println(io, raw"\begin{tikzpicture}[x=1mm, y=1mm]")
        left = 0.0
        top = maximum(arrow_ends(force)[2][2] for panel in panels for force in panel.forces)
        for (i, panel) in enumerate(panels)
            low, high = across_extent(panel.forces)
            left -= low
            draw_force_panel(io, panel, left, top + 3, 'a' + i - 1)
            left += high + 4
        end
        stern = -maximum(panel.ship.hull.length for panel in panels) / 2
        force_balance_key(io, left - 4, stern * force_balance_scale.length - 6)
        println(io, raw"\end{tikzpicture}")
    end
end

"""
    across_extent(forces)

Least and greatest distance [mm] to leeward of the centreline that the across arrows of
`forces` reach in [`force_balance_figure`](@ref), with room for their labels.
"""
function across_extent(forces)
    reach = [force.across / 1e3 * force_balance_scale.force for force in forces]
    labelled = [abs(end_) < label_width ? end_ + sign(end_) * (label_width + 1) : end_
                for end_ in reach]
    return min(minimum(labelled), -label_width - 1), max(maximum(labelled), label_width + 1)
end

"""
    draw_force_panel(io, panel, centreline, top, letter)

Write to `io` the TikZ panel `letter` of [`force_balance_figure`](@ref) for `panel`, its
centreline at `centreline` [mm]: the hull and rig from above to scale, each force as an
arrow where it acts, labelled with its symbol and value, and its title with the leeway
and heel at height `top` [mm].
"""
function draw_force_panel(io, panel, centreline, top, letter)
    (; rig, area, ship, forces, leeway, heel, conditions) = panel
    metres = force_balance_scale.length
    println(io, "\\begin{scope}[shift={(", @sprintf("%.2f", centreline), ",0)}]")
    outline = hull_outline(ship.hull.length, ship.hull.beam)
    println(io, "\\filldraw[fill=ship, draw=black, line width=",
        tex_size("rule"), "] ", join((tikz_point(metres .* point...) for point in outline),
            " -- "), " -- cycle;")
    draw_plan_rig(io, ship.rig, ship, conditions, rig, forces)
    stern = -ship.hull.length / 2 * metres
    println(io, "\\fill[black] ", tikz_point(-0.25, stern - 1.5), " rectangle ",
        tikz_point(0.25, stern + 1), ";")
    for force in forces
        draw_force(io, force, forces)
    end
    @printf(io,
        "\\node[panel, anchor=south west] at %s {(%c) %s %d\\,m\\textsuperscript{2}};\n",
        tikz_point(-14, top + 4), letter, rig_label(rig), round(Int, area))
    @printf(io, "\\node[note, anchor=south west] at %s {leeway \$\\beta = %.1f^\\circ\$, \
        heel \$\\phi = %.1f^\\circ\$};\n",
        tikz_point(-14, top), rad2deg(leeway), rad2deg(heel))
    println(io, "\\end{scope}")
end

"""
    arrow_ends(force)

Tail and head [mm] of the arrow of `force` in [`force_balance_figure`](@ref): from its
point, on the centreline at its lever.
"""
function arrow_ends(force)
    across = !iszero(force.across)
    reach = (across ? (force.across, 0.0) : (0.0, force.along)) ./ 1e3 .*
            force_balance_scale.force
    point = (0.0, force.at * force_balance_scale.length)
    return point, point .+ reach
end

"length [mm] of an arrowhead of the figure style"
arrowhead_length() = figure_style["sizes"]["arrow_length"] * 25.4 / 72.27

"""
    draw_force(io, force, forces)

Write to `io` the mark and label of one of the [`horizontal_forces`](@ref) `forces` in
[`force_balance_figure`](@ref): an arrow from its [`arrow_ends`](@ref), a dot where that
is shorter than an arrowhead, nothing where the force is zero and another acts at its
point, which then names it too, and a ring where it is zero alone.
"""
function draw_force(io, force, forces)
    value = force.along + force.across
    tail, head = arrow_ends(force)
    sharing = [other for other in forces if other !== force && other.at == force.at &&
                   other.colour == force.colour &&
                   iszero(other.across) == iszero(force.across)]
    zero = abs(value) < 500
    zero && any(other -> abs(other.along + other.across) >= 500, sharing) && return
    point = (0.0, force.at * force_balance_scale.length)
    short = hypot((head .- tail)...) < arrowhead_length()
    if zero
        println(io, "\\draw[", force.colour, ", fill=white, line width=", tex_size("rule"),
            "] ", tikz_point(point...), " circle (0.6);")
    elseif short
        println(io, "\\filldraw[", force.colour, ", draw=white, line width=",
            tex_size("rule"), "] ", tikz_point(point...), " circle (0.7);")
    else
        println(io, "\\draw[force, ", force.colour, "] ", tikz_point(tail...), " -- ",
            tikz_point(head...), ";")
    end
    text = join((@sprintf("\$%s\$ %s", other.symbol,
        kilonewtons_text(other.along + other.across))
                 for other in [force; filter(other -> abs(other.along + other.across) < 500,
                     sharing)]), ", ")
    anchor, at = label_place(force, forces, tail, head, zero || short)
    println(io, "\\node[note, text=", force.colour, "text, anchor=", anchor, "] at ",
        tikz_point(at...), " {", text, "};")
end

"estimated width [mm] of a force label in [`force_balance_figure`](@ref)"
label_width = 13.0

"""
    label_place(force, forces, tail, head, mark)

Anchor and point [mm] of the label of `force` among `forces`, its arrow from `tail` to
`head` [mm] or a `mark` at its point: past the head of an across arrow shorter than a
label, else above its shaft near the head, or below either where another force acts just
above; beside an along arrow near its head or beside a mark, on the side no across arrow
from that point takes, windward by default.
"""
function label_place(force, forces, tail, head, mark)
    if !iszero(force.across) && !mark
        leeward = force.across > 0
        short = abs(head[1]) < label_width
        crowded = any(forces) do other
            other !== force && 0 < (other.at - force.at) * force_balance_scale.length < 5 &&
                (iszero(other.across) || sign(other.across) == sign(force.across))
        end
        crowded && short &&
            return "north " * (leeward ? "west" : "east"), head .+ (0.0, -0.5)
        short && return leeward ? "west" : "east", head .+ (leeward ? 0.8 : -0.8, 0.0)
        return (crowded ? "north" : "south") * (leeward ? " east" : " west"),
        head .+ (0.0, crowded ? -0.7 : 0.7)
    end
    windward_taken = any(other -> other.at == force.at && other.across < 0, forces)
    side = windward_taken ? 1.0 : -1.0
    anchor = windward_taken ? "west" : "east"
    shaft = head .- tail
    length = hypot(shaft...)
    at = mark ? tail : length > 6 ? head .- 3 .* shaft ./ length : (tail .+ head) ./ 2
    return anchor, at .+ (1.2side, 0.0)
end

"""
    draw_plan_rig(io, rig, ship, (speed, wind, angle), name, forces)

Write to `io` the plan view of `rig`, bow up, in the colour of its `name`, at the ship
`speed` [m/s] in the true `wind` [m/s] from `angle` [rad] off the bow: a kite's tow point
with its tether along the pull of its `forces`, rotors as circles, and wing sails as their
chords along the apparent wind at mid height.
"""
function draw_plan_rig(io, rig::KiteRig, ship, conditions, name, forces)
    point = (0.0, rig.attach_position * force_balance_scale.length)
    rig_force(symbol) = only(force for force in forces if force.symbol == symbol)
    pull = (rig_force(raw"F_y").across, rig_force(raw"F_x").along)
    reach = 30 .* pull ./ hypot(pull...)
    println(io, "\\draw[", name, ", densely dashed, line width=", tex_size("dimension"),
        "] ", tikz_point(point...), " -- ", tikz_point((point .+ reach)...),
        " node[note, text=", name, "text, anchor=south west] {tether};")
    println(io, "\\fill[", name, "] ", tikz_point(point...), " circle (0.9);")
end

function draw_plan_rig(io, rig::WingRig, ship, (speed, wind, angle), name, forces)
    chord = rig.height / assumptions[:wing_aspect_ratio] * force_balance_scale.length
    _, _, apparent = WindShipOpt.centre_wind(rig, ship.env, wind, angle, speed)
    along = chord / 2 .* (sin(apparent), -cos(apparent))
    for (position, offset) in WindShipOpt.unit_positions(rig, ship.hull, assumptions)
        centre = (offset, position) .* force_balance_scale.length
        println(io, "\\draw[", name, ", line width=", tex_size("line"), "] ",
            tikz_point((centre .- along)...), " -- ", tikz_point((centre .+ along)...), ";")
    end
end

function draw_plan_rig(io, rig::WindShipOpt.RotorRig, ship, conditions, name, forces)
    metres = force_balance_scale.length
    for (position, offset) in WindShipOpt.unit_positions(rig, ship.hull, assumptions)
        println(io, "\\fill[", name, "] ", tikz_point(offset * metres, position * metres),
            " circle (", @sprintf("%.2f", rig.diameter / 2 * metres), ");")
    end
end

"""
    force_balance_key(io, right, top)

Write to `io` the key of [`force_balance_figure`](@ref), its top right corner at `right`,
`top` [mm]: the colour of the forces of the water, of the wind on the ship and of each
rig with their sections, the dot of a force shorter than an arrowhead, and the scales of
force and length.
"""
function force_balance_key(io, right, top)
    scale, metres = force_balance_scale.force, force_balance_scale.length
    entry(colour, text) = (colour, text * "\\inpaper{, " * force_sections[colour] * "}")
    water = raw"water: $R_\mathrm{cw}$, $R_\mathrm{aw}$, $R_\beta$, $R_r$, " *
        raw"$T_\mathrm{req}$, $Y_\mathrm{h}$, $F_r$"
    columns = [(108.0, [entry("water", water),
            entry("wind", raw"wind on the ship: $R_\mathrm{air}$, $Y$")]),
        (42.0, [entry(rig, "\$F_x\$, \$F_y\$ of the " * rig_label(rig))
                for (rig, _) in trim_rigs])]
    row_y(row) = top - 2.5 - 3.6(row - 1)
    println(io, "\\begin{scope}[local bounding box=key]")
    for (from_right, entries) in columns, (row, (colour, text)) in enumerate(entries)
        x, y = right - from_right + 1.5, row_y(row)
        println(io, "\\draw[force, ", colour, "] ", tikz_point(x, y), " -- ",
            tikz_point(x + 5, y), ";")
        println(io, "\\node[note, anchor=west] at ", tikz_point(x + 5.5, y), " {", text,
            "};")
    end
    x, y = right - columns[1][1] + 1.5, row_y(length(last(columns[1])) + 1)
    println(io, "\\filldraw[black, draw=white, line width=", tex_size("rule"), "] ",
        tikz_point(x + 2.5, y), " circle (0.7);")
    @printf(io, "\\node[note, anchor=west] at %s {force under \\SI{%.0f}{kN}, its value \
        in the label};\n", tikz_point(x + 5.5, y), arrowhead_length() / scale)
    rows = maximum(length(last(column)) for column in columns)
    x, y = right - columns[1][1] + 1.5, row_y(rows + 1)
    @printf(io,
        "\\draw[|-|, line width=%s] %s -- %s node[note, anchor=west] {\\SI{100}{kN}};\n",
        tex_size("rule"), tikz_point(x, y), tikz_point(x + 100scale, y))
    @printf(io,
        "\\draw[|-|, line width=%s] %s -- %s node[note, anchor=west] {\\SI{20}{m}};\n",
        tex_size("rule"), tikz_point(x + 25, y), tikz_point(x + 25 + 20metres, y))
    println(io, "\\end{scope}")
    println(io, raw"\begin{scope}[on background layer]",
        raw"\node[legend box, fit=(key), inner sep=1.5pt] {};\end{scope}")
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
    for (position, _) in WindShipOpt.unit_positions(rig, hull, assumptions)
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
    foot = Point2f(offset) +
           Point2f(WindShipOpt.launch_mast_position(hull, assumptions), deck)
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
`hull`: the kite of `kite_area` [m^2], or the tallest deck rig built.
"""
function draw_height(hull, kite_area)
    scale = hull.length / assumptions[:reference_length]
    deck_rig = assumptions[:deck_mount_height] * scale +
               max(assumptions[:wing_max_height], assumptions[:rotor_max_height])
    isfinite(kite_area) || return deck_rig
    return max(side_kite(kite_area, hull).top, deck_rig)
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

"`point` turned counterclockwise by `angle` [rad] about the origin"
rotated(point, angle) = Point2f(point[1] * cos(angle) - point[2] * sin(angle),
    point[1] * sin(angle) + point[2] * cos(angle))

"""
    draw_course_plan!(axis)

Plan view of the wind window as a half disc downwind of the ship, apparent downwind up the
page and `y` to its left as in the wind frame, the ship's course `χ` off the apparent
downwind direction towards `y`, and the mean tether force with its components along and
across the course.
"""
function draw_course_plan!(axis)
    poly!(axis, [polar_point(1, angle) for angle in range(0, π; length=60)];
        color=(palette[1], 0.12), strokecolor=:black, strokewidth=0.6)
    arrows2d!(axis, [Point2f(0, 0)], [Vec2f(0, 1.2)]; color=:black, shaftwidth=flow_width)
    text!(axis, 0, 1.2; text="apparent downwind", align=(:left, :top),
        offset=clear_offset((:left, :center), pt(4)), fontsize=note_size)
    course = deg2rad(110)
    heading = Vec2f(polar_point(1, π / 2 + course))
    poly!(axis, rotated.(hull_outline(0.36, 0.08) .- Point2f(0, 0.18), course);
        color=:gray80, strokecolor=:black, strokewidth=0.6)
    lines!(axis, [Point2f(0, 0), Point2f(1.25heading)]; color=:black, linestyle=:dash,
        linewidth=0.6)
    text!(axis, Point2f(1.25heading); text="course", align=(:right, :center),
        offset=clear_offset((:right, :center), pt(3)), fontsize=note_size)
    lines!(axis, [polar_point(0.3, π / 2 + angle) for angle in range(0, course;
        length=30)]; color=category_colours[2])
    text!(axis, polar_point(0.36, π / 2 + 0.35course); text=L"\chi",
        align=(:right, :bottom), color=category_colours[2])
    force = Vec2f(-0.68, 0.3)
    along = sum(force .* heading) * heading
    arrows2d!(axis, [Point2f(0, 0)], [force]; color=palette[1], shaftwidth=force_width)
    text!(axis, Point2f(force); text=L"\overline{\,\mathbf{F}}", align=(:right, :bottom),
        offset=clear_offset((:right, :bottom), pt(2)), color=palette[1])
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
    small_arrow!(axis, (1.35, 0.45), (0, 0.2), L"x"; align=(:center, :bottom))
    small_arrow!(axis, (1.35, 0.45), (-0.2, 0), L"y"; align=(:right, :center))
    limits!(axis, -1.7, 1.5, -0.75, 1.3)
end
