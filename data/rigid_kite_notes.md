# Rigid VTOL kite: inputs, scaling and launch evidence

Numbers behind the `rigid_*` inputs of `assumptions.yaml`. The rig is one wing with on-board propellers on an electrified tether. It pulls rather than generates, so the propellers are feathered in flight and work only in launch and landing.

## Inputs of the model

The model is MX2 at 54 m², every input a number at that design, sized away from it by the mass exponent. The sections below hold the evidence; this one says how each input is made of it. The values come from a build-up of MX2 part by part (the structure law, momentum theory and the drive mass law below, and separate prices of structure, drives and tether), run at 54 m² with every input at base, at the bound that favours the kite, and with the mass inputs at their high bounds.

| Input | Base | Low | High | Made of |
| --- | --- | --- | --- | --- |
| `rigid_mass` | 1852 | 891 | 3240 | MX2's 1852 kg on 54 m²; the build-up gave 1804 kg at sea level. Bounds: every mass and hover input favourable (16.5 kg/m²); structure, propellers and drives at their high bounds (60 kg/m²). |
| `rigid_mass_exponent` | 2.5 | 2.2 | 3.1 | Mass grows with the span to this power from MX2, at its aspect ratio: 2.4 at MX2's size and 2.6 at 200 m² by the structure law (shell per area, load-bearing part with the span cubed); 2.2 to 3.1 over wings built and designed. |
| `rigid_hover_power_per_mass` | 470 | 200 | 950 | Momentum theory below, 873 kW for 1852 kg with the 275 kg tether. Low: the light kite with the favourable hover inputs (175 kW on 889 kg). High: thrust 1.5, disc 0.4, efficiency 0.56, density 0.95, at base mass. |
| `rigid_drag` | 0.070 | 0.054 | 0.127 | 0.123 − 0.083 induced (elliptic) + 0.0022 feathered propellers + 0.029 tether (0.7 × 29.4 mm × 300 m / 4 / 54 m²). Bounds: profile, span efficiency, propeller and tether drag at their bounds. |
| `rigid_cost_per_mass` | 280 | 48 | 540 | Structure 290 USD/kg × 1370 kg + 232 USD/m² × 54 m² + drives 0.10 USD/W × 1.13 MW = 522k USD, over 1852 kg. |
| `rigid_tether_mass_per_force_length` | 3.06 | 3.06 | 3.06 | MX2's tether, 275 kg / (300 kN × 0.3 km), 1.47 times rope of 830 kg/m³ at 0.4 GPa. |
| `rigid_tether_price` | 186 | 93 | 400 | Twice the rope's 93 USD/kg, bought without the market factor like the soft kite's rope; 51k for MX2's. The rest of the station is the soft kite's winch, launch mast and ship-side controls at the kite's 300 kN and 54 m²: 70k + 30k. |
| `rigid_upkeep_per_area` | 0.61 | 0.26 | 1.2 | Airframe upkeep alone; the tether wears out over `tether_lifetime`, as the soft kite's. |

Dropped as too small to move the answer: the hover's energy, 6 min at 844 kW and 0.20 USD/kWh, USD 17 a launch; its time, 6 min of no thrust a launch, under 0.5 % of the flight hours; the tether's bending per launch; the perch's deck width, which costs cargo only on a container ship, where the VTOL kite is not routed; and half the tether's weight in flight, 7 % of the flying mass. The flight limit and life are the soft kite's (`kite_max_wind`, `kite_lifetime`), equal to the values the VTOL kite had.

## Reference design

The Makani MX2 design is the anchor (Echeverri et al. 2020, Part I, Tables 1 and 2): 54 m², 26 m span, 1852 kg with propellers, 300 m tether of 29.4 mm at 275 kg, 250-300 kN, 90 m loop radius, CL 1.81 and CD 0.123 at best performance (0.152 with tether). It was never built. The largest wing flown with on-board propellers is the M600, at 32.9 m².

## Built to pull

MX2 generates with its propellers. A kite that only pulls departs from it in three ways, each measured on the yearly cost per kN of a 54 m² kite at 12 m/s on a beam course (3000 flight hours, 150 launches):

