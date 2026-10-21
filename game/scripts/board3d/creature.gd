## Procedural 3D creatures for monsters that have no painted cut-out yet. A body plan is picked from
## the monster's NAME (stag, wyrm, phoenix, beetle, golem, sprite...; first keyword wins), falling
## back to its role; the element family sets the colours and the team sets the glowing eye colour.
## Built from a handful of primitives into one ArrayMesh per (plan, variant, family, team), cached.
## Front = +x, up = +y, feet at y = 0; about 0.6-0.9 tiles tall.
extends RefCounted

const Kit = preload("res://scripts/board3d/mesh_kit.gd")
const Palette = preload("res://scripts/theme_colors.gd")

## [keyword, plan, variant] in priority order (order matters: "griffin" before "fin", "hound" before "horn").
const KEYWORDS := [
	["phoenix", "bird", "crest"], ["quill", "bird", "crest"], ["owl", "bird", "owl"], ["rayen", "bird", "crest"],
	["raven", "bird", "crest"], ["bat", "bird", "bat"], ["griffin", "beast", "griffin"], ["monarch", "bug", "moth"],
	["moth", "bug", "moth"], ["drake", "drake", "wings"], ["wyrm", "drake", "wyrm"], ["serpent", "drake", "wyrm"],
	["hydra", "drake", "wyrm"], ["saur", "drake", "saur"], ["golem", "golem", ""], ["colossus", "golem", "big"],
	["titan", "golem", "big"], ["beetle", "bug", "beetle"], ["mantis", "bug", "mantis"], ["scorpion", "bug", "scorpion"],
	["crab", "bug", "crab"], ["weaver", "bug", "spider"], ["hopper", "hopper", ""], ["bun", "hopper", ""],
	["hound", "beast", "mane"], ["stag", "beast", "antlers"], ["horn", "beast", "horns"], ["ram", "beast", "horns"],
	["tusk", "beast", "tusks"], ["wolf", "beast", "mane"], ["fang", "beast", "mane"], ["fox", "beast", "fox"],
	["lynx", "beast", "fox"], ["panther", "beast", "cat"], ["tiger", "beast", "cat"], ["lion", "beast", "mane"],
	["fin", "floater", "fish"], ["skimmer", "floater", "fish"], ["sprite", "floater", "sprite"], ["wisp", "floater", "sprite"],
	["imp", "floater", "sprite"], ["orb", "floater", "orb"], ["ray", "floater", "ray"], ["shard", "floater", "shard"],
]
const ROLE_PLAN := {"Guardian": ["golem", ""], "Striker": ["drake", "wings"], "Assassin": ["beast", "cat"],
	"Scout": ["beast", "antlers"], "Support": ["hopper", ""], "Controller": ["bug", "beetle"],
	"Artillery": ["floater", "orb"], "Summoner": ["bird", "crest"]}
const PLANS := ["beast", "drake", "bird", "golem", "bug", "floater", "hopper"]

static var _cache: Dictionary = {}

var k: Kit
var main: Color
var sec: Color
var acc: Color
var dark: Color
var eye: Color
var glow: Color


## [plan, variant] for a monster name / role.
static func plan_for(name: String, role: String) -> Array:
	var n := name.to_lower()
	for kw in KEYWORDS:
		if n.contains(kw[0]):
			return [kw[1], kw[2]]
	return ROLE_PLAN.get(role, ["beast", "mane"])


## {mesh, height, hover} for a plan/variant in an element family, eyes in the team colour.
static func build(plan: String, variant: String, family: String, team: int) -> Dictionary:
	var key := "%s|%s|%s|%d" % [plan, variant, family, team]
	if not _cache.has(key):
		var c = load("res://scripts/board3d/creature.gd").new()
		_cache[key] = c._make(plan, variant, family, team)
	return _cache[key]


