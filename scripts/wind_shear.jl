# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Mean ERA5 wind over the sea at each stored height per unit of the mean 10 m wind, and the
# power-law exponent that gives it, over the whole region, the trade-wind belt (10-25 deg N)
# and north of 40 deg N: the source of the wind shear exponent in data/assumptions.yaml.
#   julia --project=. scripts/wind_shear.jl [era5 directory]
using Statistics
using WindShipOpt

weather = ERA5Weather(isempty(ARGS) ? joinpath(@__DIR__, "..", "era5", "atlantic_wide") :
                      ARGS[1])
lats, lons = weather.wind.lats, weather.wind.lons
"wave height at the start of the record, NaN over land"
start_waves(lat, lon) =
    first(WindShipOpt.sample(weather.waves, (weather.wave_arrays[1],), lat, lon, 0.0))
"mean over time and over the sea cells whose latitude `band` holds of each speed array"
function sea_mean(speeds, band)
    cells = [(i, j) for i in eachindex(lons), j in eachindex(lats)
             if band(lats[j]) && !isnan(start_waves(lats[j], lons[i]))]
    return mean(mean(view(speeds, i, j, :)) for (i, j) in cells)
end
wind_10m = hypot.(weather.wind_arrays...)
bands = (("whole region", latitude -> true),
    ("10-25 deg N", latitude -> 10 <= latitude <= 25),
    ("north of 40 deg N", latitude -> latitude >= 40))
println("region, height [m], speed / 10 m speed [-], exponent [-]")
for (name, band) in bands
    mean_10m = sea_mean(wind_10m, band)
    for (height, speeds) in zip(weather.aloft_heights, weather.aloft_arrays)
        height in (100, 300, 500) || continue
        ratio = sea_mean(speeds, band) / mean_10m
        println(name, ", ", Int(height), ", ", round(ratio; digits=3), ", ",
            round(log(ratio) / log(height / 10); digits=3))
    end
end
