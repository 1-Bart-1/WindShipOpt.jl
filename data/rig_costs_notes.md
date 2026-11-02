# Rotor and wing sail series cost, and cargo space lost to deck rigs

Sources behind a series-production price for Flettner rotors and rigid wing sails, on the same basis as the kite in `kite_costs_notes.md` (component prices, then a multiplier for assembly, test and margin, then installation as a fraction), and behind the container slots a deck rig costs. Built 2026-10-31. Currency conversions use 1.16 USD/EUR, the rate in `assumptions.yaml`. "Estimate" marks a number that no source states; the reasoning follows it.

## Primary documents (downloaded and read)

| Short name            | Document                                                                                                                                                                     | URL                                                                                                                                          |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| EMSA 2023             | ABS, CE Delft, Arcsilea for EMSA, _Update on Potential of Wind-Assisted Propulsion for Shipping_, Oct 2023, §2.3.1 Table 4 (p. 31–32), §2.3.4 Table 5, Table 7 (p. 45–46)    | https://www.emsa.europa.eu/opr-documents/download/7664/5078/23.html (local: `paper/literature_pdfs/emsa2023.txt`)                            |
| CE Delft 2016         | CE Delft, Tyndall Centre, Fraunhofer ISI for DG CLIMA, _Study on the analysis of market potentials and market barriers for wind propulsion technologies for ships_, Nov 2016 | https://cedelft.eu/wp-content/uploads/sites/2/2021/04/CE_Delft_7G92_Wind_Propulsion_Technologies_Final_report.pdf (local: `cedelft2016.txt`) |
| Tillig 2020 TRD       | F. Tillig, J.W. Ringsberg, _Transportation Research Part D_ 2020, rotor costs "according to Norsepower" (p. 15)                                                              | local: `paper/literature_pdfs/tillig2020trd.txt`                                                                                             |
| Tillig 2020 OE        | F. Tillig, J.W. Ringsberg, _Design, operation and analysis of wind-assisted cargo ships_, Ocean Eng. 211 (2020) 107603, Table 3                                              | local: `paper/literature_pdfs/tillig2020oe.txt`                                                                                              |
| Norsepower 2025       | Norsepower, _Rotor Sail_ brochure 2025-03-86-ENG (16 Apr 2025), technical specifications table                                                                               | https://www.norsepower.com/app/uploads/2025/04/Norsepower-Brochure-91.pdf                                                                    |
| Norsepower 2023       | Norsepower brochure, web version 2023-03-06, technical specifications table                                                                                                  | https://www.norsepower.com/app/uploads/2023/08/brochure_ENG_print.pdf                                                                        |
| Hochkirch 2021        | K. Hochkirch, V. Bertram (DNV), _Wind assisted propulsion – economical and ecological considerations_, MARINE 2021, paper 275, §3 Tables 4–5                                 | https://journals.ed.ac.uk/MARINE2021/article/download/6835/9032/22211                                                                        |
| MEPC 79/INF.21        | Finland, France, Saudi Arabia et al., _Wind propulsion_, IMO MEPC 79/INF.21 (Oct 2022), §19 and Annex literature list                                                        | https://www.wind-ship.org/archived-site/wp-content/uploads/2022/10/MEPC-79-INF.21-Wind-Propulsion-Finland-France-Saudi-Ar....pdf             |
| WISDEM CSM            | NREL WISDEM 2.0 documentation, _NREL Cost and Scaling Model example_ (`Turbine_CostsSE_2015` output, 5 MW, 126 m rotor)                                                      | https://wisdem.readthedocs.io/en/master/examples/01_nrelcsm/tutorial.html                                                                    |
| ICCT 2023 (Jones Act) | ICCT white paper on wind assist for US domestic corridors, Dec 2023                                                                                                          | https://safety4sea.com/wp-content/uploads/2023/12/ICCT-Jones-Act-white-paper-2023_12.pdf                                                     |

ICCT 2023 gives fuel savings per sail (about USD 400 k a year per rotor and 250 k per wing on ocean routes, liquid hydrogen) but no capital cost; it is not used below.

## 1. Rotor sails

### Prices paid today

