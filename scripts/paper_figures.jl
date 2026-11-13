# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Figure steps of the paper: each saves one PDF to paper/figures/, from the CSV files of
# the run in use, the data in data/kite_polars/ or the model itself. Included by paper.jl.

figures = mkpath(joinpath(root, "paper", "figures"))
polars = joinpath(root, "data", "kite_polars")
aspect_ratios = (3, 5, 8)
"the paper's figure style: sizes [pt] and colours, shared with its TikZ figures"
figure_style = TOML.parsefile(joinpath(root, "paper", "figure_style.toml"))
"the colour `name` of [`figure_style`](@ref)"
style_colour(name) = parse(Makie.Colors.Colorant, "#" * figure_style["colours"][name])
"colours of the kite, wings and rotors, in the order of `rig_names`, then of the VTOL kite"
palette = style_colour.(["kite", "wings", "rotors", "vtol", "water", "accent"])
"colours of what is not a rig, none of them a rig's"
category_colours = [palette[6], Makie.RGBf(0.42, 0.26, 0.64), Makie.RGBf(0.55, 0.47, 0.0),
    palette[5], Makie.RGBf(0.55, 0.3, 0.12), :black]
"""
    figure_style_file()

Write [`figure_style`](@ref) to paper/figure_style.tex, which the paper and its extended
abstract load: figures keep their own fonts, TikZ and its libraries, the colours, and the TikZ styles of the LaTeX figures, `force`, `flow`, `dimension`, `leader`, `label`, `note` and
`box`, with the arrowhead every arrow shares; error on any [`tikz_style_faults`](@ref).
"""
function figure_style_file()
    faults = tikz_style_faults()
    isempty(faults) || error("TikZ figures set their own style:\n", join(faults, "\n"))
    sizes = figure_style["sizes"]
    size(name) = @sprintf("%gpt", sizes[name])
    font(name) = @sprintf("\\fontsize{%g}{%g}\\selectfont", sizes[name], 1.2sizes[name])
    open(joinpath(root, "paper", "figure_style.tex"), "w") do io
        println(io, "% Written by the figure_style step from figure_style.toml; edit that.")
        println(io, "\\pdfinclusioncopyfonts=1")
        println(io, "\\usepackage{xcolor}\n\\usepackage{tikz}")
        println(io, "\\usetikzlibrary{positioning,arrows.meta,fit}")
        for (name, hex) in sort(collect(figure_style["colours"]))
            println(io, "\\definecolor{", name, "}{HTML}{", hex, "}")
        end
        println(io, "\\tikzset{")
        println(io, "  >={Stealth[length=", size("arrow_length"), ", width=",
            size("arrow_width"), "]},")
        println(io, "  every picture/.style={line width=", size("rule"), "},")
        println(io, "  force/.style={->, line width=", size("force"), "},")
        println(io, "  flow/.style={->, line width=", size("flow"), "},")
        println(io, "  dimension/.style={<->, guide, line width=", size("dimension"), "},")
        println(io, "  leader/.style={guide, line width=", size("dimension"), "},")
        println(io, "  label/.style={font=", font("text"), ", inner sep=1pt, preaction={",
            "fill=white, draw=white, line width=", size("halo"), "}},")
        println(io, "  note/.style={label, font=", font("note"), "},")
        println(io, "  box/.style={draw, rounded corners=2pt, line width=", size("rule"),
            "},")
        println(io, "}")
    end
end

"""
    tikz_style_faults()

Lines of the TikZ figures in paper/sections that set a width, font size, colour or style
of their own rather than one of [`figure_style_file`](@ref): a colour mixed from one that
is not in [`figure_style`](@ref) counts, a tint of one that is does not.
"""
function tikz_style_faults()
    own = Regex(string("line width|\\b(ultra |very )?(thin|thick)\\b|semithick|/\\.style|",
        "\\\\(definecolor|colorlet|tiny|scriptsize|footnotesize|small)\\b"))
    mixed = r"([A-Za-z]+)!\d"
    faults = String[]
    for file in filter(endswith(".tex"), readdir(sections; join=true))
        text = read(file, String)
        occursin("tikzpicture", text) || continue
        for (number, line) in enumerate(split(text, '\n'))
            foreign = any(!haskey(figure_style["colours"], match[1])
                          for match in eachmatch(mixed, line))
            (occursin(own, line) || foreign) &&
                push!(faults, "$(basename(file)):$number: $(strip(line))")
        end
    end
    return faults
end

"`n` shades of the kite's blue, light to dark"
kite_shades(n) = cgrad(:Blues, n + 2; categorical=true)[3:end]
"`n` shades of the VTOL kite's pink, light to dark"
vtol_shades(n) = cgrad(:RdPu, n + 2; categorical=true)[3:end]
column_width = 334
page_width = 522
# points per figure unit, so that a page-wide figure is the 468 pt text width
print_scale = 468 / page_width
"figure units of a size [pt] as printed"
pt(size) = size / print_scale
"path of the paper's typeface, TeX Gyre Termes, in `style`"
paper_font(style) = joinpath(root, "data", "fonts", "texgyretermes-$style.otf")
Makie.MathTeXEngine.set_texfont_family!(Makie.MathTeXEngine.FontFamily(Dict(
    :regular => paper_font("regular"), :italic => paper_font("italic"),
    :bold => paper_font("bold"), :bolditalic => paper_font("bold"),
    :math => paper_font("math"))))
"figure units of the size `name` [pt] of [`figure_style`](@ref)"
style_size(name) = pt(figure_style["sizes"][name])
"figure units of the text in figures: labels, ticks, legends and panel titles"
text_size = style_size("text")
"figure units of secondary text: values written on the data and notes beside it"
note_size = style_size("note")
"figure units of the width of axis lines, ticks and frames"
rule_width = style_size("rule")
"figure units of the width of data lines"
line_width = style_size("line")
"figure units of the size of data markers"
marker_size = style_size("marker")
"figure units of the shaft of an arrow that draws a force"
force_width = style_size("force")
"figure units of the shaft of an arrow that links boxes or steps, or a unit vector"
flow_width = style_size("flow")
set_theme!(fontsize=text_size, linewidth=line_width, markersize=marker_size,
    figure_padding=(pt(3), pt(6), pt(3), pt(3)), rowgap=pt(8), colgap=pt(10),
    fonts=(; regular=paper_font("regular"), italic=paper_font("italic"),
        bold=paper_font("bold")),
    Axis=(; xgridvisible=false, ygridvisible=false,
        titlefont=:regular, titlealign=:left, titlegap=pt(3), spinewidth=rule_width,
        xtickwidth=rule_width, ytickwidth=rule_width, xticksize=pt(2.5),
        yticksize=pt(2.5), xlabelpadding=pt(2), ylabelpadding=pt(3)),
    Arrows2D=(; shaftwidth=line_width, tipwidth=style_size("arrow_width"),
        tiplength=style_size("arrow_length")),
    Colorbar=(; spinewidth=rule_width, tickwidth=rule_width, ticksize=pt(2.5)),
    Legend=(; backgroundcolor=:white, framecolor=:gray55, framewidth=rule_width,
        titlefont=:regular, patchsize=(pt(11), pt(6)), patchlabelgap=pt(3), rowgap=0,
        colgap=pt(7), titlegap=pt(2), groupgap=pt(5), padding=(pt(3), pt(3), pt(1.5),
            pt(1.5)), margin=(pt(3), pt(3), pt(3), pt(3))))
"""
    clear_offset(align, gap)

Offset [figure units] that moves text of `align` by `gap` away from its anchor, so that
it clears what ends there.
"""
clear_offset(align, gap) = (Dict(:left => gap, :center => 0, :right => -gap)[align[1]],
    Dict(:bottom => gap, :center => 0, :top => -gap)[align[2]])

"""
    estimate_text(value)

`value` as an estimate is written: to two significant digits, with no trailing zero.
"""
estimate_text(value) = @sprintf("%.15g", round(value; sigdigits=2))

"figure units of the halo in the background colour behind each dark label"
halo_width = style_size("halo")

"""
    save_figure(name, figure)

Save `figure` at print size to paper/figures/`name`.pdf, with a halo behind each dark label
in its axes; error if [`label_faults`](@ref) finds any.
"""
function save_figure(name, figure)
    Makie.colorbuffer(figure)
    faults = label_faults(figure)
    isempty(faults) || error("labels of figure $name: ", join(faults, "; "))
    foreach(add_halo!, axis_labels(figure))
    path = joinpath(figures, "$name.pdf")
    save(path, figure; pt_per_unit=print_scale)
    rename_font_subsets(path, name)
end

"""
    rename_font_subsets(path, name)

Give each font subset in the PDF at `path` a tag of its own, drawn from `name`: Cairo tags
the same subset alike in every figure, and a viewer then takes one figure's glyphs for
another's in the paper.
"""
function rename_font_subsets(path, name)
    pdf = read(path, String)
    tags = unique(match.match for match in eachmatch(r"/[A-Z]{6}\+", pdf))
    for tag in tags
        letters = string(hash((name, tag)); base=26, pad=6)[1:6]
        new = "/" * map(letter -> Char('A' + parse(Int, letter; base=26)), letters) * "+"
        pdf = replace(pdf, tag => new)
    end
    write(path, pdf)
end

"the text plots in the axes of `figure`, those of its legends and decorations left out"
axis_labels(figure) = [plot for block in figure.content if block isa Axis
                       for plot in block.scene.plots if plot isa Makie.Text]

"whether `label` is drawn in a dark colour, which a light halo sets off"
is_dark(label) = all(colour -> Makie.Colors.Gray(Makie.to_color(colour)).val < 0.6,
    label.color[] isa AbstractVector ? label.color[] : [label.color[]])

"""
    add_halo!(label)

Draw a copy of the text plot `label` beneath it in white with a white outline, above
every line and fill of its scene.
"""
function add_halo!(label)
    is_dark(label) || return
    halo = text!(Makie.parent_scene(label), label[1]; text=label.text, align=label.align,
        offset=label.offset, fontsize=label.fontsize, font=label.font,
        rotation=label.rotation, justification=label.justification,
        markerspace=label.markerspace, space=label.space, color=:white,
        strokecolor=:white, strokewidth=halo_width)
    translate!(halo, 0, 0, 1)
    translate!(label, 0, 0, 2)
end

"""
    label_faults(figure)

Descriptions of the labels in the axes of `figure` that overlap another label, run past
the edge of their axis, or lie over a line or marker of the data; `figure` laid out.
"""
function label_faults(figure)
    faults = String[]
    for block in figure.content
        block isa Axis || continue
        scene = block.scene
        width, height = widths(scene.viewport[])
        labels = [(text, box) for plot in scene.plots if plot isa Makie.Text
                  for (text, box) in zip(label_texts(plot),
            Makie.string_boundingboxes(plot)) if !isempty(text)]
        boxes = [Rect2f(Point2f(minimum(box)[1:2]), Vec2f(widths(box)[1:2]))
                 for (_, box) in labels]
        texts = first.(labels)
        for (i, box) in enumerate(boxes)
            inside = Rect2f(0, 0, width, height)
            in_axis(box, inside) || push!(faults, "\"$(texts[i])\" runs past its axis")
            for j in (i + 1):length(boxes)
                overlaps(box, boxes[j]) &&
                    push!(faults, "\"$(texts[i])\" overlaps \"$(texts[j])\"")
            end
            margin = Rect2f(minimum(box) .- label_clearance,
                widths(box) .+ 2label_clearance)
            for plot in scene.plots
                covers_data(scene, plot, margin) &&
                    push!(faults,
                        "\"$(texts[i])\" lies over a $(Makie.plotfunc(plot)) plot")
            end
        end
    end
    return unique(faults)
end

"the strings of the text plot `plot`, one per label"
label_texts(plot) = (text = plot.text[]; text isa AbstractVector ? string.(text) :
                                          [string(text)])

"clearance [figure units] a label keeps from other labels and from lines and markers"
label_clearance = style_size("clearance")

"whether the rectangles `a` and `b` come closer than [`label_clearance`](@ref)"
overlaps(a, b) = all(min.(maximum(a), maximum(b)) .- max.(minimum(a), minimum(b)) .>
                     -label_clearance)

"whether `box` lies within `inside`, to half a point"
in_axis(box, inside) = all(minimum(box) .>= minimum(inside) .- pt(0.5)) &&
                       all(maximum(box) .<= maximum(inside) .+ pt(0.5))

"""
    covers_data(scene, plot, box)

Whether `box` [pixels of `scene`] covers a vertex or crosses a segment of `plot`, when it
is a line or scatter plot of data.
"""
function covers_data(scene, plot, box)
    plot isa Union{Makie.Lines, Makie.Scatter, Makie.LineSegments, Makie.Arrows2D} ||
        return false
    data = plot isa Makie.Arrows2D ?
           [point for (tail, vector) in zip(plot[1][], plot[2][])
            for point in (tail, tail + vector)] : plot[1][]
    points = [Point2f(Makie.project(scene, :data, :pixel,
        Point3f(point[1], point[2], 0))[1:2]) for point in data]
    plot isa Makie.Scatter && return any(in(box), filter(point -> all(isfinite, point),
        points))
    steps = plot isa Union{Makie.LineSegments, Makie.Arrows2D} ?
            (1:2:(length(points) - 1)) :
            (1:(length(points) - 1))
    return any(segment_crosses(points[k], points[k + 1], box) for k in steps
               if all(isfinite, points[k]) && all(isfinite, points[k + 1]))
end

"whether the segment from `a` to `b` passes through `box`, sampled every half point"
function segment_crosses(a, b, box)
    samples = max(2, ceil(Int, hypot((b - a)...) / pt(0.5)))
    return any(in(a + (b - a) * (k / samples), box) for k in 0:samples)
end

"""
    square_metres(before, after="")

Rich text of `before`, m with a raised 2, and `after`: the unit square metre drawn from the
digit 2, as the font's own ² is lost where LaTeX swaps in its own copy of the font.
"""
square_metres(before, after="") = rich(before, "m", superscript("2"), after)

"`text` with each hyphen set as the minus sign, as the axes print negative numbers"
typeset_minus(text) = replace(text, "-" => "−")
"the [`study_drives`](@ref) with their names in figure labels"
drive_labels = [string(drive) => Dict(:vlsfo => "VLSFO", :ammonia => "e-ammonia")[drive]
                for drive in study_drives]
"(drive, panel title) of the panels (a), (b) of a figure with one panel per drive"
drive_panels = [(drive, "($(Char('a' + k - 1))) $label")
                for (k, (drive, label)) in enumerate(drive_labels)]
"each rig with its area column in designs.csv"
rig_area_columns = (("kite", "kite_area"), ("wings", "wing_area"), ("rotors", "rotor_area"))

"""
    kite_geometry_figure()

Planforms of the kites of the three aspect ratios at equal projected area, seen
from above and to scale, with their projected span.
"""
function kite_geometry_figure()
    geometries = [read_table(joinpath(polars, "geometry_ar$aspect_ratio.csv"))
                  for aspect_ratio in aspect_ratios]
    spans = [maximum(geometry["le_y"]) - minimum(geometry["le_y"])
             for geometry in geometries]
    leading = -minimum(minimum(geometry["le_x"]) for geometry in geometries)
    trailing = -maximum(maximum(geometry["te_x"]) for geometry in geometries)
    gap = 5
    limits = (-1, sum(spans) + gap * (length(spans) - 1) + 1, trailing - 2.4, leading + 2.6)
    height = (page_width - pt(9)) * (limits[4] - limits[3]) / (limits[2] - limits[1])
    figure = Figure(size=(page_width, height + pt(6)))
    axis = Axis(figure[1, 1]; aspect=DataAspect(), limits)
    hidedecorations!(axis)
    hidespines!(axis)
    for (i, (aspect_ratio, geometry)) in enumerate(zip(aspect_ratios, geometries))
        span = spans[i]
        centre = sum(spans[1:i-1]) + gap * (i - 1) + span / 2
        outline = [Point2f.(centre .+ geometry["le_y"], -geometry["le_x"]);
            Point2f.(centre .+ reverse(geometry["te_y"]), -reverse(geometry["te_x"]))]
        poly!(axis, outline; color=kite_shades(length(aspect_ratios))[i],
            strokecolor=:black, strokewidth=0.8)
        text!(axis, centre, leading + 0.6; text="AR $aspect_ratio",
            align=(:center, :bottom))
        text!(axis, centre, trailing - 0.6; text="span $(round(span; digits=1)) m",
            align=(:center, :top), fontsize=note_size)
    end
    save_figure("kite_geometry", figure)
end

"""
    polar_figure()

Lift, drag and glide ratio of the kites in their design shape over angle of attack,
without bridle and tether.
"""
function polar_figure()
    figure = Figure(size=(page_width, 170))
    angle_label = "angle of attack [°]"
    lift = Axis(figure[1, 1]; title="(a) lift", xlabel=angle_label, ylabel=L"C_L")
    drag = Axis(figure[1, 2]; title="(b) drag", xlabel=angle_label, ylabel=L"C_D")
    glide = Axis(figure[1, 3]; title="(c) glide ratio", xlabel=angle_label,
        ylabel=L"G = C_L/C_D")
    shades = kite_shades(length(aspect_ratios))
    for (i, aspect_ratio) in enumerate(aspect_ratios)
        polar = read_table(joinpath(polars, "kite_ar$aspect_ratio.csv"))
        label = "AR $aspect_ratio"
        lines!(lift, polar["alpha"], polar["cl"]; color=shades[i])
        lines!(drag, polar["alpha"], polar["cd"]; color=shades[i], label)
        lines!(glide, polar["alpha"], polar["cl"] ./ polar["cd"]; color=shades[i])
    end
    axislegend(drag; position=:lt)
    save_figure("polars", figure)
end

"classes whose wind-load coefficients the wind-load figure shows"
wind_load_classes = ("Megamax container ship", "PCTC car carrier", "Aframax tanker",
    "general cargo coaster")

"""
    wind_load_figure()

Longitudinal and side force coefficients of the ship's own wind load over the apparent
wind angle, for the [`wind_load_classes`](@ref) with their deck cargo.
"""
function wind_load_figure()
    figure = Figure(size=(page_width, 170))
    angle_label = "apparent wind angle off the bow [°]"
    longitudinal = Axis(figure[1, 1]; title="(a) along the ship", xlabel=angle_label,
        ylabel=L"C_X", xticks=0:30:180)
    side = Axis(figure[1, 2]; title="(b) to the side", xlabel=angle_label, ylabel=L"C_Y",
        xticks=0:30:180)
    angles = 0:180
    classes = ship_classes()
    for (i, name) in enumerate(wind_load_classes)
        windage = WindShipOpt.Windage(classes[name], assumptions)
        coefficients = WindShipOpt.wind_coefficients.(Ref(windage), deg2rad.(angles))
        lines!(longitudinal, angles, first.(coefficients); color=category_colours[i],
            label=name)
        lines!(side, angles, last.(coefficients); color=category_colours[i])
    end
    axislegend(longitudinal; position=:rb)
    save_figure("wind_load", figure)
end

"""
    geometric_mean(values)

Geometric mean of the positive numbers `values`.
"""
geometric_mean(values) = exp(sum(log, values) / length(values))

