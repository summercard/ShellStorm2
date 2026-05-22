class_name InventoryModule
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
		item = itm.duplicate()
		count = n
	
	func get_item_id() -> String:
		return item.get("id", "")

var _slots: Array[InventorySlot] = []
var _capacity: int = DEFAULT_CAPACITY
var _loot_table: Dictionary = {}

func _init(capacity: int = DEFAULT_CAPACITY) -> void:
	_capacity = capacity
	_slots.resize(_capacity)
	for i in _slots:
		i = InventorySlot.new()

## 设置容量
func set_capacity(cap: int) -> void:
	_capacity = max(1, cap)
	_slots.resize(_capacity)
	capacity_changed.emit(_slots.size(), _capacity)

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
	
	var item_id: String = item.get("id", "")
	if item_id.is_empty():
		return 0
	
	var remaining: int = count
	
	# 先尝试堆叠到已有格子
	for slot in _slots:
		if not slot.is_empty() and slot.get_item_id() == item_id:
			var stack_max: int = item.get("stack_max", 1)
			if slot.count < stack_max:
				var can_put: int = min(stack_max - slot.count, remaining)
				slot.count += can_put
				remaining -= can_put
				if remaining <= 0:
					inventory_changed.emit()
					slot.item = item.duplicate()
					return count
	
	# 再找空格子放剩余的
	while remaining > 0:
		var empty_idx := _find_empty_slot()
		if empty_idx < 0:
			break  # 没有空格子了
		var stack_max: int = item.get("stack_max", 1)
		var can_put: int = min(stack_max, remaining)
		_slots[empty_idx].set_item(item, can_put)
		_slots[empty_idx].item = item.duplicate()
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
		"item": slot.item.duplicate(),
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

## 调试状态
func debug_status() -> String:
	var lines: Array[String] = ["Inventory [%d/%d]" % [get_used_slots(), _capacity]]
	for i in _slots.size():
		if not _slots[i].is_empty():
			lines.append("  [%d] %s x%d" % [i, _slots[i].get_item_id(), _slots[i].count])
	return "\n".join(lines)