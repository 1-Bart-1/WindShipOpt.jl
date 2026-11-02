# Formula and citation checks

Checked 2026-10-31 against the primary sources where they were accessible. Page numbers are the printed page numbers of the source unless marked "pdf p.". Newly downloaded PDFs are in `paper/literature_pdfs/` (`oehler2019.pdf`, `vandervlugt2019.pdf` = arXiv 1705.04133v2, `kim2021.pdf`) with `.txt` conversions next to them.

## 1. SNNM added resistance (`src/waves.jl`) against Mittendorf et al. (2022)

**Verdict: the equations and both coefficient sets match. Three discrepancies: one is an interpretation of the beam-to-following interpolation that the paper words differently, one is the spectral integration range, and one is a missing reference implementation that leaves the following-wave rule only partly verifiable.**

Source: `mittendorf2022.pdf`, DTU Orbit postprint, publisher's PDF (pdf p. = printed p. + 1).

**Non-dimensionalisation (Eq. 3, p. 6).** The paper gives "C_AW = R_AW L_pp / (ρ g ζ_a² B²)". The docstring of `added_resistance_coefficient` and the scaling in `added_resistance` (`ρ g B² / L`) match.

**Heading convention.** The paper's Fig. 3 legend runs from "180 deg." to "0 deg.". The paper says "C¹_AW,R is valid for E1 ≤ β ≤ π, C²_AW,R in π − E1 ≤ β ≤ π, C³_AW,R is valid for angles in 0 ≤ β ≤ π − E2 and C⁴_AW,R is defined for 0 ≤ β ≤ E2" (p. 6), and Eq. 18 makes the shoulder term act near β = π. So β = π is head seas and β = 0 is following seas, which is what the code assumes (`heading` π = head). `wave_heading` in `src/routing.jl` folds the direction into [0, π] with head seas at π, which is consistent.

**Reflection part (Eqs. 4–10, 18–20, pp. 6–7):**

- Eq. 5: "C¹_AW,R = x2 (L_pp/B) α_T* {sin²(E1 − β) + (2ω0U/g)[cos E1 cos(E1 − β) − cos β]} (0.87/C_B)^((1+4√Fn) f(β))". This matches `segment_reflection(bow_angle, bow_angle - heading, ...)` times `bow`. sin² is even, so E1 − β and β − E1 give the same result.
- Eq. 6 (E1 + β) matches the second bow `if` in `reflection_coefficient`. Eqs. 7 and 8 (stern, −x2, no form factor, E2 + β and E2 − β) match its two stern `if`s. The validity ranges match the four `if` conditions exactly.
- The paper says: "The form factor (0.87/C_B)^((1+4√Fn) f(β)) … is neglected (i.e. equal to 1) in following wave conditions (cf. Eqs. (7) & (8))" (p. 6). The code applies `form` to the bow segments only, which matches.
- Eqs. 9 and 10, "E1 = arctan(0.99·B/2 / L_E)" and "E2 = arctan(0.99·B/2 / L_R)", match `bow_angle` and `stern_angle`.
- Eq. 18: "f(β) = −cos β for β ∈ [π − E1, 0]; 0 for β < π − E1". The interval "[π − E1, 0]" is a typo in the paper for [π − E1, π]. `shoulder` implements the intended form and matches.
- Eq. 19, "α_T* = 1 − e^(−x26 π (T*/λ − T*/(x27 L_pp)))", matches `draft_coefficient`.
- The paper states "For the bow segments S1 and S2 the expression T* = T_max is valid" and gives Eq. 20, "T* = T_max (x28 + √|cos β|) / x29" for the stern (p. 7). `stern_draft` matches.
- The speed term 2ω0U/g uses "ω0 … the intrinsic wave frequency" (p. 6). The code uses the absolute wave frequency (λ = 2πg/ω²), which is the intended reading.

**Motion part (Eqs. 11–17, pp. 6–7):**

