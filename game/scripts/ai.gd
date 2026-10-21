## Opponent AI. One scoring engine; behaviour switches on the stage's opponent_style through
## the STYLES parameter table below (all 10 styles in the bible, plus "balanced" for the player
## side in AI-vs-AI runs). It plays ONE activation at a time (initiative model) and uses ONLY
## GameState's legal-action API, the same calls the UI makes.
extends RefCounted

const GameState = preload("res://scripts/game_state.gd")
const Data = preload("res://scripts/data_loader.gd")

## w_symbol  pull toward the enemy Symbol (path distance)
## w_enemy   pull toward the nearest enemy monster
## w_node    pull toward capsule nodes we haven't activated;  w_relic toward relics we don't own
## w_terrain value of terrain stat bonuses (and high ground);  w_choke value of a bridge
## keep_range  prefer standing at exactly max range from the nearest enemy (kiting)
## hold / trigger  stay within `hold` steps of own Sigil until an enemy comes within `trigger` of it
##                 (released once the other side has nothing left to summon or field)
## deploy_max  summons per Sigil activation;  deploy_key  which stat summons first
## sym_bonus / kill_bonus / adv_bonus  target weights;  skill_bias  extra value for skills
## defend_hp  Defend (or heal/guard) below this HP fraction when an enemy is near
const BASE := {
	"w_symbol": 1.0, "w_enemy": 0.3, "w_node": 0.0, "w_relic": 0.0, "w_terrain": 0.3,
	"w_choke": 0.0, "keep_range": false, "hold": 0, "trigger": 0, "deploy_max": 2,
	"deploy_key": "attack", "sym_bonus": 10.0, "kill_bonus": 100.0, "adv_bonus": 0.0,
	"avoid_hazard": 6.0, "w_attack_pos": 3.0, "skill_bias": 0.0, "defend_hp": 0.3,
}
const STYLES := {
	"balanced": {},
	"defensive fortress": {"w_symbol": 0.4, "w_enemy": 0.6, "hold": 3, "trigger": 6, "deploy_key": "defense", "w_terrain": 0.6, "defend_hp": 0.45},
	"trap engineer": {"w_symbol": 0.5, "w_choke": 4.0, "hold": 5, "trigger": 5, "avoid_hazard": 12.0, "w_terrain": 0.4},
	"mobility specialist": {"w_symbol": 0.8, "w_node": 1.2, "w_relic": 1.0, "deploy_key": "move"},
	"terrain controller": {"w_symbol": 0.7, "w_terrain": 2.0, "w_node": 0.5},
	"summoner": {"w_symbol": 0.8, "deploy_max": 9, "deploy_key": "hp"},
	"counter-attacker": {"w_symbol": 0.3, "w_enemy": 1.2, "hold": 2, "trigger": 7, "kill_bonus": 150.0},
	"resource thief": {"w_symbol": 0.5, "w_node": 2.0, "w_relic": 2.0},
	"long-range sniper": {"w_symbol": 0.8, "keep_range": true, "deploy_key": "range", "w_terrain": 0.8},
	"status-effect strategist": {"w_symbol": 0.8, "adv_bonus": 15.0, "w_enemy": 0.6, "skill_bias": 8.0},
	"rush attacker": {"w_symbol": 2.0, "w_enemy": 0.1, "deploy_max": 3, "sym_bonus": 40.0, "deploy_key": "move", "avoid_hazard": 2.0, "defend_hp": 0.0},
}


static func style_names() -> Array:
	return STYLES.keys()


static func params(style: String) -> Dictionary:
	var p := BASE.duplicate()
	p.merge(STYLES.get(style, {}), true)
	return p


