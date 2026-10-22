"""Aether Sigil per-level music builder.

Pipeline (each step is a sub-command; `all` runs them in order):
  master  <work>   source audio (ACE-Step renders or curated CC0 files, listed in
                   tools/music_sources.json) -> seamless loop -> HPSS split into a harmonic "base"
                   stem and a percussive "heat" stem -> -16 LUFS / -1 dBTP -> OGG under
                   game/audio/music/towers/<Txx>/ (+ final/, stings).
  map              writes game/data/music_map.json: every bible stage id -> take + per-stage mix
                   (pitch_scale, low-pass, low-shelf, heat baseline) derived from chamber number
                   and opponent_style.
  metrics <work>   renders every stage's runtime mix offline (same chain AudioManager applies)
                   and measures tempo / spectral centroid / chroma / MFCC; writes
                   tools/music_metrics.json (+ loop seam + loudness checks).

usage: python music_build.py {master,map,metrics,all} [work_dir]
Needs numpy, scipy, soundfile, librosa, pyloudnorm, ffmpeg on PATH.
"""
import json
import math
import subprocess
import sys
from pathlib import Path

import numpy as np
from scipy import signal

HERE = Path(__file__).resolve().parent
GAME = HERE.parent.parent
MUSIC = GAME / "audio" / "music"
BIBLE = GAME / "data" / "AETHER_SIGIL_MASTER_GAME_BIBLE.json"
MAP_PATH = GAME / "data" / "music_map.json"
SOURCES = HERE / "music_sources.json"
METRICS = HERE / "music_metrics.json"
SR = 48000
TARGET_LUFS = -16.0
CEIL_DBTP = -1.0
LOOP_MIN, LOOP_MAX = 56.0, 100.0   # seconds kept per loop (size budget)
TAKES = ("a", "b", "c")
SKIP_EXISTING = bool(__import__("os").environ.get("MUSIC_SKIP_EXISTING"))             # battle takes: chambers 1-3, 4-6, 7-9

# Per-tower identity. `prompt` is what ACE-Step gets (original styles only - no artist, composer,
# game or franchise names). `root` = tonal centre hint used when choosing between takes.
TOWERS = {
    "01": {"slug": "verdant", "prompt": "pastoral fantasy orchestral, wooden flute, celtic harp, plucked strings, hand drums, warm forest strings"},
    "02": {"slug": "ember", "prompt": "heroic fantasy orchestral, taiko drums, bold brass, driving low strings, fiery, anvil hits"},
    "03": {"slug": "tideglass", "prompt": "flowing fantasy orchestral, harp arpeggios, marimba, glass bells, legato strings, gentle water percussion"},
    "04": {"slug": "frost", "prompt": "crystalline winter orchestral, celesta, glockenspiel, airy synth pad, sparse pizzicato strings, cold"},
    "05": {"slug": "iron", "prompt": "industrial fantasy orchestral, clockwork percussion, metallic hits, staccato strings, low brass, steampunk"},
    "06": {"slug": "storm", "prompt": "soaring fantasy orchestral, fast string ostinato, tin whistle, timpani rolls, wind, thunder drums"},
    "07": {"slug": "obsidian", "prompt": "dark fantasy orchestral, minor key, pipe organ, tremolo strings, low drones, ominous percussion"},
    "08": {"slug": "archive", "prompt": "ancient ruins fantasy, reed flute, oud, frame drums, mysterious strings, desert modal scale"},
    "09": {"slug": "astral", "prompt": "cosmic fantasy orchestral, synth arpeggios, ethereal pads, shimmering strings, deep space"},
    "10": {"slug": "crystal", "prompt": "shimmering crystal fantasy, music box, bells, harp, glass harmonica, bright strings"},
    "11": {"slug": "rift", "prompt": "hybrid electronic orchestral, glitch percussion, pulsing synth bass, unstable phasing strings"},
    "12": {"slug": "sunforge", "prompt": "grand epic full orchestra, triumphant brass, timpani, massive drums, golden majestic strings"},
}
ROLE_WORDS = {
    "explore": "calm exploration theme, gentle, medium-slow tempo, loopable, instrumental, no vocals",
    "battle": "battle theme, energetic, rhythmic, loopable, instrumental, no vocals",
    "boss": "boss battle theme, intense, heavy, climactic, loopable, instrumental, no vocals",
    "final": "final boss battle, colossal, relentless, apocalyptic, loopable, instrumental, no vocals",
}

