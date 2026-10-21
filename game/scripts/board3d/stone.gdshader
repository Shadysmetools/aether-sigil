// Weathered ruin stone for every solid surface of the 3D board, one material for the whole island.
// Pattern comes from world position (flagstones on tops, brick courses on sides, rough strata on
// rock), tint from the vertex colour, and a "kind" + moss strength from UV2 (board_build.gd K_*).
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;
#include "res://scripts/board3d/noise.gdshaderinc"

uniform vec4 moss_color : source_color = vec4(0.30, 0.45, 0.20, 1.0);
uniform float moss_amount = 0.7;
uniform float snow_amount = 0.0;
uniform vec4 hazard_color : source_color = vec4(1.0, 0.55, 0.2, 1.0);
uniform vec4 accent_color : source_color = vec4(0.13, 0.83, 0.93, 1.0);
uniform vec4 player_color : source_color = vec4(0.13, 0.83, 0.93, 1.0);
uniform vec4 enemy_color : source_color = vec4(1.0, 0.42, 0.24, 1.0);
uniform vec4 haze_color : source_color = vec4(0.70, 0.80, 0.95, 1.0);

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float rune_ring(vec2 local, float r0) {
	float r = length(local);
	float ring = 1.0 - smoothstep(0.0, 0.018, abs(r - r0));
	ring += 1.0 - smoothstep(0.0, 0.012, abs(r - r0 + 0.07));
	float ang = atan(local.y, local.x);
	float ticks = step(0.82, fract(ang * 1.909)) * step(abs(r - r0 + 0.035), 0.03);
	return clamp(ring + ticks, 0.0, 1.0);
}

