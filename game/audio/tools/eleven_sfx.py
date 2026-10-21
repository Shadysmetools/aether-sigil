"""Upgrade any SFX / ambience id with the ElevenLabs Sound Effects API.

    python -I game/audio/tools/eleven_sfx.py --dry-run                    # list jobs, total seconds; no key needed
    python -I game/audio/tools/eleven_sfx.py --only petrify_shatter       # render candidates to audition
    python -I game/audio/tools/eleven_sfx.py --only petrify_shatter --apply   # adopt them + re-master

Flow: POST https://api.elevenlabs.io/v1/sound-generation per variant -> mp3 cached by content hash in
tools/_eleven_cache/ -> ogg candidates in tools/eleven_out/<file>.ogg (listen to these). --apply copies the
candidates into tools/overrides/, then runs make_sfx.py --only <ids>, which masters overrides exactly like
the synthesised files (trim, loudness, -1 dBTP) and keeps the registry / HOOKS / CREDITS in sync.
Delete tools/overrides/<file>.ogg to go back to the synthesis.

Key: C:/Users/HP/.claude/secrets/elevenlabs.json {"api_key": "..."} (override ELEVENLABS_KEY_FILE). Only ever
sent in the xi-api-key header; never printed or written. Pricing for sound generation is per generation/duration
- check https://elevenlabs.io/pricing before a big run (--dry-run prints the job count and seconds).
"""
import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

TOOLS = pathlib.Path(__file__).resolve().parent
AUDIO = TOOLS.parent
CACHE = TOOLS / "_eleven_cache"
OUT = TOOLS / "eleven_out"
OVERRIDES = TOOLS / "overrides"
KEY_FILE = pathlib.Path(os.environ.get("ELEVENLABS_KEY_FILE", "C:/Users/HP/.claude/secrets/elevenlabs.json"))
API = "https://api.elevenlabs.io/v1/sound-generation"
MODEL = "eleven_text_to_sound_v2"

