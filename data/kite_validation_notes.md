# Ship towing kite: validation of the cost inputs

This file checks the kite cost inputs of `assumptions.yaml` (built up in
`cost_basis_notes.md` and `kite_costs_notes.md`) against airborne wind energy
(AWE) cost literature, other industries, learning-curve reasoning and a simple
business case. Built 2026-11-01. Currency: 1.16 USD/EUR, as in
`assumptions.yaml`; prices are not escalated to a common year unless stated.
"Estimate" marks a number that no source states, with the reasoning next to it.

## 0. What is being validated

Market price = manufacturing cost × `market_price_factor` 2.0; hardware gets +15
% installation (newbuild); the tether is costed at its 79 USD/kg purchase price.
Maximum tether force is 0.5 kN/m² × projected area A, mast height √A, tether 13
spans long at 0.4 GPa. The prices below are a snapshot of the yaml values of
2026-11-01, so their mast and docking head columns and hardware totals predate the
model's taller mast and area-scaled docking head.

| Projected area | Winch (market) | Mast  | Docking head | Control unit | Hardware incl. installation | Canopy  | Tether |
| -------------- | -------------- | ----- | ------------ | ------------ | --------------------------- | ------- | ------ |
| 160 m²         | 58 k           | 21 k  | 74 k         | 27 k         | 207 k                       | 31 k    | 3 k    |
| 800 m²         | 73 k           | 47 k  | 74 k         | 46 k         | 276 k                       | 157 k   | 30 k   |
| 1,600 m²       | 92 k           | 66 k  | 74 k         | 70 k         | 348 k                       | 314 k   | 85 k   |
| 3,200 m²       | 131 k          | 94 k  | 74 k         | 118 k        | 479 k                       | 627 k   | 242 k  |
| 8,000 m²       | 246 k          | 148 k | 74 k         | 262 k        | 840 k                       | 1,568 k | 955 k  |

All in USD. The docking head is the same 74 k for every size, and the mast is
the same 0.8 m × 12 mm tube at every height; both matter in §2.

## 1. AWE LCOE check: the same kite in a pumping ground-generation system

### Method

A pumping system reels the tether out under load to drive a generator and reels
it back in with the kite depowered. Only the airborne and launch parts are
shared with the ship kite, so the check takes those from our inputs and
everything that makes electricity from the AWE literature. LCOE = (CAPEX × CRF +
OPEX + consumables) / AEP, with CRF at 8 % over 20 years = 0.1019 (our
`discount_rate`; BVGA 2022 uses 20 years at 7.5 % WACC for 2025).

| Component                                  | Source of the cost                                                                                                                                                        | 800 m² [kUSD]            | 3,200 m² [kUSD]          |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------ | ------------------------ |
| Canopy with bridle                         | **ours**, 98 USD/m² × 2.0                                                                                                                                                 | 157                      | 627                      |
| Control unit                               | **ours**, (11 k + 15 USD/m²) × 2.0                                                                                                                                        | 46                       | 118                      |
| Launch mast and docking head               | **ours**, (830 USD/m × √A + 37 k) × 2.0                                                                                                                                   | 121                      | 168                      |
| Tether                                     | **ours** for USD/kg and diameter (79 USD/kg, 0.4 GPa); length 1,000 m / 1,500 m is an estimate for a pumping system (Faggiani 2018 uses 1,500 m on a 100 m² kite)         | 47                       | 284                      |
| Drum, brake, frame                         | **ours**, the holding winch × 2.0, as a stand-in for the drum; conservative because it also carries a reeling gearbox                                                     | 73                       | 131                      |
| Gearbox                                    | AWE literature: 70 EUR/kW × crest factor 2 (Joshi et al. 2025, §2.6, Eq. 22; optimum crest factor 2, §3.1.2)                                                              | 130                      | 520                      |
| Generator                                  | AWE literature: 120 EUR/kW × crest factor 2 (Joshi et al. 2025, Eq. 23)                                                                                                   | 223                      | 891                      |
| Power converters                           | AWE literature: 100 EUR/kW, applied to the 2× machine rating (Joshi et al. 2025, Eq. 30)                                                                                  | 186                      | 742                      |
| Site preparation, foundation, installation | AWE literature: 40 + 55 × 2 + 40 EUR/kW (Joshi et al. 2025, Eqs. 31–33)                                                                                                   | 176                      | 705                      |
| Grid connection                            | AWE literature: electrical connections 23,000 + transformer 4,200 EUR per 60 kW unit in a 7 × 7 park (Faggiani 2018, Table 16.2)                                          | 421                      | 1,683                    |
| Storage                                    | none in the base, as in Faggiani's park, where units balance each other; a single unit with 60 s of ultracapacitor storage at Joshi's 60,000 EUR/kWh adds 0.93 / 3.7 MUSD | 0                        | 0                        |
| **CAPEX**                                  |                                                                                                                                                                           | **1,580** (1,975 USD/kW) | **5,869** (1,834 USD/kW) |
| O&M                                        | AWE literature: 60 EUR/kW/yr (Joshi et al. 2025, Eq. 34) plus insurance 1.3 % of CAPEX (Faggiani 2018: 1,300 on 98,800 EUR)                                               | 76/yr                    | 299/yr                   |
| Canopy replacement                         | **ours**, canopy price / 2,000 flight h × 6,000 flight h/yr (estimate: a pumping unit flies whenever the wind is in range, ~70 % of the year)                             | 470/yr                   | 1,882/yr                 |
| Tether replacement                         | life 3,000 flight h (estimate: half a year, inside the 3 months–2 years of the DEADALUS project quoted in the yaml)                                                       | 95/yr                    | 569/yr                   |