func _make(plan: String, variant: String, family: String, team: int) -> Dictionary:
	k = Kit.new()
	var fc := Palette.family(family)
	main = fc
	if main.get_luminance() < 0.25:
		main = main.lightened(0.2)
	sec = fc.lerp(Palette.SOFT_SILVER, 0.55)
	acc = Palette.SIGIL_GOLD.lerp(fc, 0.15)
	dark = Palette.MIDNIGHT_NAVY.lerp(fc, 0.35)
	eye = Palette.side(team).lerp(Color.WHITE, 0.25)
	glow = fc.lerp(Color.WHITE, 0.3)
	var height := 0.7
	var hover := 0.0
	match plan:
		"beast": height = _beast(variant)
		"drake": height = _drake(variant)
		"bird": height = _bird(variant)
		"golem": height = _golem(variant)
		"bug": height = _bug(variant)
		"floater":
			height = _floater(variant)
			hover = 0.2
		"hopper": height = _hopper()
		_: height = _beast("mane")
	return {"mesh": k.commit(), "height": height, "hover": hover, "verts": k.vertex_count()}


# ---------------------------------------------------------------- primitives

static func _basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3(0, 0, 1) if absf(y.z) < 0.9 else Vector3(1, 0, 0)
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _ell(pos: Vector3, r: Vector3, col: Color, emit := 0.0, rot := Basis(), belly: Variant = null, rings := 6, seg := 10) -> void:
	k.xf = Transform3D(rot, pos)
	k.ellipsoid(r.x, r.y, r.z, col, Vector2(0, emit), rings, seg, belly)
	k.xf = Transform3D.IDENTITY


func _limb(a: Vector3, b: Vector3, r0: float, r1: float, col: Color, emit := 0.0, seg := 6) -> void:
	k.xf = Transform3D(_basis_y(b - a), a)
	k.cylinder(r0, r1, 0.0, (b - a).length(), seg, col, Vector2(0, emit))
	k.xf = Transform3D.IDENTITY


func _cone(base: Vector3, dir: Vector3, length: float, r: float, col: Color, emit := 0.0, seg := 6) -> void:
	k.xf = Transform3D(_basis_y(dir), base)
	k.cylinder(r, 0.0, 0.0, length, seg, col, Vector2(0, emit))
	k.xf = Transform3D.IDENTITY


func _gem(pos: Vector3, r: float, col: Color, dir := Vector3.UP) -> void:
	k.xf = Transform3D(_basis_y(dir), pos)
	k.crystal(r, r * 2.2, r * 1.2, 5, col, Vector2(0, 0.9))
	k.xf = Transform3D.IDENTITY


## Double-sided triangle (wings, fins).
func _tri2(a: Vector3, b: Vector3, c: Vector3, col: Color, emit := 0.0) -> void:
	k.tri(a, b, c, col, Vector2(0, emit))
	k.tri(a, c, b, col, Vector2(0, emit))


## A fanned wing: `n` feather triangles from root toward tip directions, mirrored to side s (+1/-1).
func _wing(root: Vector3, s: float, span: float, up: float, back: float, col: Color, tip_col: Color, n := 4, emit := 0.0) -> void:
	for i in n:
		var f0 := float(i) / n
		var f1 := float(i + 1) / n
		var d0 := Vector3(-back * f0 * 1.2 + 0.05, up * (1.0 - f0 * 0.7), s * span * (0.55 + 0.45 * (1.0 - f0)))
		var d1 := Vector3(-back * f1 * 1.2 + 0.05, up * (1.0 - f1 * 0.7), s * span * (0.55 + 0.45 * (1.0 - f1)))
		var c := col.lerp(tip_col, f1)
		_tri2(root, root + d0, root + d1, c, emit)


func _eyes(pos: Vector3, spread: float, r: float) -> void:
	for s in [-1, 1]:
		_ell(pos + Vector3(0, 0, s * spread), Vector3(r, r * 1.15, r), eye, 1.0, Basis(), null, 4, 6)


# ---------------------------------------------------------------- body plans

