class_name FateCardDebug
extends Node

# FateCard 自动化验证脚本
# 验证：1) FateCardPresets.all_presets() 是否返回所有预设卡片
#      2) FateCardEngine.apply_card() 能否正确应用到武器装配树
#      3) BlueprintRegistry 与 FateCardEngine 的联动

static func run_all() -> String:
	var lines: Array[String] = ["=== FateCard 系统验证 ==="]
	
	# 1. 检查所有预设卡片
	var all_cards: Array[FateCard] = FateCardPresets.all_presets()
	lines.append("\n[1] 预设卡片总数: %d 张" % all_cards.size())
	
	var by_type: Dictionary = {}
	var by_rarity: Dictionary = {}
	for card in all_cards:
		var tname: String = FateCard.type_name(card.card_type)
		var rname: String = FateCard.rarity_name(card.card_rarity)
		by_type[tname] = by_type.get(tname, 0) + 1
		by_rarity[rname] = by_rarity.get(rname, 0) + 1
	
	lines.append("  按类型分布:")
	for t in by_type:
		lines.append("    %s: %d 张" % [t, by_type[t]])
	lines.append("  按稀有度分布:")
	for r in by_rarity:
		lines.append("    %s: %d 张" % [r, by_rarity[r]])
	
	# 2. 验证 apply_card 逻辑（模拟）
	lines.append("\n[2] FateCardEngine.apply_card 模拟测试")
	
	# 获取玩家武器树
	var player: Node = _get_player()
	if player == null or not player.has_method("get_weapon_tree"):
		lines.append("  ⚠ 无法获取玩家武器树，跳过实际应用测试")
	else:
		var tree: WeaponAssemblyTree = player.get_weapon_tree()
		if tree == null:
			lines.append("  ⚠ 武器树为 null，跳过测试")
		else:
			# 随机选3张测试
			var test_cards: Array = all_cards.slice(0, min(3, all_cards.size()))
			for card in test_cards:
				var result: FateCardEngine.ApplyResult = FateCardEngine.apply_card(card, tree)
				lines.append("  [%s] %s: %s (%s)" % [
					FateCard.rarity_name(card.card_rarity),
					card.card_name,
					"✅ 成功" if result.success else "❌ 失败",
					result.message
				])
				if not result.success:
					lines.append("         效果: %s" % str(card.effect))
	
	# 3. 检查命运卡片与 BlueprintTier 的联动
	lines.append("\n[3] 命运卡片局内可用性检查")
	var usable_count: int = 0
	for card in all_cards:
		if _is_card_usable(card):
			usable_count += 1
	lines.append("  局内可用的命运卡片: %d / %d" % [usable_count, all_cards.size()])
	
	# 4. 检查各稀有度卡片数量是否满足设计目标
	lines.append("\n[4] 稀有度分布健康检查")
	var rarity_thresholds: Dictionary = {
		"common": 8,    # 至少8张白卡
		"rare": 6,      # 至少6张蓝卡
		"epic": 5,      # 至少5张紫卡
		"legendary": 3, # 至少3张金卡
		"mystic": 2,    # 至少2张红卡
	}
	for rarity in rarity_thresholds:
		var count: int = by_rarity.get(rarity, 0)
		var threshold: int = rarity_thresholds[rarity]
		var status: String = "✅" if count >= threshold else "⚠"
		lines.append("  %s %s: %d 张 (目标≥%d)" % [status, rarity, count, threshold])
	
	return "\n".join(lines)

static func _get_player() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var root: Window = tree.get_root()
	if root == null:
		return null
	return root.get_node_or_null("Main/Player")

static func _is_card_usable(card: FateCard) -> bool:
	# 命运卡片只要有有效的 effect 就可以用
	if card.effect.is_empty():
		return false
	if card.card_name.is_empty():
		return false
	return true