# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# The paper's ships drawn from their own hulls: a hull surface with the model's main
# dimensions and form coefficients, deck, hatches, deck cargo and deckhouse, shaded and
# projected orthographically: the 140 m ship from the side, from above and from ahead as
# the TikZ pictures of paper/figure_ship.tex, and each ship class from the side in the
# ship classes figure.
# Included by paper.jl.

"""
    HullForm

Lines of a single-screw cargo hull, x forward of midship, y to port and z up from the
waterline [m]: a parallel midbody, an entrance and a run whose waterline and sectional
area curves fall as `1 - u^exponent` over their length fraction `u`, a bulbous bow, a raked
and flared stem, a counter with a transom, and a forecastle.
"""
Base.@kwdef struct HullForm
    "draft [m]"
    draft::Float64
    "half the beam [m]"
    half_beam::Float64
    "midship section coefficient [-]"
    midship_coefficient::Float64
    "height of the main deck above the waterline [m]"
    freeboard::Float64
    "height of the forecastle deck and of the hatch tops above the waterline [m]"
    foot_height::Float64
    "aft and forward ends of the waterline [m]"
    waterline::Tuple{Float64, Float64}
    "aft and forward ends of the parallel midbody [m]"
    midbody::Tuple{Float64, Float64}
    "transom, aft end of the deck [m]"
    transom::Float64
    "top of the stem, forward end of the deck [m]"
    stem::Float64
    "aft end of the forecastle [m]"
    forecastle::Float64
    "sternpost, where the flat keel ends aft, and forefoot, where it ends forward [m]"
    keel::Tuple{Float64, Float64}
    "rudder stock at the aft perpendicular [m]"
    rudder::Float64
    "exponent of the waterline curve [-]"
    waterline_exponent::Float64
    "exponent of the sectional area curve [-]"
    area_exponent::Float64
    "centre and semi-axes along, across and up of the ellipsoidal bulb [m]"
    bulb::NTuple{4, Float64}
    "height of the bulb's centre above the waterline [m]"
    bulb_centre::Float64
end

"exponent of the flare: the side's half breadth runs from the waterline's to the deck's
as the height fraction to this power"
flare_exponent = 1.4

"height [m] of the bulwark above the deck and its thickness seen from above"
bulwark = (height=1.0, width=0.5)

"depth of the counter over the rudder, as a fraction of the draft"
counter_depth = 0.25

"height of the transom's lower edge above the waterline, as a fraction of the freeboard"
transom_height = 0.3

"""
    unit_fall(u, exponent)

Fraction of full of a curve falling as `1 - u^exponent` at fraction `u` along its end.
"""
unit_fall(u, exponent) = 1 - clamp(u, 0, 1)^exponent

"""
    end_fraction(form, x)

Fraction [0 to 1] along the entrance or run at `x` [m]: 0 within the parallel midbody, 1 at
an end of the waterline.
"""
function end_fraction(form, x)
    (aft, forward) = form.waterline
    (midbody_aft, midbody_forward) = form.midbody
    x > midbody_forward && return (x - midbody_forward) / (forward - midbody_forward)
    x < midbody_aft && return (midbody_aft - x) / (midbody_aft - aft)
    return 0.0
end

"half breadth [m] of the waterline at `x` [m], zero beyond its ends"
function waterline_half_breadth(form, x)
    form.waterline[1] <= x <= form.waterline[2] || return 0.0
    return form.half_beam * unit_fall(end_fraction(form, x), form.waterline_exponent)
end

"""
    deck_half_breadth(form, x)

Half breadth [m] of the deck at `x` [m]: fuller than the waterline towards the bow, for
flare, and ending in the transom aft at three quarters of the beam.
"""
function deck_half_breadth(form, x)
    (midbody_aft, midbody_forward) = form.midbody
    form.transom <= x <= form.stem || return 0.0
    exponent = 2form.waterline_exponent
    x > midbody_forward && return form.half_beam *
           unit_fall((x - midbody_forward) / (form.stem - midbody_forward), exponent)
    x < midbody_aft && return form.half_beam * (1 - 0.25 *
           ((midbody_aft - x) / (midbody_aft - form.transom))^exponent)
    return form.half_beam
end

"height [m] of the deck above the waterline at `x` [m]: the forecastle forward of its end"
deck_height(form, x) = x >= form.forecastle ? form.foot_height : form.freeboard

