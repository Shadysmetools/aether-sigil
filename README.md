# Aether Sigil: Chronicles of the Capsule Realms

> Renamed from the Emberwick prototype on 2026-10-20. Game data: `data/` (master bible JSON, 1,000 monsters, 120 stages/maps, 486 dialogue lines).

A 12x12 isometric tactical monster-board game for iPhone and Android. Deploy monsters from capsules onto your spawn tiles and captured Prism (capsule) nodes, use terrain, high ground and bridges, and destroy the rival's Symbol. 12 towers x 10 stages, 1,000 monsters, every stage driven by the bible in `data/`.

## Status
Playable prototype (Godot 4.7.2, GDScript). The hex "Emberwick" prototype it replaced is in git history (commit `eb7e121`).

## Play
1. Open `game/project.godot` in Godot 4.7.2 and press F5 (or run `engine/Godot_v4.7.2-stable_win64.exe --path game`).
2. Stage select: pick an unlocked stage (Tower 01 stage 1 at first). Read the rival's intro, tap Continue.
3. Your turn: tap a team monster at the bottom, then a cyan tile to deploy it (it acts next turn).
4. Tap one of your monsters: cyan tiles = move, ember tiles = attack (enemy monsters or the enemy Symbol). Move then attack, or just attack.
5. End Turn. The rival plays with its `opponent_style`. Destroy the enemy Symbol (or secure 3 relics where the stage says so) to win and unlock the next stage. Progress saves to `user://aether_sigil_save.json`.

## Code (`game/`)
| File | Role |
| --- | --- |
| `data/AETHER_SIGIL_MASTER_GAME_BIBLE.json` | Copy of the bible, shipped inside the project |
| `data/game_rules.json` | Every number and interpretation the bible lacks: element chart, terrain bonuses, tile rules, Symbol HP, special-rule table, starter team |
| `scripts/data_loader.gd` | Loads both JSON files once |
| `scripts/game_state.gd` | Rules, pure logic, legal-action API |
| `scripts/ai.gd` | One AI, parameterised per `opponent_style` |
| `scripts/progress.gd` | Unlocks + local save |
| `scripts/theme_colors.gd` | Brand colour tokens (the only colour file) |
| `scripts/board_art.gd` | All drawing (replace for sprites/3D) |
| `scripts/board_view.gd` | Isometric projection, draw order, tap picking |
| `scripts/ui.gd` | Stage select, dialogue, HUD, results |

Tests: `bash game/run_tests.sh` (import check, data validation of all 120 stages, rules, UI smoke, AI-vs-AI on all 120 stages, main scene for 120 frames).

Mobile export: check that the export includes `data/*.json` (add it to the preset's include filter if needed); the game reads the bible from `res://data/` at startup.

## What's here
| Path | What |
| --- | --- |
| `game/` | Godot 4.7 project: the playable prototype (added when ready) |
| `docs/gallery/` | Animated concept art: characters, all 18 Wicks, the light board, battle animations |
| `design/` | Design-system tokens and UI component previews |

Game design document (Claude Docs): https://claude.ai/code/artifact/c95fe8f8-8f5f-4ebe-a95c-f0e41bd44a86

## Setup
1. Download **Godot 4.7.2** from https://godotengine.org (not committed here).
2. Open `game/project.godot` in Godot, then press F5 to play.

## Third-party assets
Only original work, or assets under licences safe for a commercial closed-source app (CC0 / MIT / OFL).
- Kenney Hexagon Kit, CC0: https://kenney.nl/assets/hexagon-kit (kept outside git in `assets/`)
- Third-party: Claude Code Game Studios (MIT), v1.2.0, the AI dev-studio framework in `.claude/`, `CLAUDE.md` and `project.yaml`. Licence: `docs/ccgs/LICENSE-CCGS.txt`; upstream README: `docs/ccgs/CCGS-README.md`; local changes: `docs/ccgs/LOCAL-PATCHES.md`.

## Licence
All rights reserved. Not open source.
