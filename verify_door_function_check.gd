extends Node
## 验证门功能完整性：场景加载 + 检查所有房间门的 meta 位置 + 不抛异常。

const OUTPUT_DIR := "res://outputs/019fb2a5-6bc8-7d10-a214-90288a5f7e80/previews"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await _settle_long()
	tower.force_enter_room_for_test("start")
	await _settle_long()

	# 触发所有房间的 shell 构建
	tower.force_enter_room_for_test("facility")
	await _settle_long()
	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	if facility:
		facility.ensure_shell_built()
		await _settle_long()

	# 遍历所有房间，确认门位置都正常
	var room_by_id := tower.get("_room_by_id") as Dictionary
	print("=== 门功能 & 位置检查 ===")
	var errors: Array[String] = []
	for room_id in room_by_id.keys():
		var room = room_by_id[room_id] as DungeonRoom3D
		if room == null:
			continue
		# 检查所有方向门 meta
		for direction in ["north", "south", "west", "east"]:
			var meta_key := "tower_wall_door_offset_%s" % direction
			if room.has_meta(meta_key):
				var door_offset := float(room.get_meta(meta_key))
				var dimensions := room.get_dimensions()
				var horizontal: bool = direction in ["north", "south"]
				var length: float = dimensions.x if horizontal else dimensions.y
				# 5m 模块中心
				var module_count := maxi(1, int(round(length / 5.0)))
				# 验证这个 door_offset 确实对应某个模块中心
				var on_module := false
				for i in range(module_count):
					var center := -length * 0.5 + 5.0 * (float(i) + 0.5)
					if absf(center - door_offset) < 0.01:
						on_module = true
						break
				if not on_module:
					errors.append("房间 %s 方向 %s 的门位置 %s 不在模块中心 (length=%s, modules=%s)" % [room_id, direction, door_offset, length, module_count])
				else:
					print("[OK] 房间 %s 方向 %s 门位置 = %s (length=%s, modules=%s)" % [room_id, direction, door_offset, length, module_count])

	# 检查房间门 mesh 存在
	print("\n=== 房间门 mesh 检查 ===")
	for room_id in room_by_id.keys():
		var room = room_by_id[room_id] as DungeonRoom3D
		if room == null:
			continue
		room.ensure_shell_built()
		# 看 _door_nodes
		for direction in room._door_nodes.keys():
			var door = room._door_nodes[direction] as RoomDoor3D
			if door == null:
				errors.append("房间 %s 方向 %s 门 mesh 为 null" % [room_id, direction])
				continue
			# 检查门位置
			var meta_key := "tower_wall_door_offset_%s" % direction
			var expected_offset := float(room.get_meta(meta_key))
			var actual_pos: Vector3 = door.position
			var actual_offset: float
			if direction in ["north", "south"]:
				actual_offset = actual_pos.x if direction == "north" else -actual_pos.x
			else:
				actual_offset = actual_pos.z if direction == "west" else actual_pos.z
			if absf(actual_offset - expected_offset) > 0.01:
				errors.append("房间 %s 方向 %s 门 mesh 位置 %s ≠ meta 预期 %s" % [room_id, direction, actual_offset, expected_offset])
			else:
				print("[OK] 房间 %s 方向 %s 门 mesh = %s, meta = %s" % [room_id, direction, actual_offset, expected_offset])

	# 检查塔楼外墙缺口
	print("\n=== 塔楼外墙缺口检查 ===")
	var stages := tower.find_children("*TowerFloorStage*", "Node3D", true, false)
	for stage in stages:
		if stage.has_method("_stair_hole_center"):
			for side in ["north", "south", "west", "east"]:
				var hole_center = stage._stair_hole_center(side)
				# 验证落在 5m 网格中心
				var along = hole_center.x if side in ["north", "south"] else hole_center.z
				var n = (along / 5.0) - 0.5
				var on_grid = absf(n - round(n)) < 1e-6
				print("[%s] 面 %s 缺口中线 = %s  5m 网格中心: %s" % [
					"OK" if on_grid else "FAIL",
					side, along, on_grid,
				])
				if not on_grid:
					errors.append("塔楼外墙 %s 缺口 %s 不在 5m 网格" % [side, hole_center])

	# 汇总
	print("\n=== 汇总 ===")
	if errors.is_empty():
		print("✅ 全部通过 0 错误")
	else:
		print("❌ %s 个错误：" % errors.size())
		for err in errors:
			print("  - %s" % err)

	get_tree().quit(0 if errors.is_empty() else 1)


func _settle_long() -> void:
	for i in 10:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.5).timeout