| Step | Thrust | Price with tether, winch, perch | USD/kN/year |
| --- | --- | --- | --- |
| MX2 as is, windmilling propellers | 144 kN | 2.34 M | 2976 |
| Propellers feathered | 160 kN | 2.34 M | 2691 |
| Mass from structure, propellers and hover-rated drives; structure priced alone | 160 kN | 2.05 M | 2441 |

At 300 m² the same steps give 4284, 3868 and 3280. A 1000 m² soft kite costs 902 (at 3000 canopy hours; 779 at the earlier 4000), so the 54 m² kite costs about 2.7 times as much.

- Propeller size: at 54 m², 0.3 of the wing as disc costs 14510 USD/kN, 0.61 12790, 1.0 12110, thrust within 1 %. Feathered, larger propellers pay; 0.61 is kept, 1.0 is the favourable bound.
- Tether: the M600 tether, which MX2 takes over, is rated 1 MW (Part II, p.40), about MX2's hover, so the conductors stay. A battery for an 850 kW peak at the 1.5 kW/kg estimated for a car pack (Sripad and Viswanathan 2021, SI) weighs about 560 kg, twice the whole tether.
- Aspect ratio: generating and pulling both maximise CL (CL/CD)², so 12.5 stays.

## Mass law (evidence for the size and the mass bounds; not in the model)

m = m_s S + m_F F b AR + m_r A_d + 411 kg × (P_d/1.36 MW)^ε, with S the wing area, F the tether force limit, b the span, AR the aspect ratio, m_s = 14 kg/m² (7.5-21) and m_F = 0.0063 kg per kN m (0.0026-0.0096); P_d is the hover power over 0.75, solved with the hover power.

