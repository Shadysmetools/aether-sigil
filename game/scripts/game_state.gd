## Aether Sigil battle rules. Pure logic (RefCounted, no nodes, no drawing): runs headless.
## Initiative model (battle-screen design): every round, each actor (both Sigils, then every
## monster on the board by initiative) gets one activation. A monster may Move once and then
## take ONE action: Attack, Skill, Defend or Wait (each ends the activation). A Sigil's
## activation is the commander's: Capsule-summon squad monsters, then Wait.
## Every mutating action has a can_* check returning a reason code (OK on success). The UI and
## the AI act ONLY through legal_* / can_* / apply(). All numbers come from data/game_rules.json.
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
const R_NOT_ACTIVE := "not_the_active_unit"
const R_NOT_SIGIL_TURN := "only_on_your_sigil_activation"
const R_NOT_IN_RESERVE := "not_in_reserve"
const R_NO_AP := "not_enough_ap"
const R_NO_SUMMONS := "no_summons_left"
const R_BAD_DEPLOY_TILE := "not_a_deploy_tile"
const R_NOT_YOUR_UNIT := "not_your_unit"
const R_ALREADY_MOVED := "already_moved"
const R_ALREADY_ACTED := "already_acted"
const R_UNREACHABLE := "unreachable"
const R_NO_TARGET := "no_valid_target"
const R_OUT_OF_RANGE := "out_of_range"
const R_NO_LOS := "no_line_of_sight"
const R_COOLDOWN := "skill_on_cooldown"
const R_NO_SKILL := "no_skill"
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
	var attacked := false        ## action taken this activation
	var defending := false
	var defend_mult := 1.0
	var reflect := 0
	var marked := 1.0            ## next hit taken x this
	var rooted := false          ## cannot move on its next activation
	var rooted_now := false
	var veiled := false
	var move_mod := 0            ## this activation's terrain move penalty
	var skill_cd := 0
	var once_used := false
	var dormant := false         ## ruins statue until its first activation
	var level := 1
	var skill_tier := 0          ## evolutions (and fusion) upgrade the Skill (progression.json)
	var secondary_family := ""   ## fused monsters: second element's affinity


var stage: Dictionary = {}
var stage_id := ""
var grid: Array = []                 ## [y][x] effective tile type (objectives overlay the map_grid)
var symbol_pos: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(-1, -1)]
var symbol_hp: Array[int] = [0, 0]
var symbol_max := 0
var symbol_defense := 0
var spawn_tiles: Array = [[], []]    ## per side: Array of Vector2i (walkable, not a Symbol)
var nodes: Dictionary = {}           ## capsule node Vector2i -> side that activated it, or NONE
var relics: Dictionary = {}          ## relic Vector2i -> owner or NONE
var portals: Array[Vector2i] = []
var active_portal: Vector2i = Vector2i(-1, -1)
var units: Array[Unit] = []
var reserve: Array = [[], []]        ## per side: monster ids not yet summoned
var order: Array[int] = []           ## this round's actor ids (Sigils are -1 / -2)
var order_index := 0
var actor_id := -1
var current := PLAYER                ## side of the active actor
var round_num := 1
var ap: Array[int] = [0, 0]
var summons_left := 0
var momentum_until: Array[int] = [0, 0]  ## KO move bonus applies while round_num <= this
var kos: Array[int] = [0, 0]         ## monsters each side has LOST
var rule: Dictionary = {}            ## effects of this stage's special_rule
var relic_win := false
var dormant_stage := false
var hazard_tier := 1
var winner := NONE
var win_reason := ""
var events: Array[String] = []
var rng := RandomNumberGenerator.new()
var force_hit := -1                  ## tests: 1 = always hit, 0 = always miss, -1 = roll
var custom: Dictionary = {}          ## player-owned monster records by uid (progression.battle_record)
var deployed: Dictionary = {}        ## player monster id/uid -> true once summoned (for XP)
var ko_by: Dictionary = {}           ## player monster id/uid -> knockouts it scored
var _next_id := 1
var _field_cache: Dictionary = {}