"""
    pattern_figure()

Optimal flight paths seen from the ship over the course off apparent downwind, in light
and strong apparent wind, without side-force weight, and the thrust and side force they
put on the ship, on one force scale.
"""
function pattern_figure()
    paths = read_table(data_file("patterns.csv"))
    forces = read_table(data_file("pattern_forces.csv"))
    figure = Figure(size=(page_width, 250))
    courses = 0:30:180
    colours = Makie.resample_cmap(:viridis, length(courses))
    unweighted = rows(forces, "side_weight" => 0.0)
    low, high = extrema([forces["thrust"][unweighted]; forces["side"][unweighted]]) ./ 1e3
    for (row, wind) in enumerate((6.0, 12.0))
        bottom = row == 2
        speed = "apparent wind $(round(Int, wind)) m/s"
        axis = Axis(figure[row, 1]; ylabel="elevation [°]", limits=(-35, 90, 0, 60),
            xlabel=bottom ? "azimuth off apparent downwind [°]" : "",
            title="($(('a', 'b')[row])) flight paths, $speed")
        for (i, course) in enumerate(courses)
            chosen = rows(paths, "wind" => wind, "course" => course, "side_weight" => 0.0)
            isempty(chosen) && continue
            lines!(axis, rad2deg.(paths["azimuth"][chosen]),
                rad2deg.(paths["elevation"][chosen]); color=colours[i])
        end
        bottom || hidexdecorations!(axis; ticks=false, ticklabels=false)
        thrust = Axis(figure[row, 3]; ylabel="force [kN]", limits=((-5, 185),
                (low - 30, high + 30)),
            xlabel=bottom ? "course off apparent downwind [°]" : "", xticks=0:30:180,
            yticks=-400:100:400, title="($(('c', 'd')[row])) force on the ship, $speed")
        bottom || hidexdecorations!(thrust; ticks=false, ticklabels=false)
        hlines!(thrust, 0; color=:gray80, linewidth=0.5)
        chosen = rows(forces, "wind" => wind, "side_weight" => 0.0)
        for (k, (column, label, marker)) in enumerate((("thrust", "thrust", :circle),
            ("side", "side force", :rect)))
            scatterlines!(thrust, forces["course"][chosen], forces[column][chosen] ./ 1e3;
                color=category_colours[k], label, marker)
        end
        bottom && axislegend(thrust; position=:rt)
    end
    Colorbar(figure[1:2, 2]; colormap=cgrad(colours; categorical=true),
        limits=(-15, 195), ticks=courses, width=pt(5),
        label="course off apparent downwind [°]")
    save_figure("patterns", figure)
end

"""
    draw_force_balance!(axis, area, force, radius)

Draw on `axis` the path from tether force to cloth tension of a kite of `area` [m^2], at
tether force `force` [N] and skin radius `radius` [m]: the kite pulled by its tether, the
pressure that force implies over the canopy, and a cell whose skin carries the tension.
"""
function draw_force_balance!(axis, area, force, radius)
    pressure = force / area
    arc(centre, reach, sweep) = [centre .+ reach .* (cos(angle), sin(angle))
                                 for angle in sweep]
    lines!(axis, arc((0.0, -1.0), 2.0, range(π / 4, 3π / 4; length=40)); color=:black,
        linewidth=2)
    wedge = [(x, sqrt(4 - x^2) - 1.0) for x in (-1.2, -0.6, 0.6, 1.2)]
    arrows2d!(axis, first.(wedge), last.(wedge), zeros(4), fill(0.4, 4);
        color=category_colours[1])
    arrows2d!(axis, [0.0], [0.8], [0.0], [-2.3]; color=palette[1])
    text!(axis, 0.0, 1.5; text=L"p = F/A = %$(round(Int, pressure))\,\mathrm{N/m^2}",
        align=(:center, :bottom), color=category_colours[1])
    text!(axis, -0.35, -0.9;
        text=L"F = %$(round(force / 1e6; digits=1))\,\mathrm{MN}", align=(:right, :bottom),
        color=palette[1])
    text!(axis, -0.35, -0.9; text=L"A = %$(round(Int, area))\,\mathrm{m^2}",
        align=(:right, :top), color=palette[1])
    left, right = (3.3, 0.0), (6.3, 0.0)
    centre = ((left[1] + right[1]) / 2, -0.75)
    reach = hypot(left[1] - centre[1], centre[2])
    opening = atan(-centre[2], right[1] - centre[1])
    lines!(axis, arc(centre, reach, range(opening, π - opening; length=40)); color=:black,
        linewidth=2)
    lines!(axis, [left, (left[1], -1.3)]; color=:gray60, linewidth=2)
    lines!(axis, [right, (right[1], -1.3)]; color=:gray60, linewidth=2)
    arrows2d!(axis, [centre[1]], [centre[2]], [0.0], [reach]; color=:gray40)
    text!(axis, centre...; text=L"R = %$(round(radius; digits=1))\,\mathrm{m}",
        align=(:center, :top), offset=clear_offset((:center, :top), pt(3)))
    for (corner, side) in ((left, 1), (right, -1))
        outward = 0.12 .* (corner .- centre) ./ reach
        arrows2d!(axis, [corner[1] + outward[1]], [corner[2] + outward[2]],
            [0.8side * sin(opening)], [0.8cos(opening)]; color=category_colours[2])
    end
    tension = round(Int, pressure * radius)
    text!(axis, centre[1], 1.25; text=L"T = p\,R = %$(tension)\,\mathrm{N/m}",
        align=(:center, :bottom), color=category_colours[2])
    text!(axis, left[1] - 0.1, -0.8; text="rib", fontsize=note_size,
        align=(:right, :center), color=:gray40)
    arrows2d!(axis, [1.9], [0.3], [0.8], [0.0]; color=:gray60)
    hidedecorations!(axis)
    hidespines!(axis)
end

"area-averaged radius [m] the canopy skin bulges to between ribs, in the cloth check"
skin_radius = 0.5

"strength over weight [N/m per g/m^2] of new canopy cloth, in the cloth check"
cloth_specific_strength = 170.0

"""
    canopy_tension_figure()

From tether force to cloth tension on the reference kite: (a) the force balance at the force
limit, (b) tether force and cloth tension over one optimal cycle, with its mean and peak.
"""
function canopy_tension_figure()
    area = Dict(reference_rigs)["kite"]
    limit = 1e3assumptions[:kite_max_force_per_area] * area
    table = read_table(data_file("canopy_tension_history.csv"))
    times, forces = table["time"], table["tension"] ./ 1e6
    mean_force = sum(forces .* table["duration"]) / sum(table["duration"])
    peak_force = maximum(forces)
    tension(force) = 1e3force / area * skin_radius
    strength = cloth_specific_strength * WindShipOpt.cloth_weight(assumptions) / 1e3
    figure = Figure(size=(page_width, 185))
    balance = Axis(figure[1, 1]; autolimitaspect=1, limits=(-2.4, 6.8, -1.7, 2.2),
        title="(a) from tether force to cloth tension")
    draw_force_balance!(balance, area, limit, skin_radius)
    force_axis = Axis(figure[1, 2]; xlabel="time in the cycle [s]",
        ylabel="tether force [MN]",
        title=@sprintf("(b) one cycle, %.0f m/s, %.0f° off downwind", table["wind"][1],
            table["course"][1]))
    cloth_axis = Axis(figure[1, 2]; ylabel="cloth tension [kN/m]", yaxisposition=:right)
    hidespines!(cloth_axis)
    hidexdecorations!(cloth_axis)
    lowest, highest = 0.9minimum(forces), 1.12peak_force
    ylims!(force_axis, lowest, highest)
    ylims!(cloth_axis, tension(lowest), tension(highest))
    hlines!(force_axis, mean_force; color=category_colours[1], linestyle=:dash)
    hlines!(force_axis, peak_force; color=category_colours[2], linestyle=:dot)
    lines!(force_axis, times, forces; color=palette[1])
    text!(force_axis, times[end], mean_force;
        text=@sprintf("mean %.2f MN, %.2f kN/m", mean_force, tension(mean_force)),
        fontsize=note_size, align=(:right, :top), color=category_colours[1],
        offset=clear_offset((:right, :top), pt(2)))
    text!(force_axis, times[1], peak_force;
        text=@sprintf("peak %.2f MN, %.2f kN/m\nnew cloth about %s kN/m, %s × peak",
            peak_force, tension(peak_force), estimate_text(strength),
            estimate_text(strength / tension(peak_force))),
        fontsize=note_size, align=(:left, :bottom), color=category_colours[2],
        offset=clear_offset((:left, :bottom), pt(2)))
    colsize!(figure.layout, 1, Relative(0.52))
    save_figure("canopy_tension", figure)
end

"""
    rig_polar_figure()

Thrust and side force of the best trim over true wind angle on a 140 m ship at 10.5 kn in
10 m/s wind, for an 800 m^2 kite, 800 m^2 of wings and 400 m^2 of rotors.
"""
function rig_polar_figure()
    figure = Figure(size=(column_width, 398))
    thrust = Axis(figure[1, 1]; title="(a) thrust", ylabel="thrust [kN]",
        yautolimitmargin=(0, 0.08))
    side = Axis(figure[2, 1]; title="(b) side force", xlabel="true wind angle [°]",
        ylabel="side force [kN]", xticks=30:30:180, yautolimitmargin=(0, 0.05))
    angles = 30:5:180
    rigs = ((square_metres("kite 800 "), (kite_area=800.0,)),
        (square_metres("wings 800 "), (wing_area=800.0,)),
        (square_metres("rotors 400 "), (rotor_area=400.0,)))
    for (i, (label, area)) in enumerate(rigs)
        ship = Ship(ShipDesign(:vlsfo, 140.0; area...), assumptions)
        forces = [last(WindShipOpt.best_trim(ship, ship.rig, 10.5KNOT, 10.0,
                      deg2rad(angle))) for angle in angles]
        lines!(thrust, angles, [force.thrust for force in forces] ./ 1e3;
            color=palette[i], label)
        lines!(side, angles, abs.([force.side for force in forces]) ./ 1e3;
            color=palette[i])
    end
    entries = [LineElement(color=palette[i]) for i in eachindex(rigs)]
    axislegend(side, entries, collect(first.(rigs)); position=:rt)
    linkxaxes!(thrust, side)
    hidexdecorations!(thrust; grid=false, ticks=false)
    ylims!(thrust; low=0)
    ylims!(side; low=0)
    save_figure("rig_polar", figure)
end

"""
    rig_comparison_figure()

Cost saving against the same ship without a rig on the route to Guadeloupe, as a table
over ship length (columns) and rig size (rows, grouped by rig) for each drive; the best
size of each rig on each ship is outlined.
"""
function rig_comparison_figure()
    designs = read_table(data_file("designs.csv"))
    lengths = sort(unique(designs["length"]))
    figure = Figure(size=(page_width, 330))
    panels = []
    for (column, (drive, title)) in enumerate(drive_panels)
        labels = []
        group_starts = Int[]
        cells = Tuple{Int, Int, Float64}[]
        best = Tuple{Int, Int}[]
        row = 0
        for (kind, column_name) in rig_area_columns
            areas = sort(unique(designs[column_name][rows(designs, "scenario" => "base",
                "drive" => drive)]))
            areas = filter(>(0), areas)
            first_row = row + 1
            push!(group_starts, first_row)
            for area in areas
                row += 1
                push!(labels, square_metres("$kind $(round(Int, area)) "))
            end
            for (i, length) in enumerate(lengths)
                bare = rows(designs, "scenario" => "base", "drive" => drive,
                    "length" => length, "kite_area" => 0.0, "wing_area" => 0.0,
                    "rotor_area" => 0.0)
                isempty(bare) && continue
                savings = Float64[]
                for (k, area) in enumerate(areas)
                    chosen = rows(designs, "scenario" => "base", "drive" => drive,
                        "length" => length, column_name => area)
                    saving = isempty(chosen) ? NaN :
                             percent_saving(designs["cost"][only(chosen)],
                                 designs["cost"][only(bare)])
                    push!(savings, saving)
                    isfinite(saving) && push!(cells, (i, first_row + k - 1, saving))
                end
                any(isfinite, savings) || continue
                push!(best, (i, first_row - 1 + argmax(replace(savings, NaN => -Inf))))
            end
        end
        push!(panels, (column, title, labels, cells, best, group_starts))
    end
    span = 5ceil(maximum(abs(saving) for (_, _, _, cells, _, _) in panels
                         for (_, _, saving) in cells) / 5)
    for (column, title, labels, cells, best, group_starts) in panels
        axis = Axis(figure[1, column]; title, xlabel="waterline length [m]",
            xticks=(eachindex(lengths), string.(round.(Int, lengths))),
            yticks=(eachindex(labels), labels), yreversed=true,
            yticklabelsvisible=column == 1)
        for (i, k, saving) in cells
            poly!(axis, Rect2f(i - 0.5, k - 0.5, 1, 1);
                color=get(cgrad(:RdBu), (saving + span) / 2span))
            text!(axis, i, k; text=typeset_minus(@sprintf("%.1f", saving)),
                fontsize=note_size, align=(:center, :center),
                color=abs(saving) > 0.6span ? :white : :black)
        end
        for (i, k) in best
            poly!(axis, Rect2f(i - 0.42, k - 0.4, 0.84, 0.8); color=:transparent,
                strokecolor=:black, strokewidth=pt(1))
        end
        hlines!(axis, group_starts[2:end] .- 0.5; color=:black, linewidth=0.8)
        limits!(axis, 0.5, length(lengths) + 0.5, length(labels) + 0.5, 0.5)
    end
    Colorbar(figure[1, length(drive_panels) + 1]; colormap=:RdBu, limits=(-span, span),
        label="cost saving against no rig [%]")
    save_figure("rig_comparison", figure)
end

"""
    route_figure()

Weather-routed passages on every route of a 140 m e-ammonia ship without a rig and
with a 3200 m^2 kite, for a winter and a summer departure, over the 10 m wind five days
after departure with a reference arrow; solid outbound, dashed homeward.
"""
function route_figure()
    designs = (ShipDesign(:ammonia, 140.0), ShipDesign(:ammonia, 140.0; kite_area=3200.0))
    port_hours = 24assumptions[:port_time_per_call]
    seasons = (("winter", 1), ("summer", findfirst(>=(24 * 181), departures)))
    wind_scale, reference_wind = 0.4, 10
    figure = Figure(size=(page_width, 255))
    for (column, (season, index)) in enumerate(seasons)
        axis = Axis(figure[1, column]; title="($('a' + column - 1)) $season departure",
            xlabel="longitude [°]",
            ylabel=column == 1 ? "latitude [°]" : "", aspect=DataAspect(),
            limits=(-100, 12, -26, 58))
        draw_land!(axis, mask; lons=-100:0.25:12, lats=-26:0.25:58)
        departure = departures[index]
        draw_wind!(axis, weather, departure + 24 * 5; scale=wind_scale, lons=-98:6:10,
            lats=-24:6:56)
        for (k, design) in enumerate(designs)
            ship = Ship(design, assumptions)
            table = PerformanceTable(ship, assumptions)
            out_hourly, back_hourly = WindShipOpt.leg_time_costs(ShipCosts(ship,
                assumptions), assumptions)
            for (i, name) in enumerate(route_names)
                outbound, inbound = run_corridors(name)
                out = route(outbound, table, weather, departure; time_cost=out_hourly)
                back = route(inbound, table, weather, departure + out.duration +
                                                      port_hours; time_cost=back_hourly)
                k == 1 && lines!(axis, great_circle(out.path[1], out.path[end])...;
                    color=:black, linestyle=:dot, linewidth=0.8)
                for (leg, style) in ((out, :solid), (back, :dash))
                    scatterlines!(axis, track_points(leg.path);
                        color=k == 1 ? (:black, 0.6) : category_colours[i], linestyle=style,
                        linewidth=k == 1 ? 0.8 : 1.5, markersize=pt(k == 1 ? 2.5 : 3.5))
                end
            end
        end
        column == 1 && wind_key!(axis, wind_scale, reference_wind)
    end
    entries = [[LineElement(color=category_colours[i])
                for i in eachindex(route_names)];
        LineElement(color=(:black, 0.6), linewidth=0.8);
        LineElement(color=:black, linestyle=:dot, linewidth=0.8);
        LineElement(color=:black, linewidth=0.8);
        LineElement(color=:black, linestyle=:dash, linewidth=0.8);
        MarkerElement(marker=:circle, color=:black, markersize=pt(3.5))]
    names = [[route_label(name) * " + kite" for name in route_names]; "no rig";
        "great circle"; "outbound"; "homeward"; "corridor node"]
    Legend(figure[2, 1:2], entries, names; orientation=:horizontal, nbanks=2)
    save_figure("routes", figure)
end

"""
    wind_key!(axis, scale, speed)

Reference arrow of `speed` [m/s] drawn at `scale` [deg per m/s] in a white box in the
lower left corner of a map `axis`.
"""
function wind_key!(axis, scale, speed)
    corner = Point2f(-98, -24)
    poly!(axis, Rect2f(corner, Vec2f(scale * speed + 14, 7)); color=:white,
        strokecolor=:gray55, strokewidth=rule_width)
    arrows2d!(axis, [corner .+ Point2f(2, 3.5)], [Vec2f(scale * speed, 0)];
        color=(:black, 0.35), shaftwidth=0.6, tiplength=2.8, tipwidth=2.6)
    text!(axis, corner .+ Point2f(scale * speed + 3, 3.5); text="$speed m/s",
        align=(:left, :center), fontsize=note_size)
end

"""
    figure_passages()

The labelled designs of [`passage_figure`](@ref) and each one's routed leg with its trace.
"""
function figure_passages()
    designs = (("no rig", passage_ship_design("none", 0.0)),
        (square_metres("kite 3200 "), passage_ship_design("kite", 3200.0)),
        (square_metres("wings 1500 "), passage_ship_design("wings", 1500.0)),
        (square_metres("rotors 800 "), passage_ship_design("rotors", 800.0)))
    outbound = first(run_corridors(:caribbean))
    legs = map(designs) do (label, design)
        ship = Ship(design, assumptions)
        table = PerformanceTable(ship, assumptions)
        hourly = first(WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions),
            assumptions))
        return traced_passage(table, outbound, departures[1], hourly)
    end
    return designs, legs
end

