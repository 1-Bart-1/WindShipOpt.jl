# Literature review: kites, wing sails and rotors on cargo ships

Working notes for the paper "Kites, wing sails or rotors: where each wind-assisted propulsion technology pays on cargo ships, from coasters to Panamax size". BibTeX keys refer to `literature.bib`, or to `refs.bib` where marked (refs). Compiled 2026-10-31.

**How the entries were verified.** Every DOI below was resolved through doi.org and Crossref, which returned the title, authors, volume and pages used in `literature.bib`. Reports without a DOI were checked on the publisher's own page (EMSA, ICCT, EU LIFE, Tyndall/Manchester, TU Delft repository, Journées de l'Hydrodynamique proceedings). `sources.csv` records what is held and what has been read.

## 1. Papers that compare several wind technologies

**traut2014** — Traut, M., Gilbert, P., Walsh, C., Bows, A., Filippone, A., Stansby, P., Wood, R. (2014). Propulsive power contribution of a kite and a Flettner rotor on selected shipping routes. _Applied Energy_ 113, 362–372. DOI 10.1016/j.apenergy.2013.07.026.

- Compares: one Flettner rotor of 175 m² and one towing kite of 500 m².
- Method: performance models of rotor and kite combined with wind data along five trade routes. Fixed ship speed, great-circle routes, no routing, no economics. The kite is a force model, not a trajectory optimisation from geometry.
- Numbers: average power contribution 193–373 kW per rotor and 127–461 kW for the kite; which device wins depends on the route; the rotor varies less. Their conclusions give main-engine fuel savings of 2–24 % (rotor) and 1–32 % (kite); their Table 1 gives 2–21 % and 1–32 % of propulsive power demand. Route means are about equal: 244 kW rotor, 250 kW kite. Three rotors on a 5500 dwt general cargo ship could supply more than half the main-engine power when slow steaming.
- Relevance: the closest predecessor in _Applied Energy_. Same question (kite vs rotor, route dependence), but no wing sails, no ship-size sweep, no routing and no cost. Our kite comparison against rotors must be read against theirs.

**lu2020** — Lu, R., Ringsberg, J. W. (2020). Ship energy performance study of three wind-assisted ship propulsion technologies including a parametric study of the Flettner rotor technology. _Ships and Offshore Structures_ 15(3), 249–258. DOI 10.1080/17445302.2019.1612544.

- Compares: Flettner rotor, wingsail, DynaRig. No kite.
- Method: 4-DOF performance model (ShipJOURNEY/ShipCLEAN family) on recorded voyages; constant ETA; no routing ("smart routing ... is likely to increase the fuel savings even" further, they write).
- Ships and routes: Aframax tanker (250 m) on Cape Lopez (Gabon)–Point Tupper (Canada) and Angra dos Reis (Brazil)–Rotterdam; parametric rotor study also on a Handysize bulk carrier (180 m).
- Numbers: 5.6–8.9 % fuel saving; the rotor gives the largest, then the wingsail, then the DynaRig. Rotor size and operation must match ship type, speed, route and weather.
- Relevance: a like-for-like rotor/wing comparison with a 4-DOF force balance. It is the comparison we extend: we add the kite, ship size, routing and cost.

**bentin2016** — Bentin, M., Zastrau, D., Schlaak, M., Freye, D., Elsner, R., Kotzur, S. (2016). A new routing optimization tool – influence of wind and waves on fuel consumption of ships with and without wind assisted ship propulsion systems. _Transportation Research Procedia_ 14, 153–162. DOI 10.1016/j.trpro.2016.05.051.

- Compares: ships with and without WASP inside a weather-routing tool (A*-type path search on a tree of candidate routes).
- Relevance: one of the first to put WASP inside route optimisation. Exact technologies and percentages not confirmed from the full text.

**bentin2018** — Bentin, M., Kotzur, S., Schlaak, M., Zastrau, D., Freye, D. (2018). Perspectives for a wind assisted ship propulsion. _International Journal of Maritime Engineering_ 160(A1). DOI 10.5750/ijme.v160iA1.1043. (Crossref lists the record date as 2021; the volume is the 2018 one.)

- Compares: kite, Flettner rotor and DynaRig, one size each, routed on three routes; results shown only for a 17,500 dwt carrier at 13 kn. Full notes in `literature_core.md` §8.
- Findings: routing adds about 10 percentage points on the North Atlantic, up to 35 % saving with the DynaRig, for about 2 % more voyage time.
- Relevance: the closest earlier work to ours. It has no wing sail, no leeway, heel or rudder balance, one speed, and cost only as a rough break-even fuel price of 500 €/t over 5 years or 250 €/t over 10. **We must cite it and say so.**

**cedelft2016** — CE Delft, Tyndall Centre, Fraunhofer ISI, Chalmers (2016). _Study on the analysis of market potentials and market barriers for wind propulsion technologies for ships._ European Commission, DG Climate Action. DOI 10.2834/68747.

- Compares: rotors, wingsails, kites (400 m²) and wind turbines on sample bulkers, tankers and other ship types and sizes, on typical worldwide trades, at two speed scenarios.
- Numbers: rotors and wingsails give comparable savings, 5–18 % in the high-speed scenario; relative savings on the larger ships exceed those on smaller ones, especially for bulk carriers; **kites perform better on smaller vessels**; turbines save least. EMSA quotes the kite at 1–9 % power saving at higher speeds and 2–15 % at lower speeds. Market potential 2030: 3700–10 700 installed systems.
- Method: no weather routing; market/barrier analysis with simple economics.
- Relevance: the only source I found that states a ship-size ranking across kite, rotor and wing. Our result on which rig suits which size can be checked against it.

**emsa2023** (refs) — Laursen, R., Patel, H., Sofiadi, D., Zhu, R., Nelissen, D., Van Seters, D., Pang, E. (ABS, CE Delft, Arcsilea) (2023). _Potential of Wind-Assisted Propulsion for Shipping._ EMSA, Lisbon.