| Year | Price                                                                                       | Unit                                           | Source and strength                                                                                                                                                                                                                  |
| ---- | ------------------------------------------------------------------------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 2019 | EUR 300 k / 500 k / 750 k per unit                                                          | 18×3 m / 24×4 m / 30×5 m, "installation costs" | Tillig 2020 TRD p. 15 and OE Table 3, "according to Norsepower"; manufacturer figure via peer-reviewed paper, strong. 30×5 m weighs 59 t with foundation.                                                                            |
| 2019 | USD 3.5 M for three 30 m rotors (USD 1.17 M each)                                           | 19,500 dwt asphalt bulker                      | van der Kolk et al. 2019, quoted in MEPC 79/INF.21 Annex; academic case study, medium.                                                                                                                                               |
| 2021 | USD 2.25 M for three 30×5 m rotors (USD 750 k each), installation included                  | multipurpose ship                              | Hochkirch 2021 Table 5 (DNV authors); assumption, medium.                                                                                                                                                                            |
| 2021 | EUR 560–1,050 k asset, plus 15 % newbuild / 25 % retrofit installation                      | small to large rotor                           | EMSA 2023 Table 7, one rotor supplier interviewed; medium.                                                                                                                                                                           |
| 2018 | EUR 1–2 M "to install", unclear whether per rotor or per ship                               | Norsepower                                     | Forbes, 12 Mar 2018 (https://www.forbes.com/sites/oliversmith/2018/03/12/norsepower-why-european-ships-are-switching-back-to-sails/); weak.                                                                                          |
| n.d. | USD 400 k–1 M installed per rotor; USD 1–5 M per multi-rotor delivery                       | by size                                        | IMO GreenVoyage2050, Flettner rotors page (https://greenvoyage2050.imo.org/technology/flettner-rotors/); medium.                                                                                                                     |
| 2023 | "upwards of USD 1 M each" for Anemoi's largest sails on VLOCs; expected to fall with volume | 35×5 m class                                   | Lloyd's List, _British rotor sail designer Anemoi gears up for growth_ (https://www.lloydslist.com/LL1153376/), via search snippet; medium.                                                                                          |
| 2026 | GBP 28 M exports for 29 rotor sails on seven ships since June 2023, ~GBP 0.97 M a sail      | mostly 35×5 m, folding and rail versions       | Maritime Technology Review, 3 Feb 2026 (https://maritimetechnologyreview.com/2026/02/03/anemois-rotor-sails-propel-maritime-decarbonization-forward/); export revenue, not a unit price; the per-sail figure is my division; medium. |

The Norsepower 2019 prices are linear in projected area: a least-squares line through the three points is EUR 47 k + 4.69 kEUR per m² of height × diameter (USD 54 k + 5.44 k/m²), and it reproduces the middle point (EUR 497 k against 500 k). This is the best market-price reference and is used as the high case below. CE Delft 2016 had no rotor cost at all ("the questionnaire data did not generate costs for Flettner rotors", §4.3).

No public figure shows a falling rotor price. Norsepower opened a dedicated factory in Dafeng, China, in Nov 2024, starting at 50 units a year with 100 a year planned by end 2027 (https://www.norsepower.com/post/norsepower-launches-worlds-first-dedicated-rotor-sail-factory-consolidates-leadership-of-the-wind-propulsion-market/); Anemoi targeted 200 sails a year by end 2025 against ~50 in 2023 (Lloyd's Register, _Rotor sails taking off_, Dec 2023, https://www.lr.org/en/knowledge/horizons/december-2023/rotor-sails-taking-off/). Both build the composite rotor skins in China (Anemoi with Lianyungang Zhongfu, filament wound, https://www.compositesworld.com/news/anemoi-installs-composite-rotor-sails-on-sohar-max-maritime-vessel).

### What a rotor is made of

Norsepower specification tables (composite rotor, welded steel foundation and tower, electric drive with variable speed drive, NorseControl, hydraulic tilting optional):

| Model                                   | 20×4 m (2025) | 24×4 m | 28×4 m | 30×5 m | 35×5 m |
| --------------------------------------- | ------------- | ------ | ------ | ------ | ------ |
| Projected area [m²]                     | 80            | 96     | 112    | 150    | 175    |
| Weight without foundation [t], 2025     | 29            | 33     | 36     | 50     | 56     |
| Weight without foundation [t], 2023     | 27 (18×4 m)   | 30     | 37     | 42     | 63     |
| Typical foundation [t], 2025            | 13            | 13     | 15     | 17     | 24     |
| Electric motor nominal power [kW], 2025 | 80            | 100    | 115    | 115    | 175    |
| Max continuous thrust [kN], 2025        | 175           | 175    | 205    | 270    | 350    |

Anemoi names the same main parts: composite rotor skin with internal composite and steel structure, a steel support tower, upper and lower bearings, and an electric drive; the 35×5 m rotor has a 9 m top disc (CompositesWorld, Sohar Max article above). EMSA 2023 gives 34–90 t per rotor with foundation, the foundation roughly 30 % of the mass (§2.3.1), and 26–79 kEUR a year of drive energy (Table 7).

### Cost-per-kg and cost-per-kW benchmarks

| Item                            | Benchmark                                            | Source                                                                                                                                   |
| ------------------------------- | ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Fabricated tubular steel tower  | 2.90 USD/kg (528.8 kUSD for 182.3 t)                 | WISDEM CSM 2015 output (my division)                                                                                                     |
| Completed welded steel tower    | EUR 2.30/kg market (2010), 2.50 assumed              | Vindforsk V-342, _Tall towers for large wind turbines_ (https://www.osti.gov/etdeweb/servlets/purl/992745), via search snippet           |
| Finished glass-fibre wind blade | 14.6 USD/kg (230.0 kUSD for 15.75 t)                 | WISDEM CSM 2015 output (my division)                                                                                                     |
| Composite raw materials         | glass fabric 1.9–3.0 USD/kg, UD carbon 30, resin 3.6 | NREL _A Detailed Wind Turbine Blade Cost Model_, TP-5000-73585, 2019 (https://docs.nrel.gov/docs/fy19osti/73585.pdf), via search snippet |
| Yaw bearing and drives          | 8.3 USD/kg (102.3 kUSD for 12.3 t)                   | WISDEM CSM 2015 output                                                                                                                   |
| Turbine controls                | 105.8 kUSD for a 5 MW turbine                        | WISDEM CSM 2015 output                                                                                                                   |
| Variable frequency drive        | ~250 USD/kW average over 15 projects                 | Thunder Said Energy (https://thundersaidenergy.com/downloads/variable-frequency-drives-the-economics/), consultancy, via snippet; weak   |
| Shipbuilding AH36 plate         | 683–760 USD/t                                        | BBN Ship Steel price list, undated (https://www.shipbuilding-steel.com/News/price-for-ah36-steel-plate-for-shipbuilding_2160.html); weak |

### Bottom-up series price (estimate)

Split of the Norsepower 2025 mass (estimate): composite rotor and end disc from its surface, ~30 kg/m² of cylinder area including disc and internal frames (7.5 t for 20×4, 14 t for 30×5, 16 t for 35×5); bearings and drive 8 % of the mass without foundation; the rest is the steel tower. Prices: composite 15 USD/kg (blade benchmark), tower and foundation 4 USD/kg (wind tower 2.9 raised for smaller, machined bearing seats; the kite mast in `kite_costs_notes.md` uses 5–10), bearings 30–45 kUSD a set, motor plus drive 400 USD/kW for marine type approval, controls 30 kUSD, then ×1.3 for assembly, balancing, test and supplier margin (the kite control unit uses ×1.5 for the same). Low case: 10 USD/kg composite, 3 USD/kg steel, 250 USD/kW, 15 kUSD controls, ×1.15. High case: 25, 6, 800, 60, ×1.5.

| Rotor  | Composite [t] | Tower [t] | Foundation [t] | Parts, base [kUSD] | Series price, base [kUSD] | Low [kUSD] | Bottom-up high [kUSD] | Norsepower 2019 market [kUSD] |
| ------ | ------------- | --------- | -------------- | ------------------ | ------------------------- | ---------- | --------------------- | ----------------------------- |
| 20×4 m | 7.5           | 19        | 13             | 333                | 433                       | 254        | 853                   | 489                           |
| 30×5 m | 14            | 32        | 17             | 522                | 679                       | 398        | 1,354                 | 870                           |
| 35×5 m | 16            | 36        | 24             | 623                | 810                       | 479        | 1,616                 | 1,006                         |

A line through the 20×4 and 35×5 m points gives the series price as **USD 115 k + 4.0 kUSD per m²** (low 65 k + 2.4 k/m²). The bottom-up high case lands above today's market price, so the high case is the market line, USD 55 k + 5.4 k/m²; a series price above what is paid today makes no sense. The base sits 15–20 % below the Norsepower 2019 line, about the 10 % (2030) to 20 % (2050) economies of scale that EMSA 2023 assumes for all WAPS (§ "Estimation of costs").

Learning-curve cross-check (estimate): CE Delft 2016 assumed 10 % cost reduction per doubling of installed capacity for wind propulsion, against 20 % in the energy-technology literature (§4.2); MEPC 79/INF.21 §19 repeats 10 %, citing offshore wind, against 18 % for onshore wind and 33 % for solar PV, and projected installation costs 40–50 % below 2019 by 2025/26. The 2026 prices above do not show that drop. At 10 % per doubling, a tenfold rise in cumulative output cuts cost by 30 % and a twentyfold rise by 37 % (0.9^log2 n). Wind-turbine analogues: onshore wind learning rate ≥12 % (IRENA, https://www.irena.org/Events/2014/Nov/The-True-Costs-of-Renewables-Wind-power-cost-reduction-potential-and-learning-curves), about 9 % for onshore turbine prices 1983–2019 (Springer, https://link.springer.com/doi/10.1007/s41471-021-00114-8), 5 % per doubling assumed for offshore wind (TNO, https://publications.tno.nl/publication/34629029/82t1BC/e10034.pdf). Ten- to twentyfold growth on today's market price gives USD 550–610 k for a 30×5 m rotor, between the low and base cases.

Installation: EMSA 2023 Table 7 takes 15 % of the asset cost for a newbuild and another 10 % for a retrofit (25 % in total), lower in percentage for the largest units. The foundation is already in the supply price above (Norsepower delivers it), so the 15 % covers deck reinforcement, cabling, switchboard and yard work; this is the same treatment as `kite_integration_fraction`.

## 2. Rigid wing sails

### Prices paid today

| Year | Price                                                                      | Unit                       | Source and strength                                                                                                                                                 |
| ---- | -------------------------------------------------------------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2018 | USD 2.5 M for a generic rigid sail system of 1,400 m² (~1,800 USD/m²)      | theoretical baseline       | Atkinson et al., _Cogent Engineering_ 2018 (https://www.tandfonline.com/doi/full/10.1080/23311916.2018.1543564); the authors say no production figures exist; weak. |
| 2021 | EUR 438–876 k asset, +66–130 k newbuild / +109–219 k retrofit installation | small to large hard sail   | EMSA 2023 Table 7; with Table 4's 280–1,000 m² this is 1,016–1,815 USD/m² asset only; no hard-sail supplier was interviewed; weak to medium.                        |
| 2023 | USD 2.55 M per WindWing                                                    | 37.5 m span × 20 m, 750 m² | Positive News, 25 Aug 2023 (https://www.positive.news/environment/back-to-the-future-with-wind-powered-shipping/), unattributed; 3,400 USD/m²; weak.                |
| n.d. | USD 500–700 k per installed sail                                           | suction wings              | IMO GreenVoyage2050, fixed sails or wings page (https://greenvoyage2050.imo.org/technology/fixed-sails-or-wings/); not a rigid wing, context only.                  |

Area 750 m² for the 37.5 m WindWing: BAR Technologies product page (https://www.bartechnologies.uk/commercial-ships/windwings/), span × width. No price was found for Oceanbird, OceanWings (AYRO), MOL Wind Challenger (MOL declined to disclose, Maritime Executive) or the smaller WindWings.

### What a wing is made of

| Wing                    | Area [m²] | Mass [t]                                            | Construction                                                                                       | Source                                                                                                                                                       |
| ----------------------- | --------- | --------------------------------------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Hard sails (EMSA range) | 280–1,000 | 45–100 with foundation                              | —                                                                                                  | EMSA 2023 Table 4                                                                                                                                            |
| OceanWings OW RE        | 363       | 45 (unit)                                           | 33 × 11 m wing, 2.5 m OD hull interface, elevator retraction                                       | https://www.oceanwings.com/product/ow-re-rigid-elevator-wingsail                                                                                             |
| Oceanbird Wing 560      | 560       | 98.5 wing (Damen); ~200 with foundation (Oceanbird) | carbon-steel mast and foundation; PET-core glass-fibre flap, leading and trailing panels; tiltable | https://www.theoceanbird.com/wing-560; https://www.damen.com/services/shiprepair/projects/vehicles-carrier-tirranna-harbour-and-voyage-repair-and-conversion |
| WindWings 20–24 m       | —         | <30                                                 | —                                                                                                  | https://www.vesselfinder.com/news/28659-BAR-Technologies-signs-deal-with-WindWaves-to-manufacture-new-20m--24m-WindWings                                     |
| WindWings 37.5 m        | 750       | not found                                           | steel and composite glass, built in China                                                          | Pyxis Ocean coverage (e.g. https://gcaptain.com/wind-assisted-propulsion-trial-off-to-promising-start/)                                                      |

That is 0.10–0.16 t/m² for most hard sails, 0.12 for OceanWings, 0.18 for the Oceanbird wing alone and 0.36 with its foundation.

### Bottom-up series price (estimate)

Per m² of sail area, base: 0.13 t/m² with 60 % steel (mast, structure, foundation) at 4 USD/kg and 30 % composite skins and flaps at 12 USD/kg (simpler panels than a blade), the remaining 10 % of mass being mechanisms priced as a fixed part: slewing bearing 50 k, flap and slewing actuators 40 k, tilting or retraction mechanism 80 k, controls 30 kUSD. Everything ×1.3 as for the rotor. Low: 0.10 t/m², 3 and 8 USD/kg, no tilt, ×1.15. High: 0.16 t/m², 6 and 20 USD/kg, 150 k tilt, ×1.5.

| Case | Per m² [USD/m²] | Fixed [kUSD] | At 280 m² [USD/m²] | At 500 m² | At 750 m² | At 1,000 m² |
| ---- | --------------- | ------------ | ------------------ | --------- | --------- | ----------- |
| Low  | 480             | 80           | 770                | 640       | 590       | 560         |
| Base | 1,000           | 260          | 1,940              | 1,530     | 1,360     | 1,270       |
| High | 2,300           | 525          | 4,180              | 3,350     | 3,000     | 2,830       |

The base matches EMSA's 2021 asset cost for small hard sails (1,815 USD/m² at 280 m²) and exceeds it for large ones (1,016 USD/m² at 1,000 m²), while the high case brackets the WindWings price (3,400 USD/m² at 750 m²). EMSA's hard-sail row already reads like a series or target price, not a first-of-a-kind one. The finding: a series wing is cheaper than today's 2,000 USD/m² installed in `assumptions.yaml` mostly because that figure includes installation; ex works the base at 500 m² is ~1,530 USD/m², and ~1,760 installed at +15 %.

Installation: no wing-specific figure exists; EMSA 2023 applies the same 15 % newbuild and +10 % retrofit to hard sails (Table 7).

## 3. Cargo capacity lost to deck rigs

### What exists

- **No measured container slot loss exists.** No rotor or wing sail is installed on a container ship as of this date. EMSA 2023 (§2.3.4): "WAPS have yet to be installed on a container ship, for which the lack of deck space is a key issue", and its uptake tables set container ships to zero units. CE Delft 2016 (§3.2.7): "As rotors need available deck space they are not fitted to container vessels", the same for sails; only the kite was fitted to container ships. IMO GreenVoyage2050: "Containerships may be evaluated in the case a design with elevated/retractable rotors mounted above the container cargo."
- **Maersk / Anemoi, 2 Sep 2026:** one fixed 35×5 m rotor for an 8,700 TEU Lima-class ship, installation mid-2027 (Ship & Bunker, https://shipandbunker.com/news/world/495295-maersk-to-install-worlds-first-rotor-sail-on-boxship-with-anemoi). Maritime Executive: Anemoi is "positioning the rotor near the bow", which "helps to address the concerns of impacting container capacity" (https://maritime-executive.com/article/maersk-to-test-first-wind-rotor-on-a-containership). No slot count is published.
- **ONE / Econowind, Nov 2023:** two containerised VentoFoil suction wings on the 1,036 TEU feeder _Kalamazoo_, each in a 40 ft container footprint (Energy Global, 23 Nov 2023, https://www.energyglobal.com/wind/23112023/one-to-trial-wind-propulsion-technology-for-sustainable-shipping; Econowind: "standard container footprint"). Derived: one FEU slot (2 TEU) per unit at the top of a stack. This is a suction wing, not a rotor or rigid wing.
- **OceanWings TradeWings 2500:** six 363 m² elevator wingsails on a 2,500 TEU, 197 × 32 m concept (BV Approval in Principle), "cargo space loss <1%" (https://www.oceanwings.com/use-case/containership-tradewings-2500). That is ≤25 TEU for six wings, ≤4 TEU a wing. A vendor claim for a concept; weak.
- **Zéphyr & Borée 1,800 TEU, BV AiP Dec 2021:** eight CWS wing sails on a mostly open-top ship with five holds; no capacity impact stated (https://maritime-executive.com/article/designs-for-1-800-teu-wind-assisted-containership-approved-by-bv).
- **Deadweight, not slots:** EMSA 2023 §2.3.1: only on ships under 5,000 dwt is cargo-carrying capacity likely reduced by more than 1 % per WAPS unit, through the unit's mass. The model already carries rig mass (`wing_mass_per_area`, `rotor_mass_per_area`).

### Geometric estimate for container ships (estimate)

A rig standing on a hatch cover takes every on-deck slot in the rows and bay it covers, all tiers up, and blocks the pontoon over the hold cells below unless it sits on a fixed structure. Ingredients:

- 40 ft container: 12.192 m long, 2.438 m wide, 2.591 m (2.896 m high cube) tall (ISO 668, https://en.wikipedia.org/wiki/ISO_668). One 40 ft position is 2 TEU.
- Row pitch ~2.5 m: Panamax beam 32.31 m carries 13 rows (2.49 m a row, https://www.wikipedia.org/wiki/Panamax); an APL post-Panamax of 39.4 m beam 16 rows above the hatches (2.46 m), and a ship of just over 40 m beam six tiers in 16 rows on deck (TRID abstracts https://trid.trb.org/View/400857 and https://trid.trb.org/View/431588, via search snippets); the 51.25 m Neo-Panamax limit fits 20 rows (2.56 m) (https://splash247.com/?p=104627).
- Tiers on deck (estimate except the APL six): feeder ~4, Panamax ~6, Neo-Panamax ~8, Megamax ~10.

Rows lost = ceil((footprint + 1 m clearance) / 2.5 m); TEU lost = rows × tiers on deck × 2 for one 40 ft bay.

| Rig on a hatch, deck slots only                             | Rows | Feeder (4 tiers) | Panamax (6) | Neo-Panamax (8) | Megamax (10) |
| ----------------------------------------------------------- | ---- | ---------------- | ----------- | --------------- | ------------ |
| Rotor, 5 m diameter                                         | 3    | 24               | 36          | 48              | 60           |
| Wing on a pedestal above the stacks, 2.5 m mast             | 2    | 16               | 24          | 32              | 40           |
| Wing rooted at hatch level, 14 m chord, swept 18 m (2 bays) | 8    | 128              | 192         | 256             | 320          |

The swept circle of a weathervaning wing is ~1.3 chords across (pivot near 35 % chord, estimate), which is why every container concept raises the wing above the stacks or retracts it. Bow or forecastle placement (Maersk) loses about nothing for one unit, since the foremost bay is short and visibility-limited. SOLAS V/22 limits each blind sector forward of the beam to 10° and their total to 20° (Gard, https://gard.no/insights/importance-ensuring-navigation-bridge-visibility); a 5 m rotor 100 m ahead of the bridge subtends ~3°, so visibility does not bind for one or two units.

### Car carriers and ro-ro

Cars travel inside a PCTC; the weather deck is not a cargo deck, so a wing there loses car capacity only where its foundation and supports pass through the upper decks. No figure is published for _Tirranna_ (7,650–8,000 CEU, Wing 560 fitted June 2026) or _Orcelle Wind_ (>7,000 cars). Estimate: a 3–6 m foundation through one or two decks displaces 0–10 CEU a wing. On a ro-ro such as _SC Connector_ (two tiltable 35×5 m Norsepower rotors, weather deck 610 lane metres, Sea-Cargo product sheet, https://sea-cargo.no/wp-content/uploads/2022/10/SC-Connector-produktark-2022-1.pdf) the rotors take weather-deck lane metres; no figure is published.

### Bulk carriers and tankers

Cargo sits below deck, so no cargo volume is lost; the cost is deadweight (the rig's mass) and interference with hatch covers, grabs and shore cranes. Solutions in service: Anemoi longitudinal rails on _Afros_ (2018, about 200 port calls) and transverse rails on the Kamsarmax _TR Lady_ (three 24×5 m rotors); five folding 35×5 m rotors on the 400,000 dwt _Sohar Max_, moved from the centreline to port or starboard during cargo operations (Lloyd's Register, Dec 2023); Norsepower hydraulic tilting foundation as an option (Norsepower 2025); WindWings fold flat. No price premium for rails, folding or tilting was found. Estimate: +5–20 % on the unit price for a hydraulic tilt or rail system (cylinders, hinge or bogie, power pack, longer foundation), base +10 %.

## Proposed model inputs

| Name                                       | Value   | Low    | High    | Unit             | Source                                                                                                                                                           | Strength                                 |
| ------------------------------------------ | ------- | ------ | ------- | ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| rotor_series_price_fixed                   | 115,000 | 65,000 | 55,000  | USD per unit     | Estimate from Norsepower 2025 masses and wind-industry cost per kg; the high case is the Norsepower 2019 market line, whose fixed part is smaller.               | Estimate on strong masses, medium prices |
| rotor_series_price_per_area                | 4,000   | 2,400  | 5,400   | USD/m² (H×D)     | Same bottom-up; high is Norsepower's 2019 EUR 300/500/750 k for 18×3/24×4/30×5 m (Tillig & Ringsberg 2020).                                                      | Estimate; high case strong               |
| rotor_installation_fraction                | 0.15    | 0.10   | 0.25    | of unit price    | EMSA 2023 Table 7: 15 % newbuild, +10 % retrofit; foundation already in the unit price.                                                                          | Medium (one supplier interview)          |
| wing_series_price_fixed                    | 260,000 | 80,000 | 525,000 | USD per unit     | Estimate: slewing bearing, actuators, tilt or retraction, controls, ×1.3.                                                                                        | Estimate                                 |
| wing_series_price_per_area                 | 1,000   | 480    | 2,300   | USD/m² sail area | Estimate from 0.10–0.16 t/m² (EMSA Table 4, OceanWings, Oceanbird) at steel and composite cost per kg; high brackets WindWings USD 2.55 M for 750 m².            | Estimate on medium masses; prices weak   |
| wing_series_price_per_area, area-only form | 1,500   | 650    | 3,350   | USD/m²           | The two rows above evaluated at 500 m², for a model without a fixed term.                                                                                        | Estimate                                 |
| wing_installation_fraction                 | 0.15    | 0.10   | 0.25    | of unit price    | EMSA 2023 Table 7, same rule as rotors; no wing-specific figure.                                                                                                 | Weak                                     |
| tilt_or_rail_premium                       | 0.10    | 0.05   | 0.20    | of unit price    | Estimate; rails, folding and tilting are in service (Anemoi, Norsepower, Oceanbird) but unpriced.                                                                | Estimate, no source                      |
| teu_lost_per_rotor                         | 36      | 0      | 60      | TEU per unit     | Geometric estimate, 3 rows × deck tiers × 2 TEU (Panamax base; 24 feeder, 48 Neo-Panamax); 0 for a bow unit (Maersk/Anemoi). No measured value exists.           | Estimate on sourced dimensions           |
| teu_lost_per_wing                          | 24      | 4      | 192     | TEU per unit     | Geometric estimate for a wing raised above the stacks (Panamax); low is OceanWings' <1 % claim for six wings on 2,500 TEU; high is a wing rooted at hatch level. | Estimate; low is a vendor claim          |
| ceu_lost_per_wing (PCTC)                   | 0       | 0      | 10      | CEU per unit     | Estimate: weather deck is not a car deck; only foundation penetrations count. No source.                                                                         | Estimate, no source                      |
| cargo_lost_bulk_tanker                     | 0       | 0      | 0       | m³               | Cargo is below deck; the loss is the rig's mass in deadweight, already in the rig mass inputs (EMSA 2023 §2.3.1).                                                | Medium                                   |

A usable sourced number for container slot loss does not exist. The only figures are a vendor claim for a concept (OceanWings, <1 %) and footprints from which a loss can be derived (VentoFoil, one 40 ft slot each). Treat `teu_lost_per_rotor` and `teu_lost_per_wing` as geometric estimates, scale them with the ship's deck tiers (2 × rows × tiers), and run them as a sensitivity; the low end, rigs at the bow or raised above the stacks, is what the first installation (Maersk 2027) is designed for.
