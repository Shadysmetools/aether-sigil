## Headless rules tests. Run:
##   Godot_console.exe --headless --path <game dir> --script res://tests/test_rules.gd
## Exits with the number of failures (0 = green).
extends SceneTree

const Data = preload("res://scripts/data_loader.gd")
const GameState = preload("res://scripts/game_state.gd")
const AI = preload("res://scripts/ai.gd")
const Progress = preload("res://scripts/progress.gd")

const P := GameState.PLAYER
const E := GameState.ENEMY

var passed := 0
var failed := 0


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("  PASS  ", label)
	else:
		failed += 1
		print("  FAIL  ", label)


func eq(actual, expected, label: String) -> void:
	check(actual == expected, "%s (got %s, want %s)" % [label, str(actual), str(expected)])


func _initialize() -> void:
	print("Aether Sigil rules tests")
	if not Data.ensure_loaded():
		failed += 1
		print("  FAIL  data did not load")
	else:
		test_board()
		test_initiative()
		test_movement()
		test_commands()
		test_damage()
		test_accuracy_and_high_ground()
		test_line_of_sight()
		test_water_hazard()
		test_terrain_rule()
		test_summon()
		test_ap_rule()
		test_ko_rule()
		test_portal_rule()
		test_skills()
		test_wins_and_objectives()
		test_dormant()
		test_ai_legal()
		test_progress()
	print("%d pass / %d fail" % [passed, failed])
	quit(mini(failed, 255))  # exit codes wrap at 256


func stage_with_rule(text: String) -> String:
	for s in Data.stages():
		if s.special_rule == text and s.terrain != "Ancient" and s.stage_id != "T01-L01":
			return s.stage_id
	return ""


## All-ground board, Symbols at (1,1) and (10,10), no units, empty reserves, no rule (unless given),
## every roll hits. Tests make a unit act with s.activate(id).
func flat_state(rule_text: String = "") -> GameState:
	var s := GameState.new()
	s.setup(stage_with_rule(rule_text) if rule_text != "" else "T01-L02")
	for y in GameState.SIZE:
		for x in GameState.SIZE:
			s.grid[y][x] = "ground"
	s.symbol_pos = [Vector2i(1, 1), Vector2i(10, 10)]
	s.grid[1][1] = "player_symbol"
	s.grid[10][10] = "enemy_symbol"
	s.nodes = {}
	s.relics = {}
	s.portals = []
	s.spawn_tiles = [[Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)], [Vector2i(9, 10)]]
	s._field_cache = {}
	s.units = []
	s.reserve = [[], []]
	if rule_text == "":
		s.rule = {}
	s.relic_win = false
	s.hazard_tier = 1
	s.force_hit = 1
	s.activate(GameState.sigil_id(P))
	return s


func mon_of_family(fam: String) -> String:
	for id in Data.monster_ids():
		if Data.monster(id).element_family == fam:
			return id
	return ""


func mon_with_ability(ab: String) -> String:
	for id in Data.monster_ids():
		if Data.monster(id).ability == ab:
			return id
	return ""


func sq(i: int) -> String:
	return Data.squad_collection()[i]


func test_board() -> void:
	print("[board]")
	var s := GameState.new()
	check(s.setup("T01-L02"), "T01-L02 sets up")
	eq(s.grid.size(), 12, "12 rows")
	eq(s.grid[0].size(), 12, "12 columns")
	eq(s.symbol_pos[P], Vector2i(1, 1), "player Sigil from objectives")
	eq(s.symbol_pos[E], Vector2i(10, 10), "enemy Symbol from objectives")
	check(not s.spawn_tiles[P].has(s.symbol_pos[P]), "Sigil tile is not a deploy tile")
	eq(s.reserve[P], Data.default_squad(), "player reserve = default squad")
	eq(s.reserve[P].size(), 4, "squad of 4")
	eq(s.reserve[E].size(), s.stage.enemy_roster.size(), "enemy reserve = stage roster")
	var s2 := GameState.new()
	s2.setup("T01-L10")
	check(s2.symbol_pos[P] != Vector2i(-1, -1) and s2.tile_type(s2.symbol_pos[P]) == "player_symbol", "T01-L10 paints no player Symbol: placed on the first player spawn %s" % s2.symbol_pos[P])
	check(s2.spawn_tiles[P].all(func(c): return s2.stage.map_grid[c.y][c.x] == "player_spawn"), "spawns come from the grid's player_spawn tiles")


