"""UI frame art for Bellows: nine-slice plates in the game's brass-and-basalt language.

Outputs assets/textures/ui/<name>.png at 2x (each art pixel is 2 screen pixels at 1280x720)
and assets/textures/ui/ui.json with each frame's nine-slice margin, in screen pixels.
The centres are flat or tile cleanly, so the game can stretch or tile them.
"""
import json
import os

from PIL import Image

from px import Canvas, TEX, pal, shade, mix

OUT = os.path.join(TEX, "ui")
SCALE = 2
META = {}

BRASS = pal("brass")
BRASS_L = pal("brass_light")
BRASS_D = pal("brass_dark")
CHAR = pal("charcoal")
BASALT = pal("basalt")
SLATE = pal("slate")
AMBER = pal("amber")
AMBER_L = pal("amber_light")
CYAN = pal("glow")


def save(name, c, margin):
    os.makedirs(OUT, exist_ok=True)
    img = c.img.resize((c.w * SCALE, c.h * SCALE), Image.NEAREST)
    img.save(os.path.join(OUT, name + ".png"))
    META[name] = {"margin": margin * SCALE, "size": [c.w * SCALE, c.h * SCALE]}


def rivet(c, x, y):
    c.set(x, y, BRASS_L)
    c.set(x + 1, y, BRASS)
    c.set(x, y + 1, BRASS)
    c.set(x + 1, y + 1, BRASS_D)


def bevel_frame(c, x0, y0, w, h, light, mid, dark):
    """A 2-pixel brass frame: light on top/left, dark on bottom/right, mid between."""
    x1, y1 = x0 + w - 1, y0 + h - 1
    c.hline(x0, x1, y0, light)
    c.vline(x0, y0, y1, light)
    c.hline(x0 + 1, x1 - 1, y0 + 1, mid)
    c.vline(x0 + 1, y0 + 1, y1 - 1, mid)
    c.hline(x0, x1, y1, dark)
    c.vline(x1, y0, y1, dark)
    c.hline(x0 + 1, x1 - 1, y1 - 1, mid)
    c.vline(x1 - 1, y0 + 1, y1 - 1, mid)


def panel():
    """The main window: charcoal outline, bevelled brass frame, corner plates with rivets,
    a hairline inner shadow and a basalt fill that is a touch lighter at the top."""
    S = 32
    c = Canvas(S, S)
    fill_top = mix(pal("ui_panel")[:3] + (255,), SLATE, 0.18)
    fill = pal("ui_panel")[:3] + (255,)
    for y in range(S):
        col = mix(fill_top, fill, min(1.0, y / 8.0))
        c.hline(0, S - 1, y, col)
    # outline + frame
    c.hline(0, S - 1, 0, CHAR)
    c.hline(0, S - 1, S - 1, CHAR)
    c.vline(0, 0, S - 1, CHAR)
    c.vline(S - 1, 0, S - 1, CHAR)
    bevel_frame(c, 1, 1, S - 2, S - 2, BRASS_L, BRASS, BRASS_D)
    # inner shadow line
    c.hline(3, S - 4, 3, CHAR)
    c.vline(3, 3, S - 4, CHAR)
    c.hline(4, S - 4, S - 4, shade(fill, 0.08))
    c.vline(S - 4, 4, S - 4, shade(fill, 0.08))
    # corner plates
    for (ox, oy) in [(1, 1), (S - 8, 1), (1, S - 8), (S - 8, S - 8)]:
        c.rect(ox, oy, 7, 7, BRASS)
        c.hline(ox, ox + 6, oy, BRASS_L)
        c.vline(ox, oy, oy + 6, BRASS_L)
        c.hline(ox, ox + 6, oy + 6, BRASS_D)
        c.vline(ox + 6, oy, oy + 6, BRASS_D)
        rivet(c, ox + 2, oy + 2)
        c.set(ox + 4, oy + 4, BRASS_D)
    save("panel", c, 9)


def plate(name, fill, edge_l, edge, edge_d, size=16, margin=5, accent=None):
    """A small plate: 1px outline, bevelled edge, flat fill. Optional accent strip on the left."""
    c = Canvas(size, size, fill)
    c.hline(0, size - 1, 0, CHAR)
    c.hline(0, size - 1, size - 1, CHAR)
    c.vline(0, 0, size - 1, CHAR)
    c.vline(size - 1, 0, size - 1, CHAR)
    c.hline(1, size - 2, 1, edge_l)
    c.vline(1, 1, size - 2, edge_l)
    c.hline(1, size - 2, size - 2, edge_d)
    c.vline(size - 2, 1, size - 2, edge_d)
    c.set(1, size - 2, edge)
    c.set(size - 2, 1, edge)
    if accent:
        c.rect(2, 2, 2, size - 4, accent)
    save(name, c, margin)


