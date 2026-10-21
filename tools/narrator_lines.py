"""Narrator character pass (Vellum) + scene mood tags.  Run: python tools/narrator_lines.py   (idempotent)

* Rewrites every speaker=="Narrator" line in data/story.json in Vellum's voice (positions/ids unchanged,
  line counts unchanged) and tags it with an explicit "mood".
* Tags every other story line with a "mood" from the same keyword heuristic the game uses at runtime
  (game/scripts/ui/scene_dialogue.gd infer_mood; the story test asserts the two agree).
* Writes data/narrator.json (name, mood->expression table, reactive barks).
* Mirrors both files into game/data/. The bible and the CSVs have no Narrator lines (checked), so they are untouched.
* Rewrites the rare_drop template in game/data/dialogue_triggers.json (the Narrator announces rewards).
"""
import json, os, re

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
D = os.path.join(ROOT, "data")
G = os.path.join(ROOT, "game", "data")

NAME = "Vellum"
TITLE = "the Archivist of the Aether Sigil"

# ---- moods -> expression (7 shared expressions; the Narrator art has 4 and folds the rest, see ui_art.gd)
MOOD_EXPRESSION = {
    "neutral": "neutral", "dry": "neutral", "calm": "neutral", "wistful": "neutral",
    "amused": "amused", "wry": "amused", "delighted": "amused", "fond": "amused", "proud": "amused",
    "grave": "grave", "solemn": "grave", "ominous": "grave", "rueful": "grave", "uneasy": "grave", "tense": "grave",
    "awed": "awed", "wonder": "awed", "hushed": "awed", "stunned": "awed",
    "angry": "angry", "determined": "determined", "resolute": "determined", "sad": "sad", "sorrow": "sad",
}

# ---- Narrator story lines: (section, tower_id or None, index) -> (mood, text)
N = {}


def put(sec, tid, idx, mood, text):
    N[(sec, tid, idx)] = (mood, text)


put("prologue", None, 0, "wistful", "Allow me. There was one crystal, once, holding every realm under a single sky. It was called the Aether Sigil.")
put("prologue", None, 1, "ominous", "Then it was broken. Twelve prisms scattered, the realms drifted apart, and the sky has been cracking ever since.")
put("prologue", None, 2, "rueful", "Twelve keepers raised twelve towers around the prisms. An age ago. The towers are tired now. So, if I may say, am I.")
put("prologue", None, 12, "wry", "Twelve towers, twelve keepers, and one Summoner who means to wake the world through what he summons. Noted.")
ARR = {
    "01": ("wry", "The Verdant Spire. Living bridges creak between terraces, and pollen storms climb the stairs like weather. Mind the sneezing."),
    "02": ("dry", "The Ember Bastion. Lava runs in channels under collapsing platforms, and the heat vents breathe on a count. Count along."),
    "03": ("amused", "The Tideglass Citadel. Flood gates turn with the tide, and every corridor is glass beneath moving water. Do not look down. Do look down."),
    "04": ("tense", "The Frost Meridian. Frozen stairs climb through blizzard zones, and brittle ice cracks under anything that waits. So, do not wait."),
    "05": ("wry", "The Iron Labyrinth. Walls slide on rails, magnetic fields drag at metal, and every corridor resets on a timer. I have never trusted timers."),
    "06": ("wonder", "The Storm Crown. Platforms drift along gust lanes, and lightning rods hum before every strike. Listen for the hum, Summoner."),
    "07": ("uneasy", "The Obsidian Eclipse. Shadow tiles swallow the light, teleport gates blink open, and nothing is where it looks. I dislike this place."),
    "08": ("hushed", "The Sunken Archive. Ruins rest under still water, and relic switches open chambers sealed for ages. ...I know these shelves."),
    "09": ("wonder", "The Astral Observatory. Platforms orbit a central spire, gravity thins near the star gates, and the stars move. They are not meant to."),
    "10": ("uneasy", "The Crystal Sanctum. Prism bridges carry beams of light, and resonance nodes ring when power passes. Some of that sound is old. Some is mine."),
    "11": ("solemn", "The Rift Frontier. Portals open without warning, tiles phase in and out, and the great crack fills the sky. Look at it. Please."),
    "12": ("solemn", "The Sunforge Throne. Roots, lava, glass, ice, rails, wind, shadow, ruins, stars, crystal and rifts, all at once. The margin ends here, Summoner."),
}
for _tid, (_m, _t) in ARR.items():
    put("arrival", _tid, 0, _m, _t)
