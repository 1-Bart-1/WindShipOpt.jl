# Ship size classes: sourcing notes

Sources behind every value in `ship_classes.csv`. Built 2026-10-31. Units: m, kn, kW, GT, USD, USD/t, persons, ships, fraction of fuel.

## Column definitions

- `length`: length between perpendiculars Lpp. Where a source gives only LOA, Lpp is an engineering estimate from the Lpp/LOA ratio of the MAN tables (0.95–0.98); the row says so.
- `draft`: design draught, the draught of the average loaded ship in service on which the propulsion plant is designed and at which the sources rate speed and power (MAN bulk, p. 7). Bulk carriers and the MR tanker: MAN's Tdesign; feeder: Deltamarin A.Delta2300 (8.75 m at the same 10.0 m scantling draught; Marine Link, 13 Aug 2015, `paper/literature_pdfs/marinelink2015_adelta2300.txt`); Panamax, Neo-Panamax and Megamax: scantling draught × 13.0/14.5, the design/scantling ratio of the Knud E. Hansen 12,500 TEU design (KEH 01016, `keh_12500teu.pdf`; engineering estimate); Aframax: scantling × 11.0/12.2 of MAN MR (engineering estimate); VLCC: Vive Ut Vivas design draught 20.5 m (Baird Maritime 9 Oct 2026); PCTC: Höegh Aurora 9.35 m (Deltamarin); coaster: summer draught, the only one published.
- `scantling_draft`: scantling (maximum summer) draught, the draught at which `deadweight` is quoted.
- `block_coefficient`: derived at the design draught, not published. At the scantling draught Cb_s = dwt (1 + lwt/dwt) / (1.025 · Lpp · B · Ts), with lwt/dwt inside the range of MAN ES, _Basic Principles of Ship Propulsion_ (2018), Table 1.01: crude tanker 0.13–0.20, product 0.15–0.30, bulk 0.13–0.30, container liner 0.28–0.34, feeder 0.34–0.41, ro-ro 0.6–1.4 (chosen values in the CSV `source` field). The layer between the draughts is taken off wall-sided with the model's own waterplane coefficient, Cwp = 0.763 (Cb_s/0.99 + 0.34): Cb = (Cb_s Ts − Cwp (Ts − T)) / T. Check: the KEH 12,500 TEU design loses 25,000 t of deadweight over 1.5 m, Cwp 0.79, against 0.77 from the estimate.
- `service_speed`: speed of the source design (MAN "average speed" at SMCR with 15 % sea margin; Höegh Aurora's 14.5 kn service speed, Baird Maritime), except VLCC, where it is the IMO 2018 fleet-average design speed (Table 35) that pairs with the IMO fleet-average power. The model does not use it; each class's engine is rated at `power`.
- `operating_speed`: IMO Fourth GHG Study 2020, Table 35, "average speed over ground at sea", year 2018, for the matching size bin. This is the slow-steaming speed actually sailed.
- `power`: specified MCR (SMCR) of the main engine of the source design; the model rates every drive of the class to deliver this power through a shaft (efficiency 0.96) to the propeller. PCTC: the Höegh Aurora's rating is not published; the 13,710 kW SMCR of the Knud E. Hansen 8,600 CEU DF PCTC (KEH 22014, design draught 9.30 m, 19.0 kn at 90 % SMCR) stands in.
- `newbuild_price`: Allied Shipbroking weekly report week 43, data as of 23 Oct 2026 (indicative Chinese-built bulkers, Korean-built tankers; reference sizes Capesize 180k, Kamsarmax 82k, Ultramax 64k, Handysize 40k, VLCC 310k, Aframax 110k, MR 52k dwt), or a named 2025–2026 contract.
- `cargo_value`: value of one tonne of the typical cargo, FOB-level.
- `fleet`: IMO Table 35 "Type 1 and 2" vessels (international, AIS-observed, 2018) in the matching size bin.
- `fuel_share`: CO2 of the bin over total 2018 shipping CO2 in Table 35 (1,056.5 Mt, international + domestic + fishing; matches the study's 1,056 Mt headline). CO2 stands in for fuel; HFO, MGO and LNG differ by a few percent in carbon factor.

## Primary documents (all downloaded and read)

| Short name    | Document                                                                                                          | URL                                                                                                                      |
| ------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| IMO GHG4      | IMO, Fourth IMO GHG Study 2020, Table 35 (printed p. 99–101)                                                      | local copy `data/market/raw/imo/ghg4.pdf`                                                                                |
| MAN bulk      | MAN Energy Solutions, Propulsion trends in bulk carriers, 5510-0237-01ppr, Sep 2022, Tables 1, 4–6                | https://man-es.com/docs/default-source/marine/tools/propulsion-trends-in-bulk-carriers.pdf                               |
| MAN container | MAN Energy Solutions, Propulsion trends in container vessels, 5510-0239-01ppr, Feb 2024, Tables 1, 2, 19; Fig. 20 | https://man-es.com/docs/default-source/marine/tools/propulsion-trends-in-container-vessels.pdf                           |
| MAN MR        | MAN Energy Solutions, Propulsion of 46,000–50,000 dwt MR tankers, 5510-0224-00ppr, Jan 2019, Table 1              | https://www.man-es.com/docs/default-source/document-sync/propulsion-of-46-000-50-000-dwt-mr-tankers-eng.pdf              |
| MAN basic     | MAN Energy Solutions, Basic Principles of Ship Propulsion, 2018, Table 1.01                                       | man-es.com                                                                                                               |
| Allied 2026   | Allied Shipbroking, Weekly Market Report week 43, 27 Oct 2026, p. 7                                               | https://cyprusshippingnews.com/wp-content/uploads/2026/10/ALLIED-Weekly-Market-Report-Week-43.pdf                        |
| Allied 2025   | Allied Shipbroking, Weekly Market Report week 44, data 31 Oct 2025                                                | https://cyprusshippingnews.com/wp-content/uploads/2025/11/ALLIED-Weekly-Market-Report-Week-44.pdf                        |
| World Bank    | World Bank Commodity Price Data (Pink Sheet), 2 Oct 2026, 2025 annual averages                                    | https://thedocs.worldbank.org/en/doc/74e8be41ceb20fa0da750cda2f6b9e4e-0050012026/related/CMO-Pink-Sheet-October-2026.pdf |

The MAN paper _Propulsion trends in tankers_ is listed on the MAN/Everllence site but its URL returns 404; the Aframax and VLCC rows therefore use named ships and IMO fleet averages.

## Per class

### 1. General cargo coaster, 3,800 dwt

- L 85, B 13.2, T 5.5, Cb 0.83, 10.5 kn: project reference in `assumptions.yaml` (Damen CF3850 / Conoship CIP3800 / Ferus Smit 4300 datasheets).
- Power 1,454 kW, 8.8 kn at sea, 4,880 ships, 18.9 Mt CO2: IMO GHG4 Table 35, general cargo 0–4,999 dwt. The bin's mean ship is only 2,104 dwt and another 8,416 domestic or inactive (type 3/4) hulls sit outside the count, so power is low and the fleet count is a floor for coastal trade.
- Price USD 11.6 M: Udupi Cochin 3,800 dwt series (Onmanorama, 15 Jun 2023), as in `assumptions.yaml`. A Dutch build costs more (Royal Bodewes EcoTrader 6,750 dwt ~EUR 17 M, Meriaura Apr 2024).
- Crew 7: engineering estimate, same as the `crew_cost` reasoning in `assumptions.yaml`.
- Cargo value 250 USD/t: engineering estimate for agribulk, fertiliser, steel and forest products; wheat HRW 243 USD/t, urea 423 USD/t, coal 108 USD/t (World Bank 2025 averages). Aggregates are far cheaper, steel coils dearer.
- Air draft: Kiel Canal bridges ~40 m (130 ft; Maritime Reporter, Jul 2010).

### 2. Feeder container ship, ~1,600–1,800 TEU

- L 165, B 25.6, T 10.0, 21,000 dwt, 18.9 kn, 10,500 kW: MAN container Table 19, 1,600 TEU column.
- Price USD 33 M: Euroseas 1,800 TEU feeders ~USD 32.3–33 M each (Hellenic Shipping News / Riviera, 2025; https://www.hellenicshippingnews.com/euroseas-ltd-announces-order-for-the-construction-of-two-additional-feeder-1800-teu-containerships/); Allied 2026 records 2 x 1,928 TEU at Huangpu Wenchong for Hai An at USD 33.5 M. Brokers put a Chinese-built 1,800 TEU at ~32 M, Korean ~37 M.
- IMO bin container 1,000–1,999 TEU: 1,271 ships, 13.4 kn, mean design speed 19.0 kn, 12,083 kW, 28.0 Mt CO2.
- GT not found for a representative ship.
- Crew 18: engineering estimate.

### 3. Handysize bulk carrier, ~40,000 dwt

- L 177, B 30.5, T 11.5, 42,000 dwt, 14.0 kn, 6,500 kW: MAN bulk Table 4, 42,000 dwt column. Real check: Vigor OL Brave (Tsuneishi, 2026), LOA 179.9, B 32.2, T 10.78 summer, 42,200 dwt, 26,700 GT, 5,680 kW (Baird Maritime, 26 Aug 2026; https://www.bairdmaritime.com/amp/story/shipping/dry-cargo/bulkers/vessel-review-vigor-ol-brave-handysize-bulker-optimised-for-coal-grain-and-steel-transport). Norse Ozukuma (Imabari group) 40,262 dwt, 25,240 GT.
- Price USD 31.0 M (Allied Oct 2026, 40k dwt); 29.5 M a year earlier (Allied Oct 2025); KOBC 31.25 M (ShipUniverse, Oct 2026).
- Fleet/fuel: IMO bin 10,000–34,999 dwt (2,014 ships, mean 27,303 dwt, 11.0 kn, 20.0 Mt). **Caveat:** modern 35–42k Handysizes fall in IMO's 35,000–59,999 bin with the Supramaxes; the IMO bins do not follow industry class names.
- Opex: Pacific Basin, Handysize USD 4,500/day (2024 interim report; via `assumptions.yaml`).

### 4. Ultramax (Supramax) bulk carrier, ~64,000 dwt

- L 196, B 32.2, T 13.4, 64,000 dwt, 14.5 kn, 8,600 kW: MAN bulk Table 5, 64,000 dwt column (EEDI phase 2 variant; phase 3 variant 6,500 kW at 13.6 kn).
- GT 35,638: Spar Maia / Century Zhengzhou, Nantong Xiangyu, 63,550 dwt, LOA 199.85, B 32.26 (Baird Maritime, 25 Oct 2024).
- Price USD 34.5 M (Allied Oct 2026); KOBC 35.78 M.
- Fleet/fuel: IMO bin 35,000–59,999 dwt (3,391 ships, mean 49,487 dwt, 11.4 kn, 45.7 Mt). **Caveat:** 60–64k Ultramaxes themselves sit in IMO's 60,000–99,999 bin with the Kamsarmaxes.
- Opex: Pacific Basin Supramax USD 4,910/day (2024 interim).
- Cargo value 180 USD/t: engineering estimate, a mix of coal (108) and grain (243) plus minor bulks.

### 5. Kamsarmax bulk carrier, ~82,000 dwt

- L 225 (Lpp) and 9,700 kW: MAN bulk Table 5, 84,000 dwt column (LOA 229, the Kamsar, Guinea, port limit).
- B 32.26, T 14.4, 82,000 dwt, 14.5 kn, ~43,500 GT: Tsuneishi Kamsarmax 82 (Ultra Lion class 81,600 dwt, ~43,400 GT, 14.4 m full-load draught; later Defender class 82,400 dwt, 44,000 GT; Tsuneishi press releases and JSEA SAMEIJ 2024).
- Price USD 37.5 M (Allied Oct 2026); recent contracts 37.0–37.5 M (Eurodry, Yangzijiang Maritime, Oct 2026).
- Fleet/fuel: IMO bin 60,000–99,999 dwt (3,409 ships, 11.4 kn, 63.0 Mt = 6.0 % of all shipping CO2, the largest single bulk bin).
- Cargo value 170 USD/t: engineering estimate, grain/coal mix.

### 6. Capesize bulk carrier, ~180,000 dwt

- L 282, B 45, T 18.3, 14.6 kn, 16,250 kW: MAN bulk Table 6, 175,000 dwt column; a 180k hull uses the same LOA 292 x 45 m (U-Ming 180k at CSSC Beihai: LOA 292, B 45, structural draught 18.2 m, Baird Maritime).
- GT 92,996: HUI JI HAI, Qingdao Beihai 2021, 181,415 dwt, LOA 291.97, B 45, T 18.4 (Marine Link vessel record).
- Price USD 75.0 M (Allied Oct 2026); 71.5 M a year earlier.
- Fleet/fuel: IMO bin 100,000–199,999 dwt (1,242 ships, 11.2 kn, 39.0 Mt). The 200,000+ bin (Newcastlemax, VLOC; 516 ships, 22.0 Mt, 2.1 %) is not in the CSV.
- Cargo value 100 USD/t: iron ore 2025 average 100.2 USD/dmt (World Bank).

### 7. MR product tanker, ~47,000–50,000 dwt

- L 174, B 32.2, T 11.0 design (12.2 scantling), 47,000 dwt, 15.1 kn, 9,310 kW (layout M3, 6G50ME-C9.6, 6.7 m propeller, 15 % sea margin, 10 % engine margin): MAN MR Tables 1 and 2.
- Price USD 51.0 M (Allied Oct 2026, 52k dwt reference); 52.0 M Oct 2025; KOBC 50.54 M.
- Fleet/fuel: IMO codes MR tankers as either oil tanker 20,000–59,999 dwt (615 ships, 13.8 Mt) or chemical tanker 40,000+ dwt (1,289 ships, 28.2 Mt); the CSV sums both (1,904 ships, 42.0 Mt). Operating speed 11.9 kn from the chemical bin (oil bin: 11.2 kn).
- Cargo value 650 USD/t: engineering estimate; Brent 2025 69.0 USD/bbl x 7.33 bbl/t = 506 USD/t crude, plus ~30 % for refined products. Not taken from a published product price series.
- GT not found.

### 8. Aframax / LR2 tanker, ~115,000 dwt

- B 44.0, T 15.4 (summer), 114,824 dwt, 14.15 kn service, 10,300 kW (6G60ME-C10.5 at 75.9 rpm), 60,177 GT, crew 25: Arion, Sumitomo Heavy Industries, for JHI Steamship (Baird Maritime vessel review, 18 Jun 2026; https://www.bairdmaritime.com/amp/story/shipping/tankers/vessel-review-arion-jhi-steamships-new-aframax-tanker-built-for-regional-and-intercontinental-trade). LOA 243.8 m; Lpp 236 is an engineering estimate (0.966 LOA). Chinese designs are longer: SWS 114k series LOA 249.95, B 44.0, scantling 15.0 m.
- The IMO 80–120k bin averages 13,319 kW at 14.8 kn design speed; Arion is a low-power eco design.
- Price USD 75.0 M (Allied Oct 2026); contract JHI Steamship 115k at K Shipbuilding ~73 M (Allied Oct 2025).
- Fleet/fuel: IMO oil tanker 80,000–119,999 dwt (1,029 ships, 11.2 kn, 31.1 Mt).
- Opex: Frontline LR2 USD 7,600–12,400/day in 2025 quarters incl. drydock (Frontline Q1–Q4 2025 results).
- Cargo value 506 USD/t: Brent 2025 (World Bank) x 7.33 bbl/t.

### 9. VLCC, ~300,000 dwt

- B 60, T 21.58, 301,781 dwt: Pertamina Pride, JMU, LOA 330, 7G80ME-C9.5 (Baird Maritime, 16 Feb 2021). Lpp 320 is an engineering estimate (0.97 LOA).
- GT 162,000 (specification estimate) and crew 30: Vive Ut Vivas, Jiangsu Hantong, 319,906 dwt, LOA 332.99, B 60, design draught 20.5, design speed 14.5 kn, delivered 26 Jun 2026 (Baird Maritime, 9 Oct 2026).
- Design speed 15.5 kn and 27,159 kW: IMO fleet average, oil tanker 200,000+ dwt; new eco VLCCs are designed for ~14.5 kn with less power.
- Price USD 130.0 M (Allied Oct 2026, 310k Korean); COSCO 307k at Dalian ~119 M (Allied Oct 2025, Chinese-built).
- Fleet/fuel: 755 ships, 11.9 kn, 45.3 Mt (4.3 %).
- Opex: Frontline VLCC USD 8,400–9,600/day in 2025.

### 10. Panamax container ship (old Panamax), ~4,000–4,500 TEU

- L 245, B 32.2, T 12.5, 51,000 dwt, 21.1 kn, 22,800 kW: MAN container Table 19, 4,000 TEU column (the IMO bin mean is 52,372 dwt). The 5,100 TEU column (Lpp 280, 63,500 dwt, 28,500 kW) is the maximum old-Panamax size.
- Price USD 58 M: MPC Container Ships 4,500 TEU at Jiangsu Hantong, USD 58 M each (2025); MPCC 4 x 4,500 TEU at Taizhou Sanfu for USD 228 M; Euroseas 4,300 TEU at Jiangsu New Yangzi USD 59.25 M. **Caveat:** these newbuilds are wide-beam (non-Panamax) designs; narrow 32.2 m Panamaxes are no longer ordered.
- Panama Canal old locks: max ship 295 x 32.2 x 12 m, height 57.9 m (MAN container Table 2).
- Fleet/fuel: IMO container 3,000–4,999 TEU (815 ships, 14.7 kn, 39.4 Mt).
- Opex: Global Ship Lease USD 7,809/ownership day Q1 2025 (company release), ~8,231 for 2025 (secondary).

### 11. Neo-Panamax container ship, ~14,000 TEU

- L 350, B 50.8, T 16.0, 152,000 dwt, 22.4 kn, 49,400 kW: MAN container Table 19, 14,000 TEU column. New Panama locks: max ship 366 x 51.25 x 15.2 m, height 57.9 m (MAN container Table 2).
- Price USD 152.5 M: 2 x 14,000 TEU at Hudong-Zhonghua for Zhonggu Logistics (Allied, 16 Oct 2026). Yang Ming 13,000 TEU LNG dual-fuel at 185–204 M per ship (2026) shows the spread with fuel and yard.
- Fleet/fuel: IMO container 12,000–14,499 TEU (227 ships in 2018, 16.3 kn, 22.0 Mt). The fleet has grown strongly since 2018.

### 12. Megamax container ship, ~24,000 TEU

- L 398, B 61.5, T 16.5, 230,000 dwt, 21.7 kn, 60,000 kW: MAN container Table 19, 24,000 TEU column. MSC Irina (Yangzijiang, 2023): 24,346 TEU, LOA 399.99, B 61.3 (gCaptain, Adani Ports). GT 236,184 and dwt ~236,000 from a vessel database (gocomet), not checked against Equasis (IMO 9929429).
- Price USD 267.3 M: Evergreen 6 x 24,000 TEU LNG dual-fuel at Hanwha Ocean, per Hanwha's exchange filing, the highest container-ship price recorded (Alphaliner, via India Seatrade News, Apr 2026). Hapag-Lloyd paid ~164 M for megamaxes at the same yard in 2020; a conventional-fuel megamax costs much less.
- Fleet/fuel: IMO container 20,000+ TEU: only 44 ships and 3.5 Mt in 2018. **Caveat:** this class has grown several-fold since 2018 (MSC Irina/Tessa classes, Evergreen, ONE, HMM orders); 2018 numbers understate today's share.
- Air draft: Suez Canal Bridge 70 m above water, 68 m usable air draft (Waypoint Ports, Suez special restrictions); Great Belt East Bridge ~65 m (Baltic access); Bayonne Bridge 215 ft (65.5 m) at mean high water after the 2017 raise (PANYNJ). These caps limit the height of any rotor, sail or kite mast.

### 13. PCTC car carrier, ~7,000–9,000 CEU

- B 37.62, scantling T 10.8, 25,563 dwt, 84,074 GT, 14.5 kn service, 7S60ME-C10: Höegh Aurora, 9,100 CEU, China Merchants Heavy Industry Jiangsu, LOA 199.92 (Baird Maritime, 7 Aug 2024). Design draught 9.35 m (Deltamarin reference sheet). Lpp 192 is an engineering estimate (0.96 LOA).
- Power 13,710 kW: SMCR of the Knud E. Hansen 8,600 CEU DF PCTC (8S60ME-C10.5-GI; KEH 22014, 2022), the nearest published design; the Aurora's rating is not published.
- 15.5 kn at sea, 487 ships, 17.5 Mt: IMO vehicle carrier 50,000+ GT (fleet design speed 19.9 kn, 14,588 kW).
- Price USD 100 M: 2 x 8,600 CEU LNG dual-fuel at Zhoushan Changhong for Global Car Carriers (MSC), c. 100 M each (Allied, 23 Oct 2026).
- Cargo value 15,000 USD/t: engineering estimate, ~USD 22,000 per exported car at ~1.5 t. Not from a trade-value series.

## Cross-class data

### Cargo value

| Cargo         | Value         | Source                                                                                                                                                                           |
| ------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Iron ore      | 100.2 USD/dmt | World Bank Pink Sheet, 2025 annual average                                                                                                                                       |
| Coal          | 108.4 USD/t   | World Bank, Australia, 2025                                                                                                                                                      |
| Wheat         | 243.3 USD/t   | World Bank, US HRW, 2025                                                                                                                                                         |
| Maize         | 203.2 USD/t   | World Bank, 2025                                                                                                                                                                 |
| Soybeans      | 414 USD/t     | World Bank, 2025                                                                                                                                                                 |
| Crude oil     | 506 USD/t     | Brent 69.0 USD/bbl (World Bank, 2025) x 7.33 bbl/t                                                                                                                               |
| Containerised | 5,120 USD/t   | 52,239 USD per TEU (Seabury Global Ocean Trade database, 2020, via Rodrigue, Port Economics, Management and Policy) over 10.2 t of goods per loaded TEU (Eurostat EU main ports) |

2026 prices are higher: Brent averaged 104 USD/bbl in Q2 2026 (World Bank), so the crude cargo value is the 2025 average. Other per-TEU estimates: UNCTAD-derived ~54,500 USD/TEU (Port Economics), Hoffmann 2017 ~43,500 USD/TEU (LinkedIn comment); Australian import TEU A$33,238, export A$29,350.

### Opex and crew

Crew numbers are published only for Arion (25) and Vive Ut Vivas (30); the others are engineering estimates in the 18–28 range of ocean-going cargo ships. Daily operating cost (crew, stores, repairs, insurance, management), 2024–2025:

- Handysize USD 4,500/day, Supramax USD 4,910/day: Pacific Basin 2024 interim report.
- VLCC USD 8,400–9,600/day, Suezmax 7,600–8,900, LR2 7,600–12,400 (incl. drydock): Frontline quarterly results 2025.
- Container (mixed 2,000–11,000 TEU fleet) USD 7,809/ownership day Q1 2025: Global Ship Lease. Feeders: Euroseas ~USD 7,249/day (2024 analyst note, secondary).
- Drewry fleet-wide average USD 7,474/day in 2022 (secondary citation). Drewry puts manning at over half of opex.

### Fleet and fuel ("where does wind matter")

The 13 rows cover 21,468 ships and 39.3 % of 2018 shipping CO2. Largest bins not in the CSV, all IMO Table 35, 2018: container 5,000–7,999 TEU 40.7 Mt (3.9 %) and 8,000–11,999 TEU 57.9 Mt (5.5 %); bulk 200,000+ dwt 22.0 Mt; oil tanker 120,000–199,999 dwt (Suezmax) 24.7 Mt; LNG carriers 100,000–199,999 m3 37.5 Mt; cruise 60,000+ GT 22.9 Mt; service tugs 40.3 Mt; fishing 40.0 Mt.
