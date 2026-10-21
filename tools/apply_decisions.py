"""Apply the owner's decisions of 2026-10-21 (delegated to the coordinator; final).

  1. Tower 12 "Crown of Ages" -> "Sunforge Throne" (exact-name Steam game exists). Data, stage
     names, art folders/files and their references.
  2. Subtitle "Chronicles of the Capsule Realms" -> "Chronicles of the Prism Realms" (Konami risk).
     Gameplay terms such as "capsule node" are NOT renamed.
  3. element_family "Nature" -> "Wood", "Lightning" -> "Thunder" (data, rules chart, icon files).
     Light and Dark become mutual rivals (Light > Dark and Dark > Light, x1.25 each).
  4. Monsters containing the Pokemon name "Archen": Duskmonarchen -> Duskmonarch,
     Echomonarchen -> Echomonarch, Ironmonarchen -> Ironmonarch (collision-checked).
  5. Issue #16: the JSON is canonical; each tower's L10 opponent is its tower_boss (champion),
     including the opponents list and the L10 dialogue. CSVs are regenerated from the JSON.
  6. Rule values: the design agent's proposals are accepted; Symbol/Sigil HP and the enemy
     difficulty curve are set from the simulation (SIGIL_HP / ENEMY_PCT_PER_TOWER / TOWER_ADJUST_PCT).

Edits data/AETHER_SIGIL_MASTER_GAME_BIBLE.json AND game/data/ (the shipped copy), regenerates
data/1000_MONSTERS.csv, data/120_STAGES_AND_OPPONENTS.csv and data/DIALOGUE_LINES.csv from the
JSON, renames files, and updates text references.
Run: python tools/apply_decisions.py   (idempotent: a second run changes nothing; prints
before/after counts. --check only reports, writes nothing.)"""
import csv, io, json, os, re, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
CHECK = "--check" in sys.argv
BIBLES = [os.path.join(ROOT, "data", "AETHER_SIGIL_MASTER_GAME_BIBLE.json"),
          os.path.join(ROOT, "game", "data", "AETHER_SIGIL_MASTER_GAME_BIBLE.json")]
RULES = os.path.join(ROOT, "game", "data", "game_rules.json")

OLD_TOWER, NEW_TOWER = "Crown of Ages", "Sunforge Throne"
OLD_SLUG, NEW_SLUG = "crown_of_ages", "sunforge_throne"
OLD_FILE, NEW_FILE = "Crown_of_Ages", "Sunforge_Throne"
TITLE_SWAPS = [("CHRONICLES OF THE CAPSULE REALMS", "CHRONICLES OF THE PRISM REALMS"),
               ("Chronicles of the Capsule Realms", "Chronicles of the Prism Realms")]
FAMILY = {"Nature": "Wood", "Lightning": "Thunder"}
MONSTERS = {"Duskmonarchen": "Duskmonarch", "Echomonarchen": "Echomonarch", "Ironmonarchen": "Ironmonarch"}
SIGIL_HP = 180                # chosen from the simulation table (see game_rules.json symbol._doc)
ENEMY_PCT_PER_TOWER = 10      # switched on 2026-10-21 once progression (XP, evolution, fusion) landed; see the difficulty _doc
TOWER_ADJUST_PCT = {"03": 10} # T03 alone won 7-8/10 at every curve tried
CHART = {"Fire": ["Wind"], "Wind": ["Earth"], "Earth": ["Water"], "Water": ["Fire"],
         "Thunder": ["Tech"], "Tech": ["Ice"], "Ice": ["Wood"], "Wood": ["Thunder"],
         "Light": ["Dark"], "Dark": ["Arcane", "Light"], "Arcane": ["Space"], "Space": ["Light"]}

changes = []   # (label, before, after)


def report(label, before, after):
    changes.append((label, before, after))
    print(f"  {label:<58} before {before!s:>6}   after {after!s:>6}")


