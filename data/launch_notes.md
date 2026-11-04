# Launching and landing a ship kite

Sources behind the launch and landing inputs in `assumptions.yaml`. "Estimate" marks a number no source states. Page numbers are PDF pages of the copy read; three of the papers are preprints, so they are not the journal's. Nothing here comes from the Beyond the Sea project.

## Sources read in full

| Short name | Document | What it gives here |
| --- | --- | --- |
| Erhard 2013 | Erhard, Strauch, _Control of Towing Kites for Seagoing Vessels_, IEEE TCST 21(5), arXiv:1202.3641v3 | 160 m^2 on 300 m; zenith as a low-force launch and recovery state, p. 3; air speed in the pattern, p. 9 |
| SkyPower100 | Junge et al., _Abschlussbericht SkyPower100_ (public part), 2023, TIB Hannover | Land system: launch 5 m/s, p. 62; landing harder than launch, p. 20; ram-air depower flown 2022, p. 60; 15 min hang, p. 19 |
| Fagiano 2022 | Fagiano et al., _Autonomous Airborne Wind Energy Systems_, Annu. Rev. Control Robot. Auton. Syst. 5 (author's copy) | Launch from 3 m/s, p. 9; 42 h flight, pp. 19-20 |
| CE Delft 2016 | CE Delft et al. for DG CLIMA, _Study on the analysis of market potentials and market barriers for wind propulsion technologies for ships_ | Operators' statements on daylight and labour, p. 75; static force as a sail's, p. 26 |
| US 7,866,271 | Wrage, Böhm, patent on the SkySails placement system | Launch sequence; incidence and reefing commands in the design |
| WiWo 2008 | Kempkens, WirtschaftsWoche, 27 Jan 2008 | One hand launch that needed a turn; 15 m mast |
| Verivox 2007 | dpa report, 16 Dec 2007 | Pre-service plan: no launch in head wind, stowed below Beaufort 4 and above 8; crew "more demanded" |
| Paulig 2013 | Paulig, Bungart, Specht, ch. 32 of Ahrens et al., _Airborne Wind Energy_ | SkySails launch at 5 m/s, 10 m/s in rough sea and bad weather, p. 557; no freezing, wet kites launch less easily, p. 552; reefing and stowing, pp. 559-560 |
| Fritz 2013; Maaß 2013 | Chs. 20 and 35 of the same book | Launch and landing sequence, mast retracted in flight, pp. 363-365; second winch and one operator, pp. 605, 609 |
| Konstruktionspraxis | Höltkemeier, _SkySails - das Segelschiff der Zukunft_ | Launch and landing 10-20 min each |
| PSB 081893 | Relative Workshop, _Recommended Lifetime on Vector Tandem Components_, 1993, reissued 2003 | Main canopy replaced after 600 jumps, on "tandem malfunction and equipment failures" |

Not read: Anhang B of SkyPower100 (confidential; holds its sections on stowage, trim and durability); Brabeck's talk at the STG, unobtainable here.

## What no source gives

After reading the above in full, no source gives any of these for a ship kite or a large kite: crew number or hours per launch; launches, retries, tears or losses per launch; sea limits for launching or flying. Airseas has published no flight hours, launch counts or failure rates either. So every per-launch rate in the model is our estimate, and the ranges are wide because of it.

## Lowest wind

Derivation and formulas are in the paper's subsection on the lowest wind, and one definition covers any wing from its polar and mass. Base kites, apparent wind in m/s, 200 g/m^2 cloth, polar and drag at the angle of attack that serves best, 8 deg elevation:

| Area [m^2] | Mass [kg] | Level crosswind | Steady climb | Lift-off without tether (x1.3) | Launch |
| --- | --- | --- | --- | --- | --- |
| 800 | 972 | 1.69 | 3.99 | 4.47 | 5.0 |
| 1,600 | 2,178 | 1.79 | 4.23 | 4.5 | 5.0 |
| 3,200 | 5,020 | 1.92 | 4.54 | 4.53 | 5.0 |

Both moving forms match the steady force balance solved numerically to 3 %, in a test. Where they stop holding: the level form leaves out climbing, turning, the azimuth and wind shear; the climb form holds a steady climb, with no energy from speed. With a position theta off downwind, the forms scale with cos(elevation)/cos(theta)^2 under the root.

Against the pattern search. First flight at 5 m/s at 800 m^2, and 5-6 m/s at 3,200 m^2, on courses with the wind from behind; 8-10.5 m/s on upwind courses, where theta is large: at 8 deg elevation and 60 deg of azimuth the climb form gives 8 m/s, as the search does. No pattern below 4 m/s on any course. So the climb form is the limit in the model, and the level form's 1.7 m/s would need a pattern that climbs on its momentum. The Kitepower kite is said to fly down to 2 m/s (Kitepower 2024), so real kites may do better than the model at the light end: a bias against the kite, in a band where the wind that the ship makes comes from ahead and the kite pulls little.

The factor 1.3. It stays only for a kite with no air speed of its own, at lift-off, as an estimate. It came off flight, which has air speed in reserve. The pattern search also stopped refusing a wing that cannot hang at rest at zero air speed, the same fix as the rigid kite's.

Steaming up to launch. It never gains in the model: no pattern gives force under the launch wind (test), so a kite launched on extra ship speed gives nothing once the ship slows back down, and launching later costs less. Ship-made wind also comes from ahead, where the kite pulls least. If flight were modelled down to the level form this would be worth another look. The base 140 m ship could not do it anyway: with the kite stowed its engine holds 5 m/s but not 6 m/s in a 3 m/s beam wind.

## Limits

| Limit | Launch | Stay up | Landing |
| --- | --- | --- | --- |
| Lowest apparent wind | 5 m/s (3-6), or lift-off or flight if higher | Climb wind, 3.9-4.1 m/s | None |
| Highest apparent wind | 17 m/s (13-20), estimate | 25 m/s (20-30) | 20 m/s (15-25) |
| Significant wave height | 3 m (2-4), estimate | 5 m (4-7), estimate | 4 m (3-5), estimate |

The landing wind is the design limit of the stowage of a full-size land kite, 20 m/s, a target (SkyPower100, p. 20); that report also calls landing more time-critical than launch. So the three limits differ, and a kite may be up where it should not land. What keeps it from being stranded is that it can always come down, at a price: a landing outside the landing limits is forced, with a 5 % chance (1-20 %, estimate) of losing the kite, tether and control unit, against 0.005 % for a normal cycle. With the weather known, the router lands ahead of the limit; with a forecast it may be caught out and pay. A kite that reaches a stay-up limit must land at that point. Where only a flying kite holds the ship's speed, it stays up until it has to land.

Port approach. A leg ends with the kite down at its last sample point, about 15 nmi from port, so no leg ends on a stay, and a landing there can be forced. Along the fixed coastal stages before it the kite may still fly and launch: the model has no limit for traffic lanes or pilotage, and no source gives one.

Launch wind. The launch wind is the apparent wind on the ship's course. At 6 m/s dead downwind it stays under 5 m/s for true winds from 1 to 11 m/s, so such a launch waits. A turn would not help there: no pattern gives force under the launch wind, so the kite would give nothing back on course. So the low-wind limit needs no turn in the router. What may need one is a launch in a head wind, which pre-service plans ruled out (Verivox 2007) and which no source sizes, so it is priced as a mean cost per launch below, not routed. Sources disagree on whether a turn is needed: one hand launch needed one (WiWo 2008), the patent's mast head rotates and is silent on it. Launch wind sources: Beaufort 3 for SkySails ships (`kite_costs_notes.md`), 3 m/s and 5 m/s measured against an assumed 6 on land (Fagiano 2022, SkyPower100). The Beaufort 4-8 of Verivox 2007 is a plan written before service.

Night. The base case has no night limit, and a study case launches only between 06:00 and 18:00 local solar time, taken without the season; landing stays allowed at night, or a kite up at dusk could not come down. Charterers said the kite "could only be operated at daylight" (CE Delft 2016, p. 75, speakers not separated), but flight through the night has been reported on land (Fagiano 2022, SkyPower100 from 2020) and SkySails reported 120 h non-stop at sea. The discussion treats this as the weakest assumption.

## Launch cost

Per launch and landing, in `cycle_cost`: `(1 + retry) * (crew + tear * canopy + loss * (canopy + tether + control unit)) + course`. During the launch and landing time the ship burns stowed fuel.

| Input | Low | Base | High | Basis |
| --- | --- | --- | --- | --- |
| Crew [USD] | 20 | 85 | 380 | Estimate. Officer and rating for 0.5 h; officer and two ratings for 1.5 h; officer and three ratings for 3 h at EU rates |
| Tear ending the canopy, per attempt | 0.001 % | 0.005 % | 1 % | Goal for the base, half of about 1 in 10,000 per cycle; 0.2 % is our estimate of today, inside the range |
| Loss at sea, per attempt | 0.001 % | 0.005 % | 0.5 % | Goal for the base, the other half; 0.05 % is our estimate of today, no basis in data |
| Retry, per attempt | 2 % | 5 % | 20 % | Estimate, no basis in data |
| Turn, mean per launch [USD] | 0 | 130 | 900 | Estimate: 0.1 h (0-0.7) at about 1,270 USD/h of hire and fuel of the 140 m ship, held for every ship size |
| Launch [min] | 15 | 25 | 45 | Estimate on 10-20 min at 160 m^2 and a 30 min claim at 1,000 m^2 |
| Landing and stowing [min] | 15 | 30 | 60 | Estimate on the same, plus a land stowage hang of 15 min |

Total per cycle at base: USD 242, 265 and 314 at 800, 1,600 and 3,200 m^2. At today's estimates of tear and loss it would be about USD 740, 1,270 and 2,350, read from the formula.

Crew. Rates are USD 29 for an officer and USD 14 for a rating per hour worked: the crew cost of USD 500,000 for seven over about 3,650 worked hours per berth a year, 10 h a day (estimate), split by rank. The hours are on board anyway, so this is the crew's time rather than a cash cost, and it says nothing of the workload: charterers found the system too labour-intensive for rotating crews (CE Delft 2016, p. 75), and SkyPower100 first underrated its staff need, then cut it strongly (pp. 58-59, 64). A launch was hand-flown at first and automated later, on ships and on land.

Tear. Service limits of skydiving canopies, such as 1 in 600 jumps for a tandem main (PSB 081893), rest on malfunctions and failures and are retirement counts, mostly coating and porosity, so they set only the order of magnitude and not the rate. Gradual wear from flogging, folding and packing at launch and landing is in the canopy life, so `kite_cycle_damage_probability` holds only a discrete tear that ends the canopy.

Forced landing. A landing outside the limits is charged at 5 % (1-20 %) of canopy, tether and control unit, an estimate with no data behind it, and counted apart from the launches.

Who charges what. Time out of service, repair events, and failures of the winch, control unit, tether and mast belong to rig availability. A launch failure that needs only another try is charged here, one that takes the rig out of service is not.

## Result

Draft run on 72 departures, 140 m e-methanol ship, each case the mean over them. A kite either flies or is down; it does not stay up at rest.

Launch cost. A launch and landing at base costs little: the low bound adds 0-0.5 points, 1.3 on New York at 800 m^2, where 0.16 forced landings per round trip are charged. All launch inputs at their high bound together take 1.4-7.1 points, the most at 3,200 m^2, and put the best kite behind the rotor on every route and behind the wings on New York and Bilbao. At today's estimates of tears and losses a cycle costs USD 740-2,350 instead of 242-314, read from the formula, so the result rests on the goal being met. The high bounds are joint, a worst case rather than a likely one; each input also enters the sensitivity study alone. Router noise, read from cases where a dearer input came out cheaper, is up to 0.8 points.

Ranking. The best kite against the rotor and the wings, in saving points on each route:

| Route | Against rotor | Against rotor, high launch cost | Against wings |
| --- | --- | --- | --- |
| Caribbean | -0.6 | -3.0 | +6.4 |
| New York | -2.5 | -6.2 | +2.4 |
| Bilbao | +0.8 | -2.6 | +2.8 |
| Dakar | -3.2 | -6.4 | +3.3 |
| Houston | -2.3 | -5.4 | +5.3 |
| Tubarão | -3.7 | -6.3 | +5.7 |

Time out of service. With no rig ever out of service, each kite gains 0.1-0.6 points and the wings and rotors 0.2-0.6.

Launching by day only. Launching only between 06:00 and 18:00 costs 0.1-2.4 points, median 0.6, the most at 3,200 m^2, and removes up to 3.4 launches per round trip, median 0.7. Flight share moves by no more than 0.05, since a kite up at dusk stays up. The best kite stays ahead of the wings on every route, by 1.1-6.2 points, and on Bilbao it falls from 0.8 ahead of the rotor to 0.1 behind, within the noise.

Flight. The kite flies 21-57 % of the trip and makes 2-11 launches per round trip.

Savings [%] against the same ship with no rig, at launch costs low, base and high:

| Route | Area [m^2] | Low | Base | High | Launches | Flight share |
| --- | --- | --- | --- | --- | --- | --- |
| Caribbean | 800 | 11.9 | 11.8 | 9.5 | 7.0 | 0.52 |
| Caribbean | 1,600 | 13.6 | 13.5 | 11.1 | 6.1 | 0.56 |
| Caribbean | 3,200 | 10.6 | 10.4 | 5.3 | 5.5 | 0.41 |
| New York | 800 | 10.4 | 9.1 | 6.3 | 9.2 | 0.47 |
| New York | 1,600 | 12.4 | 11.9 | 8.2 | 9.9 | 0.48 |
| New York | 3,200 | 11.9 | 11.4 | 4.3 | 8.9 | 0.37 |
| Bilbao | 800 | 2.5 | 2.5 | 0.1 | 1.9 | 0.28 |
| Bilbao | 1,600 | 3.3 | 3.2 | -0.6 | 2.1 | 0.25 |
| Bilbao | 3,200 | 3.8 | 3.5 | -0.8 | 1.9 | 0.21 |
| Dakar | 800 | 9.6 | 9.4 | 7.7 | 5.2 | 0.46 |
| Dakar | 1,600 | 11.7 | 11.5 | 8.3 | 5.0 | 0.48 |
| Dakar | 3,200 | 9.3 | 9.1 | 4.0 | 4.4 | 0.42 |
| Houston | 800 | 9.2 | 9.0 | 6.7 | 10.2 | 0.53 |
| Houston | 1,600 | 12.1 | 12.0 | 8.9 | 10.0 | 0.51 |
| Houston | 3,200 | 12.3 | 12.1 | 6.0 | 11.0 | 0.40 |
| Tubarão | 800 | 11.7 | 11.5 | 10.1 | 7.8 | 0.56 |
| Tubarão | 1,600 | 15.3 | 15.1 | 12.5 | 7.6 | 0.57 |
| Tubarão | 3,200 | 13.5 | 13.3 | 8.3 | 7.4 | 0.46 |
