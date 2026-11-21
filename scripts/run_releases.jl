# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Keeps paper runs as assets of GitHub releases, so that no run lives only on the machine
# that ran it. Each commit has one release, tagged run-<commit>, with at most one run per
# fidelity: an archive of the run's directory and the round trips it uses, labelled with
# the run's name and steps done. A run is copied with rsync from a checkout, here or on a
# cluster, and back. Included by runs.jl after paper_runs.jl; github_releases.jl reaches
# GitHub, and test/sets.jl stands in for it.

"largest archive a release takes [B]"
ASSET_LIMIT = 2^31

"tag of the release keeping the runs of `commit`"
release_tag(commit) = "run-$commit"

"name of the asset holding the run at `fidelity`"
asset_name(fidelity) = "$fidelity.tar.gz"

"label of the asset holding run `name` of record `record`: its name and steps done"
run_label(name, record) = "run $name, $(length(record["steps"])) steps"

"""
    labelled_run(label)

Name and steps done of the run an asset labelled `label` ([`run_label`](@ref)) holds.
"""
function labelled_run(label)
    found = match(r"^run (\S+), (\d+) steps$", label)
    isnothing(found) && error("no run in the asset label \"$label\"")
    return found[1], parse(Int, found[2])
end

"""
    RunAsset

An asset of a release keeping a run.
"""
struct RunAsset
    "tag of its release"
    tag::String
    "file name, [`asset_name`](@ref)"
    name::String
    "label, [`run_label`](@ref)"
    label::String
end

"""
    run_assets(releases)

Every [`RunAsset`](@ref) of the releases of `releases` that keep runs.
"""
function run_assets end

"""
    replace_asset(releases, tag, commit, name, label, path)

Upload the file at `path` as the asset `name` labelled `label` of the release `tag` of
`releases`, made as a prerelease of `commit` where there is none, replacing the asset of
that name only once the new one is uploaded.
"""
function replace_asset end

"""
    download_asset(releases, tag, name, path)

Download the asset `name` of the release `tag` of `releases` to `path`.
"""
function download_asset end

"""
    push_run(releases, name, checkout=root)

Copy run `name` and the round trips it uses from the repository `checkout`, a path here or
`user@host:path`, and upload them as the asset of its fidelity in the release of its
commit, unless that holds another run with at least as many steps done.
"""
function push_run(releases, name, checkout=root)
    mktempdir() do scratch
        copy_run(checkout, name, scratch)
        record = TOML.parsefile(joinpath(scratch, "runs", name, "run.toml"))
        tag, asset = release_tag(record["git_commit"]), asset_name(record["fidelity"])
        for kept in run_assets(releases)
            (kept.tag, kept.name) == (tag, asset) || continue
            other, steps = labelled_run(kept.label)
            other != name && steps >= length(record["steps"]) &&
                error("release $tag keeps run $other with $steps steps at ",
                    record["fidelity"], " fidelity; run $name has no more")
        end
        archive = joinpath(scratch, asset)
        run(`tar -czf $archive -C $scratch runs cases`)
        size = filesize(archive)
        size < ASSET_LIMIT || error("the archive of run $name, ",
            Base.format_bytes(size), ", is over GitHub's limit")
        replace_asset(releases, tag, record["git_commit"], asset, run_label(name, record),
            archive)
        println("pushed run ", name, " (", Base.format_bytes(size), ") to release ", tag)
    end
end

"""
    copy_run(checkout, name, scratch)

Copy with rsync run `name` of the repository `checkout` to runs/ in the directory
`scratch`, and the case-store entries it uses ([`run_entries`](@ref)) to cases/.
"""
function copy_run(checkout, name, scratch)
    occursin(r"^[\w.-]+$", name) || throw(ArgumentError("no run named $name"))
    run(`rsync -a $checkout/output/runs/$name $(mkpath(joinpath(scratch, "runs")))`)
    entries = run_entries(joinpath(scratch, "runs", name))
    cases = mkpath(joinpath(scratch, "cases"))
    isempty(entries) && return
    filters = joinpath(scratch, "entries.txt")
    open(filters, "w") do io
        for (store, model) in entries
            println(io, "+ /$store/\n+ /$store/$model-*.bin")
        end
        println(io, "- *")
    end
    run(`rsync -a --filter=". $filters" $checkout/output/cases/ $cases`)
end