"""
    bottom_height(form, x)

Height [m] of the hull's lowest point at `x` [m]: the flat keel up to the sternpost, from
which the hull rises over the propeller to the counter over the rudder and on to the
transom's lower edge; forward of the waterline the raked stem.
"""
function bottom_height(form, x)
    (aft, forward) = form.waterline
    (post, forefoot) = form.keel
    if x > forward
        return deck_height(form, x) * (x - forward) / (form.stem - forward)
    elseif x > forefoot
        return -form.draft * (1 - 0.5 * ((x - forefoot) / (forward - forefoot))^2)
    elseif x >= post
        return -form.draft
    elseif x >= form.rudder
        rise = (post - x) / (post - form.rudder)
        return -form.draft * (1 - (1 - counter_depth) * rise^2 * (3 - 2rise))
    elseif x >= aft
        return -counter_depth * form.draft * (x - aft) / (form.rudder - aft)
    end
    return transom_height * form.freeboard * (aft - x) / (aft - form.transom)
end

"""
    superellipse_fullness(m)

Area [-] of the quarter superellipse `(y/b)^m + (depth fraction)^m = 1` over its breadth
`b` by depth.
"""
function superellipse_fullness(m)
    steps = range(0, 1; length=2001)
    breadths = (1 .- steps .^ m) .^ (1 / m)
    return (sum(breadths) - (breadths[1] + breadths[end]) / 2) * step(steps)
end

"exponents of the superellipse sections and their fullness, from a V to a square"
section_table = let exponents = exp.(range(log(0.8), log(400); length=600))
    (exponents=exponents, fullness=superellipse_fullness.(exponents))
end

"""
    section_exponent(fullness)

Exponent `m` of the superellipse section `(y/b)^m + (depth fraction)^m = 1` whose area is
`fullness` times its breadth `b` by depth.
"""
function section_exponent(fullness)
    (; exponents) = section_table
    table = section_table.fullness
    wanted = clamp(fullness, first(table), last(table))
    i = clamp(searchsortedlast(table, wanted), 1, length(table) - 1)
    share = (wanted - table[i]) / (table[i+1] - table[i])
    return exponents[i] + share * (exponents[i+1] - exponents[i])
end

"""
    bulb_half_breadth(form, x, z)

Half breadth [m] of the bulb at `x` and `z` [m], zero outside it.
"""
function bulb_half_breadth(form, x, z)
    (centre, along, across, up) = form.bulb
    inside = 1 - ((x - centre) / along)^2 - ((z - form.bulb_centre) / up)^2
    return across * sqrt(max(inside, 0.0))
end

"""
    underwater_half_breadth(form, x, z)

Half breadth [m] of the hull below the waterline at `x` and `z` [m]: sections whose
fullness gives the sectional area curve, joined with the bulb.
"""
function underwater_half_breadth(form, x, z)
    breadth = waterline_half_breadth(form, x)
    depth = -bottom_height(form, x)
    hull = 0.0
    if breadth > 0 && depth > 0 && z >= -depth
        area = form.midship_coefficient * 2form.half_beam * form.draft *
               unit_fall(end_fraction(form, x), form.area_exponent)
        exponent = section_exponent(area / (2breadth * depth))
        hull = breadth * (1 - (-z / depth)^exponent)^(1 / exponent)
    end
    return max(hull, bulb_half_breadth(form, x, z))
end

"""
    topside_half_breadth(form, x, z)

Half breadth [m] of the side above the waterline at `x` and `z` [m], flaring from the
waterline's to the deck's at the top of the main deck's bulwark and upright above it, up
the forecastle, or over its whole height where the stem starts above that; zero outside
the side.
"""
function topside_half_breadth(form, x, z)
    start = max(bottom_height(form, x), 0.0)
    top = deck_height(form, x) + bulwark.height
    start <= z <= top || return 0.0
    breadth = waterline_half_breadth(form, x)
    flare_top = start < knuckle_height(form) ? knuckle_height(form) : top
    fraction = min((z - start) / (flare_top - start), 1.0)
    return breadth + (deck_half_breadth(form, x) - breadth) * fraction^flare_exponent
end

"height [m] above the waterline of the top of the main deck's bulwark, where the flare ends"
knuckle_height(form) = form.freeboard + bulwark.height

"x [m] of the foremost point of the hull, the stem or the bulb"
foremost(form) = max(form.stem, form.bulb[1] + form.bulb[2])

"half breadth [m] of the hull at `x` and `z` [m], zero outside it"
half_breadth(form, x, z) =
    z <= 0 ? underwater_half_breadth(form, x, z) : topside_half_breadth(form, x, z)

