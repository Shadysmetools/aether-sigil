"""Small DSP kit shared by make_sfx.py. numpy + scipy only. Everything is mono float64 at SR
unless a function says otherwise; stereo arrays are shape (2, n)."""
import subprocess

import numpy as np
from scipy import signal

SR = 48000


def secs(n):
    return np.arange(int(SR * n)) / SR


def hz(midi):
    return 440.0 * 2 ** ((np.asarray(midi, dtype=float) - 69) / 12.0)


def fit(x, n):
    """Pad with zeros / cut to n samples."""
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def mix(*parts):
    """Sum mono parts of different lengths, each given as (signal, start_sec, gain) or signal."""
    items = []
    for p in parts:
        if isinstance(p, tuple):
            s = p[0]
            at = p[1] if len(p) > 1 else 0.0
            g = p[2] if len(p) > 2 else 1.0
        else:
            s, at, g = p, 0.0, 1.0
        items.append((np.asarray(s, dtype=float), int(at * SR), g))
    n = max(len(s) + o for s, o, _ in items)
    out = np.zeros(n)
    for s, o, g in items:
        out[o:o + len(s)] += g * s
    return out


# ---------- envelopes ----------

def env_exp(n_sec, tau, attack=0.002):
    t = secs(n_sec)
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    return a * np.exp(-t / tau)


def env_ar(n_sec, attack, release, curve=2.0):
    t = secs(n_sec)
    up = np.clip(t / max(attack, 1e-5), 0, 1) ** curve
    down = np.clip((n_sec - t) / max(release, 1e-5), 0, 1) ** curve
    return up * down


def fade(x, fin=0.002, fout=0.01):
    x = np.array(x, dtype=float)
    a, b = int(fin * SR), int(fout * SR)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


# ---------- sources ----------

def noise(n_sec, rng):
    return rng.standard_normal(int(SR * n_sec))


def brown(n_sec, rng):
    w = np.cumsum(rng.standard_normal(int(SR * n_sec)))
    w = signal.sosfilt(signal.butter(1, 20, "hp", fs=SR, output="sos"), w)
    return w / (np.max(np.abs(w)) + 1e-9)


def osc(freq, n_sec=None, kind="sin", phase=0.0):
    """freq may be a scalar or a per-sample array (pitch contour)."""
    if np.isscalar(freq):
        freq = np.full(int(SR * n_sec), float(freq))
    ph = 2 * np.pi * np.cumsum(freq) / SR + phase
    if kind == "sin":
        return np.sin(ph)
    if kind == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if kind == "saw":  # band-limited-ish additive saw (12 partials, alias-safe below ~1.8 kHz)
        out = np.zeros_like(ph)
        for k in range(1, 13):
            mask = (freq * k) < SR * 0.45
            out += mask * np.sin(k * ph) / k
        return out * 0.6
    if kind == "sq":
        out = np.zeros_like(ph)
        for k in range(1, 24, 2):
            mask = (freq * k) < SR * 0.45
            out += mask * np.sin(k * ph) / k
        return out * 0.8
    raise ValueError(kind)


def fm(fc, ratio, index, n_sec, index_env=None):
    t = secs(n_sec)
    i = index if index_env is None else index * index_env
    return np.sin(2 * np.pi * fc * t + i * np.sin(2 * np.pi * fc * ratio * t))


def bell(f, n_sec, tau=0.8, rng=None, partials=(1, 2.76, 5.4, 8.93), amps=(1, .5, .3, .15)):
    t = secs(n_sec)
    out = np.zeros_like(t)
    for p, a in zip(partials, amps):
        out += a * np.sin(2 * np.pi * f * p * t) * np.exp(-t * p ** 0.6 / tau)
    tail = np.clip((n_sec - t) / (0.25 * n_sec), 0, 1)  # never cut a ringing partial (click)
    return out * np.clip(t / 0.001, 0, 1) * np.sin(tail * np.pi / 2)


