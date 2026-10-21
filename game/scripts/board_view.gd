## Isometric projection + draw order for a GameState. Reads state only; never changes rules.
## All shapes are delegated to board_art.gd, so real sprites or a 3D board can replace it.
## Node origin = centre of the board's ground plane.
extends Node2D

const GameState = preload("res://scripts/game_state.gd")
const Art = preload("res://scripts/board_art.gd")
const Palette = preload("res://scripts/theme_colors.gd")
const Data = preload("res://scripts/data_loader.gd")

const TILE_W := 84.0
const TILE_H := 42.0

var state: GameState
var highlights: Dictionary = {}   ## Vector2i -> Color
var selected: Variant = null      ## Vector2i or null


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


func _draw() -> void:
	if state == null or state.grid.is_empty():
		return
	# Painter's order: back (large x+y, the enemy corner) to front.
	for sum in range(2 * GameState.SIZE - 2, -1, -1):
		for x in range(0, GameState.SIZE):
			var y := sum - x
			if y < 0 or y >= GameState.SIZE:
				continue
			_draw_tile(Vector2i(x, y))


func _draw_tile(c: Vector2i) -> void:
	var type := state.tile_type(c)
	var top := Art.draw_block(self, tile_center(c), TILE_W, TILE_H, Palette.tile(type), raise_px(c))
	Art.draw_terrain_mark(self, top, TILE_W, TILE_H, type)
	if highlights.has(c):
		Art.draw_highlight(self, top, TILE_W, TILE_H, highlights[c])
	if selected != null and selected == c:
		Art.draw_highlight(self, top, TILE_W, TILE_H, Palette.SOFT_SILVER)
	if state.nodes.has(c):
		Art.draw_capsule_node(self, top, TILE_W, TILE_H, state.nodes[c])
	if state.relics.has(c):
		Art.draw_relic(self, top, TILE_W, TILE_H, state.relics[c])
	if state.portals.has(c):
		Art.draw_portal(self, top, TILE_W, TILE_H, c == state.active_portal)
	var sym := state.symbol_owner_at(c)
	if sym != GameState.NONE:
		Art.draw_symbol(self, top, TILE_W, TILE_H, sym, state.symbol_hp[sym], state.symbol_max)
	var u := state.unit_at(c)
	if u != null:
		var spent: bool = u.moved and u.attacked
		Art.draw_unit(self, top, TILE_W, TILE_H, u.owner, u.family, u.element, u.hp, u.max_hp, spent, u.dormant)
