## Full-screen 2D cinematics for the meta screens: EVOLUTION (silhouette glows white, a light spiral
## converges, one flash, the new form is revealed with rays and a particle burst), FUSION (the two
## parents spiral into each other, merge flash, reveal) and VICTORY (crystal-shard confetti, rank
## stars popping in, level-up glow rings). Tap anywhere: before the reveal it jumps to the reveal,
## after it closes. Never runs headless (play() returns null), so tests are never blocked.
## reduced_motion (aether_sigil/accessibility/reduced_motion) swaps the white flash for a soft fade.
## Presentation only.
extends CanvasLayer

const Palette = preload("res://scripts/theme_colors.gd")
const Art = preload("res://scripts/board_art.gd")
const Assets = preload("res://scripts/assets.gd")
const Data = preload("res://scripts/data_loader.gd")
const Sfx = preload("res://scripts/sfx.gd")

const PORTRAIT_SHADER := """shader_type canvas_item;
uniform float sil = 0.0;
uniform float circle = 1.0;
uniform vec4 ring : source_color = vec4(0.96, 0.78, 0.35, 1.0);
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = length(UV - vec2(0.5));
	float m = mix(1.0, 1.0 - smoothstep(0.46, 0.48, d), circle);
	float r = circle * (1.0 - smoothstep(0.0, 0.02, abs(d - 0.475)));
	vec3 col = mix(c.rgb, vec3(1.0), sil);
	COLOR = vec4(mix(col, ring.rgb, r), max(c.a * m, r) * COLOR.a);
}
"""

static var _shader: Shader

var kind := ""
var data: Dictionary = {}
var t := 0.0
var dur := 3.4
var reveal_at := 1.6
var view: Control
var portraits: Array = []          ## TextureRect per shown portrait
var _parts: Array = []             ## spiral / burst / confetti particles
var _rng := RandomNumberGenerator.new()
var _flash := 0.0
var _closing := -1.0
var _sounded := {}

signal done


## Starts a cinematic over `host` (ui root). kind: evolution | fusion | victory. Returns the overlay,
## or null when headless (nothing to wait for).
static func play(host: Node, p_kind: String, p_data: Dictionary) -> Node:
	if DisplayServer.get_name() == "headless":
		return null
	var c = load("res://scripts/cinematic.gd").new()
	c.kind = p_kind
	c.data = p_data
	host.add_child(c)
	return c


## Monster art for a bible form id (cut-out, crop or nothing).
static func art(mon_id: String) -> Texture2D:
	if mon_id == "" or not Data.has_monster(mon_id):
		return null
	var fam := str(Data.monster(mon_id).get("element_family", "")) if mon_id != "" else ""
	return Assets.monster(mon_id, fam) if mon_id != "" else null


static func reduced_motion() -> bool:
	return bool(ProjectSettings.get_setting("aether_sigil/accessibility/reduced_motion", false))


func _ready() -> void:
	layer = 40
	_rng.seed = hash(kind + str(data.get("to_name", "")))
	view = Control.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.gui_input.connect(_on_input)
	view.draw.connect(_draw_view)
	add_child(view)
	match kind:
		"evolution":
			dur = 3.6
			reveal_at = 1.7
			_portrait(data.get("from_tex"))
			_portrait(data.get("to_tex"))
			Sfx.play("evolve_build")
		"fusion":
			dur = 3.8
			reveal_at = 1.9
			_portrait(data.get("a_tex"))
			_portrait(data.get("b_tex"))
			_portrait(data.get("to_tex"))
			Sfx.play("fusion_merge")
		_:
			dur = 3.6
			reveal_at = 0.0
			for lu in data.get("levelups", []):
				_portrait(lu.get("tex"))
			for i in 70:
				_parts.append({"p": Vector2(_rng.randf() * 1080.0, -_rng.randf() * 900.0 - 40.0), "v": Vector2(_rng.randf_range(-60, 60), _rng.randf_range(260, 520)),
					"r": _rng.randf() * TAU, "w": _rng.randf_range(-5.0, 5.0), "s": _rng.randf_range(9.0, 20.0),
					"c": [Palette.AETHER_CYAN, Palette.SIGIL_GOLD, Palette.CRYSTAL_VIOLET, Palette.SOFT_SILVER, Palette.VERDANT_GREEN][i % 5]})


func _portrait(tex: Variant) -> void:
	var tr := TextureRect.new()
	tr.texture = tex if tex is Texture2D else null
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _shader == null:
		_shader = Shader.new()
		_shader.code = PORTRAIT_SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	# painted cut-outs keep their silhouette; rectangular crops are framed as medallions
	var crop := tr.texture == null or Assets.is_crop(tr.texture)
	m.set_shader_parameter("circle", 1.0 if crop else 0.0)
	tr.material = m
	tr.visible = false
	view.add_child(tr)
	portraits.append(tr)


func _on_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		skip()
		view.accept_event()