def walk_strings(o, fn):
    """Apply fn to every string in a JSON tree; returns the new tree."""
    if isinstance(o, dict):
        return {k: walk_strings(v, fn) for k, v in o.items()}
    if isinstance(o, list):
        return [walk_strings(v, fn) for v in o]
    if isinstance(o, str):
        return fn(o)
    return o


def count_in(o, needle):
    return json.dumps(o, ensure_ascii=False).count(needle)


def read(path):
    with open(path, encoding="utf-8", newline="") as f:
        return f.read()


def write(path, text):
    if CHECK:
        return
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


# ---------------------------------------------------------------- bible JSON

def apply_bible(b):
    print("Bible JSON:")
    # 1. Tower 12 name everywhere in the bible (tower name, stage names, any text).
    before = count_in(b, OLD_TOWER)
    b = walk_strings(b, lambda s: s.replace(OLD_TOWER, NEW_TOWER))
    report(f'"{OLD_TOWER}" occurrences', before, count_in(b, OLD_TOWER))
    # 2. Title / subtitle.
    before = sum(count_in(b, o) for o, _ in TITLE_SWAPS)
    for o, n in TITLE_SWAPS:
        b = walk_strings(b, lambda s, o=o, n=n: s.replace(o, n))
    report('"Capsule Realms" in title fields', before, sum(count_in(b, o) for o, _ in TITLE_SWAPS))
    # 3. element_family renames.
    for old, new in FAMILY.items():
        before = sum(1 for m in b["monsters"] if m["element_family"] == old)
        for m in b["monsters"]:
            if m["element_family"] == old:
                m["element_family"] = new
        report(f'monsters with element_family "{old}" (-> "{new}")', before,
               sum(1 for m in b["monsters"] if m["element_family"] == old))
    # 4. "Archen" monster renames, collision-checked against all 1,000 names.
    names = [m["name"] for m in b["monsters"]]
    for old, new in MONSTERS.items():
        clash = [m["id"] for m in b["monsters"] if m["name"] == new]
        holders = [m["id"] for m in b["monsters"] if m["name"] == old]
        if clash and holders:
            sys.exit(f"ABORT: {new} already exists ({clash}); cannot rename {old}")
    before = sum(1 for n in names if "archen" in n.lower())
    for m in b["monsters"]:
        if m["name"] in MONSTERS:
            m["name"] = MONSTERS[m["name"]]
    after_names = [m["name"] for m in b["monsters"]]
    if len(set(after_names)) != len(after_names) and len(set(names)) == len(names):
        sys.exit("ABORT: monster renames created a duplicate name")
    report('monster names containing "archen"', before, sum(1 for n in after_names if "archen" in n.lower()))
    # 5. Issue #16: L10 opponent = tower champion (tower_boss), incl. opponents list and dialogue.
    def l10_mismatch():
        return sum(1 for t in b["towers"] if t["levels"][-1]["opponent"] != t["tower_boss"])
    before = l10_mismatch()
    for t in b["towers"]:
        lv = t["levels"][-1]
        champ, old = t["tower_boss"], lv["opponent"]
        if old == champ:
            continue
        lv["opponent"] = champ
        for o in t.get("opponents", []):
            if o.get("stage_id") == lv["stage_id"]:
                o["name"] = champ
        for k, line in lv["dialogue"].items():
            if isinstance(line, str):
                lv["dialogue"][k] = line.replace(old, champ)
    report("towers whose L10 opponent is not the tower_boss (#16)", before, l10_mismatch())
    return b


# ---------------------------------------------------------------- CSVs from the JSON

def csv_text(rows):
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\r\n")
    for r in rows:
        w.writerow(r)
    return buf.getvalue()


def gen_monsters(b, header):
    return csv_text([header] + [[str(m.get(c, "")) for c in header] for m in b["monsters"]])


STAGE_COLS = ["tower_id", "tower_name", "stage_id", "stage_name", "map_size", "terrain", "weather", "opponent",
              "opponent_style", "enemy_roster", "win_condition", "special_rule", "boss", "map_image"]


