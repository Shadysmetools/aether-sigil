## One monster on the 3D board. It stands as a weathered stone STATUE of itself on a round chess-style
## plinth (team-coloured rim, element emblem). When it acts, the board drives the transform: element
## cracks race over the stone, the stone shatters, the live monster (painted billboard when real
## cut-out art exists, else its procedural creature in full colour) roars, performs its archetype's
## move-set, then re-petrifies from the feet up. Every monster is personal: a seed from its monster
## id picks proportions, extra features (creature.gd EXTRAS), idle pose and attack timing / arc /
## hit count. All motion runs on scaled time from the board (Tracks), never on real-time tweens,
## so hold-to-2x, hit-stop and slow-mo apply and settle() can finish any animation instantly.
## Presentation only: the board tells it what happened; it never reads rules.
extends Node3D

const Mats = preload("res://scripts/board3d/mats.gd")
const Creature = preload("res://scripts/board3d/creature.gd")
const Kit = preload("res://scripts/board3d/mesh_kit.gd")
const Assets = preload("res://scripts/assets.gd")
const Palette = preload("res://scripts/theme_colors.gd")
const Q = preload("res://scripts/board3d/anim_queue.gd")

const SCALE := 2.0         ## creatures stand ~1-1.3 tiles tall, like the concept sheet
const PLINTH_H := 0.11     ## the chess-piece base the statue stands on
const STATUE := 1.1        ## stone_h value for a full statue

## Aura per element family: [colour a, colour b, gravity, initial speed, lifetime, amount, size].
const AURA := {
	"Fire": [Palette.EMBER, Palette.SIGIL_GOLD, Vector3(0, 0.55, 0), 0.25, 1.1, 12, 0.07],
	"Water": [Palette.AETHER_CYAN, Palette.CRYSTAL_VIOLET, Vector3(0, -0.7, 0), 0.15, 1.0, 8, 0.05],
	"Wind": [Palette.SOFT_SILVER, Palette.AETHER_CYAN, Vector3(0.45, 0.15, 0.2), 0.3, 1.0, 9, 0.05],
	"Earth": [Palette.SIGIL_GOLD, Palette.VERDANT_GREEN, Vector3(0, -0.4, 0), 0.12, 1.3, 7, 0.05],
	"Wood": [Palette.VERDANT_GREEN, Palette.SIGIL_GOLD, Vector3(0.1, -0.25, 0.05), 0.12, 1.8, 8, 0.06],
	"Ice": [Palette.SOFT_SILVER, Palette.AETHER_CYAN, Vector3(0, -0.2, 0), 0.08, 1.8, 9, 0.05],
	"Thunder": [Palette.SIGIL_GOLD, Palette.SOFT_SILVER, Vector3(0, 0, 0), 0.9, 0.35, 10, 0.045],
	"Light": [Palette.SIGIL_GOLD, Palette.SOFT_SILVER, Vector3(0, 0.3, 0), 0.1, 1.6, 9, 0.05],
	"Dark": [Palette.CRYSTAL_VIOLET, Palette.MIDNIGHT_NAVY, Vector3(0, 0.25, 0), 0.08, 1.6, 8, 0.1],
	"Tech": [Palette.AETHER_CYAN, Palette.SOFT_SILVER, Vector3(0, 0.35, 0), 0.15, 1.0, 8, 0.04],
	"Space": [Palette.CRYSTAL_VIOLET, Palette.AETHER_CYAN, Vector3(0, 0.05, 0), 0.06, 1.6, 10, 0.045],
	"Arcane": [Palette.CRYSTAL_VIOLET, Palette.SIGIL_GOLD, Vector3(0, 0.3, 0), 0.12, 1.4, 9, 0.05],
}

## Archetype move-set per body plan (creature.gd PLANS).
const MOVESET := {"beast": "charge", "drake": "coil", "bird": "dive", "golem": "slam", "bug": "ram",
	"floater": "spincast", "hopper": "bounce"}

