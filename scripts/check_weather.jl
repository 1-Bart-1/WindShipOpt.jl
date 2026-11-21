# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Check the weather a draft and a final run read, era5/atlantic_wide/{wind, aloft, waves,
# climate, forecast}/, against data/weather_sha256.toml, the hashes of the files the
# project's server ran on: prints each file that is missing or differs and exits 1 if any
# does. With --write, writes that list from the files present instead.
using SHA
using TOML

era5 = joinpath(@__DIR__, "..", "era5", "atlantic_wide")
manifest = joinpath(@__DIR__, "..", "data", "weather_sha256.toml")
folders = ("wind", "aloft", "waves", "climate", "forecast")

"""
    weather_hash(file)

SHA-256 of `file`, relative to `era5`, as hexadecimal, or "missing" where it does not
exist; of a TOML file, that of its contents printed with sorted keys.
"""
function weather_hash(file)
    path = joinpath(era5, file)
    isfile(path) || return "missing"
    endswith(path, ".toml") || return bytes2hex(open(sha256, path))
    contents = TOML.parsefile(path)
    return bytes2hex(sha256(sprint(io -> TOML.print(io, contents; sorted=true))))
end

"files of the weather a run reads, relative to `era5`, without the downloads' `done` lists"
weather_files() = sort([relpath(joinpath(root, file), era5) for folder in folders
                        for (root, _, files) in walkdir(joinpath(era5, folder))
                        for file in files if file != "done"])

"[`weather_hash`](@ref) of each of `files` by file, computed on all threads"
hashes(files) =
    Dict(zip(files, fetch.([Threads.@spawn weather_hash(file) for file in files])))

if ARGS == ["--write"]
    open(io -> TOML.print(io, hashes(weather_files()); sorted=true), manifest, "w")
    println("wrote ", manifest)
else
    expected = TOML.parsefile(manifest)
    found = hashes(collect(keys(expected)))
    wrong = sort([file for (file, hash) in expected if found[file] != hash])
    for file in wrong
        println(found[file] == "missing" ? "missing: " : "differs: ", file)
    end
    isempty(wrong) || exit(1)
    println("weather matches the server's, all ", length(expected), " files")
end
