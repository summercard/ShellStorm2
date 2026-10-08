shader_type spatial;
render_mode unshaded;
uniform sampler2D code_texture : source_color, filter_linear, repeat_enable;
uniform float scroll_phase;
uniform float boot_reveal = 1.0;
void fragment() {
	vec3 color = texture(code_texture, vec2(UV.x, UV.y+scroll_phase)).rgb;
	color *= step(1.0 - boot_reveal, UV.y) * step(0.001, boot_reveal);
	ALBEDO = color;
	EMISSION = color * 0.35;
}
