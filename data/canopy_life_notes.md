# Canopy life: the derivation and its data

How the canopy life in `src/canopy.jl` follows from sources. The paper's subsection "Canopy life" is the short form. **[est]** marks our estimate; **[claim]** a maker's or seller's statement with no test shown; **[meas]** a measurement with its method stated. `paper/sources.csv` says which sources were read in full.

## Result

Life at 200 g/m² is 3,800 flight hours. The bounds give 2,200-6,900 h on the wear rate alone and 1,200-6,900 h over every sensitivity below, each changed alone. That is not a joint range: every input at its short-life bound together gives 1,100 h, or 300 h retired at 70 % of new, and at its long-life bound 18,000 h [est]. No data say how the inputs vary together, so we do not read these corners as likely. We cannot narrow this: no polyester ram-air canopy has a published life, and the wear rate is not derived from physics.

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
| S, specific strength | 170 N/m per g/m² | 110-210 | Estimate within Porcher 2006 sheets (nylon 150-210, hard polyester 110) and Ambroziak and Klosowski 2018 |
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
| Ddot = 0.012 | 484 | 883 | 1,774 | 2,732 | 4,235 | 5,520 | 6,820 |
| Ddot = 0.035 | 426 | 755 | 1,450 | 2,158 | 3,210 | 4,069 | 4,909 |
| S = 110 | 344 | 661 | 1,371 | 2,131 | 3,310 | 4,305 | 5,301 |
| S = 210 | 520 | 918 | 1,779 | 2,680 | 4,056 | 5,205 | 6,349 |
| k = 3 | 602 | 1,037 | 1,968 | 2,934 | 4,402 | 5,622 | 6,834 |
| k = 8 | 334 | 647 | 1,350 | 2,102 | 3,270 | 4,257 | 5,245 |
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

