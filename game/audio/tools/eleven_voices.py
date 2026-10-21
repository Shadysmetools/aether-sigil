"""ElevenLabs voice pipeline for Aether Sigil.

Builds the full list of spoken lines from the same data the game reads (story.json, the bible's stage
dialogue and global sample lines, dialogue_triggers.json rules), casts every speaker to a voice from
ElevenLabs' PUBLIC PREMADE library (picked by description at run time via GET /v1/voices - never a
cloned or real-person voice), and renders one Ogg Vorbis per line into
game/audio/voices/<speaker_slug>/<line_id>.ogg.

    python -I game/audio/tools/eleven_voices.py --dry-run                # no key, no network: counts + credits
    python -I game/audio/tools/eleven_voices.py --speaker Pell --limit 3 # first real test, ~100 credits
    python -I game/audio/tools/eleven_voices.py                          # everything (cached reruns cost 0)
    python -I game/audio/tools/eleven_voices.py --rival-globals generic  # 1 shared voice for rival barks

Key: C:/Users/HP/.claude/secrets/elevenlabs.json  {"api_key": "..."}  (override: ELEVENLABS_KEY_FILE).
The key is only ever placed in the xi-api-key request header. It is never printed, logged or written.

Outputs
  voices/CASTING.json     speaker -> role, description, voice preferences, chosen voice (editable; a
                          chosen voice_id is kept on reruns - delete it to re-pick)
  voices/LINES.json       every line: line_id, speaker, text, key, source (written on every run)
  voices/voice_index.json {by_id: line_id -> res path, by_key: md5(speaker+"\\n"+line) -> line_id}
                          ONLY lines whose .ogg exists; AudioManager reads it.
  voices/_cache/          raw mp3 per content hash + manifest (gdignored; delete to force re-render)

Cache key = sha256(voice_id | model | voice_settings | post-process | spoken text). A rerun only bills
lines whose key changed.
"""
import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

TOOLS = pathlib.Path(__file__).resolve().parent
AUDIO = TOOLS.parent
GAME = AUDIO.parent
DATA = GAME / "data"
VOICES = AUDIO / "voices"
CACHE = VOICES / "_cache"
KEY_FILE = pathlib.Path(os.environ.get("ELEVENLABS_KEY_FILE", "C:/Users/HP/.claude/secrets/elevenlabs.json"))
API = "https://api.elevenlabs.io"
DEFAULT_MODEL = "eleven_multilingual_v2"
CREDITS_PER_CHAR = {"eleven_multilingual_v2": 1.0, "eleven_v3": 1.0, "eleven_flash_v2_5": 0.5,
                    "eleven_turbo_v2_5": 0.5}  # ElevenLabs pricing page, 2026; confirm before buying a plan
DEFAULT_SETTINGS = {"stability": 0.45, "similarity_boost": 0.8, "style": 0.25, "use_speaker_boost": True}
VOICE_LUFS = -18.0


# ------------------------------------------------------------------ line inventory

def slug(s):
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


def key_of(speaker, line):
    """Must match AudioManager.voice_key(): md5 of UTF-8 'speaker\\nline'."""
    return hashlib.md5(f"{speaker}\n{line}".encode("utf-8")).hexdigest()


def tts_text(line):
    t = line.replace("\ufffd", " \u2014 ")  # data has U+FFFD where an em dash was lost
    return re.sub(r"\s+", " ", t).strip()


def split_line(raw, fallback):
    cut = raw.find(": ")
    return (raw[:cut], raw[cut + 2:]) if cut > 0 else (fallback, raw)


def load_json(p):
    return json.loads(pathlib.Path(p).read_text(encoding="utf-8"))


