extends Node
class_name ItemUseHandler
## 物品使用处理器 — 集中处理 use_action 字符串路由
## 配合 InventoryModule.consume_item 使用：consume_item 扣物品数量，handler 触发效果
## 
## 使用场景：
##   1. GameUIManager 右键背包物品 → consume_item + ItemUseHandler.apply(player, item)
##   2. ExtractionProgressUI BEACON 按钮 → ExtractionDirector.summon_beacon_extraction() (直接调用，无需 handler)

## 单例（延迟初始化）
static var _instance: ItemUseHandler = null
static func get_instance() -> ItemUseHandler:
	if _instance == null:
		_instance = ItemUseHandler.new()
	return _instance

## 预加载脚本（供 GameUIManager 直接 new 使用）
const _SCRIPT := preload("res://src/game/ItemUseHandler.gd")

func _init() -> void:
	pass

## 应用物品效果（返回是否成功）
## item 是物品定义字典（来自 ItemRegistry）
func apply(item: Dictionary, context: Dictionary = {}) -> bool:
	if item.is_empty():
		return false
	
	var use_action: String = item.get("use_action", "")
	if use_action.is_empty():
		return false
	
	match use_action:
		"heal":
			return _apply_heal(item, context)
		"refill_ammo":
			return _apply_refill_ammo(item, context)
		"summon_beacon_extraction":
			return _apply_summon_beacon(item, context)
		"unlock_blueprint":
			return _apply_unlock_blueprint(item, context)
		_:
			print("[ItemUseHandler] Unknown use_action: %s" % use_action)
			return false

## 治疗
func _apply_heal(item: Dictionary, context: Dictionary) -> bool:
	var heal_amount: int = item.get("heal_amount", 30)
	var player: Node = _resolve_player(context)
	if player == null or not player.has_method("heal"):
		print("[ItemUseHandler] heal failed: player not found or has no heal method")
		return false
	
	player.heal(heal_amount)
	print("[ItemUseHandler] Applied heal: %d HP" % heal_amount)
	return true

## 弹药补给（触发一次换弹）
func _apply_refill_ammo(item: Dictionary, context: Dictionary) -> bool:
	var player: Node = _resolve_player(context)
	if player == null or not player.has_method("get_weapon_tree"):
		print("[ItemUseHandler] refill_ammo failed: player not found or has no weapon_tree")
		return false
	
	var weapon_tree: Node = player.get_weapon_tree()
	if weapon_tree == null or not weapon_tree.has_method("start_reload"):
		print("[ItemUseHandler] refill_ammo failed: weapon_tree has no start_reload")
		return false
	
	weapon_tree.start_reload()
	print("[ItemUseHandler] Applied refill_ammo: reloading weapon")
	return true

## 信标撤离
func _apply_summon_beacon(item: Dictionary, context: Dictionary) -> bool:
	var extraction_director: Node = _resolve_extraction_director(context)
	if extraction_director == null or not extraction_director.has_method("summon_beacon_extraction"):
		print("[ItemUseHandler] summon_beacon failed: ExtractionDirector not found")
		return false
	
	var ok: bool = extraction_director.summon_beacon_extraction()
	if ok:
		print("[ItemUseHandler] Applied summon_beacon: extraction point created")
	else:
		print("[ItemUseHandler] summon_beacon failed: no beacon item available")
	return ok

## 蓝图解锁
func _apply_unlock_blueprint(item: Dictionary, context: Dictionary) -> bool:
	var bp_category: String = item.get("blueprint_category", "")
	var bp_loot_tier: int = item.get("blueprint_loot_tier", 0)
	var ep_reward: int = item.get("extraction_points_reward", 20)

	if bp_category.is_empty():
		print("[ItemUseHandler] unlock_blueprint failed: no blueprint_category")
		return false

	# 检查是否已解锁更高Tier
	var current_tier: int = BaseManager.get_blueprint_tier(bp_category)
	if current_tier >= bp_loot_tier + 1:
		print("[ItemUseHandler] unlock_blueprint: %s already at Tier %d (>= %d)" % [bp_category, current_tier, bp_loot_tier + 1])
		# 仍然给资源点奖励，但不提升Tier
	else:
		# 提升蓝图Tier到 loot_tier + 1（即蓝图能解锁到该Tier的物品）
		BaseManager.set_blueprint_tier(bp_category, bp_loot_tier + 1)
		print("[ItemUseHandler] Applied unlock_blueprint: %s → Tier %d" % [bp_category, bp_loot_tier + 1])

	# 给资源点奖励
	BaseManager.add_extraction_points(ep_reward)
	print("[ItemUseHandler] unlock_blueprint: awarded %d extraction_points" % ep_reward)
	return true

## 解析 player 节点
func _resolve_player(context: Dictionary) -> Node:
	var player: Node = context.get("player", null)
	if player != null:
		return player
	player = get_tree().get_first_node_in_group("player")
	if player != null:
		return player
	player = get_node_or_null("/root/Main/YSort/Player")
	if player != null:
		return player
	player = get_node_or_null("/root/Main/Player")
	return player

## 解析 ExtractionDirector
func _resolve_extraction_director(context: Dictionary) -> Node:
	var ed: Node = context.get("extraction_director", null)
	if ed != null:
		return ed
	ed = get_node_or_null("/root/Main/MapManager/ExtractionDirector")
	if ed != null:
		return ed
	ed = get_node_or_null("/root/MapManager/ExtractionDirector")
	if ed != null:
		return ed
	var map_manager: Node = get_node_or_null("/root/Main/MapManager")
	if map_manager != null and map_manager.has("extraction_director"):
		return map_manager.get("extraction_director")
	return null