"""
    passage_figure()

One winter outbound passage to Guadeloupe of a 140 m e-ammonia ship without a rig and
with each rig: the routed tracks through the corridor's nodes over the 10 m wind six days
after departure, each in the colour of its ship, and the speed, rig thrust and
fuel power at each sample of the passage.
"""
function passage_figure()
    designs, legs = figure_passages()
    design_colours = [:black; palette[eachindex(rig_names)]]
    departure = departures[1]
    figure = Figure(size=(page_width, 360))
    map_axis = Axis(figure[1, 1:2]; aspect=DataAspect(), limits=(-64, 10, 13, 56),
        xlabel="longitude [°]", ylabel="latitude [°]", title="(a) routed tracks")
    draw_land!(map_axis, mask)
    wind_scale = 0.3
    draw_wind!(map_axis, weather, departure + 24 * 6; scale=wind_scale)
    wind_key!(map_axis, Point2f(-63, 51.5), 10, wind_scale)
    first_path = first(first(legs)).path
    lines!(map_axis, great_circle(first_path[1], first_path[end])...; color=:black,
        linestyle=:dot, linewidth=0.8)
    tracks = [track_points(leg.path) for (leg, _) in legs]
    for (i, track) in enumerate(tracks)
        lines!(map_axis, track; color=design_colours[i],
            linewidth=pt(1 + 0.9(length(tracks) - i)))
    end
    scatter!(map_axis, unique(reduce(vcat, tracks)); color=:black, markersize=pt(2.5))
    labels = ("speed [kn]", "rig thrust [kN]", "fuel power [MW]")
    titles = ("(b) speed through the water", "(c) rig thrust", "(d) fuel power")
    panels = [Axis(figure[2, column]; ylabel=labels[column], title=titles[column],
                  xlabel="days since departure",
                  yticks=WilkinsonTicks(4; Q=[(1.0, 1.0), (5.0, 0.9), (2.0, 0.7)]),
                  yscale=column == 2 ? log10 : identity)
              for column in 1:3]
    ylims!(panels[2], 3, 3000)
    panels[2].yticks = [10, 100, 1000]
    for (i, (label, _)) in enumerate(designs)
        trace = legs[i][2]
        thrust = [value >= 5e3 ? value / 1e3 : NaN for value in trace.rig_thrust]
        for (panel, values) in zip(panels, (trace.speed ./ KNOT, thrust,
            trace.fuel_power ./ 1e6))
            stairs!(panel, trace.time ./ 24, values; step=:post, color=design_colours[i],
                label)
        end
    end
    linkxaxes!(panels...)
    Legend(figure[1, 3], panels[1]; tellheight=false, tellwidth=false, halign=:left,
        valign=:top)
    rowsize!(figure.layout, 1, Relative(0.6))
    save_figure("passage", figure)
end

"""
    wind_key!(axis, corner, speed, scale)

A white box with its lower left at `corner` [deg] in `axis` holding a wind arrow of
`speed` [m/s] at the `scale` of [`draw_wind!`](@ref), labelled with that speed.
"""
function wind_key!(axis, corner, speed, scale)
    poly!(axis, Rect2f(corner, Vec2f(speed * scale + 8.5, 3)); color=:white,
        strokecolor=:gray55, strokewidth=rule_width)
    start = corner .+ Point2f(1, 1.5)
    arrows2d!(axis, [start], [Vec2f(speed * scale, 0)]; color=(:black, 0.35),
        shaftwidth=0.6, tiplength=2.8, tipwidth=2.6)
    text!(axis, start .+ Point2f(speed * scale + 0.8, 0); text="$speed m/s",
        align=(:left, :center), fontsize=note_size)
end

"""
    class_order(table)

Classes of the class table sorted by deadweight.
"""
function class_order(table)
    classes = ship_classes()
    names = unique(table["class"])
    return sort(names; by=name -> classes[name].deadweight)
end

"""
    limit_groups(table)

`(limit, names)` of the deadweight-limited and of the space-limited classes of the class
table `table`, each sorted by deadweight.
"""
function limit_groups(table)
    classes = ship_classes()
    return [(limit, [name for name in class_order(table)
                     if limit_label(classes[name]) == limit])
            for limit in ("deadweight", "space")]
end

"""
    route_savings(table, column, classes, drive, rig)

The [`mean_savings`](@ref) in `column` over `classes` of each route on which any of them
was run.
"""
route_savings(table, column, classes, drive, rig) = filter(isfinite,
    [only(mean_savings(table, (column,), classes, drive, rig; routes=[route]))
     for route in unique(table["route"])])

"""
    savings_panel!(axis, table, groups, drive, column, format)

Draw on `axis`, per `(label, classes)` of `groups`, each rig's [`mean_savings`](@ref) in
`column` as a marker with a bar over its [`route_savings`](@ref), a band in the colour of
the rig with the largest mean (grey where none is positive) and that mean printed with
`format`. What was not run is left out, so a drive without data leaves `axis` blank.
"""
function savings_panel!(axis, table, groups, drive, column, format)
    savings = [[route_savings(table, column, classes, drive, kind) for kind in rig_names]
               for (_, classes) in groups]
    all_routes = reduce(vcat, reduce(vcat, savings))
    isempty(all_routes) && return
    means = [[only(mean_savings(table, (column,), classes, drive, kind))
              for kind in rig_names] for (_, classes) in groups]
    span = extrema([all_routes; 0])
    width = span[2] - span[1]
    number_x = span[2] + 0.07 * width
    for (i, group_means) in enumerate(means)
        known = findall(isfinite, group_means)
        isempty(known) && continue
        leader = known[argmax(group_means[known])]
        hspan!(axis, i - 0.5, i + 0.5;
            color=group_means[leader] > 0 ? (palette[leader], 0.2) : (:gray, 0.2))
        text!(axis, number_x, i; text=typeset_minus(Printf.format(format,
                group_means[leader])), align=(:left, :center), fontsize=note_size)
    end
    vlines!(axis, 0; color=:gray, linewidth=0.5)
    hlines!(axis, length(groups) - 1.5; color=:black, linewidth=0.5)
    for (i, rigs) in enumerate(savings), (j, values) in enumerate(rigs)
        isempty(values) && continue
        y = i + (j - 2) * 0.22
        rangebars!(axis, [y], [minimum(values)], [maximum(values)];
            direction=:x, color=(palette[j], 0.6))
        scatter!(axis, [means[i][j]], [y]; color=palette[j])
    end
    limits!(axis, span[1] - 0.04 * width, span[2] + 0.3 * width, length(groups) + 0.5, 0.5)
    axis.xticks = Makie.get_tickvalues(
        Makie.WilkinsonTicks(4; Q=[(1.0, 1.0), (5.0, 0.9), (2.0, 0.7)]), span...)
end

"""
    class_comparison_figure()

Cost saving and fuel saving of the best size of each rig for every ship class and the mean
of the deadweight-limited and of the space-limited classes, a [`savings_panel!`](@ref) of
each per drive.
"""
function class_comparison_figure()
    table = read_table(data_file("classes.csv"))
    groups = [[(name, [name]) for name in class_order(table)];
              [("mean, $limit-limited", names) for (limit, names) in limit_groups(table)]]
    figure = Figure(size=(page_width, 390))
    for (k, (drive, title)) in enumerate(drive_panels)
        Label(figure[1, (2k - 1):2k], title; tellwidth=false, halign=:left)
        fuel_label = drive == "vlsfo" ? rich("fuel, CO", subscript("2"), " saving [%]") :
                     "fuel saving [%]"
        panels = (("cost", "cost saving [%]", "%.1f"), ("fuel", fuel_label, "%.0f"))
        for (offset, (column, xlabel, format)) in enumerate(panels)
            axis = Axis(figure[2, 2k - 2 + offset]; xlabel,
                yticks=(eachindex(groups), first.(groups)), yreversed=true,
                yticklabelsvisible=(k, offset) == (1, 1))
            savings_panel!(axis, table, groups, drive, column, Printf.Format(format))
        end
    end
    rowgap!(figure.layout, 1, 4)
    Legend(figure[1, 2length(drive_panels)],
        [MarkerElement(; color=palette[j], marker=:circle)
         for j in eachindex(rig_names)], collect(rig_names); orientation=:horizontal,
        halign=:right, valign=:bottom, tellwidth=false, margin=(0, 0, 0, 0))
    save_figure("class_comparison", figure)
end

"""
    sweep_measures(table, drive, rig, class)

The cost saving [%], its part from time [points] and the speed the rig adds [kn], each the
mean over the routes, of the cheapest size of `rig` on `drive` for `class` at each value of
[`cargo_value_sweep`](@ref), as three vectors.
"""
function sweep_measures(table, drive, rig, class)
    saving, time, speed = (Float64[] for _ in 1:3)
    for value in cargo_value_sweep.values
        kept = rows(table, "class" => class, "cargo_value" => value)
        value_table = table_rows(table, kept)
        points = split_points(rig_splits(value_table, drive, rig))
        push!(saving, points[1])
        push!(time, points[3])
        push!(speed, mean_sailing_speed(value_table, drive, rig) -
                     mean_sailing_speed(value_table, drive, "none"))
    end
    return (saving, time, speed)
end

"""
    interest_classes_panel!(axis, table, drive, names)

Scatter in `axis` of the cost saving of the best size of each rig on `drive` for each class
of `names`, an open ring at low and a smaller dot at high cargo interest, so that a dot in
a ring shows two equal savings.
"""
function interest_classes_panel!(axis, table, drive, names)
    vlines!(axis, 0; color=:gray, linewidth=0.5)
    for (j, kind) in enumerate(rig_names),
        (level, factor) in pairs(cargo_interest_factors())

        level_table = interest_level_rows(table, factor)
        y = eachindex(names) .+ (j - 2) * 0.22
        savings = [only(mean_savings(level_table, ("cost",), [name], drive, kind))
                   for name in names]
        scatter!(axis, savings, collect(y); interest_marker(level, palette[j])...)
    end
end

"""
    cargo_interest_figure()

Effect of cargo interest on the rigs on the zero-emission drive: (a) the cost saving of the
best size of each rig for every class at low and high cargo interest; and, against cargo
value on the classes of the cargo value sweep, each as the mean over the routes, (b) the
cost saving, (c) its part from time and (d) the speed the rig adds.
"""
function cargo_interest_figure()
    table = read_table(data_file("cargo_interest.csv"))
    drive = string(last(study_drives))
    names = class_order(interest_level_rows(table, cargo_interest_factors().low))
    figure = Figure(size=(page_width, 400))
    classes_axis = Axis(figure[1:3, 1]; title="(a) cargo interest",
        xlabel="cost saving [%]", yticks=(eachindex(names), names), yreversed=true)
    interest_classes_panel!(classes_axis, table, drive, names)
    values = collect(cargo_value_sweep.values)
    sweep_axes = [Axis(figure[i, 2]; title, ylabel, xscale=log10, xticks=[100, 1000, 10000],
                      xtickformat=ticks -> [@sprintf("%.0f", tick) for tick in ticks],
                      xlabel=i == 3 ? "cargo value [USD/t]" : "", xticklabelsvisible=i == 3,
                      yautolimitmargin=(0.05, 0.12))
                  for (i, (title, ylabel)) in enumerate((("(b) cost saving",
            "cost saving [%]"),
        ("(c) part of the saving from time", "time [points]"),
        ("(d) speed the rig adds", "speed [kn]")))]
    class_styles = (:solid, :dash)
    for (j, kind) in enumerate(rig_names),
        (name, style) in zip(cargo_value_sweep.classes, class_styles)

        for (axis, measure) in zip(sweep_axes, sweep_measures(table, drive, kind, name))
            lines!(axis, values, measure; color=palette[j], linestyle=style)
            scatter!(axis, values, measure; color=palette[j])
        end
    end
    hlines!.(sweep_axes[2:3], 0; color=:gray, linewidth=0.5)
    linkxaxes!(sweep_axes...)
    rig_entries = [MarkerElement(; color=palette[j], marker=:circle)
                   for j in eachindex(rig_names)]
    rate = assumptions.entries[:discount_rate]
    level_entries = [MarkerElement(; interest_marker(level, :black)...)
                     for level in keys(cargo_interest_factors())]
    class_entries = [LineElement(; color=:black, linestyle=style)
                     for style in class_styles]
    Legend(figure[4, 1:2], [rig_entries, level_entries, class_entries],
        [collect(rig_names), ["$(round(Int, 100bound)) %" for bound in (rate.low,
                rate.high)], collect(cargo_value_sweep.classes)],
        ["rig", "discount rate (a)", "ship (b to d)"]; orientation=:horizontal,
        titleposition=:top, nbanks=3)
    save_figure("cargo_interest", figure)
end

"""
    interest_marker(level, colour)

Marker attributes of a saving at cargo interest `level` (`:low` or `:high`) in `colour`.
"""
interest_marker(level, colour) = level == :high ?
    (; color=colour, marker=:circle, markersize=0.7marker_size) :
    (; color=:transparent, strokecolor=colour, strokewidth=pt(0.8), marker=:circle,
        markersize=1.5marker_size)

"the tow points of the tow point study with their labels, then a midship mast in a bay"
tow_point_markers = (("bow", "bow"), ("centre", "lateral centre"),
    ("midship", "midship"), ("midship_bay", "midship, mast in a deck bay"))

"""
    midship_bay_cargo(class, cargo)

Cargo [t] of a ship of `class` that carries `cargo` [t] when its kite mast stands
midship in a 40-foot bay of the deck stack and blocks that bay across the beam on every
tier; `cargo` itself on ships without a deck stack or that fill their deadweight first.
"""
function midship_bay_cargo(class, cargo)
    class.cargo_unit == :teu || return cargo
    rows = floor(class.beam / assumptions[:container_row_pitch])
    slots = class.unit_capacity - WindShipOpt.bay_slots(rows, class)
    return min(cargo, slots * WindShipOpt.CargoUnit(:teu, assumptions).cargo)
end

"""
    tow_point_savings(table, class, route, measure)

Saving [%] in the column `measure` of the kite at each of `tow_point_markers` against
no rig for `class` on `route`; the cost of the midship mast in a bay scales with the
cargo [`midship_bay_cargo`](@ref) leaves.
"""
function tow_point_savings(table, class, route, measure)
    reference = tow_point_value(table, class, route, "none", measure)
    savings = Dict(tow => percent_saving(tow_point_value(table, class, route, tow,
                       measure), reference) for (tow, _) in tow_point_markers[1:3])
    cargo = tow_point_value(table, class, route, "midship", "cargo")
    scale = measure == "cost" ? cargo / midship_bay_cargo(ship_classes()[class], cargo) : 1
    savings["midship_bay"] = percent_saving(
        scale * tow_point_value(table, class, route, "midship", measure), reference)
    return savings
end

"Value in `column` of the tow point study's row for `class`, `route` and `tow`"
tow_point_value(table, class, route, tow, column) =
    only(table[column][rows(table, "class" => class, "route" => route, "tow" => tow)])

"""
    tow_point_figure()

Fuel and cost saving of each class's kite towing from the hull's lateral centre and
midship, and for container ships at midship with its mast in a deck bay, against the kite
towing from the bow: the mean over the routes as a marker and the range over them as a bar.
Prints the savings and the losses against the bow.
"""
function tow_point_figure()
    table = read_table(data_file("tow_point.csv"))
    names = filter(name -> !isempty(rows(table, "class" => name, "tow" => "bow")),
        class_order(table))
    routes_seen = unique(table["route"])
    figure = Figure(size=(page_width, 300))
    panels = (("fuel", "(a) fuel saving"), ("cost", "(b) cost saving"))
    for (column, (measure, title)) in enumerate(panels)
        axis = Axis(figure[1, column]; title, xlabel="against the bow [% points]",
            yticks=(eachindex(names), names), yreversed=true,
            yticklabelsvisible=column == 1)
        vlines!(axis, 0; color=:gray70, linewidth=rule_width)
        savings = [tow_point_savings(table, name, route, measure)
                   for name in names, route in routes_seen]
        markers = measure == "cost" ? tow_point_markers : tow_point_markers[1:3]
        for (i, name) in enumerate(names)
            container = ship_classes()[name].cargo_unit == :teu
            tows = [tow for (tow, _) in markers[2:end] if container || tow != "midship_bay"]
            for (j, tow) in enumerate(tows)
                values = [saving[tow] - saving["bow"] for saving in savings[i, :]]
                y = i + (j - (length(tows) + 1) / 2) * 0.22
                rangebars!(axis, [y], [minimum(values)], [maximum(values)];
                    direction=:x, color=(category_colours[j], 0.6))
                scatter!(axis, [mean(values)], [y]; color=category_colours[j])
            end
        end
        print_tow_point(measure, names, savings, markers)
    end
    axislegend(content(figure[1, 1]),
        [MarkerElement(marker=:circle, color=category_colours[j]) for j in 1:3],
        ["lateral centre", "midship", "midship, mast in a bay"]; position=:lb)
    save_figure("tow_point", figure)
end

"""
    print_tow_point(measure, names, savings, markers)

Print the mean saving in `measure` of each tow point of `markers` over all classes and
routes of `savings`, its mean, least and largest loss [% points] against the bow, and
the loss of the last of `markers` for each class of `names` on each route.
"""
function print_tow_point(measure, names, savings, markers)
    for (tow, label) in markers
        losses = [saving["bow"] - saving[tow] for saving in savings]
        @printf("  %s saving at %s: %.1f %%, loss against the bow %.2f (%.2f to %.2f)\n",
            measure, label, mean(saving[tow] for saving in savings), mean(losses),
            extrema(losses)...)
    end
    tow, label = last(markers)
    for (i, name) in enumerate(names)
        losses = [saving["bow"] - saving[tow] for saving in savings[i, :]]
        println("    $name, $measure loss at $label: ",
            join(round.(losses; digits=1), ", "))
    end
end

"""
    best_area(table, class, route, drive, rig)

Area [m^2] of the size of `rig` with the lowest cost for one class, route and drive, or
`NaN` where the rig was not run.
"""
function best_area(table, class, route, drive, rig)
    best = cheapest_row(table, class, route, drive, rig)
    return isnothing(best) ? NaN : table["area"][best]
end

"""
    median_units(table, class, drive, rig)

Median over the routes of the number of units of `rig` at its cheapest size on `class`.
"""
function median_units(table, class, drive, rig)
    counts = Int[]
    for route in unique(table["route"])
        best = cheapest_row(table, class, route, drive, rig)
        isnothing(best) || push!(counts, round(Int, table["units"][best]))
    end
    return sort(counts)[cld(length(counts), 2)]
end

"""
    unit_count_axis(cell, row_limits)

Axis in `cell` with one column per rig, its rows `row_limits` matching the axis beside it.
"""
function unit_count_axis(cell, row_limits)
    return Axis(cell; width=pt(72), xlabel="number of units",
        xticks=(eachindex(rig_names), collect(rig_names)), xticksvisible=false,
        xticklabelcolor=palette[eachindex(rig_names)],
        yticksvisible=false, yticklabelsvisible=false, yreversed=true,
        limits=((0.5, length(rig_names) + 0.5), row_limits))
end

"""
    class_size_figure()

Best area of each rig for every ship class and drive, the geometric mean over the routes
as a marker and the range over the routes as a bar, with the largest kite searched, and
beside each panel the median
number of units of each rig at its best size, each column named in the rig's colour.
"""
function class_size_figure()
    table = read_table(data_file("classes.csv"))
    names = class_order(table)
    routes_seen = unique(table["route"])
    figure = Figure(size=(page_width, 285))
    ticks = [100, 1000, 10000]
    row_limits = (0.4, length(names) + 0.6)
    kite_bound = largest_rig_area("kite", nothing)
    area_limit = 1.4kite_bound
    for (column, (drive, title)) in enumerate(drive_panels)
        axis = Axis(figure[1, 2 * column - 1]; title,
            xlabel=square_metres("best rig area [", "]"), xscale=log10,
            xticks=(ticks, string.(ticks)),
            xminorticks=IntervalsBetween(9), xminorticksvisible=true,
            xgridvisible=true, xgridcolor=:gray88,
            yticks=(eachindex(names), names), yreversed=true,
            yticklabelsvisible=column == 1, limits=((100, area_limit), row_limits))
        vlines!(axis, kite_bound; color=palette[1], linestyle=:dash, linewidth=pt(0.6))
        text!(axis, kite_bound, row_limits[1]; text="kite search\nbound",
            align=(:right, :top), offset=(-pt(2), -pt(1)), fontsize=note_size,
            color=palette[1])
        counts = unit_count_axis(figure[1, 2 * column], row_limits)
        colgap!(figure.layout, 2 * column - 1, pt(4))
        for (j, kind) in enumerate(rig_names), (i, name) in enumerate(names)
            areas = filter(isfinite, [best_area(table, name, route, drive, kind)
                                      for route in routes_seen])
            isempty(areas) && continue
            y = i + (j - 2) * 0.22
            rangebars!(axis, [y], [minimum(areas)], [maximum(areas)]; direction=:x,
                color=(palette[j], 0.6))
            scatter!(axis, [geometric_mean(areas)], [y]; color=palette[j])
            text!(counts, j, i; text=string(median_units(table, name, drive, kind)),
                fontsize=note_size, align=(:center, :center), color=palette[j])
        end
    end
    save_figure("class_sizes", figure)
