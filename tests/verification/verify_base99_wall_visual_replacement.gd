extends Node
## 基地99层普通墙只替换表现层：验证正式GLB尺寸、无玩法节点、14段槽位，
## 并确认两个带门墙、四个墙角和既有门快照仍由原系统拥有。

const WALL_SCENE: PackedScene = preload(
	"res://assets/art/environments/base_facility_3d/runtime/env_base99_wall_plain_5x9/env_base99_wall_plain_5x9_root_top3d_v001.tscn"
)


func _ready() -> void:
	var failures: Array[String] = []
	_validate_standalone_wall(failures)
	await _validate_facility_shell(failures)
	if failures.is_empty():
		print("BASE99_WALL_VISUAL_REPLACEMENT_PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("BASE99_WALL_VISUAL_REPLACEMENT_FAIL: %s" % " | ".join(failures))
	get_tree().quit(1)


func _validate_standalone_wall(failures: Array[String]) -> void:
	var wall := WALL_SCENE.instantiate()
	add_child(wall)
	var meshes := wall.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1:
		failures.append("普通墙PackedScene不是单一整合视觉网格")
	else:
		var mesh_instance := meshes[0] as MeshInstance3D
		var bounds := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		if not bounds.size.is_equal_approx(Vector3(5.0, 9.0, 0.36)):
			failures.append("普通墙Godot包围盒不是5×9×0.36m: %s" % bounds.size)
		if not is_equal_approx(bounds.position.y, 0.0):
			failures.append("普通墙底部原点没有落在y=0: %s" % bounds.position.y)
		if mesh_instance.mesh.get_surface_count() != 2:
			failures.append("普通墙没有保留两种PaletteUV材质表面")
	if not wall.find_children("*", "CollisionObject3D", true, false).is_empty():
		failures.append("普通墙视觉PackedScene意外携带玩法碰撞")
	if not bool(wall.get_meta("visual_only", false)):
		failures.append("普通墙PackedScene缺少visual_only契约")
	wall.queue_free()


func _validate_facility_shell(failures: Array[String]) -> void:
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	if facility == null:
		failures.append("未生成99层基地房间")
	else:
		var snapshot := facility.get_room_snapshot()
		if int(snapshot.get("base99_wall_plain_instance_count", 0)) != 14:
			failures.append("基地普通墙不是14个5m视觉实例")
		if int(snapshot.get("tower_door_wall_module_count", 0)) != 2:
			failures.append("两个原有带门墙被改变")
		if int(snapshot.get("tower_corner_module_count", 0)) != 4:
			failures.append("四个原有L型墙角被改变")
		if (snapshot.get("door_snapshots", []) as Array).size() != 2:
			failures.append("基地两个门的运行时快照数量被改变")
	tower.queue_free()
	await get_tree().process_frame
