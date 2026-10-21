## Shared materials and procedural textures for the 3D board (built once, cached). Colours come
## from theme_colors.gd; nothing here knows game rules.
extends RefCounted

const Palette = preload("res://scripts/theme_colors.gd")

const STONE := preload("res://scripts/board3d/stone.gdshader")
const WATER := preload("res://scripts/board3d/water.gdshader")
const FALL := preload("res://scripts/board3d/fall.gdshader")
const CLOUD := preload("res://scripts/board3d/cloud.gdshader")
const FOLIAGE := preload("res://scripts/board3d/foliage.gdshader")
const CRYSTAL := preload("res://scripts/board3d/crystal.gdshader")
const HALO := preload("res://scripts/board3d/halo.gdshader")
const HIGHLIGHT := preload("res://scripts/board3d/highlight.gdshader")
const BLOB := preload("res://scripts/board3d/blob.gdshader")
const CREATURE := preload("res://scripts/board3d/creature.gdshader")
const OUTLINE := preload("res://scripts/board3d/outline.gdshader")
const SPRITE := preload("res://scripts/board3d/sprite.gdshader")

static var _cache: Dictionary = {}


static func _sm(shader: Shader, params: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


## The island stone material for a tower theme (tower_theme dict) and haze colour.
static func stone(theme: Dictionary, haze: Color) -> ShaderMaterial:
	return _sm(STONE, {"moss_color": theme.moss, "moss_amount": theme.moss_amt, "snow_amount": 0.75 if theme.snow else 0.0,
		"hazard_color": Palette.EMBER.lerp(Palette.SIGIL_GOLD, 0.35), "accent_color": theme.accent,
		"player_color": Palette.PLAYER, "enemy_color": Palette.ENEMY, "haze_color": haze})


static func water(theme: Dictionary) -> ShaderMaterial:
	var w: Color = theme.water
	var m := _sm(WATER, {"deep_color": w.darkened(0.35), "shallow_color": w.lerp(Palette.SOFT_SILVER, 0.35)})
	m.render_priority = 1
	return m


static func fall(theme: Dictionary) -> ShaderMaterial:
	var m := _sm(FALL, {"water_color": Color(theme.water).lerp(Palette.SOFT_SILVER, 0.5)})
	m.render_priority = 2
	return m


static func cloud(cloud_col: Color, shade: Color, cover: float, opacity: float, speed: float, scale: float) -> ShaderMaterial:
	var m := _sm(CLOUD, {"cloud_color": cloud_col, "shade_color": shade, "cover": cover, "opacity": opacity, "speed": speed, "scale": scale})
	m.render_priority = -1
	return m


static func foliage(tex: Texture2D, hanging := false, sway := 0.05) -> ShaderMaterial:
	return _sm(FOLIAGE, {"tex": tex, "hanging": hanging, "sway": sway})


## Glowing crystal material in one colour (cached per colour).
static func crystal(col: Color, glow := 1.4) -> ShaderMaterial:
	var key := "crystal%s%.2f" % [col.to_html(), glow]
	if not _cache.has(key):
		_cache[key] = _sm(CRYSTAL, {"core_color": col, "glow": glow})
	return _cache[key]


static func halo(col: Color, intensity := 0.8) -> ShaderMaterial:
	var m := _sm(HALO, {"color": col, "intensity": intensity})
	m.render_priority = 3
	return m


static func highlight() -> ShaderMaterial:
	if not _cache.has("highlight"):
		var m := _sm(HIGHLIGHT)
		m.render_priority = 2
		_cache["highlight"] = m
	return _cache["highlight"]


static func blob(col: Color, ring := false) -> ShaderMaterial:
	var m := _sm(BLOB, {"color": col, "ring_mix": 1.0 if ring else 0.0})
	m.render_priority = 2 if ring else 1
	return m


## Per-monster body material (+ ink outline as next pass) so flash / dissolve are per unit.
static func creature(rim: Color, line: Color) -> ShaderMaterial:
	var m := _sm(CREATURE, {"rim_color": rim})
	m.next_pass = _sm(OUTLINE, {"line_color": line})
	return m


static func sprite(tex: Texture2D, rim: Color) -> ShaderMaterial:
	return _sm(SPRITE, {"tex": tex, "rim_color": rim})


## Unshaded additive particle material (CPUParticles3D billboards, vertex colour).
static func particle() -> StandardMaterial3D:
	if not _cache.has("particle"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = dot_texture()
		m.no_depth_test = false
		m.disable_receive_shadows = true
		m.render_priority = 4
		_cache["particle"] = m
	return _cache["particle"]


## Lit, vertex-coloured material for crystal shard particles (summon bursts).
static func shard() -> ShaderMaterial:
	if not _cache.has("shard"):
		_cache["shard"] = _sm(CRYSTAL, {"core_color": Color.WHITE, "glow": 2.0})
	return _cache["shard"]


# ---------------------------------------------------------------- procedural textures

## Soft round dot (particles).
static func dot_texture() -> Texture2D:
	if not _cache.has("dot"):
		var n := 32
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var r := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5).length() / (n / 2.0)
				var a := pow(clampf(1.0 - r, 0.0, 1.0), 1.6)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_cache["dot"] = ImageTexture.create_from_image(img)
	return _cache["dot"]


## Grass tuft: tapering blades, white (tinted per instance), bottom of the image = ground.
static func grass_texture() -> Texture2D:
	if not _cache.has("grass"):
		var w := 64
		var h := 64
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 0))
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for b in 14:
			var x0 := rng.randf_range(8, 56)
			var lean := rng.randf_range(-14, 14)
			var tall := rng.randf_range(0.45, 1.0) * h
			var wid := rng.randf_range(2.0, 3.6)
			for y in int(tall):
				var t := y / tall
				var cx := x0 + lean * t * t
				var hw := wid * (1.0 - t)
				var shade := 0.55 + 0.45 * t
				for x in range(int(cx - hw - 1), int(cx + hw + 2)):
					if x >= 0 and x < w and absf(x - cx) <= hw + 0.5:
						img.set_pixel(x, h - 1 - y, Color(shade, shade, shade, 1))
		img.generate_mipmaps()
		_cache["grass"] = ImageTexture.create_from_image(img)
	return _cache["grass"]


## Hanging vine strip: a wavy stem with leaves, top of the image = anchor.
static func vine_texture() -> Texture2D:
	if not _cache.has("vine"):
		var w := 32
		var h := 128
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 0))
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for strand in 3:
			var x0 := 8.0 + strand * 8.0
			var phase := rng.randf() * TAU
			var ln := h * rng.randf_range(0.55, 1.0)
			for y in int(ln):
				var cx := x0 + sin(y * 0.09 + phase) * 3.0
				for x in range(int(cx - 1), int(cx + 2)):
					if x >= 0 and x < w:
						img.set_pixel(x, y, Color(0.6, 0.6, 0.6, 1))
				if y % 9 == 0:
					var side := 1 if (y / 9) % 2 == 0 else -1
					for ly in 6:
						for lx in 5:
							var px := int(cx + side * (lx + 1))
							var py := y + ly - 2
							if px >= 0 and px < w and py >= 0 and py < h and Vector2(lx - 2.0, ly - 2.5).length() < 2.8:
								var s := 0.75 + 0.25 * (ly / 6.0)
								img.set_pixel(px, py, Color(s, s, s, 1))
		img.generate_mipmaps()
		_cache["vine"] = ImageTexture.create_from_image(img)
	return _cache["vine"]
