shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D screen_texture : source_color, filter_linear;
uniform float emission_strength : hint_range(0.0, 4.0) = 1.4;
uniform float scan_speed = 0.12;
uniform float scan_phase = 0.0;
void fragment() {
	vec3 content = texture(screen_texture, UV).rgb;
	float phase = fract(TIME * scan_speed + scan_phase);
	float band = 1.0 - smoothstep(0.0, 0.025, abs(UV.y - phase));
	float scan = 0.94 + 0.06 * sin(UV.y * 1300.0);
	ALBEDO = content * scan;
	EMISSION = content * emission_strength + content * band * 0.28;
}
