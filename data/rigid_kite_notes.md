# Rigid VTOL kite: scaling and launch evidence

Numbers behind the `rigid_*` inputs of `assumptions.yaml`. The rig is one wing with on-board rotors on an electrified tether. It pulls rather than generates, so the rotors are feathered in flight and work only in launch and landing.

## Reference design

The Makani MX2 design is the anchor (Echeverri et al. 2020, Part I, Tables 1 and 2): 54 m², 26 m span, 1852 kg with rotors, 300 m tether of 29.4 mm at 275 kg, 250-300 kN, 90 m loop radius, CL 1.81 and CD 0.123 at best performance (0.152 with tether). It was never built. The largest wing flown with on-board rotors is the M600, at 32.9 m².

## Built to pull

MX2 generates with its rotors. A kite that only pulls departs from it in three ways, each measured on the yearly cost per kN of a 54 m² kite at 12 m/s on a beam course (3000 flight hours, 150 launches):

| Step | Thrust | Price with tether, winch, perch | USD/kN/year |
| --- | --- | --- | --- |
| MX2 as is, windmilling rotors | 144 kN | 2.34 M | 2976 |
| Rotors feathered | 160 kN | 2.34 M | 2691 |
| Mass from structure, rotors and hover-rated drives; structure priced alone | 160 kN | 2.05 M | 2441 |

At 300 m² the same steps give 4284, 3868 and 3280. A 1000 m² soft kite costs 779.

- Rotor size: at 54 m², 0.3 of the wing as disc costs 14510 USD/kN, 0.61 12790, 1.0 12110, thrust within 1 %. Feathered, larger rotors pay; 0.61 is kept, 1.0 is the favourable bound.
- Tether: the M600 tether, which MX2 takes over, is rated 1 MW (Part II, p.40), about MX2's hover, so the conductors stay. A battery for an 850 kW peak at the 1.5 kW/kg estimated for a car pack (Sripad and Viswanathan 2021, SI) weighs about 560 kg, twice the whole tether.
- Aspect ratio: generating and pulling both maximise CL (CL/CD)², so 12.5 stays.

## Mass law

m = 1372 kg × (S/54)^(κ/2) + m_r A_d + 411 kg × (P_d/1.36 MW)^ε, κ = 2.75 (band 2.2-3.3), with the aspect ratio held; P_d is the hover power over 0.75, solved with the hover power. The routed size study also runs κ = 3.

- Structure: 1852 kg less the 480 kg of nacelles, powertrains, rotors, spinners and booms in Makani's roll-up of the 26 m wing, 1854 kg in all (Part II, pp.275, 287-288).
- Rotors: 65 kg of rotors and spinners on 8 × 4.15 m² for M600 (Part II, p.20; Part I, Table 1), 1.96 kg/m²; base 2.5 for feathering hubs (estimate), high 3.9.
- Drives: 480 kg less the rotors, 411 kg for 1.2 MW of shaft (Part I, p.184). ε = 0.81 from the motor regression W = 0.5382 Q^0.8129 with controller, inverter and cooling (Johnson et al. 2018, p.5), 1 for motors linear in torque (Part I, p.184). Low bound 241 kg: MX2's 344 kg of motors and controllers (36 + 7 kg × 8, Part II, pp.46-47) at 6.9 kW/kg, NASA's model for motors of about 170 kW (Johnson et al. 2018, p.5), instead.
- At Makani's design density 0.95 kg/m³, η 0.71 × 0.88 and fixed rotors the law returns 1823 kg for MX2.
- κ comes from whole wings with rotors and is applied to the structure alone.

- With on-board rotors, one wing that flew sits far below the anchor: Wing 7, 60 kg on 3.96 m² and 8 m (Vander Lind 2013, Fig. 28.7). To MX2 it gives κ = 2.91 by span and 2.63 by area. Its aspect ratio is 16 against 12.5: at the same area it has more span than MX2's planform and at the same span less area, so the two bracket κ at MX2's planform, and 2.75 lies between them. At κ = 2.75 the law gives 51 kg at Wing 7's area.
- From Wing 7 to the built M600 (32.9 m², 25.66 m, 1692-1731 kg) it is 2.87-2.88 by span and 3.15-3.18 by area, so the two wings actually built go about as span cubed. That is why κ = 3 runs beside the base.
- For ground-generation wings Sommerfeld et al. (2022) sweep κ over 2.7-3.3 as an assumption, against AP2 (5.5 m, 36.8 kg). van Hagen et al. (2023) use 2.7-3.0.
- Joshi et al. (2025, Table 10) give 700 kg at 20 m² to 10663 kg at 160 m² for horizontal-launch designs, about κ 2.5-3.2 between their optima, and state that VTOL "will have a different scaling due to the additional motors" (p.700).
- Eijkelhof et al. (2020) design a 150 m² wing of 6885 kg, without rotors, against 7.5 t from this law at κ = 2.75 and 8.6 t at κ = 3; from the MX2 anchor it gives κ ≈ 2.57.
- The PowerPlane of Ampyx, 28 kg on 3 m² and 5.5 m with no rotors (Ruiterkamp and Sieberling 2013, Sect. 26.2), carries 9 kg/m² against 15 for Wing 7; it does not bear on a law for wings with rotors.
- The M600 came out 40-70 % over its targets (Part I), so the risk is upward; the high bound of the reference mass covers 40 %.

