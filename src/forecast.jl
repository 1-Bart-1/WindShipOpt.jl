# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"hours after its start that a forecast reaches the ship [h]"
const FORECAST_LATENCY = 6.0

"""
    ArchiveGroup

Fields of one group (wind or waves) of a forecast archive, per (lon, lat, lead, issue),
with the mean bias against the weather and the forecast's weight in its blend with
climatology per (lon, lat, lead) of each scored year.
"""
struct ArchiveGroup
    "grid of one issue, with time in hours after that issue"
    grid::GriddedFields
    "values per variable, (lon, lat, lead, issue); `NaN` on land and where not issued"
    fields::Dict{String, Array{Float16, 4}}
    "bias per year scored, estimated from the other years"
    bias::Dict{Int, Dict{String, Array{Float32, 3}}}
    "weight of the forecast in its blend with climatology per year scored, fitted on the
    other years"
    weights::Dict{Int, Array{Float32, 3}}
    "hours from the weather origin to the first issue [h]"
    first_issue::Float64
    "hours between issues [h]"
    issue_hours::Float64
end

function ArchiveGroup(directory::AbstractString, origin::DateTime)
    grid = TOML.parsefile(joinpath(directory, "grid.toml"))
    lats, lons = Float64.(grid["lats"]), Float64.(grid["lons"])
    leads = grid["leads"]
    issue_size = length(lons) * length(lats) * leads
    fields = Dict(name => Mmap.mmap(joinpath(directory, "$name.f16"), Array{Float16, 4},
        (length(lons), length(lats), leads,
            filesize(joinpath(directory, "$name.f16")) ÷ (2issue_size)))
                  for name in grid["variables"])
    shape = (length(lons), length(lats), leads)
    bias = Dict{Int, Dict{String, Array{Float32, 3}}}()
    weights = Dict{Int, Array{Float32, 3}}()
    for entry in readdir(directory)
        path = joinpath(directory, entry)
        if startswith(entry, "bias_")
            bias[parse(Int, chopprefix(entry, "bias_"))] = Dict(
                first(splitext(file)) => Mmap.mmap(joinpath(path, file),
                    Array{Float32, 3}, shape) for file in readdir(path))
        elseif startswith(entry, "weight_")
            weights[parse(Int, chopprefix(chopsuffix(entry, ".f32"), "weight_"))] =
                Mmap.mmap(path, Array{Float32, 3}, shape)
        end
    end
    first_issue = Dates.value(DateTime(grid["first_issue"]) - origin) / 3_600_000
    return ArchiveGroup(GriddedFields(lats, lons, grid["first_lead_hours"],
            grid["step_hours"], leads, Dict{String, Array{Float32, 3}}()), fields, bias,
        weights, first_issue, grid["issue_hours"])
end

issue_time(group::ArchiveGroup, issue) = group.first_issue + group.issue_hours * (issue - 1)

issue_count(group::ArchiveGroup) = minimum(size(field, 4) for field in values(group.fields))

holds_data(field, issue) =
    !all(value -> isnan(value) || iszero(value), view(field, :, :, 1, issue))

issued_in(group::ArchiveGroup, issue) =
    all(field -> holds_data(field, issue), values(group.fields))

"""
    ForecastArchive(directory, weather, climate)

Forecasts read from the `wind` and `waves` groups in `directory` written by
`scripts/download_forecast.jl`, issued together, on the time axis of `weather`, blended
with the [`Climatology`](@ref) `climate`.
"""
struct ForecastArchive
    wind::ArchiveGroup
    waves::ArchiveGroup
    "first day of the weather origin's year, for the year each issue is scored in"
    origin::DateTime
    climate::Climatology
end

function ForecastArchive(directory::AbstractString, weather::ERA5Weather,
        climate::Climatology)
    wind, waves = (ArchiveGroup(joinpath(directory, group), weather.origin)
                   for group in ("wind", "waves"))
    (wind.first_issue, wind.issue_hours) == (waves.first_issue, waves.issue_hours) ||
        error("the wind and waves of the forecast archive $directory are issued apart")
    return ForecastArchive(wind, waves, weather.origin, climate)
end

issue_time(archive::ForecastArchive, issue) = issue_time(archive.wind, issue)

"year of issue number `issue` of `group`, on the time axis of hours from `origin`"
issue_year(group::ArchiveGroup, origin, issue) =
    Dates.year(origin + Dates.Hour(round(Int, issue_time(group, issue))))
issue_year(archive::ForecastArchive, issue) =
    issue_year(archive.wind, archive.origin, issue)

"number of the last issue of `group` to have reached the ship at `time` [h]"
latest_issue(group::ArchiveGroup, time) =
    clamp(floor(Int, (time - FORECAST_LATENCY - group.first_issue) / group.issue_hours) + 1,
        1, issue_count(group))

