class_name TrainingFateBenchPanel
extends CanvasLayer
## 靶场命运卡组装台面板（测试用）。
##
## 与基地工作台的区别只有一个：**卡池是全量的**。基地走 FateCardPresets.draw_offer(3)
## 随机三选一，这里直接摊开 FateCardPresets.playable_presets() 让测试者想装哪张装哪张。
## 卡牌本来就不存在「是否拥有」的存档门槛（收藏室也是枚举全部预设），所以这里
## 不需要绕开任何解锁数据。
##
## 装配链路与工作台完全一致：FateCardGameBridge.apply_card_with_source_selection()
## → WeaponInstance.fate_upgrades（命运槽默认 8 格）。这条链不写 BaseManager，
## 因此靶场里装的卡随场景释放，不会污染存档。
##
## 前置条件：必须先装备一把武器。没有武器时 WEAPON 卡会返回「当前没有装备枪械」，
## 面板会直接把这句话显示出来，而不是静默失败。

signal closed

const CARD_WIDTH := 168.0
const CARD_HEIGHT := 232.0
const CARDS_PER_ROW := 6
const PAUSE_REASON := "training_fate_bench"

var _player: Player3D = null
var _grid: GridContainer = null
var _status_label: Label = null
var _loadout_label: Label = null
var _busy := false


func set_player(player: Player3D) -> void:
	_player = player


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 60
	_build_ui()
	if _player != null and is_instance_valid(_player):
		_player.set_input_locked(true)
	if Global != null:
		Global.acquire_pause(PAUSE_REASON)
	_refresh()


func _exit_tree() -> void:
	if Global != null:
		Global.release_pause(PAUSE_REASON)
	if _player != null and is_instance_valid(_player):
		_player.set_input_locked(false)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.04, 0.05, 0.07, 0.94)
	add_child(background)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -566.0
	panel.offset_top = -340.0
	panel.offset_right = 566.0
	panel.offset_bottom = 340.0
	add_child(panel)
	var column := VBoxContainer.new()
	column.name = "VBox"
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var title := Label.new()
	title.name = "Title"
	title.text = "命运卡组装台 · 测试模式"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.80, 0.56, 0.96))
	column.add_child(title)
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "全部卡牌直接可用，不限次数；装配结果只写在本次测试的武器上，离开靶场即丢弃，不会进入存档。"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.72, 0.78, 0.84))
	column.add_child(hint)
	_loadout_label = Label.new()
	_loadout_label.name = "LoadoutLabel"
	_loadout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loadout_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loadout_label.add_theme_font_size_override("font_size", 15)
	_loadout_label.add_theme_color_override("font_color", Color(0.94, 0.78, 0.42))
	column.add_child(_loadout_label)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_grid = GridContainer.new()
	_grid.name = "CardGrid"
	_grid.columns = CARDS_PER_ROW
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_color_override("font_color", Color(0.66, 0.86, 0.94))
	column.add_child(_status_label)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "关闭组装台  [Esc]"
	close_button.custom_minimum_size = Vector2(0, 42)
	close_button.pressed.connect(_close)
	column.add_child(close_button)


func _refresh() -> void:
	for child in _grid.get_children():
		child.queue_free()
	for card in FateCardPresets.playable_presets():
		_grid.add_child(_create_card_entry(card))
	_refresh_loadout()


func _create_card_entry(card: FateCard) -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var button := Button.new()
	button.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	button.flat = true
	button.tooltip_text = "%s\n%s\n%s" % [
		FateCard.scope_display_name(card.scope),
		FateCard.scope_target_text(card.scope),
		card.description,
	]
	button.pressed.connect(_on_card_pressed.bind(card))
	column.add_child(button)
	var art := FateCardView.art_for(card)
	if art != null:
		FateCardView.build_art_layer(button, art, card.is_reversed(), "TarotArtFace")
	else:
		# 缺图回退：不依赖任何美术资源也要能用，否则新卡一进来面板就空一格。
		var fallback := ColorRect.new()
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fallback.color = FateCard.rarity_color(card.card_rarity).darkened(0.62)
		button.add_child(fallback)
		var fallback_label := Label.new()
		fallback_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		fallback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fallback_label.text = card.card_name
		fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fallback_label.add_theme_font_size_override("font_size", 16)
		button.add_child(fallback_label)
	var name_label := Label.new()
	name_label.text = card.card_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", FateCard.rarity_color(card.card_rarity))
	column.add_child(name_label)
	column.add_child(FateCardView.build_caption(card, 11, CARD_WIDTH - 6))
	return column


func _on_card_pressed(card: FateCard) -> void:
	if _busy:
		return
	_busy = true
	_status_label.text = "正在装配 %s ……" % card.card_name
	var result: Dictionary = await FateCardGameBridge.apply_card_with_source_selection(card, self)
	if not is_inside_tree():
		return
	_busy = false
	_status_label.text = str(result.get("message", "已完成"))
	_refresh_loadout()


func _refresh_loadout() -> void:
	if _loadout_label == null:
		return
	if _player == null or not is_instance_valid(_player):
		_loadout_label.text = "未检测到玩家"
		return
	var snapshot := _player.get_weapon_presentation_snapshot()
	if snapshot.is_empty():
		_loadout_label.text = "当前没有装备武器 —— 命运卡要挂在武器上才生效，请先到军械库取一把枪和弹药。"
		return
	var title := str(snapshot.get("display_name", snapshot.get("gun_id", "已装备武器")))
	_loadout_label.text = "当前武器：%s ｜ 命运槽 %d / %d" % [
		title,
		int(snapshot.get("fate_slot_used", 0)),
		int(snapshot.get("fate_slot_capacity", 0)),
	]


func _close() -> void:
	closed.emit()
	queue_free()
