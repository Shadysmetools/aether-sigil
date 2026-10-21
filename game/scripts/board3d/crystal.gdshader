// Glowing faceted crystals (capsule nodes, Sigil monuments, relics, crystal tiles): flat facets,
// strong emission with a fresnel rim and a slow pulse.
shader_type spatial;
render_mode specular_schlick_ggx, shadows_disabled;

uniform vec4 core_color : source_color = vec4(0.4, 0.85, 1.0, 1.0);
uniform float glow = 1.4;
uniform float pulse = 1.0;

void fragment() {
	vec3 c = COLOR.rgb * core_color.rgb;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = c * 0.55;
	ROUGHNESS = 0.08;
	METALLIC = 0.1;
	SPECULAR = 1.0;
	EMISSION = c * glow * (0.45 + fres * 1.6) * (1.0 - 0.18 * pulse + 0.18 * pulse * sin(TIME * 2.3));
}
