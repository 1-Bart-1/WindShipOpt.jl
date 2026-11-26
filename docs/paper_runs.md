# Paper runs

`paper(names...; fidelity)` in `scripts/paper.jl` computes the paper's results in steps: data steps that route ships and write CSV files, then figure and table steps that read them. Each call that makes data writes a run, `output/runs/<start time>/`, with the data files and the record `run.toml`. A step reads another step's data file from the run in use, else from the latest finished run of its fidelity, this branch's first.

## What a run keeps

Every round trip a step routes is kept in the case store, `output/cases/`, which all runs share. A stored round trip is found again by its case (ship, rig, route, fuel, departures, model part), by the value of every input of `data/assumptions.yaml` it read, by the contents of every data file it read, and by the code of a round trip. That code is everything in `src/`, the data tables, the kite polars, `scripts/setup.jl`, the package manifests, the Julia version, and the definitions in the scripts that building and sailing a case reach by name. A step whose own code changed therefore rewrites its tables from the stored round trips in minutes, and a changed input routes again only the round trips that read it. Each departure of a round trip is stored on its own as it is routed, under the round trip's directory in `departures/`, with the inputs and data files its routing read; the round trip is combined from them once all are in. A round trip stopped part way routes only its missing departures when it is computed again, and comes out the same as one routed whole.

`run.toml` says for every step what made it: the commit and whether the tree was dirty, the hash of each definition its code reaches (`model` for the model files), the base value of every input it read, the content hash and run of every data file it read, and for its round trips how many there are, which commit and processor computed them, and how many it kept from older code. `cases/<step>.csv` in the run lists each round trip of the step by its labels, with its case-store directory, the commit and tree that computed it, its round-trip code and its processor, so a sliced draft says which class, route or rig rests on which commit.

## Keeping a run on GitHub

`output/` is not in git, and a cluster's scratch space is cleared of old files, so each run is also kept as an asset of a GitHub release. Each commit has one release, a prerelease tagged `run-<commit>`, which keeps at most one run per fidelity: `draft.tar.gz` and `final.tar.gz`. An archive holds the run's directory and the round trips and departures of the case store it uses, and its label names the run and how many steps it has done. Two commands sync runs, from a laptop or the box, with gh signed in to GitHub:

```bash
bin/runs push <run>                                   # a run of this checkout
bin/runs push <run> <netid>@login.delftblue.tudelft.nl:/scratch/<netid>/WindShipOpt.jl
bin/runs pull <run or commit>                         # into this checkout
bin/runs pull <run or commit> <netid>@login.delftblue.tudelft.nl:/scratch/<netid>/WindShipOpt.jl
```

`push` copies the run with rsync, from this checkout or a checkout on another machine over ssh, packs it and uploads it, replacing the archive of the same run; the old archive is deleted only once the new one is in. Push after a run, and as often as you like while one goes: a run in progress lists the case stores its round trips go to as soon as it starts them, so the archive holds every round trip and departure stored so far. A different run of the same commit and fidelity replaces the one kept only when it has more steps done; otherwise `push` stops and names the run kept.

`pull` downloads the runs of that name, or of the commit whose hash starts so, and copies each into the checkout: here, or with rsync onto a cluster, so that a run cut short there continues with the usual resume. A run already there with as many steps done is left as it is; round trips the store lacks are added and none is overwritten. Resuming stays as safe as before: a run resumes only on its own branch, and a stored round trip is used only where its code and inputs match.

To read a run without the repository's tools, download the archive from the release page and unpack it: `tar -xzf draft.tar.gz` gives `runs/<run>/` and `cases/`.

`bin/runs backfill` pushes every run of this checkout's `output/runs/` worth keeping: of the runs of one commit and fidelity the one `paper/study_runs.toml` names, else the one with most steps done. A method study's run that `paper/study_runs.toml` does not name is skipped. It goes on past a run it cannot push and prints what it skipped and why.

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

