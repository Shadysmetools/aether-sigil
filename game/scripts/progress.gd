## The player's save: stage progression, the owned roster (levels, XP, evolutions, fusions) and
## the squad. JSON in user:// (never .tres). Schema version 2; older saves are migrated on load.
## The path is injectable so tests never touch the real save.
##   v1 (2026-10-20/21): {unlocked, cleared, squad: [monster ids]}  (squad optional)
##   v2: {version: 2, unlocked, cleared, roster: [instances], squad: [uids], next_uid}
##   v3: v2 + {story_seen: {key: true}, stars: {stage_id: 1-3}, rewards: [tower_reward strings]}
##       Migration to v3: a player who already progressed is not shown the story they skipped past
##       (prologue + arrivals of unlocked towers, boss scenes of cleared L10s are marked seen);
##       every cleared stage gets 1 star; cleared L10s grant their tower_reward.
##   v4 (Vessels / Bond, 2026-10-21): fused instances carry "bond" (draft cost = 80% of the
##       parents' Bond). Migration to v4: a fused instance without one gets it from its parents'
##       base ids (bible rarity, evolution 0); a parent that was itself a fusion counts at the
##       Bond of the child's rarity. Everything else is unchanged.
extends RefCounted

const Data = preload("res://scripts/data_loader.gd")
const Prog = preload("res://scripts/progression.gd")
const DEFAULT_PATH := "user://aether_sigil_save.json"
const Summon = preload("res://scripts/summon.gd")
const VERSION := 4

var path := DEFAULT_PATH
var unlocked := 1                ## number of stages unlocked, in play order (index < unlocked)
var cleared: Dictionary = {}     ## stage_id -> true
var roster: Array = []           ## owned monster instances (see progression.gd)
var squad: Array = []            ## uids of the 4 monsters taken into battle
var next_uid := 1
var story_seen: Dictionary = {}  ## story seen-flags (story.gd keys)
var stars: Dictionary = {}       ## stage_id -> best stars (1-3)
var rewards: Array = []          ## tower_reward strings granted on first L10 clears
var load_note := ""              ## "new", "loaded", "migrated_from_v1", "corrupt_reset"


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path
	load_save()


func new_game() -> void:
	unlocked = 1
	cleared = {}
	story_seen = {}
	stars = {}
	rewards = []
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
		set_squad(filled_squad(mapped if mapped.size() == ids.size() else []))
		_migrate_to_v3()
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
				if inst.has("bond"):
					inst.bond = int(inst.bond)
				else:
					inst.bond = migrated_bond(inst)
			roster.append(inst)
	next_uid = maxi(int(d.get("next_uid", 1)), roster.size() + 1)
	set_squad(filled_squad(d.get("squad", [])))  # v3 squads of 4 keep their 4, topped up to 6
	if v < 3:
		_migrate_to_v3()
		load_note = "migrated_from_v2"
		return
	story_seen = d.get("story_seen", {}) if typeof(d.get("story_seen")) == TYPE_DICTIONARY else {}
	stars = {}
	var st: Variant = d.get("stars", {})
	if typeof(st) == TYPE_DICTIONARY:
		for k in st:
			stars[k] = int(st[k])
	rewards = d.get("rewards", []) if typeof(d.get("rewards")) == TYPE_ARRAY else []
	load_note = "loaded" if v >= VERSION else "migrated_from_v%d" % v


## v4 migration: Bond of a fused instance saved before Bond existed.
static func migrated_bond(inst: Dictionary) -> int:
	var parts: Array = []
	for pid in inst.get("parents", []):
		var m := Data.monster(str(pid))
		parts.append({"rarity": str(m.get("rarity", inst.get("rarity", "Common")))} if not m.is_empty() else {"rarity": str(inst.get("rarity", "Common"))})
	while parts.size() < 2:
		parts.append({"rarity": str(inst.get("rarity", "Common"))})
	return Summon.fusion_bond(parts[0], parts[1])


