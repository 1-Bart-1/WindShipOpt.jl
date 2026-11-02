# Audit of the rigid wing sail inputs: polars, price, life, sizing

Audit of every wing input against published data, and a check on whether the model is unfair to wings compared with rotors. Built 2026-11-01. "Derived" marks a number computed here. "Claim" marks a manufacturer or operator figure that nobody has verified independently. Model runs use the code and `assumptions.yaml` as they stood on 2026-11-01 at 16:00 (draft fidelity, Guadeloupe corridors, 6 departures), with the wing changes applied as method overrides in a scratch session. `src/` and `assumptions.yaml` were not edited.

## Verdict

The wings lose for physical reasons, not because their inputs are unfair. The wing polar reproduces the one measured full-scale average, BAR's 1.5 t of fuel per WindWing per day. Per unit, one 750 m² WindWing gives about the same mean thrust as one 35 × 5 m rotor in the model (39 against 41 kN). Rotors win because a deck takes about four rotors for every three wings, and a rotor costs and weighs less than a wing of equal thrust. Three inputs are pessimistic for wings: lift ceiling, interference and lifetime. One input is strongly optimistic: wing mass. The rotor coefficients sit at the optimistic end of the rotor literature. Corrected together, the inputs leave the 140 m e-methanol ship to Guadeloupe where it was: wings save 3.0 % and rotors 8.4 % on today's code. Even the most wing-friendly set found here (7.3 %) stays below the rotors (8.4 %) unless the rotors' lift is also taken down to CFD or wind-tunnel level.

**The paper's numbers are stale.** The current code gives a cost saving of 3.0 % for the best wing size and 8.4 % for 800 m² of rotors on this ship. `output/paper/situations.csv` has 11.2 % and 22.8 %. The 0.25 price case is 13.9 % there. `src/` and `assumptions.yaml` have changed since those files were written; a clean session with no overrides reproduced the new numbers. The wing-to-rotor ratio is about the same in both (0.36 now, 0.49 then), so the conclusions below hold. The paper must be regenerated before any number is quoted.

## 1. Polars

### What the model does

CD = 0.02 + (0.03 + 1/(π · 2.8 · 0.9)) CL² = 0.02 + 0.156 CL², with CL from 0 to 1.8 in 37 steps (`trim_settings`). This gives L/D 8.5 at CL 0.5, 5.7 at 1.0, 4.0 at 1.5 and 3.4 at 1.8. Induced drag is 81 % of the drag at CL 1.8. The deepest trim is CL 1.8 at CD 0.53, so dead downwind the wing gives at most CD 0.53.

### The deck mirror (derived)

The minimum induced drag of a vertical wing whose root stands a gap g above an infinite mirror plane was computed in the Trefftz plane: optimal loading, 1,200 panels, converged to three digits. The ratio of effective to geometric aspect ratio is:

| gap / span  | 0    | 0.01 | 0.02 | 0.05 | 0.10 | 0.15 | 0.20 | 0.30 | 0.50 | 1.0  |
| ----------- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| AR_eff / AR | 2.00 | 1.36 | 1.30 | 1.21 | 1.15 | 1.11 | 1.09 | 1.06 | 1.04 | 1.02 |

The mirror benefit collapses within the first few percent of gap. The model's factor of 1.4 therefore stands for a root that almost seals to the deck. Installed wings sit on pedestals:

- WindWings: "Including the pedestal, the top of the WindWing is typically 45m above deck" (BAR product page). With a 37.5 m span the root is about 7.5 m up, g/b ≈ 0.2, factor ≈ 1.09.
- Oceanbird: "46 meters tall from the foundation to the top", "the wing itself is 40 meters" (theoceanbird.com/wing-560). That is about 6 m, g/b ≈ 0.15, factor ≈ 1.11.

Two further effects cut the benefit: the deck is a finite plate one or two chords wide, and the wind shear unloads the root (Malmek et al. 2024, p. 10: where "the gap between the deck and sail is large, the assumption of a sail-force mirror plane in the deck should be challenged").

