# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Regenerates the data, figures and tables of the paper. In a REPL in the scripts
# environment:
#
#     include("paper.jl")
#     paper(; fidelity=:final)                 # every step: data, then figures and tables
#     paper(; fidelity=:draft)                 # the same, faster and marked as a draft
#     paper(:designs, :routes; fidelity=:draft)  # only these steps
#     paper(:figures; fidelity=:final)         # all figures from the latest final data
#     paper(; fidelity=:draft, resume=true)    # continue this branch's unfinished run
#     paper(:sea_effect; fidelity=:draft)      # a method study, its run and its tables
#
# A paper run computes the results. Method studies, which choose or check a method, run
# only by name: paper/study_runs.toml records the run each comes from, which its figures
# read and the paper names with its commit, and its tables are written only then.
# Data steps write CSV files to a run directory output/runs/<start time>/ with the record
# run.toml and the finished round trips, so that a run cut short resumes; without `resume`
# paper() asks whether to continue an unfinished run. A final run needs a clean tree on a
# pushed commit; run.toml records the commit. Figure steps write PDFs to paper/figures/
# and table steps LaTeX to paper/sections/; draft results are marked in the paper. The
# LaTeX build is separate.
using CairoMakie
using Dates
using Printf
using Statistics
using WindShipOpt

include("setup.jl")
include("map_plotting.jl")

root = joinpath(@__DIR__, "..")
sections = mkpath(joinpath(root, "paper", "sections"))

include("paper_runs.jl")
include("size_search.jl")
include("paper_data.jl")
include("explorer_data.jl")
include("passages_data.jl")
include("grids_data.jl")
include("cargo_groups.jl")
include("paper_figures.jl")
include("paper_drawings.jl")
include("router_figures.jl")
include("paper_tables.jl")

"data steps of the results in the order they run, each writing one or two data files"
data_steps = [:patterns => patterns_data, :designs => designs_data,
    :routes => routes_data, :classes => classes_data, :forecast => forecast_data,
    :forecast_result => forecast_result_data, :sensitivity => sensitivity_data,
    :goal_size_data => goal_size_data,
    :availability_data => availability_data,
    :canopy_life_data => canopy_life_data, :canopy_price_data => canopy_price_data,
    :situations_data => situations_data,
    :wind_angle_data => wind_angle_data, :route_tracks => route_tracks_data,
    :canopy_tension => canopy_tension_data,
    :abatement_data => abatement_data,
    :combination_data => combination_data,
    :rigid_scaling_data => rigid_scaling_data, :rigid_kite_data => rigid_kite_data,
    :flight => flight_data, :speed_choice => speed_choice_data,
    :speed_size => speed_size_data]

"""
method studies, which choose or check a method or setting, run only by name: each records
its run for its figures and writes its tables
"""
study_steps = [:forecast_plans => forecast_plans_data,
    :forecast_replanning => forecast_replanning_data,
    :forecast_hours => forecast_hours_data,
    :forecast_causes => forecast_causes_data,
    :forecast_live => forecast_live_data,
    :cargo_interest => cargo_interest_data, :base_kite => base_kite_data,
    :launch => launch_data, :sea_effect => sea_effect_data,
    :convergence => convergence_data, :speed_terms => speed_terms_data,
    :published_terms => published_terms_data, :tow_point => tow_point_data,
    :model_parts => model_parts_data, :size_search => size_search_data,
    :router_decisions => router_decisions_data,
    :routing_value => routing_value_data]

"table steps of each method study, written when it runs or by name from its recorded run"
study_tables = Dict(:forecast_plans => [:forecast_plans_table => forecast_plans_table],
    :forecast_replanning => [:forecast_replanning_table => forecast_replanning_table],
    :forecast_hours => [:forecast_hours_table => forecast_hours_table],
    :forecast_causes => [:forecast_causes_table => forecast_causes_table],
    :forecast_live => [:forecast_live_table => forecast_live_table],
    :cargo_interest => [:cargo_interest_table => cargo_interest_table],
    :sea_effect => [:sea_effect_table => sea_effect_table],
    :speed_terms => [:speed_terms_table => speed_terms_table],
    :published_terms => [:published_table => published_table],
    :routing_value => [:routing_value_table => routing_value_table])

"every table step of the method studies"
study_table_steps() = unique(reduce(vcat, values(study_tables)))

"steps outside the paper, run only by name: the data of the companion website"
website_steps = [:explorer => explorer_data, :passages => passages_data,
    :grids => grids_data]

