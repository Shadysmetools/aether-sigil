"""Builds every SFX, ambience loop and music track for Aether Sigil, plus the runtime registry
(game/audio/audio_registry.json), HOOKS.md and CREDITS.md. Deterministic: per-sound seeds come
from the sound id, so a rerun reproduces the same audio.

    python -I game/audio/tools/make_sfx.py                 # everything
    python -I game/audio/tools/make_sfx.py --only cast_fire,amb_wind
    python -I game/audio/tools/make_sfx.py --skip-music

Sources, in order of preference:
  (a) CC0 packs - Kenney.nl (fetched by URL into game/audio/_downloads/kenney/, .gdignore'd) and
      OpenGameArt CC0-only music (game/audio/_downloads/oga/). Downloads are treated as data only:
      they are decoded by ffmpeg, never executed or imported.
  (b) our own synthesis (dsp.py: layered noise / FM / additive / granular / convolution reverb).
  (c) ElevenLabs sound generation can later replace any id: see eleven_sfx.py.

Mastering (every file): trim leading/trailing silence (< -60 dBFS) -> loudness gain -> true-peak
limiter (4x oversampled, ceiling -1 dBTP) -> fade-out -> Ogg Vorbis (libvorbis q5, 48 kHz).
  SFX / stings : max momentary loudness (400 ms K-weighted window, BS.1770 via pyloudnorm,
                 clip zero-padded to >= 400 ms) = -16 LUFS. Integrated loudness is meaningless on
                 clips under ~0.4 s because of the gating, hence momentary-max for one-shots.
  UI           : same method, -20 LUFS (UI sits under the battle).
  Ambience     : integrated -26 LUFS, seamless loop (tail cross-faded into head).
  Music        : integrated -16 LUFS, gain only (no limiter, so the composer's loop seam stays
                 bit-continuous), 44.1 kHz kept, peak checked <= -1 dBTP.
Needs: numpy, scipy, pyloudnorm, ffmpeg (with libvorbis) on PATH.
"""
import argparse
import json
import os
import pathlib
import subprocess
import sys
import urllib.request
import zipfile
import zlib

import numpy as np
import pyloudnorm
from scipy import signal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsp  # noqa: E402
from dsp import SR, secs, mix, fade, noise, brown, osc, fm, bell, chirp, lp, hp, bp, sweep, \
    formant, drive, grains, reverb, stereo_mix, pan, resample_pitch, env_exp, env_ar, decode, \
    encode_ogg, hz  # noqa: E402

TOOLS = pathlib.Path(__file__).resolve().parent
AUDIO = TOOLS.parent                      # game/audio
SFX_DIR = AUDIO / "sfx"
AMB_DIR = AUDIO / "ambience"
MUS_DIR = AUDIO / "music"
DL = AUDIO / "_downloads"
KENNEY_DIR = DL / "kenney"
OGA_DIR = DL / "oga"
OVERRIDES = TOOLS / "overrides"           # <file name>.ogg here replaces that file's synthesis (eleven_sfx.py --apply)

KENNEY_PACKS = {  # pack -> zip URL (scraped from https://kenney.nl/assets/<pack>, 2026-10-21)
    "interface-sounds": "https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip",
    "impact-sounds": "https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip",
    "rpg-audio": "https://kenney.nl/media/pages/assets/rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip",
    "ui-audio": "https://kenney.nl/media/pages/assets/ui-audio/490d233f68-1677590494/kenney_ui-audio.zip",
    "music-jingles": "https://kenney.nl/media/pages/assets/music-jingles/f37e530b9e-1677590399/kenney_music-jingles.zip",
    "sci-fi-sounds": "https://kenney.nl/media/pages/assets/sci-fi-sounds/6b296f9ecf-1677589334/kenney_sci-fi-sounds.zip",
    "digital-audio": "https://kenney.nl/media/pages/assets/digital-audio/216eac4753-1677590265/kenney_digital-audio.zip",
}

# Music: every page below was checked on 2026-10-21 to list CC0 as its ONLY licence.
MUSIC = {
    "title": {
        "url": "https://opengameart.org/sites/default/files/magic_puzzle_title_bpm100_0.ogg",
        "page": "https://opengameart.org/content/magic-puzzle-title", "author": "MintoDog",
        "title": "Magic Puzzle Title (100 BPM, loopable)", "use": "title screen + world map",
    },
    "battle": {
        "url": "https://opengameart.org/sites/default/files/hope_orchestral_battle_music_bpm165_0.ogg",
        "page": "https://opengameart.org/content/hopeorchestral-battle-music", "author": "MintoDog",
        "title": "Hope (Orchestral battle music, 165 BPM, loopable)", "use": "every normal battle",
    },
    "boss": {
        "url": "https://opengameart.org/sites/default/files/fairy_boss_battles_bpm185_0.ogg",
        "page": "https://opengameart.org/content/fairy-boss-battles", "author": "MintoDog",
        "title": "Fairy Boss Battles (185 BPM, loopable)", "use": "L10 boss stages + Tower 12",
    },
    "victory": {
        "url": "https://opengameart.org/sites/default/files/ogg_cozy_puzzle_jingle_result.zip",
        "member": "ogg_Cozy Puzzle Jingle & Result/Cozy Puzzle Clear (Loop)_BPM85.ogg",
        "page": "https://opengameart.org/content/cozy-puzzle-jingle-result", "author": "MintoDog",
        "title": "Cozy Puzzle Clear (Loop, 85 BPM)", "use": "victory / results screen (after victory_sting)",
    },
    "defeat": {
        "url": "https://opengameart.org/sites/default/files/ogg_cozy_puzzle_jingle_result.zip",
        "member": "ogg_Cozy Puzzle Jingle & Result/Cozy Puzzle Failure (Loop)_BPM80.ogg",
        "page": "https://opengameart.org/content/cozy-puzzle-jingle-result", "author": "MintoDog",
        "title": "Cozy Puzzle Failure (Loop, 80 BPM)", "use": "defeat / results screen (after defeat_sting)",
    },
}

ELEMENTS = ["fire", "water", "wind", "earth", "thunder", "ice", "wood", "tech", "light", "dark",
            "arcane", "space"]  # = bible monsters[].element_family, lower-cased
THEMES = {  # bible towers[].theme -> ambience id
    "Nature": "amb_nature", "Fire": "amb_fire", "Water": "amb_water", "Ice": "amb_ice",
    "Metal": "amb_metal", "Wind": "amb_wind", "Dark": "amb_dark", "Ancient": "amb_ancient",
    "Space": "amb_space", "Crystal": "amb_crystal", "Aether": "amb_aether", "Mixed": "amb_mixed",
}

TARGET = {"ui": -20.0, "sfx": -16.0, "sting": -16.0, "amb": -26.0}
TP_CEIL_DB = -1.0

SOUNDS = {}  # id -> spec


def sound(sid, kind="sfx", variants=1, event="", group="battle", kenney=()):
    """Register a generator fn(rng, variant) -> mono (n,) or stereo (2, n) float array."""
    def deco(fn):
        SOUNDS[sid] = dict(fn=fn, kind=kind, variants=variants, event=event, group=group,
                           kenney=list(kenney))
        return fn
    return deco


def rng_for(sid, v):
    return np.random.default_rng(zlib.crc32(f"{sid}#{v}".encode()))


# ---------------------------------------------------------------- downloads

def ensure_kenney(pack):
    dest = KENNEY_DIR / pack
    if dest.exists():
        return dest
    KENNEY_DIR.mkdir(parents=True, exist_ok=True)
    (DL / ".gdignore").touch()
    zp = KENNEY_DIR / f"{pack}.zip"
    print(f"  fetching Kenney {pack}")
    urllib.request.urlretrieve(KENNEY_PACKS[pack], zp)
    with zipfile.ZipFile(zp) as z:
        for n in z.namelist():
            if n.startswith("/") or ".." in n:
                continue
            z.extract(n, dest)
    zp.unlink()
    return dest


_CURRENT = {"file": None}
USED_SOURCES = {}  # output file name -> sorted Kenney source files layered into it


def K(pack, name, gain=1.0):
    """Decode one Kenney file (mono) and record it as a source of the file being built."""
    if _CURRENT["file"]:
        USED_SOURCES.setdefault(_CURRENT["file"], set()).add(f"{pack}/Audio/{name}")
    return decode(ensure_kenney(pack) / "Audio" / name) * gain


# ---------------------------------------------------------------- building blocks