Over ten rows (each Flynn row taken at both S, SUP'AIR at 38 and 45 g/m²): **median of midpoints 0.10, span 0.04-0.26.** Under a = 1 the median is 0.15, under a = 0.1 it is 0.09.

Flynn also gives a shape life of 1,700-2,700 h, and North's 2,000 h performance life agrees with it. Taking that in place of Flynn's structural life gives a median of 0.19 and a span of 0.04-0.40. A wing works through its shape, so this reading is as defensible for a kite as the structural one, and it gives 2,800 h at 200 g/m² against 4,600 h at r = 0.10.

**We choose r = 0.13 (0.052-0.26), between those two medians.** The data do not set it: the anchors would allow anything from 0.10 to 0.19 as a central value, and 0.13 is our pick. It is an estimate that fatigue data do not contradict. The high bound gives 2,200 h, near what the shape reading gives at its upper end, and the fixed wear life of 2,000 h in the table above is the same case stated as a span.

Removing UV stops any double count, but only as far as the dose per sailing hour is right. Quantum's figure is about what UV alone predicts (M = 11-21, UV life 1,900-18,000 h [est]), so it is close to a lower bound on wear life.

**Physics does not set r.** A size check [est], with fractional loss per hour r/w:

| Regime | Data | Implied r | What r = 0.13 would mean |
| --- | --- | --- | --- |
| Tension cycling, polyester rope yarn at 3 % mean, 4 % range, 10^6 cycles (TTI 2006) | -0.4 to -9.2 % | 0.0014-0.035 at 1 Hz | 4-90 times too low to matter |
| Tension cycling, woven polyester 60-85 g/m² [est], to 46-77 % of break strain, 12,000 cycles (Nosraty 2013) | Strength unchanged, at most -4.4 % | At most 0.013-0.038 at 60-120 cycles an hour | At least 400-600 such cycles an hour |
| Flutter, polyester sailcloth 166-184 g/m² [est], 30 mph, 30 min (Doyle 2011) | -3.6 to -12.6 % stiffness | 12-45 if continuous | 0.3-1.1 % flutter duty, 10-38 s an hour |
| Crumple, PA66 34-42 g/m², ISO 7854 C, 9,000 cycles (Maslanka 2023) | -0.3 to -13.5 % | 1.1e-5 to 6.8e-4 per cycle | 190-11,000 crumples an hour |

Neither duty has been measured on a kite. Patent flutter data are stiffness, not strength, and loss may not stay linear.

**Cycling woven polyester.** Nosraty 2013 is the one fabric test we hold that reads strength after cycling: six weaves of textured polyester, 150 denier warp and 80 denier weft, at 18, 22 and 26 picks/cm, 15-20 kN/m warp and 3-7 kN/m weft, about 60-85 g/m² [est, the paper gives no weight or warp density]. Strips of 5 by 20 cm were cycled to a fixed strain of 12 or 18 % at 100 cycles a minute, up to 12,000 cycles, about 2 h. Each fabric's row at 12,000 cycles against its uncycled row in Table III, the two strokes averaged, with a 95 % interval over the 18 fabrics [our arithmetic, on our transcription of the scan]:

| Property | Warp, after / before | Weft, after / before |
| --- | --- | --- |
| Maximum load | 1.007 (0.995-1.018) | 0.979 (0.956-1.001) |
| Breaking strain | 0.657 (0.631-0.682) | 0.617 (0.589-0.644) |
| Second modulus | 1.42 (1.36-1.47) | 1.59 (1.53-1.66) |

The authors' ANOVA, pooling all fabrics, agrees on load (F = 0.27, p = 0.90 warp; F = 0.18, p = 0.95 weft) and finds strain and modulus significant. So 12,000 cycles at half to three-quarters of breaking strain cost at most 4.4 % of strength. Taking that bound per cycle, and every eight of a kite as hard as this test, tension cycling gives at most 0.013-0.038 g/m²/h at 60-120 cycles an hour, 10-30 % of r = 0.13. Kite cycles are far softer, at 0.4-3 % of break. This replaces an inference from fibres and rope yarn with a measurement on cloth, and agrees with it, so r does not move: tension cycling still does not explain the wear rate. Limits:

- 12,000 cycles are 2.4 % of the 5e5 eights in a 3,800 h life. The authors expect load to fall with enough further cycles, and explain the flat load as more yarn orientation cancelling broken filaments, so a flat curve here is no proof of a flat curve later.
- The test controls strain and reports no load, and fabric stretches for good during the test, so the load per cycle falls and 46-77 % of break strain describes the start only [est].
- Part of the fall in breaking strain is likely crimp and slack pulled out rather than damage [est]. Load times breaking strain, a rough stand-in for the work to break, still falls to 0.66 warp and 0.60 weft [est]. A strength limit alone would miss this, and a tear limit may not; tear was not measured.
- No ripstop, coating, flex, UV or porosity. Text and table disagree on sample counts (2 or 5 per case; 576 samples, but 324 in the ANOVA), and P(26)'s uncycled row differs between strokes on two values (873 and 883 N, 107 and 125 N).

Asayesh and Jeddi 2007 come nearest a canopy's strain: tubular plain weave of textured polyester in the weft, 0.5 and 1 % strain, 2-4 % of break strain, at a preload of 73 N/m, 37 °C, 1 and 3 Hz, for 90 min, or 5,400 and 16,200 cycles. They read dynamic modulus only: a quick change over the first minutes, put down to yarn slip, then a slow drift, with storage modulus up about 6-15 % (by eye, Fig. 1). No strength or failure was read, so they set no rate. Their "increase in lifetime" with frequency is inferred from elongation, with no lifetime measured, and their elongation bars of 34-570 % are undefined and exceed the 26-32 % breaking strain. We use neither.

## Load variable and the T/w test

T = p R per unit width is the load. At the working limit a sail and the kite sit at the same T/w, 2.0-3.2 against 2.5 N/m per g/m² [est], both 0.4-3 % of break. Earlier notes calling sails "much lower loading" were wrong per width.

**Normalising life by T/w cannot be tested and what evidence exists is against it.** No data set varies weight and tension with strength loss measured at a canopy's tension, because cloth is chosen for its load. The nearest is Nosraty 2013, which varies stroke and weft density separately, and it cannot test T/w. It controls strain and reports no load, its weft density moves cloth weight only from about 60 to 80 g/m² [est], and strength did not move at all. What did move, breaking strain, follows the stroke (warp 0.73 at 12 %, 0.585 at 18 %; weft 0.70 and 0.535) and not the weft density (warp 0.65, 0.66, 0.66; weft 0.60, 0.62, 0.63 at 18, 22, 26 picks/cm; intervals overlap). Any strain law predicts that as well as a T/w law, and it holds at 46-77 % of break strain for a property that is not life, so it does not set b. Indirectly:

- Wings at T/w 1-3 live from under 130 h (skydive mains, below) to decades (shielded aircraft covers). Folding, opening shock, flutter and UV differ, and T/w does not sort them.
- Kubicek rates its 70 g/m² cloth at one life over envelopes that double T/w, and doubles life from 45 to 77 g/m² at about level T/w [claim]. That gives b about 1.5 at constant T/w.
- Maslanka's 34, 38 and 42 g/m² cloths show no order with weight in flex or UV.
- A coating change moved show kite life by about 2 times at one tension (Lynn 2007).

T/w therefore enters only through ln(M), as the strength left to lose. A power law in T/w is excluded: the one exponent, m = 17 (Lechat 2006, 7-25 across sources), comes from 60-90 % of break and extrapolates by 13 to 29 orders of magnitude to 3 % of break, with the form undetermined.

## Load cycles

All [est]:

- Tension: at most about 1.4e7 cycles over 3,800 h at 1 Hz. An eight of 30-60 s gives about 5e5. Rope yarn shows no loss below ranges of about 4-10 % (TTI 2006), and woven polyester none measurable in 12,000 far harder cycles (Nosraty 2013).
- Launches: at the 1.5 h a flight of the SkySails fleet (SkySails 2018), about 2,500 launch and landing cycles. The model's kite stays up longer than that.
- Flexes from luffing: 300-18,000 per cycle at 2-10 min and 2.6-30 Hz, so 8e5 to 5e7 over the life. Luffing time per launch is unmeasured.

Hours are a poor clock: paraglider intervals count flights too, and skydive mains end at 25-130 flying hours [est] because openings and packs do the damage: porosity shows after "a few hundred jumps" at about 5 minutes each (Szafran 2019), and one tandem manual replaces the main at 1,400-1,600 jumps (quoted in Szafran 2018). The law has no launch-count term because no data set could set it. #19 carries the per-launch chance of a discrete tear or loss; gradual handling wear is inside r because the anchors include it.

## Flogging

"30 minutes of flogging can equal 50 hours" traces to North Sails by 2007 (All At Sea, 1 Feb 2007). No source gives a test, cloth or metric, so we do not use it. Doyle 2011's whirl test is the only measured loss with a stated duration, and it does not support or refute the sentence.

## What ends a canopy

Two clocks run:

- **Coating: flex, fold, flutter, abrasion, then porosity.** Maslanka 2023: flex raised permeability with little strength loss. SUP'AIR: 410 s new to 29 s at 800 h, limit 25 s (only 29 s is printed; the rest by eye).
- **Yarn: UV, then strength and tear.** Maslanka 2023 and thesis: UV lost 2-75 % of strength by cloth, with 0.000 leak at 200 Pa but 0.040-0.083 L/m²/s at 1,500 Pa. A kite's 0.5-1.1 kPa lies in the untested gap. UV and flex were never applied together.

**Field porosity.** Bartoš 2018 tested 253 Gradient paragliders at one maker's inspections in 2017: EN A to D, no tandem, acro or light wings, aged 2 to over 13 years, by the time for 0.25 L through 38.5 cm² at 10 mbar. Its cloth is Porcher Skytex, stated generically as nylon 66 and not given per wing, so this is not polyester. Mean readings at the top skin's leading edge centre are 326-400 s at 2 years and 54-111 s at 13 or more (EN A to C; EN D has no wing past 9 years), and a fit to its yearly means gives a 1/e time of 5-7 years in every class [our fit, unweighted, on means with no spread]. By Fig. 16, about 4 % of all 1,012 readings lie under about 39 s [by eye; which readings the figure holds is our inference]. It records no flight hours, so it gives no rate per hour and does not enter r. With SUP'AIR's 1/e of about 300 h the two would meet at 40-60 h a year [est], which is not implausible, and that is all the check shows. The sample holds only wings still in use, mixes cloth generations and ages from manufacture. It tests no cloth strength, no flight characteristic despite its title, and states no limit. Its 4 times more porosity per 100 h is a handbook's line (Dvořák 2003) with no test; from 400 s it would pass 25 s in about 200 h, against SUP'AIR's 800 h, so we do not use it. Its ranking of classes compares correlation coefficients rather than slopes, so it does not show which wears faster, and cloth weight is not separable from class.

Nie et al. 2021 model the permeability of new parachute cloth from its weight, fibre density and thickness. They hold no aged cloth, so they set no end of life and we do not use them. They do cite a lead we do not hold, on permeability under cyclic loading (Rondeau, Desabrais and Charette 2015, doi:10.2514/6.2015-2132).

The law has one clock in strength, and anchors that end on porosity enter it as a strength equivalent. Porosity limits for paragliders: 10 s, then a test flight (BGD); 300 L/m²/min at 20 mbar, 18 s by the maker's conversion (Dudek); 25 s (SUP'AIR). No kite limit is published. Maslanka's thesis simulates a rigid paraglider at 45 km/h at leak rates of 0.05 to 1.06 L/m²/s at 200 Pa: lift down 8-29 %, glide ratio down 12-37 %. The wing is unvalidated, at one angle of attack, with no lines, ribs or seams. Tables 6 and 9 disagree on two leak values (1.120 and 2.050 against 0.095 and 1.061), and section 6 gets a worse glide (4.07) at a lower leak than section 10 (8.35), so only the trend holds and 37 % is no upper bound. The thesis gives no porosity limit. Seams, left out, leak 0.66-2.81 L/m²/s at 200 Pa. Ship kites run 2.5-6 times a paraglider's pressure [est], so a kite limit should be at least as strict. SkySails names porosity and residual strength as its test criteria and prints no results.

