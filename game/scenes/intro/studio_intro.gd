## SMETOOLS Production studio ident (~3.0 s full, ~1.0 s short).
##
## Rebuilds the official SMETOOLS logo as vectors, animates it, then crossfades into the real
## logo PNG (`logo_texture`) so the end frame IS the brand asset. Every vector element is drawn
## in the PNG's own pixel space (1024 x 1024) under one Node2D that is transformed exactly like
## the PNG sprite, so the crossfade lines up with no tuning.
##
## Swap the logo: assign another texture to `logo_texture` (the one exported slot). If the new
## logo's geometry differs, set `vector_build = false` to skip the gear rebuild and just reveal
## the texture with the glint, caption and fades.
extends CanvasLayer

## Emitted once, when the ident has faded to black (or was skipped).
signal finished

const FULL_DURATION := 3.0
const SHORT_DURATION := 1.0
const LOGO_PX := 1024.0

# --- geometry measured from art/intro/smetools-logo.png (pixels, y down) ---
const GEAR_CENTER := Vector2(508, 516)
const GEAR_ROOT_R := 176.0
const GEAR_TIP_R := 198.0
const GEAR_TEETH := 12
const RING_R := 150.0
const WORD_BOX := Rect2(147, 474, 736, 93)   # cap box of "SMETOOLS"
const LOGO_BG := Color("#0A112B")            # sampled disc colour (brief: ~#0B1430)
const BLUE := Color("#5B8CFF")
const VIOLET := Color("#9B6BFF")
const PINK := Color("#E36BFF")
const SILVER := Color("#D6DEE9")
## [centre_x, centre_y, radius, colour] for the scattered dots in the logo.
const DOTS := [
	[369, 340, 3.2, "#C492E9"], [748, 369, 3.8, "#8FACE8"], [696, 370, 3.2, "#CC87E1"],
	[320, 387, 2.0, "#A2BAE3"], [759, 412, 10.0, "#7E9EEF"], [280, 436, 6.5, "#BF7AEB"],
	[721, 446, 1.8, "#B6A6EE"], [295, 619, 8.5, "#936AE5"], [319, 637, 1.5, "#8984C4"],
	[294, 659, 4.0, "#BE6EDE"], [677, 665, 3.0, "#B879D7"], [615, 716, 6.0, "#E159DE"],
]
## Inner arcs: [radius, start_deg, span_deg, width, colour_a, colour_b] (0 deg = right, y down).
const ARCS := [
	[114.0, 200.0, 140.0, 5.0, "#E36BFF", "#9B6BFF"],
	[114.0, 30.0, 120.0, 5.0, "#9B6BFF", "#E36BFF"],
	[128.0, 200.0, 90.0, 3.5, "#E98BFF", "#C46BFF"],
]

## The one swappable brand texture. Its centre is the logo centre.
@export var logo_texture: Texture2D
## Caption under the logo, small tracked caps.
@export var caption := "PRODUCTION"
## false = skip the vector rebuild and only reveal `logo_texture` (use for a different logo).
@export var vector_build := true
## true = the ~1 s short ident.
@export var short_mode := false
## Sting played at the start (Master bus).
@export var sting: AudioStream

## Seconds of (time-scaled) play since start(); read by tests.
var elapsed := 0.0
## elapsed at the moment `finished` fired, or -1.
var finished_at := -1.0
var _done := false
var _started := false
var _tween: Tween
var _vp := Vector2(1080, 1920)

var _bg: ColorRect
var _black: ColorRect
var _frame: Node2D           # sits at the screen centre; scaling it scales about the centre
var _logo: Node2D            # PNG pixel space (origin = PNG top-left)
var _vector: Node2D          # everything that crossfades out
var _gear_group: Node2D
var _gear: Line2D
var _gear_glow: Line2D
var _trail: Line2D
var _head: Sprite2D
var _gear_pts := PackedVector2Array()
var _arc_group: Node2D
var _arcs: Array[Line2D] = []
var _dots: Array[Sprite2D] = []
var _burst: CPUParticles2D
var _word: Label
var _word_mat: ShaderMaterial
var _png: Sprite2D
var _caption: Label
var _audio: AudioStreamPlayer


