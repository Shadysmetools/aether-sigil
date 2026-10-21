## Validates all 120 stages of the bible. map_grid is the source of truth (game_rules.json map_policy).
##   ENGINE  must pass: the game can load and play the stage (grid, tile types, deploy tiles,
##           roster ids, Symbols, paths). Failures here are code or fatal data bugs.
##   DATA    contradictions inside the bible itself. Each one must be a KNOWN data issue: listed in
##           KNOWN_DATA_ISSUES below by stage id + issue key, with the documented rule fallback that
##           handles it (REASONS). An unlisted finding FAILS; a listed issue that no longer occurs
##           FAILS too (stale allowlist), so the list stays honest.
## Prints "N pass / M fail" and exits with M (0 = green).
extends SceneTree

const Data = preload("res://scripts/data_loader.gd")
const GameState = preload("res://scripts/game_state.gd")

## Why each known issue is safe to play. Sources: data/game_rules.json and docs/BALANCE-REPORT.md.
const REASONS := {
	"stone_not_in_legend": "'stone' painted but missing from map_legend -> game_rules.json tiles.stone (walkable, no LOS block, +2 def cover)",
	"objective_tile_repainted": "JSON objective tile painted as another type in map_grid -> map_policy: map_grid is the source of truth",
	"no_player_symbol": "map paints no player_symbol -> map_policy.missing_symbol: placed on the first player_spawn",
	"json_spawn_on_symbol": "JSON spawn list names the Symbol tile -> map_policy: spawns come from the grid's *_spawn tiles",
	"json_spawn_unwalkable": "JSON spawn list names an obstacle -> map_policy: spawns come from the grid's *_spawn tiles",
	"relic_win_under_3_relics": "'secure 3 relic nodes' with 1 relic -> map_policy.relic_counts_capsule_nodes",
	"portal_rule_single_gate": "portal rule with 1 warp gate -> special_rules: active gate teleports to the mirror tile (11-x, 11-y)",
}

