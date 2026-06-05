extends Node

const SAVE_PATH := "user://base_save.json"

var data: BaseData

func _ready() -> void:
	load_base()

func load_base() -> void:
	var json: Variant = AtomicJsonStore.load_dictionary(SAVE_PATH)
	if json is Dictionary:
		var save_version := str(json.get("save_version", "legacy"))
		if save_version != BaseData.SAVE_VERSION:
			push_warning("[BaseManager] Loading compatible save version %s" % save_version)
		data = BaseData.from_dict(json)
		return
	data = BaseData.new()

func _ensure_data() -> void:
	if data == null:
		load_base()

func save_base() -> void:
	_ensure_data()
	AtomicJsonStore.save_dictionary(SAVE_PATH, data._to_dict())

func record_run(success: bool, kills: int) -> void:
	data.record_run(success, kills)
	save_base()

func unlock_building(type: int) -> bool:
	match type:
		0: data.workshop_unlocked = true
		1: data.greenhouse_unlocked = true
		2: data.scrapyard_unlocked = true
		3: data.divination_unlocked = true
		4: data.vault_unlocked = true
		5: data.blackmarket_unlocked = true
		6: data.archive_unlocked = true
	save_base()
	return true

func upgrade_building(type: int) -> bool:
	match type:
		0: data.workshop_level += 1
		1: data.greenhouse_level += 1
		2: data.scrapyard_level += 1
		3: data.divination_level += 1
		4: data.vault_level += 1
		5: data.blackmarket_level += 1
		6: data.archive_level += 1
	save_base()
	return true

func is_unlocked(type: int) -> bool:
	match type:
		0: return data.workshop_unlocked
		1: return data.greenhouse_unlocked
		2: return data.scrapyard_unlocked
		3: return data.divination_unlocked
		4: return data.vault_unlocked
		5: return data.blackmarket_unlocked
		6: return data.archive_unlocked
	return false

func get_level(type: int) -> int:
	match type:
		0: return data.workshop_level
		1: return data.greenhouse_level
		2: return data.scrapyard_level
		3: return data.divination_level
		4: return data.vault_level
		5: return data.blackmarket_level
		6: return data.archive_level
	return 0

# Building unlock costs (in extraction value points)
const UNLOCK_COSTS := {
	0: 100,  # workshop
	1: 80,   # greenhouse
	2: 60,   # scrapyard
	3: 120,  # divination
	4: 150,  # vault
	5: 90,   # blackmarket
	6: 110   # archive
}

# Building upgrade costs per level
const UPGRADE_BASE_COST := {
	0: 50,   # workshop
	1: 40,   # greenhouse
	2: 30,   # scrapyard
	3: 60,   # divination
	4: 75,   # vault
	5: 45,   # blackmarket
	6: 55    # archive
}

func get_unlock_cost(type: int) -> int:
	return UNLOCK_COSTS.get(type, 999)

func get_upgrade_cost(type: int) -> int:
	var base: int = UPGRADE_BASE_COST.get(type, 0)
	return base * (get_level(type) + 1)

func update_long_term_progress(progress_type: String, value: float) -> void:
	match progress_type:
		"blueprint": data.blueprint_progress = clamp(value, 0.0, 1.0)
		"bullet": data.bullet_variant_progress = clamp(value, 0.0, 1.0)
		"boss": data.boss_defeated = true
		"zero_load": data.zero_load_extraction = true
		"five_tier": data.five_tier_weapon_made = true
	save_base()

func get_stats() -> Dictionary:
	return {
		"total_runs": data.total_runs,
		"successful_extractions": data.successful_extractions,
		"total_kills": data.total_kills,
		"extraction_rate": float(data.successful_extractions) / max(1, data.total_runs)
	}

## — 命运卡片局前选择 —
var pending_fate_card: Dictionary = {}

func set_pending_fate_card(card_data: Dictionary) -> void:
	pending_fate_card = card_data
	data.pending_fate_card = card_data
	save_base()

func get_pending_fate_card() -> Dictionary:
	return data.pending_fate_card

func clear_pending_fate_card() -> void:
	pending_fate_card = {}
	data.pending_fate_card = {}
	save_base()

## — 蓝图系统 —
func get_blueprint_tier(category_id: String) -> int:
	_ensure_data()
	match category_id:
		"gunbody": return data.blueprint_gunbody_tier
		"bullet": return data.blueprint_bullet_tier
		"attachment": return data.blueprint_attachment_tier
	return 0

func set_blueprint_tier(category_id: String, tier: int) -> void:
	_ensure_data()
	match category_id:
		"gunbody": data.blueprint_gunbody_tier = tier
		"bullet": data.blueprint_bullet_tier = tier
		"attachment": data.blueprint_attachment_tier = tier
	save_base()

