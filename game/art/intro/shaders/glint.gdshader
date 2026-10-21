// Diagonal light glint that sweeps across text. Only lights bright pixels, so the text's
// drop shadow stays dark. Drive `sweep` (local x, in pixels) and `strength` from a Tween.
shader_type canvas_item;

uniform float sweep = -10000.0;
uniform float band = 70.0;
uniform float slant = 0.45;
uniform float strength = 0.0;
uniform vec4 glint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec4 c = COLOR;
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float d = local_pos.x + local_pos.y * slant - sweep;
	float g = exp(-(d * d) / (band * band)) * strength * smoothstep(0.35, 0.8, lum);
	COLOR = vec4(mix(c.rgb, glint_color.rgb, clamp(g, 0.0, 1.0)) + glint_color.rgb * g * 0.25, c.a);
}
