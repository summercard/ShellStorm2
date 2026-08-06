extends Node
## 到达门真实生成验收：禁止force_open_edge，直接检查节点数量、Boss隔离与卸载契约。


func _ready() -> void:
	var failures: Array[String] = []
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 980095
	add_child(tower)
	await get_tree().process_frame
	var initial := tower.get_tower_snapshot()
	_expect(
		str(initial.get("floor_generation_mode", "")) == "arrival_gate_atomic_floor_bundle",
		"没有启用到达门原子FloorBundle", failures
	)
	_expect(int(initial.get("instantiated_room_count", -1)) == 3, "启动时不应预建98—95整段", failures)
	_expect((initial.get("generated_floor_indices", []) as Array) == [0], "初始错误提交了战斗楼层", failures)
	_expect(int(initial.get("vertical_connector_count", -1)) == 2, "初始应只有楼顶→基地→98入口两段楼梯", failures)
	_expect(bool(initial.get("floor_layout_plan_valid", false)), "纯数据楼层计划无效", failures)
	_expect(
		tower.activate_arrival_between_for_test("start", "facility"),
		"100→99基地交通门无法开启", failures
	)
	var after_base_arrival := tower.get_tower_snapshot()
	_expect(
		(after_base_arrival.get("generated_floor_indices", []) as Array) == [0]
		and str(after_base_arrival.get("current_room_id", "")) == "facility",
		"基地交通门错误触发战斗楼层校验", failures
	)

	# 走实际的下端门交互，不调用force_open_edge：门开启前同步提交98层。
	await get_tree().process_frame
	var entry_room: DungeonRoom3D = null
	for value in get_tree().get_nodes_in_group("dungeon_room_3d"):
		if value is DungeonRoom3D and (value as DungeonRoom3D).room_id == "floor_01_entry":
			entry_room = value as DungeonRoom3D
			break
	if entry_room != null:
		entry_room.ensure_shell_built()
	var arrival_door: RoomDoor3D = null
	if entry_room != null:
		for side_value in entry_room.door_targets.keys():
			if str(entry_room.door_targets[side_value]) == "facility":
				arrival_door = entry_room.get_door_node(str(side_value))
				break
	_expect(arrival_door != null, "98层下端到达门不存在 entry=%s targets=%s" % [str(entry_room), str(entry_room.door_targets if entry_room != null else {})], failures)
	if arrival_door != null:
		_expect(
			tower.activate_arrival_between_for_test("facility", "floor_01_entry"),
			"98层真实到达门交互失败", failures
		)
	var after_arrival := tower.get_tower_snapshot()
	_expect(2 in (after_arrival.get("generated_floor_indices", []) as Array), "到达门开启前没有提交98层", failures)
	await get_tree().process_frame
	if bool(tower.get("_door_fate_active")):
		tower.resolve_fate_choice_for_test(0)
		await get_tree().process_frame

	_expect(tower.generate_through_floor_for_test(95), "98—95 FloorBundle提交失败", failures)
	await get_tree().process_frame
	var generated := tower.get_tower_snapshot()
	_expect(
		(generated.get("generated_floor_indices", []) as Array) == [0, 2, 3, 4, 5],
		"98—95没有按楼层事务依次提交", failures
	)
	_expect(int(generated.get("instantiated_room_count", -1)) == 69, "首段节点数不等于3个普通层+Boss层+隔离/下层入口", failures)
	_expect(int(generated.get("vertical_connector_count", -1)) == 6, "提交95层时没有同步创建95→94楼梯", failures)
	_expect(int(generated.get("boss_floor_room_count", -1)) == 17, "Boss层缺少独立15×15下行大厅", failures)
	_expect(int(generated.get("boss_descent_gate_count", -1)) == 1, "95→94没有Boss专用权限门", failures)
	_expect(int(generated.get("airlock_front_gate_count", -1)) == 1, "Boss后没有双门隔离间", failures)
	var door_counts := generated.get("door_function_counts", {}) as Dictionary
	_expect(
		int(door_counts.get("base_transit", 0)) == 1
		and int(door_counts.get("floor_arrival", 0)) >= 4
		and int(door_counts.get("room_progression", 0)) > 0
		and int(door_counts.get("boss_descent", 0)) == 1
		and int(door_counts.get("airlock_exit", 0)) == 1,
		"门功能分类不完整或Boss/隔离门被错误归类", failures
	)
	_expect(
		int(generated.get("level_elevator_count", -1)) == 1
		and int(generated.get("level_elevator_floor", -1)) == 95,
		"唯一楼层电梯没有设置在95→94楼梯间", failures
	)
	_expect(int(generated.get("last_bundle_room_count", 0)) >= 17, "Boss FloorBundle没有原子补齐房间与下层入口", failures)

	var fake_loot := Node3D.new()
	fake_loot.add_to_group("ground_loot_3d")
	var boss_room: DungeonRoom3D = null
	for value in get_tree().get_nodes_in_group("dungeon_room_3d"):
		if value is DungeonRoom3D and (value as DungeonRoom3D).room_id == "extraction":
			boss_room = value as DungeonRoom3D
			break
	if boss_room != null:
		boss_room.add_child(fake_loot)
	_expect(
		tower.activate_arrival_between_for_test("floor_04_exit", "airlock_95_94"),
		"Boss后隔离到达门没有弹出确认", failures
	)
	_expect(bool(tower.get_tower_snapshot().get("airlock_warning_active", false)), "跨段警告没有显示", failures)
	tower.cancel_airlock_transition()
	_expect(not bool(tower.get_tower_snapshot().get("airlock_warning_active", true)), "取消后警告或门状态没有复位", failures)
	_expect(tower.activate_arrival_between_for_test("floor_04_exit", "airlock_95_94"), "第二次隔离门交互失败", failures)
	_expect(tower.confirm_airlock_transition(), "确认进入隔离间失败", failures)
	var keys_before_unload := int(tower.get_runtime_snapshot().get("keys", -1))
	_expect(bool(tower.call("_try_open_room_door", "floor_05_entry")), "隔离间前门无法开启", failures)
	await get_tree().process_frame
	var unloaded := tower.get_tower_snapshot()
	_expect(
		(unloaded.get("unloaded_segment_floor_indices", []) as Array) == [2, 3, 4, 5],
		"跨过隔离间后没有卸载98—95完整旧段", failures
	)
	_expect(int(unloaded.get("last_unloaded_room_count", 0)) == 65, "旧段房间节点清理数量错误", failures)
	_expect(int(unloaded.get("last_destroyed_world_loot_count", 0)) >= 1, "未拾取地面物没有永久清理", failures)
	_expect(int(tower.get_runtime_snapshot().get("keys", -2)) == keys_before_unload, "段卸载错误清除了玩家持有物", failures)
	_expect(int(unloaded.get("level_elevator_count", -1)) == 0, "通过隔离间后95层电梯仍常驻内存", failures)

	if failures.is_empty():
		print("ARRIVAL_GATE_FLOOR_BUNDLE_OK initial_rooms=3 generated_rooms=%d" % int(generated.get("instantiated_room_count", 0)))
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
