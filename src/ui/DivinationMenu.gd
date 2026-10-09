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
	# 默认焦点落在「跳过」上：打开即按 A 不该直接定下命运卡。
	UiMenuFocus.ensure_focus(self)


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
		var card_view := _create_card_view(card)
		card_options_container.add_child(card_view)
		var btn := card_view.get_meta("tarot_button") as Button
		if btn != null:
			_play_card_flip(btn, card, choice_index)

	# 更新说明
	if instruction_label:
		instruction_label.text = "选择一张命运预兆，它会保留到下一局首次开门选择"
	UIStyleFactory.apply_tactical_tree(self)


## 创建一张命运卡视图：塔罗卡面贴图 + 卡下功能文字。
## 返回「卡片列」容器；可聚焦按钮在 meta `tarot_button` 上。
func _create_card_view(card: FateCard) -> Control:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(232, 362)
	btn.text = ""
	btn.clip_contents = true
	btn.focus_mode = Control.FOCUS_ALL
	btn.tooltip_text = "%s\n%s\n%s" % [FateCard.scope_display_name(card.scope), FateCard.scope_target_text(card.scope), card.description]
	btn.set_meta("card", card)
	btn.set_meta("tarot_button", btn)
	btn.set_meta("tarot_face_ready", false)
	# 卡身份：供验收把卡面贴图与被抽中的卡牌逐一对上，防止"图装错牌"。
	btn.set_meta("tarot_stable_card_id", card.get_stable_card_id())
	btn.pressed.connect(_on_card_button_pressed.bind(card))

	# 卡面自带描边，按钮只保留悬停高亮
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.07)
	hover.set_corner_radius_all(10)
	hover.set_border_width_all(2)
	hover.border_color = Color(1.0, 1.0, 1.0, 0.55)
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	column.add_child(btn)

	var art := FateCardView.art_for(card)
	btn.set_meta("tarot_art_mode", art != null)
	if art != null:
		var back_node: Control = null
		if FateCardView.back_texture() != null:
			back_node = FateCardView.build_back_layer(btn)
		var face := FateCardView.build_art_layer(btn, art, card.is_reversed(), "TarotArtFace")
		if face != null:
			face.visible = false
		btn.set_meta("tarot_face_node", face)
		btn.set_meta("tarot_back_node", back_node)
	else:
		# 缺图回退：沿用旧的文字卡面
		btn.text = (
			"%s\n[%s] %s\n%s %s\n%s"
			% [
				FateCard.scope_display_name(card.scope),
				FateCard.rarity_name(card.card_rarity), card.card_name,
				card.orientation_symbol(), card.orientation_name(),
				FateCard.type_name(card.card_type),
			]
		)
		btn.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_color_override("font_color", FateCard.rarity_color(card.card_rarity))
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_font_size_override("normal", 12)
		var fallback_bg := UIStyleFactory.make_panel_with_border(1, FateCard.rarity_color(card.card_rarity), 6, 2)
		fallback_bg.bg_color = UIPalette.BG_DARK
		btn.add_theme_stylebox_override("normal", fallback_bg)

	column.add_child(FateCardView.build_caption(card, 13, 232))
	# 调用方拿到的是「列」而不是按钮，故在列上也挂一份，避免从列上取不到按钮。
	column.set_meta("tarot_button", btn)
	return column


func _play_card_flip(button: Button, card: FateCard, choice_index: int) -> void:
	var art_mode := bool(button.get_meta("tarot_art_mode", false))
	# 注意：不能用 get_meta(key, null) 取默认——Godot 在默认值本身为 null 时仍会打错误日志。
	var face: Control = (button.get_meta("tarot_face_node") if button.has_meta("tarot_face_node") else null) as Control
	var back: Control = (button.get_meta("tarot_back_node") if button.has_meta("tarot_back_node") else null) as Control
	if not art_mode:
		face = UIStyleFactory.make_tarot_button_text(button)
		button.set_meta("tarot_face_node", face)
	button.disabled = true
	if not art_mode:
		button.text = "✦\n命运塔罗\nFATE"
	button.pivot_offset = button.size * 0.5
	var tween := button.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		button.modulate.a = 0.0
		if not art_mode:
			button.text = ""
			face.visible = true
			UIStyleFactory.apply_tarot_orientation(button, face, card.is_reversed())
		else:
			FateCardView.reveal(face, back, card.is_reversed())
		tween.tween_property(button, "modulate:a", 1.0, 0.15)
	else:
		tween.tween_interval(0.10 + float(choice_index) * 0.08)
		tween.tween_property(button, "scale:x", 0.04, 0.14)
		tween.tween_callback(func() -> void:
			if not art_mode:
				button.text = ""
				face.visible = true
				UIStyleFactory.apply_tarot_orientation(button, face, card.is_reversed())
			else:
				FateCardView.reveal(face, back, card.is_reversed())
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
		instruction_label.text = "已保留 [%s]，它会出现在首次开门的选择中" % card.card_name
		if FateCardGameBridge.requires_source_selection(card):
			instruction_label.text += "；届时通过统一来源面板选择真实已装备来源快照，不消耗来源物品"


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
