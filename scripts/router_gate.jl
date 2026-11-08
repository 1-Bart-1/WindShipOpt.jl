# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Accuracy gate of the weather router: routes 24 cases at corridor scales 2 and 4 and
# compares the saving of each rig against the same ship without a rig with a reference.
#
#   julia +1.12 --project=. -t auto scripts/router_gate.jl <out_dir> [reference_dir]
#   julia +1.12 --project=. -t auto scripts/router_gate.jl --reference <out_dir>
#   julia +1.12 --project=. -t auto scripts/router_gate.jl --fresh <reference_dir> <out_dir>
#   julia +1.12 --project=. -t auto scripts/router_gate.jl --refine <start_scale> <scale> \
#       <out_dir> [reference_dir]
#
# Writes gate_<scale>.csv to <out_dir>, a line per finished case; a rerun on the same code
# and settings routes only the cases missing there, so another run needs an empty directory.
# Given a reference directory holding gate_<scale>.csv, prints the change per case and exits
# 1 if a saving moves by more than `SAVING_TOLERANCE` points. `--reference` searches every
# state, which makes such a directory. `--fresh` makes the reference and compares with it, a
# scale at a time and in one process, so both see the same code and inputs. `--refine`
# routes at one scale by refining the optimal route at `start_scale`; compared with a run of
# the full router at that scale, it prints the change of each saving and its spread per rig.
# A convergence check is `run_gate` with other `RouterSettings`, compared the same way.
using Printf
include(joinpath(@__DIR__, "setup.jl"))

"largest change of a saving against the reference that passes the gate [points]"
SAVING_TOLERANCE = 0.02

"largest relative change of the cost of a ship without a rig that passes the gate [-]"
BARE_COST_TOLERANCE = 2e-4

"first line of a gate file"
GATE_HEADER = "ship,rig,route,scale,cost,fuel,days,flight,launches,forced,cargo,seconds"

"router settings of a reference run: every state is searched"
REFERENCE_SETTINGS = WindShipOpt.RouterSettings(search_margins=(Inf, Inf),
    kite_search_margins=(Inf, Inf))

"""
    gate_cases(scale, start_scale=scale)

The cases at corridor `scale`, refined from `start_scale`: a 140 m methanol ship and a
Kamsarmax on VLSFO, without a rig and with each rig, on three routes.
"""
function gate_cases(scale, start_scale=scale)
    kamsarmax = ship_classes()["Kamsarmax bulk carrier"]
    ships = (("140m", (:methanol, 140.0), (1600.0, 1500.0, 800.0)),
        ("kamsarmax", (:vlsfo, kamsarmax), (3200.0, 3000.0, 1600.0)))
    cases = []
    for (ship, arguments, (kite, wings, rotors)) in ships
        rigs = (("none", (;)), ("kite", (; kite_area=kite)), ("wings", (; wing_area=wings)),
            ("rotors", (; rotor_area=rotors)))
        for (rig, area) in rigs, route in (:caribbean, :new_york, :tubarao)
            design = ShipDesign(arguments...; area...)
            push!(cases, (; ship, rig, route, scale, start_scale, design))
        end
    end
    return cases
end

"""
    gate_line(case, trip, seconds)

The line of a gate file for `case`, `trip` being `nothing` where it is infeasible.
"""
function gate_line(case, trip, seconds)
    values = isnothing(trip) ? fill("NA", 7) : repr.((trip.cost_per_tonne_km,
        trip.fuel_per_tonne_km, trip.outbound_days + trip.return_days, trip.flight_share,
        trip.launches, trip.forced_landings, trip.cargo))
    return join((case.ship, case.rig, case.route, case.scale, values...,
            round(seconds; digits=2)), ",")
end

"""
    gate_trips(path, cases, sampled)

Route the round trip over the departures `sampled` of each of `cases` not yet in the gate
file `path`, threaded, adding each line to the file as its case finishes.
"""
function gate_trips(path, cases, sampled)
    isfile(path) || write(path, GATE_HEADER * "\n")
    finished = keys(read_gate(path))
    waiting = filter(case -> (case.ship, case.rig, String(case.route)) ∉ finished, cases)
    for case in waiting
        case.design.kite_area > 0 && Ship(case.design, assumptions)
        corridors(case.route, case.scale, case.start_scale)
    end
    file_lock = ReentrantLock()
    Threads.@threads :greedy for case in waiting
        seconds = @elapsed begin
            ship = Ship(case.design, assumptions)
            trip = isnothing(ship) ? nothing : round_trip(ship,
                corridors(case.route, case.scale, case.start_scale)..., weather, sampled,
                assumptions)
        end
        line = gate_line(case, trip, seconds)
        lock(() -> open(io -> println(io, line), path, "a"), file_lock)
    end
end

"""
    read_gate(path)

Cost per tonne-km of each case of the gate file `path` by (ship, rig, route), `nothing`
where infeasible.
"""
function read_gate(path)
    rows = split.(readlines(path)[2:end], ",")
    return Dict((row[1], row[2], row[3]) => tryparse(Float64, row[5]) for row in rows)
end

