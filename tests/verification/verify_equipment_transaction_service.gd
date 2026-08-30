extends Node

const EQUIPMENT_TRANSACTION_SERVICE = preload("res://src/game/EquipmentTransactionService.gd")


class FakeWeaponOwner:
	extends RefCounted

	var slots: Array[Dictionary] = [{}, {}]
	var active_slot := 0
	var reject_next_equip := false

	func equip_weapon_item(item: Dictionary) -> Dictionary:
		return equip_weapon_item_to_slot(item, active_slot)

	func equip_weapon_item_to_slot(item: Dictionary, slot_index: int) -> Dictionary:
		if reject_next_equip:
			reject_next_equip = false
			return {"success": false, "reason": "verification rejection"}
		if slot_index < 0 or slot_index >= slots.size():
			return {"success": false, "reason": "invalid slot"}
		var old_item := slots[slot_index].duplicate(true)
		slots[slot_index] = item.duplicate(true)
		return {
			"success": true,
			"old_item": old_item,
			"new_item": item.duplicate(true),
			"snapshot": {
				"display_name": item.get("name", ""),
				"instance_suffix": str(item.get("weapon_instance_id", "")).right(6),
			},
			"slot_index": slot_index,
		}

	func get_equipped_weapon_instance_id_for_slot(slot_index: int) -> String:
		if slot_index < 0 or slot_index >= slots.size():
			return ""
		return str(slots[slot_index].get("weapon_instance_id", ""))


func _ready() -> void:
	var failures: Array[String] = []
	var inventory := InventoryModule.new(2)
	var owner := FakeWeaponOwner.new()
	var primary := _weapon("weapon_pistol", "verify-primary")
	var incoming := _weapon("weapon_shotgun", "verify-incoming")
	owner.slots[0] = primary.duplicate(true)
	_expect(inventory.add_item(incoming, 1) == 1, "Cannot seed incoming weapon", failures)
	var source_slot := _find_slot(inventory, "verify-incoming")

	var swapped: Dictionary = EQUIPMENT_TRANSACTION_SERVICE.equip_weapon_from_inventory(
		inventory, owner, source_slot, incoming, 0
	)
	_expect(bool(swapped.get("success", false)), "Valid weapon swap was rejected", failures)
	_expect(
		owner.get_equipped_weapon_instance_id_for_slot(0) == "verify-incoming",
		"Incoming instance did not reach requested equipment slot",
		failures
	)
	_expect(
		_find_slot(inventory, "verify-primary") >= 0,
		"Displaced weapon instance did not return to inventory",
		failures
	)
	_expect(
		_find_slot(inventory, "verify-incoming") < 0,
		"Incoming instance remained duplicated in inventory",
		failures
	)

	_expect(
		inventory.add_item(owner.slots[0], 1) == 1,
		"Cannot seed duplicate-instance guard case",
		failures
	)
	var inventory_before_duplicate := inventory.get_slots_snapshot()
	var duplicate_result: Dictionary = EQUIPMENT_TRANSACTION_SERVICE.equip_weapon_from_inventory(
		inventory, owner, _find_slot(inventory, "verify-incoming"), owner.slots[0], 1
	)
	_expect(
		str(duplicate_result.get("code", "")) == "duplicate_instance",
		"Duplicate equipped instance was not rejected at transaction boundary",
		failures
	)
	_expect(
		inventory.get_slots_snapshot() == inventory_before_duplicate,
		"Duplicate rejection mutated inventory",
		failures
	)

	inventory.clear_all()
	var rejected := _weapon("weapon_rifle", "verify-rejected")
	_expect(inventory.add_item(rejected, 1) == 1, "Cannot seed rejection rollback case", failures)
	var inventory_before_rejection := inventory.get_slots_snapshot()
	var equipment_before_rejection := owner.slots[1].duplicate(true)
	owner.reject_next_equip = true
	var rejected_result: Dictionary = EQUIPMENT_TRANSACTION_SERVICE.equip_weapon_from_inventory(
		inventory, owner, _find_slot(inventory, "verify-rejected"), rejected, 1
	)
	_expect(
		str(rejected_result.get("code", "")) == "equip_rejected",
		"Owner rejection did not return the expected transaction code",
		failures
	)
	_expect(
		inventory.get_slots_snapshot() == inventory_before_rejection,
		"Owner rejection did not restore the exact inventory snapshot",
		failures
	)
	_expect(
		owner.slots[1] == equipment_before_rejection,
		"Owner rejection mutated the target equipment slot",
		failures
	)

	_finish(failures)


func _weapon(item_id: String, instance_id: String) -> Dictionary:
	var item := ItemRegistry.get_instance().get_item(item_id)
	item["weapon_instance_id"] = instance_id
	return WeaponInstance.ensure_weapon_item(item)


func _find_slot(inventory: InventoryModule, instance_id: String) -> int:
	for entry in inventory.get_occupied_slots():
		var item := entry.get("item", {}) as Dictionary
		if str(item.get("weapon_instance_id", "")) == instance_id:
			return int(entry.get("slot", -1))
	return -1


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("EQUIPMENT_TRANSACTION_SERVICE_OK: swap ownership, duplicate guard and exact rejection rollback pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
