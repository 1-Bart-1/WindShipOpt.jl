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
    calm = WindShipOpt.resistance(hull, env, speed; coefficients=ship.wave_coefficients)
    balance = WindShipOpt.HullBalance(ship, speed, total, calm + waves)
    stern = -hull.length / 2
    centre = balance.lateral_centre
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
function kilonewtons_text(value)
    kilonewtons = abs(value) / 1e3
    kilonewtons < 0.5 && return "0"
    kilonewtons < 9.95 && return @sprintf("\\SI{%.1f}{kN}", kilonewtons)
    return @sprintf("\\SI{%.0f}{kN}", kilonewtons)
end

"TikZ text of the label of `force`: its symbol and value as an equation"
force_label(force) =
    "\$" * force.symbol * " = " * kilonewtons_text(force.along + force.across) * "\$"

"millimetres per kilonewton and per metre at which [`force_balance_figure`](@ref) draws"
force_balance_scale = (force=0.1, length=0.5)

"the sections of the paper that give the forces drawn in each colour"
force_sections = Dict("water" => raw"\S\ref{sec:ships}, \S\ref{sec:balance}",
    "wind" => raw"\S\ref{sec:ships}", "kite" => raw"\S\ref{sec:kite}",
    "wings" => raw"\S\ref{sec:deck_rigs}", "rotors" => raw"\S\ref{sec:deck_rigs}")

"estimated width [mm] of a force label in [`force_balance_figure`](@ref)"
label_width = 13.0

"distance [mm] between the labels of a column in [`force_balance_figure`](@ref)"
label_pitch = 3.4

"""
sizes [m] of the rig pictures of paper/figure_pics.tex that [`force_balance_figure`](@ref)
scales: the wing sail's chord and the rotor's diameter
"""
picture_sizes = (wing_chord=14.1, rotor_diameter=5.78)

"half the beam [mm] of the ship as [`force_balance_figure`](@ref) draws it"
half_beam() = paper_ship.half_beam * force_balance_scale.length

"""
    force_balance_figure()

Write paper/figures/force_balance.tex: the [`horizontal_forces`](@ref) on the 140 m ship at
10.5 kn in a 10 m/s beam wind and calm water, seen from above with the bow up, for a kite,
wing sails and rotors at their best trim, ship and rig to scale and the forces to one
scale, with a key; error unless each set [`check_balance`](@ref)s.
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
    top = maximum(panel_top, panels)
    bottom = minimum(panel -> resistance_end(panel.ship, panel.forces), panels)
    write_whole(joinpath(figures, "force_balance.tex")) do io
        println(io, "% Written by the force_balance step of scripts/paper.jl.")
        println(io, raw"\begin{tikzpicture}[x=1mm, y=1mm]")
        left = 0.0
        for (i, panel) in enumerate(panels)
            windward, leeward = across_extent(panel)
            left += windward
            draw_force_panel(io, panel, left, top, 'a' + i - 1)
            left += leeward + 3
        end
        force_balance_key(io, 0.0, bottom - 4.5)
        println(io, raw"\end{tikzpicture}")
    end
end

"""
    panel_top(panel)

Height [mm] above midship that the bow, the arrows, their labels and the tether of
`panel` reach in [`force_balance_figure`](@ref).
"""
function panel_top(panel)
    heads = [arrow_ends(force)[2][2] for force in panel.forces]
    labels = [label_top(force, panel.forces) for force in panel.forces]
    return max(maximum(heads), maximum(labels),
        paper_ship.stem * force_balance_scale.length,
        tether_end(panel.ship.rig, panel.forces)[2])
end

"""
    label_top(force, forces)

Height [mm] of the top of the label of `force` among `forces` from its
[`label_place`](@ref): a label's pitch above a south anchor, half of it above a centred one.
"""
function label_top(force, forces)
    anchor, (_, level) = label_place(force, forces)
    startswith(anchor, "north") && return level
    return level + (startswith(anchor, "south") ? label_pitch : label_pitch / 2)
end

"""
    across_extent(panel)

