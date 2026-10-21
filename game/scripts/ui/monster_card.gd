## MonsterCard: the reusable monster card (compendium sheet look). One Button that paints itself:
##   FULL (3:4 detail card)  art window, name plate, rarity diamonds, element + role badges, Bond and
##                           SP badges, level + XP, five stat bars, skill, evolution pips; flips to a
##                           back face (lore, exact stats, costs) with `flipped`.
##   COMPACT (grid card)     art, name plate, rarity, element/role, Lv, evolution pips, cost badges.
##   MINI (chip)             art, name, Lv (slot strips, evolution lines, recipes).
## Rarity escalates the frame Common -> Legendary (metal colour, border weight, gems, crest), Rare+
## get an animated shine and Epic+ a foil sweep (card_foil.gdshader, driven by TIME, no per-frame
## script), Legendary a pulsing gold aura. States: locked (not collected), unaffordable (over the
## Bond cap), selected (= button_pressed), disabled. Works with painted art (assets.gd) or the
## procedural fallback (element gradient + role silhouette). Hold for `long_pressed` (details).
## Usage: var c := MonsterCard.new(); c.setup_inst(inst, MonsterCard.Variant.COMPACT); c.on_tap(cb)
extends Button

signal long_pressed(card: Button)

const Palette = preload("res://scripts/theme_colors.gd")
const Assets = preload("res://scripts/assets.gd")
const Data = preload("res://scripts/data_loader.gd")
const Prog = preload("res://scripts/progression.gd")
const Summon = preload("res://scripts/summon.gd")
const UIArt = preload("res://scripts/ui_art.gd")
const Kit = preload("res://scripts/ui/menu_kit.gd")
const FOIL = preload("res://scripts/ui/card_foil.gdshader")

enum Variant { FULL, COMPACT, MINI }

const SIZES := {Variant.FULL: Vector2(720, 960), Variant.COMPACT: Vector2(236, 330), Variant.MINI: Vector2(150, 196)}
const LONG_PRESS := 0.45
const STAT_KEYS := ["attack", "defense", "hp", "move", "range"]
const STAT_LABEL := {"attack": "ATK", "defense": "DEF", "hp": "HP", "move": "MOVE", "range": "RANGE"}
const STAT_COLOR := {"attack": Palette.EMBER, "defense": Palette.SIGIL_GOLD, "hp": Palette.VERDANT_GREEN, "move": Palette.AETHER_CYAN, "range": Palette.CRYSTAL_VIOLET}
## Stat bars are relative to the strongest bible monster at this level (display scale, not a rule).
const STAT_REF_LEVEL := 25
## UI copy (no per-monster lore exists in the bible): one line per role.
const ROLE_LORE := {
	"Guardian": "Holds the line for its Sigil and takes the blows meant for others.",
	"Striker": "Charges in first and hits hardest the moment a gap opens.",
	"Assassin": "Waits in the blind spots, then ends a threat before it can act.",
	"Artillery": "Strikes from afar; keep it behind a wall of allies.",
	"Scout": "Swift and sharp-eyed, it claims capsule nodes before rivals can.",
	"Support": "Mends and shields its companions through the longest fights.",
	"Summoner": "Bends the aether to call allies and reshape the field.",
	"Controller": "Pins foes in place and turns the board against them.",
}

const N := Palette.MIDNIGHT_NAVY
const GOLD := Palette.SIGIL_GOLD
const CYAN := Palette.AETHER_CYAN
const SILVER := Palette.SOFT_SILVER

var variant: int = Variant.COMPACT
var rec: Dictionary = {}       ## battle-record shape (bible monster or Prog.battle_record)
var inst: Dictionary = {}      ## owned instance, {} for a compendium entry
var mon_id := ""               ## bible id of the line (base_id for an instance)
var art_id := ""               ## Assets.monster key (current form)
var uid := ""
var locked := false            ## not collected yet
var unaffordable := false      ## over the draft's Bond cap
var show_costs := true         ## Bond + SP badges
var show_level := true         ## Lv tag (compendium entries show their number instead)
var block_tag := ""            ## why this card can't be picked ("NEEDS LV10"); dims it
var flipped := false           ## FULL: back face
var model: Dictionary = {}
var draws := 0                 ## times painted (tests: the card really renders)

var _foil: ColorRect
var _aura: Control
var _tap_cb: Callable
var _press_id := 0
var _swallow := false
var _hover := false
var _hover_x := 0.5
var _tex: Texture2D
var _tex_done := false

static var _stat_max: Dictionary = {}
static var _ability_desc: Dictionary = {}


# ---------------------------------------------------------------- setup

## Owned monster instance (progress.roster entry).
func setup_inst(p_inst: Dictionary, v: int = Variant.COMPACT) -> Button:
	inst = p_inst
	uid = str(inst.get("uid", ""))
	rec = Prog.battle_record(inst)
	mon_id = str(inst.get("base_id", ""))
	art_id = str(inst.get("form_id", mon_id))
	if Prog.is_fused(inst):
		art_id = str(inst.get("parents", [""])[0])  # a fusion wears its primary parent's art, tinted by its family
	return _apply(v)


