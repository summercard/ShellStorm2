extends Control

# FateCardUIController.gd — 命运卡片选择 UI 控制器
# 管理卡片选择界面的显示/隐藏、卡片列表、选中逻辑

## 引用
@onready var card_container: HBoxContainer = $CardPanel/VBox/CardsContainer
@onready var card_panel: Panel = $CardPanel
@onready var instruction_label: Label = $CardPanel/VBox/InstructionLabel

## 预制卡片样式（用于动态创建卡片按钮）
const CARD_SCENE = preload("res://scenes/FateCardButton.tscn")

## 当前显示的卡片选项
var current_options: Array[FateCard] = []

## 是否正在显示选卡界面
var is_visible: bool = false

func _ready() -> void:
	# 初始隐藏卡片选择界面
	card_panel.hide()
	# 连接快捷键（Tab 键切换选卡 UI）
	
func _input(event: InputEvent) -> void:
	# 按 Tab 键切换显示/隐藏（游戏中可重新选卡）
	if event.is_action_pressed("ui_tab") and not is_visible:
		show_card_selection()
	elif event.is_action_pressed("ui_cancel") and is_visible:
		hide_card_selection()

## 显示卡片选择界面（从预设中随机抽 3 张）
func show_card_selection() -> void:
	if is_visible:
		return
	
	# 清空旧选项
	current_options.clear()
	for child in card_container.get_children():
		child.queue_free()
	
	# 从预设中随机抽取 3 张
	var all_cards = FateCardPresets.all_presets()
	all_cards.shuffle()
	current_options = all_cards.slice(0, 3)
	
	# 创建卡片按钮
	for card in current_options:
		var btn = _create_card_button(card)
		card_container.add_child(btn)
	
	card_panel.show()
	is_visible = true
	get_tree().paused = true

## 隐藏卡片选择界面
func hide_card_selection() -> void:
	card_panel.hide()
	is_visible = false
	get_tree().paused = false

## 创建一张卡片按钮
func _create_card_button(card: FateCard) -> Button:
	var btn := Button.new()
	
	# 设置按钮文本（卡片名 + 品质 + 类型）
	var rarity_color = FateCard.rarity_color(card.card_rarity)
	var color_hex = "#%02X%02X%02X" % [int(rarity_color.r * 255), int(rarity_color.g * 255), int(rarity_color.b * 255)]
	
	btn.text = "[%s] %s\n%s\n%s" % [
		FateCard.rarity_name(card.card_rarity),
		card.card_name,
		FateCard.type_name(card.card_type),
		card.description
	]
	btn.custom_minimum_size = Vector2(180, 100)
	btn.tooltip_text = card.description
	
	# 绑定点击事件
	btn.pressed.connect(_on_card_selected.bind(card))
	
	return btn

## 玩家选中了一张卡片
func _on_card_selected(card: FateCard) -> void:
	# 通过 FateCardGameBridge 应用卡片
	var result = FateCardGameBridge.apply_card(card)
	
	if result.success:
		print("[FateCardUI] 应用卡片成功: %s — %s" % [card.card_name, result.message])
	else:
		print("[FateCardUI] 应用卡片失败: %s — %s" % [card.card_name, result.message])
	
	hide_card_selection()

## 获取当前选项（用于调试）
func get_current_options() -> Array[FateCard]:
	return current_options.duplicate()