## Builds a battle for a stage. squad defaults to the default squad of 4.
func setup(p_stage_id: String, squad: Array = [], seed_value: int = -1, p_custom: Dictionary = {}) -> bool:
	stage = Data.stage(p_stage_id)
	if stage.is_empty():
		push_error("game_state: unknown stage %s" % p_stage_id)
		return false
	stage_id = p_stage_id
	custom = p_custom
	deployed = {}
	ko_by = {}
	var R := Data.rules()
	rng.seed = hash(p_stage_id) if seed_value < 0 else seed_value
	grid = []
	for row in stage.get("map_grid", []):
		grid.append(Array(row).duplicate())
	# map_grid is the source of truth (game_rules.json map_policy): Symbols come from their tiles;
	# a map that paints no Symbol gets it on its first spawn tile (7 boss maps).
	symbol_pos = [Vector2i(-1, -1), Vector2i(-1, -1)]
	for side in 2:
		var sym_type := "player_symbol" if side == PLAYER else "enemy_symbol"
		symbol_pos[side] = _find_tile(sym_type)
		if symbol_pos[side] == Vector2i(-1, -1):
			var first := _find_tile("player_spawn" if side == PLAYER else "enemy_spawn")
			if first != Vector2i(-1, -1):
				grid[first.y][first.x] = sym_type
				symbol_pos[side] = first
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
		var cands: Array[Vector2i] = []
		var spawn_type := "player_spawn" if side == PLAYER else "enemy_spawn"
		for y in SIZE:
			for x in SIZE:
				if grid[y][x] == spawn_type:
					cands.append(Vector2i(x, y))
		if cands.is_empty():  # no painted spawns: fall back to the JSON list
			for a in stage.get("player_spawns" if side == PLAYER else "enemy_spawns", []):
				cands.append(Data.vec(a))
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
	var team: Array = squad if not squad.is_empty() else Data.default_squad()
	reserve = [team.duplicate(), Array(stage.get("enemy_roster", [])).duplicate()]
	ap = [int(R.ap.start), int(R.ap.start)]
	momentum_until = [0, 0]
	kos = [0, 0]
	winner = NONE
	win_reason = ""
	events = []
	_next_id = 1
	_field_cache = {}
	var D: Dictionary = R.dormant_start
	dormant_stage = Array(D.terrains).has(str(stage.get("terrain", ""))) or Array(D.stage_ids).has(p_stage_id)
	if dormant_stage:
		for i in mini(int(D.statues), spawn_tiles[ENEMY].size()):
			if reserve[ENEMY].is_empty():
				break
			var u := place_unit(ENEMY, reserve[ENEMY].pop_front(), spawn_tiles[ENEMY][i])
			u.dormant = true
	round_num = 1
	_roll_portal()
	_new_round()
	_begin_activation()
	return true


static func other(p: int) -> int:
	return 1 - p


static func sigil_id(side: int) -> int:
	return -1 - side


static func is_sigil(id: int) -> bool:
	return id < 0


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


func blocks_los(c: Vector2i) -> bool:
	return bool(tile_def(c).get("blocks_los", false))


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


## Line of sight between tile centres: clear unless a blocks_los tile (obstacle, ruins) lies
## strictly between. Traced both ways and both must be clear, so it is symmetric by construction.
func has_los(a: Vector2i, b: Vector2i) -> bool:
	if manhattan(a, b) <= 1:
		return true
	return _ray_clear(a, b) and _ray_clear(b, a)


func _ray_clear(a: Vector2i, b: Vector2i) -> bool:
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y)) * 4
	for i in range(1, steps):
		var t := float(i) / steps
		var c := Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)))
		if c != a and c != b and blocks_los(c):
			return false
	return true


# ---------------------------------------------------------------- initiative

func initiative(u: Unit) -> int:
	var I: Dictionary = Data.rules().initiative
	return u.move * int(I.move_weight) + u.attack_range


