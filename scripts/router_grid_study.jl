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

"""
The study's entries by name, each a corridor scale and router settings: the planner on its
default settings and on grids with stages of the named length [nmi], its time steps halved,
and the full-corridor search on 240 nmi stages.
"""
STUDY = Dict("base" => planner_fidelity(), "grid_240" => planner_fidelity(; scale=4),
    "grid_120" => planner_fidelity(; scale=2), "grid_30" => planner_fidelity(; scale=0.5),
    "steps_half" => planner_fidelity(2; scale=2),
    "whole_240" => (; scale=4,
        settings=WindShipOpt.with_changed(WindShipOpt.RouterSettings(); near_distance=Inf)))

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