func _ready() -> void:
	layer = 100
	_vp = get_viewport().get_visible_rect().size
	_build()
	start()


## Total length of the ident for the given mode (the tween timeline is built from the same numbers).
static func get_duration(short: bool) -> float:
	return SHORT_DURATION if short else FULL_DURATION


## true when the project asks for reduced motion (no such built-in setting exists in 4.7,
## so a custom key is checked; default off).
static func reduced_motion() -> bool:
	for key in ["accessibility/general/reduced_motion", "aether_sigil/accessibility/reduced_motion"]:
		if ProjectSettings.has_setting(key) and bool(ProjectSettings.get_setting(key)):
			return true
	return false


## Starts the timeline. Called from _ready; safe to call once.
func start() -> void:
	if _started:
		return
	_started = true
	if sting and _audio and DisplayServer.get_name() != "headless":  # headless quit mid-sound leaks the playback
		_audio.stream = sting
		_audio.play(0.6 if short_mode else 0.0)  # short: chime lands at ~0.25 s
	if short_mode or reduced_motion() or not vector_build:
		_play_reveal(get_duration(short_mode))
	else:
		_play_full()


## Ends the ident immediately (tap / key). Emits `finished`.
func skip() -> void:
	_finish(true)


func _exit_tree() -> void:
	if _audio:
		_audio.stop()  # release the playback before the node goes


func _process(delta: float) -> void:
	if _started and not _done:
		elapsed += delta


func _finish(cut := false) -> void:
	if _done:
		return
	_done = true
	finished_at = elapsed
	if _tween:
		_tween.kill()
	_release_audio(cut)
	finished.emit()


## Hands the sting to the parent so it outlives this layer: it rings out on a natural finish
## and fades over 80 ms on a skip (no click from a hard stop).
func _release_audio(cut: bool) -> void:
	if not _audio or not _audio.playing or not get_parent():
		return
	var a := _audio
	_audio = null
	a.reparent(get_parent())
	a.finished.connect(a.queue_free)
	if cut:
		var fade := a.create_tween()
		fade.tween_property(a, "volume_db", -60.0, 0.08).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		fade.tween_callback(a.queue_free)


# ---------------------------------------------------------------- build

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_bg = ColorRect.new()
	_bg.color = Color.BLACK
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bg)

	# The logo lives in its own pixel space, scaled to fit the portrait width.
	var s: float = minf(_vp.x, _vp.y * 0.6) / LOGO_PX
	_frame = Node2D.new()
	_frame.position = _vp * 0.5
	_frame.scale = Vector2(s, s)
	root.add_child(_frame)
	_logo = Node2D.new()
	_logo.position = -Vector2(LOGO_PX, LOGO_PX) * 0.5
	_frame.add_child(_logo)

	_png = Sprite2D.new()
	_png.texture = logo_texture
	_png.centered = false
	if logo_texture:
		_png.scale = Vector2.ONE * LOGO_PX / float(logo_texture.get_width())
	_png.modulate.a = 0.0
	_logo.add_child(_png)

	_vector = Node2D.new()
	_logo.add_child(_vector)
	if vector_build:
		_build_vector()

	_caption = Label.new()
	_caption.text = caption
	_caption.label_settings = _settings(_font("res://art/intro/fonts/montserrat/Montserrat-Variable.ttf", 600, 16), 40, SILVER)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.size = Vector2(LOGO_PX, 60)
	_caption.position = Vector2(0, GEAR_CENTER.y + GEAR_TIP_R + 64)
	_caption.modulate.a = 0.0
	_logo.add_child(_caption)

	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://art/intro/shaders/vignette.gdshader")
	vm.set_shader_parameter("aspect", _vp.x / _vp.y)
	vm.set_shader_parameter("strength", 0.45)
	vig.material = vm
	root.add_child(vig)

	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_black)

	_audio = AudioStreamPlayer.new()
	_audio.bus = &"Master"
	add_child(_audio)


