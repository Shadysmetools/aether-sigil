## Headless rules tests. Run:
##   Godot_console.exe --headless --path <game dir> --script res://tests/test_rules.gd
## Exits with the number of failures (0 = green).
extends SceneTree

const HexGrid = preload("res://scripts/hex_grid.gd")
const Wicks = preload("res://scripts/wicks.gd")
const GameState = preload("res://scripts/game_state.gd")
const AI = preload("res://scripts/ai.gd")

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
	print("Emberwick rules tests")
	test_board()
	test_light_from_post()
	test_summon_refusals()
	test_damage_formula()
	test_combat_on_board()
	test_hearth_win()
	test_beacon_win()
	test_ai_single_turn()
	test_ai_vs_ai()
	print("%d pass / %d fail" % [passed, failed])
	quit(failed)


func test_board() -> void:
	print("[board]")
	eq(HexGrid.all_tiles(3).size(), 37, "radius-3 board has 37 tiles")
	eq(HexGrid.distance(Vector2i(0, 3), Vector2i(0, -3)), 6, "hearths are 6 apart")
	var px := HexGrid.to_pixel(Vector2i(2, -1), 80.0)
	eq(HexGrid.from_pixel(px, 80.0), Vector2i(2, -1), "pixel<->hex round trip")


func test_light_from_post() -> void:
	print("[light]")
	var s := GameState.new()
	var target := Vector2i(0, 1)
	eq(s.light_owner(Vector2i(0, 2)), GameState.HUMAN, "tile next to Hearth starts lit for player")
	eq(s.light_owner(target), GameState.NONE, "(0,1) starts dark")
	var before := s.owned_tile_count(GameState.HUMAN)
	eq(s.plant_post(GameState.HUMAN, Vector2i(0, 2)), GameState.OK, "plant Post at (0,2) with 2 Oil")
	eq(s.oil[GameState.HUMAN], 0, "Post cost 2 Oil")
	eq(s.light_owner(target), GameState.HUMAN, "Post spreads light to (0,1)")
	check(s.owned_tile_count(GameState.HUMAN) > before, "owned tile count grew (%d -> %d)" % [before, s.owned_tile_count(GameState.HUMAN)])
	eq(s.plant_post(GameState.HUMAN, Vector2i(0, 1)), GameState.R_NO_OIL, "second Post refused without Oil")
	s.oil[GameState.HUMAN] = 5
	eq(s.plant_post(GameState.HUMAN, Vector2i(3, -3)), GameState.R_NOT_YOUR_LIGHT, "Post refused on a dark tile")


func test_summon_refusals() -> void:
	print("[summon]")
	var s := GameState.new()
	var H := GameState.HUMAN
	s.oil[H] = 10
	# Positive control: own lit tile next to the Hearth.
	eq(s.can_summon(H, "pip", Vector2i(0, 2)), GameState.OK, "summon allowed on own lit tile next to Hearth")
	# Rival tile that IS adjacent to my Hearth (rival Pip kindled it) -> must fail on light, not adjacency.
	var rival_tile := Vector2i(1, 2)
	eq(HexGrid.distance(rival_tile, GameState.HEARTH_TILES[H]), 1, "fixture: (1,2) is adjacent to my Hearth")
	s.kindled[rival_tile] = GameState.RIVAL
	eq(s.light_owner(rival_tile), GameState.RIVAL, "fixture: (1,2) is rival light")
	eq(s.can_summon(H, "pip", rival_tile), GameState.R_NOT_YOUR_LIGHT, "summon refused on rival tile")
	# Dark (contested) tile that IS adjacent to my Post.
	s.posts[Vector2i(0, 1)] = H
	s.posts[Vector2i(0, -1)] = GameState.RIVAL
	var dark_tile := Vector2i(0, 0)
	eq(s.light_owner(dark_tile), GameState.NONE, "fixture: (0,0) contested -> dark")
	eq(HexGrid.distance(dark_tile, Vector2i(0, 1)), 1, "fixture: (0,0) adjacent to my Post")
	eq(s.can_summon(H, "pip", dark_tile), GameState.R_NOT_YOUR_LIGHT, "summon refused on dark tile")
	check(s.can_summon(H, "pip", Vector2i(3, -3)) != GameState.OK, "summon refused on far dark tile")
	# Actually summoning spends Oil, empties the satchel slot, applies summoning sickness.
	eq(s.summon(H, "brazier", Vector2i(0, 2)), GameState.OK, "summon Brazier")
	eq(s.oil[H], 7, "Brazier cost 3 Oil")
	check(not ("brazier" in s.satchels[H]), "Brazier left the satchel")
	eq(s.can_summon(H, "brazier", Vector2i(-1, 3)), GameState.R_NOT_IN_SATCHEL, "can't summon same Wick twice")
	eq(s.can_summon(H, "pip", Vector2i(0, 2)), GameState.R_OCCUPIED, "can't summon onto occupied tile")
	eq(s.can_summon(GameState.RIVAL, "pip", Vector2i(0, -2)), GameState.R_NOT_YOUR_TURN, "rival can't summon on my turn")


