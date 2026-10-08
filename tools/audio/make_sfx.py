"""Generates every sound effect and voice blip the game asks for (see src/autoload/audio.gd
callers). Variants are written as <name>_<n>.ogg; Audio picks one at random per play.
    python3 tools/audio/make_sfx.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from dsp import (SR, sine, saw, square, tri, fm, noise, env_adsr, env_perc, fade, lowpass, highpass,  # noqa: E402
                 bandpass, resonator, sweep_lowpass, saturate, reverb, pan, normalize, write_ogg, t_axis, rng, midi_hz)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "sfx")


def n_of(d):
    return int(d * SR)


def seg(x, d):
    n = n_of(d)
    return x[:n] if len(x) >= n else np.pad(x, (0, n - len(x)))


def place(total, parts):
    """parts: [(t_seconds, mono_array)] -> mono buffer"""
    buf = np.zeros(n_of(total))
    for t, x in parts:
        i = n_of(t)
        j = min(len(buf), i + len(x))
        buf[i:j] += x[: j - i]
    return buf


# --- UI ----------------------------------------------------------------------------------------

def ui_tick(s):
    d = 0.03
    return sine(2300, d) * env_perc(n_of(d), 0.0005, 0.008) * 0.6


def ui_move(s):
    d = 0.04
    return (sine(1500, d) * 0.6 + sine(3000, d) * 0.15) * env_perc(n_of(d), 0.001, 0.012) * 0.5


def ui_select(s):
    a = fm(midi_hz(81), 2.0, 1.2, 0.09, 30) * env_perc(n_of(0.09), 0.002, 0.04)
    b = fm(midi_hz(88), 2.0, 1.0, 0.16, 25) * env_perc(n_of(0.16), 0.002, 0.06)
    return place(0.2, [(0, a * 0.5), (0.05, b * 0.5)])


def ui_open(s):
    d = 0.32
    sw = sweep_lowpass(noise(d, s, "pink"), 500, 5000) * env_adsr(n_of(d), 0.08, 0.1, 0.4, 0.14) * 0.25
    th = sine(110, d) * env_perc(n_of(d), 0.003, 0.08) * 0.35
    return sw + th


def ui_close(s):
    d = 0.28
    sw = sweep_lowpass(noise(d, s + 9, "pink"), 4000, 400) * env_adsr(n_of(d), 0.01, 0.1, 0.5, 0.15) * 0.22
    th = sine(90, d) * env_perc(n_of(d), 0.002, 0.07) * 0.3
    return sw + place(d, [(0.12, th[: n_of(0.16)])])


def ui_error(s):
    d = 0.11
    x = lowpass(square(110, d), 900) * env_adsr(n_of(d), 0.003, 0.02, 0.7, 0.03) * 0.3
    return place(0.3, [(0, x), (0.14, x)])


def chime(s):
    notes = [76, 79, 84]
    parts = []
    for i, m in enumerate(notes):
        d = 1.2
        parts.append((i * 0.09, fm(midi_hz(m), 3.5, 2.0, d, 3.0) * env_perc(n_of(d), 0.002, 0.45) * 0.3))
    return place(1.5, parts)


def notice(s):
    a = fm(midi_hz(83), 2.0, 1.0, 0.9, 3) * env_perc(n_of(0.9), 0.002, 0.35) * 0.3
    b = fm(midi_hz(79), 2.0, 1.0, 1.1, 3) * env_perc(n_of(1.1), 0.002, 0.45) * 0.3
    return place(1.3, [(0, a), (0.16, b)])


# --- Hands & tools -----------------------------------------------------------------------------

def pickup(s):
    r = rng(s)
    base = 70 + r.integers(0, 3)
    a = fm(midi_hz(base), 1.0, 1.5, 0.15, 20) * env_perc(n_of(0.15), 0.002, 0.05)
    b = fm(midi_hz(base + 7), 1.0, 1.5, 0.25, 15) * env_perc(n_of(0.25), 0.002, 0.08)
    return place(0.3, [(0, a * 0.4), (0.06, b * 0.4)])


def metal_hit(s, freq=900.0, decay=0.35, bright=1.0):
    r = rng(s)
    d = decay * 3
    exc = noise(0.01, s) * np.hanning(n_of(0.01))
    exc = np.pad(exc, (0, n_of(d) - len(exc)))
    out = np.zeros(n_of(d))
    for k, ratio in enumerate([1.0, 2.76, 5.4, 8.93]):
        f = freq * ratio * (1 + r.uniform(-0.01, 0.01))
        out += resonator(exc, f, 60 + 40 * k) * (bright ** k) / (1 + k)
    return out * env_perc(n_of(d), 0.0005, decay) * 8.0


def salvage(s):
    clank = metal_hit(s, 640 + s * 23, 0.25)
    ratchet = place(0.5, [(0.12 + i * 0.045, highpass(noise(0.012, s + i), 2500) * env_perc(n_of(0.012), 0.0005, 0.004)) for i in range(6)])
    return place(0.8, [(0, clank * 0.6), (0.0, ratchet * 0.5)])


def well_crank(s):
    r = rng(s)
    d = 0.9
    t = t_axis(d)
    squeak_f = 700 + 120 * np.sin(2 * np.pi * 2.3 * t) + r.uniform(-40, 40)
    squeak = sine(squeak_f, d) * env_adsr(n_of(d), 0.1, 0.2, 0.5, 0.3) * 0.12
    squeak = bandpass(saturate(squeak * 3, 2), 500, 3000) * 0.3
    clicks = place(d, [(0.05 + i * 0.11, highpass(noise(0.008, s + i), 1800) * env_perc(n_of(0.008), 0.0005, 0.003) * 0.6) for i in range(7)])
    clunk = lowpass(noise(0.12, s + 50), 300) * env_perc(n_of(0.12), 0.001, 0.04) * 1.4
    gurgle = place(d, [(0.62, lowpass(noise(0.25, s + 3), 600) * env_perc(n_of(0.25), 0.02, 0.1) * 0.5)])
    return squeak + clicks + place(d, [(0.72, clunk)]) + gurgle


def water_fill(s):
    d = 0.9
    r = rng(s)
    pour = bandpass(noise(d, s, "pink"), 300, 3500) * env_adsr(n_of(d), 0.05, 0.1, 0.8, 0.25) * 0.35
    bubbles = []
    for i in range(14):
        bd = 0.05
        f0 = r.uniform(500, 1400) * (1 + i * 0.03)
        t = t_axis(bd)
        bubbles.append((r.uniform(0.05, 0.8), sine(f0 * (1 + t * 6), bd) * env_perc(n_of(bd), 0.001, 0.018) * 0.25))
    return pour + place(d, bubbles)


def water_pour(s):
    d = 0.7
    sp = highpass(noise(d, s), 2500) * env_adsr(n_of(d), 0.03, 0.1, 0.6, 0.3) * 0.25
    drops = place(d, [(rng(s + i).uniform(0.1, 0.6), sine(rng(s + i).uniform(1500, 2600), 0.03) * env_perc(n_of(0.03), 0.0005, 0.01) * 0.2) for i in range(10)])
    return sp + drops


def mine(s):
    r = rng(s)
    crack = highpass(noise(0.03, s), 1200) * env_perc(n_of(0.03), 0.0003, 0.008) * 1.4
    ping = metal_hit(s + 3, 1800 + r.uniform(-200, 200), 0.09, 0.5) * 0.35
    rubble = place(0.6, [(0.06 + r.uniform(0, 0.35), lowpass(noise(0.04, s + i), 2500) * env_perc(n_of(0.04), 0.001, 0.01) * 0.4) for i in range(6)])
    body = lowpass(noise(0.15, s + 9), 220) * env_perc(n_of(0.15), 0.001, 0.05) * 1.2
    return place(0.6, [(0, crack + seg(ping, 0.03)), (0, ping), (0, body)]) + rubble


def till(s):
    r = rng(s)
    d = 0.35
    crunch = bandpass(noise(d, s, "pink"), 150, 1800) * env_perc(n_of(d), 0.004, 0.09) * 0.9
    grit = place(d, [(r.uniform(0.02, 0.2), highpass(noise(0.01, s + i), 2000) * env_perc(n_of(0.01), 0.0005, 0.004) * 0.3) for i in range(8)])
    return crunch + grit


def plant(s):
    pat = lowpass(noise(0.12, s, "pink"), 500) * env_perc(n_of(0.12), 0.002, 0.03) * 0.8
    rattle = place(0.4, [(0.1 + i * 0.025, bandpass(noise(0.01, s + i), 2000, 6000) * env_perc(n_of(0.01), 0.0005, 0.004) * 0.25) for i in range(5)])
    return place(0.4, [(0, pat)]) + rattle


def harvest(s):
    pop = sine(240 * np.exp(-t_axis(0.12) * 9), 0.12) * env_perc(n_of(0.12), 0.001, 0.04) * 0.7
    rustle = bandpass(noise(0.35, s, "pink"), 800, 5000) * env_adsr(n_of(0.35), 0.02, 0.1, 0.4, 0.15) * 0.25
    sparkle = fm(midi_hz(84), 2.0, 1.0, 0.4, 6) * env_perc(n_of(0.4), 0.002, 0.15) * 0.15
    return place(0.5, [(0, pop), (0.02, rustle), (0.07, sparkle)])


def repair(s):
    clicks = place(0.6, [(0.02 + i * 0.07, metal_hit(s + i, 2400, 0.03, 0.4) * 0.3) for i in range(5)])
    hiss = highpass(noise(0.3, s + 20), 3000) * env_adsr(n_of(0.3), 0.02, 0.05, 0.6, 0.2) * 0.15
    return clicks + place(0.6, [(0.32, hiss)])


def pipe_lay(s):
    return place(0.6, [(0, metal_hit(s, 520 + 30 * s, 0.22) * 0.45), (0.11, metal_hit(s + 4, 760, 0.12) * 0.25)])


def wire_lay(s):
    d = 0.3
    t = t_axis(d)
    zip_ = bandpass(noise(d, s), 1500, 7000) * (0.5 + 0.5 * np.sin(2 * np.pi * 38 * t)) * env_adsr(n_of(d), 0.01, 0.05, 0.6, 0.1) * 0.25
    snap = highpass(noise(0.01, s + 1), 3000) * env_perc(n_of(0.01), 0.0003, 0.003) * 0.7
    return place(0.4, [(0, zip_), (0.29, snap)])


def build(s):
    hits = [(0.0, metal_hit(s, 420, 0.2) * 0.5), (0.22, metal_hit(s + 1, 455, 0.22) * 0.5)]
    clunk = lowpass(noise(0.2, s + 5), 260) * env_perc(n_of(0.2), 0.001, 0.07) * 1.3
    return place(1.0, hits + [(0.46, clunk)])


def craft(s):
    parts = [(0.0, metal_hit(s, 1100, 0.08) * 0.3), (0.13, lowpass(noise(0.06, s), 1500) * env_perc(n_of(0.06), 0.001, 0.02) * 0.5),
             (0.24, metal_hit(s + 2, 1350, 0.1) * 0.3)]
    done = fm(midi_hz(79), 2.0, 1.0, 0.5, 6) * env_perc(n_of(0.5), 0.002, 0.18) * 0.2
    return place(0.9, parts + [(0.38, done)])


# --- Story -------------------------------------------------------------------------------------

def winch(s):
    d = 2.2
    t = t_axis(d)
    f = 95 + 25 * np.sin(2 * np.pi * 0.7 * t) + 8 * np.sin(2 * np.pi * 5.3 * t)
    creak = saturate(sine(f, d) * (0.5 + 0.5 * np.sin(2 * np.pi * 9 * t) ** 2), 3) * 0.3
    creak = bandpass(creak, 200, 2500)
    rope = bandpass(noise(d, s), 1500, 4000) * (0.4 + 0.6 * np.abs(np.sin(2 * np.pi * 1.4 * t))) * 0.08
    return fade((creak + rope) * env_adsr(n_of(d), 0.4, 0.3, 0.8, 0.8), 0.05, 0.4)


def cable_snap(s):
    whip = highpass(noise(0.05, s), 2000) * env_perc(n_of(0.05), 0.0003, 0.01) * 1.6
    d = 2.0
    t = t_axis(d)
    twang = np.zeros(n_of(d))
    for k in range(1, 7):
        twang += np.sin(2 * np.pi * 180 * k * (1 + 0.0015 * k * k) * t) * np.exp(-t * (2.0 + k)) / k
    twang *= (1 + 0.3 * np.sin(2 * np.pi * 7 * t))
    return place(d, [(0, whip), (0.005, twang * 0.5)])


def fall(s):
    d = 2.8
    t = t_axis(d)
    wind = sweep_lowpass(noise(d, s, "pink"), 2500, 300) * env_adsr(n_of(d), 0.2, 0.3, 0.9, 0.3) * 0.5
    whistle = sine(900 * np.exp(-t * 0.5), d) * env_adsr(n_of(d), 0.5, 0.5, 0.3, 0.6) * 0.04
    thud = lowpass(noise(0.4, s + 2, "pink"), 180) * env_perc(n_of(0.4), 0.004, 0.12) * 1.6
    return place(3.4, [(0, wind + whistle), (2.85, thud)])


def travel(s):
    steps = [(0.05 + i * 0.32, lowpass(noise(0.08, s + i, "pink"), 700) * env_perc(n_of(0.08), 0.002, 0.03) * 0.5 * (1 - i * 0.18)) for i in range(4)]
    whoosh = sweep_lowpass(noise(1.0, s + 30, "pink"), 300, 1800) * env_adsr(n_of(1.0), 0.4, 0.2, 0.5, 0.3) * 0.25
    return place(1.6, steps + [(0.5, whoosh)])


def valve_turn(s):
    d = 3.0
    t = t_axis(d)
    grind = noise(d, s) * (0.6 + 0.4 * np.sin(2 * np.pi * 13 * t) ** 2)
    grind = resonator(bandpass(grind, 120, 1600), 210, 12) * 0.8 + resonator(grind, 340, 15) * 0.3
    grind = saturate(grind * env_adsr(n_of(d), 0.2, 0.5, 0.7, 0.9) * 0.6, 2)
    thunk = lowpass(noise(0.4, s + 4), 160) * env_perc(n_of(0.4), 0.001, 0.12) * 2.0
    sigh = sweep_lowpass(noise(3.0, s + 8, "pink"), 200, 1400) * env_adsr(n_of(3.0), 1.2, 0.5, 0.6, 1.2) * 0.4
    return place(5.5, [(0, grind * 0.6), (2.3, thunk), (2.4, sigh)])


def knock_323(s):
    """Three, two, three on an iron pipe — clear, deliberate, from somewhere far below."""
    hits = []
    pattern = [0.0, 0.28, 0.56, 1.25, 1.53, 2.25, 2.53, 2.81]
    for i, at in enumerate(pattern):
        k = metal_hit(s + i, 310, 0.5, 0.6)
        tap = lowpass(noise(0.03, s + 40 + i), 400) * env_perc(n_of(0.03), 0.0005, 0.01) * 0.8
        k[: len(tap)] += tap
        hits.append((at, k * 0.5))
    dry = place(4.5, hits)
    dry = lowpass(dry, 2200)
    return reverb(dry, 0.55, 3.5, 1800, 11)


def reveal(s):
    d = 4.0
    chord = sum(tri(midi_hz(m), d) for m in [50, 57, 62, 65, 69]) * 0.12
    chord = lowpass(chord, 1600) * env_adsr(n_of(d), 1.5, 0.5, 0.7, 1.5)
    sparkle = place(d, [(0.8 + i * 0.35, fm(midi_hz(m), 3.0, 1.6, 1.5, 3) * env_perc(n_of(1.5), 0.002, 0.5) * 0.1) for i, m in enumerate([81, 84, 86, 89])])
    return reverb(chord + sparkle, 0.45, 3.0, 4000, 5)


def cut_open(s):
    d = 2.0
    rumble = lowpass(noise(d, s, "brown"), 120) * env_adsr(n_of(d), 0.1, 0.3, 0.8, 0.8) * 1.4
    crumble = place(d, [(rng(s + i).uniform(0.05, 1.3), lowpass(noise(0.06, s + i), 1800) * env_perc(n_of(0.06), 0.001, 0.02) * 0.4) for i in range(26)])
    whoosh = sweep_lowpass(noise(1.4, s + 77, "pink"), 2400, 250) * env_adsr(n_of(1.4), 0.3, 0.3, 0.6, 0.5) * 0.4
    return place(2.4, [(0, rumble + crumble), (0.4, whoosh)])


def cut_close(s):
    d = 1.6
    rumble = lowpass(noise(d, s, "brown"), 140) * env_adsr(n_of(d), 0.6, 0.3, 0.6, 0.5) * 1.1
    whoosh = sweep_lowpass(noise(1.2, s + 70, "pink"), 300, 2200) * env_adsr(n_of(1.2), 0.4, 0.3, 0.6, 0.3) * 0.35
    settle = lowpass(noise(0.3, s + 5), 250) * env_perc(n_of(0.3), 0.002, 0.08) * 0.9
    return place(2.0, [(0, rumble), (0.1, whoosh), (1.25, settle)])


def lift(s):
    """The Primary Lift: a brake released, the cage taking the cable, a long whirring descent."""
    d = 3.4
    t = t_axis(d)
    brake = lowpass(noise(0.25, s), 900) * env_perc(n_of(0.25), 0.001, 0.08) * 1.2
    clank = metal_hit(s + 3, 220, 0.6, 0.5) * 0.6
    f = 70 + 30 * np.exp(-t * 0.8)
    whir = saturate(sine(f, d) * (0.6 + 0.4 * np.sin(2 * np.pi * 17 * t) ** 2), 2) * 0.25
    whir = bandpass(whir, 120, 1500) * env_adsr(n_of(d), 0.5, 0.3, 0.8, 0.9)
    cable = bandpass(noise(d, s + 9), 2000, 5000) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 2.1 * t))) * 0.06
    return place(3.8, [(0, brake), (0.05, clank), (0.25, whir + cable * env_adsr(n_of(d), 0.5, 0.3, 0.8, 0.9))])


def thud(s):
    """Somebody going down on the rock: a soft body-weight thump and a rattle of kit."""
    body = lowpass(noise(0.5, s, "pink"), 160) * env_perc(n_of(0.5), 0.004, 0.14) * 1.6
    kit = place(0.6, [(0.04 + i * 0.05, highpass(noise(0.02, s + 10 + i), 1500) * env_perc(n_of(0.02), 0.0005, 0.006) * 0.25) for i in range(4)])
    return place(0.9, [(0, body), (0.02, kit)])


def knock_single(s):
    """One knock on a pipe-head, close."""
    k = metal_hit(s, 330, 0.35, 0.7)
    tap = lowpass(noise(0.02, s + 40), 500) * env_perc(n_of(0.02), 0.0005, 0.008) * 0.9
    k[: len(tap)] += tap
    return k * 0.8


def heart_breath(s):
    """The Bellows' first breath: drawn in through every Trunk for eight seconds, held, let go."""
    d = 10.0
    t = t_axis(d)
    shape = np.clip(np.sin(np.pi * t / d), 0, 1) ** 1.5
    air = sweep_lowpass(noise(d, s, "pink"), 200, 2400) * shape * 0.7
    groan = resonator(lowpass(noise(d, s + 5), 300), 55, 30) * shape * 0.9
    chord = sum(tri(midi_hz(m), d) for m in [38, 45, 50, 54, 57]) * 0.06 * shape
    return reverb(air + groan + lowpass(chord, 1200), 0.5, 4.0, 1600, 21)