- Eq. 11: "C_AW,M = x1 a1 a2 a3 ω̄^b1 e^((b1/d1)(1 − ω̄^d1))". The code omits a3. Eq. 14 gives "a3 = 1.0 + x11 atan(|T_a − T_f|/L_pp)", which is 1 for the even-keel `Hull`, so this matches. The same applies to the trim factor "(4 − x16 atan|T_a − T_f|/L_pp)" in Eq. 16, which the code reduces to 4 (`d1` in `motion_coefficient`). Both are correct only for even keel. The `Hull` docstring states even keel, so this is fine.
- Eq. 12, first branch, "x3 C_B^x4 (x5 k_yy)² (x6/C_B)^(−(1+Fn) cos β) (ln B/T_max)^(−1) (1 − 2cos β)/x7 for β ∈ [π/2, π]", matches `a1` in `motion_coefficient`.
- Eq. 13, "0.0072 + x8 Fn for Fn < 0.12; Fn^x9 e^(−x10 Fn) for Fn ≥ 0.12", matches. Eq. 15, "b1 = x12 for ω̄ < 1, −x13 elsewhere", matches.
- Eq. 16, "x14 (L_pp C_B/B)^(−x15)" or "−x14 (L_pp C_B/B)^(−x15) × (4 − …)", matches.
- Eq. 17, "ω̄ = x17 ∛k_yy √(L_pp/λ) [1 − (x18/C_B)(ln(B_m/T_max) − ln x19)] (C_B/x20)^x21 × [(−x22 Fn² + x23 Fn)|cos β| + x24(13 + cos 2β)/x25]", matches `frequency_factor` with k_yy as gyration over length.

**Coefficients (Table 2, p. 9, "Final parameters").** All 29 values of `SNNM_FINE` (C_B < 0.70) and `SNNM_FULL` (C_B ≥ 0.70) match the table digit for digit, and the split at C_B = 0.70 matches ("two separate parameter vectors are obtained with the transition at C_B = 0.70", p. 7). The extra row "±0.2" in Table 2 is the offset x30 of the quantile (uncertainty-bound) regressions ("In addition, to the 29 parameters, an offset parameter x30 is defined", p. 8). It does not belong in the median model, so leaving it out is correct.

**Discrepancy 1.1, beam-to-following interpolation (`following_motion`).** Eq. 12 interpolates only the coefficient a1: "linear interpolation between β = π/2 and β = 0 for β ∈ ]0, π/2[". The text says the same: "The calculation of a1 in stern oblique waves β ∈ ]0, 90[ deg. is performed by linear interpolation between the beam and following sea case" (pp. 6–7). The code instead interpolates the whole C_AW,M between C_AW,M(β = π/2, Fn) and the following-sea value. In the paper, ω̄ (through |cos β| and cos 2β) is evaluated at the actual β, and so are the β-independent a2, b1 and d1 at the actual Fn. In the code, the following end uses a2 and ω̄ at Fn = 0 (or Fn_r), and the beam end uses them at Fn. The two agree at β = 0 and β = π/2 but differ in between. Suggested correction: compute a1(β) by interpolating a1 between a1(π/2) and the following-sea a1, then evaluate Eq. 11 with ω̄(β), a2(Fn), b1 and d1 at the actual heading. If the whole-coefficient interpolation is kept deliberately, say so in the paper as a simplification.

**Discrepancy 1.2, the following-sea rule (`following_motion`): partly verifiable.** Mittendorf summarises Liu & Papanikolaou (2020) as follows (p. 7): "(1) For Fn = 0, the added resistance and thus a1 are negative, (2) on the green curve (U = V_c/4) it is assumed that the radiation component vanishes (a1 = 0) and (3) on the orange curve (U = V_c/2) it is thought that C_AW is equal to the magnitude as in the head wave case, but for non-forward speed, i.e. a1 is positive, but calculated for Fn = 0. In addition, (4) the value at any condition in between will be obtained by linear interpolation and (5) conditions above the orange curve will be approximated using the relative Froude number Fn_r = (U − V_c/2)/√(g L_pp)".

