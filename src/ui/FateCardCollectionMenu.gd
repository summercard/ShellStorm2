class_name FateCardCollectionMenu
extends CanvasLayer

## 命运卡牌收藏室 — 基地建筑界面
## 展示所有已解锁的命运卡片，使用游戏内卡牌样式

@onready var content: VBoxContainer
@onready var close_button: Button
@onready var scroll_container: ScrollContainer
@onready var header_label: Label

const CARD_SIZE := 150.0
const CARDS_PER_ROW := 5

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
	title.add_theme_font_size_override("font_size", 22)
	content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "命运塔罗图鉴 · 48张可玩 / 78张设计"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	content.add_child(subtitle)

	var separator := HSeparator.new()
	content.add_child(separator)

	# 按品质分组
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
		group_label.add_theme_font_size_override("font_size", 14)
		content.add_child(group_label)

		var grid := GridContainer.new()
		grid.columns = CARDS_PER_ROW
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 16)
		content.add_child(grid)

		for card in cards:
			var card_ui := _create_card_ui(card)
			grid.add_child(card_ui)

	_add_close_hint()

func _create_card_ui(card: FateCard) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CARD_SIZE, CARD_SIZE)

	var rarity_clr := FateCard.rarity_color(card.card_rarity)

	# 背景
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.14, 0.97)
	bg.set_border_width_all(2)
	bg.set_border_color(rarity_clr)
	bg.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("normal", bg)

	# 悬停高亮
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.15, 0.15, 0.2, 0.97)
	hover.set_border_width_all(2)
	hover.set_border_color(Color(1.0, 1.0, 1.0, 0.6))
	hover.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("hover", hover)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.add_theme_constant_override("margin_left", 8)
	vbox.add_theme_constant_override("margin_right", 8)
	vbox.add_theme_constant_override("margin_top", 6)
	vbox.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(vbox)

	# 顶部：emoji + 品质角标
	var top_hbox := HBoxContainer.new()
	top_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(top_hbox)

	var emoji_lbl := Label.new()
	emoji_lbl.text = card.icon_emoji
	emoji_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emoji_lbl.add_theme_font_size_override("font_size", 28)
	top_hbox.add_child(emoji_lbl)

	var type_lbl := Label.new()
	type_lbl.text = FateCard.type_name(card.card_type)
	type_lbl.add_theme_color_override("font_color", rarity_clr)
	type_lbl.add_theme_font_size_override("font_size", 10)
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_hbox.add_child(type_lbl)

	# 卡牌名称
	var name_lbl := Label.new()
	name_lbl.text = card.card_name
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.custom_minimum_size.y = 32
	vbox.add_child(name_lbl)

	var scope_lbl := Label.new()
	scope_lbl.text = FateCard.scope_display_name(card.scope)
	scope_lbl.add_theme_color_override("font_color", FateCard.scope_color(card.scope))
	scope_lbl.add_theme_font_size_override("font_size", 10)
	scope_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(scope_lbl)

	# 分隔线
	var divider := HSeparator.new()
	divider.add_theme_constant_override("custom_minimum_size", 0)
	divider.add_theme_color_override("line_color", Color(1, 1, 1, 0.1))
	vbox.add_child(divider)

	# 图鉴同时展示同一张牌的正位与逆位，不把逆位拆成第二张收藏卡。
	var desc_lbl := Label.new()
	var tarot_definition := TarotFateCatalog.get_definition(card.get_stable_card_id())
	desc_lbl.text = "正位｜%s\n逆位｜%s" % [
		card.short_description,
		str(tarot_definition.get("reversed_short", "尚未施工")),
	]
	desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.custom_minimum_size.y = 48
	vbox.add_child(desc_lbl)

	# 底部品质角标
	var rarity_badge := Label.new()
	rarity_badge.text = "◆ %s" % FateCard.rarity_name(card.card_rarity)
	rarity_badge.add_theme_color_override("font_color", rarity_clr)
	rarity_badge.add_theme_font_size_override("font_size", 10)
	rarity_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(rarity_badge)

	panel.tooltip_text = "%s\n%s\n正位：%s\n逆位：%s" % [FateCard.scope_display_name(card.scope), FateCard.scope_target_text(card.scope), card.description, str(tarot_definition.get("reversed_description", "尚未施工"))]
	return panel

func _add_close_hint() -> void:
	var hint := Label.new()
	hint.text = "按 [×] 关闭"
	hint.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(hint)

func _on_close_pressed() -> void:
	queue_free()
