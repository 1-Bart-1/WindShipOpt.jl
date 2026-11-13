# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Error and run time of the router per corridor grid and search settings, on the 24 cases of
# the router gate:
#
#   julia +1.12 --project=. -t auto scripts/router_grid_study.jl <out_dir>
#   julia +1.12 --project=. -t auto scripts/router_grid_study.jl --table <out_dir> <entry>
#
# Each entry of `STUDY` goes to <out_dir>/<entry> and its times to <out_dir>/times.csv. A
# rerun routes only the entries not yet in that file. `--table` prints, per rig, the mean
# and largest change of the saving of each entry against the entry named <entry>.
include(joinpath(@__DIR__, "router_gate.jl"))

"the search of the study's runs and the search of the finer reference"
SEARCHES = Dict("base" => WindShipOpt.RouterSettings(),
    "fine" => WindShipOpt.RouterSettings(time_step=1.5, search_speed_stride=2,
        search_margins=(0.12, 0.2), kite_search_margins=(0.25, 0.5)),
    "bins" => WindShipOpt.RouterSettings(time_step=1.5),
    "speeds" => WindShipOpt.RouterSettings(search_speed_stride=2),
    "margins" => WindShipOpt.RouterSettings(search_margins=(0.12, 0.2),
        kite_search_margins=(0.25, 0.5)))

"(corridor scale, search) of the study's entries, in the order they are routed"
STUDY = [(4.0, "base"), (2.0, "base"), (1.0, "base"), ((4.0, 2.0), "base"),
    ((2.0, 4.0), "base"), ((1.0, 2.0), "base"), ((2.0, 1.0), "base"), (4.0, "fine"),
    (2.0, "fine"), (1.0, "fine"), (2.0, "bins"), (2.0, "speeds"), (2.0, "margins"),
    (1.0, "bins"), (1.0, "speeds"), (1.0, "margins"), (0.5, "base"), (8.0, "base"),
    (0.5, "fine")]

"name of the directory of a study entry"
entry_name(scale, search) = "$(scale_label(scale))_$search"

"CPU time this process has used, over all its threads [s]"
cpu_seconds() = sum(parse.(Float64, split(read("/proc/self/stat", String))[14:15])) / 100

"""
    run_study(out_dir)

Route the entries of `STUDY` missing from `times.csv` in `out_dir`, adding a line per entry.
"""
function run_study(out_dir)
    mkpath(out_dir)
    times = joinpath(out_dir, "times.csv")
    isfile(times) || write(times, "entry,wall_seconds,cpu_seconds,max_rss_gb\n")
    finished = first.(split.(readlines(times)[2:end], ","))
    foreach(gate_cases(4.0)) do case
        case.design.kite_area > 0 && Ship(case.design, assumptions)
    end
    for (scale, search) in STUDY
        name = entry_name(scale, search)
        name in finished && continue
        directory = joinpath(out_dir, name)
        rm(directory; force=true, recursive=true)
        cpu = cpu_seconds()
        wall = @elapsed run_gate(directory; scales=(scale,), settings=SEARCHES[search])
        line = join((name, round(wall; digits=1), round(cpu_seconds() - cpu; digits=1),
                round(Sys.maxrss() / 2^30; digits=1)), ",")
        open(io -> println(io, line), times, "a")
        println(line)
        empty!(WindShipOpt.FREE_WORKSPACES)
        GC.gc()
    end
end

"""
    entry_costs(out_dir, name)

Costs of the gate file of the study entry `name` in `out_dir`.
"""
function entry_costs(out_dir, name)
    directory = joinpath(out_dir, name)
    return read_gate(joinpath(directory, only(readdir(directory))))
end

"""
    rig_changes(entry, reference, rig)

The changes of the saving of `rig` in the costs `entry` against `reference` [points].
"""
function rig_changes(entry, reference, rig)
    rig_keys = [key for key in keys(reference) if key[2] == rig]
    pairs = [(saving(entry, key), saving(reference, key)) for key in rig_keys]
    return [entry_saving - reference_saving
            for (entry_saving, reference_saving) in pairs
            if !isnothing(entry_saving) && !isnothing(reference_saving)]
end

"""
    study_table(out_dir, reference)

Print, for each finished entry in `out_dir`, the wall and CPU time and per rig the mean and
largest change of the saving against the entry `reference` [points].
"""
function study_table(out_dir, reference)
    target = entry_costs(out_dir, reference)
    println("entry, wall s, CPU s, kite mean (max), wings mean (max), rotors mean (max)")
    for row in split.(readlines(joinpath(out_dir, "times.csv"))[2:end], ",")
        costs = entry_costs(out_dir, row[1])
        @printf("%-16s %7s %8s", row[1], row[2], row[3])
        for rig in ("kite", "wings", "rotors")
            changes = rig_changes(costs, target, rig)
            @printf("  %+6.2f (%5.2f)", sum(changes) / length(changes),
                maximum(abs, changes))
        end
        println()
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    first(ARGS) == "--table" ? study_table(ARGS[2:end]...) : run_study(ARGS...)
end