Power and energy: rated electrical power 1.0 kW per projected m², AEP 3.5 MWh
per projected m² per year (capacity factor 40 %), so 800 kW and 2,800 MWh/yr for
800 m², 3.2 MW and 11,200 MWh/yr for 3,200 m². Basis:

| System                            | Kite area                         | Rated power                       | AEP                                         | Per kite m²                              | Source                                                                                                                                                      |
| --------------------------------- | --------------------------------- | --------------------------------- | ------------------------------------------- | ---------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Faggiani & Schmehl, 100 m² design | 100 m² flat, 72 m² projected      | 60 kW continuous, 100 kW machines | 162 MWh/yr, CF 54 % (Weibull A = 12, k = 2) | 0.83 kW and 2.25 MWh/yr per projected m² | Faggiani 2018, Table 16.1 (p. 400), §16.5 (pp. 406–407)                                                                                                     |
| SkySails Power Venyo (PN-14)      | up to 180 m²                      | up to 200 kW                      | up to 760 MWh/yr                            | 1.1 kW, 4.2 MWh/yr per m²                | https://skysails-power.com/onshore-unit-pn-14/ (read 2026-11-01; company claims, "up to")                                                                   |
| SkySails Power Kyo                | up to 450 m²                      | up to 450 kW                      | up to 1,780 MWh/yr                          | 1.0 kW, 4.0 MWh/yr per m²                | same page                                                                                                                                                   |
| SkySails Power Fujun              | up to 1,200 m²                    | up to 1,300 kW                    | up to 6,580 MWh/yr                          | 1.1 kW, 5.5 MWh/yr per m²                | same page; "to be announced"                                                                                                                                |
| Kitepower Falcon                  | 60–80 m² flat, 47–62 m² projected | 100 kW nominal                    | 450 MWh/yr                                  | 1.6–2.1 kW per projected m²              | Kitepower Falcon datasheet, https://thekitepower.com/resources/product/New%20Powerful%20Ways%20-%20The%20Kitepower%20Falcon%20100kW.pdf (via search result) |

SkySails does not say whether its areas are flat or projected. The base sits
between Faggiani's computed yield and SkySails' "up to" claims; low uses
Faggiani's 2.25, high SkySails' 4.2 per m² × 1.17 flat over projected = 4.9
MWh/m²/yr. No AWE system larger than 1,200 m² has been announced, so the 3,200
m² case is an extrapolation that ignores the kite-mass penalty Joshi et al.
(2025) find to lower capacity factor with size.

### Result

| Case                                                      | 800 m² [EUR/MWh] | 3,200 m² [EUR/MWh] |
| --------------------------------------------------------- | ---------------- | ------------------ |
| Base                                                      | 247              | 258                |
| Canopy life 4,000 h (Kitepower rating) instead of 2,000 h | 175              | 185                |
| Low yield 2.25 MWh/m²/yr (Faggiani)                       | 384              | 401                |
| High yield 4.9 MWh/m²/yr (SkySails claims)                | 176              | 184                |
| Single unit with ultracapacitor storage                   | 280              | 290                |
| Optimistic: canopy 4,000 h, tether 6,000 h, high yield    | 114              | 117                |

Published AWE LCOE for comparison:

