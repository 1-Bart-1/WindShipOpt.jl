"""Print the numbers of the design, route, season, class, forecast, base kite, screening
and component studies, from the CSV files of the latest finished run paper.jl made in
output/runs/. Run: python3 -I scripts/paper_numbers.py [section ...], with the section
names of SECTIONS; all sections without one."""
import csv
import os
import sys
import tomllib
from collections import defaultdict

RUNS = os.path.join(os.path.dirname(__file__), "..", "output", "runs")


def latest_finished_run():
    """Directory of the latest finished run in RUNS, preferring final to draft fidelity."""
    finished = {}
    for name in sorted(os.listdir(RUNS)):
        path = os.path.join(RUNS, name, "run.toml")
        if os.path.exists(path):
            with open(path, "rb") as file:
                record = tomllib.load(file)
            if record["finished"]:
                finished[record["fidelity"]] = os.path.join(RUNS, name)
    return finished.get("final") or finished["draft"]


RESULTS = latest_finished_run()
DRIVES = ("vlsfo", "methanol", "hydrogen")
RIGS = ("kite", "wings", "rotors")
RIG_COLUMNS = (("kite", "kite_area"), ("wings", "wing_area"), ("rotors", "rotor_area"))


def table(name):
    """Rows of the CSV file `name` in RESULTS, or none where it is missing."""
    path = os.path.join(RESULTS, name)
    return list(csv.DictReader(open(path))) if os.path.exists(path) else []


def saving(cost, reference):
    """Cost saving [%] of `cost` against `reference`."""
    return 100 * (1 - cost / reference)


def designs_summary():
    """Best size and saving per rig on the design grid, its scenarios and the share of
    the fuel premium each rig closes."""
    rows = table("designs.csv")
    bare = {}
    for r in rows:
        if float(r["kite_area"]) + float(r["wing_area"]) + float(r["rotor_area"]) == 0:
            bare[(r["scenario"], r["drive"], r["length"])] = float(r["cost"])
    print("== design grid (Guadeloupe): best size and saving per rig")
    for drive in DRIVES:
        for length in sorted({r["length"] for r in rows}, key=float):
            reference = bare.get(("base", drive, length))
            if reference is None:
                continue
            line = [f"{drive:8s} {length:>4s} m bare {1e3 * reference:.2f}"]
            for rig, column in RIG_COLUMNS:
                options = [r for r in rows if r["scenario"] == "base" and
                           r["drive"] == drive and r["length"] == length and
                           float(r[column]) > 0]
                if not options:
                    continue
                best = min(options, key=lambda r: float(r["cost"]))
                line.append(f"{rig} {float(best[column]):.0f} m2 "
                            f"{saving(float(best['cost']), reference):.1f}%"
                            f" fly {float(best['flight_share']):.2f}")
            print(" | ".join(line))
    print("== scenarios")
    for r in rows:
        if r["scenario"] == "base":
            continue
        key = ("carbon" if r["scenario"] == "carbon" else "base", r["drive"],
               r["length"])
        reference = bare.get(key)
        if reference:
            area = float(r["kite_area"]) + float(r["wing_area"]) + float(r["rotor_area"])
            print(f"{r['scenario']:22s} {r['drive']:8s} {r['length']:>4s} area {area:5.0f}"
                  f" AR {r['kite_aspect_ratio']} saving "
                  f"{saving(float(r['cost']), reference):.1f}%")
    print("== premium of e-methanol and hydrogen over VLSFO closed by the best rig")
    for drive in DRIVES[1:]:
        for length in sorted({r["length"] for r in rows}, key=float):
            fossil = bare.get(("base", "vlsfo", length))
            green = bare.get(("base", drive, length))
            if not fossil or not green:
                continue
            line = [f"{drive:8s} {length:>4s} m premium {100 * (green / fossil - 1):.0f}%"]
            for rig, column in RIG_COLUMNS:
                options = [float(r["cost"]) for r in rows if r["scenario"] == "base" and
                           r["drive"] == drive and r["length"] == length and
                           float(r[column]) > 0]
                if options:
                    closed = (green - min(options)) / (green - fossil)
                    line.append(f"{rig} {100 * closed:.0f}%")
            print(" | ".join(line))


def routes_summary():
    """Saving of the better of the two sizes of each rig per route, drive and length."""
    rows = table("routes.csv")
    print("== routes: best saving per rig")
    bare = {(r["route"], r["drive"], r["length"]): float(r["cost"]) for r in rows
            if r["rig"] == "none"}
    for (route, drive, length), reference in sorted(bare.items()):
        line = [f"{route:10s} {drive:8s} {length:>4s}"]
        for rig in RIGS:
            options = [float(r["cost"]) for r in rows if r["route"] == route and
                       r["drive"] == drive and r["length"] == length and r["rig"] == rig]
            if options:
                line.append(f"{rig} {saving(min(options), reference):.1f}%")
        print(" | ".join(line))


