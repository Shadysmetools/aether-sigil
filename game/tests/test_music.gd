## Headless per-level music tests. Run alone:
##   Godot_console.exe --headless --path <game dir> --script res://tests/test_music.gd
## Exits with the number of failures (0 = green).
extends SceneTree

const AM := preload("res://scripts/audio_manager.gd")
const BIBLE := "res://data/AETHER_SIGIL_MASTER_GAME_BIBLE.json"
const TMP_PREFS := "user://test_music_prefs.cfg"

var passed := 0
var failed := 0
var am: Node


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL  ", label)


func _initialize() -> void:
	print("Aether Sigil music tests")
	_run.call_deferred()


func _run() -> void:
	am = AM.new()
	am.prefs_path = TMP_PREFS
	root.add_child(am)
	am.setup()
	var bible: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BIBLE))
	test_map_covers_bible(bible)
	test_every_stage_resolves(bible)
	test_stage_mixes_distinct(bible)
	test_towers_and_stings(bible)
	test_play_headless(bible)
	test_intensity()
	am.stop_all()
	am.queue_free()
	if FileAccess.file_exists(TMP_PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PREFS))
	for i in 3:
		await process_frame
	print("%d pass / %d fail" % [passed, failed])
	quit(mini(failed, 255))


func _stage_ids(bible: Dictionary) -> Array:
	var out := []
	for t in bible.towers:
		for lv in t.levels:
			out.append(str(lv.stage_id))
	return out


func test_map_covers_bible(bible: Dictionary) -> void:
	check(not am.music_map.is_empty(), "music_map.json loads")
	var ids := _stage_ids(bible)
	check(ids.size() == 120, "bible has 120 stages (%d)" % ids.size())
	check(am.music_map.get("stages", {}).size() == ids.size(), "map has exactly one entry per stage")
	for t in bible.towers:
		check(am.music_map.get("towers", {}).has(str(t.tower_id)), "tower %s mapped" % t.tower_id)
	check(am.music_map.get("towers", {}).size() == 12, "12 towers mapped")


func test_every_stage_resolves(bible: Dictionary) -> void:
	var bad := []
	for sid in _stage_ids(bible):
		var info: Dictionary = am.stage_music_info(sid)
		var ok := not info.is_empty() and not (info.files as Array).is_empty()
		if ok:
			for f in info.files:
				if not ResourceLoader.exists(str(f)) or not (load(str(f)) is AudioStreamOggVorbis):
					ok = false
			ok = ok and float(info.pitch_scale) > 0.8 and float(info.pitch_scale) < 1.25
			ok = ok and float(info.intensity) >= 0.0 and float(info.intensity) <= 1.0
		if not ok:
			bad.append(sid)
	check(bad.is_empty(), "every stage resolves to existing OGG files with a sane mix (bad: %s)" % [bad.slice(0, 8)])
	# boss chambers use the boss arrangement; T12-L10 the final boss
	check(am.stage_music_info("T01-L10").track == "T01_boss", "T01-L10 plays the T01 boss arrangement")
	check(am.stage_music_info("T12-L10").track == "final_boss", "T12-L10 plays the final boss")
	check(am.stage_music_info("T05-L02").track.begins_with("T05_battle_"), "chambers play their tower's battle takes")


## No two stages in the game share an identical (track, pitch, filter, shelf, heat) mix.
func test_stage_mixes_distinct(bible: Dictionary) -> void:
	var seen := {}
	var dup := []
	for sid in _stage_ids(bible):
		var i: Dictionary = am.stage_music_info(sid)
		var key := "%s|%.4f|%d|%.1f|%.3f" % [i.track, i.pitch_scale, int(i.lowpass_hz), float(i.low_shelf_db), float(i.intensity)]
		if seen.has(key):
			dup.append("%s=%s" % [sid, seen[key]])
		seen[key] = sid
	check(dup.is_empty(), "all 120 stage mixes are distinct (dups: %s)" % [dup])
	# intensity rises with chamber number inside every tower
	for t in bible.towers:
		var tw := str(t.tower_id)
		check(float(am.stage_music_info("T%s-L09" % tw).intensity) > float(am.stage_music_info("T%s-L01" % tw).intensity),
			"T%s: L09 hotter than L01" % tw)


