# Paper runs

`paper(names...; fidelity)` in `scripts/paper.jl` computes the paper's results in steps: data steps that route ships and write CSV files, then figure and table steps that read them. Each call that makes data writes a run, `output/runs/<start time>/`, with the data files and the record `run.toml`. A step reads another step's data file from the run in use, else from the latest finished run of its fidelity, this branch's first.

## What a run keeps

Every round trip a step routes is kept in the case store, `output/cases/`, which all runs share. A stored round trip is found again by its case (ship, rig, route, fuel, departures, model part), by the value of every input of `data/assumptions.yaml` it read, by the contents of every data file it read, and by the code of a round trip. That code is everything in `src/`, the data tables, the kite polars, `scripts/setup.jl`, the package manifests, the Julia version, and the definitions in the scripts that building and sailing a case reach by name. A step whose own code changed therefore rewrites its tables from the stored round trips in minutes, and a changed input routes again only the round trips that read it.

`run.toml` says for every step what made it: the commit and whether the tree was dirty, the hash of each definition its code reaches (`model` for the model files), the base value of every input it read, the content hash and run of every data file it read, and for its round trips how many there are, which commit and processor computed them, and how many it kept from older code. `cases/<step>.csv` in the run lists each round trip of the step by its labels, with its case-store directory, the commit and tree that computed it, its round-trip code and its processor, so a sliced draft says which class, route or rig rests on which commit.

## Rerunning what changed

```julia
include("scripts/paper.jl")
stale = paper_status(; fidelity=:draft)   # print each step's state, return the out-of-date ones
paper(stale...; fidelity=:draft)          # rerun exactly those
paper(:figures; fidelity=:draft)          # redraw the figures and tables from the new data
paper(:figures; fidelity=:final, source="2026-11-20T2000")  # from that run first
```

Figure and table steps take `source`, a run they read before any other. A run counts as finished only once every step asked of it is done, so a run whose figure steps failed would otherwise be read only after every finished run of its fidelity, older ones included. The figures and tables draw only the rigs the run holds.

`paper_status` lists every data step and method study with the run and commit its data come from, and says why one is out of date: its code or the model changed, an input it read has another value, a data file it read was rewritten, it kept round trips from older code, or it reads a data file of a step that is out of date. It also says whether the step's round trips route again or are stored. The steps come back in the order they run, so the class study reruns before the studies that read its rig sizes.

A `\stale{<steps>}{...}` marker in the paper names the steps whose rerun it waits for. Once `paper_status` lists a step as current, the text the marker covers can be rewritten from its data and the marker removed.

## A figure or table that fails to draw

A figure or table that fails, on its label check or anything else, stops no other step. The run keeps its data, finishes once every data step is done, and `paper` ends with an error naming each figure and table that failed and why. Once the code is fixed, `paper(:canopy_tension_figure; fidelity=:final)`, or `paper(:figures; fidelity=:final)` for all of them, redraws from that run's data without routing anything. A run that stopped in a figure before figures stopped nothing is still unfinished: `paper(; fidelity=:final, resume=true)` on its branch, or `bin/cluster submit final` there, skips every data step it has and draws the rest.

## Rerunning one slice of a step in a draft

After a change to the model, a draft can be brought up to date one ship class, route, fuel or rig at a time:

```julia
paper(:classes; fidelity=:draft, only=(class="handysize",))
paper(:classes; fidelity=:draft, only=(route=(:caribbean, :new_york), drive=:ammonia))
```

`only` names labels of the step's cases and the values to compute; a step none of whose cases carries them stops with an error rather than recompute nothing. Cases outside it take the latest stored round trip of any code; `run.toml` counts them under `older_cases`, and `paper_status` lists the step as out of date until a run computes them with the current code. A final run takes no `only`.

## Final runs

A final run needs a clean tree on a pushed commit, and it takes from the case store only round trips computed at that commit with a clean tree, so every part of it comes from one commit. `paper_status(; fidelity=:final)` prints the commit of each step's data and ends by saying whether every step and round trip comes from one clean commit, naming the commits where not.

The class study's rig size search starts on e-ammonia from the best sizes in `data/size_guesses.csv`, and on VLSFO from the best size e-ammonia found. The guesses are committed with the code, so a run's commit fixes them as it fixes every input, and the search routes on until the sizes either side of the best cost more, so the best size is confirmed by routing rather than taken from the guess. After a class study whose inputs moved, refresh them from its table, `write_size_guesses(read_table("output/runs/<run>/classes.csv"))`, and commit the file.

## Runs on a Slurm cluster

A run can hand its round trips to a Slurm cluster such as TU Delft's DelftBlue. The run itself is one job running `paper`, as on a workstation. Each time a step has more round trips than the job has cores, the run writes them to a batch file under `output/jobs/<run>/` and splits them into one share per as many round trips as a job has cores, every `k`-th round trip to the `k`-th share, at most one share per job the run may have running. The run's own job computes the first share and submits a job for each other one; it then waits for the store and goes on, so the cases of a later wave, such as the next round of the rig size search, are handed out once the data they read exist. The run folder that comes out is the one a workstation writes: one start time, one commit, one record.

Every job asks for the same wall time, and a run longer than that carries on by itself. Each run job queues a successor that starts once it ends, and cancels it when the run finishes or fails; a run job ended at its wall time leaves the successor to resume the run from the case store, taking over the computing jobs still running rather than submitting them again. A computing job ended at its wall time or by a node fault loses only the round trips it was computing: the run submits it again, and it computes only what is still missing. Once `retries` launches in a row of a share stored nothing, the run stops with an error naming every case still missing; once more run jobs in a row than `retries` found the run with no step done and no round trip stored since the one before, as a run job the cluster kills for its memory would, the run stops queueing successors. Submitting the run again resumes it: it computes nothing that is stored, and hands out the rest.

