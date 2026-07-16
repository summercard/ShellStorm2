class_name BaseWorldAtmosphere
extends Node2D
## Code-native presentation layer for the fixed base/wilderness map.
## It owns no gameplay state or collision: every generated detail is a stable,
## semantic replacement point for future authored tiles, props and light sprites.

const WORLD_RECT := Rect2(-1800.0, -1600.0, 9400.0, 3200.0)
const ROAD_RECT := Rect2(450.0, -130.0, 6650.0, 260.0)
const DETAIL_SEED := 0x5E11_5702
const LIGHT_TEXTURE_SIZE := 128

const ASPHALT_EDGE := Color(0.055, 0.065, 0.070, 0.95)
const CRACK_COLOR := Color(0.025, 0.030, 0.034, 0.88)
const DUST_COLOR := Color(0.25, 0.22, 0.17, 0.25)
const METAL_DARK := Color(0.11, 0.12, 0.13, 1.0)
const METAL_RUST := Color(0.34, 0.18, 0.095, 0.9)

var _rng := RandomNumberGenerator.new()
var _cracks: Array[PackedVector2Array] = []
var _debris: Array[Dictionary] = []
var _road_patches: Array[Rect2] = []
var _ruin_foundations: Array[Dictionary] = []
var _light_profiles: Array[Dictionary] = []
var _lights: Array[PointLight2D] = []
var _atmosphere_overlay: CanvasLayer = null
var _elapsed := 0.0


func _ready() -> void:
	z_index = -9
	_rng.seed = DETAIL_SEED
	_build_detail_cache()
	_ensure_color_grade()
	_build_sparse_lights()
	_build_screen_atmosphere()
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	for index in range(_lights.size()):
		var light := _lights[index]
		if not is_instance_valid(light):
			continue
		var profile := _light_profiles[index]
		var base_energy := float(profile.get("energy", 0.75))
		var phase := float(profile.get("phase", 0.0))
		var flicker := float(profile.get("flicker", 0.08))
		var wave := sin(_elapsed * 2.15 + phase) * 0.55 + sin(_elapsed * 4.7 + phase * 1.7) * 0.20
		var energy := base_energy * (1.0 + wave * flicker)
		if bool(profile.get("broken", false)):
			var outage_cycle := fmod(_elapsed + phase * 1.9, float(profile.get("period", 7.5)))
			if outage_cycle < float(profile.get("outage", 0.22)):
				energy *= 0.08
		light.energy = maxf(0.02, energy)


func _draw() -> void:
	_draw_road_structure()
	_draw_base_plaza_damage()
	_draw_ruins()
	_draw_roadside_story_props()
	_draw_cached_damage()
	_draw_light_fixtures()


func _draw_road_structure() -> void:
	# Dark shoulders and interrupted, nearly erased lane markings.
	draw_line(Vector2(450, -137), Vector2(7100, -137), ASPHALT_EDGE, 14.0, true)
	draw_line(Vector2(450, 137), Vector2(7100, 137), ASPHALT_EDGE, 14.0, true)
	for x in range(650, 7050, 360):
		if x in [1370, 2810, 4250, 6050]:
			continue
		var alpha := 0.18 + float((x / 360) % 3) * 0.045
		draw_line(Vector2(x, 0), Vector2(x + 155, 0), Color(0.63, 0.58, 0.43, alpha), 5.0, true)

	# Broken drainage ditch and base perimeter communicate scale without walls.
	draw_dashed_line(Vector2(-1650, -955), Vector2(550, -955), Color(0.12, 0.28, 0.34, 0.44), 9.0, 32.0)
	draw_dashed_line(Vector2(550, -955), Vector2(550, 955), Color(0.12, 0.28, 0.34, 0.34), 9.0, 32.0)
	draw_dashed_line(Vector2(-1650, 955), Vector2(550, 955), Color(0.12, 0.28, 0.34, 0.44), 9.0, 32.0)

	# Contamination bands distinguish the four wilderness districts subtly.
	draw_rect(Rect2(650, -1450, 1700, 1230), Color(0.12, 0.19, 0.22, 0.12), true)
	draw_rect(Rect2(2100, 220, 1700, 1230), Color(0.38, 0.19, 0.07, 0.10), true)
	draw_rect(Rect2(3800, -1450, 1600, 1230), Color(0.13, 0.30, 0.16, 0.10), true)
	draw_rect(Rect2(5400, 220, 1850, 1230), Color(0.30, 0.09, 0.24, 0.10), true)


