"""One-off data fix: every stage named one opponent but gave its dialogue to another speaker.
The `opponent` field is canonical (it is also the opponent in 120_STAGES_AND_OPPONENTS.csv),
so each dialogue line's speaker prefix is rewritten to that stage's opponent.
Run: python tools/fix_speakers.py   (idempotent; prints before/after mismatch counts)"""
import json, csv, os, sys
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")
J = os.path.join(D, "AETHER_SIGIL_MASTER_GAME_BIBLE.json")
bible = json.load(open(J, encoding="utf-8"))

def mismatches():
    n = 0
    for t in bible["towers"]:
        for l in t["levels"]:
            for line in l["dialogue"].values():
                if isinstance(line, str) and ":" in line and line.split(":", 1)[0].strip() != l["opponent"]:
                    n += 1
    return n

before = mismatches()
opp = {}
for t in bible["towers"]:
    for l in t["levels"]:
        opp[l["stage_id"]] = l["opponent"]
        for k, line in l["dialogue"].items():
            if isinstance(line, str) and ":" in line:
                l["dialogue"][k] = f'{l["opponent"]}:{line.split(":", 1)[1]}'
after = mismatches()
json.dump(bible, open(J, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

C = os.path.join(D, "DIALOGUE_LINES.csv")
rows = list(csv.DictReader(open(C, encoding="utf-8")))
cols = list(rows[0].keys())
sid = next((c for c in cols if c.lower() in ("stage_id", "stage")), None)
spk = next((c for c in cols if c.lower() in ("speaker", "character", "name")), None)
txt = next((c for c in cols if c.lower() in ("line", "text", "dialogue")), None)
changed = 0
for r in rows:
    o = opp.get(r.get(sid, ""))
    if not o:
        continue
    if spk and r[spk] != o and r[spk].lower() not in ("hero", "player"):
        r[spk] = o; changed += 1
    elif txt and ":" in r[txt]:
        who = r[txt].split(":", 1)[0].strip()
        if who != o and who.lower() not in ("hero", "player"):
            r[txt] = f"{o}:{r[txt].split(':', 1)[1]}"; changed += 1
with open(C, "w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=cols); w.writeheader(); w.writerows(rows)
print(f"JSON dialogue speaker mismatches: before {before}, after {after}")
print(f"CSV rows corrected: {changed} of {len(rows)} (columns: {cols})")
sys.exit(1 if after else 0)
