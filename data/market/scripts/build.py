"""Build the port-to-partner flow table with sea distances and the tonne-km summaries.

Usage: python3 -I build.py <data/market directory>
"""
import csv, os, re, sys
from collections import defaultdict
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from seagraph import SeaDistance
from locations import PORT_OVERRIDES, AREA_DEFAULT, PARTNER_REPS, REPORTING_FALLBACK

YEAR = "2024"
CARGO = {"LBK": "liquid bulk", "DBK": "dry bulk", "LCNT": "containers", "RO_MSP": "ro-ro",
         "RO_MNSP": "ro-ro", "OTH": "other general cargo", "UNK": "unknown"}
AGGREGATES = {"TOTAL", "SSS", "DSS", "EUR", "EU27_2020", "EU28", "EUR_NEU27_2020", "EUR_NEU28", "AFR",
              "AME", "ASI_OCE", "ASI", "OCE", "CA_1_2", "US_1_2_6", "RS_ME", "EX_YU"}
UNKNOWN = {"UNK", "UNK_NSP", "OFF_NSP", "AGG_NSP"}
SIZE_EDGES = [(1e3, "<1 Mt"), (1e4, "1-10 Mt"), (5e4, "10-50 Mt"), (float("inf"), ">50 Mt")]
DIST_EDGES = [(500, "<500 km"), (1500, "500-1500 km"), (4000, "1500-4000 km"),
              (10000, "4000-10000 km"), (float("inf"), ">10000 km")]
PORT_CODE = re.compile(r"^[A-Z]{2}_[0-9][A-Z0-9]{5}$")
UK_PARTNERS = ("UK", "UK_1", "UK_9")


def size_class(kt):
    return next(label for edge, label in SIZE_EDGES if kt < edge)


def distance_class(km):
    return next(label for edge, label in DIST_EDGES if km < edge)


def parse_locode(text):
    lat, lon = text.split()
    lat_deg = int(lat[:2]) + int(lat[2:4]) / 60
    lon_deg = int(lon[:3]) + int(lon[3:5]) / 60
    return (lat_deg if lat[-1] == "N" else -lat_deg, lon_deg if lon[-1] == "E" else -lon_deg)


def load_codelist(path):
    return dict(line.rstrip("\n").split("\t")[:2] for line in open(path, encoding="utf-8"))


def port_coordinates(ports, locode_path):
    locode = {}
    for row in csv.DictReader(open(locode_path, encoding="utf-8", errors="replace")):
        if row["Coordinates"].strip():
            locode[row["Country"] + row["Location"]] = row["Coordinates"]
    coords, source = {}, {}
    for port in ports:
        if port in PORT_OVERRIDES:
            coords[port], source[port] = PORT_OVERRIDES[port], "manual"
        elif port[4:] in locode:
            coords[port], source[port] = parse_locode(locode[port[4:]]), "UN/LOCODE"
        else:
            coords[port], source[port] = AREA_DEFAULT.get(port[:4], AREA_DEFAULT["DK_0"]), "area default"
    return coords, source


def leaf_partners(partners):
    """Drop aggregates, and a country whenever its sub-areas are also present."""
    leaves = {p for p in partners if p not in AGGREGATES}
    parents = {p.split("_")[0] for p in leaves if "_" in p and p not in UNKNOWN}
    if leaves & {"UNK", "OFF_NSP", "AGG_NSP"}:
        parents.add("UNK_NSP")
    return {p for p in leaves if p not in parents or p in UNKNOWN - {"UNK_NSP"}}


