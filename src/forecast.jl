# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"hours after its start that a forecast reaches the ship [h]"
const FORECAST_LATENCY = 6.0

"""
    ArchiveGroup

Fields of one group (wind or waves) of a forecast archive, per (lon, lat, lead, issue),
with the mean bias against the weather per (lon, lat, lead) of each scored year.
"""
struct ArchiveGroup
    "grid of one issue, with time in hours after that issue"
    grid::GriddedFields
    "values per variable, (lon, lat, lead, issue); `NaN` on land and where not issued"
    fields::Dict{String, Array{Float16, 4}}
    "bias per year scored, estimated from the other years"
    bias::Dict{Int, Dict{String, Array{Float32, 3}}}
    "hours from the weather origin to the first issue [h]"
    first_issue::Float64
    "hours between issues [h]"
    issue_hours::Float64
end

function ArchiveGroup(directory::AbstractString, origin::DateTime)
    foreach(require_link_target, readdir(directory; join=true))
    grid = TOML.parsefile(joinpath(directory, "grid.toml"))
    lats, lons = Float64.(grid["lats"]), Float64.(grid["lons"])
    leads = grid["leads"]
    issue_size = length(lons) * length(lats) * leads
    fields = Dict(name => Mmap.mmap(joinpath(directory, "$name.f16"), Array{Float16, 4},
        (length(lons), length(lats), leads,
            filesize(joinpath(directory, "$name.f16")) ÷ (2issue_size)))
                  for name in grid["variables"])
    bias = Dict{Int, Dict{String, Array{Float32, 3}}}()
    for entry in readdir(directory)
        startswith(entry, "bias_") || continue
        folder = joinpath(directory, entry)
        bias[parse(Int, entry[6:end])] = Dict(first(splitext(file)) => Mmap.mmap(
            joinpath(folder, file), Array{Float32, 3}, (length(lons), length(lats), leads))
                                              for file in readdir(folder))
    end
    first_issue = Dates.value(DateTime(grid["first_issue"]) - origin) / 3_600_000
    return ArchiveGroup(GriddedFields(lats, lons, grid["first_lead_hours"],
            grid["step_hours"], leads, Dict{String, Array{Float32, 3}}()), fields, bias,
        first_issue, grid["issue_hours"])
end

"""
    require_link_target(path)

Error, naming the link and its target, if `path` is a link whose target does not exist.
"""
function require_link_target(path)
    islink(path) && !ispath(path) &&
        error("forecast archive link $path points to $(readlink(path)), which is gone")
end

"""
    link_relative(target, link)

Make `link` a link to `target` by a path relative to the folder of `link`, replacing in one
step a link already there. Error if `link` is a real file or folder.
"""
function link_relative(target, link)
    islink(link) || !ispath(link) || error("$link is not a link, so it is not replaced")
    pending = tempname(dirname(link); cleanup=false)
    symlink(relpath(target, dirname(link)), pending)
    Base.rename(pending, link)
end

"""
    link_control_group(control, folder)

Link the bias and the wave period and direction of the archive group in `control` into the
archive group in `folder`, by paths relative to `folder`, replacing links already there.
"""
function link_control_group(control, folder)
    shared = ("period.f16", "direction_east.f16", "direction_north.f16")
    entries = filter(name -> startswith(name, "bias_") || name in shared, readdir(control))
    for entry in entries
        link_relative(joinpath(control, entry), joinpath(folder, entry))
    end
end

issue_time(group::ArchiveGroup, issue) = group.first_issue + group.issue_hours * (issue - 1)

issue_count(group::ArchiveGroup) = minimum(size(field, 4) for field in values(group.fields))

holds_data(field, issue) =
    !all(value -> isnan(value) || iszero(value), view(field, :, :, 1, issue))

issued_in(group::ArchiveGroup, issue) =
    all(field -> holds_data(field, issue), values(group.fields))

"""
    ForecastArchive(directory, weather)

Forecasts read from the `wind` and `waves` groups in `directory` written by
`scripts/download_forecast.jl`, each on its own schedule, on the time axis of `weather`.
"""
struct ForecastArchive
    wind::ArchiveGroup
    waves::ArchiveGroup
    "first day of the weather origin's year, for the year each issue is scored in"
    origin::DateTime
end

ForecastArchive(directory::AbstractString, weather::ERA5Weather) = ForecastArchive(
    ArchiveGroup(joinpath(directory, "wind"), weather.origin),
    ArchiveGroup(joinpath(directory, "waves"), weather.origin), weather.origin)

