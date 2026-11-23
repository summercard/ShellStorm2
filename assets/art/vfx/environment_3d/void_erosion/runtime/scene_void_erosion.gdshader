shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform mat4 world_to_volume;
uniform bool strict_box_bounds = false;
uniform vec3 half_size = vec3(4.5, 2.5, 4.5);
uniform float progress = 1.0;
uniform float cell_size = 0.55;
uniform float edge_width = 1.35;
uniform float edge_irregularity = 0.8;
uniform float rim_depth = 0.82;
uniform vec4 edge_color : source_color = vec4(0.73, 0.26, 1.0, 1.0);
uniform vec4 nebula_color : source_color = vec4(0.39, 0.19, 0.95, 1.0);
uniform vec4 warm_accent : source_color = vec4(1.0, 0.56, 0.67, 1.0);
uniform vec3 interior_axis = vec3(-0.4, -0.68, -0.62);
uniform float depth_scale = 1.0;
uniform int cube_count = 12;
uniform int far_cube_count = 10;
uniform float drift_speed = 0.5;
uniform float star_density = 0.82;
uniform bool fill_aperture_only = false;

varying vec3 surface_in_volume;
varying vec3 normal_in_volume;

float hash_cell(vec3 cell) {
	vec3 p = fract(cell * vec3(0.1031, 0.11369, 0.13787));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float floor_noise = mix(
		mix(hash_cell(cell), hash_cell(cell + vec3(1.0, 0.0, 0.0)), f.x),
		mix(hash_cell(cell + vec3(0.0, 1.0, 0.0)), hash_cell(cell + vec3(1.0, 1.0, 0.0)), f.x),
		f.y
	);
	cell.z += 1.0;
	float ceiling_noise = mix(
		mix(hash_cell(cell), hash_cell(cell + vec3(1.0, 0.0, 0.0)), f.x),
		mix(hash_cell(cell + vec3(0.0, 1.0, 0.0)), hash_cell(cell + vec3(1.0, 1.0, 0.0)), f.x),
		f.y
	);
	return mix(floor_noise, ceiling_noise, f.z);
}

float box_distance(vec3 p, vec3 extent) {
	vec3 q = abs(p) - extent;
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float erosion_distance(vec3 cell, vec3 extent) {
	vec3 block = floor((cell + vec3(1.0, 2.0, -1.0)) / vec3(3.0, 4.0, 3.0));
	float coarse = hash_cell(block + vec3(29.0, 17.0, 5.0)) - 0.53;
	float grain = hash_cell(cell) - 0.48;
	float erosion = (coarse * 2.15 + grain * 0.68) * edge_irregularity * cell_size;
	float bevel = min(min(extent.x, min(extent.y, extent.z)) * 0.32, cell_size * 2.35);
	return box_distance((cell + 0.5) * cell_size, extent - bevel) - bevel + erosion;
}

vec3 grid_lines(vec3 p, vec3 aa, float width) {
	vec3 edge = abs(fract(p + 0.5) - 0.5);
	vec3 ink = 1.0 - smoothstep(max(vec3(width) - aa, 0.0), vec3(width) + aa, edge);
	return ink * (1.0 - smoothstep(vec3(0.18), vec3(0.5), aa));
}

vec2 ray_box(vec3 origin, vec3 reciprocal_ray, vec3 extent) {
	vec3 a = (-extent - origin) * reciprocal_ray;
	vec3 b = (extent - origin) * reciprocal_ray;
	vec3 enter = min(a, b);
	vec3 leave = max(a, b);
	return vec2(max(enter.x, max(enter.y, enter.z)), min(leave.x, min(leave.y, leave.z)));
}

float cube_edge(vec3 hit, vec3 extent, float width) {
	vec3 d = abs(abs(hit) - extent);
	// At a ray/box hit one of the three distances is already zero.
	float second = max(min(d.x, d.y), min(max(d.x, d.y), d.z));
	return 1.0 - smoothstep(width * 0.38, width * 1.6, second);
}

vec3 reciprocal(vec3 ray) {
	return 1.0 / mix(-max(abs(ray), 0.00001), max(abs(ray), 0.00001), step(0.0, ray));
}

vec2 rotate_pair(vec2 p, vec2 cs) {
	return vec2(cs.x * p.x - cs.y * p.y, cs.y * p.x + cs.x * p.y);
}

vec3 cube_local(vec3 p, vec2 yaw, vec2 pitch, vec2 roll) {
	p.xz = rotate_pair(p.xz, yaw);
	p.yz = rotate_pair(p.yz, pitch);
	p.xy = rotate_pair(p.xy, roll);
	return p;
}

bool voxel_present(ivec3 cell, int cells, ivec3 corner, int cut_style) {
	if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, ivec3(cells)))) {
		return false;
	}
	ivec3 d = abs(cell - corner);
	if (cells == 2) {
		return (d.x + d.y + d.z) > 0;
	}
	if (cut_style == 0) {
		// One missing corner and its three adjoining cells form a stepped chip.
		return d.x + d.y + d.z > 1;
	}
	if (cut_style == 1) {
		return !(d.x <= 1 && d.y == 0 && d.z <= 1);
	}
	return !(d.x == 0 && d.y <= 1 && d.z == 0)
		&& !(d.x == cells - 1 && d.y == 0 && d.z == 1);
}

