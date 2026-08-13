extends Node
## 可装备背包专项：内容、UI、动态容量、背部Mesh与缩容溢出地面事务。

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var registry := ItemRegistry.get_instance()
	for slots in [2, 4, 8]:
		var item := registry.get_item("equipment_backpack_%d" % slots)
		_check(
			str(item.get("type", "")) == "equipment"
			and str(item.get("subtype", "")) == "backpack"
			and int(item.get("extra_slots", 0)) == slots
			and int(item.get("stack_max", 0)) == 1,
			"%d格背包物品定义不完整" % slots, failures
		)
	_check(
		_has_loot_item(registry.get_loot_table("scavenge_floor_1"), "equipment_backpack_2")
		and _has_loot_item(registry.get_loot_table("elite_floor_1"), "equipment_backpack_4")
		and _has_loot_item(registry.get_loot_table("boss_floor_1"), "equipment_backpack_8"),
		"3种背包没有分别进入搜索/精英/Boss掉落池", failures
	)

	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	for _frame in 5:
		await get_tree().process_frame
	var inventory := dungeon.get_inventory_module()
	var ui := dungeon.get("_inventory_ui") as InventoryUI
	ui.set_inventory_panel_open(true)
	await get_tree().process_frame
	_check(ui.equipment_backpack_slot != null, "角色装备栏没有独立背包槽", failures)
	_check(str(ui.equipment_backpack_slot.get_meta("slot_kind", "")) == "backpack", "背包槽类型错误", failures)

	# 左键装备8格包：物品离开普通格，容量扩为20，背部挂点生成占位Mesh。
	var expedition := registry.get_item("equipment_backpack_8")
	_check(inventory.add_item(expedition, 1) == 1, "无法放入8格背包", failures)
	var expedition_slot := _find_item_slot(inventory, "equipment_backpack_8")
	ui.call("_on_slot_clicked", expedition_slot, true)
	await get_tree().process_frame
	var equipped := dungeon.get_equipped_backpack_item()
	var presentation := dungeon.get_backpack_equipment_snapshot()
	_check(str(equipped.get("id", "")) == "equipment_backpack_8", "左键没有装备8格背包", failures)
	_check(inventory.get_capacity() == 20 and ui._slots.size() == 20, "8格背包没有把12格扩为20格", failures)
	_check(
		str(presentation.get("socket_name", "")) == "BackpackSocket"
		and bool(presentation.get("model_visible", false))
		and str(presentation.get("model_kind", "")) == "backpack"
		and int(presentation.get("mesh_count", 0)) >= 7,
		"背部挂点或8格背包Mesh表现没有同步", failures
	)
	var backpack_model := dungeon.player.get("_backpack_model") as Node3D
	_check(
		backpack_model != null
		and backpack_model.find_children("*", "CollisionShape3D", true, false).is_empty(),
		"背部占位Mesh不应增加玩法碰撞", failures
	)
	var extraction_preview := dungeon.call("_collect_extracted_items", true) as Array[Dictionary]
	_check(
		_has_item(extraction_preview, "equipment_backpack_8"),
		"成功撤离结算没有包含已装备背包本体", failures
	)
	for slot_index in range(12, 20):
		_check(bool(ui._slots[slot_index].get_meta("backpack_bonus_slot", false)), "扩展格%d没有特殊框标记" % slot_index, failures)
	var base_style := ui._slots[0].get_theme_stylebox("normal") as StyleBoxFlat
	var bonus_style := ui._slots[12].get_theme_stylebox("normal") as StyleBoxFlat
	_check(base_style != null and bonus_style != null and base_style.border_color != bonus_style.border_color, "扩展格没有使用不同颜色边框", failures)

	# 填充18个互不堆叠物，再放入2格包。换装后总量20=装备1+包内14+落地5。
	for index in range(18):
		var filler := {
			"id": "test_backpack_filler_%02d" % index,
			"name": "测试物资%02d" % index,
			"type": "material",
			"rarity": "common",
			"stack_max": 1,
		}
		_check(inventory.add_item(filler, 1) == 1, "无法填充测试物资%d" % index, failures)
	var light_pack := registry.get_item("equipment_backpack_2")
	_check(inventory.add_item(light_pack, 1) == 1, "无法放入2格背包", failures)
	var light_slot := _find_item_slot(inventory, "equipment_backpack_2")
	var ground_before := get_tree().get_nodes_in_group("ground_loot_3d").size()
	ui.call("_on_slot_drop_received", light_slot, 0, "inventory", "backpack")
	await get_tree().process_frame
	var ground_after_replace := get_tree().get_nodes_in_group("ground_loot_3d").size()
	_check(str(dungeon.get_equipped_backpack_item().get("id", "")) == "equipment_backpack_2", "拖拽没有换装2格背包", failures)
	_check(inventory.get_capacity() == 14 and inventory.get_used_slots() == 14, "换成2格包后容量/保留格错误", failures)
	_check(ground_after_replace - ground_before == 5, "换包缩容没有把5个溢出格逐项丢到地面", failures)
	_check(
		1 + inventory.get_used_slots() + (ground_after_replace - ground_before) == 20,
		"换包事务发生物品复制或丢失", failures
	)

	# 卸回基础格：先腾出一个基础格，背包本体进入该格，另外2个溢出格落地。
	inventory.clear_slot(0)
	var ground_before_unequip := get_tree().get_nodes_in_group("ground_loot_3d").size()
	ui.call("_on_slot_drop_received", 0, 0, "backpack", "inventory")
	await get_tree().process_frame
	var ground_after_unequip := get_tree().get_nodes_in_group("ground_loot_3d").size()
	_check(dungeon.get_equipped_backpack_item().is_empty(), "背包没有从装备位卸下", failures)
	_check(inventory.get_capacity() == 12 and inventory.get_used_slots() == 12, "卸下后没有恢复基础12格", failures)
	_check(str((inventory.get_slot(0).get("item", {}) as Dictionary).get("id", "")) == "equipment_backpack_2", "卸下的背包没有进入指定基础格", failures)
	_check(ground_after_unequip - ground_before_unequip == 2, "卸下缩容没有把2个溢出格丢到地面", failures)
	_check(not bool(dungeon.get_backpack_equipment_snapshot().get("model_visible", true)), "卸下后背部背包Mesh仍然存在", failures)

	# 装备背包也可直接拖到红区；先重新装备来源格中的2格包，此时没有缩容溢出。
	ui.call("_on_slot_drop_received", 0, 0, "inventory", "backpack")
	var ground_before_backpack_drop := get_tree().get_nodes_in_group("ground_loot_3d").size()
	ui.call("_on_slot_drop_received", 0, -1, "backpack", "drop")
	var ground_after_backpack_drop := get_tree().get_nodes_in_group("ground_loot_3d").size()
	_check(
		dungeon.get_equipped_backpack_item().is_empty()
		and ground_after_backpack_drop == ground_before_backpack_drop + 1,
		"装备背包拖到红区后没有卸装并生成当前房间掉落", failures
	)

	dungeon.queue_free()
	_finish(failures)


func _has_loot_item(items: Array[Dictionary], item_id: String) -> bool:
	for item in items:
		if str(item.get("id", "")) == item_id:
			return true
	return false


func _has_item(items: Array[Dictionary], item_id: String) -> bool:
	for item in items:
		if str(item.get("id", "")) == item_id:
			return true
	return false


func _find_item_slot(inventory: InventoryModule, item_id: String) -> int:
	for entry in inventory.get_occupied_slots():
		if str((entry.get("item", {}) as Dictionary).get("id", "")) == item_id:
			return int(entry.get("slot", -1))
	return -1


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("BACKPACK_EQUIPMENT_FLOW_OK: 2/4/8 loot, click/drag equip/unequip/drop, colored bonus slots, back socket mesh, shrink overflow and item conservation pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