def inset(name, fill, rim, size=16, margin=4, selected=False):
    """A recessed well (slots, sections): shadow on top/left, catch-light bottom/right."""
    c = Canvas(size, size, fill)
    dark = shade(fill, -0.5)
    light = shade(fill, 0.18)
    c.hline(0, size - 1, 0, dark)
    c.vline(0, 0, size - 1, dark)
    c.hline(1, size - 1, size - 1, light)
    c.vline(size - 1, 1, size - 1, light)
    c.hline(1, size - 2, 1, shade(fill, -0.25))
    c.vline(1, 1, size - 2, shade(fill, -0.25))
    if rim:
        for (x, y) in [(0, 0), (size - 1, 0), (0, size - 1), (size - 1, size - 1)]:
            pass
        c.hline(0, size - 1, 0, rim)
        c.hline(0, size - 1, size - 1, rim)
        c.vline(0, 0, size - 1, rim)
        c.vline(size - 1, 0, size - 1, rim)
    if selected:
        # amber corner ticks, two pixels each way
        for (x, y, dx, dy) in [(0, 0, 1, 1), (size - 1, 0, -1, 1), (0, size - 1, 1, -1), (size - 1, size - 1, -1, -1)]:
            for k in range(4):
                c.set(x + dx * k, y, AMBER_L)
                c.set(x, y + dy * k, AMBER_L)
    save(name, c, margin)


def focus_brackets():
    """Focus: amber corner brackets, nothing else, so it can sit over any control."""
    S = 16
    c = Canvas(S, S)
    for (x, y, dx, dy) in [(0, 0, 1, 1), (S - 1, 0, -1, 1), (0, S - 1, 1, -1), (S - 1, S - 1, -1, -1)]:
        for k in range(5):
            c.set(x + dx * k, y, AMBER)
            c.set(x, y + dy * k, AMBER)
            c.set(x + dx * k, y + dy, shade(AMBER, -0.3))
            c.set(x + dx, y + dy * k, shade(AMBER, -0.3))
    save("focus", c, 6)


def tab(name, fill, edge, top):
    S = 16
    c = Canvas(S, S, fill)
    c.hline(0, S - 1, 0, CHAR)
    c.vline(0, 0, S - 1, CHAR)
    c.vline(S - 1, 0, S - 1, CHAR)
    c.hline(1, S - 2, 1, top)
    c.vline(1, 1, S - 1, edge)
    c.vline(S - 2, 1, S - 1, shade(edge, -0.3))
    save(name, c, 5)


def rule():
    """Divider: a brass line with a small lozenge in the middle (stretches from both ends)."""
    W, H = 40, 7
    c = Canvas(W, H)
    c.hline(0, W - 1, 3, BRASS_D)
    c.hline(2, W - 3, 2, shade(BRASS_D, -0.4))
    m = W // 2
    for k in range(4):
        c.hline(m - k, m + k - 1, 3 - (3 - k), BRASS)
    for dy in range(-3, 4):
        half = 3 - abs(dy)
        c.hline(m - half - 1, m + half, 3 + dy, BRASS if dy <= 0 else BRASS_D)
    c.set(m - 1, 2, BRASS_L)
    c.set(m, 2, BRASS_L)
    save("rule", c, 0)
    META["rule"]["center"] = m * SCALE


def toast_plate():
    S = 16
    c = Canvas(S, S, pal("ui_bg")[:3] + (240,))
    c.hline(0, S - 1, 0, CHAR)
    c.hline(0, S - 1, S - 1, CHAR)
    c.vline(0, 0, S - 1, CHAR)
    c.vline(S - 1, 0, S - 1, CHAR)
    c.hline(1, S - 2, 1, BRASS_D)
    c.hline(1, S - 2, S - 2, shade(BRASS_D, -0.4))
    c.vline(S - 2, 1, S - 2, shade(BRASS_D, -0.4))
    save("toast", c, 5)


def hud_plate():
    """Small HUD plaques (clock, money, tool): darker, translucent, brass hairline, rivets."""
    S = 20
    fill = pal("ui_bg")[:3] + (228,)
    c = Canvas(S, S, fill)
    c.hline(0, S - 1, 0, CHAR)
    c.hline(0, S - 1, S - 1, CHAR)
    c.vline(0, 0, S - 1, CHAR)
    c.vline(S - 1, 0, S - 1, CHAR)
    c.hline(1, S - 2, 1, BRASS)
    c.vline(1, 1, S - 2, BRASS)
    c.hline(1, S - 2, S - 2, BRASS_D)
    c.vline(S - 2, 1, S - 2, BRASS_D)
    for (x, y) in [(3, 3), (S - 5, 3), (3, S - 5), (S - 5, S - 5)]:
        rivet(c, x, y)
    save("hud", c, 6)


