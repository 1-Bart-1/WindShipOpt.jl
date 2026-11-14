# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Regenerates the data and figures of the follow-up paper on kite design,
# paper/kite_design/, in a REPL in the scripts environment:
#
#     include("kite_design.jl")
#     kite_design(; fidelity=:draft)                # every step: data, then figures
#     kite_design(:aspect_figure; fidelity=:draft)  # only this step
#
# Its studies run on the ships of the main paper's development study, whose class ships
# take their rig sizes from the class results of the latest main paper run. Data goes to a
# run directory as for the main paper, figures to paper/kite_design/figures/.
include("paper.jl")

kite_design_figures = mkpath(joinpath(root, "paper", "kite_design", "figures"))

"projected aspect ratios of the kite in the aspect ratio study, those with a polar"
study_aspect_ratios = (3.0, 4.0, 5.0, 6.0, 8.0)

"""
    aspect_data()

Each ship of [`sensitivity_ships`](@ref) without a rig and with its kite at each of
[`study_aspect_ratios`](@ref), at the same area and the same price: aspect.csv.
"""
function aspect_data()
    cases = []
    for (ship, bare, route, areas) in sensitivity_ships()
        push!(cases, trip_case(bare; route, ship, aspect_ratio=0.0))
        design = ShipDesign(; bare.drive, bare.length, bare.class, areas.kite...)
        for aspect_ratio in study_aspect_ratios
            push!(cases, trip_case(design; route, ship, aspect_ratio,
                assumptions=WindShipOpt.with_kite_aspect_ratio(assumptions, aspect_ratio)))
        end
    end
    trips = round_trips(cases, sampled_departures())
    open(run_file("aspect.csv"), "w") do io
        println(io, "ship,aspect_ratio,area,cost,flight_share,launches,cargo")
        for (case, trip) in zip(cases, trips)
            isnothing(trip) && continue
            @printf(io, "%s,%.0f,%.0f,%.6f,%.3f,%.2f,%.0f\n", csv_value(case.ship),
                case.aspect_ratio, case.design.kite_area, trip.cost_per_tonne_km,
                trip.flight_share, trip.launches, trip.cargo)
        end
    end
end

"force limits of the kite in the force rating study [kN/m^2]"
study_force_ratings = (0.3, 0.5, 0.7, 1.0)

"canopy cloth weights of the force rating study [g/m^2]"
study_cloth_weights = (100.0, 141.0, 200.0, 283.0)

"wear weight exponents of the force rating study: its base, then its bounds"
study_wear_exponents = (1.0, 0.0, 1.5)

"kite areas of the force rating study [m^2]"
study_kite_areas = [1600.0 * sqrt(2.0)^k for k in 0:6]

"""
    nearby_kite_areas(kite_area, reach)

Those of [`study_kite_areas`](@ref) within `reach` grid steps of the one nearest
`kite_area`.
"""
function nearby_kite_areas(kite_area, reach)
    nearest = argmin(abs.(log.(study_kite_areas ./ kite_area)))
    return study_kite_areas[max(1, nearest - reach):min(end, nearest + reach)]
end

"""
    canopy_design(rating, cloth, wear_exponent)

The base assumptions with a kite built for the force limit `rating` [kN/m^2] from cloth of
`cloth` [g/m^2], its wear growing with cloth weight to the power `wear_exponent` and the
wear rate refitted so that cloth of `canopy_cloth_reference_weight` keeps its decay life.
"""
function canopy_design(rating, cloth, wear_exponent)
    reference = assumptions[:canopy_cloth_reference_weight] /
                WindShipOpt.decay_reference_weight
    wear_rate = assumptions[:canopy_wear_rate] *
                reference^(wear_exponent - assumptions[:canopy_wear_weight_exponent])
    return changed_assumptions((; kite_max_force_per_area=rating, canopy_cloth_weight=cloth,
        canopy_wear_weight_exponent=wear_exponent, canopy_wear_rate=wear_rate))
end

"""
    force_rating_case(bare, route, ship, rating, cloth, wear_exponent, area)

Trip case of the ship `bare` with a kite of `area` and the canopy of
[`canopy_design`](@ref), labelled with its canopy life.
"""
function force_rating_case(bare, route, ship, rating, cloth, wear_exponent, area)
    designed = canopy_design(rating, cloth, wear_exponent)
    design = ShipDesign(; bare.drive, bare.length, bare.class, kite_area=area)
    return trip_case(design; assumptions=designed, route, ship, rating, cloth,
        wear_exponent, area, life=WindShipOpt.canopy_lifetime(designed))
end

"""
    rated_cases(bare, route, ship, kite_area, wear_exponent, reach)

Cases of [`force_rating_case`](@ref) at each of [`study_force_ratings`](@ref) and
[`study_cloth_weights`](@ref), at `wear_exponent`, over `reach` area steps around
`kite_area`.
"""
rated_cases(bare, route, ship, kite_area, wear_exponent, reach) =
    vec([force_rating_case(bare, route, ship, rating, cloth, wear_exponent, area)
         for rating in study_force_ratings, cloth in study_cloth_weights,
         area in nearby_kite_areas(kite_area, reach)])

