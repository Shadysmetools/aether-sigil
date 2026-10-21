## HD-2D battle board: the same surface as board_view.gd (state, highlights, selected, tile_center,
## top_center, tile_at_local, board_size) so ui.gd and the tests drive it the same way, but the board
## is a lit 3D floating-ruin island (board3d/board_build.gd) rendered into the main viewport behind the
## HUD, with the 2D sky (CanvasLayer -1) as the 3D background. Reads state only; never changes rules.
##
## Coordinates: the node sits at the canvas origin with scale 1, so "local" points are canvas pixels.
## tile_center(c) = the projected centre of tile c's top face; tile_at_local() casts a ray against
## the 144 tile top boxes (top-face hits first), so tile_at_local(tile_center(c)) == c for every tile,
## view rotation and zoom (tests/test_board3d.gd).
extends Node2D

const GameState = preload("res://scripts/game_state.gd")
const Build = preload("res://scripts/board3d/board_build.gd")
const Mats = preload("res://scripts/board3d/mats.gd")
const Actor = preload("res://scripts/board3d/unit_actor.gd")
const Palette = preload("res://scripts/theme_colors.gd")
const Assets = preload("res://scripts/assets.gd")
const Data = preload("res://scripts/data_loader.gd")
const Art = preload("res://scripts/board_art.gd")
const UIArt = preload("res://scripts/ui_art.gd")
const SkyBackdrop = preload("res://scripts/sky_backdrop.gd")
const AnimQ = preload("res://scripts/board3d/anim_queue.gd")
const FX = preload("res://scripts/board3d/fx.gd")
const CutIn = preload("res://scripts/board3d/cut_in.gd")
const Sfx = preload("res://scripts/sfx.gd")

const PITCH_DEG := 41.0      ## camera elevation
const FOV_DEG := 28.0        ## vertical field of view (narrow = HD-2D diorama look)
const FIT_MARGIN := 0.96
const ZOOM_MAX := 2.4
const PICK_TOP := 0.6        ## tallest pick box above the ground plane (obstacles 0.48)

var state: GameState
var highlights: Dictionary = {}   ## Vector2i -> Color
var selected: Variant = null      ## Vector2i or null
var use_textures := true          ## kept for API parity with board_view.gd
var view_step := 0                ## camera quarter-turns; 0 = player corner nearest (as the 2D board)
var zoom := 1.0
var pan := Vector2.ZERO           ## extra screen-pixel pan when zoomed in
var band := Rect2()               ## screen rect the board is framed into (fit_band)
var world: Node3D
var cam: Camera3D
var sun: DirectionalLight3D
var env_node: WorldEnvironment
var environment: Environment
var builder: Build
var island: Node3D
var actors: Dictionary = {}       ## unit id -> Actor
var buttons: Array[Button] = []
var _hl: MultiMeshInstance3D
var _fx: Node3D
var _grid_ref: Array = []
var _stage := ""
var _hl_key := ""
var _ev_idx := 0
var _snap: Dictionary = {}        ## unit id -> {pos, hp, dormant}
var _sym_hp: Array = [-1, -1]
var _popups: Array = []
var _fit_dist := 30.0
var _fit_shift := Vector2.ZERO    ## pixel shift that centres the board in the band at zoom 1
var _fit_center := Vector2.ZERO   ## projected board centre at zoom 1, before the shift
var _press: Variant = null
var _dragging := false
var _swiped := false
var _time := 0.0
var _re_hit := RegEx.create_from_string("^(.+) hits (.+) for (\\d+)$")
var _re_miss := RegEx.create_from_string("^(.+) misses$")
var _re_use := RegEx.create_from_string("^(.+) uses (.+)$")
var _re_sym := RegEx.create_from_string("^P(\\d) Symbol$")
var _re_ko := RegEx.create_from_string("^(.+) is knocked out$")
var _re_def := RegEx.create_from_string("^(.+) defends$")
var _re_reflect := RegEx.create_from_string("^(.+) reflects (\\d+)$")
var _re_recharge := RegEx.create_from_string("^(.+) recharges (\\d+) HP$")
var _re_takes := RegEx.create_from_string("^(.+) takes (\\d+) from (.+)$")
var _re_obj := RegEx.create_from_string("^P(\\d) (activates the capsule node|secures the relic) at \\((-?\\d+), (-?\\d+)\\)$")

## Presentation queue (anim_queue.gd): instant when headless, so animation never blocks the rules.
var anim: AnimQ
## Tests set this and drive anim_step(dt) themselves (deterministic, no double stepping).
var manual_step := false
var cut_in: CutIn
var juice := {"shakes": 0, "flashes": 0, "slowmo": 0, "hitstops": 0, "transforms": 0, "cutins": 0, "crumbles": 0, "summons": 0}
var gap := Rect2()                ## optional screen rect above the band the board may grow into
var _overlay: CanvasLayer
var _btracks: AnimQ.Tracks
var _dying: Array = []            ## actors whose unit left the rules, still crumbling
var _to_free: Array = []          ## gone actors waiting for the queue to drain
var _acted: Dictionary = {}       ## unit id -> true once it played its first (full) transform
var _summon_cost: Dictionary = {}
var _summon_shown: Dictionary = {}
var _moss := 0.0
var _real := 0.0
var _press_t := 0.0
var _hover: Variant = null
var _shake := 0.0
var _hitstop := 0.0
var _slowmo := 0.0
var _last_flash := -10.0
var _focus_amt := 0.0
var _focus_w := Vector3.ZERO
var _target_c := Vector2.ZERO     ## where the board centre sits on screen at zoom 1


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	world = Node3D.new()
	world.name = "Board3D"
	add_child(world)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_FRUSTUM
	cam.near = 1.0
	cam.far = 400.0
	cam.size = 2.0 * cam.near * tan(deg_to_rad(FOV_DEG) / 2.0)
	world.add_child(cam)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45.0
	sun.directional_shadow_fade_start = 1.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.light_energy = 1.1
	sun.light_color = Palette.SOFT_SILVER.lerp(Palette.SIGIL_GOLD, 0.28)
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-25.0), 0.0)
	world.add_child(sun)
	environment = Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.background_canvas_max_layer = -1
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Palette.SOFT_SILVER.lerp(Palette.AETHER_CYAN, 0.25)
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 0.95
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.0
	environment.adjustment_contrast = 1.08
	env_node = WorldEnvironment.new()
	world.add_child(env_node)
	_fx = Node3D.new()
	world.add_child(_fx)
	_hl = MultiMeshInstance3D.new()
	_hl.material_override = Mats.highlight()
	_hl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_hl)
	anim = AnimQ.new()
	anim.instant = DisplayServer.get_name() == "headless"
	_btracks = AnimQ.Tracks.new(self)
	_overlay = CanvasLayer.new()
	_overlay.layer = 20
	add_child(_overlay)
	cut_in = CutIn.new()
	_overlay.add_child(cut_in)
	_make_buttons()
	_apply_visibility()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and world != null:
		_apply_visibility()


func _apply_visibility() -> void:
	var v := is_visible_in_tree()
	world.visible = v
	if _overlay != null:
		_overlay.visible = v
	if not v and anim != null:
		anim.flush()
		cut_in.skip()
	env_node.environment = environment if v else null
	if v:
		cam.make_current()
		_refit()
	else:
		cam.clear_current(false)


# ---------------------------------------------------------------- geometry API (board_view parity)

## Top-face centre of tile c, world space.
func tile_world(c: Vector2i) -> Vector3:
	var t := state.tile_type(c) if state != null else "ground"
	return Build.cell_pos(c) + Vector3(0, Build.top_y(t), 0)


## Camera projection for the canvas rect. Both directions (world -> screen and screen -> ray) use
## this one matrix, so picking and drawing agree on every platform (headless included, where the
## engine's own unproject / project_ray use different viewport sizes).
func _proj() -> Projection:
	var vp := get_viewport_rect().size
	return Projection.create_frustum_aspect(cam.size, vp.x / maxf(vp.y, 1.0), cam.frustum_offset, cam.near, cam.far, false)


## World point -> canvas pixel.
func _screen(p: Vector3) -> Vector2:
	var vp := get_viewport_rect().size
	var v := cam.global_transform.affine_inverse() * p
	var c := _proj() * Vector4(v.x, v.y, v.z, 1.0)
	if absf(c.w) < 1e-6:
		return Vector2(-1e6, -1e6)
	return Vector2((c.x / c.w * 0.5 + 0.5) * vp.x, (-c.y / c.w * 0.5 + 0.5) * vp.y)


