## Windowed (not headless) stills for visual review: world map, a dialogue line, a battle mid-fight.
## Run: Godot.exe --path game --resolution 720x1280 --script res://tests/capture_screens.gd -- <out_dir> [STAGE]
## Writes <out_dir>/world-map.png, dialogue.png, battle.png.
extends SceneTree

const GameState = preload("res://scripts/game_state.gd")
const AI = preload("res://scripts/ai.gd")
const SAVE := "user://capture_save.json"

var out := "user://"


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	for i in 12:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("saved ", out.path_join(name + ".png"), " ", img.get_size())


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out = args[0]
	var stage := args[1] if args.size() > 1 else "T01-L01"
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	root.add_child(main)
	await process_frame
	main._on_dialogue_skip()
	main.progress.unlocked = 23
	main.show_stage_select()
	await _shot("world-map")
	main.start_stage(stage)
	await create_timer(2.0).timeout
	await _shot("dialogue")
	main._on_dialogue_skip()
	var s: GameState = main.state
	s.force_hit = -1
	for guard in 200:
		if s.winner != GameState.NONE:
			break
		if s.current == GameState.PLAYER and not s.is_sigil_turn() and s.round_num >= 3:
			break
		AI.take_activation(s, s.current, "balanced" if s.current == GameState.PLAYER else str(s.stage.opponent_style))
	main.ai_running = false
	main.mode = main.Mode.UNIT
	main._refresh("Selected %s: cyan = move, ember = attack." % (s.actor_unit().name if s.actor_unit() != null else "-"))
	main._layout_board()
	await _shot("battle")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)
