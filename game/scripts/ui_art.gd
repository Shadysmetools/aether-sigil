## HUD and screen art: fonts, gold-trimmed panel styles, dialogue portraits, turn-order chips and
## world-map tower cards. Textures come from assets.gd; each piece has a procedural fallback here so
## the game looks finished before painted art arrives, and painted art replaces it with no code change.
## Colours only from theme_colors.gd.
extends RefCounted

const Palette = preload("res://scripts/theme_colors.gd")
const Assets = preload("res://scripts/assets.gd")
const Data = preload("res://scripts/data_loader.gd")

const CINZEL := "res://art/intro/fonts/cinzel/Cinzel-Variable.ttf"
const NUNITO := "res://art/intro/fonts/nunito/Nunito-Variable.ttf"
const N := Palette.MIDNIGHT_NAVY
const GOLD := Palette.SIGIL_GOLD

static var _fonts: Dictionary = {}
static var _speaker_family: Dictionary = {}
static var _glow_tex: Texture2D


# ---------------------------------------------------------------- fonts

## Bundled variable font at a weight (falls back to the engine font).
static func font(display: bool = false, weight: int = 600) -> Font:
	var key := "%s%d" % [display, weight]
	if _fonts.has(key):
		return _fonts[key]
	var fv := FontVariation.new()
	var path := CINZEL if display else NUNITO
	if ResourceLoader.exists(path):
		fv.base_font = load(path)
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	else:
		fv.base_font = ThemeDB.fallback_font
	if display:
		fv.spacing_glyph = 1
	_fonts[key] = fv
	return fv


## Theme for the whole UI: Nunito body text, linear-filtered textures.
static func theme(size: int) -> Theme:
	var t := Theme.new()
	t.default_font = font(false, 600)
	t.default_font_size = size
	return t


# ---------------------------------------------------------------- styles

## Gold-trimmed navy panel: the panel_border nine-patch (painted or generated), else a flat chamfer.
static func panel_style(edge: Color = GOLD, alpha: float = 0.93) -> StyleBox:
	var tex := Assets.ui("panel/panel_border")
	if tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		var m := 56.0 * tex.get_width() / 384.0
		sb.texture_margin_left = m
		sb.texture_margin_right = m
		sb.texture_margin_top = m
		sb.texture_margin_bottom = m
		sb.set_content_margin_all(24)
		sb.modulate_color = Color(Color.WHITE.lerp(edge, 0.0 if edge == GOLD else 0.55), alpha)
		return sb
	return chamfer(Color(N.lerp(Palette.SOFT_SILVER, 0.06), alpha), edge, 3, 18)


## Navy fill, coloured border, chamfered (cut) corners: the button/chip language of the brand sheet.
static func chamfer(bg: Color, edge: Color, border: int = 2, cut: int = 12, shadow: bool = true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(cut)
	sb.corner_detail = 1
	sb.set_content_margin_all(12)
	sb.anti_aliasing = true
	if shadow:
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 3)
	return sb


## Section header plaque (panel_header nine-patch) for "TURN ORDER", "OBJECTIVES", name plates.
static func header_style() -> StyleBox:
	var tex := Assets.ui("panel/panel_header")
	if tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		var m := 40.0 * tex.get_width() / 384.0
		sb.texture_margin_left = m
		sb.texture_margin_right = m
		sb.content_margin_left = 34
		sb.content_margin_right = 34
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		return sb
	return chamfer(N.lerp(Palette.SOFT_SILVER, 0.1), GOLD, 2, 14, false)


# ---------------------------------------------------------------- drawing helpers

## Vertical gradient quad.
static func vgrad(ci: CanvasItem, r: Rect2, top: Color, bottom: Color) -> void:
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))


## Soft radial glow made of stacked translucent discs.
static func glow(ci: CanvasItem, c: Vector2, r: float, col: Color, _steps: int = 0) -> void:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.45))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 128
		gt.height = 128
		_glow_tex = gt
	ci.draw_texture_rect(_glow_tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2), false, col)