end

"""
    winner_map_figure()

The rig with the largest cost saving for every ship class and route, deadweight-limited
classes in the top row and space-limited ones below, one column per drive, coloured by
rig and labelled with its saving [%]; grey where no rig pays.
"""
function winner_map_figure()
    table = read_table(data_file("classes.csv"))
    groups = limit_groups(table)
    route_names_seen = route_order
    kinds = ["kite", "wings", "rotors"]
    winners = Set{String}()
    figure = Figure(size=(page_width, 400))
    for (row, (limit, names)) in enumerate(groups), (column, (drive, title)) in
                                                     enumerate(drive_panels)
        axis = Axis(figure[row, column];
            title=row == 1 ? title : "",
            xticks=(eachindex(route_names_seen), route_label.(route_names_seen)),
            yticks=(eachindex(names), names), yreversed=true,
            limits=(0.5, length(route_names_seen) + 0.5, 0.5, length(names) + 0.5),
            yticklabelsvisible=column == 1, xticklabelsvisible=row == length(groups),
            xticklabelrotation=π / 4)
        column == 1 && Label(figure[row, 0], "$limit-limited"; rotation=π / 2,
            tellheight=false)
        for (i, route) in enumerate(route_names_seen), (k, name) in enumerate(names)
            savings = best_savings(table, name, route, drive)
            isempty(savings) && continue
            winner = argmax(savings)
            best = savings[winner]
            best > 0 && push!(winners, winner)
            colour = best > 0 ? (palette[findfirst(==(winner), kinds)], 0.45 + 0.55 *
                                 min(best, 40) / 40) : (:gray, 0.6)
            poly!(axis, Rect2f(i - 0.5, k - 0.5, 1, 1); color=colour)
            text!(axis, i, k; text=typeset_minus(abs(best) < 1 ? @sprintf("%.1f", best) :
                                                 string(round(Int, best))),
                align=(:center, :center), fontsize=note_size)
        end
    end
    colgap!(figure.layout, 1, pt(4))
    for (row, (_, names)) in enumerate(groups)
        rowsize!(figure.layout, row, Auto(length(names)))
    end
    shown = filter(in(winners), kinds)
    Legend(figure[1, length(drive_panels), Top()],
        [PolyElement(color=palette[findfirst(==(kind), kinds)]) for kind in shown], shown;
        orientation=:horizontal, halign=:right, valign=:bottom, tellwidth=false,
        margin=(0, 0, pt(2), 0))
    save_figure("winner_map", figure)
end

"""
    fleet_share_panel!(axis, splits, measure)

Stacked bar per drive of the share [%] of `measure` (`:bill` or `:saved`) of each band of
`splits`, a Vector of drive name and [`fleet_split`](@ref), the first drive on top.
"""
function fleet_share_panel!(axis, splits, measure)
    colours = fleet_colours()
    for (i, (_, split)) in enumerate(splits)
        total = fleet_total(split, measure)
        left = 0.0
        for band in fleet_bands
            share = 100getfield(split[band], measure) / total
            share > 0 || continue
            poly!(axis, Rect2f(left, i - 0.32, share, 0.64); color=colours[band],
                strokecolor=:white, strokewidth=0.5)
            if share >= 6
                label = fleet_band_label(share, 1e-9getfield(split[band], measure))
                margin = max(0.8, 0.15share)
                band == "level" && poly!(axis, Rect2f(left + margin, i - 0.24,
                    share - 2margin, 0.48); color=:white)
                text!(axis, left + share / 2, i; text=label, align=(:center, :center),
                    fontsize=note_size, color=band in ("level", "none") ? :black : :white)
            end
            left += share
        end
    end
    xlims!(axis, 0, 100)
    ylims!(axis, length(splits) + 0.5, 0.5)
end

"""
    fleet_band_label(share, billions)

Label of a band of `share` [%] and `billions` [USD] of a bar, the dollars, an estimate,
only if they fit.
"""
function fleet_band_label(share, billions)
    share < 14 && return @sprintf("%.0f%%", share)
    return @sprintf("%.0f%%\n%s bn", share, estimate_text(billions))
end

"fill of what the kite and rotors share: the kite's colour hatched with the rotors'"
kite_and_rotors_fill() = Pattern("/"; backgroundcolor=(palette[1], 0.55),
    linecolor=palette[3], width=1.8, tilesize=(6, 6))

"colours of the [`fleet_bands`](@ref): those of the rigs, level hatched, none grey"
fleet_colours() = Dict("kite" => palette[1], "wings" => palette[2], "rotors" => palette[3],
    "level" => kite_and_rotors_fill(),
    "none" => RGBf(0.8, 0.8, 0.8))

"""
    fleet_share_figure()

Share [%] and dollars of each band of [`fleet_bands`](@ref) in the yearly cost of carrying
the fleet's cargo (a) and in the yearly saving (b) on each drive, each total in the row's
label.
"""
function fleet_share_figure()
    table = read_table(data_file("classes.csv"))
    splits = [(drive, fleet_split_of(table, drive)) for (drive, _) in drive_labels]
    figure = Figure(size=(page_width, 175))
    panels = ((:bill, "(a) yearly cost of carrying the cargo [%, USD]"),
        (:saved, "(b) yearly cost saved by the rigs [%, USD]"))
    for (k, (measure, title)) in enumerate(panels)
        labels = [string(label, "\nUSD ", estimate_text(1e-9fleet_total(split, measure)),
                      " bn") for ((_, label), (_, split)) in zip(drive_labels, splits)]
        axis = Axis(figure[1, k]; title, yticks=(eachindex(splits), labels),
            xticks=0:25:100, ygridvisible=false, ytickalign=0, yticksize=0)
        fleet_share_panel!(axis, splits, measure)
    end
    colours = fleet_colours()
    names = Dict("kite" => "kite", "wings" => "wing sails", "rotors" => "rotors",
        "level" => "level (within $(whole_number(level_margin)) point)",
        "none" => "no rig (saves under $(whole_number(level_margin)) point)")
    shown = [band for band in fleet_bands
             if any(getfield(split[band], :bill) > 0 for (_, split) in splits)]
    Legend(figure[2, 1:2], [PolyElement(color=colours[band]) for band in shown],
        [names[band] for band in shown]; orientation=:horizontal)
    rowgap!(figure.layout, 1, 2)
    save_figure("fleet_share", figure)
end

"""
    route_label(name)

Name of the destination of route `name` for figure labels.
"""
route_label(name) = Dict("caribbean" => "Guadeloupe", "new_york" => "New York",
    "bilbao" => "Bilbao", "dakar" => "Dakar", "houston" => "Houston",
    "tubarao" => "Tubarão")[string(name)]

"""
    route_comparison_figure()

Cost saving of the best size of each rig against the same ship without a rig, per route,
for three ship lengths and each drive.
"""
function route_comparison_figure()
    routes_table = read_table(data_file("routes.csv"))
    names = ["caribbean", "new_york", "bilbao", "dakar", "houston", "tubarao"]
    kinds = ["kite", "wings", "rotors"]
    drives = filter(((drive, _),) -> drive in routes_table["drive"], drive_labels)
    figure = Figure(size=(page_width, 60 + 120length(drives)))
    for (row, (drive, drive_label)) in enumerate(drives)
        axes = map(enumerate((85.0, 140.0, 200.0))) do (column, ship_length)
            letter = 'a' + 3(row - 1) + column - 1
            axis = Axis(figure[row, column];
                title="($letter) $drive_label, $(round(Int, ship_length)) m",
                xticks=(eachindex(names), route_label.(names)), xticklabelrotation=π / 4,
                ylabel=column == 1 ? "cost saving [%]" : "", yautolimitmargin=(0.1, 0.1))
            hlines!(axis, 0; color=:gray, linewidth=0.5)
            for (j, kind) in enumerate(kinds), (i, name) in enumerate(names)
                savings = rig_savings(routes_table, (kind,), "route" => name,
                    "drive" => drive, "length" => ship_length)
                haskey(savings, kind) || continue
                barplot!(axis, [i + (j - 2) * 0.27], [savings[kind]]; width=0.25,
                    color=palette[j])
            end
            row < length(drives) && hidexdecorations!(axis; grid=false, ticks=false)
            axis
        end
        linkyaxes!(axes...)
        row == 1 && axislegend(first(axes),
            [PolyElement(color=palette[j]) for j in eachindex(kinds)],
            rig_label.(kinds); position=:rt)
    end
    save_figure("route_comparison", figure)
end

"""
    season_figure()

Cost saving of each rig at its best size over the year against the 140 m e-ammonia ship
without a rig, per month of departure, over the routes on which every rig was run: the
mean of the routes' monthly means, joined over consecutive months, with a bar over their
range.
"""
function season_figure()
    routes_table = read_table(data_file("routes.csv"))
    departures = read_table(data_file("route_departures.csv"))
    ship = ("drive" => "ammonia", "length" => 140.0)
    savings = Dict(name => month_savings(routes_table, departures, name, ship)
                   for name in unique(routes_table["route"]))
    names = [name for name in route_order if haskey(savings, name) &&
                 all(!isempty(savings[name][rig]) for rig in rig_names)]
    isempty(names) && error("no route of the 140 m e-ammonia ship has departures of " *
                            "every rig")
    figure = Figure(size=(column_width, 190))
    axis = Axis(figure[1, 1]; ylabel="cost saving [%]",
        title=join(route_label.(names), ", "), limits=((0.4, 12.6), nothing),
        xticks=(1:12, ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]))
    hlines!(axis, 0; color=:gray, linewidth=0.5)
    for (j, rig) in enumerate(rig_names)
        route_means = [[mean(get(savings[name][rig], month, [NaN])) for name in names]
                       for month in 1:12]
        shown = findall(means -> all(isfinite, means), route_means)
        x = shown .+ 0.22(j - 2)
        rangebars!(axis, x, minimum.(route_means[shown]), maximum.(route_means[shown]);
            color=(palette[j], 0.6), whiskerwidth=pt(3))
        lines!(axis, (1:12) .+ 0.22(j - 2), mean.(route_means); color=(palette[j], 0.6),
            linewidth=pt(0.8))
        scatter!(axis, x, mean.(route_means[shown]); color=palette[j])
    end
    Legend(figure[1, 1, Top()], [MarkerElement(color=palette[j], marker=:circle)
                                 for j in eachindex(rig_names)], collect(rig_names);
        orientation=:horizontal, halign=:right, valign=:bottom, tellwidth=false,
        margin=(0, 0, pt(2), 0))
    save_figure("season", figure)
end

"routes in the order the paper names them"
route_order = ["caribbean", "new_york", "bilbao", "dakar", "houston", "tubarao"]

"""
    month_savings(routes_table, departures, name, ship)

Cost saving [%] of each departure of each rig of `rig_names` at its cheapest size over the
year on route `name` against `ship` without a rig, as a Dict of rig to a Dict of month of
departure to the savings of that month; empty for a rig not run there.
"""
function month_savings(routes_table, departures, name, ship)
    bare = departure_costs(departures, "route" => name, ship..., "rig" => "none")
    return Dict(map(rig_names) do rig
        sizes = rows(routes_table, "route" => name, ship..., "rig" => rig)
        months = Dict{Int, Vector{Float64}}()
        (isempty(sizes) || isempty(bare)) && return rig => months
        area = routes_table["area"][sizes[argmin(routes_table["cost"][sizes])]]
        costs = departure_costs(departures, "route" => name, ship..., "rig" => rig,
            "area" => area)
        for (date, cost) in costs
            haskey(bare, date) || continue
            push!(get!(months, month(date), Float64[]), percent_saving(cost, bare[date]))
        end
        return rig => months
    end)
end

"""
    departure_costs(table, conditions...)

Cost per tonne-km of each departure among the rows of `table` where the `conditions` hold,
as a Dict of departure date to cost.
"""
departure_costs(table, conditions...) =
    Dict(Date(table["date"][k]) => table["cost"][k] for k in rows(table, conditions...))

"""
    best_cost(designs, drive, length, column_name)

Lowest cost per tonne-km on the route to Guadeloupe of the base designs of one drive and
length with the rig of `column_name` (any size), or without a rig for `nothing`; `NaN`
where none was run.
"""
function best_cost(designs, drive, length, column_name)
    k = cheapest_design(designs, drive, length, column_name)
    return isnothing(k) ? NaN : designs["cost"][k]
end

"""
    spread_labels(positions, gap)

`positions` moved apart where needed so that neighbours stand at least `gap` apart, in the
same order, each group centred where it was.
"""
function spread_labels(positions, gap)
    order = sortperm(positions)
    placed = positions[order]
    for _ in eachindex(placed), i in 2:length(placed)
        overlap = gap - (placed[i] - placed[i - 1])
        overlap > 0 || continue
        placed[i - 1] -= overlap / 2
        placed[i] += overlap / 2
    end
    return placed[invperm(order)]
end

"""
    premium_figure()

Share of the cost premium of an e-ammonia ship over a VLSFO ship without a rig that the
best size of each rig closes, over ship length on the route to Guadeloupe, as a marker with
a bar over the shares at the corners of the ranges of the e-ammonia and VLSFO prices.
"""
function premium_figure()
    designs = read_table(data_file("designs.csv"))
    corners = [fuel_repriced(designs, Dict("ammonia" => ammonia, "vlsfo" => vlsfo))
               for ammonia in (:low, :high), vlsfo in (:low, :high)]
    figure = Figure(size=(column_width, 165))
    lengths = sort(unique(designs["length"]))
    axis = Axis(figure[1, 1]; xlabel="waterline length [m]",
        xticks=round.(Int, lengths), ylabel="cost premium closed [%]")
    ends = Float64[]
    for (k, (label, column_name)) in enumerate(rig_area_columns)
        shares = [premium_closed(designs, "ammonia", length, column_name)
                  for length in lengths]
        valid = isfinite.(shares)
        bounds = [extrema(premium_closed(table, "ammonia", length, column_name)
                          for table in corners) for length in lengths[valid]]
        rangebars!(axis, lengths[valid] .+ 2.5(k - 2), first.(bounds), last.(bounds);
            color=(palette[k], 0.6), whiskerwidth=pt(3))
        scatter!(axis, lengths[valid] .+ 2.5(k - 2), shares[valid]; color=palette[k])
        push!(ends, last(shares[valid]))
    end
    for (k, (label, _)) in enumerate(rig_area_columns)
        text!(axis, last(lengths) + 8, spread_labels(ends, 3.5)[k]; text=label,
            color=palette[k], fontsize=note_size, align=(:left, :center))
    end
    xlims!(axis, first(lengths) - 8, last(lengths) + 30)
    ylims!(axis, 0, nothing)
    save_figure("premium", figure)
end

"""
    premium_closed(designs, drive, length, column_name)

Share [%] of the cost premium of `drive` over VLSFO without a rig, at one ship length,
that the best size of the rig of `column_name` closes.
"""
function premium_closed(designs, drive, length, column_name)
    fossil = best_cost(designs, "vlsfo", length, nothing)
    bare = best_cost(designs, drive, length, nothing)
    return 100 * (bare - best_cost(designs, drive, length, column_name)) / (bare - fossil)
end

"factor on the base value of the input `name` at its `bound`, `:low` or `:high`"
input_factor(name, bound) =
    getfield(assumptions.entries[name], bound) / assumptions.entries[name].value

"""
    fuel_repriced(designs, bounds)

`designs` with the cost of each row of a drive in `bounds`, a Dict of drive to `:low` or
`:high`, at that bound of the price of its fuel.
"""
function fuel_repriced(designs, bounds)
    price_names = Dict("ammonia" => :e_ammonia_price, "vlsfo" => :vlsfo_price)
    factor(drive) =
        haskey(bounds, drive) ? input_factor(price_names[drive], bounds[drive]) : 1.0
    repriced = copy(designs)
    repriced["cost"] = designs["cost"] .+
                       designs["fuel_cost"] .* (factor.(designs["drive"]) .- 1)
    return repriced
end

"""
    cheapest_design(designs, drive, length, column)

Row of designs.csv with the lowest cost among the base designs of `drive` and `length`
that carry only the rig of area `column`, or none for `nothing`; `nothing` if there is
none.
"""
function cheapest_design(designs, drive, length, column)
    rig_columns = ("kite_area", "wing_area", "rotor_area")
    chosen = [k for k in rows(designs, "scenario" => "base", "drive" => drive,
                  "length" => length)
              if all((name == column) == (designs[name][k] > 0) for name in rig_columns)]
    isempty(chosen) && return nothing
    return chosen[argmin(designs["cost"][chosen])]
end

"""
    breakdown_figure()

Cost per tonne-km split into its parts for an 85 m and a 200 m ship on VLSFO without a
rig, and on e-ammonia without a rig and with the cheapest size of each rig, with a bar
over the total at the low and at the high fuel price, crew cost and cargo interest.
"""
function breakdown_figure()
    designs = read_table(data_file("designs.csv"))
    parts = ["fuel_cost", "wear_cost", "port_cost", "crew_cost", "capital_cost",
        "interest_cost"]
    names = ["fuel", "kite wear", "port", "crew", "capital and maintenance",
        "cargo interest"]
    colours = [:gray30, palette[1], category_colours[3], category_colours[2], :gray68,
        palette[6]]
    fuel_prices = Dict("vlsfo" => :vlsfo_price, "ammonia" => :e_ammonia_price)
    bound_factors(drive, bound) = [input_factor(fuel_prices[drive], bound), 1, 1,
        input_factor(:crew_cost, bound), 1,
        input_factor(:cargo_value, bound) * input_factor(:discount_rate, bound)]
    cases = Tuple{String, String, Union{Nothing, String}}[("VLSFO", "vlsfo", nothing),
        ("e-ammonia", "ammonia", nothing)]
    for (rig, column) in rig_area_columns
        push!(cases, ("e-ammonia + $rig", "ammonia", column))
    end
    labels = first.(cases)
    figure = Figure(size=(page_width, 140))
    for (panel, ship_length) in enumerate((85.0, 200.0))
        found = [cheapest_design(designs, drive, ship_length, column)
                 for (_, drive, column) in cases]
        values = [isnothing(k) ? 0.0 : 1e3 * designs[part][k] for k in found, part in parts]
        axis = Axis(figure[1, panel]; title="($(Char('a' + panel - 1))) $(round(Int,
                ship_length)) m ship", yticks=(eachindex(labels), labels), yreversed=true,
            xlabel="cost [USD per 1000 tkm]", yticklabelsvisible=panel == 1)
        positions = repeat(eachindex(labels), outer=length(parts))
        stack = repeat(eachindex(parts), inner=length(labels))
        barplot!(axis, positions, vec(values); stack, direction=:x, color=colours[stack])
        totals = vec(sum(values; dims=2))
        bounds = [[sum(values[i, :] .* bound_factors(drive, bound))
                   for bound in (:low, :high)] for (i, (_, drive, _)) in enumerate(cases)]
        rangebars!(axis, eachindex(labels), first.(bounds), last.(bounds); direction=:x,
            color=:black, linewidth=pt(0.6), whiskerwidth=pt(3))
        for (i, (k, case)) in enumerate(zip(found, cases))
            (isnothing(k) || isnothing(case[3])) && continue
            text!(axis, last(bounds[i]), i;
                text=square_metres("$(round(Int, designs[case[3]][k])) "),
                align=(:left, :center), offset=(pt(3), 0), fontsize=note_size)
        end
        xlims!(axis, 0, 1.15maximum(last.(bounds)))
    end
    Legend(figure[2, 1:2], [PolyElement(; color) for color in colours], names;
        orientation=:horizontal)
    rowgap!(figure.layout, 1, 6)
    save_figure("breakdown", figure)
