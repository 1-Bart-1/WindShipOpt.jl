"""
    GriddedFields

Variables on a regular (lon, lat, time) grid, memory-mapped from the files written by
`scripts/download_era5.jl`.
"""
struct GriddedFields
    lats::Vector{Float64}
    lons::Vector{Float64}
    "hours from the weather origin to the first stored time [h]"
    time_offset::Float64
    step_hours::Float64
    "stored times common to all fields"
    steps::Int
    fields::Dict{String, Array{Float32, 3}}
end

function GriddedFields(directory::AbstractString, origin::DateTime)
    grid = TOML.parsefile(joinpath(directory, "grid.toml"))
    lats = Float64.(grid["lats"])
    lons = Float64.(grid["lons"])
    field_size = length(lons) * length(lats)
    fields = Dict{String, Array{Float32, 3}}()
    for name in grid["variables"]
        path = joinpath(directory, "$name.f32")
        steps = filesize(path) ÷ (field_size * sizeof(Float32))
        fields[name] = Mmap.mmap(path, Array{Float32, 3}, (length(lons), length(lats), steps))
    end
    offset = Dates.value(DateTime(grid["first_time"]) - origin) / 3_600_000
    steps = minimum(size(field, 3) for field in values(fields))
    return GriddedFields(lats, lons, offset, grid["step_hours"], steps, fields)
end

step_count(fields::GriddedFields) = fields.steps

"""
    ERA5Weather(directory)

ERA5 10 m wind and sea state read from `directory`, with time in hours after the first
stored wind field.
"""
struct ERA5Weather
    origin::DateTime
    wind::GriddedFields
    waves::GriddedFields
    "east and north 10 m wind [m/s] per (longitude, latitude, time)"
    wind_arrays::NTuple{2, Array{Float32, 3}}
    "wave height [m], peak period [s] and east and north direction components, same axes"
    wave_arrays::NTuple{4, Array{Float32, 3}}
end

function ERA5Weather(directory::AbstractString=joinpath(pkgdir(@__MODULE__), "era5"))
    grid = TOML.parsefile(joinpath(directory, "wind", "grid.toml"))
    origin = DateTime(grid["first_time"])
    waves = GriddedFields(joinpath(directory, "waves"), origin)
    direction = waves.fields["direction"]
    waves.fields["direction_east"] = sind.(direction)
    waves.fields["direction_north"] = cosd.(direction)
    wind = GriddedFields(joinpath(directory, "wind"), origin)
    return ERA5Weather(origin, wind, waves, (wind.fields["u10"], wind.fields["v10"]),
        (waves.fields["height"], waves.fields["period"], waves.fields["direction_east"],
            waves.fields["direction_north"]))
end

"hours of weather available from the origin [h]"
duration(weather::ERA5Weather) = min(
    weather.wind.time_offset + (step_count(weather.wind) - 1) * weather.wind.step_hours,
    weather.waves.time_offset + (step_count(weather.waves) - 1) * weather.waves.step_hours)

function cell(axis::Vector{Float64}, value)
    position = clamp((value - first(axis)) / (axis[2] - axis[1]) + 1, 1, length(axis))
    index = min(floor(Int, position), length(axis) - 1)
    return index, position - index
end

"""
    stencil(fields, lat, lon, time)

The eight grid corners around a point as ((lon index, lat index, time index), weight).
"""
function stencil(fields::GriddedFields, lat, lon, time)
    i, x = cell(fields.lons, lon)
    j, y = cell(fields.lats, lat)
    steps = step_count(fields)
    position = clamp((time - fields.time_offset) / fields.step_hours + 1, 1, steps)
    k = min(floor(Int, position), steps - 1)
    t = position - k
    return (((i + di, j + dj, k + dk), wx * wy * wt)
            for (di, wx) in ((0, 1 - x), (1, x)), (dj, wy) in ((0, 1 - y), (1, y)),
                (dk, wt) in ((0, 1 - t), (1, t)))
end

"""
    sample(fields, arrays, lat, lon, time)

Trilinear interpolation of each array in the tuple `arrays`, leaving land points (NaN)
out of the weighting; NaN where all corners are land.
"""
function sample(fields::GriddedFields, arrays::NTuple{N}, lat, lon, time) where {N}
    totals = ntuple(_ -> 0.0, N)
    weight_sum = 0.0
    for (index, weight) in stencil(fields, lat, lon, time)
        corner = map(array -> Float64(array[index...]), arrays)
        any(isnan, corner) && continue
        totals = totals .+ weight .* corner
        weight_sum += weight
    end
    return totals ./ weight_sum
end

wind(weather::ERA5Weather, lat, lon, time) =
    sample(weather.wind, weather.wind_arrays, lat, lon, time)

"""
    waves(weather, lat, lon, time)

Significant wave height [m], peak period [s] and the direction the waves come from
[rad clockwise from north]; zero height on land.
"""
function waves(weather::ERA5Weather, lat, lon, time)
    height, period, east, north = sample(weather.waves, weather.wave_arrays, lat, lon, time)
    isnan(height) && return 0.0, 0.0, 0.0
    return height, period, atan(east, north)
end

"""
    GridMask(weather, islands)

Land mask from the cells of the ERA5 wave grid that carry no wave data, plus `islands`
too small for that grid; everything outside the grid counts as land.
"""
struct GridMask
    lats::Vector{Float64}
    lons::Vector{Float64}
    "land per (longitude, latitude) cell"
    land::BitMatrix
    islands::Vector{Island}
end

GridMask(weather::ERA5Weather, islands::Vector{Island}) = GridMask(weather.waves.lats,
    weather.waves.lons, isnan.(weather.waves.fields["height"][:, :, 1]), islands)

function is_land(mask::GridMask, lat, lon)
    on_island(mask.islands, lat, lon) && return true
    first(mask.lats) <= lat <= last(mask.lats) || return true
    first(mask.lons) <= lon <= last(mask.lons) || return true
    i = argmin(abs.(mask.lons .- lon))
    j = argmin(abs.(mask.lats .- lat))
    return mask.land[i, j]
end
