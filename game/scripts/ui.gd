## Main scene controller: stage select / Build Your Squad -> dialogue -> battle HUD -> result.
## Initiative model: the active actor is shown in the Turn Order panel; on the Player Sigil's
## activation you capsule-summon squad monsters, on a monster's activation you Move then pick
## Attack / Skill / Defend / Wait. Taps go through GameState's legal-action API (same as the AI).
## Every Control is anchored or in a container; nothing sits at a fixed pixel position.
extends Node2D

const Data = preload("res://scripts/data_loader.gd")
const GameState = preload("res://scripts/game_state.gd")
const AI = preload("res://scripts/ai.gd")
const BoardView = preload("res://scripts/board_view.gd")
const Board3D = preload("res://scripts/board_3d.gd")
const Palette = preload("res://scripts/theme_colors.gd")
const Progress = preload("res://scripts/progress.gd")
const Art = preload("res://scripts/board_art.gd")
const Prog = preload("res://scripts/progression.gd")
const Story = preload("res://scripts/story.gd")
const UIArt = preload("res://scripts/ui_art.gd")
const Assets = preload("res://scripts/assets.gd")
const SkyBackdrop = preload("res://scripts/sky_backdrop.gd")
const Summon = preload("res://scripts/summon.gd")  # Vessels / SP / Bond (pre-match section at the end)
const Cinematic = preload("res://scripts/cinematic.gd")

signal evolved(uid: String, line: String)   ## hook for evolution dialogue/animation
signal fused(uid: String)

const AI_DELAY := 0.35
const FONT := 34
const SMALL := 22
const P := GameState.PLAYER
const E := GameState.ENEMY
const COMMANDS := ["Attack", "Skill", "Defend", "Wait"]

enum Mode { NONE, DEPLOY, UNIT, SKILL, PLACE }


## Story portrait: painted art per speaker (assets.gd), else a lit silhouette; drawing lives in ui_art.gd.
class Portrait extends Control:
	const PortraitArt = preload("res://scripts/ui_art.gd")
	var who := ""

	func _draw() -> void:
		PortraitArt.draw_portrait(self, Rect2(Vector2.ZERO, size), who)


## One Turn Order row: portrait chip (team slot frame + creature or Sigil), name, HP.
class OrderChip extends Control:
	const ChipArt = preload("res://scripts/ui_art.gd")
	const Pal = preload("res://scripts/theme_colors.gd")
	var idx := 1
	var side := 0
	var active := false
	var sigil := false
	var mon_id := ""
	var family := ""
	var role := ""
	var title := ""
	var sub := ""

	func _draw() -> void:
		var h := size.y
		if active:
			draw_rect(Rect2(Vector2(h * 0.5, 4), Vector2(size.x - h * 0.5, h - 8)), Color(Pal.side(side), 0.22))
			draw_rect(Rect2(Vector2(h * 0.5, 4), Vector2(size.x - h * 0.5, h - 8)), Color(Pal.SIGIL_GOLD, 0.8), false, 1.5)
		ChipArt.draw_chip(self, Rect2(Vector2.ZERO, Vector2(h, h)), idx, side, active, sigil, mon_id, family, role)
		var f := ChipArt.font(false, 700)
		var col := Pal.SIGIL_GOLD if active else Pal.side(side).lerp(Pal.SOFT_SILVER, 0.35)
		draw_string(f, Vector2(h + 10, h * 0.48), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - h - 14, 21, col)
		draw_string(ChipArt.font(), Vector2(h + 10, h * 0.84), sub, HORIZONTAL_ALIGNMENT_LEFT, size.x - h - 14, 15, Pal.SOFT_SILVER.darkened(0.25))


## World-map card art (behind the tower Button's border and caption).
class TowerArt extends Control:
	const CardArt = preload("res://scripts/ui_art.gd")
	var tid := ""
	var family := ""
	var open := false

	func _draw() -> void:
		CardArt.draw_tower_card(self, Rect2(Vector2.ZERO, size), tid, family, open)


## Tactical minimap: drawing lives in board_art.gd.
class Minimap extends Control:
	const MapArt = preload("res://scripts/board_art.gd")
	var state: RefCounted

	func _draw() -> void:
		if state != null:
			MapArt.draw_minimap(self, Rect2(Vector2.ZERO, size), state)


var save_path := Progress.DEFAULT_PATH   ## tests override before adding to the tree
var progress: Progress
var state: GameState
var board: Node2D                       ## board_3d.gd (HD-2D) or board_view.gd (2D fallback)
## "" = auto (3D in a window, 2D when headless), "2d" or "3d" to force (tests, --board-2d / --board-3d).
var board_mode := ""
var stage_id := ""
var mode: Mode = Mode.NONE
var selected_mon := ""
var ai_running := false
var midbattle_shown := false
var _dialogue_queue: Array = []
var _dialogue_done: Callable

var ui_root: Control
var select_screen: Control
var stage_buttons: Dictionary = {}       ## stage id -> Button (the open tower's 10 stages)
var tower_cards: Dictionary = {}         ## tower id -> Button on the world map
var tower_screen: Control
var tower_title: Label
var tower_note: Label
var tower_list: VBoxContainer
var current_tower := ""
var portrait: Portrait
var dialogue_skip: Button
var bark_label: Label
var barks: Dictionary = {}
var last_stars := 0
var squad_screen: Control
var squad_list: VBoxContainer
var evo_screen: Control
var evo_list: VBoxContainer
var evo_label: Label
var fusion_screen: Control
var fusion_list: VBoxContainer
var fusion_pick: Array = []
var fusion_buttons: Dictionary = {}
var fusion_preview_label: Label
var fusion_confirm: Button
var last_xp_text := ""
var last_levelups: Array = []    ## [{name, tex, level}] for the victory cinematic
var squad_buttons: Dictionary = {}
var squad_pick: Array = []
var squad_label: Label
var squad_confirm: Button
var hud: Control
var top_panel: Control
var turn_panel: Control
var side_panel: Control
var bottom_panel: Control
var stage_label: Label
var status_label: Label
var info_label: Label
var order_box: VBoxContainer
var objectives_box: VBoxContainer
var minimap: Minimap
var team_buttons: Dictionary = {}
var cmd_buttons: Dictionary = {}
var dialogue_box: Control
var dialogue_speaker: Label
var dialogue_text: Label
var result_box: Control
var result_title: Label
var result_sub: Label
var next_button: Button
var retry_button: Button
var backdrop: SkyBackdrop
var tower_art: Dictionary = {}           ## tower id -> TowerArt behind its card
var _type_tween: Tween
# Pre-match (Vessels): draft + placement. See the section at the end of this file.
var placing := false
var draft_screen: Control
var draft_list: VBoxContainer
var draft_label: Label
var draft_confirm: Button
var draft_buttons: Dictionary = {}
var draft_pick: Array = []
var draft_stage := ""
var _break_seen: Dictionary = {}


## Studio ident + title on a CanvasLayer over the built UI; it swallows input until tapped through.
## Only when this is the running main scene (tests and the demo recorder instantiate us themselves).
func _play_intro() -> void:
	var skip := get_tree().current_scene != self or DisplayServer.get_name() == "headless"
	if skip or "--no-intro" in OS.get_cmdline_user_args():
		return
	var intro: Node = preload("res://scenes/intro/intro_sequence.tscn").instantiate()
	intro.next_scene = ""
	add_child(intro)
	intro.finished.connect(intro.queue_free)


## The HD-2D 3D board unless forced off (board_mode, --board-2d, project setting
## aether_sigil/board_3d) or running headless (tests keep the 2D board unless they force "3d").
func use_3d_board() -> bool:
	if board_mode != "":
		return board_mode == "3d"
	var args := OS.get_cmdline_user_args()
	if "--board-2d" in args:
		return false
	if "--board-3d" in args:
		return true
	return DisplayServer.get_name() != "headless" and bool(ProjectSettings.get_setting("aether_sigil/board_3d", true))


