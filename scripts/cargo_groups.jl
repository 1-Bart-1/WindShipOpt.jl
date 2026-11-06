# Prints, from the class study of a run, what each rig pays in cargo on each ship class:
# the saving of its cheapest size, the points of it its mass or its blocked slots cost,
# the saving if the class filled its other limit first, and the saving of wings and
# rotors with no more units than the makers offer for bulk carriers and tankers; and per
# group of ships the rig to recommend. In the scripts environment:
#
#     include("cargo_groups.jl")
#     cargo_groups("../output/runs/<run>"); recommendation("../output/runs/<run>")
using Printf
using WindShipOpt
using WindShipOpt: CargoHold, cargo_limit, design_rig, unit_limits, with_rig

assumptions = Assumptions()

"rig areas of the class study by rig name, as `ShipDesign` keywords"
area_keywords = Dict("kite" => :kite_area, "wings" => :wing_area, "rotors" => :rotor_area)

"""
Rotor units Anemoi offers per class: Rotor Sails brochure, April 2024, Table A (Ultramax,
Kamsarmax, Capesize) and its tanker table (MR, LR2 for the Aframax, VLCC).
"""
offered_units = Dict("Ultramax bulk carrier" => 3, "Kamsarmax bulk carrier" => 3,
    "Capesize bulk carrier" => 4, "MR product tanker" => 2, "Aframax tanker" => 4,
    "VLCC" => 5)

"""
    class_rows(run)

Rows of classes.csv in the directory `run` as named tuples of strings.
"""
function class_rows(run)
    lines = readlines(joinpath(run, "classes.csv"))
    header = Symbol.(split(first(lines), ","))
    return [NamedTuple{Tuple(header)}(Tuple(strip.(split(line, ","), '"')))
            for line in lines[2:end]]
end

saving(row, bare) = 1 - parse(Float64, row.cost) / parse(Float64, bare.cost)
cargo(row) = parse(Float64, row.cargo)

"""
    cheapest_rows(rows)

Cheapest size of each rig in `rows`, keyed by class, drive, route and rig.
"""
function cheapest_rows(rows)
    cheapest = Dict{NTuple{4, String}, eltype(rows)}()
    for row in rows
        row.rig == "none" && continue
        key = (row.class, row.drive, row.route, row.rig)
        if !haskey(cheapest, key) ||
           parse(Float64, row.cost) < parse(Float64, cheapest[key].cost)
            cheapest[key] = row
        end
    end
    return cheapest
end

"rigs built so far by class name, rig name and area, as a kite builds its pattern table"
rig_cache = Dict{Tuple{String, String, Float64}, Any}()

"""
    other_limit_share(class, drive, rig, area)

Share of its cargo that `area` [m^2] of `rig` costs `class` with `drive` under the limit
the class does not fill first: its mass where the class fills its space, the slots it
blocks where the class fills its deadweight, and nothing on a ship without slots.
"""
function other_limit_share(class, drive, rig, area)
    bare = Ship(ShipDesign(Symbol(drive), class), assumptions)
    hold = CargoHold(bare, assumptions)
    other = cargo_limit(hold) == :space ? :deadweight : :space
    empty = unit_limits(hold)[other]
    isfinite(empty) || return 0.0
    fitted = get!(rig_cache, (class.name, rig, area)) do
        design = ShipDesign(Symbol(drive), class;
            NamedTuple{(area_keywords[rig],)}((area,))...)
        return design_rig(design, bare.hull, assumptions)
    end
    return 1 - unit_limits(CargoHold(with_rig(bare, fitted), assumptions))[other] / empty
end

"""
    offered_saving(rows, bare, units)

Mean saving over the routes of the sizes in `rows` with at most `units` units, linear in
the units between the two sizes run around it; `bare` holds the ship without a rig by
route.
"""
function offered_saving(rows, bare, units)
    savings = Float64[]
    for route in unique(row.route for row in rows)
        points = sort([(parse(Int, row.units), saving(row, bare[route]))
                       for row in rows if row.route == route])
        within = [point for point in points if first(point) <= units]
        above = [point for point in points if first(point) > units]
        best = maximum(last, within)
        if !isempty(above)
            (low, low_saving), (high, high_saving) = last(within), first(above)
            best = max(best, low_saving +
                             (high_saving - low_saving) * (units - low) / (high - low))
        end
        push!(savings, best)
    end
    return sum(savings) / length(savings)
end