"""
    margin_wind(east, north)

East and north wind of the margin, from member winds (lon, lat, lead, member) [m/s]: the
lower quartile of the member speeds, in the direction of the mean vector.
"""
function margin_wind(east, north)
    mean_east = dropdims(mean(east; dims=4); dims=4)
    mean_north = dropdims(mean(north; dims=4); dims=4)
    margin_east, margin_north = copy(mean_east), copy(mean_north)
    for I in CartesianIndices(mean_east)
        speeds = [hypot(east[I, member], north[I, member]) for member in axes(east, 4)]
        norm = hypot(mean_east[I], mean_north[I])
        scale = any(isnan, speeds) ? NaN32 :
                norm > 0 ? quantile(speeds, 0.25) / norm : 0.0f0
        margin_east[I], margin_north[I] = mean_east[I] * scale, mean_north[I] * scale
    end
    return margin_east, margin_north
end

"""
    margin_height(height)

Wave height of the margin from member heights (lon, lat, lead, member) [m]: the upper
quartile of the members.
"""
function margin_height(height)
    margin = dropdims(mean(height; dims=4); dims=4)
    for I in CartesianIndices(margin)
        heights = [height[I, member] for member in axes(height, 4)]
        margin[I] = any(isnan, heights) ? NaN32 : quantile(heights, 0.75)
    end
    return margin
end

"""
    ForecastEnsemble(members)

The [`ForecastArchive`](@ref)s of several runs of one forecast model, each issued every
day, that [`forecast_route`](@ref) plans on together.
"""
struct ForecastEnsemble
    members::Vector{ForecastArchive}
end

issue_time(archive::ForecastArchive, issue) = issue_time(archive.wind, issue)

issue_year(archive::ForecastArchive, issue) =
    Dates.year(archive.origin + Dates.Hour(round(Int, issue_time(archive, issue))))

"number of the last issue of `group` to have reached the ship at `time` [h]"
latest_issue(group::ArchiveGroup, time) =
    clamp(floor(Int, (time - FORECAST_LATENCY - group.first_issue) / group.issue_hours) + 1,
        1, issue_count(group))

"""
    last_held_issues(archive, time)

Numbers of the last wind and wave issues of `archive` known at `time` [h] that hold data:
one issue for both where the groups share a schedule, each on its own otherwise.
"""
function last_held_issues(archive::ForecastArchive, time)
    (; wind, waves) = archive
    wind_issue, wave_issue = latest_issue(wind, time), latest_issue(waves, time)
    if wind.issue_hours == waves.issue_hours && wind.first_issue == waves.first_issue
        issue = min(wind_issue, wave_issue)
        while issue > 1 && !(issued_in(wind, issue) && issued_in(waves, issue))
            issue -= 1
        end
        return issue, issue
    end
    while wind_issue > 1 && !issued_in(wind, wind_issue)
        wind_issue -= 1
    end
    while wave_issue > 1 && !issued_in(waves, wave_issue)
        wave_issue -= 1
    end
    return wind_issue, wave_issue
end

"""
    ArchivedForecast(archive, weather, time)

What a router knows at `time` [h]: the last forecast in `archive` to reach the ship, less
its mean bias against `weather` estimated from the other years, and beyond its last lead
or where it has no waves the weather of the same date in another year, as
[`ForecastWeather`](@ref).
"""
struct ArchivedForecast{W}
    archive::ForecastArchive
    "number of the wind issue"
    issue::Int
    "time of the wind issue [h]"
    issued::Float64
    "number of the wave issue"
    wave_issue::Int
    "time of the wave issue [h]"
    wave_issued::Float64
    year::Int
    beyond::ForecastWeather{W}
end

function ArchivedForecast(archive::ForecastArchive, weather, time)
    issue, wave_issue = last_held_issues(archive, time)
    issued, wave_issued = issue_time(archive, issue), issue_time(archive.waves, wave_issue)
    years = keys(archive.wind.bias)
    year = clamp(issue_year(archive, issue), minimum(years), maximum(years))
    span = min(last_time(archive.wind.grid), last_time(archive.waves.grid))
    return ArchivedForecast(archive, issue, issued, wave_issue, wave_issued, year,
        ForecastWeather(weather, min(issued, wave_issued), span))
end

"""
    ShortestLead(archive)

Forecast source of a ship that knows, at every time ahead, the forecast of `archive` with
the shortest lead there: what the forecast model says of the weather, without the error
that grows with lead.
"""
struct ShortestLead
    archive::ForecastArchive
end

"""
    ShortestLeadForecast(archive, weather)

What a [`ShortestLead`](@ref) ship knows: at each time the [`ArchivedForecast`](@ref) of
`archive` last issued before it.
"""
struct ShortestLeadForecast{W}
    archive::ForecastArchive
    weather::W
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
CostToGo(workspace::RouteWorkspace, corridor::Corridor, table::RouteTable,
    forecast::UncertainForecast, departure; options...) =
    CostToGo(workspace, corridor, table, forecast.known, departure; options...)

function known_weather(forecast::ExpectedForecast, weather, time, horizon)
    known = known_weather(forecast.forecast, weather, time, horizon)
    return UncertainForecast(known, known.issued, forecast.error)
end

known_weather(forecast::ShortestLead, weather, time, horizon) =
    ShortestLeadForecast(forecast.archive, weather)

