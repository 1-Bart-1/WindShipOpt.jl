"""
    Fuel

Fuel burned on board, with its price including any carbon charge.
"""
struct Fuel
    "price including carbon charge [USD/J]"
    price::Float64
    "lower heating value [J/kg]"
    heating_value::Float64
    "tank-to-wake CO2 [kg/J]"
    carbon_intensity::Float64
end

function vlsfo(assumptions::Assumptions)
    intensity = assumptions[:vlsfo_carbon_intensity]
    carbon_charge = assumptions[:carbon_price] * assumptions[:carbon_coverage] * intensity
    return Fuel((assumptions[:vlsfo_price] + carbon_charge) / 1e9,
        1e6assumptions[:vlsfo_heating_value], intensity * 1e3 / 1e9)
end

e_methanol(assumptions::Assumptions) = Fuel(assumptions[:e_methanol_price] / 1e9,
    1e6assumptions[:methanol_heating_value], 0.0)

"""
    hydrogen(assumptions)

Liquid green hydrogen, with the fuel-cell stack replacement that each joule burned in a
stack at its rated efficiency wears out added to its price.
"""
function hydrogen(assumptions::Assumptions)
    heating_value = 1e6assumptions[:hydrogen_heating_value]
    stack_wear = assumptions[:fuel_cell_efficiency] * assumptions[:fuel_cell_stack_share] *
                 assumptions[:fuel_cell_system_cost] / assumptions[:fuel_cell_stack_life] /
                 3.6e6
    return Fuel(assumptions[:hydrogen_price] / heating_value + stack_wear,
        heating_value, 0.0)
end

"""
    FuelStore

Tank system of a fuel per kilogram of fuel it holds.
"""
Base.@kwdef struct FuelStore
    "tank system mass with its fuel per kilogram of fuel [-]"
    mass_ratio::Float64 = 1.0
    "space the tank system takes from the holds per kilogram of fuel [m^3/kg]"
    volume::Float64 = 0.0
    "price of the tank system per kilogram of fuel it holds [USD/kg]"
    price::Float64 = 0.0
end

"""
    Drive

Power source, fuel and fuel store of a drive: `:vlsfo` for a mechanical diesel on VLSFO,
`:methanol` for diesel-electric gensets on e-methanol, `:hydrogen` for PEM fuel cells on
liquid hydrogen with an electric motor. Tanks of liquid fuels sit in the hull and take
no cargo space.
"""
Base.@kwdef struct Drive
    fuel::Fuel
    "efficiency from unit output to propeller shaft [-]"
    transmission_efficiency::Float64
    "number of identical engines, gensets or fuel-cell strings"
    unit_count::Int
    "peak fuel-to-output efficiency of one unit [-]"
    peak_efficiency::Float64
    "efficiency loss coefficient at part load [-]"
    part_load_penalty::Float64
    "lowest load a running unit holds [-]"
    min_load::Float64 = 0.0
    "price of the power source and its transmission [USD/kW]"
    power_cost::Float64
    store::FuelStore = FuelStore()
end

Drive(name::Symbol, assumptions::Assumptions) = Drive(Val(name), assumptions)

Drive(::Val{:vlsfo}, assumptions) = Drive(; fuel=vlsfo(assumptions),
    transmission_efficiency=assumptions[:shaft_efficiency],
    unit_count=1, peak_efficiency=assumptions[:vlsfo_engine_efficiency],
    part_load_penalty=assumptions[:part_load_penalty],
    power_cost=assumptions[:mechanical_propulsion_cost])

Drive(::Val{:methanol}, assumptions) = Drive(; fuel=e_methanol(assumptions),
    transmission_efficiency=assumptions[:electric_chain_efficiency],
    unit_count=round(Int, assumptions[:genset_count]),
    peak_efficiency=assumptions[:methanol_engine_efficiency],
    part_load_penalty=assumptions[:part_load_penalty],
    power_cost=assumptions[:electric_propulsion_cost])