STYLE = "high-fidelity fantasy game sound effect, clean, no music, no voice"
# id: (prompt, duration_seconds or None, variants, loop)
JOBS = {
    "ui_tap": ("soft crystal UI tap, short glassy click", 0.5, 2, False),
    "ui_confirm": ("bright magical UI confirm chime, two rising crystal notes", 1.0, 1, False),
    "ui_back": ("soft UI back swipe, muted descending click", 0.5, 1, False),
    "ui_locked": ("UI locked denial, dull stone thunk with low buzz", 0.6, 1, False),
    "ui_page": ("parchment page turn, quick", 0.7, 2, False),
    "step_stone": ("single footstep of a small creature on stone tile", 0.5, 4, False),
    "step_grass": ("single footstep on soft grass", 0.5, 4, False),
    "step_water": ("single small splash step in shallow water", 0.6, 4, False),
    "step_snow": ("single footstep crunch on snow", 0.5, 4, False),
    "statue_hop": ("heavy stone statue hops one tile: short stone scrape then solid clunk", 0.8, 3, False),
    "stone_crack_build": ("stone surface cracking with rising crackle and glowing magical hum, building tension", 0.7, 1, False),
    "petrify_shatter": ("stone shell shatters explosively with magical whoosh and crystal sparkle, debris scatter", 1.0, 1, False),
    "monster_awaken_roar_generic": ("fantasy monster roar, mid-size creature awakening, not a real animal", 1.5, 2, False),
    "monster_roar_beast": ("huge fantasy beast bellow, deep and rumbling, dragon-like", 2.0, 2, False),
    "monster_roar_screech": ("fantasy wyvern screech, piercing bird-like cry", 1.4, 2, False),
    "monster_roar_growl": ("short guttural fantasy creature snarl", 1.0, 2, False),
    "monster_roar_chitter": ("small magical insect creature chittering trill", 0.9, 2, False),
    "repetrify": ("living creature turning back into stone: crawling stone crackle settling into a solid thud", 0.8, 1, False),
    "stone_chip_hit": ("hit on a stone statue, chips of rock flying", 0.6, 4, False),
    "statue_crumble": ("stone statue crumbles into rubble, cascading rocks", 2.0, 1, False),
    "summon_burst": ("crystal capsule opens, magical crystal burst with shimmering bells", 2.0, 1, False),
    "hit_melee": ("creature melee attack impact, punchy body hit", 0.5, 5, False),
    "hit_heavy": ("heavy creature impact with low boom", 1.0, 3, False),
    "hit_critical": ("critical hit: massive impact, metallic ring and glass sparkle", 1.5, 2, False),
    "defend_shield": ("magical energy shield raised, humming force field", 1.2, 1, False),
    "miss_whoosh": ("fast attack whoosh that misses", 0.5, 3, False),
    "ko_dissolve": ("creature faints and dissolves into sparkling motes", 2.0, 1, False),
    "level_up": ("level up jingle, ascending bright magical arpeggio", 2.0, 1, False),
    "evolve_build": ("magical energy charging up, rising whirl, 2.5 seconds", 2.5, 1, False),
    "evolve_burst": ("radiant evolution reveal, triumphant magical burst with choir shimmer", 2.5, 1, False),
    "fusion_merge": ("two magical energies spiral together and fuse in a bright burst", 2.2, 1, False),
    "victory_sting": ("short orchestral victory fanfare sting, brass and timpani", 3.0, 1, False),
    "defeat_sting": ("short sad orchestral defeat sting, descending strings", 3.5, 1, False),
    "sigil_damage": ("large magic crystal cracks under attack, deep boom and resonant ring", 1.8, 2, False),
    "capsule_node": ("magical node powers on, rising hum and chime", 1.5, 1, False),
    "cast_fire": ("fire spell cast, whoosh of flames igniting and roaring", 1.8, 1, False),
    "cast_water": ("water spell cast, surging wave and splash", 1.8, 1, False),
    "cast_wind": ("wind spell cast, swirling gust with whistle", 1.8, 1, False),
    "cast_earth": ("earth spell cast, ground rumble and rocks erupting", 1.8, 1, False),
    "cast_thunder": ("lightning spell cast, electric crackle then thunder crack", 2.0, 1, False),
    "cast_ice": ("ice spell cast, freezing crystals forming with icy chimes", 1.8, 1, False),
    "cast_wood": ("nature spell cast, vines growing, leaves rustling, wooden creak", 1.8, 1, False),
    "cast_tech": ("sci-fi tech ability, servo whirr, digital beeps and laser", 1.5, 1, False),
    "cast_light": ("holy light spell, angelic choir swell and bright shimmer", 2.5, 1, False),
    "cast_dark": ("dark magic spell, ominous low whoosh and whispers", 2.5, 1, False),
    "cast_arcane": ("arcane magic spell, mystical warbling bells and sparkle", 2.2, 1, False),
    "cast_space": ("cosmic space magic, deep sub swell, phasing stars and echoes", 2.5, 1, False),
    "amb_nature": ("ambience of an overgrown sky garden: gentle wind, leaves, distant birds", 30, 1, True),
    "amb_fire": ("ambience of a volcanic forge fortress: low fire roar, embers crackling", 30, 1, True),
    "amb_water": ("ambience of a glass citadel over water: flowing water, drips", 30, 1, True),
    "amb_ice": ("ambience of a frozen tower: cold howling wind, ice tinkles", 30, 1, True),
    "amb_metal": ("ambience of a mechanical labyrinth: machinery hum, ticking gears, distant clanks", 30, 1, True),
    "amb_wind": ("ambience of floating sky ruins: strong gusting wind, whistling stone", 30, 1, True),
    "amb_dark": ("ambience of an eclipse shrine: dark low drone, eerie breathing air", 30, 1, True),
    "amb_ancient": ("ambience of a sunken archive: cave room tone, water drips, faint chimes", 30, 1, True),
    "amb_space": ("ambience of an astral observatory: deep space hum, soft sparkles", 30, 1, True),
    "amb_crystal": ("ambience of a crystal sanctum: resonant crystal hum, gentle chimes", 30, 1, True),
    "amb_aether": ("ambience of an unstable magic rift: warbling energy, crackles", 30, 1, True),
    "amb_mixed": ("ambience of a sun forge throne: furnace roar with crystal hum", 30, 1, True),
}


