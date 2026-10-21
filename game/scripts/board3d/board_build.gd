## Builds the 3D floating-ruin island for one GameState (presentation only; reads the grid, never
## changes it). Everything solid is merged into ONE stone mesh (one draw call + shadow pass); water,
## waterfalls, glow crystals, foliage and clouds are one mesh / MultiMesh each. Per-object nodes are
## only made for things that change at runtime: capsule-node gems, relic gems, Sigil crystals,
## portals, and the tall rim decor of each side (hidden when that side is nearest the camera).
##
## World layout: tile c's centre is (c.x - 5.5, top, c.y - 5.5); 1 unit = 1 tile.
extends RefCounted

const Kit = preload("res://scripts/board3d/mesh_kit.gd")
const Mats = preload("res://scripts/board3d/mats.gd")
const GameState = preload("res://scripts/game_state.gd")
const Data = preload("res://scripts/data_loader.gd")
const Palette = preload("res://scripts/theme_colors.gd")

const H := 0.6            ## world height per 1.0 of a tile's `raise` (game_rules.json tiles)
const BASE := -0.55       ## underside of the tile blocks = top of the island rock
const WATER_Y := -0.1     ## water surface in channels
const CHANNEL_Y := -0.32  ## channel floor under water / bridges
const RIM_Y := -0.12      ## the ruin ledge around the 12x12 board
const BEVEL := 0.028
const HALF := (GameState.SIZE - 1) / 2.0
const ISLAND_R := HALF + 1.5   ## outer edge of the rim ring

## Surface kinds read by stone.gdshader from UV2.x.
const K_STONE := 0
const K_ROCK := 1
const K_HAZARD := 2
const K_LAVA := 3
const K_ICE := 4
const K_METAL := 5
const K_SHADOW := 6
const K_SPAWN_P := 7
const K_SPAWN_E := 8
const K_WOOD := 9
const K_CRYSTAL := 10
const K_LEAF := 11
const K_GOLD := 12
const K_SKY := 13
const K_CHANNEL := 14

## Side index order used everywhere: 0 = -z, 1 = +x, 2 = +z, 3 = -x.
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const WET := ["water", "bridge"]
const BLOCKS := ["obstacle", "ruins"]
const FLORA_DENSITY := {"grass": 1.0, "ember": 0.35, "frost": 0.45, "coral": 0.7, "cog": 0.25, "shadow": 0.55, "crystal": 0.45}

var state
var theme: Dictionary
var theme_name := ""
var haze := Color(0.7, 0.8, 0.95)
var root: Node3D
var stats: Dictionary = {}
var gems: Dictionary = {}       ## Vector2i -> {node, gem, halo, kind}  capsule nodes + relics
var sigils: Dictionary = {}     ## side -> {node, gem, halo}
var portals: Dictionary = {}    ## Vector2i -> {node, ring, halo}
var rim_tall: Array = [null, null, null, null]
var spinners: Array = []        ## [Node3D, rad/s, bob amplitude, base y]
var _rim_top: Dictionary = {}   ## border cell (x or y in {-1, 12}) -> top y
var _rim_wet: Dictionary = {}   ## border cells carrying a channel to a waterfall
var _salt := 0
var _stone_mat: ShaderMaterial


# ---------------------------------------------------------------- static geometry queries

## Ground-plane centre of tile c in world space (y = 0).
static func cell_pos(c: Vector2i) -> Vector3:
	return Vector3(c.x - HALF, 0.0, c.y - HALF)


## Height of the walkable / pickable top surface of a tile type.
static func top_y(type: String) -> float:
	match type:
		"water":
			return WATER_Y
		"bridge":
			return 0.05
		"":
			return BASE
	return float(Data.tile_def(type).get("raise", 0.0)) * H


## Height of the box a tap ray is tested against: the visual top clamped to [0, PICK_CAP]. With
## every pick box inside that band no top face can hide a neighbour's centre at the board camera's
## pitch, so the projected centre of every tile picks that tile (tests/test_board3d.gd), while a
## tap anywhere on a raised top still lands on it (the ray drops < 0.5 tile before reaching the box).
const PICK_CAP := 0.28


static func pick_top(type: String) -> float:
	return clampf(top_y(type), 0.0, PICK_CAP)


## Where a monster's feet go on tile c (on top of a node pedestal / relic altar).
static func stand_y(st, c: Vector2i) -> float:
	var t: String = st.tile_type(c)
	return top_y(t) + (0.07 if t == "capsule_node" or t == "relic" else 0.0)


# ---------------------------------------------------------------- helpers

func _h(c: Vector2i, salt: int) -> float:
	return float(absi(hash([_salt, c.x, c.y, salt])) % 100003) / 100003.0


func _floor_y(c: Vector2i) -> float:
	if GameState.in_bounds(c):
		var t: String = state.tile_type(c)
		return CHANNEL_Y if WET.has(t) else top_y(t)
	return float(_rim_top.get(c, BASE))


func _lit(c: Color, v: float) -> Color:
	return Color(c.r * v, c.g * v, c.b * v, 1.0)


func _top_col(type: String, c: Vector2i) -> Color:
	var s: Color = theme.stone
	var v := 0.9 + 0.2 * _h(c, 1)
	match type:
		"stone": s = s.lightened(0.14)
		"elevation": s = s.lerp(theme.cliff, 0.12).lightened(0.06)
		"obstacle", "ruins": s = s.darkened(0.04)
		"hazard": s = s.darkened(0.2)
		"lava": s = Palette.MIDNIGHT_NAVY.lerp(Palette.EMBER, 0.2)
		"ice": s = Palette.SOFT_SILVER.lerp(Palette.AETHER_CYAN, 0.28)
		"metal": s = Palette.SOFT_SILVER.lerp(Palette.MIDNIGHT_NAVY, 0.42)
		"shadow": s = Palette.CRYSTAL_VIOLET.lerp(Palette.MIDNIGHT_NAVY, 0.68)
		"crystal": s = s.lerp(Palette.CRYSTAL_VIOLET, 0.28).lightened(0.05)
		"forest": s = s.lerp(theme.moss, 0.55)
		"mixed": s = s.lerp(theme.moss, 0.2)
		"sky": s = Palette.AETHER_CYAN.lerp(Palette.SOFT_SILVER, 0.5)
		"space": s = Palette.CRYSTAL_VIOLET.lerp(Palette.MIDNIGHT_NAVY, 0.6)
		"rift": s = Palette.CRYSTAL_VIOLET.lerp(Palette.EMBER, 0.3).lerp(Palette.MIDNIGHT_NAVY, 0.45)
		"player_spawn", "enemy_spawn": s = s.lightened(0.04)
	return _lit(s, v)


func _side_col(c: Vector2i) -> Color:
	return _lit(Color(theme.stone).lerp(theme.cliff, 0.45), 0.85 + 0.15 * _h(c, 2))


func _kind(type: String) -> int:
	match type:
		"hazard", "rift": return K_HAZARD
		"lava": return K_LAVA
		"ice": return K_ICE
		"metal": return K_METAL
		"shadow": return K_SHADOW
		"crystal": return K_CRYSTAL
		"player_spawn": return K_SPAWN_P
		"enemy_spawn": return K_SPAWN_E
		"sky", "space": return K_SKY
	return K_STONE


func _moss(type: String) -> float:
	match type:
		"mixed": return 1.0
		"ground": return 0.55
		"obstacle", "ruins": return 0.85
		"elevation": return 0.65
		"stone": return 0.4
		"forest": return 0.9
		"hazard", "lava", "metal", "ice", "shadow", "sky", "space", "rift": return 0.12
	return 0.35