def seasons_summary():
    """Saving in winter (October to March) and summer (April to September) of the best size
    over the year of each rig on the 140 m e-methanol ship per route, with the kite's flight
    share and the departures of each half year."""
    best = {}
    for r in table("routes.csv"):
        if r["drive"] == "methanol" and float(r["length"]) == 140:
            key = (r["route"], r["rig"])
            if key not in best or float(r["cost"]) < float(best[key]["cost"]):
                best[key] = r
    halves = defaultdict(list)
    for r in table("route_departures.csv"):
        chosen = best.get((r["route"], r["rig"]))
        if r["drive"] == "methanol" and chosen and r["area"] == chosen["area"] and \
                float(r["length"]) == 140:
            half = "winter" if int(r["date"][5:7]) in (10, 11, 12, 1, 2, 3) else "summer"
            halves[(r["route"], r["rig"], half)].append(r)
    print("== seasons: 140 m e-methanol, best size over the year, saving winter / summer")
    for route in sorted({key[0] for key in best}):
        line = [f"{route:10s}"]
        for half in ("winter", "summer"):
            bare = mean([float(r["cost"]) for r in halves[(route, "none", half)]])
            line.append(f"{half} n={len(halves[(route, 'none', half)])}")
            for rig in RIGS:
                rows = halves[(route, rig, half)]
                if rows:
                    cost = mean([float(r["cost"]) for r in rows])
                    text = f"{rig} {saving(cost, bare):.1f}%"
                    if rig == "kite":
                        share = mean([float(r["flight_share"]) for r in rows])
                        text += f" (flies {100 * share:.0f}%)"
                    line.append(text)
        print(" | ".join(line))


def class_cases():
    """Per (class, drive, route): the cost without a rig, and per rig the cheapest row
    and the largest area tried, which is the deck capacity or the kite search cap."""
    cases = defaultdict(lambda: {"bare": None, "best": {}, "largest": {}})
    for r in table("classes.csv"):
        case = cases[(r["class"], r["drive"], r["route"])]
        if r["rig"] == "none":
            case["bare"] = float(r["cost"])
            continue
        best = case["best"].get(r["rig"])
        if best is None or float(r["cost"]) < float(best["cost"]):
            case["best"][r["rig"]] = r
        case["largest"][r["rig"]] = max(case["largest"].get(r["rig"], 0), float(r["area"]))
    return {key: case for key, case in cases.items() if case["bare"] is not None}


def mean(values):
    """Arithmetic mean of `values`."""
    return sum(values) / len(values)


def classes_summary():
    """Saving and best size per class and rig, and the means over classes and routes."""
    cases = class_cases()
    print("== classes: saving and best size per rig, mean (range) over routes")
    for drive in DRIVES:
        savings = defaultdict(list)
        for (name, case_drive, route), case in sorted(cases.items()):
            if case_drive != drive:
                continue
            for rig, best in case["best"].items():
                savings[(rig, name)].append(saving(float(best["cost"]), case["bare"]))
                savings[(rig, route)].append(savings[(rig, name)][-1])
                savings[(rig, "area", name)].append(float(best["area"]))
        names = sorted({key[0] for key in cases})
        for name in names:
            print(f"{drive:8s} {name:28s} | " + " | ".join(
                f"{rig} {mean(savings[(rig, name)]):.1f}% ({min(savings[(rig, name)]):.1f}"
                f" to {max(savings[(rig, name)]):.1f}) "
                f"{mean(savings[(rig, 'area', name)]):.0f} m2" for rig in RIGS))
        for rig in RIGS:
            class_means = [mean(savings[(rig, name)]) for name in names]
            routes = sorted({key[2] for key in cases})
            print(f"{drive:8s} {rig:6s} mean over classes {mean(class_means):.1f}%; "
                  "by route " + ", ".join(f"{route} {mean(savings[(rig, route)]):.1f}"
                              for route in routes))
        best = {name: max(RIGS, key=lambda rig: mean(savings[(rig, name)]))
                for name in names}
        print(f"{drive:8s} best rig per class: " + ", ".join(
            f"{name} {rig} {mean(savings[(rig, name)]):.1f}" for name, rig in best.items()))


def winners_summary():
    """Rig with the largest saving per class and route, counted by route and class."""
    cases = class_cases()
    print("== winners: rig with the largest saving per class and route where one pays")
    for drive in DRIVES:
        wins, losers, best_savings = defaultdict(list), [], []
        for (name, case_drive, route), case in sorted(cases.items()):
            if case_drive != drive:
                continue
            rig, best = min(case["best"].items(), key=lambda item: float(item[1]["cost"]))
            best_saving = saving(float(best["cost"]), case["bare"])
            best_savings.append(best_saving)
            if best_saving > 0:
                wins[rig].append((name, route))
            else:
                losers.append(f"{name}/{route} ({rig} {best_saving:.1f}%)")
        print(f"{drive}: {len(best_savings)} cells, best saving "
              f"{min(best_savings):.1f} to {max(best_savings):.1f}%, no rig pays in "
              f"{len(losers)} {losers}")
        for rig, cells in wins.items():
            for position, label in ((1, "route"), (0, "class")):
                counts = defaultdict(int)
                for cell in cells:
                    counts[cell[position]] += 1
                print(f"   {rig} {len(cells)} by {label}: {dict(sorted(counts.items()))}")


