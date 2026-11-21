shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, fog_disabled;

#define VFX_SOFT 0
#define VFX_MIRROR 0
#define VFX_MIRROR_ONCE 0
#define VFX_TRANSPARENT 1
#define VFX_CUTOUT 0
#define VFX_LIT 0
#define VFX_EMISSION_MAP 0

uniform sampler2D main_texture : source_color, filter_linear, repeat_enable;
#if VFX_EMISSION_MAP
uniform sampler2D emission_texture : source_color, hint_default_white, filter_linear, repeat_enable;
#endif
uniform ivec2 axis_wrap = ivec2(-1);
uniform bool sampler_uses_mipmaps = false;
uniform bool use_texture = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 emission_tint : source_color = vec4(0.0);
uniform float tint_gain = 1.0;
uniform vec2 texture_scale = vec2(1.0);
uniform vec2 texture_offset = vec2(0.0);
uniform vec2 sheet_tiles = vec2(1.0);
uniform int geometry_mode = 0;
uniform vec3 pivot = vec3(0.0);
uniform bool mesh_flip = false;
uniform bool clamp_billboard_size = false;
uniform vec2 screen_limits = vec2(0.0, 1.0);
uniform int color_mode = 0;
uniform vec2 color_add_sub_diff = vec2(0.0);
uniform bool color_coefficients = false;
uniform int blend_semantics = 0;
uniform float cutoff = 0.5;
uniform vec2 camera_fade = vec2(-1.0);
uniform bool use_per_draw_data = false;
uniform vec4 draw_custom = vec4(0.0);
uniform vec4 draw_color = vec4(1.0);
#if VFX_SOFT
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec2 soft_distances = vec2(0.0, 0.2);
#endif

varying flat float frame_slot;
varying flat vec2 flip_uv_sign;

vec3 normalize_or(vec3 v, vec3 fallback) {
	float length_sq = dot(v, v);
	return length_sq > 1e-12 ? v * inversesqrt(length_sq) : fallback;
}

mat3 particle_rotation(vec3 a) {
	vec3 s = sin(a);
	vec3 c = cos(a);
	mat3 rx = mat3(vec3(1., 0., 0.), vec3(0., c.x, s.x), vec3(0., -s.x, c.x));
	mat3 ry = mat3(vec3(c.y, 0., -s.y), vec3(0., 1., 0.), vec3(s.y, 0., c.y));
	mat3 rz = mat3(vec3(c.z, s.z, 0.), vec3(-s.z, c.z, 0.), vec3(0., 0., 1.));
	return ry * rx * rz;
}

float screen_size_factor(float diameter, vec4 center_view, mat4 projection) {
	if (diameter <= 1e-6) {
		return 1.0;
	}
	vec4 center_clip = projection * center_view;
	float fraction = diameter * abs(projection[1][1]) * 0.5 / max(abs(center_clip.w), 1e-6);
	return clamp(fraction, screen_limits.x, screen_limits.y) / max(fraction, 1e-6);
}

