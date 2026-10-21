// Waterfalls off the island edge: streaks scrolling down UV.y, foam lip at the top, fading out.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://scripts/board3d/noise.gdshaderinc"

uniform vec4 water_color : source_color = vec4(0.6, 0.85, 0.95, 1.0);

void fragment() {
	float s = vnoise(vec2(UV.x * 14.0, UV.y * 2.5 - TIME * 2.2));
	float s2 = vnoise(vec2(UV.x * 31.0 + 4.0, UV.y * 5.0 - TIME * 3.1));
	float streak = smoothstep(0.35, 0.8, s * 0.6 + s2 * 0.5);
	float edge = smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x);
	float fade = 1.0 - smoothstep(0.35, 1.0, UV.y);
	vec3 col = mix(water_color.rgb, vec3(1.0), streak * 0.7 + (1.0 - smoothstep(0.0, 0.06, UV.y)) * 0.6);
	ALBEDO = col;
	ALPHA = clamp((0.45 + streak * 0.5) * edge * fade, 0.0, 1.0);
}