**Shape.** Flynn states that a sail keeps good shape for half to two-thirds of its structural life, 1,700-2,700 h [claim], and North's 2,000 h performance life agrees. No source gives a shape limit or a shape loss with hours for a kite. The law has no shape clock: it enters through the choice of r above and the fixed 2,000 h case, which gives 1,768 h at 200 g/m².

**Tear.** The one retirement limit we hold for a flying wing is a paraglider maker's: at a 600 g load the tear should not exceed 5 mm or break a ripstop thread (BGD) [claim, light nylon]. Dudek names the same test without a number. Aircraft cloth has a tear minimum only for new cloth, 5 lb (FAA AC 43.13-1B, Table 2-1, cotton and linen). Aerostar's balloon tests, of which we read the fabric test section only, use tongue tear above 2.5 lb and then 1.75 lb on nylon, and call tear the most discerning test of strength left. How a 600 g test scales to 200 g/m² cloth is unknown, and the law's margin is on tension and holds no tear limit.

**Retirement.** Base flies to M, which at 200 g/m² is 4 % of new strength. Regulated fabric retires far earlier: 70 % of the new strength required, not of the cloth's actual new strength (FAA AC 43.13-1B para 2-33, table for cotton and linen, applied by wing loading), and a 30 lb grab test on balloon cloth of 65 and 112 lb/in new on a strip basis (Lindstrand), so at most 46 % and 27 % [est]. A grab test reads higher than a strip test on the same cloth, so 30 lb grab is less than 30 lb in strip terms and the true shares are lower; by how much the document does not say. Retiring at 46-70 % leaves almost no room for wear: refitting each anchor one by one gives r near 0, since the maker lives then exceed what UV alone allows. So either real cloth flies below those limits, or D0 is low by the lab-field factor. Rescaling r through the same margin keeps the observed wear life at 100 g/m² and avoids counting wear twice.

