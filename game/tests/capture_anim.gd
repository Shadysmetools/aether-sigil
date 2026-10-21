## Windowed stills of the statue / transform presentation (not a test; needs a real renderer).
## Run: Godot.exe --path game --resolution 1080x1920 --script res://tests/capture_anim.gd -- <out_dir> [--fps=6]
## Staging (disclosed): the battle is advanced with AI turns (instant presentation), then our active
## monster is placed next to a rival (direct position edit) so the attack lands on screen; the attack,
## skill and KO themselves go through the real rules (GameState.attack / skill, forced hit). The
## presentation is stepped manually at 30 fps so each still lands on a phase:
##   transform-1-crack, -2-shatter, -3-live, -4-attack, -5-repetrify, cutin, ko-crumble, summon-vessel,
##   summon-statue. --art-root=<dir> points the asset resolver's painted-art root at <dir> (a folder
##   with monsters/<id or family>.png cut-outs) and prefixes the stills "painted-". --fps=N measures the frame rate over N seconds of repeated transforms (uncapped).
extends SceneTree

const GameState = preload("res://scripts/game_state.gd")
const AI = preload("res://scripts/ai.gd")
const SAVE := "user://capture_anim_save.json"
const Assets = preload("res://scripts/assets.gd")

var out := "user://"
var prefix := ""
var main: Node
var board


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func snap(name: String) -> void:
	await process_frame
	var img := root.get_texture().get_image()
	var path := out.path_join("%s%s.png" % [prefix, name])
	img.save_png(path)
	print("saved ", path)


## Steps the presentation by `sec` (30 fps steps, one rendered frame each).
func play(sec: float) -> void:
	var n := int(round(sec * 30.0))
	for i in n:
		board.anim_step(1.0 / 30.0)
		await process_frame


## Plays until a beat whose name starts with `prefix` is playing.
func until_beat(prefix: String) -> void:
	for i in 300:
		if board.anim.now_playing().begins_with(prefix):
			return
		board.anim_step(1.0 / 30.0)
		await process_frame


## Plays the current beat up to time t (seconds since it started).
func play_to(t: float) -> void:
	while board.anim.current != null and board.anim.t < t - 0.001:
		board.anim_step(1.0 / 30.0)
		await process_frame