"""
    saving(costs, (ship, rig, route))

Saving of the rig against the same ship without a rig [points], `nothing` where either
is infeasible.
"""
function saving(costs, (ship, rig, route))
    bare, rigged = costs[(ship, "none", route)], costs[(ship, rig, route)]
    (isnothing(bare) || isnothing(rigged)) && return nothing
    return 100 * (1 - rigged / bare)
end

"""
    saving_change(new, reference, key)

Change of the saving of the rigged case `key` in the costs `new` against `reference`
[points], `nothing` where either is infeasible.
"""
function saving_change(new, reference, key)
    new_saving, reference_saving = saving(new, key), saving(reference, key)
    (isnothing(new_saving) || isnothing(reference_saving)) && return nothing
    return new_saving - reference_saving
end

"""
    print_spread(new, reference)

Print the smallest, mean and largest change of the savings of each rig in the costs `new`
against `reference` [points].
"""
function print_spread(new, reference)
    for rig in ("kite", "wings", "rotors")
        changes = filter(!isnothing, [saving_change(new, reference, key)
                                      for key in keys(reference) if key[2] == rig])
        isempty(changes) && continue
        @printf("%-6s %2d savings: change %+.3f to %+.3f, mean %+.3f points\n", rig,
            length(changes), minimum(changes), maximum(changes),
            sum(changes) / length(changes))
    end
end

"""
    case_passes(new, reference, key)

Print the case `key` of the costs `new` against `reference`; whether it is inside the
tolerances.
"""
function case_passes(new, reference, key)
    if isnothing(new[key]) != isnothing(reference[key])
        println(join(key, " "), ": feasibility differs")
        return false
    end
    isnothing(new[key]) && return true
    if key[2] == "none"
        change = new[key] / reference[key] - 1
        @printf("%-34s cost %+.5f %%\n", join(key, " "), 100change)
        return abs(change) <= BARE_COST_TOLERANCE
    end
    new_saving, reference_saving = saving(new, key), saving(reference, key)
    if isnothing(new_saving) != isnothing(reference_saving)
        println(join(key, " "), ": feasibility of the ship without a rig differs")
        return false
    end
    isnothing(new_saving) && return true
    change = new_saving - reference_saving
    @printf("%-34s saving %6.2f, change %+.3f points\n", join(key, " "), new_saving, change)
    return abs(change) <= SAVING_TOLERANCE
end

"""
    gate_passes(path, reference_path)

Compare the gate file `path` with `reference_path`, printing each case; whether all pass.
"""
function gate_passes(path, reference_path)
    new, reference = read_gate(path), read_gate(reference_path)
    passed = all([case_passes(new, reference, key)
                  for key in sort!(collect(keys(reference)))])
    print_spread(new, reference)
    return passed
end

"""
    gate_scales(out_dir, reference_dir, scales, start_scale)

Run the gate at `scales` under the router settings in force, refined from `start_scale`
where given, writing to `out_dir`; whether every case is inside the tolerances of the files
in `reference_dir`, if any.
"""
function gate_scales(out_dir, reference_dir, scales, start_scale)
    mkpath(out_dir)
    passed = true
    for scale in scales
        path = joinpath(out_dir, "gate_$(Int(scale)).csv")
        cases = gate_cases(scale, something(start_scale, scale))
        wall = @elapsed gate_trips(path, cases, departures[1:6:end])
        @printf("scale %.0f: all cases in %s after %.0f s\n", scale, path, wall)
        isnothing(reference_dir) && continue
        passed &= gate_passes(path, joinpath(reference_dir, basename(path)))
    end
    return passed
end

"""
    run_gate(out_dir, reference_dir=nothing; scales=(4.0, 2.0), start_scale=nothing,
             settings=RouterSettings())

[`gate_scales`](@ref) under the router `settings`.
"""
run_gate(out_dir, reference_dir=nothing; scales=(4.0, 2.0), start_scale=nothing,
    settings=WindShipOpt.RouterSettings()) =
    WindShipOpt.with_router_settings(
        () -> gate_scales(out_dir, reference_dir, scales, start_scale), settings)

"""
    fresh_gate(reference_dir, out_dir; scales=(4.0, 2.0))

Make the reference in `reference_dir` and run the gate against it in `out_dir`, a scale at a
time; whether every case is inside the tolerances.
"""
function fresh_gate(reference_dir, out_dir; scales=(4.0, 2.0))
    passed = true
    for scale in scales
        run_gate(reference_dir; scales=(scale,), settings=REFERENCE_SETTINGS)
        passed &= run_gate(out_dir, reference_dir; scales=(scale,))
    end
    return passed
end

if abspath(PROGRAM_FILE) == @__FILE__
    if first(ARGS) == "--reference"
        run_gate(ARGS[2]; settings=REFERENCE_SETTINGS)
        exit(0)
    end
    first(ARGS) == "--fresh" && exit(fresh_gate(ARGS[2:end]...) ? 0 : 1)
    if first(ARGS) == "--refine"
        start_scale, scale = parse.(Float64, ARGS[2:3])
        exit(run_gate(ARGS[4:end]...; scales=(scale,), start_scale) ? 0 : 1)
    end
    exit(run_gate(ARGS...) ? 0 : 1)
end
