shader_type spatial;
render_mode cull_disabled;
uniform sampler2D shared_palette : source_color, filter_nearest, repeat_disable;
instance uniform float lamp_brightness : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	vec3 color = texture(shared_palette, UV).rgb;
	ALBEDO = color * 0.3;
	ROUGHNESS = 0.4;
	EMISSION = color * 2.0 * lamp_brightness;
}
