# Figure steps of the paper: each saves one PDF to paper/figures/, from the CSV files of
# the run in use, the data in data/kite_polars/ or the model itself. Included by paper.jl.

figures = mkpath(joinpath(root, "paper", "figures"))
polars = joinpath(root, "data", "kite_polars")
aspect_ratios = (3, 5, 8)
palette = Makie.wong_colors()
set_theme!(fontsize=10, figure_padding=4, Axis=(; xgridvisible=false, ygridvisible=false,
    titlesize=10, titlefont=:regular, titlealign=:left))
column_width = 334
page_width = 522
# points per figure unit, so that a page-wide figure is the 468 pt text width
print_scale = 468 / page_width
"the [`study_drives`](@ref) with their names in figure labels"
drive_labels = [string(drive) => Dict(:vlsfo => "VLSFO", :methanol => "e-methanol",
                    :hydrogen => "hydrogen")[drive] for drive in study_drives]
"(drive, panel title) of the panels (a), (b), (c) of a figure with one panel per drive"
drive_panels = [(drive, "($(Char('a' + k - 1))) $label")
                for (k, (drive, label)) in enumerate(drive_labels)]
"each rig with its area column in designs.csv"
rig_area_columns = (("kite", "kite_area"), ("wings", "wing_area"), ("rotors", "rotor_area"))

"""
    read_table(path)

Columns of a CSV file with a header line, as a Dict of name to vector; numbers parsed
and quotes removed.
"""
function read_table(path)
    lines = readlines(path)
    names = WindShipOpt.csv_fields(first(lines))
    rows = [WindShipOpt.csv_fields(line) for line in lines[2:end]]
    table = Dict{String, Vector}()
    for (k, name) in enumerate(names)
        values = getindex.(rows, k)
        numbers = tryparse.(Float64, values)
        table[name] = any(isnothing, numbers) ? String.(values) : Float64.(numbers)
    end
    return table
end

"""
    kite_geometry_figure()

Planforms of the kites of the three aspect ratios at equal projected area, seen
from above and to scale, with their projected span.
"""
function kite_geometry_figure()
    figure = Figure(size=(page_width, 120))
    geometries = [read_table(joinpath(polars, "geometry_ar$aspect_ratio.csv"))
                  for aspect_ratio in aspect_ratios]
    half_span = maximum(maximum(abs, geometry["le_y"]) for geometry in geometries)
    chords = [extrema([geometry["le_x"]; geometry["te_x"]]) for geometry in geometries]
    chord_limits = (minimum(first.(chords)) - 0.5, maximum(last.(chords)) + 3)
    for (i, (aspect_ratio, geometry)) in enumerate(zip(aspect_ratios, geometries))
        axis = Axis(figure[1, i]; aspect=DataAspect(), title="AR $aspect_ratio",
            titlealign=:center, limits=(-half_span - 1, half_span + 1, chord_limits...),
            yreversed=true)
        hidedecorations!(axis)
        hidespines!(axis)
        outline = [Point2f.(geometry["le_y"], geometry["le_x"]);
            Point2f.(reverse(geometry["te_y"]), reverse(geometry["te_x"]))]
        poly!(axis, outline; color=(palette[i], 0.8), strokecolor=:black,
            strokewidth=0.8)
        span = maximum(geometry["le_y"]) - minimum(geometry["le_y"])
        text!(axis, 0, maximum(last.(chords)) + 0.6;
            text="span $(round(span; digits=1)) m", align=(:center, :top), fontsize=8.5)
    end
    save(joinpath(figures, "kite_geometry.pdf"), figure; pt_per_unit=print_scale)
end

"""
    polar_figure()

Lift, drag and glide ratio of the kites in their design shape over angle of attack,
without bridle and tether.
"""
function polar_figure()
    figure = Figure(size=(page_width, 170))
    lift = Axis(figure[1, 1]; xlabel="angle of attack [°]", ylabel="lift coefficient")
    drag = Axis(figure[1, 2]; xlabel="angle of attack [°]", ylabel="drag coefficient")
    glide = Axis(figure[1, 3]; xlabel="angle of attack [°]", ylabel="lift over drag")
    for (i, aspect_ratio) in enumerate(aspect_ratios)
        polar = read_table(joinpath(polars, "kite_ar$aspect_ratio.csv"))
        label = "AR $aspect_ratio"
        lines!(lift, polar["alpha"], polar["cl"]; color=palette[i], label)
        lines!(drag, polar["alpha"], polar["cd"]; color=palette[i])
        lines!(glide, polar["alpha"], polar["cl"] ./ polar["cd"]; color=palette[i])
    end
    axislegend(lift; position=:rb, framevisible=false)
    save(joinpath(figures, "polars.pdf"), figure; pt_per_unit=print_scale)
end

"""
    rows(table, conditions...)

Indices of the rows of `table` where each `column => value` condition holds.
"""
function rows(table, conditions...)
    chosen = trues(length(first(values(table))))
    for (column, value) in conditions
        chosen .&= table[column] .== value
    end
    return findall(chosen)
end

"""
    percent_saving(cost, reference)

Saving [%] of `cost` against `reference`.
"""
percent_saving(cost, reference) = 100 * (1 - cost / reference)

"""
    pattern_figure()

Optimal flight paths seen from the ship over the course off apparent downwind, in light
and strong apparent wind, without side-force weight.
"""
function pattern_figure()
    paths = read_table(data_file("patterns.csv"))
    forces = read_table(data_file("pattern_forces.csv"))
    figure = Figure(size=(page_width, 300))
    courses = 0:30:180
    colours = Makie.resample_cmap(:viridis, length(courses))
    for (row, wind) in enumerate((6.0, 12.0))
        bottom = row == 2
        letter = ('a', 'b')[row]
        axis = Axis(figure[row, 1]; ylabel="elevation [°]", limits=(-35, 90, 0, 60),
            xlabel=bottom ? "azimuth off apparent downwind [°]" : "",
            title="($letter) flight paths, apparent wind $(round(Int, wind)) m/s")
        for (i, course) in enumerate(courses)
            chosen = rows(paths, "wind" => wind, "course" => course, "side_weight" => 0.0)
            isempty(chosen) && continue
            lines!(axis, rad2deg.(paths["azimuth"][chosen]),
                rad2deg.(paths["elevation"][chosen]); color=colours[i], linewidth=1.2)
        end
        bottom || hidexdecorations!(axis; ticks=false, ticklabels=false)
        thrust = Axis(figure[row, 2]; ylabel="force [kN]", limits=((-5, 185), nothing),
            xlabel=bottom ? "course off apparent downwind [°]" : "", xticks=0:30:180,
            yticks=WilkinsonTicks(4),
            title="($(('c', 'd')[row])) tether force on the ship")
        hlines!(thrust, 0; color=:gray80, linewidth=0.5)
        chosen = rows(forces, "wind" => wind, "side_weight" => 0.0)
        for (k, (column, label)) in enumerate((("thrust", "thrust"),
            ("side", "side force")))
            scatterlines!(thrust, forces["course"][chosen], forces[column][chosen] ./ 1e3;
                color=palette[k], label, markersize=4)
        end
        row == 1 && Legend(figure[3, 2], thrust; orientation=:horizontal,
            framevisible=false, labelsize=9)
    end
    Colorbar(figure[3, 1]; colormap=cgrad(colours; categorical=true),
        limits=(-15, 195), ticks=courses, vertical=false, flipaxis=false, height=6,
        label="course off apparent downwind [°]", ticklabelsize=9, labelsize=9)
    colsize!(figure.layout, 1, Relative(0.5))
    save(joinpath(figures, "patterns.pdf"), figure; pt_per_unit=print_scale)
end

"""
    draw_force_balance!(axis, area, force, radius)

Draw on `axis` the path from tether force to cloth tension of a kite of `area` [m^2], at
tether force `force` [N] and skin radius `radius` [m]: the kite pulled by its tether, the
pressure that force implies over the canopy, and a cell whose skin carries the tension.
"""
function draw_force_balance!(axis, area, force, radius)
    pressure = force / area
    style = (shaftwidth=1.5, tipwidth=7, tiplength=7)
    arc(centre, reach, sweep) = [centre .+ reach .* (cos(angle), sin(angle))
                                 for angle in sweep]
    lines!(axis, arc((0.0, -1.0), 2.0, range(π / 4, 3π / 4; length=40)); color=:black,
        linewidth=2)
    wedge = [(x, sqrt(4 - x^2) - 1.0) for x in range(-1.2, 1.2; length=5)]
    arrows2d!(axis, first.(wedge), last.(wedge), zeros(5), fill(0.4, 5); color=palette[2],
        style...)
    arrows2d!(axis, [0.0], [0.8], [0.0], [-2.3]; color=palette[1], style...)
    text!(axis, 0.0, 1.5; text=@sprintf("p = F / A = %.0f N/m²", pressure), fontsize=9,
        align=(:center, :bottom), color=palette[2])
    text!(axis, -0.2, -0.9;
        text=@sprintf("F = %.1f MN\nA = %.0f m²", force / 1e6, area),
        fontsize=9, align=(:right, :center), color=palette[1])
    left, right = (3.3, 0.0), (6.3, 0.0)
    centre = ((left[1] + right[1]) / 2, -0.75)
    reach = hypot(left[1] - centre[1], centre[2])
    opening = atan(-centre[2], right[1] - centre[1])
    lines!(axis, arc(centre, reach, range(opening, π - opening; length=40)); color=:black,
        linewidth=2)
    lines!(axis, [left, (left[1], -1.3)]; color=:gray60, linewidth=2)
    lines!(axis, [right, (right[1], -1.3)]; color=:gray60, linewidth=2)
    arrows2d!(axis, [centre[1]], [centre[2]], [0.0], [reach]; color=:gray40, style...)
    text!(axis, centre[1], -1.05; text=@sprintf("R = %.1f m", radius), fontsize=9,
        align=(:center, :center))
    for (corner, side) in ((left, 1), (right, -1))
        arrows2d!(axis, [corner[1]], [corner[2]], [0.8side * sin(opening)],
            [0.8cos(opening)]; color=palette[3], style...)
    end
    text!(axis, centre[1], 1.25; text=@sprintf("T = p R = %.0f N/m", pressure * radius),
        fontsize=9, align=(:center, :bottom), color=palette[3])
    text!(axis, left[1] - 0.1, -0.8; text="rib", fontsize=8, align=(:right, :center),
        color=:gray40)
    arrows2d!(axis, [1.9], [0.3], [0.8], [0.0]; color=:gray60, style...)
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
    strength = cloth_specific_strength * assumptions[:canopy_cloth_weight] / 1e3
    figure = Figure(size=(page_width, 210))
    balance = Axis(figure[1, 1]; aspect=DataAspect(), limits=(-3.0, 7.0, -1.8, 2.0),
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
    lines!(force_axis, times, forces; color=palette[1], linewidth=1.5)
    hlines!(force_axis, mean_force; color=palette[2], linestyle=:dash)
    hlines!(force_axis, peak_force; color=palette[3], linestyle=:dot)
    text!(force_axis, times[end], mean_force;
        text=@sprintf("mean %.2f MN, %.2f kN/m", mean_force, tension(mean_force)),
        fontsize=8, align=(:right, :top), color=palette[2])
    text!(force_axis, times[1], peak_force;
        text=@sprintf("peak %.2f MN, %.2f kN/m\nnew cloth %.0f kN/m, %.0f × peak",
            peak_force, tension(peak_force), strength, strength / tension(peak_force)),
        fontsize=8, align=(:left, :bottom), color=palette[3])
    colsize!(figure.layout, 1, Relative(0.52))
    save(joinpath(figures, "canopy_tension.pdf"), figure; pt_per_unit=print_scale)
end

"""
    rig_polar_figure()

Thrust and side force of the best trim over true wind angle on a 140 m ship at 10.5 kn in
10 m/s wind, for an 800 m^2 kite, 800 m^2 of wings and 400 m^2 of rotors.
"""
function rig_polar_figure()
    figure = Figure(size=(column_width, 398))
    thrust = Axis(figure[1, 1]; ylabel="thrust [kN]")
    side = Axis(figure[2, 1]; xlabel="true wind angle [°]", ylabel="side force [kN]")
    angles = 30:5:180
    rigs = (("kite 800 m²", (kite_area=800.0,)), ("wings 800 m²", (wing_area=800.0,)),
        ("rotors 400 m²", (rotor_area=400.0,)))
    for (i, (label, area)) in enumerate(rigs)
        ship = Ship(ShipDesign(:vlsfo, 140.0; area...), assumptions)
        forces = [last(WindShipOpt.best_trim(ship, ship.rig, 10.5KNOT, 10.0,
                      deg2rad(angle))) for angle in angles]
        lines!(thrust, angles, [force.thrust for force in forces] ./ 1e3;
            color=palette[i], label)
        lines!(side, angles, abs.([force.side for force in forces]) ./ 1e3;
            color=palette[i])
    end
    entries = [LineElement(color=palette[i], linewidth=1.5) for i in eachindex(rigs)]
    axislegend(thrust, entries, collect(first.(rigs)); position=:lt, framevisible=false,
        labelsize=9)
    linkxaxes!(thrust, side)
    hidexdecorations!(thrust; grid=false)
    save(joinpath(figures, "rig_polar.pdf"), figure; pt_per_unit=print_scale)
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
    for (column, (drive, title)) in enumerate(drive_panels)
        labels = String[]
        cells = Tuple{Int, Int, Float64}[]
        best = Tuple{Int, Int}[]
        row = 0
        for (kind, column_name) in rig_area_columns
            areas = sort(unique(designs[column_name][rows(designs, "scenario" => "base",
                "drive" => drive)]))
            areas = filter(>(0), areas)
            first_row = row + 1
            for area in areas
                row += 1
                push!(labels, "$kind $(round(Int, area)) m²")
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
        axis = Axis(figure[1, column]; title, xlabel="waterline length [m]",
            xticks=(eachindex(lengths), string.(round.(Int, lengths))),
            yticks=(eachindex(labels), labels), yreversed=true,
            yticklabelsvisible=column == 1, yticklabelsize=9)
        for (i, k, saving) in cells
            poly!(axis, Rect2f(i - 0.5, k - 0.5, 1, 1);
                color=get(cgrad(:RdBu), (clamp(saving, -30, 30) + 30) / 60))
            text!(axis, i, k; text=string(round(Int, saving)), fontsize=8.5,
                align=(:center, :center), color=abs(saving) > 18 ? :white : :black)
        end
        for (i, k) in best
            poly!(axis, Rect2f(i - 0.47, k - 0.47, 0.94, 0.94); color=:transparent,
                strokecolor=:black, strokewidth=1.2)
        end
        hlines!(axis, [findfirst(startswith("wings"), labels),
            findfirst(startswith("rotors"), labels)] .- 0.5; color=:black,
            linewidth=0.8)
        limits!(axis, 0.5, length(lengths) + 0.5, length(labels) + 0.5, 0.5)
    end
    Colorbar(figure[1, 4]; colormap=:RdBu, limits=(-30, 30),
        label="cost saving vs no rig [%]")
    save(joinpath(figures, "rig_comparison.pdf"), figure; pt_per_unit=print_scale)
end

"""
    route_figure()

Weather-routed passages on every route of a 140 m e-methanol ship without a rig and
with a 3200 m^2 kite, for a winter and a summer departure, over the 10 m wind five days
after departure; solid outbound, dashed homeward.
"""
function route_figure()
    designs = (ShipDesign(:methanol, 140.0), ShipDesign(:methanol, 140.0; kite_area=3200.0))
    port_hours = 24assumptions[:port_time_per_call]
    seasons = (("winter", 1), ("summer", findfirst(>=(24 * 181), departures)))
    figure = Figure(size=(page_width, 300))
    for (column, (season, index)) in enumerate(seasons)
        axis = Axis(figure[1, column]; title="($('a' + column - 1)) $season departure",
            xlabel="longitude [°]",
            ylabel=column == 1 ? "latitude [°]" : "", aspect=DataAspect(),
            limits=(-100, 12, -26, 58))
        draw_land!(axis, mask; lons=-100:0.25:12, lats=-26:0.25:58)
        departure = departures[index]
        draw_wind!(axis, weather, departure + 24 * 5; scale=0.12, lons=-98:6:10,
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
                    lines!(axis, smooth_track(getindex.(leg.path, 2),
                            getindex.(leg.path, 1));
                        color=k == 1 ? (:black, 0.6) : palette[i], linestyle=style,
                        linewidth=k == 1 ? 0.8 : 1.5)
                end
            end
        end
    end
    entries = [[LineElement(color=palette[i], linewidth=1.5)
                for i in eachindex(route_names)]; LineElement(color=(:black, 0.6),
        linewidth=0.8); LineElement(color=:black, linestyle=:dot, linewidth=0.8)]
    names = [[route_label(name) * " + kite" for name in route_names]; "no rig";
        "great circle"]
    Legend(figure[2, 1:2], entries, names; orientation=:horizontal, nbanks=2,
        framevisible=false, labelsize=9)
    save(joinpath(figures, "routes.pdf"), figure; pt_per_unit=print_scale)
end

"""
    window_mean(edges, values, low, high)

Time-weighted mean over [`low`, `high`] of the finite `values` that hold between
consecutive `edges`; `NaN` where none is finite.
"""
function window_mean(edges, values, low, high)
    overlaps = [max(0.0, min(edges[i + 1], high) - max(edges[i], low))
                for i in eachindex(values)]
    usable = [overlaps[i] > 0 && isfinite(values[i]) for i in eachindex(values)]
    any(usable) || return NaN
    return sum(overlaps[usable] .* values[usable]) / sum(overlaps[usable])
end

"""
    moving_average(times, values)

Hourly samples [h] and the centred 12 h moving average of the piecewise constant `values`,
each holding from its time to the next.
"""
function moving_average(times, values)
    edges = [times; last(times) + (last(times) - times[end - 1])]
    hours = range(first(times), last(edges); step=1.0)
    return hours, [window_mean(edges, values, hour - 6.0, hour + 6.0) for hour in hours]
end

"""
    passage_figure()

One winter outbound passage to Guadeloupe of a 140 m e-methanol ship without a rig and
with each rig: the routed tracks, and speed, rig thrust and fuel power over the passage.
"""
function passage_figure()
    designs = (("no rig", ShipDesign(:methanol, 140.0)),
        ("kite 3200 m²", ShipDesign(:methanol, 140.0; kite_area=3200.0)),
        ("wings 1500 m²", ShipDesign(:methanol, 140.0; wing_area=1500.0)),
        ("rotors 800 m²", ShipDesign(:methanol, 140.0; rotor_area=800.0)))
    departure = departures[1]
    outbound = first(run_corridors(:caribbean))
    figure = Figure(size=(page_width, 340))
    map = Axis(figure[1:3, 1]; aspect=DataAspect(), limits=(-63, 6, 14, 53),
        xlabel="longitude [°]", ylabel="latitude [°]", title="(a) routed tracks")
    draw_land!(map, mask)
    draw_wind!(map, weather, departure + 24 * 6; scale=0.1)
    labels = ("speed [kn]", "rig thrust [kN]", "fuel power [MW]")
    titles = ("(b) speed through the water", "(c) rig thrust", "(d) fuel power")
    panels = [Axis(figure[row, 2]; ylabel=labels[row], title=titles[row],
                  yticks=WilkinsonTicks(3),
                  xlabel=row == 3 ? "time since departure [days]" : "")
              for row in 1:3]
    for (i, (label, design)) in enumerate(designs)
        ship = Ship(design, assumptions)
        table = PerformanceTable(ship, assumptions)
        hourly = first(WindShipOpt.leg_time_costs(ShipCosts(ship, assumptions),
            assumptions))
        leg = route(outbound, table, weather, departure; time_cost=hourly)
        trace = WindShipOpt.LegTrace(table, leg, weather, departure; interval=3.0)
        i == 1 && lines!(map, great_circle(leg.path[1], leg.path[end])...; color=:black,
            linestyle=:dot, linewidth=1.0, label="great circle")
        lines!(map, smooth_track(getindex.(leg.path, 2), getindex.(leg.path, 1));
            color=palette[i], linewidth=1.5, label)
        for (panel, values) in zip(panels, (trace.speed ./ KNOT, trace.rig_thrust ./ 1e3,
            trace.fuel_power ./ 1e6))
            hours, averages = moving_average(trace.time, values)
            lines!(panel, hours ./ 24, averages; color=palette[i], linewidth=1.3)
        end
    end
    linkxaxes!(panels...)
    for panel in panels[1:2]
        hidexdecorations!(panel; grid=false, ticks=false)
    end
    Legend(figure[4, 1:2], map; orientation=:horizontal, framevisible=false, labelsize=9)
    colsize!(figure.layout, 1, Relative(0.5))
    save(joinpath(figures, "passage.pdf"), figure; pt_per_unit=print_scale)
end

"""
    best_savings(table, class, route, drive)

Cost saving [%] of the best size of each rig against the class without a rig on one
route and drive, as a Dict of rig name to saving; missing rigs are left out.
"""
best_savings(table, class, route, drive) = rig_savings(table, rig_names,
    "class" => class, "route" => route, "drive" => drive)

"""
    rig_savings(table, rigs, conditions...)

Cost saving [%] of the best size of each of `rigs` against no rig among the rows of
`table` where the `conditions` hold, as a Dict of rig name to saving; missing rigs are
left out.
"""
function rig_savings(table, rigs, conditions...)
    base = rows(table, conditions..., "rig" => "none")
    savings = Dict{String, Float64}()
    isempty(base) && return savings
    reference = only(table["cost"][base])
    for rig in rigs
        chosen = rows(table, conditions..., "rig" => rig)
        isempty(chosen) && continue
        savings[rig] = percent_saving(minimum(table["cost"][chosen]), reference)
    end
    return savings
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
    class_comparison_figure()

Cost saving of the best size of each rig for every ship class and drive: the mean
over the routes as a marker and the range over the routes as a bar.
"""
function class_comparison_figure()
    table = read_table(data_file("classes.csv"))
    names = class_order(table)
    routes_seen = unique(table["route"])
    figure = Figure(size=(page_width, 330))
    for (column, (drive, title)) in enumerate(drive_panels)
        axis = Axis(figure[1, column]; title, xlabel="cost saving [%]",
            yticks=(eachindex(names), names), yreversed=true,
            yticklabelsvisible=column == 1)
        vlines!(axis, 0; color=:gray, linewidth=0.5)
        for (j, kind) in enumerate(rig_names), (i, name) in enumerate(names)
            values = [get(best_savings(table, name, route, drive), kind, NaN)
                      for route in routes_seen]
            values = filter(isfinite, values)
            isempty(values) && continue
            y = i + (j - 2) * 0.22
            rangebars!(axis, [y], [minimum(values)], [maximum(values)];
                direction=:x, color=(palette[j], 0.6), linewidth=1.5)
            scatter!(axis, [sum(values) / length(values)], [y]; color=palette[j],
                markersize=6, label=i == 1 ? kind : nothing)
        end
    end
    Legend(figure[2, 1:3], content(figure[1, 1]); orientation=:horizontal,
        framevisible=false, labelsize=9)
    save(joinpath(figures, "class_comparison.pdf"), figure; pt_per_unit=print_scale)
end

"""
    cheapest_row(table, filters::Pair...)
    cheapest_row(table, class, route, drive, rig)

Row of `table` with the lowest cost among those matching `filters`, column => value, or of
`rig` for one class, route and drive; `nothing` where none was run.
"""
function cheapest_row(table, filters::Pair...)
    chosen = rows(table, filters...)
    return isempty(chosen) ? nothing : chosen[argmin(table["cost"][chosen])]
end

cheapest_row(table, class, route, drive, rig) = cheapest_row(table, "class" => class,
    "route" => route, "drive" => drive, "rig" => rig)

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
    class_size_figure()

Best area of each rig for every ship class and drive: the geometric mean over the
routes as a marker, the range over the routes as a bar and, for wings and rotors, the
median number of units at the best size.
"""
function class_size_figure()
    table = read_table(data_file("classes.csv"))
    names = class_order(table)
    routes_seen = unique(table["route"])
    figure = Figure(size=(page_width, 330))
    ticks = [100, 1000, 10000]
    for (column, (drive, title)) in enumerate(drive_panels)
        axis = Axis(figure[1, column]; title, xlabel="best rig area [m²]", xscale=log10,
            xticks=(ticks, string.(ticks)), yticks=(eachindex(names), names),
            yreversed=true, yticklabelsvisible=column == 1)
        for (j, kind) in enumerate(rig_names), (i, name) in enumerate(names)
            areas = filter(isfinite, [best_area(table, name, route, drive, kind)
                                      for route in routes_seen])
            isempty(areas) && continue
            y = i + (j - 2) * 0.22
            rangebars!(axis, [y], [minimum(areas)], [maximum(areas)]; direction=:x,
                color=(palette[j], 0.6), linewidth=1.5)
            centre = exp(sum(log, areas) / length(areas))
            scatter!(axis, [centre], [y]; color=palette[j], markersize=6,
                label=i == 1 ? kind : nothing)
            kind == "kite" && continue
            units = median_units(table, name, drive, kind)
            text!(axis, maximum(areas), y; text=" $units", fontsize=8.5,
                align=(:left, :center), color=palette[j])
        end
    end
    Legend(figure[2, 1:3], content(figure[1, 1]); orientation=:horizontal,
        framevisible=false, labelsize=9)
    save(joinpath(figures, "class_sizes.pdf"), figure; pt_per_unit=print_scale)
end

"""
    winner_map_figure()

The rig with the largest cost saving for every ship class and route, for each drive,
coloured by rig and labelled with its saving [%]; grey where no rig pays.
"""
function winner_map_figure()
    table = read_table(data_file("classes.csv"))
    names = class_order(table)
    route_names_seen = ["caribbean", "new_york", "bilbao", "dakar", "houston", "tubarao"]
    kinds = ["kite", "wings", "rotors"]
    figure = Figure(size=(page_width, 300))
    for (column, (drive, title)) in enumerate(drive_panels)
        axis = Axis(figure[1, column]; title,
            xticks=(eachindex(route_names_seen), route_label.(route_names_seen)),
            yticks=(eachindex(names), names), yreversed=true,
            yticklabelsvisible=column == 1, xticklabelrotation=π / 4)
        for (i, route) in enumerate(route_names_seen), (k, name) in enumerate(names)
            savings = best_savings(table, name, route, drive)
            isempty(savings) && continue
            winner = argmax(savings)
            best = savings[winner]
            colour = best > 0 ? (palette[findfirst(==(winner), kinds)], 0.35 + 0.65 *
                                 min(best, 40) / 40) : (:gray, 0.25)
            poly!(axis, Rect2f(i - 0.5, k - 0.5, 1, 1); color=colour)
            text!(axis, i, k; text=string(round(Int, best)), align=(:center, :center),
                fontsize=8.5)
        end
    end
    Legend(figure[2, 1:3], [PolyElement(color=palette[j]) for j in 1:3], kinds;
        orientation=:horizontal, framevisible=false, labelsize=9)
    save(joinpath(figures, "winner_map.pdf"), figure; pt_per_unit=print_scale)
end

"""
    track_wind(corridor, weather, times)

True wind angles [deg] and 10 m wind speeds [m/s] met along the centre line of
`corridor` at the given `times` [h], one pair per stage and time.
"""
function track_wind(corridor, weather, times)
    angles, speeds = Float64[], Float64[]
    centre = centre_index(corridor)
    for stage in 1:(size(corridor.lat, 1) - 1), time in times
        lat, lon = corridor.lat[stage, centre], corridor.lon[stage, centre]
        course = WindShipOpt.bearing(lat, lon, corridor.lat[stage + 1, centre],
            corridor.lon[stage + 1, centre])
        east, north = wind(weather, lat, lon, time)
        speed = hypot(east, north)
        push!(angles, rad2deg(WindShipOpt.true_wind_angle(east, north, speed, course)))
        push!(speeds, speed)
    end
    return angles, speeds
end

"""
    sector!(axis, angle, width, inner, outer; color)

Filled ring sector between radii `inner` and `outer` around `angle` [rad clockwise from
up] with `width` [rad], on a Cartesian `axis`.
"""
function sector!(axis, angle, width, inner, outer; color)
    arc = range(angle - width / 2, angle + width / 2; length=8)
    poly!(axis, [ring_points(outer, arc); ring_points(inner, reverse(arc))]; color,
        strokewidth=0)
end

"""
    ring_points(radius, angles)

Points at `radius` and `angles` [rad clockwise from up].
"""
ring_points(radius, angles) = Point2f.(radius .* sin.(angles), radius .* cos.(angles))

"""
    wind_climate_figure()

Wind roses relative to the ship along each route over the three years of weather: the
direction the wind comes from off the bow, head wind up, outbound on the left half and
homeward on the right; the sector length is the share of sailing time, split by 10 m
wind speed.
"""
function wind_climate_figure()
    times = 0.0:24.0:(WindShipOpt.duration(weather) - 24)
    names = ["caribbean", "new_york", "bilbao", "dakar", "houston", "tubarao"]
    speed_classes = [0, 5, 10, 15, Inf]
    class_labels = ["< 5 m/s", "5–10 m/s", "10–15 m/s", "> 15 m/s"]
    colours = Makie.resample_cmap(:Blues, 6)[2:5]
    edges = 0:15:180
    rings = [5, 10, 15]
    figure = Figure(size=(column_width, 560))
    for (k, name) in enumerate(names)
        axis = Axis(figure[(k - 1) ÷ 2 + 1, (k - 1) % 2 + 1]; aspect=DataAspect(),
            title=route_label(name),
            titlealign=:center, limits=(-19, 19, -19, 19))
        hidedecorations!(axis)
        hidespines!(axis)
        for radius in rings
            arc = range(0, 2π; length=90)
            lines!(axis, radius .* sin.(arc), radius .* cos.(arc); color=:gray80,
                linewidth=0.5)
        end
        lines!(axis, [0, 0], [-16, 16]; color=:gray60, linewidth=0.5)
        for (side, corridor) in zip((-1, 1), run_corridors(Symbol(name)))
            angles, speeds = track_wind(corridor, weather, times)
            for i in 1:(length(edges) - 1)
                inside = edges[i] .<= angles .< edges[i + 1]
                radius = 0.0
                for class_index in 1:(length(speed_classes) - 1)
                    share = 100 * count(inside .& (speed_classes[class_index] .<= speeds .<
                                                   speed_classes[class_index + 1])) /
                            length(angles)
                    sector!(axis, side * deg2rad(edges[i] + 7.5), deg2rad(14), radius,
                        radius + share; color=colours[class_index])
                    radius += share
                end
            end
        end
        text!(axis, [0.0, 0.0, -18.5, 18.5], [16.5, -16.5, -17.5, -17.5];
            text=["head wind", "astern", "out", "home"], fontsize=8.5,
            align=[(:center, :bottom), (:center, :top), (:left, :center),
                (:right, :center)], color=:gray30)
        k == 1 && text!(axis, Float64.(rings) .* sind(135), Float64.(rings) .*
                                                                 cosd(135);
            text=["$radius %" for radius in rings], fontsize=8.5, color=:gray50,
            align=(:left, :top))
    end
    Legend(figure[4, 1:2], [PolyElement(color=colour) for colour in colours], class_labels,
        "wind at 10 m"; framevisible=false, labelsize=9, titlesize=9,
        orientation=:horizontal, nbanks=2, patchsize=(8, 8), tellwidth=false)
    save(joinpath(figures, "wind_climate.pdf"), figure; pt_per_unit=print_scale)
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
    figure = Figure(size=(page_width, 440))
    names = ["caribbean", "new_york", "bilbao", "dakar", "houston", "tubarao"]
    kinds = ["kite", "wings", "rotors"]
    for (row, (drive, drive_label)) in enumerate(drive_labels),
        (column, ship_length) in enumerate((85.0, 140.0, 200.0))

        axis = Axis(figure[row, column]; title="$drive_label, $(round(Int, ship_length)) m",
            xticks=(eachindex(names), route_label.(names)), xticklabelrotation=π / 4,
            ylabel=column == 1 ? "cost saving [%]" : "")
        hlines!(axis, 0; color=:gray, linewidth=0.5)
        for (j, kind) in enumerate(kinds), (i, name) in enumerate(names)
            savings = rig_savings(routes_table, (kind,), "route" => name, "drive" => drive,
                "length" => ship_length)
            haskey(savings, kind) || continue
            barplot!(axis, [i + (j - 2) * 0.27], [savings[kind]]; width=0.25,
                color=palette[j], label=i == 1 ? kind : nothing)
        end
        row < length(drive_labels) && hidexdecorations!(axis; grid=false, ticks=false)
    end
    Legend(figure[length(drive_labels) + 1, 1:3],
        [PolyElement(color=palette[j]) for j in eachindex(kinds)], kinds;
        orientation=:horizontal, framevisible=false, labelsize=9, patchsize=(8, 8))
    save(joinpath(figures, "route_comparison.pdf"), figure; pt_per_unit=print_scale)
end

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
    premium_figure()

Share of the cost premium of an e-methanol and a hydrogen ship over a VLSFO ship without
a rig that the best size of each rig closes, over ship length on the route to Guadeloupe.
"""
function premium_figure()
    designs = read_table(data_file("designs.csv"))
    figure = Figure(size=(column_width, 300))
    axis = Axis(figure[1, 1]; xlabel="waterline length [m]", xticks=85:25:200,
        ylabel="fuel premium closed [%]")
    hlines!(axis, [0, 100]; color=:gray70, linewidth=0.5)
    lengths = sort(unique(designs["length"]))
    for (drive, linestyle) in (("methanol", :solid), ("hydrogen", :dash)),
        (k, (label, column_name)) in enumerate(rig_area_columns)

        shares = [premium_closed(designs, drive, length, column_name) for length in lengths]
        valid = isfinite.(shares)
        scatterlines!(axis, lengths[valid], shares[valid]; color=palette[k], linestyle,
            label="$label, $(Dict(drive_labels)[drive])", markersize=6)
    end
    Legend(figure[2, 1], axis; orientation=:horizontal, nbanks=3, framevisible=false,
        labelsize=9)
    save(joinpath(figures, "premium.pdf"), figure; pt_per_unit=print_scale)
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
rig, and on e-methanol and hydrogen without a rig and with the cheapest size of each rig.
"""
function breakdown_figure()
    designs = read_table(data_file("designs.csv"))
    parts = ["fuel_cost", "wear_cost", "port_cost", "crew_cost", "capital_cost",
        "interest_cost"]
    names = ["fuel", "kite wear", "port", "crew", "capital and maintenance",
        "cargo interest"]
    labels = String[]
    values = Matrix{Float64}(undef, 0, length(parts))
    cases = Tuple{String, String, Union{Nothing, String}}[("VLSFO", "vlsfo", nothing)]
    for (label, drive) in (("e-meth.", "methanol"), ("hydrogen", "hydrogen"))
        push!(cases, (label, drive, nothing))
        for (rig, column) in rig_area_columns
            push!(cases, ("$label + $rig", drive, column))
        end
    end
    for length in (85.0, 200.0)
        for (label, drive, column) in cases
            k = cheapest_design(designs, drive, length, column)
            isnothing(k) && continue
            size = isnothing(column) ? "" : " $(round(Int, designs[column][k])) m²"
            push!(labels, "$label$size, $(round(Int, length)) m")
            values = vcat(values, [designs[part][k] for part in parts]')
        end
    end
    figure = Figure(size=(column_width, 560))
    axis = Axis(figure[1, 1]; yticks=(eachindex(labels), labels), yreversed=true,
        xlabel="cost [USD per 1000 tkm]", yticklabelsize=8.5)
    positions = repeat(eachindex(labels), outer=length(parts))
    stack = repeat(eachindex(parts), inner=length(labels))
    barplot!(axis, positions, 1e3 .* vec(values); stack, direction=:x,
        color=palette[stack])
    Legend(figure[2, 1], [PolyElement(color=palette[i]) for i in eachindex(parts)], names;
        framevisible=false, orientation=:horizontal, nbanks=3, labelsize=9,
        patchsize=(8, 8))
    save(joinpath(figures, "breakdown.pdf"), figure; pt_per_unit=print_scale)
end

"""
    capital_figure()

Capital of an 85 m and a 170 m ship split into the hull with its basic drive, the extra
cost of a diesel-electric e-methanol drive, and the rig.
"""
function capital_figure()
    cases = [("VLSFO", :vlsfo, (;)), ("e-methanol", :methanol, (;)),
        ("+ kite 1600 m²", :methanol, (kite_area=1600.0,)),
        ("+ wings 800 m²", :methanol, (wing_area=800.0,)),
        ("+ rotors 400 m²", :methanol, (rotor_area=400.0,))]
    labels = String[]
    values = Matrix{Float64}(undef, 0, 3)
    for length in (85.0, 170.0)
        basic = WindShipOpt.ShipCosts(Ship(ShipDesign(:vlsfo, length), assumptions),
            assumptions).capital
        electric = WindShipOpt.ShipCosts(Ship(ShipDesign(:methanol, length), assumptions),
            assumptions).capital
        for (label, drive, rig) in cases
            capital = WindShipOpt.ShipCosts(Ship(ShipDesign(drive, length; rig...),
                assumptions), assumptions).capital
            premium = drive == :vlsfo ? 0.0 : electric - basic
            push!(labels, "$label, $(round(Int, length)) m")
            values = vcat(values, [basic premium capital - basic - premium] ./ 1e6)
        end
    end
    figure = Figure(size=(column_width, 318))
    axis = Axis(figure[1, 1]; yticks=(eachindex(labels), labels), yreversed=true,
        xlabel="capital [million USD]", yticklabelsize=9, limits=((0, 50), nothing))
    positions = repeat(eachindex(labels), outer=3)
    stack = repeat(1:3, inner=length(labels))
    barplot!(axis, positions, vec(values); stack, direction=:x, color=palette[stack])
    names = ["hull and basic drive", "e-methanol drive", "rig"]
    axislegend(axis, [PolyElement(color=palette[i]) for i in 1:3], names;
        position=:rt, framevisible=false, labelsize=9, patchsize=(7, 7))
    save(joinpath(figures, "capital.pdf"), figure; pt_per_unit=print_scale)
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

"legend entries of the best size of each rig, a line with markers for the kite"
rig_entries() = [[LineElement(color=palette[1], linewidth=1.3),
        MarkerElement(color=palette[1], marker=:circle, markersize=5)],
    LineElement(color=palette[2], linewidth=1.3), LineElement(color=palette[3],
        linewidth=1.3)]

"""
Panels of the situation figure as (title, x label, inputs with their drive, scale of the
x axis, factor from value to axis, x ticks); the fuel panel joins VLSFO and e-methanol
prices.
"""
situation_panels = [
    ("fuel price", "fuel price [USD/GJ]",
        [(:vlsfo_price, :vlsfo), (:e_methanol_price, :methanol)], log10, 1.0,
        [8, 15, 30, 60, 120]),
    ("cargo value", "cargo value [1000 USD/t]", [(:cargo_value, :methanol)], log10, 1e-3,
        ([1, 2.5, 5, 10, 20], ["1", "2.5", "5", "10", "20"])),
    ("discount rate", "discount rate [%]", [(:discount_rate, :methanol)], identity, 100.0,
        Makie.automatic),
    ("wing life", "wing life [years]", [(:wing_lifetime, :methanol)], identity, 1.0,
        Makie.automatic),
    ("wing price", "wing price [× base]", [(:wing_price, :methanol)], identity, 1.0,
        Makie.automatic),
    ("rotor speed", "highest surface speed [m/s]",
        [(:rotor_max_surface_speed, :methanol)], identity, 1.0, Makie.automatic)]

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

Cost saving of the best size of each rig on the 140 m e-methanol ship to Guadeloupe
(solid) and a Kamsarmax to Tubarão (dashed) with one input changed at a time, the fuel
price on VLSFO below 30 USD/GJ and on e-methanol above; the dashed grey lines show the
base inputs. Prints where the lead changes.
"""
function situations_figure()
    table = read_table(data_file("situations.csv"))
    figure = Figure(size=(page_width, 400))
    for (k, (title, xlabel, inputs, scale, factor, xticks)) in enumerate(situation_panels)
        bases = join([@sprintf("%.3g", factor * base_value(input))
                      for (input, _) in inputs], " / ")
        axis = Axis(figure[(k - 1) ÷ 4 + 1, (k - 1) % 4 + 1];
            title="($('a' + k - 1)) $title, base $bases", xlabel, xscale=scale, xticks,
            titlesize=9.5,
            ylabel=(k - 1) % 4 == 0 ? "cost saving [%]" : "", xticklabelsize=8.5)
        hlines!(axis, 0; color=:gray50, linewidth=0.6)
        for (ship, route, linestyle) in situation_ships, (input, drive) in inputs
            studied(ship, route, drive, input) || continue
            values, savings = situation_savings(table, ship, route, drive, input)
            x = factor .* values
            inverse = scale == log10 ? exp10 : identity
            print_leaders(ship, input, scale.(x), savings, value -> inverse(value) / factor)
            ship == "140 m" && vlines!(axis, factor * base_value(input); color=:gray40,
                linestyle=(:dash, :loose), linewidth=0.9)
            for rig in 1:3
                lines!(axis, x, savings[rig, :]; color=palette[rig], linestyle,
                    linewidth=1.3)
                linestyle == :solid && scatter!(axis, x, savings[rig, :];
                    color=palette[rig], markersize=4)
            end
        end
    end
    Legend(figure[2, 4],
        [rig_entries(),
            [LineElement(color=:black, linestyle=style, linewidth=1.1)
             for style in (:solid, (:dash, :loose))],
            [LineElement(color=:gray40, linestyle=(:dash, :loose), linewidth=0.9)]],
        [["kite", "wings", "rotors"], ["140 m, Guadeloupe", "Kamsarmax, Tubarão"],
            ["base value"]],
        ["best size of each rig", "ship", ""]; framevisible=false,
        labelsize=9, titlesize=9, rowgap=2, patchsize=(14, 8), tellheight=false)
    save(joinpath(figures, "situations.pdf"), figure; pt_per_unit=print_scale)
end

"""
    aspect_figure()

Saving of the kite of each study ship against its aspect ratio, at the same area and the
same price.
"""
function aspect_figure()
    table = read_table(data_file("aspect.csv"))
    figure = Figure(size=(column_width, 190))
    axis = Axis(figure[1, 1]; xlabel="kite aspect ratio", ylabel="cost saving [%]",
        xticks=collect(study_aspect_ratios))
    for (k, ship) in enumerate(unique(table["ship"]))
        chosen = rows(table, "ship" => ship)
        bare = table["cost"][only(filter(row -> table["aspect_ratio"][row] == 0, chosen))]
        kites = filter(row -> table["aspect_ratio"][row] > 0, chosen)
        savings = percent_saving.(table["cost"][kites], bare)
        scatterlines!(axis, table["aspect_ratio"][kites], savings; color=palette[k],
            markersize=5, linewidth=1.3, label=ship)
    end
    axislegend(axis; position=:rb, framevisible=false, labelsize=8.5)
    save(joinpath(figures, "aspect.pdf"), figure; pt_per_unit=print_scale)
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
140 m e-methanol ship on every route: (a) share of time at sea of the ship without a rig
in each true-wind-angle band, outbound and homeward; (b) mean thrust of the reference
size of each rig in each band over all routes; (c) share of each rig's propulsive work
from each band per route; (d) mean thrust over the rig's cost per day at sea.
"""
function wind_angle_figure()
    table = read_table(data_file("wind_angle.csv"))
    names = ["caribbean", "new_york", "bilbao", "dakar", "houston", "tubarao"]
    rigs = [(rig, round(Int, area)) for (rig, area) in reference_rigs]
    figure = Figure(size=(page_width, 380))
    ticks = (eachindex(names), route_label.(names))
    time_axis = Axis(figure[1, 1]; title="(a) time at sea without a rig, out | home",
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
    ylims!(thrust_axis, 0, 1.4highest)
    work_axis = Axis(figure[2, 1]; title="(c) rig work by band: kite | wings | rotors",
        ylabel="share of work [%]", xticks=ticks, xticklabelrotation=π / 6)
    cost_axis = Axis(figure[2, 2]; title="(d) mean thrust per rig cost",
        ylabel="kN per 1000 USD/day", xticks=ticks, xticklabelrotation=π / 6)
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
         for (name, low, high) in angle_bands]; orientation=:horizontal,
        framevisible=false, labelsize=9, patchsize=(8, 8))
    axislegend(thrust_axis, [PolyElement(color=palette[j]) for j in eachindex(rigs)],
        ["$rig $area m²" for (rig, area) in rigs]; position=:lt, framevisible=false,
        labelsize=9, patchsize=(8, 8))
    save(joinpath(figures, "wind_angle.pdf"), figure; pt_per_unit=print_scale)
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

Cost per tonne-km against the fuel energy saved for every size of each rig on the ships
of the abatement study, relative to the same ship on VLSFO without a rig, one column per
drive.
"""
function abatement_figure()
    table = read_table(data_file("abatement.csv"))
    figure = Figure(size=(page_width, 360))
    for (row, (name, _)) in enumerate(abatement_ships),
        (column, (drive, label)) in enumerate(drive_labels)

        fossil = only(table["cost"][rows(table, "ship" => name, "drive" => "vlsfo",
            "rig" => "none")])
        bare = only(rows(table, "ship" => name, "drive" => drive, "rig" => "none"))
        letter = 'a' + length(drive_labels) * (row - 1) + column - 1
        axis = Axis(figure[row, column]; title="($letter) $name, $label",
            xlabel=row == 2 ? "fuel energy saved [%]" : "",
            ylabel=column == 1 ? "cost vs VLSFO, no rig [%]" : "")
        hlines!(axis, 0; color=:gray50, linewidth=0.6)
        scatter!(axis, [0.0], [100 * (table["cost"][bare] / fossil - 1)]; color=:black,
            markersize=6)
        for (k, rig) in enumerate(rig_names)
            chosen = rows(table, "ship" => name, "drive" => drive, "rig" => rig)
            chosen = chosen[sortperm(table["area"][chosen])]
            saved = 100 .* (1 .- table["fuel"][chosen] ./ table["fuel"][bare])
            change = 100 .* (table["cost"][chosen] ./ fossil .- 1)
            scatterlines!(axis, saved, change; color=palette[k], markersize=4,
                linewidth=1.3)
        end
    end
    entries = [[MarkerElement(color=:black, marker=:circle, markersize=6)];
        [[LineElement(color=palette[k], linewidth=1.3),
             MarkerElement(color=palette[k], marker=:circle, markersize=4)] for k in 1:3]]
    Legend(figure[3, 1:length(drive_labels)], entries,
        ["no rig", "kite", "wings", "rotors"];
        orientation=:horizontal, framevisible=false, labelsize=9)
    save(joinpath(figures, "abatement.pdf"), figure; pt_per_unit=print_scale)
end

"""
    sensitivity_figure()

Cost saving of each rig on the 140 m e-methanol reference ship at the low and high bound
of the twelve inputs that move it most, as a tornado around the base saving.
"""
function sensitivity_figure()
    table = read_table(data_file("sensitivity.csv"))
    figure = Figure(size=(page_width, 320))
    for (column, rig) in enumerate(rig_names)
        base = screened_saving(table, "140 m", rig, "none", "value")
        swings = [(input, screened_saving(table, "140 m", rig, input, "low"),
                      screened_saving(table, "140 m", rig, input, "high"))
                  for input in filter(!=("none"), unique(table["input"]))]
        filter!(swing -> all(isfinite, swing[2:3]), swings)
        sort!(swings; by=swing -> abs(swing[3] - swing[2]))
        swings = last(swings, 12)
        axis = Axis(figure[1, column]; title="($('a' + column - 1)) $rig",
            yticks=(eachindex(swings), [replace(first(swing), "_" => " ")
                                        for swing in swings]),
            xlabel="cost saving [%]", yticklabelsize=8)
        vlines!(axis, base; color=:gray50, linewidth=0.8)
        for (k, (_, low, high)) in enumerate(swings)
            barplot!(axis, [k], [low - base]; offset=base, direction=:x, color=palette[1],
                width=0.6)
            barplot!(axis, [k], [high - base]; offset=base, direction=:x, color=palette[2],
                width=0.6)
        end
    end
    Legend(figure[2, 1:3], [PolyElement(color=palette[1]), PolyElement(color=palette[2])],
        ["input at low bound", "input at high bound"]; orientation=:horizontal,
        framevisible=false, labelsize=9)
    save(joinpath(figures, "sensitivity.pdf"), figure; pt_per_unit=print_scale)
end

"""
    component_figure()

Change in the cost saving of each rig on a 140 m e-methanol ship when the price of one
of its components is 50 % lower or higher, or one of its lifetimes doubled or halved.
"""
function component_figure()
    table = read_table(data_file("components.csv"))
    bare = only(table["cost"][rows(table, "rig" => "none")])
    figure = Figure(size=(page_width, 260))
    for (column, rig) in enumerate(rig_names)
        base_cost = only(table["cost"][rows(table, "rig" => rig, "input" => "none")])
        base = percent_saving(base_cost, bare)
        inputs = filter(!=("none"), unique(table["input"][rows(table, "rig" => rig)]))
        effects = Tuple{String, Float64, Float64}[]
        for input in inputs
            chosen = rows(table, "rig" => rig, "input" => input)
            better = minimum(table["cost"][chosen])
            worse = maximum(table["cost"][chosen])
            push!(effects, (input, percent_saving(better, bare) - base,
                percent_saving(worse, bare) - base))
        end
        sort!(effects; by=effect -> effect[2])
        labels = [replace(first(effect), "_" => " ") for effect in effects]
        title = "($('a' + column - 1)) $rig, base $(round(base; digits=1)) %"
        axis = Axis(figure[1, column]; title, yticks=(eachindex(effects), labels),
            xlabel="change in cost saving [points]", yticklabelsize=8)
        vlines!(axis, 0; color=:gray50, linewidth=0.8)
        barplot!(axis, eachindex(effects), getindex.(effects, 2); direction=:x,
            color=palette[3], width=0.6)
        barplot!(axis, eachindex(effects), getindex.(effects, 3); direction=:x,
            color=palette[6], width=0.6)
    end
    Legend(figure[2, 1:3], [PolyElement(color=palette[3]), PolyElement(color=palette[6])],
        ["50 % cheaper or twice the life", "50 % dearer or half the life"];
        orientation=:horizontal, framevisible=false, labelsize=9)
    save(joinpath(figures, "components.pdf"), figure; pt_per_unit=print_scale)
end

"""
    forecast_figure()

Cost saving of each rig on a 140 m e-methanol ship routed with perfect foresight and
with daily re-planning on forecasts of 7 and 3 days. A case with no feasible round trip,
its ship's or the bare ship's, is marked "none" in place of its bar.
"""
function forecast_figure()
    table = read_table(data_file("forecast.csv"))
    horizons = [(0.0, "perfect"), (7.0, "7 days"), (3.0, "3 days")]
    figure = Figure(size=(column_width, 240))
    axis = Axis(figure[1, 1]; xticks=(1:3, ["kite", "wings", "rotors"]),
        ylabel="cost saving [%]")
    for (j, (days, label)) in enumerate(horizons)
        bare = forecast_cost(table, "none", days)
        savings = [100 * (1 - forecast_cost(table, rig, days) / bare) for rig in rig_names]
        positions = (1:3) .+ (j - 2) * 0.27
        routed = isfinite.(savings)
        barplot!(axis, positions[routed], savings[routed]; width=0.25,
            color=palette[j], label)
        unrouted = count(.!routed)
        text!(axis, positions[.!routed], zeros(unrouted); text=fill("none", unrouted),
            rotation=pi / 2, align=(:left, :center), fontsize=8, color=palette[j])
    end
    Legend(figure[2, 1], axis, "forecast"; orientation=:horizontal, framevisible=false,
        labelsize=9, titleposition=:left)
    save(joinpath(figures, "forecast.pdf"), figure; pt_per_unit=print_scale)
end

"""
    forecast_cost(table, rig, days)

Cost per tonne-km of `rig` at forecast horizon `days` in the forecast table, `NaN` where
the case has no feasible round trip.
"""
function forecast_cost(table, rig, days)
    costs = table["cost"][rows(table, "rig" => rig, "horizon_days" => days)]
    return isempty(costs) ? NaN : only(costs)
end

"rigs of the combination figure with their legend labels and colours"
combination_rigs = (("kite", "best kite", palette[1]),
    ("rotors", "best rotors", palette[3]),
    ("kite+rotors", "best kite and rotors together", palette[4]))

"""
    combination_figure()

Cost saving against no rig of the best kite, the best rotors and the best pair of both
on each ship and drive of the combination study, and the combination's saving over the
better single rig, each as the mean over the routes with the range of the routes.
Prints the means and the share of the summed single-rig savings the combination keeps.
"""
function combination_figure()
    table = read_table(data_file("combination.csv"))
    groups = vec([(ship, drive) for drive in ("vlsfo", "methanol"),
                  ship in combination_ships])
    labels = ["$(replace(ship, " bulk carrier" => ""))\n$(Dict(drive_labels)[drive])"
              for (ship, drive) in groups]
    figure = Figure(size=(page_width, 310))
    saving_axis = Axis(figure[1, 1]; title="(a) cost saving vs no rig",
        ylabel="cost saving [%]")
    gain_axis = Axis(figure[2, 1]; title="(b) combination over the better single rig",
        xticks=(eachindex(groups), labels), ylabel="extra saving [% points]")
    linkxaxes!(saving_axis, gain_axis)
    hidexdecorations!(saving_axis)
    rowsize!(figure.layout, 2, Relative(0.4))
    for (group, (ship, drive)) in enumerate(groups)
        savings = [rig_savings(table, first.(combination_rigs), "ship" => ship,
                       "route" => string(route), "drive" => drive)
                   for route in route_names]
        for (k, (rig, _, colour)) in enumerate(combination_rigs)
            values = [saving[rig] for saving in savings]
            range_bar!(saving_axis, group + 0.27(k - 2), values, 0.25, colour)
        end
        gains = [saving["kite+rotors"] - max(saving["kite"], saving["rotors"])
                 for saving in savings]
        range_bar!(gain_axis, group, gains, 0.4, palette[4])
        print_combination(ship, drive, savings, gains)
    end
    for axis in (saving_axis, gain_axis)
        hlines!(axis, 0; color=:gray50, linewidth=0.6)
    end
    entries = [PolyElement(color=colour) for (_, _, colour) in combination_rigs]
    Legend(figure[3, 1], entries, collect(getindex.(combination_rigs, 2));
        orientation=:horizontal, framevisible=false, labelsize=9, patchsize=(12, 8))
    save(joinpath(figures, "combination.pdf"), figure; pt_per_unit=print_scale)
end

"""
    range_bar!(axis, x, values, width, colour)

Bar of `width` at `x` to the mean of `values` with a range bar from their least to their
largest.
"""
function range_bar!(axis, x, values, width, colour)
    barplot!(axis, [x], [mean(values)]; width, color=colour)
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
    figure = Figure(size=(page_width, 560))
    panels = (("fuel saved [%]", "free", :fuel_percent),
        ("fuel saved [GJ/round trip]", "free", :fuel), ("cost saved [%]", "priced",
            :cost_percent))
    designs = [(grid, string(drive)) for grid in speed_size_grid for drive in grid.drives]
    for (row, (grid, drive)) in enumerate(designs)
        shades = cgrad(:Blues, length(grid.kites) + 2; categorical=true)
        for (column, (label, pricing, quantity)) in enumerate(panels)
            letter = Char('a' + length(panels) * (row - 1) + column - 1)
            design = column == 1 ? " $(grid.ship), $(Dict(drive_labels)[drive])" : ""
            axis = Axis(figure[row, column]; title="($letter)$design",
                xlabel="ship speed [kn]", ylabel=label, xticks=collect(grid.speeds))
            for (k, area) in enumerate(grid.kites)
                savings = [speed_size_saving(table, grid.ship, drive, "kite", area, pricing,
                               knots) for knots in grid.speeds]
                held = findall(!isnothing, savings)
                scatterlines!(axis, collect(grid.speeds)[held],
                    [getproperty(savings[i], quantity) for i in held]; color=shades[k + 2],
                    markercolor=shades[k + 2], linewidth=2, markersize=8,
                    label=string(round(Int, area), " m²"))
            end
            column == length(panels) &&
                Legend(figure[row, column + 1], axis; framevisible=false, labelsize=9)
        end
    end
    save(joinpath(figures, "speed_size.pdf"), figure; pt_per_unit=print_scale)
end

"""
    rigid_scaling_figure()

Beam thrust of rigid kites and a soft kite over apparent wind, and price and annual cost per
unit of thrust at 12 m/s over area for the mass exponents of the scaling study. Prints the
scaling table.
"""
function rigid_scaling_figure()
    table = read_table(data_file("rigid_scaling.csv"))
    figure = Figure(size=(page_width, 270))
    thrust_axis = Axis(figure[1, 1]; title="(a) one kite on a beam course",
        xlabel="apparent wind [m/s]", ylabel="thrust [kN]")
    price_axis = Axis(figure[1, 2]; title="(b) price at 12 m/s", xscale=log10,
        xticks=[30, 300, 3000], xlabel="kite area [m²]", ylabel="price per thrust [USD/kN]")
    annual_axis = Axis(figure[1, 3]; title="(c) cost a year at 12 m/s", xscale=log10,
        xticks=[30, 300, 3000], xlabel="kite area [m²]", ylabel="annual cost per thrust [USD/kN]")
    base_exponent = assumptions[:rigid_mass_exponent]
    curves = (("rigid", 30.0), ("rigid", 54.0), ("rigid", 100.0), ("rigid", 300.0),
        ("soft", 1000.0))
    for (k, (kind, area)) in enumerate(curves)
        exponent = kind == "rigid" ? base_exponent : 0.0
        chosen = rows(table, "kind" => kind, "area" => area, "exponent" => exponent)
        lines!(thrust_axis, table["wind"][chosen], 1e-3 .* table["thrust"][chosen];
            color=palette[k], label="$kind $(round(Int, area)) m²")
    end
    series = [("rigid", base_exponent, :solid), ("rigid", 3.0, :dash), ("rigid", 3.3, :dot),
        ("soft", 0.0, :solid)]
    for (kind, exponent, linestyle) in series
        at_twelve = filter(row -> table["thrust"][row] > 0,
            rows(table, "kind" => kind, "exponent" => exponent, "wind" => 12.0))
        areas, prices = table["area"][at_twelve], table["price"][at_twelve]
        per_thrust = 1e3 .* prices ./ table["thrust"][at_twelve]
        annual_per_thrust = 1e3 .* table["annual"][at_twelve] ./ table["thrust"][at_twelve]
        label = kind == "soft" ? "soft kite" : "rigid, mass ∝ span^$exponent"
        colour = kind == "soft" ? palette[5] : palette[1]
        lines!(price_axis, areas, per_thrust; linestyle, label, color=colour)
        lines!(annual_axis, areas, annual_per_thrust; linestyle, color=colour)
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
    for (row, axis) in enumerate((thrust_axis, price_axis))
        Legend(figure[row + 1, 1:3], axis; orientation=:horizontal, framevisible=false,
            labelsize=8)
        rowsize!(figure.layout, row + 1, Fixed(16))
    end
    save(joinpath(figures, "rigid_scaling.pdf"), figure; pt_per_unit=print_scale)
end

"lines of the rigid size figure with the column selecting their fleets"
rigid_size_lines = (("one wing", "count" => 1.0), ("30 m² each", "unit" => 30.0),
    ("54 m² each", "unit" => 54.0), ("100 m² each", "unit" => 100.0))

"""
    rigid_size_figure()

Cost saving against no rig over the total area of rigid kites on each ship on VLSFO, as the
mean over the routes, one line per area of a kite and one for a single wing of any area,
solid for the base mass law and dashed for span cubed. Prints every fleet by saving.
"""
function rigid_size_figure()
    table = read_table(data_file("rigid_kite.csv"))
    figure = Figure(size=(page_width, 230))
    for (k, ship) in enumerate(combination_ships)
        axis = Axis(figure[1, k]; title=ship, xscale=log10, xlabel="total area [m²]",
            ylabel=k == 1 ? "cost saving [%]" : "")
        for (scenario, linestyle) in (("rigid base", :solid), ("rigid cubic", :dash))
            print_rigid_sizes(table, ship, scenario)
            for (colour, (label, fleets)) in enumerate(rigid_size_lines)
                points = sort(fleet_savings(table, ship, scenario, fleets))
                lines!(axis, getindex.(points, 1), getindex.(points, 2); linestyle, label,
                    color=palette[colour])
            end
        end
        k == 1 && axislegend(axis; unique=true, position=:lb, framevisible=false,
            labelsize=8)
    end
    save(joinpath(figures, "rigid_size.pdf"), figure; pt_per_unit=print_scale)
end

"""
    fleet_savings(table, ship, scenario, fleets)

(total area [m^2], mean saving [%] over the routes on VLSFO, kites, area of each [m^2]) of
the rows of `scenario` on `ship` that the column pair `fleets` selects, those flown on
every route.
"""
function fleet_savings(table, ship, scenario, fleets)
    chosen = rows(table, "ship" => ship, "drive" => "vlsfo", "rig" => scenario, fleets)
    points = NTuple{4, Float64}[]
    for (count, unit) in unique(zip(table["count"][chosen], table["unit"][chosen]))
        savings = Float64[]
        for route in route_names
            filters = ("ship" => ship, "route" => string(route), "drive" => "vlsfo")
            bare = table["cost"][only(rows(table, filters..., "rig" => "none"))]
            fleet = rows(table, filters..., "rig" => scenario, "unit" => unit,
                "count" => count)
            isempty(fleet) || push!(savings, 100 * (1 - table["cost"][only(fleet)] / bare))
        end
        length(savings) == length(route_names) || continue
        push!(points, (count * unit, mean(savings), count, unit))
    end
    return points
end

"""
    print_rigid_sizes(table, ship, scenario)

Print the mean saving [%] over the routes on VLSFO of every fleet of `scenario` on `ship`,
best first.
"""
function print_rigid_sizes(table, ship, scenario)
    println("  $ship, $scenario:")
    fleets = fleet_savings(table, ship, scenario, "rig" => scenario)
    for (_, saving, count, unit) in sort(fleets; by=point -> -point[2])
        @printf("    %.0f x %.0f m²: %.2f %%\n", count, unit, saving)
    end
end

"rigs of the rigid kite figure with their legend labels and colours"
rigid_kite_rigs = (("kite", "best soft kite", palette[1]),
    ("wings", "best wings", palette[2]),
    ("rotors", "best rotors", palette[3]), ("rigid base", "best rigid kites", palette[4]),
    ("rigid optimistic", "best rigid kites, favourable inputs", palette[5]))

"""
    rigid_kite_figure()

Cost saving against no rig of the best size of each rig of `rigid_kite_rigs` on each ship
and drive of the rigid kite study, as the mean over the routes with the range of the
routes. Prints the means and the rigid fleets each scenario prefers.
"""
function rigid_kite_figure()
    table = read_table(data_file("rigid_kite.csv"))
    groups = vec([(ship, drive) for drive in ("vlsfo", "methanol"),
                  ship in combination_ships])
    figure = Figure(size=(page_width, 240))
    axis = Axis(figure[1, 1]; ylabel="cost saving [%]",
        xticks=(eachindex(groups),
            ["$(replace(ship, " bulk carrier" => ""))\n$(Dict(drive_labels)[drive])"
             for (ship, drive) in groups]))
    names = first.(rigid_kite_rigs)
    for (group, (ship, drive)) in enumerate(groups)
        savings = [rig_savings(table, names, "ship" => ship, "route" => string(route),
                       "drive" => drive) for route in route_names]
        for (k, (rig, _, colour)) in enumerate(rigid_kite_rigs)
            range_bar!(axis, group + 0.17(k - 3), [saving[rig] for saving in savings], 0.15,
                colour)
        end
        print_rigid_kite(table, ship, drive, savings)
    end
    hlines!(axis, 0; color=:gray50, linewidth=0.6)
    Legend(figure[2, 1], [PolyElement(color=colour) for (_, _, colour) in rigid_kite_rigs],
        collect(getindex.(rigid_kite_rigs, 2)); orientation=:horizontal, nbanks=2,
        framevisible=false, labelsize=9, patchsize=(12, 8))
    save(joinpath(figures, "rigid_kite.pdf"), figure; pt_per_unit=print_scale)
end

"""
    print_rigid_kite(table, ship, drive, savings)

Print for one ship and drive the mean saving [%] of each rig over the routes, the routes on
which rigid kites lead and the most frequent best fleet of each scenario.
"""
function print_rigid_kite(table, ship, drive, savings)
    @printf("  %s, %s:", ship, drive)
    for (rig, _, _) in rigid_kite_rigs
        @printf(" %s %.1f (%.1f to %.1f) %%,", rig, mean(saving[rig] for saving in savings),
            extrema(saving[rig] for saving in savings)...)
    end
    println()
    for scenario in ("rigid base", "rigid optimistic")
        best = map(route_names) do route
            chosen = rows(table, "ship" => ship, "drive" => drive, "route" => string(route),
                "rig" => scenario)
            row = chosen[argmin(table["cost"][chosen])]
            "$(round(Int, table["count"][row])) x $(round(Int, table["unit"][row]))"
        end
        leads = count(saving -> saving[scenario] > maximum(saving[rig]
                for rig in ("kite", "wings", "rotors")), savings)
        println("    $scenario: best fleets ", join(best, ", "), "; leads on ", leads,
            " of ", length(route_names), " routes")
    end
end
