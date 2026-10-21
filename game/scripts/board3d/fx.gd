## One-shot 3D effects for the board: stone debris, dust, shockwaves, rubble piles, summon capsules,
## and the element delivery per family (fire bolt, water wave, wind slash, earth spikes, thunder
## strike, ice shards, wood vines, tech beam, light pillar, dark void, arcane runes, space rift).
## Every node frees itself. Effects play in real time (they are short and fire-and-forget); the
## board's timeline decides WHEN they start. No effect strobes: each bright flash happens once.
extends RefCounted

const Mats = preload("res://scripts/board3d/mats.gd")
const Palette = preload("res://scripts/theme_colors.gd")
const Build = preload("res://scripts/board3d/board_build.gd")

## Element delivery: how the attack reaches its target.
const DELIVERY := {"Fire": "bolt", "Water": "wave", "Wind": "slash", "Earth": "spikes", "Thunder": "strike",
	"Ice": "shards", "Wood": "vines", "Tech": "beam", "Light": "pillar", "Dark": "void", "Arcane": "runes", "Space": "rift"}
## Travel time per delivery (seconds from release to impact).
const TRAVEL := {"bolt": 0.22, "wave": 0.3, "slash": 0.08, "spikes": 0.12, "strike": 0.06, "shards": 0.2,
	"vines": 0.16, "beam": 0.05, "pillar": 0.1, "void": 0.14, "runes": 0.24, "rift": 0.12}


static func _free_after(n: Node, sec: float) -> void:
	if n.is_inside_tree():
		n.get_tree().create_timer(sec).timeout.connect(n.queue_free)


static func _particles(parent: Node3D, pos: Vector3, mesh: Mesh, mat: Material, amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.material_override = mat
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.position = pos
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.emitting = true
	_free_after(p, life + 0.4)
	return p


static func _box_mesh(s: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(s, s * 0.8, s * 1.1)
	return b


static func _dot(s: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(s, s)
	return q


## Stone shell flying apart (physics-free particles with gravity).
static func debris(parent: Node3D, pos: Vector3, tint: Color, n := 22, power := 1.0) -> void:
	var p := _particles(parent, pos, _box_mesh(0.08), Mats.debris(), n, 1.1)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 1.6 * power
	p.initial_velocity_max = 3.6 * power
	p.gravity = Vector3(0, -9.0, 0)
	p.angular_velocity_min = -520.0
	p.angular_velocity_max = 520.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.6
	p.color = Color(0.62, 0.6, 0.55).lerp(tint, 0.12)
	# glowing crack fragments mixed in
	var g := _particles(parent, pos, _dot(0.07), Mats.particle(), n / 2, 0.7)
	g.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	g.emission_sphere_radius = 0.25
	g.direction = Vector3.UP
	g.spread = 90.0
	g.initial_velocity_min = 1.5 * power
	g.initial_velocity_max = 3.0 * power
	g.gravity = Vector3(0, -4.0, 0)
	g.color = tint.lerp(Color.WHITE, 0.3)


## Small stone chips off a statue that takes a hit.
static func chips(parent: Node3D, pos: Vector3, n := 8) -> void:
	var p := _particles(parent, pos, _box_mesh(0.045), Mats.debris(), n, 0.7)
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0, -8.0, 0)
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.color = Color(0.6, 0.58, 0.54)


## Dust puff where a statue lands.
static func dust(parent: Node3D, pos: Vector3, n := 7) -> void:
	var p := _particles(parent, pos + Vector3(0, 0.05, 0), _dot(0.16), Mats.particle(), n, 0.55)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.22
	p.emission_ring_inner_radius = 0.1
	p.emission_ring_height = 0.02
	p.direction = Vector3(0, 0.3, 0)
	p.spread = 180.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.6
	p.gravity = Vector3(0, 0.15, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	var g := Gradient.new()
	g.set_color(0, Color(0.82, 0.78, 0.7, 0.55))
	g.set_color(1, Color(0.82, 0.78, 0.7, 0.0))
	p.color_ramp = g


## Expanding ground ring.
static func shockwave(parent: Node3D, pos: Vector3, col: Color, radius := 1.6, dur := 0.45) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := Mats.blob(col.lerp(Color.WHITE, 0.25), true)
	mi.material_override = m
	mi.position = pos + Vector3(0, 0.04, 0)
	mi.scale = Vector3.ONE * 0.3
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 2.0, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, dur)
	tw.chain().tween_callback(mi.queue_free)


## Soft light flash (a camera-facing halo), once.
static func flash(parent: Node3D, pos: Vector3, col: Color, size := 1.9, intensity := 1.4) -> void:
	var f := MeshInstance3D.new()
	f.mesh = QuadMesh.new()
	var fm := Mats.halo(col, intensity)
	f.material_override = fm
	f.position = pos
	f.scale = Vector3.ONE * 0.3
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(f)
	var tw := f.create_tween().set_parallel(true)
	tw.tween_property(f, "scale", Vector3.ONE * size, 0.45).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float): fm.set_shader_parameter("intensity", v), intensity, 0.0, 0.5)
	tw.chain().tween_callback(f.queue_free)


