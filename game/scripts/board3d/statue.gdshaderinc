// Living-statue look shared by creature.gdshader (procedural bodies) and sprite.gdshader (painted
// cut-outs). A monster on the board is a weathered stone STATUE of itself; `stone_h` is the fraction
// of its height (feet up) that is stone, so 1.1 = statue, 0 = live, and tweening it 0 -> 1.1 is the
// re-petrify sweep (glowing front). `crack` = element-light cracks racing up before the shatter,
// `vein` = faint element veins on a statue (0 for dormant guardians, which are also `cold`),
// `damage` = dark crack decals that grow as HP drops, `shield` = rune glow while defending.
// Needs noise.gdshaderinc included first.

uniform float stone_h = 1.1;
uniform float crack = 0.0;
uniform float vein = 0.7;
uniform float cold = 0.0;
uniform float damage = 0.0;
uniform float shield = 0.0;
uniform vec4 vein_color : source_color = vec4(1.0, 0.55, 0.2, 1.0);

float s_ridge(vec2 p) {
	return 1.0 - abs(vnoise(p) * 2.0 - 1.0);
}

// p: object-space-ish position (stable on the body), hf: height fraction 0 (feet) .. 1 (top),
// fres: fresnel term. Rewrites albedo / emission in place; returns the stone coverage 0..1.
float statue_apply(inout vec3 alb, inout vec3 emi, vec3 p, float hf, float fres) {
	float wob = (vnoise(p.xz * 13.0 + p.y * 3.0) - 0.5) * 0.08;
	float front = stone_h - hf + wob;
	float s = smoothstep(-0.012, 0.012, front);
	float sweeping = step(0.001, stone_h) * step(stone_h, 1.04);
	float band = sweeping * (1.0 - smoothstep(0.0, 0.06, abs(front)));
	float n = fbm3(p.xy * 3.0 + p.z * 2.0) * 0.75 + vnoise(p.xy * 14.0 + p.z * 9.0) * 0.25;
	float lum = dot(alb, vec3(0.3, 0.59, 0.11));
	vec3 warm = vec3(0.47, 0.45, 0.41);
	vec3 coldc = vec3(0.35, 0.38, 0.43);
	vec3 st = mix(warm, coldc, cold) * (0.5 + 0.7 * n) * (0.7 + 0.5 * lum);
	st *= 1.0 - 0.4 * fres;                                          // cavities / turned edges read darker
	st = mix(st, alb * 0.55 + st * 0.45, 0.16 * (1.0 - cold));      // a breath of the monster's own hue
	float lichen = smoothstep(0.72, 0.86, vnoise(p.xy * 8.0 + p.z * 5.0));
	st = mix(st, st * vec3(0.82, 0.95, 0.78), lichen * 0.55 * (1.0 - cold));
	// damage decals: dark cracks that widen with HP lost
	float dr = s_ridge(p.xy * 5.5 + p.z * 3.0 + 3.1);
	float dmg = damage > 0.01 ? smoothstep(1.0 - 0.09 * damage, 1.0, dr) : 0.0;
	st *= 1.0 - 0.8 * dmg;
	// element veins (slow pulse, < 0.3 Hz)
	float vr = s_ridge(p.xy * 9.0 + p.z * 5.0);
	float vl = smoothstep(0.93, 0.99, vr) * vein * (1.0 - cold);
	// awakening cracks racing up from the feet
	float cr = s_ridge(p.xy * 4.2 + p.z * 2.6 + 7.0);
	float reach = crack * 1.35;
	float cmask = 1.0 - smoothstep(reach - 0.12, reach, hf);
	float cl = crack > 0.001 ? smoothstep(1.0 - 0.3 * sqrt(crack), 1.0, cr) * cmask : 0.0;
	vec3 vc = vein_color.rgb;
	vec3 glow = vc * (vl * (0.75 + 0.25 * sin(TIME * 1.7)) * 2.2 + cl * 7.0 + crack * cmask * 0.35);
	glow += vc * shield * (fres * 1.8 + 0.6 * step(0.9, fract(hf * 7.0 - TIME * 0.6)));
	alb = mix(alb, st, s);
	emi = mix(emi, vec3(0.0), s) + glow * s + vc * band * 3.5;
	return s;
}
