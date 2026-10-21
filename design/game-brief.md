# Game Brief: Aether Sigil: Chronicles of the Prism Realms

<!--
POINTER STUB. Written at CCGS install time so the `minimal`-tier skills find a
brief. It holds no new design: every line is copied from README.md or points at
the real design sources below. Replace each field from those sources (or run
`/reverse-document design game` to draft it from the code) when you adopt CCGS.

Design sources of truth:
- data/AETHER_SIGIL_MASTER_GAME_BIBLE.json  (master game bible; copy shipped in game/data/)
- data/AETHER_SIGIL_GAME_BIBLE.pdf          (readable bible)
- data/1000_MONSTERS.csv, data/120_STAGES_AND_OPPONENTS.csv, data/DIALOGUE_LINES.csv, data/maps/
- game/data/game_rules.json                 (numbers and interpretations the bible lacks)
- art/concepts/                             (concept art reference sheets)
- docs/ROADMAP.md                           (roadmap)
- GDD (Claude Docs): https://claude.ai/code/artifact/c95fe8f8-8f5f-4ebe-a95c-f0e41bd44a86
-->

**One-sentence pitch:** A 12x12 isometric tactical monster-board game for iPhone and Android (from README.md).

## Core loop
- Deploy monsters from capsules onto spawn tiles and captured Prism nodes; move, attack, end turn (README.md "Play").
- Full rules: `data/AETHER_SIGIL_MASTER_GAME_BIBLE.json`, `game/data/game_rules.json`.

## Player goal & fail state — what "working" looks like
- Destroy the rival's Symbol (or secure 3 relics where the stage says so) to win and unlock the next stage (README.md).

## MVP — what must exist to be the game
- See `docs/ROADMAP.md`. Not restated here.

## Out of scope — not building this
- See `docs/ROADMAP.md`. Not restated here.

## Build order
1. See `docs/ROADMAP.md`. Not restated here.

---
**Who it's for / what they feel:** See the bible (`data/AETHER_SIGIL_GAME_BIBLE.pdf`).

**Art & audio direction:** See `art/concepts/` and `docs/gallery/`.

**Reference game:** See the bible.
