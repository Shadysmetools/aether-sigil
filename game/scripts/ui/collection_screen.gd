## Collection / Monster Compendium: all 1,000 bible monsters as compact cards, filtered by element
## family (chips), rarity, role, search text and "owned only", sorted (No. / Name / Rarity / Power /
## Element), paged (PAGE cards at a time so the grid stays light). Tap a card for its detail
## (card_detail.gd). Filtering is collection_model.gd (pure, tested).
extends Control

const Palette = preload("res://scripts/theme_colors.gd")
const Data = preload("res://scripts/data_loader.gd")
const Assets = preload("res://scripts/assets.gd")
const Kit = preload("res://scripts/ui/menu_kit.gd")
const Model = preload("res://scripts/ui/collection_model.gd")
const MonsterCard = preload("res://scripts/ui/monster_card.gd")

const PAGE := 24

var progress: RefCounted
var on_back: Callable
var on_open: Callable               ## (id: String, owned: bool) -> detail overlay
var filters := {"family": "", "rarity": "", "role": "", "search": "", "owned_only": false, "sort": "number"}
var results: Array = []             ## ids after filter + sort
var page := 0
var grid: GridContainer
var cards: Array = []               ## MonsterCards on this page
var count_label: Label
var page_label: Label
var search: LineEdit
var family_chips: Dictionary = {}   ## family ("" = all) -> Button
var rarity_menu: OptionButton
var role_menu: OptionButton
var sort_menu: OptionButton
var owned_chip: Button
var prev_b: Button
var next_b: Button
var _owned: Dictionary = {}
var _scroll: ScrollContainer


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func build() -> void:
	var scrim := ColorRect.new()   # navy scrim over the sky art
	scrim.color = Color(Palette.MIDNIGHT_NAVY, 0.86)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 28)
	m.add_theme_constant_override("margin_top", 28)
	m.add_theme_constant_override("margin_bottom", 28)
	add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	m.add_child(vb)
	vb.add_child(Kit.title_block("MONSTER COMPENDIUM", ""))
	count_label = Kit.label("", 28, Palette.AETHER_CYAN, true, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(count_label)
	# search + owned
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 12)
	vb.add_child(srow)
	search = LineEdit.new()
	search.placeholder_text = "Search name, element or skill"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.clear_button_enabled = true
	Kit.style_field(search)
	search.text_changed.connect(func(t): set_filter("search", t))
	srow.add_child(search)
	owned_chip = Kit.chip("Owned", true, 180)
	owned_chip.toggled.connect(func(on): set_filter("owned_only", on))
	srow.add_child(owned_chip)
	# element family chips (All + 12)
	var fam_grid := GridContainer.new()
	fam_grid.columns = 7
	fam_grid.add_theme_constant_override("h_separation", 8)
	fam_grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(fam_grid)
	for fam in [""] + Assets.ELEMENT_FAMILIES:
		var c := Kit.chip("ALL" if fam == "" else "", true)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.tooltip_text = "All elements" if fam == "" else fam
		if fam != "":
			var g := Kit.Glyph.new("element:" + fam)
			g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			g.offset_left = 14
			g.offset_right = -14
			g.offset_top = 14
			g.offset_bottom = -14
			c.add_child(g)
		c.pressed.connect(func(): set_filter("family", fam))
		family_chips[fam] = c
		fam_grid.add_child(c)
	# rarity / role / sort
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 10)
	vb.add_child(mrow)
	rarity_menu = _menu(mrow, ["All rarities"] + Kit.rarities(), func(i): set_filter("rarity", "" if i == 0 else Kit.rarities()[i - 1]))
	var roles := Model.values_of("role")
	role_menu = _menu(mrow, ["All roles"] + roles, func(i): set_filter("role", "" if i == 0 else roles[i - 1]))
	sort_menu = _menu(mrow, Model.SORTS.map(func(s): return "Sort: " + Model.SORT_LABELS[s]), func(i): set_filter("sort", Model.SORTS[i]))
	# grid
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(_scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(center)
	grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 16)
	center.add_child(grid)
	# pager + back
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 12)
	vb.add_child(prow)
	prev_b = Kit.button("Prev", func(): go_page(page - 1), 96, Palette.SOFT_SILVER, "ui_page")
	prev_b.size_flags_stretch_ratio = 0.6
	prow.add_child(prev_b)
	page_label = Kit.label("", 26, Palette.SOFT_SILVER, true, HORIZONTAL_ALIGNMENT_CENTER)
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prow.add_child(page_label)
	next_b = Kit.button("Next", func(): go_page(page + 1), 96, Palette.SOFT_SILVER, "ui_page")
	next_b.size_flags_stretch_ratio = 0.6
	prow.add_child(next_b)
	vb.add_child(Kit.button("Back", func(): if on_back.is_valid(): on_back.call(), 100, Palette.SOFT_SILVER, "ui_back"))


func _menu(parent: Control, items: Array, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.clip_text = true
	o.fit_to_longest_item = false
	Kit.style_field(o)
	o.item_selected.connect(cb)
	o.item_selected.connect(func(_i): Kit.sfx(self, "ui_page"))
	parent.add_child(o)
	return o


## Called when the screen opens: recount the collection, keep the filters, rebuild page 0.
func open() -> void:
	_owned = Model.collected(progress.roster) if progress != null else {}
	page = 0
	apply()


func set_filter(key: String, value: Variant) -> void:
	filters[key] = value
	page = 0
	apply()


## Re-runs the query and shows the current page.
func apply() -> void:
	results = Model.query(filters, _owned)
	for fam in family_chips:
		family_chips[fam].set_pressed_no_signal(str(filters.family) == fam)
	owned_chip.set_pressed_no_signal(bool(filters.owned_only))
	count_label.text = "Collected %d / %d   -   %d shown" % [_owned.size(), Data.monster_ids().size(), results.size()]
	go_page(page)


func pages() -> int:
	return maxi(1, ceili(results.size() / float(PAGE)))


func go_page(p: int) -> void:
	page = clampi(p, 0, pages() - 1)
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	cards = []
	for id in results.slice(page * PAGE, (page + 1) * PAGE):
		var card := MonsterCard.new()
		card.setup_bible(str(id), MonsterCard.Variant.COMPACT, _owned.has(id))
		card.toggle_mode = false
		card.show_costs = true
		card.on_tap(_open.bind(str(id)))
		card.long_pressed.connect(func(_c): _open(str(id)))
		grid.add_child(card)
		cards.append(card)
	page_label.text = "Page %d / %d" % [page + 1, pages()] if not results.is_empty() else "No monsters match"
	prev_b.disabled = page <= 0
	next_b.disabled = page >= pages() - 1
	if _scroll != null:
		_scroll.scroll_vertical = 0
	if is_inside_tree():
		Kit.stagger(cards, 0.012, 0.0)


func _open(id: String) -> void:
	if on_open.is_valid():
		on_open.call(id, _owned.has(id))
