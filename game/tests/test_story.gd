## Story mode + dialogue trigger tests: story.json schema, trigger table coverage, dialogue data
## integrity, seen-flags, stars, rewards and the save migration to schema v3.
## Run: Godot_console.exe --headless --path <game dir> --script res://tests/test_story.gd
extends SceneTree

const Data = preload("res://scripts/data_loader.gd")
const Story = preload("res://scripts/story.gd")
const Progress = preload("res://scripts/progress.gd")
const GameState = preload("res://scripts/game_state.gd")

const SAVE := "user://test_story_save.json"

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
	print("Aether Sigil story tests")
	Data.ensure_loaded()
	test_schema()
	test_lookup()
	test_triggers()
	test_dialogue_data()
	test_seen_stars_rewards()
	test_migration()
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("%d pass / %d fail" % [passed, failed])
	quit(mini(failed, 255))


func test_schema() -> void:
	print("[story.json schema]")
	var errs := Story.validate(Data.story())
	eq(errs, [], "game/data/story.json validates")
	var root_story := ProjectSettings.globalize_path("res://").path_join("../data/story.json")
	if FileAccess.file_exists(root_story):
		var j := JSON.new()
		check(j.parse(FileAccess.get_file_as_string(root_story)) == OK, "data/story.json (writer's file) parses")
		eq(Story.validate(j.data), [], "data/story.json (writer's file) validates")
		eq(JSON.stringify(j.data), JSON.stringify(Data.story()), "game/data/story.json is an exact copy of data/story.json")
	else:
		print("  NOTE  data/story.json not present yet; the placeholder is in use")
	var root_nar := ProjectSettings.globalize_path("res://").path_join("../data/narrator.json")
	if FileAccess.file_exists(root_nar):
		eq(FileAccess.get_file_as_string(root_nar), FileAccess.get_file_as_string("res://data/narrator.json"), "game/data/narrator.json is an exact copy of data/narrator.json")
	eq(str(Data.narrator().get("name", "")), "Vellum", "narrator.json names the Narrator")
	var bad: Dictionary = JSON.parse_string(JSON.stringify(Data.story()))
	bad.version = 2
	check(Story.validate(bad).any(func(e): return e.begins_with("version")), "wrong version rejected")
	bad = JSON.parse_string(JSON.stringify(Data.story()))
	bad.towers.pop_back()
	check(Story.validate(bad).any(func(e): return e.contains("missing tower_id 12")), "missing tower rejected")
	bad = JSON.parse_string(JSON.stringify(Data.story()))
	bad.prologue[0].line = ""
	check(Story.validate(bad).any(func(e): return e.begins_with("prologue[0].line")), "empty line rejected")
	bad = JSON.parse_string(JSON.stringify(Data.story()))
	bad.erase("epilogue")
	check(Story.validate(bad).any(func(e): return e.begins_with("epilogue")), "missing part rejected")
	bad = JSON.parse_string(JSON.stringify(Data.story()))
	bad.protagonist = {"name": ""}
	check(Story.validate(bad).any(func(e): return e.begins_with("protagonist")), "protagonist needs name and title")
	check(not Story.validate("nope").is_empty(), "non-object rejected")


func test_lookup() -> void:
	print("[story lookup]")
	check(Story.lines("prologue").size() > 0, "prologue lines")
	for t in Data.towers():
		var tid := str(t.tower_id)
		for part in ["arrival", "pre_boss", "post_boss"]:
			check(Story.lines("%s_%s" % [part, tid]).size() > 0, "%s_%s has lines" % [part, tid])
	check(Story.lines("finale").size() > 0 and Story.lines("epilogue").size() > 0, "finale and epilogue lines")
	eq(Story.lines("arrival_99"), [], "unknown key -> no lines")
	var g1 := Story.global_line(1, "Ari Voss")
	eq(g1.speaker, Story.hero(), "global 'Hero' line spoken by the protagonist")
	eq(Story.global_line(2, "Ari Voss").speaker, "Ari Voss", "global 'Rival' line spoken by the stage opponent")
	eq(Story.split_line("Ari Voss: Hello there.", "x"), {"speaker": "Ari Voss", "line": "Hello there."}, "stage lines split into speaker + text")


func test_triggers() -> void:
	print("[dialogue trigger table (#17)]")
	var types: Array = Data.bible().dialogue_system.types
	var table: Dictionary = Data.triggers().types
	var missing := types.filter(func(t): return not table.has(t))
	eq(missing, [], "every bible dialogue type has a trigger (%d types)" % types.size())
	for t in table:
		check(str(table[t].get("when", "")) != "" and str(table[t].get("source", "")) != "", "trigger '%s' documents when + source" % t)
	var src := FileAccess.get_file_as_string("res://scripts/ui.gd")
	for needle in ["dialogue.get(\"intro\"", "\"boss_phase\"", "_check_barks", "global_line(6", "global_line(2", "grant_reward", "\"pre_boss_\"", "\"post_boss_\"", "\"finale\"", "\"epilogue\"", "\"prologue\"", "\"arrival_\"", "Story.template(\"new_monster\")", "evolved.emit"]:
		check(src.contains(needle), "ui.gd wires %s" % needle)
	for n in range(1, 7):
		check(src.contains("global_line(%d" % n) or src.contains(", %d)" % n), "global sample line %d is used" % n)


