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
from the input that holds it.
"""
function goal_rows()
    canopy = @sprintf("\\num{%.0f} h at %.0f g/m\$^2\$", assumptions[:canopy_life],
        assumptions[:canopy_cloth_weight])
    service = @sprintf("%.0f\\,\\%%",
        100only(unique(assumptions[Symbol(out_of_service_inputs[rig])]
                       for rig in rig_names)))
    kite_loss = assumptions[:kite_cycle_damage_probability] +
                assumptions[:kite_cycle_loss_probability]
    loss = @sprintf("1 in \\num{%.0f}", 1 / only(unique((kite_loss,
        assumptions[:rigid_cycle_loss_probability]))))
    crew = @sprintf("USD~%.0f per cycle", assumptions[:kite_cycle_crew_cost])
    price = @sprintf("USD~%.0f/m\$^2\$", WindShipOpt.canopy_price(assumptions))
    today = @sprintf("our estimate USD~%.0f/m\$^2\$, from retail cloth and hand sewing",
        WindShipOpt.canopy_price_today(assumptions))
    return [("Canopy life", "kite", canopy,
            "derived \\num{3800} h (\\numrange{1200}{6900}), on makers' statements; " *
            "small kites expected 100 to \\num{1000} h"),
        ("Canopy price", "kite", price, today),
        ("Rig life", "VTOL kite", years(:rigid_lifetime),
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
            "our estimates: 0.25\\,\\% kite, 0.05\\,\\% VTOL kite; no record for a ship"),
        ("Launch and landing crew", "kites", crew, "our estimate")]
end

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
of goal_sizes.csv: the [`size_limits`](@ref) of that size, and where the rig stops paying
and falls behind the next rig (`NaN` for the last) the canopy life [h], the canopy price
[USD/m^2] and the share out of service [-], that share also for all units failing together;
for the kite its saving [%] at a canopy life of 2,000 h and at today's canopy price, and the
life and price at which it passes the rig ahead; the points of saving [%] its share out of
service costs at the goal. Raises an error where the sweeps differ in a rig's goal cost.
"""
function missed_goal_rows()
    sizes = read_table(data_file("goal_sizes.csv"))
    service = read_table(data_file("availability.csv"))
    lives = read_table(data_file("canopy_life.csv"))
    prices = read_table(data_file("canopy_price.csv"))
    result = []
    for ship in unique(sizes["ship"])
        bare = only(sizes["cost"][rows(sizes, "ship" => ship, "rig" => "none")])
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
        for (; rig, ahead, next) in WindShipOpt.ranked_neighbours(goal)
            curve = curves[rig]
            saving_short = rig == "kite" ?
                           percent_saving(curve_cost(life_curve, 2000.0), bare) : NaN
            today = WindShipOpt.canopy_price_today(assumptions)
            saving_today = rig == "kite" ?
                           percent_saving(curve_cost(price_curve, today), bare) : NaN
            push!(result, (; size_limits(sizes, cheapest[rig], bare, next)..., saving_short,
                saving_today, service_points=percent_saving(curve[2][1], bare) -
                                             percent_saving(goal[rig], bare),
                life=(kite_life_at_cost(rig, life_curve, bare),
                    kite_life_at_cost(rig, life_curve, next)),
                passes=kite_life_at_cost(rig, life_curve, ahead),
                price=(kite_price_at_cost(rig, price_curve, bare),
                    kite_price_at_cost(rig, price_curve, next)),
                passes_price=kite_price_at_cost(rig, price_curve, ahead),
                share=(WindShipOpt.share_at_cost(curve..., bare),
                    WindShipOpt.share_at_cost(curve..., next)),
                whole_behind=WindShipOpt.share_at_cost([0.0, 1.0],
                    [curve[2][1], curve[2][end]], next)))
        end
    end
    return result
end

"""
    size_limits(table, row, bare, next_cost)

Of the trip in `row` of the goal_sizes.csv `table`: ship, rig, area [m^2], cost saving [%],
cost of one crash [USD], the crashes a year at which it stops paying for itself against the
cost per tonne-km `bare` and falls behind `next_cost` of the next rig, and flight hours a
year.
"""
function size_limits(table, row, bare, next_cost)
    ship, rig, area, cost = table["ship"][row], table["rig"][row], table["area"][row],
    table["cost"][row]
    design = ShipDesign(Symbol(table["drive"][row]), study_hull(ship);
        rig_size(rig, area)...)
    crash = WindShipOpt.crash_cost(Ship(design, assumptions).rig, assumptions)
    work, trips = yearly_trips(table, row, table["route"][row])
    return (; ship, rig, area, crash, saving=percent_saving(cost, bare),
        crashes=(WindShipOpt.events_to_cost(cost, bare, work, crash),
            isnan(next_cost) ? NaN :
            WindShipOpt.events_to_cost(cost, next_cost, work, crash)),
        flight_hours=table["flight_share"][row] * 24table["days"][row] * trips)
end

