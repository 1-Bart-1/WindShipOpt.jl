"""Tonne-km of North European range ports (NL, BE, DE North Sea, FR Atlantic) by partner region.

Usage: python3 -I route_groups.py <data/market directory>
"""
import csv, os, sys
from collections import defaultdict

REGIONS = {
    "East Asia": {"CN_X_HK", "KR", "JP", "TW", "HK"},
    "SE Asia / India": {"SG", "MY", "IN", "VN", "TH", "ID", "LK", "PK", "BD"},
    "US Gulf": {"US_3"},
    "Brazil / River Plate": {"BR", "AR", "UY"},
    "Middle East Gulf": {"IQ", "SA", "SA_1", "SA_2", "AE", "QA", "KW", "OM", "BH", "IR"},
    "US East / Canada": {"US_1", "US_2", "CA", "CA_1", "CA_2", "CA_9"},
    "West Africa": {"NG", "GH", "CI", "SN", "GN", "CM", "AO", "TG", "BJ", "GA", "CG", "LR", "SL", "MR", "GQ"},
    "North Africa / Levant": {"MA", "MA_1", "MA_2", "MA_9", "DZ", "TN", "LY", "EG", "EG_1", "EG_2", "EG_9",
                              "IL", "IL_1", "LB"},
    "UK / Ireland": {"UK", "UK_1", "UK_9", "IE"},
    "Baltic": {"FI", "PL", "LT", "LV", "EE", "SE_1", "RU_2", "RU_5", "RU_6", "DE_2"},
    "Norway": {"NO"},
    "Atlantic Iberia": {"ES_1", "PT"},
    "EU Mediterranean": {"ES_2", "IT", "EL", "FR_2", "SI", "HR", "MT", "CY"},
}


def north_european(row):
    port = row["rep_port"]
    return port[:2] in ("NL", "BE") or port.startswith("DE_1") or port.startswith("FR_1")


def main(base):
    rows = list(csv.DictReader(open(os.path.join(base, "eurostat_port_partner_flows_2024.csv"))))
    eu_tkm = sum(float(r["mtkm"]) for r in rows)
    range_rows = [r for r in rows if north_european(r)]
    range_tkm = sum(float(r["mtkm"]) for r in range_rows)
    tonnes, tkm = defaultdict(float), defaultdict(lambda: defaultdict(float))
    for row in range_rows:
        for region, partners in REGIONS.items():
            if row["partner"] in partners:
                tonnes[region] += float(row["kt"]) * float(row["dedup_weight"])
                tkm[region][row["cargo"]] += float(row["mtkm"])
    with open(os.path.join(base, "north_europe_route_groups_2024.csv"), "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["region", "mt", "bn_tkm", "share_of_range_tkm", "share_of_eu_tkm", "mean_km",
                         "cargo_mix_by_tkm"])
        for region in sorted(tkm, key=lambda k: -sum(tkm[k].values())):
            total = sum(tkm[region].values())
            mix = ";".join(f"{c}={v / total:.2f}" for c, v in sorted(tkm[region].items(), key=lambda x: -x[1]))
            writer.writerow([region, round(tonnes[region] / 1e3, 1), round(total / 1e3, 1),
                             round(total / range_tkm, 3), round(total / eu_tkm, 3),
                             round(total / tonnes[region] * 1e3), mix])


if __name__ == "__main__":
    main(sys.argv[1])
