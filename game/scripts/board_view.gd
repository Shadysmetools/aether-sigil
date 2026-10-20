## Renders a GameState. Reads state only; never changes rules.
extends Node2D

const HexGrid = preload("res://scripts/hex_grid.gd")
const GameState = preload("res://scripts/game_state.gd")
const PieceArt = preload("res://scripts/piece_art.gd")

var state: GameState
var hex_size: float = 80.0
var highlights: Dictionary = {}   ## Vector2i -> Color
var selected: Variant = null      ## Vector2i or null


func tile_center(c: Vector2i) -> Vector2:
	return HexGrid.to_pixel(c, hex_size)


## Tile under a point in this node's local space, or null if off-board.
func tile_at_local(p: Vector2) -> Variant:
	var c := HexGrid.from_pixel(p, hex_size)
	return c if HexGrid.in_board(c, GameState.RADIUS) else null


func _draw() -> void:
	if state == null:
		return
	for c in state.tiles:
		PieceArt.draw_tile(self, tile_center(c), hex_size, state.light_owner(c))
	for b in state.beacons:
		PieceArt.draw_beacon(self, tile_center(b), hex_size, state.beacons[b])
	for c in state.posts:
		PieceArt.draw_post(self, tile_center(c), hex_size, state.posts[c])
	for p in 2:
		PieceArt.draw_hearth(self, tile_center(GameState.HEARTH_TILES[p]), hex_size, p, state.hearth_hp[p])
	for c in highlights:
		PieceArt.draw_highlight(self, tile_center(c), hex_size, highlights[c])
	if selected != null:
		PieceArt.draw_highlight(self, tile_center(selected), hex_size, Color.WHITE)
	for u in state.units:
		var exhausted: bool = u.owner == state.current and u.moved and u.attacked
		PieceArt.draw_wick(self, tile_center(u.pos), hex_size, u.owner, u.element, u.name, u.hp, exhausted)
