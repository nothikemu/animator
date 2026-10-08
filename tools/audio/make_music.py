"""Bellows' adaptive score. Each cue is a set of synchronized, seamlessly looping stems of
identical length; the game fades stems in and out by context (src/autoload/audio.gd CUES).
All melodies, progressions and instruments are original and synthesized here.
    python3 tools/audio/make_music.py
"""
import os
import sys

import numpy as np
from scipy import signal

sys.path.insert(0, os.path.dirname(__file__))
from dsp import (SR, sine, saw, square, tri, fm, noise, env_adsr, env_perc, lowpass, highpass, bandpass,  # noqa: E402
                 resonator, saturate, reverb_ir, pan, mix_into, write_ogg, t_axis, rng, midi_hz)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "music")

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def note_midi(name):
    """'A4', 'Bb3', 'C#5' -> MIDI number."""
    letter = name[0]
    i = 1
    acc = 0
    while i < len(name) and name[i] in "#b":
        acc += 1 if name[i] == "#" else -1
        i += 1
    octave = int(name[i:])
    return 12 * (octave + 1) + NOTE[letter] + acc


def parse(score, expect_beats=None):
    """'r:1 A4:1 C5:2 | ...' -> [(beat, dur, midi)]. Bars ('|') are only for reading."""
    out = []
    beat = 0.0
    for tok in score.replace("|", " ").split():
        n, d = tok.split(":")
        d = float(d)
        if n != "r":
            out.append((beat, d, note_midi(n)))
        beat += d
    if expect_beats is not None and abs(beat - expect_beats) > 1e-6:
        raise ValueError(f"score has {beat} beats, expected {expect_beats}: {score[:40]}...")
    return out


# --- Instruments (mono, return array of the note's full sounding length) --------------------

def inst_pad(m, d, v, seed):
    f = midi_hz(m)
    dur = d + 1.6
    x = (saw(f * 1.004, dur, 18) + saw(f * 0.996, dur, 18) + 0.6 * tri(f * 0.5, dur)) / 2.6
    x = lowpass(x, 900 + 300 * v, 2)
    return x * env_adsr(int(dur * SR), 0.9, 0.6, 0.75, 1.5) * v


def inst_pluck(m, d, v, seed):
    f = midi_hz(m)
    dur = max(d, 0.5) + 0.4
    x = fm(f, 1.0, 2.2, dur, 9) * 0.7 + sine(f * 2, dur) * 0.15 * np.exp(-t_axis(dur) * 6)
    return x * env_perc(int(dur * SR), 0.003, 0.32) * v


def inst_flute(m, d, v, seed):
    f = midi_hz(m)
    dur = d + 0.35
    t = t_axis(dur)
    vib = 1 + 0.005 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.25) / 0.3, 0, 1)
    x = sine(f * vib, dur) * 0.8 + tri(f, dur) * 0.15
    x += bandpass(noise(dur, seed), f * 0.8, min(f * 3.0, 16000)) * 0.06
    return x * env_adsr(int(dur * SR), 0.07, 0.12, 0.72, 0.3) * v


def inst_brass(m, d, v, seed):
    f = midi_hz(m)
    dur = d + 0.4
    n = int(dur * SR)
    x = saw(f, dur, 20) * 0.7 + saw(f * 1.003, dur, 20) * 0.3
    # Brightness follows the swell: dark when soft, open at the peak.
    e = env_adsr(n, 0.12, 0.2, 0.8, 0.35)
    lo = lowpass(x, 500)
    hi = lowpass(x, 2200)
    return (lo * (1 - e * 0.6) + hi * e * 0.6) * e * v * 0.8


def inst_bell(m, d, v, seed):
    f = midi_hz(m)
    dur = 3.2
    x = fm(f, 3.5, 1.8, dur, 2.2) * 0.6 + sine(f * 2.0, dur) * 0.12 * np.exp(-t_axis(dur) * 3)
    return x * env_perc(int(dur * SR), 0.002, 1.1) * v


