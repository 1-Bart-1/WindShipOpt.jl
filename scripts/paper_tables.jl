# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Table steps of the paper, written as LaTeX to paper/sections/: the inputs of
# data/assumptions.yaml and the development study, the ship classes from
# data/ship_classes.csv, the payback of each rig, the goals and what
# missing one costs, and the numbers the abstracts state. Included by paper.jl.

"""
    whole_number(x)

Text of `x` rounded to a whole number, halves away from zero, never "-0".
"""
whole_number(x) = string(round(Int, x, RoundNearestTiesAway))

"""
    whole_points(x)

Text of `x` [points] in whole points with the unit, "less than 1 point" below a half.
"""
function whole_points(x)
    points = whole_number(x)
    points == "0" && return "less than 1 point"
    return string(points, points in ("1", "-1") ? " point" : " points")
end

"""
    one_decimal(x)

Text of `x` rounded to one decimal, never "-0.0".
"""
one_decimal(x) = @sprintf("%.1f", round(x; digits=1) + 0.0)

"""
    two_digits(x)

`x` rounded to two significant digits, as LaTeX.
"""
function two_digits(x)
    x == 0 && return "0"
    rounded = round(x; sigdigits=2)
    decimals = max(0, 1 - floor(Int, log10(abs(rounded))))
    return @sprintf("\\num{%.*f}", decimals, rounded)
end

"""
    canopy_life_table()

Table of the life statements behind the canopy wear rate, from
data/canopy_life_statements.csv, as canopy_life_table.tex.
"""
function canopy_life_table()
    lives = read_table(joinpath(root, "data", "canopy_life_statements.csv"))
    columns = ("grade", "cloth", "weight", "life_text", "ends_on", "tension", "strength",
        "dose", "rate")
    open(joinpath(sections, "canopy_life_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}lllrrlrrrr@{}}\n\\toprule")
        println(io, "Source & Grade & Cloth & \$w\$ & Life \$L\$ & Ends on & \$T/w\$ & ",
            "\$\\sigma_w\$ & \$\\dot D\$ & \$r\$ \\\\")
        println(io, " & & & [g/m²] & [h] & & & & [MJ/m²/h] & [g/m²/h] \\\\\n\\midrule")
        for row in findall(==("statement"), lives["kind"])
            println(io, "\\citet{", lives["key"][row], "} & ",
                join((string(lives[column][row]) for column in columns), " & "), " \\\\")
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

"citation in a source note: a bracketed group of `@key, locator` parts, or a bare `@key`"
citation = r"\[(@[^\]]*)\]|@([A-Za-z0-9_:-]+)"

"""
    cited_note(note)

Source `note` for LaTeX: the text escaped, a bracketed group `[@key, locator; @key]` set
in parentheses as `\\citealp` citations and a bare `@key` as `\\citet{key}`.
"""
function cited_note(note)
    parts = String[]
    start = 1
    for found in eachmatch(citation, note)
        push!(parts, latex_escape(note[start:prevind(note, found.offset)]))
        push!(parts, isnothing(found[1]) ? string("\\citet{", found[2], "}") :
                     string("(", join(cite_part.(split(found[1], ";")), "; "), ")"))
        start = found.offset + ncodeunits(found.match)
    end
    push!(parts, latex_escape(note[start:end]))
    return join(parts)
end

"""
    cite_part(part)

`\\citealp` of one `@key` or `@key, locator` part of a bracketed citation group.
"""
function cite_part(part)
    found = match(r"^\s*@([A-Za-z0-9_:-]+)\s*(?:,\s*(.*?))?\s*$", part)
    isnothing(found) && error("citation part \"$part\" is not `@key` or `@key, locator`")
    key, locator = found
    isnothing(locator) && return string("\\citealp{", key, "}")
    return string("\\citealp[", latex_escape(locator), "]{", key, "}")
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
            ragged, "p{6.6cm}@{}}")
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

"words of an input's name printed otherwise in the input table"
input_words = Dict("e" => "e-", "teu" => "TEU", "ceu" => "CEU", "usd" => "USD",
    "eur" => "EUR", "vlsfo" => "VLSFO", "holtrop" => "Holtrop")

"""
    input_label(name)

Name of the input `name` as the input table prints it, in words rather than as a key.
"""
input_label(name) = replace(join([get(input_words, word, word)
                                  for word in split(string(name), "_")], " "),
    "e- " => "e-", r"^rigid " => "rigid kite ")

"""
    write_input_row(io, entry, name)

One row of the input table: name, base value, range, unit and the full source note.
"""
function write_input_row(io, entry, name)
    unit = strip(entry.unit, '"')
    println(io, latex_escape(input_label(name)), " & ", latex_number(entry.value), " & ",
        latex_number(entry.low), "--", latex_number(entry.high), " & ",
        unit == "-" ? "--" : latex_escape(unit), " & ", cited_note(entry.reason), " \\\\")
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
        println(io, "\\begin{longtable}{@{}", ragged, "p{2.5cm}", ragged, "p{2.0cm}rrrr",
            ragged, "p{4.0cm}@{}}")
        println(io, "\\caption{The inputs of the development study by the rig whose ",
            "developer can change them: base value and range; the gain of a rig's saving ",
            "at the better end of the range and its loss at the worse end, in percentage ",
            "points, in cost per tonne-km on each ship and the largest of each in ",
            "CO\\textsubscript{2} per tonne-km over the ships; and why the input is in ",
            "the study. \\savingerror}\n",
            "\\label{tab:development}\\\\")
        header = string("\\toprule\nInput & Value (range) & ",
            join(short_ship.(ships), " & "),
            " & CO\\textsubscript{2} & Why \\\\\n",
            " & & \\multicolumn{3}{c}{cost saving} & & \\\\\n\\midrule")
        println(io, header, "\n\\endfirsthead")
        println(io, "\\multicolumn{7}{@{}l}{\\cref{tab:development} (continued)}\\\\")
        println(io, header, "\n\\endhead\n\\bottomrule\n\\endfoot")
        for (rig, heading) in development_groups
            println(io, "\\multicolumn{7}{@{}l}{\\textit{", heading, "}}\\\\*")
            for entry in filter(entry -> entry.rig == rig, development_inputs)
                write_lever_row(io, table, ships, entry)
            end
        end
        println(io, "\\end{longtable}")
    end
end

"""
    write_lever_row(io, table, ships, entry)

One row of the development table.
"""
function write_lever_row(io, table, ships, entry)
    carbons = [lever_gain_loss(table, ship, entry; column="carbon") for ship in ships]
    carbon = (maximum(first, carbons), minimum(last, carbons))
    println(io, entry.label, " & ", range_cell(entry.input), " & ",
        join([effect_cell(lever_gain_loss(table, ship, entry)) for ship in ships], " & "),
        " & ", effect_cell(carbon), " & ", entry.reason, " \\\\")
end

