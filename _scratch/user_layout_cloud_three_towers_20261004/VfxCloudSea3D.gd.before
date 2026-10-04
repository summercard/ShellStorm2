@tool
class_name VfxCloudSea3D
extends VfxEffectBase3D
## Scene-owned persistent outdoor cloud prefab. Geometry and placement are authored in the TSCN.
## Runtime only validates keepouts and advances bounded shader density; it never builds meshes.

const BUILDING_CLEARANCE_M := 1.5
const HEIGHT_CLEARANCE_M := 1.5
const PREVIEW_BOUNDARIES_PATH := "res://assets/art/vfx/environment_3d/cloud_sea/cloud_layout.json"

var _flow_time := 0.0
var _enabled := true
var _floor_99_y := -12.0
var _keepouts: Array[AABB] = []
var _volumes: Array[Dictionary] = []
var _rejected_count := 0
var _sun: DirectionalLight3D
var _baked_keepouts: Array[AABB] = []
var _mask_valid := true
var _quality_profile := "high"
var _keepout_regions: Array[String] = []
var _geometry_regions: Dictionary = {}
var _fallback_bounds: Array[AABB] = []
var _procedural_city_bounds: Array[AABB] = []
var _procedural_city_texture: ImageTexture
var _procedural_city_grid := Vector4.ZERO
var _procedural_static_enabled := true
var _procedural_candidates: ImageTexture3D
var _candidate_origin := Vector3.ZERO
var _candidate_step := Vector3.ONE
var _candidate_stats: Dictionary = {}
static var _candidate_cache: Dictionary = {}


func _ready() -> void:
	var frozen: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PREVIEW_BOUNDARIES_PATH))
	for item: Dictionary in frozen.get("keepouts", []):
		var lo: Array = item["min"]
		var hi: Array = item["max"]
		var origin := Vector3(float(lo[0]), float(lo[1]), float(lo[2]))
		var endpoint := Vector3(float(hi[0]), float(hi[1]), float(hi[2]))
		_baked_keepouts.append(AABB(origin, endpoint - origin).grow(BUILDING_CLEARANCE_M))
	# Local material copies prevent clocks/preview instances from changing another prefab.
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.material_override is ShaderMaterial:
			mesh_node.material_override = mesh_node.material_override.duplicate()
	configure(effect_color, effect_size, {})
	set_procedural_static_clearance_enabled(_procedural_static_enabled)
	if not Engine.is_editor_hint() and RuntimePerformanceManager != null:
		apply_performance_quality(RuntimePerformanceManager.quality_profile)
		RuntimePerformanceManager.quality_changed.connect(apply_performance_quality)
	set_process(true)


func _on_configure(context: Dictionary) -> void:
	_enabled = bool(context.get("enabled", true))
	_floor_99_y = float(context.get("floor_99_y", -12.0))
	var main_rect: Rect2 = context.get("main_tower_rect", Rect2(-50.0, -35.0, 100.0, 80.0))
	_keepouts.clear()
	_keepout_regions.clear()
	_geometry_regions.clear()
	# All-height exclusion also protects a cutaway interior or open door and rooftop rooms.
	_record_keepout(AABB(Vector3(main_rect.position.x, -100000.0, main_rect.position.y), Vector3(main_rect.size.x, 200000.0, main_rect.size.y)).grow(BUILDING_CLEARANCE_M), "main")
	var world_root := context.get("world_root") as Node3D
	if world_root != null:
		var route := world_root.get_node_or_null("Blocks/Rooftop/CrossTowerRoute")
		if route != null:
			for building in route.get_children():
				_collect_model_bounds(building, "route/" + str(building.name))
		var city_layout: Array = context.get("city_layout", [])
		for placement: Dictionary in city_layout:
			var placement_transform: Transform3D = placement["transform"]
			_record_keepout(_transformed_box(AABB(Vector3.ONE * -0.5, Vector3.ONE), placement_transform).grow(BUILDING_CLEARANCE_M), "city/" + str(placement.get("ring", 0)))
		_sun = world_root.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	else:
		_sun = null
		# Frozen authoring bounds are only used for the independent editor/preview prefab.
		var frozen: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PREVIEW_BOUNDARIES_PATH))
		for item: Dictionary in frozen.get("keepouts", []):
			var lo: Array = item["min"]
			var hi: Array = item["max"]
			var origin := Vector3(float(lo[0]), float(lo[1]), float(lo[2]))
			var endpoint := Vector3(float(hi[0]), float(hi[1]), float(hi[2]))
			_record_keepout(AABB(origin, endpoint - origin).grow(BUILDING_CLEARANCE_M), "frozen")
	_validate_volumes()
	visible = _enabled
	_sync_materials()


