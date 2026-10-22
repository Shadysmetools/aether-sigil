# Audio credits and licences

Every shipped audio file is either CC0 (public domain dedication) or original synthesis made for this game. No CC-BY, GPL or 'free for non-commercial' material is used.

## Kenney.nl packs (CC0 1.0 - https://creativecommons.org/publicdomain/zero/1.0/)

Licence text checked in each pack's `License.txt` ("License (Creative Commons Zero, CC0)"). Credit is not required; given here anyway: **Kenney Vleugels (www.kenney.nl)**.

| Pack | Page | Download | Used in (layered and re-mastered) |
|---|---|---|---|
| interface-sounds | https://kenney.nl/assets/interface-sounds | https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip | `ui_tap`, `ui_confirm`, `ui_back`, `ui_locked` |
| rpg-audio | https://kenney.nl/assets/rpg-audio | https://kenney.nl/media/pages/assets/rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip | `ui_page` |
| impact-sounds | https://kenney.nl/assets/impact-sounds | https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip | `step_stone`, `step_grass`, `step_snow`, `statue_hop`, `petrify_shatter`, `stone_chip_hit`, `statue_crumble`, `summon_burst`, `hit_melee`, `hit_heavy`, `hit_critical`, `evolve_burst`, `sigil_damage`, `cast_earth`, `cast_ice`, `cast_wood`, `amb_metal` |
| sci-fi-sounds | https://kenney.nl/assets/sci-fi-sounds | https://kenney.nl/media/pages/assets/sci-fi-sounds/6b296f9ecf-1677589334/kenney_sci-fi-sounds.zip | `defend_shield`, `cast_tech` |
| digital-audio | https://kenney.nl/assets/digital-audio | https://kenney.nl/media/pages/assets/digital-audio/216eac4753-1677590265/kenney_digital-audio.zip | `capsule_node` |

## Music - OpenGameArt.org, CC0 only

Each page listed **CC0** as its sole licence when checked on 2026-10-21. Files are re-encoded with a loudness gain only (no edits).

| Id | Track | Author | Page | File | Licence |
|---|---|---|---|---|---|
| `title` | Magic Puzzle Title (100 BPM, loopable) | MintoDog | https://opengameart.org/content/magic-puzzle-title | https://opengameart.org/sites/default/files/magic_puzzle_title_bpm100_0.ogg | CC0 1.0 |
| `battle` | Hope (Orchestral battle music, 165 BPM, loopable) | MintoDog | https://opengameart.org/content/hopeorchestral-battle-music | https://opengameart.org/sites/default/files/hope_orchestral_battle_music_bpm165_0.ogg | CC0 1.0 |
| `boss` | Fairy Boss Battles (185 BPM, loopable) | MintoDog | https://opengameart.org/content/fairy-boss-battles | https://opengameart.org/sites/default/files/fairy_boss_battles_bpm185_0.ogg | CC0 1.0 |
| `victory` | Cozy Puzzle Clear (Loop, 85 BPM) | MintoDog | https://opengameart.org/content/cozy-puzzle-jingle-result | https://opengameart.org/sites/default/files/ogg_cozy_puzzle_jingle_result.zip | CC0 1.0 |
| `defeat` | Cozy Puzzle Failure (Loop, 80 BPM) | MintoDog | https://opengameart.org/content/cozy-puzzle-jingle-result | https://opengameart.org/sites/default/files/ogg_cozy_puzzle_jingle_result.zip | CC0 1.0 |

## Original synthesis (this repo, same licence as the game)

Made by `game/audio/tools/make_sfx.py` + `dsp.py` (numpy/scipy: noise, FM, additive, granular, STFT formant filters, convolution reverb with synthetic IRs). Creature roars are fully synthetic (pitch-contoured harmonic source + formant filter) - no animal recordings.

Per output file, the exact CC0 source files layered into it (Kenney paths are inside the pack zips above); files with no entry are 100% synthesis.

