"""Design definitions (prose + numbers) used by aether_report.py.
These are PROPOSALS by the balance analyst, not data. Kept in code so the docs are generated, not typed."""

# ------------------------------------------------------------------ rules gaps (stats the data lacks)
GAPS = [
    ("Initiative", "`init = 10*move + attack/10`, ties broken by lower `id`. Recomputed each round, so Storm Dash/slow effects matter. Players and enemies interleave in one queue."),
    ("Action economy", "On its turn a unit may Move (up to `move` tiles, BFS over walkable tiles) and then take ONE of Attack / Skill / Defend / Wait. Wait moves the unit to the end of the current round's queue once per round."),
    ("Accuracy", "Base hit chance 90%. High ground +15 (cap 100). Mist Veil target -30. Defend gives the defender -10 to be hit. A miss deals 0."),
    ("Critical hits", "10% crit chance, crit deals x1.5. Frost Lock procs only on crits, per its text."),
    ("Defend", "Until the unit's next turn: incoming damage x0.5 (applied after the max(1, ...) floor, rounded up) and it cannot be displaced."),
    ("Damage pipeline", "`dmg = max(1, atk - def)` -> x element (1.25 / 1.0 / 0.8) -> x high ground 1.30 -> x terrain-match 1.20 -> x ability modifiers -> x crit 1.5 -> x Defend 0.5 -> round half up, min 1."),
    ("High ground", "`elevation` tiles: +30% damage, +15 accuracy, +1 range, only when the attacker stands on elevation and the target does not."),
    ("Water", "Entering a `water` tile costs 2 movement (i.e. -1 move). Ending a turn on water deals 5% max HP (round up)."),
    ("Hazard", "Ending a turn on a `hazard` tile deals tier x 4% max HP (tier from the stage's `<Theme> hazard tier N` string; default tier 2)."),
    ("Line of sight", "Bresenham line between tile centres. `obstacle` and `stone` (treated as ruins/columns) block LOS for ranged attacks (range >= 2). Units do not block LOS."),
    ("Bridges", "`bridge` tiles are ordinary walkable tiles. Because the maps make them 1-wide, the rule needs no code: a unit on a bridge blocks passage. Units cannot swap places."),
    ("Terrain-family mapping", "forest->Nature, lava->Fire, water->Water, ice->Ice, metal->Tech, sky->Wind, shadow->Dark, stone/ruins->Earth, crystal->Earth, space->Space, rift->Arcane. `mixed`, `ground` and the rest are neutral. Tower themes map the same way (Metal->Tech, Ancient->Earth, Aether->Arcane, Crystal->Earth)."),
    ("Terrain bonus (base)", "A unit standing on a tile whose family equals its `element_family` deals +20% damage and takes -10% damage."),
    ("Action points (AP)", "Each side gains 2 AP at the start of its first unit's turn each round (max 4). AP is spent only by rules that say so (see 'Capsules cost 1 AP to deploy')."),
    ("Squad and deployment", "Player brings 4 monsters. The 3 `player_spawn` tiles hold the first 3. The 4th, plus any KO'd-and-revivable unit, sits in a capsule and can deploy onto an owned `capsule_node` or a free spawn tile instead of acting. Enemies deploy their roster the same way (the first 3 on `enemy_spawn`, the rest from capsules, one per round)."),
    ("Symbols", "A Symbol is a static, untargetable-by-skills object: HP = 150 + 25*(tower-1), DEF = 10 + 2*(tower-1). It is attacked like a unit and cannot act. The player Symbol has the same HP at the stage's tower number."),
]

