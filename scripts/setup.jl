# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Shared by the scripts: the weather with the date of its time zero, the forecasts, the
# departure times and the route corridors. Uses the ERA5 data in era5/atlantic_wide/ with
# its land mask and all routes when it is there, and the synthetic weather, whose time
# zero is 1 January, with the Caribbean route otherwise; the forecasts are those
# download_forecast.jl wrote to era5/atlantic_wide/forecast/. Corridors are built on first
# use by `corridors`, at a scale relative to stages of 90 nmi.
using Dates
using WindShipOpt

assumptions = Assumptions()

"""
    forecast_plan_archives(control, directory, weather)

What each plan of the forecast study plans on, keyed by plan: the `control` archive, the
archives of the ensemble mean and of the margin in `directory`, and the
[`ForecastEnsemble`](@ref) of the control run and the member folders named `p*` there.
"""
function forecast_plan_archives(control, directory, weather)
    members = filter(startswith("p"), readdir(directory))
    return Dict(:control => control,
        :mean => ForecastArchive(joinpath(directory, "mean"), weather),
        :margin => ForecastArchive(joinpath(directory, "margin"), weather),
        :members => ForecastEnsemble([control;
            [ForecastArchive(joinpath(directory, member), weather) for member in members]]))
end
"""
    read_forecast_error(path)

The [`ForecastError`](@ref) of the CSV file at `path`, of leads every 6 h.
"""
function read_forecast_error(path)
    rows = split.(readlines(path)[2:end], ",")
    return ForecastError([parse(Float64, row[2]) for row in rows])
end

forecast_wind_error = read_forecast_error(joinpath(@__DIR__, "..", "data",
    "forecast_wind_error.csv"))

"""
    replanning_sources(operational)

The plans of the re-planning study, keyed by name, on the archive `operational` issued
every 6 h: re-planning at 24, 12 or 6 h, and adapting speed or course between plans.
"""
replanning_sources(operational) = Dict(
    :operational_24h => ReplannedForecast(operational; interval=24.0),
    :operational_12h => ReplannedForecast(operational; interval=12.0),
    :operational_6h => ReplannedForecast(operational; interval=6.0),
    :operational_24h_speed => ReplannedForecast(operational; adapts=:speed),
    :operational_24h_course => ReplannedForecast(operational; adapts=:course),
    :operational_6h_course => ReplannedForecast(operational; interval=6.0, adapts=:course))

era5_directory = joinpath(@__DIR__, "..", "era5", "atlantic_wide")
if isfile(joinpath(era5_directory, "waves", "grid.toml"))
    weather = ERA5Weather(era5_directory)
    weather_origin = weather.origin
    mask = GridMask(weather, north_atlantic_mask().islands)
    route_names = [:caribbean, :new_york, :bilbao, :dakar, :houston, :tubarao]
    last_departure = WindShipOpt.duration(weather) - 24 * 100.0
    departures = collect(0.0:(24 * 14.0):last_departure)
    weather_name = "ERA5 from $(weather.origin), $(length(departures)) departures"
    forecast_directory = joinpath(era5_directory, "forecast")
    forecast_archive = isdir(forecast_directory) ?
                       ForecastArchive(forecast_directory, weather) : nothing
    members_directory = joinpath(era5_directory, "forecast_members")
    ensemble_departures = departures[1:6:end]
    forecast_plans = isdir(joinpath(members_directory, "mean")) ?
                     forecast_plan_archives(forecast_archive, members_directory, weather) :
                     Dict{Symbol, Any}()
    operational_directory = joinpath(era5_directory, "forecast_gefs11")
    isdir(joinpath(operational_directory, "wind", "bias_2017")) && merge!(forecast_plans,
        replanning_sources(ForecastArchive(operational_directory, weather)))
else
    weather = SyntheticWeather()
    weather_origin = DateTime(2017)
    mask = north_atlantic_mask()
    route_names = [:caribbean]
    departures = [24.0 * (30 * month + 1) for month in 0:11]
    weather_name = "synthetic weather, 12 departures"
    forecast_archive = nothing
    forecast_plans = Dict{Symbol, Any}()
end
println("weather: ", weather_name)

"outbound and return corridors built so far, keyed by route name and corridor scale"
corridor_cache = Dict{Tuple{Symbol, Float64}, Tuple{Corridor, Corridor}}()

"guards `corridor_cache` against the threads of a study"
corridor_lock = ReentrantLock()

"""
    corridors(name, scale)

Outbound and return corridors of route `name` at corridor `scale`, built once per session.
"""
function corridors(name, scale)
    return lock(corridor_lock) do
        get!(() -> route_corridors(name, mask; scale), corridor_cache,
            (name, Float64(scale)))
    end
end