func test_initiative() -> void:
	print("[initiative turn order]")
	var s := flat_state()
	eq(s.actor_id, GameState.sigil_id(P), "round starts with the Player Sigil")
	var fast := s.place_unit(P, sq(0), Vector2i(3, 3))
	var slow := s.place_unit(E, sq(1), Vector2i(6, 6))
	var tie_p := s.place_unit(P, sq(2), Vector2i(4, 4))
	var tie_e := s.place_unit(E, sq(2), Vector2i(7, 7))
	fast.move = 6
	slow.move = 2
	tie_p.move = 4
	tie_e.move = 4
	s._new_round()
	eq(s.order.slice(0, 2), [-1, -2], "both Sigils act first (player, enemy)")
	eq(s.order.slice(2), [fast.id, tie_p.id, tie_e.id, slow.id], "then by initiative; ties interleave player/enemy")
	s._begin_activation()
	s.wait(P)
	eq(s.actor_id, GameState.sigil_id(E), "Wait passes to the next actor")
	var newbie := s.place_unit(E, sq(3), Vector2i(8, 8))
	check(not s.order.has(newbie.id), "a monster summoned mid-round is not in this round's order")
	s.wait(E)
	eq(s.actor_id, fast.id, "fastest monster next")
	s.units.erase(tie_p)  # knocked out mid-round
	s.wait(P)
	eq(s.actor_id, tie_e.id, "a knocked-out actor is skipped")
	s.wait(E)
	s.wait(E)
	eq(s.round_num, 2, "round advances when everyone has acted")
	check(s.order.has(newbie.id), "next round includes the summoned monster")
	eq(s.order_preview(3), [-1, -2, fast.id], "turn-order preview for the HUD")


func test_movement() -> void:
	print("[movement]")
	var s := flat_state()
	var u := s.place_unit(P, sq(0), Vector2i(5, 5))
	u.move = 3
	s.activate(u.id)
	eq(s.reachable(u).size(), 24, "move 3 on open ground reaches 24 tiles (4-dir diamond)")
	check(not s.reachable(u).has(Vector2i(8, 6)), "4-direction: (8,6) is 4 steps away")
	for c in [Vector2i(6, 5), Vector2i(4, 5), Vector2i(5, 6), Vector2i(5, 4)]:
		s.grid[c.y][c.x] = "obstacle"
	eq(s.reachable(u).size(), 0, "boxed in by obstacles: no moves")
	eq(s.can_move(P, u.id, Vector2i(6, 5)), GameState.R_UNREACHABLE, "cannot move onto an obstacle")
	s.grid[5][6] = "ground"
	s.grid[4][6] = "obstacle"
	s.grid[6][6] = "obstacle"
	check(s.reachable(u).has(Vector2i(7, 5)), "gap in the wall lets the unit through")
	s.grid[5][6] = "obstacle"
	check(not s.reachable(u).has(Vector2i(7, 5)), "closed wall blocks the path")
	var s2 := flat_state()
	var w := s2.place_unit(P, sq(0), Vector2i(5, 5))
	w.move = 2
	s2.activate(w.id)
	s2.grid[5][6] = "elevation"
	eq(s2.reachable(w).get(Vector2i(6, 5), -1), 2, "climbing high ground costs 2")
	var blocker := s2.place_unit(E, sq(1), Vector2i(5, 6))
	check(not s2.reachable(w).has(blocker.pos), "cannot end on an occupied tile")
	eq(s2.can_move(P, w.id, Vector2i(10, 10)), GameState.R_UNREACHABLE, "cannot move onto a Symbol")
	eq(s2.move_unit(P, w.id, Vector2i(5, 4)), GameState.OK, "move")
	eq(s2.move_unit(P, w.id, Vector2i(5, 3)), GameState.R_ALREADY_MOVED, "one move per activation")


