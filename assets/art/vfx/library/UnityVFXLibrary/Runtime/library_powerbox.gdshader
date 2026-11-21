shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, fog_disabled;

#define POWERBOX_PBR 0
#define POWERBOX_ALPHA_MODE 0

uniform int geometry_mode = 0;
uniform vec3 pivot = vec3(0.0);
uniform bool mesh_flip = false;
uniform bool clamp_billboard_size = false;
uniform vec2 screen_limits = vec2(0.0, 1.0);
uniform vec2 sheet_tiles = vec2(1.0);
uniform bool use_per_draw_data = false;
uniform vec4 draw_custom = vec4(0.0);
uniform vec4 draw_color = vec4(1.0);

#if POWERBOX_PBR
uniform sampler2D main_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D metallic_gloss_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D bump_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D emission_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_metallic_gloss = false;
uniform bool use_bump = false;
uniform bool use_emission = false;
uniform bool smoothness_albedo_alpha = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 emission_tint : source_color = vec4(0.0);
uniform vec2 main_scale = vec2(1.0);
uniform vec2 main_offset = vec2(0.0);
uniform float metallic = 0.0;
uniform float roughness = 0.5;
uniform float gloss_map_scale = 1.0;
uniform float bump_scale = 1.0;
uniform float cutoff = 0.5;
#else
uniform sampler2D background_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D icon_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_disable;
uniform vec4 background_tint : source_color = vec4(1.0, 0.0, 0.05511808, 0.0);
uniform vec4 icon_tint : source_color = vec4(0.0);
uniform float background_contrast = 1.0;
uniform float icon_contrast = 1.0;
uniform float background_brightness = 1.0;
uniform float icon_brightness = 1.0;
uniform vec2 background_scale = vec2(1.0);
uniform vec2 background_offset = vec2(0.0);
uniform vec2 icon_scale = vec2(2.0);
uniform vec2 icon_offset = vec2(0.0);
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
#if POWERBOX_PBR
	if (mesh_flip) {
		NORMAL *= flip_sign;
		TANGENT *= flip_sign;
		BINORMAL *= flip_sign;
	}
#endif
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
		}
#if POWERBOX_PBR
		mat3 basis = mat3(MODELVIEW_MATRIX);
		if (abs(determinant(basis)) > 1e-12) {
			MODELVIEW_NORMAL_MATRIX = transpose(inverse(basis));
		}
#endif
	}
}

vec2 sampling_uv(vec2 coords, vec2 texture_size) {
	if (sheet_tiles.x * sheet_tiles.y > 1.0) {
		float frame = mod(frame_slot, sheet_tiles.x * sheet_tiles.y);
		vec2 cell = vec2(mod(frame, sheet_tiles.x), floor(frame / sheet_tiles.x));
		vec2 inset = min(vec2(0.5) / texture_size, vec2(0.5) / sheet_tiles);
		return clamp((coords + cell) / sheet_tiles, cell / sheet_tiles + inset, (cell + vec2(1.0)) / sheet_tiles - inset);
	}
	return coords;
}

void fragment() {
	vec2 uv = (UV - vec2(0.5)) * flip_uv_sign + vec2(0.5);
#if POWERBOX_PBR
	// Unity Standard 的金属、法线和发光共用 _MainTex_ST。
	vec2 coords = sampling_uv(uv * main_scale + main_offset, vec2(textureSize(main_texture, 0)));
	vec4 texel = texture(main_texture, coords);
	vec4 gloss = use_metallic_gloss ? texture(metallic_gloss_texture, coords) : vec4(0.0);
	ALBEDO = texel.rgb * tint.rgb;
	METALLIC = use_metallic_gloss ? gloss.r : metallic;
	ROUGHNESS = roughness;
	if (smoothness_albedo_alpha || use_metallic_gloss) {
		float smoothness = (smoothness_albedo_alpha ? texel.a : gloss.a) * gloss_map_scale;
		ROUGHNESS = 1.0 - clamp(smoothness, 0.0, 1.0);
	}
	if (use_bump) {
		// 共享资源保留 PNG 的 RG；网格 UV 翻 V 后，副切线与 Unity 相反。
		vec2 normal_xy = (texture(bump_texture, coords).rg * 2.0 - 1.0) * vec2(1.0, -1.0) * bump_scale;
		NORMAL_MAP = vec3(normal_xy * 0.5 + 0.5, 1.0);
	}
	if (use_emission) {
		EMISSION = texture(emission_texture, coords).rgb * emission_tint.rgb;
	}
#if POWERBOX_ALPHA_MODE != 0
	float alpha = (smoothness_albedo_alpha ? 1.0 : texel.a) * tint.a;
#if POWERBOX_ALPHA_MODE == 1
	if (alpha < cutoff) { discard; }
#else
	ALPHA = clamp(alpha, 0.0, 1.0);
#if POWERBOX_ALPHA_MODE == 3
	PREMUL_ALPHA_FACTOR = ALPHA;
#endif
#endif
#endif
#else
	vec2 background_uv = sampling_uv(uv * background_scale + background_offset, vec2(textureSize(background_texture, 0)));
	vec2 icon_uv = sampling_uv(uv * icon_scale + icon_offset, vec2(textureSize(icon_texture, 0)));
	vec4 icon = texture(icon_texture, icon_uv);
	vec3 particle = use_per_draw_data ? (draw_color * COLOR).rgb : COLOR.rgb;
	vec3 background_rgb = background_brightness * pow(texture(background_texture, background_uv).rgb, vec3(background_contrast)) * background_tint.rgb * particle;
	vec3 icon_rgb = pow(icon.rgb + icon_tint.rgb, vec3(icon_contrast)) * icon_brightness;
	ALBEDO = mix(background_rgb, icon_rgb, icon.a);
#endif
}
