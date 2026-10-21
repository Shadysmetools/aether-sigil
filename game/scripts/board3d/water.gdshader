// Channel water: two scrolling noise layers for colour, ripple normals and sparkles. Translucent.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx, shadows_disabled;
#include "res://scripts/board3d/noise.gdshaderinc"

uniform vec4 deep_color : source_color = vec4(0.08, 0.32, 0.45, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.35, 0.75, 0.85, 1.0);
uniform float flow = 1.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	float t = TIME * flow;
	float w1 = vnoise(p * 3.2 + vec2(t * 0.35, t * 0.22));
	float w2 = vnoise(p * 5.1 - vec2(t * 0.27, -t * 0.31));
	float w = (w1 + w2) * 0.5;
	float dx = vnoise(p * 4.0 + vec2(t * 0.4 + 0.05, 0.0)) - vnoise(p * 4.0 + vec2(t * 0.4, 0.0));
	float dz = vnoise(p * 4.0 + vec2(0.0, t * 0.3 + 0.05)) - vnoise(p * 4.0 + vec2(0.0, t * 0.3));
	vec3 n = normalize(vec3(-dx * 6.0, 1.0, -dz * 6.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 col = mix(deep_color.rgb, shallow_color.rgb, smoothstep(0.25, 0.75, w));
	float spark = smoothstep(0.80, 0.9, w1 * w2 * 1.9);
	col += vec3(0.9, 0.97, 1.0) * spark * 0.7;
	ALBEDO = col;
	ALPHA = 0.84;
	ROUGHNESS = 0.06;
	SPECULAR = 0.9;
	EMISSION = col * 0.18 + vec3(1.0) * spark * 0.25;
}