"""
    station(form, x; below=10, above=5)

Points `(y, z)` [m] of the port half of the section at `x` [m] from its lowest point up
to the top of the bulwark: `below` steps under the waterline, closer near the keel, and
seven more through the bulb, and `above` over the topsides with one more at the top of
the main deck's bulwark.
"""
function station(form, x; below=10, above=5)
    (centre, along, _, up) = form.bulb
    bulb_height = up * sqrt(max(1 - ((x - centre) / along)^2, 0.0))
    bulb_levels = form.bulb_centre .+ bulb_height .* cospi.(range(1, 0; length=7))
    lowest = min(bottom_height(form, x), bulb_height > 0 ? first(bulb_levels) : 0.0, 0.0)
    bulb_levels = clamp.(bulb_levels, lowest, 0.0)
    keel_levels = [lowest * (1 - (step / below)^1.5) for step in 0:below]
    underwater = [(underwater_half_breadth(form, x, z), z)
                  for z in sort(vcat(keel_levels, bulb_levels))]
    start = max(bottom_height(form, x), 0.0)
    top = deck_height(form, x) + bulwark.height
    knuckle = clamp(knuckle_height(form), start, top)
    levels = sort(vcat(range(start, top; length=above + 1), knuckle))
    topsides = [(topside_half_breadth(form, x, z), z) for z in levels]
    return vcat(underwater, topsides)
end

"""
    HullForm(hull, assumptions)

Lines of `hull` with its draft, beam, waterline length, midship and waterplane
coefficients and bulb, its displacement matched by the sectional area curve, the depth of
`depth_draft_ratio` and the forecastle and hatch tops at the rigs' foot height.
"""
function HullForm(hull::Hull, assumptions::Assumptions)
    half = hull.length / 2
    waterline = (half - hull.waterline_length, half)
    prismatic = hull.displacement_volume /
                (hull.midship_coefficient * hull.beam * hull.draft * hull.waterline_length)
    midbody_length = clamp(2.5(prismatic - 0.6), 0.0, 0.6) * hull.waterline_length
    centre = hull.centre_of_buoyancy / 100 * hull.length
    midbody = (centre - midbody_length / 2, centre + midbody_length / 2)
    fullness = (hull.waterplane_coefficient - midbody_length / hull.waterline_length) /
               (1 - midbody_length / hull.waterline_length)
    bulb_up = sqrt(hull.bulb_area / π)
    bulb_along = 0.045hull.length
    stem = half + 0.025hull.length
    shape(area_exponent) = HullForm(; hull.draft, half_beam=hull.beam / 2,
        hull.midship_coefficient,
        freeboard=(assumptions[:depth_draft_ratio] - 1) * hull.draft,
        foot_height=assumptions[:deck_mount_height] * hull.length /
                    assumptions[:reference_length],
        waterline, midbody, transom=waterline[1] - 0.005hull.length, stem,
        forecastle=half - 0.1hull.length,
        keel=(-0.45hull.length, half - 0.04hull.length), rudder=-half,
        waterline_exponent=fullness / (1 - fullness), area_exponent,
        bulb=(stem - bulb_along, bulb_along, 0.8bulb_up, bulb_up),
        bulb_centre=hull.bulb_height - hull.draft)
    low, high = 0.3, 20.0
    for _ in 1:40
        middle = sqrt(low * high)
        drawn_volume(shape(middle)) < hull.displacement_volume ? (low = middle) :
        (high = middle)
    end
    return shape(sqrt(low * high))
end

"x positions [m] of the stations drawn of `form`: close over the ends, the midbody whole"
function stations(form)
    (midbody_aft, midbody_forward) = form.midbody
    forward = foremost(form)
    aft = range(form.transom, midbody_aft; length=26)
    bow = range(midbody_forward, forward; length=40)
    return sort(unique(vcat(aft, bow, form.forecastle - 1e-6, form.forecastle)))
end

"""
    drawn_volume(form)

Displacement volume [m^3] of the hull surface of `form` below the waterline, from its
sections by the trapezoidal rule.
"""
function drawn_volume(form)
    xs = range(form.transom, form.bulb[1] + form.bulb[2]; length=600)
    areas = map(xs) do x
        points = filter(point -> point[2] <= 0, station(form, x; below=60))
        sum(2 * (points[i][1] + points[i+1][1]) / 2 * (points[i+1][2] - points[i][2])
            for i in 1:length(points)-1; init=0.0)
    end
    return sum((areas[i] + areas[i+1]) / 2 * step(xs) for i in 1:length(xs)-1)
end

