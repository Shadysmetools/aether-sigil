// Soft contact shadow under monsters, and the team ring around their feet (ring_mix = 1).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 0.5);
uniform float ring_mix = 0.0;
uniform float fade = 1.0;

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float blob = pow(clamp(1.0 - r, 0.0, 1.0), 1.4);
	float ring = (1.0 - smoothstep(0.0, 0.07, abs(r - 0.82))) + (1.0 - smoothstep(0.0, 0.04, abs(r - 0.68))) * 0.6;
	ring += (1.0 - smoothstep(0.55, 0.85, r)) * 0.18;
	float a = mix(blob, clamp(ring, 0.0, 1.0), ring_mix);
	ALBEDO = color.rgb * (1.0 + ring_mix * 0.6);
	ALPHA = a * color.a * fade;
}
