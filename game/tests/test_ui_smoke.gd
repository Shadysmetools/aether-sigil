## Loads the real main scene headless and drives it through the UI code paths:
## Build Your Squad -> stage select -> intro -> Sigil summon by tapping a tile (real input path)
## -> End summons -> paced AI -> own monster's activation: move + Defend -> layout check ->
## win -> rival's defeat line -> Next stage -> loss -> Retry. Exits with the failure count.
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
	ev.position = main.board.get_global_transform_with_canvas() * main.board.tile_center(c)
	ev.global_position = ev.position
	root.push_input(ev, true)


## Waits until the AI hands control back (bounded).
func _wait_ai(main: Node) -> void:
	for i in 200:
		if not main.ai_running:
			return
		await create_timer(0.1).timeout


func _initialize() -> void:
	_run.call_deferred()


func _done() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("%d pass / %d fail" % [passed, failed])
	quit(mini(failed, 255))


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
	check(main.stage_buttons.size() == 120, "120 stage buttons")
	check(not main.stage_buttons["T01-L01"].disabled and main.stage_buttons["T01-L02"].disabled, "T01-L01 unlocked, T01-L02 locked")
	var missing := []
	for st in Data.stages():
		for row in st.map_grid:
			for t in row:
				if not Palette.has_tile(t) and not missing.has(t):
					missing.append(t)
	check(missing.is_empty(), "every tile type has a colour")
	# Build Your Squad.
	main.show_squad_builder()
	check(main.squad_screen.visible and main.squad_buttons.size() == Data.squad_collection().size(), "squad builder lists the collection (%d)" % main.squad_buttons.size())
	var coll := Data.squad_collection()
	main._on_squad_toggle(coll[0])
	check(main.squad_confirm.disabled, "confirm disabled with 3 selected")
	main._on_squad_toggle(coll[4])
	check(not main.squad_confirm.disabled, "confirm enabled with 4")
	main._on_squad_confirm()
	check(main.progress.squad.has(coll[4]) and main.progress.squad.size() == 4, "squad saved: %s" % str(main.progress.squad))
	main.progress.set_squad(Data.default_squad())
	# Battle.
	main._on_stage_pressed("T01-L01")
	await process_frame
	check(main.dialogue_box.visible and main.dialogue_speaker.text == "Ari Voss", "intro dialogue from the bible")
	main._on_dialogue_next()
	await process_frame
	await process_frame
	var s: GameState = main.state
	check(main.hud.visible and s.actor_id == GameState.sigil_id(GameState.PLAYER), "battle opens on the Player Sigil's activation")
	check(main.order_box.get_child_count() >= 3, "turn order panel lists actors (%d)" % main.order_box.get_child_count())
	check(main.objectives_box.get_child_count() >= 4, "objectives panel lists objectives (%d)" % main.objectives_box.get_child_count())
	check(main.minimap.size.x >= 150, "tactical minimap shown (%s)" % str(main.minimap.size))
	check(s.units_of(GameState.ENEMY).any(func(u): return u.dormant), "dormant statues on the board")
	# Layout: no visible HUD panel covers a tile you might tap.
	var covered := []
	var panels: Array = [main.top_panel, main.turn_panel, main.side_panel, main.bottom_panel]
	for y in 12:
		for x in 12:
			var c := Vector2i(x, y)
			var pt: Vector2 = main.board.get_global_transform_with_canvas() * main.board.top_center(c)
			for pnl in panels:
				if pnl.get_global_rect().has_point(pt):
					covered.append(c)
	check(covered.is_empty(), "no HUD panel covers any of the 144 tiles (covered: %s)" % str(covered.slice(0, 6)))
	var vp: Vector2 = main.get_viewport().get_visible_rect().size
	var on_screen := true
	for c in [Vector2i(0, 0), Vector2i(11, 0), Vector2i(0, 11), Vector2i(11, 11)]:
		var pt: Vector2 = main.board.get_global_transform_with_canvas() * main.board.tile_center(c)
		on_screen = on_screen and Rect2(Vector2.ZERO, vp).has_point(pt)
	check(on_screen, "all four board corners on screen")
	# Summon by tapping.
	var first: String = main.progress.squad[0]
	main._on_team(0)
	check(main.board.highlights.size() > 0, "summon mode highlights legal tiles (%d)" % main.board.highlights.size())
	var spawn: Vector2i = main.board.highlights.keys()[0]
	_tap(main, spawn)
	await process_frame
	check(s.unit_at(spawn) != null and s.unit_at(spawn).mon_id == first, "tap summoned %s at %s" % [first, spawn])
	main._on_cmd("Wait")
	check(main.ai_running, "End summons hands over to the enemy (AI paced)")
	# Play on until one of our monsters is the active actor.
	var mine: GameState.Unit = null
	for guard in 40:
		await _wait_ai(main)
		if s.winner != GameState.NONE:
			break
		if main.dialogue_box.visible:
			main._on_dialogue_next()
			continue
		if s.current == GameState.PLAYER and not s.is_sigil_turn():
			mine = s.actor_unit()
			break
		if s.current == GameState.PLAYER:
			main._on_cmd("Wait")
	check(mine != null, "one of our monsters gets an initiative turn")
	if mine == null:
		_done()
		return
	check(main.mode == main.Mode.UNIT and main.board.selected == mine.pos, "active monster auto-selected")
	check(not main.cmd_buttons["Defend"].disabled and not main.cmd_buttons["Wait"].disabled, "command bar enabled")
	var dests: Array = s.legal_moves(mine)
	if not dests.is_empty():
		_tap(main, dests[0])
		await process_frame
		check(mine.pos == dests[0], "tap moved the monster")
	main._on_cmd("Defend")
	check(mine.defending and s.actor_id != mine.id, "Defend command ends its activation")
	await _wait_ai(main)
	if main.dialogue_box.visible:
		main._on_dialogue_next()
	# Win -> rival's defeat line -> result -> Next stage.
	main.ai_running = false
	s.symbol_hp[GameState.ENEMY] = 0
	s._set_winner(GameState.PLAYER, "symbol")
	main._after_action()
	var defeat_line := str(s.stage.dialogue.defeat)
	check(main.dialogue_box.visible and main.dialogue_text.text == defeat_line.substr(defeat_line.find(": ") + 2), "rival's defeat line after the win")
	main._on_dialogue_next()
	check(main.result_box.visible and main.result_title.text == "Victory" and main.next_button.visible, "victory panel with Next stage")
	check(main.progress.is_unlocked("T01-L02"), "win unlocked T01-L02")
	main._on_next()
	await process_frame
	check(main.stage_id == "T01-L02" and main.dialogue_box.visible, "Next stage starts T01-L02 with its intro")
	main._on_dialogue_next()
	main.ai_running = false
	s.symbol_hp[GameState.PLAYER] = 0
	s._set_winner(GameState.ENEMY, "symbol")
	main._after_action()
	check(main.result_box.visible and main.result_title.text == "Defeat" and not main.next_button.visible, "defeat panel with Retry only")
	main._on_retry()
	await process_frame
	check(main.stage_id == "T01-L02" and s.winner == GameState.NONE and s.units.is_empty(), "Retry restarts the stage")
	main.show_stage_select()
	check(not main.stage_buttons["T01-L02"].disabled and main.stage_buttons["T01-L03"].disabled, "stage select reflects progress")
	_done()
