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
	UIStyleFactory.apply_tactical_tree(self)
	# 手柄通路：十字键/摇杆导航与 A 键确认都需要一个「焦点持有者」，
	# 打开菜单时先抓焦点，否则手柄在子界面里没有入口。
	UiMenuFocus.ensure_focus(self)

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

## 图鉴条目：塔罗卡面 + 卡下功能文字。
## 正/逆位解读等详细信息仍保留在 tooltip，不占用卡面。
func _create_card_ui(card: FateCard) -> Control:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)

	var tarot_definition := TarotFateCatalog.get_definition(card.get_stable_card_id())
	column.tooltip_text = "%s\n%s\n正位：%s\n逆位：%s" % [
		FateCard.scope_display_name(card.scope),
		FateCard.scope_target_text(card.scope),
		card.description,
		str(tarot_definition.get("reversed_description", "尚未施工")),
	]

	var art := FateCardView.art_for(card)
	if art != null:
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(CARD_SIZE, CARD_SIZE * 1.56)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.clip_contents = true
		column.add_child(holder)
		FateCardView.build_art_layer(holder, art, card.is_reversed(), "TarotArtFace")
	else:
		# 缺图回退：保留旧的文字卡
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(CARD_SIZE, CARD_SIZE * 1.56)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.1, 0.1, 0.14, 0.97)
		bg.set_border_width_all(2)
		bg.set_border_color(FateCard.rarity_color(card.card_rarity))
		bg.set_corner_radius_all(6)
		panel.add_theme_stylebox_override("normal", bg)
		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		panel.add_child(vbox)
		var name_lbl := Label.new()
		name_lbl.text = card.card_name
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(name_lbl)
		column.add_child(panel)

	column.add_child(FateCardView.build_caption(card, 12, CARD_SIZE))
	return column

func _add_close_hint() -> void:
	var hint := Label.new()
	hint.text = "按 [×] 关闭"
	hint.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(hint)

func _on_close_pressed() -> void:
	queue_free()
