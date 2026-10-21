## Isometric projection + draw order for a GameState. Reads state only; never changes rules.
## Textures come from assets.gd (painted art -> generated placeholders); anything without a texture
## falls back to the procedural shapes in board_art.gd. Node origin = centre of the board's ground plane.
extends Node2D

const GameState = preload("res://scripts/game_state.gd")
const Art = preload("res://scripts/board_art.gd")
const Palette = preload("res://scripts/theme_colors.gd")
const Data = preload("res://scripts/data_loader.gd")
const Assets = preload("res://scripts/assets.gd")

const TILE_W := 84.0
const TILE_H := 42.0
const NO_WALK := ["obstacle", "water", "lava", "sky", "space", "rift"]

var state: GameState
var highlights: Dictionary = {}   ## Vector2i -> Color
var selected: Variant = null      ## Vector2i or null
var use_textures := true          ## false = the old all-procedural board (tests, comparison)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## Ground-plane centre of tile c, in local coordinates. The board is viewed from the player's
## corner: player tiles (small x, y) are nearest the camera (bottom of the screen).
func tile_center(c: Vector2i) -> Vector2:
	var half := (GameState.SIZE - 1) / 2.0
	var x := half - float(c.x)
	var y := half - float(c.y)
	return Vector2((x - y) * TILE_W / 2.0, (x + y) * TILE_H / 2.0)


func raise_px(c: Vector2i) -> float:
	if state == null:
		return 0.0
	return float(state.tile_def(c).get("raise", 0.0)) * TILE_H


## Centre of the tile's top face (where tokens stand).
func top_center(c: Vector2i) -> Vector2:
	return tile_center(c) - Vector2(0, maxf(raise_px(c), 4.0))


## Tile under a local point (inverse of the ground-plane projection), or null if off-board.
func tile_at_local(p: Vector2) -> Variant:
	var half := (GameState.SIZE - 1) / 2.0
	var a := p.x / (TILE_W / 2.0)
	var b := p.y / (TILE_H / 2.0)
	var c := Vector2i(roundi(half - (a + b) / 2.0), roundi(half - (b - a) / 2.0))
	return c if GameState.in_bounds(c) else null


func board_size() -> Vector2:
	return Vector2(GameState.SIZE * TILE_W, GameState.SIZE * TILE_H + TILE_H * 2.0)


## Bible tower id of the current stage ("01"), or "" before a stage is set up.
func tower_id() -> String:
	if state == null or state.stage.is_empty():
		return ""
	return str(state.stage.get("tower_id", ""))


## Texture name for the tile at c: ground variants and bridge direction are picked here.
func tile_art_name(c: Vector2i) -> String:
	var type := state.tile_type(c)
	if type == "ground":
		return ["ground", "ground_v2", "ground_v3"][(c.x * 7 + c.y * 13) % 3]
	if type == "bridge":
		var along := func(d: Vector2i) -> int:
			var s := 0
			for n in [c + d, c - d]:
				if GameState.in_bounds(n):
					var t := state.tile_type(n)
					s += 2 if t == "bridge" else (1 if not NO_WALK.has(t) else 0)
			return s
		return "bridge" if along.call(Vector2i(1, 0)) >= along.call(Vector2i(0, 1)) else "bridge_y"
	return type


func _draw() -> void:
	if state == null or state.grid.is_empty():
		return
	Art.draw_island_underside(self, _corners(), tower_id(), _waterfalls())
	# Painter's order: back (large x+y, the enemy corner) to front.
	for sum in range(2 * GameState.SIZE - 2, -1, -1):
		for x in range(0, GameState.SIZE):
			var y := sum - x
			if y < 0 or y >= GameState.SIZE:
				continue
			_draw_tile(Vector2i(x, y))


