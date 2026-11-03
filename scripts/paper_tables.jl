# Table steps of the paper, written as LaTeX to paper/sections/: the inputs of
# data/assumptions.yaml that matter ranked by effect, the ship classes from
# data/ship_classes.csv, the fuel saving and payback of each rig, the goals and what
# missing one costs. Included by paper.jl.

"""
    latex_escape(text)

`text` with the characters LaTeX treats specially escaped and powers set as superscripts.
"""
latex_escape(text) = replace(text, "\\" => "\\textbackslash{}", "&" => "\\&", "%" => "\\%",
    "\$" => "\\\$", "#" => "\\#", "_" => "\\_", "~" => "\\textasciitilde{}",
    ">=" => "\\ensuremath{\\geq}", "<=" => "\\ensuremath{\\leq}", ">" => "\\textgreater{}",
    "<" => "\\textless{}", r"\^(-?\d)" => s"\\textsuperscript{\1}", "^" => "\\^{}")

"""
    latex_number(value)

`value` as a siunitx number, whole numbers below a million without a decimal point.
"""
latex_number(value) = string("\\num{", isinteger(value) && abs(value) < 1e6 ? Int(value) :
    value, "}")

"""
    input_tables()

Write the inputs that matter, by [`input_effects`](@ref), to
paper/sections/input_tables.tex as one longtable ranked by their effect, with value,
range, unit, effect and source.
"""
function input_tables()
    effects = input_effects()
    ranked = sort(collect(keys(effects)); by=name -> -importance(effects[name]))
    filter!(name -> importance(effects[name]) >= 1, ranked)
    ragged = ">{\\raggedright\\arraybackslash}"
    open(joinpath(sections, "input_tables.tex"), "w") do io
        println(io, "\\begin{longtable}{@{}", ragged, "p{2.4cm}rr", ragged, "p{1.3cm}rr",
            ragged, "p{4.8cm}@{}}")
        println(io, "\\caption{Inputs that matter for the results, ranked by their ",
            "effect on any of the three screened ships: the largest change in the cost ",
            "saving of a rig between the low and high bound, and the largest change in ",
            "the cost of a ship without a rig at either bound.}\n\\label{tab:inputs}\\\\")
        println(io, input_header, "\n\\endfirsthead")
        println(io, "\\multicolumn{7}{@{}l}{\\cref{tab:inputs} (continued)}\\\\")
        println(io, input_header, "\n\\endhead\n\\bottomrule\n\\endfoot")
        for name in ranked
            write_input_row(io, assumptions.entries[name], name, effects[name])
        end
        println(io, "\\end{longtable}")
    end
end

"header rows of the input table"
input_header = "\\toprule\nInput & Value & Range & Unit & Saving & Cost & Source \\\\\n" *
               " & & & & [pt] & [\\%] & \\\\\n\\midrule"

"smallest change of a rig's cost saving [points] that makes an input matter"
saving_threshold = 0.5

"smallest change of the cost of a ship without a rig [%] that makes an input matter"
cost_threshold = 2.0

"""
    importance(effect)

Effect of an input relative to the thresholds; it matters from 1 on.
"""
importance(effect) = max(effect.saving / saving_threshold, effect.cost / cost_threshold)

"""
    screened_cost(table, ship, rig, input, bound)

Costs per tonne-km of the screening `table` rows of `rig` on `ship` with `input` at
`bound`: one value, or none where the trip failed.
"""
screened_cost(table, ship, rig, input, bound) = table["cost"][rows(table, "ship" => ship,
    "rig" => rig, "input" => input, "bound" => bound)]

"""
    screened_saving(table, ship, rig, input, bound)

Cost saving [%] of `rig` on `ship` with `input` at `bound` in the screening `table`,
against the same ship without a rig at the same bound; `NaN` where a trip is missing.
"""
function screened_saving(table, ship, rig, input, bound)
    with_rig = screened_cost(table, ship, rig, input, bound)
    bare = screened_cost(table, ship, "none", input, bound)
    (isempty(with_rig) || isempty(bare)) && return NaN
    return percent_saving(only(with_rig), only(bare))
end

"""
    input_effects()

Effect of each screened input in sensitivity.csv: the largest change between its low
and high bound in the cost saving of a rig [points], and the largest change from the
base in the cost of a ship without a rig [%], over the screened ships.
"""
function input_effects()
    table = read_table(data_file("sensitivity.csv"))
    effects = Dict{Symbol, NamedTuple{(:saving, :cost), Tuple{Float64, Float64}}}()
    for input in filter(!=("none"), unique(table["input"]))
        saving, cost = 0.0, 0.0
        for ship in unique(table["ship"])
            saving = max(saving, saving_change(table, ship, input))
            cost = max(cost, cost_change(table, ship, input))
        end
        effects[Symbol(input)] = (; saving, cost)
    end
    return effects