## Texture drawn to cover rect (centre crop), like CSS background-size: cover.
static func draw_cover(ci: CanvasItem, tex: Texture2D, r: Rect2, focus_y: float = 0.4, mod: Color = Color.WHITE) -> void:
	var ts := Vector2(tex.get_size())
	var s := maxf(r.size.x / ts.x, r.size.y / ts.y)
	var src_size := r.size / s
	var src_pos := Vector2((ts.x - src_size.x) * 0.5, clampf((ts.y - src_size.y) * focus_y, 0.0, ts.y - src_size.y))
	ci.draw_texture_rect_region(tex, r, Rect2(src_pos, src_size), mod)


## Chamfered gold frame line around r (double rule, corner diamonds).
static func gold_frame(ci: CanvasItem, r: Rect2, cut: float = 14.0, col: Color = GOLD, width: float = 3.0) -> void:
	var pts := func(rr: Rect2, k: float) -> PackedVector2Array:
		var p := rr.position
		var e := rr.end
		return PackedVector2Array([p + Vector2(k, 0), Vector2(e.x - k, p.y), Vector2(e.x, p.y + k), Vector2(e.x, e.y - k),
			Vector2(e.x - k, e.y), Vector2(p.x + k, e.y), Vector2(p.x, e.y - k), Vector2(p.x, p.y + k), p + Vector2(k, 0)])
	ci.draw_polyline(pts.call(r, cut), col, width, true)
	ci.draw_polyline(pts.call(r.grow(-6), cut * 0.7), Color(col, 0.45), 1.0, true)
	for c in [Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y)]:
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0)]), col)


# ---------------------------------------------------------------- speakers

## Element family that colours a speaker: tower bosses and stage rivals take their tower's family.
static func speaker_family(who: String) -> String:
	if _speaker_family.is_empty():
		var fam_of := func(tid: String) -> String:
			for t in Data.towers():
				if str(t.tower_id) == tid:
					return str(Data.rules().get("tower_theme_family", {}).get(str(t.theme), "Light"))
			return "Light"
		for st in Data.stages():
			var f: String = fam_of.call(str(st.tower_id))
			_speaker_family[str(st.opponent)] = f
		for t in Data.towers():
			_speaker_family[str(t.tower_boss)] = fam_of.call(str(t.tower_id))
		_speaker_family["Narrator"] = ""
		_speaker_family[str(Data.story().get("protagonist", {}).get("name", "Hero"))] = ""
	return str(_speaker_family.get(who, ""))


## Accent colour of a speaker's portrait.
static func speaker_color(who: String) -> Color:
	if who == "Narrator" or who == "":
		return GOLD
	if who == str(Data.story().get("protagonist", {}).get("name", "Hero")):
		return Palette.AETHER_CYAN
	var fam := speaker_family(who)
	if fam != "":
		return Palette.family(fam)
	var accents := [Palette.VERDANT_GREEN, Palette.EMBER, Palette.CRYSTAL_VIOLET, Palette.AETHER_CYAN.lerp(Palette.SOFT_SILVER, 0.3)]
	return accents[absi(hash(who)) % accents.size()]


## Dialogue portrait: painted art if present, else a lit character silhouette in the speaker's colour
## (the Narrator gets the Aether Sigil crystal). Always framed in gold.
static func draw_portrait(ci: CanvasItem, r: Rect2, who: String) -> void:
	var tex := Assets.portrait(who)
	var col := speaker_color(who)
	if tex != null:
		var tall := tex.get_height() > tex.get_width() * 1.5   # champion card crops: face sits low
		draw_cover(ci, tex, r, 0.62 if tall else 0.25)
	elif who == "Narrator" or who == "":
		_draw_narrator(ci, r)
	else:
		_draw_silhouette(ci, r, who, col)
	gold_frame(ci, r, r.size.x * 0.09, GOLD, 4.0)


