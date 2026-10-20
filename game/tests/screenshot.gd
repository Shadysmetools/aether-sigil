## Windowed (not headless) capture: opens T01-L01, deploys two monsters, lets the AI reply,
## selects a unit to show its range, and saves the frame to user://screenshot.png.
## Run with the non-console exe:  Godot.exe --path <game> --script res://tests/screenshot.gd
extends SceneTree

const SAVE := "user://screenshot_save.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	root.add_child(main)
	await process_frame
	main.start_stage(OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "T01-L01")
	main._on_dialogue_next()
	var s = main.state
	for id in main.state.reserve[0].slice(0, 3):
		var opts: Array = s.legal_deploys(0).filter(func(a): return a.mon == id)
		if not opts.is_empty():
			s.deploy(0, id, opts[0].tile)
	s.end_turn(0)
	main.AI.take_turn(s, 1, str(s.stage.opponent_style))
	var u = s.units_of(0)[0]
	main.mode = main.Mode.UNIT
	main.selected_unit = u.id
	main._refresh("Selected %s: cyan = move, ember = attack." % u.name)
	for i in 20:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png("user://screenshot.png")
	print("saved ", ProjectSettings.globalize_path("user://screenshot.png"), " ", img.get_size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)