def thump(f0=90, f1=40, dur=0.35, tau=0.12):
    t = secs(dur)
    f = f1 + (f0 - f1) * np.exp(-t / 0.04)
    return osc(f) * env_exp(dur, tau, 0.001)


def boom(rng, dur=1.2, f0=70, tau=0.35, rumble=0.6):
    t = secs(dur)
    body = osc(f0 * (0.55 + 0.45 * np.exp(-t / 0.08))) * env_exp(dur, tau, 0.002)
    rum = lp(noise(dur, rng), 180, 4) * env_exp(dur, tau * 1.6, 0.01) * rumble * 3
    return drive(body + rum, 1.5)


def whoosh(rng, dur=0.45, f0=500, f1=3500, width=0.5, peak=0.55):
    n = noise(dur, rng)
    shape = np.interp(secs(dur), [0, dur * peak, dur], [0, 1, 0]) ** 1.7
    return sweep(n, (f0, f1), width) * shape * 3


def stone_hit(rng, size=1.0, dur=0.5):
    """Stone-on-stone knock: bright crack, body thunk, a few debris grains."""
    crack = hp(noise(0.03, rng), 1800) * env_exp(0.03, 0.006)
    body = bp(noise(dur, rng), 250 / size, 2200 / size, 2) * env_exp(dur, 0.04 * size, 0.0008) * 2.2
    th = thump(140 / size, 60 / size, dur, 0.05 * size) * 0.8
    deb = grains(dur, 40 * size, rng, dur=(0.002, 0.01), band=(1500, 7000),
                 density_curve=np.exp(-np.linspace(0, 6, 64))) * 0.5
    return mix((crack, 0, 0.6), body, th, (deb, 0.02))


def debris(rng, dur=1.0, rate=220, band=(700, 6500), decay=4.0, size=(0.003, 0.02)):
    dc = np.exp(-np.linspace(0, decay, 128))
    return grains(dur, rate, rng, dur=size, band=band, density_curve=dc)


def shimmer(rng, dur=1.0, base=1200, spread=2.5, rate=40, decay=3.0, up=False):
    dc = np.linspace(0.2, 1, 128) if up else np.exp(-np.linspace(0, decay, 128))
    return grains(dur, rate, rng, dur=(0.03, 0.12), pitched=(base, base * spread), density_curve=dc,
                  amp_jitter=0.8)


def riser(rng, dur=1.0, f0=200, f1=4000):
    n = noise(dur, rng)
    shape = np.linspace(0, 1, len(n)) ** 2.2
    return sweep(n, (f0, f1), 0.35) * shape * 3


def chord_pad(notes, dur, kind="saw", detune=0.12, cutoff=2400, attack=0.3, release=0.6, rng=None):
    out = np.zeros(int(SR * dur))
    for m in notes:
        for d in (-detune, 0, detune):
            out += osc(float(hz(m + d)), dur, kind)
    out = lp(out, cutoff, 2) / (len(notes) * 3)
    return out * env_ar(dur, attack, release, 1.5)


def creature_voice(rng, dur, f0_curve, formants, rough=0.0, breath=0.3, sub=0.0, vib=(5.5, 0.02),
                   dist=2.0, top=7000):
    """Synthetic creature vocal: harmonic source with a pitch contour, roughness (AM), subharmonic,
    breath noise, then a moving formant filter. No recordings involved."""
    t = secs(dur)
    f0 = np.interp(t, np.linspace(0, dur, len(f0_curve)), f0_curve)
    f0 = f0 * (1 + vib[1] * np.sin(2 * np.pi * vib[0] * t)) * (1 + 0.01 * lp(rng.standard_normal(len(t)), 30) * 8)
    src = osc(f0, kind="saw")
    if sub:
        src += sub * osc(f0 / 2, kind="saw")
    if rough:
        src *= 1 + rough * np.sin(2 * np.pi * (28 + 10 * rng.uniform()) * t + 3 * lp(rng.standard_normal(len(t)), 60))
    src += breath * hp(noise(dur, rng), 400)
    v = formant(src, formants) * 4
    return lp(drive(v, dist), top, 4) * env_ar(dur, 0.04, 0.25, 1.2)


# ---------------------------------------------------------------- UI

@sound("ui_tap", "ui", 2, "Any button / list item tap", "ui", ["interface-sounds"])
def _(rng, v):
    return K("interface-sounds", ["click_002.ogg", "click_003.ogg"][v])


@sound("ui_confirm", "ui", 1, "Confirm / start battle / accept dialog", "ui", ["interface-sounds"])
def _(rng, v):
    base = K("interface-sounds", "confirmation_002.ogg")
    sparkle = mix((bell(float(hz(84)), 0.6, 0.25), 0.04, 0.12), (bell(float(hz(91)), 0.6, 0.25), 0.09, 0.09))
    return dsp.to_mono(reverb(mix(base, sparkle), 0.15, 0.8))


@sound("ui_back", "ui", 1, "Back / close panel / cancel", "ui", ["interface-sounds"])
def _(rng, v):
    return K("interface-sounds", "back_002.ogg")


@sound("ui_locked", "ui", 1, "Tap on a locked tower / disabled button", "ui", ["interface-sounds"])
def _(rng, v):
    return mix(K("interface-sounds", "error_004.ogg"), (thump(160, 90, 0.2, 0.05), 0, 0.4))


@sound("ui_page", "ui", 2, "Page / tab change, dialogue advance", "ui", ["rpg-audio"])
def _(rng, v):
    return K("rpg-audio", ["bookFlip1.ogg", "bookFlip2.ogg"][v])


# ---------------------------------------------------------------- movement

@sound("step_stone", "sfx", 4, "Unit moves one tile on stone/ground/metal/ruins", "move", ["impact-sounds"])
def _(rng, v):
    return mix(K("impact-sounds", f"footstep_concrete_00{v}.ogg"), (thump(120, 60, 0.15, 0.03), 0, 0.25))


@sound("step_grass", "sfx", 4, "Unit moves one tile on forest/grass", "move", ["impact-sounds"])
def _(rng, v):
    return K("impact-sounds", f"footstep_grass_00{v}.ogg")


@sound("step_water", "sfx", 4, "Unit moves one tile on water", "move")
def _(rng, v):
    dur = 0.45
    splash = bp(noise(dur, rng), 500, 5000) * env_exp(dur, 0.07, 0.004) * 1.4
    bubbles = mix(*[(chirp(rng.uniform(350, 700), rng.uniform(900, 1800), 0.04) * np.hanning(int(0.04 * SR)),
                     rng.uniform(0.02, 0.2), 0.25) for _ in range(5)])
    return mix(splash, (bubbles, 0), (thump(100, 50, 0.2, 0.04), 0, 0.3))


@sound("step_snow", "sfx", 4, "Unit moves one tile on ice/snow", "move", ["impact-sounds"])
def _(rng, v):
    return K("impact-sounds", f"footstep_snow_00{v}.ogg")


# ---------------------------------------------------------------- statue mechanic

@sound("statue_hop", "sfx", 3, "Statue moves one tile (stone slide + clunk on landing)", "statue", ["impact-sounds"])
def _(rng, v):
    scrape = bp(noise(0.22, rng), 300, 2500) * env_ar(0.22, 0.05, 0.08) * (1 + 0.6 * np.sin(2 * np.pi * 34 * secs(0.22)))
    land = mix(stone_hit(rng, 1.3, 0.45), (K("impact-sounds", f"impactMining_00{v}.ogg"), 0, 0.5))
    return mix((scrape, 0, 0.5), (land, 0.16))


@sound("stone_crack_build", "sfx", 1, "Statue starts to awaken: stone cracks with element light (~0.6 s, rising)", "statue")
def _(rng, v):
    dur = 0.62
    crackle = grains(dur, 600, rng, dur=(0.0015, 0.006), band=(1200, 9000),
                     density_curve=np.linspace(0.05, 1, 128) ** 1.5) * np.linspace(0.3, 1, int(dur * SR))
    creak = sweep(noise(dur, rng), (300, 1400), 0.25) * np.linspace(0, 1, int(dur * SR)) ** 2 * 2
    glow = chirp(220, 880, dur, "saw") * np.linspace(0, 1, int(dur * SR)) ** 3 * 0.12
    return reverb(mix(crackle * 1.4, creak * 0.6, lp(glow, 3000)), 0.2, 0.7)


