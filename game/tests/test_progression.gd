## Progression tests: XP/levels, evolution, fusion, names, save/load and migration.
## Run: Godot_console.exe --headless --path <game dir> --script res://tests/test_progression.gd
extends SceneTree

const Data = preload("res://scripts/data_loader.gd")
const Prog = preload("res://scripts/progression.gd")
const Progress = preload("res://scripts/progress.gd")
const GameState = preload("res://scripts/game_state.gd")

const SAVE := "user://test_progression_save.json"

var passed := 0
var failed := 0


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("  PASS  ", label)
	else:
		failed += 1
		print("  FAIL  ", label)


func eq(actual, expected, label: String) -> void:
	check(actual == expected, "%s (got %s, want %s)" % [label, str(actual), str(expected)])


func _initialize() -> void:
	print("Aether Sigil progression tests")
	Data.ensure_loaded()
	test_xp()
	test_evolution()
	test_fusion()
	test_names()
	test_battle_use()
	test_save_load()
	test_migration()
	_rm()
	print("%d pass / %d fail" % [passed, failed])
	quit(mini(failed, 255))


func _rm() -> void:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


func test_xp() -> void:
	print("[XP and levels]")
	var X: Dictionary = Data.progression().xp
	eq(Prog.xp_to_next(1), int(X.to_next_base) + int(X.to_next_per_level), "XP for 1 -> 2 = base + per_level")
	eq(Prog.xp_to_next(10), int(X.to_next_base) + 10 * int(X.to_next_per_level), "XP for 10 -> 11")
	var inst := Prog.new_instance("OWN-0001", "MON-0177")
	eq(inst.level, 1, "new monsters start at level 1")
	eq(Prog.add_xp(inst, Prog.xp_to_next(1) - 1), 0, "one XP short: no level")
	eq(Prog.add_xp(inst, 1), 1, "exact XP: level 2")
	eq([inst.level, inst.xp], [2, 0], "leftover XP is 0")
	eq(Prog.add_xp(inst, Prog.xp_to_next(2) + Prog.xp_to_next(3) + 5), 2, "multi-level gain")
	eq([inst.level, inst.xp], [4, 5], "carry-over XP kept")
	var cap := Prog.level_cap(inst)
	Prog.add_xp(inst, 999999)
	eq(inst.level, cap, "levels stop at level_cap (%d)" % cap)
	eq(Prog.add_xp(inst, 100), 0, "no XP gain at the cap")
	# stat growth
	var g: Dictionary = Data.progression().growth_pct_per_level
	var m := Data.monster("MON-0177")
	var lv10 := Prog.new_instance("OWN-0002", "MON-0177")
	lv10.level = 10
	var st := Prog.stats(lv10)
	eq(st.hp, roundi(m.hp * (1.0 + float(g.hp) / 100.0 * 9)), "hp grows %s%% per level" % str(g.hp))
	eq(st.attack, roundi(m.attack * (1.0 + float(g.attack) / 100.0 * 9)), "attack grows %s%% per level" % str(g.attack))
	eq([st.move, st.range], [int(m.move), int(m.range)], "move and range never grow")
	# battle XP formula
	eq(Prog.battle_xp(0, true, 1), roundi(float(X.participation) * float(X.win_mult)), "win, no KO, T01")
	eq(Prog.battle_xp(2, false, 3), roundi((float(X.participation) + 2 * float(X.per_ko)) * float(X.loss_mult) * (1.0 + float(X.tower_bonus_pct) / 100.0 * 2)), "loss, 2 KOs, T03")


