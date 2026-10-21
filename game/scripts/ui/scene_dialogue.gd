## Scene dialogue layer: characters stand IN the scene while they talk (visual-novel / cutscene style).
## It sits between the dim and the dialogue panel inside ui.gd's dialogue_box and is driven by ui.gd:
##   begin(lines, tower_id, backdrop) -> show_line(line) per line -> end().
## Everything that decides WHO stands WHERE is static and pure (plan / group_of / infer_mood / style_for),
## so tests exercise it without a scene. Reduced motion (Kit.reduced_motion or the ProjectSettings key)
## makes every slide, bob, push-in and glow pulse instant or static.
extends Control

const Data = preload("res://scripts/data_loader.gd")
const Assets = preload("res://scripts/assets.gd")
const UIArt = preload("res://scripts/ui_art.gd")
const Palette = preload("res://scripts/theme_colors.gd")
const Narrator = preload("res://scripts/narrator.gd")
const Actor = preload("res://scripts/ui/character_actor.gd")
const Kit = preload("res://scripts/ui/menu_kit.gd")

signal advance_requested   ## Auto mode wants the next line

## Slots: x as a fraction of the stage width, and the actor scale. Left group = Elio's side.
const LEFT_SLOTS := [[0.2, 1.0], [0.43, 0.86]]
const RIGHT_SLOTS := [[0.8, 1.0], [0.57, 0.86]]
const FLOAT_SLOT := [0.5, 0.85]
const PUSH_IN := 1.045

var actors: Dictionary = {}          ## who -> Actor
var slot_of: Dictionary = {}         ## who -> {group, index}
var hero := "Elio"
var history: Array = []              ## [{speaker, line}] of everything shown this scene (and earlier scenes)
var auto := false
var fast := false
var text_label: Label                ## the dialogue text (typewriter source for the talk animation)
var panel: Control                   ## the dialogue panel (actors stand on its top edge)
var instant := false
var _plan: Array = []
var _step := 0
var _stage: Control
var _backdrop: TextureRect
var _tint: ColorRect
var _log: PanelContainer
var _voice_on := false
var _last_chars := 0
var _auto_wait := 0.0
var _speaker := ""
var _push: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop = TextureRect.new()
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.visible = false
	add_child(_backdrop)
	_tint = ColorRect.new()
	_tint.color = Color(Palette.BG, 0.45)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tint.visible = false
	add_child(_tint)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)
	resized.connect(_layout)


static func reduced_motion() -> bool:
	return Kit.reduced_motion or bool(ProjectSettings.get_setting("aether_sigil/accessibility/reduced_motion", false))


# ---------------------------------------------------------------- pure helpers (tested)

## Mood tag for a line that has none. MUST match tools/narrator_lines.py infer_mood (the story test asserts it).
static func infer_mood(speaker: String, text: String) -> String:
	var t := text.to_lower()
	var has := func(ws: Array) -> bool:
		for w in ws:
			if t.contains(w):
				return true
		return false
	if has.call(["save the speeches", "how dare", "you will regret", "fool", "get out"]):
		return "angry"
	if has.call(["ha!", "haha", "rematch", "bring your whole team", "good sign", "not bad", "splendid", "fine. just this once"]):
		return "amused"
	if speaker == "Pell" and t.ends_with("!"):
		return "amused"
	if has.call(["never seen", "incredible", "beautiful", "wonder", "reforms"]):
		return "awed"
	if has.call(["...", "sorry", "fallen", "goodbye", "lost "]):
		return "sad"
	if t.contains("!") or has.call(["i'm going", "we hold", "i will", "we answered", "let's", "ready"]):
		return "determined"
	if has.call(["must", "cannot", "can't", "tired", "dark", "falling", "broke", "cracking", "burn", "sinking"]):
		return "grave"
	return "neutral"


## The line's mood tag: its own "mood" field, else inferred.
static func mood_of(d: Dictionary) -> String:
	var m := str(d.get("mood", ""))
	return m if m != "" else infer_mood(str(d.get("speaker", "")), str(d.get("line", "")))


## One of the 7 shared expressions for a line dict.
static func expression_for(d: Dictionary) -> String:
	return Narrator.expression_for_mood(mood_of(d))


## Bubble style: "speech", "thought" (inner voice, sorrow) or "shout".
static func style_for(d: Dictionary) -> String:
	var text := str(d.get("line", ""))
	var e := expression_for(d)
	if text.begins_with("...") or e == "sad":
		return "thought"
	if text.ends_with("!") and (e == "angry" or e == "determined"):
		return "shout"
	return "speech"


## Which side of the stage a speaker stands on: "float" (the Narrator), "left" (the hero and Pell) or "right".
static func group_of(who: String, hero_name: String) -> String:
	if who == Narrator.SPEAKER:
		return "float"
	if who == hero_name or who == "Pell":
		return "left"
	return "right"