| Output file | Source files |
|---|---|
| `sfx/ui_tap_01.ogg` | interface-sounds/Audio/click_002.ogg |
| `sfx/ui_tap_02.ogg` | interface-sounds/Audio/click_003.ogg |
| `sfx/ui_confirm.ogg` | interface-sounds/Audio/confirmation_002.ogg |
| `sfx/ui_back.ogg` | interface-sounds/Audio/back_002.ogg |
| `sfx/ui_locked.ogg` | interface-sounds/Audio/error_004.ogg |
| `sfx/ui_page_01.ogg` | rpg-audio/Audio/bookFlip1.ogg |
| `sfx/ui_page_02.ogg` | rpg-audio/Audio/bookFlip2.ogg |
| `sfx/step_stone_01.ogg` | impact-sounds/Audio/footstep_concrete_000.ogg |
| `sfx/step_stone_02.ogg` | impact-sounds/Audio/footstep_concrete_001.ogg |
| `sfx/step_stone_03.ogg` | impact-sounds/Audio/footstep_concrete_002.ogg |
| `sfx/step_stone_04.ogg` | impact-sounds/Audio/footstep_concrete_003.ogg |
| `sfx/step_grass_01.ogg` | impact-sounds/Audio/footstep_grass_000.ogg |
| `sfx/step_grass_02.ogg` | impact-sounds/Audio/footstep_grass_001.ogg |
| `sfx/step_grass_03.ogg` | impact-sounds/Audio/footstep_grass_002.ogg |
| `sfx/step_grass_04.ogg` | impact-sounds/Audio/footstep_grass_003.ogg |
| `sfx/step_water_01.ogg` | synthesis only (make_sfx.py) |
| `sfx/step_water_02.ogg` | synthesis only (make_sfx.py) |
| `sfx/step_water_03.ogg` | synthesis only (make_sfx.py) |
| `sfx/step_water_04.ogg` | synthesis only (make_sfx.py) |
| `sfx/step_snow_01.ogg` | impact-sounds/Audio/footstep_snow_000.ogg |
| `sfx/step_snow_02.ogg` | impact-sounds/Audio/footstep_snow_001.ogg |
| `sfx/step_snow_03.ogg` | impact-sounds/Audio/footstep_snow_002.ogg |
| `sfx/step_snow_04.ogg` | impact-sounds/Audio/footstep_snow_003.ogg |
| `sfx/statue_hop_01.ogg` | impact-sounds/Audio/impactMining_000.ogg |
| `sfx/statue_hop_02.ogg` | impact-sounds/Audio/impactMining_001.ogg |
| `sfx/statue_hop_03.ogg` | impact-sounds/Audio/impactMining_002.ogg |
| `sfx/stone_crack_build.ogg` | synthesis only (make_sfx.py) |
| `sfx/petrify_shatter.ogg` | impact-sounds/Audio/impactGlass_heavy_001.ogg |
| `sfx/monster_awaken_roar_generic_01.ogg` | synthesis only (make_sfx.py) |
| `sfx/monster_awaken_roar_generic_02.ogg` | synthesis only (make_sfx.py) |
| `sfx/monster_roar_beast_01.ogg` | synthesis only (make_sfx.py) |
| `sfx/monster_roar_beast_02.ogg` | synthesis only (make_sfx.py) |
| `sfx/monster_roar_screech_01.ogg` | synthesis only (make_sfx.py) |
| `sfx/monster_roar_screech_02.ogg` | synthesis only (make_sfx.py) |
| `sfx/monster_roar_growl_01.ogg` | synthesis only (make_sfx.py) |
| `sfx/monster_roar_growl_02.ogg` | synthesis only (make_sfx.py) |
| `sfx/monster_roar_chitter_01.ogg` | synthesis only (make_sfx.py) |
| `sfx/monster_roar_chitter_02.ogg` | synthesis only (make_sfx.py) |
| `sfx/repetrify.ogg` | synthesis only (make_sfx.py) |
| `sfx/stone_chip_hit_01.ogg` | impact-sounds/Audio/impactMining_001.ogg |
| `sfx/stone_chip_hit_02.ogg` | impact-sounds/Audio/impactMining_002.ogg |
| `sfx/stone_chip_hit_03.ogg` | impact-sounds/Audio/impactMining_003.ogg |
| `sfx/stone_chip_hit_04.ogg` | impact-sounds/Audio/impactMining_004.ogg |
| `sfx/statue_crumble.ogg` | impact-sounds/Audio/impactMining_004.ogg |
| `sfx/summon_burst.ogg` | impact-sounds/Audio/impactGlass_heavy_002.ogg |
| `sfx/hit_melee_01.ogg` | impact-sounds/Audio/impactPunch_medium_000.ogg |
| `sfx/hit_melee_02.ogg` | impact-sounds/Audio/impactPunch_medium_001.ogg |
| `sfx/hit_melee_03.ogg` | impact-sounds/Audio/impactPunch_medium_002.ogg |
| `sfx/hit_melee_04.ogg` | impact-sounds/Audio/impactPunch_medium_003.ogg |
| `sfx/hit_melee_05.ogg` | impact-sounds/Audio/impactPunch_medium_004.ogg |
| `sfx/hit_heavy_01.ogg` | impact-sounds/Audio/impactPunch_heavy_000.ogg |
| `sfx/hit_heavy_02.ogg` | impact-sounds/Audio/impactPunch_heavy_001.ogg |
| `sfx/hit_heavy_03.ogg` | impact-sounds/Audio/impactPunch_heavy_002.ogg |
| `sfx/hit_critical_01.ogg` | impact-sounds/Audio/impactBell_heavy_000.ogg, impact-sounds/Audio/impactGlass_heavy_003.ogg, impact-sounds/Audio/impactPunch_heavy_003.ogg |
| `sfx/hit_critical_02.ogg` | impact-sounds/Audio/impactBell_heavy_001.ogg, impact-sounds/Audio/impactGlass_heavy_004.ogg, impact-sounds/Audio/impactPunch_heavy_004.ogg |
| `sfx/defend_shield.ogg` | sci-fi-sounds/Audio/forceField_001.ogg |
| `sfx/miss_whoosh_01.ogg` | synthesis only (make_sfx.py) |
| `sfx/miss_whoosh_02.ogg` | synthesis only (make_sfx.py) |
| `sfx/miss_whoosh_03.ogg` | synthesis only (make_sfx.py) |
| `sfx/ko_dissolve.ogg` | synthesis only (make_sfx.py) |
| `sfx/level_up.ogg` | synthesis only (make_sfx.py) |
| `sfx/evolve_build.ogg` | synthesis only (make_sfx.py) |
| `sfx/evolve_burst.ogg` | impact-sounds/Audio/impactGlass_heavy_000.ogg |
| `sfx/fusion_merge.ogg` | synthesis only (make_sfx.py) |
| `sfx/victory_sting.ogg` | synthesis only (make_sfx.py) |
| `sfx/defeat_sting.ogg` | synthesis only (make_sfx.py) |
| `sfx/sigil_damage_01.ogg` | impact-sounds/Audio/impactGlass_heavy_002.ogg |
| `sfx/sigil_damage_02.ogg` | impact-sounds/Audio/impactGlass_heavy_003.ogg |
| `sfx/capsule_node.ogg` | digital-audio/Audio/powerUp3.ogg |
| `sfx/cast_fire.ogg` | synthesis only (make_sfx.py) |
| `sfx/cast_water.ogg` | synthesis only (make_sfx.py) |
| `sfx/cast_wind.ogg` | synthesis only (make_sfx.py) |
| `sfx/cast_earth.ogg` | impact-sounds/Audio/impactMining_002.ogg |
| `sfx/cast_thunder.ogg` | synthesis only (make_sfx.py) |
| `sfx/cast_ice.ogg` | impact-sounds/Audio/impactGlass_heavy_004.ogg |
| `sfx/cast_wood.ogg` | impact-sounds/Audio/impactWood_heavy_001.ogg |
| `sfx/cast_tech.ogg` | sci-fi-sounds/Audio/laserLarge_002.ogg |
| `sfx/cast_light.ogg` | synthesis only (make_sfx.py) |
| `sfx/cast_dark.ogg` | synthesis only (make_sfx.py) |
| `sfx/cast_arcane.ogg` | synthesis only (make_sfx.py) |
| `sfx/cast_space.ogg` | synthesis only (make_sfx.py) |
| `ambience/amb_nature.ogg` | synthesis only (make_sfx.py) |
| `ambience/amb_fire.ogg` | synthesis only (make_sfx.py) |
| `ambience/amb_water.ogg` | synthesis only (make_sfx.py) |
| `ambience/amb_ice.ogg` | synthesis only (make_sfx.py) |
| `ambience/amb_metal.ogg` | impact-sounds/Audio/impactMetal_light_000.ogg, impact-sounds/Audio/impactMetal_light_001.ogg, impact-sounds/Audio/impactMetal_light_002.ogg, impact-sounds/Audio/impactMetal_light_003.ogg, impact-sounds/Audio/impactMetal_light_004.ogg |
| `ambience/amb_wind.ogg` | synthesis only (make_sfx.py) |
| `ambience/amb_dark.ogg` | synthesis only (make_sfx.py) |
| `ambience/amb_ancient.ogg` | synthesis only (make_sfx.py) |
| `ambience/amb_space.ogg` | synthesis only (make_sfx.py) |
| `ambience/amb_crystal.ogg` | synthesis only (make_sfx.py) |
| `ambience/amb_aether.ogg` | synthesis only (make_sfx.py) |
| `ambience/amb_mixed.ogg` | synthesis only (make_sfx.py) |

