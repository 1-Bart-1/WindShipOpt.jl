# Core literature: full-text notes

Every claim below is backed by a verbatim quote and a page number from the full
text in `literature_pdfs/`. Page numbers are the printed page numbers of the
source (journal page, article page, or report page "Page X of 270"), not the PDF
page index. Quotes come from `pdftotext -layout`; only line-break hyphens,
ligatures and footnote markers were repaired or dropped, and `[...]` marks
omissions. Erhard & Strauch 2013 was read via arXiv; the IEEE version may differ
in pagination. `sources.csv` records what is held and what has been read.

---

## 1. Lu & Ringsberg 2020 — rotor vs wingsail vs DynaRig, Aframax

**Citation.** Lu, R., Ringsberg, J. W. (2020). Ship energy performance study of
three wind-assisted ship propulsion technologies including a parametric study of
the Flettner rotor technology. _Ships and Offshore Structures_ 15(3):249–258.
doi:10.1080/17445302.2019.1612544. Source: Chalmers repository copy of the
published OA version.

**Compared.** Flettner rotor, wingsail, DynaRig on an Aframax tanker; rotor-only
parametric study on Aframax and Handysize bulker; two Atlantic voyages (Cape
Lopez–Point Tupper, Angra dos Reis–Rotterdam).

- "the Flettner rotor, the DynaRig and a wingsail" (p. 249).
- Aframax: "250 m in length, 40 m in beam and 14 m in design draft"; Handysize:
  "180 m in length, 28 m in beam and 10 m in design draft" (p. 253).
- Rig sizes: "A wingsail with a total sail area of 1000 m2 was chosen as the
  reference wingsail, and its area was set to match the area of the DynaRig. It
  has a height of 50 m and a chord length of 20 m" (p. 253); rotor "18 m in
  height, 3 m in diameter of its cylinder, and 6 m in diameter of the disc
  installed in the top of the rotor. Thus, the total surface area of the rotor
  is 509 m2 and the projected area is 108 m2" (p. 253).

**Method.**

- Rig model: polar thrust/heel coefficients, "CT = CL sin a − CD cos a" and "CH
  = CL cos a + CD sin a" (p. 251); rotor model "taken from Allenström et al.
  (2012)" (p. 253).
- Force balance with side force: "The ShipJOURNEY is a 4 degrees of freedom
  balance model where the surge, sway, roll and yaw are balanced for the ship"
  (p. 251); "the required rudder angle and corresponding added resistance are
  also included in the simulation model. The drift added resistance caused by
  heel force is also accounted for." (p. 251).
- Rig placement not optimised: "the three sail technologies were put midships in
  the simulation model, which is not the optimal location from a sailing
  dynamics perspective" (p. 255).
- Weather/routing: recorded noon-report weather on the actual route, **no
  routing**: "no difference was made between simulations without and with a sail
  technology onboard. However, smart routing for more favourable wind conditions
  when a sail technology is installed onboard is likely to increase the fuel
  savings even more than what is presented in the results of this study" (p.
  253).
- Speed: fixed ETA, "The simulations with the three sail technologies were set
  to have the same ETA of 313 h." (p. 253). Speed varied only as a parametric
  case (±0.5/−1.5 kn), not optimised.
- Economics: none (fuel tonnes and % only).

**Key results.**

- Route 1: "DynaRig 313 912.6 5.6%", "Wingsail 313 881.5 8.8%", "Flettner rotor
  313 880.6 8.9%" (Table 1, p. 255). Route 2: "DynaRig 367 1113.7 4.2%",
  "Wingsail 367 1091.5 6.1%", "Flettner rotor 367 1086.6 6.5%" (Table 2, p.
  255).
- "The Flettner rotor contributed the most to fuel savings with the least sail
  area" (p. 255; repeated in conclusions p. 257).
- Speed dominates: "Even the average speed is only increased by 0.5 knot, the
  extra required fuel will cover the fuel savings achieved by the Flettner
  rotor." (p. 255).
- Size effect: "Compared to that of the Aframax Oil Tanker, the Flettner rotor
  has a better performance in fuel savings for the smaller Handysize Bulk
  Carrier." (p. 256); "the larger rotor did not improve the fuel savings for the
  Handysize Bulk Carrier" (p. 256).
- Possible error in the paper: Table 3 is labelled "Route 1" but its reference
  case reads "Time (h) [...] 367" and "Fuel (t) [...] 1162.1" (p. 256), which
  are the Route 2 numbers of Table 2 (p. 255); Table 4 ("Route 2") has "Time (h)
  194", matching neither voyage (313 h, 367 h). The parametric tables should be
  cited with care.

**Relation to our paper.** Closest published three-rig comparison, but with a
single rotor of 108 m² projected area against 1000 m² sails, so "rotor wins"
partly reflects the chosen sizes rather than a like-for-like rig comparison; no
kite, no routing, no speed optimisation and no cost metric. We add the kite,
size the rigs per ship class, optimise route and speed jointly, and report cost
per tonne-km. Their finding that a 0.5 kn speed change outweighs the rotor
saving supports treating speed as a decision variable rather than a fixed ETA.

---

## 2. Tillig & Ringsberg 2020 (Ocean Engineering) — ShipCLEAN 4-DOF with rotors

**Citation.** Tillig, F., Ringsberg, J. W. (2020). Design, operation and
analysis of wind-assisted cargo ships. _Ocean Engineering_ 211:107603.
doi:10.1016/j.oceaneng.2020.107603. Source: Chalmers repository copy (CC BY).