func test_commands() -> void:
	print("[commands: Move / Attack / Skill / Defend / Wait]")
	var s := flat_state()
	var a := s.place_unit(P, mon_of_family("Tech"), Vector2i(4, 4))
	var b := s.place_unit(P, mon_of_family("Tech"), Vector2i(0, 0))
	var d := s.place_unit(E, mon_of_family("Nature"), Vector2i(6, 4))
	a.attack_range = 3
	s.activate(a.id)
	eq(s.attack(P, b.id, d.pos), GameState.R_NOT_ACTIVE, "only the active monster can act")
	eq(s.move_unit(P, a.id, Vector2i(5, 4)), GameState.OK, "Move first")
	eq(s.actor_id, a.id, "moving does not end the activation")
	var hp0 := d.hp
	eq(s.attack(P, a.id, d.pos), GameState.OK, "then Attack")
	check(d.hp < hp0, "attack dealt damage")
	check(s.actor_id != a.id, "Attack ends the activation")
	var s2 := flat_state()
	var atk := s2.place_unit(E, mon_of_family("Tech"), Vector2i(4, 5))
	var dfn := s2.place_unit(P, mon_of_family("Tech"), Vector2i(4, 4))
	var full := GameState.compute_damage(atk.attack, dfn.defense, atk.family, dfn.family)
	var half := GameState.compute_damage(atk.attack, dfn.defense, atk.family, dfn.family, 0.5)
	s2.activate(dfn.id)
	eq(s2.defend(P, dfn.id), GameState.OK, "Defend")
	check(dfn.defending and s2.actor_id != dfn.id, "Defend sets the guard and ends the activation")
	eq(s2.damage_preview(atk, dfn.pos), half, "defending: damage x0.5 (%d -> %d)" % [full, half])
	s2.activate(dfn.id)
	check(not dfn.defending, "guard expires at its next activation")
	eq(s2.damage_preview(atk, dfn.pos), full, "full damage again")
	eq(s2.wait(P), GameState.OK, "Wait ends the activation")
	check(s2.actor_id != dfn.id, "Wait passed the turn")
	var acts := s2.legal_actions(s2.current)
	check(acts.any(func(x): return x.type == "wait"), "Wait is always a legal action")


func test_damage() -> void:
	print("[damage formula + element chart]")
	eq(GameState.compute_damage(30, 20, "Tech", "Nature"), 27, "neutral: round(1.5*30*30/50) = 27")
	eq(GameState.compute_damage(10, 40, "Tech", "Nature"), 3, "high defense still hurts: round(1.5*100/50) = 3")
	eq(GameState.compute_damage(1, 50, "Tech", "Nature"), 1, "floor of 1")
	eq(GameState.compute_damage(30, 20, "Water", "Fire"), 34, "ring Water>Fire: 27 x1.25 = 34")
	eq(GameState.compute_damage(30, 20, "Fire", "Water"), 22, "reverse Fire vs Water: 27 x0.8 = 22")
	eq(GameState.compute_damage(30, 20, "Light", "Dark"), 34, "Light beats Dark")
	eq(GameState.compute_damage(30, 20, "Dark", "Light"), 22, "Dark vs Light is the reverse (x0.8)")
	eq(GameState.compute_damage(30, 20, "Fire", "Earth"), 27, "opposite in a ring: neutral")
	eq(GameState.compute_damage(30, 20, "Fire", "Tech"), 27, "different rings: neutral")
	eq(GameState.compute_damage(30, 20, "Water", ""), 27, "Symbols have no element")
	var chart: Dictionary = Data.rules().element_chart
	var ins := {}
	var ok := true
	for f in chart:
		if f.begins_with("_"):
			continue
		if Array(chart[f]).size() != 1:
			ok = false
		for g in chart[f]:
			ins[g] = ins.get(g, 0) + 1
	for f in ins:
		if ins[f] != 1:
			ok = false
	check(ok and ins.size() == 12, "element chart: 3 rings of 4, each family beats 1 and is beaten by 1")


func test_accuracy_and_high_ground() -> void:
	print("[high ground: +30% damage, +15 accuracy, +1 range]")
	var s := flat_state()
	var a := s.place_unit(P, mon_of_family("Tech"), Vector2i(4, 4))
	var d := s.place_unit(E, mon_of_family("Tech"), Vector2i(5, 4))
	var flat := GameState.compute_damage(a.attack, d.defense, a.family, d.family)
	eq(s.hit_chance(a, d.pos), 90, "base accuracy 90")
	eq(s.damage_preview(a, d.pos), flat, "flat ground damage")
	s.grid[4][4] = "elevation"
	eq(s.hit_chance(a, d.pos), 100, "high ground: 90 + 15, capped at 100")
	eq(s.damage_preview(a, d.pos), GameState.compute_damage(a.attack, d.defense, a.family, d.family, 1.3), "high ground: x1.3 damage")
	eq(s.range_of(a, a.pos), a.attack_range + 1, "high ground: +1 range")
	d.veiled = true
	eq(s.hit_chance(a, d.pos), 75, "veiled target: -30 accuracy")
	s.activate(a.id)
	s.force_hit = 0
	var hp0 := d.hp
	s.attack(P, a.id, d.pos)
	eq(d.hp, hp0, "a missed attack deals no damage")


