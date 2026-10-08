#!/usr/bin/env python3
"""Level script for the authored places below Wick: Sallow (Station 11), the Heart, and the
Knapper Ways. Writes data/maps/<id>.json in the same ASCII format as Wick, plus previews.

Exits are named "up" and "down"; the game resolves them against the world graph (which
cavern is above, which below) when the area loads.

    python3 tools/maps/build_deep.py
"""
import json
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "data", "maps")


class Level:
    def __init__(self, w, d, floor_ch):
        self.w, self.d = w, d
        self.hgt = [["0"] * w for _ in range(d)]
        self.mat = [[floor_ch] * w for _ in range(d)]
        self.props = []

    def H(self, x0, z0, x1, z1, ch):
        for z in range(z0, z1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < self.w and 0 <= z < self.d:
                    self.hgt[z][x] = ch

    def M(self, x0, z0, x1, z1, ch):
        for z in range(z0, z1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < self.w and 0 <= z < self.d:
                    self.mat[z][x] = ch

    def P(self, t, x, z, **kw):
        d = {"type": t, "x": x, "z": z}
        d.update(kw)
        self.props.append(d)

    def walls(self, rag_seed=0):
        self.H(0, 0, self.w - 1, 1, "W")
        for x in range(self.w):
            rag = [0, 1, 1, 0, 2, 1, 0, 0, 1, 2, 2, 1, 0, 1, 0, 0][(x + rag_seed) % 16]
            if rag:
                self.H(x, 2, x, 1 + rag, "W")
        self.H(0, 0, 0, self.d - 1, "W")
        self.H(self.w - 1, 0, self.w - 1, self.d - 1, "W")

    def opening(self, x, z0, z1):
        self.H(x, z0, x, z1, "0")

    def out(self, id_, biome, legend, exits, points, lights, meta):
        return {"id": id_, "biome": biome, "legend": legend,
                "height": ["".join(r) for r in self.hgt], "mat": ["".join(r) for r in self.mat],
                "props": self.props, "exits": exits, "points": points, "lights": lights, "meta": meta}


LEGEND = {"s": "stone", ".": "moss_floor", ",": "gravel", ":": "cobble", "r": "rock_floor", "=": "stairs",
          "#": "plank", "m": "moss_deep", "~": "water", "d": "mud", "b": "basalt", "k": "blackstone",
          "a": "ash", "n": "sand"}


# ----------------------------------------------------------------------------------------
# Sallow: a settlement built inside Station 11's pump hall. Twelve people, three pumps,
# a garden of pale fungus, a river, and a wall of chalk.
# ----------------------------------------------------------------------------------------
def build_sallow():
    L = Level(40, 28, "s")
    L.walls(5)
    L.opening(0, 13, 15)
    L.opening(39, 10, 12)
    # The pump gallery along the back wall (raised), with stairs down to the plaza.
    L.H(3, 2, 36, 5, "2")
    L.M(3, 2, 36, 5, "r")
    L.H(18, 6, 21, 6, "1")
    L.M(18, 6, 21, 6, "=")
    # The plaza, paths, garden.
    L.M(10, 8, 30, 20, ":")
    L.M(1, 13, 10, 15, ",")
    L.M(30, 10, 38, 12, ",")
    L.M(6, 17, 14, 22, "d")
    L.M(30, 13, 32, 22, ",")
    # The river the pumps lift, along the south, with a plank bridge.
    for x in range(2, 38):
        for z in range(24, 27):
            L.hgt[z][x] = "~"
            L.mat[z][x] = "~"
    L.H(19, 24, 20, 26, "0")
    L.M(19, 24, 20, 26, "#")
    L.M(1, 27, 38, 27, ".")
    L.M(1, 23, 38, 23, ".")

    P = L.P
    for px in (4, 10, 26, 32):
        P("deep_pump", px, 2, size=[4, 3], block=True)
    P("knock_wall", 16, 2, size=[7, 1], block=True)
    P("house", 27, 13, size=[7, 5], variant="sallow_hall", door=[30, 17], block=True)
    P("house", 3, 7, size=[4, 4], variant="shack_pell", door=[4, 10], block=True)
    P("house", 33, 17, size=[4, 4], variant="shack_wren", door=[34, 20], block=True)
    P("house", 2, 17, size=[4, 4], variant="shack_tolley", door=[3, 20], block=True)
    P("table", 16, 12, size=[6, 1], block=True)
    P("bench_seat", 16, 11, size=[6, 1])
    P("bench_seat", 16, 13, size=[6, 1])
    P("cookfire_pit", 19, 16, block=True)
    for (x, z) in [(9, 9), (25, 9), (9, 19), (26, 20), (35, 13), (15, 7), (24, 7)]:
        P("porch_lamp", x, z, block=True)
    for (x, z) in [(7, 18), (10, 21), (13, 18)]:
        P("pale_fungus", x, z, block=True)
    for (x, z) in [(8, 20), (11, 18), (12, 21), (7, 22), (14, 20), (9, 17)]:
        P("pale_fungus_small", x, z, deco=True)
    P("crate", 24, 12, block=True)
    P("barrel", 25, 12, block=True)
    P("crate_stack", 8, 12, block=True)
    P("pipe_pile", 36, 8, block=True)
    P("gear_pile", 14, 8)
    P("heart_door", 38, 10, size=[1, 3], block=True)
    P("signpost", 6, 14, text="SALLOW · STN 11")
    P("bedroll", 36, 21)
    P("bench_seat", 34, 21, size=[2, 1])
    for (x, z, s) in [(3, 27, 1.3), (12, 27, 1.0), (27, 27, 1.4), (35, 27, 1.1), (1, 24, 0.9)]:
        P("stalagmite", x, z, scale=s, block=True)
    for (x, z) in [(5, 23), (16, 23), (24, 23), (31, 23), (36, 23)]:
        P("reed", x, z, deco=True)

    exits = [{"x": 0, "z": 14, "to": "up", "arrive": [2, 14]},
             {"x": 39, "z": 11, "to": "down", "arrive": [37, 11]}]
    points = {"arrival": [2, 14], "hub": [20, 14], "pell": [20, 4], "pell_home": [4, 11],
              "wren_porch": [35, 21], "wren_home": [34, 20], "tolley": [10, 19], "tolley_home": [3, 21],
              "table": [19, 13], "fire": [19, 17], "archive": [30, 18], "heart_door": [37, 11],
              "gallery": [12, 5], "pumps": [8, 5], "bridge": [19, 25], "commons": [20, 14]}
    lights = [{"x": 20.0, "z": 25.0, "y": 0.6, "color": "glow", "energy": 0.8, "range": 12.0, "kind": "glow"},
              {"x": 30.5, "z": 16.0, "y": 2.0, "color": "amber", "energy": 1.2, "range": 6.0, "kind": "window"}]
    return L.out("sallow", "station", LEGEND, exits, points, lights,
                 {"name": "Sallow", "ceiling": 13.0, "station": 11})


# ----------------------------------------------------------------------------------------
# The Heart: the Bellows, a pit, a bridge and a console.
# ----------------------------------------------------------------------------------------
def build_heart():
    L = Level(36, 30, "b")
    L.walls(9)
    L.opening(0, 15, 17)
    L.opening(35, 15, 17)
    L.M(2, 2, 33, 10, "r")
    for z in range(12, 15):
        for x in range(6, 30):
            L.hgt[z][x] = "~"
            L.mat[z][x] = "~"
    L.H(17, 12, 18, 14, "0")
    L.M(17, 12, 18, 14, "#")
    L.H(13, 15, 22, 19, "1")
    L.M(13, 15, 22, 19, "r")
    L.M(2, 11, 33, 11, "#")
    L.M(1, 16, 12, 16, ",")
    L.M(23, 16, 34, 16, ",")
    P = L.P
    P("bellows", 10, 2, size=[16, 9], block=True)
    P("console", 17, 16, size=[2, 1], block=True)
    for (x, z) in [(5, 8), (30, 8)]:
        P("pipe_pile", x, z, block=True)
    for (x, z) in [(4, 12), (31, 12), (8, 22), (27, 22)]:
        P("work_lamp", x, z, block=True)
    for (x, z) in [(3, 25), (32, 25), (12, 26), (24, 26)]:
        P("glow_crystal", x, z, block=True)
    P("gear_pile", 6, 19)
    P("gear_pile", 29, 20)
    for (x, z, s) in [(4, 29, 1.4), (14, 29, 1.0), (22, 29, 1.2), (31, 29, 1.5)]:
        P("stalagmite", x, z, scale=s, block=True)
    exits = [{"x": 0, "z": 16, "to": "up", "arrive": [2, 16]},
             {"x": 35, "z": 16, "to": "down", "arrive": [33, 16]}]
    points = {"arrival": [2, 16], "hub": [18, 23], "console": [18, 17], "g_barnaby": [15, 18],
              "g_hesper": [21, 18], "g_odile": [14, 20], "g_mags": [22, 20], "g_grist": [11, 22],
              "g_pell": [24, 22], "g_wren": [16, 20], "g_tolley": [20, 21], "commons": [18, 23]}
    lights = [{"x": 18.0, "z": 13.0, "y": 0.4, "color": "violet", "energy": 1.0, "range": 12.0, "kind": "glow"}]
    return L.out("heart", "heart", LEGEND, exits, points, lights, {"name": "The Heart", "ceiling": 16.0})


# ----------------------------------------------------------------------------------------
# The Knapper Ways: a carved hall where the Old Stone sits and listens.
# ----------------------------------------------------------------------------------------
def build_ways():
    L = Level(34, 26, "k")
    L.walls(3)
    L.opening(0, 11, 13)
    L.H(12, 3, 21, 6, "1")
    L.M(12, 3, 21, 6, "s")
    L.M(1, 11, 33, 13, "s")
    P = L.P
    P("stone_seat", 15, 3, size=[3, 2], block=True)
    for z in (8, 17):
        for x in (6, 10, 14, 19, 23, 27):
            P("pillar", x, z, block=True)
    for (x, z) in [(4, 4), (29, 4), (4, 21), (29, 21), (16, 23)]:
        P("glow_crystal", x, z, block=True)
    P("knock_wall", 24, 2, size=[5, 1], block=True)
    for (x, z) in [(8, 13), (25, 19), (12, 22)]:
        P("rubble_small", x, z, deco=True)
    for (x, z, s) in [(3, 25, 1.2), (15, 25, 1.0), (28, 25, 1.4)]:
        P("stalagmite", x, z, scale=s, block=True)
    exits = [{"x": 0, "z": 12, "to": "up", "arrive": [2, 12]}]
    points = {"arrival": [2, 12], "hub": [16, 12], "old_stone": [16, 7], "mural": [26, 4], "commons": [16, 12]}
    lights = [{"x": 16.5, "z": 5.0, "y": 2.0, "color": "glow", "energy": 1.0, "range": 8.0, "kind": "glow"}]
    return L.out("ways", "knapper", LEGEND, exits, points, lights, {"name": "The Knapper Ways", "ceiling": 12.0})


def preview(m, path):
    cols = {"stone": (90, 88, 98), "moss_floor": (52, 74, 48), "gravel": (110, 104, 96), "cobble": (130, 120, 104),
            "rock_floor": (70, 68, 78), "stairs": (150, 140, 120), "plank": (120, 90, 60), "moss_deep": (60, 90, 56),
            "water": (40, 70, 110), "mud": (80, 62, 46), "basalt": (56, 52, 62), "blackstone": (48, 46, 56)}
    w, d = len(m["height"][0]), len(m["height"])
    im = Image.new("RGB", (w * 12, d * 12), (20, 18, 24))
    dr = ImageDraw.Draw(im)
    for z in range(d):
        for x in range(w):
            h = m["height"][z][x]
            ch = m["mat"][z][x]
            c = (24, 22, 28) if h == "W" else cols.get(m["legend"].get(ch, "stone"), (90, 90, 90))
            if h not in ("W", "~", "0") and h.isdigit():
                c = tuple(min(255, v + int(h) * 12) for v in c)
            dr.rectangle([x * 12, z * 12, x * 12 + 11, z * 12 + 11], fill=c)
    for p in m["props"]:
        sz = p.get("size", [1, 1])
        col = (200, 150, 80) if p["type"] == "house" else (160, 160, 180)
        dr.rectangle([p["x"] * 12 + 2, p["z"] * 12 + 2, (p["x"] + sz[0]) * 12 - 3, (p["z"] + sz[1]) * 12 - 3], outline=col)
    for k, (x, z) in m["points"].items():
        dr.ellipse([x * 12 + 3, z * 12 + 3, x * 12 + 9, z * 12 + 9], fill=(86, 224, 212))
    im.save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    for build in (build_sallow, build_heart, build_ways):
        m = build()
        with open(os.path.join(OUT, m["id"] + ".json"), "w") as f:
            json.dump(m, f, indent=1)
        preview(m, os.path.join(os.path.dirname(__file__), "preview_%s.png" % m["id"]))
    print("wrote data/maps: sallow, heart, ways")


if __name__ == "__main__":
    main()