Room [mm] that `panel` of [`force_balance_figure`](@ref) takes to windward and to leeward
of its centreline: its arrows across the ship, the labels beside them and beside the hull,
the wind and the tether.
"""
function across_extent(panel)
    reach(sign) = maximum(panel.forces) do force
        head = force.across / 1e3 * force_balance_scale.force
        sign * head <= 0 && return 0.0
        return abs(head) + (label_past_head(force, panel.forces) ? label_width + 1 : 0)
    end
    wind_label = 5.0 - first(apparent_wind_arrow(panel.conditions)[1])
    windward = max(reach(-1), half_beam() + 0.8 + label_width, wind_label)
    tether = first(tether_end(panel.ship.rig, panel.forces)) + 9
    leeward = max(reach(1), 1.4 + label_width, tether)
    return windward, leeward
end

"""
    draw_force_panel(io, panel, centreline, top, letter)

Write to `io` the TikZ panel `letter` of [`force_balance_figure`](@ref) for `panel`, its
centreline at `centreline` [mm]: the ship and rig from above to scale, the apparent wind,
each force labelled with its symbol and value, and the title with the leeway and heel at
height `top` [mm].
"""
function draw_force_panel(io, panel, centreline, top, letter)
    (; rig, area, ship, forces, leeway, heel, conditions) = panel
    println(io, "\\begin{scope}[shift={(", @sprintf("%.2f", centreline), ",0)}]")
    @printf(io, "\\begin{scope}[rotate=90, scale=%.3f, transform shape]\n",
        force_balance_scale.length)
    println(io, "\\pic {ship above};")
    println(io, "\\pic {rudder above};")
    draw_plan_rig(io, ship.rig, ship, conditions)
    println(io, "\\end{scope}")
    draw_apparent_wind(io, conditions)
    draw_plan_tether(io, ship.rig, forces, rig)
    for force in forces
        is_resistance(force) || draw_force(io, force, forces)
    end
    draw_resistances(io, forces, stern(ship))
    @printf(io, "\\node[panel, anchor=south west] at %s {(%c) %s, \\SI{%d}{m^2}};\n",
        tikz_point(-12, top + 6), letter, uppercasefirst(rig_label(rig)), round(Int, area))
    @printf(io, "\\node[note, anchor=south west] at %s {leeway \$\\beta = \\SI{%.1f}{\
        \\degree}\$, heel \$\\phi = \\SI{%.1f}{\\degree}\$};\n",
        tikz_point(-12, top + 2), rad2deg(leeway), rad2deg(heel))
    println(io, "\\end{scope}")
end

"""
    draw_apparent_wind(io, conditions)

Write to `io` the arrow of the [`apparent_wind_arrow`](@ref) of `conditions`, labelled.
"""
function draw_apparent_wind(io, conditions)
    tail, head = apparent_wind_arrow(conditions)
    println(io, "\\draw[flow, wind] ", tikz_point(tail...), " -- ", tikz_point(head...),
        ";")
    println(io, "\\node[label, wind, anchor=south, align=center] at ",
        tikz_point((tail .+ (0, 0.5))...), " {apparent\\\\wind};")
end

"""
    apparent_wind_arrow((speed, wind, angle))

Tail and head [mm] of the arrow of the apparent wind at 10 m height at the ship `speed`
[m/s] in the true `wind` [m/s] from `angle` [rad] off the bow, blowing from port, its head
beside the hull.
"""
function apparent_wind_arrow((speed, wind, angle))
    _, apparent = WindShipOpt.apparent_wind(wind, angle, speed)
    towards = apparent - π / 2
    head = (-half_beam() - 1.5, 6.0)
    return head .- 9 .* (cos(towards), sin(towards)), head
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
[`force_balance_figure`](@ref), where it acts: an arrow from its [`arrow_ends`](@ref), a
dot where that is shorter than an arrowhead and a ring where the force is zero.
"""
function draw_force(io, force, forces)
    tail, head = arrow_ends(force)
    mark = mark_style(force)
    if mark == :ring
        println(io, "\\draw[", force.colour, ", fill=white, line width=", tex_size("rule"),
            "] ", tikz_point(tail...), " circle (0.6);")
    elseif mark == :dot
        println(io, "\\filldraw[", force.colour, ", draw=white, line width=",
            tex_size("rule"), "] ", tikz_point(tail...), " circle (0.7);")
    else
        println(io, "\\draw[force, ", force.colour, "] ", tikz_point(tail...), " -- ",
            tikz_point(head...), ";")
    end
    anchor, at = label_place(force, forces)
    println(io, "\\node[note, text=", force.colour, "text, anchor=", anchor, "] at ",
        tikz_point(at...), " {", force_label(force), "};")