def gen_stages(b):
    rows = [STAGE_COLS]
    for t in b["towers"]:
        for l in t["levels"]:
            rows.append([t["tower_id"], t["name"], l["stage_id"], l["name"], l["map_size"], l["terrain"], l["weather"],
                         l["opponent"], l["opponent_style"], "|".join(l["enemy_roster"]), l["win_condition"],
                         l["special_rule"], str(bool(l["boss"])),
                         "MAPS_120/%s_%s.png" % (l["stage_id"], t["name"].replace(" ", "_"))])
    return csv_text(rows)


def gen_dialogue(b):
    rows = [["stage_id", "tower", "speaker", "scene", "line"]]
    for t in b["towers"]:
        for l in t["levels"]:
            for scene, line in l["dialogue"].items():
                rows.append([l["stage_id"], t["name"], l["opponent"], scene, line])
    for i, line in enumerate(b["dialogue_system"]["sample_lines"], 1):
        rows.append(["GLOBAL", "ALL", "SYSTEM", "sample_%d" % i, line])
    return csv_text(rows)


def differing_rows(a, b):
    la, lb = a.splitlines(), b.splitlines()
    return sum(1 for x, y in zip(la, lb) if x != y) + abs(len(la) - len(lb))


def apply_csvs(b):
    print("CSVs regenerated from the JSON (rows that differ from the JSON's own rendering):")
    D = os.path.join(ROOT, "data")
    mpath = os.path.join(D, "1000_MONSTERS.csv")
    header = next(csv.reader(io.StringIO(read(mpath))))
    for name, gen in [("1000_MONSTERS.csv", lambda: gen_monsters(b, header)),
                      ("120_STAGES_AND_OPPONENTS.csv", lambda: gen_stages(b)),
                      ("DIALOGUE_LINES.csv", lambda: gen_dialogue(b))]:
        p = os.path.join(D, name)
        cur, new = read(p), gen()
        report(name, differing_rows(cur, new), 0)
        if cur != new:
            write(p, new)


# ---------------------------------------------------------------- rules table

