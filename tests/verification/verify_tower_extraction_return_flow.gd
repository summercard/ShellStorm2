extends Node

const MANAGER_SCRIPT := preload("res://src/base/BaseManager.gd")
const TEST_PATH := "user://tower_extraction_return_probe.json"


func _ready() -> void:
	var failures: Array[String] = []
	await _verify_success_returns_inside_99f_with_items(failures)
	_verify_death_insurance_persists(failures)
	_cleanup()
	if failures.is_empty():
		print("TOWER_EXTRACTION_RETURN_OK: successful extraction retains all carried ownership and returns inside 99F; death insurance persists")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_success_returns_inside_99f_with_items(failures: Array[String]) -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	add_child(tower)
	await get_tree().process_frame
	await get_tree().process_frame
	var inventory := tower.get_inventory_module()
	inventory.clear_all()
	inventory.add_item(ItemRegistry.get_instance().get_item("weapon_shotgun"), 1)
	inventory.add_item(ItemRegistry.get_instance().get_item("item_health_potion"), 2)
	inventory.add_item(ItemRegistry.get_instance().get_item("equipment_backpack_4"), 1)
	var backpack_slot := _find_slot(inventory, "equipment_backpack_4")
	if backpack_slot < 0 or not bool(tower.call("_equip_backpack_from_inventory", backpack_slot, inventory.get_slot(backpack_slot).get("item", {}))):
		failures.append("无法准备成功撤离装备背包")
	tower.call("_on_quick_item_assignment_requested", 0, "item_health_potion")
	var insurance := tower.get_insurance_module()
	var potion_slot := _find_slot(inventory, "item_health_potion")
	if potion_slot < 0 or not insurance.insure_item(inventory, potion_slot):
		failures.append("无法准备保险格测试物品")
	var inventory_before := inventory.get_occupied_slots()
	var insured_before := insurance.get_all_insured_items()
	if insured_before.size() != 1 or int(insured_before[0].get("count", 0)) != 2:
		failures.append("保险格没有保留可堆叠物的完整数量")
	var backpack_before := tower.get_equipped_backpack_item()
	var quick_items_before := (tower.get("_quick_item_ids") as Array).duplicate()
	var weapon_ids_before: Array[String] = []
	for slot_index in range(2):
		var weapon := tower.player.get_equipped_weapon_item_for_slot(slot_index)
		if not weapon.is_empty():
			weapon_ids_before.append(str(weapon.get("weapon_instance_id", "")))
	tower.call("_finish_run", true)
	await get_tree().process_frame
	if str(tower.get("_current_room_id")) != "facility":
		failures.append("成功撤离没有返回99层基地房间")
	if bool(tower.get("_completed")):
		failures.append("成功返航后仍处于锁死的行动完成状态")
	if not _same_inventory_instances(inventory_before, inventory.get_occupied_slots()):
		failures.append("成功撤离改变或清空了I键背包战利品")
	if not _same_insurance_instances(insured_before, insurance.get_all_insured_items()):
		failures.append("成功撤离改变或清空了保险格物品")
	if not _same_item_instance(backpack_before, tower.get_equipped_backpack_item()):
		failures.append("成功撤离改变或卸下了装备背包")
	if (tower.get("_quick_item_ids") as Array) != quick_items_before:
		failures.append("成功撤离改变或清空了3/4快捷栏绑定")
	var weapon_ids_after: Array[String] = []
	for slot_index in range(2):
		var weapon := tower.player.get_equipped_weapon_item_for_slot(slot_index)
		if not weapon.is_empty():
			weapon_ids_after.append(str(weapon.get("weapon_instance_id", "")))
	if weapon_ids_after != weapon_ids_before:
		failures.append("成功撤离没有保留主副武器实例")
	tower.queue_free()
	await get_tree().process_frame