func test_evolution() -> void:
	print("[evolution]")
	var th: Array = Data.progression().evolution.thresholds
	var inst := Prog.new_instance("OWN-0001", "MON-0177")
	var fam := Data.family_members(str(Data.monster("MON-0177").evolution_family))
	eq(Prog.next_form(inst), fam[fam.find("MON-0177") + 1], "next form = next member of the evolution_family")
	inst.level = int(th[0]) - 1
	eq(Prog.can_evolve(inst), "needs_level_%d" % int(th[0]), "blocked one level before the threshold")
	eq(Prog.evolve(inst), "", "evolve() refuses before the threshold")
	inst.level = int(th[0])
	eq(Prog.can_evolve(inst), Prog.OK, "allowed at Lv%d" % int(th[0]))
	var before := Prog.stats(inst)
	var line := Prog.evolve(inst)
	check(line.contains("evolved into"), "evolution dialogue line: '%s'" % line)
	eq(inst.evo_stage, 1, "evo stage 1")
	eq(inst.name, str(Data.monster(str(inst.form_id)).name), "takes the next form's name")
	eq(Prog.field(inst, "element_family"), str(Data.monster("MON-0177").element_family), "keeps its line's element")
	eq(Prog.stats(inst).hp, roundi(roundi(Data.monster("MON-0177").hp * 1.15) * (1.0 + 0.02 * (inst.level - 1))), "hp x1.15 after evolving")
	check(Prog.stats(inst).attack > before.attack, "attack rises")
	eq(Prog.can_evolve(inst), "needs_level_%d" % int(th[1]), "second evolution needs Lv%d" % int(th[1]))
	inst.level = int(th[1])
	eq(Prog.can_evolve(inst), Prog.OK if Prog.next_form(inst) != "" else "last_in_family", "second evolution at Lv%d" % int(th[1]))
	Prog.evolve(inst)
	eq(Prog.can_evolve(inst), "final_form", "3 forms per line, then final")
	var last := Prog.new_instance("OWN-0009", fam[-1])
	last.level = 50
	eq(Prog.can_evolve(last), "last_in_family", "the last family member cannot evolve")
	eq(Prog.battle_record(inst).skill_tier, 2, "each evolution upgrades the Skill tier")


func _lv(uid: String, mon: String, level: int) -> Dictionary:
	var i := Prog.new_instance(uid, mon)
	i.level = level
	return i


func test_fusion() -> void:
	print("[fusion]")
	var F: Dictionary = Data.progression().fusion
	var a := _lv("OWN-0001", "MON-0033", 20)
	var b := _lv("OWN-0002", "MON-0188", 12)
	var r1 := Prog.fusion_preview(a, b, "OWN-0050")
	var r2 := Prog.fusion_preview(b, a, "OWN-0050")
	eq(JSON.stringify(r1), JSON.stringify(r2), "A+B == B+A (deterministic)")
	eq(JSON.stringify(Prog.fusion_preview(a, b, "OWN-0050")), JSON.stringify(r1), "same parents, same result")
	eq(r1.element_family, Prog.field(a, "element_family"), "element from the higher-level parent")
	eq(r1.secondary_family, Prog.field(b, "element_family"), "secondary affinity from the other parent")
	eq([r1.ability, r1.secondary_ability], [Prog.field(a, "ability"), Prog.field(b, "ability")], "one ability from each parent; Skill = primary's")
	eq(r1.level, 20, "keeps the primary's level")
	var ba := Prog.base_stats(a)
	var bb := Prog.base_stats(b)
	eq(r1.base.hp, roundi((0.6 * ba.hp + 0.4 * bb.hp) * (1.0 + float(F.bonus_pct) / 100.0)), "hp = 60/40 blend + %d%%" % int(F.bonus_pct))
	eq(r1.base.attack, roundi((0.6 * ba.attack + 0.4 * bb.attack) * 1.1), "attack = 60/40 blend + bonus")
	eq(r1.base.move, roundi(0.6 * ba.move + 0.4 * bb.move), "move = blend, no bonus")
	var order: Array = F.rarity_order
	eq(r1.rarity, order[mini(maxi(order.find(Prog.field(a, "rarity")), order.find(Prog.field(b, "rarity"))) + 1, order.size() - 1)], "rarity = max + 1 tier")
	var leg := _lv("OWN-0003", "MON-0010", 30)  # Legendary
	eq(Prog.fusion_preview(leg, a, "OWN-0051").rarity, "Legendary", "rarity capped at Legendary")
	eq(Prog.can_fuse(a, a, 9), "same_monster_twice", "rejected: same monster twice")
	eq(Prog.can_fuse(a, _lv("OWN-0004", "MON-0099", 3), 9), "both_need_level_%d" % int(F.min_level), "rejected: parent below level %d" % int(F.min_level))
	eq(Prog.can_fuse(a, b, 4), "roster_would_drop_below_%d" % int(F.min_roster_after), "rejected: roster too small")
	eq(Prog.can_fuse(a, b, 9), Prog.OK, "valid pair accepted")
	# recipe
	var v := Prog.fusion_preview(_lv("OWN-0005", "MON-0011", 15), _lv("OWN-0006", "MON-0596", 15), "OWN-0052")
	eq([v.name, v.element_family], ["Verdalux", "Wood"], "recipe: Feraldrakea + Tempesthydraen -> Verdalux (Wood)")
	var rec := Prog.recipe_for({"base_id": "MON-0596"}, {"base_id": "MON-0011"})
	eq(v.base.hp, roundi((0.6 * Prog.base_stats(_lv("x", "MON-0011", 15)).hp + 0.4 * Prog.base_stats(_lv("y", "MON-0596", 15)).hp) * (1.0 + float(rec.bonus_pct) / 100.0)) if Prog.order_parents(_lv("OWN-0005", "MON-0011", 15), _lv("OWN-0006", "MON-0596", 15))[0].base_id == "MON-0011" else v.base.hp, "recipe bonus applies")
	# fused monster cannot evolve; secondary affinity in battle record
	eq(Prog.can_evolve(r1), "fused_monsters_do_not_evolve", "fused monsters do not evolve")
	eq(Prog.battle_record(r1).secondary_family, r1.secondary_family, "battle record carries the secondary affinity")