## The staging for a run of lines: one step per line = {who, enter [{who, group, index}], exit [who], active}.
## Left/right hold two actors each (the oldest non-hero, non-speaker leaves when a third arrives), the
## Narrator floats alone. Pure: same lines -> same plan.
static func plan(lines: Array, hero_name: String) -> Array:
	var on := {"left": [], "right": [], "float": []}
	var cap := {"left": 2, "right": 2, "float": 1}
	var out := []
	for l in lines:
		var who := str(l.get("speaker", ""))
		var step := {"who": who, "enter": [], "exit": [], "active": who}
		if who == "":
			out.append(step)
			continue
		var g := group_of(who, hero_name)
		if not (on[g] as Array).has(who):
			if (on[g] as Array).size() >= int(cap[g]):
				for cand in on[g]:
					if cand != hero_name and cand != who:
						(on[g] as Array).erase(cand)
						step.exit.append(cand)
						break
			(on[g] as Array).append(who)
			step.enter.append({"who": who, "group": g, "index": 0})
		out.append(step)
	return out


## Slot index for a group given who already stands there (first free slot).
static func free_slot(taken: Array, count: int) -> int:
	for i in count:
		if not taken.has(i):
			return i
	return 0


# ---------------------------------------------------------------- running a scene

func _actor(who: String) -> Actor:
	if actors.has(who):
		return actors[who]
	var a := Actor.new()
	a.instant = instant or reduced_motion()
	a.exited.connect(_on_actor_exited)
	_stage.add_child(a)
	actors[who] = a
	_size_actor(a)
	return a


func _size_actor(a: Actor) -> void:
	var vp := size if size.x > 10 else Vector2(1080, 1920)
	var w := minf(vp.x * 0.34, 360.0)
	var floor_y := _floor_y()
	var h := minf(w * 1.5, floor_y - 40.0)
	h = maxf(h, 200.0)
	w = minf(w, h / 1.2) if h < w * 1.2 else w
	a.size = Vector2(w, h)
	a.position = Vector2(0, floor_y - h)   # x set per slot in _place


func _floor_y() -> float:
	var vp_h := size.y if size.y > 10 else 1920.0
	if panel != null and is_instance_valid(panel) and panel.is_inside_tree() and panel.size.y > 1.0:
		return clampf(panel.global_position.y - global_position.y + 56.0, 300.0, vp_h)
	return vp_h * 0.62


func _layout() -> void:
	for who in actors:
		_size_actor(actors[who])
		_place(who)


func _place(who: String) -> void:
	var a: Actor = actors[who]
	var vp_w := size.x if size.x > 10 else 1080.0
	a.position.x = vp_w * a.home_x - a.size.x * 0.5
	a.position.y = _floor_y() - a.size.y


## Starts a scene. backdrop: draw the tower backdrop (story scenes outside battle) for tower_id ("" = world).
func begin(lines: Array, tower_id: String = "", backdrop: bool = false) -> void:
	hero = str(Data.story().get("protagonist", {}).get("name", "Elio"))
	instant = reduced_motion()
	for who in actors:
		actors[who].queue_free()
	actors = {}
	slot_of = {}
	_plan = plan(lines, hero)
	_step = 0
	_speaker = ""
	_last_chars = 0
	_auto_wait = 0.0
	visible = true
	var tex: Texture2D = Assets.backdrop(tower_id) if backdrop else null
	_backdrop.texture = tex
	_backdrop.visible = backdrop and tex != null
	_tint.visible = backdrop
	_tint.color = Color(Palette.BG, 0.45 if tex != null else 0.82)   # no painted backdrop yet: hide the screen behind
	_stage.scale = Vector2.ONE


## Shows one line: applies the staging step (exits, entrances), focuses the speaker, sets the
## expression from the mood tag and starts the voice. Returns {style, color, expression, mood}.
func show_line(d: Dictionary) -> Dictionary:
	var who := str(d.get("speaker", ""))
	var info := {"style": style_for(d), "color": UIArt.speaker_color(who), "expression": expression_for(d), "mood": mood_of(d)}
	history.append({"speaker": who, "line": str(d.get("line", ""))})
	if history.size() > 200:
		history.pop_front()
	if _step < _plan.size():
		var st: Dictionary = _plan[_step]
		_step += 1
		for w in st.exit:
			if actors.has(w):
				_release_slot(w)
				actors[w].exit()
		for e in st.enter:
			_enter(str(e.who), str(e.group))
	if who != "" and actors.has(who):
		for w in actors:
			actors[w].set_active(w == who)
			actors[w].talking = false
		var a: Actor = actors[who]
		a.set_expression(str(info.expression))
		a.talking = true
		a.talk_level = 0.0
		_speaker = who
	_last_chars = 0
	_auto_wait = 0.0
	_start_voice(who, str(d.get("line", "")))
	_push_in(who)
	return info


