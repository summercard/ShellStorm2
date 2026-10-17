class_name InventoryModule
extends RefCounted
## 背包格子与容量管理模块
## 负责：格子容量、物品存取、物品堆叠、超格拒绝

signal inventory_changed()
signal item_added(slot: int, item: Dictionary)
signal item_removed(slot: int)
signal capacity_changed(current: int, maximum: int)

const DEFAULT_CAPACITY: int = 40  # 默认8列×5行，共40个棋盘格
const GRID_COLUMNS: int = 8

class InventorySlot:
	var item: Dictionary = {}
	var count: int = 0
	## 棋盘锚点。slot 索引仍保留为锚点线性索引，兼容旧存档与旧 UI 命令。
	var grid_position := Vector2i(-1, -1)
	var rotation_quarters: int = 0
	
	func is_empty() -> bool:
		return item.is_empty() or count <= 0
	
	func clear() -> void:
		item.clear()
		count = 0
		grid_position = Vector2i(-1, -1)
		rotation_quarters = 0
	
	func set_item(itm: Dictionary, n: int) -> void:
		item = itm.duplicate(true)
		count = n
		rotation_quarters = int(item.get("grid_rotation", 0)) % 4

	func set_grid_position(position: Vector2i) -> void:
		grid_position = position

	func get_grid_size() -> Vector2i:
		var base := ItemRegistry.grid_size_of(item)
		return Vector2i(base.y, base.x) if rotation_quarters % 2 == 1 else base
	
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
	_capacity = target_capacity
	_slots.clear()
	_slots.resize(_capacity)
	for index in range(_capacity):
		_slots[index] = InventorySlot.new()
	for entry_variant in packed:
		var entry := entry_variant as Dictionary
		var item := entry.get("item", {}) as Dictionary
		var placement := _find_placement_for_entry(item, int(entry.get("grid_rotation", 0)))
		if placement.is_empty():
			overflow.append(entry.duplicate(true))
			continue
		_write_entry_at(int(placement.get("slot", -1)), item, int(entry.get("count", 1)), int(placement.get("grid_rotation", 0)))
	inventory_changed.emit()
	capacity_changed.emit(get_used_slots(), _capacity)
	return overflow

## 获取容量
func get_capacity() -> int:
	return _capacity

## 旧接口返回物品锚点数，保留给旧存档/门禁。
func get_used_slots() -> int:
	var count := 0
	for slot in _slots:
		if not slot.is_empty():
			count += 1
	return count

## 棋盘实际占用面积。UI 容量应优先显示这个值，而不是锚点数量。
func get_used_area() -> int:
	var area := 0
	for slot in _slots:
		if slot.is_empty():
			continue
		var size := slot.get_grid_size()
		area += size.x * size.y
	return area

## 棋盘宽度。容量变化时按固定8列向下扩展行数。
func get_grid_columns() -> int:
	return GRID_COLUMNS

func get_grid_rows() -> int:
	return ceili(float(_capacity) / float(GRID_COLUMNS))

func get_grid_dimensions() -> Vector2i:
	return Vector2i(GRID_COLUMNS, get_grid_rows())