known_weather(forecast::ForecastArchive, weather, time, horizon) =
    ArchivedForecast(forecast, weather, time)
known_weather(forecast::ForecastEnsemble, weather, time, horizon) =
    [ArchivedForecast(member, weather, time) for member in forecast.members]

within(group::ArchiveGroup, issued, time) = time - issued <= last_time(group.grid)

issue_arrays(group::ArchiveGroup, issue, names) =
    map(name -> view(group.fields[name], :, :, :, issue), names)

bias_arrays(group::ArchiveGroup, year, names) = map(name -> group.bias[year][name], names)

function wind(forecast::ArchivedForecast, lat, lon, time)
    group = forecast.archive.wind
    within(group, forecast.issued, time) || return wind(forecast.beyond, lat, lon, time)
    names = ("u10", "v10")
    east, north, east_bias, north_bias = sample(group.grid,
        (issue_arrays(group, forecast.issue, names)...,
            bias_arrays(group, forecast.year, names)...), lat, lon, time - forecast.issued)
    return east - east_bias, north - north_bias
end

function waves(forecast::ArchivedForecast, lat, lon, time)
    group = forecast.archive.waves
    within(group, forecast.wave_issued, time) ||
        return waves(forecast.beyond, lat, lon, time)
    height, period, east, north, height_bias, period_bias = sample(group.grid,
        (issue_arrays(group, forecast.wave_issue,
                ("height", "period", "direction_east", "direction_north"))...,
            bias_arrays(group, forecast.year, ("height", "period"))...), lat, lon,
        time - forecast.wave_issued)
    isnan(height) && return waves(forecast.beyond, lat, lon, time)
    return max(height - height_bias, 0.0), max(period - period_bias, 0.0), atan(east, north)
end

"""
    ForecastParts(forecast, forecast_wind, forecast_waves)

Forecast source of a ship that plans on the wind of `forecast` where `forecast_wind` and on
its waves where `forecast_waves`, and on the real weather otherwise.
"""
struct ForecastParts{F}
    forecast::F
    forecast_wind::Bool
    forecast_waves::Bool
end

"What a [`ForecastParts`](@ref) ship knows: each of wind and waves from `known` or `truth`."
struct PartlyKnownWeather{K, W}
    known::K
    truth::W
    forecast_wind::Bool
    forecast_waves::Bool
end

known_weather(parts::ForecastParts, weather, time, horizon) = PartlyKnownWeather(
    known_weather(parts.forecast, weather, time, horizon), weather, parts.forecast_wind,
    parts.forecast_waves)

wind(partly::PartlyKnownWeather, lat, lon, time) =
    wind(partly.forecast_wind ? partly.known : partly.truth, lat, lon, time)
waves(partly::PartlyKnownWeather, lat, lon, time) =
    waves(partly.forecast_waves ? partly.known : partly.truth, lat, lon, time)
wind_spread(partly::PartlyKnownWeather, time) =
    partly.forecast_wind ? wind_spread(partly.known, time) : 0.0

wind(forecast::ShortestLeadForecast, lat, lon, time) =
    wind(ArchivedForecast(forecast.archive, forecast.weather, time), lat, lon, time)
waves(forecast::ShortestLeadForecast, lat, lon, time) =
    waves(ArchivedForecast(forecast.archive, forecast.weather, time), lat, lon, time)

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
    for (issue, issued) in enumerate(issue_times), lead in 1:group.grid.steps
        time = issued + group.grid.time_offset + (lead - 1) * group.grid.step_hours
        step = (time - observed.time_offset) / observed.step_hours + 1
        isinteger(step) && 1 <= step <= observed.steps || continue
        for name in names
            add_difference!(view(totals[years[issue]][name], :, :, lead),
                view(counts[years[issue]][name], :, :, lead),
                view(group.fields[name], :, :, lead, issue),
                view(observed.fields[name], :, :, Int(step)))
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

"""
    write_group_bias(directory, group, observed, names, origin)

Write [`forecast_bias`](@ref) of the variables `names` of the archive `group` in
`directory` against `observed`, on the time axis from `origin`, to a `bias_<year>` folder
per year scored.
"""
function write_group_bias(directory::AbstractString, group::ArchiveGroup,
        observed::GriddedFields, names, origin)
    issue_times = issue_time.(Ref(group), 1:issue_count(group))
    years = Dates.year.(origin .+ Dates.Hour.(round.(Int, issue_times)))
    for (year, fields) in forecast_bias(group, observed, issue_times, years, names)
        folder = mkpath(joinpath(directory, "bias_$year"))
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
    archive = ForecastArchive(directory, weather)
    write_group_bias(joinpath(directory, "wind"), archive.wind, weather.wind,
        ("u10", "v10"), weather.origin)
    write_group_bias(joinpath(directory, "waves"), archive.waves, weather.waves,
        ("height", "period"), weather.origin)
end