## Water tiles on the two front edges spill off the island: [edge point, width] per waterfall.
func _waterfalls() -> Array:
	var out := []
	for i in GameState.SIZE:
		for c in [Vector2i(i, 0)] + ([Vector2i(0, i)] if i > 0 else []):
			if state.tile_type(c) == "water":
				var d := Vector2(-TILE_W / 4, TILE_H / 4) if c.y == 0 and c.x != 0 else Vector2(TILE_W / 4, TILE_H / 4)
				out.append([tile_center(c) + d + Vector2(0, 30), TILE_W * 0.4])
	return out


## Outer corners of the board's ground diamond: top, right, bottom, left.
func _corners() -> PackedVector2Array:
	var n := GameState.SIZE - 1
	return PackedVector2Array([
		tile_center(Vector2i(n, n)) - Vector2(0, TILE_H / 2),
		tile_center(Vector2i(0, n)) + Vector2(TILE_W / 2, 0),
		tile_center(Vector2i(0, 0)) + Vector2(0, TILE_H / 2),
		tile_center(Vector2i(n, 0)) - Vector2(TILE_W / 2, 0)])


func _draw_tile(c: Vector2i) -> void:
	var type := state.tile_type(c)
	var tid := tower_id()
	var tex: Texture2D = Assets.tile(tid, tile_art_name(c)) if use_textures else null
	var top: Vector2
	if tex != null:
		Art.draw_tile_texture(self, tex, tile_center(c), TILE_W)
		top = top_center(c)
	else:
		top = Art.draw_block(self, tile_center(c), TILE_W, TILE_H, Palette.tile(type), raise_px(c))
		Art.draw_terrain_mark(self, top, TILE_W, TILE_H, type)
	if highlights.has(c):
		Art.draw_highlight(self, top, TILE_W, TILE_H, highlights[c])
	if selected != null and selected == c:
		Art.draw_highlight(self, top, TILE_W, TILE_H, Palette.SIGIL_GOLD)
	if state.nodes.has(c):
		var p := Assets.prop("capsule_node", tid) if use_textures else null
		if p != null:
			Art.draw_owner_glow(self, top, TILE_W, TILE_H, state.nodes[c])
			Art.draw_prop(self, p, top, TILE_W * 0.72)
		else:
			Art.draw_capsule_node(self, top, TILE_W, TILE_H, state.nodes[c])
	if state.relics.has(c):
		var p := Assets.prop("relic", tid) if use_textures else null
		if p != null:
			Art.draw_owner_glow(self, top, TILE_W, TILE_H, state.relics[c])
			Art.draw_prop(self, p, top, TILE_W * 0.62)
		else:
			Art.draw_relic(self, top, TILE_W, TILE_H, state.relics[c])
	if state.portals.has(c):
		var p := Assets.prop("portal", tid) if use_textures else null
		if p != null:
			Art.draw_prop(self, p, top, TILE_W * 0.72, Color.WHITE if c == state.active_portal else Color(0.6, 0.6, 0.7))
		else:
			Art.draw_portal(self, top, TILE_W, TILE_H, c == state.active_portal)
	var sym := state.symbol_owner_at(c)
	if sym != GameState.NONE:
		var p := Assets.prop("player_sigil" if sym == GameState.PLAYER else "enemy_sigil", tid) if use_textures else null
		if p != null:
			Art.draw_owner_glow(self, top, TILE_W, TILE_H, sym)
			var head := Art.draw_prop(self, p, top, TILE_W * 0.95)
			Art.hp_bar(self, head + Vector2(0, -8), TILE_W * 0.7, state.symbol_hp[sym], state.symbol_max, Palette.side(sym))
		else:
			Art.draw_symbol(self, top, TILE_W, TILE_H, sym, state.symbol_hp[sym], state.symbol_max)
	var u := state.unit_at(c)
	if u != null:
		var spent: bool = u.moved and u.attacked
		if use_textures:
			Art.draw_monster(self, top, TILE_W, TILE_H, u, spent)
		else:
			Art.draw_unit(self, top, TILE_W, TILE_H, u.owner, u.family, u.element, u.hp, u.max_hp, spent, u.dormant)
