class_name MerchantInteraction
extends Area2D
## 商人交互组件 — 挂在商人NPC节点上，检测玩家接近并激活商人面板

## 信号
signal interaction_available(available: bool)

enum MerchantState {
	IDLE,         # 未激活
	AVAILABLE,    # 玩家在范围内
	ACTIVE,       # 玩家正在交易
}

## 配置
@export var interaction_radius: float = 80.0
@export var inventory_tier: int = 1
@export var shop_name: String = "流浪商人"

## 状态
var _state: MerchantState = MerchantState.IDLE
var _player_in_range: bool = false
var _interact_label: Label = null
var _merchant_ui: MerchantUI = null
var _inventory_module: InventoryModule = null
var _goods: Array[Dictionary] = []

func _ready() -> void:
	_setup_interaction_label()
	_state = MerchantState.IDLE
	interaction_available.emit(false)

## 设置背包引用
func set_inventory(inventory: InventoryModule) -> void:
	_inventory_module = inventory

## 设置商人层级
func set_tier(tier: int) -> void:
	inventory_tier = tier

## 设置显示名称
func set_shop_name(name: String) -> void:
	shop_name = name

## 预生成商品（由房间或 LootModule 调用）
func prepare_goods(goods: Array[Dictionary]) -> void:
	_goods = goods

## 连接商人UI
func set_merchant_ui(ui: MerchantUI) -> void:
	_merchant_ui = ui
	if _merchant_ui != null:
		_merchant_ui.set_inventory(_inventory_module)
		_merchant_ui.set_tier(inventory_tier)
		_merchant_ui.set_shop_name(shop_name)

## 获取或创建商人面板（如果还没创建，自动实例化一个）
func get_or_create_merchant_ui() -> MerchantUI:
	if _merchant_ui != null:
		return _merchant_ui
	
	# 动态实例化 MerchantUI 并挂载到当前场景
	var merchant_ui_scene_path := "res://src/ui/MerchantUI.gd"
	if not ResourceLoader.exists(merchant_ui_scene_path):
		push_warning("[MerchantInteraction] MerchantUI scene not found at %s" % merchant_ui_scene_path)
		return null
	
	# 从 GDScript 动态加载脚本创建节点（作为 MerchantUI 挂载）
	# MerchantUI extends Control，所以我们可以创建 Control 节点并设置脚本
	var ui_node := Control.new()
	ui_node.set_script(load(merchant_ui_scene_path) as Script)
	_merchant_ui = ui_node as MerchantUI
	
	# 设置基础属性
	_merchant_ui.name = "MerchantUI"
	_merchant_ui.anchor_left = 0.5
	_merchant_ui.anchor_right = 0.5
	_merchant_ui.anchor_top = 0.5
	_merchant_ui.anchor_bottom = 0.5
	_merchant_ui.offset_left = -200.0
	_merchant_ui.offset_right = 200.0
	_merchant_ui.offset_top = -200.0
	_merchant_ui.offset_bottom = 200.0
	_merchant_ui.z_index = 200
	
	# 连接关闭信号
	_merchant_ui.merchant_closed.connect(_on_merchant_ui_closed)
	
	# 挂载到房间根节点
	get_parent().add_child(_merchant_ui)
	
	# 初始隐藏
	_merchant_ui.hide()
	
	# 传递配置
	_merchant_ui.set_inventory(_inventory_module)
	_merchant_ui.set_tier(inventory_tier)
	_merchant_ui.set_shop_name(shop_name)
	
	return _merchant_ui

func _on_merchant_ui_closed() -> void:
	_state = MerchantState.AVAILABLE
	if _interact_label:
		_interact_label.modulate = Color(1, 1, 1, 1)

## 创建交互提示标签
func _setup_interaction_label() -> void:
	_interact_label = get_node_or_null("InteractLabel") as Label
	if _interact_label == null:
		_interact_label = get_node_or_null("../InteractLabel") as Label
	if _interact_label != null:
		_interact_label.z_index = 100
		_interact_label.modulate = Color(1, 1, 1, 0)

	# 连接 Area2D 信号
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

## Area2D 玩家进入信号回调
func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		if _state == MerchantState.IDLE:
			_state = MerchantState.AVAILABLE
		if _interact_label:
			_interact_label.modulate = Color(1, 1, 1, 1)
		interaction_available.emit(true)

## Area2D 玩家离开信号回调
func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		if _state == MerchantState.ACTIVE:
			_close_shop()
		if _interact_label:
			_interact_label.modulate = Color(1, 1, 1, 0)
		interaction_available.emit(false)

## 每帧处理输入
func _process(delta: float) -> void:
	if _state == MerchantState.AVAILABLE and _player_in_range:
		if Input.is_action_just_pressed("interact"):
			_open_shop()

## 打开商店面板
func _open_shop() -> void:
	if _state == MerchantState.ACTIVE:
		return
	
	_state = MerchantState.ACTIVE
	if _interact_label:
		_interact_label.modulate = Color(1, 1, 1, 0)
	
	# 生成商品（如果没有预生成）
	if _goods.is_empty():
		var loot := LootModule.get_instance()
		if loot != null:
			_goods = loot.generate_merchant_goods(inventory_tier, 6)
	
	# 获取或创建商人面板
	var ui := get_or_create_merchant_ui()
	if ui != null:
		ui.show_merchant(_goods)
	else:
		# 没有面板时，降级到控制台打印
		_print_goods_list()

## 关闭商店面板
func _close_shop() -> void:
	if _state != MerchantState.ACTIVE:
		return
	
	_state = MerchantState.AVAILABLE
	if _merchant_ui != null:
		_merchant_ui.hide_merchant()

## 强制设置状态为 ACTIVE（RoomGameMode 自动打开商人面板时调用）
## 解决 _auto_open_merchant() 直接 show_merchant() 但状态仍为 IDLE 的不一致问题
func force_set_active() -> void:
	_state = MerchantState.ACTIVE
	if _interact_label:
		_interact_label.modulate = Color(1, 1, 1, 0)

## 在控制台打印商品列表（回退方案）
func _print_goods_list() -> void:
	print("[Merchant] %s 商品列表:" % shop_name)
	for i in range(_goods.size()):
		var item: Dictionary = _goods[i]
		var price: int = item.get("price", 0)
		var name: String = item.get("name", "?")
		print("  [%d] %s — 魂 %d" % [i, name, price])
	print("  按数字键购买，或按 E 关闭")
