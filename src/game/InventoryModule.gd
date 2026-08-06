class_name InventoryModule
extends RefCounted
## 背包格子与容量管理模块
## 负责：格子容量、物品存取、物品堆叠、超格拒绝

signal inventory_changed()
signal item_added(slot: int, item: Dictionary)
signal item_removed(slot: int)
signal capacity_changed(current: int, maximum: int)

const DEFAULT_CAPACITY: int = 12  # 默认12格

class InventorySlot:
	var item: Dictionary = {}
	var count: int = 0
	
	func is_empty() -> bool:
		return item.is_empty() or count <= 0
	
	func clear() -> void:
		item.clear()
		count = 0
	
	func set_item(itm: Dictionary, n: int) -> void:
		item = itm.duplicate(true)
		count = n
	
	func get_item_id() -> String:
		return item.get("id", "")

var _slots: Array[InventorySlot] = []
var _capacity: int = DEFAULT_CAPACITY
var _loot_table: Dictionary = {}

func _init(capacity: int = DEFAULT_CAPACITY) -> void:
	_capacity = capacity
	_slots.resize(_capacity)
	for i in range(_slots.size()):
		_slots[i] = InventorySlot.new()

## 设置容量
func set_capacity(cap: int) -> void:
	var overflow := resize_capacity_collect_overflow(cap)
	if not overflow.is_empty():
		push_warning("[InventoryModule] set_capacity dropped overflow without a world owner; use resize_capacity_collect_overflow() for shrinking")


## 原子调整容量并返回无法保留的完整格子。物品按原格位顺序稳定压缩，
## 因此基础/低索引格优先保留，扩展区末尾物品先成为地面溢出候选。
func resize_capacity_collect_overflow(cap: int) -> Array[Dictionary]:
	var target_capacity := maxi(1, cap)
	if target_capacity == _capacity:
		return []
	var packed := get_occupied_slots()
	var overflow: Array[Dictionary] = []
	if packed.size() > target_capacity:
		for index in range(target_capacity, packed.size()):
			overflow.append((packed[index] as Dictionary).duplicate(true))
		packed.resize(target_capacity)
	_capacity = target_capacity
	_slots.clear()
	_slots.resize(_capacity)
	for index in range(_capacity):
		_slots[index] = InventorySlot.new()
	for index in range(packed.size()):
		var entry := packed[index] as Dictionary
		_slots[index].set_item(
			entry.get("item", {}) as Dictionary,
			int(entry.get("count", 1))
		)
	inventory_changed.emit()
	capacity_changed.emit(get_used_slots(), _capacity)
	return overflow

## 获取容量
func get_capacity() -> int:
	return _capacity

## 实际使用格子数
func get_used_slots() -> int:
	var count := 0
	for slot in _slots:
		if not slot.is_empty():
			count += 1
	return count

## 剩余可用格子数
func get_free_slots() -> int:
	return _capacity - get_used_slots()

## 是否还有空间
func has_space() -> bool:
	return get_free_slots() > 0

## 是否可以放入指定数量
func can_add(num_items: int = 1) -> bool:
	return get_free_slots() >= num_items

## 添加物品（自动分配格子）
## 返回实际成功添加的数量
func add_item(item: Dictionary, count: int = 1) -> int:
	if item.is_empty() or count <= 0:
		return 0
	# 一个枪械字典只代表一个真实实例；禁止用 count 复制同一实例 ID。
	if str(item.get("type", "")) == "weapon" and count != 1:
		return 0
	item = WeaponInstance.ensure_weapon_item(item)
	
	var item_id: String = item.get("id", "")
	if item_id.is_empty():
		return 0
	
	var remaining: int = count
	var instance_id := str(item.get("weapon_instance_id", ""))
	if not instance_id.is_empty() and has_weapon_instance(instance_id):
		return 0
	
	# 先尝试堆叠到已有格子
	for slot in _slots:
		if not slot.is_empty() and _items_can_stack(slot.item, item):
			var stack_max: int = item.get("stack_max", 1)
			if slot.count < stack_max:
				var can_put: int = min(stack_max - slot.count, remaining)
				slot.count += can_put
				remaining -= can_put
				if remaining <= 0:
					inventory_changed.emit()
					slot.item = item.duplicate(true)
					return count
	
	# 再找空格子放剩余的
	while remaining > 0:
		var empty_idx := _find_empty_slot()
		if empty_idx < 0:
			break  # 没有空格子了
		var stack_max: int = item.get("stack_max", 1)
		var can_put: int = min(stack_max, remaining)
		_slots[empty_idx].set_item(item, can_put)
		_slots[empty_idx].item = item.duplicate(true)
		remaining -= can_put
		item_added.emit(empty_idx, item)
	
	if remaining < count:
		inventory_changed.emit()
		capacity_changed.emit(get_used_slots(), _capacity)
	
	return count - remaining

