"""16x16 icons for items, tools, statuses and UI, in one atlas (assets/textures/icons.png).

Shared visual language: a bold silhouette, 3-tone hue-shifted ramp, one highlight pixel,
selective outline, and a faint drop shadow pixel row so icons sit on any panel.
"""
import json
import math
import os

from px import Canvas, TEX, pal, shade, ramp, mix, hexc

S = 16
COLS = 8
icons = {}


def icon():
    return Canvas(S, S)


def finish(c):
    c.outline(-0.6)
    return c


def disc_shaded(c, cx, cy, r, base):
    rr = ramp(base, 4, 0.4)
    for y in range(S):
        for x in range(S):
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            if d <= r:
                t = (x - cx + y - cy) / (r * 2)
                col = rr[3] if t < -0.35 else (rr[2] if t < 0.05 else (rr[1] if t < 0.4 else rr[0]))
                c.set(x, y, col)


def seed_icon(color):
    c = icon()
    pouch = ramp(pal("sand"), 3, 0.3)
    for y in range(5, 15):
        w = [3, 4, 5, 5, 6, 6, 6, 6, 5, 4][y - 5]
        c.hline(8 - w, 7 + w, y, pouch[1] if y < 12 else pouch[0])
    c.hline(5, 10, 5, pouch[0])
    c.rect(6, 3, 4, 2, pouch[2])
    c.line(5, 4, 3, 2, shade(pal("clay"), -0.2))
    for (x, y) in [(7, 9), (9, 10), (6, 11)]:
        c.set(x, y, color)
        c.set(x + 1, y, shade(color, -0.3))
    return finish(c)


def crop_glowbeet():
    c = icon()
    disc_shaded(c, 8, 10, 4.5, pal("violet"))
    for (x, y) in [(7, 9), (9, 11), (8, 8)]:
        c.set(x, y, pal("glow"))
    leaves = ramp(pal("moss"), 3, 0.3)
    c.line(8, 5, 5, 1, leaves[1]); c.line(8, 5, 11, 1, leaves[2]); c.line(8, 6, 8, 1, leaves[0])
    return finish(c)


def moss_fiber():
    c = icon()
    cols = ramp(pal("moss_light"), 3, 0.35)
    for i in range(6):
        c.line(3 + i, 13, 6 + i, 3, cols[i % 3])
    c.hline(4, 12, 9, shade(pal("clay"), -0.1))
    return finish(c)


def sulfur():
    c = icon()
    cols = ramp(pal("amber_light"), 3, 0.3)
    for (x, y, h) in [(5, 7, 6), (8, 4, 9), (11, 8, 5)]:
        for k in range(h):
            w = 1 if k < 2 else 2
            c.hline(x - w + 1, x + w, y + k, cols[1] if k % 3 else cols[2])
        c.set(x, y + h - 1, cols[0])
    return finish(c)


def resin():
    c = icon()
    cols = ramp(pal("ember"), 4, 0.4)
    c.ellipse(8, 10, 5, 4, cols[1])
    c.ellipse(8, 6, 3, 3, cols[1])
    c.ellipse(7, 9, 2, 2, cols[2])
    c.set(6, 5, pal("cream"))
    c.set(10, 12, cols[0])
    return finish(c)


def bellcap():
    c = icon()
    cap = ramp(pal("cream"), 3, 0.3)
    for y in range(3, 9):
        w = [2, 4, 5, 6, 6, 6][y - 3]
        c.hline(8 - w, 7 + w, y, cap[2] if y < 5 else cap[1])
    c.hline(2, 13, 9, cap[0])
    c.rect(7, 9, 2, 5, shade(pal("cream"), -0.15))
    c.set(6, 5, pal("glow"))
    return finish(c)


def rock_icon(base, vein=None):
    c = icon()
    cols = ramp(base, 4, 0.4)
    pts = [(3, 12), (5, 5), (10, 3), (13, 8), (12, 13)]
    for y in range(S):
        for x in range(S):
            inside = 3 <= x <= 13 and 3 <= y <= 13 and (x - 3) + (13 - y) > 3 and (13 - x) + (y - 3) > 2
            if inside:
                t = (x + y) / 26
                c.set(x, y, cols[3] if t < 0.4 else (cols[2] if t < 0.6 else cols[1]))
    if vein:
        c.line(5, 10, 9, 6, vein); c.line(9, 6, 11, 9, vein)
    return finish(c)