## Both Sigils first, then monsters by initiative; ties interleave sides (player first), then id.
func _new_round() -> void:
	var by_score := {}
	for u in units:
		var sc := initiative(u)
		if not by_score.has(sc):
			by_score[sc] = [[], []]
		by_score[sc][u.owner].append(u.id)
	var scores := by_score.keys()
	scores.sort()
	scores.reverse()
	order = [sigil_id(PLAYER), sigil_id(ENEMY)]
	for sc in scores:
		var pl: Array = by_score[sc][PLAYER]
		var en: Array = by_score[sc][ENEMY]
		pl.sort()
		en.sort()
		for i in maxi(pl.size(), en.size()):
			if i < pl.size():
				order.append(pl[i])
			if i < en.size():
				order.append(en[i])
	order_index = 0


func _actor_valid(id: int) -> bool:
	return is_sigil(id) or get_unit(id) != null


func actor_unit() -> Unit:
	return null if is_sigil(actor_id) else get_unit(actor_id)


func is_sigil_turn() -> bool:
	return is_sigil(actor_id)


## Upcoming actor ids: rest of this round, then next round as it stands now.
func order_preview(count: int) -> Array:
	var out := []
	for i in range(order_index, order.size()):
		if _actor_valid(order[i]):
			out.append(order[i])
	if out.size() < count:
		var saved_order := order.duplicate()
		var saved_index := order_index
		_new_round()
		for id in order:
			out.append(id)
		order = saved_order
		order_index = saved_index
	return out.slice(0, count)


func _begin_activation() -> void:
	if winner != NONE:
		return
	actor_id = order[order_index]
	current = PLAYER if actor_id == sigil_id(PLAYER) else (ENEMY if actor_id == sigil_id(ENEMY) else get_unit(actor_id).owner)
	if is_sigil(actor_id):
		var A: Dictionary = Data.rules().ap
		ap[current] = mini(int(A.cap), ap[current] + int(A.per_sigil_activation))
		summons_left = int(Data.rules().summon.per_sigil_activation)
		return
	var u := get_unit(actor_id)
	u.dormant = false
	u.moved = false
	u.attacked = false
	u.defending = false
	u.reflect = 0
	u.rooted_now = u.rooted
	u.rooted = false
	u.skill_cd = maxi(0, u.skill_cd - 1)
	var td := tile_def(u.pos)
	u.move_mod = -int(td.get("move_penalty", 0))
	var dmg := int(td.get("start_damage", 0)) + int(td.get("start_damage_per_tier", 0)) * hazard_tier
	if tile_type(u.pos) == "water" and u.family == "Water" and Data.rules().get("water_family_immune", false):
		dmg = 0
	if dmg > 0:
		u.hp -= dmg
		_log("%s takes %d from %s" % [u.name, dmg, tile_type(u.pos)])
		if u.hp <= 0:
			_knock_out(u)
			_end_activation()
			return
	if nodes.has(u.pos):
		if nodes[u.pos] != u.owner:
			nodes[u.pos] = u.owner
			_log("P%d activates the capsule node at %s" % [u.owner, u.pos])
			if relic_win and relic_progress(u.owner) >= int(Data.rules().relics_to_win):
				_set_winner(u.owner, "relics")
				return
		if u.hp < u.max_hp:
			var heal := maxi(1, u.max_hp * int(Data.rules().recharge_pct) / 100)
			u.hp = mini(u.max_hp, u.hp + heal)
			_log("%s recharges %d HP" % [u.name, heal])


func _end_activation() -> void:
	var u := actor_unit()
	if u != null:
		u.rooted_now = false
		if relics.has(u.pos) and relics[u.pos] != u.owner:
			relics[u.pos] = u.owner
			_log("P%d secures the relic at %s" % [u.owner, u.pos])
			if relic_win and relic_progress(u.owner) >= int(Data.rules().relics_to_win):
				_set_winner(u.owner, "relics")
	if winner != NONE:
		return
	order_index += 1
	while order_index < order.size() and not _actor_valid(order[order_index]):
		order_index += 1
	if order_index >= order.size():
		round_num += 1
		_roll_portal()
		_new_round()
	_begin_activation()


## Makes `id` act next (tests and tools): it is placed at the front of the remaining order.
func activate(id: int) -> void:
	var rest := order.slice(order_index).filter(func(x): return x != id)
	order.assign([id] + rest)
	order_index = 0
	_begin_activation()


