## Summon Points tuning run (tool, not part of the gate): overrides game_rules.json values in
## memory, then plays the progressing-player campaign (progression_sim) once.
## Run: Godot_console.exe --headless --path game --script res://tests/tune_sp.gd -- KEY=VALUE ...
## Keys: pct (enemy %/tower), enemy_income, enemy_start, income, start, cap, crack_range,
##       vessel_hp, ko_base, symbol_hp, t03 (tower 03 adjust %), base (enemy stat % at every tower).
extends SceneTree

const Data = preload("res://scripts/data_loader.gd")
const Sim = preload("res://tests/progression_sim.gd")


func _initialize() -> void:
	Data.ensure_loaded()
	var R := Data.rules()
	var pct := float(R.difficulty.enemy_stat_pct_per_tower)
	for a in OS.get_cmdline_user_args():
		var kv := str(a).split("=")
		if kv.size() != 2:
			continue
		var v := float(kv[1])
		match kv[0]:
			"pct": pct = v
			"enemy_income": R.summon_points.enemy_income_bonus = int(v)
			"enemy_start": R.summon_points.enemy_start_bonus = int(v)
			"income": R.summon_points.income_per_turn = int(v)
			"start": R.summon_points.start = int(v)
			"cap": R.summon_points.cap = int(v)
			"crack_range": R.summon_points.crack_range = int(v)
			"vessel_hp": R.vessel.hp_base = int(v)
			"ko_base": R.ko_sigil_damage.base = int(v)
			"symbol_hp": R.symbol.hp = int(v)
			"t03": R.difficulty.tower_adjust_pct = {"03": v}
			"base": R.difficulty.enemy_stat_base_pct = v
			"adj":  # adj=02:10,11:-10 (tower -> adjust %)
				var t := {}
				for pair in str(kv[1]).split(","):
					var tv := pair.split(":")
					if tv.size() == 2:
						t[tv[0]] = float(tv[1])
				R.difficulty.tower_adjust_pct = t
	var r := Sim.run(pct, "user://tune_sp_%d.json" % (Time.get_ticks_usec() % 100000))
	print("ARGS ", " ".join(OS.get_cmdline_user_args()))
	print(Sim.summary(pct, r))
	print("1 pass / 0 fail")
	quit(0)