## Stone block with a bevelled top: rect [x0,x1]x[z0,z1], top `t`, per-side bottoms (side index order).
## A side is skipped when its bottom is not below the bevel.
func _slab(K: Kit, x0: float, z0: float, x1: float, z1: float, t: float, bottoms: Array, top_col: Color, side_col: Color, uv_top: Vector2, uv_side: Vector2, b := BEVEL, ao := PackedFloat32Array()) -> void:
	var tcs := PackedColorArray()
	if ao.size() == 4:
		for i in 4:
			tcs.append(_lit(top_col, ao[i]))
	K.quad(Vector3(x0 + b, t, z0 + b), Vector3(x0 + b, t, z1 - b), Vector3(x1 - b, t, z1 - b), Vector3(x1 - b, t, z0 + b), top_col, uv_top, tcs)
	var e := t - b
	var bev := top_col.lerp(side_col, 0.5).darkened(0.3)
	# chamfers: -z, +x, +z, -x
	K.quad(Vector3(x1, e, z0), Vector3(x0, e, z0), Vector3(x0 + b, t, z0 + b), Vector3(x1 - b, t, z0 + b), bev, uv_top)
	K.quad(Vector3(x1, e, z1), Vector3(x1, e, z0), Vector3(x1 - b, t, z0 + b), Vector3(x1 - b, t, z1 - b), bev, uv_top)
	K.quad(Vector3(x0, e, z1), Vector3(x1, e, z1), Vector3(x1 - b, t, z1 - b), Vector3(x0 + b, t, z1 - b), bev, uv_top)
	K.quad(Vector3(x0, e, z0), Vector3(x0, e, z1), Vector3(x0 + b, t, z1 - b), Vector3(x0 + b, t, z0 + b), bev, uv_top)
	var lo := side_col.darkened(0.25)
	for i in 4:
		var y0: float = bottoms[i]
		if y0 >= e - 0.001:
			continue
		var cs := PackedColorArray([lo, lo, side_col, side_col])
		match i:
			0: K.quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, e, z0), Vector3(x1, e, z0), side_col, uv_side, cs)
			1: K.quad(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, e, z0), Vector3(x1, e, z1), side_col, uv_side, cs)
			2: K.quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, e, z1), Vector3(x0, e, z1), side_col, uv_side, cs)
			3: K.quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, e, z1), Vector3(x0, e, z0), side_col, uv_side, cs)


