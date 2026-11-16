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
var _board: Control
var _confirm: Control
var _panel: PanelContainer
var _board_wrapper: Control
var _opening := true
var _closing := false
var _input_was_locked := false
const HOLOGRAM := preload("res://src/ui/weapon_build/WeaponHologramTransition.gd")


func set_player(player: Player3D) -> void:
	_player = player
	if is_instance_valid(_board):
		_board.call("set_weapon_owner", player)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_meta("ui_prism_exempt", true)
	layer = 60
	_build_ui()
	if _player != null and is_instance_valid(_player):
		_input_was_locked = _player.input_locked
		_player.set_input_locked(true)
		FateCardGameBridge.set_player(_player)
	if Global != null:
		Global.acquire_pause(PAUSE_REASON)
	_refresh()
	_play_intro()


func _exit_tree() -> void:
	if Global != null:
		Global.release_pause(PAUSE_REASON)
	if _player != null and is_instance_valid(_player):
		var host := _player.get_parent()
		while host != null:
			if host.has_method("refresh_player_input_lock"):
				host.call_deferred("refresh_player_input_lock")
				return
			host = host.get_parent()
		_player.set_input_locked(_input_was_locked or (Global != null and Global.is_paused))


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
	_panel = panel
	panel.name = "Panel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 24
	panel.offset_top = 12
	panel.offset_right = -24
	panel.offset_bottom = -12
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
	_board = (load("res://assets/art/ui/weapon_build/weapon_build_board.tscn") as PackedScene).instantiate() as Control
	_board.name = "WeaponBuildBoard"
	_board_wrapper = Control.new()
	_board_wrapper.name = "WeaponBoardWrapper"
	_board_wrapper.custom_minimum_size = Vector2(0, 300)
	_board_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_board_wrapper)
	_board_wrapper.add_child(_board)
	_board_wrapper.resized.connect(_layout_board)
	_board.call("set_compact", true)
	_board.call("set_weapon_owner", _player)
	get_viewport().size_changed.connect(_layout_bench)
	_layout_bench()
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


func _layout_board() -> void:
	_board.size = _board_wrapper.size
	if not _opening and not _closing:
		_board.position = Vector2.ZERO


func _center_board_position() -> Vector2:
	return get_viewport().get_visible_rect().get_center() - _board_wrapper.global_position - _board.size * 0.5


func _move_board(target: Vector2) -> void:
	if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)):
		_board.position = target
		return
	var tween := _board.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_board, "position", target, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


func _play_intro() -> void:
	_grid.hide()
	_board.hide()
	await get_tree().process_frame
	_layout_board()
	_board.position = _center_board_position()
	await HOLOGRAM.open(_board, _player).finished
	await _move_board(Vector2.ZERO)
	_opening = false
	if not _closing:
		_grid.show()


func _layout_bench() -> void:
	if not is_instance_valid(_grid):
		return
	var width := get_viewport().get_visible_rect().size.x - 72
	_grid.columns = maxi(1, mini(CARDS_PER_ROW, int(width / (CARD_WIDTH + 12))))


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
	button.pressed.connect(_on_card_pressed.bind(card, button))
	column.add_child(button)
	var art := FateCardView.art_for(card)
	var face: Control
	if art != null:
		face = FateCardView.build_art_layer(button, art, card.is_reversed(), "TarotArtFace")
	else:
		# 缺图回退：不依赖任何美术资源也要能用，否则新卡一进来面板就空一格。
		var fallback := ColorRect.new()
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fallback.color = FateCard.rarity_color(card.card_rarity).darkened(0.62)
		button.add_child(fallback)
		face = fallback
		var fallback_label := Label.new()
		fallback_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		fallback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fallback_label.text = card.card_name
		fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fallback_label.add_theme_font_size_override("font_size", 16)
		button.add_child(fallback_label)
	FateCardView.build_scope_badge(button, card.scope, face)
	var name_label := Label.new()
	name_label.text = card.card_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", FateCard.rarity_color(card.card_rarity))
	column.add_child(name_label)
	column.add_child(FateCardView.build_caption(card, 11, CARD_WIDTH - 6, "", false))
	return column


func _on_card_pressed(card: FateCard, button: Button = null) -> void:
	if _busy or _opening or _closing:
		return
	_busy = true
	var target_id := str(FateCardGameBridge.get_target_summary(card).get("weapon_instance_id", ""))
	if card.scope == FateCard.Scope.WEAPON:
		_confirm = load("res://src/ui/weapon_build/FateIrreversibleConfirm.gd").new() as Control
		_confirm.set("message", "装配后该枪械命运卡不可更换！")
		_confirm.set("weapon_instance_id", target_id)
		_panel.add_child(_confirm)
		var accepted: bool = await Signal(_confirm, "completed")
		_confirm = null
		if not accepted:
			_busy = false
			return
		if target_id != str(FateCardGameBridge.get_target_summary(card).get("weapon_instance_id", "")):
			_status_label.text = "目标枪已改变，请重新选择；未装配"
			_busy = false
			return
	_status_label.text = "正在装配 %s ……" % card.card_name
	var from_rect := button.get_global_rect() if is_instance_valid(button) else Rect2()
	if card.occupies_weapon_slot():
		_board.call("refresh_from_owner")
		_board.call("set_pending_install", int(FateCardGameBridge.get_target_summary(card).get("fate_slot_used", 0)) + 1)
	var result: Dictionary = await FateCardGameBridge.apply_card_with_source_selection(card, self)
	if not is_inside_tree():
		return
	_status_label.text = str(result.get("message", "已完成"))
	_refresh_loadout()
	if bool(result.get("success", false)):
		if is_instance_valid(button):
			button.modulate.a = 0.0
		if card.occupies_weapon_slot():
			await _board.call("play_card_install", card, int(result.get("slot_index", 0)), from_rect)
		else:
			await _board.call("play_scope_feedback", card)
		if is_instance_valid(button):
			button.modulate.a = 1.0
	else:
		_board.call("clear_pending_install")
	_busy = false


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
	if is_instance_valid(_confirm):
		_confirm.call("cancel")
		return
	if _busy or _closing:
		return
	_closing = true
	while _opening:
		await get_tree().process_frame
	_grid.hide()
	await _move_board(_center_board_position())
	await HOLOGRAM.close(_board, _player).finished
	closed.emit()
	queue_free()
