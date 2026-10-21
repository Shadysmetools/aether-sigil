## Asset resolver: the ONE place that maps a game id to a texture. Painted art drops in with no
## code change. Every lookup tries, in order (first hit wins):
##   1. res://art/ai/<category>/<id>.png                 restored/upscaled painted art (game/art/ai/)
##   2. <repo>/art/ai/<category>/<id>.png                the same, read straight from the art agent's
##      repo-root folder (dev runs only; copy into game/art/ai to ship)
##   3. res://art/ai/from-concepts/... then <repo>/art/ai/from-concepts/...  crops of the concept sheets
##   4. res://art/generated/png/<...>.png                vector placeholders (copied from art/generated/png)
##   5. bundled title art (res://art/title/: logo, key-art poster) for the logo / world backdrop slots
##   6. null                                             the caller draws its procedural fallback
## Un-imported PNGs (dropped in but `--import` not run yet, the repo folder, user:// in tests) load raw.
## Results, including misses, are cached; call clear_cache() after changing the roots.
## The full slot list (what the art agent must paint) is contract_slots(); docs: art/ASSET-CONTRACT.md.
extends RefCounted

const Data = preload("res://scripts/data_loader.gd")

const AI_ROOT := "res://art/ai"
const GEN_ROOT := "res://art/generated/png"
const CONCEPTS := "from-concepts"
const TITLE_LOGO := "res://art/title/logo.png"
const TITLE_KEY_ART := "res://art/title/key_art.jpg"

## Tile types that exist on maps or legends. ground_v2/_v3 and bridge_y are extra drawing variants.
const TILE_TYPES := ["ground", "ground_v2", "ground_v3", "stone", "obstacle", "bridge", "bridge_y", "capsule_node",
	"player_symbol", "enemy_symbol", "player_spawn", "enemy_spawn", "relic", "warp_gate", "elevation", "hazard",
	"forest", "lava", "water", "ice", "metal", "sky", "shadow", "ruins", "space", "crystal", "rift", "mixed"]
const PROPS := ["player_sigil", "enemy_sigil", "capsule_node", "relic", "portal"]
const ELEMENT_FAMILIES := ["Fire", "Water", "Wind", "Earth", "Wood", "Ice", "Thunder", "Light", "Dark", "Tech", "Space", "Arcane"]
## Generated stand-in creature per monster role (tokens/silhouettes/*.png).
const ROLE_SILHOUETTE := {"Guardian": "colossus", "Striker": "drake", "Assassin": "drake", "Scout": "stag",
	"Support": "hopper", "Controller": "beetle", "Artillery": "beetle", "Summoner": "phoenix"}
const UI_SLOTS := ["panel/panel_border", "panel/panel_header", "turn_order/slot_ally", "turn_order/slot_ally_active",
	"turn_order/slot_enemy", "turn_order/slot_enemy_active", "objective/checkbox_unchecked", "objective/checkbox_checked",
	"objective/checkbox_failed", "buttons/btn_move_normal", "buttons/btn_move_pressed", "buttons/btn_move_disabled",
	"buttons/btn_attack_normal", "buttons/btn_attack_pressed", "buttons/btn_attack_disabled", "buttons/btn_skill_normal",
	"buttons/btn_skill_pressed", "buttons/btn_skill_disabled", "buttons/btn_defend_normal", "buttons/btn_defend_pressed",
	"buttons/btn_defend_disabled", "buttons/btn_wait_normal", "buttons/btn_wait_pressed", "buttons/btn_wait_disabled",
	"logo"]

static var ai_root := AI_ROOT     ## tests point these at user:// folders
static var gen_root := GEN_ROOT
static var dev_root := ProjectSettings.globalize_path("res://").path_join("../art/ai").simplify_path()  ## "" = off
static var _cache: Dictionary = {}    ## path -> Texture2D or null (misses are cached too)
static var _tower_folder: Dictionary = {}
## Owned-monster uid -> bible form id (MON-xxxx), registered by the UI so squad units find their art.
static var aliases: Dictionary = {}
static var _concepts: Dictionary = {}       ## "category/key" -> [priority, path] (from-concepts index)
static var _concept_tex: Dictionary = {}    ## Texture2D -> true for rectangular concept crops


static func clear_cache() -> void:
	_cache = {}
	_concepts = {}
	_concept_tex = {}
	_element_rep = {}


static func reset_roots() -> void:
	ai_root = AI_ROOT
	gen_root = GEN_ROOT
	dev_root = ProjectSettings.globalize_path("res://").path_join("../art/ai").simplify_path()
	clear_cache()


