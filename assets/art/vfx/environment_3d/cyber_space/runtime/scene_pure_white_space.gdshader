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
uniform float block_size = 0.72;
uniform float edge_width = 1.25;
uniform float ao_radius = 0.72;
uniform float ao_strength = 0.82;
uniform float ao_bias = 0.018;
uniform float edge_strength = 0.92;
uniform float edge_softness = 0.12;
uniform vec4 white_color : source_color = vec4(0.72, 0.74, 0.80, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.12, 0.15, 0.22, 1.0);
uniform vec4 edge_color : source_color = vec4(0.30, 0.36, 0.47, 1.0);
uniform vec4 edge_highlight_color : source_color = vec4(0.68, 0.73, 0.82, 1.0);

varying vec3 field_position;
varying vec3 field_normal;

float box_distance(vec3 point, vec3 extent) {
	vec3 q = abs(point) - extent;
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float hash_cell(vec3 cell) {
	vec3 p = fract(cell * vec3(0.1031, 0.11369, 0.13787));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

vec3 view_at(vec2 uv, float depth, mat4 inverse_projection) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	depth = depth * 2.0 - 1.0;
#endif
	vec4 projected = inverse_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return projected.xyz / max(abs(projected.w), 0.000001);
}

float structural_edge(vec2 uv, vec2 pixel_step, vec3 surface, vec3 normal, mat4 inverse_projection) {
	float edge = 0.0;
	float reach = max(0.014, -surface.z * 0.00061);
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
	vec3 center_normal = texture(scene_normals, uv).rgb * 2.0 - 1.0;
#endif
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * 0.785398;
		vec2 offset = vec2(cos(angle), sin(angle)) * pixel_step * 1.45;
		vec2 neighbor_uv = clamp(uv + offset, vec2(0.0), vec2(1.0));
		vec3 neighbor = view_at(neighbor_uv, texture(scene_depth, neighbor_uv).r, inverse_projection);
		float depth_edge = smoothstep(reach, reach * 4.6, abs(dot(neighbor - surface, normal)));
		edge = max(edge, depth_edge);
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
		vec3 neighbor_normal = texture(scene_normals, neighbor_uv).rgb * 2.0 - 1.0;
		edge = max(edge, smoothstep(0.12, 0.68, length(center_normal - neighbor_normal)) * 0.88);
#endif
	}
	return edge;
}

float screen_ao(vec2 uv, vec3 surface, vec3 normal, vec2 pixel_step, mat4 inverse_projection) {
	float occlusion = 0.0;
	float samples = 0.0;
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * 0.785398 + 0.19;
		float radius = mix(0.65, 1.0, float(i % 3) / 2.0);
		vec2 offset = vec2(cos(angle), sin(angle)) * pixel_step * ao_radius * 8.0 * radius;
		vec2 sample_uv = clamp(uv + offset, vec2(0.001), vec2(0.999));
		vec3 sample_position = view_at(sample_uv, texture(scene_depth, sample_uv).r, inverse_projection);
		float closer = smoothstep(ao_bias, ao_bias + ao_radius * 0.42, sample_position.z - surface.z);
		float near_band = 1.0 - smoothstep(ao_radius * 0.55, ao_radius * 1.6, length(sample_position - surface));
		occlusion += closer * near_band;
		samples += 1.0;
	}
	return clamp(1.0 - occlusion / max(samples, 1.0) * ao_strength * 2.25, 0.0, 1.0);
}

float block_edge_mask(vec3 point, vec3 normal) {
	vec3 coordinates = point / max(block_size, 0.08);
	vec3 local = abs(fract(coordinates + 0.5) - 0.5);
	vec3 axis = 1.0 - pow(abs(normal), vec3(3.0));
	vec3 cell_lines = 1.0 - smoothstep(vec3(0.35), vec3(0.485), local);
	float line = max(cell_lines.x * axis.x, max(cell_lines.y * axis.y, cell_lines.z * axis.z));
	vec3 cell = floor(coordinates + 0.5);
	float segment = step(0.42, hash_cell(floor(cell / vec3(2.0)) + vec3(4.0, 11.0, -7.0)));
	float variation = mix(0.52, 0.90, hash_cell(cell + vec3(19.0, -3.0, 7.0)));
	return line * segment * variation;
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
	vec3 normal = normalize(field_normal);
	vec3 abs_normal = abs(normal);
	float distance = box_distance(p, half_size * progress);
	if (strength <= 0.0 || progress <= 0.0 || distance >= (strict_box_bounds ? 0.0 : edge_width * 0.16)) {
		discard;
	}

	vec3 surface = VERTEX;
	vec3 view_normal = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	float edge = structural_edge(SCREEN_UV, 2.0 / VIEWPORT_SIZE, surface, view_normal, INV_PROJECTION_MATRIX);
	float block_mask = block_edge_mask(p, normal);
	float stepped_edge = edge * smoothstep(0.46, 0.46 + max(edge_softness, 0.01), block_mask);
	float sampled_ao = screen_ao(SCREEN_UV, surface, view_normal, 1.0 / VIEWPORT_SIZE, INV_PROJECTION_MATRIX);
	// Screen-depth AO is intentionally biased toward open white surfaces. Without
	// this floor, large coplanar panels can read as fully occluded on Compatibility.
	float ao = mix(0.82, 1.0, sampled_ao);
	float block_shadow = stepped_edge;

	vec3 original = texture(scene_color, SCREEN_UV).rgb;
	float luminance = clamp(dot(original, vec3(0.213, 0.715, 0.072)), 0.0, 1.0);
	float material_value = mix(0.72, 1.0, pow(luminance, 0.78));
	float face_light = 0.88 + dot(abs_normal, vec3(0.06, 0.12, 0.08));
	vec3 original_gray = vec3(pow(luminance, 0.78));
	vec3 base = mix(original_gray * 0.82, white_color.rgb, 0.58);
	base *= (0.84 + ao * 0.16) * material_value * face_light;
	base -= shadow_color.rgb * (1.0 - ao) * 0.22;

	float rim = smoothstep(0.0, edge_width * 0.16, -distance);
	vec3 edge_tone = mix(edge_color.rgb, edge_highlight_color.rgb, ao * 0.42);
	vec3 block_rim = edge_tone * stepped_edge * edge_strength * (0.08 + rim * 0.05);
	float seam_line = block_mask * edge * 0.38;
	float dark_slot = clamp(seam_line * (0.68 + (1.0 - ao) * 0.64) + block_shadow * 0.48, 0.0, 1.0);
	base = mix(base, shadow_color.rgb, dark_slot * 0.46);
	vec3 transition = white_color.rgb * (1.0 - smoothstep(-edge_width, edge_width * 0.16, distance)) * 0.012;

	ALBEDO = clamp(base + block_rim + transition, vec3(0.0), vec3(0.82));
	ALPHA = strength * max(1.0 - smoothstep(-edge_width, edge_width * 0.16, distance), stepped_edge * 0.72)
		* smoothstep(0.0, 0.055, progress);
}