## Plays the active actor's whole activation for side p. Returns {"actions", "rejected"}.
static func take_activation(s: GameState, p: int, style: String = "balanced") -> Dictionary:
	var stats := {"actions": 0, "rejected": 0}
	if s.winner != GameState.NONE or s.current != p:
		return stats
	var P := params(style)
	if s.is_sigil_turn():
		_summon(s, p, P, stats)
		_do(s, p, {"type": "wait"}, stats)
		return stats
	var u := s.actor_unit()
	var acted := _best_action(s, p, u, P, stats)
	if not acted and s.get_unit(u.id) != null and s.actor_id == u.id:
		var moves := s.legal_moves(u)
		if not moves.is_empty():
			var threatened := _threatened(s, p, P)
			var best_tile: Vector2i = u.pos
			var best_score := _score_tile(s, p, u, u.pos, P, threatened)
			for c in moves:
				var sc := _score_tile(s, p, u, c, P, threatened)
				if sc > best_score:
					best_score = sc
					best_tile = c
			if best_tile != u.pos:
				_do(s, p, {"type": "move", "unit": u.id, "tile": best_tile}, stats)
		if s.winner == GameState.NONE and s.actor_id == u.id and s.get_unit(u.id) != null:
			acted = _best_action(s, p, u, P, stats)
	if s.winner == GameState.NONE and s.actor_id == u.id and s.current == p and s.get_unit(u.id) != null:
		var near := _nearest_enemy(s, p, u.pos) <= 4
		if near and float(u.hp) / u.max_hp < float(P.defend_hp):
			_do(s, p, {"type": "defend", "unit": u.id}, stats)
		else:
			_do(s, p, {"type": "wait"}, stats)
	return stats


## Plays activations for side p until it is the other side's turn (or the game ends).
static func take_turn(s: GameState, p: int, style: String = "balanced") -> Dictionary:
	var total := {"actions": 0, "rejected": 0}
	var guard := 0
	while s.winner == GameState.NONE and s.current == p and guard < 64:
		var r := take_activation(s, p, style)
		total.actions += r.actions
		total.rejected += r.rejected
		guard += 1
		if r.actions == 0:
			break
	return total


static func _do(s: GameState, p: int, action: Dictionary, stats: Dictionary) -> bool:
	if s.apply(p, action) == GameState.OK:
		stats.actions += 1
		return true
	stats.rejected += 1
	return false


static func _summon(s: GameState, p: int, P: Dictionary, stats: Dictionary) -> void:
	var key: String = P.deploy_key
	var field := s.distance_field(s.symbol_pos[GameState.other(p)])
	for i in int(P.deploy_max):
		var opts := s.legal_deploys(p)
		if opts.is_empty():
			return
		var best: Dictionary = {}
		var best_score := -INF
		for a in opts:
			var m: int = s.reserve[p].find(a.mon)
			var stat := int(Data.monster(a.mon).get(key, 0))
			var score: float = stat * 100.0 - float(field.get(a.tile, 99)) - m * 0.01
			if score > best_score:
				best_score = score
				best = a
		if not _do(s, p, best, stats):
			return


## Picks the best Attack or Skill available from where the unit stands. Returns true if it acted.
static func _best_action(s: GameState, p: int, u: GameState.Unit, P: Dictionary, stats: Dictionary) -> bool:
	var best: Dictionary = {}
	var best_score := 0.0
	for t in s.legal_attacks(u):
		var sc := _value_hit(s, u, t, 1.0, P)
		if sc > best_score:
			best_score = sc
			best = {"type": "attack", "unit": u.id, "tile": t}
	var sd := s.skill_def(u)
	var frac := float(u.hp) / u.max_hp
	for t in s.legal_skill_targets(u):
		var sc := 0.0
		match str(sd.type):
			"strike", "pull", "root":
				if float(sd.get("mult", 1.0)) > 0.0:
					sc = _value_hit(s, u, t, float(sd.get("mult", 1.0)), P)
				else:
					sc = 6.0
			"chain":
				sc = _value_hit(s, u, t, float(sd.mult), P) * 1.3
			"pulse":
				for e in s.units_of(GameState.other(p)):
					if GameState.manhattan(e.pos, u.pos) <= int(sd.radius):
						sc += _value_hit(s, u, e.pos, float(sd.mult), P)
			"mark":
				sc = 8.0 if s.unit_at(t) != null or int(sd.get("radius", 0)) > 0 else 0.0
			"heal":
				sc = 40.0 if frac < 0.6 else 0.0
			"guard", "veil":
				sc = 30.0 if frac < 0.5 and _nearest_enemy(s, p, u.pos) <= 3 else 0.0
			"ward":
				var a := s.unit_at(t)
				sc = 25.0 if a != null and float(a.hp) / a.max_hp < 0.5 else 0.0
			"blink":
				sc = 0.0  # positional; the AI leaves blinks to the player
		if sc > 0.0:
			sc += float(P.skill_bias)
		if sc > best_score:
			best_score = sc
			best = {"type": "skill", "unit": u.id, "tile": t}
	if best.is_empty():
		return false
	return _do(s, p, best, stats)


