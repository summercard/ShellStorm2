shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D scene_color : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
uniform sampler2D scene_normals : hint_normal_roughness_texture, filter_nearest, repeat_disable;
#endif

uniform mat4 world_to_field;
uniform bool strict_box_bounds = false;
uniform vec3 half_size = vec3(18.0, 7.0, 18.0);
uniform float progress = 1.0;
uniform float strength = 1.0;
uniform float cell_size = 0.48;
uniform float edge_width = 1.25;
uniform float scan_speed = 0.54;
uniform vec3 grid_origin_offset = vec3(0.0);
uniform vec4 face_color : source_color = vec4(0.116, 0.068, 0.26, 1.0);
uniform vec4 grid_color : source_color = vec4(0.47, 0.35, 1.0, 1.0);
uniform vec4 outline_color : source_color = vec4(0.79, 0.62, 1.0, 1.0);
uniform vec4 edge_shadow_color : source_color = vec4(0.035, 0.022, 0.095, 1.0);
uniform vec4 edge_highlight_color : source_color = vec4(0.91, 0.84, 1.0, 1.0);
uniform float edge_shadow_strength = 0.72;
uniform float edge_highlight_strength = 1.0;
uniform vec3 edge_light_direction = vec3(-0.42, 0.76, 0.38);
uniform vec3 edge_light_position = vec3(-10.0, 10.0, 12.0);
uniform float edge_light_range = 48.0;
uniform float edge_light_falloff = 1.0;
uniform float edge_gradient_strength = 0.86;
uniform float edge_gradient_softness = 0.96;
uniform float edge_light_ambient = 0.26;
uniform float edge_light_contrast = 1.35;
uniform float edge_light_energy = 1.15;
uniform float edge_noise_scale = 0.32;
uniform float edge_noise_strength = 0.52;
uniform vec3 edge_noise_offset = vec3(17.3, -4.1, 9.7);
uniform float edge_spot_strength = 0.36;
uniform float edge_spot_threshold = 0.58;
uniform float base_color_strength = 0.58;
uniform vec4 guide_color : source_color = vec4(0.17, 0.79, 1.0, 1.0);
uniform vec4 signal_color : source_color = vec4(1.0, 0.28, 0.78, 1.0);

varying vec3 field_position;
varying vec3 field_normal;

float box_distance(vec3 point, vec3 extent) {
	vec3 offset = abs(point) - extent;
	return length(max(offset, 0.0)) + min(max(offset.x, max(offset.y, offset.z)), 0.0);
}

vec3 grating(vec3 coordinate, vec3 width, float thickness) {
	vec3 distance = abs(fract(coordinate + 0.5) - 0.5);
	vec3 ink = 1.0 - smoothstep(max(vec3(thickness) - width, 0.0), vec3(thickness) + width, distance);
	return ink * (1.0 - smoothstep(vec3(0.18), vec3(0.55), width));
}

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float smooth_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = smoothstep(vec3(0.0), vec3(1.0), fract(p));
	float c000 = hash3(cell);
	float c100 = hash3(cell + vec3(1.0, 0.0, 0.0));
	float c010 = hash3(cell + vec3(0.0, 1.0, 0.0));
	float c110 = hash3(cell + vec3(1.0, 1.0, 0.0));
	float c001 = hash3(cell + vec3(0.0, 0.0, 1.0));
	float c101 = hash3(cell + vec3(1.0, 0.0, 1.0));
	float c011 = hash3(cell + vec3(0.0, 1.0, 1.0));
	float c111 = hash3(cell + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(c000, c100, f.x), mix(c010, c110, f.x), f.y),
		mix(mix(c001, c101, f.x), mix(c011, c111, f.x), f.y), f.z);
}

float highest(vec3 channels) {
	return max(channels.x, max(channels.y, channels.z));
}

vec3 view_at(vec2 pixel, float depth, mat4 inverse_projection) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	depth = depth * 2.0 - 1.0;
#endif
	vec4 projected = inverse_projection * vec4(pixel * 2.0 - 1.0, depth, 1.0);
	return projected.xyz / max(abs(projected.w), 0.000001);
}

