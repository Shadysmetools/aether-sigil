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
		test_movement()
		test_damage()
		test_terrain_rule()
		test_capsule_deploy()
		test_ap_rule()
		test_ko_rule()
		test_portal_rule()
		test_symbol_win()
		test_relic_win()
		test_hazard_and_recharge()
		test_ai_legal()
		test_progress()
	print("%d pass / %d fail" % [passed, failed])
	quit(failed)


## First stage whose special_rule is `text` (or any stage when text is "").
func stage_with_rule(text: String) -> String:
	for s in Data.stages():
		if text == "" or s.special_rule == text:
			return s.stage_id
	return ""


func stage_without_rules() -> String:
	# A stage whose rule is none of the four (none exist), so tests clear `rule` instead.
	return Data.stages()[0].stage_id


## A battle on an all-ground board with Symbols at (1,1) and (10,10), no rule, empty reserves.
func flat_state(rule_text: String = "") -> GameState:
	var s := GameState.new()
	s.setup(stage_with_rule(rule_text) if rule_text != "" else stage_without_rules())
	for y in GameState.SIZE:
		for x in GameState.SIZE:
			s.grid[y][x] = "ground"
	s.symbol_pos = [Vector2i(1, 1), Vector2i(10, 10)]
	s.grid[1][1] = "player_symbol"
	s.grid[10][10] = "enemy_symbol"
	s.nodes = {}
	s.relics = {}
	s.portals = []
	s.spawn_tiles = [[Vector2i(2, 1)], [Vector2i(9, 10)]]
	s._field_cache = {}
	s.reserve = [[], []]
	if rule_text == "":
		s.rule = {}
	s.relic_win = false
	return s


## Some monster ids by family, for element tests.
func mon_of_family(fam: String) -> String:
	for id in Data.monster_ids():
		if Data.monster(id).element_family == fam:
			return id
	return ""


func test_board() -> void:
	print("[board]")
	var s := GameState.new()
	check(s.setup("T01-L01"), "T01-L01 sets up")
	eq(s.grid.size(), 12, "12 rows")
	eq(s.grid[0].size(), 12, "12 columns")
	eq(s.symbol_pos[P], Vector2i(1, 1), "player Symbol from objectives")
	eq(s.symbol_pos[E], Vector2i(10, 10), "enemy Symbol from objectives")
	eq(s.nodes.size(), 2, "two capsule nodes")
	check(not s.spawn_tiles[P].has(s.symbol_pos[P]), "Symbol tile is not a deploy tile")
	check(not s.spawn_tiles[P].is_empty() and not s.spawn_tiles[E].is_empty(), "both sides have deploy tiles")
	eq(s.reserve[P], Data.starter_team(), "player reserve = starter team")
	eq(s.reserve[P].size(), 5, "starter team has 5 monsters")
	eq(s.reserve[E].size(), s.stage.enemy_roster.size(), "enemy reserve = stage roster")
	# T01-L10 paints a hazard over its player_symbol objective; objectives win.
	var s2 := GameState.new()
	s2.setup("T01-L10")
	eq(s2.tile_type(Vector2i(1, 1)), "player_symbol", "objective overrides painted hazard at T01-L10 (1,1)")


func test_movement() -> void:
	print("[movement]")
	var s := flat_state()
	var u := s.place_unit(P, Data.starter_team()[0], Vector2i(5, 5))
	u.move = 3
	eq(s.reachable(u).size(), 24, "move 3 on open ground reaches 24 tiles (4-dir diamond)")
	check(not s.reachable(u).has(Vector2i(8, 6)), "4-direction: (8,6) is 4 steps away, out of reach")
	for c in [Vector2i(6, 5), Vector2i(4, 5), Vector2i(5, 6), Vector2i(5, 4)]:
		s.grid[c.y][c.x] = "obstacle"
	eq(s.reachable(u).size(), 0, "boxed in by obstacles: no moves")
	eq(s.can_move(P, u.id, Vector2i(6, 5)), GameState.R_UNREACHABLE, "cannot move onto an obstacle")
	s.grid[5][6] = "ground"
	s.grid[4][6] = "obstacle"
	s.grid[6][6] = "obstacle"
	# Wall at x=6 rows 4..6 except (6,5) open: going round the wall costs more.
	check(s.reachable(u).has(Vector2i(7, 5)), "gap in the wall lets the unit through")
	s.grid[5][6] = "obstacle"
	check(not s.reachable(u).has(Vector2i(7, 5)), "closed wall blocks the path")
	var s2 := flat_state()
	var w := s2.place_unit(P, Data.starter_team()[0], Vector2i(5, 5))
	w.move = 2
	s2.grid[5][6] = "elevation"
	eq(s2.reachable(w).get(Vector2i(6, 5), -1), 2, "climbing elevation costs 2")
	check(not s2.reachable(w).has(Vector2i(7, 5)), "cannot continue past elevation with move 2")
	var blocker := s2.place_unit(E, Data.starter_team()[1], Vector2i(5, 6))
	check(not s2.reachable(w).has(blocker.pos), "cannot end on an occupied tile")
	eq(s2.can_move(P, w.id, Vector2i(10, 10)), GameState.R_UNREACHABLE, "cannot move onto a Symbol")


