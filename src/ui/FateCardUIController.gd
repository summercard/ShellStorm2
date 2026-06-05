extends Control

# FateCardUIController.gd — 命运卡片选择 UI 控制器
# 管理卡片选择界面的显示/隐藏、卡片列表、选中逻辑
# 使用 GameUIManager 的 FateCardPanel 节点

## 引用（从 GameUIManager/FateCardPanel 查找）
var card_container: HBoxContainer
var card_panel: Control
var instruction_label: Label

## 当前显示的卡片选项
var current_options: Array[FateCard] = []

## 是否正在显示选卡界面
var is_visible: bool = false

## 来自 GameUIManager 的引用
var _ui_manager: Node = null


func _ready() -> void:
	# 必须设置为 ALWAYS，保证游戏暂停时也能接收 Tab 输入
	process_mode = Node.PROCESS_MODE_ALWAYS

	# 查找 GameUIManager（可能位于根节点的不同层级）
	_ui_manager = get_tree().get_first_node_in_group("game_ui")
	if _ui_manager == null:
		# 尝试：从根节点向下查找 GameUIManager
		var root: Node = get_tree().get_root()
		_ui_manager = root.find_child("GameUIManager", true, false)
		if _ui_manager == null:
			# 尝试 /root/Main/GameUIManager
			_ui_manager = root.get_node_or_null("Main/GameUIManager")
		if _ui_manager == null:
			# 兜底：遍历所有子节点找 GameUIManager
			_ui_manager = root.find_child("GameUIManager", false, true)

	# 查找 FateCardPanel（GameUIManager 的子节点）
	var fate_card_panel: Node = null
	if _ui_manager != null:
		fate_card_panel = _ui_manager.get_node_or_null("FateCardPanel")
	if fate_card_panel != null:
		card_panel = fate_card_panel as Panel
		card_container = fate_card_panel.get_node_or_null("VBox/CardOptions") as HBoxContainer
		instruction_label = fate_card_panel.get_node_or_null("VBox/InstructionLabel") as Label
	else:
		# 兜底：在本节点内查找
		card_panel = get_node_or_null("FateCardPanel") as Panel
		card_container = get_node_or_null("FateCardPanel/VBox/CardOptions") as HBoxContainer
		instruction_label = get_node_or_null("FateCardPanel/VBox/InstructionLabel") as Label

	if card_panel != null:
		card_panel.hide()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_visible:
		hide_card_selection()
	elif event.is_action_just_pressed("ui_tab"):
		# 只在卡片面板已显示且容器就绪时才拦截 Tab 关闭（防止竞争）
		if is_visible and card_panel != null and card_container != null:
			hide_card_selection()
			# 阻止事件继续传播，避免 DemoRoomGameMode._process() 再次触发 panel.toggle()
			get_tree().root.set_input_as_handled()
		# 卡片隐藏时让 WeaponAssemblyTreePanel 处理 Tab 切换


## 显示卡片选择界面（从预设中随机抽 3 张）
func show_card_selection() -> void:
	if is_visible:
		return

	# 清空旧选项
	current_options.clear()
	if card_container != null:
		for child in card_container.get_children():
			child.queue_free()

	# 从预设中随机抽取 3 张
	var all_cards = FateCardPresets.playable_presets()
	all_cards.shuffle()
	current_options = all_cards.slice(0, 3)

	# 创建卡片按钮
	if card_container != null:
		for card in current_options:
			var btn = _create_card_button(card)
			card_container.add_child(btn)

	# 更新提示文字
	if instruction_label != null:
		instruction_label.text = "选择一张命运卡片（Tab关闭）"

	if card_panel != null:
		card_panel.show()
	is_visible = true
	Global.acquire_pause("fate_card")


## 隐藏卡片选择界面
func hide_card_selection() -> void:
	if card_panel != null:
		card_panel.hide()
	is_visible = false
	Global.release_pause("fate_card")
	if _ui_manager != null:
		var room_mode = _ui_manager.get("_room_game_mode")
		if room_mode != null and room_mode.has_method("_on_fate_card_controller_hidden"):
			room_mode.call("_on_fate_card_controller_hidden")


## 创建一张卡片按钮
func _create_card_button(card: FateCard) -> Button:
	var btn := Button.new()

	var rarity_color = FateCard.rarity_color(card.card_rarity)
	var color_hex = (
		"#%02X%02X%02X"
		% [int(rarity_color.r * 255), int(rarity_color.g * 255), int(rarity_color.b * 255)]
	)

	btn.text = (
		"[%s] %s\n%s\n%s"
		% [
			FateCard.rarity_name(card.card_rarity),
			card.card_name,
			FateCard.type_name(card.card_type),
			card.description
		]
	)
	btn.custom_minimum_size = Vector2(200, 110)
	btn.tooltip_text = card.description

	# 简化版UI显示：emoji + 名称 + 一行说明
	var display_text := ""
	if card.icon_emoji != "":
		display_text += card.icon_emoji + " "
	display_text += card.card_name
	if card.short_description != "":
		display_text += "\n" + card.short_description
	btn.text = display_text
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.12, 0.13, 0.18, 0.95)
	bg_style.set_border_width_all(2)
	bg_style.set_border_color(rarity_color)
	bg_style.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", bg_style)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.2, 0.22, 0.3, 0.95)
	hover_style.set_border_width_all(2)
	hover_style.set_border_color(Color(1.0, 1.0, 1.0, 0.8))
	hover_style.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("hover", hover_style)

	btn.add_theme_color_override("font_color", rarity_color)
	btn.add_theme_font_size_override("font_size", 13)

	btn.pressed.connect(_on_card_selected.bind(card))
	return btn


## 玩家选中了一张卡片
func _on_card_selected(card: FateCard) -> void:
	var result = FateCardGameBridge.apply_card(card)

	if result.success:
		print("[FateCardUI] 应用卡片成功: %s — %s" % [card.card_name, result.message])
		# 通知 UI 显示应用成功
		if _ui_manager != null and _ui_manager.has_method("show_fate_card_notification"):
			_ui_manager.show_fate_card_notification("✓ %s 已应用！" % card.card_name)
	else:
		print("[FateCardUI] 应用卡片失败: %s — %s" % [card.card_name, result.message])
		if _ui_manager != null and _ui_manager.has_method("show_fate_card_notification"):
			_ui_manager.show_fate_card_notification("✗ %s 应用失败" % card.card_name)

	hide_card_selection()


## 获取当前选项（用于调试）
func get_current_options() -> Array[FateCard]:
	return current_options.duplicate()