def brass_scrap():
    c = icon()
    cols = ramp(pal("brass"), 4, 0.4)
    c.rect(2, 8, 11, 3, cols[2]); c.hline(2, 12, 8, cols[3]); c.hline(2, 12, 10, cols[1])
    c.disc(11, 5, 3, cols[2]); c.disc(11, 5, 1.2, (0, 0, 0, 0))
    c.rect(4, 11, 2, 3, cols[1])
    return finish(c)


def glowglass():
    c = icon()
    cols = ramp(pal("glow"), 3, 0.35)
    for (x, top) in [(6, 2), (9, 4), (4, 7), (11, 8)]:
        for y in range(top, 14):
            c.set(x, y, cols[2] if y == top else cols[1])
            c.set(x + 1, y, cols[0])
    return finish(c)


def pipe_section():
    c = icon()
    cols = ramp(pal("brass"), 4, 0.4)
    c.rect(2, 6, 12, 4, cols[2]); c.hline(2, 13, 6, cols[3]); c.hline(2, 13, 9, cols[0])
    c.rect(1, 5, 2, 6, cols[1]); c.rect(13, 5, 2, 6, cols[1])
    return finish(c)


def wire_coil():
    c = icon()
    for k in range(4):
        c.ellipse(5 + k * 2, 8, 2.2, 4.5, shade(pal("danger"), -0.1 + 0.08 * (k % 2)))
        c.ellipse(5 + k * 2, 8, 1.0, 3.0, (0, 0, 0, 0))
    c.line(12, 8, 14, 12, pal("brass_light"))
    return finish(c)


def filter_pad():
    c = icon()
    c.rect(3, 3, 10, 10, pal("moss"))
    for y in range(4, 12, 2):
        c.hline(4, 11, y, pal("moss_light"))
    c.rect(3, 3, 10, 1, pal("brass")); c.rect(3, 12, 10, 1, pal("brass_dark"))
    c.set(7, 7, pal("amber_light")); c.set(9, 9, pal("amber_light"))
    return finish(c)


def seal_gum():
    c = icon()
    c.rect(4, 5, 8, 8, shade(pal("cream"), -0.2))
    c.rect(4, 4, 8, 2, pal("brass"))
    c.ellipse(8, 9, 2.5, 2.5, pal("ember"))
    return finish(c)


def sack(color, mark):
    c = icon()
    cols = ramp(color, 3, 0.3)
    for y in range(4, 15):
        w = [3, 4, 5, 6, 6, 6, 6, 6, 6, 5, 4][y - 4]
        c.hline(8 - w, 7 + w, y, cols[1] if y < 11 else cols[0])
    c.rect(6, 2, 4, 2, cols[2])
    c.set(8, 9, mark); c.set(7, 10, mark); c.set(9, 10, mark)
    return finish(c)


def cup(liquid):
    c = icon()
    c.rect(4, 6, 8, 7, shade(pal("clay"), 0.1))
    c.rect(5, 7, 6, 2, liquid)
    c.rect(12, 8, 2, 3, shade(pal("clay"), -0.1))
    c.line(6, 4, 7, 2, (200, 200, 210, 160)); c.line(9, 4, 10, 1, (200, 200, 210, 160))
    return finish(c)


def bowl(fill):
    c = icon()
    c.ellipse(8, 10, 6, 3.5, shade(pal("clay"), -0.05))
    c.ellipse(8, 8, 5, 1.6, fill)
    c.set(6, 8, pal("glow")); c.set(10, 8, pal("violet"))
    c.line(5, 5, 6, 3, (200, 200, 210, 160)); c.line(9, 5, 10, 2, (200, 200, 210, 160))
    return finish(c)


def respirator():
    c = icon()
    c.ellipse(8, 8, 5, 4, shade(pal("slate"), 0.2))
    c.disc(5, 10, 2.5, pal("brass")); c.disc(11, 10, 2.5, pal("brass"))
    c.disc(5, 10, 1.0, pal("moss")); c.disc(11, 10, 1.0, pal("moss"))
    c.hline(2, 13, 6, shade(pal("clay"), -0.3))
    return finish(c)


