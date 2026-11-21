# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Keeps each paper run as an asset of a release of its commit, so that no run lives only on
# the machine that ran it: the runs of a commit at one fidelity, with the round trips they
# use, go into one archive that replaces the last one after each step, every KEEP_MINUTES
# while round trips compute, and at the end. A run resumes from that archive on any machine.
# Included by paper_runs.jl; github_releases.jl reaches GitHub, test/sets.jl stands in for
# it.

"minutes between uploads of the run in use while its round trips compute"
KEEP_MINUTES = 30

"largest archive a release takes [B]"
ASSET_LIMIT = 2^31

"where the run in use keeps its results, or nothing to keep them only here"
run_releases = nothing

"time the run in use was last kept, or this process started"
last_kept = Ref(now())

"lock held while the run in use is kept, so that one thread uploads at a time"
keeping = ReentrantLock()

"tag of the release keeping the runs of `commit`"
release_tag(commit) = "run-$commit"

"name of the asset holding the runs at `fidelity`"
asset_name(fidelity) = "$fidelity.tar.gz"

"""
    replace_asset(releases, tag, commit, name, path)

Upload the file at `path` as the asset `name` of the release `tag` of `releases`, made as a
prerelease of `commit` where there is none, replacing the asset of that name only once the
new one is uploaded.
"""
function replace_asset end

"""
    download_asset(releases, tag, name, path)

Download the asset `name` of the release `tag` of `releases` to `path`; whether there was
one to download, saying why where not.
"""
function download_asset end

"""
    keep_run(run; every=0)

Keep the runs at the fidelity and commit of `run` in [`run_releases`](@ref) as
[`keep_commit`](@ref) does, unless no run is open, or the last upload was less than `every`
minutes ago or another thread is uploading, where `every` is not 0.
"""
function keep_run(run; every=0)
    (isnothing(run_releases) || isnothing(run.directory)) && return
    now() - last_kept[] < Minute(every) && return
    every == 0 ? lock(keeping) : trylock(keeping) || return
    try
        last_kept[] = now()
        keep_commit(run_releases, run.fidelity, run.record["git_commit"],
            run.record["git_dirty"])
    finally
        unlock(keeping)
    end
end

"""
    keep_commit(releases, fidelity, commit, dirty)

Keep the runs at `fidelity` of `commit` in `releases` ([`keep_runs`](@ref)) where the tree
is clean (`dirty` false) and `commit` pushed; otherwise warn that they stay only here.
"""
function keep_commit(releases, fidelity, commit, dirty)
    dirty && return @warn "the $fidelity run is kept only on this machine: the tree " *
                          "differs from commit $commit" maxlog = 1
    is_pushed(commit) || return @warn "the $fidelity run is kept only on this machine " *
                                      "until commit $commit is pushed" maxlog = 1
    keep_runs(releases, fidelity, commit)
end

"""
    keep_runs(releases, fidelity, commit)

Upload the archive of the clean runs at `fidelity` of `commit` ([`write_archive`](@ref))
to `releases` as the asset of that fidelity in the release of `commit`, replacing the one
there; warn instead of failing where that cannot be done.
"""
function keep_runs(releases, fidelity, commit)
    try
        mktempdir(mkpath(dirname(runs_directory))) do scratch
            archive = joinpath(scratch, asset_name(fidelity))
            write_archive(archive, fidelity, commit, scratch)
            size = filesize(archive)
            size < ASSET_LIMIT || error("its archive of ", Base.format_bytes(size),
                " is over GitHub's limit")
            replace_asset(releases, release_tag(commit), commit, asset_name(fidelity),
                archive)
            println("  kept the $fidelity runs of ", first(commit, 7), " in release ",
                release_tag(commit), " (", Base.format_bytes(size), ")")
        end
    catch error
        @warn "the $fidelity run is kept only on this machine: " * sprint(showerror, error)
    end
end

"""
    write_archive(path, fidelity, commit, scratch)

Write to `path` a gzipped tar of the run directories at `fidelity` whose clean tree was at
`commit`, under runs/, and the case-store entries they use ([`run_entries`](@ref)), under
cases/, gathered in the directory `scratch`.
"""
function write_archive(path, fidelity, commit, scratch)
    directories = [directory for (directory, record) in fidelity_runs(fidelity)
                   if get(record, "git_commit", "") == commit &&
                      !get(record, "git_dirty", true)]
    isempty(directories) && error("no clean $fidelity run of commit $commit")
    staging = mkpath(joinpath(scratch, "staging"))
    for directory in directories, (folder, _, files) in walkdir(directory)
        for file in filter(!endswith(".tmp"), files)
            source = joinpath(folder, file)
            gather(source, joinpath(staging, "runs", relpath(source, runs_directory)))
        end
    end
    for entry in run_entries(directories)
        gather(entry, joinpath(staging, "cases", relpath(entry, cases_directory)))
    end
    run(`tar -czf $path -C $staging .`)