## Contact shadow per top corner (x0z0, x0z1, x1z1, x1z0): darker where taller neighbours stand.
func _corner_ao(c: Vector2i, t: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for corner in [Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(1, -1)]:
		var occ := 0.0
		for n in [Vector2i(corner.x, 0), Vector2i(0, corner.y), corner]:
			var nc: Vector2i = c + n
			if GameState.in_bounds(nc):
				var nt: String = state.tile_type(nc)
				var rise := top_y(nt) - t + (0.5 if BLOCKS.has(nt) else 0.0)
				occ += clampf(rise / 0.35, 0.0, 1.0)
		out.append(1.0 - 0.17 * occ)
	return out


func _bottoms(c: Vector2i) -> Array:
	var out := []
	for d in DIRS:
		out.append(_floor_y(c + d))
	return out


# ---------------------------------------------------------------- build

## Builds the island for `p_state` with the tower theme `p_theme_name` (bible tower `theme`).
## Returns the root Node3D (also kept in `root`); `stats` describes what was built (tests).
func build(p_state, p_theme_name: String, p_haze: Color) -> Node3D:
	state = p_state
	theme_name = p_theme_name
	theme = Palette.tower_theme(p_theme_name)
	haze = p_haze
	_salt = hash(str(state.stage_id))
	root = Node3D.new()
	root.name = "Island"
	stats = {"tiles": 0, "types": {}, "built": {}, "verts": 0, "decor": {}, "waterfalls": 0, "foliage": 0, "vines": 0}
	gems = {}
	sigils = {}
	portals = {}
	spinners = []
	_stone_mat = Mats.stone(theme, haze)
	var K := Kit.new()   # stone: tiles, props, rim, underside
	var W := Kit.new()   # water surfaces
	var F := Kit.new()   # waterfalls
	var G := Kit.new()   # static glowing crystals
	var grass: Array = []
	var vines: Array = []
	_plan_rim()
	for y in GameState.SIZE:
		for x in GameState.SIZE:
			var before := K.vertex_count() + W.vertex_count() + G.vertex_count()
			var c := Vector2i(x, y)
			_tile(K, W, F, G, grass, vines, c)
			var type: String = state.tile_type(c)
			stats.tiles += 1
			stats.types[type] = int(stats.types.get(type, 0)) + 1
			if K.vertex_count() + W.vertex_count() + G.vertex_count() > before:
				stats.built[type] = true
	_rim(K, W, F, grass, vines)
	_dress(K, vines)
	_underside(K, vines)
	_distant(K)
	_add_mesh(K, _stone_mat, "Stone", true)
	_add_mesh(W, Mats.water(theme), "Water", false)
	_add_mesh(F, Mats.fall(theme), "Falls", false)
	_add_mesh(G, Mats.crystal(theme.accent, 1.2), "Glow", false)
	_add_foliage(grass, vines)
	_add_clouds()
	stats.verts = K.vertex_count() + W.vertex_count() + F.vertex_count() + G.vertex_count()
	stats.foliage = grass.size()
	stats.vines = vines.size()
	return root


func _add_mesh(k: Kit, mat: Material, name: String, shadows: bool) -> MeshInstance3D:
	if k.vertex_count() == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = k.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


# ---------------------------------------------------------------- tiles

func _tile(K: Kit, W: Kit, F: Kit, G: Kit, grass: Array, vines: Array, c: Vector2i) -> void:
	var type: String = state.tile_type(c)
	var p := cell_pos(c)
	var t := top_y(type)
	var x0 := p.x - 0.5
	var x1 := p.x + 0.5
	var z0 := p.z - 0.5
	var z1 := p.z + 0.5
	var bt := _bottoms(c)
	var tc := _top_col(type, c)
	var sc := _side_col(c)
	var uvt := Vector2(_kind(type), _moss(type))
	var side_kind := K_METAL if type == "metal" else (K_ICE if type == "ice" else (K_LAVA if type == "lava" else K_STONE))
	var uvs := Vector2(side_kind, _moss(type) * 0.8)
	match type:
		"water", "bridge":
			_slab(K, x0, z0, x1, z1, CHANNEL_Y, bt, _lit(theme.cliff, 0.8), sc, Vector2(K_CHANNEL, 0.3), Vector2(K_STONE, 0.6), 0.0)
			W.quad(Vector3(x0, WATER_Y, z0), Vector3(x0, WATER_Y, z1), Vector3(x1, WATER_Y, z1), Vector3(x1, WATER_Y, z0), Color.WHITE)
			if type == "bridge":
				_bridge(K, c, p)
			for i in 4:
				if not GameState.in_bounds(c + DIRS[i]) and not _rim_wet.has(c + DIRS[i]):
					_fall(F, p, i, 0.5, WATER_Y)
		"elevation":
			_elevation(K, c, p, t, bt, tc, sc, uvt, uvs)
		"obstacle", "ruins":
			_slab(K, x0, z0, x1, z1, t, bt, tc, sc, uvt, uvs)
			_obstacle(K, c, p, t)
			_scatter(grass, c, t, 2.0, 0.42)
		_:
			_slab(K, x0, z0, x1, z1, t, bt, tc, sc, uvt, uvs, BEVEL, _corner_ao(c, t))
	match type:
		"capsule_node": _capsule(K, c, p, t)
		"relic": _relic(K, c, p, t)
		"warp_gate": _portal(K, c, p, t)
		"player_symbol": _sigil(K, c, p, t, GameState.PLAYER)
		"enemy_symbol": _sigil(K, c, p, t, GameState.ENEMY)
		"crystal": _shards(G, c, p, t, 3, 0.42)
		"forest": _bushes(K, c, p, t)
	var dens := {"mixed": 4.5, "ground": 1.3, "forest": 6.0, "elevation": 2.0, "stone": 1.0}
	if dens.has(type):
		_scatter(grass, c, t, float(dens[type]), 0.45)
	if type == "elevation" or BLOCKS.has(type):
		for i in 4:
			if bt[i] < t - 0.25 and _h(c, 40 + i) < 0.45:
				_vine_on_face(vines, p, i, t, 0.3 + 0.5 * _h(c, 50 + i))


## Bridge over a channel: plank deck along the walkable axis, stone end caps, rope posts.
func _bridge(K: Kit, c: Vector2i, p: Vector3) -> void:
	var along_x := _bridge_axis_x(c)
	var wood := _lit(Palette.SIGIL_GOLD.lerp(Palette.MIDNIGHT_NAVY, 0.55).lerp(Palette.EMBER, 0.12), 1.0)
	var n := 6
	for i in n:
		var f := -0.5 + (i + 0.5) / n
		var w := 0.5 / n * 0.86
		var dy := 0.012 * sin(i * 2.1 + _h(c, 7) * 6.0)
		if along_x:
			K.box(p + Vector3(f - w, -0.02 + dy, -0.36), p + Vector3(f + w, 0.05 + dy, 0.36), _lit(wood, 0.85 + 0.3 * _h(c, 60 + i)), Vector2(K_WOOD, 0.0))
		else:
			K.box(p + Vector3(-0.36, -0.02 + dy, f - w), p + Vector3(0.36, 0.05 + dy, f + w), _lit(wood, 0.85 + 0.3 * _h(c, 60 + i)), Vector2(K_WOOD, 0.0))
	for s in [-1, 1]:
		for e in [-1, 1]:
			var q := Vector3(e * 0.42, 0, s * 0.4) if along_x else Vector3(s * 0.4, 0, e * 0.42)
			K.box(p + q + Vector3(-0.04, -0.3, -0.04), p + q + Vector3(0.04, 0.22, 0.04), wood.darkened(0.2), Vector2(K_WOOD, 0.0))
		var r0 := Vector3(-0.42, 0.17, s * 0.4) if along_x else Vector3(s * 0.4, 0.17, -0.42)
		var r1 := Vector3(0.42, 0.2, s * 0.4) if along_x else Vector3(s * 0.4, 0.2, 0.42)
		K.box(p + r0.min(r1) - Vector3(0.015, 0.015, 0.015), p + r0.max(r1) + Vector3(0.015, 0.0, 0.015), wood.lightened(0.1), Vector2(K_WOOD, 0.0))


func _bridge_axis_x(c: Vector2i) -> bool:
	var score := func(d: Vector2i) -> int:
		var s := 0
		for n in [c + d, c - d]:
			if GameState.in_bounds(n):
				var t: String = state.tile_type(n)
				s += 2 if t == "bridge" else (1 if state.is_walkable(n) and t != "water" else 0)
		return s
	return score.call(Vector2i(1, 0)) >= score.call(Vector2i(0, 1))


## High ground with a short flight of stairs carved toward the lowest walkable neighbour.
func _elevation(K: Kit, c: Vector2i, p: Vector3, t: float, bt: Array, tc: Color, sc: Color, uvt: Vector2, uvs: Vector2) -> void:
	var best := -1
	var best_score := -1e9
	for i in 4:
		var n := c + DIRS[i]
		if not GameState.in_bounds(n) or not state.is_walkable(n):
			continue
		var nt: String = state.tile_type(n)
		if WET.has(nt) or top_y(nt) > t - 0.15:
			continue
		var sc2 := -Vector2(n).distance_to(Vector2(HALF, HALF)) + _h(c, 30 + i) * 0.5
		if sc2 > best_score:
			best_score = sc2
			best = i
	if best < 0:
		_slab(K, p.x - 0.5, p.z - 0.5, p.x + 0.5, p.z + 0.5, t, bt, tc, sc, uvt, uvs)
		return
	var nh := top_y(state.tile_type(c + DIRS[best]))
	var front := best
	var back := (best + 2) % 4
	var cuts := [-0.5, 0.06, 0.21, 0.36, 0.5]
	for s in 4:
		var u0: float = cuts[s]
		var u1: float = cuts[s + 1]
		var h := t if s == 0 else lerpf(t, nh, float(s) / 4.0)
		var next_h := nh if s == 3 else lerpf(t, nh, float(s + 1) / 4.0)
		var b := bt.duplicate()
		b[front] = next_h
		b[back] = 99.0 if s > 0 else bt[back]
		var r := _sub_rect(p, DIRS[best], u0, u1)
		var col := tc if s == 0 else tc.lerp(sc, 0.15 * s)
		_slab(K, r.x, r.y, r.z, r.w, h, b, col, sc, uvt, uvs, BEVEL if s == 0 else 0.018)
	stats.decor["stairs"] = int(stats.decor.get("stairs", 0)) + 1


## Rect (x0, z0, x1, z1) of the strip u0..u1 (-0.5 = back edge, 0.5 = front edge toward d) of a tile.
func _sub_rect(p: Vector3, d: Vector2i, u0: float, u1: float) -> Vector4:
	if d.x > 0:
		return Vector4(p.x + u0, p.z - 0.5, p.x + u1, p.z + 0.5)
	if d.x < 0:
		return Vector4(p.x - u1, p.z - 0.5, p.x - u0, p.z + 0.5)
	if d.y > 0:
		return Vector4(p.x - 0.5, p.z + u0, p.x + 0.5, p.z + u1)
	return Vector4(p.x - 0.5, p.z - u1, p.x + 0.5, p.z - u0)


func _is_block(c: Vector2i) -> bool:
	return GameState.in_bounds(c) and BLOCKS.has(state.tile_type(c))


## Obstacle decor: wall runs between neighbouring obstacles, otherwise a column, a gate arch or rubble.
func _obstacle(K: Kit, c: Vector2i, p: Vector3, t: float) -> void:
	var sc := _lit(Color(theme.stone).lerp(theme.cliff, 0.25), 0.95 + 0.1 * _h(c, 8))
	var uv := Vector2(K_STONE, 0.9)
	var runs: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(0, 1)]:
		if _is_block(c + d):
			runs.append(d)
	var linked := not runs.is_empty() or _is_block(c - Vector2i(1, 0)) or _is_block(c - Vector2i(0, 1))
	var roll := _h(c, 9)
	var o := p + Vector3(0, t, 0)
	if linked:
		var ph := 0.42 + 0.38 * _h(c, 10)
		K.box(o + Vector3(-0.2, 0, -0.2), o + Vector3(0.2, ph, 0.2), sc, uv)
		K.box(o + Vector3(-0.24, ph, -0.24), o + Vector3(0.24, ph + 0.07, 0.24), sc.lightened(0.08), uv)
		for d in runs:
			for k in 3:
				var a := 0.2 + k * 0.2
				var hh := 0.18 + 0.45 * _h(c, 11 + k + d.x * 5)
				if d.x != 0:
					K.box(o + Vector3(a, 0, -0.13), o + Vector3(a + 0.2, hh, 0.13), sc.darkened(0.05 * k), uv)
				else:
					K.box(o + Vector3(-0.13, 0, a), o + Vector3(0.13, hh, a + 0.2), sc.darkened(0.05 * k), uv)
		_count("wall")
	elif roll < 0.5:
		_column(K, o, 0.75 + 0.65 * _h(c, 12), _h(c, 13) < 0.45, sc, uv, _h(c, 14))
		_count("column")
	elif roll < 0.76:
		var along_x := _h(c, 15) < 0.5
		var hh := 0.62 + 0.2 * _h(c, 16)
		for s in [-1, 1]:
			var q := Vector3(s * 0.3, 0, 0) if along_x else Vector3(0, 0, s * 0.3)
			K.box(o + q + Vector3(-0.1, 0, -0.1), o + q + Vector3(0.1, hh, 0.1), sc, uv)
		var seg := 6
		var broken := int(_h(c, 17) * 3.0)
		for i in seg - broken:
			var a0 := PI * i / seg
			var a1 := PI * (i + 1) / seg
			var am := (a0 + a1) * 0.5
			var q := Vector3(-cos(am) * 0.3, hh + sin(am) * 0.3, 0)
			if not along_x:
				q = Vector3(0, q.y, q.x)
			K.xf = Transform3D(Basis(Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0), (am - PI / 2) * (1.0 if along_x else -1.0)), o + q)
			K.box(Vector3(-0.07, -0.08, -0.09), Vector3(0.07, 0.08, 0.09), sc.lightened(0.04), uv)
			K.xf = Transform3D.IDENTITY
		_count("arch")
	elif roll < 0.88:
		_guardian_statue(K, o, sc, c)
		_count("statue")
	else:
		_column(K, o, 0.25 + 0.2 * _h(c, 18), false, sc, uv, _h(c, 19))
		K.xf = Transform3D(Basis(Vector3(0, 1, 0), _h(c, 20) * TAU) * Basis(Vector3(0, 0, 1), PI / 2), o + Vector3(0.12, 0.13, 0.18))
		K.cylinder(0.13, 0.13, -0.25, 0.25, 8, sc.darkened(0.08), uv)
		K.xf = Transform3D.IDENTITY
		_rubble(K, o, 5, sc, c)
		_count("rubble")


