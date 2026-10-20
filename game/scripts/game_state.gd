## Aether Sigil battle rules. Pure logic (RefCounted, no nodes, no drawing): runs headless.
## Every mutating action has a can_* check that returns a reason code (OK on success).
## The UI and the AI act ONLY through legal_* / can_* / apply(), so the AI can never do
## anything a human could not. All numbers come from data/game_rules.json.
extends RefCounted

const Data = preload("res://scripts/data_loader.gd")

const SIZE := 12
const NONE := -1
const PLAYER := 0
const ENEMY := 1
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

# Reason codes.
const OK := "ok"
const R_GAME_OVER := "game_over"
const R_NOT_YOUR_TURN := "not_your_turn"
const R_NOT_IN_RESERVE := "not_in_reserve"
const R_NO_AP := "not_enough_ap"
const R_BAD_DEPLOY_TILE := "not_a_deploy_tile"
const R_NOT_YOUR_UNIT := "not_your_unit"
const R_ALREADY_MOVED := "already_moved"
const R_ALREADY_ATTACKED := "already_attacked"
const R_UNREACHABLE := "unreachable"
const R_NO_TARGET := "no_enemy_there"
const R_OUT_OF_RANGE := "out_of_range"
const R_BAD_ACTION := "bad_action"


class Unit:
	var id: int
	var mon_id: String
	var name: String
	var element: String
	var family: String
	var role: String
	var owner: int
	var pos: Vector2i
	var hp: int
	var max_hp: int
	var attack: int
	var defense: int
	var move: int
	var attack_range: int
	var ability: String
	var moved := false
	var attacked := false


var stage: Dictionary = {}
var stage_id := ""
var grid: Array = []                 ## [y][x] effective tile type (objectives overlay the map_grid)
var symbol_pos: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(-1, -1)]
var symbol_hp: Array[int] = [0, 0]
var symbol_max := 0
var symbol_defense := 0
var spawn_tiles: Array = [[], []]    ## per side: Array of Vector2i (walkable, not a Symbol)
var nodes: Dictionary = {}           ## capsule node Vector2i -> owner or NONE
var relics: Dictionary = {}          ## relic Vector2i -> owner or NONE
var portals: Array[Vector2i] = []
var active_portal: Vector2i = Vector2i(-1, -1)
var units: Array[Unit] = []
var reserve: Array = [[], []]        ## per side: monster ids not yet deployed
var current := PLAYER
var turn := 1                        ## player-turns so far, from 1
var round_num := 1
var ap: Array[int] = [0, 0]
var momentum: Array[int] = [0, 0]    ## own turns of KO movement bonus left
var kos: Array[int] = [0, 0]         ## monsters each side has LOST
var rule: Dictionary = {}            ## effects of this stage's special_rule
var relic_win := false
var hazard_tier := 1
var winner := NONE
var win_reason := ""
var events: Array[String] = []
var rng := RandomNumberGenerator.new()
var _next_id := 1
var _field_cache: Dictionary = {}    ## goal Vector2i -> distance field


