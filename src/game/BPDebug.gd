class_name BPDebug
extends Node

# BlueprintTier + LootModule 联动验证脚本
# 用于验证：
# 1. BlueprintRegistry.get_available_*() 是否随 Tier 正确扩大
# 2. LootModule 对 spawn_starter 掉落表的 BlueprintTier 过滤是否正确
# 3. ContainerInteraction 的 spawn_starter 掉落是否被 BlueprintTier 影响

static func run_all() -> String:
	var lines: Array[String] = ["=== BlueprintTier + LootModule 联动验证 ==="]
	
	# 1. BlueprintRegistry Tier 验证
	lines.append("\n[1] BlueprintRegistry 各 Tier 可用选项")
	for cat in ["gunbody", "bullet", "attachment"]:
		for tier in range(4):
			var items: Array[Dictionary] = []
			match cat:
				"gunbody": items = BlueprintRegistry.get_available_gunbodies(tier)
				"bullet": items = BlueprintRegistry.get_available_bullets(tier)
				"attachment": items = BlueprintRegistry.get_available_attachments(tier)
			lines.append("  Tier%d %s: %d 个 → %s" % [
				tier, cat,
				items.size(),
				", ".join(items.map(func(i): return i["display_name"]))
			])

	# 2. LootModule spawn_starter 掉落表 BlueprintTier 过滤验证
	lines.append("\n[2] LootModule spawn_starter 掉落 BlueprintTier 过滤")
	var loot := LootModule.get_instance()
	for tier in range(4):
		# 直接读取掉落表并手动过滤
		var all_items: Array[Dictionary] = ItemRegistry.get_instance().get_loot_table("spawn_starter")
		# 模拟 BlueprintTier 过滤
		var filtered: Array[Dictionary] = _filter_by_tier_simulate(all_items, tier, tier, tier)
		lines.append("  BlueprintTier %d → 可掉落 %d 种物品" % [tier, filtered.size()])
		for item in filtered:
			lines.append("    + %s [%s]" % [item.get("name", "?"), item.get("subtype", "?")])

	# 3. LootModule.generate_loot 验证
	lines.append("\n[3] LootModule.generate_loot('spawn_starter') 抽样")
	for _i in range(3):
		var samples: Array[Dictionary] = loot.generate_loot("spawn_starter", 3)
		for s in samples:
			lines.append("  → %s x%d" % [s.get("name", s.get("id", "?")), s.get("count", 1)])

	# 4. Container generate_container_loot 出生房箱子
	lines.append("\n[4] Container 出生房掉落模拟")
	var container_loot: Array[Dictionary] = loot.generate_container_loot("chest", 1)
	for item in container_loot:
		lines.append("  宝箱掉落: %s [%s]" % [item.get("name", "?"), item.get("type", "?")])

	return "\n".join(lines)

## 模拟 BlueprintTier 过滤（复制 LootModule._filter_by_blueprint_tier 逻辑）
static func _filter_by_tier_simulate(candidates: Array[Dictionary], gunbody_tier: int, bullet_tier: int, attach_tier: int) -> Array[Dictionary]:
	var usable: Array[Dictionary] = []
	for item in candidates:
		var item_tier: int = item.get("loot_table_tier", 0)
		var blueprint_loot_tier: int = item.get("blueprint_loot_tier", -1)
		var subtype: String = item.get("subtype", "")
		var item_type: String = item.get("type", "")
		var max_tier: int = 0
		match subtype:
			"gun_body": max_tier = gunbody_tier
			"bullet": max_tier = bullet_tier
			"muzzle", "stock", "scope", "magazine", "external", "mutator": max_tier = attach_tier
			_: max_tier = 99
		var effective_tier: int = item_tier
		if item_type == "blueprint" and blueprint_loot_tier >= 0:
			effective_tier = blueprint_loot_tier
		if effective_tier <= max_tier:
			usable.append(item)
	return usable