## Canvas pixel -> [ray origin, ray direction] in world space.
func screen_ray(sp: Vector2) -> Array:
	var vp := get_viewport_rect().size
	var ndc := Vector2(sp.x / vp.x * 2.0 - 1.0, 1.0 - sp.y / vp.y * 2.0)
	var v := _proj().inverse() * Vector4(ndc.x, ndc.y, -1.0, 1.0)
	var o := cam.global_position
	return [o, (cam.global_transform * (Vector3(v.x, v.y, v.z) / v.w) - o).normalized()]


func _canvas_to_local(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


## Projected centre of tile c's top face, in local (= canvas) coordinates.
func tile_center(c: Vector2i) -> Vector2:
	return _canvas_to_local(_screen(tile_world(c)))


## Where tokens stand (same point as tile_center on this board).
func top_center(c: Vector2i) -> Vector2:
	return tile_center(c)


## Tile under a local point (ray against the tile top boxes), or null if off-board.
func tile_at_local(p: Vector2) -> Variant:
	var r := screen_ray(get_global_transform_with_canvas() * p)
	return pick_ray(r[0], r[1])


## Ray pick against the tile boxes (tops at Build.pick_top): the nearest box entered through its TOP
## face wins; failing that, the nearest side hit.
func pick_ray(o: Vector3, d: Vector3) -> Variant:
	if state == null or state.grid.is_empty() or absf(d.y) < 1e-5:
		return null
	# Only tiles near where the ray crosses the board's height band can be hit.
	var t_hi := (PICK_TOP - o.y) / d.y
	var t_lo := (Build.BASE - o.y) / d.y
	var pa := o + d * minf(t_hi, t_lo)
	var pb := o + d * maxf(t_hi, t_lo)
	var x_min := floori(minf(pa.x, pb.x) + Build.HALF) - 1
	var x_max := ceili(maxf(pa.x, pb.x) + Build.HALF) + 1
	var z_min := floori(minf(pa.z, pb.z) + Build.HALF) - 1
	var z_max := ceili(maxf(pa.z, pb.z) + Build.HALF) + 1
	var best_top := INF
	var top_c: Variant = null
	var best_side := INF
	var side_c: Variant = null
	for y in range(maxi(z_min, 0), mini(z_max, GameState.SIZE - 1) + 1):
		for x in range(maxi(x_min, 0), mini(x_max, GameState.SIZE - 1) + 1):
			var c := Vector2i(x, y)
			var cx := x - Build.HALF
			var cz := y - Build.HALF
			var top := Build.pick_top(state.tile_type(c))
			var r := _slab_hit(o, d, Vector3(cx - 0.5, Build.BASE, cz - 0.5), Vector3(cx + 0.5, top, cz + 0.5))
			if r.x < 0.0:
				continue
			if r.y > 0.5:
				if r.x < best_top:
					best_top = r.x
					top_c = c
			elif r.x < best_side:
				best_side = r.x
				side_c = c
	return top_c if top_c != null else side_c


## Ray / AABB: Vector2(t_enter, entered_through_top ? 1 : 0); t_enter < 0 = miss.
static func _slab_hit(o: Vector3, d: Vector3, lo: Vector3, hi: Vector3) -> Vector2:
	var t0 := -INF
	var t1 := INF
	var axis := -1
	for i in 3:
		if absf(d[i]) < 1e-9:
			if o[i] < lo[i] or o[i] > hi[i]:
				return Vector2(-1, 0)
			continue
		var a := (lo[i] - o[i]) / d[i]
		var b := (hi[i] - o[i]) / d[i]
		if a > b:
			var s := a
			a = b
			b = s
		if a > t0:
			t0 = a
			axis = i
		t1 = minf(t1, b)
		if t0 > t1:
			return Vector2(-1, 0)
	if t1 < 0.0:
		return Vector2(-1, 0)
	return Vector2(maxf(t0, 0.0), 1.0 if axis == 1 and d.y < 0.0 else 0.0)


func board_size() -> Vector2:
	return band.size if band.size != Vector2.ZERO else Vector2(1000, 1000)


## Bible tower id of the current stage ("01"), or "".
func tower_id() -> String:
	if state == null or state.stage.is_empty():
		return ""
	return str(state.stage.get("tower_id", ""))


# ---------------------------------------------------------------- camera

## Horizontal + vertical direction from the board toward the camera.
func cam_dir() -> Vector3:
	var a := deg_to_rad(225.0 + 90.0 * view_step)
	var h := Vector3(cos(a), 0, sin(a))
	var p := deg_to_rad(PITCH_DEG)
	return (h * cos(p) + Vector3.UP * sin(p)).normalized()


func _place(dist: float, frust_size: float, shift_px: Vector2) -> void:
	var target := Vector3(0, 0.1, 0)
	cam.near = maxf(1.0, dist - 32.0)   # tight depth range = sharper directional shadows
	cam.far = dist + 220.0
	frust_size *= cam.near
	cam.global_transform = Transform3D(Basis(), target + cam_dir() * dist).looking_at(target, Vector3.UP)
	cam.size = frust_size
	var h := get_viewport_rect().size.y
	cam.frustum_offset = Vector2(-shift_px.x, shift_px.y) * frust_size / maxf(h, 1.0)


## Frustum height at a near plane of 1 (scaled by the real near in _place).
func _base_size() -> float:
	return 2.0 * tan(deg_to_rad(FOV_DEG) / 2.0)


## Screen bounds of the 12x12 tile area (ground and top heights).
func _proj_bounds() -> Rect2:
	var r := Rect2()
	var first := true
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			for y in [Build.BASE * 0.3, PICK_TOP]:
				var s := _screen(Vector3(sx * (Build.HALF + 0.5), y, sz * (Build.HALF + 0.5)))
				if first:
					r = Rect2(s, Vector2.ZERO)
					first = false
				else:
					r = r.expand(s)
	return r


## Frames the board into rect r (canvas pixels): called by ui.gd's layout pass.
## p_gap: optional rect above r (between the HUD side columns) the far corner may rise into.
func fit_band(r: Rect2, p_gap := Rect2()) -> void:
	band = r
	gap = p_gap if p_gap.size.x > 120.0 and p_gap.size.y > 30.0 and r.size.x > 200.0 and r.size.y > 200.0 else Rect2()
	position = Vector2.ZERO
	scale = Vector2.ONE
	_refit()
	_place_buttons()


func _refit() -> void:
	if cam == null or not cam.is_inside_tree():
		return
	if band.size == Vector2.ZERO:
		band = get_viewport_rect()
	var lo := 3.0
	var hi := 500.0
	var bs := _base_size()
	for i in 32:
		var mid := (lo + hi) * 0.5
		_place(mid, bs, Vector2.ZERO)
		if _fits():
			hi = mid
		else:
			lo = mid
	_fit_dist = hi
	sun.directional_shadow_max_distance = _fit_dist + 24.0
	_place(_fit_dist, bs, Vector2.ZERO)
	_fit_center = _proj_bounds().get_center()
	_target_c = band.get_center() if gap == Rect2() else _fit_center + _gap_shift()
	_apply_view()


## Outline points of the tile area (edges sampled, ground and top heights), current camera.
func _outline_pts() -> Array:
	var pts: Array = []
	var e := Build.HALF + 0.5
	var corners := [Vector2(-e, -e), Vector2(e, -e), Vector2(e, e), Vector2(-e, e)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		for k in 8:
			var q := a.lerp(b, k / 8.0)
			for y in [Build.BASE * 0.3, PICK_TOP]:
				pts.append(_screen(Vector3(q.x, y, q.y)))
	return pts


## Pixel shift placing the board bottom-aligned in the band, centred horizontally (gap framing).
func _gap_shift() -> Vector2:
	var b := _proj_bounds()
	var pad := band.size.y * (1.0 - FIT_MARGIN) * 0.5
	return Vector2(band.get_center().x - b.get_center().x, band.end.y - pad - b.end.y)


## Does the board fit at the current camera distance? Without a gap: inside the band (margin).
## With a gap: every outline point inside the band or the gap once bottom-aligned.
func _fits() -> bool:
	var b := _proj_bounds()
	if b.size.x > band.size.x * FIT_MARGIN:
		return false
	if gap == Rect2():
		return b.size.y <= band.size.y * FIT_MARGIN
	var sh := _gap_shift()
	var inner := band.grow(-band.size.y * (1.0 - FIT_MARGIN) * 0.5 + 1.0)
	var g := gap.grow(-6.0)
	for p in _outline_pts():
		var q: Vector2 = p + sh
		if not (inner.has_point(q) or (q.y >= g.position.y and q.y <= inner.end.y and q.x >= g.position.x and q.x <= g.end.x)):
			return false
	return true


## Applies zoom (narrower frustum, same camera position) and pan around the band-centred framing.
func _apply_view() -> void:
	var vp := get_viewport_rect().size
	var screen_c := vp * 0.5
	var z := zoom
	if _target_c == Vector2.ZERO:
		_target_c = band.get_center()
	var shift := _target_c - screen_c - z * (_fit_center - screen_c) + pan
	if anim != null and not anim.instant:
		if _breathing():
			z *= 1.0 + 0.006 * sin(_real * 0.45)
			shift = _target_c - screen_c - z * (_fit_center - screen_c) + pan + Vector2(sin(_real * 0.31) * 2.5, cos(_real * 0.27) * 2.0)
		if _focus_amt > 0.001:
			_place(_fit_dist, _base_size(), Vector2.ZERO)
			var q := _screen(_focus_w)
			var zf := z * (1.0 + 0.2 * _focus_amt)
			var normal := _target_c - screen_c - zf * (_fit_center - screen_c) + pan
			var focus := _target_c - screen_c - zf * (q - screen_c)
			shift = normal.lerp(focus, 0.45 * _focus_amt)
			z = zf
		if _shake > 0.0:
			shift += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
	_place(_fit_dist, _base_size() / z, shift)
	_update_rim()


func set_zoom(z: float) -> void:
	zoom = clampf(z, 1.0, ZOOM_MAX)
	if zoom <= 1.001:
		pan = Vector2.ZERO
	_apply_view()


## Turns the camera a quarter (dir = +1 / -1) around the board.
func rotate_view(dir: int) -> void:
	view_step = posmod(view_step + dir, 4)
	_refit()


func _update_rim() -> void:
	if builder == null:
		return
	var h := cam_dir()
	h.y = 0
	for s in 4:
		var n: MeshInstance3D = builder.rim_tall[s]
		if n != null and is_instance_valid(n):
			var d := Build.DIRS[s]
			n.visible = Vector3(d.x, 0, d.y).dot(h) < 0.0


# ---------------------------------------------------------------- input

## Taps, drags and wheel for the board. Returns the tapped tile (on release) or null. Drag pans when
## zoomed in; a long horizontal swipe at zoom 1 rotates the view.
func handle_input(event: InputEvent) -> Variant:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom(zoom * 1.12)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom(zoom / 1.12)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press = mb.position
				_press_t = _real
				_dragging = false
				_swiped = false
			else:
				var tap: bool = _press != null and not _dragging
				_press = null
				if tap and cut_in != null and cut_in.active():
					cut_in.skip()
					return null
				if tap:
					return tile_at_local(_canvas_to_local(mb.position))
	elif event is InputEventMouseMotion and _press == null:
		_hover = tile_at_local(_canvas_to_local((event as InputEventMouseMotion).position))
	elif event is InputEventMouseMotion and _press != null:
		var mm := event as InputEventMouseMotion
		var d: Vector2 = mm.position - _press
		if not _dragging and d.length() > 22.0:
			_dragging = true
		if _dragging:
			if zoom > 1.01:
				pan += mm.relative
				_apply_view()
			elif not _swiped and absf(d.x) > 170.0 and absf(d.x) > absf(d.y) * 2.0:
				rotate_view(-1 if d.x > 0 else 1)
				_swiped = true
	elif event is InputEventMagnifyGesture:
		set_zoom(zoom * (event as InputEventMagnifyGesture).factor)
	return null


func _make_buttons() -> void:
	for spec in [["rot_l", -1], ["rot_r", 1], ["zoom", 0]]:
		var b := Button.new()
		b.name = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(88, 88)
		b.size = Vector2(88, 88)
		for st in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(st, UIArt.chamfer(Palette.MIDNIGHT_NAVY.lerp(Palette.AETHER_CYAN, 0.12 if st != "pressed" else 0.3), Palette.SIGIL_GOLD.darkened(0.15), 2, 12))
		var dir: int = spec[1]
		if dir != 0:
			b.pressed.connect(rotate_view.bind(dir))
			b.tooltip_text = "Rotate view"
		else:
			b.pressed.connect(func(): set_zoom(1.0 if zoom > 1.5 else 1.8))
			b.tooltip_text = "Zoom"
		b.draw.connect(_draw_button_icon.bind(b, dir))
		add_child(b)
		buttons.append(b)


func _draw_button_icon(b: Button, dir: int) -> void:
	var c := b.size / 2.0
	var col := Palette.SIGIL_GOLD
	if dir == 0:
		b.draw_arc(c - Vector2(5, 5), 20, 0, TAU, 28, col, 4.0, true)
		b.draw_line(c + Vector2(9, 9), c + Vector2(26, 26), col, 6.0, true)
		var plus := zoom <= 1.5
		b.draw_line(c - Vector2(16, 5), c - Vector2(-6, 5), col, 3.0, true)
		if plus:
			b.draw_line(c - Vector2(5, 16), c - Vector2(5, -6), col, 3.0, true)
		return
	var r := 21.0
	var a0 := deg_to_rad(-70.0)
	var a1 := a0 + deg_to_rad(265.0) * dir
	b.draw_arc(c, r, a0, a1, 28, col, 4.5, true)
	var n := Vector2.from_angle(a1)
	var t := Vector2(-n.y, n.x) * dir
	var tip := c + n * r
	b.draw_colored_polygon(PackedVector2Array([tip + t * 13.0, tip + n * 9.0 - t * 3.0, tip - n * 9.0 - t * 3.0]), col)


func _place_buttons() -> void:
	if buttons.is_empty():
		return
	var y := band.end.y - 96.0
	buttons[0].position = Vector2(band.position.x + 6, y)
	buttons[1].position = Vector2(band.end.x - 94, y)
	buttons[2].position = Vector2(band.end.x - 94, y - 98)


# ---------------------------------------------------------------- frame loop

func _process(delta: float) -> void:
	if state == null or state.grid.is_empty() or not is_visible_in_tree():
		return
	_real += delta
	sync()
	if not manual_step:
		_anim_advance(delta * anim_speed(delta))
	builder.animate(_real)
	queue_redraw()


## Advances the presentation by dt seconds of (already scaled) animation time. Tests that switch
## manual_step on call this themselves for deterministic stepping.
func anim_step(dt: float) -> void:
	_anim_advance(dt)


func _anim_advance(dt: float) -> void:
	_time += dt
	anim.step(dt)
	_drain_frees()
	_btracks.step(dt)
	cut_in.advance(dt)
	var h := cam_dir()
	for a in actors.values():
		a.tick(dt, h)
	for a in _dying:
		if is_instance_valid(a):
			a.tick(dt, h)
	_dying = _dying.filter(func(a): return is_instance_valid(a) and not a.is_queued_for_deletion())
	for p in _popups:
		p.t += dt
	_popups = _popups.filter(func(p): return p.t < float(p.get("life", 1.1)))
	_shake = maxf(0.0, _shake - dt * 30.0)
	if not anim.instant and (_shake > 0.0 or _focus_amt > 0.0 or _breathing()):
		_apply_view()


## Presentation speed this frame: 0 during hit-stop, 0.35 in slow-mo, x2 while the player holds.
func anim_speed(delta: float) -> float:
	if _hitstop > 0.0:
		_hitstop -= delta
		return 0.0
	var s := 1.0
	if _slowmo > 0.0:
		_slowmo -= delta
		s = 0.35
	if held():
		s *= 2.0
	return s


## True while the player holds a press (pointer or Space / Enter) to fast-forward animations.
func held() -> bool:
	if _press != null and not _dragging and _real - _press_t > 0.3:
		return true
	return InputMap.has_action("ui_accept") and Input.is_action_pressed("ui_accept")


## Accessibility: aether_sigil/accessibility/reduced_motion disables shake, screen flash, slow-mo
## and camera breathing. Read live so the setting applies immediately.
static func reduced_motion() -> bool:
	return bool(ProjectSettings.get_setting("aether_sigil/accessibility/reduced_motion", false))


func _breathing() -> bool:
	return not reduced_motion()


## Animations still to play (syncs first, so a rules change made this frame counts).
func anim_busy() -> bool:
	if state != null and not state.grid.is_empty() and builder != null:
		sync()
	return anim.busy()


## Skips the beat playing now (tap while the rival acts) — or just the cut-in banner when one shows.
func skip_anim() -> void:
	if cut_in.active():
		cut_in.skip()
		return
	anim.skip()


func hit_stop(ms: float) -> void:
	if anim.instant:
		return
	_hitstop = maxf(_hitstop, ms / 1000.0)
	juice.hitstops += 1


func shake(px: float) -> void:
	if anim.instant or reduced_motion():
		return
	_shake = maxf(_shake, px)
	juice.shakes += 1


func slow_mo(sec: float) -> void:
	if anim.instant or reduced_motion():
		return
	_slowmo = maxf(_slowmo, sec)
	juice.slowmo += 1


## Soft full-screen flash, globally limited to one per 0.34 s (never faster than 3 Hz).
func screen_flash(col: Color, a: float) -> void:
	if anim.instant or reduced_motion():
		return
	if _real - _last_flash < 0.34:
		return
	_last_flash = _real
	cut_in.flash(col, a)
	juice.flashes += 1


func _focus_on(p: Vector3, amt: float, dur: float) -> void:
	if amt > 0.0:
		_focus_w = p
	_btracks.to("_focus_amt", amt, dur)


# ---------------------------------------------------------------- sync with GameState

## Brings the 3D scene in line with the GameState (rebuilds on a new stage). Safe to call any time.
func sync() -> void:
	if state == null or state.grid.is_empty():
		return
	if not is_same(state.grid, _grid_ref) or str(state.stage_id) != _stage:
		_rebuild()
	_sync_objectives()
	_sync_units(false)
	_sync_highlights()


func theme_name() -> String:
	for t in Data.towers():
		if str(t.tower_id) == tower_id():
			return str(t.get("theme", "Nature"))
	return "Nature"


func _rebuild() -> void:
	anim.flush()
	cut_in.skip()
	_grid_ref = state.grid
	_stage = str(state.stage_id)
	if island != null:
		island.free()
	for a in actors.values():
		a.free()
	for a in _dying + _to_free:
		if is_instance_valid(a):
			a.free()
	actors = {}
	_dying = []
	_to_free = []
	_snap = {}
	_popups = []
	_acted = {}
	_summon_cost = {}
	_summon_shown = {}
	_focus_amt = 0.0
	_shake = 0.0
	for c in _fx.get_children():
		c.free()
	var th := theme_name()
	var fam := str(Data.rules().get("tower_theme_family", {}).get(th, "Light"))
	var pal := SkyBackdrop.palette(fam)
	var haze: Color = Color(pal.low_color).lerp(pal.mid_color, 0.35)
	builder = Build.new()
	island = builder.build(state, th, haze)
	world.add_child(island)
	_moss = float(Palette.tower_theme(th).get("moss_amt", 0.0))
	if not anim.instant:
		island.add_child(_ambient(th, fam))
	environment.ambient_light_color = Color(pal.mid_color).lerp(Palette.SOFT_SILVER, 0.7)
	var dark := ["Dark", "Space", "Aether"].has(th)
	sun.light_energy = 0.9 if dark else 1.1
	sun.light_color = Palette.SOFT_SILVER.lerp(Palette.CRYSTAL_VIOLET if dark else Palette.SIGIL_GOLD, 0.28)
	_sym_hp = [state.symbol_hp[0], state.symbol_hp[1]]
	_ev_idx = state.events.size()
	_hl_key = "?"
	_sync_units(true)
	_refit()


## Drifting motes / leaves / embers / snow over the island, per tower element family.
func _ambient(theme: String, fam: String) -> CPUParticles3D:
	var cols := {"Fire": [Palette.EMBER, Palette.SIGIL_GOLD], "Ice": [Palette.SOFT_SILVER, Color.WHITE],
		"Wood": [Palette.VERDANT_GREEN, Palette.SIGIL_GOLD], "Water": [Palette.AETHER_CYAN, Palette.SOFT_SILVER],
		"Dark": [Palette.CRYSTAL_VIOLET, Palette.AETHER_CYAN], "Tech": [Palette.AETHER_CYAN, Palette.SOFT_SILVER]}
	var pair: Array = cols.get(fam, [Palette.SIGIL_GOLD, Palette.SOFT_SILVER])
	if theme == "Nature":
		pair = [Palette.VERDANT_GREEN.lerp(Palette.SIGIL_GOLD, 0.35), Palette.SIGIL_GOLD]
	var p := CPUParticles3D.new()
	p.name = "Ambient"
	var leafy := theme == "Nature" or fam == "Wood"
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.05) if leafy else Vector2(0.06, 0.06)
	p.mesh = q
	p.material_override = Mats.particle()
	p.amount = 46
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(Build.HALF + 1.0, 1.3, Build.HALF + 1.0)
	p.position = Vector3(0, 1.4, 0)
	p.direction = Vector3(1, 0, 0.4)
	p.spread = 40.0
	p.initial_velocity_min = 0.08
	p.initial_velocity_max = 0.25
	var snowy := fam == "Ice"
	p.gravity = Vector3(0.05, -0.12 if (snowy or leafy) else 0.04, 0.02)
	p.angular_velocity_min = -90.0 if leafy else 0.0
	p.angular_velocity_max = 90.0 if leafy else 0.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Color(pair[0], 0.0))
	g.set_color(1, Color(pair[1], 0.0))
	g.add_point(0.15, Color(pair[0], 0.75))
	g.add_point(0.85, Color(Color(pair[0]).lerp(pair[1], 0.6), 0.55))
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = true
	return p


