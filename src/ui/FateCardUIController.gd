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
var _pending_currency_card_id := ""
const FATE_CURRENCY_BY_RARITY := [20, 40, 70, 120, 180]

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
	_pending_currency_card_id = ""
	if card_container != null:
		for child in card_container.get_children():
			child.queue_free()

	# 从共享塔罗卡池无重复抽取3张，并独立判定正/逆位。
	current_options = FateCardPresets.draw_offer(3)

	# 创建卡片按钮
	if card_container != null:
		for choice_index in range(current_options.size()):
			var card := current_options[choice_index]
			var btn = _create_card_button(card)
			card_container.add_child(btn)
			_play_tarot_flip(btn, card, choice_index)

	# 更新提示文字
	if instruction_label != null:
		instruction_label.text = "选择一张命运卡片（Esc / Tab关闭）"

	if card_panel != null:
		card_panel.show()
	is_visible = true
	Global.acquire_pause("fate_card")


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible:
		return
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo and (
		key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE
	):
		hide_card_selection()
		get_viewport().set_input_as_handled()


## 隐藏卡片选择界面
func hide_card_selection() -> void:
	if card_panel != null:
		card_panel.hide()
	is_visible = false
	_pending_currency_card_id = ""
	Global.release_pause("fate_card")
	if _ui_manager != null:
		var room_mode = _ui_manager.get("_room_game_mode")
		if room_mode != null and room_mode.has_method("_on_fate_card_controller_hidden"):
			room_mode.call("_on_fate_card_controller_hidden")


## 创建一张卡片按钮
func _create_card_button(card: FateCard) -> Button:
	var btn := Button.new()
	var bridge := get_node_or_null("/root/FateCardGameBridge")
	var target_summary: Dictionary = {}
	if bridge != null and bridge.has_method("get_target_summary"):
		target_summary = bridge.get_target_summary(card)

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

	# 卡面必须在选择前说明作用域、所有者、是否占槽和不可逆结果。
	var display_text := ""
	if card.icon_emoji != "":
		display_text += card.icon_emoji + " "
	display_text += card.card_name
	display_text += "\n%s %s" % [card.orientation_symbol(), card.orientation_name()]
	if card.short_description != "":
		display_text += "\n" + card.short_description
	display_text += "\n%s" % FateCard.scope_display_name(card.scope)
	if card.scope == FateCard.Scope.WEAPON:
		var used := int(target_summary.get("fate_slot_used", 0))
		var capacity := int(target_summary.get("fate_slot_capacity", 0))
		display_text += "  永久槽 %d/%d → %02d" % [used, capacity, used + 1]
		display_text += "\n目标：%s #%s｜不可逆" % [
			target_summary.get("display_name", "当前枪械"),
			target_summary.get("instance_suffix", "------"),
		]
		if used >= capacity:
			display_text += "\n命运槽已满 · 再次点击兑魂%d" % int(FATE_CURRENCY_BY_RARITY[clampi(int(card.card_rarity), 0, FATE_CURRENCY_BY_RARITY.size() - 1)])
			btn.tooltip_text = "首次点击确认，第二次点击同一卡片转换为货币"
	elif card.scope == FateCard.Scope.CHARACTER:
		display_text += "  本局角色｜不占武器槽"
	else:
		display_text += "  世界规则｜不占武器槽"
	btn.text = display_text
	var bg_style := UIStyleFactory.make_panel_with_border(1, rarity_color, 6, 2)
	bg_style.bg_color = UIPalette.BG_DARK
	btn.add_theme_stylebox_override("normal", bg_style)

	var hover_style := UIStyleFactory.make_panel_with_border(2, Color(1.0, 1.0, 1.0, 0.8), 6, 2)
	hover_style.bg_color = UIPalette.BG_MID
	btn.add_theme_stylebox_override("hover", hover_style)

	btn.add_theme_color_override("font_color", FateCard.scope_color(card.scope))
	btn.add_theme_font_size_override("font_size", 13)

	btn.pressed.connect(_on_card_selected.bind(card))
	btn.set_meta("tarot_face_ready", false)
	return btn


