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
    Assumptions(path=joinpath(pkgdir(WindShipOpt), "data", "assumptions.yaml"))

All model assumptions, read from a YAML file. Index with a symbol to get the base value:
`assumptions[:e_methanol_price]`.
"""
struct Assumptions
    entries::Dict{Symbol, Assumption}
end

function Assumptions(path::AbstractString=default_assumptions_path())
    raw = YAML.load_file(path)
    entries = Dict{Symbol, Assumption}()
    for (name, entry) in raw
        entries[Symbol(name)] = Assumption(entry["value"], entry["low"], entry["high"],
            string(entry["unit"]), entry["reason"])
    end
    return Assumptions(entries)
end

default_assumptions_path() = joinpath(pkgdir(@__MODULE__), "data", "assumptions.yaml")

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