func _stand(c: Vector2i) -> Vector3:
	return Build.cell_pos(c) + Vector3(0, Build.stand_y(state, c), 0)


func _sync_objectives() -> void:
	for c in builder.gems:
		var g: Dictionary = builder.gems[c]
		var owner: int = int((state.nodes if g.kind == "node" else state.relics).get(c, GameState.NONE))
		var col: Color
		if g.kind == "node":
			col = Palette.side(owner) if owner >= 0 else Palette.SOFT_SILVER.lerp(Palette.CRYSTAL_VIOLET, 0.35)
		else:
			col = Palette.SIGIL_GOLD if owner < 0 else Palette.SIGIL_GOLD.lerp(Palette.side(owner), 0.45)
		if g.get("col", Color.BLACK) != col:
			g["col"] = col
			g.gem.material_override = Mats.crystal(col)
			(g.halo.material_override as ShaderMaterial).set_shader_parameter("color", col)
		var occupied := state.unit_at(c) != null
		for s in builder.spinners:
			if s[0] == g.gem:
				s[3] = 1.32 if occupied else (0.62 if g.kind == "node" else 0.5)
		g.gem.scale = Vector3.ONE * (0.6 if occupied else 1.0)
		g.halo.position.y = g.gem.position.y
	for c in builder.portals:
		var p: Dictionary = builder.portals[c]
		var on: bool = c == state.active_portal
		(p.halo.material_override as ShaderMaterial).set_shader_parameter("intensity", 0.9 if on else 0.25)
		(p.ring.material_override as ShaderMaterial).set_shader_parameter("fade", 1.0 if on else 0.45)
	for side in 2:
		_sym_hp[side] = state.symbol_hp[side]
		if builder.sigils.has(side):
			builder.sigils[side].gem.visible = state.symbol_hp[side] > 0