## Mastering

One-shots: trim < -60 dBFS, max-momentary loudness -16 LUFS (UI -20 LUFS), 4x true-peak limiter at -1 dBTP. Ambience: integrated -26 LUFS, seamless 30 s loops. Music: integrated -16 LUFS (or less where the -1 dBTP ceiling binds), gain only.

## Voices

Generated with ElevenLabs (premade library voices only, no cloning) by `tools/eleven_voices.py`; see `voices/CASTING.json`. Subject to the ElevenLabs terms of the account that generated them.

## Music loop measurements

| Id | Seconds | Gain dB | LUFS | RMS last/first 50 ms | max sample jump at seam |
|---|---|---|---|---|---|
| `title` | 96.0 | -4.5 | -16.0 | -25.0 / -18.8 | 0.003 |
| `battle` | 69.82 | -6.1 | -16.0 | -17.8 / -17.4 | 0.03 |
| `boss` | 103.78 | -5.3 | -16.0 | -22.4 / -13.1 | 0.032 |
| `victory` | 67.76 | -4.3 | -16.0 | -34.2 / -15.7 | 0.002 |
| `defeat` | 60.0 | -4.7 | -16.0 | -29.4 / -12.9 | 0.001 |

<!-- music_build:begin (generated by tools/music_build.py credits - do not hand-edit) -->
## Per-level music (12 towers x explore / 3 battle takes / boss, final boss, stings)

