## Monster progression: levels/XP, evolution and fusion. Pure static logic over "instance"
## dictionaries (the player's owned monsters); all numbers come from data/progression.json.
##
## Instance (as saved):
##   {uid, base_id, form_id, name, level, xp, evo_stage, fused: false}
##   fused ones add: parents, element, element_family, role, rarity, level_cap, ability,
##   secondary_ability, secondary_family, base {hp, attack, defense, move, range}
## base_id = the line's founder (its element/role/ability/base stats); form_id = the current
## form (its name), which moves along evolution_family when the monster evolves.
extends RefCounted

const Data = preload("res://scripts/data_loader.gd")

const OK := "ok"
const STATS := ["hp", "attack", "defense", "move", "range"]


static func P() -> Dictionary:
	return Data.progression()


static func new_instance(uid: String, mon_id: String) -> Dictionary:
	var m := Data.monster(mon_id)
	return {"uid": uid, "base_id": mon_id, "form_id": mon_id, "name": str(m.get("name", mon_id)),
		"level": int(P().start_level), "xp": 0, "evo_stage": 0, "fused": false}


static func is_fused(inst: Dictionary) -> bool:
	return bool(inst.get("fused", false))


static func template(inst: Dictionary) -> Dictionary:
	return Data.monster(str(inst.get("base_id", "")))


static func field(inst: Dictionary, key: String) -> String:
	if is_fused(inst):
		return str(inst.get(key, ""))
	return str(template(inst).get(key, ""))


static func level_cap(inst: Dictionary) -> int:
	if is_fused(inst):
		return int(inst.get("level_cap", 50))
	return maxi(int(template(inst).get("level_cap", 50)), int(Data.monster(str(inst.form_id)).get("level_cap", 0)))


# ---------------------------------------------------------------- XP and levels

static func xp_to_next(level: int) -> int:
	var X: Dictionary = P().xp
	return int(X.to_next_base) + int(X.to_next_per_level) * level


## Adds XP; levels up while enough XP and below the cap. Returns levels gained.
static func add_xp(inst: Dictionary, amount: int) -> int:
	var gained := 0
	var cap := level_cap(inst)
	if int(inst.level) >= cap:
		inst.xp = 0
		return 0
	inst.xp = int(inst.xp) + maxi(0, amount)
	while int(inst.level) < cap and int(inst.xp) >= xp_to_next(int(inst.level)):
		inst.xp = int(inst.xp) - xp_to_next(int(inst.level))
		inst.level = int(inst.level) + 1
		gained += 1
	if int(inst.level) >= cap:
		inst.xp = 0
	return gained


## XP one summoned monster earns from a battle.
static func battle_xp(kos: int, won: bool, tower: int) -> int:
	var X: Dictionary = P().xp
	var x := (float(X.participation) + float(X.per_ko) * kos) * (float(X.win_mult) if won else float(X.loss_mult))
	x *= 1.0 + float(X.tower_bonus_pct) / 100.0 * (tower - 1)
	return roundi(x)


# ---------------------------------------------------------------- stats

## Level-1 stats including evolution multipliers (fused: the stored blend).
static func base_stats(inst: Dictionary) -> Dictionary:
	var out := {}
	if is_fused(inst):
		for k in STATS:
			out[k] = int(inst.base[k])
		return out
	var t := template(inst)
	var mult := pow(float(P().evolution.stat_mult), int(inst.get("evo_stage", 0)))
	for k in STATS:
		out[k] = int(t.get(k, 0)) if k in ["move", "range"] else roundi(float(t.get(k, 0)) * mult)
	return out


static func stats(inst: Dictionary) -> Dictionary:
	var b := base_stats(inst)
	var G: Dictionary = P().growth_pct_per_level
	var lv := int(inst.level)
	for k in ["hp", "attack", "defense"]:
		b[k] = roundi(float(b[k]) * (1.0 + float(G[k]) / 100.0 * (lv - 1)))
	return b


