extends Node
## 一次性探针：打印 98F 入口安全房 南门 的运行时节点树与碰撞构成。
## 只读，不修改任何游戏状态。

const TARGET_ROOM := "floor_01_entry"


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await _settle()

	# 触发 98F 入口安全房（floor_01_entry）的壳体构建
	tower.force_enter_room_for_test(TARGET_ROOM)
	await _settle()

	var room_by_id := tower.get("_room_by_id") as Dictionary
	var room := room_by_id.get(TARGET_ROOM) as DungeonRoom3D
	if room == null:
		print("!! 找不到房间 ", TARGET_ROOM, "  keys=", room_by_id.keys())
		get_tree().quit(1)
		return
	room.ensure_shell_built()
	await _settle()

	print("")
	print("================================================================")
	print("房间 ", room.room_id, "  type=", room.room_type, "  dims=", room.get_dimensions())
	print("doors=", room.doors, "  door_targets=", room.door_targets)
	print("================================================================")

	# 打印房间直接子节点里与门/墙相关的
	print("\n--- 房间直接子节点（门/墙/碰撞相关） ---")
	for child in room.get_children():
		var n := child.name
		var s := str(n)
		if s.findn("door") >= 0 or s.findn("wall") >= 0 or s.findn("camera") >= 0:
			print("  ", s, "  <", child.get_class(), ">  pos=", (child as Node3D).position if child is Node3D else "-")

	# 打印每个 Door_* 子树的完整结构
	print("\n--- Door_* 门扇子树 ---")
	for child in room.get_children():
		if str(child.name).begins_with("Door_"):
			_dump(child, 0)

	# 打印每个 Imported_DoorWall5M_* 子树的完整结构
	print("\n--- Imported_DoorWall5M_* 门墙子树 ---")
	for child in room.get_children():
		if str(child.name).begins_with("Imported_DoorWall5M"):
			_dump(child, 0)

	# 统计
	print("\n--- 统计 ---")
	var door_walls: Array[Node] = []
	var door_leaves: Array[Node] = []
	for child in room.get_children():
		if str(child.name).begins_with("Imported_DoorWall5M"):
			door_walls.append(child)
		if str(child.name).begins_with("Door_"):
			door_leaves.append(child)
	print("门墙模块数 = ", door_walls.size(), "   门扇数 = ", door_leaves.size())
	for dw in door_walls:
		print("  门墙 ", dw.name, " 递归节点数 = ", _count(dw), "  asset_id=", dw.get_meta("asset_id", "-"))
	for dl in door_leaves:
		print("  门扇 ", dl.name, " 递归节点数 = ", _count(dl), "  父节点=", dl.get_parent().name)

	# Godot 分组检查
	print("\n--- Godot 分组（add_to_group） ---")
	var grouped := 0
	var stack: Array[Node] = [room]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if not n.get_groups().is_empty():
			print("  ", n.name, " groups=", n.get_groups())
			grouped += 1
		for c in n.get_children():
			stack.append(c)
	if grouped == 0:
		print("  （无）")

	get_tree().quit(0)


func _dump(node: Node, depth: int) -> void:
	var indent := ""
	for i in depth:
		indent += "    "
	var extra := ""
	if node is Node3D:
		var n3 := node as Node3D
		extra = " pos=(%.3f,%.3f,%.3f) rot_y=%.4f" % [
			n3.position.x, n3.position.y, n3.position.z, n3.rotation.y
		]
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var sz := Vector3.ZERO
		if mi.mesh is BoxMesh:
			sz = (mi.mesh as BoxMesh).size
		extra += " meshSize=(%.3f,%.3f,%.3f)" % [sz.x, sz.y, sz.z]
	if node is CollisionShape3D:
		var cs := node as CollisionShape3D
		var sz2 := Vector3.ZERO
		if cs.shape is BoxShape3D:
			sz2 = (cs.shape as BoxShape3D).size
		extra += " shapeSize=(%.3f,%.3f,%.3f)" % [sz2.x, sz2.y, sz2.z]
	if node is StaticBody3D:
		var sb := node as StaticBody3D
		extra += " layer=%d mask=%d" % [sb.collision_layer, sb.collision_mask]
	print(indent, node.name, "  <", node.get_class(), ">", extra)
	for c in node.get_children():
		_dump(c, depth + 1)


func _count(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _count(c)
	return n


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout
