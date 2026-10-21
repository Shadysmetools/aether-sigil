## Headless boot-intro tests. Run:
##   Godot_console.exe --headless --path <game dir> --script res://tests/test_intro.gd
## Exits with the number of failures (0 = green).
extends SceneTree

const Seq = preload("res://scenes/intro/intro_sequence.gd")
const Studio = preload("res://scenes/intro/studio_intro.gd")
const Title = preload("res://scenes/intro/title_intro.gd")
const SEQ_SCENE := preload("res://scenes/intro/intro_sequence.tscn")
const STUDIO_SCENE := preload("res://scenes/intro/studio_intro.tscn")
const TITLE_SCENE := preload("res://scenes/intro/title_intro.tscn")
const TMP_PREFS := "user://test_intro_prefs.cfg"
const TODAY := "2026-10-21"
const SPEED := 4.0           # Engine.time_scale while running timelines
const REAL_CAP_MS := 15000   # a hang is a FAIL, never a timeout

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
	print("Aether Sigil intro tests")
	_run.call_deferred()


func _run() -> void:
	test_audio_files()
	test_prefs()
	test_static_durations()
	test_skip_event_filter()
	Engine.time_scale = SPEED
	await test_short_mode_when_date_matches()
	await test_full_mode_on_new_day()
	await test_studio_natural_duration(false)
	await test_studio_natural_duration(true)
	await test_title_reaches_idle()
	await test_sequence_emits_finished()
	await test_skip_walks_steps()
	Engine.time_scale = 1.0
	await _frames(8)  # let freed players release their audio playbacks
	await create_timer(0.3, true, false, true).timeout
	_rm(TMP_PREFS)
	print("%d pass / %d fail" % [passed, failed])
	quit(mini(failed, 255))  # exit codes wrap at 256


# ------------------------------------------------------------ pure checks

func test_audio_files() -> void:
	for f in ["res://audio/intro/smetools_sting.wav", "res://audio/intro/title_riser.wav"]:
		check(FileAccess.file_exists(f), "%s exists" % f)
		var fa := FileAccess.open(f, FileAccess.READ)
		var n := fa.get_length() if fa else -1
		check(n > 10000 and n < 400 * 1024, "%s is under 400 KB (got %d bytes)" % [f, n])
		check(load(f) is AudioStream, "%s imports as an AudioStream" % f)


func test_prefs() -> void:
	_rm(TMP_PREFS)
	check(Seq.should_play_full(TMP_PREFS, TODAY), "no prefs file -> full intro")
	Seq.mark_full_played(TMP_PREFS, TODAY)
	check(not Seq.should_play_full(TMP_PREFS, TODAY), "same day -> short intro")
	check(Seq.should_play_full(TMP_PREFS, "2026-10-22"), "next day -> full intro again")
	check(TMP_PREFS != Seq.PREFS_PATH and Seq.PREFS_PATH == "user://intro_prefs.cfg", "prefs live in their own file, not the main save")


func test_static_durations() -> void:
	var full := Studio.get_duration(false)
	var short := Studio.get_duration(true)
	check(full >= 2.5 and full <= Seq.MAX_FULL_SECONDS, "studio full duration %.2f s within 2.5..5" % full)
	check(short >= 0.6 and short <= 1.2, "studio short duration %.2f s ~1 s" % short)
	check(Title.get_duration() <= 3.5, "title build %.2f s <= 3.5" % Title.get_duration())
	check(full + Title.get_duration() <= 8.5, "full intro to idle <= 8.5 s")


func test_skip_event_filter() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	check(Seq.is_skip_event(key), "key press skips")
	var echo := key.duplicate()
	echo.echo = true
	check(not Seq.is_skip_event(echo), "key echo ignored")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	check(Seq.is_skip_event(mb), "click / emulated tap skips")
	var up := mb.duplicate()
	up.pressed = false
	check(not Seq.is_skip_event(up), "button release ignored")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	check(not Seq.is_skip_event(touch), "raw touch ignored (arrives as emulated mouse; no double skip)")


# ------------------------------------------------------------ timeline checks