vec3 first_axis(vec3 t) {
	return t.x <= min(t.y, t.z) ? vec3(1.0, 0.0, 0.0) :
		(t.y <= t.z ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0));
}

vec4 trace_voxels(vec3 origin, vec3 ray, vec2 bounds, float unit, int cells, ivec3 corner, int cut_style) {
	float size = unit * float(cells) * 0.5;
	float t = bounds.x;
	vec3 entry = origin + ray * t;
	vec3 axis = first_axis(vec3(size) - abs(entry));
	vec3 head = entry + ray * unit * 0.00015;
	ivec3 cell = clamp(ivec3(floor((head + size) / unit)), ivec3(0), ivec3(cells - 1));
	vec3 direction = sign(ray);
	vec3 inverse_speed = abs(reciprocal(ray));
	vec3 boundary = (vec3(cell) + step(vec3(0.0), ray)) * unit - size;
	vec3 crossing = t + max((boundary - entry) * direction, vec3(unit * 0.00001)) * inverse_speed;
	vec3 stride = unit * inverse_speed;
	for (int i = 0; i < 12; i++) {
		if (voxel_present(cell, cells, corner, cut_style)) {
			return vec4(axis, t);
		}
		axis = first_axis(crossing);
		t = dot(crossing, axis);
		if (t >= bounds.y - unit * 0.00003) {
			break;
		}
		cell += ivec3(axis * direction);
		crossing += axis * stride;
	}
	return vec4(0.0, 0.0, 0.0, -1.0);
}

vec3 spatial_stars(vec3 origin, vec3 ray, float opening_depth, float footprint,
		float cube_depth, out vec3 in_front) {
	in_front = vec3(0.0);
	if (ray.z <= 0.18 || star_density <= 0.0) {
		return vec3(0.0);
	}
	vec3 stars = vec3(0.0);
	float band_depth = 1.12;
	for (int i = 0; i < 8; i++) {
		float band = float(i);
		float center_depth = opening_depth + band_depth;
		float spacing = 0.39 + band_depth * 0.021;
		float travel = (center_depth - origin.z) / ray.z;
		vec2 bin = floor((origin.xy + ray.xy * travel) / spacing);
		vec3 key = vec3(bin, 17.0 + band * 3.0);
		float seed = hash_cell(key);
		if (seed < 1.0 - star_density * mix(0.54, 0.82, band / 7.0)) {
			band_depth *= 1.60;
			continue;
		}
		vec3 jitter = vec3(hash_cell(key + 11.7), hash_cell(key + 23.3), hash_cell(key + 39.6));
		vec2 xy = (bin + mix(vec2(0.25), vec2(0.75), jitter.xy)) * spacing;
		// The center lives inside this depth interval, with a stable Z as well as XY.
		vec3 to_center = vec3(xy, center_depth + (jitter.z - 0.5) * spacing * 0.13) - origin;
		float along = dot(to_center, ray);
		vec3 miss = to_center - ray * along;
		float radius = spacing * mix(0.012, 0.040, jitter.z * jitter.z);
		float pixel = footprint * (0.76 + along * 0.18);
		float widened = max(radius, pixel * 0.62);
		float profile = exp(-dot(miss, miss) / max(widened * widened, 0.00000001) * 1.75);
		float coverage = min(1.0, radius / widened);
		float shade = mix(0.27, 1.0, seed * seed) * coverage * mix(0.63, 0.27, band / 7.0);
		vec3 cold = mix(nebula_color.rgb, vec3(0.51, 0.65, 0.95), 0.60);
		vec3 warm = mix(warm_accent.rgb, vec3(0.96, 0.75, 0.64), 0.44);
		vec3 light = mix(cold, warm, jitter.x * (1.0 - band * 0.073)) * profile * shade;
		if (along < cube_depth) {
			in_front += light;
		} else {
			stars += light;
		}
		band_depth *= 1.60;
	}
	float angle_fade = smoothstep(0.18, 0.42, ray.z);
	in_front *= angle_fade;
	return stars * angle_fade;
}

