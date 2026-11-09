# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"hours after its 00 UTC start that a day's forecast reaches the ship [h]"
const FORECAST_LATENCY = 6.0

"""
    ArchiveGroup

Fields of one group (wind or waves) of a daily forecast archive, per (lon, lat, lead,
issue), with the mean bias against the weather per (lon, lat, lead) of each scored year.
"""
struct ArchiveGroup
    "grid of one issue, with time in hours after that issue"
    grid::GriddedFields
    "values per variable, (lon, lat, lead, issue); `NaN` on land and where not issued"
    fields::Dict{String, Array{Float16, 4}}
    "bias per year scored, estimated from the other years"
    bias::Dict{Int, Dict{String, Array{Float32, 3}}}
end

function ArchiveGroup(directory::AbstractString)
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
    return ArchiveGroup(GriddedFields(lats, lons, grid["first_lead_hours"],
            grid["step_hours"], leads, Dict{String, Array{Float32, 3}}()), fields, bias)
end

issue_count(group::ArchiveGroup) = minimum(size(field, 4) for field in values(group.fields))

holds_data(field, issue) =
    !all(value -> isnan(value) || iszero(value), view(field, :, :, 1, issue))

issued_in(group::ArchiveGroup, issue) =
    all(field -> holds_data(field, issue), values(group.fields))

"""
    ForecastArchive(directory, weather)

Forecasts issued every day at 00 UTC, read from the `wind` and `waves` groups in
`directory` written by `scripts/download_forecast.jl`, on the time axis of `weather`.
"""
struct ForecastArchive
    wind::ArchiveGroup
    waves::ArchiveGroup
    "hours from the weather origin to the first issue [h]"
    first_issue::Float64
    "first day of the weather origin's year, for the year each issue is scored in"
    origin::DateTime
end

function ForecastArchive(directory::AbstractString, weather::ERA5Weather)
    grid = TOML.parsefile(joinpath(directory, "wind", "grid.toml"))
    first_issue = Dates.value(DateTime(grid["first_issue"]) - weather.origin) / 3_600_000
    return ForecastArchive(ArchiveGroup(joinpath(directory, "wind")),
        ArchiveGroup(joinpath(directory, "waves")), first_issue, weather.origin)
end

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

issue_time(archive::ForecastArchive, issue) = archive.first_issue + 24.0 * (issue - 1)

issue_year(archive::ForecastArchive, issue) =
    Dates.year(archive.origin + Dates.Hour(round(Int, issue_time(archive, issue))))

"""
    ArchivedForecast(archive, weather, time)

What a router knows at `time` [h]: the last forecast in `archive` to reach the ship, less
its mean bias against `weather` estimated from the other years, and beyond its last lead
or where it has no waves the weather of the same date in another year, as
[`ForecastWeather`](@ref).
"""
struct ArchivedForecast{W}
    archive::ForecastArchive
    issue::Int
    "time of the issue [h]"
    issued::Float64
    year::Int
    beyond::ForecastWeather{W}
end

function ArchivedForecast(archive::ForecastArchive, weather, time)
    issues = min(issue_count(archive.wind), issue_count(archive.waves))
    issue = clamp(floor(Int, (time - FORECAST_LATENCY - archive.first_issue) / 24) + 1, 1,
        issues)
    while issue > 1 && !(issued_in(archive.wind, issue) && issued_in(archive.waves, issue))
        issue -= 1
    end
    issued = issue_time(archive, issue)
    years = keys(archive.wind.bias)
    year = clamp(issue_year(archive, issue), minimum(years), maximum(years))
    span = min(last_time(archive.wind.grid), last_time(archive.waves.grid))
    return ArchivedForecast(archive, issue, issued, year,
        ForecastWeather(weather, issued, span))
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

known_weather(forecast::ShortestLead, weather, time, horizon) =
    ShortestLeadForecast(forecast.archive, weather)

known_weather(forecast::ForecastArchive, weather, time, horizon) =
    ArchivedForecast(forecast, weather, time)
known_weather(forecast::ForecastEnsemble, weather, time, horizon) =
    [ArchivedForecast(member, weather, time) for member in forecast.members]