function Drive(::Val{:hydrogen}, assumptions)
    store = FuelStore(; mass_ratio=1 / assumptions[:lh2_tank_gravimetric_density],
        volume=1 / assumptions[:lh2_tank_volumetric_density],
        price=assumptions[:lh2_tank_cost])
    return Drive(; fuel=hydrogen(assumptions),
        transmission_efficiency=assumptions[:fuel_cell_chain_efficiency],
        unit_count=round(Int, assumptions[:fuel_cell_string_count]),
        peak_efficiency=assumptions[:fuel_cell_efficiency],
        part_load_penalty=assumptions[:fuel_cell_part_load_penalty],
        min_load=assumptions[:fuel_cell_min_load],
        power_cost=assumptions[:fuel_cell_system_cost] + assumptions[:electric_drive_cost],
        store)
end

"""
    ShipClass

A standard merchant ship size class with its kind, main dimensions, deadweight, service
speed and engine power, newbuild price, the value of its cargo, its capacity in cargo
units and its container tiers on deck.
"""
Base.@kwdef struct ShipClass
    name::String
    "kind of ship: general cargo, container, bulk carrier, tanker or vehicle carrier"
    type::String
    "waterline length [m]"
    length::Float64
    "moulded breadth [m]"
    beam::Float64
    "design draught, at which the source rates speed and power [m]"
    draft::Float64
    "block coefficient at the design draught [-]"
    block_coefficient::Float64
    "deadweight at the scantling draught [t]"
    deadweight::Float64
    "service speed of the source design [kn]"
    service_speed::Float64
    "rated power of the source design's main engine [kW]"
    power::Float64
    "fraction of `power` at which the source design makes `service_speed` at the design
    draught with its sea margin, NaN where its power is no design point [-]"
    source_load::Float64
    "longitudinal centre of buoyancy forward of midships [% of length]"
    centre_of_buoyancy::Float64
    "propeller diameter over design draught [-]"
    propeller_diameter_ratio::Float64
    "newbuild price [USD]"
    newbuild_price::Float64
    "value of the cargo [USD/t]"
    cargo_value::Float64
    "unit the cargo is counted in: `:teu`, `:ceu`, or `:tonne` for ships that fill
    their deadweight"
    cargo_unit::Symbol
    "slots or deck space in `cargo_unit`, Inf for ships that fill their deadweight"
    unit_capacity::Float64
    "container tiers on deck, zero for ships without deck cargo"
    deck_tiers::Float64
    "lowest bridge or canal clearance on common calls of the class [m]"
    air_draft_limit::Float64
    "share of port calls lost to a fixed rig above `air_draft_limit` [-]"
    restricted_call_share::Float64
    "extra time per port call that a fixed deck rig costs cargo handling, Inf where it
    prevents it [h]"
    fixed_rig_port_hours::Float64
end

"""
    csv_fields(line)

Fields of one CSV `line`, with commas inside double quotes kept and the quotes removed.
"""
csv_fields(line) = [strip(field, '"') for field in
                    eachmatch(r"(\"[^\"]*\"|[^,]*)(,|$)", line) .|> first][1:(end - 1)]

"""
    ship_classes()

Standard ship classes by name, from `data/ship_classes.csv` with one class per row.
"""
function ship_classes()
    lines = readlines(joinpath(pkgdir(@__MODULE__), "data", "ship_classes.csv"))
    header = csv_fields(first(lines))
    classes = Dict{String, ShipClass}()
    for line in lines[2:end]
        row = Dict(zip(header, csv_fields(line)))
        values = Dict(Symbol(name) => parse(Float64, row[name]) for name in ("length",
            "beam", "draft", "block_coefficient", "deadweight", "service_speed",
            "power", "source_load", "centre_of_buoyancy", "propeller_diameter_ratio",
            "newbuild_price", "cargo_value", "deck_tiers", "air_draft_limit",
            "restricted_call_share", "fixed_rig_port_hours", "unit_capacity"))
        classes[row["name"]] = ShipClass(; name=row["name"], type=row["type"],
            cargo_unit=Symbol(lowercase(row["cargo_unit"])), values...)
    end
    return classes
end

"""
    Hull(class, assumptions)

Hull of the main dimensions and centre of buoyancy of ship `class`, its calm-water
resistance calibrated to the source design by [`resistance_calibration`](@ref).
"""
function Hull(class::ShipClass, assumptions::Assumptions)
    dimensions = (class.length, class.beam, class.draft, class.block_coefficient)
    holtrop = Hull(dimensions..., assumptions; class.centre_of_buoyancy)
    return Hull(dimensions..., assumptions; class.centre_of_buoyancy,
        resistance_factor=resistance_calibration(class, holtrop, assumptions))
