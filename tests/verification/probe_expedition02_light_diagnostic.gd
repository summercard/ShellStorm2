extends Node
## 远征02远景光影运行时诊断：只读装配 + 受控出图。
## 不修改正式环境；黑环境样本仅用于拆分背景/雾/环境光贡献。

const LEVEL_SCENE := "res://scenes/ExpeditionLevel02_3D.tscn"
const OUT_DIR := "I:/工作项目/shellstrom2/ShellStorm2-work/expedition02_light_diagnostic"
const ROOM_IDS: Array[String] = ["room_01", "room_02"]

var _tower: TowerDescent3D
var _environment: Environment
var _sun: DirectionalLight3D
var _rooftop_sky_bounce: OmniLight3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var packed: PackedScene = load(LEVEL_SCENE) as PackedScene
	if packed == null:
		print("EXP02_LIGHT_DIAG_FAIL scene_load")
		get_tree().quit(1)
		return
	_tower = packed.instantiate() as TowerDescent3D
	_tower.test_mode = true
	_tower.run_seed_override = 20261013
	add_child(_tower)
	await _settle(14, 1.2)
	_environment = _find_environment(_tower)
	_sun = _find_sun(_tower)
	_rooftop_sky_bounce = _tower.get_node_or_null("TowerAtmosphere3D/RooftopSkyBounce") as OmniLight3D
	# 诊断期间冻结全局时间，避免 TowerAtmosphere3D 每帧重放太阳快照覆盖受控变量。
	if GameTimeManager != null:
		GameTimeManager.set_clock_running(false)
	_dump_global_runtime("initial")
	_dump_room_shells()
	_dump_lights()

	for room_id in ROOM_IDS:
		var room_by_id: Dictionary = _tower.get("_room_by_id")
		var room: DungeonRoom3D = room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			print("EXP02_LIGHT_DIAG_FAIL missing_room=%s" % room_id)
			continue
		_tower.player.global_position = room.global_position + Vector3(0.0, 0.05, 0.0)
		_tower.call("_on_room_entered", room)
		await _settle(6, 0.35)
		_dump_global_runtime("enter_%s" % room_id)
		await _capture_room_view(room_id, room)
		if room_id == "room_01" and _sun != null:
			var original_sun_energy: float = _sun.light_energy
			_sun.light_energy = 0.0
			await _settle(6, 0.35)
			await _capture_room_view("room_01_sun_off", room)
			_sun.light_energy = original_sun_energy

	# 受控对照：只把 Environment 的背景/雾/环境光压黑，局部灯和几何不动。
	# 若远处亮度随这组值同步下降，即证明亮源来自环境/雾，而不是远处漏出的局部灯。
	var original_background: Color = _environment.background_color
	var original_fog_color: Color = _environment.fog_light_color
	var original_fog_energy: float = _environment.fog_light_energy
	var original_ambient_energy: float = _environment.ambient_light_energy
	var original_fog_enabled: bool = _environment.fog_enabled
	_environment.background_color = Color.BLACK
	_environment.fog_light_color = Color.BLACK
	_environment.fog_light_energy = 0.0
	_environment.ambient_light_energy = 0.0
	_environment.fog_enabled = true
	await _settle(6, 0.35)
	_dump_global_runtime("black_environment_control")
	var room_by_id: Dictionary = _tower.get("_room_by_id")
	var room_02: DungeonRoom3D = room_by_id.get("room_02") as DungeonRoom3D
	if room_02 != null:
		await _capture_room_view("room_02_black_environment_control", room_02)
	_environment.background_color = original_background
	_environment.fog_light_color = original_fog_color
	_environment.fog_light_energy = original_fog_energy
	_environment.ambient_light_energy = original_ambient_energy
	_environment.fog_enabled = original_fog_enabled

	print("EXP02_LIGHT_DIAG_OK")
	get_tree().quit(0)


