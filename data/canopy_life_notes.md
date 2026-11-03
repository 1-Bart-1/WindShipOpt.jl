# Canopy life: the derivation and its data

How the canopy life in `src/canopy.jl` follows from sources. The paper's subsection "Canopy life" is the short form. **[est]** marks our estimate; **[claim]** a maker's or seller's statement with no test shown; **[meas]** a measurement with its method stated. `paper/sources.csv` says which sources were read in full.

## Result

Life at 200 g/m² is 3,800 flight hours. The inputs' bounds give 2,200-6,900 h on the wear rate alone and 1,200-6,900 h with every sensitivity below. We cannot narrow this: no polyester ram-air canopy has a published life, and the wear rate is not derived from physics.

## The law

Strength decays at two rates that add, until the cloth has only the strength the force limit needs:

    1/t = 1/t_UV + 1/t_wear
    t_UV   = D_ref (w/100)^a ln(M) / Ddot
    t_wear = 100 (w/100)^b ln(M) / r
    M      = S w / (k T),  T = p_max R

| Symbol | Base | Bounds | Set by |
| --- | --- | --- | --- |
| D_ref, UV dose to 1/e at 100 g/m² | 70 MJ/m² | 35-160 | Pooled fit below |
| a, UV weight exponent | 0.4 | 0.1-1 | Pooled fit; Ceylan's series |
| Ddot, UV dose per flight hour | 0.02 MJ/m² | 0.012-0.035 | Q-Lab annual dose, geometry [est] |
| r, wear rate at 100 g/m² | 0.13 g/m²/h | 0.052-0.26 | Service statements below; not physics |
| b, wear weight exponent | 1 | 1-1.5 | Assumption; Kubicek implies 1.5 |
| S, specific strength | 170 N/m per g/m² | 110-210 | Cloth data sheets |
| k, kept strength over tension | 5 | 3-8 | Estimate |
| T, skin tension | 250 N/m at 0.5 kN/m², R = 0.5 m | | Wang and He 2018 for the form |

r is a strength-equivalent rate, not a mass balance: strength and mass loss curves do not follow each other.

Life by cloth weight [h], all from the law:

| Case | 40 | 60 | 100 | 140 | 200 | 250 | 300 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Base | 463 | 834 | 1,646 | 2,501 | 3,812 | 4,911 | 6,006 |
| r = 0.052 | 989 | 1,725 | 3,239 | 4,744 | 6,932 | 8,685 | 10,376 |
| r = 0.26 | 245 | 448 | 904 | 1,399 | 2,178 | 2,848 | 3,529 |
| a = 1 | 427 | 794 | 1,646 | 2,601 | 4,166 | 5,560 | 7,016 |
| a = 0.1 | 475 | 851 | 1,646 | 2,446 | 3,604 | 4,517 | 5,380 |
| b = 1.5 | 305 | 667 | 1,646 | 2,848 | 4,885 | 6,692 | 8,539 |
| D_ref = 35 | 416 | 732 | 1,395 | 2,063 | 3,050 | 3,849 | 4,627 |
| D_ref = 160 | 494 | 905 | 1,832 | 2,839 | 4,435 | 5,813 | 7,217 |
| Retired at 27 % of new, r rescaled | 641 | 911 | 1,396 | 1,830 | 2,413 | 2,853 | 3,261 |
| Retired at 70 % of new, r rescaled | 417 | 552 | 770 | 947 | 1,168 | 1,325 | 1,466 |
| Fixed wear life 2,000 h | 1,345 | 1,499 | 1,641 | 1,710 | 1,768 | 1,798 | 1,819 |
| Fixed wear life 5,000 h | 2,255 | 2,725 | 3,231 | 3,512 | 3,766 | 3,904 | 4,006 |

At 200 g/m² the wear term carries 75 % of the rate and UV 25 %.

## UV

exp(-D/D0) fits strength to within a factor 2 in D0 down to 5 % residual strength. D0 grows about 2 times from 75 % to 5 % residual (Asadi 2021), so short tests read low.

