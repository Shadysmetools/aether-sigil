// Logo art that arrives on a black background: alpha from luminance, colour un-premultiplied,
// so the black disappears over the key art. (Dark pixels of a transparent logo also fade; the
// logo slot is the only user.)
shader_type canvas_item;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float a = min(c.a, clamp((max(c.r, max(c.g, c.b)) - 0.03) / 0.97, 0.0, 1.0));
	COLOR = vec4(clamp(c.rgb / max(a, 0.001), 0.0, 1.0), a) * COLOR;
}