static func _value_hit(s: GameState, u: GameState.Unit, t: Vector2i, mult: float, P: Dictionary) -> float:
	var dmg := s.damage_preview(u, t, mult)
	var hit := s.hit_chance(u, t) / 100.0
	var score := float(dmg) * hit
	var e := s.unit_at(t)
	if e == null:
		score += float(P.sym_bonus)
		if dmg >= s.symbol_hp[GameState.other(u.owner)]:
			score += 1000.0 * hit
	else:
		if dmg >= e.hp:
			score += float(P.kill_bonus) * hit
		if GameState.beats(u.family, e.family):
			score += float(P.adv_bonus)
	return score


static func _nearest_enemy(s: GameState, p: int, c: Vector2i) -> int:
	var best := 99
	for e in s.units_of(GameState.other(p)):
		best = mini(best, GameState.manhattan(c, e.pos))
	return best


static func _nearest(c: Vector2i, pts: Array) -> int:
	var best := 99
	for q in pts:
		best = mini(best, GameState.manhattan(c, q))
	return best


## True when an enemy is near our Sigil, or the enemy has nothing left (so holding is pointless).
static func _threatened(s: GameState, p: int, P: Dictionary) -> bool:
	var foe := GameState.other(p)
	if s.units_of(foe).is_empty() and s.reserve[foe].is_empty():
		return true
	var own: Vector2i = s.symbol_pos[p]
	for e in s.units_of(foe):
		if GameState.manhattan(e.pos, own) <= int(P.trigger):
			return true
	return false


static func _score_tile(s: GameState, p: int, u: GameState.Unit, c: Vector2i, P: Dictionary, threatened: bool) -> float:
	var foe := GameState.other(p)
	var score := 0.0
	var fs := s.distance_field(s.symbol_pos[foe])
	score -= float(P.w_symbol) * float(fs.get(c, 40))
	var enemies: Array = []
	for e in s.units_of(foe):
		enemies.append(e.pos)
	if not enemies.is_empty():
		var de := _nearest(c, enemies)
		score -= float(P.w_enemy) * de
		if P.keep_range:
			score -= 1.5 * absi(de - s.range_of(u, c))
	if float(P.w_node) > 0.0:
		var open_nodes: Array = []
		for n in s.nodes:
			if s.nodes[n] != p:
				open_nodes.append(n)
		if not open_nodes.is_empty():
			score -= float(P.w_node) * _nearest(c, open_nodes)
	var w_relic := float(P.w_relic) + (1.0 if s.relic_win else 0.0)
	if w_relic > 0.0:
		var open_relics: Array = []
		for n in s.relics:
			if s.relics[n] != p:
				open_relics.append(n)
		if not open_relics.is_empty():
			score -= w_relic * _nearest(c, open_relics)
	var td := s.tile_def(c)
	score += float(P.w_terrain) * float(s.attack_of(u, c) - u.attack + s.defense_of(u, c) - u.defense + int(td.get("dmg_pct", 0)) / 6)
	if s.tile_type(c) == "bridge":
		score += float(P.w_choke)
	if int(td.get("start_damage", 0)) > 0 or int(td.get("start_damage_per_tier", 0)) > 0:
		score -= float(P.avoid_hazard)
	if int(P.hold) > 0 and not threatened:
		var home := s.distance_field(s.symbol_pos[p])
		var dh := int(home.get(c, 40))
		if dh > int(P.hold):
			score -= 4.0 * (dh - int(P.hold))
	var targets: Array[Vector2i] = [s.symbol_pos[foe]]
	for e in s.units_of(foe):
		targets.append(e.pos)
	for t in targets:
		if GameState.manhattan(c, t) <= s.range_of(u, c) and s.has_los(c, t):
			score += float(P.w_attack_pos)
			break
	return score
