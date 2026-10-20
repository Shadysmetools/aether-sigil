## Placeholder art: EVERY board shape is drawn here and nowhere else. Swapping in sprites or a
## 3D scene later means replacing these functions; rules and layout code never draw.
## All colours come from theme_colors.gd. Isometric: a tile is a diamond w wide, h tall.
## Motifs (brand sheet): Sigil = compass star, Prism Core = faceted crystal (capsule node;
## deliberately NOT a banded sphere), Portal = violet ring, Relic = gold triangle.
extends RefCounted

const Palette = preload("res://scripts/theme_colors.gd")


static func font() -> Font:
	return ThemeDB.fallback_font


static func _diamond(c: Vector2, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(0, -h / 2), c + Vector2(w / 2, 0), c + Vector2(0, h / 2), c + Vector2(-w / 2, 0)])


## A tile as a block: top face lifted by `raise_px`, two shaded side faces. Returns the top centre.
static func draw_block(ci: CanvasItem, c: Vector2, w: float, h: float, top: Color, raise_px: float) -> Vector2:
	var lift := maxf(raise_px, 4.0)  # every tile is a thin slab at least
	var t := c - Vector2(0, lift)
	var left := PackedVector2Array([t + Vector2(-w / 2, 0), t + Vector2(0, h / 2), c + Vector2(0, h / 2), c + Vector2(-w / 2, 0)])
	var right := PackedVector2Array([t + Vector2(0, h / 2), t + Vector2(w / 2, 0), c + Vector2(w / 2, 0), c + Vector2(0, h / 2)])
	ci.draw_colored_polygon(left, top.darkened(0.38))
	ci.draw_colored_polygon(right, top.darkened(0.55))
	var face := _diamond(t, w, h)
	ci.draw_colored_polygon(face, top)
	face.append(face[0])
	ci.draw_polyline(face, Palette.MIDNIGHT_NAVY.lerp(top, 0.35), 1.5)
	return t


## Small surface marks so terrain reads without colour alone.
static func draw_terrain_mark(ci: CanvasItem, t: Vector2, w: float, h: float, type: String) -> void:
	var ink := Palette.tile(type).lightened(0.28)
	match type:
		"forest":
			for o in [Vector2(-w * 0.15, 0), Vector2(w * 0.12, -h * 0.1), Vector2(0, h * 0.14)]:
				ci.draw_colored_polygon(PackedVector2Array([t + o + Vector2(0, -h * 0.22), t + o + Vector2(w * 0.07, 0), t + o + Vector2(-w * 0.07, 0)]), ink)
		"water", "ice", "sky":
			for k in [-1, 1]:
				ci.draw_line(t + Vector2(-w * 0.2, k * h * 0.1), t + Vector2(w * 0.2, k * h * 0.1), ink, 2.0)
		"lava", "hazard":
			ci.draw_circle(t + Vector2(-w * 0.1, 0), h * 0.09, ink)
			ci.draw_circle(t + Vector2(w * 0.12, h * 0.06), h * 0.06, ink)
		"bridge":
			for k in [-2, -1, 0, 1, 2]:
				ci.draw_line(t + Vector2(k * w * 0.08 - w * 0.08, k * h * 0.08 + h * 0.08), t + Vector2(k * w * 0.08 + w * 0.08, k * h * 0.08 - h * 0.08), ink, 2.0)
		"crystal", "rift", "space", "shadow", "metal", "ruins", "mixed":
			ci.draw_colored_polygon(_diamond(t, w * 0.22, h * 0.22), ink)


## Prism Core: a faceted hexagonal crystal standing on the tile. Owner tints the facets.
static func draw_capsule_node(ci: CanvasItem, t: Vector2, w: float, h: float, owner: int) -> void:
	var col := Palette.side(owner)
	var ht := h * 0.95
	var hw := w * 0.13
	var base := t + Vector2(0, -h * 0.08)
	var top := base + Vector2(0, -ht)
	var mid_l := base + Vector2(-hw, -ht * 0.55)
	var mid_r := base + Vector2(hw, -ht * 0.55)
	var low_l := base + Vector2(-hw, -ht * 0.2)
	var low_r := base + Vector2(hw, -ht * 0.2)
	var mid_c := base + Vector2(0, -ht * 0.45)
	ci.draw_colored_polygon(PackedVector2Array([top, mid_l, low_l, base, mid_c]), col.darkened(0.15))
	ci.draw_colored_polygon(PackedVector2Array([top, mid_c, base, low_r, mid_r]), col.darkened(0.45))
	ci.draw_line(top, mid_c, col.lightened(0.5), 1.5)
	ci.draw_line(mid_c, base, col.lightened(0.3), 1.0)
	ci.draw_polyline(PackedVector2Array([top, mid_l, low_l, base, low_r, mid_r, top]), Palette.MIDNIGHT_NAVY, 1.5)