## Bible monster (compendium). owned = collected (else the card is locked).
func setup_bible(id: String, v: int = Variant.COMPACT, owned: bool = true) -> Button:
	inst = {}
	uid = ""
	var m := Data.monster(id)
	rec = m.duplicate()
	rec["level"] = 1
	rec["evo_stage"] = 0
	mon_id = id
	art_id = id
	locked = not owned
	return _apply(v)


## One form of a line as the line's founder would become it: the founder's element, role and
## stats (evolution keeps them), the form's name and art, at the level the form is reached.
func setup_form(founder_id: String, form_id: String, stage: int, v: int = Variant.MINI) -> Button:
	inst = {}
	uid = ""
	rec = Data.monster(founder_id).duplicate()
	rec["name"] = str(Data.monster(form_id).get("name", form_id))
	rec["evo_stage"] = stage
	rec["level"] = int(line_levels()[mini(stage, line_levels().size() - 1)])
	rec["_form_of"] = founder_id
	mon_id = founder_id
	art_id = form_id
	locked = false
	return _apply(v)


## Taps call cb (a hold opens details instead and the tap is swallowed).
func on_tap(cb: Callable) -> Button:
	_tap_cb = cb
	return self


func _apply(v: int) -> Button:
	variant = v
	model = compute_model(rec, inst, mon_id)
	text = ""
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = SIZES[v]
	size = SIZES[v]
	tooltip_text = ""
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(st, empty)
	_tex_done = false
	_build_fx()
	queue_redraw()
	return self


func _ready() -> void:
	resized.connect(_on_resized)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	pressed.connect(_on_pressed)
	toggled.connect(func(_on): queue_redraw())
	_on_resized()
	_start_aura()


# ---------------------------------------------------------------- model (pure, tested)

## Everything the card shows, derived from data: tier, costs, stat fractions, XP, evolution line.
static func compute_model(r: Dictionary, p_inst: Dictionary = {}, line_id: String = "") -> Dictionary:
	var rarity := str(r.get("rarity", "Common"))
	var tier := Kit.tier_of(rarity)
	var fused := bool(r.get("fused", false))
	var lvl := int(r.get("level", 1))
	var xp_frac := 0.0
	if not p_inst.is_empty():
		var cap := Prog.level_cap(p_inst)
		xp_frac = 1.0 if lvl >= cap else clampf(float(p_inst.get("xp", 0)) / float(Prog.xp_to_next(lvl)), 0.0, 1.0)
	var line := [] if fused else evolution_line(line_id if line_id != "" else str(r.get("id", "")))
	var fracs := {}
	var mx := stat_max()
	for k in STAT_KEYS:
		fracs[k] = clampf(float(r.get(k, 0)) / float(mx[k]), 0.04, 1.0)
	return {
		"name": str(r.get("name", "?")), "rarity": rarity, "tier": tier, "stars": tier + 1,
		"family": str(r.get("element_family", "")), "element": str(r.get("element", "")), "role": str(r.get("role", "")),
		"level": lvl, "level_cap": int(r.get("level_cap", 50)), "xp_frac": xp_frac,
		"evo_stage": int(r.get("evo_stage", 0)), "evo_forms": line.size(), "line": line, "fused": fused,
		"bond": Summon.bond(r), "sp": Summon.crack_cost(r), "vessel_hp": Summon.vessel_hp(r),
		"stats": STAT_KEYS.map(func(k): return int(r.get(k, 0))), "fracs": fracs,
		"ability": str(r.get("ability", "")), "ability_desc": ability_description(str(r.get("ability", ""))),
		"frame": Kit.rarity_color(tier), "gems": [0, 1, 2, 4, 4, 6][clampi(tier, 0, 5)], "crest": tier >= 4,
		"shine": tier >= 2, "foil": tier >= 3, "aura": tier >= 5,
		"secondary_family": str(r.get("secondary_family", "")), "secondary_ability": str(r.get("secondary_ability", "")),
	}


## The 3-form line a monster evolves along: itself + the next members of its evolution_family
## (one per progression.json threshold), clipped at the family's end.
static func evolution_line(id: String) -> Array:
	if not Data.has_monster(id):
		return []
	var members := Data.family_members(str(Data.monster(id).get("evolution_family", "")))
	var i := members.find(id)
	if i < 0:
		return [id]
	return members.slice(i, mini(members.size(), i + 1 + Array(Data.progression().evolution.thresholds).size()))


## Level each form of a line is reached at: [1, 16, 36] from data.
static func line_levels() -> Array:
	return [1] + Array(Data.progression().evolution.thresholds).map(func(x): return int(x))


## Fusion recipes (progression.json) that use this monster as a parent.
static func recipes_for(id: String) -> Array:
	return Array(Data.progression().fusion.recipes).filter(func(r): return Array(r.parents).has(id))