func test_short_mode_when_date_matches() -> void:
	_rm(TMP_PREFS)
	Seq.mark_full_played(TMP_PREFS, TODAY)
	var seq := _make_seq("")
	await process_frame
	check(seq.play_full_intro == false, "date matches -> play_full_intro is false")
	check(seq.studio != null and seq.studio.short_mode, "date matches -> studio runs the short ident")
	seq.queue_free()
	await process_frame


func test_full_mode_on_new_day() -> void:
	_rm(TMP_PREFS)
	Seq.mark_full_played(TMP_PREFS, "2026-10-20")
	var seq := _make_seq("")
	await process_frame
	check(seq.play_full_intro and not seq.studio.short_mode, "new day -> full ident")
	check(not Seq.should_play_full(TMP_PREFS, TODAY), "full intro records today's date")
	seq.queue_free()
	await process_frame


func test_studio_natural_duration(short: bool) -> void:
	var s := STUDIO_SCENE.instantiate()
	s.short_mode = short
	var got := [false]
	s.finished.connect(func() -> void: got[0] = true)
	root.add_child(s)
	var ok := await _wait(func() -> bool: return got[0])
	var want := Studio.get_duration(short)
	check(ok, "studio (%s) emits finished on its own" % ("short" if short else "full"))
	check(s.finished_at >= want - 0.15 and s.finished_at <= minf(want + 0.4, Seq.MAX_FULL_SECONDS),
		"studio (%s) ran %.2f s (want ~%.1f, max %.1f)" % ["short" if short else "full", s.finished_at, want, Seq.MAX_FULL_SECONDS])
	s.queue_free()
	await process_frame


func test_title_reaches_idle() -> void:
	var t := TITLE_SCENE.instantiate()
	root.add_child(t)
	var ok := await _wait(func() -> bool: return t.is_idle)
	check(ok, "title reaches idle on its own")
	check(t.idle_at > 2.5 and t.idle_at <= Title.get_duration() + 0.4, "title build took %.2f s (<= %.1f)" % [t.idle_at, Title.get_duration() + 0.4])
	t.queue_free()
	await process_frame


func test_sequence_emits_finished() -> void:
	var seq := _make_seq("full")
	var got := [false]
	seq.finished.connect(func() -> void: got[0] = true)
	var to_idle := await _wait(func() -> bool: return seq.step == "title" and seq.title.is_idle)
	check(to_idle, "sequence plays studio -> title idle with no input")
	await _frames(4)
	seq.skip()  # "Tap to begin"
	check(got[0] and seq.step == "done", "tap at idle -> sequence emits finished")
	seq.queue_free()
	await process_frame


func test_skip_walks_steps() -> void:
	var seq := _make_seq("full")
	var got := [false]
	seq.finished.connect(func() -> void: got[0] = true)
	await _frames(3)
	check(seq.step == "studio", "starts on the studio ident")
	root.push_input(_key())
	check(seq.step == "title", "1st key press skips the studio ident")
	root.push_input(_click(true))
	check(not seq.title.is_idle, "a 2nd press inside the debounce window is ignored (one tap = one skip)")
	await _wait_game(Seq.SKIP_DEBOUNCE + 0.05)
	root.push_input(_click(false))
	check(not seq.title.is_idle, "mouse release does not skip")
	root.push_input(_click(true))
	check(seq.title.is_idle and not got[0], "next tap jumps the title build to idle")
	await _wait_game(Seq.SKIP_DEBOUNCE + 0.05)
	root.push_input(_key())
	check(got[0] and seq.step == "done", "next key press finishes the sequence")
	seq.queue_free()
	await process_frame


# ------------------------------------------------------------ helpers

func _make_seq(force: String) -> Node:
	var seq := SEQ_SCENE.instantiate()
	seq.prefs_path = TMP_PREFS
	seq.today_override = TODAY
	seq.force_mode = force
	seq.next_scene = ""
	root.add_child(seq)
	return seq


func _wait(cond: Callable) -> bool:
	var start := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - start > REAL_CAP_MS:
			return false
		await process_frame
	return true


func _wait_game(seconds: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(seconds * 1000.0 / Engine.time_scale) + 20:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _key() -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = KEY_ENTER
	k.pressed = true
	return k


func _click(pressed: bool) -> InputEventMouseButton:
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.pressed = pressed
	return m


func _rm(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