The 1.4 is therefore optimistic for real installations by about 25 % in effective AR. The model, however, also places the wing root at deck level and gives no height to a pedestal. That over-states the wing's height by the pedestal's 6–7 m under the air-draft cap. The two errors go in opposite directions. Runs: endplate 1.1 costs 0.2 pp of saving, and a sealed 2.0 gains 0.4 pp. **Induced drag at AR 2–3 is not over-penalised; if anything it is under-penalised.**

### 2D and 3D data

- **Xu et al. 2025** (IDDES, 1:58 Oceanbird wing, NACA0015, span 1.385 m, chord 0.4 m, geometric AR 3.46 on the tunnel floor, Re 7.6·10⁵; Tables 3–4): single sail CL 0.769 and CD 0.042 at α 10°; CL 1.078 and CD 0.122 at 17°, with separation starting from the floor boundary layer. With a floor mirror (AR_eff ≈ 6.9, e 0.9), CL 0.77 gives an induced CD of 0.030. With the model's 0.02 + 0.03 CL², the total is 0.068 against the 0.042 computed. The model's viscous term is about twice too high at mid CL for a single-element section, but that is not the operating point. A single-element wing tops out at CL ≈ 1.1, so the model's 1.8 is already a multi-element wing.
- **Reche-Vilanova et al. 2021** (lifting line plus DATCOM, AR 2, no mirror; Table 5): 3D CL max 1.18 without a flap, 1.70 with a 30 % plain flap, 1.73 with a 30 % slotted flap. The model's 1.8 sits just above their best two-element wing.
- **BAR WindWings**: "Our patented three-element wing design … delivers 2.5x the lift of single element wing" (product page, claim). No CL is published. If the 2.5 means maximum lift, a 3D single-element CL max of 0.9–1.1 (Xu, Reche-Vilanova) gives a three-element wing about 2.2–2.7. Read as lift at equal α, it means less. 2D multi-element wingsail CFD gives 1.95–2.65 (Yao 2026, Ocean Eng. 362, cited in `assumptions.yaml`). That paper is not in `paper/literature_pdfs/` and could not be checked here.
- **Malmek et al. 2024**: the Oceanbird wing in 3D RANS stands on a symmetry-plane floor with "the effective span … doubled" (p. 3). Its forces are therefore a sealed-mirror upper bound, not the pedestal case.
- **van Reen 2026** is a 2D panel and RANS study of symmetric cambered sections. It has no 3D polar and is used here only for interference.

**CL max 1.8 is pessimistic for a three-element WindWing** and about right for a two-element wing. A run at 2.2 raises the wing's saving from 3.0 to 4.6 % at the largest size. Proposed value: 2.0, range 1.6–2.5.

### Downwind and post-stall trim

The model stops at CL 1.8 with CD 0.53. A wing turned across the wind is a low-AR plate with CD ≈ 1.2. It is therefore under-predicted by a factor of 2.3 at an apparent wind angle of 180°. In `rig_polar_figure` conditions (10 m/s, 10.5 kn) that is 10.5 kN against about 24 kN for 1,500 m² dead downwind. The attached branch is better than a post-stall plate (CD90 1.2, CL = CD90 sin α cos α) up to an apparent wind angle of about 155°. Adding a post-stall branch with α 25–90° to the trims changes the Guadeloupe saving by less than 0.1 pp: downwind the apparent wind is weak, and the attached branch already covers the broad reach. Add it for correct polars and figures, not for the economics.

### Thrust against published full-scale figures

Mean thrust of one WindWing-size wing was computed: 750 m², 37.5 m tall, foot 12 m above water, at 12 kn. The 10 m wind is Weibull with k 2 and an 8 m/s mean, all wind angles equally likely, trimmed for best thrust. The model gives **38.8 kN mean** per wing (52 N/m²).

BAR claims "Each WindWing saves an average of 1.5t of fuel … per day on typical global routes" over 280 days at sea (product page). Cargill measured "an annual average saving of three tonnes of fuel per day" for the two wings of _Pyxis Ocean_, "within 10 percent of predictions" (Marine Log, 19 Mar 2024, secondary; DNV verified only the favourable-weather 32 % engine-energy cut, Riviera 17 May 2024). That is 1.5 t/day ≈ 357 kW of brake power at 175 g/kWh, ≈ 250 kW of thrust power at η_D 0.7, ≈ **40 kN** at 12 kn (derived). The model matches it to within the uncertainty of the wind climate assumed here.