## stage id -> known issue keys. Generated from the 2026-10-21 run and reviewed; edit by hand.
const KNOWN_DATA_ISSUES := {
	"T01-L01": ["stone_not_in_legend", "json_spawn_on_symbol"],
	"T01-L02": ["json_spawn_on_symbol", "json_spawn_unwalkable"],
	"T01-L03": ["json_spawn_on_symbol", "relic_win_under_3_relics", "portal_rule_single_gate"],
	"T01-L04": ["json_spawn_on_symbol"],
	"T01-L05": ["objective_tile_repainted", "json_spawn_on_symbol"],
	"T01-L06": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T01-L07": ["json_spawn_on_symbol", "portal_rule_single_gate"],
	"T01-L08": ["json_spawn_on_symbol", "json_spawn_unwalkable"],
	"T01-L09": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T01-L10": ["objective_tile_repainted", "no_player_symbol", "json_spawn_on_symbol"],
	"T02-L01": ["stone_not_in_legend", "json_spawn_on_symbol"],
	"T02-L02": ["json_spawn_on_symbol"],
	"T02-L03": ["json_spawn_on_symbol", "relic_win_under_3_relics", "portal_rule_single_gate"],
	"T02-L04": ["json_spawn_on_symbol"],
	"T02-L05": ["objective_tile_repainted", "json_spawn_on_symbol"],
	"T02-L06": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T02-L07": ["json_spawn_on_symbol", "json_spawn_unwalkable", "portal_rule_single_gate"],
	"T02-L08": ["json_spawn_on_symbol"],
	"T02-L09": ["json_spawn_on_symbol", "json_spawn_unwalkable", "relic_win_under_3_relics"],
	"T02-L10": ["json_spawn_on_symbol", "json_spawn_unwalkable"],
	"T03-L01": ["stone_not_in_legend", "json_spawn_on_symbol"],
	"T03-L02": ["json_spawn_on_symbol"],
	"T03-L03": ["json_spawn_on_symbol", "relic_win_under_3_relics", "portal_rule_single_gate"],
	"T03-L04": ["json_spawn_on_symbol"],
	"T03-L05": ["json_spawn_on_symbol", "json_spawn_unwalkable"],
	"T03-L06": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T03-L07": ["json_spawn_on_symbol", "portal_rule_single_gate"],
	"T03-L08": ["json_spawn_on_symbol"],
	"T03-L09": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T03-L10": ["objective_tile_repainted", "no_player_symbol", "json_spawn_unwalkable", "json_spawn_on_symbol"],
	"T04-L01": ["stone_not_in_legend", "json_spawn_on_symbol"],
	"T04-L02": ["json_spawn_on_symbol"],
	"T04-L03": ["json_spawn_on_symbol", "json_spawn_unwalkable", "relic_win_under_3_relics", "portal_rule_single_gate"],
	"T04-L04": ["objective_tile_repainted", "json_spawn_on_symbol"],
	"T04-L05": ["objective_tile_repainted", "json_spawn_on_symbol"],
	"T04-L06": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T04-L07": ["json_spawn_on_symbol", "portal_rule_single_gate"],
	"T04-L08": ["json_spawn_on_symbol"],
	"T04-L09": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T04-L10": ["json_spawn_on_symbol"],
	"T05-L01": ["stone_not_in_legend", "json_spawn_on_symbol"],
	"T05-L02": ["objective_tile_repainted", "json_spawn_on_symbol"],
	"T05-L03": ["json_spawn_on_symbol", "relic_win_under_3_relics", "portal_rule_single_gate"],
	"T05-L04": ["json_spawn_on_symbol", "json_spawn_unwalkable"],
	"T05-L05": ["json_spawn_on_symbol"],
	"T05-L06": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T05-L07": ["json_spawn_on_symbol", "portal_rule_single_gate"],
	"T05-L08": ["json_spawn_on_symbol"],
	"T05-L09": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T05-L10": ["objective_tile_repainted", "no_player_symbol", "json_spawn_on_symbol"],
	"T06-L01": ["stone_not_in_legend", "json_spawn_on_symbol"],
	"T06-L02": ["json_spawn_on_symbol"],
	"T06-L03": ["json_spawn_on_symbol", "relic_win_under_3_relics", "portal_rule_single_gate"],
	"T06-L04": ["json_spawn_on_symbol"],
	"T06-L05": ["objective_tile_repainted", "json_spawn_on_symbol"],
	"T06-L06": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T06-L07": ["json_spawn_on_symbol", "portal_rule_single_gate"],
	"T06-L08": ["json_spawn_on_symbol"],
	"T06-L09": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T06-L10": ["json_spawn_on_symbol"],
	"T07-L01": ["stone_not_in_legend", "json_spawn_on_symbol", "json_spawn_unwalkable"],
	"T07-L02": ["json_spawn_on_symbol"],
	"T07-L03": ["json_spawn_on_symbol", "json_spawn_unwalkable", "relic_win_under_3_relics", "portal_rule_single_gate"],
	"T07-L04": ["json_spawn_on_symbol"],
	"T07-L05": ["json_spawn_on_symbol"],
	"T07-L06": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T07-L07": ["json_spawn_on_symbol", "portal_rule_single_gate"],
	"T07-L08": ["json_spawn_on_symbol"],
	"T07-L09": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T07-L10": ["objective_tile_repainted", "no_player_symbol", "json_spawn_on_symbol"],
	"T08-L01": ["stone_not_in_legend", "json_spawn_on_symbol", "json_spawn_unwalkable"],
	"T08-L02": ["json_spawn_on_symbol"],
	"T08-L03": ["json_spawn_on_symbol", "relic_win_under_3_relics", "portal_rule_single_gate"],
	"T08-L04": ["json_spawn_on_symbol"],
	"T08-L05": ["objective_tile_repainted", "json_spawn_on_symbol", "json_spawn_unwalkable"],
	"T08-L06": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T08-L07": ["json_spawn_on_symbol", "portal_rule_single_gate"],
	"T08-L08": ["json_spawn_on_symbol"],
	"T08-L09": ["json_spawn_on_symbol", "json_spawn_unwalkable", "relic_win_under_3_relics"],
	"T08-L10": ["objective_tile_repainted", "no_player_symbol", "json_spawn_on_symbol"],
	"T09-L01": ["stone_not_in_legend", "json_spawn_on_symbol"],
	"T09-L02": ["json_spawn_on_symbol"],
	"T09-L03": ["json_spawn_on_symbol", "relic_win_under_3_relics", "portal_rule_single_gate"],
	"T09-L04": ["objective_tile_repainted", "json_spawn_on_symbol"],
	"T09-L05": ["json_spawn_on_symbol"],
	"T09-L06": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T09-L07": ["json_spawn_on_symbol", "portal_rule_single_gate"],
	"T09-L08": ["json_spawn_on_symbol", "json_spawn_unwalkable"],
	"T09-L09": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T09-L10": ["objective_tile_repainted", "no_player_symbol", "json_spawn_on_symbol"],
	"T10-L01": ["stone_not_in_legend", "json_spawn_on_symbol"],
	"T10-L02": ["objective_tile_repainted", "json_spawn_on_symbol"],
	"T10-L03": ["json_spawn_on_symbol", "relic_win_under_3_relics", "portal_rule_single_gate"],
	"T10-L04": ["json_spawn_on_symbol"],
	"T10-L05": ["objective_tile_repainted", "json_spawn_on_symbol"],
	"T10-L06": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T10-L07": ["json_spawn_on_symbol", "json_spawn_unwalkable", "portal_rule_single_gate"],
	"T10-L08": ["json_spawn_on_symbol"],
	"T10-L09": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T10-L10": ["json_spawn_on_symbol"],
	"T11-L01": ["stone_not_in_legend", "json_spawn_on_symbol"],
	"T11-L02": ["json_spawn_on_symbol"],
	"T11-L03": ["json_spawn_on_symbol", "relic_win_under_3_relics", "portal_rule_single_gate"],
	"T11-L04": ["json_spawn_on_symbol"],
	"T11-L05": ["objective_tile_repainted", "json_spawn_on_symbol"],
	"T11-L06": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T11-L07": ["json_spawn_on_symbol", "portal_rule_single_gate"],
	"T11-L08": ["json_spawn_on_symbol"],
	"T11-L09": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T11-L10": ["objective_tile_repainted", "no_player_symbol", "json_spawn_on_symbol"],
	"T12-L01": ["stone_not_in_legend", "json_spawn_on_symbol"],
	"T12-L02": ["json_spawn_on_symbol"],
	"T12-L03": ["json_spawn_on_symbol", "relic_win_under_3_relics", "portal_rule_single_gate"],
	"T12-L04": ["json_spawn_on_symbol"],
	"T12-L05": ["objective_tile_repainted", "json_spawn_on_symbol"],
	"T12-L06": ["json_spawn_on_symbol", "json_spawn_unwalkable", "relic_win_under_3_relics"],
	"T12-L07": ["json_spawn_on_symbol", "portal_rule_single_gate"],
	"T12-L08": ["json_spawn_on_symbol", "json_spawn_unwalkable"],
	"T12-L09": ["json_spawn_on_symbol", "relic_win_under_3_relics"],
	"T12-L10": ["json_spawn_on_symbol", "json_spawn_unwalkable"],
}

