## Stage progression: stage 1 starts unlocked; winning stage N unlocks stage N+1.
## Saved as JSON to user:// (local save). The path is injectable so tests never touch the real save.
extends RefCounted

const Data = preload("res://scripts/data_loader.gd")
const DEFAULT_PATH := "user://aether_sigil_save.json"

var path := DEFAULT_PATH
var unlocked := 1                ## number of stages unlocked, in play order (index < unlocked)
var cleared: Dictionary = {}     ## stage_id -> true
var squad: Array = []            ## the 4 monster ids taken into battle (Build Your Squad)


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path
	load_save()


func load_save() -> void:
	unlocked = 1
	cleared = {}
	squad = Data.default_squad()
	if not FileAccess.file_exists(path):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) == TYPE_DICTIONARY:
		unlocked = clampi(int(d.get("unlocked", 1)), 1, maxi(1, Data.stage_count()))
		cleared = d.get("cleared", {})
		set_squad(d.get("squad", []))  # saves from before squads fall back to the default


func save() -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("progress: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify({"unlocked": unlocked, "cleared": cleared, "squad": squad}))
	f.close()
	return true


func is_unlocked(stage_id: String) -> bool:
	var s := Data.stage(stage_id)
	return not s.is_empty() and int(s.index) < unlocked


## Records a win and unlocks the next stage. Returns the next stage id ("" after the last).
func record_win(stage_id: String) -> String:
	var s := Data.stage(stage_id)
	if s.is_empty():
		return ""
	cleared[stage_id] = true
	var nxt := int(s.index) + 1
	unlocked = maxi(unlocked, mini(nxt + 1, Data.stage_count()))
	save()
	return next_stage_id(stage_id)


static func next_stage_id(stage_id: String) -> String:
	var s := Data.stage(stage_id)
	if s.is_empty() or int(s.index) + 1 >= Data.stage_count():
		return ""
	return str(Data.stages()[int(s.index) + 1].stage_id)


## Accepts exactly squad_size distinct ids from the collection; anything else keeps the default.
func set_squad(ids: Array) -> bool:
	var coll := Data.squad_collection()
	var ok := ids.size() == Data.squad_size()
	var seen := {}
	for id in ids:
		ok = ok and coll.has(id) and not seen.has(id)
		seen[id] = true
	squad = ids.duplicate() if ok else Data.default_squad()
	return ok


func reset() -> void:
	unlocked = 1
	cleared = {}
	squad = Data.default_squad()
	save()