"""
    drawn_coefficients(form, hull)

Block, midship and waterplane coefficients of the drawn `form` on the length and
waterline length of `hull`.
"""
function drawn_coefficients(form, hull)
    xs = range(form.waterline...; length=2000)
    waterplane = 2sum(waterline_half_breadth.(Ref(form), xs)) * step(xs)
    midship = filter(point -> point[2] <= 0, station(form, 0.0; below=400))
    midship_area = sum(2 * (midship[i][1] + midship[i+1][1]) / 2 *
                       (midship[i+1][2] - midship[i][2]) for i in 1:length(midship)-1)
    return (block=drawn_volume(form) / (hull.length * hull.beam * hull.draft),
        midship=midship_area / (hull.beam * hull.draft),
        waterplane=waterplane / (hull.waterline_length * hull.beam))
end

"the 140 m ship the paper's pictures draw"
paper_ship = HullForm(Hull(140.0, assumptions), assumptions)

"""
    Face

A flat face of the ship drawn: its corner points [m] counterclockwise seen from outside,
and the figure style colour it is drawn in.
"""
struct Face
    corners::Vector{NTuple{3, Float64}}
    colour::String
end

"colour of a face of the hull with its centre at height `z` [m]"
hull_colour(z) = z < -1e-9 ? "keel" : "topsides"

"""
    flat_runs(aft, forward)

Ranges `(low, high)` of the faces between the points `aft` and `forward` [m] of two
neighbouring stations, girth step `j` joining points `j` and `j + 1`, over which the side
stays within a degree of flat and off the centre plane, each drawn as one face.
"""
function flat_runs(aft, forward)
    quad(j) = Face([aft[j], forward[j], forward[j+1], aft[j+1]], "")
    runs = Tuple{Int, Int}[]
    for j in 1:length(aft)-1
        corners = quad(j).corners
        maximum(abs(corner[2]) for corner in corners) < 1e-6 && continue
        normal = face_normal(quad(j))
        if !isempty(runs) && last(runs)[2] == j - 1 &&
           dot3(face_normal(quad(last(runs)[1])), normal) > cosd(1)
            runs[end] = (last(runs)[1], j)
        else
            push!(runs, (j, j))
        end
    end
    return runs
end

"""
    hull_faces(form)

Faces of both sides of the hull of `form` between its stations, without those lying in
the centre plane, the top of the bulwark, the deck, the forecastle front and the transom.
"""
function hull_faces(form)
    xs = stations(form)
    sections = [station(form, x) for x in xs]
    faces = Face[]
    for i in 1:length(xs)-1
        aft = [(xs[i], point...) for point in sections[i]]
        forward = [(xs[i+1], point...) for point in sections[i+1]]
        for (low, high) in flat_runs(aft, forward)
            run = vcat(aft[low], forward[low:high+1], reverse(aft[low+1:high+1]))
            colour = hull_colour(sum(corner[3] for corner in run) / length(run))
            push!(faces, Face(reverse(run), colour))
            push!(faces, Face([(x, -y, z) for (x, y, z) in run], colour))
        end
    end
    for i in 1:length(xs)-1
        rim = [(x, deck_half_breadth(form, x), deck_height(form, x) + bulwark.height)
               for x in xs[i:i+1]]
        inner = [(x, max(y - bulwark.width, 0.0), z) for (x, y, z) in rim]
        top = [inner[1], inner[2], rim[2], rim[1]]
        push!(faces, Face(top, "topsides"))
        push!(faces, Face(reverse([(x, -y, z) for (x, y, z) in top]), "topsides"))
    end
    for (from, to) in ((form.transom, form.forecastle - 1e-6), (form.forecastle, form.stem))
        edge = [(x, deck_half_breadth(form, x), deck_height(form, x))
                for x in filter(x -> from <= x <= to, xs)]
        port = reverse(edge)
        push!(faces, Face(vcat([(x, -y, z) for (x, y, z) in edge], port), "deck"))
    end
    front = form.forecastle
    breadth = deck_half_breadth(form, front)
    (low, high) = (form.freeboard, form.foot_height)
    push!(faces, Face([(front, breadth, low), (front, -breadth, low),
            (front, -breadth, high), (front, breadth, high)], "deck"))
    transom = [(form.transom, y, z) for (y, z) in station(form, form.transom) if z >= 0]
    push!(faces, Face(vcat(reverse(transom), [(x, -y, z) for (x, y, z) in transom]),
        "topsides"))
    return faces
end