end

"""
    mark_style(force)

How [`draw_force`](@ref) marks `force`: `:ring` where it is zero, `:dot` where its arrow
would be shorter than an arrowhead, else `:arrow`.
"""
function mark_style(force)
    value = abs(force.along + force.across)
    value < 500 && return :ring
    value / 1e3 * force_balance_scale.force < arrowhead_length() && return :dot
    return :arrow
end

"""
    label_past_head(force, forces)

Whether the label of the force across the ship `force` among `forces` stands past the
head of its arrow, which it does where the arrow is shorter than its label and no other
force across the ship to the same side acts within two labels' height.
"""
function label_past_head(force, forces)
    iszero(force.across) && return false
    beside(force, forces) === nothing || return false
    return abs(force.across) / 1e3 * force_balance_scale.force < label_width + 1
end

"""
    beside(force, forces)

The other force of `forces` across the ship to the same side as `force` whose point lies
within two labels' height of its point, or `nothing`.
"""
function beside(force, forces)
    iszero(force.across) && return nothing
    for other in forces
        (other === force || iszero(other.across)) && continue
        sign(other.across) == sign(force.across) || continue
        abs(other.at - force.at) * force_balance_scale.length < 2label_pitch &&
            return other
    end
    return nothing
end

"""
    label_place(force, forces)

Anchor and point [mm] of the label of `force` among `forces`. Across the ship: past the
head of an arrow shorter than its label, else against the hull above the arrow, or below
it where another force across to the same side acts just forward, or, with none such,
where a force along the ship leaves the same point or has its label beside that place,
then a label's pitch below that label.
Along the ship: to windward of the hull at its [`along_label_level`](@ref).
"""
function label_place(force, forces)
    tail, head = arrow_ends(force)
    iszero(force.across) &&
        return "east", (-half_beam() - 0.8, along_label_level(force, forces))
    side = sign(force.across)
    towards = side > 0 ? "west" : "east"
    label_past_head(force, forces) && return towards, head .+ (side * 0.8, 0.0)
    other = beside(force, forces)
    thrust_here = any(forces) do other
        other.along > 0 &&
            abs(other.at - force.at) * force_balance_scale.length < label_pitch
    end
    levels = [along_label_level(other, forces) for other in forces
              if side < 0 && iszero(other.across) && !is_resistance(other)]
    clash = filter(level -> abs(level - (head[2] + 0.7 + label_pitch / 2)) < label_pitch,
        levels)
    below = other === nothing ? thrust_here || !isempty(clash) : other.at > force.at
    level = below ? min(head[2] - 0.7, minimum(clash; init=Inf) - label_pitch) :
            head[2] + 0.7
    return (below ? "north " : "south ") * towards, (side * (half_beam() + 0.8), level)
end

"""
    along_label_level(force, forces)

Height [mm] of the label of the force along the ship `force` among `forces`: level with the
head of its arrow, or just above a mark, and just below the arrow of a force across the
ship to windward that would run through it.
"""
function along_label_level(force, forces)
    tail, head = arrow_ends(force)
    level = mark_style(force) == :arrow ? head[2] - 2 : tail[2] + 1.8
    for other in forces
        other.across < 0 || continue
        arrow = first(arrow_ends(other))[2]
        abs(arrow - level) < label_pitch / 2 && (level = arrow - label_pitch / 2 - 0.5)
    end
    return level
end