"""
    crash_limit_rows()

The [`size_limits`](@ref) on each ship of goal_sizes.csv, best rig first at the goals: the
[`kite_rigs`](@ref) at every size swept and each other rig at its cheapest size.
"""
function crash_limit_rows()
    table = read_table(data_file("goal_sizes.csv"))
    result = []
    for ship in unique(table["ship"])
        bare = only(table["cost"][rows(table, "ship" => ship, "rig" => "none")])
        cheapest = Dict(rig => cheapest_size(table, ship, rig) for rig in goal_size_rigs)
        goal = Dict(rig => table["cost"][cheapest[rig]] for rig in goal_size_rigs)
        for (; rig, next) in WindShipOpt.ranked_neighbours(goal)
            swept = rig in kite_rigs ? rows(table, "ship" => ship, "rig" => rig) :
                    [cheapest[rig]]
            append!(result, [size_limits(table, row, bare, next) for row in swept])
        end
    end
    return result
end

"""
    missed_goals_table()

Write the [`missed_goal_rows`](@ref) as panel (a) and the [`crash_limit_rows`](@ref) as
panel (b) to paper/sections/missed_goals_table.tex and print what the text takes from them
besides: the kite's saving at 2,000 h and at today's canopy price, the points each rig's
outages cost, the life and price at which the kite passes the rig ahead and the share at
which all units failing together put a rig behind.
"""
function missed_goals_table()
    open(joinpath(sections, "missed_goals_table.tex"), "w") do io
        println(io, "\\textbf{(a)} Each rig at its cheapest size\\par\\smallskip")
        println(io, "\\adjustbox{max width=\\textwidth}{%")
        println(io, "\\begin{tabular}{@{}llrrrrrrrr@{}}")
        println(io, "\\toprule")
        println(io, " & & & & \\multicolumn{2}{c}{Canopy life [h] where} & ",
            "\\multicolumn{2}{c}{Canopy price [USD/m\\textsuperscript{2}] where} & ",
            "\\multicolumn{2}{c}{Out of service [\\%] where} \\\\")
        println(io, "\\cmidrule(lr){5-6}\\cmidrule(lr){7-8}\\cmidrule(lr){9-10}")
        println(io, "Ship & Rig & Size [m\\textsuperscript{2}] & Saving [\\%] & ",
            "pays no more & behind next & pays no more & behind next & ",
            "pays no more & behind next \\\\")
        println(io, "\\midrule")
        for row in missed_goal_rows()
            cells = [short_ship(row.ship); row.rig; @sprintf("%.0f", row.area);
                     @sprintf("%.1f", row.saving); dash_cell.(row.life, "%.0f")...;
                     dash_cell.(row.price, "%.0f")...; share_cell.(row.share)...]
            println(io, join(cells, " & "), " \\\\")
            @printf("%s, %s: %.1f %% at 2,000 h, %.1f %% at today's price, ", row.ship,
                row.rig, row.saving_short, row.saving_today)
            @printf("outages cost %.2f points, passes the next up at %s h, USD %s, ",
                row.service_points, dash_cell(row.passes, "%.0f"),
                dash_cell(row.passes_price, "%.0f"))
            @printf("all units behind at %s %%\n", share_cell(row.whole_behind))
        end
        println(io, "\\bottomrule\n\\end{tabular}}\n\n\\bigskip")
        println(io, "\\textbf{(b)} Crashes a year, each rig at its cheapest size and the ",
            "kites at each size swept\\par\\smallskip")
        println(io, "\\adjustbox{max width=\\textwidth}{%")
        println(io, "\\begin{tabular}{@{}llrrrrrr@{}}")
        println(io, "\\toprule")
        println(io, " & & & & & \\multicolumn{2}{c}{Crashes a year} & Flight \\\\")
        println(io, "\\cmidrule(lr){6-7}")
        println(io, "Ship & Rig & Size [m\\textsuperscript{2}] & Saving [\\%] & ",
            "One [kUSD] & pays no more & behind next & [h/year] \\\\")
        println(io, "\\midrule")
        for row in crash_limit_rows()
            flight = row.rig in kite_rigs ? @sprintf("%.0f", row.flight_hours) : "--"
            @printf(io, "%s & %s & %.0f & %.1f & %.0f & %s & %s & %s \\\\\n",
                short_ship(row.ship), row.rig, row.area, row.saving, row.crash / 1e3,
                crash_cell.(row.crashes)..., flight)
        end
        println(io, "\\bottomrule\n\\end{tabular}}")
    end
end

"`ship` without its type, for a table column"
short_ship(ship) = replace(ship, " bulk carrier" => "", " container ship" => "")

"`value` in `format`, a dash for `NaN`"
dash_cell(value, format) = isnan(value) ? "--" :
                           Printf.format(Printf.Format(format), value)

share_cell(share) = isnan(share) ? "--" : @sprintf("%.0f", 100share)

