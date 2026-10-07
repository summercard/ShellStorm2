shader_type spatial;
render_mode unshaded;
uniform sampler2D code_texture : source_color, filter_linear, repeat_enable;
uniform float scroll_phase;
void fragment() {
	vec3 color = texture(code_texture, vec2(UV.x, UV.y+scroll_phase)).rgb;
	ALBEDO = color;
	EMISSION = color * 0.35;
}
