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
const Palette = preload("res://scripts/theme_colors.gd")
const Progress = preload("res://scripts/progress.gd")
const Art = preload("res://scripts/board_art.gd")

const AI_DELAY := 0.35
const FONT := 34
const SMALL := 22
const P := GameState.PLAYER
const E := GameState.ENEMY
const COMMANDS := ["Attack", "Skill", "Defend", "Wait"]

enum Mode { NONE, DEPLOY, UNIT, SKILL }


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
var board: BoardView
var stage_id := ""
var mode: Mode = Mode.NONE
var selected_mon := ""
var ai_running := false
var midbattle_shown := false
var _dialogue_queue: Array = []
var _dialogue_done: Callable

var ui_root: Control
var select_screen: Control
var stage_buttons: Dictionary = {}
var squad_screen: Control
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


func _ready() -> void:
	RenderingServer.set_default_clear_color(Palette.BG)
	Data.ensure_loaded()
	progress = Progress.new(save_path)
	state = GameState.new()
	board = BoardView.new()
	board.state = state
	board.visible = false
	add_child(board)
	_build_ui()
	get_viewport().size_changed.connect(_layout_board)
	show_stage_select()


# ---------------------------------------------------------------- widgets

func _style(bg: Color, edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(14)
	return sb


func _label(text: String, size: int, col: Color = Palette.TEXT, center: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, cb: Callable, min_h: float = 96) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", FONT - 8)
	b.add_theme_color_override("font_color", Palette.TEXT)
	b.add_theme_color_override("font_pressed_color", Palette.SIGIL_GOLD)
	b.add_theme_color_override("font_disabled_color", Palette.TEXT.darkened(0.55))
	b.add_theme_stylebox_override("normal", _style(Palette.panel(), Palette.panel_edge()))
	b.add_theme_stylebox_override("hover", _style(Palette.panel().lightened(0.06), Palette.AETHER_CYAN))
	b.add_theme_stylebox_override("pressed", _style(Palette.AETHER_CYAN.darkened(0.6), Palette.SIGIL_GOLD))
	b.add_theme_stylebox_override("disabled", _style(Palette.BG, Palette.panel()))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


func _panel(edge: Color = Palette.panel_edge()) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(Palette.panel(), edge))
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
	layer.add_child(ui_root)
	_build_select()
	_build_squad()
	_build_hud()
	_build_dialogue()
	_build_result()


func _build_select() -> void:
	select_screen = _full(MarginContainer.new())
	for side in ["left", "right", "top", "bottom"]:
		select_screen.add_theme_constant_override("margin_" + side, 32)
	ui_root.add_child(select_screen)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	select_screen.add_child(vb)
	vb.add_child(_label("AETHER SIGIL", 72, Palette.SIGIL_GOLD))
	vb.add_child(_label(str(Data.bible().get("tagline", "")), FONT - 4, Palette.AETHER_CYAN))
	vb.add_child(_button("Build Your Squad", show_squad_builder, 90))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)
	for t in Data.towers():
		var pnl := _panel()
		list.add_child(pnl)
		var tv := VBoxContainer.new()
		pnl.add_child(tv)
		tv.add_child(_label("Tower %s  %s  (%s)" % [t.tower_id, t.name, t.theme], FONT, Palette.SIGIL_GOLD))
		tv.add_child(_label(str(t.visual_direction), FONT - 12, Palette.TEXT.darkened(0.25)))
		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		tv.add_child(grid)
		for l in t.levels:
			var b := _button("", _on_stage_pressed.bind(str(l.stage_id)), 86)
			stage_buttons[str(l.stage_id)] = b
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
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	for id in Data.squad_collection():
		var m := Data.monster(id)
		var b := _button("%s  (%s %s %s)\nHP %d  ATK %d  DEF %d  MOVE %d  RANGE %d  Skill: %s" % [m.name, m.element, m.element_family, m.role,
			m.hp, m.attack, m.defense, m.move, m.range, m.ability], _on_squad_toggle.bind(str(id)), 110)
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", SMALL + 2)
		squad_buttons[str(id)] = b
		list.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	row.add_child(_button("Back", show_stage_select))
	squad_confirm = _button("Confirm squad", _on_squad_confirm)
	row.add_child(squad_confirm)
	squad_screen.visible = false