- Compares: rotor sails, hard sails, suction wings, kites, soft sails, turbines, by literature review and a break-even techno-economic analysis.
- Method: computes the main-engine fuel saving each WAPS must reach to cover its annual cost over 15 years, by ship segment and size (e.g. bulk carriers), for newbuild and retrofit, for low/central/high fuel prices, 2023/2030/2050. No voyage simulation, no routing.
- Key statements: rotors have shown up to 30 % savings; "hard sails and suction wings are relatively more efficient at lower ship speeds, kites support a greater reduction of fuel consumption at higher ship speeds"; larger and faster ships need a lower relative saving to pay back the same system; the required saving falls over time as renewable fuels and carbon costs raise the fuel bill; kite trials reported 10–35 % on MS Beluga SkySails (from Díaz 2020) and the provider estimated 10–15 %; savings estimates are often not comparable because of different bases.
- Relevance: frames our question (which rig pays where) but answers it only as a break-even threshold, not with a performance model. Note: EMSA does **not** state "5 to 10 %" for kite ships (see §10).

**rechevilanova2021** — Reche-Vilanova, M., Hansen, H., Bingham, H. B. (2021). Performance prediction program for wind-assisted cargo ships. _Journal of Sailing Technology_ 6(1), 91–117. DOI 10.5957/jst/2021.6.1.91.

- 6-DOF performance prediction for rotor sails, rigid wings and DynaRigs from main particulars and a published aero database; validated against Maersk Pelican (LR2 tanker, rotors). No kite, no routing, no cost.
- Relevance: methodological peer to our force balance.

**sturrup2023** — Sturrup, E., Stolz, D. (2023). _Jones Act shipping case studies: the feasibility of U.S. domestic green corridors utilizing hydrogen and wind-assist technologies._ ICCT white paper.

- Compares: rigid wing sails vs rotor sails on four US domestic vessels that run on liquid hydrogen with fuel cells.
- Findings: rotor output varies strongly with route, heading and season; wing sails always give net positive energy but about 40 % less annual energy than rotors; one rotor or wing saves tens of thousands of dollars of hydrogen a year.
- Relevance: the only comparison I found that pairs WASP with an expensive zero-carbon fuel; no kite, no routing, fuel-cost economics only.

**comer2019** — Comer, B., Chen, C., Stolz, D., Rutherford, D. (2019). _Rotors and bubbles: route-based assessment of innovative technologies to reduce ship fuel consumption and emissions._ ICCT Working Paper 2019-11.

- Rotor sails (five ships) and hull air lubrication (three ships) with AIS traffic and weather data. Rotors: about 1–12 % per rotor, 1–47 % across ships and routes. No routing, no kite or wing.

**talluri2016** — Talluri, L., Nalianda, D. K., Kyprianidis, K. G., Nikolaidis, T., Pilidis, P. (2016). Techno economic and environmental assessment of wind assisted marine propulsion systems. _Ocean Engineering_ 121, 301–311. DOI 10.1016/j.oceaneng.2016.05.047.

- Vertical-axis wind turbines on ships; Mediterranean, North Sea and Atlantic sea lines; 14 % (gas turbine) to 16 % (diesel) fuel saving; techno-economics at preliminary design. Not a kite/wing/rotor comparison.

**mason2026** — Mason, J., Della Moglie, P., Jones, C., van der Kolk, N. (2026). _A global fleet under wind: scaling wind propulsion for emission reduction, energy demand and equity._ Tyndall Centre report for Seas At Risk. (Verified on the Manchester research portal; numbers from press coverage.)

- Fleet-wide retrofit model, about 34 000–40 000 ships from AIS data; 6.3–9.4 % fleet fuel saving. Useful as the current fleet-scale bound.

## 2. ShipCLEAN and other Chalmers work

**tillig2018** — Tillig, F., Ringsberg, J. W., Mao, W., Ramne, B. (2018). Analysis of uncertainties in the prediction of ships' fuel consumption – from early design to operation conditions. _Ships and Offshore Structures_ 13(sup1), 13–24. DOI 10.1080/17445302.2018.1425519. Generic energy-systems model (ShipCLEAN's base) for a RoRo and a tanker; prediction uncertainty about 12 % at early design, below 4 % late. Relevance: sets the expected error of a main-particulars model like ours.

**tillig2019** — Tillig, F., Ringsberg, J. W. (2019). A 4 DOF simulation model developed for fuel consumption prediction of ships at sea. _Ships and Offshore Structures_ 14(sup1), 112–120. DOI 10.1080/17445302.2018.1559912. The 4-DOF (surge, sway, roll, yaw) extension; the template for our leeway/heel/rudder balance.

**tillig2020** (refs) — Tillig, F., Ringsberg, J. W. (2020). Design, operation and analysis of wind-assisted cargo ships. _Ocean Engineering_ 211, 107603. DOI 10.1016/j.oceaneng.2020.107603.

- Flettner rotors only, 11 arrangements, on a tanker (Pacific route) and a RoRo (Baltic route), with low-aspect-ratio wing theory for the hull at drift, aerodynamic interaction and individual rpm control. Fuel saving 30 % (tanker, up to 36 % with centreboards) and 14 % (RoRo, 16.8 % with centreboards); payback times at 500–700 EUR/t. Rpm control adds 1–2 points. Routes fixed; the paper concludes that "sophisticated weather routing" is needed. Source of our rotor coefficients.

**tillig2020b** — Tillig, F., Ringsberg, J. W., Psaraftis, H. N., Zis, T. (2020). Reduced environmental impact of marine transport through speed reduction and wind assisted propulsion. _Transportation Research Part D_ 83, 102380. DOI 10.1016/j.trd.2020.102380.

