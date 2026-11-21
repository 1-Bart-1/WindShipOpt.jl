# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

using Test

# Every set reports into this one, so that a failing set does not stop the sets after it.
@testset "WindShipOpt" verbose=true begin
    include("testsets.jl")
end
