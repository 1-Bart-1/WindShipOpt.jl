# Literature-based improvements to model, methods text and checks

Written 2026-11-01 from the full texts in `paper/literature_pdfs/`. Page numbers
are printed page numbers (Tillig OE and TRD: PDF page − 1; Lu 2020: pp. 249–258;
Erhard: arXiv 1202.3641v3 pagination; Podeur: bottom-of-page numbers 1–12; EMSA:
"Page X of 270"). Quotes are verbatim from `pdftotext -layout`; values marked
**[calc]** are our own arithmetic, not printed in the source. Nothing below is
implemented; `model.tex`, `results.tex`, `introduction.tex`, `main.tex` and the
code were left to the other agent.

## Priority overview

| #  | Proposal                                                                     | Files                                                      | Priority |
| -- | ---------------------------------------------------------------------------- | ---------------------------------------------------------- | -------- |
| 1  | Keep deck rigs on the deck: cap the centre of effort, let the rudder balance | `src/rig.jl` (`WingRig`, `RotorRig`), `model.tex` §balance | high     |
| 2  | Rudder effective aspect ratio 3 → about 1.6                                  | `data/assumptions.yaml` `rudder_aspect_ratio`              | high     |
| 3  | Validation cases for the checks appendix (table below)                       | new `scripts/check_*.jl`, `sections/checks.tex`            | high     |
| 4  | Kite wing-loading limit: justify 0.5 kN/m² or move towards 0.7–1.0           | `assumptions.yaml` `kite_max_force_per_area`, `model.tex`  | high     |
| 5  | Router discretisation: CFL statement, edge-midpoint weather, grid check      | `src/routing.jl`, `model.tex` §routing                     | medium   |
| 6  | Rotor wind cut-out at 20 m/s                                                 | `src/rig.jl` `rig_force(::RotorRig, …)`, assumptions       | medium   |
| 7  | Interference factor as a function of apparent wind angle                     | `src/rig.jl`, assumptions                                  | medium   |
| 8  | Wind-profile sensitivity (power law 0.11 / 1/7)                              | `src/rig.jl` `wind_at_height`, assumptions                 | medium   |
| 9  | Forecast router: 12 h re-planning as sensitivity; Mason case                 | `src/routing.jl`                                           | medium   |
| 10 | Added-resistance uncertainty band (Mittendorf quantile regressions)          | `src/waves.jl`, assumptions                                | medium   |
| 11 | Rotor details: spin cap 160 rpm, idle drag, κ on side force                  | `src/rig.jl`, assumptions                                  | low      |
| 12 | Kite parameter ranges for the tornado (turn radius, tether length, window)   | assumptions                                                | low      |
| 13 | Hull side force: nonlinear Kijima term, cross-check with ShipCLEAN hull lift | `src/hull.jl`, `checks.tex`                                | low      |
| 14 | Citation fixes in `model.tex` and `assumptions.yaml`                         | `model.tex`, `assumptions.yaml`                            | medium   |

---

## 1. Keep deck rigs on the deck (high)

**Problem.** `WingRig` and `RotorRig` set
`centre_position = lateral_centre(hull)` = 2T/Y'_β forward of midship. For the
reference coaster (T/L = 0.0647, B/L = 0.155, C_B = 0.83) this is 0.34 L
**[calc]**, and about 0.32–0.33 L for the bulk and container classes **[calc]**.
`RotorRig` and `WingRig` only check that the row fits in 75 % of the deck
length, not where it stands. A row 0.75 L long centred at 0.34 L forward runs
from −0.04 L to 0.71 L, i.e. past the bow at 0.5 L **[calc]**. So the "no rudder
needed" placement is physically impossible for every large deck rig.

**Sources.**

- Kramer & Steen 2022, p. 18–19: "Theoretically, it is possible to place the
  sails such that they apply a side force at the location of the center of
  lateral resistance. In that case, the aerodynamic side force can be balanced
  by drift-induced forces alone. However, this is often impractical, especially
  when using several sails. The center of lateral resistance is usually far
  ahead of the midship location." KVLCC2: "between 0.44 and 0.54 ship lengths
  ahead of the midship location, for drift angle between 3 and 6°"; "The bare
  hull in this case study is seen to have a center of lateral resistance ahead
  of the bow."