## The bible's description for an ability name (first monster that carries it).
static func ability_description(ability: String) -> String:
	if _ability_desc.is_empty():
		for m in Data.bible().get("monsters", []):
			if not _ability_desc.has(str(m.ability)):
				_ability_desc[str(m.ability)] = str(m.get("ability_description", ""))
	return str(_ability_desc.get(ability, ""))


## Card lore: no per-monster lore exists in the data, so a templated element/role line.
static func lore(m: Dictionary) -> String:
	var fam := str(m.family)
	return "A %s %s of the %s line, born of %s aether. %s" % [str(m.rarity).to_lower(), str(m.role).to_lower(), fam, str(m.element).to_lower(),
		ROLE_LORE.get(str(m.role), "")]


## Bar scale per stat: the bible's best at STAT_REF_LEVEL (move/range: the bible max).
static func stat_max() -> Dictionary:
	if _stat_max.is_empty():
		var G: Dictionary = Data.progression().growth_pct_per_level
		for k in STAT_KEYS:
			var best := 1.0
			for m in Data.bible().get("monsters", []):
				best = maxf(best, float(m.get(k, 0)))
			if G.has(k):
				best *= 1.0 + float(G[k]) / 100.0 * (STAT_REF_LEVEL - 1)
			_stat_max[k] = best
	return _stat_max


# ---------------------------------------------------------------- input + motion

func _on_resized() -> void:
	pivot_offset = size * 0.5
	if _foil != null:
		var a := art_rect()
		_foil.position = a.position
		_foil.size = a.size


func _on_hover(on: bool) -> void:
	_hover = on
	z_index = 2 if on else 0
	if not Kit.motion() or variant == Variant.MINI:
		return
	create_tween().tween_property(self, "scale", Vector2.ONE * (1.035 if on else 1.0), 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not on:
		create_tween().tween_property(self, "rotation", 0.0, 0.2)
	queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and _hover and Kit.motion() and variant != Variant.MINI:
		_hover_x = clampf(ev.position.x / maxf(1.0, size.x), 0.0, 1.0)
		rotation = (_hover_x - 0.5) * 0.045   # a slight tilt toward the pointer
		queue_redraw()


func _on_down() -> void:
	_press_id += 1
	var id := _press_id
	if Kit.motion():
		create_tween().tween_property(self, "scale", Vector2.ONE * 0.95, 0.07).set_trans(Tween.TRANS_QUAD)
	if is_inside_tree():
		get_tree().create_timer(LONG_PRESS).timeout.connect(func():
			if id == _press_id and is_instance_valid(self):
				_swallow = true
				Kit.sfx(self, "ui_page")
				long_pressed.emit(self))


func _on_up() -> void:
	_press_id += 1
	if Kit.motion():
		create_tween().tween_property(self, "scale", Vector2.ONE * (1.035 if _hover else 1.0), 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		scale = Vector2.ONE


func _on_pressed() -> void:
	if _swallow:
		_swallow = false
		if toggle_mode:
			set_pressed_no_signal(not button_pressed)   # a hold opened details: undo the toggle
		return
	Kit.sfx(self, "ui_locked" if (locked or unaffordable) and not button_pressed else "ui_tap")
	if _tap_cb.is_valid():
		_tap_cb.call()


## Flip (FULL): squash to the edge, swap faces, open again.
func flip() -> void:
	if not Kit.motion():
		flipped = not flipped
		queue_redraw()
		return
	Kit.sfx(self, "ui_page")
	var tw := create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "scale:x", 0.0, 0.12).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		flipped = not flipped
		if _foil != null:
			_foil.visible = not flipped
		queue_redraw())
	tw.tween_property(self, "scale:x", 1.0, 0.16).set_ease(Tween.EASE_OUT)


func set_states(p_locked: bool, p_unaffordable: bool, p_tag: String = "") -> void:
	if p_locked != locked or p_unaffordable != unaffordable or p_tag != block_tag:
		locked = p_locked
		unaffordable = p_unaffordable
		block_tag = p_tag
		queue_redraw()


## "Lv 12" for an owned monster, "No.001" for a compendium entry, "" when hidden.
func level_text() -> String:
	if not show_level:
		return ""
	return "Lv %d" % int(model.level) if not inst.is_empty() or rec.has("_form_of") else number_text()


func number_text() -> String:
	return "No.%s" % mon_id.get_slice("-", 1) if mon_id.begins_with("MON-") else ""


func _build_fx() -> void:
	if _foil != null:
		_foil.queue_free()
		_foil = null
	if _aura != null:
		_aura.queue_free()
		_aura = null
	if bool(model.get("shine", false)) and variant != Variant.MINI:
		_foil = ColorRect.new()
		_foil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = FOIL
		var foil := bool(model.foil)
		mat.set_shader_parameter("rainbow", 1.0 if foil else 0.0)
		mat.set_shader_parameter("strength", [0.0, 0.0, 0.22, 0.32, 0.38, 0.46][int(model.tier)])
		mat.set_shader_parameter("speed", (0.2 if foil else 0.14) if Kit.motion() else 0.0)
		mat.set_shader_parameter("phase", float(absi(hash(uid + mon_id)) % 100) / 100.0)
		_foil.material = mat
		add_child(_foil)
		_on_resized()
	if bool(model.get("aura", false)):
		_aura = Aura.new()
		_aura.color = model.frame
		_aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_aura.show_behind_parent = true
		_aura.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_aura)
		if is_inside_tree():
			_start_aura()