"""
    draw_resistances(io, forces, stern)

Write to `io` the resistances among `forces`, the forces aft along the ship, end to end aft
of the rudder at `stern` [mm], the largest first, each in its colour, and their labels in a
column to leeward; a zero resistance has its label alone.
"""
function draw_resistances(io, forces, stern)
    resistances = sort(filter(is_resistance, forces); by=force -> force.along)
    start, levels = stern, Float64[]
    for (i, force) in enumerate(resistances)
        reach = force.along / 1e3 * force_balance_scale.force
        last = i == length(resistances) || abs(resistances[i + 1].along) < 500
        if abs(force.along) >= 500
            println(io, "\\draw[force, ", last ? "" : "-, ", force.colour, "] ",
                tikz_point(0, start), " -- ", tikz_point(0, start + reach), ";")
        end
        push!(levels, start + reach / 2)
        start += reach
    end
    for i in reverse(eachindex(levels))[2:end]
        levels[i] = max(levels[i], levels[i + 1] + label_pitch)
    end
    for (force, level) in zip(resistances, levels)
        println(io, "\\node[note, text=", force.colour, "text, anchor=west] at ",
            tikz_point(1.4, level), " {", force_label(force), "};")
    end
end

"whether `force` is a resistance, which the thrust equation names \$R\$"
is_resistance(force) = startswith(force.symbol, "R_")

"distance [mm] below midship of the rudder of `ship` in [`force_balance_figure`](@ref)"
stern(ship) = -ship.hull.length / 2 * force_balance_scale.length

"""
    resistance_end(ship, forces)

Height [mm] at which the resistances among `forces` on `ship`, end to end aft of its rudder
as [`draw_resistances`](@ref) draws them, end.
"""
function resistance_end(ship, forces)
    resistance = sum(force.along for force in forces if is_resistance(force))
    return stern(ship) + resistance / 1e3 * force_balance_scale.force
end

"""
    tether_end(rig, forces)

End [mm] of the stretch of a kite's tether that [`force_balance_figure`](@ref) draws from
its tow point along the pull of its `forces`; the tow point of a rig without a tether.
"""
tether_end(rig, forces) = (0.0, 0.0)

function tether_end(rig::KiteRig, forces)
    rig_force(symbol) = only(force for force in forces if force.symbol == symbol)
    pull = (rig_force(raw"F_y").across, rig_force(raw"F_x").along)
    return (0.0, rig.attach_position * force_balance_scale.length) .+
           24 .* pull ./ hypot(pull...)
end

"""
    draw_plan_tether(io, rig, forces, name)

Write to `io` the tow point of a kite `rig` and its tether along the pull of its `forces`
to its [`tether_end`](@ref), in the colour of its `name`; nothing for another rig.
"""
draw_plan_tether(io, rig, forces, name) = nothing

function draw_plan_tether(io, rig::KiteRig, forces, name)
    point = (0.0, rig.attach_position * force_balance_scale.length)
    println(io, "\\draw[", name, ", densely dashed, line width=", tex_size("dimension"),
        "] ", tikz_point(point...), " -- ", tikz_point(tether_end(rig, forces)...),
        " node[label, text=", name, "text, anchor=south west] {to kite};")
    println(io, "\\fill[", name, "] ", tikz_point(point...), " circle (0.9);")
end

"""
    draw_plan_rig(io, rig, ship, (speed, wind, angle))

Write to `io` the deck rig `rig` of `ship` from above, in metres with the bow along +x, at
the ship `speed` [m/s] in the true `wind` [m/s] from `angle` [rad] off the bow: rotors as
the figure style draws them and wing sails with their chords along the apparent wind at
mid height; nothing for a kite.
"""
draw_plan_rig(io, rig::KiteRig, ship, conditions) = nothing

function draw_plan_rig(io, rig::WingRig, ship, (speed, wind, angle))
    chord = rig.area / rig.height
    _, _, apparent = WindShipOpt.centre_wind(rig, ship.env, wind, angle, speed)
    for (position, offset) in WindShipOpt.unit_positions(rig, ship.hull, assumptions)
        @printf(io, "\\pic[rotate=%.2f, scale=%.3f] at (%.2f,%.2f) {wing above};\n",
            rad2deg(apparent), chord / picture_sizes.wing_chord, position, -offset)
    end
end

function draw_plan_rig(io, rig::WindShipOpt.RotorRig, ship, conditions)
    for (position, offset) in WindShipOpt.unit_positions(rig, ship.hull, assumptions)
        @printf(io, "\\pic[scale=%.3f] at (%.2f,%.2f) {rotor above};\n",
            rig.diameter / picture_sizes.rotor_diameter, position, -offset)
    end
