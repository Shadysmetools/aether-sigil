## Loads the real main scene headless and drives it through the UI code paths:
## Build Your Squad -> stage select -> intro -> Sigil summon by tapping a tile (real input path)
## -> End summons -> paced AI -> own monster's activation: move + Defend -> layout check ->
## win -> rival's defeat line -> Next stage -> loss -> Retry. Exits with the failure count.
extends SceneTree

const GameState = preload("res://scripts/game_state.gd")
const Data = preload("res://scripts/data_loader.gd")
const Palette = preload("res://scripts/theme_colors.gd")

const SAVE := "user://smoke_save.json"
const Story = preload("res://scripts/story.gd")

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
	check(main.select_screen.visible, "starts on the title / world map")
	# Prologue on a new game, with Skip.
	check(main.dialogue_box.visible and main.dialogue_text.text == str(Story.lines("prologue")[0].line), "new game plays the prologue")
	check(main.progress.is_seen("prologue"), "prologue seen-flag saved")
	main._on_dialogue_skip()
	check(not main.dialogue_box.visible, "Skip closes the whole sequence")
	main.show_stage_select()
	check(not main.dialogue_box.visible, "prologue does not replay")
	# World map: 12 towers, lock state from the save, x/10 and stars, theme icon.
	check(main.tower_cards.size() == 12, "world map shows 12 towers")
	check(not main.tower_cards["01"].disabled and main.tower_cards["02"].disabled, "T01 unlocked, T02 locked")
	check(main.tower_cards["01"].text.contains("0/10") and main.tower_cards["01"].text.contains("Stars 0/30"), "tower card shows progress and stars: %s" % main.tower_cards["01"].text.replace("\n", " | "))
	check(main.tower_cards["01"].icon != null and main.tower_cards["12"].text.contains("Sunforge Throne"), "tower element icon loaded; T12 is Sunforge Throne")
	# Tap a tower: arrival story (tap to advance), then its 10 stages.
	main._on_tower_pressed("02")
	check(main.select_screen.visible, "tapping a locked tower does nothing")
	main._on_tower_pressed("01")
	check(main.tower_screen.visible and main.stage_buttons.size() == 10, "tower screen lists 10 stages")
	var arrival := Story.lines("arrival_01")
	check(main.dialogue_box.visible and main.dialogue_text.text == str(arrival[0].line), "first visit plays the tower arrival")
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	main._on_dialogue_tap(tap)
	check(arrival.size() < 2 or main.dialogue_text.text == str(arrival[1].line), "tap advances to the next line")
	main._on_dialogue_skip()
	main._on_tower_pressed("01")
	check(not main.dialogue_box.visible, "arrival plays once")
	check(not main.stage_buttons["T01-L01"].disabled and main.stage_buttons["T01-L02"].disabled, "T01-L01 unlocked, T01-L02 locked")
	# Longest line in any dialogue or story fits the portrait layout (no clipping).
	var longest := ""
	for st in Data.stages():
		for v in st.dialogue.values():
			if str(v).length() > longest.length():
				longest = str(v)
	for key in ["prologue", "finale", "epilogue"]:
		for l in Story.lines(key):
			if str(l.line).length() > longest.length():
				longest = str(l.line)
	for t in Data.story().towers:
		for part in ["arrival", "pre_boss", "post_boss"]:
			for l in t[part]:
				if str(l.line).length() > longest.length():
					longest = str(l.line)
	main.show_dialogue([{"speaker": "Narrator", "line": longest}], func(): pass)
	await process_frame
	await process_frame
	var dpanel: Control = main.dialogue_text.get_parent().get_parent().get_parent().get_parent()
	var vp0: Vector2 = main.get_viewport().get_visible_rect().size
	var r: Rect2 = dpanel.get_global_rect()
	check(r.position.y >= 0 and r.end.y <= vp0.y + 1 and main.dialogue_text.get_line_count() <= main.dialogue_text.get_visible_line_count() + 0, "longest line (%d chars) fits on screen: %d lines, panel %s" % [longest.length(), main.dialogue_text.get_line_count(), str(r)])
	main._on_dialogue_skip()
	var missing := []
	for st in Data.stages():
		for row in st.map_grid:
			for t in row:
				if not Palette.has_tile(t) and not missing.has(t):
					missing.append(t)
	check(missing.is_empty(), "every tile type has a colour")
	# Build Your Squad.
	main.show_squad_builder()
	check(main.squad_screen.visible and main.squad_buttons.size() == main.progress.roster.size(), "squad builder lists the owned roster (%d)" % main.squad_buttons.size())
	var coll: Array = main.progress.roster.map(func(i): return str(i.uid))
	var default_uids: Array = main.progress.squad.duplicate()
	var out_uid: String = default_uids[0]
	var in_uid: String = coll.filter(func(u): return not default_uids.has(u))[0]
	main._on_squad_toggle(out_uid)
	check(main.squad_confirm.disabled, "confirm disabled with 3 selected")
	main._on_squad_toggle(in_uid)
	check(not main.squad_confirm.disabled, "confirm enabled with 4")
	main._on_squad_confirm()
	check(main.progress.squad.has(in_uid) and main.progress.squad.size() == 4, "squad saved: %s" % str(main.progress.squad))
	main.progress.set_squad(default_uids)
	# Evolution screen.
	var evo_uid: String = default_uids[1]
	main.show_evolution()
	check(main.evo_screen.visible and main.evo_list.get_child_count() == main.progress.roster.size(), "evolution screen lists the roster")
	var hooked := []
	main.evolved.connect(func(uid, line): hooked.append(line))
	main._on_evolve(evo_uid)
	check(main.progress.get_inst(evo_uid).evo_stage == 0, "Evolve refused below the threshold")
	main.progress.get_inst(evo_uid).level = int(Data.progression().evolution.thresholds[0])
	var old_name: String = main.progress.get_inst(evo_uid).name
	main.show_evolution()
	main._on_evolve(evo_uid)
	check(main.progress.get_inst(evo_uid).evo_stage == 1 and main.progress.get_inst(evo_uid).name != old_name, "Evolve: %s -> %s" % [old_name, main.progress.get_inst(evo_uid).name])
	check(hooked.size() == 1 and main.evo_label.text == hooked[0], "evolution hook fired with the dialogue line: '%s'" % (hooked[0] if hooked.size() > 0 else ""))
	# Fusion screen: preview, then confirm.
	var bench: Array = coll.filter(func(u): return not default_uids.has(u))
	main.progress.get_inst(bench[0]).level = 12
	main.progress.get_inst(bench[1]).level = 11
	main.show_fusion()
	main._on_fusion_toggle(bench[0])
	check(main.fusion_confirm.disabled, "fusion confirm disabled with 1 pick")
	main._on_fusion_toggle(bench[1])
	var expected: Dictionary = main.progress.fusion_preview(bench[0], bench[1])
	check(not main.fusion_confirm.disabled and main.fusion_preview_label.text.contains(str(expected.name)), "Preview Fusion shows %s" % expected.name)
	var before: int = main.progress.roster.size()
	main._on_fusion_confirm()
	check(main.progress.roster.size() == before - 1 and not main.progress.get_inst(str(expected.uid)).is_empty(), "Confirm: parents consumed, %s added" % expected.name)
	main.show_squad_builder()
	check(main.squad_buttons.has(str(expected.uid)), "fused monster appears in the squad builder")
	main.progress.set_squad(default_uids)
	# Battle.
	main._on_stage_pressed("T01-L01")
	await process_frame
	check(main.dialogue_box.visible and main.dialogue_speaker.text == "Ari Voss", "stage_intro dialogue from the bible")
	main._on_dialogue_next()
	await process_frame
	await process_frame
	var s: GameState = main.state
	check(main.bark_label.text.begins_with(Story.hero() + ":"), "battle_start bark: %s" % main.bark_label.text)
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
	check(main.result_sub.text.contains("Stars") and int(main.progress.stars.get("T01-L01", 0)) >= 1, "stars recorded: %s" % str(main.progress.stars))
	check(main.result_sub.text.contains("XP"), "result shows XP earned: %s" % main.result_sub.text.replace("\n", " | "))
	check(main.progress.is_unlocked("T01-L02"), "win unlocked T01-L02")
	main._on_next()
	await process_frame
	check(main.stage_id == "T01-L02" and main.dialogue_box.visible, "Next stage starts T01-L02 with its intro")
	main._on_dialogue_next()
	main.ai_running = false
	s.symbol_hp[GameState.PLAYER] = 0
	s._set_winner(GameState.ENEMY, "symbol")
	main._after_action()
	check(main.dialogue_box.visible and main.dialogue_text.text == str(Story.global_line(2, str(s.stage.opponent)).line), "defeat: the rival gloats (global line 2)")
	main._on_dialogue_next()
	check(main.result_box.visible and main.result_title.text == "Defeat" and not main.next_button.visible, "defeat panel with Retry only")
	main._on_retry()
	await process_frame
	check(main.stage_id == "T01-L02" and s.winner == GameState.NONE and s.units.is_empty(), "Retry restarts the stage")
	main.show_tower("01")
	check(not main.stage_buttons["T01-L02"].disabled and main.stage_buttons["T01-L03"].disabled, "tower screen reflects progress")
	# L10: pre_boss story, then after the win: rival line, global 6, rare_drop reward, post_boss.
	main.progress.unlocked = 10
	main.start_stage("T01-L10")
	var pre := Story.lines("pre_boss_01")
	check(main.dialogue_box.visible and main.dialogue_text.text == str(pre[0].line), "pre_boss story plays before the L10 intro")
	main._on_dialogue_skip()
	main.ai_running = false
	s.symbol_hp[GameState.ENEMY] = 0
	s._set_winner(GameState.PLAYER, "symbol")
	main._after_action()
	var heard := []
	for i in 20:
		if not main.dialogue_box.visible:
			break
		heard.append(main.dialogue_text.text)
		main._on_dialogue_next()
	var reward := str(Data.towers()[0].tower_reward)
	check(heard.has(str(Story.global_line(6, str(s.stage.opponent)).line)), "L10 victory adds global line 6")
	check(heard.any(func(t): return t.contains(reward)), "rare_drop: '%s' announced" % reward)
	check(main.progress.rewards.has(reward), "tower reward saved")
	check(heard.has(str(Story.lines("post_boss_01")[0].line)) and main.progress.is_seen("post_boss_01"), "post_boss story after the L10 win")
	check(main.result_box.visible and main.tower_cards.size() == 12, "result after the story")
	# T12-L10: finale + epilogue follow the post_boss.
	main.progress.unlocked = 120
	main.progress.story_seen["pre_boss_12"] = true
	main.start_stage("T12-L10")
	main._on_dialogue_skip()
	main.ai_running = false
	s.symbol_hp[GameState.ENEMY] = 0
	s._set_winner(GameState.PLAYER, "symbol")
	main._after_action()
	heard = []
	for i in 30:
		if not main.dialogue_box.visible:
			break
		heard.append(main.dialogue_text.text)
		main._on_dialogue_next()
	check(heard.has(str(Story.lines("finale")[0].line)) and heard.has(str(Story.lines("epilogue")[0].line)), "finale and epilogue after T12-L10")
	check(main.progress.is_seen("finale") and main.progress.is_seen("epilogue"), "finale/epilogue seen-flags saved")
	_done()
