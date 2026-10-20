## AI-vs-AI simulation of every stage: player side = starter team with the "balanced" AI,
## enemy side = the stage roster with the AI for its opponent_style. Seeded per stage, so
## results are reproducible. Turn cap from game_rules.json (turn_cap_rounds).
## Pass/fail covers legality and consistency only; win rates are printed as balance evidence.
extends SceneTree

const Data = preload("res://scripts/data_loader.gd")
const GameState = preload("res://scripts/game_state.gd")
const AI = preload("res://scripts/ai.gd")

var passed := 0
var failed := 0


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL  ", label)


func _initialize() -> void:
	print("Aether Sigil AI-vs-AI simulation (120 stages)")
	Data.ensure_loaded()
	print("== RUN A: starter team (data/game_rules.json) ==")
	run(Data.starter_team(), true)
	var avg := average_commons()
	print("")
	print("== RUN B (control): 5 Commons closest to the Common average stats %s ==" % str(avg))
	run(avg, false)
	check(Data.stage_count() == 120, "simulated all 120 stages")
	print("%d pass / %d fail" % [passed, failed])
	quit(failed)


## One Common per role (Guardian, Striker, Artillery, Scout, Support) nearest the Common mean stats.
func average_commons() -> Array:
	var keys := ["hp", "attack", "defense", "move", "range"]
	var commons := Data.monster_ids().filter(func(id): return Data.monster(id).rarity == "Common")
	var mean := {}
	for k in keys:
		var t := 0.0
		for id in commons:
			t += Data.monster(id)[k]
		mean[k] = t / commons.size()
	var out := []
	for role in ["Guardian", "Striker", "Artillery", "Scout", "Support"]:
		var best := ""
		var best_d := INF
		for id in commons:
			var m := Data.monster(id)
			if m.role != role:
				continue
			var d := 0.0
			for k in keys:
				d += pow((m[k] - mean[k]) / maxf(1.0, mean[k]), 2)
			if d < best_d:
				best_d = d
				best = id
		out.append(best)
	return out


func run(team: Array, verbose: bool) -> void:
	var cap := int(Data.rules().turn_cap_rounds)
	var t0 := Time.get_ticks_msec()
	var wins := [0, 0]
	var capped := 0
	var reasons := {}
	var by_style := {}   ## style -> [player wins, enemy wins, capped]
	var by_tower := {}
	var rounds_total := 0
	var total_rejected := 0
	var kos := [0, 0]
	for st in Data.stages():
		var s := GameState.new()
		s.setup(st.stage_id, team)
		var rejected := 0
		var bad := ""
		while s.winner == GameState.NONE and s.round_num <= cap:
			var side := s.current
			var r := AI.take_turn(s, side, "balanced" if side == GameState.PLAYER else str(st.opponent_style))
			rejected += r.rejected
			if bad == "":
				bad = _invariants(s)
		total_rejected += rejected
		check(rejected == 0, "%s: %d illegal AI actions" % [st.stage_id, rejected])
		check(bad == "", "%s: invariant broken: %s" % [st.stage_id, bad])
		var style := str(st.opponent_style)
		if not by_style.has(style):
			by_style[style] = [0, 0, 0]
		if not by_tower.has(st.tower_id):
			by_tower[st.tower_id] = [0, 0, 0]
		var outcome := "cap"
		if s.winner == GameState.NONE:
			capped += 1
			by_style[style][2] += 1
			by_tower[st.tower_id][2] += 1
		else:
			wins[s.winner] += 1
			by_style[style][s.winner] += 1
			by_tower[st.tower_id][s.winner] += 1
			reasons[s.win_reason] = reasons.get(s.win_reason, 0) + 1
			outcome = ("PLAYER" if s.winner == GameState.PLAYER else "ENEMY ") + " by " + s.win_reason
		rounds_total += mini(s.round_num, cap)
		kos[0] += s.kos[0]
		kos[1] += s.kos[1]
		if verbose:
			print("  %s %-26s %-16s round %2d  sym %3d/%3d  lost %d/%d" % [st.stage_id, style, outcome, mini(s.round_num, cap),
				s.symbol_hp[0], s.symbol_hp[1], s.kos[0], s.kos[1]])
	var n := Data.stage_count()
	print("")
	print("RESULTS over %d stages (cap %d rounds):" % [n, cap])
	print("  ended with a winner: %d   hit the cap: %d" % [n - capped, capped])
	print("  player (balanced AI) wins: %d (%.0f%%)   enemy wins: %d (%.0f%%)" % [wins[0], 100.0 * wins[0] / n, wins[1], 100.0 * wins[1] / n])
	print("  win reasons: %s" % str(reasons))
	print("  average rounds: %.1f   monsters lost: player %d, enemy %d" % [float(rounds_total) / n, kos[0], kos[1]])
	print("  by opponent_style [player wins, enemy wins, capped]:")
	for k in by_style:
		print("    %-26s %s" % [k, str(by_style[k])])
	print("  by tower [player wins, enemy wins, capped]:")
	for k in by_tower:
		print("    T%s %s" % [k, str(by_tower[k])])
	print("  total illegal actions: %d   time %.1fs" % [total_rejected, (Time.get_ticks_msec() - t0) / 1000.0])


func _invariants(s: GameState) -> String:
	var seen := {}
	for u in s.units:
		if not s.is_walkable(u.pos):
			return "unit %s on unwalkable %s" % [u.name, u.pos]
		if seen.has(u.pos):
			return "two units on %s" % u.pos
		seen[u.pos] = true
		if u.hp <= 0 or u.hp > u.max_hp:
			return "bad hp %d on %s" % [u.hp, u.name]
	for side in 2:
		if s.symbol_hp[side] < 0:
			return "negative Symbol HP"
	return ""
