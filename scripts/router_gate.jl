# Accuracy gate of the weather router: routes 24 cases at corridor scales 2 and 4 and
# compares the saving of each rig against the same ship without a rig with a reference.
#
#   julia +1.12 --project=. -t auto scripts/router_gate.jl <out_dir> [reference_dir]
#   julia +1.12 --project=. -t auto scripts/router_gate.jl --reference <out_dir>
#
# Writes gate_<scale>.csv to <out_dir>. Given a reference directory holding
# gate_<scale>.csv, prints the change per case and exits 1 if a saving moves by more than
# `SAVING_TOLERANCE` points. `--reference` searches every state, which makes such a
# directory. A convergence check is `run_gate` with other `RouterSettings`, compared the
# same way.
using Printf
include(joinpath(@__DIR__, "setup.jl"))

"largest change of a saving against the reference that passes the gate [points]"
SAVING_TOLERANCE = 0.02

"largest relative change of the cost of a ship without a rig that passes the gate [-]"
BARE_COST_TOLERANCE = 2e-4

"""
    gate_cases(scale)

The cases at corridor `scale`: a 140 m methanol ship and a Kamsarmax on VLSFO, without a
rig and with each rig, on three routes.
"""
function gate_cases(scale)
    kamsarmax = ship_classes()["Kamsarmax bulk carrier"]
    ships = (("140m", (:methanol, 140.0), (1600.0, 1500.0, 800.0)),
        ("kamsarmax", (:vlsfo, kamsarmax), (3200.0, 3000.0, 1600.0)))
    cases = []
    for (ship, arguments, (kite, wings, rotors)) in ships
        rigs = (("none", (;)), ("kite", (; kite_area=kite)), ("wings", (; wing_area=wings)),
            ("rotors", (; rotor_area=rotors)))
        for (rig, area) in rigs, route in (:caribbean, :new_york, :tubarao)
            design = ShipDesign(arguments...; area...)
            push!(cases, (; ship, rig, route, scale, design))
        end
    end
    return cases
end

"""
    gate_trips(cases, sampled)

Round trip of each of `cases` over the departures `sampled`, threaded, and the seconds
each took; `nothing` for a ship that does not exist or a passage that fails.
"""
function gate_trips(cases, sampled)
    for case in cases
        case.design.kite_area > 0 && Ship(case.design, assumptions)
        corridors(case.route, case.scale)
    end
    trips = Vector{Any}(nothing, length(cases))
    seconds = zeros(length(cases))
    Threads.@threads :greedy for k in eachindex(cases)
        case = cases[k]
        seconds[k] = @elapsed begin
            ship = Ship(case.design, assumptions)
            trips[k] = isnothing(ship) ? nothing : round_trip(ship,
                corridors(case.route, case.scale)..., weather, sampled, assumptions)
        end
    end
    return trips, seconds
end

"""
    write_gate(path, cases, trips, seconds)

Write the results of a gate run to `path`, one line per case.
"""
function write_gate(path, cases, trips, seconds)
    open(path, "w") do io
        println(io,
            "ship,rig,route,scale,cost,fuel,days,flight,parked,launches,cargo,seconds")
        for (case, trip, time) in zip(cases, trips, seconds)
            values = isnothing(trip) ? fill("NA", 7) : repr.((trip.cost_per_tonne_km,
                trip.fuel_per_tonne_km, trip.outbound_days + trip.return_days,
                trip.flight_share, trip.parked_share, trip.launches, trip.cargo))
            println(io, join((case.ship, case.rig, case.route, case.scale, values...,
                    round(time; digits=2)), ","))
        end
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
    return all([case_passes(new, reference, key)
                for key in sort!(collect(keys(reference)))])
end

"""
    gate_scales(out_dir, reference_dir, scales)

Run the gate at `scales` under the router settings in force, writing to `out_dir`; whether
every case is inside the tolerances of the files in `reference_dir`, if any.
"""
function gate_scales(out_dir, reference_dir, scales)
    mkpath(out_dir)
    passed = true
    for scale in scales
        cases = gate_cases(scale)
        wall = @elapsed trips, seconds = gate_trips(cases, departures[1:6:end])
        path = joinpath(out_dir, "gate_$(Int(scale)).csv")
        write_gate(path, cases, trips, seconds)
        @printf("scale %.0f: %d of %d feasible, %.0f s wall, %.0f s summed\n", scale,
            count(!isnothing, trips), length(trips), wall, sum(seconds))
        isnothing(reference_dir) && continue
        passed &= gate_passes(path, joinpath(reference_dir, basename(path)))
    end
    return passed
end

"""
    run_gate(out_dir, reference_dir=nothing; scales=(2.0, 4.0), settings=RouterSettings())

[`gate_scales`](@ref) under the router `settings`.
"""
run_gate(out_dir, reference_dir=nothing; scales=(2.0, 4.0),
    settings=WindShipOpt.RouterSettings()) =
    WindShipOpt.with_router_settings(() -> gate_scales(out_dir, reference_dir, scales),
        settings)

if abspath(PROGRAM_FILE) == @__FILE__
    settings = WindShipOpt.RouterSettings(search_margins=(Inf, Inf))
    first(ARGS) == "--reference" && (run_gate(ARGS[2]; settings); exit(0))
    exit(run_gate(ARGS...) ? 0 : 1)
end