@sound("petrify_shatter", "sfx", 1, "Stone shell shatters, live monster bursts out (~0.8 s)", "statue", ["impact-sounds"])
def _(rng, v):
    dur = 0.85
    burst = mix(stone_hit(rng, 1.6, 0.6), (boom(rng, dur, 60, 0.18, 0.5), 0, 0.8))
    deb = debris(rng, dur, 700, (900, 8000), 3.5, (0.003, 0.025)) * 1.3
    glass = K("impact-sounds", "impactGlass_heavy_001.ogg") * 0.45
    wh = whoosh(rng, 0.6, 900, 6000, 0.45, 0.25)
    shim = shimmer(rng, dur, 1800, 2.2, 70, 3)
    return reverb(mix(burst, (deb, 0.01), (glass, 0.0), (wh, 0.02, 0.7), (shim, 0.05, 0.25)), 0.25, 1.2)


def _roar(rng, kind):
    if kind == "generic":
        dur = 1.05
        return creature_voice(rng, dur, [95, 150, 135, 90], [([500, 750, 650], 0.25, 1), ([1100, 1300, 1000], 0.25, 0.7),
                                                               ([2600], 0.3, 0.3)], rough=0.5, breath=0.4, sub=0.5)
    if kind == "beast":  # big low bellow
        dur = 1.3
        return creature_voice(rng, dur, [60, 95, 85, 55], [([400, 600, 500], 0.3, 1), ([900, 1100], 0.25, 0.6),
                                                             ([2300], 0.3, 0.2)], rough=0.8, breath=0.5, sub=0.9, dist=3, top=4500)
    if kind == "screech":  # bird / wyvern
        dur = 0.8
        return creature_voice(rng, dur, [700, 1250, 1100, 800], [([1600, 2400, 2000], 0.3, 1), ([3500, 4200], 0.25, 0.6)],
                              rough=0.3, breath=0.6, vib=(14, 0.04), dist=2.5)
    if kind == "growl":  # short guttural snarl
        dur = 0.7
        return creature_voice(rng, dur, [80, 110, 90], [([350, 450], 0.3, 1), ([800, 900], 0.3, 0.6)],
                              rough=1.0, breath=0.5, sub=0.7, vib=(9, 0.05), dist=3, top=5000)
    if kind == "chitter":  # insect / small sprite: fast clicky trill
        dur = 0.6
        v = creature_voice(rng, dur, [900, 1500, 1200], [([2200, 3000], 0.3, 1), ([4800], 0.3, 0.5)], rough=0.0, breath=0.3, vib=(22, 0.08))
        return v * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 26 * secs(dur))))
    raise ValueError(kind)


@sound("monster_awaken_roar_generic", "sfx", 2, "Live monster appears (default roar, any species)", "statue")
def _(rng, v):
    return reverb(_roar(rng, "generic"), 0.22, 1.1)


for _k, _desc in [("beast", "large beasts / dragons / golems"), ("screech", "birds / wyverns / wind fliers"),
                  ("growl", "small predators / dark creatures"), ("chitter", "insects / sprites / tech critters")]:
    def _mk(k):
        return lambda rng, v: reverb(_roar(rng, k), 0.22, 1.1)
    sound(f"monster_roar_{_k}", "sfx", 2, f"Awaken roar variant: {_desc}", "statue")(_mk(_k))


@sound("repetrify", "sfx", 1, "Monster turns back to stone after acting (~0.7 s, crawling then settling)", "statue")
def _(rng, v):
    dur = 0.72
    crawl = grains(dur, 500, rng, dur=(0.002, 0.008), band=(600, 5000),
                   density_curve=np.concatenate([np.linspace(1, 0.6, 90), np.linspace(0.6, 0.05, 38)]))
    grind = bp(noise(dur, rng), 150, 900) * env_ar(dur, 0.05, 0.3) * (1 + 0.5 * np.sin(2 * np.pi * 21 * secs(dur))) * 0.7
    down = chirp(700, 180, dur, "saw") * env_ar(dur, 0.02, 0.4) * 0.06
    settle = stone_hit(rng, 1.8, 0.4) * 0.8
    return reverb(mix(crawl * 1.2, grind, lp(down, 2000), (settle, dur - 0.15)), 0.18, 0.8)


@sound("stone_chip_hit", "sfx", 4, "A statue takes a hit (stone chips fly)", "statue", ["impact-sounds"])
def _(rng, v):
    return mix(stone_hit(rng, 0.9, 0.35), (K("impact-sounds", f"impactMining_00{(v + 1) % 5}.ogg"), 0, 0.6),
               (debris(rng, 0.5, 260, (1500, 8000), 5, (0.002, 0.008)), 0.01, 0.6))


@sound("statue_crumble", "sfx", 1, "A statue is KO'd: crumbles to rubble", "statue", ["impact-sounds"])
def _(rng, v):
    dur = 1.8
    cascade = grains(dur, 420, rng, dur=(0.004, 0.03), band=(250, 6000),
                     density_curve=np.concatenate([np.linspace(0.3, 1, 30), np.exp(-np.linspace(0, 3.5, 98))])) * 1.5
    rumble = lp(noise(dur, rng), 220, 4) * env_ar(dur, 0.05, 1.2) * 2.5
    hits = mix(*[(stone_hit(rng, rng.uniform(0.8, 1.8), 0.4), t, g) for t, g in [(0, 1), (0.18, 0.7), (0.42, 0.6), (0.75, 0.4)]])
    mine = K("impact-sounds", "impactMining_004.ogg") * 0.5
    return reverb(mix(cascade, rumble, hits, (mine, 0.05), (boom(rng, 1.0, 50, 0.3, 0.4), 0, 0.6)), 0.22, 1.4)


# ---------------------------------------------------------------- battle core

@sound("summon_burst", "sfx", 1, "Capsule summon: crystal burst as a monster is deployed", "battle", ["impact-sounds"])
def _(rng, v):
    dur = 1.6
    rise = riser(rng, 0.45, 600, 7000) * 0.6
    glass = K("impact-sounds", "impactGlass_heavy_002.ogg") * 0.7
    chord = mix(*[(bell(float(hz(m)), dur, 0.7), 0.42, 0.25) for m in (76, 83, 88, 92)])
    shim = shimmer(rng, dur, 2000, 2.5, 90, 2.5)
    return reverb(mix(rise, (glass, 0.42), chord, (shim, 0.42, 0.35), (thump(110, 45, 0.5, 0.15), 0.42, 0.7)), 0.3, 2.0)


@sound("hit_melee", "sfx", 5, "Basic attack lands", "battle", ["impact-sounds"])
def _(rng, v):
    return mix(K("impact-sounds", f"impactPunch_medium_00{v}.ogg"), (thump(130, 55, 0.25, 0.06), 0, 0.45),
               (whoosh(rng, 0.12, 1500, 5000, 0.5, 0.8), -0.0, 0.25))


@sound("hit_heavy", "sfx", 3, "Strong hit / super-effective hit", "battle", ["impact-sounds"])
def _(rng, v):
    return reverb(mix(K("impact-sounds", f"impactPunch_heavy_00{v}.ogg"), (boom(rng, 0.7, 75, 0.15, 0.5), 0, 0.8),
                      (debris(rng, 0.5, 120), 0.01, 0.3)), 0.15, 0.9)


@sound("hit_critical", "sfx", 2, "Critical hit (bigger, metallic ring, glass sparkle)", "battle", ["impact-sounds"])
def _(rng, v):
    ring = K("impact-sounds", f"impactBell_heavy_00{v}.ogg") * 0.4
    return reverb(mix(K("impact-sounds", f"impactPunch_heavy_00{v + 3}.ogg"), (boom(rng, 0.9, 65, 0.2, 0.6), 0, 0.9),
                      (ring, 0.0), (K("impact-sounds", f"impactGlass_heavy_00{v + 3}.ogg") * 0.4, 0.02),
                      (shimmer(rng, 0.9, 2500, 2, 60, 3), 0.03, 0.25)), 0.25, 1.4)


@sound("defend_shield", "sfx", 1, "Defend command / shield raised / hit blocked", "battle", ["sci-fi-sounds"])
def _(rng, v):
    ff = K("sci-fi-sounds", "forceField_001.ogg")
    hum = fm(220, 1.5, 2, 0.7, np.exp(-secs(0.7) / 0.2)) * env_ar(0.7, 0.02, 0.4) * 0.25
    return reverb(mix(ff, hum, (bell(float(hz(79)), 0.8, 0.3) * 0.2, 0.02)), 0.2, 1.0)