put("post_boss", "01", 4, "fond", "The Nature Prism settles into the Player Sigil. A new facet lights, green as new leaves. One of twelve. Noted, with relief.")
put("post_boss", "04", 4, "fond", "Four facets glow in the Player Sigil. Far below, Lowmere stops sinking. For now. I shall allow myself to be glad.")
put("post_boss", "08", 4, "rueful", "Eight facets. The Player Sigil is heavy now, and warm. Lowmere has risen half a span. I am, privately, afraid of nine.")
put("finale", None, 0, "wonder", "In the Sunforge, eleven facets burn in the Player Sigil. The twelfth, the Mixed Prism, rises in every color at once. I did not write this.")
put("finale", None, 1, "delighted", "One by one, the keepers arrive: Lyra, Varen, Niko, Rhea, Renn, Zara, Cira, Tarin, Silas, Sera and Mako. Unrehearsed. Delightful.")
put("finale", None, 12, "solemn", "I wrote the first ending, you see. It was perfect, and so it broke. This one I did not write: a ring of light, and the Sigil whole.")
put("finale", None, 13, "fond", "Above them, the crack in the sky begins, slowly, to close. And I am out of things to say. Thank you, Elio.")
put("epilogue", None, 0, "fond", "The Prism Realms still float apart. But now they drift together, held by twelve towers whose doors stay open. A new page begins.")
put("epilogue", None, 5, "fond", "Collect. Command. Evolve. Conquer. And when the worlds call again, answer. I will be here, pen down, listening.")

# ---- reactive barks (event -> 3 lines by arc phase: early T1-4, mid T5-8, late T9-12)
PHASES = [{"id": "early", "towers": [1, 4]}, {"id": "mid", "towers": [5, 8]}, {"id": "late", "towers": [9, 12]}]
EVENTS = {
    "battle_start": [("wry", "Another page begins. Do try to survive it, Summoner."), ("dry", "Positions, everyone. I shall keep the margins clear."), ("fond", "Begin, Elio. I have stopped predicting how this ends.")],
    "first_crack": [("wry", "A Vessel cracks. A frightful word, 'crack'. Carry on."), ("delighted", "There. A Vessel opens, and something steps out. Lovely."), ("wonder", "Cracked, and still whole. I did not know that was possible.")],
    "big_hit": [("uneasy", "Ah. That will leave a mark in the margin."), ("tense", "A heavy blow. Breathe. The page is not torn."), ("tense", "That hurt to watch. Steady, Elio.")],
    "ko": [("rueful", "A monster falls. Noted. Gently noted."), ("rueful", "One of them down. The story permits second drafts."), ("resolute", "Down, not out. Nothing ends on a single line.")],
    "vessel_broken": [("solemn", "A Vessel breaks. It is only a Vessel. ...Noted."), ("solemn", "A Vessel breaks. It is never only a Vessel."), ("rueful", "Broken things can be mended. I speak from experience.")],
    "low_sigil_hp": [("solemn", "The Sigil dims, Summoner. I would rather not narrate that ending."), ("tense", "The Sigil is low. Elio, please. I have written that ending once."), ("resolute", "Hold the light, Elio. Hold it for all of us.")],
    "victory": [("amused", "Victory. I shall pretend I expected it."), ("amused", "Well fought. I have stopped pretending to expect it."), ("delighted", "Won, and not a word of it mine. Splendid.")],
    "defeat": [("rueful", "A page lost. Turn it, and try again."), ("resolute", "Defeat is only a draft. Revise."), ("resolute", "We lose this page, not the book. Again, Elio.")],
    "evolution": [("wonder", "A new form. Growth is the least predictable chapter."), ("wonder", "It changes, and is still itself. How wonderful."), ("wonder", "Look at it. Not a word of that was mine either.")],
    "fusion": [("stunned", "Two into one. I would not have written that."), ("delighted", "Two margins, one page. Ink everywhere. I love it."), ("fond", "Fused, and better for it. Remember that, all of you.")],
}
ARRIVE = [
    ("wry", "Verdant Spire. Mind the pollen."), ("dry", "Ember Bastion. Count the vents; they count you."), ("dry", "Tideglass Citadel. Watch the glass."),
    ("tense", "Frost Meridian. The cold is the least of it."), ("dry", "Iron Labyrinth. The walls will move. Move with them."),
    ("wonder", "Storm Crown. You have a head for heights, I trust."), ("uneasy", "Obsidian Eclipse. Stay near the light. I will stay near you."),
    ("hushed", "The Sunken Archive. Touch nothing on the shelves. Please."), ("wonder", "Astral Observatory. The stars are listening, Elio."),
    ("hushed", "Crystal Sanctum. Everything here rings. Let it."), ("solemn", "Rift Frontier. Nearly there. I can hear the crack from here."),
    ("solemn", "Sunforge Throne. This is the last page I know. Walk, Elio.")]