- Why this form. The spar caps of a wing held at its centre under a lift F spread over the span weigh ρ F b AR / (12 τ σ), with τ the thickness ratio and σ/ρ the working stress over the density of the caps: the bending moment goes with F b, the depth of the spar with the chord b/AR, and the length with b. Aull et al. (2020, Eq. 21-25) derive the same proportionality. Held at N points along the span that share the load, the caps weigh 1/N² of that. Everything that no load sizes goes with the area. At a fixed force per area and aspect ratio the first part goes with span squared and the second with span cubed.
- The spar is a small part. Makani's build-up of the 26 m wing (Part II, pp.287-288, total 1854 kg): spar caps 125 kg, shear walls 68, hardpoints 57; main skin 300, second element 103, ribs 90, wire, glue and paint 80, aileron hardware 29, trailing edge 7; empennage 229, pylons 160, fuselage 50, mass balance 36, avionics 26, tip thruster 14; nacelles, powertrains and booms 480. Its example sizes the caps for 250 kN of lift and a root moment of 633 kN m on a spar 0.45 m deep (pp.279-281), 469 MPa in the caps; the formula above gives 107 kg at that stress and depth, 128 kg with the 20 % the sizer adds to the caps (p.276). So 9 % of the structure is spar caps and 18 % is sized by the tether force in a direct way.
- Bridle. M600 hung from two hardpoints 5.9 m either side of the centre on a 25.66 m span, 0.46 of the half span, with the knot 4.79 m below (Makani code release, config/m600/wing.py; Part I, Table 2). MX2 moved them to about ±1.5 m, "which has the effect of increasing bending loads on the wing" (Part I, p.21, footnote 16), because a small bridle "is extremely important to maneuverability" (Part I, pp.26-27). A wide bridle to two points would cut MX2's caps to a quarter, about 90 kg of 1372 kg. More points add line drag and take roll control away; they cannot remove the shell.
- Base split. The two coefficients return MX2's 1372 kg of structure: 756 kg of shell and 614 kg of load-bearing structure. The split is the one that also returns two wings of other lineages: 7.5 t against the 6885 kg of the 150 m² design of Eijkelhof et al. (2020; 42.7 m, peak 617 kN at 37 % of its limit), and 206 kg against the 229 kg of carbon composite in Ampyx's AP3 (48.2 % of 475 kg, van Hagen et al. 2023, Table 4; 12 m², 42 kN, Joshi et al. 2024). For M600 (32.9 m², 25.66 m, 240 kN) it gives 1.24 t, against 845 kg of structure, pylons and propellers on a design slide (Part II, p.20) and 1.26 t as built once bridles, motors, controllers and propellers are taken off 1731 kg, wiring and avionics still in it.
- Low bounds. Shell: half of 15 kg/m², the structure of a 4 m² kite with propellers that Aull et al. (2020, Tables 1-2) hold per area at every size as the lighter of two laws. Load: caps, shear walls and hardpoints of Makani's build-up, 250 kg. Together 658 kg at 54 m², 12 kg/m², and 356 kg at 20 m of span.
- High bounds. Shell: all of Makani's build-up that no load sizes, 21 kg/m². Load: what returns MX2 with a shell of 8 kg/m², near the small wings that flew. Together 2.07 t at 54 m², half above MX2, against M600's overrun of 40-70 % (Part I, p.265).
- Published laws. Joshi et al. (2024, Eq. 20), for horizontal launch from Ampyx's part-level model: m = [(0.024 w + 0.1) S² + (1.7 w + 32.5) S - 50] f(AR) with w = F/S in kN/m². At 54 m² and 5.56 kN/m² it gives 2.9 t, of which 0.9 t goes with the force. Sommerfeld et al. (2022) sweep span to the 2.7-3.3 from AP2 (36.8 kg, 5.5 m); van Hagen et al. (2023) use 2.7-3.0. The law here goes with span to the 2.45 at MX2 and to the 2.66 at 300 m².
- Sailplanes. Noth (2008, ETH thesis 18010, Table 3.1 p. 47, read in full) fits the airframe weight of 415 sailplanes (92 models, 323 manned) as 5.58 b^3.18 AR^-0.88 N and of the lightest 5 % as 0.44 b^3.10 AR^-0.25 N: 1.9 t and 0.58 t at MX2's span and aspect ratio, 0.84 t and 0.26 t at 20 m. His reason for the cube is geometric similarity, not a structural derivation, and the wing loading of his sailplanes grows with size too, so at a fixed load per area the exponent is lower, about 2.5. A Standard Cirrus wing weighs 116.5 kg on 10.04 m² (Hoff et al. 2010; EASA.A.278) for a limit lift of about 2 kN/m², against the 5.56 kN/m² here.
- Skin. Ardema et al. (1996, NASA TM-110392, p. 4 and Eq. 79, read in full) size the covers of a transport wing's box by buckling, with a thickness that grows with the bending moment to the 1/2 (truss core) or 1/3 (unstiffened). At a fixed force per area and aspect ratio a buckling-sized shell grows per area with the span to between 1/3 and 1, so a constant shell per area holds only while minimum gauge or handling sizes it. No source says where that stops.
- Exponent of the law against the evidence, span at fixed force per area and aspect ratio: law 2.44 at 50 m², 2.61 at 200 m², 2.78 at 1000 m² (bounds 2.30-2.82 at 200 m²); evidence about 2.5 at 50 m² (Sommerfeld et al. 2022 find 2.2-2.6 in designs; Noth corrected), 2.5-3.1 at 200 m² (AP3 to van Hagen's 300 m² 2.32-2.65; MX2 to Eijkelhof 2.65; Joshi Eq. 20 3.06), 2.7-3.7 at 1000 m², extrapolation only. Largest wing with propellers built: M600, 32.9 m². The base law stays; the size study also runs a structure all load-bearing, m_F = 0.0141 kg per kN m with no shell, which grows with the span cubed and returns MX2's 1372 kg.
- Load carried per unit of own weight, whole kite: AP2 5 (1.8 kN, 36.8 kg), AP3 9, M600 14, MX2 16.5 by design, Eijkelhof et al. 25 by design. Makani: "tether tension can easily exceed the weight of the kite by a factor of 10 to 15" (Part I, p.12).
- Propellers: 65 kg of propellers and spinners on 8 × 4.15 m² for M600 (Part II, p.20; Part I, Table 1), 1.96 kg/m²; base 2.5 for feathering hubs (estimate), high 3.9.
- Drives: 480 kg less the propellers, 411 kg for 1.2 MW of shaft (Part I, p.184). ε = 0.81 from the motor regression W = 0.5382 Q^0.8129 with controller, inverter and cooling (Johnson et al. 2018, p.5), 1 for motors linear in torque (Part I, p.184). Low bound 241 kg: MX2's 344 kg of motors and controllers (36 + 7 kg × 8, Part II, pp.46-47) at 6.9 kW/kg, NASA's model for motors of about 170 kW (Johnson et al. 2018, p.5), instead.
- At Makani's design density 0.95 kg/m³, η 0.71 × 0.88 and fixed-pitch propellers the law returns 1820 kg for MX2.

## What the mass decides (from the build-up model)

Yearly cost per kN of thrust at 12 m/s on a beam course (3000 flight hours, 150 launches), from the model; a 1000 m² soft kite costs 902 and a 2000 m² one 793.

| Structure | 54 m² | 100 m² | 200 m² |
| --- | --- | --- | --- |
| Base | 2435 | 2374 | 2593 |
| Low bounds | 1782 | 1620 | 1655 |
| High bounds | 3350 | 3305 | 3693 |
| No mass at all | 1315 | 1084 | 988 |
| Span cubed, equal at 54 m² | 2435 | 2653 | 3337 |

- A structure without any mass still costs more than the soft kite: upkeep per flight hour alone is 650-700 per kN, and avionics, perch, winch and launches the rest.
- From the low bounds at 100 m², the inputs that move it most are the upkeep (-341), the structure's price per kg (-179), the loop radius (-167), the avionics (-134) and the life (-100). Upkeep, avionics, structure price, perch and life together at their favourable bounds bring it to 856.
- Battery launch. At the low bounds the 54 m² kite weighs 920 kg and hovers on 368 kW, 0.4 kW per kg. Six minutes with half as much again in reserve at 80 % depth and the 150 Wh/kg of an installed pack (Johnson et al. 2018, Table 2) is 1.25 kg of battery per kW; the kite that carries it weighs about 2.1 t and hovers on about 1 MW. A battery beats the conductors only below about 5 kg/m² of kite, under half of the lightest wing above.

## Wing 7 against this model

Vander Lind (2013) gives Wing 7's inputs (Fig. 28.7, Table 28.1): CL 2, CD 0.25, parasitic 0.06, tether 0.11, AR 16, 50 m loop, 40° mean tether inclination, 20 m/s lowest flight speed, 20 kW at 10 m/s. Run through the loop model with those inputs on a 20-span tether, it flies from 6.5 m/s. The published curves pass zero power at about 5.3 m/s, read from Fig. 28.9, and flights lie about 1 m/s either side (Fig. 28.12). A kite that only pulls flies from about that wind, so the model is about 1 m/s high on the one wing with a flown power curve.

- Speed limit. Wing 7's 20 m/s is 1.8 times its stall speed of 11 m/s. The loop check here uses the stall speed. With the 1.8 the model flies Wing 7 from 7.5 m/s, further from flight, and MX2 from 8 m/s instead of 7, so the stall speed stays.
- Loop size. Base is MX2's 3.46 spans. Wing 7 flew 6.25 and M600 5.65. With MX2 on those radii and the longer tethers that fit them, 16.5-20 spans, it flies from 9 m/s instead of 7.
- Energy check. Eq. 28.33 is the argument of the loop check here: the mean speed pays for the climb above the slowest speed. As printed, with Fig. 28.7's values, it gives 48 m/s, or 33.9 m/s with the 2 under the root; the text says 30.5 m/s. None of these three is used.
- Propeller area. A = 0.52 of the wing at CD 0.2 and inflow 0.03, "comparable" to Wing 7 (Eq. 28.32), inside this input's bounds. The chapter gives no hover power, hover time or tether length for Wing 7, and its 20 spans and 500 MPa are assumptions for a plot.
- Tether. Ruiterkamp and Sieberling (2013, Fig. 26.3) show tether drag falling with size at a fixed length, as 1/√S. Here tether length goes with span, as Vander Lind sizes it, so the coefficient stays at 0.029 at every size. A loop radius that grows with span leaves no shorter tether on a large wing.
- Inertia. Ruiterkamp and Sieberling (2013, Sect. 26.3) expect a massless equilibrium to overstate power, as the wing keeps accelerating. Vander Lind (2013, Fig. 28.12) finds an analysis like it within about 1 m/s of flight, at 15 kg/m². Neither measures a wing of MX2's 34 kg/m² and up, so the sign of the error at this scale stays open.
- Pattern. Wing 7 flew circles, the PowerPlane a lemniscate at 7-9 m/s of wind.

## Makani's released code

Config and databases of google/makani at commit 1d66923 (Apache-2.0). The flight logs are in a Google Cloud listing that needs a signed-in account, and could not be fetched, so nothing here is checked against raw flight data. A pulling kite differs from Makani's generating kite as follows.

- Propellers: generating costs CD 0.09-0.18 on MX2's area, windmilling 0.019-0.022 at 40-50 m/s and 0.042 at 60 m/s from the propeller table (simulated), and a propeller held slow 0.10-0.13. Those fixed-pitch propellers cannot feather. A pull-only kite feathers: 0.0036 on the disc: 5.8 lb on a 9 ft propeller at 88° and 100 mph, against 94.4 lb locked and 60.1 lb free-wheeling at 17°, 0.058 and 0.037 (Hartman 1933, table p.12). Free-wheeling matches Makani's 0.022 on 0.61 of the wing.
- Airspeed: without generating drag a kite at the same lift coefficient flies faster, by (1+k) CD_sys / (CD_sys + CD_idle), 1.33-1.50 times at k = 0.5, so the tether limit arrives earlier. The balance of forces gives this by itself, and the airspeeds of the release are not used.
- Polar: the CL 1.81 and CD 0.123 of Part I are the zero-incidence row of the wing database, with no propellers or bridle in it, so nothing is subtracted. M600's parasitic offset from a flight glide is 0.075 against MX2's assumed 0.005, the largest open risk, carried in the high bound of the profile drag.
- Mass: a propeller out in hover needs 107 kW and 637 N m per propeller against 112 kW and 675 N m generating, so hover sized Makani's drives; the mass law rates them for the hover alone, at sea level.
- Hover: electrical to shaft efficiency 0.88.
- Wind: M600's takeoff window was 5-11 m/s in its test plan.

## Launch

Why VTOL on a ship: it is the only launch here that fits a deck and has flown from a floating base.

- Rotating arm: at least 30 m radius at 15 kg/m² (Fagiano and Schnez 2017), while real wings are 34-80 kg/m².
- Winch launch: a run of about 130 m (Fagiano and Schnez 2017).
- Catapult or rail with a capture system: shown at small scale only, must line up with the relative wind (Joshi et al. 2025, p.705, compare HTOL's spatial cost with VTOL's mass cost).
- Static lift alone needs 17-25 m/s of relative wind for these wing loadings.

Against it: the one offshore flight, from a moored spar buoy in 10 m/s and 1 m waves, lost the kite in final hover, with the buoy's motion a named cause (Part I, pp.392, 412). Part II calls launch and landing robust only onshore (p.132) and says that moving buoys with large-inertia base stations "are not well matched systems" (p.133). No source gives a limit on sea or wind for launch or landing, so the 3 m is our estimate, with a 1.5-4 m band, and the 17 m/s is held at the soft kite's launch limit, with a 13-20 m/s band. Above them a kite stays up and any landing is forced.

## Prices

There is no public price for a rigid kite. Structure and avionics come from Joshi et al. (2025, p.702), at a series of 50 or more without margin, so the paper's market price factor applies; its rope price (p.703) is what a rope maker charges, so the tether, bought like the soft kite's, takes no factor; EUR at 1.16 USD. Its avionics figure is for early commercial production with aviation certification and redundancy, which raise it from the EUR 15,000 of a prototype; the prototype figure is the low bound, a kite flown without that certification. The drive is two thirds of the 0.15 $/W of Bauer et al. (2018, p.14), three times a hobby motor's retail price per W for the motor, its drive electronics and the ground electronics; the ground third is the ship-side power here. Upkeep per flight hour is all of the airframe's maintenance (Echeverri et al. 2020, Part I, pp.108-110 printed), so its price pays no maintenance share. No deck system for a rigid kite has been built, so the winch, launch mast and ship-side controls are the soft kite's at the same force and area. The ship-side power, lifetime and loss per cycle are our own estimates and carry wide bounds. `cost_basis_notes.md` section 7 checks each against the common production stage.

## Not used

Part II's sea-state numbers (1-1.25 m, 10 m/s, p.145) are crane-lift criteria and not launch limits, and its cost tables are percentages of an undisclosed total (p.135).
