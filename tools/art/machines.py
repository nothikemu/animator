"""Machine sprites (cross-section and village lane). 16 px per cell.

Each machine is a horizontal strip of 5 frames: [idle, active1, active2, active3, broken],
plus an emission strip (glowing parts when active). Shapes are drawn with primitives so
they read as what they are: a pump looks like a pump, a burner burns.
Outputs assets/textures/machines/<id>.png, <id>_emit.png and machines.json.
"""
import json
import math
import os

from px import Canvas, TEX, pal, shade, ramp, mix, rng

OUT = os.path.join(TEX, "machines")
FRAMES = 5
manifest = {}

BRASS = ramp(pal("brass"), 5, 0.42)
IRON = ramp(mix(pal("slate"), pal("basalt"), 0.4), 5, 0.4)
COPPER = ramp(mix(pal("brass"), pal("danger"), 0.35), 4, 0.38)
WOOD = ramp(shade(pal("clay"), -0.05), 4, 0.35)
GLASS = ramp(pal("glow"), 3, 0.35)


def rivets(c, x0, y0, w, h, col, step=4):
    for x in range(x0 + 1, x0 + w - 1, step):
        c.set(x, y0 + 1, col)
        c.set(x, y0 + h - 2, col)


def plate(c, x, y, w, h, ramp_cols, rivet=True):
    c.rect(x, y, w, h, ramp_cols[2])
    c.hline(x, x + w - 1, y, ramp_cols[4] if len(ramp_cols) > 4 else ramp_cols[3])
    c.vline(x, y, y + h - 1, ramp_cols[3])
    c.hline(x, x + w - 1, y + h - 1, ramp_cols[0])
    c.vline(x + w - 1, y, y + h - 1, ramp_cols[1])
    if rivet:
        rivets(c, x, y, w, h, ramp_cols[4] if len(ramp_cols) > 4 else ramp_cols[3])


def gauge(c, cx, cy, r, angle, g=None):
    c.disc(cx, cy, r, pal("cream"))
    c.disc(cx, cy, r - 1, shade(pal("cream"), -0.08))
    ex = cx + math.cos(angle) * (r - 1.2)
    ey = cy + math.sin(angle) * (r - 1.2)
    c.line(int(cx), int(cy), int(round(ex)), int(round(ey)), pal("danger"))
    for k in range(5):
        a = math.pi * (0.8 + 0.35 * k)
        c.set(int(cx + math.cos(a) * (r - 0.5)), int(cy + math.sin(a) * (r - 0.5)), pal("charcoal"))


def strip(name, w, h, draw, emit=True):
    big = Canvas(w * FRAMES, h)
    glow = Canvas(w * FRAMES, h)
    for f in range(FRAMES):
        c = Canvas(w, h)
        g = Canvas(w, h)
        draw(c, g, f)
        c.outline(-0.6)
        big.paste(c, f * w, 0)
        glow.paste(g, f * w, 0)
    os.makedirs(OUT, exist_ok=True)
    big.save(os.path.join(OUT, name + ".png"))
    if emit:
        glow.save(os.path.join(OUT, name + "_emit.png"))
    manifest[name] = {"w": w, "h": h, "frames": FRAMES, "emit": emit}


