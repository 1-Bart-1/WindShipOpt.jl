# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Table steps of the paper, written as LaTeX to paper/sections/: the inputs of
# data/assumptions.yaml that matter ranked by effect, the ship classes from
# data/ship_classes.csv, the fuel saving and payback of each rig, the goals and what
# missing one costs, and the numbers the abstracts state. Included by paper.jl.

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

"cost per tonne-km of `ship` without a rig in the goal_sizes.csv `table`"
bare_cost(table, ship) = only(table["cost"][rows(table, "ship" => ship, "rig" => "none")])

"cost per tonne-km at `share` of the (shares, costs) `curve` of [`share_costs`](@ref)"
curve_cost((shares, costs), share) = costs[findfirst(≈(share), shares)]

"value of the input `name` in years, as a table cell"
years(name) = @sprintf("%.0f years", assumptions[name])

"""
    goal_rows()

The goals behind the results as (goal, rigs, value, what is known today), each value read
from the input that holds it.
"""
function goal_rows()
    canopy = @sprintf("\\num{%.0f} h at %.0f g/m\$^2\$", assumptions[:canopy_life],
        assumptions[:canopy_cloth_weight])
    service = @sprintf("%.0f\\,\\%%", 100out_of_service_goal())
    kite_loss = assumptions[:kite_cycle_damage_probability] +
                assumptions[:kite_cycle_loss_probability]
    loss = @sprintf("1 in \\num{%.0f}", 1 / kite_loss)
    crew = @sprintf("USD~%.0f per cycle", assumptions[:kite_cycle_crew_cost])
    price = @sprintf("USD~%.0f/m\$^2\$", WindShipOpt.canopy_price(assumptions))
    today = @sprintf("our estimate USD~%.0f/m\$^2\$, from retail cloth and hand sewing",
        WindShipOpt.canopy_price_today(assumptions))
    return [("Canopy life", "kite", canopy,
            "derived \\num{3800} h (\\numrange{1200}{6900}), on makers' statements; " *
            "small kites expected 100 to \\num{1000} h"),
        ("Canopy price", "kite", price, today),
        ("Rig life", "wings", years(:wing_lifetime),
            "stated design life; about 2 years on record"),
        ("Rig life", "rotors", years(:rotor_lifetime),
            "stated design life; about 8 years on record"),
        ("Out of service", "all", service,
            "one rotor operator's 97\\,\\%; nothing for kites"),
        ("Crash in flight", "kite", "none",
            string("no record for a ship; M600 lost all four kites in twenty crosswind ",
                "flights, three of them in hover or landing \\citep{echeverri2020part1}")),
        ("Unit lost", "wings, rotors", "none", "none reported, and no duty to report one"),
        ("Lost per launch and landing", "kite", loss,
            "our estimate 0.25\\,\\%; no record for a ship"),
        ("Launch and landing crew", "kite", crew, "our estimate")]
end

"share of time each rig is out of service at its goal, the same for all [-]"
out_of_service_goal() = only(unique(assumptions[Symbol(out_of_service_inputs[rig])]
                                    for rig in rig_names))

