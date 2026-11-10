# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

# Point the links of the forecast member archives in era5/atlantic_wide/forecast_members at
# the control archive by relative paths, replacing what they name now. Safe to run again.
# Loads only the package, because setup.jl stops on a broken link.
using WindShipOpt

atlantic_wide = joinpath(@__DIR__, "..", "era5", "atlantic_wide")
members_root = joinpath(atlantic_wide, "forecast_members")
for member in readdir(members_root), group in ("wind", "waves")
    WindShipOpt.link_control_group(joinpath(atlantic_wide, "forecast", group),
        joinpath(members_root, member, group))
end