"""
    last_held_issue(archive, time)

Number of the last issue of `archive` known at `time` [h] whose wind and waves hold data.
"""
function last_held_issue(archive::ForecastArchive, time)
    (; wind, waves) = archive
    issue = min(latest_issue(wind, time), latest_issue(waves, time))
    while issue > 1 && !(issued_in(wind, issue) && issued_in(waves, issue))
        issue -= 1
    end
    return issue
end

"""
    ArchivedForecast(archive, time)

What a router knows at `time` [h]: the last forecast in `archive` to reach the ship, less
its mean bias against the weather, blended with the archive's climatology by the weight of
its lead, both fitted on the other years; beyond its last lead or where it has no waves,
the climatology.
"""
struct ArchivedForecast
    archive::ForecastArchive
    "number of the issue"
    issue::Int
    "time of the issue [h]"
    issued::Float64
    "year whose bias and weights it reads"
    year::Int
end

function ArchivedForecast(archive::ForecastArchive, time)
    issue = last_held_issue(archive, time)
    years = keys(archive.wind.bias)
    year = clamp(issue_year(archive, issue), minimum(years), maximum(years))
    return ArchivedForecast(archive, issue, issue_time(archive, issue), year)
end

"""
    ForecastError(lead_step, wind)

Root mean square error of the vector wind [m/s] of a forecast, per lead of `lead_step`,
2`lead_step`, 3`lead_step`... [h]; a lead takes the value of the nearest of them.
"""
struct ForecastError
    lead_step::Float64
    wind::Vector{Float64}
end

"standard error [m/s] of one component of the wind forecast at `lead` [h]"
wind_spread(error::ForecastError, lead) = error.wind[
    clamp(round(Int, lead / error.lead_step), 1, length(error.wind))] / sqrt(2)

"""
    ExpectedForecast(forecast, error)

Forecast source of a ship that plans on the [`ForecastArchive`](@ref) `forecast`, weighing
the wind error of the [`ForecastError`](@ref) `error` at the lead of each sample.
"""
struct ExpectedForecast
    forecast::ForecastArchive
    error::ForecastError
end

"""
    UncertainForecast(known, issued, error)

The [`ArchivedForecast`](@ref) `known`, issued at `issued` [h], with the wind error of the
[`ForecastError`](@ref) `error`.
"""
struct UncertainForecast{K}
    known::K
    issued::Float64
    error::ForecastError
end

wind(forecast::UncertainForecast, lat, lon, time) = wind(forecast.known, lat, lon, time)
waves(forecast::UncertainForecast, lat, lon, time) = waves(forecast.known, lat, lon, time)

"standard error [m/s] of the wind speed at `time` [h] that a plan on `weather` weighs"
wind_spread(weather, time) = 0.0
wind_spread(forecast::UncertainForecast, time) =
    wind_spread(forecast.error, time - forecast.issued)

final_time_step(::UncertainForecast) = ROUTER_SETTINGS[].weighed_final_time_step

"[`CostToGo`](@ref) of a plan on `forecast`: that of its forecast without the wind error"
CostToGo(held, corridor::Corridor, table::RouteTable,
    forecast::UncertainForecast, departure; options...) =
    CostToGo(held, corridor, table, forecast.known, departure; options...)

function known_weather(forecast::ExpectedForecast, weather, time)
    known = known_weather(forecast.forecast, weather, time)
    return UncertainForecast(known, known.issued, forecast.error)
end

known_weather(forecast::ForecastArchive, weather, time) = ArchivedForecast(forecast, time)
within(group::ArchiveGroup, issued, time) = time - issued <= last_time(group.grid)

issue_arrays(group::ArchiveGroup, issue, names) =
    map(name -> view(group.fields[name], :, :, :, issue), names)

bias_arrays(group::ArchiveGroup, year, names) = map(name -> group.bias[year][name], names)

"""
    corrected_wind(forecast, lat, lon, time)

East and north wind [m/s] of `forecast` less its bias, and its weight in the blend with
climatology at that lead; NaN beyond its last lead.
"""
function corrected_wind(forecast::ArchivedForecast, lat, lon, time)
    group = forecast.archive.wind
    within(group, forecast.issued, time) || return NaN, NaN, NaN
    names = ("u10", "v10")
    east, north, east_bias, north_bias, weight = sample(group.grid,
        (issue_arrays(group, forecast.issue, names)...,
            bias_arrays(group, forecast.year, names)..., group.weights[forecast.year]),
        lat, lon, time - forecast.issued)
    return east - east_bias, north - north_bias, weight
end

