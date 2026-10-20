## Opponent AI. One scoring engine; behaviour switches on the stage's opponent_style through
## the STYLES parameter table below (all 10 styles that occur in the bible, plus "balanced"
## for the player side in AI-vs-AI runs). Uses ONLY GameState's legal-action API, the same
## calls the UI makes, so it can never do anything a human could not.
extends RefCounted

const GameState = preload("res://scripts/game_state.gd")
const Data = preload("res://scripts/data_loader.gd")

## w_symbol  pull toward the enemy Symbol (path distance)
## w_enemy   pull toward the nearest enemy monster
## w_node    pull toward capsule nodes we don't own;  w_relic toward relics we don't own
## w_terrain value of terrain/elevation stat bonuses;  w_choke value of standing on a bridge
## keep_range  prefer standing at exactly max range from the nearest enemy (kiting)
## hold / trigger  stay within `hold` steps of own Symbol until an enemy comes within `trigger` of it
## deploy_max  monsters deployed per turn;  deploy_key  which roster stat deploys first
## sym_bonus / kill_bonus / adv_bonus  target-choice weights;  avoid_hazard  penalty for hazard tiles
const BASE := {
	"w_symbol": 1.0, "w_enemy": 0.3, "w_node": 0.0, "w_relic": 0.0, "w_terrain": 0.3,
	"w_choke": 0.0, "keep_range": false, "hold": 0, "trigger": 0, "deploy_max": 2,
	"deploy_key": "attack", "sym_bonus": 10.0, "kill_bonus": 100.0, "adv_bonus": 0.0,
	"avoid_hazard": 6.0, "w_attack_pos": 3.0,
}
const STYLES := {
	"balanced": {},
	"defensive fortress": {"w_symbol": 0.4, "w_enemy": 0.6, "hold": 3, "trigger": 6, "deploy_key": "defense", "w_terrain": 0.6},
	"trap engineer": {"w_symbol": 0.5, "w_choke": 4.0, "hold": 5, "trigger": 5, "avoid_hazard": 12.0, "w_terrain": 0.4},
	"mobility specialist": {"w_symbol": 0.8, "w_node": 1.2, "w_relic": 1.0, "deploy_key": "move"},
	"terrain controller": {"w_symbol": 0.7, "w_terrain": 2.0, "w_node": 0.5},
	"summoner": {"w_symbol": 0.8, "deploy_max": 9, "deploy_key": "hp"},
	"counter-attacker": {"w_symbol": 0.3, "w_enemy": 1.2, "hold": 2, "trigger": 7, "kill_bonus": 150.0},
	"resource thief": {"w_symbol": 0.5, "w_node": 2.0, "w_relic": 2.0},
	"long-range sniper": {"w_symbol": 0.8, "keep_range": true, "deploy_key": "range", "w_terrain": 0.8},
	"status-effect strategist": {"w_symbol": 0.8, "adv_bonus": 15.0, "w_enemy": 0.6},
	"rush attacker": {"w_symbol": 2.0, "w_enemy": 0.1, "deploy_max": 3, "sym_bonus": 40.0, "deploy_key": "move", "avoid_hazard": 2.0},
}


static func style_names() -> Array:
	return STYLES.keys()


static func params(style: String) -> Dictionary:
	var p := BASE.duplicate()
	p.merge(STYLES.get(style, {}), true)
	return p


## Plays a whole turn for side p and ends it. Returns {"actions", "rejected"}.
static func take_turn(s: GameState, p: int, style: String = "balanced") -> Dictionary:
	var stats := {"actions": 0, "rejected": 0}
	if s.winner != GameState.NONE or s.current != p:
		return stats
	var P := params(style)
	_deploy(s, p, P, stats)
	var order := s.units_of(p)
	var field := s.distance_field(s.symbol_pos[GameState.other(p)])
	order.sort_custom(func(a, b): return field.get(a.pos, 999) < field.get(b.pos, 999))
	for u in order:
		if s.winner != GameState.NONE:
			break
		if s.get_unit(u.id) == null:
			continue
		_act_with(s, p, u, P, stats)
	if s.winner == GameState.NONE:
		_do(s, p, {"type": "end"}, stats)
	return stats


static func _do(s: GameState, p: int, action: Dictionary, stats: Dictionary) -> bool:
	if s.apply(p, action) == GameState.OK:
		stats.actions += 1
		return true
	stats.rejected += 1
	return false


static func _deploy(s: GameState, p: int, P: Dictionary, stats: Dictionary) -> void:
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
			# Prefer the strongest monster by the style's key, then the tile closest to the enemy Symbol.
			var score: float = stat * 100.0 - float(field.get(a.tile, 99)) - m * 0.01
			if score > best_score:
				best_score = score
				best = a
		if not _do(s, p, best, stats):
			return


static func _enemy_targets(s: GameState, p: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [s.symbol_pos[GameState.other(p)]]
	for e in s.units_of(GameState.other(p)):
		out.append(e.pos)
	return out


static func _nearest(c: Vector2i, pts: Array) -> int:
	var best := 99
	for q in pts:
		best = mini(best, GameState.manhattan(c, q))
	return best


static func _threatened(s: GameState, p: int, P: Dictionary) -> bool:
	var own: Vector2i = s.symbol_pos[p]
	for e in s.units_of(GameState.other(p)):
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
	score += float(P.w_terrain) * float(s.attack_of(u, c) - u.attack + s.defense_of(u, c) - u.defense)
	if s.tile_type(c) == "bridge":
		score += float(P.w_choke)
	if s.tile_type(c) == "hazard":
		score -= float(P.avoid_hazard)
	if int(P.hold) > 0 and not threatened:
		var home := s.distance_field(s.symbol_pos[p])
		var dh := int(home.get(c, 40))
		if dh > int(P.hold):
			score -= 4.0 * (dh - int(P.hold))
	for t in _enemy_targets(s, p):
		if GameState.manhattan(c, t) <= s.range_of(u, c):
			score += float(P.w_attack_pos)
			break
	return score


static func _best_target(s: GameState, u: GameState.Unit, P: Dictionary) -> Variant:
	var best: Variant = null
	var best_score := -INF
	for t in s.legal_attacks(u):
		var dmg := s.damage_preview(u, t)
		var score := float(dmg)
		var e := s.unit_at(t)
		if e == null:
			score += float(P.sym_bonus)
			if dmg >= s.symbol_hp[GameState.other(u.owner)]:
				score += 1000.0
		else:
			if dmg >= e.hp:
				score += float(P.kill_bonus)
			if GameState.beats(u.family, e.family):
				score += float(P.adv_bonus)
		if score > best_score:
			best_score = score
			best = t
	return best


static func _act_with(s: GameState, p: int, u: GameState.Unit, P: Dictionary, stats: Dictionary) -> void:
	if u.attacked:
		return
	var target: Variant = _best_target(s, u, P)
	if target != null:
		_do(s, p, {"type": "attack", "unit": u.id, "tile": target}, stats)
		return
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
	if s.get_unit(u.id) == null:
		return
	target = _best_target(s, u, P)
	if target != null:
		_do(s, p, {"type": "attack", "unit": u.id, "tile": target}, stats)
