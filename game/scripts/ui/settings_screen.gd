## Settings: audio sliders bound to the AudioManager buses (Master, Music, SFX, Voice, Ambience),
## reduced motion (menu_kit prefs), language placeholder, and Reset progress (tap twice).
## `audio` is injected (tests pass a fresh AudioManager with a temp prefs path); default is the
## /root/AudioManager autoload when it exists.
extends Control

const Palette = preload("res://scripts/theme_colors.gd")
const UIArt = preload("res://scripts/ui_art.gd")
const Kit = preload("res://scripts/ui/menu_kit.gd")

const BUSES := ["Master", "Music", "SFX", "Voice", "Ambience"]

var audio: Node                  ## AudioManager (or null: sliders still move, nothing plays)
var on_back: Callable
var on_reset: Callable
var sliders: Dictionary = {}     ## bus -> HSlider
var motion_toggle: Button
var language: OptionButton
var reset_button: Button
var _values: Dictionary = {}     ## bus -> Label
var _reset_armed := false


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
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 40)
	add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	m.add_child(vb)
	vb.add_child(Kit.title_block("SETTINGS", "Changes save as you make them"))
	var pnl := PanelContainer.new()
	pnl.add_theme_stylebox_override("panel", UIArt.panel_style(Palette.SIGIL_GOLD))
	vb.add_child(pnl)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	pnl.add_child(pv)
	var ah := Kit.header("AUDIO", 28)
	ah.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pv.add_child(ah)
	for bus in BUSES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		pv.add_child(row)
		var l := Kit.label(bus, 30, Palette.SOFT_SILVER, true)
		l.custom_minimum_size.x = 230
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.custom_minimum_size = Vector2(0, Kit.HIT)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_slider(s)
		row.add_child(s)
		var v := Kit.label("", 28, Palette.AETHER_CYAN, true, HORIZONTAL_ALIGNMENT_RIGHT)
		v.custom_minimum_size.x = 96
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(v)
		sliders[bus] = s
		_values[bus] = v
		s.value_changed.connect(_on_volume.bind(bus))
		s.drag_ended.connect(func(_changed): Kit.sfx(self, "ui_tap"))
	var gh := Kit.header("DISPLAY", 28)
	gh.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pv.add_child(gh)
	motion_toggle = Kit.chip("Reduced motion: Off", true)
	motion_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	motion_toggle.add_theme_font_size_override("font_size", 28)
	motion_toggle.tooltip_text = "No card shine, slides or tilts"
	motion_toggle.toggled.connect(_on_motion)
	pv.add_child(motion_toggle)
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 16)
	pv.add_child(lrow)
	var ll := Kit.label("Language", 30, Palette.SOFT_SILVER, true)
	ll.custom_minimum_size.x = 230
	ll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lrow.add_child(ll)
	language = OptionButton.new()
	language.add_item("English")
	language.add_item("More languages coming soon")
	language.set_item_disabled(1, true)
	language.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Kit.style_field(language)
	lrow.add_child(language)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)
	reset_button = Kit.button("Reset progress", _on_reset, 96, Palette.EMBER, "ui_locked")
	vb.add_child(reset_button)
	vb.add_child(Kit.button("Back", func(): if on_back.is_valid(): on_back.call(), 104, Palette.SOFT_SILVER, "ui_back"))


func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Palette.MIDNIGHT_NAVY.lerp(Palette.SOFT_SILVER, 0.18)
	track.set_corner_radius_all(6)
	track.content_margin_top = 7
	track.content_margin_bottom = 7
	var fill := track.duplicate()
	fill.bg_color = Palette.AETHER_CYAN
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var gt := _grabber(52)
	s.add_theme_icon_override("grabber", gt)
	s.add_theme_icon_override("grabber_highlight", gt)


## Gold disc grabber texture (big enough to drag with a thumb).
static func _grabber(d: int) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := Vector2(d, d) * 0.5
	for y in d:
		for x in d:
			var r := Vector2(x + 0.5, y + 0.5).distance_to(c) / (d * 0.5)
			var col := Palette.SIGIL_GOLD.lerp(Palette.SOFT_SILVER, clampf(0.35 - r, 0.0, 0.35))
			if r > 0.78:
				col = Palette.MIDNIGHT_NAVY
			img.set_pixel(x, y, Color(col, clampf((1.0 - r) * 12.0, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## Reads the current volumes and prefs into the controls (no signals fire).
func refresh() -> void:
	_reset_armed = false
	reset_button.text = "Reset progress"
	for bus in BUSES:
		var v := float(audio.get_volume(bus)) if audio != null and audio.has_method("get_volume") else 1.0
		sliders[bus].set_value_no_signal(v)
		_values[bus].text = "%d%%" % roundi(v * 100.0)
	Kit.load_prefs()
	motion_toggle.set_pressed_no_signal(Kit.reduced_motion)
	motion_toggle.text = "Reduced motion: %s" % ("On" if Kit.reduced_motion else "Off")


func _on_volume(v: float, bus: String) -> void:
	_values[bus].text = "%d%%" % roundi(v * 100.0)
	if audio != null and audio.has_method("set_volume"):
		audio.set_volume(bus, v)


func _on_motion(on: bool) -> void:
	Kit.reduced_motion = on
	motion_toggle.text = "Reduced motion: %s" % ("On" if on else "Off")
	Kit.save_prefs()


## Reset needs a second tap (destructive).
func _on_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		reset_button.text = "Tap again to erase all progress"
		return
	_reset_armed = false
	reset_button.text = "Reset progress"
	if on_reset.is_valid():
		on_reset.call()