- Couples a transport-economics model (fleet size, speed, freight) to the ShipCLEAN energy model. Cases: speed reduction of a container ship on a Pacific trade; WASP (rotors) on an MR tanker on a North Atlantic trade. Raising fuel price from 300 to 1000 USD/t saves about 21 300 t fuel/year by slow steaming; WASP saves up to 500 t/year on the tanker.
- Relevance: **prior work already joins WASP, speed and transport economics**, for one technology and one ship. We must acknowledge it; our addition is three technologies, ship size, routing and an e-methanol drive.

**zis2020a** — Zis, T. P. V., Psaraftis, H. N., Tillig, F., Ringsberg, J. W. (2020). Decarbonizing maritime transport: a Ro-Pax case study. _Research in Transportation Business & Management_ 37, 100565. DOI 10.1016/j.rtbm.2020.100565. Short-sea Ro-Pax (Gothenburg–Kiel), several measures including WASP; no single measure meets IMO targets; market-based instruments needed.

**thies2023** — Thies, F., Ringsberg, J. W. (2023). Retrofitting WASP to a RoPax vessel – design, performance and uncertainties. _Energies_ 16(2), 673. DOI 10.3390/en16020673. Rotor retrofit design on a Baltic RoPax; guidelines on which modelling parameters matter. Not a technology comparison.

**thies2025** — Thies, F., Ringsberg, J. W. (2025). Sea trials vs prediction by numerical models – uncertainties in the measurements and prediction of WASP performance. _Journal of Ocean Engineering and Science_ 10(2), 239–245. DOI 10.1016/j.joes.2024.05.001. Measurement and prediction uncertainty in WASP trials; supports our caveat that routed savings are an upper bound.

## 3. Hull, leeway and machinery effects

**kramer2022** — Kramer, J. V., Steen, S. (2022). Sail-induced resistance on a wind-powered cargo ship. _Ocean Engineering_ 261, 111688. DOI 10.1016/j.oceaneng.2022.111688. Wingsail side force causes leeway and rudder drag comparable to added resistance in waves; the rudder is the main source; keels reduce it. Relevance: justifies our leeway/rudder balance, which most WASP-comparison papers omit (Traut, CE Delft, EMSA).

**vanderkolk2019** — van der Kolk, N. J., Keuning, J. A., Huijsmans, R. H. M. (2019). Part 1: Experimental validation of a RANS-CFD methodology for the hydrodynamics of wind-assisted ships operating at leeway angles. _Ocean Engineering_ 178, 375–387. DOI 10.1016/j.oceaneng.2018.12.041. Delft Wind Assist Series; hull side force at leeway with rudder, skeg, bilge keels, barkeel.

**bordogna2019** — Bordogna, G., Muggiasca, S., Giappino, S., Belloli, M., Keuning, J. A., Huijsmans, R. H. M., van 't Veer, A. P. (2019). Experiments on a Flettner rotor at critical and supercritical Reynolds numbers. _Journal of Wind Engineering and Industrial Aerodynamics_ 188, 19–29. DOI 10.1016/j.jweia.2019.02.006. Rotor lift/drag data at high Re; cross-check for the ShipCLEAN rotor polynomials.

**ghorbani2023** — Ghorbani, M., Slaets, P., Lacey, J. (2023). A numerical simulation tool for a wind-assisted vessel verified with logged data at sea. _Ocean Engineering_ 290, 116319. DOI 10.1016/j.oceaneng.2023.116319. Hull, rudder, CPP and engine model with two suction sails, verified against logged voyages.

**thiaucourt2026** — Thiaucourt, J., Tauzia, X., Le Guen, S., Giraud, M. (2026). Equivalence of power reduction and fuel savings in wind-assisted ships. _Journal of Sailing Technology_ 11(1), 300–321. DOI 10.5957/jst/2026.11.1.300. VLCC with CPP and shaft generator; fuel saving follows wind thrust share but deviates by up to 1.4 points with the machinery control strategy (−5.7 % to −7.0 %). Relevance: supports modelling the drive (mechanical vs diesel-electric) explicitly, as we do.

## 4. Towing kites

**naaijen2006** — Naaijen, P., Koster, V., Dallinga, R. P. (2006). On the power savings by an auxiliary kite propulsion system. _International Shipbuilding Progress_ 53(4), 255–279. (No DOI found; verified on the MARIN publication page.) Kite force averaged over a closed loop; drift and yaw solved with the longitudinal and lateral force balance; fuel saving at constant speed against wind speed and direction; later cited as a 50 000 dwt tanker with a 500 m² kite. Relevance: first paper to couple a kite with hull drift; our model does the same with an optimised eight.

**dadd2011** (refs) — Dadd, G. M., Hudson, D. A., Shenoi, R. A. (2011). Determination of kite forces using three-dimensional flight trajectories for ship propulsion. _Renewable Energy_ 36(10), 2667–2678. DOI 10.1016/j.renene.2011.01.027. Kite force along prescribed 3-D figure-of-eight trajectories with a zero-mass model; our checks compare against its 300 m² case.

**erhard2013** (refs) — Erhard, M., Strauch, H. (2013). Control of towing kites for seagoing vessels. _IEEE Transactions on Control Systems Technology_ 21(5), 1629–1640. DOI 10.1109/TCST.2012.2221093. SkySails flight control; operational evidence on glide ratio and flight envelope.

**erhard2013b** — Erhard, M., Strauch, H. (2013). Theory and experimental validation of a simple comprehensible model of tethered kite dynamics used for controller design. In Ahrens, Diehl, Schmehl (eds.), _Airborne Wind Energy_, Springer, 141–165. DOI 10.1007/978-3-642-39965-7_8.

**erhard2015** — Erhard, M., Strauch, H. (2015). Flight control of tethered kites in autonomous pumping cycles for airborne wind energy. _Control Engineering Practice_ 40, 13–26. DOI 10.1016/j.conengprac.2015.03.001. Figure-of-eight ("eight-down") direction control transferred from the ship kite.