# opponent_style -> mix colour. tempo = pitch_scale multiplier (tape speed: tempo and key move
# together), heat = heat-stem baseline offset (0..1), shelf = low-shelf dB at 180 Hz,
# lp = low-pass multiplier on the chamber cutoff.
STYLE = {
    "rush attacker":            {"tempo": 1.045, "heat": 0.25, "shelf": 0.0, "lp": 1.0},
    "counter-attacker":         {"tempo": 1.020, "heat": 0.15, "shelf": 1.0, "lp": 0.95},
    "mobility specialist":      {"tempo": 1.035, "heat": 0.05, "shelf": -1.0, "lp": 1.0},
    "long-range sniper":        {"tempo": 1.000, "heat": -0.05, "shelf": -1.5, "lp": 1.0},
    "trap engineer":            {"tempo": 0.985, "heat": 0.0, "shelf": 0.5, "lp": 0.8},
    "summoner":                 {"tempo": 1.000, "heat": 0.1, "shelf": 1.5, "lp": 0.9},
    "status-effect strategist": {"tempo": 0.975, "heat": -0.1, "shelf": 0.0, "lp": 0.7},
    "resource thief":           {"tempo": 1.015, "heat": 0.0, "shelf": -0.5, "lp": 0.85},
    "terrain controller":       {"tempo": 0.965, "heat": -0.05, "shelf": 2.0, "lp": 0.9},
    "defensive fortress":       {"tempo": 0.950, "heat": -0.15, "shelf": 2.5, "lp": 0.75},
}


def bible():
    return json.loads(BIBLE.read_text(encoding="utf-8"))


def track_ids():
    """Every long track the game ships, in build order."""
    out = []
    for t in TOWERS:
        out.append(f"T{t}_explore")
        out += [f"T{t}_battle_{k}" for k in TAKES]
        out.append(f"T{t}_boss")
    out.append("final_boss")
    return out


def track_files(tid):
    """res:// paths for a track id: explore = one stereo file, battle/boss = [base, heat]."""
    if tid == "final_boss":
        d = "res://audio/music/final/final_boss"
    else:
        tw, role = tid.split("_", 1)
        d = f"res://audio/music/towers/{tw}/{role}"
    if tid.endswith("_explore"):
        return [d + ".ogg"]
    return [d + "_base.ogg", d + "_heat.ogg"]


def sting_files(tower):
    return {"victory": f"res://audio/music/towers/T{tower}/victory.ogg",
            "defeat": f"res://audio/music/towers/T{tower}/defeat.ogg"}


def res_to_path(res):
    return GAME / res.replace("res://", "")


# ------------------------------------------------------------------ audio io

def load(path, sr=SR):
    """Any audio file -> float32 (2, n) at sr via ffmpeg."""
    cmd = ["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "2", "-ar", str(sr), "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).T.astype(np.float64)


def save_ogg(x, path, quality=4, mono=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    x = np.atleast_2d(x)
    if mono and x.shape[0] == 2:
        x = x.mean(axis=0, keepdims=True)
    data = np.clip(x.T, -1, 1).astype(np.float32).tobytes()
    cmd = ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ac", str(x.shape[0]), "-ar", str(SR), "-i", "-",
           "-c:a", "libvorbis", "-q:a", str(quality), str(path)]
    subprocess.run(cmd, input=data, check=True)


# ------------------------------------------------------------------ measurement

def lufs(x):
    import pyloudnorm as pyln
    return pyln.Meter(SR).integrated_loudness(np.atleast_2d(x).T)


def true_peak_db(x):
    up = signal.resample_poly(np.atleast_2d(x), 4, 1, axis=-1)
    return 20 * math.log10(max(np.max(np.abs(up)), 1e-9))


def seam_metrics(x):
    """Loop seam check on a looped (2, n) signal: sample jump at the wrap vs the typical
    sample-to-sample step, and spectral flux at the wrap vs the median flux (a click shows up as
    a flux spike; >3x median is flagged)."""
    m = x.mean(axis=0)
    d = np.abs(np.diff(m))
    jump = abs(m[0] - m[-1])
    wrapped = np.concatenate([m[-SR:], m[:SR]])
    f, t, Z = signal.stft(wrapped, SR, nperseg=1024, noverlap=768)
    mag = np.abs(Z)
    flux = np.sqrt(np.sum(np.maximum(np.diff(mag, axis=1), 0) ** 2, axis=0))
    centre = np.argmin(np.abs(t[1:] - 1.0))
    win = flux[max(centre - 2, 0):centre + 3].max()
    return {"seam_jump": round(float(jump), 4), "p99_step": round(float(np.percentile(d, 99)), 4),
            "seam_flux_ratio": round(float(win / (np.median(flux) + 1e-9)), 2)}