// Trace through the surface grid as if each surviving tile extended into the opening.
// Its depth varies per cell, while the visible cut still starts at the original mesh.
vec4 trace_rim(vec3 p, vec3 ray, vec3 normal, vec3 cell, vec3 extent, float pixel_size) {
	if (rim_depth <= 0.0) {
		return vec4(0.0);
	}
	vec3 facing = dot(normal, ray) > 0.0 ? -normal : normal;
	float into_surface = max(-dot(facing, ray), 0.015);
	vec3 tangent = ray - facing * dot(facing, ray);
	vec3 direction = sign(tangent);
	vec3 inverse_speed = abs(reciprocal(tangent));
	vec3 next_boundary = (cell + step(vec3(0.0), tangent)) * cell_size;
	vec3 crossing = max((next_boundary - p) * direction, vec3(0.00003)) * inverse_speed;
	vec3 stride = cell_size * inverse_speed;
	// Search only the strip next to the actual opening. Grooves deep inside the
	// opening otherwise see an invented continuation of their own tiny side face.
	float tangent_limit = cell_size * 3.6 / max(length(tangent), 0.001);
	float cutoff = min(rim_depth * 1.66 / into_surface, tangent_limit);
	for (int i = 0; i < 12; i++) {
		vec3 crossed = first_axis(crossing);
		float t = dot(crossing, crossed);
		if (t > cutoff) {
			break;
		}
		cell += direction * crossed;
		crossing += stride * crossed;
		if (erosion_distance(cell, extent) < 0.0) {
			continue;
		}
		float seed = hash_cell(cell + vec3(5.0, 12.0, -3.0));
		float thickness = rim_depth * mix(0.28, 1.66, pow(seed, 1.65));
		float depth = t * into_surface;
		if (depth > thickness) {
			continue;
		}
		vec3 point = p + tangent * t;
		vec3 along_face = cross(facing, crossed);
		float side = dot(point, along_face) / cell_size;
		float width = clamp(pixel_size / cell_size * 0.85, 0.009, 0.18);
		vec3 grid = grid_lines(vec3(side, depth / cell_size, side * 3.0), vec3(width), 0.018);
		float lip = exp(-depth / max(pixel_size * 1.6, 0.022));
		float crest = exp(-depth / max(thickness * 0.28, 0.026));
		float end_edge = exp(-abs(thickness - depth) / max(pixel_size * 0.70, 0.018));
		float side_light = 0.32 + dot(crossed, vec3(0.21, 0.44, 0.10));
		float local_warmth = 0.12 + seed * seed * 0.60;
		vec3 body = mix(nebula_color.rgb * 0.62, edge_color.rgb, crest * 0.56);
		vec3 light = mix(edge_color.rgb, warm_accent.rgb, local_warmth);
		vec3 emission = body * side_light * (0.14 + 0.37 * crest);
		emission += light * (lip * (0.43 + seed * 0.86) + grid.x * 0.21 + grid.y * 0.16 + grid.z * 0.07);
		emission += nebula_color.rgb * end_edge * 0.24;
		float opacity = (0.63 + 0.33 * crest) * (1.0 - smoothstep(0.77, 1.04, depth / thickness) * 0.53);
		return vec4(emission, opacity);
	}
	return vec4(0.0);
}

