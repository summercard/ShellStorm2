extends Node

# FateCardGameBridge.gd — 命运卡片游戏桥接器
# 串联 FateCard 系统与 WeaponAssemblyTree 系统
# Autoload 单例

## 信号
signal card_applied(card: FateCard, success: bool, message: String)
signal card_list_changed()
signal scope_state_changed(scope: String, stable_card_id: String)

## 玩家已应用的卡片列表
var applied_cards: Array[FateCard] = []
var character_card_ids: Array[String] = []
var world_card_ids: Array[String] = []

## 玩家武器装配树（由 Player 初始化后注入）
var _player_weapon_tree: WeaponAssemblyTree = null
var _player: Node = null

func _ready() -> void:
	add_to_group("fate_cards")
	call_deferred("_connect_to_player")

func _connect_to_player() -> void:
	# 正确路径：/root/Main/Player（Player.gd 在 _ready 中 add_to_group("player")）
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		player = get_tree().get_root().get_node_or_null("Main/Player")
	if player == null:
		var main = get_tree().get_root().get_node_or_null("Main")
		if main != null and main.has_node("Player"):
			player = main.get_node("Player")
	if player != null and player.has_method("get_weapon_tree"):
		set_player(player)
		if _player_weapon_tree == null:
			push_warning("[FateCardGameBridge] Player found but weapon tree is null (weapon may not be initialized yet)")

func set_player(player: Node) -> void:
	if player == null or not player.has_method("get_weapon_tree"):
		return
	_player = player
	var weapon_tree: WeaponAssemblyTree = player.get_weapon_tree()
	if weapon_tree == null:
		return
	if _player_weapon_tree != null and _player_weapon_tree.tree_changed.is_connected(_on_tree_changed):
		_player_weapon_tree.tree_changed.disconnect(_on_tree_changed)
	_player_weapon_tree = weapon_tree
	if not _player_weapon_tree.tree_changed.is_connected(_on_tree_changed):
		_player_weapon_tree.tree_changed.connect(_on_tree_changed)


func reset_run_state() -> void:
	applied_cards.clear()
	character_card_ids.clear()
	world_card_ids.clear()
	card_list_changed.emit()

## 实例方法：实际应用卡片
func apply_card_instance(card: FateCard) -> Dictionary:
	if card == null:
		return {"success": false, "message": "Card is null"}

	if _player == null or not is_instance_valid(_player):
		_connect_to_player()
	if _player_weapon_tree == null:
		return {"success": false, "message": "Player weapon tree not initialized"}

	var scope_name := FateCard.scope_name(card.scope)
	var target_snapshot: Dictionary = {}
	if card.scope == FateCard.Scope.WEAPON:
		if _player == null or not _player.has_method("get_weapon_presentation_snapshot"):
			return {"success": false, "message": "当前枪械实例不可用", "scope": scope_name}
		target_snapshot = _player.call("get_weapon_presentation_snapshot") as Dictionary
		if target_snapshot.is_empty():
			return {"success": false, "message": "当前没有装备枪械", "scope": scope_name}
		var used := int(target_snapshot.get("fate_slot_used", 0))
		var capacity := int(target_snapshot.get("fate_slot_capacity", 0))
		if used >= capacity:
			return {
				"success": false,
				"message": "枪械命运槽已满 %d/%d；卡片未消耗" % [used, capacity],
				"scope": scope_name,
				"weapon_instance_id": target_snapshot.get("weapon_instance_id", ""),
				"slot_used": used,
				"slot_capacity": capacity,
			}

	# 委托给 FateCardEngine 执行完整效果（支持所有 EffectAction）
	# 使用 GDScript preload 避免 class_name 加载顺序问题
	var engine_script: GDScript = preload("res://src/weapons/FateCardEngine.gd") as GDScript
	var engine_class: Variant = engine_script
	var engine_result: Object = engine_class.apply_card(card, _player_weapon_tree)

	var result_dict: Dictionary = {
		"success": engine_result.success,
		"message": engine_result.message,
		"scope": scope_name,
		"scope_special_name": FateCard.scope_special_name(card.scope),
		"scope_display_name": FateCard.scope_display_name(card.scope),
	}
	if engine_result.success:
		if card.scope == FateCard.Scope.WEAPON:
			var transaction_id := "fate:%s:%s" % [
				target_snapshot.get("weapon_instance_id", ""), card.get_stable_card_id(),
			]
			var slot_result := _player.call(
				"append_equipped_fate_upgrade", card, transaction_id
			) as Dictionary
			if not bool(slot_result.get("success", false)):
				result_dict["success"] = false
				result_dict["message"] = str(slot_result.get("reason", "命运槽提交失败"))
				card_applied.emit(card, false, result_dict["message"])
				return result_dict
			var record := slot_result.get("record", {}) as Dictionary
			result_dict["weapon_instance_id"] = target_snapshot.get("weapon_instance_id", "")
			result_dict["slot_index"] = record.get("slot_index", 0)
			result_dict["slot_capacity"] = target_snapshot.get("fate_slot_capacity", 0)
		elif card.scope == FateCard.Scope.CHARACTER:
			if int(card.effect.get("action", -1)) == FateCard.EffectAction.APPLY_SCOPED_MODIFIER:
				if _player == null or not _player.has_method("apply_character_fate_modifier"):
					result_dict["success"] = false
					result_dict["message"] = "角色命运所有者不可用；卡片未消耗"
					card_applied.emit(card, false, result_dict["message"])
					return result_dict
				var character_result := _player.call("apply_character_fate_modifier", card.effect) as Dictionary
				if not bool(character_result.get("success", false)):
					result_dict["success"] = false
					result_dict["message"] = str(character_result.get("message", "角色命运应用失败"))
					card_applied.emit(card, false, result_dict["message"])
					return result_dict
			character_card_ids.append(card.get_stable_card_id())
			scope_state_changed.emit(scope_name, card.get_stable_card_id())
		else:
			world_card_ids.append(card.get_stable_card_id())
			scope_state_changed.emit(scope_name, card.get_stable_card_id())
		applied_cards.append(card)
		card_applied.emit(card, true, engine_result.message)
		card_list_changed.emit()
	else:
		card_applied.emit(card, false, engine_result.message)

	return result_dict