**fritz2013** — Fritz, F. (2013). Application of an automated kite system for ship propulsion and power generation. In _Airborne Wind Energy_, Springer, 359–372. DOI 10.1007/978-3-642-39965-7_20. SkySails system description by the company.

**paulig2013** — Paulig, X., Bungart, M., Specht, B. (2013). Conceptual design of textile kites considering overall system performance. In _Airborne Wind Energy_, Springer, 547–562. DOI 10.1007/978-3-642-39965-7_32. SkySails kite design trade-offs (area, aspect ratio, wing loading).

**ahrens2013**, **schmehl2018** — the two Springer _Airborne Wind Energy_ volumes (DOIs 10.1007/978-3-642-39965-7 and 10.1007/978-981-10-1947-0). Context for kite aerodynamics and the VSM line of work (cayon2023 in refs).

**leloup2016** — Leloup, R., Roncin, K., Behrel, M., Bles, G., Leroux, J.-B., Jochum, C., Parlier, Y. (2016). A continuous and analytical modeling for kites as auxiliary propulsion devoted to merchant ships, including fuel saving estimation. _Renewable Energy_ 86, 483–496. DOI 10.1016/j.renene.2015.08.036. Analytical zero-mass kite with given lift and drag, flight path over the wind window, performance prediction program for merchant ships; best gains upwind. The group's earlier conference paper gives about 10 % fuel saving at Beaufort 5 and over 50 % at Beaufort 7 for a 320 m² kite on a tanker (from the abstract only; tanker size differs between sources). Relevance: the main analytical kite model for ships; it takes the aerodynamic coefficients as inputs, whereas we derive them from geometry with the VSM.

**penloup2021** — Penloup, Q., Roncin, K., Parlier, Y. (2021). Influence of kite characteristics on propulsive power applied to ship auxiliary propulsion. _Journal of Sailing Technology_ 6(1), 173–192. DOI 10.5957/jst/2021.6.1.173. Design of experiments on lift coefficient, glide angle, maximum wing load and tether length; **the maximum wing load explains over 50 % of the gain**, tether length is second above 70° TWA, glide angle matters most close-hauled. Relevance: directly supports our force limit (0.5 kN/m²) as the governing parameter for small kites.

**podeur2016** — Podeur, V., Merdrignac, D., Behrel, M., Roncin, K., Fonti, C., Jochum, C., Parlier, Y., Renaud, P. (2016). Voyage simulation for fuel economy assessment: practical application to kite auxiliary propulsion for merchant ship. _15es Journées de l'Hydrodynamique_, Brest. Multi-year time-domain voyage simulation with ECMWF data; validated against in-service consumption (underestimates by 12 %); 2200 TEU container ship with an 800 m² kite on Halifax–Le Havre: 12.1 % at 16 kn, 6.7 % at 19 kn over five years. Relevance: the nearest kite study to ours in method (multi-year reanalysis on a North Atlantic route); fixed route and speed, no cost.

**bigi2020** — Bigi, N., Roncin, K., Leroux, J.-B., Parlier, Y. (2020). Ship towed by kite: investigation of the dynamic coupling. _Journal of Marine Science and Engineering_ 8(7), 486. DOI 10.3390/jmse8070486. Zero-mass kite coupled to seakeeping; lock-in near wave frequency; mean kite force can rise while roll falls. Relevance: justifies our quasi-steady time-averaged kite force as a first-order model.

**ran2013** — Ran, H., Janson, C.-E., Allenström, B. (2013). Auxiliary kite propulsion contribution to ship thrust. _OMAE2013_, Vol. 8. DOI 10.1115/OMAE2013-11458. Simplified kite on a Panamax tanker; engine-power reduction in following to beam seas; manoeuvring and course keeping.

**wintecc2009_record** — EU LIFE public database record of project WINTECC (LIFE06 ENV/D/000479), Beluga Fleet Management and SkySails, 2006–2009. MS Beluga SkySails: **5 % fuel saving (165 t fuel, 530 t CO2 per year) on an average route mix, 10–12 % on North Atlantic and North Pacific routes**; kite pull up to 17 t; 5 % worth 135 000–220 000 EUR/year at 430–700 EUR/t; payback 2–3 years if the average saving were 10 %. The record says the project "achieved" these savings, not how they were obtained, and gives no kite size for the ship; `wiwo2008` gives 160 m². It points to a layman report (`wintecc2009`), which we do not hold. Relevance: **the primary source for our 160 m² validation target**, better than emsa2023 (§10).

**noaa2009** (refs) — NOAA VOS, Mariners Weather Log, April 2009: SkySails operating limits (launch above Beaufort 3).

**airseas2023** — Trade press (Container News, Oct 2023): Airseas Seawing (500 m² class, later 1000 m²) on the 5300 dwt ro-ro Ville de Bordeaux; projected 16 % fuel saving from measured traction; company target 20 %. K Line ordered systems for bulkers (Cape Brolga). Not peer reviewed; use only as the current industrial data point.

## 5. Weather routing with wind-assisted propulsion

**mason2023** — Mason, J., Larkin, A., Gallego-Schmid, A. (2023). Mitigating stochastic uncertainty from weather routing for ships with wind propulsion. _Ocean Engineering_ 281, 114674. DOI 10.1016/j.oceaneng.2023.114674. 1080 departures, eastbound and westbound, in the North Sea, South Atlantic and North Atlantic; wind propulsion plus routing saves up to 29 % in ideal conditions, and weather uncertainty cuts these savings by 10–20 %. Relevance: quantifies why our perfect-forecast routing is an upper bound.

