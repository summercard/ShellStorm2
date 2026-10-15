class_name InsuranceModule
extends RefCounted
## 保险所有权与跨局保留；矩形占格统一委托 InventoryModule。
signal insurance_changed()
signal item_insured(slot: int, item: Dictionary)
signal item_claimed(item: Dictionary)
signal insurance_full()
const DEFAULT_INSURANCE_SLOTS := 16
var _board: InventoryModule

func _init(max_slots: int = DEFAULT_INSURANCE_SLOTS) -> void:
	_board = InventoryModule.new(maxi(1, max_slots))
	_board.inventory_changed.connect(func() -> void: insurance_changed.emit())

func set_max_slots(max_s: int) -> void:
	# Shrinking never silently removes insured property.
	var snapshot := get_slots_snapshot()
	_board = InventoryModule.new(maxi(1, max_s))
	restore_slots_snapshot(snapshot)
	_board.inventory_changed.connect(func() -> void: insurance_changed.emit())
	insurance_changed.emit()

func get_max_slots() -> int:
	return _board.get_capacity()

func get_used_slots() -> int:
	return _board.get_used_slots()

func get_free_slots() -> int:
	return _board.get_free_grid_cells()

func has_space() -> bool:
	return get_free_slots() > 0

func can_place_item_at(item: Dictionary, anchor: int, rotation: int = 0) -> bool:
	return _board.can_place_item_at(item, anchor, rotation)

func can_move_or_swap_slots(source: int, target: int, rotation: int = -1) -> bool:
	return _board.can_move_or_swap_slots(source, target, rotation)

func move_or_swap_slots(source: int, target: int, rotation: int = -1) -> bool:
	return _board.move_or_swap_slots(source, target, rotation)

func insure_item(inventory: InventoryModule, slot_index: int) -> bool:
	if inventory == null:
		return false
	var entry := inventory.get_slot(slot_index)
	var placement := _board.find_valid_placement(entry.get("item", {}))
	if placement.is_empty():
		insurance_full.emit()
		return false
	return insure_item_to_slot(inventory, slot_index, int(placement.slot), int(placement.grid_rotation))

func insure_item_to_slot(inventory: InventoryModule, source_slot_index: int, insurance_slot_index: int, rotation: int = -1) -> bool:
	if inventory == null:
		return false
	var entry := inventory.get_slot(source_slot_index)
	var item: Dictionary = entry.get("item", {}).duplicate(true)
	if item.is_empty() or has_weapon_instance(str(item.get("weapon_instance_id", ""))):
		return false
	if rotation >= 0:
		item["grid_rotation"] = rotation
	if not _board.can_place_item_at(item, insurance_slot_index, int(item.get("grid_rotation", 0))):
		insurance_full.emit()
		return false
	var count := int(entry.get("count", 1))
	if not _board.put_item_in_empty_slot(insurance_slot_index, item, count):
		return false
	if not inventory.remove_from_slot(source_slot_index, count):
		_board.clear_slot(insurance_slot_index)
		return false
	item_insured.emit(insurance_slot_index, item)
	return true

func insure_item_direct(item: Dictionary) -> bool:
	if item.is_empty() or has_weapon_instance(str(item.get("weapon_instance_id", ""))):
		return false
	var placement := _board.find_valid_placement(item)
	if placement.is_empty():
		insurance_full.emit()
		return false
	var copy := WeaponInstance.ensure_weapon_item(item).duplicate(true)
	copy["grid_rotation"] = int(placement.grid_rotation)
	if not _board.put_item_in_empty_slot(int(placement.slot), copy, maxi(1, int(item.get("count", 1)))):
		return false
	item_insured.emit(int(placement.slot), copy)
	return true

func claim_item(slot_index: int) -> Dictionary:
	var entry := _board.get_slot(slot_index)
	if entry.is_empty():
		return {}
	var item: Dictionary = entry.item.duplicate(true)
	item["count"] = int(entry.count)
	_board.clear_slot(slot_index)
	item_claimed.emit(item)
	return item

func claim_all() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _board.get_occupied_slots():
		var item: Dictionary = entry.item.duplicate(true)
		item["count"] = int(entry.count)
		result.append(item)
	_board.clear_all()
	return result

func on_player_death() -> Array[Dictionary]:
	return claim_all()

func clear_all() -> void:
	_board.clear_all()

func get_all_insured_items() -> Array[Dictionary]:
	var result := _board.get_occupied_slots()
	for entry in result:
		entry["insurance_slot"] = int(entry.slot)
	return result

func get_occupied_slots() -> Array[Dictionary]:
	return get_all_insured_items()

func get_slots_snapshot() -> Array[Dictionary]:
	var result := _board.get_slots_snapshot()
	for index in result.size():
		if not result[index].is_empty():
			result[index]["insurance_slot"] = index
	return result

func restore_slots_snapshot(snapshot: Array) -> void:
	_board.clear_all()
	for index in snapshot.size():
		if not snapshot[index] is Dictionary:
			continue
		var entry: Dictionary = snapshot[index]
		var item: Dictionary = entry.get("item", {}).duplicate(true)
		if item.is_empty():
			continue
		item = WeaponInstance.ensure_weapon_item(item)
		var rotation := int(entry.get("grid_rotation", item.get("grid_rotation", 0)))
		var placement := {"slot": index, "grid_rotation": rotation} if _board.can_place_item_at(item, index, rotation) else _board.find_valid_placement(item)
		# Legacy independent slots could hold objects taller than two cells.
		# Expand recovery rows only while loading, preserving every saved item.
		while placement.is_empty():
			_board.set_capacity(_board.get_capacity() + 8)
			placement = _board.find_valid_placement(item)
		item["grid_rotation"] = int(placement.grid_rotation)
		_board.put_item_in_empty_slot(int(placement.slot), item, maxi(1, int(entry.get("count", 1))))
	insurance_changed.emit()

func has_item(item_id: String) -> bool:
	for entry in _board.get_occupied_slots():
		if str(entry.item.get("id", "")) == item_id:
			return true
	return false

func has_weapon_instance(instance_id: String) -> bool:
	if instance_id.is_empty():
		return false
	for entry in _board.get_occupied_slots():
		if str(entry.item.get("weapon_instance_id", "")) == instance_id:
			return true
	return false

func debug_status() -> String:
	return "InsuranceModule [%d/%d]" % [_board.get_used_area(), get_max_slots()]
