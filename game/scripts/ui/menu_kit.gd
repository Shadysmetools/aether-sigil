## Menu kit: the shared look and feel of the meta screens (title hub, compendium, squad, draft,
## evolution, fusion, settings). Vector glyphs (element/role/menu icons, Bond hex, SP crystal,
## rarity diamonds), button juice (press scale + SFX), screen transitions, and the UI prefs
## (reduced motion). Colours only from theme_colors.gd; every animation honours reduced_motion.
extends RefCounted

const Palette = preload("res://scripts/theme_colors.gd")
const UIArt = preload("res://scripts/ui_art.gd")
const Assets = preload("res://scripts/assets.gd")
const Data = preload("res://scripts/data_loader.gd")

const N := Palette.MIDNIGHT_NAVY
const GOLD := Palette.SIGIL_GOLD
const CYAN := Palette.AETHER_CYAN
const VIOLET := Palette.CRYSTAL_VIOLET
const SILVER := Palette.SOFT_SILVER
const EMBER := Palette.EMBER

const PREFS_PATH := "user://ui_prefs.cfg"
const HIT := 88.0            ## minimum touch target at 1080 width
const BODY := 26             ## body text size at 1080 width (13 px at the 540x960 window)

static var prefs_path := PREFS_PATH   ## tests point this at a temp file
static var reduced_motion := false
static var language := "en"
static var _prefs_loaded := false


# ---------------------------------------------------------------- prefs

static func load_prefs() -> void:
	_prefs_loaded = true
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(prefs_path) and cfg.load(prefs_path) == OK:
		reduced_motion = bool(cfg.get_value("ui", "reduced_motion", false))
		language = str(cfg.get_value("ui", "language", "en"))


static func save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "reduced_motion", reduced_motion)
	cfg.set_value("ui", "language", language)
	cfg.save(prefs_path)


static func motion() -> bool:
	if not _prefs_loaded:
		load_prefs()
	return not reduced_motion


# ---------------------------------------------------------------- rarity

## Rarity tiers from data (progression.json fusion.rarity_order): Common .. Legendary (6 with Mythic).
static func rarities() -> Array:
	return Array(Data.progression().fusion.rarity_order)


static func tier_of(rarity: String) -> int:
	return maxi(0, rarities().find(rarity))


## Frame metal per tier: iron, verdant, aether, crystal, ember-gold, sigil gold.
static func rarity_color(tier: int) -> Color:
	var cols := [SILVER.lerp(N, 0.42), Palette.VERDANT_GREEN.lerp(SILVER, 0.3), CYAN, VIOLET, EMBER.lerp(GOLD, 0.45), GOLD]
	return cols[clampi(tier, 0, cols.size() - 1)]


# ---------------------------------------------------------------- audio + juice

## Plays a HOOKS.md SFX id through the AudioManager autoload when it exists (guarded).
static func sfx(node: Node, id: String) -> void:
	if node == null or not node.is_inside_tree() or not node.has_node("/root/AudioManager"):
		return
	var am := node.get_node("/root/AudioManager")
	if am.has_method("play_sfx"):
		am.play_sfx(id)


## Press feedback for any Button: scale down on press, spring back with overshoot, SFX on tap.
static func juice(b: BaseButton, sfx_id: String = "ui_tap") -> void:
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	b.button_down.connect(func():
		if motion():
			b.create_tween().tween_property(b, "scale", Vector2.ONE * 0.94, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	b.button_up.connect(func():
		if motion():
			b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			b.scale = Vector2.ONE)
	if sfx_id != "":
		b.pressed.connect(func(): sfx(b, sfx_id if not b.disabled else "ui_locked"))


## Screen entrance: fade in and slide from `dir` (x px; + = from the right), eased out.
static func enter(c: CanvasItem, dir: float = 60.0, dur: float = 0.26) -> void:
	if not c.is_inside_tree():
		return
	if not motion():
		c.modulate.a = 1.0
		return
	c.modulate.a = 0.0
	var ctl := c as Control
	var tw := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, dur)
	if ctl != null and dir != 0.0:
		var base := ctl.position.x
		ctl.position.x = base + dir
		tw.tween_property(ctl, "position:x", base, dur)


## Children rise in one after another (title hub buttons, grids).
static func stagger(items: Array, step: float = 0.04, rise: float = 40.0) -> void:
	if not motion():
		return
	var i := 0
	for it in items:
		var c := it as Control
		if c == null or not c.is_inside_tree():
			continue
		c.modulate.a = 0.0
		var tw := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "modulate:a", 1.0, 0.3).set_delay(i * step)
		if rise != 0.0:
			# containers own position: lift through the visual offset of a transform-free child instead
			c.pivot_offset = c.size * 0.5
			c.scale = Vector2.ONE * 0.92
			tw.tween_property(c, "scale", Vector2.ONE, 0.34).set_delay(i * step).set_trans(Tween.TRANS_BACK)
		i += 1


