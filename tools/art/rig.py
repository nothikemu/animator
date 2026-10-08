"""Skeleton, poses and the animation library shared by every Bellows character.

A frame is drawn from a Pose: where the hips sit, where each foot is planted, where each hand
is reaching, what that hand holds and at what angle, and what the face is doing. Knees and
elbows are solved with two-bone IK, so one animation definition fits every character's
proportions. Poses are written in *semantic* terms (forward/up relative to the character) and
mapped to each view:

  side  facing right (the game mirrors it for left)
  down  facing the camera
  up    facing away

Animations are tables of poses. Each has a frame count, a rate, whether it loops, and events
on particular frames ("step" for footfalls, "hit" for the moment a tool lands) that the game
uses to time sounds and particles.
"""
import math

from px import Canvas, shade, ramp, mix, pal, hexc

STRIP = 12          # frames per animation strip (columns in one strip)


class Pose:
    def __init__(self, view, anim, k, n):
        self.view = view
        self.anim = anim
        self.k = k
        self.n = n
        self.bob = 0            # upper body down (+) / up (-), px; feet stay planted
        self.lean = 0           # side: upper body forward (+); front views: sideways sway
        self.crouch = 0.0       # 0 standing .. 1 hips nearly on heels
        self.lift_body = 0      # whole figure off the ground (hops), px
        # Feet: (forward offset, lift). Index 0 is the near foot in side view, screen-left
        # foot in front views.
        self.feet = [(0, 0), (0, 0)]
        # Hands: semantic target (forward, up) from the shoulder, or None for hanging at rest.
        self.hands = [None, None]
        self.hold = None        # (item, hand index, semantic angle in degrees: 0 fwd, -90 up, 90 down)
        self.hold2 = None       # a second held item
        self.head_dx = 0
        self.head_dy = 0
        self.look = 0           # eyes left (-1) / right (+1), front view
        self.eyes = "open"      # open | closed | half | wide | up
        self.mouth = 0          # 0 closed, 1 open, 2 wide
        self.emote = ""         # happy | sad | surprised | annoyed
        self.breath = 0         # 0/1
        self.marks = []         # ("sweat",), ("puff", k), ("zzz", k), ("drops", k), ("steam", k), ("spark", k), ("note", k)
        self.lamp = True        # headlamp lit (player)
        self.skirt_sway = 0


# ---------------------------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------------------------
def ik(ax, ay, bx, by, l1, l2, pref):
    """Two-bone IK. Returns (joint, end) with the joint on the side of `pref`."""
    dx, dy = bx - ax, by - ay
    d = math.hypot(dx, dy)
    if d < 1e-6:
        return (ax, ay + l1), (bx, by)
    if d >= (l1 + l2) * 0.9:
        # Near full reach: a straight limb (a knee or elbow kinked by half a pixel reads as
        # a deformity at this size). Long reaches are clamped a little past nominal length.
        k = min(1.0, (l1 + l2) * 1.08 / d)
        ex, ey = ax + dx * k, ay + dy * k
        return (ax + dx * k * l1 / (l1 + l2), ay + dy * k * l1 / (l1 + l2)), (ex, ey)
    a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
    h = math.sqrt(max(0.0, l1 * l1 - a * a))
    mx, my = ax + dx * a / d, ay + dy * a / d
    px, py = -dy / d, dx / d
    if px * pref[0] + py * pref[1] < 0:
        px, py = -px, -py
    return (mx + px * h, my + py * h), (bx, by)


def thick(c, x0, y0, x1, y1, w, col, edge=None, edge_side=0):
    """A limb segment `w` pixels wide. `edge` paints one border in another tone."""
    n = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
    for i in range(n + 1):
        t = i / n
        x = x0 + (x1 - x0) * t
        y = y0 + (y1 - y0) * t
        bx = int(math.floor(x - (w - 1) / 2.0 + 0.5))
        by = int(math.floor(y + 0.5))
        for ox in range(w):
            col_here = col
            if edge is not None and ((edge_side < 0 and ox == 0) or (edge_side > 0 and ox == w - 1)):
                col_here = edge
            c.set(bx + ox, by, col_here)


def rot(dx, dy, deg):
    a = math.radians(deg)
    return dx * math.cos(a) - dy * math.sin(a), dx * math.sin(a) + dy * math.cos(a)


# ---------------------------------------------------------------------------------------------
# Held items: drawn from the hand along a screen direction.
# ---------------------------------------------------------------------------------------------
WOOD = hexc("#7a5a3e")
WOOD_D = hexc("#54402e")
IRON = hexc("#8e8a96")
IRON_D = hexc("#5e5a68")


def _dir_for(view, angle, hand_sign):
    """Screen direction (and visible length factor) of a held item at a semantic angle."""
    fx, fy = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    if view == "side":
        return fx, fy, 1.0
    # Front/back: forward points at (or away from) the camera and foreshortens.
    sx = hand_sign * 0.28 + (0.0 if view == "down" else 0.0)
    sy = fy + fx * (0.42 if view == "down" else -0.42)
    ln = math.hypot(sx, sy)
    if ln < 1e-3:
        return 0.0, 1.0, 0.3
    return sx / ln, sy / ln, max(0.35, min(1.0, ln))


