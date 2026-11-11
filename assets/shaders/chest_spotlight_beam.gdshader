shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 beam_color : source_color;
uniform float beam_strength = 0.23;
varying float height_ratio;

void vertex() {
	height_ratio = clamp(VERTEX.y / 5.2 + 0.5, 0.0, 1.0);
}

void fragment() {
	float fade = smoothstep(0.0, 0.78, height_ratio) * (1.0 - smoothstep(0.82, 1.0, height_ratio));
	float facing = pow(clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 1.6);
	ALBEDO = beam_color.rgb;
	ALPHA = clamp(fade * facing * beam_strength, 0.0, 1.0);
}
