## Loads the real main scene headless and drives it through the UI code paths
## (satchel button -> tap tile -> End Turn -> AI reply). Exits with the failure count.
extends SceneTree

const GameState = preload("res://scripts/game_state.gd")
const HexGrid = preload("res://scripts/hex_grid.gd")

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
	print("Emberwick UI smoke test")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var s: GameState = main.state
	check(s != null and main.board != null, "main scene built state and board")
	check(main.satchel_buttons.size() == 6, "6 satchel buttons")
	main._on_satchel("pip")
	check(main.board.highlights.size() > 0, "summon mode highlights legal tiles")
	_tap(main, Vector2i(0, 2))
	check(s.unit_at(Vector2i(0, 2)) != null, "tap on tile summoned Pip at (0,2)")
	check(s.oil[GameState.HUMAN] == 1, "Oil spent (2 -> 1)")
	main._on_end_turn()
	check(main.ai_running, "AI turn started after End Turn")
	await create_timer(1.5).timeout
	check(not main.ai_running and s.current == GameState.HUMAN, "AI finished and handed the turn back")
	check(s.units_of(GameState.RIVAL).size() == 1, "AI summoned a Wick")
	# Select our Pip and move it by tapping.
	_tap(main, Vector2i(0, 2))
	check(main.mode == main.Mode.UNIT, "tapping own Wick selects it")
	_tap(main, Vector2i(0, 1))
	check(s.unit_at(Vector2i(0, 1)) != null, "tap moved the Wick to (0,1)")
	s.hearth_hp[GameState.RIVAL] = 0
	s.winner = GameState.HUMAN
	s.win_reason = "hearth"
	main._refresh()
	check(main.banner.visible and main.banner_label.text.begins_with("You win"), "win banner shows")
	main._on_restart()
	check(not main.banner.visible and s.units.is_empty() and s.turn == 1, "Restart resets the game")
	print("%d pass / %d fail" % [passed, failed])
	quit(failed)
