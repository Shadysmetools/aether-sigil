## The only procedural thing the scene layer draws: a glowing Sigil icon (crystal diamond in a broken ring).
## It stands in for a character who has no painted art yet, together with the name plate. We never draw
## procedural people: a cast member is a painted anime portrait (assets.gd resolver chain, a recoloured champion
## portrait) or just a name plate and this icon. Does NOT preload ui_art.gd (ui_art preloads this).
extends RefCounted

const Palette = preload("res://scripts/theme_colors.gd")


static func _halo(ci: CanvasItem, c: Vector2, r: float, col: Color, strength: float = 1.0) -> void:
	for i in 6:
		var k := float(i) / 6.0
		ci.draw_circle(c, r * (1.0 - k * 0.85), Color(col, 0.05 * strength * (1.0 - k) + 0.01))


## Glowing Sigil icon centred in r. `talk` 0..1 pulses the glow; t = seconds (slow turn of the ring).
static func draw_sigil_icon(ci: CanvasItem, r: Rect2, col: Color = Palette.CRYSTAL_VIOLET, talk: float = 0.0, t: float = 0.0, bg: bool = false) -> void:
	var gold := Palette.SIGIL_GOLD
	if bg:
		ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([Palette.MIDNIGHT_NAVY.lerp(col, 0.32), Palette.MIDNIGHT_NAVY.lerp(col, 0.32), Palette.MIDNIGHT_NAVY, Palette.MIDNIGHT_NAVY]))
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y)
	var pulse := 0.5 + 0.5 * sin(t * 3.0)
	var energy := 0.4 + 0.6 * talk
	_halo(ci, c, s * (0.5 + 0.06 * pulse * energy), col, 1.8)
	_halo(ci, c, s * (0.3 + 0.04 * pulse * energy), gold, 1.2 + energy)
	var a0 := t * 0.4
	ci.draw_arc(c, s * 0.3, a0 + 0.5, a0 + TAU - 0.5, 40, Color(gold, 0.95), maxf(2.0, s * 0.02), true)
	ci.draw_arc(c, s * 0.25, a0 + 0.5, a0 + TAU - 0.5, 40, Color(gold, 0.4), maxf(1.5, s * 0.008), true)
	var h := s * 0.2
	var w := s * 0.11
	var top := c + Vector2(0, -h)
	var bot := c + Vector2(0, h)
	ci.draw_colored_polygon(PackedVector2Array([top, c + Vector2(-w, 0), bot, c + Vector2(w * 0.1, h * 0.1)]), col.lerp(Palette.AETHER_CYAN, 0.35).lightened(0.3))
	ci.draw_colored_polygon(PackedVector2Array([top, c + Vector2(w * 0.1, h * 0.1), bot, c + Vector2(w, 0)]), col.darkened(0.2))
	ci.draw_polyline(PackedVector2Array([top, c + Vector2(-w, 0), bot, c + Vector2(w, 0), top]), Palette.SOFT_SILVER, maxf(1.5, s * 0.01), true)
	ci.draw_circle(top, maxf(2.0, s * 0.015), Color(1, 1, 1, 0.8))