**Compared.** Flettner rotors only; MR tanker (Pacific route) and RoRo (Baltic
route); 11 rotor arrangements: "two case study ships, a tanker and a RoRo, are
equipped with a total of 11 different arrangements of Flettner rotors" (p. 1).
Lengths "Loa [m] 200 183" (RoRo, tanker; Table 2, p. 15).

**Method.**

- 4-DOF steady equilibrium: "Since only the steady-state condition is evaluated
  in ShipCLEAN, the sum of all forces and moments in each of the 4 DOFs must be
  zero" (p. 3). Motivation: side forces "must be compensated by a drift angle of
  the hull and a rudder angle, both of which create added resistance" (p. 2).
- Hull side force from low-aspect-ratio wing theory: "Low aspect ratio wing
  theory is applied and modified to be used for the prediction of lift and drag
  forces of hulls sailing at drift angles" (p. 1). Generic input only: "the data
  needed for a power prediction are the main dimensions (Loa, B, T, Δ), the
  design speed, the ship type and the propeller rpm" (p. 3).
- Rotor–rotor interaction by potential flow, and individual rpm control with
  reefing limits "(in ShipCLEAN ϕmax = 8°)" heel and "(in ShipCLEAN δmax = 10°)"
  rudder (p. 18).
- Weather: ship-measured wind, one year, hourly: "Measurements were taken every
  hour, over a full year." (p. 15); savings from a weighted polar: "The expected
  fuel savings are computed as the weighted sum of the estimated savings in all
  TWS and TWA combinations." (p. 16). One speed: "The simulations were performed
  for one target speed and account for involuntary speed loss" (p. 15).
- Routing: none, only a constant-VMG diversion check: "the gains at an initial
  TWA of 80° can reach 30%. It must be noted that the results [...] do not
  account for any necessary tacking or different wind angles further into the
  journey in order to reach the destination." (p. 18).
- Economics: simple payback on rotor cost only, "Initial investment per unit
  [EUR] 750 000", "Yearly costs per unit [EUR] 15 000" (Table 3, p. 16), at "300
  EUR/ton, 500 EUR/ton and 700 EUR/ton" (p. 19).

**Key results.**

- "Fuel savings of 30% are achieved for the tanker, and 14% are achieved for the
  RoRo." (p. 1).
- rpm control: "the estimated fuel saving for the RoRo with the initial sail set
  up and the rpm control is 14.3%; without the rpm control, this drops to 12.0%.
  For the tanker, the fuel savings are 26.0% with the rpm control and 24.8%
  without." (p. 18).
- Diminishing returns: "Since the fuel savings do not increase linearly with the
  number of rotors (due to headwind and reefing) but the investment and
  maintenance costs do, the payback time is found to be the shortest for the
  arrangements with the fewest sails." (p. 19).
- Hull appendages: "For the tanker, the centerboard and double rudders increase
  the savings from 32.1% to 36.1%, and for the RoRo, the savings increase from
  14.3% to 16.8%." (p. 20).
- Routing need: "The achievable fuel savings and the dependency of the results
  on the weather along the route show the necessity of sophisticated weather
  routing for wind-assisted ships." (p. 18). Largest uncertainty: "The source of
  the largest uncertainty for the prediction of the expected fuel savings is the
  weather conditions the ship will experience." (p. 22).
- They write of Traut et al. 2014 that "the average savings with the single
  Flettner rotor are higher than with the kite" (p. 1). Traut's Table 1 does not
  show this: the route means are about equal, and the winner changes by route.

**Relation to our paper.** This is the reference for a 4-DOF force balance with
hull lift/drag at drift, and it confirms that leeway and rudder drag cannot be
skipped; our hull + leeway/heel/rudder balance is in the same class. Their
weakness relative to ours is one rig type, one speed, a weighted polar instead
of a voyage-by-voyage simulation, no routing (they call for it explicitly), and
payback rather than full cost per tonne-km. Their result that fewer rotors give
the shortest payback agrees with the size-saturation effect we expect for rigid
rigs.

---

## 3. Tillig, Ringsberg, Psaraftis & Zis 2020 (TR-D) — speed optimisation + rotor economics

**Citation.** Tillig, F., Ringsberg, J. W., Psaraftis, H. N., Zis, T. (2020).
Reduced environmental impact of marine transport through speed reduction and
wind assisted propulsion. _Transportation Research Part D_ 83:102380.
doi:10.1016/j.trd.2020.102380. Source: Chalmers repository copy (CC BY).

**Compared.** Two separate case studies: speed optimisation of a 350 m container
ship (Pacific, no wind propulsion), and 1–6 Flettner rotors of three sizes on an
MR tanker on a North Atlantic triangle (Rotterdam–New York–Houston–Rotterdam) at
a fixed speed. Rotor sizes "3 18", "4 24", "5 30" m (Table 3, p. 11). Speed
optimisation and wind propulsion are **not combined** in one case.

**Method.**

- Same 4-DOF ShipCLEAN, accelerated by a lookup: "A grid of 18 wind speeds and
  18 wind angles is used in the study" and "the wave height and angle were
  assumed to be directly coupled to the wind speed and angle" (p. 4). "It must
  be noted that interaction effects between the rotors are not included in the
  current version of the ShipCLEAN model." (p. 11).
- Weather: statistical, not time series: wind data "in a grid of 2.5 by 2.5
  degrees covering the whole world and it is based on the reanalysis for the
  years 2002 to 2012" (p. 6); Monte Carlo with "10 000 random wind speeds and
  wind directions [...] both being treated as independent random variables" (p.
  8); wind capped at "a maximum of 33 knots (kn), i.e. Beaufort 7" (p. 6).
- Routes: great circle and rhumb line only, "a function to produce waypoints
  along the great circle route using a start and an end point, is included" (p.
  6); no optimised routing.