func _new_actor(u) -> Actor:
	var a := Actor.new()
	a.setup(u)
	a.set_moss(_moss)
	world.add_child(a)
	a.snap_to(_stand(u.pos))
	actors[u.id] = a
	return a


func _sync_units(initial: bool) -> void:
	var fresh: Array = []         # [unit, actor] summoned since the last sync
	var moves: Array = []         # [actor, from, to]
	var waking: Array = []
	var seen := {}
	for u in state.units:
		seen[u.id] = true
		var a: Actor = actors.get(u.id)
		if a == null:
			a = _new_actor(u)
			_snap[u.id] = {"pos": u.pos, "hp": u.hp, "dormant": u.dormant}
			a.queued_hp = u.hp
			if not initial:
				a.visible = false
				fresh.append([u, a])
			continue
		var s: Dictionary = _snap[u.id]
		if s.pos != u.pos:
			moves.append([a, s.pos, u.pos])
		if s.dormant and not u.dormant:
			waking.append(a)
		a.spent = u.moved and u.attacked
		a.defending = u.defending
		a.max_hp = maxi(1, u.max_hp)
		_snap[u.id] = {"pos": u.pos, "hp": u.hp, "dormant": u.dormant}
	var gone := {}                # name -> [actors] removed from the rules this sync
	for id in actors.keys():
		if not seen.has(id):
			var a: Actor = actors[id]
			actors.erase(id)
			_snap.erase(id)
			a.dying = true
			_dying.append(a)
			if not gone.has(a.unit_name):
				gone[a.unit_name] = []
			gone[a.unit_name].append(a)
	if state.events.size() < _ev_idx:
		_ev_idx = 0
	var msgs: Array = []
	for i in range(_ev_idx, state.events.size()):
		msgs.append(str(state.events[i]))
	_ev_idx = state.events.size()
	if fresh.is_empty() and moves.is_empty() and waking.is_empty() and gone.is_empty() and msgs.is_empty():
		_settle_hp()
		return
	var acts := _parse_acts(msgs, gone)
	# targets moved by a hit (pull) move after the act, everything else first
	var hit_names := {}
	for act in acts:
		for h in act.get("hits", []):
			hit_names[str(h.get("target", ""))] = true
	for f in fresh:
		_beat_summon(f[0], f[1])
	var late: Array = []
	for m in moves:
		if hit_names.has(m[0].unit_name):
			late.append(m)
		else:
			_beat_move(m[0], m[1], m[2])
	for a in waking:
		_beat_awaken(a)
	for act in acts:
		_beat_act(act)
	for m in late:
		_beat_move(m[0], m[1], m[2])
	# removed without a knockout line (e.g. state reset): just go
	for n in gone:
		for a in gone[n]:
			if not a.get_meta("claimed", false):
				_free_actor(a)
	_settle_hp()


