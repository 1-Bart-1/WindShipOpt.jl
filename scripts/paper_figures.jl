# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Figure steps of the paper: each saves one PDF to paper/figures/, from the CSV files of
# the run in use, the data in data/kite_polars/ or the model itself. Included by paper.jl.

figures = mkpath(joinpath(root, "paper", "figures"))
polars = joinpath(root, "data", "kite_polars")
"the paper's figure style: sizes [pt] and colours, shared with its TikZ figures"
figure_style = TOML.parsefile(joinpath(root, "paper", "figure_style.toml"))
"the colour `name` of the `table` of [`figure_style`](@ref), its colours or its box fills"
style_colour(name; table="colours") =
    parse(Makie.Colors.Colorant, "#" * figure_style[table][name])
"white, the background of every figure"
white = Makie.RGBf(1, 1, 1)
"colour of each rig, in the order of `rig_names`"
palette = style_colour.(collect(rig_names))
"""
    rig_offset(slot, count, step)

Offset from the centre of its group of the `slot`th of `count` rigs drawn side by side over
a span of `2step`.
"""
rig_offset(slot, count, step) = 2step * ((slot - 1) / (count - 1) - 0.5)
"width of a rig's bar in a group of `count` laid out by [`rig_offset`](@ref) with `step`"
rig_bar_width(step, count) = 0.9 * 2step / (count - 1)
"colours of what is not a rig, none of them a rig's"
category_colours = [style_colour.(["accent", "purple", "sand", "water", "slate"]);
    Makie.RGBf(0, 0, 0)]
"least differences of [`figure_style`](@ref): text contrast, colour and grey difference"
least = figure_style["contrast"]

"the sRGB colour `channel` [0 to 1] in linear light, by WCAG 2"
linear_channel(channel) = channel <= 0.04045 ? channel / 12.92 :
                          ((channel + 0.055) / 1.055)^2.4

"relative luminance of `colour`, by WCAG 2"
function luminance(colour)
    rgb = Makie.Colors.RGB(Makie.Colors.color(Makie.to_color(colour)))
    return 0.2126linear_channel(rgb.r) + 0.7152linear_channel(rgb.g) +
           0.0722linear_channel(rgb.b)
end

"contrast of `colour` and `other`, by WCAG 2: 1 between equal colours, 21 black on white"
contrast(colour, other) = (max(luminance(colour), luminance(other)) + 0.05) /
                          (min(luminance(colour), luminance(other)) + 0.05)

"""
    readable(colour, background)

`colour` as text on `background`: unchanged where it has the contrast `least["text"]`,
else black or white for a grey, and for a hue the least mix of it with black or white,
whichever stands out more, that has that contrast.
"""
function readable(colour, background)
    colour = Makie.Colors.RGB{Float32}(Makie.Colors.color(Makie.to_color(colour)))
    contrast(colour, background) >= least["text"] && return colour
    black = Makie.RGBf(0, 0, 0)
    toward = contrast(black, background) > contrast(white, background) ? black : white
    Makie.Colors.HSV(colour).s < 0.1 && return toward
    mixes = (Makie.Colors.weighted_color_mean(1 - share, colour, toward)
             for share in 0:0.02:1)
    return first(mix for mix in mixes if contrast(mix, background) >= least["text"])
end

"""
    palette_faults()

Pairs of colours meant to be told apart, the rigs, the categories beside them, gain and
loss, the ship's tones beside the rigs, the forces of water, wind and rigs, the box fills
of [`figure_style`](@ref), that come closer
than `least["colour"]` in normal or in some colour-blind vision.
"""
function palette_faults()
    colours = Makie.Colors
    visions = (identity, colours.deuteranopic, colours.protanopic, colours.tritanopic)
    groups = (("rig", style_colour.(collect(rig_names))),
        ("category", category_colours), ("cell", style_colour.(["gain", "loss"])),
        ("fill", style_colour.(collect(keys(figure_style["fills"])); table="fills")),
        ("ship", style_colour.(["keel", "topsides", "deck", "kite", "wings", "rotors",
            "suction"])),
        ("force", style_colour.(["water", "wind", "kite", "wings", "rotors"])))
    faults = String[]
    for (group, members) in groups, i in eachindex(members), j in (i + 1):length(members)
        colour, other = colours.RGB(members[i]), colours.RGB(members[j])
        difference = minimum(colours.colordiff(see(colour), see(other)) for see in visions)
        difference < least["colour"] &&
            push!(faults, @sprintf("%s colours %s and %s differ by %.1f in some vision",
                group, colours.hex(colour), colours.hex(other), difference))
    end
    return faults
end

"""
LaTeX3 code that records the box of each `label` node and each arrow as straight pieces, a
curve as eight chords, and stops the build where two labels meet or an arrow comes within
`clearance` of a label
"""
label_overlap_check = replace(raw"""
    \ExplSyntaxOn
    \seq_new:N \g_figstyle_labels_seq
    \seq_new:N \g_figstyle_segments_seq
    \cs_new_protected:Npn \figurestylesegment #1 #2
      { \use:e { \exp_not:N \figstyle_segment:w #1 , #2 \exp_not:N \q_stop } }
    \cs_new_protected:Npn \figurestylecurve #1 #2 #3 #4
      {
        \use:e
          {
            \exp_not:N \figstyle_curve:w #1 , #2 , #3 , #4 \exp_not:N \q_stop
          }
      }
    \cs_new_protected:Npn \figstyle_curve:w #1 , #2 , #3 , #4 , #5 , #6 , #7 , #8 \q_stop
      {
        \tl_set:Nn \l_tmpa_tl { #1 , #2 }
        \int_step_inline:nn { 8 }
          {
            \tl_set:Ne \l_tmpb_tl
              {
                \fp_eval:n
                  {
                    (1 - ##1/8)^3 * (#1) + 3 * (1 - ##1/8)^2 * ##1/8 * (#3)
                    + 3 * (1 - ##1/8) * (##1/8)^2 * (#5) + (##1/8)^3 * (#7)
                  } pt ,
                \fp_eval:n
                  {
                    (1 - ##1/8)^3 * (#2) + 3 * (1 - ##1/8)^2 * ##1/8 * (#4)
                    + 3 * (1 - ##1/8) * (##1/8)^2 * (#6) + (##1/8)^3 * (#8)
                  } pt
              }
            \figurestylesegment { \l_tmpa_tl } { \l_tmpb_tl }
            \tl_set_eq:NN \l_tmpa_tl \l_tmpb_tl
          }
      }
    \cs_new_protected:Npn \figstyle_segment:w #1 , #2 , #3 , #4 \q_stop
      {
        \fp_compare:nNnT { abs((#3) - (#1)) + abs((#4) - (#2)) } > { 0.1pt }
          {
            \seq_gput_right:Nx \g_figstyle_segments_seq
              {
                { \dim_to_decimal:n {#1} } { \dim_to_decimal:n {#2} }
                { \dim_to_decimal:n {#3} } { \dim_to_decimal:n {#4} }
              }
          }
      }
    \cs_new_protected:Npn \figstyle_clip:nn #1#2
      {
        \fp_compare:nNnTF { #1 } = { 0 }
          { \fp_compare:nNnT { #2 } < { 0 } { \bool_set_false:N \l_figstyle_meets_bool } }
          {
            \fp_compare:nNnTF { #1 } < { 0 }
              { \fp_set:Nn \l_figstyle_enter_fp { max(\l_figstyle_enter_fp, (#2) / (#1)) } }
              { \fp_set:Nn \l_figstyle_leave_fp { min(\l_figstyle_leave_fp, (#2) / (#1)) } }
          }
      }
    \fp_new:N \l_figstyle_enter_fp
    \fp_new:N \l_figstyle_leave_fp
    \bool_new:N \l_figstyle_meets_bool
    \cs_new_protected:Npn \figstyle_crossing:nnnnnnnn #1#2#3#4#5#6#7#8
      {
        \fp_set:Nn \l_figstyle_enter_fp { 0 }
        \fp_set:Nn \l_figstyle_leave_fp { 1 }
        \bool_set_true:N \l_figstyle_meets_bool
        \figstyle_clip:nn { #1 - #3 } { #1 - (#5 - @CLEARANCE@) }
        \figstyle_clip:nn { #3 - #1 } { (#7 + @CLEARANCE@) - #1 }
        \figstyle_clip:nn { #2 - #4 } { #2 - (#6 - @CLEARANCE@) }
        \figstyle_clip:nn { #4 - #2 } { (#8 + @CLEARANCE@) - #2 }
        \bool_if:NT \l_figstyle_meets_bool
          {
            \fp_compare:nNnT { \l_figstyle_enter_fp } < { \l_figstyle_leave_fp }
              {
                \PackageError {figurestyle}
                  { an~arrow~runs~through~the~label~at~(#5pt,~#6pt) } { }
              }
          }
      }
    \cs_new_protected:Npn \figurestylerecord #1
      {
        \group_begin:
        \pgftransformreset
        \pgfpointanchor {#1} {south~west}
        \pgfgetlastxy \l_figstyle_ax_tl \l_figstyle_ay_tl
        \pgfpointanchor {#1} {north~east}
        \pgfgetlastxy \l_figstyle_bx_tl \l_figstyle_by_tl
        \seq_gput_right:Nx \g_figstyle_labels_seq
          {
          { \dim_to_decimal:n { \dim_min:nn { \l_figstyle_ax_tl } { \l_figstyle_bx_tl } } }
          { \dim_to_decimal:n { \dim_min:nn { \l_figstyle_ay_tl } { \l_figstyle_by_tl } } }
          { \dim_to_decimal:n { \dim_max:nn { \l_figstyle_ax_tl } { \l_figstyle_bx_tl } } }
          { \dim_to_decimal:n { \dim_max:nn { \l_figstyle_ay_tl } { \l_figstyle_by_tl } } }
          }
        \group_end:
      }
    \cs_new_protected:Npn \figstyle_overlap:nnnnnnnn #1#2#3#4#5#6#7#8
      {
        \bool_lazy_all:nT
          {
            { \fp_compare_p:n { #1 < #7 } } { \fp_compare_p:n { #5 < #3 } }
            { \fp_compare_p:n { #2 < #8 } } { \fp_compare_p:n { #6 < #4 } }
          }
          {
            \PackageError {figurestyle}
              { labels~overlap~at~(#1pt,~#2pt)~and~(#5pt,~#6pt) } { }
          }
      }
    \cs_new_protected:Npn \figurestylecheck
      {
        \int_step_inline:nn { \seq_count:N \g_figstyle_labels_seq }
          {
            \int_step_inline:nnn { ##1 + 1 } { \seq_count:N \g_figstyle_labels_seq }
              {
                \use:e
                  {
                    \exp_not:N \figstyle_overlap:nnnnnnnn
                    \seq_item:Nn \g_figstyle_labels_seq { ##1 }
                    \seq_item:Nn \g_figstyle_labels_seq { ####1 }
                  }
              }
          }
        \seq_map_inline:Nn \g_figstyle_segments_seq
          {
            \seq_map_inline:Nn \g_figstyle_labels_seq
              { \use:e { \exp_not:N \figstyle_crossing:nnnnnnnn ##1 ####1 } }
          }
        \seq_gclear:N \g_figstyle_labels_seq
        \seq_gclear:N \g_figstyle_segments_seq
      }
    \ExplSyntaxOff
    """, "@CLEARANCE@" => @sprintf("%.3f", figure_style["sizes"]["clearance"] +
                                           figure_style["sizes"]["force"] / 2))

"the size `name` of [`figure_style`](@ref) in TeX points"
tex_size(name) = @sprintf("%gpt", figure_style["sizes"][name])
"the TeX command that selects the font size `name` of [`figure_style`](@ref)"
tex_font(name) = @sprintf("\\fontsize{%g}{%g}\\selectfont", figure_style["sizes"][name],
    1.2figure_style["sizes"][name])

"""
    svg_paths(d)

The SVG path data `d` as subpaths in absolute coordinates, each a named tuple of its
`start`, its `segments`, each the end of a line or the two control points and end of a
cubic Bézier curve, every arc as such curves, and whether it is `closed`.
"""
function svg_paths(d)
    subpaths = []
    tokens = [match.match for match in eachmatch(r"[A-Za-z]|-?(\d+\.?\d*|\.\d+)", d)]
    arity = Dict('M' => 2, 'L' => 2, 'H' => 1, 'V' => 1, 'C' => 6, 'S' => 4, 'A' => 7,
        'Z' => 0)
    current, start, control = (0.0, 0.0), (0.0, 0.0), (0.0, 0.0)
    command, i = 'M', 1
    while i <= length(tokens)
        if isletter(tokens[i][1])
            command = tokens[i][1]
            i += 1
        end
        relative = islowercase(command)
        offset = relative ? current : (0.0, 0.0)
        upper = uppercase(command)
        haskey(arity, upper) || error("SVG path command $command is not supported")
        numbers = parse.(Float64, tokens[i:(i + arity[upper] - 1)])
        i += arity[upper]
        segments = isempty(subpaths) ? [] : last(subpaths).segments
        if upper == 'M'
            current = start = control = Tuple(numbers .+ offset)
            push!(subpaths, (; start, segments=[], closed=Ref(false)))
            command = relative ? 'l' : 'L'
        elseif upper in ('L', 'H', 'V')
            current = upper == 'H' ? (numbers[1] + offset[1], current[2]) :
                      upper == 'V' ? (current[1], numbers[1] + offset[2]) :
                      Tuple(numbers .+ offset)
            control = current
            push!(segments, (current,))
        elseif upper in ('C', 'S')
            first_control = upper == 'C' ? Tuple(numbers[1:2] .+ offset) :
                            2 .* current .- control
            control = Tuple(numbers[(end - 3):(end - 2)] .+ offset)
            current = Tuple(numbers[(end - 1):end] .+ offset)
            push!(segments, (first_control, control, current))
        elseif upper == 'A'
            to = Tuple(numbers[6:7] .+ offset)
            append!(segments, arc_curves(current, to, numbers[1:5]...))
            current = control = to
        else
            last(subpaths).closed[] = true
            current = control = start
        end
    end
    return subpaths
end

"""
    tikz_path(subpaths)

The [`svg_paths`](@ref) `subpaths` as a TikZ path in their own units.
"""
function tikz_path(subpaths)
    tikz = IOBuffer()
    point(x, y) = @sprintf("(%.3f,%.3f)", x, y)
    for (; start, segments, closed) in subpaths
        print(tikz, " ", point(start...))
        for segment in segments
            length(segment) == 1 ? print(tikz, " -- ", point(segment[1]...)) :
            print(tikz, " .. controls ", point(segment[1]...), " and ",
                point(segment[2]...), " .. ", point(segment[3]...))
        end
        closed[] && print(tikz, " -- cycle")
    end
    return String(take!(tikz))
end

"""
    polyline(subpath; samples=16)

The points along an [`svg_paths`](@ref) `subpath`, each curve at `samples` points, back to
its start where it is closed.
"""
function polyline(subpath; samples=16)
    points = [subpath.start]
    for segment in subpath.segments
        if length(segment) == 1
            push!(points, segment[1])
        else
            from = last(points)
            c1, c2, to = segment
            for s in range(0, 1; length=samples)[2:end]
                push!(points, (1 - s)^3 .* from .+ 3(1 - s)^2 * s .* c1 .+
                              3(1 - s) * s^2 .* c2 .+ s^3 .* to)
            end
        end
    end
    subpath.closed[] && push!(points, subpath.start)
    return points
end

"""
    arc_curves(from, to, rx, ry, rotation, large, sweep)

The SVG elliptical arc from `from` to `to` as cubic Bézier curves of at most a quarter
turn each: the control points and end of each.
"""
function arc_curves(from, to, rx, ry, rotation, large, sweep)
    from == to && return []
    φ = deg2rad(rotation)
    rotate(x, y) = (cos(φ) * x - sin(φ) * y, sin(φ) * x + cos(φ) * y)
    x1, y1 = cos(φ) * (from[1] - to[1]) / 2 + sin(φ) * (from[2] - to[2]) / 2,
             -sin(φ) * (from[1] - to[1]) / 2 + cos(φ) * (from[2] - to[2]) / 2
    scale = max(1, sqrt(x1^2 / rx^2 + y1^2 / ry^2))
    rx, ry = scale * rx, scale * ry
    root = sqrt(max(0, (rx^2 * ry^2 - rx^2 * y1^2 - ry^2 * x1^2) /
                       (rx^2 * y1^2 + ry^2 * x1^2)))
    root *= large == sweep ? -1 : 1
    cx, cy = root * rx * y1 / ry, -root * ry * x1 / rx
    centre = rotate(cx, cy) .+ (from .+ to) ./ 2
    angle(u, v) = atan(v, u)
    θ1 = angle((x1 - cx) / rx, (y1 - cy) / ry)
    Δθ = mod(angle((-x1 - cx) / rx, (-y1 - cy) / ry) - θ1, 2π)
    sweep == 0 && Δθ > 0 && (Δθ -= 2π)
    pieces = ceil(Int, abs(Δθ) / (π / 2) - 1e-9)
    step = Δθ / pieces
    handle = 4 / 3 * tan(step / 4)
    on_ellipse(θ) = rotate(rx * cos(θ), ry * sin(θ)) .+ centre
    tangent(θ) = rotate(-rx * sin(θ), ry * cos(θ))
    return [(on_ellipse(θ1 + (k - 1) * step) .+ handle .* tangent(θ1 + (k - 1) * step),
             on_ellipse(θ1 + k * step) .- handle .* tangent(θ1 + k * step),
             on_ellipse(θ1 + k * step)) for k in 1:pieces]
end

