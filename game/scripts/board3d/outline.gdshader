// Inverted-hull ink outline for the procedural creatures (anime line art). Same dissolve as the body.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
#include "res://scripts/board3d/noise.gdshaderinc"

uniform vec4 line_color : source_color = vec4(0.04, 0.06, 0.12, 1.0);
uniform float width = 0.012;
uniform float dissolve = 0.0;
uniform float flash = 0.0;

varying vec3 op;

void vertex() {
	op = VERTEX;
	VERTEX += NORMAL * width;
}

void fragment() {
	if (vnoise(op.xy * 22.0 + op.z * 9.0) < dissolve * 1.05) {
		discard;
	}
	ALBEDO = mix(line_color.rgb, vec3(1.0), flash);
}
