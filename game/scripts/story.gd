## Story mode: validation and lookup for data/story.json, and the dialogue-trigger table
## (data/dialogue_triggers.json). Pure static logic; the UI plays the sequences.
## story.json schema (version 1):
##   {version, protagonist {name, title}, prologue [line], towers [{tower_id, arrival [line],
##    pre_boss [line], post_boss [line]}], finale [line], epilogue [line]}; line = {speaker, line}
## Seen-flag keys: "prologue", "arrival_TT", "pre_boss_TT", "post_boss_TT", "finale", "epilogue".
extends RefCounted

const Data = preload("res://scripts/data_loader.gd")


static func _check_lines(v: Variant, where: String, errs: Array, allow_empty: bool = false) -> void:
	if typeof(v) != TYPE_ARRAY:
		errs.append("%s: not a list" % where)
		return
	if v.is_empty() and not allow_empty:
		errs.append("%s: empty" % where)
	for i in v.size():
		var l: Variant = v[i]
		if typeof(l) != TYPE_DICTIONARY:
			errs.append("%s[%d]: not an object" % [where, i])
			continue
		for k in ["speaker", "line"]:
			if typeof(l.get(k)) != TYPE_STRING or str(l.get(k)).strip_edges() == "":
				errs.append("%s[%d].%s: missing or empty" % [where, i, k])


## Every schema problem in a story dictionary ([] = valid).
static func validate(d: Variant) -> Array:
	var errs := []
	if typeof(d) != TYPE_DICTIONARY:
		return ["story: not a JSON object"]
	if int(d.get("version", 0)) != 1:
		errs.append("version: expected 1, got %s" % str(d.get("version")))
	var p: Variant = d.get("protagonist")
	if typeof(p) != TYPE_DICTIONARY or str(p.get("name", "")) == "" or typeof(p.get("title")) != TYPE_STRING:
		errs.append("protagonist: needs name and title")
	for part in ["prologue", "finale", "epilogue"]:
		_check_lines(d.get(part), part, errs)
	var towers: Variant = d.get("towers")
	if typeof(towers) != TYPE_ARRAY:
		errs.append("towers: not a list")
		return errs
	var ids := {}
	for t in towers:
		if typeof(t) != TYPE_DICTIONARY:
			errs.append("towers: entry is not an object")
			continue
		var tid := str(t.get("tower_id", ""))
		if ids.has(tid):
			errs.append("towers: duplicate tower_id %s" % tid)
		ids[tid] = true
		for part in ["arrival", "pre_boss", "post_boss"]:
			_check_lines(t.get(part), "towers[%s].%s" % [tid, part], errs)
	for tw in Data.towers():
		if not ids.has(str(tw.tower_id)):
			errs.append("towers: missing tower_id %s" % tw.tower_id)
	return errs


static func hero() -> String:
	return str(Data.story().get("protagonist", {}).get("name", "Hero"))


## Lines for a seen-flag key ("prologue", "arrival_03", "post_boss_12", ...).
static func lines(key: String) -> Array:
	var s := Data.story()
	if s.has(key):
		return s[key]
	var cut := key.rfind("_")
	if cut < 0:
		return []
	var part := key.substr(0, cut)
	var tid := key.substr(cut + 1)
	for t in s.get("towers", []):
		if str(t.get("tower_id", "")) == tid:
			return t.get(part, [])
	return []


## A bible global sample line (1-based) with 'Hero'/'Rival' resolved: {speaker, line}.
static func global_line(n: int, rival: String) -> Dictionary:
	var samples: Array = Data.bible().get("dialogue_system", {}).get("sample_lines", [])
	if n < 1 or n > samples.size():
		return {}
	var raw := str(samples[n - 1])
	var cut := raw.find(": ")
	var who := raw.substr(0, cut) if cut > 0 else ""
	var text := raw.substr(cut + 2) if cut > 0 else raw
	var speaker := hero() if who == "Hero" else (rival if who == "Rival" else who)
	return {"speaker": speaker, "line": text}


## "Speaker: text" from a stage dialogue entry -> {speaker, line}.
static func split_line(raw: String, fallback_speaker: String) -> Dictionary:
	var cut := raw.find(": ")
	if cut > 0:
		return {"speaker": raw.substr(0, cut), "line": raw.substr(cut + 2)}
	return {"speaker": fallback_speaker, "line": raw}


static func template(type: String) -> String:
	return str(Data.triggers().get("types", {}).get(type, {}).get("template", ""))
