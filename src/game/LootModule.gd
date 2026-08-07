class_name LootModule
extends RefCounted
## 掉落模块 — 管理物品掉落生成
## 使用 ItemRegistry 提供可配置的掉落表
## 负责：掉落生成、商人供货、宝箱内容

## 单例引用
static var _instance: LootModule = null


static func get_instance() -> LootModule:
	if _instance == null:
		_instance = LootModule.new()
	return _instance


var _item_registry: ItemRegistry
var _rng: RandomNumberGenerator


func _init() -> void:
	_item_registry = ItemRegistry.get_instance()
	_rng = RandomNumberGenerator.new()
	_rng.seed = Time.get_ticks_msec()


## 设置随机种子（用于 deterministic 掉落）
func set_seed(seed: int) -> void:
	_rng.seed = seed


## 从掉落表生成掉落物品列表
## table_name: 掉落表名称，如 "loot_floor_1_2", "scavenge_floor_3" 等
## count: 最大掉落数量（实际数量受权重和随机影响）
## returns: Array[Dictionary] 物品数据列表（可直接 add_item 到 InventoryModule）
func generate_loot(table_name: String, count: int = 3) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = _item_registry.get_loot_table(table_name)
	if candidates.is_empty() and table_name.begins_with("combat_floor_"):
		candidates = _item_registry.get_loot_table("loot_floor_1_2")
	if candidates.is_empty() and table_name.begins_with("elite_floor_"):
		candidates = _item_registry.get_loot_table("loot_floor_1_2")
	if candidates.is_empty() and table_name.begins_with("scavenge_floor_"):
		candidates = _item_registry.get_loot_table("loot_floor_1_2")
	if table_name.begins_with("combat_floor_") or table_name.begins_with("elite_floor_"):
		candidates = _merge_loot_candidates(
			candidates, _item_registry.get_loot_table("loot_floor_1_2")
		)
	if candidates.is_empty():
		return []

	# 按权重排序并选择
	candidates.sort_custom(func(a, b): return a.get("loot_weight", 0) > b.get("loot_weight", 0))

	# 过滤：根据蓝图Tier排除不可用的物品
	var usable: Array[Dictionary] = _filter_by_blueprint_tier(candidates)

	var result: Array[Dictionary] = []
	var attempts: int = count * 3  # 防止运气太差选不到

	for i in range(attempts):
		if result.size() >= count:
			break
		var selected: Dictionary = _weighted_random_select(usable)
		if not selected.is_empty():
			# 复制物品数据，生成实际数量
			var entry: Dictionary = selected.duplicate(true)
			entry.erase("loot_weight")
			entry = WeaponInstance.ensure_weapon_item(entry)
			# 地面掉落以单件为最小单位；堆叠只发生在拾取进入背包之后。
			entry["count"] = 1
			result.append(entry)

	return result


## 根据蓝图Tier过滤物品（蓝图Tier决定可掉落的高级物品）
func _filter_by_blueprint_tier(candidates: Array[Dictionary]) -> Array[Dictionary]:
	var usable: Array[Dictionary] = []
	var gunbody_tier: int = 0
	var bullet_tier: int = 0
	var attach_tier: int = 0
	if BaseManager != null:
		gunbody_tier = BaseManager.get_blueprint_tier("gunbody")
		bullet_tier = BaseManager.get_blueprint_tier("bullet")
		attach_tier = BaseManager.get_blueprint_tier("attachment")

	for item in candidates:
		var item_tier: int = item.get("loot_table_tier", 0)
		var blueprint_loot_tier: int = item.get("blueprint_loot_tier", -1)  # -1 means not a blueprint
		var subtype: String = item.get("subtype", "")
		var item_type: String = item.get("type", "")
		var max_tier: int = 0
		match subtype:
			"gun_body":
				max_tier = gunbody_tier
			"bullet":
				max_tier = bullet_tier
			"muzzle", "stock", "scope", "magazine", "external", "mutator":
				max_tier = attach_tier
			_:
				# 消耗品/信标/其他不受限
				max_tier = 99
		# 蓝图类物品：用 blueprint_loot_tier 与 BlueprintTier 对比
		# 非蓝图类物品：用 loot_table_tier 与 BlueprintTier 对比
		var effective_tier: int = item_tier
		if item_type == "blueprint" and blueprint_loot_tier >= 0:
			effective_tier = blueprint_loot_tier
		if effective_tier <= max_tier:
			usable.append(item)

	return usable


## 加权随机选择
func _weighted_random_select(candidates: Array[Dictionary]) -> Dictionary:
	if candidates.is_empty():
		return {}

	var total_weight: float = 0.0
	for c in candidates:
		total_weight += c.get("loot_weight", 1.0)

	var roll: float = _rng.randf() * total_weight
	var cumulative: float = 0.0

	for c in candidates:
		cumulative += c.get("loot_weight", 1.0)
		if roll <= cumulative:
			return c

	return candidates[-1]  # fallback