def lens():
    c = icon()
    c.disc(8, 8, 5.5, pal("brass"))
    c.disc(8, 8, 4, pal("glow"))
    c.set(6, 6, pal("cream")); c.set(7, 6, pal("cream"))
    return finish(c)


def coil():
    c = icon()
    c.rect(3, 4, 10, 8, pal("brass_dark"))
    for x in range(4, 12, 2):
        c.vline(x, 4, 11, pal("brass_light"))
    c.rect(2, 3, 12, 1, pal("brass")); c.rect(2, 12, 12, 1, pal("brass"))
    c.set(8, 8, pal("glow"))
    return finish(c)


def tag():
    c = icon()
    c.rect(3, 5, 10, 6, pal("brass"))
    c.hline(4, 11, 7, pal("brass_dark")); c.hline(4, 9, 9, pal("brass_dark"))
    c.disc(4, 8, 1, (0, 0, 0, 0))
    c.line(3, 8, 1, 4, shade(pal("ash"), 0.2))
    return finish(c)


def cable():
    c = icon()
    rope = ramp(pal("sand"), 3, 0.3)
    for k in range(4):
        c.ellipse(8, 8, 6 - k * 1.2, 4.5 - k * 0.9, rope[k % 2 + 1] if k < 3 else rope[0])
    c.disc(8, 8, 1.2, (0, 0, 0, 0))
    c.line(12, 10, 14, 14, rope[1])
    c.set(14, 14, pal("brass_light")); c.set(13, 13, pal("brass"))
    return finish(c)


def vial(liquid, cork):
    c = icon()
    c.rect(6, 4, 4, 2, cork)
    c.rect(5, 6, 6, 8, (200, 215, 220, 255))
    c.rect(6, 8, 4, 5, liquid)
    c.set(6, 8, shade(liquid, 0.4))
    c.vline(10, 7, 12, (240, 250, 255, 255))
    return finish(c)


def crate_icon(mark):
    c = icon()
    wood = ramp(shade(pal("clay"), 0.05), 3, 0.3)
    c.rect(2, 5, 12, 9, wood[1])
    c.hline(2, 13, 5, wood[2]); c.hline(2, 13, 13, wood[0])
    c.line(2, 6, 13, 12, wood[0])
    c.rect(6, 7, 4, 3, pal("cream")); c.set(7, 8, mark); c.set(8, 8, mark); c.set(8, 7, mark); c.set(8, 9, mark)
    return finish(c)


def salt_icon():
    c = icon()
    for (x, y, h) in [(4, 9, 5), (7, 5, 9), (10, 7, 7), (12, 10, 4)]:
        for k in range(h):
            c.hline(x - 1 + (1 if k < 2 else 0), x + 1 - (1 if k < 2 else 0), y + k, (238, 236, 244, 255) if k % 3 else (205, 202, 220, 255))
    c.set(7, 6, (255, 255, 255, 255))
    return finish(c)


def salted_beets():
    c = icon()
    c.rect(4, 4, 8, 10, shade(pal("clay"), 0.15))
    c.rect(5, 6, 6, 7, shade(pal("violet"), -0.1))
    c.set(6, 7, pal("glow")); c.set(9, 10, pal("glow"))
    for (x, y) in [(6, 9), (8, 8), (9, 11), (7, 12)]:
        c.set(x, y, (238, 236, 244, 255))
    c.rect(4, 3, 8, 1, shade(pal("clay"), -0.2))
    return finish(c)


def journal():
    c = icon()
    c.rect(3, 3, 10, 11, shade(pal("danger"), -0.45))
    c.rect(4, 4, 8, 9, shade(pal("danger"), -0.3))
    c.vline(4, 3, 13, shade(pal("danger"), -0.6))
    c.hline(6, 10, 6, pal("cream")); c.hline(6, 9, 8, pal("cream"))
    c.set(11, 3, pal("brass_light"))
    return finish(c)


