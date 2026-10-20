## Loads the Aether Sigil bible (res://data/AETHER_SIGIL_MASTER_GAME_BIBLE.json) and the
## rules tables (res://data/game_rules.json) once, and serves typed lookups.
## Both files live inside the project so they ship in an exported mobile build
## (export presets must include "data/*.json" as non-resource files). The bible is never modified.
extends RefCounted

const BIBLE_PATH := "res://data/AETHER_SIGIL_MASTER_GAME_BIBLE.json"
const RULES_PATH := "res://data/game_rules.json"
const SIZE := 12

static var _bible: Dictionary = {}
static var _rules: Dictionary = {}
static var _stages: Array = []          ## level dicts in play order, each with tower_id/tower_name/index added
static var _stage_by_id: Dictionary = {}
static var _monsters: Dictionary = {}   ## id -> monster dict (numbers converted to int)


static func _parse(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("data_loader: cannot read %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("data_loader: %s is not a JSON object" % path)
		return {}
	return parsed


static func ensure_loaded() -> bool:
	if not _bible.is_empty():
		return true
	_bible = _parse(BIBLE_PATH)
	_rules = _parse(RULES_PATH)
	if _bible.is_empty() or _rules.is_empty():
		return false
	var i := 0
	for t in _bible.get("towers", []):
		for l in t.get("levels", []):
			var lv: Dictionary = l
			lv["tower_id"] = str(t.get("tower_id", ""))
			lv["tower_name"] = str(t.get("name", ""))
			lv["index"] = i
			_stages.append(lv)
			_stage_by_id[str(lv.get("stage_id", ""))] = lv
			i += 1
	for m in _bible.get("monsters", []):
		var md: Dictionary = m
		for k in ["hp", "attack", "defense", "move", "range", "level_cap"]:
			if md.has(k):
				md[k] = int(md[k])  # JSON numbers parse as float
		_monsters[str(md.get("id", ""))] = md
	return true


static func bible() -> Dictionary:
	ensure_loaded()
	return _bible


static func rules() -> Dictionary:
	ensure_loaded()
	return _rules


static func towers() -> Array:
	ensure_loaded()
	return _bible.get("towers", [])


static func stages() -> Array:
	ensure_loaded()
	return _stages


static func stage(id: String) -> Dictionary:
	ensure_loaded()
	return _stage_by_id.get(id, {})


static func stage_count() -> int:
	return stages().size()


static func monster(id: String) -> Dictionary:
	ensure_loaded()
	return _monsters.get(id, {})


static func has_monster(id: String) -> bool:
	ensure_loaded()
	return _monsters.has(id)


static func monster_ids() -> Array:
	ensure_loaded()
	return _monsters.keys()


static func tile_def(type: String) -> Dictionary:
	return rules().get("tiles", {}).get(type, {})


static func tile_handled(type: String) -> bool:
	return rules().get("tiles", {}).has(type)


static func starter_team() -> Array:
	return rules().get("starter_team", {}).get("ids", []).duplicate()


static func special_rule(text: String) -> Dictionary:
	return rules().get("special_rules", {}).get(text, {})


static func special_rule_known(text: String) -> bool:
	return rules().get("special_rules", {}).has(text)


## [x, y] from JSON (floats) -> Vector2i(x, y). Bible tiles index map_grid[y][x].
static func vec(a: Variant) -> Vector2i:
	if a is Array and a.size() >= 2:
		return Vector2i(int(a[0]), int(a[1]))
	return Vector2i(-1, -1)
