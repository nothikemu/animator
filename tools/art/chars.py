"""Character sprite sheets for Bellows.

Characters are paper dolls on the shared skeleton in rig.py: per-character proportions,
costume pieces and silhouettes, with hand-placed facial pixels. Every animation in rig.LIB is
a table of poses, so a new animation works for everyone with the right proportions.

Output per character: assets/textures/chars/<id>.png (+ _emit.png for what glows) and <id>.json
with frame size, each animation's first frame, length, rate, loop flag and events, and the
frames used for dialogue portraits.
"""
import math
import os

from px import Canvas, TEX, pal, shade, ramp, mix, hexc
import rig
from rig import thick, ik, draw_item, draw_marks

OUT = os.path.join(TEX, "chars")


def C(h):
    return hexc(h)


# ---------------------------------------------------------------------------------------------
# Faces
# ---------------------------------------------------------------------------------------------
def face_front(c, cx, y, skin, eye, p, eye_gap=3, mouth_y=4, blush=None):
    """Eyes, brows and mouth for the front view. y = eye row."""
    lk = p.look
    ex1, ex2 = cx - eye_gap // 2 - 1 + lk, cx + (eye_gap + 1) // 2 + lk
    dark = shade(skin, -0.5)
    e = p.emote
    if e == "happy":
        for ex in (ex1, ex2):
            c.set(ex, y, eye); c.set(ex - 1, y + 1, eye); c.set(ex + 1, y + 1, eye)
        c.hline(cx - 1, cx, y + mouth_y - 1, dark)
        c.set(cx - 2, y + mouth_y - 2, dark); c.set(cx + 1, y + mouth_y - 2, dark)
        if p.mouth:
            c.rect(cx - 1, y + mouth_y - 1, 2, 2, shade(skin, -0.62))
    elif e == "sad":
        c.set(ex1, y + 1, eye); c.set(ex2, y + 1, eye)
        c.set(ex1 - 1, y - 1, shade(skin, -0.45)); c.set(ex2 + 1, y - 1, shade(skin, -0.45))
        c.hline(cx - 1, cx, y + mouth_y, dark)
    elif e == "surprised":
        c.rect(ex1, y - 1, 1, 2, eye); c.rect(ex2, y - 1, 1, 2, eye)
        c.rect(cx - 1, y + mouth_y - 1, 2, 2, shade(skin, -0.62))
    elif e == "annoyed":
        c.set(ex1, y, eye); c.set(ex2, y, eye)
        c.hline(ex1 - 1, ex1, y - 1, shade(skin, -0.55)); c.hline(ex2, ex2 + 1, y - 1, shade(skin, -0.55))
        c.hline(cx - 1, cx + 1, y + mouth_y - 1, dark)
    else:
        for ex in (ex1, ex2):
            if p.eyes == "closed":
                c.hline(ex - (1 if ex == ex1 else 0), ex + (1 if ex == ex2 else 0), y + 1, dark)
            elif p.eyes == "half":
                c.set(ex, y + 1, eye)
            elif p.eyes == "up":
                c.set(ex, y - 1 if ex == ex1 else y - 1, eye); c.set(ex, y, eye)
            else:
                c.rect(ex, y, 1, 2, eye)
        if p.mouth == 2:
            c.rect(cx - 1, y + mouth_y - 1, 2, 2, shade(skin, -0.62))
        elif p.mouth == 1:
            c.rect(cx - 1, y + mouth_y - 1, 2, 1, shade(skin, -0.6))
        else:
            c.hline(cx - 1, cx, y + mouth_y - 1, shade(skin, -0.42))
    if blush:
        c.set(ex1 - 1, y + 2, blush); c.set(ex2 + 1, y + 2, blush)


def face_side(c, x, y, skin, eye, p):
    """Eye, nose and mouth for the side view. (x, y) = eye pixel."""
    if p.emote == "happy" or p.eyes == "closed":
        c.set(x, y + 1, eye if p.emote == "happy" else shade(skin, -0.5))
        if p.emote == "happy":
            c.set(x - 1, y + 1, eye)
    elif p.eyes == "half":
        c.set(x, y + 1, eye)
    elif p.emote == "surprised":
        c.rect(x, y - 1, 1, 2, eye)
    elif p.eyes == "up":
        c.rect(x, y - 1, 1, 2, eye)
    else:
        c.rect(x, y, 1, 2, eye)
    c.set(x + 2, y + 1, shade(skin, -0.25))                 # nose
    mc = shade(skin, -0.55)
    if p.mouth or p.emote == "surprised":
        c.rect(x + 1, y + 3, 1, 2 if p.mouth == 2 else 1, mc)
    elif p.emote == "sad":
        c.set(x + 1, y + 4, mc)
    else:
        c.set(x + 1, y + 3, shade(skin, -0.45))


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


