# Paper runs

`paper(names...; fidelity)` in `scripts/paper.jl` computes the paper's results in steps: data steps that route ships and write CSV files, then figure and table steps that read them. Each call that makes data writes a run, `output/runs/<start time>/`, with the data files and the record `run.toml`. A step reads another step's data file from the run in use, else from the latest finished run of its fidelity, this branch's first.

## What a run keeps

Every round trip a step routes is kept in the case store, `output/cases/`, which all runs share. A stored round trip is found again by its case (ship, rig, route, fuel, departures, model part), by the value of every input of `data/assumptions.yaml` it read, by the contents of every data file it read, and by the code of a round trip. That code is everything in `src/`, the data tables, the kite polars, `scripts/setup.jl`, the package manifests, the Julia version, and the definitions in the scripts that building and sailing a case reach by name. A step whose own code changed therefore rewrites its tables from the stored round trips in minutes, and a changed input routes again only the round trips that read it.

`run.toml` says for every step what made it: the commit and whether the tree was dirty, the hash of each definition its code reaches (`model` for the model files), the base value of every input it read, the content hash and run of every data file it read, and for its round trips how many there are, which commit and processor computed them, and how many it kept from older code. `cases/<step>.csv` in the run lists each round trip of the step by its labels, with its case-store directory, the commit and tree that computed it, its round-trip code and its processor, so a sliced draft says which class, route or rig rests on which commit.

## Where a run is kept

Every run is also kept on GitHub, so that no run lives only on the machine that ran it. Each commit has one release, a prerelease tagged `run-<commit>`, holding one archive per fidelity, `draft.tar.gz` and `final.tar.gz`. The archive holds every run at that fidelity whose clean tree was at that commit, under `runs/`, and the round trips those runs use, under `cases/`. A run uploads it after each step, every 30 minutes while its round trips compute, and when it finishes; each upload replaces the archive, and the old one is deleted only once the new one is in. A run on a dirty tree or an unpushed commit is kept only on its machine, with a warning, since its code is in no commit; once the commit is pushed, the next upload goes through. Uploading uses `gh` where it is installed and signed in, and otherwise curl with a token in `GITHUB_TOKEN` (the README says how to make one). Without either, the run warns and goes on.

A run resumes from its release on any machine. Before `paper` opens a run, unless `resume=false`, it downloads the archive of the checked-out commit and fidelity and takes from it every run of this branch that is missing here, or here with fewer steps done, and every stored round trip missing here. It then resumes as it would locally: the run must be on this branch, and a stored round trip counts only where it was computed by the current code from the same inputs. A run started at another commit is not fetched.

To read a run's results without running anything, download its archive, which is public, and unpack it into a folder of its own:

```bash
commit=<the commit>
mkdir -p kept && curl -fL https://github.com/1-Bart-1/WindShipOpt.jl/releases/download/run-$commit/draft.tar.gz | tar -xz -C kept
ls kept/runs   # the data files and run.toml of each run; kept/cases holds its round trips
```

The release list on GitHub, or `gh release list`, shows which commits have kept runs.

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

`only` names labels of the step's cases and the values to compute; a step none of whose cases carries them stops with an error rather than recompute nothing. Cases outside it take the latest stored round trip of any code; `run.toml` counts them under `older_cases`, and `paper_status` lists the step as out of date until a run computes them with the current code. A final run takes no `only`.

## Final runs

A final run needs a clean tree on a pushed commit, and it takes from the case store only round trips computed at that commit with a clean tree, so every part of it comes from one commit. `paper_status(; fidelity=:final)` prints the commit of each step's data and ends by saying whether every step and round trip comes from one clean commit, naming the commits where not.

## Runs on a Slurm cluster

A run can hand its round trips to a Slurm cluster such as TU Delft's DelftBlue. The run itself is one job running `paper`, as on a workstation. Each time a step has more round trips than the job has cores, the run writes them to a batch file under `output/jobs/<run>/` and splits them into one share per as many round trips as a job has cores, every `k`-th round trip to the `k`-th share, at most one share per job the run may have running. The run's own job computes the first share and submits a job for each other one; it then waits for the store and goes on, so the cases of a later wave, such as the next round of the rig size search, are handed out once the data they read exist. The run folder that comes out is the one a workstation writes: one start time, one commit, one record.

Every job asks for the same wall time, and a run longer than that carries on by itself. Each run job queues a successor that starts once it ends, and cancels it when the run finishes or fails; a run job ended at its wall time leaves the successor to resume the run from the case store, taking over the computing jobs still running rather than submitting them again. A computing job ended at its wall time or by a node fault loses only the round trips it was computing: the run submits it again, and it computes only what is still missing. Once `retries` launches in a row of a share stored nothing, the run stops with an error naming every case still missing; once more run jobs in a row than `retries` found the run with no step done and no round trip stored since the one before, as a run job the cluster kills for its memory would, the run stops queueing successors. Submitting the run again resumes it: it computes nothing that is stored, and hands out the rest.