"""
    corrected_waves(forecast, lat, lon, time)

Wave height [m] and period [s] of `forecast` less their bias, its east and north direction
components, and its weight in the blend with climatology at that lead; NaN where it holds no
waves or beyond its last lead.
"""
function corrected_waves(forecast::ArchivedForecast, lat, lon, time)
    group = forecast.archive.waves
    within(group, forecast.issued, time) || return NaN, NaN, NaN, NaN, NaN
    height, period, east, north, height_bias, period_bias, weight = sample(group.grid,
        (issue_arrays(group, forecast.issue,
                ("height", "period", "direction_east", "direction_north"))...,
            bias_arrays(group, forecast.year, ("height", "period"))...,
            group.weights[forecast.year]), lat, lon, time - forecast.issued)
    return height - height_bias, period - period_bias, east, north, weight
end

"`climate` moved toward `forecast` by `weight`"
blend(climate, forecast, weight) = climate + weight * (forecast - climate)

function wind(forecast::ArchivedForecast, lat, lon, time)
    east, north, weight = corrected_wind(forecast, lat, lon, time)
    isnan(weight) && return wind(forecast.archive.climate, lat, lon, time)
    mean_east, mean_north, mean_speed = climate_wind(forecast.archive.climate, lat, lon,
        time)
    return scaled_to(blend(mean_east, east, weight), blend(mean_north, north, weight),
        blend(mean_speed, hypot(east, north), weight))
end

function waves(forecast::ArchivedForecast, lat, lon, time)
    known = corrected_waves(forecast, lat, lon, time)
    climate = climate_waves(forecast.archive.climate, lat, lon, time)
    (isnan(first(known)) || isnan(first(climate))) && return wave_values(climate)
    return wave_values(map((normal, value) -> blend(normal, value, last(known)), climate,
        known[1:4]))
end

"""
    scored_issues(group, origin)

Time [h] of each issue of the archive `group` on the time axis from `origin`, and the year
it is scored in.
"""
function scored_issues(group::ArchiveGroup, origin)
    issues = 1:issue_count(group)
    return issue_time.(Ref(group), issues), issue_year.(Ref(group), origin, issues)
end

"""
    observed_leads(group, observed, issue_times)

Each (issue, lead, time [h], step) at which a forecast the archive `group` holds, issued at
`issue_times` [h], meets the stored time `step` of `observed`.
"""
function observed_leads(group::ArchiveGroup, observed::GriddedFields, issue_times)
    meetings = Tuple{Int, Int, Float64, Int}[]
    held = filter(issue -> issued_in(group, issue), eachindex(issue_times))
    for issue in held, lead in 1:group.grid.steps
        time = issue_times[issue] + group.grid.time_offset +
               (lead - 1) * group.grid.step_hours
        step = (time - observed.time_offset) / observed.step_hours + 1
        isinteger(step) && 1 <= step <= observed.steps &&
            push!(meetings, (issue, lead, time, Int(step)))
    end
    return meetings
end

"""
    forecast_bias(group, observed, issue_times, years, names)

Mean of forecast less `observed` per (lon, lat, lead) of each variable in `names` of the
archive `group`, for each year in `years` (the year scored of each issue), from the issues
of the other years. `issue_times` [h] place the issues on the time axis of `observed`,
whose grid the group shares.
"""
function forecast_bias(group::ArchiveGroup, observed::GriddedFields, issue_times, years,
        names)
    shape = (length(group.grid.lons), length(group.grid.lats), group.grid.steps)
    totals = Dict(year => Dict(name => zeros(shape) for name in names) for year in years)
    counts = Dict(year => Dict(name => zeros(Int, shape) for name in names)
                  for year in years)
    for (issue, lead, _, step) in observed_leads(group, observed, issue_times)
        for name in names
            add_difference!(view(totals[years[issue]][name], :, :, lead),
                view(counts[years[issue]][name], :, :, lead),
                view(group.fields[name], :, :, lead, issue),
                view(observed.fields[name], :, :, step))
        end
    end
    return Dict(year => Dict(name => Float32.(
            sum(totals[other][name] for other in years if other != year) ./
            sum(counts[other][name] for other in years if other != year))
                for name in names) for year in unique(years))
end

function add_difference!(total, count, forecast, observed)
    for i in eachindex(total, count, forecast, observed)
        difference = forecast[i] - observed[i]
        isnan(difference) && continue
        total[i] += difference
        count[i] += 1
    end
end

"`path`, with the link there removed so that writing to it never reaches its target"
unlinked(path) = (islink(path) && rm(path); path)