func _verify_death_insurance_persists(failures: Array[String]) -> void:
	_cleanup()
	var manager := MANAGER_SCRIPT.new()
	manager.save_path = TEST_PATH
	manager.data = BaseData.new()
	var inventory := InventoryModule.new(4)
	var insurance := InsuranceModule.new(2)
	var insured_weapon := WeaponInstance.ensure_weapon_item(ItemRegistry.get_instance().get_item("weapon_pistol"))
	var insured_id := str(insured_weapon.get("weapon_instance_id", ""))
	inventory.add_item(insured_weapon, 1)
	if not insurance.insure_item(inventory, 0):
		failures.append("死亡保险测试无法存入保险格")
	inventory.add_item(ItemRegistry.get_instance().get_item("item_health_potion"), 3)
	var insured_stack_slot := _find_slot(inventory, "item_health_potion")
	if insured_stack_slot < 0 or not insurance.insure_item(inventory, insured_stack_slot):
		failures.append("死亡保险测试无法存入堆叠物")
	inventory.add_item(ItemRegistry.get_instance().get_item("weapon_shotgun"), 1)
	var settlement := DeathSettlementModule.new()
	settlement.set_loss_ratio(1.0)
	var result := settlement.process_death_settlement(inventory, insurance)
	if (result.get("insurance_saved", []) as Array).size() != 2:
		failures.append("死亡结算没有判定保险格保留")
	if (result.get("dropped", []) as Array).size() != 1:
		failures.append("死亡结算没有区分未保险物品")
	var stored := manager.store_insurance_return_items(result.get("insurance_saved", []), "txn_death_insurance") as Dictionary
	if not bool(stored.get("success", false)) or manager.data.extraction_loot.size() != 2:
		failures.append("死亡保险物没有写入基地待领取集合")
	else:
		var returned_weapon := _find_owned_item(manager.data.extraction_loot, "weapon_pistol")
		var returned_stack := _find_owned_item(manager.data.extraction_loot, "item_health_potion")
		if str(returned_weapon.get("weapon_instance_id", "")) != insured_id:
			failures.append("死亡保险返还丢失了原枪械实例ID")
		if int(returned_stack.get("count", 0)) != 3:
			failures.append("死亡保险返还丢失了堆叠数量")
	manager.free()


func _find_slot(inventory: InventoryModule, item_id: String) -> int:
	for entry in inventory.get_occupied_slots():
		if str((entry.get("item", {}) as Dictionary).get("id", "")) == item_id:
			return int(entry.get("slot", -1))
	return -1


func _find_owned_item(items: Array, item_id: String) -> Dictionary:
	for raw_item in items:
		if raw_item is Dictionary and str((raw_item as Dictionary).get("id", "")) == item_id:
			return (raw_item as Dictionary).duplicate(true)
	return {}


func _same_inventory_instances(before: Array[Dictionary], after: Array[Dictionary]) -> bool:
	if before.size() != after.size():
		return false
	for index in before.size():
		var a := before[index]
		var b := after[index]
		if int(a.get("slot", -1)) != int(b.get("slot", -1)) or int(a.get("count", 0)) != int(b.get("count", 0)):
			return false
		if not _same_item_instance(a.get("item", {}) as Dictionary, b.get("item", {}) as Dictionary):
			return false
	return true


func _same_insurance_instances(before: Array[Dictionary], after: Array[Dictionary]) -> bool:
	if before.size() != after.size():
		return false
	for index in before.size():
		if int(before[index].get("count", 0)) != int(after[index].get("count", 0)):
			return false
		var a_item := before[index].get("item", {}) as Dictionary
		var b_item := after[index].get("item", {}) as Dictionary
		if str(a_item.get("weapon_instance_id", a_item.get("item_instance_id", a_item.get("id", "")))) != str(b_item.get("weapon_instance_id", b_item.get("item_instance_id", b_item.get("id", "")))):
			return false
	return true


func _same_item_instance(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("id", "")) != str(b.get("id", "")):
		return false
	return str(a.get("weapon_instance_id", a.get("item_instance_id", ""))) == str(b.get("weapon_instance_id", b.get("item_instance_id", "")))


func _cleanup() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", TEST_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