def draw_item(c, g, item, hx, hy, view, angle, hand_sign=1, k=0):
    dx, dy, ln = _dir_for(view, angle, hand_sign)
    px, py = -dy, dx    # perpendicular ("below" the shaft for a right-facing swing)
    if item in ("hoe", "tiller"):
        L = int(round(9 * ln))
        x0, y0 = hx - dx * 3 * ln, hy - dy * 3 * ln
        x1, y1 = hx + dx * L, hy + dy * L
        c.line(int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1)), WOOD)
        for i in range(3):
            c.set(int(round(x1 + px * (i + 1))), int(round(y1 + py * (i + 1))), IRON if i < 2 else IRON_D)
        c.set(int(round(x1 + px)), int(round(y1 + py)) , shade(IRON, 0.3))
    elif item == "hammer":
        L = int(round(6 * ln))
        x1, y1 = hx + dx * L, hy + dy * L
        c.line(int(round(hx - dx)), int(round(hy - dy)), int(round(x1)), int(round(y1)), WOOD)
        for s in (-2, -1, 0, 1, 2):
            c.set(int(round(x1 + px * s)), int(round(y1 + py * s)), IRON_D if s in (-2, 2) else IRON)
            c.set(int(round(x1 + px * s + dx)), int(round(y1 + py * s + dy)), IRON_D)
    elif item == "wrench":
        L = int(round(5 * ln))
        x1, y1 = hx + dx * L, hy + dy * L
        c.line(int(round(hx)), int(round(hy)), int(round(x1)), int(round(y1)), IRON)
        c.set(int(round(x1 + px)), int(round(y1 + py)), IRON_D)
        c.set(int(round(x1 - px)), int(round(y1 - py)), IRON_D)
        c.set(int(round(x1 + dx + px)), int(round(y1 + dy + py)), IRON)
        c.set(int(round(x1 + dx - px)), int(round(y1 + dy - py)), IRON)
    elif item == "can":
        brass = pal("brass")
        body = ramp(brass, 3, 0.3)
        bx, by = int(round(hx - 2)), int(round(hy - 1))
        c.rect(bx, by, 4, 4, body[1])
        c.hline(bx, bx + 3, by, body[2])
        c.vline(bx + 3, by, by + 3, body[0])
        c.set(bx + 1, by - 1, body[0]); c.set(bx + 2, by - 1, body[0])     # handle
        # spout along the pour direction
        sx, sy = hx + dx * 2, hy + dy * 2
        ex, ey = hx + dx * 5, hy + dy * 5 - 1
        c.line(int(round(sx)), int(round(sy)), int(round(ex)), int(round(ey)), body[0])
        return int(round(ex)), int(round(ey))
    elif item == "crate":
        cr = ramp(hexc("#7a5a3e"), 3, 0.3)
        bx, by = int(round(hx - 4)), int(round(hy - 3))
        c.rect(bx, by, 8, 6, cr[1])
        c.hline(bx, bx + 7, by, cr[2])
        c.hline(bx, bx + 7, by + 5, cr[0])
        c.line(bx, by + 1, bx + 7, by + 4, cr[0])
        c.set(bx + 3, by + 2, pal("brass_light"))
    elif item == "coil":
        br = ramp(pal("brass"), 3, 0.35)
        bx, by = int(round(hx - 3)), int(round(hy - 3))
        c.rect(bx, by, 6, 5, br[1])
        for x in range(bx, bx + 6, 2):
            c.vline(x, by, by + 4, br[2])
        c.hline(bx, bx + 5, by + 4, br[0])
        c.set(bx + 2, by + 2, pal("glow")); g.set(bx + 2, by + 2, pal("glow"))
    elif item == "cup":
        c.rect(int(round(hx - 1)), int(round(hy - 2)), 2, 2, pal("cream"))
        c.set(int(round(hx - 1)), int(round(hy - 3)), shade(pal("cream"), -0.2))
    elif item == "bowl":
        b = int(round(hx - 2)), int(round(hy - 2))
        c.rect(b[0], b[1] + 1, 5, 2, hexc("#9c6b46"))
        c.hline(b[0] + 1, b[0] + 3, b[1], hexc("#d9a548"))
    elif item == "ledger":
        c.rect(int(round(hx - 2)), int(round(hy - 3)), 3, 5, hexc("#5a3a2a"))
        c.vline(int(round(hx)), int(round(hy - 3)), int(round(hy + 1)), pal("cream"))
    elif item == "pencil":
        c.line(int(round(hx)), int(round(hy)), int(round(hx + dx * 2)), int(round(hy + dy * 2)), pal("amber"))
    elif item == "ladle":
        L = int(round(7 * ln))
        x1, y1 = hx + dx * L, hy + dy * L
        c.line(int(round(hx - dx)), int(round(hy - dy)), int(round(x1)), int(round(y1)), pal("ash"))
        c.rect(int(round(x1 - 1)), int(round(y1)), 3, 2, shade(pal("ash"), -0.2))
    elif item == "glass":
        cx_, cy_ = int(round(hx)), int(round(hy - 1))
        br = pal("brass_light")
        for (ox, oy) in [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]:
            c.set(cx_ + ox, cy_ + oy, br)
        c.set(cx_, cy_, pal("glow")); g.set(cx_, cy_, pal("glow"))
    elif item == "seed":
        c.set(int(round(hx)), int(round(hy + 1)), hexc("#c9a25a"))
    elif item == "crop":
        bx, by = int(round(hx - 1)), int(round(hy - 4))
        c.rect(bx, by + 2, 3, 3, hexc("#b0406a"))
        c.set(bx + 1, by + 3, hexc("#ff8ab0")); g.set(bx + 1, by + 3, hexc("#c05080"))
        c.set(bx, by + 1, pal("moss_light")); c.set(bx + 2, by, pal("moss_light")); c.set(bx + 1, by + 1, pal("moss"))
    elif item == "pouch":
        c.rect(int(round(hx - 1)), int(round(hy - 1)), 3, 3, hexc("#6b4a34"))
        c.set(int(round(hx)), int(round(hy - 2)), hexc("#c9a25a"))
    elif item == "rock":
        c.rect(int(round(hx - 1)), int(round(hy - 2)), 3, 2, IRON_D)
        c.set(int(round(hx)), int(round(hy - 2)), pal("amber")); g.set(int(round(hx)), int(round(hy - 2)), shade(pal("amber"), -0.3))
    elif item == "crank":
        c.line(int(round(hx)), int(round(hy)), int(round(hx - dx * 3)), int(round(hy - dy * 3)), pal("brass"))
    return None


