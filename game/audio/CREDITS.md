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