# ---------------------------------------------------------------------------------------------
# Generic humanoid on the skeleton
# ---------------------------------------------------------------------------------------------
def render_humanoid(c, g, p, S):
    view = p.view
    cx = S["cx"]
    feet_y = S["feet"] - p.lift_body
    L = S["leg_len"]
    hip_y = feet_y - L + int(round(p.crouch * L * 0.62)) + p.bob
    torso_top = hip_y - S["torso_h"] + p.breath
    A = S.get("arm", 7)
    tw = S["torso_w"]
    sw = S.get("shoulder_w", tw)
    ctx = {"cx": cx, "torso_top": torso_top, "leg_top": hip_y, "hip_y": hip_y, "by": feet_y,
           "view": view, "tw": tw}
    U = Canvas(c.w, c.h)
    UG = Canvas(c.w, c.h)

    # Shoulders and hand targets in screen space.
    if view == "side":
        sh_near = (cx + S.get("shoulder_x", 0) + 0.5, torso_top + 2)
        sh_far = (cx + S.get("shoulder_x", 0) - 1.5, torso_top + 2)
        shoulders = [sh_near, sh_far]
    else:
        shoulders = [(cx - sw // 2 - 1.5, torso_top + 1), (cx + sw // 2 + 0.5, torso_top + 1)]

    def target(i):
        h = p.hands[i]
        sx, sy = shoulders[i]
        if h is None:
            if view == "side":
                return sx + (0 if i == 0 else 0), sy + A
            return sx, sy + A
        fwd, up = h
        if view == "side":
            return sx + fwd, sy - up
        s_i = -1 if i == 0 else 1
        return sx - s_i * fwd * 0.45, sy - up + fwd * 0.3

    hand_pos = [target(0), target(1)]
    ends = list(hand_pos)

    def draw_arm(layer, i, dark=False):
        sx, sy = shoulders[i]
        tx, ty = hand_pos[i]
        if view == "side":
            pref = (-1, 0.4)
        else:
            pref = (-1 if i == 0 else 1, 0.25)
        elbow, end = ik(sx, sy, tx, ty, A * 0.5, A * 0.5, pref)
        sleeve = S.get("sleeve", S["cloth"])
        sr = ramp(sleeve, 3, 0.3)
        col = sr[0] if dark else sr[1]
        thick(layer, sx, sy, elbow[0], elbow[1], 2, col)
        fore = S.get("forearm", sleeve)
        fr = ramp(fore, 3, 0.3)
        thick(layer, elbow[0], elbow[1], end[0], end[1], 2, fr[0] if dark else fr[1])
        hand = S["hand"] if not dark else shade(S["hand"], -0.25)
        hx, hy = int(math.floor(end[0])), int(math.floor(end[1] + 0.5))
        layer.rect(hx, hy, 2, 2, hand)
        layer.set(hx + 1, hy + 1, shade(hand, -0.3))
        ends[i] = (end[0], end[1])
        return hx + 1, hy + 1

    # --- legs (on the base canvas) ---------------------------------------------------------
    trouser = ramp(S["trouser"], 3, 0.3)
    boot = ramp(S["boot"], 3, 0.3)
    bh = S.get("boot_h", 3)
    if view == "side":
        hip = (cx + S.get("hip_x", 0) + 0.5, hip_y)
        for i in (1, 0):            # far leg first
            fdx, lift = p.feet[i]
            fx, fy = cx + fdx + 0.5, feet_y - lift
            knee, end = ik(hip[0], hip[1], fx, fy - 1, (L - 1) * 0.5, (L - 1) * 0.5, (1, 0))
            col = trouser[0] if i == 1 else trouser[1]
            thick(c, hip[0], hip[1], knee[0], knee[1], 3, col)
            thick(c, knee[0], knee[1], end[0], end[1] - bh + 2, 3, col)
            bx = int(math.floor(end[0])) - 1
            by_ = int(math.floor(end[1] + 0.5))
            bc = boot[0] if i == 1 else boot[1]
            c.rect(bx, by_ - bh + 2, 4 + S.get("toe", 1), bh - 1, bc)
            c.hline(bx, bx + 3 + S.get("toe", 1), by_ + 1 - 0, boot[0])
            if S.get("barefoot"):
                c.rect(bx, by_ - bh + 2, 4, bh - 1, shade(S["skin"], -0.15 if i == 0 else -0.3))
    else:
        for i in (0, 1):
            s_i = -1 if i == 0 else 1
            hx = cx + s_i * S.get("hip_dx", 2)
            fdx, lift = p.feet[i]
            fy = feet_y - lift
            top = hip_y
            bot = fy - bh + 1
            knee_out = 1 if p.crouch > 0.5 else 0
            for y in range(top, bot):
                for x in range(3):
                    xx = hx - 1 + x + s_i * (knee_out if y < (top + bot) // 2 + 1 else 0)
                    col = trouser[1]
                    if (s_i < 0 and x == 0) or (s_i > 0 and x == 2):
                        col = trouser[0]
                    if y == top:
                        col = trouser[0]
                    c.set(xx, y, col)
            bx = hx - 1 - (1 if s_i < 0 else 0)
            if S.get("barefoot"):
                c.rect(bx, fy - 1, 4, 2, shade(S["skin"], -0.2))
            else:
                c.rect(bx, fy - bh + 1, 4, bh, boot[1])
                c.hline(bx, bx + 3, fy, boot[0])
                c.set(bx + (0 if s_i < 0 else 3), fy - bh + 1, boot[2])

    # --- upper body (own layer so it can lean) --------------------------------------------
    hold_after = []
    if "behind" in S:
        S["behind"](U, UG, p, ctx)
    hand_tips = [None, None]
    if view == "side":
        hand_tips[1] = draw_arm(U, 1, dark=True)
    behind_hands = []
    if view == "up":
        for i in (0, 1):
            if p.hands[i] is not None and p.hands[i][0] > 2.5:
                behind_hands.append(i)
                hand_tips[i] = draw_arm(U, i, dark=True)
        for item in (p.hold, p.hold2):
            if item and item[1] in behind_hands:
                hx, hy = ends[item[1]]
                draw_item(U, UG, item[0], hx, hy, view, item[2], -1 if item[1] == 0 else 1, p.k)
    torso(U, UG, p, S, ctx)
    S["costume"](U, UG, p, ctx)
    hy = torso_top - S["head_h"] - 1 + p.head_dy
    ctx["hy"] = hy
    if view == "side":
        S["head_side"](U, UG, p, ctx)
    elif view == "down":
        S["head_front"](U, UG, p, ctx)
    # arms
    if view == "side":
        hand_tips[0] = draw_arm(U, 0)
    elif view == "down":
        hand_tips[0] = draw_arm(U, 0)
        hand_tips[1] = draw_arm(U, 1)
    else:
        for i in (0, 1):
            if i not in behind_hands:
                hand_tips[i] = draw_arm(U, i)
    if view == "up":
        S["head_back"](U, UG, p, ctx)
    spout = None
    for item in (p.hold, p.hold2):
        if not item:
            continue
        if view == "up" and item[1] in behind_hands:
            continue
        hx, hy2 = ends[item[1]]
        r = draw_item(U, UG, item[0], hx + 0.5, hy2 + 1, view, item[2], -1 if item[1] == 0 else 1, p.k)
        if r:
            spout = r
    # marks that hang off things
    for m in p.marks:
        if m[0] == "pour" and spout and view != "up":
            for i in range(3):
                U.set(spout[0] + (i % 2), spout[1] + 2 + i * 2 + (m[1] % 2), C("#7fc3d9"))
        elif m[0] == "steam" and (p.hold and p.hold[0] in ("cup", "bowl", "ladle")):
            hx, hy2 = ends[p.hold[1]]
            for i in range(3):
                U.set(int(hx) + ((i + m[1]) % 2), int(hy2) - 2 - i * 2 - m[1] % 2, (230, 230, 240, 160 - i * 45))
        elif m[0] == "spark" and p.hold:
            hx, hy2 = ends[p.hold[1]]
            dx, dy, ln = rig._dir_for(view, p.hold[2], 1)
            tip = (int(hx + dx * 6 * ln), int(hy2 + dy * 6 * ln))
            for (ox, oy) in [(0, -2), (2, -1), (-2, -1), (1, 1), (-1, 1)]:
                U.set(tip[0] + ox, tip[1] + oy, pal("amber_light")); UG.set(tip[0] + ox, tip[1] + oy, pal("amber_light"))
    lean = p.lean if view == "side" else p.lean
    c.paste(U, lean, 0)
    g.paste(UG, lean, 0)
    for m in p.marks:
        if m[0] == "dust":
            for (ox, oy) in [(-4, 0), (-6, -1), (4, 0)] if view == "side" else [(-5, 0), (5, 0), (-6, -1), (6, -1)]:
                c.set(cx + ox, feet_y + oy, (176, 164, 140, 200))
    other = [m for m in p.marks if m[0] in ("sweat", "puff", "zzz", "note")]
    if other:
        q = rig.Pose(view, p.anim, p.k, p.n)
        q.marks = other
        draw_marks(c, g, q, cx - 4 + (2 if view == "side" else 0) + lean, hy)


def torso(c, g, p, S, ctx):
    """Body block from the shoulders to the hem; costume details go on top."""
    if "torso" in S:
        S["torso"](c, g, p, ctx)
        return
    cx, tt, ht = ctx["cx"], ctx["torso_top"], ctx["hip_y"]
    cloth = ramp(S["cloth"], 4, 0.35)
    w = S["torso_w"]
    hem = ht + 1
    if S.get("skirt"):
        hem = min(ht + S.get("skirt_len", 4), ctx["by"] - 1)
    for y in range(tt, hem):
        k = (y - tt) / max(1, ht - tt)
        if p.view in ("down", "up"):
            ww = int(w / 2 + S.get("flare", 0) * k)
            for x in range(cx - ww, cx + ww):
                col = cloth[1]
                if x == cx - ww:
                    col = cloth[2]
                elif x >= cx + ww - 1:
                    col = cloth[0]
                c.set(x, y, col)
        else:
            back = int(w / 2 - 1 + S.get("flare", 0) * k * 0.6)
            sway = _sway(p) if y > ht else 0
            for x in range(cx - back + sway, cx + int(w / 2) - 1 + (1 if y > ht else 0)):
                col = cloth[1] if x < cx + w // 2 - 2 else cloth[0]
                if x == cx - back + sway:
                    col = cloth[2]
                c.set(x, y, col)


def _sway(p):
    """Skirts and coats trail behind a walking body."""
    if p.anim in ("walk", "run", "tired", "cautious", "carry", "carrycoil"):
        return -1 if p.feet[0][0] > 0 else 0
    return 0


# ---------------------------------------------------------------------------------------------
# The player: a surface salvager
# ---------------------------------------------------------------------------------------------
PLAYER = {
    "skin": C("#b97f56"), "hair": C("#3a2a24"), "cap": C("#5c4636"), "brass": pal("brass"),
    "cape": C("#3b5559"), "vest": C("#7a6448"), "shirt": C("#c9b994"), "trouser": C("#3a3946"),
    "boot": C("#4a3529"), "rope": C("#b89a62"), "glove": C("#6b5040"), "eye": pal("charcoal"),
}


def _player_torso(c, g, p, ctx):
    P = PLAYER
    cx, tt, ht = ctx["cx"], ctx["torso_top"], ctx["hip_y"]
    vest = ramp(P["vest"], 3, 0.3)
    cape = ramp(P["cape"], 3, 0.35)
    rope = ramp(P["rope"], 3, 0.3)
    if p.view == "down":
        c.rect(cx - 7, tt, 14, 8, cape[0])
        c.rect(cx - 4, tt, 8, ht - tt + 1, vest[1])
        c.rect(cx - 1, tt + 1, 2, 4, P["shirt"])
        c.vline(cx - 4, tt, ht, vest[2])
        c.vline(cx + 3, tt, ht, vest[0])
        c.hline(cx - 4, cx + 3, ht - 1, C("#2c221c"))
        c.set(cx, ht - 1, P["brass"])
        c.rect(cx + 2, ht - 2, 2, 2, shade(P["vest"], -0.4))
        for y in range(4):
            w = 7 + (1 if y > 0 else 0) - (0 if y < 3 else 1)
            c.hline(cx - w, cx + w - 1, tt + y, cape[1] if y < 3 else cape[0])
        c.hline(cx - 6, cx - 1, tt, cape[2])
        c.ellipse(cx - 6, tt + 2, 2.6, 2.2, rope[1])
        c.ellipse(cx - 6, tt + 2, 1.2, 1.0, rope[0])
        c.set(cx - 7, tt + 1, rope[2])
    elif p.view == "up":
        c.rect(cx - 4, tt, 8, ht - tt + 1, vest[0])
        for y in range(9):
            w = 6 + (1 if y < 6 else 0)
            c.hline(cx - w, cx + w - 1, tt + y, cape[1] if 1 < y < 7 else cape[0])
        c.vline(cx - 1, tt + 2, tt + 7, cape[0])
        c.hline(cx - 6, cx + 5, tt, cape[2])
        c.ellipse(cx + 5, tt + 2, 2.6, 2.2, rope[1])
        c.ellipse(cx + 5, tt + 2, 1.2, 1.0, rope[0])
    else:
        c.rect(cx - 3, tt, 7, ht - tt + 1, vest[1])
        c.vline(cx + 3, tt + 1, ht, vest[0])
        c.hline(cx - 3, cx + 3, ht - 1, C("#2c221c"))
        sway = _sway(p) + (1 if p.anim == "run" else 0) * -1
        for y in range(9):
            w = 3 + y // 3
            c.hline(cx - 3 - w + (sway if y > 5 else 0), cx - 1, tt + y, cape[1] if y < 6 else cape[0])
        c.hline(cx - 4, cx + 2, tt, cape[2])
        c.hline(cx - 4, cx + 2, tt + 1, cape[1])
        c.ellipse(cx - 3, tt + 3, 2.4, 2.4, rope[1])
        c.ellipse(cx - 3, tt + 3, 1.1, 1.1, rope[0])


def _player_head_front(c, g, p, ctx):
    P = PLAYER
    cx, hy = ctx["cx"] + p.head_dx, ctx["hy"] - 3
    head_shape(c, cx, hy + 3, 9, 7, P["skin"])
    hair = ramp(P["hair"], 2, 0.3)
    c.rect(cx - 5, hy + 4, 1, 4, hair[0])
    c.rect(cx + 4, hy + 4, 1, 4, hair[0])
    cap = ramp(P["cap"], 3, 0.32)
    for y in range(4):
        w = [3, 4, 5, 5][y]
        c.hline(cx - w, cx + w - 1, hy + y, cap[1])
    c.hline(cx - 5, cx + 4, hy + 3, cap[0])
    c.hline(cx - 2, cx + 1, hy, cap[2])
    c.rect(cx - 1, hy + 1, 2, 2, P["brass"])
    if p.lamp:
        c.set(cx - 1, hy + 1, pal("amber_light")); c.set(cx, hy + 1, pal("cream"))
        g.set(cx - 1, hy + 1, pal("amber")); g.set(cx, hy + 1, pal("amber_light"))
    else:
        c.set(cx - 1, hy + 1, shade(P["brass"], -0.3)); c.set(cx, hy + 1, shade(P["brass"], -0.2))
    face_front(c, cx, hy + 5, P["skin"], P["eye"], p, eye_gap=3, mouth_y=4)


def _player_head_back(c, g, p, ctx):
    P = PLAYER
    cx, hy = ctx["cx"], ctx["hy"] - 3
    head_shape(c, cx, hy + 3, 9, 7, P["hair"])
    c.rect(cx - 3, hy + 8, 6, 2, shade(P["skin"], -0.25))
    cap = ramp(P["cap"], 3, 0.32)
    for y in range(5):
        w = [3, 4, 5, 5, 5][y]
        c.hline(cx - w, cx + w - 1, hy + y, cap[1] if y < 4 else cap[0])
    c.hline(cx - 2, cx + 1, hy, cap[2])
    c.hline(cx - 5, cx + 4, hy + 2, C("#2a201a"))


def _player_head_side(c, g, p, ctx):
    P = PLAYER
    cx, hy = ctx["cx"], ctx["hy"] - 3
    head_shape(c, cx + 1, hy + 3, 8, 7, P["skin"])
    hair = ramp(P["hair"], 2, 0.3)
    c.rect(cx - 3, hy + 4, 3, 4, hair[0])
    cap = ramp(P["cap"], 3, 0.32)
    for y in range(4):
        c.hline(cx - 3, cx + 3 + (1 if y == 3 else 0), hy + y, cap[1])
    c.hline(cx - 3, cx + 5, hy + 3, cap[0])
    c.hline(cx - 1, cx + 2, hy, cap[2])
    c.rect(cx + 3, hy + 1, 2, 2, P["brass"])
    if p.lamp:
        c.set(cx + 4, hy + 1, pal("amber_light")); g.set(cx + 4, hy + 1, pal("amber_light"))
    face_side(c, cx + 3, hy + 5, P["skin"], P["eye"], p)


def player_spec():
    P = PLAYER
    return {"cx": 12, "feet": 31, "leg_len": 9, "torso_h": 9, "torso_w": 8, "shoulder_w": 10, "arm": 7,
            "head_h": 6, "skin": P["skin"], "eye": P["eye"], "cloth": P["vest"], "sleeve": P["cape"],
            "hand": P["glove"], "trouser": P["trouser"], "boot": P["boot"], "torso": _player_torso,
            "costume": lambda c, g, p, ctx: None, "head_front": _player_head_front,
            "head_back": _player_head_back, "head_side": _player_head_side}


def draw_player(c, g, p):
    render_humanoid(c, g, p, player_spec())


# ---------------------------------------------------------------------------------------------
# Barnaby Coil: tall, stooped, cracked brass breathing helmet, long dark oilskin coat
# ---------------------------------------------------------------------------------------------
BARNABY = {
    "coat": C("#2e2a3a"), "coat_light": C("#45405a"), "brass": C("#a8843f"), "verd": pal("verdigris"),
    "glass": C("#1d2a30"), "glint": pal("cream"), "glove": C("#c9b994"), "trouser": C("#262430"),
    "boot": C("#2b221d"), "moss": pal("glow"), "toolroll": C("#6b5040"),
}


def helmet(c, g, cx, top, p, view):
    B = BARNABY
    br = ramp(B["brass"], 4, 0.38)
    r = 6
    hcx, hcy = cx + (1 if view == "side" else 0) - 0.5, top + 6
    for y in range(top, top + 12):
        for x in range(cx - 7, cx + 8):
            d = math.hypot(x + 0.5 - hcx - 0.5, (y + 0.5 - hcy) * 1.05)
            if d <= r + 0.3:
                col = br[2] if (x - hcx) + (y - hcy) < -3 else (br[0] if (x - hcx) + (y - hcy) > 4 else br[1])
                c.set(x, y, col)
    for (x, y) in [(cx - 5, top + 3), (cx - 6, top + 5), (cx + 4, top + 9), (cx + 5, top + 8)]:
        c.set(x, y, B["verd"])
    for k in range(10):
        a = k / 10 * math.tau
        x = int(round(hcx + 0.5 + math.cos(a) * (r - 0.6)))
        y = int(round(hcy + math.sin(a) * (r - 0.6)))
        if c.get(x, y)[3] > 0:
            c.set(x, y, br[3])
    if view == "up":
        c.hline(cx - 3, cx + 2, top + 10, br[0])
        c.line(cx - 4, top + 11, cx - 6, top + 14, shade(B["coat"], 0.1))
        return
    fx = cx + (2 if view == "side" else 0) + (p.look if view == "down" else 0) * 0
    for y in range(top + 3, top + 10):
        for x in range(fx - 4, fx + 4):
            if math.hypot(x + 0.5 - fx, (y + 0.5 - (top + 6.5)) * 1.1) <= 3.6:
                c.set(x, y, B["glass"])
    crack = [(fx - 3, top + 4), (fx - 2, top + 5), (fx - 1, top + 5), (fx, top + 6), (fx + 1, top + 7), (fx + 1, top + 8)]
    for i, (x, y) in enumerate(crack):
        c.set(x, y, shade(B["glass"], 0.45) if i % 2 else B["moss"])
        if i % 2 == 0:
            g.set(x, y, shade(B["moss"], -0.25))
    e = p.emote
    ey = top + 6
    lk = p.look if view == "down" else 0
    eyes = [(fx + 1, ey)] if view == "side" else [(fx - 2 + lk, ey), (fx + 1 + lk, ey)]
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
        elif p.eyes == "closed":
            pass
        elif p.eyes == "half":
            c.set(x, y + 1, B["glint"]); g.set(x, y + 1, shade(B["glint"], -0.2))
        elif p.eyes == "up":
            c.set(x, y - 1, B["glint"]); g.set(x, y - 1, B["glint"])
        else:
            c.rect(x, y, 1, 2, B["glint"]); g.rect(x, y, 1, 2, shade(B["glint"], -0.1))
    for k in range(16):
        a = k / 16 * math.tau
        x = int(round(fx + math.cos(a) * 3.8 - 0.5))
        y = int(round(top + 6.5 + math.sin(a) * 3.5 - 0.5))
        c.set(x, y, br[3] if k < 8 else br[1])
    c.rect(fx - 1, top + 10, 2, 2, br[0])
    c.set(fx - 1, top + 10, br[2])
    if p.mouth:
        c.set(fx, top + 11, shade(br[0], -0.4))   # the valve puffs when he talks


def _barnaby_torso(c, g, p, ctx):
    B = BARNABY
    cx, tt, ht = ctx["cx"], ctx["torso_top"], ctx["hip_y"]
    coat = ramp(B["coat"], 4, 0.35)
    hem = min(ht + 5, ctx["by"] - 2)
    if p.view in ("down", "up"):
        for y in range(tt, hem):
            k = (y - tt) / max(1, hem - tt)
            w = int(6 + k * 2.5)
            for x in range(cx - w, cx + w):
                col = coat[1]
                if x <= cx - w + 1:
                    col = coat[2]
                elif x >= cx + w - 2:
                    col = coat[0]
                if p.view == "down" and abs(x - cx + 0.5) < 1 and y > tt + 3:
                    col = coat[0]
                c.set(x, y, col)
        sway = _sway(p)
        if sway or p.feet[0][1]:
            c.hline(cx - 8, cx - 5, hem - 1, (0, 0, 0, 0))
        if p.feet[1][1]:
            c.hline(cx + 5, cx + 8, hem - 1, (0, 0, 0, 0))
        c.hline(cx - 6, cx + 5, tt, coat[3] if p.view == "down" else coat[2])
        c.hline(cx - 7, cx + 6, tt + 1, coat[2])
        if p.view == "down":
            c.rect(cx + 3, ht - 3, 3, 4, B["toolroll"])
            c.set(cx + 4, ht - 2, B["brass"])
            c.set(cx - 2, tt + 6, B["brass"])
            c.set(cx - 2, tt + 9, B["brass"])
    else:
        sway = _sway(p)
        for y in range(tt, hem):
            k = (y - tt) / max(1, hem - tt)
            back = int(4 + k * 3) + (sway if y > ht else 0)
            for x in range(cx - back, cx + 4):
                col = coat[1] if x < cx + 2 else coat[0]
                if x <= cx - back + 1:
                    col = coat[2]
                c.set(x, y, col)
        c.hline(cx - 4, cx + 4, tt, coat[2])
        c.rect(cx - 2, ht - 3, 3, 4, B["toolroll"])


def barnaby_spec():
    B = BARNABY

    def hf(c, g, p, ctx):
        helmet(c, g, ctx["cx"] + p.head_dx, ctx["hy"] - 5, p, "down")

    def hb(c, g, p, ctx):
        helmet(c, g, ctx["cx"], ctx["hy"] - 5, p, "up")

    def hs(c, g, p, ctx):
        helmet(c, g, ctx["cx"] + 2, ctx["hy"] - 4, p, "side")

    return {"cx": 13, "feet": 35, "leg_len": 8, "torso_h": 13, "torso_w": 12, "shoulder_w": 13, "arm": 9,
            "head_h": 6, "skin": B["glove"], "eye": B["glint"], "cloth": B["coat"], "sleeve": B["coat"],
            "hand": B["glove"], "trouser": B["trouser"], "boot": B["boot"], "torso": _barnaby_torso,
            "costume": lambda c, g, p, ctx: None, "head_front": hf, "head_back": hb, "head_side": hs}


def draw_barnaby(c, g, p):
    render_humanoid(c, g, p, barnaby_spec())


# --- Odile ------------------------------------------------------------------------------------------
ODILE = {"skin": C("#7a4a32"), "hair": C("#b9b2aa"), "eye": pal("charcoal"), "cloth": C("#8a5a2a"),
         "dress": C("#2c3a4a"), "boot": C("#2a1f1a"), "hand": C("#7a4a32"), "ledger": C("#5a3a2a")}


def odile_spec():
    O = ODILE

    def costume(c, g, p, ctx):
        cx, tt, lt = ctx["cx"], ctx["torso_top"], ctx["leg_top"]
        holding = p.hold and p.hold[0] in ("ledger", "pouch")
        if p.view == "down":
            c.rect(cx - 1, tt + 1, 2, lt - tt + 3, O["dress"])
            for y in range(tt + 2, lt, 2):
                c.set(cx - 2, y, pal("brass_light"))
            c.hline(cx - 4, cx + 3, tt, shade(O["cloth"], 0.2))
            if not holding and not p.hands[1]:
                c.rect(cx + 3, tt + 3, 3, 5, O["ledger"])
                c.vline(cx + 5, tt + 3, tt + 7, pal("cream"))
        elif p.view == "up":
            c.rect(cx - 3, lt - 1, 6, 3, O["dress"])
        else:
            if not holding and not p.hands[0]:
                c.rect(cx - 1, tt + 3, 3, 5, O["ledger"])
                c.vline(cx + 1, tt + 3, tt + 7, pal("cream"))

    def hair_front(c, g, p, ctx):
        cx, hy = ctx["cx"] + p.head_dx, ctx["hy"]
        head_shape(c, cx, hy + 1, 9, 7, O["skin"])
        face_front(c, cx, hy + 4, O["skin"], O["eye"], p, eye_gap=3, mouth_y=3)
        hair = ramp(O["hair"], 3, 0.3)
        c.hline(cx - 4, cx + 3, hy, hair[1])
        c.hline(cx - 3, cx + 2, hy - 1, hair[2])
        c.rect(cx - 5, hy + 1, 1, 3, hair[0])
        c.rect(cx + 4, hy + 1, 1, 3, hair[0])
        c.disc(cx - 0.5, hy - 2.5, 2.2, hair[1])
        c.hline(cx - 2, cx + 1, hy - 3, hair[2])
        c.set(cx - 2, hy, pal("brass_light")); c.set(cx + 1, hy, pal("brass_light"))
        c.hline(cx - 1, cx, hy, pal("brass"))

    def hair_back(c, g, p, ctx):
        cx, hy = ctx["cx"], ctx["hy"]
        head_shape(c, cx, hy + 1, 9, 7, O["hair"])
        c.disc(cx - 0.5, hy - 2.5, 2.2, shade(O["hair"], -0.1))
        c.line(cx - 2, hy + 2, cx - 3, hy + 6, shade(O["hair"], -0.3))
        c.line(cx + 1, hy + 2, cx + 2, hy + 6, shade(O["hair"], -0.3))

    def hair_side(c, g, p, ctx):
        cx, hy = ctx["cx"], ctx["hy"]
        head_shape(c, cx + 1, hy + 1, 8, 7, O["skin"])
        face_side(c, cx + 3, hy + 4, O["skin"], O["eye"], p)
        hair = ramp(O["hair"], 3, 0.3)
        c.rect(cx - 3, hy, 5, 3, hair[1])
        c.disc(cx - 2.5, hy - 2.0, 2.2, hair[1])
        c.set(cx + 2, hy, pal("brass_light"))

    return {"cx": 12, "feet": 31, "leg_len": 6, "torso_h": 11, "torso_w": 10, "flare": 2, "arm": 7,
            "head_h": 7, "skin": O["skin"], "eye": O["eye"], "cloth": O["cloth"],
            "sleeve": shade(O["dress"], 0.1), "hand": O["hand"], "trouser": O["dress"], "boot": O["boot"],
            "boot_h": 2, "skirt": True, "skirt_len": 3, "costume": costume, "head_front": hair_front,
            "head_back": hair_back, "head_side": hair_side}


def draw_odile(c, g, p):
    render_humanoid(c, g, p, odile_spec())


# --- Hesper ------------------------------------------------------------------------------------------
HESPER = {"skin": C("#d1b48c"), "hair": C("#6a3428"), "eye": pal("charcoal"), "shawl": C("#4f6a3a"),
          "patch": C("#5a3f8f"), "linen": C("#b8a888"), "hand": C("#7f9a5a")}


def hesper_spec():
    H = HESPER

    def costume(c, g, p, ctx):
        cx, tt, lt = ctx["cx"], ctx["torso_top"], ctx["leg_top"]
        shawl = ramp(H["shawl"], 3, 0.35)
        if p.view in ("down", "up"):
            for y in range(tt, tt + 7):
                w = 6 + (y - tt) // 2
                c.hline(cx - w, cx + w - 1, y, shawl[1] if (y + (0 if p.view == "down" else 1)) % 3 else shawl[0])
            for (dx, dy) in [(-4, 2), (3, 4), (-2, 5)]:
                c.rect(cx + dx, tt + dy, 2, 2, H["patch"])
            if p.view == "down":
                for (dx, dy, col) in [(-5, 4, pal("glow")), (4, 2, pal("moss_light")), (2, 5, pal("amber_light"))]:
                    c.rect(cx + dx, tt + dy, 1, 2, col)
                    g.rect(cx + dx, tt + dy, 1, 2, shade(col, -0.35))
        else:
            for y in range(tt, tt + 7):
                c.hline(cx - 4 - (y - tt) // 3, cx + 2, y, shawl[1])
            c.rect(cx - 3, tt + 3, 2, 2, H["patch"])
            c.rect(cx + 1, tt + 4, 1, 2, pal("glow")); g.rect(cx + 1, tt + 4, 1, 2, shade(pal("glow"), -0.35))

    def hair_front(c, g, p, ctx):
        cx, hy = ctx["cx"] + p.head_dx, ctx["hy"]
        head_shape(c, cx, hy + 1, 8, 7, H["skin"])
        face_front(c, cx, hy + 4, H["skin"], H["eye"], p, eye_gap=3, mouth_y=3)
        hair = ramp(H["hair"], 3, 0.32)
        for y in range(hy - 2, hy + 3):
            w = 5 + (1 if y > hy else 0)
            for x in range(cx - w, cx + w):
                if y >= hy + 1 and cx - 3 <= x <= cx + 2:
                    continue          # the face shows through the fringe
                c.set(x, y, hair[1] if (y % 2) else hair[2])
        for (x, y) in [(cx - 6, hy + 3), (cx + 5, hy + 4), (cx - 6, hy + 5), (cx + 5, hy + 1), (cx - 7, hy + 1)]:
            c.set(x, y, hair[0])
        c.set(cx - 3, hy - 2, pal("moss_light")); c.set(cx + 3, hy - 1, pal("moss_light"))
        c.set(cx + 1, hy - 2, pal("glow")); g.set(cx + 1, hy - 2, shade(pal("glow"), -0.3))

    def hair_back(c, g, p, ctx):
        cx, hy = ctx["cx"], ctx["hy"]
        hair = ramp(H["hair"], 3, 0.32)
        for y in range(hy - 2, hy + 8):
            w = 5 + (1 if hy < y < hy + 6 else 0)
            c.hline(cx - w, cx + w - 1, y, hair[1] if (y % 2) else hair[0])
        c.set(cx - 2, hy, pal("moss_light"))

    def hair_side(c, g, p, ctx):
        cx, hy = ctx["cx"], ctx["hy"]
        head_shape(c, cx + 1, hy + 1, 7, 7, H["skin"])
        face_side(c, cx + 3, hy + 4, H["skin"], H["eye"], p)
        hair = ramp(H["hair"], 3, 0.32)
        for y in range(hy - 2, hy + 6):
            c.hline(cx - 4, cx + (2 if y < hy + 1 else -1), y, hair[1] if y % 2 else hair[2])
        c.set(cx - 5, hy + 4, hair[0])

    return {"cx": 12, "feet": 33, "leg_len": 9, "torso_h": 11, "torso_w": 8, "flare": 3, "arm": 8,
            "head_h": 7, "skin": H["skin"], "eye": H["eye"], "cloth": H["linen"],
            "sleeve": shade(H["linen"], -0.1), "hand": H["hand"], "trouser": H["linen"], "boot": H["skin"],
            "skirt": True, "skirt_len": 7, "barefoot": True, "boot_h": 2, "costume": costume,
            "head_front": hair_front, "head_back": hair_back, "head_side": hair_side}


def draw_hesper(c, g, p):
    render_humanoid(c, g, p, hesper_spec())


# --- Mags -----------------------------------------------------------------------------------------------
MAGS = {"skin": C("#e0ae8a"), "hair": C("#b4562e"), "eye": pal("charcoal"), "dress": C("#7a3a2e"),
        "apron": C("#e6dcc0"), "boot": C("#3a2a22")}


def mags_spec():
    M = MAGS

    def costume(c, g, p, ctx):
        cx, tt, lt = ctx["cx"], ctx["torso_top"], ctx["leg_top"]
        apron = ramp(M["apron"], 3, 0.25)
        holding = p.hold is not None
        if p.view == "down":
            for y in range(tt + 2, min(lt + 3, ctx["by"] - 1)):
                w = 4 + (1 if y > tt + 5 else 0)
                c.hline(cx - w, cx + w - 1, y, apron[1] if y % 4 else apron[0])
            c.hline(cx - 6, cx + 5, tt + 6, shade(M["dress"], -0.2))
            c.rect(cx - 1, tt + 8, 3, 2, shade(pal("danger"), -0.3))
            if not holding and not p.hands[1]:
                c.vline(cx + 8, tt + 1, tt + 10, pal("ash"))
                c.rect(cx + 7, tt + 10, 3, 2, shade(pal("ash"), -0.1))
        elif p.view == "up":
            c.hline(cx - 6, cx + 5, tt + 6, shade(M["apron"], -0.15))
            c.vline(cx, tt + 6, tt + 8, shade(M["apron"], -0.15))
        else:
            for y in range(tt + 2, min(lt + 3, ctx["by"] - 1)):
                c.hline(cx + 1, cx + 4, y, apron[1])
            if not holding and not p.hands[0]:
                c.vline(cx + 5, tt + 2, tt + 9, pal("ash"))

    def hair_front(c, g, p, ctx):
        cx, hy = ctx["cx"] + p.head_dx, ctx["hy"]
        head_shape(c, cx, hy + 1, 10, 7, M["skin"])
        face_front(c, cx, hy + 4, M["skin"], M["eye"], p, eye_gap=3, mouth_y=3, blush=shade(C("#e07a6a"), 0.1))
        hair = ramp(M["hair"], 3, 0.3)
        c.hline(cx - 5, cx + 4, hy, hair[1])
        c.hline(cx - 4, cx + 3, hy - 1, hair[2])
        c.rect(cx - 6, hy + 1, 1, 2, hair[0]); c.rect(cx + 5, hy + 1, 1, 2, hair[0])
        c.disc(cx - 0.5, hy - 2.8, 2.4, hair[1])
        c.set(cx + 1, hy - 4, pal("cream"))

    def hair_back(c, g, p, ctx):
        cx, hy = ctx["cx"], ctx["hy"]
        head_shape(c, cx, hy + 1, 10, 7, M["hair"])
        c.disc(cx - 0.5, hy - 2.8, 2.4, shade(M["hair"], 0.05))

    def hair_side(c, g, p, ctx):
        cx, hy = ctx["cx"], ctx["hy"]
        head_shape(c, cx + 1, hy + 1, 9, 7, M["skin"])
        face_side(c, cx + 4, hy + 4, M["skin"], M["eye"], p)
        hair = ramp(M["hair"], 3, 0.3)
        c.rect(cx - 4, hy, 6, 3, hair[1])
        c.disc(cx - 3.5, hy - 1.5, 2.4, hair[1])

    return {"cx": 13, "feet": 31, "leg_len": 6, "torso_h": 12, "torso_w": 14, "flare": 2, "arm": 7,
            "head_h": 7, "skin": M["skin"], "eye": M["eye"], "cloth": M["dress"], "sleeve": M["skin"],
            "hand": M["skin"], "trouser": M["dress"], "boot": M["boot"], "boot_h": 2, "skirt": True,
            "skirt_len": 4, "costume": costume, "head_front": hair_front, "head_back": hair_back,
            "head_side": hair_side}


def draw_mags(c, g, p):
    render_humanoid(c, g, p, mags_spec())


# --- Grist (a Knapper) ----------------------------------------------------------------------------------
GRIST_HAND_ANIMS = {"chew", "coins", "talk", "happy", "surprised", "listen"}
GRIST = {"stone": C("#6c6a74"), "dark": C("#3e3c46"), "crystal": pal("amber"), "eye": pal("amber_light"), "strap": C("#5a3f2e")}


def draw_grist(c, g, p):
    """A Knapper walks on its knuckles; the skeleton's feet drive the knuckles and the legs."""
    G = GRIST
    st = ramp(G["stone"], 5, 0.4)
    cx = 22
    base = 44 - p.lift_body
    body_bob = p.bob + int(round(p.crouch * 4))
    lean = (1 if p.view == "side" else 0) + (p.lean if p.view == "side" else 0)
    for y in range(14 + body_bob, base - 5):
        k = (y - 14 - body_bob) / max(1, (base - 19 - body_bob))
        w = int(9 + 6 * math.sin(min(1.0, k * 1.6) * math.pi * 0.5) + (p.breath if k < 0.6 else 0))
        for x in range(cx - w + lean * 2, cx + w + lean * 2):
            t = (x - (cx - w)) / (2 * w)
            col = st[3] if t < 0.25 else (st[2] if t < 0.6 else st[1])
            if y > base - 10:
                col = st[1] if t < 0.7 else st[0]
            c.set(x, y, col)
    for k in range(5):
        x = cx - 6 + k * 3 + lean * 2
        top = 9 + (k % 2) * 2 + body_bob - (1 if p.breath else 0)
        for y in range(top, 16 + body_bob):
            c.set(x, y, G["crystal"] if y < top + 2 else shade(G["crystal"], -0.3))
        g.set(x, top, shade(G["crystal"], -0.1))
    # knuckle-walking arms: hands follow the skeleton's hand targets when raised, feet otherwise
    for idx, sgn in ((1, -1), (0, 1)):
        if p.view == "side" and sgn < 0:
            continue
        h = p.hands[idx if p.view != "side" else 0] if p.anim in GRIST_HAND_ANIMS else None
        off = p.feet[idx][0] if p.view == "side" else 0
        lift = p.feet[idx][1]
        ax = cx + sgn * 12 + lean * 4 + (off if p.view == "side" else 0)
        if h is None:
            for y in range(22 + body_bob, base - lift):
                c.rect(ax - 2, y, 4, 1, st[2] if sgn < 0 else st[1])
            c.rect(ax - 3, base - 3 - lift, 6, 3, st[0])
        else:
            fwd, up = h
            tx = ax + (fwd if p.view == "side" else -sgn * fwd * 0.6)
            ty = base - 3 - (up + 10)
            thick(c, ax, 22 + body_bob, tx, ty, 4, st[2] if sgn < 0 else st[1])
            c.rect(int(tx) - 3, int(ty), 6, 3, st[0])
            if p.hold and p.hold[1] == (idx if p.view != "side" else 0):
                draw_item(c, g, p.hold[0], tx, ty, p.view, p.hold[2])
    for sgn in (-1, 1):
        lx = cx + sgn * 5
        lift = p.feet[0 if sgn > 0 else 1][1]
        c.rect(lx - 2, base - 6, 4, 6 - lift, st[1])
    hx = cx + (8 if p.view == "side" else 0) + (p.head_dx if p.view == "down" else 0)
    hy = 18 + body_bob + p.head_dy
    if p.view != "up":
        c.ellipse(hx, hy, 5, 4, st[2])
        eyes = [(hx - 2, hy), (hx + 1, hy)] if p.view == "down" else [(hx + 2, hy - 1)]
        for (x, y) in eyes:
            col = G["eye"]
            if p.emote == "surprised" or p.eyes == "wide":
                c.rect(x, y - 1, 1, 2, col); g.rect(x, y - 1, 1, 2, col)
            elif p.emote == "sad" or p.eyes == "half":
                c.set(x, y + 1, shade(col, -0.3)); g.set(x, y + 1, shade(col, -0.5))
            elif p.emote == "happy":
                c.hline(x - 1, x, y, col); g.hline(x - 1, x, y, col)
            elif p.eyes == "closed":
                c.set(x, y + 1, st[0])
            else:
                c.set(x, y, col); g.set(x, y, col)
        mw = 1 + (1 if p.mouth else 0)
        c.hline(hx - 2, hx + 1, hy + 2, st[0])
        if p.mouth:
            c.rect(hx - 1, hy + 2, 2, mw, shade(st[0], -0.4))
    c.line(cx - 8, 16 + body_bob, cx + 6, 30 + body_bob, G["strap"])
    c.rect(cx + 4, 28 + body_bob, 4, 4, shade(G["strap"], 0.15))


# ---------------------------------------------------------------------------------------------
PLAYER_ANIMS = ["idle", "walk", "run", "tired", "cautious", "carry", "carrycoil", "look", "stretch", "yawn",
                "shiver", "lamp", "rope", "till", "hammer", "water", "wrench", "plant", "harvest", "pickup",
                "crank", "knock", "talk", "happy", "sad", "surprised", "annoyed", "celebrate", "wave", "sit",
                "cough", "getup", "collapse", "listen"]
NPC_BASE = ["idle", "walk", "tired", "look", "talk", "happy", "sad", "surprised", "annoyed", "wave", "sit",
            "stretch", "yawn", "cough"]

SPECS = [
    ("player", draw_player, 24, 32, True, PLAYER_ANIMS, {"stride": 1.0, "arm": 6}),
    ("barnaby", draw_barnaby, 26, 36, True, NPC_BASE + ["wrench", "crank", "tea", "inspect", "knock", "listen", "carry"],
     {"stride": 1.1, "arm": 9}),
    ("odile", draw_odile, 24, 32, False, NPC_BASE + ["ledger", "coins", "observe"], {"stride": 0.8, "arm": 7}),
    ("hesper", draw_hesper, 24, 34, True, NPC_BASE + ["tend", "observe", "plant", "listen"], {"stride": 1.0, "arm": 8}),
    ("mags", draw_mags, 26, 32, False, NPC_BASE + ["cook", "serve", "carry"], {"stride": 0.8, "arm": 7}),
    ("grist", draw_grist, 46, 46, True, ["idle", "walk", "look", "talk", "happy", "sad", "surprised", "annoyed",
                                         "chew", "listen", "coins"], {"stride": 1.0, "arm": 10}),
]


def build(only=None):
    os.makedirs(OUT, exist_ok=True)
    for cid, fn, w, h, emit, anims, opts in SPECS:
        if only and cid not in only:
            continue
        big = rig.build_sheet(fn, w, h, anims, opts,
                              os.path.join(OUT, cid + "_emit.png") if emit else None,
                              os.path.join(OUT, cid + ".png"), os.path.join(OUT, cid + ".json"))
        prev = os.path.join(os.path.dirname(__file__), f"preview_{cid}.png")
        big.img.resize((big.w * 3, big.h * 3), 0).save(prev)
        print(f"{cid}: {big.w}x{big.h}")


if __name__ == "__main__":
    import sys
    build(sys.argv[1:] or None)