vec3 sample_mist(vec3 origin, vec3 ray, float distance, out float transmission) {
	vec3 scattered = vec3(0.0);
	transmission = 1.0;
	float previous = 0.0;
	for (int i = 0; i < 9; i++) {
		float index = float(i + 1) / 9.0;
		float end = distance * index * index;
		vec3 sample_point = origin + ray * mix(previous, end, 0.56);
		vec3 q = sample_point * vec3(1.20, 2.0, 0.54) + vec3(4.8, 9.8, 2.7);
		float swale = sin(sample_point.x * 1.93 + sample_point.z * 0.70) * 0.69;
		float ribbon = exp(-abs(sample_point.y + swale - sample_point.x * 0.34 + 0.24) * 2.65);
		float detail = noise3(q * 2.7 + vec3(3.1, -4.0, 1.2));
		float cloud = noise3(q) * 0.76 + detail * 0.24;
		float density = smoothstep(0.37, 0.84, cloud) * (0.006 + 0.58 * ribbon);
		float opacity = 1.0 - exp(-density * (end - previous));
		vec3 cool = mix(nebula_color.rgb, vec3(0.046, 0.072, 0.44), 0.47);
		vec3 hot = mix(edge_color.rgb, warm_accent.rgb, 0.38);
		vec3 radiance = mix(cool, hot, smoothstep(0.52, 0.90, detail) * ribbon * 0.73);
		scattered += radiance * opacity * transmission * (0.20 + 0.38 * cloud);
		transmission *= 1.0 - opacity;
		previous = end;
	}
	return scattered;
}

