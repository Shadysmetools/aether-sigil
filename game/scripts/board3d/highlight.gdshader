// Tile highlight overlays (move = cyan, attack = ember, skill = violet, selected = gold), drawn as a
// MultiMesh of flat quads just above each tile top. Instance colour carries the highlight colour.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

varying vec4 hc;

void vertex() {
	hc = COLOR;
}

void fragment() {
	vec2 d = abs(UV - 0.5) * 2.0;
	float box = max(d.x, d.y);
	float border = smoothstep(0.78, 0.9, box) * (1.0 - smoothstep(0.96, 1.0, box));
	float pulse = 0.8 + 0.2 * sin(TIME * 4.0);
	float corner = step(0.62, min(d.x, d.y)) * border;
	vec3 col = hc.rgb * (1.0 + corner * 0.6);
	ALBEDO = col * (1.0 + border * 0.5);
	ALPHA = clamp((0.17 + border * 0.85 * pulse) * hc.a, 0.0, 1.0);
}