"""
    range_cell(input)

The development table's cell of the base value and range of `input` with its unit, or of
how many assumptions one of [`joint_inputs`](@ref) moves.
"""
function range_cell(input)
    haskey(joint_inputs, input) &&
        return string(length(joint_inputs[input]), " inputs, \\cref{tab:inputs}")
    assumption = assumptions.entries[input]
    unit = strip(assumption.unit, '"')
    return string(latex_number(assumption.value), " (", latex_number(assumption.low), "--",
        latex_number(assumption.high), ")",
        unit == "-" ? "" : string(" ", latex_escape(unit)))
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
    life = assumptions.entries[:canopy_life]
    derived = @sprintf("derived \\num{%.0f} h (\\numrange{%.0f}{%.0f}), ",
        round(WindShipOpt.reference_decay_life(assumptions); sigdigits=2), life.low,
        life.high)
    return [("Canopy life", "kite", canopy,
            derived * "on makers' statements; small kites expected 100 to \\num{1000} h"),
        ("Canopy price", "kite", price, today),
        ("Rig life", "wings", years(:wing_lifetime),
            "stated design life; about 2 years on record"),
        ("Rig life", "rotors", years(:rotor_lifetime),
            "stated design life; about 8 years on record"),
        ("Out of service", "all", service,
            "one rotor operator's 97\\,\\%; nothing for kites"),
        ("Crash in flight", "kite", "none", "no crash record published for a ship kite"),
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
        println(io, "Ship & Rig & Size [m\\textsuperscript{2}] & Cost saving [\\%] & ",
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
        println(io, "Ship & Rig & Size [m\\textsuperscript{2}] & Cost saving [\\%] & Rival & ",
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
    class_dimension_table()

Tabular of the ship classes with their main dimensions, deadweight and unit capacity,
the limit their cargo fills first, speed, engine power, resistance calibration, price,
cargo value, the inputs of deck cargo and port operations and the frontal and lateral
wind areas, in class_table.tex, and the rows of their sources in class_sources.tex; an
infinite fixed-rig delay, where a fixed rig prevents cargo handling, is printed as ∞.
"""
function class_dimension_table()
    classes = sort(collect(values(ship_classes())); by=class -> class.deadweight)
    notes = class_source_notes()
    open(joinpath(sections, "class_sources.tex"), "w") do io
        for class in classes
            println(io, latex_escape(class.name), " & ", cited_note(notes[class.name]),
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
        println(io, "\\begin{tabular}{@{}llrrrrrr@{}}\n\\toprule")
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
    cargo_interest_table()

Tabular of the cost saving of the cheapest size of each rig on the zero-emission drive at
low and at high cargo interest, the mean over the classes and routes, split by
[`saving_split`](@ref) into fuel, time and the rest, with the median change of the round
trip and the mean [`speed_along_track`](@ref) of the ship with and without the rig, in
cargo_interest_table.tex.
"""
function cargo_interest_table()
    table = read_table(study_file(:cargo_interest, "cargo_interest.csv"))
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
    split_numbers(table)

Name and text, per drive and rig of the class table `table`, of the fuel and time points of
the [`split_points`](@ref) of its [`rig_splits`](@ref), and the rigs and fuels on which the
fuel saved falls short of the rig's own cost, "no rig" where it never does.
"""
function split_numbers(table)
    numbers = Pair{String, String}[]
    short = String[]
    for (drive, word) in drive_words, rig in rig_names
        _, fuel, time, rest = split_points(rig_splits(table, drive, rig))
        name = word * uppercasefirst(rig)
        push!(numbers, "SplitFuel$name" => whole_number(fuel),
            "SplitTime$name" => whole_number(time))
        fuel + rest < 0 && push!(short, "$(rig_name(rig, false)) on $(fuel_names[drive])")
    end
    push!(numbers, "FuelShort" => isempty(short) ? "no rig" : listed(short))
    return numbers
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
    payback_numbers(table)

Name and text, per drive and rig of the class table `table`, of the [`payback_text`](@ref)
of the median payback over the routes of each class.
"""
function payback_numbers(table)
    return ["Payback$word$(uppercasefirst(rig))" =>
                payback_text([median_payback([payback_years(table, class, drive, route, rig)
                                              for route in unique(table["route"])])
                              for class in class_order(table)])
            for (drive, word) in drive_words for rig in rig_names]
end

"""
    payback_text(years)

Text of the range of payback `years` that are finite, and of how many classes never pay
back where some do not.
"""
function payback_text(years)
    never = count(isinf, years)
    never == length(years) && return "never"
    text = value_range(filter(isfinite, years), two_digits) * " years"
    return never == 0 ? text : "$text, and on $never classes never"
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
    price, ship = rig_price(table, best)
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

"""
    rig_price(table, row)

Price [USD] of the rig of `row` of class table `table`, the capital of its ship less that
of the same ship without a rig, and that rig ship.
"""
function rig_price(table, row)
    class, drive = ship_classes()[table["class"][row]], Symbol(table["drive"][row])
    ship = Ship(ShipDesign(drive, class; rig_size(table["rig"][row], table["area"][row])...),
        assumptions)
    retractable = table["retractable"][row] == "true"
    bare = Ship(ShipDesign(drive, class), assumptions)
    price = ShipCosts(ship, assumptions; retractable).capital -
            ShipCosts(bare, assumptions).capital
    return price, ship
end

"what the fleet market of a rig sums over its cells: scale to the unit shown, name, unit"
market_columns = (ships=(1, "Ships", ""), units=(1, "Rig units", ""),
    area=(1e-6, "Area", "[km\\textsuperscript{2}]"), sales=(1e-9, "Sales", "[USD bn]"),
    saved=(1e-9, "Saving", "[USD bn/yr]"), fuel=(1e-9, "Fuel", "[Mt/yr]"),
    carbon=(1e-12, "CO\\textsubscript{2}", "[Mt/yr]"))

"names of the [`market_columns`](@ref)"
market_measures = keys(market_columns)

"what a rig saves a ship a year: scale to the unit shown, name, unit, text of a cell"
type_saving_columns = (saved=(1e-3, "Cost", "[USD 1000]", two_digits),
    share=(1, "Cost", "[\\%]", one_decimal), fuel=(1e-3, "Fuel", "[t]", two_digits),
    carbon=(1e-6, "CO\\textsubscript{2}", "[t]", two_digits))

"""
    cell_saving(table, cell, rig)

Yearly saving of the best size of `rig` fitted to every ship of a [`fleet_cells`](@ref)
cell of class table `table`: in cost [USD], fuel [kg] and tank-to-wake CO2 [g] over the
cell's transport work.
"""
function cell_saving(table, cell, rig)
    (; work, bare) = cell
    row = cell.best[rig]
    fuel = WindShipOpt.Drive(Symbol(table["drive"][row]), assumptions).fuel
    return (; saved=cell_saved(cell, rig),
        fuel=work * (table["fuel"][bare] - table["fuel"][row]) * 1e6 / fuel.heating_value,
        carbon=work * (table["carbon"][bare] - table["carbon"][row]))
end

"""
    cell_market(table, cell, rig)

Each of the [`market_measures`](@ref) of the best size of `rig` fitted to every ship of a
[`fleet_cells`](@ref) cell of class table `table`: ships, rig units, rig area [m^2] and rig
sales [USD], then its [`cell_saving`](@ref).
"""
function cell_market(table, cell, rig)
    (; ships) = cell
    row = cell.best[rig]
    price, _ = rig_price(table, row)
    return (; ships, units=ships * table["units"][row], area=ships * table["area"][row],
        sales=ships * price, cell_saving(table, cell, rig)...)
end

"""
    type_savings(table, drive)

Each ship type of the [`fleet_cells`](@ref) of class table `table` on `drive`, with the
yearly saving per ship of the best size of each rig on average over the type's ships, in
cost [USD], as a share of the cost without a rig [%], in fuel [kg] and in CO2 [g], and
its [`fleet_leaders`](@ref) on the cost share as its `leaders`.
"""
function type_savings(table, drive)
    classes = ship_classes()
    cells = fleet_cells(table, drive)
    savings = []
    for type in sort(unique(classes[cell.class].type for cell in cells))
        own = filter(cell -> classes[cell.class].type == type, cells)
        rigs = Dict(rig => saving_per_ship(table, own, rig) for rig in rig_names)
        leaders = fleet_leaders(Dict(rig => saving.share for (rig, saving) in rigs), own,
            [cell.bill for cell in own])
        push!(savings, (; type, rigs, leaders))
    end
    return savings
end

"""
    saving_per_ship(table, cells, rig)

The [`cell_saving`](@ref) of `rig` summed over `cells` of class table `table`, per ship of
those cells, with the cost saved as a `share` [%] of their cost without a rig.
"""
function saving_per_ship(table, cells, rig)
    (; saved, fuel, carbon) = mapreduce(cell -> cell_saving(table, cell, rig),
        (one, other) -> map(+, one, other), cells)
    ships = sum(cell.ships for cell in cells)
    return (; saved=saved / ships, share=100saved / sum(cell.bill for cell in cells),
        fuel=fuel / ships, carbon=carbon / ships)
end

"""
    cell_markets(table, drive)

The [`fleet_cells`](@ref) of class table `table` on `drive` that fit a rig, each with the
ship `type` of its class, its [`fleet_leaders`](@ref) and the [`cell_market`](@ref) of
each leader and, as `"any"`, of the one that saves most.
"""
function cell_markets(table, drive)
    classes = ship_classes()
    markets = []
    for cell in fleet_cells(table, drive)
        leaders = fleet_leaders(cell.savings, [cell])
        isempty(leaders) && continue
        sums = Dict(rig => cell_market(table, cell, rig) for rig in leaders)
        sums["any"] = sums[argmax(rig -> cell.savings[rig], leaders)]
        push!(markets, (; classes[cell.class].type, leaders, sums))
    end
    return markets
end

"""
    fleet_market(markets)

Low and high sums of the [`market_measures`](@ref) of each rig, and of `"any"`, over the
[`cell_markets`](@ref) `markets` that rig leads: low over those it alone leads, high
over all.
"""
function fleet_market(markets)
    no_market = NamedTuple{market_measures}(zeros(length(market_measures)))
    market = Dict(rig => (low=no_market, high=no_market) for rig in (rig_names..., "any"))
    for (; leaders, sums) in markets, (rig, cell) in sums
        (; low, high) = market[rig]
        market[rig] = (low=length(leaders) == 1 ? map(+, low, cell) : low,
            high=map(+, high, cell))
    end
    return market
end

"""
    market_range(range, measure)

Low to high of `measure` of a [`fleet_market`](@ref) `range`, in the unit of its
[`market_columns`](@ref) to two digits; one number where they agree, a dash where both
are zero.
"""
function market_range(range, measure)
    scale = first(market_columns[measure])
    low, high = two_digits.(scale .* (range.low[measure], range.high[measure]))
    high == "0" && return "--"
    return low == high ? high : "$low--$high"
end

"""
    market_table()

Tabulars of what each rig saves a ship of each type a year, in type_saving_table.tex, and
of the rig sales of each rig's [`fleet_market`](@ref) on each drive, low to high, in total
in market_sales_table.tex and by ship type in market_sales_type_table.tex.
"""
function market_table()
    table = class_table()
    write_type_savings(table)
    markets = Dict(drive => cell_markets(table, drive) for (drive, _) in drive_labels)
    write_market_sales(markets)
    write_market_types(markets)
end

"""
    table_header(io, labels, columns, measures, repeats=1)

Header rows of a tabular: `labels` and the names of `measures` of `columns` (scale, name,
unit), `repeats` times over, then the units under them.
"""
function table_header(io, labels, columns, measures, repeats=1)
    names, units = ([columns[measure][k] for measure in measures] for k in (2, 3))
    println(io, join([labels; repeat(names, repeats)], " & "), " \\\\")
    println(io, join([fill("", length(labels)); repeat(units, repeats)], " & "), " \\\\")
end

"""
    write_type_savings(table)

Tabular of the [`type_savings`](@ref) of class table `table` on each drive in the unit of
the [`type_saving_columns`](@ref), the `leaders` of each type in bold:
type_saving_table.tex.
"""
function write_type_savings(table)
    measures = keys(type_saving_columns)
    open(joinpath(sections, "type_saving_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}lll", "r"^length(measures), "@{}}\n\\toprule")
        table_header(io, ["Fuel", "Ship type", "Rig"], type_saving_columns, measures)
        for (drive, label) in drive_labels
            println(io, "\\midrule")
            for (k, (; type, rigs, leaders)) in enumerate(type_savings(table, drive))
                k > 1 && println(io, "\\addlinespace")
                for (j, rig) in enumerate(rig_names)
                    cells = [text(scale * rigs[rig][measure])
                        for (measure, (scale, _, _, text)) in pairs(type_saving_columns)]
                    name = rig in leaders ? "\\textbf{$rig}" : rig
                    println(io, k == j == 1 ? label : "", " & ", j == 1 ? type : "", " & ",
                        name, " & ", join(cells, " & "), " \\\\")
                end
            end
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    write_market_sales(markets)

Tabular of the ships, rig units, rig area and sales of the [`fleet_market`](@ref) of each
rig and the best rig over the [`cell_markets`](@ref) `markets` of each drive:
market_sales_table.tex.
"""
function write_market_sales(markets)
    measures = (:ships, :units, :area, :sales)
    open(joinpath(sections, "market_sales_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}ll", "r"^length(measures), "@{}}\n\\toprule")
        table_header(io, ["Fuel", "Rig"], market_columns, measures)
        for (drive, label) in drive_labels
            market = fleet_market(markets[drive])
            println(io, "\\midrule")
            for (k, rig) in enumerate((rig_names..., "any"))
                cells = [market_range(market[rig], measure) for measure in measures]
                println(io, k == 1 ? label : "", " & ", rig == "any" ? "best rig" : rig,
                    " & ", join(cells, " & "), " \\\\")
            end
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    write_market_types(markets)

Tabular of the ships and sales of the [`fleet_market`](@ref) of each rig with a market on
some drive over the [`cell_markets`](@ref) of each ship type in `markets`, by drive:
market_sales_type_table.tex.
"""
function write_market_types(markets)
    measures = (:ships, :sales)
    types = unique(class.type for class in values(ship_classes()))
    rigs = [rig for rig in rig_names
            if any(market -> fleet_market(market)[rig].high.ships > 0, values(markets))]
    width = length(measures)
    open(joinpath(sections, "market_sales_type_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}ll", "r"^(width * length(rigs)),
            "@{}}\n\\toprule")
        heads = ("\\multicolumn{$width}{c}{$rig}" for rig in rigs)
        println(io, " & & ", join(heads, " & "), " \\\\")
        println(io, join(("\\cmidrule(lr){$(width * k - width + 3)-$(width * k + 2)}"
                          for k in eachindex(rigs))))
        table_header(io, ["Fuel", "Ship type"], market_columns, measures, length(rigs))
        for (drive, label) in drive_labels
            println(io, "\\midrule")
            for (k, type) in enumerate(sort(types))
                market = fleet_market(filter(cell -> cell.type == type, markets[drive]))
                cells = [market_range(market[rig], measure)
                         for rig in rigs for measure in measures]
                println(io, k == 1 ? label : "", " & ", type, " & ", join(cells, " & "),
                    " \\\\")
            end
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
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
    forecast_ratios(table, rig, plan)

Cost of `rig` over that of the ship without a rig on `plan`, per departure of forecast table
`table`; empty where the two cannot be paired, as a departure without a feasible round trip
is no row of the table.
"""
function forecast_ratios(table, rig, plan)
    cost(name) = table["cost"][rows(table, "rig" => name, "plan" => plan)]
    length(cost(rig)) == length(cost("none")) || return Float64[]
    return cost(rig) ./ cost("none")
end

"""
    forecast_saving(table, rig, plan)

Mean over the departures of forecast table `table` of the cost saving [%] of `rig` on
`plan` by [`forecast_ratios`](@ref), `NaN` where they are empty.
"""
forecast_saving(table, rig, plan) = 100 * (1 - mean(forecast_ratios(table, rig, plan)))

"""
    forecast_lead_cell(table, plan)

Mean over the departures of forecast table `table` of the kite's cost saving on `plan` less
the rotors' [points], signed, with its [`jackknife_error`](@ref), as a LaTeX cell.
"""
function forecast_lead_cell(table, plan)
    leads = 100 .* (forecast_ratios(table, "rotors", plan) .-
                    forecast_ratios(table, "kite", plan))
    spread = jackknife_error(departures -> mean(leads[departures]), length(leads))
    return @sprintf("\\(%+d \\pm %.0f\\)", round(Int, mean(leads)), spread)
end

"""
    forecast_plans_table()

Share of each rig's perfect-foresight cost saving kept per plan of the forecast study, with
its standard error over the departures [%], and that of the kite held to its plan:
forecast_plans_table.tex.
"""
function forecast_plans_table()
    write_kept_table(:forecast_plans, "forecast_plans_table.tex",
        (("true", "One forecast run"), ("mean", "Ensemble mean"),
            ("margin", "Margin for wind"), ("members", "Several members"),
            ("held_kite", "One forecast run, kite held to the plan"),
            ("kite_margin", "One forecast run, kite limits 20\\,\\% tighter in the plan"),
            ("expected", "One forecast run, wind error weighed")))
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
    write_kept_table(:forecast_replanning, "forecast_replanning_table.tex", plans;
        changes=(
            heading="Change from operational, about every 29 h, unless stated [points]",
            plans=(plans[1], plans[3], plans[4], plans[5], plans[6],
                ("operational_6h_course", "About every 10 h, adapted, from unadapted"))))
end

"""
    write_kept_table(study, table_name, plans; changes=nothing)

Write `table_name` from the kept shares in `study`_kept.csv of method study `study`: a row
per (plan, label) of `plans`, a column per rig, then under `changes.heading` a row per
(plan, label) of `changes.plans` with the paired change from the data's control.
"""
function write_kept_table(study, table_name, plans; changes=nothing)
    table = read_table(study_file(study, "$(study)_kept.csv"))
    open(joinpath(sections, table_name), "w") do io
        println(io, "\\begin{tabular}{@{}lccc@{}}\n\\toprule")
        println(io, "Plan & Kite & Wing sails & Rotors \\\\\n\\midrule")
        for (plan, label) in plans
            cells = [kept_cell(table, rig, plan) for rig in ("kite", "wings", "rotors")]
            println(io, label, " & ", join(cells, " & "), " \\\\")
        end
        if !isnothing(changes)
            println(io, "\\midrule\n\\multicolumn{4}{@{}l}{\\textit{", changes.heading,
                "}} \\\\")
            for (plan, label) in changes.plans
                cells = [kept_change_cell(table, rig, plan)
                         for rig in ("kite", "wings", "rotors")]
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
    table = read_table(study_file(:forecast_hours, "forecast_hours.csv"))
    plans = (("false", "Perfect foresight"), ("true", "One run"),
        ("members", "Several members"), ("kite_margin", "Tighter limits"))
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
        ("Fast sailing possible", "fast_real"), ("Fast sailing forecast", "fast_known"),
        ("Fast sailing possible, whole edge", "fast_real_edge"),
        ("Fast sailing forecast, whole edge", "fast_known_edge"),
        ("Fast sailing commanded", "fast_commanded"), ("Fast sailing held", "fast_held"),
        ("Fuel, kite down [GJ]", "fuel_down"), ("Fuel, kite aloft [GJ]", "fuel_up"),
        ("Fuel saved aloft [GJ]", "saved"),
        ("Saved by a speed change within the stretch [USD]", "saved_within_stretch"))
    open(joinpath(sections, "forecast_hours_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}l", "c"^length(plans), "@{}}\n\\toprule")
        println(io, "Per round trip & ", join(last.(plans), " & "),
            " \\\\\n\\midrule")
        for (label, column) in rows
            cells = [hours_cell(table, plan, column) for (plan, _) in plans]
            println(io, label, " & ", join(cells, " & "), " \\\\")
        end
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"mean and standard error over the departures of `column` of `plan`, as a table cell"
function hours_cell(table, plan, column)
    values = table[column][rows(table, "plan" => plan)]
    return @sprintf("\\(%.0f \\pm %.0f\\)", mean(values),
        std(values) / sqrt(length(values)))
end

"groups of forecast_causes_table.tex as (heading, rows of (label, statistic))"
forecast_cause_groups = (
    ("Cost saving [\\%]",
        (("Perfect foresight", cause_saving(:perfect)),
            ("Forecast plan", cause_saving(:forecast)))),
    ("Share kept by the forecast plan [\\%]",
        (("Of perfect foresight", cause_kept(:forecast, :perfect)),)),
    ("Cost saving lost [points]",
        (("Total", cause_loss(:perfect, :forecast)),)),
    ("Of the forecast's loss, by what it gets wrong, waves first",
        (("Wave forecast", cause_loss(:perfect, :wave_forecast)),
            ("Wind forecast", cause_loss(:wave_forecast, :forecast)))),
    ("Of the forecast's loss, by what it gets wrong, wind first",
        (("Wind forecast", cause_loss(:perfect, :wind_forecast)),
            ("Wave forecast", cause_loss(:wind_forecast, :forecast)))),
    ("Of the forecast's loss, by what the plan decides",
        (("Course", cause_loss(:perfect, :course_perfect)),
            ("Speed", cause_loss(:course_perfect, :course_foresight)),
            ("The kite's launches and landings", cause_loss(:course_foresight,
                :course_forecast)),
            ("Re-planning the course on later forecasts", cause_loss(:course_forecast,
                :forecast)))),
    ("A plan inside kite limits 20\\,\\% tighter [points]",
        (("Gain over the forecast plan", cause_loss(:kite_margin, :forecast)),)))

"""
    kite_margin_values(margins, trips, knowledge, plan)

Per row of [`kite_margin_rows`](@ref) and for the kite's launches per round trip, its label
and values per departure [%, -] on `knowledge` of forecast_margins.csv read into `margins`
and on `plan` of forecast_causes.csv read into `trips`, `NaN` where a trip is missing.
"""
function kite_margin_values(margins, trips, knowledge, plan)
    departures = sort(unique(trips["departure"]))
    row_of = Dict(margins["departure"][i] => i for i in eachindex(margins["knowledge"])
                  if margins["knowledge"][i] == knowledge)
    launches = Dict(trips["departure"][i] => trips["launches"][i]
                    for i in eachindex(trips["rig"])
                    if trips["rig"][i] == "kite" && trips["plan"][i] == plan)
    rows = [get(row_of, departure, 0) for departure in departures]
    shares = [(label, [row == 0 ? NaN : 100 * margins[column][row] for row in rows])
              for (label, column) in kite_margin_rows]
    per_trip = [get(launches, departure, NaN) for departure in departures]
    return [shares; ("Launches per round trip", per_trip)]
end

"LaTeX of an (value, error) estimate of [`cause_estimate`](@ref)"
cause_cell(estimate) = @sprintf("\\(%s \\pm %.1f\\)", one_decimal(estimate.value),
    estimate.error)

"""
    write_cause_groups(io, groups, saved)

Write to `io` the head of a table of the kite, wing sails and rotors and the kite's
excess over each deck rig, and per group of `groups`, as (heading, rows of (label,
statistic)), each row's [`cause_estimate`](@ref)s on the savings `saved` per rig.
"""
function write_cause_groups(io, groups, saved)
    println(io, "\\begin{tabular}{@{}lccccc@{}}\n\\toprule")
    println(io, " & Kite & Wing sails & Rotors & Kite less wing sails & ",
        "Kite less rotors \\\\\n\\midrule")
    for (heading, group) in groups
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
end

"groups of forecast_live_table.tex as (heading, rows of (label, statistic))"
forecast_live_groups = (
    ("Cost saving [\\%]",
        (("Perfect foresight, plan's speed held", cause_saving(false)),
            ("\\quad sailed live", cause_saving(:perfect_live)),
            ("Forecast plan, plan's speed held", cause_saving(:expected)),
            ("\\quad sailed live", cause_saving(:live)))),
    ("Forecast plan's loss against perfect foresight at the plan's speed [points]",
        (("Sailed live", cause_loss(false, :live)),)),
    ("Forecast plan's loss against perfect foresight sailed the same way [points]",
        (("Plan's speed held", cause_loss(false, :expected)),
            ("Sailed live", cause_loss(:perfect_live, :live)))),
    ("Gain of sailing live [points]",
        (("On the forecast plan", cause_loss(:live, :expected)),
            ("With perfect foresight", cause_loss(:perfect_live, false)))))

"""
    forecast_live_table()

Per rig the cost saving with perfect foresight and on the forecast result's plan, each
holding the plan's speed and sailed live, what the forecast costs each way and what sailing
live gains, and the kite's excess over the wing sails and the rotors, paired per departure
with standard errors over the departures of forecast_live.csv: forecast_live_table.tex.
"""
function forecast_live_table()
    table = read_table(study_file(:forecast_live, "forecast_live.csv"))
    saved = Dict(rig => rig_savings(table, rig, forecast_live_plans)
                 for rig in ("kite", "wings", "rotors"))
    open(joinpath(sections, "forecast_live_table.tex"), "w") do io
        write_cause_groups(io, forecast_live_groups, saved)
        println(io, "\\bottomrule\n\\end{tabular}")
    end
end

"""
    forecast_causes_table()

Per rig the cost saving lost by the forecast result's plan per cause, and the kite's excess
over the wing sails and the rotors paired per departure, each with its standard error over
the departures of forecast_causes.csv; and the kite's time near its limits and launches
with perfect foresight and on that plan: forecast_causes_table.tex.
"""
function forecast_causes_table()
    table = read_table(study_file(:forecast_causes, "forecast_causes.csv"))
    saved = Dict(rig => forecast_cause_savings(table, rig)
                 for rig in ("kite", "wings", "rotors"))
    margins = read_table(study_file(:forecast_causes, "forecast_margins.csv"))
    open(joinpath(sections, "forecast_causes_table.tex"), "w") do io
        write_cause_groups(io, forecast_cause_groups, saved)
        println(io, "\\midrule\nThe kite [\\%, of its time at sea unless stated] & ",
            "Perfect foresight & Forecast plan & Change & & \\\\\n\\midrule")
        perfect = kite_margin_values(margins, table, "perfect", "perfect")
        forecast = kite_margin_values(margins, table, "forecast", "forecast")
        for ((label, before), (_, after)) in zip(perfect, forecast)
            values = Dict(:perfect => before, :forecast => after)
            cells = [cause_estimate(cause_saving(:perfect), values),
                cause_estimate(cause_saving(:forecast), values),
                cause_estimate(cause_loss(:forecast, :perfect), values)]
            println(io, "\\quad ", label, " & ", join(cause_cell.(cells), " & "),
                " & & \\\\")
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
    table = read_table(study_file(:speed_terms, "speed_terms.csv"))
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
    table = read_table(study_file(:published_terms, "published_terms.csv"))
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
    fidelity_parts()

Each part of the model as (part, varied, model, error, effect): its name, how its effect is
measured, how it is modelled, its known error, and the method study whose run holds the
data file (`nothing` for a result of the paper run), that file and the groups of condition
sets whose results [`part_effect`](@ref) compares, `nothing` for a part with no measured
effect.
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
    (part="Kite flight", varied="turn radius, aspect ratio, force limit",
        model="quasi-steady pattern with mass, bridle and tether drag, searched for each " *
              "wind and course",
        error="glide ratio of 4 matched to flight data",
        effect=varied_inputs(:kite_min_turn_radius, :kite_aspect_ratio,
            :kite_max_force_per_area)),
    (part="Kite launch and sea limits", varied="wind limits, extra launch wind in a sea",
        model="fixed wind limits for launch, flight and landing; launch wind raised with " *
              "the launch mast's motion in the sea",
        error="extra launch wind scaled on one reported pair of wind speeds",
        effect=varied_inputs(:kite_weather_window)),
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
    (:model_parts, "model_parts.csv", "ship",
        [[("part" => "none",), ("part" => string(part),)]])

"for each of `inputs` of the development study, the base and both of its bounds"
function varied_inputs(inputs...)
    issubset(inputs, (entry.input for entry in development_inputs)) ||
        error("not all of $inputs are in the development study")
    return (nothing, "sensitivity.csv", "ship",
    [[("input" => "none", "bound" => "value"); [("input" => string(input), "bound" => bound)
                                                for bound in ("low", "high")]]
     for input in inputs])
end

"each weather year"
weather_years() = (:model_parts, "weather_years.csv", "ship",
    [[("year" => year,) for year in 1:ceil(Int, last(departures) / 8760)]])

"each corridor scale of the convergence study, on its one ship"
corridor_grids() =
    (:convergence, "convergence.csv", nothing,
        [[("scale" => scale,) for scale in convergence_scales]])

"the best size found by the search and the best of every size"
size_search_grid() =
    (:size_search, "size_search.csv", "class", [[(), ("round" => >=(0),)]])

"""
    part_effect((study, file, ship_column, groups))

Largest difference [points] in the cost saving of each rig between the condition sets of
any one of `groups` in data file `file` of method study `study`, or of the paper run where
`study` is `nothing`, over its ships in `ship_column`, `nothing`
for a file of the 140 m ship alone; and for each set of rigs that take turns at being
cheapest within a group, the ships where they do. Errors where the file has no row of a
condition set.
"""
function part_effect((study, file, ship_column, groups))
    table = read_table(isnothing(study) ? data_file(file) : study_file(study, file))
    spread = Dict(rig => 0.0 for rig in rig_names)
    swaps = Dict{String, Set{String}}()
    ships = isnothing(ship_column) ? [nothing] : unique(table[ship_column])
    for ship in ships, group in groups
        at_ship = isnothing(ship) ? () : (ship_column => ship,)
        for variant in group
            isempty(rows(table, at_ship..., variant...)) && error("$file has no $variant")
        end
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
the goals, the `highlight_limit` the paper build checks, the [`class_numbers`](@ref),
[`class_range_numbers`](@ref), [`recommendation_numbers`](@ref),
[`rig_lead_numbers`](@ref), [`route_numbers`](@ref), [`split_numbers`](@ref),
[`payback_numbers`](@ref), [`premium_numbers`](@ref), [`fleet_share_numbers`](@ref),
[`market_numbers`](@ref) and [`type_saving_numbers`](@ref) of the class study, the
[`design_premium_numbers`](@ref) of the design study and the
[`forecast_numbers`](@ref).
"""
function numbers_file()
    classes = class_table()
    results = [class_numbers(classes); class_range_numbers(classes);
               recommendation_numbers(classes); rig_lead_numbers(classes);
               route_numbers(classes); split_numbers(classes); payback_numbers(classes);
               premium_numbers(classes);
               design_premium_numbers(read_table(data_file("designs.csv")));
               fleet_share_numbers(classes); market_numbers(classes);
               type_saving_numbers(classes); forecast_numbers()]
    draft = paper_run.fidelity != :final
    open(joinpath(sections, "numbers.tex"), "w") do io
        for (name, text) in goal_numbers()
            print(io, number_macro(name, text, false))
        end
        print(io, number_macro("HighlightLimit", string(highlight_limit), false))
        for (name, text) in results
            print(io, number_macro(name, text, draft))
        end
    end
end

"""
    goal_numbers()

Name and text of the goals the abstracts state: canopy life, the canopy price
at the goal and today, and the share of time out of service; of the
[`kite_gap_bias`](@ref); and of the `DRAFT_SPREAD` of a draft result [points].
"""
goal_numbers() = [
    "CanopyLifeGoal" => @sprintf("\\num{%.0f}", assumptions[:canopy_life]),
    "CanopyPriceGoal" => @sprintf("%.0f", WindShipOpt.canopy_price(assumptions)),
    "CanopyPriceToday" => @sprintf("%.0f", WindShipOpt.canopy_price_today(assumptions)),
    "OutOfServiceGoal" => @sprintf("%.0f", 100out_of_service_goal()),
    "KiteGapBias" => @sprintf("%.1f", kite_gap_bias),
    ("DraftSpread" * uppercasefirst(string(part)) => one_decimal(spread)
     for (part, spread) in pairs(DRAFT_SPREAD))...]

"""
    class_numbers(classes)

Name and text, per drive and rig, of the mean over the [`fleet_cells`](@ref) of class and
route of the class table `classes` of the cost saving [%] of the cheapest size, and the
count of cells in each [`fleet_band`](@ref); and per drive the [`fraction_text`](@ref) of
the wing sails' mean saving over the rotors'.
"""
function class_numbers(classes)
    numbers = Pair{String, String}[]
    for (drive, word) in drive_words
        cells = fleet_cells(classes, drive)
        bands = fleet_band.(cells)
        savings = Dict(rig => mean(cell.savings[rig] for cell in cells) for rig in rig_names)
        push!(numbers, "Cells$word" => string(length(cells)),
            "Level$word" => string(count(==("level"), bands)),
            "NoRig$word" => string(count(==("none"), bands)),
            "WingsShare$word" => fraction_text(savings["wings"] / savings["rotors"]))
        for rig in rig_names
            name = word * uppercasefirst(rig)
            push!(numbers, "Saving$name" => whole_number(savings[rig]),
                "Leads$name" => string(count(==(rig), bands)))
        end
    end
    return numbers
end

"fractions [`fraction_text`](@ref) names, with their words"
fraction_words = (1 / 10 => "a tenth", 1 / 8 => "an eighth", 1 / 6 => "a sixth",
    1 / 5 => "a fifth", 1 / 4 => "a quarter", 1 / 3 => "a third", 1 / 2 => "half",
    2 / 3 => "two thirds", 3 / 4 => "three quarters", 1 => "as much")

"""
    fraction_text(ratio)

Words for `ratio` of one quantity to another: the nearest of the `fraction_words` by
ratio, "nothing" at or below zero, and "<ratio> times" above 1.25.
"""
function fraction_text(ratio)
    ratio <= 0 && return "nothing"
    ratio > 1.25 && return one_decimal(ratio) * " times"
    return last(argmin(fraction -> abs(log(first(fraction) / ratio)), fraction_words))
end

"""
    class_range_numbers(table)

Name and text, from the class table `table`, per drive and rig of the range over the classes
of the mean over the routes of the fuel saving [%] of the cheapest size; on VLSFO the
wing sails' largest such cost saving [%] and the classes on which they cost more than they
save; and per deck rig the most units of any cheapest size.
"""
function class_range_numbers(table)
    classes = class_order(table)
    numbers = Pair{String, String}[]
    class_saving(column, class, drive, rig) =
        only(mean_savings(table, (column,), [class], drive, rig))
    for (drive, word) in drive_words, rig in rig_names
        fuel = [class_saving("fuel", class, drive, rig) for class in classes]
        push!(numbers, "FuelRange$word$(uppercasefirst(rig))" =>
            value_range(filter(isfinite, fuel), whole_number))
    end
    wings = Dict(class => class_saving("cost", class, "vlsfo", "wings") for class in classes)
    losing = [class for class in classes if wings[class] < 0]
    push!(numbers, "WingsBestOil" => whole_number(maximum(filter(isfinite, collect(values(wings))))),
        "WingsLossClassesOil" => isempty(losing) ? "no class" : "the " * listed(losing))
    for rig in ("wings", "rotors")
        cheapest = filter(!isnothing, [cheapest_row(table, class, route, drive, rig)
                                       for class in classes
                                       for route in unique(table["route"])
                                       for (drive, _) in drive_words])
        push!(numbers, "MostUnits$(uppercasefirst(rig))" =>
            whole_number(maximum(table["units"][cheapest])))
    end
    return numbers
end

"""
    fleet_share_numbers(table)

Name and text, per drive of the class table `table`, of each band's share [%] of the
yearly cost of carrying the fleet's cargo and the total of that cost [billion USD], and
the shares of the IMO transport work and of shipping's CO2 the classes
carry.
"""
function fleet_share_numbers(table)
    numbers = Pair{String, String}[]
    for (drive, word) in drive_words
        split = fleet_split_of(table, drive)
        bill = fleet_total(split, :bill)
        push!(numbers, "FleetBill$word" => whole_number(bill / 1e9))
        for band in fleet_bands
            name = word * uppercasefirst(band)
            push!(numbers, "FleetShare$name" => whole_number(100split[band].bill / bill))
        end
    end
    _, work_share = fleet_work()
    fuel_share = read_table(joinpath(root, "data", "ship_classes.csv"))["fuel_share"]
    push!(numbers, "FleetWorkShare" => whole_number(100work_share),
        "FleetFuelShare" => whole_number(100sum(fuel_share)))
    return numbers
end

"""
    market_numbers(table)

Name and text, per drive of the class table `table`, of the [`market_range`](@ref) of the
ships, sales, cost saved and CO2 saved of each rig's [`fleet_market`](@ref) and of the best
rig's.
"""
function market_numbers(table)
    numbers = Pair{String, String}[]
    for (drive, word) in drive_words
        market = fleet_market(cell_markets(table, drive))
        for rig in (rig_names..., "any"), measure in (:ships, :sales, :saved, :carbon)
            name = string("Market", word, uppercasefirst(rig),
                uppercasefirst(string(measure)))
            push!(numbers, name => market_range(market[rig], measure))
        end
    end
    return numbers
end

"""
    type_saving_numbers(table)

Name and text, per drive of the class table `table`, ship type and rig, of the
[`type_savings`](@ref) per ship a year in cost [USD million], as a share of the cost [%]
and in CO2 [t]; and the ship types on which the wing sails cost more than they save on
VLSFO.
"""
function type_saving_numbers(table)
    numbers = Pair{String, String}[]
    losing = [type for (; type, rigs) in type_savings(table, "vlsfo")
              if rigs["wings"].share < 0]
    push!(numbers, "WingsLossTypesOil" =>
        isempty(losing) ? "no ship type" : listed(losing) * " ships")
    for (drive, word) in drive_words, (; type, rigs) in type_savings(table, drive)
        type_word = join(uppercasefirst.(split(type)))
        for rig in rig_names
            name = string("TypeSaving", word, type_word, uppercasefirst(rig))
            (; saved, share, carbon) = rigs[rig]
            push!(numbers, "$(name)Cost" => two_digits(1e-6saved),
                "$(name)Share" => whole_number(share),
                "$(name)Carbon" => two_digits(1e-6carbon))
        end
    end
    return numbers
end

"""
    forecast_numbers()

Name and text of the forecast result re-planned live: per rig its cost saving [%] and the
share of it kept [%] with its error by [`kept_cell`](@ref); the [`forecast_lead_cell`](@ref)
live and with perfect foresight; and the kite's mean flight share [%], launches and forced
landings a round trip.
"""
function forecast_numbers()
    kept = read_table(data_file("forecast_result_kept.csv"))
    result = read_table(data_file("forecast_result.csv"))
    kite = rows(result, "rig" => "kite", "plan" => "live")
    kite_mean(column) = mean(result[column][kite])
    return [["ForecastKept" * uppercasefirst(rig) => kept_cell(kept, rig, "live")
             for rig in rig_names];
            ["ForecastSaving" * uppercasefirst(rig) =>
                 whole_number(forecast_saving(result, rig, "live")) for rig in rig_names];
            "ForecastLeadLive" => forecast_lead_cell(result, "live");
            "ForecastLeadPerfect" => forecast_lead_cell(result, "false");
            "ForecastFlightShare" => whole_number(100kite_mean("flight_share"));
            "ForecastLaunches" => whole_number(kite_mean("launches"));
            "ForecastForcedLandings" => one_decimal(kite_mean("forced_landings"))]
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
    rig_lead(cells)

Of the mean cost saving [%] of each rig over fleet `cells`: the rig saving most, its
rival, the one level with it where there is one and else the next, the margin between
them [points] with its [`gap_error`](@ref), the `verdict` of the [`fleet_leaders`](@ref),
`"leads"`, `"level"` or `"none"` where no rig clearly saves, and the lead of the kite over
the rotors [points].
"""
function rig_lead(cells)
    savings = Dict(rig => mean(cell.savings[rig] for cell in cells) for rig in rig_names)
    ranked = sort(collect(rig_names); by=rig -> -savings[rig])
    leaders = sort(fleet_leaders(savings, cells); by=rig -> -savings[rig])
    rig, rival = first(ranked), length(leaders) > 1 ? leaders[2] : ranked[2]
    margin = savings[rig] - savings[rival]
    verdict = isempty(leaders) ? "none" : length(leaders) > 1 ? "level" : "leads"
    return (; rig, rival, margin, error=first(gap_error(cells, ones(length(cells)), rig,
            rival)), verdict, kite_lead=savings["kite"] - savings["rotors"])
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

For each of `ship_types` and drive of the class table `table`: its words and label, its
name in the text among `ship_places`, the [`rig_lead`](@ref), each rig's
[`saving_per_ship`](@ref) as `per_ship`, and the canopy life [h] and kites lost a year of
[`kite_limits`](@ref).
"""
function rig_lead_rows(table)
    classes = ship_classes()
    cells = Dict(drive => fleet_cells(table, drive) for (drive, _) in drive_words)
    return [begin
                names = [name for name in class_order(table) if classes[name].type in types]
                own = filter(cell -> cell.class in names, cells[drive])
                lead = rig_lead(own)
                per_ship = Dict(rig => saving_per_ship(table, own, rig)
                                for rig in rig_names)
                (; word, label, name=lowercase(label), where=ship_places, drive,
                    drive_word, lead..., per_ship,
                    kite_limits(table, names, drive, lead.kite_lead)...)
            end
            for (word, label, types) in ship_types for (drive, drive_word) in drive_words]
end

"""
    route_lead_rows(table)

For each drive, kind of ship of `ship_kind_words` and route of the class table `table`: the
kind's word, the route's name in the text and its kind of place, and the
[`rig_lead`](@ref) over the [`fleet_cells`](@ref) of the kind's classes on that route.
"""
function route_lead_rows(table)
    classes = ship_classes()
    routes = unique(table["route"])
    where = (preposition="to", every="on every route", total=length(routes))
    lead_rows = []
    for (drive, drive_word) in drive_words
        cells = fleet_cells(table, drive)
        for (unit, kind) in ship_kind_words, route in routes
            own = filter(cell -> cell.route == route && classes[cell.class].cargo_unit == unit,
                cells)
            push!(lead_rows, (; kind, name=route_label(route), where, drive, drive_word,
                rig_lead(own)...))
        end
    end
    return lead_rows
end

"""
    route_numbers(table)

Name and text, per drive of the class table `table`, of the [`route_savings_text`](@ref) and
per kind of ship of `ship_kind_words` of the [`verdict_text`](@ref) of its
[`route_lead_rows`](@ref); and of the range over classes and drives of the kite's share of
the time aloft [%] of its cheapest size on the short route to Bilbao and on the others.
"""
function route_numbers(table)
    lead_rows = route_lead_rows(table)
    numbers = Pair{String, String}[]
    for (drive, word) in drive_words
        push!(numbers, "RouteSavings$word" => route_savings_text(table, drive))
        for (_, kind) in ship_kind_words
            own = filter(row -> row.drive == drive && row.kind == kind, lead_rows)
            push!(numbers, "RouteVerdict$word$kind" => verdict_text(own))
        end
    end
    for (name, on_route) in ("Bilbao" => ==("bilbao"), "Ocean" => !=("bilbao"))
        kites = filter(!isnothing, [cheapest_row(table, class, route, drive, "kite")
                                    for class in class_order(table)
                                    for route in filter(on_route, unique(table["route"]))
                                    for (drive, _) in drive_words])
        push!(numbers, "KiteFlight$name" =>
            value_range(100table["flight_share"][kites], whole_number))
    end
    return numbers
end

"""
    route_savings_text(table, drive)

Text of each route's mean over the classes of the class table `table` of the cost saving
[%] on `drive` of the rig that saves most on that class and route, the routes in order of
that saving.
"""
function route_savings_text(table, drive)
    routes = unique(table["route"])
    best(class, route) = maximum(cheapest_saving(table, "cost", class, drive, route, rig)
                                 for rig in rig_names)
    savings = Dict(route => mean(filter(isfinite, [best(class, route)
                                                   for class in class_order(table)]))
                   for route in routes)
    ordered = sort(routes; by=route -> -savings[route])
    return listed(["$(whole_number(savings[route]))\\,\\% to $(route_label(route))"
                   for route in ordered])
end

"""
    life_limit_text(life)

Text of the canopy life [h] `life`, to the hundred; a dash where the kite has no lead.
"""
life_limit_text(life) = isnan(life) ? "--" : @sprintf("\\num{%.0f}", 100round(life / 100))

"""
    rig_lead_numbers(table)

Name and text, from the [`rig_lead_rows`](@ref) of the class table `table`, of the
[`verdict_text`](@ref) of each of `verdict_groups`, the [`advice_text`](@ref), the
[`highlight_text`](@ref), the [`places`](@ref) the wing sails are advised, per drive the
[`answer_text`](@ref), the [`saved_figures`](@ref) of the rigs it advises over every ship
type and the range of their shares [%] of the cost alone, and on container ships per drive
where the kite falls behind the rotors.
"""
function rig_lead_numbers(table)
    rows = rig_lead_rows(table)
    wings = filter(row -> row.verdict != "none" && "wings" in advised_rigs(row), rows)
    numbers = ["Advice" => advice_text(rows), "HighlightAdvice" => highlight_text(rows),
        "WingsAdvised" => isempty(wings) ? "on no ship type" : places(wings, rows)]
    for (drive, word) in drive_words
        own = filter(row -> row.drive == drive, rows)
        saved = reduce(vcat, advised_savings.(own))
        push!(numbers, "Answer$word" => answer_text(own),
            "AnswerRange$word" => saved_figures(saved, drive),
            "AnswerShares$word" => value_range(getproperty.(saved, :share), whole_number))
    end
    for (word, types, drives) in verdict_groups
        push!(numbers, "Verdict$word" =>
            verdict_text(filter(row -> row.word in types && row.drive in drives, rows)))
    end
    for row in rows
        row.word == "Container" || continue
        name = row.drive_word * row.word
        push!(numbers, "KiteLifeLimit$name" => life_limit_text(row.life),
            "KiteLossLimit$name" => crash_cell(row.losses))
    end
    return numbers
end

"name of each drive in the text"
fuel_names = Dict("vlsfo" => "fuel oil", "ammonia" => "e-ammonia")

"ship types whose verdicts the text states together: word in number macros, the words of
their `ship_types`, drives"
verdict_groups = let all_types = first.(ship_types), both = ("ammonia", "vlsfo")
    (("Container", ("Container",), both), ("CarCarrier", ("CarCarrier",), both),
        ("GeneralCargo", ("GeneralCargo",), both),
        ("BulkTanker", ("BulkCarrier", "Tanker"), both),
        ("BulkTankerGeneralCargo", ("BulkCarrier", "Tanker", "GeneralCargo"), both),
        ("ContainerAmmonia", ("Container",), ("ammonia",)),
        ("BulkCarrierAmmonia", ("BulkCarrier",), ("ammonia",)),
        ("FleetAmmonia", all_types, ("ammonia",)), ("FleetOil", all_types, ("vlsfo",)),
        ("Fleet", all_types, both))
end

"most characters a highlight of the paper may have"
highlight_limit = 85

"names of the rigs in the text, with the verb a rig leads by"
rig_subjects = Dict("kite" => ("the kite", "leads"), "wings" => ("the wing sails", "lead"),
    "rotors" => ("the rotors", "lead"))

"""
    listed(items)

`items` joined by commas and a final "and".
"""
listed(items) = join(items, ", ", " and ")

"""
    grouped(keys, items)

Each distinct key of `keys` in order of first appearance, paired with its `items`.
"""
function grouped(keys, items)
    groups = Pair{eltype(keys), Vector{eltype(items)}}[]
    for (key, item) in zip(keys, items)
        at = findfirst(group -> first(group) == key, groups)
        isnothing(at) ? push!(groups, key => [item]) : push!(last(groups[at]), item)
    end
    return groups
end

"the kind of place of a ship type in the text: the preposition before its name, the words
for all of them and how many there are"
ship_places = (preposition="on", every="on every ship type", total=length(ship_types))

"""
    place_list(names, scope, where)

Text naming the places `names` of the kind `where` with its preposition: its `every` where
they are all of its `total` and `scope` holds more than one.
"""
function place_list(names, scope, where)
    length(scope) > 1 && length(names) == where.total && return where.every
    return "$(where.preposition) " * listed(names)
end

"""
    ship_list(labels, scope)

Text naming the ship types of `labels` among `scope` by [`place_list`](@ref).
"""
ship_list(labels, scope) = place_list(lowercase.(labels), scope, ship_places)

"""
    places(rows, scope)

Where rig lead `rows` hold among the rig lead rows of `scope`, which share one kind of
place: their places and fuels, each named only where `scope` holds more than one.
"""
function places(rows, scope)
    names = unique(row.name for row in scope)
    drives = unique(row.drive for row in scope)
    where = first(scope).where
    on = [Set(row.drive for row in rows if row.name == name) for name in names]
    texts = String[]
    for (fuels, held) in grouped(on, names)
        isempty(fuels) && continue
        at = length(names) > 1 ? place_list(held, names, where) : ""
        fuel = length(drives) == 1 ? "" :
               length(fuels) == length(drives) ? "on both fuels" :
               "on " * fuel_names[only(fuels)]
        push!(texts, strip(at * " " * fuel))
    end
    return listed(texts)
end

"""
    points_range(margins)

Text of `margins` [points] in whole points: one value, or the range they span.
"""
function points_range(margins)
    reads_alike(margins, whole_number) && return whole_points(first(margins))
    return value_range(margins, whole_number) * " points"
end

"""
    verdict_key(row)

What a rig lead `row` says, margin aside: its verdict, with the best rig and its rival
where one leads, and the two in the order of `rig_names` where they are level.
"""
function verdict_key(row)
    row.verdict == "none" && return (row.verdict,)
    row.verdict == "leads" && return (row.verdict, row.rig, row.rival)
    return (row.verdict, rig_pair(row)...)
end

"the best rig of a [`rig_lead`](@ref) `lead` and its rival, in the order of `rig_names`"
rig_pair(lead) = sort([lead.rig, lead.rival]; by=rig -> findfirst(==(rig), rig_names))

"""
    verdict_phrase(key, margins, where)

Text of a [`verdict_key`](@ref) `key` holding with `margins` [points] at the
[`places`](@ref) `where`: the best rig leading its rival by their margin, the two level
and how far apart, or no rig clearly saving.
"""
function verdict_phrase(key, margins, where)
    first(key) == "none" && return strip("no rig clearly saves " * where)
    (rig, verb), (rival, _) = rig_subjects[key[2]], rig_subjects[key[3]]
    margin = points_range(margins)
    first(key) == "leads" && return strip("$rig $verb $rival by $margin $where")
    apart = (reads_alike(margins, whole_number) ? "" : "at most ") *
            whole_points(maximum(margins))
    return "$rig and $rival are level, $apart apart" * (isempty(where) ? "" : ", $where")
end

"""
    verdict_text(rows)

Text of the verdicts of rig lead `rows` of [`rig_lead_rows`](@ref), each kind of
[`verdict_phrase`](@ref) once with the [`places`](@ref) it holds, e-ammonia first.
"""
function verdict_text(rows)
    rows = sort(rows; by=row -> row.drive != "ammonia")
    parts = [verdict_phrase(key, [row.margin for row in held], places(held, rows))
             for (key, held) in grouped(verdict_key.(rows), rows)]
    length(parts) > 2 && return join(parts, "; ", "; and ")
    return join(parts, ", and ")
end

"""
    rig_name(rig, short)

Name of `rig` in the text, without its article where `short`.
"""
rig_name(rig, short) = short ? rig_short_names[rig] : first(rig_subjects[rig])

"names of the rigs in the shortest text"
rig_short_names = Dict("kite" => "kite", "wings" => "wing sails", "rotors" => "rotors")

"""
    advice(lead; short=false)

Rig to use by a [`rig_lead`](@ref) `lead`: the rig that leads, either of two level, in
the order of `rig_names`, or no rig; `short` names a rig without its article.
"""
function advice(lead; short=false)
    lead.verdict == "none" && return "no rig"
    lead.verdict == "leads" && return rig_name(lead.rig, short)
    return "either " * join(rig_name.(rig_pair(lead), short), " or ")
end

"""
    advice_text(rows)

Text of the [`advice`](@ref) of rig lead `rows` of [`rig_lead_rows`](@ref): first the rigs
to use whatever the fuel, ship types given the same rig named together, then per ship
type where the fuel changes the rig, the rig on each fuel.
"""
function advice_text(rows)
    labels = unique(row.label for row in rows)
    drives = sort(unique(row.drive for row in rows); by=drive -> drive != "ammonia")
    advised = [[advice(only(filter(row -> row.label == label && row.drive == drive, rows)))
                for drive in drives] for label in labels]
    same = [all(==(first(rigs)), rigs) for rigs in advised]
    fuels = length(drives) == 1 ? fuel_names[only(drives)] : "both fuels"
    common = ["$(first(rigs)) " * ship_list(names, labels)
              for (rigs, names) in grouped(advised[same], labels[same])]
    differing, previous = String[], String[]
    for (rigs, names) in grouped(advised[.!same], labels[.!same])
        per_fuel = ["$rig on $(fuel_names[drive])" for (rig, drive) in zip(rigs, drives)]
        on_fuels = previous == reverse(rigs) ? "the other way round" : listed(per_fuel)
        verb = isempty(differing) ? "use " : ""
        push!(differing, "$(ship_list(names, labels)) $verb$on_fuels")
        previous = rigs
    end
    parts = String[]
    isempty(common) || push!(parts, "on $fuels use " * join(common, ", ", ", and "))
    isempty(differing) || push!(parts, join(differing, ", ", ", and "))
    return join(parts, "; ")
end

"whether every one of `values` reads alike by `format`"
reads_alike(values, format) = allequal(format.(values))

"""
    value_range(values, format)

Text of `values` by `format`: one value where they [`reads_alike`](@ref), else the range
they span.
"""
function value_range(values, format)
    low, high = format.(extrema(values))
    return reads_alike(values, format) ? low : "$low to $high"
end

"""
    advised_savings(row)

The `per_ship` savings of the rigs rig lead `row` of [`rig_lead_rows`](@ref) advises: the
rig that leads, both where two are level, none where no rig clearly saves.
"""
function advised_savings(row)
    row.verdict == "none" && return []
    return [row.per_ship[rig] for rig in advised_rigs(row)]
end

"the rig that leads in a [`rig_lead`](@ref) `lead`, or the two that are level"
advised_rigs(lead) = lead.verdict == "leads" ? [lead.rig] : rig_pair(lead)

"""
    saved_figures(saved, drive)

Text of the range of `saved` savings a ship a year: the share [%] of the cost per tonne-km,
the US dollars and, on VLSFO, the tonnes of CO2.
"""
function saved_figures(saved, drive)
    figures = [value_range(getproperty.(saved, :share), whole_number) * "\\,\\%",
        "USD~" * value_range(1e-6getproperty.(saved, :saved), two_digits) * " million"]
    drive == "vlsfo" && push!(figures,
        value_range(1e-6getproperty.(saved, :carbon), two_digits) * "~t of CO\$_2\$")
    return listed(figures)
end

"""
    answer_clause(row)

Text of the [`advice`](@ref) of rig lead `row` of [`rig_lead_rows`](@ref) on its ship type,
with the [`saved_figures`](@ref) of its [`advised_savings`](@ref).
"""
function answer_clause(row)
    ships = lowercase(row.label)
    row.verdict == "none" && return "no rig on $ships, where none clearly saves"
    return "$(advice(row)) on $ships, $(saved_figures(advised_savings(row), row.drive))"
end

"""
    answer_text(rows)

Text of the [`answer_clause`](@ref) of each of rig lead `rows` of one drive, in the order of
`ship_types`.
"""
answer_text(rows) = join(answer_clause.(rows), "; ")

"""
    highlight_text(rows)

Highlight of the advice of rig lead `rows`: the [`advice_text`](@ref) on both fuels, else
on e-ammonia, else on e-ammonia in short with the last rig "elsewhere", else with the
number of ship types per rig, else the rigs best on some ship type on e-ammonia, whichever
first has at most `highlight_limit` characters; the shortest, with a warning, where none
has.
"""
function highlight_text(rows)
    ammonia = filter(row -> row.drive == "ammonia", rows)
    groups = last.(grouped(advice.(ammonia), ammonia))
    rigs = [advice(first(held); short=true) for held in groups]
    named = [rig * " " * ship_list([row.label for row in held], ammonia)
             for (rig, held) in zip(rigs, groups)]
    length(groups) > 1 && (named[end] = last(rigs) * " elsewhere")
    counts = ["$rig on $(length(held))" for (rig, held) in zip(rigs, groups)]
    counts[1] *= length(first(groups)) == 1 ? " ship type" : " ship types"
    best = Set(rig for row in ammonia if row.verdict != "none" for rig in advised_rigs(row))
    options = [rig_short_names[rig] for rig in rig_names if rig in best]
    any(row -> row.verdict == "none", ammonia) && push!(options, "none")
    sentences = [uppercasefirst(advice_text(rows)) * ".",
        uppercasefirst(advice_text(ammonia)) * ".", "On e-ammonia: $(join(named, ", ")).",
        "On e-ammonia: $(join(counts, ", ")).",
        "On e-ammonia the best rig depends on the ship type: $(join(options, ", ", " or "))."]
    fits = findfirst(sentence -> length(sentence) <= highlight_limit, sentences)
    isnothing(fits) || return sentences[fits]
    shortest = argmin(length, sentences)
    @warn "No highlight of the advice fits $highlight_limit characters" shortest
    return shortest
end

"""
    rig_margin_table()

Tabular per kind of ship and drive of the best rig, the next, the margin between their
cost savings with its error and whether the best leads or the two are level, and where
the kite falls behind the rotors, in rig_margin_table.tex.
"""
function rig_margin_table()
    open(joinpath(sections, "rig_margin_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}llllrlrr@{}}\n\\toprule")
        println(io, " & & & & & & \\multicolumn{2}{c}{Kite behind rotors at} \\\\")
        println(io, "\\cmidrule(l){7-8}")
        println(io, "Ship type & Fuel & Best & Next & Margin [points] & Verdict & ",
            "Canopy life [h] & Kites lost [per year] \\\\\n\\midrule")
        for row in rig_lead_rows(class_table())
            println(io, join([row.label, Dict(drive_labels)[row.drive], row.rig, row.rival,
                    @sprintf("\\(%.1f \\pm %.1f\\)", row.margin, row.error),
                    row.verdict, life_limit_text(row.life),
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
    design_premium_numbers(designs)

Name and text of the [`whole_range`](@ref) over the ship lengths of designs.csv `designs`,
on the route to Guadeloupe, of how much more [%] the e-ammonia ship costs than the same
ship on VLSFO without a rig, of the share of that premium the best size of each rig closes
([`premium_closed`](@ref)), and of how much more it costs with the better of kite and
rotors, at the lengths where both were run.
"""
function design_premium_numbers(designs)
    lengths = sort(unique(designs["length"]))
    premium(column) = [fuel_premium(designs, "ammonia", length, column)
                       for length in lengths]
    numbers = ["DesignPremium" => whole_range(premium(nothing)),
        "DesignPremiumBestRig" => whole_range(min.(premium("kite_area"),
            premium("rotor_area")))]
    for (rig, column) in rig_area_columns
        closed = [premium_closed(designs, "ammonia", length, column) for length in lengths]
        push!(numbers, "DesignPremiumClosed" * uppercasefirst(rig) => whole_range(closed))
    end
    return numbers
end

"""
    whole_range(values)

Lowest to highest of the finite `values` in whole numbers, `"<low> to <high>"`, or the one
number where both round alike.
"""
function whole_range(values)
    low, high = whole_number.(extrema(filter(isfinite, values)))
    return low == high ? low : "$low to $high"
end

"""
    sea_effect_table()

Kite cost saving per tonne-km and share of the time aloft of the ships of the sea effect
study, as modelled and with no extra launch wind from the sea, averaged over the routes:
sea_effect_table.tex.
"""
function sea_effect_table()
    table = read_table(study_file(:sea_effect, "sea_effect.csv"))
    ships = (first(sea_effect_classes), "140 m", Iterators.drop(sea_effect_classes, 1)...)
    open(joinpath(sections, "sea_effect_table.tex"), "w") do io
        println(io, "\\begin{tabular}{@{}lrrrrr@{}}\n\\toprule")
        println(io, "Ship & \\multicolumn{2}{c}{Saving [\\%]} & Difference & ",
            "\\multicolumn{2}{c}{Time aloft [\\%]} \\\\")
        println(io, "\\cmidrule(lr){2-3}\\cmidrule(lr){5-6}")
        println(io, " & Modelled & No sea effect & [points] & Modelled & No sea effect ",
            "\\\\\n\\midrule")
        for ship in ships
            saved = sea_effect_saving.(Ref(table), ship, ("model", "none"))
            aloft = sea_effect_flight.(Ref(table), ship, ("model", "none"))
            @printf(io, "%s & %.1f & %.1f & %s & %.1f & %.1f \\\\\n", ship, saved...,
                one_decimal(saved[1] - saved[2]), aloft...)
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
