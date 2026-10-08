#!/usr/bin/env python3
"""Level script for Wick and the Undercroft.

Writes data/wick_map.json and data/undercroft_wick.json (ASCII grids + props) and a
preview PNG to tools/maps/preview_*.png. The JSON files are the runtime source of truth;
this script is the authoring tool. Re-run after editing:  python3 tools/maps/build_maps.py
"""
import json
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, "data")

W, D = 48, 32           # Wick: x across, z depth (north = 0, south = camera side)
SLICE_Z = 20            # the utility lane; the cut plane is its south face
UW, UH, GROUND = 48, 24, 10


# ----------------------------------------------------------------------------------------
# Wick (3D village)
# ----------------------------------------------------------------------------------------
def build_wick():
    hgt = [["0"] * W for _ in range(D)]
    mat = [["."] * W for _ in range(D)]

    def H(x0, z0, x1, z1, ch):
        for z in range(z0, z1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < W and 0 <= z < D:
                    hgt[z][x] = ch

    def M(x0, z0, x1, z1, ch):
        for z in range(z0, z1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < W and 0 <= z < D:
                    mat[z][x] = ch

    # Cavern walls: tall back wall with a ragged edge, side walls.
    H(0, 0, 47, 1, "W")
    for x in range(W):
        rag = [0, 1, 1, 0, 2, 1, 0, 0, 1, 2, 2, 1, 0, 1, 0, 0][x % 16]
        if rag:
            H(x, 2, x, 1 + rag, "W")
    H(0, 0, 0, 31, "W")
    H(47, 0, 47, 31, "W")
    M(0, 0, 47, 31, ".")  # moss floor everywhere by default

    # Arrival grotto (north-west): raised shelf where the player lands from the Chute.
    H(1, 2, 7, 6, "3")
    H(1, 7, 7, 7, "2")
    H(2, 8, 6, 8, "1")
    M(1, 2, 7, 8, "r")
    M(3, 7, 4, 8, "=")          # stairs down from the shelf
    hgt[7][3] = "2"; hgt[7][4] = "2"; hgt[8][3] = "1"; hgt[8][4] = "1"

    # Terraces along the back wall for depth.
    H(8, 2, 17, 3, "2")
    H(26, 2, 35, 3, "2")
    H(18, 2, 25, 2, "3")
    M(8, 2, 35, 3, "r")

    # The utility lane: gravel, across the whole village on the slice row.
    M(1, SLICE_Z, 46, SLICE_Z, ",")
    # Paths
    M(5, 14, 5, 19, ",")           # Lease door path
    M(5, 9, 5, 13, ",")            # from the grotto stairs to the Lease
    M(3, 9, 18, 9, ",")            # north path west
    M(18, 9, 30, 19, ":")          # the Commons (cobbles)
    M(30, 12, 37, 13, ",")         # to the Exchange and Pump Hall
    M(37, 13, 45, 13, ",")
    M(44, 13, 46, 17, ",")         # Reach gate approach
    M(26, 21, 27, 23, "#")         # dock planks over the shore

    # The Lease farm: tillable soil.
    M(6, 15, 15, 19, "f")

    # Lake Wickwater (south of the lane): peeled away in the cross-section.
    for z in range(22, 31):
        for x in range(13, 42):
            dx = (x - 27.5) / 15.0
            dz = (z - 27.0) / 5.6
            if dx * dx + dz * dz < 1.0:
                hgt[z][x] = "~"
                mat[z][x] = "~"
    H(26, 22, 27, 25, "0"); M(26, 22, 27, 25, "#")   # the dock reaches into the water
    M(2, 22, 12, 30, "m")          # Hesper's moss beds / shore moss
    M(42, 22, 46, 30, "r")
    H(43, 25, 46, 30, "2")
    H(1, 28, 6, 30, "1")

    props = []

    def P(t, x, z, **kw):
        d = {"type": t, "x": x, "z": z}
        d.update(kw)
        props.append(d)

    # Buildings ("interior": the Lease is a cutaway dollhouse you can walk into).
    P("house", 3, 10, size=[6, 5], variant="lease", door=[5, 14], interior=True, block=True)
    P("house", 19, 4, size=[7, 5], variant="lantern_house", door=[22, 8], block=True)
    P("house", 30, 6, size=[6, 5], variant="exchange", door=[32, 10], block=True)
    P("house", 31, 15, size=[4, 4], variant="odile", door=[32, 18], block=True)
    P("house", 37, 3, size=[9, 8], variant="pump_hall", door=[41, 10], block=True)
    P("house", 38, 14, size=[5, 4], variant="annex", door=[39, 17], block=True)
    P("house", 3, 23, size=[4, 4], variant="hesper", door=[5, 26], block=True)

    # Lease interior furniture (positions inside the house footprint).
    P("bed", 4, 11, size=[1, 2], block=True, home=True)
    P("bench", 7, 11, size=[1, 1], block=True, home=True, station="bench")
    P("stove", 6, 11, block=True, home=True)
    P("chest", 4, 13, block=True, home=True, station="storage")
    P("shelf", 5, 11, home=True)

    # Glowroot trees: the grove's living light.
    for (x, z, s) in [(12, 6, 1.2), (16, 13, 1.0), (28, 4, 1.1), (36, 16, 0.9), (2, 15, 1.0),
                      (10, 23, 1.1), (20, 23, 0.9), (34, 22, 1.0), (44, 21, 1.2), (17, 18, 0.8),
                      (8, 4, 1.3), (44, 9, 0.9), (24, 13, 0.7)]:
        P("glowroot", x, z, scale=s, block=True)
    for (x, z) in [(14, 8), (11, 12), (2, 11), (26, 9), (35, 11), (29, 18), (42, 18), (9, 21),
                   (31, 21), (21, 21), (39, 21), (15, 21), (45, 19), (1, 20), (6, 21), (23, 3),
                   (33, 3), (13, 2), (40, 12), (46, 25)]:
        P("glowroot_small", x, z)
    for (x, z) in [(10, 10), (13, 11), (16, 6), (27, 15), (34, 19), (44, 16), (3, 18), (16, 16),
                   (40, 20), (12, 21), (22, 12), (29, 13), (8, 25), (11, 27), (4, 29), (7, 27),
                   (45, 23), (14, 4), (33, 4), (24, 5)]:
        P("moss_tuft", x, z)
    for (x, z) in [(9, 8), (17, 10), (36, 18), (43, 11), (1, 12), (19, 16), (12, 24), (5, 28)]:
        P("mushroom", x, z)

    # The Commons.
    P("table", 22, 11, size=[2, 1], block=True)
    P("table", 22, 14, size=[2, 1], block=True)
    P("bench_seat", 22, 10, size=[2, 1])
    P("bench_seat", 22, 12, size=[2, 1])
    P("bench_seat", 22, 15, size=[2, 1])
    P("notice_board", 27, 11, block=True)
    P("town_lamp", 19, 10, block=True)
    P("town_lamp", 28, 10, block=True)
    P("town_lamp", 19, 18, block=True)
    P("town_lamp", 28, 18, block=True)
    P("market_stall", 25, 16, size=[2, 1], block=True)
    P("barrel", 36, 8, block=True)
    P("barrel", 36, 9, block=True)
    P("crate", 29, 9, block=True)
    P("crate", 29, 10, block=True)
    P("crate_stack", 35, 11, block=True)

    # The Lease: fence, broken lamp, scattered tools.
    for x in range(6, 16):
        P("fence", x, 14, rot=0)
    P("fence_post", 16, 14)
    P("barrel", 9, 13, block=True)
    P("signpost", 4, 9, text="THE LEASE")

    # Barnaby's annex clutter and the workbench he lets you use.
    P("workbench", 43, 16, block=True, station="bench_barnaby")
    P("pipe_pile", 42, 18, block=True)
    P("gear_pile", 37, 18)
    P("chimney_pipe", 45, 6, block=True)

    # Lake shore.
    P("dock_post", 25, 22)
    P("dock_post", 28, 22)
    P("dock_post", 25, 25)
    P("dock_post", 28, 25)
    P("boat", 29, 24)
    for (x, z) in [(13, 24), (16, 29), (38, 28), (41, 24), (19, 31), (35, 31), (30, 30)]:
        P("shore_rock", x, z, block=True)
    P("specimen_rack", 8, 23, block=True)
    P("moss_frame", 10, 25, size=[2, 1], block=True)
    P("moss_frame", 10, 27, size=[2, 1], block=True)

    # Foreground occluders on the camera side (blur under DOF; frame the diorama).
    for (x, z, s) in [(4, 31, 1.4), (15, 31, 1.0), (24, 31, 1.6), (33, 31, 1.1), (44, 30, 1.5),
                      (11, 30, 0.8), (39, 31, 0.9)]:
        P("stalagmite", x, z, scale=s, block=True)
    for (x, z, s) in [(1, 26, 1.0), (46, 28, 1.2)]:
        P("stalagmite", x, z, scale=s, block=True)

    # The Chute (arrival) and the Reach gate.
    P("chute", 3, 3, size=[2, 2])
    P("rubble_small", 5, 4)
    P("salvage_harness", 4, 5)
    P("reach_gate", 46, 14, size=[1, 4])

    exits = [{"x": 46, "z": 15, "to": "reach", "arrive": [44, 15]},
             {"x": 46, "z": 16, "to": "reach", "arrive": [44, 16]}]

    points = {
        "arrival": [4, 5], "lease_door": [5, 15], "lease_inside": [6, 12], "well": [24, 19],
        "commons": [23, 13], "commons_table": [21, 13], "lantern_door": [22, 9],
        "exchange_door": [32, 11], "exchange_counter": [31, 12], "odile_door": [32, 19],
        "pumphall_door": [41, 11], "annex_door": [39, 18], "annex_bench": [43, 17],
        "hesper_door": [5, 27], "moss_beds": [9, 26], "dock": [26, 23], "reach_gate": [44, 15],
        "lane_west": [8, 20], "lane_east": [40, 20], "farm": [10, 17], "pipe_heads": [30, 19],
        "shore_east": [40, 23], "grotto": [5, 6], "lake_view": [21, 21], "barnaby_well": [23, 19],
        "board": [26, 12],
    }

    lights = [
        {"x": 22.5, "z": 6.5, "y": 2.2, "color": "amber", "energy": 2.0, "range": 8.0, "kind": "window"},
        {"x": 32.5, "z": 9.0, "y": 2.0, "color": "amber", "energy": 1.4, "range": 6.0, "kind": "window"},
        {"x": 41.0, "z": 15.5, "y": 2.0, "color": "amber", "energy": 1.2, "range": 6.0, "kind": "window"},
        {"x": 4.0, "z": 3.5, "y": 6.0, "color": "cream", "energy": 1.8, "range": 9.0, "kind": "shaft"},
    ]

    legend = {".": "moss_floor", ",": "gravel", ":": "cobble", "f": "farm_soil", "r": "rock_floor",
              "=": "stairs", "#": "plank", "m": "moss_deep", "~": "water"}
    return {
        "id": "wick", "biome": "grove", "slice_z": SLICE_Z,
        "legend": legend,
        "height": ["".join(r) for r in hgt],
        "mat": ["".join(r) for r in mat],
        "props": props, "exits": exits, "points": points, "lights": lights,
        "meta": {"name": "Wick", "ceiling": 12.0, "ambient": "grove"},
    }


# ----------------------------------------------------------------------------------------
# Undercroft (cross-section under the lane)
# ----------------------------------------------------------------------------------------
def build_undercroft():
    g = [["."] * UW for _ in range(UH)]

    def F(x0, y0, x1, y1, ch):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                g[y][x] = ch

    F(0, GROUND, 47, GROUND, "T")
    F(0, 11, 47, 13, "s")
    F(0, 14, 47, 15, "c")
    F(0, 16, 47, 22, "r")
    F(0, 23, 47, 23, "B")
    F(0, 11, 0, 23, "B")
    F(47, 11, 47, 23, "B")
    F(18, GROUND, 29, GROUND, "s")          # cobbled commons: no farmable topsoil
    # Old Pump Hall basement (brick) with the Station pump.
    F(34, 10, 45, 16, "b")
    F(35, 11, 44, 15, ".")
    F(41, 16, 42, 16, ".")                  # shaft down to the Sink
    # The Sink: flooded chamber fed by the spring.
    F(34, 17, 43, 21, ".")
    F(46, 12, 46, 17, ".")                  # the spring's waterfall shaft (turbine site)
    F(44, 17, 45, 17, ".")                  # channel from the shaft foot into the Sink
    # Cistern (stone lined).
    F(26, 12, 31, 17, "S")
    F(27, 13, 30, 16, ".")
    # Maintenance crawlspace where the feed line runs.
    F(21, 12, 25, 13, ".")
    # Geothermal seam.
    F(12, 21, 20, 22, "E")
    # The sour pocket under the Lease, sealed by a thin crust.
    F(3, 19, 9, 21, ".")
    F(3, 18, 9, 18, "L")

    fissure = [[7, 10], [7, 11], [7, 12], [8, 13], [8, 14], [7, 15], [7, 16], [8, 17], [7, 18], [6, 18]]

    pipes = []
    # Wick feed line: well (24,9) -> crawlspace -> cistern intake (27,16). Burst at (24,13).
    for y in range(9, 16):
        pipes.append([24, y, 0.0 if y == 13 else 1.0])
    for x in range(25, 28):
        pipes.append([x, 15, 1.0])
    pipes.append([27, 16, 1.0])
    # Station line (old, cracked): Sink intake (41,21) -> shaft -> pump; pump -> cistern outlet.
    for y in range(15, 22):
        pipes.append([41, y, 0.35 if y in (17, 19) else 0.8])
    pipes.append([40, 15, 0.8])
    pipes.append([39, 15, 0.8])
    for x in range(30, 37):
        pipes.append([x, 12, 0.3 if x in (33, 34) else 0.85])
    pipes.append([30, 13, 0.85])

    machines = [
        {"def": "old_well", "x": 24, "y": 9},
        {"def": "intake", "x": 27, "y": 16, "fixed": True},
        {"def": "wick_mains", "x": 29, "y": 16},
        {"def": "station_pump", "x": 36, "y": 12},
        {"def": "intake", "x": 41, "y": 21, "fixed": True},
        {"def": "outlet", "x": 30, "y": 13, "fixed": True},
        {"def": "lift_winch", "x": 42, "y": 12},
    ]

    water = []
    for x in range(27, 31):
        water += [[x, 16, 1.0], [x, 15, 1.0], [x, 14, 0.35]]
    for x in range(34, 44):
        for y in range(19, 22):
            water.append([x, y, 1.0])
    for x in range(21, 25):
        water.append([x, 13, 0.45])

    relics = [
        {"type": "crew_locker", "x": 21, "y": 12, "lore": "locker"},
        {"type": "stencil", "x": 35, "y": 11, "text": "STN-7  PRIMARY LIFT"},
        {"type": "gauge", "x": 43, "y": 11, "label": "LOWER STATIONS", "story": "gauge"},
        {"type": "trunk_valve", "x": 38, "y": 21, "size": [2, 1]},
        {"type": "old_pipes", "x": 44, "y": 11, "size": [1, 4]},
    ]

    legend = {".": "air", "T": "topsoil", "s": "soil", "c": "clay", "r": "rock", "b": "brick",
              "S": "stone", "m": "metal", "i": "insulation", "B": "bedrock", "E": "ember", "L": "seal"}
    return {
        "w": UW, "h": UH, "ground_y": GROUND, "slice_z": SLICE_Z,
        "legend": legend, "rows": ["".join(r) for r in g],
        "pipes": pipes, "wires": [], "machines": machines, "water": water,
        "springs": [[46, 12, 0.0045]],
        "drains": [[34, 19, 0.009]],
        "vents": [[37, 21, {"3": 0.0015}]],
        "hot": [[x, y, 92.0] for x in range(12, 21) for y in (21, 22)],
        "pockets": [{"cells": [3, 19, 9, 21], "gas": {"0": 0.2, "2": 2.4}}],
        "fissure": fissure, "relics": relics,
    }


# ----------------------------------------------------------------------------------------
def preview_wick(m, path):
    cols = {"moss_floor": (52, 74, 48), "gravel": (110, 104, 96), "cobble": (130, 120, 104),
            "farm_soil": (92, 66, 44), "rock_floor": (70, 68, 78), "stairs": (150, 140, 120),
            "plank": (140, 100, 60), "moss_deep": (40, 90, 50), "water": (40, 90, 140)}
    s = 14
    img = Image.new("RGB", (W * s, D * s))
    dr = ImageDraw.Draw(img)
    for z in range(D):
        for x in range(W):
            hc = m["height"][z][x]
            mt = m["legend"].get(m["mat"][z][x], "moss_floor")
            c = cols.get(mt, (255, 0, 255))
            if hc == "W":
                c = (25, 24, 30)
            elif hc.isdigit():
                k = 1.0 + int(hc) * 0.12
                c = tuple(min(255, int(v * k)) for v in c)
            dr.rectangle([x * s, z * s, x * s + s - 1, z * s + s - 1], fill=c)
    for p in m["props"]:
        sz = p.get("size", [1, 1])
        col = {"house": (180, 150, 90), "glowroot": (90, 230, 220), "glowroot_small": (60, 160, 160),
               "stalagmite": (120, 110, 130)}.get(p["type"], (200, 200, 200))
        if p["type"] in ("moss_tuft", "mushroom"):
            continue
        dr.rectangle([p["x"] * s + 2, p["z"] * s + 2, (p["x"] + sz[0]) * s - 3, (p["z"] + sz[1]) * s - 3], outline=col)
    dr.line([0, (SLICE_Z + 1) * s, W * s, (SLICE_Z + 1) * s], fill=(255, 80, 80), width=2)
    img.save(path)


def preview_undercroft(u, path):
    cols = {".": (20, 22, 30), "T": (92, 66, 44), "s": (80, 60, 45), "c": (110, 80, 60), "r": (70, 68, 78),
            "b": (120, 60, 50), "S": (100, 100, 110), "B": (35, 34, 40), "E": (220, 90, 30), "L": (150, 150, 60)}
    s = 14
    img = Image.new("RGB", (UW * s, UH * s))
    dr = ImageDraw.Draw(img)
    for y in range(UH):
        for x in range(UW):
            dr.rectangle([x * s, y * s, x * s + s - 1, y * s + s - 1], fill=cols[u["rows"][y][x]])
    for (x, y, a) in u["water"]:
        dr.rectangle([x * s, y * s + int(s * (1 - a)), x * s + s - 1, y * s + s - 1], fill=(50, 110, 170))
    for (x, y, hp) in u["pipes"]:
        dr.rectangle([x * s + 4, y * s + 4, x * s + s - 5, y * s + s - 5], fill=(200, 160, 80) if hp > 0.5 else (255, 60, 60))
    for mch in u["machines"]:
        dr.rectangle([mch["x"] * s, mch["y"] * s, mch["x"] * s + s - 1, mch["y"] * s + s - 1], outline=(255, 255, 255))
    img.save(path)


if __name__ == "__main__":
    wick = build_wick()
    under = build_undercroft()
    with open(os.path.join(DATA, "wick_map.json"), "w") as f:
        json.dump(wick, f, indent=1)
    with open(os.path.join(DATA, "undercroft_wick.json"), "w") as f:
        json.dump(under, f, indent=1)
    here = os.path.dirname(os.path.abspath(__file__))
    preview_wick(wick, os.path.join(here, "preview_wick.png"))
    preview_undercroft(under, os.path.join(here, "preview_undercroft.png"))
    print("wrote wick_map.json, undercroft_wick.json and previews")
