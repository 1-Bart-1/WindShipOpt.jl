# What the router does for speed

The paper describes the router's method and the approximations that change its answer. This page holds the rest: what the code does only to reach that answer sooner, why each is safe, and what the settings cost to run. The settings themselves are `RouterSettings` in `src/routing.jl` and the grids of the paper's table of grids, solver settings and constants. Every figure here is from development runs on the 12 development departures of the 140 m e-ammonia ship to Guadeloupe unless another case is named, on code of 14 and 15 November 2026 (commits 4c05b87 to 2b0e5e5) or earlier, so read them as guidance for the next change and measure again.

## The performance table

The router needs the fuel power of the ship models millions of times, so `PerformanceTable` in `src/performance.jl` solves each rig's best setting once per cell and the router reads the result: over speed through the water, true wind speed at 10 m height, true wind angle and the waves' added resistance, with the rig at its best setting and, for a kite, stowed. The heave and pitch of the launch mast behind the kite's extra launch wind in a sea are tabulated the same way, per metre of significant wave height over speed, peak period and heading. The grids are the paper's; they are the only way the tables change a result.

## Skipping states by the cost to go

A coarser backward programme (`CostToGo` in `src/routing.jl`) estimates the cost from each node and aloft state to the destination on time knots 24 h apart. The forward programme skips any state or edge whose cost so far plus this estimate exceeds the estimate at departure by more than 3 %, repeats at 6 % if its best passage ends above that limit or it finds none, and then searches all states. The paper states the rule and its measured effect on the savings. How the settings were chosen:

- **Knot spacing.** The estimate interpolates linearly in time between its knots, so it cannot time a passage to a spell of good wind. On the worst of 36 legs it reads 23 % high for a kite and 22 % for rotors with knots 48 h apart, and 15 % and 10 % at 24 h; finer weather samples leave that unchanged and more speeds change it by about two points. Averaged over those legs it reads high by 6.5 % for a kite, 5.6 % for rotors, 2.3 % for wing sails and 1.1 % without a rig at 48 h. How far the cost to go departs on average from a straight line between knots ranks the rigs nearly the same way, at 1.9 % for a kite, 2.4 % for rotors, 1.3 % for wing sails and 0.7 % without a rig, but it explains less than half of the difference between legs; the rest, which leaves a kite reading 2.6 % high on average even with knots 6 h apart, is not traced. Knots 12 h and 6 h apart read closer still but lost one rotor case 0.44 points of cost saving, so the spacing stops at 24 h.
- **Margins.** Against a search of all states on 24 cases (two ships on three routes, bare and with each rig, at stages 360 nmi and 180 nmi apart), the settings in use leave the wing sails' cost saving no lower, the rotors' at most 0.01 points lower and the ship without a rig unchanged, at about 30 % more run time than knots 48 h apart with the kite searched within 10 %, then 20 %, which lost up to 0.27 points.
- **One arrival per state for a kite.** The kite was first checked at margins of 20 %, then 40 %, keeping an arrival with the kite up and one with it down per state, and lost nothing against the search of all states. Keeping one per state, the kite up counting as cheaper by the cost of a launch, at the margins of the other rigs, moves the kite's cost saving against that search by −0.19 ± 0.35 points on the 12 development departures and by at most 0.35 points on any of the five kite cases of three routes and two ships, at two thirds of the run time. Of that time saving the rule gives 6 % at equal margins, and keeping both states at 3 % moves the kite's saving by at most 0.23 points.
- **Rejected.** Taking the search limit from the best cost on the next coarser corridor lost up to 0.94 points on the kite at up to twice the run time. Two cheaper ways of discarding states, dropping an arrival later and more expensive than another and stopping at the first speed that costs more, lost 2 to 5 points of cost saving, because a later, more expensive arrival often meets better weather.

## What the grid costs to run

The paper's convergence table gives the change of the cost saving on each grid against the reference. The computing time of one rig's 12 round trips on each, in CPU seconds on a shared machine, so ratios under about 1.2 are not firm:

| Stages, rows [nmi]                           | CPU [s] |
| -------------------------------------------- | ------: |
| 240, 60, time steps 4 times as long          |     160 |
| 120, 30, time steps twice as long            |     359 |
| 60, 15, far rows every eighth                |     914 |
| 30, 7.5, far rows every eighth               |    2257 |
| 60, 15                                       |    1972 |
| 60, 15, time bins halved                     |    2926 |
| 60, 7.5, far rows every eighth               |    2216 |
| 45, 11.25                                    |    2199 |
| 45, 11.25, graded, near 480 nmi              |    2124 |
| 45, 11.25, graded, every second row at first |    1428 |
| 45, 11.25, graded: the results               |     919 |
| 240, 60, whole corridor                      |    3391 |
| 30, 7.5, steps halved: the reference         |   13539 |

Of the grids that meet the paper's standard (each rig's saving within 3 points of the reference and the gap between two rigs within 1 point), the grid of the results is the fastest tried. The reference takes 15 times its computing time. Halving the rows alone, to 7.5 nmi, meets the standard narrowly at more than twice the time. Keeping every fourth row to the end of each plan, rather than half as many each time the distance ahead doubles, takes 2.4 times the time; keeping every stage and row for the first 480 nmi, or every second row at first, 1.6 to 2.3 times. The search of the whole corridor at once on stages 240 nmi apart takes 3.7 times the time of the results. Against the check grid of stages 30 nmi and rows 7.5 nmi apart at the time steps of the results, the plan that keeps every fourth row to the end takes more than twice the time of the graded plan. A draft on stages 240 nmi apart and half the departures takes about as long as a draft on the grid of the results with one in six of them.

