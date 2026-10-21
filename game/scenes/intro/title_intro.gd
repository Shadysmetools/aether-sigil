## Animated Aether Sigil title (~3 s build, then idle until tapped).
##
## Build: light motes converge into the Prism Core crystal -> two gold rings spin in and
## settle -> "AETHER SIGIL" lights up -> subtitle -> tagline -> "Tap to begin" pulses.
## Idle: slow counter-rotating rings, a breathing crystal glow and soft particle drift.
## Everything is procedural (Polygon2D / Line2D / CPUParticles2D); no concept art is used.
extends CanvasLayer

## Emitted when the player taps / presses a key during idle (or skip() is called twice).
signal finished
## Emitted when the build reaches its idle state.
signal idle_started

const BUILD_DURATION := 3.0
const NAVY := Color("#0B1220")
const CYAN := Color("#22D3EE")
const VIOLET := Color("#B15CFF")
const GOLD := Color("#F6C445")
const SILVER := Color("#D6DEE9")
const CINZEL := "res://art/intro/fonts/cinzel/Cinzel-Variable.ttf"
const NUNITO := "res://art/intro/fonts/nunito/Nunito-Variable.ttf"
const MOTES := 44
const PULSE_PERIOD := 1.8  # s; 0.56 Hz, far below the 3 Hz flash limit

@export var title_text := "AETHER SIGIL"
@export var subtitle_text := "CHRONICLES OF THE PRISM REALMS"
@export var tagline_text := "Collect. Command. Evolve. Conquer."
@export var prompt_text := "Tap to begin"
## Riser played at the start (its chime lands as the title lights, ~1.7 s).
@export var riser: AudioStream

## Seconds of (time-scaled) play since start; read by tests.
var elapsed := 0.0
## elapsed when the idle state was reached, or -1.
var idle_at := -1.0
var is_idle := false
var _done := false
var _build_tween: Tween
var _idle_tweens: Array[Tween] = []
var _vp := Vector2(1080, 1920)
var _safe := Rect2()
var _rng := RandomNumberGenerator.new()

var _stage: Node2D
var _crystal: Node2D
var _glow: Sprite2D
var _ring_a: Node2D
var _ring_b: Node2D
var _motes: Array[Sprite2D] = []
var _sparkle: CPUParticles2D
var _drift: CPUParticles2D
var _title: Label
var _divider: Line2D
var _subtitle: Label
var _tagline: Label
var _prompt: Label
var _audio: AudioStreamPlayer


func _ready() -> void:
	layer = 90
	_rng.seed = 7
	_vp = get_viewport().get_visible_rect().size
	_safe = _safe_rect()
	_build()
	if riser and DisplayServer.get_name() != "headless":  # headless quit mid-sound leaks the playback
		_audio.stream = riser
		_audio.play()
	if reduced_motion():
		_play_reduced()
	else:
		_play_build()


## Length of the build (the timeline below is built from the same constant).
static func get_duration() -> float:
	return BUILD_DURATION


## Mirrors studio_intro.reduced_motion(): custom project key, default off.
static func reduced_motion() -> bool:
	for key in ["accessibility/general/reduced_motion", "aether_sigil/accessibility/reduced_motion"]:
		if ProjectSettings.has_setting(key) and bool(ProjectSettings.get_setting(key)):
			return true
	return false


## First call during the build jumps to the finished idle state; a call during idle ends the title.
func skip() -> void:
	if _done:
		return
	if not is_idle:
		if _build_tween and _build_tween.is_valid():
			_build_tween.custom_step(BUILD_DURATION + 1.0)  # fast-forward to the final frame
		_enter_idle()
	else:
		_done = true
		finished.emit()


func _exit_tree() -> void:
	if _audio:
		_audio.stop()  # release the playback before the node goes


func _process(delta: float) -> void:
	elapsed += delta