def inventory(rival_globals="per-rival"):
    story = load_json(DATA / "story.json")
    bible = load_json(DATA / "AETHER_SIGIL_MASTER_GAME_BIBLE.json")
    hero = story.get("protagonist", {}).get("name", "Hero")
    lines, seen = [], {}

    def add(line_id, speaker, text, source, group):
        k = key_of(speaker, text)
        if k in seen:  # same speaker + same words -> one file, many triggers
            seen[k]["sources"].append(source)
            return
        rec = dict(line_id=line_id, speaker=speaker, text=text, tts=tts_text(text), key=k, sources=[source], group=group)
        seen[k] = rec
        lines.append(rec)

    for part in ("prologue", "finale", "epilogue"):
        for i, ln in enumerate(story.get(part, []), 1):
            add(f"{part}_{i:02d}", ln["speaker"], ln["line"], f"story.{part}[{i - 1}]", "story")
    for tw in story.get("towers", []):
        tid = str(tw["tower_id"])
        for part in ("arrival", "pre_boss", "post_boss"):
            for i, ln in enumerate(tw.get(part, []), 1):
                add(f"{part}_{tid}_{i:02d}", ln["speaker"], ln["line"], f"story.towers[{tid}].{part}[{i - 1}]", "story")

    samples = bible["dialogue_system"]["sample_lines"]
    for n in (1, 3, 5):  # Hero barks
        who, text = split_line(samples[n - 1], "")
        add(f"global_{n}", hero, text, f"global.{n}", "hero_bark")

    opponents, boss_opponents = [], []
    for tw in bible["towers"]:
        for lv in tw["levels"]:
            sid, opp = lv["stage_id"], lv["opponent"]
            if opp not in opponents:
                opponents.append(opp)
            is_boss = sid.endswith("L10") or bool(lv.get("boss"))
            if is_boss and opp not in boss_opponents:
                boss_opponents.append(opp)
            for k in ("intro", "midbattle", "defeat", "boss_intro"):
                if k == "boss_intro" and not is_boss:
                    continue  # identical on all 120 stages; only reachable on L10 (dialogue_triggers.json)
                raw = lv.get("dialogue", {}).get(k)
                if raw:
                    sp, text = split_line(raw, opp)
                    add(f"stage_{sid}_{k}", sp, text, f"stage.{sid}.{k}", "stage")
        # rare_drop: "You obtained the {reward}!" (template) - narrated
        tpl = load_json(DATA / "dialogue_triggers.json")["types"]["rare_drop"]["template"]
        add(f"rare_drop_{tw['tower_id']}", "Narrator", tpl.replace("{reward}", tw["tower_reward"]),
            f"template.rare_drop.{tw['tower_id']}", "narration")

    if rival_globals != "skip":
        for n in (2, 4, 6):  # Rival barks: 2 = defeat gloat, 4 = first KO bark (every stage), 6 = after L10 win
            who, text = split_line(samples[n - 1], "")
            pool = boss_opponents if n == 6 else opponents
            if rival_globals == "generic":
                add(f"global_{n}_rival", "Rival", text, f"global.{n}", "rival_bark")
                rec = seen[key_of("Rival", text)]
                rec["aliases"] = [key_of(o, text) for o in pool]
            else:
                for o in pool:
                    add(f"global_{n}_{slug(o)}", o, text, f"global.{n}", "rival_bark")
    return lines


# ------------------------------------------------------------------ casting