def file_names(sid, variants):
    return [f"{sid}.ogg"] if variants == 1 else [f"{sid}_{v + 1:02d}.ogg" for v in range(variants)]


def api_key():
    try:
        k = json.loads(KEY_FILE.read_text(encoding="utf-8")).get("api_key", "")
    except (OSError, ValueError):
        k = ""
    if not k:
        sys.exit(f"No ElevenLabs key: expected {KEY_FILE} with {{\"api_key\": \"...\"}}. (--dry-run works without one.)")
    return k


def generate(key, body):
    req = urllib.request.Request(API + "?output_format=mp3_44100_128", data=json.dumps(body).encode(), method="POST",
                                 headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            msg = e.read()[:300].decode("utf-8", "replace")
            if e.code in (429, 500, 502, 503) and attempt < 4:
                time.sleep(2 ** attempt * 3)
                continue
            sys.exit(f"sound-generation -> HTTP {e.code}: {msg}")
        except urllib.error.URLError as e:
            if attempt < 4:
                time.sleep(3)
                continue
            sys.exit(f"sound-generation -> network error: {e.reason}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", default="", help="comma list of ids (default: all jobs)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--apply", action="store_true", help="adopt rendered candidates for --only ids and re-master")
    ap.add_argument("--influence", type=float, default=0.45, help="prompt_influence 0..1")
    ap.add_argument("--seed-tag", default="v1", help="change to get fresh takes (part of the cache key)")
    a = ap.parse_args()
    ids = [i for i in a.only.split(",") if i] or list(JOBS)
    unknown = [i for i in ids if i not in JOBS]
    if unknown:
        sys.exit(f"unknown ids: {unknown}")

    if a.apply:
        OVERRIDES.mkdir(parents=True, exist_ok=True)
        for sid in ids:
            for name in file_names(sid, JOBS[sid][2]):
                src = OUT / name
                if not src.exists():
                    sys.exit(f"no candidate {src} - render it first")
                shutil.copyfile(src, OVERRIDES / name)
        subprocess.run([sys.executable, "-I", str(TOOLS / "make_sfx.py"), "--skip-music", "--only", ",".join(ids)], check=True)
        return

    n = sum(JOBS[i][2] for i in ids)
    secs = sum((JOBS[i][1] or 5) * JOBS[i][2] for i in ids)
    print(f"{len(ids)} ids, {n} generations, {secs:.0f} s of audio requested")
    if a.dry_run:
        for i in ids:
            p, d, v, loop = JOBS[i]
            print(f"  {i:30s} x{v} {d}s{' loop' if loop else ''}  \"{p}\"")
        return
    key = api_key()
    CACHE.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    for sid in ids:
        prompt, dur, variants, loop = JOBS[sid]
        for v, name in enumerate(file_names(sid, variants)):
            body = {"text": f"{prompt}. {STYLE}", "model_id": MODEL, "prompt_influence": a.influence}
            if dur:
                body["duration_seconds"] = float(min(max(dur, 0.5), 30))
            if loop:
                body["loop"] = True
            h = hashlib.sha256(json.dumps([body, v, a.seed_tag], sort_keys=True).encode()).hexdigest()[:24]
            mp3 = CACHE / f"{h}.mp3"
            if not mp3.exists():
                mp3.write_bytes(generate(key, body))
                print(f"  generated {name}")
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(mp3), "-c:a", "libvorbis", "-q:a", "6",
                            str(OUT / name)], check=True)
    print(f"candidates in {OUT} - listen, then rerun with --only <ids> --apply")


if __name__ == "__main__":
    main()
