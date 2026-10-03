"""Terrain / building / strata tile atlas (16 px tiles) for Bellows.

Outputs assets/textures/terrain.png, terrain_emit.png and terrain.json (name -> [col, row]).
Each tile is seamless (periodic noise) and uses 3-5 colours from hue-shifted ramps.
"""
import zlib
import json
import math
import os

from px import Canvas, TEX, pal, shade, ramp, mix, fbm, value_noise, dither_pick, rng, hexc

T = 16
COLS = 16
atlas = Canvas(COLS * T, COLS * T)
emit = Canvas(COLS * T, COLS * T, (0, 0, 0, 255))
index = {}
_slot = [0]


def new_tile(name):
    i = _slot[0]
    _slot[0] += 1
    cx, cy = (i % COLS), (i // COLS)
    index[name] = [cx, cy]
    return cx * T, cy * T


def put(name, tile, glow=None):
    ox, oy = new_tile(name)
    for y in range(T):
        for x in range(T):
            atlas.set(ox + x, oy + y, tile.get(x, y))
            if glow is not None:
                g = glow.get(x, y)
                if g[3] > 0:
                    emit.set(ox + x, oy + y, g)


def noise_fill(base, seed, spread=0.32, steps=4, contrast=1.0, period=T, octaves=3):
    c = Canvas(T, T)
    cols = ramp(base, steps, spread)
    for y in range(T):
        for x in range(T):
            n = fbm(x, y, period, seed, octaves)
            n = 0.5 + (n - 0.5) * contrast
            c.set(x, y, dither_pick(cols, max(0.0, min(1.0, n)), x, y))
    return c


def wrap(c, x, y, col):
    c.set(x % T, y % T, col)


# --- floors ------------------------------------------------------------------------------------
def moss(seed, deep=False):
    base = pal("moss_dark") if not deep else mix(pal("moss_dark"), pal("verdigris"), 0.35)
    c = noise_fill(shade(base, -0.08), seed, 0.3, 4, 1.25)
    r = rng(seed)
    # Muted greens: the grove's colour should come from glowroot light, not lime moss.
    light = mix(pal("moss"), pal("moss_dark"), 0.3) if not deep else mix(pal("moss"), pal("glow_dark"), 0.25)
    tip = mix(pal("moss_light"), pal("moss"), 0.55) if not deep else mix(pal("moss_light"), pal("glow"), 0.3)
    for _ in range(9 if not deep else 12):
        x, y = r.randrange(T), r.randrange(T)
        for dx, dy in [(0, 0), (1, 0), (0, 1), (-1, 0)]:
            wrap(c, x + dx, y + dy, light)
        wrap(c, x, y - 1, tip)
        wrap(c, x + 1, y + 1, shade(base, -0.25))
    if deep:
        g = Canvas(T, T)
        for _ in range(3):
            x, y = r.randrange(T), r.randrange(T)
            wrap(c, x, y, pal("glow"))
            g.set(x % T, y % T, shade(pal("glow"), -0.3))
        return c, g
    for _ in range(2):
        x, y = r.randrange(T), r.randrange(T)
        wrap(c, x, y, pal("earth"))
    return c, None


def gravel(seed):
    c = noise_fill(shade(pal("earth"), -0.1), seed, 0.22, 3, 0.8)
    r = rng(seed)
    stones = [pal("stone"), pal("ash"), shade(pal("slate"), 0.15), pal("clay")]
    for _ in range(22):
        x, y = r.randrange(T), r.randrange(T)
        s = stones[r.randrange(len(stones))]
        wrap(c, x, y, s)
        wrap(c, x + 1, y, shade(s, -0.25))
        if r.random() < 0.5:
            wrap(c, x, y - 1, shade(s, 0.3))
    return c


def cobble(seed):
    c = Canvas(T, T)
    r = rng(seed)
    mortar = shade(pal("basalt"), -0.1)
    pts = [(r.randrange(T), r.randrange(T)) for _ in range(7)]
    tones = [shade(pal("stone"), r.uniform(-0.12, 0.1)) for _ in pts]
    for y in range(T):
        for x in range(T):
            best, second, bi = 1e9, 1e9, 0
            for i, (px_, py_) in enumerate(pts):
                dx = min(abs(x - px_), T - abs(x - px_))
                dy = min(abs(y - py_), T - abs(y - py_))
                d = math.hypot(dx * 1.1, dy)
                if d < best:
                    second, best, bi = best, d, i
                elif d < second:
                    second = d
            if second - best < 1.15:
                c.set(x, y, mortar)
            else:
                base = tones[bi]
                # light from the upper left
                px_, py_ = pts[bi]
                ddx = ((x - px_ + T // 2) % T) - T // 2
                ddy = ((y - py_ + T // 2) % T) - T // 2
                t = -(ddx + ddy) / 6.0
                col = shade(base, 0.18) if t > 0.55 else (shade(base, -0.18) if t < -0.6 else base)
                c.set(x, y, col)
    return c


def soil(seed, tilled=False, wet=False):
    base = shade(pal("earth"), -0.05) if not wet else shade(pal("earth"), -0.32)
    c = noise_fill(base, seed, 0.25, 4, 1.1)
    r = rng(seed)
    if tilled:
        for y in range(T):
            ridge = y % 4
            for x in range(T):
                if ridge == 0:
                    c.set(x, y, shade(base, -0.35))
                elif ridge == 1:
                    c.set(x, y, shade(base, 0.12 if not wet else 0.05))
    for _ in range(8):
        x, y = r.randrange(T), r.randrange(T)
        wrap(c, x, y, shade(base, 0.22 if not wet else 0.1))
        wrap(c, x + 1, y + 1, shade(base, -0.3))
    if wet:
        for _ in range(3):
            x, y = r.randrange(T), r.randrange(T)
            wrap(c, x, y, mix(base, pal("water_light"), 0.35))
    return c


def rock_floor(seed, base=None, cracks=4):
    base = base or shade(pal("slate"), 0.05)
    c = noise_fill(base, seed, 0.2, 4, 1.0)
    r = rng(seed)
    for _ in range(cracks):
        x, y = r.randrange(T), r.randrange(T)
        for k in range(r.randint(3, 6)):
            wrap(c, x, y, shade(base, -0.45))
            x += r.choice([1, 1, 0])
            y += r.choice([0, 1, 1, -1])
    for _ in range(4):
        x, y = r.randrange(T), r.randrange(T)
        wrap(c, x, y, shade(base, 0.25))
    return c


def planks(seed, base=None, vertical=False):
    base = base or shade(pal("clay"), -0.05)
    c = Canvas(T, T)
    r = rng(seed)
    for row in range(4):
        tone = shade(base, r.uniform(-0.12, 0.1))
        offset = r.randrange(T)
        for yy in range(4):
            for x in range(T):
                y = row * 4 + yy
                col = tone
                if yy == 0:
                    col = shade(tone, -0.42)
                elif yy == 1:
                    col = shade(tone, 0.12)
                elif (x + offset) % 13 == 0:
                    col = shade(tone, -0.42)
                elif value_noise(x * 3, y, T * 3, seed + row, 2) > 0.72:
                    col = shade(tone, -0.12)
                if vertical:
                    c.set(y, x, col)
                else:
                    c.set(x, y, col)
        if r.random() < 0.8:
            nx = (offset + 3) % T
            for nail in (nx, (nx + 7) % T):
                if vertical:
                    c.set(row * 4 + 2, nail, pal("brass_dark"))
                else:
                    c.set(nail, row * 4 + 2, pal("brass_dark"))
    return c


def brick(seed, base=None, rows=4):
    base = base or mix(pal("clay"), pal("danger"), 0.18)
    c = Canvas(T, T)
    r = rng(seed)
    mortar = shade(pal("ash"), -0.2)
    bh = T // rows
    for row in range(rows):
        off = 0 if row % 2 == 0 else 4
        for y in range(row * bh, row * bh + bh):
            for x in range(T):
                if y == row * bh or (x + off) % 8 == 0:
                    c.set(x, y, mortar)
                else:
                    t = fbm(x, y, T, seed, 2)
                    brick_id = ((x + off) // 8) + row * 3
                    tone = shade(base, (_rh(brick_id, seed) - 0.5) * 0.25)
                    col = tone
                    if y == row * bh + 1:
                        col = shade(tone, 0.15)
                    elif y == row * bh + bh - 1:
                        col = shade(tone, -0.18)
                    if t > 0.72:
                        col = shade(col, -0.15)
                    c.set(x, y, col)
    return c


def _rh(i, s):
    return rng(i * 977 + s).random()


def stone_block(seed, base=None):
    base = base or pal("stone")
    c = Canvas(T, T)
    mortar = shade(pal("basalt"), -0.05)
    for y in range(T):
        for x in range(T):
            row = y // 8
            off = 0 if row % 2 == 0 else 8
            if y % 8 == 0 or (x + off) % 16 == 0:
                c.set(x, y, mortar)
            else:
                t = fbm(x, y, T, seed, 3)
                col = dither_pick(ramp(base, 4, 0.22), t, x, y)
                if y % 8 == 1:
                    col = shade(col, 0.12)
                if y % 8 == 7:
                    col = shade(col, -0.15)
                c.set(x, y, col)
    return c


def water_tile(seed):
    c = Canvas(T, T)
    cols = ramp(mix(pal("water"), pal("basalt"), 0.45), 3, 0.25)
    for y in range(T):
        for x in range(T):
            c.set(x, y, dither_pick(cols, fbm(x, y, T, seed, 2), x, y))
    return c


def vent(seed):
    c = rock_floor(seed, pal("basalt"), 2)
    g = Canvas(T, T)
    r = rng(seed)
    for k in range(3):
        x, y = r.randrange(3, 13), r.randrange(3, 13)
        for i in range(5):
            col = pal("ember") if i % 2 == 0 else pal("amber")
            c.set(x, y, col)
            g.set(x, y, shade(pal("ember"), -0.1))
            x = (x + r.choice([-1, 0, 1])) % T
            y = (y + 1) % T
    return c, g


# --- sides (cliffs) ------------------------------------------------------------------------------
def rock_side(seed, base=None, crystals=False):
    base = base or shade(pal("slate"), -0.05)
    c = Canvas(T, T)
    r = rng(seed)
    for y in range(T):
        stratum = (y + int(value_noise(0, y, T, seed, 4) * 3)) // 5
        tone = shade(base, (_rh(stratum, seed) - 0.5) * 0.3)
        for x in range(T):
            n = fbm(x * 2, y, T * 2, seed, 2)
            col = dither_pick(ramp(tone, 3, 0.2), n, x, y)
            c.set(x, y, col)
    for _ in range(3):
        x, y = r.randrange(T), r.randrange(T)
        for k in range(r.randint(3, 7)):
            wrap(c, x, y, shade(base, -0.5))
            wrap(c, x + 1, y, shade(base, 0.12))
            y += 1
            x += r.choice([-1, 0, 0, 1])
    g = None
    if crystals:
        g = Canvas(T, T)
        for _ in range(2):
            x, y = r.randrange(T), r.randrange(T)
            for dx, dy in [(0, 0), (0, 1), (1, 1)]:
                wrap(c, x + dx, y + dy, pal("glow") if dy == 0 else pal("glow_dark"))
                g.set((x + dx) % T, (y + dy) % T, shade(pal("glow"), -0.35))
    return c, g


def earth_side(seed, top=None):
    base = shade(pal("earth"), -0.08)
    c = noise_fill(base, seed, 0.28, 4, 1.15)
    r = rng(seed)
    for _ in range(4):  # roots
        x, y = r.randrange(T), r.randrange(4, T)
        for k in range(r.randint(3, 6)):
            wrap(c, x, y, pal("clay"))
            x += r.choice([-1, 0, 1])
            y += 1
    for _ in range(5):
        x, y = r.randrange(T), r.randrange(T)
        wrap(c, x, y, pal("stone"))
    if top is not None:  # grassy/mossy lip on the top two rows
        for x in range(T):
            depth = 2 + (1 if value_noise(x, 0, T, seed, 2) > 0.6 else 0)
            for y in range(depth):
                c.set(x, y, top if y < depth - 1 else shade(top, -0.3))
    return c


def level_mean(c, target):
    """Shift a tile so its mean luminance matches `target`'s: variants then tile without
    reading as a checkerboard from across the cross-section."""
    def lum(col):
        return 0.299 * col[0] + 0.587 * col[1] + 0.114 * col[2]
    px = [c.get(x, y) for y in range(c.h) for x in range(c.w)]
    mean = sum(lum(p) for p in px) / len(px)
    d = lum(target) - mean
    for y in range(c.h):
        for x in range(c.w):
            r, g, b, a = c.get(x, y)
            c.set(x, y, (max(0, min(255, int(r + d))), max(0, min(255, int(g + d))), max(0, min(255, int(b + d))), a))
    return c


def strata(name, seed):
    t, g = _strata(name, seed)
    if name in ("soil", "clay", "rock", "bedrock", "air_back"):
        base = {"soil": shade(pal("earth"), -0.12), "clay": shade(pal("clay"), -0.05),
                "rock": STRATA_ROCK, "bedrock": shade(pal("charcoal"), 0.12),
                "air_back": shade(pal("basalt"), -0.2)}[name]
        t = level_mean(t, base)
    return t, g


STRATA_ROCK = shade(mix(pal("slate"), pal("earth"), 0.45), 0.03)


def _strata(name, seed):
    """Undercroft cross-section materials (front faces of the cut)."""
    if name == "topsoil":
        c = earth_side(seed, top=pal("moss"))
        return c, None
    if name == "soil":
        c = noise_fill(shade(pal("earth"), -0.12), seed, 0.22, 4, 0.8)
        r = rng(seed)
        for _ in range(3):  # pebbles
            x, y = r.randrange(T), r.randrange(T)
            wrap(c, x, y, shade(pal("ash"), -0.2))
            wrap(c, x + 1, y, shade(pal("ash"), -0.35))
        return c, None
    if name == "clay":
        c = noise_fill(shade(pal("clay"), -0.05), seed, 0.22, 4, 0.9)
        for y in range(0, T, 5):
            for x in range(T):
                if value_noise(x, y, T, seed, 4) > 0.45:
                    c.set(x, y, shade(pal("clay"), -0.25))
        return c, None
    if name == "rock":
        return rock_side(seed, STRATA_ROCK)
    if name == "brick":
        return brick(seed, shade(mix(pal("clay"), pal("danger"), 0.22), -0.12)), None
    if name == "stone":
        return stone_block(seed, shade(pal("stone"), 0.05)), None
    if name == "metal":
        c = Canvas(T, T)
        cols = ramp(pal("brass_dark"), 4, 0.3)
        for y in range(T):
            for x in range(T):
                c.set(x, y, dither_pick(cols, 0.35 + 0.3 * fbm(x, y, T, seed, 2), x, y))
        for x, y in [(2, 2), (13, 2), (2, 13), (13, 13)]:
            c.set(x, y, pal("brass_light"))
            c.set(x + 1, y + 1, shade(pal("brass_dark"), -0.4))
        return c, None
    if name == "insulation":
        c = Canvas(T, T)
        for y in range(T):
            for x in range(T):
                band = (x + y) % 6 < 3
                c.set(x, y, shade(pal("moss_light"), -0.25 if band else -0.4))
        return c, None
    if name == "bedrock":
        c, _ = rock_side(seed, shade(mix(pal("charcoal"), pal("slate"), 0.45), 0.02))
        return c, None
    if name == "ember":
        c, _ = rock_side(seed, shade(mix(pal("basalt"), pal("danger"), 0.18), 0.04))
        g = Canvas(T, T)
        r = rng(seed)
        for _ in range(3):  # continuous glowing veins that run off the tile edges
            x, y = r.randrange(T), r.randrange(T)
            dx = r.choice([-1, 1])
            for k in range(T + 4):
                col = pal("ember") if k % 4 else pal("amber_light")
                wrap(c, x, y, col)
                g.set(x % T, y % T, shade(col, -0.15))
                wrap(c, x, y + 1, shade(mix(pal("basalt"), pal("ember"), 0.45), -0.1))
                x += dx
                if r.random() < 0.35:
                    y += r.choice([-1, 1])
        return c, g
    if name == "seal":
        c = noise_fill(shade(pal("sour"), -0.35), seed, 0.25, 4, 1.2)
        r = rng(seed)
        for _ in range(6):
            x, y = r.randrange(T), r.randrange(T)
            wrap(c, x, y, pal("sour"))
        return c, None
    if name == "air_back":
        c = noise_fill(shade(pal("basalt"), -0.25), seed, 0.18, 3, 0.9)
        return c, None
    raise ValueError(name)


# --- building surfaces ---------------------------------------------------------------------------
def roof_slate(seed, base=None):
    base = base or shade(pal("slate"), -0.05)
    c = Canvas(T, T)
    for y in range(T):
        row = y // 4
        off = (row % 2) * 3
        for x in range(T):
            tone = shade(base, (_rh((x + off) // 6 + row * 7, seed) - 0.5) * 0.2)
            col = tone
            if y % 4 == 3:
                col = shade(tone, -0.45)
            elif y % 4 == 0:
                col = shade(tone, 0.16)
            elif (x + off) % 6 == 0:
                col = shade(tone, -0.3)
            c.set(x, y, col)
    return c


def roof_moss(seed):
    c = roof_slate(seed, shade(pal("slate"), -0.15))
    r = rng(seed)
    for _ in range(26):
        x, y = r.randrange(T), r.randrange(T)
        wrap(c, x, y, pal("moss") if r.random() < 0.6 else pal("moss_light"))
    return c


def roof_metal(seed):
    c = Canvas(T, T)
    base = mix(pal("brass_dark"), pal("danger"), 0.15)
    for y in range(T):
        for x in range(T):
            ridge = x % 4
            col = shade(base, 0.15) if ridge == 0 else (shade(base, -0.3) if ridge == 3 else base)
            if fbm(x, y, T, seed, 3) > 0.62:
                col = mix(col, pal("verdigris"), 0.45)
            c.set(x, y, col)
    return c


def plaster(seed, base=None):
    base = base or shade(pal("sand"), -0.15)
    c = noise_fill(base, seed, 0.15, 3, 0.8)
    r = rng(seed)
    for _ in range(3):
        x, y = r.randrange(T), r.randrange(T)
        for k in range(r.randint(2, 5)):
            wrap(c, x, y, shade(base, -0.3))
            x += 1
            y += r.choice([0, 1])
    return c


def window(lit):
    c = Canvas(T, T)
    frame = shade(pal("clay"), -0.3)
    c.rect(0, 0, T, T, frame)
    glass = pal("amber_light") if lit else shade(pal("basalt"), 0.05)
    g = Canvas(T, T)
    for y in range(2, 14):
        for x in range(2, 14):
            if x in (7, 8) or y in (7, 8):
                c.set(x, y, shade(frame, 0.1))
            else:
                col = glass if not lit else (pal("cream") if (x + y) % 9 == 0 else glass)
                c.set(x, y, col)
                if lit:
                    g.set(x, y, shade(pal("amber"), -0.05))
    c.hline(1, 14, 14, shade(frame, 0.25))
    return c, (g if lit else None)


def door(seed):
    c = planks(seed, shade(pal("clay"), -0.25), vertical=True)
    for y in range(T):
        c.set(0, y, shade(pal("clay"), -0.55))
        c.set(T - 1, y, shade(pal("clay"), -0.55))
    c.set(11, 8, pal("brass_light"))
    c.set(11, 9, pal("brass_dark"))
    return c


def build():
    # Floors (top faces)
    for i in range(4):
        t, g = moss(10 + i)
        put(f"moss_floor_{i}", t, g)
    for i in range(2):
        t, g = moss(20 + i, deep=True)
        put(f"moss_deep_{i}", t, g)
    for i in range(3):
        put(f"gravel_{i}", gravel(30 + i))
    for i in range(3):
        put(f"cobble_{i}", cobble(40 + i))
    for i in range(2):
        put(f"farm_soil_{i}", soil(50 + i))
    for i in range(2):
        put(f"tilled_{i}", soil(55 + i, tilled=True))
    for i in range(2):
        put(f"tilled_wet_{i}", soil(58 + i, tilled=True, wet=True))
    for i in range(3):
        put(f"rock_floor_{i}", rock_floor(60 + i))
    st = rock_floor(65, shade(pal("stone"), 0.1), 1)
    for y in range(T):
        for x in range(T):
            if y % 5 == 0:
                st.set(x, y, shade(pal("stone"), -0.4))
            elif y % 5 == 1:
                st.set(x, y, shade(pal("stone"), 0.25))
    put("stairs_0", st)
    for i in range(2):
        put(f"plank_{i}", planks(70 + i))
    for i in range(2):
        put(f"dirt_{i}", soil(75 + i))
    for i in range(3):
        put(f"blackstone_{i}", rock_floor(80 + i, shade(pal("basalt"), 0.12), 3))
    for i in range(2):
        put(f"ash_{i}", noise_fill(shade(pal("ash"), -0.25), 85 + i, 0.25, 4, 1.0))
    for i in range(2):
        put(f"basalt_{i}", rock_floor(88 + i, pal("basalt"), 5))
    for i in range(2):
        put(f"mud_{i}", soil(90 + i, wet=True))
    for i in range(2):
        put(f"stone_{i}", rock_floor(93 + i, pal("stone"), 2))
    t, g = vent(96)
    put("vent_0", t, g)
    put("water_0", water_tile(97))
    put("rock_0", rock_floor(98, shade(pal("slate"), -0.15), 3))   # wall tops
    put("sand_0", noise_fill(shade(pal("sand"), -0.1), 99, 0.2, 3, 0.9))
    # Sides
    for i in range(3):
        t, _ = rock_side(100 + i)
        put(f"side_rock_{i}", t)
    for i in range(2):
        t, g = rock_side(105 + i, crystals=True)
        put(f"side_rock_glint_{i}", t, g)
    for i in range(2):
        put(f"side_earth_{i}", earth_side(110 + i, top=pal("moss")))
    put("side_earth_plain", earth_side(113))
    put("side_plank", planks(114, shade(pal("clay"), -0.2), vertical=True))
    t, _ = rock_side(115, pal("basalt"))
    put("side_basalt", t)
    t, _ = rock_side(116, shade(pal("basalt"), 0.1))
    put("side_blackstone", t)
    put("side_mud", earth_side(117))
    # Strata (cross-section)
    for name in ["topsoil", "soil", "clay", "rock", "brick", "stone", "metal", "insulation", "bedrock", "ember", "seal", "air_back"]:
        for i in range(2):
            t, g = strata(name, 200 + zlib.crc32(name.encode()) % 97 + i * 13)
            put(f"strata_{name}_{i}", t, g)
    # Building surfaces
    for i in range(2):
        put(f"wall_plank_{i}", planks(300 + i, shade(pal("clay"), -0.12), vertical=True))
    for i in range(2):
        put(f"wall_brick_{i}", brick(310 + i))
    for i in range(2):
        put(f"wall_stone_{i}", stone_block(320 + i))
    for i in range(2):
        put(f"wall_plaster_{i}", plaster(330 + i))
    put("wall_brick_dark_0", brick(340, shade(mix(pal("clay"), pal("danger"), 0.2), -0.25)))
    put("roof_slate_0", roof_slate(350))
    put("roof_moss_0", roof_moss(351))
    put("roof_metal_0", roof_metal(352))
    put("roof_slate_dark_0", roof_slate(353, shade(mix(pal("violet_dark"), pal("slate"), 0.55), -0.18)))
    t, g = window(True)
    put("window_lit_0", t, g)
    t, _ = window(False)
    put("window_dark_0", t)
    put("door_0", door(360))
    put("beam_0", planks(361, shade(pal("clay"), -0.4)))
    put("floorboard_0", planks(362, shade(pal("sand"), -0.3)))
    rug = Canvas(T, T)
    for y in range(T):
        for x in range(T):
            b = min(x, y, T - 1 - x, T - 1 - y)
            col = pal("violet_dark") if b == 1 else (shade(pal("danger"), -0.35) if b > 1 else shade(pal("violet_dark"), -0.3))
            if b > 2 and (x + y) % 4 == 0:
                col = pal("amber")
            rug.set(x, y, col)
    put("rug_0", rug)
    metal = Canvas(T, T)
    cols = ramp(pal("brass"), 4, 0.3)
    for y in range(T):
        for x in range(T):
            metal.set(x, y, dither_pick(cols, 0.3 + 0.4 * fbm(x, y, T, 370, 2), x, y))
    for x in range(0, T, 5):
        metal.set(x, 1, pal("brass_light"))
        metal.set(x, 14, pal("brass_light"))
    put("metal_brass_0", metal)
    dark = Canvas(T, T, pal("charcoal"))
    put("black_0", dark)

    atlas.save(os.path.join(TEX, "terrain.png"))
    emit.save(os.path.join(TEX, "terrain_emit.png"))
    with open(os.path.join(TEX, "terrain.json"), "w") as f:
        json.dump({"tile": T, "cols": COLS, "tiles": index}, f, indent=0)
    # Preview at 4x for review
    atlas.img.resize((atlas.w * 3, atlas.h * 3), 0).save(os.path.join(os.path.dirname(__file__), "preview_terrain.png"))
    print(f"terrain atlas: {len(index)} tiles")


if __name__ == "__main__":
    build()