| Source                                                                         | Value                                                                                         | Where                                                                                                       |
| ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Faggiani & Schmehl 2018, 100 m² soft kite, 5 % discount rate                   | "just below 120 ¤/MWh" for 49 units; 105 single unit and 96 park at the optimum 250 m²        | pp. 407–409, Figs. 16.11–16.12, https://awesco.tudelft.nl/publication/faggiani-2018/faggiani-2018.pdf       |
| BVG Associates 2022, representative ground-generation system, 7.5 m/s at 100 m | 99 EUR/MWh (2025), 45 (2030), 24 (2040), 15 (2050), from 15 % learning to 2030 and 10 % after | Table 5 and Table 4, p. 25, https://vb.nweurope.eu/media/20517/bvga-getting-airborne-white-paper-220929.pdf |
| Joshi, von Terzi & Schmehl 2025, rigid-wing ground generation, 10 % discount   | 142 EUR/MWh at the optimum 500 kW                                                             | WES 10, 695, §3.1.1, Table 7, https://wes.copernicus.org/articles/10/695/2025/                              |
| Joshi et al. 2025, Table 1: published AWE estimates compiled                   | 18–150 EUR/MWh for 20–4,100 kW                                                                | Table 1 (downloaded xlsx)                                                                                   |
| SkySails Power target                                                          | "under 25 cents per kWh"                                                                      | https://skysails-power.com/onshore-unit-pn-14/                                                              |
| IRENA, onshore wind, global weighted average 2024                              | 34 USD/MWh; Europe ~51                                                                        | IRENA, _Renewable Power Generation Costs in 2024_ (Jul 2025), via secondary summaries; PDF not opened       |

### Differences between the ship kite and a pumping system

- **Generator against holding winch.** The ship winch holds the tether and reels
  slowly at launch and landing; a pumping drum reels out under full load all the
  time and needs a gearbox, a generator rated at about twice the average power
  and converters. In the table that is 539 kUSD (800 m²) against our 73 kUSD
  winch, so a cheap ship winch says nothing about the AWE ground station, and
  vice versa.
- **Storage and grid.** The ship kite has neither. A single pumping unit needs
  storage to bridge the reel-in phase (Joshi: ultracapacitors are among the
  largest CAPEX and OPEX items), and grid connection is the largest single CAPEX
  item in the table.
- **Tether wear.** In pumping, the tether bends over the drum under load every
  cycle; on the ship it stays on the drum at a fixed length in flight. Joshi et
  al. (2025) name tether replacement a primary LCoE driver. The check uses 3,000
  h against our ship 4,000 h; the ship value may even be conservative.
- **Canopy duty.** A pumping kite flies ~6,000 h a year, powering and depowering
  every cycle (tens of thousands of load cycles a year); a ship kite flies when
  the ship is at sea in suitable wind (estimate below: ~2,000 h a year) at a
  steadier load. Per flight hour the pumping canopy wears at least as fast.

### Verdict on the AWE check

Our shared components do not give an absurdly low AWE LCOE. The base, 250–260
EUR/MWh, is above every published AWE estimate except SkySails' own target and
is ~7× onshore wind. Their CAPEX is moderate: canopy, control unit, launch
hardware and tether are 23 % (800 m²) and 20 % (3,200 m²) of system CAPEX; the
drivetrain and grid connection dominate, as in the literature. What drives the
high LCOE is canopy replacement: 470 kUSD a year at 800 m², 168 USD/MWh on its
own, because a 2,000 h canopy is replaced three times a year in pumping service.
With Kitepower's 4,000 h rating and SkySails' claimed yield the LCOE falls to
~115 EUR/MWh, the level Faggiani and BVGA give for 2025. So the canopy price per
m² is consistent with AWE practice (§2), and our 2,000 h canopy life is, if
anything, pessimistic against what AWE developers assume. The check cannot
validate the ship-specific hardware (winch, mast scaling, docking head); those
are compared with other industries below.

## 2. Cross-industry check of each component's manufacturing cost

### Canopy (98 USD per projected m² manufacturing, 196 market; 84 / 168 USD per flat m²)