# --- Footsteps ---------------------------------------------------------------------------------

def step_soft(s):
    r = rng(s)
    return lowpass(noise(0.09, s, "pink"), 380 + r.uniform(-60, 60)) * env_perc(n_of(0.09), 0.003, 0.025) * 0.9


def step_stone(s):
    r = rng(s)
    click = bandpass(noise(0.03, s), 1500, 5000) * env_perc(n_of(0.03), 0.0005, 0.006) * 0.6
    body = lowpass(noise(0.06, s + 1), 600 + r.uniform(-80, 80)) * env_perc(n_of(0.06), 0.001, 0.018) * 0.6
    return place(0.1, [(0, click + seg(body, 0.03)), (0, body)])


def step_wood(s):
    r = rng(s)
    exc = noise(0.004, s) * np.hanning(n_of(0.004))
    exc = np.pad(exc, (0, n_of(0.18) - len(exc)))
    body = resonator(exc, 180 + r.uniform(-15, 15), 9) * 6 + resonator(exc, 420, 12) * 2
    return lowpass(body, 1800) * env_perc(n_of(0.18), 0.001, 0.05) * 0.8


def step_gravel(s):
    r = rng(s)
    grains = place(0.14, [(r.uniform(0, 0.06), bandpass(noise(0.012, s + i), 1200, 6000) * env_perc(n_of(0.012), 0.0005, 0.005) * 0.4) for i in range(9)])
    body = lowpass(noise(0.08, s + 30, "pink"), 500) * env_perc(n_of(0.08), 0.002, 0.025) * 0.6
    return grains + place(0.14, [(0, body)])


