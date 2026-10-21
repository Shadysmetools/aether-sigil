## HD-2D 3D board (scripts/board_3d.gd + scripts/board3d/): headless checks of everything that can
## break play — the island builds for every tile type on all 120 stage maps; grid <-> screen mapping
## round-trips for all 144 tiles (every stage at the default view; one stage per tower at all four
## rotations and min/max zoom); the windowed ray pick equals a brute-force pick; taps on the real main
## scene summon through the 3D board (press + release), drags never tap; monster visuals resolve
## (painted cut-out -> billboard, concept crop / nothing -> procedural creature); every bible
## monster gets a creature body plan. Exits with the failure count.
extends SceneTree

const GameState = preload("res://scripts/game_state.gd")
const Data = preload("res://scripts/data_loader.gd")
const Build = preload("res://scripts/board3d/board_build.gd")
const Board3D = preload("res://scripts/board_3d.gd")
const Actor = preload("res://scripts/board3d/unit_actor.gd")
const Creature = preload("res://scripts/board3d/creature.gd")
const Assets = preload("res://scripts/assets.gd")
const Palette = preload("res://scripts/theme_colors.gd")

const SAVE := "user://board3d_save.json"
const AI_DIR := "user://board3d_test/ai"
const BAND := Rect2(16, 520, 1048, 1060)

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
	print("Aether Sigil HD-2D board test")
	Data.ensure_loaded()
	test_themes()
	test_build_all_stages()
	await test_mapping()
	await test_main_scene()
	test_billboard()
	test_creatures()
	print("%d pass / %d fail" % [passed, failed])
	quit(mini(failed, 255))


func _tower_theme(tid: String) -> String:
	for t in Data.towers():
		if str(t.tower_id) == tid:
			return str(t.theme)
	return ""


func test_themes() -> void:
	print("[themes]")
	var known := Palette.tower_themes()
	for t in Data.towers():
		check(known.has(str(t.theme)), "tower %s theme '%s' has a 3D board look" % [t.tower_id, t.theme])


## Every tile of every stage builds geometry; objective props match the GameState.
func test_build_all_stages() -> void:
	print("[build: 120 stage maps]")
	var all_types := {}
	var bad_stages: Array = []
	var verts := 0
	for st in Data.stages():
		var s := GameState.new()
		s.setup(str(st.stage_id))
		var b := Build.new()
		var root := b.build(s, _tower_theme(str(st.tower_id)), Color(0.7, 0.8, 0.95))
		var problems: Array = []
		if int(b.stats.tiles) != 144:
			problems.append("tiles %d" % b.stats.tiles)
		var sum := 0
		for t in b.stats.types:
			sum += int(b.stats.types[t])
			all_types[t] = true
			if not b.stats.built.has(t):
				problems.append("type %s built nothing" % t)
		if sum != 144:
			problems.append("type counts %d" % sum)
		var nodes := 0
		var relics := 0
		for c in b.gems:
			if b.gems[c].kind == "node":
				nodes += 1
			else:
				relics += 1
		if nodes != s.nodes.size() or relics != s.relics.size():
			problems.append("gems %d/%d vs %d/%d" % [nodes, relics, s.nodes.size(), s.relics.size()])
		if b.portals.size() != s.portals.size():
			problems.append("portals")
		for side in 2:
			if s.symbol_pos[side] != Vector2i(-1, -1) and not b.sigils.has(side):
				problems.append("sigil %d missing" % side)
		if int(b.stats.verts) <= 0 or root.get_node_or_null("Stone") == null:
			problems.append("no stone mesh")
		if int(b.stats.waterfalls) < 4:
			problems.append("waterfalls %d" % b.stats.waterfalls)
		if not problems.is_empty():
			bad_stages.append("%s: %s" % [st.stage_id, ", ".join(problems)])
		verts += int(b.stats.verts)
		root.free()
	check(bad_stages.is_empty(), "all 120 stage maps build every tile type, objective and Sigil (%s)" % str(bad_stages.slice(0, 4)))
	print("    tile types seen: %s; avg verts/island %d" % [", ".join(all_types.keys()), verts / maxi(1, Data.stages().size())])
	for t in all_types:
		check(Data.tile_handled(t), "map tile type '%s' is a rules tile the 3D board builds" % t)
	# Every legend type (even those no map paints yet) builds on a synthetic board.
	var s2 := GameState.new()
	s2.setup("T01-L01")
	var legend: Dictionary = Data.rules().tiles
	var types: Array = []
	for t in legend:
		if t != "_doc":
			types.append(t)
	for y in GameState.SIZE:
		for x in GameState.SIZE:
			s2.grid[y][x] = types[(x + y * GameState.SIZE) % types.size()]
	var b2 := Build.new()
	var r2 := b2.build(s2, "Nature", Color.WHITE)
	var missing: Array = []
	for t in types:
		if not b2.stats.built.has(t):
			missing.append(t)
	check(missing.is_empty(), "every rules tile type (%d) builds a mesh: missing %s" % [types.size(), str(missing)])
	r2.free()


