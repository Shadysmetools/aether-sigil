## Scene dialogue + Narrator (Vellum) tests: mood tags and expressions, voice-key sync, bark director,
## staging plan, actor state machine, scene layer, bark bubble, procedural figures, UI wiring.
## Run: Godot_console.exe --headless --path <game dir> --script res://tests/test_scene.gd
extends SceneTree

const Data = preload("res://scripts/data_loader.gd")
const Story = preload("res://scripts/story.gd")
const GameState = preload("res://scripts/game_state.gd")
const Narrator = preload("res://scripts/narrator.gd")
const SceneDialogue = preload("res://scripts/ui/scene_dialogue.gd")
const Actor = preload("res://scripts/ui/character_actor.gd")
const BarkBubble = preload("res://scripts/ui/bark_bubble.gd")
const Kit = preload("res://scripts/ui/menu_kit.gd")
const UIArt = preload("res://scripts/ui_art.gd")
const Assets = preload("res://scripts/assets.gd")
const AudioManager = preload("res://scripts/audio_manager.gd")

var passed := 0
var failed := 0


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("  PASS  ", label)
	else:
		failed += 1
		print("  FAIL  ", label)


func eq(actual, expected, label: String) -> void:
	check(actual == expected, "%s (got %s, want %s)" % [label, str(actual), str(expected)])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("Aether Sigil scene + narrator tests")
	Data.ensure_loaded()
	test_data()
	test_voice_sync()
	test_moods()
	test_bark_director()
	test_plan()
	test_actor()
	test_resolver()
	await test_scene_layer()
	await test_bubble()
	await test_figures()
	print("%d pass / %d fail" % [passed, failed])
	quit(mini(failed, 255))


# ---------------------------------------------------------------- data

func _narrator_story_lines() -> Array:
	var out := []
	for e in Narrator.story_line_ids():
		if str(e.line.speaker) == Narrator.SPEAKER:
			out.append(e)
	return out


func test_data() -> void:
	print("[narrator data]")
	var nar := Data.narrator()
	eq(str(nar.get("name")), "Vellum", "the Narrator has a name")
	eq(Narrator.plate_name("Narrator"), "Vellum", "plate shows Vellum")
	eq(Narrator.plate_name("Elio"), "Elio", "other plates unchanged")
	eq(Story.hero(), "Elio", "protagonist unchanged")
	var ids := Narrator.story_line_ids()
	eq(ids.size(), 215, "story.json keeps its 215 lines")
	var nl := _narrator_story_lines()
	eq(nl.size(), 25, "25 Narrator story lines (counts unchanged)")
	var table: Dictionary = nar.mood_expression
	var all_tagged := true
	var all_expr := true
	for e in nl:
		var m := str(e.line.get("mood", ""))
		if m == "" or not table.has(m):
			all_tagged = false
			print("    untagged: ", e.id)
		if not Narrator.EXPRESSIONS.has(SceneDialogue.expression_for(e.line)):
			all_expr = false
	check(all_tagged, "every Narrator story line id has a known mood tag")
	check(all_expr, "...and an expression")
	var untagged := 0
	for e in ids:
		if str(e.line.get("mood", "")) == "":
			untagged += 1
	eq(untagged, 0, "every story line has a mood tag")
	var seen := {}
	var barks_ok := true
	for b in Narrator.all_barks():
		if seen.has(b.id) or not table.has(str(b.mood)) or str(b.line) == "" or str(b.line).length() > 80:
			barks_ok = false
			print("    bad bark: ", b.id)
		seen[b.id] = true
		if not Narrator.EXPRESSIONS.has(Narrator.expression_for_mood(str(b.mood))):
			barks_ok = false
	check(barks_ok, "%d barks: unique ids, mood + expression, short" % Narrator.all_barks().size())
	for ev in ["battle_start", "first_crack", "big_hit", "ko", "vessel_broken", "low_sigil_hp", "victory", "defeat", "evolution", "fusion"]:
		var n := 0
		for b in Narrator.all_barks():
			if b.event == ev:
				n += 1
		eq(n, 3, "event %s has an early/mid/late line" % ev)
	for t in Data.towers():
		var tid := str(t.tower_id)
		check(not Narrator.bark("arrival", tid).is_empty() and not Narrator.bark("clear", tid).is_empty(), "tower %s has arrival + clear barks" % tid)
	eq(Narrator.phase_for_tower("03"), "early", "tower 3 is the early phase")
	eq(Narrator.phase_for_tower("07"), "mid", "tower 7 is the mid phase")
	eq(Narrator.phase_for_tower("12"), "late", "tower 12 is the late phase")
	check(str(Narrator.bark("victory", "01").line) != str(Narrator.bark("victory", "12").line), "barks change with the arc")
	check(not Story.lines("prologue")[0].line.begins_with("Long ago"), "the opening line is in Vellum's voice")


