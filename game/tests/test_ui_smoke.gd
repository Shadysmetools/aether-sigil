## Loads the real main scene headless and drives it through the UI code paths:
## stage select -> intro dialogue -> deploy by tapping a tile (real input path) -> End Turn ->
## AI reply -> select + move -> win -> rival's defeat line -> Next stage. Exits with failures.
extends SceneTree

const GameState = preload("res://scripts/game_state.gd")
const Data = preload("res://scripts/data_loader.gd")
const Palette = preload("res://scripts/theme_colors.gd")

const SAVE := "user://smoke_save.json"

var passed := 0
var failed := 0


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("  PASS  ", label)
	else:
		failed += 1
		print("  FAIL  ", label)


func _tap(main: Node, c: Vector2i) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	# Real input path: viewport -> GUI (mouse filters) -> _unhandled_input, in canvas coords.
	ev.position = main.board.get_global_transform_with_canvas() * main.board.tile_center(c)
	ev.global_position = ev.position
	root.push_input(ev, true)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("Aether Sigil UI smoke test")
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	root.add_child(main)
	await process_frame
	await process_frame
	check(main.select_screen.visible, "starts on stage select")
	check(main.stage_buttons.size() == 120, "120 stage buttons (got %d)" % main.stage_buttons.size())
	check(not main.stage_buttons["T01-L01"].disabled, "T01-L01 unlocked")
	check(main.stage_buttons["T01-L02"].disabled, "T01-L02 locked")
	# Every tile type on any map has its own colour.
	var missing := []
	for st in Data.stages():
		for row in st.map_grid:
			for t in row:
				if not Palette.has_tile(t) and not missing.has(t):
					missing.append(t)
	check(missing.is_empty(), "every tile type has a colour (missing %s)" % str(missing))

	main._on_stage_pressed("T01-L01")
	await process_frame
	check(main.dialogue_box.visible, "intro dialogue shows before battle")
	check(main.dialogue_text.text.length() > 10 and main.dialogue_speaker.text == "Ari Voss", "intro line from the bible, speaker '%s'" % main.dialogue_speaker.text)
	main._on_dialogue_next()
	check(not main.dialogue_box.visible and main.hud.visible, "dialogue closes, HUD shows")
	var s: GameState = main.state
	var team := Data.starter_team()
	main._on_team(team[0])
	check(main.board.highlights.size() > 0, "deploy mode highlights legal tiles (%d)" % main.board.highlights.size())
	var spawn: Vector2i = main.board.highlights.keys()[0]
	_tap(main, spawn)
	await process_frame
	check(s.unit_at(spawn) != null and s.unit_at(spawn).mon_id == team[0], "tap on tile deployed %s at %s" % [team[0], spawn])
	check(main.team_buttons[team[0]].text.contains("on board"), "team button shows the monster is on board")
	# Pick-test the iso inverse on every tile.
	var pick_ok := true
	for y in 12:
		for x in 12:
			var c := Vector2i(x, y)
			if main.board.tile_at_local(main.board.tile_center(c)) != c:
				pick_ok = false
	check(pick_ok, "isometric picking inverts the projection on all 144 tiles")
	main._on_end_turn()
	check(main.ai_running, "AI turn started after End Turn")
	await create_timer(1.5).timeout
	check(not main.ai_running and s.current == GameState.PLAYER, "AI finished and handed the turn back")
	check(s.units_of(GameState.ENEMY).size() > 0, "AI deployed monsters")
	# Layout: the board's tapped tile must not sit under a HUD panel.
	var hud_bottom: Control = main.team_buttons[team[0]].get_parent().get_parent().get_parent()
	check(hud_bottom.get_global_rect().position.y > main.get_viewport().get_visible_rect().size.y * 0.6, "bottom HUD docked to the lower part of the screen (top at %d)" % hud_bottom.get_global_rect().position.y)
	var u := s.unit_at(spawn)
	if u == null:
		print("%d pass / %d fail" % [passed, failed + 1])
		quit(failed + 1)
		return
	_tap(main, spawn)
	await process_frame
	check(main.mode == main.Mode.UNIT and main.selected_unit == u.id, "tapping own monster selects it")
	var dests: Array = s.legal_moves(u)
	check(dests.size() > 0 and main.board.highlights.size() >= dests.size(), "move range highlighted")
	_tap(main, dests[0])
	await process_frame
	check(u.pos == dests[0], "tap moved the monster to %s" % dests[0])
	# Force a win: the rival's 'defeat' line plays, then the result with Next stage.
	s.symbol_hp[GameState.ENEMY] = 0
	s._set_winner(GameState.PLAYER, "symbol")
	main._after_action()
	check(main.dialogue_box.visible and main.dialogue_text.text == str(s.stage.dialogue.defeat).substr(str(s.stage.dialogue.defeat).find(": ") + 2), "rival's defeat line after the win")
	main._on_dialogue_next()
	check(main.result_box.visible and main.result_title.text == "Victory", "victory panel")
	check(main.next_button.visible, "Next stage offered")
	check(main.progress.is_unlocked("T01-L02"), "win unlocked T01-L02")
	main._on_next()
	await process_frame
	check(main.stage_id == "T01-L02" and main.dialogue_box.visible, "Next stage starts T01-L02 with its intro")
	main._on_dialogue_next()
	s.symbol_hp[GameState.PLAYER] = 0
	s._set_winner(GameState.ENEMY, "symbol")
	main._after_action()
	check(main.result_box.visible and main.result_title.text == "Defeat" and not main.next_button.visible, "defeat panel with Retry only")
	main._on_retry()
	await process_frame
	check(main.stage_id == "T01-L02" and s.winner == GameState.NONE and s.units.is_empty(), "Retry restarts the stage")
	main.show_stage_select()
	check(not main.stage_buttons["T01-L02"].disabled and main.stage_buttons["T01-L03"].disabled, "stage select reflects progress")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("%d pass / %d fail" % [passed, failed])
	quit(failed)