def chirp(f0, f1, n_sec, kind="sin", curve="exp"):
    n = int(SR * n_sec)
    if curve == "exp":
        f = f0 * (f1 / f0) ** np.linspace(0, 1, n)
    else:
        f = np.linspace(f0, f1, n)
    return osc(f, kind=kind)


# ---------- filters ----------

def _sos(kind, f, order=2):
    if isinstance(f, (list, tuple)):
        f = [min(max(v, 10), SR * 0.49) for v in f]
    else:
        f = min(max(f, 10), SR * 0.49)
    return signal.butter(order, f, kind, fs=SR, output="sos")


def lp(x, f, order=2):
    return signal.sosfilt(_sos("lowpass", f, order), x)


def hp(x, f, order=2):
    return signal.sosfilt(_sos("highpass", f, order), x)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("bandpass", [lo, hi], order), x)


def sweep(x, centers, width_oct=0.6, gain_curve=None):
    """Time-varying band-pass done in the STFT domain. `centers` = per-frame centre Hz
    (array resampled to the frame count) or a (start, end) pair (log sweep)."""
    nper = 1024
    f, tt, Z = signal.stft(x, SR, nperseg=nper, noverlap=nper * 3 // 4)
    nfr = Z.shape[1]
    if isinstance(centers, tuple):
        c = centers[0] * (centers[1] / centers[0]) ** np.linspace(0, 1, nfr)
    else:
        c = np.interp(np.linspace(0, 1, nfr), np.linspace(0, 1, len(centers)), centers)
    lf = np.log2(np.maximum(f, 1))[:, None]
    mask = np.exp(-0.5 * ((lf - np.log2(c)[None, :]) / width_oct) ** 2)
    _, y = signal.istft(Z * mask, SR, nperseg=nper, noverlap=nper * 3 // 4)
    return fit(y, len(x))


def formant(x, formants, n_frames_profile=None):
    """Vowel-ish filter: formants = list of per-time (f, bw_oct, gain) tracks, each a tuple of
    arrays or scalars. Implemented as a sum of STFT-domain band masks."""
    nper = 1024
    f, tt, Z = signal.stft(x, SR, nperseg=nper, noverlap=nper * 3 // 4)
    nfr = Z.shape[1]
    lf = np.log2(np.maximum(f, 1))[:, None]
    mask = np.zeros(Z.shape)
    for fc, bw, g in formants:
        fc = np.interp(np.linspace(0, 1, nfr), np.linspace(0, 1, np.size(fc)), np.atleast_1d(fc))
        mask += g * np.exp(-0.5 * ((lf - np.log2(fc)[None, :]) / bw) ** 2)
    _, y = signal.istft(Z * mask, SR, nperseg=nper, noverlap=nper * 3 // 4)
    return fit(y, len(x))


def drive(x, amount=2.0):
    return np.tanh(x * amount) / np.tanh(amount)


# ---------- texture ----------

def grains(n_sec, rate, rng, dur=(0.002, 0.012), band=(1500, 9000), density_curve=None,
           pitched=None, amp_jitter=0.6):
    """Scatter short noise (or sine if `pitched`=(lo,hi) Hz) grains. `density_curve` (array 0..1
    over the length) modulates the rate; used for crackle, debris, rain, sparkles."""
    n = int(SR * n_sec)
    out = np.zeros(n)
    total = int(rate * n_sec * 1.5) + 1
    times = np.sort(rng.uniform(0, n_sec, total))
    if density_curve is not None:
        dc = np.interp(times / n_sec, np.linspace(0, 1, len(density_curve)), density_curve)
        times = times[rng.uniform(0, 1, len(times)) < dc]
    else:
        times = times[: int(rate * n_sec)]
    for t0 in times:
        d = rng.uniform(*dur)
        m = int(d * SR)
        if m < 8:
            continue
        w = np.hanning(m) * np.exp(-np.linspace(0, 4, m))
        if pitched:
            fr = rng.uniform(*pitched)
            g = np.sin(2 * np.pi * fr * np.arange(m) / SR)
        else:
            g = rng.standard_normal(m)
        g *= w * (1 - amp_jitter * rng.uniform())
        s = int(t0 * SR)
        e = min(n, s + m)
        out[s:e] += g[: e - s]
    if not pitched and band:
        out = bp(out, *band)
    return out


# ---------- space ----------

_ir_cache = {}


def reverb_ir(seconds, rng_seed=7, damp=6000, predelay=0.012, stereo=True):
    key = (seconds, rng_seed, damp, predelay, stereo)
    if key in _ir_cache:
        return _ir_cache[key]
    r = np.random.default_rng(rng_seed)
    n = int(SR * seconds)
    t = np.arange(n) / SR
    chans = []
    for c in range(2 if stereo else 1):
        x = r.standard_normal(n) * np.exp(-6.9 * t / seconds)  # -60 dB at `seconds`
        # darker as it decays: split into a bright head and dark tail
        dark = lp(x, damp * 0.35)
        bright = lp(x, damp)
        k = np.exp(-t / (seconds * 0.25))
        x = bright * k + dark * (1 - k)
        x = np.concatenate([np.zeros(int(predelay * SR)), x])
        chans.append(x / np.sqrt(np.sum(x ** 2)))
    ir = np.array(chans)
    _ir_cache[key] = ir
    return ir


def reverb(x, wet=0.3, seconds=1.6, damp=6000, predelay=0.012):
    """Mono in -> stereo out (2, n). Dry stays centred."""
    ir = reverb_ir(seconds, damp=damp, predelay=predelay)
    n = len(x) + ir.shape[1]
    out = np.zeros((2, n))
    for c in range(2):
        w = signal.fftconvolve(x, ir[c])
        out[c, :len(w)] += wet * w
        out[c, :len(x)] += (1 - wet * 0.5) * x
    return out


def to_mono(st):
    return st.mean(axis=0) if st.ndim == 2 else st


def pan(x, p):
    """p in -1..1 -> stereo, equal power."""
    a = (p + 1) * np.pi / 4
    return np.array([np.cos(a) * x, np.sin(a) * x])


def stereo_mix(*parts):
    """parts: (stereo_or_mono, start_sec, gain)."""
    items = []
    for s, at, g in parts:
        s = np.asarray(s, dtype=float)
        if s.ndim == 1:
            s = np.array([s, s])
        items.append((s, int(at * SR), g))
    n = max(s.shape[1] + o for s, o, _ in items)
    out = np.zeros((2, n))
    for s, o, g in items:
        out[:, o:o + s.shape[1]] += g * s
    return out


def resample_pitch(x, ratio):
    """Pitch/speed change by `ratio` (>1 = higher & shorter)."""
    n = int(len(x) / ratio)
    return np.interp(np.arange(n) * ratio, np.arange(len(x)), x)


# ---------- io ----------

def decode(path, channels=1, sr=SR):
    """Any audio file -> float array via ffmpeg, resampled to `sr`. Mono (n,) or stereo (2, n)."""
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", str(channels), "-ar", str(sr), "-"],
        check=True, capture_output=True).stdout
    a = np.frombuffer(raw, dtype=np.float32).astype(float)
    return a if channels == 1 else a.reshape(-1, channels).T


def encode_ogg(x, path, quality=5, sr=SR):
    x = np.asarray(x, dtype=np.float32)
    ch = 1 if x.ndim == 1 else x.shape[0]
    data = x if x.ndim == 1 else x.T.copy()
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(sr), "-ac", str(ch), "-i", "-",
         "-c:a", "libvorbis", "-q:a", str(quality), "-map_metadata", "-1", "-fflags", "+bitexact",
         "-flags:a", "+bitexact", str(path)],
        input=np.ascontiguousarray(data).tobytes(), check=True)
