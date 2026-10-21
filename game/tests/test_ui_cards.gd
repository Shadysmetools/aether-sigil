## Monster cards + meta screens: every rarity x element renders (painted art and missing art),
## the card model matches the rules (Bond, SP, evolution line, stat bars), long-press swallows the
## tap, compendium filter/sort/search correctness, the draft refuses picks over the Bond cap, the
## settings sliders drive the audio buses, every menu opens and closes, touch targets >= 88 px.
extends SceneTree

const Data = preload("res://scripts/data_loader.gd")
const Assets = preload("res://scripts/assets.gd")
const Prog = preload("res://scripts/progression.gd")
const Summon = preload("res://scripts/summon.gd")
const MonsterCard = preload("res://scripts/ui/monster_card.gd")
const Kit = preload("res://scripts/ui/menu_kit.gd")
const Model = preload("res://scripts/ui/collection_model.gd")
const AM = preload("res://scripts/audio_manager.gd")

const SAVE := "user://ui_cards_save.json"
const UI_PREFS := "user://ui_cards_prefs.cfg"
const AUDIO_PREFS := "user://ui_cards_audio.cfg"

var passed := 0
var failed := 0


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL  ", label)


func eq(a: Variant, b: Variant, label: String) -> void:
	check(a == b, "%s (got %s, want %s)" % [label, str(a), str(b)])


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _cleanup() -> void:
	for p in [SAVE, UI_PREFS, AUDIO_PREFS]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _run() -> void:
	print("Aether Sigil monster cards + meta screens")
	_cleanup()
	Kit.prefs_path = UI_PREFS
	Kit.reduced_motion = false
	Kit.load_prefs()
	Data.ensure_loaded()
	await test_card_matrix(true)
	await test_missing_art()
	test_model()
	await test_long_press()
	test_collection_model()
	await test_main_screens()
	_cleanup()
	print("%d pass / %d fail" % [passed, failed])
	quit(mini(failed, 255))


## A bible monster of rarity r and family f; if the data has none, one of rarity r recast to f.
func _record(r: String, f: String) -> Dictionary:
	var any := ""
	for id in Data.monster_ids():
		var m := Data.monster(id)
		if str(m.rarity) == r:
			if any == "":
				any = id
			if str(m.element_family) == f:
				return {"id": id, "rec": m.duplicate()}
	var rec := Data.monster(any).duplicate()
	rec["element_family"] = f
	return {"id": any, "rec": rec}


func _card_for(r: String, f: String, v: int) -> Button:
	var pick := _record(r, f)
	var c := MonsterCard.new()
	c.setup_bible(str(pick.id), v, true)
	if str(c.rec.element_family) != f:   # recast family (combination missing from the data)
		c.rec["element_family"] = f
		c.model = MonsterCard.compute_model(c.rec, {}, str(pick.id))
	return c


## Every rarity x every element family, all three sizes: builds, paints, right tier effects.
func test_card_matrix(painted: bool) -> void:
	print("[card matrix: %s]" % ("painted art" if painted else "fallback art"))
	var holder := Control.new()
	holder.size = Vector2(1080, 1920)
	root.add_child(holder)
	var rar := Kit.rarities()
	eq(rar.size(), 6, "six rarity tiers from data (Common..Legendary with Mythic)")
	var frames := {}
	var bad := []
	var cards := []
	for r in rar:
		for f in Assets.ELEMENT_FAMILIES:
			for v in [MonsterCard.Variant.FULL, MonsterCard.Variant.COMPACT, MonsterCard.Variant.MINI]:
				var c := _card_for(r, f, v)
				holder.add_child(c)
				cards.append(c)
	await _frames(3)
	for c in cards:
		var t := Kit.tier_of(str(c.rec.rarity))
		frames[t] = c.model.frame
		if c.draws < 1:
			bad.append("%s/%s/%d not drawn" % [c.rec.rarity, c.rec.element_family, c.variant])
		if c.size.x < MonsterCard.SIZES[c.variant].x - 0.5:
			bad.append("%s size %s" % [c.rec.name, str(c.size)])
		if c.variant != MonsterCard.Variant.MINI and (c._foil != null) != (t >= 2):
			bad.append("%s tier %d shine=%s" % [c.rec.name, t, str(c._foil != null)])
		if (c._aura != null) != (t >= 5):
			bad.append("%s tier %d aura=%s" % [c.rec.name, t, str(c._aura != null)])
		if c.model.family != str(c.rec.element_family):
			bad.append("%s family" % c.rec.name)
	eq(bad, [], "%d cards (6 rarities x 12 families x 3 sizes) render with the right frame effects" % cards.size())
	var distinct := {}
	for t in frames:
		distinct[str(frames[t])] = true
	eq(distinct.size(), 6, "each rarity tier has its own frame metal")
	var full := _card_for("Legendary", "Fire", MonsterCard.Variant.FULL)
	holder.add_child(full)
	await _frames(1)
	var d0: int = full.draws
	full.flip()
	await create_timer(0.4).timeout
	check(full.flipped and full.draws > d0, "FULL card flips to its back face and repaints")
	check(full.model.gems == 6 and full.model.crest and full.model.foil, "Legendary: 6 gems, crest, foil")
	var com := _card_for("Common", "Water", MonsterCard.Variant.FULL)
	check(com.model.gems == 0 and not com.model.crest and not com.model.shine, "Common: plain frame, no gems, no shine")
	holder.queue_free()
	com.free()
	await _frames(1)


