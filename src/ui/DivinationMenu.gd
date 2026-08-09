class_name DivinationMenu
extends CanvasLayer

## 命运占卜屋 — 基地建筑界面
## 玩家可在局间抽卡，选定后该卡会在下一局首次开门时作为保留选项出现
## 通过 FateCardPresets 随机生成选项，通过 FateCardGameBridge 暂存下一局卡片

var card_options_container: HBoxContainer
var instruction_label: Label
var skip_button: Button
var selected_card_label: Label

## 暂存的下一局命运卡片
var pending_card: FateCard = null

## 每局免费抽卡次数
const FREE_DRAWS_PER_RUN := 1


func _ready() -> void:
	card_options_container = get_node_or_null("Panel/VBox/CardOptions")
	instruction_label = get_node_or_null("Panel/VBox/InstructionLabel")
	skip_button = get_node_or_null("Panel/VBox/SkipButton")
	selected_card_label = get_node_or_null("Panel/VBox/SelectedCardLabel")
	if skip_button:
		skip_button.pressed.connect(_on_skip_pressed)
	_selected_card_label_reset()
	_draw_cards()
	UIStyleFactory.apply_tactical_tree(self)


func _draw_cards() -> void:
	if not card_options_container:
		push_warning("DivinationMenu: card_options_container is null, skipping _draw_cards")
		return
	# 清空旧选项
	for child in card_options_container.get_children():
		child.queue_free()
	_pending_card_reset()

	# 从共享塔罗卡池无重复抽取，并为每张牌独立判定正/逆位。
	var options := FateCardPresets.draw_offer(3)

	for choice_index in range(options.size()):
		var card := options[choice_index]
		var btn := _create_card_button(card)
		card_options_container.add_child(btn)
		_play_card_flip(btn, card, choice_index)

	# 更新说明
	if instruction_label:
		instruction_label.text = "选择一张命运预兆，它会保留到下一局首次开门选择"
	UIStyleFactory.apply_tactical_tree(self)


## 创建一张命运卡片按钮
func _create_card_button(card: FateCard) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 150)

	# 品质颜色
	var rarity_color := FateCard.rarity_color(card.card_rarity)
	var rarity_hex: String = (
		"#%02X%02X%02X"
		% [int(rarity_color.r * 255), int(rarity_color.g * 255), int(rarity_color.b * 255)]
	)

	# 卡面先显示天体作用域专名，再显示品质/名称/效果类型。
	var type_str := FateCard.type_name(card.card_type)
	btn.text = (
		"%s\n[%s] %s\n%s %s\n%s"
		% [FateCard.scope_display_name(card.scope), FateCard.rarity_name(card.card_rarity), card.card_name, card.orientation_symbol(), card.orientation_name(), type_str]
	)
	btn.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_theme_color_override("font_color", rarity_color)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_font_size_override("normal", 12)
	btn.set_meta("card", card)
	btn.pressed.connect(_on_card_button_pressed.bind(card))
	btn.set_meta("tarot_face_ready", false)

	# Tooltip
	btn.tooltip_text = "%s\n%s\n%s" % [FateCard.scope_display_name(card.scope), FateCard.scope_target_text(card.scope), card.description]

	# 卡片背景色 — 稀有色边框
	var bg_style := UIStyleFactory.make_panel_with_border(1, rarity_color, 6, 2)
	bg_style.bg_color = UIPalette.BG_DARK
	btn.add_theme_stylebox_override("normal", bg_style)

	var hover_style := UIStyleFactory.make_panel_with_border(2, Color(1.0, 1.0, 1.0, 0.8), 6, 2)
	hover_style.bg_color = UIPalette.BG_MID
	btn.add_theme_stylebox_override("hover", hover_style)

	return btn


func _play_card_flip(button: Button, card: FateCard, choice_index: int) -> void:
	var face_text := button.text
	button.disabled = true
	button.text = "✦\n命运塔罗\nFATE"
	button.pivot_offset = button.size * 0.5
	var tween := button.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		button.modulate.a = 0.0
		button.text = face_text
		button.rotation = PI if card.is_reversed() else 0.0
		tween.tween_property(button, "modulate:a", 1.0, 0.15)
	else:
		tween.tween_interval(0.10 + float(choice_index) * 0.08)
		tween.tween_property(button, "scale:x", 0.04, 0.14)
		tween.tween_callback(func() -> void:
			button.text = face_text
			button.rotation = PI if card.is_reversed() else 0.0
		)
		tween.tween_property(button, "scale:x", 1.0, 0.18)
	tween.tween_callback(func() -> void:
		button.disabled = false
		button.set_meta("tarot_face_ready", true)
		button.set_meta("tarot_face_rotation", button.rotation)
	)


## 选中了一张卡片
func _on_card_button_pressed(card: FateCard) -> void:
	pending_card = card
	_update_selected_label(card)

	# 持久化到 BaseManager（下一局自动加载）
	BaseManager.set_pending_fate_card(
		{
			"card_id": card.card_id,
			"stable_card_id": card.get_stable_card_id(),
			"card_name": card.card_name,
			"legacy_card_name": card.legacy_card_name,
			"orientation": card.orientation,
			"orientation_roll": card.orientation_roll,
			"card_type": card.card_type,
			"card_rarity": card.card_rarity,
			"description": card.description,
			"tags": card.tags,
			"effect": card.effect,
			"visual": card.visual
		}
	)

	# 视觉反馈：卡片确认提示
	if instruction_label:
		instruction_label.text = "已保留 [%s]，它会出现在首次开门的选择中".format([card.card_name])


## 更新已选择标签
func _update_selected_label(card: FateCard) -> void:
	if selected_card_label == null:
		return
	var color := FateCard.rarity_color(card.card_rarity)
	var hex: String = "#%02X%02X%02X" % [int(color.r * 255), int(color.g * 255), int(color.b * 255)]
	selected_card_label.text = (
		"已选: [%s] %s · %s" % [FateCard.rarity_name(card.card_rarity), card.card_name, card.orientation_name()]
	)
	selected_card_label.add_theme_color_override("font_color", color)
	selected_card_label.visible = true


func _selected_card_label_reset() -> void:
	if selected_card_label:
		selected_card_label.text = ""
		selected_card_label.visible = false


func _pending_card_reset() -> void:
	pending_card = null


## 跳过（不选）
func _on_skip_pressed() -> void:
	_pending_card_reset()
	if instruction_label:
		instruction_label.text = "已跳过抽卡。祝你好运。"
	await get_tree().create_timer(1.0).timeout
	_close()


## 关闭界面（返回基地）
func _close() -> void:
	queue_free()


## 获取暂存的命运卡片（供 BaseMenu 开始游戏时传递到 Dungeon3D）。
func get_pending_card() -> FateCard:
	return pending_card
