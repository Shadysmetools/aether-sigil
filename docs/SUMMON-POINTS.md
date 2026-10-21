# Vessels and Summon Points (SP)

Owner request (Shady, 2026-10-21): "monsters are capsules — you spend points to summon them; when the capsule cracks it turns into a statue like chess", plus "before the match the player chooses monsters and places them; the game starts with the Symbol (our Player Sigil) and the chosen monsters sitting in capsules on the board". The coordinator's research brief (the same day) set the structure. Every rule here is our own, with our own names and numbers. All numbers live in `game/data/game_rules.json` and can be tuned there.

On screen the sealed shell is called a **Vessel** (`terms.vessel`, one localisation key). The word "capsule" is not used as a player-facing noun, for IP reasons. Code and data keep `capsule` internally. Capsule **nodes** (map tiles) keep their name and behaviour.

## 1. Match flow

1. **Draft (pre-match).** Pick up to **6** Vessels from your roster (roster max 12). Their **Bond** costs must total no more than the tower's cap. The enemy always brings its whole bible `enemy_roster`, because the bible is the source of truth for rosters.
2. **Placement (pre-match, on the battle board).** Each side has a **home zone**: walkable tiles within 2 (Manhattan) of its spawn tiles or its painted Symbol tile, closer to its own Symbol than to the enemy's. The zone excludes capsule nodes, relics, warp gates and the enemy's spawn tiles. Both Sigils are placed first. Then the Vessels are placed **alternately, one at a time**. The side whose Vessels have the lower total initiative (the "initiative loser") places first; on a tie the player does. At most **2 Vessels may touch your own Sigil** (Chebyshev 1). The enemy's Vessel positions are revealed, but their contents stay hidden until cracked. On all 120 maps, radius 2 leaves at least 6 spare tiles for each side (`test_data.gd` checks this for every stage).
3. **The match** starts with both Sigils and every sealed Vessel on the board. No monster is on the board yet, except the ruins-stage dormant statues the bible already had.

## 2. The Sigil is an actor

- The Sigil has its own initiative slot at **mid speed (40)**. Monsters score `move x 10 + range`, so the Sigil acts after move-4+ monsters and before move-3 ones.
- Its activation is **Move 1 tile**, then one action: **Crack**, **Defend** (takes x0.5 damage until its next activation) or **Wait**.
- **Crack** spends SP to open one of your Vessels that is within **Chebyshev 4** of your Sigil. Vessels further away are out of reach, so the Sigil has to advance. The monster appears on the Vessel's tile, or on a capsule node you hold, as a **statue** (`dormant`). It joins the **end of the current round's** turn order and wakes at its first activation. Only one crack per Sigil turn, and cracking ends the Sigil's activation.
- Sealed Vessels have no initiative slot.

## 3. Numbers

| Rarity | Crack (SP) | Bond | Vessel HP | KO backlash to own Sigil |
|---|---|---|---|---|
| Common | 2 | 10 | 30 | 8 |
| Uncommon | 3 | 15 | 40 | 12 |
| Rare | 4 | 22 | 50 | 16 |
| Epic | 6 | 30 | 60 | 20 |
| Mythic | 7 | 35 | 70 | 24 |
| Legendary | 8 | 40 | 80 | 28 |

- **Evolved** monsters cost +1 SP to crack (a flat +1, not +1 per stage) and +5 Bond per evolution stage. A **fused** monster counts as evolved for SP. Its Bond is **80% of its two parents' Bond**, stored on the instance when the fusion happens.
- **Bond cap by tower:** 60, 65, 70, 75, 80, 85, 90, 95, 100, 105, 110, 120. The default squad of 6 Commons costs exactly 60. The `draft` cap trims the strongest-first auto-draft when an evolved squad outgrows it. In the tuned campaign it trimmed 3 of 120 drafts.
- **SP:** start 4. From round 2, each own Sigil activation gives **+3**, plus **+1 per capsule node held**, up to a **cap of 12**. Holding nodes speeds up your deployment, so contesting nodes now matters.
- **Stage rule** (24 stages, L04 and L08 of every tower): "Vessels cost +1 SP to crack". Every crack on that stage costs 1 SP more. This replaces the pre-SP rule "Capsules cost 1 AP to deploy", because Action Points no longer exist. `tools/apply_summon_points.py` rewrote the text in both bibles, the CSV exports, `docs/data/stage_difficulty.csv`, `docs/tools/aether_design.py` and `docs/BALANCE-REPORT.md`. The script is idempotent and has a `--check` mode.
- **Vessels can be attacked.** They take hits like the Symbol: no element, **DEF 0**, HP `30 + 10 x tier` (tier = rarity index, Common 0 to Legendary 5). A **broken Vessel** loses its monster for the match and deals **10** damage to its own Sigil. Vessels block movement.
- **KO backlash:** a knocked-out monster deals `8 + 4 x tier` damage to its own Sigil.
- **KO policy:** a knocked-out monster, or a broken Vessel, is **lost for the match**. Nothing recharges. Vessels are finite pieces, like chess pieces, and a lost piece is gone. A recharge rule would also need a re-placement step mid-battle.
- **Anti-bait:** a monster cracked *this round* deals x0.75 to a Sigil, so a freshly cracked monster cannot snipe a Sigil at full strength.

