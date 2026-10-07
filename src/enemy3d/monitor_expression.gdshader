shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform vec4 region;
uniform vec2 face_scale = vec2(1.0);
uniform vec2 face_center;
void vertex() {
	VERTEX.xy = face_center + (VERTEX.xy-face_center) * face_scale;
}
void fragment() {
	vec2 uv = region.xy + UV * region.zw;
	vec4 ink = texture(atlas, uv);
	ALBEDO = ink.rgb;
	ALPHA = ink.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
