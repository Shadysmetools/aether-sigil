## The player's save: stage progression, the owned roster (levels, XP, evolutions, fusions) and
## the squad. JSON in user:// (never .tres). Schema version 2; older saves are migrated on load.
## The path is injectable so tests never touch the real save.
##   v1 (2026-10-20/21): {unlocked, cleared, squad: [monster ids]}  (squad optional)
##   v2: {version: 2, unlocked, cleared, roster: [instances], squad: [uids], next_uid}
extends RefCounted

const Data = preload("res://scripts/data_loader.gd")
const Prog = preload("res://scripts/progression.gd")
const DEFAULT_PATH := "user://aether_sigil_save.json"
const VERSION := 2

var path := DEFAULT_PATH
var unlocked := 1                ## number of stages unlocked, in play order (index < unlocked)
var cleared: Dictionary = {}     ## stage_id -> true
var roster: Array = []           ## owned monster instances (see progression.gd)
var squad: Array = []            ## uids of the 4 monsters taken into battle
var next_uid := 1
var load_note := ""              ## "new", "loaded", "migrated_from_v1", "corrupt_reset"


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path
	load_save()


func new_game() -> void:
	unlocked = 1
	cleared = {}
	roster = []
	next_uid = 1
	for id in Data.squad_collection():
		roster.append(Prog.new_instance(_take_uid(), str(id)))
	squad = _uids_for_ids(Data.default_squad())


func _take_uid() -> String:
	var u := "OWN-%04d" % next_uid
	next_uid += 1
	return u


func _uids_for_ids(ids: Array) -> Array:
	var out := []
	for id in ids:
		for inst in roster:
			if str(inst.base_id) == str(id) and not out.has(inst.uid):
				out.append(inst.uid)
				break
	return out


func load_save() -> void:
	new_game()
	load_note = "new"
	if not FileAccess.file_exists(path):
		return
	var j := JSON.new()  # instance parse: a corrupt file returns an error code instead of logging ERROR
	var d: Variant = j.data if j.parse(FileAccess.get_file_as_string(path)) == OK else null
	if typeof(d) != TYPE_DICTIONARY:
		load_note = "corrupt_reset"
		push_warning("progress: %s is not a valid save; starting a new game" % path)
		return
	var v := int(d.get("version", 1))
	unlocked = clampi(int(d.get("unlocked", 1)), 1, maxi(1, Data.stage_count()))
	cleared = d.get("cleared", {}) if typeof(d.get("cleared", {})) == TYPE_DICTIONARY else {}
	if v <= 1:
		# v1 had no roster: everyone owns the collection at level 1; the v1 squad held monster ids.
		var ids: Array = d.get("squad", [])
		var mapped := _uids_for_ids(ids)
		set_squad(mapped if mapped.size() == ids.size() else [])
		load_note = "migrated_from_v1"
		return
	var r: Variant = d.get("roster", [])
	if typeof(r) != TYPE_ARRAY or r.is_empty():
		load_note = "corrupt_reset"
		return
	roster = []
	for inst in r:
		if typeof(inst) == TYPE_DICTIONARY and inst.has("uid") and (inst.get("fused", false) or Data.has_monster(str(inst.get("base_id", "")))):
			inst.level = int(inst.get("level", 1))
			inst.xp = int(inst.get("xp", 0))
			inst.evo_stage = int(inst.get("evo_stage", 0))
			if inst.get("fused", false):  # JSON numbers load as floats
				inst.level_cap = int(inst.get("level_cap", 50))
				for k in inst.base:
					inst.base[k] = int(inst.base[k])
			roster.append(inst)
	next_uid = maxi(int(d.get("next_uid", 1)), roster.size() + 1)
	set_squad(d.get("squad", []))
	load_note = "loaded"


func to_dict() -> Dictionary:
	return {"version": VERSION, "unlocked": unlocked, "cleared": cleared, "roster": roster, "squad": squad, "next_uid": next_uid}


