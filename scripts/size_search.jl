# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# The search for the cheapest size of a rig: which sizes to try first, over the whole grid
# or from a guess, and which next from the costs of the sizes tried so far, until the
# cheapest of each valley is confirmed.
# Included by paper.jl.

"""
    size_grid(lower, upper)

Areas [m^2] a size search may try: `lower`, every fourth power of two more than half a
step inside both bounds, and `upper`.
"""
function size_grid(lower, upper)
    lower == upper && return [lower]
    steps = ceil(Int, 4log2(lower) + 0.5):floor(Int, 4log2(upper) - 0.5)
    return [lower; [2.0^(step / 4) for step in steps]; upper]
end

"""
    nearest_step(grid, area)

Index of the area of `grid` nearest `area` [m^2] on a log scale.
"""
nearest_step(grid, area) = argmin(abs.(log.(grid ./ area)))

"""
    coarse_sizes(grid)

Areas [m^2] of `grid` a size search with no guess tries first: its lower bound, every
doubling of it on `grid` and its upper bound.
"""
coarse_sizes(grid) = grid[unique([1:4:length(grid); length(grid)])]

"""
    start_sizes(guess, grid)

Areas [m^2] of `grid` a size search from a guess tries first: the one nearest `guess` and
its neighbours.
"""
function start_sizes(guess, grid)
    centre = nearest_step(grid, guess)
    return grid[max(centre - 1, 1):min(centre + 1, length(grid))]
end

"""
    next_sizes(points, grid)

Next areas [m^2] of `grid` to try in the search for the cheapest rig size, from the
(area, cost) `points` tried so far: one about each [`valley`](@ref) of the points until
each is confirmed, its neighbours on `grid` tried and more expensive, or it has none. Past
a valley at an end of the points tried the search widens by the golden ratio; between its
neighbours it takes the vertex of the parabola through the three, or a golden-section step
into the wider side. A search whose points are all infeasible, at cost `Inf`, gives up.
"""
function next_sizes(points, grid)
    tried = sort([(nearest_step(grid, area), cost) for (area, cost) in points])
    steps, cost = first.(tried), last.(tried)
    sizes = [next_step(steps, cost, k, grid) for k in eachindex(steps) if valley(cost, k)]
    return grid[unique(filter(!isnothing, sizes))]
end

"""
    valley(cost, k)

Whether point `k` of the `cost` of points sorted by area is feasible and no more expensive
than the points beside it.
"""
valley(cost, k) = isfinite(cost[k]) && cost[k] <= min(get(cost, k - 1, Inf),
    get(cost, k + 1, Inf))

"""
    next_step(steps, cost, k, grid)

Index in `grid` of the next area to try about the valley `k` of the tried grid indices
`steps` and their `cost`, or `nothing` once it is confirmed; see [`next_sizes`](@ref).
"""
function next_step(steps, cost, k, grid)
    step = steps[k]
    open_below = step > 1 && (k == 1 || steps[k - 1] < step - 1)
    open_above = step < length(grid) && (k == length(steps) || steps[k + 1] > step + 1)
    open_below || open_above || return nothing
    x = log.(grid[steps])
    target = if k == 1 && open_below && length(x) > 1
        x[1] - 1.618(x[2] - x[1])
    elseif k == length(x) && open_above && length(x) > 1
        x[k] + 1.618(x[k] - x[k - 1])
    elseif 1 < k < length(x)
        inner_target(x, cost, k)
    end
    next = isnothing(target) ? step : nearest_step(grid, exp(target))
    next in steps && (next = open_above ? step + 1 : step - 1)
    return next
end

"""
    inner_target(x, cost, k)

Log area to try between the neighbours of the cheapest point `k` of the log areas `x` and
their `cost`: the vertex of the parabola through the three, or a golden-section step into
the wider side where that vertex is no new point or a neighbour is infeasible.
"""
function inner_target(x, cost, k)
    left, right = x[k] - x[k - 1], x[k + 1] - x[k]
    rise_left, rise_right = cost[k - 1] - cost[k], cost[k + 1] - cost[k]
    golden = right > left ? x[k] + 0.382right : x[k] - 0.382left
    isfinite(rise_left + rise_right) || return golden
    vertex = x[k] + (right^2 * rise_left - left^2 * rise_right) /
                    (2(left * rise_right + right * rise_left))
    close = minimum(abs.(x .- vertex)) < 0.05(left + right)
    return close || !(x[k - 1] < vertex < x[k + 1]) ? golden : vertex
end
