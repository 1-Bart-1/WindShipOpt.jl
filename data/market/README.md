# Seaborne cargo market map

Data to pick representative kite-assisted cargo routes from North Europe. All
tonnages are gross weight of goods; tonne-km use estimated sea distances. Built
on 2026-10-31.

## Sources

- Eurostat `mar_go_am_<cc>` (25 reporting countries: EU coastal states, NO, TR,
  ME), SDMX TSV bulk download into `raw/`. Dimensions: reporting main port ×
  partner country / maritime coastal area × direction × cargo type × flag. Code
  lists `raw/cl_*.tsv`.
- UN/LOCODE code list (GitHub mirror `datasets/un-locode`, `raw/locode/`); the
  UNECE site is behind a Cloudflare wall. 32 small ports fall back to an area
  default coordinate and about 100 are placed by hand (`scripts/locations.py`).
- IMO Fourth GHG Study 2020, Table 35 (ships, dwt, distance, CO2 per type/size
  bin) and Table 60 (EEOI, AER), year 2018 (`raw/imo/`).
- UNCTAD Review of Maritime Transport 2024 and 2025 (`raw/unctad/`).

## Method

1. `eurostat_mar_go_am_2024_2025.csv`: raw extract, all flags summed
   (`natvessr=TOTAL`), thousand tonnes. Base year is 2024, the latest with every
   country present (DK and IE have no 2025).
2. `scripts/build.py` takes the leaf partners: it drops aggregates and a country
   whenever its sub-areas are present. Leaf sums match the published totals
   within rounding in 98% of groups.
3. Partner location: the public data has no partner port. For a partner that
   reports to Eurostat, the partner is spread over its reporting ports, weighted
   by the tonnes they exchange with the reporting port's country (mirror data);
   these get a size class. For other partners, judgement-weighted representative
   ports are used (`PARTNER_REPS`); these get the class `non-reporting`.
4. Flows between two reporting countries appear at both ends, so they get weight
   0.5 (`dedup_weight`).
5. Sea distance: shortest path over a hand-built sea-lane graph
   (`scripts/seagraph.py`, 185 waypoints, with the Kiel, Suez and Panama
   canals). Each port joins the graph at its nearest waypoint. Checks against
   published distances from Rotterdam (Shanghai, Houston, New York, Santos,
   Gdansk, Singapore, Genoa, Sabetta) agree within 5–10%. `sea_km_no_suez`
   closes Suez.
6. Size classes use the port's 2024 total throughput: <1, 1–10, 10–50 and >50
   Mt. Distance classes use `sea_km`.

## Files

| File                                   | Content                                                                                 |
| -------------------------------------- | --------------------------------------------------------------------------------------- |
| `eurostat_port_partner_flows_2024.csv` | reporting port × partner × direction × cargo, with distances and tonne-km               |
| `port_throughput_2024.csv`             | 545 main ports: throughput, coordinates, size class                                     |
| `summary_by_*.csv`                     | shares of tonnes and tonne-km by size class, distance, cargo, cargo × distance, partner |
| `top20_pairs_RTM_ANR_HAM.csv`          | top 20 Rotterdam / Antwerp-Bruges / Hamburg pairs by tonne-km                           |
| `north_europe_route_groups_2024.csv`   | NL, BE, DE North Sea and FR Atlantic ports by partner region; `scripts/route_groups.py` |
| `imo_ghg4_transport_work_*.csv`        | 2018 transport work by ship type and size, and its share by dwt class                   |
| `unctad_tonne_miles_by_cargo.csv`      | world tonne-miles by cargo (2023–24 partly read off a chart; 2018 from IMO Table 71)    |

## Gaps

- No port-to-port detail: the partner port size for extra-European partners is
  unknown, and that is 87% of tonne-km.
- No ship size per flow. Eurostat publishes vessel size only for port calls
  (`mar_tf_qm`), so the dwt split is taken from the world-fleet IMO 2018 shares.
- The UK has not reported since 2020, so UK ports appear only as partners.
- Estonia is confidential and aggregated. Sweden's 48 Mt of "other ports" and
  Norway's 24 Mt sit at assumed coordinates.
- Distances route through Suez; in 2024 most Asia traffic went around the Cape
  (+26% tonne-km overall if Suez is closed).
- Tonne-km counts only flows touching a reporting port. It is a European-trade
  view, not world shipping.