## Painted-art roots in priority order.
static func ai_roots() -> Array:
	# Restored art beats crops wherever it lives: both restored roots first, then both crop roots.
	var dev := dev_root != "" and dev_root != ai_root
	var r := [ai_root]
	if dev:
		r.append(dev_root)
	r.append(ai_root.path_join(CONCEPTS))
	if dev:
		r.append(dev_root.path_join(CONCEPTS))
	return r


## Loads one file (imported resource, else the raw PNG), cached. null if it does not exist.
static func _load(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	_cache[path] = tex
	return tex


## First existing texture among the candidates (relative to the ai root, then the generated root).
static func _resolve(ai: Array, gen: Array, bundled: Array = []) -> Texture2D:
	for root in ai_roots():
		for rel in ai:
			var t := _load("%s/%s.png" % [root, rel])
			if t != null:
				return t
	for rel in gen:
		var t := _load("%s/%s.png" % [gen_root, rel])
		if t != null:
			return t
	for path in bundled:
		var t := _load(path)
		if t != null:
			return t
	return null


## Index of every from-concepts folder (the art agent's crops of the owner's concept sheets), keyed by
## a normalised name so the crops are usable whatever their file names: "towers/T01" (t01_..._art
## beats t01_..._card), "champions/lyra_quill" (c01_lyra_quill), "monsters/quillphoenix"
## (m07_quillphoenix beats evo_*/_lvNN beats *_card), "protagonist/summoner_closeup", "logo/logo".
static func _concept_index() -> Dictionary:
	if not _concepts.is_empty():
		return _concepts
	_concepts["_built"] = [99, ""]
	for root in ai_roots():
		if not root.ends_with(CONCEPTS):
			continue
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		for cat in dir.get_directories():
			var sub := DirAccess.open(root.path_join(cat))
			if sub == null:
				continue
			for f in sub.get_files():
				f = f.trim_suffix(".import").trim_suffix(".remap")
				if not f.ends_with(".png"):
					continue
				var name := f.get_basename()
				var pri := 0
				if name.ends_with("_card"):
					pri = 2
					name = name.trim_suffix("_card")
				elif name.ends_with("_art"):
					name = name.trim_suffix("_art")
				var rx := RegEx.create_from_string("_lv[0-9]+$")
				if rx.search(name) != null:
					pri = 1
					name = rx.sub(name, "")
				if name.begins_with("evo_"):
					pri = maxi(pri, 1)
					name = name.trim_prefix("evo_")
				var lead := RegEx.create_from_string("^([a-z])([0-9][0-9])_")
				var m := lead.search(name)
				var key := name
				if m != null:
					key = ("T" + m.get_string(2)) if cat == "towers" else name.substr(m.get_end())
				var k := "%s/%s" % [cat, key]
				if not _concepts.has(k) or int(_concepts[k][0]) > pri:
					_concepts[k] = [pri, root.path_join(cat).path_join(f)]
	return _concepts


## A concept crop by category and normalised key, or null.
static func concept(category: String, key: String) -> Texture2D:
	var e: Variant = _concept_index().get("%s/%s" % [category, key])
	if e == null or str(e[1]) == "":
		return null
	var t := _load(str(e[1]))
	if t != null:
		_concept_tex[t] = true
	return t


## True for a rectangular crop of a concept sheet (not a cut-out): draw it framed, never standing.
static func is_crop(tex: Texture2D) -> bool:
	return tex != null and _concept_tex.has(tex)


## Which tier a lookup came from: "ai", "generated" or "" (procedural). For tests and debugging.
static func tier(tex: Texture2D) -> String:
	if tex == null:
		return ""
	var p := tex.resource_path
	for k in _cache:
		if _cache[k] == tex:
			p = k
	for root in ai_roots():
		if p.begins_with(root.path_join(CONCEPTS)):
			return "concepts"
	for root in ai_roots():
		if p.begins_with(root):
			return "ai"
	if p.begins_with(gen_root):
		return "generated"
	return "bundled"


# ---------------------------------------------------------------- ids

## Bible tower id "01" -> contract key "T01".
static func tower_key(tid: String) -> String:
	return tid if tid.begins_with("T") else "T" + tid


## Generated tile folder for a tower: "T01_verdant_spire".
static func tower_folder(tid: String) -> String:
	if _tower_folder.is_empty():
		for t in Data.towers():
			_tower_folder[str(t.tower_id)] = "T%s_%s" % [t.tower_id, str(t.name).to_lower().replace(" ", "_")]
	return str(_tower_folder.get(tid.trim_prefix("T"), ""))


## Speaker name -> portrait id: lowercase, every run of non-alphanumerics becomes one "_".
static func slug(s: String) -> String:
	var out := ""
	var gap := false
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			if gap and out != "":
				out += "_"
			out += ch
			gap = false
		else:
			gap = true
	return out


# ---------------------------------------------------------------- lookups

## Isometric tile (256x320, ground anchor at 128,248) for a tower and tile type.
static func tile(tid: String, type: String) -> Texture2D:
	var k := tower_key(tid)
	return _resolve(["tiles/%s/%s" % [k, type], "tiles/_any/%s" % type], ["tiles/%s/%s" % [tower_folder(tid), type]])


## Standing prop (256x384, foot anchor at 128,352). A tower may override: props/T01/relic.png.
static func prop(id: String, tid: String = "") -> Texture2D:
	var ai := ["props/%s" % id]
	if tid != "":
		ai.push_front("props/%s/%s" % [tower_key(tid), id])
	return _resolve(ai, ["props/%s" % id])


## Painted monster (512x512, foot anchor at 256,472): per monster id, then evolution family, then
## element family. null = no painted creature (use token_frame + silhouette).
static func monster(mon_id: String, element_family: String = "") -> Texture2D:
	mon_id = str(aliases.get(mon_id, mon_id))
	var ai := ["monsters/%s" % mon_id]
	var d := Data.monster(mon_id) if Data.has_monster(mon_id) else {}
	if str(d.get("evolution_family", "")) != "":
		ai.append("monsters/%s" % d.evolution_family)
	var fam := element_family if element_family != "" else str(d.get("element_family", ""))
	if fam != "":
		ai.append("monsters/%s" % fam.to_lower())
	var t := _resolve(ai, [])
	if t != null:
		return t
	# The owner's compendium crops: this monster by name, then any member of its evolution family,
	# then a representative of its element family.
	if not d.is_empty():
		t = concept("monsters", slug(str(d.name)))
		if t == null and str(d.get("evolution_family", "")) != "":
			for mid in Data.family_members(str(d.evolution_family)):
				t = concept("monsters", slug(str(Data.monster(mid).name)))
				if t != null:
					break
	if t == null and fam != "":
		t = _element_concept(fam)
	return t


static var _element_rep: Dictionary = {}

## First compendium crop whose bible monster has this element family (sorted by name, stable).
static func _element_concept(fam: String) -> Texture2D:
	if _element_rep.is_empty():
		_element_rep["_built"] = ""
		var keys := _concept_index().keys()
		keys.sort()
		var by_name := {}
		for m in Data.bible().get("monsters", []):
			by_name[slug(str(m.name))] = str(m.element_family)
		for k in keys:
			if str(k).begins_with("monsters/"):
				var f := str(by_name.get(str(k).trim_prefix("monsters/"), ""))
				if f != "" and not _element_rep.has(f):
					_element_rep[f] = str(k).trim_prefix("monsters/")
	if not _element_rep.has(fam):
		return null
	return concept("monsters", str(_element_rep[fam]))


## Generated creature stand-in for a role (Soft Silver, tint with modulate).
static func silhouette(role: String) -> Texture2D:
	return _resolve([], ["tokens/silhouettes/%s" % ROLE_SILHOUETTE.get(role, "stag")])


## Team + element token frame (256x256; creature slot r82 at 128,120).
static func token_frame(owner: int, element_family: String) -> Texture2D:
	var name := "%s_%s" % ["ally" if owner == 0 else "enemy", element_family.to_lower()]
	return _resolve(["tokens/frames/%s" % name], ["tokens/frames/%s" % name])


## Element family icon (256x256).
static func element_icon(element_family: String) -> Texture2D:
	var f := element_family.to_lower()
	return _resolve(["icons/elements/%s" % f], ["icons/elements/%s" % f])


## Dialogue portrait for a speaker NAME (e.g. "Kess Varrow" -> portraits/kess_varrow). null = procedural.
static func portrait(speaker: String) -> Texture2D:
	var t := _resolve(["portraits/%s" % slug(speaker)], [])
	if t == null:
		t = concept("champions", slug(speaker))
	if t == null and speaker == str(Data.story().get("protagonist", {}).get("name", "")):
		t = concept("protagonist", "summoner_closeup")
	return t


## Painted tower card scene (600x800) for the world map. null = procedural card.
static func tower_art(tid: String) -> Texture2D:
	var t := _resolve(["towers/%s" % tower_key(tid)], [])
	return t if t != null else concept("towers", tower_key(tid))


## Battle / map backdrop (1080x1920, opaque): per tower, then "world". null = the procedural sky shader.
static func backdrop(tid: String = "") -> Texture2D:
	if tid == "":
		return title_backdrop()
	return _resolve(["backdrops/%s" % tower_key(tid)], [])


## World map / title backdrop: painted backdrops/world, else the owner's key-art poster.
static func title_backdrop() -> Texture2D:
	var t := _resolve(["backdrops/world"], [])
	if t == null:
		t = concept("key-art", "key_art_poster")
	return t if t != null else _resolve([], [], [TITLE_KEY_ART])


## UI piece by contract name, e.g. "panel/panel_border", "turn_order/slot_ally_active".
static func ui(name: String) -> Texture2D:
	var ai := ["ui/%s" % name]
	if name == "logo":
		ai.append("logo/logo")
	return _resolve(ai, ["ui/%s" % name], [TITLE_LOGO] if name == "logo" else [])


# ---------------------------------------------------------------- the contract

## Every speaker who can appear in a dialogue box: narrator, protagonist, story cast, stage
## dialogue speakers and opponents, bible sample-line speakers. Sorted, de-duplicated names.
static func speakers() -> Array:
	var seen := {"Narrator": true}
	seen[str(Data.story().get("protagonist", {}).get("name", "Hero"))] = true
	var add_lines := func(arr: Array) -> void:
		for l in arr:
			if typeof(l) == TYPE_DICTIONARY and str(l.get("speaker", "")) != "":
				seen[str(l.speaker)] = true
	var s := Data.story()
	for part in ["prologue", "finale", "epilogue"]:
		add_lines.call(s.get(part, []))
	for t in s.get("towers", []):
		for part in ["arrival", "pre_boss", "post_boss"]:
			add_lines.call(t.get(part, []))
	for st in Data.stages():
		seen[str(st.opponent)] = true
		for v in st.dialogue.values():
			var cut := str(v).find(": ")
			if cut > 0:
				seen[str(v).substr(0, cut)] = true
	for t in Data.towers():
		seen[str(t.tower_boss)] = true
	var out := seen.keys()
	out.sort()
	return out


## Core cast first (narrator, protagonist, story speakers, tower bosses): the portraits to paint first.
static func core_speakers() -> Array:
	var seen := {"Narrator": true}
	seen[str(Data.story().get("protagonist", {}).get("name", "Hero"))] = true
	var s := Data.story()
	for part in ["prologue", "finale", "epilogue"]:
		for l in s.get(part, []):
			seen[str(l.speaker)] = true
	for t in s.get("towers", []):
		for part in ["arrival", "pre_boss", "post_boss"]:
			for l in t.get(part, []):
				seen[str(l.speaker)] = true
	for t in Data.towers():
		seen[str(t.tower_boss)] = true
	var out := seen.keys()
	out.sort()
	return out


## Evolution families in bible order.
static func evolution_families() -> Array:
	var seen := {}
	for m in Data.bible().get("monsters", []):
		seen[str(m.evolution_family)] = true
	return seen.keys()


## category -> Array of slot ids (paths under art/ai/ without .png). The art agent paints exactly these.
static func contract_slots() -> Dictionary:
	var tiles := []
	var towers := []
	var backdrops := ["backdrops/world"]
	for t in Data.towers():
		var k := tower_key(str(t.tower_id))
		towers.append("towers/%s" % k)
		backdrops.append("backdrops/%s" % k)
		for type in TILE_TYPES:
			tiles.append("tiles/%s/%s" % [k, type])
	var portraits := []
	for sp in speakers():
		portraits.append("portraits/%s" % slug(sp))
	var monsters := []
	for f in ELEMENT_FAMILIES:
		monsters.append("monsters/%s" % f.to_lower())
	for f in evolution_families():
		monsters.append("monsters/%s" % f)
	return {
		"tiles": tiles,
		"props": PROPS.map(func(p): return "props/" + p),
		"monsters": monsters,
		"portraits": portraits,
		"towers": towers,
		"backdrops": backdrops,
		"icons": ELEMENT_FAMILIES.map(func(f): return "icons/elements/" + f.to_lower()),
		"ui": UI_SLOTS.map(func(u): return "ui/" + u),
	}