# ---------------------------------------------------------------- build

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = NAVY
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://art/intro/shaders/vignette.gdshader")
	vm.set_shader_parameter("aspect", _vp.x / _vp.y)
	vm.set_shader_parameter("strength", 0.7)
	vig.material = vm
	add_child(vig)

	var dot := _dot_texture(32)

	_drift = CPUParticles2D.new()
	_drift.position = Vector2(_vp.x * 0.5, _vp.y * 0.55)
	_drift.amount = 36
	_drift.lifetime = 7.0
	_drift.preprocess = 0.0
	_drift.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_drift.emission_rect_extents = Vector2(_vp.x * 0.5, _vp.y * 0.45)
	_drift.direction = Vector2(0, -1)
	_drift.spread = 25.0
	_drift.gravity = Vector2(0, -6)
	_drift.initial_velocity_min = 8.0
	_drift.initial_velocity_max = 26.0
	_drift.scale_amount_min = 0.12
	_drift.scale_amount_max = 0.35
	_drift.texture = dot
	_drift.material = _add_material()
	_drift.color_ramp = _ramp([Color(CYAN, 0.0), Color(CYAN, 0.55), Color(VIOLET, 0.45), Color(VIOLET, 0.0)])
	_drift.emitting = false
	add_child(_drift)

	_stage = Node2D.new()
	_stage.position = Vector2(_vp.x * 0.5, _safe.position.y + _safe.size.y * 0.36)
	add_child(_stage)

	_glow = Sprite2D.new()
	_glow.texture = _glow_texture()
	_glow.material = _add_material()
	_glow.scale = Vector2.ONE * 2.2
	_glow.modulate.a = 0.0
	_stage.add_child(_glow)

	_ring_b = _make_ring(255.0, 3.0, Color(GOLD, 0.75), 12, false)
	_ring_a = _make_ring(305.0, 7.0, GOLD, 4, true)
	_stage.add_child(_ring_b)
	_stage.add_child(_ring_a)
	_crystal = _make_crystal()
	_stage.add_child(_crystal)

	_sparkle = CPUParticles2D.new()
	_sparkle.amount = 18
	_sparkle.lifetime = 1.8
	_sparkle.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_sparkle.emission_sphere_radius = 190.0
	_sparkle.gravity = Vector2(0, -10)
	_sparkle.initial_velocity_min = 4.0
	_sparkle.initial_velocity_max = 18.0
	_sparkle.scale_amount_min = 0.15
	_sparkle.scale_amount_max = 0.4
	_sparkle.texture = dot
	_sparkle.material = _add_material()
	_sparkle.color_ramp = _ramp([Color(1, 1, 1, 0.0), Color(1, 0.95, 0.8, 0.9), Color(GOLD, 0.0)])
	_sparkle.emitting = false
	_stage.add_child(_sparkle)

	for i in MOTES:
		var m := Sprite2D.new()
		m.texture = dot
		m.material = _add_material()
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(380.0, 760.0)
		m.position = Vector2(cos(ang), sin(ang)) * r
		m.set_meta("from", m.position)
		m.scale = Vector2.ONE * _rng.randf_range(0.6, 1.2)
		m.modulate = (CYAN if i % 3 else VIOLET).lerp(Color.WHITE, 0.3)
		m.modulate.a = 0.0
		_stage.add_child(m)
		_motes.append(m)

	# --- text, centred by full-width anchors inside the safe area ---
	var text_root := Control.new()
	text_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	text_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(text_root)
	var max_w := minf(_safe.size.x * 0.9, 1000.0)
	var y0 := _safe.position.y + _safe.size.y * 0.36 + 360.0

	var title_font := _font(CINZEL, 700, 6)
	var ts := _settings(title_font, _fit(title_font, title_text, max_w, 132), Color("#F4F8FC"))
	ts.outline_size = 3
	ts.outline_color = Color(CYAN, 0.35)
	ts.shadow_color = Color(CYAN, 0.0)
	ts.shadow_size = 22
	ts.shadow_offset = Vector2.ZERO
	_title = _label(text_root, title_text, ts, y0)

	_divider = Line2D.new()
	_divider.width = 2.5
	_divider.default_color = GOLD
	_divider.gradient = _ramp([Color(GOLD, 0.0), GOLD, Color(GOLD, 0.0)])
	_divider.position = Vector2(_vp.x * 0.5, y0 + ts.font_size * 1.25)
	_divider.points = PackedVector2Array([Vector2(-1, 0), Vector2(1, 0)])
	_divider.scale.x = 0.0
	add_child(_divider)

	var sub_font := _font(CINZEL, 600, 3)
	var ss := _settings(sub_font, _fit(sub_font, subtitle_text, max_w * 0.94, 44), GOLD)
	_subtitle = _label(text_root, subtitle_text, ss, y0 + ts.font_size * 1.25 + 26.0)

	var tag_font := _font(NUNITO, 600, 1)
	var tgs := _settings(tag_font, _fit(tag_font, tagline_text, max_w, 44), Color(SILVER, 0.9))
	_tagline = _label(text_root, tagline_text, tgs, _subtitle.position.y + ss.font_size * 1.6 + 30.0)

	var pf := _font(NUNITO, 700, 2)
	var ps := _settings(pf, 48, CYAN)
	ps.shadow_color = Color(CYAN, 0.35)
	ps.shadow_size = 12
	ps.shadow_offset = Vector2.ZERO
	_prompt = _label(text_root, prompt_text, ps, _safe.end.y - 170.0)

	_audio = AudioStreamPlayer.new()
	_audio.bus = &"Master"
	add_child(_audio)


