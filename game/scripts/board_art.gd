## Placeholder art: EVERY board shape is drawn here and nowhere else. Swapping in sprites or a
## 3D scene later means replacing these functions; rules and layout code never draw.
## All colours come from theme_colors.gd. Isometric: a tile is a diamond w wide, h tall.
## Motifs (brand sheet): Sigil = compass star, Prism Core = faceted crystal (capsule node;
## deliberately NOT a banded sphere), Portal = violet ring, Relic = gold triangle.
extends RefCounted

const Palette = preload("res://scripts/theme_colors.gd")
const Assets = preload("res://scripts/assets.gd")


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


## Sigil (a side's Symbol, the commander): a large faceted crystal floating over a stone pedestal
## that carries the gold compass-star motif, ringed in the owner colour, with an HP bar.
## Deliberately bigger and taller than the capsule-node Prism so the two never read alike.
static func draw_symbol(ci: CanvasItem, t: Vector2, w: float, h: float, owner: int, hp: int, max_hp: int) -> void:
	var side := Palette.side(owner)
	# pedestal: a small raised block
	var pw := w * 0.5
	var ph := h * 0.5
	var lift := h * 0.45
	var base := t
	var top := base - Vector2(0, lift)
	var left := PackedVector2Array([top + Vector2(-pw / 2, 0), top + Vector2(0, ph / 2), base + Vector2(0, ph / 2), base + Vector2(-pw / 2, 0)])
	var right := PackedVector2Array([top + Vector2(0, ph / 2), top + Vector2(pw / 2, 0), base + Vector2(pw / 2, 0), base + Vector2(0, ph / 2)])
	var stone := Palette.SOFT_SILVER.lerp(Palette.MIDNIGHT_NAVY, 0.45)
	ci.draw_colored_polygon(left, stone.darkened(0.3))
	ci.draw_colored_polygon(right, stone.darkened(0.5))
	ci.draw_colored_polygon(_diamond(top, pw, ph), stone)
	# owner ring on the pedestal top
	ci.draw_set_transform(top, 0.0, Vector2(1.0, 0.5))
	ci.draw_arc(Vector2.ZERO, pw * 0.42, 0, TAU, 32, side, 3.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# compass star on the pedestal's front face
	var star_c := base + Vector2(0, ph * 0.25 - lift * 0.45)
	var r := h * 0.2
	var pts := PackedVector2Array()
	for i in 16:
		var a := -PI / 2 + i * TAU / 16
		var rr := r if i % 4 == 0 else (r * 0.55 if i % 2 == 0 else r * 0.28)
		pts.append(star_c + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, Palette.SIGIL_GOLD)
	# floating crystal: tall bipyramid, two shaded facets, gold edge
	var cc := top + Vector2(0, -h * 0.95)
	var ch := h * 0.85
	var cw := w * 0.17
	var apex := cc + Vector2(0, -ch)
	var foot := cc + Vector2(0, ch * 0.45)
	var lft := cc + Vector2(-cw, 0)
	var rgt := cc + Vector2(cw, 0)
	var mid := cc + Vector2(cw * 0.15, ch * 0.05)
	ci.draw_colored_polygon(PackedVector2Array([apex, lft, foot, mid]), side.lightened(0.15))
	ci.draw_colored_polygon(PackedVector2Array([apex, mid, foot, rgt]), side.darkened(0.35))
	ci.draw_polyline(PackedVector2Array([apex, lft, foot, rgt, apex]), Palette.SIGIL_GOLD, 2.0)
	ci.draw_line(apex, mid, Palette.SOFT_SILVER, 1.0)
	_hp_bar(ci, apex + Vector2(0, -12), w * 0.6, hp, max_hp, side)


static func _hp_bar(ci: CanvasItem, c: Vector2, width: float, hp: int, max_hp: int, col: Color) -> void:
	var frac := clampf(float(hp) / maxf(1.0, float(max_hp)), 0.0, 1.0)
	var r := Rect2(c - Vector2(width / 2, 4), Vector2(width, 8))
	ci.draw_rect(r, Palette.MIDNIGHT_NAVY)
	ci.draw_rect(Rect2(r.position, Vector2(width * frac, 8)), col)
	ci.draw_rect(r, Palette.SOFT_SILVER.darkened(0.3), false, 1.0)


## Monster token: family-coloured disc, owner ring, element initial, HP number underneath.
static func draw_unit(ci: CanvasItem, t: Vector2, w: float, h: float, owner: int, family: String, element: String, hp: int, max_hp: int, spent: bool, dormant: bool = false) -> void:
	var r := h * 0.5
	var c := t + Vector2(0, -r * 0.9)
	ci.draw_set_transform(t, 0.0, Vector2(1.0, 0.5))
	ci.draw_circle(Vector2.ZERO, r * 1.05, Color(0, 0, 0, 0.35))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var fill := Palette.family(family)
	if spent:
		fill = fill.lerp(Palette.MIDNIGHT_NAVY, 0.45)
	if dormant:  # ruins statue: grey stone until it awakens
		fill = Palette.SOFT_SILVER.lerp(Palette.MIDNIGHT_NAVY, 0.5)
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


## Tactical minimap: top-down 12x12, player corner bottom-left (same side as the iso view).
## Tiles by type colour, Sigils as rings, monsters as dots, relics gold, capsule nodes as small prisms.
static func draw_minimap(ci: CanvasItem, rect: Rect2, state) -> void:
	if state == null or state.grid.is_empty():
		return
	var n := 12
	var cell := floorf(minf(rect.size.x, rect.size.y) / n)
	var origin := rect.position + (rect.size - Vector2(cell * n, cell * n)) / 2.0
	var at := func(c: Vector2i) -> Vector2:
		return origin + Vector2(c.x * cell, (n - 1 - c.y) * cell)
	ci.draw_rect(Rect2(origin - Vector2(2, 2), Vector2(cell * n + 4, cell * n + 4)), Palette.MIDNIGHT_NAVY)
	for y in n:
		for x in n:
			var c := Vector2i(x, y)
			ci.draw_rect(Rect2(at.call(c), Vector2(cell - 1, cell - 1)), Palette.tile(state.tile_type(c)))
	for c in state.relics:
		ci.draw_circle(at.call(c) + Vector2(cell, cell) / 2, cell * 0.3, Palette.SIGIL_GOLD)
	for c in state.nodes:
		var m: Vector2 = at.call(c) + Vector2(cell, cell) / 2
		ci.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -cell * 0.4), m + Vector2(cell * 0.25, 0), m + Vector2(0, cell * 0.4), m + Vector2(-cell * 0.25, 0)]), Palette.side(state.nodes[c]))
	for side in 2:
		var sp: Vector2 = at.call(state.symbol_pos[side]) + Vector2(cell, cell) / 2
		ci.draw_arc(sp, cell * 0.45, 0, TAU, 16, Palette.side(side), 2.5)
	for u in state.units:
		ci.draw_circle(at.call(u.pos) + Vector2(cell, cell) / 2, cell * 0.32, Palette.side(u.owner))