func test_line_of_sight() -> void:
	print("[line of sight]")
	var s := flat_state()
	var a := s.place_unit(P, mon_of_family("Tech"), Vector2i(2, 5))
	var d := s.place_unit(E, mon_of_family("Tech"), Vector2i(5, 5))
	a.attack_range = 4
	s.activate(a.id)
	eq(s.can_attack(P, a.id, d.pos), GameState.OK, "clear line: ranged attack allowed")
	s.grid[5][3] = "obstacle"
	eq(s.can_attack(P, a.id, d.pos), GameState.R_NO_LOS, "obstacle between blocks a ranged attack")
	check(not s.legal_attacks(a).has(d.pos), "legal_attacks respects line of sight")
	s.grid[5][3] = "ruins"
	eq(s.can_attack(P, a.id, d.pos), GameState.R_NO_LOS, "ruins/columns block line of sight too")
	s.grid[5][3] = "ground"
	var adj := s.place_unit(E, mon_of_family("Tech"), Vector2i(2, 6))
	s.grid[6][3] = "obstacle"
	eq(s.can_attack(P, a.id, adj.pos), GameState.OK, "adjacent attacks never need line of sight")
	var r := GameState.new()
	r.setup("T05-L03")
	var asym := 0
	for y in 12:
		for x in 12:
			for dy in range(-4, 5):
				for dx in range(-4, 5):
					var a2 := Vector2i(x, y)
					var b2 := Vector2i(x + dx, y + dy)
					if GameState.in_bounds(b2) and r.has_los(a2, b2) != r.has_los(b2, a2):
						asym += 1
	eq(asym, 0, "line of sight is symmetric on T05-L03 (all pairs within 4)")
	var g := flat_state()
	g.grid[4][5] = "obstacle"
	eq(g.has_los(Vector2i(4, 4), Vector2i(6, 6)), g.has_los(Vector2i(6, 6), Vector2i(4, 4)), "corner graze is symmetric")


func test_water_hazard() -> void:
	print("[water / hazard: -1 move, damage at activation start]")
	var s := flat_state()
	s.grid[5][5] = "water"
	var u := s.place_unit(P, mon_of_family("Fire"), Vector2i(5, 5))
	var hp0 := u.hp
	s.activate(u.id)
	eq(u.hp, hp0 - 5, "water: 5 damage at activation start")
	eq(s.move_of(u), u.move - 1, "water: movement -1")
	var s2 := flat_state()
	s2.hazard_tier = 2
	s2.grid[5][5] = "hazard"
	var h := s2.place_unit(P, mon_of_family("Fire"), Vector2i(5, 5))
	var h0 := h.hp
	s2.activate(h.id)
	eq(h.hp, h0 - 16, "hazard tier 2: 2 x 8 at activation start")
	eq(s2.move_of(h), h.move - 1, "hazard: movement -1")


func test_terrain_rule() -> void:
	print("[special rule: Terrain bonuses are doubled]")
	var off := flat_state()
	var on := flat_state("Terrain bonuses are doubled")
	eq(on.terrain_mult(), 2, "rule sets terrain multiplier 2")
	var results := []
	for s: GameState in [off, on]:
		s.grid[4][5] = "forest"
		var atk := s.place_unit(P, mon_of_family("Tech"), Vector2i(4, 4))
		var nat := s.place_unit(E, mon_of_family("Nature"), Vector2i(5, 4))
		atk.attack = 40
		nat.defense = 30
		var row := [s.defense_of(nat, nat.pos) - nat.defense, s.damage_preview(atk, nat.pos)]
		s.grid[4][4] = "elevation"
		row.append(s.damage_preview(atk, nat.pos))
		row.append(s.hit_chance(atk, nat.pos))
		results.append(row)
	eq(results[0][0], 4, "Nature on forest: +4 defense normally")
	eq(results[1][0], 8, "Nature on forest: +8 defense when doubled")
	eq(results[0][1], GameState.compute_damage(40, 34, "Tech", "Nature"), "normal: vs defense 34")
	eq(results[1][1], GameState.compute_damage(40, 38, "Tech", "Nature"), "doubled: vs defense 38")
	check(results[1][1] < results[0][1], "doubled terrain lowers the damage taken (%d -> %d)" % [results[0][1], results[1][1]])
	eq(results[0][2], GameState.compute_damage(40, 34, "Tech", "Nature", 1.3), "high ground normal: x1.3")
	eq(results[1][2], GameState.compute_damage(40, 38, "Tech", "Nature", 1.6), "high ground doubled: x1.6")
	eq(results[1][3], 100, "doubled accuracy bonus +30 (capped 100)")


