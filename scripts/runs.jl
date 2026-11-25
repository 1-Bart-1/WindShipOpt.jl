# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Keeps paper runs in GitHub releases and brings them back; bin/runs calls it, from a
# laptop or the box, never from a cluster. A checkout is this repository, here by default
# or on a cluster as user@host:path.
#
#     bin/runs push <run> [<checkout>]          copy a run there, pack and upload it
#     bin/runs pull <run or commit> [<checkout>]  download a run and unpack it there
#     bin/runs backfill                        push every run here worth keeping
root = joinpath(@__DIR__, "..")
include(joinpath(@__DIR__, "paper_runs.jl"))
include(joinpath(@__DIR__, "run_releases.jl"))
include(joinpath(@__DIR__, "github_releases.jl"))

"""
    backfill(releases)

Push every run of this repository that [`backfill_runs`](@ref) keeps to `releases`, going
on past one that fails, and print those skipped and failed with why.
"""
function backfill(releases)
    kept, skipped = backfill_runs()
    for name in kept
        try
            push_run(releases, name)
        catch error
            push!(skipped, name => "push failed: " * sprint(showerror, error))
        end
    end
    for (name, why) in skipped
        println("skipped ", name, ": ", why)
    end
end

command = isempty(ARGS) ? "help" : popfirst!(ARGS)
if command == "push" && length(ARGS) in 1:2
    push_run(paper_releases, ARGS...)
elseif command == "pull" && length(ARGS) in 1:2
    pull_runs(paper_releases, ARGS...)
elseif command == "backfill" && isempty(ARGS)
    backfill(paper_releases)
else
    println("usage: bin/runs push <run> [<checkout>] | bin/runs pull <run or commit> ",
        "[<checkout>] | bin/runs backfill")
end
