extends Node
## 对照：99 与远征01 的 Boss 房**共享边侧**有没有门节点、美术门扇挡不挡人。

const LEVELS := [
	{"id": "99", "scene": "res://scenes/ExpeditionLevel99_3D.tscn"},
	{"id": "expedition_01", "scene": "res://scenes/ExpeditionLevel01_3D.tscn"},
]


func _ready() -> void:
	call_deferred("probe")


func probe() -> void:
	for value in LEVELS:
		var level := value as Dictionary
		await _dump(str(level.get("id", "")), str(level.get("scene", "")))
	print("LEAF_BLOCK_DONE")
	get_tree().quit(0)


func _dump(level_id: String, scene_path: String) -> void:
	var tower := (load(scene_path) as PackedScene).instantiate() as Dungeon3D
	tower.test_mode = true
	if tower is TowerDescent3D:
		(tower as TowerDescent3D).run_seed_override = 77001199
	add_child(tower)
	for _i in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame
	var boss := tower._room_by_id.get("boss") as DungeonRoom3D
	print("=== LEAF %s ===" % level_id)
	var door_nodes: Dictionary = boss.get("_door_nodes")
	var keys: Array[String] = []
	for key in door_nodes.keys():
		keys.append(str(key))
	print("  boss._door_nodes 侧 = %s" % str(keys))
	print("  boss.door_targets = %s" % str(boss.get("door_targets")))
	var leaves: Array[Node] = []
	for value in boss.find_children("*", "Node3D", true, false):
		if str(value.name).begins_with("外壳门扇_") or str(value.name).begins_with("外壳密封边"):
			leaves.append(value)
	print("  入口门扇/密封边节点 %d 个：" % leaves.size())
	for leaf in leaves:
		var bodies := leaf.find_children("*", "StaticBody3D", true, false)
		var layers: Array[String] = []
		for body in bodies:
			layers.append(str((body as StaticBody3D).collision_layer))
		print("     %-34s 世界=%s 碰撞层=%s parent=%s" % [
			str(leaf.name), str((leaf as Node3D).global_position), str(layers),
			str((leaf as Node3D).get_parent().name),
		])
	if not leaves.is_empty():
		var probe_point := (leaves[0] as Node3D).global_position
		var space := get_viewport().world_3d.direct_space_state
		var toward := Vector3(0.0, 0.0, 1.0) if level_id == "99" else Vector3(0.0, 0.0, -1.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			probe_point, probe_point + toward * 2.0
		))
		print("  穿过门扇射线 → %s" % ("空" if hit.is_empty() else str((hit.collider as Node).name)))
	tower.queue_free()
	await get_tree().process_frame


func _v(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]