func _round_trip(board, s: GameState) -> Array:
	var bad: Array = []
	for y in GameState.SIZE:
		for x in GameState.SIZE:
			var c := Vector2i(x, y)
			var got: Variant = board.tile_at_local(board.tile_center(c))
			if got != c:
				bad.append("%s->%s" % [c, got])
	return bad


func _brute_pick(board, o: Vector3, d: Vector3) -> Variant:
	var best_top := INF
	var top_c: Variant = null
	var best_side := INF
	var side_c: Variant = null
	for y in GameState.SIZE:
		for x in GameState.SIZE:
			var c := Vector2i(x, y)
			var p := Build.cell_pos(c)
			var r := Board3D._slab_hit(o, d, Vector3(p.x - 0.5, Build.BASE, p.z - 0.5), Vector3(p.x + 0.5, Build.pick_top(board.state.tile_type(c)), p.z + 0.5))
			if r.x < 0.0:
				continue
			if r.y > 0.5 and r.x < best_top:
				best_top = r.x
				top_c = c
			elif r.y <= 0.5 and r.x < best_side:
				best_side = r.x
				side_c = c
	return top_c if top_c != null else side_c


func test_mapping() -> void:
	print("[grid <-> screen mapping, picking]")
	var board = Board3D.new()
	root.add_child(board)
	await process_frame
	var s := GameState.new()
	s.setup("T01-L01")
	board.state = s
	board.fit_band(BAND)
	var bad_stages: Array = []
	var outside: Array = []
	for st in Data.stages():
		s.setup(str(st.stage_id))
		board.view_step = 0
		board.zoom = 1.0
		board.fit_band(BAND)
		var bad := _round_trip(board, s)
		if not bad.is_empty():
			bad_stages.append("%s %s" % [st.stage_id, str(bad.slice(0, 3))])
		for y in GameState.SIZE:
			for x in GameState.SIZE:
				if not BAND.has_point(board.tile_center(Vector2i(x, y))):
					outside.append("%s %s" % [st.stage_id, Vector2i(x, y)])
	check(bad_stages.is_empty(), "tile_at_local(tile_center(c)) == c for all 144 tiles on all 120 stages (%s)" % str(bad_stages.slice(0, 3)))
	check(outside.is_empty(), "every tile centre lies inside the board band at zoom 1 (%s)" % str(outside.slice(0, 3)))
	# One stage per tower (the one with the most raised tiles), every rotation, min and max zoom.
	for t in Data.towers():
		var pick_id := ""
		var most := -1
		for st in Data.stages():
			if str(st.tower_id) != str(t.tower_id):
				continue
			var n := 0
			for row in st.map_grid:
				for cell in row:
					n += 1 if ["elevation", "obstacle", "stone", "water"].has(str(cell)) else 0
			if n > most:
				most = n
				pick_id = str(st.stage_id)
		s.setup(pick_id)
		for step in 4:
			for z in [1.0, Board3D.ZOOM_MAX]:
				board.view_step = step
				board.zoom = z
				board.fit_band(BAND)
				var bad := _round_trip(board, s)
				check(bad.is_empty(), "%s view %d zoom %.1f: 144/144 tiles round-trip (%s)" % [pick_id, step, z, str(bad.slice(0, 3))])
	# Windowed pick == brute force over all 144 boxes, on random screen points.
	board.view_step = 1
	board.zoom = 1.0
	s.setup("T05-L02")
	board.fit_band(BAND)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mism := 0
	var hits := 0
	for i in 1500:
		var sp := Vector2(rng.randf_range(BAND.position.x, BAND.end.x), rng.randf_range(BAND.position.y, BAND.end.y))
		var ray: Array = board.screen_ray(sp)
		var o: Vector3 = ray[0]
		var d: Vector3 = ray[1]
		var a: Variant = board.pick_ray(o, d)
		if a != _brute_pick(board, o, d):
			mism += 1
		if a != null:
			hits += 1
	check(mism == 0 and hits > 400, "windowed ray pick matches brute force on 1500 random points (%d mismatches, %d on-board)" % [mism, hits])
	check(board.tile_at_local(Vector2(4, 4)) == null, "a point off the island picks nothing")
	board.view_step = 0
	board.zoom = 1.0
	board.fit_band(BAND)
	var p00: Vector2 = board.tile_center(Vector2i(0, 0))
	var p11: Vector2 = board.tile_center(Vector2i(11, 11))
	check(p00.y > p11.y, "default view matches the 2D board: player corner (0,0) nearest the camera (below (11,11))")
	board.rotate_view(1)
	check(board.view_step == 1 and _round_trip(board, s).is_empty(), "rotate_view turns a quarter and picking still maps")
	board.queue_free()
	await process_frame


