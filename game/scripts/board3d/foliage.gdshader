// Grass tufts, vines and leaves (MultiMesh): alpha-cut texture tinted by the instance colour, with
// a gentle wind sway on the free end and an upward normal so they light like the ground.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float sway = 0.05;
uniform bool hanging = false;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float free_end = hanging ? UV.y : (1.0 - UV.y);
	VERTEX.x += sin(TIME * 1.7 + o.x * 1.3 + o.z * 0.9) * sway * free_end;
	VERTEX.z += cos(TIME * 1.3 + o.z * 1.1) * sway * 0.6 * free_end;
}

void fragment() {
	vec4 t = texture(tex, UV);
	if (t.a < 0.45) {
		discard;
	}
	ALBEDO = t.rgb * COLOR.rgb;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.25, 0.0)).xyz);
}
