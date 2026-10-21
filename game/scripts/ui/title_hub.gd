## Title hub (main menu): key-art backdrop, the Aether Sigil logo, and big icon buttons for Story
## (the world map), Squad, Collection, Evolution, Fusion and Settings. Each button's subtitle shows
## live progress from the save. Navigation is injected (`nav`: action -> Callable) by ui.gd.
extends Control

const Palette = preload("res://scripts/theme_colors.gd")
const Data = preload("res://scripts/data_loader.gd")
const Assets = preload("res://scripts/assets.gd")
const Prog = preload("res://scripts/progression.gd")
const Kit = preload("res://scripts/ui/menu_kit.gd")
const Model = preload("res://scripts/ui/collection_model.gd")

const ACTIONS := ["story", "squad", "collection", "evolution", "fusion", "settings"]

var nav: Dictionary = {}          ## "story" -> Callable, ...
var progress: RefCounted          ## progress.gd
var buttons: Dictionary = {}      ## action -> Button
var _subs: Dictionary = {}        ## action -> Label (subtitle)


## Painted key art (cover) under a navy gradient + vignette, so text stays readable on any art.
class Backdrop extends Control:
	const UIA = preload("res://scripts/ui_art.gd")
	const Pal = preload("res://scripts/theme_colors.gd")
	var tex: Texture2D

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if tex != null:
			UIA.draw_cover(self, tex, r, 0.3)
		else:
			UIA.vgrad(self, r, Pal.MIDNIGHT_NAVY.lerp(Pal.CRYSTAL_VIOLET, 0.3), Pal.MIDNIGHT_NAVY)
			UIA.glow(self, Vector2(size.x * 0.5, size.y * 0.28), size.x * 0.7, Color(Pal.AETHER_CYAN, 0.35))
		UIA.vgrad(self, Rect2(Vector2.ZERO, Vector2(size.x, size.y * 0.34)), Color(Pal.MIDNIGHT_NAVY, 0.7), Color(Pal.MIDNIGHT_NAVY, 0.0))
		UIA.glow(self, Vector2(size.x * 0.5, size.y * 0.16), size.x * 0.42, Color(Pal.MIDNIGHT_NAVY, 0.55))
		UIA.vgrad(self, Rect2(Vector2(0, size.y * 0.36), Vector2(size.x, size.y * 0.24)), Color(Pal.MIDNIGHT_NAVY, 0.0), Color(Pal.MIDNIGHT_NAVY, 0.86))
		draw_rect(Rect2(Vector2(0, size.y * 0.6), Vector2(size.x, size.y * 0.4)), Color(Pal.MIDNIGHT_NAVY, 0.86))


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func build() -> void:
	var bg := Backdrop.new()
	bg.tex = Assets.title_backdrop()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 48)
	m.add_theme_constant_override("margin_top", 40)
	m.add_theme_constant_override("margin_bottom", 48)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(vb)
	var logo := Assets.ui("logo")
	if logo != null:
		var lr := TextureRect.new()
		lr.texture = logo
		lr.custom_minimum_size = Vector2(0, 500)
		lr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var key := ShaderMaterial.new()   # logos often arrive on black: key luminance to alpha
		key.shader = preload("res://scripts/luma_key.gdshader")
		lr.material = key
		vb.add_child(lr)
	else:
		var word := Kit.label("AETHER SIGIL", 112, Palette.SIGIL_GOLD.lerp(Palette.SOFT_SILVER, 0.25), true, HORIZONTAL_ALIGNMENT_CENTER)
		word.add_theme_constant_override("outline_size", 12)
		word.add_theme_color_override("font_shadow_color", Color(Palette.CRYSTAL_VIOLET, 0.6))
		word.add_theme_constant_override("shadow_offset_y", 4)
		word.custom_minimum_size = Vector2(0, 300)
		word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		vb.add_child(word)
	var tag := Kit.header(str(Data.bible().get("tagline", "")), 30)   # gold plaque: readable over any art
	tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(tag)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(spacer)
	_add(vb, "story", "Story", "menu", true)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	vb.add_child(grid)
	for a in ["squad", "collection", "evolution", "fusion"]:
		_add(grid, a, a.capitalize(), a, false)
	_add(vb, "settings", "Settings", "settings", false)
	buttons.settings.custom_minimum_size.y = 104


func _add(parent: Control, action: String, caption: String, _icon: String, primary: bool) -> void:
	var b := Kit.hub_button(caption, " ", action, _go.bind(action), primary)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	buttons[action] = b
	# the subtitle label is the second child of the caption column
	var col: VBoxContainer = b.get_child(0).get_child(1)
	if col.get_child_count() > 1:
		_subs[action] = col.get_child(1)


func _go(action: String) -> void:
	var cb: Callable = nav.get(action, Callable())
	if cb.is_valid():
		cb.call()


## Live subtitles from the save (stages cleared, collected count, evolutions ready ...).
func refresh() -> void:
	if progress == null:
		return
	var roster: Array = progress.roster
	var cleared: int = progress.cleared.size()
	var ready := roster.filter(func(i): return Prog.can_evolve(i) == Prog.OK).size()
	var F: Dictionary = Data.progression().fusion
	var fusable := roster.filter(func(i): return int(i.level) >= int(F.min_level)).size()
	var subs := {
		"story": "The Twelve Towers  -  %d / %d stages cleared" % [cleared, Data.stage_count()],
		"squad": "%d of %d monsters ready" % [progress.squad.size(), roster.size()],
		"collection": "%d / %d collected" % [Model.collected(roster).size(), Data.monster_ids().size()],
		"evolution": ("%d ready to evolve" % ready) if ready > 0 else "Lv %s forms" % "/".join(Data.progression().evolution.thresholds.map(func(x): return str(int(x)))),
		"fusion": ("%d can fuse (Lv%d+)" % [fusable, int(F.min_level)]),
		"settings": "Audio, motion, language",
	}
	for a in subs:
		if _subs.has(a):
			_subs[a].text = subs[a]


func play_enter() -> void:
	Kit.stagger(ACTIONS.map(func(a): return buttons.get(a)), 0.05)