## A pile of rubble that settles where a statue crumbled, then sinks away.
static func rubble_pile(parent: Node3D, pos: Vector3, tint: Color, seed: int) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var col := Color(0.6, 0.58, 0.53).lerp(tint, 0.1)
	for i in 9:
		var b := MeshInstance3D.new()
		var s := rng.randf_range(0.06, 0.14)
		b.mesh = _box_mesh(s)
		var m := StandardMaterial3D.new()
		m.albedo_color = col.darkened(rng.randf() * 0.25)
		m.roughness = 0.95
		b.material_override = m
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.02, 0.3)
		b.position = Vector3(cos(a) * d, s * 0.4, sin(a) * d)
		b.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		root.add_child(b)
	var tw := root.create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(root, "position:y", pos.y - 0.35, 1.0).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(root, "scale", Vector3(1.0, 0.2, 1.0), 1.0)
	tw.tween_callback(root.queue_free)
	return root


## Glowing geometry piece with an auto fade.
static func _glow_mesh(parent: Node3D, mesh: Mesh, col: Color, xf: Transform3D, life: float, energy := 1.8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := Mats.glow(col, energy)
	mi.material_override = m
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_interval(life * 0.45)
	tw.tween_property(m, "albedo_color:a", 0.0, life * 0.55)
	tw.tween_callback(mi.queue_free)
	return mi


static func _orb_mover(parent: Node3D, from: Vector3, to: Vector3, col: Color, size: float, travel: float, arc := 0.0, trail := true) -> void:
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	orb.mesh = sm
	orb.material_override = Mats.glow(col.lerp(Color.WHITE, 0.35), 2.2)
	orb.position = from
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(orb)
	if trail:
		var p := CPUParticles3D.new()
		p.mesh = _dot(size * 1.4)
		p.material_override = Mats.particle()
		p.amount = 16
		p.lifetime = 0.3
		p.local_coords = false
		p.spread = 180.0
		p.initial_velocity_min = 0.05
		p.initial_velocity_max = 0.2
		p.gravity = Vector3.ZERO
		var g := Gradient.new()
		g.set_color(0, Color(col, 0.9))
		g.set_color(1, Color(col, 0.0))
		p.color_ramp = g
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		orb.add_child(p)
		p.emitting = true
	var tw := orb.create_tween()
	tw.tween_method(func(f: float):
		if is_instance_valid(orb):
			orb.position = from.lerp(to, f) + Vector3(0, arc * 4.0 * f * (1.0 - f), 0), 0.0, 1.0, maxf(travel, 0.01))
	tw.tween_callback(orb.queue_free)


## Delivers an element attack from `from` (attacker chest) to `to` (target chest). `var_k` = skill
## variant 0..2 (from the skill name): more / bigger pieces. Returns the travel time to impact.
## ground_y: the target's foot height (ground-borne effects: spikes, vines, waves, pillars).
static func deliver(parent: Node3D, family: String, from: Vector3, to: Vector3, var_k: int, rng_seed: int, ground_y := -999.0) -> float:
	var kind := str(DELIVERY.get(family, "runes"))
	var col := Palette.family(family)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var travel: float = TRAVEL.get(kind, 0.15)
	var n := 1 + var_k * 2
	var ground := Vector3(to.x, to.y - 0.45 if ground_y < -900.0 else ground_y, to.z)
	match kind:
		"bolt":
			for i in n:
				var jit := Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(-0.1, 0.15), rng.randf_range(-0.15, 0.15)) * (1.0 if i > 0 else 0.0)
				_orb_mover(parent, from, to + jit, Palette.EMBER.lerp(Palette.SIGIL_GOLD, 0.3), 0.1 + 0.03 * var_k, travel + i * 0.04, 0.3)
		"wave":
			var d := to - from
			d.y = 0
			var steps := 7
			for i in steps:
				var f := float(i) / (steps - 1)
				var at := from.lerp(to, f)
				at.y = ground.y + 0.05
				var q := QuadMesh.new()
				q.size = Vector2(0.55 + 0.15 * var_k, 0.35 + 0.1 * var_k)
				var xf := Transform3D(Basis.looking_at(d.normalized() if d.length() > 0.01 else Vector3.FORWARD, Vector3.UP), at + Vector3(0, 0.15, 0))
				var mi := _glow_mesh(parent, q, col.lerp(Palette.SOFT_SILVER, 0.3), xf, 0.35 + f * 0.2, 1.2)
				mi.visible = false
				parent.get_tree().create_timer(travel * f).timeout.connect(mi.set.bind("visible", true))
		"slash":
			for i in 1 + var_k:
				var q := QuadMesh.new()
				q.size = Vector2(1.1, 0.07)
				var ang := rng.randf_range(-0.9, 0.9)
				var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(0, 0, 1), ang)
				_glow_mesh(parent, q, Palette.SOFT_SILVER.lerp(col, 0.4), Transform3D(b, to), 0.3, 2.4)
		"spikes":
			for i in 3 + var_k * 2:
				var a := TAU * i / (3.0 + var_k * 2) + rng.randf()
				var r := 0.0 if i == 0 else rng.randf_range(0.15, 0.4)
				var c := CylinderMesh.new()
				c.top_radius = 0.0
				c.bottom_radius = rng.randf_range(0.07, 0.12)
				c.height = rng.randf_range(0.5, 0.85)
				c.radial_segments = 5
				var mi := MeshInstance3D.new()
				mi.mesh = c
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(0.55, 0.47, 0.36).lerp(col, 0.25)
				m.roughness = 0.9
				mi.material_override = m
				var tilt := Basis(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), -0.25 * (r / 0.4))
				mi.transform = Transform3D(tilt, ground + Vector3(cos(a) * r, -0.5, sin(a) * r))
				parent.add_child(mi)
				var tw := mi.create_tween()
				tw.tween_property(mi, "position:y", ground.y + c.height * 0.4, 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
				tw.tween_interval(0.45)
				tw.tween_property(mi, "position:y", ground.y - 0.6, 0.3).set_ease(Tween.EASE_IN)
				tw.tween_callback(mi.queue_free)
		"strike":
			var top := to + Vector3(rng.randf_range(-0.4, 0.4), 6.0, rng.randf_range(-0.4, 0.4))
			var prev := top
			var segs := 7
			for i in range(1, segs + 1):
				var f := float(i) / segs
				var pt := top.lerp(to, f) + (Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25)) if i < segs else Vector3.ZERO)
				var len := prev.distance_to(pt)
				var bx := BoxMesh.new()
				bx.size = Vector3(0.06 + 0.02 * var_k, len, 0.06 + 0.02 * var_k)
				var dir := (pt - prev).normalized()
				var bb := _basis_y(dir)
				_glow_mesh(parent, bx, Palette.SIGIL_GOLD.lerp(Color.WHITE, 0.5), Transform3D(bb, (prev + pt) * 0.5), 0.32, 3.0)
				prev = pt
		"shards":
			for i in 2 + var_k * 2:
				var jit := Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.1, 0.2), rng.randf_range(-0.2, 0.2))
				var shard := MeshInstance3D.new()
				shard.mesh = Build.crystal_mesh(0.05, 0.16, 0.08, 4)
				shard.material_override = Mats.crystal(Palette.AETHER_CYAN.lerp(Palette.SOFT_SILVER, 0.5), 1.8)
				shard.position = from
				parent.add_child(shard)
				var dir := (to + jit - from).normalized()
				shard.basis = _basis_y(dir)
				var tw := shard.create_tween()
				tw.tween_interval(i * 0.035)
				tw.tween_property(shard, "position", to + jit, travel).set_ease(Tween.EASE_IN)
				tw.tween_property(shard, "scale", Vector3.ONE * 0.01, 0.15)
				tw.tween_callback(shard.queue_free)
		"vines":
			for i in 3 + var_k:
				var a := TAU * i / (3.0 + var_k) + rng.randf() * 0.5
				var c := CylinderMesh.new()
				c.top_radius = 0.015
				c.bottom_radius = 0.045
				c.height = 0.9
				c.radial_segments = 5
				var mi := MeshInstance3D.new()
				mi.mesh = c
				var m := StandardMaterial3D.new()
				m.albedo_color = Palette.VERDANT_GREEN.darkened(0.25)
				m.emission_enabled = true
				m.emission = Palette.VERDANT_GREEN * 0.4
				mi.material_override = m
				var out := Vector3(cos(a), 0, sin(a))
				mi.transform = Transform3D(Basis(out.cross(Vector3.UP).normalized(), 0.45), ground + out * 0.32 + Vector3(0, 0.3, 0))
				mi.scale = Vector3(1, 0.01, 1)
				parent.add_child(mi)
				var tw := mi.create_tween()
				tw.tween_property(mi, "scale", Vector3.ONE, 0.16).set_ease(Tween.EASE_OUT)
				tw.tween_interval(0.5)
				tw.tween_property(mi, "scale", Vector3(1, 0.01, 1), 0.25)
				tw.tween_callback(mi.queue_free)
			var lv := _particles(parent, to, _dot(0.08), Mats.particle(), 12, 0.8)
			lv.spread = 180.0
			lv.initial_velocity_min = 0.6
			lv.initial_velocity_max = 1.2
			lv.gravity = Vector3(0, -1.5, 0)
			lv.color = Palette.VERDANT_GREEN.lerp(Palette.SIGIL_GOLD, 0.2)
		"beam":
			var d := to - from
			var bx := BoxMesh.new()
			bx.size = Vector3(0.06 + 0.04 * var_k, d.length(), 0.06 + 0.04 * var_k)
			_glow_mesh(parent, bx, Palette.AETHER_CYAN, Transform3D(_basis_y(d), (from + to) * 0.5), 0.4, 2.6)
			var core := BoxMesh.new()
			core.size = Vector3(0.02, d.length(), 0.02)
			_glow_mesh(parent, core, Color.WHITE, Transform3D(_basis_y(d), (from + to) * 0.5), 0.3, 2.0)
		"pillar":
			var c := CylinderMesh.new()
			c.top_radius = 0.35 + 0.08 * var_k
			c.bottom_radius = 0.3 + 0.08 * var_k
			c.height = 5.0
			c.radial_segments = 14
			c.cap_top = false
			c.cap_bottom = false
			_glow_mesh(parent, c, Palette.SIGIL_GOLD.lerp(Color.WHITE, 0.45), Transform3D(Basis(), ground + Vector3(0, 2.5, 0)), 0.6, 1.1)
		"void":
			var sm := SphereMesh.new()
			sm.radius = 0.4 + 0.1 * var_k
			sm.height = sm.radius * 2.0
			var mi := MeshInstance3D.new()
			mi.mesh = sm
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.05, 0.02, 0.12, 0.85)
			mi.material_override = m
			mi.position = to
			mi.scale = Vector3.ONE * 0.05
			parent.add_child(mi)
			var tw := mi.create_tween()
			tw.tween_property(mi, "scale", Vector3.ONE, 0.14).set_ease(Tween.EASE_OUT)
			tw.tween_interval(0.3)
			tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.2).set_ease(Tween.EASE_IN)
			tw.tween_callback(mi.queue_free)
			var p := _particles(parent, to, _dot(0.07), Mats.particle(), 18, 0.5)
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.7
			p.radial_accel_min = -6.0
			p.radial_accel_max = -4.0
			p.gravity = Vector3.ZERO
			p.color = Palette.CRYSTAL_VIOLET
		"runes":
			for i in 1 + var_k:
				_orb_mover(parent, from + Vector3(0, 0.1 * i, 0), to, Palette.CRYSTAL_VIOLET.lerp(Palette.SIGIL_GOLD, 0.3), 0.07, travel + i * 0.05, 0.5, true)
			var ringm := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(1, 1)
			q.orientation = PlaneMesh.FACE_Y
			ringm.mesh = q
			var rm := Mats.blob(Palette.CRYSTAL_VIOLET, true)
			ringm.material_override = rm
			ringm.position = ground + Vector3(0, 0.06, 0)
			ringm.scale = Vector3.ONE * 1.4
			parent.add_child(ringm)
			var tw := ringm.create_tween()
			tw.tween_property(ringm, "rotation:y", PI, 0.7)
			tw.parallel().tween_method(func(v: float): rm.set_shader_parameter("fade", v), 1.0, 0.0, 0.7)
			tw.tween_callback(ringm.queue_free)
		"rift":
			var q := QuadMesh.new()
			q.size = Vector2(0.35 + 0.1 * var_k, 1.3)
			var mi := _glow_mesh(parent, q, Palette.CRYSTAL_VIOLET.lerp(Palette.AETHER_CYAN, 0.35), Transform3D(Basis(Vector3.UP, rng.randf() * PI), to), 0.6, 1.8)
			mi.scale = Vector3(0.05, 1, 1)
			var tw := mi.create_tween()
			tw.tween_property(mi, "scale", Vector3.ONE, 0.12).set_ease(Tween.EASE_OUT)
			var st := _particles(parent, to, _dot(0.05), Mats.particle(), 14, 0.6)
			st.spread = 180.0
			st.initial_velocity_min = 0.8
			st.initial_velocity_max = 1.6
			st.gravity = Vector3.ZERO
			st.color = Palette.AETHER_CYAN.lerp(Color.WHITE, 0.4)
	return travel