MAIN = {
    "Narrator": ("narrator", "adult", "male", "warm, wonder-filled storyteller; unhurried, gentle gravitas",
                 "neutral / british", ["narration", "calm", "deep", "warm", "storyteller"]),
    "Elio": ("protagonist summoner", "young (17-20)", "male", "earnest, brave, kind; quietly determined, never smug",
             "neutral american", ["young", "friendly", "conversational", "warm"]),
    "Pell": ("Elio's small hatchling monster companion", "child-like creature", "female",
             "tiny, bright, simple sentences, curious, brave-but-scared; speaks of itself in third person",
             "neutral", ["young", "playful", "cute", "animated", "childish"]),
    "Maren Oake": ("Elio's guardian / mentor on Lowmere isle", "older (55-65)", "female",
                   "steady, wise, tender but firm; a craftswoman, not a queen", "british / soft rural",
                   ["mature", "calm", "warm", "wise", "middle aged", "old"]),
    "Kess Varrow": ("rival summoner who becomes a friend", "young (17-20)", "female",
                    "fast-talking, competitive, sardonic, secretly warm", "american",
                    ["young", "confident", "energetic", "sassy"]),
    "Rival": ("generic stage rival (only with --rival-globals generic)", "young adult", "male",
              "cocky, taunting", "neutral", ["confident", "young"]),
}
CHAMPIONS = {  # tower_boss per bible tower: (gender, age, tone keywords)
    "Lyra Quill": ("female", "young adult", "bubbly, encouraging nature keeper; tower 01 (Nature)", ["upbeat", "friendly", "young"]),
    "Varen Lux": ("male", "adult", "proud, fiery, theatrical forge-master; tower 02 (Fire)", ["intense", "confident", "strong"]),
    "Niko Ardent": ("male", "young adult", "cool, fluid, playful tide champion; tower 03 (Water)", ["casual", "calm", "young"]),
    "Rhea Volt": ("female", "adult", "crisp, disciplined, ice-cold precision; tower 04 (Ice)", ["crisp", "confident", "serious"]),
    "Renn Calder": ("male", "middle aged", "gruff engineer, dry humour; tower 05 (Metal)", ["gruff", "deep", "middle aged"]),
    "Zara Nyx": ("female", "young adult", "restless, wild storm summoner; tower 06 (Wind)", ["energetic", "intense", "young"]),
    "Cira Dawn": ("female", "adult", "hushed, eerie, kind beneath the dark; tower 07 (Dark)", ["soft", "whispery", "mysterious"]),
    "Tarin Moss": ("male", "old", "slow, scholarly archivist; tower 08 (Ancient)", ["old", "wise", "calm"]),
    "Silas Wren": ("male", "old", "dreamy stargazer, knowing, odd; tower 09 (Space)", ["old", "raspy", "calm", "wise"]),
    "Sera Vale": ("female", "adult", "serene, regal crystal keeper; tower 10 (Crystal)", ["elegant", "calm", "mature"]),
    "Mako Reed": ("male", "young adult", "jittery, brilliant rift-walker; tower 11 (Aether)", ["energetic", "nervous", "young"]),
    "Ari Zephyr": ("female", "adult", "final champion of the Sunforge: radiant, commanding, generous; tower 12 (Mixed)",
                   ["authoritative", "strong", "confident", "mature"]),
}
FEMALE_FIRST = {"Ayla", "Cira", "Ilya", "Juno", "Kira", "Lira", "Lyra", "Mira", "Noa", "Rhea", "Sera", "Sora", "Tessa",
                "Veya", "Zara", "Ari"}
SURNAME_TONE = {  # stage rivals: tone from their surname flavour
    "Ardent": "hot-headed", "Ashen": "smouldering, dry", "Bloom": "cheerful", "Calder": "methodical", "Cross": "stern",
    "Dawn": "bright", "Dray": "laconic", "Flint": "sharp", "Frost": "cool, clipped", "Grave": "grim", "Hollow": "quiet, eerie",
    "Lux": "showy", "Moss": "easygoing", "Nyx": "sly", "Quill": "clever", "Reed": "nervy", "Rook": "calculating",
    "Rune": "cryptic", "Slate": "flat, stoic", "Storm": "loud", "Vale": "polite", "Volt": "snappy", "Voss": "confident",
    "Wren": "whimsical", "Zephyr": "airy, breezy",
}