func _label(parent: Control, text: String, ls: LabelSettings, y: float) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.offset_left = _safe.position.x
	l.offset_right = -(_vp.x - _safe.end.x)
	l.position.y = y
	l.pivot_offset = Vector2(_vp.x * 0.5, ls.font_size * 0.7)
	l.modulate.a = 0.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _make_crystal() -> Node2D:
	var root := Node2D.new()
	var T := Vector2(0, -205)
	var R := Vector2(122, -18)
	var B := Vector2(0, 212)
	var L := Vector2(-122, -18)
	var C := Vector2(-6, -34)
	var facets := [
		[[T, L, C], [Color("#E8FDFF"), CYAN, Color.WHITE]],
		[[T, R, C], [Color("#F6EDFF"), VIOLET, Color("#FFFFFF")]],
		[[L, B, C], [Color("#1AA7C9"), Color("#5B2BC9"), Color("#7FE9FF")]],
		[[R, B, C], [Color("#8B3BE0"), Color("#2E1673"), Color("#D9A8FF")]],
	]
	for f in facets:
		var p := Polygon2D.new()
		p.polygon = PackedVector2Array(f[0])
		p.vertex_colors = PackedColorArray(f[1])
		p.antialiased = true
		root.add_child(p)
	# inner table facet highlight
	var tbl := Polygon2D.new()
	tbl.polygon = PackedVector2Array([C + Vector2(0, -78), C + Vector2(44, 6), C + Vector2(0, 74), C + Vector2(-44, 6)])
	tbl.color = Color(1, 1, 1, 0.22)
	root.add_child(tbl)
	for e in [[T, C], [L, C], [R, C], [B, C]]:
		var l := Line2D.new()
		l.points = PackedVector2Array(e)
		l.width = 1.6
		l.default_color = Color(1, 1, 1, 0.55)
		root.add_child(l)
	var rim := Line2D.new()
	rim.points = PackedVector2Array([T, R, B, L])
	rim.closed = true
	rim.width = 4.0
	rim.joint_mode = Line2D.LINE_JOINT_SHARP
	rim.default_color = SILVER
	rim.antialiased = true
	root.add_child(rim)
	root.scale = Vector2.ZERO
	root.modulate.a = 0.0
	return root


func _make_ring(radius: float, width: float, color: Color, marks: int, spikes: bool) -> Node2D:
	var root := Node2D.new()
	var ring := Line2D.new()
	var pts := PackedVector2Array()
	for i in 128:
		pts.append(Vector2.from_angle(TAU * i / 128.0) * radius)
	ring.points = pts
	ring.closed = true
	ring.width = width
	ring.default_color = color
	ring.antialiased = true
	if spikes:
		ring.gradient = _ramp([GOLD, Color("#FFE9A8"), GOLD, Color("#C9952A"), GOLD])
	root.add_child(ring)
	for i in marks:
		var a := TAU * i / float(marks)
		var dir := Vector2.from_angle(a)
		var nrm := dir.orthogonal()
		var p := Polygon2D.new()
		if spikes:  # long four-point star spikes at N/E/S/W
			p.polygon = PackedVector2Array([dir * (radius - 18), dir * radius + nrm * 12, dir * (radius + 70), dir * radius - nrm * 12])
			p.color = Color("#FFE08A")
		else:      # small diamond ticks
			p.polygon = PackedVector2Array([dir * (radius - 9), dir * radius + nrm * 6, dir * (radius + 9), dir * radius - nrm * 6])
			p.color = Color(GOLD, 0.9)
		p.antialiased = true
		root.add_child(p)
	if not spikes:  # two orbiting orbs
		for i in 2:
			var orb := Sprite2D.new()
			orb.texture = _dot_texture(32)
			orb.material = _add_material()
			orb.position = Vector2.from_angle(PI * 0.25 + PI * i) * radius
			orb.scale = Vector2.ONE * 0.75
			orb.modulate = CYAN if i == 0 else VIOLET
			root.add_child(orb)
	root.modulate.a = 0.0
	return root


