# WindShipOpt.jl

> **Work in progress.** The model, its inputs and the paper are still changing, and the numbers in this repository are drafts that later runs replace. Do not cite or rely on them yet.

Design optimisation of wind-assisted coasters for long ocean routes. It compares towing kites, wing sails and Flettner rotors, alone or combined, on cargo ships from coasters to Megamax container ships, on VLSFO, e-methanol or hydrogen, with weather routing on every voyage. The figure of merit is the cost per tonne-kilometre of the transport service.

## Model chain

1. **Hull**: Holtrop–Mennen (1984) calm-water resistance, with Kijima side-force slope and slender-body induced drag for leeway.
2. **Rig**: rigid wings via a lifting-line polar and Flettner rotors via fitted coefficients, with array interference; kite via a quasi-steady crosswind model without reeling, with pattern centre, width, heading and angle of attack optimised per wind; all limited by heel and leeway.
3. **Propulsion**: actuator-disk propeller with a viscous loss factor; diesel engines, gensets or PEM fuel cells with a part-load efficiency curve.
4. **Performance table**: required thrust over (speed, 10 m wind, true wind angle), kite flown and stowed, plus added resistance over (speed, peak period, wave heading), per design.
5. **Routing**: forward dynamic programming over (stage, lateral node, arrival time) in a corridor, minimising fuel cost plus time cost.
6. **Economics**: capital annuity, crew, maintenance, port calls and cargo interest; the time cost per hour makes the per-voyage optimum the per-tonne-km optimum.

Every number the model assumes, with its sensitivity range and the reason for it, is in [`data/assumptions.yaml`](data/assumptions.yaml).

## Running

```bash
./bin/install
./bin/run_julia scripts/compare_designs.jl
```

## Status

Runs on ERA5 wind and waves when `era5/atlantic_wide/` exists, otherwise on synthetic weather. Not in the model: currents, batteries with regeneration, a coastline finer than the ERA5 grid, an outer design optimiser.

## Licence

Everything here is © 2026 Bart van de Lint under the [GNU Affero General Public License v3.0 or later](LICENSES/AGPL-3.0-or-later.txt): the code, the paper, the data notes and the inputs. A few files belong to others and keep their own licence: the TeX Gyre Termes fonts in `data/fonts/` (LPPL 1.3c or later), the Eurostat extract in `data/market/` (CC BY 4.0, source: Eurostat), the tables taken from the Fourth IMO GHG Study 2020 and UNCTAD's Review of Maritime Transport (all rights reserved by their publishers), and `bin/reuse_lint` (MIT). The repository follows the [REUSE specification](https://reuse.software): every file's copyright and licence is in its header or in [`REUSE.toml`](REUSE.toml), the licence texts are in [`LICENSES/`](LICENSES/), and `./bin/reuse_lint` checks it.