"""
    run_entries(directory)

Case stores the run in `directory` uses, each with the round-trip code of the entries it
takes, as its case records ([`write_cases`](@ref)) and stores in progress
([`note_stores`](@ref)) list them.
"""
function run_entries(directory)
    records = joinpath(directory, "cases")
    isdir(records) || return Set{Tuple{String, String}}()
    return Set((row["store"], row["trip_model"])
               for file in readdir(records; join=true) if endswith(file, ".csv")
               for row in csv_rows(file))
end

"""
    csv_rows(path)

Rows of the CSV file at `path` whose fields [`csv_field`](@ref) wrote, each a dictionary
from the names of its header to its fields.
"""
function csv_rows(path)
    header, lines... = readlines(path)
    return [Dict(zip(split(header, ','), quoted_fields(line))) for line in lines]
end

"""
    quoted_fields(line)

The fields of a CSV line whose fields [`csv_field`](@ref) wrote.
"""
quoted_fields(line) = [replace(field.captures[1], "\"\"" => "\"")
                       for field in eachmatch(r"\"((?:[^\"]|\"\")*)\"", line)]

"""
    pull_runs(releases, wanted, checkout=root)

Download the runs kept in `releases` whose name is `wanted`, or whose commit starts with
it, into the repository `checkout`, a path here or `user@host:path` ([`place_run`]
(@ref)).
"""
function pull_runs(releases, wanted, checkout=root)
    assets = filter(run_assets(releases)) do asset
        endswith(asset.name, ".tar.gz") &&
            (first(labelled_run(asset.label)) == wanted ||
             startswith(asset.tag, release_tag(wanted)))
    end
    isempty(assets) && error("no release keeps a run named $wanted or of commit $wanted")
    for asset in assets
        mktempdir() do scratch
            archive = joinpath(scratch, asset.name)
            download_asset(releases, asset.tag, asset.name, archive)
            run(`tar -xzf $archive -C $scratch`)
            place_run(scratch, labelled_run(asset.label)..., checkout)
        end
    end
end

"""
    place_run(scratch, name, steps, checkout)

Copy run `name`, with `steps` steps done, from runs/ in `scratch` into the repository
`checkout` where it has no such run or one with fewer steps done, and add to its case store
the entries in cases/ that it lacks.
"""
function place_run(scratch, name, steps, checkout)
    there = mkpath(joinpath(scratch, "there"))
    record = `rsync -a $checkout/output/runs/$name/run.toml $there`
    if success(pipeline(record; stderr=devnull)) &&
       length(TOML.parsefile(joinpath(there, "run.toml"))["steps"]) >= steps
        println("run ", name, " is there with as many steps done; left as it is")
    else
        run(`rsync -a -R --delete $scratch/./runs/$name/ $checkout/output`)
        println("pulled run ", name, " into ", checkout)
    end
    run(`rsync -a --ignore-existing $scratch/cases $checkout/output`)
end

"""
    backfill_runs(directory=runs_directory, studies=TOML.parsefile(study_runs_path))

The runs in `directory` worth keeping, and those skipped, each with why: of the runs at one
commit and fidelity the one named in `studies`, else the one with most steps done; a
method study's run that `studies` does not name is skipped.
"""
function backfill_runs(directory=runs_directory, studies=TOML.parsefile(study_runs_path))
    named = Set(study["run"] for study in values(studies))
    candidates = Dict{Tuple{String, String}, Vector{Tuple{Bool, Int, String}}}()
    skipped = Pair{String, String}[]
    for name in readdir(directory)
        path = joinpath(directory, name, "run.toml")
        isfile(path) || continue
        record = TOML.parsefile(path)
        study = any(step -> endswith(step["name"], "_record"), record["steps"])
        if study && !(name in named)
            push!(skipped, name => "a method study's run the paper does not read")
        elseif !haskey(record, "git_commit")
            push!(skipped, name => "its record names no commit")
        else
            runs = get!(candidates, (record["git_commit"], record["fidelity"]), [])
            push!(runs, (name in named, length(record["steps"]), name))
        end
    end
    kept = String[]
    for ((commit, fidelity), runs) in candidates
        sort!(runs; rev=true)
        push!(kept, last(first(runs)))
        for (_, _, name) in runs[2:end]
            push!(skipped, name => "run $(last(first(runs))) is kept for its $fidelity " *
                                   "at $(first(commit, 7))")
        end
    end
    return sort(kept), sort(skipped)
end