def inst_drone(m, d, v, seed):
    f = midi_hz(m)
    dur = d + 2.0
    t = t_axis(dur)
    x = saw(f, dur, 14) * 0.5 + saw(f * 1.5, dur, 10) * 0.25 + sine(f * 0.5, dur) * 0.4
    # Slow breathing filter, block-processed.
    out = np.zeros_like(x)
    block = 2048
    zi = None
    for i in range(0, len(x), block):
        c = 260 + 220 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.05 * (i / SR) + seed))
        b, a = signal.butter(2, c / (SR / 2), "low")
        if zi is None:
            zi = signal.lfilter_zi(b, a) * 0
        seg, zi = signal.lfilter(b, a, x[i:i + block], zi=zi)
        out[i:i + block] = seg
    return out * env_adsr(len(out), 2.0, 0.5, 0.9, 2.0) * v


def inst_bass(m, d, v, seed):
    f = midi_hz(m)
    dur = d + 0.15
    n = int(dur * SR)
    x = saw(f, dur, 12) * 0.6 + square(f, dur, 6) * 0.25 + sine(f, dur) * 0.5
    e = env_perc(n, 0.004, 0.22)
    x = lowpass(x, 220 + 900 * 0.5, 2) * 0.6 + lowpass(x, 1400) * e * 0.4
    return saturate(x * env_adsr(n, 0.004, 0.08, 0.7, 0.08) * v * 1.2, 1.5)


def inst_metal(m, d, v, seed):
    f = midi_hz(m)
    dur = 0.35
    x = fm(f, 1.414, 2.6, dur, 18)
    return x * env_perc(int(dur * SR), 0.001, 0.08) * v


def inst_kick(m, d, v, seed):
    dur = 0.35
    t = t_axis(dur)
    x = sine(55 + 90 * np.exp(-t * 28), dur)
    return x * env_perc(int(dur * SR), 0.001, 0.12) * v


def inst_clank(m, d, v, seed):
    dur = 0.4
    exc = noise(0.006, seed) * np.hanning(int(0.006 * SR))
    exc = np.pad(exc, (0, int(dur * SR) - len(exc)))
    out = sum(resonator(exc, 520 * r, 80) / (1 + k) for k, r in enumerate([1.0, 2.71, 5.2]))
    return out * env_perc(int(dur * SR), 0.0005, 0.12) * v * 6


def inst_tick(m, d, v, seed):
    dur = 0.03
    return highpass(noise(dur, seed), 5000) * env_perc(int(dur * SR), 0.0003, 0.008) * v


def inst_alarm(m, d, v, seed):
    f = midi_hz(m)
    dur = d
    t = t_axis(dur)
    x = lowpass(square(f, dur, 8), 1800) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * t))
    return x * env_adsr(int(dur * SR), 0.02, 0.05, 0.8, 0.1) * v


def inst_knock(m, d, v, seed):
    dur = 0.9
    exc = noise(0.004, seed) * np.hanning(int(0.004 * SR))
    exc = np.pad(exc, (0, int(dur * SR) - len(exc)))
    out = sum(resonator(exc, 300 * r, 70) / (1 + k) for k, r in enumerate([1.0, 2.76, 5.4]))
    out = lowpass(out, 1800)
    return out * env_perc(int(dur * SR), 0.0005, 0.25) * v * 7


# --- Rendering ---------------------------------------------------------------------------------