func _release_slot(who: String) -> void:
	slot_of.erase(who)


func _enter(who: String, group: String) -> void:
	var a := _actor(who)
	if a.is_on_stage():
		return
	var table: Array = LEFT_SLOTS if group == "left" else RIGHT_SLOTS
	var taken := []
	for w in slot_of:
		if slot_of[w].group == group:
			taken.append(int(slot_of[w].index))
	if group == "float":
		a.enter(who, 0, FLOAT_SLOT[0], FLOAT_SLOT[1], true)
		slot_of[who] = {"group": group, "index": 0}
	else:
		var idx := free_slot(taken, table.size())
		slot_of[who] = {"group": group, "index": idx}
		a.enter(who, -1 if group == "left" else 1, table[idx][0], table[idx][1])
	_place(who)


func _on_actor_exited(_a: Control) -> void:
	pass


## Everyone leaves; the layer hides once they are gone.
func end() -> void:
	_stop_voice()
	for who in actors:
		actors[who].talking = false
		actors[who].exit()
	_push_in("")
	if instant or reduced_motion():
		_finish_hide()
	else:
		get_tree().create_timer(0.35).timeout.connect(_finish_hide)


func _finish_hide() -> void:
	# a new scene may have begun in the meantime
	for who in actors:
		if actors[who].is_on_stage():
			return
	visible = false
	_backdrop.visible = false
	_tint.visible = false


## Camera push-in: the stage scales slightly about the speaker.
func _push_in(who: String) -> void:
	if _push != null:
		_push.kill()
	if reduced_motion() or not is_inside_tree():
		_stage.scale = Vector2.ONE
		return
	var target := PUSH_IN if who != "" else 1.0
	if who != "" and actors.has(who):
		var a: Actor = actors[who]
		_stage.pivot_offset = a.position + Vector2(a.size.x * 0.5, a.size.y * 0.6)
	_stage.scale = Vector2.ONE if who != "" else _stage.scale
	_push = create_tween()
	_push.tween_property(_stage, "scale", Vector2(target, target), 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- talking

func _audio() -> Node:
	return get_node_or_null("/root/AudioManager") if is_inside_tree() else null


func _start_voice(who: String, line: String) -> void:
	_voice_on = false
	var am := _audio()
	if am != null and who != "" and am.has_method("play_voice_line"):
		_voice_on = bool(am.play_voice_line(who, line)) and not bool(am.get("silent"))


func _stop_voice() -> void:
	_voice_on = false
	var am := _audio()
	if am != null and am.has_method("stop_voice"):
		am.stop_voice()


## Voice amplitude 0..1 from the voice bus peak, or -1 when no voice is playing.
func _voice_level() -> float:
	if not _voice_on:
		return -1.0
	for b in ["Voice", "Voices", "Dialogue"]:
		var idx := AudioServer.get_bus_index(b)
		if idx >= 0:
			return clampf(db_to_linear(AudioServer.get_bus_peak_volume_left_db(idx, 0)) * 3.0, 0.0, 1.0)
	return -1.0


## Per-character blip pitch: stable hash of the name, 0.8 .. 1.4.
static func blip_pitch(who: String) -> float:
	return 0.8 + float(absi(hash(who)) % 60) / 100.0


func _blip(who: String) -> void:
	var am := _audio()
	if am == null or not am.has_method("play_sfx") or not am.has_method("has_sfx"):
		return
	var id := "text_blip" if am.has_sfx("text_blip") else ("ui_tap" if am.has_sfx("ui_tap") else "")
	if id != "":
		am.play_sfx(id, null, 0.0, -14.0 + (4.0 if Narrator.is_narrator(who) else 0.0))


func _process(dt: float) -> void:
	if not visible or _speaker == "" or not actors.has(_speaker):
		return
	var a: Actor = actors[_speaker]
	var typing := false
	var done := true
	if text_label != null and is_instance_valid(text_label):
		var total := text_label.get_total_character_count()
		var shown := int(round(text_label.visible_ratio * total)) if total > 0 else 0
		typing = shown < total
		done = not typing
		if shown > _last_chars:
			if (shown - _last_chars) >= 1 and shown % 2 == 0:
				_blip(_speaker)
			_last_chars = shown
	var vl := _voice_level()
	if vl >= 0.0:
		a.talk_level = vl
		a.talking = vl > 0.05
		done = vl < 0.02 and not typing
	else:
		a.talking = typing
		a.talk_level = (0.55 + 0.45 * sin(a.clock * 13.0)) * 0.8 if typing else 0.0
	if auto and done:
		_auto_wait += dt
		var n := text_label.get_total_character_count() if text_label != null else 40
		var need := (0.35 + n * 0.008) if fast else (1.1 + n * 0.028)
		if _auto_wait >= need:
			_auto_wait = 0.0
			advance_requested.emit()


## Typewriter duration for a line of n characters.
func type_time(n: int) -> float:
	return clampf(n * (0.005 if fast else 0.014), 0.12 if fast else 0.2, 0.6 if fast else 1.6)


# ---------------------------------------------------------------- history log

func toggle_log(parent: Control) -> void:
	if _log != null and is_instance_valid(_log):
		_log.queue_free()
		_log = null
		return
	_log = PanelContainer.new()
	_log.add_theme_stylebox_override("panel", UIArt.panel_style(Palette.CRYSTAL_VIOLET, 0.97))
	_log.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_log.offset_left = 40
	_log.offset_right = -40
	_log.offset_top = 120
	_log.offset_bottom = -420
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	sc.add_child(v)
	var head := Label.new()
	head.text = "HISTORY"
	head.add_theme_font_override("font", UIArt.font(true, 700))
	head.add_theme_font_size_override("font_size", 28)
	head.add_theme_color_override("font_color", Palette.SIGIL_GOLD)
	v.add_child(head)
	for h in history.slice(maxi(0, history.size() - 40)):
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text = "%s: %s" % [Narrator.plate_name(str(h.speaker)), h.line]
		l.add_theme_font_size_override("font_size", 24)
		l.add_theme_color_override("font_color", UIArt.speaker_color(str(h.speaker)).lerp(Palette.TEXT, 0.55))
		v.add_child(l)
	parent.add_child(_log)
	await get_tree().process_frame
	if sc != null and is_instance_valid(sc):
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)