static func _draw_narrator(ci: CanvasItem, r: Rect2) -> void:
	vgrad(ci, r, N.lerp(Palette.CRYSTAL_VIOLET, 0.35), N)
	var c := r.get_center()
	var s := r.size.x
	glow(ci, c, s * 0.48, Color(Palette.CRYSTAL_VIOLET, 0.9))
	ci.draw_arc(c, s * 0.34, 0, TAU, 64, Color(GOLD, 0.9), 3.0, true)
	ci.draw_arc(c, s * 0.29, 0, TAU, 64, Color(GOLD, 0.45), 1.5, true)
	var star := PackedVector2Array()
	for i in 16:
		var a := -PI / 2 + i * TAU / 16
		var rr := s * 0.44 if i % 4 == 0 else (s * 0.2 if i % 2 == 0 else s * 0.1)
		star.append(c + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(star, Color(GOLD, 0.85))
	var h := s * 0.25
	var w := s * 0.13
	var top := c + Vector2(0, -h)
	var bot := c + Vector2(0, h)
	ci.draw_colored_polygon(PackedVector2Array([top, c + Vector2(-w, 0), bot, c + Vector2(w * 0.1, h * 0.1)]), Palette.CRYSTAL_VIOLET.lerp(Palette.AETHER_CYAN, 0.35).lightened(0.25))
	ci.draw_colored_polygon(PackedVector2Array([top, c + Vector2(w * 0.1, h * 0.1), bot, c + Vector2(w, 0)]), Palette.CRYSTAL_VIOLET.darkened(0.2))
	ci.draw_polyline(PackedVector2Array([top, c + Vector2(-w, 0), bot, c + Vector2(w, 0), top]), Palette.SOFT_SILVER, 1.5, true)
	glow(ci, top, s * 0.06, Color(Palette.SOFT_SILVER, 1.0), 3)


static func _draw_silhouette(ci: CanvasItem, r: Rect2, who: String, col: Color) -> void:
	var s := r.size.x
	var o := r.position
	var p := func(x: float, y: float) -> Vector2:
		return o + Vector2(x * s, y * r.size.y)
	vgrad(ci, r, N.lerp(col, 0.42), N.lerp(col, 0.08))
	glow(ci, p.call(0.5, 0.42), s * 0.5, Color(col.lightened(0.2), 0.8))
	var h := absi(hash(who))
	var style := h % 3
	var body := N.lerp(col, 0.12)
	var rim := col.lightened(0.35)
	# shoulders and coat
	var coat := PackedVector2Array([p.call(0.04, 1.0), p.call(0.1, 0.8), p.call(0.26, 0.7), p.call(0.4, 0.66), p.call(0.43, 0.6),
		p.call(0.57, 0.6), p.call(0.6, 0.66), p.call(0.74, 0.7), p.call(0.9, 0.8), p.call(0.96, 1.0)])
	if style == 1:  # long hair falls over the shoulders
		ci.draw_colored_polygon(PackedVector2Array([p.call(0.3, 0.3), p.call(0.7, 0.3), p.call(0.74, 0.62), p.call(0.66, 0.84), p.call(0.34, 0.84), p.call(0.26, 0.62)]), body.darkened(0.15))
	ci.draw_colored_polygon(coat, body)
	ci.draw_polyline(PackedVector2Array([p.call(0.1, 0.8), p.call(0.26, 0.7), p.call(0.4, 0.66)]), rim, 2.0, true)
	ci.draw_polyline(PackedVector2Array([p.call(0.6, 0.66), p.call(0.74, 0.7), p.call(0.9, 0.8)]), Color(rim, 0.55), 2.0, true)
	# gold collar + emblem (the summoners' black-and-gold coats)
	ci.draw_polyline(PackedVector2Array([p.call(0.36, 0.7), p.call(0.5, 0.82), p.call(0.64, 0.7)]), GOLD, 3.0, true)
	var em: Vector2 = p.call(0.5, 0.9)
	ci.draw_colored_polygon(PackedVector2Array([em + Vector2(0, -s * 0.04), em + Vector2(s * 0.025, 0), em + Vector2(0, s * 0.04), em + Vector2(-s * 0.025, 0)]), col.lightened(0.3))
	# head
	var hc: Vector2 = p.call(0.5, 0.43)
	var hr := s * 0.155
	if style == 2:  # hood
		ci.draw_colored_polygon(PackedVector2Array([hc + Vector2(-hr * 1.45, hr * 1.6), hc + Vector2(-hr * 1.4, -hr * 0.4), hc + Vector2(0, -hr * 1.55), hc + Vector2(hr * 1.4, -hr * 0.4), hc + Vector2(hr * 1.45, hr * 1.6)]), body.darkened(0.2))
	ci.draw_circle(hc, hr, body.lightened(0.04))
	ci.draw_arc(hc, hr, -PI * 0.95, -PI * 0.35, 24, rim, 2.5, true)
	if style == 0:  # spiky crown of hair
		var spikes := PackedVector2Array([hc + Vector2(-hr * 1.15, hr * 0.1)])
		for i in 7:
			var a := PI + i * PI / 6.0
			var rr := hr * (1.55 if i % 2 == 0 else 1.05)
			spikes.append(hc + Vector2(cos(a), sin(a)) * rr + Vector2(0, -hr * 0.05))
		spikes.append(hc + Vector2(hr * 1.15, hr * 0.1))
		spikes.append(hc + Vector2(0, -hr * 0.35))
		ci.draw_colored_polygon(spikes, body.darkened(0.25))
	elif style == 1:
		ci.draw_colored_polygon(PackedVector2Array([hc + Vector2(-hr * 1.1, hr * 0.4), hc + Vector2(-hr * 0.9, -hr * 0.9), hc + Vector2(0, -hr * 1.2), hc + Vector2(hr * 0.9, -hr * 0.9), hc + Vector2(hr * 1.1, hr * 0.4), hc + Vector2(0, -hr * 0.45)]), body.darkened(0.25))
	# eyes: two lit slits
	var eye := col.lightened(0.55)
	for dx in [-0.38, 0.38]:
		var e: Vector2 = hc + Vector2(dx * hr, hr * 0.12)
		ci.draw_line(e + Vector2(-hr * 0.17, 0), e + Vector2(hr * 0.17, -hr * 0.04), eye, 3.0, true)
		ci.draw_circle(e, hr * 0.07, Color(eye, 0.6))
	# element sigil of their tower
	var fam := speaker_family(who)
	var icon := Assets.element_icon(fam) if fam != "" else null
	if icon != null:
		var isz := s * 0.26
		ci.draw_texture_rect(icon, Rect2(r.end - Vector2(isz, isz) - Vector2(s * 0.05, r.size.y * 0.05), Vector2(isz, isz)), false)


# ---------------------------------------------------------------- creature art for chips/buttons

## Draws a creature into r: painted monster (bust crop) or tinted silhouette on its element frame.
static func draw_creature(ci: CanvasItem, r: Rect2, mon_id: String, family: String, role: String, mod: Color = Color.WHITE) -> void:
	var tex := Assets.monster(mon_id, family)
	if tex != null:
		draw_cover(ci, tex, r, 0.15, mod)
		return
	var fc := Palette.family(family)
	vgrad(ci, r, N.lerp(fc, 0.45) * mod, N.lerp(fc, 0.12) * mod)
	var sil := Assets.silhouette(role)
	if sil != null:
		ci.draw_texture_rect(sil, r.grow(-r.size.x * 0.1), false, Palette.SOFT_SILVER.lerp(fc, 0.35) * mod)


## Turn-order chip art: slot frame (team, active), creature or sigil inside, order number.
static func draw_chip(ci: CanvasItem, r: Rect2, idx: int, side: int, active: bool, sigil: bool, mon_id: String, family: String, role: String) -> void:
	var team := Palette.side(side)
	var inner := r.grow(-r.size.x * 16.0 / 144.0)
	var slot := Assets.ui("turn_order/slot_%s%s" % ["ally" if side == 0 else "enemy", "_active" if active else ""])
	if slot != null:
		ci.draw_texture_rect(slot, r, false)
	else:
		ci.draw_rect(r, team, false, 3.0)
	if sigil:
		vgrad(ci, inner, N.lerp(team, 0.45), N)
		var p := Assets.prop("player_sigil" if side == 0 else "enemy_sigil")
		if p != null:
			draw_cover(ci, p, inner.grow(inner.size.x * 0.2), 0.32)
	else:
		draw_creature(ci, inner, mon_id, family, role)
	var f := font(true, 700)
	var fs := int(r.size.y * 0.3)
	ci.draw_string_outline(f, r.position + Vector2(r.size.x * 0.05, fs * 0.95), str(idx), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, N)
	ci.draw_string(f, r.position + Vector2(r.size.x * 0.05, fs * 0.95), str(idx), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.SOFT_SILVER)


# ---------------------------------------------------------------- tower cards

## A world-map tower card: painted tower scene, else a floating spire on a family-coloured sky.
static func draw_tower_card(ci: CanvasItem, r: Rect2, tid: String, family: String, open: bool) -> void:
	var fc := Palette.family(family)
	var art := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.66))
	var tex := Assets.tower_art(tid)
	if tex != null:
		draw_cover(ci, tex, art, 0.35)
	else:
		vgrad(ci, art, N.lerp(fc, 0.35), fc.lerp(Palette.SOFT_SILVER, 0.35).lerp(N, 0.15))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("card" + tid)
		for i in 5:  # clouds
			var cc := art.position + Vector2(rng.randf() * art.size.x, art.size.y * (0.45 + rng.randf() * 0.5))
			glow(ci, cc, art.size.x * (0.12 + rng.randf() * 0.12), Color(Palette.SOFT_SILVER, 0.45), 4)
		glow(ci, art.position + art.size * Vector2(0.5, 0.45), art.size.x * 0.45, Color(fc.lightened(0.4), 0.7))
		_spire_island(ci, art.position + art.size * Vector2(0.5, 0.62), art.size.x * 0.5, fc, rng)
	# caption band
	var cap := Rect2(Vector2(r.position.x, art.end.y), Vector2(r.size.x, r.end.y - art.end.y))
	vgrad(ci, Rect2(art.position + Vector2(0, art.size.y * 0.6), Vector2(art.size.x, art.size.y * 0.4)), Color(N, 0.0), Color(N, 0.92))
	vgrad(ci, cap, Color(N, 0.92), N)
	if not open:
		ci.draw_rect(r, Color(N, 0.55))
		var lc := r.position + r.size * Vector2(0.88, 0.09)
		var lw := r.size.x * 0.06
		ci.draw_arc(lc + Vector2(0, -lw * 0.3), lw * 0.5, PI, TAU, 16, GOLD.darkened(0.25), 3.0, true)
		ci.draw_rect(Rect2(lc - Vector2(lw * 0.7, lw * 0.3), Vector2(lw * 1.4, lw * 1.05)), GOLD.darkened(0.25))
		ci.draw_circle(lc + Vector2(0, lw * 0.2), lw * 0.16, N)