## Planning on forecasts

- Sailed live, a ship values the passage beyond the current edge by the backward estimate of the cost to go. Taking that estimate from an earlier plan beyond four days, instead of making it all on each day's forecast, runs in under half the time on two ships and five routes with four departures each, and in under a third on the 12 development departures; the paper gives what it does to the savings.
- Valuing by the backward estimate over the whole corridor takes five times the run time of sailing live by the plan's own cost. The two faster ways, the plan's own cost and the estimate made only on the coarse planning grid, move the gap between kite and rotors by more than the one point to which every faster method is held, as the paper's appendix on planning on forecasts gives.
- Planning on the blend of forecast and climatology takes the same run time as planning on the corrected forecast with another year's weather beyond it.

## What a routing process holds in memory

- **States of the search.** The forward programme has a state for every row of the corridor, time bin, kite state and stage, of 47 bytes each. Held whole that is 672 MB for a plan of the route to Guadeloupe (429 rows, 401 time bins of 3 h up to the longest passage of 1200 h, 22 stages) on every thread that routes, and up to 3.7 GB where a search takes a whole corridor. A pass reaches few of them, since the cost to go keeps it near the best passage and no passage takes 1200 h, so `RouteWorkspace` in `src/routing.jl` holds the states by row, the lateral nodes of one time bin, kite state and stage, and only the rows a pass wrote to: about 65 MB per thread on that route, with the same routes to the last bit at the same run time.
- **Wave directions.** The east and north components of the wave direction, which the weather interpolates, are files beside the ERA5 directions, written on first use and memory-mapped like the rest of the weather, so the processes on a machine share them. Computed in each process they took 676 MB of it, as they still do where the weather folder cannot be written to.

Routing the three ships of the development case on 4 threads, a process holds 2.4 GB at the end, 1.0 GB of it weather and libraries shared with other processes, against 5.8 GB with the states held whole and the components computed in each process.

## Where one round trip's time goes

Profiled warm on one thread on 22 November 2026, one round trip of the development case takes 8 to 10 s with rotors and 17 to 24 s with a kite, by departure. Half of it is the final pass along the path found, which tries every speed on time bins of a quarter hour, and the search and the cost to go take about a quarter each. In all three the time goes to the points sampled along the edges. Interpolating the weather and setting the sea state on the edge's course takes 35 to 40 % of the round trip, and finding the speed the engines hold at each point 35 % with rotors and 45 % with a kite. A speed the engines cannot hold is tried from the commanded speed down, 2.0 speeds per point on average with rotors and 3.7 with a kite. The weather reads are bound by arithmetic, not by memory: points near the last one, as the router reads them, take 170 ns for wind and waves, against 370 ns at random points, so storing the variables of a cell side by side would gain little. The lookup of the performance table already works on its four values at once.

Two things the profile showed are done once now, and give the same routes to the last bit on 54 round trips (four rigs to Guadeloupe over the 12 departures, the kite and the rotors to Houston over three):

- **The land check of the weather grid** found the nearest cell by building two arrays the length of the grid's axes on every call, and checked the small islands first. It now steps to the nearest cell and reads the grid before the islands. Re-planning checks every edge of its grid against land, so this was a tenth of a round trip with rotors, and 2.4 GB of the 2.75 GB a round trip allocated.
- **The fuels at an edge's first point** are kept for every speed commanded from that node at that time, with the kite aloft and down, where the same speed was looked up there again for each. That leaves a kite 12 % fewer lookups of the table per round trip and rotors 6 %.

A round trip now allocates 0.35 GB in 4 thousand allocations, against 2.75 GB in 2.85 million. Routing the 54 round trips on 4 threads took 215 s against 283 s, with garbage collection 1 % of the time against 5 %, on a shared machine whose load changed during the runs. On one thread the gain is 5 to 10 %, too close to the noise of the shared machine to state more firmly.

The arithmetic at each sampled point is lighter too, which moves results only by rounding: on the 36 development round trips no cost changes by more than 7 parts in 10^15. A lookup in the performance table finds its interval from a list of equal steps no wider than the narrowest interval and multiplies by the interval's reciprocal width, where it divided three times and walked the doubling knots of the added resistance one by one. Each routing speed keeps its propeller's constants, so the power delivered to the propeller needs no division. The weather sample multiplies by reciprocal grid spacings and divides by its weights only next to land. The kite's wind aloft takes one logarithm where it took two and searched the heights twice. The wind angle on a course takes one sine and cosine, where it took that pair twice. A speed whose table cell the engines cannot power is ruled out before the waves' added resistance is read. A leg routed with the kite now takes 0.89 times the processor time of the leg before, and one with rotors 0.93 times. These are medians of four pairs on one core of the shared machine, in the same process before and after. Allocation is unchanged.

Each pull request into `main` times a leg routed with rotors and one with a kite, as a round trip routes them, against `main` on the same runner, and the comparison is posted on the pull request (`benchmark/benchmarks.jl`, run by AirspeedVelocity.jl). The weather there is a small grid of smoothly varying wind and waves, so the times are for comparing two versions, not for the run time of the paper's cases. The test suite checks that what runs per edge and per leg does not allocate (`test/hot_path_checks.jl`).
