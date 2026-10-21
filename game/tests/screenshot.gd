## Windowed (not headless) capture: opens a stage (default T01-L01), summons the squad, plays
## AI activations until one of our monsters is active, shows its range, saves user://screenshot.png.
## Run with the non-console exe:  Godot.exe --path <game> --script res://tests/screenshot.gd [-- STAGE]
extends SceneTree

const GameState = preload("res://scripts/game_state.gd")
const AI = preload("res://scripts/ai.gd")
const SAVE := "user://screenshot_save.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	root.add_child(main)
	await process_frame
	var args := OS.get_cmdline_user_args()
	main.start_stage(args[0] if not args.is_empty() else "T01-L01")
	main.dialogue_box.visible = false
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
	for i in 20:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png("user://screenshot.png")
	print("saved ", ProjectSettings.globalize_path("user://screenshot.png"), " ", img.get_size(), " board at ", main.board.position, " x", main.board.scale.x)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)
