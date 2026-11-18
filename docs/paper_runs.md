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

Every job asks for the same wall time, and a run longer than that carries on by itself. Each run job queues a successor that starts once it ends, and cancels it when the run finishes or fails; a run job ended at its wall time leaves the successor to resume the run from the case store, taking over the computing jobs still running rather than submitting them again. A computing job ended at its wall time or by a node fault loses only the round trips it was computing: the run submits it again, and it computes only what is still missing. Once `retries` launches in a row of a share stored nothing, the run stops with an error naming every case still missing. Submitting the run again resumes it: it computes nothing that is stored, and hands out the rest.

Every cluster setting is in `scripts/cluster.toml`: the account and partition, which you must set, the cores and memory of each job, the wall time of every job, how many jobs run at once, the run's own included, and the retries. Where the cluster limits the cores of each job, run `jobs` jobs of the most cores allowed; where it limits the cores of all running jobs together, run one job of all of them, `jobs = 1`, which computes every round trip itself. All jobs of a run use the one partition, so one processor model computes the whole run. A final run takes only round trips computed on the processor it runs on; a draft takes them from any machine, so a draft may mix round trips from a workstation and from the cluster.

### Setting it up once, on a DelftBlue login node

Compute nodes have no internet, so Julia and the packages are installed on a login node. The commands below keep the repository on `/scratch`, which holds 5 TB but is cleared of old files, so copy the results back after each run.

```bash
ssh <netid>@login.delftblue.tudelft.nl
curl -fsSL https://install.julialang.org | sh -s -- --yes   # juliaup, in your home
source ~/.bashrc && juliaup add 1.12
cd /scratch/$USER && git clone https://github.com/1-Bart-1/WindShipOpt.jl && cd WindShipOpt.jl
./bin/install -y                                            # installs and precompiles the packages
sacctmgr list user $USER withassoc format='user%-20,account%-45'   # your accounts
```

Set `account` (on DelftBlue `research-<faculty>-<department>`; without one a job is charged to `innovation`, limited to 24 hours and 4 jobs) and `partition` (`compute-p1`: 48 cores, at most `3996M` per core; `compute-p2`: 64 cores, at most `4000M`) in `scripts/cluster.toml`, keeping `cores` at most the partition's cores per node, and commit them, since a final run needs a clean tree on a pushed commit. Then copy the weather from the machine that has it:

```bash
rsync -a era5/ <netid>@login.delftblue.tudelft.nl:/scratch/<netid>/WindShipOpt.jl/era5/
```

### Running

```bash
bin/cluster submit draft            # a draft run of every step; `final` for a final run
bin/cluster submit draft classes    # or only the steps named
bin/cluster status                  # jobs queued, and what the latest run of each fidelity has done
```

`bin/cluster estimate [cores]` prints what a final and a draft run take, in core hours and in days on the cluster's jobs, on one job, and on a workstation of `cores` cores (20 by default). It takes the cases of each step from the latest finished draft run, scales them to each fidelity's departures and rounds of the rig size search, and prices them at the core seconds per departure of a sample of round trips it times on the machine it runs on: one case of each ship class with each rig, and the 140 m e-ammonia ship to Guadeloupe with each rig, with perfect foresight and sailed live. The sample takes some hours; it is kept in `output/estimates/` per round-trip code and processor and timed again only when either changes.

`status` lists the jobs, each run's steps done and still to do, and for each batch how many of its round trips are stored. The run's log is `output/slurm/run-<job>.log` and each job's log sits beside its batch in `output/jobs/<run>/`. A run that stopped, at its wall time or naming the cases still missing, is finished by submitting it again with the same command. Bring the run and the case store home with `rsync -a <netid>@login.delftblue.tudelft.nl:/scratch/<netid>/WindShipOpt.jl/output/ output/`. Pull on the cluster before submitting a final run, so it runs the commit you mean.
