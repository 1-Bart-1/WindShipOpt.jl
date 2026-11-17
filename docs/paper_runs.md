# Paper runs

`paper(names...; fidelity)` in `scripts/paper.jl` computes the paper's results in steps: data steps that route ships and write CSV files, then figure and table steps that read them. Each call that makes data writes a run, `output/runs/<start time>/`, with the data files and the record `run.toml`. A step reads another step's data file from the run in use, else from the latest finished run of its fidelity, this branch's first.

## What a run keeps

Every round trip a step routes is kept in the case store, `output/cases/`, which all runs share. A stored round trip is found again by its case (ship, rig, route, fuel, departures, model part), by the value of every input of `data/assumptions.yaml` it read, by the contents of every data file it read, and by the code of a round trip. That code is everything in `src/`, the data tables, the kite polars, `scripts/setup.jl`, the package manifests, the Julia version, and the definitions in the scripts that building and sailing a case reach by name. A step whose own code changed therefore rewrites its tables from the stored round trips in minutes, and a changed input routes again only the round trips that read it.

`run.toml` says for every step what made it: the commit and whether the tree was dirty, the hash of each definition its code reaches (`model` for the model files), the base value of every input it read, the content hash and run of every data file it read, and for its round trips how many there are, which commit and processor computed them, and how many it kept from older code.

## Rerunning what changed

```julia
include("scripts/paper.jl")
stale = paper_status(; fidelity=:draft)   # print each step's state, return the out-of-date ones
paper(stale...; fidelity=:draft)          # rerun exactly those
paper(:figures; fidelity=:draft)          # redraw the figures and tables from the new data
```

`paper_status` lists every data step and method study with the run and commit its data come from, and says why one is out of date: its code or the model changed, an input it read has another value, a data file it read was rewritten, it kept round trips from older code, or it reads a data file of a step that is out of date. It also says whether the step's round trips route again or are stored. The steps come back in the order they run, so the class study reruns before the studies that read its rig sizes.

A `\stale{<steps>}{...}` marker in the paper names the steps whose rerun it waits for. Once `paper_status` lists a step as current, the text the marker covers can be rewritten from its data and the marker removed.

## Rerunning one slice of a step in a draft

After a change to the model, a draft can be brought up to date one ship class, route, fuel or rig at a time:

```julia
paper(:classes; fidelity=:draft, only=(class="handysize",))
paper(:classes; fidelity=:draft, only=(route=(:caribbean, :new_york), drive=:ammonia))
```

`only` names labels of the step's cases and the values to compute. Cases outside it take the latest stored round trip of any code; `run.toml` counts them under `older_cases`, and `paper_status` lists the step as out of date until a run computes them with the current code. A final run takes no `only`.

## Final runs

A final run needs a clean tree on a pushed commit, and it takes from the case store only round trips computed at that commit with a clean tree, so every part of it comes from one commit. `paper_status(; fidelity=:final)` prints the commit of each step's data, which shows where final data were made at different commits.
