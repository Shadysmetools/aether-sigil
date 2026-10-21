// Drifting cloud sea below the floating island (big horizontal planes).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://scripts/board3d/noise.gdshaderinc"

uniform vec4 cloud_color : source_color = vec4(0.97, 0.98, 1.0, 1.0);
uniform vec4 shade_color : source_color = vec4(0.55, 0.65, 0.82, 1.0);
uniform float cover = 0.5;
uniform float speed = 0.02;
uniform float opacity = 0.9;
uniform float scale = 0.12;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz * scale + vec2(TIME * speed, TIME * speed * 0.4);
	float n = fbm3(p);
	float lit = fbm3(p + vec2(0.06, 0.09));
	float m = smoothstep(1.0 - cover, 1.18 - cover, n);
	float r = length(UV - 0.5) * 2.0;
	vec3 col = mix(shade_color.rgb, cloud_color.rgb, clamp(0.45 + (n - lit) * 5.0, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = m * opacity * (1.0 - smoothstep(0.55, 1.0, r));
}
