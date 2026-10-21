// Soft radial vignette overlay for a full-rect ColorRect. Pure alpha darkening, so it sits
// on top of the scene and frames whatever is underneath.
shader_type canvas_item;

uniform float aspect = 0.5625;   // width / height
uniform float inner = 0.55;
uniform float outer = 1.25;
uniform float strength = 0.65;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.x *= aspect;
	float d = length(p);
	COLOR = vec4(0.0, 0.0, 0.0, smoothstep(inner, outer, d) * strength);
}