func log_open() -> bool:
	return _log != null and is_instance_valid(_log)


# ---------------------------------------------------------------- champion cut-in

## A diagonal banner with the champion sliding in, shown over the start of a boss battle. Non-modal,
## ends by itself (reduced motion: a still banner that fades).
func cut_in(parent: Control, who: String, title: String, secs: float = 1.8) -> Control:
	var band := Control.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(band)
	var col := UIArt.speaker_color(who)
	var vp := parent.size if parent.size.x > 10 else Vector2(1080, 1920)
	var strip := ColorRect.new()
	strip.color = Color(Palette.BG.lerp(col, 0.35), 0.92)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.size = Vector2(vp.x * 1.3, 250)
	strip.rotation = -0.09
	strip.position = Vector2(-vp.x * 0.1, vp.y * 0.28)
	band.add_child(strip)
	var edge := ColorRect.new()
	edge.color = Color(Palette.SIGIL_GOLD, 0.9)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.size = Vector2(vp.x * 1.3, 5)
	edge.rotation = -0.09
	edge.position = strip.position + Vector2(0, 245)
	band.add_child(edge)
	var a := Actor.new()
	a.instant = reduced_motion()
	a.size = Vector2(420, 560)
	a.position = Vector2(vp.x - 470, vp.y * 0.28 - 330)
	band.add_child(a)
	a.enter(who, 1, 0.5, 1.0)
	a.set_active(true)
	a.set_expression("determined")
	var name_l := Label.new()
	name_l.text = who.to_upper()
	name_l.add_theme_font_override("font", UIArt.font(true, 800))
	name_l.add_theme_font_size_override("font_size", 64)
	name_l.add_theme_color_override("font_color", Palette.TEXT)
	name_l.position = Vector2(60, vp.y * 0.28 + 20)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(name_l)
	var sub := Label.new()
	sub.text = title
	sub.add_theme_font_override("font", UIArt.font(false, 700))
	sub.add_theme_font_size_override("font_size", 30)
	sub.add_theme_color_override("font_color", Palette.SIGIL_GOLD)
	sub.position = Vector2(64, vp.y * 0.28 + 110)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(sub)
	if reduced_motion() or not band.is_inside_tree():
		band.modulate.a = 1.0
		if band.is_inside_tree():
			var tw0 := band.create_tween()
			tw0.tween_interval(secs)
			tw0.tween_property(band, "modulate:a", 0.0, 0.3)
			tw0.tween_callback(band.queue_free)
		return band
	band.modulate.a = 0.0
	strip.position.x -= vp.x * 0.5
	var tw := band.create_tween()
	tw.set_parallel(true)
	tw.tween_property(band, "modulate:a", 1.0, 0.15)
	tw.tween_property(strip, "position:x", -vp.x * 0.1, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(secs)
	tw.chain().tween_property(band, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(band.queue_free)
	return band
