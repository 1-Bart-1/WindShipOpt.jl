# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""
    Recording()

Arithmetic recorded over named inputs, for evaluating elsewhere at other input values:
each node an input with its base value, a constant, or an operation on earlier nodes,
each stored once.
"""
struct Recording
    "nodes in order: (:input, (name, base)), (:constant, (value,)) or (operation, operands)"
    nodes::Vector{Tuple{Symbol, Tuple}}
    "index of each node in `nodes`"
    index::Dict{Tuple{Symbol, Tuple}, Int}
end

Recording() = Recording(Tuple{Symbol, Tuple}[], Dict{Tuple{Symbol, Tuple}, Int}())

"the recording that operations on [`Recorded`](@ref) values add to, nothing outside one"
const RECORDING = ScopedValue{Union{Nothing, Recording}}(nothing)

"""
    Recorded

A number computed from recorded inputs: its value at the base inputs and its node in the
[`Recording`](@ref) in force. Comparing it or converting it to a float is an error, since
that would fix a branch or a value at the base inputs.
"""
struct Recorded <: Real
    value::Float64
    node::Int
end

"""
    record(f, recording)

Call `f()` with operations on [`Recorded`](@ref) values adding to `recording`.
"""
record(f, recording::Recording) = with(f, RECORDING => recording)

"""
    recorded_input(name, base)

The input `name` of base value `base` as a [`Recorded`](@ref) value.
"""
recorded_input(name::AbstractString, base::Real) =
    Recorded(base, recorded_node(:input, (String(name), Float64(base))))

function recorded_node(operation, operands)
    recording = RECORDING[]
    isnothing(recording) && error("a recorded value is used outside its recording")
    return get!(recording.index, (operation, operands)) do
        push!(recording.nodes, (operation, operands))
        length(recording.nodes)
    end
end

constant(value::Real) = Recorded(value, recorded_node(:constant, (Float64(value),)))

Base.convert(::Type{Recorded}, value::Recorded) = value
Base.convert(::Type{Recorded}, value::Real) = constant(value)
Base.promote_rule(::Type{Recorded}, ::Type{<:Real}) = Recorded
Base.zero(::Type{Recorded}) = constant(0.0)
Base.one(::Type{Recorded}) = constant(1.0)

for operation in (:+, :-, :*, :/, :^, :min, :max)
    @eval begin
        Base.$operation(a::Recorded, b::Recorded) = Recorded($operation(a.value, b.value),
            recorded_node($(QuoteNode(operation)), (a.node, b.node)))
        Base.$operation(a::Recorded, b::Real) = $operation(a, constant(b))
        Base.$operation(a::Real, b::Recorded) = $operation(constant(a), b)
    end
end
Base.:^(a::Recorded, b::Integer) = a^constant(b)
Base.:*(a::Bool, b::Recorded) = constant(a) * b
Base.:*(a::Recorded, b::Bool) = a * constant(b)

for operation in (:-, :sqrt, :exp, :log)
    @eval Base.$operation(a::Recorded) = Recorded($operation(a.value),
        recorded_node($(QuoteNode(operation)), (a.node,)))
end

branch_error(_...) = error("a branch or conversion on a recorded input would fix it at \
    its base value")
for operation in (:<, :<=, :isless, :(==))
    @eval begin
        Base.$operation(a::Recorded, b::Recorded) = branch_error()
        Base.$operation(a::Recorded, b::Real) = branch_error()
        Base.$operation(a::Real, b::Recorded) = branch_error()
    end
end
Base.Float64(::Recorded) = branch_error()
Base.convert(::Type{Float64}, ::Recorded) = branch_error()
Base.isfinite(::Recorded) = branch_error()