func _draw_base_plaza_damage() -> void:
	# Layered emergency markings break up the large plaza while keeping its safe,
	# navigable silhouette readable from the default camera.
	var plaza_outline := PackedVector2Array([
		Vector2(-1268, -216), Vector2(-732, -216), Vector2(-626, 0),
		Vector2(-732, 216), Vector2(-1268, 216), Vector2(-1374, 0), Vector2(-1268, -216),
	])
	draw_polyline(plaza_outline, Color(0.27, 0.43, 0.48, 0.27), 8.0, true)
	var inner_outline := PackedVector2Array([
		Vector2(-1220, -170), Vector2(-780, -170), Vector2(-690, 0),
		Vector2(-780, 170), Vector2(-1220, 170), Vector2(-1310, 0), Vector2(-1220, -170),
	])
	draw_polyline(inner_outline, Color(0.54, 0.48, 0.30, 0.16), 4.0, true)

	# Faded maintenance bays and repaired slab seams.
	for rect in [Rect2(-1245, -138, 155, 74), Rect2(-910, -138, 155, 74), Rect2(-1245, 64, 155, 74), Rect2(-910, 64, 155, 74)]:
		draw_rect(rect, Color(0.08, 0.10, 0.11, 0.30), true)
		draw_rect(rect, Color(0.40, 0.45, 0.43, 0.16), false, 3.0)
	for x in range(-1218, -1080, 24):
		draw_line(Vector2(x, -132), Vector2(x + 16, -68), Color(0.54, 0.34, 0.10, 0.18), 5.0, true)

	# Central service ring and cables leading to barely functioning facilities.
	draw_arc(Vector2(-1000, 0), 78.0, 0.0, TAU, 32, Color(0.31, 0.54, 0.62, 0.24), 5.0, true)
	draw_arc(Vector2(-1000, 0), 46.0, 0.35, TAU - 0.60, 24, Color(0.58, 0.52, 0.31, 0.18), 3.0, true)
	draw_circle(Vector2(-1000, 0), 13.0, Color(0.03, 0.04, 0.05, 0.74))
	for cable in [
		PackedVector2Array([Vector2(-1070, -42), Vector2(-1190, -105), Vector2(-1340, -196)]),
		PackedVector2Array([Vector2(-930, -42), Vector2(-790, -104), Vector2(-645, -196)]),
		PackedVector2Array([Vector2(-1070, 42), Vector2(-1200, 112), Vector2(-1360, 205)]),
		PackedVector2Array([Vector2(-930, 42), Vector2(-790, 112), Vector2(-640, 205)]),
	]:
		draw_polyline(cable, Color(0.025, 0.03, 0.035, 0.72), 5.0, true)

	# Concrete damage and small improvised power crates around the safe zone.
	for crack in [
		PackedVector2Array([Vector2(-1280, -70), Vector2(-1208, -45), Vector2(-1150, -12), Vector2(-1092, -26)]),
		PackedVector2Array([Vector2(-850, 15), Vector2(-805, 46), Vector2(-735, 58), Vector2(-682, 105)]),
		PackedVector2Array([Vector2(-1130, 175), Vector2(-1092, 122), Vector2(-1030, 104)]),
	]:
		draw_polyline(crack, Color(0.025, 0.03, 0.035, 0.72), 3.0, true)
	for crate_pos in [Vector2(-1315, 148), Vector2(-690, -145)]:
		draw_rect(Rect2(crate_pos - Vector2(28, 19), Vector2(56, 38)), Color(0.075, 0.085, 0.09, 1.0), true)
		draw_rect(Rect2(crate_pos - Vector2(23, 14), Vector2(46, 28)), Color(0.18, 0.20, 0.19, 0.82), false, 3.0)
		draw_circle(crate_pos + Vector2(15, -6), 3.0, Color(0.36, 0.78, 0.84, 0.65))


func _draw_ruins() -> void:
	for ruin in _ruin_foundations:
		var rect: Rect2 = ruin["rect"]
		var tint: Color = ruin["tint"]
		draw_rect(rect, Color(tint, 0.11), true)
		draw_rect(rect, Color(tint.lightened(0.18), 0.34), false, 5.0)
		var collapsed_side := int(ruin["side"])
		if collapsed_side % 2 == 0:
			draw_line(rect.position, rect.end, Color(tint, 0.28), 7.0, true)
		else:
			draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), Color(tint, 0.28), 7.0, true)
		# Sparse interior beams make foundations read as abandoned structures.
		draw_line(Vector2(rect.position.x + 24, rect.position.y + 28), Vector2(rect.end.x - 30, rect.position.y + 28), Color(0.08, 0.085, 0.09, 0.7), 8.0, true)