- Economics: "C = journeyTime (pFC + X )" with "a per day profit (P)" that "can
  be used to optimize the ship speed, route, or utilization of the ship" (p. 5).
  Rotor payback "only includes the abovementioned installation and maintenance
  costs, but no other capital costs" (p. 12).

**Key results.**

- Speed: "Reducing the average speed from 24 kn to 20.5 kn will save 1934 t
  (36%) of heavy fuel oil per round trip" (p. 10); "the optimal speed is not
  changing with the changing weather on the routes" (p. 10).
- Rotors on the North Atlantic triangle: with mean weather "the results show
  virtually no savings with the sails" (p. 12), but "not a single simulation of
  all the 10 000 runs showed losses due to the sails, while the maximum achieved
  fuel saving was 20% for the setup with 6 rotors 5 × 30 m" (p. 12); "savings of
  up to 71 t (12%) of heavy fuel oil [...] per round trip" (p. 12).
- Payback: "The installations with one rotor are the most cost-efficient for
  each sail size." (p. 12); "the breakeven for the most efficient sail (Fig. 20:
  1 rotor 4 × 24 m) is 16.7 years. For an assumed future fuel price of 1000
  USD/t, this time is reduced to 8.4 years." (p. 14); the largest set-up's
  breakeven "is close to a tanker's expected maximum target service life" (p.
  15).

**Relation to our paper.** The only paper read that couples a 4-DOF ship model
to a transport-economics model, but speed optimisation is applied to a ship
without sails and the sail case is run at a fixed speed, on fixed routes, with
statistical rather than chronological weather. We optimise speed and route
jointly with the rig in the loop, on ERA5 time series, for three rig types and
13 ship sizes, and use full cost per tonne-km instead of payback. Their
observation that mean-weather analysis hides most of the saving (≈0% vs up to
20%) supports our choice of chronological weather over climatological means.

---

## 4. CE Delft, Tyndall, Fraunhofer ISI & Chalmers 2016 — EU market study

**Citation.** Nelissen, D., Traut, M., Köhler, J., Mao, W., Faber, J., Ahdour,
S. (2016). _Study on the analysis of market potentials and market barriers for
wind propulsion technologies for ships._ CE Delft, report 16.7G92.114, for
European Commission DG CLIMA. doi:10.2834/68747. Source: Chalmers repository
copy.

**Compared.** "Four wind propulsion technology concepts have been selected: a
Flettner rotor, a wingsail, a towing kite, and a wind power turbine." (p. 30).
Six ships: bulkers 7,200 and 90,000 dwt, tankers 5,400 and 90,000 dwt, container
1,000 and 5,000 TEU (Table 5, p. 34). Twelve trade routes plus one year of AIS
tracks (pp. 35–37).

**Method.**

- Rig models: constant coefficients. Rotor "CL = 10.0", "CD = 3.0" (p. 32);
  wingsail "CL = 2.0", "CD = 1.0" (p. 32); kite "CL = 1.25", "CL/CD = 4.5"
  (p. 33) (equation spacing normalised). Kite: "the kite is assumed to fly a
  circular pattern" with force taken as the pattern average, "neglecting any
  time-dependency of that force and also neglecting the effect of gravity on the
  motion of the kite" (p. 32); "The rope length is 350 m. The diameter of the
  circular flight pattern is 122 m." (p. 33).
- Sizing rules: rotors and sails scale with deadweight^(2/3) and length (p. 34);
  kite fixed: "A single kite of a fixed size of 400 m2 is fitted to each of the
  sample vessels." (p. 35); "Due to deck space constraints, the kite is the only
  technology fitted to container carriers." (p. 35).
- Ship model: thrust × speed / propulsive efficiency, "A constant value of
  ηP=0.7 is assumed" (p. 31); "Fuel savings are estimated from power savings
  assuming a constant engine specific fuel consumption" (p. 31).
- No side-force balance: "A quantitative analysis of the additional resistance
  is beyond the scope of this report." and "presented estimates are
  over-optimistic in ignoring side force effects" (p. 119).
- No routing, fixed speed: "performance modelling assumes that ships operate as
  usual, and at constant speed irrespective of employed wind propulsion
  technology" (p. 117). Two fixed speeds per ship, the slow one "A speed
  reduction of 15%" (p. 34). No waves: "They have not been considered in this
  report." (p. 118).
- Wind: "Wind data are read from ERA-Interim, 6-hourly, dataset, on a 0.125°x
  0.125° grid, at 10 m height", power-law profile "with an exponent P = 0.11"
  (p. 37).
- Economics: fleet diffusion by "a discounted payback period calculation"
  (p. 53) with "required payback time to decide to install the WPTs: 5 years;"
  (p. 54). No rotor costs: "the questionnaire data did not generate costs for
  Flettner rotors" (p. 54).

**Key results.**

- Savings, AIS profiles, higher speed: "Large bulk carrier (90,000 dwt) 17% 18%
  5% 2%", "Small bulk carrier (7,200 dwt) 5% 5% 9% 1%", "Large tanker (90,000
  dwt) 9% 9% 3% 1%", "Small tanker (5,400 dwt) 5% 5% 9% 1%", "Large container
  vessel (5,000 TEU) 1%" (rotor, wingsail, kite, turbine; Table 8, p. 50). Lower
  speed: "Large bulk carrier (90,000 dwt) 23% 24% 9% 4%", "Small tanker (5,400
  dwt) 7% 8% 15% 2%" (Table 9, p. 50).