func test_summon() -> void:
	print("[capsule summon via the Player Sigil]")
	var s := flat_state()
	var node := Vector2i(5, 5)
	s.grid[5][5] = "capsule_node"
	s.nodes = {node: GameState.NONE}
	var sq4: Array = Data.default_squad()
	s.reserve = [sq4.duplicate(), []]
	eq(s.can_deploy(P, sq4[0], node), GameState.R_BAD_DEPLOY_TILE, "cannot summon onto a node not yet activated")
	eq(s.deploy(P, sq4[0], Vector2i(2, 1)), GameState.OK, "summon onto a spawn tile")
	eq(s.deploy(P, sq4[1], Vector2i(3, 1)), GameState.OK, "second summon this activation")
	eq(s.deploy(P, sq4[2], Vector2i(4, 1)), GameState.R_NO_SUMMONS, "2 summons per Sigil activation")
	var first := s.unit_at(Vector2i(2, 1))
	check(not s.order.has(first.id), "summoned monster waits for next round")
	s.wait(P)
	eq(s.can_deploy(E, "MON-0001", Vector2i(9, 10)), GameState.R_NOT_IN_RESERVE, "enemy Sigil summons only its roster")
	var runner := s.place_unit(P, sq4[3], node)
	s.activate(runner.id)
	eq(s.nodes[node], P, "a monster starting its activation on a node activates it")
	s.move_unit(P, runner.id, Vector2i(5, 6))
	s.wait(P)
	s.activate(GameState.sigil_id(P))
	eq(s.deploy(P, sq4[2], node), GameState.OK, "summon onto the activated capsule node")
	var s2 := flat_state()
	var m := s2.place_unit(P, sq(0), Vector2i(6, 6))
	s2.activate(m.id)
	s2.reserve[P] = sq4.duplicate()
	eq(s2.can_deploy(P, sq4[0], Vector2i(2, 1)), GameState.R_NOT_SIGIL_TURN, "monsters cannot summon; only the Sigil")


func test_ap_rule() -> void:
	print("[special rule: Capsules cost 1 AP to deploy]")
	var sq4: Array = Data.default_squad()
	var off := flat_state()
	off.reserve[P] = sq4.duplicate()
	eq(off.deploy(P, sq4[0], Vector2i(2, 1)), GameState.OK, "no rule: 1st summon")
	eq(off.deploy(P, sq4[1], Vector2i(3, 1)), GameState.OK, "no rule: 2nd summon is free")
	var on := flat_state("Capsules cost 1 AP to deploy")
	on.ap[P] = 0
	on.activate(GameState.sigil_id(P))
	on.reserve[P] = sq4.duplicate()
	eq(on.ap[P], 1, "Sigil activation grants 1 AP")
	eq(on.deploy(P, sq4[0], Vector2i(2, 1)), GameState.OK, "rule: 1st summon spends the AP")
	eq(on.deploy(P, sq4[1], Vector2i(3, 1)), GameState.R_NO_AP, "rule: 2nd summon refused (1 per activation instead of 2)")


func test_ko_rule() -> void:
	print("[special rule: Movement after a knockout is +1]")
	var moves := []
	for text in ["", "Movement after a knockout is +1"]:
		var s := flat_state(text)
		var a := s.place_unit(P, sq(0), Vector2i(4, 4))
		var b := s.place_unit(P, sq(1), Vector2i(0, 6))
		var victim := s.place_unit(E, sq(2), Vector2i(5, 4))
		victim.hp = 1
		var before := s.move_of(b)
		s.activate(a.id)
		s.attack(P, a.id, victim.pos)
		var during := s.move_of(b)
		s.round_num += 1
		var next_round := s.move_of(b)
		s.round_num += 1
		moves.append([before, during, next_round, s.move_of(b), s.kos[E]])
	eq(moves[0][4], 1, "KO recorded")
	eq(moves[0][1], moves[0][0], "no rule: move unchanged after KO")
	eq([moves[1][1], moves[1][2], moves[1][3]], [moves[1][0] + 1, moves[1][0] + 1, moves[1][0]], "rule: +1 move this round and next, then gone")


func test_portal_rule() -> void:
	print("[special rule: One random portal activates each round]")
	var ends := []
	for text in ["", "One random portal activates each round"]:
		var s := flat_state(text)
		var gate := Vector2i(3, 8)
		s.grid[8][3] = "warp_gate"
		s.portals = [gate]
		s._roll_portal()
		var u := s.place_unit(P, sq(0), Vector2i(3, 6))
		u.move = 3
		s.activate(u.id)
		s.move_unit(P, u.id, gate)
		ends.append(u.pos)
	eq(ends[0], Vector2i(3, 8), "no rule: gate is dormant")
	eq(ends[1], Vector2i(8, 3), "rule: active gate warps to the mirrored tile (11-x, 11-y)")