func _run() -> void:
	var fps_secs := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fps="):
			fps_secs = float(a.trim_prefix("--fps="))
		elif a.begins_with("--art-root="):
			Assets.ai_root = a.trim_prefix("--art-root=")
			Assets.dev_root = ""
			Assets.clear_cache()
			prefix = "painted-"
		elif out == "user://":
			out = a
	DirAccess.make_dir_recursive_absolute(out)
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	main = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	root.add_child(main)
	await process_frame
	main._on_dialogue_skip()
	main.start_stage("T01-L01")
	await _frames(3)
	main._on_dialogue_skip()
	board = main.board
	var s: GameState = main.state
	board.anim.instant = true
	for guard in 200:
		if s.winner != GameState.NONE:
			break
		if s.current == GameState.PLAYER and not s.is_sigil_turn() and s.round_num >= 2:
			break
		AI.take_activation(s, s.current, "balanced" if s.current == GameState.PLAYER else str(s.stage.opponent_style))
	board.sync()
	main.ai_running = false
	await _frames(5)
	board.anim.instant = false
	board.manual_step = true
	var u: GameState.Unit = s.actor_unit()
	var foe: GameState.Unit = _foe_near(s, u)
	if u == null or foe == null:
		print("no attacker / foe; abort")
		quit(1)
		return
	_place_next_to(s, u, foe)
	board.sync()
	await play(1.0)
	main.mode = main.Mode.NONE
	main._refresh("%s attacks %s" % [u.name, foe.name])
	main.board.highlights = {}
	await _frames(10)
	s.force_hit = 1
	print("attack: %s (%s, %s) -> %s" % [u.name, u.family, board.actors[u.id].moveset(), foe.name])
	s.attack(GameState.PLAYER, u.id, foe.pos)
	board.sync()
	await until_beat("transform")
	await play_to(0.42)
	await snap("transform-1-crack")
	await play_to(0.62)
	await snap("transform-2-shatter")
	await play_to(0.86)
	await snap("transform-3-live")
	await play_to(1.12)
	await snap("transform-4-attack")
	await play_to(1.72)
	await snap("transform-5-repetrify")
	await play(1.5)
	# skill cut-in: the next player activation that has a skill target
	board.anim.instant = true
	var tries := 0
	while tries < 60 and s.winner == GameState.NONE:
		tries += 1
		if s.current == GameState.PLAYER and not s.is_sigil_turn():
			var su: GameState.Unit = s.actor_unit()
			if su != null and not s.legal_skill_targets(su).is_empty() and s.skill_def(su).type != "blink":
				break
		AI.take_activation(s, s.current, "balanced")
	board.sync()
	board.anim.instant = false
	await play(0.5)
	var su2: GameState.Unit = s.actor_unit()
	if su2 != null and s.current == GameState.PLAYER and not s.legal_skill_targets(su2).is_empty():
		print("skill: %s uses %s" % [su2.name, su2.ability])
		s.skill(GameState.PLAYER, su2.id, s.legal_skill_targets(su2)[0])
		board.sync()
		await play(0.3)
		await snap("cutin")
		await play(3.0)
	# KO: our next activation finishes a weakened rival (rival HP lowered: disclosed staging)
	board.anim.instant = true
	tries = 0
	while tries < 60 and s.winner == GameState.NONE and not (s.current == GameState.PLAYER and not s.is_sigil_turn()):
		tries += 1
		AI.take_activation(s, s.current, "balanced")
	board.sync()
	board.anim.instant = false
	await play(0.5)
	var ku: GameState.Unit = s.actor_unit()
	var kf: GameState.Unit = _foe_near(s, ku) if ku != null else null
	if ku != null and kf != null:
		_place_next_to(s, ku, kf)
		board.sync()
		await play(1.0)
		kf.hp = 1
		board._snap[kf.id].hp = 1
		board.actors[kf.id].shown_hp = 1
		board.actors[kf.id].queued_hp = 1
		print("ko: %s -> %s" % [ku.name, kf.name])
		s.attack(GameState.PLAYER, ku.id, kf.pos)
		board.sync()
		var t := 0.0
		var crumbled := false
		while t < 4.0 and board.anim_busy():
			await play(1.0 / 30.0)
			t += 1.0 / 30.0
			if not crumbled and board.juice.crumbles > 0:
				crumbled = true
				await play(0.15)
				await snap("ko-crumble")
		await play(1.0)
	# summon: a fresh unit through the hook, with an SP cost
	var spot := Vector2i(-1, -1)
	for y in range(0, 4):
		for x in range(0, 12):
			var c := Vector2i(x, y)
			if s.is_walkable(c) and s.unit_at(c) == null:
				spot = c
		if spot != Vector2i(-1, -1):
			break
	var nu := GameState.Unit.new()
	var any: GameState.Unit = s.units[0]
	nu.id = 9001
	nu.mon_id = any.mon_id
	nu.name = any.name + " II"
	nu.family = any.family
	nu.role = any.role
	nu.owner = 0
	nu.pos = spot
	nu.max_hp = 100
	nu.hp = 100
	s.units.append(nu)
	board.play_summon(nu, 3)
	await play(0.62)
	await snap("summon-vessel")
	await play(0.6)
	await snap("summon-statue")
	await play(1.0)
	s.units.erase(nu)
	board.sync()
	await play(0.5)
	print("juice ", board.juice)
	if fps_secs > 0.0:
		board.manual_step = false
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		var fr := [0]
		var t0 := Time.get_ticks_msec()
		process_frame.connect(func(): fr[0] += 1)
		while Time.get_ticks_msec() - t0 < int(fps_secs * 1000.0):
			# keep transforms running: replay an attack whenever the queue is idle
			if not board.anim_busy():
				var a: GameState.Unit = null
				var b: GameState.Unit = null
				for x in s.units:
					if x.owner == 0 and a == null:
						a = x
					if x.owner == 1 and b == null:
						b = x
				if a != null and b != null:
					s.events.append("%s uses Test Skill" % a.name)
					s.events.append("%s hits %s for 1" % [a.name, b.name])
					b.hp -= 1
			await process_frame
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		print("FPS %.1f over %.1fs during transforms" % [fr[0] / secs, secs])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)


func _foe_near(s: GameState, u: GameState.Unit) -> GameState.Unit:
	var best: GameState.Unit = null
	var bd := 999
	for e in s.units:
		if e.owner != u.owner and not e.dormant:
			var d := GameState.manhattan(e.pos, u.pos)
			if d < bd:
				bd = d
				best = e
	if best == null:
		for e in s.units:
			if e.owner != u.owner:
				return e
	return best


func _place_next_to(s: GameState, u: GameState.Unit, foe: GameState.Unit) -> void:
	for d in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1)]:
		var c: Vector2i = foe.pos + d
		if GameState.in_bounds(c) and s.is_walkable(c) and (s.unit_at(c) == null or s.unit_at(c) == u):
			u.pos = c
			return
