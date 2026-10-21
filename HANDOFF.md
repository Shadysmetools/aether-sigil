# Aether Sigil handoff, 2026-10-21

**Repo:** https://github.com/Shadysmetools/aether-sigil (private, `main` @ b137437; renamed from emberwick).

## State
- **Game** (`game/`, Godot 4.7.2):
  - 12x12 isometric battle loop driven by `data/AETHER_SIGIL_MASTER_GAME_BIBLE.json`: 120 stages, 1,000 monsters, opponents, dialogue.
  - Rules: initiative turns; Move/Attack/Skill/Defend/Wait; terrain and line of sight; multi-objectives; Player Sigil; capsule summons; squad of 4; levels, evolution and fusion; versioned local save (schema v2).
- **Tests:** `bash game/run_tests.sh` gives 18,623 pass / 0 fail (GREEN), across 7 suites incl. progression and story. The gate is strict: any failing assertion makes it RED, proven with a deliberate break.
- **Balance** (AI vs AI over 120 stages, difficulty curve on): a progressing default squad wins 50% (every tower 30-70%); without progression the same squad wins 8%, so levels, evolution and fusion are what carry a player through T12.
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

## Progression (2026-10-21)
Rules: `game/data/progression.json` (one table); code: `game/scripts/progression.gd` (pure logic), `progress.gd` (save schema v2, migrates v1).
- **XP/levels:** each summoned squad monster earns (30 + 15 x KOs) x 1.5 on a win / x 1.0 on a loss; level L -> L+1 costs 150 + 2 x L; levels stop at the bible's `level_cap` (30-50). hp +2%, attack/defense +1.5% per level.
- **Evolution:** at Lv16 and Lv36 (compendium sheet) into the next member of the bible's `evolution_family`; x1.15 hp/atk/def and +1 Skill tier per evolution; 3 forms per line. The line keeps its element/role (families mix elements in the data). Evolution screen, `evolved` signal + gold flash + placeholder line.
- **Fusion:** 2 owned monsters (both Lv10+) -> 1, deterministic; element/role/Skill from the higher-level parent, the other's element as a x1.1 secondary affinity; stats 60/40 blend +10%; rarity max+1 (cap Legendary); generated name checked against the 1,000 bible names and `game/data/reserved_names.json` (partial franchise list). Recipes: Feraldrakea + Tempesthydraen -> Verdalux, Lumenbatyx + Spectratuskon -> Celestilux, Cinderhopperor + Miresaur -> Vaporwyrm. Fusion screen with Preview -> Confirm.
- **Difficulty curve ON:** enemies x (1 + 10% x (tower-1)), T03 +10%. Progressing default squad (T01->T12, one attempt, fusions after T04/T08): 60/120 player wins (50%), every tower 3-7/10. Tuning runs: `game/tests/tune_curve.gd -- PCT [XP_BASE [T03_ADJ]]`; the table is in game_rules.json `difficulty._doc`.
- Not done: squad presets/filters (#18), stars/badges/tower rewards (#13), materials for evolution, fusion recipes beyond 3.

## Story, world map, video (2026-10-21)
- **Story mode:** `game/data/story.json` = the story writer's `data/story.json` (protagonist Elio), validated by `game/scripts/story.gd`. Player: coloured-initial portraits (placeholder), tap anywhere to advance, Skip. Seen-flags in the save (schema v3, migrates v1/v2). Triggers: prologue on a new game; arrival on the first tower visit; pre_boss before L10; rival line + global line 6 + tower reward + post_boss after an L10 win; finale + epilogue after T12-L10.
- **Dialogue (#17):** all 11 bible dialogue types are mapped in `game/data/dialogue_triggers.json` (scenes, HUD barks, screen lines). boss_intro is the same line on all 120 stages, so it only plays on the 12 L10s.
- **World map (#15):** 12 tower cards (theme colour, element icon from `game/art/elements`, lock state, x/10, stars x/30) -> tower screen (10 stages with stars) -> battle. Stars: 1 per win, +1 if the Sigil is at 50%+ HP, +1 if no monster was lost.
- **Video:** `docs/media/aether-sigil-gameplay.mp4` (95.8 s, 540x960, 1.6 MB) and `...-narrated.mp4` (TTS, 2.3 MB), plus 7 stills and `narration.txt`. Re-record: `engine/Godot_v4.7.2-stable_win64.exe --path game --write-movie out.avi --fixed-fps 30 --script res://tests/demo_recording.gd`, then ffmpeg (see narration.txt). The studio intro (motion-graphics agent) was not ready; the demo plays `game/scenes/intro/intro_sequence.tscn` first once it exists.

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
- hidden traps; evolution materials; more fusion recipes
- Android SDK + JDK 17 (manual; you accept the licences)
- export preset
- device test

Export templates for 4.7.2 are installed.