@sound("miss_whoosh", "sfx", 3, "Attack misses / dodge", "battle")
def _(rng, v):
    return whoosh(rng, rng.uniform(0.3, 0.45), rng.uniform(300, 600), rng.uniform(3000, 6000), 0.5, rng.uniform(0.4, 0.6))


@sound("ko_dissolve", "sfx", 1, "Monster KO (non-statue fallback): faint + dissolve into motes", "battle")
def _(rng, v):
    dur = 1.6
    fall = chirp(600, 90, 0.9, "tri") * env_ar(0.9, 0.01, 0.5) * 0.4
    motes = shimmer(rng, dur, 900, 3, 70, 2.2)
    air = sweep(noise(dur, rng), (4000, 500), 0.5) * env_ar(dur, 0.05, 1.0) * 1.5
    return reverb(mix(fall, motes * 0.8, air * 0.6, (thump(90, 40, 0.4, 0.1), 0, 0.5)), 0.35, 2.2)


@sound("level_up", "sting", 1, "Monster levels up", "progress")
def _(rng, v):
    notes = [72, 76, 79, 84, 88]
    arp = mix(*[(mix((bell(float(hz(m)), 1.0, 0.45), 0, 0.5), (osc(float(hz(m)), 0.25, "tri") * env_exp(0.25, 0.08), 0, 0.3)), i * 0.07)
                for i, m in enumerate(notes)])
    pad = chord_pad([72, 76, 79, 84], 1.4, "saw", cutoff=3500, attack=0.25, release=0.8) * 0.7
    return reverb(mix(arp, (pad, 0.25), (shimmer(rng, 1.2, 2500, 2, 50, 2), 0.3, 0.3)), 0.3, 1.8)


@sound("evolve_build", "sfx", 1, "Evolution: energy builds (~2.5 s riser; play evolve_burst at its end)", "progress")
def _(rng, v):
    dur = 2.5
    t = secs(dur)
    r = riser(rng, dur, 150, 6000) * 0.8
    tone = osc(110 * 2 ** (t / dur * 2), kind="saw") * (t / dur) ** 2 * 0.2
    pulse = (0.5 + 0.5 * np.sin(2 * np.pi * (3 + 14 * (t / dur) ** 2) * t))
    sh = shimmer(rng, dur, 1500, 3, 120, up=True)
    return reverb(mix(r, lp(tone, 2500) * pulse, sh * 0.6), 0.3, 1.5)


@sound("evolve_burst", "sfx", 1, "Evolution: the new form is revealed", "progress", ["impact-sounds"])
def _(rng, v):
    dur = 2.4
    chord = chord_pad([60, 67, 72, 76, 79], dur, "saw", 0.15, 4000, 0.02, 1.6)
    bells = mix(*[(bell(float(hz(m)), dur, 0.9), 0, 0.2) for m in (84, 88, 91, 96)])
    return reverb(mix(chord, bells, (boom(rng, 1.4, 55, 0.4, 0.5), 0, 0.9),
                      (K("impact-sounds", "impactGlass_heavy_000.ogg") * 0.5, 0), (shimmer(rng, dur, 2200, 2.5, 110, 1.8), 0, 0.5)),
                  0.35, 2.6)


@sound("fusion_merge", "sfx", 1, "Fusion: two monsters spiral together and merge (~2.2 s)", "progress")
def _(rng, v):
    dur = 2.2
    t = secs(dur)
    a = osc(hz(60) * (1 + 0.5 * (1 - t / dur) ** 2), kind="saw")
    b = osc(hz(67) * (1 - 0.3 * (1 - t / dur) ** 2), kind="saw")
    trem = 0.5 + 0.5 * np.sin(2 * np.pi * (2 + 12 * (t / dur) ** 2) * t)
    pair = lp(a + b, 2500) * (t / dur) ** 1.5 * trem * 0.25
    l = pair * (0.5 + 0.5 * np.sin(2 * np.pi * 1.5 * t ** 1.4))
    r = pair * (0.5 - 0.5 * np.sin(2 * np.pi * 1.5 * t ** 1.4))
    st = np.array([l, r])
    hit_at = dur - 0.35
    flash = mix((boom(rng, 1.0, 60, 0.3), hit_at, 0.8), (bell(float(hz(84)), 1.0, 0.6), hit_at, 0.4),
                (shimmer(rng, 1.0, 2200, 2, 100, 2), hit_at, 0.4), (riser(rng, hit_at, 300, 5000), 0, 0.5))
    return stereo_mix((st, 0, 1), (reverb(flash, 0.3, 2.0), 0, 1))


@sound("victory_sting", "sting", 1, "Battle won (plays before music 'victory')", "result")
def _(rng, v):
    def brass(notes, d):
        return chord_pad(notes, d, "saw", 0.08, 2800, 0.03, 0.3)
    seq = [([67, 71, 74], 0.0, 0.18), ([67, 71, 74], 0.2, 0.18), ([69, 72, 76], 0.4, 0.18), ([71, 74, 79, 83], 0.62, 1.5)]
    parts = [(brass(n, d), at, 1.0) for n, at, d in seq]
    timp = mix(*[(thump(95, 70, 0.6, 0.25), at, 0.8) for at in (0, 0.2, 0.4, 0.62)])
    bells = mix(*[(bell(float(hz(m)), 1.6, 0.8), 0.62, 0.25) for m in (83, 86, 91)])
    return reverb(mix(*parts, timp, bells, (shimmer(rng, 1.5, 2500, 2, 50, 2), 0.62, 0.35)), 0.3, 2.0)


@sound("defeat_sting", "sting", 1, "Battle lost (plays before music 'defeat')", "result")
def _(rng, v):
    seq = [([62, 65, 69], 0.0, 0.5), ([61, 64, 68], 0.5, 0.5), ([57, 60, 64], 1.0, 1.8)]
    parts = [(chord_pad(n, d, "saw", 0.1, 1600, 0.05, 0.6), at, 1.0) for n, at, d in seq]
    return reverb(mix(*parts, (boom(rng, 2.0, 45, 0.6, 0.6), 1.0, 0.7), (lp(brown(2.8, rng), 300) * env_ar(2.8, 0.5, 1.2), 0, 0.3)),
                  0.35, 2.4)


@sound("sigil_damage", "sfx", 2, "A player/enemy Symbol (sigil) takes damage", "battle", ["impact-sounds"])
def _(rng, v):
    dur = 1.4
    crack = K("impact-sounds", f"impactGlass_heavy_00{v + 2}.ogg")
    ring = sum(np.sin(2 * np.pi * f * secs(dur)) * np.exp(-secs(dur) / 0.5) for f in (311, 466, 622 * 1.01)) * 0.12
    ring = drive(ring * (1 + 0.6 * np.sin(2 * np.pi * 7 * secs(dur))), 2)
    return reverb(mix(crack, (boom(rng, 1.2, 50, 0.3, 0.7), 0, 0.9), ring, (debris(rng, 0.8, 200, (1500, 8000)), 0.02, 0.4)), 0.3, 1.8)


@sound("capsule_node", "sfx", 1, "Capsule node activates / recharges", "battle", ["digital-audio"])
def _(rng, v):
    dur = 1.0
    hum = fm(hz(57), 2.0, 1.5, dur, np.linspace(0, 1, int(dur * SR))) * env_ar(dur, 0.3, 0.4) * 0.3
    return reverb(mix(K("digital-audio", "powerUp3.ogg", 0.7), hum, (bell(float(hz(81)), 0.8, 0.4) * 0.25, 0.25),
                      (shimmer(rng, 0.8, 1800, 2, 40, 2), 0.2, 0.3)), 0.25, 1.4)


# ---------------------------------------------------------------- element casts (x12)