func _dump_global_runtime(stage: String) -> void:
	if _environment == null:
		print("LIGHT_DIAG stage=%s environment=<null>" % stage)
		return
	print("LIGHT_DIAG_ENV stage=%s background_mode=%d background=%s ambient_source=%d ambient_color=%s ambient_energy=%.6f fog_enabled=%s fog_color=%s fog_energy=%.6f fog_density=%.6f fog_height=%.6f fog_height_density=%.6f tonemap=%d exposure=%.6f" % [
		stage,
		_environment.background_mode,
		var_to_str(_environment.background_color),
		_environment.ambient_light_source,
		var_to_str(_environment.ambient_light_color),
		_environment.ambient_light_energy,
		_environment.fog_enabled,
		var_to_str(_environment.fog_light_color),
		_environment.fog_light_energy,
		_environment.fog_density,
		_environment.fog_height,
		_environment.fog_height_density,
		_environment.tonemap_mode,
		_environment.tonemap_exposure,
	])
	if _sun != null:
		print("LIGHT_DIAG_SUN stage=%s path=%s visible=%s energy=%.6f color=%s shadow=%s cull=%d caster=%d rotation=%s pos=%s" % [
			stage,
			str(_sun.get_path()),
			_sun.is_visible_in_tree(),
			_sun.light_energy,
			var_to_str(_sun.light_color),
			_sun.shadow_enabled,
			_sun.light_cull_mask,
			_sun.shadow_caster_mask,
			var_to_str(_sun.global_rotation_degrees),
			var_to_str(_sun.global_position),
		])


func _dump_room_shells() -> void:
	var room_by_id: Dictionary = _tower.get("_room_by_id")
	for room_id in ROOM_IDS:
		var room: DungeonRoom3D = room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			continue
		var ceiling_count := 0
		var ceiling_visible := 0
		var ceiling_aabb := AABB()
		var ceiling_found := false
		for node in room.find_children("*", "Node3D", true, false):
			var child: Node3D = node as Node3D
			if child == null or not str(child.name).begins_with("CEILING_"):
				continue
			ceiling_count += 1
			if child.is_visible_in_tree():
				ceiling_visible += 1
			var child_aabb: AABB = _node_aabb(child)
			if child_aabb.size != Vector3.ZERO:
				ceiling_aabb = child_aabb if not ceiling_found else ceiling_aabb.merge(child_aabb)
				ceiling_found = true
		print("LIGHT_DIAG_ROOM room=%s pos=%s size=%s ceiling_count=%d ceiling_visible=%d ceiling_aabb=%s" % [
			room_id,
			var_to_str(room.global_position),
			var_to_str(room.call("get_dimensions")),
			ceiling_count,
			ceiling_visible,
			var_to_str(ceiling_aabb),
		])


func _dump_lights() -> void:
	var counts: Dictionary = {"DirectionalLight3D": 0, "OmniLight3D": 0, "SpotLight3D": 0}
	for node in _tower.find_children("*", "Light3D", true, false):
		var light: Light3D = node as Light3D
		if light == null:
			continue
		var kind := light.get_class()
		counts[kind] = int(counts.get(kind, 0)) + 1
		var range_value := -1.0
		var spot_angle := -1.0
		if light is OmniLight3D:
			range_value = (light as OmniLight3D).omni_range
		elif light is SpotLight3D:
			range_value = (light as SpotLight3D).spot_range
			spot_angle = (light as SpotLight3D).spot_angle
		print("LIGHT_DIAG_LIGHT path=%s kind=%s visible=%s enabled=%s energy=%.6f color=%s cull=%d caster=%d shadow=%s pos=%s range=%.3f spot_angle=%.3f" % [
			str(light.get_path()),
			kind,
			light.is_visible_in_tree(),
			light.light_energy > 0.0,
			light.light_energy,
			var_to_str(light.light_color),
			light.light_cull_mask,
			light.shadow_caster_mask,
			light.shadow_enabled if light is DirectionalLight3D or light is OmniLight3D or light is SpotLight3D else false,
			var_to_str(light.global_position),
			range_value,
			spot_angle,
		])
	print("LIGHT_DIAG_LIGHT_COUNTS %s" % var_to_str(counts))


