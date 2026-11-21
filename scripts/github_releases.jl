# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# The releases on GitHub that keep the paper runs (run_releases.jl): written through the
# GitHub CLI as it is signed in, read from their public address. Included by runs.jl.
using Downloads

"""
    GitHubReleases

The releases of a repository on GitHub.
"""
struct GitHubReleases
    "owner/name of the repository"
    repository::String
end

"the releases of this repository, which keep its paper runs"
paper_releases = GitHubReleases("1-Bart-1/WindShipOpt.jl")

"""
    gh_api(releases, path, arguments...; jq=".")

Lines of what `jq` selects from the answer of `gh api` with `arguments` on `path` under
the repository of `releases`; nothing where the answer is 404.
"""
function gh_api(releases::GitHubReleases, path, arguments...; jq=".")
    output, errors = IOBuffer(), IOBuffer()
    command = `gh api repos/$(releases.repository)/$path $arguments --jq $jq`
    if !success(pipeline(command; stdout=output, stderr=errors))
        message = String(take!(errors))
        contains(message, "HTTP 404") && return nothing
        error("gh api $path: ", message)
    end
    return split(String(take!(output)), '\n'; keepempty=false)
end

function run_assets(releases::GitHubReleases)
    jq = """.[] | select(.tag_name | startswith("run-")) | .tag_name as \$tag |
        .assets[] | [\$tag, .name, .label] | @tsv"""
    return [RunAsset(split(line, '\t')...)
            for line in gh_api(releases, "releases", "--paginate"; jq)]
end

function replace_asset(releases::GitHubReleases, tag, commit, name, label, path)
    release = gh_api(releases, "releases/tags/$tag"; jq=".id")
    if isnothing(release)
        release = gh_api(releases, "releases", "-X", "POST", "-f", "tag_name=$tag",
            "-f", "target_commitish=$commit", "-f", "name=Paper run of $(first(commit, 7))",
            "-f", "body=docs/paper_runs.md says how to pull a run from here.",
            "-F", "prerelease=true", "-f", "make_latest=false"; jq=".id")
    end
    part = name * ".part"
    earlier = asset_ids(releases, only(release))
    haskey(earlier, part) && delete_asset(releases, earlier[part])
    mktempdir() do scratch
        upload = joinpath(scratch, part)
        symlink(abspath(path), upload)
        run(`gh release upload $tag $(upload * "#" * label) -R $(releases.repository)`)
    end
    haskey(earlier, name) && delete_asset(releases, earlier[name])
    uploaded = asset_ids(releases, only(release))[part]
    gh_api(releases, "releases/assets/$uploaded", "-X", "PATCH", "-f", "name=$name",
        "-f", "label=$label")
end

"""
    asset_ids(releases, release)

The id of each asset of the release of id `release` of `releases`, by its name.
"""
asset_ids(releases, release) = Dict(reverse.(Tuple.(split.(gh_api(releases,
    "releases/$release"; jq=".assets[] | [(.id | tostring), .name] | @tsv"), '\t'))))

"delete the asset of id `asset` from the releases of `releases`"
delete_asset(releases, asset) = gh_api(releases, "releases/assets/$asset", "-X", "DELETE")

download_asset(releases::GitHubReleases, tag, name, path) = Downloads.download(
    "https://github.com/$(releases.repository)/releases/download/$tag/$name", path)
