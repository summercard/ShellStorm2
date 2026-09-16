extends Node
## 一次性探针：实测 98F 入口安全房 门墙/门扇/碰撞 的运行时锚点（基准坐标）。
## 目的：回答"换资产时能不能定位到基准坐标"。只读，不改游戏状态。

const TARGET_ROOM := "floor_01_entry"


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await _settle()

	tower.force_enter_room_for_test(TARGET_ROOM)
	await _settle()

	var room_by_id := tower.get("_room_by_id") as Dictionary
	var room := room_by_id.get(TARGET_ROOM) as DungeonRoom3D
	if room == null:
		print("!! 找不到房间 ", TARGET_ROOM)
		get_tree().quit(1)
		return
	room.ensure_shell_built()
	await _settle()

	print("")
	print("############ A. 房间锚点 ############")
	print("room_id      = ", room.room_id)
	print("room_type    = ", room.room_type)
	print("dimensions   = ", room.get_dimensions())
	print("doors        = ", room.doors)
	print("door_targets = ", room.door_targets)
	print("local  position   = ", room.position)
	print("local  rotation.y = ", room.rotation.y)
	print("GLOBAL position   = ", room.global_position)
	print("GLOBAL rotation.y = ", room.global_rotation.y)
	print("parent           = ", room.get_parent().name if room.get_parent() != null else "-")

	print("")
	print("############ B. 门位 meta（房间自己写的） ############")
	for d in ["north", "south", "east", "west"]:
		var key := "tower_wall_door_offset_%s" % d
		if room.has_meta(key):
			print("  ", key, " = ", room.get_meta(key))
		else:
			print("  ", key, " = <无>")

	print("")
	print("############ C. 门墙模块 ############")
	var door_walls: Array[Node3D] = []
	for child in room.get_children():
		if str(child.name).begins_with("Imported_DoorWall5M"):
			door_walls.append(child as Node3D)
	for m in door_walls:
		print("--- ", m.name, " ---")
		print("  asset_id      = ", m.get_meta("asset_id", "-"))
		print("  direction     = ", m.get_meta("tower_wall_direction", "-"))
		print("  grid_unit_m   = ", m.get_meta("grid_unit_m", "-"))
		print("  local  position   = ", m.position)
		print("  local  rotation.y = ", m.rotation.y)
		print("  GLOBAL position   = ", m.global_position)
		print("  GLOBAL rotation.y = ", m.global_rotation.y)
		var box := _local_mesh_aabb(m)
		print("  prefab 视觉 AABB(局部): pos=", box.position.snappedf(0.001),
			"  end=", box.end.snappedf(0.001), "  size=", box.size.snappedf(0.001))
		print("  GLOBAL 视觉 AABB: pos=", _global_mesh_aabb(m).position.snappedf(0.001),
			"  end=", _global_mesh_aabb(m).end.snappedf(0.001))
		print("  子树:")
		_dump(m, 2)

	print("")
	print("############ D. 门扇（RoomDoor3D） ############")
	var leaves: Array[Node3D] = []
	for child in room.get_children():
		if str(child.name).begins_with("Door_"):
			leaves.append(child as Node3D)
	for d in leaves:
		print("--- ", d.name, " ---")
		print("  父节点        = ", d.get_parent().name)
		print("  local  position   = ", d.position)
		print("  local  rotation.y = ", d.rotation.y)
		print("  GLOBAL position   = ", d.global_position)
		print("  GLOBAL rotation.y = ", d.global_rotation.y)
		print("  子树:")
		_dump(d, 2)

	print("")
	print("############ E. 房间下门相关碰撞体 ############")
	for child in room.get_children():
		var s := str(child.name)
		if s.begins_with("TowerWallCollision") or s.begins_with("CameraOnlyDoorWall"):
			var b := child as Node3D
			print("--- ", s, " <", child.get_class(), "> ---")
			print("  local position   = ", b.position)
			print("  local rotation.y = ", b.rotation.y)
			print("  GLOBAL position  = ", b.global_position)
			if child is StaticBody3D:
				print("  layer=", (child as StaticBody3D).collision_layer,
					" mask=", (child as StaticBody3D).collision_mask)
			print("  子树:")
			_dump(child, 2)

	print("")
	print("############ F. 分组统计 ############")
	var found := 0
	var stack: Array[Node] = [room]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if not n.get_groups().is_empty():
			print("  ", n.name, "  groups=", n.get_groups())
			found += 1
		for c in n.get_children():
			stack.append(c)
	print("  带分组的节点数 = ", found)

	get_tree().quit(0)


func _local_mesh_aabb(root: Node) -> AABB:
	var acc := AABB()
	var found := false
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mi := value as MeshInstance3D
		if mi.mesh == null:
			continue
		var local_aabb := mi.transform * mi.mesh.get_aabb()
		acc = local_aabb if not found else acc.merge(local_aabb)
		found = true
	return acc


func _global_mesh_aabb(root: Node) -> AABB:
	var acc := AABB()
	var found := false
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mi := value as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := mi.global_transform * mi.mesh.get_aabb()
		acc = b if not found else acc.merge(b)
		found = true
	return acc


func _dump(node: Node, depth: int) -> void:
	var indent := ""
	for i in depth:
		indent += "  "
	var extra := ""
	if node is Node3D:
		var n3 := node as Node3D
		extra = " pos=(%.3f,%.3f,%.3f) rot_y=%.4f" % [
			n3.position.x, n3.position.y, n3.position.z, n3.rotation.y
		]
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is BoxMesh:
		var sz := ((node as MeshInstance3D).mesh as BoxMesh).size
		extra += " boxMesh=(%.3f,%.3f,%.3f)" % [sz.x, sz.y, sz.z]
	if node is CollisionShape3D and (node as CollisionShape3D).shape is BoxShape3D:
		var sz2 := ((node as CollisionShape3D).shape as BoxShape3D).size
		extra += " boxShape=(%.3f,%.3f,%.3f)" % [sz2.x, sz2.y, sz2.z]
	if node is StaticBody3D:
		var sb := node as StaticBody3D
		extra += " layer=%d mask=%d" % [sb.collision_layer, sb.collision_mask]
	print(indent, node.name, " <", node.get_class(), ">", extra)
	for c in node.get_children():
		_dump(c, depth + 1)


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout
