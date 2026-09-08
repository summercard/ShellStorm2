extends Node
## Confirms the v021 door import changed only reusable visual prefabs.

const WALL_VISUAL: PackedScene = preload("res://assets/art/environments/base_facility_3d/runtime/env_base99_wall_door_5x9/env_base99_wall_door_5x9_root_top3d_v002.tscn")
const LIFT_VISUAL: PackedScene = preload("res://assets/art/environments/base_facility_3d/runtime/env_base99_door_lift_2p2x2p5/env_base99_door_lift_2p2x2p5_root_top3d_v002.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	_validate_visual_root(WALL_VISUAL, "ENV-BASE99-WALL-DOOR-5X9", "DungeonRoom3D + RoomDoor3D", failures)
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
	if str(visual.get_meta("visual_revision", "")) != "v021_shared_east_west_door_visuals":
		failures.append("视觉Prefab没有v021来源标识: %s" % visual.name)
	visual.queue_free()