CLEAR = [
    ("fond", "One facet lit; eleven to go."), ("proud", "Discipline, rewarded. Two."), ("fond", "Three. The tide turns your way."),
    ("fond", "Four. Lowmere breathes easier."), ("amused", "Five. Even the timers were on time."), ("proud", "Six. Half the sky, mended."),
    ("fond", "Seven. Even shadows keep faith."), ("rueful", "Eight. Do not ask what I read there."), ("wonder", "Nine. The stars forgive you."),
    ("fond", "Ten. Ring the bell, Elio."), ("solemn", "Eleven. One left. Only one."), ("fond", "Twelve. The pen is yours, Elio.")]


def barks():
    out = []
    for ev, trio in EVENTS.items():
        for ph, (m, t) in zip(PHASES, trio):
            out.append({"id": f"bark_{ev}_{ph['id']}", "event": ev, "phase": ph["id"], "mood": m, "line": t})
    for i, (m, t) in enumerate(ARRIVE, 1):
        out.append({"id": f"bark_arrival_{i:02d}", "event": "arrival", "tower": f"{i:02d}", "mood": m, "line": t})
    for i, (m, t) in enumerate(CLEAR, 1):
        out.append({"id": f"bark_clear_{i:02d}", "event": "clear", "tower": f"{i:02d}", "mood": m, "line": t})
    return out


# ---- runtime-shared mood heuristic (MUST match scene_dialogue.gd infer_mood)
def infer_mood(speaker, text):
    t = text.lower()

    def has(ws):
        return any(w in t for w in ws)
    if has(["save the speeches", "how dare", "you will regret", "fool", "get out"]):
        return "angry"
    if has(["ha!", "haha", "rematch", "bring your whole team", "good sign", "not bad", "splendid", "fine. just this once"]):
        return "amused"
    if speaker == "Pell" and t.endswith("!"):
        return "amused"
    if has(["never seen", "incredible", "beautiful", "wonder", "reforms"]):
        return "awed"
    if has(["...", "sorry", "fallen", "goodbye", "lost "]):
        return "sad"
    if "!" in t or has(["i'm going", "we hold", "i will", "we answered", "let's", "ready"]):
        return "determined"
    if has(["must", "cannot", "can't", "tired", "dark", "falling", "broke", "cracking", "burn", "sinking"]):
        return "grave"
    return "neutral"


def load(p):
    return json.load(open(p, encoding="utf-8"))


def dump(p, o, indent):
    with open(p, "w", encoding="utf-8", newline="\n") as f:
        json.dump(o, f, ensure_ascii=False, indent=indent)


def raw_indent(p):
    s = open(p, encoding="utf-8").read(400)
    m = re.search(r"\n( +)\"", s)
    return len(m.group(1)) if m else 2


def apply_story(s):
    changed = 0
    seen = set()

    def fix(arr, sec, tid):
        nonlocal changed
        for i, l in enumerate(arr):
            if l["speaker"] == "Narrator":
                m, t = N[(sec, tid, i)]
                seen.add((sec, tid, i))
            else:
                m, t = infer_mood(l["speaker"], l["line"]), l["line"]
            if l.get("line") != t or l.get("mood") != m:
                changed += 1
            l["line"], l["mood"] = t, m
    for sec in ("prologue", "finale", "epilogue"):
        fix(s[sec], sec, None)
    for tw in s["towers"]:
        for sec in ("arrival", "pre_boss", "post_boss"):
            fix(tw[sec], sec, tw["tower_id"])
    assert seen == set(N), f"narrator slots mismatch: {seen ^ set(N)}"
    return changed


def main():
    sp = os.path.join(D, "story.json")
    ind = raw_indent(sp)
    s = load(sp)
    ch = apply_story(s)
    nar = {"version": 1, "speaker_id": "Narrator", "name": NAME, "title": TITLE,
           "expressions": ["neutral", "amused", "grave", "awed", "angry", "determined", "sad"],
           "mood_expression": MOOD_EXPRESSION, "phases": PHASES, "barks": barks()}
    for b in nar["barks"]:
        assert b["mood"] in MOOD_EXPRESSION, b
    for m, _t in N.values():
        assert m in MOOD_EXPRESSION, m
    for d in (D, G):
        dump(os.path.join(d, "story.json"), s, ind)
        dump(os.path.join(d, "narrator.json"), nar, 1)
    tp = os.path.join(G, "dialogue_triggers.json")
    txt = open(tp, encoding="utf-8", newline="").read()
    new = re.sub(r'("rare_drop"\s*:\s*\{.*?"template"\s*:\s*)"[^"]*"',
                 lambda m: m.group(1) + '"Entered in the ledger, with some satisfaction: the {reward}. Yours."', txt, count=1, flags=re.S)
    open(tp, "w", encoding="utf-8", newline="").write(new)
    print(f"story lines changed: {ch}; narrator lines: {len(N)}; barks: {len(nar['barks'])}")


if __name__ == "__main__":
    main()
