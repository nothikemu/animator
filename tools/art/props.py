"""Billboard sprites: plants, crops, stalagmites, lamps, resource nodes, clutter.

Writes assets/textures/props/<name>.png (+ <name>_emit.png for glowing parts) and
assets/textures/props/props.json with frame sizes.  Organic shapes are drawn with
seeded procedural rules and then hand-tuned by parameters; every sprite gets a
selective outline and palette-locked hue-shifted ramps.
"""
import json
import math
import os

from px import Canvas, TEX, pal, shade, ramp, mix, rng, fbm, dither_pick

OUT = os.path.join(TEX, "props")
manifest = {}


def save(name, canvas, glow=None, frames=1):
    os.makedirs(OUT, exist_ok=True)
    canvas.save(os.path.join(OUT, name + ".png"))
    if glow is not None:
        glow.save(os.path.join(OUT, name + "_emit.png"))
    manifest[name] = {"w": canvas.w // frames, "h": canvas.h, "frames": frames, "emit": glow is not None}


def blank(w, h):
    return Canvas(w, h)


# --- organic helpers ------------------------------------------------------------------------
def bezier(p0, p1, p2, t):
    a = (1 - t) * (1 - t)
    b = 2 * (1 - t) * t
    c = t * t
    return (a * p0[0] + b * p1[0] + c * p2[0], a * p0[1] + b * p1[1] + c * p2[1])


def stroke(c, pts, r0, r1, colors, light_dir=-1):
    """Thick tapered stroke along points; shaded left-light / right-shadow."""
    n = len(pts)
    for i, (x, y) in enumerate(pts):
        r = r0 + (r1 - r0) * (i / max(1, n - 1))
        for yy in range(int(y - r - 1), int(y + r + 2)):
            for xx in range(int(x - r - 1), int(x + r + 2)):
                d = (xx + 0.5 - x) / max(r, 0.01)
                dy = (yy + 0.5 - y) / max(r, 0.01)
                if d * d + dy * dy <= 1.0:
                    if d * light_dir > 0.35:
                        col = colors[2]
                    elif d * light_dir < -0.45:
                        col = colors[0]
                    else:
                        col = colors[1]
                    c.set(xx, yy, col)


def glow_dot(c, g, x, y, r, core, rim, glowcol):
    for yy in range(int(y - r - 1), int(y + r + 2)):
        for xx in range(int(x - r - 1), int(x + r + 2)):
            d = math.hypot(xx + 0.5 - x, yy + 0.5 - y)
            if d <= r:
                col = core if d < r * 0.5 else rim
                c.set(xx, yy, col)
                g.set(xx, yy, glowcol if d < r * 0.6 else shade(glowcol, -0.45))


# --- glowroots ----------------------------------------------------------------------------------
def glowroot(seed, w=40, h=60):
    c, g = blank(w, h), blank(w, h)
    r = rng(seed)
    bark = [shade(mix(pal("violet_dark"), pal("earth"), 0.55), -0.35),
            mix(pal("violet_dark"), pal("earth"), 0.55), shade(mix(pal("violet_dark"), pal("clay"), 0.5), 0.15)]
    base_x = w / 2 + r.uniform(-2, 2)
    top = (w / 2 + r.uniform(-4, 4), h * 0.38)
    # Root flare at the base: three roots splaying into the ground.
    for dx in (-7, -3, 4, 8):
        pts = [bezier((base_x + dx * 0.3, h - 9), (base_x + dx * 0.8, h - 4), (base_x + dx, h - 1), t / 10) for t in range(11)]
        stroke(c, pts, 1.8, 0.8, bark)
    # Twisted trunk: two intertwined strands.
    for phase in (0.0, math.pi):
        pts = []
        for i in range(30):
            t = i / 29
            x = base_x + (top[0] - base_x) * t + math.sin(t * 6.0 + phase) * 1.8 * (1 - t * 0.5)
            y = (h - 6) + (top[1] - (h - 6)) * t
            pts.append((x, y))
        stroke(c, pts, 2.6, 1.6, bark)
    # Arching branches that droop with luminous bulbs.
    branches = 4 + r.randint(0, 1)
    bulbs = []
    for b in range(branches):
        side = -1 if b % 2 == 0 else 1
        spread = (6 + b * 3.2 + r.uniform(0, 3)) * side
        start = (top[0] + r.uniform(-1, 1), top[1] + r.uniform(-1, 3))
        ctrl = (start[0] + spread * 0.6, start[1] - 10 - r.uniform(0, 6))
        end = (start[0] + spread, start[1] + 2 + r.uniform(0, 6))
        pts = [bezier(start, ctrl, end, t / 16) for t in range(17)]
        stroke(c, pts, 1.4, 0.6, bark)
        # Tendrils hang from along the arch.
        for k in range(2 + r.randint(0, 2)):
            px_, py_ = bezier(start, ctrl, end, r.uniform(0.45, 1.0))
            length = r.randint(4, 12)
            for yy in range(int(py_), int(py_) + length):
                c.set(int(px_), yy, shade(pal("verdigris"), -0.3))
            bulbs.append((int(px_) + 0.5, int(py_) + length + 1.0, 1.6 if r.random() < 0.6 else 2.2))
    for (bx, by, br) in bulbs:
        glow_dot(c, g, bx, by, br, pal("cream"), pal("glow"), pal("glow"))
    # Glowing knots on the trunk.
    for k in range(3):
        y = int(h * (0.5 + 0.13 * k))
        x = int(base_x + math.sin(k * 2.1) * 1.5)
        c.set(x, y, pal("glow"))
        g.set(x, y, shade(pal("glow"), -0.2))
    c.outline(-0.6)
    return c, g


def glowroot_small(seed):
    w, h = 18, 22
    c, g = blank(w, h), blank(w, h)
    r = rng(seed)
    stem = [shade(pal("verdigris"), -0.45), shade(pal("verdigris"), -0.25), pal("verdigris")]
    for k in range(3):
        x0 = w / 2 + (k - 1) * 3
        top = (x0 + r.uniform(-3, 3), 6 + r.uniform(0, 5))
        pts = [bezier((x0, h - 1), (x0 + (k - 1) * 2, h - 8), top, t / 10) for t in range(11)]
        stroke(c, pts, 1.0, 0.6, stem)
        glow_dot(c, g, top[0], top[1] - 1, 1.7, pal("cream"), pal("glow"), pal("glow"))
    c.outline(-0.6)
    return c, g


# --- ground cover ---------------------------------------------------------------------------------
def moss_tuft(seed):
    w, h = 16, 10
    c = blank(w, h)
    r = rng(seed)
    cols = ramp(pal("moss"), 4, 0.35)
    for k in range(5):
        cx, cy, rad = r.uniform(3, 13), r.uniform(5, 8), r.uniform(2.0, 3.6)
        for y in range(h):
            for x in range(w):
                if (x + 0.5 - cx) ** 2 + ((y + 0.5 - cy) * 1.4) ** 2 <= rad * rad:
                    t = 1 - (y / h)
                    c.set(x, y, dither_pick(cols, min(1, t + r.uniform(-0.1, 0.1)), x, y))
    for k in range(4):
        x = r.randrange(2, 14)
        for y in range(h):
            if c.get(x, y)[3] > 0:
                c.set(x, y - 1, pal("moss_light"))
                break
    c.outline(-0.55)
    return c


def mushroom(seed):
    w, h = 14, 16
    c, g = blank(w, h), blank(w, h)
    r = rng(seed)
    cap = ramp(mix(pal("violet"), pal("cream"), 0.25), 3, 0.3)
    for k in range(2):
        x = 4 + k * 5 + r.randint(-1, 1)
        top = 4 + k * 3 + r.randint(0, 2)
        for y in range(top + 2, h):
            c.set(x, y, pal("cream") if y < h - 1 else shade(pal("cream"), -0.3))
            c.set(x + 1, y, shade(pal("cream"), -0.2))
        for y in range(top - 1, top + 3):
            span = 3 if y > top else 2
            for xx in range(x - span + 1, x + span + 1):
                c.set(xx, y, cap[2] if y == top - 1 else (cap[0] if y == top + 2 else cap[1]))
        for s in range(2):
            sx, sy = x - 1 + s * 2, top
            c.set(sx, sy, pal("glow"))
            g.set(sx, sy, shade(pal("glow"), -0.4))
    c.outline(-0.6)
    return c, g


def stalagmite(seed):
    w, h = 26, 60
    c = blank(w, h)
    r = rng(seed)
    base = mix(pal("stone"), pal("violet_dark"), 0.25)
    cols = ramp(base, 5, 0.42)
    tip_x = w / 2 + r.uniform(-3, 3)
    for y in range(h):
        t = y / (h - 1)
        half = 1 + (w / 2 - 2) * (t ** 1.4)
        cx = tip_x + (w / 2 - tip_x) * t
        for x in range(w):
            d = (x + 0.5 - cx) / max(half, 0.5)
            if abs(d) <= 1.0:
                band = math.sin(y * 0.55 + fbm(x, y, 64, seed) * 3.0) * 0.12
                v = 0.5 - d * 0.45 + band
                c.set(x, y, dither_pick(cols, max(0, min(1, v)), x, y))
    # wet highlight streaks
    for k in range(3):
        x = int(tip_x - 2 + k * 2)
        for y in range(r.randint(6, 18), r.randint(30, 50)):
            if c.get(x, y)[3] > 0 and r.random() < 0.75:
                c.set(x, y, shade(base, 0.45))
    c.outline(-0.62)
    return c


def shore_rock(seed):
    w, h = 26, 18
    c = blank(w, h)
    r = rng(seed)
    cols = ramp(mix(pal("slate"), pal("verdigris"), 0.15), 4, 0.4)
    blobs = [(r.uniform(6, 20), r.uniform(9, 14), r.uniform(4, 8)) for _ in range(3)]
    for y in range(h):
        for x in range(w):
            inside = any(((x + 0.5 - bx) / br) ** 2 + ((y + 0.5 - by) / (br * 0.75)) ** 2 <= 1 for bx, by, br in blobs)
            if inside:
                v = 1.0 - y / h * 0.9 + (fbm(x, y, 32, seed) - 0.5) * 0.4
                c.set(x, y, dither_pick(cols, max(0, min(1, v)), x, y))
    for x in range(w):  # wet line at the bottom
        for y in range(h - 1, -1, -1):
            if c.get(x, y)[3] > 0:
                c.set(x, y, shade(pal("water"), -0.35))
                break
    c.outline(-0.6)
    return c


def rubble(seed, w=32, h=26, n=9):
    c = blank(w, h)
    r = rng(seed)
    cols = ramp(pal("stone"), 4, 0.4)
    for k in range(n):
        bx, by, br = r.uniform(5, w - 5), r.uniform(h * 0.35, h - 4), r.uniform(3, 6)
        for y in range(h):
            for x in range(w):
                d = ((x + 0.5 - bx) / br) ** 2 + ((y + 0.5 - by) / (br * 0.8)) ** 2
                if d <= 1:
                    v = 0.75 - (x - bx) / br * 0.25 - (y - by) / br * 0.25
                    c.set(x, y, dither_pick(cols, max(0, min(1, v)), x, y))
    c.outline(-0.6)
    return c


# --- lamps & clutter ----------------------------------------------------------------------------
def lamp_post(height=40, lantern=True, kind="town"):
    w = 14
    c, g = blank(w, height), blank(w, height)
    iron = shade(pal("basalt"), 0.15)
    for y in range(8, height):
        c.set(6, y, iron)
        c.set(7, y, shade(iron, -0.3))
    c.rect(4, height - 3, 6, 3, shade(pal("stone"), -0.1))
    c.hline(5, 10, 8, iron)
    if lantern:
        brass = pal("brass")
        c.rect(3, 1, 7, 1, brass)
        for y in range(2, 9):
            c.set(3, y, brass)
            c.set(9, y, shade(brass, -0.3))
            for x in range(4, 9):
                col = pal("amber_light") if kind == "town" else pal("glow")
                if y in (2, 8):
                    col = pal("amber") if kind == "town" else pal("glow_dark")
                c.set(x, y, col)
                g.set(x, y, shade(col, -0.1))
        c.set(6, 0, brass)
    c.outline(-0.6)
    return c, g


def barrel_jars():
    w, h = 18, 22
    c, g = blank(w, h), blank(w, h)
    cols = [pal("glow_dark"), pal("moss_light"), pal("violet"), pal("amber")]
    for i, (x, y) in enumerate([(2, 8), (7, 6), (12, 9), (4, 15), (10, 15)]):
        col = cols[i % len(cols)]
        c.rect(x, y, 4, 5, shade(pal("cream"), -0.25))
        c.rect(x + 1, y + 1, 2, 3, col)
        c.hline(x, x + 3, y - 1, pal("brass_dark"))
        if i % 2 == 0:
            g.rect(x + 1, y + 1, 2, 3, shade(col, -0.35))
    c.outline(-0.6)
    return c, g


def gear_pile():
    w, h = 20, 12
    c = blank(w, h)
    for (x, y, rr) in [(6, 7, 4), (13, 8, 3), (10, 5, 2.5)]:
        c.disc(x, y, rr, pal("brass"))
        c.disc(x, y, rr * 0.45, shade(pal("brass"), -0.4))
        for k in range(8):
            a = k / 8 * math.tau
            c.set(int(x + math.cos(a) * (rr + 1)), int(y + math.sin(a) * (rr + 1)), shade(pal("brass"), 0.2))
    c.outline(-0.6)
    return c


def harness():
    w, h = 18, 10
    c = blank(w, h)
    rope = pal("sand")
    c.line(1, 7, 16, 6, rope)
    c.line(2, 8, 12, 3, shade(rope, -0.2))
    c.disc(13, 4, 2.2, pal("brass"))
    c.disc(13, 4, 1.0, (0, 0, 0, 0))
    c.rect(4, 6, 5, 3, shade(pal("clay"), -0.3))
    c.outline(-0.55)
    return c


# --- resources --------------------------------------------------------------------------------
def crystal_cluster(seed, color, w=18, h=22, emit=True):
    c, g = blank(w, h), blank(w, h)
    r = rng(seed)
    base = rock_base(c, seed, w, h, 6)
    for k in range(4):
        x = r.uniform(4, w - 4)
        top = r.uniform(2, h * 0.55)
        width = r.uniform(1.5, 2.8)
        for y in range(int(top), h - 4):
            t = (y - top) / max(1, (h - 4 - top))
            half = width * min(1.0, t * 2 + 0.3)
            for xx in range(int(x - half), int(x + half) + 1):
                col = shade(color, 0.35) if xx < x else (color if xx == int(x) else shade(color, -0.3))
                if y == int(top):
                    col = pal("cream")
                c.set(xx, y, col)
                if emit:
                    g.set(xx, y, shade(color, -0.25))
    c.outline(-0.6)
    return c, g


def rock_base(c, seed, w, h, height):
    cols = ramp(pal("basalt"), 4, 0.35)
    for y in range(h - height, h):
        for x in range(1, w - 1):
            if abs(x - w / 2) < (w / 2 - 1) * (0.6 + 0.4 * (y - (h - height)) / height):
                c.set(x, y, dither_pick(cols, 0.7 - (y - (h - height)) / height * 0.5, x, y))


def ore_node(seed, base, vein=None, w=22, h=18):
    c, g = blank(w, h), blank(w, h)
    r = rng(seed)
    cols = ramp(base, 4, 0.4)
    facets = [(r.uniform(5, w - 5), r.uniform(6, h - 4), r.uniform(4, 7)) for _ in range(4)]
    for y in range(h):
        for x in range(w):
            best = None
            for i, (fx, fy, fr) in enumerate(facets):
                d = max(abs(x + 0.5 - fx) / fr, abs(y + 0.5 - fy) / (fr * 0.85))
                if d <= 1 and (best is None or d < best[0]):
                    best = (d, i)
            if best:
                fx, fy, fr = facets[best[1]]
                v = 0.55 + (0.3 if x < fx and y < fy else (-0.25 if x > fx else 0.0))
                c.set(x, y, dither_pick(cols, max(0, min(1, v)), x, y))
    if vein:
        for k in range(3):
            x, y = r.randrange(4, w - 4), r.randrange(4, h - 3)
            for i in range(r.randint(3, 6)):
                if c.get(x, y)[3] > 0:
                    c.set(x, y, vein)
                    g.set(x, y, shade(vein, -0.15))
                x += r.choice([-1, 1, 0])
                y += r.choice([0, 1, -1])
    c.outline(-0.6)
    return c, (g if vein else None)


def scrap_pile(seed):
    w, h = 24, 16
    c = blank(w, h)
    r = rng(seed)
    for k in range(7):
        x0, y0 = r.randrange(2, w - 8), r.randrange(5, h - 3)
        length = r.randint(5, 10)
        col = pal("brass") if r.random() < 0.6 else pal("verdigris")
        for i in range(length):
            c.set(x0 + i, y0 - i // 3, col)
            c.set(x0 + i, y0 - i // 3 + 1, shade(col, -0.35))
    for k in range(2):
        c.disc(r.uniform(5, w - 5), r.uniform(9, 13), 2.5, shade(pal("brass"), -0.15))
    c.outline(-0.6)
    return c


def lore_page():
    w, h = 12, 14
    c, g = blank(w, h), blank(w, h)
    c.rect(2, 2, 8, 10, pal("cream"))
    for y in range(4, 11, 2):
        c.hline(3, 8, y, shade(pal("cream"), -0.4))
    c.set(9, 2, shade(pal("cream"), -0.25))
    c.rect(5, 0, 2, 2, pal("brass"))
    g.rect(2, 2, 8, 10, (60, 52, 36, 255))
    c.outline(-0.55)
    return c, g


def crate(seed, broken=False):
    w, h = 18, 16
    c = blank(w, h)
    wood = ramp(shade(pal("clay"), -0.1), 3, 0.3)
    for y in range(2, h):
        for x in range(1, w - 1):
            col = wood[1]
            if y in (2, h - 1) or x in (1, w - 2):
                col = wood[0]
            elif (x + y) % 9 == 0:
                col = wood[2]
            c.set(x, y, col)
    c.line(2, 3, w - 3, h - 2, wood[0])
    if broken:
        for x in range(5, 12):
            c.set(x, 2, (0, 0, 0, 0))
            c.set(x, 3, (0, 0, 0, 0))
    c.outline(-0.6)
    return c


# --- crops -----------------------------------------------------------------------------------------
def crop_sheet(kind):
    W, H, F = 18, 22, 5
    c, g = blank(W * F, H), blank(W * F, H)
    for stage in range(F):
        f, fg = blank(W, H), blank(W, H)
        draw_crop(kind, stage, f, fg, W, H)
        f.outline(-0.6)
        c.paste(f, stage * W, 0)
        g.paste(fg, stage * W, 0)
    return c, g


def leaf(f, x, y, length, angle, cols, width=1.5):
    for i in range(length):
        t = i / max(1, length - 1)
        px_ = x + math.cos(angle) * i
        py_ = y - math.sin(angle) * i + t * t * length * 0.25
        half = width * math.sin(math.pi * min(0.99, t * 0.9 + 0.1))
        for k in range(-int(half), int(half) + 1):
            col = cols[2] if k < 0 else (cols[0] if k > 0 else cols[1])
            f.set(int(px_ - math.sin(angle) * k), int(py_ + k * 0.3), col)


def draw_crop(kind, stage, f, g, W, H):
    soil_y = H - 2
    if stage == 4:  # dead husk
        husk = shade(pal("clay"), -0.25)
        for i in range(6):
            f.set(W // 2 + (i % 3) - 1, soil_y - i, husk)
        f.line(W // 2, soil_y - 4, W // 2 + 4, soil_y - 2, husk)
        f.line(W // 2, soil_y - 3, W // 2 - 4, soil_y - 1, shade(husk, -0.2))
        return
    grow = [0.35, 0.6, 0.85, 1.0][stage]
    if kind == "glowbeet":
        cols = ramp(mix(pal("moss"), pal("violet_dark"), 0.25), 3, 0.35)
        n = 3 + stage
        for k in range(n):
            a = math.pi * (0.25 + 0.5 * k / max(1, n - 1))
            leaf(f, W // 2, soil_y - 2, int(4 + 6 * grow), a, cols, 1.2 + grow)
        if stage >= 2:
            bulb = pal("violet") if stage == 2 else mix(pal("violet"), pal("glow"), 0.3)
            f.ellipse(W / 2, soil_y - 1, 3 + stage * 0.5, 2.4, bulb)
            f.set(W // 2 - 1, soil_y - 2, shade(bulb, 0.4))
        if stage == 3:
            for (x, y) in [(W // 2 - 1, soil_y - 1), (W // 2 + 1, soil_y - 1), (W // 2, soil_y - 2)]:
                f.set(x, y, pal("glow"))
                g.set(x, y, pal("glow"))
            g.set(W // 2, soil_y, shade(pal("glow"), -0.3))
    elif kind == "cave_moss":
        cols = ramp(pal("moss_light"), 4, 0.35)
        rad = 2.5 + 4.5 * grow
        for y in range(H):
            for x in range(W):
                d = ((x + 0.5 - W / 2) / rad) ** 2 + ((y + 0.5 - soil_y) / (rad * 0.6)) ** 2
                if d <= 1 and y <= soil_y:
                    f.set(x, y, dither_pick(cols, 1 - d * 0.7, x, y))
        if stage == 3:
            for x in range(W // 2 - 4, W // 2 + 5, 2):
                f.set(x, soil_y - int(rad * 0.55) - 1, pal("cream"))
                f.set(x, soil_y - int(rad * 0.55), shade(pal("moss_light"), -0.3))
    elif kind == "sulfur_fern":
        cols = ramp(mix(pal("sour"), pal("moss"), 0.45), 3, 0.35)
        n = 2 + stage
        for k in range(n):
            a = math.pi * (0.3 + 0.4 * k / max(1, n - 1))
            length = int(5 + 8 * grow)
            x, y = W / 2, soil_y
            for i in range(length):
                x += math.cos(a) * 0.9
                y -= math.sin(a) * 0.9 - i * 0.04
                f.set(int(x), int(y), cols[1])
                if i % 2 == 0 and i > 1:
                    f.set(int(x) - 1, int(y) + 1, cols[2])
                    f.set(int(x) + 1, int(y) + 1, cols[0])
            if stage < 2:
                f.set(int(x), int(y) - 1, cols[2])  # unfurled tip
        if stage == 3:
            for (x, y) in [(W // 2 - 3, soil_y - 1), (W // 2 + 2, soil_y - 2), (W // 2, soil_y)]:
                f.set(x, y, pal("amber_light"))
                f.set(x + 1, y, pal("sour"))
    elif kind == "emberroot":
        cols = ramp(mix(pal("danger"), pal("clay"), 0.3), 3, 0.3)
        n = 2 + stage
        for k in range(n):
            x = W // 2 - n + k * 2 + 1
            hgt = int((4 + 9 * grow) * (0.7 + 0.3 * ((k * 7) % 3) / 2))
            for y in range(soil_y - hgt, soil_y + 1):
                f.set(x, y, cols[1] if y > soil_y - hgt + 1 else cols[2])
                if (y + k) % 3 == 0:
                    f.set(x + 1, y, cols[0])
            if stage == 3:
                f.set(x, soil_y - hgt - 1, pal("ember"))
                g.set(x, soil_y - hgt - 1, pal("ember"))
                g.set(x, soil_y - hgt, shade(pal("ember"), -0.4))
    elif kind == "bellcap":
        cols = ramp(pal("cream"), 3, 0.3)
        n = 1 + stage
        for k in range(n):
            x = W // 2 + (k - n // 2) * 4
            hgt = int(3 + 6 * grow) - (k % 2) * 2
            for y in range(soil_y - hgt, soil_y + 1):
                f.set(x, y, shade(pal("cream"), -0.15))
            capw = 2 + (1 if stage >= 2 else 0)
            for dy in range(3):
                for dx in range(-capw + dy // 2, capw - dy // 2 + 1):
                    f.set(x + dx, soil_y - hgt - 2 + dy, cols[2] if dy == 0 else cols[1])
            if stage == 3:
                f.set(x, soil_y - hgt - 1, pal("glow"))
                g.set(x, soil_y - hgt - 1, shade(pal("glow"), -0.3))
                g.set(x - 1, soil_y - hgt, shade(pal("cream"), -0.6))


def build():
    for i in range(3):
        c, g = glowroot(100 + i * 17)
        save(f"glowroot_{i}", c, g)
    for i in range(2):
        c, g = glowroot_small(200 + i)
        save(f"glowroot_small_{i}", c, g)
    for i in range(3):
        save(f"moss_tuft_{i}", moss_tuft(300 + i))
    for i in range(2):
        c, g = mushroom(310 + i)
        save(f"mushroom_{i}", c, g)
    for i in range(3):
        save(f"stalagmite_{i}", stalagmite(400 + i))
    for i in range(2):
        save(f"shore_rock_{i}", shore_rock(500 + i))
    save("rubble", rubble(600))
    save("rubble_small", rubble(601, 16, 12, 4))
    c, g = lamp_post(40, True, "town")
    save("town_lamp", c, g)
    c, g = lamp_post(30, True, "town")
    save("porch_lamp", c, g)
    c, g = lamp_post(34, True, "work")
    save("work_lamp", c, g)
    c, g = barrel_jars()
    save("jars", c, g)
    save("gear_pile", gear_pile())
    save("salvage_harness", harness())
    c, g = crystal_cluster(700, pal("glow"))
    save("glowglass_node", c, g)
    c, g = crystal_cluster(701, pal("ember"), 18, 24)
    save("ember_crystal", c, g)
    c, g = ore_node(710, shade(pal("basalt"), 0.1))
    save("blackstone_node", c)
    c, g = ore_node(711, shade(pal("basalt"), -0.05), pal("ember"))
    save("thermal_node", c, g)
    save("scrap_pile", scrap_pile(720))
    c = moss_tuft(730)
    big = Canvas(24, 14)
    big.paste(moss_tuft(731), 0, 4)
    big.paste(moss_tuft(732), 8, 2)
    save("moss_patch", big)
    c, g = lore_page()
    save("lore_page", c, g)
    save("crate_broken", crate(740, True))
    save("crate_small", crate(741))
    for kind in ["glowbeet", "cave_moss", "sulfur_fern", "emberroot", "bellcap"]:
        c, g = crop_sheet(kind)
        save(f"crop_{kind}", c, g, frames=5)
    # Wild variants for the Reach (mature frame only).
    for kind, name in [("emberroot", "emberroot_wild"), ("bellcap", "bellcap_wild")]:
        f, fg = blank(18, 22), blank(18, 22)
        draw_crop(kind, 3, f, fg, 18, 22)
        f.outline(-0.6)
        save(name, f, fg)
    c, g = mushroom(320)
    tall = Canvas(16, 24)
    tall.paste(c, 1, 8)
    tg = Canvas(16, 24)
    tg.paste(g, 1, 8)
    save("pale_fungus", tall, tg)
    with open(os.path.join(OUT, "props.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    # contact sheet preview
    sheet = Canvas(640, 360, (40, 38, 50, 255))
    x = y = 4
    row_h = 0
    for name in manifest:
        from PIL import Image
        im = Image.open(os.path.join(OUT, name + ".png"))
        if x + im.width > 636:
            x = 4
            y += row_h + 4
            row_h = 0
        sheet.img.paste(im, (x, y), im)
        x += im.width + 4
        row_h = max(row_h, im.height)
    sheet.img.resize((1280, 720), 0).save(os.path.join(os.path.dirname(__file__), "preview_props.png"))
    print(f"props: {len(manifest)} sprites")


if __name__ == "__main__":
    build()