## 生成商人供货列表
## tier: 商人层级（影响可选商品范围）
## count: 商品数量
func generate_merchant_goods(tier: int, count: int = 6) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = _item_registry.get_merchant_goods(tier)
	if candidates.is_empty():
		return []

	# 过滤：按蓝图Tier
	candidates = _filter_by_blueprint_tier(candidates)

	candidates.shuffle()
	var result: Array[Dictionary] = []
	for i in range(min(count, candidates.size())):
		var item: Dictionary = candidates[i].duplicate(true)
		item.erase("merchant_tier")
		item = WeaponInstance.ensure_weapon_item(item)
		# 商人价格可能有溢价/折扣
		var base_price: int = item.get("price", 10)
		item["price"] = int(base_price * (0.9 + _rng.randf() * 0.2))  # ±10%
		result.append(item)

	return result


## 生成搜刮房容器内容
## container_type: "crate", "locker", "hidden_cache"
## floor: 当前楼层
func generate_container_loot(container_type: String, floor: int) -> Array[Dictionary]:
	var table_name: String = "scavenge_floor_%d" % [min(5, floor)]
	var loot := generate_loot(table_name, 1)
	if floor <= 1 and not _contains_item(loot, "item_room_key"):
		var key := _item_registry.get_item("item_room_key")
		if loot.is_empty() and not key.is_empty() and _rng.randf() < 0.45:
			key["count"] = 1
			loot.append(key)
	return loot


## 生成怪物掉落
## enemy_data: 怪物配置数据（来自 MonsterInjector）
## returns: Array[Dictionary] 死亡点可生成的概率物品列表；货币由 RoomGameMode 必定生成魂球
func generate_enemy_loot(enemy_data: Dictionary) -> Array[Dictionary]:
	var floor: int = enemy_data.get("floor", 1)
	var loot_table: String = enemy_data.get(
		"loot_table", "loot_floor_1_2" if floor <= 2 else "loot_common"
	)
	var is_boss: bool = enemy_data.get("is_boss", false)
	var is_elite: bool = enemy_data.get("is_elite", false)

	# 普通怪以魂币为主，物品是低概率惊喜；精英/Boss 才稳定提供构筑收益。
	var count: int = 1 if _rng.randf() < 0.26 else 0
	if is_elite or is_boss:
		count = 1

	var loot: Array[Dictionary] = generate_loot(loot_table, count)
	if loot.is_empty() and floor <= 1 and not is_boss and _rng.randf() < (0.20 if is_elite else 0.08):
		var key := _item_registry.get_item("item_room_key")
		if not key.is_empty():
			key["count"] = 1
			loot.append(key)

	# Boss/精英附加魂也只返回为掉落数据；玩法层必须把它合并到地面魂球，
	# 禁止在击杀回调内直接调用 GameManager.add_currency()。
	var currency_bonus: int = 0
	if is_boss:
		currency_bonus = 200 + floor * 20
	elif is_elite:
		currency_bonus = 50 + floor * 20
	# 将货币奖励附加到 loot 结果最后一项（如果有的话），或新增一个 currency 条目
	if currency_bonus > 0:
		var currency_entry: Dictionary = {
			"id": "__currency__",  # 特殊 ID 表示货币
			"name": "魂",
			"type": "currency",
			"count": currency_bonus,
			"is_currency": true
		}
		loot.append(currency_entry)

	return loot


func _contains_item(loot: Array[Dictionary], item_id: String) -> bool:
	for item in loot:
		if item.get("id", "") == item_id:
			return true
	return false


func _merge_loot_candidates(
	primary: Array[Dictionary], fallback: Array[Dictionary]
) -> Array[Dictionary]:
	var merged: Array[Dictionary] = []
	var seen: Dictionary = {}
	for item in primary:
		var item_id := str(item.get("id", ""))
		if item_id.is_empty() or seen.has(item_id):
			continue
		seen[item_id] = true
		merged.append(item)
	for item in fallback:
		var item_id := str(item.get("id", ""))
		if item_id.is_empty() or seen.has(item_id):
			continue
		seen[item_id] = true
		merged.append(item)
	return merged


## 将掉落物品添加到背包
## returns: 实际添加成功的物品数量
func grant_loot_to_inventory(loot: Array[Dictionary], inventory: InventoryModule) -> int:
	if inventory == null or loot.is_empty():
		return 0

	var granted: int = 0
	for item_data in loot:
		var item_id: String = item_data.get("id", "")
		var count: int = item_data.get("count", 1)
		if item_id.is_empty():
			continue
		var added: int = inventory.add_item(item_data, count)
		if added > 0:
			granted += 1
			# 特别处理：信标道具同步到 ExtractionDirector
			if item_id == "item_beacon":
				_sync_beacon_to_extraction_director(inventory)
	return granted


## 同步信标数量到 ExtractionDirector
## 在 RoomGameMode 地图生成时和每次获得物品后调用
func _sync_beacon_to_extraction_director(inventory: InventoryModule) -> void:
	# 这个逻辑应该在 RoomGameMode 层面处理
	# 这里只提供辅助方法
	pass


## 获取物品注册表引用（用于查询）
func get_item_registry() -> ItemRegistry:
	return _item_registry


## 调试：测试掉落
func debug_test_loot(table_name: String, count: int = 5) -> String:
	var loot: Array[Dictionary] = generate_loot(table_name, count)
	var lines: Array[String] = ["LootModule.generate_loot(%s, %d)" % [table_name, count]]
	for item in loot:
		lines.append("  + %s x%d" % [item.get("name", item.get("id", "?")), item.get("count", 1)])
	return "\n".join(lines)
