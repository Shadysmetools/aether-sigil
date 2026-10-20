## Pure hex math for a pointy-top axial grid. No rendering, no game rules.
## Coordinates are Vector2i(q, r); the implicit cube coord is s = -q - r.
extends RefCounted

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


static func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRECTIONS:
		out.append(c + d)
	return out


static func in_board(c: Vector2i, radius: int) -> bool:
	return distance(c, Vector2i.ZERO) <= radius


## Every tile within `radius` of the origin (radius 3 -> 37 tiles).
static func all_tiles(radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(maxi(-radius, -q - radius), mini(radius, -q + radius) + 1):
			out.append(Vector2i(q, r))
	return out


static func to_pixel(c: Vector2i, size: float) -> Vector2:
	var x := size * sqrt(3.0) * (c.x + c.y / 2.0)
	var y := size * 1.5 * c.y
	return Vector2(x, y)


static func from_pixel(p: Vector2, size: float) -> Vector2i:
	var q := (sqrt(3.0) / 3.0 * p.x - p.y / 3.0) / size
	var r := (2.0 / 3.0 * p.y) / size
	return cube_round(q, r)


static func cube_round(fq: float, fr: float) -> Vector2i:
	var fs := -fq - fr
	var q := roundi(fq)
	var r := roundi(fr)
	var s := roundi(fs)
	var dq := absf(q - fq)
	var dr := absf(r - fr)
	var ds := absf(s - fs)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(q, r)


## Corner points of a pointy-top hex centred at the origin.
static func corners(size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var ang := deg_to_rad(60.0 * i - 30.0)
		pts.append(Vector2(size * cos(ang), size * sin(ang)))
	return pts