- Size effect: "for towing kites relative savings are, by comparison, higher for
  smaller vessels but lower for larger vessels" (p. 51); this follows from the
  fixed 400 m² kite: "Because a single kite, of the same size, is matched with
  each of the vessels, its power contribution, in absolute terms, does not vary
  much between the various sample vessels." (p. 51).
- Speed effect: "Whereas for towing kites and the wind turbine absolute savings
  tend to be equal or even lower at the higher speed, in the case of the
  wingsail and the rotor absolute savings are, for all applicable ship types
  considered, larger at the higher voyage speed." (p. 51).
- Kite polar: "Strong tailwinds present ideal operating conditions for a towing
  kite." (p. 41); "The average side force exerted by the kite is, by comparison,
  much smaller than that exerted by the rotor or the wingsail" (p. 41).
- Rotor ≈ wingsail: "Relative savings are comparable for Flettner rotor and
  wingsails" (p. 51).
- Most cost-effective in diffusion model: "For bulk carriers and tankers, this
  was found to be the wingsail." (pp. 54–55); kite for container ships (p. 55).
- Inconsistency in the report: the text describes Figure 7 as "the 90,000 dwt
  bulker" but the caption reads "Rotor on 7,200 bulker" (p. 38).

**Relation to our paper.** The widest technology × ship-size comparison read,
and the only one of the full texts with all of rotor, wingsail and kite over a
size range; it uses ERA reanalysis like us. But it is power-only at constant
speed with no routing, no side force, no waves and a fixed 400 m² kite, so its
"kite wins on small ships, loses on large ones" result is largely built in by
the sizing rule. We test that conclusion with physics-based leeway/heel/rudder
balance, kite area scaled per ship class, routing and speed optimisation, and
full cost per tonne-km; the authors themselves list "the sizing of the
technology" and "how the vessel is operated - in terms of speed and routing"
among the most important accuracy factors (p. 52).

---

## 5. EMSA 2023 — Potential of wind-assisted propulsion for shipping

**Citation.** European Maritime Safety Agency (2023). _Potential of
Wind-Assisted Propulsion for Shipping._ Authors Laursen, R., Patel, H., Sofiadi,
D., Zhu, R., Nelissen, D., Van Seters, D., Pang, E. (ABS, CE Delft, Arcsilea).
EMSA, Lisbon. Source: emsa.europa.eu.

**Compared.** Rotor sails, hard sails, suction wings and kites; 13 ship types in
IMO size bins (Table 6, pp. 43–45). Mostly a review plus regulation and HAZID;
no performance simulation of its own.

**Method (economics).** Break-even, not savings: "the relative annual fuel
savings, that would be required from the main engine [...] to cover the annual
costs [...] are calculated for 2021, 2030 and 2050" (p. 42), "assuming a
weighted average cost of capital of 7% and installment payments over 15 years"
(p. 42). "This approach has been selected as an alternative to calculating the
return on investment based on the expected savings from the different WAPS." (p.
133). Kites: "For kites, only one unit per ship is expected to be installed" (p.
45); maintenance "5% of the 2021 CAPEX for kites and 2% of the 2021 CAPEX for
all other technologies" (p. 45). 2021 asset cost per unit (EUR 1,000): rotor
"560 1,050", kite "340 2,345" (min/max, Table 7, p. 46). Fuel scenarios: 2030 "a
blend of VLSFO (95%) and biofuel (5%)" (p. 48); 2050 baseline "Ammonia" (Table
11, p. 48). Small ships excluded: "the use of WAPS might be less common for
small vessels (<5,000 DWT) [...] Therefore, these have not been considered." (p.
42).

**Key results.**

- Required break-even ME savings for a kite on a newbuild container ship are
  small, e.g. "5,000- 0.8% 0.5%" for 5,000–7,999 TEU in 2021 low/high fuel price
  (Table 18, p. 64), versus "35,000- 12.7% 7.1%" for a 35,000–59,999 DWT bulker
  (p. 64).
- "compared to smaller and slower ships, larger and faster ships have higher
  fuel consumption and therefore, lower relative savings are needed to break
  even when considering the same system costs" (p. 133).
- Kite evidence is thin: "less research and modelling has been done on the
  performance of kites [...] The lack of data makes it particularly difficult to
  estimate the savings potential of kites." (p. 30).
- Speed dependence (contradicts CE Delft 2016, see §4): "some technologies
  perform better at lower vessel's speed (hard sail and suction wing) while
  other technologies (rotor sail and kite) perform better at higher vessel
  speed" (p. 31).
- Routing value is modest in the one quantified study cited: "about 10% of the
  19% in CO2 reduction (i.e., 1.9% of the reduction) could be ascribed to the
  use of voyage optimisation" (p. 39); and "if the total length of the journey
  also increases by 15%, only 3.5% of fuel is saved compared to the original
  journey" (p. 39). Yet: "Voyage optimization is, thus, considered critical to
  maximise the savings." (p. 133).
- Rotor headline: "rotor sails, which is the technology with the most available
  data, revealed up to 30% savings" (p. 133).
- Second-hand summaries (not verified by us): "A numerical model calculated the
  fuel savings for a 500 m² kite (Traut, et al., 2014). The amount of savings is
  ranging from 1% to 32%, depending on the ship type and route." (p. 30).

**Relation to our paper.** Gives the current EU cost basis (CAPEX/OPEX per unit,
WACC 7%, 15 years) and a future-fuel scenario, which we can cross-check our cost
inputs against; it also states that results "are sensitive on the initial CAPEX
assumption" (p. 3). It never computes savings and cost together, so it cannot
say which rig wins; we do, per ship class and for VLSFO vs e-methanol (EMSA uses
ammonia for 2050, not methanol). Its claim that kites do better at higher speed
is the opposite of CE Delft 2016 and of Podeur et al. 2016 (§6), and our results
can settle that disagreement.

