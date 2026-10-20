## Placeholder art. Every piece is drawn here and nowhere else, so swapping in real
## sprites later means replacing these functions (e.g. with draw_texture_rect calls).
extends RefCounted

const HexGrid = preload("res://scripts/hex_grid.gd")

const COL_BG := Color("#0E1630")
const COL_PLAYER := Color("#F2A93B")
const COL_RIVAL := Color("#7B5CC4")
const COL_DARK := Color("#1D2850")
const COL_EDGE := Color("#0E1630")
const COL_TEXT := Color("#FFF6E5")
const ELEMENT_COLORS := {
	"Ember": Color("#E8572A"), "Tide": Color("#2F8FD8"), "Bloom": Color("#5BBF5A"),
	"Stone": Color("#9A8F80"), "Gale": Color("#C9E4E8"),
}


static func player_color(p: int) -> Color:
	return COL_PLAYER if p == 0 else COL_RIVAL


static func tile_color(owner: int) -> Color:
	match owner:
		0: return COL_PLAYER
		1: return COL_RIVAL
	return COL_DARK


static func font() -> Font:
	return ThemeDB.fallback_font


static func _text_centered(ci: CanvasItem, center: Vector2, text: String, size: int, color: Color) -> void:
	var f := font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var asc := f.get_ascent(size)
	var desc := f.get_descent(size)
	ci.draw_string(f, center + Vector2(-w / 2.0, (asc - desc) / 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func draw_tile(ci: CanvasItem, center: Vector2, size: float, owner: int) -> void:
	var pts := HexGrid.corners(size * 0.95)
	for i in pts.size():
		pts[i] += center
	ci.draw_colored_polygon(pts, tile_color(owner))
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_polyline(outline, COL_EDGE, 3.0)


static func draw_highlight(ci: CanvasItem, center: Vector2, size: float, color: Color) -> void:
	var pts := HexGrid.corners(size * 0.82)
	for i in pts.size():
		pts[i] += center
	pts.append(pts[0])
	ci.draw_polyline(pts, color, 6.0)


static func draw_hearth(ci: CanvasItem, center: Vector2, size: float, owner: int, hp: int) -> void:
	var c := player_color(owner)
	ci.draw_circle(center, size * 0.62, COL_BG)
	ci.draw_circle(center, size * 0.55, c.darkened(0.35))
	var flame := PackedVector2Array([
		center + Vector2(0, -size * 0.45), center + Vector2(size * 0.25, size * 0.05),
		center + Vector2(0, size * 0.3), center + Vector2(-size * 0.25, size * 0.05)])
	ci.draw_colored_polygon(flame, c.lightened(0.3))
	_text_centered(ci, center + Vector2(0, size * 0.42), str(hp), int(size * 0.34), COL_TEXT)


static func draw_post(ci: CanvasItem, center: Vector2, size: float, owner: int) -> void:
	var c := player_color(owner)
	var base := center + Vector2(size * 0.45, -size * 0.35)
	ci.draw_rect(Rect2(base + Vector2(-4, -2), Vector2(8, size * 0.42)), COL_BG)
	ci.draw_circle(base, size * 0.15, COL_BG)
	ci.draw_circle(base, size * 0.11, c.lightened(0.4))


static func draw_beacon(ci: CanvasItem, center: Vector2, size: float, owner: int) -> void:
	var col := COL_TEXT if owner < 0 else player_color(owner).lightened(0.25)
	var r := size * 0.7
	var pts := PackedVector2Array()
	for i in 4:
		var a := deg_to_rad(90.0 * i)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, 5.0)


## A Wick: owner-coloured ring, element-coloured body, initial letter, HP number.
static func draw_wick(ci: CanvasItem, center: Vector2, size: float, owner: int, element: String, wick_name: String, hp: int, exhausted: bool) -> void:
	var r := size * 0.5
	ci.draw_circle(center, r + 6, player_color(owner))
	var body: Color = ELEMENT_COLORS.get(element, Color.GRAY)
	if exhausted:
		body = body.darkened(0.45)
	ci.draw_circle(center, r, body)
	_text_centered(ci, center + Vector2(0, -r * 0.1), wick_name.substr(0, 1), int(size * 0.55), COL_TEXT)
	var badge := center + Vector2(r * 0.8, r * 0.8)
	ci.draw_circle(badge, size * 0.24, COL_BG)
	_text_centered(ci, badge, str(hp), int(size * 0.3), COL_TEXT)
