## Widgets for the squad / draft / evolution / fusion screens: the 6-slot squad strip, the Bond
## total-vs-cap bar, a roster card grid, the evolution path row and the fusion stage
## (A + B -> animated result card). Pure presentation: ui.gd keeps the picks and the rules.
extends RefCounted

const Palette = preload("res://scripts/theme_colors.gd")
const UIArt = preload("res://scripts/ui_art.gd")
const Data = preload("res://scripts/data_loader.gd")
const Prog = preload("res://scripts/progression.gd")
const Summon = preload("res://scripts/summon.gd")
const Kit = preload("res://scripts/ui/menu_kit.gd")
const MonsterCard = preload("res://scripts/ui/monster_card.gd")


## Grid for compact cards: 4 columns at 1080 (3 when narrower), centred in a scroll.
static func card_grid(parent: Control) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 16)
	center.add_child(g)
	return g


## Empty slot: dashed chamfer with its number.
class EmptySlot extends Control:
	const K = preload("res://scripts/ui/menu_kit.gd")
	const MC = preload("res://scripts/ui/monster_card.gd")
	var idx := 1

	func _draw() -> void:
		var r := Rect2(Vector2(4, 4), size - Vector2(8, 8))
		var pts := MC.cham(r, 10.0)
		pts.append(pts[0])
		for i in pts.size() - 1:   # dashed edge
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var n := int(a.distance_to(b) / 14.0)
			for j in n:
				if j % 2 == 0:
					draw_line(a.lerp(b, float(j) / n), a.lerp(b, float(j + 1) / n), Color(K.GOLD, 0.45), 2.0, true)
		K.centered_text(self, size * 0.5, str(idx), int(size.x * 0.32), Color(K.SILVER, 0.35), true, 0)


## The squad strip: n slots, filled with MINI cards for the picks (in pick order).
class SlotStrip extends HBoxContainer:
	const MC = preload("res://scripts/ui/monster_card.gd")
	const SW = preload("res://scripts/ui/squad_widgets.gd")
	var slots := 6
	var cards: Array = []
	var on_slot: Callable        ## (uid) -> tapping a filled slot (e.g. remove it)

	func _init(n: int = 6) -> void:
		slots = n
		alignment = BoxContainer.ALIGNMENT_CENTER
		add_theme_constant_override("separation", 10)

	## insts: the picked instances (<= slots).
	func set_items(insts: Array) -> void:
		for c in get_children():
			remove_child(c)
			c.queue_free()
		cards = []
		for i in slots:
			if i < insts.size():
				var card := MC.new()
				card.setup_inst(insts[i], MC.Variant.MINI)
				card.toggle_mode = false
				var u := str(insts[i].uid)
				card.on_tap(func(): if on_slot.is_valid(): on_slot.call(u))
				add_child(card)
				cards.append(card)
			else:
				var e := SW.EmptySlot.new()
				e.idx = i + 1
				e.custom_minimum_size = MC.SIZES[MC.Variant.MINI]
				e.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(e)


## Bond total vs the tower's cap: cyan fill, gold at the cap, ember when a pick would exceed it.
class BondBar extends Control:
	const K = preload("res://scripts/ui/menu_kit.gd")
	const UIA = preload("res://scripts/ui_art.gd")
	const S = preload("res://scripts/summon.gd")
	var total := 0
	var cap := 60
	var count := 0
	var slots := 6

	func set_values(p_total: int, p_cap: int, p_count: int, p_slots: int) -> void:
		total = p_total
		cap = maxi(1, p_cap)
		count = p_count
		slots = p_slots
		queue_redraw()

	func _draw() -> void:
		var over := total > cap
		var bar := Rect2(Vector2(0, size.y * 0.52), Vector2(size.x, size.y * 0.4))
		draw_rect(bar, Color(K.N.lerp(K.SILVER, 0.12), 0.95))
		var frac := clampf(float(total) / float(cap), 0.0, 1.0)
		var col: Color = K.EMBER if over else (K.GOLD if total == cap else K.CYAN)
		UIA.vgrad(self, Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), col.lightened(0.3), col.darkened(0.2))
		for t in range(10, cap, 10):   # ticks every 10 Bond
			var x := bar.position.x + bar.size.x * t / float(cap)
			draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(K.N, 0.6), 2.0)
		draw_rect(bar, Color(K.GOLD, 0.7), false, 2.0)
		var f := UIA.font(true, 700)
		var fs := int(size.y * 0.36)
		var left := "%s  %d / %d" % [S.term("bond").to_upper(), total, cap]
		draw_string_outline(f, Vector2(0, size.y * 0.42), left, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, K.N)
		draw_string(f, Vector2(0, size.y * 0.42), left, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col.lightened(0.2))
		var right := "%s  %d / %d" % [S.term("vessels").to_upper(), count, slots]
		draw_string_outline(f, Vector2(0, size.y * 0.42), right, HORIZONTAL_ALIGNMENT_RIGHT, size.x, fs, 5, K.N)
		draw_string(f, Vector2(0, size.y * 0.42), right, HORIZONTAL_ALIGNMENT_RIGHT, size.x, fs, K.SILVER)


