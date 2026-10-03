"""Small DSP toolkit for Bellows' generated audio. Everything is synthesized from scratch:
oscillators, envelopes, filters, noise, a convolution reverb built from shaped noise, and
an ffmpeg-backed Ogg Vorbis writer. Deterministic: every generator takes an explicit seed.
"""
import os
import subprocess
import tempfile
import wave

import numpy as np
from scipy import signal

SR = 44100


def rng(seed):
    return np.random.default_rng(seed)


def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def midi_hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


# --- Oscillators -------------------------------------------------------------------------------

def sine(freq, dur, phase=0.0):
    t = t_axis(dur)
    if np.ndim(freq):
        return np.sin(2 * np.pi * np.cumsum(freq) / SR + phase)
    return np.sin(2 * np.pi * freq * t + phase)


def saw(freq, dur, harmonics=24):
    """Band-limited sawtooth by additive synthesis (no aliasing in the pixel-quiet register)."""
    t = t_axis(dur)
    out = np.zeros_like(t)
    for k in range(1, harmonics + 1):
        if freq * k > SR * 0.45:
            break
        out += ((-1) ** (k + 1)) * np.sin(2 * np.pi * freq * k * t) / k
    return out * (2 / np.pi)


def square(freq, dur, harmonics=16):
    t = t_axis(dur)
    out = np.zeros_like(t)
    for k in range(1, 2 * harmonics, 2):
        if freq * k > SR * 0.45:
            break
        out += np.sin(2 * np.pi * freq * k * t) / k
    return out * (4 / np.pi)


def tri(freq, dur, harmonics=12):
    t = t_axis(dur)
    out = np.zeros_like(t)
    for i, k in enumerate(range(1, 2 * harmonics, 2)):
        if freq * k > SR * 0.45:
            break
        out += ((-1) ** i) * np.sin(2 * np.pi * freq * k * t) / (k * k)
    return out * (8 / np.pi ** 2)


def fm(carrier, ratio, index, dur, index_decay=4.0):
    """Two-operator FM; the index decays so bells and plucks brighten then mellow."""
    t = t_axis(dur)
    idx = index * np.exp(-t * index_decay)
    mod = np.sin(2 * np.pi * carrier * ratio * t) * idx
    return np.sin(2 * np.pi * carrier * t + mod)


