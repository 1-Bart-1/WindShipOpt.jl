# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Download the perturbed members of the GEFSv12 reforecast (10 m wind and significant wave
# height) for the issues a ship uses on the departures of the forecast study, into
# era5/atlantic_wide/forecast_members/<member>/{wind,waves}/, in the layout and with the
# bias and blend weights of the control archive, and write the ensemble mean and a margin
# for the wind that may not come beside them, with their own bias and blend weights. All
# share the control's wave period and direction. Issues outside the study stay holes in the
# files. Resumable.
ENV["ERA5_REGION"] = "atlantic_wide"
include("setup.jl")
include("download_forecast.jl")
using Statistics: mean

members = ["p01", "p02", "p03", "p04"]
members_root = joinpath(era5, "forecast_members")
"days from each departure over which a ship reads forecasts [day]"
window_days = 56

"the groups of a perturbed member: wind and significant wave height"
member_groups = (groups[1], (; groups[2]..., records=Dict("height" => "HTSGW"),
    finish=identity))

"""
    study_issues(departures)

Numbers of the issues read by ships leaving at `departures` [h] over `window_days` days.
"""
study_issues(departures) =
    sort(unique([ArchivedForecast(forecast_archive, departure + 24.0 * day).issue
                 for departure in departures, day in 0:window_days]))

"""
    link_archive(directory; calibration=true)

Make `directory` an archive with the grids and the wave period and direction of the control
archive in `output`, and its bias and blend weights where `calibration`.
"""
function link_archive(directory; calibration=true)
    for group in ("wind", "waves")
        folder = mkpath(joinpath(directory, group))
        cp(joinpath(output, group, "grid.toml"), joinpath(folder, "grid.toml"); force=true)
        WindShipOpt.link_control_group(joinpath(output, group), folder; calibration)
    end
end

"""
    write_statistics(wanted)

Write the issues numbered `wanted` of the archives `mean` and `margin`, from the control
archive and the member archives, at their places in files spanning every issue.
"""
function write_statistics(wanted)
    foreach(name -> link_archive(joinpath(members_root, name); calibration=false),
        ("mean", "margin"))
    for (group, names) in (("wind", ["u10", "v10"]), ("waves", ["height"]))
        archives = [WindShipOpt.ArchiveGroup(joinpath(output, group), weather.origin);
                    [WindShipOpt.ArchiveGroup(joinpath(members_root, member, group),
                         weather.origin) for member in members]]
        files = Dict((kind, name) => statistics_file(joinpath(members_root, kind, group),
                         name, size(archives[1].fields[name]))
                     for kind in ("mean", "margin"), name in names)
        for issue in wanted
            write_issue_statistics(files, archives, names, group, issue)
        end
        foreach(close, values(files))
        println("statistics of ", group, " written")
    end
end

function statistics_file(folder, name, shape)
    path = joinpath(folder, "$name.f16")
    isfile(path) || touch(path)
    io = open(path, "r+")
    truncate(io, max(filesize(io), 2prod(shape)))
    return io
end

function write_issue_statistics(files, archives, names, group, issue)
    fields = Dict(name => cat([Float32.(archive.fields[name][:, :, :, issue])
                               for archive in archives]...; dims=4) for name in names)
    means = Dict(name => dropdims(mean(fields[name]; dims=4); dims=4) for name in names)
    margins = copy(means)
    if group == "wind"
        margins["u10"], margins["v10"] = WindShipOpt.margin_wind(fields["u10"],
            fields["v10"])
    else
        margins["height"] = WindShipOpt.margin_height(fields["height"])
    end
    issue_bytes = 2prod(size(archives[1].fields[names[1]])[1:3])
    for (kind, statistics) in (("mean", means), ("margin", margins)), name in names
        io = files[(kind, name)]
        seek(io, (issue - 1) * issue_bytes)
        write(io, Float16.(statistics[name]))
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    wanted = study_issues(ensemble_departures)
    println(length(wanted), " issues wanted")
    for member in members
        foreach(group -> download(group; member, root=joinpath(members_root, member),
                wanted), member_groups)
        link_archive(joinpath(members_root, member))
    end
    write_statistics(wanted)
    for name in ("mean", "margin")
        write_forecast_bias(joinpath(members_root, name), weather)
        write_forecast_weights(joinpath(members_root, name), weather,
            forecast_archive.climate)
    end
    println("forecast ensemble complete")
end
