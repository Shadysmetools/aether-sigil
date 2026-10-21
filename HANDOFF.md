# Aether Sigil handoff, 2026-10-21

**Repo:** https://github.com/Shadysmetools/aether-sigil (private, `main` @ b137437; renamed from emberwick).

## State
- **Game** (`game/`, Godot 4.7.2):
  - 12x12 isometric battle loop driven by `data/AETHER_SIGIL_MASTER_GAME_BIBLE.json`: 120 stages, 1,000 monsters, opponents, dialogue.
  - Rules: initiative turns; Move/Attack/Skill/Defend/Wait; terrain and line of sight; multi-objectives; Player Sigil; capsule summons; squad of 4; progression with local save.
- **Tests:** `bash game/run_tests.sh` gives 16,322 pass / 0 fail (GREEN). The gate is strict: any failing assertion makes it RED, proven with a deliberate break.
- **Balance** (AI vs AI over 120 stages): the design squad wins 48% vs the enemy's 43%; there is no difficulty curve yet.
- **Known data issues:** 353 contradictions in the generated bible, handled by rule fallbacks and listed in `KNOWN_DATA_ISSUES` in `game/tests/test_data.gd`.

## Docs and assets
| Item | Where |
| --- | --- |
| Balance analysis and ability specs (reproducible) | `docs/BALANCE-REPORT.md`, `docs/ABILITIES.md` |
| Milestones M1-M7 and 41 GitHub issues | `docs/ROADMAP.md`, GitHub |
| Name review (not legal advice) | `docs/IP-CHECK.md` |
| 365 original placeholder art files and prompt pack | `art/generated/`, `art/PROMPTS.md` |
| AI concept sheets (reference only) | `art/concepts/` |

## Studio
Claude Code Game Studios v1.2.0 is installed: `.claude/`, `project.yaml`, `CLAUDE.md`. Local patches are in `docs/ccgs/LOCAL-PATCHES.md`.

**First run:** open this folder in Claude Code, then run, in order:
1. `/project-stage-detect`
2. `/adopt`
3. `/gate-check`
4. `/setup-engine refresh` (not the full setup)

## Open decisions (owner): DECIDED 2026-10-21
Delegated by the owner to the coordinator; final. Applied by `tools/apply_decisions.py` (idempotent; edits both bible copies, regenerates the CSVs, renames art/map files) plus code and tests.
1. **Tower 12 renamed "Crown of Ages" -> "Sunforge Throne"** (an exact-name Steam game exists; no Steam match for the new name). Data, stage names ("Sunforge Throne — Chamber N"), maps `data/maps/T12-L*_Sunforge_Throne.png`, art `art/generated/{png,svg}/tiles/T12_sunforge_throne`, MANIFEST, art tools and PROMPTS.
2. **Subtitle: "Aether Sigil: Chronicles of the Prism Realms"** ("Capsule" dropped, Konami risk). Bible title, project.yaml, CLAUDE.md, README, in-game title, design/game-brief.md. Mechanics keep their names ("capsule node") for now. Trademark searches and a lawyer review are still open (#31).
3. **Rule values approved:** accuracy 90%, high ground +15 accuracy / +30% damage / +1 range, defend x0.5, damage max(1, round(1.5*atk^2/(atk+def))), element rings x1.25 / x0.8. **Sigil/Symbol HP = 180**, tuned by simulation (default squad, 120 stages, 60-round cap, no curve): HP 120 -> 48% player wins / 9% capped / median 12 rounds; **180 -> 47% / 9% / 13**; 240 -> 46% / 10% / 14; 300 -> 46% / 10% / 15; 360 -> 45% / 11% / 16. **Difficulty curve** `difficulty.enemy_stat_pct_per_tower` added but shipped at **0**: +1/+2/+3% per tower drop player wins to 37% / 27% / 22% (T07-T12 nearly unwinnable at +3%) because the squad has no progression yet.
4. **Elements:** `element_family` Nature -> **Wood** (63 monsters), Lightning -> **Thunder** (62); icon/token files renamed (`wood`, `thunder`). Rings: Fire>Wind>Earth>Water>Fire; Thunder>Tech>Ice>Wood>Thunder; Mystic: **Light <-> Dark mutual rivals** (x1.25 each way), Dark>Arcane>Space>Light. Tower themes/terrain text ("Nature" tower theme, "Nature hazard") are unchanged.
5. **Monsters renamed** (Pokémon "Archen"): Duskmonarchen -> Duskmonarch, Echomonarchen -> Echomonarch, Ironmonarchen -> Ironmonarch (no collisions in the 1,000).
6. **Champions (#16):** the JSON's `tower_boss` is canonical; each tower's L10 opponent, opponents-list entry and L10 dialogue now use the champion (12 towers fixed); the stage and dialogue CSVs are regenerated from the JSON; `test_data.gd` asserts it.

## Next
- 3D view
- difficulty curve
- hidden traps and evolution
- Android SDK + JDK 17 (manual; you accept the licences)
- export preset
- device test

Export templates for 4.7.2 are installed.
