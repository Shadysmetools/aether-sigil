## Headless audio tests. Run:
##   Godot_console.exe --headless --path <game dir> --script res://tests/test_audio.gd
## Exits with the number of failures (0 = green).
extends SceneTree

const AM := preload("res://scripts/audio_manager.gd")
const Story := preload("res://scripts/story.gd")
const TMP_PREFS := "user://test_audio_prefs.cfg"
const ELEMENTS := ["fire", "water", "wind", "earth", "thunder", "ice", "wood", "tech", "light", "dark", "arcane", "space"]
const REQUIRED := ["ui_tap", "ui_confirm", "ui_back", "ui_locked", "ui_page", "step_stone", "step_grass", "step_water",
	"summon_burst", "hit_melee", "hit_heavy", "hit_critical", "defend_shield", "miss_whoosh", "ko_dissolve", "level_up",
	"evolve_build", "evolve_burst", "fusion_merge", "victory_sting", "defeat_sting", "sigil_damage", "capsule_node",
	"statue_hop", "stone_crack_build", "petrify_shatter", "monster_awaken_roar_generic", "repetrify", "stone_chip_hit",
	"statue_crumble"]

var passed := 0
var failed := 0
var am: Node


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("  PASS  ", label)
	else:
		failed += 1
		print("  FAIL  ", label)


func _initialize() -> void:
	print("Aether Sigil audio tests")
	_run.call_deferred()


func _run() -> void:
	am = _fresh()
	test_buses()
	test_hooks_resolve()
	test_required_ids()
	test_theme_ambience()
	test_music()
	test_play_sfx()
	test_voice_missing_is_silent()
	test_voice_keys_match_python()
	test_prefs()
	await test_rapid_crossfade()
	am.queue_free()
	if FileAccess.file_exists(TMP_PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PREFS))
	for i in 3:
		await process_frame
	print("%d pass / %d fail" % [passed, failed])
	quit(mini(failed, 255))


## A manager instance on a temp prefs file (never the autoload, never the player's prefs).
func _fresh() -> Node:
	var n: Node = AM.new()
	n.prefs_path = TMP_PREFS
	root.add_child(n)
	n.setup()
	return n


func test_buses() -> void:
	for b in ["Master", "Music", "SFX", "Voice", "Ambience"]:
		check(AudioServer.get_bus_index(b) != -1, "bus %s exists" % b)
	check(am.silent == (DisplayServer.get_name() == "headless"), "silent mode follows the headless display server")


## Every backticked id in a HOOKS.md table row resolves to an importable AudioStream.
func test_hooks_resolve() -> void:
	var md := FileAccess.get_file_as_string("res://audio/HOOKS.md")
	check(md.length() > 0, "HOOKS.md readable")
	var re := RegEx.new()
	re.compile("^\\|[^|]*\\| `([a-z0-9_]+)` \\|")
	var ids: Array[String] = []
	for line in md.split("\n"):
		var m := re.search(line)
		if m:
			ids.append(m.get_string(1))
	check(ids.size() >= 60, "HOOKS.md lists %d ids" % ids.size())
	var bad: Array[String] = []
	for id in ids:
		var files: Array = []
		if am.registry.sfx.has(id):
			files = am.registry.sfx[id].files
		elif am.registry.ambience.has(id):
			files = am.registry.ambience[id].files
		elif am.registry.music.has(id):
			files = [am.registry.music[id].file]
		if files.is_empty():
			bad.append(id + " (not in registry)")
		for f in files:
			if not ResourceLoader.exists(f) or not (load(f) is AudioStream):
				bad.append("%s -> %s" % [id, f])
	check(bad.is_empty(), "every HOOKS id resolves to a file %s" % [bad.slice(0, 5)])


func test_required_ids() -> void:
	var missing: Array[String] = []
	for id in REQUIRED:
		if not am.has_sfx(id):
			missing.append(id)
	for e in ELEMENTS:
		if not am.has_sfx("cast_" + e):
			missing.append("cast_" + e)
	check(missing.is_empty(), "required SFX ids present %s" % [missing])


func test_theme_ambience() -> void:
	var themes := {}
	var bible: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/AETHER_SIGIL_MASTER_GAME_BIBLE.json"))
	for t in bible.towers:
		themes[str(t.theme)] = true
	var bad: Array = []
	for th in themes:
		var id := str(am.registry.theme_ambience.get(th, ""))
		if id == "" or not am.registry.ambience.has(id):
			bad.append(th)
	check(bad.is_empty(), "every bible tower theme has an ambience loop %s" % [bad])
	am.play_ambience_for_theme("Wind", 0.0)
	check(am.current_ambience == "amb_wind", "play_ambience_for_theme(Wind) -> amb_wind")
	am.stop_ambience(0.0)


func test_music() -> void:
	for id in ["title", "battle", "boss", "victory", "defeat"]:
		check(am.registry.music.has(id), "music %s registered" % id)
	am.play_music("battle", 0.0)
	check(am.current_music == "battle", "play_music(battle) is current")
	var s: AudioStream = load(am.registry.music.battle.file)
	check(s is AudioStreamOggVorbis and (s as AudioStreamOggVorbis).loop, "battle music stream loops")
	am.play_music("does_not_exist", 0.0)
	check(am.current_music == "", "unknown music id stops music, no error")
	am.stop_music(0.0)


