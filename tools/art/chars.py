"""Character sprite sheets for Bellows.

Characters are built as paper dolls from deliberately chosen shapes (per-character
proportions, costume pieces and silhouettes) with hand-placed facial pixels; animation
comes from pose parameters (stride, bob, arm swing, tool arc), so every frame is
consistent.  Output per character: assets/textures/chars/<id>.png (+ _emit.png) and
<id>.json describing frame size and animations.

Sheet rows (4 frames each):
  0 idle_down   1 idle_up   2 idle_side
  3 walk_down   4 walk_up   5 walk_side
  6 work_down   7 work_up   8 work_side
  9 talk_down   10 emote_down (happy, sad, surprised, annoyed)
"""
import json
import math
import os

from px import Canvas, TEX, pal, shade, ramp, mix, hexc

OUT = os.path.join(TEX, "chars")

ROWS = ["idle_down", "idle_up", "idle_side", "walk_down", "walk_up", "walk_side",
        "work_down", "work_up", "work_side", "talk_down", "emote_down"]
FPS = {"idle": 3, "walk": 8, "work": 8, "talk": 8, "emote": 1}


def C(h):
    return hexc(h)


class Pose:
    def __init__(self, view, anim, f):
        self.view = view        # down | up | side
        self.anim = anim        # idle | walk | work | talk | emote
        self.f = f
        self.bob = 0
        self.stride = 0         # -1, 0, 1
        self.arm = 0            # arm swing -1..1
        self.breath = 0
        self.mouth = 0
        self.emote = ""
        self.tool = 0           # work arc phase 0..3
        if anim == "idle":
            self.breath = [0, 0, 1, 1][f]
        elif anim == "walk":
            self.stride = [1, 0, -1, 0][f]
            self.bob = [0, -1, 0, -1][f]
            self.arm = [-1, 0, 1, 0][f]
        elif anim == "work":
            self.tool = f
            self.bob = [0, -1, 0, 1][f]
        elif anim == "talk":
            self.mouth = [1, 0, 1, 0][f]
        elif anim == "emote":
            self.emote = ["happy", "sad", "surprised", "annoyed"][f]