The code matches points (2) to (5): zero at U/V_c = 1/4, the zero-speed head value at 1/2, linear in U in between, and the head-wave formula at Fn_r above that, continuous at U = V_c/2. On point (1), Mittendorf says only that the value is negative. The code's choice of exactly minus the zero-speed head-wave value at U = 0, which is what `(4ratio - 1)` implies, is not stated in Mittendorf. It is also unclear whether Fn_r in (5), and Fn = 0 in (3), apply to a1 only or to a2 and ω̄ as well. The code applies them to all three.

Liu & Papanikolaou (2020) is closed access (Unpaywall: `"oa_status":"closed"`) and could not be checked. The reference implementation (https://gitlab.gbar.dtu.dk/mamit/RAW_Formula) timed out. The rule is therefore only partly verifiable; see Need download.

**Discrepancy 1.3, spectral integration (`added_resistance`).** The factor 2 and the form R_AW = 2 ∫ (R_AW/ζ_a²) S(ω) dω, written as `2scale * Σ C_AW S Δω` with scale = ρgB²/L, are correct and match the irregular-wave equation in `model.tex`. Mittendorf does not give the irregular-wave formula; the paper only says "the calculation of the mean added resistance in irregular waves is trivial given a suitable (directional) wave energy density spectrum and under the assumption of linear superposition" (p. 14).

`model.tex` writes ∫_0^∞, but the code integrates 0.15–3.0 rad/s. With `periods = 3:18` in `PerformanceTable`, the upper cut drops a sizeable share of the spectral energy at short peak periods. The energy fraction above ω is 1 − exp(−1.25(ω_p/ω)⁴), so the code drops about 25 % of m0 at T_p = 3 s, 9 % at 4 s and 4 % at 5 s. In short waves C_AW tends to the near-constant reflection value, so R_AW is underestimated by up to that fraction. Suggested correction: raise the upper limit to about 5 rad/s, or scale it with ω_p (for example 0.2ω_p to 5ω_p).

**JONSWAP (`jonswap`).** The code matches DNV-RP-C205 (Oct. 2010) §3.5.5, p. 33: "S_J(ω) = A_γ S_PM(ω) γ^exp(−0.5((ω − ω_p)/(σ ω_p))²)", "S_PM(ω) = (5/16) H_S² ω_p⁴ ω^−5 exp(−(5/4)(ω/ω_p)^−4)", "σ = σ_a for ω ≤ ω_p, σ_b for ω > ω_p", "A_γ = 1 − 0.287 ln(γ) is a normalizing factor", and "Average values for the JONSWAP experiment data are γ = 3.3, σ_a = 0.07, σ_b = 0.09".

γ = 3.3 is the standard mean value. DNV §3.5.5.5 recommends, when no value is given, γ = 5 for T_p/√H_s ≤ 3.6, exp(5.75 − 1.15 T_p/√H_s) for 3.6 to 5, and 1 above 5. This is not an error, but with ERA5 sea states a fixed 3.3 is a choice worth stating.

## 2. Hull side-force derivatives (`src/hull.jl`, `side_force_slope`, `lateral_centre`, `leeway_drag`)

**Verdict: the formula matches Kijima et al. (1990) as reproduced in an open-access source. It could not be checked against Inoue et al. (1981), which is not accessible. The induced drag ½F_yβ is a lower bound, not a source formula.**

**Formula.** Kim & Lee (2021), J. Mar. Sci. Eng. 9:854, doi 10.3390/jmse9080854, reproduce "Kijima et al. (1990) empirical formula on an even keel and under full load conditions" in their Eq. 7 (p. 5):

- "Y'_β = ½ π k + 1.4 C_b B/L"
- "N'_β = k"
- "N'_r = −0.54k + k²"
- "where k = 2d/L"

So (π/2)·k with k = 2T/L is exactly πT/L, and the code's `π * draft / length + 1.4 C_B * beam / length` is identical. N'_β = k = 2T/L also matches.

**Non-dimensionalisation.** Kijima & Nakiri (2003), "On the practical prediction method for ship manoeuvring characteristics" (Nippon Foundation library copy), give in Eq. 2 "X', Y' = X, Y / (½ρ L d U²), N' = N / (½ρ L² d U²)". This matches the code's ½ρV²LT. The lever arm is then x_h = N/Y = N'_β L / Y'_β = 2T/Y'_β, which matches `lateral_centre`. With Y'_β > 0 and N'_β > 0, the side force acts forward of midship (the Munk moment), so the sign is consistent.

That later paper uses a different, newer regression ("Y'_β = ½πκ + 1.9257(C_b B/L)σ_a", "N'_β = κ[15.0668{…}² − 23.819{…} + 1.802]", Eq. 7). The code's form is the 1990 one.

**Attribution.** The bib entry `inoue1981` (Inoue, Hirano, Kijima, ISP 28(321):112–125) is plausibly the origin of the even-keel terms, but this could not be verified. Suggested correction: cite Kijima et al. (1990), J. Soc. Naval Arch. Japan 168:141–148, doi 10.2534/jjasnaoe1968.1990.168_141, for the exact form, or add it next to Inoue (1981) once Inoue is checked.

**Applicability.** Kijima's database is 13 merchant models (Kim & Lee, Table 1). Kim & Lee report that Kijima's formula overestimated turning advance by 43 % for trawler-type model hulls (Table 3), which is relevant for a short coaster (L/B = 6.4).

**Induced drag `leeway_drag` = ½F_yβ.** No source formula was found; Yasukawa & Yoshimura (2015) could not be downloaded (Springer bot wall). Reasoning:

- The term (π/2)k is Jones' slender-wing lift slope for aspect ratio k. For that potential part with full leading-edge suction, C_Di = C_L α/2, so D = ½F_yβ is exact.
- The 1.4 C_B B/L term is cross-flow (separated) lift, whose force is normal to the hull with no suction. It costs F_yβ.
- For the reference hull (T/L = 5.5/85, B/L = 13.2/85, C_B = 0.83), the potential part is 0.203 of Y'_β = 0.384, i.e. 53 %. A drag consistent with the same split is (½·0.203 + 0.181)/0.384 · F_yβ = 0.74 F_yβ, against 0.5 F_yβ in the code.
- The code therefore underestimates the leeway drag by about a third. This is reasonable as an optimistic lower bound if stated as such.
- Suggested correction: D_β = [(π/4)k + 1.4 C_B B/L] / Y'_β · F_yβ, or ½F_yβ with an explicit "lower bound (full suction)" remark. Alternatively, use measured X'_vv data (MMG) once Yasukawa & Yoshimura (2015) is available.

## 3. Rudder area A = TL/100 [1 + 25(B/L)²] (`rudder_area`)

**Verdict: not verifiable in a primary source. The formula is confirmed only by secondary material, and the current DNV class rules do not contain it.**

- **Current DNV rules.** The 2012 DNV Rules for Classification of Ships, Pt. 3 Ch. 3 (rules.dnv.com `ts303.pdf`), Sec. 2 on rudders, define "A = area of rudder blade in m², including area of flap" only for scantlings. I found no minimum-area formula in that document.
- **Secondary confirmation.** A lecture by P.-Å. Kvick (Linnaeus University, "Roderkrafter", slide "Conventional rudder (minimum area) — Classification guidance") gives "A_r = (d L/100)[1 + 25(B/L)²]". The same slide gives the Reed's alternative "A_r = d L / F, F 60–70".
- **Wording seen only in a search snippet.** A ScienceDirect topic page (book chapter citing Molland & Turnock 2007 and Brix 1993) was summarised by a search engine as "Det Norske Veritas recommends: (6.91) A_R/(L·T) ≥ 0.01·(1 + 25(B/L)²)". The page itself returned HTTP 403, so this is not a verified quote.

This wording points to an older DNV recommendation, quoted as a minimum, not "the DNV area". Suggested correction: write "the minimum rudder area recommended by DNV, A_r ≥ TL/100 [1 + 25(B/L)²] (Brix 1993; Molland & Turnock 2007)" once one of those books is checked.

## 4. Taylor wake fraction w = 0.5C_B − 0.05 and t = 0.6w (`src/propulsion.jl`)

**Verdict: both are confirmed by a secondary industry source. Taylor's original was not accessed.**

MAN Energy Solutions, "Basic principles of ship propulsion" (doc. 5510-0004-04), printed pp. 18–19 (pdf p. 10), says:

- "Typical values of w are shown in Table 2.02 (p. 22), a first estimate can be given by w = 0.5 × CB − 0.05, Ref. [2.2]. For large d/T ratios (propeller diameter to draught of the ship) the size of the wake fraction will be reduced."
- On thrust deduction: "a first estimate can be given by t = 0.27 × CB or by t = 0.60 × w, again considering that the value of t will reduce for large d/T ratios."
- Ref. [2.2] is Carlton, "Marine Propellers and Propulsion", 3rd ed., Elsevier 2012.

Taylor's single-screw formula (Taylor 1933, "Speed and Power of Ships") is reproduced in Carlton and in Harvald (1983), but neither was accessed. Suggested citation: Carlton (2012) or MAN (2018) for both relations, rather than leaving t = 0.6w as an unsupported model assumption. The code's `thrust_deduction_ratio` = 0.6 matches MAN.

## 5. Kite in-flight glide ratio (`model.tex`)

**Verdict: discrepancy. The 3.6 to 4.0 range is from two different kites, only the 3.6 is (likely) the 25 m² V3-generation kite, and the values exclude the tether.**

**van der Vlugt et al. (2019), arXiv 1705.04133v2 pagination.**

- Table 1 (p. 11) gives "Traction phase L/D_k 3.6 | 4.0" for the "moderate | strong" wind cases, with "Kite surface area A 25 m² | 14 m²" and "Mass kite incl. control unit m 19.6 kg | 15.0 kg".
- The kites are described on p. 9. The strong-wind kite is "a Genetrix Hydra 14 m² with a projected surface area of S = 10.2 m² modified to withstand the high wing loading … the control unit including the used sensor unit has a mass of 10 kg". The moderate-wind kite is "a scaled up and redesigned version of the Genetrix Hydra with a wing surface area of A = 25 m², a projected area of S = 18.6 m²".
- L/D_k is "the lift-to-drag ratio of the kite without the tether" (Eq. 60, p. 11). It is obtained after removing the tether drag D_t from flight data ("This estimate still includes the effect of tether drag D_t … To eliminate this we first recalculate the total aerodynamic drag", p. 11). It therefore includes bridle and KCU but excludes the tether.
- van der Vlugt does not call the 25 m² kite "V3". Oehler & Schmehl (2019, p. 5) describe their 25 m² LEI V3 as reflecting "the technology status in 2012 (… van der Vlugt et al., 2019)".

**Oehler & Schmehl (2019), WES 4:1–21.**

- "The experiments described in this paper have been performed with a LEI V3 kite with a wing surface area of 25 m²" (p. 5).
- "The lift-to-drag ratio of the entire kite (all components from bridle point outwards) is derived … the aerodynamic drag on the KCU and measurement setup [is taken into account]" (p. 13).
- "During the traction phases we measure an average lift-to-drag ratio of about L/D = 4, and during the retraction phases we measure an average ratio of about L/D = 3" (p. 14).
- "The maximum of about L/D = 5 occurs in the range 5° < α < 10° and is only reached for u_p = 1" (p. 14).
- Their Table 1 (p. 2) lists van der Vlugt et al. (2019) as "LEI, 14, 25 m², … L/D 4, 3.6".

These values cover kite, bridle and KCU, without the tether.

**Suggested correction:** "the 25 m² V3 kite reaches a lift-to-drag ratio of 3.6 (van der Vlugt et al. 2019) to about 4 (Oehler & Schmehl 2019) in traction, including bridle and control unit but without the tether". This affects the calibration claim: the model's target of 4 with bridle but without tether is consistent with these numbers.

## 6. NOAA Mariners Weather Log, April 2009 (SkySails)

**Verdict: matches.**

From https://vos.noaa.gov/MWL/apr_09/skysails.shtml (fetched directly), article "Skysails" by Captain John Konrad, Mariners Weather Log 53(1), April 2009: "Of further importance, the SkySails-System is designed for operation in predominantly prevailing wind forces of 3 to 8 Beaufort at sea. The system can be recovered, but not launched at wind forces below 3 Beaufort."

Minor fixes to the bib entry `noaa2009`:

- The author is John Konrad, not the "NOAA Voluntary Observing Ship Program".
- It is a secondary popular article restating SkySails' own specifications.
- Beaufort 3 is a 10 m wind of 3.4–5.4 m/s. The model's 6 m/s apparent wind at 170 m is a translation of that limit, not a quote.

## 7. A quarter of the tether drag acting at the kite

**Verdict: matches; a source was found.**

van der Vlugt et al. (2019), p. 3 (arXiv pagination): "The aerodynamic drag of the tether is taken into account by adding one fourth of the tether drag area to the kite drag area as proposed in [3] and numerically validated in [28]". Eq. 13 gives "D_t = (1/8) ρ d_t r C_D,c v_a²".

- [3] is Argatov, Rautakorpi, Silvennoinen (2009), Renewable Energy 34(6):1525–1532, doi 10.1016/j.renene.2008.11.001.
- [28] is Argatov, Rautakorpi, Silvennoinen (2011), J. Wind Eng. Ind. Aerodyn. 99(5):1079–1088, doi 10.1016/j.jweia.2011.07.010.

`tether_drag` in `src/rig.jl` uses `C_D,t d L / (4A)` added to the kite drag coefficient, which is the same as ¼·½ρ C_D,t d L v_a². This matches, provided A is the same reference area as the kite polar (van der Vlugt uses the projected area S). Suggested citation: van der Vlugt et al. (2019) and Argatov et al. (2009).

## Need download

1. Liu, S., Papanikolaou, A. (2020). Regression analysis of experimental data for added resistance in waves of arbitrary heading and development of a semi-empirical formula. Ocean Engineering 206:107357. doi 10.1016/j.oceaneng.2020.107357. Closed access: https://doi.org/10.1016/j.oceaneng.2020.107357 (try NTUA or ResearchGate author copy). Needed for the following-wave rule (check 1.2), in particular the magnitude at U = 0 and whether Fn_r and Fn = 0 apply to a1 only.
2. Mittendorf et al. reference code: https://gitlab.gbar.dtu.dk/mamit/RAW_Formula (connection timed out from the sandbox). This would settle discrepancies 1.1 and 1.2 directly.
3. Inoue, S., Hirano, M., Kijima, K. (1981). Hydrodynamic derivatives on ship manoeuvring. International Shipbuilding Progress 28(321):112–125. doi 10.3233/ISP-1981-2832103. https://content.iospress.com/articles/international-shipbuilding-progress/isp28-321-03
4. Kijima, K., Katsuno, T., Nakiri, Y., Furukawa, Y. (1990). On the manoeuvring performance of a ship with the parameter of loading condition. J. Soc. Naval Arch. Japan 168:141–148. doi 10.2534/jjasnaoe1968.1990.168_141. https://www.jstage.jst.go.jp/article/jjasnaoe1968/1990/168/1990_168_141/_article (the PDF link needs a browser).
5. Yasukawa, H., Yoshimura, Y. (2015). Introduction of MMG standard method for ship maneuvering predictions. J. Mar. Sci. Technol. 20:37–52. doi 10.1007/s00773-014-0293-y. Open access: https://link.springer.com/article/10.1007/s00773-014-0293-y (Springer blocked the scripted download). Useful for X'_vv data on the leeway drag.
6. Molland, A.F., Turnock, S.R. (2007). Marine Rudders and Control Surfaces. Butterworth-Heinemann. doi 10.1016/B978-0-7506-6944-3.X5000-2. Alternatively Brix, J. (ed.) (1993), Manoeuvring Technical Manual, Seehafen Verlag. Either is needed for the DNV rudder-area quote with page.
7. Carlton, J. (2012). Marine Propellers and Propulsion, 3rd ed. Elsevier. doi 10.1016/C2010-0-68327-0. Alternatively Taylor, D.W. (1933), The Speed and Power of Ships. Needed for the primary attribution of w = 0.5C_B − 0.05.