def sizes_summary():
    """Routes on which the best rig is the largest area tried, and the units it has."""
    cases = class_cases()
    print("== sizes: best area at the largest area tried, units of the best deck rigs")
    for drive in DRIVES:
        for rig in RIGS:
            capped, units = defaultdict(int), defaultdict(list)
            for (name, case_drive, _), case in cases.items():
                if case_drive != drive or rig not in case["best"]:
                    continue
                best = case["best"][rig]
                capped[name] += float(best["area"]) >= case["largest"][rig]
                units[name].append(int(best["units"]))
            print(f"{drive} {rig}: " + ", ".join(
                f"{name} {capped[name]}/{len(units[name])} max units {max(units[name])}"
                for name in sorted(units)))


def forecast_summary():
    """Saving of each rig with a perfect and a limited forecast."""
    print("== forecast")
    rows = table("forecast.csv")
    bare = {r["horizon_days"]: float(r["cost"]) for r in rows if r["rig"] == "none"}
    for r in rows:
        if r["rig"] != "none":
            print(f"{r['rig']:7s} horizon {r['horizon_days']:>4s} d saving "
                  f"{saving(float(r['cost']), bare[r['horizon_days']]):.1f}%")


def other_summaries():
    """Largest swings of the input screening and the effect of component prices."""
    print("== input screening: largest swings in saving per ship and rig")
    rows = table("sensitivity.csv")
    cost = {(r["ship"], r["rig"], r["input"], r["bound"]): float(r["cost"]) for r in rows}
    for ship in sorted({r["ship"] for r in rows}):
        for rig in RIGS:
            swings = []
            for (case_ship, case_rig, name, bound) in cost:
                if case_ship != ship or case_rig != rig or bound != "low":
                    continue
                keys = [(ship, case_rig, name, side) for side in ("low", "high")] + \
                       [(ship, "none", name, side) for side in ("low", "high")]
                if not all(key in cost for key in keys):
                    continue
                low = saving(cost[keys[0]], cost[keys[2]])
                high = saving(cost[keys[1]], cost[keys[3]])
                swings.append((abs(high - low), name, low, high))
            for swing, name, low, high in sorted(swings, reverse=True)[:8]:
                print(f"{ship:28s} {rig:7s} {name:32s} low {low:.1f}% high {high:.1f}%")
    print("== components (change in saving, points)")
    rows = table("components.csv")
    bare = [float(r["cost"]) for r in rows if r["rig"] == "none"]
    if bare:
        for rig in RIGS:
            base = [float(r["cost"]) for r in rows
                    if r["rig"] == rig and r["input"] == "none"]
            if not base:
                continue
            reference = saving(base[0], bare[0])
            print(f"{rig}: base saving {reference:.1f}%")
            for r in rows:
                if r["rig"] == rig and r["input"] != "none":
                    print(f"   {r['input']:30s} x{r['factor']:>4s} "
                          f"{saving(float(r['cost']), bare[0]) - reference:+.2f} pt")


def base_kite_summary():
    """Fuel and cost saving of each base kite variant, and the spread of the noise cases."""
    print("== base kite: fuel and cost saving against the ship without a rig")
    rows = table("base_kite.csv")
    bare = {r["ship"]: r for r in rows if r["variant"] == "bare"}
    savings = defaultdict(list)
    for r in rows:
        if r["variant"] == "bare":
            continue
        fuel = saving(float(r["fuel"]), float(bare[r["ship"]]["fuel"]))
        cost = saving(float(r["cost"]), float(bare[r["ship"]]["cost"]))
        print(f"{r['ship']:28s} {r['variant']:36s} fuel {fuel:6.2f}% cost {cost:6.2f}%")
        if r["variant"] == "base" or r["variant"].startswith("noise_"):
            savings[r["ship"]].append((fuel, cost))
    for ship, values in savings.items():
        fuel, cost = zip(*values)
        print(f"{ship:28s} noise spread: fuel {max(fuel) - min(fuel):.2f} "
              f"cost {max(cost) - min(cost):.2f} points")


SECTIONS = {"designs": designs_summary, "routes": routes_summary,
            "seasons": seasons_summary, "classes": classes_summary,
            "winners": winners_summary,
            "sizes": sizes_summary, "forecast": forecast_summary, "base_kite": base_kite_summary,
            "other": other_summaries}
for section in sys.argv[1:] or SECTIONS:
    SECTIONS[section]()
