# Regenerates the data, figures and tables of the paper. In a REPL in the scripts
# environment:
#
#     include("paper.jl")
#     paper(; fidelity=:final)                 # every step: data, then figures and tables
#     paper(; fidelity=:draft)                 # the same, faster and marked as a draft
#     paper(:designs, :routes; fidelity=:draft)  # only these steps
#     paper(:figures; fidelity=:final)         # all figures from the latest final data
#     paper(; fidelity=:draft, resume=true)    # continue the latest unfinished run unasked
#
# Data steps write CSV files to a run directory output/runs/<start time>/ with the record
# run.toml and the finished round trips, so that a run cut short resumes; without `resume`
# paper() asks whether to continue an unfinished run. A final run needs a clean tree on a
# pushed commit; run.toml records the commit. Figure steps write PDFs to paper/figures/
# and table steps LaTeX to paper/sections/; draft results are marked in the paper. The
# LaTeX build is separate.
using CairoMakie
using Printf
using Statistics
using WindShipOpt

include("setup.jl")
include("map_plotting.jl")

root = joinpath(@__DIR__, "..")
sections = mkpath(joinpath(root, "paper", "sections"))

include("paper_runs.jl")
include("paper_data.jl")
include("explorer_data.jl")
include("paper_figures.jl")
include("paper_tables.jl")

"data steps in the order they run, each writing one or two data files"
data_steps = [:patterns => patterns_data, :designs => designs_data,
    :routes => routes_data, :classes => classes_data, :forecast => forecast_data,
    :sensitivity => sensitivity_data, :availability_data => availability_data,
    :situations_data => situations_data,
    :wind_angle_data => wind_angle_data, :abatement_data => abatement_data,
    :components => components_data, :combination_data => combination_data,
    :launch_parking => launch_parking_data, :convergence => convergence_data]

"steps outside the paper, run only by name: the data of the companion website"
website_steps = [:explorer => explorer_data]

"figure and table steps, each reading the data files and writing one output"
output_steps = [:kite_geometry => kite_geometry_figure, :polars => polar_figure,
    :capital => capital_figure, :patterns_figure => pattern_figure,
    :rig_polar => rig_polar_figure, :routes_figure => route_figure,
    :wind_climate => wind_climate_figure, :passage => passage_figure,
    :premium => premium_figure, :breakdown => breakdown_figure,
    :rig_comparison => rig_comparison_figure, :route_comparison => route_comparison_figure,
    :class_comparison => class_comparison_figure, :class_sizes => class_size_figure,
    :winner_map => winner_map_figure, :life => life_figure,
    :situations_figure => situations_figure, :wind_angle_figure => wind_angle_figure,
    :sensitivity_figure => sensitivity_figure, :components_figure => component_figure,
    :forecast_figure => forecast_figure, :input_tables => input_tables,
    :class_table => class_table, :fuel_table => fuel_table,
    :payback_table => payback_table, :availability_table => availability_table,
    :abatement => abatement_figure, :combination => combination_figure]

"""
    paper(names...; fidelity, resume=nothing)

Run the named steps, or every data step and then every figure and table step when no name
is given, at `fidelity` (:draft or :final); `:data` and `:figures` run all steps of that
kind. Any step but figures and tables alone runs in a new or resumed run: `resume` true
takes the latest unfinished run at `fidelity`, false none, and nothing asks on stdin.
Steps that run has done are skipped, and it counts as finished once every step asked of it
is done. A final run errors on a dirty tree or unpushed commit.
"""
function paper(names::Symbol...; fidelity, resume=nothing)
    haskey(fidelities, fidelity) || throw(ArgumentError("no fidelity $fidelity"))
    steps = isempty(names) ? [data_steps; output_steps] :
            [step for name in names for step in selected_steps(name)]
    global paper_run = all(in(first.(output_steps)), first.(steps)) ?
                       PaperRun(nothing, fidelity, Dict{String, Any}(), 0, 0) :
                       open_run(fidelity, first.(steps), resume)
    for (name, step) in steps
        if step_done(paper_run, name)
            println("step ", name, " already done")
            continue
        end
        run_step!(paper_run, name, step)
    end
    finish_run!(paper_run)
    mark_fidelity(joinpath(sections, "fidelity.tex"), fidelity, first.(steps),
        first.(output_steps))
    return nothing
end

"""
    selected_steps(name)

The steps `name` stands for: all data steps for `:data`, all figure and table steps for
`:figures`, otherwise the one step of that name.
"""
function selected_steps(name)
    name == :data && return data_steps
    name == :figures && return output_steps
    matches = [step for step in [data_steps; output_steps; website_steps]
               if first(step) == name]
    isempty(matches) && throw(ArgumentError("no paper step $name"))
    return matches
end