func _beast(v: String) -> float:
	var bz := 0.15
	_ell(Vector3(-0.02, 0.36, 0), Vector3(0.26, 0.16, bz), main, 0.0, Basis(), sec)
	_ell(Vector3(0.15, 0.41, 0), Vector3(0.15, 0.17, 0.15), main, 0.0, Basis(), sec)
	_ell(Vector3(-0.02, 0.5, 0), Vector3(0.17, 0.035, 0.12), acc, 0.15)           # gilded back plate
	_limb(Vector3(0.18, 0.44, 0), Vector3(0.28, 0.57, 0), 0.085, 0.07, main)
	var head := Vector3(0.32, 0.61, 0)
	_ell(head, Vector3(0.12, 0.11, 0.105), main, 0.0, Basis(), sec)
	var snout := 0.06 if v == "fox" or v == "cat" else 0.075
	_ell(head + Vector3(0.11, -0.04, 0), Vector3(snout, 0.05, 0.06), sec)
	_ell(head + Vector3(0.11 + snout, -0.03, 0), Vector3(0.018, 0.016, 0.022), dark)
	_eyes(head + Vector3(0.075, 0.03, 0), 0.058, 0.022)
	_gem(head + Vector3(0.06, 0.095, 0), 0.025, glow, Vector3(0.3, 1, 0))
	var ear := 0.16 if v == "fox" else 0.1
	for s in [-1, 1]:
		_cone(head + Vector3(-0.02, 0.08, s * 0.06), Vector3(-0.2, 1, s * 0.35), ear, 0.04, main)
	for f in [[0.16, 1.0], [-0.17, 1.0]]:
		for s in [-1, 1]:
			var top := Vector3(f[0], 0.32, s * 0.09)
			_limb(top, Vector3(f[0] + 0.02, 0.03, s * 0.095), 0.055, 0.04, main)
			_ell(Vector3(f[0] + 0.04, 0.03, s * 0.095), Vector3(0.05, 0.03, 0.04), dark)
	match v:
		"fox":
			_ell(Vector3(-0.38, 0.47, 0), Vector3(0.17, 0.08, 0.08), main, 0.0, Basis(Vector3(0, 0, 1), 0.6))
			_ell(Vector3(-0.5, 0.56, 0), Vector3(0.06, 0.05, 0.05), sec)
		"cat":
			_limb(Vector3(-0.26, 0.4, 0), Vector3(-0.42, 0.62, 0), 0.03, 0.015, main)
		_:
			_limb(Vector3(-0.26, 0.42, 0), Vector3(-0.42, 0.52, 0), 0.045, 0.015, main)
	match v:
		"antlers":
			for s in [-1, 1]:
				var a := head + Vector3(-0.02, 0.09, s * 0.05)
				var b := a + Vector3(-0.08, 0.2, s * 0.12)
				_limb(a, b, 0.018, 0.012, acc, 0.35, 5)
				_limb(b, b + Vector3(-0.05, 0.12, s * 0.1), 0.012, 0.005, acc, 0.35, 5)
				_limb(b, b + Vector3(0.07, 0.1, s * 0.02), 0.012, 0.005, acc, 0.35, 5)
				_limb(a + Vector3(-0.04, 0.1, s * 0.06), a + Vector3(0.04, 0.17, s * 0.12), 0.01, 0.004, acc, 0.35, 5)
		"horns":
			for s in [-1, 1]:
				_cone(head + Vector3(0.0, 0.08, s * 0.06), Vector3(-0.5, 0.8, s * 0.4), 0.17, 0.035, acc, 0.2)
		"tusks":
			for s in [-1, 1]:
				_cone(head + Vector3(0.14, -0.08, s * 0.05), Vector3(0.6, 0.5, s * 0.2), 0.12, 0.022, Palette.SOFT_SILVER)
		"mane":
			for i in 7:
				var a := TAU * i / 7.0
				_cone(Vector3(0.22, 0.52, 0) + Vector3(0, cos(a) * 0.08, sin(a) * 0.09), Vector3(-0.6, cos(a), sin(a)), 0.13, 0.035, sec.lerp(acc, 0.3))
		"griffin":
			for s in [-1, 1]:
				_wing(Vector3(0.05, 0.5, s * 0.1), s, 0.42, 0.32, 0.3, sec, glow, 4, 0.1)
	return 0.8 if v == "antlers" else 0.7