---

## 6. Podeur et al. 2016 — kite voyage simulation, 2200 TEU container ship

**Citation.** Podeur, V., Merdrignac, D., Behrel, M., Roncin, K., Fonti, C.,
Jochum, C., Parlier, Y., Renaud, P. (2016). Simulation de voyage au long cours
pour le calcul d'économies de carburant : application à la propulsion par
cerf-volant ("Voyage simulation for fuel economy assessment: practical
application to kite auxiliary propulsion for merchant ship"). _15èmes Journées
de l'Hydrodynamique_, Brest. Source:
actesjh.ec-nantes.fr/images/15JH/Articles/podeur.pdf. In French with English
abstract; French quotes are given verbatim with a translation.

**Compared.** Kite only; one ship (2200 TEU container ship, "LOA 197.2 m", Table
3, p. 8); one route Halifax–Le Havre; two speeds.

**Method.**

- Kite: optimised-trajectory force database after Leloup, scaled linearly with
  area: "les propriétés aérodynamiques sont considérées constantes. La force
  propulsive devient donc directement proportionnelle à la superficie de l'aile
  souhaitée." (aerodynamic properties constant, force proportional to area; p.
  5). Reference kite "320 m2", "CL 0,776", "12,2°" glide angle, "300 m" lines
  (Table 2, p. 5); case kite "800m²" (p. 8). Operating window "entre Beaufort 2
  et Beaufort 7 (3m/s < VWR < 17m/s)" (p. 5).
- Ship: surge only, **no leeway**: "R Leloup [8] a montré que la dérive du
  navire pouvait être négligée en première approximation. Nous pouvons donc ne
  considérer que les efforts longitudinaux qui s'appliquent sur le navire."
  (drift neglected, longitudinal forces only; p. 3). No waves (p. 1).
- Weather: chronological ERA-Interim, "Sa résolution spatiale est de 0.75° et sa
  résolution temporelle est de 6 heures." (p. 3); "125 pour chaque vitesse"
  round trips over 5 years (p. 8).
- Route: "La trajectoire orthodromique est calculée entre les deux ports" (great
  circle; p. 3); no routing. Constant speed, no speed optimisation. No
  economics.
- Validation: "It shows an underestimation of 12% of the mean fuel consumption
  mainly due to the neglect of the reefers consumption and the waves added
  resistance." (p. 1).

**Key results.**

- Le Havre→Halifax "Economie moyenne 6.0 %" at 16 kn and "3.1 %" at 19 kn (Table
  5, p. 9); Halifax→Le Havre "18.2 %" and "10.2 %" (Table 6, p. 10).
- Round trip "Economie moyenne 12.1 %" at 16 kn and "6.6 %" at 19 kn (Table 7,
  p. 11); the abstract gives "6.7% at a speed of 19 knots" (p. 1), a small
  internal inconsistency.
- Speed: "une augmentation de la vitesse de moins de 20% revient à réduire
  l'économie réalisée pratiquement de moitié" (a speed increase of under 20%
  almost halves the saving; p. 11).
- Season: "les meilleurs rendements sont obtenus pour les périodes hivernales"
  (best in winter; p. 10).
- Side force left open: "l'effet de l'augmentation de la surface du cerf-volant
  sur les efforts transversaux et la capacité du navire à suivre une route sans
  une dérive trop importante doivent être évalués par ailleurs" (effect of a
  larger kite on transverse forces and drift must be evaluated elsewhere; p.
  11).
- The authors' own caveat: if the 12% underprediction is confirmed "il faut
  diminuer d'autant les pourcentages d'économies réalisées" (the savings
  percentages must be reduced accordingly; p. 11).

**Relation to our paper.** Closest kite study in method (chronological ECMWF
reanalysis, multi-year, North Atlantic, container ship), and its numbers are a
direct benchmark for our kite on a feeder-size container ship. It has no
leeway/rudder balance (the authors defer it), no routing, fixed speed, a single
ship and no costs; we add all of these and the comparison with rigid rigs. Its
finding that kite savings fall sharply with speed agrees with CE Delft 2016 and
contradicts EMSA 2023.

---

## 7. Erhard & Strauch 2013 — SkySails towing-kite control

**Citation.** Erhard, M., Strauch, H. (2013). Control of towing kites for
seagoing vessels. _IEEE Transactions on Control Systems Technology_
21(5):1629–1640. doi:10.1109/TCST.2012.2221093. Read as arXiv:1202.3641v3 (Oct
2012); page numbers refer to the arXiv version.

**Compared / scope.** Flight control of the SkySails kite; no ship performance
or fuel savings.

**Method and facts.**

- Product scale: "the latest product generation with a nominal size of 320 m2
  can replace up to 2 MW of the main engine's propulsion power" (p. 1); "The 132
  m vessel utilizes kites of sizes up to 320 m2" (Fig. 1 caption, p. 1).
- Point-mass quasi-steady model: "we neglect acceleration and gravity effects in
  order to obtain these simple equations of motion" (p. 3); steady state "ϑ0 (ψ)
  = arctan(E cos ψ)" and "va = v0 E cos ϑ" with glide ratio E (p. 3).
- Ship decoupled: "we have completely excluded the ship from our treatment by
  arguing that consideration of the apparent wind [...] is an appropriate
  approximation for the basic design of the control system" (p. 9).
- Flight test: "a 160 m2 kite at an operational towing line length of 300 m";
  "the dynamical flight mode leads to an air path speed of factor 3–4 higher
  than the estimated wind speed at flight altitude" (Fig. 18 caption, p. 9).