Every cluster setting is in `scripts/cluster.toml`: the account and partition (DelftBlue's `innovation` account on `compute-p2` by default), the cores and memory of each job, the wall time of every job, how many jobs run at once, the run's own included, and the retries. Where the cluster limits the cores of each job, run `jobs` jobs of the most cores allowed; where it limits the cores of all running jobs together, run one job of all of them, `jobs = 1`, which computes every round trip itself. All jobs of a run use the one partition, so one processor model computes the whole run. A final run takes only round trips computed on the processor it runs on; a draft takes them from any machine, so a draft may mix round trips from a workstation and from the cluster.

### Setting it up once, on a DelftBlue login node

Compute nodes have no internet, so Julia, the packages and the weather are fetched on a login node. `bin/delftblue_setup` does all of it: juliaup, the repository on `/scratch` (5 TB, but cleared of old files, so copy the results back after each run), the packages, and the weather through `bin/weather` from public stores. It resumes where it stopped and runs at the lowest CPU priority on 4 threads, so the login node stays usable; run it inside `tmux`, since the weather takes hours.

A draft and a final run read four weather folders under `era5/atlantic_wide/`, 13 GB together: the ERA5 wind and wave series (1.2 GB), their climate means (8 MB), and the GEFSv12 control forecast of every day with its bias and blend weights (12 GB). On 4 cores the packages took 13 minutes, the ERA5 series 8, the climate means 10, and the forecast about 29 seconds per day of waves and 11 of wind, some 12 hours for its 1096 days. The forecast ensemble members and the GEFS v11 forecasts that the box also holds are read only by the method studies of the forecast, not by a paper run, so they are not fetched; nor is the box's case store, since a run routes what it does not find there. `bin/weather` ends with `scripts/check_weather.jl`, which hashes each of the 48 files against `data/weather_sha256.toml`, the box's, and names every file missing or different. Delete such a file's folder and run `bin/weather` again.

```bash
ssh <netid>@login.delftblue.tudelft.nl   # from outside TU Delft's network, connect eduVPN first
tmux
curl -fsSL https://raw.githubusercontent.com/1-Bart-1/WindShipOpt.jl/main/bin/delftblue_setup | bash
exec bash -l   # puts julia on your PATH
```

Without a project account, jobs are charged to `innovation`: 24 hours each and 4 at once in total, so a draft and a final run started together share those 4. With a project account (`research-<faculty>-<department>`, listed at the end of the setup), set it as `account` in `scripts/cluster.toml` and commit it, since a final run needs a clean tree on a pushed commit. `compute-p1` has 48 cores and at most `3996M` per core, `compute-p2` 64 cores and at most `4000M`; keep `cores` at most the partition's.

### Running

```bash
bin/cluster submit draft            # a draft run of every step; `final` for a final run
bin/cluster submit draft classes    # or only the steps named
bin/cluster keep                    # in tmux: upload the runs to GitHub while their jobs run
bin/cluster status                  # jobs queued, and what the latest run of each fidelity has done
```

`bin/cluster estimate [cores]` prints what a final and a draft run take, in core hours and in days on the cluster's jobs, on one job, and on a workstation of `cores` cores (20 by default). It takes the cases of each step from the finished draft run with the most steps, scales them to each fidelity's departures and rounds of the rig size search, and prices them at the core seconds per departure of a sample of round trips it times on the machine it runs on: one case of each ship class with each rig, and the 140 m e-ammonia ship to Guadeloupe with each rig, with perfect foresight and sailed live. The sample takes some hours on every core it is given, so time it on a workstation or inside a job (`srun --account=<account> --partition=<partition> --cpus-per-task=64 --time=8:00:00 bin/cluster estimate`), never on a login node. It is kept in `output/estimates/` per round-trip code and processor and timed again only when either changes.

`status` lists the jobs, each run's steps done and still to do, and for each batch how many of its round trips are stored. The run's log is `output/slurm/run-<job>.log` and each job's log sits beside its batch in `output/jobs/<run>/`. A run that stopped, at its wall time or naming the cases still missing, is finished by submitting it again with the same command. Pull on the cluster before submitting a final run, so it runs the commit you mean.

Compute nodes reach no internet, so the login node does the run's talking to GitHub. `submit` first fetches the run kept in the release of the checked-out commit, so a run whose `/scratch` was cleared resumes from there. `bin/cluster keep`, left running in `tmux` on the login node, uploads the latest run of each fidelity every 30 minutes while jobs of a paper run are queued or running, and once more when they have ended; the run jobs try too, and warn when they cannot. Any machine then has the run as [Where a run is kept](#where-a-run-is-kept) says, and `rsync -a <netid>@login.delftblue.tudelft.nl:/scratch/<netid>/WindShipOpt.jl/output/ output/` still copies the whole of `output/`.