"""
    write_group_bias(directory, group, observed, names, origin)

Write [`forecast_bias`](@ref) of the variables `names` of the archive `group` in
`directory` against `observed`, on the time axis from `origin`, to a `bias_<year>` folder
per year scored, in place of a link there.
"""
function write_group_bias(directory::AbstractString, group::ArchiveGroup,
        observed::GriddedFields, names, origin)
    for (year, fields) in forecast_bias(group, observed, scored_issues(group, origin)...,
        names)
        folder = mkpath(unlinked(joinpath(directory, "bias_$year")))
        for (variable, bias) in fields
            write(joinpath(folder, "$variable.f32"), bias)
        end
    end
end

"""
    write_forecast_bias(directory, weather)

Write [`write_group_bias`](@ref) of the wind and the wave height and period of the forecast
archive in `directory` against `weather`.
"""
function write_forecast_bias(directory::AbstractString, weather::ERA5Weather)
    for (group, observed, names) in (("wind", weather.wind, ("u10", "v10")),
        ("waves", weather.waves, ("height", "period")))
        folder = joinpath(directory, group)
        write_group_bias(folder, ArchiveGroup(folder, weather.origin), observed, names,
            weather.origin)
    end
end

"""
    forecast_weights(group, observed, normals, origin, names)

Weight of the bias-corrected forecast of the archive `group` in its blend with the
climatology `normals` per (lon, lat, lead), for each year scored: the regression of the
anomaly of `observed` from `normals` on that of the forecast, without intercept, over the
issues of the other years and the variables `names`, within 0 and 1, and 0 where never met.
Times are hours from `origin`.
"""
function forecast_weights(group::ArchiveGroup, observed::GriddedFields,
        normals::GriddedFields, origin, names)
    normals.lats ≈ group.grid.lats && normals.lons ≈ group.grid.lons ||
        error("the climatology's grid differs from the forecast's")
    issue_times, years = scored_issues(group, origin)
    shape = (length(group.grid.lons), length(group.grid.lats), group.grid.steps)
    products = Dict(year => zeros(shape) for year in keys(group.bias))
    squares = Dict(year => zeros(shape) for year in keys(group.bias))
    for (issue, lead, time, step) in observed_leads(group, observed, issue_times)
        position = month_position(origin, time)
        for name in names
            normal = month_field(normals, name, position)
            for year in keys(products)
                year == years[issue] && continue
                add_regression!(view(products[year], :, :, lead),
                    view(squares[year], :, :, lead),
                    view(group.fields[name], :, :, lead, issue),
                    view(group.bias[year][name], :, :, lead),
                    view(observed.fields[name], :, :, step), normal)
            end
        end
    end
    return Dict(year => Float32.(ifelse.(squares[year] .> 0,
        clamp.(products[year] ./ squares[year], 0, 1), 0)) for year in keys(products))
end

"the (lon, lat) field `name` of the monthly `fields` at `position` [months]"
function month_field(fields::GriddedFields, name, position)
    k, t = time_cell(fields, position)
    months = fields.fields[name]
    return (1 - t) .* view(months, :, :, k) .+ t .* view(months, :, :, k + 1)
end

function add_regression!(products, squares, forecast, bias, observed, normal)
    for i in eachindex(products, squares, forecast, bias, observed, normal)
        anomaly = forecast[i] - bias[i] - normal[i]
        observed_anomaly = observed[i] - normal[i]
        (isnan(anomaly) || isnan(observed_anomaly)) && continue
        products[i] += observed_anomaly * anomaly
        squares[i] += anomaly^2
    end
end

"""
    write_group_weights(directory, group, observed, normals, names, origin)

Write [`forecast_weights`](@ref) of the variables `names` of the archive `group` in
`directory` against `observed` and the climatology `normals`, on the time axis from
`origin`, to a `weight_<year>.f32` file per year scored, in place of a link there.
"""
function write_group_weights(directory::AbstractString, group::ArchiveGroup,
        observed::GriddedFields, normals::GriddedFields, names, origin)
    for (year, weights) in forecast_weights(group, observed, normals, origin, names)
        write(unlinked(joinpath(directory, "weight_$year.f32")), weights)
    end
end

"""
    write_forecast_weights(directory, weather, climate)

Write [`write_group_weights`](@ref) of the wind vector and the wave height of the forecast
archive in `directory`, whose bias [`write_forecast_bias`](@ref) wrote, against `weather`
and the [`Climatology`](@ref) `climate`.
"""
function write_forecast_weights(directory::AbstractString, weather::ERA5Weather,
        climate::Climatology)
    for (group, observed, normals, names) in (("wind", weather.wind, climate.wind,
            ("u10", "v10")), ("waves", weather.waves, climate.waves, ("height",)))
        folder = joinpath(directory, group)
        write_group_weights(folder, ArchiveGroup(folder, weather.origin), observed,
            normals, names, weather.origin)
    end
end