func test_names() -> void:
	print("[fusion names: uniqueness + franchise check]")
	var bible := {}
	for id in Data.monster_ids():
		bible[str(Data.monster(id).name).to_lower()] = true
	# The bible itself must be clean (the 3 'archen' names were renamed on 2026-10-21).
	var dirty := []
	for id in Data.monster_ids():
		var n := str(Data.monster(id).name)
		var p := Prog.name_problem(n)
		if p != "collides_with_bible_monster":
			dirty.append("%s:%s" % [n, p])
	eq(dirty, [], "no bible monster hits a reserved franchise name or token")
	check(Prog.name_problem("Pikachu") == "reserved_franchise_name", "reserved franchise names are refused")
	check(Prog.name_problem("Duskmonarchen").begins_with("contains_reserved_token"), "reserved tokens refused (archen)")
	check(Prog.name_problem("Fangstaga") == "collides_with_bible_monster", "bible names refused")
	for r in Data.progression().fusion.recipes:
		eq(Prog.name_problem(str(r.name)), "", "recipe name '%s' is clean" % r.name)
	# Generated names for many deterministic pairs: never empty, never a bible/reserved name, unique.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ids := Data.monster_ids()
	var seen := {}
	var bad := []
	var dup := 0
	for i in 400:
		var a := str(ids[rng.randi_range(0, ids.size() - 1)])
		var b := str(ids[rng.randi_range(0, ids.size() - 1)])
		if a == b:
			continue
		var n := Prog.fusion_name(str(Data.monster(a).name), str(Data.monster(b).name), seen)
		if n == "" or bible.has(n.to_lower()) or Prog.name_problem(n, {}) != "":
			bad.append("%s+%s=%s" % [a, b, n])
		if seen.has(n.to_lower()):
			dup += 1
		seen[n.to_lower()] = true
	eq(bad, [], "400 generated fusion names: none empty, bible or reserved")
	eq(dup, 0, "generated names stay unique when earlier ones are taken")
	eq(Prog.fusion_name("Fangstaga", "Jadescorpionis"), Prog.fusion_name("Fangstaga", "Jadescorpionis"), "name generation is deterministic")


func test_battle_use() -> void:
	print("[owned monsters in battle]")
	var pr := Progress.new(SAVE)
	pr.new_game()
	var uid: String = pr.squad[0]
	var inst := pr.get_inst(uid)
	inst.level = 20
	var s := GameState.new()
	s.setup("T01-L02", pr.squad, -1, pr.squad_records())
	var u := s.place_unit(GameState.PLAYER, uid, Vector2i(5, 5))
	eq(u.max_hp, Prog.stats(inst).hp, "battle uses the levelled stats (Lv20)")
	eq(u.level, 20, "unit knows its level")
	# fused unit with secondary affinity
	var a := _lv("OWN-0090", "MON-0177", 15)   # Water
	var b := _lv("OWN-0091", "MON-0188", 12)   # Fire
	var f := Prog.fusion_preview(a, b, "OWN-0092")
	var s2 := GameState.new()
	s2.setup("T01-L02", [], -1, {"OWN-0092": Prog.battle_record(f)})
	var fu := s2.place_unit(GameState.PLAYER, "OWN-0092", Vector2i(4, 4))
	eq(fu.secondary_family, "Fire", "fused unit carries Fire affinity")
	var tgt := ""
	for id in Data.monster_ids():
		if Data.monster(id).element_family == "Wind":  # Fire beats Wind; Water vs Wind neutral
			tgt = id
			break
	var e := s2.place_unit(GameState.ENEMY, tgt, Vector2i(5, 4))
	var with_aff := s2.damage_preview(fu, e.pos)
	fu.secondary_family = ""
	eq(with_aff, maxi(1, roundi(float(GameState.compute_damage(fu.attack, e.defense, fu.family, e.family)) * 1.1)) if with_aff != s2.damage_preview(fu, e.pos) else with_aff, "secondary affinity x1.1 vs the ring it beats")
	check(with_aff > s2.damage_preview(fu, e.pos), "affinity raises damage (%d > %d)" % [with_aff, s2.damage_preview(fu, e.pos)])
	# XP award after a battle
	var s3 := GameState.new()
	s3.setup("T03-L01", pr.squad, -1, pr.squad_records())
	s3.reserve[GameState.PLAYER] = pr.squad.duplicate()
	var first: String = pr.squad[0]
	s3.deploy(GameState.PLAYER, first, s3.deploy_tiles(GameState.PLAYER)[0])
	s3.ko_by[first] = 2
	var lvl0 := int(pr.get_inst(first).level)
	var res := pr.award_battle(s3, true)
	eq(res.keys(), [first], "only summoned squad monsters earn XP")
	eq(res[first].xp, Prog.battle_xp(2, true, 3), "XP = participation + 2 KOs, win, T03")
	check(int(pr.get_inst(first).level) >= lvl0, "level kept or raised")