var passed := 0
var failed := 0
var engine_failed := 0
var known := 0
var known_seen: Dictionary = {}  ## "stage|key" -> true
var findings: Dictionary = {}    ## key -> Array of "stage detail" (UNLISTED findings only)


func engine(cond: bool, stage_id: String, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		engine_failed += 1
		print("  FAIL  ENGINE %s: %s" % [stage_id, label])


func data(cond: bool, key: String, stage_id: String, detail: String) -> void:
	if cond:
		passed += 1
		return
	if OS.get_cmdline_user_args().has("--dump-findings"):
		print("FINDING|%s|%s" % [stage_id, key])
	if Array(KNOWN_DATA_ISSUES.get(stage_id, [])).has(key):
		known += 1
		known_seen["%s|%s" % [stage_id, key]] = true
		return
	failed += 1
	if not findings.has(key):
		findings[key] = []
	findings[key].append("%s %s" % [stage_id, detail])


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
	# Issue #16: one canonical champion per tower; the L10 opponent IS the tower_boss.
	for t in Data.towers():
		var l10: Dictionary = t.levels[-1]
		engine(str(l10.opponent) == str(t.tower_boss), str(l10.stage_id), "L10 opponent '%s' is the tower champion '%s'" % [l10.opponent, t.tower_boss])
		for line in l10.dialogue.values():
			engine(str(line).begins_with(str(t.tower_boss) + ":"), str(l10.stage_id), "L10 dialogue spoken by the champion")
	var names := {}
	for id in Data.monster_ids():
		var nm := str(Data.monster(id).name)
		engine(not names.has(nm), id, "monster name '%s' is unique" % nm)
		engine(not nm.to_lower().contains("archen"), id, "no 'archen' in monster names")
		names[nm] = true
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
	var stale := []
	for sid in KNOWN_DATA_ISSUES:
		for key in KNOWN_DATA_ISSUES[sid]:
			if not known_seen.has("%s|%s" % [sid, key]):
				stale.append("%s %s" % [sid, key])
	failed += stale.size()
	var per_key := {}
	for k in known_seen:
		var key: String = k.split("|")[1]
		per_key[key] = per_key.get(key, 0) + 1
	print("KNOWN DATA ISSUES (allowlisted with a rule fallback): %d occurrences across %d stages" % [known, KNOWN_DATA_ISSUES.size()])
	for key in per_key:
		print("  %-26s %3d stages  %s" % [key, per_key[key], REASONS.get(key, "")])
	print("STALE allowlist entries (listed but no longer found): %d %s" % [stale.size(), str(stale.slice(0, 8))])
	print("UNLISTED DATA FINDINGS (fail):")
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
	quit(mini(failed, 255))  # exit codes wrap at 256


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
		data(st.get("map_legend", {}).has(t), "stone_not_in_legend" if t == "stone" else "tile_not_in_legend", id, "'%s'" % t)

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
			data(g[c.y][c.x] == o.type, "objective_tile_repainted", id, "%s %s is '%s'" % [o.type, c, g[c.y][c.x]])
	engine(syms.player_symbol == 1 and syms.enemy_symbol == 1, id, "exactly one Symbol per side in objectives")
	var painted := {"player_symbol": 0, "enemy_symbol": 0}
	for row in g:
		for t in row:
			if painted.has(t):
				painted[t] += 1
	data(painted.player_symbol == 1, "no_player_symbol", id, "%d painted" % painted.player_symbol)
	data(painted.enemy_symbol == 1, "no_enemy_symbol", id, "%d painted" % painted.enemy_symbol)

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
				data(false, "json_spawn_on_symbol", id, "%s %s" % [key, c])
			else:
				data(s.is_walkable(c), "json_spawn_unwalkable", id, "%s %s is '%s'" % [key, c, t])

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
		data(s.relics.size() >= int(Data.rules().relics_to_win), "relic_win_under_3_relics", id, "%d relic(s)" % s.relics.size())
	if s.rule.get("random_portal", false):
		data(s.portals.size() >= 2, "portal_rule_single_gate", id, "%d gate(s)" % s.portals.size())
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