## Tap: jump to the reveal, or close once revealed.
func skip() -> void:
	if t < reveal_at:
		t = reveal_at
	else:
		close()


func close() -> void:
	if _closing < 0.0:
		_closing = 0.0


func _process(delta: float) -> void:
	view.position = Vector2.ZERO
	view.size = view.get_viewport_rect().size
	t += delta
	_flash = maxf(0.0, _flash - delta * 2.0)
	if t >= dur:
		close()
	if _closing >= 0.0:
		_closing += delta
		view.modulate.a = clampf(1.0 - _closing / 0.3, 0.0, 1.0)
		if _closing >= 0.3:
			done.emit()
			queue_free()
			return
	if reveal_at > 0.0 and t >= reveal_at and not _sounded.has("reveal"):
		_sounded["reveal"] = true
		_flash = 0.0 if reduced_motion() else 0.85
		Sfx.play("evolve_burst")
		for i in 60:
			var a := _rng.randf() * TAU
			_parts.append({"p": view.size * Vector2(0.5, 0.45), "v": Vector2.from_angle(a) * _rng.randf_range(220, 700), "life": _rng.randf_range(0.6, 1.3), "age": 0.0,
				"c": Palette.SIGIL_GOLD.lerp(Palette.family(str(data.get("family", "Light"))), _rng.randf() * 0.6), "burst": true})
	for p in _parts:
		if p.has("burst"):
			p.age += delta
			p.p += p.v * delta
			p.v *= 0.96
		elif kind == "victory":
			p.p += p.v * delta
			p.r += p.w * delta
			if p.p.y > view.size.y + 40.0:
				p.p.y = -30.0
	_parts = _parts.filter(func(p): return not p.has("burst") or p.age < p.life)
	_layout()
	view.queue_redraw()


func _layout() -> void:
	var c := view.size * Vector2(0.5, 0.45)
	var big := minf(view.size.x * 0.62, 620.0)
	match kind:
		"evolution":
			var a: TextureRect = portraits[0]
			var b: TextureRect = portraits[1]
			var pre := t < reveal_at
			a.visible = pre
			b.visible = not pre
			if pre:
				var k := clampf((t - 0.3) / (reveal_at - 0.4), 0.0, 1.0)
				var s := big * (0.9 + 0.04 * sin(t * TAU * 1.1) * k)
				_place(a, c, s)
				(a.material as ShaderMaterial).set_shader_parameter("sil", k)
			else:
				var k := clampf((t - reveal_at) / 0.5, 0.0, 1.0)
				_place(b, c, big * (0.6 + 0.4 * _back(k)))
				(b.material as ShaderMaterial).set_shader_parameter("sil", 1.0 - k)
		"fusion":
			var pre := t < reveal_at
			for i in 2:
				var p: TextureRect = portraits[i]
				p.visible = pre
				if pre:
					var k := clampf((t - 0.2) / (reveal_at - 0.2), 0.0, 1.0)
					var ang := PI * i + k * TAU * 1.25
					var rad := (1.0 - k * k) * view.size.x * 0.3
					_place(p, c + Vector2.from_angle(ang) * rad, big * (0.55 - 0.2 * k))
					(p.material as ShaderMaterial).set_shader_parameter("sil", k)
			var r: TextureRect = portraits[2]
			r.visible = not pre
			if not pre:
				var k := clampf((t - reveal_at) / 0.5, 0.0, 1.0)
				_place(r, c, big * (0.6 + 0.4 * _back(k)))
				(r.material as ShaderMaterial).set_shader_parameter("sil", 1.0 - k)
		_:
			for i in portraits.size():
				var p: TextureRect = portraits[i]
				var at := 1.3 + i * 0.25
				p.visible = t >= at
				var n := portraits.size()
				var x := view.size.x * (i + 1) / (n + 1)
				_place(p, Vector2(x, view.size.y * 0.66), 150.0 * _back(clampf((t - at) / 0.35, 0.0, 1.0)))


static func _back(f: float) -> float:
	return 1.0 + 2.70158 * pow(f - 1.0, 3.0) + 1.70158 * pow(f - 1.0, 2.0)


func _place(tr: TextureRect, center: Vector2, s: float) -> void:
	tr.size = Vector2(s, s)
	tr.position = center - Vector2(s, s) / 2.0