func _ready() -> void:
	RenderingServer.set_default_clear_color(Palette.BG)
	Data.ensure_loaded()
	progress = Progress.new(save_path)
	state = GameState.new()
	var sky_layer := CanvasLayer.new()   # behind the board (layer 0) and the UI
	sky_layer.layer = -1
	add_child(sky_layer)
	backdrop = SkyBackdrop.new()
	sky_layer.add_child(backdrop)
	board = Board3D.new() if use_3d_board() else BoardView.new()
	board.state = state
	board.visible = false
	add_child(board)
	_build_ui()
	get_viewport().size_changed.connect(_layout_board)
	_play_intro()
	show_stage_select()


# ---------------------------------------------------------------- widgets

## Buttons and chips: navy fill, coloured border, chamfered corners (ui_art.gd).
func _style(bg: Color, edge: Color) -> StyleBoxFlat:
	return UIArt.chamfer(bg, edge, 2, 12)


## display = Cinzel (titles, names); otherwise the theme's Nunito body font.
func _label(text: String, size: int, col: Color = Palette.TEXT, center: bool = true, display: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Palette.MIDNIGHT_NAVY)
	l.add_theme_constant_override("outline_size", 6 if display else 3)
	if display:
		l.add_theme_font_override("font", UIArt.font(true, 700))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Gold section plaque ("TURN ORDER", "OBJECTIVES") with a Cinzel title.
func _header(text: String, size: int = SMALL + 2) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIArt.header_style())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(text, size, Palette.SIGIL_GOLD, false, true)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	p.add_child(l)
	return p


func _button(text: String, cb: Callable, min_h: float = 96) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", FONT - 8)
	b.add_theme_color_override("font_color", Palette.TEXT)
	b.add_theme_color_override("font_pressed_color", Palette.SIGIL_GOLD)
	b.add_theme_color_override("font_disabled_color", Palette.TEXT.darkened(0.55))
	var navy := Palette.MIDNIGHT_NAVY.lerp(Palette.SOFT_SILVER, 0.07)
	b.add_theme_stylebox_override("normal", _style(Color(navy, 0.94), Palette.SIGIL_GOLD.darkened(0.15)))
	b.add_theme_stylebox_override("hover", _style(Color(navy.lightened(0.06), 0.96), Palette.SIGIL_GOLD))
	b.add_theme_stylebox_override("pressed", _style(Palette.AETHER_CYAN.lerp(Palette.MIDNIGHT_NAVY, 0.62), Palette.AETHER_CYAN))
	b.add_theme_stylebox_override("hover_pressed", _style(Palette.AETHER_CYAN.lerp(Palette.MIDNIGHT_NAVY, 0.55), Palette.AETHER_CYAN))
	b.add_theme_stylebox_override("disabled", _style(Color(Palette.BG, 0.88), Palette.SOFT_SILVER.lerp(Palette.BG, 0.7)))
	b.add_theme_color_override("icon_disabled_color", Color(0.45, 0.47, 0.55, 0.7))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


func _panel(edge: Color = Palette.panel_edge()) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIArt.panel_style(Palette.SIGIL_GOLD if edge == Palette.panel_edge() else edge))
	return p


func _full(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


## Docks a panel to the top or bottom edge with a margin; it grows to its content's minimum height.
func _dock(c: Control, bottom: bool, margin: float = 16.0) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	c.anchor_top = 1.0 if bottom else 0.0
	c.anchor_bottom = c.anchor_top
	c.offset_left = margin
	c.offset_right = -margin
	c.offset_top = -margin if bottom else margin
	c.offset_bottom = c.offset_top
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END


## Pins a fixed-width column to the left or right edge, just under the top bar (set in _layout_board).
func _column(c: Control, right: bool, width: float) -> void:
	c.anchor_left = 1.0 if right else 0.0
	c.anchor_right = c.anchor_left
	c.anchor_top = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = -16.0 - width if right else 16.0
	c.offset_right = -16.0 if right else 16.0 + width
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root = _full(Control.new())
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = UIArt.theme(FONT)
	ui_root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	layer.add_child(ui_root)
	_build_select()
	_build_squad()
	_build_draft()
	_build_evolution()
	_build_fusion()
	_build_tower_screen()
	_build_hud()
	_build_dialogue()
	_build_result()


func _build_select() -> void:
	select_screen = _full(MarginContainer.new())
	for side in ["left", "right", "top", "bottom"]:
		select_screen.add_theme_constant_override("margin_" + side, 32)
	ui_root.add_child(select_screen)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	select_screen.add_child(vb)
	var logo := Assets.ui("logo")  # painted logo slot; else the Cinzel wordmark
	if logo != null:
		var lr := TextureRect.new()
		lr.texture = logo
		lr.custom_minimum_size = Vector2(0, 360)
		lr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var key := ShaderMaterial.new()  # logos often arrive on black: key luminance to alpha
		key.shader = preload("res://scripts/luma_key.gdshader")
		lr.material = key
		vb.add_child(lr)
	else:
		var word := _label("AETHER SIGIL", 104, Palette.SIGIL_GOLD.lerp(Palette.SOFT_SILVER, 0.25), true, true)
		word.add_theme_constant_override("outline_size", 12)
		word.add_theme_color_override("font_shadow_color", Color(Palette.CRYSTAL_VIOLET, 0.6))
		word.add_theme_constant_override("shadow_offset_y", 4)
		vb.add_child(word)
	var full_title := str(Data.bible().get("title", ""))
	if logo == null and full_title.contains(": "):
		vb.add_child(_label(full_title.split(": ", true, 1)[1].to_upper(), FONT - 8, Palette.SIGIL_GOLD, true, true))
	vb.add_child(_label(str(Data.bible().get("tagline", "")), FONT - 6, Palette.SOFT_SILVER))
	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 10)
	vb.add_child(meta_row)
	meta_row.add_child(_button("Squad", show_squad_builder, 90))
	meta_row.add_child(_button("Evolution", show_evolution, 90))
	meta_row.add_child(_button("Fusion", show_fusion, 90))
	var hdr := _header("WORLD MAP  -  THE TWELVE TOWERS", FONT - 6)
	hdr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(hdr)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for t in Data.towers():
		var tid := str(t.tower_id)
		var b := _button("", _on_tower_pressed.bind(tid), 300)
		b.add_theme_font_size_override("font_size", SMALL)
		b.add_theme_font_override("font", UIArt.font(true, 700))
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.add_theme_constant_override("icon_max_width", 46)
		b.add_theme_constant_override("h_separation", 2)
		var fam := tower_family(t)
		b.icon = Assets.element_icon(fam)
		var tex_path := "res://art/elements/%s.png" % fam.to_lower()
		if b.icon == null and ResourceLoader.exists(tex_path):
			b.icon = load(tex_path)
		var col := Palette.family(fam)
		var clear := Color(0, 0, 0, 0)
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var edge: Color = {"normal": Palette.SIGIL_GOLD.darkened(0.1), "hover": Palette.SIGIL_GOLD.lerp(Palette.SOFT_SILVER, 0.4),
				"pressed": col, "hover_pressed": col, "disabled": Palette.SOFT_SILVER.lerp(Palette.BG, 0.6)}[st]
			var sb := UIArt.chamfer(clear, edge, 3, 18, false)
			sb.content_margin_top = 168
			sb.content_margin_bottom = 10
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_color_override("font_disabled_color", Palette.SOFT_SILVER.darkened(0.35))
		b.clip_contents = true
		var art := TowerArt.new()
		art.tid = tid
		art.family = fam
		art.show_behind_parent = true
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.add_child(art)
		tower_art[tid] = art
		tower_cards[tid] = b
		grid.add_child(b)
	vb.add_child(_button("Reset progress", _on_reset_progress, 76))