"""
    box_faces(low, high, colour)

The faces of the box with opposite corners `low` and `high` [m], its bottom left out.
"""
function box_faces(low, high, colour)
    (x1, y1, z1), (x2, y2, z2) = low, high
    return [Face([(x1, y1, z2), (x2, y1, z2), (x2, y2, z2), (x1, y2, z2)], colour),
        Face([(x1, y1, z1), (x2, y1, z1), (x2, y1, z2), (x1, y1, z2)], colour),
        Face([(x2, y2, z1), (x1, y2, z1), (x1, y2, z2), (x2, y2, z2)], colour),
        Face([(x2, y1, z1), (x2, y2, z1), (x2, y2, z2), (x2, y1, z2)], colour),
        Face([(x1, y2, z1), (x1, y1, z1), (x1, y1, z2), (x1, y2, z2)], colour)]
end

"length [m] of one hatch cover with the gap to the next"
hatch_length = 15.0

"""
    deck_faces(form, hull, type)

Faces of what the ship of `form`, `hull` and ship `type` carries outside its hull: rudder
and deckhouse with its wheelhouse across the beam, at the bridge of `hull` or aft; hatch
covers up to the rigs' foot height and the containers of `hull` stacked on them, on all but
tankers; and on a vehicle carrier its car decks closed up to the height of its windage,
the wheelhouse on top.
"""
function deck_faces(form, hull, type)
    (; length, draft, bridge_distance) = hull
    faces = Face[]
    if type == "vehicle carrier"
        top = WindShipOpt.Windage(type, length, hull.beam, 0, assumptions).lateral_area /
              length
        aft, forward = form.transom + 0.01length, form.forecastle
        breadth = min(deck_half_breadth(form, aft), deck_half_breadth(form, forward))
        append!(faces, box_faces((aft, -breadth, form.freeboard), (forward, breadth, top),
            "ship"))
        append!(faces, deckhouse_faces(form, length, forward - 0.08length, top,
            top + 0.04length))
    else
        house_aft = isfinite(bridge_distance) ?
                    length / 2 - bridge_distance - 0.08length : -length / 2 + 0.02length
        house_top = max(form.freeboard + 10length / 85,
            form.foot_height + hull.deck_cargo_height + 0.02length)
        type in ("oil product tanker", "crude oil tanker") ||
            append!(faces, hatch_faces(form, hull, (house_aft, house_aft + 0.08length)))
        append!(faces, deckhouse_faces(form, length, house_aft, form.freeboard, house_top))
    end
    return append!(faces, box_faces((form.rudder - 0.015length, -0.004length, -0.95draft),
        (form.rudder + 0.015length, 0.004length, -counter_depth * draft), "keel"))
end

"""
    hatch_faces(form, hull, house)

Faces of the hatch covers of the ship of `form` and `hull` up to its rigs' foot height,
from a fifth of its length forward of the stern to its forecastle, each with the containers
of `hull` stacked on it, leaving out those under the deckhouse from `house[1]` to `house[2]`
[m].
"""
function hatch_faces(form, hull, house)
    (; length, deck_cargo_height) = hull
    hatch_aft, hatch_forward = -length / 2 + 0.2length, form.forecastle - 0.03length
    panels = max(1, round(Int, (hatch_forward - hatch_aft) / hatch_length))
    pitch = (hatch_forward - hatch_aft) / panels
    faces = Face[]
    for panel in 0:panels-1
        aft = hatch_aft + panel * pitch
        forward = aft + pitch - 0.004length
        forward > house[1] && aft < house[2] && continue
        append!(faces, box_faces((aft, -0.75form.half_beam, form.freeboard),
            (forward, 0.75form.half_beam, form.foot_height), "ship"))
        deck_cargo_height > 0 || continue
        breadth = 0.95min(deck_half_breadth(form, aft), deck_half_breadth(form, forward))
        append!(faces, box_faces((aft, -breadth, form.foot_height),
            (forward, breadth, form.foot_height + deck_cargo_height), "ship"))
    end
    return faces
end

"""
    deckhouse_faces(form, length, aft, floor, top)

Faces of the deckhouse of the ship of `form` and `length` [m] from `aft` [m], standing on
`floor` [m], its wheelhouse across the beam reaching up to `top` [m] with its front
windows.
"""
function deckhouse_faces(form, length, aft, floor, top)
    house_half = 0.9deck_half_breadth(form, aft)
    (wheelhouse, front) = (top - 0.02length, aft + 0.08length)
    faces = [box_faces((aft, -house_half, floor), (front, house_half, wheelhouse), "ship");
        box_faces((aft + 0.05length, -form.half_beam, wheelhouse),
            (front, form.half_beam, top), "ship")]
    panes = 9
    width = 2house_half / panes
    (low, high) = (top - 0.015length, top - 0.006length)
    for pane in 0:panes-1
        (left, right) = (-house_half + pane * width + 0.1, -house_half + (pane + 1) * width)
        push!(faces, Face([(front + 0.01, left, low), (front + 0.01, right, low),
                (front + 0.01, right, high), (front + 0.01, left, high)], "keel"))
    end
    return faces
