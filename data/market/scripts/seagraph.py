# SPDX-FileCopyrightText: 2026 Bart van de Lint
# SPDX-License-Identifier: AGPL-3.0-or-later

"""Coarse sea-lane graph for approximate port-to-port sea distances [km]."""
import heapq, math

NODES = {
    # North Sea, Channel, British Isles
    "NS_S": (52.5, 3.0), "DOVER": (51.0, 1.6), "CH_C": (50.2, -1.0), "CH_W": (49.6, -5.0),
    "USHANT": (48.3, -5.7), "GBIGHT": (54.0, 7.8), "ELBE": (53.9, 9.0), "JUTW": (56.0, 7.5),
    "NS_C": (55.5, 4.0), "NS_N": (59.0, 2.0), "HUMBER": (53.6, 0.6), "UK_E": (55.0, 0.0),
    "FORTH": (56.1, -2.3), "UK_NE": (57.5, -1.5), "PENTLAND": (58.75, -2.8),
    "NW_SCOT": (58.7, -6.0), "HEBR_W": (57.0, -8.5), "N_CHAN": (55.3, -5.8),
    "IRISH": (53.5, -5.3), "STGEORGE": (52.0, -6.0), "CELTIC": (51.0, -7.0),
    "SHANNON": (52.4, -10.2),
    # Norway, Arctic
    "NORW_S": (58.5, 5.0), "NORW_SW": (60.3, 4.6), "NORW_W": (62.5, 4.5), "NORW_N": (68.5, 12.0),
    "NCAPE": (71.3, 25.0), "BARENTS": (70.5, 36.0), "WHITE": (66.5, 40.5),
    "KARA_G": (70.5, 57.5), "KARA": (72.5, 67.0), "SKAGRK": (58.0, 9.0), "OSLOF": (59.0, 10.6),
    "FAROE": (62.0, -7.0), "ICELAND": (63.2, -20.0),
    # Kattegat, Baltic
    "SKAGEN": (57.9, 10.8), "KATT": (56.8, 11.5), "ORESUND": (55.6, 12.8), "GBELT": (55.3, 11.0),
    "KIELB": (54.6, 10.6), "BALT_W": (54.8, 13.0), "POMERAN": (54.2, 14.3), "BORNHOLM": (55.0, 15.2),
    "GDANSK_B": (54.7, 19.0), "BALT_E": (55.7, 20.3), "BALT_C": (56.8, 19.0), "IRBE": (57.8, 21.8),
    "GRIGA": (57.5, 23.8), "BALT_N": (59.3, 20.5), "GFIN_W": (59.6, 23.0), "GFIN_E": (60.0, 27.0),
    "GBOTH_S": (61.5, 19.0), "GBOTH_N": (64.5, 22.5),
    # Biscay, Iberia, NW Africa
    "LOIRE": (47.0, -3.0), "BISCAY": (45.5, -4.5), "GIRONDE": (45.6, -1.6), "BISCAY_S": (43.8, -3.5),
    "GALICIA_N": (43.9, -8.0), "FINISTERRE": (43.0, -9.6), "PORT_N": (41.2, -9.3),
    "PORT_W": (38.6, -9.8), "ST_VINC": (36.9, -9.2), "CADIZ_G": (36.4, -7.0), "GIBR": (35.95, -5.6),
    "MOROCCO_W": (33.0, -9.0), "CANARY": (28.0, -15.5), "CAPE_VERDE": (15.0, -21.0),
    # Mediterranean
    "ALBORAN": (36.0, -3.0), "CABO_GATA": (36.6, -1.8), "PALOS": (37.6, -0.5),
    "VALENCIA_G": (39.3, 0.3), "CATALAN": (41.0, 2.6), "LION": (42.8, 4.8), "LIGURIAN": (43.8, 8.5),
    "BALEARIC": (39.0, 4.5), "ALG_W": (36.0, -0.5), "ALG_E": (37.3, 7.0), "SARD_S": (38.3, 9.0),
    "TYRRH_N": (42.0, 10.5), "TYRRH": (40.0, 12.5), "SICILY_N": (38.7, 13.5), "MESSINA": (38.1, 15.6),
    "SICILY_CH": (37.4, 11.5), "MALTA": (35.8, 14.5), "LIBYA_W": (33.3, 12.5), "LIBYA_E": (32.5, 20.0),
    "IONIAN": (37.0, 18.5), "OTRANTO": (40.2, 19.0), "ADRIA_C": (42.5, 16.0), "ADRIA_N": (44.5, 13.0),
    "MALEA": (36.3, 23.3), "AEGEAN_S": (37.0, 24.5), "AEGEAN_N": (39.5, 24.8), "RHODES": (36.0, 28.0),
    "DARDAN": (40.0, 26.2), "MARMARA": (40.8, 28.3), "BOSPH": (41.2, 29.1), "BLACK_W": (43.0, 29.5),
    "ODESSA_O": (46.0, 31.0), "BLACK_C": (43.5, 34.0), "KERCH": (45.0, 36.5), "BLACK_E": (42.0, 40.0),
    "CRETE_S": (34.5, 25.0), "CILICIA": (36.0, 34.5), "LEVANT": (33.5, 33.0),
    # Suez, Red Sea, Gulf, Indian Ocean
    "PORT_SAID": (31.3, 32.35), "SUEZ": (29.9, 32.55), "RED_N": (27.3, 34.0), "RED_NC": (24.0, 36.5),
    "RED_C": (20.0, 38.5), "BAB": (12.6, 43.4), "ADEN": (12.5, 46.0), "SOCOTRA": (12.5, 53.0),
    "RAS_HADD": (22.8, 60.2), "HORMUZ": (26.5, 56.5), "GULF_C": (27.0, 52.0), "GULF_N": (29.0, 49.5),
    "KUTCH": (22.0, 68.5), "INDIA_W": (19.0, 71.5), "INDIA_SW": (9.0, 75.5), "DONDRA": (5.6, 80.6),
    "BENGAL": (15.0, 84.0), "MALACCA_N": (6.0, 95.5), "MALACCA": (3.0, 100.5),
    "SINGAPORE": (1.2, 103.9), "GULF_TH": (10.0, 101.5), "SCS_S": (4.5, 107.5), "SCS_C": (12.0, 112.0),
    "SCS_N": (20.5, 115.5), "TAIWAN_STR": (24.5, 119.5), "ECS": (30.5, 123.5), "YELLOW": (36.5, 123.0),
    "KOREA_S": (34.0, 128.5), "JAPAN_S": (33.0, 135.0), "LUZON": (20.5, 121.5),
    "SUNDA": (-6.3, 105.5), "JAVA_SEA": (-5.5, 108.5), "MAKASSAR": (-2.0, 117.5),
    "AUS_NW": (-19.5, 116.0), "AUS_W": (-32.0, 114.5), "AUS_SW": (-35.5, 117.0),
    "AUS_S": (-38.5, 141.0), "BASS": (-39.3, 146.5), "AUS_E": (-34.0, 151.5), "AUS_NE": (-23.5, 153.0),
    "NZ_N": (-36.0, 175.0),
    # Africa
    "LIBERIA_O": (4.5, -11.0), "GULF_GUINEA": (4.0, 3.0), "ANGOLA": (-9.0, 12.0),
    "CAPE_GOOD": (-35.0, 18.3), "AGULHAS": (-36.5, 21.0), "DURBAN_O": (-30.0, 32.0),
    "MOZ_CH": (-20.0, 40.0), "E_AFR": (-5.0, 41.0), "IND_SW": (-30.0, 50.0),
    # Americas
    "CAPE_RACE": (46.5, -53.0), "CABOT": (47.3, -59.5), "STLAW": (49.5, -65.0),
    "QUEBEC": (46.8, -71.2), "LAKES": (43.5, -79.0), "NOVA_S": (43.5, -64.0), "US_NE": (40.3, -73.5),
    "HATTERAS": (35.0, -75.0), "US_SE": (31.5, -80.0), "NE_PROV": (26.0, -76.5),
    "FLORIDA_STR": (24.3, -81.5), "GULF_MEX": (26.0, -90.0), "YUCATAN": (21.7, -86.0),
    "CARIB_E": (18.5, -64.0), "CARIB_S": (12.5, -66.0), "CARIB_C": (15.0, -75.0),
    "PANAMA_ATL": (9.6, -79.9), "PANAMA_PAC": (8.7, -79.5), "PAC_COL": (3.0, -79.5),
    "PERU": (-12.0, -78.0), "CHILE": (-33.0, -72.2), "MEX_W": (16.0, -99.0), "US_SW": (33.5, -118.5),
    "US_NW": (48.4, -124.8), "BRAZIL_N": (-1.5, -43.5), "BRAZIL_NE": (-5.5, -34.5),
    "BRAZIL_E": (-23.0, -41.0), "SANTOS": (-24.5, -46.0), "RIO_PLATA": (-35.5, -55.0),
    "GUIANA": (8.0, -57.0),
}