## Builds a battle for a stage. player_team defaults to the starter team.
func setup(p_stage_id: String, player_team: Array = [], seed_value: int = -1) -> bool:
	stage = Data.stage(p_stage_id)
	if stage.is_empty():
		push_error("game_state: unknown stage %s" % p_stage_id)
		return false
	stage_id = p_stage_id
	var R := Data.rules()
	rng.seed = hash(p_stage_id) if seed_value < 0 else seed_value
	grid = []
	for row in stage.get("map_grid", []):
		grid.append(Array(row).duplicate())
	# Objectives are explicit coordinates: they win over the painted grid (20 tiles disagree).
	symbol_pos = [Vector2i(-1, -1), Vector2i(-1, -1)]
	for o in stage.get("objectives", []):
		var c := Data.vec(o.get("tile"))
		var t := str(o.get("type", ""))
		if not in_bounds(c):
			continue
		grid[c.y][c.x] = t
		if t == "player_symbol":
			symbol_pos[PLAYER] = c
		elif t == "enemy_symbol":
			symbol_pos[ENEMY] = c
	for side in 2:
		if symbol_pos[side] == Vector2i(-1, -1):
			symbol_pos[side] = _find_tile("player_symbol" if side == PLAYER else "enemy_symbol")
	symbol_max = int(R.symbol.hp)
	symbol_defense = int(R.symbol.defense)
	symbol_hp = [symbol_max, symbol_max]
	nodes = {}
	relics = {}
	portals = []
	for y in SIZE:
		for x in SIZE:
			var c := Vector2i(x, y)
			match tile_type(c):
				"capsule_node": nodes[c] = NONE
				"relic": relics[c] = NONE
				"warp_gate": portals.append(c)
	spawn_tiles = [[], []]
	for side in 2:
		var listed: Array = stage.get("player_spawns" if side == PLAYER else "enemy_spawns", [])
		var cands: Array[Vector2i] = []
		for a in listed:
			cands.append(Data.vec(a))
		var spawn_type := "player_spawn" if side == PLAYER else "enemy_spawn"
		for y in SIZE:
			for x in SIZE:
				if grid[y][x] == spawn_type:
					cands.append(Vector2i(x, y))
		for c in cands:
			if is_walkable(c) and not spawn_tiles[side].has(c):
				spawn_tiles[side].append(c)
	rule = Data.special_rule(str(stage.get("special_rule", "")))
	relic_win = str(stage.get("win_condition", "")).to_lower().contains("relic")
	hazard_tier = 1
	var tier_re := RegEx.create_from_string("tier\\s*(\\d+)")
	for h in stage.get("hazards", []):
		var m := tier_re.search(str(h))
		if m:
			hazard_tier = int(m.get_string(1))
	units = []
	var team: Array = player_team if not player_team.is_empty() else Data.starter_team()
	reserve = [team.duplicate(), Array(stage.get("enemy_roster", [])).duplicate()]
	current = PLAYER
	turn = 1
	round_num = 1
	ap = [int(R.ap.start), int(R.ap.start)]
	momentum = [0, 0]
	kos = [0, 0]
	winner = NONE
	win_reason = ""
	events = []
	_next_id = 1
	_field_cache = {}
	_roll_portal()
	return true


static func other(p: int) -> int:
	return 1 - p


# ---------------------------------------------------------------- board queries

static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < SIZE and c.y < SIZE


func tile_type(c: Vector2i) -> String:
	if not in_bounds(c) or grid.is_empty():
		return ""
	return str(grid[c.y][c.x])


func tile_def(c: Vector2i) -> Dictionary:
	return Data.tile_def(tile_type(c))


## Terrain passability (ignores units). Symbols and obstacles block.
func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and bool(tile_def(c).get("walkable", false))


func unit_at(c: Vector2i) -> Unit:
	for u in units:
		if u.pos == c:
			return u
	return null


func get_unit(id: int) -> Unit:
	for u in units:
		if u.id == id:
			return u
	return null