def default_casting(lines):
    speakers = []
    for ln in lines:
        if ln["speaker"] not in speakers:
            speakers.append(ln["speaker"])
    out = {}
    for sp in speakers:
        if sp in MAIN:
            role, age, gender, tone, accent, kw = MAIN[sp]
            tier = "main"
        elif sp in CHAMPIONS:
            gender, age, tone, kw = CHAMPIONS[sp]
            role, accent, tier = "tower champion", "any", "champion"
        else:
            first, _, last = sp.partition(" ")
            gender = "female" if first in FEMALE_FIRST else "male"
            age, role, accent, tier = "young adult", "stage rival summoner", "any", "rival"
            tone = f"{SURNAME_TONE.get(last, 'confident')}, competitive"
            kw = [w.strip() for w in re.split(r"[ ,]+", SURNAME_TONE.get(last, "confident")) if w] + ["young"]
        out[sp] = {
            "slug": slug(sp), "role": role, "tier": tier,
            "description": {"age": age, "gender": gender, "tone": tone, "accent": accent},
            "match": {"gender": gender, "keywords": kw},
            "voice_id": None, "voice_name": None,
            "voice_settings": dict(DEFAULT_SETTINGS),
            "post_pitch_semitones": 4.0 if sp == "Pell" else 0.0,
        }
    if "Pell" in out:
        out["Pell"]["voice_settings"]["style"] = 0.5
    return out


def load_casting(lines):
    path = VOICES / "CASTING.json"
    fresh = default_casting(lines)
    if path.exists():
        old = load_json(path).get("speakers", {})
        for sp, rec in fresh.items():
            if sp in old:  # keep hand edits and chosen voices
                rec.update(old[sp])
    return fresh


def save_casting(cast):
    doc = {"_doc": "Speaker -> voice. Generated by tools/eleven_voices.py; hand edits are kept. voice_id is picked from "
                   "the ElevenLabs PREMADE library by 'match' (gender + keywords vs the voice labels) on first real run, "
                   "then frozen here. Clear voice_id to re-pick. post_pitch_semitones is applied with ffmpeg after TTS.",
           "speakers": cast}
    VOICES.mkdir(parents=True, exist_ok=True)
    (VOICES / "CASTING.json").write_text(json.dumps(doc, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


# ------------------------------------------------------------------ API

def api_key():
    try:
        k = load_json(KEY_FILE).get("api_key", "")
    except (OSError, ValueError):
        k = ""
    if not k:
        sys.exit(f"No ElevenLabs key: expected {KEY_FILE} with {{\"api_key\": \"...\"}}. (--dry-run works without one.)")
    return k


def request(method, path, key, body=None, accept="application/json"):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": accept})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            msg = e.read()[:300].decode("utf-8", "replace")
            if e.code in (429, 500, 502, 503) and attempt < 4:
                time.sleep(2 ** attempt * 3)
                continue
            sys.exit(f"ElevenLabs {method} {path} -> HTTP {e.code}: {msg}")
        except urllib.error.URLError as e:
            if attempt < 4:
                time.sleep(3)
                continue
            sys.exit(f"ElevenLabs {method} {path} -> network error: {e.reason}")


def premade_voices(key):
    vs = json.loads(request("GET", "/v1/voices", key))["voices"]
    vs = [v for v in vs if v.get("category") == "premade"]
    return sorted(vs, key=lambda v: v["voice_id"])


def voice_text(v):
    lab = v.get("labels") or {}
    return " ".join([v.get("name", ""), v.get("description") or ""] + [str(x) for x in lab.values()]).lower()


def assign_voices(cast, voices):
    """Deterministic pick: gender must match; keyword hits score; main cast + champions get exclusive voices where
    possible; rivals spread across the remaining pool (penalty per reuse)."""
    used = {}
    exclusive = set()
    for sp, rec in cast.items():
        if rec.get("voice_id"):
            used[rec["voice_id"]] = used.get(rec["voice_id"], 0) + 1
            if rec["tier"] in ("main", "champion"):
                exclusive.add(rec["voice_id"])
    order = sorted(cast, key=lambda s: {"main": 0, "champion": 1, "rival": 2}[cast[s]["tier"]])
    for sp in order:
        rec = cast[sp]
        if rec.get("voice_id"):
            continue
        best, best_s = None, -1e9
        for v in voices:
            lab = v.get("labels") or {}
            g = str(lab.get("gender", "")).lower()
            s = 0.0
            if g and g != rec["match"]["gender"]:
                s -= 100
            txt = voice_text(v)
            s += sum(2 for kw in rec["match"]["keywords"] if kw.lower() in txt)
            age = str(lab.get("age", "")).lower()
            want = rec["description"]["age"]
            if ("old" in want and "old" in age) or ("young" in want and "young" in age) or ("middle" in want and "middle" in age):
                s += 3
            if v["voice_id"] in exclusive:
                s -= 50
            s -= 4 * used.get(v["voice_id"], 0)
            if s > best_s:
                best, best_s = v, s
        if best is None:
            continue
        rec["voice_id"], rec["voice_name"] = best["voice_id"], best.get("name")
        used[best["voice_id"]] = used.get(best["voice_id"], 0) + 1
        if rec["tier"] in ("main", "champion"):
            exclusive.add(best["voice_id"])


def render_hash(rec, cast_rec, model):
    blob = json.dumps([cast_rec["voice_id"], model, cast_rec["voice_settings"], cast_rec.get("post_pitch_semitones", 0),
                       rec["tts"]], sort_keys=True)
    return hashlib.sha256(blob.encode()).hexdigest()[:24]


def to_ogg(mp3, ogg, semitones):
    af = []
    if semitones:
        r = 2 ** (semitones / 12)
        af.append(f"asetrate={int(44100 * r)},aresample=44100,atempo={1 / r:.5f}")
    trim = "silenceremove=start_periods=1:start_threshold=-55dB"  # ends only - keep the pauses inside a line
    af += [trim, "areverse", trim, "areverse",
           f"loudnorm=I={VOICE_LUFS}:TP=-1.5:LRA=11", "aresample=44100"]
    ogg.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(mp3), "-af", ",".join(af), "-ac", "1", "-ar", "44100",
                    "-c:a", "libvorbis", "-q:a", "5", "-map_metadata", "-1", str(ogg)], check=True)