## The user (a monster with `ability`) is active; a Tech-family dummy target stands next to it.
func _skill_state(ability: String, upos: Vector2i = Vector2i(4, 4), tpos: Vector2i = Vector2i(5, 4)) -> GameState:
	var s := flat_state()
	var u := s.place_unit(P, mon_with_ability(ability), upos)
	u.attack_range = maxi(u.attack_range, 2)
	var t := s.place_unit(E, mon_of_family("Tech"), tpos)
	s.activate(u.id)
	s.set_meta("u", u)
	s.set_meta("t", t)
	return s


func test_skills() -> void:
	print("[skills: one test per effect type]")
	var types := {}
	var unmapped := []
	for id in Data.monster_ids():
		var ab := str(Data.monster(id).ability)
		var sd := Data.ability(ab)
		if sd.is_empty():
			if not unmapped.has(ab):
				unmapped.append(ab)
		else:
			types[sd.type] = true
	eq(unmapped, [], "every ability on the 1,000 monsters maps to a skill effect")
	eq(types.size(), 11, "11 effect types in use (%s)" % ", ".join(types.keys()))
	var s := _skill_state("Storm Dash")
	var u: GameState.Unit = s.get_meta("u")
	var t: GameState.Unit = s.get_meta("t")
	var want := s.damage_preview(u, t.pos, 1.25)
	var hp0 := t.hp
	eq(s.skill(P, u.id, t.pos), GameState.OK, "strike: Storm Dash")
	eq(t.hp, hp0 - want, "strike deals x1.25")
	eq(s.skill(P, u.id, t.pos), GameState.R_NOT_ACTIVE, "skill ended the activation")
	s.activate(u.id)
	eq(s.can_skill(P, u.id, t.pos), GameState.R_COOLDOWN, "skill on cooldown next activation")
	s = _skill_state("Tidal Pull", Vector2i(4, 4), Vector2i(4, 6))
	t = s.get_meta("t")
	s.skill(P, s.get_meta("u").id, t.pos)
	eq(t.pos, Vector2i(4, 5), "pull drags the target 1 tile toward the user")
	s = _skill_state("Chain Spark")
	t = s.get_meta("t")
	var t2 := s.place_unit(E, mon_of_family("Tech"), t.pos + Vector2i(1, 1))
	var h2 := t2.hp
	s.skill(P, s.get_meta("u").id, t.pos)
	check(t2.hp < h2, "chain jumps to a second enemy within 2")
	s = _skill_state("Ember Mark")
	t = s.get_meta("t")
	s.skill(P, s.get_meta("u").id, t.pos)
	eq(t.marked, 1.5, "mark: next hit on the target x1.5")
	s = _skill_state("Gravity Well")
	t = s.get_meta("t")
	hp0 = t.hp
	s.skill(P, s.get_meta("u").id, t.pos)
	s.activate(t.id)
	check(t.hp == hp0 and s.move_of(t) == 0, "root: target cannot move on its next activation (no damage)")
	s = _skill_state("Moon Pulse")
	t = s.get_meta("t")
	var far := s.place_unit(E, mon_of_family("Tech"), Vector2i(9, 9))
	hp0 = t.hp
	var hf := far.hp
	s.skill(P, s.get_meta("u").id, s.get_meta("u").pos)
	check(t.hp < hp0 and far.hp == hf, "pulse hits enemies within 2 only")
	s = _skill_state("Verdant Renewal")
	u = s.get_meta("u")
	u.hp = 10
	s.grid[u.pos.y][u.pos.x] = "forest"
	s.skill(P, u.id, u.pos)
	eq(u.hp, 10 + u.max_hp * 20 / 100 * 2, "heal 20% max HP, doubled on Nature terrain")
	s = _skill_state("Prism Guard")
	u = s.get_meta("u")
	t = s.get_meta("t")
	s.skill(P, u.id, u.pos)
	check(u.defending and u.defend_mult == 0.5 and u.reflect == 25, "guard: x0.5 damage, reflect 25%")
	t.attack = u.defense + 40
	var th := t.hp
	s.activate(t.id)
	s.attack(E, t.id, u.pos)
	check(t.hp < th, "reflect hurts the attacker")
	s = _skill_state("Lumen Ward")
	u = s.get_meta("u")
	var ally := s.place_unit(P, mon_of_family("Tech"), u.pos + Vector2i(0, -1))
	eq(s.skill(P, u.id, ally.pos), GameState.OK, "ward targets an adjacent ally")
	check(ally.defending, "ward: the ally defends")
	s = _skill_state("Phase Step")
	u = s.get_meta("u")
	s.units.erase(s.get_meta("t"))
	s.grid[u.pos.y][u.pos.x + 1] = "obstacle"
	eq(s.skill(P, u.id, u.pos + Vector2i(2, 0)), GameState.OK, "blink 2 tiles straight over an obstacle")
	eq(u.pos, Vector2i(6, 4), "blinked")
	s = _skill_state("Astral Shift")
	u = s.get_meta("u")
	eq(s.can_skill(P, u.id, Vector2i(8, 8)), GameState.R_NO_TARGET, "Astral Shift only to special nodes")
	s.grid[8][8] = "capsule_node"
	eq(s.skill(P, u.id, Vector2i(8, 8)), GameState.OK, "Astral Shift to a capsule node")
	u.skill_cd = 0
	s.activate(u.id)
	u.skill_cd = 0
	eq(s.can_skill(P, u.id, Vector2i(8, 7) if s.tile_type(Vector2i(8, 7)) == "capsule_node" else Vector2i(8, 8)), GameState.R_COOLDOWN, "once per battle")
	s = _skill_state("Mist Veil")
	u = s.get_meta("u")
	t = s.get_meta("t")
	s.skill(P, u.id, u.pos)
	eq(s.hit_chance(t, u.pos), 60, "veil: enemies hit at 90 - 30")