def draw_marks(c, g, p, top_x, top_y):
    """Little overlay marks: sweat, breath puffs, sleep, steam, water drops, sparks, notes."""
    for m in p.marks:
        kind = m[0]
        k = m[1] if len(m) > 1 else 0
        if kind == "sweat":
            c.set(top_x + 5, top_y + 3, hexc("#9fd8e8")); c.set(top_x + 5, top_y + 4, hexc("#d8f4ff"))
        elif kind == "puff":
            a = 160 - k * 40
            if a > 0:
                for (ox, oy) in [(0, 0), (1, 0), (0, -1), (1 + k, -1 - k)]:
                    c.set(top_x + 6 + k + ox, top_y + 6 - k + oy, (220, 225, 235, a))
        elif kind == "zzz":
            c.set(top_x + 6 + k, top_y - k, pal("cream")); c.set(top_x + 7 + k, top_y - k, pal("cream"))
        elif kind == "steam":
            for i in range(3):
                c.set(m[2] + ((i + k) % 2), m[3] - i * 2 - k % 2, (230, 230, 240, 150 - i * 40))
        elif kind == "drops":
            sx, sy = m[2], m[3]
            for i in range(3):
                c.set(sx + (i % 2), sy + 2 + i * 2 + k % 2, hexc("#7fc3d9"))
        elif kind == "spark":
            sx, sy = m[2], m[3]
            for (ox, oy) in [(0, -2), (2, -1), (-2, -1), (1, 1), (-1, 1)][: 3 + k % 3]:
                c.set(sx + ox, sy + oy, pal("amber_light")); g.set(sx + ox, sy + oy, pal("amber_light"))
        elif kind == "dust":
            sx, sy = m[2], m[3]
            for (ox, oy) in [(-2, 0), (2, 0), (-3, -1), (3, -1)]:
                c.set(sx + ox, sy + oy, (168, 158, 134, 170))
        elif kind == "note":
            c.set(top_x + 7, top_y - 1 - k, pal("glow")); c.set(top_x + 8, top_y - 2 - k, pal("glow"))
            g.set(top_x + 7, top_y - 1 - k, pal("glow"))


# ---------------------------------------------------------------------------------------------
# Animation tables
# ---------------------------------------------------------------------------------------------
WALK_DX = [3, 2, 0, -2, -3, -2, 0, 2]
WALK_LIFT = [0, 0, 0, 0, 0, 1, 2, 1]
WALK_BOB = [0, 1, 0, -1, 0, 1, 0, -1]
RUN_DX = [3, 1, -2, -4, -3, 0, 3, 5]
RUN_LIFT = [0, 0, 1, 2, 3, 3, 2, 1]
RUN_BOB = [1, 0, -1, -2, 1, 0, -1, -2]


def _gait(p, k, o, dx_t, lift_t, bob_t, stride=1.0, lift_mul=1.0, bob_mul=1.0):
    near = (dx_t[k], lift_t[k])
    far = (dx_t[(k + 4) % 8], lift_t[(k + 4) % 8])
    s = o.get("stride", 1.0) * stride
    p.feet = [(int(round(near[0] * s)), int(round(near[1] * lift_mul))),
              (int(round(far[0] * s)), int(round(far[1] * lift_mul)))]
    p.bob = int(round(bob_t[k] * bob_mul))
    if p.view != "side":
        # front/back: the foot that is swinging is the lifted one; feet stay apart
        p.feet = [(0, int(round(near[1] * lift_mul))), (0, int(round(far[1] * lift_mul)))]
    return near, far


def _arm_swing(p, o, near_dx, amount=0.7, A=None):
    A = A if A is not None else o.get("arm", 7)
    sw = -near_dx * amount * o.get("stride", 1.0)
    if p.view == "side":
        p.hands = [(sw, -A + abs(sw) * 0.3), (-sw, -A + abs(sw) * 0.3)]
    else:
        # in front/back views the swing reads as the hand rising a little as it comes forward
        p.hands = [(max(0, -sw) * 0.8, -A + max(0, -sw) * 0.6), (max(0, sw) * 0.8, -A + max(0, sw) * 0.6)]


def a_idle(p, k, o):
    p.breath = [0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0][k]
    p.head_dy = [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0][k]
    if k == 9:
        p.eyes = "closed"


def a_walk(p, k, o):
    near, far = _gait(p, k, o, WALK_DX, WALK_LIFT, WALK_BOB)
    _arm_swing(p, o, near[0])
    p.head_dy = WALK_BOB[(k - 1) % 8] * 0  # head rides with the body


def a_run(p, k, o):
    near, far = _gait(p, k, o, RUN_DX, RUN_LIFT, RUN_BOB, stride=1.15, lift_mul=1.0)
    p.lean = 1
    A = o.get("arm", 7)
    sw = -near[0] * 0.8
    if p.view == "side":
        p.hands = [(sw + 2, -A * 0.45), (-sw + 2, -A * 0.45)]
    else:
        p.hands = [(2 + max(0, -sw), -A * 0.5 + max(0, -sw) * 0.5), (2 + max(0, sw), -A * 0.5 + max(0, sw) * 0.5)]
    if k in (0, 4):
        p.marks.append(("dust", 0, 0, 0))