func get_target_summary(card: FateCard = null) -> Dictionary:
	if card == null:
		return {}
	var result := {
		"scope": FateCard.scope_name(card.scope),
		"scope_special_name": FateCard.scope_special_name(card.scope),
		"scope_display_name": FateCard.scope_display_name(card.scope),
		"occupies_weapon_slot": card.occupies_weapon_slot(),
		"stable_card_id": card.get_stable_card_id(),
	}
	if card.scope == FateCard.Scope.WEAPON and _player != null and _player.has_method(
		"get_weapon_presentation_snapshot"
	):
		var snapshot := _player.call("get_weapon_presentation_snapshot") as Dictionary
		result.merge(snapshot, true)
		result["next_slot_index"] = int(snapshot.get("fate_slot_used", 0)) + 1
	return result

## 应用一张命运卡片（静态方法，供外部调用）
static func apply_card(card: FateCard) -> Dictionary:
	if card == null:
		return {"success": false, "message": "Card is null"}

	var instance: Node = _get_instance()
	if instance == null:
		return {"success": false, "message": "FateCardGameBridge instance not found"}

	return instance.apply_card_instance(card)

## 获取单例实例（通过组查找，比节点路径更稳定）
static func apply_fate_card_from_trigger(fate_card_id: String) -> Dictionary:
	## 供 MapFateTriggers 调用：fate_card_id 字符串 → 找到对应 preset → 执行效果
	## 避免 MapFateTriggers 需要直接引用 FateCardEngine
	var card: FateCard = null
	match fate_card_id:
		"fate_reinforce": card = FateCardPresets.fate_reinforce()
		"fate_mark_enemy": card = FateCardPresets.fate_mark_enemy()
		"fate_lucky_chest": card = FateCardPresets.fate_lucky_chest()
		"fate_extra_loot": card = FateCardPresets.fate_extra_loot()
		"fate_curse_map": card = FateCardPresets.fate_curse_map()
		"fate_bless_dead": card = FateCardPresets.fate_bless_dead()
	if card == null:
		return {"success": false, "message": "Unknown fate_card_id: " + fate_card_id}
	return apply_card(card)


## 获取单例实例（通过组查找，比节点路径更稳定）
static func _get_instance() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group("fate_cards")

func get_weapon_tree() -> WeaponAssemblyTree:
	return _player_weapon_tree

func get_card_count() -> int:
	return applied_cards.size()

func get_cards() -> Array[FateCard]:
	return applied_cards.duplicate()


func get_scope_cards(scope: FateCard.Scope) -> Array[FateCard]:
	var cards: Array[FateCard] = []
	for card in applied_cards:
		if card != null and card.scope == scope:
			cards.append(card)
	return cards


func get_scope_state_snapshot() -> Dictionary:
	var character_cards: Array[Dictionary] = []
	var world_cards: Array[Dictionary] = []
	for card in applied_cards:
		if card == null or card.scope == FateCard.Scope.WEAPON:
			continue
		var entry := {
			"stable_card_id": card.get_stable_card_id(),
			"name": card.card_name,
			"short_description": card.short_description,
			"scope": FateCard.scope_name(card.scope),
			"scope_display_name": FateCard.scope_display_name(card.scope),
		}
		if card.scope == FateCard.Scope.CHARACTER:
			character_cards.append(entry)
		else:
			world_cards.append(entry)
	return {"character": character_cards, "world": world_cards}

## 给予随机命运卡片（由环境命运触发器调用，通过 FateCardEngine 间接触发）
func grant_random_card_from_trigger() -> void:
	# 从 FateCardPresets 随机选一张给予玩家（仅记录到应用列表，UI展示由调用方处理）
	var all_cards: Array[FateCard] = []
	var by_type = FateCardPresets.by_type(FateCard.CardType.ENHANCE)
	for c in by_type:
		all_cards.append(c)
	by_type = FateCardPresets.by_type(FateCard.CardType.RULE)
	for c in by_type:
		all_cards.append(c)
	by_type = FateCardPresets.by_type(FateCard.CardType.MUTATE)
	for c in by_type:
		all_cards.append(c)
	if all_cards.is_empty():
		return
	var random_card: FateCard = all_cards[randi() % all_cards.size()]
	applied_cards.append(random_card)
	card_applied.emit(random_card, true, "环境命运：获得随机命运卡片 " + random_card.card_name)
	card_list_changed.emit()

## 记录已应用的命运卡片（由 FateCardEngine 在环境命运触发器中调用）
func record_applied_card(card: FateCard) -> void:
	if card == null:
		return
	applied_cards.append(card)
	card_applied.emit(card, true, "随机命卡：" + card.card_name)
	card_list_changed.emit()

func _on_tree_changed() -> void:
	pass

func _to_string() -> String:
	return "[FateCardGameBridge: cards=%d]" % applied_cards.size()
