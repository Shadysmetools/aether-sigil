## Windowed stills of the scene layer + Vellum for visual review (not part of the gate).
## Run: Godot.exe --path game --resolution 1080x1920 --script res://tests/capture_scene.gd -- <out_dir>
## Writes narrator-dialogue, narrator-neutral/amused/grave/awed, narrator-sheet (4 faces + full figure),
## narrator-vs-cast (Vellum beside Elio / Pell / Kess), battle-bark, scene-multi (Elio+Pell+rival), cut-in.
extends SceneTree

const Data = preload("res://scripts/data_loader.gd")
const Assets = preload("res://scripts/assets.gd")
const UIArt = preload("res://scripts/ui_art.gd")
const Palette = preload("res://scripts/theme_colors.gd")
const Narrator = preload("res://scripts/narrator.gd")
const Story = preload("res://scripts/story.gd")
const SAVE := "user://capture_scene_save.json"

var out := "user://"
var main: Node


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String, frames: int = 40) -> void:
	for i in frames:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("saved ", out.path_join(name + ".png"), " ", img.get_size())


func _line(who: String, text: String, mood: String) -> Dictionary:
	return {"speaker": who, "line": text, "mood": mood}


func _say(lines: Array, tower: String, backdrop: bool, idx: int, frames: int = 60) -> void:
	main.show_dialogue(lines, func(): pass, tower, backdrop)
	for i in idx:
		main._on_dialogue_next()
	main.dialogue_text.visible_ratio = 1.0
	await _shot("tmp", frames)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	main = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	root.add_child(main)
	await process_frame
	await process_frame
	main.progress.mark_seen("prologue")
	main.show_tower("01")
	# 1. Vellum in a dialogue at a tower arrival
	var arrival: Array = Story.lines("arrival_01")
	main.show_dialogue(arrival, func(): pass, "01", true)
	main.dialogue_text.visible_ratio = 1.0
	await _shot("narrator-dialogue", 70)
	# 2. each face, through the real dialogue path
	var faces := {"neutral": ["dry", "The Ember Bastion. Lava runs under collapsing platforms. Count along."],
		"amused": ["wry", "Another page begins. Do try to survive it, Summoner."],
		"grave": ["solemn", "The Sigil dims, Summoner. I would rather not narrate that ending."],
		"awed": ["wonder", "Look at it. Not a word of that was mine either."]}
	for k in faces:
		main.show_dialogue([_line("Narrator", faces[k][1], faces[k][0])], func(): pass, "02", true)
		main.dialogue_text.visible_ratio = 1.0
		await _shot("narrator-" + k, 60)
	main._on_dialogue_skip()
	# 3. sheet: four faces, the full figure and the bark-bubble bust
	await _sheet()
	# 4. a multi-character scene: Elio + Pell + a rival (and Vellum opening it)
	var scene_lines := [
		_line("Narrator", "The Verdant Spire. Mind the sneezing.", "wry"),
		_line("Elio", "The bridges are moving. They're growing while we walk on them.", "awed"),
		_line("Pell", "Green smell. Happy smell.", "amused"),
		_line("Kess Varrow", "Roots in the walls, pollen in the vents. I'll be at the top before you finish sneezing.", "determined"),
		_line("Elio", "Then I'll see you at the top.", "determined"),
	]
	main.show_dialogue(scene_lines, func(): pass, "01", true)
	for i in 3:
		main._on_dialogue_next()
	main.dialogue_text.visible_ratio = 1.0
	await _shot("scene-multi", 90)
	main._on_dialogue_skip()
	# 5. battle: Vellum's bark bubble and a rival taunt
	main.start_stage("T01-L02")
	await process_frame
	main._on_dialogue_skip()
	await process_frame
	main.narrator_say("battle_start", true)
	main.rival_bubble.place_at(Vector2(360, 230))
	main.rival_bubble.say(str(main.state.stage.opponent), "You brought power. I brought a plan.", "angry", "rival_test")
	await _shot("battle-bark", 80)
	main.narrator_say("vessel_broken", true)
	await _shot("battle-bark-grave", 60)
	# 6. champion cut-in at a tower boss stage
	main.start_stage("T01-L10")
	await _shot("cut-in", 26)
	main._on_dialogue_skip()
	print("done")
	quit(0)


func _sheet() -> void:
	main._hide_all()
	var layer := CanvasLayer.new()
	layer.layer = 60
	root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Palette.MIDNIGHT_NAVY
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var sheet := Control.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(sheet)
	sheet.draw.connect(func():
		var f := UIArt.font(true, 700)
		sheet.draw_string(f, Vector2(30, 56), "VELLUM  -  faces", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Palette.SIGIL_GOLD)
		var x := 30.0
		for e in ["neutral", "amused", "grave", "awed"]:
			UIArt.draw_portrait(sheet, Rect2(x, 76, 240, 240), "Narrator", e, 0.0, false, 0.5)
			sheet.draw_string(f, Vector2(x, 346), e, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Palette.TEXT)
			x += 255.0
		sheet.draw_string(f, Vector2(30, 400), "full figure, then talking", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Palette.SIGIL_GOLD)
		UIArt.draw_actor_figure(sheet, Rect2(30, 410, 330, 480), "Narrator", "neutral", 0.0, false, 0.6)
		UIArt.draw_actor_figure(sheet, Rect2(380, 410, 330, 480), "Narrator", "amused", 0.8, false, 1.9)
		sheet.draw_string(f, Vector2(30, 930), "beside the cast (portraits, then standing)", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Palette.SIGIL_GOLD)
		var x2 := 30.0
		var cast := ["Narrator", "Elio", "Pell", "Kess Varrow", "Ari Voss"]
		for w in cast:
			UIArt.draw_portrait(sheet, Rect2(x2, 950, 195, 195), w, "neutral", 0.0, false, 0.5)
			sheet.draw_string(f, Vector2(x2, 1172), Narrator.plate_name(w), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Palette.TEXT)
			x2 += 208.0
		x2 = 30.0
		for w in cast:
			UIArt.draw_actor_figure(sheet, Rect2(x2, 1190, 195, 360), w, "neutral", 0.0, false, 0.5)
			x2 += 208.0)
	sheet.queue_redraw()
	await _shot("narrator-sheet", 20)
	layer.queue_free()
