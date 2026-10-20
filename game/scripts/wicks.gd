## Designer-tunable data: elements and every Wick definition live here and only here.
extends RefCounted

## Each element beats the NEXT one in this list (wrapping): Ember>Bloom>Tide>Stone>Gale>Ember.
const ELEMENT_CYCLE: Array[String] = ["Ember", "Bloom", "Tide", "Stone", "Gale"]

const DEFAULT_MOVE := 2
const DEFAULT_RANGE := 1

## id -> definition. power/guard/hp = stats; cost = Oil; ability is a free-form tag the rules check.
const DEFS := {
	"pip":        {"name": "Pip",        "element": "Ember", "cost": 1, "power": 3, "guard": 1, "hp": 6,  "move": 2, "range": 1, "ability": "kindle"},
	"brazier":    {"name": "Brazier",    "element": "Ember", "cost": 3, "power": 4, "guard": 4, "hp": 12, "move": 2, "range": 1, "ability": ""},
	"cinderwing": {"name": "Cinderwing", "element": "Ember", "cost": 4, "power": 6, "guard": 2, "hp": 9,  "move": 2, "range": 2, "ability": ""},
	"dropkin":    {"name": "Dropkin",    "element": "Tide",  "cost": 1, "power": 1, "guard": 1, "hp": 6,  "move": 2, "range": 1, "ability": ""},
	"riptide":    {"name": "Riptide",    "element": "Tide",  "cost": 3, "power": 5, "guard": 2, "hp": 9,  "move": 2, "range": 1, "ability": ""},
	"harborcrab": {"name": "Harborcrab", "element": "Tide",  "cost": 2, "power": 3, "guard": 4, "hp": 11, "move": 2, "range": 1, "ability": ""},
}

## Starting satchel for each player (order = button order in the UI).
const STARTING_SATCHEL: Array[String] = ["pip", "brazier", "cinderwing", "dropkin", "riptide", "harborcrab"]


static func get_def(id: String) -> Dictionary:
	return DEFS[id]


static func beats(attacker_element: String, defender_element: String) -> bool:
	var i := ELEMENT_CYCLE.find(attacker_element)
	if i < 0 or defender_element == "":
		return false
	return ELEMENT_CYCLE[(i + 1) % ELEMENT_CYCLE.size()] == defender_element
