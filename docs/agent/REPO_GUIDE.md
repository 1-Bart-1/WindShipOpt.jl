# Repo guide

This repository holds a ship and rig cost model, and a paper built on it: "Towing kites, wing sails and Flettner rotors on cargo ships: a routed cost comparison across ship classes, routes and fuels".

## Paper rules

- The comparison is objective, with no advocacy. Each rig is treated equally, near its own optimum.
- Every input comes from real, sourced data. Cite only papers read in full. Never base a number on a search snippet or an abstract.
- If a source can't be fetched, retry outside any sandbox, then ask Bart on the thread with its title and DOI. Bart has institutional access.
- Where full-scale data are missing, predict from physics and small-scale evidence, and state the scaling law and its assumptions.
- Use data from Beyond the Sea or its SK100 kite, or name that kite in the paper, only with Beyond the Sea's consent given through Bart; with it, cite the data as provided by Beyond the Sea. Their published papers may always be cited.
- The paper refers to no local file. The kite canopy is polyester ripstop.
- The paper is one document, `paper/main.tex`, built from `paper/sections/`: a body and appendices in the same PDF, with no separate supplement. The body reads from start to end without the appendices: every figure, table and equation its text needs stands in the body where it is used, and the models are in the Method. A pointer to an appendix only offers more (a derivation, a check, a full input table, a secondary study), in a sentence that stands without it.
- After every change to the paper, the extended abstract or the kite design paper (their text, tables, figures or preamble), run `./bin/build_paper`: it builds the TeX Live image `paper/tex/Dockerfile` defines and all three documents in it, as CI does; a package a document starts to load goes into that Dockerfile in the same change. Look at the rendered pages you changed: a table or figure that is cut, overflowing, scaled up or hard to read is a defect. Never commit the PDF or LaTeX build files. Bart builds his own copy.
- Prose is one paragraph per line. `\tbd{...}` marks a number or claim still to be confirmed.
- `\stale{<studies>}{...}` marks text, a table or a figure caption whose numbers a merged change made stale until the named studies rerun, comma-separated. The paper build warns at each and lists the studies left at its end; the pull request that rewrites the text from the rerun removes the marker.
- `\studyresult{<studies>}{...}` marks text, or with an empty body a table or figure caption, whose numbers come from the recorded run of a finished method study whose code has left the repository; that run and its commit are named where its table or figure is (`\studyrun`). It stays: such a study never reruns.
- A result number in the result-bearing text (abstract, highlights, results, certainty, limits, industry, conclusions, the trust appendix, extended abstract) is a generated `\Num...` macro or table, or sits in `\stale` or `\studyresult`; in a table or figure, one `\stale{<study>}{}` in its caption covers it. An input, literature value or method constant typed there is wrapped in `\given{...}`. `scripts/check_numbers.py` lists every other number typed there, and `scripts/check_highlights.py` every highlight longer than the journal's `\NumHighlightLimit` characters as rendered; CI and `latexmk` in `paper/` run both.

## Data outside the repository

`/var/lib/windship/` on the box holds what git doesn't:

- `era5/`: the weather. Link it into the worktree with `ln -s /var/lib/windship/era5 era5`.
- `output/`: shared results. Link it with `ln -s /var/lib/windship/output output`, so runs survive a worktree and later tasks can read them.
- `literature_pdfs/`: sources and their extracted text, read-only by convention. Link it with `ln -s /var/lib/windship/literature_pdfs paper/literature_pdfs`. `paper/sources.csv` is the one record of what is held and read; `scripts/check_sources.py` fails on a cited source not read in full, a held file whose hash changed, or a source the input or class source tables name in words rather than by key.
- `gate/`: reference results and scratch scripts of the router accuracy gate. `scripts/router_gate.jl` reruns the gate and resumes from the cases a stopped run finished; `gate/fine_3h_1.5h/` is the reference at the current router settings.
- `laptop_output/`: earlier laptop results. They come from older router code, so use them only to compare trends, never as paper numbers.

## Running

- Use Julia 1.13, with `Manifest-v1.13.toml.default` and `scripts/Manifest-v1.13.toml.default` copied to `Manifest-v1.13.toml` next to them.
- `paper(names...; fidelity, resume)` in `scripts/paper.jl` runs the studies. Each run writes to `output/runs/<stamp>/`, with its code hash and commit in `run.toml`, and stores its round trips in `output/cases/`, which every run shares. `paper_status(; fidelity)` lists the steps a change made out of date, which `paper` then reruns; [`docs/paper_runs.md`](../paper_runs.md) has the workflow.
- A final run refuses a dirty tree or an unpushed commit.
- A paper run computes the results only. A method study, which chooses or checks a method or setting, is one of `study_steps` and runs by name, `paper(:sea_effect; fidelity=:draft)`: that records its run in `paper/study_runs.toml` and writes its tables, whose captions name the run and commit through `\studyrun`. Commit both with the tables.
