# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

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
        fields[name] = Mmap.mmap(path, Array{Float32, 3},
            (length(lons), length(lats), steps))
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
duration(weather::ERA5Weather) = min(last_time(weather.wind), last_time(weather.waves))

last_time(fields::GriddedFields) =
    fields.time_offset + (step_count(fields) - 1) * fields.step_hours

function cell(axis::Vector{Float64}, value)
    position = clamp((value - first(axis)) / (axis[2] - axis[1]) + 1, 1, length(axis))
    index = min(floor(Int, position), length(axis) - 1)
    return index, position - index
end

"step `k` of `fields` at or before `time`, clamped to the stored times, and the share `t`
of the way to the next"
function time_cell(fields::GriddedFields, time)
    steps = step_count(fields)
    position = clamp((time - fields.time_offset) / fields.step_hours + 1, 1, steps)
    k = min(floor(Int, position), steps - 1)
    return k, position - k
end

"""
    sample(fields, arrays, lat, lon, time)

Trilinear interpolation of each array in the tuple `arrays`, leaving land points (NaN)
out of the weighting; NaN where all corners are land.
"""
function sample(fields::GriddedFields, arrays::Tuple, lat, lon, time)
    i, x = cell(fields.lons, lon)
    j, y = cell(fields.lats, lat)
    k, t = time_cell(fields, time)
    totals = map(_ -> 0.0, arrays)
    weight_sum = 0.0
    for (dk, wt) in ((0, 1 - t), (1, t)), (dj, wy) in ((0, 1 - y), (1, y)),
        (di, wx) in ((0, 1 - x), (1, x))

        corner = corner_values(arrays, i + di, j + dj, k + dk)
        any(isnan, corner) && continue
        totals = weighted_sum(totals, wx * wy * wt, corner)
        weight_sum += wx * wy * wt
    end
    return totals ./ weight_sum
end

corner_values(arrays, i, j, k) = map(array -> Float64(@inbounds array[i, j, k]), arrays)

weighted_sum(totals, weight, values) = map((total, value) -> total + weight * value, totals,
    values)

wind(weather::ERA5Weather, lat, lon, time) =
    sample(weather.wind, weather.wind_arrays, lat, lon, time)

"""
    waves(weather, lat, lon, time)

Significant wave height [m], peak period [s] and the direction the waves come from
[rad clockwise from north]; zero height on land.
"""
waves(weather::ERA5Weather, lat, lon, time) =
    wave_values(sample(weather.waves, weather.wave_arrays, lat, lon, time))

"""
    wave_values((height, period, east, north))

Wave height [m] and period [s], at least zero, and the direction [rad clockwise from north]
of the east and north components; all zero where `height` is NaN (land).
"""
function wave_values((height, period, east, north))
    isnan(height) && return 0.0, 0.0, 0.0
    return max(height, 0.0), max(period, 0.0), atan(east, north)
end

"""
    Climatology(directory, origin)

Monthly mean ERA5 wind and waves per cell, read from the `wind` and `waves` folders that
`scripts/download_era5.jl` writes to `directory` with `ERA5_PRODUCT=climate`, on the time
axis of hours from `origin`, varying linearly between the middles of the months.
"""
struct Climatology
    origin::DateTime
    "wind per (lon, lat, month), the months December, January to December, January"
    wind::GriddedFields
    "waves per (lon, lat, month), on the same months as `wind`"
    waves::GriddedFields
    "east and north wind of the mean vector, and the mean wind speed [m/s]"
    wind_arrays::NTuple{3, Array{Float32, 3}}
    "wave height [m], peak period [s] and the mean east and north direction components"
    wave_arrays::NTuple{4, Array{Float32, 3}}
end

function Climatology(directory::AbstractString, origin::DateTime)
    wind = monthly_fields(joinpath(directory, "wind"))
    waves = monthly_fields(joinpath(directory, "waves"))
    return Climatology(origin, wind, waves,
        (wind.fields["u10"], wind.fields["v10"], wind.fields["speed"]),
        (waves.fields["height"], waves.fields["period"], waves.fields["direction_east"],
            waves.fields["direction_north"]))
end

"""
    monthly_fields(directory)

The (lon, lat, month) fields in `directory` with December put before January and January
after December, on a time axis in months from the middle of January.
"""
function monthly_fields(directory)
    grid = TOML.parsefile(joinpath(directory, "grid.toml"))
    lats, lons = Float64.(grid["lats"]), Float64.(grid["lons"])
    fields = Dict{String, Array{Float32, 3}}()
    for name in grid["variables"]
        months = read!(joinpath(directory, "$name.f32"),
            Array{Float32, 3}(undef, length(lons), length(lats), 12))
        fields[name] = cat(months[:, :, 12:12], months, months[:, :, 1:1]; dims=3)
    end
    return GriddedFields(lats, lons, -1.0, 1.0, 14, fields)
end

"months from the middle of January to `time` [h] after `origin`, within its year"
function month_position(origin::DateTime, time)
    moment = origin + Dates.Millisecond(round(Int, 3_600_000 * time))
    start = DateTime(Dates.firstdayofmonth(moment))
    return Dates.month(moment) - 1.5 +
           Dates.value(moment - start) / (86_400_000 * Dates.daysinmonth(moment))
end

"east and north wind of the climate's mean vector and its mean wind speed [m/s]"
climate_wind(climate::Climatology, lat, lon, time) = sample(climate.wind,
    climate.wind_arrays, lat, lon, month_position(climate.origin, time))

"wave height [m], period [s] and mean east and north direction components; NaN on land"
climate_waves(climate::Climatology, lat, lon, time) = sample(climate.waves,
    climate.wave_arrays, lat, lon, month_position(climate.origin, time))

wind(climate::Climatology, lat, lon, time) =
    scaled_to(climate_wind(climate, lat, lon, time)...)
waves(climate::Climatology, lat, lon, time) =
    wave_values(climate_waves(climate, lat, lon, time))

"the vector (`east`, `north`) scaled to the length `speed`, or zero where it has none"
function scaled_to(east, north, speed)
    length = hypot(east, north)
    iszero(length) && return 0.0, 0.0
    return east * speed / length, north * speed / length
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