# 全域城市每格最多一栋：上传格点足迹/高度，避免合并成整片城市超级禁云盒。
func set_procedural_city_layout(layout: Array[Dictionary], config: Dictionary) -> void:
	var grid := int(float(config["extent_m"]) / float(config["spacing_m"]))
	var image := Image.create(grid, grid * 2, false, Image.FORMAT_RGBAF)
	image.fill(Color(0, 0, 0, 0))
	_procedural_city_bounds.clear()
	for placement in layout:
		var transform: Transform3D = placement["transform"]
		var box := _transformed_box(AABB(Vector3.ONE * -0.5, Vector3.ONE), transform).grow(BUILDING_CLEARANCE_M)
		_procedural_city_bounds.append(box)
		var x: int = placement["grid_x"]
		var z: int = placement["grid_z"]
		image.set_pixel(x, z, Color(box.position.x, box.position.z, box.end.x, box.end.z))
		image.set_pixel(x, z + grid, Color(box.position.y, box.end.y, 1.0, 0.0))
	_procedural_city_texture = ImageTexture.create_from_image(image)
	var center: Array = config["center_xz"]
	var half := float(config["extent_m"]) * 0.5
	_procedural_city_grid = Vector4(center[0] - half, center[1] - half, float(config["spacing_m"]), grid)
	_procedural_candidates = null
	if _procedural_static_enabled:
		_build_candidate_cache(layout, config, image)
	_sync_materials()


func set_procedural_static_clearance_enabled(enabled: bool) -> void:
	var shader := load("res://src/vfx/CloudStaticClearance.gdshader") as Shader if enabled else null
	_procedural_static_enabled = enabled and shader != null
	for volume in _volumes:
		var material := (volume["node"] as MeshInstance3D).material_override as ShaderMaterial
		if material == null:
			continue
		if _procedural_static_enabled and not material.has_meta("legacy_clearance_shader"):
			material.set_meta("legacy_clearance_shader", material.shader)
			material.shader = shader
		elif not _procedural_static_enabled and material.has_meta("legacy_clearance_shader"):
			material.shader = material.get_meta("legacy_clearance_shader") as Shader
			material.remove_meta("legacy_clearance_shader")
	if not _procedural_static_enabled:
		_procedural_candidates = null
		_candidate_stats = {"valid": false, "reason": "未启用或静态Shader加载失败，保留旧查询"}
	elif _procedural_candidates == null:
		_candidate_stats = {"valid": false, "reason": "启用后需重新set_procedural_city_layout以校验完整变换哈希"}
	_sync_materials()