**zis2020b** — Zis, T. P. V., Psaraftis, H. N., Ding, L. (2020). Ship weather routing: a taxonomy and survey. _Ocean Engineering_ 213, 107697. DOI 10.1016/j.oceaneng.2020.107697. Survey of isochrone, dynamic programming, calculus of variations and graph search; calls for benchmark instances. Background for our DP router.

**sidoti2017** — Sidoti, D. et al. (2017). A multiobjective path-planning algorithm with time windows for asset routing in a dynamic weather-impacted environment. _IEEE Trans. Systems, Man, and Cybernetics: Systems_ 47(12), 3256–3271. DOI 10.1109/TSMC.2016.2573271. Multi-objective DP over route, speed and power-plant configuration with time windows. Relevance: DP with joint route and speed choice, as in our router; no wind propulsion.

**guzelbulut2024** — Guzelbulut, C., Badalotti, T., Fujita, Y., Sugimoto, T., Suzuki, K. (2024). Artificial neural network-based route optimization of a wind-assisted ship. _JMSE_ 12(9), 1645. DOI 10.3390/jmse12091645. Up to 9.7 % energy saving from routing at the same voyage time, up to 35 % with 10 % longer voyages. One ship, one technology.

**precioso2026** — Precioso, D., Suárez, F., Jiménez de la Jara, J., Ballester-Ripoll, R., Gómez-Ullate, D. (2026). BERS: locally optimal continuous algorithm for maritime weather routing with just-in-time arrival. arXiv:2605.31533 (preprint). ERA5, 366 departures in 2024 on Atlantic and Pacific corridors, 88 m cargo ship with optional rigid wingsails; routing alone 23–59 % less propulsive energy than great circle, up to 75 % with wingsails. Relevance: closest recent routing study in ship size and data (ERA5, ~90 m ship, Atlantic). One technology, energy only, no cost.

**vanderkolk2019b** — van der Kolk, N. J., Bordogna, G., Mason, J., Desprairies, P., Vrijdag, A. (2019). Case study: wind-assisted ship propulsion performance prediction, routing, and economic modelling. RINA Power & Propulsion Alternatives for Ships, London. (TU Delft repository.) 5150 dwt general cargo ship (Damen design) in the Baltic at 10 kn: 2.99 % saving with one rotor, 6.11 % with two; payback analysis. Relevance: performance + routing + economics for a **small** ship, but one technology and a weak-wind sea.

Also routing-relevant: bentin2016, bentin2018 (§1), tillig2020 (§2, recommends routing), podeur2016 (§4, multi-year voyage simulation without route choice).

## 6. Techno-economics, barriers and fuels

**rehmatulla2017** — Rehmatulla, N., Parker, S., Smith, T., Stulgis, V. (2017). Wind technologies: opportunities and barriers to a low carbon shipping industry. _Marine Policy_ 75, 217–226. DOI 10.1016/j.marpol.2015.12.021. Abatement potential 10–60 % across sources; barriers are cost of capital, split incentives and lack of trusted performance data; third-party capital as remedy.

**chou2021** — Chou, T., Kosmas, V., Acciaro, M., Renken, K. (2021). A comeback of wind power in shipping: an economic and operational review on the wind-assisted ship propulsion technology. _Sustainability_ 13(4), 1880. DOI 10.3390/su13041880. Secondary-data review of uptake, fuel-saving claims and adoption factors for ships above 5000 GT. (Note: it is in _Sustainability_, not _Ocean Engineering_.)

**ballini2017** — Ballini, F., Ölçer, A. I., Brandt, J., Neumann, D. (2017). Health costs and economic impact of wind assisted ship propulsion. _Ocean Engineering_ 146, 477–485. DOI 10.1016/j.oceaneng.2017.09.014. Health externalities of air pollution avoided by WASP via a chemical transport model and the EVA valuation model.

**lindstad2021** — Lindstad, E., Lagemann, B., Rialland, A., Gamlem, G. M., Valland, A. (2021). Reduction of maritime GHG emissions and the potential role of E-fuels. _Transportation Research Part D_ 101, 103075. DOI 10.1016/j.trd.2021.103075. Well-to-wake emissions, energy and abatement cost of e-hydrogen, e-ammonia, e-diesel, e-LNG, e-methanol; dual-fuel engines as the robust path; e-fuel benefit depends on abundant renewable power.

**fasihi2024** — Fasihi, M., Breyer, C. (2024). Global production potential of green methanol based on variable renewable electricity. _Energy & Environmental Science_ 17(10), 3503–3522. DOI 10.1039/D3EE02951D. E-methanol at best sites (7 % WACC): 1200–1500 EUR/t (2020), 600–680 (2030), 390–430 (2040), 315–350 (2050). Source for our e-methanol price range.

**stolz2022** — Stolz, B., Held, M., Georges, G., Boulouchos, K. (2022). Techno-economic analysis of renewable fuels for ships carrying bulk cargo in Europe. _Nature Energy_ 7(2), 203–212. DOI 10.1038/s41560-021-00957-9. Carbon-neutral fuels raise total cost of ownership by a factor of 2–6 in 2030. No wind assistance.

**kanchiralla2022** — Kanchiralla, F. M., Brynolf, S., Malmgren, E., Hansson, J., Grahn, M. (2022). Life-cycle assessment and costing of fuels and propulsion systems in future fossil-free shipping. _Environmental Science & Technology_ 56(17), 12517–12531. DOI 10.1021/acs.est.2c03016. LCA and life-cycle cost of electro-fuels and drives (combustion, fuel cell, electric); electro-ammonia in fuel cells most cost-effective in carbon abatement. No wind assistance.

The specific claim "wind-assisted propulsion lowers the cost of decarbonisation with e-fuels" I found only in advocacy material (IWSA open letter, Seas At Risk "Wind First!" 2025, BAR Technologies) and as a qualitative statement in emsa2023 (required saving falls as renewable fuels raise the fuel bill). I found **no peer-reviewed paper that models WASP and e-fuel together with a voyage model and full cost**; sturrup2023 (rotor/wing with hydrogen, fuel cost only) is the closest. Not cited as a paper.