def chalk():
    c = icon()
    c.line(4, 12, 11, 5, (236, 232, 222, 255)); c.line(5, 12, 12, 5, (210, 206, 196, 255))
    c.line(4, 13, 11, 6, (236, 232, 222, 255))
    for (x, y) in [(2, 3), (4, 3), (6, 3)]:
        c.set(x, y, (236, 232, 222, 255))
    return finish(c)


def sludge():
    c = icon()
    c.ellipse(8, 11, 6, 3.5, shade(pal("sour"), -0.45))
    c.ellipse(7, 9, 3, 2, shade(pal("sour"), -0.3))
    c.set(5, 10, pal("sour")); c.set(10, 11, pal("sour"))
    return finish(c)


# --- tools ----------------------------------------------------------------------------------------
def tool_hands():
    c = icon()
    skin = ramp(hexc("#b97f56"), 3, 0.3)
    c.rect(5, 6, 6, 7, skin[1])
    for i in range(4):
        c.rect(5 + i * 1 + (i > 1), 2 + (i % 2), 1, 5, skin[2] if i % 2 else skin[1])
    c.rect(10, 7, 3, 2, skin[1])
    return finish(c)


def tool_tiller():
    c = icon()
    c.line(3, 13, 11, 5, shade(pal("clay"), -0.1))
    c.line(4, 13, 12, 5, shade(pal("clay"), -0.35))
    c.rect(10, 2, 4, 3, pal("ash")); c.rect(12, 5, 2, 3, pal("ash"))
    return finish(c)


def tool_can():
    c = icon()
    cols = ramp(pal("verdigris"), 3, 0.35)
    c.rect(3, 6, 8, 7, cols[1]); c.hline(3, 10, 6, cols[2]); c.hline(3, 10, 12, cols[0])
    c.line(11, 8, 14, 4, cols[1]); c.rect(13, 3, 2, 2, cols[2])
    c.line(4, 6, 7, 3, shade(pal("brass"), 0)); c.line(7, 3, 9, 6, pal("brass"))
    return finish(c)


def tool_hammer():
    c = icon()
    c.line(3, 14, 10, 7, shade(pal("clay"), -0.15))
    c.rect(8, 2, 6, 4, pal("ash")); c.hline(8, 13, 2, shade(pal("ash"), 0.3)); c.rect(12, 6, 2, 1, pal("ash"))
    return finish(c)


def tool_wrench():
    c = icon()
    c.line(3, 13, 10, 6, pal("brass")); c.line(4, 13, 11, 6, pal("brass_dark"))
    c.disc(11, 5, 3, pal("brass")); c.rect(11, 2, 3, 3, (0, 0, 0, 0))
    return finish(c)


def tool_glass():
    c = icon()
    c.disc(8, 7, 5, pal("brass"))
    c.disc(8, 7, 3.6, shade(pal("glow_dark"), -0.3))
    c.hline(6, 10, 7, pal("glow")); c.vline(8, 5, 9, pal("glow"))
    c.rect(7, 12, 2, 3, pal("brass_dark"))
    return finish(c)


# --- status / overlay / ui ---------------------------------------------------------------------
def st_power():
    c = icon()
    for (x, y) in [(9, 1), (8, 2), (7, 3), (6, 4), (5, 5), (5, 6), (6, 6), (7, 6), (8, 6), (9, 6), (10, 6), (9, 7), (8, 8), (7, 9), (6, 10), (5, 11)]:
        c.set(x, y, pal("amber_light"))
        c.set(x + 1, y, pal("amber"))
    return finish(c)


