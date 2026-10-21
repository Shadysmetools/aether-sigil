## Tiny procedural mesh builder for the 3D board: packed arrays in, one ArrayMesh surface out.
## Every primitive takes a Transform3D, a vertex colour and a UV2 "material hint" (read by the
## shaders: x = surface kind, y = moss / emission strength). Faces are given counter-clockwise as
## seen from outside and emitted in Godot's clockwise front-face order. Keeps its own vertex count
## so headless tests can check what was built (the dummy renderer returns empty mesh arrays).
extends RefCounted

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var xf := Transform3D.IDENTITY   ## applied to everything added (push a transform, add, reset)


func vertex_count() -> int:
	return verts.size()


func _v(p: Vector3, n: Vector3, c: Color, uv: Vector2, uv2: Vector2) -> void:
	verts.append(xf * p)
	normals.append((xf.basis * n).normalized())
	colors.append(c)
	uvs.append(uv)
	uv2s.append(uv2)


## Triangle a,b,c counter-clockwise from the front; flat normal.
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, uv2 := Vector2.ZERO) -> void:
	var n := (b - a).cross(c - a).normalized()
	_v(a, n, col, Vector2(a.x + a.z, a.y), uv2)
	_v(c, n, col, Vector2(c.x + c.z, c.y), uv2)
	_v(b, n, col, Vector2(b.x + b.z, b.y), uv2)


## Quad a,b,c,d counter-clockwise from the front; flat normal. Optional per-corner colours.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, uv2 := Vector2.ZERO, cols: PackedColorArray = PackedColorArray(), quv := PackedVector2Array()) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n == Vector3.ZERO:
		n = (c - a).cross(d - a).normalized()
	var cs := cols if cols.size() == 4 else PackedColorArray([col, col, col, col])
	var us := quv if quv.size() == 4 else PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	for i in [0, 2, 1, 0, 3, 2]:
		var p: Vector3 = [a, b, c, d][i]
		_v(p, n, cs[i], us[i], uv2)


## Axis-aligned box (before xf) from min corner to max corner. bottom=false skips the underside.
func box(lo: Vector3, hi: Vector3, col: Color, uv2 := Vector2.ZERO, bottom := false, side_col: Variant = null) -> void:
	var sc: Color = col if side_col == null else side_col
	var p := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	quad(p[4], p[7], p[6], p[5], col, uv2)          # top (+y)
	quad(p[1], p[0], p[4], p[5], sc, uv2)          # -z
	quad(p[2], p[1], p[5], p[6], sc, uv2)          # +x
	quad(p[3], p[2], p[6], p[7], sc, uv2)          # +z
	quad(p[0], p[3], p[7], p[4], sc, uv2)          # -x
	if bottom:
		quad(p[0], p[1], p[2], p[3], sc, uv2)


## Cylinder / cone / frustum along +y from y0 to y1, `seg` sides, flat-shaded sides.
func cylinder(r0: float, r1: float, y0: float, y1: float, seg: int, col: Color, uv2 := Vector2.ZERO, caps := true, top_col: Variant = null) -> void:
	var tc: Color = col if top_col == null else top_col
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var b0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var b1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var t0 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var t1 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		if r1 > 0.0001:
			quad(b1, b0, t0, t1, col, uv2)
		else:
			tri(b1, b0, t0, col, uv2)
		if caps:
			if r1 > 0.0001:
				tri(Vector3(0, y1, 0), t1, t0, tc, uv2)
			tri(Vector3(0, y0, 0), b0, b1, col, uv2)


## Faceted crystal: a `seg`-sided bipyramid (radius r, tip heights above/below the middle ring).
func crystal(r: float, up: float, down: float, seg: int, col: Color, uv2 := Vector2.ZERO, twist := 0.0) -> void:
	for i in seg:
		var a0 := TAU * i / seg + twist
		var a1 := TAU * (i + 1) / seg + twist
		var m0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var m1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		tri(m1, m0, Vector3(0, up, 0), col, uv2)
		tri(m0, m1, Vector3(0, -down, 0), col.darkened(0.25), uv2)


## Smooth ellipsoid centred at the origin (radii rx, ry, rz) — creature bodies.
func ellipsoid(rx: float, ry: float, rz: float, col: Color, uv2 := Vector2.ZERO, rings := 7, seg := 10, belly: Variant = null) -> void:
	var bc: Color = col if belly == null else belly
	var pts := []
	for r in rings + 1:
		var row := []
		var v := PI * r / rings
		for s in seg + 1:
			var u := TAU * s / seg
			row.append(Vector3(sin(v) * cos(u), cos(v), sin(v) * sin(u)))
		pts.append(row)
	var sc := Vector3(rx, ry, rz)
	for r in rings:
		for s in seg:
			var q := [pts[r][s], pts[r][s + 1], pts[r + 1][s + 1], pts[r + 1][s]]
			for i in [0, 2, 1, 0, 3, 2]:
				var n: Vector3 = q[i]
				var c := bc if n.y < -0.35 else col
				_v(n * sc, (n / sc).normalized(), c, Vector2(float(s) / seg, float(r) / rings), uv2)


func commit(mesh: ArrayMesh = null) -> ArrayMesh:
	var m := mesh if mesh != null else ArrayMesh.new()
	if verts.is_empty():
		return m
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2s
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