var uid := -1
var side := 0
var family := ""
var unit_name := ""
var mon_id := ""
var plan := "beast"
var variant := ""
var seed := 0
var extras: Array = []
var is_sprite := false
var height := 0.7
var model_h := 0.7
var hover := 0.0
var base := Vector3.ZERO          ## feet position on the tile
var facing := Vector3(1, 0, 1)
var dormant := false
var spent := false
var defending := false
var dying := false
var max_hp := 1
var shown_hp := 1                 ## HP the overlay shows (moves at impact, not when the rules change)
var queued_hp := 1                ## HP after every beat already queued (the board books hits ahead)
var tf := 1.0                     ## personal timing factor (0.88 .. 1.14)
var arc := 1.0                    ## personal arc height factor
var hits_n := 1                   ## personal visual hit count for multi-strike move-sets
var prop_scale := Vector3.ONE     ## personal proportions
var lean := 0.0                   ## personal idle pose (statue tilt)
var body: Node3D
var visual: MeshInstance3D
var mat: ShaderMaterial
var plinth: MeshInstance3D
var emblem: Sprite3D
var shadow: MeshInstance3D
var ring: MeshInstance3D
var aura: CPUParticles3D
var tracks: Q.Tracks

# animated by tracks
var stone_h := STATUE
var crack := 0.0
var vein := 0.7
var cold := 0.0
var damage_v := 0.0
var shield_v := 0.0
var flash_v := 0.0
var shake_v := 0.0
var off := Vector3.ZERO           ## attack body offset (world)
var lift := 0.0
var spin := 0.0
var pitch := 0.0
var pop := 1.0
var grow := 1.0
var dissolve := 0.0
var hop_y := 0.0
var _t := 0.0
var _phase := 0.0
var _turn_hold := 0.0
var _last_base := Vector3.ZERO


## Builds the visuals for unit u (GameState.Unit). tex_override: tests inject a texture.
func setup(u, tex_override: Texture2D = null) -> void:
	uid = u.id
	side = u.owner
	family = str(u.family)
	unit_name = str(u.name)
	mon_id = str(u.mon_id)
	# cold grey only for ruins guardians; a freshly cracked monster is a team statue (dormant by rule)
	dormant = u.dormant and (int(u.cracked_round) if "cracked_round" in u else -1) < 0
	max_hp = maxi(1, int(u.max_hp))
	shown_hp = int(u.hp)
	seed = personal_seed(mon_id if mon_id != "" else unit_name)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	tf = rng.randf_range(0.88, 1.14)
	arc = rng.randf_range(0.75, 1.3)
	hits_n = 1 + rng.randi() % 3
	prop_scale = Vector3(rng.randf_range(0.9, 1.12), rng.randf_range(0.9, 1.14), rng.randf_range(0.9, 1.1))
	lean = rng.randf_range(-0.09, 0.09)
	_phase = float(uid % 13) * 0.7
	facing = Vector3(1, 0, 1).normalized() if side == 0 else Vector3(-1, 0, -1).normalized()
	tracks = Q.Tracks.new(self)
	body = Node3D.new()
	add_child(body)
	var team := Palette.side(side)
	var fam_col := Palette.family(family)
	var p := Creature.plan_for(unit_name, str(u.role))
	plan = p[0]
	variant = p[1]
	extras = Creature.extras_for(seed)
	var tex: Texture2D = tex_override if tex_override != null else Assets.monster(mon_id, family)
	if tex != null and not Assets.is_crop(tex):
		is_sprite = true
		var ts := Vector2(tex.get_size())
		height = 1.9
		model_h = height
		var q := QuadMesh.new()
		q.size = Vector2(height * ts.x / maxf(ts.y, 1.0), height)
		q.center_offset = Vector3(0, height * 0.42, 0)
		visual = MeshInstance3D.new()
		visual.mesh = q
		mat = Mats.sprite(tex, fam_col)
	else:
		var c := Creature.build(plan, variant, family, side, seed)
		height = c.height * SCALE
		model_h = c.height
		hover = c.hover * SCALE
		visual = MeshInstance3D.new()
		visual.mesh = c.mesh
		visual.scale = Vector3.ONE * SCALE
		mat = Mats.creature(fam_col.lerp(Color.WHITE, 0.3), Palette.MIDNIGHT_NAVY.lerp(fam_col, 0.25))
	mat.set_shader_parameter("vein_color", fam_col.lerp(Color.WHITE, 0.15))
	mat.set_shader_parameter("model_h", model_h)
	if mat.next_pass != null:
		mat.next_pass.set_shader_parameter("model_h", model_h)
	visual.material_override = mat
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(visual)
	shadow = _flat(0.75, Mats.blob(Color(0.02, 0.03, 0.06, 0.55)), 0.012)
	ring = _flat(0.96, Mats.blob(team, true), 0.022)
	plinth = MeshInstance3D.new()
	plinth.mesh = plinth_mesh(team)
	plinth.material_override = Mats.plinth()
	add_child(plinth)
	emblem = Sprite3D.new()
	emblem.texture = Assets.element_icon(family)
	emblem.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	emblem.pixel_size = 0.16 / maxf(1.0, float(emblem.texture.get_width())) if emblem.texture != null else 0.01
	emblem.no_depth_test = false
	emblem.shaded = false
	emblem.modulate = Color(1, 1, 1, 0.95)
	add_child(emblem)
	aura = _make_aura()
	body.add_child(aura)
	_apply_dormant_look()


