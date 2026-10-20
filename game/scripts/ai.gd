## Simple rival AI. Uses ONLY the public, validated GameState actions (same as the UI),
## so it can never do anything a human could not. Returns stats for testing.
extends RefCounted

const HexGrid = preload("res://scripts/hex_grid.gd")
const Wicks = preload("res://scripts/wicks.gd")
const GameState = preload("res://scripts/game_state.gd")


## Plays a whole turn for player `p` and ends it. Returns {"actions": int, "rejected": int}.
static func take_turn(s: GameState, p: int) -> Dictionary:
	var stats := {"actions": 0, "rejected": 0}
	if s.winner != GameState.NONE or s.current != p:
		return stats
	_try_summon(s, p, stats)
	_try_post(s, p, stats)
	for u in s.units_of(p):
		if s.winner != GameState.NONE:
			break
		if s.get_unit(u.id) == null:
			continue
		_act_with(s, p, u, stats)
	if s.winner == GameState.NONE:
		_do(s.end_turn(p), stats)
	return stats


static func _do(result: String, stats: Dictionary) -> bool:
	if result == GameState.OK:
		stats.actions += 1
		return true
	stats.rejected += 1
	return false


## Goals: Beacons not yet ours, enemy Wicks, enemy Hearth.
static func _goals(s: GameState, p: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for b in s.beacons:
		if s.beacons[b] != p:
			out.append(b)
	for e in s.units_of(GameState.other(p)):
		out.append(e.pos)
	out.append(GameState.HEARTH_TILES[GameState.other(p)])
	return out


static func _dist_to_goals(c: Vector2i, goals: Array[Vector2i]) -> int:
	var best := 999
	for g in goals:
		best = mini(best, HexGrid.distance(c, g))
	return best


static func _try_summon(s: GameState, p: int, stats: Dictionary) -> void:
	var options: Array = s.satchels[p].duplicate()
	options.sort_custom(func(a, b): return int(Wicks.get_def(a).cost) < int(Wicks.get_def(b).cost))
	var goals := _goals(s, p)
	for def_id in options:
		if int(Wicks.get_def(def_id).cost) > s.oil[p]:
			continue
		var best := Vector2i.ZERO
		var best_score := 9999
		var found := false
		for c in s.tiles:
			if s.can_summon(p, def_id, c) != GameState.OK:
				continue
			var score := _dist_to_goals(c, goals)
			if score < best_score:
				best_score = score
				best = c
				found = true
		if found:
			_do(s.summon(p, def_id, best), stats)
			return  # one summon per turn


static func _try_post(s: GameState, p: int, stats: Dictionary) -> void:
	# Only spend "spare" Oil: keep enough back to afford the cheapest Wick still in the satchel.
	var reserve := 0
	if not s.satchels[p].is_empty():
		reserve = 99
		for def_id in s.satchels[p]:
			reserve = mini(reserve, int(Wicks.get_def(def_id).cost))
	if s.oil[p] - reserve < GameState.POST_COST:
		return
	var goals := _goals(s, p)
	var best := Vector2i.ZERO
	var best_gain := 0
	var best_tiebreak := 9999
	for c in s.tiles:
		if s.can_plant_post(p, c) != GameState.OK:
			continue
		var gain := 0
		for n in HexGrid.neighbors(c):
			if HexGrid.in_board(n, GameState.RADIUS) and s.light_owner(n) != p:
				gain += 1
		var tb := _dist_to_goals(c, goals)
		if gain > best_gain or (gain == best_gain and gain > 0 and tb < best_tiebreak):
			best_gain = gain
			best_tiebreak = tb
			best = c
	if best_gain > 0:
		_do(s.plant_post(p, best), stats)


static func _best_target(s: GameState, p: int, u: GameState.Unit) -> Variant:
	var best: Variant = null
	var best_hp := 9999
	var targets: Array[Vector2i] = []
	for e in s.units_of(GameState.other(p)):
		targets.append(e.pos)
	targets.append(GameState.HEARTH_TILES[GameState.other(p)])
	for t in targets:
		if s.can_attack(p, u.id, t) != GameState.OK:
			continue
		var e = s.unit_at(t)
		var hp: int = e.hp if e != null else s.hearth_hp[GameState.other(p)]
		if hp < best_hp:
			best_hp = hp
			best = t
	return best


static func _act_with(s: GameState, p: int, u: GameState.Unit, stats: Dictionary) -> void:
	if u.attacked:
		return
	var target: Variant = _best_target(s, p, u)
	if target != null:
		_do(s.attack(p, u.id, target), stats)
		return
	if not u.moved:
		var on_open_beacon: bool = s.beacons.has(u.pos) and s.beacons[u.pos] != p
		if not on_open_beacon:
			var goals := _goals(s, p)
			var here := _dist_to_goals(u.pos, goals)
			var best_tile: Vector2i = u.pos
			var best_d := here
			var reach := s.reachable(u)
			for c in reach:
				var d := _dist_to_goals(c, goals)
				if d < best_d:
					best_d = d
					best_tile = c
			if best_tile != u.pos:
				_do(s.move_unit(p, u.id, best_tile), stats)
	target = _best_target(s, p, u)
	if target != null:
		_do(s.attack(p, u.id, target), stats)
