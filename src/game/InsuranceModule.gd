class_name InsuranceModule
extends RefCounted
## 保险格管理模块
## 负责：保险格数量上限、保险/取出规则、死亡后保底

signal insurance_changed()
signal item_insured(slot: int, item: Dictionary)
signal item_claimed(item: Dictionary)
signal insurance_full()

const DEFAULT_INSURANCE_SLOTS: int = 2  # 默认2个保险格

class InsuranceSlot:
	var item: Dictionary = {}
	var insured_at: int = 0  # 时间戳
	
	func is_empty() -> bool:
		return item.is_empty()
	
	func clear() -> void:
		item.clear()
		insured_at = 0
	
	func set_item(itm: Dictionary) -> void:
		item = WeaponInstance.ensure_weapon_item(itm).duplicate(true)
		insured_at = Time.get_unix_time_from_system()

var _insurance_slots: Array[InsuranceSlot] = []
var _max_slots: int = DEFAULT_INSURANCE_SLOTS
var _carry_over_on_death: bool = true

func _init(max_slots: int = DEFAULT_INSURANCE_SLOTS) -> void:
	_max_slots = max_slots
	_insurance_slots.resize(_max_slots)
	for i in range(_insurance_slots.size()):
		_insurance_slots[i] = InsuranceSlot.new()

## 设置保险格上限
func set_max_slots(max_s: int) -> void:
	_max_slots = max(0, max_s)
	_insurance_slots.resize(_max_slots)
	for i in range(_insurance_slots.size()):
		if _insurance_slots[i] == null:
			_insurance_slots[i] = InsuranceSlot.new()
	insurance_changed.emit()

## 获取保险格上限
func get_max_slots() -> int:
	return _max_slots

## 获取已用保险格数量
func get_used_slots() -> int:
	var count := 0
	for slot in _insurance_slots:
		if not slot.is_empty():
			count += 1
	return count

## 是否有空闲保险格
func has_space() -> bool:
	return get_used_slots() < _max_slots

## 获取空闲保险格数量
func get_free_slots() -> int:
	return _max_slots - get_used_slots()

## 保险物品（从背包指定格子）
## 物品会被从 InventoryModule 转移到保险格
## 返回是否成功
func insure_item(inventory: InventoryModule, slot_index: int) -> bool:
	if inventory == null:
		return false
	
	if not has_space():
		insurance_full.emit()
		return false
	
	var slot_data: Dictionary = inventory.get_slot(slot_index)
	if slot_data.is_empty():
		return false
	var instance_id := str((slot_data.get("item", {}) as Dictionary).get("weapon_instance_id", ""))
	if not instance_id.is_empty() and has_weapon_instance(instance_id):
		return false
	
	var empty_idx := _find_empty_slot()
	if empty_idx < 0:
		return false
	
	_insurance_slots[empty_idx].set_item(slot_data["item"])
	inventory.remove_from_slot(slot_index, slot_data["count"])
	
	insurance_changed.emit()
	item_insured.emit(empty_idx, slot_data["item"])
	return true

## 保险指定物品（直接传入物品数据）
func insure_item_direct(item: Dictionary) -> bool:
	if item.is_empty():
		return false
	
	var instance_id := str(item.get("weapon_instance_id", ""))
	if not instance_id.is_empty() and has_weapon_instance(instance_id):
		return false
	if not has_space():
		insurance_full.emit()
		return false
	
	var empty_idx := _find_empty_slot()
	if empty_idx < 0:
		return false
	
	_insurance_slots[empty_idx].set_item(item)
	insurance_changed.emit()
	item_insured.emit(empty_idx, item)
	return true

## 从保险格取出物品（返还给玩家）
## 返回物品数据，失败返回空字典
func claim_item(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= _insurance_slots.size():
		return {}
	var slot: InsuranceSlot = _insurance_slots[slot_index]
	if slot.is_empty():
		return {}
	
	var item: Dictionary = slot.item.duplicate(true)
	slot.clear()
	insurance_changed.emit()
	item_claimed.emit(item)
	return item

## 取出所有保险物品（用于撤离成功后）
func claim_all() -> Array[Dictionary]:
	var claimed: Array[Dictionary] = []
	for slot in _insurance_slots:
		if not slot.is_empty():
			claimed.append(slot.item.duplicate(true))
			slot.clear()
	insurance_changed.emit()
	return claimed

## 死亡时触发：保险格内物品必定保留（不丢失）
## 返回应该保留的物品列表（实际上保险格物品本来就不会丢失）
func on_player_death() -> Array[Dictionary]:
	# 保险格物品默认保留，这是核心价值
	return claim_all()

## 清空保险格（整局重置）
func clear_all() -> void:
	for slot in _insurance_slots:
		slot.clear()
	insurance_changed.emit()

## 获取所有保险物品（用于UI）
## 返回格式与 InventoryModule.get_occupied_slots() 对齐：{item, count, insurance_slot}
func get_all_insured_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in _insurance_slots.size():
		if not _insurance_slots[i].is_empty():
			var d: Dictionary = {
				"item": _insurance_slots[i].item.duplicate(true),
				"count": 1,
				"insurance_slot": i  # 与 GameUIManager._refresh_insurance_ui() 的 key 对齐
			}
			result.append(d)
	return result

## API 对齐方法（与 InventoryModule.get_occupied_slots() 对称）
func get_occupied_slots() -> Array[Dictionary]:
	return get_all_insured_items()

## 是否有保险某物品
func has_item(item_id: String) -> bool:
	for slot in _insurance_slots:
		if not slot.is_empty() and slot.item.get("id", "") == item_id:
			return true
	return false


func has_weapon_instance(weapon_instance_id: String) -> bool:
	if weapon_instance_id.is_empty():
		return false
	for slot in _insurance_slots:
		if not slot.is_empty() and str(slot.item.get("weapon_instance_id", "")) == weapon_instance_id:
			return true
	return false

func _find_empty_slot() -> int:
	for i in _insurance_slots.size():
		if _insurance_slots[i].is_empty():
			return i
	return -1

## 调试状态
func debug_status() -> String:
	var lines: Array[String] = ["InsuranceModule [%d/%d]" % [get_used_slots(), _max_slots]]
	for i in _insurance_slots.size():
		if not _insurance_slots[i].is_empty():
			lines.append("  [%d] %s (insured at %d)" % [i, _insurance_slots[i].item.get("id", ""), _insurance_slots[i].insured_at])
	return "\n".join(lines)