func _draw_view() -> void:
	var vp := view.size
	var c := vp * Vector2(0.5, 0.45)
	var fade := clampf(t / 0.3, 0.0, 1.0)
	view.draw_rect(Rect2(Vector2.ZERO, vp), Color(Palette.MIDNIGHT_NAVY.darkened(0.4), 0.88 * fade))
	var f := Art.font()
	var fam_col := Palette.family(str(data.get("family", "Light")))
	if kind == "evolution" or kind == "fusion":
		# converging light spiral before the reveal
		if t < reveal_at:
			var k := clampf(t / reveal_at, 0.0, 1.0)
			for arm in 3:
				for i in 18:
					var u := float(i) / 18.0
					var ang := arm * TAU / 3.0 + u * 5.0 + t * 3.0
					var rad := (1.0 - k) * 520.0 * (1.0 - u * 0.7) + 40.0
					var p := c + Vector2.from_angle(ang) * rad
					view.draw_circle(p, 3.0 + 5.0 * u, Color(Palette.SIGIL_GOLD.lerp(fam_col, u), 0.25 + 0.6 * u * k))
		else:
			# rotating rays behind the revealed form
			var k := clampf((t - reveal_at) / 0.6, 0.0, 1.0)
			for i in 14:
				var a0 := TAU * i / 14.0 + t * 0.4
				var pts := PackedVector2Array([c, c + Vector2.from_angle(a0 - 0.08) * 900.0 * k, c + Vector2.from_angle(a0 + 0.08) * 900.0 * k])
				view.draw_colored_polygon(pts, Color(Palette.SIGIL_GOLD.lerp(fam_col, 0.4), 0.16))
			view.draw_circle(c, 330.0 * k, Color(fam_col, 0.12))
		var title := "EVOLUTION" if kind == "evolution" else "FUSION"
		_text(f, title, Vector2(vp.x / 2.0, 250.0), 76, Palette.SIGIL_GOLD)
		if t >= reveal_at:
			var line := "%s evolved into %s!" % [data.get("from_name", ""), data.get("to_name", "")] if kind == "evolution" \
				else "%s + %s  ->  %s" % [data.get("a_name", ""), data.get("b_name", ""), data.get("to_name", "")]
			_text(f, line, Vector2(vp.x / 2.0, vp.y * 0.78), 40, Palette.SOFT_SILVER)
	else:
		for p in _parts:
			if p.has("burst"):
				continue
			var s: float = p.s
			var pts := PackedVector2Array()
			for k in 4:
				var a: float = p.r + k * PI / 2.0
				var rr := s if k % 2 == 0 else s * 0.45
				pts.append(p.p + Vector2.from_angle(a) * rr)
			view.draw_colored_polygon(pts, Color(p.c, 0.9))
		_text(f, "VICTORY", Vector2(vp.x / 2.0, vp.y * 0.3), 110, Palette.SIGIL_GOLD)
		var stars := int(data.get("stars", 0))
		for i in 3:
			var at := 0.45 + i * 0.3
			if t < at:
				continue
			var k := _back(clampf((t - at) / 0.3, 0.0, 1.0))
			var sc := Vector2(vp.x / 2.0 + (i - 1) * 170.0, vp.y * 0.43)
			_star(sc, 64.0 * k, Palette.SIGIL_GOLD if i < stars else Palette.MIDNIGHT_NAVY.lightened(0.25))
			if i < stars and not _sounded.has("star%d" % i):
				_sounded["star%d" % i] = true
				Sfx.play("ui_confirm")
		var lus: Array = data.get("levelups", [])
		for i in lus.size():
			var at := 1.3 + i * 0.25
			if t < at:
				continue
			var x := vp.x * (i + 1) / (lus.size() + 1)
			var y := vp.y * 0.66
			var k := clampf((t - at) / 0.8, 0.0, 1.0)
			view.draw_arc(Vector2(x, y), 80.0 + 60.0 * k, 0, TAU, 48, Color(Palette.SIGIL_GOLD, 1.0 - k), 6.0, true)
			view.draw_arc(Vector2(x, y), 82.0, 0, TAU, 48, Palette.SIGIL_GOLD, 3.0, true)
			_text(f, "LEVEL UP", Vector2(x, y - 100.0), 30, Palette.SIGIL_GOLD)
			_text(f, "%s Lv%d" % [lus[i].get("name", ""), int(lus[i].get("level", 0))], Vector2(x, y + 120.0), 26, Palette.SOFT_SILVER)
			if not _sounded.has("lu%d" % i):
				_sounded["lu%d" % i] = true
				Sfx.play("level_up")
		if t > 1.0:
			_text(f, "Tap to continue", Vector2(vp.x / 2.0, vp.y * 0.86), 28, Color(Palette.SOFT_SILVER, 0.7))
	for p in _parts:
		if p.has("burst"):
			view.draw_circle(p.p, 5.0, Color(p.c, clampf(1.0 - p.age / p.life, 0.0, 1.0)))
	if _flash > 0.0:
		view.draw_rect(Rect2(Vector2.ZERO, vp), Color(1, 1, 1, _flash))


func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(c + Vector2.from_angle(a) * (r if i % 2 == 0 else r * 0.45))
	view.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	view.draw_polyline(pts, Palette.SIGIL_GOLD.darkened(0.3), 3.0, true)


func _text(f: Font, s: String, center: Vector2, size: int, col: Color) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := center - Vector2(w / 2.0, 0)
	view.draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 10, Palette.MIDNIGHT_NAVY)
	view.draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