# ------------------------------------------------------------------ opponent styles -> AI behaviour
AI = {
    "defensive fortress": dict(
        target="Lowest effective HP (hp/INC) unit inside its own half; ignores units outside its zone.",
        position="Holds the 3x3 ring around its Symbol and the nearest capsule node. Guardians stand on bridge or articulation tiles between the player and the Symbol. Never crosses the midline (row/col 6) before round 6.",
        defend="Defends when no target is in range after moving, or when HP < 50% and an ally can still attack.",
        skill="Uses shields/zone skills (Crystal Bloom, Lumen Ward, Gravity Well) on the turn an enemy first enters its half.",
        knob="aggro_radius = 4 tiles from own Symbol"),
    "trap engineer": dict(
        target="The unit with the lowest move (it can't escape zones).",
        position="Pre-places zones and terrain on chokepoints (bridges, articulation tiles) in rounds 1-2, then kites at range 1 tile beyond the player's move+range.",
        defend="Rarely. Only when it is adjacent to 2+ enemies.",
        skill="Prioritises Gravity Well, Crystal Bloom and Magma Trail on chokepoints. Hidden-trap hazards (when the stage lists them) are placed on the 2 tiles nearest the player spawn path.",
        knob="trap_budget = 2 per round"),
    "mobility specialist": dict(
        target="The isolated unit (no ally within 2 tiles), then backline (range >= 3).",
        position="Flanks: paths that avoid the player's threat area. Uses warp gates when that shortens the path by 3 or more. Ends turns out of the reach of 2+ enemies.",
        defend="Never. It Waits instead if it cannot attack safely.",
        skill="Movement skills first (Storm Dash, Phase Step, Astral Shift). Chases KO follow-ups.",
        knob="max_exposure = 1 attacker able to reach it"),
    "terrain controller": dict(
        target="Units standing on terrain that grants them a bonus, then the closest unit.",
        position="Seeks elevation and family-matching tiles first (scores tiles: +3 elevation, +2 family match, -2 water, -3 hazard).",
        defend="When it stands on elevation and no target is in range.",
        skill="Skills that alter tiles or zones (Crystal Bloom, Magma Trail, Gravity Well). Tidal Pull is used to drag players onto water or hazard tiles.",
        knob="tile_score weights above"),
    "summoner": dict(
        target="Whoever threatens its summons or capsules, then the nearest unit.",
        position="Stays 1 tile behind its front line. Contests capsule nodes and deploys the full roster as early as AP allows.",
        defend="When an enemy can reach it this round and it has already deployed.",
        skill="Spawn and copy skills (Crystal Bloom, Void Echo). Deploys a capsule every round it can.",
        knob="deploy_priority = max"),
    "counter-attacker": dict(
        target="The last unit that damaged it or an ally; otherwise none.",
        position="Waits inside its own half until the player commits (a player unit ends a turn within 5 tiles), then converges on that unit.",
        defend="Defaults to Defend when nothing has attacked this round (bait).",
        skill="Reactive skills (Prism Guard, Metal Skin and Mist Veil are passive; actives used are Ember Mark on the aggressor and Lumen Ward on the hit ally).",
        knob="commit_radius = 5"),
    "resource thief": dict(
        target="Units standing on capsule or relic nodes, then the player's Symbol carriers/escorts.",
        position="Rushes the nearest capsule/relic node, then contests nodes the player owns.",
        defend="When it stands on a node, so it keeps holding it.",
        skill="Tidal Pull (pull a holder off a node), Astral Shift (teleport onto a node).",
        knob="node_value = 3x a unit KO"),
    "long-range sniper": dict(
        target="Highest damage-per-hit target it can reach without moving into enemy reach.",
        position="Keeps distance >= its range and outside player move+range. Prefers elevation and LOS lanes behind obstacles/stone.",
        defend="When it cannot shoot this turn without stepping into danger.",
        skill="Damage amplifiers (Ember Mark, Chain Spark, Moon Pulse) when 2+ targets cluster.",
        knob="kite_margin = 1 tile"),
    "status-effect strategist": dict(
        target="The highest-power player unit (disable the carry).",
        position="Mid-range: stays within skill range of 2+ targets.",
        defend="Rarely. Only when all its skills are on cooldown and it is threatened.",
        skill="Always uses an available control skill (Frost Lock via crit-fishing, Gravity Well, Tidal Pull, Ember Mark) before plain attacks.",
        knob="skill_bias = 1.0 (always if available)"),
    "rush attacker": dict(
        target="Shortest BFS path to the player Symbol. It attacks units only if they block that path or can be KO'd this turn.",
        position="Full move toward the player Symbol every turn, all units together.",
        defend="Never.",
        skill="Offensive skills only (Moon Pulse, Chain Spark, Storm Dash chains).",
        knob="symbol_focus = 0.8"),
}

