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
	if not Engine.is_editor_hint() and RuntimePerformanceManager != null:
		apply_performance_quality(RuntimePerformanceManager.quality_profile)
		RuntimePerformanceManager.quality_changed.connect(apply_performance_quality)
	set_process(true)


func _on_configure(context: Dictionary) -> void:
	_enabled = bool(context.get("enabled", true))
	_floor_99_y = float(context.get("floor_99_y", -12.0))
	var main_rect: Rect2 = context.get("main_tower_rect", Rect2(-50.0, -35.0, 100.0, 80.0))
	_keepouts.clear()
	# All-height exclusion also protects a cutaway interior or open door and rooftop rooms.
	_keepouts.append(AABB(Vector3(main_rect.position.x, -100000.0, main_rect.position.y), Vector3(main_rect.size.x, 200000.0, main_rect.size.y)).grow(BUILDING_CLEARANCE_M))
	var world_root := context.get("world_root") as Node3D
	if world_root != null:
		var route := world_root.get_node_or_null("Blocks/Rooftop/CrossTowerRoute")
		if route != null:
			_collect_model_bounds(route)
		var city_layout: Array = context.get("city_layout", [])
		for placement: Dictionary in city_layout:
			var placement_transform: Transform3D = placement["transform"]
			_keepouts.append(_transformed_box(AABB(Vector3.ONE * -0.5, Vector3.ONE), placement_transform).grow(BUILDING_CLEARANCE_M))
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
			_keepouts.append(AABB(origin, endpoint - origin).grow(BUILDING_CLEARANCE_M))
	_validate_volumes()
	visible = _enabled
	_sync_materials()


func _collect_model_bounds(node: Node) -> void:
	# Hidden rails are still excluded: a model visibility change must never permit clouds inside.
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			_keepouts.append(_transformed_box(mesh_node.get_aabb(), mesh_node.global_transform).grow(BUILDING_CLEARANCE_M))
	for child in node.get_children():
		_collect_model_bounds(child)


func _validate_volumes() -> void:
	_volumes.clear()
	_rejected_count = 0
	_mask_valid = true
	# A changed building must be re-baked explicitly. Never trust a stale exclusion texture.
	for keepout in _keepouts:
		var covered := false
		for baked in _baked_keepouts:
			if baked.grow(0.02).encloses(keepout):
				covered = true
				break
		if not covered:
			_mask_valid = false
			break
	for group_name in ["CloudSea", "AirWisps"]:
		var group_node := get_node_or_null(NodePath(group_name))
		if group_node == null:
			continue
		for node in group_node.get_children():
			if not node is MeshInstance3D:
				continue
			var mesh_node := node as MeshInstance3D
			var bounds := _transformed_box(mesh_node.get_aabb(), mesh_node.global_transform)
			var safe := _mask_valid
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
	_sync_materials()


func _sync_materials() -> void:
	var daylight := clampf(_sun.light_energy / 3.0, 0.0, 1.0) if is_instance_valid(_sun) else 1.0
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
		"mask_valid": _mask_valid, "quality_profile": _quality_profile}