## Small horizontal shake: a refused tap (over the Bond cap, locked).
static func shake(c: Control) -> void:
	if not motion() or not c.is_inside_tree():
		return
	var x := c.position.x
	var tw := c.create_tween()
	for d in [14.0, -11.0, 7.0, -4.0, 0.0]:
		tw.tween_property(c, "position:x", x + d, 0.045)


# ---------------------------------------------------------------- widgets

static func label(text: String, size: int, col: Color = SILVER, display: bool = false, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", N)
	l.add_theme_constant_override("outline_size", 6 if display else 3)
	if display:
		l.add_theme_font_override("font", UIArt.font(true, 700))
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Navy button with a gold edge; `accent` tints the edge (primary = gold, back = silver).
static func button(text: String, cb: Callable, min_h: float = 96.0, accent: Color = GOLD, sfx_id: String = "ui_tap") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(HIT, maxf(min_h, HIT))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_font_override("font", UIArt.font(true, 700))
	b.add_theme_color_override("font_color", SILVER)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", SILVER.darkened(0.55))
	var navy := N.lerp(SILVER, 0.07)
	b.add_theme_stylebox_override("normal", UIArt.chamfer(Color(navy, 0.95), accent.darkened(0.12), 2, 14))
	b.add_theme_stylebox_override("hover", UIArt.chamfer(Color(navy.lightened(0.06), 0.97), accent.lightened(0.15), 3, 14))
	b.add_theme_stylebox_override("pressed", UIArt.chamfer(CYAN.lerp(N, 0.62), CYAN, 3, 14))
	b.add_theme_stylebox_override("hover_pressed", UIArt.chamfer(CYAN.lerp(N, 0.55), CYAN, 3, 14))
	b.add_theme_stylebox_override("disabled", UIArt.chamfer(Color(N, 0.88), SILVER.lerp(N, 0.7), 2, 14))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if cb.is_valid():
		b.pressed.connect(cb)
	juice(b, sfx_id)
	return b


## Filter chip (toggle): 88x88 minimum, icon glyph drawn by a child, optional text.
static func chip(text: String, toggle: bool = true, min_w: float = HIT) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.custom_minimum_size = Vector2(min_w, HIT)
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_font_override("font", UIArt.font(true, 700))
	b.add_theme_color_override("font_color", SILVER.darkened(0.1))
	b.add_theme_color_override("font_pressed_color", N)
	b.add_theme_color_override("font_hover_pressed_color", N)
	b.add_theme_stylebox_override("normal", UIArt.chamfer(Color(N.lerp(SILVER, 0.06), 0.92), SILVER.lerp(N, 0.55), 2, 12, false))
	b.add_theme_stylebox_override("hover", UIArt.chamfer(Color(N.lerp(SILVER, 0.12), 0.95), GOLD.darkened(0.2), 2, 12, false))
	b.add_theme_stylebox_override("pressed", UIArt.chamfer(GOLD.lerp(N, 0.08), GOLD.lightened(0.2), 3, 12, false))
	b.add_theme_stylebox_override("hover_pressed", UIArt.chamfer(GOLD, GOLD.lightened(0.3), 3, 12, false))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	juice(b, "ui_page")
	return b


## Styles an OptionButton / LineEdit to the navy + gold language.
static func style_field(c: Control) -> void:
	c.custom_minimum_size.y = HIT
	c.add_theme_font_size_override("font_size", 26)
	c.add_theme_color_override("font_color", SILVER)
	c.add_theme_color_override("font_placeholder_color", SILVER.darkened(0.45))
	for st in ["normal", "hover", "pressed", "focus", "read_only"]:
		var edge := GOLD if st in ["focus", "pressed"] else GOLD.darkened(0.35)
		c.add_theme_stylebox_override(st, UIArt.chamfer(Color(N.lerp(SILVER, 0.05), 0.95), edge, 2, 12, false))
	if c is OptionButton:
		c.add_theme_font_override("font", UIArt.font(false, 700))
		var pop: PopupMenu = c.get_popup()
		pop.add_theme_font_size_override("font_size", 30)
		pop.add_theme_stylebox_override("panel", UIArt.chamfer(Color(N, 0.98), GOLD.darkened(0.2), 2, 10, true))
		pop.add_theme_constant_override("v_separation", 28)


## Gold section header plaque with a Cinzel title.
static func header(text: String, size: int = 30) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIArt.header_style())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, size, GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	p.add_child(l)
	return p