- Kramer & Steen 2022, p. 17: "the difference in the resistance between a center
  of effort midship and the optimal center of effort is only around 1–2%."
- Tillig & Ringsberg 2020 (OE), p. 19: "savings are larger if the rotors are
  arranged further aft, i.e., if the side force on the rudder is higher." Table
  6, p. 20: R4 21.1 % (14.3 % initial), T6.1 36.0 % (32.1 %) after optimising
  positions, "a minimal distance between the rotors of 10% of the ship's length
  is ensured."
- Tillig OE p. 17: "the lift to drag ratio of the rudder is much higher than the
  lift to drag ratio of the hull." Kramer p. 18 says the opposite from CFD: "the
  hull is around 3 times as efficient as the rudder." The two models disagree;
  ours follows neither once the rig is constrained.
- Dhainaut et al. 2025, p. 120: optimal rotor positions "tend to be located
  towards the front of the ship … to counteract the yawing moment induced by the
  hull".

**Change.** In `WingRig(…)` and `RotorRig(…)`:
`row_length = count * spacing * unit_size`;
`centre_position = min(lateral_centre(hull), 0.5hull.length - bow_clearance - row_length/2)`,
with a new assumption `bow_clearance` (forecastle; no source found, e.g. 0.05 L
as engineering assumption). The existing rudder balance
(`F_r = (F_y x_h − M_z)/(−L/2 − x_h)`) then carries the rest. Better still: make
the centre position a design variable over the feasible deck window and keep the
cheapest, as Tillig and Dhainaut do. The kite keeps x_h (the tether can be led
from a deck fairlead), but fix the `KiteRig` docstring, which says "from a mast
on the bow" while `attach_position` is at the lateral centre. Update `model.tex`
§balance ("Every rig is placed where it balances best") accordingly.

**Expected effect.** Small for the saving if Kramer is right (1–2 % of
resistance), several points if Tillig is right. It removes an unphysical
advantage of large wing and rotor rigs and makes the "same advantage for all
three rigs" sentence in `model.tex` true only for small rigs; say so.

## 2. Rudder effective aspect ratio (high)

`rudder_aspect_ratio` = 3.0, reason "doubled by the hull above it acting as a
mirror plane". Kramer & Steen 2022, p. 8: "The effective aspect-ratio for the
rudder was found to be 0.93 times the geometrical aspect-ratio"; p. 18: "The
value of the estimated effective aspect-ratio for the rudder is roughly 1.57,
while the same value for the keel is 5.4." So the CFD-tuned value shows no
mirror doubling. Set the value to 1.6, low 1.2, high 3.0, and cite Kramer.
Kramer also supports `rudder_max_lift` = 1.0: "The rudder lift-coefficient is
limited to a maximum value of 1.0" (p. 15), and notes a 10° geometric limit
"would correspond to a limit on the lift-coefficient of approximately 0.5 for
our case study" (p. 15); ShipCLEAN reefs at "δmax = 10°" (Tillig OE p. 17).
Kramer's rudder area is "right above 2% of the underwater hull lateral area …
Bertram (2012) states that this variable is typically around 1.5% for cargo
ships" (p. 3); our DNV formula gives 1.8 % of LT for the coaster **[calc]**,
between Bertram and Kramer.

**Expected effect.** None today (the rudder carries no load with the rig at
x_h); with proposal 1 it roughly doubles rudder induced drag. Do 1 and 2
together.

Also `leeway_limit` reason can cite Kramer p. 8: "the drift angle during the
route simulations was generally below 6°", and Reche-Vilanova et al. 2021, Table
1 p. 95: "Leeway [-10°:10°] … Heel [-10°:10°] … Rudder [-20°:20°]". Kramer
limits heel to 10°: "The heel angle is limited to a maximum value of 10◦…
(Tillig and Ringsberg, 2020) use 8◦" (p. 15).

## 3. Validation cases (high)

Ready-to-use cases. "Reported" is the source's own number; anything else is
marked.