def st_water():
    c = icon()
    for y in range(2, 14):
        w = max(0, min(5, (y - 2) // 2 + 1 if y < 10 else 14 - y))
        c.hline(8 - w, 7 + w, y, pal("water_light") if y < 8 else pal("water"))
    c.set(6, 9, pal("cream"))
    return finish(c)


def st_gas():
    c = icon()
    for (x, y, r) in [(5, 10, 3), (9, 8, 3.5), (11, 11, 2.5)]:
        c.disc(x, y, r, pal("sour"))
    c.disc(8, 8, 1.5, shade(pal("sour"), 0.3))
    return finish(c)


def st_heat():
    c = icon()
    c.ellipse(8, 10, 4, 4, pal("ember"))
    c.ellipse(8, 7, 2.5, 4, pal("amber"))
    c.ellipse(8, 10, 1.5, 2, pal("amber_light"))
    return finish(c)


def st_warn():
    c = icon()
    for y in range(2, 14):
        w = (y - 1) // 2
        c.hline(8 - w, 7 + w, y, pal("danger"))
    c.vline(8, 5, 9, pal("cream")); c.set(8, 11, pal("cream"))
    return finish(c)


def st_ok():
    c = icon()
    c.line(3, 8, 6, 11, pal("glow")); c.line(6, 11, 12, 4, pal("glow"))
    c.line(3, 9, 6, 12, pal("glow_dark")); c.line(6, 12, 12, 5, pal("glow_dark"))
    return finish(c)


def glim():
    c = icon()
    c.disc(8, 8, 4.5, pal("glow_dark"))
    c.disc(8, 8, 3, pal("glow"))
    c.set(7, 6, pal("cream"))
    return finish(c)


def gear():
    c = icon()
    for k in range(8):
        a = k / 8 * math.tau
        c.rect(int(8 + math.cos(a) * 5.5) - 1, int(8 + math.sin(a) * 5.5) - 1, 2, 2, pal("brass"))
    c.disc(8, 8, 4.5, pal("brass"))
    c.disc(8, 8, 2, pal("brass_dark"))
    return finish(c)


def build():
    spec = [
        ("glowbeet_seed", seed_icon(pal("violet"))), ("moss_spore", seed_icon(pal("moss_light"))),
        ("fern_spore", seed_icon(pal("sour"))), ("emberroot_seed", seed_icon(pal("ember"))),
        ("bellcap_spore", seed_icon(pal("cream"))),
        ("glowbeet", crop_glowbeet()), ("moss_fiber", moss_fiber()), ("sulfur", sulfur()),
        ("ember_resin", resin()), ("bellcap", bellcap()),
        ("blackstone", rock_icon(shade(pal("basalt"), 0.1))), ("brass_scrap", brass_scrap()),
        ("glowglass", glowglass()), ("thermal_ore", rock_icon(shade(pal("basalt"), -0.05), pal("ember"))),
        ("pipe_section", pipe_section()), ("wire_coil", wire_coil()), ("filter_pad", filter_pad()),
        ("seal_gum", seal_gum()), ("fertiliser", sack(pal("clay"), pal("moss_light"))), ("sludge", sludge()),
        ("moss_tea", cup(pal("moss"))), ("glowbeet_stew", bowl(shade(pal("danger"), -0.2))),
        ("respirator", respirator()), ("lamp_lens", lens()), ("governor_coil", coil()), ("crew_tag", tag()),
        ("crew_cable", cable()), ("moss_tincture", vial(pal("glow"), shade(pal("clay"), 0.1))),
        ("river_medicine", crate_icon(shade(pal("danger"), -0.1))), ("salt", salt_icon()),
        ("salted_beets", salted_beets()), ("wren_journal", journal()), ("knock_chalk", chalk()),
        ("tool_hands", tool_hands()), ("tool_tiller", tool_tiller()), ("tool_can", tool_can()),
        ("tool_hammer", tool_hammer()), ("tool_wrench", tool_wrench()), ("tool_glass", tool_glass()),
        ("st_power", st_power()), ("st_water", st_water()), ("st_gas", st_gas()), ("st_heat", st_heat()),
        ("st_warn", st_warn()), ("st_ok", st_ok()), ("glim", glim()), ("gear", gear()),
    ]
    rows = (len(spec) + COLS - 1) // COLS
    atlas = Canvas(COLS * S, rows * S)
    for i, (name, c) in enumerate(spec):
        x, y = (i % COLS) * S, (i // COLS) * S
        atlas.paste(c, x, y)
        icons[name] = [i % COLS, i // COLS]
    atlas.save(os.path.join(TEX, "icons.png"))
    with open(os.path.join(TEX, "icons.json"), "w") as f:
        json.dump({"size": S, "cols": COLS, "icons": icons}, f, indent=0)
    atlas.img.resize((atlas.w * 4, atlas.h * 4), 0).save(os.path.join(os.path.dirname(__file__), "preview_icons.png"))
    print(f"icons: {len(icons)}")


if __name__ == "__main__":
    build()