end

"""
    resistance_calibration(class, hull, assumptions)

Factor on the uncalibrated calm-water resistance of `hull` of ship `class` that makes the
power delivered to its propeller at the service speed that of the source design: its
`source_load` of the engine power through the shaft without the source sea margin; 1
where the class has no source design point.
"""
function resistance_calibration(class::ShipClass, hull::Hull, assumptions::Assumptions)
    isnan(class.source_load) && return 1.0
    env = Environment(assumptions)
    speed = class.service_speed * KNOT
    delivered = 1e3class.power * class.source_load * assumptions[:shaft_efficiency] /
                (1 + assumptions[:source_sea_margin])
    propeller = Propeller(hull, class.propeller_diameter_ratio, assumptions)
    return delivered_thrust(propeller, env, speed, delivered) / resistance(hull, env, speed)
end

"""
    ShipDesign(drive, length; wing_area=0, kite_area=0, kite_aspect_ratio=3, rotor_area=0)
    ShipDesign(drive, class::ShipClass; kwargs...)

Design point of the optimization. `drive` names a [`Drive`](@ref): `:vlsfo`, `:methanol`
or `:hydrogen`. A positive `wing_area` adds rigid wings of that total area [m^2], a
positive `kite_area` a towing kite of that projected area and projected
`kite_aspect_ratio`, a positive `rigid_kite_area` rigid VTOL kites of about that total
area, a positive `rotor_area` Flettner rotors of that total height times diameter. A kite
may fly over wings or rotors as a [`CombinedRig`](@ref); wings and
rotors exclude each other. With a `class` the hull, engine power, price and cargo value
are those of the class, otherwise the reference coaster is scaled to `length`.
"""
Base.@kwdef struct ShipDesign
    drive::Symbol
    "waterline length [m]"
    length::Float64
    wing_area::Float64 = 0.0
    kite_area::Float64 = 0.0
    kite_aspect_ratio::Float64 = 3.0
    rotor_area::Float64 = 0.0
    rigid_kite_area::Float64 = 0.0
    class::Union{Nothing, ShipClass} = nothing
end

ShipDesign(drive::Symbol, length::Real; kwargs...) = ShipDesign(; drive, length, kwargs...)
ShipDesign(drive::Symbol, class::ShipClass; kwargs...) =
    ShipDesign(; drive, length=class.length, class, kwargs...)

"""
    Windage(class, assumptions)

[`Windage`](@ref) of a ship of `class` with its deck cargo.
"""
Windage(class::ShipClass, assumptions::Assumptions) =
    Windage(class.type, class.length, class.beam, class.deck_tiers, assumptions)

"""
    Windage(design, hull, assumptions)

[`Windage`](@ref) of the class of `design`, or of a general cargo ship the size of `hull`.
"""
Windage(design::ShipDesign, hull::Hull, assumptions::Assumptions) =
    isnothing(design.class) ?
    Windage("general cargo", hull.length, hull.beam, 0.0, assumptions) :
    Windage(design.class, assumptions)

"""
    Propeller(design, hull, assumptions)

Propeller behind `hull` of the diameter ratio of the class of `design`, or of the
reference coaster.
"""
Propeller(design::ShipDesign, hull::Hull, assumptions::Assumptions) =
    isnothing(design.class) ? Propeller(hull, assumptions) :
    Propeller(hull, design.class.propeller_diameter_ratio, assumptions)

"""
    Ship

A design turned into the models that the performance table and the cost model use.
"""
struct Ship{R}
    design::ShipDesign
    env::Environment
    hull::Hull
    "Holtrop wave-making coefficients of the calm-water resistance"
    wave_coefficients::WaveCoefficients
    seakeeping::SeakeepingHull
    propeller::Propeller
    powertrain::Powertrain
    rig::R
    fuel::Fuel
    windage::Windage
    "righting moment per radian of heel [N m/rad]"
    righting_stiffness::Float64
    heel_limit::Float64
    leeway_limit::Float64
    "rudder area [m^2]"
    rudder_area::Float64
    "effective rudder aspect ratio including the hull mirror effect [-]"
    rudder_aspect_ratio::Float64
    "highest rudder lift coefficient used to balance the rig [-]"
    rudder_max_lift::Float64
    "highest speed through the water [m/s]"
    max_speed::Float64
