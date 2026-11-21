# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# What computing the paper's round trips needs and nothing that plots: the weather, the run
# record and case store, and the cases of each step. paper.jl builds on it, and a cluster
# job computing round trips loads it alone.
using Dates
using Printf
using Statistics
using WindShipOpt

include("setup.jl")

root = joinpath(@__DIR__, "..")

include("paper_runs.jl")
include("size_search.jl")
include("paper_data.jl")
