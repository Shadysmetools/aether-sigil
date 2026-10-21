"""Fold the old Action Point stage rule into Summon Points (owner request 2026-10-21; design in
docs/SUMMON-POINTS.md).

The bible's 24 L04/L08 stages say "Capsules cost 1 AP to deploy". AP no longer exists: summoning
(cracking a Vessel) is paid in SP, so the rule becomes "Vessels cost +1 SP to crack" (every crack
on that stage costs 1 SP more; game_rules.json special_rules.sp_surcharge). "Vessel" is the
player-facing name of the sealed shell (IP: no "capsule" as the shell noun on screen); the
intermediate text "Capsules cost +1 SP to summon" (first SP draft, same day) is mapped too. The text is
rewritten in every copy: both bibles, the CSV exports, the stage-difficulty table, the design
generator and the balance report. game_rules.json is edited by hand (its key is already new).

Run: python tools/apply_summon_points.py          (idempotent: a second run changes nothing)
     python tools/apply_summon_points.py --check  (reports counts, writes nothing)"""
import os, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
CHECK = "--check" in sys.argv
OLDS = ["Capsules cost 1 AP to deploy", "Capsules cost +1 SP to summon"]
NEW = "Vessels cost +1 SP to crack"
FILES = [
    "data/AETHER_SIGIL_MASTER_GAME_BIBLE.json",
    "game/data/AETHER_SIGIL_MASTER_GAME_BIBLE.json",
    "data/120_STAGES_AND_OPPONENTS.csv",
    "docs/data/stage_difficulty.csv",
    "docs/tools/aether_design.py",
    "docs/BALANCE-REPORT.md",
    "docs/SUMMON-POINTS.md",
]


def main() -> int:
    total = 0
    for rel in FILES:
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            print(f"  {rel:<52} missing (skipped)")
            continue
        with open(path, "r", encoding="utf-8", newline="") as f:
            text = f.read()
        before, after = sum(text.count(o) for o in OLDS), text.count(NEW)
        if rel.endswith(".md"):  # docs quote the pre-SP text as history: only the intermediate text is replaced
            before = text.count(OLDS[1])
            new_text = text.replace(OLDS[1], NEW)
        else:
            new_text = text
            for o in OLDS:
                new_text = new_text.replace(o, NEW)
        print(f"  {rel:<52} old {before:>3}   new {after:>3}")
        total += before
        if before and not CHECK:
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(new_text)
    print(("would change" if CHECK else "changed") + f" {total} occurrence(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