func test_voice_sync() -> void:
	print("[voice keys match the game's lines]")
	var j := JSON.new()
	var path := "res://audio/voices/LINES.json"
	check(j.parse(FileAccess.get_file_as_string(path)) == OK, "LINES.json parses")
	var keys := {}
	for l in j.data.lines:
		keys[str(l.key)] = str(l.line_id)
	var missing := []
	for e in Narrator.story_line_ids():
		var k := AudioManager.voice_key(str(e.line.speaker), str(e.line.line))
		if not keys.has(k):
			missing.append(e.id)
	eq(missing, [], "every story line's voice key is in LINES.json")
	missing = []
	for b in Narrator.all_barks():
		if not keys.has(AudioManager.voice_key("Narrator", str(b.line))):
			missing.append(b.id)
	eq(missing, [], "every Narrator bark's voice key is in LINES.json")
	var cast: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://audio/voices/CASTING.json"))
	var d: Dictionary = cast.speakers.Narrator.description
	check(d.has("timbre") and d.has("pacing") and d.has("accent") and d.has("age"), "CASTING.json has the detailed Narrator voice direction")


# ---------------------------------------------------------------- moods

func test_moods() -> void:
	print("[mood -> expression]")
	eq(Narrator.expression_for_mood("wry"), "amused", "wry -> amused")
	eq(Narrator.expression_for_mood("solemn"), "grave", "solemn -> grave")
	eq(Narrator.expression_for_mood("wonder"), "awed", "wonder -> awed")
	eq(Narrator.expression_for_mood("resolute"), "determined", "resolute -> determined")
	eq(Narrator.expression_for_mood("angry"), "angry", "angry passes through")
	eq(Narrator.expression_for_mood("nonsense"), "neutral", "unknown tags are neutral")
	eq(Narrator.art_expression("sad"), "grave", "the 4-face Narrator art folds sad into grave")
	eq(Narrator.art_expression("determined"), "neutral", "...and determined into neutral")
	eq(Narrator.art_expression("awed"), "awed", "awed stays awed")
	eq(SceneDialogue.infer_mood("Kess Varrow", "Save the speeches."), "angry", "inferred: angry")
	eq(SceneDialogue.infer_mood("Pell", "Pell too! Pell holds too!"), "amused", "inferred: Pell cheers")
	eq(SceneDialogue.infer_mood("Elio", "Then I'm going."), "determined", "inferred: determined")
	eq(SceneDialogue.infer_mood("Maren Oake", "The isle is falling."), "grave", "inferred: grave")
	eq(SceneDialogue.infer_mood("Elio", "Hello there."), "neutral", "inferred: neutral")
	var bad := 0
	for e in Narrator.story_line_ids():
		if str(e.line.speaker) != Narrator.SPEAKER and SceneDialogue.infer_mood(str(e.line.speaker), str(e.line.line)) != str(e.line.mood):
			bad += 1
	eq(bad, 0, "the tool's tags and the runtime inference agree on every other story line")
	eq(SceneDialogue.mood_of({"speaker": "Elio", "line": "Hi", "mood": "awed"}), "awed", "an explicit mood wins")
	eq(SceneDialogue.style_for({"speaker": "Elio", "line": "...I did not know.", "mood": "neutral"}), "thought", "thought bubble")
	eq(SceneDialogue.style_for({"speaker": "Kess", "line": "Move it!", "mood": "determined"}), "shout", "shout bubble")
	eq(SceneDialogue.style_for({"speaker": "Elio", "line": "Hello.", "mood": "neutral"}), "speech", "speech bubble")
	var lo := 9.0
	var hi := 0.0
	for w in ["Elio", "Pell", "Kess Varrow", "Narrator", "Ari Zephyr"]:
		lo = minf(lo, SceneDialogue.blip_pitch(w))
		hi = maxf(hi, SceneDialogue.blip_pitch(w))
	check(lo >= 0.8 and hi <= 1.4 and SceneDialogue.blip_pitch("Elio") == SceneDialogue.blip_pitch("Elio"), "blip pitch is per character, stable, in range")