D0 [MJ/m², 295-385 nm] of polyester without UV blockers, field values as measured, lamp values times 3 for the lab-to-field gap of the one data set with both on one roll (Stevens 2018: 46-94 in lamps, 217-233 outdoors):

| Source | w [g/m²] | D0 | Basis |
| --- | --- | --- | --- |
| Hunt 2022, 20D | 40 [est] | 39 | Roof, dose [est] |
| Hunt 2022 | 115 [est] | 142 | Roof, dose [est] |
| Hunt 2022 | 150 [est] | 85 | Roof, dose [est] |
| Dekanic 2023 | 156 | 87 | Xenon x 3, dose [est] |
| Uzumcu 2024, raw | 161 | 42 | UV-A x 3 |
| Lodi 2008 | 171, 280, 450 | 80, 74, 145 | Outdoors, measured dose; nonwoven |
| Ceylan 2023 | 177, 415 | 75, 75 | Lamp x 3, band [est] |
| Asadi 2021 | 337 | 105 | QUV x 3 |
| Stevens 2018 | 1,500 [est] | 225 | Outdoors, measured dose |

Least squares on logs: **a = 0.40 +/- 0.12, D0(100) = 63** (r = 0.72, n = 12). Field values only: a = 0.42 +/- 0.13, D0(100) = 72 (n = 7). Below 500 g/m²: a = 0.32 +/- 0.17. Within Ceylan's nine weights of 177-415 g/m², at one lab and dose: a = 0.1 +/- 0.4. So a = 1 is rejected and a = 0 cannot be rejected within canopy weights. The damage lies in the skin of each 15-25 um filament, and heavier cloth has more or thicker yarns, not thicker filaments.

Finish moves D0 more than weight: 3.8 times for TiO2 in a coating on one polyester (Hunt 2022), 1.7-6 times for PU on raw polyester (Uzumcu 2024). The base has no UV blocker. Maslanka 2023 is nylon and is not in the fit. Poly-Fiber's 85 % loss a year is an untested seller's claim and is not in the fit.

No source measures the dose on a kite skin. At 0.02 MJ/m²/h, 60 % of the Florida mean, the top skin is the critical one [est]. A kite left on deck at 0.04 MJ/m²/h would double this, so the stowage must be opaque.

## Wear rate

Each statement gives r after removing UV: `r = w ln(M) / L - w Ddot / D0(w)`. Inputs other than the life are our estimates.

| Source | Cloth | w | Life [h] | Ends on | T/w | S | Ddot | r at a = 0.4 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Flynn 2015 [claim] | Woven polyester sail | 250 [est] | 3,500-4,000 | Structure | 2.0 [est] | 110-207 | 0.04-0.07 [est] | 0-0.12 |
| Flynn 2015 [claim] | Same | 400 [est] | 3,500-4,000 | Structure | 2.0 [est] | 110-207 | 0.04-0.07 [est] | 0.01-0.22 |
| Kubicek 2026 [claim] | Polyester balloon | 45 | 400-500 | Not stated | 2.8 [est] | 222 | 0.01-0.03 [est] | 0.22-0.30 |
| Kubicek 2026 [claim] | Polyester balloon | 70 | 800-1,000 | Not stated | 2.9 [est] | 222 | 0.01-0.03 [est] | 0.16-0.23 |
| Kubicek 2026 [claim] | Polyester balloon | 77 | over 1,000 | Not stated | 2.6 [est] | 222 | 0.01-0.03 [est] | 0.18-0.21 |
| SUP'AIR 2016 [meas, by maker] | Tandem paraglider, fibre not stated | 38-45 [est] | 800-850 | Porosity 25 s | 1.6 [est] | 200 [est] | 0.05-0.09 [est] | 0.07-0.14 |
| Lynn 2007 [claim] | Maxi show kite | 50 [est] | 1,800-2,400 [est, from over 300 flying days] | Coating, porosity | 0.6 [est] | 200 [est] | 0.05-0.09 [est] | 0-0.07 |

