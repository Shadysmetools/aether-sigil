## A small floating companion bubble for battle and meta screens: a mini figure (Vellum, or a rival) and a
## one-line speech bubble. Non-blocking (only the bubble itself takes taps), auto-dismisses, tap to skip,
## waits while `blocked` says a modal dialogue is open, respects reduced motion.
extends Control

const UIArt = preload("res://scripts/ui_art.gd")
const Palette = preload("res://scripts/theme_colors.gd")
const Narrator = preload("res://scripts/narrator.gd")
const Kit = preload("res://scripts/ui/menu_kit.gd")
const Scene = preload("res://scripts/ui/scene_dialogue.gd")

signal dismissed(bark_id: String)

const FIG := 120.0
const WIDTH := 640.0

var who := Narrator.SPEAKER
var last_id := ""              ## id of the most recent bark shown (tests)
var shown_ids: Array = []
var text := ""
var expression := "neutral"
var blocked: Callable          ## returns true while a modal dialogue/cinematic is up
var enabled := true
var clock := 0.0
var _label: Label
var _panel: PanelContainer
var _fig: Control
var _life := 0.0
var _age := 0.0
var _queue: Array = []
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	custom_minimum_size = Vector2(WIDTH, FIG + 10)
	size = custom_minimum_size
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_fig = Control.new()
	_fig.custom_minimum_size = Vector2(FIG, FIG)
	_fig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fig.draw.connect(_draw_fig)
	row.add_child(_fig)
	_panel = PanelContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP     # the bubble is the only thing that takes taps
	_panel.gui_input.connect(_on_tap)
	row.add_child(_panel)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 24)
	_label.custom_minimum_size = Vector2(WIDTH - FIG - 60.0, 0)
	_label.add_theme_color_override("font_color", Palette.TEXT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)


static func reduced_motion() -> bool:
	return Scene.reduced_motion()


func place_at(pos: Vector2) -> void:
	position = pos


## Style the bubble for a speaker: edge colour and (via who) the mini figure.
func set_speaker(p_who: String) -> void:
	who = p_who
	var edge := UIArt.speaker_color(who) if who != Narrator.SPEAKER else Palette.CRYSTAL_VIOLET.lerp(Palette.SIGIL_GOLD, 0.5)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.BG, 0.94)
	sb.border_color = edge
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", sb)
	size = Vector2(WIDTH, FIG + 10)


## Queue a line. Replaces what is showing when `urgent`; otherwise it waits its turn (max 2 queued).
func say(p_who: String, line: String, mood: String, bark_id: String, urgent: bool = false) -> void:
	if not enabled or line == "":
		return
	var item := {"who": p_who, "line": line, "mood": mood, "id": bark_id}
	if visible and urgent:
		_queue.clear()
		_show(item)
	elif visible:
		if _queue.size() < 2:
			_queue.append(item)
	else:
		_show(item)


func _show(item: Dictionary) -> void:
	set_speaker(str(item.who))
	text = str(item.line)
	_label.text = text
	expression = Narrator.expression_for_mood(str(item.mood))
	last_id = str(item.id)
	shown_ids.append(last_id)
	_life = clampf(3.2 + text.length() * 0.045, 3.2, 7.0)
	_age = 0.0
	visible = true
	modulate.a = 1.0
	if _tween != null:
		_tween.kill()
	if not reduced_motion() and is_inside_tree():
		modulate.a = 0.0
		_tween = create_tween()
		_tween.tween_property(self, "modulate:a", 1.0, 0.25)
	_fig.queue_redraw()


## Tap, or the owner's code: dismiss now (the next queued bark, if any, follows).
func dismiss() -> void:
	if not visible:
		return
	var id := last_id
	visible = false
	if not _queue.is_empty():
		_show(_queue.pop_front())
	dismissed.emit(id)


func clear_all() -> void:
	_queue.clear()
	visible = false


func _on_tap(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		dismiss()
		accept_event()


## Advance by dt without the scene tree (tests call this directly).
func advance(dt: float) -> void:
	clock += dt
	if not visible:
		return
	if blocked.is_valid() and blocked.call():
		return               # a modal dialogue is open: the bark keeps its full time afterwards
	_age += dt
	_life -= dt
	_fig.queue_redraw()
	if _life <= 0.0:
		dismiss()


func _process(dt: float) -> void:
	if visible:
		advance(dt)


func _draw_fig() -> void:
	var r := Rect2(Vector2(4, 4), Vector2(FIG - 8, FIG - 8))
	var calm := reduced_motion()
	if not calm:
		r.position.y += sin(clock * 1.8) * 4.0
	var talking := 0.0 if calm or _age > 1.4 else (0.5 + 0.5 * sin(clock * 11.0)) * 0.4
	_fig.draw_circle(Rect2(Vector2(4, 4), Vector2(FIG - 8, FIG - 8)).get_center(), (FIG - 8) * 0.5, Color(Palette.BG, 0.8))
	UIArt.draw_actor_figure(_fig, r, who, expression, talking, false, 0.0 if calm else clock, true)
