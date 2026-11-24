# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""
    uniform_weather()

ERA5 weather held in memory over the North Atlantic for 60 days: a steady north-easterly
wind of 8 m/s, 10 m/s aloft, and 2 m waves of 8 s from the north-east.
"""
function uniform_weather()
    lats, lons = collect(0.0:5.0:60.0), collect(-80.0:5.0:10.0)
    steps, step_hours = 3, 720.0
    field(value) = fill(Float32(value), length(lons), length(lats), steps)
    gridded(fields) = GriddedFields(lats, lons, 0.0, step_hours, steps, fields)
    heights = 100:100:1200
    wind = gridded(Dict("u10" => field(-8sind(45)), "v10" => field(-8cosd(45))))
    aloft = gridded(Dict("speed_$height" => field(10.0) for height in heights))
    waves = gridded(Dict("height" => field(2.0), "period" => field(8.0),
        "direction_east" => field(sind(45)), "direction_north" => field(cosd(45))))
    return ERA5Weather(DateTime(2017), wind, aloft, waves, heights)
end

@setup_workload begin
    assumptions = Assumptions()
    weather = uniform_weather()
    mask = GridMask(weather, north_atlantic_mask().islands)
    corridors = route_corridors(:caribbean, mask; scale=4.0)
    rigs = ((;), (; kite_area=3200.0), (; wing_area=1500.0), (; rotor_area=800.0),
        (; suction_area=800.0), (; rigid_kite_area=200.0), (; lei_kite_area=700.0))
    coarse = RouterSettings(routing_speeds=2, search_speed_stride=1, time_step=12.0,
        edge_sample_hours=12.0)
    stand_in = PatternForce((0.3, 0.8, 0.2), 1.0, 0.3)
    @compile_workload with_router_settings(coarse) do
        with(STAND_IN_PATTERN => stand_in) do
            for rig in rigs
                design = ShipDesign(:ammonia, 140.0; rig...)
                ship = Ship(design, assumptions; route=:caribbean)
                round_trip(ship, corridors..., weather, [0.0], assumptions)
            end
        end
    end
    # the routes left their workspaces in the pool, which would be saved in the image
    empty!(FREE_WORKSPACES)
end
