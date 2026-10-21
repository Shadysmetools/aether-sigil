// Procedural creatures (board3d/creature.gd): vertex-coloured, soft lit, fresnel rim in the element
// colour, emissive eyes/crystals (UV2.y), plus hit flash, desaturation (spent) and a noise dissolve
// with a glowing edge (summon / crumble). On the board every monster is a stone statue of itself
// (statue.gdshaderinc): stone_h / crack / vein / cold / damage / shield.
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
#include "res://scripts/board3d/noise.gdshaderinc"
#include "res://scripts/board3d/statue.gdshaderinc"

uniform float flash = 0.0;
uniform float sat = 1.0;
uniform float dissolve = 0.0;
uniform float model_h = 0.7;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 rim_color : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform float sway = 1.0;

varying vec3 op;

void vertex() {
	op = VERTEX;
	// live only: wings / fins flap and the tail sways (slow sines, < 1 Hz)
	float live = 1.0 - clamp(stone_h, 0.0, 1.0);
	float wing = smoothstep(0.14, 0.42, abs(VERTEX.z)) * step(0.25, VERTEX.y / model_h);
	VERTEX.y += sin(TIME * 4.4) * 0.05 * wing * live * sway;
	float tail = 1.0 - smoothstep(-0.5, -0.22, VERTEX.x);
	VERTEX.z += sin(TIME * 3.0 + VERTEX.x * 4.0) * 0.045 * tail * live * sway;
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
	vec3 emi = c * UV2.y * 2.6 * sat + rim_color.rgb * fres * 0.7 * sat;
	float s = statue_apply(c, emi, op * 3.0, op.y / model_h, fres);
	ALBEDO = c;
	ROUGHNESS = mix(0.55, 0.92, s);
	EMISSION = emi + vec3(flash) * 1.5 + mix(rim_color.rgb, vec3(0.75, 0.72, 0.66), s) * edge * 2.5;
}
