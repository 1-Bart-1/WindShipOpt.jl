# Prototype of a per-point, per-time wind profile from ERA5; not included from
# WindShipOpt.jl. Load with `include(joinpath(pkgdir(WindShipOpt), "src", "shear_proto.jl"))`.
using WindShipOpt: Environment, wind_at_height

"standard gravity used by ECMWF to turn geopotential into geopotential height [m/s^2]"
const ERA5_GRAVITY = 9.80665

"mean geometric height over sea of ERA5 L137 model levels 121-137 [m], from 2018-01-01"
const MODEL_LEVEL_HEIGHTS = [732.3, 653.3, 580.5, 513.4, 451.7, 394.9, 342.8, 294.9, 251.0,
    210.8, 174.0, 140.2, 109.4, 81.2, 55.4, 31.8, 10.3]

"heights of the stored profile ratios [m]"
const PROFILE_HEIGHTS = [10.0, 30.0, 100.0, 200.0, 300.0, 450.0, 600.0]

"""
    profile_nodes(speed_10m, speed_100m, level_heights, level_speeds)

Heights [m] and wind speeds [m/s] of one ERA5 column, sorted by height: the 10 m and
100 m winds and the pressure-level winds whose height lies above 150 m. Levels closer to
the surface, or under it where the surface pressure is low, are left out because ERA5
extrapolates them.
"""
function profile_nodes(speed_10m, speed_100m, level_heights, level_speeds)
    heights = [10.0, 100.0]
    speeds = [speed_10m, speed_100m]
    for (height, speed) in sort(collect(zip(level_heights, level_speeds)))
        height > 150 || continue
        push!(heights, height)
        push!(speeds, speed)
    end
    return heights, speeds
end

"""
    profile_speed(heights, speeds, height)

Wind speed [m/s] at `height` [m], linear in the logarithm of height between the
`profile_nodes` and held at the top node above them.
"""
function profile_speed(heights, speeds, height)
    height >= last(heights) && return last(speeds)
    i = clamp(searchsortedlast(heights, height), 1, length(heights) - 1)
    fraction = log(height / heights[i]) / log(heights[i + 1] / heights[i])
    return speeds[i] + fraction * (speeds[i + 1] - speeds[i])
end

"""
    profile_ratios(speed_10m, speed_100m, geopotentials, level_speeds;
                   heights=PROFILE_HEIGHTS)

Ratios U(z)/U(10 m) at `heights` [m] for one ERA5 column with pressure-level
`geopotentials` [m^2/s^2] and wind speeds [m/s]; NaN where the 10 m wind is calm.
"""
function profile_ratios(speed_10m, speed_100m, geopotentials, level_speeds;
        heights=PROFILE_HEIGHTS)
    speed_10m > 0.5 || return fill(NaN, length(heights))
    nodes = profile_nodes(speed_10m, speed_100m, geopotentials ./ ERA5_GRAVITY,
        level_speeds)
    return [profile_speed(nodes..., height) / speed_10m for height in heights]
end

"""
    ratio_at(ratios, height; heights=PROFILE_HEIGHTS)

U(height)/U(10 m) interpolated in the logarithm of height between stored `ratios`.
"""
ratio_at(ratios, height; heights=PROFILE_HEIGHTS) = profile_speed(heights, ratios, height)

"""
    equivalent_10m_wind(env, wind_at_reference, height)

10 m wind [m/s] that the log profile of `env` would raise to `wind_at_reference` at
`height` [m]: the key into a table indexed by 10 m wind for a rig whose force depends
only on the wind at `height`.
"""
equivalent_10m_wind(env::Environment, wind_at_reference, height) =
    wind_at_reference / wind_at_height(env, 1.0, height)

"""
    model_level_ratios(speed_10m, level_speeds; heights=PROFILE_HEIGHTS)

Ratios U(z)/U(10 m) at `heights` [m] from the wind speeds [m/s] on ERA5 model levels
121-137, top first; NaN where the 10 m wind is calm.
"""
function model_level_ratios(speed_10m, level_speeds; heights=PROFILE_HEIGHTS)
    speed_10m > 0.5 || return fill(NaN, length(heights))
    nodes = reverse(MODEL_LEVEL_HEIGHTS), reverse(level_speeds)
    return [profile_speed(nodes..., height) / speed_10m for height in heights]
end