func _draw_roadside_story_props() -> void:
	# Wrecked convoy: readable silhouettes at the road scale.
	_draw_wreck(Vector2(2160, -230), -0.18, Color(0.18, 0.23, 0.24, 1.0))
	_draw_wreck(Vector2(5180, 265), 0.12, Color(0.27, 0.16, 0.10, 1.0))
	_draw_wreck(Vector2(6830, -245), -0.32, Color(0.13, 0.15, 0.17, 1.0))

	# Collapsed checkpoints and staggered barriers break the long road rhythm.
	_draw_barrier(Vector2(780, -170), -0.08)
	_draw_barrier(Vector2(3400, 185), 0.12)
	_draw_barrier(Vector2(5850, -175), -0.10)
	_draw_warning_sign(Vector2(1120, 215), Color(0.40, 0.58, 0.62, 1.0))
	_draw_warning_sign(Vector2(4070, -220), Color(0.45, 0.63, 0.31, 1.0))

	# Dead tree silhouettes make the open fields feel exposed rather than empty.
	for tree_pos in [Vector2(860, -930), Vector2(1880, -1110), Vector2(2640, 980), Vector2(3550, 1120), Vector2(4100, -980), Vector2(5320, -1170), Vector2(5710, 1030), Vector2(6990, 950)]:
		_draw_dead_tree(tree_pos)