func _build_squad() -> void:
	squad_screen = _full(MarginContainer.new())
	for side in ["left", "right", "top", "bottom"]:
		squad_screen.add_theme_constant_override("margin_" + side, 32)
	ui_root.add_child(squad_screen)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	squad_screen.add_child(vb)
	vb.add_child(_label("BUILD YOUR SQUAD", 56, Palette.SIGIL_GOLD))
	squad_label = _label("", FONT - 6, Palette.AETHER_CYAN)
	vb.add_child(squad_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	squad_list = VBoxContainer.new()
	squad_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	squad_list.add_theme_constant_override("separation", 10)
	scroll.add_child(squad_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	row.add_child(_button("Back", show_stage_select))
	squad_confirm = _button("Confirm squad", _on_squad_confirm)
	row.add_child(squad_confirm)
	squad_screen.visible = false


func _meta_screen(title: String) -> Array:
	var screen := _full(MarginContainer.new())
	for side in ["left", "right", "top", "bottom"]:
		screen.add_theme_constant_override("margin_" + side, 32)
	ui_root.add_child(screen)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	screen.add_child(vb)
	vb.add_child(_label(title, 56, Palette.SIGIL_GOLD))
	var note := _label("", FONT - 8, Palette.AETHER_CYAN)
	vb.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	screen.visible = false
	return [screen, vb, list, note]


func _build_evolution() -> void:
	var parts := _meta_screen("EVOLUTION")
	evo_screen = parts[0]
	evo_list = parts[2]
	evo_label = parts[3]
	parts[1].add_child(_button("Back", show_stage_select, 90))


func show_evolution(msg: String = "") -> void:
	_hide_all()
	evo_screen.visible = true
	evo_label.text = msg if msg != "" else "Monsters evolve at Lv%s into the next form of their family." % "/".join(Data.progression().evolution.thresholds.map(func(x): return str(int(x))))
	for c in evo_list.get_children():
		c.queue_free()
	for inst in progress.roster:
		var row := _panel()
		evo_list.add_child(row)
		var v := VBoxContainer.new()
		row.add_child(v)
		v.add_child(_label(_inst_text(inst), SMALL + 2, Palette.TEXT, false))
		var why := Prog.can_evolve(inst)
		var nxt := Prog.next_form(inst)
		var need := Prog.evolve_level(inst)
		var req := "Next: %s at Lv%d" % [Data.monster(nxt).name, need] if nxt != "" and need > 0 else ("Final form" if not Prog.is_fused(inst) else "Fused monsters do not evolve")
		v.add_child(_label(req, SMALL, Palette.SIGIL_GOLD, false))
		var b := _button("Evolve" if why == Prog.OK else "Evolve (%s)" % why.replace("_", " "), _on_evolve.bind(str(inst.uid)), 76)
		b.disabled = why != Prog.OK
		v.add_child(b)


func _on_evolve(uid: String) -> void:
	var before := progress.get_inst(uid).duplicate()
	var line := progress.evolve(uid)
	if line == "":
		return
	evolved.emit(uid, line)
	show_evolution(line)
	var after := progress.get_inst(uid)
	Cinematic.play(self, "evolution", {"from_tex": Cinematic.art(str(before.get("form_id", ""))), "to_tex": Cinematic.art(str(after.get("form_id", ""))),
		"from_name": str(before.get("name", "")), "to_name": str(after.get("name", "")),
		"family": str(Data.monster(str(after.get("form_id", ""))).get("element_family", "Light"))})
	var tw := create_tween()  # evolution animation hook: a gold flash on the screen
	evo_screen.modulate = Palette.SIGIL_GOLD
	tw.tween_property(evo_screen, "modulate", Color.WHITE, 0.6)


func _build_fusion() -> void:
	var parts := _meta_screen("FUSION")
	fusion_screen = parts[0]
	fusion_list = parts[2]
	var vb: VBoxContainer = parts[1]
	parts[3].text = "Pick 2 monsters (both are consumed). Preview first, then confirm."
	var pnl := _panel(Palette.CRYSTAL_VIOLET)
	vb.add_child(pnl)
	fusion_preview_label = _label("", SMALL + 2, Palette.TEXT, false)
	pnl.add_child(fusion_preview_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	row.add_child(_button("Back", show_stage_select, 90))
	fusion_confirm = _button("Confirm fusion", _on_fusion_confirm, 90)
	row.add_child(fusion_confirm)


func show_fusion() -> void:
	_hide_all()
	fusion_screen.visible = true
	fusion_pick = []
	for c in fusion_list.get_children():
		c.queue_free()
	fusion_buttons = {}
	for inst in progress.roster:
		var b := _button(_inst_text(inst), _on_fusion_toggle.bind(str(inst.uid)), 100)
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", SMALL + 2)
		fusion_buttons[str(inst.uid)] = b
		fusion_list.add_child(b)
	_refresh_fusion()


func _on_fusion_toggle(uid: String) -> void:
	if fusion_pick.has(uid):
		fusion_pick.erase(uid)
	elif fusion_pick.size() < 2:
		fusion_pick.append(uid)
	_refresh_fusion()


## Preview Fusion: the exact monster Confirm will create.
func _refresh_fusion() -> void:
	for uid in fusion_buttons:
		fusion_buttons[uid].set_pressed_no_signal(fusion_pick.has(uid))
	fusion_confirm.disabled = true
	if fusion_pick.size() < 2:
		fusion_preview_label.text = "Preview: pick %d more." % (2 - fusion_pick.size())
		return
	var res := progress.fusion_preview(fusion_pick[0], fusion_pick[1])
	if res.has("error"):
		fusion_preview_label.text = "Can't fuse: %s" % str(res.error).replace("_", " ")
		return
	fusion_preview_label.text = "Preview:  %s + %s  ->  %s\n%s" % [res.parent_names[0], res.parent_names[1], res.name, _inst_text(res)]
	fusion_confirm.disabled = false


func _on_fusion_confirm() -> void:
	if fusion_pick.size() != 2:
		return
	var pa := progress.get_inst(fusion_pick[0]).duplicate()
	var pb := progress.get_inst(fusion_pick[1]).duplicate()
	var res := progress.fuse(fusion_pick[0], fusion_pick[1])
	if res.has("error"):
		fusion_preview_label.text = "Can't fuse: %s" % res.error
		return
	# a fused monster has no bible form of its own: it is revealed in its primary parent's likeness
	var a_tex := Cinematic.art(str(pa.get("form_id", "")))
	var to_tex := Cinematic.art(str(res.get("form_id", ""))) if Data.has_monster(str(res.get("form_id", ""))) else null
	Cinematic.play(self, "fusion", {"a_tex": a_tex, "b_tex": Cinematic.art(str(pb.get("form_id", ""))),
		"to_tex": to_tex if to_tex != null else a_tex, "a_name": str(pa.get("name", "")), "b_name": str(pb.get("name", "")), "to_name": str(res.get("name", "")),
		"family": str(res.get("element_family", "Arcane"))})
	fused.emit(str(res.uid))
	show_fusion()
	fusion_preview_label.text = Story.template("new_monster").format({"name": res.name})


func _notification(what: int) -> void:
	# Autosave when the app is paused, backgrounded or closed.
	if progress != null and what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		progress.save()


## Tower theme -> element family for its icon and colour (game_rules.json tower_theme_family).
static func tower_family(t: Dictionary) -> String:
	return str(Data.rules().get("tower_theme_family", {}).get(str(t.get("theme", "")), "Light"))


## Bible tower entry by id ({} if unknown).
static func _tower(tid: String) -> Dictionary:
	for t in Data.towers():
		if str(t.tower_id) == tid:
			return t
	return {}


func _build_tower_screen() -> void:
	var parts := _meta_screen("TOWER")
	tower_screen = parts[0]
	tower_title = parts[0].get_child(0).get_child(0)
	tower_note = parts[3]
	tower_list = parts[2]
	parts[1].add_child(_button("World map", show_stage_select, 90))


func show_tower(tid: String) -> void:
	_hide_all()
	tower_screen.visible = true
	current_tower = tid
	var t: Dictionary = {}
	for tw in Data.towers():
		if str(tw.tower_id) == tid:
			t = tw
	var pr := progress.tower_progress(tid)
	tower_title.text = "TOWER %s  %s" % [tid, str(t.name).to_upper()]
	tower_note.text = "%s  |  %d/10 cleared  |  Stars %d/%d\nChampion: %s  |  Reward: %s" % [t.theme, pr.cleared, pr.stars, pr.max_stars, t.tower_boss, t.tower_reward]
	for c in tower_list.get_children():
		c.queue_free()
	stage_buttons = {}
	for l in t.levels:
		var sid := str(l.stage_id)
		var open := progress.is_unlocked(sid)
		var stars := int(progress.stars.get(sid, 0))
		var txt := "%s  %s\nvs %s (%s)  |  %s%s" % [sid.right(3), l.name, l.opponent, l.opponent_style,
			("Stars %d/3" % stars) if progress.cleared.has(sid) else "Not cleared", "  |  BOSS" if bool(l.get("boss", false)) else ""]
		var b := _button(txt if open else "%s  Locked" % sid.right(3), _on_stage_pressed.bind(sid), 100)
		b.add_theme_font_size_override("font_size", SMALL + 2)
		b.disabled = not open
		stage_buttons[sid] = b
		tower_list.add_child(b)


func _on_tower_pressed(tid: String) -> void:
	if not progress.tower_unlocked(tid):
		return
	show_tower(tid)
	_play_story("arrival_" + tid, func(): pass)


## Plays a story sequence once (seen-flag in the save); skipping counts as seen.
func _play_story(key: String, done: Callable) -> bool:
	if progress.is_seen(key):
		done.call()
		return false
	progress.mark_seen(key)
	show_dialogue(Story.lines(key), done)
	return true


func _on_dialogue_tap(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_on_dialogue_next()


func _on_dialogue_skip() -> void:
	_dialogue_queue = []
	_finish_dialogue()


func _finish_dialogue() -> void:
	dialogue_box.visible = false
	if _dialogue_done.is_valid():
		var cb := _dialogue_done
		_dialogue_done = Callable()
		cb.call()


## Battle barks (one-line toasts): battle_start, low_hp, rival knockout, enemy Symbol exposed.
func _check_barks() -> void:
	if state.stage.is_empty() or state.winner != GameState.NONE:
		return
	var rival := str(state.stage.opponent)
	var low := int(Data.triggers().get("low_hp_pct", 50))
	var fire := func(key: String, n: int) -> void:
		if not barks.has(key):
			barks[key] = true
			var d := Story.global_line(n, rival)
			bark_label.text = "%s: %s" % [d.speaker, d.line]
	if not barks.has("battle_start"):  # the first check of a battle (faster enemy statues may act first)
		fire.call("battle_start", 1)
	if state.symbol_hp[P] * 100 < low * state.symbol_max:
		fire.call("low_hp", 3)
	if state.kos[P] > 0:
		fire.call("rival_ko", 4)
	if state.symbol_hp[E] * 2 <= state.symbol_max:
		fire.call("boss_phase", 5)


func _build_hud() -> void:
	hud = _full(Control.new())
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(hud)
	top_panel = _panel()
	hud.add_child(top_panel)
	_dock(top_panel, false)
	var tv := VBoxContainer.new()
	top_panel.add_child(tv)
	tv.add_theme_constant_override("separation", 2)
	stage_label = _label("", FONT - 4, Palette.SIGIL_GOLD, true, true)
	tv.add_child(stage_label)
	status_label = _label("", SMALL + 2)
	tv.add_child(status_label)
	bark_label = _label("", SMALL, Palette.AETHER_CYAN)
	tv.add_child(bark_label)
	# Left: Turn Order (portrait chips).
	turn_panel = _panel()
	hud.add_child(turn_panel)
	_column(turn_panel, false, 330)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	turn_panel.add_child(lv)
	lv.add_child(_header("TURN ORDER"))
	order_box = VBoxContainer.new()
	order_box.add_theme_constant_override("separation", 4)
	lv.add_child(order_box)
	# Right: Tactical map + Objectives.
	side_panel = _panel()
	hud.add_child(side_panel)
	_column(side_panel, true, 340)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	side_panel.add_child(rv)
	rv.add_child(_header("TACTICAL MAP"))
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(290, 190)
	minimap.state = state
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.add_child(minimap)
	rv.add_child(_header("OBJECTIVES"))
	objectives_box = VBoxContainer.new()
	objectives_box.add_theme_constant_override("separation", 2)
	rv.add_child(objectives_box)
	# Bottom: info, Sigil squad, monster commands.
	bottom_panel = _panel()
	hud.add_child(bottom_panel)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 10)
	bottom_panel.add_child(bv)
	var cmd_hdr := _header("MONSTER COMMAND")
	cmd_hdr.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bv.add_child(cmd_hdr)
	info_label = _label("", SMALL + 4)
	info_label.custom_minimum_size = Vector2(0, 64)
	bv.add_child(info_label)
	var team_row := HBoxContainer.new()
	team_row.add_theme_constant_override("separation", 8)
	bv.add_child(team_row)
	for i in Data.squad_size():
		var b := _button("", _on_team.bind(i), 100)
		b.add_theme_font_size_override("font_size", SMALL)
		b.add_theme_constant_override("icon_max_width", 64)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		team_buttons[i] = b
		team_row.add_child(b)
	var cmd_row := HBoxContainer.new()
	cmd_row.add_theme_constant_override("separation", 8)
	bv.add_child(cmd_row)
	for c in COMMANDS:
		var b := _button(c, _on_cmd.bind(c), 88)
		b.icon = Assets.ui("buttons/btn_%s_normal" % c.to_lower())
		b.add_theme_constant_override("icon_max_width", 60)
		b.add_theme_font_size_override("font_size", SMALL + 2)
		b.add_theme_font_override("font", UIArt.font(true, 700))
		cmd_buttons[c] = b
		cmd_row.add_child(b)
	var stages := _button("Stages", show_stage_select, 88)
	stages.size_flags_horizontal = Control.SIZE_FILL
	stages.custom_minimum_size.x = 150
	stages.add_theme_font_size_override("font_size", SMALL)
	cmd_row.add_child(stages)
	_dock(bottom_panel, true)
	# Panels settle over a few frames (autowrapped labels); re-fit the board whenever they change.
	for c in [top_panel, turn_panel, side_panel, bottom_panel]:
		c.minimum_size_changed.connect(_layout_board)
		c.resized.connect(_layout_board)


func _build_dialogue() -> void:
	dialogue_box = _full(Control.new())
	ui_root.add_child(dialogue_box)
	var dim := _full(ColorRect.new())
	dim.color = Color(Palette.BG, 0.42)
	dim.gui_input.connect(_on_dialogue_tap)  # tap anywhere to advance
	dialogue_box.add_child(dim)
	var pnl := PanelContainer.new()
	pnl.add_theme_stylebox_override("panel", UIArt.panel_style(Palette.SIGIL_GOLD, 1.0))
	pnl.gui_input.connect(_on_dialogue_tap)
	dialogue_box.add_child(pnl)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pnl.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	v.add_child(row)
	portrait = Portrait.new()
	portrait.custom_minimum_size = Vector2(230, 230)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 10)
	row.add_child(tv)
	var plate := _header("")  # name plate: gold plaque with the speaker's name in Cinzel
	plate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	plate.get_child(0).free()
	dialogue_speaker = _label("", FONT, Palette.SIGIL_GOLD, false, true)
	dialogue_speaker.autowrap_mode = TextServer.AUTOWRAP_OFF
	plate.add_child(dialogue_speaker)
	tv.add_child(plate)
	dialogue_text = _label("", FONT - 4, Palette.TEXT, false)
	dialogue_text.custom_minimum_size = Vector2(0, 150)
	dialogue_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING  # typewriter keeps the layout
	tv.add_child(dialogue_text)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 12)
	v.add_child(brow)
	dialogue_skip = _button("Skip", _on_dialogue_skip, 80)
	brow.add_child(dialogue_skip)
	brow.add_child(_button("Continue", _on_dialogue_next, 80))
	_dock(pnl, true, 24.0)
	dialogue_box.visible = false


func _build_result() -> void:
	result_box = _full(CenterContainer.new())
	ui_root.add_child(result_box)
	var pnl := _panel(Palette.SIGIL_GOLD)
	pnl.custom_minimum_size = Vector2(760, 0)
	result_box.add_child(pnl)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	pnl.add_child(v)
	result_title = _label("", 72, Palette.SIGIL_GOLD)
	v.add_child(result_title)
	result_sub = _label("", FONT - 4)
	v.add_child(result_sub)
	next_button = _button("Next stage", _on_next)
	v.add_child(next_button)
	retry_button = _button("Retry", _on_retry)
	v.add_child(retry_button)
	v.add_child(_button("Stage select", show_stage_select))
	result_box.visible = false


## Side columns sit under the top bar; the board fills the band between them and the bottom bar.
func _layout_board() -> void:
	if top_panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var top_h := top_panel.get_combined_minimum_size().y + 16.0
	for c in [turn_panel, side_panel]:
		c.offset_top = top_h + 10.0
		c.offset_bottom = c.offset_top
	var band_top := top_h + 10.0 + maxf(turn_panel.get_combined_minimum_size().y, side_panel.get_combined_minimum_size().y) + 10.0
	var band_bottom := vp.y - bottom_panel.get_combined_minimum_size().y - 16.0 - 10.0
	if board.has_method("fit_band"):
		# the far corner of the island may rise into the gap between the two side columns
		var gl := turn_panel.get_global_rect()
		var gr := side_panel.get_global_rect()
		var gap := Rect2(gl.end.x + 8.0, top_h + 10.0, gr.position.x - gl.end.x - 16.0, band_top - top_h - 10.0)
		board.fit_band(Rect2(16.0, band_top, vp.x - 32.0, band_bottom - band_top), gap)
		return
	var bs: Vector2 = board.board_size()
	var fit := minf((vp.x - 32.0) / bs.x, (band_bottom - band_top) / bs.y)
	board.scale = Vector2.ONE * clampf(fit, 0.4, 1.15)
	board.position = Vector2(vp.x / 2.0, (band_top + band_bottom) / 2.0 + bs.y * board.scale.y * 0.04)


# ---------------------------------------------------------------- screens

func _hide_all() -> void:
	ai_running = false
	board.visible = false
	hud.visible = false
	dialogue_box.visible = false
	result_box.visible = false
	select_screen.visible = false
	squad_screen.visible = false
	draft_screen.visible = false
	placing = false
	evo_screen.visible = false
	fusion_screen.visible = false
	tower_screen.visible = false


## World map (title screen): 12 towers with lock state, x/10 and stars. Plays the prologue once.
func show_stage_select() -> void:
	_hide_all()
	select_screen.visible = true
	for t in Data.towers():
		var tid := str(t.tower_id)
		var b: Button = tower_cards[tid]
		var pr := progress.tower_progress(tid)
		var open := progress.tower_unlocked(tid)
		b.disabled = not open
		b.text = "T%s  %s\n%d/10   Stars %d/%d" % [tid, t.name, pr.cleared, pr.stars, pr.max_stars] if open else "T%s  %s\nLocked" % [tid, t.name]
		tower_art[tid].open = open
		tower_art[tid].queue_redraw()
	backdrop.set_tower("", "")
	_play_story("prologue", func(): pass)


## One line describing an owned monster (level, evolution, stats, skill).
func _inst_text(inst: Dictionary) -> String:
	var r := Prog.battle_record(inst)
	var extra := ""
	if Prog.is_fused(inst):
		extra = "  Fused (+%s affinity, also %s)" % [inst.secondary_family, inst.secondary_ability]
	return "%s  Lv%d/%d  %s %s %s %s\nHP %d  ATK %d  DEF %d  MOVE %d  RANGE %d  Skill: %s%s%s" % [inst.name, inst.level, Prog.level_cap(inst),
		r.rarity, r.element, r.element_family, r.role, r.hp, r.attack, r.defense, r.move, r.range, r.ability,
		"+%d" % r.skill_tier if r.skill_tier > 0 else "", extra]


func show_squad_builder() -> void:
	_hide_all()
	squad_screen.visible = true
	for c in squad_list.get_children():
		c.queue_free()
	squad_buttons = {}
	for inst in progress.roster:
		var b := _button(_inst_text(inst), _on_squad_toggle.bind(str(inst.uid)), 110)
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", SMALL + 2)
		squad_buttons[str(inst.uid)] = b
		squad_list.add_child(b)
	squad_pick = progress.squad.duplicate()
	_refresh_squad()


func _refresh_squad() -> void:
	for id in squad_buttons:
		squad_buttons[id].set_pressed_no_signal(squad_pick.has(id))
	squad_label.text = "Choose %d monsters: %d selected" % [Data.squad_size(), squad_pick.size()]
	squad_confirm.disabled = squad_pick.size() != Data.squad_size()


func _on_squad_toggle(id: String) -> void:
	if squad_pick.has(id):
		squad_pick.erase(id)
	elif squad_pick.size() < Data.squad_size():
		squad_pick.append(id)
	_refresh_squad()


func _on_squad_confirm() -> void:
	if progress.set_squad(squad_pick):
		progress.save()
		show_stage_select()


func start_stage(id: String) -> void:
	_hide_all()
	stage_id = id
	for inst in progress.roster:
		if str(inst.get("form_id", "")) != "":
			Assets.aliases[str(inst.uid)] = str(inst.form_id)
	state.setup(id, _default_draft(id), -1, _roster_records())
	_open_battle()


## The battle screen after setup / placement: HUD, intro dialogue, then play.
func _open_battle() -> void:
	_hide_all()
	_break_seen = {}
	mode = Mode.NONE
	midbattle_shown = false
	barks = {}
	bark_label.text = ""
	board.visible = true
	hud.visible = true
	backdrop.set_tower(str(state.stage.tower_id), tower_family(_tower(str(state.stage.tower_id))))
	_refresh("")
	_layout_board.call_deferred()
	var st := state.stage
	var seq: Array = []
	var tid := str(st.tower_id)
	if str(st.stage_id).right(3) == "L10" and not progress.is_seen("pre_boss_" + tid):
		progress.mark_seen("pre_boss_" + tid)
		seq += Story.lines("pre_boss_" + tid)
	seq.append(str(st.dialogue.get("intro", "")))                     # stage_intro
	if bool(st.get("boss", false)) and st.dialogue.has("boss_intro"):
		seq.append(str(st.dialogue.boss_intro))                       # boss_phase
	show_dialogue(seq, _continue)


## lines: "Speaker: text" strings or {speaker, line} dicts.
func show_dialogue(lines: Array, done: Callable) -> void:
	var rival := str(state.stage.get("opponent", "")) if not state.stage.is_empty() else ""
	_dialogue_queue = []
	for l in lines:
		var d: Dictionary = l if typeof(l) == TYPE_DICTIONARY else Story.split_line(str(l), rival)
		if str(d.get("line", "")) != "":
			_dialogue_queue.append(d)
	_dialogue_done = done
	if _dialogue_queue.is_empty():
		dialogue_box.visible = false
		done.call()
		return
	dialogue_box.visible = true
	_show_line()


func _show_line() -> void:
	var d: Dictionary = _dialogue_queue[0]
	dialogue_speaker.text = str(d.speaker)
	dialogue_text.text = str(d.line)
	portrait.who = str(d.speaker)
	portrait.queue_redraw()
	# Typewriter: the full text is set (tests and taps read it); only the reveal is animated, and
	# fast enough that the longest line is out well before a tap or the demo's 3 s per line.
	if _type_tween != null:
		_type_tween.kill()
	dialogue_text.visible_ratio = 0.0
	_type_tween = create_tween()
	_type_tween.tween_property(dialogue_text, "visible_ratio", 1.0, clampf(dialogue_text.text.length() * 0.014, 0.2, 1.6))


func _on_dialogue_next() -> void:
	if not dialogue_box.visible:
		return
	if not _dialogue_queue.is_empty():
		_dialogue_queue.pop_front()
	if _dialogue_queue.is_empty():
		_finish_dialogue()
		return
	_show_line()


func _show_result() -> void:
	var won := state.winner == P
	var how := {"symbol": "Symbol destroyed", "relics": "Relic nodes secured", "rout": "Enemy routed: no monster or %s left" % Summon.term("vessel"), "time": "Round limit: your Sigil held more HP"}
	if won:
		var nxt := progress.record_win(stage_id)
		result_title.text = "Victory"
		result_sub.text = "%s. Stars %d/3. %s" % [how.get(state.win_reason, state.win_reason), last_stars, ("Next: " + nxt) if nxt != "" else "All 120 stages cleared!"]
		next_button.visible = nxt != ""
		Cinematic.play(self, "victory", {"stars": last_stars, "levelups": last_levelups.slice(0, 4)})
	else:
		result_title.text = "Defeat" if state.winner == E else "Stalemate"
		var lost := {"symbol": "Your Sigil fell", "relics": "The enemy secured the relic nodes", "rout": "Routed: no monster or %s left" % Summon.term("vessel"), "time": "Round limit: the enemy Sigil held more HP"}
		result_sub.text = str(lost.get(state.win_reason, state.win_reason)) if state.winner == E else "Round limit reached with equal Sigil HP (draw)"
		next_button.visible = false
	if last_xp_text != "":
		result_sub.text += "\n" + last_xp_text
	result_box.visible = true


# ---------------------------------------------------------------- HUD refresh

func _actor_name(id: int) -> String:
	if GameState.is_sigil(id):
		return "Player Sigil" if id == GameState.sigil_id(P) else "Enemy Sigil"
	var u := state.get_unit(id)
	return "?" if u == null else "%s%s" % [u.name, " (statue)" if u.dormant else ""]


func _actor_side(id: int) -> int:
	if GameState.is_sigil(id):
		return P if id == GameState.sigil_id(P) else E
	var u := state.get_unit(id)
	return GameState.NONE if u == null else u.owner


func _refresh(msg: String = "") -> void:
	if state.stage.is_empty():
		return
	var st := state.stage
	stage_label.text = "%s  |  %s" % [state.stage_id, st.name]
	var extra := "   %s %d/%d (+%d next turn)" % [Summon.term("sp"), state.sp[P], state.sp_cap(), state.sp_income(P)]
	status_label.text = "vs %s (%s)   Round %d/%d
Rule: %s%s" % [st.opponent, st.opponent_style, state.round_num, GameState.turn_cap(), st.special_rule, extra]
	_vessel_hooks()
	for c in order_box.get_children():
		c.queue_free()
	var i := 1
	for id in state.order_preview(8):
		var chip := OrderChip.new()
		chip.custom_minimum_size = Vector2(0, 52)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.idx = i
		chip.active = i == 1
		chip.side = maxi(0, _actor_side(id))
		chip.title = _actor_name(id)
		if GameState.is_sigil(id):
			chip.sigil = true
			chip.sub = "Sigil  HP %d/%d" % [state.symbol_hp[chip.side], state.symbol_max]
		else:
			var u := state.get_unit(id)
			if u != null:
				chip.mon_id = u.mon_id
				chip.family = u.family
				chip.role = u.role
				chip.title = u.name
				chip.sub = "%s %s  HP %d/%d%s" % [u.element, u.role, u.hp, u.max_hp, "  statue" if u.dormant else ""]
		order_box.add_child(chip)
		i += 1
	for c in objectives_box.get_children():
		c.queue_free()
	for o in state.objectives():
		var col := Palette.SIGIL_GOLD if o.kind == "win" else (Palette.AETHER_CYAN if o.kind == "loss" else Palette.TEXT)
		var orow := HBoxContainer.new()
		orow.add_theme_constant_override("separation", 8)
		orow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := TextureRect.new()
		box.texture = Assets.ui("objective/checkbox_%s" % ("checked" if o.done else "unchecked"))
		box.custom_minimum_size = Vector2(26, 26)
		box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		box.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		orow.add_child(box)
		var ol := _label("%s%s (%s)" % ["" if box.texture != null else ("[x] " if o.done else "[ ] "), o.text, o.progress], SMALL - 2, col, false)
		ol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		orow.add_child(ol)
		objectives_box.add_child(orow)
	var my_turn := _my_turn()
	var sigil_turn := my_turn and state.is_sigil_turn()
	var squad: Array = state.team  # the Vessel tray: this match's drafted Vessels
	for idx in team_buttons:
		var b: Button = team_buttons[idx]
		if idx >= squad.size():
			b.visible = false
			continue
		var id: String = squad[idx]
		var d: Dictionary = state.custom.get(id, Data.monster(id))
		var waiting: bool = state.reserve[P].has(id)
		var can := sigil_turn and waiting and state.legal_deploys(P).any(func(a): return a.mon == id)
		if placing:
			can = waiting and state.capsule_of(P, id).get("pos", Vector2i.ZERO) == Vector2i(-1, -1) and state.placement_side() == P and state.placement_step() == "vessel"
		b.text = _tray_text(id, d, waiting)
		b.disabled = not can
		b.set_pressed_no_signal(mode == Mode.DEPLOY and selected_mon == id)
		var art := Assets.monster(id, str(d.element_family))
		b.icon = art if art != null else Assets.silhouette(str(d.get("role", "")))
		var fc := Palette.family(str(d.element_family))
		b.add_theme_color_override("icon_normal_color", Color.WHITE if art != null else Palette.SOFT_SILVER.lerp(fc, 0.45))
		b.add_theme_color_override("icon_hover_color", Color.WHITE if art != null else Palette.SOFT_SILVER.lerp(fc, 0.3))
	var u := state.actor_unit() if my_turn else null
	cmd_buttons["Attack"].disabled = u == null or state.legal_attacks(u).is_empty()
	cmd_buttons["Skill"].disabled = u == null or state.legal_skill_targets(u).is_empty()
	cmd_buttons["Skill"].text = "Skill" if u == null else "Skill: %s" % u.ability
	cmd_buttons["Defend"].disabled = u == null and not sigil_turn
	cmd_buttons["Wait"].disabled = not my_turn and not placing
	cmd_buttons["Wait"].text = "Start battle" if placing else ("End turn" if sigil_turn else "Wait")
	if msg != "":
		info_label.text = msg
	_update_highlights()
	board.queue_redraw()
	minimap.queue_redraw()


func _my_turn() -> bool:
	return state.current == P and state.winner == GameState.NONE and not ai_running and not dialogue_box.visible and not result_box.visible


func _update_highlights() -> void:
	var h := {}
	board.selected = null
	var u := state.actor_unit()
	if u != null:
		board.selected = u.pos
	if placing:
		_placement_highlights(h)
	elif _my_turn():
		if state.is_sigil_turn() and mode != Mode.DEPLOY:
			for c in state.sigil_moves(P):
				h[c] = Palette.AETHER_CYAN
		match mode:
			Mode.DEPLOY:
				for a in state.legal_deploys(P):
					if a.mon == selected_mon:
						h[a.tile] = Palette.AETHER_CYAN
			Mode.UNIT:
				if u != null:
					for c in state.legal_moves(u):
						h[c] = Palette.AETHER_CYAN
					for c in state.legal_attacks(u):
						h[c] = Palette.EMBER
			Mode.SKILL:
				if u != null:
					for c in state.legal_skill_targets(u):
						h[c] = Palette.CRYSTAL_VIOLET
	board.highlights = h


# ---------------------------------------------------------------- flow

func _continue() -> void:
	if dialogue_box.visible or result_box.visible or not board.visible or placing:
		return
	if state.is_over():
		_end_battle()
		return
	_check_barks()
	if state.current == E:
		_run_ai()
		return
	if state.is_sigil_turn():
		mode = Mode.NONE
		var any := not state.legal_deploys(P).is_empty()
		_refresh(("Your Sigil (%d %s): cyan = move 1 tile. Tap a %s in the tray, then its tile to Crack it. Or Defend / End turn." % [state.sp[P], Summon.term("sp"), Summon.term("vessel")]) if any else "Your Sigil (%d %s): cyan = move 1 tile, or Defend / End turn." % [state.sp[P], Summon.term("sp")])
	else:
		var u := state.actor_unit()
		mode = Mode.UNIT
		_refresh("%s (%s %s): cyan = move, ember = attack. Or Skill / Defend / Wait." % [u.name, u.element, u.role])


func _run_ai() -> void:
	ai_running = true
	_refresh("%s's turn..." % _actor_name(state.actor_id))
	while state.current == E and state.winner == GameState.NONE:
		await get_tree().create_timer(AI_DELAY).timeout
		if not ai_running or not board.visible:
			return
		AI.take_activation(state, E, str(state.stage.opponent_style))
		_refresh()
		await _anim_wait()
		if not ai_running or not board.visible:
			return
		_check_barks()
		if _midbattle_due():
			ai_running = false
			_show_midbattle()
			return
	ai_running = false
	_continue()


## knockout trigger: the stage's midbattle scene at the first knockout of the battle.
func _midbattle_due() -> bool:
	return not midbattle_shown and state.kos[P] + state.kos[E] > 0


func _show_midbattle() -> void:
	midbattle_shown = true
	await _anim_wait()
	show_dialogue([str(state.stage.dialogue.get("midbattle", ""))], _continue)


## Waits (up to `limit` s) for the 3D board's animation queue to drain. Returns at once on the 2D
## board and headless (the queue is instant there), so it never blocks game logic in tests.
func _anim_wait(limit := 8.0) -> void:
	if not board.has_method("anim_busy"):
		return
	var t0 := Time.get_ticks_msec()
	while board.visible and board.anim_busy() and Time.get_ticks_msec() - t0 < int(limit * 1000.0):
		await get_tree().process_frame


## victory / defeat / rare_drop / post_boss / finale / epilogue.
func _end_battle() -> void:
	var was_on := board.visible
	await _anim_wait()
	if was_on and not board.visible:
		return   # the player left the battle while the last blows played
	_refresh()
	var won := state.winner == P
	var gains := progress.award_battle(state, won)
	var parts := []
	last_levelups = []
	for uid in gains:
		var inst := progress.get_inst(uid)
		if gains[uid].levels > 0:
			last_levelups.append({"name": str(inst.name), "level": int(inst.level), "tex": Cinematic.art(str(inst.get("form_id", "")))})
		parts.append("%s +%d XP%s" % [inst.name, gains[uid].xp, (" (Lv%d)" % inst.level) if gains[uid].levels > 0 else ""])
	last_xp_text = ", ".join(parts)
	var rival := str(state.stage.opponent)
	var seq: Array = []
	if won:
		last_stars = Progress.battle_stars(state)
		progress.record_stars(stage_id, last_stars)
		seq.append(str(state.stage.dialogue.get("defeat", "")))      # victory: the rival concedes
		var tid := str(state.stage.tower_id)
		if stage_id.right(3) == "L10":
			seq.append(Story.global_line(6, rival))
			var reward := progress.grant_reward(stage_id)          # rare_drop
			if reward != "":
				seq.append({"speaker": Story.hero(), "line": Story.template("rare_drop").format({"reward": reward})})
			for key in ["post_boss_" + tid] + (["finale", "epilogue"] if tid == "12" else []):
				if not progress.is_seen(key):
					progress.mark_seen(key)
					seq += Story.lines(key)
	else:
		seq.append(Story.global_line(2, rival))                     # defeat: the rival gloats
	show_dialogue(seq, _show_result)


## After any player action: end, midbattle line, or carry on.
func _after_action(msg: String = "") -> void:
	_refresh(msg)
	if state.winner != GameState.NONE:
		_end_battle()
		return
	if _midbattle_due():
		_show_midbattle()
		return
	_continue()


# ---------------------------------------------------------------- input

func _on_stage_pressed(id: String) -> void:
	if progress.is_unlocked(id):
		show_prematch(id)


func _on_reset_progress() -> void:
	progress.reset()
	show_stage_select()


func _on_team(idx: int) -> void:
	if placing and idx < state.team.size():
		mode = Mode.PLACE
		selected_mon = state.team[idx]
		_refresh("Tap a gold tile to place this %s." % Summon.term("vessel"))
		return
	if not _my_turn() or not state.is_sigil_turn() or idx >= state.team.size():
		return
	mode = Mode.DEPLOY
	selected_mon = state.team[idx]
	_refresh("Tap a cyan tile to Crack %s for %d %s (its %s, or a capsule node you hold)." % [state.custom.get(selected_mon, Data.monster(selected_mon)).get("name", selected_mon), state.summon_cost(P, selected_mon), Summon.term("sp"), Summon.term("vessel")])


func _on_cmd(c: String) -> void:
	if placing:
		if c == "Wait":
			_start_placed_battle()
		return
	if not _my_turn():
		return
	var u := state.actor_unit()
	match c:
		"Attack":
			mode = Mode.UNIT
			_refresh("Tap an ember tile to attack.")
		"Skill":
			if u != null:
				mode = Mode.SKILL
				var sd := state.skill_def(u)
				_refresh("%s (%s): tap a violet tile." % [u.ability, sd.get("type", "")])
		"Defend":
			if u != null:
				state.defend(P, u.id)
				_after_action("%s defends." % u.name)
			elif state.is_sigil_turn():
				state.defend(P, GameState.sigil_id(P))
				_after_action("Your Sigil defends.")
		"Wait":
			state.wait(P)
			_after_action(" ")


func _on_next() -> void:
	var nxt := Progress.next_stage_id(stage_id)
	if nxt != "" and progress.is_unlocked(nxt):
		show_prematch(nxt)


## Retry: back to the pre-match with this match's draft preselected.
func _on_retry() -> void:
	var last: Array = state.team.duplicate()
	show_prematch(stage_id)
	if Summon.draft_check(last, Data.stage(stage_id), _roster_records()) == Summon.OK:
		draft_pick = last
		_refresh_draft()


func _unhandled_input(event: InputEvent) -> void:
	if board.has_method("handle_input"):  # 3D board: taps on release, drags pan / rotate
		if not board.visible:
			return
		var picked: Variant = board.handle_input(event)
		if picked != null and (_my_turn() or placing):
			_on_tile(picked)
		elif picked != null and board.has_method("skip_anim"):
			board.skip_anim()   # tap while the rival acts: skip the animation playing now
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if not board.visible or not (_my_turn() or placing):
		return
	var tile: Variant = board.tile_at_local(board.to_local(event.position))
	if tile != null:
		_on_tile(tile)


func _on_tile(c: Vector2i) -> void:
	if placing:
		_on_place_tile(c)
		return
	var u := state.actor_unit()
	if state.is_sigil_turn() and mode != Mode.DEPLOY and state.can_move_sigil(P, c) == GameState.OK:
		state.move_sigil(P, c)
		_refresh("Your Sigil moved. Crack a %s, Defend or End turn." % Summon.term("vessel"))
		return
	match mode:
		Mode.DEPLOY:
			var r := state.deploy(P, selected_mon, c)
			mode = Mode.NONE
			if r == GameState.OK:
				var cracked: GameState.Unit = state.get_unit(int(state.last_crack.unit))
				_after_action("Cracked! %s joins the end of this round." % cracked.name)  # _refresh fires board.play_summon
			else:
				_refresh("Can't Crack there: " + r)
			return
		Mode.SKILL:
			if u != null and state.can_skill(P, u.id, c) == GameState.OK:
				state.skill(P, u.id, c)
				_after_action("%s used %s." % [u.name, u.ability])
				return
		Mode.UNIT:
			if u != null and state.can_attack(P, u.id, c) == GameState.OK:
				var dmg := state.damage_preview(u, c)
				var chance := state.hit_chance(u, c)
				state.attack(P, u.id, c)
				_after_action("Attack (%d%% to hit, %d damage)." % [chance, dmg])
				return
			if u != null and state.can_move(P, u.id, c) == GameState.OK:
				state.move_unit(P, u.id, c)
				_refresh("Moved. Attack, Skill, Defend or Wait.")
				return
	var t := state.unit_at(c)
	if t == null and not state.capsule_at(c).is_empty():
		_refresh(_vessel_text(state.capsule_at(c)))
		return
	if t != null:
		_refresh("%s %s (%s %s)  HP %d/%d  ATK %d DEF %d  Move %d Range %d  Skill %s%s" % [
			"Ally" if t.owner == P else "Enemy", t.name, t.element, t.role, t.hp, t.max_hp,
			t.attack, t.defense, t.move, t.attack_range, t.ability, "  (dormant statue)" if t.dormant else ""])
	else:
		var td := state.tile_type(c)
		_refresh("%s: %s" % [td, str(state.stage.get("map_legend", {}).get(td, ""))])


# ---------------------------------------------------------------- pre-match: draft + placement (Vessels)
# Owner design 2026-10-21 (docs/SUMMON-POINTS.md): pick up to 6 Vessels under the tower's Bond
# cap, then place the Sigil and the Vessels on the home zone, alternating with the AI one at a
# time; the match starts with the Sigil and sealed Vessels on the board. start_stage(id) skips
# all of this (auto draft + auto placement) for tests, tools and the demo.

func _build_draft() -> void:
	var parts := _meta_screen("CHOOSE YOUR %s" % Summon.term("vessels").to_upper())
	draft_screen = parts[0]
	draft_list = parts[2]
	draft_label = parts[3]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parts[1].add_child(row)
	row.add_child(_button("Back", show_stage_select))
	draft_confirm = _button("Place %s" % Summon.term("vessels"), _on_draft_confirm)
	row.add_child(draft_confirm)


## Battle records for the whole owned roster (a draft may include monsters outside the saved squad).
func _roster_records() -> Dictionary:
	var out := {}
	for inst in progress.roster:
		out[str(inst.uid)] = Prog.battle_record(inst)
	return out


## The saved squad trimmed to the stage's Bond cap (strongest first).
func _default_draft(id: String) -> Array:
	return Summon.auto_draft(progress.squad, Data.stage(id), _roster_records(), func(u): return Prog.power(progress.get_inst(str(u))))


func show_prematch(id: String) -> void:
	_hide_all()
	draft_stage = id
	draft_screen.visible = true
	for c in draft_list.get_children():
		c.queue_free()
	draft_buttons = {}
	var recs := _roster_records()
	for inst in progress.roster:
		var uid := str(inst.uid)
		var r: Dictionary = recs[uid]
		var b := _button("%s\n%s %d   %s %d   %s %d HP" % [_inst_text(inst), Summon.term("bond"), Summon.bond(r), Summon.term("sp"), Summon.crack_cost(r), Summon.term("vessel"), Summon.vessel_hp(r)], _on_draft_toggle.bind(uid), 140)
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", SMALL + 2)
		draft_buttons[uid] = b
		draft_list.add_child(b)
	draft_pick = _default_draft(id)
	_refresh_draft()


func _refresh_draft() -> void:
	var st := Data.stage(draft_stage)
	var recs := _roster_records()
	for uid in draft_buttons:
		draft_buttons[uid].set_pressed_no_signal(draft_pick.has(uid))
	var why := Summon.draft_check(draft_pick, st, recs)
	draft_label.text = "%s: %s   |   %s %d / %d   |   %s %d / %d%s" % [draft_stage, str(st.get("name", "")), Summon.term("vessels"), draft_pick.size(), Data.squad_size(),
		Summon.term("bond"), Summon.total_bond(draft_pick, recs), Summon.draft_cap(st), "" if why == Summon.OK else "   (" + why.replace("_", " ") + ")"]
	draft_confirm.disabled = why != Summon.OK


func _on_draft_toggle(uid: String) -> void:
	if draft_pick.has(uid):
		draft_pick.erase(uid)
	elif draft_pick.size() < Data.squad_size():
		draft_pick.append(uid)
	_refresh_draft()


func _on_draft_confirm() -> void:
	if Summon.draft_check(draft_pick, Data.stage(draft_stage), _roster_records()) != Summon.OK:
		return
	_begin_placement(draft_stage, draft_pick.duplicate())


## Placement on the battle board: the state is in its placement phase; the AI plays its steps.
func _begin_placement(id: String, pick: Array) -> void:
	_hide_all()
	stage_id = id
	for inst in progress.roster:
		if str(inst.get("form_id", "")) != "":
			Assets.aliases[str(inst.uid)] = str(inst.form_id)
	state.setup(id, pick, -1, _roster_records(), false)
	placing = true
	mode = Mode.NONE
	selected_mon = ""
	board.visible = true
	hud.visible = true
	backdrop.set_tower(str(state.stage.tower_id), tower_family(_tower(str(state.stage.tower_id))))
	_layout_board.call_deferred()
	_advance_placement()


## Plays the enemy's placement steps (one at a time, alternating) and prompts the player.
func _advance_placement() -> void:
	while state.placement_side() == E:
		state.auto_place_step(E)
	var v := Summon.term("vessel")
	var msg := ""
	match state.placement_step():
		"sigil":
			msg = "Place your Sigil: tap a gold tile of your home zone (tap it where it stands to keep it)."
		"vessel":
			msg = "Place a %s: pick one in the tray (or just tap a gold tile for the next). At most %d next to your Sigil. %d left." % [v, int(Data.rules().placement.max_adjacent_to_sigil), state.unplaced_capsules(P).size()]
		_:
			msg = "All placed. Tap Start battle."
	_refresh(msg)


func _placement_highlights(h: Dictionary) -> void:
	if state.placement_side() != P:
		return
	for c in state.zone[P]:
		var ok := false
		if state.placement_step() == "sigil":
			ok = state.can_place_sigil(P, c) == GameState.OK
		else:
			var caps := state.unplaced_capsules(P)
			ok = not caps.is_empty() and state.can_place_capsule(P, str(caps[0].mon), c) == GameState.OK
		if ok:
			h[c] = Palette.SIGIL_GOLD


func _on_place_tile(c: Vector2i) -> void:
	if state.placement_side() != P:
		return
	var r := ""
	if state.placement_step() == "sigil":
		r = state.place_sigil(P, c)
	else:
		var mon := selected_mon
		if mon == "" or state.capsule_of(P, mon).get("pos", Vector2i.ZERO) != Vector2i(-1, -1):
			var caps := state.unplaced_capsules(P)
			mon = str(caps[0].mon) if not caps.is_empty() else ""
		r = state.place_capsule(P, mon, c)
	if r != GameState.OK:
		_refresh("Can't place there: " + r.replace("_", " "))
		return
	selected_mon = ""
	mode = Mode.NONE
	_advance_placement()


## Start battle: anything still unplaced is auto-placed, then the stage intro plays.
func _start_placed_battle() -> void:
	if not placing:
		return
	state.start_battle()
	placing = false
	_open_battle()


func _tray_text(id: String, d: Dictionary, waiting: bool) -> String:
	var nm := str(d.get("name", id)).left(10)
	if waiting:
		var cap := state.capsule_of(P, id)
		var where := "unplaced" if cap.get("pos", Vector2i.ZERO) == Vector2i(-1, -1) else ("%s %d/%d" % [Summon.term("vessel"), int(cap.hp), int(cap.max_hp)])
		return "%s  %d %s\n%s" % [nm, state.summon_cost(P, id), Summon.term("sp"), where]
	return "%s\n%s" % [nm, "on board" if state.units_of(P).any(func(u): return u.mon_id == id) else "lost"]


## Tap info for a sealed Vessel; enemy contents stay hidden (placement.enemy_contents_hidden).
func _vessel_text(cap: Dictionary) -> String:
	var mine := int(cap.owner) == P
	var hidden := not mine and bool(Data.rules().placement.get("enemy_contents_hidden", true))
	var nm := "sealed" if hidden else str(Summon.record_for(str(cap.mon), state.custom if mine else {}).get("name", cap.mon))
	return "%s %s (%s)  HP %d/%d%s" % ["Your" if mine else "Enemy", Summon.term("vessel"), nm, int(cap.hp), int(cap.max_hp),
		("  Crack: %d %s" % [state.summon_cost(P, str(cap.mon)), Summon.term("sp")]) if mine else ""]


## Animation hooks, fired once each from every _refresh (player and AI actions alike):
## board.play_summon(unit, sp_cost) for a new crack, board.play_vessel_break(vessel) for a break.
func _vessel_hooks() -> void:
	if not state.last_crack.is_empty() and not _break_seen.has("crack_%d" % int(state.last_crack.unit)):
		_break_seen["crack_%d" % int(state.last_crack.unit)] = true
		var u: GameState.Unit = state.get_unit(int(state.last_crack.unit))
		if u != null and board.has_method("play_summon"):
			board.play_summon(u, int(state.last_crack.cost))
	if state.last_break.is_empty() or _break_seen.has(state.last_break.hash()):
		return
	_break_seen[state.last_break.hash()] = true
	if board.has_method("play_vessel_break"):
		board.play_vessel_break(state.last_break)
