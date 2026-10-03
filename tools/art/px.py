"""Tiny pixel-art toolkit used by every Bellows art generator.

Design rules baked in:
  * colours come from data/palette.json or from hue-shifted ramps derived from it
  * shading ramps shift shadows toward violet and highlights toward warm
  * outlines are *selective*: tinted from the neighbouring fill, never pure black
  * noise used for texture is periodic so tiles wrap seamlessly
"""
import colorsys
import json
import math
import os
import random

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEX = os.path.join(ROOT, "assets", "textures")

with open(os.path.join(ROOT, "data", "palette.json")) as f:
    _PAL = {k: v for k, v in json.load(f).items() if not k.startswith("_")}


def hexc(h):
    h = h.lstrip("#")
    if len(h) == 6:
        h += "ff"
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4, 6))


def pal(name):
    return hexc(_PAL[name])


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3)) + (a[3] if len(a) > 3 else 255,)


def shade(c, amount):
    """Hue-shifted shading. amount < 0 darkens toward violet, > 0 lightens toward warm."""
    r, g, b = c[0] / 255, c[1] / 255, c[2] / 255
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    if amount < 0:
        l = max(0.0, l * (1 + amount))
        h = _hue_toward(h, 0.72, -amount * 0.12)   # violet
        s = min(1.0, s * (1 - amount * 0.15))
    else:
        l = min(1.0, l + (1 - l) * amount)
        h = _hue_toward(h, 0.11, amount * 0.10)     # warm amber
        s = s * (1 - amount * 0.2)
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return (int(r * 255), int(g * 255), int(b * 255), c[3] if len(c) > 3 else 255)


def _hue_toward(h, target, t):
    d = ((target - h + 0.5) % 1.0) - 0.5
    return (h + d * min(1.0, t)) % 1.0


def ramp(c, n=4, spread=0.42):
    """n-step ramp from dark to light around c (c sits roughly in the middle)."""
    out = []
    for i in range(n):
        t = (i / (n - 1)) * 2 - 1  # -1..1
        out.append(shade(c, t * spread) if t != 0 else c)
    return out


# --- noise ---------------------------------------------------------------------------------
def _hash(x, y, seed):
    n = (x * 374761393 + y * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def value_noise(x, y, period, seed, cell=4):
    """Periodic value noise in [0,1]; period in pixels must be divisible by cell."""
    gx, gy = x / cell, y / cell
    x0, y0 = int(math.floor(gx)), int(math.floor(gy))
    fx, fy = gx - x0, gy - y0
    p = max(1, period // cell)

    def v(ix, iy):
        return _hash(ix % p, iy % p, seed)

    sx = fx * fx * (3 - 2 * fx)
    sy = fy * fy * (3 - 2 * fy)
    a = v(x0, y0) + (v(x0 + 1, y0) - v(x0, y0)) * sx
    b = v(x0, y0 + 1) + (v(x0 + 1, y0 + 1) - v(x0, y0 + 1)) * sx
    return a + (b - a) * sy


def fbm(x, y, period, seed, octaves=3):
    total, amp, norm, cell = 0.0, 1.0, 0.0, 8
    for o in range(octaves):
        total += value_noise(x, y, period, seed + o * 31, max(1, cell)) * amp
        norm += amp
        amp *= 0.5
        cell = max(1, cell // 2)
    return total / norm


BAYER4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def dither_pick(colors, t, x, y):
    """Pick from an ordered list of colours by t in [0,1] with 4x4 ordered dithering."""
    n = len(colors)
    f = t * (n - 1)
    i = int(math.floor(f))
    frac = f - i
    if i >= n - 1:
        return colors[-1]
    thresh = (BAYER4[y % 4][x % 4] + 0.5) / 16.0
    return colors[i + 1] if frac > thresh else colors[i]


# --- canvas ----------------------------------------------------------------------------------
class Canvas:
    def __init__(self, w, h, fill=(0, 0, 0, 0)):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w, h), fill)
        self.px = self.img.load()

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[x, y]
        return (0, 0, 0, 0)

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h and c is not None:
            if len(c) == 3:
                c = c + (255,)
            self.px[x, y] = c

    def blend(self, x, y, c, a):
        if 0 <= x < self.w and 0 <= y < self.h:
            o = self.px[x, y]
            if o[3] == 0:
                return
            self.px[x, y] = mix(o, c, a)[:3] + (o[3],)

    def rect(self, x0, y0, w, h, c):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                self.set(x, y, c)

    def hline(self, x0, x1, y, c):
        for x in range(min(x0, x1), max(x0, x1) + 1):
            self.set(x, y, c)

    def vline(self, x, y0, y1, c):
        for y in range(min(y0, y1), max(y0, y1) + 1):
            self.set(x, y, c)

    def line(self, x0, y0, x1, y1, c):
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.set(x0, y0, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def disc(self, cx, cy, r, c):
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                    self.set(x, y, c)

    def ellipse(self, cx, cy, rx, ry, c):
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                    self.set(x, y, c)

    def paste(self, other, ox, oy, flip=False):
        for y in range(other.h):
            for x in range(other.w):
                c = other.px[other.w - 1 - x if flip else x, y]
                if c[3] > 0:
                    self.set(ox + x, oy + y, c)

    def ascii(self, rows, keys, ox=0, oy=0, flip=False):
        """Draws an ASCII pixel map. keys maps characters to colours ('.' / ' ' = transparent)."""
        width = max(len(r) for r in rows)
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch in (".", " "):
                    continue
                c = keys.get(ch)
                if c is None:
                    raise KeyError(f"unknown pixel key {ch!r}")
                xx = (width - 1 - x) if flip else x
                self.set(ox + xx, oy + y, c)

    def outline(self, darken=-0.62, diagonal=False, only_outside=True):
        """Selective outline: transparent pixels touching the silhouette take a dark,
        violet-shifted version of the neighbouring fill colour."""
        add = {}
        dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        if diagonal:
            dirs += [(1, 1), (-1, 1), (1, -1), (-1, -1)]
        for y in range(self.h):
            for x in range(self.w):
                if self.px[x, y][3] != 0:
                    continue
                for dx, dy in dirs:
                    c = self.get(x + dx, y + dy)
                    if c[3] > 0:
                        add[(x, y)] = shade(c, darken)
                        break
        for (x, y), c in add.items():
            self.px[x, y] = c[:3] + (255,)
        return self

    def save(self, path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.img.save(path)

    def crop(self, x, y, w, h):
        c = Canvas(w, h)
        c.img = self.img.crop((x, y, x + w, y + h))
        c.px = c.img.load()
        return c


def rng(seed):
    return random.Random(seed)