## Screen title block: big Cinzel title with a violet glow + a cyan subtitle.
static func title_block(title: String, sub: String = "") -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := label(title, 60, GOLD.lerp(SILVER, 0.18), true, HORIZONTAL_ALIGNMENT_CENTER)
	t.add_theme_constant_override("outline_size", 10)
	t.add_theme_color_override("font_shadow_color", Color(VIOLET, 0.55))
	t.add_theme_constant_override("shadow_offset_y", 4)
	v.add_child(t)
	var rule := Rule.new()
	rule.custom_minimum_size = Vector2(0, 18)
	v.add_child(rule)
	if sub != "":
		v.add_child(label(sub, 26, CYAN, false, HORIZONTAL_ALIGNMENT_CENTER))
	return v


## Thin gold rule with a centre diamond (under titles).
class Rule extends Control:
	const K = preload("res://scripts/ui/menu_kit.gd")
	func _draw() -> void:
		var c := size * 0.5
		var w := minf(size.x * 0.34, 360.0)
		draw_line(Vector2(c.x - w, c.y), Vector2(c.x - 14, c.y), Color(K.GOLD, 0.7), 2.0, true)
		draw_line(Vector2(c.x + 14, c.y), Vector2(c.x + w, c.y), Color(K.GOLD, 0.7), 2.0, true)
		K.diamond(self, c, 8.0, K.GOLD)


## A Control that paints one vector glyph (menu icon, role, element) centred in its rect.
class Glyph extends Control:
	const K = preload("res://scripts/ui/menu_kit.gd")
	var kind := ""        ## "menu:story", "role:Guardian", "element:Fire"
	var color := Color.WHITE

	func _init(p_kind: String = "", p_color: Color = Color.WHITE) -> void:
		kind = p_kind
		color = p_color
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var parts := kind.split(":")
		if parts.size() < 2:
			return
		match parts[0]:
			"menu": K.menu_icon(self, c, r, parts[1], color)
			"role": K.role_glyph(self, c, r * 0.8, parts[1], color)
			"element": K.element_badge(self, c, r, parts[1])


## Big icon button for the title hub: glyph disc on the left, Cinzel caption, subtitle line.
static func hub_button(text: String, sub: String, icon: String, cb: Callable, primary: bool = false) -> Button:
	var b := button("", cb, 150 if primary else 132, GOLD if primary else GOLD.darkened(0.25), "ui_confirm" if primary else "ui_tap")
	if primary:
		b.add_theme_stylebox_override("normal", UIArt.chamfer(Color(VIOLET.lerp(N, 0.72), 0.96), GOLD, 3, 18))
		b.add_theme_stylebox_override("hover", UIArt.chamfer(Color(VIOLET.lerp(N, 0.62), 0.98), GOLD.lightened(0.2), 4, 18))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 22
	row.offset_right = -16
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var g := Glyph.new("menu:" + icon, GOLD if primary else CYAN.lerp(SILVER, 0.2))
	g.custom_minimum_size = Vector2(96, 96) if primary else Vector2(80, 80)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(g)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 0)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tv)
	var t := label(text, 44 if primary else 34, GOLD.lerp(SILVER, 0.1) if primary else SILVER, true)
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	tv.add_child(t)
	if sub != "":
		var s := label(sub, 22, SILVER.darkened(0.25))
		s.autowrap_mode = TextServer.AUTOWRAP_OFF
		s.clip_text = true
		tv.add_child(s)
	b.set_meta("caption", text)
	return b


