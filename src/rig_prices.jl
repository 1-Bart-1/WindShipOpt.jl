# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""
    RigPrice

A price paid, quoted or estimated for one unit of a rig, a row of `data/rig_prices.csv`.
"""
struct RigPrice
    "kind of rig: `:kite`, `:wing` or `:rotor`"
    rig::Symbol
    "`:paid`, `:quoted` or `:estimate`"
    kind::Symbol
    year::Int
    "units of the rig's kind built by that year"
    units_built::Float64
    "rotor height [m]"
    height::Float64
    "rotor diameter [m]"
    diameter::Float64
    "wing or kite area [m^2]"
    area::Float64
    "price in `currency`"
    price::Float64
    currency::String
    "whether the price includes installation on the ship"
    installed::Bool
    "consumer price index of `year`, as `hicp_today`"
    hicp::Float64
    source::String
end

const RIG_PRICES_FILE = joinpath(pkgdir(@__MODULE__), "data", "rig_prices.csv")
include_dependency(RIG_PRICES_FILE)

"""
    rig_prices()

Every [`RigPrice`](@ref) of `data/rig_prices.csv`.
"""
function rig_prices()
    lines = readlines(RIG_PRICES_FILE)
    header = csv_fields(first(lines))
    number(text) = isempty(text) ? NaN : parse(Float64, text)
    return map(lines[2:end]) do line
        row = Dict(zip(header, csv_fields(line)))
        RigPrice(Symbol(row["rig"]), Symbol(row["kind"]), parse(Int, row["year"]),
            number(row["units_built"]), number(row["height"]), number(row["diameter"]),
            number(row["area"]), number(row["price"]), row["currency"],
            row["installed"] == "true", number(row["hicp"]), row["source"])
    end
end

const RIG_PRICES = rig_prices()

"""
    today_price(price, assumptions)

`price` [USD] in today's money: converted from euros and raised by the price index.
"""
function today_price(price::RigPrice, assumptions)
    rate = price.currency == "EUR" ? assumptions[:usd_per_eur] : 1.0
    return rate * price.price * assumptions[:hicp_today] / price.hicp
end

"""
    bottom_up_price(price, assumptions)

Bottom-up price [USD] of the unit `price` is for: its manufacturing cost times the market
price factor, with installation where `price` includes it; a kite's with its canopy.
"""
function bottom_up_price(price::RigPrice, assumptions)
    if price.rig == :kite
        max_force = 1e3assumptions[:kite_max_force_per_area] * price.area
        cost = sum(kite_price_parts(price.area, max_force, assumptions)) +
               Canopy(assumptions).cost_per_area * price.area
        return assumptions[:market_price_factor] * cost
    end
    parts = price.rig == :rotor ?
        deck_price_parts(1, price.height * price.diameter, assumptions, :rotor_unit_cost,
            :rotor_cost_per_area, :rotor_installation_fraction) :
        deck_price_parts(1, price.area, assumptions, :wing_unit_cost, :wing_cost_per_area,
            :wing_installation_fraction)
    cost = parts.units + parts.surface + (price.installed ? parts.installation : 0.0)
    return assumptions[:market_price_factor] * cost
end

"""
    stage_units(rig, assumptions)

Units of the kind `rig` built once `stage_ships` ships carry it.
"""
stage_units(rig::Symbol, assumptions) =
    assumptions[:stage_ships] * assumptions[Symbol(rig, :s_per_ship)]

"""
    stage_ratio(price, assumptions)

`price` in today's money moved along the learning curve to the units built at the
production stage, over the bottom-up price of the same unit.
"""
function stage_ratio(price::RigPrice, assumptions)
    exponent = log(1 - assumptions[:learning_rate]) / log(2)
    learning = (stage_units(price.rig, assumptions) / price.units_built)^exponent
    return learning * today_price(price, assumptions) / bottom_up_price(price, assumptions)
end

"""
    stage_price_factor(rig, assumptions)

Price of a rig of kind `rig` (`:kite`, `:wing` or `:rotor`) at the production stage over its
bottom-up price: the geometric mean of the [`stage_ratio`](@ref)s of its real prices, and at
least one, since below its bottom-up price a maker cannot build it. At a `learning_rate` of
zero it is the price as paid today.
"""
function stage_price_factor(rig::Symbol, assumptions)
    ratios = [log(stage_ratio(price, assumptions))
              for price in RIG_PRICES if price.rig == rig]
    return max(1.0, exp(mean(ratios)))
end

"""
    price_factor(rig, assumptions)

Price of a rig of kind `rig` over its manufacturing cost: the market price factor times the
[`stage_price_factor`](@ref).
"""
price_factor(rig::Symbol, assumptions) =
    assumptions[:market_price_factor] * stage_price_factor(rig, assumptions)

"""
    as_paid(assumptions)

Fresh `Assumptions` at a learning rate of zero, which price every rig as paid today.
"""
as_paid(assumptions) = with_value(assumptions, :learning_rate, 0.0)
