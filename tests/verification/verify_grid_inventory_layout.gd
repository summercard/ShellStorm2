extends Node
## 格子背包数据契约：尺寸、矩形占位、旋转、堆叠与旧快照迁移。

func _ready() -> void:
	var failures: Array[String] = []
	var registry := ItemRegistry.get_instance()
	var rifle := registry.get_item("weapon_rifle")
	var pistol := registry.get_item("weapon_pistol")
	var potion := registry.get_item("item_health_potion")
	for item in registry.get_all_items():
		var dimensions := item.get("grid_size", []) as Array
		_check(dimensions.size() == 2 and int(dimensions[0]) >= 1 and int(dimensions[1]) >= 1, "物品%s没有合法占格尺寸" % str(item.get("id", "")), failures)
		_check(int(item.get("grid_area", 0)) == int(dimensions[0]) * int(dimensions[1]), "物品%s占格面积与宽高不一致" % str(item.get("id", "")), failures)
	_check((rifle.get("grid_size", []) as Array) == [4, 2], "步枪没有落盘为4x2", failures)
	_check((pistol.get("grid_size", []) as Array) == [2, 1], "手枪没有落盘为2x1", failures)
	_check(int(rifle.get("grid_area", 0)) == 8, "步枪占格面积不是8", failures)

	var inventory := InventoryModule.new(24)
	_check(inventory.add_item(rifle, 1) == 1, "4x2步枪无法放入24格棋盘", failures)
	var rifle_slot := inventory.find_weapon_instance_slot(str((inventory.get_occupied_slots()[0].get("item", {}) as Dictionary).get("weapon_instance_id", "")))
	if rifle_slot < 0:
		rifle_slot = int(inventory.get_occupied_slots()[0].get("slot", -1))
	var rifle_entry := inventory.get_slot(rifle_slot)
	_check(
		inventory.get_occupied_grid_cells(rifle_entry).size() == 8,
		"步枪没有占用连续8格",
		failures,
	)
	_check(inventory.get_free_grid_cells() == 16, "放入4x2步枪后剩余面积不是16", failures)
	_check(not inventory.can_place_item_at(pistol, 0), "已被步枪占用的锚点错误地允许放手枪", failures)
	_check(inventory.can_place_item_at(pistol, 12), "棋盘尾部空位无法放置手枪", failures)

	var rotated_item := potion.duplicate(true)
	rotated_item["grid_size"] = [2, 3]
	rotated_item["grid_area"] = 6
	var rotation_board := InventoryModule.new(24)
	_check(rotation_board.can_place_item_at(rotated_item, 0, 1), "旋转物品没有按宽高交换判定", failures)
	_check(not rotation_board.can_place_item_at(rotated_item, 18, 0), "未旋转物品越过棋盘底部却被接受", failures)

	var snapshot := inventory.get_slots_snapshot()
	var encoded := JSON.stringify(snapshot)
	var decoded := JSON.parse_string(encoded) as Array
	var restored := InventoryModule.new(24)
	restored.restore_slots_snapshot(decoded)
	_check(
		restored.get_occupied_grid_cells(restored.get_occupied_slots()[0]).size() == 8,
		"JSON快照恢复后4x2步枪占位丢失",
		failures,
	)

	var stack_a := ItemRegistry.get_instance().get_item("item_health_potion")
	_check(inventory.add_item(stack_a, 2) == 2, "1x1可堆叠物无法在剩余棋盘空间入包", failures)
	_check(inventory.get_item_count("item_health_potion") == 2, "堆叠数量错误", failures)

	var before := JSON.stringify(inventory.get_slots_snapshot())
	_check(not inventory.move_or_swap_slots(rifle_slot, 18, 1), "越界旋转被接受", failures)
	_check(JSON.stringify(inventory.get_slots_snapshot()) == before, "拒绝旋转改变了原物品", failures)
	var rotate_only := InventoryModule.new(32)
	rotate_only.add_item(rifle, 1)
	_check(rotate_only.move_or_swap_slots(0, 0, 1), "原地合法旋转失败", failures)
	_check(int(rotate_only.get_slot(0).get("grid_rotation", -1)) == 1, "原地旋转未保存", failures)
	var swap_board := InventoryModule.new(24)
	var tall := potion.duplicate(true)
	tall["grid_size"] = [1, 2]
	tall["grid_area"] = 2
	swap_board.put_item_in_empty_slot(0, tall, 1)
	swap_board.put_item_in_empty_slot(2, rifle, 1)
	var swap_before := JSON.stringify(swap_board.get_slots_snapshot())
	_check(not swap_board.move_or_swap_slots(0, 2), "交换后的物品彼此重叠", failures)
	_check(JSON.stringify(swap_board.get_slots_snapshot()) == swap_before, "拒绝交换未保留快照", failures)
	var safe := InsuranceModule.new()
	_check(safe.get_max_slots() == 16, "保险柜不是8x2", failures)
	var insured_source := InventoryModule.new(24)
	insured_source.add_item(rifle, 1)
	_check(safe.insure_item_to_slot(insured_source, 0, 4), "保险柜不能按4x2放入步枪", failures)
	_check(not safe.can_place_item_at(potion, 13), "保险柜覆盖格允许重叠", failures)
	_check(safe.move_or_swap_slots(4, 0), "保险柜跨格移动失败", failures)
	_check(not safe.move_or_swap_slots(0, 0, 1), "保险柜越界旋转被接受", failures)
	_check(safe.claim_item(0).get("id", "") == rifle.id, "保险柜领取丢失物品", failures)
	var legacy_item := potion.duplicate(true)
	legacy_item["grid_size"] = [4, 4]
	legacy_item["grid_area"] = 16
	safe.restore_slots_snapshot([{"item": legacy_item, "count": 1}, {"item": rifle, "count": 1}])
	_check(safe.get_used_slots() == 2 and safe.get_max_slots() >= 32, "保险柜旧档恢复未保留全部物品", failures)
	var legacy_bag := InventoryModule.new(24)
	legacy_bag.restore_slots_snapshot([{"item": legacy_item, "count": 1}])
	_check(legacy_bag.get_used_area() == 16, "八列迁移丢失旧四行物品", failures)
	if failures.is_empty():
		print("GRID_INVENTORY_LAYOUT_OK")
	else:
		for failure in failures:
			push_error(failure)
		print("GRID_INVENTORY_LAYOUT_FAIL count=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