end

"faces of the ship of `form`, `hull` and ship `type`: its hull and what it carries"
ship_faces(form, hull, type) = vcat(hull_faces(form), deck_faces(form, hull, type))

"""
    section_outline(form)

Points `(y, z)` [m] of the hull of `form` seen from ahead, its widest breadth at each
height, from the top of the port bulwark down round the keel to the starboard one.
"""
function section_outline(form)
    xs = range(form.transom, foremost(form); length=800)
    (knuckle, top) = (knuckle_height(form), form.foot_height + bulwark.height)
    levels = sort(unique(vcat(-form.draft * cospi.(range(0, 0.5; length=40)),
        range(0, knuckle; length=10), range(knuckle + 1e-6, top; length=10))))
    port = [(maximum(x -> half_breadth(form, x, z), xs), z) for z in reverse(levels)]
    return vcat(port, [(-y, z) for (y, z) in reverse(port)])
end

"""
    bow_brightness(form, y, z)

Brightness [-] seen from ahead of the foremost hull of `form` at breadth `y` and height
`z` [m], or of the midbody's side where the bow is narrower than `y`.
"""
function bow_brightness(form, y, z)
    xs = range(foremost(form), form.midbody[2]; length=2000)
    x = xs[something(findfirst(x -> half_breadth(form, x, z) >= abs(y), xs), end)]
    step = 0.05
    along = (half_breadth(form, x + step, z) - half_breadth(form, x - step, z)) / 2step
    up = (half_breadth(form, x, z + step) - half_breadth(form, x, z - step)) / 2step
    normal = (-along, sign(y), -up) ./ hypot(along, sign(y), up)
    return brightness(dot3((normal[2], normal[3], normal[1]), light))
end

"""
    bow_shades(form, colour, heights; columns=40, blur=0.3)

Colours across the hull of `form` seen from ahead, from starboard to port at `columns`
evenly spaced breadths: the figure style `colour` at the brightness of the bow averaged
over `heights` [m] and over a Gaussian across the breadth of `blur` times the half beam.
"""
function bow_shades(form, colour, heights; columns=40, blur=0.3)
    breadths = range(-form.half_beam, form.half_beam; length=columns)
    levels = [sum(z -> bow_brightness(form, y, z), heights) / length(heights)
              for y in breadths]
    return map(breadths) do y
        weights = exp.(-((breadths .- y) ./ (blur * form.half_beam)) .^ 2 ./ 2)
        shade(colour, sum(weights .* levels) / sum(weights))
    end
end

"""
    tikz_shading(io, name, colours)

Declare the PGF horizontal shading `name` running through `colours` from left to right
across the path it fills.
"""
function tikz_shading(io, name, colours)
    stops = ["color($(round(25 + 50(i - 1) / (length(colours) - 1); digits=2))bp)=($colour)"
             for (i, colour) in enumerate(colours)]
    println(io, "\\pgfdeclarehorizontalshading{$name}{100bp}{",
        "color(0bp)=($(first(colours))); ", join(stops, "; "),
        "; color(100bp)=($(last(colours)))}")
end

"""
camera axes of each view: right and up across the page and towards the viewer, with the
bow to the right from the side and from above
"""
views = Dict(:side => ((1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, -1.0, 0.0)),
    :above => ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)),
    :ahead => ((0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0)))

"direction of the light in each view's camera axes: from the upper left, in front"
light = (-0.4, 0.55, 0.73) ./ hypot(-0.4, 0.55, 0.73)

dot3(a, b) = sum(a .* b)
cross3(a, b) = (a[2]b[3] - a[3]b[2], a[3]b[1] - a[1]b[3], a[1]b[2] - a[2]b[1])

"outward unit normal of `face`, zero where it has no area"
function face_normal(face)
    corners = face.corners
    normal = (0.0, 0.0, 0.0)
    for i in eachindex(corners)
        normal = normal .+ cross3(corners[i], corners[mod1(i + 1, length(corners))])
    end
    size = hypot(normal...)
    return size > 1e-9 ? normal ./ size : normal
end

