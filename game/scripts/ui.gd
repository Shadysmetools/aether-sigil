## Main scene controller: builds the HUD, turns taps into GameState actions, runs the AI turn.
extends Node2D

const GameState = preload("res://scripts/game_state.gd")
const Wicks = preload("res://scripts/wicks.gd")
const AI = preload("res://scripts/ai.gd")
const BoardView = preload("res://scripts/board_view.gd")
const PieceArt = preload("res://scripts/piece_art.gd")

const VIEW_SIZE := Vector2(1080, 1920)
const BOARD_CENTER := Vector2(540, 880)
const AI_DELAY := 0.6
const FONT_SIZE := 34

enum Mode { NONE, SUMMON, POST, UNIT }

var state: GameState
var board: BoardView
var mode: Mode = Mode.NONE
var selected_def := ""
var selected_unit := -1
var ai_running := false

var top_label: Label
var info_label: Label
var satchel_buttons: Dictionary = {}  ## def_id -> Button
var post_button: Button
var end_button: Button
var banner: PanelContainer
var banner_label: Label


func _ready() -> void:
	RenderingServer.set_default_clear_color(PieceArt.COL_BG)
	state = GameState.new()
	board = BoardView.new()
	board.state = state
	board.position = BOARD_CENTER
	add_child(board)
	_build_hud()
	_refresh("Your turn. Summon a Wick next to your Hearth.")


# ---------------------------------------------------------------- HUD

func _make_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 110)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", FONT_SIZE - 4)
	b.pressed.connect(cb)
	return b


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.size = VIEW_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var top := PanelContainer.new()
	top.position = Vector2.ZERO
	top.size = Vector2(VIEW_SIZE.x, 150)
	root.add_child(top)
	top_label = Label.new()
	top_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_label.add_theme_font_size_override("font_size", FONT_SIZE)
	top.add_child(top_label)

	info_label = Label.new()
	info_label.position = Vector2(20, 1380)
	info_label.size = Vector2(VIEW_SIZE.x - 40, 90)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_font_size_override("font_size", FONT_SIZE - 6)
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(info_label)

	var bottom := PanelContainer.new()
	bottom.position = Vector2(0, 1480)
	bottom.size = Vector2(VIEW_SIZE.x, VIEW_SIZE.y - 1480)
	root.add_child(bottom)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	bottom.add_child(vb)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)
	for def_id in Wicks.STARTING_SATCHEL:
		var b := _make_button("", _on_satchel.bind(def_id))
		satchel_buttons[def_id] = b
		grid.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	post_button = _make_button("Post (%d Oil)" % GameState.POST_COST, _on_post)
	end_button = _make_button("End Turn", _on_end_turn)
	row.add_child(post_button)
	row.add_child(end_button)

	banner = PanelContainer.new()
	banner.position = Vector2(140, 700)
	banner.size = Vector2(800, 380)
	banner.visible = false
	root.add_child(banner)
	var bvb := VBoxContainer.new()
	bvb.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.add_child(bvb)
	banner_label = Label.new()
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.add_theme_font_size_override("font_size", 64)
	bvb.add_child(banner_label)
	bvb.add_child(_make_button("Restart", _on_restart))


func _refresh(msg: String = "") -> void:
	var p := GameState.HUMAN
	top_label.text = "Oil %d/%d   Turn %d   Beacons %d/3 (Rival %d)\nHearth %d   Rival Hearth %d" % [
		state.oil[p], GameState.OIL_CAP, state.turn, state.beacons_owned(p),
		state.beacons_owned(GameState.RIVAL), state.hearth_hp[p], state.hearth_hp[GameState.RIVAL]]
	var my_turn := state.current == p and state.winner == GameState.NONE and not ai_running
	for def_id in satchel_buttons:
		var d := Wicks.get_def(def_id)
		var b: Button = satchel_buttons[def_id]
		var have: bool = def_id in state.satchels[p]
		b.text = "%s %d\n%d/%d/%d" % [d.name, d.cost, d.power, d.guard, d.hp] if have else "(%s)" % d.name
		b.disabled = not my_turn or not have or state.oil[p] < int(d.cost)
		b.button_pressed = false
	post_button.disabled = not my_turn or state.oil[p] < GameState.POST_COST
	end_button.disabled = not my_turn
	if msg != "":
		info_label.text = msg
	_update_highlights()
	if state.winner != GameState.NONE:
		banner.visible = true
		var how := "Hearth snuffed" if state.win_reason == "hearth" else "All 3 Beacons held"
		banner_label.text = ("You win!" if state.winner == p else "You lose") + "\n" + how
	else:
		banner.visible = false
	board.queue_redraw()


