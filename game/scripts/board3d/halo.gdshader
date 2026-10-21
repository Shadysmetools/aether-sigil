// Additive camera-facing glow sprite (fake bloom around crystals, summons, auras).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.4, 0.85, 1.0, 1.0);
uniform float intensity = 0.8;
uniform float flicker = 0.15;

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = pow(clamp(1.0 - r, 0.0, 1.0), 2.2);
	float f = 1.0 - flicker + flicker * sin(TIME * 3.0 + MODEL_MATRIX[3].x * 2.0);
	ALBEDO = color.rgb * a * intensity * f;
}
