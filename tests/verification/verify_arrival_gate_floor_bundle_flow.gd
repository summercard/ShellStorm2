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
	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	_expect(facility != null, "99层基地房间不存在", failures)
	if facility != null:
		# 开门本身不再伪造房间进入；模拟角色真正跨过基地墙体内沿。
		tower.player.global_position = facility.global_position + Vector3(0.0, 0.05, 0.0)
		tower.call("_refresh_physical_location_authority", true)
	var after_base_arrival := tower.get_tower_snapshot()
	_expect(
		(after_base_arrival.get("generated_floor_indices", []) as Array) == [0]
		and str(after_base_arrival.get("current_room_id", "")) == "facility",
		"基地交通门错误触发战斗楼层校验", failures
	)
	if facility != null:
		facility.ensure_shell_built()
		tower.player.global_position = facility.global_position + Vector3(0.0, 0.05, 0.0)
		tower.call("_update_facility_combat_lock")
		_expect(
			tower.is_player_inside_facility() and not tower.player.combat_enabled,
			"只有基地室内应锁定开火，但中心基地没有锁定", failures
		)
		for target_room_id in ["start", "floor_01_entry"]:
			var edge := tower.call("_edge_key", "facility", target_room_id) as String
			var side := "west" if target_room_id == "start" else "east"
			var door := facility.get_door_node(side)
			_expect(
				door != null and tower.try_open_room_door(target_room_id),
				"基地%s侧门无法按E开启" % side, failures
			)
			if door != null:
				_expect(door.is_open, "基地%s侧门开启后没有播放开门状态" % side, failures)
			var dimensions := facility.get_dimensions()
			var outside_x := -(dimensions.x * 0.5 + 4.0) if side == "west" else dimensions.x * 0.5 + 4.0
			var door_local_z := facility.to_local(door.global_position).z if door != null else 0.0
			tower.player.global_position = facility.to_global(Vector3(outside_x, 0.05, door_local_z))
			tower.call("_update_facility_combat_lock")
			await get_tree().create_timer(1.25).timeout
			await get_tree().physics_frame
			_expect(
				not tower.is_player_inside_facility() and tower.player.combat_enabled,
				"离开基地屋体后仍然禁止开火", failures
			)
			_expect(
				door != null and not door.is_open and bool((tower.get("_open_edges") as Dictionary).get(edge, false)),
				"基地%s侧门离开后没有关闭，或错误撤销了楼梯路线授权" % side, failures
			)
			if target_room_id == "start":
				var rooftop := (tower.get("_room_by_id") as Dictionary).get("start") as DungeonRoom3D
				var rooftop_door := rooftop.get_door_node("west") if rooftop != null else null
				_expect(
					rooftop_door != null and not rooftop_door.is_open,
					"基地出门自动关闭后，天台上端门状态不是关闭",
					failures
				)
				if rooftop_door != null:
					tower.player.global_position = rooftop_door.global_position
					_expect(
						str(tower.get("_current_room_id")) == "facility"
						and tower.try_open_stair_arrival_for_test(),
						"角色在楼梯内、房间上下文仍为99F时不能从内侧开启天台门",
						failures
					)
					_expect(
						rooftop_door.is_open and door != null and not door.is_open,
						"内侧开启天台门错误联动打开了99F基地侧门",
						failures
					)
			tower.player.global_position = facility.global_position + Vector3(0.0, 0.05, 0.0)
			tower.force_enter_room_for_test("facility")
			_expect(
				tower.try_open_room_door(target_room_id) and door != null and door.is_open,
				"基地%s侧门自动关闭后不能再次按E开启" % side, failures
			)
			await get_tree().process_frame
			_expect(
				door != null and door.is_open,
				"基地%s侧门刚开启就被错误自动关闭" % side, failures
			)
			tower.player.global_position = facility.to_global(Vector3(outside_x, 0.05, 0.0))
			await get_tree().create_timer(1.25).timeout
			tower.player.global_position = facility.global_position + Vector3(0.0, 0.05, 0.0)
			tower.force_enter_room_for_test("facility")

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
		var arrival_edge := tower.call("_edge_key", "facility", "floor_01_entry") as String
		var arrival_connector := (tower.get("_corridor_by_edge") as Dictionary).get(arrival_edge) as Node3D
		var room_to_stair := arrival_door.global_position - entry_room.global_position
		room_to_stair.y = 0.0
		room_to_stair = room_to_stair.normalized()
		# 真实动线：角色仍站在安全屋墙体外的楼梯平台。读档容错会接受这个
		# 位置，但实时房间归属绝不能因此提前切换到98F安全屋。
		tower.force_enter_room_for_test("facility")
		tower.player.global_position = arrival_door.global_position + room_to_stair * 0.75 + Vector3.UP * 0.05
		tower.call("_refresh_physical_location_authority", true)
		_expect(
			str(tower.get("_current_room_id")) == "facility"
			and not entry_room.contains_world_position(tower.player.global_position),
			"角色尚在98F安全屋门外却被提前识别为安全屋",
			failures
		)
		_expect(tower.player.request_interaction_for_test(), "统一交互控制器没有接收98层到达门请求", failures)
		await get_tree().process_frame
		await get_tree().physics_frame
		_expect(
			arrival_connector != null
			and arrival_door.is_open
			and not bool(arrival_door.get_snapshot().get("blocks_passage", true)),
			"98层门外真实按E后门板或碰撞没有打开", failures
		)
		_expect(
			str(tower.get("_current_room_id")) == "facility",
			"只打开98F到达门就提前提交了安全屋房间归属", failures
		)
		# 只有角色中心真正跨过墙体内沿，当前房间才允许切换为安全屋。
		tower.player.global_position = arrival_door.global_position - room_to_stair * 0.45 + Vector3.UP * 0.05
		tower.call("_refresh_physical_location_authority", true)
		_expect(
			entry_room.contains_world_position(tower.player.global_position)
			and str(tower.get("_current_room_id")) == "floor_01_entry",
			"角色真正进入98F安全屋后没有提交正确房间归属", failures
		)
		await get_tree().physics_frame
		await get_tree().process_frame
	var after_arrival := tower.get_tower_snapshot()
	_expect(2 in (after_arrival.get("generated_floor_indices", []) as Array), "到达门开启前没有提交98层", failures)
	await get_tree().process_frame
	_expect(not bool(tower.get("_door_fate_active")), "安全屋到达门错误触发命运卡选择", failures)
	# 实际进入98F安全屋后，必须由真实房间触发器在身后封门；禁止手动调用
	# _on_initial_loop_entry_physically_entered 掩盖实机触发缺失。
	var first_edge := tower.call("_edge_key", "facility", "floor_01_entry") as String
	_expect(
		bool(tower.get("_initial_loop_gate_sealed"))
		and not bool((tower.get("_open_edges") as Dictionary).get(first_edge, true)),
		"98F大循环首门没有在角色进入后关闭", failures
	)
	var sealed_save := tower.build_runtime_save_snapshot()
	var sealed_world := sealed_save.get("world_state", {}) as Dictionary
	_expect(
		not bool((sealed_save.get("edge_states", {}) as Dictionary).get(first_edge, true))
		and bool(sealed_world.get("initial_loop_gate_sealed", false))
		and bool((sealed_world.get("vertical_arrival_open", {}) as Dictionary).get(first_edge, false)),
		"98F首门实体已关闭，但行动快照没有原子记录封门/到达状态", failures
	)
	var carried := tower.get_inventory_module()
	var carried_insurance := tower.get_insurance_module()
	carried.add_item(ItemRegistry.get_instance().get_item("item_battery_l"), 1)
	carried.add_item(ItemRegistry.get_instance().get_item("item_health_potion"), 1)
	tower.call("_on_quick_item_assignment_requested", 1, "item_health_potion")
	_expect(
		carried_insurance.insure_item_direct(ItemRegistry.get_instance().get_item("item_battery_s")),
		"无法准备反向撤退保险物", failures
	)
	var secondary := WeaponInstance.ensure_weapon_item(ItemRegistry.get_instance().get_item("weapon_shotgun"))
	var secondary_result := tower.player.equip_weapon_item_to_slot(secondary, 1)
	_expect(bool(secondary_result.get("success", false)), "无法准备撤退时的副武器", failures)
	tower.call("_show_initial_loop_retreat_warning")
	_expect(tower.get("_initial_loop_retreat_overlay") != null, "反向开启98F首门没有显示撤退确认", failures)
	tower.call("_cancel_initial_loop_retreat")
	_expect(carried.has_item("item_battery_l"), "取消撤退错误清除了背包物品", failures)
	_expect(
		(tower.get("_quick_inventory") as InventoryModule).has_item("item_health_potion"),
		"取消撤退错误清除了快捷物品", failures
	)
	_expect(carried_insurance.has_item("item_battery_s"), "取消撤退错误清除了保险物", failures)
	tower.call("_show_initial_loop_retreat_warning")
	tower.confirm_initial_loop_retreat_for_test()
	_expect(
		carried.get_used_slots() == 0
		and tower.player.get_equipped_weapon_instance_for_slot(0) == null
		and tower.player.get_equipped_weapon_instance_for_slot(1) == null,
		"确认撤退没有清空背包及主/副武器", failures
	)
	_expect(carried_insurance.has_item("item_battery_s"), "确认反向撤退错误清除了保险物", failures)
	_expect(
		(tower.get("_quick_inventory") as InventoryModule).get_used_slots() == 0,
		"确认反向撤退没有清空真实快捷物品槽", failures
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
	var reset_rooftop_door := tower.find_child("BaseRooftopTransitDoor", true, false) as RoomDoor3D
	var reset_base_west_door := facility.get_door_node("west") if facility != null else null
	var reset_base_east_door := facility.get_door_node("east") if facility != null else null
	_expect(
		reset_rooftop_door != null and not reset_rooftop_door.is_open and
		reset_base_west_door != null and not reset_base_west_door.is_open and
		reset_base_east_door != null and not reset_base_east_door.is_open,
		"撤退后99F基地三扇门没有全部回到关闭状态", failures
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
	# 第二轮也必须走真实的门外→门内物理动线。这里过去直接调用封门回调，
	# 会掩盖撤退重建后RoomTrigger或门状态没有正确复位的回归。
	if reset_entry != null and reset_arrival_door != null:
		var reset_room_to_stair := reset_arrival_door.global_position - reset_entry.global_position
		reset_room_to_stair.y = 0.0
		reset_room_to_stair = reset_room_to_stair.normalized()
		tower.player.global_position = reset_arrival_door.global_position + reset_room_to_stair * 0.75 + Vector3.UP * 0.05
		tower.call("_refresh_physical_location_authority", true)
		await get_tree().physics_frame
		tower.player.global_position = reset_arrival_door.global_position - reset_room_to_stair * 0.45 + Vector3.UP * 0.05
		tower.call("_refresh_physical_location_authority", true)
		await get_tree().physics_frame
		await get_tree().process_frame
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
	var active_airlock_id := str(tower.get("_active_airlock_room_id"))
	var active_airlock := (tower.get("_room_by_id") as Dictionary).get(active_airlock_id) as DungeonRoom3D
	if active_airlock != null:
		# 确认只开门；角色真正进入隔离间后才取得该房间归属。
		tower.player.global_position = active_airlock.global_position + Vector3(0.0, 0.05, 0.0)
		tower.call("_refresh_physical_location_authority", true)
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
