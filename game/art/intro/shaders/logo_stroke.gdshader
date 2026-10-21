// Spatial 3-stop gradient for the SMETOOLS gear strokes (blue -> violet -> pink),
// measured from the official logo. Works on Line2D without UVs: colour comes from the
// vertex position in the node's local space. `boost` brightens the draw-on light trail.
shader_type canvas_item;

uniform vec4 c0 : source_color = vec4(0.357, 0.549, 1.0, 1.0);  // #5B8CFF
uniform vec4 c1 : source_color = vec4(0.608, 0.420, 1.0, 1.0);  // #9B6BFF
uniform vec4 c2 : source_color = vec4(0.890, 0.420, 1.0, 1.0);  // #E36BFF
uniform vec2 dir = vec2(0.70, 0.71);
uniform float span = 200.0;
uniform float boost = 1.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float t = clamp(dot(local_pos, normalize(dir)) / span * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = t < 0.5 ? mix(c0.rgb, c1.rgb, t * 2.0) : mix(c1.rgb, c2.rgb, t * 2.0 - 1.0);
	COLOR = vec4(min(col * boost, vec3(1.0)), COLOR.a);
}
