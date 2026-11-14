# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Error and run time of the planner per fidelity, on the gate's development cases:
#
#   julia +1.12 --project=. -t auto scripts/router_grid_study.jl <out_dir> [entry...]
#   julia +1.12 --project=. -t auto scripts/router_grid_study.jl --table <out_dir> <entry>
#
# Routes each named entry of `STUDY`, or all of them, into <out_dir>/<entry>, skipping cases
# already there. `--table` prints, per entry, the CPU time per case and each rig's saving
# against the entry named <entry>, and whether it meets the standard against it.
include(joinpath(@__DIR__, "router_gate.jl"))

"settings of the planner the study varies from"
base_settings = WindShipOpt.RouterSettings()

"`base_settings` with the fields `changes` replaced"
varied(; changes...) = WindShipOpt.with_changed(base_settings; changes...)

"the study's entries by name, each a corridor scale and router settings"
STUDY = Dict("coarse" => planner_fidelity(0.5), "base" => planner_fidelity(1),
    "fine" => planner_fidelity(2), "finest" => planner_fidelity(4),
    "final_1h" => (; scale=1, settings=varied(final_time_step=1.0)),
    "near_480" => (; scale=1, settings=varied(near_distance=480.0)),
    "near_120" => (; scale=1, settings=varied(near_distance=120.0)),
    "rows_4" => (; scale=1, settings=varied(far_row_stride=4)),
    "rows_16" => (; scale=1, settings=varied(far_row_stride=16)),
    "legs_360" => (; scale=(1.5, 1), settings=base_settings),
    "legs_480" => (; scale=(2, 1), settings=base_settings),
    "rows_30" => (; scale=(1, 0.5), settings=base_settings),
    "legs_480_rows_30" => (; scale=(2, 0.5), settings=base_settings),
    "to_go_48" => (; scale=1, settings=varied(to_go_step=48.0)),
    "final_1h_legs_360" => (; scale=(1.5, 1), settings=varied(final_time_step=1.0)),
    "near_960" => (; scale=1, settings=varied(near_distance=960.0)),
    "near_1920" => (; scale=1, settings=varied(near_distance=1920.0)),
    "rows_1" => (; scale=1, settings=varied(far_row_stride=1)),
    "far_samples_3" => (; scale=1, settings=varied(far_sample_hours=3.0)),
    "legs_120" => (; scale=(0.5, 1), settings=base_settings),
    "grid_fine" => (; scale=0.5, settings=base_settings),
    "grid_finest" => (; scale=0.25, settings=base_settings),
    "grid_8x" => (; scale=0.125, settings=base_settings),
    "grid_finest_steps_fine" => planner_fidelity(2; scale=0.5),
    "steps_fine" => planner_fidelity(2; scale=2),
    "whole" => (; scale=1, settings=varied(near_distance=Inf)))

"""
    run_study(out_dir, names=keys(STUDY))

Route the development cases of each entry of `STUDY` in `names` into `out_dir`/<name>.
"""
function run_study(out_dir, names=keys(STUDY))
    for name in names
        gate_trips(joinpath(out_dir, name), development_cases(), STUDY[name])
        empty!(WindShipOpt.FREE_WORKSPACES)
        GC.gc()
        println(name, " done")
    end
end

"""
    cpu_per_case(directory)

CPU time per case of the gate run in `directory` [s], over all its runs.
"""
function cpu_per_case(directory)
    rows = split.(readlines(joinpath(directory, "times.csv"))[2:end], ",")
    return sum(parse(Float64, row[3]) for row in rows) /
           sum(parse(Int, row[1]) for row in rows)
end

"""
    study_table(out_dir, reference)

Print, for each finished entry in `out_dir`, its CPU time per case and each rig's saving
against the entry `reference`, and whether it meets the standard against it.
"""
function study_table(out_dir, reference)
    target = read_gate(joinpath(out_dir, reference, "gate.csv"))
    for name in sort!(filter(name -> isdir(joinpath(out_dir, name)), readdir(out_dir)))
        @printf("== %s: %.0f CPU-s per case\n", name, cpu_per_case(joinpath(out_dir, name)))
        passed = standard_passes(read_gate(joinpath(out_dir, name, "gate.csv")), target)
        println(passed ? "meets the standard" : "fails the standard")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    first(ARGS) == "--table" ? study_table(ARGS[2:end]...) :
    run_study(ARGS[1], length(ARGS) > 1 ? ARGS[2:end] : keys(STUDY))
end
