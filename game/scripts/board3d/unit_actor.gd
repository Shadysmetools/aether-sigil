## One monster standing on the 3D board: painted cut-out billboard (Assets.monster with real alpha)
## or a procedural creature (creature.gd), with contact shadow, team ring, element aura particles and
## the animations the board triggers (move with hops, lunge, hit flash + shake, faint dissolve,
## summon, awaken). Presentation only: the board tells it what happened; it never reads rules.
extends Node3D

const Mats = preload("res://scripts/board3d/mats.gd")
const Creature = preload("res://scripts/board3d/creature.gd")
const Assets = preload("res://scripts/assets.gd")
const Palette = preload("res://scripts/theme_colors.gd")

## Aura per element family: [colour a, colour b, gravity, initial speed, lifetime, amount, size].
const SCALE := 2.0   ## creatures stand ~1-1.3 tiles tall, like the concept sheet

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

var uid := -1
var side := 0
var family := ""
var unit_name := ""
var is_sprite := false
var height := 0.7
var hover := 0.0
var base := Vector3.ZERO          ## feet position on the tile (moves with tweens)
var facing := Vector3(1, 0, 1)
var dormant := false
var spent := false
var dying := false
var body: Node3D
var visual: MeshInstance3D
var mat: ShaderMaterial
var shadow: MeshInstance3D
var ring: MeshInstance3D
var aura: CPUParticles3D
var _t := 0.0
var _phase := 0.0
var _flash := 0.0
var _shake := 0.0
var _lunge := Vector3.ZERO
var _dissolve := 0.0
var _grow := 1.0
var _move: Tween
var _fx: Tween
var _turn_hold := 0.0             ## seconds to keep a move / attack facing before turning back


## Builds the visuals for unit u (GameState.Unit). tex_override: tests inject a texture.
func setup(u, tex_override: Texture2D = null) -> void:
	uid = u.id
	side = u.owner
	family = str(u.family)
	unit_name = str(u.name)
	dormant = u.dormant
	_phase = float(uid % 13) * 0.7
	facing = Vector3(1, 0, 1).normalized() if side == 0 else Vector3(-1, 0, -1).normalized()
	body = Node3D.new()
	add_child(body)
	var team := Palette.side(side)
	var fam_col := Palette.family(family)
	var tex: Texture2D = tex_override if tex_override != null else Assets.monster(str(u.mon_id), family)
	if tex != null and not Assets.is_crop(tex):
		is_sprite = true
		var ts := Vector2(tex.get_size())
		height = 1.9
		var q := QuadMesh.new()
		q.size = Vector2(height * ts.x / maxf(ts.y, 1.0), height)
		q.center_offset = Vector3(0, height * 0.42, 0)
		visual = MeshInstance3D.new()
		visual.mesh = q
		mat = Mats.sprite(tex, fam_col)
	else:
		var plan := Creature.plan_for(unit_name, str(u.role))
		var c := Creature.build(plan[0], plan[1], family, side)
		height = c.height * SCALE
		hover = c.hover * SCALE
		visual = MeshInstance3D.new()
		visual.mesh = c.mesh
		visual.scale = Vector3.ONE * SCALE
		mat = Mats.creature(fam_col.lerp(Color.WHITE, 0.3), Palette.MIDNIGHT_NAVY.lerp(fam_col, 0.25))
	visual.material_override = mat
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(visual)
	shadow = _flat(0.75, Mats.blob(Color(0.02, 0.03, 0.06, 0.55)), 0.012)
	ring = _flat(0.96, Mats.blob(team, true), 0.022)
	aura = _make_aura()
	body.add_child(aura)


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
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


# ---------------------------------------------------------------- animation API

func snap_to(pos: Vector3) -> void:
	if _move != null and _move.is_valid():
		_move.kill()
	base = pos
	position = base


## Walks a path of foot positions; hops when the height changes (stairs, high ground).
func move_path(points: Array, total := 0.32) -> void:
	if _move != null and _move.is_valid():
		_move.kill()
	if points.size() < 2:
		snap_to(points[-1] if not points.is_empty() else base)
		return
	_move = create_tween()
	var step := clampf(total / (points.size() - 1), 0.05, 0.12)
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var dy := absf(b.y - a.y)
		var hop := 0.05 + (dy * 1.4 + 0.12 if dy > 0.04 else 0.0)
		_move.tween_method(_hop.bind(a, b, hop), 0.0, 1.0, step)