## No painted art anywhere: Assets.monster is null and the cards still paint (procedural fallback).
func test_missing_art() -> void:
	print("[missing art]")
	Assets.ai_root = "user://__ui_cards_no_art__"
	Assets.gen_root = "user://__ui_cards_no_art__"
	Assets.dev_root = ""
	Assets.clear_cache()
	check(Assets.monster("MON-0001", "Water") == null, "art roots blanked: no monster texture resolves")
	var holder := Control.new()
	root.add_child(holder)
	var cards := []
	for r in Kit.rarities():
		for v in [MonsterCard.Variant.FULL, MonsterCard.Variant.COMPACT, MonsterCard.Variant.MINI]:
			var c := _card_for(r, "Arcane", v)
			holder.add_child(c)
			cards.append(c)
	await _frames(3)
	check(cards.all(func(c): return c.draws > 0 and c._texture() == null), "all %d cards paint the procedural fallback" % cards.size())
	holder.queue_free()
	Assets.reset_roots()
	await _frames(1)


func test_model() -> void:
	print("[card model]")
	var m := Data.monster("MON-0001")
	var cm := MonsterCard.compute_model(m, {}, "MON-0001")
	eq(cm.bond, Summon.bond(m), "Bond badge = Summon.bond")
	eq(cm.sp, Summon.crack_cost(m), "SP badge = Summon.crack_cost")
	eq(MonsterCard.line_levels(), [1] + Array(Data.progression().evolution.thresholds).map(func(x): return int(x)), "line levels from data (1/16/36)")
	var bad := []
	for id in Data.monster_ids():
		var line := MonsterCard.evolution_line(id)
		if line.is_empty() or line[0] != id or line.size() > 3:
			bad.append(id)
		for x in line:
			if str(Data.monster(x).evolution_family) != str(Data.monster(id).evolution_family):
				bad.append(id)
	eq(bad, [], "every evolution line starts at the monster, <= 3 forms, one family")
	var fr: Dictionary = MonsterCard.compute_model(m).fracs
	check(fr.values().all(func(x): return x > 0.0 and x <= 1.0), "stat bar fractions in (0, 1]")
	var recipe: Dictionary = Data.progression().fusion.recipes[0]
	check(MonsterCard.recipes_for(str(recipe.parents[0])).has(recipe), "fusion recipes found for a parent")
	check(MonsterCard.ability_description(str(m.ability)) == str(m.ability_description), "skill line = bible ability_description")
	var inst := Prog.new_instance("OWN-9001", "MON-0001")
	inst.level = 16
	Prog.evolve(inst)
	var em := MonsterCard.compute_model(Prog.battle_record(inst), inst, str(inst.base_id))
	check(em.evo_stage == 1 and em.evo_forms == 3 and em.bond == Summon.bond(Prog.battle_record(inst)), "evolved instance: stage pip 2/3, Bond includes evolution")
	var a := Prog.new_instance("OWN-9002", str(recipe.parents[0]))
	var b := Prog.new_instance("OWN-9003", str(recipe.parents[1]))
	a.level = 12
	b.level = 12
	var fz := Prog.fusion_preview(a, b, "OWN-9004")
	var fc := MonsterCard.new()
	fc.setup_inst(fz, MonsterCard.Variant.COMPACT)
	check(fc.model.fused and fc.model.evo_forms == 0 and fc.model.name == str(recipe.name), "fused card: ribbon, no evolution pips (%s)" % fc.model.name)
	fc.free()