func _start_aura() -> void:
	if _aura == null or not Kit.motion() or _aura.has_meta("pulsing"):
		return
	_aura.set_meta("pulsing", true)
	var tw := _aura.create_tween().set_loops()
	tw.tween_property(_aura, "modulate:a", 0.45, 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_aura, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE)


## Legendary aura: soft gold halo around the frame (pulsed by modulate).
class Aura extends Control:
	const UIA = preload("res://scripts/ui_art.gd")
	var color := Color.WHITE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		for i in 7:
			var g := r.grow(4.0 + i * 4.0)
			draw_rect(g, Color(color, 0.16 - i * 0.02), false, 4.0)
		for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			UIA.glow(self, c, size.x * 0.16, Color(color, 0.5))


# ---------------------------------------------------------------- geometry

## Scale factor against the variant's design size.
func k() -> float:
	return size.x / float(SIZES[variant].x)


## The art window inside the frame.
func art_rect() -> Rect2:
	var s := k()
	match variant:
		Variant.FULL:
			return Rect2(Vector2(20, 20) * s, Vector2(size.x - 40 * s, size.y * 0.5))
		Variant.COMPACT:
			return Rect2(Vector2(7, 7) * s, Vector2(size.x - 14 * s, size.y * 0.71))
	return Rect2(Vector2(5, 5) * s, Vector2(size.x - 10 * s, size.y * 0.72))


static func cham(r: Rect2, cut: float) -> PackedVector2Array:
	var p := r.position
	var e := r.end
	return PackedVector2Array([p + Vector2(cut, 0), Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut), Vector2(e.x, e.y - cut),
		Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut), Vector2(p.x, p.y + cut)])


func _ring(r: Rect2, cut: float, col: Color, w: float) -> void:
	var pts := cham(r, cut)
	pts.append(pts[0])
	draw_polyline(pts, col, w, true)


func _font(display: bool, weight: int = 700) -> Font:
	return UIArt.font(display, weight)


## Largest size <= fs (>= min_fs) at which `t` fits `width`.
func _fit(t: String, width: float, fs: int, min_fs: int, display: bool = true) -> int:
	var f := _font(display)
	var s := fs
	while s > min_fs and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > width:
		s -= 1
	return s


func _text(pos: Vector2, t: String, fs: int, col: Color, display: bool = false, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, outline: int = 4) -> void:
	var f := _font(display, 700 if display else 700)
	if outline > 0:
		draw_string_outline(f, pos, t, align, width, fs, outline, N)
	draw_string(f, pos, t, align, width, fs, col)


func _texture() -> Texture2D:
	if not _tex_done:
		_tex_done = true
		_tex = Assets.monster(art_id, str(model.get("family", "")))
	return _tex


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if model.is_empty():
		return
	draws += 1
	match variant:
		Variant.FULL:
			if flipped:
				_draw_back()
			else:
				_draw_full()
		Variant.COMPACT:
			_draw_compact()
		_:
			_draw_mini()


func _selected() -> bool:
	return toggle_mode and button_pressed