# ------------------------------------------------------------------ loop finding

def find_loop(x, lo=LOOP_MIN, hi=LOOP_MAX):
    """Returns (a, b, fade) sample indices of the best bar-aligned loop region in x."""
    import librosa
    mono = librosa.resample(x.mean(axis=0), orig_sr=SR, target_sr=22050)
    tempo, beats = librosa.beat.beat_track(y=mono, sr=22050, units="frames", hop_length=512)
    tempo = float(np.atleast_1d(tempo)[0])
    chroma = librosa.feature.chroma_cqt(y=mono, sr=22050, hop_length=512)
    mfcc = librosa.feature.mfcc(y=mono, sr=22050, hop_length=512, n_mfcc=13)
    rms = librosa.feature.rms(y=mono, hop_length=512)
    feat = np.vstack([chroma, mfcc[1:] / 40.0, rms * 8])
    bt = librosa.frames_to_time(beats, sr=22050, hop_length=512)
    dur = x.shape[1] / SR
    if len(beats) < 16:
        # no usable beat grid: loop the whole thing with a long crossfade
        fade = min(3.0, dur * 0.05)
        return int(fade * SR), x.shape[1], int(fade * SR), tempo
    spb = 60.0 / max(tempo, 40)
    fade_s = min(max(2 * spb, 0.5), 1.6)

    nb = len(beats)
    cs = np.concatenate([np.zeros((feat.shape[0], 1)), np.cumsum(feat, axis=1)], axis=1)

    def wins(n, shift=0):
        """mean feature over beats [i+shift, i+shift+n) for every beat i (unit-normalised)."""
        i0 = np.clip(np.arange(nb) + shift, 0, nb - 1)
        i1 = np.clip(i0 + n, 0, nb - 1)
        f0, f1 = beats[i0], np.maximum(beats[i1], beats[i0] + 1)
        w = (cs[:, f1] - cs[:, f0]) / (f1 - f0)
        return w.T, w[-1]

    W8, lvl = wins(8)
    P4, _ = wins(4, -4)
    n8 = W8 / (np.linalg.norm(W8, axis=1, keepdims=True) + 1e-9)
    n4 = P4 / (np.linalg.norm(P4, axis=1, keepdims=True) + 1e-9)
    S = n8 @ n8.T + 0.5 * (n4 @ n4.T)
    S -= 0.3 * np.abs(np.log((lvl[:, None] + 1e-3) / (lvl[None, :] + 1e-3)))
    L = bt[None, :] - bt[:, None]
    S += 0.002 * L
    ii, jj = np.meshgrid(np.arange(nb), np.arange(nb), indexing="ij")
    ok = ((L >= lo) & (L <= hi) & ((jj - ii) % 4 == 0) & (jj - ii >= 16) & (jj < nb - 8)
          & (bt[:, None] >= fade_s + 0.3) & (bt[:, None] <= dur * 0.5))
    best = None
    if ok.any():
        S[~ok] = -np.inf
        i, j = np.unravel_index(np.argmax(S), S.shape)
        best = (S[i, j], bt[i], bt[j])
    if best is None:
        fade = min(3.0, dur * 0.05)
        return int(fade * SR), x.shape[1], int(fade * SR), tempo
    return int(best[1] * SR), int(best[2] * SR), int(fade_s * SR), tempo


def make_loop(x, a, b, fade):
    """x[a:b] with its last `fade` samples equal-power cross-faded into x[a-fade:a], so the end
    flows into the start. Requires a >= fade."""
    fade = min(fade, a)
    y = x[:, a:b].copy()
    if fade > 0:
        t = np.linspace(0, 1, fade)
        fo, fi = np.cos(t * np.pi / 2), np.sin(t * np.pi / 2)
        y[:, -fade:] = x[:, b - fade:b] * fo + x[:, a - fade:a] * fi
    return y