EDGES = """
NS_S DOVER; DOVER CH_C; CH_C CH_W; CH_W USHANT; NS_S GBIGHT; GBIGHT ELBE; GBIGHT JUTW; NS_C GBIGHT;
NS_S NS_C; NS_C JUTW; JUTW SKAGRK; NS_C NS_N; NS_S HUMBER; HUMBER UK_E; UK_E NS_C; UK_E FORTH;
FORTH UK_NE; UK_NE NS_N; UK_NE PENTLAND; PENTLAND NW_SCOT; NW_SCOT HEBR_W; HEBR_W N_CHAN;
N_CHAN IRISH; IRISH STGEORGE; STGEORGE CELTIC; CELTIC CH_W; CELTIC USHANT; CELTIC SHANNON;
SHANNON HEBR_W; NS_N NORW_SW; NORW_S NORW_SW; NORW_S SKAGRK; NS_C NORW_S; SKAGRK SKAGEN;
SKAGRK OSLOF; NORW_SW NORW_W; NORW_W NORW_N; NORW_N NCAPE; NCAPE BARENTS; BARENTS WHITE;
BARENTS KARA_G; KARA_G KARA; NS_N FAROE; NW_SCOT FAROE; FAROE ICELAND; NORW_W FAROE;
SKAGEN KATT; KATT ORESUND; KATT GBELT; GBELT KIELB; ELBE KIELB; KIELB BALT_W; ORESUND BALT_W;
BALT_W POMERAN; POMERAN BORNHOLM; BALT_W BORNHOLM; BORNHOLM GDANSK_B; BORNHOLM BALT_E;
GDANSK_B BALT_E; BALT_E BALT_C; BORNHOLM BALT_C; BALT_C IRBE; IRBE GRIGA; BALT_C BALT_N;
BALT_N GFIN_W; GFIN_W GFIN_E; BALT_N GBOTH_S; GBOTH_S GBOTH_N;
USHANT LOIRE; USHANT BISCAY; LOIRE BISCAY; BISCAY GIRONDE; BISCAY BISCAY_S; BISCAY_S GALICIA_N;
GALICIA_N FINISTERRE; USHANT FINISTERRE; FINISTERRE PORT_N; PORT_N PORT_W; PORT_W ST_VINC;
ST_VINC CADIZ_G; CADIZ_G GIBR; ST_VINC MOROCCO_W; MOROCCO_W CANARY; ST_VINC CANARY;
CANARY CAPE_VERDE; GIBR MOROCCO_W;
GIBR ALBORAN; ALBORAN CABO_GATA; CABO_GATA PALOS; PALOS VALENCIA_G; VALENCIA_G CATALAN;
CATALAN LION; LION LIGURIAN; ALBORAN ALG_W; ALG_W BALEARIC; ALG_E BALEARIC; BALEARIC VALENCIA_G;
BALEARIC CATALAN; BALEARIC LION; BALEARIC SARD_S; ALG_W ALG_E; ALG_E SARD_S; ALG_E SICILY_CH;
LIGURIAN TYRRH_N; TYRRH_N TYRRH; SARD_S TYRRH; TYRRH SICILY_N; SICILY_N MESSINA; SARD_S SICILY_CH;
SICILY_CH SICILY_N; SICILY_CH MALTA; MALTA IONIAN; MALTA LIBYA_W; LIBYA_W LIBYA_E; LIBYA_E CRETE_S;
MALTA CRETE_S; MESSINA IONIAN; IONIAN OTRANTO; OTRANTO ADRIA_C; ADRIA_C ADRIA_N; IONIAN MALEA;
IONIAN CRETE_S; MALEA AEGEAN_S; AEGEAN_S AEGEAN_N; AEGEAN_N DARDAN; DARDAN MARMARA; MARMARA BOSPH;
BOSPH BLACK_W; BLACK_W ODESSA_O; BLACK_W BLACK_C; BLACK_C KERCH; BLACK_C BLACK_E; ODESSA_O BLACK_C;
CRETE_S AEGEAN_S; RHODES AEGEAN_S; RHODES CRETE_S; RHODES CILICIA; CRETE_S LEVANT; LEVANT CILICIA;
LEVANT PORT_SAID; CRETE_S PORT_SAID;
PORT_SAID SUEZ; SUEZ RED_N; RED_N RED_NC; RED_NC RED_C; RED_C BAB; BAB ADEN; ADEN SOCOTRA;
SOCOTRA RAS_HADD; RAS_HADD HORMUZ; HORMUZ GULF_C; GULF_C GULF_N; RAS_HADD KUTCH; KUTCH INDIA_W;
INDIA_W INDIA_SW; INDIA_SW DONDRA; SOCOTRA DONDRA; SOCOTRA INDIA_SW; DONDRA BENGAL;
DONDRA MALACCA_N; BENGAL MALACCA_N; MALACCA_N MALACCA; MALACCA SINGAPORE; SINGAPORE SCS_S;
SCS_S GULF_TH; SCS_S SCS_C; SCS_C SCS_N; SCS_N TAIWAN_STR; TAIWAN_STR ECS; ECS YELLOW; ECS KOREA_S;
YELLOW KOREA_S; KOREA_S JAPAN_S; SCS_N LUZON; LUZON JAPAN_S; SINGAPORE JAVA_SEA; SUNDA JAVA_SEA;
JAVA_SEA MAKASSAR; DONDRA SUNDA; DONDRA AUS_NW; SUNDA AUS_NW; AUS_NW AUS_W; AUS_W AUS_SW;
AUS_SW AUS_S; AUS_S BASS; BASS AUS_E; AUS_E AUS_NE; AUS_E NZ_N;
CAPE_VERDE LIBERIA_O; LIBERIA_O GULF_GUINEA; GULF_GUINEA ANGOLA; ANGOLA CAPE_GOOD;
CAPE_VERDE CAPE_GOOD; CAPE_GOOD AGULHAS; AGULHAS DURBAN_O; DURBAN_O MOZ_CH; MOZ_CH E_AFR;
E_AFR SOCOTRA; AGULHAS IND_SW; IND_SW DONDRA; IND_SW SUNDA; IND_SW AUS_W; IND_SW RAS_HADD;
IND_SW SOCOTRA; IND_SW MALACCA_N;
CH_W CAPE_RACE; NW_SCOT CAPE_RACE; CAPE_RACE CABOT; CABOT STLAW; STLAW QUEBEC; QUEBEC LAKES;
CAPE_RACE NOVA_S; NOVA_S US_NE; CH_W US_NE; US_NE HATTERAS; CH_W HATTERAS; HATTERAS US_SE;
US_SE FLORIDA_STR; HATTERAS NE_PROV; NE_PROV FLORIDA_STR; FLORIDA_STR GULF_MEX; GULF_MEX YUCATAN;
YUCATAN CARIB_C; CH_W NE_PROV; FINISTERRE NE_PROV; CANARY CARIB_E; CH_W CARIB_E; CARIB_E CARIB_C;
CARIB_E CARIB_S; CARIB_S CARIB_C; CARIB_C PANAMA_ATL; PANAMA_ATL PANAMA_PAC; PANAMA_PAC PAC_COL;
PAC_COL PERU; PERU CHILE; PANAMA_PAC MEX_W; MEX_W US_SW; US_SW US_NW; US_SW JAPAN_S; US_NW JAPAN_S;
CAPE_VERDE BRAZIL_N; CAPE_VERDE BRAZIL_NE; BRAZIL_N BRAZIL_NE; BRAZIL_NE BRAZIL_E; BRAZIL_E SANTOS;
SANTOS RIO_PLATA; BRAZIL_N GUIANA; GUIANA CARIB_S; CAPE_VERDE GUIANA; CANARY GUIANA;
BRAZIL_E CAPE_GOOD; RIO_PLATA CAPE_GOOD; CHILE RIO_PLATA
"""