end

"""
    force_balance_key(io, left, top)

Write to `io` the key of [`force_balance_figure`](@ref) in two rows, its top left corner at
`left`, `top` [mm]: the colour of the forces of the water, of the wind on the ship and of
each rig with their sections, and the scales of force and length.
"""
function force_balance_key(io, left, top)
    entries = [("water", "the water"), ("wind", "the wind on the ship"),
        ((rig, "the " * rig_label(rig)) for (rig, _) in trim_rigs)...]
    column, row_y = 40.0, row -> top - 2.5 - label_pitch * (row - 1)
    println(io, "\\begin{scope}[local bounding box=key]")
    for (i, (colour, text)) in enumerate(entries)
        x, y = left + 1.5 + column * mod(i - 1, 3), row_y(cld(i, 3))
        println(io, "\\draw[force, ", colour, "] ", tikz_point(x, y), " -- ",
            tikz_point(x + 5, y), ";")
        println(io, "\\node[note, anchor=west] at ", tikz_point(x + 5.5, y), " {", text,
            "\\inpaper{, ", force_sections[colour], "}};")
    end
    x, y = left + 1.5 + 2column, row_y(2)
    scale, metres = force_balance_scale.force, force_balance_scale.length
    @printf(io,
        "\\draw[|-|, line width=%s] %s -- %s node[note, anchor=west] {\\SI{100}{kN}};\n",
        tex_size("rule"), tikz_point(x, y), tikz_point(x + 100scale, y))
    @printf(io,
        "\\draw[|-|, line width=%s] %s -- %s node[note, anchor=west] {\\SI{20}{m}};\n",
        tex_size("rule"), tikz_point(x + 22, y), tikz_point(x + 22 + 20metres, y))
    println(io, "\\end{scope}")
    println(io, raw"\begin{scope}[on background layer]",
        raw"\node[legend box, fit=(key), inner sep=1.5pt] {};\end{scope}")
end

"""
    draw_ship!(axis, faces, offset)

The ship whose faces [`projected`](@ref) returns as `faces`, shifted by `offset` [m], each
face in its shade with a seam of the same colour.
"""
function draw_ship!(axis, faces, offset)
    polygons = [[Point2f(corner .+ offset) for corner in corners]
                for (corners, _, _) in faces]
    colours = [shaded(colour, brightness) for (_, colour, brightness) in faces]
    poly!(axis, polygons; color=colours, strokecolor=colours,
        strokewidth=pt(figure_style["sizes"]["seam"]))
end

"""
    draw_side_rig!(axis, rig, hull, form, offset)

Side view of the wing or rotor `rig` on `hull` of lines `form` shifted by `offset` [m]:
each unit as its height times its chord or diameter, standing at its foot height on a
foundation of its width from the deck below it.
"""
function draw_side_rig!(axis, rig, hull, form, offset)
    width = rig isa WingRig ? rig.area / rig.height : rig.diameter
    for (position, _) in WindShipOpt.unit_positions(rig, hull, assumptions)
        deck = deck_height(form, position)
        poly!(axis, Rect2f(Point2f(offset) + Point2f(position - width / 2, deck),
                Vec2f(width, max(rig.foot_height - deck, 0.0)));
            color=style_colour("ship"), strokewidth=0)
        poly!(axis, Rect2f(Point2f(offset) + Point2f(position - width / 2,
                    rig.foot_height), Vec2f(width, rig.height));
            color=rig_colour(deck_rig_name(rig)),
            strokewidth=0)
    end
end

"""
    side_kite(area, hull)

Heights [m] above the waterline and span [m] of the side view of a kite of projected
`area` [m^2] at the design aspect ratio on `hull`: its deck, launch mast top, the foot of
its control unit, drawn just above the mast, and the top of its canopy.
"""
function side_kite(area, hull)
    span = sqrt(area * design_aspect_ratio)
    deck = assumptions[:deck_mount_height] * hull.length / assumptions[:reference_length]
    mast_top = deck + WindShipOpt.launch_mast_height(area, assumptions)
    foot = mast_top + 20
    return (; span, deck, mast_top, foot, top=foot + last(kite_extent) * span)
end