## 移除物品（指定格子）
func remove_from_slot(slot_index: int, count: int = 1) -> bool:
	if slot_index < 0 or slot_index >= _slots.size():
		return false
	var slot: InventorySlot = _slots[slot_index]
	if slot.is_empty():
		return false
	
	var to_remove: int = min(count, slot.count)
	slot.count -= to_remove
	if slot.count <= 0:
		slot.clear()
		item_removed.emit(slot_index)
	
	inventory_changed.emit()
	capacity_changed.emit(get_used_slots(), _capacity)
	return true

## 从指定格子获取物品信息
func get_slot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= _slots.size():
		return {}
	var slot: InventorySlot = _slots[slot_index]
	if slot.is_empty():
		return {}
	return {
		"item": slot.item.duplicate(true),
		"count": slot.count,
		"slot": slot_index
	}

## 获取所有非空格子（用于UI渲染）
func get_occupied_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in _slots.size():
		if not _slots[i].is_empty():
			result.append(get_slot(i))
	return result

## 清空指定格子
func clear_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= _slots.size():
		return false
	_slots[slot_index].clear()
	item_removed.emit(slot_index)
	inventory_changed.emit()
	capacity_changed.emit(get_used_slots(), _capacity)
	return true

## 清空所有格子
func clear_all() -> void:
	for slot in _slots:
		slot.clear()
	inventory_changed.emit()
	capacity_changed.emit(0, _capacity)

## 丢弃随机物品（死亡掉落用）
func drop_random_items(loss_ratio: float = 0.5, exclude_ids: Array[String] = []) -> Array[Dictionary]:
	## 随机丢弃部分物品，返回被丢弃的物品列表
	var dropped: Array[Dictionary] = []
	var to_drop: Array[int] = []
	
	for i in _slots.size():
		if not _slots[i].is_empty():
			var item_id: String = _slots[i].get_item_id()
			if item_id not in exclude_ids:
				to_drop.append(i)
	
	to_drop.shuffle()
	var drop_count := int(to_drop.size() * loss_ratio)
	drop_count = min(drop_count, to_drop.size())
	
	for j in drop_count:
		var idx: int = to_drop[j]
		dropped.append(get_slot(idx))
		clear_slot(idx)
	
	return dropped

## 转移物品到另一 InventoryModule
func transfer_to(target: InventoryModule, slot_index: int) -> bool:
	if target == null:
		return false
	var slot_data: Dictionary = get_slot(slot_index)
	if slot_data.is_empty():
		return false
	
	var item: Dictionary = slot_data["item"]
	var count: int = slot_data["count"]
	var transferred: int = target.add_item(item, count)
	if transferred > 0:
		remove_from_slot(slot_index, transferred)
		return true
	return false

## 获取物品总数（按ID统计）
func get_item_count(item_id: String) -> int:
	var total := 0
	for slot in _slots:
		if not slot.is_empty() and slot.get_item_id() == item_id:
			total += slot.count
	return total

## 是否有某物品
func has_item(item_id: String) -> bool:
	return get_item_count(item_id) > 0


func has_weapon_instance(weapon_instance_id: String) -> bool:
	if weapon_instance_id.is_empty():
		return false
	for slot in _slots:
		if not slot.is_empty() and str(slot.item.get("weapon_instance_id", "")) == weapon_instance_id:
			return true
	return false


func find_weapon_instance_slot(weapon_instance_id: String) -> int:
	if weapon_instance_id.is_empty():
		return -1
	for i in _slots.size():
		if not _slots[i].is_empty() and str(_slots[i].item.get("weapon_instance_id", "")) == weapon_instance_id:
			return i
	return -1


func replace_item_in_slot(slot_index: int, item: Dictionary) -> bool:
	if slot_index < 0 or slot_index >= _slots.size() or item.is_empty():
		return false
	var normalized := WeaponInstance.ensure_weapon_item(item)
	var instance_id := str(normalized.get("weapon_instance_id", ""))
	var existing_index := find_weapon_instance_slot(instance_id)
	if not instance_id.is_empty() and existing_index >= 0 and existing_index != slot_index:
		return false
	_slots[slot_index].set_item(normalized, 1)
	inventory_changed.emit()
	capacity_changed.emit(get_used_slots(), _capacity)
	return true