def broken_overlay(c, w, h, seed):
    r = rng(seed)
    for k in range(6):
        x, y = r.randrange(w), r.randrange(h)
        if c.get(x, y)[3] > 0:
            c.set(x, y, mix(c.get(x, y), pal("verdigris"), 0.6))
    c.line(2, h // 3, w // 2, h // 3 + 3, shade(pal("charcoal"), 0.1))


# --- machines ---------------------------------------------------------------------------------
def well(c, g, f):
    w, h = 20, 28
    # stone ring
    stone = ramp(pal("stone"), 4, 0.35)
    for y in range(18, 28):
        c.hline(2, 17, y, stone[2] if y < 21 else stone[1])
    for x in range(2, 18, 4):
        c.vline(x, 18, 27, stone[0])
    c.hline(2, 17, 18, stone[3])
    # pump column and lever
    plate(c, 8, 6, 4, 13, IRON)
    c.rect(11, 12, 5, 2, IRON[2])           # spout
    c.set(15, 14, pal("water_light") if f in (1, 2, 3) else IRON[1])
    lever = [(-6, -4), (-6, 2), (-6, -6), (-6, 0), (-6, -2)][f]
    c.line(9, 7, 9 + lever[0], 7 + lever[1], WOOD[2])
    c.line(10, 7, 10 + lever[0], 8 + lever[1], WOOD[1])
    c.disc(9, 6, 1.5, BRASS[3])
    # bucket
    c.rect(13, 21, 4, 4, WOOD[1])
    c.hline(13, 16, 21, BRASS[2])
    if f in (1, 2, 3):
        c.rect(14, 22, 2, 1, pal("water_light"))


def mains(c, g, f):
    plate(c, 3, 4, 10, 10, IRON)
    c.disc(8, 9, 3.5, COPPER[2])
    for k in range(4):
        a = k * math.pi / 2 + (0.3 if f == 4 else 0)
        c.line(8, 9, int(8 + math.cos(a) * 3), int(9 + math.sin(a) * 3), COPPER[3])
    c.rect(0, 8, 3, 3, BRASS[2])
    c.rect(13, 8, 3, 3, BRASS[2])


def station_pump(c, g, f):
    w, h = 64, 64
    dead = f in (0, 4)
    # base plinth
    plate(c, 2, 54, 60, 10, IRON)
    # main cylinder
    for x in range(10, 38):
        t = (x - 10) / 28
        col = BRASS[4] if t < 0.15 else (BRASS[3] if t < 0.4 else (BRASS[2] if t < 0.75 else BRASS[1]))
        c.vline(x, 14, 53, col)
    for y in (18, 30, 42):
        c.hline(10, 37, y, BRASS[0])
        rivets(c, 10, y - 1, 28, 3, BRASS[4], 3)
    # dome
    c.ellipse(24, 14, 14, 6, BRASS[3])
    c.ellipse(22, 12, 8, 3, BRASS[4])
    # flywheel
    fx, fy, fr = 49, 30, 12
    c.disc(fx, fy, fr, IRON[1])
    c.disc(fx, fy, fr - 2, (0, 0, 0, 0))
    rot = 0 if dead else f * 0.5
    for k in range(6):
        a = rot + k * math.pi / 3
        c.line(fx, fy, int(fx + math.cos(a) * (fr - 2)), int(fy + math.sin(a) * (fr - 2)), IRON[3])
    c.disc(fx, fy, 2.5, BRASS[3])
    # piston rod
    py = 22 + (0 if dead else [0, 4, 8, 4][f % 4])
    c.rect(37, py, 12, 3, IRON[3])
    # gauges
    # One big pressure gauge and a small one set low, plus a sight glass: asymmetric so the
    # cylinder never reads as a face.
    gauge(c, 18, 24, 5, math.pi * (0.9 if dead else 1.4 + 0.15 * f))
    gauge(c, 29, 37, 3, math.pi * (0.85 if dead else 1.6))
    c.rect(31, 20, 3, 9, IRON[1])
    c.rect(32, 21, 1, 7, shade(pal("water"), -0.3) if dead else pal("water_light"))
    # outlet pipes
    c.rect(0, 46, 10, 5, COPPER[2])
    c.hline(0, 9, 46, COPPER[3])
    if dead:
        broken_overlay(c, w, h, 41)
        for k in range(10):
            c.set(12 + k * 2, 50 - (k % 3), pal("verdigris"))
        c.line(14, 34, 22, 40, shade(pal("charcoal"), 0.1))
    else:
        for (x, y) in [(18, 24), (29, 37)]:
            g.set(x, y, pal("amber"))
        lvl = 24 - [0, 2, 3, 2][f % 4]
        c.rect(32, lvl, 1, 28 - lvl, pal("glow"))
        g.rect(32, lvl, 1, 28 - lvl, pal("glow"))


def intake(c, g, f):
    c.rect(6, 0, 4, 6, BRASS[2])
    c.vline(6, 0, 5, BRASS[3])
    for y in range(6, 15):
        w = 5 if y < 13 else 4
        for x in range(8 - w, 8 + w):
            c.set(x, y, IRON[2] if (x + y) % 2 else IRON[0])
    c.hline(3, 12, 6, BRASS[3])


def pump(c, g, f):
    # 16x32: motor on top, impeller housing below
    plate(c, 2, 2, 12, 12, IRON)
    for y in range(4, 12, 2):
        c.hline(4, 11, y, IRON[1])
    c.rect(6, 14, 4, 3, BRASS[2])
    c.disc(8, 23, 6, COPPER[2])
    c.disc(8, 23, 4, COPPER[1])
    rot = f * 0.7
    for k in range(3):
        a = rot + k * math.tau / 3
        c.line(8, 23, int(8 + math.cos(a) * 4), int(23 + math.sin(a) * 4), COPPER[3])
    c.rect(0, 22, 2, 3, BRASS[2])
    c.rect(14, 22, 2, 3, BRASS[2])
    c.rect(3, 29, 10, 3, IRON[1])
    if f in (1, 2, 3):
        c.set(12, 5, pal("glow")); g.set(12, 5, pal("glow"))
    if f == 4:
        broken_overlay(c, 16, 32, 5)


def outlet(c, g, f):
    c.rect(6, 0, 4, 8, BRASS[2])
    c.vline(6, 0, 7, BRASS[3])
    c.rect(4, 8, 8, 4, BRASS[1])
    c.hline(4, 11, 8, BRASS[3])
    if f in (1, 2, 3):
        for k in range(3):
            c.set(6 + k * 2 - (f % 2), 13 + k % 2, pal("water_light"))


def burner(c, g, f):
    w, h = 32, 32
    lit = f in (1, 2, 3)
    plate(c, 3, 12, 26, 18, IRON)
    # firebox door with grate
    c.rect(8, 17, 16, 9, shade(pal("charcoal"), 0.05))
    for x in range(9, 24, 3):
        c.vline(x, 17, 25, IRON[3])
    if lit:
        flick = [0, 1, 0, 2][f % 4]
        for y in range(19, 25):
            for x in range(10, 23):
                if (x + y + flick) % 3 != 0 and x % 3 != 0:
                    col = pal("ember") if y > 21 else pal("amber_light")
                    c.set(x, y, col)
                    g.set(x, y, col)
    # flue / chimney
    c.rect(20, 2, 5, 11, IRON[2])
    c.vline(20, 2, 12, IRON[3])
    c.hline(19, 25, 2, IRON[4])
    if lit:
        for k in range(3):
            c.set(22 + (f + k) % 2, 0 + k - (f % 2), (180, 170, 140, 140))
    # dials
    gauge(c, 9, 14, 2.5, math.pi * (1.0 if not lit else 1.6))
    c.rect(26, 20, 3, 6, BRASS[2])
    if f == 4:
        broken_overlay(c, w, h, 9)


def turbine(c, g, f):
    # 16x32 frame with glowglass vanes
    plate(c, 1, 0, 14, 4, BRASS)
    plate(c, 1, 28, 14, 4, BRASS)
    c.vline(2, 4, 27, BRASS[2])
    c.vline(13, 4, 27, BRASS[1])
    rot = f * math.pi / 6
    for k in range(4):
        a = rot + k * math.pi / 2
        for t in range(1, 6):
            x = int(round(8 + math.cos(a) * t))
            y = int(round(16 + math.sin(a) * t * 1.5))
            c.set(x, y, GLASS[1] if t < 5 else GLASS[2])
            if f in (1, 2, 3):
                g.set(x, y, shade(pal("glow"), -0.4))
    c.disc(8, 16, 1.5, BRASS[3])


def crank(c, g, f):
    plate(c, 3, 6, 10, 9, IRON)
    c.disc(8, 10, 3, COPPER[2])
    a = f * math.pi / 2
    hx, hy = int(8 + math.cos(a) * 4), int(10 + math.sin(a) * 4)
    c.line(8, 10, hx, hy, BRASS[3])
    c.rect(hx - 1, hy - 1, 2, 2, WOOD[2])


def heat_cell(c, g, f):
    plate(c, 3, 2, 10, 13, BRASS)
    c.rect(5, 4, 6, 9, shade(pal("basalt"), 0.1))
    level = [1, 3, 5, 7, 0][f]
    for y in range(12 - level, 12):
        c.hline(6, 9, y, pal("ember"))
        g.hline(6, 9, y, shade(pal("ember"), -0.2))


def lamp(c, g, f):
    # 16x28 post with bulb (surface lamp)
    c.rect(7, 8, 2, 18, IRON[1])
    c.rect(5, 25, 6, 3, IRON[2])
    c.rect(4, 2, 8, 7, BRASS[1])
    lit = f in (1, 2, 3)
    col = pal("amber_light") if lit else shade(pal("cream"), -0.5)
    c.rect(5, 3, 6, 5, col)
    if lit:
        g.rect(5, 3, 6, 5, pal("amber_light"))
    c.hline(3, 12, 1, BRASS[3])


def sprinkler(c, g, f):
    c.rect(6, 10, 4, 6, BRASS[2])
    c.rect(4, 8, 8, 3, BRASS[3])
    if f in (1, 2, 3):
        for k in range(6):
            a = math.pi * (1.1 + 0.16 * k) + f * 0.1
            x, y = int(8 + math.cos(a) * (3 + f)), int(7 + math.sin(a) * (2 + f * 0.6))
            c.set(x, y, pal("water_light"))


def scrubber(c, g, f):
    w, h = 32, 32
    plate(c, 2, 6, 28, 24, IRON)
    # fan grille
    c.disc(10, 16, 6, shade(pal("charcoal"), 0.1))
    rot = f * 0.6
    for k in range(5):
        a = rot + k * math.tau / 5
        c.line(10, 16, int(10 + math.cos(a) * 5), int(16 + math.sin(a) * 5), IRON[3])
    # filter window (moss)
    c.rect(18, 10, 9, 14, pal("moss"))
    for y in range(11, 24, 2):
        c.hline(19, 26, y, pal("moss_light"))
    if f in (1, 2, 3):
        c.set(28, 8, pal("glow")); g.set(28, 8, pal("glow"))
    c.rect(4, 2, 6, 4, IRON[2])   # intake hood
    c.rect(22, 2, 6, 4, IRON[2])
    if f == 4:
        c.rect(18, 10, 9, 14, shade(pal("sour"), -0.4))


def fan(c, g, f):
    c.disc(8, 8, 7, IRON[2])
    c.disc(8, 8, 6, shade(pal("charcoal"), 0.1))
    rot = f * 0.8
    for k in range(4):
        a = rot + k * math.pi / 2
        c.line(8, 8, int(8 + math.cos(a) * 5), int(8 + math.sin(a) * 5), BRASS[3])
        c.line(8, 8, int(8 + math.cos(a + 0.3) * 4), int(8 + math.sin(a + 0.3) * 4), BRASS[2])
    c.disc(8, 8, 1.2, BRASS[4])


def compost(c, g, f):
    for y in range(4, 16):
        c.hline(2, 29, y, WOOD[2] if y % 4 else WOOD[0])
    for x in range(2, 30, 7):
        c.vline(x, 4, 15, WOOD[0])
    c.hline(1, 30, 3, BRASS[2])
    if f in (1, 2, 3):
        c.set(10 + f, 1, (160, 170, 120, 140))


def exchanger(c, g, f):
    plate(c, 1, 1, 14, 14, IRON, rivet=False)
    for x in range(3, 14, 2):
        c.vline(x, 3, 12, COPPER[2] if f in (1, 2, 3) else COPPER[1])
    if f in (1, 2, 3):
        for x in range(3, 14, 4):
            g.vline(x, 3, 12, shade(pal("ember"), -0.55))


def tank(c, g, f):
    w, h = 32, 32
    for y in range(4, 30):
        for x in range(3, 29):
            t = (x - 3) / 26
            c.set(x, y, IRON[3] if t < 0.2 else (IRON[2] if t < 0.7 else IRON[1]))
    c.ellipse(16, 4, 13, 3, IRON[3])
    for y in (10, 20):
        rivets(c, 3, y - 1, 26, 3, IRON[4], 3)
    c.rect(13, 8, 6, 18, shade(pal("charcoal"), 0.1))
    level = [4, 8, 12, 16, 2][f]
    c.rect(14, 26 - level, 4, level, pal("water"))


# --- relics -----------------------------------------------------------------------------------------
def crew_locker(c, g, f):
    plate(c, 2, 2, 12, 22, IRON)
    c.vline(8, 3, 22, IRON[0])
    c.rect(4, 6, 3, 1, IRON[0]); c.rect(9, 6, 3, 1, IRON[0])
    c.set(7, 13, BRASS[3]); c.set(9, 13, BRASS[3])
    c.rect(4, 16, 3, 3, pal("cream"))     # a stuck label


def gauge_relic(c, g, f):
    plate(c, 1, 1, 14, 14, BRASS)
    angle = [math.pi * 0.85, math.pi * 1.3, math.pi * 1.6, math.pi * 1.9, math.pi * 0.85][f]
    gauge(c, 8, 8, 5, angle)


def trunk_valve(c, g, f):
    w, h = 32, 16
    plate(c, 0, 8, 32, 8, IRON)
    c.disc(16, 7, 7, COPPER[2])
    c.disc(16, 7, 5, (0, 0, 0, 0))
    rot = f * 0.4
    for k in range(4):
        a = rot + k * math.pi / 2
        c.line(16, 7, int(16 + math.cos(a) * 6), int(7 + math.sin(a) * 6), COPPER[3])
    c.disc(16, 7, 1.5, BRASS[4])
    if f == 4:
        for x in range(4, 28, 3):
            c.set(x, 12, pal("verdigris"))


def build():
    strip("old_well", 20, 28, well)
    strip("wick_mains", 16, 16, mains, emit=False)
    strip("station_pump", 64, 64, station_pump)
    strip("intake", 16, 16, intake, emit=False)
    strip("pump", 16, 32, pump)
    strip("outlet", 16, 16, outlet, emit=False)
    strip("burner", 32, 32, burner)
    strip("turbine", 16, 32, turbine)
    strip("crank", 16, 16, crank, emit=False)
    strip("heat_cell", 16, 16, heat_cell)
    strip("lamp", 16, 28, lamp)
    strip("sprinkler", 16, 16, sprinkler, emit=False)
    strip("scrubber", 32, 32, scrubber)
    strip("fan", 16, 16, fan, emit=False)
    strip("compost", 32, 16, compost, emit=False)
    strip("exchanger", 16, 16, exchanger)
    strip("tank", 32, 32, tank, emit=False)
    strip("crew_locker", 16, 24, crew_locker, emit=False)
    strip("gauge", 16, 16, gauge_relic, emit=False)
    strip("trunk_valve", 32, 16, trunk_valve, emit=False)
    with open(os.path.join(OUT, "machines.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    sheet = Canvas(700, 420, (36, 34, 44, 255))
    x, y, rowh = 4, 4, 0
    from PIL import Image
    for name in manifest:
        im = Image.open(os.path.join(OUT, name + ".png"))
        if x + im.width > 696:
            x, y, rowh = 4, y + rowh + 6, 0
        sheet.img.paste(im, (x, y), im)
        x += im.width + 6
        rowh = max(rowh, im.height)
    sheet.img.resize((1400, 840), 0).save(os.path.join(os.path.dirname(__file__), "preview_machines.png"))
    print(f"machines: {len(manifest)}")


if __name__ == "__main__":
    build()
