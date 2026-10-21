## Asset resolver (scripts/assets.gd): tier order ai -> from-concepts -> generated -> bundled -> null,
## raw-PNG loading, the concept-crop index, and coverage: every bible tower, tile type on a map,
## element family, monster and dialogue speaker resolves to a texture or a working procedural draw.
extends SceneTree

const Assets = preload("res://scripts/assets.gd")
const Data = preload("res://scripts/data_loader.gd")
const UIArt = preload("res://scripts/ui_art.gd")
const Art = preload("res://scripts/board_art.gd")

const AI := "user://assets_test/ai"
const GEN := "user://assets_test/gen"

var passed := 0
var failed := 0


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL  ", label)


func _initialize() -> void:
	_run.call_deferred()


func _png(path: String, col: Color, size := Vector2i(8, 8)) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(col)
	img.save_png(path)


func _rm(dir: String) -> void:
	var abs_dir := ProjectSettings.globalize_path(dir)
	var d := DirAccess.open(abs_dir)
	if d == null:
		return
	for sub in d.get_directories():
		_rm(dir.path_join(sub))
	for f in d.get_files():
		DirAccess.remove_absolute(abs_dir.path_join(f))
	DirAccess.remove_absolute(abs_dir)


func _run() -> void:
	print("Aether Sigil asset resolver test")
	Data.ensure_loaded()
	test_tiers()
	test_concept_index()
	test_ids()
	test_coverage()
	test_contract()
	await test_procedural_draws()
	print("%d pass / %d fail" % [passed, failed])
	quit(mini(failed, 255))


func _sandbox() -> void:
	_rm("user://assets_test")
	Assets.ai_root = AI
	Assets.gen_root = GEN
	Assets.dev_root = ""
	Assets.aliases = {}
	Assets.clear_cache()


func test_tiers() -> void:
	print("[tier order]")
	_sandbox()
	check(Assets.tile("01", "ground") == null, "nothing on disk -> null (procedural)")
	_png(GEN + "/tiles/T01_verdant_spire/ground.png", Color.RED)
	Assets.clear_cache()
	var t := Assets.tile("01", "ground")
	check(t != null and Assets.tier(t) == "generated", "generated placeholder used when no painted art")
	check(t.get_width() == 8, "raw (un-imported) PNG loads")
	_png(AI + "/from-concepts/tiles/T01/ground.png", Color.GREEN)
	Assets.clear_cache()
	check(Assets.tier(Assets.tile("01", "ground")) == "concepts", "from-concepts beats generated")
	_png(AI + "/tiles/T01/ground.png", Color.BLUE)
	check(Assets.tier(Assets.tile("01", "ground")) == "concepts", "results are cached until clear_cache()")
	Assets.clear_cache()
	check(Assets.tier(Assets.tile("01", "ground")) == "ai", "art/ai beats from-concepts")
	# restored art in the repo-root dev folder beats a crop in game/art/ai/from-concepts
	Assets.dev_root = "user://assets_test/dev"
	_png(AI + "/from-concepts/towers/T04.png", Color.RED)
	_png("user://assets_test/dev/towers/T04.png", Color.GREEN, Vector2i(5, 5))
	Assets.clear_cache()
	var t4 := Assets.tower_art("04")
	check(t4 != null and t4.get_width() == 5 and Assets.tier(t4) == "ai", "restored art (any root) beats concept crops (any root)")
	Assets.dev_root = ""
	Assets.clear_cache()
	_png(AI + "/tiles/_any/lava.png", Color.ORANGE)
	Assets.clear_cache()
	check(Assets.tier(Assets.tile("05", "lava")) == "ai", "tiles/_any/<type> serves every tower")
	# per-tower prop override, then the shared prop
	_png(GEN + "/props/relic.png", Color.YELLOW)
	_png(AI + "/props/T02/relic.png", Color.WHITE)
	Assets.clear_cache()
	check(Assets.tier(Assets.prop("relic", "01")) == "generated" and Assets.tier(Assets.prop("relic", "02")) == "ai", "props/<tower>/<id> overrides props/<id>")
	# monster chain: id -> evolution family -> element family
	var mon: Dictionary = Data.bible().monsters[0]
	_png(AI + "/monsters/%s.png" % str(mon.element_family).to_lower(), Color.GRAY)
	Assets.clear_cache()
	var by_elem := Assets.monster(str(mon.id))
	_png(AI + "/monsters/%s.png" % mon.evolution_family, Color.GRAY)
	Assets.clear_cache()
	var by_fam := Assets.monster(str(mon.id))
	_png(AI + "/monsters/%s.png" % mon.id, Color.GRAY)
	Assets.clear_cache()
	var by_id := Assets.monster(str(mon.id))
	check(by_elem != null and by_fam != null and by_id != null and by_id != by_fam and by_fam != by_elem, "monster: id beats evolution family beats element family")
	Assets.aliases["uid-7"] = str(mon.id)
	check(Assets.monster("uid-7") == by_id, "owned-monster uid resolves through its form id")
	# backdrops: tower, then nothing (shader); title: world, then bundled key art
	check(Assets.backdrop("03") == null, "no tower backdrop -> procedural sky")
	check(Assets.tier(Assets.title_backdrop()) == "bundled", "title backdrop falls back to the bundled key art")
	_png(AI + "/backdrops/world.png", Color.BLACK)
	Assets.clear_cache()
	check(Assets.tier(Assets.title_backdrop()) == "ai", "painted backdrops/world replaces the key art")
	check(Assets.tier(Assets.ui("logo")) == "bundled", "logo falls back to the bundled logo")
	check(Assets.portrait("Nobody Here") == null, "unknown speaker -> procedural portrait")


