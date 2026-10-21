## Full-screen sky behind the board and the world map. A painted backdrop (assets.gd backdrop()) is
## shown when it exists; otherwise the drifting-cloud shader (sky.gdshader) tinted per tower element,
## with distant floating-ruin silhouettes. Never takes input.
extends Control

const Palette = preload("res://scripts/theme_colors.gd")
const Assets = preload("res://scripts/assets.gd")
const SKY_SHADER = preload("res://scripts/sky.gdshader")

var sky: ColorRect
var painted: TextureRect
var far: Control
var shade: ColorRect
var family := ""   ## element family that tints the sky ("" = world map dusk)


class FarIslands extends Control:
	const P = preload("res://scripts/theme_colors.gd")
	var seed_key := "world"
	var tint := Color.WHITE

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(seed_key)
		var w := size.x
		var h := size.y
		for i in 6:
			var depth := rng.randf()
			var edge := rng.randf() * 0.22   # hug the left/right edges: the centre belongs to the board
			var c := Vector2((edge if i % 2 == 0 else 1.0 - edge) * w, h * (0.06 + rng.randf() * 0.3))
			var s := lerpf(18.0, 60.0, depth) * w / 1080.0 * 1.6
			var col := Color(tint.lerp(P.MIDNIGHT_NAVY, 0.15 + depth * 0.25), lerpf(0.18, 0.4, depth))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s, 0), c + Vector2(s, 0), c + Vector2(s * 0.5, s * 0.35),
				c + Vector2(s * 0.1, s * 0.9), c + Vector2(-s * 0.35, s * 0.4)]), col)
			for k in 4:
				var x := c.x + (k - 1.5) * s * 0.4 + rng.randf_range(-8, 8)
				var tall := s * rng.randf_range(0.5, 1.4)
				var tw := s * 0.1
				draw_colored_polygon(PackedVector2Array([Vector2(x - tw, c.y), Vector2(x - tw, c.y - tall * 0.75),
					Vector2(x, c.y - tall), Vector2(x + tw, c.y - tall * 0.75), Vector2(x + tw, c.y)]), col)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky = ColorRect.new()
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	sky.material = mat
	add_child(sky)
	far = FarIslands.new()
	far.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	far.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(far)
	painted = TextureRect.new()
	painted.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	painted.mouse_filter = Control.MOUSE_FILTER_IGNORE
	painted.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	painted.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(painted)
	shade = ColorRect.new()  # keeps text readable over painted art
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.color = Color(Palette.MIDNIGHT_NAVY, 0.46)
	add_child(shade)
	resized.connect(_on_resized)
	set_tower("", "")


func _on_resized() -> void:
	if size.y > 0:
		(sky.material as ShaderMaterial).set_shader_parameter("aspect", size.x / size.y)


## Sky for a tower (bible id "01", its element family) or the world map (both "").
func set_tower(tid: String, fam: String) -> void:
	family = fam
	var tex := Assets.backdrop(tid)
	painted.texture = tex
	painted.visible = tex != null
	shade.visible = tex != null
	sky.visible = tex == null
	far.visible = tex == null
	var cols := palette(fam)
	var mat := sky.material as ShaderMaterial
	for k in cols:
		mat.set_shader_parameter(k, cols[k])
	far.seed_key = "far" + tid
	far.tint = cols.mid_color
	far.queue_redraw()


## Shader colours per element family; every colour is a blend of the brand tokens.
static func palette(fam: String) -> Dictionary:
	var N := Palette.MIDNIGHT_NAVY
	var S := Palette.SOFT_SILVER
	var C := Palette.AETHER_CYAN
	var V := Palette.CRYSTAL_VIOLET
	var E := Palette.EMBER
	var G := Palette.SIGIL_GOLD
	var day := {"top_color": C.lerp(V, 0.3).lerp(N, 0.5), "mid_color": C.lerp(V, 0.15).lerp(S, 0.4).lerp(N, 0.18),
		"low_color": S.lerp(C, 0.2), "cloud_color": S.lerp(Color.WHITE, 0.7), "shade_color": C.lerp(V, 0.25).lerp(N, 0.3).lerp(S, 0.4),
		"glow_color": G.lerp(S, 0.4), "cover": 0.58}
	match fam:
		"Fire":
			return {"top_color": E.lerp(N, 0.75), "mid_color": E.lerp(G, 0.25).lerp(N, 0.3), "low_color": G.lerp(E, 0.35).lerp(S, 0.2),
				"cloud_color": G.lerp(S, 0.55), "shade_color": E.lerp(N, 0.55), "glow_color": G, "cover": 0.5}
		"Dark", "Arcane", "Space":
			return {"top_color": V.lerp(N, 0.85), "mid_color": V.lerp(N, 0.55), "low_color": V.lerp(C, 0.3).lerp(S, 0.25).lerp(N, 0.3),
				"cloud_color": V.lerp(S, 0.55), "shade_color": V.lerp(N, 0.72), "glow_color": V.lerp(S, 0.3), "cover": 0.42}
		"Ice":
			day.low_color = S.lerp(Color.WHITE, 0.4)
			day.cover = 0.58
			return day
		"Light":
			day.glow_color = G
			day.low_color = G.lerp(S, 0.6)
			return day
		"":
			return {"top_color": V.lerp(N, 0.8), "mid_color": C.lerp(V, 0.45).lerp(N, 0.5), "low_color": G.lerp(V, 0.3).lerp(S, 0.3).lerp(N, 0.2),
				"cloud_color": S.lerp(V, 0.15), "shade_color": V.lerp(N, 0.6), "glow_color": G.lerp(E, 0.2), "cover": 0.46}
	return day