# ------------------------------------------------------------------ index + report

def write_lines(lines):
    VOICES.mkdir(parents=True, exist_ok=True)
    (VOICES / "LINES.json").write_text(json.dumps(
        {"_doc": "Every voiced line (generated by tools/eleven_voices.py). key = md5(speaker+'\\n'+line).",
         "lines": [{k: ln.get(k, []) for k in ("line_id", "speaker", "text", "key", "aliases", "sources", "group")}
                   for ln in lines]},
        indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


def write_index(lines, cast):
    by_id, by_key = {}, {}
    for ln in lines:
        p = VOICES / cast[ln["speaker"]]["slug"] / f"{ln['line_id']}.ogg"
        if p.exists():
            by_id[ln["line_id"]] = "res://" + p.relative_to(GAME).as_posix()
            by_key[ln["key"]] = ln["line_id"]
            for a in ln.get("aliases", []):
                by_key[a] = ln["line_id"]
    (VOICES / "voice_index.json").write_text(json.dumps({"by_id": by_id, "by_key": by_key}, indent=1) + "\n", encoding="utf-8")
    return len(by_id)


def report(lines, model, title):
    rate = CREDITS_PER_CHAR.get(model, 1.0)
    per = {}
    for ln in lines:
        per.setdefault(ln["speaker"], [0, 0])
        per[ln["speaker"]][0] += 1
        per[ln["speaker"]][1] += len(ln["tts"])
    groups = {}
    for ln in lines:
        g = groups.setdefault(ln["group"], [0, 0])
        g[0] += 1
        g[1] += len(ln["tts"])
    total = sum(v[1] for v in per.values())
    print(f"\n{title}: {len(lines)} lines, {len(per)} speakers, {total:,} characters "
          f"-> ~{int(total * rate):,} credits on {model} ({rate} credit/char)")
    print("  by group: " + ", ".join(f"{g} {n} lines/{c:,} ch" for g, (n, c) in groups.items()))
    top = sorted(per.items(), key=lambda kv: -kv[1][1])
    print("  top speakers: " + ", ".join(f"{s} {c:,}" for s, (n, c) in top[:12]))
    return total


# ------------------------------------------------------------------ main

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true", help="count characters + credits; no key, no network")
    ap.add_argument("--speaker", action="append", default=[], help="only these speakers (name or slug, repeatable)")
    ap.add_argument("--limit", type=int, default=0, help="render at most N lines (after filters)")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--rival-globals", choices=["per-rival", "generic", "skip"], default="per-rival",
                    help="rival barks (global 2/4/6): one render per stage rival, one shared 'Rival' voice, or none")
    a = ap.parse_args()

    lines = inventory(a.rival_globals)
    cast = load_casting(lines)
    write_lines(lines)
    if a.dry_run:
        save_casting(cast)
        report(lines, a.model, "ALL lines")
        for alt in ("generic", "skip"):
            if alt != a.rival_globals:
                report(inventory(alt), a.model, f"with --rival-globals {alt}")
    sel = lines
    if a.speaker:
        want = {s.lower() for s in a.speaker} | {slug(s) for s in a.speaker}
        sel = [ln for ln in sel if ln["speaker"].lower() in want or slug(ln["speaker"]) in want]
    CACHE.mkdir(parents=True, exist_ok=True)
    (CACHE / ".gdignore").touch()
    manifest_p = CACHE / "manifest.json"
    manifest = load_json(manifest_p) if manifest_p.exists() else {}

    if a.dry_run:
        # what a real run would bill now = selected lines whose cached render is missing
        todo = [ln for ln in sel if not (VOICES / cast[ln["speaker"]]["slug"] / f"{ln['line_id']}.ogg").exists()]
        if a.limit:
            todo = todo[: a.limit]
        ch = sum(len(ln["tts"]) for ln in todo)
        print(f"\nThis selection would render {len(todo)} lines, {ch:,} characters, "
              f"~{int(ch * CREDITS_PER_CHAR.get(a.model, 1.0)):,} credits (cached lines excluded).")
        n = write_index(lines, cast)
        print(f"voice_index.json: {n} rendered lines indexed. CASTING.json / LINES.json in {VOICES}")
        return

    key = api_key()
    if any(not cast[ln["speaker"]].get("voice_id") for ln in sel):
        voices = premade_voices(key)
        if not voices:
            sys.exit("GET /v1/voices returned no premade voices.")
        assign_voices(cast, voices)
        save_casting(cast)
    done = billed = 0
    for ln in sel:
        if a.limit and done >= a.limit:
            break
        c = cast[ln["speaker"]]
        h = render_hash(ln, c, a.model)
        ogg = VOICES / c["slug"] / f"{ln['line_id']}.ogg"
        mp3 = CACHE / f"{h}.mp3"
        if manifest.get(ln["line_id"]) == h and ogg.exists():
            continue
        if not mp3.exists():
            body = {"text": ln["tts"], "model_id": a.model, "voice_settings": c["voice_settings"]}
            audio = request("POST", f"/v1/text-to-speech/{c['voice_id']}?output_format=mp3_44100_128", key, body,
                            accept="audio/mpeg")
            mp3.write_bytes(audio)
            billed += len(ln["tts"])
        to_ogg(mp3, ogg, c.get("post_pitch_semitones", 0))
        manifest[ln["line_id"]] = h
        manifest_p.write_text(json.dumps(manifest, indent=1), encoding="utf-8")
        done += 1
        print(f"  [{done}] {ln['speaker']}: {ln['line_id']}")
    n = write_index(lines, cast)
    print(f"rendered {done} lines ({billed:,} new characters billed); voice_index.json now lists {n} lines")


if __name__ == "__main__":
    main()
