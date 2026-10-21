## The Narrator as a character: Vellum, the Archivist of the Aether Sigil (docs/NARRATOR.md).
## Data: data/narrator.json (name, mood->expression table, barks). The speaker id stays "Narrator"
## everywhere (portrait slot, voice casting, voice keys); only the name plate shows "Vellum".
## Pure logic, headless-safe. BarkDirector turns GameState changes into bark events.
extends RefCounted

const Data = preload("res://scripts/data_loader.gd")
const GameState = preload("res://scripts/game_state.gd")

const SPEAKER := "Narrator"
const EXPRESSIONS := ["neutral", "amused", "grave", "awed", "angry", "determined", "sad"]
## Events in priority order (first = most important when several fire in one refresh).
const EVENTS := ["low_sigil_hp", "vessel_broken", "ko", "big_hit", "first_crack", "battle_start"]
const BIG_HIT_UNIT := 0.40     ## one refresh drops a monster by this share of its max HP
const BIG_HIT_SIGIL := 0.25    ## ...or a Sigil by this share of the Symbol max


static func is_narrator(who: String) -> bool:
	return who == SPEAKER


static func display_name() -> String:
	return str(Data.narrator().get("name", "Narrator"))


static func title() -> String:
	return str(Data.narrator().get("title", ""))


## Name shown on the dialogue name plate for a speaker id.
static func plate_name(who: String) -> String:
	return display_name() if who == SPEAKER else who


## One of the 7 shared expressions for a mood tag (unknown tags -> neutral).
static func expression_for_mood(mood: String) -> String:
	var t: Dictionary = Data.narrator().get("mood_expression", {})
	var e := str(t.get(mood, mood))
	return e if EXPRESSIONS.has(e) else "neutral"


## The Narrator art has four faces; the other three fold into them.
static func art_expression(expr: String) -> String:
	match expr:
		"angry", "sad": return "grave"
		"determined": return "neutral"
	return expr if ["neutral", "amused", "grave", "awed"].has(expr) else "neutral"


## "early" (towers 1-4), "mid" (5-8) or "late" (9-12) for a tower id.
static func phase_for_tower(tower_id: String) -> String:
	var n := int(tower_id)
	for ph in Data.narrator().get("phases", []):
		if n >= int(ph.towers[0]) and n <= int(ph.towers[1]):
			return str(ph.id)
	return "early"


## The bark for an event: {id, event, mood, line} or {} when none. arrival/clear are per tower.
static func bark(event: String, tower_id: String = "01") -> Dictionary:
	var phase := phase_for_tower(tower_id)
	var tid := "%02d" % int(tower_id)
	for b in Data.narrator().get("barks", []):
		if str(b.event) != event:
			continue
		if event == "arrival" or event == "clear":
			if str(b.tower) == tid:
				return b
		elif str(b.phase) == phase:
			return b
	return {}


static func all_barks() -> Array:
	return Data.narrator().get("barks", [])


## Ids the story lines get in the voice pipeline (eleven_voices.py): prologue_01, arrival_03_01 ...
static func story_line_ids() -> Array:
	var out := []
	var s := Data.story()
	for part in ["prologue", "finale", "epilogue"]:
		for i in s.get(part, []).size():
			out.append({"id": "%s_%02d" % [part, i + 1], "line": s[part][i]})
	for t in s.get("towers", []):
		for part in ["arrival", "pre_boss", "post_boss"]:
			for i in t.get(part, []).size():
				out.append({"id": "%s_%s_%02d" % [part, t.tower_id, i + 1], "line": t[part][i]})
	return out


## Watches a battle and reports bark events. Each event fires once per battle (big_hit: at most once
## per `big_hit_gap` rounds). update() returns the events that fired this refresh in priority order.
class BarkDirector extends RefCounted:
	var fired: Dictionary = {}
	var hp: Dictionary = {}          ## unit id -> last seen hp; -1 / -2 -> Sigil hp
	var kos_seen := 0
	var started := false
	var last_big_round := -99
	var big_hit_gap := 3
	var breaks_seen: Dictionary = {}

	func update(state: GameState) -> Array:
		var out := []
		if state == null or state.stage.is_empty() or state.winner != GameState.NONE:
			return out
		var P := GameState.PLAYER
		var got := {}
		if not started:
			started = true
			got["battle_start"] = true
		# big hit: compare with the last snapshot
		var big := false
		for u in state.units:
			if hp.has(u.id) and u.max_hp > 0 and float(int(hp[u.id]) - u.hp) >= BIG_HIT_UNIT * u.max_hp:
				big = true
			hp[u.id] = u.hp
		for side in 2:
			var key := -1 - side
			if hp.has(key) and state.symbol_max > 0 and float(int(hp[key]) - state.symbol_hp[side]) >= BIG_HIT_SIGIL * state.symbol_max:
				big = true
			hp[key] = state.symbol_hp[side]
		if big and state.round_num - last_big_round >= big_hit_gap:
			last_big_round = state.round_num
			got["big_hit"] = true
		if not state.last_crack.is_empty() and not fired.has("first_crack"):
			var cu: GameState.Unit = state.get_unit(int(state.last_crack.unit))
			if cu != null and cu.owner == P:
				got["first_crack"] = true
		var ko_total := state.kos[0] + state.kos[1]
		if ko_total > kos_seen:
			kos_seen = ko_total
			got["ko"] = true
		if not state.last_break.is_empty() and not breaks_seen.has(state.last_break.hash()):
			breaks_seen[state.last_break.hash()] = true
			got["vessel_broken"] = true
		var low := int(Data.triggers().get("low_hp_pct", 50))
		if state.symbol_hp[P] * 100 < low * state.symbol_max:
			got["low_sigil_hp"] = true
		for ev in EVENTS:
			if got.has(ev) and (ev == "big_hit" or not fired.has(ev)):
				fired[ev] = true
				out.append(ev)
		return out