end

"""
    Ship(design, assumptions)

Ship for `design`, or `nothing` if its rig does not fit on the hull. Its engines,
gensets or fuel cells are rated for the [`rated_delivered_power`](@ref) and the hotel
load.
"""
function Ship(design::ShipDesign, assumptions::Assumptions)
    env = Environment(assumptions)
    hull = isnothing(design.class) ? Hull(design.length, assumptions) :
           Hull(design.class, assumptions)
    rig = design_rig(design, hull, assumptions)
    isnothing(rig) && has_rig(design) && return nothing
    stiffness = displacement_mass(hull, env) * env.gravity *
                assumptions[:metacentric_height_ratio] * hull.beam
    drive = Drive(design.drive, assumptions)
    hotel_load = 1e3assumptions[:hotel_load]
    hull_parts = (design, env, hull, WaveCoefficients(hull),
        SeakeepingHull(hull, assumptions), Propeller(design, hull, assumptions))
    other_parts = (rig, drive.fuel, Windage(design, hull, assumptions), stiffness,
        deg2rad(assumptions[:heel_limit]), deg2rad(assumptions[:leeway_limit]),
        rudder_area(hull), assumptions[:rudder_aspect_ratio], assumptions[:rudder_max_lift],
        assumptions[:max_froude_number] * sqrt(env.gravity * hull.length))
    unlimited = Powertrain(; installed_power=Inf, unit_count=1, peak_efficiency=1.0,
        part_load_penalty=0.0, drive.transmission_efficiency, hotel_load)
    delivered = rated_delivered_power(Ship(hull_parts..., unlimited, other_parts...),
        assumptions)
    powertrain = Powertrain(;
        installed_power=delivered / drive.transmission_efficiency + hotel_load,
        drive.unit_count, drive.peak_efficiency, drive.part_load_penalty,
        drive.transmission_efficiency, hotel_load, drive.min_load)
    return Ship(hull_parts..., powertrain, other_parts...)
end

"""
    with_rig(ship, rig)

`ship` with its aerodynamics from `rig`, everything else as it was built.
"""
with_rig(ship::Ship, rig) = Ship(ship.design, ship.env, ship.hull, ship.wave_coefficients,
    ship.seakeeping, ship.propeller, ship.powertrain, rig, ship.fuel, ship.windage,
    ship.righting_stiffness, ship.heel_limit,
    ship.leeway_limit, ship.rudder_area, ship.rudder_aspect_ratio, ship.rudder_max_lift,
    ship.max_speed)

"""
    rated_delivered_power(ship, assumptions)

Power [W] delivered to the propeller at the rating of the main engine of `ship`: the
engine power of its class's source design through the shaft, or for the reference coaster
family the calm-water power at the service speed with the sea and engine margins.
"""
function rated_delivered_power(ship::Ship, assumptions::Assumptions)
    (; class) = ship.design
    isnothing(class) || return 1e3class.power * assumptions[:shaft_efficiency]
    speed = assumptions[:service_speed] * KNOT
    calm = delivered_power(ship.propeller, ship.env, speed,
        first(best_trim(ship, ship.rig, speed, 0.0, 0.0)))
    return calm * (1 + assumptions[:sea_margin]) / assumptions[:engine_rating_fraction]
end

has_rig(design::ShipDesign) =
    any(>(0), (design.wing_area, design.kite_area, design.rotor_area,
        design.rigid_kite_area))

function design_rig(design::ShipDesign, hull::Hull, assumptions::Assumptions)
    if design.rigid_kite_area > 0
        any(>(0), (design.wing_area, design.kite_area, design.rotor_area)) &&
            throw(ArgumentError("rigid kites fly alone on a design"))
        return rigid_kite_rig(design.rigid_kite_area, hull, assumptions)
    end
    design.wing_area > 0 && design.rotor_area > 0 &&
        throw(ArgumentError("a design carries wings or rotors, not both"))
    standing_type, standing_area = design.wing_area > 0 ? (WingRig, design.wing_area) :
                                   (RotorRig, design.rotor_area)
    design.kite_area > 0 && standing_area > 0 && return CombinedRig(design.kite_area,
        design.kite_aspect_ratio, standing_type, standing_area, hull, assumptions)
    design.kite_area > 0 && return KiteRig(design.kite_area, design.kite_aspect_ratio, hull,
        assumptions)
    standing_area > 0 && return standing_type(standing_area, hull, assumptions)
    return nothing