"""
    force_rating_cases(bare, route, ship, kite_area)

Cases of one ship in the force rating study: without a rig, then its
[`rated_cases`](@ref) at the base of [`study_wear_exponents`](@ref) over one area step
around `kite_area` and at its bounds at the area nearest it.
"""
function force_rating_cases(bare, route, ship, kite_area)
    base, bounds... = study_wear_exponents
    return [trip_case(bare; route, ship, rating=0.0, cloth=0.0, wear_exponent=base,
                area=0.0, life=0.0);
            rated_cases(bare, route, ship, kite_area, base, 1);
            reduce(vcat, [rated_cases(bare, route, ship, kite_area, bound, 0)
                          for bound in bounds])]
end

"""
    force_rating_data()

Each ship of [`sensitivity_ships`](@ref) with the cases of [`force_rating_cases`](@ref):
force_rating.csv.
"""
function force_rating_data()
    cases = reduce(vcat, [force_rating_cases(bare, route, ship, areas.kite.kite_area)
                          for (ship, bare, route, areas) in sensitivity_ships()])
    write_trips("force_rating.csv", cases, round_trips(cases, sampled_departures()), :ship,
        :rating, :cloth, :wear_exponent, :area, :life)
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
    save(joinpath(kite_design_figures, "aspect.pdf"), figure; pt_per_unit=print_scale)
end

"""
    best_force_rating_saving(table, ship, bare, conditions...)

Highest saving [%] of `ship`, costing `bare` without a rig, over the rows of
force_rating.csv that meet `conditions`, with that row.
"""
function best_force_rating_saving(table, ship, bare, conditions...)
    chosen = rows(table, "ship" => ship, conditions...)
    savings = percent_saving.(table["cost"][chosen], bare)
    best = argmax(savings)
    return savings[best], chosen[best]
end

"""
    force_rating_figure()

(a) Saving of each study ship at its best cloth weight and kite area against the force
limit, at each of [`study_wear_exponents`](@ref); (b) at the base force limit and wear
exponent, its saving at its best area against the cloth weight.
"""
function force_rating_figure()
    table = read_table(data_file("force_rating.csv"))
    figure = Figure(size=(column_width, 330))
    by_limit = Axis(figure[1, 1]; xlabel="force limit [kN/m²]", ylabel="cost saving [%]",
        xticks=collect(study_force_ratings), title="(a) best cloth and area")
    by_cloth = Axis(figure[2, 1]; xlabel="cloth weight [g/m²]", ylabel="cost saving [%]",
        xticks=collect(study_cloth_weights),
        title="(b) at the base force limit and wear exponent")
    base_exponent = first(study_wear_exponents)
    base_limit = assumptions[:kite_max_force_per_area]
    linestyles = (:solid, :dash, :dot)
    ships = unique(table["ship"])
    for (k, ship) in enumerate(ships)
        bare = table["cost"][only(rows(table, "ship" => ship, "rating" => 0))]
        for (wear_exponent, linestyle) in zip(study_wear_exponents, linestyles)
            savings = [first(best_force_rating_saving(table, ship, bare, "rating" => rating,
                           "wear_exponent" => wear_exponent))
                       for rating in study_force_ratings]
            lines!(by_limit, collect(study_force_ratings), savings;
                color=category_colours[k], linestyle)
        end
        savings = [first(best_force_rating_saving(table, ship, bare, "rating" => base_limit,
                       "wear_exponent" => base_exponent, "cloth" => cloth))
                   for cloth in study_cloth_weights]
        scatterlines!(by_cloth, collect(study_cloth_weights), savings;
            color=category_colours[k])
    end
    ship_entries = [LineElement(color=category_colours[k]) for k in eachindex(ships)]
    wear_entries = [LineElement(; color=:black, linestyle) for linestyle in linestyles]
    Legend(figure[3, 1], [ship_entries, wear_entries],
        [ships, [@sprintf("b = %g", exponent) for exponent in study_wear_exponents]],
        ["ship", "wear"]; orientation=:horizontal, nbanks=3, titleposition=:left,
        titlegap=6)
    rowgap!(figure.layout, 2, 6)
    save(joinpath(kite_design_figures, "force_rating.pdf"), figure; pt_per_unit=print_scale)
end

"data steps of the follow-up paper in the order they run"
kite_design_data_steps = [:aspect_data => aspect_data,
    :force_rating_data => force_rating_data]

"figure steps of the follow-up paper, each reading the data files and writing one figure"
kite_design_figure_steps = [:aspect_figure => aspect_figure,
    :force_rating_figure => force_rating_figure]

"""
    kite_design(names...; fidelity, resume=nothing)

Run the named steps of the follow-up paper, or every data step and then every figure step
when no name is given, at `fidelity` (:draft or :final), with `resume` as for
[`paper`](@ref).
"""
function kite_design(names::Symbol...; fidelity, resume=nothing)
    all_steps = [kite_design_data_steps; kite_design_figure_steps]
    unknown = setdiff(names, first.(all_steps))
    isempty(unknown) || throw(ArgumentError("no kite design step $(join(unknown, ", "))"))
    steps = isempty(names) ? all_steps : filter(step -> first(step) in names, all_steps)
    run_steps(steps, first.(kite_design_figure_steps); fidelity, resume)
end
