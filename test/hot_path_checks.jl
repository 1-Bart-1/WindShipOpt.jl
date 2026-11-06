# Checks of the code that runs per edge and per leg of a route: `dynamic_calls` for type
# stability and `allocations` for what a call allocates.
using Test, TOML, WindShipOpt

"""
    dynamic_calls(call, argument_types)

Signatures of the methods holding a call the compiler left to run-time dispatch or a field
read from a value of no concrete type, in the optimised code of `call` on `argument_types`
and of everything it calls, leaving out the paths that only throw.
"""
function dynamic_calls(call, argument_types)
    found = Set{String}()
    seen = Set{Any}()
    pending = Any[Base.signature_type(call, argument_types)]
    while !isempty(pending)
        signature = pop!(pending)
        signature in seen && continue
        push!(seen, signature)
        for (code, returned) in Base.code_typed_by_type(signature; optimize=true)
            returned === Union{} && continue
            scan_code!(found, pending, code, signature)
        end
    end
    return sort!(collect(found))
end

"""
    scan_code!(found, pending, code, signature)

Add the signature of the method `code` to `found` if it dispatches at run time or reads a
field of a value of no concrete type, and the signatures it calls to `pending`.
"""
function scan_code!(found, pending, code, signature)
    for statement in code.code
        statement isa Expr || continue
        if statement.head === :invoke
            target = statement.args[1]
            instance = target isa Core.CodeInstance ? target.def : target
            push!(pending, instance.specTypes)
        elseif statement.head === :call && (is_dynamic(code, statement.args[1]) ||
                reads_unknown_type(code, statement))
            push!(found, string(signature))
        end
    end
end

"""
    callee_value(code, callee)

The function the callee of a `:call` statement of `code` stands for, or its type.
"""
function callee_value(code, callee)
    callee isa Core.SSAValue && (callee = code.ssavaluetypes[callee.id])
    callee isa Core.Const && (callee = callee.val)
    callee isa GlobalRef && (callee = isdefined(callee.mod, callee.name) ?
                                      getglobal(callee.mod, callee.name) : Any)
    return callee
end

"""
    is_dynamic(code, callee)

Whether the callee of a `:call` statement of `code` is anything but a builtin, or is the
builtin applying a splatted call: what the optimiser leaves of a call it could not resolve.
"""
function is_dynamic(code, callee)
    callee = callee_value(code, callee)
    callee === Core._apply_iterate && return true
    return !(callee isa Core.Builtin || callee isa Core.IntrinsicFunction)
end

"""
    reads_unknown_type(code, statement)

Whether the `:call` `statement` of `code` reads a field of a value whose concrete type the
compiler does not know, which boxes what it reads.
"""
function reads_unknown_type(code, statement)
    callee_value(code, statement.args[1]) === Core.getfield || return false
    object = statement.args[2]
    type = object isa Core.SSAValue ? code.ssavaluetypes[object.id] :
           object isa Core.Argument ? code.slottypes[object.n] : typeof(object)
    return !isconcretetype(Core.Compiler.widenconst(type))
end

"""
    allocations(call)

Allocations of `call()` once compiled, the fewest of three tries, so that another thread
allocating during one try does not count.
"""
function allocations(call)
    call()
    return minimum(@allocations(call()) for _ in 1:3)
end

"""
    gridded_weather(directory)

[`ERA5Weather`](@ref) of constant sea state and wind on a small grid written to `directory`.
"""
function gridded_weather(directory)
    grid = (; lats=collect(0.0:1.5:75.0), lons=collect(-90.0:1.5:15.0))
    for (group, step, names) in (("wind", 6, ("u10", "v10")),
        ("waves", 1, ("height", "period", "direction")))
        mkpath(joinpath(directory, group))
        open(joinpath(directory, group, "grid.toml"), "w") do io
            TOML.print(io, Dict("lats" => grid.lats, "lons" => grid.lons,
                "step_hours" => step,
                "first_time" => "2017-01-01T00:00:00", "variables" => collect(names)))
        end
        for name in names
            write(joinpath(directory, group, "$name.f32"),
                fill(Float32(5), length(grid.lons), length(grid.lats), 8))
        end
    end
    return ERA5Weather(directory)
end