| Benchmark                                            | Price                                               | Per flat m²                                                                                                            | Source                                                                                                                                                                                                                                |
| ---------------------------------------------------- | --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ozone Buzz Z7 paraglider, 22–31 m² flat, with lines  | EUR 4,200 list incl. 20 % VAT                       | 130–184 USD ex VAT, retail                                                                                             | `kite_costs_notes.md` §3 (paratroc.com, flybubble.com)                                                                                                                                                                                |
| Kitesurf kites, LEI and closed-cell ram-air, 6–19 m² | USD 1,700–2,870                                     | 134–151 USD at the largest sizes, retail                                                                               | `kite_costs_notes.md` §3 (mackiteboarding.com)                                                                                                                                                                                        |
| Faggiani 2018 series AWE kite, C = c·A^0.75          | EUR 22,000 at 100 m² flat                           | 255 USD at 100 m²; 146 at 936 m²; 103 at 3,744 m²                                                                      | Table 16.2, p. 406                                                                                                                                                                                                                    |
| Joshi et al. 2025, rigid composite kite              | 200 EUR/m² plus 250 EUR/kg                          | > 232 USD                                                                                                              | §2.6.1                                                                                                                                                                                                                                |
| G-11 cargo parachute, 100 ft (30.5 m) round, nylon   | DoD standard price USD 8,496 (effective 1 Oct 2025) | 11.6 USD per m² of single-layer canopy (730 m² nominal); ~35 USD per m² of a three-layer ram-air equivalent (estimate) | NSN 1670-01-016-7841, https://highergov.com/nsn/1670010167841; diameter from the USMC G-11/G-12 info sheet, https://www.marcorsyscom.marines.mil/Portals/105/PfM/GCES/PM_ICE/Info%20Sheets/Reconnaissance%20Team/G11_G12_PIS_2018.pdf |

Our market price of 168 USD per flat m² sits at the retail price of sport wings,
which include dealer margin and VAT, and at Faggiani's series AWE kite price at
800 m². The military cargo parachute, a single-skin round canopy bought by the
thousand, sets a floor of ~35 USD/m² for three layers of cloth; our 84 USD/m²
manufacturing cost is 2.4× that, which a heavier, reinforced ship-kite cloth at
10× a paraglider's wing loading justifies. Above ~1,000 m² our linear cost per
m² is higher than Faggiani's A^0.75 (627 against 386 kUSD at 3,200 m²).
**Plausible for series production; conservative at the largest sizes.**

### Tether (79 USD/kg purchase)

Faggiani 2018 implies 79 USD/kg (EUR 9,000 for 1,500 m of 12 mm, Table 16.2);
Joshi et al. 2025 use 80 EUR/kg (93 USD/kg) plus ~10 % coating mass (§2.6.2);
retail Dyneema reels cost 145–150 USD/kg (`kite_costs_notes.md` §4d). No public
price for SK78/SK99 fibre per kg was found (only retail line per metre and a
2014 DSM notice of a 5 % price increase), so a fibre-plus-braiding build-up is
not possible. Diameters grow large: 36 mm at 800 m², 71 mm at 3,200 m², 113 mm
at 8,000 m²; offshore HMPE mooring ropes are made in such sizes, but no bulk
price was found. **Plausible as a series purchase price; the 8,000 m² rope is
outside any priced product.**

### Holding winch (27 k + 0.024 USD/N manufacturing; 54 k + 0.048 USD/N market)

| Benchmark                                                    | Price                                     | Per N          | Source                                                                                                                                                                                                                 |
| ------------------------------------------------------------ | ----------------------------------------- | -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Chinese deck mooring winches, 10–2,000 kN pull (asking, FOB) | USD 8,000–50,000                          | ~0.02 marginal | `kite_costs_notes.md` §4a (hnnucrane.en.made-in-china.com)                                                                                                                                                             |
| Yacht windlass, 15.6 kN (retail)                             | USD 6,940–9,045                           | 0.44–0.58      | same (defender.com)                                                                                                                                                                                                    |
| Faggiani 2018 drum + tether handling and bearings, 32 kN     | EUR 12,200                                | 0.44 USD/N     | Table 16.2                                                                                                                                                                                                             |
| AHTS towing winches, brake holding up to 670–750 t           | price on request, custom-built per vessel | —              | https://www.macgregor.com/Products/products/offshore-deck-machinery-equipment/anchor-handling-winches ; https://palfinger.com/worldwide/en/our-products/deck-equipment/winches/anchor-handling-and-towing-winches.html |

Up to 1,600 m² (800 kN, ~80 t) the holding force is in the range of ordinary
mooring winches, and our market price (58–92 kUSD) is 2–7× the Chinese FOB
asking prices, which covers class approval, controls and a brake rated above
pull. At 3,200 m² (1.6 MN, 163 t) and 8,000 m² (4 MN, 408 t) the brake load is
beyond ship mooring winches (brakes are designed to 80 % of line MBL, Wärtsilä)
and in the class of anchor-handling tug winches, which are custom-built; no
price was found, but 131–246 kUSD for a class-approved 160–400 t brake winch is
likely low (estimate). **Plausible to 1,600 m²; probably low above.**

