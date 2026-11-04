shader_type spatial;
render_mode world_vertex_coords, cull_disabled;

uniform sampler2D base_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D surface_texture : filter_linear_mipmap, repeat_enable;
uniform float glitch : hint_range(0.0, 1.0) = 0.0;
uniform float charge : hint_range(0.0, 1.0) = 0.0;
varying vec3 body_world;

float hash_band(float value) {
	return fract(sin(value * 79.13) * 4358.55);
}

void vertex() {
	body_world = VERTEX;
	float band = floor(body_world.y * 15.0);
	float tick = floor(TIME * 18.0);
	float jump = hash_band(band + 13.0 * tick) - 0.5;
	VERTEX += INV_VIEW_MATRIX[0].xyz * jump * glitch * 0.60;
}

void fragment() {
	float band = floor(body_world.y * 28.0);
	float tick = floor(TIME * 18.0);
	float drop = hash_band(band + floor(body_world.x * 5.0) * 3.17 + tick * 17.0);
	if (drop < glitch * 0.94) {
		discard;
	}
	vec3 base = texture(base_texture, UV).rgb;
	vec3 surface = texture(surface_texture, UV).rgb;
	// CRT glass island measured on the skinned v002 mesh from the attack side.
	vec2 glass = UV - vec2(0.475, 0.214);
	float screen = smoothstep(0.0, 0.0015, glass.x) * (1.0 - smoothstep(0.0365, 0.0385, glass.x));
	screen *= smoothstep(0.0, 0.0015, glass.y) * (1.0 - smoothstep(0.062, 0.064, glass.y));
	float scan = 0.66 + 0.34 * sin(glass.x * 680.0 + TIME * 18.0);
	float static_line = step(0.73, hash_band(band + tick * 6.0));
	vec3 cyan = vec3(0.11, 0.77, 1.0);
	ALBEDO = mix(base, cyan, max(glitch * 0.40, charge * screen * 0.65));
	ROUGHNESS = surface.g;
	METALLIC = surface.b;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	EMISSION = cyan * (charge * screen * (1.0 + 2.4 * scan) + glitch * (0.22 + static_line * 2.2));
}
