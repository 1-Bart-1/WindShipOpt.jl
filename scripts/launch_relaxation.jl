# Compares the kite savings of approximations of the router's launch logic with the
# full router's on the kite cases of the accuracy gate, per ship and route.
#
#   julia +1.12 --project=. -t auto scripts/launch_relaxation.jl <out_dir> <scale> [name...]
#
# Writes <name>_<scale>.csv to <out_dir> for each of `names` (default all of
# `LAUNCH_APPROXIMATIONS`), with the ships without a rig in bare_<scale>.csv, and prints
# what [`print_savings`](@ref) reports over every file there. A rerun routes only the
# cases missing from the files.
include("router_gate.jl")

"router settings of the full router and each approximation compared with it"
LAUNCH_APPROXIMATIONS = (bare=WindShipOpt.RouterSettings(),
    full=WindShipOpt.RouterSettings(),
    free=WindShipOpt.RouterSettings(launch_spread_hours=Inf, settle_launches=false),
    settled=WindShipOpt.RouterSettings(launch_spread_hours=Inf),
    narrow=WindShipOpt.RouterSettings(launch_spread_hours=Inf,
        kite_search_margins=WindShipOpt.RouterSettings().search_margins),
    spread_24h=WindShipOpt.RouterSettings(launch_spread_hours=24.0),
    spread_48h=WindShipOpt.RouterSettings(launch_spread_hours=48.0))

"""
    route_approximation(out_dir, name, scale)

Route the kite cases at corridor `scale` under the settings `name` of
`LAUNCH_APPROXIMATIONS`, or the ships without a rig for `bare`; the file written.
"""
function route_approximation(out_dir, name, scale)
    rig = name == :bare ? "none" : "kite"
    cases = filter(case -> case.rig == rig, gate_cases(scale))
    path = joinpath(out_dir, "$(name)_$(Int(scale)).csv")
    wall = @elapsed WindShipOpt.with_router_settings(
        () -> gate_trips(path, cases, departures[1:6:end]), LAUNCH_APPROXIMATIONS[name])
    @printf("%s at scale %.0f: all cases in %s after %.0f s\n", name, scale, path, wall)
    return path
end

"""
    read_seconds(path)

Routing time [s] of each case of the gate file `path` by (ship, rig, route).
"""
function read_seconds(path)
    rows = split.(readlines(path)[2:end], ",")
    return Dict((row[1], row[2], row[3]) => parse(Float64, row[12]) for row in rows)
end

"""
    print_savings(out_dir, scale)

Print per ship and route the kite saving [points] of each approximation with a file in
`out_dir`, its change and routing time against the full router's where that has a file,
and the gap between `free` and `settled` where both have one.
"""
function print_savings(out_dir, scale)
    file(name) = joinpath(out_dir, "$(name)_$(Int(scale)).csv")
    has_file(name) = isfile(file(name))
    bare = read_gate(file(:bare))
    savings(name) = Dict(key => saving(merge(bare, read_gate(file(name))), key)
                         for key in keys(read_gate(file(name))))
    for name in filter(has_file, filter(!=(:bare), keys(LAUNCH_APPROXIMATIONS)))
        println(name)
        here, timing = savings(name), read_seconds(file(name))
        for key in sort!(collect(keys(here)))
            @printf("  %-24s saving %7.3f", join(key, " "), here[key])
            if has_file(:full)
                @printf("  against full %+7.3f  time %.2f", here[key] - savings(:full)[key],
                    timing[key] / read_seconds(file(:full))[key])
            end
            println()
        end
    end
    all(has_file, (:free, :settled)) || return
    free, settled = savings(:free), savings(:settled)
    println("gap between free and settled launches [points of saving]")
    for key in sort!(collect(keys(free)))
        @printf("  %-24s %7.3f\n", join(key, " "), free[key] - settled[key])
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    out_dir, scale_text, names... = ARGS
    mkpath(out_dir)
    scale = parse(Float64, scale_text)
    every_name = filter(!=(:bare), keys(LAUNCH_APPROXIMATIONS))
    chosen = isempty(names) ? every_name : Symbol.(names)
    route_approximation(out_dir, :bare, scale)
    foreach(name -> route_approximation(out_dir, name, scale), chosen)
    print_savings(out_dir, scale)
end