## Floating island with a cluster of spires (procedural tower silhouette).
static func _spire_island(ci: CanvasItem, c: Vector2, w: float, col: Color, rng: RandomNumberGenerator) -> void:
	var rock := N.lerp(col, 0.25)
	var lit := col.lightened(0.25)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-w * 0.5, 0), c + Vector2(w * 0.5, 0), c + Vector2(w * 0.3, w * 0.2),
		c + Vector2(w * 0.12, w * 0.32), c + Vector2(0, w * 0.5), c + Vector2(-w * 0.14, w * 0.3), c + Vector2(-w * 0.34, w * 0.18)]), rock.darkened(0.2))
	ci.draw_line(c + Vector2(-w * 0.5, 0), c + Vector2(w * 0.5, 0), lit, 2.0, true)
	var spires := [[0.0, 0.95, 0.12], [-0.22, 0.6, 0.09], [0.22, 0.68, 0.09], [-0.38, 0.38, 0.07], [0.37, 0.42, 0.07]]
	for sp in spires:
		var x: float = c.x + sp[0] * w
		var hgt: float = sp[1] * w * (0.85 + rng.randf() * 0.3)
		var hw: float = sp[2] * w
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x - hw, c.y), Vector2(x - hw, c.y - hgt * 0.7), Vector2(x, c.y - hgt),
			Vector2(x + hw, c.y - hgt * 0.7), Vector2(x + hw, c.y)]), rock)
		ci.draw_line(Vector2(x - hw, c.y - hgt * 0.7), Vector2(x, c.y - hgt), lit, 2.0, true)
		ci.draw_circle(Vector2(x, c.y - hgt * 0.45), hw * 0.3, Color(GOLD, 0.85))
