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

## Running the paper

The paper's results come from `paper` in `scripts/paper.jl`, as a draft run (fast, marked as a draft) or a final run (a clean tree on a pushed commit). [`docs/paper_runs.md`](docs/paper_runs.md) says how a run is kept and how to rerun only what a change made out of date; [`docs/router_speed.md`](docs/router_speed.md) says what the router does only for speed and what its settings cost. Results land in `output/runs/<start time>/`, and the figures and tables in `paper/`.

**On a workstation.** Install Julia with [juliaup](https://github.com/JuliaLang/juliaup), then:

```bash
./bin/install          # the Julia version and packages this repo is on
./bin/weather          # ERA5 and NOAA forecasts from public stores, no account; some hours, resumable
cd scripts && julia +$(../bin/julia_version) --project=. -t auto -e 'include("paper.jl"); paper(; fidelity=:draft)'
```

A final run takes days on a workstation, so it belongs on the box or a cluster.

**On the box**, the project's shared server, the weather and the store of routed round trips already exist: link them into the checkout with `ln -s /var/lib/windship/era5 era5` and `ln -s /var/lib/windship/output output`, then start `paper` as above. Runs there share the store, so a later run reuses every round trip an earlier one routed.

**On DelftBlue**, TU Delft's cluster, with your NetID and no other access:

```bash
ssh <netid>@login.delftblue.tudelft.nl   # from outside TU Delft's network, connect eduVPN first
tmux                   # the setup's weather download takes hours
curl -fsSL https://raw.githubusercontent.com/1-Bart-1/WindShipOpt.jl/main/bin/delftblue_setup | bash
exec bash -l           # puts julia on your PATH
cd /scratch/$USER/WindShipOpt.jl
bin/cluster submit final        # or: bin/cluster submit draft
bin/cluster status
```

The setup can be rerun and resumes where it stopped; it ends by checking every weather file against the box's and names any that differ. Jobs go to the research account `research-ae-fpt` set in `scripts/cluster.toml`, which allows up to 64 jobs at once; the run uses all 64, of 6 hours each, and resumes by itself past that. `/scratch` is cleared of old files, so copy `output/` home after a run, and run `bin/weather` before a run that comes months after the setup. [`docs/paper_runs.md`](docs/paper_runs.md#runs-on-a-slurm-cluster) has the detail.

To try the model on one ship without the paper: `./bin/run_julia scripts/compare_designs.jl`.

## Companion explorer

`site/` is the paper's companion website, one page read top to bottom: a reader picks a ship, a route and a fuel, changes the prices and rig goals, and sees each rig's best size and what it saves against the same ship on e-ammonia and on fuel oil. Each input marks when it differs from the paper's value and has a button that sets it back, and one button sets back all of them. It evaluates the model's own cost formulas, recorded over those inputs, on the voyages the class study routed, so no cost formula is written twice and the site routes nothing of its own. It offers only inputs that change what a voyage costs, over their range in the paper, and fuel and carbon prices, which shift the ship's speed, only by a moderate change. A full paper run writes the site's data into its run directory at its end; `paper(:site; fidelity)` packs them again from the run in use.

The site reads its data from the newest final run, or from the newest draft run until there is one (`EXPLORER_JSON=<path>`, `PASSAGES_DIRECTORY=<path>` and `GRIDS_JSON=<path>` pick others). With Node.js 20.19, or 22.12 or later:

```bash
./bin/explorer              # http://localhost:5173
npm --prefix site test      # fails where the site and the model disagree at the paper's inputs or changed ones
npm --prefix site run build # static site in site/dist
```

The page's passages, shown on the route chosen at its top, are the round trips the wind angle step routes: the passage figure's ship without a rig and with the reference size of the kite, the wing sails and the rotors on every route and every sampled departure, with the state of the ship and rig at each point the router sailed. A build without such a run leaves them out.

The router's grid, a section of the site below the passage viewer, draws the corridor grid the run routes on for the route chosen at the top, on a globe or a flat map: its usable and unusable nodes, the edges the router may take, and in rust every edge or row step running more than 90° off the centre line's course. Clicking a node shows every route from Rotterdam to port through it.

## Status

Runs on ERA5 wind and waves when `era5/atlantic_wide/` exists, otherwise on synthetic weather. Not in the model: currents, batteries with regeneration, a coastline finer than the ERA5 grid, an outer design optimiser.

## Licence

Everything here is © 2026 Bart van de Lint under the [GNU Affero General Public License v3.0 or later](LICENSES/AGPL-3.0-or-later.txt): the code, the paper, the data notes and the inputs. A few files belong to others and keep their own licence: the TeX Gyre Termes fonts in `data/fonts/` (LPPL 1.3c or later), the tables taken from the Fourth IMO GHG Study 2020 in `data/market/` (all rights reserved by the IMO), and `bin/reuse_lint` (MIT). The repository follows the [REUSE specification](https://reuse.software): every file's copyright and licence is in its header or in [`REUSE.toml`](REUSE.toml), the licence texts are in [`LICENSES/`](LICENSES/), and `./bin/reuse_lint` checks it.