## Body plate + art window with the element backdrop and the creature (painted or procedural).
func _draw_body_and_art(cut: float) -> Rect2:
	var r := Rect2(Vector2.ZERO, size)
	var fc := Palette.family(str(model.family))
	var frame: Color = model.frame
	if _selected():
		for i in 4:
			_ring(r.grow(3.0 + i * 3.0), cut + i * 2.0, Color(CYAN, 0.35 - i * 0.08), 3.0)
	draw_colored_polygon(cham(r, cut), N.lerp(frame, 0.07))
	var a := art_rect()
	UIArt.vgrad(self, a, N.lerp(fc, 0.55), N.lerp(fc, 0.12))
	UIArt.glow(self, a.position + a.size * Vector2(0.5, 0.42), a.size.x * 0.55, Color(fc.lightened(0.35), 0.55))
	var tex := _texture()
	var dim := Color(0.34, 0.36, 0.46) if locked else (Color(0.62, 0.62, 0.7) if disabled else Color.WHITE)
	if tex != null:
		UIArt.draw_cover(self, tex, a, 0.3 if Assets.is_crop(tex) else 0.2, dim)
	else:
		var sil := Assets.silhouette(str(model.role))
		var box := Rect2(a.position + a.size * Vector2(0.12, 0.1), a.size * Vector2(0.76, 0.8))
		var side := minf(box.size.x, box.size.y)
		box = Rect2(box.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
		if sil != null:
			draw_texture_rect(sil, box, false, SILVER.lerp(fc, 0.4) * dim)
		else:
			Kit.role_glyph(self, box.get_center(), side * 0.36, str(model.role), Color(SILVER.lerp(fc, 0.4), 0.9) * dim)
	if _hover and Kit.motion():
		UIArt.glow(self, a.position + Vector2(a.size.x * _hover_x, a.size.y * 0.3), a.size.x * 0.4, Color(1, 1, 1, 0.1))
	# fade the art into the body under the name plate
	var fade := Rect2(a.position + Vector2(0, a.size.y * 0.62), Vector2(a.size.x, a.size.y * 0.38))
	UIArt.vgrad(self, fade, Color(N, 0.0), Color(N.lerp(frame, 0.07), 0.94))
	if locked:
		draw_rect(a, Color(N, 0.35))
	return a


## Rarity frame: metal ring (weight by tier), inner gold rule, gems, crest for Mythic+.
func _draw_frame(cut: float, s: float) -> void:
	var r := Rect2(Vector2.ZERO, size)
	var t := int(model.tier)
	var frame: Color = model.frame
	var w := (2.5 + t * 0.9) * s * (2.0 if variant == Variant.FULL else 1.0)
	_ring(r.grow(-w * 0.5), cut, frame.darkened(0.25), w)
	_ring(r.grow(-w * 0.5), cut, Color(frame.lightened(0.35), 0.55), maxf(1.0, w * 0.25))
	_ring(r.grow(-w - 4.0 * s), cut * 0.8, Color(GOLD, 0.3 + t * 0.12), maxf(1.0, 1.6 * s))
	var a := art_rect()
	if not flipped:
		_ring(a, 8.0 * s, Color(GOLD, 0.35 + t * 0.1), maxf(1.0, 1.5 * s))
	var gem_r := (7.0 + t) * s * (1.6 if variant == Variant.FULL else 1.0)
	var gc: Color = frame.lightened(0.25) if t < 5 else Color.WHITE.lerp(GOLD, 0.35)
	var spots := []
	match int(model.gems):
		1: spots = [Vector2(size.x * 0.5, w * 0.5)]
		2: spots = [Vector2(size.x * 0.5, w * 0.5), Vector2(size.x * 0.5, size.y - w * 0.5)]
		4: spots = [Vector2(cut * 0.5, cut * 0.5), Vector2(size.x - cut * 0.5, cut * 0.5), Vector2(size.x - cut * 0.5, size.y - cut * 0.5), Vector2(cut * 0.5, size.y - cut * 0.5)]
		6: spots = [Vector2(cut * 0.5, cut * 0.5), Vector2(size.x - cut * 0.5, cut * 0.5), Vector2(size.x - cut * 0.5, size.y - cut * 0.5), Vector2(cut * 0.5, size.y - cut * 0.5), Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5)]
	for p in spots:
		UIArt.glow(self, p, gem_r * 2.2, Color(gc, 0.35))
		Kit.diamond(self, p, gem_r, gc, N)
	if bool(model.crest):
		var c := Vector2(size.x * 0.5, w * 0.4)
		var cr := gem_r * 1.5
		draw_colored_polygon(PackedVector2Array([c + Vector2(-cr * 3.2, 0), c + Vector2(-cr * 0.9, -cr * 0.55), c + Vector2(-cr * 0.9, cr * 0.55)]), frame.darkened(0.1))
		draw_colored_polygon(PackedVector2Array([c + Vector2(cr * 3.2, 0), c + Vector2(cr * 0.9, -cr * 0.55), c + Vector2(cr * 0.9, cr * 0.55)]), frame.darkened(0.1))
		UIArt.glow(self, c, cr * 3.0, Color(gc, 0.45))
		Kit.diamond(self, c, cr, gc, N)


## Name plate across the art's lower edge; returns its rect.
func _draw_plate(center: Vector2, w: float, h: float, s: float, name_fs: int) -> Rect2:
	var pr := Rect2(center - Vector2(w, h) * 0.5, Vector2(w, h))
	var frame: Color = model.frame
	draw_colored_polygon(cham(pr, h * 0.3), Color(N.lerp(frame, 0.1), 0.97))
	_ring(pr, h * 0.3, frame.lerp(GOLD, 0.5), maxf(1.0, 2.0 * s))
	_ring(pr.grow(-4.0 * s), h * 0.25, Color(GOLD, 0.3), 1.0)
	var nm: String = model.name.to_upper() if variant != Variant.MINI else model.name
	var fs := _fit(nm, w - 24.0 * s, name_fs, int(name_fs * 0.62))
	Kit.centered_text(self, pr.get_center(), nm, fs, (SILVER.darkened(0.3) if locked else GOLD.lerp(Color.WHITE, 0.25)), true, int(4 * s) + 2)
	return pr


func _draw_bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Color(N.lerp(SILVER, 0.12), 0.95))
	if frac > 0.0:
		var f := Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y))
		UIArt.vgrad(self, f, col.lightened(0.25), col.darkened(0.15))
	draw_rect(r, Color(SILVER, 0.25), false, 1.0)