func test_wins_and_objectives() -> void:
	print("[wins, loss, objectives]")
	var s := flat_state()
	var u := s.place_unit(P, sq(0), Vector2i(9, 10))
	s.symbol_hp[E] = 1
	s.activate(u.id)
	check(s.legal_attacks(u).has(Vector2i(10, 10)), "enemy Symbol is a legal target")
	s.attack(P, u.id, Vector2i(10, 10))
	eq([s.winner, s.win_reason], [P, "symbol"], "destroying the enemy Symbol wins")
	eq(s.wait(P), GameState.R_GAME_OVER, "no actions after the game ends")
	var s2 := flat_state()
	var e := s2.place_unit(E, sq(0), Vector2i(2, 1))
	s2.symbol_hp[P] = 1
	s2.activate(e.id)
	s2.attack(E, e.id, Vector2i(1, 1))
	eq(s2.winner, E, "losing the Player Sigil loses")
	var s3 := flat_state()
	var killer := s3.place_unit(P, sq(0), Vector2i(5, 5))
	var victim := s3.place_unit(E, sq(1), Vector2i(5, 6))
	victim.hp = 1
	s3.activate(killer.id)
	s3.attack(P, killer.id, victim.pos)
	eq(s3.winner, GameState.NONE, "wiping out every enemy monster is a bonus, not a win")
	var obj := s3.objectives()
	eq(obj[0].kind, "win", "objective 1 is the stage's win condition")
	eq(obj[1].text, "Protect the Player Sigil", "objective 2 protects the Sigil")
	check(obj[2].text == "Defeat all enemy monsters" and obj[2].done, "bonus: defeat all enemy monsters, done")
	var r := flat_state()
	r.relic_win = true
	var tiles := [Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3)]
	r.relics = {tiles[0]: P, tiles[1]: P, tiles[2]: GameState.NONE}
	var ru := r.place_unit(P, sq(0), tiles[2])
	r.activate(ru.id)
	r.wait(P)
	eq([r.winner, r.win_reason], [P, "relics"], "third relic secured -> win on a relic stage")
	var rn := flat_state()
	rn.relic_win = true
	rn.relics = {Vector2i(3, 3): GameState.NONE}
	rn.nodes = {Vector2i(6, 6): P, Vector2i(7, 7): P}
	rn.grid[3][3] = "relic"
	var rr := rn.place_unit(P, sq(0), Vector2i(3, 3))
	rn.activate(rr.id)
	rn.wait(P)
	eq([rn.winner, rn.win_reason], [P, "relics"], "1 relic + 2 activated capsule nodes = 3 relic nodes (map_policy)")
	var tr := GameState.new()
	tr.setup("T01-L03")
	check(tr.relic_win and tr.relics.size() + tr.nodes.size() >= 3, "T01-L03 relic win is now reachable (%d relic + %d nodes)" % [tr.relics.size(), tr.nodes.size()])
	var real := GameState.new()
	real.setup("T01-L01")
	var texts := real.objectives().map(func(o): return o.text)
	check(texts.has("Activate capsule nodes") and texts.has("Obtain the golden relic"), "T01-L01 lists capsule-node and golden-relic objectives")
	eq(real.objectives()[3].progress, "0/2", "capsule nodes start 0/2")