## — 资源点数系统 —
func get_extraction_points() -> int:
	return data.extraction_points

func add_extraction_points(amount: int) -> void:
	data.extraction_points += amount
	save_base()

func spend_extraction_points(amount: int) -> bool:
	if data.extraction_points < amount:
		return false
	data.extraction_points -= amount
	save_base()
	return true

## — 保险柜物品持久化 —
func get_vault_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in data.vault_items:
		if item is Dictionary:
			result.append(item)
	return result

func set_vault_items(items: Array[Dictionary]) -> void:
	data.vault_items = items
	save_base()

func add_vault_item(item: Dictionary) -> bool:
	if data.vault_items.size() >= _get_vault_capacity():
		return false
	data.vault_items.append(item.duplicate())
	save_base()
	return true

func remove_vault_item(index: int) -> bool:
	if index < 0 or index >= data.vault_items.size():
		return false
	data.vault_items.remove_at(index)
	save_base()
	return true

func _get_vault_capacity() -> int:
	# 保险柜容量 = 默认2格 + vault_level增加
	return 2 + data.vault_level

func get_vault_capacity() -> int:
	return _get_vault_capacity()

func get_vault_free_slots() -> int:
	return max(0, _get_vault_capacity() - data.vault_items.size())

func get_pending_loadout_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in data.pending_loadout_items:
		if item is Dictionary:
			result.append(item.duplicate(true))
	return result

func stage_vault_item_for_loadout(vault_index: int) -> bool:
	if vault_index < 0 or vault_index >= data.vault_items.size():
		return false
	var item: Dictionary = data.vault_items[vault_index]
	if item.is_empty():
		return false
	data.pending_loadout_items.append(item.duplicate(true))
	save_base()
	return true

func remove_pending_loadout_item(loadout_index: int) -> bool:
	if loadout_index < 0 or loadout_index >= data.pending_loadout_items.size():
		return false
	data.pending_loadout_items.remove_at(loadout_index)
	save_base()
	return true

func clear_pending_loadout() -> void:
	data.pending_loadout_items.clear()
	save_base()

func consume_pending_loadout() -> Array[Dictionary]:
	var consumed: Array[Dictionary] = []
	for staged in data.pending_loadout_items:
		if not (staged is Dictionary):
			continue
		var vault_index := _find_matching_vault_item(staged)
		if vault_index < 0:
			continue
		var item: Dictionary = data.vault_items[vault_index]
		consumed.append(item.duplicate(true))
		data.vault_items.remove_at(vault_index)
	data.pending_loadout_items.clear()
	save_base()
	return consumed

func _find_matching_vault_item(target: Dictionary) -> int:
	var target_id: String = target.get("id", "")
	for i in data.vault_items.size():
		var item: Dictionary = data.vault_items[i]
		if target_id != "" and item.get("id", "") == target_id:
			return i
		if item == target:
			return i
	return -1

## — 撤离战利品管理（返回大厅后待存入仓库）—
func get_extraction_loot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in data.extraction_loot:
		if item is Dictionary:
			result.append(item.duplicate(true))
	return result

func add_extraction_loot(item: Dictionary, count: int = 1) -> void:
	var new_item: Dictionary = item.duplicate(true)
	new_item["count"] = count
	data.extraction_loot.append(new_item)
	save_base()

func add_extraction_loot_items(items: Array[Dictionary]) -> void:
	for item in items:
		if item is Dictionary:
			add_extraction_loot(item, item.get("count", 1))
	save_base()

func get_extraction_loot_count() -> int:
	return data.extraction_loot.size()

func deposit_extraction_loot_item(index: int) -> bool:
	if index < 0 or index >= data.extraction_loot.size():
		return false
	var item: Dictionary = data.extraction_loot[index]
	if item.is_empty():
		data.extraction_loot.remove_at(index)
		save_base()
		return false
	if add_vault_item(item):
		data.extraction_loot.remove_at(index)
		save_base()
		return true
	return false

func deposit_all_extraction_loot() -> int:
	var deposited := 0
	# 逐个存入，溢出处理
	var overflow_count := 0
	for item in data.extraction_loot:
		if item is Dictionary and not item.is_empty():
			if add_vault_item(item):
				deposited += 1
			else:
				overflow_count += 1
	# 溢出转换为资源点数
	if overflow_count > 0:
		add_extraction_points(overflow_count * 5)
	data.extraction_loot.clear()
	save_base()
	return deposited

func discard_extraction_loot_item(index: int) -> void:
	if index < 0 or index >= data.extraction_loot.size():
		return
	data.extraction_loot.remove_at(index)
	save_base()

func clear_extraction_loot() -> void:
	data.extraction_loot.clear()
	save_base()