"""
    cargo_groups(run)

Print, per drive and class sorted by deadweight, the limit the class fills first and for
each rig its mean saving over the routes, the points its cargo costs, and its saving under
the other limit; then the saving of wings and rotors at the units offered.
"""
function cargo_groups(run)
    rows = class_rows(run)
    cheapest = cheapest_rows(rows)
    classes = ship_classes()
    names = sort(unique(row.class for row in rows); by=name -> classes[name].deadweight)
    for drive in unique(row.drive for row in rows)
        println("== ", drive, ": saving, cargo charge and saving under the other limit [%]")
        for name in names
            class = classes[name]
            limit = cargo_limit(CargoHold(Ship(ShipDesign(Symbol(drive), class),
                assumptions), assumptions))
            ours = [row for row in rows if row.class == name && row.drive == drive]
            bare = Dict(row.route => row for row in ours if row.rig == "none")
            line = @sprintf("%-28s %-10s", name, limit)
            for rig in ("kite", "wings", "rotors")
                sizes = [row for row in ours if row.rig == rig]
                best = [cheapest[(name, drive, route, rig)] for route in keys(bare)]
                now = [saving(row, bare[row.route]) for row in best]
                gross = [1 - (1 - s) * cargo(row) / cargo(bare[row.route])
                         for (s, row) in zip(now, best)]
                other = [1 - (1 - g) / (1 - other_limit_share(class, drive, rig,
                    parse(Float64, row.area))) for (g, row) in zip(gross, best)]
                mean(values) = 100sum(values) / length(values)
                line *= @sprintf(" | %s %5.1f charge %4.2f other %5.1f", rig, mean(now),
                    mean(gross) - mean(now), mean(other))
                if rig != "kite" && haskey(offered_units, name)
                    line *= @sprintf(" at %d units %5.1f", offered_units[name],
                        100offered_saving(sizes, bare, offered_units[name]))
                end
            end
            println(line)
        end
    end
end

"""
    recommendation(run)

Print, per drive and group of classes (deadweight-limited, space-limited container ships,
the Megamax and the car carrier), each rig's mean saving over classes and routes, its CO2
saving where the fuel emits it and its cost against the same ship on VLSFO without a rig,
that cost without a rig, and the rig that saves most on each route, counted over the
classes of the group.
"""
function recommendation(run)
    rows = class_rows(run)
    classes = ship_classes()
    group(name) = classes[name].cargo_unit == :ceu ? "car carrier" :
                  classes[name].cargo_unit == :teu ?
                  string("container, ", cargo_limit(CargoHold(Ship(ShipDesign(:vlsfo,
                      classes[name]), assumptions), assumptions))) : "deadweight"
    groups = Dict(name => group(name) for name in unique(row.class for row in rows))
    bare = Dict((row.class, row.drive, row.route) => row
                for row in rows if row.rig == "none")
    cheapest = cheapest_rows(rows)
    relative(row, reference, column) = 100 * (1 - parse(Float64, getfield(row, column)) /
                                              parse(Float64, getfield(reference, column)))
    for drive in unique(row.drive for row in rows), name in sort(unique(values(groups)))
        println("== ", drive, ", ", name)
        for rig in ("kite", "wings", "rotors")
            cases = [(row, bare[(row.class, drive, row.route)],
                      bare[(row.class, "vlsfo", row.route)])
                     for ((class, case_drive, _, case_rig), row) in cheapest
                     if groups[class] == name && case_drive == drive && case_rig == rig]
            mean(values) = sum(values) / length(values)
            carbon = drive == "vlsfo" ?
                     mean([relative(row, own, :carbon) for (row, own, _) in cases]) : NaN
            @printf("%-6s saving %5.1f %% CO2 %5.1f %% cost against bare VLSFO %+5.1f %%\n",
                rig, mean([relative(row, own, :cost) for (row, own, _) in cases]), carbon,
                -mean([relative(row, fossil, :cost) for (row, _, fossil) in cases]))
        end
        premium = [-relative(reference, bare[(class, "vlsfo", route)], :cost)
                   for ((class, case_drive, route), reference) in bare
                   if groups[class] == name && case_drive == drive]
        @printf("none   cost against bare VLSFO %+5.1f %%\n",
            sum(premium) / length(premium))
        wins = Dict{Tuple{String, String}, Int}()
        for ((class, case_drive, route), reference) in bare
            (groups[class] == name && case_drive == drive) || continue
            rig = argmin(rig -> parse(Float64, cheapest[(class, drive, route, rig)].cost),
                ("kite", "wings", "rotors"))
            wins[(route, rig)] = get(wins, (route, rig), 0) + 1
        end
        println("best rig by route: ", join(sort(["$route $rig $count"
            for ((route, rig), count) in wins]), ", "))
    end
end
