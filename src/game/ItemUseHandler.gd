extends Node
class_name ItemUseHandler
## 物品使用处理器 — 集中处理 use_action 字符串路由
## 配合 InventoryModule.consume_item 使用：consume_item 扣物品数量，handler 触发效果
## 
## 使用场景：
##   1. 3D 背包界面使用物品 → consume_item + ItemUseHandler.apply(item, context)
##   2. 3D 撤离信标由 Dungeon3D 流程直接处理，无需 handler

## 单例（延迟初始化）
static var _instance: ItemUseHandler = null
static func get_instance() -> ItemUseHandler:
	if _instance == null or not is_instance_valid(_instance):
		_instance = ItemUseHandler.new()
		# Node型单例必须由SceneTree持有。仅保存在静态字段会成为未入树孤儿，
		# 退出时留下ItemUseHandler脚本资源和ObjectDB实例。
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.root.add_child(_instance)
	return _instance

## 预加载脚本（供当前 UI/运行时直接 new 使用）
const _SCRIPT := preload("res://src/game/ItemUseHandler.gd")

# 三类电池对应的恢复比例(与 ItemRegistry 物品定义一一对应)
const FLASHLIGHT_RESTORE_MAP := {
	"item_battery_s": 0.25,
	"item_battery_l": 0.75,
	"item_cell_pack": 1.0,
}

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
		"restore_flashlight_charge":
			return _apply_restore_flashlight_charge(item, context)
		"equip_flashlight_module":
			return _apply_equip_flashlight_module(item, context)
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
	var current_hp = player.get("current_hp")
	var max_hp = player.get("max_hp")
	if current_hp != null and max_hp != null and int(current_hp) >= int(max_hp):
		print("[ItemUseHandler] heal skipped: player is already at full health")
		return false
	
	player.heal(heal_amount)
	print("[ItemUseHandler] Applied heal: %d HP" % heal_amount)
	return true

## 弹药补给（触发一次换弹）
func _apply_refill_ammo(item: Dictionary, context: Dictionary) -> bool:
	var player: Node = _resolve_player(context)
	if player != null and player.has_method("request_reload"):
		return bool(player.call("request_reload"))
	if player != null and player.has_method("refill_ammo"):
		return bool(player.call("refill_ammo"))
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


## 电池恢复手电筒电量。已满则拒绝,quick-slot 据此不消耗道具。
func _apply_restore_flashlight_charge(item: Dictionary, context: Dictionary) -> bool:
	var player: Node = _resolve_player(context)
	if player == null:
		print("[ItemUseHandler] restore_flashlight_charge failed: player not found")
		return false
	var flashlight := player.get_node_or_null("PlayerFlashlight3D")
	if flashlight == null:
		print("[ItemUseHandler] restore_flashlight_charge failed: flashlight node missing")
		return false
	var item_id: String = str(item.get("id", ""))
	var amount: float = float(FLASHLIGHT_RESTORE_MAP.get(item_id, float(item.get("restore_amount", 0.25))))
	if amount <= 0.0:
		print("[ItemUseHandler] restore_flashlight_charge failed: unknown battery id %s" % item_id)
		return false
	if bool(flashlight.call("restore_charge", amount)):
		print("[ItemUseHandler] Applied restore_flashlight_charge: +%d%% via %s" % [int(round(amount * 100.0)), item_id])
		return true
	print("[ItemUseHandler] restore_flashlight_charge skipped: flashlight already full")
	return false


## 装备手电筒模块(仅在基地生效)
func _apply_equip_flashlight_module(item: Dictionary, context: Dictionary) -> bool:
	var player: Node = _resolve_player(context)
	if player == null or not player.has_method("equip_flashlight_module"):
		print("[ItemUseHandler] equip_flashlight_module failed: player missing or not 3D")
		return false
	var module_id := str(item.get("module_id", ""))
	if module_id.is_empty():
		module_id = str(item.get("id", "")).trim_prefix("item_flashlight_")
	if module_id.is_empty() or not player.has_method("is_player_inside_facility") or not bool(player.is_player_inside_facility()):
		print("[ItemUseHandler] equip_flashlight_module rejected: facility required")
		return false
	var flashlight := player.get_node_or_null("PlayerFlashlight3D")
	if flashlight == null:
		print("[ItemUseHandler] equip_flashlight_module rejected: flashlight missing")
		return false
	# 点击基地设施的同一帧就允许安装，不能依赖下一次 Player3D.physics_process 才刷新状态。
	flashlight.set_in_facility(true)
	# 稀有实体模块在基地确认安装后转为永久解锁；之后工坊只切长期装备选择。
	if module_id == "efficient" and not BaseManager.unlock_flashlight_module(module_id):
		print("[ItemUseHandler] equip_flashlight_module rejected: unlock save failed")
		return false
	if not BaseManager.is_flashlight_module_unlocked(module_id):
		print("[ItemUseHandler] equip_flashlight_module rejected: module locked")
		return false
	if not BaseManager.set_equipped_flashlight_module(module_id):
		print("[ItemUseHandler] equip_flashlight_module rejected: equip save failed")
		return false
	var result: Dictionary = player.equip_flashlight_module(item)
	if bool(result.get("success", false)):
		print("[ItemUseHandler] Applied equip_flashlight_module: %s" % str(item.get("id", "?")))
		return true
	print("[ItemUseHandler] equip_flashlight_module rejected: %s" % str(result.get("reason", "?")))
	return false


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