def _cast(element, rng):
    d = 1.3
    if element == "fire":
        ign = whoosh(rng, 0.5, 200, 2500, 0.7, 0.35) * 1.2
        roar = drive(lp(noise(d, rng), 900, 2) * env_ar(d, 0.15, 0.8) * 3, 2) * 0.8
        crackle = grains(d, 350, rng, dur=(0.001, 0.004), band=(2000, 9000), density_curve=np.exp(-np.linspace(0, 2, 64)))
        return reverb(mix(ign, (roar, 0.15), (crackle, 0.1, 0.9), (boom(rng, 0.8, 70, 0.2, 0.5), 0.35, 0.6)), 0.2, 1.2)
    if element == "water":
        swell = sweep(noise(d, rng), (300, 1200), 0.6) * env_ar(d, 0.35, 0.6) * 3
        splash = bp(noise(0.8, rng), 600, 6000) * env_exp(0.8, 0.15) * 1.5
        bub = grains(d, 60, rng, dur=(0.02, 0.05), pitched=(500, 1600), density_curve=np.exp(-np.linspace(0, 2.5, 64)))
        return reverb(mix(swell, (splash, 0.4), (bub, 0.35, 0.6), (thump(90, 45, 0.5, 0.15), 0.4, 0.6)), 0.3, 1.6)
    if element == "wind":
        a = whoosh(rng, 0.9, 300, 4000, 0.4, 0.5)
        b = whoosh(rng, 0.8, 500, 6000, 0.35, 0.45)
        whistle = sweep(noise(d, rng), (900, 2600), 0.05) * env_ar(d, 0.3, 0.6) * 4
        return stereo_mix((pan(a, -0.6), 0, 1), (pan(b, 0.6), 0.15, 1), (reverb(whistle * 0.5, 0.4, 1.8), 0.05, 1))
    if element == "earth":
        rumble = lp(noise(d, rng), 250, 4) * env_ar(d, 0.1, 0.9) * 4
        return reverb(mix(rumble, (boom(rng, 1.2, 55, 0.35, 0.8), 0.2, 1.1), (stone_hit(rng, 1.6, 0.6), 0.2, 0.9),
                          (debris(rng, 1.0, 300, (500, 6000)), 0.22, 0.9), (K("impact-sounds", "impactMining_002.ogg"), 0.22, 0.5)),
                      0.2, 1.2)
    if element == "thunder":
        zap = fm(90, 7.1, 9, 0.5, np.exp(-secs(0.5) / 0.2)) * env_exp(0.5, 0.18) * 0.5
        crack = hp(noise(0.12, rng), 1500) * env_exp(0.12, 0.02, 0.0005) * 1.5
        rumble = lp(noise(d + 0.6, rng), 300, 3) * env_ar(d + 0.6, 0.15, 1.2) * 3
        charge = sweep(noise(0.3, rng), (2000, 8000), 0.3) * np.linspace(0, 1, int(0.3 * SR)) ** 2 * 2
        return reverb(mix(charge, (crack, 0.3), (drive(zap, 3), 0.3), (rumble, 0.32), (boom(rng, 0.9, 60, 0.25, 0.4), 0.3, 0.6)), 0.3, 2.0)
    if element == "ice":
        bells = mix(*[(bell(rng.uniform(1800, 4200), 1.0, 0.35, partials=(1, 2.32, 4.25, 6.63)), rng.uniform(0.15, 0.6), 0.15)
                      for _ in range(9)])
        cracks = grains(0.6, 60, rng, dur=(0.002, 0.006), band=(2500, 10000))
        cold = sweep(noise(d, rng), (5000, 1500), 0.5) * env_ar(d, 0.2, 0.6) * 2
        return reverb(mix(cold, (cracks, 0.15, 1.2), bells, (K("impact-sounds", "impactGlass_heavy_004.ogg") * 0.5, 0.3)), 0.35, 2.0)
    if element == "wood":
        knock = K("impact-sounds", "impactWood_heavy_001.ogg")
        rustle = grains(d, 500, rng, dur=(0.003, 0.012), band=(2500, 9000), density_curve=np.interp(np.linspace(0, 1, 64), [0, .3, 1], [0.1, 1, 0])) * 0.8
        grow = fm(hz(50), 1.0, 2.5, d, np.linspace(0, 1, int(d * SR))) * env_ar(d, 0.4, 0.5) * 0.35
        creak = sweep(noise(0.6, rng), (250, 700), 0.15) * env_ar(0.6, 0.1, 0.3) * 3
        return reverb(mix(rustle, (lp(grow, 1800), 0.0), (creak, 0.25, 0.6), (knock, 0.55)), 0.25, 1.3)
    if element == "tech":
        beeps = mix(*[(osc(float(hz(m)), 0.06, "sq") * env_exp(0.06, 0.03) * 0.25, i * 0.06) for i, m in enumerate((84, 88, 91, 96, 91, 100))])
        servo = chirp(300, 1400, 0.4, "saw") * env_ar(0.4, 0.05, 0.1) * 0.15
        laser = K("sci-fi-sounds", "laserLarge_002.ogg")
        return reverb(mix(beeps, (lp(servo, 4000), 0.0), (laser, 0.38), (thump(140, 60, 0.3, 0.08), 0.38, 0.5)), 0.15, 0.9)
    if element == "light":
        choir = formant(chord_pad([72, 76, 79, 83, 88], d + 0.4, "saw", 0.15, 6000, 0.3, 0.8) * 3,
                        [(800, 0.25, 1), (1150, 0.25, 0.6), (2900, 0.3, 0.3)])
        rise = riser(rng, 0.5, 1500, 9000) * 0.4
        return reverb(mix(rise, (choir * 2, 0.15), (shimmer(rng, d, 3000, 2, 80, 2), 0.4, 0.4), (bell(float(hz(96)), 1.2, 0.6) * 0.2, 0.45)), 0.4, 2.4)
    if element == "dark":
        t = secs(d)
        drone = lp(osc(hz(36) * (1 - 0.15 * t / d), kind="saw") + osc(hz(36.3), d, "saw"), 600) * env_ar(d, 0.5, 0.5) * 0.4
        rev = whoosh(rng, d, 3000, 200, 0.6, 0.8) * 0.8
        whisper = formant(noise(d, rng), [([900, 600], 0.2, 1), ([2500, 1800], 0.2, 0.6)]) * env_ar(d, 0.4, 0.4) * 1.5
        return reverb(mix(drone, rev, whisper, (boom(rng, 0.8, 45, 0.25, 0.7), d - 0.25, 0.8)), 0.4, 2.2, damp=3000)
    if element == "arcane":
        t = secs(d)
        chord = mix(*[(fm(float(hz(m)), 1.414, 2.0, d, np.exp(-t / 0.5)) * env_ar(d, 0.05, 0.8) * 0.18, i * 0.05) for i, m in enumerate((69, 73, 76, 80))])
        warble = chord * (1 + 0.3 * np.sin(2 * np.pi * 6 * secs(len(chord) / SR)))
        rev_cym = sweep(noise(0.6, rng), (8000, 3000), 0.6) * np.linspace(0, 1, int(0.6 * SR)) ** 3 * 1.5
        return reverb(mix(rev_cym, (warble, 0.55), (shimmer(rng, d, 1500, 3, 60, 2), 0.6, 0.4)), 0.4, 2.2)
    if element == "space":
        t = secs(d + 0.5)
        sub = osc(40 + 15 * t / (d + 0.5), kind="sin") * env_ar(d + 0.5, 0.6, 0.6) * 0.6
        phase = sweep(noise(d + 0.5, rng), (200, 6000), 0.15) * env_ar(d + 0.5, 0.3, 0.5) * 3
        echoes = mix(*[(bell(float(hz(86)), 0.5, 0.25) * 0.3 * 0.6 ** k, 0.4 + k * 0.18) for k in range(5)])
        return reverb(mix(sub, phase, echoes, (shimmer(rng, d, 3000, 2, 40, 2), 0.3, 0.3)), 0.45, 3.0)
    raise ValueError(element)


for _el in ELEMENTS:
    def _mkc(el):
        return lambda rng, v: _cast(el, rng)
    sound(f"cast_{_el}", "sfx", 1, f"Skill cast, element_family {_el.capitalize()}", "cast",
          ["impact-sounds"] if _el in ("earth", "ice", "wood") else (["sci-fi-sounds"] if _el == "tech" else []))(_mkc(_el))


# ---------------------------------------------------------------- ambience (30 s loops)

AMB_LEN = 30.0
AMB_XF = 3.0