func _update_highlights() -> void:
	var h := {}
	var p := GameState.HUMAN
	board.selected = null
	match mode:
		Mode.SUMMON:
			for c in state.tiles:
				if state.can_summon(p, selected_def, c) == GameState.OK:
					h[c] = Color("#7CFC9A")
		Mode.POST:
			for c in state.tiles:
				if state.can_plant_post(p, c) == GameState.OK:
					h[c] = Color("#FFE08A")
		Mode.UNIT:
			var u = state.get_unit(selected_unit)
			if u != null:
				board.selected = u.pos
				for c in state.tiles:
					if state.can_move(p, u.id, c) == GameState.OK:
						h[c] = Color("#CFE8FF")
					elif state.can_attack(p, u.id, c) == GameState.OK:
						h[c] = Color("#FF4D4D")
	board.highlights = h


# ---------------------------------------------------------------- input

func _on_satchel(def_id: String) -> void:
	mode = Mode.SUMMON
	selected_def = def_id
	_refresh("Tap a green tile to summon %s." % Wicks.get_def(def_id).name)


func _on_post() -> void:
	mode = Mode.POST
	_refresh("Tap a yellow tile to plant a Lantern Post.")


func _on_restart() -> void:
	state.reset()
	mode = Mode.NONE
	ai_running = false
	_refresh("New game. Your turn.")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if state.current != GameState.HUMAN or state.winner != GameState.NONE or ai_running:
		return
	var local: Vector2 = board.make_input_local(event).position
	var tile: Variant = board.tile_at_local(local)
	if tile == null:
		mode = Mode.NONE
		_refresh(" ")
		return
	_on_tile(tile)


func _on_tile(c: Vector2i) -> void:
	var p := GameState.HUMAN
	var r := ""
	match mode:
		Mode.SUMMON:
			r = state.summon(p, selected_def, c)
			mode = Mode.NONE
			_refresh("Summoned." if r == GameState.OK else "Can't summon: " + r)
			return
		Mode.POST:
			r = state.plant_post(p, c)
			mode = Mode.NONE
			_refresh("Post planted." if r == GameState.OK else "Can't plant: " + r)
			return
		Mode.UNIT:
			if state.can_attack(p, selected_unit, c) == GameState.OK:
				state.attack(p, selected_unit, c)
				mode = Mode.NONE
				_refresh("Attack!")
				return
			if state.can_move(p, selected_unit, c) == GameState.OK:
				state.move_unit(p, selected_unit, c)
				_refresh("Moved. Tap a red target to attack, or pick another Wick.")
				return
	var u = state.unit_at(c)
	if u != null and u.owner == p:
		mode = Mode.UNIT
		selected_unit = u.id
		_refresh("%s %s  P%d G%d HP%d/%d  Move %d Range %d" % [u.name, u.element, u.power, u.guard, u.hp, u.max_hp, u.move, u.attack_range])
	else:
		mode = Mode.NONE
		_refresh(" ")


func _on_end_turn() -> void:
	if state.end_turn(GameState.HUMAN) != GameState.OK:
		return
	mode = Mode.NONE
	if state.winner != GameState.NONE:
		_refresh()
		return
	ai_running = true
	_refresh("Rival is thinking...")
	await get_tree().create_timer(AI_DELAY).timeout
	if not ai_running:
		return  # restarted while waiting
	AI.take_turn(state, GameState.RIVAL)
	ai_running = false
	_refresh("Your turn.")
