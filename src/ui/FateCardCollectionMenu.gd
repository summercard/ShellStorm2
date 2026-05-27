class_name FateCardCollectionMenu
extends CanvasLayer

## 命运卡牌收藏室 — 基地建筑界面
## 展示所有已解锁的命运卡片，支持查看详情

@onready var content: VBoxContainer
@onready var close_button: Button
@onready var scroll_container: ScrollContainer
@onready var header_label: Label

func _ready() -> void:
	content = get_node_or_null("Panel/VBox/ScrollContainer/Content")
	close_button = get_node_or_null("Panel/VBox/CloseButton")
	header_label = get_node_or_null("Panel/VBox/HeaderLabel")
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	_build_collection_view()

func _build_collection_view() -> void:
	if content == null:
		return
	for child in content.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "命运卡牌收藏室"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "全部卡牌均已解锁"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8, 1.0))
	content.add_child(subtitle)

	var separator := HSeparator.new()
	content.add_child(separator)

	# 按品质分组展示
	var rarities: Array = [
		FateCard.CardRarity.COMMON,
		FateCard.CardRarity.RARE,
		FateCard.CardRarity.EPIC,
		FateCard.CardRarity.LEGENDARY,
		FateCard.CardRarity.MYSTIC,
	]
	for rarity in rarities:
		var cards := FateCardPresets.by_rarity(rarity)
		if cards.is_empty():
			continue

		var group_label := Label.new()
		group_label.text = "── %s ──" % FateCard.rarity_name(rarity)
		group_label.add_theme_color_override("font_color", FateCard.rarity_color(rarity))
		content.add_child(group_label)

		var grid := GridContainer.new()
		grid.columns = 3
		content.add_child(grid)

		for card in cards:
			var card_ui := _create_card_item(card)
			grid.add_child(card_ui)

	_add_close_hint()

func _create_card_item(card: FateCard) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(180, 100)

	var color := FateCard.rarity_color(card.card_rarity)
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.12, 0.13, 0.18, 0.95)
	normal_style.set_border_width_all(2)
	normal_style.set_border_color(color)
	normal_style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("normal", normal_style)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = card.card_name
	name_lbl.add_theme_color_override("font_color", color)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_lbl)

	var type_lbl := Label.new()
	type_lbl.text = "[%s] %s" % [FateCard.rarity_name(card.card_rarity), FateCard.type_name(card.card_type)]
	type_lbl.add_theme_font_size_override("font_size", 11)
	type_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(type_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = card.short_description
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.custom_minimum_size.y = 36
	vbox.add_child(desc_lbl)

	panel.tooltip_text = card.description
	return panel

func _add_close_hint() -> void:
	var hint := Label.new()
	hint.text = "按 [×] 关闭"
	hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(hint)

func _on_close_pressed() -> void:
	queue_free()