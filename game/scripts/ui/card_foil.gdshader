// Monster card foil / shine sweep (monster_card.gd). Additive diagonal band that crosses the art
// window every 1/speed seconds. rainbow 0 = white shine (Rare), 1 = aether->violet->gold foil (Epic+).
// speed 0 = reduced motion (a still, faint sheen).
shader_type canvas_item;
render_mode blend_add;

uniform float strength = 0.3;
uniform float speed = 0.22;
uniform float rainbow = 1.0;
uniform float phase = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	float t = speed > 0.0 ? fract(TIME * speed + phase) : 0.42;
	float d = (UV.x * 0.75 + UV.y * 0.55) - (t * 2.6 - 0.7);
	float band = exp(-d * d * 42.0) + 0.45 * exp(-(d + 0.22) * (d + 0.22) * 160.0);
	vec3 foil = vec3(0.13, 0.83, 0.93);                         // aether cyan
	foil = mix(foil, vec3(0.69, 0.36, 1.0), smoothstep(0.0, 0.5, fract(UV.x * 0.9 + UV.y * 0.6 + t)));   // crystal violet
	foil = mix(foil, vec3(0.96, 0.77, 0.27), smoothstep(0.5, 1.0, fract(UV.x * 0.9 + UV.y * 0.6 + t)));  // sigil gold
	vec3 c = mix(tint.rgb, foil, rainbow);
	float edge = smoothstep(0.0, 0.06, UV.x) * smoothstep(1.0, 0.94, UV.x) * smoothstep(0.0, 0.05, UV.y) * smoothstep(1.0, 0.95, UV.y);
	COLOR = vec4(c, clamp(band * strength * edge, 0.0, 1.0));
}