# ---------------------------------------------------------------- stats

func terrain_mult() -> int:
	return int(rule.get("terrain_mult", 1))


func _family_match(u: Unit, c: Vector2i) -> bool:
	return Array(tile_def(c).get("family", [])).has(u.family)


func attack_of(u: Unit, c: Vector2i) -> int:
	var bonus := int(Data.rules().terrain_bonus.family_atk) if _family_match(u, c) else 0
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


## High-ground range bonus is NOT doubled by 'Terrain bonuses are doubled'.
func range_of(u: Unit, c: Vector2i) -> int:
	return u.attack_range + int(tile_def(c).get("range_bonus", 0))


func move_of(u: Unit) -> int:
	if u.rooted_now:
		return 0
	var bonus := int(rule.get("ko_move_bonus", 0)) if round_num <= momentum_until[u.owner] else 0
	return maxi(0, u.move + u.move_mod + bonus)


## Damage multiplier from where the attacker stands (high ground +30%, doubled by the rule).
func position_mult(u: Unit) -> float:
	return 1.0 + float(tile_def(u.pos).get("dmg_pct", 0)) * terrain_mult() / 100.0


func hit_chance(u: Unit, target: Vector2i) -> int:
	var A: Dictionary = Data.rules().accuracy
	var c := int(A.base) + int(tile_def(u.pos).get("acc_bonus", 0)) * terrain_mult()
	var t := unit_at(target)
	if t != null and t.veiled:
		c -= int(A.veil_penalty)
	return clampi(c, int(A.min), int(A.max))


static func beats(a_family: String, d_family: String) -> bool:
	return Array(Data.rules().element_chart.get(a_family, [])).has(d_family)


## max(1, round(1.5 * atk^2 / (atk + def))) x mult x element (1.25 / 0.8), rounded, min 1.
static func compute_damage(atk: int, def: int, a_family: String, d_family: String, mult: float = 1.0) -> int:
	var dm: Dictionary = Data.rules().damage
	var a := float(maxi(0, atk))
	var base := maxi(1, roundi(float(dm.scale) * a * a / maxf(1.0, a + float(maxi(0, def)))))
	var d := float(base) * mult
	if d_family != "" and beats(a_family, d_family):
		d *= float(dm.advantage_mult)
	elif d_family != "" and beats(d_family, a_family):
		d *= float(dm.disadvantage_mult)
	return maxi(1, roundi(d))


func damage_preview(u: Unit, target: Vector2i, skill_mult: float = 1.0) -> int:
	var mult := skill_mult * position_mult(u)
	var t := unit_at(target)
	if t != null:
		mult *= t.marked
		# Fusion secondary affinity: a small bonus where the second element has the advantage.
		if u.secondary_family != "" and beats(u.secondary_family, t.family) and not beats(u.family, t.family):
			mult *= float(Data.progression().fusion.secondary_affinity_mult)
		if t.defending:
			mult *= t.defend_mult
		return compute_damage(attack_of(u, u.pos), defense_of(t, t.pos), u.family, t.family, mult)
	return compute_damage(attack_of(u, u.pos), symbol_defense, u.family, "", mult)


# ---------------------------------------------------------------- activation checks

func _turn_check(p: int) -> String:
	if winner != NONE:
		return R_GAME_OVER
	if p != current:
		return R_NOT_YOUR_TURN
	return OK


func _unit_check(p: int, unit_id: int) -> String:
	var r := _turn_check(p)
	if r != OK:
		return r
	var u := get_unit(unit_id)
	if u == null or u.owner != p:
		return R_NOT_YOUR_UNIT
	if unit_id != actor_id:
		return R_NOT_ACTIVE
	if u.attacked:
		return R_ALREADY_ACTED
	return OK


# ---------------------------------------------------------------- capsule summon (Sigil)

func deploy_cost() -> int:
	return int(rule.get("deploy_ap_cost", 0))