func _build_vector() -> void:
	var stroke := ShaderMaterial.new()
	stroke.shader = load("res://art/intro/shaders/logo_stroke.gdshader")
	stroke.set_shader_parameter("span", GEAR_TIP_R)
	var trail_mat := stroke.duplicate() as ShaderMaterial
	trail_mat.set_shader_parameter("boost", 1.7)

	_gear_group = Node2D.new()
	_gear_group.position = GEAR_CENTER
	_vector.add_child(_gear_group)

	_gear_pts = _gear_points()
	_gear_glow = _line(10.0, Color(1, 1, 1, 0.22), stroke)
	_gear = _line(4.6, Color.WHITE, stroke)
	_trail = _line(9.0, Color.WHITE, trail_mat)
	_trail.gradient = _fade_gradient()
	for l in [_gear_glow, _gear, _trail]:
		_gear_group.add_child(l)

	var ring := _line(2.4, Color(1, 1, 1, 0.75), stroke)
	ring.name = "Ring"
	ring.points = _arc_points(RING_R, 0.0, 360.0, 160)
	ring.closed = true
	ring.modulate.a = 0.0
	_gear_group.add_child(ring)

	_head = Sprite2D.new()
	_head.texture = _dot_texture(64)
	_head.scale = Vector2.ONE * 0.9
	_head.material = _add_material()
	_head.modulate = Color(0.85, 0.8, 1.0, 0.0)
	_gear_group.add_child(_head)

	_arc_group = Node2D.new()
	_arc_group.position = GEAR_CENTER
	_vector.add_child(_arc_group)
	for a in ARCS:
		var glow := _line(a[3] * 3.2, Color(Color(a[4]), 0.22), null)
		var core := _line(a[3], Color.WHITE, null)
		var g := Gradient.new()
		g.set_color(0, Color(a[4]))
		g.set_color(1, Color(a[5]))
		core.gradient = g
		_arc_group.add_child(glow)
		_arc_group.add_child(core)
		_arcs.append(glow)
		_arcs.append(core)

	var dot_tex := _dot_texture(32)
	for d in DOTS:
		var sp := Sprite2D.new()
		sp.texture = dot_tex
		sp.modulate = Color(d[3])
		sp.set_meta("target", Vector2(d[0], d[1]))
		sp.set_meta("size", d[2] * 1.5 / 16.0)
		sp.position = GEAR_CENTER
		sp.scale = Vector2.ZERO
		_vector.add_child(sp)
		_dots.append(sp)

	_burst = CPUParticles2D.new()
	_burst.position = GEAR_CENTER
	_burst.emitting = false
	_burst.one_shot = true
	_burst.amount = 48
	_burst.lifetime = 0.9
	_burst.explosiveness = 0.95
	_burst.spread = 180.0
	_burst.gravity = Vector2.ZERO
	_burst.initial_velocity_min = 260.0
	_burst.initial_velocity_max = 620.0
	_burst.damping_min = 380.0
	_burst.damping_max = 520.0
	_burst.scale_amount_min = 0.08
	_burst.scale_amount_max = 0.22
	_burst.texture = dot_tex
	_burst.material = _add_material()
	var ramp := Gradient.new()
	ramp.set_color(0, Color(BLUE, 1.0))
	ramp.add_point(0.5, Color(VIOLET, 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color(PINK, 0.0))
	_burst.color_ramp = ramp
	_vector.add_child(_burst)

	# Wordmark: Montserrat ExtraBold/Black, sized to the measured cap box.
	var fv := _font("res://art/intro/fonts/montserrat/Montserrat-Variable.ttf", 850, 0)
	var fsize := 100
	var w := fv.get_string_size("SMETOOLS", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	if w > 0.0:
		fsize = int(round(fsize * WORD_BOX.size.x / w))
	_word = Label.new()
	_word.text = "SMETOOLS"
	var ls := _settings(fv, fsize, SILVER)
	ls.shadow_color = Color(0.02, 0.03, 0.08, 0.75)
	ls.shadow_offset = Vector2(0, 6)
	ls.shadow_size = 10
	_word.label_settings = ls
	_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_word.size = Vector2(LOGO_PX, fsize * 1.4)
	var baseline := WORD_BOX.position.y + WORD_BOX.size.y
	_word.position = Vector2(WORD_BOX.get_center().x - LOGO_PX * 0.5, baseline - fv.get_ascent(fsize))
	_word.pivot_offset = Vector2(LOGO_PX * 0.5, fv.get_ascent(fsize) - WORD_BOX.size.y * 0.5)
	_word_mat = ShaderMaterial.new()
	_word_mat.shader = load("res://art/intro/shaders/glint.gdshader")
	_word.material = _word_mat
	_word.modulate.a = 0.0
	_vector.add_child(_word)


# ---------------------------------------------------------------- timelines

func _play_full() -> void:
	var t := create_tween().set_parallel(true)
	_tween = t
	var Q := Tween.TRANS_QUART
	var OUT := Tween.EASE_OUT
	# black -> logo navy
	t.tween_property(_bg, "color", LOGO_BG, 0.45).set_trans(Q).set_ease(OUT)
	# gear: stroke draw-on with a light trail, and a 40 deg rotation that settles
	_gear_group.rotation_degrees = -40.0
	t.tween_property(_gear_group, "rotation_degrees", 0.0, 1.45).set_delay(0.1).set_trans(Q).set_ease(OUT)
	t.tween_property(_head, "modulate:a", 1.0, 0.15).set_delay(0.1)
	t.tween_method(_draw_gear, 0.0, 1.0, 0.95).set_delay(0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_head, "modulate:a", 0.0, 0.25).set_delay(1.0)
	t.tween_property(_trail, "modulate:a", 0.0, 0.3).set_delay(1.0)
	t.tween_property(_gear_group.get_node("Ring"), "modulate:a", 1.0, 0.5).set_delay(0.55).set_trans(Q).set_ease(OUT)
	# inner arcs sweep in, counter-rotating
	_arc_group.rotation_degrees = 70.0
	t.tween_method(_draw_arcs, 0.0, 1.0, 0.7).set_delay(0.45).set_trans(Q).set_ease(OUT)
	t.tween_property(_arc_group, "rotation_degrees", 0.0, 0.9).set_delay(0.45).set_trans(Q).set_ease(OUT)
	# particles: burst out, then settle onto the logo's dot positions
	t.tween_callback(_burst.restart).set_delay(0.55)
	for i in _dots.size():
		var sp := _dots[i]
		var target: Vector2 = sp.get_meta("target")
		var sz: float = sp.get_meta("size")
		var over := GEAR_CENTER + (target - GEAR_CENTER) * 1.65
		var d := 0.55 + 0.012 * i
		t.tween_property(sp, "scale", Vector2.ONE * sz, 0.3).set_delay(d).set_trans(Q).set_ease(OUT)
		t.tween_property(sp, "position", over, 0.32).set_delay(d).set_trans(Q).set_ease(OUT)
		t.tween_property(sp, "position", target, 0.5).set_delay(d + 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	# wordmark drops in with a slight scale overshoot, then a silver-white glint sweeps
	_word.position.y -= 46.0
	_word.scale = Vector2.ONE * 1.18
	t.tween_property(_word, "modulate:a", 1.0, 0.25).set_delay(0.95)
	t.tween_property(_word, "position:y", _word.position.y + 46.0, 0.42).set_delay(0.95).set_trans(Q).set_ease(OUT)
	t.tween_property(_word, "scale", Vector2.ONE, 0.5).set_delay(0.95).set_trans(Tween.TRANS_BACK).set_ease(OUT)
	_word_mat.set_shader_parameter("sweep", -260.0)
	t.tween_method(_set_glint, 0.0, 1.0, 0.6).set_delay(1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_word.label_settings, "font_color", Color.WHITE, 0.4).set_delay(1.3).set_trans(Q).set_ease(OUT)
	# caption
	_caption.position.y += 14.0
	t.tween_property(_caption, "modulate:a", 1.0, 0.45).set_delay(1.4).set_trans(Q).set_ease(OUT)
	t.tween_property(_caption, "position:y", _caption.position.y - 14.0, 0.45).set_delay(1.4).set_trans(Q).set_ease(OUT)
	# crossfade the vector build into the official PNG, hold ~0.6 s, fade to black
	t.tween_property(_png, "modulate:a", 1.0, 0.3).set_delay(1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_vector, "modulate:a", 0.0, 0.3).set_delay(1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_black, "color:a", 1.0, 0.3).set_delay(FULL_DURATION - 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(_finish)


## Short (~1 s) / reduced-motion path: no build, just a soft reveal of the real logo.
func _play_reveal(total: float) -> void:
	_vector.visible = false
	var t := create_tween().set_parallel(true)
	_tween = t
	var fade_in := total * 0.3
	var fade_out := total * 0.3
	t.tween_property(_bg, "color", LOGO_BG, fade_in).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	if not reduced_motion():
		var s1 := _frame.scale
		_frame.scale = s1 * 1.04
		t.tween_property(_frame, "scale", s1, total - fade_out).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(_png, "modulate:a", 1.0, fade_in).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(_caption, "modulate:a", 1.0, fade_in).set_delay(fade_in * 0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(_black, "color:a", 1.0, fade_out).set_delay(total - fade_out).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(_finish)


func _draw_gear(p: float) -> void:
	var n := _gear_pts.size()
	var f := p * float(n - 1)
	var i := int(floor(f))
	var pts := _gear_pts.slice(0, i + 1)
	if i < n - 1:
		pts.append(_gear_pts[i].lerp(_gear_pts[i + 1], f - i))
	_gear.points = pts
	_gear_glow.points = pts
	var tail := maxi(0, pts.size() - int(n * 0.14))
	_trail.points = pts.slice(tail)
	if pts.size() > 0:
		_head.position = pts[pts.size() - 1]
	if p >= 1.0:
		_gear.closed = true
		_gear_glow.closed = true


func _draw_arcs(p: float) -> void:
	for i in ARCS.size():
		var a: Array = ARCS[i]
		var pts := _arc_points(a[0], a[1], a[2] * p, 48)
		_arcs[i * 2].points = pts
		_arcs[i * 2 + 1].points = pts


func _set_glint(p: float) -> void:
	_word_mat.set_shader_parameter("sweep", lerpf(-260.0, LOGO_PX + 260.0, p))
	_word_mat.set_shader_parameter("strength", sin(p * PI) * 0.9)


# ---------------------------------------------------------------- helpers

## Closed 12-tooth gear outline (teeth centred at -90 + 30k deg), starting at the left tooth
## (180 deg) and running clockwise. Tip spans 13 deg, flanks 3 deg, root 11 deg (from the PNG).
static func _gear_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var step := 360.0 / GEAR_TEETH
	for i in GEAR_TEETH:
		var c := 180.0 + i * step
		for a in [-15.0, -12.0, -9.5]:
			pts.append(_polar(GEAR_ROOT_R, c + a))
		for a in [-6.5, -3.25, 0.0, 3.25, 6.5]:
			pts.append(_polar(GEAR_TIP_R, c + a))
		for a in [9.5, 12.0]:
			pts.append(_polar(GEAR_ROOT_R, c + a))
	pts.append(pts[0])
	return pts


static func _polar(r: float, deg: float) -> Vector2:
	return Vector2(cos(deg_to_rad(deg)), sin(deg_to_rad(deg))) * r


static func _arc_points(r: float, start_deg: float, span_deg: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if span_deg <= 0.01:
		return pts
	for j in segs + 1:
		pts.append(_polar(r, start_deg + span_deg * j / float(segs)))
	return pts


func _line(width: float, color: Color, mat: Material) -> Line2D:
	var l := Line2D.new()
	l.width = width
	l.default_color = color
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	l.antialiased = true
	if mat:
		l.material = mat
	return l


static func _fade_gradient() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 1))
	return g


static func _add_material() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


static func _dot_texture(px: int) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.45, Color(1, 1, 1, 0.85))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = px
	tex.height = px
	return tex


## Loads a bundled variable font at a weight; falls back to the engine default font.
static func _font(path: String, weight: int, spacing: int) -> Font:
	var fv := FontVariation.new()
	if ResourceLoader.exists(path):
		fv.base_font = load(path)
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	else:
		fv.base_font = ThemeDB.fallback_font
	fv.spacing_glyph = spacing
	return fv


static func _settings(font: Font, size: int, color: Color) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = color
	return ls