end

const KNOT = 1852 / 3600

"""
    HullBalance

Steady response of hull and rudder to a rig force: heel [rad], leeway [rad], rudder lift
coefficient [-] and the drag of leeway and rudder together [N].
"""
struct HullBalance
    heel::Float64
    leeway::Float64
    rudder_lift_coefficient::Float64
    drag::Float64
end

"""
    rudder_side_force(hull, force)

Side force [N] of the rudder at the stern of `hull` that cancels the yaw moment of the rig
`force` about the hull's lateral centre.
"""
function rudder_side_force(hull::Hull, force::RigForce)
    centre = lateral_centre(hull)
    return (force.side * centre - force.yaw_moment) / (-hull.length / 2 - centre)
end

"""
    HullBalance(ship, speed, force)

Balance of the rig `force` at `speed` [m/s]: the rudder at the stern cancels the yaw
moment about the hull's lateral centre, the hull carries the rest of the side force, and
both act at half draft for the heel.
"""
function HullBalance(ship::Ship, speed, force::RigForce)
    (; hull, env) = ship
    rudder_force = rudder_side_force(hull, force)
    leeway, induced = leeway_drag(hull, env, speed, abs(force.side + rudder_force))
    rudder_load = 0.5env.water_density * speed^2 * ship.rudder_area
    rudder_drag = rudder_force^2 / (rudder_load * π * ship.rudder_aspect_ratio)
    heel = abs(force.heeling_moment + force.side * hull.draft / 2) / ship.righting_stiffness
    return HullBalance(heel, leeway, abs(rudder_force) / rudder_load, induced + rudder_drag)
end

"""
    required_thrust(ship, speed, wind_10m, true_angle, force)

Net propeller thrust [N] the ship needs at `speed` with the rig delivering `force` and the
wind on the ship's [`Windage`](@ref) balanced together, or `Inf` if the rig pushes the
heel, leeway or rudder past its limit, or further past it than the wind on the ship
alone.
"""
function required_thrust(ship::Ship, speed, wind_10m, true_angle, force::RigForce)
    hull_force = wind_force(ship.windage, ship.env, wind_10m, true_angle, speed)
    balance = HullBalance(ship, speed, force + hull_force)
    if force != NO_RIG_FORCE
        alone = HullBalance(ship, speed, hull_force)
        balance.heel <= max(ship.heel_limit, alone.heel) &&
            balance.leeway <= max(ship.leeway_limit, alone.leeway) &&
            balance.rudder_lift_coefficient <=
            max(ship.rudder_max_lift, alone.rudder_lift_coefficient) || return Inf
    end
    return resistance(ship.hull, ship.env, speed; coefficients=ship.wave_coefficients) +
           balance.drag - force.thrust - hull_force.thrust
end

"""
    best_trim(ship, rig, speed, wind_10m, true_angle)

Required propeller thrust [N] and rig force of `ship` carrying `rig`, its own rig or a
part of it, at the trim that needs the least engine output, propeller and rig power
together.
"""
best_trim(ship::Ship, ::Nothing, speed, wind_10m, true_angle) =
    required_thrust(ship, speed, wind_10m, true_angle, NO_RIG_FORCE), NO_RIG_FORCE

function best_trim(ship::Ship, rig, speed, wind_10m, true_angle)
    best, best_output = (Inf, NO_RIG_FORCE), Inf
    for trim in trim_settings(rig)
        force = rig_force(rig, ship.env, wind_10m, true_angle, speed, trim)
        thrust = required_thrust(ship, speed, wind_10m, true_angle, force)
        isfinite(thrust) || continue
        output = delivered_power(ship.propeller, ship.env, speed, thrust) /
                 ship.powertrain.transmission_efficiency + force.power
        if output < best_output
            best, best_output = (thrust, force), output
        end
    end
    return best
end