## Own spawn tiles plus capsule nodes this side has activated, that are free.
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
	if actor_id != sigil_id(p):
		return R_NOT_SIGIL_TURN
	if not reserve[p].has(mon_id):
		return R_NOT_IN_RESERVE
	if summons_left <= 0:
		return R_NO_SUMMONS
	if ap[p] < deploy_cost():
		return R_NO_AP
	if not deploy_tiles(p).has(c):
		return R_BAD_DEPLOY_TILE
	return OK


## Capsule summon. The monster joins the turn order next round.
func deploy(p: int, mon_id: String, c: Vector2i) -> String:
	var r := can_deploy(p, mon_id, c)
	if r != OK:
		return r
	ap[p] -= deploy_cost()
	summons_left -= 1
	reserve[p].erase(mon_id)
	var u := place_unit(p, mon_id, c)
	if p == PLAYER:
		deployed[mon_id] = true
	_log("P%d summons %s at %s" % [p, u.name, c])
	return OK


## Puts a monster on the board with NO rule checks (tests, tutorials, tools).
func place_unit(p: int, mon_id: String, c: Vector2i) -> Unit:
	var d: Dictionary = custom[mon_id] if custom.has(mon_id) else Data.monster(mon_id)
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
	u.level = int(d.get("level", 1))
	u.skill_tier = int(d.get("skill_tier", 0))
	u.secondary_family = str(d.get("secondary_family", ""))
	if p == ENEMY:
		var f := enemy_scale()
		u.hp = roundi(u.hp * f)
		u.max_hp = u.hp
		u.attack = roundi(u.attack * f)
		u.defense = roundi(u.defense * f)
	units.append(u)
	return u


## Difficulty curve (game_rules.json difficulty): enemy stats x (1 + pct/100 x (tower - 1) + tower_adjust_pct/100).
func enemy_scale() -> float:
	var pct := float(Data.rules().get("difficulty", {}).get("enemy_stat_pct_per_tower", 0))
	var tower := maxi(1, int(str(stage.get("tower_id", "1"))))
	var adj := float(Data.rules().get("difficulty", {}).get("tower_adjust_pct", {}).get(str(stage.get("tower_id", "")), 0))
	return 1.0 + pct / 100.0 * (tower - 1) + adj / 100.0


# ---------------------------------------------------------------- Move

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
	var r := _unit_check(p, unit_id)
	if r != OK:
		return r
	var u := get_unit(unit_id)
	if u.moved:
		return R_ALREADY_MOVED
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


# ---------------------------------------------------------------- Attack

## Target check shared by Attack and targeted skills. Symbols count only if allow_symbol.
func _target_check(u: Unit, target: Vector2i, allow_symbol: bool) -> String:
	var t := unit_at(target)
	var enemy_symbol := allow_symbol and symbol_owner_at(target) == other(u.owner)
	if not enemy_symbol and (t == null or t.owner == u.owner):
		return R_NO_TARGET
	if manhattan(u.pos, target) > range_of(u, u.pos):
		return R_OUT_OF_RANGE
	if not has_los(u.pos, target):
		return R_NO_LOS
	return OK


func can_attack(p: int, unit_id: int, target: Vector2i) -> String:
	var r := _unit_check(p, unit_id)
	if r != OK:
		return r
	return _target_check(get_unit(unit_id), target, true)


func attack(p: int, unit_id: int, target: Vector2i) -> String:
	var r := can_attack(p, unit_id, target)
	if r != OK:
		return r
	var u := get_unit(unit_id)
	_hit(u, target, 1.0)
	_finish(u)
	return OK


func _roll(chance: int) -> bool:
	if force_hit >= 0:
		return force_hit == 1
	return rng.randf() * 100.0 < float(chance)


