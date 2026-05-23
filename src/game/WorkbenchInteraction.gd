class_name WorkbenchInteraction
extends Area2D

## 工作台交互组件 — 挂在工作台 Area2D 上
## 玩家接近后按 interact 键可打开武器改造界面
## 支持重新装配枪身、子弹、配件

signal workbench_interaction_available(available: bool)
signal workbench_opened()
signal workbench_closed()

enum WorkbenchState {
	AVAILABLE,   # 可交互
	OPEN,        # 界面已打开
	CLOSED,      # 已关闭
}

## 配置
@export var interaction_radius: float = 60.0

## 状态
var _state: WorkbenchState = WorkbenchState.AVAILABLE
var _player_in_range: bool = false
var _interact_label: Label = null
var _workbench_panel: Control = null
var _opened: bool = false
var _upgrade_slots: int = 1
var _free_use: bool = true

## 引用
var _player: Node = null
var _inventory_module: InventoryModule = null

func _ready() -> void:
	_setup_interaction_label()
	_state = WorkbenchState.AVAILABLE
	workbench_interaction_available.emit(false)
	
	# 连接 Area2D 信号
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

## 设置工作台属性（由 RoomFactory 调用）
func setup_workbench(upgrade_slots: int, free_use: bool) -> void:
	_upgrade_slots = upgrade_slots
	_free_use = free_use

## 设置背包引用（由 RoomFactory 用于后续改造消耗逻辑）
func set_inventory(inventory: InventoryModule) -> void:
	_inventory_module = inventory

func _setup_interaction_label() -> void:
	_interact_label = get_node_or_null("InteractLabel") as Label
	if _interact_label != null:
		_interact_label.z_index = 100
		_interact_label.modulate = Color(1, 1, 1, 0)

## Area2D 玩家进入信号回调
func _on_body_entered(body: Node2D) -> void:
	if body is Player or body.is_in_group("player"):
		_player_in_range = true
		_player = body
		if _state != WorkbenchState.OPEN and _interact_label:
			_interact_label.modulate = Color(1, 1, 1, 1)
		workbench_interaction_available.emit(true)

## Area2D 玩家离开信号回调
func _on_body_exited(body: Node2D) -> void:
	if body is Player or body.is_in_group("player"):
		_player_in_range = false
		_player = null
		if _interact_label:
			_interact_label.modulate = Color(1, 1, 1, 0)
		workbench_interaction_available.emit(false)

## 每帧处理输入
func _process(delta: float) -> void:
	if _opened:
		return
	
	if _player_in_range and Input.is_action_just_pressed("interact"):
		_open_workbench()

## 打开工作台界面
func _open_workbench() -> void:
	if _opened:
		return
	_opened = true
	_state = WorkbenchState.OPEN
	if _interact_label:
		_interact_label.modulate = Color(1, 1, 1, 0)
	
	# 隐藏标签，通知玩家
	workbench_opened.emit()
	
	# 动态加载工作台 UI 脚本并显示
	_show_workbench_panel()
	
	print("[WorkbenchInteraction] 工作台已打开")

## 显示工作台面板
func _show_workbench_panel() -> void:
	# 加载 WorkbenchPanel 场景
	var panel_scene_path := "res://scenes/WorkbenchPanel.tscn"
	if ResourceLoader.exists(panel_scene_path):
		var scene: PackedScene = load(panel_scene_path) as PackedScene
		if scene != null:
			_workbench_panel = scene.instantiate() as Control
	if _workbench_panel == null:
		push_warning("[WorkbenchInteraction] WorkbenchPanel scene not found, using fallback")
		_create_fallback_panel()
		return
	
	# 注入玩家引用
	if _workbench_panel.has_method("set_player"):
		_workbench_panel.set_player(_player)
	if _workbench_panel.has_method("set_workbench_ref"):
		_workbench_panel.set_workbench_ref(self)
	
	get_tree().get_root().add_child(_workbench_panel)

## 后备简易面板（当 WorkbenchPanel.gd 不存在时）
func _create_fallback_panel() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 400)
	panel.position = Vector2(200, 100)
	
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	
	var title := Label.new()
	title.text = "武器改造台"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var desc := Label.new()
	desc.text = "BlueprintTier: gunbody=%d, bullet=%d, attachment=%d" % [
		BaseManager.get_blueprint_tier("gunbody"),
		BaseManager.get_blueprint_tier("bullet"),
		BaseManager.get_blueprint_tier("attachment"),
	]
	vbox.add_child(desc)
	
	var info := Label.new()
	info.text = _get_weapon_tree_info()
	vbox.add_child(info)
	
	var close_btn := Button.new()
	close_btn.text = "关闭 [ESC]"
	close_btn.pressed.connect(_close_workbench)
	vbox.add_child(close_btn)
	
	get_tree().get_root().add_child(panel)
	_workbench_panel = panel

## 获取当前武器树信息
func _get_weapon_tree_info() -> String:
	if _player == null or not _player.has_method("get_weapon_tree"):
		return "玩家武器树不可用"
	
	var tree: Node = _player.get_weapon_tree()
	if tree == null or not tree.has_method("get_tree_string"):
		return "武器树未初始化"
	
	return tree.get_tree_string()

## 关闭工作台界面
func _close_workbench() -> void:
	if not _opened:
		return
	_opened = false
	_state = WorkbenchState.AVAILABLE
	
	if _workbench_panel != null:
		_workbench_panel.queue_free()
		_workbench_panel = null
	
	if _player_in_range and _interact_label:
		_interact_label.modulate = Color(1, 1, 1, 1)
	
	workbench_closed.emit()
	print("[WorkbenchInteraction] 工作台已关闭")

## 处理 ESC 关闭（由外部调用）
func handle_esc() -> void:
	if _opened:
		_close_workbench()