# ---------------------------------------------------------------- bark director

func _unit(id: int, owner: int, hp: int) -> GameState.Unit:
	var u := GameState.Unit.new()
	u.id = id
	u.owner = owner
	u.hp = hp
	u.max_hp = 100
	return u


func test_bark_director() -> void:
	print("[bark director fires on the right events, headless]")
	var s := GameState.new()
	s.setup("T01-L02")
	var P := GameState.PLAYER
	var d := Narrator.BarkDirector.new()
	eq(d.update(s), ["battle_start"], "first look: battle_start")
	eq(d.update(s), [], "nothing new: silent")
	s.symbol_hp[P] = int(s.symbol_max * 0.8)
	eq(d.update(s), [], "a 20% Sigil dent is not a big hit")
	s.symbol_hp[P] = int(s.symbol_max * 0.62)
	eq(d.update(s), [], "...nor is the next one")
	s.symbol_hp[P] = int(s.symbol_max * 0.45)
	eq(d.update(s), ["low_sigil_hp"], "low Sigil HP")
	eq(d.update(s), [], "low Sigil HP fires once")
	s.kos[P] = 1
	eq(d.update(s), ["ko"], "a knockout")
	s.last_break = {"mon": "x", "pos": Vector2i(1, 1)}
	eq(d.update(s), ["vessel_broken"], "a Vessel breaks")
	var u := _unit(901, P, 100)
	s.units.append(u)
	d.update(s)
	u.hp = 40
	eq(d.update(s), ["big_hit"], "a big hit (60% of max HP)")
	u.hp = 0
	eq(d.update(s), [], "a second big hit inside the cooldown is ignored")
	var d2 := Narrator.BarkDirector.new()
	var s2 := GameState.new()
	s2.setup("T01-L02")
	d2.update(s2)
	var cu := _unit(902, P, 100)
	s2.units.append(cu)
	s2.last_crack = {"unit": 902, "cost": 1}
	eq(d2.update(s2), ["first_crack"], "the first Vessel crack")
	s2.last_crack = {"unit": 902, "cost": 1}
	eq(d2.update(s2), [], "...once")
	var s3 := GameState.new()
	s3.setup("T01-L02")
	var d3 := Narrator.BarkDirector.new()
	d3.update(s3)
	var eu := _unit(903, GameState.ENEMY, 100)
	s3.units.append(eu)
	s3.last_crack = {"unit": 903, "cost": 1}
	eq(d3.update(s3), [], "an enemy crack is not the player's first crack")
	var multi := Narrator.BarkDirector.new()
	var s4 := GameState.new()
	s4.setup("T01-L02")
	s4.symbol_hp[P] = 1
	s4.kos[P] = 1
	eq(multi.update(s4), ["low_sigil_hp", "ko", "battle_start"], "several events fire in priority order")
	s4.winner = GameState.PLAYER
	eq(Narrator.BarkDirector.new().update(s4), [], "no barks once the battle is decided")
	eq(Narrator.BarkDirector.new().update(null), [], "null state is safe")


# ---------------------------------------------------------------- staging

