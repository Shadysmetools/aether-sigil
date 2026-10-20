## Main scene controller: stage select -> dialogue -> battle HUD -> result.
## Turns taps into GameState actions (the same legal-action API the AI uses) and runs the
## opponent's AI turn. Every Control is anchored or in a container; nothing is placed at a
## fixed pixel position, so the layout follows the portrait viewport (canvas_items stretch).
extends Node2D

const Data = preload("res://scripts/data_loader.gd")
const GameState = preload("res://scripts/game_state.gd")
const AI = preload("res://scripts/ai.gd")
const BoardView = preload("res://scripts/board_view.gd")
const Palette = preload("res://scripts/theme_colors.gd")
const Progress = preload("res://scripts/progress.gd")

const AI_DELAY := 0.5
const FONT := 34
const P := GameState.PLAYER
const E := GameState.ENEMY

enum Mode { NONE, DEPLOY, UNIT }

var save_path := Progress.DEFAULT_PATH   ## tests override before adding to the tree
var progress: Progress
var state: GameState
var board: BoardView
var stage_id := ""
var mode: Mode = Mode.NONE
var selected_mon := ""
var selected_unit := -1
var ai_running := false
var midbattle_shown := false
var _dialogue_queue: Array = []
var _dialogue_done: Callable

# Screens / widgets
var ui_root: Control
var select_screen: Control
var stage_buttons: Dictionary = {}      ## stage_id -> Button
var hud: Control
var stage_label: Label
var status_label: Label
var info_label: Label
var team_buttons: Dictionary = {}       ## monster id -> Button
var end_button: Button
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
	_layout_board()
	show_stage_select()


# ---------------------------------------------------------------- widgets

func _style(bg: Color, edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(18)
	return sb


func _label(text: String, size: int, col: Color = Palette.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, cb: Callable, min_h: float = 100) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", FONT - 6)
	b.add_theme_color_override("font_color", Palette.TEXT)
	b.add_theme_color_override("font_disabled_color", Palette.TEXT.darkened(0.55))
	b.add_theme_stylebox_override("normal", _style(Palette.panel(), Palette.panel_edge()))
	b.add_theme_stylebox_override("hover", _style(Palette.panel().lightened(0.06), Palette.AETHER_CYAN))
	b.add_theme_stylebox_override("pressed", _style(Palette.AETHER_CYAN.darkened(0.6), Palette.AETHER_CYAN))
	b.add_theme_stylebox_override("disabled", _style(Palette.BG, Palette.panel()))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b


func _panel(edge: Color = Palette.panel_edge()) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(Palette.panel(), edge))
	return p


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


func _full(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root = _full(Control.new())
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)
	_build_select()
	_build_hud()
	_build_dialogue()
	_build_result()


func _build_select() -> void:
	select_screen = _full(MarginContainer.new())
	for side in ["left", "right", "top", "bottom"]:
		select_screen.add_theme_constant_override("margin_" + side, 32)
	ui_root.add_child(select_screen)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	select_screen.add_child(vb)
	vb.add_child(_label("AETHER SIGIL", 72, Palette.SIGIL_GOLD))
	vb.add_child(_label(str(Data.bible().get("tagline", "")), FONT - 4, Palette.AETHER_CYAN))
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
			var b := _button("", _on_stage_pressed.bind(str(l.stage_id)), 90)
			stage_buttons[str(l.stage_id)] = b
			grid.add_child(b)
	vb.add_child(_button("Reset progress", _on_reset_progress, 80))


