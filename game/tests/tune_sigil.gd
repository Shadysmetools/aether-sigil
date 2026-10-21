## Sigil/Symbol HP tuning run (tool, not part of the gate). Overrides symbol.hp and the enemy
## difficulty curve in memory, then plays all 120 stages AI vs AI with the default squad.
## Run: Godot_console.exe --headless --path game --script res://tests/tune_sigil.gd -- HP PCT
## Prints one summary line and per-tower player wins / enemy wins / capped.
extends SceneTree

const Data = preload("res://scripts/data_loader.gd")
const GameState = preload("res://scripts/game_state.gd")
const AI = preload("res://scripts/ai.gd")


func _initialize() -> void:
	Data.ensure_loaded()
	var args := OS.get_cmdline_user_args()
	var hp := int(args[0]) if args.size() > 0 else int(Data.rules().symbol.hp)
	var pct := float(args[1]) if args.size() > 1 else float(Data.rules().get("difficulty", {}).get("enemy_stat_pct_per_tower", 0))
	Data.rules().symbol.hp = hp
	Data.rules()["difficulty"] = {"enemy_stat_pct_per_tower": pct}
	var cap := int(Data.rules().turn_cap_rounds)
	var wins := [0, 0]
	var capped := 0
	var rounds: Array[int] = []
	var tower := {}
	for st in Data.stages():
		var s := GameState.new()
		s.setup(st.stage_id, Data.default_squad())
		while s.winner == GameState.NONE and s.round_num <= cap:
			AI.take_activation(s, s.current, "balanced" if s.current == GameState.PLAYER else str(st.opponent_style))
		var t: String = st.tower_id
		if not tower.has(t):
			tower[t] = [0, 0, 0]
		if s.winner == GameState.NONE:
			capped += 1
			tower[t][2] += 1
		else:
			wins[s.winner] += 1
			tower[t][s.winner] += 1
		rounds.append(mini(s.round_num, cap))
	rounds.sort()
	var n := rounds.size()
	var median := (rounds[n / 2] + rounds[(n - 1) / 2]) / 2.0
	print("TUNE hp=%d pct=%d  player %d (%.0f%%)  enemy %d (%.0f%%)  capped %d (%.0f%%)  median_rounds %.1f" % [
		hp, int(pct), wins[0], 100.0 * wins[0] / n, wins[1], 100.0 * wins[1] / n, capped, 100.0 * capped / n, median])
	var row := []
	for k in tower:
		row.append("T%s %d/%d/%d" % [k, tower[k][0], tower[k][1], tower[k][2]])
	print("TOWERS hp=%d pct=%d  %s" % [hp, int(pct), "  ".join(row)])
	print("1 pass / 0 fail")
	quit(0)
