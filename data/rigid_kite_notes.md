# Rigid VTOL kite: scaling and launch evidence

Numbers behind the `rigid_*` inputs of `assumptions.yaml`. The rig is one wing with on-board rotors on an electrified tether. It pulls rather than generates, so the rotors idle in flight and work only in launch and landing.

## Reference design

The Makani MX2 design is the anchor (Echeverri et al. 2020, Part I, Tables 1 and 2): 54 m², 26 m span, 1852 kg with rotors, 300 m tether of 29.4 mm at 275 kg, 250-300 kN, 90 m loop radius, CL 1.81 and CD 0.123 at best performance (0.152 with tether). It was never built. The largest wing flown with on-board rotors is the M600, at 32.9 m².

## Mass law

m = 1852 kg × (S/54)^(κ/2), κ = 2.5, band 2.2-3.3, with the aspect ratio held. The routed size study also runs κ = 3.

- With on-board rotors, the only evidence is Makani's two designs, about κ = 2.5 from their real spans. That is not a fit.
- For ground-generation wings Sommerfeld et al. (2022) sweep κ over 2.7-3.3 as an assumption, against AP2 (5.5 m, 36.8 kg). van Hagen et al. (2023) use 2.7-3.0.
- Joshi et al. (2025, Table 10) give 700 kg at 20 m² to 10663 kg at 160 m² for horizontal-launch designs, about κ 2.5-3.2 between their optima, and state that VTOL "will have a different scaling due to the additional motors" (p.700).
- Eijkelhof et al. (2020) design a 150 m² wing of 6885 kg, against 8.6 t from this law at κ = 3 and 6.8 t at κ = 2.5; from the MX2 anchor it gives κ ≈ 2.57.
- The M600 came out 40-70 % over its targets (Part I), so the risk is upward; the high bound of the reference mass covers 40 %.

## Makani's released code

Config and databases of google/makani at commit 1d66923 (Apache-2.0). The flight logs are in a Google Cloud listing that needs a signed-in account, and could not be fetched, so nothing here is checked against raw flight data. A pulling kite differs from Makani's generating kite as follows.

- Rotors: generating costs CD 0.09-0.18 on MX2's area, windmilling 0.019-0.022 at 40-50 m/s and 0.042 at 60 m/s from the rotor table (simulated). A rotor held slow costs 0.10-0.13, so idle has to mean windmilling. The pattern search charges the idle value alone.
- Airspeed: without generating drag a kite at the same lift coefficient flies faster, by (1+k) CD_sys / (CD_sys + CD_idle), 1.33-1.50 times at k = 0.5, so the tether limit arrives earlier. The balance of forces gives this by itself, and the airspeeds of the release are not used.
- Polar: the CL 1.81 and CD 0.123 of Part I are the zero-incidence row of the wing database, with no rotors or bridle in it, so nothing is subtracted. M600's parasitic offset from a flight glide is 0.075 against MX2's assumed 0.005, the largest open risk, carried in the high bound of the profile drag.
- Mass: M600's motor-generators and controllers are 411 kg of 1561 kg, but a rotor out in hover needs 107 kW and 637 N m per rotor against 112 kW and 675 N m generating, so the peak rating of a hover-only drive does not fall, and no mass saving can be claimed. Its continuous duty does fall; no figure follows from the release.
- Hover: electrical to shaft efficiency 0.88.
- Wind: M600's takeoff window was 5-11 m/s in its test plan.

## Launch

Why VTOL on a ship: it is the only launch here that fits a deck and has flown from a floating base.

- Rotating arm: at least 30 m radius at 15 kg/m² (Fagiano and Schnez 2017), while real wings are 34-80 kg/m².
- Winch launch: a run of about 130 m (Fagiano and Schnez 2017).
- Catapult or rail with a capture system: shown at small scale only, must line up with the relative wind (Joshi et al. 2025, p.705, compare HTOL's spatial cost with VTOL's mass cost).
- Static lift alone needs 17-25 m/s of relative wind for these wing loadings.

Against it: the one offshore flight, from a moored spar buoy in 10 m/s and 1 m waves, lost the kite in final hover, with the buoy's motion a named cause (Part I, pp.392, 412). Part II calls launch and landing robust only onshore (p.132) and says that moving buoys with large-inertia base stations "are not well matched systems" (p.133). No source gives a sea-state limit for launch or landing, so the 3 m limit is our estimate, with a 1.5-4 m band.

## Prices

There is no public price for a rigid kite. Structure, avionics and tether come from Joshi et al. (2025, p.702), which excludes margin, so the paper's market price factor applies. The drive is the 0.15 $/W estimate of Bauer et al. (2018, p.14), which includes ground power electronics. The perch, ship-side power, lifetime and loss per cycle are our own estimates and carry wide bounds.

## Not used

Part II's sea-state numbers (1-1.25 m, 10 m/s, p.145) are crane-lift criteria and not launch limits, and its cost tables are percentages of an undisclosed total (p.135).
