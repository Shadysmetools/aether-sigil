## All Emberwick rules. Pure logic: no nodes, no drawing, so it runs headless in tests.
## Every mutating action has a matching can_* check that returns a reason code (OK on success).
extends RefCounted

const HexGrid = preload("res://scripts/hex_grid.gd")
const Wicks = preload("res://scripts/wicks.gd")

const RADIUS := 3
const NONE := -1
const HUMAN := 0
const RIVAL := 1

const HEARTH_TILES: Array[Vector2i] = [Vector2i(0, 3), Vector2i(0, -3)]
const BEACON_TILES: Array[Vector2i] = [Vector2i(-2, 1), Vector2i(0, 0), Vector2i(2, -1)]
const HEARTH_HP := 10
const START_OIL := 0
const OIL_PER_TURN := 2
const OIL_CAP := 10
const POST_COST := 2
const DARK_POWER_PENALTY := 1

# Reason codes returned by can_* / action methods.
const OK := "ok"
const R_GAME_OVER := "game_over"
const R_NOT_YOUR_TURN := "not_your_turn"
const R_NOT_IN_SATCHEL := "not_in_satchel"
const R_NO_OIL := "not_enough_oil"
const R_OFF_BOARD := "off_board"
const R_OCCUPIED := "tile_occupied"
const R_NOT_YOUR_LIGHT := "not_your_light"
const R_NOT_NEAR_SOURCE := "not_next_to_hearth_or_post"
const R_HAS_POST := "already_has_post"
const R_RESERVED := "reserved_tile"
const R_NOT_YOUR_UNIT := "not_your_wick"
const R_ALREADY_MOVED := "already_moved"
const R_ALREADY_ATTACKED := "already_attacked"
const R_UNREACHABLE := "unreachable"
const R_NO_TARGET := "no_enemy_there"
const R_OUT_OF_RANGE := "out_of_range"


class Unit:
	var id: int
	var def_id: String
	var name: String
	var element: String
	var owner: int
	var pos: Vector2i
	var hp: int
	var max_hp: int
	var power: int
	var guard: int
	var move: int
	var attack_range: int
	var ability: String
	var moved := false
	var attacked := false


var tiles: Array[Vector2i] = []
var current: int = HUMAN
var turn: int = 1            ## counts every player-turn, starting at 1
var oil: Array[int] = [0, 0]
var hearth_hp: Array[int] = [HEARTH_HP, HEARTH_HP]
var posts: Dictionary = {}   ## Vector2i -> owner
var kindled: Dictionary = {} ## Vector2i -> owner (Pip's Kindle; overrides other light)
var beacons: Dictionary = {} ## Vector2i -> owner or NONE
var units: Array[Unit] = []
var satchels: Array = [[], []]
var winner: int = NONE
var win_reason := ""
var events: Array[String] = []
var _next_id := 1


func _init() -> void:
	reset()


func reset() -> void:
	tiles = HexGrid.all_tiles(RADIUS)
	current = HUMAN
	turn = 1
	oil = [START_OIL, START_OIL]
	hearth_hp = [HEARTH_HP, HEARTH_HP]
	posts = {}
	kindled = {}
	beacons = {}
	for b in BEACON_TILES:
		beacons[b] = NONE
	units = []
	satchels = [Wicks.STARTING_SATCHEL.duplicate(), Wicks.STARTING_SATCHEL.duplicate()]
	winner = NONE
	win_reason = ""
	events = []
	_next_id = 1
	_start_turn()


static func other(p: int) -> int:
	return 1 - p


# ---------------------------------------------------------------- light