# ---------------------------------------------------------------- vector drawing

static func diamond(ci: CanvasItem, c: Vector2, r: float, col: Color, outline: Color = Color(0, 0, 0, 0)) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.72, 0), c + Vector2(0, r), c + Vector2(-r * 0.72, 0)])
	ci.draw_colored_polygon(pts, col)
	if outline.a > 0.0:
		pts.append(pts[0])
		ci.draw_polyline(pts, outline, maxf(1.0, r * 0.14), true)


static func hexagon(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := PI / 6.0 + i * TAU / 6.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## Bond cost badge: gold-rimmed navy hexagon with the number.
static func bond_badge(ci: CanvasItem, c: Vector2, r: float, value: int, warn: bool = false) -> void:
	var rim := EMBER if warn else GOLD
	ci.draw_colored_polygon(hexagon(c, r), rim.darkened(0.15))
	ci.draw_colored_polygon(hexagon(c, r * 0.82), N.lerp(rim, 0.18))
	var p := hexagon(c, r * 0.82)
	p.append(p[0])
	ci.draw_polyline(p, Color(rim.lightened(0.3), 0.8), maxf(1.0, r * 0.06), true)
	centered_text(ci, c + Vector2(0, -r * 0.05), str(value), int(r * 0.95), rim.lightened(0.35), true)
	centered_text(ci, c + Vector2(0, r * 0.52), "BOND", maxi(9, int(r * 0.3)), Color(rim, 0.95), false)


## SP crack-cost badge: aether crystal (tall diamond) with the number.
static func sp_badge(ci: CanvasItem, c: Vector2, r: float, value: int) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r * 1.12), c + Vector2(r * 0.82, 0), c + Vector2(0, r * 1.12), c + Vector2(-r * 0.82, 0)])
	ci.draw_colored_polygon(pts, CYAN.darkened(0.25))
	var inner := PackedVector2Array([c + Vector2(0, -r * 0.9), c + Vector2(r * 0.64, 0), c + Vector2(0, r * 0.9), c + Vector2(-r * 0.64, 0)])
	ci.draw_colored_polygon(inner, N.lerp(CYAN, 0.25))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.9), c + Vector2(r * 0.64, 0), c]), Color(CYAN.lightened(0.5), 0.25))
	centered_text(ci, c + Vector2(0, -r * 0.08), str(value), int(r * 0.92), CYAN.lightened(0.55), true)
	centered_text(ci, c + Vector2(0, r * 0.5), "SP", maxi(9, int(r * 0.32)), CYAN.lightened(0.3), false)


## Text centred on a point (vertically by font metrics), with a navy outline.
static func centered_text(ci: CanvasItem, c: Vector2, text: String, fs: int, col: Color, display: bool = true, outline: int = 4) -> void:
	var f := UIArt.font(display, 800 if not display else 700)
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := Vector2(c.x - sz.x * 0.5, c.y + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5)
	if outline > 0:
		ci.draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, N)
	ci.draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Element badge: painted element icon if present, else a family-coloured disc with its initial.
static func element_badge(ci: CanvasItem, c: Vector2, r: float, family: String) -> void:
	var fc := Palette.family(family)
	ci.draw_circle(c, r, N.lerp(fc, 0.25))
	ci.draw_arc(c, r, 0, TAU, 40, fc.lightened(0.25), maxf(1.5, r * 0.09), true)
	var icon := Assets.element_icon(family)
	if icon != null:
		ci.draw_texture_rect(icon, Rect2(c - Vector2(r, r) * 0.82, Vector2(r, r) * 1.64), false)
	else:
		centered_text(ci, c, family.left(1), int(r * 1.05), fc.lightened(0.45), true)