"""
    brightness(lit)

Brightness [-] of a face whose normal has the cosine `lit` with the light: 1 for a face
square to the viewer, lighter towards the light and darker away from it.
"""
function brightness(lit)
    facing = light[3]
    lit >= facing && return 1 + 1.1(lit - facing)
    return 1 - 0.6(facing - max(lit, 0.0))
end

"""
    shade_mix(brightness)

Share [%] of a colour at `brightness` [-] and the colour it is mixed with: black below 1
and white above it, in steps of 3 %.
"""
function shade_mix(brightness)
    level = round(Int, 100brightness / 3) * 3
    return level <= 100 ? (level, "black") : (200 - level, "white")
end

"xcolor expression of the figure style `colour` at `brightness` [-] by [`shade_mix`](@ref)"
function shade(colour, brightness)
    share, other = shade_mix(brightness)
    return "$(colour)!$(share)!$(other)"
end

"Makie colour of the figure style `colour` at `brightness` [-] by [`shade_mix`](@ref)"
function shaded(colour, brightness)
    share, other = shade_mix(brightness)
    return Makie.Colors.weighted_color_mean(share / 100, style_colour(colour),
        parse(Makie.Colors.Colorant, other))
end

"""
    projected(faces, view)

The faces in `faces` seen in `view`, back to front, as their corners across and up the
page [m], their figure style colour and their [`brightness`](@ref).
"""
function projected(faces, view)
    right, up, towards = views[view]
    facing = filter(face -> dot3(face_normal(face), towards) > 1e-6, faces)
    seen = facing[unhidden([[(dot3(corner, right), dot3(corner, up), dot3(corner, towards))
                             for corner in face.corners] for face in facing])]
    depth(face) = sum(dot3(corner, towards) for corner in face.corners) /
                  length(face.corners)
    return map(sort(seen; by=depth)) do face
        normal = face_normal(face)
        lit = dot3((dot3(normal, right), dot3(normal, up), dot3(normal, towards)), light)
        corners = [(dot3(corner, right), dot3(corner, up)) for corner in face.corners]
        (corners, face.colour, brightness(lit))
    end
end

"""
    unhidden(polygons; pixel=0.1)

Indices of the flat `polygons`, each its corners across, up and towards the viewer [m],
that are nearest the viewer at some point of a grid of `pixel` [m], or smaller than two
of its cells and not behind the nearest at their centre.
"""
function unhidden(polygons; pixel=0.1)
    corners = reduce(vcat, polygons)
    low = (minimum(first, corners), minimum(corner -> corner[2], corners))
    cell(point) = (point[1] - low[1], point[2] - low[2]) ./ pixel
    high = cell((maximum(first, corners), maximum(corner -> corner[2], corners)))
    nearest = fill(-Inf, ceil.(Int, high) .+ 2)
    owner = zeros(Int, size(nearest))
    small = Int[]
    for (index, polygon) in enumerate(polygons)
        points = [(cell(corner)..., corner[3]) for corner in polygon]
        area = 0.0
        for i in 2:length(points)-1
            area += rasterize!(nearest, owner, index, points[1], points[i], points[i+1])
        end
        area < 2 && push!(small, index)
    end
    exposed = filter(small) do index
        centre = cell(reduce((a, b) -> a .+ b, polygons[index]) ./ length(polygons[index]))
        column, row = clamp.(ceil.(Int, centre), 1, size(nearest))
        sum(corner[3] for corner in polygons[index]) / length(polygons[index]) >=
        nearest[column, row] - 0.5
    end
    return sort(union(filter(>(0), unique(owner)), exposed))
end

"""
    rasterize!(nearest, owner, index, a, b, c)

Mark the cells of the triangle `a`, `b`, `c` (cell coordinates and depth) where it is
nearer than `nearest` as owned by `index`; return its area in cells.
"""
function rasterize!(nearest, owner, index, a, b, c)
    area = (b[1] - a[1]) * (c[2] - a[2]) - (c[1] - a[1]) * (b[2] - a[2])
    abs(area) < 1e-12 && return 0.0
    columns = max(1, floor(Int, min(a[1], b[1], c[1]))):min(size(nearest, 1),
        ceil(Int, max(a[1], b[1], c[1])))
    rows = max(1, floor(Int, min(a[2], b[2], c[2]))):min(size(nearest, 2),
        ceil(Int, max(a[2], b[2], c[2])))
    for column in columns, row in rows
        x, y = column - 0.5, row - 0.5
        wa = ((b[1] - x) * (c[2] - y) - (c[1] - x) * (b[2] - y)) / area
        wb = ((c[1] - x) * (a[2] - y) - (a[1] - x) * (c[2] - y)) / area
        wc = 1 - wa - wb
        min(wa, wb, wc) < 0 && continue
        depth = wa * a[3] + wb * b[3] + wc * c[3]
        if depth > nearest[column, row] + 1e-6
            nearest[column, row] = depth
            owner[column, row] = index
        end
    end
    return abs(area) / 2