def a_tired(p, k, o):
    near, far = _gait(p, k, o, WALK_DX, WALK_LIFT, WALK_BOB, stride=0.6, lift_mul=0.6, bob_mul=0.6)
    _arm_swing(p, o, near[0], amount=0.3, A=o.get("arm", 7) + 1)
    p.head_dy = 1
    p.lean = 1 if p.view == "side" else 0
    p.eyes = "half"
    if k == 6:
        p.marks.append(("puff", 0))
    if k == 7:
        p.marks.append(("puff", 1))


def a_cautious(p, k, o):
    near, far = _gait(p, k, o, WALK_DX, WALK_LIFT, WALK_BOB, stride=0.6, lift_mul=0.7, bob_mul=0.5)
    _arm_swing(p, o, near[0], amount=0.3)
    # hand over nose and mouth
    p.hands[0] = (3, 2) if p.view == "side" else (2, 4.5, 5.5)
    p.lean = 1 if p.view == "side" else 0
    p.head_dy = 1
    p.eyes = "half"


def a_carry(p, k, o):
    near, far = _gait(p, k, o, WALK_DX, WALK_LIFT, WALK_BOB, stride=0.8)
    if p.view == "side":
        p.hands = [(4, -2), (4, -2)]
        p.hold = ("crate", 0, 0)
    else:
        p.hands = [(3, -2.5), (3, -2.5)]
        p.hold = ("crate", 1, 0)
    p.lean = -1 if p.view == "side" else 0


def a_carry_coil(p, k, o):
    a_carry(p, k, o)
    p.hold = ("coil", p.hold[1], 0)


def a_look(p, k, o):
    a_idle(p, k, o)
    p.look = [0, 0, -1, -1, -1, -1, 0, 1, 1, 1, 1, 0][k]
    p.head_dx = p.look if p.view == "down" else 0
    p.eyes = "closed" if k == 6 else "open"


def a_stretch(p, k, o):
    A = o.get("arm", 7)
    up = [0, 0.3, 0.7, 1, 1, 1, 1, 1, 0.8, 0.5, 0.2, 0][k]
    if p.view == "side":
        p.hands = [(1 - up, -A + up * (A * 2 + 3)), (0, -A + up * (A * 2 + 2))]
    else:
        p.hands = [(1, -A + up * (A * 2 + 3)), (1, -A + up * (A * 2 + 3))]
    p.bob = -1 if 3 <= k <= 7 else 0
    p.eyes = "closed" if 3 <= k <= 8 else "open"
    p.mouth = 2 if 4 <= k <= 6 else 0
    p.breath = 1 if 3 <= k <= 7 else 0


def a_yawn(p, k, o):
    a_idle(p, k % 8, o)
    up = [0, 0.4, 1, 1, 1, 1, 1, 0.6, 0.2, 0][k]
    A = o.get("arm", 7)
    p.hands = [(2 * up, -A + up * (A + 3)), None] if p.view == "side" else [(2 * up, -A + up * (A + 4.5), 5.5 * up), None]
    p.mouth = 2 if 2 <= k <= 6 else 0
    p.eyes = "closed" if 2 <= k <= 7 else "half"
    p.head_dy = -1 if 2 <= k <= 5 else 0


def a_shiver(p, k, o):
    p.lean = [1, 0, -1, 0, 1, 0, -1, 0][k] if p.view != "side" else 0
    p.head_dx = p.lean if p.view == "down" else 0
    if p.view == "side":
        p.bob = k % 2
    p.hands = [(3, 1), (3, 1)] if p.view != "side" else [(2, 1), (1, 1)]
    p.eyes = "half"
    p.mouth = 1 if k % 2 else 0
    if k in (2, 3):
        p.marks.append(("puff", k - 2))


def a_lamp(p, k, o):
    a_idle(p, k % 8, o)
    A = o.get("arm", 7)
    up = [0, 0.5, 1, 1, 1, 1, 1, 1, 0.5, 0][k]
    tap = k in (3, 6)
    if p.view == "side":
        p.hands = [(2 * up + (1 if tap else 0), -A + up * (A + 6)), None]
    else:
        p.hands = [None, (1 * up, -A + up * (A + 7.5) + (1 if tap else 0), 4.5 * up)]
    p.lamp = k not in (4, 5)
    p.eyes = "up" if 2 <= k <= 7 else "open"


def a_rope(p, k, o):
    a_idle(p, k % 8, o)
    A = o.get("arm", 7)
    up = [0, 0.5, 1, 1, 1, 1, 1, 0.5, 0, 0][k]
    hand = (up * 1 + (k % 2) * up, -A + up * (A + 1)) if p.view == "side" else (up * 2, -A + up * (A + 1) + (k % 2) * up)
    p.hands = [None, hand] if p.view != "side" else [hand, None]


# --- tool actions ---------------------------------------------------------------------------
def _two_hands(p, fwd, up, spread=0.0):
    if p.view == "side":
        p.hands = [(fwd, up), (fwd - 1, up - 0.5)]
    else:
        p.hands = [(fwd + spread, up), (fwd + spread, up)]


