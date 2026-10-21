## Tiny sound shim for presentation code: Sfx.play("statue_hop") forwards to the AudioManager autoload
## (game/audio/HOOKS.md ids) when it exists and silently does nothing otherwise (headless tests, or
## builds without the audio pack). Presentation never depends on sound being present.
extends RefCounted

## Last ids requested (newest last, capped) — lets tests check which hooks fired.
static var history: Array = []


static func _manager() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("AudioManager")
	return null


## Plays a sound effect id from HOOKS.md. pos: optional world position; jitter: pitch variation.
static func play(id: String, pos: Variant = null, jitter := 0.04) -> void:
	history.append(id)
	if history.size() > 64:
		history.pop_front()
	var am := _manager()
	if am != null and am.has_method("play_sfx"):
		am.play_sfx(id, pos, jitter)


## Picks the awaken roar that suits a creature body plan (HOOKS.md roar variants).
static func roar_for(plan: String) -> String:
	match plan:
		"drake", "golem": return "monster_roar_beast"
		"bird": return "monster_roar_screech"
		"beast": return "monster_roar_growl"
		"bug", "floater", "hopper": return "monster_roar_chitter"
	return "monster_awaken_roar_generic"