### Launch mast (830 USD/m manufacturing; 237 kg/m with 30 % foundation, i.e. 3.5 USD/kg, 7.0 USD/kg market)

Chinese hot-dip galvanised telecom towers are listed at ~1,000–1,350 USD/t
(asking, FOB, 1 t minimum order; Accio listings via search, not opened),
lighting poles at 100–250 USD/m bare (`kite_costs_notes.md` §4b), and WISDEM's
supplier price for a finished wind tower is 2.9 USD/kg (`cost_basis_notes.md`
§0). Per kg our market price is 2.4× a wind tower and 5–7× a Chinese telecom
pole, so the steel itself is not underpriced. The flaw is scaling: the model
keeps one 0.8 m × 12 mm tube at every height, so an 89 m mast for 8,000 m² costs
only 148 kUSD and could not stand (height over diameter ~110, carrying a ~2.5 t
canopy and ship motions). Faggiani's launch-and-landing cost, c·M_kite·√A, gives
the same 121 kUSD as ours at 800 m² but 752 kUSD against our 168 kUSD (mast plus
head) at 3,200 m² (kite mass 0.3 kg/m² + 100 kg control unit). **Plausible at
160–1,000 m²; low above, because the cross-section does not grow with height.**

### Docking head (37 k manufacturing, the same at every size)

Chinese 5 t marine knuckle-boom cranes are listed at USD 5,100–90,000
(madeinchina.com listings via search); class-approved units (Palfinger, Sormec)
are price-on-request. A slewing gripper with hydraulics and an inflation fan at
37 k manufacturing / 74 k market is in that bracket for a 50–300 kg canopy. It
cannot be the same for a 2.4 t canopy at 8,000 m². **Plausible to ~1,000 m²; low
above.**

### Control unit (11 k + 15 USD/m² manufacturing)

Faggiani 2018 prices a series KCU for 100 m² at EUR 3,000 (Table 16.2); Joshi et
al. 2025 put avionics at EUR 15,000 for a prototype and EUR 150,000 for early
commercial units with aviation certification and redundancy (§2.6.1); integrated
servos with drives start at USD 698 (Teknic, `kite_costs_notes.md` §4c). Ours is
12.2 k manufacturing at 72 m², 4× Faggiani, and 59 k at 3,200 m². **Plausible;
certification could push it to the high value (22 k + 30 USD/m²).**

These rows compare at the sizes as sold, which are flat (section 6). At their projected areas, 125 and 250 m², our price is 10 and 15 % lower, from the hardware and today's canopy, so the ratios rise by about that.

## 3. Production volume and technology phase

### What "series production" implies

Every observed ship-kite price is 2.4–6× ours:

| Observed                                                              | Ours (market, incl. installation) | Ratio nominal                      | Ratio with ~50 % inflation since 2007–2009 (estimate from CPI) |
| --------------------------------------------------------------------- | --------------------------------- | ---------------------------------- | -------------------------------------------------------------- |
| SkySails 160 m², EUR 0.5 M (2007), 580 kUSD                           | 241 kUSD                          | 2.4                                | 3.6                                                            |
| SkySails 320 m², ~EUR 1 M "estimated selling price" (2009), 1.16 MUSD | 297 kUSD                          | 3.9                                | 5.9                                                            |
| AFP 2011: "Retailing at half a million and one million euros"         | —                                 | —                                  | —                                                              |
| EMSA 2023 Table 7, EUR 340–2,345 k asset                              | —                                 | 1.8–5.5 (`cost_basis_notes.md` §6) | —                                                              |

AFP source: https://terradaily.com/want-to-save-fuel-go-fly-a-kite-999/ (15 Apr
2011). Those prices came from a maker that never made a profit, so its cost was
likely above them.

