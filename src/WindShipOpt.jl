# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""
    WindShipOpt

Design optimisation of wind-assisted merchant ships (wings, rotors or a towing kite, on
VLSFO, e-methanol or e-ammonia), with weather routing on long ocean routes.
"""
module WindShipOpt

using Base.ScopedValues: ScopedValue, with
using Random: Random
using Statistics: mean
using Dates: DateTime, Dates
using Mmap: Mmap
using Optim: Optim
using TOML: TOML
using YAML: YAML

export Assumption, Assumptions, with_value, inputs_read
export Environment, Hull, WaveCoefficients, resistance, wetted_surface, form_factor
export SeakeepingHull, added_resistance, added_resistance_coefficient, jonswap
export WingRig, KiteRig, RigForce, rig_force, apparent_wind
export Propeller, Powertrain, delivered_power
export ShipDesign, Ship, Fuel, fuel_power
export PerformanceTable, RouteTable, lookup
export LandMask, GridMask, north_atlantic_mask, SyntheticWeather, ERA5Weather, wind, waves
export Corridor, return_corridor, route_corridors, centre_index, Leg, route
export RefinedCorridor, track_length
export ForecastWeather, forecast_route, ShipClass, ship_classes
export ShipCosts, RoundTrip, round_trip, KNOT, NAUTICAL_MILE
export LegTrace

include("recording.jl")
include("assumptions.jl")
include("hull.jl")
include("waves.jl")
include("pattern.jl")
include("canopy.jl")
include("rig.jl")
include("propulsion.jl")
include("windage.jl")
include("ship.jl")
include("performance.jl")
include("geography.jl")
include("weather.jl")
include("era5.jl")
include("routing.jl")
include("economics.jl")
include("analysis.jl")

end
