extends Node
class_name FateCardGameBridge

# FateCardGameBridge.gd — 命运卡片游戏桥接器
# Autoload 单例，全局管理命运卡片的实际应用
# 串联 FateCard 系统与 WeaponAssemblyTree 系统

## 信号
signal card_applied(card: FateCard, success: bool, message: String)
signal card_list_changed()

## 玩家已应用的卡片列表
var applied_cards: Array[FateCard] = []

## 玩家武器装配树（由 Player 初始化后注入）
var _player_weapon_tree: WeaponAssemblyTree = null

func _ready() -> void:
	# 等待 Player 节点准备就绪后再获取 weapon_tree
	await get_tree().create_timer(0.1).timeout
	_connect_to_player()

func _connect_to_player() -> void:
	# 延迟获取玩家节点，避免时序问题
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("get_weapon_tree"):
		_player_weapon_tree = player.get_weapon_tree()
		_player_weapon_tree.tree_changed.connect(_on_tree_changed)

## 应用一张命运卡片
func apply_card(card: FateCard) -> FateCardExecutor.ApplyResult:
	if card == null:
		var result := FateCardExecutor.ApplyResult.new()
		result.success = false
		result.message = "Card is null"
		return result

	if _player_weapon_tree == null:
		var result := FateCardExecutor.ApplyResult.new()
		result.success = false
		result.message = "Player weapon tree not initialized"
		return result

	var result := FateCardExecutor.apply_card(card, _player_weapon_tree)

	if result.success:
		applied_cards.append(card)
		card_applied.emit(card, true, result.message)
		card_list_changed.emit()
	else:
		card_applied.emit(card, false, result.message)

	return result

## 获取玩家的武器装配树
func get_weapon_tree() -> WeaponAssemblyTree:
	return _player_weapon_tree

## 获取当前已应用的卡片数量
func get_card_count() -> int:
	return applied_cards.size()

## 获取所有已应用的卡片
func get_cards() -> Array[FateCard]:
	return applied_cards.duplicate()

func _on_tree_changed() -> void:
	# 装配树变化时可以触发对应的 UI 更新
	pass

func _to_string() -> String:
	return "[FateCardGameBridge: cards=%d]" % applied_cards.size()