# ---------------------------------------------------------------- timelines

func _play_build() -> void:
	var t := create_tween().set_parallel(true)
	_build_tween = t
	var Q := Tween.TRANS_QUART
	var OUT := Tween.EASE_OUT
	# 0.0-1.05 motes converge
	for i in _motes.size():
		var m := _motes[i]
		var d := 0.02 * (i % 12)
		t.tween_property(m, "modulate:a", 0.95, 0.3).set_delay(d).set_trans(Tween.TRANS_CUBIC).set_ease(OUT)
		t.tween_property(m, "position", Vector2.ZERO, 0.8).set_delay(d).set_trans(Q).set_ease(Tween.EASE_IN)
		t.tween_property(m, "scale", Vector2.ONE * 0.3, 0.8).set_delay(d).set_trans(Q).set_ease(Tween.EASE_IN)
		t.tween_property(m, "modulate:a", 0.0, 0.15).set_delay(d + 0.8)
	# 0.85-1.35 crystal forms, with a single soft bloom
	t.tween_property(_crystal, "modulate:a", 1.0, 0.35).set_delay(0.85).set_trans(Q).set_ease(OUT)
	t.tween_property(_crystal, "scale", Vector2.ONE, 0.55).set_delay(0.85).set_trans(Tween.TRANS_BACK).set_ease(OUT)
	t.tween_property(_glow, "modulate:a", 1.0, 0.35).set_delay(0.85).set_trans(Q).set_ease(OUT)
	t.tween_property(_glow, "modulate:a", 0.6, 0.8).set_delay(1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(_sparkle.set.bind("emitting", true)).set_delay(0.95)
	# 1.0-1.9 rings spin in and settle
	_ring_a.rotation_degrees = -200.0
	_ring_a.scale = Vector2.ONE * 1.5
	_ring_b.rotation_degrees = 160.0
	_ring_b.scale = Vector2.ONE * 0.6
	for spec in [[_ring_a, 1.0], [_ring_b, 1.1]]:
		var ring: Node2D = spec[0]
		var d: float = spec[1]
		t.tween_property(ring, "modulate:a", 1.0, 0.4).set_delay(d).set_trans(Q).set_ease(OUT)
		t.tween_property(ring, "rotation_degrees", 0.0, 0.8).set_delay(d).set_trans(Q).set_ease(OUT)
		t.tween_property(ring, "scale", Vector2.ONE, 0.8).set_delay(d).set_trans(Q).set_ease(OUT)
	# 1.55-2.2 title lights up (riser chime at ~1.7)
	_title.scale = Vector2.ONE * 0.96
	t.tween_property(_title, "modulate:a", 1.0, 0.5).set_delay(1.55).set_trans(Q).set_ease(OUT)
	t.tween_property(_title, "scale", Vector2.ONE, 0.65).set_delay(1.55).set_trans(Q).set_ease(OUT)
	t.tween_property(_title.label_settings, "shadow_color", Color(CYAN, 0.5), 0.6).set_delay(1.6).set_trans(Q).set_ease(OUT)
	t.tween_property(_divider, "scale:x", 300.0, 0.6).set_delay(1.75).set_trans(Q).set_ease(OUT)
	# 1.95 subtitle, 2.25 tagline, 2.6 prompt
	for spec in [[_subtitle, 1.95], [_tagline, 2.25]]:
		var l: Label = spec[0]
		var d: float = spec[1]
		var y := l.position.y
		l.position.y = y + 18.0
		t.tween_property(l, "modulate:a", 1.0, 0.5).set_delay(d).set_trans(Q).set_ease(OUT)
		t.tween_property(l, "position:y", y, 0.5).set_delay(d).set_trans(Q).set_ease(OUT)
	t.tween_property(_prompt, "modulate:a", 1.0, 0.4).set_delay(2.6).set_trans(Q).set_ease(OUT)
	t.finished.connect(_enter_idle)


func _play_reduced() -> void:
	# Reduced motion: a single 0.8 s cross-fade into the final layout, no spins or particles.
	_crystal.scale = Vector2.ONE
	var t := create_tween().set_parallel(true)
	_build_tween = t
	for n in [_crystal, _ring_a, _ring_b, _title, _subtitle, _tagline, _prompt]:
		t.tween_property(n, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(_glow, "modulate:a", 0.6, 0.8)
	_divider.scale.x = 300.0
	t.finished.connect(_enter_idle)


func _enter_idle() -> void:
	if is_idle:
		return
	is_idle = true
	idle_at = elapsed
	if _build_tween and _build_tween.is_valid():
		_build_tween.kill()
	for m in _motes:
		m.visible = false
	_prompt.modulate.a = 1.0
	idle_started.emit()
	if reduced_motion():
		return
	_drift.emitting = true
	_sparkle.emitting = true
	# slow counter-rotation (loops forever)
	var ra := create_tween().set_loops()
	ra.tween_method(func(v: float) -> void: _ring_a.rotation_degrees = v, 0.0, 360.0, 60.0)
	var rb := create_tween().set_loops()
	rb.tween_method(func(v: float) -> void: _ring_b.rotation_degrees = v, 0.0, -360.0, 90.0)
	# crystal glow breathing + prompt pulse (0.56 Hz, soft: never a flash)
	var br := create_tween().set_loops()
	br.tween_property(_glow, "modulate:a", 0.9, PULSE_PERIOD * 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	br.tween_property(_glow, "modulate:a", 0.55, PULSE_PERIOD * 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var pp := create_tween().set_loops()
	pp.tween_property(_prompt, "modulate:a", 0.35, PULSE_PERIOD * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pp.tween_property(_prompt, "modulate:a", 1.0, PULSE_PERIOD * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var bob := create_tween().set_loops()
	bob.tween_property(_crystal, "position:y", -8.0, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(_crystal, "position:y", 8.0, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tweens = [ra, rb, br, pp, bob]


# ---------------------------------------------------------------- helpers

## Safe area in viewport coordinates (falls back to the full viewport).
func _safe_rect() -> Rect2:
	var full := Rect2(Vector2.ZERO, _vp)
	if DisplayServer.get_name() == "headless":
		return full
	var win := Vector2(DisplayServer.window_get_size())
	var sa := Rect2(DisplayServer.get_display_safe_area())
	sa.position -= Vector2(DisplayServer.window_get_position())  # screen -> window coords
	if win.x <= 0.0 or sa.size.x <= 0.0:
		return full
	var k := _vp / win
	var r := Rect2(sa.position * k, sa.size * k).intersection(full)
	return r if r.size.x > _vp.x * 0.5 and r.size.y > _vp.y * 0.5 else full


static func _fit(font: Font, text: String, max_w: float, want: int) -> int:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, want).x
	if w <= max_w or w <= 0.0:
		return want
	return int(floor(want * max_w / w))


static func _ramp(colors: Array) -> Gradient:
	var offs := PackedFloat32Array()
	for i in colors.size():
		offs.append(i / float(colors.size() - 1))
	var g := Gradient.new()
	g.offsets = offs
	g.colors = PackedColorArray(colors)
	return g


static func _add_material() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


static func _dot_texture(px: int) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.gradient = _ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = px
	tex.height = px
	return tex


static func _glow_texture() -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.gradient = _ramp([Color(0.75, 0.95, 1.0, 0.85), Color(CYAN, 0.45), Color(VIOLET, 0.18), Color(VIOLET, 0.0)])
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex


## Bundled variable font at a weight; falls back to the engine default font.
static func _font(path: String, weight: int, spacing: int) -> Font:
	var fv := FontVariation.new()
	if ResourceLoader.exists(path):
		fv.base_font = load(path)
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
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
