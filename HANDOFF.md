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

## Open decisions (owner)
1. Rename tower "Crown of Ages" (an upcoming Steam game uses the exact name).
2. Subtitle: drop "Capsule"? Settle it before the Android listing (M5).
3. Approve the proposed rule values: Symbol HP 120, accuracy 90%, element chart (3 rings of 4).
4. Element names: Nature -> Wood? Lightning -> Thunder? Should Light and Dark be mutual rivals?

## Next
- 3D view
- difficulty curve
- hidden traps and evolution
- Android SDK + JDK 17 (manual; you accept the licences)
- export preset
- device test

Export templates for 4.7.2 are installed.