class Cue:
    def __init__(self, name, bpm, bars, beats_per_bar=4):
        self.name = name
        self.bpm = bpm
        self.beats = bars * beats_per_bar
        self.spb = 60.0 / bpm
        self.n = int(round(self.beats * self.spb * SR))
        self.stems = {}

    def stem(self, stem, events, inst, vel=0.7, pan_pos=0.0, rev=0.3, rev_len=2.6, seed=1, humanize=0.0):
        buf = np.zeros((self.n, 2))
        r = rng(seed)
        for i, (beat, dur, m) in enumerate(events):
            v = vel * (1 + r.uniform(-humanize, humanize)) if humanize else vel
            x = inst(m, dur * self.spb, v, seed + i)
            at = int(round((beat * self.spb + (r.uniform(0, 0.012) if humanize else 0.0)) * SR))
            p = pan_pos if not isinstance(pan_pos, tuple) else r.uniform(*pan_pos)
            mix_into(buf, pan(x, p), at % self.n)
        if rev > 0:
            irs = reverb_ir(rev_len, 3200, seed + 100)
            wet_l = signal.fftconvolve(buf[:, 0] + buf[:, 1], irs[0]) * 0.5
            wet_r = signal.fftconvolve(buf[:, 0] + buf[:, 1], irs[1]) * 0.5
            wet = np.zeros((self.n, 2))
            mix_into(wet, np.stack([wet_l, wet_r], axis=1), 0)   # tail wraps: seamless loop
            buf = buf * (1 - rev) + wet * rev
        self.stems[stem] = self.stems.get(stem, 0) + buf

    def write(self, quality=3):
        total = sum(self.stems.values())
        peak = np.max(np.abs(total)) + 1e-9
        g = 0.88 / peak
        for name, buf in self.stems.items():
            write_ogg(os.path.join(OUT, f"{self.name}_{name}.ogg"), buf * g, quality=quality)
        return self.n / SR


def chords(prog, beats_each):
    """[[midi...], ...] -> events, each chord held `beats_each`."""
    ev = []
    for i, ch in enumerate(prog):
        for m in ch:
            ev.append((i * beats_each, beats_each, m))
    return ev


def arpeggio(prog, beats_each, step, pattern, octave_up=12, start=0.0):
    ev = []
    for i, ch in enumerate(prog):
        n_steps = int(beats_each / step)
        for k in range(n_steps):
            idx = pattern[k % len(pattern)]
            m = ch[idx % len(ch)] + (octave_up if idx >= len(ch) else 0)
            ev.append((start + i * beats_each + k * step, step, m + octave_up * 0))
    return ev


# --- The score ---------------------------------------------------------------------------------

DM9 = [50, 57, 60, 64, 65]
BBMAJ7 = [46, 53, 57, 62, 65]
F_A = [45, 53, 60, 64, 69]
C69 = [48, 55, 57, 62, 64]
GM9 = [43, 50, 53, 57, 58]
A7SUS = [45, 52, 55, 62, 64]
WICK_PROG = [DM9, BBMAJ7, F_A, C69, DM9, GM9, BBMAJ7, A7SUS]

WICK_MELODY = (
    "r:1 A4:1 C5:1 D5:1 | E5:2 D5:1 C5:1 | D5:3 A4:1 | F4:2 G4:2 | "
    "A4:1 G4:1 F4:1 E4:1 | F4:2 C5:2 | D5:1 C5:1 A4:1 G4:1 | G4:4 | "
    "r:1 A4:1 C5:1 D5:1 | F5:2 E5:1 D5:1 | D5:2 Bb4:1 A4:1 | G4:3 r:1 | "
    "F4:1 G4:1 A4:1 Bb4:1 | D5:2 C5:2 | A4:2 G4:1 F4:1 | E4:3 r:1"
)
WICK_COUNTER = "F3:4 E3:4 | D3:8 | C3:4 E3:4 | G3:8 | F3:4 A3:4 | Bb3:4 A3:4 | F3:8 | E3:4 C#4:4"


def cue_wick():
    c = Cue("wick", 84, 16)
    c.stem("pad", chords(WICK_PROG, 8), inst_pad, 0.32, (-0.3, 0.3), 0.35, seed=3)
    c.stem("melody", parse(WICK_MELODY, 64), inst_flute, 0.55, 0.1, 0.32, seed=5, humanize=0.08)
    c.stem("counter", parse(WICK_COUNTER.replace("|", ""), 64), inst_brass, 0.3, -0.35, 0.3, seed=7)
    pulse = []
    for i, ch in enumerate(WICK_PROG):
        tones = sorted(ch)[1:]
        pat = [0, 2, 1, 3, 2, 1, 3, 2]
        for k in range(16):
            pulse.append((i * 8 + k * 0.5, 0.5, tones[pat[k % 8] % len(tones)] + 12))
    c.stem("pulse", pulse, inst_pluck, 0.28, (-0.5, 0.5), 0.25, seed=9, humanize=0.15)
    return c