def great_circle_km(lat1, lon1, lat2, lon2):
    """Haversine great-circle distance [km] between two points given in degrees."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dlat, dlon = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dlat / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlon / 2) ** 2
    return 2 * 6371.0 * math.asin(math.sqrt(a))


def edge_list():
    """Pairs of node names joined by a sea lane."""
    return [tuple(pair.split()) for pair in EDGES.replace("\n", " ").split(";") if pair.strip()]


def all_pairs(closed=()):
    """Shortest sea-lane distance [km] between all node pairs, omitting edges in `closed`."""
    adjacency = {name: [] for name in NODES}
    for a, b in edge_list():
        if (a, b) in closed or (b, a) in closed:
            continue
        length = great_circle_km(*NODES[a], *NODES[b])
        adjacency[a].append((b, length))
        adjacency[b].append((a, length))
    table = {}
    for source in NODES:
        dist = {source: 0.0}
        queue = [(0.0, source)]
        while queue:
            d, node = heapq.heappop(queue)
            if d > dist[node]:
                continue
            for neighbour, length in adjacency[node]:
                if d + length < dist.get(neighbour, math.inf):
                    dist[neighbour] = d + length
                    heapq.heappush(queue, (d + length, neighbour))
        table[source] = dist
    return table


NEAREST = {}


def nearest_node(lat, lon):
    """Name of the graph node closest to a point."""
    if (lat, lon) not in NEAREST:
        NEAREST[(lat, lon)] = min(NODES, key=lambda name: great_circle_km(lat, lon, *NODES[name]))
    return NEAREST[(lat, lon)]


class SeaDistance:
    """Port-to-port sea distance via the nearest graph nodes, with and without Suez."""

    def __init__(self):
        self.open = all_pairs()
        self.cape = all_pairs(closed={("PORT_SAID", "SUEZ")})

    def __call__(self, a, b):
        """Great-circle, sea (via Suez) and sea (Suez closed) distance [km] from a to b."""
        gc = great_circle_km(*a, *b)
        node_a, node_b = nearest_node(*a), nearest_node(*b)
        if node_a == node_b:
            return gc, 1.15 * gc, 1.15 * gc
        legs = great_circle_km(*a, *NODES[node_a]) + great_circle_km(*b, *NODES[node_b])
        return (gc, max(legs + self.open[node_a][node_b], gc),
                max(legs + self.cape[node_a][node_b], gc))