# ------------------------------------------------------------------ special rules
RULES = {
    "Terrain bonuses are doubled": "Every POSITIVE terrain modifier is doubled for both sides: high ground becomes +60% damage, +30 accuracy, +2 range, and terrain-family match becomes +40% damage dealt / -20% taken. Penalties (water move cost, water/hazard damage) are unchanged. Implement as `terrainBonusMult = 2` applied to the bonus delta, not to the total.",
    "Movement after a knockout is +1": "When a unit KOs an enemy (or the Symbol takes its final hit), that unit gets `move + 1` on its NEXT turn only, for both sides. It does not stack with itself; multiple KOs in one turn still give +1. It stacks with Storm Dash, which grants an immediate extra move.",
    "One random portal activates each round": "At the start of each round, pick one `warp_gate` tile uniformly at random (seeded RNG). A unit that ENTERS the active gate may teleport, as a free action, to any other warp gate or, if the map has only one gate, to the mirrored tile `(11-r, 11-c)` (or the nearest free walkable tile to it). The active gate glows. Inactive gates are plain ground.",
    "Capsules cost 1 AP to deploy": "Deploying from a capsule costs 1 AP from the side's pool (see Action points) in addition to the unit's action. With 2 AP per round, at most 2 deploys per round. When this rule is absent, deploys cost 0 AP.",
}
WINS = {
    "Defeat the enemy Symbol": "Victory when the enemy Symbol's HP reaches 0. Defeat when the player Symbol's HP reaches 0 OR all player units are KO'd with no capsules left. Wiping the enemy roster does not win by itself: the Symbol must still fall, but with no defenders it takes no extra rules.",
    "Defeat the enemy Symbol or secure 3 relic nodes": "Either the Symbol condition above, OR at the start of the player's round the player OWNS 3 nodes at once. A node (`relic` or `capsule_node` tile, because each map has only 1 relic, see the integrity section) is owned by the last side to end a unit's turn on it with no enemy unit adjacent. Same defeat condition. The enemy AI can also win by securing 3 nodes.",
}
OWNER_OBJECTIVES = {
    "defeat all": "Optional/secondary: if every enemy unit is KO'd and no enemy capsules remain, the enemy Symbol loses its DEF (becomes 0).",
    "protect the Player Sigil": "Already the loss condition of every stage (player Symbol HP 0 = defeat).",
    "activate capsule nodes": "Same ownership rule as relic nodes. An owned capsule node is a deploy point and restores 1 AP to its owner at round start.",
    "relic": "Optional scoring: owning the relic at battle end gives +1 reward tier. On relic-win stages it counts toward the 3 nodes.",
}

# ------------------------------------------------------------------ element chart (proposal)
RINGS = [
    ("Elemental", ["Fire", "Wind", "Earth", "Water"], "Fire burns away Wind, Wind erodes Earth, Earth dams Water, Water quenches Fire"),
    ("Wild", ["Lightning", "Tech", "Ice", "Nature"], "Lightning shorts Tech, Tech's engines melt Ice, Ice freezes Nature, Nature's roots ground Lightning"),
    ("Cosmic", ["Light", "Dark", "Arcane", "Space"], "Light banishes Dark, Dark corrupts Arcane, Arcane sigils bind Space, Space's gravity swallows Light"),
]
ELEM_ADV, ELEM_DIS = 1.25, 0.8

