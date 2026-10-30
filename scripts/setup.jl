# Shared by the scripts: route corridors, the weather, and the departure times. Uses the
# ERA5 data in era5/ when it is there, and the synthetic weather otherwise.
using WindShipOpt

assumptions = Assumptions()
mask = north_atlantic_mask()
outbound, inbound = caribbean_corridors(mask)
era5_directory = joinpath(@__DIR__, "..", "era5")
if isfile(joinpath(era5_directory, "waves", "grid.toml"))
    weather = ERA5Weather(era5_directory)
    last_departure = WindShipOpt.duration(weather) - 24 * 100.0
    departures = collect(0.0:(24 * 14.0):last_departure)
    weather_name = "ERA5 from $(weather.origin), $(length(departures)) departures"
else
    weather = SyntheticWeather()
    departures = [24.0 * (30 * month + 1) for month in 0:11]
    weather_name = "synthetic weather, 12 departures"
end
println("weather: ", weather_name)