- "for controller design the complete aerodynamics can be reduced to a law
  involving only one or two quantities" (p. 9).

**Relation to our paper.** Justifies a quasi-steady, glide-ratio-based kite
force model driven by apparent wind, which is what a voyage-scale model needs,
and gives real system sizes (160–320 m², 300 m line, ~2 MW). It gives no fuel or
cost numbers, so it is a modelling citation only, not a performance benchmark.

---

## 8. Bentin, Kotzur, Schlaak, Zastrau & Freye 2018 — kite, rotor and DynaRig with routing

**Citation.** Bentin, M., Kotzur, S., Schlaak, M., Zastrau, D., Freye, D. (2018). Perspectives for a wind assisted ship propulsion. _Int. J. Maritime Engineering_ 160(A1), A-1 to A-10. doi:10.5750/ijme.v160iA1.1043; the PDF prints doi 10.3940/rina.ijme.2018.a1.439.

- **Set-up.** One kite (800 m²), four rotors (25 × 4 m) and a three-mast DynaRig (800 m² each), sized so the "wind force is about the same for the three systems for lateral winds" (p. A-6), on a 17,500 dwt carrier, a 37,600 dwt bulker and a 114,000 dwt tanker (p. A-2). All results shown are for the carrier at a fixed 13 kn, one journey a week in 2008 on analysis weather (p. A-7).
- **Results.** Baltimore to Wilhelmshaven, great circle and routed: rotor 21 and 31 %, DynaRig 25 and 35 %, kite 23 and 29 %. The reverse direction: 14 and 24 %, 21 and 33 %, 10 and 19 % (Table 2, p. A-8). Routing adds about 5 h to 294 h (p. A-8).
- **Balance.** None. Thrust is subtracted from the required power, "P_e(WASP) = P_e − P_e(WPS)" (p. A-2). The words leeway, drift, heel, rudder and side force do not occur. "Interactions between different units (rotors or masts) on the ship are neglected" (p. A-6). There is no wing sail.
- **Cost.** Numbers, but no cost model: a "rough estimation" that a rig on windy routes "might be profitable for a fuel prices of the order of 500 €/to (profitability after 5 years) or 250 €/to (profitability after 10 years)", with "Details will be discussed elsewhere" (p. A-9). There are no rig prices and no cost per tonne-km. "With the price of the actual fuel used in seagoing ships a profitability is not yet given" (p. A-9).

## 9. Citations checked against the source

- **Cayon, Gaunaa & Schmehl 2023.** Supports the Vortex Step Method: "a 3D nonlinear vortex step method coupled with viscous 2D airfoil polars" (p. 1). It tests leading-edge inflatable kites only, not a ram-air wing, and builds on "the method described in [27,28]" (p. 5). It names "the inability to deal with stall" (p. 15), and its drag is "still considerably smaller" than experiment (p. 15).
- **Holtrop & Mennen 1982.** All of pp. 166–170 read, from a course upload with a scanned text layer. "the given modifications have a tentative character only, because the adjustments are based on a small number of experiments" and "the application is limited to hull forms resembling the average ship" (p. 166). The worked example is on p. 170.
- **Holtrop 1984, incomplete copy.** The same upload holds three pages of the five the bibliography gives (272–276), numbered 3 to 5. It stops after the correlation allowance, with no reference list, and the cavitation and partial-submergence formulae its introduction promises are absent. The form factor and the wave resistance up to Fn 0.4, which the model takes from it, are on those pages (formulae compared by eye on the page images).
- **IMO 2023, MEPC.377(80).** "to reach net-zero GHG emissions by or around, i.e. close to, 2050, taking into account different national circumstances" (Annex 15, p. 6). Checkpoints are 20 to 30 % by 2030 and 70 to 80 % by 2040 (p. 6), on a well-to-wake basis (p. 5).
- **Loyd 1980.** Never prints the formula the model section gives. His closed form is Eq. 13, "L = ½ρC_L A (V_w − V_L)² (L/D_K)²" (p. 108), with tension about equal to lift, so against it the model's tension is higher by (1 + 1/G²)^1.5: 9.5 % at G = 4 and 1.5 % at G = 10 **[calc]**. Eqs. 39–41 (p. 110) with no weight and no reeling give the model's formula exactly **[calc]**, so a citation should name those equations.
- **Ortigosa, López & García 2009.** Table 1 (p. 16) gives 0.73 < C_P < 0.85 for tankers and bulk carriers, as the range of the Holtrop and Mennen evaluation. It cites only their 1982 paper, which has no such table, so the range rests on Ortigosa alone.
- **Rasp et al. 2024, journal version (JAMES 16(6), e2023MS004019).** The 1.5° and six hours are evaluation choices in the paper (p. 7), which says of the data only "A subset of the ERA5 data set is available on the cloud" (p. 4) and "Data is available freely on Google Cloud Storage" (p. 24). The arXiv v2 preprint words these passages the same, with the 1.5° on p. 9 and no data availability statement. The WeatherBench 2 data guide (weatherbench2.readthedocs.io, read 2026-11-02) lists `1959-2023_01_10-6h-240x121_equiangular_with_poles_conservative.zarr`, which is the copy itself.

## 10. Ahrens, Diehl & Schmehl 2013 — the chapters on kites, against this model

Printed page numbers of the book. Chapters read in full: 2, 3, 5, 8, 9, 14, 15, 17, 18, 19, 20, 21, 23, 24, 25, 26, 28, 31, 32, 33, 35. Left unread after the table of contents, as outside what the model holds: 1, 4, 6, 7, 10-13, 16, 22, 27, 29, 30, 34. Chapter 19 names a project whose kite the paper leaves out; its measurements are on other kites, so it is not used.