func _drake(v: String) -> float:
	if v == "wyrm":
		var pts := [Vector3(-0.3, 0.1, -0.12), Vector3(-0.15, 0.13, 0.08), Vector3(0.02, 0.17, -0.06), Vector3(0.12, 0.3, 0.02), Vector3(0.16, 0.46, 0)]
		for i in pts.size():
			var r := 0.1 + 0.025 * i
			_ell(pts[i], Vector3(r, r * 0.9, r), main, 0.0, Basis(), sec)
			_cone(pts[i] + Vector3(0, r * 0.8, 0), Vector3(-0.3, 1, 0), 0.07, 0.03, acc, 0.2)
		_ell(Vector3(-0.42, 0.08, -0.14), Vector3(0.08, 0.05, 0.05), main)
		var wh := Vector3(0.24, 0.6, 0)
		_ell(wh, Vector3(0.14, 0.1, 0.1), main, 0.0, Basis(), sec)
		_ell(wh + Vector3(0.13, -0.03, 0), Vector3(0.08, 0.05, 0.07), sec)
		_eyes(wh + Vector3(0.08, 0.04, 0), 0.06, 0.022)
		for s in [-1, 1]:
			_cone(wh + Vector3(-0.04, 0.07, s * 0.05), Vector3(-0.8, 0.5, s * 0.2), 0.2, 0.03, acc, 0.25)
			_tri2(wh + Vector3(-0.05, 0.0, s * 0.08), wh + Vector3(-0.2, 0.06, s * 0.2), wh + Vector3(-0.16, -0.08, s * 0.12), glow, 0.3)
		return 0.72
	_ell(Vector3(-0.04, 0.34, 0), Vector3(0.28, 0.17, 0.16), main, 0.0, Basis(), sec)
	_limb(Vector3(0.16, 0.4, 0), Vector3(0.3, 0.62, 0), 0.09, 0.065, main)
	var head := Vector3(0.36, 0.66, 0)
	_ell(head, Vector3(0.13, 0.095, 0.1), main, 0.0, Basis(), sec)
	_ell(head + Vector3(0.13, -0.03, 0), Vector3(0.09, 0.05, 0.07), main)
	_eyes(head + Vector3(0.07, 0.035, 0), 0.06, 0.022)
	for s in [-1, 1]:
		_cone(head + Vector3(-0.05, 0.07, s * 0.05), Vector3(-0.9, 0.6, s * 0.25), 0.2, 0.032, acc, 0.25)
	for i in 5:
		_cone(Vector3(0.12 - i * 0.1, 0.5 - i * 0.02, 0), Vector3(-0.3, 1, 0), 0.09 - i * 0.008, 0.035, acc, 0.15, 4)
	var tail := [Vector3(-0.3, 0.32, 0), Vector3(-0.44, 0.26, 0.06), Vector3(-0.56, 0.2, 0.1), Vector3(-0.65, 0.17, 0.08)]
	for i in tail.size() - 1:
		_limb(tail[i], tail[i + 1], 0.08 - i * 0.022, 0.06 - i * 0.02, main)
	_cone(tail[3], Vector3(-1, 0.1, 0), 0.08, 0.03, acc, 0.3)
	for f in [0.16, -0.18]:
		for s in [-1, 1]:
			_limb(Vector3(f, 0.3, s * 0.11), Vector3(f + 0.03, 0.03, s * 0.12), 0.06, 0.045, main)
			_ell(Vector3(f + 0.05, 0.03, s * 0.12), Vector3(0.055, 0.03, 0.045), dark)
	if v == "wings":
		for s in [-1, 1]:
			var r := Vector3(0.02, 0.48, s * 0.12)
			_limb(r, r + Vector3(-0.1, 0.32, s * 0.28), 0.025, 0.015, main)
			_wing(r, s, 0.5, 0.38, 0.42, dark.lerp(main, 0.4), glow, 4, 0.15)
	if v == "saur":
		_ell(head + Vector3(0.02, -0.02, 0), Vector3(0.16, 0.11, 0.11), main)
	return 0.75


