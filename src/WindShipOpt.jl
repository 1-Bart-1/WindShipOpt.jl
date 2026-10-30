"""
    WindShipOpt

Design optimisation of wind-assisted coasters (rigid wing or towing kite on e-methanol)
against a conventional VLSFO coaster, with weather routing on a long ocean route.
"""
module WindShipOpt

using Interpolations: Flat, Gridded, Linear, extrapolate, interpolate
using Random: Random
using Statistics: mean
using Dates: DateTime, Dates
using Mmap: Mmap
using TOML: TOML
using YAML: YAML

export Assumption, Assumptions, with_value
export Environment, Hull, WaveCoefficients, resistance, wetted_surface, form_factor
export SeakeepingHull, added_resistance, added_resistance_coefficient, jonswap
export WingRig, KiteRig, RigForce, rig_force, apparent_wind
export Propeller, Powertrain, delivered_power
export ShipDesign, Ship, Fuel, fuel_power
export PerformanceTable, lookup
export LandMask, north_atlantic_mask, SyntheticWeather, ERA5Weather, wind, waves
export Corridor, return_corridor, caribbean_corridors, centre_index, Leg, route
export ShipCosts, RoundTrip, round_trip, KNOT, NAUTICAL_MILE
export LegTrace, sailing_speed

include("assumptions.jl")
include("hull.jl")
include("waves.jl")
include("rig.jl")
include("propulsion.jl")
include("ship.jl")
include("performance.jl")
include("geography.jl")
include("weather.jl")
include("era5.jl")
include("routing.jl")
include("economics.jl")
include("analysis.jl")

end
