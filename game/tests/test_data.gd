## Validates all 120 stages of the bible. Two kinds of check:
##   ENGINE  must pass: the game can load and play the stage (grid, tile types, deploy tiles,
##           roster ids, Symbols, paths). Failures here are code or fatal data bugs.
##   DATA    contradictions inside the bible itself. Reported as data findings, never "fixed"
##           in the data; the rules engine applies the documented policy in game_rules.json.
## Prints "N pass / M fail" (M counts both kinds) and exits with the ENGINE failure count.
extends SceneTree

const Data = preload("res://scripts/data_loader.gd")
const GameState = preload("res://scripts/game_state.gd")

var passed := 0
var failed := 0
var engine_failed := 0
var findings: Dictionary = {}   ## category -> Array of "stage: detail"


func engine(cond: bool, stage_id: String, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		engine_failed += 1
		print("  FAIL  ENGINE %s: %s" % [stage_id, label])


func data(cond: bool, category: String, stage_id: String, detail: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		if not findings.has(category):
			findings[category] = []
		findings[category].append("%s %s" % [stage_id, detail])


func _initialize() -> void:
	print("Aether Sigil data validation")
	if not Data.ensure_loaded():
		print("  FAIL  bible did not load")
		print("0 pass / 1 fail")
		quit(1)
		return
	var stages := Data.stages()
	engine(stages.size() == 120, "ALL", "120 stages (got %d)" % stages.size())
	engine(Data.towers().size() == 12, "ALL", "12 towers")
	engine(Data.monster_ids().size() == int(Data.bible().monster_count), "ALL", "monster_count matches the list")
	var tiles_seen := {}
	for st in stages:
		check_stage(st, tiles_seen)
	check_monsters()
	var unhandled := []
	for t in tiles_seen:
		if not Data.tile_handled(t):
			unhandled.append(t)
	print("Tile types seen on the 120 maps (%d): %s" % [tiles_seen.size(), ", ".join(tiles_seen.keys())])
	engine(unhandled.is_empty(), "ALL", "every tile type has a rule (unhandled: %s)" % str(unhandled))
	print("")
	print("DATA FINDINGS (contradictions in the bible; engine policy in data/game_rules.json):")
	if findings.is_empty():
		print("  none")
	for cat in findings:
		var items: Array = findings[cat]
		print("  [%s] %d" % [cat, items.size()])
		var shown := items.slice(0, 8)
		print("    " + "; ".join(shown) + (" ... (+%d more)" % (items.size() - 8) if items.size() > 8 else ""))
	print("")
	print("ENGINE failures: %d" % engine_failed)
	print("%d pass / %d fail" % [passed, failed])
	quit(engine_failed)


func check_stage(st: Dictionary, tiles_seen: Dictionary) -> void:
	var id: String = st.stage_id
	var g: Array = st.get("map_grid", [])
	var square := g.size() == 12
	for row in g:
		square = square and Array(row).size() == 12
	engine(square, id, "map_grid is 12x12")
	engine(str(st.get("map_size", "")) == "12x12", id, "map_size says 12x12")
	if not square:
		return
	var used := {}
	for row in g:
		for t in row:
			used[t] = true
			tiles_seen[t] = true
	for t in used:
		engine(Data.tile_handled(t), id, "tile type '%s' handled" % t)
	for t in st.get("map_legend", {}):
		engine(Data.tile_handled(t), id, "legend type '%s' handled" % t)
	for t in used:
		data(st.get("map_legend", {}).has(t), "tile used but missing from map_legend", id, "'%s'" % t)

	# Objectives vs painted grid.
	var syms := {"player_symbol": 0, "enemy_symbol": 0}
	for o in st.get("objectives", []):
		var c := Data.vec(o.tile)
		var inb := GameState.in_bounds(c)
		engine(inb, id, "objective %s %s in bounds" % [o.type, c])
		engine(Data.tile_handled(str(o.type)), id, "objective type '%s' handled" % o.type)
		if syms.has(o.type):
			syms[o.type] += 1
		if inb:
			data(g[c.y][c.x] == o.type, "objective tile painted as another type in map_grid", id, "%s %s is '%s'" % [o.type, c, g[c.y][c.x]])
	engine(syms.player_symbol == 1 and syms.enemy_symbol == 1, id, "exactly one Symbol per side in objectives")

	var s := GameState.new()
	engine(s.setup(id), id, "GameState.setup")
	for side in 2:
		engine(GameState.in_bounds(s.symbol_pos[side]), id, "Symbol %d located" % side)
		engine(not s.spawn_tiles[side].is_empty(), id, "side %d has at least one legal deploy tile" % side)
		for c in s.spawn_tiles[side]:
			engine(s.is_walkable(c) and s.symbol_owner_at(c) == GameState.NONE, id, "deploy tile %s walkable" % c)
	for c in s.nodes:
		engine(s.is_walkable(c), id, "capsule node %s walkable" % c)

	# Listed spawns (data): in bounds, on a walkable tile that is not a Symbol.
	for key in ["player_spawns", "enemy_spawns"]:
		for a in st.get(key, []):
			var c := Data.vec(a)
			engine(GameState.in_bounds(c), id, "%s %s in bounds" % [key, c])
			if not GameState.in_bounds(c):
				continue
			var t := s.tile_type(c)
			if t.ends_with("_symbol"):
				data(false, "listed spawn sits ON a Symbol (Symbol tile excluded from deploy)", id, "%s %s" % [key, c])
			else:
				data(s.is_walkable(c), "listed spawn on an unwalkable tile", id, "%s %s is '%s'" % [key, c, t])

	# Paths: from each player spawn (listed and effective) to the enemy Symbol, and back.
	var to_enemy := s.distance_field(s.symbol_pos[GameState.ENEMY])
	var to_player := s.distance_field(s.symbol_pos[GameState.PLAYER])
	var starts: Array[Vector2i] = []
	for a in st.get("player_spawns", []):
		starts.append(Data.vec(a))
	for c in s.spawn_tiles[GameState.PLAYER]:
		if not starts.has(c):
			starts.append(c)
	for c in starts:
		engine(_reaches(s, to_enemy, c), id, "path from player spawn %s to enemy Symbol" % c)
	for c in s.spawn_tiles[GameState.ENEMY]:
		engine(_reaches(s, to_player, c), id, "path from enemy spawn %s to player Symbol" % c)

	# Roster.
	var roster: Array = st.get("enemy_roster", [])
	engine(not roster.is_empty(), id, "enemy roster not empty")
	for m in roster:
		engine(Data.has_monster(m), id, "roster monster %s exists" % m)

	# Rules text.
	var rule := str(st.get("special_rule", ""))
	engine(Data.special_rule_known(rule), id, "special_rule implemented: '%s'" % rule)
	var win := str(st.get("win_condition", ""))
	engine(win.contains("Defeat the enemy Symbol"), id, "win condition includes 'Defeat the enemy Symbol'")
	if s.relic_win:
		data(s.relics.size() >= int(Data.rules().relics_to_win), "'secure 3 relic nodes' but fewer than 3 relics on the map", id, "%d relic(s)" % s.relics.size())
	if s.rule.get("random_portal", false):
		data(s.portals.size() >= 2, "portal rule but fewer than 2 warp gates (no gate-to-gate link)", id, "%d gate(s)" % s.portals.size())
	var dlg: Dictionary = st.get("dialogue", {})
	for k in ["intro", "midbattle", "defeat"]:
		engine(str(dlg.get(k, "")) != "", id, "dialogue '%s' present" % k)


func _reaches(s: GameState, field: Dictionary, c: Vector2i) -> bool:
	if field.has(c):
		return true
	for d in GameState.DIRS:  # a spawn on an obstacle still counts if it touches the network
		if field.has(c + d):
			return true
	return false


func check_monsters() -> void:
	var fams: Dictionary = Data.rules().element_chart
	for id in Data.monster_ids():
		var m := Data.monster(id)
		var ok := true
		for k in ["hp", "attack", "defense", "move", "range"]:
			ok = ok and m.has(k) and int(m[k]) > 0
		engine(ok, id, "positive hp/attack/defense/move/range")
		engine(fams.has(str(m.get("element_family", ""))), id, "family '%s' in element chart" % m.get("element_family", ""))