func light_sources(p: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [HEARTH_TILES[p]]
	for c in posts:
		if posts[c] == p:
			out.append(c)
	return out


func _reaches(p: int, c: Vector2i) -> bool:
	for s in light_sources(p):
		if HexGrid.distance(s, c) <= 1:
			return true
	return false


## Owner of the light on a tile, or NONE if dark.
## Precedence: a Kindled tile belongs to whoever kindled it; otherwise exactly one
## player's light must reach it. A tile reached by BOTH lights is contested = dark.
func light_owner(c: Vector2i) -> int:
	if not HexGrid.in_board(c, RADIUS):
		return NONE
	if kindled.has(c):
		return kindled[c]
	var a := _reaches(HUMAN, c)
	var b := _reaches(RIVAL, c)
	if a and not b:
		return HUMAN
	if b and not a:
		return RIVAL
	return NONE


func owned_tile_count(p: int) -> int:
	var n := 0
	for c in tiles:
		if light_owner(c) == p:
			n += 1
	return n


func beacons_owned(p: int) -> int:
	var n := 0
	for b in beacons:
		if beacons[b] == p:
			n += 1
	return n


# ---------------------------------------------------------------- queries

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


func hearth_owner_at(c: Vector2i) -> int:
	return HEARTH_TILES.find(c)  # -1 (NONE) if not a hearth


func is_blocked(c: Vector2i) -> bool:
	return unit_at(c) != null or hearth_owner_at(c) != NONE


func units_of(p: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.owner == p:
			out.append(u)
	return out


func _turn_check(p: int) -> String:
	if winner != NONE:
		return R_GAME_OVER
	if p != current:
		return R_NOT_YOUR_TURN
	return OK


# ---------------------------------------------------------------- summon

func can_summon(p: int, def_id: String, c: Vector2i) -> String:
	var r := _turn_check(p)
	if r != OK:
		return r
	if not (def_id in satchels[p]):
		return R_NOT_IN_SATCHEL
	if oil[p] < int(Wicks.get_def(def_id).cost):
		return R_NO_OIL
	if not HexGrid.in_board(c, RADIUS):
		return R_OFF_BOARD
	if is_blocked(c):
		return R_OCCUPIED
	if light_owner(c) != p:
		return R_NOT_YOUR_LIGHT
	var near := false
	for s in light_sources(p):
		if HexGrid.distance(s, c) == 1:
			near = true
			break
	if not near:
		return R_NOT_NEAR_SOURCE
	return OK


func summon(p: int, def_id: String, c: Vector2i) -> String:
	var r := can_summon(p, def_id, c)
	if r != OK:
		return r
	oil[p] -= int(Wicks.get_def(def_id).cost)
	satchels[p].erase(def_id)
	var u := place_unit(p, def_id, c)
	u.moved = true      # summoning sickness: acts from next turn
	u.attacked = true
	_log("P%d summons %s at %s" % [p, u.name, c])
	return OK


## Puts a Wick on the board with NO rule checks (tests, tutorials, editor tools).
func place_unit(p: int, def_id: String, c: Vector2i) -> Unit:
	var d := Wicks.get_def(def_id)
	var u := Unit.new()
	u.id = _next_id
	_next_id += 1
	u.def_id = def_id
	u.name = d.name
	u.element = d.element
	u.owner = p
	u.pos = c
	u.hp = d.hp
	u.max_hp = d.hp
	u.power = d.power
	u.guard = d.guard
	u.move = d.get("move", Wicks.DEFAULT_MOVE)
	u.attack_range = d.get("range", Wicks.DEFAULT_RANGE)
	u.ability = d.get("ability", "")
	units.append(u)
	return u


# ---------------------------------------------------------------- posts

func can_plant_post(p: int, c: Vector2i) -> String:
	var r := _turn_check(p)
	if r != OK:
		return r
	if oil[p] < POST_COST:
		return R_NO_OIL
	if not HexGrid.in_board(c, RADIUS):
		return R_OFF_BOARD
	if posts.has(c):
		return R_HAS_POST
	if hearth_owner_at(c) != NONE:
		return R_RESERVED
	if light_owner(c) != p:
		return R_NOT_YOUR_LIGHT
	return OK


func plant_post(p: int, c: Vector2i) -> String:
	var r := can_plant_post(p, c)
	if r != OK:
		return r
	oil[p] -= POST_COST
	posts[c] = p
	_log("P%d plants a Post at %s" % [p, c])
	return OK


# ---------------------------------------------------------------- movement

## Tiles the unit can end on this turn -> path length. Excludes its own tile.
func reachable(u: Unit) -> Dictionary:
	var dist := {u.pos: 0}
	var frontier: Array[Vector2i] = [u.pos]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		if dist[c] >= u.move:
			continue
		for n in HexGrid.neighbors(c):
			if dist.has(n) or not HexGrid.in_board(n, RADIUS) or is_blocked(n):
				continue
			dist[n] = dist[c] + 1
			frontier.append(n)
	dist.erase(u.pos)
	return dist


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
	if u.ability == "kindle":
		kindled[dest] = p
	return OK


# ---------------------------------------------------------------- combat

## Damage = max(1, Power - Guard), x1.5 (floored) with element advantage.
## Power is reduced by 1 first if the attacker stands on a dark tile.
static func compute_damage(power: int, guard: int, atk_element: String, def_element: String, attacker_on_dark: bool) -> int:
	var p := power - (DARK_POWER_PENALTY if attacker_on_dark else 0)
	var d := maxi(1, p - guard)
	if Wicks.beats(atk_element, def_element):
		d = (d * 3) / 2
	return d


func damage_preview(u: Unit, target: Vector2i) -> int:
	var on_dark := light_owner(u.pos) == NONE
	var t := unit_at(target)
	if t != null:
		return compute_damage(u.power, t.guard, u.element, t.element, on_dark)
	return compute_damage(u.power, 0, u.element, "", on_dark)  # Hearths: Guard 0, no element


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
	var enemy_hearth := hearth_owner_at(target) == other(p)
	if not enemy_hearth and (t == null or t.owner == p):
		return R_NO_TARGET
	if HexGrid.distance(u.pos, target) > u.attack_range:
		return R_OUT_OF_RANGE
	return OK


func attack(p: int, unit_id: int, target: Vector2i) -> String:
	var r := can_attack(p, unit_id, target)
	if r != OK:
		return r
	var u := get_unit(unit_id)
	var dmg := damage_preview(u, target)
	u.attacked = true
	u.moved = true  # attacking ends the Wick's turn
	var t := unit_at(target)
	if t != null:
		t.hp -= dmg
		_log("%s hits %s for %d" % [u.name, t.name, dmg])
		if t.hp <= 0:
			units.erase(t)
			_log("%s is snuffed out" % t.name)
	else:
		var victim := other(p)
		hearth_hp[victim] = maxi(0, hearth_hp[victim] - dmg)
		_log("%s hits P%d Hearth for %d" % [u.name, victim, dmg])
		if hearth_hp[victim] == 0:
			_set_winner(p, "hearth")
	return OK


# ---------------------------------------------------------------- turns

func end_turn(p: int) -> String:
	var r := _turn_check(p)
	if r != OK:
		return r
	for u in units_of(p):
		if beacons.has(u.pos) and beacons[u.pos] != p:
			beacons[u.pos] = p
			_log("P%d claims the Beacon at %s" % [p, u.pos])
	current = other(p)
	turn += 1
	_start_turn()
	return OK


func _start_turn() -> void:
	oil[current] = mini(OIL_CAP, oil[current] + OIL_PER_TURN)
	for u in units_of(current):
		u.moved = false
		u.attacked = false
	if beacons_owned(current) == BEACON_TILES.size():
		_set_winner(current, "beacons")


func _set_winner(p: int, reason: String) -> void:
	if winner == NONE:
		winner = p
		win_reason = reason
		_log("P%d wins by %s" % [p, reason])


func _log(msg: String) -> void:
	events.append(msg)
