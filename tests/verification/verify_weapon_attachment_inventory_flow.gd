extends Node

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 10810
	add_child(dungeon)
	for _frame in 6:
		await get_tree().process_frame
	var player := dungeon.player
	var inventory := dungeon.get_inventory_module()
	var ui := dungeon.get("_inventory_ui") as InventoryUI
	_check(player != null and inventory != null and ui != null, "配件验收运行态未创建", failures)
	if player == null or inventory == null or ui == null:
		_finish(failures)
		return

	_verify_baseball_bat(player, failures)
	_verify_install_detach_and_ownership(dungeon, player, inventory, failures)
	ui.set_inventory_panel_open(true)
	await get_tree().process_frame
	_verify_unified_equipment_ui(ui, failures)
	_verify_legacy_snapshot_migration(failures)

	dungeon.queue_free()
	await get_tree().process_frame
	_finish(failures)


func _verify_baseball_bat(player: Player3D, failures: Array[String]) -> void:
	var goods := BaseManager.get_base_shop_goods()
	_check(not goods.is_empty() and str(goods[0].get("id", "")) == "weapon_baseball_bat", "棒球棍不是基地贩卖机第一件初级商品", failures)
	var bat := ItemRegistry.get_instance().get_item("weapon_baseball_bat")
	_check(not bat.is_empty() and int(bat.get("base_buy_price", 0)) == 45 and int(bat.get("base_shelf_order", 0)) == 1, "棒球棍商品定义/价格/货架顺序错误", failures)
	var result := player.equip_weapon_item_to_slot(bat, 0)
	var snapshot := player.get_weapon_snapshot()
	_check(bool(result.get("success", false)) and str(snapshot.get("gun_id", "")) == "bp_baseball_bat", "棒球棍不能作为武器实例装备", failures)
	_check(bool(snapshot.get("melee", false)) and int((snapshot.get("melee_profile", {}).get("combo_count", 0))) == 3, "棒球棍没有进入三段近战状态机", failures)
	var bounds := snapshot.get("visual_bounds_hint", Vector3.ZERO) as Vector3
	_check(bounds.z >= 1.45 and bounds.x >= 0.27, "棒球棍模型尺寸未达到可读标准", failures)


func _verify_install_detach_and_ownership(
	dungeon: Dungeon3D, player: Player3D, inventory: InventoryModule, failures: Array[String]
) -> void:
	player.equip_weapon_item_to_slot(ItemRegistry.get_instance().get_item("weapon_rifle"), 0)
	player.equip_weapon_item_to_slot(ItemRegistry.get_instance().get_item("weapon_shotgun"), 1)
	player.switch_weapon_slot(0)
	_check(_seed_and_install(dungeon, inventory, "attach_scope", 0, AssemblyNode.SlotType.SCOPE), "瞄具不能装入步枪瞄具槽", failures)
	_check(_seed_and_install(dungeon, inventory, "attach_big_mag", 0, AssemblyNode.SlotType.MAGAZINE), "弹匣不能装入步枪弹匣槽", failures)
	_check(_seed_and_install(dungeon, inventory, "attach_rubber_stock", 1, AssemblyNode.SlotType.STOCK), "枪托不能装到非激活副武器", failures)
	_check(player.get_active_weapon_slot() == 0 and str(player.get_weapon_snapshot().get("gun_id", "")) == "bp_rifle", "给副武器装配件错误切换了当前武器", failures)

	var scope := ItemRegistry.get_instance().get_item("attach_scope")
	inventory.add_item(scope, 1)
	var unsupported_slot := _find_item_slot(inventory, "attach_scope")
	var unsupported := bool(dungeon.call("_install_attachment_from_inventory", unsupported_slot, scope, 1, AssemblyNode.SlotType.SCOPE))
	_check(not unsupported and not inventory.get_slot(unsupported_slot).is_empty(), "散弹枪不支持的瞄具槽仍可安装或吞掉物品", failures)

	var rifle_id := player.get_equipped_weapon_instance_id_for_slot(0)
	var empty_target := _find_empty_slot(inventory)
	_check(bool(dungeon.call("_remove_attachment_to_inventory", 0, AssemblyNode.SlotType.SCOPE, empty_target)), "已装瞄具不能单独拆回指定背包格", failures)
	_check(str((inventory.get_slot(empty_target).get("item", {}) as Dictionary).get("id", "")) == "attach_scope", "拆下的瞄具没有进入目标背包格", failures)
	_check(bool(dungeon.call("_install_attachment_from_inventory", empty_target, scope, 0, AssemblyNode.SlotType.SCOPE)), "拆下的瞄具不能重新安装", failures)

	var gun_target := _find_empty_slot(inventory)
	dungeon.call("_on_equipped_weapon_to_inventory_requested", 0, gun_target)
	var packed := inventory.get_slot(gun_target).get("item", {}) as Dictionary
	_check(str(packed.get("weapon_instance_id", "")) == rifle_id, "整枪入包时武器实例ID改变", failures)
	var packed_layout := WeaponInstance.from_item(packed).get_presentation_snapshot().get("attachment_layout", []) as Array
	_check(_installed_id(packed_layout, AssemblyNode.SlotType.SCOPE) == "attach_scope" and _installed_id(packed_layout, AssemblyNode.SlotType.MAGAZINE) == "attach_big_mag", "整枪入包时已装配件没有跟枪走", failures)
	dungeon.call("_equip_weapon_from_inventory", gun_target, packed, 0)
	_check(player.get_equipped_weapon_instance_id_for_slot(0) == rifle_id, "整枪重新装备时没有恢复原实例", failures)
	var restored := player.get_weapon_attachment_layout_for_slot(0)
	_check(_installed_id(restored, AssemblyNode.SlotType.SCOPE) == "attach_scope" and _installed_id(restored, AssemblyNode.SlotType.MAGAZINE) == "attach_big_mag", "整枪重新装备后配件树未恢复", failures)