## Impact sparkle in the element colour at the target.
static func impact(parent: Node3D, pos: Vector3, family: String, big: bool) -> void:
	var col := Palette.family(family)
	var p := _particles(parent, pos, _dot(0.08), Mats.particle(), 18 if big else 10, 0.5)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12
	p.spread = 180.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.6 if big else 1.8
	p.gravity = Vector3(0, -2.0, 0)
	p.color = col.lerp(Color.WHITE, 0.35)


## Sealed faceted capsule crystal (NOT a sphere) for the summon sequence.
static func capsule(parent: Node3D, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Build.crystal_mesh(0.2, 0.42, 0.3, 6)
	mi.material_override = Mats.crystal(col, 1.0)
	mi.position = pos
	mi.scale = Vector3.ONE * 1.6
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var h := MeshInstance3D.new()
	h.mesh = QuadMesh.new()
	h.material_override = Mats.halo(col, 0.9)
	h.scale = Vector3.ONE * 0.9
	h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(h)
	return mi


## Vertical light beam (summon burst).
static func beam_up(parent: Node3D, pos: Vector3, col: Color) -> void:
	var c := CylinderMesh.new()
	c.top_radius = 0.05
	c.bottom_radius = 0.3
	c.height = 4.5
	c.radial_segments = 12
	c.cap_top = false
	c.cap_bottom = false
	_glow_mesh(parent, c, col.lerp(Color.WHITE, 0.5), Transform3D(Basis(), pos + Vector3(0, 2.25, 0)), 0.7, 1.2)


static func _basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	if y.length() < 0.5:
		return Basis()
	var ref := Vector3(0, 0, 1) if absf(y.z) < 0.9 else Vector3(1, 0, 0)
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)