## One hit: accuracy roll, damage, mark consumed, reflect, KO. Returns damage dealt (-1 = miss).
func _hit(u: Unit, target: Vector2i, mult: float) -> int:
	u.veiled = false
	if not _roll(hit_chance(u, target)):
		_log("%s misses" % u.name)
		return -1
	var dmg := damage_preview(u, target, mult)
	var t := unit_at(target)
	if t != null:
		t.hp -= dmg
		t.marked = 1.0
		_log("%s hits %s for %d" % [u.name, t.name, dmg])
		if t.defending and t.reflect > 0 and u.hp > 0:
			var back := maxi(1, dmg * t.reflect / 100)
			u.hp -= back
			_log("%s reflects %d" % [t.name, back])
			if u.hp <= 0:
				_knock_out(u)
		if t.hp <= 0:
			_knock_out(t)
			if u.owner == PLAYER:
				ko_by[u.mon_id] = int(ko_by.get(u.mon_id, 0)) + 1
			if rule.has("ko_move_bonus"):
				momentum_until[u.owner] = round_num + 1
	else:
		var victim := other(u.owner)
		symbol_hp[victim] = maxi(0, symbol_hp[victim] - dmg)
		_log("%s hits P%d Symbol for %d" % [u.name, victim, dmg])
		if symbol_hp[victim] == 0:
			_set_winner(u.owner, "symbol")
	return dmg


func _knock_out(t: Unit) -> void:
	units.erase(t)
	kos[t.owner] += 1
	_log("%s is knocked out" % t.name)


## Ends the active unit's activation after an action (unless the game ended or it died).
func _finish(u: Unit) -> void:
	u.attacked = true
	u.moved = true
	if winner == NONE:
		_end_activation()


# ---------------------------------------------------------------- Skill

func skill_def(u: Unit) -> Dictionary:
	return Data.ability(u.ability)


func can_skill(p: int, unit_id: int, target: Vector2i) -> String:
	var r := _unit_check(p, unit_id)
	if r != OK:
		return r
	var u := get_unit(unit_id)
	var sd := skill_def(u)
	if sd.is_empty():
		return R_NO_SKILL
	if u.skill_cd > 0 or (sd.get("once", false) and u.once_used):
		return R_COOLDOWN
	match str(sd.type):
		"strike":
			return _target_check(u, target, true)
		"pull", "chain", "root":
			return _target_check(u, target, false)
		"mark":
			if int(sd.get("radius", 0)) > 0:
				return OK if target == u.pos else R_NO_TARGET
			return _target_check(u, target, false)
		"pulse", "heal", "guard", "veil":
			return OK if target == u.pos else R_NO_TARGET
		"ward":
			var a := unit_at(target)
			return OK if a != null and a.owner == p and a != u and manhattan(a.pos, u.pos) == 1 else R_NO_TARGET
		"blink":
			if target == u.pos or not is_walkable(target) or unit_at(target) != null:
				return R_NO_TARGET
			if sd.get("nodes_only", false) and not ["capsule_node", "relic", "warp_gate"].has(tile_type(target)):
				return R_NO_TARGET
			return OK if manhattan(u.pos, target) <= int(sd.get("range", 1)) else R_OUT_OF_RANGE
	return R_NO_SKILL