The class study routes a kite over rotors as a rig of its own only on the classes and fuels in `data/pair_cases.csv`, on every route of each, its kite and rotor areas searched in turn from the best of each alone. The file holds where the kite-and-rotors step (`paper(:combination_data; fidelity=:final)`) found the pair clearly leading each rig alone; after a rerun of that step, refresh it with `write_pair_cases("output/runs/<run>")` and commit it.

## Runs on a Slurm cluster

A run can hand the departures of its round trips to a Slurm cluster such as TU Delft's DelftBlue. The run itself is one job running `paper`, as on a workstation. Each time a step's missing round trips have more departures than the run's own job has cores, the run writes the step's cases to a batch file under `output/jobs/<run>/` and splits their departures into one share per as many departures as a computing job has cores, at most one share per job the run may have running besides its own. A share is a run of departures in turn, so it holds the departures of a few cases and each job builds a case's performance tables once. The run's own job submits a job for each share and routes none itself; it then waits for the store, combines each round trip from its departures and goes on, so the cases of a later wave, such as the next round of the rig size search, are handed out once the data they read exist. The run folder that comes out is the one a workstation writes: one start time, one commit, one record.

Every job asks for the same wall time, and a run longer than that carries on by itself. Each run job queues a successor that starts once it ends, and cancels it when the run finishes or fails; a run job ended at its wall time leaves the successor to resume the run from the case store, taking over the computing jobs still running rather than submitting them again. A computing job ended at its wall time or by a node fault loses only the departures it was routing: the run submits it again, and it routes only what is still missing. Once `retries` launches in a row of a share stored nothing, the run stops with an error naming every departure still missing; once more run jobs in a row than `retries` found the run with no step done and no departure stored since the one before, as a run job the cluster kills for its memory would, the run stops queueing successors. Submitting the run again resumes it: it computes nothing that is stored, and hands out the rest.

A job computing round trips loads only what routing needs, without the plotting packages. On the box, on 4 threads, a job had loaded it 14 seconds after Julia started and stored its first departure, of the bare 140 m ship, 35 seconds after: 11 seconds setting up the case's routing, its performance tables and the rig's compiled code, and 11 routing the departure. Each further case takes 8 to 12 seconds to set up, once per job. A kite whose flight-pattern table is not yet in `output/pattern_tables/` builds it first, 6 minutes on 4 cores for a 3,200 m² kite, and every later job reads it from there. A job's share holds about one departure per core, so a job stores nothing unless its wall time outlasts the longest departure of its share. On the box a class case with a kite took 8 minutes on one core in a draft (2 departures) and 48 minutes on average in a final run (12 departures), about 4 minutes a departure. `bin/cluster estimate`, run inside a job, gives these times on the cluster's own processor.