## 7. Ship size, speed and short sea

- cedelft2016: relative savings of rotors and wings larger on larger ships; kites better on smaller ships.
- emsa2023: larger and faster ships need a smaller relative saving to pay for the same rig; wings and suction wings favour low speed, kites and rotors higher speed (as stated; for the kite this contradicts the usual argument that apparent wind falls with speed — worth discussing).
- traut2014: three rotors could give more than half the power of a 5500 dwt cargo ship at slow steaming.
- podeur2016: kite saving halves from 16 to 19 kn (12.1 % → 6.7 %).
- lu2020: rotor sizing must match ship type and speed (tanker vs Handysize bulker).
- tillig2020: 30 % on a slow tanker vs 14 % on a faster RoRo.
- vanderkolk2019b, zis2020a, thies2023: short-sea and Baltic cases, single technology.
- huang2025: names ship type and size as a source of the spread in published savings.

No paper I found sweeps waterline length continuously for several rigs at once with the speed re-optimised.

## 8. Reviews 2021–2026

- **chou2021** — economic and operational review (above).
- **huang2025** — Huang, J., Souppez, J.-B. (2025). State of the art in wind assisted ship propulsion for maritime decarbonisation and sustainable shipping: a systematic review. _Journal of Sailing Technology_ 10(1), 258–278. DOI 10.5957/jst/2025.10.1.258. First systematic review: mean 17 % CO2 reduction, interquartile 7.5–22.5 %; Flettner rotors most studied and installed; suction wings widely installed but little studied; methods inconsistent; benefits still mostly predictions.
- **kolodziejski2025** — Kolodziejski, M., Sosnowski, M. (2025). Review of wind-assisted propulsion systems in maritime transport. _Energies_ 18(4), 897. DOI 10.3390/en18040897. Rotor sails, suction wings, rigid sails; manufacturer survey. (Note: second author is Sosnowski, not "Sosnowska".)
- emsa2023 and mason2026 serve as the 2023 and 2026 grey-literature state of the art.

## 9. Not verified or not found — left out of literature.bib

- **Wellicome & Wilkinson 1984** "Ship propulsive kites – an initial study": a patent cites it as Wellicome, J. F., Williams, S., Southampton report SSSU 19, ISSN 0140 3818. No library or repository record found. Second author uncertain. Cite only if you hold a copy.
- **Nyanya et al. (Ocean Engineering 2021, WASP review)**: not found. A "wind and solar assisted ship propulsion optimisation ... bulk carrier" paper exists but its authors and venue could not be confirmed.
- **Khan et al. (WASP simulation)**: not found under that author list.
- **Werner et al.**: only "Speed trial verification for a wind assisted ship" (Werner, Nisbet, Hörteborn, Nielsen, RINA Wind Propulsion 2021, rotor on m/v Copenhagen) was found; no routing paper. Left out (conference PDF on the Interreg WASP site only).
- **Kramer, Steen, Savio 2016** "Drift forces – wingsails vs Flettner rotors" (HISWA): cited by others, proceedings not found.
- **Ma et al., Mittendorf on WASP routing**: no WASP routing paper by these authors found. (mittendorf2022 in refs is on added resistance.)
- **Duport et al. (kite routing)**: not found; the Parlier/Roncin group's voyage work is podeur2016.
- **Lloyd's Register 2015** wind-powered shipping report: only reproduced in trade press; left out.
- **ITTC specialist committee report on wind-assisted ships**: not found by search; check ittc.info if wanted.
- **Mærsk Mc-Kinney Møller Center WASP report**: not found.
- **Laursen et al. (WASP study)** is the EMSA 2023 report itself (emsa2023).
- **Mason et al. "Quantifying voyage optimisation with wind propulsion for short-term CO2 mitigation in shipping"**: dataset (Mendeley, DOI 10.17632/5ss54b9bwh) found, journal article not confirmed; mason2023 used instead.

## 10. Remarks on the current draft

- `checks.tex` says "Ships that flew towing kites reported savings of 5 to 10 % \citep{emsa2023}". EMSA does not give that range: it quotes 10–35 % from Beluga SkySails trials (via Díaz 2020) and 10–15 % from the provider. The 5 % average and 10–12 % North Atlantic figures are from the EU LIFE WINTECC record. Suggest: "MS Beluga SkySails saved 5 % on its average route mix and 10–12 % on North Atlantic routes \citep{wintecc2009_record}." Our 6.7 % on Rotterdam–Guadeloupe sits inside that range.
- Leloup's kite model and Penloup's DOE both treat the maximum wing load as the binding limit; that backs our 0.5 kN/m² cap and the finding that a 160 m² kite saturates.

## 11. Comparison table