func test_plan() -> void:
	print("[multi-speaker staging]")
	var lines := Story.lines("prologue")
	var plan := SceneDialogue.plan(lines, "Elio")
	eq(plan.size(), lines.size(), "one step per line")
	eq(SceneDialogue.group_of("Narrator", "Elio"), "float", "Vellum floats")
	eq(SceneDialogue.group_of("Pell", "Elio"), "left", "Pell stands with Elio")
	eq(SceneDialogue.group_of("Maren Oake", "Elio"), "right", "Maren stands opposite Elio")
	eq(plan[0].enter.size(), 1, "the first line brings its speaker on")
	check(plan[0].enter[0].who == "Narrator" and plan[0].enter[0].group == "float", "scene opens on the floating Narrator")
	var entered := {}
	for st in plan:
		for e in st.enter:
			entered[e.who] = true
	check(entered.has("Elio") and entered.has("Pell") and entered.has("Maren Oake") and entered.has("Kess Varrow") and entered.has("Narrator"), "the prologue stages all five speakers")
	# invariants over every sequence in the story
	var seqs := [Story.lines("prologue"), Story.lines("finale"), Story.lines("epilogue")]
	for t in Data.towers():
		for part in ["arrival", "pre_boss", "post_boss"]:
			seqs.append(Story.lines("%s_%s" % [part, t.tower_id]))
	var ok := true
	for seq in seqs:
		var p := SceneDialogue.plan(seq, "Elio")
		var on := {}
		for i in p.size():
			for w in p[i].exit:
				if not on.has(w):
					ok = false
				on.erase(w)
			for e in p[i].enter:
				if on.has(e.who):
					ok = false
				on[e.who] = e.group
			if str(p[i].who) != "" and not on.has(p[i].who):
				ok = false   # the speaker must be on stage
			var per := {"left": 0, "right": 0, "float": 0}
			for w in on:
				per[on[w]] += 1
			if per.left > 2 or per.right > 2 or per.float > 1:
				ok = false
	check(ok, "all %d sequences: speaker always on stage, at most 2 per side + 1 floating, exits only of present actors" % seqs.size())
	# a finale with many keepers rotates the right-hand side
	var fin := SceneDialogue.plan(Story.lines("finale"), "Elio")
	var exits := 0
	for st in fin:
		exits += st.exit.size()
	check(exits > 0, "the 12-keeper finale rotates actors out (%d exits)" % exits)


# ---------------------------------------------------------------- actor state machine

func test_actor() -> void:
	print("[actor entrance / exit state machine]")
	var a := Actor.new()
	var exited := []
	a.exited.connect(func(x): exited.append(x))
	root.add_child(a)
	a.size = Vector2(300, 400)
	eq(a.state, Actor.State.ABSENT, "starts absent")
	check(not a.visible, "...and hidden")
	a.enter("Kess Varrow", 1, 0.8, 1.0)
	eq(a.state, Actor.State.ENTERING, "enter -> ENTERING")
	var p0 := a.pose()
	check(float(p0.slide) > 100.0, "starts off to the right (slide %.0f)" % float(p0.slide))
	a.advance(0.1)
	eq(a.state, Actor.State.ENTERING, "still sliding after 0.1 s")
	check(float(a.pose().slide) < float(p0.slide), "slide shrinks")
	a.advance(1.0)
	eq(a.state, Actor.State.PRESENT, "-> PRESENT")
	check(absf(float(a.pose().slide)) < 0.5, "at rest in its slot")
	a.set_active(true)
	for i in 30:
		a.advance(0.05)
	check(a.focus > 0.99 and float(a.pose().dim) > 0.99, "the speaker steps forward and brightens")
	var pa: Dictionary = a.pose()
	a.set_active(false)
	for i in 30:
		a.advance(0.05)
	check(float(a.pose().dim) < float(pa.dim) and float(a.pose().scale) < float(pa.scale), "others dim and shrink")
	a.exit()
	eq(a.state, Actor.State.EXITING, "exit -> EXITING")
	a.advance(1.0)
	eq(a.state, Actor.State.ABSENT, "-> ABSENT")
	eq(exited.size(), 1, "exited signal fired once")
	check(not a.visible, "hidden after exit")
	a.exit()
	eq(exited.size(), 1, "exiting an absent actor does nothing")
	# blinking happens
	a.enter("Elio", -1, 0.2, 1.0)
	a.advance(1.0)
	var blinked := false
	for i in 400:
		a.advance(0.05)
		blinked = blinked or a.blinking
	check(blinked, "the actor blinks")
	# reduced motion: instant
	var r := Actor.new()
	r.instant = true
	root.add_child(r)
	r.enter("Pell", -1, 0.3, 0.9)
	eq(r.state, Actor.State.PRESENT, "reduced motion: enters instantly")
	r.set_active(true)
	check(r.focus == 1.0, "reduced motion: focus is instant")
	var pr: Dictionary = r.pose()
	check(float(pr.sx) == 1.0 and float(pr.sy) == 1.0 and float(pr.slide) == 0.0, "reduced motion: no squash, no slide")
	r.exit()
	eq(r.state, Actor.State.ABSENT, "reduced motion: leaves instantly")
	a.queue_free()
	r.queue_free()


# ---------------------------------------------------------------- art resolver chain