def gauge():
    """Gauge track and fill for the breath meter: a recessed glass tube and a liquid fill."""
    W, H = 24, 8
    c = Canvas(W, H, shade(BASALT, -0.3))
    c.hline(0, W - 1, 0, CHAR)
    c.hline(0, W - 1, H - 1, BRASS_D)
    c.vline(0, 0, H - 1, CHAR)
    c.vline(W - 1, 0, H - 1, BRASS_D)
    c.hline(1, W - 2, 1, shade(BASALT, -0.55))
    save("gauge_track", c, 3)
    f = Canvas(W, H, (0, 0, 0, 0))
    for y in range(1, H - 1):
        col = CYAN if y > 2 else shade(CYAN, 0.45)
        if y >= H - 3:
            col = pal("glow_dark")
        f.hline(1, W - 2, y, col)
    save("gauge_fill", f, 3)


def switch(on):
    """A toggle: a recessed track, lit amber when on, with a brass knob."""
    W, H = 18, 10
    c = Canvas(W, H)
    track = shade(AMBER, -0.35) if on else shade(BASALT, -0.25)
    c.rect(1, 2, W - 2, H - 4, track)
    c.hline(2, W - 3, 1, CHAR)
    c.hline(2, W - 3, H - 2, CHAR)
    c.vline(0, 3, H - 4, CHAR)
    c.vline(W - 1, 3, H - 4, CHAR)
    c.hline(2, W - 3, 2, shade(track, -0.3))
    kx = W - 9 if on else 1
    c.rect(kx, 0, 8, H, CHAR)
    c.rect(kx + 1, 1, 6, H - 2, BRASS)
    c.hline(kx + 1, kx + 6, 1, BRASS_L)
    c.hline(kx + 1, kx + 6, H - 2, BRASS_D)
    c.set(kx + 3, 4, BRASS_D)
    c.set(kx + 4, 5, BRASS_D)
    save("switch_on" if on else "switch_off", c, 0)


def tickbox(on):
    S = 10
    c = Canvas(S, S, shade(BASALT, -0.3))
    c.hline(0, S - 1, 0, CHAR)
    c.vline(0, 0, S - 1, CHAR)
    c.hline(0, S - 1, S - 1, BRASS_D)
    c.vline(S - 1, 0, S - 1, BRASS_D)
    if on:
        for (x, y) in [(2, 5), (3, 6), (4, 7), (5, 6), (6, 5), (7, 4), (7, 3)]:
            c.set(x, y, AMBER_L)
            c.set(x, y + 1, shade(AMBER, -0.3))
    save("tick_on" if on else "tick_off", c, 0)


def build():
    panel()
    switch(True)
    switch(False)
    tickbox(True)
    tickbox(False)
    plate("button", (27, 26, 33, 236), pal("ash"), SLATE, shade(BASALT, -0.3))
    plate("button_hover", (42, 39, 51, 245), BRASS_L, BRASS, BRASS_D)
    plate("button_pressed", (16, 15, 20, 245), BRASS_D, BRASS, AMBER)
    plate("button_disabled", (22, 21, 26, 240), shade(SLATE, -0.2), shade(SLATE, -0.3), shade(BASALT, -0.3))
    focus_brackets()
    inset("well", (20, 19, 25, 235), None)
    inset("slot", (24, 22, 30, 240), shade(BRASS_D, -0.25), size=20, margin=5)
    inset("slot_selected", (40, 34, 30, 245), AMBER, size=20, margin=5, selected=True)
    tab("tab", (27, 26, 33, 236), SLATE, shade(SLATE, 0.1))
    tab("tab_selected", pal("ui_panel")[:3] + (255,), BRASS, BRASS_L)
    rule()
    toast_plate()
    hud_plate()
    gauge()
    with open(os.path.join(OUT, "ui.json"), "w") as f:
        json.dump(META, f, indent=1)
    # preview sheet
    names = list(META)
    sheet = Image.new("RGBA", (len(names) * 72, 80), (40, 40, 48, 255))
    for i, n in enumerate(names):
        im = Image.open(os.path.join(OUT, n + ".png"))
        sheet.paste(im, (i * 72 + 4, 4), im)
    sheet.save(os.path.join(os.path.dirname(__file__), "preview_ui.png"))
    print("ui frames:", ", ".join(names))


if __name__ == "__main__":
    build()