With cost ∝ (cumulative units)^log2(1 − LR), a cost ratio R needs log(R)/−log(1
− LR) doublings. Starting from ~10 units (SkySails' "around ten towing kites
sold"):

| Ratio to close | LR 10 % | LR 15 % | LR 20 % |
| -------------- | ------- | ------- | ------- |
| 2.8            | 8,700   | 810     | 250     |
| 4.2            | 126,000 | 4,600   | 860     |
| 6.0            | 1.3 M   | 21,000  | 2,600   |

Learning rates: onshore wind 12 % (IRENA 2017,
https://www.irena.org/News/articles/2017/Mar/Onshore-Wind-Industry-Learning-Fast),
14.4 % for US installed cost 1982–2004 (Wiser & Bolinger,
https://escholarship.org/content/qt64g3z5r7/qt64g3z5r7.pdf), a literature mean
of ~22 % for wind farms (EPRI 2013 seminar slides,
https://eea.epri.com/pdf/epri-energy-and-climate-change-research-seminar/2013/2013_08.pdf),
and BVGA's 15 % for AWE to 2030. At 15–20 % our prices correspond to **roughly
250–5,000 cumulative units, central ~1,000** (estimate). Read the other way: at
unit 50 the cost is (50/1,000)^−0.234 = 2.0× the series cost at LR 15 %.

### Where the technology is today

- **SkySails (2007–2016):** ram-air kites of 160–400 m², "around ten" sold, four
  to five in operation at the peak, 1,200 automated flights and ~1,800 h of air
  time across the fleet; business liquidated in 2016 (`kite_costs_notes.md` §1).
  A system prototype in an operational environment, never sustained commercial
  operation: TRL 7, not 9, despite sales.
- **Airseas / K Line (2016–):** 500 m² Seawing on _Ville de Bordeaux_ from 2022
  with automated figure-eight flights (2023), five firm K Line units; business
  bought by K Line in 2024; phase one finished in June 2025 with a 300 m² kite
  on land at Dakhla, phase two about two years more (`kite_costs_notes.md` §2).
  TRL 6–7.
- **Other start-ups:** small kites (50–400 m²) on a handful of ships, with
  launch masts of ~10 m. TRL 7 at small size.
- Ship kites built to date: of order 10–20 units (estimate from the above). The
  target of the EU Seawing4Blue project was 1,000 Seawings by 2030
  (https://cinea.ec.europa.eu/featured-projects/seawing4blue_da); by comparison
  Norsepower, the most deployed rotor maker, had 32 rotor sails on 18 vessels in
  2025 (funding-news aggregator Techleap, Jul 2025, page not reachable; search
  snippet only).

**Verdict on production volume:** our prices are those of an Nth-of-a-kind product after
~1,000 cumulative units, about 50–100× the ship kites built so far. They are a
mature-market scenario, not the price a shipowner can buy at today.

## 4. Development cost and business case

### Funding of comparable developers

| Developer                 | Funding                                                                                                                                                                                       | Outcome                                                                       | Source                                                                                                                        |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| SkySails (ship kites)     | "funding of 47 million euros mostly from venture capital investors" by April 2011; one round of EUR 15 M in 2010 (DSM Venturing among investors)                                              | ~10 sold; marine business liquidated 2016                                     | AFP via terradaily.com (15 Apr 2011); https://www.chemistryviews.org/?p=29865 (search snippet)                                |
| Airseas (ship kite)       | EUR 1.2 M founding equity (10 % Airbus); ADEME aid EUR 7.2 M of which 4.45 M to Airseas; EU Seawing4Blue EUR 2.5 M of a 3.57 M budget; later equity and the K Line purchase price undisclosed | bought by K Line 2024, still in testing                                       | lejournaldesentreprises.com (search snippets); https://cinea.ec.europa.eu/featured-projects/seawing4blue_da                   |
| Norsepower (rotor sails)  | EUR 28 M Series C (2023); ~EUR 70 M in total since 2012 (2025, aggregator)                                                                                                                    | 32 rotors on 18 vessels; factory in China                                     | https://maritime-executive.com/corporate/norsepower-secures-28m-investment-to-expand-rotor-sail-production ; Techleap snippet |
| Kitepower (AWE)           | EUR 3 M (2021), > EUR 1 M crowdfunding (2022), "over €4.1 million" in total equity                                                                                                            | 100 kW product, small series                                                  | https://thekitepower.com/?p=14270 ; https://tudelft.nl/en/2022/lr/successful-crowdfunding-campaign-spin-off-company-kitepower |
| Ampyx Power (AWE)         | failed to close a EUR 15 M round in late 2021, insolvent                                                                                                                                      | bankrupt 2022                                                                 | https://siliconcanals.com/nl/ampyx-power-bankrupt-wind-energy-technology/ (search snippet)                                    |
| Makani (AWE)              | Google.org USD 15–20 M and ARPA-E USD 3 M before 2013; seven years inside Alphabet X, amount undisclosed                                                                                      | closed 2020: "the road to commercialization is longer and riskier than hoped" | https://spectrum.ieee.org/google-acquires-airborne-wind-power-company-makani ; https://en.wikipedia.org/wiki/Makani_(company) |
| AWE sector, public grants | "about ¤75 million has been awarded to date"                                                                                                                                                  | —                                                                             | BVGA 2022, p. 18                                                                                                              |

No source gives a total above USD 100 M for Makani; that figure is not used.
Certification: DNV-ST-0511 lists rotor sails, wing sails and ventilated foils
explicitly; other WAPS types are agreed case by case (GlobalSpec scope listing
of the 2022 edition), so a kite has no ready approval route. No fee for type
approval was found.

### Development cost estimate

**USD 100 M (range 70–150 M)** to a type-approved ship kite with a fleet track
record (estimate). Reasoning: SkySails spent EUR 47 M (~USD 55 M, ~USD 80 M
today) and did not reach a reliable product; Norsepower needed ~EUR 70 M to
reach 32 units of a mechanically simpler rig; the remaining work (autonomous
launch and recovery at sea, canopy endurance, a first-of-its-kind approval
route) is the part SkySails did not solve.

### Business case

Assumptions (all estimates unless sourced): an average system of 800 m², sold at
our market prices of 240 kUSD hardware without installation (the yard installs),
157 kUSD canopy and 30 kUSD tether = 427 kUSD; cost of goods 70 % of price at
series volume (F = 1.37 / (1 − 0.30), `cost_basis_notes.md` §1); before unit
1,000 the cost follows a 15 % learning curve from the ~10 units built, while the
price stays at the series level, because shipowners compare against rotor sails;
2,000 flight h a year per ship (IMO GreenVoyage2050: kite usable 20–30 % of the
time, https://greenvoyage2050.imo.org/technology/kite/), so one canopy a year
and one tether every two years, sold at the same margin; fixed engineering,
sales and service cost USD 15 M a year; development USD 100 M before the first
sale; 10 % discount rate.

| Ramp (units/yr)                             | Break-even (cumulative cash > 0) | Peak funding need | NPV over 20 years at 10 % |
| ------------------------------------------- | -------------------------------- | ----------------- | ------------------------- |
| Fast: 5, 10, 20, 40, 80, 120, 160, then 200 | year 12, ~1,400 units installed  | ~USD 213 M        | +105 MUSD                 |
| Fast, no spare-canopy sales                 | not within 20 years              | —                 | −152 MUSD                 |
| Fast, cost at series level from unit 1      | year 10                          | —                 | +173 MUSD                 |
| Fast, development 150 M                     | year 13                          | —                 | +55 MUSD                  |
| Slow: 2, 5, 10, 15, 20, 30, 40, then 50     | not within 20 years              | > USD 290 M       | −201 MUSD                 |
| Fast, canopy at USD 234/m², 187.5 kUSD      | year 12                          | ~USD 215 M        | +154 MUSD                 |
| Fast, canopy at USD 150/m², 119.8 kUSD      | year 13                          | ~USD 213 M        | +42 MUSD                  |
| Fast, USD 234/m², canopy life 4,000 h       | year 13                          | ~USD 215 M        | +15 MUSD                  |
| Fast, USD 150/m², canopy life 4,000 h       | year 15                          | ~USD 214 M        | −47 MUSD                  |

Each year's cash is (sales + spares) × (1 − 0.7·f(n)) − 15 MUSD, with n the units sold so far and f(n) = (min(n + 10, 1000)/1000)^log2(0.85), per unit within a year's sales and 1 at series level. Spares are, for each ship sold in the 15 years before, half a tether and a canopy per canopy life at 2,000 flight h a year. Cash is discounted from the end of its year. This reproduces the first five rows within 2 MUSD. The last four set the canopy price and life in the same sum; hardware and tether stay as above.

Two findings. First, the hardware sale alone never pays back the development: at
a 30 % gross margin a 427 kUSD system leaves 128 kUSD before fixed costs, and
the business depends on canopy replacements, which over a 15-year ship life are
worth ~6× the first sale. Second, it only works at ~100–200 systems a year,
which is ten times the whole wind-propulsion market's current output of any
single rig maker (Norsepower: 32 rotors in 13 years). At SkySails' or
Norsepower's historical pace it does not break even.

## 5. Overall verdict and suggested input changes

Per component, the kite inputs are consistent with a mass-produced product:
canopy, tether and control unit sit at or near series AWE assumptions and retail
sport-wing prices, steel is not underpriced per kg, and the shared components
put into a pumping AWE system give a high, not a low, LCOE (250 EUR/MWh base
against 96–150 in the literature). As a system price they correspond to ~1,000
cumulative units, 50–100× the ship kites built so far, so they describe a mature
market that no ship-kite maker has reached. Two inputs do not scale with kite
size and make the kite too cheap above ~1,000–1,600 m²: the mast (fixed tube)
and the docking head (fixed cost); the winch per N is probably low above ~1,600
kN.

Suggested changes:

| Input                                                                                             | Change                                                                                                                                                                                                  | Why                                                                                                            |
| ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `winch_cost_per_force`                                                                            | run the high value (0.084 USD/N) for kites above ~3,200 m²                                                                                                                                              | brake loads above ~150 t are in the custom anchor-handling-winch class                                         |
| `market_price_factor`                                                                             | keep 2.0 as the mature-market base; add a near-term case at 2.5 together with high mast, head and winch values, which comes to ~2× the base system price, the cost at unit ~50 on a 15 % learning curve | the base corresponds to ~1,000 cumulative units                                                                |
| canopy cost and life, `tether_price`, `tether_lifetime`, `control_unit_cost`                      | keep                                                                                                                                                                                                    | supported by the cross-industry and AWE checks                                                                 |

Report the kite results as a series-production scenario, and state alongside
them that the business behind it needs ~USD 200 M of funding, ~150–200 systems a
year and canopy replacement revenue to break even in about 12 years.

## 6. Aspect ratio and area basis of towing kites

The base kite has a projected aspect ratio of 3. On the shape in `kite_polars/wing_polars.jl` (arc with projected span 0.82 of flat span, tip chord 0.4 of root) flat area is 1.185 times projected area, so flat aspect ratio = 3 × (1/0.82)² / 1.185 = 3.76. The value is one used by industry, from an industrial design known to the authors without a public reference.

| Kite | Area | Span | Aspect ratio | Source |
| ---- | ---- | ---- | ------------ | ------ |
| SkySails ship kite | "Flat size of 225 m²", 160 kN | none | "projected aspect ratio lower than 2" | Paulig et al. 2013, pp. 552, 561 |
| SkySails ship kite | 160 m², by the same naming flat | "projected span ... about 14 m" | 1.6 at 125 m² projected | Paulig et al. 2013, Fig. 32.5 |
| Ram-air wing from SkySails Power, not stated to be a ship kite | 160 m² total, 125 m² projected | 15.2 m projected | 1.86 projected, stated | Folkersma, Schmehl & Viré 2020, Table 1 |
| SkySails ship kites | 320 m² | none | "moderate", "very low", no number | Penloup et al. 2021, pp. 2, 17 |
| Airseas Seawing | 1,000 m² "sail surface", basis not stated | none | none | Airseas web page |

Paulig et al. also compare flat aspect ratios of 4.8 and 2.7 in CFD (Fig. 32.1) and give glide ratios of 4 to 5.

At projected 2 the polar method on this shape gives drag below zero up to 2° and a maximum L/D of 39; at 2.5 it gives a usable polar and at 1.86 drag below zero up to about 8°. The polar at 3 reproduces to 2.4e-7.

**Area basis.** Paulig et al. state a flat size only for the 225 m² kite. The 160 m² kite reads the same way, as 160 m² total goes with 125 m² projected in Folkersma et al. and its 14 m span then gives an aspect ratio below 2; the 320 m² kite is inferred from the naming. All inputs here are on projected area, at 1.28 flat over projected, the one pair in a source read in full (160 / 125, Folkersma et al. 2020). The PN-14 data sheet, seen only as a search snippet, lists 90 m² projected and "up to 180 m²" flat, 2.0, which is not used: this shape has 1.185. At 2.0 the 160 m² kite would be 80 m² and its mast 1.68 √A, inside the range below. This takes 160 m² to 125 m², 225 to 176 and 320 to 250. Inputs:

| Input | Reading on projected area | Value (range) |
| ----- | ------------------------- | ------------- |
| Mast height ratio | 15 m on 125 m²: 1.34; Airseas 35 m on 1,000 m²: 1.11 projected, 1.25 flat; PN-14 19 m on 90 m²: 2.0 | 1.3 (0.8–2.0) |
| Tether over span at aspect ratio 3 | 300 m on 125 m²: 15.5; about 360 m on 250 m² (Paulig p. 554): 13.1; 19.7 on the kite's own 15.2 m | 13, from the larger kite (10–20) |
| Turn radius over span at aspect ratio 3 | 45 m on 125 m², bounds 29 and 83 m | 2.3 (1.5–4.3) |
| Force per area | 160 kN on 225 m² flat, about 0.7 (Paulig p. 557): 0.9 on projected | 0.5, a stated choice (0.4–1.0) |

**Canopy mass.** Paulig gives 0.5–0.6 kg/m² for kites of 160–320 m² and 120 kg with lines for the 225 m² kite on cloth slightly above 100 g/m², which is 0.68 kg/m² projected.
