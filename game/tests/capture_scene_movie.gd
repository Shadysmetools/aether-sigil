## Records the scene layer for ~20 s (engine movie mode): Vellum, Maren, Elio, Pell and Kess talking in a scene.
## Run: Godot.exe --path game --resolution 720x1280 --fixed-fps 30 --write-movie <out.avi> --script res://tests/capture_scene_movie.gd
extends SceneTree

const Story = preload("res://scripts/story.gd")
const SAVE := "user://capture_movie_save.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	root.add_child(main)
	for i in 3:
		await process_frame
	main.progress.mark_seen("prologue")
	main.show_stage_select()
	var p: Array = Story.lines("prologue")
	var lines := []
	for i in [0, 3, 4, 6, 7, 10, 11, 12]:
		lines.append(p[i])
	main.show_dialogue(lines, func(): pass, "", true)
	main.scene.auto = true
	for i in 660:
		await process_frame
	quit(0)
