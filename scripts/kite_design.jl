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
study_force_ratings = (0.3, 0.5, 0.7, 0.9, 1.3)

"kite areas of the force rating study [m^2]"
study_kite_areas = [1600.0 * sqrt(2.0)^k for k in 0:6]

"""
    nearby_kite_areas(kite_area)

Those of [`study_kite_areas`](@ref) within one grid step of the one nearest `kite_area`.
"""
function nearby_kite_areas(kite_area)
    nearest = argmin(abs.(log.(study_kite_areas ./ kite_area)))
    return study_kite_areas[max(1, nearest - 1):min(end, nearest + 1)]
end

"""
    force_rating_case(bare, route, ship, rating, area)

Trip case of the ship `bare` with a kite of `area` built for the force limit `rating`
[kN/m^2].
"""
function force_rating_case(bare, route, ship, rating, area)
    design = ShipDesign(; bare.drive, bare.length, bare.class, kite_area=area)
    return trip_case(design; route, ship, rating, area,
        assumptions=changed_assumptions((; kite_max_force_per_area=rating)))
end

"""
    force_rating_cases(bare, route, ship, kite_area)

Cases of one ship in the force rating study: without a rig, then its
[`force_rating_case`](@ref) at each of [`study_force_ratings`](@ref) over one area step
around `kite_area`.
"""
force_rating_cases(bare, route, ship, kite_area) =
    [trip_case(bare; route, ship, rating=0.0, area=0.0);
     vec([force_rating_case(bare, route, ship, rating, area)
          for rating in study_force_ratings, area in nearby_kite_areas(kite_area)])]

"""
    force_rating_data()

Each ship of [`sensitivity_ships`](@ref) with the cases of [`force_rating_cases`](@ref):
force_rating.csv.
"""
function force_rating_data()
    cases = reduce(vcat, [force_rating_cases(bare, route, ship, areas.kite.kite_area)
                          for (ship, bare, route, areas) in sensitivity_ships()])
    write_trips("force_rating.csv", cases, round_trips(cases, sampled_departures()), :ship,
        :rating, :area)
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
force_rating.csv that meet `conditions`.
"""
function best_force_rating_saving(table, ship, bare, conditions...)
    chosen = rows(table, "ship" => ship, conditions...)
    return maximum(percent_saving.(table["cost"][chosen], bare))
end

"""
    force_rating_figure()

Saving of each study ship at its best kite area against the force limit.
"""
function force_rating_figure()
    table = read_table(data_file("force_rating.csv"))
    figure = Figure(size=(column_width, 200))
    axis = Axis(figure[1, 1]; xlabel="force limit [kN/m²]", ylabel="cost saving [%]",
        xticks=collect(study_force_ratings))
    for (k, ship) in enumerate(unique(table["ship"]))
        bare = table["cost"][only(rows(table, "ship" => ship, "rating" => 0))]
        savings = [best_force_rating_saving(table, ship, bare, "rating" => rating)
                   for rating in study_force_ratings]
        scatterlines!(axis, collect(study_force_ratings), savings;
            color=category_colours[k], label=ship)
    end
    Legend(figure[2, 1], axis; orientation=:horizontal, nbanks=2)
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
    check_drawn(run_steps(steps, first.(kite_design_figure_steps); fidelity, resume))
end
