# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Download the forecasts a ship could have routed on: the control run of NOAA's GEFSv12
# reforecast, issued daily at 00 UTC, with its 10 m wind and its WAVEWATCH III sea state
# out to 16 days, into era5/<region>/forecast/{wind,waves}/ on the grids of the ERA5 data
# of the same region (ERA5_REGION, as for download_era5.jl). Wind is averaged over each
# 1.5° cell, waves are sampled at the 0.5° points. An issue the archive holds incomplete is
# left empty (NaN). Then writes the mean bias of each year's forecasts against ERA5, from
# the other years. Resumable: rerun to continue.
using Dates
using Downloads
using GRIB
using TOML
using WindShipOpt

wind_store = "https://noaa-gefs-retrospective.s3.amazonaws.com/GEFSv12/reforecast"
wave_store = "https://noaa-nws-gefswaves-reforecast-pds.s3.amazonaws.com/GEFSv12/reforecast"
issues = Date(2016, 12, 31):Day(1):Date(2019, 12, 31)
region = get(ENV, "ERA5_REGION", "atlantic")
era5 = joinpath(@__DIR__, "..", "era5", region == "atlantic" ? "" : region)
output = joinpath(era5, "forecast")
wind_leads = 6:6:384
wave_leads = 12:12:384
wave_start_hour = 3
wind_records = Dict("u10" => "ugrd", "v10" => "vgrd")
wave_records = Dict("height" => "HTSGW", "period" => "PERPW", "direction" => "WWSDIR")

function read_bytes(url; range=nothing)
    headers = isnothing(range) ? Pair{String, String}[] :
              ["Range" => "bytes=$(first(range))-$(something(last(range), ""))"]
    for attempt in 1:6
        try
            buffer = IOBuffer()
            Downloads.download(url, buffer; headers, timeout=300)
            return take!(buffer)
        catch
            attempt == 6 && rethrow()
            sleep(5attempt)
        end
    end
end

"""
    index_ranges(url, wanted)

First and last byte (`nothing` for the end of the file) in the GRIB file at `url` of the
records whose inventory line `wanted` accepts, in file order, from its `.idx` inventory.
"""
function index_ranges(url, wanted)
    lines = split(String(read_bytes(url)), '\n'; keepempty=false)
    starts = [parse(Int, split(line, ':')[2]) for line in lines]
    return [(starts[i], i < length(lines) ? starts[i + 1] - 1 : nothing)
            for i in eachindex(lines) if wanted(lines[i])]
end

lead_text(hours) = "$hours hour fcst"

function wind_ranges(date, variable)
    stamp = Dates.format(date, "yyyymmdd") * "00"
    files = String[]
    ranges = Tuple{Int, Union{Int, Nothing}}[]
    for days in ("1-10", dayofweek(date) == Wednesday ? "10-35" : "10-16")
        url = "$wind_store/$(year(date))/$stamp/c00/Days:$days/" *
              "$(variable)_hgt_$(stamp)_c00.grib2"
        found = index_ranges("$url.idx", line -> occursin(":10 m above ground:", line) &&
            any(lead -> occursin(":$(lead_text(lead)):", line), wind_leads))
        append!(files, fill(url, length(found)))
        append!(ranges, found)
    end
    return collect(zip(files, ranges))
end

function wave_ranges(date, record)
    stamp = Dates.format(date, "yyyymmdd")
    url = "$wave_store/$(year(date))/$stamp/gridded/gefs.wave.$stamp.c00.global.0p25"
    found = index_ranges("$url.idx", line -> occursin(":$record:surface:", line) &&
        any(lead -> occursin(":$(lead_text(lead - wave_start_hour)):", line), wave_leads))
    return [("$url.grib2", range) for range in found]
end

"""
    overlap_weights(targets, half_width, sources, source_width; period=Inf)

Weights of each source cell of width `source_width` in each target cell of half width
`half_width` around `targets`, by the length they share, normalised per target.
"""
function overlap_weights(targets, half_width, sources, source_width; period=Inf)
    weights = zeros(length(targets), length(sources))
    for (i, target) in enumerate(targets), (j, source) in enumerate(sources)
        offset = isfinite(period) ? mod(source - target + period / 2, period) - period / 2 :
                 source - target
        weights[i, j] = max(0.0, min(offset + source_width / 2, half_width) -
                                 max(offset - source_width / 2, -half_width))
    end
    return weights ./ sum(weights; dims=2)
end