func _bird(v: String) -> float:
	_ell(Vector3(0, 0.38, 0), Vector3(0.15, 0.19, 0.14), main, 0.0, Basis(Vector3(0, 0, 1), -0.35), sec)
	var head := Vector3(0.1, 0.6, 0)
	var hr := 0.12 if v == "owl" else 0.095
	_ell(head, Vector3(hr, hr, hr), main, 0.0, Basis(), sec)
	if v == "owl":
		_ell(head + Vector3(0.07, -0.01, 0), Vector3(0.05, 0.09, 0.1), sec)
		_eyes(head + Vector3(0.1, 0.02, 0), 0.05, 0.032)
		for s in [-1, 1]:
			_cone(head + Vector3(0, 0.09, s * 0.07), Vector3(-0.1, 1, s * 0.4), 0.09, 0.03, main)
	else:
		_eyes(head + Vector3(0.06, 0.03, 0), 0.055, 0.02)
	_cone(head + Vector3(hr * 0.9, -0.01, 0), Vector3(1, -0.25, 0), 0.09, 0.03, acc)
	if v == "crest":
		for i in 4:
			_cone(head + Vector3(-0.04, 0.06, 0), Vector3(-0.8 - i * 0.2, 0.9 - i * 0.2, (i - 1.5) * 0.15), 0.18 + i * 0.02, 0.02, glow, 0.8, 4)
	var wing_col := dark if v == "bat" else main
	for s in [-1, 1]:
		_wing(Vector3(0.0, 0.48, s * 0.11), s, 0.5, 0.42, 0.35, wing_col, glow if v != "bat" else main, 5, 0.25 if v == "crest" else 0.05)
		_limb(Vector3(0.0, 0.22, s * 0.06), Vector3(0.02, 0.0, s * 0.07), 0.02, 0.015, acc)
		_ell(Vector3(0.05, 0.01, s * 0.07), Vector3(0.05, 0.015, 0.03), acc)
	for i in 3:
		_tri2(Vector3(-0.12, 0.3, 0), Vector3(-0.42, 0.22 + i * 0.05, (i - 1) * 0.12), Vector3(-0.4, 0.3 + i * 0.05, (i - 1) * 0.12 + 0.06), glow if v == "crest" else main, 0.3 if v == "crest" else 0.0)
	return 0.85


func _golem(v: String) -> float:
	var stone := main.lerp(Palette.SOFT_SILVER.lerp(Palette.MIDNIGHT_NAVY, 0.4), 0.45)
	for s in [-1, 1]:
		k.box(Vector3(-0.08, 0.0, s * 0.11 - 0.06), Vector3(0.08, 0.26, s * 0.11 + 0.06), stone, Vector2.ZERO)
		k.box(Vector3(-0.05, 0.0, s * 0.11 - 0.07), Vector3(0.12, 0.06, s * 0.11 + 0.07), dark, Vector2.ZERO)
	k.box(Vector3(-0.13, 0.24, -0.17), Vector3(0.13, 0.34, 0.17), dark, Vector2.ZERO)
	k.xf = Transform3D(Basis(Vector3(0, 0, 1), -0.08), Vector3(0, 0.48, 0))
	k.box(Vector3(-0.16, -0.15, -0.22), Vector3(0.16, 0.16, 0.22), stone, Vector2.ZERO)
	k.box(Vector3(0.1, -0.08, -0.12), Vector3(0.18, 0.1, 0.12), acc, Vector2(0, 0.1))
	k.xf = Transform3D.IDENTITY
	_gem(Vector3(0.19, 0.5, 0), 0.04, glow, Vector3(1, 0.2, 0))
	for s in [-1, 1]:
		_ell(Vector3(0, 0.62, s * 0.25), Vector3(0.11, 0.1, 0.11), main)
		_limb(Vector3(0.02, 0.58, s * 0.28), Vector3(0.08, 0.26, s * 0.3), 0.07, 0.06, stone)
		k.box(Vector3(0.02, 0.14, s * 0.3 - 0.08), Vector3(0.18, 0.28, s * 0.3 + 0.08), dark, Vector2.ZERO)
		_cone(Vector3(0, 0.68, s * 0.25), Vector3(-0.2, 1, s * 0.5), 0.1, 0.04, acc, 0.15, 4)
	k.box(Vector3(-0.06, 0.64, -0.08), Vector3(0.1, 0.78, 0.08), stone, Vector2.ZERO)
	k.box(Vector3(0.095, 0.69, -0.06), Vector3(0.105, 0.72, 0.06), eye, Vector2(0, 1.0))
	_cone(Vector3(0.0, 0.78, 0), Vector3(0.1, 1, 0), 0.09, 0.05, acc, 0.2, 4)
	return 0.95 if v == "big" else 0.85


