# Figures of routed voyages Rotterdam - Guadeloupe: routes on a map, what happens along a
# winter passage, wind-only polars, and the wind angles actually sailed.
using CairoMakie
using Statistics
using WindShipOpt
using WindShipOpt: is_land

include("setup.jl")
output = mkpath(joinpath(@__DIR__, "..", "output"))

designs = [ShipDesign(:methanol, 85.0), ShipDesign(:wing, 85.0; wing_area=800.0),
    ShipDesign(:kite, 85.0; kite_area=400.0)]
labels = ["e-methanol", "wing 800 m²", "kite 400 m²"]
colours = Makie.wong_colors()[1:3]
ships = [Ship(design, assumptions) for design in designs]
hourly = [WindShipOpt.time_cost(ShipCosts(ship, assumptions), assumptions) for ship in ships]
tables = [PerformanceTable(ship) for ship in ships]
port_hours = 24assumptions[:port_time_per_call]

function round_trip_traces(index, departure)
    ship, table = ships[index], tables[index]
    out = route(outbound, table, ship.fuel, weather, departure; time_cost=hourly[index])
    back_departure = departure + out.duration + port_hours
    back = route(inbound, table, ship.fuel, weather, back_departure;
        time_cost=hourly[index])
    return LegTrace(ship, out, weather, departure),
    LegTrace(ship, back, weather, back_departure)
end

traces = Matrix{Any}(undef, length(designs), length(departures))
Threads.@threads for job in CartesianIndices(traces)
    traces[job] = round_trip_traces(job[1], departures[job[2]])
end

function draw_land!(axis)
    lats = range(5, 56; step=0.25)
    lons = range(-70, 10; step=0.25)
    land = [is_land(mask, lat, lon) for lon in lons, lat in lats]
    heatmap!(axis, lons, lats, land; colormap=[:transparent, (:grey, 0.6)])
end

function draw_wind!(axis, time)
    lons, lats = -66:4:6, 8:4:54
    points = [Point2f(lon, lat) for lon in lons for lat in lats]
    vectors = [Vec2f(wind(weather, p[2], p[1], time)...) for p in points]
    arrows2d!(axis, points, vectors .* 0.18f0; color=(:black, 0.35))
end

# Map: outbound and return route of each design for two departures.
summer = findfirst(departure -> departure >= 24 * 181, departures)
for (season, column) in (("winter", 1), ("summer", summer))
    figure = Figure(; size=(1300, 600))
    for (leg_index, title) in ((1, "outbound"), (2, "return"))
        axis = Axis(figure[1, leg_index]; title="$title, $season departure",
            xlabel="longitude [°]", ylabel="latitude [°]", aspect=DataAspect(),
            limits=(-68, 8, 8, 56))
        draw_land!(axis)
        first_trace = traces[1, column][leg_index]
        draw_wind!(axis, departures[column] + mean(first_trace.time))
        corridor = leg_index == 1 ? outbound : inbound
        band = findall(vec(any(corridor.water; dims=1)))
        for lateral in (first(band), centre_index(corridor), last(band))
            lines!(axis, corridor.lon[:, lateral], corridor.lat[:, lateral];
                color=:grey, linestyle=:dash)
        end
        for (i, label) in enumerate(labels)
            trace = traces[i, column][leg_index]
            lines!(axis, trace.lon, trace.lat; color=colours[i], linewidth=2.5, label)
        end
        leg_index == 1 && axislegend(axis; position=:lb)
    end
    save(joinpath(output, "routes_$season.png"), figure)
end

# Along one outbound passage.
figure = Figure(; size=(1100, 1400))
quantities = [
    ("speed [kn]", trace -> trace.speed ./ KNOT),
    ("true wind angle [°]", trace -> rad2deg.(trace.true_wind_angle)),
    ("10 m wind [m/s]", trace -> trace.wind_speed),
    ("wave height [m]", trace -> trace.wave_height),
    ("wave resistance [kN]", trace -> trace.added_resistance ./ 1e3),
    ("rig thrust [kN]", trace -> trace.rig_thrust ./ 1e3),
    ("leeway drag [kN]", trace -> trace.induced_drag ./ 1e3),
    ("fuel power [kW]", trace -> trace.fuel_power ./ 1e3)]
for (leg_index, title) in ((1, "outbound, winter"), (2, "return, winter"))
    for (row, (ylabel, quantity)) in enumerate(quantities)
        axis = Axis(figure[row, leg_index]; ylabel, title=row == 1 ? title : "",
            xlabel=row == length(quantities) ? "time [days]" : "")
        for (i, label) in enumerate(labels)
            trace = traces[i, 1][leg_index]
            stairs!(axis, trace.time ./ 24, quantity(trace); color=colours[i], label,
                step=:post)
        end
        row == 1 && leg_index == 1 && axislegend(axis; position=:rb)
    end
end
save(joinpath(output, "passage_winter.png"), figure)

# Wind-only speed polars.
figure = Figure(; size=(1100, 500))
angles = deg2rad.(0:5:180)
for (column, wind_speed) in enumerate((8.0, 12.0))
    axis = PolarAxis(figure[1, column]; title="speed on wind alone [kn], $wind_speed m/s",
        thetalimits=(0, π), theta_0=-π / 2, direction=-1)
    for (i, label) in enumerate(labels[2:3])
        speeds = [sailing_speed(ships[i + 1], wind_speed, angle) / KNOT for angle in angles]
        lines!(axis, angles, speeds; color=colours[i + 1], linewidth=2.5, label)
    end
end
Legend(figure[1, 3], [LineElement(; color, linewidth=2.5) for color in colours[2:3]],
    labels[2:3])
save(joinpath(output, "polars.png"), figure)

# True wind angles sailed over all departures, weighted by time.
figure = Figure(; size=(1100, 450))
for (leg_index, title) in ((1, "outbound"), (2, "return"))
    axis = Axis(figure[1, leg_index]; title="true wind angle sailed, $title, $(length(departures)) departures",
        xlabel="true wind angle [°]", ylabel="share of time")
    for (i, label) in enumerate(labels)
        angles_sailed = Float64[]
        weights = Float64[]
        for column in eachindex(departures)
            trace = traces[i, column][leg_index]
            append!(angles_sailed, rad2deg.(trace.true_wind_angle))
            append!(weights, diff([trace.time; trace.time[end] + 1.0]))
        end
        hist!(axis, angles_sailed; bins=0:10:180, weights, normalization=:probability,
            color=(colours[i], 0.45), strokecolor=colours[i], strokewidth=1.5, label)
    end
    leg_index == 1 && axislegend(axis; position=:lt)
end
save(joinpath(output, "wind_angles.png"), figure)
println("figures written to ", output)