- **Paulig et al., ch. 32, SkySails ship kites.** "The specific weight of 160 to 320 m2 kites is around 0.5–0.6 kg/m2" (p. 552). "A 320 m2 kite designed to provide a pull of up to 320 kN (design load) has a mass of about 250 kg, the appropriate control pod adds 70 kg and the towing line another 0.9 kg/m" at "a tether length of about 360 m" (p. 554). "Flat size of 225 m2", "Kite weight with lines of 120 kg", "Fabric weight of slightly above 100 g/m2", "projected aspect ratio lower than 2", "Glide ratio between 4 and 5" (p. 561). "a launch can easily be considered at about 5 m/s while rough sea and bad weather might require 10 m/s" (p. 557). "Operation is limited to non-freezing conditions" (p. 552). "fatigue issues for textile wings and ropes are a limiting factor for economic success" (p. 562). Moved the control unit mass, the launch wind bound and the tether mass bound. It also sets the high end of `canopy_mass_overhead`, whose base of 0.05 is the owner's decision.
- **Bosman et al., ch. 33, DSM.** The "worked in" tether "will have a diameter which is about 15% less. This is the diameter that needs to be used for further engineering" (p. 569). "a good design factor for HMPE tethers to start the design iteration is FD = 3" (p. 568). Table 33.4: 30.6 mm nominal, 26.0 mm worked in, 60.8 kg/100 m, 88,000 daN (p. 582). "The linear density of HMPE is 970 kg/m3" (p. 578), so 26.0 mm at this weight, 1,145 kg/m^3, cannot be the rope's section. At 533 MPa, D/d 100: "60,000 single bends", "45 days until failure of the tether"; a year needs "Fd = 4", SK78 XBO and improved construction (pp. 579-580). "a maximum of 40% MBL can be applied to the tether to avoid rapid deterioration" (p. 574). Sets `tether_stress` and `tether_rope_density` on the nominal diameter; its time-tension-temperature creep diagram is one of the two laws of `tether_lifetime`, and its 45 days over a drum shows why the tow point must not bend the rope.
- **Dunker, ch. 31.** "a nominal L/D can be achieved that is about equal to the AR, from an AR of about 2 to 7" (p. 523). "Parachutes normally have a ratio of A-line length to constructed span of 0.5 to 0.6" (p. 528). "one may need A through E, F, G, H, or more" (p. 530). Wings of "36 m2 , 102 m2 , 250 m2 , 350 m2 , 900 m2 , and 1,040 m2" (p. 532); "one of the heaviest wings ever manufactured weighed 600 kg" (p. 531). Life in hours from degradation factors, an example of 265 h "not representative of any AWE system" (pp. 541-543). Moved the bound of `bridle_rows`; confirms `bridle_height_ratio` and the glide ratio.
- **Fritz, ch. 20, SkySails.** "design load of 320 kN and offers an effective thrust of up to 190 kN", "2000 kW" (p. 361). Launch from a telescopic mast, "During flight, the telescopic mast is retracted" (p. 363), and a second winch for landing (p. 364). Confirms the mast and thrust.
- **Maaß & Erhard, ch. 35, SkySails.** "The energy to drive the actuator as well as the communication data to the airborne components have to pass the towing rope" (p. 603). "a single operator on the ship must be empowered to run the system" (p. 609). "power and communication losses are a common scenario" (p. 600). Corrects the reason of the control unit, which held a battery and radio.
- **Erhard & Strauch, ch. 8, SkySails.** "the glide ratio would be E ≈ 3.9" (p. 156), "E ≈ 4–5 for our kites including tether" (p. 157), "gk=0.039 rad/m" at 160 m² (p. 158), "gk ≈ 0.13 rad/m" at 20 m² (p. 154). E "more or less represents the glide ratio of the overall system" (p. 153), so both figures include the tether. The base kite with its tether, 3.85, sits at the fit and just under the range, which supports `kite_flight_drag` without room to lower it. Confirms `kite_min_turn_radius`.
- **van der Vlugt et al., ch. 23.** "the lifetime of a kite could be around 1000h of operation" (p. 409), then "hardly any knowledge"; glide ratio 5.0 in reel-out, measured (p. 421); tether "only loaded to one third of its breaking strength" (p. 410). Bears on `canopy_life`, unchanged.
- **Bormann et al., ch. 24.** "we expect the full-load lifetime of the textile wings, even with significant strengthening of the high load areas, not to surpass much more then 100 hours" (p. 435); flat 15-21 m², projected 12.8-17.9 m² (p. 431), the 1.17 of `canopy_cloth_area_ratio`. Bears on `canopy_life`, unchanged.
- **Fechner & Schmehl, ch. 14.** "It is suggested to choose a safety factor St of 3.0" (p. 257). Confirms the design factor.
- **Nothing new for an input:** ch. 2, 3 (a lift-off method like ours, p. 63), 5 (generic shear tables; ours are sea data), 9, 15 (all assumed), 17, 18, 19, 21, 25. Ch. 26 and 28 are rigid kites, passed to the rigid kite work.
- **What no chapter gives:** launch or landing time, launch or landing wind or sea limits beyond the above, a launch crew count, a crash or failure rate, availability, or a measured canopy life.

## Gap statement (grounded only in the full texts above)