def apply_rules():
    print("game/data/game_rules.json:")
    raw = read(RULES)
    r = json.loads(raw)
    before = len(re.findall(r"\b(Nature|Lightning)\b", raw))
    fam_re = re.compile(r"\b(Nature|Lightning)\b")
    r = walk_strings(r, lambda s: fam_re.sub(lambda m: FAMILY[m.group(1)], s))
    # keys too (element chart / tile families)
    r["element_chart"] = {"_doc": "Decided 2026-10-21 (owner, via coordinator). Three rings; each family beats the next in its ring (x1.25) and takes x0.8 from the one before; cross-ring and opposite-in-ring matchups are neutral. Elemental: Fire>Wind>Earth>Water>Fire. Wild: Thunder>Tech>Ice>Wood>Thunder. Mystic: Light<->Dark are MUTUAL rivals (each deals x1.25 to the other), Dark>Arcane>Space>Light. Family names Nature->Wood and Lightning->Thunder. Ring design: docs/BALANCE-REPORT.md section 10."}
    r["element_chart"].update(CHART)
    r["symbol"]["hp"] = SIGIL_HP
    r["symbol"]["_doc"] = ("The Player Sigil / enemy Symbol: a crystal on a pedestal on the *_symbol tile, the side's commander; "
                           "it blocks movement and is attacked like a unit with no element; if it falls, its side loses. Defense 10 "
                           "(design proposal, accepted 2026-10-21). HP tuned by simulation on 2026-10-21 "
                           "(game/tests/tune_sigil.gd, default squad, 120 stages, 60-round cap): tried 120/180/240/300/360 "
                           "with no difficulty curve: 120 -> 48% player / 9% capped / median 12; 180 -> 47% / 9% / 13; "
                           "240 -> 46% / 10% / 14; 300 -> 46% / 10% / 15; 360 -> 45% / 11% / 16. Chose 180: inside every target "
                           "(45-55% player wins, median 12-20 rounds, <=10% capped) with margin on all three. HP barely moves "
                           "the win rate; it mostly sets battle length. See HANDOFF.md 'Open decisions'.")
    r["difficulty"] = {"_doc": ("Difficulty curve: enemy monsters' hp, attack and defense x (1 + pct/100 x (tower - 1) + tower_adjust_pct[tower]/100); "
                                "player monsters are unscaled (they level, evolve and fuse instead). History: shipped at 0 on 2026-10-21 while the squad had no "
                                "progression (+1/+2/+3% gave 37/27/22% player wins at Sigil HP 240). Switched on the same day with progression "
                                "(game/data/progression.json) and tuned with game/tests/tune_curve.gd (progressing default squad, T01->T12 in order, one "
                                "attempt per stage, fusions after T04 and T08): pct 6 -> 89% player wins, 8 -> 74%, 9 -> 63%, 10 -> 53% but T03/T04 8/10, "
                                "11 -> 47% but T03 8/10; with T03 +10%: pct 9.5 -> 58% (T04/T05 8/10), 10 -> 50% with every tower 3-7/10 (chosen), "
                                "10.5 -> 43%. The player's XP snowballs, so the result is sensitive: re-run tune_curve after changing XP or growth."),
                       "enemy_stat_pct_per_tower": ENEMY_PCT_PER_TOWER, "tower_adjust_pct": TOWER_ADJUST_PCT}
    r["accuracy"]["_doc"] = ("Hit chance % = base + high-ground bonus - veil penalty, clamped to [min, max]. The roll uses the "
                             "battle's seeded RNG. Values approved 2026-10-21 (design proposal: base 90, high ground +15).")
    new = json.dumps(r, indent=2, ensure_ascii=False)
    report("Nature/Lightning mentions in the rules table", before, len(re.findall(r"\b(Nature|Lightning)\b", new)))
    report("symbol.hp (Sigil HP)", json.loads(raw)["symbol"]["hp"], SIGIL_HP)
    report("difficulty.enemy_stat_pct_per_tower", json.loads(raw).get("difficulty", {}).get("enemy_stat_pct_per_tower", 0), ENEMY_PCT_PER_TOWER)
    report("difficulty.tower_adjust_pct[03]", json.loads(raw).get("difficulty", {}).get("tower_adjust_pct", {}).get("03", 0), TOWER_ADJUST_PCT.get("03", 0))
    report("Dark beats Light (mutual rivals)", int("Light" in json.loads(raw)["element_chart"].get("Dark", [])), int("Light" in CHART["Dark"]))
    report("rules file rewritten (any other drift)", int(new != raw), 0)
    if new != raw:
        write(RULES, new)


# ---------------------------------------------------------------- files and references

def renames():
    G = os.path.join(ROOT, "art", "generated")
    pairs = []
    for kind in ("png", "svg"):
        pairs.append((os.path.join(G, kind, "tiles", "T12_" + OLD_SLUG), os.path.join(G, kind, "tiles", "T12_" + NEW_SLUG)))
        for old, new in (("nature", "wood"), ("lightning", "thunder")):
            pairs.append((os.path.join(G, kind, "icons", "elements", old + "." + kind), os.path.join(G, kind, "icons", "elements", new + "." + kind)))
            for team in ("ally", "enemy"):
                pairs.append((os.path.join(G, kind, "tokens", "frames", "%s_%s.%s" % (team, old, kind)),
                              os.path.join(G, kind, "tokens", "frames", "%s_%s.%s" % (team, new, kind))))
        pairs.append((os.path.join(G, kind, "tokens", "samples", "ally_nature_stag." + kind),
                      os.path.join(G, kind, "tokens", "samples", "ally_wood_stag." + kind)))
    pairs.append((os.path.join(G, "previews", "sheet_tiles_T12_%s.png" % OLD_SLUG), os.path.join(G, "previews", "sheet_tiles_T12_%s.png" % NEW_SLUG)))
    maps = os.path.join(ROOT, "data", "maps")
    for f in sorted(os.listdir(maps)):
        if OLD_FILE in f:
            pairs.append((os.path.join(maps, f), os.path.join(maps, f.replace(OLD_FILE, NEW_FILE))))
    return pairs