## Hold = details, and the tap that ends the hold is swallowed (toggle undone).
func test_long_press() -> void:
	print("[long press]")
	var c := _card_for("Rare", "Wind", MonsterCard.Variant.COMPACT)
	root.add_child(c)
	await _frames(1)
	var taps := [0]
	var holds := [0]
	c.on_tap(func(): taps[0] += 1)
	c.long_pressed.connect(func(_c): holds[0] += 1)
	c.button_down.emit()
	await create_timer(MonsterCard.LONG_PRESS + 0.15).timeout
	c.button_up.emit()
	c.button_pressed = true          # what a toggle release does
	c.pressed.emit()
	check(holds[0] == 1 and taps[0] == 0 and not c.button_pressed, "hold opens details, swallows the tap and undoes the toggle")
	c.button_down.emit()
	c.button_up.emit()
	c.pressed.emit()
	await create_timer(MonsterCard.LONG_PRESS + 0.1).timeout
	check(taps[0] == 1 and holds[0] == 1, "a quick tap calls the tap callback only")
	c.queue_free()


func test_collection_model() -> void:
	print("[compendium filter / sort / search]")
	var all := Model.query({})
	eq(all.size(), 1000, "no filter: all 1,000 monsters")
	check(Model.query({"family": "Fire"}).all(func(id): return str(Data.monster(id).element_family) == "Fire"), "family filter")
	check(Model.query({"rarity": "Epic"}).all(func(id): return str(Data.monster(id).rarity) == "Epic"), "rarity filter")
	check(Model.query({"role": "Scout"}).all(func(id): return str(Data.monster(id).role) == "Scout"), "role filter")
	var brute := Data.monster_ids().filter(func(id):
		var m := Data.monster(id)
		return m.element_family == "Water" and m.rarity == "Rare" and m.role == "Guardian")
	eq(Model.query({"family": "Water", "rarity": "Rare", "role": "Guardian"}).size(), brute.size(), "combined filters = intersection")
	var counts := 0
	for f in Assets.ELEMENT_FAMILIES:
		counts += Model.query({"family": f}).size()
	eq(counts, 1000, "the 12 family filters partition the compendium")
	check(Model.query({"search": "FANGST"}).has("MON-0001"), "search is case-insensitive on names")
	var mist := Model.query({"search": "mist"})
	check(not mist.is_empty() and mist.all(func(id):
		var m := Data.monster(id)
		return str(m.name).to_lower().contains("mist") or str(m.element).to_lower().contains("mist") or str(m.ability).to_lower().contains("mist") or str(id).to_lower().contains("mist")), "search matches name / element / skill")
	eq(Model.query({"search": "zzzz-no-such"}), [], "search with no match is empty")
	var by_name := Model.query({"sort": "name"})
	var ok := true
	for i in by_name.size() - 1:
		if str(Data.monster(by_name[i]).name).naturalnocasecmp_to(str(Data.monster(by_name[i + 1]).name)) > 0:
			ok = false
	check(ok, "sort by name is ascending")
	var by_rar := Model.query({"sort": "rarity"})
	ok = true
	for i in by_rar.size() - 1:
		if Kit.tier_of(str(Data.monster(by_rar[i]).rarity)) < Kit.tier_of(str(Data.monster(by_rar[i + 1]).rarity)):
			ok = false
	check(ok and str(Data.monster(by_rar[0]).rarity) == "Legendary", "sort by rarity: Legendary first, never rising")
	var by_pow := Model.query({"sort": "power", "family": "Ice"})
	ok = true
	for i in by_pow.size() - 1:
		if Model.power_of(by_pow[i]) < Model.power_of(by_pow[i + 1]):
			ok = false
	check(ok, "sort by power is descending")
	var by_el := Model.query({"sort": "element"})
	ok = true
	for i in by_el.size() - 1:
		if str(Data.monster(by_el[i]).element_family) > str(Data.monster(by_el[i + 1]).element_family):
			ok = false
	check(ok, "sort by element groups families")
	var num := Model.query({"sort": "number"})
	check(num[0] == "MON-0001" and num[-1] == "MON-1000", "default sort is compendium number")
	var roster := [Prog.new_instance("OWN-1", "MON-0001"), Prog.new_instance("OWN-2", "MON-0007")]
	var own := Model.collected(roster)
	eq(own.size(), 2, "collected = owned forms")
	eq(Model.query({"owned_only": true}, own).size(), 2, "owned-only filter")
	roster[0].level = 16
	Prog.evolve(roster[0])
	eq(Model.collected(roster).size(), 3, "evolving adds the new form to the collection")