## Any HP change no event explained (heal skills, regen): a small number + the shown HP catches up.
func _settle_hp() -> void:
	for u in state.units:
		var a: Actor = actors.get(u.id)
		if a == null or a.queued_hp == u.hp:
			continue
		var d: int = u.hp - a.queued_hp
		a.queued_hp = u.hp
		var hp: int = u.hp
		var beat := {"name": "hp", "dur": 0.35, "cues": [[0.0, func():
			if is_instance_valid(a):
				_popup(a.head_world(), ("+%d" if d > 0 else "-%d") % absi(d), Palette.VERDANT_GREEN if d > 0 else Palette.EMBER, "heal" if d > 0 else "dmg")
				if d > 0:
					FX.shockwave(_fx, a.base, Palette.VERDANT_GREEN, 0.7, 0.5)
		]], "end": func():
			if is_instance_valid(a):
				if d > 0:
					a.heal_to(hp)
				else:
					a.hit(hp)
				a.settle()}
		anim.push(beat)


## Groups this sync's log lines into acts: {type: attack|skill|defend|tick|ko|objective, ...}.
func _parse_acts(msgs: Array, gone: Dictionary) -> Array:
	var acts: Array = []
	var cur: Variant = null
	for msg in msgs:
		var m := _re_use.search(msg)
		if m != null:
			cur = {"type": "skill", "actor": m.get_string(1), "skill": m.get_string(2), "hits": [], "ko": []}
			acts.append(cur)
			continue
		m = _re_hit.search(msg)
		if m != null:
			var who := m.get_string(1)
			if cur == null or cur.actor != who or (cur.type == "attack" and not cur.hits.is_empty()):
				cur = {"type": "attack", "actor": who, "hits": [], "ko": []}
				acts.append(cur)
			cur.hits.append({"target": m.get_string(2), "dmg": int(m.get_string(3))})
			continue
		m = _re_miss.search(msg)
		if m != null:
			var who := m.get_string(1)
			if cur == null or cur.actor != who or (cur.type == "attack" and not cur.hits.is_empty()):
				cur = {"type": "attack", "actor": who, "hits": [], "ko": []}
				acts.append(cur)
			cur.hits.append({"target": "", "miss": true})
			continue
		m = _re_reflect.search(msg)
		if m != null and cur != null:
			cur.hits.append({"reflect": m.get_string(1), "dmg": int(m.get_string(2)), "target": cur.actor})
			continue
		m = _re_ko.search(msg)
		if m != null:
			var n := m.get_string(1)
			if cur != null and cur.has("ko"):
				cur.ko.append(n)
			else:
				acts.append({"type": "ko", "name": n})
			continue
		m = _re_def.search(msg)
		if m != null:
			acts.append({"type": "defend", "actor": m.get_string(1)})
			cur = null
			continue
		m = _re_recharge.search(msg)
		if m != null:
			acts.append({"type": "tick", "name": m.get_string(1), "amount": int(m.get_string(2))})
			continue
		m = _re_takes.search(msg)
		if m != null:
			acts.append({"type": "tick", "name": m.get_string(1), "amount": -int(m.get_string(2))})
			continue
		m = _re_obj.search(msg)
		if m != null:
			acts.append({"type": "objective", "cell": Vector2i(int(m.get_string(3)), int(m.get_string(4))), "side": int(m.get_string(1))})
			continue
	# resolve names to actors now (KO'd units are already gone from the rules)
	for act in acts:
		act["gone"] = gone
	return acts


## Actor for a name: live ones first (optionally on a given side), then the ones removed this sync.
func _find(n: String, gone: Dictionary, side := -1) -> Actor:
	var any: Actor = null
	for a in actors.values():
		if a.unit_name == n:
			if side < 0 or a.side == side:
				return a
			any = a
	if gone.has(n):
		for a in gone[n]:
			if side < 0 or a.side == side:
				return a
		return gone[n][0]
	return any


## Frees a gone actor — at once when nothing is queued, else once the queue drains (queued beats
## hold references to their actors; none may be freed under them).
func _free_actor(a: Actor) -> void:
	if not is_instance_valid(a):
		return
	a.visible = false
	if anim.busy():
		if not _to_free.has(a):
			_to_free.append(a)
		return
	_dying.erase(a)
	a.queue_free()


func _drain_frees() -> void:
	if anim.busy() or _to_free.is_empty():
		return
	for a in _to_free:
		if is_instance_valid(a):
			_dying.erase(a)
			a.queue_free()
	_to_free.clear()


## Kept for API parity: older callers asked the actor by name.
func _actor_named(n: String) -> Actor:
	return _find(n, {})


# ---------------------------------------------------------------- beats

## Rules agent hook: a monster was summoned from its Vessel for sp_cost Summon Points. The board
## plays the Vessel-crack + statue placement once per unit (the sync that sees the new unit plays
## it too; whichever comes first shows the cost if known).
func play_summon(unit, sp_cost := -1) -> void:
	if unit == null:
		return
	_summon_cost[unit.id] = sp_cost
	if _summon_shown.has(unit.id) and sp_cost > 0:
		var a: Actor = actors.get(unit.id)
		if a != null:
			_popup(a.head_world() + Vector3(0, 0.3, 0), "-%d SP" % sp_cost, Palette.CRYSTAL_VIOLET.lerp(Color.WHITE, 0.3), "sp")
		return
	if builder != null:
		sync()


## Rules agent hook: a Vessel (capsule crystal holding an undeployed monster) was shattered by an
## enemy attack — the crystal explodes and the monster inside is lost. `vessel` may be a dict or an
## object; its tile comes from pos / tile / cell, its colour from owner / side and family.
func play_vessel_break(vessel) -> void:
	if builder == null or vessel == null:
		return
	var cell: Variant = _field(vessel, ["pos", "tile", "cell"])
	if not (cell is Vector2i):
		return
	var owner := int(_field(vessel, ["owner", "side"], 0))
	var fam := str(_field(vessel, ["family", "element_family"], ""))
	var col := Palette.family(fam) if fam != "" else Palette.side(owner)
	var p := _stand(cell)
	var name := str(_field(vessel, ["name", "mon_name"], ""))
	var holder := [null]
	var cues := [
		[0.0, func():
			holder[0] = FX.capsule(_fx, p + Vector3(0, 0.35, 0), col)
			Sfx.play("stone_crack_build", p)],
		[0.18, func():
			if holder[0] != null and is_instance_valid(holder[0]):
				var v: MeshInstance3D = holder[0]
				v.material_override = Mats.crystal(col.lerp(Color.WHITE, 0.4), 3.0)
				var tw := v.create_tween()
				tw.tween_property(v, "scale", Vector3(1.25, 0.85, 1.25), 0.1)],
		[0.3, func():
			if holder[0] != null and is_instance_valid(holder[0]):
				holder[0].queue_free()
			burst(p + Vector3(0, 0.4, 0), col, 22)
			FX.shockwave(_fx, p, col, 1.2, 0.4)
			screen_flash(col, 0.15)
			shake(5.0)
			Sfx.play("petrify_shatter", p)
			_popup(p + Vector3(0, 0.9, 0), ("%s lost" % name) if name != "" else "Vessel lost", Palette.EMBER, "tag")],
	]
	anim.push({"name": "vessel_break", "dur": 0.9, "cues": cues, "end": func():
		if holder[0] != null and is_instance_valid(holder[0]):
			holder[0].queue_free()})