def main(base):
    raw = os.path.join(base, "raw")
    rep_names = load_codelist(os.path.join(raw, "cl_rep_mar.tsv"))
    par_names = load_codelist(os.path.join(raw, "cl_par_mar.tsv"))
    flows = defaultdict(dict)          # (port, direct, cargo) -> {partner: kt}
    throughput = {}
    for row in csv.DictReader(open(os.path.join(base, "eurostat_mar_go_am_2024_2025.csv"))):
        if row["year"] != YEAR or not PORT_CODE.match(row["rep_mar"]):
            continue
        port, kt = row["rep_mar"], float(row["kt"])
        if row["par_mar"] == "TOTAL" and row["direct"] == "TOTAL" and row["cargo"] == "TOTAL":
            throughput[port] = kt
        if row["direct"] in ("IN", "OUT") and (row["cargo"] in CARGO or row["cargo"] == "TOTAL"):
            flows[(port, row["direct"], row["cargo"])][row["par_mar"]] = kt
    ports = sorted(throughput)
    coords, coord_source = port_coordinates(ports, os.path.join(raw, "locode", "code-list.csv"))
    reporting = {p[:2] for p in ports}
    ports_by_country = defaultdict(list)
    for p in ports:
        ports_by_country[p[:2]].append(p)

    # mirror weights: tonnes each reporting port q exchanges with partner country c
    mirror = defaultdict(float)
    for (port, direct, cargo), partners in flows.items():
        if cargo != "TOTAL":
            continue
        for partner, kt in partners.items():
            if partner not in AGGREGATES and partner not in UNKNOWN:
                mirror[(port, partner.split("_")[0])] += kt

    def partner_locations(port, partner):
        """[(lat, lon, weight, size class)] standing for the partner seen from `port`."""
        country = partner.split("_")[0]
        if country in reporting and partner not in UK_PARTNERS:
            candidates = [q for q in ports_by_country[country] if q != port
                          and (partner == country or q.startswith(partner))]
            weights = {q: mirror.get((q, port[:2]), 0.0) for q in candidates}
            if sum(weights.values()) == 0:
                weights = {q: throughput[q] for q in candidates}
            total = sum(weights.values())
            if total > 0:
                return [(*coords[q], w / total, size_class(throughput[q])) for q, w in weights.items() if w > 0]
        reps = PARTNER_REPS.get(partner) or PARTNER_REPS.get(country) or REPORTING_FALLBACK.get(country)
        if reps is None:
            return None
        total = sum(r[3] for r in reps)
        return [(lat, lon, w / total, "non-reporting") for _, lat, lon, w in reps]

    sea = SeaDistance()
    distance_cache = {}

    def pair_distance(port, partner):
        key = (port, partner)
        if key not in distance_cache:
            locations = partner_locations(port, partner)
            if locations is None:
                distance_cache[key] = None
            else:
                gc = sea_km = cape_km = 0.0
                classes = defaultdict(float)
                for lat, lon, w, cls in locations:
                    g, s, c = sea(coords[port], (lat, lon))
                    gc, sea_km, cape_km = gc + w * g, sea_km + w * s, cape_km + w * c
                    classes[cls] += w
                distance_cache[key] = (gc, sea_km, cape_km, dict(classes))
        return distance_cache[key]

    out_rows, checks = [], []
    for (port, direct, cargo), partners in sorted(flows.items()):
        if cargo == "TOTAL":
            continue
        for partner in sorted(leaf_partners(partners)):
            kt = partners[partner]
            if kt <= 0:
                continue
            country = partner.split("_")[0]
            dedup = 0.5 if country in reporting and partner not in UK_PARTNERS else 1.0
            dist = None if partner in UNKNOWN else pair_distance(port, partner)
            record = dict(rep_port=port, rep_name=rep_names.get(port, ""), rep_country=port[:2],
                        rep_size_class=size_class(throughput[port]), partner=partner,
                        partner_name=par_names.get(partner, ""), direction=direct,
                        cargo_code=cargo, cargo=CARGO[cargo], kt=kt, dedup_weight=dedup)
            if dist is None:
                record.update(gc_km="", sea_km="", sea_km_no_suez="", distance_class="unknown",
                            partner_size_mix="", mtkm=0.0)
            else:
                gc, sea_km, cape_km, classes = dist
                record.update(gc_km=round(gc), sea_km=round(sea_km), sea_km_no_suez=round(cape_km),
                            distance_class=distance_class(sea_km),
                            partner_size_mix=";".join(f"{k}={v:.2f}" for k, v in sorted(classes.items())),
                            mtkm=dedup * kt * sea_km / 1e3)
            out_rows.append(record)
        leaf_sum = sum(partners[p] for p in leaf_partners(partners))
        if "TOTAL" in partners:
            checks.append((port, direct, cargo, partners["TOTAL"], leaf_sum))

    write_csv(os.path.join(base, "eurostat_port_partner_flows_2024.csv"), out_rows)
    write_csv(os.path.join(base, "port_throughput_2024.csv"), [
        dict(rep_port=p, name=rep_names.get(p, ""), country=p[:2], lat=coords[p][0], lon=coords[p][1],
             coord_source=coord_source[p], throughput_kt=throughput[p], size_class=size_class(throughput[p]))
        for p in sorted(ports, key=lambda p: -throughput[p])])
    bad = [c for c in checks if abs(c[3] - c[4]) > max(1.0, 0.01 * c[3])]
    print(f"{len(out_rows)} flow rows; {len(bad)} of {len(checks)} groups where leaf sum != TOTAL")
    for c in bad[:10]:
        print("  ", c)
    summarise(base, out_rows)