Original score rendered locally with ACE-Step v1-3.5B by tools/music_acestep.py (instrumental prompts describing original styles; no artist, composer, game or franchise names).

Generator: ACE-Step v1-3.5B - code https://github.com/ace-step/ACE-Step (LICENSE: Apache-2.0), weights https://huggingface.co/ACE-Step/ACE-Step-v1-3.5B (model card `license: apache-2.0`), both checked 2026-10-21. Any row whose origin is a CC0 page (fallback path, `tools/music_curate.py`) lists that page; each such page showed CC0 as its sole licence when catalogued.

Processing (`tools/music_build.py master`): bar-aligned loop region + equal-power cross-fade at the seam, harmonic/percussive split (battle + boss -> `_base` / `_heat` stems, heat stem mono), -16 LUFS integrated / -1 dBTP (gain + look-ahead limiter, re-measured on the decoded OGG). Stings (`towers/Txx/victory.ogg`, `defeat.ogg`) are cut from the tower's battle take a (victory) / explore theme slowed -3 st (defeat), with a synthetic ring-out tail.

| Track | Source | Author | Page | Licence | Files |
|---|---|---|---|---|---|
| `T01_explore` | ACE-Step v1-3.5B render, seed 883120813 | - | - | Apache-2.0 model; no third-party audio | `towers/T01/explore.ogg` |
| `T01_battle_a` | ACE-Step v1-3.5B render, seed 1569469387 | - | - | Apache-2.0 model; no third-party audio | `towers/T01/battle_a_base.ogg`, `towers/T01/battle_a_heat.ogg` |
| `T01_battle_b` | ACE-Step v1-3.5B render, seed 1297075825 | - | - | Apache-2.0 model; no third-party audio | `towers/T01/battle_b_base.ogg`, `towers/T01/battle_b_heat.ogg` |
| `T01_battle_c` | ACE-Step v1-3.5B render, seed 1011662567 | - | - | Apache-2.0 model; no third-party audio | `towers/T01/battle_c_base.ogg`, `towers/T01/battle_c_heat.ogg` |
| `T01_boss` | ACE-Step v1-3.5B render, seed 1995616819 | - | - | Apache-2.0 model; no third-party audio | `towers/T01/boss_base.ogg`, `towers/T01/boss_heat.ogg` |
| `T02_explore` | ACE-Step v1-3.5B render, seed 455097960 | - | - | Apache-2.0 model; no third-party audio | `towers/T02/explore.ogg` |
| `T02_battle_a` | ACE-Step v1-3.5B render, seed 1065743560 | - | - | Apache-2.0 model; no third-party audio | `towers/T02/battle_a_base.ogg`, `towers/T02/battle_a_heat.ogg` |
| `T02_battle_b` | ACE-Step v1-3.5B render, seed 800250226 | - | - | Apache-2.0 model; no third-party audio | `towers/T02/battle_b_base.ogg`, `towers/T02/battle_b_heat.ogg` |
| `T02_battle_c` | ACE-Step v1-3.5B render, seed 1488316900 | - | - | Apache-2.0 model; no third-party audio | `towers/T02/battle_c_base.ogg`, `towers/T02/battle_c_heat.ogg` |
| `T02_boss` | ACE-Step v1-3.5B render, seed 33265821 | - | - | Apache-2.0 model; no third-party audio | `towers/T02/boss_base.ogg`, `towers/T02/boss_heat.ogg` |
| `T03_explore` | ACE-Step v1-3.5B render, seed 234435115 | - | - | Apache-2.0 model; no third-party audio | `towers/T03/explore.ogg` |
| `T03_battle_a` | ACE-Step v1-3.5B render, seed 1501160438 | - | - | Apache-2.0 model; no third-party audio | `towers/T03/battle_a_base.ogg`, `towers/T03/battle_a_heat.ogg` |
| `T03_battle_b` | ACE-Step v1-3.5B render, seed 1228611148 | - | - | Apache-2.0 model; no third-party audio | `towers/T03/battle_b_base.ogg`, `towers/T03/battle_b_heat.ogg` |
| `T03_battle_c` | ACE-Step v1-3.5B render, seed 1078062810 | - | - | Apache-2.0 model; no third-party audio | `towers/T03/battle_c_base.ogg`, `towers/T03/battle_c_heat.ogg` |
| `T03_boss` | ACE-Step v1-3.5B render, seed 993661752 | - | - | Apache-2.0 model; no third-party audio | `towers/T03/boss_base.ogg`, `towers/T03/boss_heat.ogg` |
| `T04_explore` | ACE-Step v1-3.5B render, seed 1780094946 | - | - | Apache-2.0 model; no third-party audio | `towers/T04/explore.ogg` |
| `T04_battle_a` | ACE-Step v1-3.5B render, seed 1148216463 | - | - | Apache-2.0 model; no third-party audio | `towers/T04/battle_a_base.ogg`, `towers/T04/battle_a_heat.ogg` |
| `T04_battle_b` | ACE-Step v1-3.5B render, seed 581740853 | - | - | Apache-2.0 model; no third-party audio | `towers/T04/battle_b_base.ogg`, `towers/T04/battle_b_heat.ogg` |
| `T04_battle_c` | ACE-Step v1-3.5B render, seed 1437309347 | - | - | Apache-2.0 model; no third-party audio | `towers/T04/battle_c_base.ogg`, `towers/T04/battle_c_heat.ogg` |
| `T04_boss` | ACE-Step v1-3.5B render, seed 641672064 | - | - | Apache-2.0 model; no third-party audio | `towers/T04/boss_base.ogg`, `towers/T04/boss_heat.ogg` |
| `T05_explore` | ACE-Step v1-3.5B render, seed 130652065 | - | - | Apache-2.0 model; no third-party audio | `towers/T05/explore.ogg` |
| `T05_battle_a` | ACE-Step v1-3.5B render, seed 1416074161 | - | - | Apache-2.0 model; no third-party audio | `towers/T05/battle_a_base.ogg`, `towers/T05/battle_a_heat.ogg` |
| `T05_battle_b` | ACE-Step v1-3.5B render, seed 1446587915 | - | - | Apache-2.0 model; no third-party audio | `towers/T05/battle_b_base.ogg`, `towers/T05/battle_b_heat.ogg` |
| `T05_battle_c` | ACE-Step v1-3.5B render, seed 1127505565 | - | - | Apache-2.0 model; no third-party audio | `towers/T05/battle_c_base.ogg`, `towers/T05/battle_c_heat.ogg` |
| `T05_boss` | ACE-Step v1-3.5B render, seed 1982749733 | - | - | Apache-2.0 model; no third-party audio | `towers/T05/boss_base.ogg`, `towers/T05/boss_heat.ogg` |
| `T06_explore` | ACE-Step v1-3.5B render, seed 1485041508 | - | - | Apache-2.0 model; no third-party audio | `towers/T06/explore.ogg` |
| `T06_battle_a` | ACE-Step v1-3.5B render, seed 1209701554 | - | - | Apache-2.0 model; no third-party audio | `towers/T06/battle_a_base.ogg`, `towers/T06/battle_a_heat.ogg` |
| `T06_battle_b` | ACE-Step v1-3.5B render, seed 643397896 | - | - | Apache-2.0 model; no third-party audio | `towers/T06/battle_b_base.ogg`, `towers/T06/battle_b_heat.ogg` |
| `T06_battle_c` | ACE-Step v1-3.5B render, seed 1365133726 | - | - | Apache-2.0 model; no third-party audio | `towers/T06/battle_c_base.ogg`, `towers/T06/battle_c_heat.ogg` |
| `T06_boss` | ACE-Step v1-3.5B render, seed 1811382923 | - | - | Apache-2.0 model; no third-party audio | `towers/T06/boss_base.ogg`, `towers/T06/boss_heat.ogg` |
| `T07_explore` | ACE-Step v1-3.5B render, seed 1636631335 | - | - | Apache-2.0 model; no third-party audio | `towers/T07/explore.ogg` |
| `T07_battle_a` | ACE-Step v1-3.5B render, seed 1351762828 | - | - | Apache-2.0 model; no third-party audio | `towers/T07/battle_a_base.ogg`, `towers/T07/battle_a_heat.ogg` |
| `T07_battle_b` | ACE-Step v1-3.5B render, seed 1382383158 | - | - | Apache-2.0 model; no third-party audio | `towers/T07/battle_b_base.ogg`, `towers/T07/battle_b_heat.ogg` |
| `T07_battle_c` | ACE-Step v1-3.5B render, seed 1197903520 | - | - | Apache-2.0 model; no third-party audio | `towers/T07/battle_c_base.ogg`, `towers/T07/battle_c_heat.ogg` |
| `T07_boss` | ACE-Step v1-3.5B render, seed 695581998 | - | - | Apache-2.0 model; no third-party audio | `towers/T07/boss_base.ogg`, `towers/T07/boss_heat.ogg` |
| `T08_explore` | ACE-Step v1-3.5B render, seed 125524214 | - | - | Apache-2.0 model; no third-party audio | `towers/T08/explore.ogg` |
| `T08_battle_a` | ACE-Step v1-3.5B render, seed 711164929 | - | - | Apache-2.0 model; no third-party audio | `towers/T08/battle_a_base.ogg`, `towers/T08/battle_a_heat.ogg` |
| `T08_battle_b` | ACE-Step v1-3.5B render, seed 948980155 | - | - | Apache-2.0 model; no third-party audio | `towers/T08/battle_b_base.ogg`, `towers/T08/battle_b_heat.ogg` |
| `T08_battle_c` | ACE-Step v1-3.5B render, seed 1335327021 | - | - | Apache-2.0 model; no third-party audio | `towers/T08/battle_c_base.ogg`, `towers/T08/battle_c_heat.ogg` |
| `T08_boss` | ACE-Step v1-3.5B render, seed 1375593467 | - | - | Apache-2.0 model; no third-party audio | `towers/T08/boss_base.ogg`, `towers/T08/boss_heat.ogg` |
| `T09_explore` | ACE-Step v1-3.5B render, seed 268455093 | - | - | Apache-2.0 model; no third-party audio | `towers/T09/explore.ogg` |
| `T09_battle_a` | ACE-Step v1-3.5B render, seed 1314616127 | - | - | Apache-2.0 model; no third-party audio | `towers/T09/battle_a_base.ogg`, `towers/T09/battle_a_heat.ogg` |
| `T09_battle_b` | ACE-Step v1-3.5B render, seed 1612484229 | - | - | Apache-2.0 model; no third-party audio | `towers/T09/battle_b_base.ogg`, `towers/T09/battle_b_heat.ogg` |
| `T09_battle_c` | ACE-Step v1-3.5B render, seed 689929747 | - | - | Apache-2.0 model; no third-party audio | `towers/T09/battle_c_base.ogg`, `towers/T09/battle_c_heat.ogg` |
| `T09_boss` | ACE-Step v1-3.5B render, seed 594254942 | - | - | Apache-2.0 model; no third-party audio | `towers/T09/boss_base.ogg`, `towers/T09/boss_heat.ogg` |
| `T10_explore` | ACE-Step v1-3.5B render, seed 1398903248 | - | - | Apache-2.0 model; no third-party audio | `towers/T10/explore.ogg` |
| `T10_battle_a` | ACE-Step v1-3.5B render, seed 1941997365 | - | - | Apache-2.0 model; no third-party audio | `towers/T10/battle_a_base.ogg`, `towers/T10/battle_a_heat.ogg` |
| `T10_battle_b` | ACE-Step v1-3.5B render, seed 1939096207 | - | - | Apache-2.0 model; no third-party audio | `towers/T10/battle_b_base.ogg`, `towers/T10/battle_b_heat.ogg` |
| `T10_battle_c` | ACE-Step v1-3.5B render, seed 647582233 | - | - | Apache-2.0 model; no third-party audio | `towers/T10/battle_c_base.ogg`, `towers/T10/battle_c_heat.ogg` |
| `T10_boss` | ACE-Step v1-3.5B render, seed 467233314 | - | - | Apache-2.0 model; no third-party audio | `towers/T10/boss_base.ogg`, `towers/T10/boss_heat.ogg` |
| `T11_explore` | ACE-Step v1-3.5B render, seed 1142588819 | - | - | Apache-2.0 model; no third-party audio | `towers/T11/explore.ogg` |
| `T11_battle_a` | ACE-Step v1-3.5B render, seed 617437195 | - | - | Apache-2.0 model; no third-party audio | `towers/T11/battle_a_base.ogg`, `towers/T11/battle_a_heat.ogg` |
| `T11_battle_b` | ACE-Step v1-3.5B render, seed 84655537 | - | - | Apache-2.0 model; no third-party audio | `towers/T11/battle_b_base.ogg`, `towers/T11/battle_b_heat.ogg` |
| `T11_battle_c` | ACE-Step v1-3.5B render, seed 1913425191 | - | - | Apache-2.0 model; no third-party audio | `towers/T11/battle_c_base.ogg`, `towers/T11/battle_c_heat.ogg` |
| `T11_boss` | ACE-Step v1-3.5B render, seed 1498424711 | - | - | Apache-2.0 model; no third-party audio | `towers/T11/boss_base.ogg`, `towers/T11/boss_heat.ogg` |
| `T12_explore` | ACE-Step v1-3.5B render, seed 107095382 | - | - | Apache-2.0 model; no third-party audio | `towers/T12/explore.ogg` |
| `T12_battle_a` | ACE-Step v1-3.5B render, seed 1999984392 | - | - | Apache-2.0 model; no third-party audio | `towers/T12/battle_a_base.ogg`, `towers/T12/battle_a_heat.ogg` |
| `T12_battle_b` | ACE-Step v1-3.5B render, seed 1996911282 | - | - | Apache-2.0 model; no third-party audio | `towers/T12/battle_b_base.ogg`, `towers/T12/battle_b_heat.ogg` |
| `T12_battle_c` | ACE-Step v1-3.5B render, seed 570794532 | - | - | Apache-2.0 model; no third-party audio | `towers/T12/battle_c_base.ogg`, `towers/T12/battle_c_heat.ogg` |
| `T12_boss` | ACE-Step v1-3.5B render, seed 1444006697 | - | - | Apache-2.0 model; no third-party audio | `towers/T12/boss_base.ogg`, `towers/T12/boss_heat.ogg` |
| `final_boss` | ACE-Step v1-3.5B render, seed 259115131 | - | - | Apache-2.0 model; no third-party audio | `final/final_boss_base.ogg`, `final/final_boss_heat.ogg` |