func _build_candidate_cache(layout: Array[Dictionary], config: Dictionary, boxes: Image) -> void:
	var started := Time.get_ticks_usec()
	# 哈希含完整配置、世界变换和实际扩张包络；仅设置布局时计算，不扫描每帧。
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(["exact_candidates_v1", config, layout, _procedural_city_bounds]))
	var key := hashing.finish().hex_encode()
	if _candidate_cache.has(key):
		var cached: Dictionary = _candidate_cache[key]
		_procedural_candidates = cached["texture"]
		_candidate_origin = cached["origin"]
		_candidate_step = cached["step"]
		_candidate_stats = cached["stats"].duplicate()
		_candidate_stats["cache_hit"] = true
		_candidate_stats["setup_ms"] = (Time.get_ticks_usec() - started) / 1000.0
		return
	_procedural_candidates = null
	var grid := int(_procedural_city_grid.w)
	var spacing := _procedural_city_grid.z
	_candidate_step = Vector3(spacing / 4.0, 8.0, spacing / 4.0)
	_candidate_origin = Vector3(_procedural_city_grid.x - spacing, -112.0, _procedural_city_grid.y - spacing)
	var width := (grid + 2) * 4
	var depth := width
	var height := 22
	var slices: Array[Image] = []
	var histogram := [0, 0, 0, 0, 0, 0]
	# 单元与旧格点边界对齐，因此整单元共用同一个旧九格候选集合。
	for z in range(depth):
		var slice := Image.create(width, height, false, Image.FORMAT_RGBAF)
		for x in range(width):
			var slots: Array[int] = []
			var near_boxes: Array[AABB] = []
			var cell := Vector2i((x >> 2) - 1, (z >> 2) - 1)
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var slot := cell + Vector2i(dx, dz)
					if slot.x < 0 or slot.y < 0 or slot.x >= grid or slot.y >= grid:
						continue
					var h := boxes.get_pixel(slot.x, slot.y + grid)
					if h.b < 0.5:
						continue
					var f := boxes.get_pixel(slot.x, slot.y)
					slots.append(slot.y * grid + slot.x + 1)
					near_boxes.append(AABB(Vector3(f.r, h.r, f.g), Vector3(f.b - f.r, h.g - h.r, f.a - f.g)))
			for y in range(height):
				var lo := _candidate_origin + Vector3(x, y, z) * _candidate_step
				var hi := lo + _candidate_step
				var upper := 16.0
				for box in near_boxes:
					var farthest := (box.position - lo).max(hi - box.end).max(Vector3.ZERO)
					upper = minf(upper, farthest.length())
				var candidates: Array[int] = []
				for index in range(near_boxes.size()):
					var box := near_boxes[index]
					var nearest := (box.position - hi).max(lo - box.end).max(Vector3.ZERO)
					# 严格不等式加浮点保护带：平局与最近楼切换两边均保留。
					if nearest.length() <= upper + 0.001:
						candidates.append(slots[index])
				var encoded := Color(0, 0, 0, 0)
				if candidates.size() > 4:
					encoded.r = -1.0
					histogram[5] += 1
				else:
					for index in range(candidates.size()):
						encoded[index] = float(candidates[index])
					histogram[candidates.size()] += 1
				slice.set_pixel(x, y, encoded)
		slices.append(slice)
	var texture := ImageTexture3D.new()
	var error := texture.create(Image.FORMAT_RGBAF, width, height, depth, false, slices)
	_candidate_stats = {"key": key, "cache_hit": false, "setup_ms": (Time.get_ticks_usec() - started) / 1000.0, "bytes": width * height * depth * 16, "dimensions": [width, height, depth], "histogram_0_1_2_3_4_fallback": histogram, "valid": error == OK}
	if error == OK:
		_procedural_candidates = texture
		_candidate_cache.clear()
		_candidate_cache[key] = {"texture": texture, "origin": _candidate_origin, "step": _candidate_step, "stats": _candidate_stats.duplicate()}


func get_procedural_city_cache_snapshot() -> Dictionary:
	return _candidate_stats.duplicate(true)


func get_procedural_city_exclusion_bounds() -> Array[AABB]:
	return _procedural_city_bounds.duplicate()

func _record_keepout(bounds: AABB, region: String) -> void:
	_keepouts.append(bounds)
	_keepout_regions.append(region)
	_geometry_regions[region] = (_geometry_regions[region] as AABB).merge(bounds) if _geometry_regions.has(region) else bounds


func _collect_model_bounds(node: Node, region: String) -> void:
	# 地表不是整座城市禁云区；景观部件分开记录，禁止按父级合并巨大包络。
	if node.name == "OpenWorldGroundPlane":
		return
	if node.get_parent() != null and node.get_parent().name == "LandscapeFoundation":
		region += "/" + str(node.name)
	# Hidden rails are still excluded: a model visibility change must never permit clouds inside.
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			_record_keepout(_transformed_box(mesh_node.get_aabb(), mesh_node.global_transform).grow(BUILDING_CLEARANCE_M), region)
	for child in node.get_children():
		_collect_model_bounds(child, region)


func _validate_volumes() -> void:
	_volumes.clear()
	_rejected_count = 0
	_mask_valid = true
	_fallback_bounds.clear()
	var changed_regions: Dictionary = {}
	# Changed buildings receive a conservative analytic exclusion, keeping the rest visible.
	for index in range(_keepouts.size()):
		var keepout := _keepouts[index]
		var covered := false
		for baked in _baked_keepouts:
			if baked.grow(0.02).encloses(keepout):
				covered = true
				break
		if not covered:
			_mask_valid = false
			changed_regions[_keepout_regions[index]] = true
	for region in changed_regions:
		var bounds: AABB = _geometry_regions[region]
		if _fallback_bounds.size() < 16:
			_fallback_bounds.append(bounds)
		else:
			_fallback_bounds[15] = _fallback_bounds[15].merge(bounds)
	for group_name in ["CloudSea", "AirWisps"]:
		var group_node := get_node_or_null(NodePath(group_name))
		if group_node == null:
			continue
		for node in group_node.get_children():
			if not node is MeshInstance3D:
				continue
			var mesh_node := node as MeshInstance3D
			var bounds := _transformed_box(mesh_node.get_aabb(), mesh_node.global_transform)
			var safe := true
			if group_name == "CloudSea" and bounds.end.y > _floor_99_y - HEIGHT_CLEARANCE_M + 0.001:
				safe = false
			for keepout in _keepouts:
				if keepout.encloses(bounds):
					safe = false
					break
			mesh_node.visible = safe
			if group_name == "AirWisps" and _quality_profile == "low" and mesh_node.get_index() % 2 == 1:
				mesh_node.visible = false
			if not safe:
				_rejected_count += 1
			_volumes.append({"node": mesh_node, "kind": group_name, "bounds": bounds, "enabled": mesh_node.visible and _enabled})