static func power(inst: Dictionary) -> float:
	var s := stats(inst)
	return s.hp / 5.0 + s.attack * 1.5 + s.defense + s.move * 3 + s.range * 3


## Monster-shaped record GameState.place_unit understands (plus level, skill_tier, secondary_family).
static func battle_record(inst: Dictionary) -> Dictionary:
	var r := stats(inst)
	r["id"] = str(inst.uid)
	r["name"] = str(inst.name)
	for k in ["element", "element_family", "role", "rarity", "ability"]:
		r[k] = field(inst, k)
	r["level"] = int(inst.level)
	r["level_cap"] = level_cap(inst)
	r["skill_tier"] = int(inst.get("evo_stage", 0)) + (1 if is_fused(inst) else 0)
	r["secondary_family"] = str(inst.get("secondary_family", ""))
	r["secondary_ability"] = str(inst.get("secondary_ability", ""))
	return r


# ---------------------------------------------------------------- evolution

static func next_form(inst: Dictionary) -> String:
	if is_fused(inst):
		return ""
	var fam := str(Data.monster(str(inst.form_id)).get("evolution_family", ""))
	var members := Data.family_members(fam)
	var i := members.find(str(inst.form_id))
	return str(members[i + 1]) if i >= 0 and i + 1 < members.size() else ""


static func evolve_level(inst: Dictionary) -> int:
	var th: Array = P().evolution.thresholds
	var st := int(inst.get("evo_stage", 0))
	return int(th[st]) if st < th.size() else -1


static func can_evolve(inst: Dictionary) -> String:
	if is_fused(inst):
		return "fused_monsters_do_not_evolve"
	var need := evolve_level(inst)
	if need < 0:
		return "final_form"
	if next_form(inst) == "":
		return "last_in_family"
	if int(inst.level) < need:
		return "needs_level_%d" % need
	return OK


## Evolves in place. Returns the evolution dialogue line, or "" if it could not.
static func evolve(inst: Dictionary) -> String:
	if can_evolve(inst) != OK:
		return ""
	var old := str(inst.name)
	inst.form_id = next_form(inst)
	inst.name = str(Data.monster(str(inst.form_id)).name)
	inst.evo_stage = int(inst.evo_stage) + 1
	return str(P().evolution.dialogue).format({"old": old, "new": inst.name})


# ---------------------------------------------------------------- names

static func _lower_set(arr: Array) -> Dictionary:
	var d := {}
	for n in arr:
		d[str(n).to_lower()] = true
	return d


static var _bible_names := {}
static var _reserved_names := {}


## Why a name can't be used ("" if fine). taken = lowercase names already in use (roster etc.).
static func name_problem(name: String, taken: Dictionary = {}) -> String:
	if _bible_names.is_empty():
		for id in Data.monster_ids():
			_bible_names[str(Data.monster(id).name).to_lower()] = true
		var R := Data.reserved()
		for k in R:
			if k != "_doc" and k != "tokens":
				_reserved_names.merge(_lower_set(R[k]))
	var n := name.to_lower()
	if n.length() < 4:
		return "too_short"
	if _bible_names.has(n):
		return "collides_with_bible_monster"
	if _reserved_names.has(n):
		return "reserved_franchise_name"
	for t in Data.reserved().get("tokens", []):
		if n.contains(str(t)):
			return "contains_reserved_token_%s" % t
	if taken.has(n):
		return "already_used"
	return ""


## Deterministic generated name; see progression.json fusion.name_doc.
static func fusion_name(primary: String, secondary: String, taken: Dictionary = {}) -> String:
	var F: Dictionary = P().fusion
	var h := int(F.head_len)
	var mid := secondary.length() / 2
	var cands := []
	for extra in 4:
		cands.append(primary.substr(0, h + extra) + secondary.substr(mid).to_lower())
	for shift in range(1, 4):
		cands.append(primary.substr(0, h) + secondary.substr(mid + shift).to_lower())
	var base: String = cands[0]
	for suf in F.fallback_suffixes:
		cands.append(base + str(suf))
	for c in cands:
		var name := str(c).capitalize().replace(" ", "")
		if name_problem(name, taken) == "":
			return name
	return ""


