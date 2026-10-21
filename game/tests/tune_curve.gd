## Difficulty-curve tuning (tool, not part of the gate): progressing player, one PCT per run.
## Run: Godot_console.exe --headless --path game --script res://tests/tune_curve.gd -- PCT [TO_NEXT_BASE [T03_ADJUST_PCT]]
extends SceneTree

const Data = preload("res://scripts/data_loader.gd")
const Sim = preload("res://tests/progression_sim.gd")


func _initialize() -> void:
	Data.ensure_loaded()
	var args := OS.get_cmdline_user_args()
	var pct := float(args[0]) if not args.is_empty() else 0.0
	if args.size() > 1:
		Data.progression().xp.to_next_base = int(args[1])
		print("override xp.to_next_base = ", args[1])
	if args.size() > 2:
		Data.rules().difficulty["tower_adjust_pct"] = {"03": float(args[2])}
		print("override difficulty.tower_adjust_pct = {03: ", args[2], "}")
	var r := Sim.run(pct, "user://tune_curve_%s.json" % str(pct))
	print(Sim.summary(pct, r))
	print("1 pass / 0 fail")
	quit(0)
