# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Download ERA5 for one region into era5/<group>/ (North Atlantic) or
# era5/<region>/<group>/, one Float32 file per variable plus grid.toml. With
# ERA5_PRODUCT=climate it writes instead the monthly means of 1991-2016 per cell (lon, lat,
# month) to era5/<region>/climate/<group>/, from every other wind chunk and a wave field
# every 102 h. The region is the ERA5_REGION environment variable:
# - "atlantic" (default): Rotterdam to the Caribbean
# - "north_sea": Rotterdam to Norway and Iceland
# - "atlantic_wide": the Atlantic from Brazil and the US Gulf to Europe
# Wind: WeatherBench2's 1.5° 6-hourly copy (small chunks). Waves: ARCO-ERA5 0.25° hourly,
# thinned to 0.5° and 12-hourly. Resumable: rerun to continue.
using Blosc
using Dates
using Downloads
using TOML

bucket = "https://storage.googleapis.com"
arco = "$bucket/gcp-public-data-arco-era5/ar/full_37-1h-0p25deg-chunk-1.zarr-v3"
weatherbench = "$bucket/weatherbench2/datasets/era5/" *
               "1959-2023_01_10-6h-240x121_equiangular_with_poles_conservative.zarr"
series_years = 2017:2019
climate_years = 1991:2016
region = get(ENV, "ERA5_REGION", "atlantic")
lat_range, lon_range, subdirectory = Dict(
    "atlantic" => ((5.0, 56.0), (-75.0, 10.0), ""),
    "north_sea" => ((50.0, 67.0), (-25.0, 14.0), "north_sea"),
    "atlantic_wide" => ((-35.0, 56.0), (-100.0, 10.0), "atlantic_wide"))[region]
output = joinpath(@__DIR__, "..", "era5", subdirectory)

function fetch(url)
    for attempt in 1:6
        try
            buffer = IOBuffer()
            Downloads.download(url, buffer; timeout=300)
            return take!(buffer)
        catch error
            attempt == 6 && rethrow()
            sleep(5attempt)
        end
    end
end

decode(T, url) = Blosc.decompress(T, fetch(url))
in_range(value, (low, high)) = low <= value <= high
signed_lon(lon) = lon > 180 ? lon - 360 : lon

"""
    Source

Where one group of variables lives and how its chunks map to (lon, lat, time).
"""
struct Source
    store::String
    variables::Dict{String, String}
    columns::Vector{Int}
    rows::Vector{Int}
    lons::Vector{Float64}
    lats::Vector{Float64}
    "chunk number and time steps inside the chunk for each stored time"
    chunks::Vector{Tuple{Int, Vector{Int}}}
    times::Vector{DateTime}
    read_chunk::Function
end

function weatherbench_source(years; chunk_stride=1)
    lats = decode(Float64, "$weatherbench/latitude/0")
    lons = signed_lon.(decode(Float64, "$weatherbench/longitude/0"))
    rows = sort(findall(lat -> in_range(lat, lat_range), lats); by=row -> lats[row])
    columns = filter(column -> in_range(lons[column], lon_range), sortperm(lons))
    origin = DateTime(1959)
    first_step = Dates.value(DateTime(first(years)) - origin) ÷ 21_600_000
    last_step = Dates.value(DateTime(last(years) + 1) - origin) ÷ 21_600_000 - 1
    chunks = [(chunk, [step - 8chunk + 1
                       for step in max(8chunk, first_step):min(8chunk + 7, last_step)])
              for chunk in (first_step ÷ 8):chunk_stride:(last_step ÷ 8)]
    times = [origin + Hour(6(8chunk + step - 1)) for (chunk, steps) in chunks
             for step in steps]
    read_chunk(url) = reshape(decode(Float32, url), length(lats), length(lons), 8)
    variables = Dict("u10" => "10m_u_component_of_wind", "v10" => "10m_v_component_of_wind")
    return Source(weatherbench, variables, columns, rows, lons[columns], lats[rows], chunks,
        times, read_chunk)
end

function arco_source(times)
    lats = collect(90.0:-0.25:-90.0)
    lons = signed_lon.(collect(0.0:0.25:359.75))
    rows = reverse(findall(lat -> in_range(lat, lat_range) && iszero(mod(lat, 0.5)), lats))
    columns = filter(column -> in_range(lons[column], lon_range) &&
                                   iszero(mod(lons[column], 0.5)), sortperm(lons))
    chunks = [(Dates.value(time - DateTime(1900)) ÷ 3_600_000, [1]) for time in times]
    read_chunk(url) = permutedims(reshape(decode(Float32, url), 1440, 721, 1), (2, 1, 3))
    variables = Dict("height" => "significant_height_of_combined_wind_waves_and_swell",
        "direction" => "mean_wave_direction", "period" => "peak_wave_period")
    return Source(arco, variables, columns, rows, lons[columns], lats[rows], chunks, times,
        read_chunk)
end