end

"`faces` drawn by the PGF macros of paper/figure_ship.tex, each on one line"
function tikz_faces(io, faces)
    for (corners, colour, brightness) in faces
        print(io, "\\hullface{", shade(colour, brightness), "}")
        for (i, corner) in enumerate(corners)
            @printf(io, "\\hull%s{%.2f}{%.2f}", i == 1 ? "move" : "line", corner...)
        end
        println(io, "\\hullfill")
    end
end

"""
    check_drawn_hull(form, hull)

Error unless the block, midship and waterplane coefficients of the drawn `form` are within
1 % of those of `hull`.
"""
function check_drawn_hull(form, hull)
    drawn = drawn_coefficients(form, hull)
    model = (block=WindShipOpt.block_coefficient(hull), midship=hull.midship_coefficient,
        waterplane=hull.waterplane_coefficient)
    for name in keys(model)
        abs(drawn[name] / model[name] - 1) < 0.01 ||
            error("the $(hull.length) m drawn hull's $name coefficient $(drawn[name]) is ",
                "not the model's ", model[name])
    end
end

"""
    ship_pictures_file()

Write paper/figure_ship.tex: the 140 m ship of the model as the TikZ pictures `ship side`,
`ship above` and `ship ahead`, the last its hull as one shaded section heeled by the
pic's argument [deg] with the keel colour below the level waterline, in metres about
midship on the waterline, with each view's faces in paper/ship/, and the macros of its
foot height and its bow, once [`check_drawn_hull`](@ref) passes.
"""
function ship_pictures_file()
    hull = Hull(140.0, assumptions)
    check_drawn_hull(paper_ship, hull)
    faces = ship_faces(paper_ship, hull, "general cargo")
    folder = mkpath(joinpath(root, "paper", "ship"))
    for view in (:side, :above)
        write_whole(io -> tikz_faces(io, projected(faces, view)),
            joinpath(folder, "$view.tex"))
    end
    deck = deck_faces(paper_ship, hull, "general cargo")
    write_whole(io -> tikz_faces(io, projected(deck, :ahead)),
        joinpath(folder, "ahead.tex"))
    (; draft, freeboard) = paper_ship
    write_whole(joinpath(root, "paper", "figure_ship.tex")) do io
        println(io, "% Written by the ship_pictures step of scripts/paper.jl.")
        @printf(io, "\\def\\shipfoot{%.2f}\n\\def\\shipbow{%.2f}\n", paper_ship.foot_height,
            paper_ship.stem)
        tikz_shading(io, "hull topsides", bow_shades(paper_ship, "topsides",
            range(0.1freeboard, knuckle_height(paper_ship); length=8)))
        tikz_shading(io, "hull keel", bow_shades(paper_ship, "keel",
            range(-0.9draft, -0.1draft; length=8)))
        print(io, "\\def\\hullsection{")
        outline = section_outline(paper_ship)
        join(io, (@sprintf("(%.2f,%.2f)", point...) for point in outline), " -- ")
        println(io, " -- cycle}")
        print(io, raw"""
        \def\hullface#1{\pgfsetfillcolor{#1}\pgfsetstrokecolor{#1}}
        \def\hullmove#1#2{\pgfpathmoveto{\pgfqpointxy{#1}{#2}}}
        \def\hullline#1#2{\pgfpathlineto{\pgfqpointxy{#1}{#2}}}
        \def\hullfill{\pgfpathclose\pgfusepath{fill,stroke}}
        \tikzset{
          ship side/.pic={\begin{scope}[hull face]\input{ship/side}\end{scope}},
          ship above/.pic={\begin{scope}[hull face]\input{ship/above}\end{scope}},
          ship ahead/.pic={
            \begin{scope}[hull face]\input{ship/ahead}\end{scope}
            \begin{scope}\clip[rotate=-#1] (-40,0) rectangle (40,40);
              \shade[shading=hull topsides] \hullsection;\end{scope}
            \begin{scope}\clip[rotate=-#1] (-40,-30) rectangle (40,0);
              \shade[shading=hull keel] \hullsection;\end{scope}},
        }
        """)
    end
end
