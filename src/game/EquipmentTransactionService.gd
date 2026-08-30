class_name EquipmentTransactionService
extends RefCounted
## 背包与玩家装备栏之间的原子事务边界。
##
## 本服务不依赖 HUD，也不写提示文本。调用方只消费结构化结果，避免世界场景同时
## 承担实例去重、背包回滚和玩家装备状态协调。


static func equip_weapon_from_inventory(
	inventory: InventoryModule,
	weapon_owner: Object,
	source_slot_index: int,
	item: Dictionary,
	target_weapon_slot := -1
) -> Dictionary:
	if inventory == null:
		return _failure("inventory_unavailable", "背包不可用")
	if weapon_owner == null or not weapon_owner.has_method("equip_weapon_item"):
		return _failure("weapon_owner_unavailable", "装备栏不可用")
	if target_weapon_slot >= 0 and not weapon_owner.has_method("equip_weapon_item_to_slot"):
		return _failure("target_slot_unsupported", "装备栏不支持指定槽位")

	var source_entry := inventory.get_slot(source_slot_index)
	if source_entry.is_empty():
		return _failure("source_slot_empty", "来源背包格为空")
	var source_item := source_entry.get("item", {}) as Dictionary
	if source_item.is_empty() or str(source_item.get("id", "")) != str(item.get("id", "")):
		return _failure("source_slot_changed", "来源背包格内容已变化")

	var incoming := WeaponInstance.ensure_weapon_item(source_item)
	if str(incoming.get("type", "")) != "weapon":
		return _failure("invalid_weapon", "该物品不是有效武器")
	var incoming_id := str(incoming.get("weapon_instance_id", ""))
	if incoming_id.is_empty():
		return _failure("missing_instance_id", "武器实例缺少唯一标识")
	if weapon_owner.has_method("get_equipped_weapon_instance_id_for_slot"):
		for equipped_slot in range(2):
			if incoming_id == str(weapon_owner.call("get_equipped_weapon_instance_id_for_slot", equipped_slot)):
				return _failure(
					"duplicate_instance",
					"该枪械实例已在%s #%s" % [
						"主武器栏" if equipped_slot == 0 else "副武器栏",
						incoming_id.right(6).to_upper(),
					],
					{"equipped_slot": equipped_slot, "weapon_instance_id": incoming_id}
				)

	var inventory_before := inventory.get_slots_snapshot()
	if not inventory.remove_from_slot(source_slot_index, 1):
		return _failure("inventory_remove_failed", "无法从来源背包格取出武器")

	var equip_result := _equip(weapon_owner, incoming, target_weapon_slot)
	if not bool(equip_result.get("success", false)):
		inventory.restore_slots_snapshot(inventory_before)
		return _failure(
			"equip_rejected",
			str(equip_result.get("reason", equip_result.get("message", "换枪失败"))),
			{"owner_result": equip_result}
		)

	var old_item := equip_result.get("old_item", {}) as Dictionary
	if not old_item.is_empty() and inventory.add_item(old_item, 1) != 1:
		var rollback_slot := int(equip_result.get("slot_index", target_weapon_slot))
		var rollback := _equip(weapon_owner, old_item, rollback_slot)
		if bool(rollback.get("success", false)):
			inventory.restore_slots_snapshot(inventory_before)
			return _failure(
				"inventory_write_failed_rolled_back",
				"换枪失败：原武器无法放回背包，已完整回滚",
				{"rollback": rollback}
			)
		return _failure(
			"rollback_failed",
			"换枪事务异常：原武器无法放回背包且装备栏回滚失败",
			{"rollback": rollback, "owner_result": equip_result}
		)

	return {
		"success": true,
		"code": "equipped",
		"incoming_item": incoming.duplicate(true),
		"old_item": old_item.duplicate(true),
		"snapshot": (equip_result.get("snapshot", {}) as Dictionary).duplicate(true),
		"slot_index": int(equip_result.get("slot_index", target_weapon_slot)),
		"weapon_instance_id": incoming_id,
	}


static func _equip(weapon_owner: Object, item: Dictionary, target_weapon_slot: int) -> Dictionary:
	if target_weapon_slot >= 0:
		return weapon_owner.call("equip_weapon_item_to_slot", item, target_weapon_slot) as Dictionary
	return weapon_owner.call("equip_weapon_item", item) as Dictionary


static func _failure(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	var result := {
		"success": false,
		"code": code,
		"message": message,
	}
	for key in details:
		result[key] = details[key]
	return result