A job computing round trips loads only what routing needs, without the plotting packages, and on the box starts its first round trip 10 seconds after Julia starts. Its first round trip of each rig compiles almost nothing, about a second, since the package's precompile workload routes one departure of every rig; installing the package takes about a minute longer for it. A kite whose flight-pattern table is not yet in `output/pattern_tables/` builds it first, about 12 minutes on 4 cores, and every later job reads it from there. A job's share holds about one round trip per core, so a job stores nothing unless its wall time outlasts the longest round trip of its share. On the box a class case with a kite takes 8 minutes on one core in a draft (2 departures) and 48 minutes on average in a final run (12 departures): an hour serves a draft, while a final run needs four hours or more. `bin/cluster estimate`, run inside a job, gives these times on the cluster's own processor.

Every cluster setting is in `scripts/cluster.toml`: the account and partition (DelftBlue's research account `research-ae-fpt` on `compute-p2` by default), the cores and memory of each job, the wall time of every job, how many jobs run at once, the run's own included, and the retries. Where the cluster limits the cores of each job, run `jobs` jobs of the most cores allowed; where it limits the cores of all running jobs together, run one job of all of them, `jobs = 1`, which computes every round trip itself. All jobs of a run use the one partition, so one processor model computes the whole run. A final run takes only round trips computed on the processor it runs on; a draft takes them from any machine, so a draft may mix round trips from a workstation and from the cluster.

### Setting it up once, on a DelftBlue login node

Compute nodes have no internet, so Julia, the packages and the weather are fetched on a login node. `bin/delftblue_setup` does all of it: juliaup, the repository on `/scratch` (5 TB, but cleared of old files, so copy the results back after each run), the packages, and the weather through `bin/weather` from public stores. It resumes where it stopped and runs at the lowest CPU priority on 4 threads, so the login node stays usable; run it inside `tmux`, since the weather takes hours.

A draft and a final run read five weather folders under `era5/atlantic_wide/`, 14 GB together: the ERA5 wind and wave series (1.2 GB), the ERA5 wind speed aloft (0.9 GB, from 16 GB of pressure levels), their climate means (8 MB), and the GEFSv12 control forecast of every day with its bias and blend weights (12 GB). On 4 cores the packages took 13 minutes, the ERA5 series 8, the climate means 10, and the forecast about 29 seconds per day of waves and 11 of wind, some 12 hours for its 1096 days. The forecast ensemble members and the GEFS v11 forecasts that the box also holds are read only by the method studies of the forecast, not by a paper run, so they are not fetched; nor is the box's case store, since a run routes what it does not find there. `bin/weather` ends with `scripts/check_weather.jl`, which hashes each of the 48 files against `data/weather_sha256.toml`, the box's, and names every file missing or different. Delete such a file's folder and run `bin/weather` again.

```bash
ssh <netid>@login.delftblue.tudelft.nl   # from outside TU Delft's network, connect eduVPN first
tmux
curl -fsSL https://raw.githubusercontent.com/1-Bart-1/WindShipOpt.jl/main/bin/delftblue_setup | bash
exec bash -l   # puts julia on your PATH
```

Jobs are charged to the research account `research-ae-fpt` (faculty AE, department FPT): a job may run up to 120 hours, and up to 64 jobs of one user run at once. The run uses all 64 jobs, of 64 cores and 6 hours each: short jobs slip into gaps in the queue sooner, and the run resumes by itself past them. 6 hours is well over the 48 minutes a final round trip takes on average, so a slow one still finishes inside its job. Without a research account, set `account = "innovation"` and `jobs = 4`: 24 hours a job and 4 jobs at once, and a draft and a final run started together share those 4. The setup lists your accounts at its end. Commit any change to `scripts/cluster.toml`, since a final run needs a clean tree on a pushed commit. `compute-p1` has 48 cores and at most `3996M` per core, `compute-p2` 64 cores and at most `4000M`; keep `cores` at most the partition's.

### Running

```bash
bin/cluster submit draft            # a draft run of every step; `final` for a final run
bin/cluster submit draft classes    # or only the steps named
bin/cluster status                  # jobs queued, and what the latest run of each fidelity has done
```

`bin/cluster estimate [cores]` prints what a final and a draft run take, in core hours and in days on the cluster's jobs, on one job, and on a workstation of `cores` cores (20 by default). It takes the cases of each step from the finished draft run with the most steps, scales them to each fidelity's departures, and prices them at the core seconds per departure of a sample of round trips it times on the machine it runs on: one case of each ship class with each rig, and the 140 m e-ammonia ship to Guadeloupe with each rig, with perfect foresight and sailed live. The sample takes some hours on every core it is given, so time it on a workstation or inside a job (`srun --account=<account> --partition=<partition> --cpus-per-task=64 --time=8:00:00 bin/cluster estimate`), never on a login node. It is kept in `output/estimates/` per round-trip code and processor and timed again only when either changes.

`status` lists the jobs, each run's steps done and still to do, and for each batch how many of its round trips are stored. The run's log is `output/slurm/run-<job>.log` and each job's log sits beside its batch in `output/jobs/<run>/`. A run that stopped, at its wall time or naming the cases still missing, is finished by submitting it again with the same command. Bring the run and the case store home with `rsync -a <netid>@login.delftblue.tudelft.nl:/scratch/<netid>/WindShipOpt.jl/output/ output/`. Pull on the cluster before submitting a final run, so it runs the commit you mean.