func test_damage_formula() -> void:
	print("[damage]")
	var dmg := GameState.compute_damage
	eq(dmg.call(3, 1, "Ember", "Tide", false), 2, "3 Power vs 1 Guard = 2")
	eq(dmg.call(1, 4, "Tide", "Ember", false), 1, "minimum damage is 1")
	eq(dmg.call(4, 1, "Ember", "Tide", true), 2, "dark tile -1 Power: (4-1)-1 = 2")
	eq(dmg.call(6, 2, "Ember", "Bloom", false), 6, "advantage x1.5: 4 -> 6")
	eq(dmg.call(3, 1, "Ember", "Bloom", false), 3, "advantage floors: 2 -> 3")
	eq(dmg.call(5, 2, "Tide", "Stone", false), 4, "advantage floors: 3 -> 4")
	eq(dmg.call(1, 9, "Tide", "Stone", false), 1, "advantage on minimum: 1 -> 1")
	eq(dmg.call(6, 2, "Bloom", "Ember", false), 4, "no bonus the other way round")
	eq(dmg.call(6, 2, "Gale", "Ember", false), 6, "cycle wraps: Gale beats Ember")
	eq(dmg.call(6, 2, "Ember", "Tide", false), 4, "Ember vs Tide is neutral")


func test_combat_on_board() -> void:
	print("[combat]")
	var s := GameState.new()
	var me := s.place_unit(GameState.HUMAN, "riptide", Vector2i(0, 2))  # lit tile
	var foe := s.place_unit(GameState.RIVAL, "pip", Vector2i(0, 1))
	eq(s.attack(GameState.HUMAN, me.id, foe.pos), GameState.OK, "attack adjacent enemy")
	eq(foe.hp, 6 - 4, "Riptide 5 vs Pip Guard 1 -> 4 damage")
	eq(s.attack(GameState.HUMAN, me.id, foe.pos), GameState.R_ALREADY_ATTACKED, "only one attack per turn")
	eq(s.move_unit(GameState.HUMAN, me.id, Vector2i(1, 1)), GameState.R_ALREADY_MOVED, "attacking ends movement")
	var dark := s.place_unit(GameState.HUMAN, "brazier", Vector2i(2, -2))
	var foe2 := s.place_unit(GameState.RIVAL, "harborcrab", Vector2i(2, -3))
	eq(s.light_owner(dark.pos), GameState.NONE, "fixture: (2,-2) is dark")
	s.attack(GameState.HUMAN, dark.id, foe2.pos)
	eq(foe2.hp, 11 - 1, "dark Brazier (4-1) vs Guard 4 -> min 1")
	var cw := s.place_unit(GameState.HUMAN, "cinderwing", Vector2i(-1, 3))
	eq(s.can_attack(GameState.HUMAN, cw.id, Vector2i(-1, 1)), GameState.R_NO_TARGET, "no target on empty tile")
	var far := s.place_unit(GameState.RIVAL, "dropkin", Vector2i(-1, 1))
	eq(s.can_attack(GameState.HUMAN, cw.id, far.pos), GameState.OK, "Cinderwing hits at range 2")
	eq(s.can_attack(GameState.HUMAN, cw.id, Vector2i(-2, 1)), GameState.R_NO_TARGET, "can not attack an empty Beacon")
	var pip := s.place_unit(GameState.HUMAN, "pip", Vector2i(1, 2))
	eq(s.move_unit(GameState.HUMAN, pip.id, Vector2i(2, 0)), GameState.OK, "Pip moves 2")
	eq(s.light_owner(Vector2i(2, 0)), GameState.HUMAN, "Kindle: Pip's tile becomes player light")
	eq(s.move_unit(GameState.HUMAN, pip.id, Vector2i(2, -1)), GameState.R_ALREADY_MOVED, "only one move per turn")


