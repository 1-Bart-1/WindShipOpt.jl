# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""
    Assumption

One model assumption: base value, sensitivity bounds, unit, its source in one short line,
and its value as known today, which differs from the base value only for a goal.
"""
struct Assumption
    value::Float64
    low::Float64
    high::Float64
    unit::String
    source::String
    today::Float64
end

"""
    Assumptions()

All model assumptions, read from `data/assumptions.yaml`. Index with a symbol to get the
base value: `assumptions[:e_methanol_price]`.
"""
struct Assumptions{R}
    entries::Dict{Symbol, Assumption}
    "[`Recorded`](@ref) values read in place of the base values of their names, or nothing"
    recorded::R
end

Assumptions(entries::Dict{Symbol, Assumption}) = Assumptions(entries, nothing)

function Assumptions()
    raw = YAML.load_file(joinpath(pkgdir(@__MODULE__), "data", "assumptions.yaml"))
    entries = Dict{Symbol, Assumption}()
    for (name, entry) in raw
        entries[Symbol(name)] = Assumption(entry["value"], entry["low"], entry["high"],
            string(entry["unit"]), entry["source"], get(entry, "today", entry["value"]))
    end
    return Assumptions(entries)
end

"names of the inputs read in a scope of [`inputs_read`](@ref)"
struct InputsRead
    "names of the inputs read so far"
    names::Set{Symbol}
    "lock guarding `names` against tasks reading at once"
    lock::ReentrantLock
end

"the record of the innermost [`inputs_read`](@ref) running, or nothing outside one"
const INPUTS_READ = ScopedValue{Union{Nothing, InputsRead}}(nothing)

"whether `name` is one of the inputs in `assumptions`"
Base.haskey(assumptions::Assumptions, name::Symbol) = haskey(assumptions.entries, name)

function Base.getindex(assumptions::Assumptions, name::Symbol)
    record = INPUTS_READ[]
    isnothing(record) || @lock record.lock push!(record.names, name)
    recorded = assumptions.recorded
    return isnothing(recorded) ? assumptions.entries[name].value :
           get(() -> assumptions.entries[name].value, recorded, name)
end

"""
    inputs_read(f)

Call `f()` and return its result with the names of the inputs read from any `Assumptions`
while it ran, in the tasks it spawned too.
"""
function inputs_read(f)
    record = InputsRead(Set{Symbol}(), ReentrantLock())
    result = with(f, INPUTS_READ => record)
    return result, record.names
end

"""
    recorded_inputs(assumptions, names)

`assumptions` with each of `names` read as a [`Recorded`](@ref) input of its base value.
"""
recorded_inputs(assumptions::Assumptions, names) = Assumptions(assumptions.entries,
    Dict(name => recorded_input(string(name), assumptions[name]) for name in names))

"""
    with_value(assumptions, name, value)

Fresh `Assumptions` with the base value of `name` replaced by `value`.
"""
function with_value(assumptions::Assumptions, name::Symbol, value)
    entries = copy(assumptions.entries)
    old = entries[name]
    entries[name] = Assumption(value, old.low, old.high, old.unit, old.source, old.today)
    return Assumptions(entries, assumptions.recorded)
end

"""
    at_today(assumptions)

Fresh `Assumptions` with every input at its value known today: a goal's own, and any other
input's base value, which is its value today.
"""
at_today(assumptions::Assumptions) = Assumptions(
    Dict(name => Assumption(entry.today, entry.low, entry.high, entry.unit, entry.source,
             entry.today) for (name, entry) in assumptions.entries), assumptions.recorded)