end

"""
    gather(source, target)

Hard-link the file `source` to `target`, or copy it where the file system cannot link.
"""
function gather(source, target)
    mkpath(dirname(target))
    try
        hardlink(source, target)
    catch
        cp(source, target)
    end
end

"""
    run_entries(directories)

Paths of the case-store entries the runs in `directories` use: in each store their case
records ([`write_cases`](@ref)) and stores in progress ([`note_stores`](@ref)) list, the
entries of the round-trip code listed with it.
"""
function run_entries(directories)
    listed = Set{Tuple{String, String}}()
    for directory in directories
        records = joinpath(directory, "cases")
        isdir(records) || continue
        for file in filter(endswith(".csv"), readdir(records; join=true))
            union!(listed, (row["store"], row["trip_model"]) for row in csv_rows(file))
        end
    end
    entries = String[]
    for (store, model) in listed
        directory = joinpath(cases_directory, store)
        isdir(directory) || continue
        append!(entries, filter(file -> startswith(basename(file), model * "-") &&
                                        endswith(file, ".bin"),
            readdir(directory; join=true)))
    end
    return entries
end

"""
    note_stores(run, directories)

Add to cases/stores.csv in the directory of `run` the case stores `directories` its round
trips are about to come from, with its round-trip code, so that an archive taken before the
step ends holds them.
"""
function note_stores(run, directories)
    isnothing(run.directory) && return
    path = joinpath(mkpath(joinpath(run.directory, "cases")), "stores.csv")
    @lock run.tally.lock open(path, "a") do io
        position(io) == 0 && println(io, "store,trip_model")
        for directory in unique(directories)
            println(io, csv_field(basename(directory)), ",", csv_field(run.trip_model))
        end
    end
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
    fetch_runs(releases, fidelity)

Bring the runs at `fidelity` kept in `releases` for the commit checked out here into this
machine's runs and case store, where they are on this branch: a run missing here, or here
with fewer steps done, is taken from the release, and every case-store entry missing here
is added. Warn instead of failing where that cannot be done.
"""
function fetch_runs(releases, fidelity)
    commit = git_output("rev-parse", "HEAD")
    try
        mktempdir(mkpath(dirname(runs_directory))) do scratch
            archive = joinpath(scratch, asset_name(fidelity))
            download_asset(releases, release_tag(commit), asset_name(fidelity), archive) ||
                return
            run(`tar -xzf $archive -C $scratch`)
            merge_runs(joinpath(scratch, "runs"), fidelity, commit,
                git_output("rev-parse", "--abbrev-ref", "HEAD"))
            merge_entries(joinpath(scratch, "cases"))
        end
    catch error
        @warn "no $fidelity run fetched from its release: " * sprint(showerror, error)
    end
end

"""
    merge_runs(fetched, fidelity, commit, branch)

Move each run directory in `fetched` at `fidelity` of `commit` on `branch` into the runs
directory where it has no run of that name, or one with fewer steps done.
"""
function merge_runs(fetched, fidelity, commit, branch)
    isdir(fetched) || return
    mkpath(runs_directory)
    for name in readdir(fetched)
        record = TOML.parsefile(joinpath(fetched, name, "run.toml"))
        (record["fidelity"], record["git_commit"], record["git_branch"]) ==
        (string(fidelity), commit, branch) || continue
        here = joinpath(runs_directory, name)
        record_here = joinpath(here, "run.toml")
        isfile(record_here) &&
            length(TOML.parsefile(record_here)["steps"]) >= length(record["steps"]) &&
            continue
        mv(joinpath(fetched, name), here; force=true)
        println("fetched run ", name, " from release ", release_tag(commit))
    end
end

"""
    merge_entries(fetched)

Move into the case store each entry of the case stores in `fetched` that it lacks.
"""
function merge_entries(fetched)
    isdir(fetched) || return
    for store in readdir(fetched), file in readdir(joinpath(fetched, store))
        endswith(file, ".bin") || continue
        here = joinpath(cases_directory, store, file)
        isfile(here) && continue
        mkpath(dirname(here))
        mv(joinpath(fetched, store, file), here)
    end
end