## 4. Winning

You win when any of these happens:

- the enemy Sigil drops to 0 HP (180);
- **Rout**: the enemy has no monster on the board and no sealed Vessel;
- on relic stages, the bible's relic win (unchanged).

The match is capped at **30 rounds**. After round 30 the side with the higher Sigil HP % wins ("time"). If both sides are equal, the match is a draw. Wiping out every enemy monster used to be a bonus objective only; under Rout it now wins, once no enemy Vessel is left either.

## 5. AI (per `opponent_style`)

| Style | Placement plan | Crack policy |
|---|---|---|
| rush attacker, mobility specialist | front (nearest the enemy Symbol) | spends at once; picks highest move / attack |
| defensive fortress | wall (around its own Sigil) | banks 4 SP; spends early only when threatened or empty-handed |
| counter-attacker | wall | banks 3 |
| trap engineer, long-range sniper | wall | banks 2 |
| resource thief | nodes (nearest capsule nodes) | cracks onto held nodes / near open nodes; values breaking Vessels |
| summoner | spawn | cheapest first (floods the board) |
| others | spawn | spends at once |

- The AI acts only through `legal_*` and `apply()`, so it cannot overspend. `test_sim.gd` checks every activation of 360 simulated battles: SP stays within 0..cap, no unit stands on a Vessel, and every reserve monster has a Vessel.
- The Sigil steps toward a Vessel that is out of crack range when it cannot crack anything now. It Defends when an enemy monster is within 3 tiles, and otherwise Waits.
- Target scoring weighs the Sigil, kills and Vessels (`vessel_bonus`, plus a kill bonus when the hit breaks one), so a hittable Vessel does not pull every unit off the Symbol.

## 6. Evolution and fusion

Evolution and fusion happen only between matches, on the meta screens, as before. Nothing evolves mid-battle.

## 7. Save schema v4

Save v4 adds `bond` on fused instances. Older saves migrate as follows:

- **Fused monsters** get their Bond from their parents' base ids, using bible rarity at evolution 0.
- **Squads of 4** (from v1 and v3 saves) keep their 4 and are topped up to 6 with the strongest other owned monsters.

`test_progression.gd test_migration_v4` covers both.

## 8. Code map and board contract

- `game/scripts/summon.gd` holds costs, Bond, Vessel HP, the draft cap/check and the auto-draft.
- `game/scripts/game_state.gd` holds the placement phase (`setup(..., auto_start=false)`, `placement_queue`, `place_sigil`, `place_capsule`, `auto_place_step`, `start_battle`), SP (`sp`, `sp_income`, `summon_cost`), Crack (`deploy`), the Sigil's move and defend actions, Vessels as targets, backlash, Rout and the time limit. `setup()` with the default arguments auto-places both sides and starts at once; tests, tools and sims use this.
- `game/scripts/ai.gd` holds `_sigil_turn` and `_crack_choice`, with the style knobs `sp_bank`, `crack_nodes` and `vessel_bonus`.
- `game/scripts/ui.gd` has a section at the end of the file with the draft screen (Bond, SP and Vessel HP per monster, total against the cap), placement on the board (gold tiles, tray pick, then tap; "Start battle" auto-places the rest), the Vessel tray (icon, name, SP cost, disabled when unaffordable or out of range) and the HUD line `SP n/12 (+k next turn)`. A stage tap, Next and Retry (with the last team preselected) open the draft. `start_stage(id)` (tests, demo, screenshots) skips straight to an auto draft and auto placement. Result text covers rout and time wins and losses.
- **Animation hooks (guarded with `has_method`):**
  - `board.play_summon(unit, sp_cost)` after a crack. `state.last_crack = {unit, cost}`.
  - `board.play_vessel_break(vessel)` once per broken Vessel. `state.last_break` is the Vessel dict.
