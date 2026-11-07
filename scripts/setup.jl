# Shared by the scripts: the weather with the date of its time zero, the departure times
# and the route corridors. Uses the ERA5 data in era5/atlantic_wide/ with its land mask and
# all routes when it is there, and the synthetic weather, whose time zero is 1 January,
# with the Caribbean route otherwise. Corridors are built on first use by `corridors`, at
# a scale relative to stages of 90 nmi.
using Dates
using WindShipOpt

assumptions = Assumptions()
era5_directory = joinpath(@__DIR__, "..", "era5", "atlantic_wide")
if isfile(joinpath(era5_directory, "waves", "grid.toml"))
    weather = ERA5Weather(era5_directory)
    weather_origin = weather.origin
    mask = GridMask(weather, north_atlantic_mask().islands)
    route_names = [:caribbean, :new_york, :bilbao, :dakar, :houston, :tubarao]
    last_departure = WindShipOpt.duration(weather) - 24 * 100.0
    departures = collect(0.0:(24 * 14.0):last_departure)
    weather_name = "ERA5 from $(weather.origin), $(length(departures)) departures"
else
    weather = SyntheticWeather()
    weather_origin = DateTime(2017)
    mask = north_atlantic_mask()
    route_names = [:caribbean]
    departures = [24.0 * (30 * month + 1) for month in 0:11]
    weather_name = "synthetic weather, 12 departures"
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