## Relic: gold triangle; filled when secured (owner ring), outline when open.
static func draw_relic(ci: CanvasItem, t: Vector2, w: float, h: float, owner: int) -> void:
	var s := h * 0.38
	var tri := PackedVector2Array([t + Vector2(0, -s * 1.4), t + Vector2(s, s * 0.2), t + Vector2(-s, s * 0.2)])
	ci.draw_colored_polygon(tri, Palette.SIGIL_GOLD if owner >= 0 else Palette.SIGIL_GOLD.darkened(0.45))
	tri.append(tri[0])
	ci.draw_polyline(tri, Palette.side(owner) if owner >= 0 else Palette.SIGIL_GOLD, 2.0)


## Portal: violet ring lying on the tile; bright when active.
static func draw_portal(ci: CanvasItem, t: Vector2, w: float, h: float, active: bool) -> void:
	var col := Palette.CRYSTAL_VIOLET if active else Palette.CRYSTAL_VIOLET.darkened(0.45)
	ci.draw_set_transform(t, 0.0, Vector2(1.0, 0.5))
	ci.draw_arc(Vector2.ZERO, w * 0.3, 0, TAU, 32, col, 5.0 if active else 3.0)
	if active:
		ci.draw_arc(Vector2.ZERO, w * 0.2, 0, TAU, 32, col.lightened(0.4), 2.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Sigil (a Symbol): gold eight-point compass star on a pillar, ringed in the owner colour, HP bar.
static func draw_symbol(ci: CanvasItem, t: Vector2, w: float, h: float, owner: int, hp: int, max_hp: int) -> void:
	var c := t + Vector2(0, -h * 0.75)
	var r := h * 0.62
	var pts := PackedVector2Array()
	for i in 16:
		var a := -PI / 2 + i * TAU / 16
		var rr := r if i % 4 == 0 else (r * 0.6 if i % 2 == 0 else r * 0.3)
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	ci.draw_circle(c, r * 0.95, Palette.side(owner).darkened(0.55))
	ci.draw_arc(c, r * 0.95, 0, TAU, 32, Palette.side(owner), 3.0)
	ci.draw_colored_polygon(pts, Palette.SIGIL_GOLD)
	ci.draw_circle(c, r * 0.14, Palette.MIDNIGHT_NAVY)
	_hp_bar(ci, c + Vector2(0, -r - 12), w * 0.6, hp, max_hp, Palette.side(owner))


static func _hp_bar(ci: CanvasItem, c: Vector2, width: float, hp: int, max_hp: int, col: Color) -> void:
	var frac := clampf(float(hp) / maxf(1.0, float(max_hp)), 0.0, 1.0)
	var r := Rect2(c - Vector2(width / 2, 4), Vector2(width, 8))
	ci.draw_rect(r, Palette.MIDNIGHT_NAVY)
	ci.draw_rect(Rect2(r.position, Vector2(width * frac, 8)), col)
	ci.draw_rect(r, Palette.SOFT_SILVER.darkened(0.3), false, 1.0)


## Monster token: family-coloured disc, owner ring, element initial, HP number underneath.
static func draw_unit(ci: CanvasItem, t: Vector2, w: float, h: float, owner: int, family: String, element: String, hp: int, max_hp: int, spent: bool) -> void:
	var r := h * 0.5
	var c := t + Vector2(0, -r * 0.9)
	ci.draw_set_transform(t, 0.0, Vector2(1.0, 0.5))
	ci.draw_circle(Vector2.ZERO, r * 1.05, Color(0, 0, 0, 0.35))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var fill := Palette.family(family)
	if spent:
		fill = fill.lerp(Palette.MIDNIGHT_NAVY, 0.45)
	ci.draw_circle(c, r, fill)
	ci.draw_arc(c, r, 0, TAU, 32, Palette.side(owner), 4.0)
	var f := font()
	var fs := int(r * 1.1)
	var letter := element.substr(0, 1).to_upper()
	var tw := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string_outline(f, c + Vector2(-tw / 2, fs * 0.36), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Palette.MIDNIGHT_NAVY)
	ci.draw_string(f, c + Vector2(-tw / 2, fs * 0.36), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.SOFT_SILVER)
	var hs := str(hp)
	var hfs := int(h * 0.42)
	var hw := f.get_string_size(hs, HORIZONTAL_ALIGNMENT_LEFT, -1, hfs).x
	var hp_pos := c + Vector2(-hw / 2, r + hfs * 0.95)
	ci.draw_string_outline(f, hp_pos, hs, HORIZONTAL_ALIGNMENT_LEFT, -1, hfs, 4, Palette.MIDNIGHT_NAVY)
	ci.draw_string(f, hp_pos, hs, HORIZONTAL_ALIGNMENT_LEFT, -1, hfs, Palette.side(owner) if hp * 2 > max_hp else Palette.EMBER.lightened(0.3))


## Move / attack / deploy highlight on a tile's top face.
static func draw_highlight(ci: CanvasItem, t: Vector2, w: float, h: float, col: Color) -> void:
	var face := _diamond(t, w * 0.9, h * 0.9)
	ci.draw_colored_polygon(face, Color(col, 0.35))
	face.append(face[0])
	ci.draw_polyline(face, col, 2.5)