func test_hearth_win() -> void:
	print("[hearth win]")
	var s := GameState.new()
	var u := s.place_unit(GameState.HUMAN, "cinderwing", Vector2i(0, -2))
	s.hearth_hp[GameState.RIVAL] = 3
	eq(s.attack(GameState.HUMAN, u.id, GameState.HEARTH_TILES[GameState.RIVAL]), GameState.OK, "attack rival Hearth")
	eq(s.hearth_hp[GameState.RIVAL], 0, "Hearth HP floors at 0")
	eq(s.winner, GameState.HUMAN, "Hearth at 0 -> player wins")
	eq(s.win_reason, "hearth", "win reason = hearth")
	eq(s.end_turn(GameState.HUMAN), GameState.R_GAME_OVER, "no actions after game over")


func test_beacon_win() -> void:
	print("[beacon win]")
	var s := GameState.new()
	s.place_unit(GameState.HUMAN, "pip", GameState.BEACON_TILES[0])
	s.place_unit(GameState.HUMAN, "dropkin", GameState.BEACON_TILES[1])
	eq(s.end_turn(GameState.HUMAN), GameState.OK, "end turn on 2 beacons")
	eq(s.beacons_owned(GameState.HUMAN), 2, "2 beacons claimed at end of turn")
	s.end_turn(GameState.RIVAL)
	eq(s.winner, GameState.NONE, "2 beacons is not a win")
	s.place_unit(GameState.HUMAN, "riptide", GameState.BEACON_TILES[2])
	s.end_turn(GameState.HUMAN)
	eq(s.beacons_owned(GameState.HUMAN), 3, "3 beacons claimed")
	eq(s.winner, GameState.NONE, "no win until the start of your NEXT turn")
	s.end_turn(GameState.RIVAL)  # rival passes without retaking any
	eq(s.winner, GameState.HUMAN, "start turn holding all 3 beacons -> win")
	eq(s.win_reason, "beacons", "win reason = beacons")


func _invariants_ok(s: GameState) -> String:
	var seen := {}
	for u in s.units:
		if seen.has(u.pos):
			return "two units on %s" % u.pos
		seen[u.pos] = true
		if not HexGrid.in_board(u.pos, GameState.RADIUS):
			return "unit off board"
		if s.hearth_owner_at(u.pos) != GameState.NONE:
			return "unit on a hearth"
		if u.hp <= 0:
			return "dead unit left on board"
	for p in 2:
		if s.oil[p] < 0 or s.oil[p] > GameState.OIL_CAP:
			return "oil out of range: %d" % s.oil[p]
	return ""


func test_ai_single_turn() -> void:
	print("[ai]")
	var s := GameState.new()
	s.end_turn(GameState.HUMAN)
	var oil_before := s.oil[GameState.RIVAL]
	var st := AI.take_turn(s, GameState.RIVAL)
	eq(st.rejected, 0, "AI made no illegal calls")
	check(st.actions >= 2, "AI acted (summon + end turn), actions=%d" % st.actions)
	eq(s.units_of(GameState.RIVAL).size(), 1, "AI summoned one Wick")
	check(s.oil[GameState.RIVAL] < oil_before, "AI spent Oil")
	eq(s.current, GameState.HUMAN, "AI ended its turn")
	eq(_invariants_ok(s), "", "board invariants hold")
	eq(AI.take_turn(s, GameState.RIVAL).actions, 0, "AI does nothing when it is not its turn")


func test_ai_vs_ai() -> void:
	print("[ai vs ai]")
	var games := 5
	var total_rejected := 0
	var bad := ""
	var finished := 0
	var max_turns := 200
	for g in games:
		var s := GameState.new()
		while s.winner == GameState.NONE and s.turn < max_turns:
			var st := AI.take_turn(s, s.current)
			total_rejected += st.rejected
			var inv := _invariants_ok(s)
			if inv != "" and bad == "":
				bad = "game %d turn %d: %s" % [g, s.turn, inv]
		if s.winner != GameState.NONE:
			finished += 1
		print("    game %d: winner P%d by %s after %d turns" % [g, s.winner, s.win_reason, s.turn])
	eq(total_rejected, 0, "AI vs AI: zero rejected actions over %d games" % games)
	eq(bad, "", "AI vs AI: invariants hold every turn")
	check(finished > 0, "AI vs AI: games reach a winner (%d/%d)" % [finished, games])