func save() -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("progress: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	return true


# ---------------------------------------------------------------- roster

func get_inst(uid: String) -> Dictionary:
	for inst in roster:
		if str(inst.uid) == uid:
			return inst
	return {}


## Battle records for the squad, keyed by uid (GameState.setup's `custom`).
func squad_records() -> Dictionary:
	var out := {}
	for uid in squad:
		var inst := get_inst(uid)
		if not inst.is_empty():
			out[uid] = Prog.battle_record(inst)
	return out


## Accepts exactly squad_size distinct owned uids; anything else falls back to the 4 strongest.
func set_squad(uids: Array) -> bool:
	var ok := uids.size() == Data.squad_size()
	var seen := {}
	for u in uids:
		ok = ok and not get_inst(str(u)).is_empty() and not seen.has(u)
		seen[u] = true
	squad = uids.duplicate() if ok else auto_squad()
	return ok


func auto_squad() -> Array:
	var sorted := roster.duplicate()
	sorted.sort_custom(func(a, b): return Prog.power(a) > Prog.power(b))
	var out := []
	for inst in sorted.slice(0, Data.squad_size()):
		out.append(inst.uid)
	return out


func taken_names(except_uids: Array = []) -> Dictionary:
	var d := {}
	for inst in roster:
		if not except_uids.has(inst.uid):
			d[str(inst.name).to_lower()] = true
	return d


# ---------------------------------------------------------------- after a battle

## Awards XP to every squad monster that was summoned in `state` (a finished GameState).
## Returns {uid: {xp, levels}}. Saves.
func award_battle(state, won: bool) -> Dictionary:
	var out := {}
	var tower := maxi(1, int(str(state.stage.get("tower_id", "1"))))
	for uid in squad:
		if not state.deployed.has(uid):
			continue
		var inst := get_inst(uid)
		if inst.is_empty():
			continue
		var xp := Prog.battle_xp(int(state.ko_by.get(uid, 0)), won, tower)
		out[uid] = {"xp": xp, "levels": Prog.add_xp(inst, xp)}
	save()
	return out


func evolve(uid: String) -> String:
	var inst := get_inst(uid)
	var line := Prog.evolve(inst) if not inst.is_empty() else ""
	if line != "":
		save()
	return line


func fusion_preview(uid_a: String, uid_b: String) -> Dictionary:
	var a := get_inst(uid_a)
	var b := get_inst(uid_b)
	var why := Prog.can_fuse(a, b, roster.size())
	if why != Prog.OK:
		return {"error": why}
	return Prog.fusion_preview(a, b, "OWN-%04d" % next_uid, taken_names([uid_a, uid_b]))


## Consumes both parents and adds the fused monster. Returns it, or {"error": reason}.
func fuse(uid_a: String, uid_b: String) -> Dictionary:
	var res := fusion_preview(uid_a, uid_b)
	if res.has("error"):
		return res
	_take_uid()
	roster = roster.filter(func(i): return i.uid != uid_a and i.uid != uid_b)
	roster.append(res)
	var sq := squad.filter(func(u): return u != uid_a and u != uid_b)
	if sq.size() < squad.size():
		sq.append(res.uid)
	set_squad(sq)
	save()
	return res


# ---------------------------------------------------------------- stages

func is_unlocked(stage_id: String) -> bool:
	var s := Data.stage(stage_id)
	return not s.is_empty() and int(s.index) < unlocked


## Records a win and unlocks the next stage. Returns the next stage id ("" after the last).
func record_win(stage_id: String) -> String:
	var s := Data.stage(stage_id)
	if s.is_empty():
		return ""
	cleared[stage_id] = true
	unlocked = maxi(unlocked, mini(int(s.index) + 2, Data.stage_count()))
	save()
	return next_stage_id(stage_id)


static func next_stage_id(stage_id: String) -> String:
	var s := Data.stage(stage_id)
	if s.is_empty() or int(s.index) + 1 >= Data.stage_count():
		return ""
	return str(Data.stages()[int(s.index) + 1].stage_id)


func reset() -> void:
	new_game()
	save()
