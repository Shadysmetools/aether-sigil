## A progressing player plays all 120 stages in order (AI vs AI, one attempt per stage):
## the squad (drafted under the stage's Bond cap: summon.gd auto_draft) earns XP after every battle, evolves as soon as it may, and fuses once after T04-L10
## and once after T08-L10 (the two weakest eligible squad members). The squad starts as the
## default squad and is kept; after a fusion the fused monster and the strongest bench monster
## take the two freed slots. Used by tests/test_sim.gd (gate) and tests/tune_curve.gd (tuning).
extends RefCounted

const Data = preload("res://scripts/data_loader.gd")
const GameState = preload("res://scripts/game_state.gd")
const AI = preload("res://scripts/ai.gd")
const Prog = preload("res://scripts/progression.gd")
const Progress = preload("res://scripts/progress.gd")
const Summon = preload("res://scripts/summon.gd")

const FUSE_AFTER := ["T04-L10", "T08-L10"]


## Returns {wins, losses, capped, rejected, bad, tower: {tid: [w, l, c]}, evolutions, fusions, levels}.
static func run(pct: float, save_path: String) -> Dictionary:
	var saved_pct = Data.rules().get("difficulty", {}).get("enemy_stat_pct_per_tower", 0)
	Data.rules().difficulty.enemy_stat_pct_per_tower = pct
	var pr := Progress.new(save_path)
	pr.new_game()
	var cap := int(Data.rules().turn_cap_rounds)
	var out := {"wins": 0, "losses": 0, "capped": 0, "rejected": 0, "bad": "", "tower": {}, "evolutions": 0, "fusions": [], "levels": [], "trimmed": 0, "rounds": 0, "reasons": {}}
	for st in Data.stages():
		var s := GameState.new()
		var recs := pr.squad_records()
		var team := Summon.auto_draft(pr.squad, st, recs, func(u): return Prog.power(pr.get_inst(u)))
		if team.size() < pr.squad.size():
			out.trimmed += 1
		s.setup(st.stage_id, team, -1, recs)
		while s.winner == GameState.NONE and s.round_num <= cap:
			var r := AI.take_activation(s, s.current, "balanced" if s.current == GameState.PLAYER else str(st.opponent_style))
			out.rejected += r.rejected
		out.rounds += mini(s.round_num, cap)
		var why := ("P:" if s.winner == GameState.PLAYER else "E:") + s.win_reason if s.winner != GameState.NONE else "draw"
		out.reasons[why] = int(out.reasons.get(why, 0)) + 1
		var t: String = st.tower_id
		if not out.tower.has(t):
			out.tower[t] = [0, 0, 0]
		if s.winner == GameState.PLAYER:
			out.wins += 1
			out.tower[t][0] += 1
		elif s.winner == GameState.ENEMY:
			out.losses += 1
			out.tower[t][1] += 1
		else:
			out.capped += 1
			out.tower[t][2] += 1
		pr.award_battle(s, s.winner == GameState.PLAYER)
		for inst in pr.roster:
			if Prog.can_evolve(inst) == Prog.OK:
				Prog.evolve(inst)
				out.evolutions += 1
		if FUSE_AFTER.has(st.stage_id):
			var cands := pr.squad.map(func(u): return pr.get_inst(u)).filter(func(i): return int(i.level) >= int(Data.progression().fusion.min_level))
			cands.sort_custom(func(a, b): return Prog.power(a) < Prog.power(b))
			if cands.size() >= 2:
				var keep := pr.squad.filter(func(u): return u != cands[0].uid and u != cands[1].uid)
				var f := pr.fuse(cands[0].uid, cands[1].uid)
				if not f.has("error"):
					out.fusions.append("%s+%s=%s Lv%d" % [f.parent_names[0], f.parent_names[1], f.name, f.level])
					var bench := pr.roster.filter(func(i): return not keep.has(i.uid) and i.uid != f.uid)
					bench.sort_custom(func(a, b): return Prog.power(a) > Prog.power(b))
					pr.set_squad(keep + [f.uid, bench[0].uid])
	for u in pr.squad:
		var i := pr.get_inst(u)
		out.levels.append("%s Lv%d evo%d" % [i.name, i.level, i.evo_stage])
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	Data.rules().difficulty.enemy_stat_pct_per_tower = saved_pct
	return out


static func summary(pct: float, r: Dictionary) -> String:
	var n := 120.0
	var rows := []
	for k in r.tower:
		var w: Array = r.tower[k]
		rows.append("T%s %d/%d/%d" % [k, w[0], w[1], w[2]])
	return "PROG pct=%s  player %d (%.0f%%)  enemy %d  draw %d  avg rounds %.1f  drafts trimmed by Bond cap %d  reasons %s  evolutions %d  fusions %s\n  per tower (player/enemy/capped): %s\n  final squad: %s" % [
		str(pct), r.wins, 100.0 * r.wins / n, r.losses, r.capped, r.rounds / n, r.trimmed, str(r.reasons), r.evolutions, str(r.fusions), "  ".join(rows), ", ".join(r.levels)]
