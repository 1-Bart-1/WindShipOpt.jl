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

"corridor scale of stages `stage` [nmi] apart"
stages(stage) = stage / WindShipOpt.OCEAN_SPACING

"default router settings with `changes` made"
changed(; changes...) = WindShipOpt.with_changed(WindShipOpt.RouterSettings(); changes...)

"default router settings with far rows a fixed stride apart to the end, and `changes` made"
two_zone(; changes...) = changed(; row_doubling_ratio=Inf, changes...)

"""
The study's entries by name, each a corridor scale and router settings: the planner on its
default settings, with a near part of 480 nmi, and with far rows starting at every second;
on the default grid with far rows a fixed stride apart to the end; on grids with stages of
the named length [nmi] and far rows every fourth; on 60 nmi stages with its time bins alone
halved, and with rows 7.5 nmi apart and far rows 60 nmi apart; refined in grid and time
steps together from 60 nmi stages, by the named factor, with far rows 60 nmi apart; and the
full-corridor search on 240 nmi stages.
"""
STUDY = Dict("base" => planner_fidelity(),
    "near_480" => (; scale=1, settings=changed(; near_distance=480.0)),
    "stride_2" => (; scale=1, settings=changed(; far_row_stride=2)),
    "two_zone" => (; scale=1, settings=two_zone()),
    (name => planner_fidelity(; scale=stages(stage), settings=two_zone())
     for (name, stage) in ("grid_240" => 240, "grid_120" => 120, "grid_60" => 60))...,
    "grid_60_bins_half" => (; scale=stages(60), settings=two_zone(; time_step=1.5)),
    "grid_60_rows_7.5" => (; scale=(stages(60), 7.5 / WindShipOpt.LATERAL_SPACING),
        settings=two_zone(; far_row_stride=8)),
    (name => planner_fidelity(factor; scale=stages(60),
        settings=two_zone(; far_row_stride=round(Int, 4factor)))
     for (name, factor) in ("ladder_240" => 1 / 4, "ladder_120" => 1 / 2,
        "grid_30_steps_half" => 2))...,
    "whole_240" => (; scale=stages(240), settings=two_zone(; near_distance=Inf)))

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
