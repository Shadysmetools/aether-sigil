## Full-width overlay above the HUD for the board's 2D juice: the skill CUT-IN (a diagonal banner
## that slides in with the monster's portrait and skill name, ~0.7 s, tap to skip) and the soft
## screen flash. Time is fed by the board (advance(dt)), so hold-to-2x applies.
extends Control

const Palette = preload("res://scripts/theme_colors.gd")
const Art = preload("res://scripts/board_art.gd")

const DUR := 0.7

var tex: Texture2D
var mon_name := ""
var skill := ""
var col := Color.WHITE
var from_left := true
var t := DUR
var flash_a := 0.0
var flash_col := Color.WHITE
var shown := 0               ## cut-ins started (tests / report)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Starts a cut-in. side 0 slides from the left, 1 from the right.
func play(p_tex: Texture2D, p_name: String, p_skill: String, p_col: Color, side: int) -> void:
	tex = p_tex
	mon_name = p_name
	skill = p_skill
	col = p_col
	from_left = side == 0
	t = 0.0
	shown += 1
	queue_redraw()


func active() -> bool:
	return t < DUR


func skip() -> void:
	t = DUR
	queue_redraw()


func flash(c: Color, a: float) -> void:
	flash_col = c
	flash_a = maxf(flash_a, a)
	queue_redraw()


func advance(dt: float) -> void:
	var was := active() or flash_a > 0.0
	t = minf(DUR, t + dt)
	flash_a = maxf(0.0, flash_a - dt * 2.6)
	if was:
		queue_redraw()


func _draw() -> void:
	var vp := size
	if flash_a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(flash_col, flash_a))
	if not active():
		return
	# slide in 0.14 s, hold, slide out 0.14 s
	var k := 1.0
	if t < 0.14:
		k = 1.0 - pow(1.0 - t / 0.14, 3.0)
	elif t > DUR - 0.14:
		k = 1.0 - pow((t - (DUR - 0.14)) / 0.14, 2.0)
	var dir := 1.0 if from_left else -1.0
	var shift := (1.0 - k) * vp.x * 1.1 * -dir
	var cy := vp.y * 0.4
	var h := 250.0
	var slant := 90.0
	var a := clampf(k * 1.4, 0.0, 1.0)
	# dim the battle behind the banner
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.35 * a))
	var poly := PackedVector2Array([
		Vector2(-40 + shift, cy - h / 2 + slant), Vector2(vp.x + 40 + shift, cy - h / 2 - slant),
		Vector2(vp.x + 40 + shift, cy + h / 2 - slant), Vector2(-40 + shift, cy + h / 2 + slant)])
	draw_colored_polygon(poly, Color(Palette.MIDNIGHT_NAVY, 0.93))
	# element-coloured edge bands
	for e in [-1.0, 1.0]:
		var o: float = e * h / 2
		var band := PackedVector2Array([
			Vector2(-40 + shift, cy + o + slant - 7), Vector2(vp.x + 40 + shift, cy + o - slant - 7),
			Vector2(vp.x + 40 + shift, cy + o - slant + 7), Vector2(-40 + shift, cy + o + slant + 7)])
		draw_colored_polygon(band, col)
	# speed lines
	for i in 9:
		var y := cy - h / 2 + 30 + i * 24
		var x0 := fmod(t * 2600.0 * dir + i * 173.0, vp.x + 400) - 200 if from_left else vp.x - fmod(t * 2600.0 + i * 173.0, vp.x + 400) + 200
		draw_line(Vector2(x0 + shift, y + slant * 0.1), Vector2(x0 + shift + 160 * dir, y), Color(col, 0.35), 3.0)
	# portrait panel
	var pw := 300.0
	var px := (60.0 if from_left else vp.x - 60.0 - pw) + shift
	var prect := Rect2(px, cy - h / 2 + 6 + (slant * 0.35 if from_left else -slant * 0.35) - 10, pw, h - 12)
	if tex != null:
		var ts := Vector2(tex.get_size())
		var want := prect.size.x / prect.size.y
		var src := Rect2(Vector2.ZERO, ts)
		if ts.x / ts.y > want:
			src.size.x = ts.y * want
			src.position.x = (ts.x - src.size.x) / 2.0
		else:
			src.size.y = ts.x / want
			src.position.y = (ts.y - src.size.y) * 0.25
		draw_texture_rect_region(tex, prect, src, Color(1, 1, 1, a))
	draw_rect(prect, Color(Palette.SIGIL_GOLD, a), false, 4.0)
	# names
	var f := Art.font()
	var tx := (px + pw + 36.0) if from_left else (px - 36.0)
	var big := 64
	var small := 34
	var sw := f.get_string_size(skill, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	var nw := f.get_string_size(mon_name, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x
	var sx := tx if from_left else tx - sw
	var nx := tx if from_left else tx - nw
	sx = clampf(sx, 10.0, vp.x - sw - 10.0)
	nx = clampf(nx, 10.0, vp.x - nw - 10.0)
	draw_string_outline(f, Vector2(nx, cy - 34), mon_name, HORIZONTAL_ALIGNMENT_LEFT, -1, small, 8, Color(Palette.MIDNIGHT_NAVY, a))
	draw_string(f, Vector2(nx, cy - 34), mon_name, HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color(Palette.SOFT_SILVER, a))
	draw_string_outline(f, Vector2(sx, cy + 44), skill, HORIZONTAL_ALIGNMENT_LEFT, -1, big, 12, Color(Palette.MIDNIGHT_NAVY, a))
	draw_string(f, Vector2(sx, cy + 44), skill, HORIZONTAL_ALIGNMENT_LEFT, -1, big, Color(Palette.SIGIL_GOLD.lerp(col, 0.25), a))