def a_till(p, k, o):
    A = o.get("arm", 7)
    # raise, hold, strike, recover
    fwd = [2, 1, 0, 0, 3, 5, 5, 3][k]
    up = [-4, 0, 5, 6, 1, -4, -5, -3][k]
    ang = [45, -40, -110, -120, -20, 60, 70, 50][k]
    _two_hands(p, fwd, up)
    p.hold = ("hoe", 0 if p.view == "side" else 1, ang)
    p.crouch = [0, 0, 0, 0, 0.1, 0.3, 0.3, 0.1][k]
    p.bob = [0, 0, -1, -1, 0, 1, 1, 0][k]
    p.lean = [0, 0, -1, -1, 0, 1, 1, 0][k] if p.view == "side" else 0
    p.eyes = "half" if k in (5, 6) else "open"
    if k == 5:
        p.marks.append(("dust", 0, 0, 0))


def a_hammer(p, k, o):
    fwd = [2, 1, -1, -1, 3, 5, 5, 3][k]
    up = [-3, 2, 6, 7, 2, -2, -3, -2][k]
    ang = [30, -60, -120, -130, -30, 40, 50, 30][k]
    _two_hands(p, fwd, up)
    p.hold = ("hammer", 0 if p.view == "side" else 1, ang)
    p.crouch = [0, 0, 0, 0, 0, 0.2, 0.25, 0.1][k]
    p.bob = [0, 0, -1, -1, 0, 1, 1, 0][k]
    p.lean = [0, -1, -1, -1, 0, 1, 1, 0][k] if p.view == "side" else 0
    p.eyes = "half" if k in (5, 6) else "open"
    if k == 5:
        p.marks.append(("spark", k, 0, 0))


def a_water(p, k, o):
    tilt = [0, 10, 35, 50, 55, 50, 30, 5][k]
    if p.view == "side":
        p.hands = [(5, -1), None]
    else:
        p.hands = [None, (4, -1)]
    p.hold = ("can", 0 if p.view == "side" else 1, tilt)
    p.crouch = 0.1 if 2 <= k <= 6 else 0.0
    p.lean = 1 if (p.view == "side" and 2 <= k <= 6) else 0
    if 3 <= k <= 6:
        p.marks.append(("pour", k))


def a_wrench(p, k, o):
    p.crouch = 0.55
    turn = [-30, -10, 15, 35, 35, 15, -10, -30][k]
    if p.view == "side":
        p.hands = [(5, -3 + (1 if 2 <= k <= 5 else 0)), (4, -3)]
    else:
        p.hands = [(4, -3), (4, -3 + (1 if 2 <= k <= 5 else 0))]
    p.hold = ("wrench", 0 if p.view == "side" else 1, turn)
    p.lean = 1 if p.view == "side" else 0
    p.head_dy = 1
    if k == 4:
        p.marks.append(("spark", k, 0, 0))


def a_plant(p, k, o):
    p.crouch = [0.2, 0.5, 0.8, 0.85, 0.85, 0.85, 0.6, 0.3][k]
    reach = [0, 0.5, 1, 1, 1, 0.7, 0.3, 0][k]
    if p.view == "side":
        p.hands = [(2 + reach * 4, -6 - reach * 3 + (1 if k == 5 else 0)), None]
    else:
        p.hands = [None, (2 + reach * 3, -6 - reach * 2 + (1 if k == 5 else 0))]
    if k in (2, 3):
        p.hold = ("seed", 0 if p.view == "side" else 1, 90)
    p.lean = 1 if p.view == "side" else 0
    p.head_dy = 1 if 2 <= k <= 5 else 0


def a_harvest(p, k, o):
    p.crouch = [0.3, 0.7, 0.8, 0.6, 0.2, 0, 0, 0][k]
    if p.view == "side":
        p.hands = [[(3, -7), (5, -9), (5, -9), (4, -6), (3, -1), (2, 5), (2, 6), (2, 4)][k],
                   [None, (4, -9), (4, -9), (3, -6), (2, -2), None, None, None][k]]
    else:
        p.hands = [[None, (3, -8), (3, -8), (3, -6), (2, -2), None, None, None][k],
                   [(2, -7), (3, -8), (3, -8), (3, -6), (2, -1), (1, 6), (1, 7), (1, 5)][k]]
    if k >= 2:
        p.hold = ("crop", 0 if p.view == "side" else 1, -90)
    p.lean = [1, 1, 1, 0, -1, 0, 0, 0][k] if p.view == "side" else 0
    p.bob = [0, 0, 0, 0, 0, -1, -1, 0][k]
    p.eyes = "half" if k in (2, 3) else ("open" if k < 5 else "happy")
    if k >= 5:
        p.emote = "happy"


def a_pickup(p, k, o):
    p.crouch = [0.2, 0.6, 0.7, 0.6, 0.3, 0][k]
    if p.view == "side":
        p.hands = [[(3, -7), (4, -9), (4, -10), (3, -7), (2, -5), None][k], None]
    else:
        p.hands = [None, [(2, -7), (3, -8), (3, -9), (2, -7), (1, -5), None][k]]
    p.lean = 1 if p.view == "side" and 1 <= k <= 3 else 0
    p.head_dy = 1 if 1 <= k <= 3 else 0


def a_crank(p, k, o):
    ang = k / 8 * math.tau
    cx_, cy_ = 4 + math.cos(ang) * 1.5, -2 + math.sin(ang) * 1.5
    if p.view == "side":
        p.hands = [(cx_, -cy_ - 2), (cx_ - 1, -cy_ - 2)]
    else:
        p.hands = [(cx_ - 1, -cy_ - 2), (cx_ - 1, -cy_ - 2)]
    p.hold = ("crank", 0 if p.view == "side" else 1, math.degrees(ang))
    p.bob = 1 if k in (2, 3, 4) else 0
    p.lean = 1 if p.view == "side" else 0