### Loop measurements (decoded OGG, full mix)

| Track | Seconds | LUFS | dBTP | seam jump / p99 step | seam flux / median |
|---|---|---|---|---|---|
| `T01_battle_a` | 64.0 | -16.13 | -4.56 | 0.01 / 0.023 | 1.98 |
| `T01_battle_b` | 78.3 | -16.0 | -3.24 | 0.0093 / 0.0351 | 1.35 |
| `T01_battle_c` | 62.0 | -16.15 | -3.85 | 0.0078 / 0.02 | 1.79 |
| `T01_boss` | 92.7 | -16.0 | -5.49 | 0.0026 / 0.0325 | 1.39 |
| `T01_explore` | 60.6 | -16.0 | -4.42 | 0.0125 / 0.0386 | 2.36 |
| `T02_battle_a` | 58.0 | -16.0 | -4.82 | 0.0248 / 0.0459 | 2.51 |
| `T02_battle_b` | 58.8 | -16.0 | -4.79 | 0.0096 / 0.0285 | 1.92 |
| `T02_battle_c` | 57.6 | -16.15 | -6.42 | 0.0024 / 0.0218 | 3.32 |
| `T02_boss` | 65.1 | -16.0 | -5.1 | 0.0044 / 0.0247 | 3.27 |
| `T02_explore` | 72.1 | -16.04 | -4.91 | 0.0038 / 0.0314 | 3.77 |
| `T03_battle_a` | 85.7 | -16.0 | -4.49 | 0.0168 / 0.0478 | 2.44 |
| `T03_battle_b` | 79.1 | -16.0 | -3.98 | 0.0055 / 0.0608 | 1.79 |
| `T03_battle_c` | 66.7 | -16.0 | -4.27 | 0.0072 / 0.0307 | 2.58 |
| `T03_boss` | 57.2 | -16.0 | -3.1 | 0.0144 / 0.0325 | 3.65 |
| `T03_explore` | 58.5 | -16.04 | -4.65 | 0.001 / 0.0554 | 3.55 |
| `T04_battle_a` | 69.1 | -16.0 | -4.67 | 0.0055 / 0.0323 | 1.96 |
| `T04_battle_b` | 64.6 | -16.0 | -3.32 | 0.0285 / 0.0742 | 1.58 |
| `T04_battle_c` | 60.0 | -16.0 | -4.21 | 0.001 / 0.0294 | 3.5 |
| `T04_boss` | 60.0 | -16.0 | -4.48 | 0.001 / 0.0353 | 1.51 |
| `T04_explore` | 62.8 | -16.01 | -5.35 | 0.0037 / 0.022 | 1.69 |
| `T05_battle_a` | 57.4 | -16.0 | -5.02 | 0.0141 / 0.0297 | 3.59 |
| `T05_battle_b` | 84.8 | -16.0 | -3.39 | 0.0021 / 0.0354 | 1.77 |
| `T05_battle_c` | 64.9 | -16.0 | -3.43 | 0.0111 / 0.0343 | 2.13 |
| `T05_boss` | 63.0 | -16.0 | -5.95 | 0.0026 / 0.0193 | 1.79 |
| `T05_explore` | 56.4 | -16.12 | -4.02 | 0.0076 / 0.0605 | 1.62 |
| `T06_battle_a` | 65.2 | -16.0 | -4.23 | 0.009 / 0.033 | 2.85 |
| `T06_battle_b` | 74.3 | -16.0 | -4.24 | 0.0103 / 0.032 | 3.05 |
| `T06_battle_c` | 67.5 | -16.0 | -2.78 | 0.0065 / 0.0316 | 1.55 |
| `T06_boss` | 59.8 | -16.0 | -6.61 | 0.0086 / 0.0372 | 2.99 |
| `T06_explore` | 74.3 | -16.06 | -5.18 | 0.0096 / 0.0247 | 1.78 |
| `T07_battle_a` | 85.4 | -16.0 | -5.67 | 0.0067 / 0.0193 | 2.6 |
| `T07_battle_b` | 58.5 | -16.0 | -4.29 | 0.0033 / 0.0322 | 3.47 |
| `T07_battle_c` | 90.6 | -16.0 | -4.01 | 0.0038 / 0.0296 | 4.02 |
| `T07_boss` | 78.0 | -16.0 | -5.47 | 0.0013 / 0.0146 | 2.2 |
| `T07_explore` | 57.0 | -16.06 | -5.74 | 0.0077 / 0.0619 | 1.29 |
| `T08_battle_a` | 78.7 | -16.0 | -3.7 | 0.003 / 0.0275 | 2.3 |
| `T08_battle_b` | 65.1 | -16.0 | -2.31 | 0.02 / 0.0667 | 4.26 |
| `T08_battle_c` | 76.4 | -16.0 | -3.4 | 0.0186 / 0.0427 | 1.49 |
| `T08_boss` | 94.5 | -16.0 | -2.87 | 0.0083 / 0.0315 | 3.3 |
| `T08_explore` | 78.3 | -16.05 | -5.41 | 0.0001 / 0.043 | 1.28 |
| `T09_battle_a` | 83.1 | -16.0 | -4.31 | 0.0048 / 0.0308 | 4.29 |
| `T09_battle_b` | 80.0 | -16.0 | -4.23 | 0.0057 / 0.0303 | 2.17 |
| `T09_battle_c` | 69.3 | -16.0 | -4.93 | 0.006 / 0.0529 | 3.59 |
| `T09_boss` | 76.7 | -16.0 | -4.74 | 0.0072 / 0.0167 | 3.91 |
| `T09_explore` | 78.4 | -16.03 | -4.37 | 0.0004 / 0.0413 | 2.64 |
| `T10_battle_a` | 80.8 | -16.0 | -4.94 | 0.0124 / 0.0248 | 2.86 |
| `T10_battle_b` | 87.3 | -16.0 | -3.95 | 0.0056 / 0.0405 | 1.87 |
| `T10_battle_c` | 59.4 | -16.0 | -2.41 | 0.0057 / 0.0602 | 2.82 |
| `T10_boss` | 57.8 | -16.0 | -4.9 | 0.0012 / 0.0356 | 2.2 |
| `T10_explore` | 67.2 | -16.0 | -3.55 | 0.0097 / 0.0255 | 1.34 |
| `T11_battle_a` | 67.2 | -16.0 | -2.91 | 0.0011 / 0.0435 | 1.65 |
| `T11_battle_b` | 56.1 | -16.0 | -3.86 | 0.0151 / 0.0327 | 1.78 |
| `T11_battle_c` | 70.0 | -16.0 | -5.02 | 0.0126 / 0.0371 | 2.61 |
| `T11_boss` | 75.8 | -16.0 | -3.58 | 0.0263 / 0.0401 | 0.88 |
| `T11_explore` | 66.4 | -16.06 | -3.12 | 0.0007 / 0.0468 | 2.56 |
| `T12_battle_a` | 56.4 | -16.0 | -5.03 | 0.0068 / 0.0328 | 3.53 |
| `T12_battle_b` | 89.9 | -16.0 | -4.58 | 0.0008 / 0.0392 | 1.31 |
| `T12_battle_c` | 86.7 | -16.0 | -3.67 | 0.0024 / 0.0487 | 5.04 |
| `T12_boss` | 88.9 | -16.0 | -4.2 | 0.0108 / 0.0288 | 1.16 |
| `T12_explore` | 59.6 | -16.09 | -4.74 | 0.0081 / 0.0411 | 0.66 |
| `final_boss` | 75.1 | -16.0 | -4.31 | 0.0069 / 0.0263 | 1.48 |
<!-- music_build:end -->