## One evolution screen row: the owned card, its path (current -> next forms with levels), the
## requirement line and the Evolve button. Returns [row, evolve_button].
static func evolution_row(inst: Dictionary, why: String, req: String, on_evolve: Callable, on_hold: Callable) -> Array:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UIArt.panel_style(Palette.SIGIL_GOLD if why == Prog.OK else Palette.panel_edge(), 0.9))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	row.add_child(h)
	var card := MonsterCard.new()
	card.setup_inst(inst, MonsterCard.Variant.COMPACT)
	card.toggle_mode = false
	card.show_costs = false
	card.on_tap(on_hold.bind(card))
	card.long_pressed.connect(on_hold)
	h.add_child(card)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	h.add_child(v)
	var nm := Kit.label("%s  Lv %d / %d" % [inst.name, int(inst.level), Prog.level_cap(inst)], 30, Palette.SIGIL_GOLD.lerp(Color.WHITE, 0.2), true)
	v.add_child(nm)
	var path := HBoxContainer.new()
	path.add_theme_constant_override("separation", 4)
	v.add_child(path)
	var line := [] if Prog.is_fused(inst) else MonsterCard.evolution_line(str(inst.base_id))
	var lv := MonsterCard.line_levels()
	var stage := int(inst.get("evo_stage", 0))
	for i in line.size():
		if i > 0:
			var arrow := Kit.label(">", 34, Palette.SIGIL_GOLD if i <= stage + 1 else Palette.SOFT_SILVER.darkened(0.4), true, HORIZONTAL_ALIGNMENT_CENTER)
			arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			path.add_child(arrow)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := MonsterCard.new()
		m.setup_form(str(inst.base_id), str(line[i]), i, MonsterCard.Variant.MINI)
		m.locked = i > stage
		m.show_level = false
		m.custom_minimum_size = Vector2(118, 154)
		m.toggle_mode = true
		m.set_pressed_no_signal(i == stage)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(m)
		col.add_child(Kit.label("Lv %d" % int(lv[mini(i, lv.size() - 1)]), 20, Palette.SIGIL_GOLD if i <= stage else Palette.SOFT_SILVER.darkened(0.3), true, HORIZONTAL_ALIGNMENT_CENTER))
		path.add_child(col)
	v.add_child(Kit.label(req, 24, Palette.AETHER_CYAN if why == Prog.OK else Palette.SOFT_SILVER.darkened(0.15)))
	var b := Kit.button("Evolve" if why == Prog.OK else "Evolve  (%s)" % why.replace("_", " "), on_evolve, 92, Palette.SIGIL_GOLD, "evolve_build" if why == Prog.OK else "ui_locked")
	b.disabled = why != Prog.OK
	v.add_child(b)
	return [row, b]


## Fusion stage: [A] + [B] = [result]; the result card pops in (scale + flash) when it changes.
class FusionStage extends HBoxContainer:
	const MC = preload("res://scripts/ui/monster_card.gd")
	const SW = preload("res://scripts/ui/squad_widgets.gd")
	const K = preload("res://scripts/ui/menu_kit.gd")
	const Pal = preload("res://scripts/theme_colors.gd")
	var slot_a: Control
	var slot_b: Control
	var result_holder: CenterContainer
	var result_card: Button
	var _last_key := ""

	func _init() -> void:
		alignment = BoxContainer.ALIGNMENT_CENTER
		add_theme_constant_override("separation", 6)
		slot_a = _holder()
		add_child(slot_a)
		add_child(_sym("+"))
		slot_b = _holder()
		add_child(slot_b)
		add_child(_sym("="))
		result_holder = CenterContainer.new()
		result_holder.custom_minimum_size = Vector2(300, 420)
		add_child(result_holder)

	func _holder() -> CenterContainer:
		var c := CenterContainer.new()
		c.custom_minimum_size = Vector2(236, 330)
		return c

	func _sym(t: String) -> Label:
		var l := K.label(t, 64, Pal.SIGIL_GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.custom_minimum_size.x = 44
		return l

	func _fill(holder: Control, inst: Dictionary, size: Vector2, empty_idx: int) -> Button:
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
		if inst.is_empty():
			var e := SW.EmptySlot.new()
			e.idx = empty_idx
			e.custom_minimum_size = size
			e.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(e)
			return null
		var card := MC.new()
		card.setup_inst(inst, MC.Variant.COMPACT)
		card.custom_minimum_size = size
		card.toggle_mode = false
		card.show_costs = false
		holder.add_child(card)
		return card

	## a, b: picked instances ({} = empty); res: fusion preview ({} or with "error" = no result).
	func show_pick(a: Dictionary, b: Dictionary, res: Dictionary) -> void:
		_fill(slot_a, a, Vector2(236, 330), 1)
		_fill(slot_b, b, Vector2(236, 330), 2)
		var ok := not res.is_empty() and not res.has("error")
		result_card = _fill(result_holder, res if ok else {}, Vector2(300, 420), 3)
		var key := str(res.get("name", "")) if ok else ""
		if ok and key != _last_key and K.motion() and is_inside_tree():
			result_card.pivot_offset = Vector2(150, 210)
			result_card.scale = Vector2.ONE * 0.55
			result_card.modulate = Color(2.2, 2.0, 2.6, 0.0)
			var tw := result_card.create_tween().set_parallel(true)
			tw.tween_property(result_card, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(result_card, "modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_CUBIC)
			K.sfx(self, "ui_confirm")
		_last_key = key
