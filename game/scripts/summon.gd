## Vessels, Summon Points (SP) and the pre-match Bond draft. Pure static helpers; every number
## comes from data/game_rules.json (terms, summon_points, bond, vessel, ko_sigil_damage).
## Design: docs/SUMMON-POINTS.md. A "record" is a monster dict as GameState sees it: a bible
## monster, or a player battle record (progression.battle_record: evo_stage, fused, bond).
extends RefCounted

const Data = preload("res://scripts/data_loader.gd")

const OK := "ok"
const R_TOO_MANY := "too_many_vessels"
const R_OVER_CAP := "over_bond_cap"
const R_EMPTY := "no_vessels"
const R_DUPLICATE := "duplicate_vessel"


## Player-facing term (localisation key in game_rules.json terms), e.g. term("vessel") -> "Vessel".
static func term(key: String) -> String:
	return str(Data.rules().get("terms", {}).get(key, key.capitalize()))


static func SP() -> Dictionary:
	return Data.rules().summon_points


static func record_for(mon_id: String, custom: Dictionary = {}) -> Dictionary:
	return custom[mon_id] if custom.has(mon_id) else Data.monster(mon_id)


static func rarity_of(record: Dictionary) -> String:
	return str(record.get("rarity", "Common"))


## Rarity index 0 (Common) .. 5 (Legendary); drives Vessel HP and KO backlash.
static func tier(record: Dictionary) -> int:
	return maxi(0, Array(Data.progression().fusion.rarity_order).find(rarity_of(record)))


static func evolved(record: Dictionary) -> bool:
	return int(record.get("evo_stage", 0)) > 0 or bool(record.get("fused", false))


## SP to crack (no stage surcharge): rarity + evolved_extra if evolved or fused.
static func crack_cost(record: Dictionary) -> int:
	var table: Dictionary = SP().crack_cost_by_rarity
	var c := int(table.get(rarity_of(record), table.Common))
	return c + (int(SP().evolved_extra) if evolved(record) else 0)


## Bond (draft cost). Fused monsters carry a stored "bond"; others: rarity + per_evolution x stage.
static func bond(record: Dictionary) -> int:
	if record.has("bond"):
		return int(record.bond)
	var B: Dictionary = Data.rules().bond
	return int(B.cost_by_rarity.get(rarity_of(record), B.cost_by_rarity.Common)) + int(B.per_evolution) * int(record.get("evo_stage", 0))


## Bond of a fusion of two parents (instances or records).
static func fusion_bond(a: Dictionary, b: Dictionary) -> int:
	return roundi(float(bond(a) + bond(b)) * float(Data.rules().bond.fusion_pct) / 100.0)


static func vessel_hp(record: Dictionary) -> int:
	var V: Dictionary = Data.rules().vessel
	return int(V.hp_base) + int(V.hp_per_tier) * tier(record)


static func ko_sigil_damage(record: Dictionary) -> int:
	var K: Dictionary = Data.rules().ko_sigil_damage
	return int(K.base) + int(K.per_tier) * tier(record)


## Bond cap for a stage's tower: bond.cap_by_tower[tower - 1] (last entry beyond the table).
static func draft_cap(stage: Dictionary) -> int:
	var caps: Array = Data.rules().bond.cap_by_tower
	var tower := maxi(1, int(str(stage.get("tower_id", "1"))))
	return int(caps[mini(tower, caps.size()) - 1])


static func total_bond(ids: Array, custom: Dictionary = {}) -> int:
	var t := 0
	for id in ids:
		t += bond(record_for(str(id), custom))
	return t


## OK, or why this pick is not a legal draft for `stage`.
static func draft_check(ids: Array, stage: Dictionary, custom: Dictionary = {}) -> String:
	if ids.is_empty():
		return R_EMPTY
	if ids.size() > Data.squad_size():
		return R_TOO_MANY
	var seen := {}
	for id in ids:
		if seen.has(id):
			return R_DUPLICATE
		seen[id] = true
	if total_bond(ids, custom) > draft_cap(stage):
		return R_OVER_CAP
	return OK


## The strongest legal draft from `ids` (result keeps their order): greedy by `power` (higher
## first; default = the given order), skipping any pick that would exceed the Bond cap.
static func auto_draft(ids: Array, stage: Dictionary, custom: Dictionary = {}, power: Callable = Callable()) -> Array:
	var ranked := ids.duplicate()
	if power.is_valid():
		ranked.sort_custom(func(a, b): return power.call(a) > power.call(b))
	var cap := draft_cap(stage)
	var picked := {}
	var spent := 0
	for id in ranked:
		if picked.size() >= Data.squad_size():
			break
		var c := bond(record_for(str(id), custom))
		if spent + c <= cap:
			picked[id] = true
			spent += c
	return ids.filter(func(id): return picked.has(id))
