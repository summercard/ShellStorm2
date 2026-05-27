extends Node
class_name FateCardEngine

# FateCardEngine.gd — 命运卡片效果执行器
# 负责将 FateCard 的效果应用到 WeaponAssemblyTree / AssemblyNode
# 是 FateCard 系统与武器装配系统的桥梁

## 信号
signal card_applied(card: FateCard, targets: Array[AssemblyNode], success: bool)
signal card_removed(card_id: String)

## 错误类型
enum ApplyError {
	OK = 0,
	NO_TARGET = 1,
	TARGET_INVALID = 2,
	SLOT_OCCUPIED = 3,
	DEPTH_EXCEEDED = 4,
	CIRCULAR_REF = 5,
	APPLY_FAILED = 6,
}


## 执行结果
class ApplyResult:
	var success: bool = false
	var error: ApplyError = ApplyError.OK
	var message: String = ""
	var modified_nodes: Array[AssemblyNode] = []
	var effect_value: Variant = null


## 应用一张命运卡片到玩家武器装配树（静态方法，供外部 UI 调用）
## 自动从场景树查找玩家的 WeaponAssemblyTree 并应用卡片
static func apply_card_to_player(card: FateCard) -> ApplyResult:
	var player: Node = _find_player()
	if player == null or not player.has_method("get_weapon_tree"):
		var result: ApplyResult = ApplyResult.new()
		result.success = false
		result.error = ApplyError.TARGET_INVALID
		result.message = "Player node not found in scene tree"
		return result

	var weapon_tree: WeaponAssemblyTree = player.get_weapon_tree()
	if weapon_tree == null:
		var result: ApplyResult = ApplyResult.new()
		result.success = false
		result.error = ApplyError.TARGET_INVALID
		result.message = "Player weapon tree not initialized"
		return result

	return apply_card(card, weapon_tree)