func _bug(v: String) -> float:
	var shell := main.lerp(dark, 0.2)
	match v:
		"mantis":
			_ell(Vector3(-0.2, 0.2, 0), Vector3(0.2, 0.08, 0.08), main, 0.0, Basis(Vector3(0, 0, 1), 0.2), sec)
			_limb(Vector3(-0.02, 0.22, 0), Vector3(0.1, 0.5, 0), 0.06, 0.045, main)
			var head := Vector3(0.14, 0.56, 0)
			_ell(head, Vector3(0.07, 0.06, 0.09), main)
			_eyes(head + Vector3(0.03, 0.02, 0), 0.07, 0.03)
			for s in [-1, 1]:
				_limb(Vector3(0.08, 0.42, s * 0.06), Vector3(0.22, 0.3, s * 0.1), 0.03, 0.025, main)
				_cone(Vector3(0.22, 0.3, s * 0.1), Vector3(-0.2, 1, 0), 0.24, 0.03, acc, 0.2)
				_cone(head + Vector3(0, 0.05, s * 0.03), Vector3(0.6, 1, s * 0.5), 0.14, 0.008, main)
				_tri2(Vector3(-0.02, 0.3, s * 0.03), Vector3(-0.42, 0.26, s * 0.12), Vector3(-0.3, 0.36, s * 0.05), glow, 0.2)
			_legs(Vector3(-0.1, 0.2, 0), 2, 0.2)
			return 0.68
		"scorpion", "crab":
			_ell(Vector3(0, 0.18, 0), Vector3(0.2, 0.09, 0.16), shell, 0.0, Basis(), sec)
			_eyes(Vector3(0.18, 0.24, 0), 0.04, 0.02)
			for s in [-1, 1]:
				_limb(Vector3(0.12, 0.18, s * 0.12), Vector3(0.26, 0.22, s * 0.2), 0.03, 0.025, shell)
				_ell(Vector3(0.32, 0.23, s * 0.2), Vector3(0.08, 0.05, 0.05), acc)
				_cone(Vector3(0.36, 0.25, s * 0.2), Vector3(1, 0.3, -s * 0.3), 0.08, 0.025, acc)
			_legs(Vector3(-0.02, 0.17, 0), 3, 0.18)
			if v == "scorpion":
				var pts := [Vector3(-0.18, 0.2, 0), Vector3(-0.3, 0.32, 0), Vector3(-0.32, 0.48, 0), Vector3(-0.22, 0.6, 0), Vector3(-0.1, 0.62, 0)]
				for i in pts.size() - 1:
					_limb(pts[i], pts[i + 1], 0.05 - i * 0.008, 0.045 - i * 0.008, shell)
				_cone(pts[4], Vector3(1, -0.6, 0), 0.1, 0.035, glow, 0.8)
				return 0.66
			return 0.4
		"moth":
			_ell(Vector3(0, 0.35, 0), Vector3(0.16, 0.07, 0.07), main, 0.0, Basis(Vector3(0, 0, 1), 0.3), sec)
			_ell(Vector3(0.14, 0.42, 0), Vector3(0.06, 0.06, 0.06), sec)
			_eyes(Vector3(0.18, 0.44, 0), 0.04, 0.022)
			for s in [-1, 1]:
				_wing(Vector3(0.02, 0.38, s * 0.04), s, 0.45, 0.4, 0.15, main.lerp(glow, 0.3), acc, 3, 0.35)
				_wing(Vector3(-0.04, 0.34, s * 0.04), s, 0.3, 0.12, 0.35, main, glow, 3, 0.35)
				_cone(Vector3(0.17, 0.48, s * 0.02), Vector3(0.5, 1, s * 0.6), 0.14, 0.008, acc)
			_legs(Vector3(0, 0.32, 0), 2, 0.12)
			return 0.75
		"spider":
			_ell(Vector3(-0.12, 0.26, 0), Vector3(0.17, 0.15, 0.15), shell, 0.0, Basis(), sec)
			_ell(Vector3(0.1, 0.22, 0), Vector3(0.09, 0.08, 0.08), main)
			_eyes(Vector3(0.17, 0.26, 0), 0.035, 0.018)
			_gem(Vector3(-0.12, 0.42, 0), 0.04, glow)
			_legs(Vector3(0.0, 0.22, 0), 4, 0.28)
			return 0.48
	# beetle
	_ell(Vector3(-0.06, 0.24, 0), Vector3(0.24, 0.15, 0.18), shell, 0.1, Basis(), sec)
	_ell(Vector3(-0.06, 0.33, 0), Vector3(0.21, 0.06, 0.005), acc, 0.3)
	_ell(Vector3(0.18, 0.22, 0), Vector3(0.09, 0.08, 0.1), main)
	_eyes(Vector3(0.24, 0.25, 0), 0.06, 0.022)
	_cone(Vector3(0.24, 0.27, 0), Vector3(1, 1.3, 0), 0.24, 0.035, acc, 0.25)
	_legs(Vector3(0.0, 0.2, 0), 3, 0.24)
	return 0.55