func test_dormant() -> void:
	print("[dormant statues]")
	var s := GameState.new()
	s.setup("T01-L01")
	check(s.dormant_stage, "T01-L01 is ruins-themed (design example)")
	var statues := s.units_of(E).filter(func(x): return x.dormant)
	eq(statues.size(), 3, "3 enemy statues on the board at start")
	check(statues.all(func(x): return s.order.has(x.id)), "statues are in round 1's turn order")
	var st: GameState.Unit = statues[0]
	s.activate(st.id)
	check(not st.dormant, "a statue awakens at its first activation")
	var t8 := GameState.new()
	t8.setup("T08-L01")
	check(t8.dormant_stage and t8.units_of(E).size() > 0, "Ancient-terrain tower 08 starts with statues")
	var plain := GameState.new()
	plain.setup("T01-L02")
	eq(plain.units.size(), 0, "other stages start with an empty board")


func _invariants(s: GameState) -> String:
	var seen := {}
	for u in s.units:
		if not s.is_walkable(u.pos):
			return "unit %s on unwalkable %s" % [u.name, u.pos]
		if seen.has(u.pos):
			return "two units on %s" % u.pos
		seen[u.pos] = true
		if u.hp <= 0:
			return "dead unit on board"
	return ""


func test_ai_legal() -> void:
	print("[AI legal actions]")
	var s := GameState.new()
	s.setup("T01-L02")
	s.wait(P)
	eq(s.actor_id, GameState.sigil_id(E), "enemy Sigil acts second")
	var st := AI.take_activation(s, E, s.stage.opponent_style)
	eq(st.rejected, 0, "AI made no illegal calls")
	check(s.units_of(E).size() > 0, "AI Sigil summoned monsters (%d)" % s.units_of(E).size())
	check(s.actor_id != GameState.sigil_id(E), "AI ended its activation")
	var styles := {}
	for st2 in Data.stages():
		styles[st2.opponent_style] = true
	var missing := []
	for k in styles:
		if not AI.STYLES.has(k):
			missing.append(k)
	eq(missing, [], "every opponent_style has an AI profile (%d styles)" % styles.size())
	var i := 0
	for style in styles:
		var g := GameState.new()
		g.setup(Data.stages()[i].stage_id)
		i += 11
		var rej := 0
		var bad := ""
		while g.winner == GameState.NONE and g.round_num <= 12:
			var r := AI.take_activation(g, g.current, "balanced" if g.current == P else style)
			rej += r.rejected
			if bad == "":
				bad = _invariants(g)
		eq([rej, bad], [0, ""], "style '%s': legal and consistent for 12 rounds" % style)
	var h := GameState.new()
	h.setup("T02-L04")
	var all_ok := true
	for a in h.legal_actions(P):
		if a.type == "deploy" and h.can_deploy(P, a.mon, a.tile) != GameState.OK:
			all_ok = false
	check(all_ok and h.legal_actions(P).size() > 1, "every listed legal summon passes can_deploy")
	eq(h.legal_actions(E).size(), 0, "no legal actions for the side not active")


func test_progress() -> void:
	print("[progression + squad save]")
	var path := "user://test_progress.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var pr := Progress.new(path)
	check(pr.is_unlocked("T01-L01"), "first stage unlocked")
	check(not pr.is_unlocked("T01-L02"), "second stage locked")
	eq(pr.squad, Data.default_squad(), "default squad of 4")
	var coll := Data.squad_collection()
	check(not pr.set_squad(coll.slice(0, 3)), "a squad of 3 is refused")
	check(not pr.set_squad([coll[0], coll[0], coll[1], coll[2]]), "duplicates refused")
	var pick := [coll[4], coll[3], coll[2], coll[1]]
	check(pr.set_squad(pick), "a squad of 4 from the collection is accepted")
	eq(pr.record_win("T01-L01"), "T01-L02", "winning returns the next stage")
	var again := Progress.new(path)
	check(again.is_unlocked("T01-L02") and not again.is_unlocked("T01-L03"), "progress persists")
	eq(again.squad, pick, "squad persists")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"unlocked\": 3, \"cleared\": {}}")
	f.close()
	var old := Progress.new(path)
	check(old.unlocked == 3 and old.squad == Data.default_squad(), "a pre-squad save loads with the default squad")
	eq(Progress.next_stage_id("T01-L10"), "T02-L01", "tower 1 stage 10 leads to tower 2 stage 1")
	eq(Progress.next_stage_id("T12-L10"), "", "last stage has no next")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
