extends Node
## 定点诊断：room_10 → Boss 房门洞前 0.62 m 处到底是什么在挡人。

const EXP01_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 77001199


func _ready() -> void:
	call_deferred("probe")


func probe() -> void:
	var tower := EXP01_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	for _i in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame
	var room_10 := tower._room_by_id.get("room_10") as DungeonRoom3D
	var boss := tower._room_by_id.get("boss") as DungeonRoom3D
	var space := get_viewport().world_3d.direct_space_state
	var origin := Vector3(57.49, 0.0, -269.38)
	print("=== BLOCK 起点 %s ===" % str(origin))
	for height in [0.10, 0.30, 0.60, 1.00, 1.50, 2.00]:
		var from := Vector3(origin.x, origin.y + height, origin.z)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, 0.0, -3.0)))
		print("  y+%.2f → %s" % [height, "空" if hit.is_empty() else "%s @%s" % [
			str((hit.collider as Node).name), str(hit.position),
		]])
	# 扇形扫描：在门前 0.3 / 0.6 / 1.0 m 处横向扫
	for dz in [0.0, -0.3, -0.6, -1.0, -1.5]:
		var row: Array[String] = []
		for dx in [-2.4, -1.2, 0.0, 1.2, 2.4]:
			var from := Vector3(origin.x + dx, origin.y + 0.4, origin.z + dz)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, 0.0, -2.0)))
			row.append("空" if hit.is_empty() else str((hit.collider as Node).name))
		print("  z%+.1f → %s" % [dz, str(row)])
	# 近邻碰撞体枚举（世界 AABB 距该点 1.5 m 内）
	var near: Array[String] = []
	for value in get_tree().root.find_children("*", "CollisionShape3D", true, false):
		var shape := value as CollisionShape3D
		if shape.shape == null or shape.disabled:
			continue
		var body := shape.get_parent() as Node
		var layer := 0
		if body is CollisionObject3D:
			layer = (body as CollisionObject3D).collision_layer
		var aabb := shape.global_transform * shape.shape.get_debug_mesh().get_aabb()
		if aabb.position.distance_to(origin) > 4.0 and aabb.end.distance_to(origin) > 4.0:
			continue
		near.append("%s(layer=%d, y=%.2f..%.2f, z=%.2f..%.2f)" % [
			str(shape.get_path()).replace("/root/", ""), layer,
			aabb.position.y, aabb.end.y, aabb.position.z, aabb.end.z,
		])
	print("  近邻碰撞体 %d 个：" % near.size())
	for entry in near.slice(0, 24):
		print("     %s" % entry)
	print("BLOCK_DONE")
	get_tree().quit(0)