func _tap(main: Node, c: Vector2i, drag := Vector2.ZERO) -> void:
	var pos: Vector2 = main.board.get_global_transform_with_canvas() * main.board.tile_center(c)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	root.push_input(down, true)
	if drag != Vector2.ZERO:
		var mv := InputEventMouseMotion.new()
		mv.position = pos + drag
		mv.global_position = mv.position
		mv.relative = drag
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(mv, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos + drag
	up.global_position = up.position
	root.push_input(up, true)


## The real main scene with the 3D board forced on (headless defaults to 2D).
func test_main_scene() -> void:
	print("[main scene with the 3D board]")
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	main.board_mode = "3d"
	root.add_child(main)
	await process_frame
	main._on_dialogue_skip()
	check(main.board.has_method("fit_band"), "board_mode 3d gives the HD-2D board")
	main.start_stage("T01-L01")
	await process_frame
	main._on_dialogue_skip()
	await process_frame
	await process_frame
	var s: GameState = main.state
	check(main.board.island != null and main.board.island.get_node_or_null("Stone") != null, "island built for the stage")
	check(main.board.actors.size() == s.units.size() and s.units.size() > 0, "one 3D actor per unit on the board (%d, dormant statues)" % main.board.actors.size())
	var covered: Array = []
	var off: Array = []
	var vp: Vector2 = main.get_viewport().get_visible_rect().size
	for y in 12:
		for x in 12:
			var c := Vector2i(x, y)
			var pt: Vector2 = main.board.get_global_transform_with_canvas() * main.board.top_center(c)
			if not Rect2(Vector2.ZERO, vp).has_point(pt):
				off.append(c)
			for pnl in [main.top_panel, main.turn_panel, main.side_panel, main.bottom_panel]:
				if pnl.get_global_rect().has_point(pt):
					covered.append(c)
			for b in main.board.buttons:
				if b.get_global_rect().has_point(pt):
					covered.append(c)
	check(covered.is_empty(), "no HUD panel or board button covers any of the 144 tiles (%s)" % str(covered.slice(0, 5)))
	check(off.is_empty(), "all 144 tiles on screen (%s)" % str(off.slice(0, 5)))
	var first: String = main.progress.squad[0]
	main._on_team(0)
	check(main.board.highlights.size() > 0, "summon mode highlights legal tiles")
	var spawn: Vector2i = main.board.highlights.keys()[0]
	_tap(main, spawn, Vector2(0, 260))
	await process_frame
	check(s.unit_at(spawn) == null, "a drag that starts on a tile does not tap it")
	_tap(main, spawn)
	await process_frame
	check(s.unit_at(spawn) != null and s.unit_at(spawn).mon_id == first, "press + release on the projected tile summons %s at %s" % [first, spawn])
	await process_frame
	check(main.board.actors.has(s.unit_at(spawn).id), "summoned monster gets a 3D actor")
	main.board.rotate_view(1)
	await process_frame
	main._on_team(1)
	if main.board.highlights.size() > 0:
		var second: Vector2i = main.board.highlights.keys()[0]
		_tap(main, second)
		await process_frame
		check(s.unit_at(second) != null, "after a quarter turn a tap still lands on the right tile (%s)" % second)
	main._on_cmd("Wait")
	for i in 60:
		await create_timer(0.05).timeout
		if not main.ai_running:
			break
	check(main.board.actors.size() == s.units.size(), "actors follow the battle (%d actors, %d units)" % [main.board.actors.size(), s.units.size()])
	main.show_stage_select()
	await process_frame
	check(not main.board.world.visible and not main.board.cam.current, "leaving the battle hides the 3D world and releases the camera")
	main.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


func _unit(mon_id: String, owner := 0) -> GameState.Unit:
	var d := Data.monster(mon_id)
	var u := GameState.Unit.new()
	u.id = 900 + owner
	u.mon_id = mon_id
	u.name = str(d.name)
	u.family = str(d.element_family)
	u.role = str(d.role)
	u.owner = owner
	return u


func test_billboard() -> void:
	print("[monster visuals]")
	# A painted cut-out with real alpha in the art drop folder -> upright billboard, alpha-cut.
	var path := AI_DIR.path_join("monsters/MON-0001.png")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(8, 60):
		for x in range(20, 44):
			img.set_pixel(x, y, Color(0.9, 0.4, 0.2, 1))
	img.save_png(path)
	var keep_ai: String = Assets.ai_root
	var keep_dev: String = Assets.dev_root
	Assets.ai_root = AI_DIR
	Assets.dev_root = ""
	Assets.clear_cache()
	var tex := Assets.monster("MON-0001")
	check(tex != null and not Assets.is_crop(tex), "Assets resolves the painted cut-out for MON-0001")
	var a := Actor.new()
	a.setup(_unit("MON-0001"))
	check(a.is_sprite and a.visual.mesh is QuadMesh, "a cut-out becomes a billboard quad")
	var q := a.visual.mesh as QuadMesh
	check(is_equal_approx(q.size.x, q.size.y), "billboard keeps the art's aspect ratio (%s)" % str(q.size))
	check(a.mat.get_shader_parameter("tex") == tex, "billboard samples the resolved texture (alpha-cut shader)")
	a.free()
	Assets.ai_root = keep_ai
	Assets.dev_root = ""
	Assets.clear_cache()
	# No painted art (dev art folder off) -> procedural creature, not a medallion or a rectangle.
	var b := Actor.new()
	b.setup(_unit("MON-0001", 1))
	check(not b.is_sprite and b.visual.mesh is ArrayMesh and b.mat.next_pass != null, "no cut-out -> procedural creature with ink outline")
	b.free()
	# A rectangular concept crop must never stand as a billboard card.
	var crop := ImageTexture.create_from_image(img)
	Assets._concept_tex[crop] = true
	var c := Actor.new()
	c.setup(_unit("MON-0002"), crop)
	check(not c.is_sprite, "a concept-sheet crop falls back to the procedural creature")
	c.free()
	Assets._concept_tex.erase(crop)
	Assets.dev_root = keep_dev
	Assets.clear_cache()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_creatures() -> void:
	print("[procedural creatures]")
	var per_plan := {}
	var empty: Array = []
	for id in Data.monster_ids():
		var d := Data.monster(id)
		var p := Creature.plan_for(str(d.name), str(d.role))
		per_plan[p[0]] = int(per_plan.get(p[0], 0)) + 1
		var key := "%s/%s" % p
		if not per_plan.has(key):
			per_plan[key] = 0
			var c := Creature.build(p[0], p[1], str(d.element_family), 0)
			if int(c.verts) < 60 or float(c.height) <= 0.2:
				empty.append(key)
	check(empty.is_empty(), "every body plan/variant used by the bible builds a creature mesh (%s)" % str(empty))
	var plans := 0
	for p in Creature.PLANS:
		if int(per_plan.get(p, 0)) > 0:
			plans += 1
	check(plans >= 6, "bible monsters spread over %d body plans: %s" % [plans, str(per_plan.keys().filter(func(k): return not str(k).contains("/")).map(func(k): return "%s %d" % [k, per_plan[k]]))])
	for fam in Assets.ELEMENT_FAMILIES:
		check(Actor.AURA.has(fam), "element family %s has an aura" % fam)