## A weathered lion guardian on a plinth (set dressing on blocked tiles; never a unit).
func _guardian_statue(K: Kit, o: Vector3, sc: Color, c: Vector2i) -> void:
	var uv := Vector2(K_STONE, 0.9)
	var face := _h(c, 21) * TAU
	K.box(o + Vector3(-0.26, 0, -0.26), o + Vector3(0.26, 0.16, 0.26), sc.darkened(0.08), uv)
	K.xf = Transform3D(Basis(Vector3.UP, face), o + Vector3(0, 0.16, 0))
	K.ellipsoid(0.2, 0.14, 0.12, sc.lightened(0.05), uv, 5, 8)
	K.xf = Transform3D(Basis(Vector3.UP, face), o + Vector3(0, 0.16, 0) + Basis(Vector3.UP, face) * Vector3(0.16, 0.16, 0))
	K.ellipsoid(0.11, 0.12, 0.11, sc.lightened(0.1), uv, 5, 8)
	K.cylinder(0.15, 0.08, -0.06, 0.06, 7, sc, uv)   # mane ruff
	K.xf = Transform3D.IDENTITY
	_count("guardian")


## Braziers with live fire on a few blocked tiles, fallen columns on the near rim: set dressing in
## the play area that never covers a walkable tile (picking is against tile boxes, unaffected).
func _dress(K: Kit, vines: Array) -> void:
	var blocked: Array = []
	for y in GameState.SIZE:
		for x in GameState.SIZE:
			var c := Vector2i(x, y)
			if BLOCKS.has(state.tile_type(c)):
				blocked.append(c)
	blocked.sort_custom(func(a, b): return _h(a, 700) < _h(b, 700))
	for i in mini(3, blocked.size()):
		var c: Vector2i = blocked[i]
		var p := cell_pos(c) + Vector3(0, top_y(state.tile_type(c)), 0)
		var corner := Vector3(0.3 if _h(c, 701) < 0.5 else -0.3, 0, 0.3 if _h(c, 702) < 0.5 else -0.3)
		_brazier(K, p + corner)
		# vines climbing the blocked tile's faces
		for k in 4:
			_vine_on_face(vines, cell_pos(c), k, top_y(state.tile_type(c)) + 0.4, 0.5)
	var n := GameState.SIZE
	for c in _rim_top:
		if _rim_wet.has(c) or _h(c, 710) > 0.3:
			continue
		var near: bool = c.y >= n or c.x < 0     # the sides nearest the default camera stay low
		var t: float = _rim_top[c]
		var p := cell_pos(c) + Vector3(0, t, 0)
		var col := _lit(Color(theme.stone).lerp(theme.cliff, 0.2), 0.95)
		var r := 0.1 if near else 0.15
		K.xf = Transform3D(Basis(Vector3.UP, _h(c, 711) * PI) * Basis(Vector3(0, 0, 1), PI / 2), p + Vector3(0, r, 0))
		K.cylinder(r, r, -0.32, 0.32, 8, col, Vector2(K_STONE, 0.9))
		K.xf = Transform3D.IDENTITY
		_count("fallen_column")


func _brazier(K: Kit, o: Vector3) -> void:
	var iron := _lit(Palette.MIDNIGHT_NAVY.lerp(Palette.SIGIL_GOLD, 0.35), 0.9)
	for i in 3:
		var a := TAU * i / 3.0
		K.xf = Transform3D(Basis(Vector3(cos(a + PI / 2), 0, sin(a + PI / 2)), 0.18), o + Vector3(cos(a) * 0.07, 0, sin(a) * 0.07))
		K.cylinder(0.018, 0.014, 0.0, 0.34, 4, iron, Vector2(K_METAL, 0.0))
	K.xf = Transform3D(Basis(), o + Vector3(0, 0.32, 0))
	K.cylinder(0.08, 0.15, 0.0, 0.09, 8, _lit(Palette.SIGIL_GOLD, 0.75), Vector2(K_GOLD, 0.0))
	K.xf = Transform3D.IDENTITY
	var fire := CPUParticles3D.new()
	fire.name = "BrazierFire"
	var q := QuadMesh.new()
	q.size = Vector2(0.13, 0.13)
	fire.mesh = q
	fire.material_override = Mats.particle()
	fire.amount = 16
	fire.lifetime = 0.7
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = 0.06
	fire.direction = Vector3.UP
	fire.spread = 12.0
	fire.initial_velocity_min = 0.25
	fire.initial_velocity_max = 0.5
	fire.gravity = Vector3(0, 0.8, 0)
	fire.scale_amount_min = 0.7
	fire.scale_amount_max = 1.3
	var g := Gradient.new()
	g.set_color(0, Color(Palette.SIGIL_GOLD.lerp(Color.WHITE, 0.4), 0.95))
	g.set_color(1, Color(Palette.EMBER.darkened(0.3), 0.0))
	g.add_point(0.45, Color(Palette.EMBER, 0.8))
	fire.color_ramp = g
	fire.position = o + Vector3(0, 0.43, 0)
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fire)
	var glow := MeshInstance3D.new()
	glow.mesh = QuadMesh.new()
	glow.material_override = Mats.halo(Palette.EMBER.lerp(Palette.SIGIL_GOLD, 0.4), 0.7)
	glow.position = o + Vector3(0, 0.5, 0)
	glow.scale = Vector3.ONE * 0.9
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)
	_count("brazier")


