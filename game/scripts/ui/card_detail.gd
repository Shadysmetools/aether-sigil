## Card detail overlay: the FULL monster card (tap to flip to its lore side), its evolution line
## (every form with the level it is reached at) and the fusion recipes that use it. Opens over any
## meta screen; tap the dimmed backdrop or Close to dismiss.
extends Control

const Palette = preload("res://scripts/theme_colors.gd")
const Data = preload("res://scripts/data_loader.gd")
const Kit = preload("res://scripts/ui/menu_kit.gd")
const MonsterCard = preload("res://scripts/ui/monster_card.gd")

signal closed

var card: Button              ## the FULL MonsterCard on show
var strip: HBoxContainer      ## evolution line (MINI cards)
var recipes_label: Label
var _box: VBoxContainer


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(Palette.MIDNIGHT_NAVY, 0.9)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_box)


func open_inst(inst: Dictionary) -> void:
	_open(func(c): c.setup_inst(inst, MonsterCard.Variant.FULL), str(inst.get("base_id", "")), int(inst.get("evo_stage", 0)), bool(inst.get("fused", false)))


func open_bible(id: String, owned: bool = true) -> void:
	_open(func(c): c.setup_bible(id, MonsterCard.Variant.FULL, owned), id, 0, false)


## Opens on whatever a MonsterCard shows (long-press from any grid).
func open_card(src: Button) -> void:
	if not src.inst.is_empty():
		open_inst(src.inst)
	else:
		open_bible(src.mon_id, not src.locked)


func _open(setup: Callable, line_id: String, stage: int, fused: bool) -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	card = MonsterCard.new()
	setup.call(card)
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1080, 1920)
	var cw := clampf(minf(vp.x - 64.0, (vp.y - 760.0) * 0.75), 420.0, 720.0)
	card.custom_minimum_size = Vector2(cw, cw * 4.0 / 3.0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.toggle_mode = false
	card.on_tap(card.flip)
	_box.add_child(card)
	var hint := Kit.label("Tap the card to turn it over", 22, Palette.SOFT_SILVER.darkened(0.3), false, HORIZONTAL_ALIGNMENT_CENTER)
	_box.add_child(hint)
	# evolution line
	var hdr := Kit.header("EVOLUTION LINE" if not fused else "FUSED FORM", 26)
	hdr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.add_child(hdr)
	strip = HBoxContainer.new()
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 8)
	_box.add_child(strip)
	var line := [] if fused else MonsterCard.evolution_line(line_id)
	var lv := MonsterCard.line_levels()
	for i in line.size():
		if i > 0:
			var arrow := Kit.label(">", 40, Palette.SIGIL_GOLD, true, HORIZONTAL_ALIGNMENT_CENTER)
			arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			strip.add_child(arrow)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var chipc := MonsterCard.new()
		chipc.setup_form(line_id, str(line[i]), i, MonsterCard.Variant.MINI)
		chipc.show_level = false
		chipc.show_costs = false
		chipc.toggle_mode = true
		chipc.set_pressed_no_signal(i == stage)
		chipc.disabled = false
		chipc.on_tap(func(): chipc.set_pressed_no_signal(i == stage))
		col.add_child(chipc)
		col.add_child(Kit.label("Lv %d" % int(lv[mini_index(i, lv)]), 22, Palette.SIGIL_GOLD if i <= stage else Palette.SOFT_SILVER.darkened(0.2), true, HORIZONTAL_ALIGNMENT_CENTER))
		strip.add_child(col)
	if fused:
		strip.add_child(Kit.label("Fused monsters do not evolve.", 24, Palette.SOFT_SILVER, false, HORIZONTAL_ALIGNMENT_CENTER))
	# fusion recipes
	var recs := MonsterCard.recipes_for(line_id)
	var lines := []
	for r in recs:
		lines.append("%s + %s  ->  %s (%s)" % [Data.monster(str(r.parents[0])).get("name", "?"), Data.monster(str(r.parents[1])).get("name", "?"), r.name, r.get("element_family", "")])
	var F: Dictionary = Data.progression().fusion
	recipes_label = Kit.label("FUSION RECIPES\n" + ("\n".join(lines) if not lines.is_empty() else "No named recipe. Fuse any two Lv%d+ monsters for a new form one rarity higher." % int(F.min_level)),
		24, Palette.CRYSTAL_VIOLET.lightened(0.45), false, HORIZONTAL_ALIGNMENT_CENTER)
	recipes_label.custom_minimum_size = Vector2(minf(vp.x - 80.0, 900.0), 0)
	_box.add_child(recipes_label)
	var close_b := Kit.button("Close", close, 96, Palette.SOFT_SILVER, "ui_back")
	close_b.custom_minimum_size.x = 360
	close_b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.add_child(close_b)
	visible = true
	Kit.enter(self, 0.0, 0.2)
	if Kit.motion() and is_inside_tree():
		card.scale = Vector2.ONE * 0.86
		card.pivot_offset = card.custom_minimum_size * 0.5
		card.create_tween().tween_property(card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func mini_index(i: int, lv: Array) -> int:
	return mini(i, lv.size() - 1)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()