void fragment() {
	int kind = int(UV2.x + 0.5);
	float moss_k = UV2.y;
	vec3 base = COLOR.rgb;
	bool top = wn.y > 0.6;
	vec2 tp = top ? wp.xz : vec2(wp.x + wp.z, wp.y * 1.4);
	float n1 = fbm3(tp * 2.7);
	float n2 = vnoise(tp * 13.0);
	vec3 col = base;
	float grout = 0.0;
	float rough = 0.9;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	if (kind == 1) {            // raw rock (island underside, cliffs)
		float strata = vnoise(vec2(wp.y * 5.0, (wp.x + wp.z) * 0.6));
		col *= 0.62 + 0.55 * fbm3(vec2((wp.x - wp.z) * 1.1, wp.y * 2.6));
		col *= 0.82 + 0.3 * strata;
		col *= 0.9 + 0.2 * n2;
	} else if (kind == 9) {     // wooden planks
		float plank = vnoise(vec2(tp.x * 1.5, tp.y * 30.0));
		col *= 0.7 + 0.4 * plank;
		col *= 0.85 + 0.25 * n2;
		rough = 0.8;
	} else if (kind == 11) {    // foliage (tree canopies, bushes)
		col *= 0.55 + 0.75 * vnoise(wp.xz * 8.0 + wp.y * 6.0);
		col *= 0.8 + 0.3 * fbm3(wp.xz * 2.0 + wp.y);
		rough = 1.0;
	} else if (kind == 12) {    // gold trim
		col *= 0.85 + 0.3 * n2;
		rough = 0.32;
		metal = 0.85;
	} else {
		if (top) {
			// one slab per tile, some split in two; grout is thin and the bevel draws the tile seam
			vec2 tile = floor(wp.xz);
			float split = hash21(tile + 3.7);
			vec2 q = wp.xz * (split > 0.55 ? vec2(2.0, 1.0) : (split > 0.3 ? vec2(1.0, 2.0) : vec2(1.0)));
			vec2 cell = floor(q);
			vec2 f = fract(q);
			float e = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
			grout = (1.0 - smoothstep(0.012, 0.04, e + (n2 - 0.5) * 0.03)) * 0.8;
			col *= 0.86 + 0.24 * hash21(cell * 1.31 + 0.7);
			col *= 0.94 + 0.12 * smoothstep(0.0, 0.25, e);
		} else {
			float row = floor(wp.y * 4.5);
			float u = (wp.x + wp.z) * 2.2 + mod(row, 2.0) * 0.5;
			vec2 f = vec2(fract(u), fract(wp.y * 4.5));
			float e = min(min(f.x, 1.0 - f.x) * 0.55, min(f.y, 1.0 - f.y));
			grout = 1.0 - smoothstep(0.03, 0.09, e);
			col *= 0.8 + 0.32 * hash21(vec2(floor(u), row));
			col *= 0.78 + 0.3 * vnoise(vec2((wp.x + wp.z) * 8.0, wp.y * 1.3));
		}
		col *= 0.72 + 0.48 * n1;
		col = mix(col, col * 0.42, grout);
		float crack = 1.0 - smoothstep(0.0, 0.016, abs(vnoise(tp * 3.6 + 11.0) - 0.5));
		col *= 1.0 - crack * 0.28 * step(0.5, n1);
		vec2 local = wp.xz - (floor(wp.xz) + 0.5);
		if (kind == 2) {        // hazard: glowing fissures
			float fis = 1.0 - smoothstep(0.0, 0.05, abs(vnoise(tp * 2.6 + 3.1) - 0.5));
			float pulse = 0.65 + 0.35 * sin(TIME * 3.0 + wp.x * 1.7 + wp.z);
			emit += hazard_color.rgb * (fis * 1.6 + grout * 0.5) * pulse * (top ? 1.0 : 0.35);
			col *= 0.7;
		} else if (kind == 3) { // lava: dark crust over a moving glow
			float flow = fbm3(tp * 1.8 + vec2(TIME * 0.12, TIME * 0.07));
			float hot = smoothstep(0.42, 0.7, flow);
			col = mix(col * 0.35, hazard_color.rgb * 0.6, hot);
			emit += mix(hazard_color.rgb, vec3(1.0, 0.85, 0.35), hot * 0.6) * hot * (top ? 2.2 : 0.8);
		} else if (kind == 4) { // ice: pale, glossy, frost veins
			col = mix(col, vec3(0.86, 0.95, 1.0), 0.45);
			col += vec3(0.25, 0.35, 0.4) * (1.0 - smoothstep(0.0, 0.04, abs(n2 - 0.5)));
			rough = 0.12;
		} else if (kind == 5) { // metal plates, rivets, cyan seams
			vec2 a = abs(local);
			float seam = step(0.44, max(a.x, a.y));
			float rivet = 1.0 - smoothstep(0.015, 0.025, length(a - vec2(0.36)));
			col = mix(col, col * 1.25, rivet);
			emit += accent_color.rgb * seam * 0.6 * (0.7 + 0.3 * sin(TIME * 2.0 + wp.x));
			rough = 0.42;
			metal = 0.6;
		} else if (kind == 6) { // shadow: violet wisps
			float w = smoothstep(0.55, 0.85, fbm3(tp * 1.6 + vec2(TIME * 0.08, -TIME * 0.05)));
			col *= 0.55;
			emit += accent_color.rgb * w * 0.7;
		} else if ((kind == 7 || kind == 8) && top) {   // spawn rune circle
			vec3 team = kind == 7 ? player_color.rgb : enemy_color.rgb;
			float r = rune_ring(local, 0.40);
			col = mix(col, team * 0.5, r * 0.6);
			emit += team * r * (0.75 + 0.25 * sin(TIME * 2.0));
		} else if (kind == 10) { // crystal-shot stone
			float g = pow(vnoise(tp * 9.0), 6.0);
			col = mix(col, accent_color.rgb * 0.6, 0.18);
			emit += accent_color.rgb * g * 1.5;
		} else if (kind == 13) { // sky / space: starry glass
			col = mix(col * 0.5, accent_color.rgb * 0.25, 0.5);
			emit += vec3(1.0) * step(0.985, hash21(floor(tp * 40.0))) * 1.2;
		} else if (kind == 14) { // wet channel floor
			col *= 0.55;
			rough = 0.3;
		}
	}
	// moss: patches on tops and in grout, drips down the sides
	float mm;
	if (top) {
		mm = smoothstep(0.56, 0.8, fbm3(wp.xz * 1.6 + 4.0) + moss_k * 0.25 - 0.12);
		mm = max(mm, grout * moss_k * 0.85);
	} else {
		mm = smoothstep(0.58, 0.8, fbm3(vec2((wp.x + wp.z) * 2.6, wp.y * 0.9)) + moss_k * 0.15);
	}
	mm *= moss_amount * moss_k;
	vec3 mossc = moss_color.rgb * (0.6 + 0.8 * vnoise(wp.xz * 12.0 + wp.y * 5.0));
	col = mix(col, mossc, clamp(mm, 0.0, 1.0));
	if (top) {
		col = mix(col, vec3(0.92, 0.96, 1.0), snow_amount * smoothstep(0.38, 0.62, fbm3(wp.xz * 2.2 + 9.0)));
	}
	float haze = clamp((-wp.y - 0.8) / 7.5, 0.0, 1.0);
	col = mix(col, haze_color.rgb, haze * 0.75);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