"""
    edge_allocations(table, weather, corridor)

[`allocations`](@ref) of each thing done per edge on the [`RouteTable`](@ref) `table`, by
name.
"""
function edge_allocations(table, weather, corridor)
    stage, lateral = 2, centre_index(corridor)
    step = WindShipOpt.MAX_LATERAL_STEP + 1
    start = WindShipOpt.EdgeSample(table.table, weather, corridor, stage, lateral, step,
        0.0, 100.0)
    points = WindShipOpt.SailedPoint[]
    prices = (; fuel=table.table.ship.fuel.price, time=100.0)
    return (; wind=allocations(() -> wind(weather, 50.0, -10.0, 100.0)),
        waves=allocations(() -> waves(weather, 50.0, -10.0, 100.0)),
        sample=allocations(() -> WindShipOpt.EdgeSample(table.table, weather, corridor,
            stage, lateral, step, 0.5, 100.0)),
        held_speed=allocations(() -> WindShipOpt.held_speed(table, 3, start)),
        sail_edge=allocations(() -> WindShipOpt.sail_edge!(points, start, table, weather,
            corridor, stage, lateral, step, 100.0, 3)),
        kite_passage=allocations(() -> WindShipOpt.kite_passage(table, points, false,
            prices)))
end

"""
    leg_allocations(table, weather, corridor)

[`allocations`](@ref) of a route along `corridor` on the [`RouteTable`](@ref) `table`.
"""
leg_allocations(table, weather, corridor) =
    allocations(() -> route(corridor, table, weather, 24.0; time_cost=100.0))

"a table of the 85 m methanol ship with the rig of each of the `sizes` keywords"
rig_table(; sizes...) =
    RouteTable(PerformanceTable(Ship(ShipDesign(:methanol, 85.0; sizes...), Assumptions()),
        Assumptions()))

rig_tables = (bare=rig_table(), wings=rig_table(wing_area=400.0),
    rotors=rig_table(rotor_area=200.0), kite=rig_table(kite_area=200.0),
    kite_and_wings=rig_table(kite_area=200.0, wing_area=400.0))
gridded = gridded_weather(mktempdir())
coarse_corridor = first(route_corridors(:caribbean, north_atlantic_mask(); scale=16))

@testset "the dispatch check finds run-time dispatch and only that" begin
    unstable(box) = box[] + 1
    @noinline hidden(box) = box[] + 1
    calls_unstable(box) = 2 * hidden(box)
    @noinline barrier(x) = x + 1
    stable(x) = 2 * barrier(x)
    splatted(values) = barrier(values...)
    reads_first(box) = box[].first + 1
    @test !isempty(dynamic_calls(unstable, (Base.RefValue{Any},)))
    @test !isempty(dynamic_calls(reads_first, (Base.RefValue{Pair{Int}},)))
    @test isempty(dynamic_calls(reads_first, (Base.RefValue{Pair{Int, Int}},)))
    @test !isempty(dynamic_calls(calls_unstable, (Base.RefValue{Any},)))
    @test !isempty(dynamic_calls(splatted, (Vector{Int},)))
    @test isempty(dynamic_calls(stable, (Int,)))
    @test isempty(dynamic_calls(splatted, (Tuple{Int},)))
end

@testset "the allocation check counts allocations and not the compiling of the call" begin
    @test allocations(() -> rand(3)) >= 1
    @test allocations(() -> sum((1, 2, 3))) == 0
end

@testset "what runs per edge and per leg of a route dispatches nothing at run time" begin
    forecast = ForecastWeather(gridded, 0.0, 24.0)
    prices = @NamedTuple{fuel::Float64, time::Float64}
    points = Vector{WindShipOpt.SailedPoint}
    for table in rig_tables, weather in (SyntheticWeather(), gridded, forecast)
        kinds = typeof.((table, weather))
        @test isempty(dynamic_calls(WindShipOpt.sail_edge!, (points, WindShipOpt.EdgeSample,
            kinds[1], kinds[2], Corridor, Int, Int, Int, Float64, Int)))
        @test isempty(dynamic_calls(WindShipOpt.kite_passage,
            (kinds[1], points, Bool, prices)))
        @test isempty(dynamic_calls(Core.kwcall, (@NamedTuple{time_cost::Float64},
            typeof(route), Corridor, kinds[1], kinds[2], Float64)))
    end
end

@testset "what runs per edge of a route does not allocate" begin
    for table in rig_tables, weather in (SyntheticWeather(), gridded,
        ForecastWeather(gridded, 0.0, 24.0))

        @test all(iszero, edge_allocations(table, weather, coarse_corridor))
    end
end

@testset "a routed leg makes the same few allocations at any corridor scale" begin
    leg_counts = [leg_allocations(table, gridded, coarse_corridor) for table in rig_tables]
    @test all(<=(40), leg_counts)
    finer_corridor = first(route_corridors(:caribbean, north_atlantic_mask(); scale=8))
    @test leg_allocations(rig_tables.bare, gridded, finer_corridor) == first(leg_counts)
end