# ------------------------------------------------------------------ abilities spec
# trigger: active (Skill command) | passive | on-hit | on-crit | on-KO
ABIL = {
 "Ember Mark":     ("debuff", "active", "Skill: single enemy within range+1, LOS. Applies MARK (2 turns or until consumed). The next damaging hit on the target from any ally gets x1.30 and is typed as the marker's element. Cooldown 2.", ["status", "damage_mod"]),
 "Rift Bite":      ("damage", "passive", "Passive: basic attacks against a unit standing on a `warp_gate` (or the active portal tile) deal x1.50. Also applies to enemies on `rift` tiles if they are added.", ["damage_mod"]),
 "Chain Spark":    ("damage", "on-hit", "On a successful basic attack: a second hit jumps to the nearest other enemy within 2 tiles of the target (no LOS needed) for 50% of the dealt damage (min 1). Once per attack.", ["damage_mod", "aoe_select"]),
 "Moon Pulse":     ("damage", "active", "Skill: CHARGE (unit cannot move, Wait counts) for 2 of its own turns. On the 3rd turn it auto-fires: all enemies within radius 2 take x1.20 of base damage. Allies are unaffected. KO or displacement cancels the charge. Cooldown 3.", ["charge", "aoe_select", "damage_mod"]),
 "Verdant Renewal": ("heal", "passive", "Passive: at end of own turn on a Nature tile (`forest`, or any tile on a Nature-theme stage), heal 8% max HP (round up).", ["heal", "tile_query"]),
 "Metal Skin":     ("buff", "passive", "Passive: while HP > 50% max, incoming damage from basic attacks is x0.75 (applied before the min-1 floor is re-applied).", ["damage_mod"]),
 "Prism Guard":    ("buff", "passive", "Passive: the first incoming hit each round is x0.70. 25% of the prevented amount (min 1) is dealt back to the attacker if adjacent or in range 1.", ["damage_mod", "reflect"]),
 "Iron Root":      ("buff", "passive", "Passive: immune to displacement (Tidal Pull, pushes). If it did not move this turn, +20% DEF until its next turn (shown as a stance icon).", ["status", "stat_mod"]),
 "Mist Veil":      ("buff", "passive", "Passive: VEILED (attackers -30 accuracy) at battle start and after every turn it does not attack. Attacking removes it until its next non-attacking turn.", ["status"]),
 "Lumen Ward":     ("buff", "active", "Skill: adjacent ally (or self) gains WARD. It cancels the next status (Mark, Root, Slow, Pull) applied to it. Lasts until consumed or 3 turns. Cooldown 2.", ["status"]),
 "Frost Lock":     ("debuff", "on-crit", "On a critical basic attack: target is ROOTED (move = 0) for its next turn. Does not stack.", ["status"]),
 "Gravity Well":   ("debuff", "active", "Skill: target tile within range, LOS. Creates a 3x3 SLOW zone for 2 rounds. Units starting or entering inside have move -2 (min 1). Cooldown 3.", ["zone", "status"]),
 "Tidal Pull":     ("debuff", "on-hit", "On a successful basic attack at range >= 2: pull the target 1 tile toward this unit along the straight line if that tile is walkable and empty. No pull through obstacles. Iron Root/Defend/Ward resist.", ["displace"]),
 "Phase Step":     ("movement", "passive", "Passive: pathing may pass through ONE `obstacle`/`stone` tile per move (cannot end on it). After entering a tile whose terrain type differs from the start tile, +1 move this turn (once).", ["pathing_mod", "stat_mod"]),
 "Storm Dash":     ("movement", "on-KO", "On KO (by any damage this unit deals): may immediately move again up to floor(move/2) tiles. Once per turn.", ["extra_move"]),
 "Astral Shift":   ("movement", "active", "Skill (once per battle): teleport to any unoccupied special node (`capsule_node`, `relic`, `warp_gate`, `elevation`) in LOS or within 6 tiles. Counts as the unit's action. It may still Move before using it.", ["teleport", "tile_query"]),
 "Crystal Bloom":  ("summon", "active", "Skill: place a CRYSTAL (blocks movement and LOS, 20% of caster max HP, DEF = caster DEF) on an adjacent empty tile for 3 rounds or until destroyed. Max 1 per caster. Cooldown 2.", ["spawn_object"]),
 "Magma Trail":    ("summon", "passive", "Passive: each tile it leaves while moving becomes HEATED for 2 rounds. An enemy entering or ending on a heated tile takes 6% of its max HP (once per tile per turn). Max 6 heated tiles per unit.", ["tile_effect"]),
 "Soul Lantern":   ("utility", "passive", "Passive aura: reveals hidden traps and concealed capsules within radius 3 at the start of its turn (fog/stealth flag cleared for both sides' visibility).", ["reveal"]),
 "Void Echo":      ("utility", "active", "Skill: repeat the most recent ACTIVE skill used by any unit within 4 tiles in the last round, at 50% numbers (damage/heal/duration rounded down, min 1). It cannot echo Void Echo or Astral Shift. Cooldown 3.", ["copy_skill"]),
}
NEAR_DUP = [
    ("Damage reducers", ["Metal Skin", "Prism Guard", "Iron Root"], "one `incomingDamageModifier(unit, hit)` hook with per-ability predicates (HP>50% / first-hit-per-round / stationary)"),
    ("Conditional bonus damage", ["Rift Bite", "Ember Mark"], "one `outgoingDamageModifier` hook; Ember Mark adds a status, Rift Bite a tile check"),
    ("Movement restriction", ["Frost Lock", "Gravity Well"], "shared ROOT/SLOW status; Gravity Well applies it from a zone"),
    ("Bonus movement", ["Storm Dash", "Phase Step"], "shared `grantExtraMove(unit, n)`; triggers differ (KO vs terrain change)"),
    ("Hit riders", ["Chain Spark", "Tidal Pull"], "shared `onHit` dispatcher; jump-damage vs displace"),
    ("Tile/object creation", ["Crystal Bloom", "Magma Trail"], "shared `TileEffect` entity with TTL"),
]