def _wind(rng, dur, lo=200, hi=1500, gust=0.12):
    t = secs(dur)
    centre = lo * (hi / lo) ** (0.5 + 0.5 * np.sin(2 * np.pi * gust * t + 2 * np.sin(2 * np.pi * gust * 0.37 * t)))
    w = sweep(noise(dur, rng), centre[:: max(1, len(t) // 600)], 0.5) * 2
    amp = 0.6 + 0.4 * np.sin(2 * np.pi * gust * 1.3 * t + 1)
    return w * amp


def _amb(theme, rng):
    d = AMB_LEN + AMB_XF
    if theme == "nature":
        tw = np.zeros(int(d * SR))
        for _ in range(26):
            n = int(rng.uniform(0.04, 0.1) * SR)
            f = rng.uniform(2800, 4800)
            c = np.sin(2 * np.pi * np.cumsum(f * (1 + 0.25 * np.sin(np.linspace(0, rng.uniform(3, 9), n)))) / SR) * np.hanning(n)
            for k in range(int(rng.integers(1, 4))):
                s = int(rng.uniform(0, d - 0.5) * SR) + int(k * 0.13 * SR)
                tw[s:s + n] += c * 0.06
        leaves = grains(d, 260, rng, dur=(0.004, 0.015), band=(3000, 9000)) * 0.25
        return mix(_wind(rng, d, 250, 1200, 0.07) * 0.5, leaves, tw)
    if theme == "fire":
        roar = lp(brown(d, rng), 400) * 0.8
        crack = grains(d, 90, rng, dur=(0.001, 0.005), band=(1500, 8000)) * 0.9
        pops = grains(d, 6, rng, dur=(0.01, 0.03), band=(600, 3000)) * 1.2
        return mix(roar, crack, pops)
    if theme == "water":
        flow = bp(noise(d, rng), 300, 3000) * (0.7 + 0.3 * np.sin(2 * np.pi * 0.1 * secs(d))) * 0.4
        drips = grains(d, 3, rng, dur=(0.03, 0.06), pitched=(700, 1600)) * 0.5
        return mix(flow, lp(brown(d, rng), 250) * 0.6, drips)
    if theme == "ice":
        howl = _wind(rng, d, 500, 2600, 0.05) * 0.6
        tinkle = mix(*[(bell(rng.uniform(2500, 5000), 1.2, 0.3, partials=(1, 2.32, 4.25)) * 0.03, rng.uniform(0, d - 1.3), 1) for _ in range(30)])
        return mix(howl, tinkle)
    if theme == "metal":
        hum = (osc(55, d) * 0.15 + osc(110, d) * 0.06 + osc(165.5, d) * 0.03) * (0.8 + 0.2 * np.sin(2 * np.pi * 0.3 * secs(d)))
        ticks = np.zeros(int(d * SR))
        for i in range(int(d / 0.75)):
            tk = hp(noise(0.01, rng), 3000) * env_exp(0.01, 0.002) * 0.15
            s = int(i * 0.75 * SR)
            ticks[s:s + len(tk)] += tk
        clanks = mix(*[(K("impact-sounds", f"impactMetal_light_00{int(rng.integers(0, 5))}.ogg") * 0.15, rng.uniform(0, d - 1), 1) for _ in range(6)])
        return mix(hum, ticks, lp(clanks, 3000), bp(noise(d, rng), 2000, 6000) * 0.02)
    if theme == "wind":  # sky ruins
        a = _wind(rng, d, 250, 2200, 0.09) * 0.8
        whistle = sweep(noise(d, rng), 900 + 500 * np.sin(np.linspace(0, 6 * np.pi, 400)), 0.05) * 1.2
        return mix(a, whistle * (0.4 + 0.4 * np.sin(2 * np.pi * 0.07 * secs(d))))
    if theme == "dark":
        drone = lp(osc(hz(33), d, "saw") + osc(hz(33.15), d, "saw") + 0.5 * osc(hz(40), d, "saw"), 280) * 0.25
        breath = formant(noise(d, rng), [(700, 0.25, 1), (1600, 0.25, 0.5)]) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.11 * secs(d))) * 0.12
        return mix(drone, breath)
    if theme == "ancient":
        room = lp(brown(d, rng), 300) * 0.5 + bp(noise(d, rng), 200, 900) * 0.04
        drips = grains(d, 2, rng, dur=(0.02, 0.05), pitched=(900, 2200)) * 0.6
        chime = mix(*[(bell(float(hz(rng.choice([62, 65, 69, 72]))), 4.0, 1.5) * 0.04, rng.uniform(0, d - 4), 1) for _ in range(4)])
        return dsp.to_mono(reverb(mix(room, drips, chime), 0.5, 3.5, damp=3000))
    if theme == "space":
        pad = sum(osc(float(hz(m)), d) * (0.5 + 0.5 * np.sin(2 * np.pi * r * secs(d) + m)) for m, r in [(38, 0.05), (45, 0.03), (50, 0.04), (57, 0.06)]) * 0.12
        sparkle = grains(d, 5, rng, dur=(0.05, 0.15), pitched=(2500, 6000)) * 0.15
        return mix(pad, sparkle, lp(brown(d, rng), 150) * 0.3)
    if theme == "crystal":
        hum = sum(osc(float(hz(m)), d) * (0.5 + 0.5 * np.sin(2 * np.pi * r * secs(d) + m)) for m, r in [(64, 0.07), (71, 0.05), (76, 0.09), (83, 0.04)]) * 0.07
        chimes = mix(*[(bell(float(hz(rng.choice([76, 79, 83, 88, 91]))), 2.0, 0.8) * 0.05, rng.uniform(0, d - 2), 1) for _ in range(14)])
        return mix(hum, chimes, _wind(rng, d, 800, 3000, 0.05) * 0.1)
    if theme == "aether":
        t = secs(d)
        warble = osc(hz(52) * (1 + 0.03 * np.sin(2 * np.pi * 0.2 * t)), kind="saw") + osc(hz(59) * (1 + 0.04 * np.sin(2 * np.pi * 0.13 * t + 1)), kind="saw")
        warble = sweep(warble, 600 + 500 * np.sin(np.linspace(0, 8 * np.pi, 300)), 0.6) * 0.3
        rift = grains(d, 40, rng, dur=(0.002, 0.01), band=(2000, 9000), density_curve=0.3 + 0.7 * (np.sin(np.linspace(0, 9, 64)) > 0.6)) * 0.4
        return mix(warble, rift, lp(brown(d, rng), 200) * 0.3)
    if theme == "mixed":  # Sunforge: furnace roar + crystal hum
        return mix(_amb("fire", rng) * 0.7, _amb("crystal", rng) * 0.6)
    raise ValueError(theme)


for _th, _aid in THEMES.items():
    def _mka(th):
        return lambda rng, v: _amb(th, rng)
    sound(_aid, "amb", 1, f"Tower ambience loop, theme {_th}", "ambience",
          ["impact-sounds"] if _th == "Metal" else [])(_mka(_th.lower()))


# ---------------------------------------------------------------- mastering

_meter = pyloudnorm.Meter(SR, block_size=0.4)


def _mono(x):
    return x if x.ndim == 1 else x.mean(axis=0)


def momentary_max(x):
    """Max K-weighted loudness over 400 ms windows (hop 50 ms); clip padded to 400 ms."""
    y = x if x.ndim == 1 else x.T
    n = len(y)
    w = int(0.4 * SR)
    if n < w:
        pad = np.zeros((w - n,) + y.shape[1:])
        y = np.concatenate([y, pad])
        n = w
    best = -120.0
    for s in range(0, n - w + 1, int(0.05 * SR)):
        with np.errstate(divide="ignore"):
            l = _meter.integrated_loudness(y[s:s + w])
        if np.isfinite(l):
            best = max(best, l)
    return best


def integrated(x):
    return _meter.integrated_loudness(x if x.ndim == 1 else x.T)


def true_peak_db(x):
    up = signal.resample_poly(np.atleast_2d(x), 4, 1, axis=-1)
    return 20 * np.log10(np.max(np.abs(up)) + 1e-12)


def limit(x, ceil_db=TP_CEIL_DB):
    """Look-ahead true-peak limiter: 4x-oversampled peak detection, 1.5 ms look-ahead, 80 ms release."""
    x2 = np.atleast_2d(x).astype(float)
    ceil = 10 ** ((ceil_db - 0.2) / 20)
    for _ in range(4):
        up = np.max(np.abs(signal.resample_poly(x2, 4, 1, axis=-1)), axis=0)
        pk = up[: x2.shape[1] * 4].reshape(-1, 4).max(axis=1) if len(up) >= x2.shape[1] * 4 else np.resize(up, x2.shape[1])
        need = np.minimum(1.0, ceil / np.maximum(pk, 1e-9))
        if need.min() >= 0.999:
            break
        la = int(0.0015 * SR)
        g = np.minimum.reduce([np.roll(np.pad(need, (la, la), constant_values=1.0), -k)[la:la + len(need)] for k in range(0, 2 * la + 1, 4)])
        rel = np.exp(-1 / (0.08 * SR))
        sm = np.empty_like(g)
        cur = 1.0
        for i, gi in enumerate(g):
            cur = gi if gi < cur else gi + (cur - gi) * rel
            sm[i] = cur
        x2 = x2 * sm
    return x2[0] if np.ndim(x) == 1 else x2


def trim(x, thresh_db=-60.0):
    m = np.abs(_mono(x))
    th = 10 ** (thresh_db / 20) * max(m.max(), 1e-9)
    idx = np.nonzero(m > th)[0]
    if len(idx) == 0:
        return x
    a = max(0, idx[0] - int(0.002 * SR))
    b = min(len(m), idx[-1] + int(0.02 * SR))
    return x[..., a:b]


def master_oneshot(x, target):
    x = trim(np.asarray(x, dtype=float))
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.5
    l = momentary_max(x)
    x = x * 10 ** ((target - l) / 20)
    x = limit(x)
    n = x.shape[-1]
    fo = min(int(0.03 * SR), n // 4)
    x[..., n - fo:] *= np.linspace(1, 0, fo)
    return x


def master_loop(x, target, length=AMB_LEN, xf=AMB_XF):
    """x is length+xf long: cross-fade the tail into the head (equal power) -> seamless loop."""
    x = np.atleast_2d(np.asarray(x, dtype=float))
    L, X = int(length * SR), int(xf * SR)
    head = x[:, :L].copy()
    tail = x[:, L:L + X]
    k = np.linspace(0, np.pi / 2, X)
    head[:, :X] = head[:, :X] * np.sin(k) + tail * np.cos(k)
    l = integrated(head if head.shape[0] > 1 else head[0])
    head = head * 10 ** ((target - l) / 20)
    pk = true_peak_db(head)
    if pk > TP_CEIL_DB:
        head = head * 10 ** ((TP_CEIL_DB - 0.1 - pk) / 20)
    return head if head.shape[0] > 1 else head[0]


def master_loop_gain(x, target):
    """An already-looping source (ElevenLabs loop=true): loudness gain + true-peak check only."""
    x = np.asarray(x, dtype=float)
    x = x * 10 ** ((target - integrated(x)) / 20)
    pk = true_peak_db(x)
    return x * 10 ** ((TP_CEIL_DB - 0.1 - pk) / 20) if pk > TP_CEIL_DB else x


# ---------------------------------------------------------------- build

def channels_of(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=channels",
                          "-of", "csv=p=0", str(path)], capture_output=True, text=True, check=True).stdout
    return int(out.strip())


def rel(p):
    return "res://" + p.relative_to(AUDIO.parent).as_posix()


def build_sounds(only):
    SFX_DIR.mkdir(parents=True, exist_ok=True)
    AMB_DIR.mkdir(parents=True, exist_ok=True)
    report = {}
    for sid, spec in SOUNDS.items():
        files = []
        out_dir = AMB_DIR if spec["kind"] == "amb" else SFX_DIR
        for v in range(spec["variants"]):
            name = f"{sid}.ogg" if spec["variants"] == 1 else f"{sid}_{v + 1:02d}.ogg"
            path = out_dir / name
            files.append(path)
            if only and sid not in only and path.exists():
                continue
            ov = OVERRIDES / name
            _CURRENT["file"] = name
            USED_SOURCES.pop(name, None)
            if ov.exists():  # an approved ElevenLabs (or hand-made) source replaces the synthesis
                raw = decode(ov, channels_of(ov))
                USED_SOURCES[name] = {"ElevenLabs override: tools/overrides/" + name}
                y = master_loop_gain(raw, TARGET["amb"]) if spec["kind"] == "amb" else master_oneshot(raw, TARGET[spec["kind"]])
            elif spec["kind"] == "amb":
                a = spec["fn"](rng_for(sid, v), v)
                b = spec["fn"](rng_for(sid, v + 1000), v)  # second take, different seed -> real stereo width
                raw = np.array([0.8 * a + 0.2 * b, 0.8 * b + 0.2 * a])
                y = master_loop(raw, TARGET["amb"])
            else:
                raw = spec["fn"](rng_for(sid, v), v)
                y = master_oneshot(raw, TARGET[spec["kind"]])
            _CURRENT["file"] = None
            encode_ogg(y, path)
            for _ in range(4):  # Vorbis can overshoot the limiter by ~1-2 dB: re-check the decoded file
                ch = 1 if np.ndim(y) == 1 else 2
                over = true_peak_db(decode(path, ch)) - (TP_CEIL_DB - 0.05)
                if over <= 0:
                    break
                y = y * 10 ** (-(over + 0.1) / 20)
                encode_ogg(y, path)
        spec["files"] = files
        y = decode(files[0], channels_of(files[0]))
        report[sid] = (round(momentary_max(y) if spec["kind"] != "amb" else integrated(y), 1),
                       round(true_peak_db(y), 1), round(y.shape[-1] / SR, 2))
        print(f"  {sid:30s} x{spec['variants']}  loud={report[sid][0]:6.1f}  tp={report[sid][1]:5.1f}  {report[sid][2]:5.2f}s")
    return report


def fetch_music():
    out = {}
    for mid, m in MUSIC.items():
        slug = m["page"].rsplit("/", 1)[1]
        d = OGA_DIR / slug
        d.mkdir(parents=True, exist_ok=True)
        (DL / ".gdignore").touch()
        fn = d / m["url"].rsplit("/", 1)[1]
        if not fn.exists():
            print(f"  fetching {m['url']}")
            urllib.request.urlretrieve(m["url"], fn)
        if "member" in m:
            src = d / m["member"]
            if not src.exists():
                with zipfile.ZipFile(fn) as z:
                    if ".." in m["member"] or m["member"].startswith("/"):
                        raise ValueError("bad member")
                    z.extract(m["member"], d)
            fn = src
        out[mid] = fn
    return out


def build_music():
    MUS_DIR.mkdir(parents=True, exist_ok=True)
    srcs = fetch_music()
    meter = pyloudnorm.Meter(44100)
    info = {}
    for mid, src in srcs.items():
        x = decode(src, 2, 44100)
        l = meter.integrated_loudness(x.T)
        g = -16.0 - l
        up = signal.resample_poly(x, 4, 1, axis=-1)
        pk = 20 * np.log10(np.max(np.abs(up)) + 1e-12)
        g = min(g, TP_CEIL_DB - 0.1 - pk)
        y = x * 10 ** (g / 20)
        path = MUS_DIR / f"{mid}.ogg"
        encode_ogg(y, path, quality=6, sr=44100)
        # loop-seam check: level step and sample jump across end->start
        z = decode(path, 2, 44100)
        e, s = z[:, -2205:], z[:, :2205]
        rms = lambda a: 20 * np.log10(np.sqrt(np.mean(a ** 2)) + 1e-9)
        info[mid] = dict(seconds=round(z.shape[1] / 44100, 2), gain_db=round(g, 1), lufs=round(meter.integrated_loudness(z.T), 1),
                         seam_rms_end=round(rms(e), 1), seam_rms_start=round(rms(s), 1),
                         seam_jump=round(float(np.max(np.abs(z[:, -1] - z[:, 0]))), 3))
        print(f"  music {mid:8s} {info[mid]}")
    return info


def write_registry():
    reg = {"_doc": "Generated by game/audio/tools/make_sfx.py - do not hand-edit. id -> files (variants are "
                   "picked at random), bus, loop.", "sfx": {}, "ambience": {}, "music": {}, "theme_ambience": THEMES}
    for sid, spec in SOUNDS.items():
        if spec["kind"] == "amb":
            reg["ambience"][sid] = {"files": [rel(p) for p in spec["files"]], "bus": "Ambience", "loop": True}
        else:
            reg["sfx"][sid] = {"files": [rel(p) for p in spec["files"]], "bus": "SFX", "group": spec["group"]}
    for mid, m in MUSIC.items():
        reg["music"][mid] = {"file": rel(MUS_DIR / f"{mid}.ogg"), "bus": "Music", "loop": True, "use": m["use"]}
    (AUDIO / "audio_registry.json").write_text(json.dumps(reg, indent=1) + "\n", encoding="utf-8")


def write_hooks():
    lines = ["# Audio hooks - game event -> sound id",
             "",
             "Generated by `game/audio/tools/make_sfx.py` (edit the `event` text there, not here). "
             "Call `AudioManager.play_sfx(\"<id>\", position_or_null, pitch_jitter)`; ids with variants pick one at random. "
             "Music: `AudioManager.play_music(\"<id>\", crossfade_sec)`. Ambience: `AudioManager.play_ambience_for_theme(tower.theme)` "
             "or `play_ambience(\"<id>\")`. Voice: `AudioManager.play_voice(\"<line_id>\")` (silent no-op when the file is missing).",
             "",
             "Suggested pitch_jitter: 0.06 for steps / hits / chips, 0.03 for casts, 0 for UI, stings and music-like cues.",
             ""]
    groups = [("ui", "UI"), ("move", "Movement"), ("statue", "Statue mechanic (stone -> awaken -> act -> re-petrify)"),
              ("battle", "Battle"), ("cast", "Skill casts (by monster `element_family`)"), ("progress", "Progression"),
              ("result", "Result stings"), ("ambience", "Ambience loops (by tower `theme`)")]
    for g, title in groups:
        lines += [f"## {title}", "", "| Event | Id | Variants | Bus |", "|---|---|---|---|"]
        for sid, spec in SOUNDS.items():
            if spec["group"] == g:
                bus = "Ambience" if spec["kind"] == "amb" else "SFX"
                lines.append(f"| {spec['event']} | `{sid}` | {spec['variants']} | {bus} |")
        lines.append("")
    if any(s["group"] == "statue" for s in SOUNDS.values()):
        lines += ["Statue attack sequence: `stone_crack_build` (0.6 s) -> `petrify_shatter` + `monster_awaken_roar_*` "
                  "(or a `monster_roar_<kind>` by species) -> `cast_<element>` / `hit_*` -> `repetrify`. "
                  "Hits on a statue: `stone_chip_hit`; KO: `statue_crumble`.", "",
                  "Sync points for the animation pass: `stone_crack_build` crackle peaks and cuts at ~0.62 s (start "
                  "`petrify_shatter` there; its impact is at 0 s); `repetrify` settle thunk lands at ~0.57 s; "
                  "`statue_hop` landing clunk at ~0.16 s; `evolve_build` is 2.5 s to its peak, then `evolve_burst`; "
                  "`fusion_merge` flash at ~1.85 s.", ""]
    lines += ["## Voice", "",
              "| Event | Call |", "|---|---|",
              "| Dialogue box shows a line ({speaker, line} from story.gd: scenes, barks, stage intros) | "
              "AudioManager.play_voice_line(speaker, line) - looks up md5(speaker + newline + line) in voices/voice_index.json |",
              "| Dialogue advanced / skipped | AudioManager.stop_voice() |",
              "| Tower reward scene (rare_drop) | AudioManager.play_voice(\"rare_drop_<tower_id>\") |", "",
              "Music ducks by 9 dB while a voice plays. Lines that are not rendered yet are silent (returns false).", ""]
    lines += ["## Music", "", "| Event | Id |", "|---|---|"]
    for mid, m in MUSIC.items():
        lines.append(f"| {m['use']} | `{mid}` |")
    lines += ["", "Tower ambience mapping (bible `towers[].theme`): " +
              ", ".join(f"{k} -> `{v}`" for k, v in THEMES.items()), ""]
    (AUDIO / "HOOKS.md").write_text("\n".join(lines), encoding="utf-8")


def write_credits(music_info):
    kenney_used = {}
    for sid, spec in SOUNDS.items():
        for pk in spec["kenney"]:
            kenney_used.setdefault(pk, []).append(sid)
    L = ["# Audio credits and licences", "",
         "Every shipped audio file is either CC0 (public domain dedication) or original synthesis made for this game. "
         "No CC-BY, GPL or 'free for non-commercial' material is used.", "",
         "## Kenney.nl packs (CC0 1.0 - https://creativecommons.org/publicdomain/zero/1.0/)", "",
         "Licence text checked in each pack's `License.txt` (\"License (Creative Commons Zero, CC0)\"). "
         "Credit is not required; given here anyway: **Kenney Vleugels (www.kenney.nl)**.", "",
         "| Pack | Page | Download | Used in (layered and re-mastered) |", "|---|---|---|---|"]
    for pk, ids in kenney_used.items():
        L.append(f"| {pk} | https://kenney.nl/assets/{pk} | {KENNEY_PACKS[pk]} | {', '.join(f'`{i}`' for i in ids)} |")
    L += ["", "## Music - OpenGameArt.org, CC0 only", "",
          "Each page listed **CC0** as its sole licence when checked on 2026-10-21. Files are re-encoded with a loudness "
          "gain only (no edits).", "", "| Id | Track | Author | Page | File | Licence |", "|---|---|---|---|---|---|"]
    for mid, m in MUSIC.items():
        L.append(f"| `{mid}` | {m['title']} | {m['author']} | {m['page']} | {m['url']} | CC0 1.0 |")
    L += ["", "## Original synthesis (this repo, same licence as the game)", "",
          "Made by `game/audio/tools/make_sfx.py` + `dsp.py` (numpy/scipy: noise, FM, additive, granular, "
          "STFT formant filters, convolution reverb with synthetic IRs). Creature roars are fully synthetic (pitch-contoured "
          "harmonic source + formant filter) - no animal recordings.", "",
          "Per output file, the exact CC0 source files layered into it (Kenney paths are inside the pack zips above); "
          "files with no entry are 100% synthesis.", "",
          "| Output file | Source files |", "|---|---|"]
    for sid, spec in SOUNDS.items():
        for p in spec["files"]:
            src = sorted(USED_SOURCES.get(p.name, []))
            L.append(f"| `{p.relative_to(AUDIO).as_posix()}` | {', '.join(src) if src else 'synthesis only (make_sfx.py)'} |")
    L += ["", "## Mastering", "",
          "One-shots: trim < -60 dBFS, max-momentary loudness -16 LUFS (UI -20 LUFS), 4x true-peak limiter at -1 dBTP. "
          "Ambience: integrated -26 LUFS, seamless 30 s loops. Music: integrated -16 LUFS (or less where the -1 dBTP "
          "ceiling binds), gain only.", "",
          "## Voices", "", "Generated with ElevenLabs (premade library voices only, no cloning) by `tools/eleven_voices.py`; "
          "see `voices/CASTING.json`. Subject to the ElevenLabs terms of the account that generated them.", ""]
    if music_info:
        L += ["## Music loop measurements", "", "| Id | Seconds | Gain dB | LUFS | RMS last/first 50 ms | max sample jump at seam |",
              "|---|---|---|---|---|---|"]
        for mid, i in music_info.items():
            L.append(f"| `{mid}` | {i['seconds']} | {i['gain_db']} | {i['lufs']} | {i['seam_rms_end']} / {i['seam_rms_start']} | {i['seam_jump']} |")
        L.append("")
    ov = sorted(p.name for p in OVERRIDES.glob("*.ogg")) if OVERRIDES.exists() else []
    if ov:
        L += ["## ElevenLabs sound generation overrides", "",
              "These files were generated with the ElevenLabs Sound Effects API (tools/eleven_sfx.py) and replace the "
              "synthesis for that file; use is subject to the ElevenLabs terms of the generating account:", "",
              ", ".join(f"`{n}`" for n in ov), ""]
    (AUDIO / "CREDITS.md").write_text("\n".join(L), encoding="utf-8")


SOURCES_JSON = TOOLS / "sources.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="comma list of ids to rebuild (others reuse existing files)")
    ap.add_argument("--skip-music", action="store_true")
    a = ap.parse_args()
    only = set(filter(None, a.only.split(",")))
    print("SFX + ambience:")
    if SOURCES_JSON.exists():
        for k, v in json.loads(SOURCES_JSON.read_text(encoding="utf-8")).items():
            USED_SOURCES.setdefault(k, set(v))
    build_sounds(only)
    SOURCES_JSON.write_text(json.dumps({k: sorted(v) for k, v in sorted(USED_SOURCES.items())}, indent=1) + "\n",
                            encoding="utf-8")
    info = {}
    mi = AUDIO / "tools" / "music_info.json"
    if not a.skip_music:
        print("Music:")
        info = build_music()
        mi.write_text(json.dumps(info, indent=1), encoding="utf-8")
    elif mi.exists():
        info = json.loads(mi.read_text(encoding="utf-8"))
    write_registry()
    write_hooks()
    write_credits(info)
    print("wrote audio_registry.json, HOOKS.md, CREDITS.md")


if __name__ == "__main__":
    main()