end

"""
    share_costs(table, ship, rig)

The shares out of service [-] and costs per tonne-km of `rig` on `ship` in the availability
`table`, ascending in the share.
"""
function share_costs(table, ship, rig)
    picked = rows(table, "ship" => ship, "rig" => rig)
    order = sortperm(table["share"][picked])
    return table["share"][picked][order], table["cost"][picked][order]
end

"cost per tonne-km at `share` of the (shares, costs) `curve` of [`share_costs`](@ref)"
curve_cost((shares, costs), share) = costs[findfirst(≈(share), shares)]

"value of the input `name` in years, as a table cell"
years(name) = @sprintf("%.0f years", assumptions[name])

"""
    goal_rows()

The goals behind the results as (goal, rigs, value, what is known today), each value read
from the input that holds it, but for the rigid kite's life, which no input holds.
"""
function goal_rows()
    canopy = @sprintf("\\num{%.0f} h at %.0f g/m\$^2\$", assumptions[:canopy_life],
        assumptions[:canopy_cloth_weight])
    service = @sprintf("%.0f\\,\\%%",
        100only(unique(assumptions[Symbol(out_of_service_inputs[rig])]
                       for rig in rig_names)))
    loss = @sprintf("1 in \\num{%.0f}", 1 / assumptions[:kite_cycle_damage_probability])
    crew = @sprintf("USD~%.0f per cycle", assumptions[:kite_cycle_crew_cost])
    return [("Canopy life", "kite", canopy,
            "derived \\num{3800} h (\\numrange{1200}{6900}), on makers' statements"),
        ("Rig life", "rigid kite", "15 years",
            "M600 flew 22 h of crosswind in all \\citep{echeverri2020part1}"),
        ("Rig life", "wings", years(:wing_lifetime),
            "stated design life; about 2 years on record"),
        ("Rig life", "rotors", years(:rotor_lifetime),
            "stated design life; about 8 years on record"),
        ("Out of service", "all", service,
            "one rotor operator's 97\\,\\%; nothing for kites"),
        ("Crash in flight", "kites", "none",
            string("no record for a ship; M600 lost all four kites in twenty crosswind ",
                "flights, three of them in hover or landing \\citep{echeverri2020part1}")),
        ("Unit lost", "wings, rotors", "none", "none reported, and no duty to report one"),
        ("Lost per launch and landing", "kites", loss,
            "our estimates: 0.2\\,\\% kite, 0.05\\,\\% rigid kite; no record for a ship"),
        ("Launch and landing crew", "kites", crew, "our estimate")]
end