def noise(dur, seed=0, color="white"):
    r = rng(seed)
    n = r.standard_normal(int(dur * SR))
    if color == "pink":
        b, a = [0.049922035, -0.095993537, 0.050612699, -0.004408786], [1, -2.494956002, 2.017265875, -0.522189400]
        n = signal.lfilter(b, a, n) * 3.0
    elif color == "brown":
        n = np.cumsum(n)
        n = n - signal.savgol_filter(n, 4001 if len(n) > 4001 else (len(n) // 2) * 2 - 1, 2) if len(n) > 7 else n
        n = n / (np.max(np.abs(n)) + 1e-9)
    return n


# --- Envelopes ---------------------------------------------------------------------------------

def env_adsr(n, a=0.01, d=0.1, s=0.7, r=0.2):
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    s_n = max(0, n - a_n - d_n - r_n)
    e = np.concatenate([
        np.linspace(0, 1, max(a_n, 1), endpoint=False),
        np.linspace(1, s, max(d_n, 1), endpoint=False),
        np.full(s_n, s),
        np.linspace(s, 0, max(r_n, 1)),
    ])
    if len(e) < n:
        e = np.pad(e, (0, n - len(e)))
    return e[:n]


def env_perc(n, attack=0.002, decay=0.3, curve=1.0):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    return a * np.exp(-t / max(decay, 1e-5) * curve)


def fade(x, fin=0.005, fout=0.02):
    x = x.copy()
    i, o = int(fin * SR), int(fout * SR)
    if i > 0:
        x[:i] *= np.linspace(0, 1, i)
    if o > 0 and o < len(x):
        x[-o:] *= np.linspace(1, 0, o)
    return x


# --- Filters -----------------------------------------------------------------------------------

def lowpass(x, cutoff, order=2):
    b, a = signal.butter(order, min(cutoff / (SR / 2), 0.99), "low")
    return signal.lfilter(b, a, x)


def highpass(x, cutoff, order=2):
    b, a = signal.butter(order, max(cutoff / (SR / 2), 0.0005), "high")
    return signal.lfilter(b, a, x)


def bandpass(x, lo, hi, order=2):
    b, a = signal.butter(order, [max(lo / (SR / 2), 0.0005), min(hi / (SR / 2), 0.99)], "band")
    return signal.lfilter(b, a, x)


def resonator(x, freq, q=30.0):
    """A ringing two-pole resonance (pipes, wood, glass)."""
    w = 2 * np.pi * freq / SR
    r = np.exp(-np.pi * freq / (q * SR))
    b = [1 - r]
    a = [1, -2 * r * np.cos(w), r * r]
    return signal.lfilter(b, a, x)


def sweep_lowpass(x, start, end, steps=64):
    """Time-varying low-pass by block processing (filter sweeps, wind gusts)."""
    out = np.zeros_like(x)
    block = max(1, len(x) // steps)
    zi = None
    for i in range(0, len(x), block):
        k = i / max(len(x) - 1, 1)
        c = start * (end / start) ** k
        b, a = signal.butter(2, min(c / (SR / 2), 0.99), "low")
        if zi is None:
            zi = signal.lfilter_zi(b, a) * 0
        seg, zi = signal.lfilter(b, a, x[i:i + block], zi=zi)
        out[i:i + block] = seg
    return out


def saturate(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


# --- Space -------------------------------------------------------------------------------------

_IR_CACHE = {}


def reverb_ir(length=2.4, damp=3000.0, seed=7, stereo=True):
    key = (length, damp, seed, stereo)
    if key in _IR_CACHE:
        return _IR_CACHE[key]
    r = rng(seed)
    n = int(length * SR)
    t = np.arange(n) / SR
    decay = np.exp(-t * 6.9 / length)
    chans = []
    for c in range(2 if stereo else 1):
        ir = r.standard_normal(n) * decay
        ir = lowpass(ir, damp, 1)
        ir[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))   # pre-delay softness
        ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
        chans.append(ir)
    _IR_CACHE[key] = chans
    return chans


def reverb(x, mix=0.3, length=2.4, damp=3000.0, seed=7):
    """Convolution reverb. Mono in -> stereo out (n, 2), tail included."""
    irs = reverb_ir(length, damp, seed)
    wet = [signal.fftconvolve(x, ir) for ir in irs]
    n = len(wet[0])
    dry = np.pad(x, (0, n - len(x)))
    return np.stack([dry * (1 - mix) + wet[0] * mix, dry * (1 - mix) + wet[1] * mix], axis=1)


def pan(x, p):
    """Mono -> stereo with equal-power pan, p in [-1, 1]."""
    a = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1)


def to_stereo(x):
    return x if x.ndim == 2 else np.stack([x, x], axis=1)


def mix_into(buf, x, at):
    """Adds x (mono or stereo) into buf (stereo) at sample offset `at`, wrapping for loops."""
    x = to_stereo(x)
    n = len(buf)
    end = at + len(x)
    if end <= n:
        buf[at:end] += x
    else:
        first = n - at
        buf[at:] += x[:first]
        rest = x[first:]
        while len(rest) > 0:
            k = min(len(rest), n)
            buf[:k] += rest[:k]
            rest = rest[k:]


def normalize(x, peak=0.89):
    m = np.max(np.abs(x)) + 1e-9
    return x * (peak / m)


# --- Output ------------------------------------------------------------------------------------

def write_ogg(path, x, quality=4, peak=None):
    """Writes float audio (mono or stereo) as Ogg Vorbis via ffmpeg."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if peak is not None:
        x = normalize(x, peak)
    x = np.clip(x, -1.0, 1.0)
    pcm = (x * 32767).astype(np.int16)
    ch = 1 if pcm.ndim == 1 else pcm.shape[1]
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tmp = f.name
    with wave.open(tmp, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(quality), path], check=True)
    os.unlink(tmp)
