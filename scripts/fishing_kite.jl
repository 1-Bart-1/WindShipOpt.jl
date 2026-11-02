# Fuel saving and payback of a towing kite on a 41 m beam trawler in the central North Sea
# (55 N, 3 E), over the ERA5 years with headings spread evenly, while trawling against
# gear drag and while steaming. Writes output/fishing.csv.
using Printf
include("setup.jl")

output = mkpath(joinpath(@__DIR__, "..", "output"))

"""
    override(assumptions, pairs)

`assumptions` with each name => value of `pairs` replaced.
"""
function override(assumptions, pairs)
    for (name, value) in pairs
        assumptions = with_value(assumptions, name, value)
    end
    return assumptions
end

# Damen/Hakvoort beam trawler: 41.05 m, 9 m beam, 1,470 kW (Marine Link); draft and block
# coefficient from a bottom-trawler design range (ARESA); MGO at Rotterdam, Oct 2026.
trawler = override(assumptions, [:reference_length => 41.0, :reference_beam => 9.0,
    :reference_draft => 4.0, :block_coefficient => 0.55, :service_speed => 10.0,
    :vlsfo_price => 31.0, :superstructure_height => 6.0, :sea_margin => 4.43])
latitude, longitude = 55.0, 3.0
times = 0.0:6.0:(WindShipOpt.duration(weather) - 6)
headings = deg2rad.(0:30:330)
hours_per_year = 5000.0

"""
    mean_fuel_power(table, speed, gear)

Mean fuel power [W] without and with the kite, and the share of time it is flown, at
`speed` [m/s] against `gear` drag [N] over all weather times and headings.
"""
function mean_fuel_power(table, speed, gear)
    price = table.ship.fuel.price * 3600
    without, with, flown, count = 0.0, 0.0, 0, 0
    for time in times, course in headings
        east, north = wind(weather, latitude, longitude, time)
        wind_speed = min(hypot(east, north), table.max_wind)
        angle = WindShipOpt.true_wind_angle(east, north, hypot(east, north), course)
        height, period, from = waves(weather, latitude, longitude, time)
        heading = WindShipOpt.wave_heading(from, course)
        drag = gear + (height > 0 ?
                       height^2 * table.wave_resistance(speed, period, heading) : 0.0)
        stowed = WindShipOpt.fuel_power(table, speed,
            table.stowed_thrust(speed, wind_speed, angle) + drag)
        flying = WindShipOpt.fuel_power(table, speed,
            table.flown_thrust(speed, wind_speed, angle) + drag)
        isfinite(stowed) || continue
        fly = flying * price + table.wear_cost < stowed * price
        without += stowed
        with += fly ? flying : stowed
        flown += fly
        count += 1
    end
    return without / count, with / count, flown / count
end

open(joinpath(output, "fishing.csv"), "w") do io
    println(io, "mode,gear,kite_area,fuel_power,fuel_power_kite,saving,flown,net,capital,",
        "payback")
    for area in (100.0, 200.0, 400.0)
        ship = Ship(ShipDesign(:vlsfo, 41.0; kite_area=area), trawler)
        table = PerformanceTable(ship, trawler)
        capital, _, _ = WindShipOpt.rig_costs(ship.rig, trawler)
        for (mode, speed, gear) in (("trawl", 3.5KNOT, 25e3), ("trawl", 3.5KNOT, 50e3),
                ("trawl", 3.5KNOT, 100e3), ("steam", 10.0KNOT, 0.0))
            without, with, share = mean_fuel_power(table, speed, gear)
            net = (without - with) * ship.fuel.price * 3600 * hours_per_year -
                  table.wear_cost * share * hours_per_year
            @printf(io, "%s,%.0f,%.0f,%.0f,%.0f,%.4f,%.3f,%.0f,%.0f,%.2f\n", mode, gear,
                area, without, with, 1 - with / without, share, net, capital,
                capital / net)
        end
    end
end