## Story portrait placeholder: a ringed disc in a colour picked from the speaker's name, with
## their initials. Replace with character art later (same signature).
static func draw_portrait(ci: CanvasItem, rect: Rect2, who: String) -> void:
	var accents := [Palette.AETHER_CYAN, Palette.VERDANT_GREEN, Palette.EMBER, Palette.CRYSTAL_VIOLET, Palette.SIGIL_GOLD]
	var col: Color = Palette.SOFT_SILVER if who == "Narrator" or who == "" else accents[absi(hash(who)) % accents.size()]
	var c := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.46
	ci.draw_circle(c, r, col.lerp(Palette.MIDNIGHT_NAVY, 0.55))
	ci.draw_arc(c, r, 0, TAU, 48, col, 4.0)
	var parts := who.split(" ", false)
	var initials := ""
	for w in parts.slice(0, 2):
		initials += w.substr(0, 1).to_upper()
	if initials == "":
		initials = "?"
	var f := font()
	var fs := int(r * 0.8)
	var tw := f.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(f, c + Vector2(-tw / 2, fs * 0.35), initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.SOFT_SILVER)


# ---------------------------------------------------------------- textured board (assets.gd)

## An isometric tile texture (contract: 256 px top face wide, ground anchor at 50% x, 77.5% y).
static func draw_tile_texture(ci: CanvasItem, tex: Texture2D, ground: Vector2, w: float) -> void:
	var ts := Vector2(tex.get_size())
	var s := w / ts.x
	var anchor := Vector2(ts.x * 0.5, ts.y * 248.0 / 320.0) * s
	ci.draw_texture_rect(tex, Rect2(ground - anchor, ts * s), false)


