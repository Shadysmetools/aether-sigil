// Painted monster cut-outs (Assets.monster with real alpha) as upright billboards. Alpha-cut,
// unshaded (the art is already lit), with the same flash / desaturate / dissolve controls.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://scripts/board3d/noise.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float flash = 0.0;
uniform float sat = 1.0;
uniform float dissolve = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 rim_color : source_color = vec4(0.5, 0.8, 1.0, 1.0);

void fragment() {
	vec4 t = texture(tex, UV);
	float n = vnoise(UV * 40.0);
	if (t.a < 0.5 || n < dissolve * 1.05) {
		discard;
	}
	vec3 c = t.rgb * tint.rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(vec3(g), c, sat);
	float edge = dissolve > 0.0 ? 1.0 - smoothstep(0.0, 0.08, n - dissolve) : 0.0;
	ALBEDO = mix(c, vec3(1.0), flash) + rim_color.rgb * edge * 2.0;
}