## Evolution pips: one diamond per form of the line, filled up to the current form.
func _draw_evo_pips(c: Vector2, r: float) -> void:
	var n := int(model.evo_forms)
	if n <= 1:
		return
	var gap := r * 2.0
	for i in n:
		var p := Vector2(c.x - gap * (n - 1) * 0.5 + i * gap, c.y)
		if i <= int(model.evo_stage):
			Kit.diamond(self, p, r, GOLD, N)
		else:
			Kit.diamond(self, p, r * 0.8, Color(N, 0.7), Color(GOLD, 0.45))


func _draw_fused_ribbon(c: Vector2, w: float, h: float, s: float) -> void:
	var v := Palette.CRYSTAL_VIOLET
	var pts := PackedVector2Array([c + Vector2(-w * 0.5 - h * 0.4, -h * 0.5), c + Vector2(w * 0.5 + h * 0.4, -h * 0.5), c + Vector2(w * 0.5, 0),
		c + Vector2(w * 0.5 + h * 0.4, h * 0.5), c + Vector2(-w * 0.5 - h * 0.4, h * 0.5), c + Vector2(-w * 0.5, 0)])
	draw_colored_polygon(pts, v.darkened(0.25))
	pts.append(pts[0])
	draw_polyline(pts, v.lightened(0.4), maxf(1.0, 1.5 * s), true)
	Kit.centered_text(self, c, "FUSED", int(h * 0.62), Color.WHITE, true, 3)


func _draw_state_overlay(cut: float, s: float) -> void:
	var r := Rect2(Vector2.ZERO, size)
	var tag := block_tag if block_tag != "" else ("OVER %s CAP" % Summon.term("bond").to_upper() if unaffordable else "")
	if tag != "" and not _selected():
		draw_colored_polygon(cham(r, cut), Color(N, 0.55))
		var pr := Rect2(Vector2(size.x * 0.1, size.y * 0.4), Vector2(size.x * 0.8, 40.0 * s))
		draw_colored_polygon(cham(pr, 10.0 * s), (Palette.EMBER if unaffordable else Palette.CRYSTAL_VIOLET).darkened(0.35))
		Kit.centered_text(self, pr.get_center(), tag, _fit(tag, pr.size.x - 10 * s, int(22 * s), 10), Color.WHITE, true, 3)
	if locked:
		var c := art_rect().get_center()
		var lw := 26.0 * s * (1.8 if variant == Variant.FULL else 1.0)
		draw_arc(c + Vector2(0, -lw * 0.35), lw * 0.55, PI, TAU, 18, GOLD.darkened(0.2), maxf(2.0, lw * 0.16), true)
		draw_rect(Rect2(c - Vector2(lw * 0.75, lw * 0.3), Vector2(lw * 1.5, lw * 1.1)), GOLD.darkened(0.2))
		draw_circle(c + Vector2(0, lw * 0.2), lw * 0.17, N)
	if _selected():
		var cc := Vector2(size.x * 0.5, 4.0 * s)
		var cr := 20.0 * s * (1.4 if variant == Variant.FULL else 1.0)
		draw_circle(cc, cr, CYAN)
		draw_arc(cc, cr, 0, TAU, 24, Color.WHITE, maxf(1.5, 2.0 * s), true)
		draw_polyline(PackedVector2Array([cc + Vector2(-cr * 0.45, 0), cc + Vector2(-cr * 0.1, cr * 0.38), cc + Vector2(cr * 0.5, -cr * 0.35)]), N, maxf(2.0, cr * 0.22), true)
	if disabled and not locked:
		draw_colored_polygon(cham(r, cut), Color(N, 0.35))


