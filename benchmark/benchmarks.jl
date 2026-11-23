# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Benchmarks of the weather router's dominant step, a leg routed by `forecast_route` as a
# round trip routes it, for AirspeedVelocity.jl. The weather is a small ERA5-format grid of
# smoothly varying wind and waves written to a temporary folder, so no ERA5 data is needed.
using BenchmarkTools, TOML, WindShipOpt

"""
    patterned_weather(directory)

[`ERA5Weather`](@ref) on a 1.5° grid of the North Atlantic written to `directory`, its wind,
wind aloft and waves varying smoothly in place and over 50 days.
"""
function patterned_weather(directory)
    lats, lons, step = collect(0.0:1.5:60.0), collect(-90.0:1.5:15.0), 6
    times = 0:step:1200
    wave(lat, lon, time) = sin(lat / 9 + time / 40) * cos(lon / 13 - time / 70)
    speed(lat, lon, time) = 9 + 5wave(lat, lon, time)
    fields = Dict("u10" => (lat, lon, time) -> speed(lat, lon, time) * cos(lat / 20),
        "v10" => (lat, lon, time) -> speed(lat, lon, time) * sin(lon / 25),
        "speed_100" => (lat, lon, time) -> 1.25speed(lat, lon, time),
        "speed_1000" => (lat, lon, time) -> 1.6speed(lat, lon, time),
        "height" => (lat, lon, time) -> 2 + 1.5wave(lat, lon, time),
        "period" => (lat, lon, time) -> 8 + 2wave(lat, lon, time),
        "direction" => (lat, lon, time) -> mod(240 + 60wave(lat, lon, time), 360))
    for (group, names) in (("wind", ("u10", "v10")), ("aloft", ("speed_100", "speed_1000")),
        ("waves", ("height", "period", "direction")))
        mkpath(joinpath(directory, group))
        open(joinpath(directory, group, "grid.toml"), "w") do io
            TOML.print(io, Dict("lats" => lats, "lons" => lons, "step_hours" => step,
                "heights" => [100, 1000], "first_time" => "2017-01-01T00:00:00",
                "variables" => collect(names)))
        end
        for name in names
            write(joinpath(directory, group, "$name.f32"),
                [Float32(fields[name](lat, lon, time)) for lon in lons, lat in lats,
                 time in times])
        end
    end
    return ERA5Weather(directory)
end

"route table and hourly time cost [USD/h] of the 140 m e-ammonia ship with `rig`"
function rigged_ship(assumptions; rig...)
    ship = Ship(ShipDesign(:ammonia, 140.0; rig...), assumptions)
    hourly = WindShipOpt.leg_time_costs(first(WindShipOpt.ship_costs(ship, assumptions)),
        assumptions)
    return RouteTable(PerformanceTable(ship, assumptions)), first(hourly)
end

const SUITE = BenchmarkGroup()

let assumptions = Assumptions(), weather = patterned_weather(mktempdir())
    mask = GridMask(weather, north_atlantic_mask().islands)
    outbound = first(route_corridors(:caribbean, mask; scale=2))
    for (name, rig) in (("rotors", (; rotor_area=800.0)), ("kite", (; kite_area=3200.0)))
        table, time_cost = rigged_ship(assumptions; rig...)
        SUITE["forecast_route"][name] = @benchmarkable WindShipOpt.forecast_route(
            $outbound, $table, $weather, 24.0; time_cost=$time_cost) samples=5 evals=1
    end
end
