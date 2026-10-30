"""
    WindShipOpt

Design optimisation of wind-assisted coasters (rigid wing or towing kite on e-methanol)
against a conventional VLSFO coaster, with weather routing on a long ocean route.
"""
module WindShipOpt

using Interpolations: Flat, Gridded, Linear, extrapolate, interpolate
using Random: Random
using Statistics: mean
using YAML: YAML

export Assumption, Assumptions, with_value
export Environment, Hull, WaveCoefficients, resistance, wetted_surface, form_factor
export WingRig, KiteRig, RigForce, rig_force, apparent_wind
export Propeller, Powertrain, delivered_power
export ShipDesign, Ship, Fuel, fuel_power
export PerformanceTable, lookup
export LandMask, north_atlantic_mask, SyntheticWeather, wind
export Corridor, return_corridor, Leg, route
export ShipCosts, RoundTrip, round_trip, KNOT, NAUTICAL_MILE

include("assumptions.jl")
include("hull.jl")
include("rig.jl")
include("propulsion.jl")
include("ship.jl")
include("performance.jl")
include("geography.jl")
include("weather.jl")
include("routing.jl")
include("economics.jl")

end
