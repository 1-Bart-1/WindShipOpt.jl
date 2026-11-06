# Repo guide

This repository holds a ship and rig cost model, and a paper built on it: "Towing kites, wing sails and Flettner rotors on cargo ships: a routed cost comparison across ship classes, routes and fuels".

## Paper rules

- The comparison is objective, with no advocacy. Each rig is treated equally, near its own optimum.
- Every input comes from real, sourced data. Cite only papers read in full. Never base a number on a search snippet or an abstract.
- If a source can't be fetched, retry outside any sandbox, then ask Bart on the thread with its title and DOI. Bart has institutional access.
- Where full-scale data are missing, predict from physics and small-scale evidence, and state the scaling law and its assumptions.
- Never use data from Beyond the Sea or its SK100 kite, and never name that kite in the paper.
- The paper refers to no local file. The kite canopy is polyester ripstop.
- On the box, build the paper in a TeX Live container (Docker) after every change to its text, tables or figures, and look at the rendered pages you changed: a table or figure that is cut, overflowing, scaled up or hard to read is a defect. Never commit the PDF or LaTeX build files. Bart builds his own copy.
- Prose is one paragraph per line. `\tbd{...}` marks a number or claim still to be confirmed.

## Data outside the repository

`/var/lib/windship/` on the box holds what git doesn't:

- `era5/`: the weather. Link it into the worktree with `ln -s /var/lib/windship/era5 era5`.
- `output/`: shared results. Link it with `ln -s /var/lib/windship/output output`, so runs survive a worktree and later tasks can read them.
- `literature_pdfs/`: sources and their extracted text, read-only by convention. Link it with `ln -s /var/lib/windship/literature_pdfs paper/literature_pdfs`. `paper/sources.csv` is the one record of what is held and read; `scripts/check_sources.py` fails on a cited source not read in full, or a held file whose hash changed.
- `gate/`: reference results and scratch scripts of the router accuracy gate. `scripts/router_gate.jl` reruns the gate and resumes from the cases a stopped run finished; `gate/fine_3h_1.5h/` is the reference at the current router settings.
- `laptop_output/`: earlier laptop results. They come from older router code, so use them only to compare trends, never as paper numbers.

## Running

- Use Julia 1.12, with `Manifest-v1.12.toml.default` and `scripts/Manifest-v1.12.toml.default` copied to `Manifest-v1.12.toml` next to them.
- `paper(names...; fidelity, resume)` in `scripts/paper.jl` runs the studies. Each run writes to `output/runs/<stamp>/`, with its code hash and commit in `run.toml`.
- A final run refuses a dirty tree or an unpushed commit.
