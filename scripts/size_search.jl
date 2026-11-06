# The search for the cheapest size of a rig: which area to try next from the costs of the
# areas tried so far. Included by paper.jl.

"""
    next_size(points, lower, upper)

Next area [m^2] to try in the search for the cheapest rig size, from the (area, cost)
`points` tried so far within `lower` and `upper`: the vertex of the parabola in log area
through the best point and its neighbours, or a golden-section step into the wider side
where that vertex is no new point; by [`bound_step`](@ref) towards the neighbour when the
best is a bound; rounded by [`snap_area`](@ref).
"""
function next_size(points, lower, upper)
    sorted = sort(filter(point -> isfinite(last(point)), points); by=first)
    x = [log(first(point)) for point in sorted]
    cost = [last(point) for point in sorted]
    k = argmin(cost)
    k == 1 && return clamp(snap_area(exp(bound_step(x[1], x[2]))), lower, upper)
    k == length(x) && return clamp(snap_area(exp(bound_step(x[k], x[k - 1]))), lower, upper)
    left, right = x[k] - x[k - 1], x[k + 1] - x[k]
    rise_left, rise_right = cost[k - 1] - cost[k], cost[k + 1] - cost[k]
    vertex = x[k] + (right^2 * rise_left - left^2 * rise_right) /
                    (2(left * rise_right + right * rise_left))
    close = minimum(abs.(x .- vertex)) < 0.05(left + right)
    if close || !(x[k - 1] < vertex < x[k + 1])
        vertex = right > left ? x[k] + 0.382right : x[k] - 0.382left
    end
    return clamp(snap_area(exp(vertex)), lower, upper)
end

"""
    bound_step(bound, neighbour)

The log area a fourth power of two from the log area `bound` towards `neighbour`, or
halfway to `neighbour` where that is nearer.
"""
bound_step(bound, neighbour) =
    bound + clamp((neighbour - bound) / 2, -log(2) / 4, log(2) / 4)

"""
    snap_area(area)

`area` [m^2] rounded to the nearest step of a fourth power of two.
"""
snap_area(area) = 2.0^(round(4log2(area)) / 4)
