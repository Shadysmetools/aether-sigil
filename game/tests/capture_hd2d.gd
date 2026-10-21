## Windowed stills + fps probe for the HD-2D board (not a test; needs a real renderer).
## Run: Godot.exe --path game --resolution 1080x1920 --script res://tests/capture_hd2d.gd -- <out_dir> [STAGE ...] [--zoom=1.8] [--step=1] [--fps=6]
## For each stage: opens it, plays AI activations for both sides until round 3 (summons, moves,
## attacks), selects our active monster and saves <out_dir>/battle-<STAGE>.png. --fps=N measures the
## average frame rate over N seconds of the live battle (vsync off, uncapped) and prints "FPS ...".
extends SceneTree

const GameState = preload("res://scripts/game_state.gd")
const AI = preload("res://scripts/ai.gd")
const SAVE := "user://capture_hd2d_save.json"

var out := "user://"


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var stages: Array = []
	var zoom := 1.0
	var step := 0
	var fps_secs := 0.0
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--zoom="):
			zoom = float(a.trim_prefix("--zoom="))
		elif a.begins_with("--step="):
			step = int(a.trim_prefix("--step="))
		elif a.begins_with("--fps="):
			fps_secs = float(a.trim_prefix("--fps="))
		elif out == "user://":
			out = a
		else:
			stages.append(a)
	if stages.is_empty():
		stages = ["T01-L01"]
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	root.add_child(main)
	await process_frame
	main._on_dialogue_skip()
	for stage in stages:
		main.start_stage(stage)
		await _frames(3)
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
		if main.board.has_method("rotate_view"):
			for i in step:
				main.board.rotate_view(1)
			main.board.set_zoom(zoom)
		await _frames(45)
		var img := root.get_texture().get_image()
		var path := out.path_join("battle-%s.png" % stage)
		img.save_png(path)
		print("saved ", path, " ", img.get_size())
		if main.board.has_method("rotate_view"):
			print("cam dist %.1f shadow max %.1f near %.2f" % [main.board._fit_dist, main.board.sun.directional_shadow_max_distance, main.board.cam.near])
		if fps_secs > 0.0:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
			await _frames(30)
			var t0 := Time.get_ticks_usec()
			var f0 := Engine.get_frames_drawn()
			while Time.get_ticks_usec() - t0 < int(fps_secs * 1e6):
				await process_frame
			var secs := (Time.get_ticks_usec() - t0) / 1e6
			var drawn := Engine.get_frames_drawn() - f0
			print("FPS %s %.1f (%d frames / %.2fs, renderer %s, window %s, draw calls %d, primitives %d)" % [stage, drawn / secs, drawn, secs,
				RenderingServer.get_current_rendering_method(), str(DisplayServer.window_get_size()),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)