float structural_edge(vec2 uv, vec2 pixel_step, vec3 surface, vec3 normal, mat4 inverse_projection) {
	float discontinuity = 0.0;
	float reach = max(0.014, -surface.z * 0.00061);
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
	vec3 pixel_normal = texture(scene_normals, uv).rgb * 2.0 - 1.0;
#endif
	for (int i = 0; i < 4; i++) {
		vec2 axis = i < 2 ? vec2(pixel_step.x, 0.0) : vec2(0.0, pixel_step.y);
		vec2 neighbor_uv = clamp(uv + axis * (i % 2 == 0 ? 1.0 : -1.0), vec2(0.0), vec2(1.0));
		float depth = texture(scene_depth, neighbor_uv).r;
		vec3 neighbor = view_at(neighbor_uv, depth, inverse_projection);
		float gap = abs(dot(neighbor - surface, normal));
		float edge = smoothstep(reach, reach * 4.4, gap);
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
		vec3 neighbor_normal = texture(scene_normals, neighbor_uv).rgb * 2.0 - 1.0;
		edge = max(edge, smoothstep(0.17, 0.76, length(pixel_normal - neighbor_normal)) * 0.87);
#endif
		discontinuity = max(discontinuity, edge);
	}
	return discontinuity;
}

float glowing_track(float coordinate, float pixel_width, float line_width) {
	float distance = abs(coordinate);
	return 1.0 - smoothstep(line_width, line_width + max(pixel_width, 0.012), distance);
}

