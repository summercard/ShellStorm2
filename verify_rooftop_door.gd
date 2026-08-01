extends Node
## 专门测试 rooftop (start) 门的功能和通过性

func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await _settle_long()
	tower.force_enter_room_for_test("start")
	await _settle_long()

	# 隐藏 HUD
	for child in tower.find_children("*", "CanvasLayer", true, false):
		(child as CanvasLayer).visible = false
	for child in tower.find_children("*", "Control", true, false):
		(child as Control).visible = false

	# 冻结玩家
	tower.player.set_physics_process(false)
	tower.player.set_process(false)
	tower.player.velocity = Vector3.ZERO

	var room_by_id := tower.get("_room_by_id") as Dictionary
	var rooftop: DungeonRoom3D = room_by_id.get("start") as DungeonRoom3D
	if rooftop == null:
		print("❌ 没有 start 房间")
		get_tree().quit(1)
		return

	rooftop.ensure_shell_built()
	await _settle_short()

	print("=== Rooftop 房间信息 ===")
	print("  size_class: %s" % rooftop.size_class)
	print("  doors: %s" % rooftop.doors)
	print("  dimensions: %s" % rooftop.get_dimensions())
	print("  _door_nodes: %s" % rooftop._door_nodes.keys())
	print("  _shell_built: %s" % rooftop._shell_built)

	# 检查门对象
	for direction in rooftop._door_nodes.keys():
		var door = rooftop._door_nodes[direction] as RoomDoor3D
		if door != null:
			print("  门 %s: direction=%s target=%s global_pos=%s rotation_y=%s" % [
				direction, door.direction, door.target_room_id, door.global_position, door.rotation.y
			])
			print("    is_open=%s collision.disabled=%s _collision=%s _panel=%s" % [
				door.is_open, (door._collision.disabled if door._collision != null else "null"),
				door._collision != null, door._panel != null
			])
			# door 自身的 local position
			print("    local_pos=%s 在房间内位置" % door.position)

	# 检查门旁边的墙
	print("\n=== Rooftop 子节点 ===")
	for child in rooftop.get_children():
		var name = child.name
		if name.begins_with("Door") or name.contains("wall") or name.contains("Wall") or name.contains("Railing"):
			print("  %s: type=%s global_pos=%s" % [name, child.get_class(), child.global_position])

	# 玩家走到 access_direction 门附近
	var access_dir := rooftop.doors[0] if rooftop.doors.size() > 0 else "west"
	print("\n=== 测试玩家靠近门 + 触发 ===")
	for direction in rooftop._door_nodes.keys():
		var door = rooftop._door_nodes[direction] as RoomDoor3D
		if door == null:
			continue
		# 玩家站到门边 1m
		tower.player.global_position = door.global_position + Vector3(0, 0, 1.0)
		await _settle_short()
		var nearest: Dictionary = rooftop.get_nearest_door(tower.player.global_position)
		print("  玩家 %s 门附近，nearest=%s door.global_pos=%s" % [
			tower.player.global_position, nearest, door.global_position
		])

	# 模拟 E 键 — 不通过 try_open_room_door，直接调 door.set_open
	print("\n=== 直接调 door.set_open 看视觉/碰撞 ===")
	for direction in rooftop._door_nodes.keys():
		var door = rooftop._door_nodes[direction] as RoomDoor3D
		if door == null:
			continue
		print("  门 %s: set_open(true) 前 is_open=%s collision.disabled=%s" % [
			direction, door.is_open, door._collision.disabled
		])
		door.set_open(true, true)
		await _settle_short()
		print("  门 %s: set_open(true) 后 is_open=%s collision.disabled=%s _panel.position.y=%s" % [
			direction, door.is_open, door._collision.disabled, door._panel.position.y
		])

	# 测物理通过性
	print("\n=== 物理通过性 raycast ===")
	for direction in rooftop._door_nodes.keys():
		var door = rooftop._door_nodes[direction] as RoomDoor3D
		if door == null:
			continue
		# 门所在方向
		var door_forward := Vector3.RIGHT
		match door.direction:
			"north": door_forward = Vector3(0, 0, -1)
			"south": door_forward = Vector3(0, 0, 1)
			"west":  door_forward = Vector3(-1, 0, 0)
			"east":  door_forward = Vector3(1, 0, 0)
		var space_state := tower.get_world_3d().direct_space_state
		var door_pos: Vector3 = door.global_position
		# 抬高到门中心高度 (DOOR_CLEAR_HEIGHT_M * 0.5 = 1.25)
		door_pos.y = 1.2
		var ray_start: Vector3 = door_pos + door_forward * -1.5
		var ray_end: Vector3 = door_pos + door_forward * 1.0
		var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.exclude = [tower.player.get_rid()]
		# 关门
		door.set_open(false, true)
		await _settle_short()
		var hit_closed = space_state.intersect_ray(query)
		# 开门
		door.set_open(true, true)
		await _settle_short()
		var hit_open = space_state.intersect_ray(query)
		print("  门 %s: 关门撞到=%s, 开门撞到=%s" % [
			direction,
			"无" if hit_closed.is_empty() else str(hit_closed.get("collider").name),
			"无" if hit_open.is_empty() else str(hit_open.get("collider").name)
		])

	# 看 _open_edges 状态
	print("\n=== 塔楼 _open_edges 总览 ===")
	var edges: Dictionary = tower.get("_open_edges") as Dictionary
	for k in edges.keys():
		print("  %s = %s" % [k, edges[k]])

	get_tree().quit(0)


func _settle_long() -> void:
	for i in 8:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout


func _settle_short() -> void:
	for i in 3:
		await get_tree().process_frame
		await get_tree().physics_frame