"""
    goals_table()

Write the [`goal_rows`](@ref) to paper/sections/goals_table.tex.
"""
function goals_table()
    open(joinpath(sections, "goals_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}lllp{0.42\\textwidth}@{}}\n\\toprule")
        println(io, "Goal & Rig & Value & Today \\\\\n\\midrule")
        for row in goal_rows()
            println(io, join(row, " & "), " \\\\")
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"canopy life [h] at which `rig` reaches `cost` on the (lives, costs) `curve`; kite only"
kite_life_at_cost(rig, curve, cost) =
    rig == "kite" ? WindShipOpt.life_at_cost(curve..., cost) : NaN

"""
    missed_goal_rows()

For each screened ship and each rig, best first at the goals: cost saving [%], and where it
stops paying and falls behind the next rig (`NaN` for the last) the canopy life [h] and the
share out of service [-], that share also for all units failing together; for the kite its
saving [%] at a canopy life of 2,000 h and the life at which it passes the rig ahead; the
points of saving [%] its share out of service costs at the goal.
"""
function missed_goal_rows()
    service = read_table(data_file("availability.csv"))
    lives = read_table(data_file("canopy_life.csv"))
    result = []
    for ship in unique(service["ship"])
        bare = only(share_costs(service, ship, "none")[2])
        curves = Dict(rig => share_costs(service, ship, rig) for rig in rig_names)
        goal = Dict(rig => curve_cost(curves[rig],
                        assumptions[Symbol(out_of_service_inputs[rig])])
                    for rig in rig_names)
        ranked = sort(collect(rig_names); by=rig -> goal[rig])
        picked = rows(lives, "ship" => ship)
        life_curve = lives["life"][picked], lives["cost"][picked]
        for (rank, rig) in enumerate(ranked)
            curve = curves[rig]
            next_cost = rank < length(ranked) ? goal[ranked[rank + 1]] : NaN
            ahead_cost = rank > 1 ? goal[ranked[rank - 1]] : NaN
            saving_short = rig == "kite" ?
                           percent_saving(curve_cost(life_curve, 2000.0), bare) : NaN
            saving = percent_saving(goal[rig], bare)
            push!(result, (; ship, rig, saving, saving_short,
                service_points=percent_saving(curve[2][1], bare) - saving,
                life=(kite_life_at_cost(rig, life_curve, bare),
                    kite_life_at_cost(rig, life_curve, next_cost)),
                passes=kite_life_at_cost(rig, life_curve, ahead_cost),
                share=(WindShipOpt.share_at_cost(curve..., bare),
                    WindShipOpt.share_at_cost(curve..., next_cost)),
                whole_behind=WindShipOpt.share_at_cost([0.0, 1.0],
                    [curve[2][1], curve[2][end]], next_cost)))
        end
    end
    return result
end

"""
    missed_goals_table()

Write the [`missed_goal_rows`](@ref) to paper/sections/missed_goals_table.tex and print what
the text takes from them besides: the points each rig's outages cost and the life at which
the kite passes the rig ahead.
"""
function missed_goals_table()
    open(joinpath(sections, "missed_goals_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}llrrrrrrr@{}}\n\\toprule")
        println(io, " & & \\multicolumn{2}{c}{Saving [\\%]} & ",
            "\\multicolumn{2}{c}{Canopy life [h] where} & ",
            "\\multicolumn{3}{c}{Out of service [\\%] where} \\\\")
        println(io, "\\cmidrule(lr){3-4}\\cmidrule(lr){5-6}\\cmidrule(lr){7-9}")
        println(io, "Ship & Rig & at goals & at \\num{2000} h & ",
            "pays no more & behind next & pays no more & behind next & all units \\\\")
        println(io, "\\midrule")
        for row in missed_goal_rows()
            cells = [row.ship; row.rig; @sprintf("%.1f", row.saving);
                     dash_cell(row.saving_short, "%.1f"); dash_cell.(row.life, "%.0f")...;
                     share_cell.(row.share)...;
                     share_cell(row.whole_behind)]
            println(io, join(cells, " & "), " \\\\")
            @printf("%s, %s: outages cost %.2f points, passes the next up at %s h\n",
                row.ship, row.rig, row.service_points, dash_cell(row.passes, "%.0f"))
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"`value` in `format`, a dash for `NaN`"
dash_cell(value, format) = isnan(value) ? "--" :
                           Printf.format(Printf.Format(format), value)

share_cell(share) = isnan(share) ? "--" : @sprintf("%.0f", 100share)

"""
    saving_change(table, ship, input)

Largest change in the cost saving of a rig on `ship` [points] between the low and high
bound of `input`, over the rigs with both trips.
"""
function saving_change(table, ship, input)
    change = 0.0
    for rig in rig_names
        swing = abs(screened_saving(table, ship, rig, input, "high") -
                    screened_saving(table, ship, rig, input, "low"))
        isfinite(swing) && (change = max(change, swing))
    end
    return change
end

"""
    cost_change(table, ship, input)

Largest change [%] in the cost of `ship` without a rig at either bound of `input`
against its base cost.
"""
function cost_change(table, ship, input)
    base = only(screened_cost(table, ship, "none", "none", "value"))
    change = 0.0
    for bound in ("low", "high")
        cost = screened_cost(table, ship, "none", input, bound)
        isempty(cost) || (change = max(change, 100abs(only(cost) / base - 1)))
    end
    return change
end

"""
    write_input_row(io, entry, name, effect)

One row of the input table: name, base value, range, unit, effect and the full source
note.
"""
function write_input_row(io, entry, name, effect)
    label = replace(string(name), "_" => " ")
    unit = strip(entry.unit, '"')
    println(io, latex_escape(label), " & ", latex_number(entry.value), " & ",
        latex_number(entry.low), "--", latex_number(entry.high), " & ",
        unit == "-" ? "--" : latex_escape(unit), " & ",
        @sprintf("%.1f", effect.saving), " & ", @sprintf("%.1f", effect.cost), " & ",
        latex_escape(entry.reason), " \\\\")
end

"""
    class_table()

Tabular of the ship classes with their main dimensions, deadweight and unit capacity,
speed, engine power, resistance calibration, price, cargo value and the inputs of deck
cargo and port operations, in class_table.tex, and the rows of their sources in
class_sources.tex; an infinite fixed-rig delay, where a fixed rig prevents cargo handling,
is printed as ∞.
"""
function class_table()
    classes = sort(collect(values(ship_classes())); by=class -> class.deadweight)
    notes = class_source_notes()
    open(joinpath(sections, "class_sources.tex"), "w") do io
        for class in classes
            println(io, latex_escape(class.name), " & ", latex_escape(notes[class.name]),
                " \\\\")
        end
    end
    open(joinpath(sections, "class_table.tex"), "w") do io
        println(io, "\\setlength{\\tabcolsep}{3pt}")
        println(io, "\\begin{adjustbox}{max width=\\textwidth}")
        println(io, "\\begin{tabular}{@{}l", "r"^15, "@{}}")
        println(io, "\\toprule")
        println(io, "Class & \$L\$ & \$B\$ & \$T\$ & \$C_B\$ & Deadweight & Capacity & ",
            "Speed & Power & \$f_R\$ & Price & Cargo & Deck & Air draft & Lost & ",
            "Fixed-rig \\\\")
        println(io, " & [m] & [m] & [m] & & [t] & & [kn] & [MW] & & [MUSD] & [USD/t] & ",
            "tiers & limit [m] & calls [\\%] & delay [h] \\\\")
        println(io, "\\midrule")
        for class in classes
            write_class_row(io, class)
        end
        println(io, "\\bottomrule")
        println(io, "\\end{tabular}")
        println(io, "\\end{adjustbox}")
    end
end

"""
    write_class_row(io, class)

One row of the ship class table.
"""
function write_class_row(io, class)
    delay = isfinite(class.fixed_rig_port_hours) ?
            latex_number(class.fixed_rig_port_hours) : "\$\\infty\$"
    println(io, latex_escape(class.name), " & ", latex_number(class.length), " & ",
        latex_number(class.beam), " & ", latex_number(class.draft), " & ",
        latex_number(class.block_coefficient), " & ", latex_number(class.deadweight), " & ",
        unit_capacity(class), " & ", latex_number(class.service_speed), " & ",
        latex_number(round(class.power / 1e3; digits=1)), " & ",
        latex_number(round(Hull(class, assumptions).resistance_factor; digits=2)), " & ",
        latex_number(round(class.newbuild_price / 1e6; digits=1)), " & ",
        latex_number(class.cargo_value), " & ", latex_number(class.deck_tiers), " & ",
        latex_number(class.air_draft_limit), " & ",
        latex_number(round(100class.restricted_call_share; digits=1)), " & ", delay,
        " \\\\")
end

"""
    unit_capacity(class)

Cargo units of `class` with their unit, a dash for a ship that fills its deadweight.
"""
unit_capacity(class) = isfinite(class.unit_capacity) ?
    string(latex_number(class.unit_capacity), " ", uppercase(string(class.cargo_unit))) :
    "--"

"""
    class_source_notes()

Source note of each ship class by name from the class file, without the references to
the project's own notes.
"""
function class_source_notes()
    lines = readlines(joinpath(root, "data", "ship_classes.csv"))
    header = WindShipOpt.csv_fields(first(lines))
    notes = Dict{String, String}()
    for line in lines[2:end]
        row = Dict(zip(header, WindShipOpt.csv_fields(line)))
        notes[row["name"]] = replace(row["source"], r" \([^()]*notes\)" => "")
    end
    return notes
end

"""
    fuel_table()

Tabular of the fuel energy that the cheapest size of each rig saves on each ship class,
the mean over the routes, with each drive, and the tank-to-wake CO2 of the class on
VLSFO without a rig, in fuel_table.tex.
"""
function fuel_table()
    table = read_table(data_file("classes.csv"))
    open(joinpath(sections, "fuel_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}lr", "r"^(3length(drive_labels)), "@{}}")
        println(io, "\\toprule\n & CO\\textsubscript{2}, no rig & ", drive_header(3))
        println(io, "Class & [g/tkm] & ", rig_header())
        println(io, "\\midrule")
        for class in class_order(table)
            write_fuel_row(io, table, class)
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    drive_header(first_column)

Header row of one group of three rig columns per drive, the first group starting at
table column `first_column`, with a rule under each group.
"""
function drive_header(first_column)
    groups = join(("\\multicolumn{3}{c}{$label}" for (_, label) in drive_labels), " & ")
    starts = first_column .+ 3 .* (0:(length(drive_labels) - 1))
    return string(groups, " \\\\\n",
        join("\\cmidrule(lr){$start-$(start + 2)}" for start in starts))
end

"header cells of the rigs of every drive group"
rig_header() = string(join(repeat(["kite", "wings", "rotors"], length(drive_labels)),
        " & "), " \\\\")

"""
    write_fuel_row(io, table, class)

One row of the fuel table: the CO2 of `class` on VLSFO without a rig and the fuel saving
[%] of each rig at its cheapest size on each drive, both averaged over the routes.
"""
function write_fuel_row(io, table, class)
    bare = rows(table, "class" => class, "drive" => "vlsfo", "rig" => "none")
    cells = [@sprintf("%.1f", mean(table["carbon"][bare]))]
    for (drive, _) in drive_labels, rig in rig_names
        savings = [fuel_saving(table, class, drive, route, rig)
                   for route in unique(table["route"])]
        filter!(isfinite, savings)
        push!(cells, isempty(savings) ? "--" : @sprintf("%.1f", mean(savings)))
    end
    println(io, latex_escape(class), " & ", join(cells, " & "), " \\\\")
end

"""
    fuel_saving(table, class, drive, route, rig)

Fuel energy [%] that the cheapest size of `rig` saves against the same class without a
rig on one drive and route; `NaN` where a trip is missing.
"""
function fuel_saving(table, class, drive, route, rig)
    bare = rows(table, "class" => class, "drive" => drive, "route" => route,
        "rig" => "none")
    cheapest = cheapest_row(table, class, route, drive, rig)
    (isempty(bare) || isnothing(cheapest)) && return NaN
    return percent_saving(table["fuel"][cheapest], only(table["fuel"][bare]))
end

"""
    payback_table()

Tabular of the discounted payback time [years] of the cheapest size of each rig on each
ship class, the median over the routes, with each drive, in payback_table.tex; a dash
where the rig does not pay back within its life.
"""
function payback_table()
    table = read_table(data_file("classes.csv"))
    open(joinpath(sections, "payback_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}l", "r"^(3length(drive_labels)), "@{}}")
        println(io, "\\toprule\n & ", drive_header(2))
        println(io, "Class & ", rig_header())
        println(io, "\\midrule")
        for class in class_order(table)
            cells = String[]
            for (drive, _) in drive_labels, rig in rig_names
                years = [payback_years(table, class, drive, route, rig)
                         for route in unique(table["route"])]
                push!(cells, payback_cell(years))
            end
            println(io, latex_escape(class), " & ", join(cells, " & "), " \\\\")
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    payback_cell(years)

Median of the payback `years` over the routes, a dash when the median rig never pays
back.
"""
function payback_cell(years)
    middle = sort(years)[cld(length(years), 2)]
    return isfinite(middle) ? @sprintf("%.1f", middle) : "--"
end

"""
    payback_years(table, class, drive, route, rig)

Years until the yearly cash saving of the cheapest size of `rig`, before its own capital
charges and at the transport work of the rig ship, repays the rig's price at the
discount rate; `Inf` where it never does within the rig's life.
"""
function payback_years(table, class, drive, route, rig)
    bare = rows(table, "class" => class, "drive" => drive, "route" => route,
        "rig" => "none")
    best = cheapest_row(table, class, route, drive, rig)
    (isempty(bare) || isnothing(best)) && return Inf
    design = ShipDesign(Symbol(drive), ship_classes()[class];
        rig_size(rig, table["area"][best])...)
    ship = Ship(design, assumptions)
    retractable = table["retractable"][best] == "true"
    price = ShipCosts(ship, assumptions; retractable).capital -
            ShipCosts(Ship(ShipDesign(Symbol(drive), ship_classes()[class]), assumptions),
                assumptions).capital
    rate = assumptions[:discount_rate]
    lifetime = rig == "kite" ? assumptions[:kite_lifetime] :
               rig == "wings" ? assumptions[:wing_lifetime] : assumptions[:rotor_lifetime]
    charges = (WindShipOpt.capital_recovery(rate, lifetime) +
               assumptions[:maintenance_fraction]) * price
    outbound, inbound = run_corridors(Symbol(route))
    tonne_km = table["cargo"][best] * (outbound.track_length +
                                       assumptions[:backhaul_fraction] *
                                       inbound.track_length) / 1e3
    hours = 24table["days"][best] + 48assumptions[:port_time_per_call]
    yearly_work = tonne_km * 8760assumptions[:availability] / hours
    saving = (only(table["cost"][bare]) - table["cost"][best]) * yearly_work + charges
    saving > rate * price || return Inf
    years = -log(1 - rate * price / saving) / log(1 + rate)
    return years <= lifetime ? years : Inf
end