func _build_hud() -> void:
	hud = _full(Control.new())
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(hud)
	top_panel = _panel()
	hud.add_child(top_panel)
	_dock(top_panel, false)
	var tv := VBoxContainer.new()
	top_panel.add_child(tv)
	stage_label = _label("", FONT - 6, Palette.SIGIL_GOLD)
	tv.add_child(stage_label)
	status_label = _label("", SMALL + 2)
	tv.add_child(status_label)
	# Left: Turn Order.
	turn_panel = _panel()
	hud.add_child(turn_panel)
	_column(turn_panel, false, 300)
	var lv := VBoxContainer.new()
	turn_panel.add_child(lv)
	lv.add_child(_label("TURN ORDER", SMALL + 2, Palette.SIGIL_GOLD, false))
	order_box = VBoxContainer.new()
	order_box.add_theme_constant_override("separation", 2)
	lv.add_child(order_box)
	# Right: Tactical map + Objectives.
	side_panel = _panel()
	hud.add_child(side_panel)
	_column(side_panel, true, 330)
	var rv := VBoxContainer.new()
	side_panel.add_child(rv)
	rv.add_child(_label("TACTICAL MAP", SMALL + 2, Palette.SIGIL_GOLD, false))
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(300, 200)
	minimap.state = state
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.add_child(minimap)
	rv.add_child(_label("OBJECTIVES", SMALL + 2, Palette.SIGIL_GOLD, false))
	objectives_box = VBoxContainer.new()
	rv.add_child(objectives_box)
	# Bottom: info, Sigil squad, monster commands.
	bottom_panel = _panel()
	hud.add_child(bottom_panel)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 10)
	bottom_panel.add_child(bv)
	info_label = _label("", SMALL + 4)
	info_label.custom_minimum_size = Vector2(0, 70)
	bv.add_child(info_label)
	var team_row := HBoxContainer.new()
	team_row.add_theme_constant_override("separation", 8)
	bv.add_child(team_row)
	for i in Data.squad_size():
		var b := _button("", _on_team.bind(i), 100)
		b.add_theme_font_size_override("font_size", SMALL)
		team_buttons[i] = b
		team_row.add_child(b)
	var cmd_row := HBoxContainer.new()
	cmd_row.add_theme_constant_override("separation", 8)
	bv.add_child(cmd_row)
	for c in COMMANDS:
		var b := _button(c, _on_cmd.bind(c), 88)
		cmd_buttons[c] = b
		cmd_row.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bv.add_child(row)
	row.add_child(_button("Stages", show_stage_select, 76))
	_dock(bottom_panel, true)
	# Panels settle over a few frames (autowrapped labels); re-fit the board whenever they change.
	for c in [top_panel, turn_panel, side_panel, bottom_panel]:
		c.minimum_size_changed.connect(_layout_board)
		c.resized.connect(_layout_board)


func _build_dialogue() -> void:
	dialogue_box = _full(Control.new())
	ui_root.add_child(dialogue_box)
	var dim := _full(ColorRect.new())
	dim.color = Color(Palette.BG, 0.55)
	dialogue_box.add_child(dim)
	var pnl := _panel(Palette.SIGIL_GOLD)
	dialogue_box.add_child(pnl)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	pnl.add_child(v)
	dialogue_speaker = _label("", FONT, Palette.SIGIL_GOLD, false)
	v.add_child(dialogue_speaker)
	dialogue_text = _label("", FONT - 2, Palette.TEXT, false)
	dialogue_text.custom_minimum_size = Vector2(0, 120)
	v.add_child(dialogue_text)
	v.add_child(_button("Continue", _on_dialogue_next))
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
	var bs := board.board_size()
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