"""
    goals_table()

Write the [`goal_rows`](@ref) to paper/sections/goals_table.tex.
"""
function goals_table()
    open(joinpath(sections, "goals_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}lllp{0.40\\textwidth}@{}}\n\\toprule")
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

"canopy price [USD/m^2] at which `rig` reaches `cost` on the (prices, costs) `curve`; kite
only"
kite_price_at_cost(rig, curve, cost) =
    rig == "kite" ? WindShipOpt.price_at_cost(curve..., cost) : NaN

"""
    missed_goal_rows()

For each ship of the goal limits and each rig, best first at the goals, at the cheapest size
of goal_sizes.csv: the [`size_limits`](@ref) of that size against its rival, the cheapest
other rig, and where the rig stops paying and where it comes level with that rival the
canopy life [h], the canopy price [USD/m^2] and the share out of service [-], that share
also for all units failing together;
for the kite its saving [%] at half the canopy life goal and at today's canopy price, and
the life and price at which it passes the rig ahead; the points of saving [%] its share out of
service costs at the goal. Raises an error where the sweeps differ in a rig's goal cost.
"""
function missed_goal_rows()
    sizes = read_table(data_file("goal_sizes.csv"))
    service = read_table(data_file("availability.csv"))
    lives = read_table(data_file("canopy_life.csv"))
    prices = read_table(data_file("canopy_price.csv"))
    result = []
    for ship in unique(sizes["ship"])
        bare = bare_cost(sizes, ship)
        cheapest = Dict(rig => cheapest_size(sizes, ship, rig) for rig in rig_names)
        goal = Dict(rig => sizes["cost"][cheapest[rig]] for rig in rig_names)
        curves = Dict(rig => share_costs(service, ship, rig) for rig in rig_names)
        picked = rows(lives, "ship" => ship)
        life_curve = lives["life"][picked], lives["cost"][picked]
        priced = rows(prices, "ship" => ship)
        price_curve = prices["price"][priced], prices["cost"][priced]
        WindShipOpt.check_goal_cost(ship, "out of service", goal, Dict(rig => curve_cost(
            curves[rig], assumptions[Symbol(out_of_service_inputs[rig])])
                                                                      for rig in rig_names))
        WindShipOpt.check_goal_cost(ship, "canopy life", Dict("kite" => goal["kite"]),
            Dict("kite" => curve_cost(life_curve, assumptions[:canopy_life])))
        WindShipOpt.check_goal_cost(ship, "canopy price", Dict("kite" => goal["kite"]),
            Dict("kite" => curve_cost(price_curve, WindShipOpt.canopy_price(assumptions))))
        for (; rig, rival, rival_cost, ahead) in WindShipOpt.ranked_rivals(goal)
            curve = curves[rig]
            half_goal = assumptions[:canopy_life] / 2
            saving_short = rig == "kite" ?
                           percent_saving(curve_cost(life_curve, half_goal), bare) : NaN
            today = WindShipOpt.canopy_price_today(assumptions)
            saving_today = rig == "kite" ?
                           percent_saving(curve_cost(price_curve, today), bare) : NaN
            push!(result, (; size_limits(sizes, cheapest[rig], bare, rival, rival_cost)...,
                saving_short,
                saving_today, service_points=percent_saving(curve[2][1], bare) -
                                             percent_saving(goal[rig], bare),
                life=(kite_life_at_cost(rig, life_curve, bare),
                    kite_life_at_cost(rig, life_curve, rival_cost)),
                passes=kite_life_at_cost(rig, life_curve, ahead),
                price=(kite_price_at_cost(rig, price_curve, bare),
                    kite_price_at_cost(rig, price_curve, rival_cost)),
                passes_price=kite_price_at_cost(rig, price_curve, ahead),
                share=(share_limit(curve, bare), share_limit(curve, rival_cost)),
                whole_behind=share_limit(([0.0, 1.0], [curve[2][1], curve[2][end]]),
                    rival_cost)))
        end
    end
    return result
end

"""
    size_limits(table, row, bare, rival, rival_cost)

Of the trip in `row` of the goal_sizes.csv `table`: ship, rig, area [m^2], cost saving [%],
the `rival` rig and the points of saving [%] by which the rig leads it at `rival_cost`,
cost of one crash [USD], the crashes a year at which it stops paying for itself against the
cost per tonne-km `bare` and comes level with its rival, and flight hours a year.
"""
function size_limits(table, row, bare, rival, rival_cost)
    ship, rig, area, cost = table["ship"][row], table["rig"][row], table["area"][row],
    table["cost"][row]
    design = ShipDesign(Symbol(table["drive"][row]), study_hull(ship);
        rig_size(rig, area)...)
    crash = WindShipOpt.crash_cost(Ship(design, assumptions).rig, assumptions)
    work, trips = yearly_trips(table, row, table["route"][row])
    return (; ship, rig, area, crash, saving=percent_saving(cost, bare), rival,
        lead=percent_saving(cost, bare) - percent_saving(rival_cost, bare),
        crashes=(crash_limit(cost, bare, work, crash),
            crash_limit(cost, rival_cost, work, crash)),
        flight_hours=table["flight_share"][row] * 24table["days"][row] * trips)
end

"""
    share_limit(curve, target)

Share out of service [-] at which the (shares, costs) `curve` reaches the cost per tonne-km
`target`; `NaN` where it starts at or above it, so that no share is left.
"""
share_limit(curve, target) =
    curve[2][1] < target ? WindShipOpt.share_at_cost(curve..., target) : NaN

"""
    crash_limit(cost, target, work, crash)

Crashes a year of cost `crash` [USD] at which a rig at `cost` per tonne-km over `work`
tonne-km a year reaches `target`; `NaN` where it is already there.
"""
crash_limit(cost, target, work, crash) =
    cost < target ? WindShipOpt.events_to_cost(cost, target, work, crash) : NaN

"""
    crash_limit_rows()

The [`size_limits`](@ref) on each ship of goal_sizes.csv of each rig at its cheapest size,
best rig first at the goals, and print for the kite the saving [%] and crashes a year to
stop paying at every size swept.
"""
function crash_limit_rows()
    table = read_table(data_file("goal_sizes.csv"))
    result = []
    for ship in unique(table["ship"])
        bare = bare_cost(table, ship)
        cheapest = Dict(rig => cheapest_size(table, ship, rig) for rig in rig_names)
        goal = Dict(rig => table["cost"][cheapest[rig]] for rig in rig_names)
        for (; rig, rival, rival_cost) in WindShipOpt.ranked_rivals(goal)
            push!(result, size_limits(table, cheapest[rig], bare, rival, rival_cost))
            rig == "kite" || continue
            swept = rows(table, "ship" => ship, "rig" => rig)
            limits = [size_limits(table, row, bare, rival, rival_cost) for row in swept]
            sizes = [@sprintf("%.0f m²: %.1f %%, %s/year", limit.area, limit.saving,
                         crash_cell(first(limit.crashes))) for limit in limits]
            println(ship, ", ", paper_name(rig), " by size: ", join(sizes, "; "))
        end
    end
    return result
end

"""
    goal_margins(row)

How far each limit of a [`missed_goal_rows`](@ref) row lies from its goal on the side that
leaves room, as fractions of the goal for canopy life and price and in shares for the time
out of service: positive where the goal can be missed by that much, negative where the goal
falls short of it.
"""
function goal_margins(row)
    life, price = assumptions[:canopy_life], WindShipOpt.canopy_price(assumptions)
    share = assumptions[Symbol(out_of_service_inputs[row.rig])]
    return [(life .- row.life) ./ life...; (row.price .- price) ./ price...;
            (row.share .- share)...]
end

"""
    missed_goals_table()

Write the [`missed_goal_rows`](@ref) as panel (a) and the [`crash_limit_rows`](@ref) as
panel (b) to paper/sections/missed_goals_table.tex, savings and leads shaded by their sign
and the limits by their [`goal_margins`](@ref), and print what the text takes from them
besides: the kite's saving at half the life goal and at today's canopy price, the points
each rig's outages cost, the life and price at which the kite passes the rig ahead and the share at
which all units failing together put a rig level with its rival.
"""
function missed_goals_table()
    goal_rows, crash_rows = missed_goal_rows(), crash_limit_rows()
    saving_scale = column_scale([getproperty.(goal_rows, :saving);
                                 getproperty.(crash_rows, :saving)])
    lead_scale = column_scale(getproperty.(goal_rows, :lead))
    margins = goal_margins.(goal_rows)
    margin_scales = [column_scale(getindex.(margins, k)) for k in 1:6]
    open(joinpath(sections, "missed_goals_table.tex"), "w") do io
        println(io, "\\textbf{(a)} Each rig at its cheapest size\\par\\smallskip")
        println(io, "\\adjustbox{max width=\\textwidth}{%")
        println(io, "\\begin{tabular}{@{}llrrlrrrrrrr@{}}")
        println(io, "\\toprule")
        println(io, " & & & & \\multicolumn{2}{c}{Against its rival} & ",
            "\\multicolumn{2}{c}{Canopy life [h] where} & ",
            "\\multicolumn{2}{c}{Canopy price [USD/m\\textsuperscript{2}] where} & ",
            "\\multicolumn{2}{c}{Out of service [\\%] where} \\\\")
        println(io, "\\cmidrule(lr){5-6}\\cmidrule(lr){7-8}\\cmidrule(lr){9-10}",
            "\\cmidrule(lr){11-12}")
        println(io, "Ship & Rig & Size [m\\textsuperscript{2}] & Saving [\\%] & ",
            "Rival & Lead [points] & ", join(fill("pays no more & level", 3), " & "),
            " \\\\")
        println(io, "\\midrule")
        for (row, margin) in zip(goal_rows, margins)
            shown = [row.life...; row.price...; 100 .* row.share...]
            limits = [shaded_cell(margin[k], margin_scales[k]; shown=shown[k],
                          format="%.0f") for k in 1:6]
            cells = [short_ship(row.ship); paper_name(row.rig); @sprintf("%.0f", row.area);
                     shaded_cell(row.saving, saving_scale); paper_name(row.rival);
                     shaded_cell(row.lead, lead_scale; format="%+.1f"); limits]
            println(io, join(cells, " & "), " \\\\")
            @printf("%s, %s: %.1f %% at half the life goal, %.1f %% at today's price, ",
                row.ship, paper_name(row.rig), row.saving_short, row.saving_today)
            @printf("outages cost %.2f points, passes the next up at %s h, USD %s, ",
                row.service_points, dash_cell(row.passes, "%.0f"),
                dash_cell(row.passes_price, "%.0f"))
            @printf("all units level with the rival at %s %%\n",
                share_cell(row.whole_behind))
        end
        println(io, "\\bottomrule\n\\end{tabular}}\n\n\\bigskip")
        println(io, "\\textbf{(b)} Crashes a year, each rig at its cheapest size",
            "\\par\\smallskip")
        println(io, "\\adjustbox{max width=\\textwidth}{%")
        println(io, "\\begin{tabular}{@{}llrrlrrrr@{}}")
        println(io, "\\toprule")
        println(io, " & & & & & & \\multicolumn{2}{c}{Crashes a year where} & ",
            "Flight \\\\")
        println(io, "\\cmidrule(lr){7-8}")
        println(io, "Ship & Rig & Size [m\\textsuperscript{2}] & Saving [\\%] & Rival & ",
            "One [kUSD] & pays no more & level & [h/year] \\\\")
        println(io, "\\midrule")
        crash_scales = [column_scale(getindex.(getproperty.(crash_rows, :crashes), k))
                        for k in 1:2]
        for row in crash_rows
            flight = row.rig == "kite" ? @sprintf("%.0f", row.flight_hours) : "--"
            crashes = [shaded_cell(sqrt(row.crashes[k]), sqrt(crash_scales[k]);
                           shown=row.crashes[k], format="%.2g") for k in 1:2]
            @printf(io, "%s & %s & %.0f & %s & %s & %.0f & %s & %s & %s \\\\\n",
                short_ship(row.ship), paper_name(row.rig), row.area,
                shaded_cell(row.saving, saving_scale), paper_name(row.rival),
                row.crash / 1e3, crashes..., flight)
        end
        println(io, "\\bottomrule\n\\end{tabular}}")
    end
end

"`ship` without its type, for a table column"
short_ship(ship) = replace(ship, " bulk carrier" => "", " container ship" => "")

"`value` in `format`, a dash where it is not finite"
dash_cell(value, format) = isfinite(value) ? Printf.format(Printf.Format(format), value) :
                           "--"

share_cell(share) = isnan(share) ? "--" : @sprintf("%.0f", 100share)

crash_cell(crashes) = isnan(crashes) ? "--" : @sprintf("%.2g", crashes)

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
the limit their cargo fills first, speed, engine power, resistance calibration, price,
cargo value, the inputs of deck cargo and port operations and the frontal and lateral
wind areas, in class_table.tex, and the rows of their sources in class_sources.tex; an
infinite fixed-rig delay, where a fixed rig prevents cargo handling, is printed as ∞.
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
        println(io, "\\begin{tabular}{@{}l", "r"^6, "l", "r"^11, "@{}}")
        println(io, "\\toprule")
        println(io, "Class & \$L\$ & \$B\$ & \$T\$ & \$C_B\$ & Deadweight & Capacity & ",
            "Limit & Speed & Power & \$f_R\$ & Price & Cargo & Deck & Air draft & Lost & ",
            "Fixed-rig & \$A_\\mathrm{F}\$ & \$A_\\mathrm{L}\$ \\\\")
        println(io, " & [m] & [m] & [m] & & [t] & & & [kn] & [MW] & & [MUSD] & [USD/t] & ",
            "tiers & limit [m] & calls [\\%] & delay [h] & [m\$^2\$] & [m\$^2\$] \\\\")
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
    windage = WindShipOpt.Windage(class, assumptions)
    println(io, latex_escape(class.name), " & ", latex_number(class.length), " & ",
        latex_number(class.beam), " & ", latex_number(class.draft), " & ",
        latex_number(class.block_coefficient), " & ", latex_number(class.deadweight), " & ",
        unit_capacity(class), " & ", limit_label(class), " & ",
        latex_number(class.service_speed), " & ",
        latex_number(round(class.power / 1e3; digits=1)), " & ",
        latex_number(round(Hull(class, assumptions).resistance_factor; digits=2)), " & ",
        latex_number(round(class.newbuild_price / 1e6; digits=1)), " & ",
        latex_number(class.cargo_value), " & ", latex_number(class.deck_tiers), " & ",
        latex_number(class.air_draft_limit), " & ",
        latex_number(round(100class.restricted_call_share; digits=1)), " & ", delay, " & ",
        latex_number(round(Int, windage.frontal_area)), " & ",
        latex_number(round(Int, windage.lateral_area)), " \\\\")
end

"""
    unit_capacity(class)

Cargo units of `class` with their unit, a dash for a ship that fills its deadweight.
"""
unit_capacity(class) = isfinite(class.unit_capacity) ?
    string(latex_number(class.unit_capacity), " ", uppercase(string(class.cargo_unit))) :
    "--"

"""
    limit_label(class)

"deadweight" where `class` without a rig fills its deadweight before its slots or decks,
"space" otherwise.
"""
limit_label(class) = string(WindShipOpt.cargo_limit(class, assumptions))

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

Tabular of the cost and fuel energy that the cheapest size of each rig saves on each ship
class with each drive, the mean over the routes, as "cost / fuel" in percent, with the
tank-to-wake CO2 of the class on VLSFO without a rig; deadweight-limited and
space-limited classes in two blocks, each closed by its mean, and each cell shaded by its
cost saving, in fuel_table.tex.
"""
function fuel_table()
    table = read_table(data_file("classes.csv"))
    classes = ship_classes()
    groups = [(limit, [name for name in class_order(table)
                       if limit_label(classes[name]) == limit])
              for limit in ("deadweight", "space")]
    scale = column_scale([first(saving) for (_, names) in groups for name in names
                          for saving in fuel_row_savings(table, [name])])
    open(joinpath(sections, "fuel_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}lr", "r"^(3length(drive_labels)), "@{}}")
        println(io, "\\toprule\n & CO\\textsubscript{2}, no rig & ", drive_header(3))
        println(io, "Class & [g/tkm] & ", rig_header())
        for (limit, names) in groups
            println(io, "\\midrule\n\\multicolumn{", 2 + 3length(drive_labels),
                "}{@{}l}{\\emph{", limit, "-limited}} \\\\")
            for name in names
                write_fuel_row(io, table, [name], latex_escape(name), scale)
            end
            write_fuel_row(io, table, names, "\\emph{mean}", scale)
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    split_table()

Tabular of the cost saving of the cheapest size of each rig with each drive, the mean
over the classes and routes, split by [`saving_split`](@ref) into fuel, time and the
rest, with the share of round trips the rig shortens and their median change, in
split_table.tex.
"""
function split_table()
    table = read_table(data_file("classes.csv"))
    lines = []
    for (drive, label) in drive_labels, (k, rig) in enumerate(rig_names)
        splits = filter(!isnothing, [saving_split(table, class, route, drive, rig)
                                     for class in class_order(table)
                                     for route in unique(table["route"])])
        saving, fuel, time = (mean(getproperty.(splits, part))
                              for part in (:saving, :fuel, :time))
        hours = getproperty.(splits, :hours)
        push!(lines, (; label=k == 1 ? label : "", rig,
            points=[saving, fuel, time, saving - fuel - time],
            shorter=100count(<(0), hours) / length(hours), trip=median(hours)))
    end
    scales = [maximum(abs(line.points[k]) for line in lines) for k in 1:4]
    trip_scale = maximum(abs(line.trip) for line in lines)
    open(joinpath(sections, "split_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}llrrrrrr@{}}\n\\toprule")
        println(io, " & & Saving & Fuel & Time & Rig and other & Shorter & ",
            "Round trip \\\\")
        println(io, "Drive & Rig & [\\%] & [points] & [points] & [points] & [\\%] & ",
            "[\\%] \\\\\n\\midrule")
        for line in lines
            cells = [shaded_cell(value, scale)
                     for (value, scale) in zip(line.points, scales)]
            @printf(io, "%s & %s & %s & %.0f & %s \\\\\n", line.label, line.rig,
                join(cells, " & "), line.shorter, shaded_cell(-line.trip, trip_scale;
                    shown=line.trip))
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    shaded_cell(value, scale; shown=value, format="%.1f")

Table cell of `shown` in `format`, a dash where it is not finite, on a background of the
paper's gain colour where `value` is positive and its loss colour where negative, the deeper
the larger `value` is against `scale`; plain where `value` is zero or not finite.
"""
function shaded_cell(value, scale; shown=value, format="%.1f")
    text = dash_cell(shown, format)
    isfinite(value) && value != 0 || return text
    depth = round(Int, 40 * min(abs(value) / scale, 1))
    return @sprintf("\\cellcolor{%s!%d}%s", value > 0 ? "gain" : "loss", depth, text)
end

"largest finite `abs` of `values`, the scale of a shaded column; 1 where none is finite"
column_scale(values) = maximum(abs, filter(isfinite, values); init=0.0) |>
                       scale -> scale > 0 ? scale : 1.0

"""
    saving_split(table, class, route, drive, rig)

Cost saving [%] of the cheapest size of `rig` against the same class without a rig on one
drive and route, the part of it from fuel and the part from time, the crew, capital and
cargo interest of the ship without a rig over the hours the rig takes off the round trip,
each in points of that ship's cost, and the change in round-trip hours [%]; `nothing`
where a trip is missing.
"""
function saving_split(table, class, route, drive, rig)
    bare = rows(table, "class" => class, "drive" => drive, "route" => route,
        "rig" => "none")
    cheapest = cheapest_row(table, class, route, drive, rig)
    (isempty(bare) || isnothing(cheapest)) && return nothing
    bare = only(bare)
    reference = table["cost"][bare]
    time_cost = sum(table[part][bare] for part in ("crew_cost", "capital_cost",
        "interest_cost"))
    hours = table["hours"][cheapest] / table["hours"][bare]
    fuel = table["fuel_cost"][bare] - table["fuel_cost"][cheapest]
    return (saving=percent_saving(table["cost"][cheapest], reference),
        fuel=100fuel / reference, time=100time_cost * (1 - hours) / reference,
        hours=100(hours - 1))
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
    fuel_row_savings(table, classes)

Cost and fuel saving [%] of each rig at its cheapest size on each drive, averaged over
`classes` and the routes, as `(cost, fuel)` drive by drive in the order of the fuel table;
`NaN` where none was run.
"""
fuel_row_savings(table, classes) =
    [Tuple(mean_savings(table, ("cost", "fuel"), classes, drive, rig))
     for (drive, _) in drive_labels for rig in rig_names]

"""
    write_fuel_row(io, table, classes, label, scale)

One row of the fuel table under `label`: the CO2 of `classes` on VLSFO without a rig and
the [`fuel_row_savings`](@ref) as "cost / fuel", shaded by the cost saving against
`scale`.
"""
function write_fuel_row(io, table, classes, label, scale)
    bare = [k for class in classes
            for k in rows(table, "class" => class, "drive" => "vlsfo", "rig" => "none")]
    cells = [@sprintf("%.1f", mean(table["carbon"][bare]));
             [isfinite(cost) ? string(shaded_cell(cost, scale), @sprintf(" / %.0f", fuel)) :
              "--" for (cost, fuel) in fuel_row_savings(table, classes)]]
    println(io, label, " & ", join(cells, " & "), " \\\\")
end

"""
    mean_savings(table, columns, classes, drive, rig)

Mean over `classes` and the routes of the class table `table` of the saving [%] in each of
`columns` of the cheapest size of `rig` on `drive`, over the routes where all are known;
`NaN` for each where none is.
"""
function mean_savings(table, columns, classes, drive, rig)
    savings = [[cheapest_saving(table, column, class, drive, route, rig)
                for column in columns]
               for class in classes for route in unique(table["route"])]
    known = filter(saving -> all(isfinite, saving), savings)
    return isempty(known) ? fill(NaN, length(columns)) : mean(known)
end

"""
    cheapest_saving(table, column, class, drive, route, rig)

Saving [%] in `column` ("cost" or "fuel") of the cheapest size of `rig` against the same
class without a rig on one drive and route; `NaN` where a trip is missing.
"""
function cheapest_saving(table, column, class, drive, route, rig)
    bare = rows(table, "class" => class, "drive" => drive, "route" => route,
        "rig" => "none")
    cheapest = cheapest_row(table, class, route, drive, rig)
    (isempty(bare) || isnothing(cheapest)) && return NaN
    return percent_saving(table[column][cheapest], only(table[column][bare]))
end

"""
    payback_table()

Tabular of the discounted payback time [years] of the cheapest size of each rig on each
ship class, the median over the routes, with each drive, in payback_table.tex; a dash
where the rig does not pay back within its life.
"""
function payback_table()
    table = read_table(data_file("classes.csv"))
    medians = Dict(class => [median_payback([payback_years(table, class, drive, route, rig)
                                             for route in unique(table["route"])])
                             for (drive, _) in drive_labels for rig in rig_names]
                   for class in class_order(table))
    scale = column_scale(1 ./ reduce(vcat, values(medians)))
    open(joinpath(sections, "payback_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}l", "r"^(3length(drive_labels)), "@{}}")
        println(io, "\\toprule\n & ", drive_header(2))
        println(io, "Class & ", rig_header())
        println(io, "\\midrule")
        for class in class_order(table)
            cells = [shaded_cell(1 / years, scale; shown=years) for years in medians[class]]
            println(io, latex_escape(class), " & ", join(cells, " & "), " \\\\")
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    median_payback(years)

Median of the payback `years` over the routes, `Inf` when the median rig never pays back.
"""
median_payback(years) = sort(years)[cld(length(years), 2)]

"""
    yearly_trips(table, row, route)

Transport work [tonne-km] and round trips of the trip in `row` of `table`, on `route`, over
a year's trading hours.
"""
function yearly_trips(table, row, route)
    outbound, inbound = run_corridors(Symbol(route))
    tonne_km = table["cargo"][row] * (outbound.track_length +
                                      assumptions[:backhaul_fraction] *
                                      inbound.track_length) / 1e3
    hours = 24table["days"][row] + 48assumptions[:port_time_per_call]
    trips = 8760assumptions[:availability] / hours
    return tonne_km * trips, trips
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
    charges = WindShipOpt.capital_recovery(rate, lifetime) *
              (price - WindShipOpt.worn_part_price(ship.rig, assumptions)) +
              WindShipOpt.rig_maintenance(ship.rig, price, assumptions)
    saving = (only(table["cost"][bare]) - table["cost"][best]) *
             first(yearly_trips(table, best, route)) + charges
    saving > rate * price || return Inf
    years = -log(1 - rate * price / saving) / log(1 + rate)
    return years <= lifetime ? years : Inf
end

"true wind angle bands of flight.csv as the table of where the rigs work names them"
flight_bands = [(0, "0--30"), (30, "30--60"), (60, "60--90"), (90, "90--120"),
    (120, "120--150"), (150, "150--180")]

"""
    flight_table()

Where the kite works over the study of routes.csv, by band of true wind angle: share of the
time, share of it in which the kite could pull, is up and pulls, its mean thrust while
up and lowest apparent wind angle, how much of each speed band it flies and its speed
against the ship without a rig, with the lowest apparent angles of the deck rigs:
flight_table.tex.
"""
function flight_table()
    table = read_table(data_file("flight.csv"))
    open(joinpath(sections, "flight_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}lrrrrrrrrrrrrrrrr@{}}\n\\toprule")
        println(io, "True wind & Time & Could & Up & Pulls & Thrust & ",
            "\\multicolumn{3}{c}{Could at speed [\\%]} & ",
            "\\multicolumn{3}{c}{Up at speed [\\%]} & \\multicolumn{2}{c}{Speed [kn]} & ",
            "\\multicolumn{3}{c}{Lowest AWA ",
            "[\\si{\\degree}]} \\\\")
        println(io, "\\cmidrule(lr){7-9}\\cmidrule(lr){10-12}\\cmidrule(lr){13-14}",
            "\\cmidrule(lr){15-17}")
        println(io, "angle [\\si{\\degree}] & [\\%] & [\\%] & [\\%] & [\\%] & [kN] & ",
            "<10 & 10--12 & >12 & <10 & 10--12 & >12 & no rig & kite & kite & wings & ",
            "rotors \\\\\n\\midrule")
        foreach(band -> write_flight_row(io, table, band), flight_bands)
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    kite_share(table, column, angle, speeds)

Share [%] of the kite's hours in true wind angle band `angle` at the ship speed bands
`speeds` counted in `column` of flight.csv, `--` where it has no such hours.
"""
function kite_share(table, column, angle, speeds)
    found = [i for i in rows(table, "rig" => "kite", "angle" => angle)
             if table["speed"][i] in speeds]
    isempty(found) && return "--"
    return @sprintf("%.0f", 100sum(table[column][found]) / sum(table["hours"][found]))
end

"""
    write_flight_row(io, table, band)

One row of [`flight_table`](@ref) for `band`, a pair of the lower angle and its label.
"""
function write_flight_row(io, table, (angle, label))
    kite = rows(table, "rig" => "kite", "angle" => angle)
    bare = rows(table, "rig" => "none", "angle" => angle)
    kite_hours = sum(table["hours"][kite])
    share(column) = @sprintf("%.0f", 100sum(table[column][kite]) / kite_hours)
    lowest(rig) = @sprintf("%.0f",
        minimum(table["lowest_angle"][rows(table, "rig" => rig, "angle" => angle)]))
    cells = (@sprintf("%.0f", 100kite_hours /
                              sum(table["hours"][rows(table, "rig" => "kite")])),
        share("available"), share("flying"), share("pulling"),
        @sprintf("%.0f", sum(table["thrust_hours"][kite]) / sum(table["flying"][kite])),
        (kite_share(table, column, angle, speeds)
         for speeds in ((8,), (10,), (12, 14)), column in ("available", "flying"))...,
        @sprintf("%.1f", sum(table["distance"][bare]) / sum(table["hours"][bare])),
        @sprintf("%.1f", sum(table["distance"][kite]) / kite_hours),
        lowest("kite"), lowest("wings"), lowest("rotors"))
    println(io, label, " & ", join(cells, " & "), " \\\\")
end

"""
    speed_choice_table()

Median over steady winds of the cost-optimal speed of the 140 m ship without and with the
reference rigs, free of the rig's cost, with its force held and the speed that force alone
gives: speed_choice_table.tex.
"""
function speed_choice_table()
    table = read_table(data_file("speed_choice.csv"))
    columns = ("bare", "free", "free_of_rig_cost", "held", "sailing")
    open(joinpath(sections, "speed_choice_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}llrrrrr@{}}\n\\toprule")
        println(io, "Drive & Rig & No rig & With rig & Rig free of cost & Force held & ",
            "Sailing on the force \\\\\n\\midrule")
        for (drive, drive_label) in drive_labels[1:2], rig in ("kite", "wings", "rotors")
            found = rows(table, "drive" => drive, "rig" => rig)
            cells = (@sprintf("%.1f", median(table[column][found])) for column in columns)
            println(io, drive_label, " & ", rig, " & ", join(cells, " & "), " \\\\")
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    speed_terms_table()

Fuel saving and change in time of the reference rigs on the 140 m ship on the terms of the
literature and on ours, against the ship without a rig on the same terms and drive, mean
over the routes of speed_terms.csv: speed_terms_table.tex.
"""
function speed_terms_table()
    table = read_table(data_file("speed_terms.csv"))
    labels = [("8kn", "\\SI{8}{kn}, fixed"), ("9kn", "\\SI{9}{kn}, fixed"),
        ("10kn", "\\SI{10}{kn}, fixed"), ("same_time", "same time as no rig"),
        ("cost", "speed set by cost")]
    open(joinpath(sections, "speed_terms_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}llrrrrrr@{}}\n\\toprule")
        println(io, " & & \\multicolumn{3}{c}{Fuel saved [\\%]} & ",
            "\\multicolumn{3}{c}{Time saved [\\%]} \\\\")
        println(io, "\\cmidrule(lr){3-5}\\cmidrule(lr){6-8}")
        println(io, "Drive & Terms & kite & wings & rotors & kite & wings & rotors \\\\")
        println(io, "\\midrule")
        lines = [(drive_label, label, speed_term_savings(table, drive, terms, "fuel"),
                     speed_term_savings(table, drive, terms, "hours"))
                 for (drive, drive_label) in drive_labels[1:2] for (terms, label) in labels]
        fuel_scale, time_scale = (column_scale(reduce(vcat, getindex.(lines, k)))
                                  for k in 3:4)
        for (drive_label, label, fuel, hours) in lines
            cells = [shaded_cell.(fuel, fuel_scale); shaded_cell.(hours, time_scale)]
            println(io, drive_label, " & ", label, " & ", join(cells, " & "), " \\\\")
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    speed_term_savings(table, drive, terms, column)

Saving [%] in `column` of kite, wings and rotors on `terms` against the ship without a rig,
which on the same-time terms is the one routed for cost, averaged over the routes; `NaN`
where a passage failed.
"""
function speed_term_savings(table, drive, terms, column)
    bare_terms = terms == "same_time" ? "cost" : terms
    return map(["kite", "wings", "rotors"]) do rig
        savings = Float64[]
        for route in unique(table["route"])
            bare = rows(table, "route" => route, "drive" => drive, "rig" => "none",
                "terms" => bare_terms)
            rigged = rows(table, "route" => route, "drive" => drive, "rig" => rig,
                "terms" => terms)
            (isempty(bare) || isempty(rigged)) && continue
            push!(savings, 100(1 - table[column][only(rigged)] / table[column][only(bare)]))
        end
        return isempty(savings) ? NaN : mean(savings)
    end
end

"""
What published fixed-speed kite studies report for each row of published_terms.csv: the
citation key, the speed [kn], its label in the table and the fuel saving they state [%].
"""
published_savings = [("podeur2016", 16.0, "\\citet{podeur2016}", "12.1"),
    ("podeur2016", 19.0, "\\citet{podeur2016}", "6.6"),
    ("bentin2018", 13.0, "\\citet{bentin2018}", "19--29, routed"),
    ("leloup2013", 8.0, "\\citet{leloup2013}", "23.5, downwind in one wind"),
    ("leloup2013", 15.5, "\\citet{leloup2013}", "26.6, one crossing"),
    ("cedelft2016", 10.5, "\\citet{cedelft2016}", "2--15"),
    ("cedelft2016", 12.3, "\\citet{cedelft2016}", "1--9"),
    ("traut2014", 11.2, "\\citet{traut2014}", "1--32")]

"""
    published_table()

Published fuel savings of kites at fixed speed beside our model at that speed on the nearest
of our ships, priced and free of the kite's running cost, and the routed saving and time of
our cost-optimal speed: published_table.tex.
"""
function published_table()
    table = read_table(data_file("published_terms.csv"))
    open(joinpath(sections, "published_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}llrrlrr@{}}\n\\toprule")
        println(io, "Study & Our ship & Kite & Speed & Published & ",
            "\\multicolumn{2}{c}{Ours [\\%]} \\\\")
        println(io, "\\cmidrule(lr){6-7}")
        println(io, " & & [\\si{m^2}] & [kn] & [\\%] & priced & free \\\\\n\\midrule")
        for (source, knots, label, published) in published_savings
            found = rows(table, "source" => source, "speed" => knots)
            isempty(found) && continue
            i = only(found)
            saving(column) = @sprintf("%.1f",
                100(1 - table[column][i] / table["fuel_bare"][i]))
            println(io, join((label, table["ship"][i], @sprintf("%.0f", table["area"][i]),
                    @sprintf("%.1f", knots), published, saving("fuel_kite"),
                    saving("fuel_free")), " & "), " \\\\")
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    speed_size_saving(table, ship, drive, rig, area, pricing, knots)

Over both routes of speed_size.csv, what `area` [m^2] of `rig` saves at `knots` [kn] against
the ship without a rig at that speed: fuel [%], fuel [GJ per round trip], cost [%], cost
[USD per 1000 tonne-km], and the rig's mean share of sea time flown; `nothing` where a
passage failed.
"""
function speed_size_saving(table, ship, drive, rig, area, pricing, knots)
    case(rig_name, rig_area, rig_pricing) = rows(table, "ship" => ship, "drive" => drive,
        "knots" => knots, "rig" => rig_name, "area" => rig_area, "pricing" => rig_pricing)
    rigged, bare = case(rig, area, pricing), case("none", 0.0, "priced")
    (isempty(rigged) || length(rigged) != length(bare)) && return nothing
    fuel_saved = mean(table["fuel"][bare] .- table["fuel"][rigged])
    cost_saved = mean(table["cost"][bare] .- table["cost"][rigged])
    return (fuel_percent=100fuel_saved / mean(table["fuel"][bare]), fuel=fuel_saved,
        cost_percent=100cost_saved / mean(table["cost"][bare]), cost=1e3cost_saved,
        flight=100mean(table["flight_share"][rigged]))
end

"""
    speed_size_table()

Kite savings by held ship speed on each ship and fuel of speed_size.csv: fuel saved by the
smallest kite and by the kite that saves the most fuel, both free of running cost, in
relative and absolute terms, the priced kite that saves the most cost, and the share of sea
time the largest kite flies: speed_size_table.tex.
"""
function speed_size_table()
    table = read_table(data_file("speed_size.csv"))
    open(joinpath(sections, "speed_size_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}llrrrrrrrrrr@{}}\n\\toprule")
        println(io, "Ship & Fuel & Speed & No kite & \\multicolumn{2}{c}{Smallest kite} & ",
            "\\multicolumn{3}{c}{Most fuel saved} & ",
            "\\multicolumn{2}{c}{Most cost saved} & Flown \\\\")
        println(io, "\\cmidrule(lr){5-6}\\cmidrule(lr){7-9}\\cmidrule(lr){10-11}")
        println(io, " & & [kn] & [GJ] & [\\%] & [GJ] & [\\si{m^2}] & [\\%] & [GJ] & ",
            "[\\si{m^2}] & [\\%] & [\\%] \\\\")
        println(io, "\\midrule")
        lines = []
        for grid in speed_size_grid, drive in string.(grid.drives), knots in grid.speeds
            saving(area, pricing) = speed_size_saving(table, grid.ship, drive, "kite", area,
                pricing, knots)
            free = [saving(area, "free") for area in grid.kites]
            priced = [saving(area, "priced") for area in grid.kites]
            (any(isnothing, free) || any(isnothing, priced)) && continue
            most_fuel = argmax(i -> free[i].fuel, eachindex(free))
            most_cost = argmax(i -> priced[i].cost_percent, eachindex(priced))
            bare = rows(table, "ship" => grid.ship, "drive" => drive, "knots" => knots,
                "rig" => "none")
            push!(lines, (; grid.ship, drive, knots, bare=mean(table["fuel"][bare]),
                smallest=free[1], most_fuel=free[most_fuel],
                fuel_area=grid.kites[most_fuel], cost_area=grid.kites[most_cost],
                cost=priced[most_cost].cost_percent,
                flight=free[end].flight))
        end
        fuel_scale = column_scale(getproperty.(getproperty.(lines, :most_fuel),
            :fuel_percent))
        cost_scale = column_scale(getproperty.(lines, :cost))
        for line in lines
            println(io, join((line.ship, Dict(drive_labels)[line.drive],
                    @sprintf("%.0f", line.knots), @sprintf("%.0f", line.bare),
                    shaded_cell(line.smallest.fuel_percent, fuel_scale),
                    @sprintf("%.0f", line.smallest.fuel), @sprintf("%.0f", line.fuel_area),
                    shaded_cell(line.most_fuel.fuel_percent, fuel_scale),
                    @sprintf("%.0f", line.most_fuel.fuel), @sprintf("%.0f", line.cost_area),
                    shaded_cell(line.cost, cost_scale), @sprintf("%.0f", line.flight)),
                " & "), " \\\\")
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end


"""
    fidelity_parts()

Each part of the model as (part, varied, model, error, effect): its name, how its effect is
measured, how it is modelled, its known error, and the data file with the groups of
condition sets whose results [`part_effect`](@ref) compares.
"""
fidelity_parts() = [
    (part="Calm-water resistance", varied="calibration off",
        model="Holtrop--Mennen, scaled to the delivered power of each class's " *
              "source design",
        error="Holtrop's worked example within 5\\,\\%; uncalibrated 9 to 71\\,\\% above " *
              "the source designs", effect=switched(:calibration)),
    (part="Added resistance in waves", varied="removed",
        model="SNNM response integrated over the ERA5 wave spectrum, waves from any angle",
        error="peak in head waves within the scatter of the data behind SNNM",
        effect=switched(:waves)),
    (part="Windage", varied="removed",
        model="drag coefficient times the cosine of the apparent wind angle on the front " *
              "area", error="no side force, no dependence on the deck cargo",
        effect=switched(:windage)),
    (part="Heel, leeway and rudder limits", varied="removed",
        model="steady balance; side force beyond the limits is shed by trimming the rig",
        error="limits are design rules, not measured", effect=switched(:limits)),
    (part="Leeway and rudder drag", varied="rudder drag off",
        model="Kijima side force slope; rudder as a lifting line carrying the yaw moment",
        error="hull side force from regression, not from tests of these hulls",
        effect=switched(:rudder)),
    (part="Propeller and engine", varied="input ranges",
        model="actuator disk with viscous loss; engine efficiency falling at part load",
        error="no open-water curve of a real propeller",
        effect=varied_inputs(:propeller_viscous_efficiency, :thrust_deduction_ratio,
            :propeller_diameter_ratio, :part_load_penalty, :engine_rating_fraction,
            :methanol_engine_efficiency, :vlsfo_engine_efficiency, :shaft_efficiency)),
    (part="Wind at height", varied="input ranges",
        model="one power-law profile from 10\\,m, the mean of ERA5 over the region",
        error="real shear varies with stability from hour to hour",
        effect=varied_inputs(:wind_shear_exponent, :air_density)),
    (part="Wing sail forces", varied="input ranges",
        model="lifting line with stall, trimmed at each wind; array factor of the units",
        error="interference fitted to CFD of three to four sails",
        effect=varied_inputs(:wing_max_lift_coefficient, :wing_profile_drag_coefficient,
            :wing_span_efficiency, :wing_endplate_factor, :wing_separation_drag_factor,
            :wing_stalled_drag_coefficient, :wing_interference_amplitude,
            :wing_interference_decay)),
    (part="Rotor forces", varied="input ranges",
        model="ShipCLEAN coefficients over spin ratio, trimmed at each wind; array factor",
        error="fit to CFD and full-scale data within its scatter; interference from two " *
              "to four rotors",
        effect=varied_inputs(:rotor_lift_factor, :rotor_interference_amplitude,
            :rotor_interference_decay, :rotor_max_surface_speed, :rotor_max_wind)),
    (part="Kite flight", varied="input ranges",
        model="quasi-steady pattern with mass, bridle and tether drag, searched for each " *
              "wind and course",
        error="glide ratio of 4 matched to flight data",
        effect=varied_inputs(:kite_min_turn_radius, :tether_length_ratio,
            :kite_min_elevation, :kite_flight_drag, :kite_stall_margin,
            :kite_max_force_per_area, :kite_mass_per_area, :tether_drag_coefficient)),
    (part="Kite launch and sea limits", varied="input ranges",
        model="fixed limits of wind and significant wave height for launch, flight and " *
              "landing",
        error="wave limits are estimates without a source",
        effect=varied_inputs(:kite_launch_max_wave_height, :kite_max_wave_height,
            :kite_landing_max_wave_height, :kite_max_wind, :kite_launch_max_wind,
            :kite_launch_min_wind, :kite_landing_max_wind, :kite_launch_margin)),
    (part="Wear and availability", varied="input ranges",
        model="canopy life from UV and wear per flight hour; launch damage and loss; " *
              "time out of service for every rig",
        error="canopy wear rate from paragliders, not from towing kites",
        effect=varied_inputs(:canopy_life, :tether_lifetime, :kite_cycle_damage_probability,
            :kite_cycle_loss_probability, :kite_out_of_service, :wing_out_of_service,
            :rotor_out_of_service, :wing_lifetime, :rotor_lifetime)),
    (part="Rig prices", varied="input ranges",
        model="price per area and per unit, installation, maintenance",
        error="ranges of the quoted and built-up prices",
        effect=varied_inputs(:canopy_making_cost_per_area, :tether_price,
            :canopy_cloth_base_price, :wing_cost_per_area, :wing_unit_cost,
            :rotor_cost_per_area, :rotor_unit_cost, :maintenance_fraction)),
    (part="Weather sample", varied="each year alone",
        model="ERA5 2017 to 2019, a departure every 6\\,h",
        error="three years against a climate", effect=weather_years()),
    (part="Router", varied="corridor grid",
        model="dynamic programming over a corridor grid of positions and speeds",
        error="not converged in the corridor spacing", effect=corridor_grids()),
    (part="Rig size search", varied="every size",
        model="three sizes, then two by interpolation",
        error="the loss against the best of every size, shown here",
        effect=size_search_grid()),
]

"the whole model and the model with `part` off, in the model-part study"
switched(part) =
    ("model_parts.csv", "ship", [[("part" => "none",), ("part" => string(part),)]])

"for each of `inputs`, the base and both bounds of the input screening"
varied_inputs(inputs...) = ("sensitivity.csv", "ship",
    [[("input" => "none", "bound" => "value"); [("input" => string(input), "bound" => bound)
                                                for bound in ("low", "high")]]
     for input in inputs])

"each weather year"
weather_years() = ("weather_years.csv", "ship",
    [[("year" => year,) for year in 1:ceil(Int, last(departures) / 8760)]])

"each corridor scale of the convergence study, on its one ship"
corridor_grids() =
    ("convergence.csv", nothing, [[("scale" => scale,) for scale in (8.0, 4.0, 2.0)]])

"the best size found by the search and the best of every size"
size_search_grid() = ("size_search.csv", "class", [[(), ("round" => >=(0),)]])

"""
    part_effect((file, ship_column, groups))

Largest difference [points] in the cost saving of each rig between the condition sets of
any one of `groups` in data `file`, over its ships in `ship_column`, `nothing` for a file
of the 140 m ship alone; and for each set of rigs that take turns at being cheapest
within a group, the ships where they do.
"""
function part_effect((file, ship_column, groups))
    table = read_table(data_file(file))
    spread = Dict(rig => 0.0 for rig in rig_names)
    swaps = Dict{String, Set{String}}()
    ships = isnothing(ship_column) ? [nothing] : unique(table[ship_column])
    for ship in ships, group in groups
        at_ship = isnothing(ship) ? () : (ship_column => ship,)
        costs = filter(cost -> all(isfinite, values(cost)),
            [best_costs(table, (at_ship..., variant...)) for variant in group])
        length(costs) > 1 || continue
        for rig in rig_names
            savings = [percent_saving(cost[rig], cost["none"]) for cost in costs]
            spread[rig] = max(spread[rig], maximum(savings) - minimum(savings))
        end
        best = unique(argmin(rig -> cost[rig], rig_names) for cost in costs)
        length(best) > 1 && push!(get!(swaps, join(sort(best), "/"), Set()),
            replace(short_ship(something(ship, "140 m")), " " => "~"))
    end
    return spread, sort([string(rigs, " on ", join(sort(collect(swapped)), ", "))
                         for (rigs, swapped) in swaps])
end

"cheapest cost per tonne-km without a rig and of each rig in the `conditions` rows"
best_costs(table, conditions) = Dict(rig => minimum(table["cost"][rows(table,
    conditions..., "rig" => rig)]; init=Inf) for rig in ("none", rig_names...))

"""
    fidelity_table()

Write each of [`fidelity_parts`](@ref) with its model, its effect on each rig's cost saving
and on which rig is cheapest by [`part_effect`](@ref), and its known error, to
paper/sections/fidelity_table.tex.
"""
function fidelity_table()
    open(joinpath(sections, "fidelity_table.tex"), "w") do io
        for (; part, varied, model, error, effect) in fidelity_parts()
            spread, swaps = part_effect(effect)
            @printf(io, "%s {\\itshape (%s)} & %s & %.1f & %.1f & %.1f & %s & %s \\\\\n",
                part, varied, model, spread["kite"], spread["wings"], spread["rotors"],
                isempty(swaps) ? "--" : join(swaps, "; "), error)
        end
    end
end

"word of each drive in the names of the number macros"
drive_words = ["vlsfo" => "Oil", "ammonia" => "Ammonia"]

"word in the names of the number macros of each kind of ship, by the unit of its cargo"
ship_kind_words = [:teu => "Container", :ceu => "CarCarrier", :tonne => "Bulk"]

"""
    numbers_file()

Write the numbers the paper and its extended abstract state as LaTeX macros `\\Num...` to
paper/sections/numbers.tex by [`number_macro`](@ref), the results marked at draft fidelity:
the goals, and the [`class_numbers`](@ref), [`recommendation_numbers`](@ref) and
[`premium_numbers`](@ref) of the class study.
"""
function numbers_file()
    classes = read_table(data_file("classes.csv"))
    results = [class_numbers(classes); recommendation_numbers(classes);
               premium_numbers(classes)]
    draft = paper_run.fidelity != :final
    open(joinpath(sections, "numbers.tex"), "w") do io
        for (name, text) in goal_numbers()
            print(io, number_macro(name, text, false))
        end
        for (name, text) in results
            print(io, number_macro(name, text, draft))
        end
    end
end

"""
    goal_numbers()

Name and text of the goals the abstracts state: canopy life, the canopy price
at the goal and today, and the share of time out of service.
"""
goal_numbers() = [
    "CanopyLifeGoal" => @sprintf("\\num{%.0f}", assumptions[:canopy_life]),
    "CanopyPriceGoal" => @sprintf("%.0f", WindShipOpt.canopy_price(assumptions)),
    "CanopyPriceToday" => @sprintf("%.0f", WindShipOpt.canopy_price_today(assumptions)),
    "OutOfServiceGoal" => @sprintf("%.0f", 100out_of_service_goal())]

"""
    class_numbers(classes)

Name and text, per drive and rig, of the mean over the classes and routes of the class
table `classes` of the cost saving [%] of the cheapest size, and of the cells of class
and route where the rig saves most and saves at all, with the count of cells.
"""
function class_numbers(classes)
    numbers = Pair{String, String}[]
    for (drive, word) in drive_words
        cells = filter(!isempty, [best_savings(classes, class, route, drive)
                                  for class in class_order(classes)
                                  for route in unique(classes["route"])])
        leaders = [argmax(cell) for cell in cells if maximum(values(cell)) > 0]
        push!(numbers, "Cells$word" => string(length(cells)))
        for rig in rig_names
            name = word * uppercasefirst(rig)
            push!(numbers, "Saving$name" => whole_number(
                    mean(cell[rig] for cell in cells if haskey(cell, rig))),
                "Leads$name" => string(count(==(rig), leaders)))
        end
    end
    return numbers
end

"""
    recommendation_numbers(table)

Name and text, per kind of ship of `ship_kind_words` and rig, of the [`mean_savings`](@ref)
over its classes in the class table `table` of the cost [%] on each drive and of the
tank-to-wake CO2 [%] on VLSFO.
"""
function recommendation_numbers(table)
    classes = ship_classes()
    numbers = Pair{String, String}[]
    for (unit, kind) in ship_kind_words, rig in rig_names
        names = [name for name in class_order(table) if classes[name].cargo_unit == unit]
        name = kind * uppercasefirst(rig)
        for (drive, word) in drive_words
            cost, = mean_savings(table, ("cost",), names, drive, rig)
            push!(numbers, "Saving$word$name" => whole_number(cost))
        end
        carbon, = mean_savings(table, ("carbon",), names, "vlsfo", rig)
        push!(numbers, "Carbon$name" => whole_number(carbon))
    end
    return numbers
end

"""
    premium_numbers(table)

Name and text of the mean over the classes and routes of the class table `table` of how
much more [%] the e-ammonia ship costs than the same ship on VLSFO without a rig, without
a rig and with the rig that saves it most.
"""
function premium_numbers(table)
    without, with = Float64[], Float64[]
    for class in class_order(table), route in unique(table["route"])
        fossil = rows(table, "class" => class, "drive" => "vlsfo", "route" => route,
            "rig" => "none")
        bare = rows(table, "class" => class, "drive" => "ammonia", "route" => route,
            "rig" => "none")
        (isempty(fossil) || isempty(bare)) && continue
        rigged = filter(!isnothing, [cheapest_row(table, class, route, "ammonia", rig)
                                     for rig in rig_names])
        reference = only(table["cost"][fossil])
        push!(without, -percent_saving(only(table["cost"][bare]), reference))
        push!(with, -percent_saving(minimum(table["cost"][rigged]), reference))
    end
    return ["PremiumNoRig" => whole_number(mean(without)),
        "PremiumBestRig" => whole_number(mean(with))]
end
