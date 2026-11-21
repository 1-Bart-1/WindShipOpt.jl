# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# The real GitHub behind the releases that keep the paper runs, which test/sets.jl stands in
# for. It writes a test release of the checked-out commit, which must be pushed, and deletes
# it after; it needs gh signed in or GITHUB_TOKEN set, with write access to the repository,
# so it is never part of CI. Run by hand from the repository:
#
#     julia --project=scripts test/github_releases.jl
using Test

module GitHubReleases
root = normpath(joinpath(@__DIR__, ".."))
include(joinpath(root, "scripts", "paper_runs.jl"))
include(joinpath(root, "scripts", "github_releases.jl"))
end

releases = GitHubReleases.default_releases()
if releases isa GitHubReleases.CurlReleases && !haskey(ENV, "GITHUB_TOKEN")
    @info "skipped: neither gh nor GITHUB_TOKEN to write releases with"
else
    @testset "a real release holds one asset, the one last uploaded" begin
        commit = GitHubReleases.git_output("rev-parse", "HEAD")
        tag = "run-test-$(rand(UInt32))"
        files = mktempdir()
        try
            for text in ("first", "second")
                write(joinpath(files, text), text)
                GitHubReleases.replace_asset(releases, tag, commit, "draft.tar.gz",
                    joinpath(files, text))
            end
            release = GitHubReleases.github_api(releases, "GET", "releases/tags/$tag")
            @test [asset["name"] for asset in release["assets"]] == ["draft.tar.gz"]
            @test release["prerelease"]
            fetched = joinpath(files, "fetched")
            @test GitHubReleases.download_asset(releases, tag, "draft.tar.gz", fetched)
            @test read(fetched, String) == "second"
        finally
            release = GitHubReleases.github_api(releases, "GET", "releases/tags/$tag")
            isnothing(release) ||
                GitHubReleases.github_api(releases, "DELETE", "releases/$(release["id"])")
            GitHubReleases.github_api(releases, "DELETE", "git/refs/tags/$tag")
        end
    end
end
