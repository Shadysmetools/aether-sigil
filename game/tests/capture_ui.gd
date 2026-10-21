## Windowed stills of the meta screens and monster cards for visual review (not part of the gate).
## Run: Godot.exe --path game --resolution 1080x1920 --script res://tests/capture_ui.gd -- <out_dir>
## Writes title-hub, collection-grid, card-common, card-legendary, card-legendary-back, draft,
## fusion-preview, evolution, squad, settings, rarity-ladder (painted art) and rarity-ladder-fallback.
extends SceneTree

const Data = preload("res://scripts/data_loader.gd")
const Assets = preload("res://scripts/assets.gd")
const MonsterCard = preload("res://scripts/ui/monster_card.gd")
const Kit = preload("res://scripts/ui/menu_kit.gd")
const Palette = preload("res://scripts/theme_colors.gd")
const SAVE := "user://capture_ui_save.json"

var out := "user://"


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String, frames: int = 30) -> void:
	for i in frames:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("saved ", out.path_join(name + ".png"), " ", img.get_size())


## First bible monster of a rarity (optionally of a family).
func _first(rarity: String, fam: String = "") -> String:
	for id in Data.monster_ids():
		var m := Data.monster(id)
		if str(m.rarity) == rarity and (fam == "" or str(m.element_family) == fam):
			return id
	return ""


func _ladder(main: Node, name: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Palette.MIDNIGHT_NAVY
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 40)
	m.theme = main.ui_root.theme
	layer.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	m.add_child(v)
	v.add_child(Kit.title_block("RARITY LADDER", "Common -> Legendary  (compact + mini)"))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 40)
	g.add_theme_constant_override("v_separation", 28)
	var c := CenterContainer.new()
	c.add_child(g)
	v.add_child(c)
	var fams := ["Fire", "Water", "Wood", "Arcane", "Thunder", "Light"]
	var i := 0
	for r in Kit.rarities():
		var card := MonsterCard.new()
		card.setup_bible(_first(r, fams[i]) if _first(r, fams[i]) != "" else _first(r), MonsterCard.Variant.COMPACT, true)
		card.custom_minimum_size = Vector2(300, 420)
		if i == 2:
			card.toggle_mode = true
			card.set_pressed_no_signal(true)
		g.add_child(card)
		i += 1
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	for r in Kit.rarities():
		var mc := MonsterCard.new()
		mc.setup_bible(_first(r), MonsterCard.Variant.MINI, r != "Common")
		row.add_child(mc)
	await _shot(name, 40)
	layer.queue_free()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	root.add_child(main)
	await process_frame
	main._on_dialogue_skip()
	main.progress.unlocked = 14
	for sid in ["T01-L01", "T01-L02", "T01-L03"]:
		main.progress.record_win(sid)
	var roster: Array = main.progress.roster
	roster[0].level = 18
	roster[1].level = 12
	roster[2].level = 9
	for i in range(3, roster.size()):
		roster[i].level = 10 + i
	main.show_title_hub()
	main._on_dialogue_skip()
	await _shot("title-hub", 60)
	main.show_collection()
	await _shot("collection-grid", 40)
	main.card_detail.open_bible(_first("Common", "Water"), true)
	await _shot("card-common")
	main.card_detail.open_bible(_first("Legendary", "Fire"), true)
	await _shot("card-legendary")
	main.card_detail.card.flip()
	await _shot("card-legendary-back")
	main.card_detail.close()
	main.show_squad_builder()
	await _shot("squad")
	main._on_stage_pressed("T02-L01" if main.progress.is_unlocked("T02-L01") else "T01-L04")
	# pick past the cap so the over-cap state shows
	await _shot("draft")
	main.show_evolution()
	await _shot("evolution")
	main.show_fusion()
	var bench: Array = roster.filter(func(i): return not main.progress.squad.has(i.uid))
	main._on_fusion_toggle(str(bench[0].uid) if bench.size() > 0 else str(roster[3].uid))
	main._on_fusion_toggle(str(bench[1].uid) if bench.size() > 1 else str(roster[4].uid))
	await _shot("fusion-preview", 50)
	main.show_settings()
	await _shot("settings")
	main._hide_all()
	await _ladder(main, "rarity-ladder")
	# no painted art at all: procedural fallback
	Assets.ai_root = "user://__no_art__"
	Assets.gen_root = "user://__no_art__"
	Assets.dev_root = ""
	Assets.clear_cache()
	await _ladder(main, "rarity-ladder-fallback")
	main.card_detail.open_bible(_first("Legendary", "Fire"), true)
	await _shot("card-legendary-fallback")
	Assets.reset_roots()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)