void vertex() {
	field_position = (world_to_field * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	field_normal = mat3(world_to_field) * MODEL_NORMAL_MATRIX * NORMAL;
	vec4 view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 clip = PROJECTION_MATRIX * view_position;
	vec4 lifted = PROJECTION_MATRIX * (view_position + vec4(0.0, 0.0, 0.0015, 0.0));
	if (lifted.w > 0.00001) {
		clip.z = lifted.z * clip.w / lifted.w;
	}
	POSITION = clip;
}

void fragment() {
	vec3 p = field_position;
	vec3 grid_point = p - grid_origin_offset;
	vec3 coordinate = grid_point / cell_size;
	vec3 width = max(fwidth(coordinate) * 0.57, vec3(0.002));
	vec3 surface_normal = normalize(field_normal);
	vec3 view_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	float distance = box_distance(p, half_size * progress);
	if (strength <= 0.0 || progress <= 0.0 || distance >= (strict_box_bounds ? 0.0 : edge_width * 0.16)) {
		discard;
	}

	float fade = 1.0 - smoothstep(-edge_width, edge_width * 0.16, distance);
	float transition = exp(-abs(distance + edge_width * 0.20) / (edge_width * 0.20));
	vec3 n = abs(surface_normal);
	vec3 tangent_weight = 1.0 - pow(n, vec3(3.0));
	float fine = highest(grating(coordinate, width, 0.018) * tangent_weight);
	float etched = highest(grating(coordinate * 3.0, width * 3.0, 0.012) * tangent_weight);
	vec3 routes = grating(coordinate / 5.0, width / 5.0, 0.014) * tangent_weight;
	float macro = highest(routes);
	float junction = max(routes.x * routes.y, max(routes.x * routes.z, routes.y * routes.z));

	float edge = structural_edge(SCREEN_UV, 1.25 / VIEWPORT_SIZE, VERTEX, view_normal, INV_PROJECTION_MATRIX);
	// Continuous virtual light with stable, low-frequency local variation.
	vec3 light_direction = normalize(edge_light_direction);
	vec3 to_light = edge_light_position - p;
	float light_distance = length(to_light);
	vec3 point_direction = to_light / max(light_distance, 0.001);
	float facing = max(dot(surface_normal, point_direction), 0.0);
	float distance_gradient = 1.0 - smoothstep(0.0, max(edge_light_range, 0.01), light_distance);
	distance_gradient = pow(distance_gradient, max(edge_light_falloff, 0.05));
	float point_light = facing * distance_gradient;
	float directional_gradient = max(dot(surface_normal, light_direction), 0.0);
	float diffuse = mix(directional_gradient, point_light, edge_gradient_strength);
	float gradient_width = max(edge_gradient_softness, 0.01);
	float light_gradient = smoothstep(0.5 - gradient_width * 0.5, 0.5 + gradient_width * 0.5, diffuse);
	float lit_value = clamp(edge_light_ambient + pow(light_gradient, max(edge_light_contrast, 0.05)) * (1.0 - edge_light_ambient), 0.0, 1.0);
	float local_noise = smooth_noise(grid_point * max(edge_noise_scale, 0.001) + edge_noise_offset);
	float local_spot = smoothstep(edge_spot_threshold - 0.18, edge_spot_threshold + 0.18, local_noise);
	float local_light = clamp(lit_value + (local_noise - 0.5) * edge_noise_strength
		+ local_spot * edge_spot_strength, 0.0, 1.0);
	light_gradient = mix(0.5, light_gradient, edge_gradient_strength);
	float shadow_factor = mix(0.34, 1.0, local_light) * mix(1.0, 0.60, (1.0 - light_gradient) * edge_shadow_strength);
	float highlight_factor = smoothstep(0.58, 0.96, local_light) * edge_highlight_strength * edge_light_energy;

	vec3 original = texture(scene_color, SCREEN_UV).rgb;
	float luminance = clamp(dot(original, vec3(0.213, 0.715, 0.072)), 0.0, 1.0);
	float surface_tone = pow(luminance, 0.47);
	float angular_fill = dot(n, vec3(0.07, 0.25, 0.13));
	float body_light = mix(0.52, 1.0, local_light);
	vec3 body = face_color.rgb * (0.56 + surface_tone * 1.42 + angular_fill) * base_color_strength * body_light;
	body += grid_color.rgb * (surface_tone * 0.039 + 0.014) * body_light;
	vec3 line_tone = mix(grid_color.rgb, outline_color.rgb, local_light * 0.45);
	vec3 matrix_light = line_tone * (fine * 0.20 + etched * 0.052 + macro * 0.23) * shadow_factor;
	matrix_light += mix(line_tone, outline_color.rgb, local_light * 0.45) * junction * 0.78 * shadow_factor;

	float floor_weight = smoothstep(0.43, 0.92, n.y);
	float guide_x = glowing_track(grid_point.x, width.x * cell_size, 0.017);
	float guide_z = glowing_track(grid_point.z, width.z * cell_size, 0.013);
	float pulse_x = pow(0.5 + 0.5 * cos(grid_point.z * 2.3 - TIME * scan_speed * 4.4), 17.0);
	float pulse_z = pow(0.5 + 0.5 * cos(grid_point.x * 2.0 + TIME * scan_speed * 3.7), 21.0);
	vec3 signals = floor_weight * (guide_color.rgb * guide_x * (0.46 + pulse_x * 1.53)
		+ signal_color.rgb * guide_z * (0.34 + pulse_z * 1.50)) * mix(0.62, 1.0, local_light);
	float tick = pow(0.5 + 0.5 * cos((grid_point.x - grid_point.z + grid_point.y * 0.62)
		* 7.5 - TIME * scan_speed * 2.9), 32.0);
	signals += mix(guide_color.rgb, signal_color.rgb, tick) * macro * tick * 0.35;

	vec3 edge_tone = mix(edge_shadow_color.rgb, outline_color.rgb, local_light);
	vec3 structure = edge_tone * edge * (0.56 + surface_tone * 0.58 + junction * 0.42) * shadow_factor;
	structure += edge_highlight_color.rgb * edge * highlight_factor
		* (0.18 + surface_tone * 0.32 + junction * 0.26);
	vec3 crossing_band = mix(guide_color.rgb, signal_color.rgb, 0.40)
		* transition * (0.05 + fine * 0.37 + macro * 0.43 + edge * 0.40);

	ALBEDO = body + matrix_light + structure + signals + crossing_band;
	float rim_alpha = transition * (0.24 + fine * 0.22) * (1.0 - smoothstep(-edge_width * 0.18, edge_width * 0.16, distance));
	ALPHA = strength * max(fade, rim_alpha) * smoothstep(0.0, 0.055, progress);
}