func units_of(p: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.owner == p:
			out.append(u)
	return out


func symbol_owner_at(c: Vector2i) -> int:
	return symbol_pos.find(c)


func _find_tile(t: String) -> Vector2i:
	for y in SIZE:
		for x in SIZE:
			if grid[y][x] == t:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Steps from every tile to `goal` over walkable terrain, ignoring units (cached; terrain is static).
## The goal itself may be unwalkable (a Symbol): tiles next to it get 1.
func distance_field(goal: Vector2i) -> Dictionary:
	if _field_cache.has(goal):
		return _field_cache[goal]
	var dist := {goal: 0}
	var frontier: Array[Vector2i] = [goal]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		for d in DIRS:
			var n := c + d
			if dist.has(n) or not is_walkable(n):
				continue
			dist[n] = dist[c] + 1
			frontier.append(n)
	_field_cache[goal] = dist
	return dist


# ---------------------------------------------------------------- stats

func terrain_mult() -> int:
	return int(rule.get("terrain_mult", 1))


func _family_match(u: Unit, c: Vector2i) -> bool:
	return Array(tile_def(c).get("family", [])).has(u.family)


func attack_of(u: Unit, c: Vector2i) -> int:
	var tb: Dictionary = Data.rules().terrain_bonus
	var bonus := int(tile_def(c).get("atk_bonus", 0))
	if _family_match(u, c):
		bonus += int(tb.family_atk)
	return u.attack + bonus * terrain_mult()


func defense_of(u: Unit, c: Vector2i) -> int:
	var tb: Dictionary = Data.rules().terrain_bonus
	var td := tile_def(c)
	var bonus := int(td.get("def_bonus", 0))
	if _family_match(u, c):
		bonus += int(tb.family_def)
	if td.get("mixed", false):
		bonus += int(tb.mixed_def)
	return u.defense + bonus * terrain_mult()


## Range bonus from high ground is NOT doubled by 'Terrain bonuses are doubled' (range 6 would cover half the board).
func range_of(u: Unit, c: Vector2i) -> int:
	return u.attack_range + int(tile_def(c).get("range_bonus", 0))


func move_of(u: Unit) -> int:
	return u.move + (int(rule.get("ko_move_bonus", 0)) if momentum[u.owner] > 0 else 0)


static func beats(a_family: String, d_family: String) -> bool:
	return Array(Data.rules().element_chart.get(a_family, [])).has(d_family)


## max(1, attack - defense), then x1.5 advantage / x0.75 disadvantage (floored, min 1).
static func compute_damage(atk: int, def: int, a_family: String, d_family: String) -> int:
	var dm: Dictionary = Data.rules().damage
	var d := float(maxi(1, atk - def))
	if d_family != "" and beats(a_family, d_family):
		d *= float(dm.advantage_mult)
	elif d_family != "" and beats(d_family, a_family):
		d *= float(dm.disadvantage_mult)
	return maxi(1, int(floor(d)))


func damage_preview(u: Unit, target: Vector2i) -> int:
	var t := unit_at(target)
	if t != null:
		return compute_damage(attack_of(u, u.pos), defense_of(t, t.pos), u.family, t.family)
	return compute_damage(attack_of(u, u.pos), symbol_defense, u.family, "")


# ---------------------------------------------------------------- turn checks

func _turn_check(p: int) -> String:
	if winner != NONE:
		return R_GAME_OVER
	if p != current:
		return R_NOT_YOUR_TURN
	return OK


# ---------------------------------------------------------------- deploy

func deploy_cost() -> int:
	return int(rule.get("deploy_ap_cost", 0))


## Own spawn tiles plus capsule nodes this side has captured, that are free.
func deploy_tiles(p: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in spawn_tiles[p]:
		if unit_at(c) == null:
			out.append(c)
	for c in nodes:
		if nodes[c] == p and unit_at(c) == null and not out.has(c):
			out.append(c)
	return out


func can_deploy(p: int, mon_id: String, c: Vector2i) -> String:
	var r := _turn_check(p)
	if r != OK:
		return r
	if not reserve[p].has(mon_id):
		return R_NOT_IN_RESERVE
	if ap[p] < deploy_cost():
		return R_NO_AP
	if not deploy_tiles(p).has(c):
		return R_BAD_DEPLOY_TILE
	return OK


func deploy(p: int, mon_id: String, c: Vector2i) -> String:
	var r := can_deploy(p, mon_id, c)
	if r != OK:
		return r
	ap[p] -= deploy_cost()
	reserve[p].erase(mon_id)
	var u := place_unit(p, mon_id, c)
	u.moved = true      # deployment sickness: acts from next turn
	u.attacked = true
	_log("P%d deploys %s at %s" % [p, u.name, c])
	return OK


## Puts a monster on the board with NO rule checks (tests, tutorials, tools).
func place_unit(p: int, mon_id: String, c: Vector2i) -> Unit:
	var d := Data.monster(mon_id)
	var u := Unit.new()
	u.id = _next_id
	_next_id += 1
	u.mon_id = mon_id
	u.name = str(d.get("name", mon_id))
	u.element = str(d.get("element", ""))
	u.family = str(d.get("element_family", ""))
	u.role = str(d.get("role", ""))
	u.owner = p
	u.pos = c
	u.hp = int(d.get("hp", 1))
	u.max_hp = u.hp
	u.attack = int(d.get("attack", 0))
	u.defense = int(d.get("defense", 0))
	u.move = int(d.get("move", 1))
	u.attack_range = int(d.get("range", 1))
	u.ability = str(d.get("ability", ""))
	units.append(u)
	return u


# ---------------------------------------------------------------- movement

## Tiles the unit can end on -> movement cost (Dijkstra, 4-dir, units block). Excludes its own tile.
func reachable(u: Unit) -> Dictionary:
	var budget := move_of(u)
	var cost := {u.pos: 0}
	var open: Array[Vector2i] = [u.pos]
	while not open.is_empty():
		var best_i := 0
		for i in open.size():
			if cost[open[i]] < cost[open[best_i]]:
				best_i = i
		var c: Vector2i = open[best_i]
		open.remove_at(best_i)
		for d in DIRS:
			var n := c + d
			if not is_walkable(n) or unit_at(n) != null:
				continue
			var nc: int = cost[c] + int(tile_def(n).get("move_cost", 1))
			if nc > budget or (cost.has(n) and cost[n] <= nc):
				continue
			cost[n] = nc
			open.append(n)
	cost.erase(u.pos)
	return cost


func can_move(p: int, unit_id: int, dest: Vector2i) -> String:
	var r := _turn_check(p)
	if r != OK:
		return r
	var u := get_unit(unit_id)
	if u == null or u.owner != p:
		return R_NOT_YOUR_UNIT
	if u.moved:
		return R_ALREADY_MOVED
	if u.attacked:
		return R_ALREADY_ATTACKED
	if not reachable(u).has(dest):
		return R_UNREACHABLE
	return OK


func move_unit(p: int, unit_id: int, dest: Vector2i) -> String:
	var r := can_move(p, unit_id, dest)
	if r != OK:
		return r
	var u := get_unit(unit_id)
	u.pos = dest
	u.moved = true
	if rule.get("random_portal", false) and dest == active_portal:
		var to := portal_destination(dest)
		if to != dest:
			u.pos = to
			_log("%s warps %s -> %s" % [u.name, dest, to])
	return OK


## Active gate sends a unit to the mirrored tile (11-x, 11-y), or the nearest free walkable tile to it.
func portal_destination(from: Vector2i) -> Vector2i:
	var mirror := Vector2i(SIZE - 1 - from.x, SIZE - 1 - from.y)
	var seen := {mirror: true}
	var q: Array[Vector2i] = [mirror]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c != from and is_walkable(c) and unit_at(c) == null:
			return c
		for d in DIRS:
			var n := c + d
			if in_bounds(n) and not seen.has(n):
				seen[n] = true
				q.append(n)
	return from


func _roll_portal() -> void:
	active_portal = Vector2i(-1, -1)
	if rule.get("random_portal", false) and not portals.is_empty():
		active_portal = portals[rng.randi_range(0, portals.size() - 1)]


# ---------------------------------------------------------------- combat

func can_attack(p: int, unit_id: int, target: Vector2i) -> String:
	var r := _turn_check(p)
	if r != OK:
		return r
	var u := get_unit(unit_id)
	if u == null or u.owner != p:
		return R_NOT_YOUR_UNIT
	if u.attacked:
		return R_ALREADY_ATTACKED
	var t := unit_at(target)
	var enemy_symbol := symbol_owner_at(target) == other(p)
	if not enemy_symbol and (t == null or t.owner == p):
		return R_NO_TARGET
	if manhattan(u.pos, target) > range_of(u, u.pos):
		return R_OUT_OF_RANGE
	return OK


func attack(p: int, unit_id: int, target: Vector2i) -> String:
	var r := can_attack(p, unit_id, target)
	if r != OK:
		return r
	var u := get_unit(unit_id)
	var dmg := damage_preview(u, target)
	u.attacked = true
	u.moved = true  # attacking ends the monster's turn
	var t := unit_at(target)
	if t != null:
		t.hp -= dmg
		_log("%s hits %s for %d" % [u.name, t.name, dmg])
		if t.hp <= 0:
			_knock_out(t)
			if rule.has("ko_move_bonus"):
				momentum[p] = 2  # rest of this turn + next own turn
	else:
		var victim := other(p)
		symbol_hp[victim] = maxi(0, symbol_hp[victim] - dmg)
		_log("%s hits P%d Symbol for %d" % [u.name, victim, dmg])
		if symbol_hp[victim] == 0:
			_set_winner(p, "symbol")
	return OK


func _knock_out(t: Unit) -> void:
	units.erase(t)
	kos[t.owner] += 1
	_log("%s is knocked out" % t.name)
	_check_elimination()


func _check_elimination() -> void:
	for side in 2:
		if units_of(side).is_empty() and reserve[side].is_empty():
			_set_winner(other(side), "elimination")


# ---------------------------------------------------------------- turns

func end_turn(p: int) -> String:
	var r := _turn_check(p)
	if r != OK:
		return r
	var hz := int(Data.rules().hazard_damage_per_tier) * hazard_tier
	for u in units_of(p):
		if tile_type(u.pos) == "hazard":
			u.hp -= hz
			_log("%s takes %d hazard damage" % [u.name, hz])
			if u.hp <= 0:
				_knock_out(u)
	for u in units_of(p):
		if nodes.has(u.pos) and nodes[u.pos] != p:
			nodes[u.pos] = p
			_log("P%d captures the capsule node at %s" % [p, u.pos])
		if relics.has(u.pos) and relics[u.pos] != p:
			relics[u.pos] = p
			_log("P%d secures the relic at %s" % [p, u.pos])
	if relic_win and relics_owned(p) >= int(Data.rules().relics_to_win):
		_set_winner(p, "relics")
	if momentum[p] > 0:
		momentum[p] -= 1
	if winner != NONE:
		return OK
	current = other(p)
	turn += 1
	if current == PLAYER:
		round_num += 1
		_roll_portal()
	_start_turn()
	return OK


func _start_turn() -> void:
	var A: Dictionary = Data.rules().ap
	ap[current] = mini(int(A.cap), ap[current] + int(A.per_turn))
	var pct := int(Data.rules().recharge_pct)
	for u in units_of(current):
		u.moved = false
		u.attacked = false
		if nodes.get(u.pos, NONE) == current and u.hp < u.max_hp:
			var heal := maxi(1, u.max_hp * pct / 100)
			u.hp = mini(u.max_hp, u.hp + heal)
			_log("%s recharges %d HP on its capsule node" % [u.name, heal])


func relics_owned(p: int) -> int:
	var n := 0
	for c in relics:
		if relics[c] == p:
			n += 1
	return n


func _set_winner(p: int, reason: String) -> void:
	if winner == NONE:
		winner = p
		win_reason = reason
		_log("P%d wins by %s" % [p, reason])


func _log(msg: String) -> void:
	events.append(msg)


# ---------------------------------------------------------------- legal-action API (UI + AI)

func legal_deploys(p: int) -> Array:
	var out := []
	if _turn_check(p) != OK or ap[p] < deploy_cost():
		return out
	var tiles := deploy_tiles(p)
	for mon in reserve[p]:
		for c in tiles:
			out.append({"type": "deploy", "mon": mon, "tile": c})
	return out


func legal_moves(u: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if u == null or _turn_check(u.owner) != OK or u.moved or u.attacked:
		return out
	for c in reachable(u):
		out.append(c)
	return out


func legal_attacks(u: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if u == null or _turn_check(u.owner) != OK or u.attacked:
		return out
	var targets: Array[Vector2i] = [symbol_pos[other(u.owner)]]
	for e in units_of(other(u.owner)):
		targets.append(e.pos)
	for t in targets:
		if can_attack(u.owner, u.id, t) == OK:
			out.append(t)
	return out


## Every legal action for side p as dicts: deploy / move / attack / end.
func legal_actions(p: int) -> Array:
	var out := legal_deploys(p)
	for u in units_of(p):
		for c in legal_moves(u):
			out.append({"type": "move", "unit": u.id, "tile": c})
		for c in legal_attacks(u):
			out.append({"type": "attack", "unit": u.id, "tile": c})
	if _turn_check(p) == OK:
		out.append({"type": "end"})
	return out


func apply(p: int, a: Dictionary) -> String:
	match str(a.get("type", "")):
		"deploy": return deploy(p, str(a.mon), a.tile)
		"move": return move_unit(p, int(a.unit), a.tile)
		"attack": return attack(p, int(a.unit), a.tile)
		"end": return end_turn(p)
	return R_BAD_ACTION
