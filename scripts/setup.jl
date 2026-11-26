# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Shared by the scripts: the weather with the date of its time zero, the forecasts, the
# departure times with the paper's sample of them, and the route corridors. Uses the ERA5
# data in era5/atlantic_wide/ with its land mask and all routes when it is there, and the
# synthetic weather, whose time zero is 1 January, with the Caribbean route otherwise; the
# forecasts are those download_forecast.jl wrote to era5/atlantic_wide/forecast/.
# Corridors are built on first use by `corridors`, at a scale relative to stages of 90 nmi.
using Dates
using WindShipOpt
using WindShipOpt: with_changed

assumptions = Assumptions()

era5_directory = joinpath(@__DIR__, "..", "era5", "atlantic_wide")
if isfile(joinpath(era5_directory, "waves", "grid.toml"))
    weather = ERA5Weather(era5_directory)
    weather_origin = weather.origin
    mask = GridMask(weather, north_atlantic_mask().islands)
    route_names = [:caribbean, :new_york, :bilbao, :dakar, :houston, :tubarao]
    last_departure = WindShipOpt.duration(weather) - 24 * 100.0
    departures = collect(0.0:(24 * 14.0):last_departure)
    # the paper's sample: in each calendar month once, the departure nearest its 15th
    sample_months = [(2017, 1), (2017, 4), (2017, 7), (2017, 10), (2017, 12), (2018, 2),
        (2018, 5), (2018, 8), (2018, 11), (2019, 3), (2019, 6), (2019, 9)]
    paper_departures = map(sample_months) do (year, month)
        middle = Hour(DateTime(year, month, 15) - weather_origin).value
        departures[argmin(abs.(departures .- middle))]
    end
    weather_name = "ERA5 from $(weather.origin), $(length(departures)) departures"
    forecast_directory = joinpath(era5_directory, "forecast")
    climate_directory = joinpath(era5_directory, "climate")
    forecast_archive = isdir(forecast_directory) ? ForecastArchive(forecast_directory,
        weather, Climatology(climate_directory, weather.origin)) : nothing
else
    weather = SyntheticWeather()
    weather_origin = DateTime(2017)
    mask = north_atlantic_mask()
    route_names = [:caribbean]
    departures = [24.0 * (30 * month + 1) for month in 0:11]
    paper_departures = departures
    weather_name = "synthetic weather, 12 departures"
    forecast_archive = nothing
end
println("weather: ", weather_name)

"outbound and return corridors built so far, keyed by route name and corridor scales"
corridor_cache = Dict{Tuple{Symbol, Float64, Float64}, Tuple{Corridor, Corridor}}()

"guards `corridor_cache` against the threads of a study"
corridor_lock = ReentrantLock()

"""
    corridors(name, scale)

Outbound and return corridors of route `name` at corridor `scale`, one number or a pair of
stage and row scales, built once per session.
"""
function corridors(name, scale)
    stage_scale, lateral_scale = scale isa Number ? (scale, scale) : scale
    return lock(corridor_lock) do
        get!(() -> route_corridors(name, mask; scale=stage_scale,
                lateral_spacing=WindShipOpt.LATERAL_SPACING * lateral_scale),
            corridor_cache, (name, Float64(stage_scale), Float64(lateral_scale)))
    end
end