end

"""
    gross_and_net_saving(table, class, drive, rig)

Mean over the routes of the cost saving [%] of the best size of `rig` on `class`, as it
stands (net) and if the ship carried the cargo of the same ship without a rig (gross).
"""
function gross_and_net_saving(table, class, drive, rig)
    gross, net = Float64[], Float64[]
    for route in unique(table["route"])
        conditions = ("class" => class, "route" => route, "drive" => drive)
        best = cheapest_row(table, conditions..., "rig" => rig)
        bare = rows(table, conditions..., "rig" => "none")
        (isnothing(best) || isempty(bare)) && continue
        saving_now = percent_saving(table["cost"][best], only(table["cost"][bare]))
        push!(net, saving_now)
        push!(gross, 100saving_at_bare_cargo(saving_now / 100, table["cargo"][best],
            only(table["cargo"][bare])))
    end
    return mean(gross), mean(net)
end

"""
    cargo_cost_figure()

Cost saving of the best size of each rig on e-ammonia for each ship class, per cargo-limit
group: the saving as it stands, solid, and what the cargo its rig displaces costs, pale,
which together make the saving if the ship carried its cargo as without a rig.
"""
function cargo_cost_figure()
    table = read_table(data_file("classes.csv"))
    groups = limit_groups(table)
    figure = Figure(size=(page_width, 235))
    largest = maximum(length.(last.(groups)))
    cells = [figure[1, 1], GridLayout(figure[1, 2])]
    axes = map(enumerate(groups)) do (column, (limit, names))
        axis = Axis(column == 1 ? cells[1] : cells[2][1, 1];
            title="($(Char('a' + column - 1))) $limit-limited", xlabel="cost saving [%]",
            yticks=(eachindex(names), names), yreversed=true,
            limits=(nothing, (0.45, length(names) + 0.55)))
        for (j, rig) in enumerate(rig_names), (i, name) in enumerate(names)
            gross, net = gross_and_net_saving(table, name, "ammonia", rig)
            y = i + (j - 2) * 0.26
            barplot!(axis, [y], [net]; direction=:x, color=palette[j], width=0.24)
            barplot!(axis, [y], [gross]; direction=:x, fillto=net, color=(palette[j], 0.3),
                width=0.24)
        end
        vlines!(axis, 0; color=:gray, linewidth=0.5)
        xlims!(axis, 0, nothing)
        return axis
    end
    linkxaxes!(axes...)
    Legend(cells[2][2, 1],
        [[PolyElement(color=palette[j]) for j in eachindex(rig_names)],
         [PolyElement(color=(palette[j], 0.3)) for j in eachindex(rig_names)]],
        [collect(rig_names), collect(rig_names)], ["saving", "lost to cargo"];
        orientation=:horizontal, nbanks=3, titleposition=:top, tellheight=false,
        halign=:right, valign=:bottom)
    Makie.update_state_before_display!(figure)
    axes[2].height = length(last(groups[2])) / largest * height(axes[1].scene.viewport[])
    save_figure("cargo_cost", figure)
end

"""
    canopy_life_figure()

Flight hours of canopies of data/canopy_life_statements.csv as ranges by what stated them,
with the derived life and its range of the assumptions, and the goal.
"""
function canopy_life_figure()
    lives = read_table(joinpath(root, "data", "canopy_life_statements.csv"))
    goal = assumptions.entries[:canopy_life]
    order = [findall(==("statement"), lives["kind"]);
        findall(==("sail_shape"), lives["kind"]); findall(==("small_kite"), lives["kind"]);
        findall(==("derived"), lives["kind"])]
    labels = lives["label"][order]
    figure = Figure(size=(page_width, 190))
    axis = Axis(figure[1, 1]; xscale=log10, xlabel="flight hours of the canopy",
        xticks=([100, 300, 1000, 3000, 10000], ["100", "300", "1000", "3000", "10000"]),
        yticks=(eachindex(labels), labels), yreversed=true,
        limits=((70, 20000), (0.3, length(labels) + 0.7)))
    vspan!(axis, goal.low, goal.high; color=(palette[1], 0.1))
    vlines!(axis, goal.value; color=:black, linewidth=0.75)
    text!(axis, goal.value, 0.5; text="goal", align=(:right, :top),
        offset=clear_offset((:right, :top), pt(2)), fontsize=note_size)
    for (i, row) in enumerate(order)
        derived = lives["kind"][row] == "derived"
        colour = derived ? palette[1] : :gray35
        low, high = derived ? (goal.low, goal.high) :
                    (lives["life_low"][row], lives["life_high"][row])
        rangebars!(axis, [i], [low], [high]; direction=:x, color=colour,
            linewidth=derived ? 2.5 : 1.5, whiskerwidth=derived || high < 1.1low ? 0 : 4)
        derived && scatter!(axis, [lives["life_low"][row]], [i]; color=colour, markersize=7)
        measured = lives["grade"][row] == "meas"
        lives["kind"][row] == "statement" && scatter!(axis, [sqrt(low * high)], [i];
            color=measured ? :gray35 : :white, strokecolor=:gray35, strokewidth=0.75,
            marker=:rect)
        label = derived ? "$(estimate_text(lives["life_low"][row])) " *
                          "($(estimate_text(low))–$(estimate_text(high)))" :
                replace(lives["life_text"][row], "--" => "–")
        crosses_goal = 1.15high < goal.value < 2.3high
        text!(axis, crosses_goal ? low / 1.15 : 1.15high, i; text=label,
            align=(crosses_goal ? :right : :left, :center), fontsize=note_size,
            color=colour)
    end
    entries = [MarkerElement(marker=:rect, color=:white, strokecolor=:gray35,
            strokewidth=0.75), MarkerElement(marker=:rect, color=:gray35),
        MarkerElement(marker='*', color=:gray35, markersize=pt(9)),
        LineElement(color=:black, linewidth=0.75),
        PolyElement(color=(palette[1], 0.1))]
    axislegend(axis, entries, ["claim", "measurement", "hours we estimate",
            "goal", "derived range"]; position=:lt)
    save_figure("canopy_life", figure)
end

"""
    large_rigs_figure()

Best kite area of every ship class on both drives against the largest kites and ram-air
wings built, and the median number of wing and rotor units against the most rotors in
service, the geometric mean over the routes and its range for the area.
"""
function large_rigs_figure()
    table = read_table(data_file("classes.csv"))
    names = class_order(table)
    routes_seen = unique(table["route"])
    flat_per_projected = 160 / 125
    flown, bound = 320 / flat_per_projected, largest_rig_area("kite", nothing)
    designed = (1000 / flat_per_projected, 1040)
    marks = ((flown, rich("largest ship kite flown\n(320 m", superscript("2"), " flat)"),
            :bottom),
        (first(designed), "largest ship kite designed,\nlargest cargo parachute",
            :bottom), (bound, "upper bound of the search", :top))
    rotors_in_service = 5
    figure = Figure(size=(page_width, 215))
    areas = Axis(figure[1, 1]; title="(a) best kite area", xscale=log10,
        xlabel=rich("projected area [m", superscript("2"), "]"),
        xticks=([100, 1000, 10000], ["100", "1000", "10000"]),
        yticks=(eachindex(names), names), yreversed=true,
        limits=((100, 30000), (0.3, length(names) + 0.7)))
    units = Axis(figure[1, 2]; title="(b) deck units at the best size", xlabel="units",
        yticks=(eachindex(names), names), yreversed=true, yticklabelsvisible=false,
        limits=((0, nothing), (0.3, length(names) + 0.7)))
    vspan!(areas, designed...; color=(:gray50, 0.25))
    vlines!(areas, flown; color=:gray50, linewidth=0.5)
    vlines!(areas, bound; color=:gray50, linewidth=0.5, linestyle=:dash)
    for (area, label, anchor) in marks
        text!(areas, area, anchor == :top ? 0.4 : length(names) + 0.65; text=label,
            rotation=π / 2, align=(anchor == :top ? :right : :left, :bottom),
            offset=(-pt(2), 0), fontsize=note_size, color=:gray35)
    end
    for (k, (drive, _)) in enumerate(drive_panels)
        for (i, name) in enumerate(names)
            values = filter(isfinite, [best_area(table, name, route, drive, "kite")
                                       for route in routes_seen])
            isempty(values) && continue
            y = i + (k - 1.5) * 0.3
            rangebars!(areas, [y], [minimum(values)], [maximum(values)]; direction=:x,
                color=(palette[1], k == 2 ? 0.8 : 0.35))
            scatter!(areas, [geometric_mean(values)], [y];
                color=k == 2 ? palette[1] : :white, strokecolor=palette[1],
                strokewidth=0.75)
            maximum(values) >= bound && scatter!(areas, [1.15bound], [y];
                marker=:rtriangle, color=(palette[1], k == 2 ? 0.8 : 0.35),
                markersize=pt(5))
        end
    end
    vlines!(units, rotors_in_service; color=:gray70, linewidth=0.5)
    text!(units, rotors_in_service, length(names) + 0.65; text="most rotors in service",
        rotation=π / 2, align=(:left, :bottom), offset=(-pt(2), 0), fontsize=note_size,
        color=:gray35)
    for (i, name) in enumerate(names), (j, rig) in zip((2, 3), ("wings", "rotors"))
        scatter!(units, [median_units(table, name, "ammonia", rig)],
            [i + (j - 2.5) * 0.3]; color=palette[j])
    end
    xlims!(units, 0, nothing)
    axislegend(units, [MarkerElement(marker=:circle, color=:white,
            strokecolor=palette[1], strokewidth=0.75),
        MarkerElement(marker=:circle, color=palette[1]),
        MarkerElement(marker=:rtriangle, color=palette[1], markersize=pt(5)),
        MarkerElement(marker=:circle, color=palette[2]),
        MarkerElement(marker=:circle, color=palette[3])],
        ["(a) kite on VLSFO", "(a) kite on e-ammonia", "(a) range cut by the bound",
            "(b) wing sails", "(b) rotors"]; position=:rt)
    save_figure("large_rigs", figure)
end

"""
    capital_parts(ships, drive, inputs)

Capital [million USD] in `inputs` of the hull with its basic drive, the extra cost of a
dual-fuel e-ammonia engine on `drive`, and the rig, from `ships`: the ship on VLSFO and on
e-ammonia, both without a rig, and the ship shown.
"""
function capital_parts(ships, drive, inputs)
    basic, dual_fuel, capital = (WindShipOpt.ShipCosts(ship, inputs).capital
                                 for ship in ships)
    premium = drive == :vlsfo ? 0.0 : dual_fuel - basic
    return [basic, premium, capital - basic - premium] ./ 1e6
end