func _draw_cached_damage() -> void:
	for patch in _road_patches:
		draw_rect(patch, Color(0.07, 0.075, 0.075, 0.62), true)
		draw_rect(patch, Color(0.31, 0.27, 0.20, 0.17), false, 2.0)
	for points in _cracks:
		draw_polyline(points, CRACK_COLOR, 3.0, true)
		if points.size() >= 3:
			var branch_origin := points[1]
			var branch_end := branch_origin + Vector2(18, -14).rotated(float(points[0].x) * 0.013)
			draw_line(branch_origin, branch_end, Color(CRACK_COLOR, 0.64), 1.5, true)
	for item in _debris:
		draw_set_transform(item["position"], float(item["rotation"]), Vector2.ONE)
		draw_rect(Rect2(-item["size"] * 0.5, item["size"]), item["color"], true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_light_fixtures() -> void:
	for profile in _light_profiles:
		var position: Vector2 = profile["position"]
		var color: Color = profile["color"]
		draw_line(position + Vector2(0, 8), position + Vector2(0, 62), METAL_DARK, 7.0, true)
		draw_line(position + Vector2(-3, 62), position + Vector2(16, 70), METAL_DARK, 5.0, true)
		draw_circle(position, 10.0, Color(0.03, 0.035, 0.04, 1.0))
		draw_circle(position, 5.0, Color(color, 0.95))
		draw_circle(position, 17.0, Color(color, 0.10))


func _draw_wreck(position: Vector2, rotation: float, body_color: Color) -> void:
	draw_set_transform(position, rotation, Vector2.ONE)
	draw_rect(Rect2(-64, -27, 128, 54), Color(0.015, 0.02, 0.022, 0.55), true)
	draw_colored_polygon(PackedVector2Array([Vector2(-58, -22), Vector2(38, -25), Vector2(60, -9), Vector2(52, 21), Vector2(-50, 24), Vector2(-66, 8)]), body_color)
	draw_rect(Rect2(-24, -18, 46, 31), body_color.lightened(0.12), true)
	draw_rect(Rect2(-17, -14, 31, 23), Color(0.045, 0.07, 0.08, 0.85), true)
	draw_circle(Vector2(-40, 25), 10.0, Color(0.025, 0.025, 0.025, 1.0))
	draw_circle(Vector2(38, 23), 10.0, Color(0.025, 0.025, 0.025, 1.0))
	draw_line(Vector2(-58, -10), Vector2(52, 11), METAL_RUST, 5.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_barrier(position: Vector2, rotation: float) -> void:
	draw_set_transform(position, rotation, Vector2.ONE)
	for offset in [-48.0, 0.0, 48.0]:
		draw_rect(Rect2(offset - 26, -10, 52, 20), Color(0.18, 0.20, 0.20, 1.0), true)
		draw_line(Vector2(offset - 20, -6), Vector2(offset + 18, 6), Color(0.58, 0.35, 0.12, 0.75), 5.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_warning_sign(position: Vector2, color: Color) -> void:
	draw_line(position, position + Vector2(0, 74), METAL_DARK, 6.0, true)
	var sign := PackedVector2Array([position + Vector2(-25, 6), position + Vector2(25, 6), position + Vector2(18, 43), position + Vector2(-18, 43)])
	draw_colored_polygon(sign, color.darkened(0.46))
	draw_polyline(PackedVector2Array([sign[0], sign[1], sign[2], sign[3], sign[0]]), Color(color, 0.76), 3.0, true)


func _draw_dead_tree(position: Vector2) -> void:
	var trunk := Color(0.10, 0.085, 0.065, 0.88)
	draw_line(position, position + Vector2(-5, -68), trunk, 8.0, true)
	draw_line(position + Vector2(-4, -38), position + Vector2(-34, -66), trunk, 5.0, true)
	draw_line(position + Vector2(-5, -52), position + Vector2(25, -84), trunk, 4.0, true)
	draw_line(position + Vector2(-25, -58), position + Vector2(-43, -78), trunk, 3.0, true)


func _build_detail_cache() -> void:
	for i in range(42):
		var x := _rng.randf_range(560.0, 7040.0)
		var y := _rng.randf_range(-112.0, 112.0)
		var length := _rng.randf_range(34.0, 105.0)
		var angle := _rng.randf_range(-0.75, 0.75)
		var start := Vector2(x, y)
		var points := PackedVector2Array([start])
		for segment in range(1, 4):
			points.append(start + Vector2(length * float(segment) / 3.0, _rng.randf_range(-13.0, 13.0)).rotated(angle))
		_cracks.append(points)

	for i in range(14):
		var x := _rng.randf_range(520.0, 7000.0)
		var y := _rng.randf_range(-95.0, 95.0)
		_road_patches.append(Rect2(x, y, _rng.randf_range(45.0, 120.0), _rng.randf_range(18.0, 44.0)))

	for i in range(96):
		var on_road := i < 38
		var position := Vector2(
			_rng.randf_range(520.0, 7150.0),
			_rng.randf_range(-125.0, 125.0) if on_road else _rng.randf_range(-1420.0, 1420.0)
		)
		if not on_road and absf(position.y) < 210.0:
			position.y += 320.0 * signf(position.y if position.y != 0.0 else 1.0)
		_debris.append({
			"position": position,
			"size": Vector2(_rng.randf_range(5.0, 22.0), _rng.randf_range(3.0, 11.0)),
			"rotation": _rng.randf_range(-PI, PI),
			"color": METAL_RUST if i % 4 == 0 else Color(DUST_COLOR, _rng.randf_range(0.24, 0.52)),
		})

	var ruin_specs := [
		Rect2(820, -1320, 430, 260), Rect2(1710, -620, 360, 250),
		Rect2(2360, 760, 450, 300), Rect2(3310, 430, 330, 230),
		Rect2(3900, -1280, 470, 280), Rect2(4870, -520, 360, 230),
		Rect2(5650, 760, 430, 300), Rect2(6650, 440, 390, 260),
	]
	for index in range(ruin_specs.size()):
		_ruin_foundations.append({
			"rect": ruin_specs[index],
			"tint": [Color(0.20, 0.28, 0.30), Color(0.34, 0.22, 0.13), Color(0.18, 0.30, 0.20), Color(0.28, 0.16, 0.27)][index % 4],
			"side": index,
		})


func _ensure_color_grade() -> void:
	var grade := CanvasModulate.new()
	grade.name = "WorldColorGrade"
	grade.color = Color(0.62, 0.68, 0.76, 1.0)
	add_child(grade)


func _build_sparse_lights() -> void:
	_light_profiles = [
		_light(Vector2(-1460, -610), Color(0.48, 0.82, 1.00), 0.62, 0.06, false, 1.1),
		_light(Vector2(-1010, -80), Color(0.52, 0.86, 1.00), 0.84, 0.04, false, 2.3),
		_light(Vector2(-580, 520), Color(0.45, 0.76, 0.94), 0.52, 0.10, true, 3.6),
		_light(Vector2(120, 0), Color(0.42, 0.68, 0.76), 0.38, 0.16, true, 5.0),
		_light(Vector2(980, 0), Color(0.72, 0.64, 0.42), 0.42, 0.20, true, 0.6),
		_light(Vector2(1470, -650), Color(0.38, 0.72, 1.00), 0.92, 0.07, false, 1.7),
		_light(Vector2(2370, 10), Color(0.90, 0.53, 0.20), 0.54, 0.18, true, 4.4),
		_light(Vector2(2970, 680), Color(1.00, 0.43, 0.13), 1.02, 0.12, true, 2.8),
		_light(Vector2(3770, -20), Color(0.54, 0.75, 0.36), 0.46, 0.16, true, 5.8),
		_light(Vector2(4570, -680), Color(0.42, 0.96, 0.48), 0.94, 0.10, false, 3.2),
		_light(Vector2(5350, 15), Color(0.76, 0.30, 0.43), 0.42, 0.20, true, 1.2),
		_light(Vector2(6170, 720), Color(0.92, 0.26, 0.74), 0.96, 0.10, true, 4.9),
		_light(Vector2(7000, -15), Color(0.48, 0.62, 0.72), 0.32, 0.22, true, 2.0),
	]
	var light_texture := _make_radial_light_texture()
	for index in range(_light_profiles.size()):
		var profile := _light_profiles[index]
		var light := PointLight2D.new()
		light.name = "SparseLight_%02d" % (index + 1)
		light.position = profile["position"]
		light.color = profile["color"]
		light.energy = profile["energy"]
		light.texture = light_texture
		light.texture_scale = float(profile.get("radius", 250.0)) / (LIGHT_TEXTURE_SIZE * 0.5)
		light.blend_mode = Light2D.BLEND_MODE_ADD
		light.shadow_enabled = false
		light.range_z_min = -4096
		light.range_z_max = 4096
		add_child(light)
		_lights.append(light)


func _light(position: Vector2, color: Color, energy: float, flicker: float, broken: bool, phase: float) -> Dictionary:
	return {
		"position": position,
		"color": color,
		"energy": energy,
		"flicker": flicker,
		"broken": broken,
		"phase": phase,
		"period": 6.5 + phase * 0.45,
		"outage": 0.16 + flicker * 0.8,
		"radius": 250.0 if position.x < 600.0 else 310.0,
	}


func _make_radial_light_texture() -> ImageTexture:
	var image := Image.create(LIGHT_TEXTURE_SIZE, LIGHT_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(LIGHT_TEXTURE_SIZE * 0.5, LIGHT_TEXTURE_SIZE * 0.5)
	var radius := LIGHT_TEXTURE_SIZE * 0.5
	for y in range(LIGHT_TEXTURE_SIZE):
		for x in range(LIGHT_TEXTURE_SIZE):
			var distance := Vector2(x, y).distance_to(center) / radius
			var strength := pow(clampf(1.0 - distance, 0.0, 1.0), 2.2)
			image.set_pixel(x, y, Color(strength, strength, strength, strength))
	return ImageTexture.create_from_image(image)


func _build_screen_atmosphere() -> void:
	_atmosphere_overlay = CanvasLayer.new()
	_atmosphere_overlay.name = "ScreenAtmosphere"
	_atmosphere_overlay.layer = 5
	add_child(_atmosphere_overlay)
	var overlay := ColorRect.new()
	overlay.name = "DustVignette"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float edge = smoothstep(0.28, 0.78, length(p * vec2(1.0, 0.82)));
	float grain = hash(floor(UV * vec2(420.0, 240.0)) + floor(TIME * 2.0));
	float drifting = sin((UV.y + TIME * 0.012) * 42.0 + sin(UV.x * 13.0)) * 0.5 + 0.5;
	float alpha = edge * 0.30 + drifting * 0.018 + grain * 0.012;
	COLOR = vec4(0.018, 0.030, 0.050, alpha);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	overlay.material = material
	_atmosphere_overlay.add_child(overlay)


func get_sparse_light_count() -> int:
	return _lights.size()


func get_zone_light_colors() -> Array[Color]:
	var colors: Array[Color] = []
	for profile in _light_profiles:
		var color: Color = profile["color"]
		if not colors.has(color):
			colors.append(color)
	return colors


func has_screen_atmosphere() -> bool:
	return _atmosphere_overlay != null and is_instance_valid(_atmosphere_overlay)


func get_detail_counts() -> Dictionary:
	return {
		"cracks": _cracks.size(),
		"debris": _debris.size(),
		"road_patches": _road_patches.size(),
		"ruins": _ruin_foundations.size(),
		"wrecks": 3,
		"barriers": 3,
	}
