// Painted monster cut-outs (Assets.monster with real alpha) as upright billboards. Alpha-cut and
// unshaded (the art is already lit). On the board the cut-out is a carved ROCK statue of that exact
// painting (statue.gdshaderinc): granite albedo from the art's luminance, a fake normal from the
// luminance gradient for chiselled relief, ambient-occlusion darkening toward the silhouette edge
// and in deep strokes, lichen speckle (`moss`), faint element veins. Live (stone_h 0) it is the
// full-colour painting with an element rim glow, breathing and a soft wing / upper-body sway.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://scripts/board3d/noise.gdshaderinc"
#include "res://scripts/board3d/statue.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float flash = 0.0;
uniform float sat = 1.0;
uniform float dissolve = 0.0;
uniform float moss = 0.0;
uniform float sway = 1.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 rim_color : source_color = vec4(0.5, 0.8, 1.0, 1.0);

void vertex() {
	// live only: the upper half sways like breathing wings (slow, < 1 Hz)
	float up = smoothstep(0.45, 1.0, 1.0 - UV.y);
	float live = 1.0 - clamp(stone_h, 0.0, 1.0);
	VERTEX.x += sin(TIME * 2.6) * 0.035 * up * live * sway * sign(VERTEX.x);
	VERTEX.y += sin(TIME * 2.6 + 1.2) * 0.02 * up * live * sway;
}

float lum(vec3 c) {
	return dot(c, vec3(0.3, 0.59, 0.11));
}

void fragment() {
	vec4 t = texture(tex, UV);
	float n = vnoise(UV * 40.0);
	if (t.a < 0.5 || n < dissolve * 1.05) {
		discard;
	}
	vec3 c = t.rgb * tint.rgb;
	float g = lum(c);
	c = mix(vec3(g), c, sat);
	float edge = dissolve > 0.0 ? 1.0 - smoothstep(0.0, 0.08, n - dissolve) : 0.0;
	// relief from the painting: luminance gradient -> normal, lit from the upper left
	vec2 px = vec2(0.006, 0.006);
	float lx = lum(texture(tex, UV + vec2(px.x, 0.0)).rgb) - lum(texture(tex, UV - vec2(px.x, 0.0)).rgb);
	float ly = lum(texture(tex, UV + vec2(0.0, px.y)).rgb) - lum(texture(tex, UV - vec2(0.0, px.y)).rgb);
	vec3 nrm = normalize(vec3(-lx * 3.5, ly * 3.5, 0.35));
	float relief = clamp(0.55 + 0.75 * dot(nrm, normalize(vec3(-0.5, 0.6, 0.6))), 0.25, 1.35);
	// silhouette-edge occlusion (alpha taps) + deep strokes
	float ao = 0.0;
	vec2 o = vec2(0.035, 0.03);
	ao += texture(tex, UV + vec2(o.x, 0.0)).a + texture(tex, UV - vec2(o.x, 0.0)).a;
	ao += texture(tex, UV + vec2(0.0, o.y)).a + texture(tex, UV - vec2(0.0, o.y)).a;
	ao = mix(0.55, 1.0, smoothstep(1.5, 4.0, ao)) * mix(0.75, 1.0, smoothstep(0.08, 0.4, g));
	vec3 emi = vec3(0.0);
	float hf = 1.0 - UV.y;
	vec3 sp = vec3(UV.x * 2.2, hf * 2.2, 0.0);
	vec3 rock = c;
	float s = statue_apply(rock, emi, sp, hf, 0.0);
	// moss / lichen on the statue (Verdant-type towers)
	float mz = smoothstep(0.6, 0.8, fbm3(sp.xy * 5.0 + 3.0) + (1.0 - hf) * 0.15) * moss;
	rock = mix(rock, rock * vec3(0.55, 0.85, 0.45), mz * s);
	vec3 statue_col = rock * relief * ao;
	vec3 live_col = c + rim_color.rgb * smoothstep(0.6, 1.0, 1.0 - ao) * 0.6;
	vec3 col = mix(live_col, statue_col, s);
	ALBEDO = mix(col, vec3(1.0), flash) + emi + rim_color.rgb * edge * 2.0;
}