# --- Voices: one syllable each; pitch varies per character at runtime ------------------------

def formant_voice(f0, formants, d=0.075, breath=0.05, seed=0, shape="saw"):
    src = saw(f0, d, 30) if shape == "saw" else (square(f0, d, 12) if shape == "square" else tri(f0, d))
    out = np.zeros(n_of(d))
    for (f, q, g) in formants:
        out += resonator(src, f, q) * g
    out += bandpass(noise(d, seed), 1500, 6000) * breath
    return fade(out * env_adsr(n_of(d), 0.006, 0.02, 0.8, 0.025), 0.002, 0.01)


def voices():
    return {
        "voice_brass_muffled": lowpass(formant_voice(118, [(420, 6, 1.0), (900, 8, 0.4)], 0.08, 0.02, 1), 1400),
        "voice_pluck_clock": fm(midi_hz(69), 2.0, 2.5, 0.06, 40) * env_perc(n_of(0.06), 0.001, 0.025) + seg(highpass(noise(0.004, 2), 4000) * 0.15, 0.06),
        "voice_glass_bow": sine(760 * (1 + 0.012 * np.sin(2 * np.pi * 9 * t_axis(0.09))), 0.09) * env_adsr(n_of(0.09), 0.015, 0.02, 0.8, 0.03) * 0.8,
        "voice_reed_warm": lowpass(formant_voice(196, [(650, 7, 1.0), (1100, 9, 0.5)], 0.075, 0.04, 3, "square"), 2400),
        "voice_stone_marimba": (sine(150, 0.12) + 0.4 * sine(150 * 3.9, 0.12) * np.exp(-t_axis(0.12) * 40)) * env_perc(n_of(0.12), 0.002, 0.05),
        "voice_player": formant_voice(220, [(560, 8, 1.0), (1300, 10, 0.35)], 0.07, 0.03, 5, "tri"),
    }


