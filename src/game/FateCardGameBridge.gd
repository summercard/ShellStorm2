extends Node

# FateCardGameBridge.gd — 命运卡片游戏桥接器
# 串联 FateCard 系统与 WeaponAssemblyTree 系统
# Autoload 单例

## 信号
signal card_applied(card: FateCard, success: bool, message: String)
signal card_list_changed()

## 玩家已应用的卡片列表
var applied_cards: Array[FateCard] = []

## 玩家武器装配树（由 Player 初始化后注入）
var _player_weapon_tree: WeaponAssemblyTree = null

func _ready() -> void:
	add_to_group("fate_cards")
	await get_tree().create_timer(0.1).timeout
	_connect_to_player()

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
	var weapon_tree: WeaponAssemblyTree = player.get_weapon_tree()
	if weapon_tree == null:
		return
	if _player_weapon_tree != null and _player_weapon_tree.tree_changed.is_connected(_on_tree_changed):
		_player_weapon_tree.tree_changed.disconnect(_on_tree_changed)
	_player_weapon_tree = weapon_tree
	if not _player_weapon_tree.tree_changed.is_connected(_on_tree_changed):
		_player_weapon_tree.tree_changed.connect(_on_tree_changed)

## 实例方法：实际应用卡片
func apply_card_instance(card: FateCard) -> Dictionary:
	if card == null:
		return {"success": false, "message": "Card is null"}

	if _player_weapon_tree == null:
		return {"success": false, "message": "Player weapon tree not initialized"}

	# 委托给 FateCardEngine 执行完整效果（支持所有 EffectAction）
	# 使用 GDScript preload 避免 class_name 加载顺序问题
	var engine_script: GDScript = preload("res://src/weapons/FateCardEngine.gd") as GDScript
	var engine_class: Variant = engine_script
	var engine_result: Object = engine_class.apply_card(card, _player_weapon_tree)

	var result_dict: Dictionary = {
		"success": engine_result.success,
		"message": engine_result.message,
	}
	if engine_result.success:
		applied_cards.append(card)
		card_applied.emit(card, true, engine_result.message)
		card_list_changed.emit()
	else:
		card_applied.emit(card, false, engine_result.message)

	return result_dict

## 应用一张命运卡片（静态方法，供外部调用）
static func apply_card(card: FateCard) -> Dictionary:
	if card == null:
		return {"success": false, "message": "Card is null"}

	var instance: Node = _get_instance()
	if instance == null:
		return {"success": false, "message": "FateCardGameBridge instance not found"}

	return instance.apply_card_instance(card)

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