## Wing 7 against this model

Vander Lind (2013) gives Wing 7's inputs (Fig. 28.7, Table 28.1): CL 2, CD 0.25, parasitic 0.06, tether 0.11, AR 16, 50 m loop, 40° mean tether inclination, 20 m/s lowest flight speed, 20 kW at 10 m/s. Run through the loop model with those inputs on a 20-span tether, it flies from 6.5 m/s. The published curves pass zero power at about 5.3 m/s, read from Fig. 28.9, and flights lie about 1 m/s either side (Fig. 28.12). A kite that only pulls flies from about that wind, so the model is about 1 m/s high on the one wing with a flown power curve.

- Speed limit. Wing 7's 20 m/s is 1.8 times its stall speed of 11 m/s. The loop check here uses the stall speed. With the 1.8 the model flies Wing 7 from 7.5 m/s, further from flight, and MX2 from 8 m/s instead of 7, so the stall speed stays.
- Loop size. Base is MX2's 3.46 spans. Wing 7 flew 6.25 and M600 5.65. With MX2 on those radii and the longer tethers that fit them, 16.5-20 spans, it flies from 9 m/s instead of 7.
- Energy check. Eq. 28.33 is the argument of the loop check here: the mean speed pays for the climb above the slowest speed. As printed, with Fig. 28.7's values, it gives 48 m/s, or 33.9 m/s with the 2 under the root; the text says 30.5 m/s. None of these three is used.
- Rotor area. A = 0.52 of the wing at CD 0.2 and inflow 0.03, "comparable" to Wing 7 (Eq. 28.32), inside this input's bounds. The chapter gives no hover power, hover time or tether length for Wing 7, and its 20 spans and 500 MPa are assumptions for a plot.
- Tether. Ruiterkamp and Sieberling (2013, Fig. 26.3) show tether drag falling with size at a fixed length, as 1/√S. Here tether length goes with span, as Vander Lind sizes it, so the coefficient stays at 0.029 at every size. A loop radius that grows with span leaves no shorter tether on a large wing.
- Inertia. Ruiterkamp and Sieberling (2013, Sect. 26.3) expect a massless equilibrium to overstate power, as the wing keeps accelerating. Vander Lind (2013, Fig. 28.12) finds an analysis like it within about 1 m/s of flight, at 15 kg/m². Neither measures a wing of MX2's 34 kg/m² and up, so the sign of the error at this scale stays open.
- Pattern. Wing 7 flew circles, the PowerPlane a lemniscate at 7-9 m/s of wind.

## Makani's released code

Config and databases of google/makani at commit 1d66923 (Apache-2.0). The flight logs are in a Google Cloud listing that needs a signed-in account, and could not be fetched, so nothing here is checked against raw flight data. A pulling kite differs from Makani's generating kite as follows.

- Rotors: generating costs CD 0.09-0.18 on MX2's area, windmilling 0.019-0.022 at 40-50 m/s and 0.042 at 60 m/s from the rotor table (simulated), and a rotor held slow 0.10-0.13. Those fixed-pitch rotors cannot feather. A pull-only kite feathers: 0.0036 on the disc: 5.8 lb on a 9 ft propeller at 88° and 100 mph, against 94.4 lb locked and 60.1 lb free-wheeling at 17°, 0.058 and 0.037 (Hartman 1933, table p.12). Free-wheeling matches Makani's 0.022 on 0.61 of the wing.
- Airspeed: without generating drag a kite at the same lift coefficient flies faster, by (1+k) CD_sys / (CD_sys + CD_idle), 1.33-1.50 times at k = 0.5, so the tether limit arrives earlier. The balance of forces gives this by itself, and the airspeeds of the release are not used.
- Polar: the CL 1.81 and CD 0.123 of Part I are the zero-incidence row of the wing database, with no rotors or bridle in it, so nothing is subtracted. M600's parasitic offset from a flight glide is 0.075 against MX2's assumed 0.005, the largest open risk, carried in the high bound of the profile drag.
- Mass: a rotor out in hover needs 107 kW and 637 N m per rotor against 112 kW and 675 N m generating, so hover sized Makani's drives; the mass law rates them for the hover alone, at sea level.
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

There is no public price for a rigid kite. Structure, avionics and rope come from Joshi et al. (2025, pp.702-703), at a series of 50 or more without margin, so the paper's market price factor applies; EUR at 1.16 USD. Its avionics figure is for early commercial production with aviation certification and redundancy, which raise it from the EUR 15,000 of a prototype; the prototype figure is the low bound, a kite flown without that certification. The drive is two thirds of the 0.15 $/W of Bauer et al. (2018, p.14), three times a hobby motor's retail price per W for the motor, its drive electronics and the ground electronics; the ground third is the ship-side power here. Upkeep per flight hour is all of the airframe's maintenance (Echeverri et al. 2020, Part I, pp.108-110 printed), so its price pays no maintenance share. The perch, ship-side power, lifetime and loss per cycle are our own estimates and carry wide bounds. `cost_basis_notes.md` section 7 checks each against the common production stage.

## Not used

Part II's sea-state numbers (1-1.25 m, 10 m/s, p.145) are crane-lift criteria and not launch limits, and its cost tables are percentages of an undisclosed total (p.135).