## 应用一张卡片到装配树
## 返回 ApplyResult
static func apply_card(
	card: FateCard, tree: WeaponAssemblyTree, target_nodes: Array[AssemblyNode] = []
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()

	if card == null or tree == null:
		result.error = ApplyError.TARGET_INVALID
		result.message = "card or tree is null"
		return result

	if target_nodes.is_empty():
		# 尝试自动选择目标
		target_nodes = _auto_select_targets(card, tree)

	if target_nodes.is_empty():
		result.error = ApplyError.NO_TARGET
		result.message = "No valid target found for card: %s" % card.card_name
		return result

	# 根据 EffectAction 执行
	var action: int = int(card.effect.get("action", -1))
	match action:
		-1:
			result.error = ApplyError.APPLY_FAILED
			result.message = "Card has no effect action defined"
			return result

		FateCard.EffectAction.ATTACH_GUN_TO_BULLET:
			result = _apply_attach_gun_to_bullet(card, tree, target_nodes)
		FateCard.EffectAction.ATTACH_TO_MOUNT:
			result = _apply_attach_to_mount(card, tree, target_nodes)
		FateCard.EffectAction.ATTACH_GUN_TO_GUN:
			result = _apply_attach_gun_to_gun(card, tree, target_nodes)
		FateCard.EffectAction.SCALE_NODE:
			result = _apply_scale_node(card, tree, target_nodes)
		FateCard.EffectAction.SCALE_UP:
			result = _apply_scale_up(card, tree, target_nodes)
		FateCard.EffectAction.ADD_EYES:
			result = _apply_add_eyes(card, tree, target_nodes)
		FateCard.EffectAction.ADD_LEGS:
			result = _apply_add_legs(card, tree, target_nodes)
		FateCard.EffectAction.MULTIPLY_FIRE_RATE:
			result = _apply_multiply_fire_rate(card, tree, target_nodes)
		FateCard.EffectAction.ADD_DAMAGE:
			result = _apply_add_damage(card, tree, target_nodes)
		FateCard.EffectAction.MUTATE_TO_HOMING:
			result = _apply_mutate_to_homing(card, tree, target_nodes)
		FateCard.EffectAction.MUTATE_TO_LIVING:
			result = _apply_mutate_to_living(card, tree, target_nodes)
		FateCard.EffectAction.EVERY_NTH_FIRE:
			result = _apply_every_nth_fire(card, tree, target_nodes)
		FateCard.EffectAction.CRIT_ON_KILL:
			result = _apply_crit_on_kill(card, tree, target_nodes)
		FateCard.EffectAction.REINFORCE_WAVE:
			result = _apply_reinforce_wave(card, tree, target_nodes)
		FateCard.EffectAction.GRANT_RANDOM_CARD:
			result = _apply_grant_random_card(card, tree, target_nodes)
		FateCard.EffectAction.LUCKY_CHEST:
			result = _apply_lucky_chest(card, tree, target_nodes)
		FateCard.EffectAction.EXTRA_LOOT:
			result = _apply_extra_loot(card, tree, target_nodes)
		FateCard.EffectAction.CURSE_ROOM_ENEMIES:
			result = _apply_curse_room_enemies(card, tree, target_nodes)
		FateCard.EffectAction.OUT_OF_CONTROL:
			result = _apply_out_of_control(card, tree, target_nodes)
		FateCard.EffectAction.SIZE_GROWTH:
			result = _apply_size_growth(card, tree, target_nodes)
		FateCard.EffectAction.BLESS_DEAD:
			result = _apply_bless_dead(card, tree, target_nodes)
		_:
			result.error = ApplyError.APPLY_FAILED
			result.message = "Unsupported effect action: %d" % action
			return result

	return result


## 自动选择目标节点（基于 card.target_rules）
static func _auto_select_targets(card: FateCard, tree: WeaponAssemblyTree) -> Array[AssemblyNode]:
	var root: AssemblyNode = tree.get_root()
	if root == null:
		return []

	var candidates: Array[AssemblyNode] = []

	if card.target_rules.is_empty():
		# 无规则时默认选根节点
		candidates.append(root)
	else:
		for rule in card.target_rules:
			var select: String = str(rule.get("select", ""))
			var required_tags: Array[String] = []
			for tag in rule.get("requiredTags", []):
				required_tags.append(str(tag))
			var matched: Array[AssemblyNode] = _find_nodes_by_selector(root, select, required_tags)
			for node in matched:
				if not candidates.has(node):
					candidates.append(node)

	return candidates


## 根据选择器查找节点
static func _find_nodes_by_selector(
	root: AssemblyNode, select: String, required_tags: Array[String]
) -> Array[AssemblyNode]:
	var results: Array[AssemblyNode] = []
	var descendants: Array[AssemblyNode] = root.get_all_descendants()
	descendants.append(root)  # 包含根节点

	var node_type_filter := -1
	match select.to_upper():
		"BULLET":
			node_type_filter = AssemblyNode.NodeType.BULLET
		"GUNBODY", "GUN_BODY":
			node_type_filter = AssemblyNode.NodeType.GUN_BODY
		"ATTACHMENT":
			node_type_filter = AssemblyNode.NodeType.ATTACHMENT

	for node in descendants:
		if node_type_filter >= 0 and node.node_type != node_type_filter:
			continue
		if required_tags.is_empty() or _node_has_all_tags(node, required_tags):
			results.append(node)

	return results


static func _node_has_all_tags(node: AssemblyNode, tags: Array[String]) -> bool:
	for tag in tags:
		if not node.tags.has(tag):
			return false
	return true


## ===== 效果执行：ATTACH_GUN_TO_BULLET =====
## 子弹上挂枪身，子弹飞行时会携带枪并自动射击
static func _apply_attach_gun_to_bullet(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	var root: AssemblyNode = tree.get_root()
	var modified: Array[AssemblyNode] = []

	# 找第一个子弹节点作为子弹
	var bullet_node: AssemblyNode = null
	for t in targets:
		if t.node_type == AssemblyNode.NodeType.BULLET:
			bullet_node = t
			break

	if bullet_node == null:
		# 自动找一个子弹
		var descendants: Array[AssemblyNode] = root.get_all_descendants()
		for d in descendants:
			if d.node_type == AssemblyNode.NodeType.BULLET:
				bullet_node = d
				break

	if bullet_node == null:
		result.error = ApplyError.NO_TARGET
		result.message = "No bullet node found to attach gun"
		return result

	# 创建新枪身节点
	var attached_gun: AssemblyNode = AssemblyNode.new(
		AssemblyNode.NodeType.GUN_BODY, "AttachedGun_" + card.card_id
	)
	var damage_scale: float = card.effect.get("damage_scale", 0.5)
	var fire_rate_scale: float = card.effect.get("fire_rate_scale", 0.6)
	(
		attached_gun
		. set_base_stats(
			{
				"damage": int(10 * damage_scale),
				"fire_rate": 4.0 * fire_rate_scale,
				"bullet_count": 1,
			}
		)
	)
	attached_gun.tags = ["Fate.AttachedGun", card.card_id]

	# 挂载到子弹的 MOUNT 槽
	if bullet_node.slots[AssemblyNode.SlotType.MOUNT] != null:
		result.error = ApplyError.SLOT_OCCUPIED
		result.message = "Bullet mount slot already occupied"
		return result

	var ok: bool = tree.mount(bullet_node, AssemblyNode.SlotType.MOUNT, attached_gun)
	if not ok:
		result.error = ApplyError.APPLY_FAILED
		result.message = "Failed to mount gun to bullet"
		return result

	modified.append(bullet_node)
	modified.append(attached_gun)
	result.success = true
	_fate_audio_card_applied()
	result.modified_nodes = modified
	result.effect_value = attached_gun
	result.message = "Attached gun to bullet: %s" % bullet_node.node_id
	return result


## ===== 效果执行：ATTACH_TO_MOUNT =====
## 挂载任意节点到目标槽位
static func _apply_attach_to_mount(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()

	if targets.is_empty():
		result.error = ApplyError.NO_TARGET
		return result

	var target: AssemblyNode = targets[0]
	var slot_type: AssemblyNode.SlotType = AssemblyNode.SlotType.MOUNT
	if card.effect.has("target_slot"):
		var slot_name: String = card.effect.get("target_slot", "MOUNT")
		slot_type = AssemblyNode.SlotType.get(slot_name)

	# 如果是挂载类组合卡，自动创建一个配件节点。
	var action: int = int(card.effect.get("action", -1))
	var child_node: AssemblyNode = null

	if card.card_type == FateCard.CardType.COMBINE:
		# 组合类：创建一个匹配的子节点
		if action == FateCard.EffectAction.ATTACH_TO_MOUNT:
			# 默认创建附件节点
			child_node = AssemblyNode.new(
				AssemblyNode.NodeType.ATTACHMENT, "FateAttachment_" + card.card_id
			)
		child_node.tags = card.tags.duplicate()
		# 配件寄生默认效果：命中触发。命中时 Bullet 会派发 attachment_hit_triggered 信号，
		# 其效果（分裂/强化等）由 Bullet 根据挂载的配件节点 stats 具体决定
		var default_stats := {"damage": 0, "fire_rate": 0, "fate_attachment_hit_trigger": true, "trigger_on_hit": true}
		child_node.set_base_stats(default_stats)

	if child_node == null:
		result.error = ApplyError.APPLY_FAILED
		result.message = "Could not create child node for combine card"
		return result

	# 配件寄生：标记命中触发效果，供 Bullet 运行时检测
	if card.card_name == "配件寄生" or card.effect.get("trigger_on_hit", false):
		var attach_stats: Dictionary = child_node.get_base_stats()
		attach_stats["fate_attachment_hit_trigger"] = true
		attach_stats["trigger_on_hit"] = true
		child_node.set_base_stats(attach_stats)
		child_node.tags.append("Fate.AttachmentHitTrigger")

	if target.slots[slot_type] != null:
		result.error = ApplyError.SLOT_OCCUPIED
		result.message = "Target slot %s already occupied" % AssemblyNode.SlotType.keys()[slot_type]
		return result

	var ok: bool = tree.mount(target, slot_type, child_node)
	if not ok:
		result.error = ApplyError.APPLY_FAILED
		result.message = "Failed to mount node"
		return result

	result.success = true
	_fate_audio_card_applied()
	result.modified_nodes = [target, child_node]
	result.effect_value = child_node
	result.message = (
		"Mounted %s to %s slot of %s"
		% [child_node.node_name, AssemblyNode.SlotType.keys()[slot_type], target.node_name]
	)
	return result


## ===== 效果执行：ATTACH_GUN_TO_GUN =====
## 枪上加枪：枪身挂枪身，主枪开火时副枪也跟随射击
## 实现：找到一个 GUN_BODY 节点作为主枪，在其 MOUNT 槽挂载一个副枪身
## 副枪的射击通过 WeaponAssemblyTree._fire_co_mounted_gun() 实现
static func _apply_attach_gun_to_gun(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	var root: AssemblyNode = tree.get_root()

	# 找主枪身节点（优先选 targets 中的 GUN_BODY，否则找根节点或第一个 GUN_BODY）
	var main_gun: AssemblyNode = null
	for t in targets:
		if t.node_type == AssemblyNode.NodeType.GUN_BODY:
			main_gun = t
			break

	if main_gun == null:
		# 自动找一个枪身
		if root != null and root.node_type == AssemblyNode.NodeType.GUN_BODY:
			main_gun = root
		else:
			var descendants: Array[AssemblyNode] = root.get_all_descendants()
			for d in descendants:
				if d.node_type == AssemblyNode.NodeType.GUN_BODY:
					main_gun = d
					break

	if main_gun == null:
		result.error = ApplyError.NO_TARGET
		result.message = "No GUN_BODY node found to attach secondary gun"
		return result

	# 检查主枪的 MOUNT 槽是否空闲
	if main_gun.slots[AssemblyNode.SlotType.MOUNT] != null:
		result.error = ApplyError.SLOT_OCCUPIED
		result.message = "Main gun mount slot already occupied"
		return result

	# 从 effect 参数获取缩放参数
	var damage_scale: float = card.effect.get("damage_scale", 0.5)
	var fire_rate_scale: float = card.effect.get("fire_rate_scale", 0.6)
	var follow_probability: float = card.effect.get("follow_probability", 1.0)  # 跟随射击概率

	# 创建副枪身节点
	var secondary_gun: AssemblyNode = AssemblyNode.new(
		AssemblyNode.NodeType.GUN_BODY, "SecondaryGun_" + card.card_id
	)
	(
		secondary_gun
		. set_base_stats(
			{
				"damage": int(10 * damage_scale),
				"fire_rate": 4.0 * fire_rate_scale,
				"bullet_count": 1,
			}
		)
	)
	secondary_gun.tags = ["Fate.SecondaryGun", card.card_id, "Fate.GunOnGun"]

	# 将副枪挂载到主枪的 MOUNT 槽
	var ok: bool = tree.mount(main_gun, AssemblyNode.SlotType.MOUNT, secondary_gun)
	if not ok:
		result.error = ApplyError.APPLY_FAILED
		result.message = "Failed to mount secondary gun"
		return result

	result.success = true
	_fate_audio_card_applied()
	result.modified_nodes = [main_gun, secondary_gun]
	result.effect_value = secondary_gun
	result.message = (
		"Attached secondary gun to %s (follow_prob=%.0f%%)"
		% [main_gun.node_name, follow_probability * 100]
	)
	return result


## ===== 效果执行：SCALE_NODE =====
## 缩放节点
static func _apply_scale_node(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	if targets.is_empty():
		result.error = ApplyError.NO_TARGET
		return result

	var target: AssemblyNode = targets[0]
	var scale: float = card.effect.get("scale", 1.5)
	var damage_bonus: int = card.effect.get("damage_bonus", 3)
	var speed_multiplier: float = card.effect.get("speed_multiplier", 1.0)

	# 在 base_stats 中记录缩放因子
	var stats: Dictionary = target.get_base_stats()
	stats["fate_scale"] = scale
	if target.node_type == AssemblyNode.NodeType.BULLET:
		stats["bullet_damage"] = stats.get("bullet_damage", 5) + damage_bonus
	else:
		stats["damage"] = stats.get("damage", 10) + damage_bonus
	stats["speed"] = stats.get("speed", 1.0) * speed_multiplier
	target.set_base_stats(stats)
	target.tags.append("Fate.Scaled")
	tree.refresh_stats()

	result.success = true
	_fate_audio_card_applied()
	result.modified_nodes = [target]
	result.effect_value = scale
	result.message = "Scaled node %s by %.1fx" % [target.node_name, scale]
	return result


## ===== 效果执行：MULTIPLY_FIRE_RATE =====
## 射速倍率
static func _apply_multiply_fire_rate(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	if targets.is_empty():
		result.error = ApplyError.NO_TARGET
		return result

	var target: AssemblyNode = targets[0]
	var multiplier: float = card.effect.get("multiplier", 1.5)
	var overheat_penalty: float = card.effect.get("overheat_penalty", 1.0)
	var stats: Dictionary = target.get_base_stats()
	stats["fire_rate_multiplier"] = multiplier
	stats["fire_rate"] = stats.get("fire_rate", 4.0) * multiplier
	stats["overheat_penalty"] = overheat_penalty
	target.tags.append("Fate.Overclocked")
	target.set_base_stats(stats)
	tree.refresh_stats()

	result.success = true
	_fate_audio_card_applied()
	result.modified_nodes = [target]
	result.effect_value = multiplier
	result.message = "Applied %.1fx fire rate to %s" % [multiplier, target.node_name]
	return result


## ===== 效果执行：ADD_DAMAGE =====
## 增加伤害
static func _apply_add_damage(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	if targets.is_empty():
		result.error = ApplyError.NO_TARGET
		return result

	var target: AssemblyNode = targets[0]
	var damage_bonus: int = card.effect.get("damage_bonus", 5)
	var pierce_level: int = card.effect.get("pierce_level", 0)
	var stats: Dictionary = target.get_base_stats()
	if target.node_type == AssemblyNode.NodeType.BULLET:
		stats["bullet_damage"] = stats.get("bullet_damage", 5) + damage_bonus
	else:
		stats["damage"] = stats.get("damage", 10) + damage_bonus
	if pierce_level > 0:
		stats["pierce_level"] = pierce_level
	target.set_base_stats(stats)
	target.tags.append("Fate.ArmorPierced")
	tree.refresh_stats()

	result.success = true
	_fate_audio_card_applied()
	result.modified_nodes = [target]
	result.effect_value = damage_bonus
	result.message = "Added +%d damage to %s" % [damage_bonus, target.node_name]
	return result


## ===== 效果执行：MUTATE_TO_HOMING =====
## 子弹变追踪弹
static func _apply_mutate_to_homing(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	if targets.is_empty():
		result.error = ApplyError.NO_TARGET
		return result

	var target: AssemblyNode = targets[0]
	var homing_strength: float = card.effect.get("homing_strength", 0.3)
	var speed_penalty: float = card.effect.get("speed_penalty", 0.2)
	var return_to_player: bool = card.effect.get("return_to_player", false)

	var stats: Dictionary = target.get_base_stats()
	stats["homing"] = true
	stats["homing_strength"] = homing_strength
	stats["speed"] = stats.get("speed", 1.0) * (1.0 - speed_penalty)
	stats["return_to_player"] = return_to_player
	if return_to_player:
		stats["return_damage_multiplier"] = card.effect.get("return_damage_multiplier", 0.6)
	target.set_base_stats(stats)
	target.tags.append("Fate.Homing")
	if return_to_player:
		target.tags.append("Fate.ReturnBullet")
	tree.refresh_stats()

	# Apply visual enhancements from card.visual (e.g. AddEyes for "活过来")
	if card.visual.has("action"):
		var visual_action: String = str(card.visual.get("action", ""))
		if visual_action == "AddEyes":
			var eye_count: int = int(card.visual.get("eye_count", 2))
			var vstats: Dictionary = target.get_base_stats()
			vstats["visual_eyes"] = eye_count
			vstats["visual_has_eyes"] = true
			target.set_base_stats(vstats)
			target.tags.append("Fate.Visual.HasEyes")
			target.node_name += " 👁"
		elif visual_action == "AddLegs":
			var leg_count: int = int(card.visual.get("leg_count", 4))
			var vstats: Dictionary = target.get_base_stats()
			vstats["visual_legs"] = leg_count
			vstats["visual_has_legs"] = true
			target.set_base_stats(vstats)
			target.tags.append("Fate.Visual.HasLegs")
			target.node_name += " 🦵"

	result.success = true
	_fate_audio_card_applied()
	result.modified_nodes = [target]
	result.effect_value = homing_strength
	result.message = "Mutated %s to homing (strength=%.2f)" % [target.node_name, homing_strength]
	return result


## ===== 效果执行：MUTATE_TO_LIVING =====
## 子弹变活体（不想飞：落地生成炮台）
static func _apply_mutate_to_living(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	if targets.is_empty():
		result.error = ApplyError.NO_TARGET
		return result

	var target: AssemblyNode = targets[0]
	var spawn_turret: bool = card.effect.get("spawn_turret_on_land", true)
	var turret_duration: float = card.effect.get("turret_duration", 5.0)

	var stats: Dictionary = target.get_base_stats()
	stats["spawn_turret_on_land"] = spawn_turret
	stats["turret_duration"] = turret_duration
	target.set_base_stats(stats)
	target.tags.append("Fate.Turret")
	tree.refresh_stats()

	result.success = true
	_fate_audio_card_applied()
	result.modified_nodes = [target]
	result.effect_value = turret_duration
	result.message = "Set turret-on-land (duration=%.1fs) on %s" % [turret_duration, target.node_name]
	return result


## ===== 效果执行：EVERY_NTH_FIRE =====
## 每第N发触发特殊效果
static func _apply_every_nth_fire(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	if targets.is_empty():
		result.error = ApplyError.NO_TARGET
		return result

	var target: AssemblyNode = targets[0]
	var nth: int = card.effect.get("nth", 7)
	var attach_gun: bool = card.effect.get("attach_gun", true)

	var stats: Dictionary = target.get_base_stats()
	stats["every_nth_fire"] = nth
	stats["every_nth_attach_gun"] = attach_gun
	target.set_base_stats(stats)
	target.tags.append("Fate.EveryNthFire")
	tree.refresh_stats()

	result.success = true
	_fate_audio_card_applied()
	result.modified_nodes = [target]
	result.effect_value = nth
	result.message = "Set every %d-th fire trigger on %s" % [nth, target.node_name]
	return result


## ===== 效果执行：CRIT_ON_KILL =====
## 击杀必暴击
static func _apply_crit_on_kill(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	if targets.is_empty():
		result.error = ApplyError.NO_TARGET
		return result

	var target: AssemblyNode = targets[0]
	var crit_mult: float = card.effect.get("crit_damage_multiplier", 2.5)
	var stats: Dictionary = target.get_base_stats()
	stats["crit_on_kill"] = true
	stats["crit_damage_multiplier"] = crit_mult
	target.set_base_stats(stats)
	target.tags.append("Fate.CritOnKill")
	tree.refresh_stats()

	result.success = true
	_fate_audio_card_applied()
	result.modified_nodes = [target]
	result.effect_value = crit_mult
	result.message = "Set crit-on-kill (%.1fx) on %s" % [crit_mult, target.node_name]
	return result


## ===== 效果执行：SCALE_UP（视觉类）=====
static func _apply_scale_up(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	return _apply_scale_node(card, tree, targets)


## ===== 效果执行：ADD_EYES（视觉类）=====
static func _apply_add_eyes(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	if targets.is_empty():
		result.error = ApplyError.NO_TARGET
		return result

	var target: AssemblyNode = targets[0]
	var eye_count: int = card.effect.get("eye_count", 2)
	var stats: Dictionary = target.get_base_stats()
	stats["visual_eyes"] = eye_count
	stats["visual_has_eyes"] = true
	target.set_base_stats(stats)
	target.tags.append("Fate.Visual.HasEyes")
	tree.refresh_stats()

	result.success = true
	_fate_audio_card_applied()
	result.modified_nodes = [target]
	result.effect_value = eye_count
	result.message = "Added %d eyes visual to %s" % [eye_count, target.node_name]
	return result


## ===== 效果执行：ADD_LEGS（视觉类）=====
static func _apply_add_legs(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	if targets.is_empty():
		result.error = ApplyError.NO_TARGET
		return result

	var target: AssemblyNode = targets[0]
	var stats: Dictionary = target.get_base_stats()
	stats["visual_has_legs"] = true
	stats["visual_leg_count"] = card.effect.get("leg_count", 4)
	target.set_base_stats(stats)
	target.tags.append("Fate.Visual.HasLegs")
	tree.refresh_stats()

	result.success = true
	_fate_audio_card_applied()
	result.modified_nodes = [target]
	result.effect_value = true
	result.message = "Added legs visual to %s" % target.node_name
	return result


## ===== 效果执行：REINFORCE_WAVE（环境命运触发器）=====
## 触发波次外额外刷怪 — 无需目标节点，直接通知 RoomWaveSpawner
static func _apply_reinforce_wave(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	result.success = true
	_fate_audio_card_applied()
	result.message = "Reinforce wave triggered (no target node needed)"
	# 通知房间游戏模式触发额外刷怪
	var rgm: Node = _find_room_game_mode()
	if rgm != null and rgm.has_method("trigger_extra_wave"):
		rgm.trigger_extra_wave()
	return result


## ===== 效果执行：GRANT_RANDOM_CARD（环境命运触发器）=====
## 给予随机命运卡片 — 随机选一张可玩命卡，真正应用其效果（修改武器树）
static func _apply_grant_random_card(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	result.success = true
	_fate_audio_card_applied()
	result.message = "Grant random fate card triggered"
	# 随机选一张可玩命卡（不含 MAP_TRIGGER 类，避免递归触发环境触发器本身）
	var all_cards: Array[FateCard] = []
	var playable: Array[FateCard] = FateCardPresets.playable_presets()
	for c in playable:
		if c.card_type != FateCard.CardType.CURSE and not c.tags.has("Fate.MapTrigger"):
			all_cards.append(c)
	if all_cards.is_empty():
		result.message = "No available cards to grant"
		return result
	var random_card: FateCard = all_cards[randi() % all_cards.size()]
	# 真正执行卡片的 EffectAction（武器树修改），而非只记录到列表
	var bridge: Node = _find_fate_card_bridge()
	if bridge != null:
		var engine_script: GDScript = preload("res://src/weapons/FateCardEngine.gd") as GDScript
		var engine_class: Variant = engine_script
		var engine_result: Object = engine_class.apply_card(random_card, tree)
		result.success = engine_result.success
		result.message = "随机命卡：" + random_card.card_name + " — " + engine_result.message
		if result.success:
			if bridge.has_method("record_applied_card"):
				bridge.record_applied_card(random_card)
		else:
			push_warning("[FateCardEngine] 随机命卡应用失败: " + random_card.card_name)
	else:
		result.message = "随机命卡：" + random_card.card_name + "（桥接器未就绪，仅记录）"
	return result


## ===== 效果执行：LUCKY_CHEST（环境命运触发器）=====
## 下次开箱品质提升 — 通过 RoomGameMode 设置标记
static func _apply_lucky_chest(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	result.success = true
	_fate_audio_card_applied()
	result.effect_value = card.effect.get("quality_boost", 1)
	result.message = "Lucky chest quality boost: +%d" % [result.effect_value]
	var rgm: Node = _find_room_game_mode()
	if rgm != null and rgm.has_method("set_next_chest_quality_boost"):
		rgm.set_next_chest_quality_boost(int(result.effect_value))
	return result


## ===== 效果执行：EXTRA_LOOT（环境命运触发器）=====
## 下次开箱额外掉落
static func _apply_extra_loot(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	result.success = true
	_fate_audio_card_applied()
	result.message = "Extra loot triggered"
	var rgm: Node = _find_room_game_mode()
	if rgm != null and rgm.has_method("set_extra_loot_next_chest"):
		rgm.set_extra_loot_next_chest(true)
	return result


## ===== 效果执行：CURSE_ROOM_ENEMIES（环境命运触发器）=====
## 当前房间内所有敌人伤害提升
static func _apply_curse_room_enemies(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	var damage_mult: float = card.effect.get("damage_multiplier", 1.15)
	result.success = true
	_fate_audio_card_applied()
	result.effect_value = damage_mult
	result.message = "Curse room enemies: %.0f%% damage boost" % [(damage_mult - 1.0) * 100.0]
	var rgm: Node = _find_room_game_mode()
	if rgm != null and rgm.has_method("apply_curse_to_current_room"):
		rgm.apply_curse_to_current_room(damage_mult)
	return result


## ===== 效果执行：BLESS_DEAD（环境命运触发器）=====
## 低血量存活后获得伤害加成
static func _apply_bless_dead(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	result.success = true
	_fate_audio_card_applied()
	result.effect_value = {
		"hp_threshold": card.effect.get("hp_threshold", 0.3),
		"survive_timer": card.effect.get("survive_duration", 30.0),
		"damage_bonus": card.effect.get("damage_bonus", 0.1),
	}
	result.message = (
		"Bless dead: HP<%.0f%% survive %.0fs = +%.0f%% damage"
		% [
			result.effect_value.hp_threshold * 100.0,
			result.effect_value.survive_timer,
			result.effect_value.damage_bonus * 100.0,
		]
	)
	# 通过 RoomGameMode 设置祝福状态
	var rgm: Node = _find_room_game_mode()
	if rgm != null and rgm.has_method("apply_bless_dead"):
		rgm.apply_bless_dead(
			result.effect_value.hp_threshold,
			result.effect_value.survive_timer,
			result.effect_value.damage_bonus
		)
	return result


## ===== 效果执行：OUT_OF_CONTROL（管不住了）=====
## 子弹上的挂载枪随机乱射，不一定瞄准敌人
static func _apply_out_of_control(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	var root: AssemblyNode = tree.get_root()
	var bullet_node: AssemblyNode = null

	# 找子弹节点
	for t in targets:
		if t.node_type == AssemblyNode.NodeType.BULLET:
			bullet_node = t
			break
	if bullet_node == null:
		var descendants: Array[AssemblyNode] = root.get_all_descendants()
		for d in descendants:
			if d.node_type == AssemblyNode.NodeType.BULLET:
				bullet_node = d
				break
	if bullet_node == null:
		result.error = ApplyError.NO_TARGET
		result.message = "No bullet node found for OUT_OF_CONTROL"
		return result

	# 读取乱射参数
	var aim_randomness: float = card.effect.get("aim_randomness", 0.5)  # 0=精准，1=完全随机
	var damage_scale: float = card.effect.get("damage_scale", 0.8)

	# 将乱射标记写入子弹节点 stats
	var stats: Dictionary = bullet_node.get_base_stats()
	stats["uncontrolled_gun"] = true
	stats["aim_randomness"] = aim_randomness
	stats["uncontrolled_damage_scale"] = damage_scale
	bullet_node.set_base_stats(stats)
	bullet_node.tags.append("Fate.Uncontrolled")

	result.success = true
	_fate_audio_card_applied()
	result.modified_nodes = [bullet_node]
	result.effect_value = aim_randomness
	result.message = "Set uncontrolled gun (aim_randomness=%.0f%%, damage_scale=%.0f%%) on %s" % [
		aim_randomness * 100.0, damage_scale * 100.0, bullet_node.node_name
	]
	return result


## ===== 效果执行：SIZE_GROWTH（火力暴食）=====
## 子弹每命中一次就变大，但也会降低玩家移速
static func _apply_size_growth(
	card: FateCard, tree: WeaponAssemblyTree, targets: Array[AssemblyNode]
) -> ApplyResult:
	var result: ApplyResult = ApplyResult.new()
	var root: AssemblyNode = tree.get_root()
	var bullet_node: AssemblyNode = null

	for t in targets:
		if t.node_type == AssemblyNode.NodeType.BULLET:
			bullet_node = t
			break
	if bullet_node == null:
		var descendants: Array[AssemblyNode] = root.get_all_descendants()
		for d in descendants:
			if d.node_type == AssemblyNode.NodeType.BULLET:
				bullet_node = d
				break
	if bullet_node == null:
		result.error = ApplyError.NO_TARGET
		result.message = "No bullet node found for SIZE_GROWTH"
		return result

	var growth_per_hit: float = card.effect.get("growth_per_hit", 0.2)
	var max_scale: float = card.effect.get("max_scale", 3.0)

	var stats: Dictionary = bullet_node.get_base_stats()
	stats["size_growth"] = true
	stats["growth_per_hit"] = growth_per_hit
	stats["max_fate_scale"] = max_scale
	bullet_node.set_base_stats(stats)
	bullet_node.tags.append("Fate.SizeGrowth")

	result.success = true
	_fate_audio_card_applied()
	result.modified_nodes = [bullet_node]
	result.effect_value = {"growth_per_hit": growth_per_hit, "max_scale": max_scale}
	result.message = "Set size growth (+%.0f%%/hit, max=%.0fx) on %s" % [
		growth_per_hit * 100.0, max_scale, bullet_node.node_name
	]
	return result


## ========== 辅助方法 ==========


static func _find_player() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.get_root() == null:
		return null
	var player: Node = tree.get_first_node_in_group("player")
	if player != null:
		return player
	var root: Node = tree.get_root()
	player = root.get_node_or_null("Main/RoomGameMode/Player")
	if player == null:
		player = root.find_child("Player", true, false)
	return player


static func _find_room_game_mode() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.get_root() == null:
		return null
	var root: Node = tree.get_root()
	var rgm: Node = root.get_node_or_null("Main/RoomGameMode")
	if rgm == null:
		rgm = root.find_child("RoomGameMode", false, false)
	return rgm


static func _find_fate_card_bridge() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group("fate_cards")


## 播放命运卡片应用音效（供各效果方法调用）
static func _fate_audio_card_applied() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var audio := tree.root.get_node_or_null("AudioManager") as AudioManager
	if audio != null:
		audio.play_fate_card_sfx()
