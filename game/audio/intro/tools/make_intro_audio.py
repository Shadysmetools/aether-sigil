"""Synthesises the two intro sounds for Aether Sigil. Original work, no samples.

    python make_intro_audio.py            (writes next to this script's parent folder)

Outputs (16-bit PCM, 44.1 kHz, peak-normalised to -3 dBFS):
  smetools_sting.wav  ~1.9 s stereo  shimmer swell + bell-like chime (chime lands at 0.85 s)
  title_riser.wav     ~2.8 s mono    gentle swell + low chime (chime lands at 1.70 s)

Only numpy + the standard library. Deterministic (fixed seed), so re-running gives
byte-identical files.
"""
import os
import wave

import numpy as np

SR = 44100
PEAK = 10 ** (-3.0 / 20.0)  # -3 dBFS
OUT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = np.random.default_rng(20261021)


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def hz(note):
    """MIDI note number -> Hz."""
    return 440.0 * 2 ** ((note - 69) / 12.0)


def comb(x, delay_s, g):
    """y[n] = x[n] + g*y[n-D], vectorised in blocks of D samples."""
    d = max(1, int(delay_s * SR))
    y = np.copy(x)
    for start in range(d, len(x), d):
        end = min(start + d, len(x))
        y[start:end] += g * y[start - d:end - d]
    return y


def allpass(x, delay_s, g):
    """Schroeder all-pass: y[n] = -g*x[n] + x[n-D] + g*y[n-D]."""
    d = max(1, int(delay_s * SR))
    y = -g * x
    y[d:] += x[:-d]
    for start in range(d, len(x), d):
        end = min(start + d, len(x))
        y[start:end] += g * y[start - d:end - d]
    return y


def reverb(x, wet=0.28, spread=0.0, room=0.80):
    """Light Schroeder reverb: 4 parallel combs into 2 series all-passes."""
    k = 1.0 + spread
    acc = np.zeros_like(x)
    for dly in (0.0297, 0.0371, 0.0411, 0.0437):
        acc += comb(x, dly * k, room)
    acc /= 4.0
    acc = allpass(acc, 0.0050 * k, 0.7)
    acc = allpass(acc, 0.0017 * k, 0.7)
    return (1.0 - wet) * x + wet * acc


def bell(t, f0, start, decay=1.6, amp=1.0):
    """Inharmonic struck-bell partials with a soft 4 ms attack."""
    ratios = (0.56, 0.92, 1.19, 1.71, 2.00, 2.74, 3.00, 3.76, 4.07)
    amps = (0.35, 0.55, 1.00, 0.55, 0.45, 0.30, 0.22, 0.14, 0.10)
    tt = t - start
    on = tt >= 0
    out = np.zeros_like(t)
    for r, a in zip(ratios, amps):
        env = np.exp(-tt[on] * r / decay) * (1 - np.exp(-tt[on] / 0.004))
        out[on] += a * env * np.sin(2 * np.pi * f0 * r * tt[on] + rng.uniform(0, 6.28))
    return amp * out


def shimmer(t, notes, peak_at, rise_pow=2.4, decay=0.9, sparkle=True):
    """Cluster of high sine partials that swells to peak_at, each with its own tremolo."""
    out = np.zeros_like(t)
    for n in notes:
        for det in (-0.004, 0.0, 0.0045):
            f = hz(n) * (1 + det)
            vib = 0.002 * np.sin(2 * np.pi * rng.uniform(4, 6) * t)
            phase = 2 * np.pi * np.cumsum(f * (1 + vib)) / SR
            trem = 1.0 - (0.55 * (0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(7, 15) * t + rng.uniform(0, 6.28))) if sparkle else 0)
            out += trem * np.sin(phase + rng.uniform(0, 6.28)) / (1 + 0.15 * (n - notes[0]))
    rise = np.clip(t / peak_at, 0, 1) ** rise_pow
    fall = np.where(t > peak_at, np.exp(-(t - peak_at) / decay), 1.0)
    return out * rise * fall


def fade_tail(x, sec=0.18):
    n = int(sec * SR)
    x[-n:] *= np.cos(np.linspace(0, np.pi / 2, n)) ** 2
    return x


def normalise(x):
    return x * (PEAK / np.max(np.abs(x)))


def write_wav(name, chans):
    data = np.stack(chans, axis=-1) if len(chans) > 1 else chans[0][:, None]
    pcm = np.clip(np.round(data * 32767), -32768, 32767).astype("<i2")
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(pcm.shape[1])
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("%-20s %5.2f s  %d ch  %6d bytes" % (name, len(pcm) / SR, pcm.shape[1], os.path.getsize(path)))


def make_sting():
    t = t_axis(1.9)
    chime_at = 0.85
    # E major add9 shimmer, high register (E6 G#6 B6 F#7 E7 G#7)
    sh = shimmer(t, [88, 92, 95, 102, 100, 104], peak_at=chime_at, decay=0.55) * 0.10
    ch = bell(t, hz(76), chime_at, decay=1.4, amp=0.55)          # E5 bell
    ch += bell(t, hz(83), chime_at + 0.012, decay=1.1, amp=0.22)  # B5 sympathetic
    dry = sh + ch
    left = reverb(dry, wet=0.30, spread=0.0)
    right = reverb(dry, wet=0.30, spread=0.037)
    peak = max(np.max(np.abs(left)), np.max(np.abs(right)))
    left, right = fade_tail(left * PEAK / peak), fade_tail(right * PEAK / peak)
    write_wav("smetools_sting.wav", [left, right])


def make_riser():
    t = t_axis(2.8)
    chime_at = 1.70
    # low A-minor-add9 pad swelling in, then releasing after the chime
    pad = np.zeros_like(t)
    for n, a in ((45, 1.0), (52, 0.7), (57, 0.55), (59, 0.35), (64, 0.3)):
        pad += a * np.sin(2 * np.pi * hz(n) * t + rng.uniform(0, 6.28))
        pad += 0.3 * a * np.sin(2 * np.pi * hz(n) * 2.003 * t)
    swell = np.clip(t / chime_at, 0, 1) ** 2.2
    release = np.where(t > chime_at, np.exp(-(t - chime_at) / 0.45), 1.0)
    pad *= swell * release * 0.12
    # rising airy shimmer that glides up a fifth into the chime
    glide = 1 + 0.5 * np.clip(t / chime_at, 0, 1) ** 3
    air = np.zeros_like(t)
    for n in (81, 88, 93):
        air += np.sin(2 * np.pi * np.cumsum(hz(n) * glide) / SR + rng.uniform(0, 6.28))
    air *= (np.clip(t / chime_at, 0, 1) ** 3) * np.where(t > chime_at, np.exp(-(t - chime_at) / 0.2), 1.0) * 0.05
    ch = bell(t, hz(57), chime_at, decay=2.2, amp=0.8) + bell(t, hz(64), chime_at + 0.02, decay=1.8, amp=0.3)
    mix = reverb(pad + air + ch, wet=0.32, room=0.82)
    write_wav("title_riser.wav", [fade_tail(normalise(mix), 0.3)])


if __name__ == "__main__":
    make_sting()
    make_riser()
