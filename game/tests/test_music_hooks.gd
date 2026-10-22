## Music / ambience hooks fire the right AudioManager ids per screen. A fake AudioManager is
## injected into ui.gd (audio_override) and records every call. Exits with the failure count.
extends SceneTree

const GameState = preload("res://scripts/game_state.gd")
const SAVE := "user://music_hooks_save.json"

class FakeAudio extends Node:
	var calls: Array = []
	func play_world_map_music(_c = 2.0) -> void: calls.append(["world_map"])
	func play_tower_ambient_music(t, _c = 2.0) -> void: calls.append(["tower", str(t)])
	func play_stage_music(s: String, _c = 1.5) -> void: calls.append(["stage", s])
	func play_stage_result(s: String, won: bool, _c = 0.25) -> void: calls.append(["result", s, won])
	func set_battle_heat(r: float) -> void: calls.append(["heat", snappedf(r, 0.01)])
	func play_ambience_for_theme(t: String, _c = 2.0) -> void: calls.append(["amb", t])
	func stop_ambience(_f = 1.5) -> void: calls.append(["amb_stop"])
	func clear() -> void: calls.clear()
	func has_call(prefix: Array) -> bool:
		for c in calls:
			if c.slice(0, prefix.size()) == prefix:
				return true
		return false

var passed := 0
var failed := 0


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("Aether Sigil music hook tests")
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	var fake := FakeAudio.new()
	main.audio_override = fake
	root.add_child(main)
	await process_frame
	await process_frame
	check(fake.has_call(["world_map"]), "title / world map -> play_world_map_music")
	main._on_dialogue_skip()
	fake.clear()
	main.show_stage_select()
	check(fake.has_call(["world_map"]), "show_stage_select -> world map music")
	fake.clear()
	main.show_title_hub()
	check(fake.has_call(["world_map"]), "show_title_hub -> world map music")
	fake.clear()
	main._on_tower_pressed("01")
	check(fake.has_call(["tower", "01"]), "tower select -> tower ambient music 01")
	main._on_dialogue_skip()
	fake.clear()
	main.show_prematch("T01-L01")
	check(fake.has_call(["tower", "01"]), "draft -> tower ambient music")
	main._on_draft_confirm()
	await process_frame
	check(not fake.has_call(["stage"]), "placement does not start battle music yet")
	main._on_cmd("Wait")
	await process_frame
	var theme := str(main._tower("01").get("theme", ""))
	check(fake.has_call(["stage", "T01-L01"]), "battle start -> play_stage_music(T01-L01)")
	check(theme != "" and fake.has_call(["amb", theme]), "battle start -> ambience for theme '%s'" % theme)
	var s: GameState = main.state
	fake.clear()
	s.symbol_hp[GameState.PLAYER] = s.symbol_max / 4
	main._refresh()
	check(fake.has_call(["heat", 0.25]), "Sigil at 25%% -> set_battle_heat(0.25): %s" % str(fake.calls))
	fake.clear()
	main.ai_running = false
	s.symbol_hp[GameState.ENEMY] = 0
	s._set_winner(GameState.PLAYER, "symbol")
	main._after_action()
	main._on_dialogue_next()
	check(fake.has_call(["result", "T01-L01", true]), "win -> play_stage_result(won=true)")
	fake.clear()
	main._on_next()
	await process_frame
	check(fake.has_call(["amb_stop"]), "leaving the battle stops ambience")
	check(fake.has_call(["tower", "01"]), "Next stage -> draft ambient music")
	main._on_draft_confirm()
	main._on_cmd("Wait")
	await process_frame
	main.ai_running = false
	main.state.symbol_hp[GameState.PLAYER] = 0
	main.state._set_winner(GameState.ENEMY, "symbol")
	fake.clear()
	main._after_action()
	main._on_dialogue_next()
	check(fake.has_call(["result", "T01-L02", false]), "loss -> play_stage_result(won=false)")
	fake.clear()
	main._on_retry()
	await process_frame
	check(fake.has_call(["amb_stop"]) and fake.has_call(["tower", "01"]), "Retry -> ambience stopped, draft ambient music")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("%d pass / %d fail" % [passed, failed])
	quit(mini(failed, 255))