func _build_hud() -> void:
	hud = _full(Control.new())
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(hud)
	var top := _panel()
	hud.add_child(top)
	_dock(top, false)
	var tv := VBoxContainer.new()
	top.add_child(tv)
	stage_label = _label("", FONT - 4, Palette.SIGIL_GOLD)
	tv.add_child(stage_label)
	status_label = _label("", FONT - 6)
	tv.add_child(status_label)
	var bottom := _panel()
	hud.add_child(bottom)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 12)
	bottom.add_child(bv)
	info_label = _label("", FONT - 8)
	info_label.custom_minimum_size = Vector2(0, 84)
	bv.add_child(info_label)
	bv.add_child(_label("Team: tap a monster, then a cyan tile to deploy", FONT - 12, Palette.AETHER_CYAN))
	var team_row := HBoxContainer.new()
	team_row.add_theme_constant_override("separation", 8)
	bv.add_child(team_row)
	for id in Data.starter_team():
		var b := _button("", _on_team.bind(str(id)), 120)
		b.add_theme_font_size_override("font_size", FONT - 14)
		team_buttons[str(id)] = b
		team_row.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bv.add_child(row)
	row.add_child(_button("Stages", show_stage_select))
	end_button = _button("End Turn", _on_end_turn)
	row.add_child(end_button)
	_dock(bottom, true)


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
	dialogue_speaker = _label("", FONT, Palette.SIGIL_GOLD)
	dialogue_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(dialogue_speaker)
	dialogue_text = _label("", FONT - 2)
	dialogue_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
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


func _layout_board() -> void:
	var vp := get_viewport().get_visible_rect().size
	var fit := (vp.x - 32.0) / board.board_size().x
	board.scale = Vector2.ONE * minf(1.15, fit)
	board.position = Vector2(vp.x / 2.0, vp.y * 0.46)


# ---------------------------------------------------------------- screens

func show_stage_select() -> void:
	ai_running = false
	board.visible = false
	hud.visible = false
	dialogue_box.visible = false
	result_box.visible = false
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


func start_stage(id: String) -> void:
	stage_id = id
	state.setup(id)
	mode = Mode.NONE
	ai_running = false
	midbattle_shown = false
	select_screen.visible = false
	result_box.visible = false
	board.visible = true
	hud.visible = true
	var st := state.stage
	var lines: Array = [str(st.dialogue.get("intro", ""))]
	if bool(st.get("boss", false)) and st.dialogue.has("boss_intro"):
		lines.append(str(st.dialogue.boss_intro))
	_refresh("Deploy your team onto the cyan spawn tiles.")
	show_dialogue(lines, func(): _refresh("Your turn. Tap a team monster to deploy it."))


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
	var how := {"symbol": "Symbol destroyed", "relics": "Relics secured", "elimination": "Team eliminated"}
	if won:
		var nxt := progress.record_win(stage_id)
		result_title.text = "Victory"
		result_sub.text = "%s. %s" % [how.get(state.win_reason, state.win_reason), ("Next: " + nxt) if nxt != "" else "All 120 stages cleared!"]
		next_button.visible = nxt != ""
	else:
		result_title.text = "Defeat" if state.winner == E else "Stalemate"
		result_sub.text = how.get(state.win_reason, "Round cap reached") if state.winner == E else "Round cap reached"
		next_button.visible = false
	result_box.visible = true


# ---------------------------------------------------------------- HUD refresh

func _refresh(msg: String = "") -> void:
	if state.stage.is_empty():
		return
	var st := state.stage
	stage_label.text = "%s  vs %s (%s)" % [st.name, st.opponent, st.opponent_style]
	var rule_txt := str(st.special_rule)
	var extra := ""
	if state.relic_win:
		extra = "   Relics %d/%d" % [state.relics_owned(P), int(Data.rules().relics_to_win)]
	if state.deploy_cost() > 0:
		extra += "   AP %d" % state.ap[P]
	status_label.text = "Round %d   %s\nYour Symbol %d   Enemy Symbol %d%s\nRule: %s" % [
		state.round_num, "Your turn" if state.current == P else "Rival's turn",
		state.symbol_hp[P], state.symbol_hp[E], extra, rule_txt]
	var my_turn := _my_turn()
	var can_place := my_turn and not state.legal_deploys(P).is_empty()
	for id in team_buttons:
		var d := Data.monster(id)
		var b: Button = team_buttons[id]
		var waiting: bool = state.reserve[P].has(id)
		b.text = "%s\n%s %d/%d/%d" % [str(d.name).left(9), str(d.element_family).left(5), d.hp, d.attack, d.defense] if waiting else "%s\non board" % str(d.name).left(9)
		b.disabled = not (waiting and can_place)
	end_button.disabled = not my_turn
	if msg != "":
		info_label.text = msg
	_update_highlights()
	board.queue_redraw()


func _my_turn() -> bool:
	return state.current == P and state.winner == GameState.NONE and not ai_running and not dialogue_box.visible and not result_box.visible