func _count(k: String) -> void:
	stats.decor[k] = int(stats.decor.get(k, 0)) + 1


## A fluted-looking column: plinth, 8-sided shaft, capital (or a slanted broken top).
func _column(K: Kit, o: Vector3, height: float, intact: bool, sc: Color, uv: Vector2, r: float) -> void:
	K.box(o + Vector3(-0.27, 0, -0.27), o + Vector3(0.27, 0.1, 0.27), sc.darkened(0.06), uv)
	K.xf = Transform3D(Basis(Vector3.UP, r * TAU), o)
	K.cylinder(0.19, 0.17, 0.1, height, 8, sc.lightened(0.05), uv, not intact)
	if intact:
		K.box(Vector3(-0.24, height, -0.24), Vector3(0.24, height + 0.09, 0.24), sc.lightened(0.1), uv)
		K.box(Vector3(-0.2, height - 0.05, -0.2), Vector3(0.2, height, 0.2), sc, uv)
	else:
		K.xf = Transform3D(Basis(Vector3.UP, r * TAU) * Basis(Vector3(1, 0, 0), 0.5), o + Vector3(0, height, 0))
		K.cylinder(0.17, 0.12, -0.05, 0.12, 8, sc.lightened(0.05), uv)
	K.xf = Transform3D.IDENTITY


func _rubble(K: Kit, o: Vector3, n: int, sc: Color, c: Vector2i) -> void:
	for i in n:
		var a := _h(c, 70 + i) * TAU
		var d := 0.18 + 0.22 * _h(c, 80 + i)
		var s := 0.05 + 0.06 * _h(c, 90 + i)
		K.xf = Transform3D(Basis(Vector3(_h(c, 100 + i), 1, _h(c, 110 + i)).normalized(), a), o + Vector3(cos(a) * d, s * 0.6, sin(a) * d))
		K.box(Vector3(-s, -s, -s), Vector3(s, s, s), sc.darkened(0.1 * _h(c, 120 + i)), Vector2(K_STONE, 0.5))
	K.xf = Transform3D.IDENTITY


# ---------------------------------------------------------------- objectives

func _pedestal(K: Kit, o: Vector3, r: float, h: float, gold: bool) -> void:
	K.xf = Transform3D(Basis(Vector3.UP, PI / 8), o)
	K.cylinder(r, r * 0.92, 0.0, h, 8, _lit(Color(theme.stone).lightened(0.12), 1.0), Vector2(K_STONE, 0.2))
	if gold:
		K.cylinder(r * 1.04, r * 1.0, h - 0.03, h + 0.008, 8, _lit(Palette.SIGIL_GOLD, 0.9), Vector2(K_GOLD, 0.0), false)
	K.xf = Transform3D.IDENTITY


func _gem_node(o: Vector3, mesh: Mesh, col: Color, y: float, halo_size: float, spin: float) -> Dictionary:
	var node := Node3D.new()
	node.position = o
	root.add_child(node)
	var gem := MeshInstance3D.new()
	gem.mesh = mesh
	gem.material_override = Mats.crystal(col)
	gem.position = Vector3(0, y, 0)
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(gem)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	halo.mesh = q
	halo.material_override = Mats.halo(col, 0.3)
	halo.position = Vector3(0, y, 0)
	halo.scale = Vector3.ONE * halo_size
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(halo)
	spinners.append([gem, spin, 0.04, y])
	return {"node": node, "gem": gem, "halo": halo}


static func crystal_mesh(r: float, up: float, down: float, seg: int) -> ArrayMesh:
	var k := Kit.new()
	k.crystal(r, up, down, seg, Color.WHITE)
	return k.commit()


## Capsule node: gold-ringed pedestal and a floating faceted crystal capsule (owner-coloured).
func _capsule(K: Kit, c: Vector2i, p: Vector3, t: float) -> void:
	var o := p + Vector3(0, t, 0)
	_pedestal(K, o, 0.38, 0.07, true)
	for i in 4:
		var a := PI / 4 + i * PI / 2
		K.xf = Transform3D(Basis(Vector3.UP, -a) * Basis(Vector3(0, 0, 1), -0.35), o + Vector3(cos(a) * 0.34, 0.07, sin(a) * 0.34))
		K.box(Vector3(-0.025, 0, -0.025), Vector3(0.025, 0.2, 0.025), _lit(Palette.SIGIL_GOLD, 0.85), Vector2(K_GOLD, 0))
	K.xf = Transform3D.IDENTITY
	var g := _gem_node(o, crystal_mesh(0.15, 0.36, 0.22, 6), Palette.NEUTRAL, 0.62, 1.0, 0.8)
	g["kind"] = "node"
	gems[c] = g


func _relic(K: Kit, c: Vector2i, p: Vector3, t: float) -> void:
	var o := p + Vector3(0, t, 0)
	_pedestal(K, o, 0.3, 0.07, true)
	K.box(o + Vector3(-0.12, 0.07, -0.12), o + Vector3(0.12, 0.2, 0.12), _lit(theme.stone, 1.1), Vector2(K_STONE, 0.2))
	var g := _gem_node(o, crystal_mesh(0.12, 0.22, 0.12, 4), Palette.SIGIL_GOLD, 0.5, 0.9, 1.2)
	g["kind"] = "relic"
	gems[c] = g


## Warp gate: two leaning obelisks on opposite corners and a glowing floor ring (violet).
func _portal(K: Kit, c: Vector2i, p: Vector3, t: float) -> void:
	var o := p + Vector3(0, t, 0)
	for s in [-1, 1]:
		K.xf = Transform3D(Basis(Vector3(1, 0, -1).normalized(), s * 0.12), o + Vector3(s * 0.38, 0, s * 0.38))
		K.cylinder(0.08, 0.03, 0.0, 0.62, 4, _lit(Color(theme.stone).lerp(Palette.CRYSTAL_VIOLET, 0.2), 1.0), Vector2(K_STONE, 0.3))
	K.xf = Transform3D.IDENTITY
	var node := Node3D.new()
	node.position = o
	root.add_child(node)
	var ring := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	q.orientation = PlaneMesh.FACE_Y
	ring.mesh = q
	ring.material_override = Mats.blob(Palette.CRYSTAL_VIOLET, true)
	ring.position = Vector3(0, 0.03, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(ring)
	var halo := MeshInstance3D.new()
	var hq := QuadMesh.new()
	halo.mesh = hq
	halo.material_override = Mats.halo(Palette.CRYSTAL_VIOLET, 0.35)
	halo.position = Vector3(0, 0.35, 0)
	halo.scale = Vector3.ONE * 1.2
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(halo)
	spinners.append([ring, 0.6, 0.0, 0.03])
	portals[c] = {"node": node, "ring": ring, "halo": halo}


## Sigil monument (Symbol): two-tier rune pedestal, a large floating crystal in the side's colour,
## three orbiting shards.
## The Sigil monument: pedestals + crystal in one node, so the board can glide it when the Sigil
## moves in battle (the grid is edited in place; the island mesh is not rebuilt).
func _sigil(K: Kit, c: Vector2i, p: Vector3, t: float, side: int) -> void:
	var o := p + Vector3(0, t, 0)
	var P := Kit.new()
	_pedestal(P, Vector3.ZERO, 0.46, 0.12, false)
	_pedestal(P, Vector3(0, 0.12, 0), 0.34, 0.12, true)
	var col := Palette.side(side)
	var g := _gem_node(o, crystal_mesh(0.17, 0.5, 0.32, 6), col, 1.0, 1.9, 0.6)
	var ped := MeshInstance3D.new()
	ped.name = "Pedestal"
	ped.mesh = P.commit()
	ped.material_override = _stone_mat
	g.node.add_child(ped)
	for i in 3:
		var shard := MeshInstance3D.new()
		shard.mesh = crystal_mesh(0.045, 0.1, 0.07, 4)
		shard.material_override = Mats.crystal(col)
		var a := TAU * i / 3.0
		shard.position = Vector3(cos(a) * 0.3, 0.0, sin(a) * 0.3)
		g.gem.add_child(shard)
	sigils[side] = g


## Small accent-coloured crystal clusters (crystal tiles, crystal flora), into the glow mesh.
func _shards(G: Kit, c: Vector2i, p: Vector3, t: float, n: int, spread: float) -> void:
	for i in n:
		var a := _h(c, 200 + i) * TAU
		var d := spread * (0.55 + 0.45 * _h(c, 210 + i))
		var tilt := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), 0.25 + 0.3 * _h(c, 220 + i))
		G.xf = Transform3D(tilt, p + Vector3(cos(a) * d, t, sin(a) * d))
		var s := 0.04 + 0.04 * _h(c, 230 + i)
		G.crystal(s, s * 3.5, 0.02, 5, Color.WHITE.lerp(Palette.SOFT_SILVER, 0.3))
	G.xf = Transform3D.IDENTITY