def a_knock(p, k, o):
    rap = k in (2, 5)
    if p.view == "side":
        p.hands = [(5 + (1 if rap else 0), 1 if not rap else 1.5), None]
    else:
        p.hands = [None, (5 + (1 if rap else 0), 2)]
    p.lean = 1 if p.view == "side" else 0
    p.head_dy = 0
    p.eyes = "half" if k > 5 else "open"


# --- social ---------------------------------------------------------------------------------
def a_talk(p, k, o):
    a_idle(p, k % 8, o)
    A = o.get("arm", 7)
    g = [0, 0.4, 1, 1, 0.6, 0.2, 0, 0][k]
    if p.view == "side":
        p.hands = [(2 + g * 2, -A + g * 4), None]
    else:
        p.hands = [None, (1 + g * 2, -A + g * 4)]
    p.mouth = [1, 0, 1, 1, 0, 1, 0, 0][k]


def a_happy(p, k, o):
    p.emote = "happy"
    p.bob = [0, -1, -2, -1, 0, -1, -1, 0][k]
    p.lift_body = [0, 1, 2, 1, 0, 1, 1, 0][k]
    A = o.get("arm", 7)
    up = [0, 0.5, 0.8, 0.5, 0.2, 0.4, 0.4, 0][k]
    p.hands = [(1, -A + up * 6), (1, -A + up * 6)]
    p.mouth = 1 if k in (1, 2, 5, 6) else 0


def a_sad(p, k, o):
    p.emote = "sad"
    p.bob = [0, 1, 1, 1, 1, 1, 1, 1][k]
    p.head_dy = [0, 1, 1, 2, 2, 2, 2, 2][k]
    A = o.get("arm", 7)
    p.hands = [(0, -A - 1), (0, -A - 1)]


def a_surprised(p, k, o):
    p.emote = "surprised"
    p.bob = [0, -2, -1, 0, 0, 0, 0, 0][k]
    p.lift_body = [0, 2, 1, 0, 0, 0, 0, 0][k]
    p.lean = [0, -1, -1, -1, 0, 0, 0, 0][k] if p.view == "side" else 0
    A = o.get("arm", 7)
    up = [0, 1, 0.8, 0.5, 0.4, 0.3, 0.3, 0.3][k]
    p.hands = [(1, -A + up * 5), (1, -A + up * 5)]


def a_annoyed(p, k, o):
    p.emote = "annoyed"
    p.hands = [(2, -3), (2, -3.5)] if p.view == "side" else [(3, -3.5), (3, -3)]
    p.feet = [(0, 0), (0, 1 if k in (2, 6) else 0)]


def a_celebrate(p, k, o):
    p.emote = "happy"
    A = o.get("arm", 7)
    up = [0, 0.6, 1, 1, 1, 1, 0.6, 0.2][k]
    p.hands = [(0, -A + up * (A * 2 + 3)), (0, -A + up * (A * 2 + 3))]
    p.lift_body = [0, 0, 2, 3, 2, 0, 0, 0][k]
    p.crouch = [0.2, 0.3, 0, 0, 0, 0.2, 0, 0][k]
    p.mouth = 2 if 2 <= k <= 5 else 1


def a_wave(p, k, o):
    a_idle(p, k % 8, o)
    A = o.get("arm", 7)
    up = [0, 0.6, 1, 1, 1, 1, 1, 0.5][k]
    sway = [0, 0, -1, 1, -1, 1, -1, 0][k]
    if p.view == "side":
        p.hands = [(1 + sway, -A + up * (A + 8)), None]
    else:
        p.hands = [None, (sway * 1.5, -A + up * (A + 8))]
    p.emote = "happy" if 2 <= k <= 6 else ""


def a_sit(p, k, o):
    p.crouch = 0.75
    p.breath = [0, 0, 1, 1][k]
    if p.view == "side":
        p.feet = [(4, 0), (3, 0)]
        p.hands = [(3, -4), (2, -4)]
    else:
        p.hands = [(2, -4), (2, -4)]


def a_cough(p, k, o):
    p.hands = [(3, 2), None] if p.view == "side" else [(2, 4.5, 5.5), None]
    p.lean = [0, 1, 1, 0, 1, 1, 0, 0][k] if p.view == "side" else 0
    p.bob = [0, 1, 0, 0, 1, 0, 0, 0][k]
    p.eyes = "closed" if k in (1, 2, 4, 5) else "half"
    p.mouth = 1 if k in (1, 4) else 0


def a_getup(p, k, o):
    """From sprawled on all fours to standing (the landing in the grotto)."""
    p.crouch = [1, 1, 1, 0.95, 0.85, 0.7, 0.5, 0.3, 0.1, 0][k]
    A = o.get("arm", 7)
    if p.view == "side":
        p.hands = [[(5, -10), (5, -10), (5, -10), (5, -10), (4, -9), (3, -7), (2, -6), (1, -7), (0, -7), None][k], None]
    else:
        p.hands = [[(3, -9), (3, -9), (3, -9), (3, -9), (2, -8), (2, -7), (1, -7), None, None, None][k]] * 2
    p.lean = [2, 2, 2, 2, 1, 1, 0, 0, 0, 0][k] if p.view == "side" else 0
    p.head_dy = [2, 2, 1, 1, 1, 0, 0, 0, 0, 0][k]
    p.eyes = ["closed", "closed", "half", "half", "open", "open", "open", "open", "open", "open"][k]
    if k == 9:
        p.head_dx = 0