# ---------------------------------------------------------------------------------------------
# Shared body parts
# ---------------------------------------------------------------------------------------------
def legs(c, p, cx, top, bottom, trouser, boot, gap=1, width=3, boot_h=3, wide_boot=1):
    """Two legs from `top` to `bottom` (feet line). Stride moves feet apart (side view)
    or lifts one foot (front/back view)."""
    t = ramp(trouser, 3, 0.3)
    b = ramp(boot, 3, 0.3)
    if p.view == "side":
        for leg, sgn in ((0, 1), (1, -1)):
            off = p.stride * sgn * 2
            lift = 1 if (p.stride != 0 and sgn == p.stride) else 0
            col = t[1] if leg == 0 else t[0]
            x0 = cx - 1 + off // 2
            for y in range(top, bottom - boot_h + 1 - lift):
                k = (y - top) / max(1, bottom - top)
                xx = x0 + int(round(off * 0.5 * k))
                c.rect(xx, y, width - 1, 1, col)
            fx = x0 + off // 2 + int(round(off * 0.5))
            c.rect(fx - 1, bottom - boot_h + 1 - lift, width + 1 + wide_boot, boot_h - 1, b[1] if leg == 0 else b[0])
            c.rect(fx - 1, bottom - lift, width + 1 + wide_boot, 1, b[0])
        return
    for side, sgn in ((-1, -1), (1, 1)):
        lift = 1 if p.stride == sgn else 0
        x0 = cx + (gap // 2 if sgn > 0 else -(gap // 2) - width) + (0 if sgn > 0 else 0)
        if sgn < 0:
            x0 = cx - gap // 2 - width
        else:
            x0 = cx + (gap + 1) // 2
        for y in range(top, bottom - boot_h + 1 - lift):
            for x in range(x0, x0 + width):
                col = t[1]
                if (sgn < 0 and x == x0) or (sgn > 0 and x == x0 + width - 1):
                    col = t[0]
                if y == top:
                    col = t[0]
                c.set(x, y, col)
        by = bottom - boot_h + 1 - lift
        bx = x0 - (wide_boot if sgn < 0 else 0)
        c.rect(bx, by, width + wide_boot, boot_h, b[1])
        c.rect(bx, by + boot_h - 1, width + wide_boot, 1, b[0])
        c.set(bx + (0 if sgn < 0 else width + wide_boot - 1), by, b[2])


def arm(c, x, y, length, sleeve, hand, swing=0, width=2, side_view=False):
    s = ramp(sleeve, 3, 0.3)
    for i in range(length):
        xx = x + (int(round(swing * i / length)) if side_view else 0)
        yy = y + i - (abs(swing) if not side_view and i > length // 2 and swing < 0 else 0)
        c.rect(xx, yy, width, 1, s[1] if i % 3 else s[0])
    hx = x + (swing if side_view else 0)
    c.rect(hx, y + length, width, 2, hand)
    c.set(hx + width - 1, y + length + 1, shade(hand, -0.3))


def face_front(c, cx, y, skin, eye, p, eye_gap=3, mouth_y=4, blush=None):
    """Eyes, brows, mouth for front view. y = eye row."""
    ex1, ex2 = cx - eye_gap // 2 - 1, cx + (eye_gap + 1) // 2
    e = p.emote
    if e == "happy":
        c.set(ex1, y, eye); c.set(ex2, y, eye)
        c.set(ex1 - 1, y + 1, eye); c.set(ex2 + 1, y + 1, eye)
        c.hline(cx - 1, cx, y + mouth_y - 1, shade(skin, -0.5))
        c.set(cx - 2, y + mouth_y - 2, shade(skin, -0.5)); c.set(cx + 1, y + mouth_y - 2, shade(skin, -0.5))
    elif e == "sad":
        c.set(ex1, y + 1, eye); c.set(ex2, y + 1, eye)
        c.set(ex1 - 1, y - 1, shade(skin, -0.45)); c.set(ex2 + 1, y - 1, shade(skin, -0.45))
        c.hline(cx - 1, cx, y + mouth_y, shade(skin, -0.5))
    elif e == "surprised":
        c.rect(ex1, y - 1, 1, 2, eye); c.rect(ex2, y - 1, 1, 2, eye)
        c.rect(cx - 1, y + mouth_y - 1, 2, 2, shade(skin, -0.6))
    elif e == "annoyed":
        c.set(ex1, y, eye); c.set(ex2, y, eye)
        c.hline(ex1 - 1, ex1, y - 1, shade(skin, -0.55)); c.hline(ex2, ex2 + 1, y - 1, shade(skin, -0.55))
        c.hline(cx - 1, cx + 1, y + mouth_y - 1, shade(skin, -0.5))
    else:
        c.rect(ex1, y, 1, 2 if p.breath == 0 or p.anim != "idle" else 1, eye)
        c.rect(ex2, y, 1, 2 if p.breath == 0 or p.anim != "idle" else 1, eye)
        if p.mouth:
            c.rect(cx - 1, y + mouth_y - 1, 2, 1, shade(skin, -0.6))
        else:
            c.hline(cx - 1, cx, y + mouth_y - 1, shade(skin, -0.42))
    if blush:
        c.set(ex1 - 1, y + 2, blush); c.set(ex2 + 1, y + 2, blush)


def head_shape(c, cx, top, w, h, skin):
    s = ramp(skin, 3, 0.3)
    x0 = cx - w // 2
    for y in range(top, top + h):
        inset = 1 if y in (top, top + h - 1) else 0
        for x in range(x0 + inset, x0 + w - inset):
            col = s[1]
            if x == x0 + inset and y > top:
                col = s[2]
            if x >= x0 + w - 1 - inset or y == top + h - 1:
                col = s[0]
            c.set(x, y, col)


def sheet(draw, fw, fh, cid, emit=False):
    rows = len(ROWS)
    big = Canvas(fw * 4, fh * rows)
    glow = Canvas(fw * 4, fh * rows)
    for r, name in enumerate(ROWS):
        anim, view = name.split("_")
        for f in range(4):
            frame = Canvas(fw, fh)
            g = Canvas(fw, fh)
            p = Pose(view, anim, f)
            draw(frame, g, p)
            frame.outline(-0.62)
            big.paste(frame, f * fw, r * fh)
            glow.paste(g, f * fw, r * fh)
    os.makedirs(OUT, exist_ok=True)
    big.save(os.path.join(OUT, cid + ".png"))
    has_emit = emit
    if emit:
        glow.save(os.path.join(OUT, cid + "_emit.png"))
    anims = {}
    for r, name in enumerate(ROWS):
        anim = name.split("_")[0]
        anims[name] = {"row": r, "frames": 4 if anim != "emote" else 4, "fps": FPS[anim], "loop": anim not in ("emote",)}
    with open(os.path.join(OUT, cid + ".json"), "w") as fjson:
        json.dump({"w": fw, "h": fh, "cols": 4, "rows": rows, "emit": has_emit, "anims": anims}, fjson, indent=1)
    return big


# ---------------------------------------------------------------------------------------------
# The player: a surface salvager
# ---------------------------------------------------------------------------------------------
PLAYER = {
    "skin": C("#b97f56"), "hair": C("#3a2a24"), "cap": C("#5c4636"), "brass": pal("brass"),
    "cape": C("#3b5559"), "vest": C("#7a6448"), "shirt": C("#c9b994"), "trouser": C("#3a3946"),
    "boot": C("#4a3529"), "rope": C("#b89a62"), "glove": C("#6b5040"), "eye": pal("charcoal"),
}


def draw_player(c, g, p):
    P = PLAYER
    cx = 12
    by = 31 + p.bob
    leg_top = 22 + p.bob
    legs(c, p, cx, leg_top, by, P["trouser"], P["boot"], gap=1, width=3, boot_h=3)
    tool_up = p.anim == "work" and p.tool in (0, 1)
    if p.view == "down":
        torso_top = 13 + p.bob + p.breath
        # back arm parts / cape behind
        cape = ramp(P["cape"], 3, 0.35)
        c.rect(cx - 7, torso_top, 14, 8 - p.breath, cape[0])
        # torso: shirt + vest
        vest = ramp(P["vest"], 3, 0.3)
        c.rect(cx - 4, torso_top, 8, leg_top - torso_top + 1, vest[1])
        c.rect(cx - 1, torso_top + 1, 2, 4, P["shirt"])
        c.vline(cx - 4, torso_top, leg_top, vest[2])
        c.vline(cx + 3, torso_top, leg_top, vest[0])
        c.hline(cx - 4, cx + 3, leg_top - 1, C("#2c221c"))   # belt
        c.set(cx, leg_top - 1, P["brass"])
        c.rect(cx + 2, leg_top - 2, 2, 2, shade(P["vest"], -0.4))  # pouch
        # capelet over shoulders
        for y in range(4):
            w = 7 + (1 if y > 0 else 0) - (0 if y < 3 else 1)
            c.hline(cx - w, cx + w - 1, torso_top + y, cape[1] if y < 3 else cape[0])
        c.hline(cx - 6, cx - 1, torso_top, cape[2])
        # rope coil on the character's right shoulder (viewer's left)
        rope = ramp(P["rope"], 3, 0.3)
        c.ellipse(cx - 6, torso_top + 2, 2.6, 2.2, rope[1])
        c.ellipse(cx - 6, torso_top + 2, 1.2, 1.0, rope[0])
        c.set(cx - 7, torso_top + 1, rope[2])
        # arms
        swing = p.arm
        if tool_up:
            arm(c, cx - 7, torso_top + 1 - p.tool, 5, P["cape"], P["glove"])
            arm(c, cx + 5, torso_top + 1 - p.tool, 5, P["cape"], P["glove"])
        else:
            arm(c, cx - 7, torso_top + 3, 6 + (1 if swing > 0 else 0), P["cape"], P["glove"])
            arm(c, cx + 5, torso_top + 3, 6 + (1 if swing < 0 else 0), P["cape"], P["glove"])
        # head
        hy = 3 + p.bob + (1 if p.breath and p.f == 3 else 0)
        head_shape(c, cx, hy + 3, 9, 7, P["skin"])
        hair = ramp(P["hair"], 2, 0.3)
        c.rect(cx - 5, hy + 4, 1, 4, hair[0])
        c.rect(cx + 4, hy + 4, 1, 4, hair[0])
        # leather cap with brass headlamp
        cap = ramp(P["cap"], 3, 0.32)
        for y in range(4):
            w = [3, 4, 5, 5][y]
            c.hline(cx - w, cx + w - 1, hy + y, cap[1])
        c.hline(cx - 5, cx + 4, hy + 3, cap[0])
        c.hline(cx - 2, cx + 1, hy, cap[2])
        c.rect(cx - 1, hy + 1, 2, 2, P["brass"])
        c.set(cx - 1, hy + 1, pal("amber_light"))
        c.set(cx, hy + 1, pal("cream"))
        g.set(cx - 1, hy + 1, pal("amber")); g.set(cx, hy + 1, pal("amber_light"))
        face_front(c, cx, hy + 5, P["skin"], P["eye"], p, eye_gap=3, mouth_y=4)
    elif p.view == "up":
        torso_top = 13 + p.bob + p.breath
        vest = ramp(P["vest"], 3, 0.3)
        c.rect(cx - 4, torso_top, 8, leg_top - torso_top + 1, vest[0])
        cape = ramp(P["cape"], 3, 0.35)
        for y in range(9 - p.breath):
            w = 6 + (1 if y < 6 else 0)
            c.hline(cx - w, cx + w - 1, torso_top + y, cape[1] if 1 < y < 7 else cape[0])
        c.vline(cx - 1, torso_top + 2, torso_top + 7, cape[0])
        c.hline(cx - 6, cx + 5, torso_top, cape[2])
        rope = ramp(P["rope"], 3, 0.3)
        c.ellipse(cx + 5, torso_top + 2, 2.6, 2.2, rope[1])
        c.ellipse(cx + 5, torso_top + 2, 1.2, 1.0, rope[0])
        swing = p.arm
        if tool_up:
            arm(c, cx - 8, torso_top + 1 - p.tool, 5, P["cape"], P["glove"])
            arm(c, cx + 6, torso_top + 1 - p.tool, 5, P["cape"], P["glove"])
        else:
            arm(c, cx - 8, torso_top + 3, 6 + (1 if swing < 0 else 0), P["cape"], P["glove"])
            arm(c, cx + 6, torso_top + 3, 6 + (1 if swing > 0 else 0), P["cape"], P["glove"])
        hy = 3 + p.bob + (1 if p.breath and p.f == 3 else 0)
        hair = ramp(P["hair"], 3, 0.3)
        head_shape(c, cx, hy + 3, 9, 7, P["hair"])
        c.rect(cx - 3, hy + 8, 6, 2, shade(P["skin"], -0.25))  # nape
        cap = ramp(P["cap"], 3, 0.32)
        for y in range(5):
            w = [3, 4, 5, 5, 5][y]
            c.hline(cx - w, cx + w - 1, hy + y, cap[1] if y < 4 else cap[0])
        c.hline(cx - 2, cx + 1, hy, cap[2])
        c.hline(cx - 5, cx + 4, hy + 2, C("#2a201a"))  # lamp strap
    else:  # side (facing right)
        torso_top = 13 + p.bob + p.breath
        vest = ramp(P["vest"], 3, 0.3)
        c.rect(cx - 3, torso_top, 7, leg_top - torso_top + 1, vest[1])
        c.vline(cx + 3, torso_top + 1, leg_top, vest[0])
        c.hline(cx - 3, cx + 3, leg_top - 1, C("#2c221c"))
        cape = ramp(P["cape"], 3, 0.35)
        # cape hangs behind (to the left), sways with the stride
        sway = -p.stride
        for y in range(9 - p.breath):
            w = 3 + y // 3
            c.hline(cx - 3 - w + (sway if y > 5 else 0), cx - 1, torso_top + y, cape[1] if y < 6 else cape[0])
        c.hline(cx - 4, cx + 2, torso_top, cape[2])
        c.hline(cx - 4, cx + 2, torso_top + 1, cape[1])
        rope = ramp(P["rope"], 3, 0.3)
        c.ellipse(cx - 3, torso_top + 3, 2.4, 2.4, rope[1])
        c.ellipse(cx - 3, torso_top + 3, 1.1, 1.1, rope[0])
        # arm (front)
        if tool_up:
            a = [(-2, -5), (1, -6), (4, -1), (3, 2)][p.tool]
            c.line(cx, torso_top + 2, cx + a[0], torso_top + 2 + a[1], P["cape"])
            c.rect(cx + a[0], torso_top + 2 + a[1], 2, 2, P["glove"])
        else:
            arm(c, cx, torso_top + 2, 6, P["cape"], P["glove"], swing=p.arm * 2, side_view=True)
        hy = 3 + p.bob + (1 if p.breath and p.f == 3 else 0)
        head_shape(c, cx + 1, hy + 3, 8, 7, P["skin"])
        hair = ramp(P["hair"], 2, 0.3)
        c.rect(cx - 3, hy + 4, 3, 4, hair[0])
        cap = ramp(P["cap"], 3, 0.32)
        for y in range(4):
            c.hline(cx - 3, cx + 3 + (1 if y == 3 else 0), hy + y, cap[1])
        c.hline(cx - 3, cx + 5, hy + 3, cap[0])   # brim
        c.hline(cx - 1, cx + 2, hy, cap[2])
        c.rect(cx + 3, hy + 1, 2, 2, P["brass"])
        c.set(cx + 4, hy + 1, pal("amber_light"))
        g.set(cx + 4, hy + 1, pal("amber_light"))
        # eye + nose + mouth
        ey = hy + 5
        if p.emote == "happy":
            c.set(cx + 3, ey, P["eye"])
        else:
            c.rect(cx + 3, ey, 1, 2, P["eye"])
        c.set(cx + 5, ey + 1, shade(P["skin"], -0.25))
        c.set(cx + 4, ey + 3, shade(P["skin"], -0.45))
    # tool arc in work frames (down/up views): a simple tool shaft
    if p.anim == "work" and p.view in ("down", "up"):
        shaft = shade(pal("clay"), -0.1)
        ty = [4, 2, 12, 16][p.tool] + p.bob
        c.vline(cx + 6, ty, ty + 6, shaft)
        c.rect(cx + 5, ty - 1, 3, 2, pal("ash"))


# ---------------------------------------------------------------------------------------------
# Barnaby Coil: tall, stooped, cracked brass breathing helmet, long dark oilskin coat
# ---------------------------------------------------------------------------------------------
BARNABY = {
    "coat": C("#2e2a3a"), "coat_light": C("#45405a"), "brass": C("#a8843f"), "verd": pal("verdigris"),
    "glass": C("#1d2a30"), "glint": pal("glow"), "glove": C("#c9b994"), "trouser": C("#262430"),
    "boot": C("#2b221d"), "moss": pal("glow"), "toolroll": C("#6b5040"),
}


def helmet(c, g, cx, top, p, view):
    B = BARNABY
    br = ramp(B["brass"], 4, 0.38)
    r = 6
    hcx, hcy = cx + (1 if view == "side" else 0) - 0.5, top + 6
    # dome
    for y in range(top, top + 12):
        for x in range(cx - 7, cx + 8):
            d = math.hypot(x + 0.5 - hcx - 0.5, (y + 0.5 - hcy) * 1.05)
            if d <= r + 0.3:
                col = br[2] if (x - hcx) + (y - hcy) < -3 else (br[0] if (x - hcx) + (y - hcy) > 4 else br[1])
                c.set(x, y, col)
    # verdigris patina patches
    for (dx, dy) in [(-4, 2), (-5, 4), (3, 8), (4, 7)]:
        c.set(int(hcx + dx), int(hcy + dy - 6 + 6) - 6 + top + 0, B["verd"]) if False else None
    for (x, y) in [(cx - 5, top + 3), (cx - 6, top + 5), (cx + 4, top + 9), (cx + 5, top + 8)]:
        c.set(x, y, B["verd"])
    # rivets ring
    for k in range(10):
        a = k / 10 * math.tau
        x = int(round(hcx + 0.5 + math.cos(a) * (r - 0.6)))
        y = int(round(hcy + math.sin(a) * (r - 0.6)))
        if c.get(x, y)[3] > 0:
            c.set(x, y, br[3])
    if view == "up":
        # back of the helmet: air hose loop
        c.hline(cx - 3, cx + 2, top + 10, br[0])
        c.line(cx - 4, top + 11, cx - 6, top + 14, shade(B["coat"], 0.1))
        return
    # faceplate
    fx = cx + (2 if view == "side" else 0)
    fw = 4 if view == "side" else 4
    for y in range(top + 3, top + 10):
        for x in range(fx - fw, fx + fw):
            if math.hypot(x + 0.5 - fx, (y + 0.5 - (top + 6.5)) * 1.1) <= 3.6:
                c.set(x, y, B["glass"])
    # crack across the glass with a thread of glowing moss
    crack = [(fx - 3, top + 4), (fx - 2, top + 5), (fx - 1, top + 5), (fx, top + 6), (fx + 1, top + 7), (fx + 1, top + 8)]
    for i, (x, y) in enumerate(crack):
        c.set(x, y, shade(B["glass"], 0.45) if i % 2 else B["moss"])
        if i % 2 == 0:
            g.set(x, y, shade(B["moss"], -0.25))
    # eye glints: expression lives here
    e = p.emote
    ey = top + 6
    if view == "side":
        eyes = [(fx + 1, ey)]
    else:
        eyes = [(fx - 2, ey), (fx + 1, ey)]
    for (x, y) in eyes:
        if e == "happy":
            c.set(x, y, B["glint"]); c.set(x + 1, y, B["glint"])
            g.set(x, y, B["glint"]); g.set(x + 1, y, B["glint"])
        elif e == "sad":
            c.set(x, y + 1, shade(B["glint"], -0.35)); g.set(x, y + 1, shade(B["glint"], -0.55))
        elif e == "surprised":
            c.rect(x, y - 1, 1, 3, B["glint"]); g.rect(x, y - 1, 1, 3, B["glint"])
        elif e == "annoyed":
            c.set(x, y, B["glint"]); g.set(x, y, B["glint"])
            c.set(x - 1 if x < fx else x + 1, y - 1, shade(B["glass"], 0.5))
        else:
            h = 1 if (p.anim == "idle" and p.f == 3) else 2
            c.rect(x, y, 1, h, B["glint"]); g.rect(x, y, 1, h, shade(B["glint"], -0.1))
    # rim of the faceplate
    for k in range(16):
        a = k / 16 * math.tau
        x = int(round(fx + math.cos(a) * 3.8 - 0.5))
        y = int(round(top + 6.5 + math.sin(a) * 3.5 - 0.5))
        c.set(x, y, br[3] if k < 8 else br[1])
    # breathing valve at the chin
    c.rect(fx - 1, top + 10, 2, 2, br[0])
    c.set(fx - 1, top + 10, br[2])


def draw_barnaby(c, g, p):
    B = BARNABY
    cx = 13
    by = 35 + p.bob
    leg_top = 27 + p.bob
    legs(c, p, cx, leg_top, by, B["trouser"], B["boot"], gap=1, width=3, boot_h=3)
    coat = ramp(B["coat"], 4, 0.35)
    torso_top = 14 + p.bob + p.breath
    tool_up = p.anim == "work" and p.tool in (0, 1)
    if p.view in ("down", "up"):
        # long coat: wide at the shoulders, flares to the knees
        for y in range(torso_top, leg_top + 5):
            k = (y - torso_top) / (leg_top + 5 - torso_top)
            w = int(6 + k * 2.5)
            for x in range(cx - w, cx + w):
                col = coat[1]
                if x <= cx - w + 1:
                    col = coat[2]
                elif x >= cx + w - 2:
                    col = coat[0]
                if p.view == "down" and abs(x - cx + 0.5) < 1 and y > torso_top + 3:
                    col = coat[0]  # coat opening
                c.set(x, y, col)
        # hem flutters with the stride
        if p.stride:
            c.hline(cx - 8, cx - 5, leg_top + 5, (0, 0, 0, 0)) if p.stride > 0 else c.hline(cx + 5, cx + 8, leg_top + 5, (0, 0, 0, 0))
        # stoop: shoulders hunched forward (a dark yoke)
        c.hline(cx - 6, cx + 5, torso_top, coat[3] if p.view == "down" else coat[2])
        c.hline(cx - 7, cx + 6, torso_top + 1, coat[2])
        if p.view == "down":
            # tool roll on the hip, brass buckles
            c.rect(cx + 3, leg_top - 3, 3, 4, B["toolroll"])
            c.set(cx + 4, leg_top - 2, B["brass"])
            c.set(cx - 2, torso_top + 6, B["brass"])
            c.set(cx - 2, torso_top + 9, B["brass"])
        # long arms (he is long-limbed)
        if tool_up:
            arm(c, cx - 8, torso_top + 1 - p.tool, 6, B["coat"], B["glove"])
            arm(c, cx + 6, torso_top + 1 - p.tool, 6, B["coat"], B["glove"])
        else:
            arm(c, cx - 8, torso_top + 2, 9 + (1 if p.arm > 0 else 0), B["coat"], B["glove"])
            arm(c, cx + 6, torso_top + 2, 9 + (1 if p.arm < 0 else 0), B["coat"], B["glove"])
        helmet(c, g, cx, 2 + p.bob + (1 if p.f == 3 and p.anim == "idle" else 0), p, p.view)
    else:
        for y in range(torso_top, leg_top + 5):
            k = (y - torso_top) / (leg_top + 5 - torso_top)
            back = int(4 + k * 3) + (-p.stride if y > leg_top else 0)
            for x in range(cx - back, cx + 4):
                col = coat[1] if x < cx + 2 else coat[0]
                if x <= cx - back + 1:
                    col = coat[2]
                c.set(x, y, col)
        c.hline(cx - 4, cx + 4, torso_top, coat[2])
        c.rect(cx - 2, leg_top - 3, 3, 4, B["toolroll"])
        if tool_up:
            a = [(-1, -6), (2, -7), (5, -1), (4, 2)][p.tool]
            c.line(cx + 1, torso_top + 2, cx + 1 + a[0], torso_top + 2 + a[1], B["coat_light"])
            c.rect(cx + 1 + a[0], torso_top + 2 + a[1], 2, 2, B["glove"])
        else:
            arm(c, cx + 1, torso_top + 2, 9, B["coat"], B["glove"], swing=p.arm * 2, side_view=True)
        # stooped: helmet sits forward of the shoulders
        helmet(c, g, cx + 2, 3 + p.bob + (1 if p.f == 3 and p.anim == "idle" else 0), p, "side")


# ---------------------------------------------------------------------------------------------
def build(only=None):
    specs = [("player", draw_player, 24, 32, True), ("barnaby", draw_barnaby, 26, 36, True)]
    for cid, fn, w, h, emit in specs:
        if only and cid not in only:
            continue
        big = sheet(fn, w, h, cid, emit)
        big.img.resize((big.w * 4, big.h * 4), 0).save(os.path.join(os.path.dirname(__file__), f"preview_{cid}.png"))
        print(f"{cid}: {big.w}x{big.h}")


if __name__ == "__main__":
    import sys
    build(sys.argv[1:] or None)