func _bushes(K: Kit, c: Vector2i, p: Vector3, t: float) -> void:
	for i in 2:
		var a := (i + _h(c, 300)) * PI + PI / 4
		var q := p + Vector3(cos(a) * 0.33, t + 0.08, sin(a) * 0.33)
		K.xf = Transform3D(Basis(), q)
		K.ellipsoid(0.13, 0.1, 0.13, _lit(theme.moss, 0.9 + 0.2 * _h(c, 301 + i)), Vector2(K_LEAF, 0), 4, 7)
	K.xf = Transform3D.IDENTITY


func _scatter(grass: Array, c: Vector2i, t: float, density: float, spread: float) -> void:
	var f: float = FLORA_DENSITY.get(theme.flora, 1.0)
	var n := int(density * f + _h(c, 400))
	var p := cell_pos(c)
	for i in n:
		var a := _h(c, 410 + i) * TAU
		var d := spread * sqrt(_h(c, 430 + i)) * 0.95
		var s := 0.11 + 0.11 * _h(c, 450 + i)
		var pos := p + Vector3(cos(a) * d, t, sin(a) * d)
		var col: Color = Color(theme.moss).lerp(Palette.VERDANT_GREEN, 0.15)
		col = _lit(col, 0.75 + 0.5 * _h(c, 470 + i))
		if theme.flora == "grass" and _h(c, 490 + i) < 0.1:
			col = Palette.SOFT_SILVER if _h(c, 495 + i) < 0.6 else Palette.SIGIL_GOLD.lightened(0.2)
			s *= 0.7
		grass.append([Transform3D(Basis(Vector3.UP, _h(c, 500 + i) * TAU).scaled(Vector3(s, s * (0.8 + 0.6 * _h(c, 510 + i)), s)), pos), col])


func _vine_on_face(vines: Array, p: Vector3, side: int, top: float, length: float) -> void:
	var d := DIRS[side]
	var n := Vector3(d.x, 0, d.y)
	var along := Vector3(-n.z, 0, n.x)
	var off := (_h(Vector2i(int(p.x * 10), int(p.z * 10)), side) - 0.5) * 0.6
	var pos := p + n * 0.505 + along * off + Vector3(0, top - 0.02, 0)
	var basis := Basis(along, Vector3.UP, n) * Basis.from_scale(Vector3(0.28, length, 1.0))
	vines.append([Transform3D(basis, pos), _lit(theme.moss, 0.8)])


## Waterfall pouring over the outer edge on `side` of a cell centred at p (half-extent `half`).
func _fall(F: Kit, p: Vector3, side: int, half: float, y_top: float, drop := 5.5) -> void:
	var d := DIRS[side]
	var n := Vector3(d.x, 0, d.y)
	var along := Vector3(-n.z, 0, n.x)
	var e := p + n * (half + 0.03)
	var w := 0.42
	var a := e - along * w + Vector3(0, y_top, 0)
	var b := e + along * w + Vector3(0, y_top, 0)
	var spread := n * 0.6
	F.quad(a + Vector3(0, -drop, 0) + spread, b + Vector3(0, -drop, 0) + spread, b, a, Color.WHITE, Vector2.ZERO,
		PackedColorArray(), PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]))
	# lip: water curling over the edge
	F.quad(a, b, b - n * 0.12 + Vector3(0, 0.0, 0), a - n * 0.12, Color.WHITE, Vector2.ZERO, PackedColorArray(),
		PackedVector2Array([Vector2(0, 0.02), Vector2(1, 0.02), Vector2(1, 0), Vector2(0, 0)]))
	stats.waterfalls = int(stats.get("waterfalls", 0)) + 1


# ---------------------------------------------------------------- rim, underside, distance

## Which border cells are low / broken / carry water, decided before the tiles are built.
func _plan_rim() -> void:
	_rim_top = {}
	_rim_wet = {}
	var n := GameState.SIZE
	for i in range(-1, n + 1):
		for c in [Vector2i(i, -1), Vector2i(i, n), Vector2i(-1, i), Vector2i(n, i)]:
			var broken := _h(c, 600) < 0.22
			_rim_top[c] = (RIM_Y - 0.22 - 0.12 * _h(c, 601)) if broken else (RIM_Y + (_h(c, 602) - 0.5) * 0.06)
	# channels: board water reaching the edge continues through the rim; plus one decorative spill per side
	for y in n:
		for x in n:
			var c := Vector2i(x, y)
			if WET.has(state.tile_type(c)):
				for d in DIRS:
					if _rim_top.has(c + d):
						_rim_wet[c + d] = d
	for s in 4:
		var k := 2 + int(_h(Vector2i(s, 0), 610) * (n - 4))
		var c: Vector2i = [Vector2i(k, -1), Vector2i(n, k), Vector2i(k, n), Vector2i(-1, k)][s]
		if not _rim_wet.has(c):
			_rim_wet[c] = DIRS[s]
	for c in _rim_wet:
		_rim_top[c] = CHANNEL_Y


func _rim_side(c: Vector2i) -> int:
	var n := GameState.SIZE
	if c.y < 0:
		return 0
	if c.x >= n:
		return 1
	if c.y >= n:
		return 2
	return 3


