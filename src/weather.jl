"""
    SyntheticWeather

Analytic stand-in for reanalysis wind over the North Atlantic: trade winds, horse
latitudes and westerlies with a seasonal cycle, plus eastward-travelling synoptic
disturbances that are strongest in the westerlies.
"""
struct SyntheticWeather
    "phase of each synoptic wave [rad]"
    phases::Vector{Float64}
    "wavenumber of each synoptic wave [1/m]"
    wavenumbers::Vector{Float64}
    "angular frequency of each synoptic wave [rad/h]"
    frequencies::Vector{Float64}
end

"""
    SyntheticWeather(; seed=1)

Synthetic weather with three synoptic waves of 2000-4000 km wavelength travelling east
at about 10 m/s, with phases drawn from `seed`.
"""
function SyntheticWeather(; seed=1)
    rng = Random.Xoshiro(seed)
    wavelengths = [2.0e6, 3.0e6, 4.0e6]
    wavenumbers = 2π ./ wavelengths
    frequencies = wavenumbers .* 10.0 .* 3600
    return SyntheticWeather(2π .* rand(rng, 3), wavenumbers, frequencies)
end

"""
    wind(weather, lat, lon, time)

Eastward and northward 10 m wind [m/s] at `lat`, `lon` [deg] and `time` [h] after the
start of the year.
"""
function wind(weather::SyntheticWeather, lat, lon, time)
    season = 1 + 0.2cos(2π * (time / 24 - 15) / 365)
    trades = exp(-((lat - 16) / 9)^2)
    westerlies = exp(-((lat - 48) / 9)^2)
    east = -7.0season * trades + 9.0season * westerlies
    north = -3.0season * exp(-((lat - 18) / 10)^2)
    amplitude = 1.5 + 5.0westerlies
    x = EARTH_RADIUS * deg2rad(lon) * cosd(lat)
    y = EARTH_RADIUS * deg2rad(lat)
    for (phase, k, ω) in zip(weather.phases, weather.wavenumbers, weather.frequencies)
        argument = k * (x + 0.5y) - ω * time + phase
        east += amplitude / 3 * sin(argument)
        north += amplitude * cos(argument)
    end
    return east, north
end