## 返回某物品占用的棋盘坐标。item_entry 必须来自 get_slot/get_occupied_slots。
func get_occupied_grid_cells(item_entry: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var index := int(item_entry.get("slot", -1))
	if index < 0:
		return cells
	var origin := Vector2i(index % GRID_COLUMNS, index / GRID_COLUMNS)
	var size := ItemRegistry.grid_size_of(item_entry.get("item", {}) as Dictionary)
	var rotation := int(item_entry.get("grid_rotation", 0))
	if rotation % 2 == 1:
		size = Vector2i(size.y, size.x)
	for y in size.y:
		for x in size.x:
			cells.append(origin + Vector2i(x, y))
	return cells

func _slot_occupied_cells(slot_index: int) -> Array[Vector2i]:
	if slot_index < 0 or slot_index >= _slots.size() or _slots[slot_index].is_empty():
		return []
	return get_occupied_grid_cells({
		"slot": slot_index,
		"item": _slots[slot_index].item,
		"grid_rotation": _slots[slot_index].rotation_quarters,
	})

func _cell_belongs_to_source(cell_index: int, source_index: int) -> bool:
	if source_index < 0:
		return false
	var cell := Vector2i(cell_index % GRID_COLUMNS, cell_index / GRID_COLUMNS)
	return cell in _slot_occupied_cells(source_index)

func _cell_is_free_for_item(cell_index: int, source_index: int = -1, ignored_index: int = -1) -> bool:
	if _cell_belongs_to_source(cell_index, source_index):
		return true
	var cell := Vector2i(cell_index % GRID_COLUMNS, cell_index / GRID_COLUMNS)
	for occupied_index in _slots.size():
		if _slots[occupied_index].is_empty() or occupied_index == source_index or occupied_index == ignored_index:
			continue
		if cell in _slot_occupied_cells(occupied_index):
			return false
	return true

## 判断矩形物品是否能以锚点放入棋盘；允许 source_index 自身占用的格子被忽略。
func can_place_item_at(item: Dictionary, anchor_index: int, rotation_quarters: int = 0, source_index: int = -1, ignored_index: int = -1) -> bool:
	if item.is_empty() or anchor_index < 0 or anchor_index >= _capacity:
		return false
	var size := ItemRegistry.grid_size_of(item)
	if rotation_quarters % 2 == 1:
		size = Vector2i(size.y, size.x)
	var origin := Vector2i(anchor_index % GRID_COLUMNS, anchor_index / GRID_COLUMNS)
	if origin.x + size.x > GRID_COLUMNS or origin.y + size.y > get_grid_rows():
		return false
	for y in size.y:
		for x in size.x:
			var cell := origin + Vector2i(x, y)
			var occupant := cell.y * GRID_COLUMNS + cell.x
			if occupant >= _capacity:
				return false
			if occupant == source_index:
				continue
			if not _cell_is_free_for_item(occupant, source_index, ignored_index):
				return false
	return true

func _find_placement_for_entry(item: Dictionary, preferred_rotation: int = 0, source_index: int = -1) -> Dictionary:
	var rotations: Array[int] = [preferred_rotation % 4]
	if preferred_rotation % 2 == 0:
		rotations.append((preferred_rotation + 1) % 4)
	else:
		rotations.append((preferred_rotation + 1) % 4)
	for rotation in rotations:
		for index in _capacity:
			if can_place_item_at(item, index, rotation, source_index):
				return {"slot": index, "grid_rotation": rotation}
	return {}

func _write_entry_at(anchor_index: int, item: Dictionary, count: int, rotation: int = 0) -> bool:
	if anchor_index < 0 or anchor_index >= _capacity or not can_place_item_at(item, anchor_index, rotation):
		return false
	_slots[anchor_index].set_item(item, count)
	_slots[anchor_index].rotation_quarters = rotation % 4
	_slots[anchor_index].item["grid_rotation"] = _slots[anchor_index].rotation_quarters
	return true

## 找到第一个可放置锚点。标准朝向失败后尝试90°旋转。
func find_valid_placement(item: Dictionary, source_index: int = -1) -> Dictionary:
	for rotation in [0, 1]:
		for index in _capacity:
			if can_place_item_at(item, index, rotation, source_index):
				return {"slot": index, "grid_rotation": rotation}
	return {}

## 剩余可用面积（不是旧的一物一格 free slot）。
func get_free_grid_cells() -> int:
	var occupied := {}
	for entry in get_occupied_slots():
		for cell in get_occupied_grid_cells(entry):
			occupied[str(cell)] = true
	return maxi(0, _capacity - occupied.size())

## 剩余可用格数：兼容旧调用，现返回棋盘剩余面积。
func get_free_slots() -> int:
	return get_free_grid_cells()

func has_space() -> bool:
	return get_free_grid_cells() > 0

## 是否还有足够棋盘面积；精确放置仍由 can_add_item_exact 负责。
func can_add(num_items: int = 1) -> bool:
	return get_free_grid_cells() >= num_items


## 交易预检：已有堆叠的剩余容量也算可用空间；不改变格位。
func can_add_item_exact(item: Dictionary, count: int = 1) -> bool:
	if item.is_empty() or count <= 0 or str(item.get("id", "")).is_empty():
		return false
	if str(item.get("type", "")) == "weapon" and count != 1:
		return false
	var instance_id := str(item.get("weapon_instance_id", ""))
	if not instance_id.is_empty() and has_weapon_instance(instance_id):
		return false
	var remaining := count
	var stack_max := maxi(1, int(item.get("stack_max", 1)))
	for slot in _slots:
		if not slot.is_empty() and _items_can_stack(slot.item, item):
			remaining -= maxi(0, stack_max - slot.count)
			if remaining <= 0:
				return true
	var size := ItemRegistry.grid_size_of(item)
	var required_area := maxi(1, size.x * size.y)
	if remaining <= 0:
		return true
	return find_valid_placement(item) != {} and get_free_grid_cells() >= required_area

## 购买预检：只在独立棋盘副本尝试，失败/余额不足不移动真实物品。
## 普通拾取不调用此口，保留玩家自行布局的规则。
func plan_purchase_add(item: Dictionary, count: int = 1) -> Dictionary:
	var board := InventoryModule.new(_capacity)
	board.restore_slots_snapshot(get_slots_snapshot())
	if board.can_add_item_exact(item, count) and board.add_item(item, count) == count:
		return {"slots": board.get_slots_snapshot(), "sorted": false}
	board.restore_slots_snapshot(get_slots_snapshot())
	board.sort_items()
	if board.can_add_item_exact(item, count) and board.add_item(item, count) == count:
		return {"slots": board.get_slots_snapshot(), "sorted": true}
	return {}

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
	
	# 再按矩形占位寻找锚点。一个堆叠块只占一份物理矩形。
	while remaining > 0:
		var placement := find_valid_placement(item)
		if placement.is_empty():
			break  # 棋盘没有可容纳该物品的连续区域
		var anchor_index := int(placement.get("slot", -1))
		if anchor_index < 0:
			break
		var stack_max: int = item.get("stack_max", 1)
		var can_put: int = min(stack_max, remaining)
		_slots[anchor_index].set_item(item, can_put)
		_slots[anchor_index].item = item.duplicate(true)
		_slots[anchor_index].rotation_quarters = int(placement.get("grid_rotation", 0))
		_slots[anchor_index].item["grid_rotation"] = _slots[anchor_index].rotation_quarters
		remaining -= can_put
		item_added.emit(anchor_index, item)
	
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
	var result := {
		"item": slot.item.duplicate(true),
		"count": slot.count,
		"slot": slot_index
	}
	if slot.rotation_quarters % 4 != 0:
		result["grid_rotation"] = slot.rotation_quarters % 4
	return result

## 获取所有非空格子（用于UI渲染）
func get_occupied_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in _slots.size():
		if not _slots[i].is_empty():
			result.append(get_slot(i))
	return result

## 事务用完整格位快照。保留空格和原索引，供基地仓储/商店失败时精确回滚。
func get_slots_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in _slots.size():
		result.append(get_slot(index))
	return result

func restore_slots_snapshot(snapshot: Array) -> void:
	for slot in _slots:
		slot.clear()
	# 旧档的 slot 仍作为首选锚点；大物品原位放不下时再找合法位置。
	for index in snapshot.size():
		if not snapshot[index] is Dictionary:
			continue
		var entry := snapshot[index] as Dictionary
		var item := entry.get("item", {}) as Dictionary
		var count := int(entry.get("count", 0))
		if item.is_empty() or count <= 0:
			continue
		var rotation := int(entry.get("grid_rotation", item.get("grid_rotation", 0))) % 4
		var placement := {"slot": index, "grid_rotation": rotation} if can_place_item_at(item, index, rotation) else _find_placement_for_entry(item, rotation)
		# Legacy snapshots may use another row width. Recover all owned items.
		while placement.is_empty():
			var start := _capacity
			_capacity += GRID_COLUMNS
			for extra in range(start, _capacity):
				_slots.append(InventorySlot.new())
			placement = _find_placement_for_entry(item, rotation)
		_write_entry_at(int(placement.get("slot", -1)), item, count, int(placement.get("grid_rotation", rotation)))
	inventory_changed.emit()
	capacity_changed.emit(get_used_slots(), _capacity)

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


## 将一个完整物品写入指定锚点。装备位卸装使用该接口，禁止覆盖已占区域。
func put_item_in_empty_slot(slot_index: int, item: Dictionary, count: int = 1) -> bool:
	if slot_index < 0 or slot_index >= _slots.size() or item.is_empty() or count <= 0:
		return false
	var normalized := WeaponInstance.ensure_weapon_item(item)
	if str(normalized.get("type", "")) == "weapon" and count != 1:
		return false
	var instance_id := str(normalized.get("weapon_instance_id", ""))
	if not instance_id.is_empty() and has_weapon_instance(instance_id):
		return false
	var rotation := int(normalized.get("grid_rotation", 0))
	if not can_place_item_at(normalized, slot_index, rotation):
		return false
	_write_entry_at(slot_index, normalized, count, rotation)
	item_added.emit(slot_index, normalized)
	inventory_changed.emit()
	capacity_changed.emit(get_used_slots(), _capacity)
	return true


## 背包内拖拽移动/交换。以矩形占位做原子预检，不会把大物品塞进重叠区域。
func can_move_or_swap_slots(from_index: int, to_index: int, requested_rotation: int = -1) -> bool:
	if from_index < 0 or from_index >= _slots.size() or to_index < 0 or to_index >= _slots.size() or _slots[from_index].is_empty():
		return false
	var rotation := _slots[from_index].rotation_quarters if requested_rotation < 0 else posmod(requested_rotation, 4)
	if not can_place_item_at(_slots[from_index].item, to_index, rotation, from_index, to_index):
		return false
	if from_index == to_index or _slots[to_index].is_empty():
		return true
	if not can_place_item_at(_slots[to_index].item, from_index, _slots[to_index].rotation_quarters, from_index, to_index):
		return false
	var source_cells := get_occupied_grid_cells({"slot": to_index, "item": _slots[from_index].item, "grid_rotation": rotation})
	var target_cells := get_occupied_grid_cells({"slot": from_index, "item": _slots[to_index].item, "grid_rotation": _slots[to_index].rotation_quarters})
	for cell in source_cells:
		if cell in target_cells:
			return false
	return true

func move_or_swap_slots(from_index: int, to_index: int, requested_rotation: int = -1) -> bool:
	# Preflight is read-only: rejected rotation must not alter the source footprint.
	if not can_move_or_swap_slots(from_index, to_index, requested_rotation):
		return false
	var source_item := _slots[from_index].item.duplicate(true)
	var source_count := _slots[from_index].count
	var source_rotation := _slots[from_index].rotation_quarters if requested_rotation < 0 else posmod(requested_rotation, 4)
	var target_item := _slots[to_index].item.duplicate(true)
	var target_count := _slots[to_index].count
	var target_rotation := _slots[to_index].rotation_quarters
	_slots[from_index].clear()
	_slots[to_index].clear()
	_write_entry_at(to_index, source_item, source_count, source_rotation)
	if from_index != to_index and not target_item.is_empty():
		_write_entry_at(from_index, target_item, target_count, target_rotation)
	inventory_changed.emit()
	capacity_changed.emit(get_used_slots(), _capacity)
	return true


## 稳定整理：类型 → 稀有度 → 名称 → 枪械实例 ID；面积优先，再按稳定键。
func sort_items() -> void:
	var packed: Array[Dictionary] = get_occupied_slots()
	var before_snapshot := get_slots_snapshot()
	packed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_item := a.get("item", {}) as Dictionary
		var b_item := b.get("item", {}) as Dictionary
		var a_size := ItemRegistry.grid_size_of(a_item)
		var b_size := ItemRegistry.grid_size_of(b_item)
		var a_area := a_size.x * a_size.y
		var b_area := b_size.x * b_size.y
		if a_area != b_area:
			return a_area > b_area
		return _sort_key(a_item).naturalnocasecmp_to(_sort_key(b_item)) < 0
	)
	for slot in _slots:
		slot.clear()
	var failed_item_id := ""
	for entry_variant in packed:
		var entry := entry_variant as Dictionary
		var placement := find_valid_placement(entry.get("item", {}) as Dictionary)
		if placement.is_empty():
			failed_item_id = str((entry.get("item", {}) as Dictionary).get("id", ""))
			break
		_write_entry_at(int(placement.get("slot", -1)), entry.get("item", {}) as Dictionary, int(entry.get("count", 1)), int(placement.get("grid_rotation", 0)))
	if not failed_item_id.is_empty():
		# 整理必须是原子操作：任何物品放不下，恢复完整快照，禁止静默丢失。
		restore_slots_snapshot(before_snapshot)
		push_warning("[InventoryModule] sort_items rolled back; could not fit: %s" % failed_item_id)
		return
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