func test_concept_index() -> void:
	print("[from-concepts index]")
	_sandbox()
	var fc := AI + "/from-concepts"
	_png(fc + "/towers/t01_verdant_spire_card.png", Color.RED, Vector2i(4, 4))
	_png(fc + "/towers/t01_verdant_spire_art.png", Color.GREEN, Vector2i(6, 6))
	_png(fc + "/champions/c01_lyra_quill.png", Color.BLUE, Vector2i(5, 10))
	_png(fc + "/protagonist/summoner_closeup.png", Color.BLUE, Vector2i(7, 7))
	_png(fc + "/monsters/m07_quillphoenix_card.png", Color.RED, Vector2i(3, 3))
	_png(fc + "/monsters/m07_quillphoenix.png", Color.GREEN, Vector2i(9, 9))
	_png(fc + "/monsters/evo_quillphoenix_lv36.png", Color.RED, Vector2i(2, 2))
	Assets.clear_cache()
	var tw := Assets.tower_art("01")
	check(tw != null and tw.get_width() == 6, "tower card: t01_*_art beats t01_*_card")
	check(Assets.tower_art("02") == null, "tower without a crop -> procedural card")
	var lyra := Assets.portrait("Lyra Quill")
	check(lyra != null and Assets.is_crop(lyra), "champion crop c01_lyra_quill is Lyra Quill's portrait")
	check(Assets.portrait(str(Data.story().protagonist.name)) != null, "protagonist portrait from protagonist/summoner_closeup")
	var qp: Dictionary = {}
	for m in Data.bible().monsters:
		if str(m.name) == "Quillphoenix":
			qp = m
	check(not qp.is_empty(), "bible has Quillphoenix")
	if not qp.is_empty():
		var t := Assets.monster(str(qp.id))
		check(t != null and t.get_width() == 9, "monster crop by name: plain beats evo_*_lvNN beats *_card")
		var sib := ""
		for mid in Data.family_members(str(qp.evolution_family)):
			if mid != str(qp.id):
				sib = mid
		check(sib == "" or Assets.monster(sib) == t, "evolution-family member falls back to its family's crop")
		var other := ""
		for m in Data.bible().monsters:
			if str(m.element_family) == str(qp.element_family) and str(m.evolution_family) != str(qp.evolution_family):
				other = str(m.id)
				break
		check(other == "" or Assets.monster(other) == t, "same element family borrows the representative crop")
	_rm("user://assets_test")


func test_ids() -> void:
	print("[ids]")
	check(Assets.slug("Kess Varrow") == "kess_varrow" and Assets.slug("  Ari  Voss! ") == "ari_voss" and Assets.slug("Narrator") == "narrator", "speaker slug rule")
	check(Assets.tower_key("01") == "T01" and Assets.tower_key("T12") == "T12", "tower key T01..T12")
	check(Assets.tower_folder("12") == "T12_sunforge_throne", "generated folder for a tower")


