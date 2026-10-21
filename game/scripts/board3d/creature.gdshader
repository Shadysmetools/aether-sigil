// Procedural creatures (board3d/creature.gd): vertex-coloured, soft lit, fresnel rim in the element
// colour, emissive eyes/crystals (UV2.y), plus hit flash, desaturation (statues, spent) and a
// noise dissolve with a glowing edge (faint / summon).
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
#include "res://scripts/board3d/noise.gdshaderinc"

uniform float flash = 0.0;
uniform float sat = 1.0;
uniform float dissolve = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 rim_color : source_color = vec4(0.5, 0.8, 1.0, 1.0);

varying vec3 op;

void vertex() {
	op = VERTEX;
}

void fragment() {
	float n = vnoise(op.xy * 22.0 + op.z * 9.0);
	if (n < dissolve * 1.05) {
		discard;
	}
	vec3 c = COLOR.rgb * tint.rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(vec3(g), c, sat);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float edge = dissolve > 0.0 ? 1.0 - smoothstep(0.0, 0.08, n - dissolve) : 0.0;
	ALBEDO = c;
	ROUGHNESS = 0.55;
	EMISSION = c * UV2.y * 2.2 * sat + rim_color.rgb * fres * 0.45 * sat + vec3(flash) * 1.5 + rim_color.rgb * edge * 2.5;
}