| Case                                         | Ship (L, B, T, C_B, Δ/dwt, speed)                                                                                                                            | Rig                                                                                                                                          | Route, weather                                                                                                                                | Reported                                                                                                                                                                                                                                                             | What our model needs                                                                                         |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| **A. Podeur 2016, kite**                     | 2200 TEU Fort class; LOA 197.2, LPP 187.6, B 30.2, T 11.0 m; ∇ 41 767 m³ (C_B 0.67 **[calc]**); A_LR 4314, A_FR 779 m²; propeller D 7.79 m (Tableau 3, p. 8) | 1 kite 800 m², CL 0.776, ε 12.02° (12.2° in Tableau 2), lines 300 m (p. 8); flies Bft 2–7, 3 < V_WR < 17 m/s (p. 5)                          | Halifax–Le Havre great circle, constant speed 16 and 19 kn; ERA-Interim 0.75°/6 h, 2010–2014, 125 round trips per speed (pp. 3, 8)            | LH→Halifax 6.0 % / 3.1 %; Halifax→LH 18.2 % / 10.2 %; round trip 12.1 % / 6.6 % at 16 / 19 kn (Tableaux 5–7, pp. 9–11). Flight time 60 %/50 % and 81 %/75 % of the passage. Model underpredicts noon-report fuel by 12 % (p. 7–8)                                    | fixed great-circle, fixed-speed mode in `routing.jl`; Halifax is inside the ERA5 box; years differ (2017–19) |
| **B. Tillig & Ringsberg 2020 OE, MR tanker** | LOA 183, B 32.2, T 11.0 m, Δ 50 600 t (C_B 0.76 on LOA **[calc]**), v_des 15, v_service 12 kn, GM0 4.4 m, deck 4.2 m (Table 2, p. 15)                        | 4 rotors 5 × 30 m, base 3 m, 59 t each, max operating wind 20 m/s (Table 3, p. 16); also T3.1, T6.1                                          | polar, no route: TWS 10 m/s, 12 kn                                                                                                            | savings up to 65 % at TWA ≈ 110°, losses below 40–50° (p. 15); 4 rotors max ≈ 100 kW each ≈ 15 % of calm-water propulsion power at 12 kn (p. 15) ⇒ ≈ 2.7 MW **[calc]**; year-weighted 26.0 % (rpm control), 24.8 % without (p. 17); Table 6 T3.1 23.1 %, T6.1 36.0 % | performance table only; cheapest and most direct rotor check                                                 |
| **C. Tillig OE, RoRo**                       | LOA 200, B 27.0, T 6.5 m, Δ 21 000 t (C_B 0.58 **[calc]**), v_des 20, v_service 18 kn, GM0 1.0 m, two propellers, double rudders (Table 2, p. 15)            | 4 rotors 5 × 30 m, aft                                                                                                                       | polar at TWS 10 m/s, 18 kn                                                                                                                    | up to 55 % at TWA ≈ 110° (p. 15); 100 kW per rotor ≈ 5 % of calm-water power at 18 kn ⇒ ≈ 8 MW **[calc]**; 14.3 % / 12.0 % with / without rpm control (p. 17)                                                                                                        | single-propeller model is a limit; use as calm-water and polar check only                                    |
| **D. Tillig et al. 2020 TRD, MR tanker**     | same tanker; propeller 130 rpm at design speed (Table 2, p. 6)                                                                                               | 1, 2, 4, 6 rotors of 3 × 18, 4 × 24, 5 × 30 m, **no interaction** (Table 3, p. 11)                                                           | Rotterdam–New York–Houston–Rotterdam, 12 kn, 9961 nm, JRA-25 statistics (pp. 6, 11)                                                           | mean weather "virtually no savings"; Monte Carlo max 20 % (6 × 5 × 30 m); up to 71 t (12 %) per round trip (p. 12); 6 × 5 × 30 m up to 85 % at 20 kn TWS (p. 11)                                                                                                     | κ = 1 run; our New York and Houston routes cover two of three legs                                           |
| **E. Mason et al. 2023, Panamax**            | 80 000 dwt bulk carrier, design speed 14.5 kn, T 14 m (p. 2); speeds 8–14 kn, engine cap 9.5 MW (pp. 4–5)                                                    | 4 rotors 35 × 5 m (p. 2)                                                                                                                     | Route 3 Caribbean (26.8N 74.5W) → Gibraltar (35.9N 6.8W), 6400 km, ETA = great-circle time, 2018–2020, departure every 6 days (Table 1, p. 7) | eastbound GCR 11.5 %, a priori routed forecast 28.7 %, realised 21.2 %, adaptive (12 h) 25.4 % (Figs. 7, 13; values read from plots)                                                                                                                                 | ETA-constrained routing; forecast router. Only L/B missing: use our Panamax class                            |
| **F. Penloup 2021, kite points**             | ship speed 19 kn                                                                                                                                             | 320 m², zero mass, SWL 100 kg/m², CL 0.6/1.2, f 4/10, L_t/√A 16.77/33.54; wind U10 (z/10)^(1/7) (pp. 178–181)                                | point forces at V_WT 7 and 17 m/s, TWA 60/120/180°                                                                                            | Table 4, p. 183, e.g. CL 0.6, f 4, L_t 300 m: 8.22, 12.3, 0.07, 47.33, 151.2, 245.0 kN; all high: 74.57, 171.0, 0.18, 162.5, 292.6, 308.0 kN                                                                                                                         | `pattern.jl` with mass off, flight drag set to reach f; direct kite-model check                              |
| **G. Reche-Vilanova 2021, Maersk Pelican**   | LOA 244.6, LPP 233, B 42.03, T 15.45 m, 109 647 dwt, 15 260 kW, 15.3 kn (p. 107)                                                                             | 2 rotors 30 × 5 m                                                                                                                            | trial data at 12.5 kn, TWS bins 0–12.5 m/s (p. 107)                                                                                           | only plots (Fig. 11) and "fair agreement" (p. 114); press figure 8.2 % (ref. list p. 116)                                                                                                                                                                            | qualitative only                                                                                             |
| **H. Bentin 2016, BBC Hudson**               | 17 500 dwt, LPP 133–134, B 22.8, T 8.3 m (full), C_B 0.78–0.72, 7074 kW, 15 kn (pp. 156–157)                                                                 | 4 rotors 25 × 4 m (p. 160), generic coefficients                                                                                             | Baltimore–Wilhelmshaven, 13 kn, DWD 2008 (p. 160)                                                                                             | WASP −36 % GC / −53 % routed eastbound, −14 % / −28 % westbound (Table 1, p. 161); routing alone ≈ 4 % / 8 %                                                                                                                                                         | both ports lie inside our weather box; qualitative only, rotor model is generic                              |
| **I. Traut 2014, routes**                    | type, dwt, speed, power only, e.g. Tubarão–Grimsby bulk 50 000 dwt, 11.2 kn, 3700 kW (Table 1, p. 366)                                                       | kite 500 m², CL 1.0, CD 0.286, 350 m rope, circle radius 10° at 25° elevation; rotor 35 × 5 m, CL 12.5, CD 0.2, CM 0.2, SR 3.5 (pp. 363–364) | UK Met Office UM 2011, 53 weekly fields, shortest path (p. 366)                                                                               | Tubarão→Grimsby kite 171.0 kW out / 236.3 back, rotor 200.6/200.7 kW (Table 1, p. 366)                                                                                                                                                                               | our Tubarão route exists; compare mean rig power, not savings                                                |
| **J. Dhainaut 2025**                         | same 2200 TEU ship as A (Table 1, p. 105); rudder 37.08 m²                                                                                                   | 6 rotors (3 per side), span 25 m, AR 6, ShipCLEAN polynomials (pp. 105, 108)                                                                 | Brittany–Halifax, ECMWF 2014, t_max 140/160 h, no waves, no heel (pp. 103, 112)                                                               | 3 per side: −14 % (p. 118; Fig. 12 suggests ≈ 11 % at 140 h, ≈ 18 % at 160 h); no rotors: +20 h ⇒ −30 % fuel                                                                                                                                                         | combined with A it gives kite and rotor on one hull and route                                                |

