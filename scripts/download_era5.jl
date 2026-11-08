# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Download ERA5 for one region into era5/<group>/ (North Atlantic) or
# era5/<region>/<group>/, one Float32 file per variable plus grid.toml. The region is the
# ERA5_REGION environment variable:
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
years = 2017:2019
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

function weatherbench_source()
    lats = decode(Float64, "$weatherbench/latitude/0")
    lons = signed_lon.(decode(Float64, "$weatherbench/longitude/0"))
    rows = sort(findall(lat -> in_range(lat, lat_range), lats); by=row -> lats[row])
    columns = filter(column -> in_range(lons[column], lon_range), sortperm(lons))
    origin = DateTime(1959)
    first_step = Dates.value(DateTime(first(years)) - origin) ÷ 21_600_000
    last_step = Dates.value(DateTime(last(years) + 1) - origin) ÷ 21_600_000 - 1
    chunks = [(chunk, [step - 8chunk + 1
                       for step in max(8chunk, first_step):min(8chunk + 7, last_step)])
              for chunk in (first_step ÷ 8):(last_step ÷ 8)]
    times = [origin + Hour(6step) for step in first_step:last_step]
    read_chunk(url) = reshape(decode(Float32, url), length(lats), length(lons), 8)
    variables = Dict("u10" => "10m_u_component_of_wind", "v10" => "10m_v_component_of_wind")
    return Source(weatherbench, variables, columns, rows, lons[columns], lats[rows], chunks,
        times, read_chunk)
end

function arco_source()
    lats = collect(90.0:-0.25:-90.0)
    lons = signed_lon.(collect(0.0:0.25:359.75))
    rows = reverse(findall(lat -> in_range(lat, lat_range) && iszero(mod(lat, 0.5)), lats))
    columns = filter(column -> in_range(lons[column], lon_range) &&
                                   iszero(mod(lons[column], 0.5)), sortperm(lons))
    times = collect(DateTime(first(years)):Hour(12):DateTime(last(years), 12, 31, 12))
    chunks = [(Dates.value(time - DateTime(1900)) ÷ 3_600_000, [1]) for time in times]
    read_chunk(url) = permutedims(reshape(decode(Float32, url), 1440, 721, 1), (2, 1, 3))
    variables = Dict("height" => "significant_height_of_combined_wind_waves_and_swell",
        "direction" => "mean_wave_direction", "period" => "peak_wave_period")
    return Source(arco, variables, columns, rows, lons[columns], lats[rows], chunks, times,
        read_chunk)
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
        jobs = [(name, index) for index in batch for name in names]
        blocks = asyncmap(jobs; ntasks=16) do (name, index)
            chunk = first(source.chunks[index])
            url = "$(source.store)/$(source.variables[name])/$chunk.0.0"
            block = source.read_chunk(url)
            return block[source.rows, source.columns, last(source.chunks[index])]
        end
        for ((name, index), block) in zip(jobs, blocks)
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

download(weatherbench_source(), "wind")
download(arco_source(), "waves")
