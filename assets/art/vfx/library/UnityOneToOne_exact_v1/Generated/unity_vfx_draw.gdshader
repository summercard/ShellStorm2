shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, fog_disabled;

#define VFX_SOFT 0
#define VFX_MIRROR 0

uniform sampler2D main_texture : source_color, filter_linear, repeat_enable;
uniform bool use_texture = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 texture_scale = vec2(1.0);
uniform vec2 texture_offset = vec2(0.0);
uniform vec2 sheet_tiles = vec2(1.0);
uniform int geometry_mode = 0;
uniform bool clamp_billboard_size = false;
uniform vec2 screen_limits = vec2(0.0, 1.0);
#if VFX_SOFT
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec2 soft_distances = vec2(0.0, 0.2);
#endif

varying flat float frame_slot;

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
	frame_slot = INSTANCE_CUSTOM.x;
	// Mesh/Local 和 ribbon 直接走 Godot 的真实模型矩阵，不重建朝向。
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
				// 正交实测使用 -camera_z；透视仍沿用逐粒子朝向，未与 Unity 对标。
				vec3 camera_forward = -toward_camera;
				// Z 反射反转叉积，Unity V=1 / Godot V=0 又对应 -H，两个负号抵消。
				vec3 side = normalize_or(cross(camera_forward, direction), vec3(0.0));
				// 保留旧屏幕尺寸钳制；该比例并非 Unity 已实证的钳制语义。
				float factor = screen_size_factor(length(MODEL_MATRIX[2].xyz), center_view, PROJECTION_MATRIX);
				vec3 width_axis = MODEL_MATRIX[1].xyz;
				float width = length(width_axis) * sign(dot(cross(direction, width_axis), MODEL_MATRIX[2].xyz));
				along = -signed_axis * factor;
				across = side * width * factor;
				// Quad 左侧 U0 在 P，右侧 U1 在尾部。
				center.xyz += 0.5 * along;
			}
			MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(along, 0.), vec4(across, 0.), vec4(camera_z, 0.), center);
		} else {
			vec3 size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
			mat3 rotation = particle_rotation(INSTANCE_CUSTOM.yzw);
			// Mesh/Facing is per particle even in an orthographic camera (Unity BakeMesh).
			vec3 z_axis = geometry_mode == 2 ? point_to_camera : camera_z;
			vec3 x_axis = normalize_or(cross(camera_y, z_axis), camera_x);
			vec3 y_axis = cross(z_axis, x_axis);
			// 先按粒子局部轴缩放和旋转，再落到对应的相机基底。
			float factor = clamp_billboard_size ? screen_size_factor(max(size.x, size.y), center_view, PROJECTION_MATRIX) : 1.0;
			mat3 axes = mat3(x_axis, y_axis, z_axis) * rotation;
			MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(axes[0] * size.x * factor, 0.), vec4(axes[1] * size.y * factor, 0.), vec4(axes[2] * size.z * factor, 0.), center);
		}
	}
}

void fragment() {
	vec4 texel = vec4(1.0);
	if (use_texture) {
		vec2 coords = UV * texture_scale + texture_offset;
		if (sheet_tiles.x * sheet_tiles.y > 1.0) {
			float frame = mod(round(frame_slot), sheet_tiles.x * sheet_tiles.y);
			vec2 cell = vec2(mod(frame, sheet_tiles.x), floor(frame / sheet_tiles.x));
			// UV 原点在左上；线性采样限制在该格的半像素内，避免串到邻帧。
			vec2 inset = min(vec2(0.5) / vec2(textureSize(main_texture, 0)), vec2(0.5) / sheet_tiles);
			coords = clamp((coords + cell) / sheet_tiles, cell / sheet_tiles + inset, (cell + vec2(1.0)) / sheet_tiles - inset);
		}
#if VFX_MIRROR
		coords = vec2(1.0) - abs(mod(coords, vec2(2.0)) - vec2(1.0));
#endif
		texel = texture(main_texture, coords);
	}
	vec4 result = texel * tint * COLOR;
#if VFX_SOFT
	float depth = texture(scene_depth, SCREEN_UV).r;
	if (depth > 0.0) {
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		ndc.z = depth * 2.0 - 1.0;
#endif
		vec4 opaque_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		float gap = VERTEX.z - opaque_view.z / opaque_view.w;
		result.a *= clamp((gap - soft_distances.x) / max(soft_distances.y - soft_distances.x, 1e-6), 0.0, 1.0);
	}
#endif
	ALBEDO = result.rgb;
	ALPHA = result.a;
}
