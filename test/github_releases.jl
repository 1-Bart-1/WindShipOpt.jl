# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# The real GitHub behind the releases that keep the paper runs, which test/sets.jl stands in
# for. It pushes a made-up run of the checked-out commit, which must be pushed and have no
# release of its own yet, pulls it into another checkout and deletes the release after. It
# needs gh signed in with write access to the repository, so it is never part of CI. Run by
# hand from the repository:
#
#     julia --project=scripts test/github_releases.jl
using Test

module RealReleases
root = normpath(joinpath(@__DIR__, ".."))
include(joinpath(root, "scripts", "paper_runs.jl"))
include(joinpath(root, "scripts", "run_releases.jl"))
include(joinpath(root, "scripts", "github_releases.jl"))
end

releases = RealReleases.paper_releases
commit = RealReleases.git_output("rev-parse", "HEAD")
tag = RealReleases.release_tag(commit)
isnothing(RealReleases.gh_api(releases, "releases/tags/$tag"; jq=".id")) ||
    error("commit $commit has a release of its own; check out one without")

@testset "a run pushed to a real release pulls back whole, its archive replaced" begin
    sent, received = mktempdir(), mktempdir()
    directory = mkpath(joinpath(sent, "output", "runs", "2000-01-01T0000"))
    try
        for steps in 1:2
            record = Dict("fidelity" => "draft", "finished" => "", "git_commit" => commit,
                "steps" => [Dict("name" => "step $k") for k in 1:steps])
            open(io -> RealReleases.TOML.print(io, record), joinpath(directory, "run.toml"),
                "w")
            RealReleases.push_run(releases, "2000-01-01T0000", sent)
        end
        assets = filter(asset -> asset.tag == tag, RealReleases.run_assets(releases))
        @test [(asset.name, asset.label) for asset in assets] ==
              [("draft.tar.gz", "run 2000-01-01T0000, 2 steps")]
        RealReleases.pull_runs(releases, "2000-01-01T0000", received)
        @test read(joinpath(received, "output", "runs", "2000-01-01T0000", "run.toml")) ==
              read(joinpath(directory, "run.toml"))
    finally
        release = RealReleases.gh_api(releases, "releases/tags/$tag"; jq=".id")
        isnothing(release) ||
            RealReleases.gh_api(releases, "releases/$(only(release))", "-X", "DELETE")
        RealReleases.gh_api(releases, "git/refs/tags/$tag", "-X", "DELETE")
    end
end