func test_play_sfx() -> void:
	check(am.play_sfx("ui_tap") != null, "play_sfx non-positional")
	check(am.play_sfx("hit_melee", Vector2(10, 20), 0.06) is AudioStreamPlayer2D, "play_sfx 2D")
	check(am.play_sfx("stone_chip_hit", Vector3(1, 0, 2), 0.06) is AudioStreamPlayer3D, "play_sfx 3D")
	for i in 40:  # more than the pool: must recycle, never fail
		am.play_sfx("step_stone", null, 0.06)
	check(am.play_sfx("step_stone") != null, "pool recycles past POOL_SIZE")
	check(am.play_sfx("no_such_sound") == null, "unknown sfx id = null, no error")


func test_voice_missing_is_silent() -> void:
	check(am.play_voice("no_such_line") == false, "missing voice line id -> false")
	check(am.play_voice_line("Elio", "A line nobody wrote.") == false, "unknown speaker/text -> false")
	var saved: Dictionary = am.voice_index
	am.voice_index = {"by_id": {"ghost": "res://audio/voices/elio/ghost.ogg"}, "by_key": {}}
	check(am.play_voice("ghost") == false, "indexed but missing file -> false, no error")
	am.voice_index = saved
	check(not am.is_voice_playing(), "nothing is playing after missing voices")


## LINES.json keys are md5(speaker + '\n' + line) computed in Python; the game must compute the same
## key from the {speaker, line} it shows (story.gd), including non-ASCII text.
func test_voice_keys_match_python() -> void:
	check(AM.voice_key("Elio", "Capsule ready — go") == "5ddf1165f80bf8c41b087bf9f290b1bf", "voice_key = Python md5 (UTF-8)")
	var path := "res://audio/voices/LINES.json"
	if not FileAccess.file_exists(path):
		check(false, "LINES.json exists")
		return
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var bad := 0
	for ln in doc.lines:
		if AM.voice_key(str(ln.speaker), str(ln.text)) != str(ln.key):
			bad += 1
	check(doc.lines.size() > 500 and bad == 0, "all %d LINES.json keys match voice_key (%d bad)" % [doc.lines.size(), bad])
	var keys := {}
	var has_rival_barks := false
	for ln in doc.lines:
		keys[str(ln.key)] = true
		for a in ln.get("aliases", []):  # --rival-globals generic: one file, every rival's key
			keys[str(a)] = true
		has_rival_barks = has_rival_barks or str(ln.get("group", "")) == "rival_bark"
	var g1: Dictionary = Story.global_line(1, "Ari Voss")
	check(keys.has(AM.voice_key(g1.speaker, g1.line)), "story.gd global_line(1) is in LINES.json")
	if has_rival_barks:  # absent only with --rival-globals skip
		var g2: Dictionary = Story.global_line(2, "Ari Voss")
		check(keys.has(AM.voice_key(g2.speaker, g2.line)), "rival bark for Ari Voss is in LINES.json")
	var pro: Array = Story.lines("prologue")
	check(not pro.is_empty() and keys.has(AM.voice_key(str(pro[0].speaker), str(pro[0].line))), "prologue line 1 is in LINES.json")


## battle -> victory -> title inside one fade time: the reused player's old fade-out must not stop
## the new track. Runs with real playback (silent off) and stops everything afterwards.
func test_rapid_crossfade() -> void:
	am.silent = false
	am.play_music("battle", 0.4)
	await process_frame
	am.play_music("victory", 0.4)
	await process_frame
	am.play_music("title", 0.4)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 900:
		await process_frame
	var playing := []
	for c in am.get_children():
		if c is AudioStreamPlayer and c.bus == &"Music" and c.playing:
			playing.append(c)
	check(playing.size() == 1, "after rapid crossfades exactly one music player plays (%d)" % playing.size())
	check(playing.size() == 1 and playing[0].stream == load(am.registry.music.title.file), "and it is the title track")
	check(playing.size() == 1 and playing[0].volume_db > -1.0, "faded fully in (%.1f dB)" % (playing[0].volume_db if playing.size() else -99.0))
	am.stop_all()
	for c in am.get_children():  # release the playbacks before quit (headless quit mid-sound leaks them)
		if c is AudioStreamPlayer:
			c.stream = null
	am._streams.clear()
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 400:  # the audio thread frees a stopped playback on its next mix
		await process_frame
	am.silent = true


func test_prefs() -> void:
	am.set_volume("Music", 0.25)
	am.set_volume("SFX", 0.5)
	check(FileAccess.file_exists(TMP_PREFS), "prefs saved to the injected path")
	var b: Node = AM.new()
	b.prefs_path = TMP_PREFS
	root.add_child(b)
	b.setup()
	check(is_equal_approx(b.get_volume("Music"), 0.25) and is_equal_approx(b.get_volume("SFX"), 0.5), "volumes reload from prefs")
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), linear_to_db(0.5)), "SFX bus volume applied")
	b.set_volume("Music", 0.0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "volume 0 mutes the bus")
	b.queue_free()
