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
	_make_buttons()
	_apply_visibility()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and world != null:
		_apply_visibility()


func _apply_visibility() -> void:
	var v := is_visible_in_tree()
	world.visible = v
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
func fit_band(r: Rect2) -> void:
	band = r
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
		var b := _proj_bounds()
		if b.size.x <= band.size.x * FIT_MARGIN and b.size.y <= band.size.y * FIT_MARGIN:
			hi = mid
		else:
			lo = mid
	_fit_dist = hi
	sun.directional_shadow_max_distance = _fit_dist + 24.0
	_place(_fit_dist, bs, Vector2.ZERO)
	_fit_center = _proj_bounds().get_center()
	_apply_view()


## Applies zoom (narrower frustum, same camera position) and pan around the band-centred framing.
func _apply_view() -> void:
	var vp := get_viewport_rect().size
	var screen_c := vp * 0.5
	var z := zoom
	var shift := band.get_center() - screen_c - z * (_fit_center - screen_c) + pan
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
				_dragging = false
				_swiped = false
			else:
				var tap: bool = _press != null and not _dragging
				_press = null
				if tap:
					return tile_at_local(_canvas_to_local(mb.position))
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


# ---------------------------------------------------------------- sync with GameState

func _process(delta: float) -> void:
	if state == null or state.grid.is_empty() or not is_visible_in_tree():
		return
	_time += delta
	sync()
	builder.animate(_time)
	var h := cam_dir()
	for a in actors.values():
		a.tick(delta, h)
	for p in _popups:
		p.t += delta
	_popups = _popups.filter(func(p): return p.t < 1.1)
	queue_redraw()


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
	_grid_ref = state.grid
	_stage = str(state.stage_id)
	if island != null:
		island.free()
	for a in actors.values():
		a.free()
	actors = {}
	_snap = {}
	_popups = []
	for c in _fx.get_children():
		c.free()
	var th := theme_name()
	var fam := str(Data.rules().get("tower_theme_family", {}).get(th, "Light"))
	var pal := SkyBackdrop.palette(fam)
	var haze: Color = Color(pal.low_color).lerp(pal.mid_color, 0.35)
	builder = Build.new()
	island = builder.build(state, th, haze)
	world.add_child(island)
	environment.ambient_light_color = Color(pal.mid_color).lerp(Palette.SOFT_SILVER, 0.7)
	var dark := ["Dark", "Space", "Aether"].has(th)
	sun.light_energy = 0.9 if dark else 1.1
	sun.light_color = Palette.SOFT_SILVER.lerp(Palette.CRYSTAL_VIOLET if dark else Palette.SIGIL_GOLD, 0.28)
	_sym_hp = [state.symbol_hp[0], state.symbol_hp[1]]
	_ev_idx = state.events.size()
	_hl_key = "?"
	_sync_units(true)
	_refit()


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
		var hp: int = state.symbol_hp[side]
		if _sym_hp[side] >= 0 and hp < _sym_hp[side] and builder.sigils.has(side):
			var g: Dictionary = builder.sigils[side]
			_popup(g.node.global_position + Vector3(0, 1.4, 0), "-%d" % (_sym_hp[side] - hp), Palette.EMBER)
			burst(g.node.global_position + Vector3(0, 1.0, 0), Palette.side(side), 8)
		_sym_hp[side] = hp
		if builder.sigils.has(side):
			builder.sigils[side].gem.visible = hp > 0


func _sync_units(initial: bool) -> void:
	var seen := {}
	for u in state.units:
		seen[u.id] = true
		var a: Actor = actors.get(u.id)
		if a == null:
			a = Actor.new()
			a.setup(u)
			world.add_child(a)
			a.snap_to(_stand(u.pos))
			actors[u.id] = a
			_snap[u.id] = {"pos": u.pos, "hp": u.hp, "dormant": u.dormant}
			if not initial:
				a.summon()
				burst(_stand(u.pos) + Vector3(0, 0.3, 0), Palette.side(u.owner), 16)
			continue
		var s: Dictionary = _snap[u.id]
		if s.pos != u.pos:
			var path := tile_path(s.pos, u.pos)
			if path.size() >= 2:
				var pts: Array = []
				for c in path:
					pts.append(_stand(c))
				a.move_path(pts)
			else:
				burst(a.base + Vector3(0, 0.3, 0), Palette.CRYSTAL_VIOLET, 8)
				a.warp_to(_stand(u.pos))
				burst(_stand(u.pos) + Vector3(0, 0.3, 0), Palette.CRYSTAL_VIOLET, 10)
		if u.hp < s.hp:
			a.hit()
			_popup(a.head_world(), "-%d" % (s.hp - u.hp), Palette.EMBER)
		elif u.hp > s.hp:
			_popup(a.head_world(), "+%d" % (u.hp - s.hp), Palette.VERDANT_GREEN)
		if s.dormant and not u.dormant:
			a.awaken()
			burst(a.base + Vector3(0, 0.4, 0), Palette.EMBER, 12)
		a.dormant = u.dormant
		a.spent = u.moved and u.attacked
		_snap[u.id] = {"pos": u.pos, "hp": u.hp, "dormant": u.dormant}
	for id in actors.keys():
		if not seen.has(id):
			var a: Actor = actors[id]
			burst(a.base + Vector3(0, 0.4, 0), Palette.family(a.family), 10)
			a.faint()
			actors.erase(id)
			_snap.erase(id)
	if state.events.size() < _ev_idx:
		_ev_idx = 0
	for i in range(_ev_idx, state.events.size()):
		_on_event(str(state.events[i]))
	_ev_idx = state.events.size()