Over ten rows (each Flynn row taken at both S): **median of midpoints 0.11, span 0.04-0.26.** Under a = 1 the median is 0.18, under a = 0.1 it is 0.11. So 0.13 (0.052-0.26) stands, as an estimate that fatigue data do not contradict.

Removing UV stops any double count, but only as far as the dose per sailing hour is right. Quantum's figure is about what UV alone predicts (M = 11-21, UV life 1,900-18,000 h [est]), so it is close to a lower bound on wear life.

**Physics does not set r.** A size check [est], with fractional loss per hour r/w:

| Regime | Data | Implied r | What r = 0.13 would mean |
| --- | --- | --- | --- |
| Tension cycling, polyester rope yarn at 3 % mean, 4 % range, 10^6 cycles (TTI 2006) | -0.4 to -9.2 % | 0.0014-0.035 at 1 Hz | 4-90 times too low to matter |
| Flutter, polyester sailcloth 166-184 g/m² [est], 30 mph, 30 min (Doyle 2011) | -3.6 to -12.6 % stiffness | 12-45 if continuous | 0.3-1.1 % flutter duty, 10-38 s an hour |
| Crumple, PA66 34-42 g/m², ISO 7854 C, 9,000 cycles (Maslanka 2023) | -0.3 to -13.5 % | 1.1e-5 to 6.8e-4 per cycle | 190-11,000 crumples an hour |

Neither duty has been measured on a kite. Patent flutter data are stiffness, not strength, and loss may not stay linear.

## Load variable and the T/w test

T = p R per unit width is the load. At the working limit a sail and the kite sit at the same T/w, 2.0-3.2 against 2.5 N/m per g/m² [est], both 0.4-3 % of break. Earlier notes calling sails "much lower loading" were wrong per width.

**Normalising life by T/w cannot be tested and what evidence exists is against it.** No data set varies weight and tension with wear measured, because cloth is chosen for its load. Indirectly:

- Wings at T/w 1-3 live from under 130 h (skydive mains) to decades (shielded aircraft covers). Folding, opening shock, flutter and UV differ, and T/w does not sort them.
- Kubicek rates its 70 g/m² cloth at one life over envelopes that double T/w, and doubles life from 45 to 77 g/m² at about level T/w [claim]. That gives b about 1.5 at constant T/w.
- Maslanka's 34, 38 and 42 g/m² cloths show no order with weight in flex or UV.
- A coating change moved show kite life by about 2 times at one tension (Lynn 2007).

T/w therefore enters only through ln(M), as the strength left to lose. A power law in T/w is excluded: the one exponent, m = 17 (Lechat 2006, 7-25 across sources), comes from 60-90 % of break and extrapolates by 13 to 29 orders of magnitude to 3 % of break, with the form undetermined.

## Load cycles

All [est]:

- Tension: at most about 1.4e7 cycles over 3,800 h at 1 Hz. An eight of 30-60 s gives about 5e5. Rope yarn shows no loss below ranges of about 4-10 % (TTI 2006).
- Launches: at the 1.5 h a flight of the SkySails fleet (SkySails 2018), about 2,500 launch and landing cycles. The model's kite stays up longer than that.
- Flexes from luffing: 300-18,000 per cycle at 2-10 min and 2.6-30 Hz, so 8e5 to 5e7 over the life. Luffing time per launch is unmeasured.

Hours are a poor clock: paraglider intervals count flights too, and skydive mains end at 25-130 flying hours because openings and packs do the damage. The law has no launch-count term because no data set could set it. #19 carries the per-launch chance of a discrete tear or loss; gradual handling wear is inside r because the anchors include it.

## Flogging

"30 minutes of flogging can equal 50 hours" traces to North Sails by 2007 (All At Sea, 1 Feb 2007). No source gives a test, cloth or metric, so we do not use it. Doyle 2011's whirl test is the only measured loss with a stated duration, and it does not support or refute the sentence.

