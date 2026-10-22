## 40 s demo with audio: stage start -> battle music -> a Sigil drops under 50% -> heat layer fades in.
## Record: Godot.exe --path game --resolution 540x960 --write-movie out.avi --fixed-fps 30 --script res://tests/demo_music_clip.gd
## Prints "MARK <video seconds> <event>" lines. Demo shortcut (disclosed): the Sigil HP is set directly.
extends SceneTree

const GameState = preload("res://scripts/game_state.gd")
const SAVE := "user://demo_music_save.json"
var frames := 0
var main: Node


func _initialize() -> void:
	process_frame.connect(func(): frames += 1)
	_run.call_deferred()


func mark(l: String) -> void:
	print("MARK %.2f %s" % [frames / 30.0, l])


func wait(sec: float) -> void:
	await create_timer(sec).timeout


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	root.add_child(main)
	await wait(0.5)
	main._on_dialogue_skip()
	main._on_stage_pressed("T01-L01")
	await wait(1.0)
	main._on_draft_confirm()
	await wait(1.0)
	main._on_cmd("Wait")
	await wait(0.5)
	mark("battle start, music=%s" % str(main._am().current_stage_music))
	await wait(1.0)
	main._on_dialogue_skip()
	await wait(16.0)
	mark("before heat, intensity=%.2f" % main._am().music_intensity)
	var s: GameState = main.state
	s.symbol_hp[GameState.PLAYER] = int(s.symbol_max * 0.3)
	main._refresh()
	mark("Sigil at 30%%, intensity target=%.2f" % main._am().music_intensity)
	await wait(21.0)
	mark("end, intensity=%.2f" % main._am().music_intensity)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)