func _visible_buttons(n: Node, out: Array) -> void:
	if n is CanvasItem and not n.visible:
		return
	if n is BaseButton or n is OptionButton:
		out.append(n)
	for c in n.get_children():
		_visible_buttons(c, out)


func _small_targets(screen: Control) -> Array:
	var bs := []
	_visible_buttons(screen, bs)
	return bs.filter(func(b): return b.size.x < Kit.HIT - 0.5 or b.size.y < Kit.HIT - 0.5).map(func(b): return "%s %s" % [b.name, str(b.size)])


## The real main scene: hub, every menu opens/closes, draft Bond cap, settings, detail overlay.
func test_main_scene_setup() -> Node:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	root.add_child(main)
	await _frames(2)
	return main


func test_main_screens() -> void:
	print("[main scene meta screens]")
	var main: Node = await test_main_scene_setup()
	check(main.select_screen.visible and main.hub.visible and not main.map_view.visible, "starts on the title hub")
	main._on_dialogue_skip()
	var screens := {"hub": main.hub, "map": main.map_view, "squad": main.squad_screen, "collection": main.collection_screen,
		"evolution": main.evo_screen, "fusion": main.fusion_screen, "settings": main.settings_screen}
	var meta := [main.squad_screen, main.collection_screen, main.evo_screen, main.fusion_screen, main.settings_screen, main.draft_screen, main.tower_screen]
	# every hub button routes to its screen; Back returns to the hub
	var routes := {"story": "map", "squad": "squad", "collection": "collection", "evolution": "evolution", "fusion": "fusion", "settings": "settings"}
	for a in routes:
		main.show_title_hub()
		await _frames(1)
		main.hub.buttons[a].pressed.emit()
		await _frames(2)
		var want: Control = screens[routes[a]]
		var shown := meta.filter(func(s): return s.visible)
		check(want.is_visible_in_tree() and (shown.size() == (0 if a == "story" else 1)), "hub '%s' opens only its screen" % a)
		eq(_small_targets(want), [], "'%s' touch targets >= 88 px" % a)
	main.show_title_hub()
	await _frames(1)
	eq(_small_targets(main.hub), [], "hub touch targets >= 88 px")
	check(main.hub._subs["collection"].text.contains("/ 1000"), "hub shows collected / 1000: %s" % main.hub._subs["collection"].text)
	# collection: filter through the UI, page, open + close a detail
	main.show_collection()
	await _frames(1)
	var col = main.collection_screen
	eq(col.cards.size(), col.PAGE, "compendium page shows %d cards" % col.PAGE)
	col.family_chips["Fire"].pressed.emit()
	await _frames(1)
	check(col.cards.all(func(c): return str(c.rec.element_family) == "Fire") and col.results.size() == Model.query({"family": "Fire"}).size(), "Fire chip filters the grid")
	col.rarity_menu.select(6)
	col.rarity_menu.item_selected.emit(6)
	await _frames(1)
	check(col.cards.all(func(c): return str(c.rec.rarity) == "Legendary" and str(c.rec.element_family) == "Fire"), "rarity menu narrows within the element")
	col.family_chips[""].pressed.emit()
	col.rarity_menu.select(0)
	col.rarity_menu.item_selected.emit(0)
	col.sort_menu.select(1)
	col.sort_menu.item_selected.emit(1)
	await _frames(1)
	eq(col.pages(), ceili(1000 / float(col.PAGE)), "pages over the whole compendium")
	col.next_b.pressed.emit()
	await _frames(1)
	eq(col.page, 1, "Next pages forward")
	eq(col.cards[0].mon_id, Model.query({"sort": "name"})[col.PAGE], "page 2 starts at result %d (sorted by name)" % col.PAGE)
	col.search.text_changed.emit("fangst")
	await _frames(1)
	check(col.results.has("MON-0001") and col.page == 0, "search box filters and resets the page")
	col.cards[0].pressed.emit()
	await _frames(2)
	check(main.card_detail.visible and main.card_detail.card.variant == MonsterCard.Variant.FULL and main.card_detail.strip.get_child_count() >= 1, "tapping a compendium card opens the FULL detail with its evolution line")
	main.card_detail.close()
	check(not main.card_detail.visible, "detail closes")
	# squad slots follow the picks
	main.show_squad_builder()
	await _frames(1)
	eq(main.squad_slots.cards.size(), main.squad_pick.size(), "squad strip shows one mini card per pick")
	# draft: Bond cap enforced in the UI
	main.progress.unlocked = 11
	main._on_stage_pressed("T01-L01")
	await _frames(1)
	check(main.draft_screen.visible, "stage tap opens the draft")
	var cap := Summon.draft_cap(Data.stage("T01-L01"))
	var recs: Dictionary = main._roster_records()
	main.draft_pick = []
	main._refresh_draft()
	var ever_over := false
	var refused := 0
	for inst in main.progress.roster:
		var before: int = main.draft_pick.size()
		var uid := str(inst.uid)
		var fits := Summon.total_bond(main.draft_pick, recs) + Summon.bond(recs[uid]) <= cap and before < Data.squad_size()
		check(main.draft_buttons[uid].unaffordable == (not fits), "card %s shows over-cap state = %s" % [uid, str(not fits)])
		main.draft_buttons[uid].pressed.emit()
		if Summon.total_bond(main.draft_pick, recs) > cap:
			ever_over = true
		if main.draft_pick.size() == before:
			refused += 1
	check(not ever_over, "tapping every card never pushes the draft over the Bond cap (%d)" % cap)
	check(refused > 0, "over-cap picks are refused (%d)" % refused)
	eq(main.draft_bond_bar.total, Summon.total_bond(main.draft_pick, recs), "Bond bar shows the running total")
	eq(main.draft_bond_bar.cap, cap, "Bond bar shows the tower cap")
	check(main.draft_slots.cards.size() == main.draft_pick.size() and not main.draft_confirm.disabled, "slots filled, Place enabled for the legal draft")
	eq(_small_targets(main.draft_screen), [], "draft touch targets >= 88 px")
	main._on_draft_toggle(main.draft_pick[0])
	check(main.draft_pick.size() == main.draft_slots.cards.size(), "removing a pick frees its slot")
	main._on_draft_back()
	await _frames(1)
	check(not main.draft_screen.visible, "draft Back leaves the draft")
	# evolution + fusion screens list the roster as cards
	main.progress.get_inst(main.progress.squad[0]).level = 16
	main.show_evolution()
	await _frames(1)
	eq(main.evo_list.get_child_count(), main.progress.roster.size(), "evolution rows = roster")
	main.show_fusion()
	var bench: Array = main.progress.roster.filter(func(i): return not main.progress.squad.has(i.uid))
	bench[0].level = 12
	bench[1].level = 11
	main._on_fusion_toggle(str(bench[0].uid))
	main._on_fusion_toggle(str(bench[1].uid))
	await _frames(2)
	var prev: Dictionary = main.progress.fusion_preview(str(bench[0].uid), str(bench[1].uid))
	check(main.fusion_stage.result_card != null and main.fusion_stage.result_card.model.name == str(prev.name), "fusion stage previews the result card (%s)" % prev.name)
	# settings: sliders drive an injected AudioManager; reduced motion persists
	var am: Node = AM.new()
	am.prefs_path = AUDIO_PREFS
	root.add_child(am)
	await _frames(1)
	main.settings_screen.audio = am
	main.show_settings()
	await _frames(1)
	main.settings_screen.sliders["Music"].value = 0.25
	check(absf(am.get_volume("Music") - 0.25) < 0.001, "Music slider sets the Music bus volume")
	main.settings_screen.sliders["SFX"].value = 0.6
	check(absf(am.get_volume("SFX") - 0.6) < 0.001, "SFX slider sets the SFX bus volume")
	main.settings_screen.motion_toggle.button_pressed = true
	check(Kit.reduced_motion and FileAccess.file_exists(UI_PREFS), "reduced motion saved to the UI prefs")
	Kit.reduced_motion = false
	Kit.load_prefs()
	check(Kit.reduced_motion, "reduced motion reloads from the prefs file")
	main.settings_screen.motion_toggle.button_pressed = false
	main.settings_screen.reset_button.pressed.emit()
	check(main.progress.roster.size() > 0 and main.settings_screen.reset_button.text.contains("again"), "Reset asks for a second tap")
	main.settings_screen.refresh()
	am.queue_free()
	main.show_title_hub()
	await _frames(1)
	check(meta.all(func(s): return not s.visible) and main.hub.visible, "every meta screen closed on return to the hub")
	main.queue_free()
	await _frames(2)