void vertex() {
	vec4 custom_data = use_per_draw_data ? draw_custom : INSTANCE_CUSTOM;
	frame_slot = floor(round(custom_data.x) / 8.0);
	int flags = int(mod(round(custom_data.x), 8.0));
	vec3 flip_sign = vec3((flags & 1) == 0 ? 1.0 : -1.0, (flags & 2) == 0 ? 1.0 : -1.0, (flags & 4) == 0 ? 1.0 : -1.0);
	flip_uv_sign = mesh_flip ? vec2(1.0) : flip_sign.xy;
	VERTEX = (mesh_flip ? VERTEX * flip_sign : VERTEX) - pivot;
	if (geometry_mode != 0) {
		vec3 camera_x = INV_VIEW_MATRIX[0].xyz;
		vec3 camera_y = INV_VIEW_MATRIX[1].xyz;
		vec3 camera_z = INV_VIEW_MATRIX[2].xyz;
		vec4 center = MODEL_MATRIX[3];
		vec4 center_view = VIEW_MATRIX * center;
		bool ortho = PROJECTION_MATRIX[3][3] > 0.5;
		vec3 point_to_camera = normalize_or(INV_VIEW_MATRIX[3].xyz - center.xyz, camera_z);
		vec3 toward_camera = ortho ? camera_z : point_to_camera;
		if (geometry_mode == 3) {
			vec3 signed_axis = MODEL_MATRIX[0].xyz;
			vec3 along = vec3(0.0);
			vec3 across = vec3(0.0);
			if (dot(signed_axis, signed_axis) > 0.0) {
				vec3 direction = normalize(signed_axis);
				vec3 side = normalize_or(cross(-toward_camera, direction), vec3(0.0));
				float factor = screen_size_factor(length(MODEL_MATRIX[2].xyz), center_view, PROJECTION_MATRIX);
				vec3 width_axis = MODEL_MATRIX[1].xyz;
				float width = length(width_axis) * sign(dot(cross(direction, width_axis), MODEL_MATRIX[2].xyz));
				along = -signed_axis * factor;
				across = side * width * factor;
				center.xyz += 0.5 * along;
			}
			MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(along, 0.), vec4(across, 0.), vec4(camera_z, 0.), center);
#if VFX_LIT
			MODELVIEW_NORMAL_MATRIX = mat3(VIEW_MATRIX) * mat3(normalize_or(along, camera_x), normalize_or(across, camera_y), camera_z);
#endif
		} else {
			vec3 up = vec3(0.0, 1.0, 0.0);
			vec3 size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
			mat3 rotation = particle_rotation(custom_data.yzw);
			vec3 z_axis = geometry_mode == 2 ? point_to_camera : camera_z;
			vec3 x_axis = normalize_or(cross(camera_y, z_axis), camera_x);
			vec3 y_axis = cross(z_axis, x_axis);
			if (geometry_mode == 4) {
				x_axis = vec3(1.0, 0.0, 0.0);
				y_axis = vec3(0.0, 0.0, -1.0);
				z_axis = up;
			} else if (geometry_mode == 5) {
				y_axis = up;
				z_axis = normalize_or(vec3(toward_camera.x, 0.0, toward_camera.z), vec3(0.0, 0.0, 1.0));
				x_axis = cross(y_axis, z_axis);
			} else if (geometry_mode == 6) {
				y_axis = normalize_or(MODEL_MATRIX[1].xyz, camera_y);
				vec3 reference = abs(y_axis.y) < 0.99 ? up : vec3(0.0, 0.0, 1.0);
				x_axis = normalize_or(cross(y_axis, toward_camera), normalize_or(cross(y_axis, reference), camera_x));
				z_axis = cross(x_axis, y_axis);
			}
			float factor = clamp_billboard_size ? screen_size_factor(max(size.x, size.y), center_view, PROJECTION_MATRIX) : 1.0;
			mat3 axes = mat3(x_axis, y_axis, z_axis) * rotation;
			MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(axes[0] * size.x * factor, 0.), vec4(axes[1] * size.y * factor, 0.), vec4(axes[2] * size.z * factor, 0.), center);
#if VFX_LIT
			MODELVIEW_NORMAL_MATRIX = mat3(VIEW_MATRIX) * axes;
#endif
		}
	}
}

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

vec3 combine_color(vec3 base, vec3 particle) {
	if (color_mode == 1) {
		return mix(2.0 * base * particle, 1.0 - 2.0 * (1.0 - base) * (1.0 - particle), step(vec3(0.5), base));
	}
	if (color_mode == 2) {
		return hsv_to_rgb(vec3(rgb_to_hsv(particle).xy, rgb_to_hsv(base).z));
	}
	if (color_mode >= 3 && color_mode <= 5) {
		vec2 coefficients = color_add_sub_diff;
		if (!color_coefficients) {
			coefficients = vec2(color_mode == 3 ? 1.0 : -1.0, color_mode == 5 ? 1.0 : 0.0);
		}
		vec3 composed = base + particle * coefficients.x;
		return mix(composed, abs(composed), coefficients.y);
	}
	return base * particle;
}