"""
    capital_figure()

Capital of an 85 m and a 170 m ship split into the hull with its basic drive, the extra
cost of a dual-fuel e-ammonia engine, and the rig, with the range of the hull and of the
rig over the bounds of the inputs one at a time; the fuel tank, sized by the route, is
left out.
"""
function capital_figure()
    cases = [("VLSFO", :vlsfo, (;)), ("e-ammonia", :ammonia, (;)),
        ("+ kite 1600 m²", :ammonia, (kite_area=1600.0,)),
        ("+ wing sails 800 m²", :ammonia, (wing_area=800.0,)),
        ("+ rotors 400 m²", :ammonia, (rotor_area=400.0,))]
    labels = String[]
    values = Matrix{Float64}(undef, 0, 3)
    lows, highs = similar(values), similar(values)
    for length in (85.0, 170.0), (label, drive, rig) in cases
        ships = [Ship(design, assumptions) for design in (ShipDesign(:vlsfo, length),
            ShipDesign(:ammonia, length), ShipDesign(drive, length; rig...))]
        spread = reduce(hcat, [capital_parts(ships, drive,
            WindShipOpt.with_value(assumptions, name, bound))
                               for (name, entry) in assumptions.entries
                               for bound in (entry.low, entry.high)])
        push!(labels, "$label, $(round(Int, length)) m")
        values = vcat(values, capital_parts(ships, drive, assumptions)')
        lows = vcat(lows, minimum(spread; dims=2)')
        highs = vcat(highs, maximum(spread; dims=2)')
    end
    figure = Figure(size=(column_width, 318))
    axis = Axis(figure[1, 1]; yticks=(eachindex(labels), labels), yreversed=true,
        xlabel="capital [million USD]", limits=((0, nothing), nothing))
    positions = repeat(eachindex(labels), outer=3)
    stack = repeat(1:3, inner=length(labels))
    rig_colours = repeat([:gray; :gray; palette[eachindex(rig_names)]], 2)
    engine_colour = category_colours[2]
    colours = [[:gray55 for _ in labels]; [engine_colour for _ in labels]; rig_colours]
    barplot!(axis, positions, vec(values); stack, direction=:x, color=colours)
    start = values[:, 1] .+ values[:, 2]
    rigged = values[:, 3] .> 0
    rangebars!(axis, eachindex(labels) .- 0.2, lows[:, 1], highs[:, 1]; direction=:x,
        color=:black, linewidth=0.8, whiskerwidth=3)
    rangebars!(axis, findall(rigged) .+ 0.2, start[rigged] .+ lows[rigged, 3],
        start[rigged] .+ highs[rigged, 3]; direction=:x, color=:black, linewidth=0.8,
        whiskerwidth=3)
    names = ["hull and basic drive", "e-ammonia engine", "kite", "wing sails", "rotors"]
    axislegend(axis, [PolyElement(color=:gray55); PolyElement(color=engine_colour);
            [PolyElement(color=palette[k]) for k in eachindex(rig_names)]], names;
        position=:rt)
    save_figure("capital", figure)
end

"""
    situation_cost(table, ship, route, drive, input, value, rig)

Lowest cost [USD/tkm] of any size of `rig` (or the ship without a rig for "none") in
situations.csv with `input` at `value`, taken at the base inputs where the input leaves
that rig's cost unchanged; `Inf` where no size is feasible.
"""
function situation_cost(table, ship, route, drive, input, value, rig)
    changed = input != :base && value != base_value(input) &&
              rig in last(situation_inputs[input])
    chosen = rows(table, "ship" => ship, "route" => string(route),
        "drive" => string(drive), "input" => changed ? string(input) : "base",
        "value" => changed ? value : 0.0, "rig" => rig)
    return isempty(chosen) ? Inf : minimum(table["cost"][chosen])
end

"""
    situation_savings(table, ship, route, drive, input)

Values of `input`, base included, and the cost saving [%] of the best size of the kite,
the wings and the rotors at each, as a matrix with one row per rig; NaN where no size is
feasible.
"""
function situation_savings(table, ship, route, drive, input)
    values = sort([base_value(input); collect(first(situation_inputs[input]))])
    savings = fill(NaN, 3, length(values))
    for (j, value) in enumerate(values), (i, rig) in enumerate(rig_names)
        bare = situation_cost(table, ship, route, drive, input, value, "none")
        cost = situation_cost(table, ship, route, drive, input, value, rig)
        isfinite(cost) && (savings[i, j] = percent_saving(cost, bare))
    end
    return values, savings
end

"""
    leader_starts(positions, savings)

Positions from which each leading rig (row of `savings`) saves most, as (start, row), with
the boundaries where the lead changes interpolated linearly in `positions`.
"""
function leader_starts(positions, savings)
    leaders = [argmax(replace(savings[:, j], NaN => -Inf)) for j in eachindex(positions)]
    starts = Tuple{Float64, Int}[]
    start = first(positions)
    for j in 1:(length(positions) - 1)
        before, after = leaders[j], leaders[j + 1]
        before == after && continue
        gap_left = savings[before, j] - savings[after, j]
        gap_right = savings[before, j + 1] - savings[after, j + 1]
        share = all(isfinite, (gap_left, gap_right)) ? gap_left / (gap_left - gap_right) :
                0.5
        crossing = positions[j] + share * (positions[j + 1] - positions[j])
        push!(starts, (start, before))
        start = crossing
    end
    push!(starts, (start, last(leaders)))
    return starts
end

"""
    print_leaders(name, input, positions, savings, to_value)

Print the input value from which each rig of `savings` leads; `to_value` maps
`positions` back to input values.
"""
function print_leaders(name, input, positions, savings, to_value)
    leads = [(round(to_value(start); sigdigits=3), rig_names[row])
             for (start, row) in leader_starts(positions, savings)]
    println("  ", name, ", ", input, ": ", join(["$rig from $value" for (value, rig) in
                                                leads], ", "))
end

"legend entries of the best size of each rig: a line, with a marker where `markers`"
rig_entries(markers) = [markers ? [LineElement(; color),
                            MarkerElement(; color, marker=:circle)] :
                        LineElement(; color) for color in palette[eachindex(rig_names)]]

"""
Panels of the situation figure as (title, x label, inputs with their drive, scale of the
x axis, factor from value to axis, x ticks); the fuel panel joins VLSFO and e-ammonia
prices.
"""
situation_panels = [
    ("fuel price", "fuel price [USD/GJ]",
        [(:vlsfo_price, :vlsfo), (:e_ammonia_price, :ammonia)], log10, 1.0,
        [8, 15, 30, 60, 120]),
    ("cargo value", "cargo value [1000 USD/t]", [(:cargo_value, :ammonia)], log10, 1e-3,
        ([1, 2.5, 5, 10, 20], ["1", "2.5", "5", "10", "20"])),
    ("discount rate", "discount rate [%]", [(:discount_rate, :ammonia)], identity, 100.0,
        Makie.automatic),
    ("wing life", "wing life [years]", [(:wing_lifetime, :ammonia)], identity, 1.0,
        Makie.automatic),
    ("wing price", "wing price [× base]", [(:wing_price, :ammonia)], identity, 1.0,
        Makie.automatic),
    ("rotor speed", "highest surface speed [m/s]",
        [(:rotor_max_surface_speed, :ammonia)], identity, 1.0, Makie.automatic)]

"ship, route and line style of each ship of the situation figure"
situation_ships = [("140 m", :caribbean, :solid), ("Kamsarmax bulk carrier", :tubarao,
    (:dash, :loose))]

"""
    studied(ship, route, drive, input)

Whether `situation_studies` varies `input` on `ship`, `route` and `drive`.
"""
function studied(ship, route, drive, input)
    for (study_ship, study_route, study_drive, inputs) in situation_studies
        (study_ship, study_route, study_drive) == (ship, route, drive) &&
            input in inputs && return true
    end
    return false
end

"""
    situations_figure()

Cost saving of the best size of each rig on the 140 m e-ammonia ship to Guadeloupe
(solid, filled markers) and a Kamsarmax to Tubarão (dashed, open markers) with one input
changed at a time, on one scale, the fuel price on VLSFO below 30 USD/GJ and on e-ammonia
above; thin grey lines mark the base inputs. Prints where the lead changes.
"""
function situations_figure()
    table = read_table(data_file("situations.csv"))
    figure = Figure(size=(page_width, 380))
    shown = Float64[]
    fuel_switches = []
    axes = map(enumerate(situation_panels)) do (k, (title, xlabel, inputs, scale, factor,
        xticks))
        axis = Axis(figure[(k - 1) ÷ 4 + 1, (k - 1) % 4 + 1];
            title="($('a' + k - 1)) $title", xlabel, xscale=scale, xticks,
            ylabel=(k - 1) % 4 == 0 ? "cost saving [%]" : "",
            yticklabelsvisible=(k - 1) % 4 == 0)
        hlines!(axis, 0; color=:gray50, linewidth=0.6)
        if length(inputs) > 1
            switch = factor * first(situation_inputs[first(last(inputs))][1])
            vspan!(axis, switch, factor * last(situation_inputs[first(last(inputs))][1]);
                color=(:gray50, 0.1))
            push!(fuel_switches, (axis, switch))
        end
        for (ship, route, linestyle) in situation_ships, (input, drive) in inputs
            studied(ship, route, drive, input) || continue
            values, savings = situation_savings(table, ship, route, drive, input)
            x = factor .* values
            inverse = scale == log10 ? exp10 : identity
            print_leaders(ship, input, scale.(x), savings, value -> inverse(value) / factor)
            append!(shown, filter(isfinite, savings))
            ship == "140 m" && vlines!(axis, factor * base_value(input); color=:gray50,
                linewidth=rule_width, ymax=0.88)
            for rig in 1:3
                lines!(axis, x, savings[rig, :]; color=palette[rig], linestyle)
                scatter!(axis, x, savings[rig, :]; color=linestyle == :solid ?
                    palette[rig] : :white, strokecolor=palette[rig],
                    strokewidth=rule_width)
            end
        end
        axis
    end
    linkyaxes!(axes...)
    low, high = extrema(shown)
    top = high + 0.1 * (high - low)
    ylims!(first(axes), low - 0.05 * (high - low), top)
    for (axis, switch) in fuel_switches,
        (label, align) in (("VLSFO", (:right, :top)), ("e-ammonia", (:left, :top)))
        text!(axis, switch, top; text=label, align, fontsize=note_size, color=:gray30,
            offset=clear_offset(align, pt(2)))
    end
    ships = [[LineElement(; color=:black, linestyle),
        MarkerElement(color=linestyle == :solid ? :black : :white, strokecolor=:black,
            strokewidth=rule_width, marker=:circle)]
             for (_, _, linestyle) in situation_ships]
    Legend(figure[2, 3:4],
        [rig_entries(true); ships; LineElement(color=:gray50, linewidth=rule_width)],
        ["best kite", "best wing sails", "best rotors", "140 m, Guadeloupe",
            "Kamsarmax, Tubarão", "base input"]; tellheight=false, tellwidth=false,
        halign=:left, valign=:bottom)
    save_figure("situations", figure)
end

"e-fuels of the fuel figure as (price input, drive, label, line style)"
fuel_lines = [(:e_ammonia_price, :ammonia, "e-ammonia", :solid),
    (:e_methanol_price, :methanol, "e-methanol", (:dash, :loose))]

"""
    fuel_figure()

Cost saving of the best size of each rig over the fuel price on each ship of the situation
study, on e-ammonia and on e-methanol, each at the prices of the situation study, with
each fuel's price range and base value in a strip below. Prints where the lead changes.
"""
function fuel_figure()
    table = read_table(data_file("situations.csv"))
    figure = Figure(size=(page_width, 240))
    axes = map(enumerate(situation_ships)) do (k, (ship, route, _))
        axis = Axis(figure[1, k]; title="($('a' + k - 1)) $ship, $(route_label(route))",
            xscale=log10, ylabel=k == 1 ? "cost saving [%]" : "")
        for (input, drive, label, linestyle) in fuel_lines
            values, savings = situation_savings(table, ship, route, drive, input)
            print_leaders("$ship, $label", input, log10.(values), savings, exp10)
            for rig in 1:3
                scatterlines!(axis, values, savings[rig, :]; color=palette[rig], linestyle,
                    markersize=0.8marker_size)
            end
        end
        prices = Axis(figure[2, k]; xscale=log10, xticks=[30, 45, 60, 90, 120],
            xlabel="fuel price [USD/GJ], logarithmic", height=pt(14),
            limits=(nothing, (0.4, length(fuel_lines) + 0.6)), yticksvisible=false,
            yticklabelsvisible=false, bottomspinevisible=true, topspinevisible=false,
            leftspinevisible=false, rightspinevisible=false)
        for (j, (input, _, _, linestyle)) in enumerate(fuel_lines)
            price = assumptions.entries[input]
            lines!(prices, [price.low, price.high], [j, j]; color=:black, linestyle,
                linewidth=pt(0.8))
            scatter!(prices, [price.value], [j]; color=:black, marker=:vline,
                markersize=pt(5))
        end
        linkxaxes!(axis, prices)
        hidexdecorations!(axis; ticks=false)
        return axis
    end
    rowgap!(figure.layout, 1, pt(3))
    axislegend(axes[2], rig_entries(false), ["kite", "wings", "rotors"];
        position=:lt, orientation=:horizontal)
    axislegend(axes[1], [LineElement(color=:black, linestyle=style)
                         for (_, _, _, style) in fuel_lines],
        [label for (_, _, label, _) in fuel_lines]; position=:rb)
    save_figure("fuels", figure)
end

"""
    aspect_figure()

Saving of the kite of each study ship against its aspect ratio, at the same area and the
same price.
"""
function aspect_figure()
    table = read_table(data_file("aspect.csv"))
    figure = Figure(size=(column_width, 200))
    axis = Axis(figure[1, 1]; xlabel="kite aspect ratio", ylabel="cost saving [%]",
        xticks=collect(study_aspect_ratios))
    for (k, ship) in enumerate(unique(table["ship"]))
        chosen = rows(table, "ship" => ship)
        bare = table["cost"][only(filter(row -> table["aspect_ratio"][row] == 0, chosen))]
        kites = filter(row -> table["aspect_ratio"][row] > 0, chosen)
        savings = percent_saving.(table["cost"][kites], bare)
        scatterlines!(axis, table["aspect_ratio"][kites], savings;
            color=category_colours[k], label=ship)
    end
    Legend(figure[2, 1], axis; orientation=:horizontal, nbanks=2)
    save_figure("aspect", figure)
end

"""
    best_force_rating_saving(table, ship, rating, exponent, areas, bare)

Highest saving [%] over `areas` in force_rating.csv of `ship`, costing `bare` without a rig,
with a kite built for `rating` whose cloth follows the limit to the power `exponent`.
"""
function best_force_rating_saving(table, ship, rating, exponent, areas, bare)
    chosen = rows(table, "ship" => ship, "rating" => rating, "exponent" => exponent)
    return maximum(percent_saving(table["cost"][row], bare)
                   for row in chosen if table["area"][row] in areas)
end

"""
    force_rating_figure()

Saving of each study ship at its best kite area against the force limit, with cloth that
follows the limit by the base exponent, in proportion, or not at all, each over the kite
areas that cloth law was run at.
"""
function force_rating_figure()
    table = read_table(data_file("force_rating.csv"))
    figure = Figure(size=(column_width, 215))
    axis = Axis(figure[1, 1]; xlabel="force limit [kN/m²]",
        ylabel="cost saving [%]", xticks=collect(study_force_ratings))
    base = assumptions[:canopy_cloth_force_exponent]
    reference = assumptions[:canopy_cloth_reference_force]
    laws = ((base, :solid, "keeps its life"), (1.0, :dash, "in proportion"),
        (0.0, :dot, "fixed at 200 g/m²"))
    ships = unique(table["ship"])
    for (k, ship) in enumerate(ships)
        bare = table["cost"][only(rows(table, "ship" => ship, "rating" => 0))]
        for (exponent, linestyle, _) in laws
            ratings = exponent == base ? collect(study_force_ratings) :
                      sort([extrema(study_force_ratings)..., reference])
            areas = Set(table["area"][rows(table, "ship" => ship, "exponent" => exponent)])
            savings = [best_force_rating_saving(table, ship, rating,
                           rating == reference ? base : exponent, areas, bare)
                       for rating in ratings]
            lines!(axis, ratings, savings; color=category_colours[k], linestyle)
        end
    end
    ship_entries = [LineElement(color=category_colours[k]) for k in eachindex(ships)]
    law_entries = [LineElement(; color=:black, linestyle)
                   for (_, linestyle, _) in laws]
    Legend(figure[2, 1], [ship_entries, law_entries], [ships, collect(last.(laws))],
        ["ship", "cloth"]; orientation=:horizontal, nbanks=3, titleposition=:left,
        titlegap=6)
    rowgap!(figure.layout, 1, 6)
    save_figure("force_rating", figure)
end

"""
    band_totals(table, rig, column; route=nothing, direction=nothing)

Sum of `column` of wind_angle.csv for `rig` in each band of `angle_bands`, over every
route and direction or only the given ones.
"""
function band_totals(table, rig, column; route=nothing, direction=nothing)
    conditions = ["rig" => rig]
    isnothing(route) || push!(conditions, "route" => route)
    isnothing(direction) || push!(conditions, "direction" => direction)
    return [sum(table[column][rows(table, conditions..., "band" => name)]; init=0.0)
            for (name, _, _) in angle_bands]
end

"opacities of the true-wind-angle bands in stacked bars, upwind darkest"
band_alphas = (1.0, 0.55, 0.22)

"""
    wind_angle_figure()

Where the wind comes from and where each rig pulls, from the routed round trips of the
140 m e-ammonia ship on every route: (a) share of time at sea of the ship without a rig
in each true-wind-angle band, outbound and homeward; (b) mean thrust of the reference
size of each rig in each band over all routes; (c) share of each rig's propulsive work
from each band per route; (d) mean thrust over the rig's cost per day at sea.
"""
function wind_angle_figure()
    table = read_table(data_file("wind_angle.csv"))
    names = route_order
    rigs = [(rig, round(Int, area)) for (rig, area) in reference_rigs]
    figure = Figure(size=(page_width, 380))
    ticks = (eachindex(names), route_label.(names))
    time_axis = Axis(figure[1, 1]; title="(a) time at sea without a rig, out and home",
        ylabel="share of time [%]", xticks=ticks, xticklabelrotation=π / 6)
    for (i, name) in enumerate(names),
        (offset, direction) in ((-0.2, "out"), (0.2, "home"))

        hours = band_totals(table, "none", "hours"; route=name, direction)
        stacked_bar!(time_axis, i + offset, 100 .* hours ./ sum(hours), 0.36, :gray25)
    end
    thrust_axis = Axis(figure[1, 2]; title="(b) mean thrust, all routes",
        ylabel="thrust [kN]",
        xticks=(eachindex(angle_bands), ["$(round(Int, low))–$(round(Int, high))°\n$name"
                                         for (name, low, high) in angle_bands]))
    highest = 0.0
    for (j, (rig, _)) in enumerate(rigs)
        thrust = band_totals(table, rig, "thrust_hours") ./ band_totals(table, rig, "hours")
        barplot!(thrust_axis, eachindex(angle_bands) .+ (j - 2) * 0.27, thrust;
            width=0.25, color=palette[j])
        highest = max(highest, maximum(thrust))
    end
    ylims!(thrust_axis, 0, 1.45highest)
    work_axis = Axis(figure[2, 1]; title="(c) share of each rig's work by band",
        ylabel="share of work [%]", xticks=ticks, xticklabelrotation=π / 6)
    cost_axis = Axis(figure[2, 2]; title="(d) mean thrust per rig cost",
        ylabel="kN/(1000 USD/day)", xticks=ticks, xticklabelrotation=π / 6)
    for (i, name) in enumerate(names), (j, (rig, _)) in enumerate(rigs)
        work = band_totals(table, rig, "work"; route=name)
        stacked_bar!(work_axis, i + (j - 2) * 0.28, 100 .* work ./ sum(work), 0.25,
            palette[j])
        chosen = rows(table, "rig" => rig, "route" => name)
        thrust = sum(table["thrust_hours"][chosen]) / sum(table["hours"][chosen])
        per_day = 24 * first(table["rig_cost"][chosen]) / 1e3
        barplot!(cost_axis, [i + (j - 2) * 0.27], [thrust / per_day]; width=0.25,
            color=palette[j])
    end
    hidexdecorations!(time_axis; ticks=false, ticklabels=false)
    Legend(figure[3, 1:2], [PolyElement(color=(:gray25, alpha)) for alpha in band_alphas],
        ["$name $(round(Int, low))–$(round(Int, high))°"
         for (name, low, high) in angle_bands],
        "true wind angle, darkest upwind in each colour";
        orientation=:horizontal, titleposition=:left)
    axislegend(thrust_axis, [PolyElement(color=palette[j]) for j in eachindex(rigs)],
        [square_metres("$rig $area ") for (rig, area) in rigs]; position=:lt)
    save_figure("wind_angle", figure)
end

"""
    stacked_bar!(axis, x, shares, width, colour)

One bar at `x` stacked from `shares` [%] of the true-wind-angle bands, in `colour` at
the opacities of `band_alphas`.
"""
function stacked_bar!(axis, x, shares, width, colour)
    barplot!(axis, fill(x, length(shares)), shares; stack=eachindex(shares),
        color=[(colour, alpha) for alpha in band_alphas], width)
end

"""
    abatement_figure()

Cost per tonne-km against the fuel energy saved, relative to the same ship on the same
drive without a rig, over every size of each rig on the [`abatement_ships`](@ref), one
panel per ship and drive, all on one fuel axis and each drive on one cost axis; markers
grow with rig area, keyed in (a), and below zero the rig pays.
"""
function abatement_figure()
    table = read_table(data_file("abatement.csv"))
    figure = Figure(size=(page_width, 380))
    panels = Matrix{Axis}(undef, length(abatement_ships), length(drive_labels))
    for (row, (name, _)) in enumerate(abatement_ships),
        (column, (drive, label)) in enumerate(drive_labels)

        bare = only(rows(table, "ship" => name, "drive" => drive, "rig" => "none"))
        letter = 'a' + length(drive_labels) * (row - 1) + column - 1
        axis = panels[row, column] = Axis(figure[row, column];
            title="($letter) $(replace(name, " bulk carrier" => "")), $label",
            xlabel=row == 2 ? "fuel energy saved [%]" : "",
            ylabel=column == 1 ? "cost change [%]" : "",
            xticklabelsvisible=row == 2)
        hspan!(axis, -100, 0; color=(:gray, 0.08))
        hlines!(axis, 0; color=:gray50, linewidth=0.6)
        for (k, rig) in enumerate(rig_names)
            chosen = rows(table, "ship" => name, "drive" => drive, "rig" => rig)
            chosen = chosen[sortperm(table["area"][chosen])]
            saved = 100 .* (1 .- table["fuel"][chosen] ./ table["fuel"][bare])
            change = 100 .* (table["cost"][chosen] ./ table["cost"][bare] .- 1)
            areas = table["area"][chosen]
            lines!(axis, saved, change; color=(palette[k], 0.6), linewidth=0.9)
            scatter!(axis, saved, change; color=palette[k], marker=rig_markers[k],
                markersize=area_marker_size.(areas))
        end
    end
    saved_all = [100 * (1 - table["fuel"][i] / table["fuel"][only(rows(table, "ship" =>
        table["ship"][i], "drive" => table["drive"][i], "rig" => "none"))])
                 for i in eachindex(table["fuel"])]
    for column in axes(panels, 2)
        drive = first(drive_labels[column])
        limits = [abatement_limits(table, name, drive, only(rows(table, "ship" => name,
            "drive" => drive, "rig" => "none"))) for (name, _) in abatement_ships]
        for axis in panels[:, column]
            limits!(axis, min(0, minimum(saved_all) - 0.04 * maximum(saved_all)),
                1.08 * maximum(saved_all), minimum(first.(limits)), maximum(last.(limits)))
        end
    end
    axislegend(panels[1, 2],
        [[LineElement(color=(palette[k], 0.6), linewidth=0.9),
          MarkerElement(color=palette[k], marker=rig_markers[k])]
         for k in eachindex(rig_names)],
        collect(rig_names); position=:rt)
    key_areas = (200, 800, 3200, 12800)
    axislegend(panels[1, 1],
        [MarkerElement(color=:gray40, marker=:circle, markersize=area_marker_size(area))
         for area in key_areas], ["$area" for area in key_areas], L"\mathrm{m^2}";
        position=:rb, orientation=:horizontal, titleposition=:left)
    save_figure("abatement", figure)
end

"markers of the kite, wings and rotors, in the order of `rig_names`, told apart by shape"
rig_markers = (:circle, :rect, :utriangle)

"marker size [figure units] of a rig of `area` [m²], growing with its logarithm"
area_marker_size(area) = pt(1.5) + pt(0.9) * log2(area / 100)

"""
    abatement_limits(table, ship, drive, bare)

Cost-change limits [%] of an [`abatement_figure`](@ref) panel: every rig size with a margin,
and zero.
"""
function abatement_limits(table, ship, drive, bare)
    chosen = rows(table, "ship" => ship, "drive" => drive)
    change = 100 .* (table["cost"][chosen] ./ table["cost"][bare] .- 1)
    low, high = min(minimum(change), 0.0), max(maximum(change), 0.0)
    margin = 0.1 * (high - low)
    return low - margin, high + margin
end

"`rig` as the text names it"
rig_label(rig) = replace(rig, "wings" => "wing sails")

"""
    development_panel!(axis, table, ships, levers, rig, column)

Bars in `axis` of the change of the saving of `rig` in `column` between the low and high
bound of each of `levers`, one per ship in the colours of `category_colours`, with the
high bound marked, and a tick in the ship's colour where neither bound moves it.
"""
function development_panel!(axis, table, ships, levers, rig, column)
    vlines!(axis, 0; color=:gray70, linewidth=rule_width)
    for (k, entry) in enumerate(levers), (j, ship) in enumerate(ships)
        low, high = bound_changes(table, ship, rig, string(entry.input); column)
        isfinite(low + high) || continue
        y = k + (2 - j) * 0.27
        if abs(high) + abs(low) < 0.01
            scatter!(axis, [0.0], [y]; marker=:vline, color=category_colours[j],
                markersize=pt(7), strokecolor=category_colours[j], strokewidth=pt(0.6))
            continue
        end
        barplot!(axis, [y], [high - low]; offset=low, direction=:x, width=0.22,
            color=category_colours[j])
        scatter!(axis, [high], [y]; marker=:vline, color=:black, markersize=pt(7))
    end
end

"""
    sensitivity_figure()

Where development pays: for each rig the inputs of [`development_inputs`](@ref) that move
it, largest effect on top, with the change of its saving of cost per tonne-km (left) and of
CO2 per tonne-km (right) between the bounds of each input on each ship of the study, on one
scale per column.
"""
function sensitivity_figure()
    table = read_table(data_file("sensitivity.csv"))
    ships = unique(table["ship"])
    panels = [filter(entry -> rig in lever_rigs(entry), development_inputs)
              for rig in rig_names]
    for (levers, rig) in zip(panels, rig_names)
        sort!(levers; by=entry -> maximum(ship -> abs(-(bound_changes(table, ship, rig,
            string(entry.input))...)), ships))
    end
    figure = Figure(size=(page_width, 500))
    columns = [("cost", "change of cost saving [points]", 2),
        ("carbon", rich("change of CO", subscript("2"), " saving [points]"), 5)]
    for (column, (name, label, step)) in enumerate(columns)
        changes = [change for (levers, rig) in zip(panels, rig_names) for entry in levers
                   for ship in ships
                   for change in bound_changes(table, ship, rig, string(entry.input);
                       column=name) if isfinite(change)]
        low, high = min(minimum(changes), 0), max(maximum(changes), 0)
        margin = 0.06 * (high - low)
        for (row, (rig, levers)) in enumerate(zip(rig_names, panels))
            letter = 'a' + 2 * (row - 1) + column - 1
            title = column == 1 ?
                    rich("($letter) $(rig_label(rig)), cost",
                subscript("2"; color=:transparent)) :
                    rich("($letter) $(rig_label(rig)), CO", subscript("2"))
            axis = Axis(figure[row, column]; title,
                yticks=(eachindex(levers), [entry.label for entry in levers]),
                yticksvisible=column == 1, yticklabelsvisible=column == 1,
                xlabel=row == length(rig_names) ? label : "",
                xticks=step * (ceil(low / step):floor(high / step)),
                limits=((low - margin, high + margin), (0.4, length(levers) + 0.6)))
            development_panel!(axis, table, ships, levers, rig, name)
            row == 2 && column == 2 && axislegend(axis,
                [[PolyElement(color=category_colours[j]) for j in eachindex(ships)];
                    [MarkerElement(marker=:vline, color=:black, markersize=pt(7))]],
                [short_ship.(ships); "high end of range"]; position=:lb)
            rowsize!(figure.layout, row, Auto(length(levers)))
        end
    end
    save_figure("sensitivity", figure)
end

"plans of the forecast figure's saving panel, as (plan of forecast_plans.csv, label)"
forecast_figure_plans = (("false", "perfect foresight"),
    ("members", "several forecast members"), ("true", "one forecast run"))

"""
    forecast_figure()

(a) Mean cost saving over the departures, with its standard error, of each rig on a 140 m
e-ammonia ship per plan of [`forecast_figure_plans`](@ref), a plan with no feasible round
trip marked "none" in place of its bar; (b, c) root mean square error of the archived
forecasts' wind and wave height along the route against lead time, beside that of the same
date in another year.
"""
function forecast_figure()
    table = read_table(data_file("forecast_plans.csv"))
    figure = Figure(size=(page_width, 180))
    axis = Axis(figure[1, 1]; xticks=(1:3, ["kite", "wing sails", "rotors"]),
        ylabel="cost saving [%]", title="(a) saving")
    plan_alphas = (1.0, 0.6, 0.3)
    tops = Float64[]
    for (j, (plan, _)) in enumerate(forecast_figure_plans)
        savings = [forecast_saving(table, rig, plan) for rig in rig_names]
        positions = (1:3) .+ (j - 2) * 0.27
        routed = isfinite.(first.(savings))
        means, errors = first.(savings[routed]), last.(savings[routed])
        barplot!(axis, positions[routed], means; width=0.25,
            color=[(palette[rig], plan_alphas[j]) for rig in findall(routed)])
        errorbars!(axis, positions[routed], means, errors; color=:black,
            whiskerwidth=pt(3), linewidth=rule_width)
        append!(tops, means .+ errors)
        unrouted = count(.!routed)
        text!(axis, positions[.!routed], zeros(unrouted); text=fill("none", unrouted),
            rotation=pi / 2, align=(:left, :center), fontsize=note_size, color=:gray30)
    end
    ylims!(axis, 0, 1.7 * maximum(tops))
    rig_patch(rig) = Point2f[((rig - 1) / 3, 0), (rig / 3, 0), (rig / 3, 1),
        ((rig - 1) / 3, 1)]
    axislegend(axis, [[PolyElement(color=(palette[rig], alpha), points=rig_patch(rig))
                       for rig in 1:3] for alpha in plan_alphas],
        collect(last.(forecast_figure_plans)); position=:lt)
    errors = read_table(data_file("forecast_error.csv"))
    for (column, (quantity, unit)) in enumerate((("wind", "m/s"), ("height", "m")))
        panel = Axis(figure[1, column + 1]; xlabel="lead time [days]",
            ylabel="rms error [$unit]",
            title=column == 1 ? "(b) wind at 10 m" : "(c) wave height")
        forecast = lines!(panel, errors["lead_days"], errors["$(quantity)_forecast"];
            color=:black)
        other_year = lines!(panel, errors["lead_days"], errors["$(quantity)_other_year"];
            color=:gray50, linestyle=:dash)
        ylims!(panel, 0, 1.2 * maximum([errors["$(quantity)_forecast"];
            errors["$(quantity)_other_year"]]))
        column == 2 && axislegend(panel, [forecast, other_year],
            ["archived forecast", "same date, other year"]; position=:rb)
    end
    save_figure("forecast", figure)
end

"""
    forecast_saving(table, rig, plan)

Mean over the departures of the cost saving [%] of `rig` on `plan`, against the ship
without a rig on the same plan, with its standard error, `(NaN, NaN)` where the two cannot
be paired: a departure without a feasible round trip is no row of the table.
"""
function forecast_saving(table, rig, plan)
    cost(name) = table["cost"][rows(table, "rig" => name, "plan" => plan)]
    length(cost(rig)) == length(cost("none")) || return (NaN, NaN)
    savings = 100 .* (1 .- cost(rig) ./ cost("none"))
    return (mean(savings), std(savings) / sqrt(length(savings)))
end

"rigs of the combination figure with their legend labels and colours"
combination_rigs = (("kite", "best kite", palette[1]),
    ("rotors", "best rotors", palette[3]),
    ("kite+rotors", "best kite and rotors together", kite_and_rotors_fill()))

"""
    combination_figure()

Cost saving against no rig of the best kite, the best rotors and the best of the pairs on
each class and drive of combination_pairs.csv, and that pair's saving over the better
single rig against twice its noise, the root mean square of [`pair_gain_errors`](@ref), each
as the mean over the routes with their range. Prints the means, the share of the summed
savings the pair keeps and the noise.
"""
function combination_figure()
    table = read_table(data_file("combination_pairs.csv"))
    groups = vec([(ship, drive) for drive in ("vlsfo", "ammonia"), ship in pair_classes])
    labels = ["$(replace(ship, " bulk carrier" => ""))\n$(Dict(drive_labels)[drive])"
              for (ship, drive) in groups]
    figure = Figure(size=(page_width, 310))
    saving_axis = Axis(figure[1, 1]; title="(a) cost saving against no rig",
        ylabel="cost saving [%]")
    gain_axis = Axis(figure[2, 1]; title="(b) pair over the better single rig",
        xticks=(eachindex(groups), labels), ylabel="extra saving [% points]")
    linkxaxes!(saving_axis, gain_axis)
    hidexdecorations!(saving_axis)
    rowsize!(figure.layout, 2, Relative(0.4))
    errors = pair_gain_errors(read_table(data_file("combination_departures.csv")))
    gain_noise = sqrt(mean(abs2, errors))
    hspan!(gain_axis, -2gain_noise, 2gain_noise; color=(:gray50, 0.15))
    tops = Float64[]
    for (group, (ship, drive)) in enumerate(groups)
        savings = [rig_savings(table, first.(combination_rigs), "ship" => ship,
                       "route" => string(route), "drive" => drive) for route in pair_routes]
        for (k, (rig, _, colour)) in enumerate(combination_rigs)
            values = [saving[rig] for saving in savings]
            range_bar!(saving_axis, group + 0.27(k - 2), values, 0.25, colour)
            push!(tops, maximum(values))
        end
        gains = pair_gain.(savings)
        range_bar!(gain_axis, group, gains, 0.4, kite_and_rotors_fill())
        print_combination(ship, drive, savings, gains)
    end
    @printf("  noise of the extra saving %.2f points, %.2f to %.2f by design\n",
        gain_noise, extrema(errors)...)
    for axis in (saving_axis, gain_axis)
        hlines!(axis, 0; color=:gray50, linewidth=0.6)
    end
    ylims!(saving_axis, nothing, 1.4maximum(tops))
    ylims!(gain_axis, -1.3 * 2gain_noise, nothing)
    entries = [[PolyElement(color=colour) for (_, _, colour) in combination_rigs];
        MarkerElement(marker='I', color=:black, markersize=pt(8));
        PolyElement(color=(:gray50, 0.15))]
    axislegend(saving_axis, entries, [collect(getindex.(combination_rigs, 2));
            "range over the two routes"; "(b) twice the noise of the extra saving"];
        position=:ct, orientation=:horizontal, nbanks=2)
    save_figure("combination", figure)
end

"""
    range_bar!(axis, x, values, width, colour)

Bar of `width` at `x` to the mean of `values` with a range bar from their least to their
largest.
"""
function range_bar!(axis, x, values, width, colour)
    barplot!(axis, [x], [mean(values)]; width, color=colour, strokecolor=:gray20,
        strokewidth=rule_width)
    rangebars!(axis, [x], [minimum(values)], [maximum(values)]; color=:black,
        whiskerwidth=4, linewidth=0.8)
end

"""
    print_combination(ship, drive, savings, gains)

Print the mean savings [%] of the rigs of `combination_rigs` over the routes, the mean
and range of the combination's extra saving `gains` [% points] and the mean share of the
summed single-rig savings it keeps where both single rigs save.
"""
function print_combination(ship, drive, savings, gains)
    means = [mean(saving[rig] for saving in savings) for (rig, _, _) in combination_rigs]
    kept = [saving["kite+rotors"] / (saving["kite"] + saving["rotors"])
            for saving in savings if saving["kite"] > 0 && saving["rotors"] > 0]
    @printf("  %s, %s: saving kite %.1f, rotors %.1f, both %.1f %%; ", ship, drive,
        means...)
    @printf("extra %.1f (%.1f to %.1f) points; ", mean(gains), extrema(gains)...)
    println(isempty(kept) ? "no route where both single rigs save" :
            @sprintf("keeps %.0f %% of the summed savings", 100mean(kept)))
end

"""
    speed_size_figure()

Fuel saved by a kite free of running cost, in relative and absolute terms, and cost saved by
the priced kite, against held ship speed at each kite size, for each ship and fuel of
speed_size.csv: speed_size.pdf.
"""
function speed_size_figure()
    table = read_table(data_file("speed_size.csv"))
    figure = Figure(size=(page_width, 430))
    panels = (("fuel saved [%]", "free", :fuel_percent),
        ("fuel saved [GJ/round trip]", "free", :fuel), ("cost saved [%]", "priced",
            :cost_percent))
    designs = [(grid, string(drive)) for grid in speed_size_grid for drive in grid.drives]
    for (row, (grid, drive)) in enumerate(designs)
        shades = cgrad(:Blues, length(grid.kites) + 3; categorical=true)
        for (column, (label, pricing, quantity)) in enumerate(panels)
            letter = Char('a' + length(panels) * (row - 1) + column - 1)
            short_ship = replace(grid.ship, " container ship" => "")
            design = column == 1 ? " $short_ship, $(Dict(drive_labels)[drive])" : ""
            axis = Axis(figure[row, column]; title="($letter)$design",
                xlabel=row == length(designs) ? "ship speed [kn]" : "", ylabel=label,
                xticks=collect(grid.speeds))
            ends, drawn = Float64[], Float64[]
            for (k, area) in enumerate(grid.kites)
                savings = [speed_size_saving(table, grid.ship, drive,
                               speed_size_routes(table, grid, drive, knots), "kite", area,
                               pricing, knots) for knots in grid.speeds]
                held = findall(!isnothing, savings)
                values = [getproperty(savings[i], quantity) for i in held]
                scatterlines!(axis, collect(grid.speeds)[held], values;
                    color=shades[k + 3])
                push!(ends, last(values))
                append!(drawn, values)
            end
            column == length(panels) || continue
            spread = spread_labels(ends, 0.13 * (maximum(drawn) - minimum(drawn)))
            for (k, area) in enumerate(grid.kites)
                text!(axis, last(grid.speeds), spread[k]; text="$(round(Int, area)) m²",
                    color=shades[k + 3], fontsize=note_size, align=(:left, :center),
                    offset=(5, 0))
            end
            xlims!(axis, first(grid.speeds) - 0.3,
                last(grid.speeds) + 0.55 * (last(grid.speeds) - first(grid.speeds)))
        end
    end
    save_figure("speed_size", figure)
end

"`name`, a kind of kite or scenario in the rigid kite data, as the paper names it"
paper_name(name) = replace(name, "rigid" => "VTOL")

"""
    rigid_scaling_figure()

Beam thrust of VTOL kites and a soft kite over apparent wind, and price and annual cost per
unit of thrust at 12 m/s over area for the mass exponents of the scaling study. Prints the
scaling table.
"""
function rigid_scaling_figure()
    table = read_table(data_file("rigid_scaling.csv"))
    figure = Figure(size=(page_width, 330))
    thrust_axis = Axis(figure[1, 1]; title="(a) one kite on a beam course",
        xlabel="apparent wind [m/s]", ylabel="thrust [kN]")
    price_axis = Axis(figure[1, 2]; title="(b) price at 12 m/s", xscale=log10,
        xticks=[30, 300, 3000], xlabel=square_metres("kite area [", "]"),
        ylabel="price per thrust [USD/kN]",
        ytickformat=values -> [@sprintf("%.0f", value) for value in values])
    annual_axis = Axis(figure[2, 1]; title="(c) cost a year at 12 m/s", xscale=log10,
        xticks=[30, 300, 3000], xlabel=square_metres("kite area [", "]"),
        ylabel="USD/kN a year")
    wind_axis = Axis(figure[2, 2]; title="(d) lowest wind", xscale=log10,
        xticks=[30, 100, 300], xlabel=square_metres("kite area [", "]"),
        ylabel="apparent wind [m/s]")
    exponents = assumptions.entries[:rigid_mass_exponent]
    base_exponent = exponents.value
    curves = (("rigid", 30.0), ("rigid", 54.0), ("rigid", 100.0), ("rigid", 300.0),
        ("soft", 1000.0))
    highest = 0.0
    for (k, (kind, area)) in enumerate(curves)
        exponent = kind == "rigid" ? base_exponent : 0.0
        chosen = rows(table, "kind" => kind, "area" => area, "exponent" => exponent)
        highest = max(highest, 1e-3maximum(table["thrust"][chosen]))
        lines!(thrust_axis, table["wind"][chosen], 1e-3 .* table["thrust"][chosen];
            color=kind == "soft" ? palette[1] : vtol_shades(length(curves) - 1)[k],
            label=square_metres("$(paper_name(kind)) $(round(Int, area)) "))
    end
    series = [("rigid", exponents.low, :dash), ("rigid", base_exponent, :solid),
        ("rigid", exponents.high, :dot), ("soft", 0.0, :solid)]
    for (kind, exponent, linestyle) in series
        at_twelve = filter(row -> table["thrust"][row] > 0,
            rows(table, "kind" => kind, "exponent" => exponent, "wind" => 12.0))
        areas, prices = table["area"][at_twelve], table["price"][at_twelve]
        per_thrust = 1e3 .* prices ./ table["thrust"][at_twelve]
        annual_per_thrust = 1e3 .* table["annual"][at_twelve] ./ table["thrust"][at_twelve]
        label = kind == "soft" ? "soft kite" :
                L"%$(paper_name(kind)), $\kappa = %$(exponent)$"
        colour = kind == "soft" ? palette[1] : palette[4]
        lines!(price_axis, areas, per_thrust; linestyle, label, color=colour)
        lines!(annual_axis, areas, annual_per_thrust; linestyle, color=colour)
        kind == "rigid" && lines!(wind_axis, areas, table["lowest_wind"][at_twelve];
            linestyle, color=colour)
        @printf("  %s %.1f: USD/kN a year %s\n", kind, exponent,
            join(round.(Int, annual_per_thrust), ", "))
        kind == "rigid" && exponent == base_exponent && for i in eachindex(areas)
            row = at_twelve[i]
            @printf("  %3.0f m2: span %.0f m, mass %.1f t, stall %.0f m/s, hover %.1f MW, ",
                areas[i], table["span"][row], 1e-3table["mass"][row], table["stall"][row],
                1e-6table["hover_power"][row])
            @printf("flies from %.0f m/s, %.0f kN at 12 m/s, %.1f MUSD\n",
                table["lowest_wind"][row], 1e-3table["thrust"][row], 1e-6prices[i])
        end
    end
    axislegend(thrust_axis; position=:lt, orientation=:horizontal, nbanks=3)
    ylims!(thrust_axis, -0.04highest, 1.65highest)
    axislegend(price_axis; position=:rt)
    linkxaxes!(price_axis, annual_axis)
    for axis in (price_axis, annual_axis, wind_axis)
        axis.yautolimitmargin = (0.05, 0.1)
    end
    xlims!(wind_axis, 25, 600)
    save_figure("rigid_scaling", figure)
end

"rigs of the rigid kite figure with their legend labels and colours"
rigid_kite_rigs = (("kite", "best soft kite", palette[1]),
    ("wings", "best wings", palette[2]),
    ("rotors", "best rotors", palette[3]), ("rigid base", "best VTOL kites", palette[4]),
    ("rigid optimistic", "best VTOL kites, favourable inputs", vtol_shades(4)[3]))

"""
    rigid_kite_figure()

Cost saving against no rig of the best size of each rig of `rigid_kite_rigs` on each ship
and drive of the rigid kite study, as the mean over the routes with the range of the
routes. Prints the means and the rigid fleets each scenario prefers.
"""
function rigid_kite_figure()
    table = read_table(data_file("rigid_kite.csv"))
    groups = vec([(ship, drive) for drive in ("vlsfo", "ammonia"),
                  ship in pair_classes])
    figure = Figure(size=(page_width, 240))
    axis = Axis(figure[1, 1]; ylabel="cost saving [%]",
        xticks=(eachindex(groups),
            ["$(replace(ship, " bulk carrier" => ""))\n$(Dict(drive_labels)[drive])"
             for (ship, drive) in groups]))
    names = first.(rigid_kite_rigs)
    for (group, (ship, drive)) in enumerate(groups)
        savings = [rig_savings(table, names, "ship" => ship, "route" => string(route),
                       "drive" => drive) for route in pair_routes]
        for (k, (rig, _, colour)) in enumerate(rigid_kite_rigs)
            range_bar!(axis, group + 0.17(k - 3), [saving[rig] for saving in savings], 0.15,
                colour)
        end
        print_rigid_kite(table, ship, drive, savings)
    end
    hlines!(axis, 0; color=:gray50, linewidth=0.6)
    axis.yautolimitmargin = (0.05, 0.3)
    axislegend(axis, [PolyElement(color=colour) for (_, _, colour) in rigid_kite_rigs],
        collect(getindex.(rigid_kite_rigs, 2)); position=:lt)
    save_figure("rigid_kite", figure)
end

"""
    print_rigid_kite(table, ship, drive, savings)

Print for one ship and drive the mean saving [%] of each rig over the routes, and for each
scenario its best fleet on each route and the routes on which it leads.
"""
function print_rigid_kite(table, ship, drive, savings)
    @printf("  %s, %s:", ship, drive)
    for (rig, _, _) in rigid_kite_rigs
        @printf(" %s %.1f (%.1f to %.1f) %%,", paper_name(rig),
            mean(saving[rig] for saving in savings),
            extrema(saving[rig] for saving in savings)...)
    end
    println()
    for scenario in ("rigid base", "rigid optimistic")
        best = map(pair_routes) do route
            chosen = rows(table, "ship" => ship, "drive" => drive, "route" => string(route),
                "rig" => scenario)
            row = chosen[argmin(table["cost"][chosen])]
            "$(round(Int, table["count"][row])) x $(round(Int, table["unit"][row]))"
        end
        leads = count(saving -> saving[scenario] > maximum(saving[rig]
                for rig in ("kite", "wings", "rotors")), savings)
        println("    $(paper_name(scenario)): best fleets ", join(best, ", "),
            "; leads on ", leads, " of ", length(pair_routes), " routes")
    end
end

"""
    canopy_price_range(inputs, today)

Lowest and highest [`WindShipOpt.canopy_price`](@ref) [USD/m^2] of `inputs` with each input
of the price in turn at its low and its high bound, those of the `_today` input for the
names in `today`.
"""
function canopy_price_range(inputs, today)
    names = (:canopy_cloth_area_ratio, :market_price_factor,
        WindShipOpt.canopy_price_inputs...)
    bounds = [assumptions.entries[name in today ? Symbol(name, :_today) : name]
              for name in names]
    prices = [WindShipOpt.canopy_price(WindShipOpt.with_value(inputs, name, bound))
              for (name, entry) in zip(names, bounds) for bound in (entry.low, entry.high)]
    return extrema(prices)
end

"""
    retail_cloth_prices()

Cloth weights [g/m^2], prices [USD per m^2 sewn, without VAT, with offcuts] and sources of
the retail cloths in data/canopy_cloth_prices.csv.
"""
function retail_cloth_prices()
    table = read_table(joinpath(root, "data", "canopy_cloth_prices.csv"))
    metres = Dict("m" => 1.0, "yd" => 0.9144)
    dollars = Dict("USD" => 1.0, "EUR" => assumptions[:usd_per_eur])
    prices = [price * dollars[currency] / (1 + vat) / (metres[per] * width)
              for (price, currency, per, width, vat) in zip(table["price"],
        table["currency"], table["per"], table["width"], table["vat"])]
    return table["weight"], cloth_offcut_factor * prices, table["source"]
end

"cloth bought per m^2 of cloth sewn into a canopy [-]"
cloth_offcut_factor = 1.15

"""
    canopy_price_figure()

(a) Price of a canopy per projected m^2 as built today, at the goal with today's cloth, and
at the goal, split into cloth, sewing with lines and hardware, and the market margin, with
the range over the bounds of its inputs; (b) price of a sewn m^2 of cloth against cloth
weight: the retail prices it rests on, the line through them, and the goal with its range.
"""
function canopy_price_figure()
    figure = Figure(size=(page_width, 175))
    price = Axis(figure[1, 1]; xlabel="price per projected m² [USD]",
        title="(a) canopy price")
    cloth = Axis(figure[1, 2]; xlabel="cloth weight [g/m²]",
        ylabel="USD per m² of cloth", title="(b) sewn cloth")
    colsize!(figure.layout, 1, Relative(0.58))
    cloth_inputs = (:canopy_cloth_base_price, :canopy_cloth_price_per_weight)
    cases = [("today", WindShipOpt.canopy_price_inputs),
        ("goal, today's cloth", cloth_inputs), ("goal", ())]
    parts = ("cloth", "sewing, lines, hardware", "market margin")
    part_colors = [palette[1], palette[5], :gray60]
    for (row, (label, today)) in enumerate(cases)
        inputs = WindShipOpt.with_today(assumptions, today)
        making = inputs[:canopy_making_cost_per_area]
        cost = WindShipOpt.Canopy(inputs).cost_per_area
        segments = [cost - making, making, (inputs[:market_price_factor] - 1) * cost]
        barplot!(price, fill(row, 3), segments; stack=1:3, direction=:x,
            color=part_colors, gap=0.3)
        text!(price, cumsum(segments) .- segments ./ 2, fill(row - 0.14, 3);
            text=estimate_text.(segments), align=(:center, :center),
            fontsize=note_size, color=:white)
        low, high = canopy_price_range(inputs, today)
        rangebars!(price, [row + 0.17], [low], [high]; direction=:x, color=:black,
            linewidth=line_width, whiskerwidth=pt(4))
        text!(price, sum(segments), row - 0.14; text=string(estimate_text(sum(segments)),
                " (", estimate_text(low), "–", estimate_text(high), ")"),
            align=(:left, :center), offset=clear_offset((:left, :center), pt(3)))
    end
    price.yticks = (eachindex(cases), first.(cases))
    price.yreversed = true
    xlims!(price, 0, nothing)
    hideydecorations!(price; ticklabels=false)
    weights = 0:5:400
    weight = WindShipOpt.cloth_weight(assumptions)
    goal_band = [extrema(WindShipOpt.sewn_cloth_price(WindShipOpt.with_value(assumptions,
                         name, bound), cloth_weight)
                         for name in cloth_inputs
                         for bound in (assumptions.entries[name].low,
                             assumptions.entries[name].high))
                 for cloth_weight in weights]
    band!(cloth, weights, first.(goal_band), last.(goal_band); color=(palette[1], 0.15))
    retail_weights, retail_prices, sources = retail_cloth_prices()
    sources = (("extremtextil_prices_2026", "extremtextil", :circle),
        ("sailrite_dacron_prices_2026", "Sailrite", :rect),
        ("jonesairfoils_icarex", "Jones Airfoils", :diamond))
    retail_weights, retail_prices, retail_sources = retail_cloth_prices()
    source_elements = map(sources) do (source, _, marker)
        chosen = retail_sources .== source
        scatter!(cloth, retail_weights[chosen], retail_prices[chosen]; marker,
            color=:white, strokecolor=:black, strokewidth=rule_width)
        MarkerElement(; marker, color=:white, strokecolor=:black, strokewidth=rule_width)
    end
    lines!(cloth, weights, WindShipOpt.sewn_cloth_price.(Ref(WindShipOpt.with_today(
        assumptions, cloth_inputs)), weights); color=:black)
    lines!(cloth, weights, WindShipOpt.sewn_cloth_price.(Ref(assumptions), weights);
        color=palette[1], linestyle=:dash)
    vlines!(cloth, weight; color=:gray, linewidth=rule_width)
    ylims!(cloth, 0, nothing)
    Legend(figure[2, 1], [PolyElement(; color) for color in part_colors],
        collect(parts); orientation=:horizontal, tellwidth=false, valign=:top)
    Legend(figure[2, 2], [collect(source_elements); LineElement(; color=:black);
            [[PolyElement(; color=(palette[1], 0.15)),
                LineElement(; color=palette[1], linestyle=:dash)]]],
        [collect(getindex.(sources, 2)); "retail line"; "goal"];
        orientation=:horizontal, nbanks=2, tellwidth=false, valign=:top)
    rowgap!(figure.layout, pt(4))
    save_figure("canopy_price", figure)
end

"""
    min_wind_figure()

Lowest apparent wind against projected area for the kite of the design aspect ratio: the
crosswind and climbing bounds at the lowest elevation, lift-off with the margin, and the
launch wind the model uses, which is the largest of these and the reported launch wind,
with its range over the bounds of the margin and of the reported launch wind in turn.
"""
function min_wind_figure()
    figure = Figure(size=(column_width, 190))
    axis = Axis(figure[1, 1]; xscale=log10, xlabel="projected kite area [m²]",
        ylabel="lowest apparent wind [m/s]",
        xticks=([500, 1000, 2000, 4000, 8000, 16000], ["500", "1000", "2000", "4000",
            "8000", "16000"]))
    areas = exp.(range(log(500), log(16000); length=40))
    elevation = deg2rad(assumptions[:kite_min_elevation])
    bounds = [WindShipOpt.with_value(assumptions, name, bound)
              for name in (:kite_launch_margin, :kite_launch_min_wind)
              for bound in (assumptions.entries[name].low, assumptions.entries[name].high)]
    winds = map(areas) do area
        model, _, diameter = WindShipOpt.kite_model(area, design_aspect_ratio, assumptions)
        tether_mass = WindShipOpt.rope_mass(diameter, model.tether_length, assumptions)
        lift_off = WindShipOpt.static_wind(model.mass - tether_mass / 2, model)
        launches = [WindShipOpt.launch_min_wind(model, tether_mass, inputs)
                    for inputs in bounds]
        (cross=WindShipOpt.crosswind_min_wind(model, elevation),
            climb=WindShipOpt.climbing_min_wind(model, elevation),
            lift=assumptions[:kite_launch_margin] * lift_off,
            launch=WindShipOpt.launch_min_wind(model, tether_mass, assumptions),
            launch_low=minimum(launches), launch_high=maximum(launches))
    end
    launch_colour = :gray60
    band!(axis, areas, getindex.(winds, :launch_low), getindex.(winds, :launch_high);
        color=(launch_colour, 0.2))
    curves = ((:launch, launch_colour, pt(3.5)), (:lift, category_colours[1], line_width),
        (:climb, category_colours[2], line_width),
        (:cross, category_colours[3], line_width))
    for (key, color, linewidth) in curves
        lines!(axis, areas, getindex.(winds, key); color, linewidth)
    end
    ylims!(axis, 0, 1.35 * maximum(getindex.(winds, :launch_high)))
    entries = [[LineElement(; color, linewidth) for (_, color, linewidth) in curves];
        PolyElement(color=(launch_colour, 0.2))]
    axislegend(axis, entries, ["launch", "lift-off", "climb", "crosswind",
            "launch range"]; position=:lt, orientation=:horizontal, nbanks=2)
    save_figure("min_wind", figure)
end

"""
    missed_goals_figure()

Cost saving of each rig against the canopy life, the canopy price and the share out of
service, for each ship of the development study with its rig sizes held: the kite's saving
over the swept canopy inputs, the other rigs' at their goals, and every rig's over its
share out of service. Each goal is a vertical line over the shaded range of its input;
today's canopy price is dotted over its own range.
"""
function missed_goals_figure()
    sizes = read_table(data_file("goal_sizes.csv"))
    service = read_table(data_file("availability.csv"))
    lives = read_table(data_file("canopy_life.csv"))
    prices = read_table(data_file("canopy_price.csv"))
    ships = unique(service["ship"])
    sweeps = ((lives, "life"), (prices, "price"))
    price_inputs = WindShipOpt.canopy_price_inputs
    price_today = WindShipOpt.with_today(assumptions, price_inputs)
    service_inputs = [assumptions.entries[Symbol(out_of_service_inputs[rig])]
                      for rig in rig_names]
    service_goal = only(unique(input.value for input in service_inputs))
    figure = Figure(size=(page_width, 410))
    for (column, ship) in enumerate(ships)
        bare = bare_cost(sizes, ship)
        curves = Dict(rig => share_costs(service, ship, rig) for rig in rig_names)
        goal = Dict(rig => percent_saving(curve_cost(curves[rig],
                assumptions[Symbol(out_of_service_inputs[rig])]), bare)
                    for rig in rig_names)
        axes = [Axis(figure[row, column]; xlabel, ylabel=column == 1 ? "saving [%]" : "",
                    title=row == 1 ? "($('a' + column - 1)) $ship" : "", xscale, xticks,
                    yticks=WilkinsonTicks(4; Q=[(1.0, 1.0), (5.0, 0.9), (2.0, 0.7)]),
                    yautolimitmargin=(0.05, 0.1))
                for (row, (xlabel, xscale, xticks)) in enumerate((
                    ("canopy life [h]", log10,
                        ([500, 2000, 8000], ["500", "2000", "8000"])),
                    (rich("canopy price [USD/m", superscript("2"), "]"), identity,
                        Makie.automatic),
                    ("out of service [%]", Makie.pseudolog10, [0, 1, 3, 10, 30, 100])))]
        goal_marks!(axes[1], assumptions.entries[:canopy_life])
        vspan!(axes[2], canopy_price_range(assumptions, ())...; color=(:gray50, 0.15))
        vlines!(axes[2], WindShipOpt.canopy_price(assumptions); color=:black,
            linewidth=0.75)
        vspan!(axes[2], canopy_price_range(price_today, price_inputs)...;
            color=(palette[1], 0.1))
        vlines!(axes[2], WindShipOpt.canopy_price(price_today); color=:black,
            linewidth=0.75, linestyle=:dot)
        vspan!(axes[3], 100minimum(input.low for input in service_inputs),
            100maximum(input.high for input in service_inputs); color=(:gray50, 0.15))
        vlines!(axes[3], 100service_goal; color=:black, linewidth=0.75)
        for axis in axes
            hlines!(axis, 0; color=:gray60, linewidth=0.5)
        end
        for (axis, (table, input)) in zip(axes, sweeps)
            picked = rows(table, "ship" => ship)
            order = sortperm(table[input][picked])
            values = table[input][picked][order]
            for (k, rig) in enumerate(rig_names)
                rig == "kite" && continue
                hlines!(axis, goal[rig]; color=palette[k], linestyle=:dash, linewidth=1)
            end
            scatterlines!(axis, values, percent_saving.(table["cost"][picked][order], bare);
                color=palette[1])
        end
        for (k, rig) in enumerate(rig_names)
            shares, costs = curves[rig]
            scatterlines!(axes[3], 100shares, percent_saving.(costs, bare);
                color=palette[k])
        end
        if column == 1
            price_high = maximum(prices["price"])
            for (k, rig) in enumerate(rig_names)
                rig == "kite" && continue
                align = rig == "rotors" ? (:right, :top) : (:right, :bottom)
                text!(axes[2], price_high, goal[rig];
                    text="$(rig_label(rig)) at their goals", color=palette[k],
                    fontsize=note_size, align,
                    offset=clear_offset(align, pt(2)))
            end
            picked = rows(prices, "ship" => ship)
            middle = picked[argmin(abs.(prices["price"][picked] .- price_high / 1.4))]
            text!(axes[2], prices["price"][middle],
                percent_saving(prices["cost"][middle], bare); text="kite",
                color=palette[1], fontsize=note_size, align=(:left, :bottom),
                offset=clear_offset((:left, :bottom), pt(3)))
        end
        column == 2 && axislegend(axes[2],
            [[PolyElement(color=(:gray50, 0.15)),
                    LineElement(color=:black, linewidth=0.75)],
                [PolyElement(color=(palette[1], 0.1)),
                    LineElement(color=:black, linewidth=0.75, linestyle=:dot)]],
            ["goal, its range", "today, its range"]; position=(1, 0.6))
    end
    save_figure("missed_goals", figure)
end

"""
    goal_marks!(axis, input)

The goal `input` of the assumptions as a vertical line over the shaded range between its
low and high bounds.
"""
function goal_marks!(axis, input)
    vspan!(axis, input.low, input.high; color=(:gray50, 0.15))
    vlines!(axis, input.value; color=:black, linewidth=0.75)
end

"""
    rigid_mass_figure()

Mass of a rigid kite against its area: the mass law of the assumptions at the base
exponent and its bounds through the MX2 anchor with the range of its mass, and the
published wings of data/rigid_kite_masses.csv, its `area` [m^2] and `mass_low` to
`mass_high` [kg], with and without rotors, filled where built and hollow where designed.
"""
function rigid_mass_figure()
    published = read_table(joinpath(root, "data", "rigid_kite_masses.csv"))
    figure = Figure(size=(column_width, 200))
    ticks = [3, 10, 30, 100, 300]
    axis = Axis(figure[1, 1]; xscale=log10, yscale=log10, xlabel="wing area [m²]",
        ylabel="mass [kg]", xticks=(ticks, string.(ticks)),
        yticks=([30, 100, 300, 1000, 3000, 10000, 30000],
            ["30", "100", "300", "1000", "3000", "10000", "30000"]))
    anchor_area = assumptions[:rigid_reference_area]
    anchor_mass = assumptions.entries[:rigid_reference_mass]
    exponent = assumptions.entries[:rigid_mass_exponent]
    areas = exp.(range(log(3), log(500); length=40))
    for (value, linestyle) in ((exponent.low, :dot), (exponent.value, :solid),
        (exponent.high, :dash))
        lines!(axis, areas, anchor_mass.value .* (areas ./ anchor_area) .^ (value / 2);
            color=:black, linestyle, linewidth=0.8, label=L"\kappa = %$(value)")
    end
    rangebars!(axis, [anchor_area], [anchor_mass.low], [anchor_mass.high]; color=:black,
        linewidth=0.8, whiskerwidth=4)
    scatter!(axis, [anchor_area], [anchor_mass.value]; color=:white, strokecolor=:black,
        strokewidth=0.75, marker=:diamond, markersize=pt(7))
    text!(axis, anchor_area, anchor_mass.value; text="MX2", align=(:left, :top),
        offset=clear_offset((:left, :top), pt(4)), fontsize=note_size)
    with_rotors = published["rotors"] .== "true"
    built = occursin.(r"flown|built", published["name"])
    for i in eachindex(built)
        color = category_colours[with_rotors[i] ? 1 : 2]
        mass = (published["mass_low"][i] + published["mass_high"][i]) / 2
        rangebars!(axis, [published["area"][i]], [published["mass_low"][i]],
            [published["mass_high"][i]]; color)
        scatter!(axis, [published["area"][i]], [mass]; color=built[i] ? color : :white,
            strokecolor=color, strokewidth=0.75, markersize=pt(5))
        law = anchor_mass.value * (published["area"][i] / anchor_area)^(exponent.value / 2)
        align = mass < law ? (:left, :top) :
                (published["area"][i] > 10 ? :right : :left, :bottom)
        text!(axis, published["area"][i], mass; text=first(split(published["name"][i],
            ",")), align, offset=clear_offset(align, pt(2.5)), fontsize=note_size, color,
            glowwidth=pt(1.5), glowcolor=:white)
    end
    entries = [[LineElement(; color=:black, linestyle, linewidth=0.8)
                for linestyle in (:dot, :solid, :dash)];
        [MarkerElement(marker=:circle, color=category_colours[k], markersize=pt(5))
         for k in 1:2];
        MarkerElement(marker=:circle, color=:white, strokecolor=:black, strokewidth=0.75,
            markersize=pt(5))]
    names = [[L"\kappa = %$(value)" for value in (exponent.low, exponent.value,
            exponent.high)]; "with propellers"; "without propellers"; "design"]
    axislegend(axis, entries, names; position=:rb)
    save_figure("rigid_mass", figure)
end
