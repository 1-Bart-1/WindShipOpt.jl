# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""
    Assumption

One model assumption: base value, sensitivity bounds, unit and the reason for the value.
"""
struct Assumption
    value::Float64
    low::Float64
    high::Float64
    unit::String
    reason::String
end

"""
    Assumptions()

All model assumptions, read from `data/assumptions.yaml`. Index with a symbol to get the
base value: `assumptions[:e_methanol_price]`.
"""
struct Assumptions
    entries::Dict{Symbol, Assumption}
end

function Assumptions()
    raw = YAML.load_file(joinpath(pkgdir(@__MODULE__), "data", "assumptions.yaml"))
    entries = Dict{Symbol, Assumption}()
    for (name, entry) in raw
        entries[Symbol(name)] = Assumption(entry["value"], entry["low"], entry["high"],
            string(entry["unit"]), entry["reason"])
    end
    return Assumptions(entries)
end

Base.getindex(assumptions::Assumptions, name::Symbol) = assumptions.entries[name].value

"""
    with_value(assumptions, name, value)

Fresh `Assumptions` with the base value of `name` replaced by `value`.
"""
function with_value(assumptions::Assumptions, name::Symbol, value)
    entries = copy(assumptions.entries)
    old = entries[name]
    entries[name] = Assumption(value, old.low, old.high, old.unit, old.reason)
    return Assumptions(entries)
end