func show_stage_select() -> void:
	_hide_all()
	select_screen.visible = true
	for id in stage_buttons:
		var st := Data.stage(id)
		var b: Button = stage_buttons[id]
		var n := int(str(st.stage_id).right(2))
		var open := progress.is_unlocked(id)
		b.disabled = not open
		b.text = ("%d%s" % [n, " won" if progress.cleared.has(id) else ""]) if open else "Locked"
		if bool(st.get("boss", false)) and open:
			b.text += " Boss"


func show_squad_builder() -> void:
	_hide_all()
	squad_screen.visible = true
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
	state.setup(id, progress.squad)
	mode = Mode.NONE
	midbattle_shown = false
	board.visible = true
	hud.visible = true
	_refresh("")
	_layout_board.call_deferred()
	var st := state.stage
	var lines: Array = [str(st.dialogue.get("intro", ""))]
	if bool(st.get("boss", false)) and st.dialogue.has("boss_intro"):
		lines.append(str(st.dialogue.boss_intro))
	show_dialogue(lines, _continue)


func show_dialogue(lines: Array, done: Callable) -> void:
	_dialogue_queue = lines.filter(func(l): return str(l) != "")
	_dialogue_done = done
	if _dialogue_queue.is_empty():
		dialogue_box.visible = false
		done.call()
		return
	dialogue_box.visible = true
	_show_line()


func _show_line() -> void:
	var line := str(_dialogue_queue[0])
	var cut := line.find(": ")
	dialogue_speaker.text = line.substr(0, cut) if cut > 0 else str(state.stage.get("opponent", ""))
	dialogue_text.text = line.substr(cut + 2) if cut > 0 else line


func _on_dialogue_next() -> void:
	if not _dialogue_queue.is_empty():
		_dialogue_queue.pop_front()
	if _dialogue_queue.is_empty():
		dialogue_box.visible = false
		if _dialogue_done.is_valid():
			_dialogue_done.call()
		return
	_show_line()


func _show_result() -> void:
	var won := state.winner == P
	var how := {"symbol": "Symbol destroyed", "relics": "Relic nodes secured"}
	if won:
		var nxt := progress.record_win(stage_id)
		result_title.text = "Victory"
		result_sub.text = "%s. %s" % [how.get(state.win_reason, state.win_reason), ("Next: " + nxt) if nxt != "" else "All 120 stages cleared!"]
		next_button.visible = nxt != ""
	else:
		result_title.text = "Defeat" if state.winner == E else "Stalemate"
		result_sub.text = "Your Sigil fell" if state.winner == E else "Round cap reached"
		next_button.visible = false
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
	stage_label.text = "%s  |  %s  vs %s (%s)" % [state.stage_id, st.name, st.opponent, st.opponent_style]
	var extra := "   AP %d" % state.ap[P] if state.deploy_cost() > 0 else ""
	status_label.text = "Round %d   Rule: %s%s" % [state.round_num, st.special_rule, extra]
	for c in order_box.get_children():
		c.queue_free()
	var i := 1
	for id in state.order_preview(8):
		var col := Palette.side(_actor_side(id))
		if i == 1:
			col = Palette.SIGIL_GOLD
		order_box.add_child(_label("%d  %s" % [i, _actor_name(id)], SMALL, col, false))
		i += 1
	for c in objectives_box.get_children():
		c.queue_free()
	for o in state.objectives():
		var col := Palette.SIGIL_GOLD if o.kind == "win" else (Palette.AETHER_CYAN if o.kind == "loss" else Palette.TEXT)
		objectives_box.add_child(_label("%s %s (%s)" % ["[x]" if o.done else "[ ]", o.text, o.progress], SMALL - 2, col, false))
	var my_turn := _my_turn()
	var sigil_turn := my_turn and state.is_sigil_turn()
	var squad: Array = progress.squad
	for idx in team_buttons:
		var b: Button = team_buttons[idx]
		if idx >= squad.size():
			b.visible = false
			continue
		var id: String = squad[idx]
		var d := Data.monster(id)
		var waiting: bool = state.reserve[P].has(id)
		var can := sigil_turn and waiting and state.legal_deploys(P).any(func(a): return a.mon == id)
		b.text = "%s\n%s %d/%d/%d" % [str(d.name).left(10), str(d.element_family).left(5), d.hp, d.attack, d.defense] if waiting else "%s\n%s" % [str(d.name).left(10), "on board" if state.units_of(P).any(func(u): return u.mon_id == id) else "KO"]
		b.disabled = not can
		b.set_pressed_no_signal(mode == Mode.DEPLOY and selected_mon == id)
	var u := state.actor_unit() if my_turn else null
	cmd_buttons["Attack"].disabled = u == null or state.legal_attacks(u).is_empty()
	cmd_buttons["Skill"].disabled = u == null or state.legal_skill_targets(u).is_empty()
	cmd_buttons["Skill"].text = "Skill" if u == null else "Skill: %s" % u.ability
	cmd_buttons["Defend"].disabled = u == null
	cmd_buttons["Wait"].disabled = not my_turn
	cmd_buttons["Wait"].text = "End summons" if sigil_turn else "Wait"
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
	if _my_turn():
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

