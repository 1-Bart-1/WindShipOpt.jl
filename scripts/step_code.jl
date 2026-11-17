# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# The code a step of the paper runs: the top-level definitions of the scripts it reaches by
# name, each with a hash of its expression, so a run can tell which steps a change touches.
# Included by paper_runs.jl and by the tests.
using Serialization

"""
    script_definitions(files)

Each name defined at top level in the Julia `files`, by a function, a method, an
assignment or a struct, with the expressions that define it, stripped of docstrings and
line numbers.
"""
function script_definitions(files)
    definitions = Dict{Symbol, Vector{Any}}()
    for file in files
        add_definitions!(definitions, Meta.parseall(read(file, String)))
    end
    return definitions
end

"""
    add_definitions!(definitions, expression)

Add to `definitions` the names that top-level `expression` defines, looking inside blocks,
conditionals, macro calls and docstrings.
"""
function add_definitions!(definitions, expression)
    expression isa Expr || return definitions
    head = expression.head
    if head in (:toplevel, :block, :if, :elseif)
        foreach(part -> add_definitions!(definitions, part), expression.args)
    elseif head == :macrocall
        add_definitions!(definitions, last(expression.args))
    else
        name = defined_name(expression)
        isnothing(name) ||
            push!(get!(definitions, name, Any[]), without_line_numbers(expression))
    end
    return definitions
end

"""
    defined_name(expression)

The name a function, method, assignment or struct `expression` defines, or nothing.
"""
function defined_name(expression)
    head = expression.head
    head in (:function, :(=), :struct) || return nothing
    target = expression.args[head == :struct ? 2 : 1]
    while target isa Expr && target.head in (:call, :where, :(::), :(<:), :curly, :.)
        target = target.head == :. ? last(target.args) : first(target.args)
    end
    target isa QuoteNode && return target.value
    return target isa Symbol ? target : nothing
end

"""
    without_line_numbers(expression)

`expression` with `nothing` in place of every line number node.
"""
function without_line_numbers(expression)
    expression isa LineNumberNode && return nothing
    expression isa Expr || return expression
    return Expr(expression.head, without_line_numbers.(expression.args)...)
end

"""
    names_used!(names, expression)

Add to `names` every symbol, quoted or not, that occurs in `expression`.
"""
function names_used!(names, expression)
    expression isa Symbol && push!(names, expression)
    expression isa QuoteNode && expression.value isa Symbol &&
        push!(names, expression.value)
    expression isa Expr && foreach(part -> names_used!(names, part), expression.args)
    return names
end

"""
    reachable_definitions(definitions, roots)

The names of `definitions` that `roots` reach by naming them, the roots among them,
following every name each definition uses.
"""
function reachable_definitions(definitions, roots)
    reached = Set{Symbol}()
    pending = collect(Symbol, roots)
    while !isempty(pending)
        name = pop!(pending)
        (name in reached || !haskey(definitions, name)) && continue
        push!(reached, name)
        for expression in definitions[name]
            append!(pending, setdiff(names_used!(Set{Symbol}(), expression), reached))
        end
    end
    return reached
end

"""
    code_hashes(definitions, roots)

Each name of `definitions` that `roots` reach, as a string, with a hash in hex of its
expressions.
"""
code_hashes(definitions, roots) = Dict(string(name) => content_hash(definitions[name])
                                      for name in reachable_definitions(definitions, roots))

"""
    content_hash(value)

Hash of the serialized `value` as a hexadecimal string, the same in every session.
"""
function content_hash(value)
    io = IOBuffer()
    serialize(io, value)
    return string(hash(String(take!(io))); base=16)
end