## A standing prop (contract: foot anchor at 50% x, 91.7% y) drawn `width` px wide on the top face.
## Returns the prop's top point (for HP bars).
static func draw_prop(ci: CanvasItem, tex: Texture2D, top: Vector2, width: float, mod: Color = Color.WHITE) -> Vector2:
	var ts := Vector2(tex.get_size())
	var s := width / ts.x
	var anchor := Vector2(ts.x * 0.5, ts.y * 352.0 / 384.0) * s
	ci.draw_texture_rect(tex, Rect2(top - anchor, ts * s), false, mod)
	return top - Vector2(0, anchor.y * 0.88)


## Owner glow ring on a tile's top face (capsule nodes, relics, Sigils); nothing when unowned.
static func draw_owner_glow(ci: CanvasItem, t: Vector2, w: float, h: float, owner: int) -> void:
	if owner < 0:
		return
	var col := Palette.side(owner)
	ci.draw_set_transform(t, 0.0, Vector2(1.0, 0.5))
	ci.draw_circle(Vector2.ZERO, w * 0.36, Color(col, 0.18))
	ci.draw_arc(Vector2.ZERO, w * 0.36, 0, TAU, 32, Color(col, 0.85), 2.5, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Public HP bar (team colour fill, gold rim, HP number on the left).
static func hp_bar(ci: CanvasItem, c: Vector2, width: float, hp: int, max_hp: int, col: Color) -> void:
	var frac := clampf(float(hp) / maxf(1.0, float(max_hp)), 0.0, 1.0)
	var r := Rect2(c - Vector2(width / 2, 5), Vector2(width, 10))
	ci.draw_rect(r.grow(1.5), Palette.MIDNIGHT_NAVY)
	ci.draw_rect(Rect2(r.position, Vector2(width * frac, r.size.y)), col if frac > 0.5 else Palette.EMBER.lerp(Palette.SIGIL_GOLD, frac * 1.6))
	ci.draw_rect(Rect2(r.position, Vector2(width * frac, 3)), Color(1, 1, 1, 0.3))
	ci.draw_rect(r.grow(1.5), Palette.SIGIL_GOLD.darkened(0.2), false, 1.0)
	var f := font()
	var s := str(hp)
	var fs := 14
	var tw := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := Vector2(r.position.x - tw - 4, c.y + fs * 0.36)
	ci.draw_string_outline(f, tp, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Palette.MIDNIGHT_NAVY)
	ci.draw_string(f, tp, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.SOFT_SILVER)


## Monster on the board: team tile glow, then the painted creature standing on the tile (contract:
## 512x512, foot at 50% x, 92% y) or the generated token frame with a tinted silhouette; HP bar
## and element badge. Spent = dimmed; dormant statue = stone grey.
static func draw_monster(ci: CanvasItem, t: Vector2, w: float, h: float, u, spent: bool) -> void:
	var team := Palette.side(u.owner)
	var face := _diamond(t, w * 0.9, h * 0.9)
	ci.draw_colored_polygon(face, Color(team, 0.1 if u.dormant else 0.26))
	face.append(face[0])
	ci.draw_polyline(face, Color(team, 0.45 if u.dormant else 0.95), 2.0, true)
	var mod := Color.WHITE
	if spent:
		mod = Color(0.6, 0.62, 0.72)
	if u.dormant:
		mod = Color(0.58, 0.6, 0.64)
	ci.draw_set_transform(t, 0.0, Vector2(1.0, 0.5))
	ci.draw_circle(Vector2.ZERO, w * 0.26, Color(0, 0, 0, 0.35))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var head := t
	var tex: Texture2D = Assets.monster(u.mon_id, u.family)
	if tex != null and not Assets.is_crop(tex):
		var ts := Vector2(tex.get_size())
		var s := w * 1.15 / ts.x
		var anchor := Vector2(ts.x * 0.5, ts.y * 0.92) * s
		ci.draw_texture_rect(tex, Rect2(t - anchor, ts * s), false, mod)
		head = t - Vector2(0, anchor.y * 0.95)
		var icon: Texture2D = Assets.element_icon(u.family)
		if icon != null:
			ci.draw_texture_rect(icon, Rect2(t + Vector2(w * 0.18, -h * 0.55), Vector2(24, 24)), false)
	else:
		var frame: Texture2D = Assets.token_frame(u.owner, u.family)
		if frame == null:
			draw_unit(ci, t, w, h, u.owner, u.family, u.element, u.hp, u.max_hp, spent, u.dormant)
			return
		var s := w * 1.12 / 256.0
		var origin := t - Vector2(128.0, 246.0) * s + Vector2(0, h * 0.12)
		var fc := Palette.family(u.family)
		ci.draw_texture_rect(frame, Rect2(origin, Vector2(256, 256) * s), false, mod)
		var slot_c := origin + Vector2(128, 120) * s
		ci.draw_circle(slot_c, 80.0 * s, Palette.MIDNIGHT_NAVY.lerp(fc, 0.38) * mod)
		ci.draw_circle(slot_c + Vector2(0, -20.0 * s), 52.0 * s, Color(fc.lightened(0.3), 0.25) * mod)
		var sil: Texture2D = Assets.silhouette(u.role)
		if tex != null:  # a concept-sheet crop: painted creature inside the medallion
			draw_texture_circle(ci, tex, slot_c, 80.0 * s, mod)
		elif sil != null:
			var box := 164.0 * 0.82 * s
			ci.draw_texture_rect(sil, Rect2(slot_c - Vector2(box, box) / 2, Vector2(box, box)), false, Palette.SOFT_SILVER.lerp(fc, 0.22) * mod)
		head = origin + Vector2(0, 2)
	hp_bar(ci, Vector2(t.x, head.y - 8), w * 0.56, u.hp, u.max_hp, team)


## The floating-island underside below the board's two front edges: rock cliff, a tapering
## jagged root fading into the sky, waterfalls where water tiles meet the edge, cloud wisps.
## corners = [top, right, bottom, left] of the board's ground diamond; falls = [[edge point, width]].
static func draw_island_underside(ci: CanvasItem, corners: PackedVector2Array, tid: String = "", falls: Array = []) -> void:
	var R := corners[1]
	var B := corners[2]
	var L := corners[3]
	var N := Palette.MIDNIGHT_NAVY
	var rock := Palette.SIGIL_GOLD.lerp(N, 0.66).lerp(Palette.SOFT_SILVER, 0.16)
	var haze := Palette.AETHER_CYAN.lerp(Palette.SOFT_SILVER, 0.55).lerp(N, 0.25)
	var cliff := 30.0
	var drop := (R.x - L.x) * 0.42
	var dl := Vector2(0, cliff)
	ci.draw_colored_polygon(PackedVector2Array([L, B, B + dl, L + dl]), rock.darkened(0.15))
	ci.draw_colored_polygon(PackedVector2Array([B, R, R + dl, B + dl]), rock.darkened(0.42))
	for k in [0.45, 0.8]:
		ci.draw_line(L + dl * k, B + dl * k, rock.darkened(0.35), 1.5, true)
		ci.draw_line(B + dl * k, R + dl * k, rock.darkened(0.6), 1.5, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("island" + tid)
	var tip := B + Vector2((rng.randf() - 0.5) * 60.0, drop)
	var pts := PackedVector2Array([L + dl, B + dl, R + dl])
	var cols := PackedColorArray([rock.darkened(0.3), rock.darkened(0.45), rock.darkened(0.55)])
	var steps := 9
	for i in range(1, steps):
		var f := float(i) / steps
		var p := (R + dl).lerp(tip, f) + Vector2(rng.randf_range(-18, 18), rng.randf_range(-10, 22) * (1.0 - f))
		p.x -= sin(f * PI) * 40.0
		pts.append(p)
		cols.append(rock.darkened(0.55).lerp(haze, f * 0.85))
	pts.append(tip)
	cols.append(Color(haze, 0.0))
	for i in range(steps - 1, 0, -1):
		var f := float(i) / steps
		var p := (L + dl).lerp(tip, f) + Vector2(rng.randf_range(-18, 18), rng.randf_range(-10, 22) * (1.0 - f))
		p.x += sin(f * PI) * 40.0
		pts.append(p)
		cols.append(rock.darkened(0.3).lerp(haze, f * 0.85))
	ci.draw_polygon(pts, cols)
	for i in 7:
		var f := (i + 0.5) / 7.0
		var a := (L + dl).lerp(B + dl, f) if i % 2 == 0 else (B + dl).lerp(R + dl, f)
		var ln := rng.randf_range(18, 46)
		ci.draw_colored_polygon(PackedVector2Array([a + Vector2(-9, -2), a + Vector2(9, -2), a + Vector2(rng.randf_range(-3, 3), ln)]), rock.darkened(0.5))
	for fl in falls:
		var a: Vector2 = fl[0]
		var fw: float = fl[1]
		var water := Palette.AETHER_CYAN.lerp(Palette.SOFT_SILVER, 0.6)
		ci.draw_polygon(PackedVector2Array([a + Vector2(-fw / 2, 0), a + Vector2(fw / 2, 0), a + Vector2(fw * 0.4, drop * 0.75), a + Vector2(-fw * 0.4, drop * 0.75)]),
			PackedColorArray([Color(water, 0.9), Color(water, 0.9), Color(water, 0.0), Color(water, 0.0)]))
		for k in 3:
			var x := (k - 1) * fw * 0.25
			ci.draw_line(a + Vector2(x, 4), a + Vector2(x * 0.8, drop * 0.5), Color(1, 1, 1, 0.35), 1.5, true)
	for i in 6:
		var cx := lerpf(L.x * 0.8, R.x * 0.8, rng.randf())
		var cy := B.y + drop * rng.randf_range(0.35, 0.95)
		var cr := rng.randf_range(50, 110)
		for k in 4:
			ci.draw_circle(Vector2(cx + k * cr * 0.35, cy), cr * (1.0 - k * 0.15), Color(Palette.SOFT_SILVER, 0.07))


## Texture clipped to a circle (square centre crop, biased to the upper part where faces are).
static func draw_texture_circle(ci: CanvasItem, tex: Texture2D, c: Vector2, r: float, mod: Color = Color.WHITE, focus_y: float = 0.3) -> void:
	var ts := Vector2(tex.get_size())
	var side := minf(ts.x, ts.y)
	var u0 := Vector2((ts.x - side) * 0.5 / ts.x, (ts.y - side) * focus_y / ts.y)
	var us := Vector2(side / ts.x, side / ts.y)
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 32:
		var d := Vector2.from_angle(i * TAU / 32.0)
		pts.append(c + d * r)
		uvs.append(u0 + (d * 0.5 + Vector2(0.5, 0.5)) * us)
	ci.draw_colored_polygon(pts, mod, uvs, tex)
