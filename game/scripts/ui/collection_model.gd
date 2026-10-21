## Compendium model: filter, search and sort over the 1,000 bible monsters, and the player's
## collected set. Pure static helpers (the collection screen and tests/test_ui_cards.gd use them).
extends RefCounted

const Data = preload("res://scripts/data_loader.gd")
const Prog = preload("res://scripts/progression.gd")
const Kit = preload("res://scripts/ui/menu_kit.gd")

const SORTS := ["number", "name", "rarity", "power", "element"]
const SORT_LABELS := {"number": "No.", "name": "Name", "rarity": "Rarity", "power": "Power", "element": "Element"}

static var _power: Dictionary = {}


## Bible ids the player has collected: every form each owned (non-fused) line has reached.
## There is no separate caught/seen set in the save, so this is derived from the roster.
static func collected(roster: Array) -> Dictionary:
	var out := {}
	for inst in roster:
		if Prog.is_fused(inst):
			continue
		var base := str(inst.get("base_id", ""))
		var members := Data.family_members(str(Data.monster(base).get("evolution_family", "")))
		var i := members.find(base)
		if i < 0:
			out[base] = true
			continue
		for j in range(i, mini(members.size(), i + int(inst.get("evo_stage", 0)) + 1)):
			out[str(members[j])] = true
		out[str(inst.get("form_id", base))] = true
	return out


## Level-1 power of a bible monster (the same formula the auto-squad uses).
static func power_of(id: String) -> float:
	if not _power.has(id):
		_power[id] = Prog.power(Prog.new_instance("C-0", id))
	return float(_power[id])


## filters: family, rarity, role ("" = any), search (name / element / ability, case-insensitive),
## owned_only (bool), sort (SORTS). Returns bible ids.
static func query(filters: Dictionary, owned: Dictionary = {}) -> Array:
	var fam := str(filters.get("family", ""))
	var rar := str(filters.get("rarity", ""))
	var role := str(filters.get("role", ""))
	var q := str(filters.get("search", "")).strip_edges().to_lower()
	var only := bool(filters.get("owned_only", false))
	var out := []
	for id in Data.monster_ids():
		var m := Data.monster(id)
		if fam != "" and str(m.element_family) != fam:
			continue
		if rar != "" and str(m.rarity) != rar:
			continue
		if role != "" and str(m.role) != role:
			continue
		if only and not owned.has(id):
			continue
		if q != "" and not (str(m.name).to_lower().contains(q) or str(m.element).to_lower().contains(q) or str(m.ability).to_lower().contains(q) or str(id).to_lower().contains(q)):
			continue
		out.append(id)
	return sort_ids(out, str(filters.get("sort", "number")))


static func sort_ids(ids: Array, by: String) -> Array:
	var out := ids.duplicate()
	match by:
		"name":
			out.sort_custom(func(a, b): return str(Data.monster(a).name).naturalnocasecmp_to(str(Data.monster(b).name)) < 0)
		"rarity":
			out.sort_custom(func(a, b):
				var ta := Kit.tier_of(str(Data.monster(a).rarity))
				var tb := Kit.tier_of(str(Data.monster(b).rarity))
				return ta > tb if ta != tb else str(a) < str(b))
		"power":
			out.sort_custom(func(a, b):
				var pa := power_of(a)
				var pb := power_of(b)
				return pa > pb if pa != pb else str(a) < str(b))
		"element":
			out.sort_custom(func(a, b):
				var fa := str(Data.monster(a).element_family)
				var fb := str(Data.monster(b).element_family)
				return fa < fb if fa != fb else str(a) < str(b))
		_:
			out.sort()
	return out


## Distinct values of a bible field, sorted (filter menus).
static func values_of(field: String) -> Array:
	var seen := {}
	for id in Data.monster_ids():
		seen[str(Data.monster(id).get(field, ""))] = true
	var out := seen.keys()
	out.sort()
	return out