vec3 deep_space(vec3 point, vec3 ray, float pixel_size) {
	vec3 forward = normalize(interior_axis);
	vec3 reference = abs(forward.y) > 0.94 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(forward, reference));
	vec3 up = cross(right, forward);
	float span = max(2.0, max(half_size.x, max(half_size.y, half_size.z)));
	float clock = TIME * drift_speed;
	vec3 origin = point / span;
	mat3 volume_basis = transpose(mat3(right, up, forward));
	vec3 mist_origin = volume_basis * origin;
	vec3 mist_ray = volume_basis * ray;
	vec3 dark = vec3(0.0016, 0.0013, 0.008);
	float opening_depth = dot(half_size / span, abs(forward));
	float nearest = 24.0;
	float front_alpha = 0.0;
	vec3 front_color = vec3(0.0);
	vec3 front_light = vec3(0.0);
	vec3 accumulated_edges = vec3(0.0);
	float unit = cell_size / span;
	for (int i = 0; i < 24; i++) {
		bool far_band = i >= 12;
		if (!far_band && i >= cube_count) {
			continue;
		}
		if (far_band && i >= 12 + far_cube_count) {
			break;
		}
		float index = float(i);
		float seed = hash_cell(vec3(index + 0.9, 17.0, 6.0));
		int family = i % 3;
		int cells = 2 + int(step(0.38, seed)) + int(!far_band && i < 5 && seed > 0.62);
		float size = unit * float(cells) * 0.5;
		float phase = index * 2.39996;
		float home_depth = far_band ? 5.0 + seed * 6.3 : 0.24 + mod(index, 5.0) * 0.31 + step(5.0, index) * 0.95;
		float depth_sway = 0.15 * sin(clock * (0.43 + seed * 0.16) + phase * 1.3);
		float distance = opening_depth + size * 1.74 + unit * 1.8 + (home_depth + depth_sway) * depth_scale;
		float spread = (0.38 + distance * 0.29) * (0.39 + seed * 0.68);
		vec2 offset = vec2(cos(phase) * 1.2, sin(phase)) * spread;
		offset += vec2(sin(clock * 0.67 + phase), cos(clock * 0.49 + phase)) * (0.075 + seed * 0.087);
		vec3 center = forward * distance + right * offset.x + up * offset.y;
		vec3 delta = origin - center;
		vec3 lateral = delta - ray * dot(delta, ray);
		if (dot(lateral, lateral) > size * size * 3.0) {
			continue;
		}
		float yaw_angle = phase + sin(clock * 0.42 + phase) * 0.39;
		float pitch_angle = 0.21 + sin(phase * 1.14 + clock * 0.50) * 0.49;
		float roll_angle = sin(phase * 1.18 - clock * 0.36) * 0.54;
		vec2 yaw = vec2(cos(yaw_angle), sin(yaw_angle));
		vec2 pitch = vec2(cos(pitch_angle), sin(pitch_angle));
		vec2 roll = vec2(cos(roll_angle), sin(roll_angle));
		vec3 local_ray = cube_local(ray, yaw, pitch, roll);
		vec3 local_origin = cube_local(delta, yaw, pitch, roll);
		vec3 extent = vec3(size);
		vec2 bounds = ray_box(local_origin, reciprocal(local_ray), extent);
		if (bounds.x <= 0.007 || bounds.y <= bounds.x) {
			continue;
		}
		ivec3 corner = ivec3(step(vec3(0.5), vec3(seed, hash_cell(vec3(index, 2.0, 3.0)),
			hash_cell(vec3(index, 4.0, 9.0))))) * (cells - 1);
		vec4 hit = trace_voxels(local_origin, local_ray, bounds, unit, cells, corner, family);
		if (hit.w < 0.0) {
			continue;
		}
		vec3 front = local_origin + local_ray * hit.w;
		vec3 coord = (front + size) / unit;
		float width = clamp(pixel_size / span * (0.56 + hit.w * 0.14), unit * 0.014, unit * 0.17);
		vec3 face = hit.xyz;
		float face_light = dot(face, vec3(0.31, 0.86, 0.49));
		vec3 lines = grid_lines(coord, vec3(width / unit), 0.023) * (1.0 - face);
		vec3 fine = grid_lines(coord * 3.0, vec3(width / unit * 3.0), 0.012) * (1.0 - face);
		float panel = max(lines.x, max(lines.y, lines.z));
		float etched = max(fine.x, max(fine.y, fine.z));
		// Sample the adjoining tiles to light the cut silhouette as well as the outer edges.
		ivec3 cell = clamp(ivec3(floor(coord + local_ray * 0.00015)), ivec3(0), ivec3(cells - 1));
		ivec3 toward_edge = ivec3(mix(vec3(-1.0), vec3(1.0), step(0.5, coord - vec3(cell))));
		vec3 exposed = vec3(
			voxel_present(cell + ivec3(toward_edge.x, 0, 0), cells, corner, family) ? 0.0 : 1.0,
			voxel_present(cell + ivec3(0, toward_edge.y, 0), cells, corner, family) ? 0.0 : 1.0,
			voxel_present(cell + ivec3(0, 0, toward_edge.z), cells, corner, family) ? 0.0 : 1.0
		);
		float edge = max(cube_edge(front, extent, width), clamp(dot(exposed, lines), 0.0, 1.0));
		float bevel = max(cube_edge(front, extent, width * (1.8 + seed)), edge);
		float highlight = pow(clamp(dot(front / size, vec3(-0.39, 0.73, 0.47)) * 0.43 + 0.48, 0.0, 1.0), 2.5);
		float falloff = 1.0 / (1.0 + hit.w * 0.34 + hit.w * hit.w * 0.024);
		vec3 ice = mix(nebula_color.rgb, vec3(0.13, 0.27, 0.91), 0.40);
		vec3 tint = family == 0 ? ice : mix(edge_color.rgb, warm_accent.rgb, float(family - 1) * 0.29);
		vec3 warm = mix(tint, warm_accent.rgb, 0.10 + 0.58 * highlight);
		vec3 pane = dark + tint * (0.09 + face_light * 0.46) + warm * highlight * highlight * 0.16;
		vec3 glow = (tint * (bevel * 0.23 + panel * 0.22 + etched * 0.08)
			+ warm * edge * (0.58 + highlight * 1.9)) * falloff;
		accumulated_edges += glow;
		if (hit.w < nearest) {
			nearest = hit.w;
			front_alpha = (0.57 + 0.12 * float(family) + 0.20 * bevel) * falloff;
			front_color = pane;
			front_light = glow;
		}
	}
	float transmittance;
	float mist_distance = mix(14.0, clamp(nearest, 0.3, 14.0), front_alpha);
	vec3 mist = sample_mist(mist_origin, mist_ray, mist_distance, transmittance);
	vec3 in_front;
	float cube_depth = front_alpha > 0.0 ? nearest : 0.0;
	vec3 behind = spatial_stars(mist_origin, mist_ray, opening_depth, pixel_size / span, cube_depth, in_front);
	vec3 sky = dark + behind * transmittance + mist;
	return mix(sky, front_color + mist * 0.55, clamp(front_alpha, 0.0, 1.0))
		+ in_front * mix(0.62, 1.0, transmittance)
		+ front_light + max(accumulated_edges - front_light, vec3(0.0)) * (1.0 - front_alpha) * 0.72;
}

