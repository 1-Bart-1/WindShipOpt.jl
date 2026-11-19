# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""
    RotorPrice

A price paid or quoted for one Flettner rotor, a row of `data/rotor_prices.csv`.
"""
struct RotorPrice
    "`:paid` or `:quoted`"
    kind::Symbol
    year::Int
    "rotor height [m]"
    height::Float64
    "rotor diameter [m]"
    diameter::Float64
    "price in `currency`"
    price::Float64
    currency::String
    "whether the price includes installation on the ship"
    installed::Bool
    "whether the rotor folds or tilts"
    retractable::Bool
    "consumer price index of `year`, as `hicp_today`"
    hicp::Float64
    source::String
end

const ROTOR_PRICES_FILE = joinpath(pkgdir(@__MODULE__), "data", "rotor_prices.csv")
include_dependency(ROTOR_PRICES_FILE)

"""
    rotor_prices()

Every [`RotorPrice`](@ref) of `data/rotor_prices.csv`.
"""
function rotor_prices()
    lines = readlines(ROTOR_PRICES_FILE)
    header = csv_fields(first(lines))
    return map(lines[2:end]) do line
        row = Dict(zip(header, csv_fields(line)))
        RotorPrice(Symbol(row["kind"]), parse(Int, row["year"]),
            parse(Float64, row["height"]), parse(Float64, row["diameter"]),
            parse(Float64, row["price"]), row["currency"], row["installed"] == "true",
            row["retractable"] == "true", parse(Float64, row["hicp"]), row["source"])
    end
end

const ROTOR_PRICES = rotor_prices()

"""
    today_price(price, assumptions)

`price` [USD] in today's money: converted from euros and raised by the price index.
"""
function today_price(price::RotorPrice, assumptions)
    rate = price.currency == "EUR" ? assumptions[:usd_per_eur] : 1.0
    return rate * price.price * assumptions[:hicp_today] / price.hicp
end

"""
    bottom_up_price(price, assumptions)

Bottom-up price [USD] of the rotor `price` is for: its manufacturing cost times the market
price factor, with installation and the retractable rig premium where `price` includes them.
"""
function bottom_up_price(price::RotorPrice, assumptions)
    parts = deck_price_parts(1, price.height * price.diameter, assumptions,
        :rotor_unit_cost, :rotor_cost_per_area, :rotor_installation_fraction)
    cost = parts.units + parts.surface + (price.installed ? parts.installation : 0.0)
    premium = price.retractable ? 1 + assumptions[:retractable_rig_premium] : 1.0
    return assumptions[:market_price_factor] * premium * cost
end