"""
    draw_side_kite!(axis, area, hull, offset)

Side view of the kite of [`side_kite`](@ref) towed by `hull` shifted by `offset` [m]: its
launch mast at the towing point and the kite seen from ahead, to scale, on a tether not
drawn to length.
"""
function draw_side_kite!(axis, area, hull, offset)
    (; span, deck, mast_top, foot) = side_kite(area, hull)
    mast_foot = Point2f(offset) +
                Point2f(WindShipOpt.launch_mast_position(hull, assumptions), deck)
    mast = mast_foot + Point2f(0, mast_top - deck)
    lines!(axis, [mast_foot, mast]; color=:black, linewidth=1)
    kite_foot = Point2f(mast_foot[1], offset[2] + foot)
    lines!(axis, [mast, kite_foot]; color=:gray50, linewidth=0.6, linestyle=:dash)
    draw_kite!(axis, kite_foot, span)
end

"""
    draw_kite!(axis, foot, span; colour=style_colour("kite"))

Draw on `axis` the kite of [`kite_parts`](@ref) seen from ahead, `span` across in the
axis's units, the foot of its control unit at `foot`, in `colour`.
"""
function draw_kite!(axis, foot, span; colour=style_colour("kite"))
    for (class, subpaths) in kite_parts
        name, share, size = kite_part_styles[class]
        base = name == "rig" ? colour : name == "white" ? white : style_colour(name)
        tint = Makie.Colors.weighted_color_mean(share, base, white)
        for subpath in subpaths
            points = [Point2f(foot) + Point2f(x, -y) * span / 100
                      for (x, y) in polyline(subpath)]
            isnothing(size) ? poly!(axis, points; color=tint, strokewidth=0) :
            lines!(axis, points; color=tint, linewidth=style_size(size))
        end
    end
end

"""
    ship_classes_figure()

The standard ship classes in [`class_order`](@ref), side by side to one scale, each with the
geometric mean over the routes of the best size on VLSFO of each rig the class study holds,
laid out as the model lays them out.
"""
function ship_classes_figure()
    table = read_table(data_file("classes.csv"))
    names = class_order(table)
    classes = ship_classes()
    routes_seen = unique(table["route"])
    kinds = last.(study_rigs(table))
    longest = maximum(classes[name].length for name in names)
    gap = 0.22longest
    rows = [drawn_class(name, classes[name], table, routes_seen, kinds) for name in names]
    width = length(kinds) * longest + (length(kinds) - 1) * gap
    metres_per_unit = 1.45width / page_width
    margin = (pt(2) + line_height(note_size) + 3label_clearance) * metres_per_unit
    tops = cumsum([draw_height(hull, faces, first(areas), rigs) + hull.draft + margin
                   for (_, hull, _, faces, areas, rigs) in rows])
    top = 10 + (line_height(text_size) + 3label_clearance) * metres_per_unit
    bottom = -last(tops) - 15
    figure = Figure(size=(page_width, (top - bottom) / metres_per_unit))
    axis = Axis(figure[1, 1]; aspect=DataAspect())
    hidedecorations!(axis)
    hidespines!(axis)
    for (row, (name, hull, form, faces, areas, rigs)) in enumerate(rows)
        y = -tops[row] + hull.draft + margin
        for (column, (kind, area, rig)) in enumerate(zip(kinds, areas, rigs))
            offset = ((column - 1) * (longest + gap) + longest / 2, y)
            draw_ship!(axis, faces, offset)
            text!(axis, offset[1] - hull.length / 2, y - hull.draft;
                text=cell_label(kind, area, rig), align=(:left, :top),
                offset=(0, -pt(2)), fontsize=note_size, color=:gray40)
            isfinite(area) || continue
            if kind == "kite"
                draw_side_kite!(axis, area, hull, offset)
            else
                isnothing(rig) || draw_side_rig!(axis, rig, hull, form, offset)
            end
        end
        text!(axis, -0.09longest, y; text=name, align=(:right, :center))
    end
    for (column, title) in enumerate(rig_label.(kinds))
        centre = (column - 1) * (longest + gap) + longest / 2
        text!(axis, centre, 10; text=title, align=(:center, :bottom))
    end
    bar = Point2f(-0.25width, 10)
    lines!(axis, [bar, bar + Point2f(100, 0)]; color=:black, linewidth=1.5)
    text!(axis, bar + Point2f(50, 0); text="100 m", align=(:center, :bottom),
        offset=(0, 2), fontsize=note_size)
    limits!(axis, -0.36width, 1.02width, bottom, top)
    save_figure("ship_classes", figure)