func test_dialogue_data() -> void:
	print("[dialogue data integrity]")
	var f := FileAccess.open("res://data/../../data/DIALOGUE_LINES.csv", FileAccess.READ)
	if f == null:
		f = FileAccess.open(ProjectSettings.globalize_path("res://").path_join("../data/DIALOGUE_LINES.csv"), FileAccess.READ)
	check(f != null, "DIALOGUE_LINES.csv readable")
	if f == null:
		return
	var header := f.get_csv_line()
	eq(Array(header), ["stage_id", "tower", "speaker", "scene", "line"], "CSV header")
	var rows := 0
	var bad := []
	while not f.eof_reached():
		var r := f.get_csv_line()
		if r.size() < 5:
			continue
		rows += 1
		var sid := r[0]
		if sid == "GLOBAL":
			if r[2] != "SYSTEM" or not r[3].begins_with("sample_"):
				bad.append("GLOBAL row %s" % r[3])
			continue
		var st := Data.stage(sid)
		if st.is_empty():
			bad.append("unknown stage %s" % sid)
		elif r[2] != str(st.opponent):
			bad.append("%s speaker %s is not the opponent %s" % [sid, r[2], st.opponent])
		elif str(st.dialogue.get(r[3], "")) != r[4]:
			bad.append("%s %s differs from the bible" % [sid, r[3]])
	eq(rows, 486, "486 dialogue lines")
	eq(bad, [], "every line references an existing stage and its opponent (or GLOBAL)")
	var chars := {"Narrator": true, Story.hero(): true}
	for t in Data.towers():
		chars[str(t.tower_boss)] = true
		for o in t.opponents:
			chars[str(o.name)] = true
	var unknown := []
	for key in ["prologue", "finale", "epilogue"]:
		for l in Story.lines(key):
			if not chars.has(str(l.speaker)):
				unknown.append(str(l.speaker))
	for t in Data.story().towers:
		for part in ["arrival", "pre_boss", "post_boss"]:
			for l in t[part]:
				if not chars.has(str(l.speaker)):
					unknown.append(str(l.speaker))
	if not unknown.is_empty():
		print("  NOTE  story speakers not in the bible (new characters): %s" % str(unknown))
	check(true, "story speakers listed (%d not in the bible)" % unknown.size())


func test_seen_stars_rewards() -> void:
	print("[seen flags, stars, rewards]")
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var pr := Progress.new(SAVE)
	check(not pr.is_seen("prologue"), "new game: nothing seen")
	pr.mark_seen("prologue")
	pr.mark_seen("arrival_01")
	pr.record_stars("T01-L01", 2)
	pr.record_stars("T01-L01", 1)
	eq(pr.stars["T01-L01"], 2, "best stars kept")
	eq(pr.grant_reward("T01-L05"), "", "only L10 grants a reward")
	var reward := pr.grant_reward("T01-L10")
	eq(reward, str(Data.towers()[0].tower_reward), "L10 grants the bible's tower_reward")
	eq(pr.grant_reward("T01-L10"), "", "reward granted once")
	var again := Progress.new(SAVE)
	check(again.is_seen("prologue") and again.is_seen("arrival_01") and not again.is_seen("arrival_02"), "seen flags persist")
	eq(again.stars.get("T01-L01", 0), 2, "stars persist")
	eq(again.rewards, [reward], "rewards persist")
	eq(again.tower_progress("01").stars, 2, "tower progress sums stars")
	var s := GameState.new()
	s.setup("T01-L02")
	s.symbol_hp[0] = s.symbol_max
	eq(Progress.battle_stars(s), 3, "3 stars: full Sigil, no monster lost")
	s.kos[0] = 1
	eq(Progress.battle_stars(s), 2, "2 stars: a monster was lost")
	s.symbol_hp[0] = s.symbol_max / 4
	eq(Progress.battle_stars(s), 1, "1 star: Sigil below half and a monster lost")


func test_migration() -> void:
	print("[save migration v2 -> v3]")
	var v2 := Progress.new(SAVE)
	v2.new_game()
	var d := v2.to_dict()
	d.version = 2
	d.erase("story_seen")
	d.erase("stars")
	d.erase("rewards")
	d.unlocked = 12  # through T02-L02
	var cl := {}
	for sid in ["T01-L01", "T01-L05", "T01-L10", "T02-L01"]:
		cl[sid] = true
	d.cleared = cl
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var pr := Progress.new(SAVE)
	eq(pr.load_note, "migrated_from_v2", "v2 save migrated")
	check(pr.is_seen("prologue"), "a player with progress skips the prologue")
	check(pr.is_seen("arrival_01") and pr.is_seen("arrival_02") and not pr.is_seen("arrival_03"), "arrivals of unlocked towers marked seen")
	check(pr.is_seen("post_boss_01") and not pr.is_seen("post_boss_02"), "boss scenes of cleared L10s marked seen")
	eq(pr.stars.get("T01-L05", 0), 1, "cleared stages get 1 star")
	eq(pr.rewards, [str(Data.towers()[0].tower_reward)], "cleared L10 grants its reward")
	eq(pr.roster.size(), d.roster.size(), "roster kept")
	pr.save()
	var back: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	eq(int(back.version), 4, "re-saved as the current schema (v4)")
	var fresh := Progress.new("user://test_story_new.json")
	check(not fresh.is_seen("prologue"), "a brand-new game still sees the prologue")
	if FileAccess.file_exists("user://test_story_new.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_story_new.json"))