func _rim(K: Kit, W: Kit, F: Kit, grass: Array, vines: Array) -> void:
	var tall: Array = []
	for s in 4:
		tall.append(Kit.new())
	var n := GameState.SIZE
	for c in _rim_top:
		var p := cell_pos(c)
		var t: float = _rim_top[c]
		var bt := []
		for d in DIRS:
			var nc: Vector2i = c + d
			if GameState.in_bounds(nc):
				bt.append(_floor_y(nc))
			elif _rim_top.has(nc):
				bt.append(_rim_top[nc])
			else:
				bt.append(BASE)
		var corner: bool = (c.x < 0 or c.x >= n) and (c.y < 0 or c.y >= n)
		var col := _lit(Color(theme.stone).lerp(theme.cliff, 0.3), 0.85 + 0.2 * _h(c, 620))
		if _rim_wet.has(c):
			_slab(K, p.x - 0.5, p.z - 0.5, p.x + 0.5, p.z + 0.5, CHANNEL_Y, bt, _lit(theme.cliff, 0.8), _side_col(c), Vector2(K_CHANNEL, 0.3), Vector2(K_STONE, 0.7), 0.0)
			W.quad(Vector3(p.x - 0.5, WATER_Y, p.z - 0.5), Vector3(p.x - 0.5, WATER_Y, p.z + 0.5), Vector3(p.x + 0.5, WATER_Y, p.z + 0.5), Vector3(p.x + 0.5, WATER_Y, p.z - 0.5), Color.WHITE)
			var out: Vector2i = _rim_wet[c]
			_fall(F, p, DIRS.find(out), 0.5, WATER_Y, 6.5)
			# channel walls on both sides of the spill
			for sd in [-1, 1]:
				var along: Vector3 = Vector3(-out.y, 0, out.x) * sd
				var q: Vector3 = p + along * 0.44
				var wa: Vector3 = q + Vector3(-0.07, CHANNEL_Y, -0.07) - Vector3(out.x, 0, out.y) * 0.4
				var wb: Vector3 = q + Vector3(0.07, RIM_Y + 0.08, 0.07) + Vector3(out.x, 0, out.y) * 0.4
				K.box(wa.min(wb) * Vector3(1, 0, 1) + Vector3(0, CHANNEL_Y, 0), wa.max(wb) * Vector3(1, 0, 1) + Vector3(0, RIM_Y + 0.08, 0), col, Vector2(K_STONE, 0.8))
			continue
		_slab(K, p.x - 0.5, p.z - 0.5, p.x + 0.5, p.z + 0.5, t, bt, col, _side_col(c), Vector2(K_STONE, 0.95), Vector2(K_ROCK, 0.7), 0.05)
		_scatter(grass, c, t, 4.0, 0.46)
		for i in 4:
			if bt[i] <= BASE + 0.01 and _h(c, 630 + i) < 0.55:
				_vine_on_face(vines, p, i, t, 0.5 + 0.9 * _h(c, 640 + i))
		if _h(c, 650) < 0.35:
			_rubble(K, p + Vector3(0, t, 0), 3, col, c)
		var T: Kit = tall[_rim_side(c)]
		var o := p + Vector3(0, t, 0)
		var out_dir := _rim_out(c)
		if corner:
			_column(T, o, 2.2 + 0.8 * _h(c, 665), _h(c, 666) < 0.35, col, Vector2(K_STONE, 0.9), _h(c, 667))
			continue
		# broken back wall along the outer edge of the rim (far sides only: it lives in the tall mesh)
		var wall_h := 0.25 + 0.75 * _h(c, 668) * _h(c, 669)
		var along := Vector3(absf(out_dir.z), 0, absf(out_dir.x))
		var wq := o + out_dir * 0.36
		T.box(wq - along * 0.5 - Vector3(0.11, 0, 0.11) * (Vector3.ONE - along), wq + along * 0.5 + Vector3(0.11, wall_h, 0.11) * (Vector3.ONE - along) + Vector3(0, wall_h, 0) * along, col.darkened(0.08), Vector2(K_STONE, 0.95))
		var roll := _h(c, 660)
		var mid := GameState.SIZE / 2
		if (c.x == mid or c.y == mid) and not corner:
			_grand_arch(T, o, along, col)
			continue
		if theme.trees and roll < 0.3:
			_tree(T, o, c)
		elif roll < 0.55:
			_column(T, o, 1.4 + 1.1 * _h(c, 661), _h(c, 662) < 0.5, col, Vector2(K_STONE, 0.9), _h(c, 663))
		elif roll < 0.72:
			var hh := 0.9 + 0.8 * _h(c, 664)
			var along_x: bool = c.y < 0 or c.y >= n
			var a := Vector3(0.36, 0, 0) if along_x else Vector3(0, 0, 0.36)
			for sd in [-1, 1]:
				T.box(o + a * sd + Vector3(-0.12, 0, -0.12), o + a * sd + Vector3(0.12, hh, 0.12), col, Vector2(K_STONE, 0.9))
			var lo := o - a - Vector3(0.14, 0, 0.14) + Vector3(0, hh, 0)
			var hi := o + a + Vector3(0.14, 0.16, 0.14) + Vector3(0, hh, 0)
			T.box(lo, hi, col.lightened(0.06), Vector2(K_STONE, 0.9))
	for s in 4:
		var k: Kit = tall[s]
		if k.vertex_count() > 0:
			rim_tall[s] = _add_mesh(k, _stone_mat, "RimTall%d" % s, true)
	stats.decor["rim_cells"] = _rim_top.size()


## Outward unit vector of a rim cell (toward the sky).
func _rim_out(c: Vector2i) -> Vector3:
	var n := GameState.SIZE
	var v := Vector3(-1 if c.x < 0 else (1 if c.x >= n else 0), 0, -1 if c.y < 0 else (1 if c.y >= n else 0))
	return v.normalized()


## A tall ruined gateway spanning the rim cell: two pillars and a stepped arch (far-side landmark).
func _grand_arch(T: Kit, o: Vector3, along: Vector3, col: Color) -> void:
	var hh := 2.1
	var uv := Vector2(K_STONE, 0.9)
	for sd in [-1.0, 1.0]:
		var q: Vector3 = o + along * 0.62 * sd
		T.box(q - Vector3(0.17, 0, 0.17), q + Vector3(0.17, hh, 0.17), col, uv)
		T.box(q - Vector3(0.22, 0, 0.22), q + Vector3(0.22, 0.16, 0.22), col.darkened(0.1), uv)
		T.box(q - Vector3(0.21, -hh, 0.21), q + Vector3(0.21, hh + 0.1, 0.21), col.lightened(0.08), uv)
	var seg := 9
	for i in seg:
		var a0 := PI * (i + 0.5) / seg
		var q: Vector3 = o + along * (-cos(a0) * 0.62) + Vector3(0, hh + 0.1 + sin(a0) * 0.62, 0)
		var w := along * 0.13 + Vector3(0.14, 0.11, 0.14) * (Vector3.ONE - along)
		T.box(q - w - Vector3(0, 0.0, 0), q + w, col.lightened(0.04), uv)
	T.box(o + Vector3(0, hh + 0.72, 0) - along * 0.12 - Vector3(0.12, 0, 0.12) * (Vector3.ONE - along), o + Vector3(0, hh + 0.98, 0) + along * 0.12 + Vector3(0.12, 0, 0.12) * (Vector3.ONE - along), _lit(Palette.SIGIL_GOLD, 0.8), Vector2(K_GOLD, 0))
	_count("grand_arch")