func _legs(c: Vector3, pairs: int, reach: float) -> void:
	for i in pairs:
		var x := c.x + (i - (pairs - 1) / 2.0) * 0.11
		for s in [-1, 1]:
			var knee := Vector3(x + 0.02, c.y + 0.1, s * reach)
			_limb(Vector3(x, c.y, s * 0.06), knee, 0.022, 0.018, dark)
			_limb(knee, Vector3(x + 0.05, 0.0, s * (reach + 0.06)), 0.018, 0.008, dark)


func _floater(v: String) -> float:
	match v:
		"orb":
			_ell(Vector3(0, 0.38, 0), Vector3(0.17, 0.17, 0.17), main, 0.15, Basis(), sec)
			_ell(Vector3(0.14, 0.4, 0), Vector3(0.05, 0.06, 0.08), eye, 1.0)
			for r in 2:
				for i in 16:
					var a := TAU * i / 16.0
					var b := Basis(Vector3(1, 0, 0), 0.5 + r * 1.2)
					var q := b * Vector3(cos(a) * 0.26, 0, sin(a) * 0.26)
					k.xf = Transform3D(b * Basis(Vector3.UP, -a), Vector3(0, 0.38, 0) + q)
					k.box(Vector3(-0.012, -0.012, -0.055), Vector3(0.012, 0.012, 0.055), acc, Vector2(0, 0.4))
			k.xf = Transform3D.IDENTITY
			return 0.6
		"fish":
			_ell(Vector3(0, 0.35, 0), Vector3(0.22, 0.11, 0.08), main, 0.0, Basis(), sec)
			_eyes(Vector3(0.14, 0.38, 0), 0.06, 0.022)
			_tri2(Vector3(-0.18, 0.35, 0), Vector3(-0.38, 0.5, 0), Vector3(-0.38, 0.2, 0), glow, 0.4)
			_tri2(Vector3(0.0, 0.44, 0), Vector3(-0.14, 0.6, 0), Vector3(-0.12, 0.44, 0), glow, 0.4)
			for s in [-1, 1]:
				_tri2(Vector3(0.04, 0.32, s * 0.07), Vector3(-0.08, 0.26, s * 0.24), Vector3(-0.1, 0.33, s * 0.1), glow, 0.4)
			return 0.6
		"ray":
			_ell(Vector3(0, 0.35, 0), Vector3(0.2, 0.05, 0.14), main, 0.0, Basis(), sec)
			for s in [-1, 1]:
				_tri2(Vector3(0.12, 0.35, s * 0.1), Vector3(-0.12, 0.4, s * 0.45), Vector3(-0.16, 0.33, s * 0.1), main.lerp(glow, 0.3), 0.2)
			_limb(Vector3(-0.18, 0.35, 0), Vector3(-0.55, 0.42, 0), 0.02, 0.004, dark)
			_eyes(Vector3(0.14, 0.39, 0), 0.06, 0.02)
			return 0.5
		"shard":
			for i in 5:
				var a := TAU * i / 5.0
				_gem(Vector3(cos(a) * 0.1, 0.32, sin(a) * 0.1), 0.05 + 0.02 * (i % 2), main.lerp(glow, 0.4), Vector3(cos(a) * 0.5, 1, sin(a) * 0.5))
			_gem(Vector3(0, 0.38, 0), 0.09, glow)
			_eyes(Vector3(0.1, 0.42, 0), 0.04, 0.02)
			return 0.7
	# sprite: little winged fairy-spirit
	_cone(Vector3(0, 0.18, 0), Vector3.UP, 0.32, 0.11, main, 0.15, 8)
	_ell(Vector3(0, 0.55, 0), Vector3(0.11, 0.11, 0.11), sec, 0.0)
	_ell(Vector3(-0.03, 0.6, 0), Vector3(0.11, 0.07, 0.12), main)
	_eyes(Vector3(0.08, 0.56, 0), 0.045, 0.022)
	_gem(Vector3(0.0, 0.36, 0), 0.04, glow)
	for s in [-1, 1]:
		_tri2(Vector3(-0.02, 0.45, s * 0.05), Vector3(-0.12, 0.72, s * 0.32), Vector3(-0.18, 0.5, s * 0.22), glow, 0.6)
		_tri2(Vector3(-0.02, 0.42, s * 0.05), Vector3(-0.16, 0.3, s * 0.26), Vector3(-0.12, 0.42, s * 0.2), glow, 0.6)
	return 0.75