AYRO reports 1.3 t/day per 363 m² Oceanwing on the faster _Canopée_ ("typically 1.3 tonnes per day per wingsail", oceanwings.com, claim). That is 3.6 t/day per 1,000 m² against BAR's 2.0. A smaller, faster ship with more apparent wind is consistent with this. _Shofu Maru_ (one Wind Challenger) measured 5–8 % per voyage average (MOL via AJOT, 15 May 2024, Lloyd's Register-verified method).

At 10 m/s and 12 kn the single wing gives 70 kN at a true wind angle of 60°, 89 kN at 90°, 68 kN at 120°, 31 kN at 150° and 5 kN at 180°. No manufacturer publishes thrust in kN.

## 2. Rotor against wing

| Measure                                          | Model                                          | Literature                                                                                                       |
| ------------------------------------------------ | ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Peak CL ratio, rotor (h·d) over wing (planform)  | 9.5/1.8 = 5.3 at SR 3; 11.45/1.8 = 6.4 at SR 4 | 7.76 against a plain wing, 5.3 against a slotted-flap wing (Reche-Vilanova 2021, Table 5)                        |
| Mean net thrust per m², 35×5 rotor over WindWing | 235/52 = 4.5 (derived above)                   | Lu & Ringsberg 2020: an 18×3 m rotor (108 m²) saved 8.9 % and a 1,000 m² wing 8.8 % on an Aframax, ratio about 9 |
| Mean thrust per unit                             | rotor 41 kN, WindWing 39 kN                    | BAR 1.5 t/day per WindWing; no per-rotor average found                                                           |
| Rotor lift at SR 3                               | 9.5 (ShipCLEAN fit to full-scale data)         | 6.5 in the wind tunnel (Bordogna 2020, AR 5), 8.5 in CFD (Li 2012); all quoted by Tillig & Ringsberg 2020, p. 8  |

The model's per-m² ratio sits at the wing-friendly end of the published comparisons. Area is not a fair basis anyway, since rotor area is height × diameter and wing area is planform. The fair bases are per unit, per deck metre, per USD and per tonne:

- **Per USD.** The model price, with market factor 2, 15 % installation and the 12 % retractable premium, is 1.45 MUSD for a 750 m² wing and 1.11 MUSD for a 35 × 5 m rotor (derived). At equal mean thrust, the rotor gives 30 % more thrust per USD.
- **Per tonne.** The model has 90 t per WindWing and 110 t per rotor. Real figures are about 200 t per WindWing ("Each wing weighs roughly 200 tonnes", Riviera/DNV 2024) and 80 t per rotor (Norsepower 2025: 56 t plus a 24 t foundation). Real rotors give about 2.5 times the thrust per tonne. The model's wing mass is the one input clearly biased in favour of wings (§5).
- **Per deck length.** One 35 × 5 m rotor needs 3D = 15 m; one WindWing needs 1.5c = 30 m. On 105 m of usable deck the model fits four 34.6 m rotors but only three wings (2,440 m² at most).

The rotor side is generous. Tillig & Ringsberg (2020, p. 8) report that their full-scale fit sits above model-scale and CFD data. They also note that it agrees worse at high spin ratios, and that SR 1.5–2.5 is the typical optimum. The model trims rotors up to SR 4. Scaling rotor lift to the CFD level (×0.89) cuts the rotor saving from 8.4 to 7.0 %. Scaling to wind-tunnel level (×0.68) cuts it to 4.1 %. Capping SR at 3 lowers mean rotor thrust by 7 %. Reynolds effects favour the full-scale fit (Tillig), so the base is defensible. The rotor's range, however, should reach down to the CFD level (proposal in §7).

## 3. Interference