def a_collapse(p, k, o):
    p.crouch = [0, 0.2, 0.5, 0.8, 1, 1, 1, 1][k]
    if p.view == "side":
        p.hands = [[None, None, (2, -6), (4, -9), (5, -10), (5, -10), (5, -10), (5, -10)][k], None]
    else:
        p.hands = [[None, None, (2, -6), (3, -9), (3, -9), (3, -9), (3, -9), (3, -9)][k]] * 2
    p.lean = [0, 0, 1, 1, 2, 2, 2, 2][k] if p.view == "side" else 0
    p.head_dy = [0, 1, 1, 1, 2, 2, 3, 3][k]
    p.eyes = "half" if k < 4 else "closed"


def a_listen(p, k, o):
    """Kneels and lays a palm on the ground or a pipe, listening."""
    p.crouch = 0.8
    if p.view == "side":
        p.hands = [(4, -9), None]
    else:
        p.hands = [None, (3, -8)]
    p.head_dy = 1
    p.head_dx = 1 if p.view == "down" else 0
    p.eyes = "closed" if 3 <= k <= 8 else "half"


# --- NPC activities -------------------------------------------------------------------------
def a_tea(p, k, o):
    a_idle(p, k % 8, o)
    sip = [0, 0, 0.5, 1, 1, 1, 0.5, 0, 0, 0, 0, 0][k]
    if p.view == "side":
        p.hands = [(3 + sip, -3 + sip * 6), None]
    else:
        p.hands = [None, (2 + sip, -3 + sip * 7, 2 + sip * 3.5)]
    p.hold = ("cup", 0 if p.view == "side" else 1, 0)
    if sip == 0 and k % 3 == 0:
        p.marks.append(("steam", k // 3, 0, 0))


def a_ledger(p, k, o):
    a_idle(p, k % 8, o)
    w = [0, 1, 0, 1, 2, 1, 2, 1, 0, 1, 0, 0][k]
    if p.view == "side":
        p.hands = [(3, -3), (4 + (w % 2), -2.5 + w * 0.5)]
    else:
        p.hands = [(3, -3), (3 + (w % 2), -2 + w * 0.5)]
    p.hold = ("ledger", 0, 0)
    p.hold2 = ("pencil", 1, 60)
    p.head_dy = 1
    p.eyes = "half"


def a_coins(p, k, o):
    a_idle(p, k % 8, o)
    tap = k in (2, 4, 6)
    if p.view == "side":
        p.hands = [(4, -3), (4, -2 + (1 if tap else 0))]
    else:
        p.hands = [(3, -3), (3, -2 + (1 if tap else 0))]
    p.hold = ("pouch", 0, 0)
    p.head_dy = 1
    p.mouth = 1 if k in (3, 7) else 0


def a_tend(p, k, o):
    p.crouch = 0.85
    pat = [0, 1, 0, 1, 0, 0, 1, 0][k]
    if p.view == "side":
        p.hands = [(5, -9 + pat), (4, -9 + (1 - pat))]
    else:
        p.hands = [(3, -8 + pat), (3, -8 + (1 - pat))]
    p.lean = 1 if p.view == "side" else 0
    p.head_dy = 1
    p.mouth = 1 if k in (2, 5) else 0


def a_observe(p, k, o):
    a_idle(p, k % 8, o)
    A = o.get("arm", 7)
    count = [0, 0, 1, 1, 2, 2, 3, 3, 2, 1, 0, 0][k]
    if p.view == "side":
        p.hands = [(3, -A + 9 + (count % 2)), None]
    else:
        p.hands = [None, (2, -A + 9 + (count % 2))]
    p.eyes = "up"
    p.head_dy = -1
    p.mouth = 1 if k in (3, 5, 7) else 0


def a_inspect(p, k, o):
    a_idle(p, k % 8, o)
    if p.view == "side":
        p.hands = [(3, 5), None]
    else:
        p.hands = [None, (3, 5.5)]
    p.hold = ("glass", 0 if p.view == "side" else 1, 0)
    p.look = [0, -1, -1, -1, 0, 1, 1, 1, 0, 0, 0, 0][k]
    p.head_dx = p.look if p.view == "down" else 0


def a_cook(p, k, o):
    ang = k / 8 * math.tau
    if p.view == "side":
        p.hands = [(4 + math.cos(ang) * 1.5, -3 + math.sin(ang)), (3, -4)]
    else:
        p.hands = [(3, -4), (3 + math.cos(ang) * 1.2, -3 + math.sin(ang))]
    p.hold = ("ladle", 0 if p.view == "side" else 1, 80)
    p.bob = 1 if k in (2, 3) else 0
    p.lean = 1 if p.view == "side" else 0
    if k % 4 == 0:
        p.marks.append(("steam", k // 4, 0, 0))


def a_serve(p, k, o):
    a_idle(p, k % 8, o)
    reach = [0, 0.5, 1, 1, 1, 1, 0.5, 0][k]
    p.hands = [(2 + reach * 3, -3), (2 + reach * 3, -3)]
    p.hold = ("bowl", 1 if p.view != "side" else 0, 0)
    p.emote = "happy" if 2 <= k <= 5 else ""
    if k % 3 == 1:
        p.marks.append(("steam", k // 3, 0, 0))


def a_chew(p, k, o):
    """Grist eats a stone."""
    up = [0, 0.5, 1, 1, 1, 1, 0.6, 0.2, 0, 0, 0, 0][k]
    p.hands = [(4, -10 + up * 9), None]
    if up > 0.3:
        p.hold = ("rock", 0, 0)
    p.mouth = 1 if k in (4, 5, 7, 9) else 0
    p.eyes = "half" if k > 6 else "open"
    p.emote = "happy" if k >= 8 else ""


# Library: name -> (frames, fps, loop, views, fn, events)
LIB = {
    "idle": (12, 5, True, ("down", "up", "side"), a_idle, {}),
    "walk": (8, 11, True, ("down", "up", "side"), a_walk, {"step": [0, 4]}),
    "run": (8, 15, True, ("down", "up", "side"), a_run, {"step": [0, 4]}),
    "tired": (8, 7, True, ("down", "up", "side"), a_tired, {"step": [0, 4]}),
    "cautious": (8, 8, True, ("down", "up", "side"), a_cautious, {"step": [0, 4]}),
    "carry": (8, 9, True, ("down", "up", "side"), a_carry, {"step": [0, 4]}),
    "carrycoil": (8, 8, True, ("down", "up", "side"), a_carry_coil, {"step": [0, 4]}),
    "look": (12, 6, False, ("down", "side"), a_look, {}),
    "stretch": (12, 7, False, ("down", "side"), a_stretch, {}),
    "yawn": (10, 6, False, ("down", "side"), a_yawn, {}),
    "shiver": (8, 14, True, ("down", "side"), a_shiver, {}),
    "lamp": (10, 8, False, ("down", "side"), a_lamp, {"tap": [3, 6]}),
    "rope": (10, 7, False, ("down", "side"), a_rope, {}),
    "till": (8, 13, False, ("down", "up", "side"), a_till, {"hit": [5]}),
    "hammer": (8, 14, False, ("down", "up", "side"), a_hammer, {"hit": [5]}),
    "water": (8, 10, False, ("down", "up", "side"), a_water, {"hit": [3]}),
    "wrench": (8, 10, True, ("down", "up", "side"), a_wrench, {"hit": [4]}),
    "plant": (8, 11, False, ("down", "up", "side"), a_plant, {"hit": [4]}),
    "harvest": (8, 11, False, ("down", "up", "side"), a_harvest, {"hit": [3]}),
    "pickup": (6, 12, False, ("down", "up", "side"), a_pickup, {"hit": [2]}),
    "crank": (8, 9, True, ("down", "up", "side"), a_crank, {"hit": [0]}),
    "knock": (8, 10, False, ("down", "up", "side"), a_knock, {"hit": [2, 5]}),
    "talk": (8, 8, True, ("down", "side"), a_talk, {}),
    "happy": (8, 9, False, ("down", "side"), a_happy, {}),
    "sad": (8, 6, False, ("down", "side"), a_sad, {}),
    "surprised": (8, 10, False, ("down", "side"), a_surprised, {}),
    "annoyed": (8, 6, True, ("down", "side"), a_annoyed, {}),
    "celebrate": (8, 10, False, ("down",), a_celebrate, {}),
    "wave": (8, 10, False, ("down", "side"), a_wave, {}),
    "sit": (4, 3, True, ("down", "side"), a_sit, {}),
    "cough": (8, 10, False, ("down", "side"), a_cough, {}),
    "getup": (10, 5, False, ("down", "side"), a_getup, {}),
    "collapse": (8, 7, False, ("down", "side"), a_collapse, {}),
    "listen": (12, 5, True, ("down", "side"), a_listen, {}),
    "tea": (12, 5, True, ("down", "side"), a_tea, {}),
    "ledger": (12, 6, True, ("down", "side"), a_ledger, {}),
    "coins": (8, 6, True, ("down", "side"), a_coins, {}),
    "tend": (8, 5, True, ("down", "side"), a_tend, {}),
    "observe": (12, 4, True, ("down", "side"), a_observe, {}),
    "inspect": (12, 4, True, ("down", "side"), a_inspect, {}),
    "cook": (8, 7, True, ("down", "side"), a_cook, {}),
    "serve": (8, 6, True, ("down", "side"), a_serve, {}),
    "chew": (12, 6, True, ("down", "side"), a_chew, {}),
}

PORTRAIT_FRAMES = {"neutral": ("idle", 0), "happy": ("happy", 2), "sad": ("sad", 4),
                   "surprised": ("surprised", 2), "annoyed": ("annoyed", 1)}


def build_sheet(draw, fw, fh, anims, opts, emit_path, out_png, out_json):
    """Packs every (anim, view) strip into a sheet two strips wide and writes the metadata."""
    strips = []
    for name in anims:
        n, fps, loop, views, fn, events = LIB[name]
        for view in views:
            strips.append((name, view, n, fps, loop, fn, events))
    per_row = 2
    rows = (len(strips) + per_row - 1) // per_row
    cols = STRIP * per_row
    big = Canvas(fw * cols, fh * rows)
    glow = Canvas(fw * cols, fh * rows)
    meta = {}
    for si, (name, view, n, fps, loop, fn, events) in enumerate(strips):
        r, s = si // per_row, si % per_row
        for k in range(n):
            frame = Canvas(fw, fh)
            g = Canvas(fw, fh)
            p = Pose(view, name, k, n)
            fn(p, k, opts)
            draw(frame, g, p)
            frame.outline(-0.62)
            big.paste(frame, (s * STRIP + k) * fw, r * fh)
            glow.paste(g, (s * STRIP + k) * fw, r * fh)
        meta[f"{name}_{view}"] = {"start": r * cols + s * STRIP, "frames": n, "fps": fps, "loop": loop,
                                  "events": events}
    big.save(out_png)
    if emit_path:
        glow.save(emit_path)
    portraits = {}
    for emote, (anim, k) in PORTRAIT_FRAMES.items():
        key = f"{anim}_down"
        if key in meta:
            portraits[emote] = meta[key]["start"] + k
    import json
    with open(out_json, "w") as f:
        json.dump({"w": fw, "h": fh, "cols": cols, "rows": rows, "emit": bool(emit_path),
                   "anims": meta, "portraits": portraits}, f, indent=1)
    return big