static func _field(o, keys: Array, default: Variant = null) -> Variant:
	for k in keys:
		if o is Dictionary and o.has(k):
			return o[k]
		if o is Object and k in o:
			return o.get(k)
	return default


## Summon: a sealed faceted Vessel crystal rises onto the tile, spins, cracks with light seams and
## bursts; a light beam stands up and the monster's STATUE assembles from the light on its plinth.
func _beat_summon(u, a: Actor) -> void:
	_summon_shown[u.id] = true
	var p: Vector3 = a.base
	var col := Palette.side(a.side).lerp(Palette.family(a.family), 0.35)
	var holder := [null]
	var uid: int = u.id
	var cues := [
		[0.0, func():
			var v := FX.capsule(_fx, p + Vector3(0, -0.6, 0), col)
			holder[0] = v
			var tw := v.create_tween().set_parallel(true)
			tw.tween_property(v, "position:y", p.y + 0.45, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tw.tween_property(v, "rotation:y", TAU * 1.5, 0.9).set_ease(Tween.EASE_IN_OUT)
			var cost := int(_summon_cost.get(uid, -1))
			if cost > 0:
				_popup(p + Vector3(0, 1.3, 0), "-%d SP" % cost, Palette.CRYSTAL_VIOLET.lerp(Color.WHITE, 0.3), "sp")
			Sfx.play("capsule_node", p)],
		[0.5, func():
			if holder[0] != null and is_instance_valid(holder[0]):
				holder[0].material_override = Mats.crystal(col.lerp(Color.WHITE, 0.45), 3.2)
				FX.flash(_fx, p + Vector3(0, 0.5, 0), col, 1.0, 0.8)
				Sfx.play("stone_crack_build", p)],
		[0.8, func():
			if holder[0] != null and is_instance_valid(holder[0]):
				holder[0].queue_free()
			FX.beam_up(_fx, p, col)
			burst(p + Vector3(0, 0.5, 0), col, 18)
			FX.shockwave(_fx, p, col, 1.1, 0.4)
			screen_flash(col.lerp(Color.WHITE, 0.5), 0.12)
			Sfx.play("summon_burst", p)
			juice.summons += 1
			if is_instance_valid(a):
				a.materialise(0.5)],
	]
	anim.push({"name": "summon", "dur": 1.45, "cues": cues, "end": func():
		if holder[0] != null and is_instance_valid(holder[0]):
			holder[0].queue_free()
		if is_instance_valid(a):
			a.settle()})


## Statue hop / slide tile to tile, a dust puff and a stone clunk on every landing.
func _beat_move(a: Actor, from: Vector2i, to: Vector2i) -> void:
	var path := tile_path(from, to)
	var dest := _stand(to)
	if path.size() < 2:
		var src := _stand(from)
		anim.push({"name": "warp", "dur": 0.45, "cues": [[0.0, func():
			if is_instance_valid(a):
				burst(src + Vector3(0, 0.3, 0), Palette.CRYSTAL_VIOLET, 8)
				a.warp_to(dest)
				burst(dest + Vector3(0, 0.3, 0), Palette.CRYSTAL_VIOLET, 10)]],
			"end": func():
				if is_instance_valid(a):
					a.snap_to(dest)
					a.settle()})
		return
	var pts: Array = []
	for c in path:
		pts.append(_stand(c))
	var step := 0.17
	var cues: Array = [[0.0, func():
		if is_instance_valid(a):
			a.move_path(pts, step)]]
	for i in range(1, pts.size()):
		var land: Vector3 = pts[i]
		cues.append([step * i, func():
			FX.dust(_fx, land)
			Sfx.play("statue_hop", land)])
	anim.push({"name": "move", "dur": step * (pts.size() - 1) + 0.06, "cues": cues, "end": func():
		if is_instance_valid(a):
			a.snap_to(dest)
			a.settle()})


## A dormant guardian awakens: the dramatic transform — cold stone shudders, cracks race up, it
## bursts apart, the guardian roars, then turns to living (veined) rival stone.
func _beat_awaken(a: Actor) -> void:
	var cues := [
		[0.0, func():
			if is_instance_valid(a):
				_focus_on(a.chest_world(), 1.0, 0.5)
				a.crack_up(1.0)
				Sfx.play("stone_crack_build", a.base)],
		[1.0, func():
			if is_instance_valid(a):
				a.shatter()
				FX.debris(_fx, a.chest_world(), Palette.family(a.family), 34, 1.4)
				FX.flash(_fx, a.chest_world(), Palette.family(a.family), 3.0, 1.8)
				FX.shockwave(_fx, a.base, Palette.family(a.family), 2.4, 0.6)
				screen_flash(Palette.family(a.family).lerp(Color.WHITE, 0.5), 0.3)
				shake(12.0)
				Sfx.play("petrify_shatter", a.base)
				Sfx.play(Sfx.roar_for(a.plan), a.base)
				a.tracks.seq("pop", [[0.1, 1.25, "out"], [0.6, 1.08], [0.2, 1.0]])
				juice.transforms += 1],
		[1.95, func():
			if is_instance_valid(a):
				a.repetrify(0.7)
				Sfx.play("repetrify", a.base)
				_focus_on(Vector3.ZERO, 0.0, 0.6)],
	]
	anim.push({"name": "awaken", "dur": 2.75, "cues": cues, "end": func():
		_focus_amt = 0.0 if not anim.busy() else _focus_amt
		if is_instance_valid(a):
			a.dormant = false
			a.settle()})


func _beat_act(act: Dictionary) -> void:
	match str(act.type):
		"attack", "skill": _beat_attack(act)
		"defend":
			var a := _find(str(act.actor), act.gone)
			if a == null:
				return
			anim.push({"name": "defend", "dur": 0.55, "cues": [[0.0, func():
				if is_instance_valid(a):
					a.shield_flare()
					FX.shockwave(_fx, a.base, Palette.side(a.side).lerp(Palette.SIGIL_GOLD, 0.4), 0.8, 0.5)
					Sfx.play("defend_shield", a.base)]],
				"end": func():
					if is_instance_valid(a):
						a.settle()})
		"tick":
			var a := _find(str(act.name), act.gone)
			if a == null:
				return
			var amt := int(act.amount)
			a.queued_hp += amt
			var hp: int = a.queued_hp
			anim.push({"name": "tick", "dur": 0.4, "cues": [[0.0, func():
				if is_instance_valid(a):
					_popup(a.head_world(), ("+%d" if amt > 0 else "-%d") % absi(amt), Palette.VERDANT_GREEN if amt > 0 else Palette.EMBER, "heal" if amt > 0 else "dmg")
					if amt < 0:
						a.hit(hp)
						FX.chips(_fx, a.chest_world(), 5)
					else:
						a.heal_to(hp)]],
				"end": func():
					if is_instance_valid(a):
						a.shown_hp = hp
						a.settle()})
		"ko":
			var a := _find(str(act.name), act.gone)
			if a == null:
				return
			a.set_meta("claimed", true)
			anim.push({"name": "ko", "dur": 1.0, "cues": [[0.0, func(): _crumble(a)]], "end": func(): _free_actor(a)})
		"objective":
			var c: Vector2i = act.cell
			if not GameState.in_bounds(c):
				return
			var p := _stand(c)
			var col := Palette.side(int(act.side))
			anim.push({"name": "objective", "dur": 0.35, "cues": [[0.0, func():
				burst(p + Vector3(0, 0.6, 0), col, 10)
				Sfx.play("capsule_node", p)]], "end": func(): pass})


## The KO: statue crumbles into a rubble pile that sinks away; slow-mo + shake.
func _crumble(a: Actor) -> void:
	if not is_instance_valid(a):
		return
	a.crumble(0.4)
	var col := Palette.family(a.family)
	FX.debris(_fx, a.chest_world(), col, 30, 1.1)
	FX.rubble_pile(_fx, a.base, col, a.seed)
	FX.shockwave(_fx, a.base, Palette.SOFT_SILVER, 1.3, 0.5)
	slow_mo(0.6)
	shake(9.0)
	Sfx.play("statue_crumble", a.base)
	juice.crumbles += 1


## Attack / skill: the statue TRANSFORMS. Full cinematic (cut-in for skills, cracks race up, camera
## eases in) on skills and on each monster's first act of the battle; otherwise the quick version
## (whole transform + attack <= 1.2 s). Phases: crack -> shatter (debris, flash, shockwave) -> live
## roar -> archetype move-set + element delivery -> impacts -> re-petrify from the feet up.
func _beat_attack(act: Dictionary) -> void:
	var gone: Dictionary = act.gone
	var a := _find(str(act.actor), gone)
	var hits: Array = act.get("hits", [])
	var kos: Array = act.get("ko", [])
	if a == null:
		return
	var skill := str(act.type) == "skill"
	var full := skill or not _acted.has(a.uid)
	_acted[a.uid] = true
	# resolve targets now; hp after each hit from the queued (not yet shown) HP
	var infos: Array = []
	for h in hits:
		var info := {"dmg": int(h.get("dmg", 0)), "miss": h.get("miss", false), "actor": null, "pos": Vector3.ZERO, "reflect": h.has("reflect")}
		var tn := str(h.get("target", ""))
		if info.reflect:
			info.actor = a
		elif info.miss:
			info.actor = _nearest_foe(a)
		else:
			var sm := _re_sym.search(tn)
			if sm != null:
				var sp: Vector2i = state.symbol_pos[int(sm.get_string(1))]
				info.pos = Build.cell_pos(sp) + Vector3(0, Build.stand_y(state, sp) + 0.9, 0)
				info["sigil"] = true
			else:
				info.actor = _find(tn, gone, 1 - a.side)
		var t: Actor = info.actor
		if t != null and not info.miss:
			t.queued_hp -= info.dmg
			info["hp"] = t.queued_hp
			info["effective"] = not info.reflect and GameState.beats(a.family, t.family)
			if kos.has(t.unit_name) and t.dying:
				info["ko"] = true
				t.set_meta("claimed", true)
		infos.append(info)
	var crack_d := 0.55 if full else 0.16
	var t_sh := maxf(crack_d, 0.72) if skill else crack_d
	var speed := 1.0 if full else 1.25
	var timing := a.move_timing(speed)
	var t_atk := t_sh + (0.34 if full else 0.1)
	var rel: Array = timing.release if not timing.release.is_empty() else [0.2]
	var fam := a.family
	var var_k := absi(hash(str(act.get("skill", "")))) % 3 if skill else 0
	var delivery := str(FX.DELIVERY.get(fam, "runes"))
	var travel: float = FX.TRAVEL.get(delivery, 0.15) if (skill or a.moveset() == "spincast") else 0.06
	var t_rel: float = t_atk + float(rel[0])
	var cues: Array = []
	var first: Actor = null
	var aim := Vector3.ZERO
	for info in infos:
		if info.actor != null and info.actor != a:
			first = info.actor
			break
		if info.get("sigil", false):
			aim = info.pos
			break
	cues.append([0.0, func():
		if not is_instance_valid(a):
			return
		if full:
			_focus_on(a.chest_world(), 0.7 if skill else 0.45, 0.35)
		if skill:
			cut_in.play(_portrait(a), a.unit_name, str(act.skill), Palette.family(a.family), a.side)
			juice.cutins += 1
			Sfx.play("cast_" + fam.to_lower(), a.base)
		a.crack_up(crack_d)
		Sfx.play("stone_crack_build", a.base)])
	cues.append([t_sh, func():
		if not is_instance_valid(a):
			return
		a.shatter()
		var c := Palette.family(a.family)
		FX.debris(_fx, a.chest_world(), c, 22 if full else 14, 1.0 if full else 0.8)
		FX.flash(_fx, a.chest_world(), c, 2.2 if full else 1.4, 1.5)
		FX.shockwave(_fx, a.base, c, 1.5 if full else 1.0, 0.45)
		if full:
			screen_flash(c.lerp(Color.WHITE, 0.5), 0.16)
			shake(4.0)
		Sfx.play("petrify_shatter", a.base)
		Sfx.play(Sfx.roar_for(a.plan), a.base)
		juice.transforms += 1])
	cues.append([t_atk, func():
		if not is_instance_valid(a):
			return
		var tp := aim
		if first != null and is_instance_valid(first):
			tp = first.base
		elif tp == Vector3.ZERO:
			tp = a.base + a.facing
		a.attack_move(tp, a.moveset() == "spincast" or travel > 0.1, speed)])
	var t_imp := t_rel + travel
	var t_last := t_atk + float(timing.dur) * 0.85
	var n_tgt := 0
	for i in infos.size():
		var info: Dictionary = infos[i]
		var ti := t_imp + n_tgt * (0.2 if full else 0.12)
		if not info.reflect:
			n_tgt += 1
			cues.append([t_rel + (ti - t_imp), func():
				if not is_instance_valid(a):
					return
				var to: Vector3
				var gy := -999.0
				if info.actor != null and is_instance_valid(info.actor):
					to = info.actor.chest_world()
					gy = info.actor.base.y
				elif info.get("sigil", false):
					to = info.pos
				else:
					to = a.chest_world() + a.facing * 1.2
					gy = a.base.y
				FX.deliver(_fx, fam, a.chest_world(), to, var_k, a.seed + i, gy)])
		else:
			ti = t_imp + 0.12
		# extra visual strikes for multi-hit move-sets (ram) land on the first target
		if i == 0 and rel.size() > 1 and info.actor != null:
			for j in range(1, rel.size()):
				var tj: float = t_atk + float(rel[j]) + travel
				cues.append([tj, func():
					if info.actor != null and is_instance_valid(info.actor):
						info.actor.flash_v = 0.5
						FX.chips(_fx, info.actor.chest_world(), 4)
						Sfx.play("stone_chip_hit", info.actor.base)])
				ti = maxf(ti, tj + 0.02)
		cues.append([ti, func(): _impact(a, info, skill)])
		t_last = maxf(t_last, ti)
	var t_back := t_last + (0.35 if full else 0.08)
	var pet := 0.6 if full else 0.28
	cues.append([t_back, func():
		if is_instance_valid(a):
			a.repetrify(pet)
			Sfx.play("repetrify", a.base)
		if full:
			_focus_on(Vector3.ZERO, 0.0, 0.5)])
	var dur := t_back + pet + (0.1 if full else 0.0)
	anim.push({"name": "transform_full" if full else "transform", "dur": dur, "cues": cues, "end": func():
		cut_in.skip()
		if is_instance_valid(a) and not a.dying:
			a.settle()
		for info in infos:
			var t: Actor = info.actor
			if t == null or not is_instance_valid(t):
				continue
			if info.has("hp"):
				t.shown_hp = int(info.hp)
			if info.get("ko", false):
				_free_actor(t)
			elif t != a:
				t.settle()
		if is_instance_valid(a) and a.dying:
			_free_actor(a)
		if not anim.busy():
			_btracks.cancel("_focus_amt")
			_focus_amt = 0.0})


func _nearest_foe(a: Actor) -> Actor:
	var best: Actor = null
	var bd := INF
	for b in actors.values():
		if b.side != a.side and not b.dying:
			var d: float = b.base.distance_to(a.base)
			if d < bd:
				bd = d
				best = b
	return best


func _impact(a: Actor, info: Dictionary, skill: bool) -> void:
	var t: Actor = info.actor
	if info.miss:
		var p: Vector3 = t.head_world() if t != null and is_instance_valid(t) else (a.chest_world() + a.facing if is_instance_valid(a) else Vector3.ZERO)
		_popup(p, "MISS", Palette.SOFT_SILVER, "miss")
		if t != null and is_instance_valid(t):
			t.tracks.seq("off", [[0.08, -a.facing * 0.12, "out"], [0.18, Vector3.ZERO]])
		Sfx.play("miss_whoosh", p)
		return
	var dmg := int(info.dmg)
	if info.get("sigil", false):
		_popup(info.pos + Vector3(0, 0.5, 0), "-%d" % dmg, Palette.EMBER, "big" if skill else "dmg")
		burst(info.pos, Palette.family(a.family), 10)
		hit_stop(55.0)
		shake(5.0)
		Sfx.play("sigil_damage", info.pos)
		return
	if t == null or not is_instance_valid(t):
		return
	var frac := clampf(float(dmg) / float(maxi(1, t.max_hp)), 0.0, 1.0)
	t.hit(int(info.get("hp", t.shown_hp - dmg)))
	var big: bool = skill and not info.reflect
	_popup(t.head_world(), "-%d" % dmg, Palette.SIGIL_GOLD if big else Palette.EMBER, "big" if big else "dmg")
	if info.get("effective", false):
		_popup(t.head_world() + Vector3(0, 0.45, 0), "EFFECTIVE!", Palette.AETHER_CYAN.lerp(Palette.SIGIL_GOLD, 0.4), "tag")
	FX.impact(_fx, t.chest_world(), a.family, big)
	if t.is_statue():
		FX.chips(_fx, t.chest_world(), 6 + int(frac * 10.0))
		Sfx.play("stone_chip_hit", t.base)
	hit_stop(40.0 + 50.0 * clampf(frac * 2.5, 0.0, 1.0))
	shake(3.0 + 12.0 * frac)
	Sfx.play("hit_heavy" if (big or info.get("effective", false)) else "hit_melee", t.base)
	if info.get("ko", false):
		_crumble(t)


## Portrait for the cut-in: the monster's art (cut-out or concept crop), else its element icon.
func _portrait(a: Actor) -> Texture2D:
	var tex: Texture2D = Assets.monster(a.mon_id, a.family)
	return tex if tex != null else Assets.element_icon(a.family)


## Shortest 4-neighbour path over walkable tiles (visual only; [] when none, e.g. a warp).
func tile_path(from: Vector2i, to: Vector2i) -> Array:
	if from == to:
		return [from]
	var prev := {from: from}
	var q: Array[Vector2i] = [from]
	var i := 0
	while i < q.size() and i < 400:
		var c := q[i]
		i += 1
		for d in Build.DIRS:
			var n := c + d
			if prev.has(n) or not GameState.in_bounds(n):
				continue
			if n != to and not state.is_walkable(n):
				continue
			prev[n] = c
			if n == to:
				var path := [to]
				var k := to
				while k != from:
					k = prev[k]
					path.push_front(k)
				return path if path.size() <= 12 else []
			q.append(n)
	return []


func _sync_highlights() -> void:
	var key := str(highlights) + str(selected)
	if key == _hl_key:
		return
	_hl_key = key
	var items: Array = []
	for c in highlights:
		items.append([c, highlights[c]])
	if selected != null:
		items.append([selected, Palette.SIGIL_GOLD])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(0.94, 0.94)
	q.orientation = PlaneMesh.FACE_Y
	mm.mesh = q
	mm.instance_count = items.size()
	for i in items.size():
		var c: Vector2i = items[i][0]
		mm.set_instance_transform(i, Transform3D(Basis(), Build.cell_pos(c) + Vector3(0, Build.stand_y(state, c) + 0.018, 0)))
		mm.set_instance_color(i, items[i][1])
	_hl.multimesh = mm


# ---------------------------------------------------------------- effects

## Crystal-shard burst + flash (summons, knockouts, skills, warps).
func burst(pos: Vector3, col: Color, n: int = 14) -> void:
	if _fx == null:
		return
	var p := CPUParticles3D.new()
	p.mesh = Build.crystal_mesh(0.035, 0.08, 0.05, 4)
	p.material_override = Mats.shard()
	p.amount = n
	p.lifetime = 0.8
	p.one_shot = true
	p.explosiveness = 0.92
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12
	p.direction = Vector3.UP
	p.spread = 65.0
	p.initial_velocity_min = 1.4
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -5.0, 0)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	p.color = col.lerp(Color.WHITE, 0.2)
	p.position = pos
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.add_child(p)
	p.emitting = true
	FX.flash(_fx, pos, col, 1.9, 1.4)
	get_tree().create_timer(1.3).timeout.connect(p.queue_free)