func _draw_full() -> void:
	var s := k()
	var cut := 26.0 * s
	var a := _draw_body_and_art(cut)
	var fam := str(model.family)
	var fc := Palette.family(fam)
	# element + role badges (top-left), costs (top-right)
	var eb := a.position + Vector2(52, 54) * s
	Kit.element_badge(self, eb, 36.0 * s, fam)
	_text(eb + Vector2(48, -6) * s, fam.to_upper(), int(26 * s), fc.lightened(0.35), true)
	_text(eb + Vector2(48, 22) * s, str(model.element), int(22 * s), SILVER)
	var rr := Rect2(a.position + Vector2(18, 106) * s, Vector2(196, 50) * s)
	draw_colored_polygon(cham(rr, 12 * s), Color(N, 0.82))
	_ring(rr, 12 * s, Color(SILVER, 0.6), 1.5 * s)
	Kit.role_glyph(self, rr.position + Vector2(30, 25) * s, 15 * s, str(model.role), SILVER)
	_text(rr.position + Vector2(56, 34) * s, str(model.role).to_upper(), int(22 * s), SILVER, true)
	if show_costs:
		Kit.bond_badge(self, Vector2(a.end.x - 52 * s, a.position.y + 56 * s), 42.0 * s, int(model.bond), unaffordable)
		Kit.sp_badge(self, Vector2(a.end.x - 52 * s, a.position.y + 158 * s), 34.0 * s, int(model.sp))
	# name plate + rarity
	var pr := _draw_plate(Vector2(size.x * 0.5, a.end.y), size.x * 0.82, 74 * s, s, int(46 * s))
	Kit.rarity_pips(self, Vector2(size.x * 0.5, pr.end.y + 22 * s), 11.0 * s, int(model.tier))
	_text(Vector2(40 * s, pr.end.y + 30 * s), str(model.rarity).to_upper(), int(20 * s), model.frame.lightened(0.2), true)
	# level, XP, evolution pips
	var y := pr.end.y + 58 * s
	if inst.is_empty():   # compendium entry: its number and level cap (no XP yet)
		_text(Vector2(40 * s, y + 30 * s), number_text(), int(34 * s), GOLD.lerp(Color.WHITE, 0.2), true)
		_text(Vector2(240 * s, y + 30 * s), "Level cap %d" % int(model.level_cap), int(24 * s), SILVER)
	else:
		_text(Vector2(40 * s, y + 30 * s), "Lv %d" % int(model.level), int(36 * s), GOLD.lerp(Color.WHITE, 0.2), true)
		_text(Vector2(40 * s, y + 56 * s), "cap %d" % int(model.level_cap), int(18 * s), SILVER.darkened(0.2))
		_draw_bar(Rect2(Vector2(176 * s, y + 14 * s), Vector2(340 * s, 14 * s)), float(model.xp_frac), CYAN)
		_text(Vector2(176 * s, y + 52 * s), "XP %d%%" % roundi(float(model.xp_frac) * 100.0), int(18 * s), CYAN.lightened(0.3))
	_draw_evo_pips(Vector2(size.x - 100 * s, y + 20 * s), 12.0 * s)
	if int(model.evo_forms) > 1:
		Kit.centered_text(self, Vector2(size.x - 100 * s, y + 50 * s), "FORM %d/%d" % [int(model.evo_stage) + 1, int(model.evo_forms)], int(17 * s), GOLD.darkened(0.1), true, 2)
	# stat bars
	y += 74 * s
	var i := 0
	for key in STAT_KEYS:
		var ry := y + i * 31 * s
		_text(Vector2(40 * s, ry + 22 * s), STAT_LABEL[key], int(20 * s), SILVER.darkened(0.1), true)
		_draw_bar(Rect2(Vector2(150 * s, ry + 8 * s), Vector2(440 * s, 16 * s)), float(model.fracs[key]), STAT_COLOR[key])
		_text(Vector2(606 * s, ry + 24 * s), str(model.stats[i]), int(24 * s), Color.WHITE, true)
		i += 1
	# skill
	y += 5 * 31 * s + 6 * s
	var sk := Rect2(Vector2(28 * s, y), Vector2(size.x - 56 * s, size.y - y - 28 * s))
	draw_colored_polygon(cham(sk, 12 * s), Color(N.lerp(Palette.CRYSTAL_VIOLET, 0.12), 0.95))
	_ring(sk, 12 * s, Color(Palette.CRYSTAL_VIOLET, 0.6), 1.5 * s)
	_text(sk.position + Vector2(16, 30) * s, "SKILL", int(18 * s), Palette.CRYSTAL_VIOLET.lightened(0.35), true)
	_text(sk.position + Vector2(90, 31) * s, str(model.ability), int(28 * s), Color.WHITE, true)
	draw_multiline_string(_font(false, 600), sk.position + Vector2(16, 60) * s, str(model.ability_desc), HORIZONTAL_ALIGNMENT_LEFT, sk.size.x - 32 * s, int(21 * s), 2, SILVER)
	_draw_frame(cut, s)
	if bool(model.fused):
		_draw_fused_ribbon(Vector2(size.x * 0.5, 22 * s), 150 * s, 40 * s, s)
	_draw_state_overlay(cut, s)