func _hopper() -> float:
	_ell(Vector3(-0.04, 0.24, 0), Vector3(0.18, 0.17, 0.16), main, 0.0, Basis(), sec)
	var head := Vector3(0.12, 0.44, 0)
	_ell(head, Vector3(0.13, 0.12, 0.13), main, 0.0, Basis(), sec)
	_eyes(head + Vector3(0.09, 0.03, 0), 0.06, 0.028)
	_ell(head + Vector3(0.12, -0.03, 0), Vector3(0.025, 0.02, 0.03), dark)
	for s in [-1, 1]:
		_ell(head + Vector3(-0.04, 0.18, s * 0.06), Vector3(0.04, 0.14, 0.035), main, 0.0, Basis(Vector3(1, 0, 0), s * -0.25) * Basis(Vector3(0, 0, 1), 0.3))
		_ell(head + Vector3(-0.03, 0.18, s * 0.075), Vector3(0.015, 0.1, 0.02), glow, 0.4, Basis(Vector3(1, 0, 0), s * -0.25) * Basis(Vector3(0, 0, 1), 0.3))
		_ell(Vector3(0.0, 0.04, s * 0.1), Vector3(0.11, 0.045, 0.06), sec)
		_ell(Vector3(0.12, 0.16, s * 0.08), Vector3(0.04, 0.06, 0.04), main)
	_ell(Vector3(-0.22, 0.3, 0), Vector3(0.06, 0.06, 0.06), sec)
	_gem(head + Vector3(0.04, 0.12, 0), 0.025, glow)
	return 0.75