## Role glyphs (as on the compendium sheet): shield, sword, daggers, crosshair, wing, heart, spiral, eye.
static func role_glyph(ci: CanvasItem, c: Vector2, r: float, role: String, col: Color) -> void:
	var w := maxf(1.5, r * 0.16)
	match role:
		"Guardian":
			var s := PackedVector2Array([c + Vector2(-r * 0.8, -r * 0.8), c + Vector2(r * 0.8, -r * 0.8), c + Vector2(r * 0.8, -r * 0.1), c + Vector2(0, r), c + Vector2(-r * 0.8, -r * 0.1)])
			ci.draw_colored_polygon(s, Color(col, 0.25))
			s.append(s[0])
			ci.draw_polyline(s, col, w, true)
			ci.draw_line(c + Vector2(0, -r * 0.55), c + Vector2(0, r * 0.55), col, w * 0.8, true)
		"Striker":
			ci.draw_line(c + Vector2(-r * 0.75, r * 0.75), c + Vector2(r * 0.7, -r * 0.7), col, w * 1.2, true)
			ci.draw_line(c + Vector2(-r * 0.62, r * 0.18), c + Vector2(-r * 0.18, r * 0.62), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.85, -r * 0.85), c + Vector2(r * 0.45, -r * 0.62), c + Vector2(r * 0.62, -r * 0.45)]), col)
		"Assassin":
			ci.draw_line(c + Vector2(-r * 0.8, r * 0.8), c + Vector2(r * 0.8, -r * 0.8), col, w, true)
			ci.draw_line(c + Vector2(r * 0.8, r * 0.8), c + Vector2(-r * 0.8, -r * 0.8), col, w, true)
			ci.draw_line(c + Vector2(-r * 0.6, r * 0.2), c + Vector2(-r * 0.2, r * 0.6), col, w, true)
			ci.draw_line(c + Vector2(r * 0.6, r * 0.2), c + Vector2(r * 0.2, r * 0.6), col, w, true)
		"Artillery":
			ci.draw_arc(c, r * 0.62, 0, TAU, 32, col, w, true)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				ci.draw_line(c + d * r * 0.3, c + d * r, col, w, true)
			ci.draw_circle(c, r * 0.12, col)
		"Scout":
			for k in 2:
				var o := Vector2(-r * 0.35 + k * r * 0.55, 0)
				ci.draw_polyline(PackedVector2Array([c + o + Vector2(-r * 0.3, -r * 0.7), c + o + Vector2(r * 0.3, 0), c + o + Vector2(-r * 0.3, r * 0.7)]), col, w * 1.1, true)
		"Support":
			ci.draw_circle(c + Vector2(-r * 0.36, -r * 0.22), r * 0.4, col)
			ci.draw_circle(c + Vector2(r * 0.36, -r * 0.22), r * 0.4, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.74, -r * 0.08), c + Vector2(r * 0.74, -r * 0.08), c + Vector2(0, r * 0.8)]), col)
		"Summoner":
			var pts := PackedVector2Array()
			for i in 40:
				var t := i / 39.0
				var a := t * TAU * 1.6
				pts.append(c + Vector2(cos(a), sin(a)) * r * (0.12 + 0.82 * t))
			ci.draw_polyline(pts, col, w, true)
		"Controller":
			var eye := PackedVector2Array()
			for i in 17:
				var a := PI * i / 16.0
				eye.append(c + Vector2(-cos(a) * r * 0.9, -sin(a) * r * 0.5))
			for i in range(1, 16):
				var a := PI * i / 16.0
				eye.append(c + Vector2(cos(a) * r * 0.9, sin(a) * r * 0.5))
			eye.append(eye[0])
			ci.draw_polyline(eye, col, w, true)
			ci.draw_circle(c, r * 0.26, col)
		_:
			diamond(ci, c, r * 0.7, col)