func _migrate_to_v3() -> void:
	story_seen = {}
	stars = {}
	rewards = []
	for sid in cleared:
		stars[sid] = 1
	if unlocked > 1 or not cleared.is_empty():
		story_seen["prologue"] = true
	for t in Data.towers():
		var tid := str(t.tower_id)
		if tower_unlocked(tid) and (unlocked > 1 or not cleared.is_empty()):
			story_seen["arrival_" + tid] = true
		var l10 := str(t.levels[-1].stage_id)
		if cleared.has(l10):
			story_seen["pre_boss_" + tid] = true
			story_seen["post_boss_" + tid] = true
			rewards.append(str(t.tower_reward))


func to_dict() -> Dictionary:
	return {"version": VERSION, "unlocked": unlocked, "cleared": cleared, "roster": roster, "squad": squad,
		"next_uid": next_uid, "story_seen": story_seen, "stars": stars, "rewards": rewards}


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


## The valid, owned, distinct uids of `uids` (in order, at most squad_size), topped up with the
## strongest other owned monsters. Used when loading older saves (squad of 4 -> 6) and after a fusion.
func filled_squad(uids: Array) -> Array:
	var out := []
	for u in uids:
		if out.size() < Data.squad_size() and not get_inst(str(u)).is_empty() and not out.has(str(u)):
			out.append(str(u))
	for u in auto_squad_order():
		if out.size() >= Data.squad_size():
			break
		if not out.has(u):
			out.append(u)
	return out


func auto_squad_order() -> Array:
	var sorted := roster.duplicate()
	sorted.sort_custom(func(a, b): return Prog.power(a) > Prog.power(b))
	return sorted.map(func(i): return str(i.uid))


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
	var drafted: Array = state.get("team") if state.get("team") != null and not state.team.is_empty() else squad
	for uid in drafted:
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
	set_squad(filled_squad(sq))
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


# ---------------------------------------------------------------- story, stars, towers

func is_seen(key: String) -> bool:
	return story_seen.has(key)


func mark_seen(key: String) -> void:
	if not story_seen.has(key):
		story_seen[key] = true
		save()


## Stars for a finished battle the player won: 1 + Sigil above stars.sigil_hp_pct + no monster lost.
static func battle_stars(state) -> int:
	var S: Dictionary = Data.progression().stars
	var n := 1
	if state.symbol_hp[0] * 100 >= int(S.sigil_hp_pct) * state.symbol_max:
		n += 1
	if int(state.kos[0]) == 0:
		n += 1
	return n


func record_stars(stage_id: String, n: int) -> void:
	stars[stage_id] = maxi(int(stars.get(stage_id, 0)), n)
	save()


func tower_unlocked(tower_id: String) -> bool:
	for t in Data.towers():
		if str(t.tower_id) == tower_id:
			return is_unlocked(str(t.levels[0].stage_id))
	return false


## {cleared: 0-10, stars: 0-30, max_stars: 30}
func tower_progress(tower_id: String) -> Dictionary:
	var out := {"cleared": 0, "stars": 0, "max_stars": 0}
	for t in Data.towers():
		if str(t.tower_id) != tower_id:
			continue
		for l in t.levels:
			out.max_stars += 3
			if cleared.has(str(l.stage_id)):
				out.cleared += 1
			out.stars += int(stars.get(str(l.stage_id), 0))
	return out


## Grants the tower's reward on the first L10 clear. Returns the reward ("" if not new).
func grant_reward(stage_id: String) -> String:
	var st := Data.stage(stage_id)
	if st.is_empty() or str(st.stage_id).right(3) != "L10":
		return ""
	for t in Data.towers():
		if str(t.tower_id) == str(st.tower_id):
			var r := str(t.tower_reward)
			if rewards.has(r):
				return ""
			rewards.append(r)
			save()
			return r
	return ""


func reset() -> void:
	new_game()
	save()