## Hands control to whoever acts next: the enemy AI (paced) or the player's active actor.
func _continue() -> void:
	if dialogue_box.visible or result_box.visible or not board.visible:
		return
	if state.winner != GameState.NONE or state.round_num > int(Data.rules().turn_cap_rounds):
		_end_battle()
		return
	if state.current == E:
		_run_ai()
		return
	if state.is_sigil_turn():
		mode = Mode.NONE
		var any := not state.legal_deploys(P).is_empty()
		_refresh("Your Sigil: tap a squad monster, then a cyan tile to summon it. Then End summons." if any else "Your Sigil: nothing to summon. Tap End summons.")
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
		if _midbattle_due():
			ai_running = false
			_show_midbattle()
			return
	ai_running = false
	_continue()


func _midbattle_due() -> bool:
	return not midbattle_shown and (state.kos[P] + state.kos[E] > 0 or state.symbol_hp[E] * 2 <= state.symbol_max)


func _show_midbattle() -> void:
	midbattle_shown = true
	show_dialogue([str(state.stage.dialogue.get("midbattle", ""))], _continue)


func _end_battle() -> void:
	_refresh()
	if state.winner == P:
		show_dialogue([str(state.stage.dialogue.get("defeat", ""))], _show_result)
	else:
		_show_result()


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
		start_stage(id)


func _on_reset_progress() -> void:
	progress.reset()
	show_stage_select()


func _on_team(idx: int) -> void:
	if not _my_turn() or not state.is_sigil_turn() or idx >= progress.squad.size():
		return
	mode = Mode.DEPLOY
	selected_mon = progress.squad[idx]
	_refresh("Tap a cyan tile to summon %s (spawn tiles and capsule nodes you activated)." % Data.monster(selected_mon).name)


func _on_cmd(c: String) -> void:
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
		"Wait":
			state.wait(P)
			_after_action(" ")


func _on_next() -> void:
	var nxt := Progress.next_stage_id(stage_id)
	if nxt != "" and progress.is_unlocked(nxt):
		start_stage(nxt)


func _on_retry() -> void:
	start_stage(stage_id)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if not board.visible or not _my_turn():
		return
	var tile: Variant = board.tile_at_local(board.to_local(event.position))
	if tile != null:
		_on_tile(tile)


func _on_tile(c: Vector2i) -> void:
	var u := state.actor_unit()
	match mode:
		Mode.DEPLOY:
			var r := state.deploy(P, selected_mon, c)
			mode = Mode.NONE
			_refresh("Summoned. It joins the turn order next round." if r == GameState.OK else "Can't summon there: " + r)
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
	if t != null:
		_refresh("%s %s (%s %s)  HP %d/%d  ATK %d DEF %d  Move %d Range %d  Skill %s%s" % [
			"Ally" if t.owner == P else "Enemy", t.name, t.element, t.role, t.hp, t.max_hp,
			t.attack, t.defense, t.move, t.attack_range, t.ability, "  (dormant statue)" if t.dormant else ""])
	else:
		var td := state.tile_type(c)
		_refresh("%s: %s" % [td, str(state.stage.get("map_legend", {}).get(td, ""))])
