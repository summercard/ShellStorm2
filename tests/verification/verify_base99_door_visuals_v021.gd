extends Node
## Confirms the v021 door import changed only reusable visual prefabs.

const WALL_VISUAL: PackedScene = preload("res://assets/art/environments/base_facility_3d/runtime/env_base99_wall_door_5x12/env_base99_wall_door_5x12_root_top3d_v004.tscn")
const LIFT_VISUAL: PackedScene = preload("res://assets/art/environments/base_facility_3d/runtime/env_base99_door_lift_2p2x2p5/env_base99_door_lift_2p2x2p5_root_top3d_v002.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	_validate_visual_root(WALL_VISUAL, "ENV-BASE99-WALL-DOOR-5X12", "DungeonRoom3D + RoomDoor3D", failures)
	_validate_visual_root(LIFT_VISUAL, "ENV-BASE99-DOOR-LIFT-22X25", "RoomDoor3D", failures)
	if failures.is_empty():
		print("BASE99_DOOR_VISUALS_V021_OK: 4 packages -> 2 shared visual prefabs")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _validate_visual_root(scene: PackedScene, asset_id: String, collision_owner: String, failures: Array[String]) -> void:
	var visual := scene.instantiate() as Node3D
	add_child(visual)
	if str(visual.get_meta("asset_id", "")) != asset_id:
		failures.append("视觉Prefab AssetID错误: %s" % visual.name)
	if not bool(visual.get_meta("visual_only", false)):
		failures.append("视觉Prefab缺少visual_only: %s" % visual.name)
	if str(visual.get_meta("collision_owner", "")) != collision_owner:
		failures.append("碰撞职责被改变: %s" % visual.name)
	if not visual.find_children("*", "CollisionObject3D", true, false).is_empty():
		failures.append("视觉Prefab意外新增碰撞: %s" % visual.name)
	if visual.find_children("*", "MeshInstance3D", true, false).is_empty():
		failures.append("视觉Prefab没有导入网格: %s" % visual.name)
	if asset_id == "ENV-BASE99-WALL-DOOR-5X12":
		_validate_deep_runtime_metal(visual, failures)
		if not is_equal_approx(float(visual.get_meta("visual_height_m", 0.0)), 11.9):
			failures.append("带门墙可见高度不是11.9米")
	var expected_revision := (
		"v021_shared_east_west_door_visuals_height12"
		if asset_id == "ENV-BASE99-WALL-DOOR-5X12"
		else "v021_shared_east_west_door_visuals"
	)
	if str(visual.get_meta("visual_revision", "")) != expected_revision:
		failures.append("视觉Prefab没有v021来源标识: %s" % visual.name)
	visual.queue_free()


func _validate_deep_runtime_metal(visual: Node3D, failures: Array[String]) -> void:
	for item in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := item as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			if material == null or material.resource_name != "01_精工金属_紫色骨架":
				continue
			if material.metallic > 0.35 or material.roughness < 0.54:
				failures.append("带门墙高反射金属没有转换为游戏内深色金属")
			if material.albedo_color.r > 0.50:
				failures.append("带门墙主体亮度仍可能被日照推成白色")
			return
	failures.append("带门墙缺少主体金属材质")
