## Statue / transform presentation (board_3d.gd + board3d/anim_queue.gd, unit_actor.gd, fx.gd):
## the beat queue (instant when headless, ordered cues, skip / flush settle), the full attack
## transform phases and its return to stone, the quick transform staying <= 1.2 s, KO crumble
## leaving no orphan nodes, reduced_motion disabling shake / flash / slow-mo, the 3 Hz flash cap,
## skill cut-ins, play_summon (cost popup, one sequence per unit), play_vessel_break, and that every
## bible monster gets its own statue / move-set signature. Rule events are fed exactly as GameState
## logs them. Exits with the failure count.
extends SceneTree

const GameState = preload("res://scripts/game_state.gd")
const Data = preload("res://scripts/data_loader.gd")
const Board3D = preload("res://scripts/board_3d.gd")
const AnimQ = preload("res://scripts/board3d/anim_queue.gd")
const Actor = preload("res://scripts/board3d/unit_actor.gd")
const Creature = preload("res://scripts/board3d/creature.gd")
const FX = preload("res://scripts/board3d/fx.gd")
const Assets = preload("res://scripts/assets.gd")

const BAND := Rect2(16, 520, 1048, 1060)
const SETTING := "aether_sigil/accessibility/reduced_motion"

var passed := 0
var failed := 0


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("  PASS  ", label)
	else:
		failed += 1
		print("  FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("Aether Sigil statue / transform animation test")
	Data.ensure_loaded()
	test_queue()
	await test_instant_board()
	await test_transform()
	await test_ko_orphans()
	await test_reduced_motion()
	await test_summon_and_vessel()
	test_personal()
	print("%d pass / %d fail" % [passed, failed])
	quit(mini(failed, 255))


# ---------------------------------------------------------------- queue

func test_queue() -> void:
	print("[animation queue]")
	var trail: Array = []
	var q := AnimQ.new()
	q.instant = true
	q.push({"name": "a", "dur": 5.0, "cues": [[0.0, func(): trail.append("cue")]], "end": func(): trail.append("end")})
	check(not q.busy() and trail == ["end"], "instant queue: push settles at once (end only, no waiting) %s" % str(trail))
	trail.clear()
	q = AnimQ.new()
	q.push({"name": "a", "dur": 1.0, "cues": [[0.5, func(): trail.append("a2")], [0.0, func(): trail.append("a1")]], "end": func(): trail.append("a_end")})
	q.push({"name": "b", "dur": 1.0, "cues": [[0.0, func(): trail.append("b1")]], "end": func(): trail.append("b_end")})
	q.step(0.1)
	check(trail == ["a1"] and q.now_playing() == "a", "beats play one at a time, cues in time order")
	q.step(1.0)
	q.step(0.01)
	check(trail == ["a1", "a2", "a_end", "b1"], "a beat ends after its duration, then the next starts %s" % str(trail))
	q.skip()
	check(trail[-1] == "b_end" and not q.busy(), "skip() settles the playing beat")
	q.push({"name": "c", "dur": 1.0, "cues": [], "end": func(): trail.append("c_end")})
	q.push({"name": "d", "dur": 1.0, "cues": [], "end": func(): trail.append("d_end")})
	q.flush()
	check(trail.slice(-2) == ["c_end", "d_end"] and not q.busy(), "flush() settles every queued beat in order")
	var obj := Actor.new()
	var tr := AnimQ.Tracks.new(obj)
	tr.seq("lift", [[0.5, 1.0, "lin"], [0.5, 0.0, "lin"]])
	tr.step(0.25)
	var mid := obj.lift
	tr.step(0.5)
	check(is_equal_approx(mid, 0.5) and is_equal_approx(obj.lift, 0.5), "tracks tween through segments on scaled time (%.2f, %.2f)" % [mid, obj.lift])
	tr.settle()
	check(obj.lift == 0.0 and not tr.busy(), "settle() jumps tracks to their end value")
	obj.free()


# ---------------------------------------------------------------- helpers

func _unit(id: int, mon_id: String, owner: int, pos: Vector2i) -> GameState.Unit:
	var d := Data.monster(mon_id)
	var u := GameState.Unit.new()
	u.id = id
	u.mon_id = mon_id
	u.name = str(d.name)
	u.family = str(d.element_family)
	u.element = str(d.get("element", d.element_family))
	u.role = str(d.role)
	u.owner = owner
	u.pos = pos
	u.max_hp = 120
	u.hp = 120
	u.ability = "Test Skill"
	return u


## A 3D board on T01-L01 with two monsters face to face (player at (5,5), rival at (6,5)).
func _board(instant: bool) -> Array:
	var b = Board3D.new()
	root.add_child(b)
	await process_frame
	var s := GameState.new()
	s.setup("T01-L01")
	s.units.clear()
	var ids := Data.monster_ids()
	var a := _unit(501, str(ids[0]), 0, Vector2i(5, 5))
	var t := _unit(502, str(ids[7 % ids.size()]), 1, Vector2i(6, 5))
	s.units.append(a)
	s.units.append(t)
	b.state = s
	b.anim.instant = instant
	b.manual_step = true
	b.fit_band(BAND)
	b.sync()
	return [b, s, a, t]


func _hit(s: GameState, a: GameState.Unit, t: GameState.Unit, dmg: int) -> void:
	t.hp -= dmg
	s.events.append("%s hits %s for %d" % [a.name, t.name, dmg])


## Steps the board's presentation at 30 fps until idle; returns seconds simulated.
func _drain(b, watch: Callable = Callable(), limit := 12.0) -> float:
	var t := 0.0
	while b.anim_busy() and t < limit:
		b.anim_step(1.0 / 30.0)
		t += 1.0 / 30.0
		if watch.is_valid():
			watch.call()
	return t


# ---------------------------------------------------------------- tests

func test_instant_board() -> void:
	print("[instant in headless]")
	var r: Array = await _board(true)
	var b = r[0]
	check(b.anim.instant == true or DisplayServer.get_name() != "headless", "the board's queue is instant when headless")
	b.anim.instant = true
	var s: GameState = r[1]
	_hit(s, r[2], r[3], 30)
	var busy: bool = b.anim_busy()
	var t: Actor = b.actors[502]
	check(not busy and t.shown_hp == 90, "a hit settles in the same frame: queue idle, shown HP %d" % t.shown_hp)
	check(t.is_statue() and b.actors[501].is_statue(), "both monsters stand as statues after the instant transform")
	check(b.juice.shakes == 0 and b.juice.flashes == 0, "no shake / flash in instant mode")
	b.queue_free()
	await process_frame


func test_transform() -> void:
	print("[transform sequence: crack -> shatter -> live -> attack -> re-petrify]")
	var r: Array = await _board(false)
	var b = r[0]
	var s: GameState = r[1]
	var au: GameState.Unit = r[2]
	var tu: GameState.Unit = r[3]
	var a: Actor = b.actors[501]
	var t: Actor = b.actors[502]
	check(a.is_statue() and a.stone_h >= 1.0, "monsters start as stone statues (stone_h %.2f)" % a.stone_h)
	_hit(s, au, tu, 30)
	var seen := {"crack": 0.0, "live": false, "moved": false, "hp_drop_at": -1.0, "live_at": -1.0, "name": ""}
	var clock := [0.0]
	var shown_before: int = t.shown_hp
	var dur := _drain(b, func():
		clock[0] += 1.0 / 30.0
		if seen.name == "":
			seen.name = b.anim.now_playing()
		seen.crack = maxf(seen.crack, a.crack)
		if a.stone_h < 0.05 and not seen.live:
			seen.live = true
			seen.live_at = clock[0]
		if a.off.length() > 0.05 or a.lift > 0.05 or absf(a.spin) > 0.1 or absf(a.pitch) > 0.1:
			seen.moved = true
		if t.shown_hp < shown_before and seen.hp_drop_at < 0.0:
			seen.hp_drop_at = clock[0])
	check(seen.name == "transform_full", "a monster's first attack plays the full transform (%s)" % seen.name)
	check(seen.crack > 0.9, "phase 1: element cracks race over the stone (crack %.2f)" % seen.crack)
	check(seen.live, "phase 2-3: the stone shatters and the live monster appears (stone_h -> 0 at %.2fs)" % seen.live_at)
	check(seen.moved, "phase 4: the archetype move-set animates the body (%s)" % a.moveset())
	check(seen.hp_drop_at > seen.live_at, "the target's HP bar drops at impact, after the transform (%.2fs > %.2fs)" % [seen.hp_drop_at, seen.live_at])
	check(a.is_statue() and a.stone_h >= 1.0 and a.crack == 0.0 and a.off == Vector3.ZERO, "phase 5: back to a statue, at rest (stone_h %.2f)" % a.stone_h)
	check(t.shown_hp == 90 and t.damage_v > 0.2, "target shows the new HP and crack decals (damage %.2f)" % t.damage_v)
	check(not b.anim_busy() and dur < 3.5, "the full sequence completes (%.2fs)" % dur)
	check(b.juice.transforms == 1, "one transform counted")
	# second attack by the same monster: the quick version, <= 1.2 s
	_hit(s, au, tu, 20)
	var name2 := [""]
	var dur2 := _drain(b, func():
		if name2[0] == "":
			name2[0] = b.anim.now_playing())
	check(name2[0] == "transform" and dur2 <= 1.25, "repeat attacks use the quick transform: %s %.2fs (<= 1.2 s + a frame)" % [name2[0], dur2])
	check(a.is_statue(), "and still return to stone")
	# every move-set's quick version fits 1.2 s at the slowest personal timing
	var worst := 0.0
	for plan in Actor.MOVESET:
		var x := Actor.new()
		x.plan = plan
		x.tf = 1.14
		x.hits_n = 3
		var tm: Dictionary = x.move_timing(1.25)
		worst = maxf(worst, 0.26 + float(tm.dur) * 0.85 + 0.3)
		x.free()
	check(worst <= 1.25, "slowest quick move-set + transform stays within ~1.2 s (%.2fs)" % worst)
	# a skill: cut-in + full transform
	s.events.append("%s uses Test Skill" % au.name)
	_hit(s, au, tu, 25)
	_drain(b)
	check(b.cut_in.shown == 1 and b.juice.cutins == 1, "skills play the cut-in banner (%d)" % b.cut_in.shown)
	check(a.is_statue() and t.shown_hp == 45, "after the skill: statue again, target HP %d" % t.shown_hp)
	# defend: rune shield glow while defending
	au.defending = true
	s.events.append("%s defends" % au.name)
	_drain(b)
	check(a.defending, "defending statues keep the rune shield on")
	# tap-to-skip
	_hit(s, au, tu, 5)
	b.anim_busy()
	b.anim_step(0.1)
	b.skip_anim()
	b.skip_anim()
	check(not b.anim_busy() and a.is_statue() and t.shown_hp == 40, "skipping settles the beat in its end state")
	b.queue_free()
	await process_frame


func test_ko_orphans() -> void:
	print("[KO crumble leaves no orphans]")
	for instant in [true, false]:
		var r: Array = await _board(instant)
		var b = r[0]
		var s: GameState = r[1]
		await process_frame
		var orphans_before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
		var nodes_before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		var t: Actor = b.actors[502]
		var tu: GameState.Unit = r[3]
		tu.hp = 0
		s.units.erase(tu)
		s.events.append("%s hits %s for %d" % [r[2].name, tu.name, 120])
		s.events.append("%s is knocked out" % tu.name)
		b.sync()
		check(not b.actors.has(502), "%s: the KO'd unit leaves `actors` at once (actors == units)" % ("instant" if instant else "animated"))
		if not instant:
			var crumbled := [false]
			var wr: WeakRef = weakref(t)
			_drain(b, func():
				var x: Actor = wr.get_ref()
				if x != null and x.dying and x.dissolve > 0.3:
					crumbled[0] = true)
			check(crumbled[0] and b.juice.crumbles == 1, "the statue crumbles (dissolve + rubble) before it goes")
		await process_frame
		await process_frame
		check(not is_instance_valid(t), "the crumbled actor is freed")
		check(b._dying.is_empty(), "no actor left in the crumbling list")
		# rubble / debris are timed; let them expire
		for i in 90:
			await process_frame
		await create_timer(2.6).timeout
		await process_frame
		var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
		check(orphans <= orphans_before, "no orphan nodes after the KO (%d -> %d)" % [orphans_before, orphans])
		check(b._fx.get_child_count() == 0, "every effect node freed itself (%d left)" % b._fx.get_child_count())
		check(Performance.get_monitor(Performance.OBJECT_NODE_COUNT) < nodes_before, "node count dropped below the pre-KO count")
		b.queue_free()
		await process_frame


func test_reduced_motion() -> void:
	print("[reduced_motion]")
	var keep: Variant = ProjectSettings.get_setting(SETTING, false)
	check(ProjectSettings.has_setting(SETTING), "project setting %s exists" % SETTING)
	for on in [true, false]:
		ProjectSettings.set_setting(SETTING, on)
		var r: Array = await _board(false)
		var b = r[0]
		var s: GameState = r[1]
		var max_shake := [0.0]
		var max_flash := [0.0]
		var min_speed := [1.0]
		s.events.append("%s uses Test Skill" % r[2].name)
		_hit(s, r[2], r[3], 60)
		_drain(b, func():
			max_shake[0] = maxf(max_shake[0], b._shake)
			max_flash[0] = maxf(max_flash[0], b.cut_in.flash_a)
			if b._slowmo > 0.0:
				min_speed[0] = 0.35)
		r[3].hp = 0
		s.units.erase(r[3])
		s.events.append("%s hits %s for 60" % [r[2].name, r[3].name])
		s.events.append("%s is knocked out" % r[3].name)
		_drain(b, func():
			max_shake[0] = maxf(max_shake[0], b._shake)
			max_flash[0] = maxf(max_flash[0], b.cut_in.flash_a)
			if b._slowmo > 0.0:
				min_speed[0] = 0.35)
		if on:
			check(max_shake[0] == 0.0 and b.juice.shakes == 0, "reduced_motion: no camera shake (%.1f px)" % max_shake[0])
			check(max_flash[0] == 0.0 and b.juice.flashes == 0, "reduced_motion: no screen flash")
			check(b.juice.slowmo == 0 and min_speed[0] == 1.0, "reduced_motion: no slow-mo on the KO")
			check(not b._breathing(), "reduced_motion: no camera breathing")
		else:
			check(max_shake[0] > 0.0 and b.juice.flashes > 0 and b.juice.slowmo > 0, "default: shake %.1f px, %d flashes, slow-mo on KO" % [max_shake[0], b.juice.flashes])
			b.juice.flashes = 0
			b._last_flash = -10.0
			for i in 5:
				b.screen_flash(Color.WHITE, 0.2)
			check(b.juice.flashes == 1, "flashes are capped at one per 0.34 s (never faster than 3 Hz): %d of 5" % b.juice.flashes)
		b.queue_free()
		await process_frame
	ProjectSettings.set_setting(SETTING, keep)


func test_summon_and_vessel() -> void:
	print("[summon from a Vessel, vessel break]")
	var r: Array = await _board(false)
	var b = r[0]
	var s: GameState = r[1]
	var ids := Data.monster_ids()
	var u := _unit(503, str(ids[3]), 0, Vector2i(4, 4))
	s.units.append(u)
	b.play_summon(u, 3)
	var a: Actor = b.actors.get(503)
	check(a != null and not a.visible, "the summoned statue waits hidden for its Vessel to crack")
	var sp := [false]
	var vessel := [false]
	_drain(b, func():
		for p in b._popups:
			if p.text == "-3 SP":
				sp[0] = true
		for c in b._fx.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is ArrayMesh:
				vessel[0] = true)
	b.play_summon(u, 3)
	check(sp[0], "the Summon Point cost floats during the summon (-3 SP)")
	check(vessel[0], "a faceted Vessel crystal appears on the tile")
	check(b.juice.summons == 1, "one summon sequence per unit, even when both the hook and the sync see it (%d)" % b.juice.summons)
	check(a.visible and a.is_statue() and a.dissolve == 0.0, "the statue stands assembled on its plinth")
	b.play_vessel_break({"pos": Vector2i(2, 2), "owner": 1, "name": "Test"})
	var played: int = b.anim.played
	_drain(b)
	check(b.anim.played == played + 1, "play_vessel_break plays one beat and settles")
	b.play_vessel_break({"tile": Vector2i(3, 2)})
	b.play_vessel_break(null)
	_drain(b)
	check(not b.anim_busy(), "vessel break tolerates partial / null data")
	b.queue_free()
	await process_frame


func test_personal() -> void:
	print("[every monster its own statue and move-set]")
	var sigs := {}
	var timings := {}
	var n := 0
	for id in Data.monster_ids():
		var d := Data.monster(id)
		var seed := Actor.personal_seed(str(id))
		var plan: Array = Creature.plan_for(str(d.name), str(d.role))
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var tf := snappedf(rng.randf_range(0.88, 1.14), 0.02)
		var arc := snappedf(rng.randf_range(0.75, 1.3), 0.05)
		var hits := 1 + rng.randi() % 3
		var sig := "%s/%s/%s/%s/%s/%.2f/%.2f/%d" % [plan[0], plan[1], d.element_family, d.get("ability", ""), str(Creature.extras_for(seed)), tf, arc, hits]
		sigs[sig] = int(sigs.get(sig, 0)) + 1
		timings["%s/%.2f/%d" % [plan[0], tf, hits]] = true
		n += 1
	var unique := 0
	for k in sigs:
		if int(sigs[k]) == 1:
			unique += 1
	check(unique >= int(n * 0.95), "%d of %d bible monsters have a unique statue + move-set signature" % [unique, n])
	check(timings.size() >= 40, "%d distinct move-set timings (archetype x timing x hit count)" % timings.size())
	var c1 := Creature.build("beast", "mane", "Fire", 0, 11)
	var c2 := Creature.build("beast", "mane", "Fire", 0, 12345)
	check(int(c1.verts) != int(c2.verts) or Creature.extras_for(11) != Creature.extras_for(12345), "two seeds of the same body plan build different statues")
	for fam in Assets.ELEMENT_FAMILIES:
		check(FX.DELIVERY.has(fam), "element %s has an attack delivery (%s)" % [fam, FX.DELIVERY.get(fam, "-")])