func _draw_back() -> void:
	var s := k()
	var cut := 26.0 * s
	var r := Rect2(Vector2.ZERO, size)
	var fc := Palette.family(str(model.family))
	draw_colored_polygon(cham(r, cut), N.lerp(model.frame, 0.07))
	UIArt.glow(self, Vector2(size.x * 0.5, size.y * 0.3), size.x * 0.7, Color(fc, 0.18))
	var pr := _draw_plate(Vector2(size.x * 0.5, 70 * s), size.x * 0.82, 74 * s, s, int(46 * s))
	Kit.rarity_pips(self, Vector2(size.x * 0.5, pr.end.y + 22 * s), 11.0 * s, int(model.tier))
	var x := 44.0 * s
	var w := size.x - 88.0 * s
	var y := pr.end.y + 74 * s
	_text(Vector2(x, y), "LORE", int(22 * s), GOLD, true)
	draw_multiline_string(_font(false, 600), Vector2(x, y + 36 * s), lore(model), HORIZONTAL_ALIGNMENT_LEFT, w, int(25 * s), 4, SILVER)
	y += 190 * s
	_text(Vector2(x, y), "SKILL  -  %s" % str(model.ability).to_upper(), int(22 * s), Palette.CRYSTAL_VIOLET.lightened(0.35), true)
	draw_multiline_string(_font(false, 600), Vector2(x, y + 36 * s), str(model.ability_desc), HORIZONTAL_ALIGNMENT_LEFT, w, int(25 * s), 3, SILVER)
	if bool(model.fused) and str(model.secondary_ability) != "":
		_text(Vector2(x, y + 128 * s), "Also carries %s (%s affinity)" % [model.secondary_ability, model.secondary_family], int(21 * s), Palette.CRYSTAL_VIOLET.lightened(0.45))
	y += 170 * s
	_text(Vector2(x, y), "STATS  (Lv %d / %d)" % [int(model.level), int(model.level_cap)], int(22 * s), GOLD, true)
	var i := 0
	for key in STAT_KEYS:
		var cx := x + (i % 3) * (w / 3.0)
		var cy := y + 50 * s + (i / 3) * 56 * s
		_text(Vector2(cx, cy), STAT_LABEL[key], int(20 * s), STAT_COLOR[key].lightened(0.2), true)
		_text(Vector2(cx + 96 * s, cy + 2 * s), str(model.stats[i]), int(30 * s), Color.WHITE, true)
		i += 1
	y += 170 * s
	_text(Vector2(x, y), "SUMMONING", int(22 * s), GOLD, true)
	var costs := "%s %d    Crack %d %s    %s HP %d" % [Summon.term("bond"), int(model.bond), int(model.sp), Summon.term("sp"), Summon.term("vessel"), int(model.vessel_hp)]
	_text(Vector2(x, y + 40 * s), costs, int(24 * s), CYAN.lightened(0.3))
	Kit.centered_text(self, Vector2(size.x * 0.5, size.y - 40 * s), "TAP TO TURN BACK", int(18 * s), SILVER.darkened(0.3), true, 2)
	_draw_frame(cut, s)


func _draw_compact() -> void:
	var s := k()
	var cut := 14.0 * s
	var a := _draw_body_and_art(cut)
	var fam := str(model.family)
	Kit.element_badge(self, a.position + Vector2(24, 24) * s, 19.0 * s, fam)
	var rc := a.position + Vector2(24, 64) * s
	draw_circle(rc, 16 * s, Color(N, 0.8))
	draw_arc(rc, 16 * s, 0, TAU, 20, Color(SILVER, 0.5), 1.2 * s, true)
	Kit.role_glyph(self, rc, 10.0 * s, str(model.role), SILVER)
	if show_costs:
		Kit.bond_badge(self, Vector2(a.end.x - 25 * s, a.position.y + 26 * s), 23.0 * s, int(model.bond), unaffordable)
		Kit.sp_badge(self, Vector2(a.end.x - 25 * s, a.position.y + 82 * s), 18.0 * s, int(model.sp))
	# Lv pill + evolution pips on the art's lower edge
	var lv := level_text()
	var lr := Rect2(Vector2(a.position.x + 6 * s, a.end.y - 40 * s), Vector2(78 * s, 30 * s))
	if lv != "":
		draw_colored_polygon(cham(lr, 8 * s), Color(N, 0.85))
		_ring(lr, 8 * s, Color(GOLD, 0.6), 1.2 * s)
		Kit.centered_text(self, lr.get_center(), lv, _fit(lv, lr.size.x - 8 * s, int(22 * s), 12), GOLD.lerp(Color.WHITE, 0.3), true, 3)
	_draw_evo_pips(Vector2(a.end.x - 40 * s, a.end.y - 25 * s), 8.0 * s)
	# name + rarity under the art
	var nm: String = model.name
	var ny := a.end.y + (size.y - a.end.y) * 0.42
	var fs := _fit(nm, size.x - 18 * s, int(26 * s), int(17 * s))
	Kit.centered_text(self, Vector2(size.x * 0.5, ny), nm, fs, SILVER.darkened(0.3) if locked else GOLD.lerp(Color.WHITE, 0.3), true, 4)
	Kit.rarity_pips(self, Vector2(size.x * 0.5, ny + 30 * s), 7.0 * s, int(model.tier))
	_draw_frame(cut, s)
	if bool(model.fused):
		_draw_fused_ribbon(Vector2(size.x * 0.5, 16 * s), 70 * s, 24 * s, s)
	_draw_state_overlay(cut, s)


func _draw_mini() -> void:
	var s := k()
	var cut := 10.0 * s
	var a := _draw_body_and_art(cut)
	Kit.element_badge(self, a.position + Vector2(17, 17) * s, 14.0 * s, str(model.family))
	var lv := level_text()
	if lv != "":
		Kit.centered_text(self, Vector2(a.end.x - 32 * s, a.end.y - 14 * s), lv, _fit(lv, 60 * s, int(19 * s), 11), GOLD.lerp(Color.WHITE, 0.3), true, 4)
	var nm: String = model.name
	var fs := _fit(nm, size.x - 10 * s, int(21 * s), int(14 * s))
	Kit.centered_text(self, Vector2(size.x * 0.5, a.end.y + (size.y - a.end.y) * 0.5), nm, fs, GOLD.lerp(Color.WHITE, 0.3), true, 3)
	_draw_frame(cut, s)
	_draw_state_overlay(cut, s)