within(forecast::ArchivedForecast, group, time) =
    time - forecast.issued <= last_time(group.grid)

issue_arrays(group::ArchiveGroup, issue, names) =
    map(name -> view(group.fields[name], :, :, :, issue), names)

bias_arrays(group::ArchiveGroup, year, names) = map(name -> group.bias[year][name], names)

function wind(forecast::ArchivedForecast, lat, lon, time)
    group = forecast.archive.wind
    within(forecast, group, time) || return wind(forecast.beyond, lat, lon, time)
    names = ("u10", "v10")
    east, north, east_bias, north_bias = sample(group.grid,
        (issue_arrays(group, forecast.issue, names)...,
            bias_arrays(group, forecast.year, names)...), lat, lon, time - forecast.issued)
    return east - east_bias, north - north_bias
end

function waves(forecast::ArchivedForecast, lat, lon, time)
    group = forecast.archive.waves
    within(forecast, group, time) || return waves(forecast.beyond, lat, lon, time)
    height, period, east, north, height_bias, period_bias = sample(group.grid,
        (issue_arrays(group, forecast.issue,
                ("height", "period", "direction_east", "direction_north"))...,
            bias_arrays(group, forecast.year, ("height", "period"))...), lat, lon,
        time - forecast.issued)
    isnan(height) && return waves(forecast.beyond, lat, lon, time)
    return max(height - height_bias, 0.0), max(period - period_bias, 0.0), atan(east, north)
end

"""
    ForecastParts(forecast, wind_band=(Inf, Inf), forecast_waves=true)

Forecast source of a ship that plans on the waves of `forecast` where `forecast_waves`,
otherwise on the real waves, and on the real wind except where the real or the forecast
wind speed at 10 m lies in `wind_band` [m/s], where it plans on the wind of `forecast`.
"""
struct ForecastParts{F}
    forecast::F
    wind_band::NTuple{2, Float64}
    forecast_waves::Bool
end
ForecastParts(forecast, wind_band=(Inf, Inf)) = ForecastParts(forecast, wind_band, true)

"What a [`ForecastParts`](@ref) ship knows: `wind_band` splits `known` from the `truth`."
struct PartlyKnownWeather{K, W}
    known::K
    truth::W
    wind_band::NTuple{2, Float64}
    forecast_waves::Bool
end

known_weather(parts::ForecastParts, weather, time, horizon) = PartlyKnownWeather(
    known_weather(parts.forecast, weather, time, horizon), weather, parts.wind_band,
    parts.forecast_waves)

function wind(partly::PartlyKnownWeather, lat, lon, time)
    real_wind = wind(partly.truth, lat, lon, time)
    forecast_wind = wind(partly.known, lat, lon, time)
    low, high = partly.wind_band
    in_band(vector) = low <= hypot(vector...) <= high
    return in_band(real_wind) || in_band(forecast_wind) ? forecast_wind : real_wind
end

waves(partly::PartlyKnownWeather, lat, lon, time) =
    waves(partly.forecast_waves ? partly.known : partly.truth, lat, lon, time)

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
    write_forecast_bias(directory, weather)

Write [`forecast_bias`](@ref) of the wind and the wave height and period of the forecast
archive in `directory` against `weather` to a `bias_<year>` folder per year scored.
"""
function write_forecast_bias(directory::AbstractString, weather::ERA5Weather)
    archive = ForecastArchive(directory, weather)
    issues = 1:min(issue_count(archive.wind), issue_count(archive.waves))
    issue_times = issue_time.(Ref(archive), issues)
    years = issue_year.(Ref(archive), issues)
    for (name, group, observed, names) in (
        ("wind", archive.wind, weather.wind, ("u10", "v10")),
        ("waves", archive.waves, weather.waves, ("height", "period")))
        for (year, fields) in forecast_bias(group, observed, issue_times, years, names)
            folder = mkpath(joinpath(directory, name, "bias_$year"))
            for (variable, bias) in fields
                write(joinpath(folder, "$variable.f32"), bias)
            end
        end
    end
end
