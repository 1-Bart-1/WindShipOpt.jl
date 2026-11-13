# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Table steps of the paper, written as LaTeX to paper/sections/: the inputs of
# data/assumptions.yaml and the development study, the ship classes from
# data/ship_classes.csv, the payback of each rig, the goals and what
# missing one costs, and the numbers the abstracts state. Included by paper.jl.

"""
    canopy_life_table()

Table of the life statements behind the canopy wear rate, from
data/canopy_life_statements.csv, as canopy_life_table.tex; a cloth given as "same" is the
one of the row above.
"""
function canopy_life_table()
    lives = read_table(joinpath(root, "data", "canopy_life_statements.csv"))
    columns = ("grade", "cloth", "weight", "life_text", "ends_on", "tension", "strength",
        "dose", "rate")
    open(joinpath(sections, "canopy_life_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}lllrrlrrrr@{}}\n\\toprule")
        println(io, "Source & Grade & Cloth & \$w\$ & Life \$L\$ & Ends on & \$T/w\$ & ",
            "\$\\sigma_w\$ & \$\\dot D\$ & \$r\$ \\\\")
        square = "m\\textsuperscript{2}"
        println(io, " & & & [g/$square] & [h] & & & & [MJ/$square/h] & [g/$square/h] ",
            "\\\\\n\\midrule")
        cloth = ""
        for row in findall(==("statement"), lives["kind"])
            lives["cloth"][row] == "same" || (cloth = lives["cloth"][row])
            cells = (column == "cloth" ? cloth : string(lives[column][row])
                     for column in columns)
            println(io, "\\citet{", lives["key"][row], "} & ", join(cells, " & "), " \\\\")
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    latex_escape(text)

`text` with the characters LaTeX treats specially escaped and powers set as superscripts.
"""
latex_escape(text) = replace(text, "\\" => "\\textbackslash{}", "&" => "\\&", "%" => "\\%",
    "\$" => "\\\$", "#" => "\\#", "_" => "\\_", "~" => "\\textasciitilde{}",
    ">=" => "\\ensuremath{\\geq}", "<=" => "\\ensuremath{\\leq}", ">" => "\\textgreater{}",
    "<" => "\\textless{}", r"\^(-?\d)" => s"\\textsuperscript{\1}", "^" => "\\^{}")

"""
    latex_prose(text)

Plain-text source note `text` escaped and typeset: about for `~`, en dashes in ranges,
minus and times signs, digit groups, subscripts, degrees Celsius, the paper's \$C_B\$ and
TEU, and page numbers and numbers with their unit unbroken.
"""
function latex_prose(text)
    text = replace(latex_escape(replace(text, "~" => "about ")),
        r"\d{1,3}(,\d{3})+(?!\d)|(?<![\w.,-])\d{5,}(?=\+|-\d{5,}\b)|(?<=\d-)\d{5,}\b" =>
            digit_groups)
    return replace(text,
        r"(?<![\w-])(\d+(?:\.\d+)?)-(?=\d+(?:\.\d+)?(?![\w-]))" => s"\1--",
        r"(?<![\w-])([A-Z])-(?=[A-Z](?![\w-]))" => s"\1--",
        r"(^|[\s(=])-(?=\d)" => s"\1\\ensuremath{-}",
        r"(\d) - (?=\d)" => s"\1 \\ensuremath{-} ",
        r"(\w)\*(?=\w)" => s"\1\\ensuremath{\\times}",
        r"(\S) x (?=\d)" => s"\1 \\ensuremath{\\times} ",
        r"\b([A-Za-z])\\_([A-Za-z]+)\b" => s"\\ensuremath{\1_\\mathrm{\2}}",
        r"\bFn\b" => "\\ensuremath{F_n}",
        r"(\d) C(?![\w\\])" => s"\1\\,\\si{\\degreeCelsius}",
        r"(\d) \\%" => s"\1\\,\\%", r"\bp\. (?=\d)" => "p.~",
        r"\bCb\b" => "\\ensuremath{C_B}", r"\bteu\b" => "TEU",
        r"(\d) (?=(m|t|kn|kW|MW|TEU|CEU|dwt|GT)\b)" => s"\1~")
end

"a number written with thousands commas, regrouped as the paper's numbers are"
function digit_groups(number)
    digits = replace(number, "," => "")
    length(digits) <= 4 && return digits
    groups = Iterators.partition(reverse(digits), 3)
    return join(reverse([reverse(join(group)) for group in groups]), "\\,")
end

"""
    latex_number(value)

`value` as a siunitx number, whole numbers below a million without a decimal point.
"""
latex_number(value) = string("\\num{", isinteger(value) && abs(value) < 1e6 ? Int(value) :
    value, "}")

"""
    input_tables()

Write [`ranged_inputs`](@ref) to paper/sections/input_tables.tex as one longtable with
value, range, unit and source.
"""
function input_tables()
    ragged = ">{\\raggedright\\arraybackslash}"
    open(joinpath(sections, "input_tables.tex"), "w") do io
        println(io, "\\begin{longtable}{@{}", ragged, "p{3.2cm}rr", ragged, "p{1.3cm}",
            ragged, "p{6.0cm}@{}}")
        println(io, "\\caption{Every input with a range, with its base value, range, unit ",
            "and source.}\n\\label{tab:inputs}\\\\")
        println(io, input_header, "\n\\endfirsthead")
        println(io, "\\multicolumn{5}{@{}l}{\\cref{tab:inputs} (continued)}\\\\")
        println(io, input_header, "\n\\endhead\n\\bottomrule\n\\endfoot")
        for (name, entry) in ranged_inputs()
            write_input_row(io, entry, name)
        end
        println(io, "\\end{longtable}")
    end
end

"every input with a range as (name, entry), sorted by name"
ranged_inputs() = sort!([pair for pair in assumptions.entries
                         if pair.second.low != pair.second.high]; by=first)

"header row of the input table"
input_header = "\\toprule\nInput & Value & Range & Unit & Source \\\\\n\\midrule"

"""
    write_input_row(io, entry, name)

One row of the input table: name, base value, range, unit and the full source note.
"""
function write_input_row(io, entry, name)
    label = uppercasefirst(replace(string(name), "_" => " ", r"^e_" => "e-",
        r"(?<![a-z])(vlsfo|teu|ceu|usd|eur)(?![a-z])" => uppercase, "froude" => "Froude"))
    unit = strip(entry.unit, '"')
    println(io, latex_escape(label), " & ", latex_number(entry.value),
        " & ", latex_number(entry.low), "--", latex_number(entry.high), " & ",
        unit == "-" ? "--" : latex_escape(unit), " & ", latex_prose(entry.reason), " \\\\")
end

"""
    sensitivity_saving(table, ship, rig, input, bound; column="cost")

Saving [%] in `column` per tonne-km of `rig` on `ship` with `input` at `bound` in the
development study `table`, against the same ship without a rig at the same bound; `NaN`
where a trip is missing.
"""
function sensitivity_saving(table, ship, rig, input, bound; column="cost")
    with_rig = study_values(table, column, ship, rig, input, bound)
    bare = study_values(table, column, ship, "none", input, bound)
    (isempty(with_rig) || isempty(bare)) && return NaN
    return percent_saving(only(with_rig), only(bare))
end

"the values of `column` of `rig` on `ship` with `input` at `bound` in the development study"
study_values(table, column, ship, rig, input, bound) =
    table[column][rows(table, "ship" => ship, "rig" => rig, "input" => input,
        "bound" => bound)]

"""
    bound_changes(table, ship, rig, input; column="cost")

Change of the saving of `rig` on `ship` in `column`, in points against the base inputs,
with `input` at its low and at its high bound.
"""
function bound_changes(table, ship, rig, input; column="cost")
    base = sensitivity_saving(table, ship, rig, "none", "value"; column)
    return (sensitivity_saving(table, ship, rig, input, "low"; column) - base,
        sensitivity_saving(table, ship, rig, input, "high"; column) - base)
end

"""
    lever_rigs(entry)

The rigs whose saving an entry of [`development_inputs`](@ref) moves.
"""
lever_rigs(entry) = entry.rig in rig_names ? (entry.rig,) : rig_names

"""
    lever_gain_loss(table, ship, entry; column="cost")

Largest rise and largest fall [points] of a saving in `column` on `ship` at either bound
of the development `entry`, over its rigs with both trips, zero where a side moves no rig
that way; `NaN` for both where no rig has both trips.
"""
function lever_gain_loss(table, ship, entry; column="cost")
    changes = [bound_changes(table, ship, rig, string(entry.input); column)
               for rig in lever_rigs(entry)]
    complete = filter(pair -> all(isfinite, pair), changes)
    isempty(complete) && return (NaN, NaN)
    return max(0.0, maximum(maximum, complete)), min(0.0, minimum(minimum, complete))
end

"a change in points with its sign, as LaTeX; no sign where it rounds to zero"
function signed_points(change)
    abs(change) < 0.05 && return "0.0"
    return replace(@sprintf("%+.1f", change), "-" => "\$-\$")
end

"the LaTeX cell of a gain and a loss in points, draft-marked; dashes without trips"
function effect_cell((gain, loss))
    isnan(gain) && return "--"
    text = string(signed_points(gain), "/", signed_points(loss))
    return paper_run.fidelity == :final ? text : "\\tbd{$text}"
end

"heading of each group of the development table, by the rig of its inputs"
development_groups = ["kite" => "Kite", "wings" => "Wing sails", "rotors" => "Rotors",
    "condition" => "Conditions"]

"""
    development_table()

Write [`development_inputs`](@ref) by rig to paper/sections/development_table.tex: value,
range, the gain and the loss of the cost saving on each ship, the largest gain and loss of
the CO2 saving, and the reason the input is in the study.
"""
function development_table()
    table = read_table(data_file("sensitivity.csv"))
    ships = unique(table["ship"])
    ragged = ">{\\raggedright\\arraybackslash}"
    open(joinpath(sections, "development_table.tex"), "w") do io
        println(io, "\\begin{longtable}{@{}", ragged, "p{2.5cm}", ragged, "p{2.6cm}rrrr",
            ragged, "p{3.4cm}@{}}")
        println(io, "\\caption{The inputs of the development study by the rig whose ",
            "developer can change them: base value and range; the gain of a rig's saving ",
            "at the better end of the range and its loss at the worse end, in percentage ",
            "points, in cost per tonne-km on each ship and the largest of each in ",
            "CO\\textsubscript{2} per tonne-km over the ships; and why the input is in ",
            "the study. Values are estimates, conditions or goals (g), to two digits, and ",
            "the gains and losses model output, to a tenth of a point; ",
            "\\cref{tab:goals} gives what is known today against each goal.}\n",
            "\\label{tab:development}\\\\")
        header = string("\\toprule\n & & \\multicolumn{3}{c}{Cost saving} & & \\\\\n",
            "\\cmidrule(lr){3-5}\nInput & Value (range) & ",
            join(short_ship.(ships), " & "),
            " & CO\\textsubscript{2} & Why \\\\\n\\midrule")
        println(io, header, "\n\\endfirsthead")
        println(io, "\\multicolumn{7}{@{}l}{\\cref{tab:development} (continued)}\\\\")
        println(io, header, "\n\\endhead\n\\bottomrule\n\\endfoot")
        for (rig, heading) in development_groups
            rig == first(first(development_groups)) || println(io, "\\addlinespace")
            println(io, "\\multicolumn{7}{@{}l}{\\textit{", heading, "}}\\\\*")
            for entry in filter(entry -> entry.rig == rig, development_inputs)
                write_lever_row(io, table, ships, entry)
            end
        end
        println(io, "\\end{longtable}")
    end
end

"the inputs of the development study that are development goals"
goal_inputs = (:canopy_making_cost_per_area, :canopy_life, :kite_out_of_service,
    :wing_out_of_service, :rotor_out_of_service)

"""
    write_lever_row(io, table, ships, entry)

One row of the development table.
"""
function write_lever_row(io, table, ships, entry)
    assumption = assumptions.entries[entry.input]
    unit = strip(assumption.unit, '"')
    carbons = [lever_gain_loss(table, ship, entry; column="carbon") for ship in ships]
    carbon = (maximum(first, carbons), minimum(last, carbons))
    estimate(value) = latex_number(round(value; sigdigits=2))
    goal = entry.input in goal_inputs ? "\\textsuperscript{g}" : ""
    println(io, uppercasefirst(entry.label), " & ", estimate(assumption.value), goal, " (",
        estimate(assumption.low), "--", estimate(assumption.high), ")",
        unit == "-" ? "" : string(" ", latex_escape(unit)), " & ",
        join([effect_cell(lever_gain_loss(table, ship, entry)) for ship in ships], " & "),
        " & ", effect_cell(carbon), " & ", entry.reason, " \\\\")
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
    crew_entry = assumptions.entries[:kite_cycle_crew_cost]
    crew = string("USD~", estimate_text(crew_entry.value), " per cycle (",
        estimate_text(crew_entry.low), " to ", estimate_text(crew_entry.high), ")")
    loss_high = assumptions.entries[:kite_cycle_damage_probability].high +
                assumptions.entries[:kite_cycle_loss_probability].high
    price = "USD~$(estimate_text(WindShipOpt.canopy_price(assumptions)))/m\$^2\$"
    today_inputs = WindShipOpt.with_today(assumptions, WindShipOpt.canopy_price_inputs)
    low, high = canopy_price_range(today_inputs, WindShipOpt.canopy_price_inputs)
    today = string("our estimate USD~",
        estimate_text(WindShipOpt.canopy_price(today_inputs)), "/m\$^2\$ (", estimate_text(low), " to ", estimate_text(high),
        "), from retail cloth and hand sewing")
    return [("Canopy life", "kite", canopy,
            "derived \\num{3800} h (\\numrange{1200}{6900}), on makers' statements; " *
            "small kites expected 100 to \\num{1000} h"),
        ("Canopy price", "kite", price, today),
        ("Rig life", "wings", years(:wing_lifetime),
            "stated design life; about 2 years on record"),
        ("Rig life", "rotors", years(:rotor_lifetime),
            "stated design life; about 8 years on record"),
        ("Out of service", "all", service,
            "our reading of one rotor operator's 97\\,\\% usable " *
            "\\citep{spliethoff2021}; nothing for kites"),
        ("Crash in flight", "kite", "none",
            string("no record for a ship; M600 lost all four kites in twenty crosswind ",
                "flights, three of them in hover or landing \\citep{echeverri2020part1}")),
        ("Unit lost", "wings, rotors", "none", "none reported, and no duty to report one"),
        ("Lost per launch and landing", "kite", loss,
            "our estimate 0.25\\,\\% (up to $(estimate_text(100loss_high))\\,\\%); " *
            "no record for a ship"),
        ("Launch and landing crew", "kite", crew,
            "an estimate, not a goal: no source gives crew time per launch")]
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
        println(io, join([join(row, " & ") for row in goal_rows()],
            " \\\\\\addlinespace\n"), " \\\\")
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
the life and price at which it passes the rig ahead; the points of saving [%] its share out
of service costs at the goal. Raises an error where the sweeps differ in a rig's goal cost.
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
each rig's outages cost, the life and price at which the kite passes the rig ahead and the
share at which all units failing together put a rig level with its rival.
"""
function missed_goals_table()
    goal_rows, crash_rows = missed_goal_rows(), crash_limit_rows()
    saving_scale = column_scale([getproperty.(goal_rows, :saving);
                                 getproperty.(crash_rows, :saving)])
    lead_scale = column_scale(getproperty.(goal_rows, :lead))
    margins = goal_margins.(goal_rows)
    margin_scales = [column_scale(getindex.(margins, k)) for k in 1:6]
    open(joinpath(sections, "missed_goals_table.tex"), "w") do io
        println(io, "\\setlength{\\tabcolsep}{4pt}")
        println(io, "\\textbf{(a)} Each rig at its best size\\par\\smallskip")
        println(io, "\\adjustbox{max width=\\textwidth}{%")
        println(io, "\\begin{tabular}{@{}llrrlrrrrrrr}")
        println(io, "\\toprule")
        println(io, " & & & & \\multicolumn{2}{c}{Against its rival} & ",
            "\\multicolumn{2}{c}{Canopy life [h] where} & ",
            "\\multicolumn{2}{c}{\\shortstack{Canopy price where\\\\",
            "{}[USD/m\\textsuperscript{2}]}} & ",
            "\\multicolumn{2}{c}{\\shortstack{Out of service where\\\\{}[\\%]}} \\\\")
        println(io, "\\cmidrule(lr){5-6}\\cmidrule(lr){7-8}\\cmidrule(lr){9-10}",
            "\\cmidrule(lr){11-12}")
        println(io, "Ship & Rig & Size [m\\textsuperscript{2}] & Cost saving [\\%] & ",
            "Rival & Lead [points] & ", join(fill("pays no more & level", 3), " & "),
            " \\\\")
        println(io, "\\midrule")
        for (row, margin) in zip(goal_rows, margins)
            shown = [round.([row.life...; row.price...]; sigdigits=2);
                     100 .* row.share...]
            limits = [shaded_cell(margin[k], margin_scales[k]; shown=shown[k],
                          format="%.0f") for k in 1:6]
            cells = [short_ship(row.ship); table_rig(row.rig); area_cell(row.area);
                     shaded_cell(row.saving, saving_scale); table_rig(row.rival);
                     shaded_cell(row.lead, lead_scale; format="\\(%+.1f\\)"); limits]
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
        println(io, "\\textbf{(b)} Crashes a year, each rig at its best size",
            "\\par\\smallskip")
        println(io, "\\adjustbox{max width=\\textwidth}{%")
        println(io, "\\begin{tabular}{@{}llrrlrrrr}")
        println(io, "\\toprule")
        println(io, " & & & & & & \\multicolumn{2}{c}{Crashes a year where} & ",
            "Flight \\\\")
        println(io, "\\cmidrule(lr){7-8}")
        println(io, "Ship & Rig & Size [m\\textsuperscript{2}] & Cost saving [\\%] & Rival & ",
            "One [kUSD] & pays no more & level & [h/year] \\\\")
        println(io, "\\midrule")
        crash_scales = [column_scale(getindex.(getproperty.(crash_rows, :crashes), k))
                        for k in 1:2]
        for row in crash_rows
            flight = row.rig == "kite" ? @sprintf("%.0f", row.flight_hours) : "--"
            crashes = [shaded_cell(sqrt(row.crashes[k]), sqrt(crash_scales[k]);
                           shown=row.crashes[k], format="%.2g") for k in 1:2]
            @printf(io, "%s & %s & %s & %s & %s & %.0f & %s & %s & %s \\\\\n",
                short_ship(row.ship), table_rig(row.rig), area_cell(row.area),
                shaded_cell(row.saving, saving_scale), table_rig(row.rival),
                round(row.crash / 1e3; sigdigits=2), crashes..., flight)
        end
        println(io, "\\bottomrule\n\\end{tabular}}")
    end
end

"`rig` as a table names it"
table_rig(rig) = rig_label(paper_name(rig))

"rig area [m^2] of a swept size, to two significant digits, as a table cell"
area_cell(area) = @sprintf("%.0f", round(area; sigdigits=2))

"`ship` without its type, for a table column"
short_ship(ship) = replace(ship, " bulk carrier" => "", " container ship" => "")

"`value` in `format`, a dash where it is not finite"
dash_cell(value, format) = isfinite(value) ? Printf.format(Printf.Format(format), value) :
                           "--"

share_cell(share) = isnan(share) ? "--" : @sprintf("%.0f", 100share)

crash_cell(crashes) = isnan(crashes) ? "--" : @sprintf("%.2g", crashes)

"""
    class_table()

Tabulars of the ship classes in class_table.tex, one above the other: their main
dimensions, deadweight and unit capacity, the limit their cargo fills first, speed, engine
power, resistance calibration and price; then cargo value, the inputs of deck cargo and
port operations and the frontal and lateral wind areas to three digits, with a dagger on
what the sources estimate. The rows of their sources go to class_sources.tex. An infinite
fixed-rig delay, where a fixed rig prevents cargo handling, is printed as ∞.
"""
function class_table()
    classes = sort(collect(values(ship_classes())); by=class -> class.deadweight)
    notes = class_source_notes()
    open(joinpath(sections, "class_sources.tex"), "w") do io
        for class in classes
            println(io, latex_escape(class.name), " & ", latex_prose(notes[class.name]),
                " \\\\")
        end
    end
    open(joinpath(sections, "class_table.tex"), "w") do io
        println(io, "\\setlength{\\tabcolsep}{3pt}")
        println(io, "\\begin{tabular}{@{}l", "r"^6, "l", "r"^4, "@{}}")
        println(io, "\\toprule")
        println(io, "Class & \$L\$ & \$B\$ & \$T\$ & \$C_B\$ & Deadweight & Capacity & ",
            "Limit & Speed & Power & \$f_R\$ & Price \\\\")
        println(io, " & [m] & [m] & [m] & & [t] & & & [kn] & [MW] & & [MUSD] \\\\")
        println(io, "\\midrule")
        foreach(class -> write_class_design_row(io, class), classes)
        println(io, "\\bottomrule\n\\end{tabular}\n\n\\medskip")
        println(io, "\\begin{tabular}{@{}l", "r"^7, "@{}}")
        println(io, "\\toprule")
        estimate = "\$^\\dagger\$"
        println(io, "Class & Cargo value & Deck & Air draft$estimate & Lost$estimate & ",
            "Fixed-rig$estimate & \$A_\\mathrm{F}\$ & \$A_\\mathrm{L}\$ \\\\")
        println(io, " & [USD/t] & tiers & limit [m] & calls [\\%] & delay [h] & ",
            "[m\$^2\$] & [m\$^2\$] \\\\")
        println(io, "\\midrule")
        for class in classes
            write_class_cargo_row(io, class, estimated_fields(notes[class.name]))
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    write_class_design_row(io, class)

One row of the design part of the ship class table.
"""
function write_class_design_row(io, class)
    println(io, latex_escape(class.name), " & ", latex_number(class.length), " & ",
        dash_cell(class.beam, "\\num{%.1f}"), " & ", dash_cell(class.draft, "\\num{%.1f}"),
        " & ", dash_cell(class.block_coefficient, "\\num{%.2f}"), " & ",
        latex_number(class.deadweight), " & ", unit_capacity(class), " & ",
        limit_label(class), " & ", dash_cell(class.service_speed, "\\num{%.1f}"), " & ",
        dash_cell(class.power / 1e3, "\\num{%.1f}"), " & ",
        dash_cell(Hull(class, assumptions).resistance_factor, "\\num{%.2f}"), " & ",
        dash_cell(class.newbuild_price / 1e6, "\\num{%.1f}"), " \\\\")
end

"""
    write_class_cargo_row(io, class, estimated)

One row of the cargo and operations part of the ship class table, with a dagger on the
cargo value where it is among the `estimated` fields of the class's source note.
"""
function write_class_cargo_row(io, class, estimated)
    delay = isfinite(class.fixed_rig_port_hours) ?
            latex_number(class.fixed_rig_port_hours) : "\$\\infty\$"
    mark = "cargo value" in estimated ? "\\rlap{\$^\\dagger\$}" : ""
    windage = WindShipOpt.Windage(class, assumptions)
    println(io, latex_escape(class.name), " & ", latex_number(class.cargo_value), mark,
        " & ", latex_number(class.deck_tiers), " & ", latex_number(class.air_draft_limit),
        " & ",
        latex_number(round(100class.restricted_call_share; digits=1)), " & ", delay, " & ",
        latex_number(round(Int, round(windage.frontal_area; sigdigits=3))), " & ",
        latex_number(round(Int, round(windage.lateral_area; sigdigits=3))), " \\\\")
end

"""
    estimated_fields(note)

Names of the fields that the source `note` of a ship class gives as an estimate.
"""
function estimated_fields(note)
    fields = String[]
    for part in split(note, "; ")
        names, text = (split(part, ": "; limit=2)..., "")
        occursin("estimate", text) && append!(fields, strip.(split(names, r"[,/]")))
    end
    return fields
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
the project's own notes, with the currency of its prices in millions and the unit of its
lengths overall.
"""
function class_source_notes()
    lines = readlines(joinpath(root, "data", "ship_classes.csv"))
    header = WindShipOpt.csv_fields(first(lines))
    notes = Dict{String, String}()
    for line in lines[2:end]
        row = Dict(zip(header, WindShipOpt.csv_fields(line)))
        notes[row["name"]] = replace(row["source"], r" \([^()]*notes\)" => "",
            r"(?<![\w.])(\d+(?:\.\d+)?) M\b" => s"USD \1 M",
            r"\bLOA (\d+(?:\.\d+)?)" => s"LOA \1 m")
    end
    return notes
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
        splits = rig_splits(table, drive, rig)
        hours = getproperty.(splits, :hours)
        push!(lines, (; label=k == 1 ? label : "", rig, points=split_points(splits),
            shorter=100count(<(0), hours) / length(hours), trip=median(hours)))
    end
    cells = split_cells(lines)
    trip_scale = column_scale([line.trip for line in lines])
    open(joinpath(sections, "split_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}llrrrrrr}\n\\toprule")
        println(io, " & & Saving & Fuel & Time & Rig and other & Shorter & ",
            "Round trip \\\\")
        println(io, "Drive & Rig & [\\%] & [points] & [points] & [points] & [\\%] & ",
            "[\\%] \\\\\n\\midrule")
        for (line, shaded) in zip(lines, cells)
            @printf(io, "%s & %s & %s & %.0f & %s \\\\\n", line.label, line.rig, shaded,
                line.shorter, shaded_cell(-line.trip, trip_scale; shown=line.trip))
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    shaded_cell(value, scale; shown=value, format="%.1f", lightest=0)

Table cell of `shown` in `format`, a dash where it is not finite, on a background of the
paper's gain colour where `value` is positive and its loss colour where negative, from
`lightest` to 40 % deep the larger `value` is against `scale`; plain where `value` is zero
or not finite.
"""
function shaded_cell(value, scale; shown=value, format="%.1f", lightest=0)
    text = dash_cell(shown, format)
    isfinite(value) && value != 0 || return text
    depth = round(Int, lightest + (40 - lightest) * min(abs(value) / scale, 1))
    return @sprintf("\\cellcolor{%s!%d}%s", value > 0 ? "gain" : "loss", depth, text)
end

"largest finite `abs` of `values`, the scale of a shaded column; 1 where none is finite"
column_scale(values) = maximum(abs, filter(isfinite, values); init=0.0) |>
                       scale -> scale > 0 ? scale : 1.0

"""
    cargo_interest_table()

Tabular of the cost saving of the cheapest size of each rig on the zero-emission drive at
low and at high cargo interest, the mean over the classes and routes, split by
[`saving_split`](@ref) into fuel, time and the rest, with the median change of the round
trip and the mean [`speed_along_track`](@ref) of the ship with and without the rig, in
cargo_interest_table.tex.
"""
function cargo_interest_table()
    table = read_table(data_file("cargo_interest.csv"))
    drive = string(last(study_drives))
    lines = []
    for (level, factor) in pairs(cargo_interest_factors())
        level_table = interest_level_rows(table, factor)
        push!(lines, (; level, rig="no rig", points=fill(NaN, 4), trip=NaN,
            speed=mean_sailing_speed(level_table, drive, "none")))
        for rig in rig_names
            splits = rig_splits(level_table, drive, rig)
            push!(lines, (; level="", rig, points=split_points(splits),
                trip=median(getproperty.(splits, :hours)),
                speed=mean_sailing_speed(level_table, drive, rig)))
        end
    end
    cells = split_cells(lines)
    trip_scale = column_scale([line.trip for line in lines])
    open(joinpath(sections, "cargo_interest_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}llrrrrrr@{}}\n\\toprule")
        println(io, "Cargo & & Saving & Fuel & Time & Rig and other & Round trip & ",
            "Speed \\\\")
        println(io, "interest & Rig & [\\%] & [points] & [points] & [points] & [\\%] & ",
            "[kn] \\\\\n\\midrule")
        for (line, shaded) in zip(lines, cells)
            @printf(io, "%s & %s & %s & %s & %.1f \\\\\n", line.level, line.rig, shaded,
                shaded_cell(-line.trip, trip_scale; shown=line.trip), line.speed)
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    split_points(splits)

Mean over `splits` of the saving and its parts in points: `[saving, fuel, time, rest]`.
"""
function split_points(splits)
    saving, fuel, time = (mean(getproperty.(splits, part))
                          for part in (:saving, :fuel, :time))
    return [saving, fuel, time, saving - fuel - time]
end

"""
    split_cells(lines)

The four shaded split columns of each of `lines`, joined for a table row, every column
against its own largest value.
"""
function split_cells(lines)
    scales = [column_scale([line.points[k] for line in lines]) for k in 1:4]
    return [join(shaded_cell.(line.points, scales), " & ") for line in lines]
end

"""
    rig_splits(table, drive, rig)

The [`saving_split`](@ref) of every class and route of `table` that has a trip of `rig`
on `drive`.
"""
function rig_splits(table, drive, rig)
    return filter(!isnothing, [saving_split(table, class, route, drive, rig)
                               for class in class_order(table)
                               for route in unique(table["route"])])
end

"""
    mean_sailing_speed(table, drive, rig)

Mean [`speed_along_track`](@ref) [kn] of the cheapest size of `rig`, or of the ship without
a rig for `"none"`, over the classes and routes of `table`.
"""
function mean_sailing_speed(table, drive, rig)
    cheapest = [cheapest_row(table, class, route, drive, rig)
                for class in class_order(table) for route in unique(table["route"])]
    speeds = [speed_along_track(table["sailed_km"][k], table["days"][k])
              for k in cheapest if !isnothing(k)]
    return mean(speeds)
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
    mean_savings(table, columns, classes, drive, rig; routes=unique(table["route"]))

Mean over `classes` and `routes` of the class table `table` of the saving [%] in each of
`columns` of the cheapest size of `rig` on `drive`, over the cases where all are known;
`NaN` for each where none is.
"""
function mean_savings(table, columns, classes, drive, rig; routes=unique(table["route"]))
    savings = [[cheapest_saving(table, column, class, drive, route, rig)
                for column in columns]
               for class in classes for route in routes]
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
        println(io, "\\begin{tabular}{@{}l", "r"^(3length(drive_labels)), "}")
        println(io, "\\toprule\n & ", drive_header(2))
        println(io, "Class & ", rig_header())
        println(io, "\\midrule")
        for class in class_order(table)
            cells = [shaded_cell(1 / years, scale; shown=payback_shown(years),
                         format=payback_shown(years) < 2 ? "%.1f" : "%.0f")
                     for years in medians[class]]
            println(io, latex_escape(class), " & ", join(cells, " & "), " \\\\")
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"payback `years` as the table gives it: to the half year below two years, else whole"
payback_shown(years) = years < 2 ? round(2years) / 2 : round(years)

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
        @sprintf("\\(%.0f\\)",
            sum(table["thrust_hours"][kite]) / sum(table["flying"][kite])),
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
            "Force alone \\\\\n\\midrule")
        for (drive, drive_label) in drive_labels[1:2], rig in ("kite", "wings", "rotors")
            found = rows(table, "drive" => drive, "rig" => rig)
            cells = (@sprintf("%.1f", median(table[column][found])) for column in columns)
            println(io, rig == "kite" ? drive_label : "", " & ", rig, " & ",
                join(cells, " & "), " \\\\")
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"share of `rig`'s cost saving kept on `plan` with its error [%], in LaTeX; `--` if not run"
function kept_cell(table, rig, plan)
    found = rows(table, "rig" => rig, "plan" => plan)
    isempty(found) && return "--"
    return @sprintf("\\(%.0f \\pm %.0f\\)", 100table["kept"][only(found)],
        100table["kept_error"][only(found)])
end

"change of `rig`'s kept share on `plan` from the control with its paired error [points]"
function kept_change_cell(table, rig, plan)
    found = only(rows(table, "rig" => rig, "plan" => plan))
    change = round(Int, 100table["difference_from_control"][found])
    return @sprintf("\\(%+d \\pm %.0f\\)", change, 100table["difference_error"][found])
end

"""
    forecast_plans_table()

Share of each rig's perfect-foresight cost saving kept per plan of the forecast study, with
its standard error over the departures [%], and that of the kite held to its plan, the
plans on the draft's grid and on a fine grid near the ship apart:
forecast_plans_table.tex.
"""
function forecast_plans_table()
    write_kept_table("forecast_plans_kept.csv", "forecast_plans_table.tex",
        (("On the draft's route grid", (("true", "One forecast run"),
                ("mean", "Ensemble mean"), ("margin", "Margin for wind"),
                ("members", "Several members"),
                ("held_kite", "One forecast run, kite held to the plan"),
                ("kite_margin",
                    "One forecast run, kite limits 20\\,\\% tighter in the plan"),
                ("expected", "One forecast run, wind error weighed"))),
            ("On a fine grid near the ship", (("grid_perfect", "Perfect foresight"),
                ("grid", "One forecast run"), ("grid_expected", "Wind error weighed")))))
end

"""
    forecast_replanning_table()

Share of each rig's perfect-foresight cost saving kept per case of the re-planning study,
with its standard error over the departures [%], and its paired change from the plan it
differs from in one thing [points]: forecast_replanning_table.tex.
"""
function forecast_replanning_table()
    plans = (("true", "Reforecast, about every 29 h"),
        ("operational_24h", "Operational, about every 29 h"),
        ("operational_12h", "Operational, about every 18 h"),
        ("operational_6h", "Operational, about every 10 h"),
        ("operational_24h_speed", "About every 29 h, speed adapted"),
        ("operational_24h_course", "About every 29 h, speed and course adapted"),
        ("operational_6h_course", "About every 10 h, speed and course adapted"))
    write_kept_table("forecast_replanning_kept.csv", "forecast_replanning_table.tex",
        ((nothing, plans),); changes=(
            heading="Change from operational, about every 29 h, unless stated [points]",
            plans=(plans[1], plans[3], plans[4], plans[5], plans[6],
                ("operational_6h_course", "About every 10 h, adapted, from unadapted"))))
end

"""
    write_kept_table(data_name, table_name, blocks; changes=nothing)

Write `table_name` from the kept shares in `data_name`: per (heading, plans) of `blocks` the
heading, where there is one, and a row per (plan, label) of its plans, a column per rig,
then under `changes.heading` a row per (plan, label) of `changes.plans` with the paired
change from the data's control.
"""
function write_kept_table(data_name, table_name, blocks; changes=nothing)
    table = read_table(data_file(data_name))
    rigs = ("kite", "wings", "rotors")
    open(joinpath(sections, table_name), "w") do io
        println(io, "\\begin{tabular}{@{}lccc@{}}\n\\toprule")
        println(io, "Plan & Kite & Wing sails & Rotors \\\\\n\\midrule")
        for (heading, plans) in blocks
            isnothing(heading) ||
                println(io, "\\multicolumn{4}{@{}l}{\\textit{", heading, "}} \\\\")
            indent = isnothing(heading) ? "" : "\\quad "
            for (plan, label) in plans
                cells = [kept_cell(table, rig, plan) for rig in rigs]
                println(io, indent, label, " & ", join(cells, " & "), " \\\\")
            end
        end
        if !isnothing(changes)
            println(io, "\\midrule\n\\multicolumn{4}{@{}l}{\\textit{", changes.heading,
                "}} \\\\")
            for (plan, label) in changes.plans
                cells = [kept_change_cell(table, rig, plan) for rig in rigs]
                println(io, "\\quad ", label, " & ", join(cells, " & "), " \\\\")
            end
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    forecast_hours_table()

Hours per round trip of the kite ship over the departures of forecast_hours.csv with their
standard error, per plan: forecast_hours_table.tex.
"""
function forecast_hours_table()
    table = read_table(data_file("forecast_hours.csv"))
    plans = (("false", "Perfect foresight"), ("true", "One run"),
        ("members", "Several members"), ("kite_margin", "Limits 20\\,\\% tighter"))
    rows = (("Passage [d]", "days"), ("Distance [nmi]", "distance"),
        ("Hours at the commanded speed", "commanded"), ("Hours holding", "held"),
        ("Hours aloft", "up"), ("Too little wind", "too_little_wind"),
        ("\\quad no one speed launches it", "too_little_wind_no_speed"),
        ("\\quad a speed does, without paying", "too_little_wind_no_pay"),
        ("\\quad a speed pays, over the whole edge too", "too_little_wind_pays_edge"),
        ("\\quad a speed pays, only within the edge", "too_little_wind_pays_stretch"),
        ("No forward pull", "no_forward_pull"), ("Too much wind", "too_much_wind"),
        ("Hull limit", "hull_limit"), ("Sea", "sea"), ("No saving", "no_saving"),
        ("Stayed down by choice", "chosen"), ("Wanted up, not flown", "wanted_not_flown"),
        ("Fast sailing", nothing), ("\\quad possible", "fast_real"),
        ("\\quad forecast", "fast_known"),
        ("\\quad possible, whole edge", "fast_real_edge"),
        ("\\quad forecast, whole edge", "fast_known_edge"),
        ("\\quad commanded", "fast_commanded"), ("\\quad held", "fast_held"),
        ("Fuel, kite down [GJ]", "fuel_down"), ("Fuel, kite aloft [GJ]", "fuel_up"),
        ("Fuel saved aloft [GJ]", "saved"),
        ("Saved by a speed change within the stretch [USD]", "saved_within_stretch"))
    open(joinpath(sections, "forecast_hours_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}l", "c"^length(plans), "@{}}\n\\toprule")
        println(io, "Per round trip & ", join(last.(plans), " & "),
            " \\\\\n\\midrule")
        for (label, column) in rows
            cells = [isnothing(column) ? "" : hours_cell(table, plan, column)
                     for (plan, _) in plans]
            println(io, label, " & ", join(cells, " & "), " \\\\")
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    hours_cell(table, plan, column)

Mean and standard error over the departures of `column` of `plan`, as a table cell, the
error to two significant digits and both to the same place, whole units at the finest.
"""
function hours_cell(table, plan, column)
    values = table[column][rows(table, "plan" => plan)]
    error = std(values) / sqrt(length(values))
    place = error < 10 ? 0 : floor(Int, log10(round(error; sigdigits=2))) - 1
    rounded(value) = round(Int, round(value; digits=-place))
    return @sprintf("\\(%d \\pm %d\\)", rounded(mean(values)), rounded(error))
end

"groups of forecast_causes_table.tex as (heading, rows of (label, statistic))"
forecast_cause_groups = (
    ("Cost saving [\\%]",
        (("With perfect foresight", cause_saving(:perfect)),
            ("Re-planned daily on the forecasts", cause_saving(:forecast)))),
    ("Cost saving lost [points]",
        (("Total", cause_loss(:perfect, :forecast)),)),
    ("Of which, course first",
        (("Course", cause_loss(:perfect, :forecast_course)),
            ("Re-planning once a day, on the forecast's course",
                cause_loss(:forecast_course, :forecast_course_replanned)),
            ("Speed", cause_loss(:forecast_course_replanned, :foresight_kite)),
            ("The kite's flying decisions", cause_loss(:foresight_kite, :forecast)))),
    ("Of which, course last",
        (("Re-planning once a day, on the course of perfect foresight",
                cause_loss(:perfect, :perfect_course_replanned)),
            ("Speed and the kite's flying decisions",
                cause_loss(:perfect_course_replanned, :perfect_course)),
            ("Course", cause_loss(:perfect_course, :forecast)))),
    ("Of which, by what the forecast gets wrong",
        (("Re-planning once a day, routed", cause_loss(:perfect, :replanned)),
            ("Forecast model against the reanalysis",
                cause_loss(:replanned, :shortest_lead)),
            ("Error growing with lead time", cause_loss(:shortest_lead, :forecast)))),
    ("After re-planning, by the weather forecast, waves first",
        (("Wave forecast", cause_loss(:replanned, :wave_forecast)),
            ("Wind forecast, inside the common wind-speed band",
                cause_loss(:wave_forecast, :wind_near_limit)),
            ("Wind forecast, outside that band",
                cause_loss(:wind_near_limit, :forecast)))),
    ("After re-planning, by the weather forecast, waves last",
        (("Wind forecast", cause_loss(:replanned, :wind_forecast)),
            ("Wave forecast", cause_loss(:wind_forecast, :forecast)))),
    ("On one fixed course for every rig",
        (("Cost saving with perfect foresight [\\%]", cause_saving(:common_perfect)),
            ("Cost saving on the forecasts [\\%]", cause_saving(:common_forecast)),
            ("Cost saving lost [points]", cause_loss(:common_perfect, :common_forecast)),
            ("Loss added by routing on foresight [points]",
                cause_difference(cause_loss(:perfect, :forecast),
                    cause_loss(:common_perfect, :common_forecast))))),
    ("Share of the cost saving kept [\\%]",
        (("Routed", cause_kept(:forecast, :perfect)),
            ("On the fixed course", cause_kept(:common_forecast, :common_perfect)))))

"""
    kite_margin_estimate(margins, column)

Mean over the departures on the control forecast, as a [`cause_estimate`](@ref), of the
share [%] in `column` of forecast_margins.csv read into `margins`.
"""
function kite_margin_estimate(margins, column)
    rows = findall(==("forecast"), margins["knowledge"])
    shares = Dict(:share => 100 .* margins[column][rows])
    return cause_estimate(cause_saving(:share), shares)
end

"""
    cause_cell(estimate)

LaTeX of an (value, error) estimate of [`cause_estimate`](@ref), the error to two
significant digits, one decimal at the finest, and the value to the same place.
"""
function cause_cell(estimate)
    digits = estimate.error < 9.95 ? 1 : 0
    return Printf.format(Printf.Format("\\(%.$(digits)f \\pm %.$(digits)f\\)"),
        round(estimate.value; digits) + 0.0, estimate.error)
end

"""
    forecast_causes_table()

Per rig the cost saving lost on the archived forecasts per cause, and the kite's excess over
the wing sails and the rotors paired per departure, each with its standard error over the
departures of forecast_causes.csv: forecast_causes_table.tex.
"""
function forecast_causes_table()
    table = read_table(data_file("forecast_causes.csv"))
    saved = Dict(rig => forecast_cause_savings(table, rig)
                 for rig in ("kite", "wings", "rotors"))
    open(joinpath(sections, "forecast_causes_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}lccccc@{}}\n\\toprule")
        println(io, " & Kite & Wing sails & Rotors & Kite less wing sails & ",
            "Kite less rotors \\\\\n\\midrule")
        for (heading, group) in forecast_cause_groups
            println(io, "\\multicolumn{6}{@{}l}{\\textit{", heading, "}} \\\\")
            for (label, statistic) in group
                cells = [[cause_estimate(statistic, saved[rig])
                          for rig in ("kite", "wings", "rotors")];
                    [cause_estimate(statistic, saved["kite"], saved[rig])
                     for rig in ("wings", "rotors")]]
                println(io, "\\quad ", label, " & ", join(cause_cell.(cells), " & "),
                    " \\\\")
            end
        end
        margins = read_table(data_file("forecast_margins.csv"))
        println(io, "\\multicolumn{6}{@{}l}{\\textit{The kite's time near its limits on ",
            "the forecasts, of the time at sea unless stated [\\%]}} \\\\")
        for (label, column) in kite_margin_rows
            println(io, "\\quad ", label, " & ",
                cause_cell(kite_margin_estimate(margins, column)), " & & & & \\\\")
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
        println(io, "\\begin{tabular}{@{}llrrrrrr}\n\\toprule")
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
        for (k, (drive_label, label, fuel, hours)) in enumerate(lines)
            cells = [shaded_cell.(fuel, fuel_scale); shaded_cell.(hours, time_scale)]
            first_of_drive = k == 1 || lines[k - 1][1] != drive_label
            println(io, first_of_drive ? drive_label : "", " & ", label, " & ",
                join(cells, " & "), " \\\\")
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
citation key, the speed [kn], its label in the table, the fuel saving they state [%] and
what it covers where that is narrower than a year of trips.
"""
published_savings = [("podeur2016", 16.0, "\\citet{podeur2016}", "12.1", ""),
    ("podeur2016", 19.0, "\\citet{podeur2016}", "6.6", ""),
    ("bentin2018", 13.0, "\\citet{bentin2018}", "19--29", "routed"),
    ("leloup2013", 8.0, "\\citet{leloup2013}", "23.5", "downwind in one wind"),
    ("leloup2013", 15.5, "\\citet{leloup2013}", "26.6", "one crossing"),
    ("cedelft2016", 10.5, "\\citet{cedelft2016}", "2--15", ""),
    ("cedelft2016", 12.3, "\\citet{cedelft2016}", "1--9", ""),
    ("traut2014", 11.2, "\\citet{traut2014}", "1--32", "")]

"""
    published_table()

Published fuel savings of kites at fixed speed beside our model at that speed on the nearest
of our ships, priced and free of the kite's running cost, and the routed saving and time of
our cost-optimal speed: published_table.tex.
"""
function published_table()
    table = read_table(data_file("published_terms.csv"))
    open(joinpath(sections, "published_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}llrrrrrl@{}}\n\\toprule")
        println(io, "Study & Our ship & Kite & Speed & Published & ",
            "\\multicolumn{2}{c}{Ours [\\%]} & Covers \\\\")
        println(io, "\\cmidrule(lr){6-7}")
        println(io, " & & [\\si{m^2}] & [kn] & [\\%] & priced & free & \\\\\n\\midrule")
        for (source, knots, label, published, scope) in published_savings
            found = rows(table, "source" => source, "speed" => knots)
            isempty(found) && continue
            i = only(found)
            saving(column) = @sprintf("%.1f",
                100(1 - table[column][i] / table["fuel_bare"][i]))
            println(io, join((label, table["ship"][i], @sprintf("%.0f", table["area"][i]),
                    @sprintf("%g", knots), published, saving("fuel_kite"),
                    saving("fuel_free"), scope), " & "), " \\\\")
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
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
            "\\multicolumn{2}{c}{Most cost saved} & Largest up \\\\")
        println(io, "\\cmidrule(lr){5-6}\\cmidrule(lr){7-9}\\cmidrule(lr){10-11}")
        println(io, " & & [kn] & [GJ] & [\\%] & [GJ] & [\\si{m^2}] & [\\%] & [GJ] & ",
            "[\\si{m^2}] & [\\%] & [\\%] \\\\")
        println(io, "\\midrule")
        lines = []
        for grid in speed_size_grid, drive in string.(grid.drives), knots in grid.speeds
            routes = speed_size_routes(table, grid, drive, knots)
            saving(area, pricing) = speed_size_saving(table, grid.ship, drive, routes, "kite",
                area, pricing, knots)
            free = [saving(area, "free") for area in grid.kites]
            priced = [saving(area, "priced") for area in grid.kites]
            (any(isnothing, free) || any(isnothing, priced)) && continue
            most_fuel = argmax(i -> free[i].fuel, eachindex(free))
            most_cost = argmax(i -> priced[i].cost_percent, eachindex(priced))
            push!(lines, (; grid.ship, drive, knots, bare=free[1].bare_fuel,
                smallest=free[1], most_fuel=free[most_fuel],
                fuel_area=grid.kites[most_fuel], cost_area=grid.kites[most_cost],
                cost=priced[most_cost].cost_percent,
                flight=free[end].flight))
        end
        fuel_scale = column_scale(getproperty.(getproperty.(lines, :most_fuel),
            :fuel_percent))
        cost_scale = column_scale(getproperty.(lines, :cost))
        function signed(value, scale)
            shown = round(value; digits=1) + 0.0
            return shaded_cell(shown == 0 ? 0.0 : value, scale; shown,
                format="\\(%.1f\\)", lightest=12)
        end
        for line in lines
            println(io, join((line.ship == "140 m" ? "140 m ship" : line.ship,
                    Dict(drive_labels)[line.drive], @sprintf("%.0f", line.knots),
                    @sprintf("%.0f", line.bare),
                    signed(line.smallest.fuel_percent, fuel_scale),
                    @sprintf("%.0f", line.smallest.fuel), @sprintf("%.0f", line.fuel_area),
                    signed(line.most_fuel.fuel_percent, fuel_scale),
                    @sprintf("%.0f", line.most_fuel.fuel), @sprintf("%.0f", line.cost_area),
                    signed(line.cost, cost_scale), @sprintf("%.0f", line.flight)),
                " & "), " \\\\")
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end


"""
    fidelity_parts()

Each part of the model as (part, varied, model, error, effect): its name, how its effect is
measured, how it is modelled, its known error, and the data file with the groups of
condition sets whose results [`part_effect`](@ref) compares, `nothing` for a part with no
measured effect.
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
        model="Blendermann's loading functions on the frontal and lateral area, with " *
              "side force and yaw moment",
        error="loading functions by ship type, not measured on these ships",
        effect=switched(:windage)),
    (part="Heel, leeway and rudder limits", varied="removed",
        model="steady balance; side force beyond the limits is shed by trimming the rig",
        error="limits are design rules, not measured", effect=switched(:limits)),
    (part="Leeway and rudder drag", varied="rudder drag off",
        model="Kijima side force slope; rudder as a lifting line carrying the yaw moment",
        error="hull side force from regression, not from tests of these hulls",
        effect=switched(:rudder)),
    (part="Propeller and engine", varied="not measured",
        model="actuator disk with viscous loss; engine efficiency falling at part load",
        error="no open-water curve of a real propeller",
        effect=nothing),
    (part="Wind at height", varied="not measured",
        model="one power-law profile from 10\\,m, the mean of ERA5 over the region",
        error="real shear varies with stability from hour to hour",
        effect=nothing),
    (part="Wing sail forces", varied="maximum lift",
        model="lifting line with stall, trimmed at each wind; array factor of the units",
        error="interference fitted to CFD of three to four sails",
        effect=varied_inputs(:wing_max_lift_coefficient)),
    (part="Rotor forces", varied="lift and highest wind",
        model="ShipCLEAN coefficients over spin ratio, trimmed at each wind; array factor",
        error="fit to CFD and full-scale data within its scatter; interference from two " *
              "to four rotors",
        effect=varied_inputs(:rotor_lift_factor, :rotor_max_wind)),
    (part="Kite flight", varied="turn radius, drag, force limit",
        model="quasi-steady pattern with mass, bridle and tether drag, searched for each " *
              "wind and course",
        error="glide ratio of 4 matched to flight data",
        effect=varied_inputs(:kite_min_turn_radius, :kite_flight_drag,
            :kite_max_force_per_area)),
    (part="Kite launch and sea limits", varied="wind limits, extra launch wind in a sea",
        model="fixed wind limits for launch, flight and landing; launch wind raised with " *
              "the launch mast's motion in the sea",
        error="extra launch wind scaled on one reported pair of wind speeds",
        effect=varied_inputs(:kite_launch_sea_wind, :kite_launch_min_wind,
            :kite_launch_max_wind, :kite_landing_max_wind, :kite_max_wind)),
    (part="Wear and availability", varied="canopy life, out of service",
        model="canopy life from UV and wear per flight hour; launch damage and loss; " *
              "time out of service for every rig",
        error="canopy wear rate from paragliders, not from towing kites",
        effect=varied_inputs(:canopy_life, :kite_out_of_service, :wing_out_of_service,
            :rotor_out_of_service)),
    (part="Rig prices", varied="prices per area",
        model="price per area and per unit, installation, maintenance",
        error="ranges of the quoted and built-up prices",
        effect=varied_inputs(:canopy_making_cost_per_area, :wing_cost_per_area,
            :rotor_cost_per_area)),
    (part="Weather sample", varied="each year alone",
        model="ERA5 2017 to 2019, a departure every 6\\,h",
        error="three years against a climate", effect=weather_years()),
    (part="Router", varied="corridor grid",
        model="dynamic programming over a corridor grid of positions and speeds",
        error="a finer corridor and search raise a kite or rotor saving by up " *
              "to 2.4 points",
        effect=corridor_grids()),
    (part="Rig size search", varied="every size",
        model="three sizes, then two by interpolation",
        error="the loss against the best of every size, shown here",
        effect=size_search_grid()),
]

"the whole model and the model with `part` off, in the model-part study"
switched(part) =
    ("model_parts.csv", "ship", [[("part" => "none",), ("part" => string(part),)]])

"for each of `inputs` of the development study, the base and both of its bounds"
function varied_inputs(inputs...)
    issubset(inputs, (entry.input for entry in development_inputs)) ||
        error("not all of $inputs are in the development study")
    return ("sensitivity.csv", "ship",
    [[("input" => "none", "bound" => "value"); [("input" => string(input), "bound" => bound)
                                                for bound in ("low", "high")]]
     for input in inputs])
end

"each weather year"
weather_years() = ("weather_years.csv", "ship",
    [[("year" => year,) for year in 1:ceil(Int, last(departures) / 8760)]])

"each corridor scale of the convergence study, on its one ship"
corridor_grids() =
    ("convergence.csv", nothing, [[("scale" => scale,) for scale in convergence_scales]])

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
            if isnothing(effect)
                @printf(io, "%s {\\itshape (%s)} & %s & -- & -- & -- & -- & %s \\\\\n",
                    part, varied, model, error)
                continue
            end
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
the goals, and the [`class_numbers`](@ref), [`recommendation_numbers`](@ref),
[`rig_lead_numbers`](@ref), [`premium_numbers`](@ref) and [`fleet_share_numbers`](@ref) of
the class study.
"""
function numbers_file()
    classes = read_table(data_file("classes.csv"))
    results = [class_numbers(classes); recommendation_numbers(classes);
               rig_lead_numbers(classes); premium_numbers(classes);
               fleet_share_numbers(classes)]
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
    "CanopyPriceGoal" => estimate_text(WindShipOpt.canopy_price(assumptions)),
    "CanopyPriceToday" => estimate_text(WindShipOpt.canopy_price_today(assumptions)),
    "OutOfServiceGoal" => @sprintf("%.0f", 100out_of_service_goal())]

"""
    class_numbers(classes)

Name and text, per drive and rig, of the mean over the classes and routes of the class
table `classes` of the cost saving [%] of the cheapest size, and of the cells of class
and route where the rig leads by [`fleet_band`](@ref), with the counts of cells and of
level cells.
"""
function class_numbers(classes)
    numbers = Pair{String, String}[]
    for (drive, word) in drive_words
        cells = filter(!isempty, [best_savings(classes, class, route, drive)
                                  for class in class_order(classes)
                                  for route in unique(classes["route"])])
        bands = fleet_band.(cells)
        push!(numbers, "Cells$word" => string(length(cells)),
            "Level$word" => string(count(==("level"), bands)))
        for rig in rig_names
            name = word * uppercasefirst(rig)
            push!(numbers, "Saving$name" => whole_number(
                    mean(cell[rig] for cell in cells if haskey(cell, rig))),
                "Leads$name" => string(count(==(rig), bands)))
        end
    end
    return numbers
end

"""
    fleet_share_numbers(table)

Name and text, per drive of the class table `table`, of each band's share [%] of the
yearly cost of carrying the fleet's cargo, the totals of that cost and of the saving
[billion USD], the shares of the IMO transport work and of shipping's CO2 the classes
carry, and the [`level_margin`](@ref).
"""
function fleet_share_numbers(table)
    numbers = Pair{String, String}[]
    for (drive, word) in drive_words
        split = fleet_split_of(table, drive)
        bill = fleet_total(split, :bill)
        push!(numbers, "FleetBill$word" => whole_number(bill / 1e9),
            "FleetSaved$word" => whole_number(fleet_total(split, :saved) / 1e9))
        for band in fleet_bands
            name = word * uppercasefirst(band)
            push!(numbers, "FleetShare$name" => whole_number(100split[band].bill / bill))
        end
    end
    _, work_share = fleet_work()
    fuel_share = read_table(joinpath(root, "data", "ship_classes.csv"))["fuel_share"]
    push!(numbers, "FleetWorkShare" => whole_number(100work_share),
        "FleetFuelShare" => whole_number(100sum(fuel_share)),
        "FleetLevelMargin" => whole_number(level_margin))
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

"kinds of ship the paper recommends a rig for: word in number macros, label, ship types"
ship_types = (("Container", "Container ships", ("container",)),
    ("CarCarrier", "Car carriers", ("vehicle carrier",)),
    ("BulkCarrier", "Bulk carriers", ("bulk carrier",)),
    ("Tanker", "Tankers", ("oil product tanker", "crude oil tanker")),
    ("GeneralCargo", "General cargo ships", ("general cargo",)))

"""
    rig_lead(table, classes, drive)

Of the [`mean_savings`](@ref) of the cost [%] of each rig over `classes` and routes in the
class table `table`: the rig saving most, its rival saving next most, the margin between
them [points] and the lead of the kite over the rotors [points].
"""
function rig_lead(table, classes, drive)
    savings = Dict(rig => only(mean_savings(table, ("cost",), classes, drive, rig))
                   for rig in rig_names)
    (; rig, rival) = first(WindShipOpt.ranked_rivals(Dict(rig => -saving
                                                          for (rig, saving) in savings)))
    return (; rig, rival, margin=savings[rig] - savings[rival],
        kite_lead=savings["kite"] - savings["rotors"])
end

"""
    priced_kite(area, class)

Kite of `area` [m^2] for a ship of `class` built for what it costs, flying no course.
"""
function priced_kite(area, class)
    return KiteRig(area, design_aspect_ratio, Hull(class, assumptions), assumptions;
        courses=Float64[])
end

"""
    kite_goal_points(table, class, route, drive)

Points of cost saving, with the cheapest kite and its flying held, that its canopy costs per
unit of inverse canopy life and that one kite lost a year costs; `nothing` without the trip.
"""
function kite_goal_points(table, class, route, drive)
    bare = rows(table, "class" => class, "drive" => drive, "route" => route,
        "rig" => "none")
    row = cheapest_row(table, class, route, drive, "kite")
    (isempty(bare) || isnothing(row)) && return nothing
    rig = priced_kite(table["area"][row], ship_classes()[class])
    work, trips = yearly_trips(table, row, route)
    points_per_usd = 100 / (work * only(table["cost"][bare]))
    hours = table["flight_share"][row] * 24table["days"][row] * trips
    return (canopy=first(WindShipOpt.consumable_costs(rig, assumptions)) * hours *
                   points_per_usd,
        crash=WindShipOpt.crash_cost(rig, assumptions) * points_per_usd)
end

"""
    kite_limits(table, classes, drive, lead)

[`WindShipOpt.lead_limits`](@ref) of the kite's `lead` over the rotors on `classes`, the
costs of its goals the mean over their routes of [`kite_goal_points`](@ref).
"""
function kite_limits(table, classes, drive, lead)
    points = filter(!isnothing, [kite_goal_points(table, class, route, drive)
                                 for class in classes for route in unique(table["route"])])
    return WindShipOpt.lead_limits(lead, assumptions[:canopy_life],
        mean(point.canopy for point in points), mean(point.crash for point in points))
end

"""
    rig_lead_rows(table)

For each of `ship_types` and drive of the class table `table`: its words and label, the
[`rig_lead`](@ref) and the canopy life [h] and kites lost a year of [`kite_limits`](@ref).
"""
function rig_lead_rows(table)
    classes = ship_classes()
    return [begin
                names = [name for name in class_order(table) if classes[name].type in types]
                lead = rig_lead(table, names, drive)
                (; word, label, drive, drive_word, lead...,
                    kite_limits(table, names, drive, lead.kite_lead)...)
            end
            for (word, label, types) in ship_types for (drive, drive_word) in drive_words]
end

"""
    life_limit_text(life)

Text of the canopy life [h] `life`, to the hundred; a dash where the kite has no lead.
"""
life_limit_text(life) = isnan(life) ? "--" : @sprintf("\\num{%.0f}", 100round(life / 100))

"""
    rig_lead_numbers(table)

Name and text, per kind of ship of `ship_types` and drive of the class table `table`, of
the margin [points] of the best rig, and on container ships where the kite falls behind
the rotors.
"""
function rig_lead_numbers(table)
    numbers = Pair{String, String}[]
    for row in rig_lead_rows(table)
        name = row.drive_word * row.word
        push!(numbers, "Margin$name" => @sprintf("%.1f", row.margin))
        row.word == "Container" || continue
        push!(numbers, "KiteLifeLimit$name" => life_limit_text(row.life),
            "KiteLossLimit$name" => crash_cell(row.losses))
    end
    return numbers
end

"""
    rig_margin_table()

Tabular per kind of ship and drive of the best rig, the next and the margin between their
cost savings, and where the kite falls behind the rotors, in rig_margin_table.tex.
"""
function rig_margin_table()
    open(joinpath(sections, "rig_margin_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}llllrrr@{}}\n\\toprule")
        println(io, " & & & & & \\multicolumn{2}{c}{Kite behind rotors at} \\\\")
        println(io, "\\cmidrule(l){6-7}")
        println(io, "Ship type & Fuel & Best & Next & Margin [points] & Canopy life [h] & ",
            "Kites lost [per year] \\\\\n\\midrule")
        rows_of_types = rig_lead_rows(read_table(data_file("classes.csv")))
        for (k, row) in enumerate(rows_of_types)
            leaders = row.margin < level_margin ?
                      "\\multicolumn{2}{l}{$(row.rig) and $(row.rival) level}" :
                      "$(row.rig) & $(row.rival)"
            first_of_type = k == 1 || rows_of_types[k - 1].label != row.label
            println(io, join([first_of_type ? row.label : "", Dict(drive_labels)[row.drive],
                    leaders, @sprintf("%.1f", row.margin), life_limit_text(row.life),
                    crash_cell(row.losses)], " & "), " \\\\")
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    premium_numbers(table)

Name and text of the mean over the classes and routes of the class table `table` of how
much more [%] the e-ammonia ship costs than the same ship on VLSFO without a rig, without
a rig and with the rig that saves it most, and the share [%] of the premium that rig closes.
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
        "PremiumBestRig" => whole_number(mean(with)),
        "PremiumClosed" => whole_number(100 * (1 - mean(with) / mean(without)))]
end

"""
    sea_effect_table()

Kite cost saving per tonne-km and share of the time aloft of the ships of the sea effect
study, as modelled and with no extra launch wind from the sea, averaged over the routes:
sea_effect_table.tex.
"""
function sea_effect_table()
    table = read_table(data_file("sea_effect.csv"))
    ships = (first(sea_effect_classes), "140 m", Iterators.drop(sea_effect_classes, 1)...)
    open(joinpath(sections, "sea_effect_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}lrrrrr@{}}\n\\toprule")
        println(io, "Ship & \\multicolumn{2}{c}{Saving [\\%]} & Difference [points] & ",
            "\\multicolumn{2}{c}{Time aloft [\\%]} \\\\")
        println(io, "\\cmidrule(lr){2-3}\\cmidrule(lr){5-6}")
        println(io, " & Modelled & No sea effect & & Modelled & No sea effect ",
            "\\\\\n\\midrule")
        for ship in ships
            saved = sea_effect_saving.(Ref(table), ship, ("model", "none"))
            aloft = sea_effect_flight.(Ref(table), ship, ("model", "none"))
            # adding 0.0 turns a rounded -0.0 into 0.0
            @printf(io, "%s & %.1f & %.1f & \\(%.1f\\) & %.1f & %.1f \\\\\n",
                ship == "140 m" ? "140 m ship" : ship, saved...,
                round(saved[1] - saved[2]; digits=1) + 0.0, aloft...)
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"mean rows of `table` for `ship` with kite and `sea` setting, cost saving per tonne-km [%]"
function sea_effect_saving(table, ship, sea)
    savings = [100 * (1 - table["cost"][kite] / table["cost"][bare])
               for route in unique(table["route"])
               for bare in sea_effect_rows(table, ship, route, "none", "none")
               for kite in sea_effect_rows(table, ship, route, "kite", sea)]
    return mean(savings)
end

"mean share of the time aloft [%] of `ship` with the kite and `sea` setting"
sea_effect_flight(table, ship, sea) =
    100 * mean(table["flight_share"][kite]
               for route in unique(table["route"])
               for kite in sea_effect_rows(table, ship, route, "kite", sea))

"row numbers of `table` for `ship` on `route` with `rig` and `sea` setting"
sea_effect_rows(table, ship, route, rig, sea) =
    findall(i -> table["ship"][i] == ship && table["route"][i] == route &&
                 table["rig"][i] == rig && table["sea"][i] == sea, eachindex(table["ship"]))
