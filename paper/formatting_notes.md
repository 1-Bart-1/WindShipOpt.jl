# Formatting notes

## Changed

- `main.tex` preamble: loads `longtable`; `xcolor` now comes before `hyperref`;
  links are coloured dark blue (`colorlinks,allcolors={blue!50!black}`) instead
  of hidden; cleveref writes "Fig."/"Figs." for both `\cref` and `\Cref`, so the
  text no longer mixes "Figure 7" and "Fig. 7"; float parameters are looser
  (`\topfraction` 0.9, `\textfraction` 0.1, `\floatpagefraction` 0.7, up to 3
  top floats) so two floats can share a page; `placeins` is `[section,below]`,
  which keeps every float in its own section but lets it sit on the page where
  the next section starts.
- Appendices: references to them said "Section Appendix A"; they now say
  "Appendix A" (`\crefalias{section}{appendix}` with a name-free format). Figure
  and table counters now restart in each appendix (elsarticle did not reset
  them, so the cost table was "Table B.2" as the only table in Appendix B; it is
  now B.1). The `\clearpage` before the references is gone.
- Front matter: Bart van de Lint is marked as the corresponding author
  (`\corref`/`\cortext`). The highlights page before the title is elsarticle's
  standard behaviour and is kept.
- Floats: all figures and tables are `[tbp]` instead of `[t]`. With `[t]` LaTeX
  could not build float pages, so each half-page results figure got its own
  nearly empty page.
- Figure order: `fig:routes` and `fig:wind_climate` are first cited in the
  Method (Section "Weather and routes") but were placed in the Results, so they
  were numbered 8 and 11 while cited before Fig. 5. Both float blocks moved
  unchanged to the end of that Method subsection (before
  `\subsection{Weather routing}`); figures are now numbered in the order they
  are first cited.
- Captions in `results.tex`: "10~m wind" is now `\SI{10}{m} wind`, like the rest
  of the paper.
- Cost table: it ran 274 pt off the page as a `table*`. `sections/inputs.tex`
  now holds a `longtable` with the caption, a header repeated on every page
  ("Table B.1 (continued)"), ragged-right Input and Source columns, a full-width
  caption and a little row spacing. `scripts/paper_tables.jl` now writes only
  the rows to `cost_table.tex`, and writes "--" for dimensionless units instead
  of "-".
- Bibliography: `man2011` had no year, so it was cited as "(MAN Energy
  Solutions, )". It now has `year = {2018}`, the edition the repo's data notes
  cite (doc. 5510-0004-04); the key is unchanged. `emsa2023` got `institution`
  and `address = {Lisbon}`, which fixes the BibTeX warning. The German
  `wrage2018` title is brace-protected, because the style had lowercased its
  nouns ("zugdrachen", "frachtschiffe").

## Needs your action or decision

- Run `scripts/paper_tables.jl` (I did not run Julia). Until you do, the old
  `cost_table.tex` (a whole `tabular`) sits inside the new `longtable`: it
  compiles but runs off the page. The script's `names` list also has inputs the
  current generated file lacks (`market_price_factor`, `wing_unit_cost`,
  `rotor_cost_per_area`, …): `costs.tex` quotes the new wing and rotor pricing
  while the table still shows the old `wing cost per area` of 2000 USD/m². The
  longtable handles the extra rows.
- `sections/model.tex`, "Weather and routes", has a broken fragment:
  `… finer (\cref{sec:checks}). apart.}. Nodes and edges …`. The stray `}` is a
  LaTeX error ("Too many }'s") and `apart.}.` is left-over text. I left it alone
  because model.tex is being edited at the same time; delete `apart.}.` there.
  My scratch build patched it.
- Figures not yet referenced in the text (their paragraphs are still `\tbd`):
  `fig:premium`, `fig:rig_comparison`, `fig:route_comparison`,
  `fig:class_comparison`, `fig:class_sizes`, `fig:winner_map`, `fig:breakdown`.
  Cite each one in the results text before the figure. Unused figure files in
  `figures/`: `chains.pdf`, `fishing.pdf`, `life.pdf`, `pareto.pdf` (plus old
  `*-1.png` files).
- Results layout: most page-wide results figures are about 300 pt tall plus
  caption, so two of them do not fit on one 622 pt page. Until the results text
  is written they fill pages 14–19 one or two at a time; the gaps will fill with
  text once it is there. If they still leave gaps then, the fix is shorter
  figures from the plotting scripts, not scaling them down in LaTeX.
- Link colour: dark-blue links are for review copies. For final submission go
  back to `hidelinks` if you prefer; Elsevier re-typesets anyway.
- `poland2025` (Wind Energy Science Discussions) has no volume or DOI and
  renders with a dangling " ."; add its DOI. `podeur2016` has no page numbers
  (harmless BibTeX warning).
- Applied Energy requires sections the paper does not have yet: Declaration of
  competing interest, CRediT author statement, Data availability (the repository
  link is still `\tbd`), and the declaration on generative AI use. Abstract
  limit is 250 words.
- The `\plot` macro's optional width argument (`\plot[\textwidth]{…}`) is
  ignored; it is harmless but could be removed.