func skill(p: int, unit_id: int, target: Vector2i) -> String:
	var r := can_skill(p, unit_id, target)
	if r != OK:
		return r
	var u := get_unit(unit_id)
	var sd := skill_def(u)
	var up: Dictionary = Data.progression().evolution.skill_upgrade
	var mult := float(sd.get("mult", 1.0)) * (1.0 + float(up.mult_bonus) * u.skill_tier)
	_log("%s uses %s" % [u.name, u.ability])
	match str(sd.type):
		"strike":
			if sd.has("portal_mult") and ["warp_gate", "hazard"].has(tile_type(target)):
				mult = float(sd.portal_mult) * (1.0 + float(up.mult_bonus) * u.skill_tier)
			_hit(u, target, mult)
		"pull":
			var t := unit_at(target)
			if _hit(u, target, mult) >= 0 and t.hp > 0:
				var step := Vector2i(signi(u.pos.x - t.pos.x), 0) if absi(u.pos.x - t.pos.x) >= absi(u.pos.y - t.pos.y) else Vector2i(0, signi(u.pos.y - t.pos.y))
				var dest := t.pos + step
				if is_walkable(dest) and unit_at(dest) == null:
					t.pos = dest
		"chain":
			if _hit(u, target, mult) >= 0:
				var best: Unit = null
				for e in units_of(other(u.owner)):
					if e.pos != target and manhattan(e.pos, target) <= int(sd.radius) and (best == null or manhattan(e.pos, target) < manhattan(best.pos, target)):
						best = e
				if best != null and u.hp > 0:
					_hit(u, best.pos, float(sd.chain_mult))
		"mark":
			var radius := int(sd.get("radius", 0))
			for e in units_of(other(u.owner)):
				if (radius == 0 and e.pos == target) or (radius > 0 and manhattan(e.pos, u.pos) <= radius):
					e.marked = mult
		"root":
			var t := unit_at(target)
			var landed := true
			if mult > 0.0:
				landed = _hit(u, target, mult) >= 0
			if landed and t.hp > 0:
				t.rooted = true
		"pulse":
			for e in units_of(other(u.owner)):
				if manhattan(e.pos, u.pos) <= int(sd.radius) and u.hp > 0:
					_hit(u, e.pos, mult)
		"heal":
			var amount := u.max_hp * (int(sd.pct) + int(up.heal_pct_bonus) * u.skill_tier) / 100
			if Array(tile_def(u.pos).get("family", [])).has("Wood"):
				amount *= int(sd.get("nature_mult", 1))
			u.hp = mini(u.max_hp, u.hp + amount)
		"guard":
			u.defending = true
			u.defend_mult = maxf(0.2, float(sd.get("mult", 1.0)) - float(up.guard_mult_cut) * u.skill_tier)
			u.reflect = int(sd.get("reflect", 0))
		"ward":
			var a := unit_at(target)
			a.defending = true
			a.defend_mult = float(Data.rules().defend.mult)
		"blink":
			u.pos = target
		"veil":
			u.veiled = true
	u.skill_cd = maxi(1, int(Data.rules().skill.cooldown) - int(up.cooldown_cut) * u.skill_tier) + 1  # +1: ticks down at its next activation start
	if sd.get("once", false):
		u.once_used = true
	if get_unit(u.id) != null:
		_finish(u)
	elif winner == NONE:
		_end_activation()
	return OK


# ---------------------------------------------------------------- Defend / Wait

func can_defend(p: int, unit_id: int) -> String:
	return _unit_check(p, unit_id)


func defend(p: int, unit_id: int) -> String:
	var r := can_defend(p, unit_id)
	if r != OK:
		return r
	var u := get_unit(unit_id)
	u.defending = true
	u.defend_mult = float(Data.rules().defend.mult)
	u.reflect = 0
	_log("%s defends" % u.name)
	_finish(u)
	return OK


## Ends the active actor's activation (a monster's Wait, or the Sigil finishing its summons).
func wait(p: int) -> String:
	var r := _turn_check(p)
	if r != OK:
		return r
	var u := actor_unit()
	if u != null:
		u.attacked = true
		u.moved = true
	_end_activation()
	return OK


func relics_owned(p: int) -> int:
	var n := 0
	for c in relics:
		if relics[c] == p:
			n += 1
	return n


## Relic nodes held toward 'secure 3 relic nodes': relics, plus activated capsule nodes
## (map_policy.relic_counts_capsule_nodes; every relic stage paints only 1 relic).
func relic_progress(p: int) -> int:
	var n := relics_owned(p)
	if Data.rules().get("map_policy", {}).get("relic_counts_capsule_nodes", false):
		n += nodes_activated(p)
	return n


func nodes_activated(p: int) -> int:
	var n := 0
	for c in nodes:
		if nodes[c] == p:
			n += 1
	return n


func _set_winner(p: int, reason: String) -> void:
	if winner == NONE:
		winner = p
		win_reason = reason
		_log("P%d wins by %s" % [p, reason])


func _log(msg: String) -> void:
	events.append(msg)


# ---------------------------------------------------------------- objectives