func _update_highlights() -> void:
	var h := {}
	board.selected = null
	match mode:
		Mode.DEPLOY:
			for a in state.legal_deploys(P):
				if a.mon == selected_mon:
					h[a.tile] = Palette.AETHER_CYAN
		Mode.UNIT:
			var u := state.get_unit(selected_unit)
			if u != null:
				board.selected = u.pos
				for c in state.legal_moves(u):
					h[c] = Palette.AETHER_CYAN
				for c in state.legal_attacks(u):
					h[c] = Palette.EMBER
	board.highlights = h


# ---------------------------------------------------------------- input

func _on_stage_pressed(id: String) -> void:
	if progress.is_unlocked(id):
		start_stage(id)


func _on_reset_progress() -> void:
	progress.reset()
	show_stage_select()


func _on_team(id: String) -> void:
	if not _my_turn():
		return
	mode = Mode.DEPLOY
	selected_mon = id
	_refresh("Tap a cyan tile to deploy %s (spawn tiles and your captured Prism nodes)." % Data.monster(id).name)


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
	if tile == null:
		mode = Mode.NONE
		_refresh(" ")
		return
	_on_tile(tile)


func _on_tile(c: Vector2i) -> void:
	var r := ""
	match mode:
		Mode.DEPLOY:
			r = state.deploy(P, selected_mon, c)
			mode = Mode.NONE
			_refresh("Deployed. It can act next turn." if r == GameState.OK else "Can't deploy there: " + r)
			return
		Mode.UNIT:
			if state.can_attack(P, selected_unit, c) == GameState.OK:
				var dmg := state.damage_preview(state.get_unit(selected_unit), c)
				state.attack(P, selected_unit, c)
				mode = Mode.NONE
				_after_action("Hit for %d." % dmg)
				return
			if state.can_move(P, selected_unit, c) == GameState.OK:
				state.move_unit(P, selected_unit, c)
				_after_action("Moved. Tap an ember tile to attack, or pick another monster.")
				return
	var u := state.unit_at(c)
	if u != null and u.owner == P:
		mode = Mode.UNIT
		selected_unit = u.id
		_refresh("%s (%s %s %s)  HP %d/%d  ATK %d DEF %d  Move %d Range %d  %s" % [u.name, u.element, u.family, u.role,
			u.hp, u.max_hp, state.attack_of(u, u.pos), state.defense_of(u, u.pos), state.move_of(u), state.range_of(u, u.pos), u.ability])
	elif u != null:
		mode = Mode.NONE
		_refresh("Enemy %s (%s)  HP %d/%d  ATK %d DEF %d" % [u.name, u.family, u.hp, u.max_hp, u.attack, u.defense])
	else:
		mode = Mode.NONE
		var td := state.tile_type(c)
		_refresh("%s: %s" % [td, str(state.stage.get("map_legend", {}).get(td, ""))])


## After any action: game over -> rival concedes (defeat line) or result; first loss -> midbattle line.
func _after_action(msg: String = "") -> void:
	if state.winner != GameState.NONE:
		_refresh(msg)
		if state.winner == P:
			show_dialogue([str(state.stage.dialogue.get("defeat", ""))], _show_result)
		else:
			_show_result()
		return
	if state.round_num > int(Data.rules().turn_cap_rounds):
		_refresh(msg)
		_show_result()
		return
	if not midbattle_shown and (state.kos[P] + state.kos[E] > 0 or state.symbol_hp[E] * 2 <= state.symbol_max):
		midbattle_shown = true
		_refresh(msg)
		show_dialogue([str(state.stage.dialogue.get("midbattle", ""))], func(): _refresh())
		return
	_refresh(msg)


func _on_end_turn() -> void:
	if not _my_turn() or state.end_turn(P) != GameState.OK:
		return
	mode = Mode.NONE
	if state.winner != GameState.NONE:
		_after_action()
		return
	ai_running = true
	_refresh("%s is thinking..." % state.stage.opponent)
	await get_tree().create_timer(AI_DELAY).timeout
	if not ai_running:
		return  # left the stage while waiting
	AI.take_turn(state, E, str(state.stage.opponent_style))
	ai_running = false
	_after_action("Your turn.")