def apply_files():
    print("Files:")
    pairs = renames()
    pending = [(a, b) for a, b in pairs if os.path.exists(a)]
    for a, b in pending:
        if os.path.exists(b):
            sys.exit("ABORT: both %s and %s exist" % (a, b))
        if not CHECK:
            os.rename(a, b)
    report("files/folders still under old names (T12, element icons, maps)", len(pending), 0 if not CHECK else len(pending))


TEXT_RULES = [
    # (relative path or folder, [(old, new), ...])
    ("art/generated/MANIFEST.md", [("T12_" + OLD_SLUG, "T12_" + NEW_SLUG), (OLD_SLUG, NEW_SLUG), (OLD_TOWER, NEW_TOWER),
                                   ("icons/elements/nature", "icons/elements/wood"), ("icons/elements/lightning", "icons/elements/thunder"),
                                   ("ally_nature", "ally_wood"), ("enemy_nature", "enemy_wood"),
                                   ("ally_lightning", "ally_thunder"), ("enemy_lightning", "enemy_thunder"),
                                   ("Element family icon: Nature", "Element family icon: Wood"),
                                   ("Element family icon: Lightning", "Element family icon: Thunder"),
                                   ("Nature family", "Wood family"), ("Lightning family", "Thunder family"),
                                   ("Earth, Nature, Ice, Lightning,", "Earth, Wood, Ice, Thunder,")]),
    ("art/generated/tools/aether_art.py", [(OLD_SLUG, NEW_SLUG), (OLD_TOWER, NEW_TOWER),
                                           ('"Nature"', '"Wood"'), ('"Lightning"', '"Thunder"')]),
    ("art/generated/tools/make_manifest.py", [("Earth, Nature, Ice, Lightning,", "Earth, Wood, Ice, Thunder,")]),
    ("art/PROMPTS.md", [(OLD_TOWER, NEW_TOWER)]),
    ("art/generated/svg/tiles/T12_" + NEW_SLUG, [(OLD_SLUG, NEW_SLUG), (OLD_TOWER, NEW_TOWER)]),
    ("data/README_FOR_CLAUDE.md", TITLE_SWAPS),
    ("README.md", TITLE_SWAPS),
    ("project.yaml", TITLE_SWAPS),
    ("design/game-brief.md", TITLE_SWAPS),
    ("docs/ROADMAP.md", TITLE_SWAPS + [(OLD_TOWER, NEW_TOWER)]),
    ("docs/data/monster_power.csv", list(MONSTERS.items())),
]


def apply_text():
    print("Text references:")
    for rel, swaps in TEXT_RULES:
        path = os.path.join(ROOT, rel)
        files = []
        if os.path.isdir(path):
            files = [os.path.join(path, f) for f in sorted(os.listdir(path))]
        elif os.path.exists(path):
            files = [path]
        before = after = 0
        for f in files:
            t = read(f)
            before += sum(t.count(o) for o, _ in swaps)
            for o, n in swaps:
                t = t.replace(o, n)
            after += sum(t.count(o) for o, _ in swaps)
            if t != read(f):
                write(f, t)
        report(rel, before, after)


def main():
    print("apply_decisions.py%s" % ("  (--check: no writes)" if CHECK else ""))
    raws = [read(p) for p in BIBLES]
    b = apply_bible(json.loads(raws[0]))
    out = json.dumps(b, ensure_ascii=False, indent=1)
    for p, raw in zip(BIBLES, raws):
        if raw != out:
            write(p, out)
    report("bible copies differing from the canonical JSON", sum(1 for r in raws if r != out), 0)
    apply_csvs(b)
    apply_rules()
    apply_files()
    apply_text()
    total = sum(1 for _, bef, aft in changes if bef != aft)
    print("DONE: %d item(s) changed%s" % (total, "" if total else " (already applied)"))


if __name__ == "__main__":
    main()