**Background, not cited in the paper.** Knacke's parachute design manual (1991), of which we read only the pages on these factors, sets no life and holds no strength decay per dose or per hour for nylon or polyester. Its Table 6-7 allows design factors for repeated use and handling, on parachutes used up to about 50 times at most: fatigue 0.9-1.0, abrasion 0.9-1.0, joints 0.8, all losses together 0.58-0.8, in an ultimate design factor of 1.9-2.98. These are allowances, not measurements, though the design factor sits near our safety factor of 2-2.5. Its Table 6-10 grades ultraviolet resistance good for Dacron and poor for nylon, and its text gives Dacron better low-porosity stability. That is qualitative, and it is one more reason not to carry nylon results (Maslanka 2023, Bartoš 2018, possibly SUP'AIR) over to polyester unchanged. The Apollo line tests it mentions, at 75 % of ultimate, are given without a number on these pages. Nothing here moves an input.

## Seams

Thread is not shown to be worse than cloth. The one curve, a vendor's on untreated tex 148 polyester (Shippee 2016), gives lab D0 30-51 [est, unit assumed] against 12-35 for lab cloth. Thread stands proud and abrades, which UV does not capture; a sailmaker reports stitching as the weakest part of a sail, with "UV stabilized" thread losing about half its strength in two years in the tropics, "not a lab test figure" (Gifford 2014) [anec]. Seam capacity at 3 stitches/cm and tex 40 is about 17 kN/m [est], like the cloth at 100 g/m², with seam efficiency 85 % on nylon ripstop (Neha 2024). Seams are not modelled separately; replacing thread may be cheaper than a canopy, which the model does not count.

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
