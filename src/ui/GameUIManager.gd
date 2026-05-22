class_name GameUIManager
## 游戏 UI 总管理器
## 独立管理所有游戏界面元素，与 RoomGameMode 解耦
## RoomGameMode 通过 signal 通知 UI 更新，UI Manager 订阅 signal

extends CanvasLayer

## — 游戏状态 UI —
@onready var hp_bar: ProgressBar = $GameHUD/HPBarBG/HPBar
@onready var score_label: Label = $GameHUD/TopRightPanel/VBox/ScoreLabel
@onready var wave_label: Label = $GameHUD/TopRightPanel/VBox/WaveLabel
@onready var currency_label: Label = $GameHUD/CurrencyLabel
@onready var room_info_label: Label = $GameHUD/RoomInfoLabel
@onready var clearing_progress: ProgressBar = $GameHUD/ClearingProgress

## — 背包 UI —
@onready var inventory_panel: PanelContainer = $InventoryPanel
@onready var inventory_capacity_label: Label = $InventoryPanel/VBox/CapacityLabel

## — 撤离 UI —
@onready var extraction_panel: PanelContainer = $ExtractionPanel
@onready var extraction_type_label: Label = $ExtractionPanel/VBox/ExtractionTypeLabel
@onready var countdown_bar: ProgressBar = $ExtractionPanel/VBox/CountdownBar
@onready var countdown_label: Label = $ExtractionPanel/VBox/CountdownLabel
@onready var abort_button: Button = $ExtractionPanel/VBox/AbortButton

## — 命运卡片 UI —
@onready var fate_card_panel: Control = $FateCardPanel

var _room_game_mode: Node = null
var _inventory_module: Node = null
var _extraction_module: Node = null
var _insurance_module: Node = null

func _ready() -> void:
	# 初始隐藏
	extraction_panel.visible = false
	inventory_panel.visible = false
	fate_card_panel.visible = false
	clearing_progress.visible = false

## 绑定房间游戏模式
func set_room_game_mode(mode: Node) -> void:
	_room_game_mode = mode
	
	# 连接信号
	if mode.has_signal("room_cleared"):
		mode.room_cleared.connect(_on_room_cleared)
	if mode.has_signal("game_over"):
		mode.game_over.connect(_on_game_over)
	if mode.has_signal("extraction_ready"):
		mode.extraction_ready.connect(_on_extraction_ready)
	if mode.has_signal("floor_changed"):
		mode.floor_changed.connect(_on_floor_changed)

## 绑定背包模块
func set_inventory_module(module: Node) -> void:
	_inventory_module = module
	if module.has_signal("inventory_changed"):
		module.inventory_changed.connect(_on_inventory_changed)
	if module.has_signal("capacity_changed"):
		module.capacity_changed.connect(_on_capacity_changed)

## 绑定保险格模块
func set_insurance_module(module: Node) -> void:
	_insurance_module = module
	if module.has_signal("insurance_changed"):
		module.insurance_changed.connect(_on_insurance_changed)

## 绑定撤离模块
func set_extraction_module(module: Node) -> void:
	_extraction_module = module
	if module.has_signal("extraction_completed"):
		module.extraction_completed.connect(_on_extraction_completed)
	if module.has_signal("extraction_aborted"):
		module.extraction_aborted.connect(_on_extraction_aborted)

## 更新 HP 显示
func update_hp(current: int, maximum: int) -> void:
	if hp_bar:
		hp_bar.max_value = maximum
		hp_bar.value = current

## 更新分数
func update_score(score_val: int) -> void:
	if score_label:
		score_label.text = "Score: %d" % score_val

## 更新货币
func update_currency(amount: int) -> void:
	if currency_label:
		currency_label.text = "魂: %d" % amount

## 更新楼层
func update_floor(floor: int) -> void:
	if wave_label:
		wave_label.text = "Floor: %d" % floor

## 房间清理完成
func _on_room_cleared(room_data) -> void:
	if room_info_label:
		room_info_label.text = "房间清理完成！"
	clearing_progress.visible = false

## 游戏结束
func _on_game_over(reason: String) -> void:
	if room_info_label:
		room_info_label.text = "游戏结束: %s" % reason

## 撤离就绪
func _on_extraction_ready() -> void:
	if extraction_panel:
		extraction_panel.visible = true

## 楼层变化
func _on_floor_changed(old_f: int, new_f: int) -> void:
	update_floor(new_f)

## 背包变化
func _on_inventory_changed() -> void:
	if inventory_capacity_label and _inventory_module:
		var used = _inventory_module.get("get_used_slots")
		if used != null:
			inventory_capacity_label.text = "背包 %d/12" % used

## 容量变化
func _on_capacity_changed(current: int, maximum: int) -> void:
	if inventory_capacity_label:
		inventory_capacity_label.text = "背包 %d/%d" % [current, maximum]

## 保险格变化
func _on_insurance_changed() -> void:
	pass  # 可扩展

## 撤离完成
func _on_extraction_completed(success: bool, loot: Array) -> void:
	extraction_panel.visible = false

## 撤离中断
func _on_extraction_aborted() -> void:
	if room_info_label:
		room_info_label.text = "撤离已中断！"

## 隐藏所有面板
func hide_all_panels() -> void:
	extraction_panel.visible = false
	inventory_panel.visible = false
	fate_card_panel.visible = false