Every cluster setting is in `scripts/cluster.toml`: the account and partition (DelftBlue's research account `research-ae-fpt` on `compute-p2` by default), the cores and memory per core of the run's own job and of each computing job, the wall time of every job, how many jobs run at once, the run's own included, and the retries. A job asks for a quarter of a `compute-p2` node or less, so the scheduler can start it in the gaps a busy cluster leaves rather than wait for a whole node. The run's own job has 8 cores at 3000M each: it hands out the round trips, routes the batches too small to hand out, and draws the figures; a whole draft run in one process peaked at 12.2 GB on 12 threads. A computing job has 16 cores at 800M each, 12.5 GB: on the box's ERA5 weather, a job routing the largest kite on the Megamax container ship peaked at 2.8 GB on 4 threads, 5.2 to 5.9 GB on 16 whether it routed 2, 8 or 16 cases at once, and 7.4 GB on 32. Where the cluster limits the cores of all running jobs together, run one job of all of them, `jobs = 1` with `run_cores` that many, which computes every round trip itself. All jobs of a run use the one partition, so one processor model computes the whole run. A final run takes only round trips computed on the processor it runs on; a draft takes them from any machine, so a draft may mix round trips from a workstation and from the cluster.

### Setting it up once, on a DelftBlue login node

Compute nodes have no internet, so Julia, the packages and the weather are fetched on a login node. `bin/delftblue_setup` does all of it: juliaup, the repository on `/scratch` (5 TB, but cleared of old files, so copy the results back after each run), the packages, and the weather through `bin/weather` from public stores. It resumes where it stopped and runs at the lowest CPU priority on 4 threads, so the login node stays usable; run it inside `tmux`, since the weather takes hours.

A draft and a final run read five weather folders under `era5/atlantic_wide/`, 14 GB together: the ERA5 wind and wave series (1.2 GB), the ERA5 wind speed aloft (0.9 GB, from 16 GB of pressure levels), their climate means (8 MB), and the GEFSv12 control forecast of every day with its bias and blend weights (12 GB). On 4 cores the packages took 13 minutes, the ERA5 series 8, the climate means 10, and the forecast about 29 seconds per day of waves and 11 of wind, some 12 hours for its 1096 days. The forecast ensemble members and the GEFS v11 forecasts that the box also holds are read only by the method studies of the forecast, not by a paper run, so they are not fetched; nor is the box's case store, since a run routes what it does not find there. `bin/weather` ends with `scripts/check_weather.jl`, which hashes each of the 48 files against `data/weather_sha256.toml`, the box's, and names every file missing or different. Delete such a file's folder and run `bin/weather` again.

```bash
ssh <netid>@login.delftblue.tudelft.nl   # from outside TU Delft's network, connect eduVPN first
tmux
curl -fsSL https://raw.githubusercontent.com/1-Bart-1/WindShipOpt.jl/main/bin/delftblue_setup | bash
exec bash -l   # puts julia on your PATH
```

Jobs are charged to the research account `research-ae-fpt` (faculty AE, department FPT): a job may run up to 120 hours, and DelftBlue's documentation says up to 64 jobs of one user run at once. The run asks for 256 jobs, about the 4,096 cores of 64 whole nodes, of 1 hour each: short, small jobs pass the queue much sooner, jobs past the cluster's limit wait in the queue until others end, and the run carries on past its wall time by itself, each job ended at it losing only the departures it was routing. Without a research account, set `account = "innovation"` and `jobs = 4`: 4 jobs at once, and a draft and a final run started together share those 4. The setup lists your accounts at its end. Commit any change to `scripts/cluster.toml`, since a final run needs a clean tree on a pushed commit. `compute-p1` has 48 cores and at most `3996M` per core, `compute-p2` 64 cores and at most `4000M`; keep each job's cores and memory per core at most the partition's, since DelftBlue takes memory per core only.

### Running

```bash
bin/cluster submit draft            # a draft run of every step; `final` for a final run
bin/cluster submit draft classes    # or only the steps named
bin/cluster status                  # jobs queued, and what the latest run of each fidelity has done
```

`bin/cluster estimate [cores]` prints what a final and a draft run take, in core hours and in days on the cluster's jobs, on one job, and on a workstation of `cores` cores (20 by default). It takes the cases of each step from the finished draft run with the most steps, scales them to each fidelity's departures, and prices them at the core seconds per departure of a sample of round trips it times on the machine it runs on: one case of each ship class with each rig, and the 140 m e-ammonia ship to Guadeloupe with each rig, with perfect foresight and sailed live. The sample takes some hours on every core it is given, so time it on a workstation or inside a job (`srun --account=<account> --partition=<partition> --cpus-per-task=64 --time=8:00:00 bin/cluster estimate`), never on a login node. It is kept in `output/estimates/` per round-trip code and processor and timed again only when either changes.

`status` lists the jobs, each run's steps done and still to do, and for each batch how many of its departures are stored. The run's log is `output/slurm/run-<job>.log` and each job's log sits beside its batch in `output/jobs/<run>/`. A run that stopped, at its wall time or naming the departures still missing, is finished by submitting it again with the same command. Keep the run on GitHub with `bin/runs push <run> <netid>@login.delftblue.tudelft.nl:/scratch/<netid>/WindShipOpt.jl` from a laptop or the box, after the run and now and then during it ([Keeping a run on GitHub](#keeping-a-run-on-github)); nothing on the cluster signs in to GitHub. Pull on the cluster before submitting a final run, so it runs the commit you mean.