Recommended for `checks.tex`: **B** (rotor polar and calm-water power), **F**
(kite point forces), **A** (kite voyage). B and F need no router; A needs a
fixed-route constant-speed mode (also useful to report "routing gain" as Mason
and Bentin do). Lu & Ringsberg 2020 is not reproducible: no displacement or
power ("due to the confidentiality agreements … further details of the ships are
not able to be provided", p. 253) and the parametric tables are mislabelled
(Table 3 "Route 1" carries the Route 2 numbers 367 h and 1162.1 t; Tables 4 and
6 use 194 h, matching neither voyage, p. 256).

Nearest existing classes: the MR product tanker class (174 m) for B and D, the
Aframax class (236 m) for Lu & Ringsberg's 250 m tanker, the Kamsarmax class
(225 m) for E; the 2200 TEU ship of A and J lies between the feeder (165 m) and
Panamax container (245 m) classes, so A and J need their own hull from the
particulars above.

Dadd et al. (2011) could not be obtained; case F (Penloup 2021) is the kite-model check.

## 4. Kite wing-loading limit (high)

`kite_max_force_per_area` = 0.5 kN/m² (low 0.4, high 1.0). Penloup et al. 2021,
p. 176, citing Paulig: "In extreme load, a value of 1kN / m2 is adopted, while
for the average load one takes 0.7kN / m2"; p. 181: "100 kg. m−2, which
corresponds approximately to a limit of 1 kN of traction per square meter of
kite. This limit can be found in SkySails documentation"; Podeur 2016 Tableau 2,
p. 5: "Charge alaire 100 kg/m2". Penloup p. 173: "The maximum wing load
parameter is the one that shows the most influence on the propulsive force. Over
50% of the gains obtained through this study are directly attributable to it";
p. 190: gain "rising about 50% in average, when doubled".

**Change.** Keep 0.5 as base if the Faggiani/Kitepower basis is preferred, but
(a) the `reason` gives the 1.0 bound from the SkyPower100 final report (Junge et
al. 2023, sec. I.4, "Flächenlasten bis zu 1 kN/m²"), (b) make sure the tornado
runs the 1.0 bound, and (c) state in `model.tex` that the limit is below the
SkySails design value. `discussion.tex` ("We hold both at the values of today's
kites") is then accurate only with this caveat. **Effect:** large on kite size
and saving at the cost optimum, since the large kites run at their force limit.

## 5. Router discretisation (medium)

Wendling & Lagemann 2025:

- p. 366–367: "the shortest distance separating grid stages shall be no shorter
  than the maximum distance traveled in one time step"; with nearest rounding "C
  < 0.5", with upward rounding "C < 1", C = V_max Δt/Δx.
- p. 367–368: coarse time steps are over-optimistic because "Rounding is
  susceptible to reduce sailing time on an arc by up to ½∆t … rounding can
  virtually decrease energy consumption 'for free'".
- p. 370: "A very large forward resolution is prone to error … some weather
  conditions may be skipped entirely, and the assumption of constant weather
  along an arc becomes unrealistic."
- p. 376: "coarser weather data tends to yield underoptimistic outcomes …
  preferable to keep ∆Wxy under 1° and ∆Wt under 6h."
- Table 6, p. 378: "∆x < 100 km"; "D > 20%"; "2 < AR < 4"; "Na ≥ 5"; "∆Wt < 3h";
  "∆Wxy < 0.5°".

Our grid: Δx = 90 nmi = 167 km (results at 360 nmi = 667 km), Δt = 3 h, node
spacing 60 nmi ⇒ aspect ratio 1.5, ±3 neighbours ⇒ Na = 7 **[calc]**; weather
1.5°/6 h. With Δt = 3 h and Δx = 90 nmi, C = 0.5 at exactly 15 kn and above 0.5
for the faster classes **[calc]**.

**Changes.**

1. `model.tex` §routing: the sentence "A ship at 15 kn sails 45 nmi in one bin,
   half a stage or less, which meets the condition" holds only up to 15 kn.
   Because the router carries the exact arrival time, Wendling's rounding error
   does not apply to fuel; say that instead, and drop the half-stage claim or
   restrict it.
2. `src/routing.jl`: sample wind and waves at the edge midpoint (position and
   time) rather than at the edge start; on 360-nmi edges the start-point sample
   covers up to a day of sailing. Cheap and removes the "constant weather along
   an arc" objection.
3. The grid check in `checks.tex` already shows < 3 % change; add one run with
   45-nmi stages and 1.5 h bins on the fastest class (Megamax) to confirm the C
   > 0.5 regime.
4. `discussion.tex` now states the weather-resolution caveat (coarse weather
   understates the gain).

## 6. Rotor wind cut-out (medium)

Tillig OE Table 3, p. 16: "Max. wind speed for operation [m/s] 20". Our rotors
run in any wind (only the 47 m/s surface-speed cap). Add `rotor_max_wind` (20
m/s apparent wind at mid height, low 18, high 25) and return `NO_RIG_FORCE`
above it in `rig_force(::RotorRig, …)`, analogous to `kite_max_wind`. The same
for wings if a source is found (none in these papers). **Effect:** small on
savings, removes an asymmetry with the kite in storms.

## 7. Interference factor vs apparent wind angle (medium)

Done: κ(n, s) = 1 − (1 − 1/n) A exp(−s/s0) on thrust only, wings A = 0.30, s0 = 2.86 c, rotors A = 0.38, s0 = 2.72 D (assumptions.yaml; wings: A is the fixed-trim CFD fit less a third for independent sheeting and s0 our engineering estimate; rotors: fit in data/interference_notes.md). Still constant over apparent wind angle.

- Rotors: Tillig OE p. 9: two rotors 3 D apart, "thrust coefficient is
  significantly reduced, up to 38% according to measurements at 30° AWA … In
  reaching conditions the thrust coefficient is increased with up to 7%".
  Reche-Vilanova 2021, p. 106: "when rotor sails are spaced 15 diameters apart,
  the interaction effects are very small. However, when they are spaced 3
  diameters apart, interaction effects include changes in the aerodynamic
  coefficients of up to 20%". Han et al. 2025 (Processes, p. 12): wake "up to
  8D"; "Approximately 9D, was adopted as a preliminary spacing guideline".
  ShipCLEAN's own interaction effect on four rotors was "less than 1%" in thrust
  (Tillig OE p. 8).
- Wings: Malmek et al. 2024, Table 6, p. 10: a lifting line without interaction
  errs in driving force of four sails by "40% … 20% … 23%" at AWA 30/60/90°. van
  Reen 2026, abstract: "The in-line layout experiences thrust losses of up to 6%
  … The parallel layout exhibits larger reductions ranging from 10% to 28%."
  EMSA 2023 p. 29 citing Mboumba Mboumba 2022: "the thrust of three sails was
  equal to three times the thrust of one sail. However, for five sails, the
  total thrust was only 3.83 times".

**Changes.** (a) Done: model.tex cites Malmek 2024 and Xu 2025 for A, van Reen 2026 for sheeting and Wang 2024 for the 10 c reference of s0, with wing A = 0.30 as the code uses; discussion.tex compares Mboumba 2022 with the 91 and 85 % this gives. (b) Optionally make κ a function of apparent wind angle, e.g.
0.62 at 30° rising to 1.0 at ≥ 90° for rotors 3 D apart (from Tillig's two-rotor
measurement) and 0.8 at low AWA to 0.95 at beam for wings — only for the number
of units actually used; count = 1 ⇒ κ = 1. (c) `rig_force` applies κ to thrust
but not to side force, so shading lowers thrust while keeping full side force.
Either apply it to both lift and drag (physically consistent) or state that the
side force is deliberately not reduced (conservative).

## 8. Wind-profile sensitivity (medium)

Our log profile with z0 = 0.2 mm gives 1.26 × U10 at 170 m and 1.085 × at 25 m
**[calc]**. Power laws used in the literature: exponent 0.11 (Reche-Vilanova p.
98: "exponential gradient with exponent 0.11"; CE Delft 2016 p. 37 "P = 0.11"),
1/7 (Penloup p. 178), 0.27 (Tillig OE p. 5, "Hellmann coefficient … 0.27").
These give 1.37, 1.50 and 2.15 at 170 m **[calc]**. Even the `high` roughness
1e-3 m gives only 1.31 **[calc]**; matching the 0.11 law at 170 m needs z0 ≈ 5
mm **[calc]**. Add a tornado case with the 0.11 power law (or z0 = 5e-3) and say
in `model.tex` that the profile is at the low end, conservative mostly for the
kite (now stated in `discussion.tex`).

## 9. Forecast router (medium)

Mason et al. 2023: re-plans "in 12-h intervals" (p. 12) and notes standard ships
re-plan "around once per day". Abstract-level 44 % is the loss of the routing
increment on Route 3 eastbound: "carbon savings reduce from a theoretical 2.50
times increase to a realised 1.84 times increase, representing a 44% reduction
in additional savings from the technology" (p. 9). Adaptive re-routing recovers
to 0.794–0.879 of the maximum potential on Routes 2 and 3 (p. 12). Their
forecasts are TIGGE control runs of 360 h, so they need no climatological
fallback; ours (other-year same-date weather beyond the horizon) is new and
should be described as such. **Change:** add a 12 h re-planning sensitivity;
report our forecast loss in Mason's terms (share of the routing increment lost)
so the numbers compare. `related.tex` and `discussion.tex` now cite this
correctly; the earlier text ("daily re-routing recovers it", "up to 44 % of the
saving") overstated it.

## 10. Added-resistance uncertainty (medium)

Mittendorf et al. 2022: database "1127 samples of 25 ships" (p. 3); ranges "L ∈
[90, 355] m, C_b ∈ [0.503, 0.858] and Fn ∈ [0.0, 0.3]", "L/B ∈ [5.05, 7.5]",
"B/T ∈ [2.5, 4.7]" (p. 3); R² 0.711–0.731 for the recalibrated fits (Table 3, p.
9); "a 90% prediction interval … τ = 0.05 and τ = 0.95" (p. 8); "The largest
uncertainty is present in resonant conditions" (p. 10). **Changes.** (a) Check
every class against these ranges (the 85 m coaster is below L = 90 m; the
Megamax at about 400 m is above 355 m; coaster L/B 6.4 is inside); list the
out-of-range classes in `model.tex`. (b) If Table 2 gives the τ = 0.05/0.95
parameter vectors, add them as `low`/`high` of a new `added_resistance_quantile`
assumption for the tornado. Kramer & Steen use a Pierson–Moskowitz spectrum
(p. 10) rather than JONSWAP; not a change, but the DNV γ rule in
`formula_checks.md` §1 is the better default.

## 11. Rotor details (low)

- Spin cap: Reche-Vilanova p. 112: "maximum spinning RPM limit (defined at 160
  in this case according to Norsepower)" for 30 × 5 m ⇒ 41.9 m/s **[calc]**,
  below our 47 m/s (EMSA's 180 rpm). Lower the base or widen `low` to 40
  (already 40).
- Idle drag: Tillig OE p. 9: at SR 0.5 "the ShipCLEAN simulation gives a value
  of about 0.3, while the full and model scale measurements show values of about
  0.5–0.8"; our polynomial gives 0.196 at 0.5 **[calc]**, and Tillig idles at
  "spin ratio of approximately 0.5" (p. 17). The ship will choose SR 0.5 in head
  wind, so idle drag is optimistic. Reche-Vilanova uses "CD … assumed to be 0.5"
  for the idle rotor (p. 102). Floor the drag at 0.5 for SR ≤ 1, or note it.
- Dhainaut p. 109: "the power is solely dependent on the spin ratio … can lead
  to non-physical solutions"; our surface-speed cap already prevents this.

## 12. Kite parameter ranges (low)

- Turn radius (ours 1.6 projected spans): Penloup p. 187: "Fagiano… minimum
  turning radius about 2.5 wingspan. In the case of Dadd (2010) and Behrel
  (2018a), turning radii of about one wingspan were measured"; p. 176 (Bigi):
  "the optimal turning radius of the trajectory is approximately equal to the
  wingspan". Use 1.0–2.5 as low/high.
- Tether length (ours 13 projected spans ⇒ L_t/√A = 22.5 at AR 3 **[calc]**):
  Penloup's range 16.77–33.54 (p. 181); second most influential for TWA > 70°
  (p. 173).
- Glide ratio and CL: Traut CL 1.0, CD 0.286 (p. 363); Podeur CL 0.776, ε 12.2°
  (p. 5); Erhard "E = 4–5" (Table II, p. 6); Penloup "achieving CL higher than
  0.8 is uneasy" (p. 180). Our calibration target (4 at CL 0.8) sits inside; now
  in `discussion.tex`.
- Flight window: Podeur "entre Beaufort 2 et Beaufort 7 (3m/s < VWR < 17m/s)"
  (p. 5), on ship-relative wind; Traut deploys when "the rope force does not
  exceed 1000 kN at any point, and d < 135°" (p. 366). No paper uses a
  wave-height limit; our 4 m stays an engineering assumption.
- Figure of eight vs static: Penloup p. 189: at 19 kn, TWA 40°, 17 m/s, "the
  wing loading in static flight is 688N/m2. While in dynamics … 17 times higher
  with a glide ratio of 4". Useful as a check that a kite at rest and an eight
  differ by this order.

## 13. Hull side force (low)

- Kim & Lee 2021, p. 5, Kijima also has "Y′ββ = 2.5d(1−Cb)/B + 0.5"; linear-only
  underestimates side force at large drift (conservative near 10°).
- Kijima's database: 13 merchant models, C_B 0.522–0.835, L/B 4.505–6.897 (Kim &
  Lee Table 1, p. 4); Kim & Lee p. 11: "the accuracy tends to suffer when
  applying the formula to a different hull form". Cite Kijima et al. (1990) as
  primary source.
- Cross-check: ShipCLEAN hull lift Eq. 33 (Tillig OE p. 12), "cL =
  0.8·0.5π·AR·sinβ + 0.6541·sin|β|·sinβ·cosβ" with AR = T/L on L_pp T
  (reconstructed sign), and induced drag Eq. 37 "cDi = 0.66·cL·|β|^0.6 +
  0.6541·sin³|β|". Tillig p. 12: it "gives a 30% lower lift coefficient than the
  measurements for the Series 60 hull and a 50% higher value for the tanker". A
  short check comparing our Y'_β β and leeway drag with Eq. 33/37 at 5° for the
  coaster and the MR tanker would bound the leeway-drag lower-bound issue in
  `formula_checks.md` §2.

## 14. Citation fixes (medium)

- `model.tex` §wings: interference source: done (see 7a), with Wang 2024 cited for the 1.5 c spacing and the 10 c reference of s0.
- `model.tex` §balance: the 8° heel limit is Tillig's; Kramer uses 10° (p. 15).
  Cite both.
- `model.tex` §waves: Mittendorf does not use the name "SNNM"; it recalibrates
  Liu & Papanikolaou (2020). Kramer calls it SNNM. Write "the formula of
  \citet{liu2020} as recalibrated by \citet{mittendorf2022}".
- `assumptions.yaml` `rudder_aspect_ratio`: reason contradicted by Kramer (see
  2).
- `refs.bib` `tillig2020`: DOI 10.1016/j.oceaneng.2020.107603 added (from the
  PDF header).

## Errors found in the sources (do not cite these numbers)

- Lu & Ringsberg 2020: Route 2 rotor saving "107.9 t" (text) vs 75.5 t from
  Table 2 **[calc]**; the annual "1755 t" inherits it; projected rotor area "108
  m2" for an 18 × 3 m rotor (54 m²); Tables 3–6 route labels and times (p.
  255–256).
- Tillig OE: abstract 30 %/14 % vs Table 6 36.0 %/21.1 % after position
  optimisation; "approximately 2.5%" from rpm control vs 2.3 and 1.2 points
  reported (p. 17, 21).
- Tillig TRD p. 16: "12 to 16 kn will increase the forces from the rotors by
  about 40%" vs (16/12)² = 1.78 **[calc]**.
- Dhainaut p. 118: "14%" for three rotors per side vs about 11 % (140 h) and 18
  % (160 h) read from Fig. 12.
- Podeur: round-trip 6.6 % (Tableau 7) vs 6.7 % (abstract); ε 12.2° vs 12.02°.
- Bentin 2016: abstract says "branch and bound", the method section an A*
  search; weekly vs daily departures.
- Huang & Souppez 2025 p. 266: mean ship speed "24.97 kn" called "a more
  sensible ship speed"; do not cite.
- Penloup 2021 p. 180: text says linear area scaling, Eq. 13 prints √(A_k/320).