def write_csv(path, rows):
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def share_table(rows, key_fn, label_names):
    tonnes, tkm = defaultdict(float), defaultdict(float)
    for row in rows:
        for key, weight in key_fn(row):
            tonnes[key] += weight * row["dedup_weight"] * row["kt"]
            tkm[key] += weight * row["mtkm"]
    total_t, total_tkm = sum(tonnes.values()), sum(tkm.values())
    table = []
    for key in sorted(tonnes, key=lambda k: -tkm[k]):
        entry = dict(zip(label_names, key if isinstance(key, tuple) else (key,)))
        entry.update(mt=round(tonnes[key] / 1e3, 2), share_tonnes=round(tonnes[key] / total_t, 4),
                     bn_tkm=round(tkm[key] / 1e3, 2), share_tkm=round(tkm[key] / total_tkm, 4),
                     mean_km=round(tkm[key] / tonnes[key] * 1e3) if tonnes[key] else "")
        table.append(entry)
    return table


def partner_size_split(row):
    if not row["partner_size_mix"]:
        return [("unknown", 1.0)]
    return [(k, float(v)) for k, v in (item.split("=") for item in row["partner_size_mix"].split(";"))]


def summarise(base, rows):
    known = [r for r in rows if r["distance_class"] != "unknown"]
    tables = {
        "summary_by_size_class.csv": share_table(
            known, lambda r: [((r["rep_size_class"], cls), w) for cls, w in partner_size_split(r)],
            ["rep_size_class", "partner_size_class"]),
        "summary_by_rep_size_class.csv": share_table(known, lambda r: [(r["rep_size_class"], 1.0)], ["rep_size_class"]),
        "summary_by_distance_class.csv": share_table(rows, lambda r: [(r["distance_class"], 1.0)], ["distance_class"]),
        "summary_by_cargo.csv": share_table(rows, lambda r: [(r["cargo"], 1.0)], ["cargo"]),
        "summary_by_cargo_x_distance.csv": share_table(
            known, lambda r: [((r["cargo"], r["distance_class"]), 1.0)], ["cargo", "distance_class"]),
        "summary_by_partner.csv": share_table(
            known, lambda r: [((r["partner"], r["partner_name"]), 1.0)], ["partner", "partner_name"]),
    }
    for name, table in tables.items():
        write_csv(os.path.join(base, name), table)
    hubs = {"NL_0NLRTM", "BE_0BE003", "DE_1DEHAM"}
    pairs = defaultdict(lambda: defaultdict(float))
    for r in known:
        if r["rep_port"] not in hubs:
            continue
        p = pairs[(r["rep_port"], r["rep_name"], r["partner"], r["partner_name"])]
        p["kt"] += r["kt"]
        p["mtkm"] += r["mtkm"]
        p["sea_km"] = r["sea_km"]
        p[r["cargo"]] += r["mtkm"]
    total_tkm = sum(r["mtkm"] for r in known)
    hub_tkm = sum(p["mtkm"] for p in pairs.values())
    top = []
    for (port, name, partner, pname), p in sorted(pairs.items(), key=lambda kv: -kv[1]["mtkm"])[:20]:
        cargo_mix = sorted(((c, v) for c, v in p.items() if c not in ("kt", "mtkm", "sea_km")), key=lambda x: -x[1])
        top.append(dict(rep_port=port, rep_name=name, partner=partner, partner_name=pname, sea_km=p["sea_km"],
                        mt_both_directions=round(p["kt"] / 1e3, 2), bn_tkm=round(p["mtkm"] / 1e3, 2),
                        share_of_hub_tkm=round(p["mtkm"] / hub_tkm, 4), share_of_all_tkm=round(p["mtkm"] / total_tkm, 4),
                        cargo_mix_by_tkm=";".join(f"{c}={v / p['mtkm']:.2f}" for c, v in cargo_mix if v > 0)))
    write_csv(os.path.join(base, "top20_pairs_RTM_ANR_HAM.csv"), top)


if __name__ == "__main__":
    main(sys.argv[1])