# ---------------------------------------------------------------- fusion

static func rarity_index(r: String) -> int:
	return Array(P().fusion.rarity_order).find(r)


## [primary, secondary]: higher level, then higher rarity, then lower uid.
static func order_parents(a: Dictionary, b: Dictionary) -> Array:
	var ka := [int(a.level), rarity_index(field(a, "rarity")), -str(a.uid).get_slice("-", 1).to_int()]
	var kb := [int(b.level), rarity_index(field(b, "rarity")), -str(b.uid).get_slice("-", 1).to_int()]
	for i in 3:
		if ka[i] != kb[i]:
			return [a, b] if ka[i] > kb[i] else [b, a]
	return [a, b] if str(a.uid) < str(b.uid) else [b, a]


static func recipe_for(a: Dictionary, b: Dictionary) -> Dictionary:
	var pair := [str(a.get("base_id", "")), str(b.get("base_id", ""))]
	for r in P().fusion.recipes:
		var ps: Array = r.parents
		if (ps[0] == pair[0] and ps[1] == pair[1]) or (ps[0] == pair[1] and ps[1] == pair[0]):
			return r
	return {}


static func can_fuse(a: Dictionary, b: Dictionary, roster_size: int) -> String:
	var F: Dictionary = P().fusion
	if a.is_empty() or b.is_empty():
		return "pick_two_monsters"
	if str(a.uid) == str(b.uid):
		return "same_monster_twice"
	if int(a.level) < int(F.min_level) or int(b.level) < int(F.min_level):
		return "both_need_level_%d" % int(F.min_level)
	if roster_size - 1 < int(F.min_roster_after):
		return "roster_would_drop_below_%d" % int(F.min_roster_after)
	return OK


## The fused monster these parents make (not yet added anywhere). Same parents -> same result.
static func fusion_preview(a: Dictionary, b: Dictionary, uid: String, taken: Dictionary = {}) -> Dictionary:
	var F: Dictionary = P().fusion
	var ord := order_parents(a, b)
	var p: Dictionary = ord[0]
	var s: Dictionary = ord[1]
	var recipe := recipe_for(p, s)
	var bonus := float(recipe.get("bonus_pct", F.bonus_pct))
	var w := float(F.weight_primary)
	var bp := base_stats(p)
	var bs := base_stats(s)
	var base := {}
	for k in STATS:
		var v: float = w * bp[k] + (1.0 - w) * bs[k]
		base[k] = roundi(v * (1.0 + bonus / 100.0)) if k in ["hp", "attack", "defense"] else roundi(v)
	var ri := mini(maxi(rarity_index(field(p, "rarity")), rarity_index(field(s, "rarity"))) + int(F.rarity_step), Array(F.rarity_order).size() - 1)
	var name := str(recipe.get("name", ""))
	if name == "":
		name = fusion_name(str(p.name), str(s.name), taken)
	return {"uid": uid, "base_id": "FUSION", "form_id": "FUSION", "name": name,
		"level": int(p.level), "xp": 0, "evo_stage": 0, "fused": true,
		"parents": [str(p.get("base_id", "")), str(s.get("base_id", ""))],
		"parent_names": [str(p.name), str(s.name)],
		"element": str(recipe.get("element", field(p, "element"))),
		"element_family": str(recipe.get("element_family", field(p, "element_family"))),
		"role": field(p, "role"), "rarity": str(F.rarity_order[ri]),
		"level_cap": maxi(level_cap(p), level_cap(s)),
		"ability": field(p, "ability"), "secondary_ability": field(s, "ability"),
		"secondary_family": field(s, "element_family"), "base": base}