HUSH_PROG = [[41, 53, 57, 60, 64, 71], [45, 52, 55, 60, 64], [38, 50, 57, 60, 64], [36, 52, 55, 59, 64], [40, 52, 55, 59, 62], [43, 50, 57, 59, 62]]
HUSH_MELODY = "r:2 C5:2 | B4:2 A4:2 | E5:4 | r:2 D5:1 C5:1 | A4:4 | G4:2 A4:2 | B4:3 C5:1 | E5:4 | D5:2 C5:2 | A4:4 | G4:2 E4:2 | F4:4"


def cue_hush():
    c = Cue("hush", 66, 12)
    c.stem("pad", chords(HUSH_PROG, 8), inst_pad, 0.3, (-0.4, 0.4), 0.45, 3.2, seed=13)
    c.stem("melody", parse(HUSH_MELODY, 48), inst_flute, 0.42, -0.1, 0.45, 3.2, seed=15, humanize=0.08)
    r = rng(17)
    scale = [76, 77, 79, 81, 83, 84, 86, 88]
    bells = [(b, 1, int(r.choice(scale))) for b in np.arange(0, 48, 2.0) + 0.0 if r.random() < 0.55]
    c.stem("glass", bells, inst_bell, 0.22, (-0.7, 0.7), 0.5, 3.6, seed=19)
    return c


def cue_menu():
    c = Cue("menu", 70, 16)
    c.stem("pad", chords(WICK_PROG, 8), inst_pad, 0.3, (-0.4, 0.4), 0.45, 3.4, seed=23)
    mel = parse(WICK_MELODY, 64)
    sparse = [e for i, e in enumerate(mel) if e[1] >= 1.5 or i % 3 == 0]
    c.stem("melody", sparse, inst_flute, 0.45, 0.0, 0.45, 3.4, seed=25, humanize=0.06)
    r = rng(27)
    bells = [(b, 1, int(r.choice([74, 77, 81, 84, 86]))) for b in np.arange(0, 64, 4.0) + 3.0]
    c.stem("glass", bells, inst_bell, 0.2, (-0.6, 0.6), 0.5, 3.6, seed=29)
    return c


def cue_reach():
    c = Cue("reach", 72, 16)
    c.stem("drone", [(0, 64, 38), (0, 64, 45)], inst_drone, 0.35, 0.0, 0.4, 3.5, seed=31)
    r = rng(33)
    phryg = [74, 75, 77, 79, 81, 82, 84, 86]
    bells = []
    b = 1.0
    while b < 64:
        bells.append((b, 1, int(r.choice(phryg))))
        b += float(r.choice([3.0, 4.0, 5.0, 6.0]))
    c.stem("glass", bells, inst_bell, 0.24, (-0.8, 0.8), 0.55, 4.0, seed=35)
    beats = []
    for bar in range(16):
        beats.append((bar * 4.0, 0.3, 36))
        beats.append((bar * 4.0 + 0.6, 0.3, 36))
    c.stem("pulse", beats, inst_kick, 0.5, 0.0, 0.3, 3.0, seed=37)
    return c


CUT_ROOTS = [38, 34, 36, 33]
CUT_ARP = [[62, 65, 69, 72], [58, 62, 65, 69], [60, 64, 67, 70], [57, 61, 64, 67]]