"""
    decode(bytes, leads, regrid)

Fields of the GRIB records in `bytes`, one per lead [h] after 00 UTC in `leads`, each
turned by `regrid` from (lon, lat) on its own grid to the target grid; `nothing` where a
lead is missing.
"""
function decode(bytes, leads, regrid)
    path, io = mktemp()
    write(io, bytes)
    close(io)
    fields = Dict{Int, Matrix{Float32}}()
    GribFile(path) do file
        for message in file
            hours = message["step"] + message["dataTime"] ÷ 100
            values = message["values"]
            values[values .== message["missingValue"]] .= NaN
            lons = range(message["longitudeOfFirstGridPointInDegrees"];
                step=message["iDirectionIncrementInDegrees"], length=message["Ni"])
            lats = range(message["latitudeOfFirstGridPointInDegrees"];
                step=-message["jDirectionIncrementInDegrees"], length=message["Nj"])
            fields[hours] = regrid(values, lons, lats)
        end
    end
    rm(path)
    all(lead -> haskey(fields, lead), leads) || return nothing
    return [fields[lead] for lead in leads]
end

signed(lon) = lon > 180 ? lon - 360 : lon

function cell_average(grid)
    half_width = abs(grid["lats"][2] - grid["lats"][1]) / 2
    cache = Dict{Tuple{Int, Int, Float64}, Tuple{Matrix{Float64}, Matrix{Float64}}}()
    cache_lock = ReentrantLock()
    function regrid(values, lons, lats)
        width = abs(lats[2] - lats[1])
        lon_weights, lat_weights = @lock cache_lock get!(cache,
            (length(lons), length(lats), width)) do
            (overlap_weights(grid["lons"], half_width, signed.(lons), width; period=360.0),
                overlap_weights(grid["lats"], half_width, lats, width))
        end
        return Float32.(lon_weights * values * lat_weights')
    end
    return regrid
end

function point_sample(grid)
    function regrid(values, lons, lats)
        columns = [findfirst(lon -> isapprox(signed(lon), target; atol=1e-3), lons)
                   for target in grid["lons"]]
        rows = [findfirst(lat -> isapprox(lat, target; atol=1e-3), lats)
                for target in grid["lats"]]
        return Float32.(values[columns, rows])
    end
    return regrid
end

function direction_components(fields)
    direction = fields["direction"]
    return Dict("height" => fields["height"], "period" => fields["period"],
        "direction_east" => [sind.(field) for field in direction],
        "direction_north" => [cosd.(field) for field in direction])
end

groups = (
    (name="wind", records=wind_records, leads=wind_leads, ranges=wind_ranges,
        regrid=cell_average, finish=identity),
    (name="waves", records=wave_records, leads=wave_leads, ranges=wave_ranges,
        regrid=point_sample, finish=direction_components))

function issue_fields(group, date, regrid, shape)
    variables = sort(collect(keys(group.records)))
    pieces = [group.ranges(date, group.records[variable]) for variable in variables]
    bytes = asyncmap(Iterators.flatten(pieces); ntasks=12) do (url, range)
        read_bytes(url; range)
    end
    fields = Dict{String, Vector{Matrix{Float32}}}()
    first_piece = 1
    for (variable, piece) in zip(variables, pieces)
        records = bytes[first_piece:(first_piece + length(piece) - 1)]
        decoded = isempty(records) ? nothing :
                  decode(reduce(vcat, records), group.leads, regrid)
        if isnothing(decoded)
            println(group.name, " issue ", date, " incomplete in the archive, left empty")
            empty = [fill(NaN32, shape) for _ in group.leads]
            return group.finish(Dict(name => empty for name in variables))
        end
        fields[variable] = decoded
        first_piece += length(piece)
    end
    return group.finish(fields)
end

function download(group)
    directory = mkpath(joinpath(output, group.name))
    grid = TOML.parsefile(joinpath(era5, group.name, "grid.toml"))
    regrid = group.regrid(grid)
    names = sort(collect(keys(group.finish(Dict(name => [zeros(Float32, 1, 1)]
                                                for name in keys(group.records))))))
    open(joinpath(directory, "grid.toml"), "w") do io
        TOML.print(io, Dict("lats" => grid["lats"], "lons" => grid["lons"],
            "first_issue" => string(DateTime(first(issues))), "issue_hours" => 24,
            "first_lead_hours" => first(group.leads), "step_hours" => step(group.leads),
            "leads" => length(group.leads), "variables" => names))
    end
    issue_bytes = length(grid["lats"]) * length(grid["lons"]) * length(group.leads) * 2
    files = Dict(name => open(joinpath(directory, "$name.f16"), "a+") for name in names)
    done = minimum(filesize(joinpath(directory, "$name.f16")) ÷ issue_bytes
                   for name in names)
    for io in values(files)
        truncate(io, done * issue_bytes)
        seekend(io)
    end
    shape = (length(grid["lons"]), length(grid["lats"]))
    for batch in Iterators.partition((done + 1):length(issues), 8)
        fields = fetch.([Threads.@spawn issue_fields(group, issues[index], regrid, shape)
                         for index in batch])
        for issue in fields, name in names, field in issue[name]
            write(files[name], Float16.(field))
        end
        foreach(flush, values(files))
        println(group.name, " issue ", last(batch), "/", length(issues))
    end
    foreach(close, values(files))
end

foreach(download, groups)
write_forecast_bias(output, ERA5Weather(era5))
println("forecast archive complete")