float wrap_axis(float v, int mode, float inset) {
	if (mode == 0) { return fract(v); }
	// When the sampler repeats for the other axis, U/V = 1 would sample
	// the opposite edge. Keep the clamped/mirrored axis at a texel centre.
	if (mode == 1) { return clamp(v, inset, 1.0 - inset); }
	if (mode == 2) { return clamp(1.0 - abs(mod(v, 2.0) - 1.0), inset, 1.0 - inset); }
	if (mode == 3) { return clamp(abs(v), inset, 1.0 - inset); }
	return v;
}

void fragment() {
	vec4 texel = vec4(1.0);
	vec2 coords = ((UV - vec2(0.5)) * flip_uv_sign + vec2(0.5)) * texture_scale + texture_offset;
	if (use_texture) {
		if (sheet_tiles.x * sheet_tiles.y > 1.0) {
			float frame = mod(frame_slot, sheet_tiles.x * sheet_tiles.y);
			vec2 cell = vec2(mod(frame, sheet_tiles.x), floor(frame / sheet_tiles.x));
			vec2 inset = min(vec2(0.5) / vec2(textureSize(main_texture, 0)), vec2(0.5) / sheet_tiles);
			coords = clamp((coords + cell) / sheet_tiles, cell / sheet_tiles + inset, (cell + vec2(1.0)) / sheet_tiles - inset);
		}
#if VFX_MIRROR
		coords = vec2(1.0) - abs(mod(coords, vec2(2.0)) - vec2(1.0));
#endif
#if VFX_MIRROR_ONCE
		coords = clamp(abs(coords), vec2(0.0), vec2(1.0));
#endif
		if (any(greaterThanEqual(axis_wrap, ivec2(0)))) {
			vec2 size_px = vec2(textureSize(main_texture, 0));
			vec2 du = dFdx(coords);
			vec2 dv = dFdy(coords);
			float footprint = max(length(du * size_px), length(dv * size_px));
			float span = sampler_uses_mipmaps ? exp2(ceil(log2(max(1.0, footprint)))) : 1.0;
			vec2 edge = min(vec2(0.5), vec2(0.5 * span) / size_px);
			coords = vec2(wrap_axis(coords.x, axis_wrap.x, edge.x), wrap_axis(coords.y, axis_wrap.y, edge.y));
			texel = textureGrad(main_texture, coords, du, dv);
		} else {
			texel = texture(main_texture, coords);
		}
	}
	vec4 particle = use_per_draw_data ? draw_color * COLOR : COLOR;
	vec4 base = texel * tint * tint_gain;
	vec4 result = vec4(combine_color(base.rgb, particle.rgb), base.a * particle.a);
	float fade = 1.0;
#if VFX_SOFT
	float depth = texture(scene_depth, SCREEN_UV).r;
	if (depth > 0.0) {
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		ndc.z = depth * 2.0 - 1.0;
#endif
		vec4 opaque_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		float gap = VERTEX.z - opaque_view.z / opaque_view.w;
		fade *= clamp((gap - soft_distances.x) / max(soft_distances.y - soft_distances.x, 1e-6), 0.0, 1.0);
	}
#endif
	if (camera_fade.x >= 0.0) {
		fade *= clamp((-VERTEX.z - camera_fade.x) / max(camera_fade.y - camera_fade.x, 1e-6), 0.0, 1.0);
	}
	result.a *= fade;
#if VFX_CUTOUT
	if (result.a < cutoff) {
		discard;
	}
#endif
	if (blend_semantics == 1) {
		result.rgb *= clamp(result.a, 0.0, 1.0);
	} else if (blend_semantics == 2) {
		result.rgb = mix(vec3(1.0), result.rgb, clamp(result.a, 0.0, 1.0));
	} else if (blend_semantics == 3) {
		result.rgb = mix(vec3(0.5), result.rgb, clamp(result.a, 0.0, 1.0)) * 2.0;
	}
	vec3 glow = emission_tint.rgb * fade;
#if VFX_EMISSION_MAP
	glow *= texture(emission_texture, coords).rgb;
#endif
#if VFX_LIT
	ALBEDO = result.rgb;
	EMISSION = glow;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
#else
	ALBEDO = result.rgb + glow;
#endif
#if VFX_TRANSPARENT
	ALPHA = clamp(result.a, 0.0, 1.0);
#endif
}