"""
    icon_pics(io)

Write to `io` the TikZ picture `<concept> icon` of each icon of [`figure_style`](@ref):
the outline of its SVG in paper/icons/, `icon_size` across, centred on the origin and
drawn in the colour and line weight of an icon.
"""
function icon_pics(io)
    unit = @sprintf("%.4gpt", figure_style["sizes"]["icon_size"] / 24)
    for (concept, name) in sort(collect(figure_style["icons"]))
        svg = read(joinpath(root, "paper", "icons", name * ".svg"), String)
        paths = [tikz_path(svg_paths(found[1]))
                 for found in eachmatch(r"<path d=\"([^\"]+)\"", svg)]
        println(io, "  ", concept, " icon/.pic={\\draw[icon, icon line, x=", unit,
            ", y=-", unit, ", shift={(-12,-12)}]", join(paths), ";},")
    end
end

"the paper's soft kite seen from ahead, 100 across with y down and the foot of its control
unit at the origin"
kite_svg = read(joinpath(root, "paper", "drawings", "kite.svg"), String)

"""
    kite_parts

The parts of [`kite_svg`](@ref) but its backdrop, in the order drawn: the class of each
and its [`svg_paths`](@ref).
"""
kite_parts = [(found[1], svg_paths(found[2]))
              for found in eachmatch(r"<path class=\"(\w+)\"[^>]* d=\"([^\"]+)\"", kite_svg)
              if found[1] != "backdrop"]

"""
    kite_part_styles

How each part of [`kite_parts`](@ref) is drawn: its colour, `rig` for the colour the kite
is drawn in, the share of that colour in a tint of it with white, and the size of
[`figure_style`](@ref) it is stroked with, or `nothing` where it is filled.
"""
kite_part_styles = Dict("canopy" => ("rig", 1.0, nothing),
    "intakes" => ("rig", 0.55, nothing), "cells" => ("white", 1.0, "cell"),
    "bridle" => ("rig", 1.0, "bridle"), "tether" => ("rig", 1.0, "rule"),
    "unit" => ("keel", 1.0, nothing))

"extent of the drawn kite of [`kite_parts`](@ref), below and above its foot, over its span"
kite_extent = extrema(-point[2] / 100 for (_, subpaths) in kite_parts
                      for subpath in subpaths for point in polyline(subpath))

"""
    kite_pics(io)

Write to `io` the TikZ picture `kite` of [`kite_parts`](@ref), 1 across, the foot of its
control unit at the origin, in the colour of its argument, `kite` by default; `kite
backdrop`, the white behind its bridle that hides what lies behind the kite; and the `kite
wear icon`, the kite in the colour of an icon, as wide as an icon's drawing.
"""
function kite_pics(io)
    scope = "\\begin{scope}[xscale=0.01, yscale=-0.01]"
    println(io, "  kite/.pic={", scope)
    for (class, subpaths) in kite_parts
        colour, share, size = kite_part_styles[class]
        colour == "rig" && (colour = share == 1 ? "#1" : "#1!$(round(Int, 100share))")
        command = isnothing(size) ? "\\fill[$colour]" :
                  "\\draw[$colour, line width=$(tex_size(size)), line join=round]"
        println(io, "    ", command, tikz_path(subpaths), ";")
    end
    println(io, "  \\end{scope}},")
    println(io, "  pics/kite/.default=kite,")
    backdrop = match(r"class=\"backdrop\"[^>]* d=\"([^\"]+)\"", kite_svg)[1]
    println(io, "  kite backdrop/.pic={", scope, "\\fill[white]",
        tikz_path(svg_paths(backdrop)), ";\\end{scope}},")
    span = figure_style["sizes"]["icon_size"] * 20 / 24
    shift = -sum(kite_extent) / 2 * span
    size = @sprintf("%.3gpt", span)
    println(io, "  kite wear icon/.pic={\\pic[x=", size, ", y=", size, ", yshift=",
        @sprintf("%.3gpt", shift), "] {kite=icon};},")
end

"""
    figure_style_file()

Write [`figure_style`](@ref) to paper/figure_style.tex as xcolor colours and TikZ styles,
with [`label_overlap_check`](@ref); error on any [`tikz_style_faults`](@ref) or
[`palette_faults`](@ref).
"""
function figure_style_file()
    faults = tikz_style_faults()
    isempty(faults) || error("TikZ figures set their own style:\n", join(faults, "\n"))
    faults = palette_faults()
    isempty(faults) || error("colours of the figure style: ", join(faults, "; "))
    write_whole(joinpath(root, "paper", "figure_style.tex")) do io
        println(io, "% Written by the figure_style step from figure_style.toml; edit that.")
        println(io, "\\pdfinclusioncopyfonts=1")
        println(io, "\\usepackage{xcolor}\n\\usepackage{tikz}")
        println(io, "\\usetikzlibrary{positioning,arrows.meta,fit,backgrounds,",
            "decorations.pathreplacing}")
        for (name, hex) in sort(collect(figure_style["colours"]))
            println(io, "\\definecolor{", name, "}{HTML}{", hex, "}")
            dark = Makie.Colors.hex(readable(style_colour(name), white))
            println(io, "\\definecolor{", name, "text}{HTML}{", dark, "}")
        end
        for (name, hex) in sort(collect(figure_style["fills"]))
            println(io, "\\definecolor{", name, "fill}{HTML}{", hex, "}")
        end
        print(io, label_overlap_check)
        println(io, "\\tikzset{")
        println(io, "  >={Stealth[length=", tex_size("arrow_length"), ", width=",
            tex_size("arrow_width"), "]},")
        println(io, "  every picture/.style={line width=", tex_size("rule"), ", font=",
            tex_font("text"), ", execute at end picture=\\figurestylecheck, ",
            "every node/.style={execute at begin node={\\hyphenpenalty=10000\\relax}}},")
        println(io, "  recorded/.style={postaction={decorate, decoration={show path ",
            "construction, lineto code={\\figurestylesegment{\\tikzinputsegmentfirst}",
            "{\\tikzinputsegmentlast}}, curveto code={\\figurestylecurve",
            "{\\tikzinputsegmentfirst}{\\tikzinputsegmentsupporta}",
            "{\\tikzinputsegmentsupportb}{\\tikzinputsegmentlast}}}}},")
        println(io, "  force/.style={->, line width=", tex_size("force"), ", recorded},")
        println(io, "  flow/.style={->, line width=", tex_size("flow"), ", recorded},")
        println(io, "  dimension/.style={<->, guide, line width=", tex_size("dimension"),
            "},")
        println(io, "  leader/.style={guide, line width=", tex_size("dimension"), "},")
        println(io, "  icon line/.style={line width=", tex_size("icon"),
            ", line cap=round, line join=round},")
        println(io, "  hull face/.style={line width=", tex_size("seam"), ", line join=round},")
        println(io, "  crossing/.style={draw=white, line width=", tex_size("crossing"),
            "},")
        println(io, "  label/.style={font=", tex_font("text"), ", inner sep=1pt, ",
            "preaction={fill=white, draw=white, line width=", tex_size("halo"), "}, ",
            "append after command={\\pgfextra{\\figurestylerecord{\\tikzlastnode}}}},")
        println(io, "  note/.style={label, font=", tex_font("note"), "},")
        println(io, "  box/.style={draw, rounded corners=2pt, line width=",
            tex_size("rule"), "},")
        println(io, "  legend box/.style={draw=guide, fill=white, line width=",
            tex_size("rule"), ", inner sep=2pt, font=", tex_font("note"), "},")
        for name in sort(collect(keys(figure_style["fills"])))
            println(io, "  ", name, " box/.style={box, fill=", name, "fill},")
        end
        println(io, "  box title/.style={font=", tex_font("text"), "\\bfseries, ",
            "align=left, inner sep=0pt},")
        println(io, "  box text/.style={align=left, inner sep=0pt},")
        println(io, "  panel/.style={anchor=west, inner sep=0pt},")
        println(io, "  step number/.style={circle, fill=black, text=white, font=",
            tex_font("note"), "\\bfseries, inner sep=0pt, minimum size=", tex_size("step"),
            "},")
        icon_pics(io)
        kite_pics(io)
        println(io, "}")
        println(io, "\\input{figure_pics}")
    end
end

"""
    tikz_style_faults()

Lines of the TikZ figures in paper/sections and of their shared pictures that set a
width, font size, colour or style of their own rather than one of
[`figure_style_file`](@ref): a colour mixed from one that is not in [`figure_style`](@ref)
counts, a tint of one that is does not, and so does
[`faint_text`](@ref).
"""
function tikz_style_faults()
    own = Regex(string("line width|\\b(ultra |very )?(thin|thick)\\b|semithick|/\\.style|",
        "\\\\(definecolor|colorlet|tiny|scriptsize|footnotesize|small)\\b"))
    mixed = r"([A-Za-z]+)!\d"
    faults = String[]
    for file in [filter(endswith(".tex"), readdir(sections; join=true));
                 joinpath(root, "paper", "figure_pics.tex")]
        text = read(file, String)
        occursin("tikzpicture", text) || continue
        for (number, line) in enumerate(split(text, '\n'))
            foreign = any(!haskey(figure_style["colours"], match[1])
                          for match in eachmatch(mixed, line))
            (occursin(own, line) || foreign || !isempty(faint_text(line))) &&
                push!(faults, "$(basename(file)):$number: $(strip(line))")
        end
    end
    return faults
end

"""
    faint_text(line)

The colours of node text and `\\textcolor` in the TikZ `line` that are a colour of
[`figure_style`](@ref) less than [`readable`](@ref) on white, or a tint of one, where its
`<name>text` shade belongs.
"""
function faint_text(line)
    faint = String[]
    options = [option for found in eachmatch(r"node\s*\[([^\]]*)\]", line)
               for option in split(found[1], ',')]
    named = [found[1] for found in eachmatch(r"\\textcolor\{([^}]*)\}", line)]
    for option in [options; named]
        colour = strip(replace(strip(option), r"^text\s*=\s*" => ""))
        name = first(split(colour, '!'))
        haskey(figure_style["colours"], name) || continue
        (occursin('!', colour) || contrast(style_colour(name), white) < least["text"]) &&
            push!(faint, colour)
    end
    return faint
end

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
"figure units of the width of goal lines, laws drawn through data and range bars"
goal_width = style_size("goal")
"figure units of the size of data markers"
marker_size = style_size("marker")
"figure units of the outline of a hollow marker"
outline_width = style_size("outline")
"figure units of the end mark of a range bar"
whisker_width = style_size("whisker")
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

"`value` rounded as an estimate is written, to two significant digits"
rounded_estimate(value) = round(value; sigdigits=2)

"`value` as an estimate is written: to two significant digits, both shown"
function estimate_text(value)
    rounded = rounded_estimate(value)
    iszero(rounded) && return "0"
    return @sprintf("%.*f", max(0, 1 - floor(Int, log10(abs(rounded)))), rounded)
end

"figure units of the halo in the background colour behind each dark label"
halo_width = style_size("halo")

"""
    save_figure(name, figure)

Save `figure` at print size to paper/figures/`name`.pdf, each label in its axes set
[`readable`](@ref) on what lies behind it and drawn on a halo of that colour; error if
[`label_faults`](@ref) finds any.
"""
function save_figure(name, figure)
    Makie.colorbuffer(figure)
    faults = label_faults(figure)
    isempty(faults) || error("labels of figure $name: ", join(faults, "; "))
    labels = axis_labels(figure)
    foreach(redraw_label!, labels, label_backgrounds(figure, labels))
    path = joinpath(figures, "$name.pdf")
    save(path, figure; pt_per_unit=print_scale)
    rename_font_subsets(path, name)
end

"""
    rename_font_subsets(path, name)

Give each font subset in the PDF at `path` a tag of its own, drawn from `name`.
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

"""
    label_backgrounds(figure, labels)

Per text plot of `labels` in `figure`, the colour behind each of its strings: the colour
of median lightness under the string's box, rendered with every label hidden.
"""
function label_backgrounds(figure, labels)
    foreach(label -> label.visible = false, labels)
    image = Makie.colorbuffer(figure)
    foreach(label -> label.visible = true, labels)
    scale = size(image, 2) / widths(figure.scene.viewport[])[1]
    return [[colour_behind(image, scale, Makie.parent_scene(label), box)
             for box in Makie.string_boundingboxes(label)] for label in labels]
end

"""
    colour_behind(image, scale, scene, box)

The colour of median lightness in `image`, of `scale` pixels per figure unit, under `box`
[figure units of `scene`].
"""
function colour_behind(image, scale, scene, box)
    origin = minimum(scene.viewport[])
    low = (origin .+ Point2f(minimum(box)[1:2])) .* scale
    high = (origin .+ Point2f(maximum(box)[1:2])) .* scale
    height, width = size(image)
    rows = (clamp(round(Int, height - high[2]) + 1, 1, height)):(clamp(
        round(Int, height - low[2]), 1, height))
    columns = (clamp(round(Int, low[1]) + 1, 1, width)):(clamp(round(Int, high[1]), 1,
        width))
    pixels = Makie.Colors.RGB{Float32}.(vec(image[rows, columns]))
    isempty(pixels) && return white
    return sort(pixels; by=luminance)[cld(length(pixels), 2)]
end

"the one colour of `colours` where all are equal, else `colours`, one per string"
one_or_each(colours) = allequal(colours) ? first(colours) : colours

"""
    redraw_label!(label, behind)

Hide the text plot `label` and draw it again above every line and fill of its scene,
each string [`readable`](@ref) on its colour `behind` and on a halo of that colour.
"""
function redraw_label!(label, behind)
    isempty(behind) && return
    colours = label.color[] isa AbstractVector ? label.color[] :
              fill(label.color[], length(behind))
    length(colours) == length(behind) || (colours = fill(first(colours), length(behind)))
    halo = copy_label(label; color=one_or_each(behind), strokecolor=one_or_each(behind),
        strokewidth=halo_width)
    redrawn = copy_label(label; color=one_or_each(readable.(colours, behind)))
    translate!(halo, 0, 0, 1)
    translate!(redrawn, 0, 0, 2)
    label.visible = false
end

"a copy of the text plot `label` in its scene, with the attributes `kwargs` changed"
copy_label(label; kwargs...) = text!(Makie.parent_scene(label), label[1];
    text=label.text[], align=label.align[], offset=label.offset[],
    fontsize=label.fontsize[], font=label.font[], rotation=label.rotation[],
    justification=label.justification[], markerspace=label.markerspace[],
    space=label.space[], kwargs...)

"""
    label_faults(figure)

Descriptions of the labels in the axes of `figure` that overlap another label or a legend,
run past the edge of their axis, or lie over a line or marker of the data, and of the
legends in an axis that lie over its data; `figure` laid out.
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
            on_white_box(scene, box) && continue
            for plot in scene.plots
                covers_data(scene, plot, margin) &&
                    push!(faults,
                        "\"$(texts[i])\" lies over a $(Makie.plotfunc(plot)) plot")
            end
        end
        for legend in axis_legends(figure, block)
            any(box -> overlaps(box, legend), boxes) &&
                push!(faults, "a legend overlaps a label")
            for plot in scene.plots
                legend_covers(scene, plot, legend) &&
                    push!(faults, "a legend lies over a $(Makie.plotfunc(plot)) plot")
            end
        end
        append!(faults, tick_faults(block.xaxis), tick_faults(block.yaxis))
    end
    return unique([faults; legend_bound_faults(figure)])
end

"""
    legend_bound_faults(figure)

Descriptions of the legends of `figure` that run past its edge, or past the edge of an
axis they lie partly inside; `figure` laid out.
"""
function legend_bound_faults(figure)
    page = Rect2f(figure.scene.viewport[])
    axes = [Rect2f(block.scene.viewport[]) for block in figure.content if block isa Axis]
    faults = String[]
    for block in figure.content
        block isa Legend || continue
        box = Rect2f(block.layoutobservables.computedbbox[])
        in_axis(box, page) || push!(faults, "a legend runs past the figure")
        any(axis -> overlaps(box, axis, 0) && !in_axis(box, axis), axes) &&
            push!(faults, "a legend runs past its axis")
    end
    return faults
end

"the gap [figure units] [`tick_faults`](@ref) asks of two tick labels side by side"
tick_gap = style_size("tick_gap")

"""
    tick_faults(side)

Descriptions of the tick labels of the axis `side` of an `Axis` whose [`em_boxes`](@ref)
come closer than [`tick_gap`](@ref) along their lines or overlap across them; none where
its tick labels are hidden.
"""
function tick_faults(side)
    plot = side.elements[:ticklabels]
    plot.visible[] || return String[]
    texts = string.(side.ticklabels[])
    labels = [(text, box) for (text, box) in zip(texts, em_boxes(plot)) if !isempty(text)]
    return ["tick labels \"$(first(labels[i]))\" and \"$(first(labels[j]))\" touch"
            for i in eachindex(labels) for j in (i + 1):length(labels)
            if overlaps(last(labels[i]), last(labels[j]), Vec2f(tick_gap, 0))]
end

"""
    em_boxes(plot)

The boxes [figure units] of the strings of the text plot `plot`, each as wide as its
glyphs' advance and as tall as their em squares, in the frame its rotation turns it into.
"""
function em_boxes(plot)
    Makie.string_boundingboxes(plot)
    glyphs = Makie.raw_glyph_boundingboxes(plot)
    sizes = plot.text_scales[]
    origins = plot.glyph_origins[]
    rotations = plot.text_rotation[]
    return [isempty(block) ? Rect2f(Point2f(position[1:2]), Vec2f(0)) :
            mapreduce(union, block) do i
                em_box(glyphs[i], sizes[i][2], position .+ origins[i], rotations[i])
            end
            for (block, position) in zip(plot.text_blocks[], plot.markerspace_positions[])]
end