## Objective list for the HUD: {text, kind: win|loss|bonus, done, progress}.
func objectives() -> Array:
	var O: Dictionary = Data.rules().objectives
	var out := []
	var primary := str(O.primary_symbol)
	var prog := "%d/%d" % [symbol_max - symbol_hp[ENEMY], symbol_max]
	if relic_win:
		primary += " " + str(O.primary_relics) % int(Data.rules().relics_to_win)
		prog += ", relic nodes %d/%d" % [relic_progress(PLAYER), int(Data.rules().relics_to_win)]
	out.append({"text": primary, "kind": "win", "done": winner == PLAYER, "progress": prog})
	out.append({"text": str(O.protect), "kind": "loss", "done": symbol_hp[PLAYER] > 0, "progress": "%d/%d" % [symbol_hp[PLAYER], symbol_max]})
	var left: int = units_of(ENEMY).size() + reserve[ENEMY].size()
	out.append({"text": str(O.defeat_all), "kind": "bonus", "done": left == 0, "progress": "%d left" % left})
	if not nodes.is_empty():
		out.append({"text": str(O.capsule_nodes), "kind": "bonus", "done": nodes_activated(PLAYER) == nodes.size(), "progress": "%d/%d" % [nodes_activated(PLAYER), nodes.size()]})
	if not relics.is_empty():
		out.append({"text": str(O.golden_relic), "kind": "bonus", "done": relics_owned(PLAYER) > 0, "progress": "%d/%d" % [relics_owned(PLAYER), relics.size()]})
	return out


# ---------------------------------------------------------------- legal-action API (UI + AI)

func legal_deploys(p: int) -> Array:
	var out := []
	if _turn_check(p) != OK or actor_id != sigil_id(p) or summons_left <= 0 or ap[p] < deploy_cost():
		return out
	var tiles := deploy_tiles(p)
	for mon in reserve[p]:
		for c in tiles:
			out.append({"type": "deploy", "mon": mon, "tile": c})
	return out


func legal_moves(u: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if u == null or _unit_check(u.owner, u.id) != OK or u.moved:
		return out
	for c in reachable(u):
		out.append(c)
	return out


func legal_attacks(u: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if u == null or _unit_check(u.owner, u.id) != OK:
		return out
	var targets: Array[Vector2i] = [symbol_pos[other(u.owner)]]
	for e in units_of(other(u.owner)):
		targets.append(e.pos)
	for t in targets:
		if can_attack(u.owner, u.id, t) == OK:
			out.append(t)
	return out


func legal_skill_targets(u: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if u == null or _unit_check(u.owner, u.id) != OK or skill_def(u).is_empty():
		return out
	var sd := skill_def(u)
	var cands: Array[Vector2i] = [u.pos]
	match str(sd.type):
		"strike":
			cands.append(symbol_pos[other(u.owner)])
			for e in units_of(other(u.owner)):
				cands.append(e.pos)
		"pull", "chain", "root", "mark":
			for e in units_of(other(u.owner)):
				cands.append(e.pos)
		"ward":
			for d in DIRS:
				cands.append(u.pos + d)
		"blink":
			var rng_max := mini(int(sd.get("range", 1)), 2 * SIZE)
			for y in SIZE:
				for x in SIZE:
					var c := Vector2i(x, y)
					if manhattan(c, u.pos) <= rng_max:
						cands.append(c)
	for c in cands:
		if not out.has(c) and can_skill(u.owner, u.id, c) == OK:
			out.append(c)
	return out


## Every legal action for the active actor of side p.
func legal_actions(p: int) -> Array:
	if _turn_check(p) != OK:
		return []
	var out := []
	if is_sigil(actor_id):
		out = legal_deploys(p)
	else:
		var u := actor_unit()
		for c in legal_moves(u):
			out.append({"type": "move", "unit": u.id, "tile": c})
		for c in legal_attacks(u):
			out.append({"type": "attack", "unit": u.id, "tile": c})
		for c in legal_skill_targets(u):
			out.append({"type": "skill", "unit": u.id, "tile": c})
		if can_defend(p, u.id) == OK:
			out.append({"type": "defend", "unit": u.id})
	out.append({"type": "wait"})
	return out


func apply(p: int, a: Dictionary) -> String:
	match str(a.get("type", "")):
		"deploy": return deploy(p, str(a.mon), a.tile)
		"move": return move_unit(p, int(a.unit), a.tile)
		"attack": return attack(p, int(a.unit), a.tile)
		"skill": return skill(p, int(a.unit), a.tile)
		"defend": return defend(p, int(a.unit))
		"wait", "end": return wait(p)
	return R_BAD_ACTION