crash_cell(crashes) = isnan(crashes) ? "--" : string(round(crashes; sigdigits=2))

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
speed, engine power, resistance calibration, price, cargo value, the inputs of deck
cargo and port operations and the frontal and lateral wind areas, in class_table.tex,
and the rows of their sources in class_sources.tex; an infinite fixed-rig delay, where a fixed rig prevents cargo handling,
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
        println(io, "\\begin{tabular}{@{}l", "r"^17, "@{}}")
        println(io, "\\toprule")
        println(io, "Class & \$L\$ & \$B\$ & \$T\$ & \$C_B\$ & Deadweight & Capacity & ",
            "Speed & Power & \$f_R\$ & Price & Cargo & Deck & Air draft & Lost & ",
            "Fixed-rig & \$A_\\mathrm{F}\$ & \$A_\\mathrm{L}\$ \\\\")
        println(io, " & [m] & [m] & [m] & & [t] & & [kn] & [MW] & & [MUSD] & [USD/t] & ",
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
        unit_capacity(class), " & ", latex_number(class.service_speed), " & ",
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
    split_table()

Tabular of the cost saving of the cheapest size of each rig with each drive, the mean
over the classes and routes, split by [`saving_split`](@ref) into fuel, time and the
rest, with the share of round trips the rig shortens and their median change, in
split_table.tex.
"""
function split_table()
    table = read_table(data_file("classes.csv"))
    open(joinpath(sections, "split_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}llrrrrrr@{}}\n\\toprule")
        println(io, " & & Saving & Fuel & Time & Rig and other & Shorter & ",
            "Round trip \\\\")
        println(io, "Drive & Rig & [\\%] & [points] & [points] & [points] & [\\%] & ",
            "[\\%] \\\\\n\\midrule")
        for (drive, label) in drive_labels, (k, rig) in enumerate(rig_names)
            splits = filter(!isnothing, [saving_split(table, class, route, drive, rig)
                                         for class in class_order(table)
                                         for route in unique(table["route"])])
            saving, fuel, time = (mean(getproperty.(splits, part))
                                  for part in (:saving, :fuel, :time))
            hours = getproperty.(splits, :hours)
            @printf(io, "%s & %s & %.1f & %.1f & %.1f & %.1f & %.0f & %.1f \\\\\n",
                k == 1 ? label : "", rig, saving, fuel, time, saving - fuel - time,
                100count(<(0), hours) / length(hours), median(hours))
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

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
    charges = (WindShipOpt.capital_recovery(rate, lifetime) +
               assumptions[:maintenance_fraction]) *
              (price - WindShipOpt.worn_part_price(ship.rig, assumptions))
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
        for (drive, drive_label) in drive_labels[1:2], (terms, label) in labels
            cells = (speed_term_cells(table, drive, terms, "fuel")...,
                speed_term_cells(table, drive, terms, "hours")...)
            println(io, drive_label, " & ", label, " & ", join(cells, " & "), " \\\\")
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    speed_term_cells(table, drive, terms, column)

Saving [%] in `column` of each rig on `terms` against the ship without a rig, which on the
same-time terms is the one routed for cost; `--` where a passage failed.
"""
function speed_term_cells(table, drive, terms, column)
    bare_terms = terms == "same_time" ? "cost" : terms
    return map(("kite", "wings", "rotors")) do rig
        savings = Float64[]
        for route in unique(table["route"])
            bare = rows(table, "route" => route, "drive" => drive, "rig" => "none",
                "terms" => bare_terms)
            rigged = rows(table, "route" => route, "drive" => drive, "rig" => rig,
                "terms" => terms)
            (isempty(bare) || isempty(rigged)) && continue
            push!(savings, 100(1 - table[column][only(rigged)] / table[column][only(bare)]))
        end
        return isempty(savings) ? "--" : @sprintf("%.1f", mean(savings))
    end
end

"""
What published fixed-speed kite studies report for each row of published_terms.csv: the
citation key, the speed [kn], its label in the table and the fuel saving they state [%].
"""
published_savings = [("podeur2016", 16.0, "\\citet{podeur2016}", "12.1"),
    ("podeur2016", 19.0, "\\citet{podeur2016}", "6.6"),
    ("bentin2018", 13.0, "\\citet{bentin2018}", "19--29, routed"),
    ("leloup2013", 8.0, "\\tbd{Leloup et al. 2013}", "up to 23.5, one wind"),
    ("leloup2013", 15.5, "\\tbd{Leloup et al. 2013}", "26.6, one crossing"),
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
            println(io, join((grid.ship, Dict(drive_labels)[drive], @sprintf("%.0f", knots),
                    @sprintf("%.0f", mean(table["fuel"][bare])),
                    @sprintf("%.1f", free[1].fuel_percent), @sprintf("%.0f", free[1].fuel),
                    @sprintf("%.0f", grid.kites[most_fuel]),
                    @sprintf("%.1f", free[most_fuel].fuel_percent),
                    @sprintf("%.0f", free[most_fuel].fuel),
                    @sprintf("%.0f", grid.kites[most_cost]),
                    @sprintf("%.1f", priced[most_cost].cost_percent),
                    @sprintf("%.0f", free[end].flight)), " & "), " \\\\")
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