func _verify_unified_equipment_ui(ui: InventoryUI, failures: Array[String]) -> void:
	_check(ui.equipment_attachment_slots.size() == 2, "主/副武器没有各自的配件栏", failures)
	if ui.equipment_attachment_slots.size() != 2:
		return
	for weapon_slots in ui.equipment_attachment_slots:
		_check((weapon_slots as Array).size() == AssemblyNode.PUBLIC_ATTACHMENT_SLOTS.size(), "不同枪械没有显示统一数量/位置的配件槽", failures)
	var primary_slots := ui.equipment_attachment_slots[0] as Array
	var secondary_slots := ui.equipment_attachment_slots[1] as Array
	var rifle_scope := _find_ui_attachment_slot(primary_slots, AssemblyNode.SlotType.SCOPE)
	var shotgun_scope := _find_ui_attachment_slot(secondary_slots, AssemblyNode.SlotType.SCOPE)
	var shotgun_stock := _find_ui_attachment_slot(secondary_slots, AssemblyNode.SlotType.STOCK)
	_check(rifle_scope != null and str((rifle_scope.get_meta("slot_item", {}) as Dictionary).get("id", "")) == "attach_scope", "装备栏未显示步枪已装瞄具", failures)
	_check(shotgun_scope != null and bool(shotgun_scope.get_meta("slot_disabled", false)), "散弹枪未开放的瞄具槽没有禁用", failures)
	_check(shotgun_stock != null and not bool(shotgun_stock.get_meta("slot_disabled", true)) and str((shotgun_stock.get_meta("slot_item", {}) as Dictionary).get("id", "")) == "attach_rubber_stock", "散弹枪开放的枪托槽未显示已装配件", failures)


func _verify_legacy_snapshot_migration(failures: Array[String]) -> void:
	var source := WeaponInstance.from_item(ItemRegistry.get_instance().get_item("weapon_rifle"))
	var tree := source.build_runtime_tree()
	var scope := BlueprintRegistry.create_assembly_node("attach_scope")
	tree.mount(tree.get_root(), AssemblyNode.SlotType.SCOPE, scope)
	source.capture_runtime_tree(tree)
	tree.free()
	var legacy_item := source.to_item_dictionary()
	var legacy_snapshot := legacy_item.get("assembly_snapshot", {}) as Dictionary
	var slots := legacy_snapshot.get("slots", {}) as Dictionary
	slots["0"] = slots.get(str(AssemblyNode.SlotType.SCOPE), {})
	slots.erase(str(AssemblyNode.SlotType.SCOPE))
	legacy_snapshot["tags"] = ["rifle", "automatic", "assault"]
	legacy_item["assembly_snapshot"] = legacy_snapshot
	legacy_item["weapon_instance"] = {}
	var migrated := WeaponInstance.from_item(legacy_item)
	var migrated_tree := migrated.build_runtime_tree()
	_check(migrated_tree.get_root().supports_attachment_slot(AssemblyNode.SlotType.SCOPE), "旧武器快照没有补齐新兼容契约", failures)
	_check(migrated_tree.get_root().slots.get(AssemblyNode.SlotType.SCOPE) != null and migrated_tree.get_root().slots.get(AssemblyNode.SlotType.MOUNT) == null, "旧MOUNT配件没有迁移到统一瞄具槽", failures)
	migrated_tree.free()


func _seed_and_install(dungeon: Dungeon3D, inventory: InventoryModule, item_id: String, weapon_slot: int, slot_type: int) -> bool:
	var item := ItemRegistry.get_instance().get_item(item_id)
	if inventory.add_item(item, 1) != 1:
		return false
	var source_slot := _find_item_slot(inventory, item_id)
	return bool(dungeon.call("_install_attachment_from_inventory", source_slot, item, weapon_slot, slot_type))


func _installed_id(layout: Array, slot_type: int) -> String:
	for raw_entry in layout:
		if raw_entry is Dictionary and int((raw_entry as Dictionary).get("slot_type", -1)) == slot_type:
			return str((raw_entry as Dictionary).get("installed_item_id", ""))
	return ""


func _find_ui_attachment_slot(slots: Array, slot_type: int) -> Control:
	for slot in slots:
		if int((slot as Control).get_meta("attachment_slot_type", -1)) == slot_type:
			return slot as Control
	return null


func _find_item_slot(inventory: InventoryModule, item_id: String) -> int:
	for entry in inventory.get_occupied_slots():
		if str((entry.get("item", {}) as Dictionary).get("id", "")) == item_id:
			return int(entry.get("slot", -1))
	return -1


func _find_empty_slot(inventory: InventoryModule) -> int:
	for slot_index in range(inventory.get_capacity()):
		if inventory.get_slot(slot_index).is_empty():
			return slot_index
	return -1


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("WEAPON_ATTACHMENT_INVENTORY_FLOW_OK: baseball bat vending, unified six-slot equipment UI, compatibility, detach/replace, inactive weapon edits, legacy migration and whole-gun ownership pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