## 将一个完整物品写入指定空格。装备位卸装使用该接口，禁止覆盖已有物品。
func put_item_in_empty_slot(slot_index: int, item: Dictionary, count: int = 1) -> bool:
	if slot_index < 0 or slot_index >= _slots.size() or item.is_empty() or count <= 0:
		return false
	if not _slots[slot_index].is_empty():
		return false
	var normalized := WeaponInstance.ensure_weapon_item(item)
	if str(normalized.get("type", "")) == "weapon" and count != 1:
		return false
	var instance_id := str(normalized.get("weapon_instance_id", ""))
	if not instance_id.is_empty() and has_weapon_instance(instance_id):
		return false
	_slots[slot_index].set_item(normalized, count)
	item_added.emit(slot_index, normalized)
	inventory_changed.emit()
	capacity_changed.emit(get_used_slots(), _capacity)
	return true


## 背包内拖拽移动/交换。枪械字典整体换位，不重新生成实例或构筑。
func move_or_swap_slots(from_index: int, to_index: int) -> bool:
	if from_index < 0 or from_index >= _slots.size():
		return false
	if to_index < 0 or to_index >= _slots.size() or from_index == to_index:
		return false
	var source := _slots[from_index]
	if source.is_empty():
		return false
	var source_item := source.item.duplicate(true)
	var source_count := source.count
	var target := _slots[to_index]
	var target_item := target.item.duplicate(true)
	var target_count := target.count
	target.set_item(source_item, source_count)
	if target_item.is_empty() or target_count <= 0:
		source.clear()
	else:
		source.set_item(target_item, target_count)
	inventory_changed.emit()
	capacity_changed.emit(get_used_slots(), _capacity)
	return true


## 稳定整理：类型 → 稀有度 → 名称 → 枪械实例 ID；只改变格位。
func sort_items() -> void:
	var packed: Array[Dictionary] = get_occupied_slots()
	packed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_item := a.get("item", {}) as Dictionary
		var b_item := b.get("item", {}) as Dictionary
		var a_key := _sort_key(a_item)
		var b_key := _sort_key(b_item)
		return a_key.naturalnocasecmp_to(b_key) < 0
	)
	for slot in _slots:
		slot.clear()
	for index in packed.size():
		var entry := packed[index]
		_slots[index].set_item(entry.get("item", {}), int(entry.get("count", 1)))
	inventory_changed.emit()
	capacity_changed.emit(get_used_slots(), _capacity)

## 消耗物品（用于撤离消耗品）
func consume_item(item_id: String, count: int = 1) -> bool:
	var total_needed := count
	for i in _slots.size():
		if not _slots[i].is_empty() and _slots[i].get_item_id() == item_id:
			var can_take: int = min(_slots[i].count, total_needed)
			_slots[i].count -= can_take
			total_needed -= can_take
			if _slots[i].count <= 0:
				_slots[i].clear()
			if total_needed <= 0:
				break
	
	if total_needed > 0:
		return false
	inventory_changed.emit()
	capacity_changed.emit(get_used_slots(), _capacity)
	return true

func _find_empty_slot() -> int:
	for i in _slots.size():
		if _slots[i].is_empty():
			return i
	return -1


func _items_can_stack(existing: Dictionary, incoming: Dictionary) -> bool:
	if str(existing.get("id", "")) != str(incoming.get("id", "")):
		return false
	if str(existing.get("type", "")) == "weapon" or str(incoming.get("type", "")) == "weapon":
		return false
	return str(existing.get("weapon_instance_id", "")).is_empty() and str(
		incoming.get("weapon_instance_id", "")
	).is_empty()


func _sort_key(item: Dictionary) -> String:
	var type_rank: String = str({
		"weapon": "00", "module": "10", "attachment": "11",
		"consumable": "20", "key": "30", "currency": "40",
	}.get(str(item.get("type", "")), "90"))
	var rarity_rank: String = str({
		"legendary": "00", "epic": "10", "rare": "20", "uncommon": "30", "common": "40",
	}.get(str(item.get("rarity", "common")).to_lower(), "50"))
	return "%s|%s|%s|%s|%s" % [
		type_rank,
		rarity_rank,
		str(item.get("name", "")),
		str(item.get("weapon_instance_id", "")),
		str(item.get("id", "")),
	]

## 调试状态
func debug_status() -> String:
	var lines: Array[String] = ["Inventory [%d/%d]" % [get_used_slots(), _capacity]]
	for i in _slots.size():
		if not _slots[i].is_empty():
			lines.append("  [%d] %s x%d" % [i, _slots[i].get_item_id(), _slots[i].count])
	return "\n".join(lines)
