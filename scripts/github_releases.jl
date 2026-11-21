# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# The releases on GitHub that keep the paper runs (run_releases.jl), written through the
# GitHub CLI where it is installed, else through curl with the token in GITHUB_TOKEN, and
# read from their public address. Included by paper.jl and cluster.jl.
using Downloads
using JSON

"repository whose releases keep the paper runs"
RESULTS_REPOSITORY = "1-Bart-1/WindShipOpt.jl"

"releases of `repository` written through the GitHub CLI, `gh`, as it is signed in"
struct GhReleases
    repository::String
end

"releases of `repository` written through curl with the token in GITHUB_TOKEN"
struct CurlReleases
    repository::String
end

"""
    default_releases()

The releases of [`RESULTS_REPOSITORY`](@ref) through `gh` where it is installed, else
through curl.
"""
default_releases() = isnothing(Sys.which("gh")) ? CurlReleases(RESULTS_REPOSITORY) :
                     GhReleases(RESULTS_REPOSITORY)

function replace_asset(releases::Union{GhReleases, CurlReleases}, tag, commit, name, path)
    release = github_api(releases, "GET", "releases/tags/$tag")
    if isnothing(release)
        release = github_api(releases, "POST", "releases"; body=Dict("tag_name" => tag,
            "target_commitish" => commit, "name" => "Paper runs at $(first(commit, 7))",
            "body" => "The paper runs of commit $commit, one archive per fidelity. " *
                      "docs/paper_runs.md says how to fetch one and resume from it.",
            "prerelease" => true, "make_latest" => "false"))
    end
    earlier = Dict(asset["name"] => asset["id"] for asset in release["assets"])
    part = name * ".part"
    haskey(earlier, part) && delete_asset(releases, earlier[part])
    uploaded = upload_file(releases, release, path, part)
    haskey(earlier, name) && delete_asset(releases, earlier[name])
    github_api(releases, "PATCH", "releases/assets/$uploaded"; body=Dict("name" => name))
end

"delete the asset of id `asset` from the releases of `releases`"
delete_asset(releases, asset) = github_api(releases, "DELETE", "releases/assets/$asset")

"""
    github_api(releases, method, path; body=nothing)

Answer of GitHub's REST API to `method` on `path` under the repository of `releases`, with
`body` sent as JSON: the parsed JSON, or nothing where it is empty or the API answers 404.
"""
function github_api(releases::GhReleases, method, path; body=nothing)
    output, errors = IOBuffer(), IOBuffer()
    input = isnothing(body) ? `` : `--input -`
    command = `gh api -X $method repos/$(releases.repository)/$path $input`
    stdin = IOBuffer(isnothing(body) ? "" : JSON.json(body))
    if !success(pipeline(command; stdin, stdout=output, stderr=errors))
        message = String(take!(errors))
        contains(message, "HTTP 404") && return nothing
        error("gh api $method $path: ", message)
    end
    return parsed_json(String(take!(output)))
end

function github_api(releases::CurlReleases, method, path; body=nothing)
    mktempdir() do scratch
        data = isnothing(body) ? nothing : joinpath(scratch, "body.json")
        isnothing(data) || write(data, JSON.json(body))
        return curl_json(method,
            "https://api.github.com/repos/$(releases.repository)/$path", data,
            "application/json")
    end
end

"parsed JSON of `text`, or nothing where it is empty"
parsed_json(text) = isempty(strip(text)) ? nothing : JSON.parse(text)

"""
    curl_json(method, url, data, content_type)

Parsed JSON answer of `method` on `url` with the file `data`, of `content_type`, as its
body where it is not nothing, sent by curl with the token in GITHUB_TOKEN; nothing where the
answer is empty or 404.
"""
function curl_json(method, url, data, content_type)
    token = get(ENV, "GITHUB_TOKEN", "")
    isempty(token) && error("GITHUB_TOKEN is not set; the README's section on DelftBlue ",
        "says how to set it")
    mktempdir() do scratch
        answer = joinpath(scratch, "answer")
        config = """
            header = "Authorization: Bearer $token"
            header = "Accept: application/vnd.github+json"
            header = "Content-Type: $content_type"
            """
        body = isnothing(data) ? `` : `--data-binary @$data`
        command = `curl -sS --connect-timeout 20 -X $method -o $answer -w "%{http_code}"
            -K - $body $url`
        status = parse(Int, read(pipeline(command; stdin=IOBuffer(config)), String))
        text = isfile(answer) ? read(answer, String) : ""
        status == 404 && return nothing
        status < 300 || error("GitHub answered $status to $method $url: $text")
        return parsed_json(text)
    end
end

"""
    upload_file(releases, release, path, name)

Upload the file at `path` as the asset `name` of `release`, a release as the API gives it;
return the id of the new asset.
"""
function upload_file(releases::GhReleases, release, path, name)
    mktempdir() do scratch
        named = joinpath(scratch, name)
        symlink(abspath(path), named)
        run(`gh release upload $(release["tag_name"]) $named -R $(releases.repository)`)
    end
    assets = github_api(releases, "GET", "releases/$(release["id"])")["assets"]
    return only(asset["id"] for asset in assets if asset["name"] == name)
end

function upload_file(releases::CurlReleases, release, path, name)
    url = "https://uploads.github.com/repos/$(releases.repository)/releases/" *
          "$(release["id"])/assets?name=$name"
    return curl_json("POST", url, path, "application/gzip")["id"]
end

function download_asset(releases::Union{GhReleases, CurlReleases}, tag, name, path)
    url = "https://github.com/$(releases.repository)/releases/download/$tag/$name"
    try
        Downloads.download(url, path)
        return true
    catch error
        error isa Downloads.RequestError || rethrow()
        reason = error.response.status == 0 ? error.message : error.response.message
        println("no ", name, " in release ", tag, ": ", reason)
        return false
    end
end