## What ends a canopy

Two clocks run:

- **Coating: flex, fold, flutter, abrasion, then porosity.** Maslanka 2023: flex raised permeability with little strength loss. SUP'AIR: 410 s new to 29 s at 800 h, limit 25 s (only 29 s is printed; the rest by eye).
- **Yarn: UV, then strength and tear.** Maslanka 2023 and thesis: UV lost 2-75 % of strength by cloth, with 0.000 leak at 200 Pa but 0.040-0.083 L/m²/s at 1,500 Pa. A kite's 0.5-1.1 kPa lies in the untested gap. UV and flex were never applied together.

The law has one clock in strength, and anchors that end on porosity enter it as a strength equivalent. Porosity limits for paragliders: 18 s (Dudek), 25 s (SUP'AIR), with no kite limit published. Maslanka's thesis simulates a rigid paraglider at 45 km/h at leak rates of 0.05 to 1.06 L/m²/s at 200 Pa: lift down 8-29 %, glide ratio down 12-37 %. The wing is unvalidated, at one angle of attack, with no lines, ribs or seams. Tables 6 and 9 disagree on two leak values (1.120 and 2.050 against 0.095 and 1.061), and section 6 gets a worse glide (4.07) at a lower leak than section 10 (8.35), so only the trend holds and 37 % is no upper bound. The thesis gives no porosity limit. Seams, left out, leak 0.66-2.81 L/m²/s at 200 Pa. Ship kites run 2.5-6 times a paraglider's pressure [est], so a kite limit should be at least as strict. SkySails names porosity and residual strength as its test criteria and prints no results.

**Retirement.** Base flies to M, which at 200 g/m² is 4 % of new strength. Regulated fabric retires far earlier: 70 % of required new strength (FAA AC 43.13-1B para 2-33, table for cotton and linen, applied by wing loading), 30 lb grab on balloon cloth of 65 and 112 lb/in new (Lindstrand), so 46 % and 27 % [est]; a grab value reads higher than a strip value, so these are low. Retiring at 46-70 % leaves almost no room for wear: refitting each anchor one by one gives r near 0, since the maker lives then exceed what UV alone allows. So either real cloth flies below those limits, or D0 is low by the lab-field factor. Rescaling r through the same margin keeps the observed wear life at 100 g/m² and avoids counting wear twice.

## Seams

Thread is not shown to be worse than cloth. The one curve, a vendor's on untreated tex 148 polyester (Shippee 2016), gives lab D0 30-51 [est, unit assumed] against 12-35 for lab cloth. Thread stands proud and abrades, which UV does not capture; sailors report stitching going first (Gifford 2014) [anec]. Seam capacity at 3 stitches/cm and tex 40 is about 17 kN/m [est], like the cloth at 100 g/m², with seam efficiency 85 % on nylon ripstop (Neha 2024). Seams are not modelled separately; replacing thread may be cheaper than a canopy, which the model does not count.

## Corrections to the first-pass notes

- "Rolly Tasker via Seabreeze" is Andrew Dove of North Sails. His 2,000 h is a performance life, so removing UV from it to get a wear life is invalid, and it is gone.
- The kitesurf 200-500 h was a search snippet from a dead page, and is gone.
- 46 lb/in is TSO-C14b; a polyester STC at 9 psf or more uses 56 lb/in.
- The fatigue exponent's extrapolation to 3 % of break is 1.6e13 cycles under Lechat's log law and 7.7e28 under a power law.
- Sailcloth reaches 207-211 N/m per g/m² (Ambroziak and Klosowski 2018), so 110 is not all sailcloth.

## What would settle it

Cheapest first:

1. Porosity and strip tests on retired ship kite or paraglider panels.
2. Flutter and crumple on polyester ripstop at three or more weights, with strength and porosity at several cycle counts.
3. Pulsed burst tubes at two pressures and two weights; SkySails Power ran such tests and printed no results.
4. Flutter duty and UV dose measured on a flying kite.