func test_coverage() -> void:
	print("[coverage with the shipped art]")
	Assets.reset_roots()
	Assets.aliases = {}
	var missing := []
	for st in Data.stages():
		var tid := str(st.tower_id)
		var seen := {}
		for row in st.map_grid:
			for t in row:
				seen[t] = true
		for t in seen:
			var names: Array = [t] if t != "ground" else ["ground", "ground_v2", "ground_v3"]
			if t == "bridge":
				names = ["bridge", "bridge_y"]
			for n in names:
				if Assets.tile(tid, n) == null and not missing.has("%s/%s" % [tid, n]):
					missing.append("%s/%s" % [tid, n])
	check(missing.is_empty(), "every tile type on every tower's maps has a texture (missing %s)" % str(missing.slice(0, 5)))
	for t in Data.towers():
		var tid := str(t.tower_id)
		var fam := str(Data.rules().tower_theme_family.get(str(t.theme), "Light"))
		check(Assets.element_icon(fam) != null, "tower %s card has art or its element icon" % tid)
	for p in Assets.PROPS:
		check(Assets.prop(p) != null, "prop %s has a texture" % p)
	for f in Assets.ELEMENT_FAMILIES:
		check(Assets.element_icon(f) != null and Assets.token_frame(0, f) != null and Assets.token_frame(1, f) != null, "element family %s: icon + ally/enemy token frames" % f)
	var no_art := []
	for m in Data.bible().monsters:
		if Assets.monster(str(m.id), str(m.element_family)) == null and Assets.silhouette(str(m.role)) == null:
			no_art.append(m.id)
	check(no_art.is_empty(), "all 1000 monsters draw a creature (painted, concept crop or silhouette) (missing %s)" % str(no_art.slice(0, 5)))
	var fam_art := 0
	for f in Assets.evolution_families():
		var members := Data.family_members(f)
		if not members.is_empty() and Assets.monster(str(members[0])) != null:
			fam_art += 1
	print("  info: %d / %d evolution families currently show painted or concept art" % [fam_art, Assets.evolution_families().size()])
	for name in ["turn_order/slot_ally", "turn_order/slot_enemy_active", "panel/panel_border", "panel/panel_header", "objective/checkbox_checked", "buttons/btn_attack_normal"]:
		check(Assets.ui(name) != null, "ui %s has a texture" % name)
	check(Assets.ui("logo") != null and Assets.title_backdrop() != null, "title logo and key-art backdrop resolve")


func test_contract() -> void:
	print("[contract]")
	var slots := Assets.contract_slots()
	var all := []
	for k in slots:
		all += slots[k]
	var uniq := {}
	for s in all:
		uniq[s] = true
	check(uniq.size() == all.size(), "contract slot ids are unique (%d)" % all.size())
	check(slots.tiles.size() == 12 * Assets.TILE_TYPES.size(), "tiles: 12 towers x %d types" % Assets.TILE_TYPES.size())
	check(slots.towers.size() == 12 and slots.backdrops.size() == 13, "12 tower cards, 12 + world backdrops")
	check(slots.monsters.size() == 12 + Assets.evolution_families().size(), "monsters: 12 element + %d evolution families" % Assets.evolution_families().size())
	var sp := Assets.speakers()
	check(sp.has("Narrator") and sp.has(str(Data.story().protagonist.name)) and sp.has("Kess Varrow") and sp.has("Ari Voss"), "speakers include narrator, protagonist, story cast, stage rivals")
	for st in Data.stages():
		if not sp.has(str(st.opponent)):
			check(false, "opponent %s is a contract speaker" % st.opponent)
	check(slots.portraits.size() == sp.size(), "one portrait slot per speaker (%d)" % sp.size())
	var core := Assets.core_speakers()
	check(core.size() < sp.size() and core.has("Lyra Quill"), "core cast (%d) is a subset with the tower champions" % core.size())


## Every procedural fallback draws without errors (headless canvas).
func test_procedural_draws() -> void:
	print("[procedural fallbacks draw]")
	_sandbox()  # empty roots: everything procedural
	var c := Control.new()
	c.size = Vector2(200, 200)
	root.add_child(c)
	var who := Assets.speakers()   # every speaker in story.json, stage dialogue and the bible
	c.draw.connect(func():
		for w in who:
			UIArt.draw_portrait(c, Rect2(0, 0, 200, 200), w)
		UIArt.draw_tower_card(c, Rect2(0, 0, 200, 300), "01", "Wood", true)
		UIArt.draw_tower_card(c, Rect2(0, 0, 200, 300), "12", "Light", false)
		UIArt.draw_chip(c, Rect2(0, 0, 50, 50), 1, 0, true, false, "MON-0001", "Water", "Guardian")
		UIArt.draw_chip(c, Rect2(0, 0, 50, 50), 2, 1, false, true, "", "", "")
		Art.draw_island_underside(c, PackedVector2Array([Vector2(0, -100), Vector2(200, 0), Vector2(0, 100), Vector2(-200, 0)]), "01", [[Vector2(10, 110), 30.0]]))
	c.queue_redraw()
	await process_frame
	await process_frame
	check(true, "procedural portraits for all %d speakers, cards, chips and island underside drew" % who.size())
	for w in who:
		check(UIArt.speaker_color(w).a > 0.0, "speaker %s has a portrait colour" % w)
	Assets.reset_roots()
	var painted := 0
	for w in Assets.core_speakers():
		if Assets.portrait(w) != null:
			painted += 1
	print("  info: %d / %d core speakers currently have painted or concept portraits (rest: procedural)" % [painted, Assets.core_speakers().size()])
	c.queue_free()
	_rm("user://assets_test")
	Assets.reset_roots()
