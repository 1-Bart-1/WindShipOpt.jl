# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Download the 10 m wind of the control run of NOAA's operational GEFSv11 forecasts, issued
# every 6 h through 2017-2019, onto the ERA5 wind grid in
# era5/atlantic_wide/forecast_gefs11/wind/, as download_forecast.jl does for the GEFSv12
# reforecast, with its mean bias against ERA5 from the other years. Waves of this archive
# are those of the GEFSv12 wave reforecast, which starts once a day: no public archive
# holds wave forecasts of those years issued more often. Resumable: rerun to continue.
ENV["ERA5_REGION"] = "atlantic_wide"
include("setup.jl")
include("download_forecast.jl")

operational_store = "https://noaa-gefs-pds.s3.amazonaws.com"
operational_issues = DateTime(2017, 1, 1):Hour(6):DateTime(2019, 12, 31, 18)
operational_root = joinpath(era5, "forecast_gefs11")
"first day the store files a run under `pgrb2a/`, with leads below 100 h in two digits"
first_nested_day = Date(2018, 7, 27)

"""
    operational_url(issue, lead)

GRIB file of the control run issued at the DateTime `issue` at `lead` [h] in the store.
"""
function operational_url(issue, lead)
    day, cycle = Dates.format(issue, "yyyymmdd"), Dates.format(issue, "HH")
    name = "gec00.t$(cycle)z.pgrb2af"
    Date(issue) < first_nested_day &&
        return "$operational_store/gefs.$day/$cycle/$name$(lpad(lead, 3, '0'))"
    return "$operational_store/gefs.$day/$cycle/pgrb2a/$name$(lpad(lead, 2, '0'))"
end

"""
    operational_ranges(issue, record, member)

Files and byte ranges of the 10 m wind `record` at each lead of `issue`; empty where a
lead is not in the store.
"""
function operational_ranges(issue, record, member)
    pieces = Tuple{String, Tuple{Int, Union{Int, Nothing}}}[]
    for lead in wind_leads
        url = operational_url(issue, lead)
        found = try
            index_ranges("$url.idx",
                line -> occursin(":$record:10 m above ground:", line) &&
                        occursin(":$(lead_text(lead)):", line))
        catch
            return empty(pieces)
        end
        length(found) == 1 || return empty(pieces)
        push!(pieces, (url, only(found)))
    end
    return pieces
end

operational_group = (; groups[1]..., records=Dict("u10" => "UGRD", "v10" => "VGRD"),
    ranges=operational_ranges)

"""
    link_waves(root)

Make the wave forecasts of `root` those of the GEFSv12 reforecast archive, by a path
relative to `root`.
"""
function link_waves(root)
    link = joinpath(root, "waves")
    islink(link) && rm(link)
    symlink(relpath(joinpath(output, "waves"), root), link)
end

if abspath(PROGRAM_FILE) == @__FILE__
    download(operational_group; root=operational_root, schedule=operational_issues)
    link_waves(operational_root)
    wind_directory = joinpath(operational_root, "wind")
    WindShipOpt.write_group_bias(wind_directory,
        WindShipOpt.ArchiveGroup(wind_directory, weather.origin), weather.wind,
        ("u10", "v10"), weather.origin)
    println("operational forecast archive complete")
end