func test_towers_and_stings(bible: Dictionary) -> void:
	for t in bible.towers:
		var tw: Dictionary = am.music_map.towers[str(t.tower_id)]
		var ex: Dictionary = am.music_map.tracks.get(str(tw.explore), {})
		check(not ex.is_empty() and ResourceLoader.exists(str(ex.files[0])), "T%s explore theme exists" % t.tower_id)
		for k in ["victory", "defeat"]:
			check(ResourceLoader.exists(str(tw.stings[k])), "T%s %s sting exists" % [t.tower_id, k])
	for tid in am.music_map.tracks:
		for f in am.music_map.tracks[tid].files:
			check(ResourceLoader.exists(str(f)), "track %s file %s exists" % [tid, f])


func test_play_headless(bible: Dictionary) -> void:
	check(am.silent, "headless run is silent")
	for sid in _stage_ids(bible):
		am.play_stage_music(sid, 0.0)
		if am.current_stage_music != sid:
			check(false, "play_stage_music(%s) becomes current" % sid)
			return
	check(true, "play_stage_music works for all 120 stages headless")
	var p: AudioStreamPlayer = am._music[am._music_active]
	check(p.stream is AudioStreamSynchronized, "battle music is a synchronized 2-stem stream")
	check(str(p.bus).begins_with("Music") and AudioServer.get_bus_index(p.bus) != -1, "stage music routes to a Music sub-bus")
	am.play_stage_music("T99-L99", 0.0)
	check(am.current_music == "battle", "unknown stage falls back to the generic battle track")
	am.play_tower_ambient_music("T03", 0.0)
	check(am.current_stage_music == "tower:03" and am.current_music == "T03_explore", "play_tower_ambient_music(T03)")
	am.play_tower_ambient_music(7, 0.0)
	check(am.current_music == "T07_explore", "play_tower_ambient_music(7)")
	check(am._music[am._music_active].pitch_scale == 1.0, "explore theme plays unpitched")
	am.play_tower_ambient_music("nope", 0.0)
	check(am.current_music == "title", "unknown tower -> title theme")
	am.play_stage_result("T04-L03", true, 0.0)
	check(am.current_music == "victory:04", "victory sting for tower 04")
	am.play_stage_result("T04-L03", false, 0.0)
	check(am.current_music == "defeat:04", "defeat sting for tower 04")
	am.play_world_map_music(0.0)
	check(am.current_music == "title", "world map plays the title theme")
	am.play_music("battle", 0.0)
	check(am._music[am._music_active].bus == &"Music" and am._music[am._music_active].pitch_scale == 1.0,
		"generic play_music resets bus + pitch")
	for b in AM.MUSIC_SUB_BUSES:
		var bi := AudioServer.get_bus_index(b)
		check(bi != -1 and AudioServer.get_bus_send(bi) == &"Music" and AudioServer.get_bus_effect_count(bi) == 2,
			"sub-bus %s -> Music with shelf + low-pass" % b)


func test_intensity() -> void:
	am.play_stage_music("T02-L01", 0.0)
	var base: float = am.music_intensity
	var sync := am._music[am._music_active].stream as AudioStreamSynchronized
	am.set_battle_heat(0.9)
	check(is_equal_approx(am.music_intensity, base), "Sigils above 50 %% keep the stage baseline (%.2f)" % base)
	am.set_music_intensity(1.0, 0.0)
	check(sync != null and is_equal_approx(sync.get_sync_stream_volume(1), 0.0), "intensity 1 = heat stem at 0 dB")
	am.set_music_intensity(0.0, 0.0)
	check(sync != null and sync.get_sync_stream_volume(1) <= AM.HEAT_FLOOR_DB + 0.01, "intensity 0 = heat stem at floor")
	am.set_battle_heat(0.2)
	check(am.music_intensity > 0.85, "a Sigil under 50 %% raises the heat (%.2f)" % am.music_intensity)
	am.play_tower_ambient_music("01", 0.0)
	am.set_music_intensity(1.0, 0.0)  # explore track is not layered: must be a harmless no-op
	check(am.current_music == "T01_explore", "set_music_intensity on a non-layered track is a no-op")