- **No paper read compares kite, rigid wing sail and Flettner rotor with one ship model that includes the side-force balance.** CE Delft 2016 has all three (plus turbine) but ignores side force ("presented estimates are over-optimistic in ignoring side force effects", p. 119); Lu & Ringsberg 2020 has the 4-DOF balance but no kite; Tillig & Ringsberg 2020 is rotor-only; Podeur et al. 2016 is kite-only with drift neglected (p. 3); Bentin et al. 2018 has kite, rotor and DynaRig but no wing sail and no side force. Side force is balanced in routed studies only for rotors: Mason et al. 2023 (4 DoF with heel, leeway and rudder, p. 3) and Dhainaut et al. 2025 (quasi-static surge, sway and yaw with hull drift and rudder, no heel, pp. 104, 112). Wendling & Lagemann 2025 route a four-wing-sail ship from precomputed speed polars (p. 363).
- **Of the multi-rig comparisons, only Bentin et al. 2018 routes, at one speed (13 kn), one ship and one size per rig.** Lu & Ringsberg (p. 253), Tillig & Ringsberg (p. 18), CE Delft (p. 117) and Podeur (great circle, p. 3) use fixed routes; three of them say routing would raise savings. Single-rig routing studies: Bentin et al. 2016 and Mason et al. 2023 (rotors), Dhainaut et al. 2025 (rotors, route and rotor layout optimised together), Wendling & Lagemann 2025 (wing sails). EMSA quantifies routing twice: 9 to 25 % for three rotors at constant voyage time (Norsepower/Napa 2022, p. 28) and "1.9% of the reduction" (NAPA/Norsepower/Sumitomo 2023, p. 39).
- **Speed is optimised together with a rig only for rotors and wing sails, mostly against fuel or energy under a time limit; never with a kite, and only once with time given a money value, by a sweep at fixed rig size and no routing.** Mason et al. 2023 optimise route and speed (8-14 kn) for minimum fuel with arrival no later than on the great circle (pp. 4-5); Dhainaut et al. 2025 optimise route, engine RPM and rotor layout for minimum fuel under a maximum voyage time of 140 or 160 h (pp. 112, 118); Wendling & Lagemann 2025 optimise route and engine power and give the Pareto front of voyage time against energy (pp. 352, 358). Hansen et al. 2025 sweep 6-15 kn for a Capesize with four rotors on generic routes, with time charged at a 15,000 USD/d charter rate, and find the minimum voyage cost at 9-10 kn (p. 13). Tillig et al. 2020 optimise speed only for a ship without sails and run rotors at a fixed 12 kn (pp. 10-11); the other comparisons use fixed speed or fixed ETA. Lu & Ringsberg (p. 255), CE Delft (p. 51) and Podeur (p. 11) find speed changes the wind saving strongly.
- **No full cost per tonne-km across rigs.** Economics in the texts read are payback on rig CAPEX/OPEX only (Tillig OE p. 19; Tillig TRD p. 12, "no other capital costs"), discounted payback for diffusion (CE Delft p. 53), break-even fuel saving without computing the saving (EMSA p. 133), or one rough break-even fuel price for an unnamed rig (Bentin 2018, p. A-9, 500 EUR/t over 5 years, 250 EUR/t over 10, from Schlaak 2016). The one full voyage cost is Hansen et al. 2025, for four rotors on one Capesize bulk carrier from a charterer's view: charter, port, main and auxiliary fuel, CO2 at 100 USD/t and the rig's depreciation, interest and maintenance per round trip of 10,000 nm (pp. 3, 13), with the rig adding at least 50,000 USD per trip on a 5.4 m/s route and saving up to about 200,000 USD (about 10 %) on a 10.7 m/s route (p. 13); it gives no cost per tonne-km and compares no other rig. Dhainaut et al. 2025 name profitability as future work (p. 122); Mason 2023 and Wendling 2025 have no cost; Huang & Souppez 2025 leave economics out (p. 262).
- **Size range with rigs scaled per ship is missing for the kite.** CE Delft's six ships use one fixed 400 m2 kite (p. 35), so its "kite better on small ships, worse on large" result (p. 51) is set by the sizing rule; EMSA also assumes one kite per ship (p. 45) and excludes ships under 5,000 DWT (p. 42). Dhainaut et al. 2025 vary only the rotor count (0-3 per side) on one ship (p. 118), and Hansen et al. 2025 only 4 against 5 rotors on one Capesize bulk carrier, where the fifth rotor adds 21.2 % rather than 25 % to the power reduction (p. 15). No study read spans coaster to Megamax; the 48 studies in Huang & Souppez span 75 to 363 m L_OA between them (p. 266).
- **Fuel switch is absent from performance studies.** Only EMSA varies fuel (VLSFO, VLSFO/FAME blend, ammonia; p. 48), and only for break-even. The 2025 routing studies use one fuel (Dhainaut: HFO, p. 110) or energy only (Wendling); Hansen et al. 2025 vary the price of one fuel, VLSFO at 600 or 1,200 USD/t with CO2 at 100 USD/t (pp. 13, 15), but not the fuel. No study read evaluates wind propulsion against an e-fuel such as e-methanol.
- **The literature disagrees on how kite benefit varies with ship speed.** CE Delft finds kite absolute savings "equal or even lower at the higher speed" (p. 51) and Podeur finds a <20% speed rise nearly halves kite savings (p. 11), while EMSA states that kites "perform better at higher vessel speed" (p. 31). Across all rigs, Huang & Souppez 2025 find reported savings "not to be sensitive to wind or ship speed" (p. 269). A joint speed-rig optimisation can resolve this.
- **Caveat:** Checked against Dhainaut et al. 2025, Hansen et al. 2025, Huang & Souppez 2025 and Wendling & Lagemann 2025 (all held, read in full) and Mason et al. 2023. Thiaucourt 2026 (JST 11(1)) is not held and could bear on the cost and routing bullets.