def hpss_loop(y):
    """Harmonic/percussive split of a loop, computed on a circular pad so both stems still loop
    seamlessly. margin=1 masks sum to 1, so base + heat == y (before mono-folding the heat)."""
    import librosa
    pad = 2 * SR
    n = y.shape[1]
    tiled = np.concatenate([y[:, -pad:], y, y[:, :pad]], axis=1)
    # one soft mask from the mid channel (median filters are the slow part), applied to L and R
    D = [librosa.stft(tiled[c], n_fft=4096, hop_length=1024) for c in range(2)]
    mag = np.abs(D[0] + D[1]) / 2
    from scipy.ndimage import median_filter
    harm = median_filter(mag, size=(1, 17), mode="reflect")
    perc = median_filter(mag, size=(17, 1), mode="reflect")
    mask = harm ** 2 / (harm ** 2 + perc ** 2 + 1e-12)
    H = np.stack([librosa.istft(D[c] * mask, hop_length=1024, length=tiled.shape[1]) for c in range(2)])
    h = H[:, pad:pad + n]
    p = (y - h).mean(axis=0, keepdims=True).repeat(2, axis=0)   # heat stem ships mono
    return h, p


# ------------------------------------------------------------------ mastering

def limiter_gain(x, ceil_db, look=0.005, release=0.15, block=64):
    """Gain curve (n,) keeping the 4x-oversampled peak of x under ceil_db: look-ahead min filter
    (instant attack), one-pole release, computed per 64-sample block and interpolated."""
    from scipy.ndimage import minimum_filter1d
    n = x.shape[1]
    ceil = 10 ** (ceil_db / 20)
    pk = np.abs(signal.resample_poly(np.atleast_2d(x), 4, 1, axis=-1)).max(axis=0)[:4 * n].reshape(-1, 4).max(axis=1)
    nb = -(-n // block)
    pk = np.pad(pk, (0, nb * block - n)).reshape(nb, block).max(axis=1)
    need = np.minimum(1.0, ceil / np.maximum(pk, 1e-9))
    la = max(int(look * SR / block), 1)
    need = minimum_filter1d(need, size=2 * la + 1)
    rel = math.exp(-block / (release * SR))
    g = np.empty(nb)
    cur = 1.0
    for i in range(nb):
        cur = need[i] if need[i] < cur else need[i] + (cur - need[i]) * rel
        g[i] = cur
    g = minimum_filter1d(g, size=3)
    return np.interp(np.arange(n), np.arange(nb) * block + block / 2, g)


def master_pair(base, heat):
    """Gain both stems so the full mix sits at -16 LUFS integrated with true peak <= -1 dBTP;
    the same gain curve is applied to both stems so their sum is the mastered mix."""
    full = base + heat
    g = 10 ** ((TARGET_LUFS - lufs(full)) / 20)
    full_g = full * g
    curve = np.ones(full.shape[1])
    if true_peak_db(full_g) > CEIL_DBTP - 0.3:
        curve = limiter_gain(full_g, CEIL_DBTP - 0.6)
    return base * g * curve, heat * g * curve


# ------------------------------------------------------------------ stings

def reverb_tail(x, secs=2.2, seed=7):
    rng = np.random.default_rng(seed)
    n = int(secs * SR)
    ir = rng.standard_normal((2, n)) * np.exp(-np.arange(n) / (0.45 * SR))
    ir[:, :int(0.01 * SR)] *= np.linspace(0, 1, int(0.01 * SR))
    ir /= np.sqrt(np.sum(ir ** 2, axis=1, keepdims=True))
    wet = np.stack([signal.fftconvolve(x[c], ir[c]) for c in range(2)])
    dry = np.concatenate([x, np.zeros((2, n))], axis=1)
    m = min(dry.shape[1], wet.shape[1])
    return dry[:, :m] + 0.35 * wet[:, :m]


def make_sting(src, kind, seed):
    """Victory: the strongest 2-bar phrase of a battle take, bright, with a ring-out.
    Defeat: a slowed (-3 semitones), darkened 2-bar phrase of the explore theme, fading."""
    import librosa
    mono = librosa.resample(src.mean(axis=0), orig_sr=SR, target_sr=22050)
    tempo, beats = librosa.beat.beat_track(y=mono, sr=22050, hop_length=512)
    bt = librosa.frames_to_time(beats, sr=22050, hop_length=512)
    onset = librosa.onset.onset_strength(y=mono, sr=22050, hop_length=512)
    if len(bt) < 12:
        bt = np.arange(0, src.shape[1] / SR - 4, 0.5)
    cand = [i for i in range(len(bt) - 8) if bt[i] > 1.0]
    pick = max(cand, key=lambda i: onset[int(bt[i] * 22050 / 512)]) if cand else 0
    a = int(bt[pick] * SR)
    b = int(bt[min(pick + 8, len(bt) - 1)] * SR)
    b = min(max(b, a + int(3.0 * SR)), a + int(5.0 * SR), src.shape[1])
    seg = src[:, a:b].copy()
    if kind == "defeat":
        r = 2 ** (-3 / 12)
        seg = signal.resample(seg, int(seg.shape[1] / r), axis=1)
        sos = signal.butter(4, 1800, "lowpass", fs=SR, output="sos")
        seg = signal.sosfilt(sos, seg, axis=1)
    n = seg.shape[1]
    env = np.ones(n)
    fi = int(0.03 * SR)
    env[:fi] = np.linspace(0, 1, fi)
    fo = int((1.2 if kind == "victory" else 2.5) * SR)
    env[-fo:] *= np.linspace(1, 0, fo) ** 1.5
    seg = reverb_tail(seg * env, 2.0 if kind == "victory" else 2.8, seed)
    seg = seg[:, :int(np.max(np.nonzero(np.abs(seg).max(axis=0) > 1e-4)) + 1)]
    g = 10 ** ((TARGET_LUFS - lufs(seg)) / 20)
    seg = seg * g
    if true_peak_db(seg) > CEIL_DBTP:
        seg *= 10 ** ((CEIL_DBTP - 0.2 - true_peak_db(seg)) / 20)
    return seg


# ------------------------------------------------------------------ steps

def step_master(work):
    work = Path(work)
    src = json.loads(SOURCES.read_text(encoding="utf-8"))
    info = {}
    prev = json.loads((work / "master_info.json").read_text()) if (work / "master_info.json").exists() else {}
    for tid in track_ids():
        s = src["tracks"].get(tid)
        if not s:
            continue
        path = work / s["local"]
        if SKIP_EXISTING and all(res_to_path(f).exists() and res_to_path(f).stat().st_mtime > path.stat().st_mtime
                                 for f in track_files(tid)):
            info[tid] = prev.get(tid, {})
            continue
        x = load(path)
        if "trim" in s:
            x = x[:, int(s["trim"][0] * SR):int(s["trim"][1] * SR)]
        a, b, fade, tempo = find_loop(x)
        y = make_loop(x, a, b, fade)
        files = track_files(tid)
        if len(files) == 1:
            g = 10 ** ((TARGET_LUFS - lufs(y)) / 20)
            y = y * g
            if true_peak_db(y) > CEIL_DBTP - 0.3:
                y = y * limiter_gain(y, CEIL_DBTP - 0.6)
            stems = [y]
        else:
            stems = list(master_pair(*hpss_loop(y)))
        # Vorbis shifts loudness / peaks a little: measure the decoded files, correct once.
        for attempt in range(3):
            save_ogg(stems[0], res_to_path(files[0]), quality=3)
            if len(stems) > 1:
                save_ogg(stems[1], res_to_path(files[1]), quality=1, mono=True)
            dec = decoded_mix(files)
            err = TARGET_LUFS - lufs(dec)
            over = true_peak_db(dec) - (CEIL_DBTP - 0.1)
            corr = min(err, -over) if over > 0 else err
            if abs(err) <= 0.15 and over <= 0:
                break
            stems = [s_ * 10 ** (corr / 20) for s_ in stems]
        full = dec
        info[tid] = {"source": s["local"], "loop_start": round(a / SR, 3), "loop_end": round(b / SR, 3),
                     "seconds": round(y.shape[1] / SR, 2), "fade": round(fade / SR, 3),
                     "tempo": round(tempo, 1)}
        print(f"  {tid}: {info[tid]['seconds']} s loop @ {info[tid]['tempo']} bpm")
    for t in TOWERS:
        ex, ba = f"T{t}_explore", f"T{t}_battle_a"
        if ex not in src["tracks"] or ba not in src["tracks"]:
            continue
        files = sting_files(t)
        vic = make_sting(load(work / src["tracks"][ba]["local"]), "victory", int(t))
        dfe = make_sting(load(work / src["tracks"][ex]["local"]), "defeat", int(t) + 50)
        save_ogg(vic, res_to_path(files["victory"]), quality=3)
        save_ogg(dfe, res_to_path(files["defeat"]), quality=3)
        info[f"T{t}_victory"] = {"seconds": round(vic.shape[1] / SR, 2)}
        info[f"T{t}_defeat"] = {"seconds": round(dfe.shape[1] / SR, 2)}
    (work / "master_info.json").write_text(json.dumps(info, indent=1))


def decoded_mix(files):
    """Decoded OGG(s) of a track summed as the game plays them at intensity 1."""
    xs = [load(res_to_path(f)) for f in files]
    if len(xs) == 1:
        return xs[0]
    n = min(x.shape[1] for x in xs)
    return xs[0][:, :n] + xs[1][:, :n]


def stage_mix(tower, chamber, style):
    """Per-stage runtime mix. Chamber 1..9 raises intensity: the heat stem's baseline, the
    low-pass opens, tempo creeps up; opponent_style colours it (see STYLE)."""
    st = STYLE.get(style, {"tempo": 1.0, "heat": 0.0, "shelf": 0.0, "lp": 1.0})
    k = (chamber - 1) / 8.0                       # 0 .. 1 across L01..L09
    take = TAKES[min((chamber - 1) // 3, 2)]
    pos = (chamber - 1) % 3                       # position inside the take's trio
    pitch = st["tempo"] * (1.0 + 0.012 * pos + 0.01 * k)
    heat = min(max(0.30 + 0.45 * k + st["heat"], 0.10), 0.90)
    cutoff = max((7500 + 12500 * k ** 0.8) * st["lp"], 5500)
    return {"take": take, "pitch_scale": round(pitch, 4), "heat": round(heat, 3),
            "lowpass_hz": int(min(cutoff, 20000)), "low_shelf_db": st["shelf"]}


def step_map():
    b = bible()
    towers = {}
    stages = {}
    for t in b["towers"]:
        tw = t["tower_id"]
        tracks = {f"explore": f"T{tw}_explore", "boss": f"T{tw}_boss"}
        for k in TAKES:
            tracks[f"battle_{k}"] = f"T{tw}_battle_{k}"
        towers[tw] = {"name": t["name"], "theme": t["theme"], "explore": f"T{tw}_explore",
                      "stings": sting_files(tw), "tracks": tracks}
        for lv in t["levels"]:
            sid = lv["stage_id"]
            chamber = int(sid.split("-L")[1])
            if chamber == 10:
                track = "final_boss" if tw == "12" else f"T{tw}_boss"
                mix = {"take": "boss", "pitch_scale": 1.0, "heat": 0.8 if tw != "12" else 0.9,
                       "lowpass_hz": 20000, "low_shelf_db": 1.0}
            else:
                mix = stage_mix(tw, chamber, lv.get("opponent_style", ""))
                track = f"T{tw}_battle_{mix['take']}"
            stages[sid] = {"tower": tw, "chamber": chamber, "track": track,
                           "opponent_style": lv.get("opponent_style", ""),
                           "intensity": mix["heat"], **{k: v for k, v in mix.items() if k not in ("take", "heat")}}
    tracks = {tid: {"files": track_files(tid), "layered": not tid.endswith("_explore")} for tid in track_ids()}
    out = {
        "_doc": "Generated by game/audio/tools/music_build.py map - do not hand-edit. stage -> track "
                "+ runtime mix applied by AudioManager.play_stage_music(): pitch_scale (tempo+key), "
                "lowpass_hz / low_shelf_db (per-player sub-bus), intensity = heat-stem baseline "
                "(0..1; set_music_intensity() raises it in battle).",
        "title": "title",
        "world_map": "title",
        "tracks": tracks,
        "towers": towers,
        "stages": stages,
    }
    MAP_PATH.write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"music_map: {len(stages)} stages, {len(towers)} towers, {len(tracks)} tracks")


# ------------------------------------------------------------------ metrics

def runtime_mix(base, heat, st, secs=40.0):
    """Offline copy of the AudioManager chain: base + heat*intensity -> pitch_scale (resample)
    -> low-shelf 180 Hz -> low-pass. Returns mono (n,) of `secs` output seconds."""
    heat = np.atleast_2d(heat)
    if heat.shape[0] == 1:
        heat = np.repeat(heat, 2, axis=0)
    n = min(base.shape[1], heat.shape[1])
    x = (base[:, :n] + heat[:, :n] * st["intensity"]).mean(axis=0)
    p = st["pitch_scale"]
    if abs(p - 1) > 1e-4:
        up, down = int(round(1000 / p)), 1000
        x = signal.resample_poly(x, up, down)
    if st.get("low_shelf_db"):
        x = x + (10 ** (st["low_shelf_db"] / 20) - 1) * signal.sosfilt(signal.butter(2, 180, "lowpass", fs=SR, output="sos"), x)
    if st["lowpass_hz"] < 19000:
        x = signal.sosfilt(signal.butter(2, st["lowpass_hz"], "lowpass", fs=SR, output="sos"), x)
    return x[:int(secs * SR)]


def features(x):
    import librosa
    y = librosa.resample(x, orig_sr=SR, target_sr=22050)
    tempo = float(np.atleast_1d(librosa.beat.beat_track(y=y, sr=22050)[0])[0])
    cent = float(librosa.feature.spectral_centroid(y=y, sr=22050).mean())
    chroma = librosa.feature.chroma_cqt(y=y, sr=22050).mean(axis=1)
    mfcc = librosa.feature.mfcc(y=y, sr=22050, n_mfcc=20)
    return {"tempo": tempo, "centroid": cent, "chroma": chroma / (chroma.sum() + 1e-9),
            "mfcc": mfcc.mean(axis=1), "mfcc_sd": mfcc.std(axis=1)}


def step_metrics(work=None):
    m = json.loads(MAP_PATH.read_text(encoding="utf-8"))
    feats = {}
    loops = {}
    by_track = {}
    for sid, st in m["stages"].items():
        by_track.setdefault(st["track"], []).append(sid)
    for tid in m["tracks"]:  # one decoded track in memory at a time (RAM is tight)
        files = m["tracks"][tid]["files"]
        xs = [load(res_to_path(f)).astype(np.float32) for f in files]
        full = decoded_mix(files).astype(np.float32)
        loops[tid] = {**seam_metrics(full), "lufs": round(lufs(full), 2), "dbtp": round(true_peak_db(full), 2),
                      "seconds": round(full.shape[1] / SR, 1)}
        del full
        for sid in by_track.get(tid, []):
            feats[sid] = features(runtime_mix(xs[0], xs[1][:1], m["stages"][sid]))
        del xs
    sids = sorted(feats)
    vec = np.array([np.concatenate([feats[s]["mfcc"], feats[s]["mfcc_sd"], feats[s]["chroma"] * 50,
                                    [feats[s]["centroid"] / 100.0]]) for s in sids])
    mu, sd = vec.mean(axis=0), vec.std(axis=0) + 1e-9
    z = (vec - mu) / sd
    D = np.sqrt(((z[:, None, :] - z[None, :, :]) ** 2).sum(-1)) / math.sqrt(z.shape[1])
    np.fill_diagonal(D, np.inf)
    per_tower = {}
    for t in sorted({s[1:3] for s in sids}):
        idx = [i for i, s in enumerate(sids) if s[1:3] == t]
        sub = D[np.ix_(idx, idx)]
        i, j = np.unravel_index(np.argmin(sub), sub.shape)
        tempos = [feats[sids[k]]["tempo"] for k in idx]
        cents = [feats[sids[k]]["centroid"] for k in idx]
        per_tower[t] = {"min_pair": [sids[idx[i]], sids[idx[j]]], "min_dist": round(float(sub[i, j]), 3),
                        "median_dist": round(float(np.median(sub[np.isfinite(sub)])), 3),
                        "tempo_range": [round(min(tempos), 1), round(max(tempos), 1)],
                        "centroid_range_hz": [int(min(cents)), int(max(cents))]}
    stings = {}
    for t, tw in m["towers"].items():
        for k, f in tw["stings"].items():
            p = res_to_path(f)
            if p.exists():
                x = load(p)
                stings[f"T{t}_{k}"] = {"seconds": round(x.shape[1] / SR, 2), "dbtp": round(true_peak_db(x), 2),
                                       "lufs": round(lufs(x), 2)}
    allfin = D[np.isfinite(D)]
    out = {"stages": len(sids), "distance": "RMS of z-scored [MFCC mean+sd, chroma, centroid] over 40 s of each stage's runtime mix",
           "global_min": round(float(allfin.min()), 3), "global_median": round(float(np.median(allfin)), 3),
           "per_tower": per_tower, "loops": loops, "stings": stings,
           "stage_features": {s: {"tempo": round(feats[s]["tempo"], 1), "centroid": int(feats[s]["centroid"])} for s in sids}}
    METRICS.write_text(json.dumps(out, indent=1))
    print(json.dumps({k: out[k] for k in ("global_min", "global_median")}))
    for t, v in per_tower.items():
        print(t, v)


def step_sources(work):
    """Writes music_sources.json from the ACE-Step renders in <work>/gen (music_acestep.py)."""
    work = Path(work)
    tracks = {}
    for tid in track_ids():
        meta = work / "gen" / f"{tid}.json"
        if (work / "gen" / f"{tid}.wav").exists() and meta.exists():
            j = json.loads(meta.read_text())
            tracks[tid] = {"origin": "ace-step", "local": f"gen/{tid}.wav", "model": j["model"],
                           "seed": j["seed"], "prompt": j["prompt"], "lyrics": j["lyrics"],
                           "duration": j["duration"], "licence": "Apache-2.0 model; no third-party audio"}
    out = {"note": "Original score rendered locally with ACE-Step v1-3.5B by tools/music_acestep.py "
                   "(instrumental prompts describing original styles; no artist, composer, game or franchise names).",
           "checked": "2026-10-21", "tracks": tracks}
    SOURCES.write_text(json.dumps(out, indent=1) + "\n", encoding="utf-8")
    print("music_sources:", len(tracks), "of", len(track_ids()))


def step_credits():
    """Rewrites the per-level music section of audio/CREDITS.md from music_sources.json."""
    src = json.loads(SOURCES.read_text(encoding="utf-8"))
    info = json.loads(METRICS.read_text()) if METRICS.exists() else {}
    rows = []
    for tid in track_ids():
        s_ = src["tracks"].get(tid)
        if not s_:
            continue
        files = ", ".join("`" + f.replace("res://audio/music/", "") + "`" for f in track_files(tid))
        trim = f" (section {s_['trim'][0]:.0f}-{s_['trim'][1]:.0f} s)" if "trim" in s_ else ""
        if s_.get("origin") == "ace-step":
            rows.append(f"| `{tid}` | ACE-Step v1-3.5B render, seed {s_.get('seed')}{trim} | - | - | Apache-2.0 model; no third-party audio | {files} |")
        else:
            rows.append(f"| `{tid}` | {s_['title']}{trim} | {s_['author']} | {s_['page']} | {s_['licence']} | {files} |")
    lp = info.get("loops", {})
    meas = [f"| `{k}` | {v['seconds']} | {v['lufs']} | {v['dbtp']} | {v['seam_jump']} / {v['p99_step']} | {v['seam_flux_ratio']} |"
            for k, v in sorted(lp.items())]
    body = "\n".join([
        "<!-- music_build:begin (generated by tools/music_build.py credits - do not hand-edit) -->",
        "## Per-level music (12 towers x explore / 3 battle takes / boss, final boss, stings)",
        "",
        src.get("note", ""),
        "",
        "Generator: ACE-Step v1-3.5B - code https://github.com/ace-step/ACE-Step (LICENSE: Apache-2.0), weights "
        "https://huggingface.co/ACE-Step/ACE-Step-v1-3.5B (model card `license: apache-2.0`), both checked "
        + src.get("checked", "") + ". Any row whose origin is a CC0 page (fallback path, `tools/music_curate.py`) "
        "lists that page; each such page showed CC0 as its sole licence when catalogued.",
        "",
        "Processing (`tools/music_build.py master`): bar-aligned loop region + equal-power cross-fade at the seam, "
        "harmonic/percussive split (battle + boss -> `_base` / `_heat` stems, heat stem mono), -16 LUFS integrated / "
        "-1 dBTP (gain + look-ahead limiter, re-measured on the decoded OGG). Stings (`towers/Txx/victory.ogg`, "
        "`defeat.ogg`) are cut from the tower's battle take a (victory) / explore theme slowed -3 st (defeat), "
        "with a synthetic ring-out tail.",
        "",
        "| Track | Source | Author | Page | Licence | Files |",
        "|---|---|---|---|---|---|",
        *rows,
        "",
        "### Loop measurements (decoded OGG, full mix)",
        "",
        "| Track | Seconds | LUFS | dBTP | seam jump / p99 step | seam flux / median |",
        "|---|---|---|---|---|---|",
        *meas,
        "<!-- music_build:end -->",
    ])
    cp = GAME / "audio" / "CREDITS.md"
    txt = cp.read_text(encoding="utf-8")
    if "<!-- music_build:begin" in txt:
        a_ = txt.index("<!-- music_build:begin")
        b_ = txt.index("<!-- music_build:end -->") + len("<!-- music_build:end -->")
        txt = txt[:a_] + body + txt[b_:]
    else:
        txt = txt.rstrip("\n") + "\n\n" + body + "\n"
    cp.write_text(txt, encoding="utf-8")
    print("CREDITS.md music section:", len(rows), "tracks")


if __name__ == "__main__":
    cmd = sys.argv[1]
    work = sys.argv[2] if len(sys.argv) > 2 else None
    if cmd == "sources":
        step_sources(work)
    if cmd in ("master", "all"):
        step_master(work)
    if cmd in ("map", "all"):
        step_map()
    if cmd in ("metrics", "all"):
        step_metrics(work)
    if cmd in ("credits", "all"):
        step_credits()