func _png(rel: String) -> void:
	var path := "user://t_scene_ai/%s.png" % rel
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var img := Image.create(8, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	img.save_png(path)


func test_resolver() -> void:
	print("[portrait chain: mood -> portrait -> characters -> borrowed champion]")
	DirAccess.make_dir_recursive_absolute("user://t_scene_ai")
	for rel in ["portraits/narrator__grave", "portraits/elio", "portraits/elio__amused", "characters/elio", "portraits/zara_nyx", "portraits/lyra_quill", "characters/pell"]:
		_png(rel)
	Assets.ai_root = "user://t_scene_ai"
	Assets.dev_root = ""
	Assets.clear_cache()
	check(Assets.narrator_art("neutral") == null, "no neutral Vellum art: null (the old emblem file is never used)")
	check(Assets.narrator_art("grave") != null and Assets.narrator_art("sad") == Assets.narrator_art("grave"), "narrator__grave serves grave and (folded) sad")
	check(Assets.portrait_mood("Elio", "amused") != Assets.portrait_mood("Elio", "grave"), "Elio: the amused portrait beats the plain one; other moods fall back to it")
	check(Assets.portrait_mood("Elio", "grave") == Assets.portrait("Elio"), "...mood -> portraits/<id> fallback")
	check(Assets.full_body("Elio") != null and Assets.full_body("Maren Oake") == null, "characters/<id> is the full-body slot")
	check(Assets.portrait("Pell") != null, "characters/<id> also serves as a last-resort portrait")
	var kess := Assets.borrowed("Kess Varrow")
	check(not kess.is_empty() and kess.from == "Zara Nyx", "Kess (no art) borrows her tower's champion portrait")
	var maren := Assets.borrowed("Maren Oake")
	check(not maren.is_empty() and maren.from == "Lyra Quill", "Maren borrows the Verdant Spire champion")
	check(Assets.borrowed("Zara Nyx").is_empty() and Assets.borrowed("Narrator").is_empty(), "cast with art (or Vellum) never borrows")
	var rival := str(Data.stages()[0].opponent)
	var br := Assets.borrowed(rival)
	check(not br.is_empty() and br.from == "Lyra Quill", "a tower-1 stage rival borrows Lyra's portrait (%s)" % rival)
	check(Assets.tint_for("Kess Varrow") != Assets.tint_for("Maren Oake") and Assets.tint_for("Kess Varrow") == Assets.tint_for("Kess Varrow"), "the recolour is stable per name and differs between names")
	Assets.reset_roots()


# ---------------------------------------------------------------- scene layer

func test_scene_layer() -> void:
	print("[scene layer: Elio + Pell + a rival talk]")
	Kit.reduced_motion = false
	var sc := SceneDialogue.new()
	root.add_child(sc)
	sc.size = Vector2(1080, 1920)
	var lines := [
		{"speaker": "Narrator", "line": "The Verdant Spire.", "mood": "wry"},
		{"speaker": "Elio", "line": "The bridges are moving.", "mood": "awed"},
		{"speaker": "Pell", "line": "Green smell. Happy smell.", "mood": "amused"},
		{"speaker": "Kess Varrow", "line": "Save the speeches.", "mood": "angry"},
	]
	sc.begin(lines, "01", true)
	check(sc.visible, "begin shows the layer")
	var infos := []
	for l in lines:
		infos.append(sc.show_line(l))
	eq(sc.actors.size(), 4, "four characters in the scene")
	eq(infos[0].expression, "amused", "Vellum's wry line -> amused face")
	eq(infos[3].expression, "angry", "Kess's angry line -> angry face")
	check(sc.actors["Kess Varrow"].active and not sc.actors["Elio"].active, "only the current speaker is active")
	eq(sc.actors["Narrator"].floating, true, "Vellum floats")
	check(sc.actors["Elio"].home_x < 0.5 and sc.actors["Kess Varrow"].home_x > 0.5, "Elio left, the rival right")
	check(sc.actors["Pell"].home_x < 0.5 and sc.actors["Pell"].home_scale < 1.0, "Pell stands inner-left, smaller")
	eq(sc.history.size(), 4, "history log records the lines")
	await process_frame
	await process_frame
	var panel := Control.new()
	sc.add_child(panel)
	sc.toggle_log(panel)
	await process_frame
	check(sc.log_open(), "history log opens")
	sc.toggle_log(panel)
	check(not sc.log_open(), "...and closes")
	# auto mode asks for the next line once the text is done
	var fired := [0]
	sc.advance_requested.connect(func(): fired[0] += 1)
	var lab := Label.new()
	lab.text = "Hello there"
	lab.visible_ratio = 1.0
	root.add_child(lab)
	sc.text_label = lab
	sc.auto = true
	sc.fast = true
	for i in 120:
		sc._process(0.1)
	check(fired[0] >= 1, "auto-advance requests the next line (%d)" % fired[0])
	sc.auto = false
	check(sc.type_time(80) <= 0.6, "fast type time is short")
	sc.end()
	await create_timer(0.7).timeout
	for w in sc.actors:
		check(not sc.actors[w].is_on_stage(), "%s left at the end" % w)
	check(not sc.visible, "the layer hides after the scene")
	# reduced motion: everything instant
	Kit.reduced_motion = true
	sc.begin(lines, "", false)
	sc.show_line(lines[0])
	sc.show_line(lines[1])
	eq(sc.actors["Elio"].state, Actor.State.PRESENT, "reduced motion: Elio is on stage immediately")
	check(sc.actors["Elio"].instant, "reduced motion: actors are instant")
	sc.end()
	Kit.reduced_motion = false
	sc.queue_free()
	lab.queue_free()
	panel.queue_free()


# ---------------------------------------------------------------- bark bubble

func test_bubble() -> void:
	print("[bark bubble: non-blocking, auto-dismiss, skippable]")
	Kit.reduced_motion = false
	var b := BarkBubble.new()
	root.add_child(b)
	var open := [true]
	b.blocked = func(): return open[0]
	b.say("Narrator", "A page begins.", "wry", "bark_test_a")
	check(b.visible and b.last_id == "bark_test_a" and b.expression == "amused", "shows the bark with the mood's face")
	check(b.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the bubble root never swallows board taps")
	b.advance(30.0)
	check(b.visible, "waits while a dialogue is open")
	open[0] = false
	b.advance(30.0)
	check(not b.visible, "auto-dismisses")
	b.say("Narrator", "One.", "dry", "bark_test_b")
	b.say("Narrator", "Two.", "dry", "bark_test_c")
	eq(b.last_id, "bark_test_b", "a second bark waits its turn")
	b.dismiss()
	eq(b.last_id, "bark_test_c", "skipping shows the queued bark")
	b.say("Narrator", "Urgent.", "solemn", "bark_test_d", true)
	eq(b.last_id, "bark_test_d", "an urgent bark replaces the current one")
	b.dismiss()
	check(not b.visible, "tap/skip dismisses")
	b.enabled = false
	b.say("Narrator", "Muted.", "dry", "bark_test_e")
	check(not b.visible, "disabled bubbles stay silent")
	b.enabled = true
	Kit.reduced_motion = true
	b.say("Narrator", "Still.", "dry", "bark_test_f")
	check(b.visible and b.modulate.a == 1.0, "reduced motion: appears without a fade")
	Kit.reduced_motion = false
	b.queue_free()


# ---------------------------------------------------------------- figures

func test_figures() -> void:
	print("[figures draw (painted / borrowed / sigil icon only): 7 expressions x speakers]")
	Assets.reset_roots()
	var c := Control.new()
	c.size = Vector2(400, 600)
	root.add_child(c)
	var count := [0]
	c.draw.connect(func():
		for who in ["Narrator", "Elio", "Pell", "Kess Varrow", "Maren Oake", "Lyra Quill", "Ari Zephyr"]:
			for e in Narrator.EXPRESSIONS:
				UIArt.draw_actor_figure(c, Rect2(0, 0, 400, 560), who, e, 0.5, e == "sad", 1.3)
				UIArt.draw_actor_figure(c, Rect2(0, 0, 120, 120), who, e, 0.0, false, 0.0, true)
				UIArt.draw_portrait(c, Rect2(0, 0, 200, 200), who, e, 0.3, false, 0.7)
				count[0] += 1)
	c.queue_redraw()
	await process_frame
	await process_frame
	check(count[0] == 49, "all %d figure/expression combinations drew" % count[0])
	var tex := Assets.portrait("Narrator")
	check(tex == Assets.narrator_art("neutral"), "the Narrator portrait goes through the expression resolver (never the old emblem)")
	c.queue_free()