With 2–3 wings on a 140 m ship, the units are spread over the deck at 2.2c, and the array factor gives κ(3, 2.2c) = 0.865. Data at about 1.9c with every sail at the same angle of attack: Malmek 2024 3D RANS, κ 0.71–0.83 with a mean of 0.79 (derived in `interference_notes.md`); Xu 2025 IDDES, κ 0.88–0.89 at α 10° and 1.00–1.02 at α 17°. Mboumba 2022 has three sails at 2.4c with κ 0.98, which is weak evidence. Independent sheeting recovers loss: van Reen's optimisation lifts κ at 60° from 0.79 to 0.96 (r = 0.81), with no gain at 90° and 120°; Li 2015 gained 42 % thrust with independent sheeting (quoted by Malmek 2024, p. 2).

The fit to equal-trim CFD is therefore a lower bound for an operated rig. Taking a third of the loss back (A 0.44 → 0.30) gives κ(3, 2.2c) = 0.91 and raises the saving by 0.5 pp. It is not punitive at the spacings used; the 11–15 units of a large ship stand at the same per-unit spacing, and (1 − 1/n) saturates. Proposed value: 0.30, range 0.15–0.72.

## 4. Price

No manufacturer, press release or grant discloses the price of a wing sail. The figures that exist:

- **EMSA 2023, Table 7.** Hard sail asset cost EUR 438–876 k (2021, single unit), installation +66–130 k on a newbuild and +109–219 k as a retrofit. Rotor asset EUR 560–1,050 k. Hard sails in Table 4 span 280–1,000 m².
- **Press.** WindWings USD 2.55 M per 750 m² wing (Positive News 2023, unattributed; 3,400 USD/m²). A Shipfinex blog gives USD 2–5 M per rigid wing plus 1–2 M installation (weak). Wind Challenger about USD 2.5 M per sail (NBC News snippet, undated, unverified). IMO GreenVoyage2050 gives USD 0.5–0.7 M per sail installed, with "great uncertainty".

Model price at factor 1 is 66 k + 665 USD/m², so the market price is 132 k + 1,330 USD/m². Against EMSA in USD at 1.16:

| Case            | Model market price [kUSD] | EMSA asset [kUSD] | Model / EMSA |
| --------------- | ------------------------- | ----------------- | ------------ |
| Wing, 280 m²    | 504                       | 508 (min)         | 0.99         |
| Wing, 1,000 m²  | 1,462                     | 1,016 (max)       | 1.44         |
| Rotor, 24 × 4 m | 540                       | 650 (min)         | 0.83         |
| Rotor, 35 × 5 m | 862                       | 1,218 (max)       | 0.71         |

On EMSA's basis the model prices large wings 0–44 % above EMSA and rotors 17–29 % below it. Relative to rotors, that is a bias of about 20–40 % against large wings. The press figures for WindWings are 2–3 times higher still, however, so the market evidence points the other way. Price is a second-order lever: in the old paper outputs, a quarter of the price raised the saving only from 11.2 to 13.9 %. In today's runs, 0.8 times the price raised it from 3.0 to 4.3 %. Keep the value; the reason should cite EMSA and the press range.

## 5. Mass

Current input: 0.12 t/m², range 0.08–0.27. Data:

| Wing          | Mass                                                | t/m² of sail |
| ------------- | --------------------------------------------------- | ------------ |
| EMSA Table 4  | 45–100 t for 280–1,000 m²                           | 0.10–0.16    |
| AYRO OW RE    | 45 t unit for 363 m²                                | 0.12         |
| WindWing      | "roughly 200 tonnes" for 750 m² (Riviera/DNV 2024)  | 0.27         |
| Oceanbird 560 | "approximately 200 tons" with foundation for 560 m² | 0.36         |

The two wings near the model's size (500–750 m², 31–38 m) weigh 0.27–0.36 t/m². At 0.25 t/m², the best wing's saving falls from 3.0 to 1.1 %, because the extra 320 t comes out of cargo on a 16,500 t ship. **This is the largest single correction, and it goes against wings.** Proposed value: 0.25, range 0.12–0.36. The rotor's 0.63 t/m² (110 t for 35 × 5 m against Norsepower's 80 t) is mildly pessimistic for rotors.

## 6. Life and maintenance