end

"figure units of a line of text of `size`, from its lowest descender to its top"
line_height(size) =
    widths(Makie.text_bb("lg", Makie.to_font(paper_font("regular")), size))[2]

"""
    drawn_class(name, class, table, routes, kinds)

What [`ship_classes_figure`](@ref) draws of ship `class` called `name`: its hull, its lines,
their faces seen from the side, and the area of each rig of `kinds` of
[`mean_best_area`](@ref) over `routes` in `table` with the rig the model builds of it.
"""
function drawn_class(name, class, table, routes, kinds)
    areas = [mean_best_area(table, name, routes, kind) for kind in kinds]
    hull = Hull(class, assumptions)
    form = HullForm(hull, assumptions)
    check_drawn_hull(form, hull)
    faces = projected(ship_faces(form, hull, class.type), :side)
    return (name, hull, form, faces, areas, built_rig.(Ref(class), kinds, areas))
end

"""
    cell_label(kind, area, rig)

Label under a ship in [`ship_classes_figure`](@ref): the `area` [m^2] of rig `kind` to three
significant digits, its digits grouped, in parentheses where the model builds no deck `rig`
of it, or "no data yet" where the study has no area.
"""
function cell_label(kind, area, rig)
    isfinite(area) || return "no data yet"
    digits = digit_groups(string(Int(round(area; sigdigits=3))))
    built = kind == "kite" || !isnothing(rig)
    return built ? L"%$(digits)\,\mathrm{m^2}" : L"(%$(digits)\,\mathrm{m^2})"
end

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
    built_rig(class, kind, area)

Rig the model builds of `area` [m^2] of rig `kind` on a VLSFO ship of `class`, in the layout
it chooses; `nothing` for the kite, an area not searched or one that does not fit.
"""
function built_rig(class, kind, area)
    (kind == "kite" || !isfinite(area)) && return nothing
    ship = Ship(ShipDesign(:vlsfo, class; rig_size(kind, area)...), assumptions)
    return isnothing(ship) ? nothing : ship.rig
end

"""
    draw_height(hull, faces, kite_area, rigs)

Height [m] above the waterline of the top of what [`ship_classes_figure`](@ref) draws of
`hull`: its projected `faces`, the kite of `kite_area` [m^2] and the deck `rigs`.
"""
function draw_height(hull, faces, kite_area, rigs)
    tops = [maximum(last, corners) for (corners, _, _) in faces]
    append!(tops, rig.foot_height + rig.height for rig in rigs if !isnothing(rig))
    isfinite(kite_area) && push!(tops, side_kite(kite_area, hull).top)
    return maximum(tops; init=0.0)
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
        L"\hat{\mathbf{h}}"; color=style_colour("accent"), align=(:center, :bottom))
    lines!(axis, [kite + 0.12 * (cos(angle) * outward + sin(angle) * along)
                  for angle in range(0, heading; length=12)]; color=style_colour("accent"))
    text!(axis, kite + 0.2 * (cos(heading / 2) * outward + sin(heading / 2) * along);
        text=L"\itpsi", align=(:center, :center), color=style_colour("accent"))
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
        arrows2d!(axis, [origin], [vector]; color=style_colour("accent"),
            shaftwidth=force_width)
        normal = Vec2f(vector[2], -vector[1]) / hypot(vector...)
        middle = origin + 0.75vector
        outward = sum(normal .* (inside - middle)) > 0 ? -normal : normal
        text!(axis, middle + 0.15outward; text=label, align=(:center, :center),
            color=style_colour("accent"))
    end
    small_arrow!(axis, (1.35, 0.45), (0, 0.2), L"x"; align=(:center, :bottom))
    small_arrow!(axis, (1.35, 0.45), (-0.2, 0), L"y"; align=(:right, :center))
    limits!(axis, -1.7, 1.5, -0.75, 1.3)
end