## Floating number / tag. kind: dmg | big (skill hit: big gold + burst) | heal | miss | tag | sp.
func _popup(world_pos: Vector3, text: String, col: Color, kind := "dmg") -> void:
	_popups.append({"pos": world_pos, "text": text, "col": col, "t": 0.0, "kind": kind, "life": 1.5 if kind == "big" else 1.15})


# ---------------------------------------------------------------- 2D overlay (HP bars, badges, popups)

func _draw() -> void:
	if state == null or state.grid.is_empty() or cam == null or not cam.is_inside_tree():
		return
	var inv := get_global_transform_with_canvas().affine_inverse()
	var w := 46.0 * clampf(zoom, 1.0, 1.6)
	var f := Art.font()
	for id in actors:
		var a: Actor = actors[id]
		if a.dying or not a.visible or cam.is_position_behind(a.head_world()):
			continue
		var sp: Vector2 = inv * _screen(a.head_world())
		Art.hp_bar(self, sp, w, a.shown_hp, a.max_hp, Palette.side(a.side))
		var icon: Texture2D = Assets.element_icon(a.family)
		var ic := sp + Vector2(w / 2.0 + 14.0, 0.0)
		draw_circle(ic, 12.0, Palette.MIDNIGHT_NAVY)
		draw_arc(ic, 12.0, 0, TAU, 20, Palette.side(a.side), 2.0, true)
		if icon != null:
			draw_texture_rect(icon, Rect2(ic - Vector2(9, 9), Vector2(18, 18)), false)
		else:
			draw_circle(ic, 7.0, Palette.family(a.family))
		# name plate when selected or hovered
		var cell: Variant = _cell_of(a)
		if cell != null and (cell == selected or cell == _hover):
			var fs := 26
			var tw := f.get_string_size(a.unit_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var r := Rect2(sp + Vector2(-tw / 2.0 - 12.0, -50.0), Vector2(tw + 24.0, 34.0))
			draw_rect(r, Color(Palette.MIDNIGHT_NAVY, 0.88))
			draw_rect(r, Palette.side(a.side), false, 2.0)
			draw_string(f, r.position + Vector2(12, 25), a.unit_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.SOFT_SILVER)
	for side in 2:
		if builder != null and builder.sigils.has(side) and state.symbol_hp[side] > 0:
			var sp: Vector2 = inv * _screen(builder.sigils[side].node.global_position + Vector3(0, 1.75, 0))
			Art.hp_bar(self, sp, w * 1.4, state.symbol_hp[side], state.symbol_max, Palette.side(side))
	for p in _popups:
		_draw_popup(inv, f, p)


func _cell_of(a: Actor) -> Variant:
	var u := state.get_unit(a.uid)
	return u.pos if u != null else null


func _draw_popup(inv: Transform2D, f: Font, p: Dictionary) -> void:
	var t: float = p.t
	var kind: String = p.get("kind", "dmg")
	var life: float = p.get("life", 1.1)
	var rise := 70.0 if kind != "tag" else 40.0
	var sp: Vector2 = inv * _screen(p.pos) - Vector2(0, rise * minf(t, 1.0))
	var a := clampf((life - t) / 0.35, 0.0, 1.0)
	var fs := {"big": 66, "heal": 44, "miss": 36, "tag": 30, "sp": 38}.get(kind, 42) as int
	var pop := 1.0 + (0.7 if kind == "big" else 0.35) * maxf(0.0, 1.0 - t / 0.14)
	fs = int(fs * pop)
	if kind == "big" and t < 0.45:
		var r := 20.0 + 140.0 * t
		draw_arc(sp - Vector2(0, fs * 0.3), r, 0, TAU, 32, Color(Palette.SIGIL_GOLD, 0.7 * (1.0 - t / 0.45)), 5.0, true)
		for i in 8:
			var d := Vector2.from_angle(TAU * i / 8.0 + 0.2)
			draw_line(sp - Vector2(0, fs * 0.3) + d * r * 0.6, sp - Vector2(0, fs * 0.3) + d * r, Color(Palette.SIGIL_GOLD, 0.8 * (1.0 - t / 0.45)), 4.0)
	var tw := f.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(f, sp - Vector2(tw / 2, 0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10 if kind == "big" else 8, Color(Palette.MIDNIGHT_NAVY, a))
	draw_string(f, sp - Vector2(tw / 2, 0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(p.col, a))