func test_damage() -> void:
	print("[damage]")
	eq(GameState.compute_damage(30, 20, "Tech", "Nature"), 10, "neutral: max(1, 30-20) = 10")
	eq(GameState.compute_damage(10, 40, "Tech", "Nature"), 1, "floor of 1 when defense >= attack")
	eq(GameState.compute_damage(30, 20, "Water", "Fire"), 15, "advantage Water>Fire: 10 x1.5 = 15")
	eq(GameState.compute_damage(30, 20, "Fire", "Water"), 7, "disadvantage Fire vs Water: 10 x0.75 = 7")
	eq(GameState.compute_damage(30, 20, "Light", "Dark"), 15, "Light beats Dark")
	eq(GameState.compute_damage(30, 20, "Dark", "Light"), 15, "Dark beats Light (mutual)")
	eq(GameState.compute_damage(30, 20, "Water", ""), 10, "Symbols have no element")
	# Chart is balanced: every family beats 2 and is beaten by 2.
	var chart: Dictionary = Data.rules().element_chart
	var ins := {}
	var ok := true
	for f in chart:
		if f.begins_with("_"):
			continue
		if Array(chart[f]).size() != 2:
			ok = false
		for g in chart[f]:
			ins[g] = ins.get(g, 0) + 1
	for f in ins:
		if ins[f] != 2:
			ok = false
	check(ok and ins.size() == 12, "element chart: 12 families, each beats 2 and is beaten by 2")
	var fams := {}
	for id in Data.monster_ids():
		fams[Data.monster(id).element_family] = true
	var missing := []
	for f in fams:
		if not chart.has(f):
			missing.append(f)
	eq(missing, [], "every monster family is in the chart")
	# On-board: attacker uses its terrain-adjusted stats.
	var s := flat_state()
	var a := s.place_unit(P, mon_of_family("Water"), Vector2i(4, 4))
	var d := s.place_unit(E, mon_of_family("Fire"), Vector2i(5, 4))
	var want := GameState.compute_damage(a.attack, d.defense, "Water", "Fire")
	eq(s.damage_preview(a, d.pos), want, "board damage matches the formula")
	var hp0 := d.hp
	eq(s.attack(P, a.id, d.pos), GameState.OK, "attack in range")
	eq(d.hp, hp0 - want, "target lost the previewed HP")
	eq(s.attack(P, a.id, d.pos), GameState.R_ALREADY_ATTACKED, "one attack per turn")


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
		atk.attack = nat.defense + 10  # neutral matchup (Tech vs Nature), 10 over base defense
		results.append([s.defense_of(nat, nat.pos) - nat.defense, s.damage_preview(atk, nat.pos)])
	eq(results[0][0], 4, "Nature monster on forest: +4 defense normally")
	eq(results[1][0], 8, "Nature monster on forest: +8 defense when doubled")
	eq(results[0][1], 6, "normal terrain: 10 - 4 = 6 damage")
	eq(results[1][1], 2, "doubled terrain: 10 - 8 = 2 damage (rule flips the outcome)")
	var s2 := flat_state()
	s2.grid[3][3] = "elevation"
	var hi := s2.place_unit(P, mon_of_family("Tech"), Vector2i(3, 3))
	eq(s2.range_of(hi, hi.pos), hi.attack_range + 1, "elevation gives +1 range")
	eq(s2.attack_of(hi, hi.pos), hi.attack + 3, "elevation gives +3 attack")


func test_capsule_deploy() -> void:
	print("[capsule node deploy]")
	var s := flat_state()
	var node := Vector2i(5, 5)
	s.grid[5][5] = "capsule_node"
	s.nodes = {node: GameState.NONE}
	var team := Data.starter_team()
	s.reserve = [team.duplicate(), [team[0]]]
	eq(s.can_deploy(P, team[0], node), GameState.R_BAD_DEPLOY_TILE, "cannot deploy on an uncaptured node")
	eq(s.can_deploy(P, team[0], Vector2i(7, 7)), GameState.R_BAD_DEPLOY_TILE, "cannot deploy on a random tile")
	eq(s.deploy(P, team[0], Vector2i(2, 1)), GameState.OK, "deploy on own spawn tile")
	var first := s.unit_at(Vector2i(2, 1))
	check(first != null and first.moved and first.attacked, "deployed monster waits a turn")
	eq(s.can_deploy(P, "MON-9999", Vector2i(2, 1)), GameState.R_NOT_IN_RESERVE, "only reserve monsters deploy")
	var runner := s.place_unit(P, team[4], node)
	eq(s.end_turn(P), GameState.OK, "end turn on the node")
	eq(s.nodes[node], P, "node captured by ending the turn on it")
	s.end_turn(E)
	s.move_unit(P, runner.id, Vector2i(5, 6))
	eq(s.deploy(P, team[1], node), GameState.OK, "deploy onto the captured capsule node")
	eq(s.unit_at(node).mon_id, team[1], "monster stands on the node")


