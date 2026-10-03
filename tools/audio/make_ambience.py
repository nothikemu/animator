"""Looping ambience beds, one per biome (data/biomes.json "ambience"). 32-second loops built
from shaped noise and sparse seeded events; event tails wrap so the loop is seamless.
    python3 tools/audio/make_ambience.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from dsp import (SR, sine, fm, noise, env_perc, env_adsr, lowpass, highpass, bandpass, resonator,  # noqa: E402
                 sweep_lowpass, pan, mix_into, normalize, write_ogg, t_axis, rng, reverb)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "ambience")
LOOP = 32.0


def loopify(x, n, k=None):
    """Takes n samples from an over-rendered signal and crossfades its continuation into the
    head, so sample n-1 flows into sample 0 without a click."""
    k = k or int(0.5 * SR)
    out = x[:n].copy()
    ramp = np.linspace(0, 1, k)
    out[:k] = x[:k] * ramp + x[n:n + k] * (1 - ramp)
    return out


def bed(seed, lo, hi, gain, sway=0.08):
    """Filtered noise bed whose level breathes slowly; built from a loop-length buffer so it
    wraps cleanly (the slow LFOs complete whole cycles in the loop)."""
    n = int(LOOP * SR)
    x = loopify(bandpass(noise(LOOP + 1.0, seed, "pink"), lo, hi)[int(0.4 * SR):], n)
    t = np.arange(n) / SR
    lfo = 1 + sway * np.sin(2 * np.pi * t / LOOP * 2) + sway * 0.5 * np.sin(2 * np.pi * t / LOOP * 5 + 1.3)
    # Crossfade the head with the over-rendered tail for a click-free seam.
    return x * lfo * gain


def drip(seed, freq=None):
    r = rng(seed)
    f = freq or r.uniform(900, 2200)
    d = 0.25
    t = t_axis(d)
    plink = sine(f * (1 + 0.6 * np.exp(-t * 40)), d) * env_perc(int(d * SR), 0.0005, 0.05)
    return plink * 0.5


def place_events(buf, events):
    for at, x, p in events:
        mix_into(buf, pan(x, p), int(at * SR) % len(buf))


def grove():
    n = int(LOOP * SR)
    buf = np.zeros((n, 2))
    air = bed(1, 120, 1800, 0.25)
    buf += np.stack([air, bed(2, 120, 1800, 0.25)], axis=1)
    hum = (sine(55, LOOP) * 0.06 + sine(110.3, LOOP) * 0.02)[:n]
    buf += np.stack([hum, hum], axis=1)
    r = rng(3)
    ev = [(r.uniform(0, LOOP), drip(10 + i), r.uniform(-0.8, 0.8)) for i in range(18)]
    # Glowroot "ticks": tiny soft chirps, very quiet, in clusters.
    for i in range(7):
        at = r.uniform(0, LOOP)
        for k in range(3):
            ev.append((at + k * 0.11, fm(r.uniform(3200, 4200), 2.0, 1.0, 0.06, 30) * env_perc(int(0.06 * SR), 0.001, 0.015) * 0.08, r.uniform(-1, 1)))
    place_events(buf, ev)
    return buf


def blackstone():
    n = int(LOOP * SR)
    buf = np.stack([bed(21, 200, 3500, 0.22, 0.15), bed(22, 200, 3500, 0.22, 0.15)], axis=1)
    wind = loopify(lowpass(noise(LOOP + 1, 23, "pink"), 650)[int(0.4 * SR):], n) * 0.12
    buf += np.stack([wind, wind * 0.8], axis=1)
    r = rng(24)
    ev = []
    for i in range(9):  # distant knapping: stone on stone, in little runs
        at = r.uniform(0, LOOP)
        for k in range(r.integers(2, 5)):
            tap = lowpass(highpass(noise(0.03, 30 + i * 7 + k), 600), 2500) * env_perc(int(0.03 * SR), 0.0005, 0.008) * 0.35
            ev.append((at + k * r.uniform(0.18, 0.3), tap, r.uniform(-0.9, 0.9)))
    for i in range(5):  # gravel trickles
        at = r.uniform(0, LOOP)
        tr = bandpass(noise(0.8, 60 + i), 1500, 6000) * env_adsr(int(0.8 * SR), 0.05, 0.2, 0.3, 0.4) * 0.08
        ev.append((at, tr, r.uniform(-1, 1)))
    place_events(buf, ev)
    return buf


def ember():
    n = int(LOOP * SR)
    rumble = loopify(lowpass(noise(LOOP + 1, 41, "pink"), 90)[int(0.4 * SR):], n) * 0.9
    buf = np.stack([rumble, rumble * 0.95], axis=1)
    buf += np.stack([bed(42, 300, 2000, 0.1), bed(43, 300, 2000, 0.1)], axis=1)
    r = rng(44)
    ev = []
    for i in range(60):  # crackles
        c = highpass(noise(0.006, 100 + i), 2500) * env_perc(int(0.006 * SR), 0.0002, 0.002) * r.uniform(0.1, 0.4)
        ev.append((r.uniform(0, LOOP), c, r.uniform(-1, 1)))
    for i in range(4):  # steam vents
        d = r.uniform(1.0, 2.0)
        hiss = highpass(noise(d, 200 + i), 2500) * env_adsr(int(d * SR), 0.15, 0.2, 0.6, 0.5) * 0.25
        ev.append((r.uniform(0, LOOP), hiss, r.uniform(-0.7, 0.7)))
    place_events(buf, ev)
    return buf


def sump():
    n = int(LOOP * SR)
    t = np.arange(n) / SR
    lap = loopify(lowpass(noise(LOOP + 1, 51, "pink"), 350)[int(0.4 * SR):], n) * (0.5 + 0.5 * np.sin(2 * np.pi * t / LOOP * 4) ** 2) * 0.5
    buf = np.stack([lap, np.roll(lap, 2000)], axis=1)
    r = rng(52)
    ev = [(r.uniform(0, LOOP), drip(60 + i, r.uniform(500, 1100)) * 1.2, r.uniform(-0.9, 0.9)) for i in range(24)]
    for i in range(2):  # a deep groan in the rock
        d = 4.0
        g = resonator(lowpass(noise(d, 300 + i), 200), 48 + i * 7, 20) * env_adsr(int(d * SR), 1.2, 0.5, 0.6, 1.8) * 1.2
        ev.append((r.uniform(0, LOOP), g, r.uniform(-0.5, 0.5)))
    place_events(buf, ev)
    wet = reverb(buf[:, 0], 0.4, 3.0, 1500, 9)
    out = np.zeros((n, 2))
    mix_into(out, wet, 0)
    return out


def main():
    for name, fn in [("grove", grove), ("blackstone", blackstone), ("ember", ember), ("sump", sump)]:
        x = fn()
        write_ogg(os.path.join(OUT, name + ".ogg"), normalize(x, 0.5), quality=2)
        print("ambience:", name)


if __name__ == "__main__":
    main()