func _capture_room_view(tag: String, room: DungeonRoom3D) -> void:
	if DisplayServer.get_name() == "headless":
		print("LIGHT_DIAG_SHOT_SKIP tag=%s reason=headless_renderer" % tag)
		return
	var camera := Camera3D.new()
	camera.name = "LightDiagnosticCamera"
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 78.0
	camera.near = 0.05
	camera.far = 520.0
	_tower.add_child(camera)
	var center: Vector3 = room.global_position
	if tag.contains("room_01"):
		camera.global_position = Vector3(center.x - 2.5, center.y + 1.10, center.z + 5.5)
		camera.look_at(Vector3(center.x - 2.5, center.y + 0.80, center.z - 8.0), Vector3.UP)
	else:
		camera.global_position = Vector3(center.x + 3.6, center.y + 1.25, center.z + 20.0)
		camera.look_at(Vector3(center.x - 5.0, center.y + 1.05, center.z - 2.0), Vector3.UP)
	camera.make_current()
	await _settle(10, 0.0)
	var viewport_texture: ViewportTexture = get_viewport().get_texture()
	if viewport_texture == null:
		print("LIGHT_DIAG_SHOT_SKIP tag=%s reason=headless_viewport_texture_unavailable" % tag)
		camera.queue_free()
		return
	var image: Image = viewport_texture.get_image()
	if image == null:
		print("LIGHT_DIAG_SHOT_SKIP tag=%s reason=viewport_image_unavailable" % tag)
		camera.queue_free()
		return
	var out_path := "%s/%s.png" % [OUT_DIR, tag]
	var save_error := image.save_png(out_path)
	var stats: Dictionary = _image_stats(image)
	print("LIGHT_DIAG_SHOT tag=%s save_error=%d size=%dx%d mean_luma=%.6f upper_luma=%.6f center_luma=%.6f" % [
		tag, save_error, image.get_width(), image.get_height(),
		float(stats.get("mean_luma", 0.0)),
		float(stats.get("upper_luma", 0.0)),
		float(stats.get("center_luma", 0.0)),
	])
	camera.queue_free()


func _image_stats(image: Image) -> Dictionary:
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return {"mean_luma": 0.0, "upper_luma": 0.0, "center_luma": 0.0}
	var total := 0.0
	var upper := 0.0
	var center := 0.0
	var count := 0
	var upper_count := 0
	var center_count := 0
	for y in range(0, height, 8):
		for x in range(0, width, 8):
			var value: Color = image.get_pixel(x, y)
			var luma := value.r * 0.2126 + value.g * 0.7152 + value.b * 0.0722
			total += luma
			count += 1
			if y < height * 0.35:
				upper += luma
				upper_count += 1
			if x > width * 0.35 and x < width * 0.65 and y > height * 0.25 and y < height * 0.70:
				center += luma
				center_count += 1
	return {
		"mean_luma": total / float(count),
		"upper_luma": upper / float(upper_count),
		"center_luma": center / float(center_count),
	}


func _find_environment(root: Node) -> Environment:
	for node in root.find_children("*", "WorldEnvironment", true, false):
		var world: WorldEnvironment = node as WorldEnvironment
		if world != null and world.environment != null:
			return world.environment
	return null


func _find_sun(root: Node) -> DirectionalLight3D:
	for node in root.find_children("*", "DirectionalLight3D", true, false):
		return node as DirectionalLight3D
	return null


func _node_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var box: AABB = _mesh_world_aabb(mesh_instance)
		result = box if not found else result.merge(box)
		found = true
	return result if found else AABB()


func _mesh_world_aabb(mesh_instance: MeshInstance3D) -> AABB:
	var local_box: AABB = mesh_instance.get_aabb()
	var min_point := mesh_instance.global_transform * local_box.position
	var max_point := min_point
	for index in range(8):
		var corner := local_box.position + Vector3(
			local_box.size.x if (index & 1) != 0 else 0.0,
			local_box.size.y if (index & 2) != 0 else 0.0,
			local_box.size.z if (index & 4) != 0 else 0.0
		)
		var world_point := mesh_instance.global_transform * corner
		min_point = Vector3(minf(min_point.x, world_point.x), minf(min_point.y, world_point.y), minf(min_point.z, world_point.z))
		max_point = Vector3(maxf(max_point.x, world_point.x), maxf(max_point.y, world_point.y), maxf(max_point.z, world_point.z))
	return AABB(min_point, max_point - min_point)


func _settle(frames: int, seconds: float) -> void:
	for _index in range(frames):
		await get_tree().process_frame
		await get_tree().physics_frame
	if seconds > 0.0:
		await get_tree().create_timer(seconds).timeout