func test_ap_rule() -> void:
	print("[special rule: Capsules cost 1 AP to deploy]")
	var team := Data.starter_team()
	var off := flat_state()
	off.spawn_tiles[P] = [Vector2i(2, 1), Vector2i(3, 1)]
	off.reserve[P] = team.duplicate()
	eq(off.deploy(P, team[0], Vector2i(2, 1)), GameState.OK, "no rule: 1st deploy")
	eq(off.deploy(P, team[1], Vector2i(3, 1)), GameState.OK, "no rule: 2nd deploy is free")
	var on := flat_state("Capsules cost 1 AP to deploy")
	on.spawn_tiles[P] = [Vector2i(2, 1), Vector2i(3, 1)]
	on.reserve[P] = team.duplicate()
	eq(on.deploy_cost(), 1, "rule: deploy costs 1 AP")
	eq(on.deploy(P, team[0], Vector2i(2, 1)), GameState.OK, "rule: 1st deploy spends the AP")
	eq(on.deploy(P, team[1], Vector2i(3, 1)), GameState.R_NO_AP, "rule: 2nd deploy refused, no AP")
	eq(on.legal_deploys(P).size(), 0, "rule: no legal deploys without AP")
	on.end_turn(P)
	on.end_turn(E)
	eq(on.ap[P], 1, "AP refills by 1 next turn")


func test_ko_rule() -> void:
	print("[special rule: Movement after a knockout is +1]")
	var moves := []
	for text in ["", "Movement after a knockout is +1"]:
		var s := flat_state(text)
		var a := s.place_unit(P, Data.starter_team()[0], Vector2i(4, 4))
		var b := s.place_unit(P, Data.starter_team()[1], Vector2i(0, 6))
		var victim := s.place_unit(E, Data.starter_team()[2], Vector2i(5, 4))
		s.place_unit(E, Data.starter_team()[3], Vector2i(11, 0))  # so the KO doesn't end the game
		victim.hp = 1
		var before := s.move_of(b)
		s.attack(P, a.id, victim.pos)
		moves.append([before, s.move_of(b), s.kos[E]])
	eq(moves[0][2], 1, "KO recorded")
	eq(moves[0][1], moves[0][0], "no rule: move unchanged after KO")
	eq(moves[1][1], moves[1][0] + 1, "rule: allies get +1 move after a KO")


func test_portal_rule() -> void:
	print("[special rule: One random portal activates each round]")
	var ends := []
	for text in ["", "One random portal activates each round"]:
		var s := flat_state(text)
		var gate := Vector2i(3, 8)
		s.grid[8][3] = "warp_gate"
		s.portals = [gate]
		s._roll_portal()
		var u := s.place_unit(P, Data.starter_team()[0], Vector2i(3, 6))
		u.move = 3
		s.move_unit(P, u.id, gate)
		ends.append(u.pos)
	eq(ends[0], Vector2i(3, 8), "no rule: gate is dormant")
	eq(ends[1], Vector2i(8, 3), "rule: active gate warps to the mirrored tile (11-x, 11-y)")


func test_symbol_win() -> void:
	print("[win: defeat the enemy Symbol]")
	var s := flat_state()
	var u := s.place_unit(P, Data.starter_team()[0], Vector2i(9, 10))
	s.place_unit(E, Data.starter_team()[1], Vector2i(0, 11))
	s.symbol_hp[E] = 1
	eq(s.legal_attacks(u).has(Vector2i(10, 10)), true, "enemy Symbol is a legal target")
	eq(s.attack(P, u.id, Vector2i(10, 10)), GameState.OK, "hit the Symbol")
	eq(s.symbol_hp[E], 0, "Symbol HP reaches 0")
	eq(s.winner, P, "player wins")
	eq(s.win_reason, "symbol", "by Symbol")
	eq(s.end_turn(P), GameState.R_GAME_OVER, "no actions after the game ends")
	var s2 := flat_state()
	var v := s2.place_unit(P, Data.starter_team()[0], Vector2i(2, 1))
	eq(s2.can_attack(P, v.id, Vector2i(1, 1)), GameState.R_NO_TARGET, "cannot attack your own Symbol")