def cue_cut():
    c = Cue("cut", 96, 16)
    bass = []
    for bar in range(16):
        root = CUT_ROOTS[(bar // 2) % 4]
        for b, oct_ in [(0, 0), (0.75, 0), (1.5, 12), (2.5, 0), (3.0, 0), (3.5, 12)]:
            bass.append((bar * 4 + b, 0.45, root + oct_))
    c.stem("bass", bass, inst_bass, 0.26, 0.0, 0.12, 1.6, seed=41)
    arp = []
    pat = [0, 2, 1, 3, 2, 1, 0, 3, 1, 2, 0, 3, 2, 3, 1, 2]
    for bar in range(16):
        tones = CUT_ARP[(bar // 2) % 4]
        for k in range(16):
            arp.append((bar * 4 + k * 0.25, 0.25, tones[pat[k] % 4]))
    c.stem("ostinato", arp, inst_metal, 0.34, (-0.6, 0.6), 0.25, 2.0, seed=43, humanize=0.2)
    perc = []
    for bar in range(16):
        perc.append((bar * 4.0, 0.3, 0))
        perc.append((bar * 4.0 + 2.0, 0.3, 0))
    c.stem("perc", perc, inst_kick, 0.55, 0.0, 0.15, 1.5, seed=45)
    clanks = [(bar * 4.0 + b, 0.2, 0) for bar in range(16) for b in (1.0, 3.0)]
    c.stem("perc", clanks, inst_clank, 0.45, 0.25, 0.3, 1.8, seed=47)
    ticks = [(k * 0.25, 0.1, 0) for k in range(64 * 4) if k % 2 == 1]
    c.stem("perc", ticks, inst_tick, 0.25, (-0.4, 0.4), 0.1, 1.0, seed=49, humanize=0.3)
    alarm = [(b, 0.95, 74 if int(b) % 2 == 0 else 80) for b in np.arange(0, 64, 1.0)]
    c.stem("alarm", alarm, inst_alarm, 0.16, 0.0, 0.3, 2.0, seed=51)
    return c


D_MAJ = [50, 57, 62, 66, 69]
G_D = [43, 55, 59, 62, 67]
BM7 = [47, 54, 57, 62, 66]
A_SUS = [45, 52, 57, 62, 64]
A_MAJ = [45, 52, 57, 61, 64]
EM7 = [40, 52, 55, 59, 62]
STATION_PROG = [D_MAJ, G_D, BM7, A_SUS, D_MAJ, EM7, G_D, A_MAJ]


def cue_station():
    c = Cue("station", 70, 16)
    c.stem("pad", chords(STATION_PROG, 8), inst_pad, 0.28, (-0.4, 0.4), 0.4, 3.0, seed=61)
    c.stem("brass", chords([[m for m in ch if m < 64] for ch in STATION_PROG], 8), inst_brass, 0.3, (-0.3, 0.3), 0.35, 3.0, seed=63)
    major = WICK_MELODY.replace("F4", "F#4").replace("F5", "F#5").replace("C5", "C#5").replace("Bb4", "B4")
    c.stem("melody", parse(major, 64), inst_flute, 0.5, 0.0, 0.35, 3.0, seed=65, humanize=0.06)
    knocks = []
    for bar in (0, 8):
        for b in (0.0, 0.5, 1.0, 2.0, 2.5, 3.5, 4.0, 4.5):
            knocks.append((bar * 4 + 2.0 + b, 0.3, 0))
    c.stem("knock", knocks, inst_knock, 1.4, 0.15, 0.55, 3.5, seed=67)
    return c


# --- Below the lift --------------------------------------------------------------------------

DEEP_PROG = [[45, 52, 57, 59, 64], [41, 48, 53, 57, 64], [43, 50, 55, 57, 62], [40, 47, 55, 59, 62]]


def cue_deep():
    """The Lower Stations: low and patient, a pad that breathes, and the knock far away."""
    c = Cue("deep", 60, 16)
    c.stem("drone", [(0, 64, 33), (0, 64, 40)], inst_drone, 0.32, 0.0, 0.45, 4.0, seed=71)
    c.stem("breath", chords(DEEP_PROG * 2, 8), inst_pad, 0.22, (-0.5, 0.5), 0.55, 4.2, seed=73)
    r = rng(75)
    aeolian = [69, 71, 72, 74, 76, 77, 79, 81]
    bells = []
    b = 2.0
    while b < 64:
        bells.append((b, 1, int(r.choice(aeolian))))
        b += float(r.choice([4.0, 5.0, 6.0, 7.0]))
    c.stem("glass", bells, inst_bell, 0.2, (-0.8, 0.8), 0.6, 4.4, seed=77)
    knocks = [(bar * 4 + 1.0 + k, 0.3, 0) for bar in (4, 12) for k in (0.0, 0.5, 1.0, 2.0, 2.5, 3.5, 4.0, 4.5)]
    c.stem("knock", knocks, inst_knock, 0.7, -0.2, 0.7, 4.5, seed=79)
    return c


C_MAJ = [48, 55, 60, 64, 67]
SALLOW_PROG = [D_MAJ, C_MAJ, G_D, D_MAJ, BM7, G_D, EM7, A_SUS]
SALLOW_MELODY = (
    "D5:2 E5:1 F#5:1 | A5:3 G5:1 | F#5:2 E5:1 D5:1 | C5:4 | "
    "B4:2 C5:1 D5:1 | E5:2 D5:2 | B4:1 A4:1 G4:1 A4:1 | A4:4 | "
    "D5:2 E5:1 F#5:1 | A5:2 B5:2 | A5:1 G5:1 F#5:1 E5:1 | D5:3 r:1 | "
    "C5:2 B4:1 A4:1 | G4:2 A4:2 | B4:1 C5:1 E5:1 D5:1 | D5:4"
)


def cue_sallow():
    """Sallow: candlelight, twelve people, a tune somebody taught a child. Mixolydian, warm, tired."""
    c = Cue("sallow", 76, 16)
    c.stem("pad", chords(SALLOW_PROG, 8), inst_pad, 0.24, (-0.4, 0.4), 0.4, 3.0, seed=81)
    c.stem("pluck", arpeggio(SALLOW_PROG, 8, 1.0, [0, 2, 3, 1, 4, 2, 3, 1]), inst_pluck, 0.3, (-0.4, 0.4), 0.3, 2.4, seed=83, humanize=0.1)
    c.stem("melody", parse(SALLOW_MELODY, 64), inst_flute, 0.48, 0.1, 0.35, 3.0, seed=85, humanize=0.08)
    knocks = [(60 + k, 0.3, 0) for k in (0.0, 0.5, 1.0, 2.0, 2.5)]
    c.stem("knock", knocks, inst_knock, 0.9, 0.2, 0.5, 3.0, seed=87)
    return c


DMAJ9 = [38, 50, 57, 62, 64, 66]
BM11 = [35, 47, 54, 57, 64]
GMAJ7 = [31, 43, 55, 59, 62, 66]
ASUS4 = [33, 45, 52, 57, 62]
HEART_PROG = [DMAJ9, BM11, GMAJ7, ASUS4]
HEART_BRASS = "D4:4 F#4:4 | A4:4 B4:4 | A4:8 | G4:4 F#4:4 | E4:4 F#4:4 | A4:8 | B4:4 A4:4 | D5:8"


def cue_heart():
    """The Heart: one enormous held breath, and, once it breathes again, the brass."""
    c = Cue("heart", 56, 16)
    c.stem("drone", [(0, 64, 26), (0, 64, 33)], inst_drone, 0.36, 0.0, 0.5, 5.0, seed=91)
    c.stem("breath", chords(HEART_PROG * 2, 8), inst_pad, 0.26, (-0.6, 0.6), 0.6, 5.0, seed=93)
    r = rng(95)
    penta = [74, 76, 78, 81, 83, 86]
    bells = [(b, 2, int(r.choice(penta))) for b in np.arange(1.0, 64.0, 4.0) if r.random() < 0.7]
    c.stem("glass", bells, inst_bell, 0.2, (-0.8, 0.8), 0.6, 5.0, seed=97)
    c.stem("brass", parse(HEART_BRASS, 64), inst_brass, 0.34, 0.0, 0.5, 4.5, seed=99)
    return c


def main():
    total = 0.0
    for make in [cue_menu, cue_wick, cue_hush, cue_reach, cue_cut, cue_station, cue_deep, cue_sallow, cue_heart]:
        c = make()
        secs = c.write()
        total += secs
        print(f"{c.name}: {len(c.stems)} stems x {secs:.1f}s")
    print(f"music: {total:.0f}s of loops")


if __name__ == "__main__":
    main()