"""
    fetch_blocks(source, batch, names)

The chunks numbered `batch` of the variables `names` of `source`, cut to its region and
times, by (name, chunk number).
"""
function fetch_blocks(source::Source, batch, names)
    jobs = [(name, index) for index in batch for name in names]
    blocks = asyncmap(jobs; ntasks=16) do (name, index)
        chunk, steps = source.chunks[index]
        url = "$(source.store)/$(source.variables[name])/$chunk.0.0"
        return source.read_chunk(url)[source.rows, source.columns, steps]
    end
    return Dict(zip(jobs, blocks))
end

function download(source::Source, group)
    directory = mkpath(joinpath(output, group))
    names = sort(collect(keys(source.variables)))
    open(joinpath(directory, "grid.toml"), "w") do io
        TOML.print(io, Dict("lats" => source.lats, "lons" => source.lons,
            "first_time" => string(first(source.times)),
            "step_hours" => Dates.value(Hour(source.times[2] - source.times[1])),
            "variables" => names))
    end
    field_bytes = length(source.lats) * length(source.lons) * sizeof(Float32)
    files = Dict(name => open(joinpath(directory, "$name.f32"), "a+") for name in names)
    done = minimum(filesize(joinpath(directory, "$name.f32")) ÷ field_bytes
                   for name in names)
    for io in values(files)
        truncate(io, done * field_bytes)
        seekend(io)
    end
    chunk_start = findfirst(
        i -> sum(length(last(entry)) for entry in source.chunks[1:i]) > done,
        eachindex(source.chunks))
    isnothing(chunk_start) && return println(group, " complete")
    skip = done - sum(length(last(entry)) for entry in source.chunks[1:(chunk_start - 1)];
        init=0)
    for batch in Iterators.partition(chunk_start:length(source.chunks), 8)
        blocks = fetch_blocks(source, batch, names)
        for index in batch, name in names
            block = blocks[(name, index)]
            steps = axes(block, 3)
            index == chunk_start && (steps = steps[(skip + 1):end])
            for step in steps
                write(files[name], permutedims(block[:, :, step]))
            end
        end
        foreach(flush, values(files))
        println(group, " chunk ", last(batch), "/", length(source.chunks))
    end
    foreach(close, values(files))
    println(group, " complete")
end

"""
    climate_fields(fields)

The fields a climatology averages from one time of `fields` (lon, lat): the wind's east and
north components and its speed, or the wave height, period and the east and north
components of the direction the waves come from.
"""
function climate_fields(fields)
    haskey(fields, "u10") && return Dict("u10" => fields["u10"], "v10" => fields["v10"],
        "speed" => hypot.(fields["u10"], fields["v10"]))
    return Dict("height" => fields["height"], "period" => fields["period"],
        "direction_east" => sind.(fields["direction"]),
        "direction_north" => cosd.(fields["direction"]))
end

function add_field!(total, count, field)
    for i in eachindex(total, count, field)
        isnan(field[i]) && continue
        total[i] += field[i]
        count[i] += 1
    end
end

"""
    write_climate(source, group)

Write the mean of [`climate_fields`](@ref) over the times of `source` per (lon, lat,
calendar month) to `climate/<group>/`, NaN where no time holds data.
"""
function write_climate(source::Source, group)
    shape = (length(source.lons), length(source.lats), 12)
    totals, counts = Dict{String, Array{Float64, 3}}(), Dict{String, Array{Int, 3}}()
    names = sort(collect(keys(source.variables)))
    time_index = 0
    for batch in Iterators.partition(eachindex(source.chunks), 8)
        blocks = fetch_blocks(source, batch, names)
        for index in batch, step in eachindex(last(source.chunks[index]))
            time_index += 1
            month = Dates.month(source.times[time_index])
            fields = Dict(name => permutedims(blocks[(name, index)][:, :, step])
                          for name in names)
            for (name, field) in climate_fields(fields)
                total = get!(() -> zeros(shape), totals, name)
                count = get!(() -> zeros(Int, shape), counts, name)
                add_field!(view(total, :, :, month), view(count, :, :, month), field)
            end
        end
        println(group, " chunk ", last(batch), "/", length(source.chunks))
    end
    directory = mkpath(joinpath(output, "climate", group))
    for (name, total) in totals
        write(joinpath(directory, "$name.f32"), Float32.(total ./ counts[name]))
    end
    open(joinpath(directory, "grid.toml"), "w") do io
        TOML.print(io, Dict("lats" => source.lats, "lons" => source.lons,
            "variables" => sort(collect(keys(totals))),
            "years" => [first(climate_years), last(climate_years)],
            "times" => length(source.times)))
    end
    println(group, " climate complete")
end

if get(ENV, "ERA5_PRODUCT", "series") == "climate"
    write_climate(weatherbench_source(climate_years; chunk_stride=2), "wind")
    write_climate(arco_source(collect(DateTime(first(climate_years)):Hour(102):DateTime(
            last(climate_years), 12, 31, 23))), "waves")
else
    download(weatherbench_source(series_years), "wind")
    download(arco_source(collect(DateTime(first(series_years)):Hour(12):DateTime(
            last(series_years), 12, 31, 12))), "waves")
end