"figure and table steps, each reading the data files and writing one output"
output_steps = [:kite => kite_figure,
    :wind_load => wind_load_figure,
    :capital => capital_figure, :patterns_figure => pattern_figure,
    :canopy_tension_figure => canopy_tension_figure,
    :rig_polar => rig_polar_figure, :routes_figure => route_figure,
    :passage => passage_figure,
    :premium => premium_figure, :breakdown => breakdown_figure,
    :rig_comparison => rig_comparison_figure,
    :season_figure => season_figure,
    :class_comparison => class_comparison_figure, :class_sizes => class_size_figure,
    :cargo_interest_figure => cargo_interest_figure,
    :winner_map => winner_map_figure,
    :situations_figure => situations_figure,
    :fuels => fuel_figure,
    :wind_angle_figure => wind_angle_figure,
    :sensitivity_figure => sensitivity_figure,
    :forecast_figure => forecast_figure, :input_tables => input_tables,
    :rotor_prices_table => rotor_prices_table,
    :development_table => development_table,
    :class_table => class_dimension_table, :fidelity_table => fidelity_table,
    :drift_check_table => drift_check_table,
    :split_table => split_table,
    :payback_table => payback_table, :market_table => market_table,
    :goals_table => goals_table,
    :missed_goals_table => missed_goals_table,
    :rig_margin_table => rig_margin_table,
    :abatement => abatement_figure, :combination => combination_figure,
    :rigid_scaling => rigid_scaling_figure, :rigid_kite => rigid_kite_figure,
    :flight_table => flight_table, :speed_choice_table => speed_choice_table,
    :speed_size_figure => speed_size_figure,
    :min_wind => min_wind_figure,
    :force_balance => force_balance_figure, :ship_classes => ship_classes_figure,
    :kite_frames => kite_frames_figure, :router => router_figure,
    :missed_goals => missed_goals_figure, :cargo_cost => cargo_cost_figure,
    :large_rigs => large_rigs_figure, :kite_mass => kite_mass_figure,
    :canopy_cells => canopy_cells_figure,
    :tow_point_figure => tow_point_figure,
    :fleet_share => fleet_share_figure, :numbers => numbers_file,
    :figure_style => figure_style_file, :rigid_numbers => rigid_numbers_file]

"""
    paper(names...; fidelity, resume=nothing, only=nothing)

Run the named steps, or every data step of the results and then every figure and table
step when no name is given, at `fidelity` (:draft or :final); `:data` and `:figures` run all
steps of that kind. Any step but figures and tables alone runs in a new or resumed run:
`resume` true takes the latest unfinished run at `fidelity` on this git branch, false none,
and nothing asks on stdin.
Steps that run has done are skipped, and it counts as finished once every step asked of it
is done. Round trips the case store holds for the code and inputs are reused. A draft with
`only`, labels and their values such as `(class="handysize", route=:caribbean)`, computes
only the cases carrying them and keeps the latest stored round trip of the others, of any
code. A final run errors on a dirty tree or unpushed commit.
"""
function paper(names::Symbol...; fidelity, resume=nothing, only=nothing)
    steps = isempty(names) ? [data_steps; output_steps] :
            [step for name in names for step in selected_steps(name)]
    run_steps(steps, first.([output_steps; study_table_steps()]); fidelity, resume, only)
    mark_fidelity(joinpath(sections, "fidelity.tex"), fidelity, first.(steps),
        first.(output_steps))
    return nothing
end

"""
    run_steps(steps, outputs; fidelity, resume, only=nothing)

Run `steps` at `fidelity` in a new or resumed run as [`paper`](@ref) does, or without a run
when all of them are among the figure and table steps `outputs`.
"""
function run_steps(steps, outputs; fidelity, resume, only=nothing)
    haskey(fidelities, fidelity) || throw(ArgumentError("no fidelity $fidelity"))
    global paper_run = all(in(outputs), first.(steps)) ? PaperRun(fidelity) :
                       open_run(fidelity, first.(steps), resume; only)
    for (name, step) in steps
        if step_done(paper_run, name)
            println("step ", name, " already done")
            continue
        end
        run_step!(paper_run, name, step)
    end
    finish_run!(paper_run)
end

"""
    selected_steps(name)

The steps `name` stands for: all data steps for `:data`, all figure and table steps for
`:figures`, for a method study the study, its record and its tables, otherwise the one step
of that name.
"""
function selected_steps(name)
    name == :data && return data_steps
    name == :figures && return output_steps
    for (study, step) in study_steps
        study == name && return [study => step;
                                 Symbol(study, :_record) => () -> record_study(study);
                                 get(study_tables, study, [])]
    end
    steps = [data_steps; study_table_steps(); output_steps; website_steps]
    matches = filter(step -> first(step) == name, steps)
    isempty(matches) && throw(ArgumentError("no paper step $name"))
    return matches
end

"""
    paper_status(; fidelity)

Print for each data step and method study at `fidelity` whether the data the paper reads
from it are current and, where not, why and whether its round trips recompute; return the
names of those out of date in the order they run, for [`paper`](@ref). A step is out of
date where [`step_reasons`](@ref) gives a reason or it reads a data file of a step that is.
At `:final`, also print whether all of them come from one clean commit.
"""
function paper_status(; fidelity)
    previous = paper_run
    global paper_run = PaperRun(fidelity)
    try
        return print_steps_status(fidelity)
    finally
        global paper_run = previous
    end
end

"""
    print_steps_status(fidelity)

Print and return what [`paper_status`](@ref) does, with the run in use set to `fidelity`.
"""
function print_steps_status(fidelity)
    definitions = script_definitions(script_files())
    current_trips = trip_model(definitions)
    steps = [data_steps; study_steps]
    found = Dict(name => step_location(name) for (name, _) in steps)
    reasons = Dict(name => isnothing(found[name]) ? ["never ran at $fidelity fidelity"] :
                           step_reasons(last(found[name]), step_code(definitions, step))
                   for (name, step) in steps)
    makers = Dict(file => name for (name, location) in found if !isnothing(location)
                  for file in last(location)["files"])
    spread_staleness!(reasons, found, makers)
    for (name, _) in steps
        print_status(name, found[name], reasons[name], current_trips)
    end
    fidelity == :final &&
        print_commits(part_commits(filter(!isnothing, collect(values(found)))))
    return [name for (name, _) in steps if !isempty(reasons[name])]
end