func test_relic_win() -> void:
	print("[win: secure 3 relic nodes]")
	var s := flat_state()
	s.relic_win = true
	var r := [Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3)]
	for c in r:
		s.grid[c.y][c.x] = "relic"
	s.relics = {r[0]: P, r[1]: P, r[2]: GameState.NONE}
	s.place_unit(P, Data.starter_team()[0], r[2])
	s.place_unit(E, Data.starter_team()[1], Vector2i(0, 11))
	s.end_turn(P)
	eq(s.winner, P, "third relic secured -> win")
	eq(s.win_reason, "relics", "by relics")
	var s2 := flat_state()
	s2.relic_win = false
	s2.relics = {r[0]: P, r[1]: P, r[2]: GameState.NONE}
	s2.place_unit(P, Data.starter_team()[0], r[2])
	s2.end_turn(P)
	eq(s2.winner, GameState.NONE, "relics don't win on a Symbol-only stage")


func test_hazard_and_recharge() -> void:
	print("[hazard + recharge]")
	var s := flat_state()
	s.hazard_tier = 2
	s.grid[5][5] = "hazard"
	var u := s.place_unit(P, Data.starter_team()[0], Vector2i(5, 5))
	s.place_unit(E, Data.starter_team()[1], Vector2i(0, 11))
	var hp0 := u.hp
	s.end_turn(P)
	eq(u.hp, hp0 - 16, "hazard tier 2 deals 2 x 8 at end of turn")
	var s2 := flat_state()
	var node := Vector2i(6, 6)
	s2.grid[6][6] = "capsule_node"
	s2.nodes = {node: P}
	var w := s2.place_unit(P, Data.starter_team()[0], node)
	s2.place_unit(E, Data.starter_team()[1], Vector2i(0, 11))
	w.hp = 10
	s2.end_turn(P)
	s2.end_turn(E)
	eq(w.hp, 10 + w.max_hp * 20 / 100, "owned node recharges 20% max HP at turn start")


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
	s.setup("T01-L01")
	s.end_turn(P)
	var st := AI.take_turn(s, E, s.stage.opponent_style)
	eq(st.rejected, 0, "AI made no illegal calls")
	check(s.units_of(E).size() > 0, "AI deployed monsters (%d)" % s.units_of(E).size())
	eq(s.current, P, "AI ended its turn")
	eq(AI.take_turn(s, E).actions, 0, "AI does nothing when it is not its turn")
	var styles := {}
	for st2 in Data.stages():
		styles[st2.opponent_style] = true
	var missing := []
	for k in styles:
		if not AI.STYLES.has(k):
			missing.append(k)
	eq(missing, [], "every opponent_style in the data has an AI profile (%d styles)" % styles.size())
	# Each style, 12 rounds against the balanced player AI: zero illegal actions, invariants hold.
	var i := 0
	for style in styles:
		var g := GameState.new()
		g.setup(Data.stages()[i].stage_id)
		i += 11
		var rej := 0
		var bad := ""
		while g.winner == GameState.NONE and g.round_num <= 12:
			var r := AI.take_turn(g, g.current, "balanced" if g.current == P else style)
			rej += r.rejected
			if bad == "":
				bad = _invariants(g)
		eq([rej, bad], [0, ""], "style '%s': legal and consistent for 12 rounds" % style)
	# Legal-action API agrees with can_* checks.
	var h := GameState.new()
	h.setup("T02-L04")
	var all_ok := true
	for a in h.legal_actions(P):
		if a.type == "deploy" and h.can_deploy(P, a.mon, a.tile) != GameState.OK:
			all_ok = false
	check(all_ok and h.legal_actions(P).size() > 1, "every listed legal deploy passes can_deploy")
	eq(h.legal_actions(E).size(), 0, "no legal actions for the side not on turn")


func test_progress() -> void:
	print("[progression save]")
	var path := "user://test_progress.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var pr := Progress.new(path)
	check(pr.is_unlocked("T01-L01"), "first stage unlocked")
	check(not pr.is_unlocked("T01-L02"), "second stage locked")
	eq(pr.record_win("T01-L01"), "T01-L02", "winning returns the next stage")
	check(pr.is_unlocked("T01-L02"), "win unlocks the next stage")
	var again := Progress.new(path)
	check(again.is_unlocked("T01-L02") and not again.is_unlocked("T01-L03"), "progress persists to %s" % path)
	eq(Progress.next_stage_id("T01-L10"), "T02-L01", "tower 1 stage 10 leads to tower 2 stage 1")
	eq(Progress.next_stage_id("T12-L10"), "", "last stage has no next")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