"""
    em_box(glyph, size, point, rotation)

The box [figure units] of the em square of a glyph whose unturned line box is `glyph`, of
font size `size` and origin `point`, in the frame `rotation` turns it into.
"""
function em_box(glyph, size, point, rotation)
    turned = (conj(rotation) * Point3d(point))[1:2]
    low = minimum(glyph) .+ (0, (widths(glyph)[2] - size) / 2)
    return Rect2f(Point2f(low .+ turned), Vec2f(widths(glyph)[1], size))
end

"the boxes [pixels of the scene of `axis`] of the legends of `figure` inside `axis`"
function axis_legends(figure, axis)
    viewport = Rect2f(axis.scene.viewport[])
    boxes = [Rect2f(block.layoutobservables.computedbbox[]) for block in figure.content
             if block isa Legend]
    return [Rect2f(minimum(box) .- minimum(viewport), widths(box)) for box in boxes
            if in_axis(box, viewport)]
end

"whether a legend of box `box` [pixels of `scene`] lies over the data of `plot`"
legend_covers(scene, plot, box) = covers_data(scene, plot, box) ||
                                  covers_bars(scene, plot, box) ||
                                  covers_band(scene, plot, box)

"""
    clear_axislegend(figure, axes, contents...; kwargs...)

An `axislegend` of `contents` and `kwargs` in the first corner, top right first, of the
first of `axes` where it covers no data and no other legend, or in the top right of the
first where none is clear.
"""
function clear_axislegend(figure, axes, contents...; kwargs...)
    for position in (:rt, :lt, :rb, :lb), axis in axes
        others = axis_legends(figure, axis)
        legend = axislegend(axis, contents...; position, kwargs...)
        Makie.update_state_before_display!(figure)
        box = only(setdiff(axis_legends(figure, axis), others))
        any(plot -> legend_covers(axis.scene, plot, box), axis.scene.plots) ||
            any(other -> overlaps(box, other), others) || return legend
        delete!(legend)
    end
    return axislegend(first(axes), contents...; position=:rt, kwargs...)
end

"whether `box` [pixels of `scene`] lies on a white rectangle drawn in `scene`"
on_white_box(scene, box) = any(plot isa Makie.Poly && plot[1][] isa Rect &&
                               Makie.to_color(plot.color[]) == Makie.to_color(:white) &&
                               in_axis(box, pixel_rect(scene, plot[1][]))
                               for plot in scene.plots)

"the rectangle `rect` [data of `scene`] in pixels of `scene`"
function pixel_rect(scene, rect)
    corners = [pixel_point(scene, corner) for corner in (minimum(rect), maximum(rect))]
    low, high = min.(corners...), max.(corners...)
    return Rect2f(Point2f(low[1], low[2]), Vec2f(high[1] - low[1], high[2] - low[2]))
end

"the point `point` [data of `scene`] in pixels of `scene`, through its axis scales"
function pixel_point(scene, point)
    scaled = Makie.apply_transform(Makie.transform_func(scene),
        Point3f(point[1], point[2], 0))
    return Point2f(Makie.project(scene, :data, :pixel, scaled)[1:2])
end

"the strings of the text plot `plot`, one per label"
label_texts(plot) = (text = plot.text[]; text isa AbstractVector ? string.(text) :
                                          [string(text)])

"clearance [figure units] a label keeps from other labels and from lines and markers"
label_clearance = style_size("clearance")

"whether the rectangles `box` and `other` come closer than `clearance`"
overlaps(box, other, clearance=label_clearance) =
    all(min.(maximum(box), maximum(other)) .- max.(minimum(box), minimum(other)) .>
        -clearance)

"whether `box` lies within `inside`, to half a point"
in_axis(box, inside) = all(minimum(box) .>= minimum(inside) .- pt(0.5)) &&
                       all(maximum(box) .<= maximum(inside) .+ pt(0.5))

"""
    covers_data(scene, plot, box)

Whether `box` [pixels of `scene`] covers a vertex or crosses a segment of `plot`, when it
is a line, scatter, range or error bar plot of data.
"""
function covers_data(scene, plot, box)
    plot isa Union{Makie.Rangebars, Makie.Errorbars} &&
        return any(bar -> bar.space[] == :data && covers_data(scene, bar, box), plot.plots)
    plot isa Union{Makie.Lines, Makie.Scatter, Makie.LineSegments, Makie.Arrows2D} ||
        return false
    data = plot isa Makie.Arrows2D ?
           [point for (tail, vector) in zip(plot[1][], plot[2][])
            for point in (tail, tail + vector)] : plot[1][]
    points = [pixel_point(scene, point) for point in data]
    plot isa Makie.Scatter && return any(in(box), filter(point -> all(isfinite, point),
        points))
    steps = plot isa Union{Makie.LineSegments, Makie.Arrows2D} ?
            (1:2:(length(points) - 1)) :
            (1:(length(points) - 1))
    return any(segment_crosses(points[k], points[k + 1], box) for k in steps
               if all(isfinite, points[k]) && all(isfinite, points[k + 1]))
end

"whether `box` [pixels of `scene`] comes within the clearance of a bar of `plot`"
covers_bars(scene, plot, box) = plot isa Makie.BarPlot &&
    any(bar -> overlaps(pixel_rect(scene, bar), box),
        filter(bar -> bar isa Rect, first(plot.plots)[1][]))

"""
    covers_band(scene, plot, box)

Whether `box` [pixels of `scene`] lies over the shaded range of `plot`, when it is a band,
sampled every half point along the band.
"""
function covers_band(scene, plot, box)
    plot isa Makie.Band || return false
    lower, upper = ([pixel_point(scene, point) for point in plot[side][]] for side in 1:2)
    for k in 1:(length(lower) - 1)
        samples = max(1, ceil(Int, abs(lower[k + 1][1] - lower[k][1]) / pt(0.5)))
        for fraction in (0:samples) ./ samples
            segment_crosses(lower[k] + (lower[k + 1] - lower[k]) * fraction,
                upper[k] + (upper[k + 1] - upper[k]) * fraction, box) && return true
        end
    end
    return false
end

"whether the segment from `start` to `stop` passes through `box`, sampled every half point"
function segment_crosses(start, stop, box)
    samples = max(2, ceil(Int, hypot((stop - start)...) / pt(0.5)))
    return any(in(start + (stop - start) * (k / samples), box) for k in 0:samples)
end

"""
    square_metres(before, after="")

Rich text of `before`, the unit square metre as m with a raised digit 2, and `after`.
"""
square_metres(before, after="") = rich(before, "m", superscript("2"), after)

"`text` with its leading hyphen set as `minus`, by default the one the axes print"
typeset_minus(text, minus="−") = replace(text, r"^-" => minus)
"the [`study_drives`](@ref) with their names in figure labels"
drive_labels = [string(drive) => Dict(:vlsfo => "VLSFO", :ammonia => "e-ammonia")[drive]
                for drive in study_drives]
"(drive, panel title) of the panels (a), (b) of a figure with one panel per drive"
drive_panels = [(drive, "($(Char('a' + k - 1))) $label")
                for (k, (drive, label)) in enumerate(drive_labels)]
"each rig with the area [m^2] it is trimmed at on the 140 m VLSFO ship in 10 m/s wind"
trim_rigs = (("kite", 800.0), ("wings", 800.0), ("rotors", 400.0))

"""
    kite_figure()

The kite the paper flies, at the design aspect ratio and 100 m²: (a) seen from above,
leading edge at the top, and from ahead, and its lift and drag coefficients (b) and glide
ratio (c) in the design shape over angle of attack, without bridle and tether.
"""
function kite_figure()
    aspect_ratio = isinteger(design_aspect_ratio) ? Int(design_aspect_ratio) :
                   design_aspect_ratio
    geometry = read_table(joinpath(polars, "geometry_ar$aspect_ratio.csv"))
    polar = read_table(joinpath(polars, "kite_ar$aspect_ratio.csv"))
    figure = Figure(size=(page_width, 150))
    shape = Axis(figure[1, 1]; autolimitaspect=1, title="(a) from above and ahead")
    hidedecorations!(shape)
    hidespines!(shape)
    above = [Point2f.(geometry["le_y"], -geometry["le_x"]);
        Point2f.(reverse(geometry["te_y"]), -reverse(geometry["te_x"]))]
    poly!(shape, above; color=palette[1], strokecolor=:black, strokewidth=0.8)
    span = maximum(geometry["le_y"]) - minimum(geometry["le_y"])
    trailing = -maximum(geometry["te_x"])
    text!(shape, 0, trailing; text="span $(round(span; digits=1)) m",
        align=(:center, :top), offset=(0, -pt(2)), fontsize=note_size)
    margin = 1
    wind = Point2f(0.5span + 1.5margin, -minimum(geometry["le_x"]))
    arrows2d!(shape, [wind], [Vec2f(0, trailing - wind[2])]; color=:black,
        shaftwidth=flow_width)
    text!(shape, wind; text="wind", align=(:center, :bottom), offset=(0, pt(1)),
        fontsize=note_size)
    front = trailing - 4margin
    lines!(shape, -geometry["le_y"], geometry["le_z"] .+ front; color=palette[1],
        linewidth=3)
    limits!(shape, -0.5span - margin, wind[1] + 1.5margin,
        front + minimum(geometry["le_z"]) - margin, wind[2] + 2.5margin)
    angle = "angle of attack [°]"
    coefficients = Axis(figure[1, 2]; xlabel=angle, ylabel="coefficient",
        title="(b) lift and drag")
    lines!(coefficients, polar["alpha"], polar["cl"]; color=palette[1],
        label=L"C_L")
    lines!(coefficients, polar["alpha"], polar["cd"]; color=palette[1],
        linestyle=:dash, label=L"C_D")
    axislegend(coefficients; position=:lt)
    glide = Axis(figure[1, 3]; xlabel=angle, ylabel=L"G = C_L/C_D",
        title="(c) glide ratio")
    lines!(glide, polar["alpha"], polar["cl"] ./ polar["cd"]; color=palette[1])
    colsize!(figure.layout, 1, Relative(0.3))
    save_figure("kite", figure)
end

"classes whose wind-load coefficients the wind-load figure shows, in deadweight order"
wind_load_classes = ("general cargo coaster", "PCTC car carrier", "Aframax tanker",
    "Megamax container ship")

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
    deck_rig_figure()

Write paper/figures/deck_rigs.pdf: the model of the deck rigs, (a) the lift over drag of
wing sails and suction sails at each trim, attached and stalled, (b) the rotor's lift, drag
and spin power over spin ratio, and (c) the thrust factor of wings and rotors in one row
and in two columns over their number, at the closest spacing.
"""
function deck_rig_figure()
    figure = Figure(size=(page_width, 170))
    polar = Axis(figure[1, 1]; xlabel=L"C_D", ylabel=L"C_L",
        title="(a) wing and suction sails, over their trim")
    for rig in ("wings", "suction")
        ship = Ship(ShipDesign(:vlsfo, 140.0; rig_size(rig, 800.0)...), assumptions)
        trims = WindShipOpt.trim_ranges(ship.rig, ship.env, 10.0, π / 2, 5.0)
        for (trim, style) in zip(trims, (:solid, :dash))
            settings = WindShipOpt.trim_setting.(Ref(ship.rig), Ref(trim),
                range(trim.low, trim.high; length=100))
            lines!(polar, last.(settings), first.(settings); color=rig_colour(rig),
                linestyle=style)
        end
    end
    axislegend(polar, [LineElement(; color=rig_colour("wings")),
            LineElement(; color=rig_colour("suction")), LineElement(; color=:black),
            LineElement(; color=:black, linestyle=:dash)],
        ["wing", "suction", "attached", "stalled"]; position=(0.98, 0.12))
    spins = range(0, WindShipOpt.MAX_SPIN_RATIO; length=100)
    coefficients = WindShipOpt.rotor_coefficients.(spins)
    rotor = Axis(figure[1, 2]; xlabel=L"spin ratio $\alpha$", ylabel="coefficient",
        title="(b) rotor, over its spin")
    lift = assumptions[:rotor_lift_factor] .* first.(coefficients)
    lines!(rotor, spins, lift; color=palette[3], label=L"C_L")
    lines!(rotor, spins, getindex.(coefficients, 2); color=palette[3], linestyle=:dash,
        label=L"C_D")
    lines!(rotor, spins, last.(coefficients); color=palette[3], linestyle=:dot,
        label=L"C_{P,\mathrm{spin}}")
    axislegend(rotor; position=:lt)
    shading = Axis(figure[1, 3]; xlabel=L"units $n$", ylabel=L"thrust factor $f$",
        title="(c) shading at the closest spacing", xticks=2:2:8,
        limits=(nothing, (0.45, 1.0)))
    for (unit, colour) in ((:wing, palette[2]), (:rotor, palette[3]))
        setting(name) = assumptions[Symbol(unit, name)]
        spacing, decay = setting(:_spacing), setting(:_interference_decay)
        amplitude = setting(:_interference_amplitude)
        abreast = setting(:_abreast_loss) * amplitude
        counts = 2:2:8
        row = WindShipOpt.array_factor.(counts, spacing, amplitude, decay)
        columns = WindShipOpt.array_factor.(counts .÷ 2, spacing, amplitude, decay) .*
                  WindShipOpt.array_factor(2, spacing, abreast, decay)
        scatterlines!(shading, counts, row; color=colour, markersize=marker_size)
        scatterlines!(shading, counts, columns; color=colour, linestyle=:dash,
            markersize=marker_size)
    end
    elements = [LineElement(; color=palette[2]), LineElement(; color=palette[3]),
        LineElement(; color=:black), LineElement(; color=:black, linestyle=:dash)]
    axislegend(shading, elements, ["wing sails", "rotors", "one row", "two columns"];
        position=:lb)
    save_figure("deck_rigs", figure)
end

"""
    pattern_figure()

Optimal flight paths seen from the ship looking downwind, positive azimuth to the left,
over the course off apparent downwind, a ring where the kite is held still, nested where
still kites share a point, in light and strong apparent wind, without side-force weight,
and the thrust and side force they put on the ship, on one force scale.
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
            xreversed=true, xlabel=bottom ? "azimuth off apparent downwind [°]" : "",
            title="($(('a', 'b')[row])) flight paths, $speed")
        held = Dict{NTuple{2, Float64}, Int}()
        for (i, course) in enumerate(courses)
            chosen = rows(paths, "wind" => wind, "course" => course, "side_weight" => 0.0)
            isempty(chosen) && continue
            azimuths = rad2deg.(paths["azimuth"][chosen])
            elevations = rad2deg.(paths["elevation"][chosen])
            if allequal(azimuths) && allequal(elevations)
                point = (round(azimuths[1]; digits=1), round(elevations[1]; digits=1))
                rings = held[point] = get(held, point, 0) + 1
                scatter!(axis, [point]; color=:transparent, strokecolor=colours[i],
                    strokewidth=line_width, markersize=marker_size * (1 + rings))
            else
                lines!(axis, azimuths, elevations; color=colours[i])
            end
        end
        bottom || hidexdecorations!(axis; ticks=false, ticklabels=false)
        thrust = Axis(figure[row, 3]; ylabel="force [kN]", limits=((-10, 190),
                (low - 30, high + 30)),
            xlabel=bottom ? "course off apparent downwind [°]" : "", xticks=0:30:180,
            yticks=-400:100:400, title="($(('c', 'd')[row])) force on the ship, $speed")
        bottom || hidexdecorations!(thrust; ticks=false, ticklabels=false)
        reference_line!(thrust)
        chosen = rows(forces, "wind" => wind, "side_weight" => 0.0)
        for (k, (column, label, marker)) in enumerate((("thrust", "thrust", :circle),
            ("side", "side force", :rect)))
            scatterlines!(thrust, forces["course"][chosen], forces[column][chosen] ./ 1e3;
                color=category_colours[k], label, marker)
        end
        bottom || axislegend(thrust; position=:rt)
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
    normals = [0.2 .* (x, y + 1.0) for (x, y) in wedge]
    arrows2d!(axis, first.(wedge), last.(wedge), first.(normals), last.(normals);
        color=category_colours[1])
    arrows2d!(axis, [0.0], [1.0], [0.0], [-2.5]; color=palette[1])
    text!(axis, 0.0, 1.5; text=L"p = F/A = %$(round(Int, pressure))\,\mathrm{N/m^2}",
        align=(:center, :bottom), color=category_colours[1])
    text!(axis, -0.35, -0.9;
        text=L"F = %$(round(force / 1e6; digits=1))\,\mathrm{MN}", align=(:right, :bottom),
        offset=(0, pt(1)), color=palette[1])
    text!(axis, -0.35, -0.9; text=L"A = %$(round(Int, area))\,\mathrm{m^2}",
        align=(:right, :top), offset=(0, -pt(1)), color=palette[1])
    left, right = (3.0, 0.0), (6.8, 0.0)
    centre = ((left[1] + right[1]) / 2, -0.75)
    reach = hypot(left[1] - centre[1], centre[2])
    opening = atan(-centre[2], right[1] - centre[1])
    lines!(axis, arc(centre, reach, range(opening, π - opening; length=40)); color=:black,
        linewidth=2)
    lines!(axis, [left, (left[1], -1.3)]; color=:gray60, linewidth=2)
    lines!(axis, [right, (right[1], -1.3)]; color=:gray60, linewidth=2)
    arrows2d!(axis, [centre[1]], [centre[2]], [0.0], [reach]; color=:gray40)
    text!(axis, centre[1], centre[2] + reach / 3;
        text=L"R = %$(round(radius; digits=1))\,\mathrm{m}", align=(:right, :center),
        offset=clear_offset((:right, :center), pt(3)))
    for (corner, side) in ((left, 1), (right, -1))
        outward = 0.12 .* (corner .- centre) ./ reach
        arrows2d!(axis, [corner[1] + outward[1]], [corner[2] + outward[2]],
            [0.8side * sin(opening)], [0.8cos(opening)]; color=category_colours[2])
    end
    tension = round(Int, pressure * radius)
    text!(axis, centre[1], centre[2] + reach;
        text=L"T = p\,R = %$(tension)\,\mathrm{N/m}", align=(:center, :bottom),
        offset=clear_offset((:center, :bottom), pt(3)), color=category_colours[2])
    text!(axis, left[1] - 0.1, -0.8; text="rib", fontsize=note_size,
        align=(:right, :center), color=:gray40)
    arrows2d!(axis, [1.9], [0.3], [0.8], [0.0]; color=:gray60)
    hidedecorations!(axis)
    hidespines!(axis)