void vertex() {
	surface_in_volume = (world_to_volume * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_in_volume = mat3(world_to_volume) * (MODEL_NORMAL_MATRIX * NORMAL);
	// A millimetre-scale camera-depth lift keeps the overlay on its own mesh in Forward+.
	vec4 view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 clip = PROJECTION_MATRIX * view_position;
	vec4 lifted = PROJECTION_MATRIX * (view_position + vec4(0.0, 0.0, 0.0015, 0.0));
	if (lifted.w > 0.00001) {
		clip.z = lifted.z * clip.w / lifted.w;
	}
	POSITION = clip;
}

void fragment() {
	vec3 p = surface_in_volume;
	mat3 view_to_volume = mat3(world_to_volume * INV_VIEW_MATRIX);
	vec3 camera_forward = normalize(view_to_volume * vec3(0.0, 0.0, -1.0));
	vec3 view_ray = PROJECTION_MATRIX[3][3] > 0.5 ? vec3(0.0, 0.0, -1.0) : normalize(VERTEX);
	vec3 ray = normalize(view_to_volume * view_ray);
	// Start the interior on the same ray plane even where the wall is recessed or beveled.
	vec3 ray_start = p - ray * (dot(p, camera_forward) / max(dot(ray, camera_forward), 0.001));
	float ray_pixel_size = max(length(dFdx(ray_start)), length(dFdy(ray_start)));
	vec3 extent = half_size * progress;
	vec3 coordinates = p / cell_size;
	vec3 aa = max(fwidth(coordinates) * 0.65, vec3(0.002));
	float pixel_size = max(length(dFdx(p)), length(dFdy(p)));
	float bounds_distance = box_distance(p, extent);
	if (progress <= 0.0 || (strict_box_bounds && bounds_distance > 0.0) || bounds_distance > edge_width + cell_size * 2.1) {
		discard;
	}

	vec3 cell = floor(coordinates);
	float signed_distance = erosion_distance(cell, extent);
	float reveal = smoothstep(0.0, 0.075, progress);
	if (fill_aperture_only) {
		if (signed_distance >= 0.0) {
			discard;
		}
		ALBEDO = deep_space(ray_start, ray, ray_pixel_size);
		ALPHA = reveal;
	} else {
		if (signed_distance >= edge_width) {
			discard;
		}
		float inside = 1.0 - step(0.0, signed_distance);
		float rim = 1.0 - smoothstep(0.02, edge_width, abs(signed_distance));
		vec3 normal = normalize(normal_in_volume);
		vec3 n = abs(normal);
		vec3 axis_weight = 1.0 - pow(n, vec3(4.0));
		vec3 major = grid_lines(coordinates, aa, 0.023) * axis_weight;
		vec3 minor = grid_lines(coordinates * 3.0, aa * 3.0, 0.012) * axis_weight;
		vec3 neighbor = mix(vec3(-1.0), vec3(1.0), step(0.5, fract(coordinates)));
		vec3 other_side = vec3(
			erosion_distance(cell + vec3(neighbor.x, 0.0, 0.0), extent),
			erosion_distance(cell + vec3(0.0, neighbor.y, 0.0), extent),
			erosion_distance(cell + vec3(0.0, 0.0, neighbor.z), extent)
		);
		vec3 seam = major * abs(step(vec3(0.0), other_side) - vec3(1.0 - inside));
		float border = max(seam.x, max(seam.y, seam.z));
		float wire = max(major.x, max(major.y, major.z));
		float subgrid = max(minor.x, max(minor.y, minor.z));
		float tile = hash_cell(cell);
		float patch = hash_cell(floor(cell / 3.0) + vec3(2.0, 9.0, -15.0));
		float sparkle = pow(tile, 4.0) * (0.38 + 0.62 * patch);
		float pulse = 0.91 + sin(TIME * drift_speed * 1.3 + tile * 9.0) * 0.09;
		float surface_glass = rim * (0.14 + 0.34 * patch);
		vec3 cold = mix(nebula_color.rgb, edge_color.rgb, 0.43);
		vec3 hot = mix(edge_color.rgb, warm_accent.rgb, 0.20 + 0.44 * sparkle);
		vec3 rim_color = cold * (0.14 + 0.22 * tile + wire * (0.45 + patch * 0.58) + 0.17 * subgrid);
		rim_color += hot * border * (0.49 + 1.90 * sparkle + 0.34 * patch);
		vec3 color = rim_color * pulse;
		float opacity = max(border * (0.47 + 0.46 * patch), rim * (surface_glass + wire * 0.47 + subgrid * 0.09));
		if (inside > 0.5) {
			vec4 cut_wall = vec4(0.0);
			if (signed_distance > -cell_size * 2.5) {
				cut_wall = trace_rim(p, ray, normal, cell, extent, pixel_size);
			}
			color = mix(deep_space(ray_start, ray, ray_pixel_size), cut_wall.rgb, cut_wall.a);
			color += hot * border * (0.21 + 0.84 * sparkle);
			opacity = 1.0;
		}
		ALBEDO = color;
		ALPHA = clamp(opacity, 0.0, 1.0) * reveal;
	}
}
