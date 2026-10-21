// Procedural sky for the battle board and world map: vertical gradient, two drifting cloud
// layers (3-octave value noise), a soft sun glow. Cheap enough for 30 fps at 1080x1920 on GL
// Compatibility. Replaced by a painted backdrop (art/ai/backdrops/...) when one exists.
shader_type canvas_item;

uniform vec4 top_color : source_color = vec4(0.10, 0.20, 0.42, 1.0);
uniform vec4 mid_color : source_color = vec4(0.36, 0.55, 0.80, 1.0);
uniform vec4 low_color : source_color = vec4(0.78, 0.86, 0.95, 1.0);
uniform vec4 cloud_color : source_color = vec4(0.97, 0.98, 1.0, 1.0);
uniform vec4 shade_color : source_color = vec4(0.42, 0.52, 0.70, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.86, 0.55, 1.0);
uniform vec2 glow_pos = vec2(0.72, 0.12);
uniform float aspect = 0.5625;   // width / height of the rect
uniform float speed = 0.012;
uniform float cover = 0.48;      // 0 = clear, 1 = overcast

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 3; i++) {
		v += a * noise(p);
		p = p * 2.07 + vec2(1.7, 9.2);
		a *= 0.48;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(top_color.rgb, mid_color.rgb, smoothstep(0.0, 0.55, uv.y));
	col = mix(col, low_color.rgb, smoothstep(0.5, 1.0, uv.y));
	vec2 p = vec2(uv.x * aspect, uv.y) * 3.2;
	float t = TIME * speed;
	// far layer: thin, slow
	float far = fbm(p * 1.6 + vec2(t * 0.6, 0.0));
	float far_m = smoothstep(1.0 - cover * 0.9, 1.05 - cover * 0.6, far + uv.y * 0.18);
	col = mix(col, mix(mid_color.rgb, cloud_color.rgb, 0.55), far_m * 0.55);
	// near layer: puffy, lit from the top
	vec2 q = p * vec2(0.9, 1.6) + vec2(t, 0.0);
	float n = fbm(q);
	float lit = fbm(q + vec2(0.0, -0.08));
	float m = smoothstep(1.0 - cover, 1.15 - cover, n + uv.y * 0.22);
	vec3 cloud = mix(shade_color.rgb, cloud_color.rgb, clamp(0.35 + (lit - n) * 4.0 + (1.0 - uv.y) * 0.2, 0.0, 1.0));
	col = mix(col, cloud, m * 0.92);
	// sun glow
	float g = 1.0 - smoothstep(0.0, 0.55, distance(vec2(uv.x * aspect, uv.y), vec2(glow_pos.x * aspect, glow_pos.y)));
	col += glow_color.rgb * g * g * 0.35;
	COLOR = vec4(col, 1.0);
}