| Paper             | Kite                                   | Wing    | Rotor         | Other              | Ships                                   | Routes                | Weather data         | Routing | Speed optimised   | Leeway/heel balance      | Economics              | Fuel scenario                         | Savings found                    |
| ----------------- | -------------------------------------- | ------- | ------------- | ------------------ | --------------------------------------- | --------------------- | -------------------- | ------- | ----------------- | ------------------------ | ---------------------- | ------------------------------------- | -------------------------------- |
| traut2014         | yes                                    | –       | yes           | –                  | 5500 dwt cargo and others               | 5 trade routes        | reanalysis wind      | no      | no                | no                       | no                     | HFO                                   | rotor 2–24 %, kite 1–32 %        |
| lu2020            | –                                      | yes     | yes           | DynaRig            | Aframax tanker, Handysize bulker        | 2 Atlantic            | recorded             | no      | no (fixed ETA)    | 4-DOF                    | no                     | HFO                                   | 5.6–8.9 %                        |
| bentin2016/2018   | yes                                    | –       | yes           | DynaRig            | bulker, MPC, tanker                     | several               | yes                  | yes     | not stated        | not stated               | qualitative            | fossil                                | route-dependent                  |
| cedelft2016       | yes                                    | yes     | yes           | turbines           | bulkers, tankers, others, several sizes | world trades          | climatology          | no      | 2 speed scenarios | no                       | market, payback        | fossil                                | 5–18 % (rotor/wing)              |
| emsa2023          | review                                 | review  | review        | suction, soft sail | segments by size                        | –                     | –                    | no      | no                | no                       | break-even CAPEX/OPEX  | fossil to 2050, carbon cost           | required savings only            |
| rechevilanova2021 | –                                      | yes     | yes           | DynaRig            | LR2 tanker                              | –                     | polar                | no      | no                | 6-DOF                    | no                     | –                                     | validation                       |
| tillig2020        | –                                      | –       | yes           | –                  | tanker, RoRo                            | Pacific, Baltic       | measured             | no      | no                | 4-DOF                    | payback                | fuel price                            | 30 %, 14 %                       |
| tillig2020b       | –                                      | –       | yes           | slow steaming      | MR tanker, container                    | N Atlantic, Pacific   | yes                  | no      | yes (economic)    | 4-DOF                    | transport economics    | 300–1000 USD/t                        | up to 500 t/y                    |
| sturrup2023       | –                                      | yes     | yes           | –                  | 4 US vessels                            | US domestic           | yes                  | no      | no                | no                       | fuel cost              | liquid H2                             | wing 40 % less energy than rotor |
| comer2019         | –                                      | –       | yes           | air lubrication    | 5 rotor ships                           | real routes           | yes                  | no      | no                | no                       | no                     | –                                     | 1–47 %                           |
| vanderkolk2019b   | –                                      | –       | yes           | –                  | 5150 dwt cargo                          | Baltic                | yes                  | yes     | no                | yes                      | payback                | fossil                                | 3–6 %                            |
| podeur2016        | yes                                    | –       | –             | –                  | 2200 TEU                                | Halifax–Le Havre      | ECMWF 5 y            | no      | 2 speeds          | no                       | no                     | –                                     | 12.1 %, 6.7 %                    |
| leloup2016        | yes                                    | –       | –             | –                  | merchant/tanker                         | –                     | point conditions     | no      | no                | no                       | no                     | –                                     | ~10 % at Bf 5                    |
| naaijen2006       | yes                                    | –       | –             | –                  | tanker                                  | –                     | point conditions     | no      | no                | drift + yaw              | no                     | –                                     | vs wind                          |
| mason2023         | –                                      | –       | yes (generic) | –                  | cargo                                   | N Sea, N & S Atlantic | forecast vs hindcast | yes     | no                | no                       | no                     | –                                     | up to 29 %                       |
| precioso2026      | –                                      | yes     | –             | –                  | 88 m cargo                              | Atlantic, Pacific     | ERA5 2024            | yes     | JIT arrival       | no                       | no                     | –                                     | up to 75 % energy                |
| guzelbulut2024    | –                                      | –       | yes           | –                  | one ship                                | –                     | yes                  | yes     | time constraint   | no                       | no                     | –                                     | 9.7–35 %                         |
| wintecc2009_record | yes                                    | –       | –             | –                  | Beluga SkySails                         | operation             | –                    | no      | no                | –                        | payback                | 430–700 EUR/t                         | 5 % avg, 10–12 % N Atl           |
| **this paper**    | **160–3200 m², VSM + optimised eight** | **yes** | **yes**       | –                  | **85–200 m LWL**                        | **4 N Atlantic**      | **ERA5 2017–19**     | **DP**  | **yes**           | **leeway, heel, rudder** | **full cost per t·km** | **VLSFO vs e-methanol, carbon price** | –                                |

## 12. Gap analysis

Each candidate gap, checked against what exists.

**(a) One hull model, one cost model and routing for all three rigs.** Partly new. Like-for-like comparisons exist: kite vs rotor (traut2014), rotor vs wing vs DynaRig with a 4-DOF balance (lu2020, rechevilanova2021), rotor vs wing (sturrup2023), and kite vs rotor vs DynaRig with route optimisation (bentin2018). CE Delft compared kite, rotor and wing over ship types. None has the three of kite, wing and rotor in one force balance with weather routing that re-optimises speed, and none prices the result. bentin2018 is the nearest; we must name it and state the difference (no wing sail, no leeway/heel/rudder balance reported, cost only qualitative).

**(b) Ship size and fuel price/drive.** Mostly new. CE Delft (2016) and EMSA (2023) vary ship size, but by sample ships or break-even thresholds without a voyage model. tillig2020b varies fuel price for one rotor ship. Papers on e-fuel costs (lindstad2021, stolz2022, kanchiralla2022, fasihi2024) ignore wind. sturrup2023 pairs rigs with hydrogen but prices only fuel. No paper sweeps ship length continuously and switches between VLSFO mechanical drive and e-methanol diesel-electric drive. The EMSA statement that the required saving falls with renewable fuels is qualitative; we quantify it.

**(c) Kite from geometry with an optimised figure-of-eight.** New in the ship-economics context. Ship-kite models take lift and drag as inputs (naaijen2006, leloup2016, penloup2021, traut2014) or fly prescribed trajectories (dadd2011). The VSM (cayon2023) comes from airborne wind energy and has not been used to size ship kites. Penloup's finding that wing load dominates agrees with our force-limit result and should be cited as support, not as competition.

**(d) Cost per tonne-km including time, capital, port, crew.** Partly new. tillig2020b and zis2020a couple WASP to transport economics, including speed and fleet effects, for one rotor ship each. EMSA computes annualised CAPEX/OPEX break-even. Others report fuel saving and payback only (tillig2020, vanderkolk2019b, wintecc2009_record). No paper compares three rigs on full cost per tonne-km with kite wear and cargo interest. Do not claim to be first to include time costs at all.