SFX = {
    "ui_tick": (ui_tick, 1), "ui_move": (ui_move, 1), "ui_select": (ui_select, 1), "ui_open": (ui_open, 1),
    "ui_close": (ui_close, 1), "ui_error": (ui_error, 1), "chime": (chime, 1), "notice": (notice, 1),
    "pickup": (pickup, 3), "salvage": (salvage, 3), "well_crank": (well_crank, 3), "water_fill": (water_fill, 2),
    "water_pour": (water_pour, 2), "mine": (mine, 4), "till": (till, 3), "plant": (plant, 2), "harvest": (harvest, 3),
    "repair": (repair, 2), "pipe_lay": (pipe_lay, 3), "wire_lay": (wire_lay, 2), "build": (build, 2), "craft": (craft, 2),
    "winch": (winch, 1), "cable_snap": (cable_snap, 1), "fall": (fall, 1), "travel": (travel, 1),
    "valve_turn": (valve_turn, 1), "knock_323": (knock_323, 1), "reveal": (reveal, 1),
    "cut_open": (cut_open, 1), "cut_close": (cut_close, 1),
    "lift": (lift, 1), "thud": (thud, 1), "knock_single": (knock_single, 3), "heart_breath": (heart_breath, 1),
    "step_soft": (step_soft, 4), "step_stone": (step_stone, 4), "step_wood": (step_wood, 4), "step_gravel": (step_gravel, 4),
}


def main():
    count = 0
    for name, (fn, variants) in SFX.items():
        for v in range(variants):
            x = fn(100 + v * 17 + len(name))
            x = normalize(x, 0.8 if not name.startswith(("ui_", "step_")) else 0.6)
            path = os.path.join(OUT, f"{name}_{v + 1}.ogg" if variants > 1 else f"{name}.ogg")
            write_ogg(path, fade(x, 0.0, 0.01) if x.ndim == 1 else x, quality=4)
            count += 1
    for name, x in voices().items():
        write_ogg(os.path.join(OUT, name + ".ogg"), normalize(x, 0.7), quality=4)
        count += 1
    print(f"sfx: {count} files")


if __name__ == "__main__":
    main()