end

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
    skin_radius = assumptions[:canopy_skin_radius]
    tension(force) = 1e3force / area * skin_radius
    strength = assumptions[:canopy_cloth_specific_strength] *
               WindShipOpt.cloth_weight(assumptions) / 1e3
    figure = Figure(size=(page_width, 185))
    balance = Axis(figure[1, 1]; autolimitaspect=1, limits=(-2.4, 7.3, -1.7, 2.2),
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
    above = longest_run(forces .>= mean_force)
    text!(force_axis, (times[first(above)] + times[last(above)]) / 2, mean_force;
        text=@sprintf("mean %s MN\n%s kN/m", estimate_text(mean_force),
            estimate_text(tension(mean_force))),
        fontsize=note_size, align=(:center, :top), color=category_colours[1],
        offset=clear_offset((:center, :top), pt(2)))
    text!(force_axis, times[1], peak_force;
        text=@sprintf("peak %s MN, %s kN/m\nnew cloth about %s kN/m, %s × peak",
            estimate_text(peak_force), estimate_text(tension(peak_force)),
            estimate_text(strength),
            estimate_text(strength / tension(peak_force))),
        fontsize=note_size, align=(:left, :bottom), color=category_colours[2],
        offset=clear_offset((:left, :bottom), pt(2)))
    colsize!(figure.layout, 1, Relative(0.52))
    save_figure("canopy_tension", figure)
end

"the indices of the longest unbroken run of `true` in `flags`"
function longest_run(flags)
    starts = findall(k -> flags[k] && (k == 1 || !flags[k - 1]), eachindex(flags))
    runs = [start:(something(findnext(!, flags, start), length(flags) + 1) - 1)
            for start in starts]
    return runs[argmax(length.(runs))]
end

"""
    rig_polar_figure()

Thrust and side force of the best trim over true wind angle on a 140 m ship at 10.5 kn in
10 m/s wind, for an 800 m^2 kite, 800 m^2 of wings and 400 m^2 of rotors.
"""
function rig_polar_figure()
    figure = Figure(size=(column_width, 398))
    thrust = Axis(figure[1, 1]; title="(a) thrust", ylabel="thrust [kN]", xticks=30:30:180,
        yautolimitmargin=(0, 0.08))
    side = Axis(figure[2, 1]; title="(b) side force", xlabel="true wind angle [°]",
        ylabel="side force [kN]", xticks=30:30:180, yautolimitmargin=(0, 0.05))
    angles = 30:5:180
    labels = [square_metres("$(rig_label(rig)) $(round(Int, area)) ")
              for (rig, area) in trim_rigs]
    for (i, (rig, area)) in enumerate(trim_rigs)
        ship = Ship(ShipDesign(:vlsfo, 140.0; rig_size(rig, area)...), assumptions)
        label = labels[i]
        forces = [WindShipOpt.best_trim(ship, ship.rig, 10.5KNOT, 10.0,
                      deg2rad(angle)).force for angle in angles]
        lines!(thrust, angles, [force.thrust for force in forces] ./ 1e3;
            color=palette[i], label)
        lines!(side, angles, abs.([force.side for force in forces]) ./ 1e3;
            color=palette[i])
    end
    entries = [LineElement(color=palette[i]) for i in eachindex(trim_rigs)]
    axislegend(side, entries, labels; position=:rt)
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
        axis = Axis(figure[1, column]; title, xlabel="ship length [m]",
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

Weather-routed passages of route_tracks.csv on every route of a 140 m e-ammonia ship
without a rig and with the reference kite, for a winter and a summer departure, over the
10 m wind five days after departure with a reference arrow; solid outbound, dashed homeward.
"""
function route_figure()
    route_colours = category_colours[[1, 2, 3, 4, 6, 5]]
    tracks = read_table(data_file("route_tracks.csv"))
    kite_area = Dict(reference_rigs)["kite"]
    wind_scale, reference_wind = 0.4, 10
    figure = Figure(size=(page_width, 255))
    for (column, (season, departure)) in enumerate(track_seasons())
        axis = Axis(figure[1, column]; title="($('a' + column - 1)) $season departure",
            xlabel="longitude [°]",
            ylabel=column == 1 ? "latitude [°]" : "", aspect=DataAspect(),
            limits=(-100, 12, -26, 60))
        draw_land!(axis, mask; lons=-100:0.25:12, lats=-26:0.25:60)
        draw_wind!(axis, weather, departure + 24 * 5; scale=wind_scale, lons=-96:6:6,
            lats=-22:6:50)
        for (k, area) in enumerate((0.0, kite_area))
            for (i, name) in reverse(collect(enumerate(route_names))),
                (direction, style) in (("out", :solid), ("back", :dash))
                leg = rows(tracks, "season" => season, "route" => string(name),
                    "kite_area" => area, "direction" => direction)
                isempty(leg) && error("no $direction track on $name in $season")
                path = tuple.(tracks["lat"][leg], tracks["lon"][leg])
                k == 1 && direction == "out" &&
                    lines!(axis, great_circle(first(path), last(path))...;
                        color=:black, linestyle=:dot, linewidth=0.8)
                scatterlines!(axis, track_points(path);
                    color=k == 1 ? (:black, 0.6) : route_colours[i], linestyle=style,
                    linewidth=k == 1 ? 0.8 : 1.5, markersize=pt(k == 1 ? 2.5 : 3.5))
            end
        end
        column == 1 &&
            wind_key!(axis, Point2f(-98, 51.5), reference_wind, wind_scale, 7)
    end
    entries = [[LineElement(color=route_colours[i]) for i in eachindex(route_names)];
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
    passage_rows(table, file, rig, area)

Rows of `table`, read from `file`, of the ship with `rig` of `area` [m^2]; errors where
there are none.
"""
function passage_rows(table, file, rig, area)
    found = rows(table, "rig" => rig, "area" => area)
    isempty(found) && error("no rows in $file for the $rig of $area m^2")
    return found
end

"""
    passage_figure()

One winter outbound passage to Guadeloupe of a 140 m e-ammonia ship without a rig and
with each rig, from passage_tracks.csv and passage_traces.csv: the routed tracks through
the corridor's nodes over the 10 m wind six days after departure, each in the colour of its
ship, and the speed, rig thrust and fuel power at each sample of the passage.
"""
function passage_figure()
    tracks = read_table(data_file("passage_tracks.csv"))
    traces = read_table(data_file("passage_traces.csv"))
    rigs = reference_rigs_and_none
    design_colours = [:black; palette[eachindex(rig_names)]]
    names = [rig == "none" ? "no rig" :
             square_metres("$(rig_label(rig)) $(round(Int, area)) ")
             for (rig, area) in rigs]
    figure = Figure(size=(page_width, 410))
    map_axis = Axis(figure[1, 1:3]; aspect=DataAspect(), limits=(-64, 10, 13, 56),
        xlabel="longitude [°]", ylabel="latitude [°]", title="(a) routed tracks")
    draw_land!(map_axis, mask)
    wind_scale = 0.3
    draw_wind!(map_axis, weather, departures[1] + 24 * 6; scale=wind_scale)
    paths = map(rigs) do (rig, area)
        stages = passage_rows(tracks, "passage_tracks.csv", rig, area)
        return tuple.(tracks["lat"][stages], tracks["lon"][stages])
    end
    lines!(map_axis, great_circle(first(paths[1]), last(paths[1]))...; color=:black,
        linestyle=:dot, linewidth=0.8)
    points = track_points.(paths)
    for (i, track) in enumerate(points)
        lines!(map_axis, track; color=design_colours[i],
            linewidth=pt(1 + 0.9(length(points) - i)))
    end
    scatter!(map_axis, unique(reduce(vcat, points)); color=:black, markersize=pt(2.5))
    labels = ("speed [kn]", "rig thrust [kN]", "fuel power [MW]")
    titles = ("(b) speed through the water", "(c) rig thrust", "(d) fuel power")
    panels = [Axis(figure[3, column]; ylabel=labels[column], title=titles[column],
                  xlabel="days since departure",
                  yticks=WilkinsonTicks(4; Q=[(1.0, 1.0), (5.0, 0.9), (2.0, 0.7)]),
                  yscale=column == 2 ? log10 : identity)
              for column in 1:3]
    ylims!(panels[2], 3, 3000)
    panels[2].yticks = [10, 100, 1000]
    for (i, (rig, area)) in enumerate(rigs)
        samples = passage_rows(traces, "passage_traces.csv", rig, area)
        thrust = [value >= 5 ? value : NaN for value in traces["rig_thrust"][samples]]
        for (panel, values) in zip(panels, (traces["speed"][samples], thrust,
            traces["fuel_power"][samples]))
            stairs!(panel, traces["time"][samples] ./ 24, values; step=:post,
                color=design_colours[i])
        end
    end
    linkxaxes!(panels...)
    legend = Legend(figure[2, 1:3],
        [[LineElement(; color=design_colours[i]) for i in eachindex(rigs)];
         PolyElement(; color=(:grey, 0.55))], [names; "land"];
        orientation=:horizontal, tellwidth=false)
    key_size = (10wind_scale + 2.8 * 3, 3) .+ 0.4
    key = Axis(figure[2, 1:3]; tellwidth=false, tellheight=false,
        limits=(-0.2, key_size[1] - 0.2, -0.2, key_size[2] - 0.2))
    hidedecorations!(key)
    hidespines!(key)
    wind_key!(key, Point2f(0, 0), 10, wind_scale, 3)
    rowsize!(figure.layout, 1, Relative(0.64))
    rowgap!(figure.layout, 1, pt(4))
    Makie.colorbuffer(figure)
    key.width, key.height = key_size .* (widths(map_axis.scene.viewport[])[1] /
                                         widths(map_axis.finallimits[])[1])
    total, legend_width = widths(figure.scene.viewport[])[1],
    widths(legend.layoutobservables.computedbbox[])[1]
    legend.halign = (total - legend_width - pt(6) - key.width[]) / 2 /
                    (total - legend_width)
    Makie.colorbuffer(figure)
    key.halign = (maximum(legend.layoutobservables.computedbbox[])[1] + pt(6)) /
                 (total - key.width[])
    save_figure("passage", figure)
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
    lead_text(lead)

Text and colour of the [`rig_lead`](@ref) `lead` beside its row: the rig that leads and its
margin [points] in its colour, the two rigs that are level, or that no rig clearly saves.
"""
function lead_text(lead)
    lead.verdict == "none" && return ("no rig saves", :black)
    lead.verdict == "level" &&
        return ("$(rig_label(lead.rig)) = $(rig_label(lead.rival))", :black)
    return (@sprintf("%s +%.1f", rig_label(lead.rig), lead.margin), rig_colour(lead.rig))
end

"distance [rows] between the lines of neighbouring rigs within one row"
lane_offset = 0.28
"size of the marker of a mean drawn over the bar of its range"
mean_marker_size = 1.5marker_size
"colour of the bar of the range of rig `j` of `rig_names` under the marker of its mean"
range_colour(j) = (palette[j], 0.5)

"""
    savings_panel!(axis, table, groups, drive)

Draw on `axis`, per `(label, classes)` of `groups` of the class table `table` on `drive`,
a row with a line for each rig run there: its [`mean_savings`](@ref) of cost as a marker
over a thin bar spanning its [`route_savings`](@ref), and beside the row the
[`lead_text`](@ref) of the [`rig_lead`](@ref) over the classes' [`fleet_cells`](@ref).
"""
function savings_panel!(axis, table, groups, drive)
    cells = fleet_cells(table, drive)
    rigs = study_rigs(table)
    for (i, (_, classes)) in enumerate(groups)
        iseven(i) && hspan!(axis, i - 0.5, i + 0.5; color=(:gray, 0.12))
        for (slot, (j, kind)) in enumerate(rigs)
            y = i + rig_offset(slot, length(rigs), lane_offset)
            values = route_savings(table, "cost", classes, drive, kind)
            isempty(values) && continue
            rangebars!(axis, [y], [minimum(values)], [maximum(values)]; direction=:x,
                color=range_colour(j), linewidth=goal_width, whiskerwidth=0)
            scatter!(axis, [only(mean_savings(table, ("cost",), classes, drive, kind))],
                [y]; color=palette[j], marker=rig_markers[j], markersize=mean_marker_size)
        end
    end
    span = extrema([reduce(vcat, [route_savings(table, "cost", classes, drive, kind)
                                  for (_, classes) in groups, (_, kind) in rigs]); 0])
    width = span[2] - span[1]
    low, high = span[1] - 0.04width, span[2] + 0.5width
    for (i, (_, classes)) in enumerate(groups)
        text, color = lead_text(rig_lead(filter(cell -> cell.class in classes, cells)))
        text!(axis, high, i; text, color, align=(:right, :center), fontsize=note_size,
            offset=clear_offset((:right, :center), pt(2.5)))
    end
    reference_line!(axis; vertical=true)
    hlines!(axis, length(groups) - 1.5; color=:black, linewidth=rule_width)
    limits!(axis, low, high, length(groups) + 0.5, 0.5)
    axis.xticks = Makie.get_tickvalues(
        Makie.WilkinsonTicks(4; k_min=3, Q=[(1.0, 1.0), (5.0, 0.9), (2.0, 0.7)]), span...)
end

"""
    class_comparison_figure()

Cost saving of the best size of each rig for every ship class and the mean of the
deadweight-limited and of the space-limited classes, a [`savings_panel!`](@ref) per drive.
"""
function class_comparison_figure()
    table = compared_table()
    groups = [[(name, [name]) for name in class_order(table)];
              [("mean, $limit-limited", names) for (limit, names) in limit_groups(table)]]
    figure = Figure(size=(page_width, 400))
    for (k, (drive, title)) in enumerate(drive_panels)
        axis = Axis(figure[1, k]; title, xlabel="cost saving [%]",
            yticks=(eachindex(groups), first.(groups)), yreversed=true,
            yticklabelsvisible=k == 1, ygridvisible=false)
        savings_panel!(axis, table, groups, drive)
    end
    Legend(figure[2, 1:length(drive_panels)],
        [[LineElement(; color=range_colour(j), linewidth=goal_width),
          MarkerElement(; color=palette[j], marker=rig_markers[j],
              markersize=mean_marker_size)]
         for (j, _) in study_rigs(table)], [rig_label(rig) for (_, rig) in study_rigs(table)];
        orientation=:horizontal, tellwidth=false)
    rowgap!(figure.layout, 1, pt(4))
    save_figure("class_comparison", figure)
end

"""
    sweep_measures(table, drive, rig, class)

The cost saving [%], its part from time [points] and the speed the rig adds [kn], each the
mean over the routes, of the cheapest size of `rig` on `drive` for `class` at each of the
[`swept_cargo_values`](@ref) of `table`, as three vectors.
"""
function sweep_measures(table, drive, rig, class)
    saving, time, speed = (Float64[] for _ in 1:3)
    for value in swept_cargo_values(table)
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
    reference_line!(axis; vertical=true)
    rigs = study_rigs(table)
    for (slot, (j, kind)) in enumerate(rigs), level in (:high, :low)
        factor = cargo_interest_factors()[level]
        level_table = interest_level_rows(table, factor)
        y = eachindex(names) .+ rig_offset(slot, length(rigs), 0.22)
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
    table = read_table(study_file(:cargo_interest, "cargo_interest.csv"))
    drive = string(last(study_drives))
    names = class_order(interest_level_rows(table, cargo_interest_factors().low))
    figure = Figure(size=(page_width, 400))
    classes_axis = Axis(figure[1:3, 1]; title="(a) cargo interest",
        xlabel="cost saving [%]", yticks=(eachindex(names), names), yreversed=true)
    interest_classes_panel!(classes_axis, table, drive, names)
    values = swept_cargo_values(table)
    sweep_axes = [Axis(figure[i, 2]; title, ylabel,
                      doubling_axis(:x, extrema(values)...; base=100)...,
                      xlabel=i == 3 ? "cargo value [USD/t]" : "", xticklabelsvisible=i == 3,
                      yautolimitmargin=(0.05, 0.12))
                  for (i, (title, ylabel)) in enumerate((("(b) cost saving",
            "cost saving [%]"),
        ("(c) part of the saving from time", "time [points]"),
        ("(d) speed the rig adds", "speed [kn]")))]
    class_styles = (:solid, :dash)
    rigs = study_rigs(table)
    for (j, kind) in rigs, (name, style) in zip(cargo_value_sweep.classes, class_styles)
        for (axis, measure) in zip(sweep_axes, sweep_measures(table, drive, kind, name))
            lines!(axis, values, measure; color=palette[j], linestyle=style)
            scatter!(axis, values, measure; color=palette[j], strokecolor=:white,
                strokewidth=pt(0.4))
        end
    end
    reference_line!.(sweep_axes[2:3])
    linkxaxes!(sweep_axes...)
    rig_entries = [MarkerElement(; color=palette[j], marker=:circle) for (j, _) in rigs]
    rate = assumptions.entries[:discount_rate]
    level_entries = [MarkerElement(; interest_marker(level, :black)...)
                     for level in keys(cargo_interest_factors())]
    class_entries = [LineElement(; color=:black, linestyle=style)
                     for style in class_styles]
    blank = MarkerElement(; color=:transparent, marker=:circle)
    Legend(figure[4, 1:2], [rig_entries, [level_entries; blank], [class_entries; blank]],
        [[rig_label(rig) for (_, rig) in rigs],
            [["$(round(Int, 100bound)) %" for bound in (rate.low, rate.high)]; " "],
            [collect(cargo_value_sweep.classes); " "]],
        ["rig", "discount rate (a)", "ship (b to d)"]; orientation=:horizontal,
        titleposition=:top, nbanks=3)
    space = maximum(tight_yticklabel_spacing!, sweep_axes)
    foreach(axis -> axis.yticklabelspace = space, sweep_axes)
    save_figure("cargo_interest", figure)
end

"""
    interest_marker(level, colour)

Marker attributes of a saving at cargo interest `level` (`:low` or `:high`) in `colour`.
"""
interest_marker(level, colour) = level == :high ?
    (; color=(colour, 0.45), marker=:circle, markersize=1.3marker_size) :
    (; color=:transparent, strokecolor=colour, strokewidth=pt(0.8), marker=:circle,
        markersize=1.3marker_size)

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
    slots = class.unit_capacity - 2rows * class.deck_tiers
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
    table = read_table(study_file(:tow_point, "tow_point.csv"))
    names = filter(name -> !isempty(rows(table, "class" => name, "tow" => "bow")),
        class_order(table))
    routes_seen = unique(table["route"])
    figure = Figure(size=(page_width, 300))
    panels = (("fuel", "(a) fuel saving"), ("cost", "(b) cost saving"))
    for (column, (measure, title)) in enumerate(panels)
        axis = Axis(figure[1, column]; title, xlabel="against the bow [% points]",
            yticks=(eachindex(names), names), yreversed=true,
            yticklabelsvisible=column == 1)
        reference_line!(axis; vertical=true)
        savings = [tow_point_savings(table, name, route, measure)
                   for name in names, route in routes_seen]
        markers = measure == "cost" ? tow_point_markers : tow_point_markers[1:3]
        for (i, name) in enumerate(names)
            container = ship_classes()[name].cargo_unit == :teu
            tows = [tow for (tow, _) in markers[2:end] if container || tow != "midship_bay"]
            for (j, tow) in enumerate(tows)
                values = [saving[tow] - saving["bow"] for saving in savings[i, :]]
                y = i + (j - (length(tows) + 1) / 2) * lane_offset
                rangebars!(axis, [y], [minimum(values)], [maximum(values)];
                    direction=:x, color=(category_colours[j], 0.6))
                scatter!(axis, [mean(values)], [y]; color=category_colours[j])
            end
        end
        print_tow_point(measure, names, savings, markers)
    end
    axislegend(content(figure[1, 2]),
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
    unit_count_axis(cell, rigs, row_limits)

Axis in `cell` with one column per rig of `rigs`, pairs of index in `rig_names` and name,
named upright in the rig's colour and just wide enough to keep the names apart, its rows
`row_limits` matching the axis beside it.
"""
function unit_count_axis(cell, rigs, row_limits)
    return Axis(cell; width=length(rigs) * (text_size + tick_gap),
        xlabel="number\nof units", xticks=(eachindex(rigs), last.(rigs)),
        xticksvisible=false, xticklabelrotation=π / 2,
        xticklabelcolor=palette[first.(rigs)],
        yticksvisible=false, yticklabelsvisible=false, yreversed=true,
        limits=((0.5, length(rigs) + 0.5), row_limits))
end

"""
    class_size_figure()

Best area of each rig for every ship class and drive, the geometric mean over the routes
as a marker and the range over the routes as a bar, with the largest kite searched as a
dashed line named in the legend, and beside each panel the median number of units of each
rig at its best size, each column named in the rig's colour.
"""
function class_size_figure()
    table = compared_table()
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
        vlines!(axis, kite_bound; color=palette[1], linestyle=:dash, linewidth=rule_width)
        rigs = study_rigs(table)
        counts = unit_count_axis(figure[1, 2 * column], rigs, row_limits)
        colgap!(figure.layout, 2 * column - 1, pt(4))
        for (slot, (j, kind)) in enumerate(rigs), (i, name) in enumerate(names)
            areas = filter(isfinite, [best_area(table, name, route, drive, kind)
                                      for route in routes_seen])
            isempty(areas) && continue
            y = i + rig_offset(slot, length(rigs), 0.22)
            rangebars!(axis, [y], [minimum(areas)], [maximum(areas)]; direction=:x,
                color=(palette[j], 0.6))
            scatter!(axis, [geometric_mean(areas)], [y]; color=palette[j])
            text!(counts, slot, i; text=string(median_units(table, name, drive, kind)),
                fontsize=note_size, align=(:center, :center), color=palette[j])
        end
    end
    Legend(figure[2, 1:4], [LineElement(color=palette[1], linestyle=:dash,
            linewidth=rule_width)], ["largest kite searched"]; orientation=:horizontal)
    save_figure("class_sizes", figure)
end

"""
    winner_map_figure()

The [`fleet_band`](@ref) of every ship class and route, deadweight-limited classes in the
top row and space-limited ones below, one column per drive, coloured by the rig that
leads, hatched in the colours of the two best where they are level and grey where no rig
clearly saves, and labelled with the best cost saving [%].
"""
function winner_map_figure()
    table = compared_table()
    groups = limit_groups(table)
    route_names_seen = route_order
    bands = Set{String}()
    figure = Figure(size=(page_width, 400))
    for (row, (limit, names)) in enumerate(groups), (column, (drive, title)) in
                                                     enumerate(drive_panels)
        axis = Axis(figure[row, column];
            title=row == 1 ? title : "",
            xticks=(eachindex(route_names_seen), route_label.(route_names_seen)),
            yticks=(eachindex(names), names), yreversed=true,
            limits=(0.5, length(route_names_seen) + 0.5, 0.5, length(names) + 0.5),
            yticklabelsvisible=column == 1, xticklabelsvisible=row == length(groups),
            xticksvisible=row == length(groups),
            xticklabelrotation=π / 4)
        column == 1 && Label(figure[row, 0], "$limit-limited"; rotation=π / 2,
            tellheight=false)
        cells = fleet_cells(table, drive)
        for (i, route) in enumerate(route_names_seen), (k, name) in enumerate(names)
            cell = only(filter(cell -> (cell.class, cell.route) == (name, route), cells))
            lead = rig_lead([cell])
            band = lead.verdict == "leads" ? lead.rig : lead.verdict
            push!(bands, band)
            best = cell.savings[lead.rig]
            shade = winner_shade(rig_colour(lead.rig), best)
            fill = band == "none" ? fleet_colours()["none"] :
                   band == "level" ? level_fill(lead.rig, lead.rival; background=shade) :
                   shade
            fill_rect!(axis, Rect2f(i - 0.5, k - 0.5, 1, 1), fill)
            text!(axis, i, k; text=typeset_minus(abs(best) < 1 ? @sprintf("%.1f", best) :
                                                 string(round(Int, best))),
                align=(:center, :center), fontsize=note_size)
        end
    end
    colgap!(figure.layout, 1, pt(4))
    for (row, (_, names)) in enumerate(groups)
        rowsize!(figure.layout, row, Auto(length(names)))
    end
    shown = [band for band in fleet_bands if band in bands]
    Legend(figure[0, 1:length(drive_panels)],
        [band_entry(band) for band in shown],
        [band == "none" ? "no rig" : rig_label(band) for band in shown];
        orientation=:horizontal, halign=:right, tellwidth=false, margin=(0, 0, 0, 0))
    rowgap!(figure.layout, 1, 0)
    save_figure("winner_map", figure)
end

"""
    winner_shade(colour, saving)

`colour` mixed with white for a cell of the winner map whose best rig saves `saving` [%]:
the paler, the smaller the saving, full at 40 %.
"""
winner_shade(colour, saving) = Makie.Colors.weighted_color_mean(
    0.55 + 0.45 * clamp(saving, 0, 40) / 40, RGBf(Makie.to_color(colour)), white)

"""
    fleet_share_panel!(axis, splits, measure, label)

Stacked bar per drive of the share [%] of `measure` (`:bill` or `:saved`) of each band of
`splits`, a Vector of drive name and [`fleet_split`](@ref), the first drive on top, each
band written with `label(share, billions)`.
"""
function fleet_share_panel!(axis, splits, measure, label)
    colours = fleet_colours()
    for (i, (_, split)) in enumerate(splits)
        total = fleet_total(split, measure)
        left = 0.0
        for band in fleet_bands
            share = 100getfield(split[band], measure) / total
            share > 0 || continue
            fill_rect!(axis, Rect2f(left, i - 0.35, share, 0.7), colours[band];
                strokecolor=:white, strokewidth=0.5)
            billions = 1e-9getfield(split[band], measure)
            text!(axis, left + share / 2, i; text=label(share, billions),
                align=(:center, :center), fontsize=note_size)
            left += share
        end
    end
    xlims!(axis, 0, 100)
    ylims!(axis, length(splits) + 0.5, 0.5)
end

"share [%] of its bar below which a band of the fleet share figure is too narrow to label"
least_labelled_share = 4

"label of a band of `share` [%] of the cost carried, empty where it does not fit"
cost_band_label(share, _) = share < least_labelled_share ? "" : percent_text(share)

"label of a band of `share` [%] and `billions` [USD a year] saved, short where narrow"
function saving_band_label(share, billions)
    share < least_labelled_share && return ""
    share < 15 && return percent_text(share)
    return string("USD ", estimate_text(billions), " bn, ", percent_text(share))
end

"`share` [%] in whole per cent, set as the paper sets it"
percent_text(share) = @sprintf("%.0f\u2009%%", share)

"""
    fleet_total_label(name, split, measure)

Label of the bar of drive `name` of a [`fleet_split`](@ref): the total of `measure` and, for
the saving, its share of the cost of carrying the cargo.
"""
function fleet_total_label(name, split, measure)
    total = fleet_total(split, measure)
    label = string(name, "\nUSD ", estimate_text(1e-9total), " bn")
    measure == :saved || return label
    share = percent_text(100total / fleet_total(split, :bill))
    return string(label, ",\n", share, " of (a)")
end

"colour of the rig `rig` of [`rig_names`](@ref)"
rig_colour(rig) = palette[findfirst(==(rig), rig_names)]

"""
    level_fill(rig, other; background=(rig_colour(rig), 0.55))

Fill of what two rigs share: `background`, by default the colour of `rig`, hatched by
[`hatch!`](@ref) with the colour of `other`.
"""
level_fill(rig, other; background=(rig_colour(rig), 0.55)) =
    (; background, stripe=rig_colour(other))

"""
    fill_rect!(axis, rect, fill; attributes...)

Fill the rectangle `rect` [data of `axis`] with the colour `fill`, or with the background of
a [`level_fill`](@ref) hatched with its stripe.
"""
fill_rect!(axis, rect, fill; attributes...) = poly!(axis, rect; color=fill, attributes...)

function fill_rect!(axis, rect, fill::NamedTuple; attributes...)
    poly!(axis, rect; color=fill.background, attributes...)
    hatch!(axis, rect, fill.stripe)
end

"legend entry of the colour or [`level_fill`](@ref) `fill`"
fill_entry(fill) = PolyElement(color=fill)
fill_entry(fill::NamedTuple) = hatched_entry(fill.background, fill.stripe)

"legend entry of the band `band` of [`fleet_bands`](@ref)"
band_entry(band) = fill_entry(fleet_colours()[band])

"colours of the [`fleet_bands`](@ref): those of the rigs, level hatched, none grey"
fleet_colours() = Dict((rig => rig_colour(rig) for rig in rig_names)...,
    "level" => level_fill("kite", "rotors"), "none" => RGBf(0.8, 0.8, 0.8))

"pitch [figure units] of the stripes of [`hatch!`](@ref)"
hatch_pitch = style_size("hatch_pitch")

"width [figure units] of the stripes of [`hatch!`](@ref)"
hatch_width = style_size("hatch_width")

"""
    hatch!(axis, rect, stripe)

Stripes of `stripe` rising at 45° across the rectangle `rect` [data of `axis`], on one grid
for the whole axis, drawn as polygons.
"""
function hatch!(axis, rect, stripe)
    stripes = lift(axis.scene.viewport, axis.finallimits) do viewport, limits
        hatch_polygons(rect, viewport, limits, axis.yreversed[])
    end
    poly!(axis, stripes; color=stripe, strokewidth=0)
end

"""
    hatch_polygons(rect, viewport, limits, reversed)

The stripes of [`hatch!`](@ref) across `rect` [data] as polygons [data], for an axis of
`viewport` and `limits`, its y axis `reversed` or not.
"""
function hatch_polygons(rect, viewport, limits, reversed)
    scale = widths(viewport) ./ widths(limits) .* (1, reversed ? -1 : 1)
    corners = minimum(rect) .* scale, maximum(rect) .* scale
    box = Rect2f(min.(corners...), abs.(corners[2] .- corners[1]))
    low, high = minimum(box), maximum(box)
    offsets = hatch_pitch * (floor((low[1] - high[2]) / hatch_pitch):
                             ceil((high[1] - low[2]) / hatch_pitch))
    band = hatch_width * sqrt(2)
    polygons = [clip_polygon(Point2f[(low[1], low[1] - offset),
                    (high[1], high[1] - offset), (high[1], high[1] - offset - band),
                    (low[1], low[1] - offset - band)], box) for offset in offsets]
    return [[Point2f(point ./ scale) for point in polygon] for polygon in polygons
            if length(polygon) >= 3]
end

"""
    clip_polygon(points, box)

The convex polygon `points` cut to the rectangle `box`, by the Sutherland-Hodgman method.
"""
function clip_polygon(points, box)
    for (index, bound, below) in ((1, minimum(box)[1], false), (1, maximum(box)[1], true),
        (2, minimum(box)[2], false), (2, maximum(box)[2], true))
        isempty(points) && break
        inside = [below ? point[index] <= bound : point[index] >= bound
                  for point in points]
        kept = Point2f[]
        for k in eachindex(points)
            previous = mod1(k - 1, length(points))
            if inside[k] != inside[previous]
                t = (bound - points[previous][index]) /
                    (points[k][index] - points[previous][index])
                push!(kept, points[previous] + t * (points[k] - points[previous]))
            end
            inside[k] && push!(kept, points[k])
        end
        points = kept
    end
    return points
end

"legend entry of a fill of `background` hatched by [`hatch!`](@ref) with `stripe`"
hatched_entry(background, stripe) = [PolyElement(color=background);
    [LineElement(color=stripe, linewidth=hatch_width * print_scale,
         linepoints=Point2f[(max(0, offset), max(0, -offset)),
             (min(1, 1 + offset), min(1, 1 - offset))])
     for offset in (-0.6, -0.2, 0.2, 0.6)]]

"""
    fleet_share_figure()

The yearly cost of carrying the fleet's cargo split by the rig that lowers it most (a),
and the yearly cost the rigs save there split by rig (b), a bar per drive with its total.
"""
function fleet_share_figure()
    table = compared_table()
    splits = [(drive, fleet_split_of(table, drive)) for (drive, _) in drive_labels]
    figure = Figure(size=(page_width, 250))
    classes = length(first(fleet_work()))
    panels = ((:bill, cost_band_label, "(a) How much of shipping each rig suits: the \
               yearly cost of carrying the cargo of the $classes classes, by the rig that \
               lowers it most"),
        (:saved, saving_band_label, "(b) How much each rig saves there: the part of \
                 the cost in (a) that the rigs take out, by rig"))
    for (k, (measure, label, title)) in enumerate(panels)
        ticks = [fleet_total_label(name, split, measure) for ((_, name), (_, split)) in
                 zip(drive_labels, splits)]
        axis = Axis(figure[k, 1]; title, yticks=(eachindex(splits), ticks),
            xticks=0:25:100, xticklabelsvisible=k == length(panels),
            xlabel=k == length(panels) ? "share of each bar [%]" : "", ytickalign=0,
            yticksize=0)
        fleet_share_panel!(axis, splits, measure, label)
    end
    shown = [band for band in fleet_bands
             if any(getfield(split[band], measure) > 0
                    for (_, split) in splits, (measure, _, _) in panels)]
    names = Dict((rig => rig_label(rig) for rig in rig_names)...,
        "level" => "two rigs level within the error",
        "none" => "no rig saves beyond the error")
    Legend(figure[3, 1], [band_entry(band) for band in shown],
        [names[band] for band in shown]; orientation=:horizontal)
    rowgap!(figure.layout, 2, pt(3))
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
    rigs = study_rigs(routes_table)
    names = [name for name in route_order if haskey(savings, name) &&
                 all(!isempty(savings[name][rig]) for (_, rig) in rigs)]
    isempty(names) && error("no route of the 140 m e-ammonia ship has departures of " *
                            "every rig")
    figure = Figure(size=(column_width, 190))
    axis = Axis(figure[1, 1]; ylabel="cost saving [%]",
        title=join(route_label.(names), ", "), limits=((0.4, 12.6), nothing),
        xticks=(1:12, ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]))
    reference_line!(axis)
    for (slot, (j, rig)) in enumerate(rigs)
        route_means = [[mean(get(savings[name][rig], month, [NaN])) for name in names]
                       for month in 1:12]
        shown = findall(means -> all(isfinite, means), route_means)
        x = shown .+ rig_offset(slot, length(rigs), 0.22)
        rangebars!(axis, x, minimum.(route_means[shown]), maximum.(route_means[shown]);
            color=(palette[j], 0.6), whiskerwidth=pt(3))
        lines!(axis, (1:12) .+ rig_offset(slot, length(rigs), 0.22), mean.(route_means);
            color=(palette[j], 0.6), linewidth=pt(0.8))
        scatter!(axis, x, mean.(route_means[shown]); color=palette[j])
    end
    Legend(figure[2, 1], [MarkerElement(color=palette[j], marker=:circle) for (j, _) in rigs],
        [rig_label(rig) for (_, rig) in rigs];
        orientation=:horizontal)
    rowgap!(figure.layout, 1, pt(4))
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
    spread_labels(positions, gap, low, high)

`positions` moved apart where needed so that neighbours stand at least `gap` apart, in the
same order, each group centred where it was and then pushed within `low` to `high`.
"""
function spread_labels(positions, gap, low, high)
    order = sortperm(positions)
    placed = positions[order]
    for _ in eachindex(placed), i in 2:length(placed)
        overlap = gap - (placed[i] - placed[i - 1])
        overlap > 0 || continue
        placed[i - 1] -= overlap / 2
        placed[i] += overlap / 2
    end
    count = length(placed)
    placed .= min.(placed, high .- (count .- (1:count)) .* gap)
    placed .= max.(placed, low .+ (0:(count - 1)) .* gap)
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
    axis = Axis(figure[1, 1]; xlabel="ship length [m]",
        xticks=(lengths, string.(round.(Int, lengths))), ylabel="cost premium closed [%]")
    shares = [[premium_closed(designs, "ammonia", length, column_name)
               for length in lengths] for (_, column_name) in rig_area_columns]
    for (k, (_, column_name)) in enumerate(rig_area_columns)
        valid = isfinite.(shares[k])
        bounds = [extrema(premium_closed(table, "ammonia", length, column_name)
                          for table in corners) for length in lengths[valid]]
        x = [length + 2.5(count(isfinite(share[i]) for share in shares[1:k]) -
                          (count(isfinite(share[i]) for share in shares) + 1) / 2)
             for (i, length) in enumerate(lengths) if valid[i]]
        rangebars!(axis, x, first.(bounds), last.(bounds);
            color=(palette[k], 0.6), whiskerwidth=pt(3))
        scatter!(axis, x, shares[k][valid]; color=palette[k])
    end
    whisker = Point2f[(0.5, 0), (0.5, 1)]
    axislegend(axis, [[LineElement(; color=(palette[k], 0.6), linewidth=line_width,
                           linepoints=whisker),
                       MarkerElement(; color=palette[k], marker=:circle)]
                      for k in eachindex(rig_area_columns)],
        collect(rig_label.(first.(rig_area_columns))); position=:lt)
    xlims!(axis, first(lengths) - 8, last(lengths) + 8)
    ylims!(axis, 0, nothing)
    save_figure("premium", figure)
end

"factor on the base value of the input `name` at its `bound`, `:low` or `:high`"
input_factor(name, bound) =
    getfield(assumptions.entries[name], bound) / assumptions.entries[name].value

"the input of the price of the fuel of each drive of designs.csv"
fuel_price_inputs = Dict("vlsfo" => :vlsfo_price, "ammonia" => :e_ammonia_price)

"""
    fuel_factor(drive, bounds)

Factor on the fuel price of `drive` at its bound in `bounds`, a Dict of drive to `:low` or
`:high`; one for a drive not in it.
"""
fuel_factor(drive, bounds) =
    haskey(bounds, drive) ? input_factor(fuel_price_inputs[drive], bounds[drive]) : 1.0

"""
    fuel_repriced(designs, bounds)

`designs` with the cost of each row of a drive in `bounds`, a Dict of drive to `:low` or
`:high`, at that bound of the price of its fuel.
"""
function fuel_repriced(designs, bounds)
    repriced = copy(designs)
    factors = fuel_factor.(designs["drive"], Ref(bounds))
    repriced["cost"] = designs["cost"] .+ designs["fuel_cost"] .* (factors .- 1)
    return repriced
end

"""
    breakdown_factors(drive, bound)

Factors on the parts of the [`breakdown_figure`](@ref) with the fuel price of `drive` and
the cargo interest at `bound`, `:low` or `:high`.
"""
breakdown_factors(drive, bound) =
    [input_factor(fuel_price_inputs[drive], bound), 1, 1, 1, 1,
        input_factor(:cargo_value, bound) * input_factor(:discount_rate, bound)]

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
        style_colour("accent")]
    cases = Tuple{String, String, Union{Nothing, String}}[("VLSFO", "vlsfo", nothing),
        ("e-ammonia", "ammonia", nothing)]
    for (rig, column) in rig_area_columns
        push!(cases, ("e-ammonia + $(rig_label(rig))", "ammonia", column))
    end
    labels = first.(cases)
    figure = Figure(size=(page_width, 175))
    for (panel, ship_length) in enumerate((85.0, 200.0))
        found = [cheapest_design(designs, drive, ship_length, column)
                 for (_, drive, column) in cases]
        values = [isnothing(k) ? 0.0 : 1e3 * designs[part][k] for k in found, part in parts]
        axis = Axis(figure[1, panel]; title="($(Char('a' + panel - 1))) $(round(Int,
                ship_length)) m ship", yticks=(eachindex(labels), labels), yreversed=true,
            xlabel="cost [USD per 1000 tkm]", yticklabelsvisible=panel == 1)
        positions = repeat(eachindex(labels), outer=length(parts))
        stack = repeat(eachindex(parts), inner=length(labels))
        barplot!(axis, positions, vec(values); stack, direction=:x, color=colours[stack],
            width=0.56)
        totals = vec(sum(values; dims=2))
        bounds = [[sum(values[i, :] .* breakdown_factors(drive, bound))
                   for bound in (:low, :high)] for (i, (_, drive, _)) in enumerate(cases)]
        rangebars!(axis, eachindex(labels) .+ 0.39, first.(bounds), last.(bounds);
            direction=:x, color=:black, linewidth=pt(0.6), whiskerwidth=pt(2.5))
        for (i, (k, case)) in enumerate(zip(found, cases))
            (isnothing(k) || isnothing(case[3])) && continue
            text!(axis, totals[i], i;
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
    table = compared_table()
    groups = limit_groups(table)
    rigs = study_rigs(table)
    figure = Figure(size=(page_width, 235))
    largest = maximum(length.(last.(groups)))
    cells = [figure[1, 1], GridLayout(figure[1, 2])]
    axes = map(enumerate(groups)) do (column, (limit, names))
        axis = Axis(column == 1 ? cells[1] : cells[2][1, 1];
            title="($(Char('a' + column - 1))) $limit-limited", xlabel="cost saving [%]",
            yticks=(eachindex(names), names), yreversed=true,
            limits=(nothing, (0.45, length(names) + 0.55)))
        for (slot, (j, rig)) in enumerate(rigs), (i, name) in enumerate(names)
            gross, net = gross_and_net_saving(table, name, "ammonia", rig)
            y = i + rig_offset(slot, length(rigs), 0.26)
            barplot!(axis, [y], [net]; direction=:x, color=palette[j],
                width=rig_bar_width(0.26, length(rigs)))
            barplot!(axis, [y], [gross]; direction=:x, fillto=net, color=(palette[j], 0.3),
                width=rig_bar_width(0.26, length(rigs)))
        end
        reference_line!(axis; vertical=true)
        xlims!(axis, 0, nothing)
        return axis
    end
    linkxaxes!(axes...)
    Legend(cells[2][2, 1],
        [[PolyElement(color=palette[j]) for (j, _) in rigs],
         [PolyElement(color=(palette[j], 0.3)) for (j, _) in rigs]],
        fill([rig_label(rig) for (_, rig) in rigs], 2), ["saving", "lost to cargo"];
        orientation=:horizontal, nbanks=3, titleposition=:top, tellheight=false,
        halign=:right, valign=:bottom, margin=(0, 0, 0, 0))
    Makie.update_state_before_display!(figure)
    axes[2].height = length(last(groups[2])) / largest * height(axes[1].scene.viewport[])
    save_figure("cargo_cost", figure)
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
    marks = ((flown, "flown"), (first(designed), "designed"))
    rotors_in_service = 5
    foot, gap, cut_size = length(names) + 0.5, pt(3), pt(5)
    rows = (-1.2, length(names) + 0.7)
    figure = Figure(size=(page_width, 225))
    areas = Axis(figure[1, 1]; title="(a) best kite area",
        doubling_axis(:x, 125, bound)..., xlabel=square_metres("projected area [", "]"),
        yticks=(eachindex(names), names), yreversed=true,
        limits=((100, 1.4bound), rows))
    units = Axis(figure[1, 2]; title="(b) deck units at the best size", xlabel="units",
        yticks=(eachindex(names), names), yreversed=true, yticklabelsvisible=false,
        limits=((0, nothing), rows))
    vspan!(areas, designed...; color=(:gray50, 0.25))
    reference_line!(areas, flown; vertical=true)
    reference_line!(areas, bound; vertical=true, linestyle=:dash)
    for (area, label) in marks
        text!(areas, area, first(rows); text=label, align=(:right, :top),
            offset=(-gap, -gap), fontsize=note_size, color=:gray35)
    end
    text!(areas, bound, first(rows); text="upper bound of the search", rotation=π / 2,
        align=(:right, :bottom), offset=(-gap, -gap), fontsize=note_size, color=:gray35)
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
                strokewidth=outline_width)
            maximum(values) >= bound && scatter!(areas, [bound], [y];
                marker=:rtriangle, color=(palette[1], k == 2 ? 0.8 : 0.35),
                markersize=cut_size, marker_offset=(-cut_size / 2, 0))
        end
    end
    reference_line!(units, rotors_in_service; vertical=true)
    text!(units, rotors_in_service, foot; text="most rotors in service",
        rotation=π / 2, align=(:left, :bottom), offset=(-gap, 0), fontsize=note_size,
        color=:gray35)
    deck_rigs = filter(in(table["rig"]), deck_rig_names)
    for (i, name) in enumerate(names), (j, rig) in enumerate(deck_rigs)
        scatter!(units, [median_units(table, name, "ammonia", rig)],
            [i + (j - (length(deck_rigs) + 1) / 2) * 0.25]; color=rig_colour(rig),
            strokecolor=:white, strokewidth=rule_width)
    end
    xlims!(units, 0, nothing)
    axislegend(areas, [MarkerElement(marker=:circle, color=:white,
            strokecolor=palette[1], strokewidth=outline_width),
        MarkerElement(marker=:circle, color=palette[1])], ["VLSFO", "e-ammonia"];
        position=(0.75, 1))
    axislegend(units, [MarkerElement(marker=:circle, color=rig_colour(rig))
                       for rig in deck_rigs],
        collect(rig_label.(deck_rigs)); position=:rt, orientation=:horizontal)
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
cost of a dual-fuel e-ammonia engine, and the rig, with the range of each part over the
bounds of the inputs one at a time; the fuel tank, sized by the route, is left out.
"""
function capital_figure()
    areas = Dict("kite" => 1600.0, "wings" => 800.0, "rotors" => 400.0,
        "suction" => 400.0, "vtol" => 100.0)
    cases = [("VLSFO", :vlsfo, (;)); ("e-ammonia", :ammonia, (;));
        [("+ $(rig_label(rig)) $(round(Int, areas[rig])) ", :ammonia,
          rig_size(rig, areas[rig])) for rig in rig_names]]
    labels = Any[]
    values = Matrix{Float64}(undef, 0, 3)
    lows, highs = similar(values), similar(values)
    for length in (85.0, 170.0), (label, drive, rig) in cases
        ships = [Ship(design, assumptions) for design in (ShipDesign(:vlsfo, length),
            ShipDesign(:ammonia, length), ShipDesign(drive, length; rig...))]
        spread = reduce(hcat, [capital_parts(ships, drive, inputs)
                               for inputs in one_at_a_time(assumptions,
            collect(keys(assumptions.entries)))])
        suffix = ", $(round(Int, length)) m"
        push!(labels, isempty(rig) ? label * suffix : square_metres(label, suffix))
        values = vcat(values, capital_parts(ships, drive, assumptions)')
        lows = vcat(lows, minimum(spread; dims=2)')
        highs = vcat(highs, maximum(spread; dims=2)')
    end
    figure = Figure(size=(column_width, 380))
    axis = Axis(figure[1, 1]; yticks=(eachindex(labels), labels), yreversed=true,
        xlabel="capital [million USD]", limits=((0, nothing), nothing))
    positions = repeat(eachindex(labels), outer=3)
    stack = repeat(1:3, inner=length(labels))
    rig_colours = repeat([:gray; :gray; palette[eachindex(rig_names)]], 2)
    engine_colour = category_colours[2]
    colours = [[:gray55 for _ in labels]; [engine_colour for _ in labels]; rig_colours]
    barplot!(axis, positions, vec(values); stack, direction=:x, color=colours, width=0.4)
    for (lane, part) in ((-0.31, 1), (0.28, 2), (0.4, 3))
        shown = values[:, part] .> 0
        start = part == 1 ? zeros(length(labels)) : sum(values[:, 1:(part - 1)]; dims=2)
        rangebars!(axis, findall(shown) .+ lane, start[shown] .+ lows[shown, part],
            start[shown] .+ highs[shown, part]; direction=:x, color=:black,
            linewidth=goal_width, whiskerwidth=whisker_width)
    end
    names = ["hull and basic drive"; "e-ammonia engine"; rig_label.(collect(rig_names))]
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
    swept_savings(cost, input)

[`swept_values`](@ref) of `input` and the cost saving [%] of each rig of `rig_names` at
each, one row per rig, from `cost(value, rig)`, the cost of a case or Inf where
it has none; NaN where a rig or the ship without one has no cost.
"""
function swept_savings(cost, input)
    values = swept_values(input)
    savings = fill(NaN, length(rig_names), length(values))
    for (j, value) in enumerate(values), (i, rig) in enumerate(rig_names)
        bare, rigged = cost(value, "none"), cost(value, rig)
        isfinite(bare) && isfinite(rigged) && (savings[i, j] = percent_saving(rigged, bare))
    end
    return values, savings
end

"""
    situation_savings(table, ship, route, drive, input)

[`swept_savings`](@ref) of the best size of each rig in situations.csv.
"""
situation_savings(table, ship, route, drive, input) = swept_savings(input) do value, rig
    situation_cost(table, ship, route, drive, input, value, rig)
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

"""
legend entries of the best size of each rig of `rigs`, pairs of index in `rig_names` and
name: a line, with a marker where `markers`
"""
rig_entries(markers, rigs) = [markers ? [LineElement(; color),
                                  MarkerElement(; color, marker=:circle)] :
                              LineElement(; color) for color in palette[first.(rigs)]]

"""
    doubling_ticks(low, high; base=125)

Ticks of a log axis from `low` to `high` at each doubling of `base`, as values and labels,
every other one labelled where there are more than seven.
"""
function doubling_ticks(low, high; base=125)
    powers = floor(Int, log2(low / base) + 1e-9):ceil(Int, log2(high / base) - 1e-9)
    values = [base * 2.0^power for power in powers]
    step = length(values) > 7 ? 2 : 1
    labels = [(i - 1) % step == 0 ? @sprintf("%.15g", value) : ""
              for (i, value) in enumerate(values)]
    return values, labels
end

"""
    doubling_axis(side, low, high; base=125)

Keyword arguments of an `Axis` that draw its `side` (`:x` or `:y`) on a log scale from `low`
to `high`, with the [`doubling_ticks`](@ref) of `base` and a minor tick between each two.
"""
doubling_axis(side, low, high; base=125) = NamedTuple{(Symbol(side, :scale),
    Symbol(side, :ticks), Symbol(side, :minorticks), Symbol(side, :minorticksvisible))}((
    log10, doubling_ticks(low, high; base), IntervalsBetween(2), true))

"""
Panels of the situation figure as (title, x label, inputs with their drive, scale of the
x axis, factor from value to axis, x ticks); the fuel panel joins VLSFO and e-ammonia
prices.
"""
situation_panels = [
    ("fuel price", "fuel price [USD/GJ]",
        [(:vlsfo_price, :vlsfo), (:e_ammonia_price, :ammonia)], log10, 1.0,
        doubling_ticks(7.5, 120; base=7.5)),
    ("cargo value", "cargo value [1000 USD/t]", [(:cargo_value, :ammonia)], log10, 1e-3,
        doubling_ticks(1.25, 20; base=1.25)),
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
            xminorticks=IntervalsBetween(2), xminorticksvisible=scale == log10,
            ylabel=(k - 1) % 4 == 0 ? "cost saving [%]" : "",
            yticklabelsvisible=(k - 1) % 4 == 0)
        reference_line!(axis)
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
            for rig in eachindex(rig_names)
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
    rigs = study_rigs(table)
    Legend(figure[2, 3:4],
        [rig_entries(true, rigs); ships; LineElement(color=:gray50, linewidth=rule_width)],
        ["best " .* rig_label.(last.(rigs));
            ["140 m, Guadeloupe", "Kamsarmax, Tubarão", "base input"]];
        tellheight=false, tellwidth=false,
        halign=:left, valign=:bottom)
    save_figure("situations", figure)
end

"label and line style of each drive of `fuel_drives` in the fuel figure"
fuel_styles = Dict(:ammonia => ("e-ammonia", :solid),
    :methanol => ("e-methanol", (:dash, :loose)))

"keyword arguments of the fuel price axes of [`fuel_figure`](@ref), log [USD/GJ]"
fuel_price_axis = doubling_axis(:x, 15, 120; base=15)

"""
    fuel_savings(table, class, route, drive, input)

[`swept_savings`](@ref) of each rig of fuels.csv on `class`, `route` and `drive`.
"""
fuel_savings(table, class, route, drive, input) = swept_savings(input) do value, rig
    chosen = cheapest_row(table, "class" => class, "route" => string(route),
        "drive" => string(drive), "value" => value, "rig" => rig)
    isnothing(chosen) ? Inf : table["cost"][chosen]
end

"""
    fuel_figure()

Cost saving of each rig over the fuel price on each ship of the fuel study, on e-ammonia
and on e-methanol, with each fuel's price range and base value in a strip below. Prints
where the lead changes.
"""
function fuel_figure()
    table = read_table(data_file("fuels.csv"))
    figure = Figure(size=(page_width, 250))
    axes = map(enumerate(fuel_ships)) do (k, (class, route))
        axis = Axis(figure[1, k]; title="($('a' + k - 1)) $class\nto $(route_label(route))",
            fuel_price_axis..., ylabel=k == 1 ? "cost saving [%]" : "")
        for (input, drive) in fuel_drives
            label, linestyle = fuel_styles[drive]
            values, savings = fuel_savings(table, class, route, drive, input)
            print_leaders("$class, $label", input, log10.(values), savings, exp10)
            for rig in eachindex(rig_names)
                scatterlines!(axis, values, savings[rig, :]; color=palette[rig], linestyle,
                    markersize=0.8marker_size)
            end
        end
        prices = Axis(figure[2, k]; fuel_price_axis..., xlabel="fuel price [USD/GJ]",
            height=pt(14),
            limits=(nothing, (0.4, length(fuel_drives) + 0.6)), yticksvisible=false,
            yticklabelsvisible=false, bottomspinevisible=true, topspinevisible=false,
            leftspinevisible=false, rightspinevisible=false)
        for (j, (input, drive)) in enumerate(fuel_drives)
            linestyle = last(fuel_styles[drive])
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
    rigs = study_rigs(table)
    axislegend(axes[2], rig_entries(false, rigs), rig_label.(last.(rigs));
        position=:lt, orientation=:horizontal)
    styles = [fuel_styles[drive] for (_, drive) in fuel_drives]
    axislegend(axes[1], [LineElement(; color=:black, linestyle) for (_, linestyle) in styles],
        first.(styles); position=:rb)
    save_figure("fuels", figure)
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
    rigs = [(rig, round(Int, area)) for (rig, area) in reference_rigs if rig in table["rig"]]
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
        ylabel="thrust [kN]", yautolimitmargin=(0, 0.05),
        xticks=(eachindex(angle_bands), ["$(round(Int, low))–$(round(Int, high))°\n$name"
                                         for (name, low, high) in angle_bands]))
    for (slot, (rig, _)) in enumerate(rigs)
        thrust = band_totals(table, rig, "thrust_hours") ./ band_totals(table, rig, "hours")
        barplot!(thrust_axis, eachindex(angle_bands) .+ rig_offset(slot, length(rigs), 0.27),
            thrust; width=rig_bar_width(0.27, length(rigs)), color=rig_colour(rig))
    end
    work_axis = Axis(figure[2, 1]; title="(c) share of each rig’s work by band",
        ylabel="share of work [%]", xticks=ticks, xticklabelrotation=π / 6)
    cost_axis = Axis(figure[2, 2]; title="(d) mean thrust per rig cost",
        ylabel="thrust per cost\n[kN per 1000 USD/day]", xticks=ticks,
        xticklabelrotation=π / 6, yautolimitmargin=(0, 0.05))
    for (i, name) in enumerate(names)
        cost(rig) = first(table["rig_cost"][rows(table, "rig" => rig, "route" => name)])
        for (slot, (rig, _)) in enumerate(rigs)
            work = band_totals(table, rig, "work"; route=name)
            stacked_bar!(work_axis, i + rig_offset(slot, length(rigs), lane_offset),
                100 .* work ./ sum(work), rig_bar_width(lane_offset, length(rigs)),
                rig_colour(rig))
            chosen = rows(table, "rig" => rig, "route" => name)
            thrust = sum(table["thrust_hours"][chosen]) / sum(table["hours"][chosen])
            barplot!(cost_axis, [i + rig_offset(slot, length(rigs), 0.27)],
                [thrust / (24e-3 * cost(rig))];
                width=rig_bar_width(0.27, length(rigs)), color=rig_colour(rig))
        end
    end
    hidexdecorations!(time_axis; ticks=false, ticklabels=false)
    Legend(figure[3, 1:2], [PolyElement(color=rig_colour(rig)) for (rig, _) in rigs],
        [square_metres("$(rig_label(rig)) $area ") for (rig, area) in rigs];
        orientation=:horizontal)
    Legend(figure[4, 1:2], [PolyElement(color=(:gray25, alpha)) for alpha in band_alphas],
        ["$name $(round(Int, low))–$(round(Int, high))°"
         for (name, low, high) in angle_bands],
        "true wind angle, darkest upwind in each colour";
        orientation=:horizontal, titleposition=:left)
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
        reference_line!(axis)
        for (k, rig) in enumerate(rig_names)
            chosen = rows(table, "ship" => name, "drive" => drive, "rig" => rig)
            chosen = chosen[sortperm(table["area"][chosen])]
            saved = 100 .* (1 .- table["fuel"][chosen] ./ table["fuel"][bare])
            change = 100 .* (table["cost"][chosen] ./ table["cost"][bare] .- 1)
            areas = table["area"][chosen]
            lines!(axis, saved, change; color=(palette[k], 0.6), linewidth=0.9)
            scatter!(axis, saved, change; color=palette[k], marker=rig_markers[k],
                markersize=area_marker_size.(areas), strokecolor=:white,
                strokewidth=pt(0.25))
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
    clear_axislegend(figure, panels,
        [[LineElement(color=(palette[k], 0.6), linewidth=0.9),
          MarkerElement(color=palette[k], marker=rig_markers[k])]
         for k in eachindex(rig_names)],
        collect(rig_label.(rig_names)))
    key_areas = (200, 800, 3200, 12800)
    clear_axislegend(figure, panels[:, [2, 1]],
        [MarkerElement(color=:gray40, marker=:circle, markersize=area_marker_size(area))
         for area in key_areas], ["$area" for area in key_areas], L"\mathrm{m^2}";
        orientation=:horizontal, titleposition=:left)
    save_figure("abatement", figure)
end

"markers of the rigs, in the order of `rig_names`, told apart by shape"
rig_markers = (:circle, :rect, :utriangle, :diamond, :dtriangle, :hexagon)

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
rig_label(rig) = get(rig_short_names, rig, rig)

"""
    development_panel!(axis, table, bias, ships, levers, rig, column)

Bars in `axis` of the change of the saving of `rig` in `column` between the low and high
bound of each of `levers`, one per ship in the colours of `category_colours`, with the
high bound marked, a one-sided whisker at a recosted bound for what routing anew would
gain by the recosting bias table `bias` ([`recosting_error`](@ref)), and a tick in the
ship's colour where neither bound moves it.
"""
function development_panel!(axis, table, bias, ships, levers, rig, column)
    reference_line!(axis; vertical=true)
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
        for (change, bound) in ((low, :low), (high, :high))
            gain = recosting_error(bias, string(entry.input),
                bound_change(entry.input, bound), rig; column)
            abs(gain) > 0.005 || continue
            errorbars!(axis, [change], [y], [max(-gain, 0.0)], [max(gain, 0.0)];
                direction=:x, color=:black, whiskerwidth=pt(3), linewidth=rule_width)
        end
    end
end

"height [figure units] of the row of one input in the sensitivity figure"
input_row_height = pt(12)

"""
    sensitivity_figure()

Where development pays: for each rig of the study the inputs of
[`development_inputs`](@ref) it varied for that rig, largest effect on top, with the change
of its saving of cost per tonne-km (left) and of CO2 per tonne-km (right) between the
bounds of each input on each ship of the study, on one scale per column, and at a recosted
bound the one-sided gain of routing anew.
"""
function sensitivity_figure()
    table = read_table(data_file("sensitivity.csv"))
    bias = read_table(data_file("recosting_bias.csv"))
    ships = unique(table["ship"])
    rigs = last.(study_rigs(table))
    panels = [filter(entry -> rig in lever_rigs(entry) &&
                                  any(ship -> all(isfinite, bound_changes(table, ship, rig,
                                          string(entry.input))), ships),
                  development_inputs)
              for rig in rigs]
    for (levers, rig) in zip(panels, rigs)
        sort!(levers; by=entry -> maximum(ship -> abs(-(bound_changes(table, ship, rig,
            string(entry.input))...)), ships))
    end
    figure = Figure(size=(page_width, page_width))
    columns = [("cost", "change of cost saving [points]", 2),
        ("carbon", rich("change of CO", subscript("2"), " saving [points]"), 5)]
    for (column, (name, label, step)) in enumerate(columns)
        changes = [change for (levers, rig) in zip(panels, rigs) for entry in levers
                   for ship in ships
                   for change in bound_changes(table, ship, rig, string(entry.input);
                       column=name) if isfinite(change)]
        low, high = min(minimum(changes), 0), max(maximum(changes), 0)
        margin = 0.06 * (high - low)
        for (row, (rig, levers)) in enumerate(zip(rigs, panels))
            letter = 'a' + 2 * (row - 1) + column - 1
            title = column == 1 ?
                    rich("($letter) $(rig_label(rig)), cost",
                subscript("2"; color=:transparent)) :
                    rich("($letter) $(rig_label(rig)), CO", subscript("2"))
            axis = Axis(figure[row, column]; title,
                yticks=(eachindex(levers), [entry.label for entry in levers]),
                yticksvisible=column == 1, yticklabelsvisible=column == 1,
                xlabel=row == length(rigs) ? label : "",
                xticks=step * (ceil(low / step):floor(high / step)),
                limits=((low - margin, high + margin), (0.4, length(levers) + 0.6)))
            development_panel!(axis, table, bias, ships, levers, rig, name)
            rowsize!(figure.layout, row, Fixed(length(levers) * input_row_height))
        end
    end
    Legend(figure[length(rigs) + 1, 1:2],
        [[PolyElement(color=category_colours[j]) for j in eachindex(ships)];
            [MarkerElement(marker=:vline, color=:black, markersize=pt(7)),
                LineElement(color=:black, linewidth=rule_width)]],
        [short_ship.(ships); "high end of range"; "gain of routing anew"];
        orientation=:horizontal)
    resize_to_layout!(figure)
    save_figure("sensitivity", figure)
end

"plans of the forecast figure's saving panel, as (plan of forecast_result.csv, label)"
forecast_figure_plans = (("false", "perfect foresight"),
    ("live", "re-planned on the forecasts"))

"the `k`th of `n` strips, from the left, of the unit square of a legend patch"
rig_patch(k, n) = Point2f[((k - 1) / n, 0), (k / n, 0), (k / n, 1), ((k - 1) / n, 1)]

"""
    forecast_figure()

(a) Mean cost saving over the departures, with its standard error, of each rig on a 140 m
e-ammonia ship per plan of [`forecast_figure_plans`](@ref), a plan with no feasible round
trip marked "none" in place of its bar; (b, c) root mean square error along the route
against lead time of the archived forecasts' wind and wave height, of their blend with the
climatology and of the climatology; (d) the forecast's mean weight in the blend.
"""
function forecast_figure()
    table = read_table(data_file("forecast_result.csv"))
    rigs = study_rigs(table)
    figure = Figure(size=(page_width, 300))
    axis = Axis(figure[1, 1]; xticks=(eachindex(rigs), rig_label.(last.(rigs))),
        ylabel="cost saving [%]", title="(a) saving")
    plan_alphas = (1.0, 0.6, 0.3)[eachindex(forecast_figure_plans)]
    tops = Float64[]
    for (j, (plan, _)) in enumerate(forecast_figure_plans)
        savings = [forecast_saving(table, rig, plan) for (_, rig) in rigs]
        spreads = [100std(ratios) / sqrt(length(ratios))
                   for ratios in forecast_ratios.(Ref(table), last.(rigs), plan)]
        positions = eachindex(rigs) .+
                    (j - (length(forecast_figure_plans) + 1) / 2) * 0.27
        routed = isfinite.(savings)
        means, errors = savings[routed], spreads[routed]
        barplot!(axis, positions[routed], means; width=0.25,
            color=[(palette[k], plan_alphas[j]) for (k, _) in rigs[routed]])
        errorbars!(axis, positions[routed], means, errors; color=:black,
            whiskerwidth=pt(3), linewidth=rule_width)
        append!(tops, means .+ errors)
        unrouted = count(.!routed)
        text!(axis, positions[.!routed], zeros(unrouted); text=fill("none", unrouted),
            rotation=pi / 2, align=(:left, :center), fontsize=note_size, color=:gray30)
    end
    ylims!(axis, 0, 1.7 * maximum(tops))
    axislegend(axis, [[PolyElement(color=(palette[k], alpha),
                           points=rig_patch(slot, length(rigs)))
                       for (slot, (k, _)) in enumerate(rigs)] for alpha in plan_alphas],
        collect(last.(forecast_figure_plans)); position=:lt)
    errors = read_table(data_file("forecast_error.csv"))
    days = errors["lead_days"]
    for (column, (quantity, unit, place)) in enumerate((("wind", "m/s", (1, 2)),
        ("height", "m", (2, 1))))
        panel = Axis(figure[place...]; xlabel="lead time [days]",
            ylabel="rms error [$unit]",
            title=column == 1 ? "(b) wind at 10 m" : "(c) wave height")
        drawn = [lines!(panel, days, errors["$(quantity)_$name"]; style...)
                 for (name, style) in forecast_error_lines]
        ylims!(panel, 0, 1.25 * maximum(maximum(errors["$(quantity)_$name"])
                                        for (name, _) in forecast_error_lines))
        column == 1 && axislegend(panel, drawn,
            ["archived forecast", "blend planned on", "climatology"]; position=:rb)
    end
    weights = Axis(figure[2, 2]; xlabel="lead time [days]", ylabel=L"weight $a(L)$",
        title="(d) weight of the forecast in the blend")
    for (quantity, label, linestyle) in (("wind", "wind", :solid),
        ("height", "wave height", :dash))
        lines!(weights, days, errors["$(quantity)_weight"]; color=:black, linestyle, label)
    end
    ylims!(weights, 0, 1)
    axislegend(weights; position=:rt)
    save_figure("forecast", figure)
end

"columns of forecast_error.csv in the forecast figure's error panels, with their style"
forecast_error_lines = (("forecast", (; color=:black)), ("blend", (; color=palette[1])),
    ("climate", (; color=:gray50, linestyle=:dash)))

"rigs of the combination figure with their legend labels and colours"
combination_rigs = (("kite", "best kite", palette[1]),
    ("rotors", "best rotors", palette[3]),
    ("kite+rotors", "best kite and rotors together", level_fill("kite", "rotors")))

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
            range_bar!(saving_axis, group + 0.27(k - 2), values, 0.2, colour)
            push!(tops, maximum(values))
        end
        gains = pair_gain.(savings)
        range_bar!(gain_axis, group, gains, 0.32, level_fill("kite", "rotors"))
        print_combination(ship, drive, savings, gains)
    end
    @printf("  noise of the extra saving %.2f points, %.2f to %.2f by design\n",
        gain_noise, extrema(errors)...)
    for axis in (saving_axis, gain_axis)
        reference_line!(axis)
    end
    ylims!(saving_axis, nothing, 1.4maximum(tops))
    ylims!(gain_axis, -1.6 * 2gain_noise, nothing)
    text!(gain_axis, length(groups) + 0.5, -2gain_noise;
        text="twice its standard error", align=(:right, :top),
        offset=clear_offset((:right, :top), pt(2)), fontsize=note_size, color=:gray35)
    capped = Point2f[(0.35, 0), (0.65, 0), (0.5, 0), (0.5, 1), (0.35, 1), (0.65, 1)]
    entries = [[fill_entry(colour) for (_, _, colour) in combination_rigs];
        LineElement(points=capped, color=:black, linewidth=0.8)]
    axislegend(saving_axis, entries, [collect(getindex.(combination_rigs, 2));
        "range over the two routes"]; position=:lt)
    save_figure("combination", figure)
end

"""
    range_bar!(axis, x, values, width, fill)

Bar of `width` at `x` to the mean of `values`, filled by [`fill_rect!`](@ref) with `fill`,
with a range bar from their least to their largest.
"""
function range_bar!(axis, x, values, width, fill)
    fill_rect!(axis, Rect2f(x - width / 2, 0, width, mean(values)), fill;
        strokecolor=:gray20, strokewidth=rule_width)
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
    labelled = []
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
            margin = 0.05 * (maximum(drawn) - minimum(drawn))
            ylims!(axis, minimum(drawn) - margin, maximum(drawn) + margin)
            xlims!(axis, first(grid.speeds) - 0.3,
                last(grid.speeds) + 0.55 * (last(grid.speeds) - first(grid.speeds)))
            push!(labelled, (axis, grid, shades, ends))
        end
    end
    Makie.update_state_before_display!(figure)
    for (axis, grid, shades, ends) in labelled
        end_labels!(axis, last(grid.speeds), ends,
            [square_metres("$(round(Int, area)) ") for area in grid.kites],
            shades[(1:length(grid.kites)) .+ 3])
    end
    save_figure("speed_size", figure)
end

"""
    end_labels!(axis, x, ends, texts, colours)

Labels `texts` in `colours` right of the line ends at `x` and heights `ends` in `axis`,
moved apart where they would touch and kept within its limits; the figure laid out.
"""
function end_labels!(axis, x, ends, texts, colours)
    anchors = Point2f.(x, ends)
    label = text!(axis, anchors; text=texts, color=colours, fontsize=note_size,
        align=(:left, :center), offset=(5, 0))
    reach = maximum(zip(Makie.string_boundingboxes(label), anchors)) do (box, anchor)
        centre = pixel_point(axis.scene, anchor)[2]
        max(centre - minimum(box)[2], maximum(box)[2] - centre)
    end
    limits = axis.finallimits[]
    low, high = minimum(limits)[2], maximum(limits)[2]
    per_unit = (high - low) / height(axis.scene.viewport[])
    half = reach * per_unit
    spread = spread_labels(ends, 2half + label_clearance * per_unit, low + half,
        high - half)
    label[1] = Point2f.(x, spread)
end

"""
    min_wind_figure()

Lowest apparent wind against projected area for the kite of the design aspect ratio: the
crosswind and climbing bounds at the lowest elevation, and the calm-sea launch wind the
model uses, the larger of the climbing bound and the reported launch wind, with its range
over the range of the reported launch wind.
"""
function min_wind_figure()
    figure = Figure(size=(column_width, 190))
    axis = Axis(figure[1, 1]; doubling_axis(:x, 500, 16000)...,
        xlabel=square_metres("projected kite area [", "]"),
        ylabel="lowest apparent wind [m/s]")
    areas = exp.(range(log(500), log(16000); length=40))
    elevation = deg2rad(assumptions[:kite_min_elevation])
    bounds = one_at_a_time(assumptions, (:kite_launch_min_wind,))
    winds = map(areas) do area
        model, _, _ = WindShipOpt.kite_model(area, design_aspect_ratio, assumptions)
        launches = [WindShipOpt.launch_min_wind(model, inputs) for inputs in bounds]
        (cross=WindShipOpt.crosswind_min_wind(model, elevation),
            climb=WindShipOpt.climbing_min_wind(model, elevation),
            launch=WindShipOpt.launch_min_wind(model, assumptions),
            launch_low=minimum(launches), launch_high=maximum(launches))
    end
    launch_colour = :gray60
    band!(axis, areas, getindex.(winds, :launch_low), getindex.(winds, :launch_high);
        color=(launch_colour, 0.25))
    curves = ((:launch, launch_colour, pt(3.5)), (:climb, category_colours[2], line_width),
        (:cross, category_colours[3], line_width))
    for (key, color, linewidth) in curves
        lines!(axis, areas, getindex.(winds, key); color, linewidth)
    end
    ylims!(axis, 0, 1.35 * maximum(getindex.(winds, :launch_high)))
    entries = [key == :launch ?
               [PolyElement(color=(color, 0.25)), LineElement(; color, linewidth)] :
               LineElement(; color, linewidth) for (key, color, linewidth) in curves]
    axislegend(axis, entries, ["launch", "climb", "crosswind"]; position=:lt,
        orientation=:horizontal)
    save_figure("min_wind", figure)
end

"""
    missed_goals_figure()

Cost saving of each rig against the canopy life, the canopy price and the share out of
service, for each ship of the development study with its rig sizes held: the kite's saving
over the swept canopy inputs, the other rigs' at their goals, and every rig's over its
share out of service. Each goal is a vertical line over the shaded range of its input,
and the canopy price, an estimate with no range, a dotted line.
"""
function missed_goals_figure()
    sizes = read_table(data_file("goal_sizes.csv"))
    service = read_table(data_file("availability.csv"))
    lives = read_table(data_file("canopy_life.csv"))
    prices = read_table(data_file("canopy_price.csv"))
    ships = unique(service["ship"])
    sweeps = ((lives, "life"), (prices, "price"))
    rigs = study_rigs(sizes)
    service_inputs = [assumptions.entries[Symbol(out_of_service_inputs[rig])]
                      for (_, rig) in rigs]
    service_goal = only(unique(input.value for input in service_inputs))
    figure = Figure(size=(page_width, 410))
    for (column, ship) in enumerate(ships)
        bare = bare_cost(sizes, ship)
        curves = Dict(rig => share_costs(service, ship, rig) for (_, rig) in rigs)
        goal = Dict(rig => percent_saving(curve_cost(curves[rig],
                assumptions[Symbol(out_of_service_inputs[rig])]), bare)
                    for (_, rig) in rigs)
        axes = [Axis(figure[row, column]; xlabel, ylabel=column == 1 ? "saving [%]" : "",
                    title=row == 1 ? "($('a' + column - 1)) $ship" : "", xscale, xticks,
                    yticks=WilkinsonTicks(4; Q=[(1.0, 1.0), (5.0, 0.9), (2.0, 0.7)]),
                    yautolimitmargin=(0.05, 0.1))
                for (row, (xlabel, xscale, xticks)) in enumerate((
                    ("canopy life [h]", log10, doubling_ticks(500, 16000)),
                    (square_metres("canopy price [USD/", "]"), identity,
                        Makie.automatic),
                    ("out of service [%]", Makie.pseudolog10,
                        [0, 1, 2, 4, 8, 16, 32, 64])))]
        goal_marks!(axes[1], assumptions.entries[:canopy_life])
        vlines!(axes[2], reference_canopy_price(assumptions); color=:black,
            linewidth=goal_width, linestyle=:dot)
        goal_marks!(axes[3], 100service_goal,
            100minimum(input.low for input in service_inputs),
            100maximum(input.high for input in service_inputs))
        foreach(reference_line!, axes)
        for (axis, (table, input)) in zip(axes, sweeps)
            picked = rows(table, "ship" => ship)
            order = sortperm(table[input][picked])
            values = table[input][picked][order]
            for (k, rig) in rigs
                rig == "kite" && continue
                hlines!(axis, goal[rig]; color=palette[k], linestyle=:dash, linewidth=1)
            end
            scatterlines!(axis, values, percent_saving.(table["cost"][picked][order], bare);
                color=palette[1])
        end
        for (k, rig) in rigs
            shares, costs = curves[rig]
            scatterlines!(axes[3], 100shares, percent_saving.(costs, bare);
                color=palette[k])
        end
        if column == 1
            price_high = maximum(prices["price"])
            for (k, rig) in rigs
                rig == "kite" && continue
                align = rig == "rotors" ? (:right, :top) : (:right, :bottom)
                text!(axes[2], price_high, goal[rig];
                    text=rig_label(rig), color=palette[k],
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
                    LineElement(color=:black, linewidth=goal_width)],
                LineElement(color=:black, linewidth=goal_width, linestyle=:dot)],
            ["goal, its range", "estimate"]; position=(1, 0.6))
    end
    save_figure("missed_goals", figure)
end

"""
    goal_marks!(axis, value, low, high)

A vertical goal line at `value` over the range from `low` to `high` shaded grey;
`goal_marks!(axis, input)` for an input of the assumptions.
"""
function goal_marks!(axis, value, low, high)
    vspan!(axis, low, high; color=(:gray50, 0.15))
    vlines!(axis, value; color=:black, linewidth=goal_width)
end

goal_marks!(axis, input) = goal_marks!(axis, input.value, input.low, input.high)

"""
    reference_line!(axis, value=0; vertical=false, linestyle=:solid)

A horizontal line, or a `vertical` one, at `value` across `axis` in the guide colour.
"""
reference_line!(axis, value=0; vertical=false, linestyle=:solid) =
    (vertical ? vlines! : hlines!)(axis, value; color=style_colour("guide"),
        linewidth=rule_width, linestyle)

"inputs of the mass of a soft kite without its tether, each with its bound that lightens it"
soft_mass_inputs = (canopy_flat_area_ratio=:low, canopy_cell_width=:high)

"""
    soft_mass_bound(lightest)

`assumptions` with every one of [`soft_mass_inputs`](@ref) at the bound that makes a soft
kite lightest, or heaviest where `lightest` is false.
"""
function soft_mass_bound(lightest)
    return foldl(pairs(soft_mass_inputs); init=assumptions) do inputs, (name, light)
        bound = lightest ? light : (light == :low ? :high : :low)
        with_value(inputs, name, getfield(inputs.entries[name], bound))
    end
end

"""
    soft_kite_mass(area, inputs)

Mass [kg] of a soft kite of projected `area` [m^2] without its tether, at `inputs`.
"""
function soft_kite_mass(area, inputs)
    aspect_ratio = inputs[:kite_aspect_ratio]
    max_force = 1e3inputs[:kite_max_force_per_area] * area
    return WindShipOpt.soft_kite_mass(area, aspect_ratio, max_force, inputs)
end

"""
    mass_law!(axis, sizes, per_area, low, high, largest_built, color)

The mass per area `per_area` of a law over `sizes` between its `low` and `high` bounds,
solid up to the `largest_built` size and dashed beyond it.
"""
function mass_law!(axis, sizes, per_area, low, high, largest_built, color)
    band!(axis, sizes, low, high; color=(color, 0.18))
    built = sizes .<= largest_built
    lines!(axis, sizes[built], per_area[built]; color)
    beyond = findfirst(.!built) - 1:lastindex(sizes)
    lines!(axis, sizes[beyond], per_area[beyond]; color, linestyle=:dash)
end

"marker of a published wing or kite that flew, was built, or was only designed"
status_markers = Dict("flown" => :circle, "built" => :rect, "designed" => :utriangle)

"the assumptions at each pair of bounds of the VTOL kite's mass and its exponent"
rigid_mass_bounds() = [with_value(with_value(assumptions, :rigid_mass,
                           getfield(assumptions.entries[:rigid_mass], mass)),
                           :rigid_mass_exponent,
                           getfield(assumptions.entries[:rigid_mass_exponent], exponent))
                       for mass in (:low, :high), exponent in (:low, :high)]

"""
    lei_kite_mass(area, inputs)

Mass [kg] of a leading-edge inflatable kite of projected `area` [m^2] without its tether, at
`inputs`.
"""
lei_kite_mass(area, inputs) = WindShipOpt.soft_kite_mass(area, inputs[:lei_aspect_ratio],
    1e3inputs[:lei_max_force_per_area] * area, inputs, WindShipOpt.TubeFrame())

"the assumptions at each bound of the leading-edge inflatable kite's force limit per area"
lei_mass_bounds() = [with_value(assumptions, :lei_max_force_per_area,
                         getfield(assumptions.entries[:lei_max_force_per_area], bound))
                     for bound in (:low, :high)]

"""
    kite_mass_figure()

Mass per area against area of VTOL kites, ram-air kites and leading-edge inflatable kites
without their tether: each law at base inputs between its bounds, dashed beyond the largest
kite of its kind flown and beyond MX2, which the VTOL kite's law is scaled from, and the
published wings and kites of data/kite_masses.csv, its `kind`, `status`, `area` [m^2] and
`mass_low` to `mass_high` [kg].
"""
function kite_mass_figure()
    published = read_table(joinpath(root, "data", "kite_masses.csv"))
    rigid_colour, soft_colour, lei_colour = style_colour("vtol"), palette[1],
    style_colour("lei")
    figure = Figure(size=(column_width, 200))
    axis = Axis(figure[1, 1]; doubling_axis(:x, 2.5, 5120; base=2.5)...,
        doubling_axis(:y, 0.125, 8192; base=0.125)...,
        xlabel=square_metres("projected area [", "]"),
        ylabel=square_metres("mass per area [kg/", "]"), limits=(nothing, (0.08, 12000)))
    flew = published["status"] .!= "designed"
    soft = published["kind"] .== "soft"
    rigid_areas = exp.(range(log(10), log(2000); length=50))
    rigid_per_area(inputs) = WindShipOpt.rigid_kite_mass.(rigid_areas, Ref(inputs)) ./
                             rigid_areas
    bounds = rigid_per_area.(rigid_mass_bounds())
    mass_law!(axis, rigid_areas, rigid_per_area(assumptions), min.(bounds...),
        max.(bounds...), assumptions[:rigid_reference_area], rigid_colour)
    soft_areas = exp.(range(log(5), log(5000); length=50))
    per_area(inputs) = soft_kite_mass.(soft_areas, Ref(inputs)) ./ soft_areas
    mass_law!(axis, soft_areas, per_area(assumptions), per_area(soft_mass_bound(true)),
        per_area(soft_mass_bound(false)), maximum(published["area"][flew .& soft]),
        soft_colour)
    lei_per_area(inputs) = lei_kite_mass.(soft_areas, Ref(inputs)) ./ soft_areas
    lei_bounds = lei_per_area.(lei_mass_bounds())
    mass_law!(axis, soft_areas, lei_per_area(assumptions), min.(lei_bounds...),
        max.(lei_bounds...), maximum(published["area"][published["kind"] .== "lei"]),
        lei_colour)
    kind_colours = Dict("soft" => soft_colour, "lei" => lei_colour,
        "propellers" => rigid_colour)
    for row in eachindex(published["name"])
        color = get(kind_colours, published["kind"][row], category_colours[2])
        area = published["area"][row]
        low, high = published["mass_low"][row], published["mass_high"][row]
        rangebars!(axis, [area], [low / area], [high / area]; color)
        scatter!(axis, [area], [(low + high) / 2area]; color,
            marker=status_markers[published["status"][row]])
    end
    statuses = ["flown", "built", "designed"]
    markers = [MarkerElement(color=:black, marker=status_markers[status])
               for status in statuses]
    entries = [LineElement(color=rigid_colour), LineElement(color=soft_colour),
        LineElement(color=lei_colour), LineElement(color=:black, linestyle=:dash),
        markers...]
    axislegend(axis, entries,
        ["VTOL kite", "ram-air kite", "LEI kite", "extrapolated", statuses...];
        position=:lt, nbanks=3, rowgap=0, colgap=pt(6),
        patchsize=(pt(12), pt(6)))
    save_figure("kite_mass", figure)
end

"""
    deck_mass_figure()

Mass per area against unit height of the wing sails, rotors and suction sails: each size
law at base inputs between the bounds of its mass exponent, solid up to the tallest unit
built and dashed beyond, and the built units of data/deck_unit_masses.csv, their `unit`,
`height` [m], `width` [m] and `mass` [t].
"""
function deck_mass_figure()
    built = read_table(joinpath(root, "data", "deck_unit_masses.csv"))
    figure = Figure(size=(column_width, 200))
    axis = Axis(figure[1, 1]; doubling_axis(:x, 10, 160; base=10)...,
        doubling_axis(:y, 0.0625, 2; base=0.0625)..., xlabel="unit height [m]",
        ylabel=rich("mass per area [t/m", superscript("2"), "]"),
        limits=((9, 170), (0.06, 2.2)))
    heights = exp.(range(log(9), log(170); length=60))
    for (unit, rig) in ((:wing, "wings"), (:rotor, "rotors"), (:suction, "suction"))
        setting(name) = assumptions[Symbol(unit, name)]
        reference = setting(:_reference_height)
        exponent = assumptions.entries[Symbol(unit, :_mass_exponent)]
        law(k) = setting(:_mass_per_area) .* max.(heights ./ reference, 1.0) .^ (k - 2)
        mass_law!(axis, heights, law(exponent.value), law(exponent.low),
            law(exponent.high), reference, style_colour(rig))
        rows = built["unit"] .== String(unit)
        scatter!(axis, built["height"][rows],
            built["mass"][rows] ./ (built["height"][rows] .* built["width"][rows]);
            color=style_colour(rig))
    end
    entries = [[LineElement(color=style_colour(rig)),
                   MarkerElement(color=style_colour(rig), marker=:circle)]
               for rig in ("wings", "rotors", "suction")]
    axislegend(axis, [entries..., LineElement(color=:black, linestyle=:dash)],
        ["wing sail", "rotor", "suction sail", "extrapolated"]; position=:lt, nbanks=2,
        rowgap=0, colgap=pt(6), patchsize=(pt(12), pt(6)))
    save_figure("deck_mass", figure)
end

"marker of a published canopy of each `kind` in data/canopy_cells.csv"
canopy_markers = Dict("paraglider" => :circle, "kite" => :rect, "parafoil" => :utriangle)

"""
    canopy_cells_figure()

Mean chord over cell width against mean chord of the ram-air canopies of
data/canopy_cells.csv, its `kind`, `flat_area` [m^2], `flat_span` [m] and `cells`, and the
rule of the model, the cells of `canopy_cell_width` at every chord between its bounds, solid
over the mean chords of the kites the class study searches.
"""
function canopy_cells_figure()
    published = read_table(joinpath(root, "data", "canopy_cells.csv"))
    chords = published["flat_area"] ./ published["flat_span"]
    ratios = chords .* published["cells"] ./ published["flat_span"]
    figure = Figure(size=(column_width, 170))
    axis = Axis(figure[1, 1]; xscale=log10, yscale=log10, xlabel=L"mean chord $c$ [m]",
        ylabel=L"chord over cell width $c/w$",
        xticks=([1, 3, 10, 30, 100], ["1", "3", "10", "30", "100"]),
        yticks=([1, 3, 10, 30, 100], ["1", "3", "10", "30", "100"]),
        limits=(nothing, (0.8, 300)))
    kite_areas = size_bounds(first(values(ship_classes())))["kite"]
    kite_chords = sqrt.(collect(kite_areas) ./ assumptions[:kite_aspect_ratio])
    vspan!(axis, kite_chords...; color=(:gray50, 0.15))
    line_chords = sort([exp.(range(log(0.8), log(160); length=60)); kite_chords...])
    width = assumptions.entries[:canopy_cell_width]
    band!(axis, line_chords, line_chords ./ width.high, line_chords ./ width.low;
        color=(palette[1], 0.18))
    rule = line_chords ./ width.value
    searched = minimum(kite_chords) .<= line_chords .<= maximum(kite_chords)
    beyond = .!(minimum(kite_chords) .< line_chords .< maximum(kite_chords))
    lines!(axis, line_chords, ifelse.(searched, rule, NaN); color=palette[1])
    lines!(axis, line_chords, ifelse.(beyond, rule, NaN); color=palette[1], linestyle=:dash)
    for kind in keys(canopy_markers)
        shown = published["kind"] .== kind
        scatter!(axis, chords[shown], ratios[shown]; color=:black,
            marker=canopy_markers[kind])
    end
    kinds = ["paraglider", "kite", "parafoil"]
    markers = [MarkerElement(color=:black, marker=canopy_markers[kind]) for kind in kinds]
    entries = [markers..., LineElement(color=palette[1]),
        PolyElement(color=(:gray50, 0.15))]
    axislegend(axis, entries, [kinds..., "model", "kites searched"]; position=:lt,
        nbanks=2, rowgap=0, colgap=pt(6), patchsize=(pt(12), pt(6)))
    save(joinpath(figures, "canopy_cells.pdf"), figure; pt_per_unit=print_scale)
end
