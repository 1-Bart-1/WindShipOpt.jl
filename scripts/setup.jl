# Shared by the scripts: the weather, the forecasts, the departure times and the route
# corridors. Uses the ERA5 data in era5/atlantic_wide/ with its land mask and all routes
# when it is there, and the synthetic weather with the Caribbean route otherwise; the
# forecasts are those download_forecast.jl wrote to era5/atlantic_wide/forecast/.
# Corridors are built on first use by `corridors`, at a scale relative to stages of 90 nmi.
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
era5_directory = joinpath(@__DIR__, "..", "era5", "atlantic_wide")
if isfile(joinpath(era5_directory, "waves", "grid.toml"))
    weather = ERA5Weather(era5_directory)
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
else
    weather = SyntheticWeather()
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