func _hop(f: float, a: Vector3, b: Vector3, hop: float) -> void:
	base = a.lerp(b, f) + Vector3(0, hop * 4.0 * f * (1.0 - f), 0)
	var d := b - a
	d.y = 0
	if d.length() > 0.01:
		facing = d.normalized()
		_turn_hold = 0.5


## Teleport (warp gate) — fade out / in handled by the board's bursts.
func warp_to(pos: Vector3) -> void:
	snap_to(pos)
	_grow = 0.2


func lunge_at(target: Vector3) -> void:
	var d := target - (base if base != Vector3.ZERO else position)
	d.y = 0
	if d.length() < 0.01:
		return
	facing = d.normalized()
	_turn_hold = 0.6
	var tw := create_tween()
	tw.tween_property(self, "_lunge", facing * 0.32, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_lunge", Vector3.ZERO, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func hit() -> void:
	_flash = 1.0
	_shake = 1.0


func cast() -> void:
	_flash = 0.6
	if aura != null:
		aura.restart()


func summon() -> void:
	_grow = 0.0
	_dissolve = 0.9


func awaken() -> void:
	_flash = 1.0
	_grow = 0.6


## Fades out with a glowing dissolve, then frees itself.
func faint() -> void:
	dying = true
	if aura != null:
		aura.emitting = false
	_fx = create_tween()
	_fx.tween_property(self, "_dissolve", 1.0, 0.7)
	_fx.tween_callback(queue_free)


## Head point for the HP bar (world space).
func head_world() -> Vector3:
	return global_position + Vector3(0, hover + height * maxf(_grow, 0.3) + 0.14, 0) + _lunge


## Per-frame update. cam_dir = horizontal direction from the board toward the camera.
func tick(delta: float, cam_dir: Vector3) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta * 4.0)
	_shake = maxf(0.0, _shake - delta * 3.5)
	_grow = minf(1.0, _grow + delta * 2.6)
	if not dying:
		_dissolve = maxf(0.0, _dissolve - delta * 2.2)
	var bob := 0.0 if dormant else sin(_t * 2.3 + _phase) * (0.035 if hover > 0.0 else 0.018)
	var breathe := 0.0 if dormant else sin(_t * 2.3 + _phase + 0.6) * 0.025
	var jitter := Vector3(sin(_t * 70.0), 0, cos(_t * 63.0)) * 0.05 * _shake
	position = base
	body.position = Vector3(0, hover + bob, 0) + _lunge + jitter
	# idle pose: three-quarter view toward the camera, allies facing screen-right, rivals screen-left
	_turn_hold = maxf(0.0, _turn_hold - delta)
	if _turn_hold <= 0.0:
		var toward := Vector3(cam_dir.x, 0, cam_dir.z).normalized()
		var right := (-toward).cross(Vector3.UP).normalized()
		var want := (right * (1.0 if side == 0 else -1.0) + toward * 0.75).normalized()
		facing = facing.lerp(want, minf(1.0, delta * 5.0)).normalized()
	var g := _grow
	body.scale = Vector3(g, g * (1.0 + breathe), g)
	if is_sprite:
		body.rotation.y = atan2(cam_dir.x, cam_dir.z)
	else:
		body.rotation.y = atan2(-facing.z, facing.x)
	var sat := 0.0 if dormant else (0.55 if spent else 1.0)
	mat.set_shader_parameter("flash", _flash)
	mat.set_shader_parameter("sat", sat)
	mat.set_shader_parameter("dissolve", _dissolve)
	mat.set_shader_parameter("tint", Color(0.82, 0.82, 0.86) if dormant else (Color(0.82, 0.82, 0.9) if spent else Color.WHITE))
	if mat.next_pass != null:
		mat.next_pass.set_shader_parameter("dissolve", _dissolve)
		mat.next_pass.set_shader_parameter("flash", _flash)
	if aura != null:
		aura.emitting = not dormant and not dying
	var fade := 1.0 - _dissolve
	(ring.material_override as ShaderMaterial).set_shader_parameter("fade", fade * (0.45 if dormant else 1.0))
	(shadow.material_override as ShaderMaterial).set_shader_parameter("fade", fade)