func _process(delta: float) -> void:
	# Persistent environment VFX use lifetime=0. Scene ownership supplies their lifecycle.
	# Godot's inherited pause mode stops this clock while the game is paused.
	if not _enabled:
		return
	_flow_time += maxf(delta, 0.0)
	_sync_dynamic_materials()


func _sync_dynamic_materials() -> void:
	var daylight := clampf(_sun.light_energy / 3.0, 0.0, 1.0) if is_instance_valid(_sun) else 1.0
	var direction := _sun.global_basis.z.normalized() if is_instance_valid(_sun) else Vector3(-0.4, 0.8, 0.3).normalized()
	for volume in _volumes:
		var material := (volume["node"] as MeshInstance3D).material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter("flow_time", _flow_time)
			material.set_shader_parameter("daylight", daylight)
			material.set_shader_parameter("light_direction", direction)


func _sync_materials() -> void:
	var daylight := clampf(_sun.light_energy / 3.0, 0.0, 1.0) if is_instance_valid(_sun) else 1.0
	var regions := PackedVector4Array()
	for index in range(16):
		var bounds: AABB = _fallback_bounds[index] if index < _fallback_bounds.size() else AABB()
		regions.append(Vector4(bounds.position.x, bounds.position.y, bounds.position.z, 0.0))
		regions.append(Vector4(bounds.end.x, bounds.end.y, bounds.end.z, 0.0))
	for volume in _volumes:
		var mesh_node := volume["node"] as MeshInstance3D
		var material := mesh_node.material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter("flow_time", _flow_time)
			material.set_shader_parameter("daylight", daylight)
			material.set_shader_parameter("tint", Vector3(effect_color.r, effect_color.g, effect_color.b))
			material.set_shader_parameter("ray_steps", 40 if _quality_profile == "low" else 64 if _quality_profile == "balanced" else 96)
			material.set_shader_parameter("light_steps", 2 if _quality_profile == "low" else 3 if _quality_profile == "balanced" else 4)
			material.set_shader_parameter("light_direction", _sun.global_basis.z.normalized() if is_instance_valid(_sun) else Vector3(-0.4, 0.8, 0.3).normalized())
			material.set_shader_parameter("fallback_regions", regions)
			material.set_shader_parameter("fallback_count", _fallback_bounds.size())
			material.set_shader_parameter("procedural_city_enabled", _procedural_city_texture != null)
			if _procedural_city_texture != null:
				material.set_shader_parameter("procedural_city_boxes", _procedural_city_texture)
				material.set_shader_parameter("procedural_city_grid", _procedural_city_grid)
			material.set_shader_parameter("procedural_static_enabled", _procedural_static_enabled and _procedural_candidates != null)
			if _procedural_candidates != null:
				material.set_shader_parameter("procedural_candidates", _procedural_candidates)
				material.set_shader_parameter("candidate_origin", _candidate_origin)
				material.set_shader_parameter("candidate_step", _candidate_step)


func apply_performance_quality(profile: String) -> void:
	_quality_profile = profile
	_validate_volumes()
	_sync_materials()


static func _transformed_box(box: AABB, placement: Transform3D) -> AABB:
	var result := AABB(placement * box.position, Vector3.ZERO)
	for index in range(8):
		result = result.expand(placement * box.get_endpoint(index))
	return result


func get_cloud_volumes() -> Array[Dictionary]:
	return _volumes.duplicate()


func get_exclusion_bounds() -> Array[AABB]:
	return _keepouts.duplicate()


func get_fallback_bounds() -> Array[AABB]:
	return _fallback_bounds.duplicate()


func get_presentation_snapshot() -> Dictionary:
	var sea_count := 0
	var wisp_count := 0
	for volume in _volumes:
		if not bool(volume["enabled"]):
			continue
		if str(volume["kind"]) == "CloudSea":
			sea_count += 1
		else:
			wisp_count += 1
	return {"enabled": _enabled, "sea_count": sea_count, "wisp_count": wisp_count,
		"flow_time": _flow_time, "rejected_count": _rejected_count,
		"keepout_count": _keepouts.size(), "floor_99_y": _floor_99_y,
		"mask_valid": _mask_valid, "fallback_count": _fallback_bounds.size(), "quality_profile": _quality_profile}
