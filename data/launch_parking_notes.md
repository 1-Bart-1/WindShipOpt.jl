# Launching, landing and parking a ship kite

Sources behind the launch, landing and parking inputs in `assumptions.yaml`. "Estimate" marks a number no source states. Page numbers are PDF pages of the copy read; three of the papers are preprints, so they are not the journal's. Nothing here comes from the Beyond the Sea project, whose papers (Bigi 2018, Penloup 2021) were not used for any figure.

## Sources read in full

| Short name | Document | What it gives here |
| --- | --- | --- |
| Erhard 2013 | Erhard, Strauch, _Control of Towing Kites for Seagoing Vessels_, IEEE TCST 21(5), arXiv:1202.3641v3 | 160 m^2 on 300 m; zenith as a low-force launch and recovery state, p. 3; glide ratio 4-5, p. 6; air speed in the pattern, p. 9 |
| Erhard 2015 | Erhard, Strauch, _Flight control of tethered kites in autonomous pumping cycles_, Control Eng. Practice 40, arXiv:1409.3083v2 | Ram-air prototype with no depower, p. 3; neutral force in reel-in, Fig. 21 |
| SkyPower100 | Junge et al., _Abschlussbericht SkyPower100_ (public part), 2023, TIB Hannover | Land system: launch 5 m/s, p. 62; landing harder than launch, p. 20; ram-air depower flown 2022, p. 60; 15 min hang, p. 19 |
| Fagiano 2022 | Fagiano et al., _Autonomous Airborne Wind Energy Systems_, Annu. Rev. Control Robot. Auton. Syst. 5 (author's copy) | Launch from 3 m/s, p. 9; 42 h flight, pp. 19-20 |
| CE Delft 2016 | CE Delft et al. for DG CLIMA, _Study on the analysis of market potentials and market barriers for wind propulsion technologies for ships_ | Operators' statements on daylight and labour, p. 75; static force as a sail's, p. 26 |
| van der Vlugt 2019 | van der Vlugt et al., _Quasi-steady model of a pumping kite power system_, Renew. Energy, arXiv:1705.04133v2 | Force coefficient in reel-in against reel-out, Table 1, p. 11 |
| Oehler 2019 | Oehler, Schmehl, _Aerodynamic characterization of a soft kite by in situ flow measurement_, Wind Energ. Sci. 4 | L/D about 3 in reel-in and 4 in reel-out, p. 14 |
| US 7,866,271 | Wrage, Böhm, patent on the SkySails placement system | Launch sequence; incidence and reefing commands in the design |
| WiWo 2008 | Kempkens, WirtschaftsWoche, 27 Jan 2008 | One hand launch that needed a turn; 15 m mast |
| Verivox 2007 | dpa report, 16 Dec 2007 | Pre-service plan: no launch in head wind, stowed below Beaufort 4 and above 8; crew "more demanded" |
| Konstruktionspraxis | Höltkemeier, _SkySails - das Segelschiff der Zukunft_ | Launch and landing 10-20 min each |
| PSB 081893 | Relative Workshop, _Recommended Lifetime on Vector Tandem Components_, 1993, reissued 2003 | Main canopy replaced after 600 jumps, on "tandem malfunction and equipment failures" |

Not read: Anhang B of SkyPower100 (confidential; holds its sections on stowage, trim and durability); Brabeck's talk at the STG and Paulig et al. 2013, both unobtainable here.

## What no source gives

After reading the above in full, no source gives any of these for a ship kite or a large kite: crew number or hours per launch; launches, retries, tears or losses per launch; sea limits for launching or flying; a measured force or duration for holding a kite in one place; the control work of holding it; a force ratio of a depowered ram-air wing. Airseas has published no flight hours, launch counts or failure rates either. So every per-launch rate in the model is our estimate, and the ranges are wide because of it.

## Parked forces

A parked kite is a kite at rest on its tether, with air speed equal to the apparent wind. We compute it with the same force balance as the flying kite and give the ship its thrust, side force and yaw moment through the same chain. Tether drag is part of the balance, as in flight. The position is free: at each wind and course the model picks the elevation (10-70 deg), side and angle of attack that make the ship's task least costly, under the side weight of the trim, so a parked kite does not sit where it hurts most. On a beam reach it even gives useful thrust, since at rest a kite is a sail (CE Delft 2016, p. 26).

Model values, 140 m ship kites, base 200 g/m^2 cloth, side weight 0. Thrust is along the course; a negative thrust is the drag penalty Bart asked about. Course is off the apparent downwind direction, so 180 deg is dead into the apparent wind.

| Area [m^2] | Apparent wind [m/s] | Thrust at 0 deg [kN] | Thrust at 90 deg [kN] | Thrust at 180 deg [kN] | Side at 180 deg [kN] |
| --- | --- | --- | --- | --- | --- |
| 800 | 6 | 5.3 | 16.1 | -3.7 | -9.7 |
| 800 | 10 | 14.8 | 52.3 | -10.3 | -37.0 |
| 800 | 15 | 33.3 | 121.0 | -23.1 | -87.0 |
| 1,600 | 10 | 29.6 | 104.5 | -20.5 | -73.8 |
| 3,200 | 6 | 21.3 | 60.8 | -14.8 | -22.8 |
| 3,200 | 10 | 59.1 | 207.7 | -41.0 | -139.7 |
| 3,200 | 15 | 133.0 | 482.7 | -92.3 | -323.0 |

Where to park. The force is lowest near the top of the window, and the model reaches it where it asks for little side force: with side weight 3 it picks 70 deg elevation, and upwind at 10 m/s on 3,200 m^2 this gives -41 kN of thrust and 14.5 kN of side force instead of 139.7 kN. Lift acts across the wind, so the pull along the wind is about the kite's drag at any position; only the side force falls with height.

Depower. The parked kite holds a force coefficient between 0.7 and 1 of its value just below stall, at angles of attack 11.6-20 deg, L/D 3.8-3.9. That lies in the 3-4.5 reported for soft kites at rest or in reel-in (Erhard 2013, p. 6; Oehler 2019, p. 14; van der Vlugt 2019, p. 11). The bound of 0.7 is our estimate. The 0.25-0.33 of van der Vlugt 2019 is a coefficient ratio on leading-edge inflatable wings of 14 and 25 m^2, and its 0.25 force set-point is imposed by the controller. On ram-air wings Erhard 2015 had no depower, and SkyPower100 flew a depowering actuator in 2022 with no ratio published. The low bound 0.3 tests the leading-edge figure; the high bound 1 is a wing with no depower.

Stay-up wind. Equation (park) of the paper gives 5.1-5.4 m/s at 800-3,200 m^2 with the 200 g/m^2 cloth; a position holds from about 4.3-4.5 m/s in the model. Fagiano 2022 reports flight in about 6 m/s aloft, the lowest wind met, which bounds the minimum from above only.

Control work. No source gives a number for holding a kite. Erhard 2013 flies neutral mode with a plain PID on azimuth (p. 9) against deflections of 40-70 % of range in the pattern (p. 8); we charge no separate energy for holding.

What is known of ram-air kites holding position: neutral states are published only as short low-force phases of launch, recovery or reel-in (Erhard 2013, p. 3; Erhard 2015, p. 3; Fagiano 2022, p. 9; SkyPower100, pp. 8, 36). The nearest force measurement is 1-2 kN against 4-8 kN in the power phase on 30 m^2 at 7.5 m/s (Erhard 2015, Fig. 21, read by eye), while reeling in, so it is lower than holding at fixed length. The long flights, 42 h and 120 h, were powered flight. Whether a ram-air kite holds station for hours in a seaway is unknown, so parking is an unproven operation; gusts and downwinds can cause free flight (Erhard 2013, pp. 2, 9).

## Limits

| Limit | Launch | Stay up | Landing |
| --- | --- | --- | --- |
| Lowest apparent wind | 5 m/s (3-6), or the stay-up wind if higher | Equation (park) | None |
| Highest apparent wind | 17 m/s (13-20), estimate | 25 m/s (20-35) | None in the model |
| Significant wave height | 3 m (2-4), estimate | 4 m (3-6), estimate | Same as staying up in the limit, but always allowed |

A kite aloft that meets a limit must land at that point, at stowed fuel. There is no case where it cannot: landing has no limit of its own. That is a simplification, not a finding. SkyPower100 calls landing more time-critical than launch (p. 20) and designed its stowage for up to 20 m/s, so a landing at 25 m/s is unproven. Tightening stay-up to what landing can do would shrink flight at the top end only. A leg must end with the kite down, so a stay cannot run through port approach; the kite must be down by the last stage and the landing's cost is part of the launch.

Launch wind. The launch wind is the apparent wind on the ship's course. At 6 m/s dead downwind it stays under 5 m/s for true winds from 1 to 11 m/s, so such a launch must wait or turn. The router sees the wait: it may launch only where the limit holds. The turn is priced as a mean cost per launch below, not routed. Sources disagree on whether a turn is needed: one hand launch needed one (WiWo 2008), the patent's mast head rotates and is silent on it. Launch wind sources: Beaufort 3 for SkySails ships (`kite_costs_notes.md`), 3 m/s and 5 m/s measured against an assumed 6 on land (Fagiano 2022, SkyPower100). The Beaufort 4-8 of Verivox 2007 is a plan written before service.

Night and port. The model has no night limit. Charterers said the kite "could only be operated at daylight" (CE Delft 2016, p. 75, speakers not separated), but flight through the night has been reported on land (Fagiano 2022, SkyPower100 from 2020) and SkySails reported 120 h non-stop at sea. The discussion treats this as the weakest assumption, and the launch-per-trip and flight-share results below show what is at stake.

## Launch cost

Per launch and landing, in `cycle_cost`: `(1 + retry) * (crew + tear * canopy + loss * (canopy + tether + control unit)) + course`. During the launch and landing time the ship burns stowed fuel.

| Input | Low | Base | High | Basis |
| --- | --- | --- | --- | --- |
| Crew [USD] | 10 | 35 | 260 | Estimate. Officer and rating for 0.5 h; officer and two ratings for 1.5 h; officer and three ratings for 3 h at EU rates |
| Tear ending the canopy, per attempt | 0.05 % | 0.2 % | 1 % | Estimate |
| Loss at sea, per attempt | 0.01 % | 0.05 % | 0.5 % | Estimate, no basis in data |
| Retry, per attempt | 2 % | 5 % | 20 % | Estimate, no basis in data |
| Turn, mean per launch [USD] | 0 | 130 | 900 | Estimate: 0.1 h (0-0.7) at about 1,270 USD/h of hire and fuel |
| Launch [min] | 15 | 25 | 45 | Estimate on 10-20 min at 160 m^2 and a 30 min claim at 1,000 m^2 |
| Landing and stowing [min] | 15 | 30 | 60 | Estimate on the same, plus a land stowage hang of 15 min |

Crew. The old USD 150 assumed two crew for an hour at a loaded rate; the ranks on the crew cost in this file give far less. The crew's own view is not in it: charterers found the system too labour-intensive for rotating crews (CE Delft 2016, p. 75), and SkyPower100 first underrated its staff need, then cut it strongly (pp. 58-59, 64). A launch was hand-flown at first and automated later, on ships and on land.

Tear. Service limits of skydiving canopies, such as 1 in 600 jumps for a tandem main (PSB 081893), rest on malfunctions and failures and are retirement counts, mostly coating and porosity, so they set only the order of magnitude and not the rate. Gradual wear from flogging, folding and packing at launch and landing is in the canopy life, so `kite_cycle_damage_probability` holds only a discrete tear that ends the canopy.

Who charges what. Time out of service, repair events, and failures of the winch, control unit, tether and mast belong to rig availability. A launch failure that needs only another try is charged here, one that takes the rig out of service is not.