func _play_tarot_flip(button: Button, card: FateCard, choice_index: int) -> void:
	if button == null:
		return
	var face_text := button.text
	button.disabled = true
	button.text = "✦\n命运塔罗\nFATE"
	button.scale = Vector2.ONE
	button.pivot_offset = button.size * 0.5
	var reduce_motion := bool(ProjectSettings.get_setting("accessibility/reduce_motion", false))
	var tween := button.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if reduce_motion:
		button.modulate.a = 0.0
		button.text = face_text
		button.rotation = PI if card.is_reversed() else 0.0
		tween.tween_property(button, "modulate:a", 1.0, 0.15)
	else:
		tween.tween_interval(0.10 + float(choice_index) * 0.08)
		tween.tween_property(button, "scale:x", 0.04, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(func() -> void:
			button.text = face_text
			button.rotation = PI if card.is_reversed() else 0.0
		)
		tween.tween_property(button, "scale:x", 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_finish_tarot_flip.bind(button, card))


func _finish_tarot_flip(button: Button, card: FateCard) -> void:
	if button == null or not is_instance_valid(button):
		return
	button.disabled = false
	button.set_meta("tarot_face_ready", true)
	button.set_meta("tarot_orientation", card.orientation_name())
	button.set_meta("tarot_face_rotation", button.rotation)


## 玩家选中了一张卡片
func _on_card_selected(card: FateCard) -> void:
	if card.scope == FateCard.Scope.WEAPON:
		var target := FateCardGameBridge.get_target_summary(card)
		var capacity := int(target.get("fate_slot_capacity", 0))
		if capacity > 0 and int(target.get("fate_slot_used", 0)) >= capacity:
			var stable_id := card.get_stable_card_id()
			var value := int(FATE_CURRENCY_BY_RARITY[clampi(int(card.card_rarity), 0, FATE_CURRENCY_BY_RARITY.size() - 1)])
			if _pending_currency_card_id != stable_id:
				_pending_currency_card_id = stable_id
				if instruction_label != null:
					instruction_label.text = "再次点击%s，转换为%d魂；Esc取消" % [card.card_name, value]
				return
			GameManager.add_currency(value)
			if _ui_manager != null and _ui_manager.has_method("show_fate_card_notification"):
				_ui_manager.show_fate_card_notification("命运转化：%s → %d魂" % [card.card_name, value])
			hide_card_selection()
			return
	_pending_currency_card_id = ""
	var result = FateCardGameBridge.apply_card(card)

	if result.success:
		print("[FateCardUI] 应用卡片成功: %s — %s" % [card.card_name, result.message])
		# 通知 UI 显示应用成功
		if _ui_manager != null and _ui_manager.has_method("show_fate_card_notification"):
			var detail := "✓ %s · %s 已应用" % [FateCard.scope_display_name(card.scope), card.card_name]
			if result.has("slot_index"):
				detail += " · 永久槽 %02d/%d" % [
					result.get("slot_index", 0), result.get("slot_capacity", 0),
				]
			_ui_manager.show_fate_card_notification(detail)
		hide_card_selection()
	else:
		print("[FateCardUI] 应用卡片失败: %s — %s" % [card.card_name, result.message])
		if _ui_manager != null and _ui_manager.has_method("show_fate_card_notification"):
			_ui_manager.show_fate_card_notification("✗ %s：%s" % [
				card.card_name, result.get("message", "应用失败"),
			])
		if instruction_label != null:
			instruction_label.text = "未应用：%s｜请选择其他卡或关闭" % result.get(
				"message", "未知原因"
			)


## 获取当前选项（用于调试）
func get_current_options() -> Array[FateCard]:
	return current_options.duplicate()
