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
	var inventory_ui := tower.get("_inventory_ui") as InventoryUI
	_expect(inventory_ui != null, "塔楼没有创建战术背包界面", failures)
	if inventory_ui != null:
		await _press_key(KEY_I)
		_expect(inventory_ui.is_inventory_open(), "塔楼内按I没有打开背包", failures)
		_expect(tower.player.input_locked, "塔楼背包打开后没有锁定玩家输入", failures)
		await _press_key(KEY_I)
		_expect(not inventory_ui.is_inventory_open(), "塔楼内再次按I没有关闭背包", failures)
		_expect(not tower.player.input_locked, "塔楼背包关闭后没有恢复玩家输入", failures)
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
	_expect(not bool(tower.get("_door_fate_active")), "安全屋到达门错误触发命运卡选择", failures)
	# 实际进入98F安全屋后，首门在身后封闭；反向开启必须走撤退确认并清空随身物。
	tower.call("_on_initial_loop_entry_physically_entered", entry_room)
	var first_edge := tower.call("_edge_key", "facility", "floor_01_entry") as String
	_expect(
		bool(tower.get("_initial_loop_gate_sealed"))
		and not bool((tower.get("_open_edges") as Dictionary).get(first_edge, true)),
		"98F大循环首门没有在角色进入后关闭", failures
	)
	var carried := tower.get_inventory_module()
	carried.add_item(ItemRegistry.get_instance().get_item("item_health_potion"), 1)
	var secondary := WeaponInstance.ensure_weapon_item(ItemRegistry.get_instance().get_item("weapon_shotgun"))
	var secondary_result := tower.player.equip_weapon_item_to_slot(secondary, 1)
	_expect(bool(secondary_result.get("success", false)), "无法准备撤退时的副武器", failures)
	tower.call("_show_initial_loop_retreat_warning")
	_expect(tower.get("_initial_loop_retreat_overlay") != null, "反向开启98F首门没有显示撤退确认", failures)
	tower.call("_cancel_initial_loop_retreat")
	_expect(carried.has_item("item_health_potion"), "取消撤退错误清除了物品", failures)
	tower.call("_show_initial_loop_retreat_warning")
	tower.confirm_initial_loop_retreat_for_test()
	_expect(
		carried.get_used_slots() == 0
		and tower.player.get_equipped_weapon_instance_for_slot(0) == null
		and tower.player.get_equipped_weapon_instance_for_slot(1) == null,
		"确认撤退没有清空背包及主/副武器", failures
	)
	_expect(str(tower.get_tower_snapshot().get("current_room_id", "")) == "facility", "确认撤退没有返回99F基地", failures)
	for _frame in 2:
		await get_tree().process_frame
	var reset_snapshot := tower.get_tower_snapshot()
	_expect(
		(reset_snapshot.get("generated_floor_indices", []) as Array) == [0]
		and int(reset_snapshot.get("instantiated_room_count", -1)) == 3
		and int(reset_snapshot.get("vertical_connector_count", -1)) == 2,
		"撤退后没有销毁首门生成的关卡并恢复初始3房/2楼梯状态", failures
	)
	_expect(
		not bool(tower.get("_initial_loop_gate_armed"))
		and not bool(tower.get("_initial_loop_gate_sealed"))
		and not bool((tower.get("_vertical_arrival_open") as Dictionary).get(first_edge, true)),
		"撤退后98F首门事务标志或下端到达门状态没有复位", failures
	)
	var reset_entry := tower.get("_room_by_id").get("floor_01_entry") as DungeonRoom3D
	var reset_arrival_door: RoomDoor3D = null
	if reset_entry != null:
		reset_entry.ensure_shell_built()
		for side_value in reset_entry.door_targets.keys():
			if str(reset_entry.door_targets[side_value]) == "facility":
				reset_arrival_door = reset_entry.get_door_node(str(side_value))
				break
	_expect(reset_arrival_door != null and not reset_arrival_door.is_open, "撤退后重新返回时98F安全屋入口门不是关闭状态", failures)
	var reset_connector := (tower.get("_corridor_by_edge") as Dictionary).get(first_edge) as Node3D
	_expect(reset_connector != null, "撤退重建后基地→98F楼梯连接器不存在", failures)
	if reset_connector != null and reset_arrival_door != null:
		var rebuilt_lower_door := reset_connector.get_meta("lower_door_position", Vector3.ZERO) as Vector3
		_expect(
			rebuilt_lower_door.distance_to(reset_arrival_door.global_position) <= 0.01,
			"撤退重建后楼梯接驳点与98F门洞错位，可能产生空气墙", failures
		)
	_expect(
		tower.activate_arrival_between_for_test("facility", "floor_01_entry"),
		"撤退后无法重新开启98F到达门并开始新循环", failures
	)
	# 门碰撞采用deferred切换，等待物理帧后直接射线穿过门洞；这项检查
	# 会同时捕获门碰撞、错位墙模块以及旧楼梯围护碰撞残留。
	await get_tree().physics_frame
	await get_tree().physics_frame
	if reset_arrival_door != null and reset_connector != null:
		var outward := reset_connector.get_meta("outward", Vector3.RIGHT) as Vector3
		var doorway_center := reset_arrival_door.global_position + Vector3.UP * 0.9
		var exclusions: Array[RID] = []
		if tower.player is CollisionObject3D:
			exclusions.append(tower.player.get_rid())
		var query := PhysicsRayQueryParameters3D.create(
			doorway_center - outward * 1.0,
			doorway_center + outward * 1.0,
			1,
			exclusions
		)
		query.collide_with_areas = false
		var doorway_hit := tower.get_world_3d().direct_space_state.intersect_ray(query)
		_expect(
			doorway_hit.is_empty(),
			"撤退后二次开启98F门仍有物理阻挡：%s" % str(doorway_hit.get("collider", null)),
			failures
		)
	_expect(
		2 in (tower.get_tower_snapshot().get("generated_floor_indices", []) as Array),
		"撤退后再次开门没有重新生成98F FloorBundle", failures
	)
	tower.call("_on_initial_loop_entry_physically_entered", reset_entry)
	_expect(
		bool(tower.get("_initial_loop_gate_sealed"))
		and not bool((tower.get("_open_edges") as Dictionary).get(first_edge, true)),
		"撤退后新循环首次进入98F时入口门没有再次关闭", failures
	)

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


func _press_key(keycode: Key) -> void:
	var pressed := InputEventKey.new()
	pressed.keycode = keycode
	pressed.physical_keycode = keycode
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await get_tree().process_frame
	var released := InputEventKey.new()
	released.keycode = keycode
	released.physical_keycode = keycode
	released.pressed = false
	Input.parse_input_event(released)
	await get_tree().process_frame