func _actor_named(n: String) -> Actor:
	for a in actors.values():
		if a.unit_name == n and not a.dying:
			return a
	return null


func _on_event(msg: String) -> void:
	var m := _re_hit.search(msg)
	if m != null:
		var a := _actor_named(m.get_string(1))
		if a == null:
			return
		var target := m.get_string(2)
		var sm := _re_sym.search(target)
		var dest := Vector3.ZERO
		if sm != null:
			dest = Build.cell_pos(state.symbol_pos[int(sm.get_string(1))])
		else:
			var t := _actor_named(target)
			if t == null:
				for u in state.units:
					if u.name == target:
						dest = _stand(u.pos)
			else:
				dest = t.base
		a.lunge_at(dest)
		return
	m = _re_miss.search(msg)
	if m != null:
		var a := _actor_named(m.get_string(1))
		if a != null:
			a.lunge_at(a.base + a.facing)
			_popup(a.head_world(), "miss", Palette.SOFT_SILVER)
		return
	m = _re_use.search(msg)
	if m != null:
		var a := _actor_named(m.get_string(1))
		if a != null:
			a.cast()
			burst(a.base + Vector3(0, 0.5, 0), Palette.family(a.family), 8)


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
	var flash := MeshInstance3D.new()
	flash.mesh = QuadMesh.new()
	var fm := Mats.halo(col, 1.4)
	flash.material_override = fm
	flash.position = pos
	flash.scale = Vector3.ONE * 0.3
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.add_child(flash)
	var tw := flash.create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "scale", Vector3.ONE * 1.9, 0.45).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): fm.set_shader_parameter("intensity", v), 1.4, 0.0, 0.5)
	tw.chain().tween_callback(flash.queue_free)
	get_tree().create_timer(1.3).timeout.connect(p.queue_free)


func _popup(world_pos: Vector3, text: String, col: Color) -> void:
	_popups.append({"pos": world_pos, "text": text, "col": col, "t": 0.0})


# ---------------------------------------------------------------- 2D overlay (HP bars, badges, popups)

func _draw() -> void:
	if state == null or state.grid.is_empty() or cam == null or not cam.is_inside_tree():
		return
	var inv := get_global_transform_with_canvas().affine_inverse()
	var w := 46.0 * clampf(zoom, 1.0, 1.6)
	for id in actors:
		var a: Actor = actors[id]
		var u := state.get_unit(id)
		if u == null or a.dying or cam.is_position_behind(a.head_world()):
			continue
		var sp: Vector2 = inv * _screen(a.head_world())
		Art.hp_bar(self, sp, w, u.hp, u.max_hp, Palette.side(u.owner))
		var icon: Texture2D = Assets.element_icon(u.family)
		var ic := sp + Vector2(w / 2.0 + 14.0, 0.0)
		draw_circle(ic, 12.0, Palette.MIDNIGHT_NAVY)
		draw_arc(ic, 12.0, 0, TAU, 20, Palette.side(u.owner), 2.0, true)
		if icon != null:
			draw_texture_rect(icon, Rect2(ic - Vector2(9, 9), Vector2(18, 18)), false)
		else:
			draw_circle(ic, 7.0, Palette.family(u.family))
	for side in 2:
		if builder != null and builder.sigils.has(side) and state.symbol_hp[side] > 0:
			var sp: Vector2 = inv * _screen(builder.sigils[side].node.global_position + Vector3(0, 1.75, 0))
			Art.hp_bar(self, sp, w * 1.4, state.symbol_hp[side], state.symbol_max, Palette.side(side))
	var f := Art.font()
	for p in _popups:
		var sp: Vector2 = inv * _screen(p.pos) - Vector2(0, 70.0 * p.t)
		var a := clampf(1.3 - p.t * 1.2, 0.0, 1.0)
		var fs := 40
		var tw := f.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(f, sp - Vector2(tw / 2, 0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(Palette.MIDNIGHT_NAVY, a))
		draw_string(f, sp - Vector2(tw / 2, 0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(p.col, a))