func test_save_load() -> void:
	print("[save/load with evolved and fused monsters]")
	_rm()
	var pr := Progress.new(SAVE)
	eq(pr.load_note, "new", "no save: new game")
	var u0: String = pr.roster[0].uid
	var u1: String = pr.roster[1].uid
	var u2: String = pr.roster[2].uid
	pr.get_inst(u0).level = 16
	check(pr.evolve(u0) != "", "evolve via progress")
	pr.get_inst(u1).level = 12
	pr.get_inst(u2).level = 14
	var prev := pr.fusion_preview(u1, u2)
	check(not prev.has("error"), "preview before confirming")
	var n_before := pr.roster.size()
	var fused := pr.fuse(u1, u2)
	eq(fused.name, prev.name, "confirmed fusion matches its preview")
	eq(pr.roster.size(), n_before - 1, "both parents consumed, one fused monster added")
	check(pr.get_inst(u1).is_empty() and pr.get_inst(u2).is_empty(), "parents gone")
	eq(pr.fuse(u1, u2).get("error", ""), "pick_two_monsters", "fusing consumed monsters is rejected")
	var squad := [fused.uid, u0, pr.roster[3].uid, pr.roster[4].uid]
	check(pr.set_squad(squad), "fused monster can join the squad")
	pr.save()
	var again := Progress.new(SAVE)
	eq(again.load_note, "loaded", "v2 save loads")
	eq(again.get_inst(u0).evo_stage, 1, "evolved form persists")
	eq(again.get_inst(u0).name, pr.get_inst(u0).name, "evolved name persists")
	eq(JSON.stringify(again.get_inst(fused.uid)), JSON.stringify(fused), "fused monster persists exactly")
	eq(again.squad, squad, "squad with the fused monster persists")
	eq(JSON.stringify(Prog.battle_record(again.get_inst(fused.uid))), JSON.stringify(Prog.battle_record(fused)), "same battle stats after reload")


func test_migration() -> void:
	print("[save migration v1 -> v2, corrupt save]")
	_rm()
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"unlocked": 5, "cleared": {"T01-L01": true}, "squad": ["MON-0033", "MON-0640", "MON-0077", "MON-0596"]}))
	f.close()
	var pr := Progress.new(SAVE)
	eq(pr.load_note, "migrated_from_v1", "v1 save migrated")
	eq(pr.unlocked, 5, "unlocks kept")
	check(pr.cleared.has("T01-L01"), "cleared stages kept")
	var ids := pr.squad.map(func(u): return pr.get_inst(u).base_id)
	eq(ids, ["MON-0033", "MON-0640", "MON-0077", "MON-0596"], "v1 squad (monster ids) mapped to owned uids")
	eq(pr.roster.size(), Data.squad_collection().size(), "roster created for the v1 player")
	pr.save()
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	eq(int(d.version), 3, "re-saved as the current schema (v3)")
	var f2 := FileAccess.open(SAVE, FileAccess.WRITE)
	f2.store_string("{not json")
	f2.close()
	var bad := Progress.new(SAVE)
	check(bad.load_note == "corrupt_reset" and bad.roster.size() == Data.squad_collection().size() and bad.unlocked == 1, "corrupt save -> new game, no crash")