**(e) Multiple routes.** Not new by itself. traut2014 (5 routes), mason2023 (3 basins), comer2019, lu2020 (2), CE Delft (world trades) cover several routes. Our contribution is the combination with (a)–(d), and the Caribbean and short-sea Bilbao routes, which no study I found covers.

**(f) Which situation favours which rig.** Partly new. CE Delft states kites suit small ships and rotors/wings large ones; EMSA states a speed ranking; traut2014 says the winner depends on route. These are statements from sample cases or literature. A map of the winning rig over ship size × fuel price × route from one consistent model has not been published, as far as this search found.

**Also worth stating:** the routed savings are upper bounds (mason2023: forecast uncertainty removes 10–20 % of the routing gain), and the drive matters (thiaucourt2026). The 160 m² reproduction of the SkySails figure (wintecc2009_record: 5 % average, 10–12 % North Atlantic) is a validation that earlier kite comparisons lacked.

## 13. Draft "Related work"

Wind-assisted propulsion is again on cargo ships, and a recent review counts more than a hundred installations \citep{kolodziejski2025}. The published savings spread widely. A systematic review finds a mean CO$_2$ reduction of 17\,\%, with half the studies between 7.5 and 22.5\,\% \citep{huang2025}. The spread comes from different ships, speeds, routes and methods, so two studies rarely compare \citep{emsa2023,huang2025}. Fleet-wide retrofits would save 6 to 9\,\% of fuel \citep{mason2026}.

Few studies compare technologies on the same ship. \citet{traut2014} modelled one Flettner rotor and one towing kite on five trade routes. The rotor saved 2 to 24\,\% of main-engine fuel and the kite 1 to 32\,\%, and the better device changed with the route. \citet{lu2020} compared a rotor, a wing sail and a DynaRig on an Aframax tanker with a 4-DOF model and found savings of 5.6 to 8.9\,\%, highest for the rotor. \citet{rechevilanova2021} built a 6-DOF prediction program for the same three rigs. \citet{sturrup2023} compared wing sails and rotors on four hydrogen-fuelled vessels: the rotors gave more energy, the wings gave it more steadily. \citet{bentin2016,bentin2018} put a kite, a rotor and a DynaRig into a weather-routing tool and showed that routing raises the saving. A study for the European Commission compared rotors, wings, kites and turbines on sample ships and found that rotors and wings save more on large ships and kites more on small ones \citep{cedelft2016}. None of these studies prices all three rigs with one cost model, and only the last varies ship size.

Rotor ships are the best studied. The ShipCLEAN model balances surge, sway, roll and yaw, and couples aerodynamic interaction with a hull at leeway \citep{tillig2019,tillig2020}. It predicts 30\,\% savings on a tanker and 14\,\% on a RoRo with rotors \citep{tillig2020}. Coupled to a transport-economics model, it shows that higher fuel prices pay for both slow steaming and rotors \citep{tillig2020b,zis2020a}. Side force has a cost: the leeway and rudder angle it needs add resistance comparable to the added resistance in waves \citep{kramer2022,vanderkolk2019}. Most technology comparisons ignore this.

Towing kites have a separate literature. \citet{naaijen2006} averaged the kite force over a loop and solved it with the hull drift. \citet{dadd2011} computed the force along three-dimensional figure-of-eight paths. \citet{leloup2016} gave an analytical kite model for merchant ships, and \citet{penloup2021} showed that the allowed wing load sets most of the thrust. \citet{bigi2020} coupled the kite to ship motions. These models take the lift and drag of the kite as given. SkySails flew a 160\,m$^2$ kite on a cargo ship from 2008 \citep{erhard2013,fritz2013}. It saved 5\,\% of fuel on the average route mix and 10 to 12\,\% on the North Atlantic \citep{wintecc2009_record}. A voyage simulation of an 800\,m$^2$ kite on a 2200\,TEU ship found 12\,\% at 16 knots and 7\,\% at 19 knots over five years \citep{podeur2016}. Airborne wind energy has since produced kite models that start from the geometry, such as the Vortex Step Method \citep{cayon2023}, but to our knowledge they have not been used to size ship kites.

Weather routing raises the value of wind. Route optimisation alone saves energy, and routing with wing sails or rotors saves more \citep{guzelbulut2024,precioso2026}. Most routers are graph searches or dynamic programmes over route and speed \citep{zis2020b,sidoti2017}. Routing with a perfect forecast overstates the gain: forecast uncertainty removes 10 to 20\,\% of it \citep{mason2023}.

The economics depend on fuel. Barriers to wind propulsion are the cost of capital, split incentives and a lack of trusted performance data \citep{rehmatulla2017,chou2021}. Break-even analyses show that large and fast ships pay back a rig with a smaller relative saving, and that the required saving falls as renewable fuels raise the fuel bill \citep{emsa2023}. E-methanol from the best sites costs 600 to 680\,EUR/t in 2030 \citep{fasihi2024}, and carbon-neutral fuels raise the cost of owning a bulk carrier two- to six-fold \citep{stolz2022,lindstad2021,kanchiralla2022}. These fuel studies leave out wind. How the drive converts thrust into fuel also shifts the saving \citep{thiaucourt2026}.

This paper joins these lines. We model kites, wing sails and rotors with one hull, one force balance and one cost model, and let a dynamic-programming router choose route and speed through three years of ERA5 weather. We vary the ship from 85 to 200\,m and switch from VLSFO to e-methanol. We size the kite from its geometry with the Vortex Step Method and an optimised figure-of-eight. We compare the rigs on cost per tonne-kilometre, including capital, crew, port dues, fuel, kite wear and cargo interest, and check the kite against the SkySails figures.