- **Design life.** "designed with a 25-year lifetime in mind" (Oceanbird Wing 560 page). "endure 25 years without significant component maintenance" (CM Energy, BAR's builder, 2026, vendor). "25-year design lifespan" (Anemoi, sponsored article). EMSA takes "more than 20 years". The 20 years used for both rigs is pessimistic for both alike; 25 years matches `hull_lifetime`. Proposed for both: 25, range 20–30.
- **Maintenance.** EMSA 2023 (p. 45) puts maintenance and repair at "5% of the 2021 CAPEX for kites and 2% of the 2021 CAPEX for all other technologies": EUR 8–18 k a year for hard sails, 12–22 k for rotors. On top come rotor drive energy of EUR 26–79 k a year and, for hard sails, power consumption "probably negligible". BAR claims "Minimal O&M with simple greasing and hydraulic maintenance. Five-year service intervals". Oceanbird quotes 6–10 kW per wing in operation. The model charges `maintenance_fraction` (3 %) on the whole capital, wings and rotors alike, and models rotor spin power explicitly. That is correct and even-handed. Wings have no measurable maintenance advantage beyond the spin power the model already counts.

## 7. Sizing and height

- **Height 40 m.** Wing 560: 40 m; WindWing: 37.5 m. Correct. Under the 45 m air-draft cap the 140 m ship's wings reach 38.4 m and its rotors only 35 m, so the cap does not hurt wings more. But the model gives the wing no pedestal (see §1).
- **AR 2.** WindWings 1.9, Oceanbird 2.9, AYRO about 3.3. AR 3 changes the saving by less than 0.1 pp, since more and narrower wings fit but interfere. Correct.
- **Spacing and deck length.** 1.5c is the clearance of quarter-chord pivots and Wang's aerodynamic minimum. Installed ships stand wider: three WindWings planned per Kamsarmax (229 m) and four on the 300 m _Berge Olympus_, at about 2.5–3c. The 75 % deck length applies to rotors too. The rule is not unfair.
- **Single centreline row.** All installed multi-wing ships use one, except the _Orcelle Wind_ concept ("six wing sails that runs in parallel across the deck"). Correct for the ships modelled.
- **Grid.** `situation_sizes` tries 800, 1,500 and 3,000 m² on the 140 m ship. The 3,000 m² case does not fit, so the largest size actually tried is 1,500 m², while 2,440 m² fits and is better by 0.5 pp. Add `largest_area` or 2,400 m² to the 140 m wing sizes.

## Re-run: 140 m e-methanol ship to Guadeloupe

Today's code, draft fidelity. "Wings max" is the largest wing area that fits, 2,441 m² (2,451 m² at AR 3).

| Case                                                                   | Wings 1,500 m² | Wings max | Rotors 800 m² |
| ---------------------------------------------------------------------- | -------------- | --------- | ------------- |
| Base                                                                   | 2.5 %          | 3.0 %     | 8.4 %         |
| CL max 2.2                                                             | 3.8 %          | 4.6 %     |               |
| Endplate 1.1 (pedestal gap)                                            | 2.3 %          | 2.8 %     |               |
| Endplate 2.0 (sealed)                                                  | 2.9 %          | 3.4 %     |               |
| Interference amplitude 0.30                                            | 2.9 %          | 3.5 %     |               |
| Post-stall branch, CD90 1.2                                            | 2.6 %          | 3.0 %     |               |
| Mass 0.25 t/m²                                                         | 1.4 %          | 1.1 %     |               |
| AR 3                                                                   | 2.7 %          | 3.0 %     |               |
| Best estimate: CL 2.0, endplate 1.2, A 0.30, mass 0.25, post-stall     | 2.3 %          | 3.0 %     |               |
| Best estimate, price × 0.8                                             | 3.1 %          | 4.3 %     |               |
| Optimistic wing: CL 2.2, endplate 1.4, A 0.22, price × 0.75, mass 0.12 | 5.3 %          | 7.3 %     |               |
| Rotor lift × 0.89 (CFD level)                                          |                |           | 7.0 %         |
| Rotor lift × 0.68 (wind-tunnel level)                                  |                |           | 4.1 %         |

The best estimate leaves the wings where they were, because the aerodynamic gains (+1.6 pp) and the mass correction (−1.9 pp) cancel. Wings beat rotors only when every wing input is at its optimistic end and the rotor's lift is at its pessimistic end.

## Proposed changes

`assumptions.yaml`:

```yaml
wing_max_lift_coefficient:
  value: 2.0
  low: 1.6
  high: 2.5
  unit: "-"
  reason: "3D lift ceiling of a multi-element wing sail: AR 2 wings reach 1.70-1.73 with a 30 % flap (Reche-Vilanova et al. 2021, Table 5), a single NACA0015 sail 1.08 (Xu et al. 2025, Table 4); BAR claims 2.5 times the lift of a single element for its three-element WindWing. Two-element sections reach 1.95-2.65 in 2D (Yao 2026)."
wing_endplate_factor:
  value: 1.4
  low: 1.1
  high: 2.0
  unit: "-"
  reason: "Effective over geometric aspect ratio from the deck mirror: 2.0 sealed, 1.36 at a root gap of 1 % of span, 1.21 at 5 %, 1.09 at 20 % (minimum induced drag, Trefftz plane). WindWings stand about 7.5 m and the Oceanbird wing about 6 m above deck on pedestals (BAR; Oceanbird), the low bound."
wing_interference_amplitude:
  value: 0.30
  low: 0.15
  high: 0.72
  unit: "-"
  reason: "Loss amplitude of the wing array factor: 0.44 fits sails held at one angle of attack in 3D RANS (Malmek et al. 2024) and IDDES (Xu et al. 2025); independent sheeting recovers 0-80 % of the loss depending on wind angle (van Reen 2026), a third taken here."
wing_mass_per_area:
  value: 0.25
  low: 0.12
  high: 0.36
  unit: t/m^2
  reason: "Wing with pedestal and foundation: WindWing about 200 t for 750 m^2 (DNV via Riviera 2024), Oceanbird Wing 560 about 200 t with foundation (Oceanbird); smaller hard sails 0.10-0.16 (EMSA 2023, Table 4; AYRO OW RE 45 t for 363 m^2)."
wing_lifetime:
  value: 25.0
  low: 20.0
  high: 30.0
  unit: years
  reason: "Oceanbird designs the Wing 560 for 25 years and BAR's builder claims 25 years; EMSA (2023) takes more than 20 years for wind-propulsion assets."
rotor_lifetime:
  value: 25.0
  low: 20.0
  high: 30.0
  unit: years
  reason: "Anemoi states a 25-year design life; EMSA (2023) takes more than 20 years for wind-propulsion assets."
```

The `wing_cost_per_area` reason should add that the model is 0–44 % above EMSA's 2021 hard-sail asset range while the press puts a WindWing at 3,400 USD/m².

Code changes, as diff descriptions:

1. `src/rig.jl`: give `WingRig` a stalled branch. Add a field `stalled_drag_coefficient` (new key `wing_stalled_drag_coefficient`: 1.2, range 1.0–1.4, the normal-force coefficient of a low-AR plate). Extend `trim_settings(::WingRig)` with angles of attack from 25° to 90°. For those trims `rig_force` takes CL = CD90 sin α cos α and CD = CD0 + CD90 sin² α. This corrects the downwind polar, a factor of 2.3 at 180°, at almost no cost effect.
2. `src/rig.jl`, `WingRig(total_area, hull, assumptions)`: if the endplate factor is lowered to the pedestal case, subtract the pedestal height from `max_height` as well (new key `wing_pedestal_height`, about 7 m from BAR's 45 m top for a 37.5 m wing). Otherwise do neither.
3. Rotors, for fairness of the comparison: give the rotor lift a range in the sensitivity study. The low end is 0.89 times the ShipCLEAN fit (CFD, Li 2012) and is better than a hard cap. This is a new key that multiplies `rotor_coefficients` lift; it needs care against `CLEAN_CODE.md` §6 and is justified only because the screening needs the range.
4. `scripts/paper_data.jl`, `situation_sizes["140 m"]["wings"]`: replace 3,000 m², which does not fit, with the largest area that does fit (about 2,400 m²).