## Title-hub menu icons: story (tower), squad, collection (book), fusion, evolution, settings (gear).
static func menu_icon(ci: CanvasItem, c: Vector2, r: float, kind: String, col: Color) -> void:
	ci.draw_circle(c, r * 0.98, Color(N.lerp(col, 0.12), 0.9))
	ci.draw_arc(c, r * 0.98, 0, TAU, 48, Color(col, 0.85), maxf(2.0, r * 0.05), true)
	UIArt.glow(ci, c, r * 0.9, Color(col, 0.18))
	var w := maxf(2.0, r * 0.07)
	var k := r * 0.55
	match kind:
		"story":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-k * 0.35, k), c + Vector2(-k * 0.35, -k * 0.3), c + Vector2(0, -k * 1.0), c + Vector2(k * 0.35, -k * 0.3), c + Vector2(k * 0.35, k)]), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-k * 0.95, k), c + Vector2(-k * 0.95, k * 0.1), c + Vector2(-k * 0.72, -k * 0.25), c + Vector2(-k * 0.5, k * 0.1), c + Vector2(-k * 0.5, k)]), Color(col, 0.7))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(k * 0.5, k), c + Vector2(k * 0.5, k * 0.1), c + Vector2(k * 0.72, -k * 0.25), c + Vector2(k * 0.95, k * 0.1), c + Vector2(k * 0.95, k)]), Color(col, 0.7))
			ci.draw_circle(c + Vector2(0, -k * 0.2), k * 0.13, N)
		"squad":
			for i in 3:
				var o := Vector2((i - 1) * k * 0.62, (0.15 if i != 1 else -0.1) * k)
				var s := PackedVector2Array([c + o + Vector2(-k * 0.34, -k * 0.45), c + o + Vector2(k * 0.34, -k * 0.45), c + o + Vector2(k * 0.34, k * 0.05), c + o + Vector2(0, k * 0.6), c + o + Vector2(-k * 0.34, k * 0.05)])
				ci.draw_colored_polygon(s, col if i == 1 else Color(col, 0.65))
				s.append(s[0])
				ci.draw_polyline(s, N, w * 0.6, true)
		"collection":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-k, -k * 0.7), c + Vector2(-k * 0.05, -k * 0.5), c + Vector2(-k * 0.05, k * 0.8), c + Vector2(-k, k * 0.6)]), Color(col, 0.75))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(k, -k * 0.7), c + Vector2(k * 0.05, -k * 0.5), c + Vector2(k * 0.05, k * 0.8), c + Vector2(k, k * 0.6)]), col)
			for i in 3:
				var y := -k * 0.2 + i * k * 0.28
				ci.draw_line(c + Vector2(k * 0.2, y), c + Vector2(k * 0.8, y + k * 0.06), N, w * 0.5, true)
		"fusion":
			ci.draw_arc(c + Vector2(-k * 0.35, 0), k * 0.62, 0, TAU, 36, col, w, true)
			ci.draw_arc(c + Vector2(k * 0.35, 0), k * 0.62, 0, TAU, 36, Color(col, 0.75), w, true)
			diamond(ci, c, k * 0.42, col)
		"evolution":
			for i in 3:
				var y := k * 0.7 - i * k * 0.62
				ci.draw_polyline(PackedVector2Array([c + Vector2(-k * 0.7, y + k * 0.35), c + Vector2(0, y - k * 0.2), c + Vector2(k * 0.7, y + k * 0.35)]), Color(col, 0.55 + i * 0.22), w * 1.2, true)
		"settings":
			var pts := PackedVector2Array()
			for i in 48:
				var a := i * TAU / 48.0
				var rr := k * (0.95 if (i / 3) % 2 == 0 else 0.72)
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c, k * 0.34, N)
		"back":
			ci.draw_polyline(PackedVector2Array([c + Vector2(k * 0.3, -k * 0.6), c + Vector2(-k * 0.35, 0), c + Vector2(k * 0.3, k * 0.6)]), col, w * 1.4, true)
		_:
			diamond(ci, c, k, col)


## Rarity diamonds: tier+1 filled in the rarity colour, the rest hollow (6 max).
static func rarity_pips(ci: CanvasItem, center: Vector2, r: float, tier: int, total: int = 6) -> void:
	var col := rarity_color(tier)
	var gap := r * 1.75
	var x0 := center.x - gap * (total - 1) * 0.5
	for i in total:
		var c := Vector2(x0 + i * gap, center.y)
		if i <= tier:
			diamond(ci, c, r, col.lightened(0.15), N)
		else:
			diamond(ci, c, r * 0.8, Color(N, 0.6), Color(SILVER, 0.35))