## Stable per-monster seed (same monster -> same statue, pose and move-set variation).
static func personal_seed(key: String) -> int:
	return absi(hash(key)) % 1000003


## Round chess-piece base: wide foot, waist, top disc, team-coloured rim band (vertex colours).
static func plinth_mesh(team: Color) -> ArrayMesh:
	var k := Kit.new()
	var stone := Color(0.62, 0.6, 0.56)
	k.cylinder(0.37, 0.35, 0.0, 0.045, 16, stone.darkened(0.12), Vector2(0, 0))
	k.cylinder(0.36, 0.37, 0.045, 0.062, 16, team.lerp(Color.WHITE, 0.1), Vector2(0, 0.9))
	k.cylinder(0.3, 0.27, 0.062, 0.085, 16, stone, Vector2(0, 0))
	k.cylinder(0.31, 0.32, 0.085, PLINTH_H, 16, stone.lightened(0.08), Vector2(0, 0), true, stone.lightened(0.12))
	return k.commit()


func _flat(size: float, m: Material, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.material_override = m
	mi.position.y = y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _make_aura() -> CPUParticles3D:
	var a: Array = AURA.get(family, AURA["Arcane"])
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(a[6], a[6])
	p.mesh = q
	p.material_override = Mats.particle()
	p.amount = a[5]
	p.lifetime = a[4]
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.28
	p.position = Vector3(0, height * 0.5, 0)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = a[3] * 0.5
	p.initial_velocity_max = a[3]
	p.gravity = a[2]
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var g := Gradient.new()
	g.set_color(0, Color(a[0], 0.0))
	g.set_color(1, Color(a[1], 0.0))
	g.add_point(0.2, Color(a[0], 0.9))
	g.add_point(0.7, Color(Color(a[0]).lerp(a[1], 0.6), 0.6))
	p.color_ramp = g
	p.local_coords = false
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _apply_dormant_look() -> void:
	cold = 1.0 if dormant else 0.0
	vein = 0.0 if dormant else 0.7


## True while the monster stands as stone (not mid-transform).
func is_statue() -> bool:
	return stone_h >= 1.0 and not dying


## Move-set name for this monster's body plan.
func moveset() -> String:
	return str(MOVESET.get(plan, "charge"))


# ---------------------------------------------------------------- animation API (scaled time)

func snap_to(pos: Vector3) -> void:
	tracks.cancel("base")
	tracks.cancel("hop_y")
	base = pos
	hop_y = 0.0
	position = base
	_last_base = base


## Statue hop / slide along foot positions. Returns the landing times (for dust puffs + sounds).
func move_path(points: Array, step := 0.17) -> Array:
	if points.size() < 2:
		snap_to(points[-1] if not points.is_empty() else base)
		return []
	var bs: Array = []
	var hs: Array = []
	var lands: Array = []
	var t := 0.0
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var dy := absf(b.y - a.y)
		var up := 0.09 + (dy * 1.3 + 0.1 if dy > 0.04 else 0.0)
		bs.append([step, b, "io"])
		hs.append([step * 0.45, up, "out"])
		hs.append([step * 0.55, 0.0, "in"])
		t += step
		lands.append(t)
	base = points[0]
	tracks.seq("base", bs)
	tracks.seq("hop_y", hs)
	return lands


## Teleport (warp gate) — the board adds the bursts.
func warp_to(pos: Vector3) -> void:
	snap_to(pos)
	grow = 0.2
	tracks.to("grow", 1.0, 0.35, "out")


## Phase 1: element light cracks race up the stone (dormant guardians shake while they do).
func crack_up(dur: float) -> void:
	tracks.to("crack", 1.0, dur, "in")
	if dormant:
		tracks.seq("shake_v", [[dur * 0.8, 0.6, "in"], [dur * 0.2, 1.0]])


## Phase 2+3: the stone shell is gone; the live monster rears up in a roar pose.
func shatter() -> void:
	stone_h = 0.0
	crack = 0.0
	shake_v = 0.0
	if dormant:
		dormant = false
		cold = 0.0
	flash_v = 0.55
	tracks.to("flash_v", 0.0, 0.35, "out")
	tracks.seq("pop", [[0.08, 1.16, "out"], [0.26, 1.0, "io"]])
	tracks.seq("lift", [[0.12, 0.16 * arc, "out"], [0.22, 0.0, "io"]])
	tracks.seq("pitch", [[0.12, 0.28, "out"], [0.22, 0.0, "io"]])
	if aura != null:
		aura.emitting = true
		aura.restart()


## Phase 4: this monster's archetype move-set toward a world point. Returns {release: [times],
## dur} relative to now (scaled by the personal timing factor). Only the body moves; feet stay.
func attack_move(target: Vector3, ranged: bool, speed := 1.0) -> Dictionary:
	var d := target - base
	d.y = 0
	if d.length() > 0.01:
		facing = d.normalized()
	_turn_hold = 3.0
	var reach := clampf(d.length() - 0.55, 0.25, 1.5)
	if ranged:
		reach = minf(reach, 0.35)
	var spec := move_spec(facing, reach, speed)
	for prop in spec.tracks:
		tracks.seq(prop, spec.tracks[prop])
	if spec.tracks.has("spin"):
		spin = 0.0
	return spec


## Timing of this monster's move-set without playing it (the board schedules impacts from it).
func move_timing(speed := 1.0) -> Dictionary:
	return move_spec(Vector3.RIGHT, 1.0, speed)


## The move-set as track segments: {tracks: {prop: segs}, release: [t...], dur}.
## Archetype (body plan) x personal timing (tf), arc height (arc) and hit count (hits_n).
func move_spec(f: Vector3, reach: float, speed := 1.0) -> Dictionary:
	var k := tf / maxf(speed, 0.1)
	var tr := {}
	var rel: Array = []
	var dur := 0.0
	match moveset():
		"charge":   # stag / hound / beast: wind back, charge, return
			tr["off"] = [[0.12 * k, -f * 0.16, "out"], [0.11 * k, f * reach * 0.8, "in"], [0.07 * k, f * reach * 0.8], [0.22 * k, Vector3.ZERO]]
			tr["pitch"] = [[0.12 * k, 0.12, "out"], [0.11 * k, -0.18, "in"], [0.29 * k, 0.0]]
			rel = [0.23 * k]
			dur = 0.52 * k
		"coil":     # wyrm / drake: coil back low, whip-strike forward and up
			tr["off"] = [[0.18 * k, -f * 0.22, "out"], [0.08 * k, f * reach * 0.85, "in"], [0.1 * k, f * reach * 0.85], [0.24 * k, Vector3.ZERO]]
			tr["lift"] = [[0.18 * k, -0.04, "out"], [0.08 * k, 0.16 * arc, "in"], [0.34 * k, 0.0]]
			tr["pitch"] = [[0.18 * k, 0.3, "out"], [0.08 * k, -0.25, "in"], [0.34 * k, 0.0]]
			rel = [0.26 * k]
			dur = 0.6 * k
		"dive":     # phoenix / bird: soar up and back, dive onto the target, glide home
			tr["off"] = [[0.24 * k, -f * 0.2, "out"], [0.12 * k, f * reach * 0.9, "in"], [0.05 * k, f * reach * 0.9], [0.28 * k, Vector3.ZERO]]
			tr["lift"] = [[0.24 * k, 0.85 * arc, "out"], [0.12 * k, 0.05, "in"], [0.05 * k, 0.05], [0.28 * k, 0.0]]
			tr["pitch"] = [[0.24 * k, 0.25, "out"], [0.12 * k, -0.6, "in"], [0.33 * k, 0.0]]
			rel = [0.36 * k]
			dur = 0.69 * k
		"slam":     # golem / colossus: heave up, slam the ground (shock travels to the target)
			tr["lift"] = [[0.22 * k, 0.38 * arc, "out"], [0.07 * k, -0.02, "in"], [0.12 * k, -0.02], [0.2 * k, 0.0]]
			tr["pitch"] = [[0.22 * k, 0.22, "out"], [0.07 * k, -0.3, "in"], [0.32 * k, 0.0]]
			tr["pop"] = [[0.22 * k, 1.06], [0.07 * k, 0.94, "in"], [0.32 * k, 1.0]]
			rel = [0.29 * k]
			dur = 0.61 * k
		"ram":      # beetle / bug: low, rapid rams — one per personal hit
			var segs: Array = [[0.1 * k, -f * 0.12, "out"]]
			var t := 0.1 * k
			for i in hits_n:
				segs.append([0.07 * k, f * reach * 0.7, "in"])
				t += 0.07 * k
				rel.append(t)
				segs.append([0.08 * k, f * reach * 0.25, "out"])
				t += 0.08 * k
			segs.append([0.18 * k, Vector3.ZERO])
			tr["off"] = segs
			tr["pitch"] = [[0.1 * k, -0.15], [t - 0.1 * k, -0.15], [0.18 * k, 0.0]]
			dur = t + 0.18 * k
		"spincast": # sprite / orb / floater: rise, spin and cast
			tr["lift"] = [[0.16 * k, 0.28 * arc, "out"], [0.3 * k, 0.28 * arc], [0.2 * k, 0.0]]
			tr["spin"] = [[0.42 * k, TAU * (1 + hits_n % 2), "io"]]
			rel = [0.3 * k]
			dur = 0.66 * k
		_:          # "bounce" — hopper / bun: hop arc onto the target, bounce home
			tr["off"] = [[0.17 * k, f * reach * 0.85, "lin"], [0.06 * k, f * reach * 0.85], [0.2 * k, Vector3.ZERO, "lin"]]
			tr["lift"] = [[0.1 * k, 0.5 * arc, "out"], [0.07 * k, 0.02, "in"], [0.06 * k, 0.0], [0.1 * k, 0.3 * arc, "out"], [0.1 * k, 0.0, "in"]]
			rel = [0.17 * k]
			dur = 0.43 * k
	return {"tracks": tr, "release": rel, "dur": dur}


## Phase 5: turns back to stone from the feet up.
func repetrify(dur := 0.6) -> void:
	tracks.cancel("stone_h")
	stone_h = 0.0
	tracks.to("stone_h", STATUE, dur, "lin")
	if aura != null:
		aura.emitting = false
	vein = 0.0
	tracks.to("vein", 0.7, dur * 1.5, "in")


## A hit on this monster (statue or live): flash, shudder, crack decals toward the new HP.
func hit(new_hp: int) -> void:
	shown_hp = new_hp
	flash_v = 0.8
	tracks.to("flash_v", 0.0, 0.3, "out")
	shake_v = 1.0
	tracks.to("shake_v", 0.0, 0.3, "out")
	tracks.to("damage_v", hp_damage(), 0.25, "out")


func heal_to(new_hp: int) -> void:
	shown_hp = new_hp
	tracks.to("damage_v", hp_damage(), 0.4, "out")


## Crack-decal amount for the shown HP (0 = unharmed, 1 = about to crumble).
func hp_damage() -> float:
	return clampf(1.0 - float(shown_hp) / float(maxi(1, max_hp)), 0.0, 1.0)


func shield_flare() -> void:
	tracks.seq("shield_v", [[0.12, 1.0, "out"], [0.4, 0.55]])


## KO: the statue crumbles (the board drops the rubble pile); the actor fades out.
func crumble(dur := 0.4) -> void:
	dying = true
	stone_h = STATUE
	crack = 0.0
	if aura != null:
		aura.emitting = false
	tracks.to("dissolve", 1.0, dur, "in")
	tracks.seq("lift", [[dur, -0.25, "in"]])


## Summon: the statue materialises out of light on its plinth.
func materialise(dur := 0.45) -> void:
	visible = true
	dissolve = 1.0
	grow = 0.7
	tracks.to("dissolve", 0.0, dur, "out")
	tracks.to("grow", 1.0, dur, "back")


## Lichen / moss on painted statues (Verdant-type towers).
func set_moss(v: float) -> void:
	if is_sprite:
		mat.set_shader_parameter("moss", v)


## Ends every running animation in its rest pose (statue unless dying).
func settle() -> void:
	tracks.settle()
	off = Vector3.ZERO
	lift = 0.0
	spin = 0.0
	pitch = 0.0
	pop = 1.0
	grow = 1.0
	hop_y = 0.0
	crack = 0.0
	shake_v = 0.0
	flash_v = 0.0
	if not dying:
		stone_h = STATUE
		dissolve = 0.0
		visible = true
		vein = 0.0 if dormant else 0.7
		cold = 1.0 if dormant else 0.0
	damage_v = hp_damage()
	if aura != null:
		aura.emitting = false


## Head point for the HP bar (world space).
func head_world() -> Vector3:
	return global_position + Vector3(0, PLINTH_H + hover + height * prop_scale.y * maxf(grow, 0.3) + 0.14 + lift, 0) + off


## World point at the monster's chest (VFX origin).
func chest_world() -> Vector3:
	return global_position + Vector3(0, PLINTH_H + hover + height * 0.5 + lift, 0) + off


## Per-frame update with board-scaled time. cam_dir = horizontal direction from the board to the camera.
func tick(delta: float, cam_dir: Vector3) -> void:
	_t += delta
	tracks.step(delta)
	var live := stone_h < 0.5
	var bob := sin(_t * 2.3 + _phase) * (0.035 if hover > 0.0 else 0.018) if live else 0.0
	var breathe := sin(_t * 2.3 + _phase + 0.6) * 0.025 if live else 0.0
	var jitter := Vector3(sin(_t * 70.0), 0, cos(_t * 63.0)) * 0.045 * shake_v
	position = base + Vector3(0, hop_y, 0)
	var mv := base - _last_base
	mv.y = 0
	if mv.length() > 0.002:
		facing = mv.normalized()
		_turn_hold = 0.4
	_last_base = base
	body.position = Vector3(0, PLINTH_H + hover + bob + lift, 0) + off + jitter
	_turn_hold = maxf(0.0, _turn_hold - delta)
	if _turn_hold <= 0.0:
		var toward := Vector3(cam_dir.x, 0, cam_dir.z).normalized()
		var right := (-toward).cross(Vector3.UP).normalized()
		var want := (right * (1.0 if side == 0 else -1.0) + toward * 0.75).normalized()
		facing = facing.lerp(want, minf(1.0, delta * 5.0)).normalized()
	var g := grow * pop
	body.scale = Vector3(prop_scale.x * g, prop_scale.y * g * (1.0 + breathe), prop_scale.z * g)
	if is_sprite:
		body.rotation = Vector3(-0.16, atan2(cam_dir.x, cam_dir.z) + spin, lean * 0.5 if not live else 0.0)
	else:
		body.rotation = Vector3(0, atan2(-facing.z, facing.x) + spin, pitch + (lean if not live else 0.0))
	var sat := 0.55 if spent and live else 1.0
	mat.set_shader_parameter("flash", flash_v)
	mat.set_shader_parameter("sat", sat)
	mat.set_shader_parameter("dissolve", dissolve)
	mat.set_shader_parameter("stone_h", stone_h)
	mat.set_shader_parameter("crack", crack)
	mat.set_shader_parameter("vein", vein)
	mat.set_shader_parameter("cold", cold)
	mat.set_shader_parameter("damage", damage_v)
	mat.set_shader_parameter("shield", maxf(shield_v, 0.55 if defending else 0.0))
	if mat.next_pass != null:
		mat.next_pass.set_shader_parameter("dissolve", dissolve)
		mat.next_pass.set_shader_parameter("flash", flash_v)
		mat.next_pass.set_shader_parameter("stone_h", stone_h)
	var fade := 1.0 - dissolve
	(ring.material_override as ShaderMaterial).set_shader_parameter("fade", fade * (0.4 if dormant else 1.0))
	(shadow.material_override as ShaderMaterial).set_shader_parameter("fade", fade)
	plinth.visible = fade > 0.05
	plinth.scale = Vector3.ONE * clampf(grow, 0.0, 1.0)
	emblem.visible = fade > 0.3
	emblem.position = Vector3(cam_dir.x, 0, cam_dir.z).normalized() * 0.33 + Vector3(0, 0.07, 0)