- **Data the boards should draw:**
  - `state.capsules[side]`: an Array of `{mon, owner, pos, hp, max_hp}` (pos `(-1,-1)` means off-board), with `state.capsule_at(c)` and `state.capsules_on_board(side)` as helpers.
  - The 2D board and the minimap draw Vessels now. The 3D board does not yet. During placement, tiles are highlighted gold.
  - The Sigil can now move: `state.symbol_pos` changes and the grid is edited in place (during placement the grid is replaced by a copy, so the 3D board rebuilds).

## 9. Balance

All runs are AI vs AI and seeded, so they are reproducible. The **gate** is RUN C of `game/tests/test_sim.gd`: a progressing player plays T01 to T12 in order, once per stage, with XP, evolutions and 2 fusions. It must reach 45-55% player wins overall and 3-7/10 in every tower.

| | Before (2026-10-21: squad of 4, both Sigils first, 2 free summons/turn, 60-round cap) | After (Vessels + SP, squad of 6, curve re-tuned) |
|---|---|---|
| RUN C: progressing player, overall | **60/120 = 50%** (6 capped) | **62/120 = 52%** (0 draws) |
| T01 | 6/3/1 | 5/5 |
| T02 | 5/4/1 | 7/3 |
| T03 | 6/4/0 | 5/5 |
| T04 | 6/4/0 | 7/3 |
| T05 | 7/1/2 | 6/4 |
| T06 | 4/5/1 | 7/3 |
| T07 | 3/7/0 | 5/5 |
| T08 | 6/4/0 | 3/7 |
| T09 | 4/5/1 | 4/6 |
| T10 | 4/6/0 | 5/5 |
| T11 | 5/5/0 | 3/7 |
| T12 | 4/6/0 | 5/5 |
| RUN C: average battle length | not reported (RUN A: 12.3 rounds) | 10.9 rounds (RUN A: 9.6) |
| RUN C: how battles end | symbol / relics | P symbol 42, P rout 18, E rout 43, E symbol 9, relics 6, time 2 |
| RUN A (fixed default squad, no progression; info only) | 9/120 = 8% | 21/120 = 18% |
| RUN B (4 average Commons, control; info only) | 3/120 = 3% | 2/120 = 2% |

(Tower cells are player wins / enemy wins / capped or drawn, out of 10.)

**Tuning path** (`game/tests/tune_sp.gd -- key=value ...`; "base" is the new flat `difficulty.enemy_stat_base_pct`):

- Old curve: 95% player wins, T01-T05 all 10/10. Six Vessels against slower, pricier enemy cracks, plus Rout, overwhelm a stat curve built for 4 monsters.
- Enemy SP bonuses barely moved it: +2 income/+4 start gave 92%; +3/+8 gave 89%. SP is not the bottleneck. The 1-crack-per-turn limit paces both sides.
- Raising the per-tower % alone gave 84% at 15%, 56% at 20% (but T01-T03 10/10 and T11 0/10) and 37% at 25%. Early towers stayed trivial because the per-tower term is 0 at T01, so a flat base was added.
- base 40 / 12% gave 48% (T11 1/10); 40 / 10% gave 54% (T03 8, T08 1).
- **Chosen: base 42 / 10% per tower, with T02 +10%, T03 +25% and T08 -15%.** This gives 52%, with every tower 3-7/10. T08 is the Ancient tower, whose 3 dormant statues start on the board and so get a head start. T03 kept winning 8/10 at small adjustments.

**T08 and T11 sit at 3/10, the gate's lower bound.** The runs are seeded, so the gate passes reliably, but any change to XP, Bond, SP or Vessel numbers will probably need a re-tune. The player's XP snowball makes the result sensitive to the curve. Re-run `tune_sp.gd` after any change to XP, Bond, SP or Vessel numbers.

## 10. Open items (animation agent / later)

- **The 3D board does not draw Vessels yet.** In battle they are invisible tiles that block movement and can be attacked. Only the 2D board, the minimap and the gold placement highlights show them. Draw them from `state.capsules`.
- **The Sigil moves in battle.** `symbol_pos` changes and the grid is edited in place (no new grid reference), so the 3D board must re-read `symbol_pos` on sync to move the crystal.
- **Bible text:** 50 monster `ability_description`s and 4 core-loop / creative / sample lines still use "capsule" as the shell noun ("Capsule ready."). The story and trigger files have none. These were left for the story writer to rewrite.