func _tree(T: Kit, o: Vector3, c: Vector2i) -> void:
	var h := 0.9 + 0.7 * _h(c, 670)
	var bark := _lit(Palette.SIGIL_GOLD.lerp(Palette.MIDNIGHT_NAVY, 0.62), 1.0)
	T.xf = Transform3D(Basis(Vector3(1, 0, 1).normalized(), (_h(c, 671) - 0.5) * 0.3), o)
	T.cylinder(0.09, 0.05, 0.0, h, 6, bark, Vector2(K_WOOD, 0.0))
	T.xf = Transform3D.IDENTITY
	var leaf: Color = theme.moss
	for i in 3:
		var q := o + Vector3((_h(c, 672 + i) - 0.5) * 0.3, h + i * 0.12 - 0.1, (_h(c, 675 + i) - 0.5) * 0.3)
		T.xf = Transform3D(Basis(), q)
		T.ellipsoid(0.32 - i * 0.06, 0.24 - i * 0.03, 0.32 - i * 0.06, _lit(leaf, 0.85 + 0.15 * i), Vector2(K_LEAF, 0.0), 5, 8)
	T.xf = Transform3D.IDENTITY


## The rock root under the island: rings shrinking from the rim's square outline to a jagged tip,
## with hanging stalactites and vines. Colours fade toward the sky haze with depth.
func _underside(K: Kit, vines: Array) -> void:
	var per := 14
	var outline: Array[Vector3] = []
	for s in 4:
		for i in per:
			var f := -1.0 + 2.0 * i / per
			var q: Vector3 = [Vector3(f, 0, -1), Vector3(1, 0, f), Vector3(-f, 0, 1), Vector3(-1, 0, -f)][s]
			outline.append(q * ISLAND_R)
	var profile := [[1.0, BASE], [0.985, BASE - 0.75], [0.9, -1.75], [0.77, -2.75], [0.6, -3.8], [0.43, -4.9], [0.27, -6.0], [0.13, -7.1], [0.0, -8.3]]
	var rings: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = _salt
	for k in profile.size():
		var ring: Array[Vector3] = []
		var sc: float = profile[k][0]
		for i in outline.size():
			var q: Vector3 = outline[i]
			var rnd := q.normalized() * ISLAND_R
			var shape := q.lerp(rnd, clampf(k / 3.0, 0.0, 1.0))
			var jit := 1.0 if k == 0 else 1.0 + (rng.randf() - 0.5) * 0.16
			var y: float = profile[k][1] + (0.0 if k == 0 else (rng.randf() - 0.5) * 0.4)
			ring.append(Vector3(shape.x * sc * jit, y, shape.z * sc * jit))
		rings.append(ring)
	var top_col := _lit(theme.cliff, 0.9)
	for k in rings.size() - 1:
		var c0 := _lit(top_col, 1.0 - k * 0.07)
		var c1 := _lit(top_col, 1.0 - (k + 1) * 0.07)
		var r0: Array = rings[k]
		var r1: Array = rings[k + 1]
		for i in r0.size():
			var j := (i + 1) % r0.size()
			var a: Vector3 = r0[i]
			var b: Vector3 = r0[j]
			var cc: Vector3 = r1[j]
			var d: Vector3 = r1[i]
			var outward := Vector3((a.x + b.x) * 0.5, 0, (a.z + b.z) * 0.5).normalized()
			if (b - a).cross(cc - a).dot(outward) >= 0.0:
				K.quad(d, cc, b, a, c0, Vector2(K_ROCK, 0.35 if k < 2 else 0.0), PackedColorArray([c1, c1, c0, c0]))
			else:
				K.quad(a, b, cc, d, c0, Vector2(K_ROCK, 0.35 if k < 2 else 0.0), PackedColorArray([c0, c0, c1, c1]))
	# stalactites
	for i in 16:
		var k := 2 + rng.randi_range(0, 4)
		var r: Array = rings[k]
		var q: Vector3 = r[rng.randi_range(0, r.size() - 1)] * 0.93
		K.xf = Transform3D(Basis(Vector3(1, 0, 0), PI), q)
		K.cylinder(0.25 + rng.randf() * 0.35, 0.0, 0.0, 0.8 + rng.randf() * 1.8, 5, _lit(top_col, 0.62), Vector2(K_ROCK, 0.0), false)
	K.xf = Transform3D.IDENTITY
	stats.decor["underside_rings"] = rings.size()


## A few small floating islets far off, pre-hazed (aerial perspective) for depth.
func _distant(K: Kit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _salt + 99
	for i in 6:
		var a := TAU * (i + rng.randf() * 0.6) / 6.0
		var dist := 14.0 + rng.randf() * 7.0
		var o := Vector3(cos(a) * dist, -2.5 + rng.randf() * 4.0, sin(a) * dist)
		var r := 0.7 + rng.randf() * 0.9
		var fade := clampf((dist - 10.0) / 16.0, 0.2, 0.5)
		var top := Color(theme.stone).lerp(haze, fade)
		var rock := Color(theme.cliff).lerp(haze, fade)
		K.xf = Transform3D(Basis(), o)
		K.cylinder(r, r * 0.95, -0.3, 0.0, 8, rock, Vector2(K_ROCK, 0.0), true, top)
		K.xf = Transform3D(Basis(Vector3(1, 0, 0), PI), o + Vector3(0, -0.3, 0))
		K.cylinder(r * 0.95, 0.0, 0.0, 1.6 + rng.randf() * 2.2, 7, rock.darkened(0.1), Vector2(K_ROCK, 0.0), false)
		K.xf = Transform3D.IDENTITY
		for j in rng.randi_range(1, 3):
			var q := o + Vector3((rng.randf() - 0.5) * r, 0, (rng.randf() - 0.5) * r)
			_column(K, q, 0.8 + rng.randf() * 1.4, rng.randf() < 0.4, top, Vector2(K_STONE, 0.5), rng.randf())


func _add_foliage(grass: Array, vines: Array) -> void:
	var tuft := Kit.new()
	for k in 2:
		var a := k * PI / 2 + 0.3
		var u := Vector3(cos(a), 0, sin(a)) * 0.5
		tuft.quad(-u, u, u + Vector3.UP, -u + Vector3.UP, Color.WHITE)
	var tuft_mesh := tuft.commit()
	var vine := Kit.new()
	vine.quad(Vector3(-0.5, -1, 0), Vector3(0.5, -1, 0), Vector3(0.5, 0, 0), Vector3(-0.5, 0, 0), Color.WHITE)
	var vine_mesh := vine.commit()
	var tex := Mats.grass_texture()
	_multimesh(tuft_mesh, grass, Mats.foliage(tex, false, 0.06), "Grass")
	_multimesh(vine_mesh, vines, Mats.foliage(Mats.vine_texture(), true, 0.03), "Vines")


func _multimesh(mesh: Mesh, items: Array, mat: Material, name: String) -> void:
	if items.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, items[i][1])
	var mi := MultiMeshInstance3D.new()
	mi.name = name
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Two cloud layers below the island.
func _add_clouds() -> void:
	var layers := [[-3.4, 70.0, 0.42, 0.75, 0.012, 0.09], [-6.8, 110.0, 0.55, 0.95, 0.008, 0.06]]
	for l in layers:
		var mi := MeshInstance3D.new()
		var q := PlaneMesh.new()
		q.size = Vector2(l[1], l[1])
		mi.mesh = q
		mi.position = Vector3(0, l[0], 0)
		mi.material_override = Mats.cloud(Palette.SOFT_SILVER.lerp(Color.WHITE, 0.6), haze.lerp(Palette.MIDNIGHT_NAVY, 0.25), l[2], l[3], l[4], l[5])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


## Per-frame idle animation of gems and portal rings (called by the board).
func animate(t: float) -> void:
	for s in spinners:
		var n: Node3D = s[0]
		if not is_instance_valid(n):
			continue
		n.rotation.y = t * float(s[1])
		n.position.y = float(s[3]) + sin(t * 1.7 + n.get_instance_id() % 7) * float(s[2])
