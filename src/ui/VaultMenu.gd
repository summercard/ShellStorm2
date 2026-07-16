class_name VaultMenu
extends CanvasLayer

## 保险柜 — 基地建筑界面
## 保险柜中的物品跨局持久化（存储在 BaseManager），死亡不丢失，撤离成功自动转入
## 界面支持：查看已存物品、从背包存入、从保险柜取出

@onready var content: VBoxContainer
@onready var status_label: Label
@onready var close_button: Button

## 保险柜基础容量
const BASE_CAPACITY := 2

func _ready() -> void:
	content = get_node_or_null("Panel/VBox/Content")
	status_label = get_node_or_null("Panel/VBox/StatusLabel")
	close_button = get_node_or_null("Panel/VBox/CloseButton")
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
		# 关闭按钮统一样式
		var close_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.BORDER_NORMAL)
		UIStyleFactory.apply_button_style(close_button, close_styles)
	_build_vault_view()

func _get_vault_capacity() -> int:
	var vault_lvl: int = 0
	if BaseManager != null:
		vault_lvl = BaseManager.get_level(4)  # building type 4 = vault
	return BASE_CAPACITY + vault_lvl

func _get_vault_items() -> Array[Dictionary]:
	if BaseManager != null:
		return BaseManager.get_vault_items()
	return []

func _build_vault_view() -> void:
	if content == null:
		return
	for child in content.get_children():
		child.queue_free()

	var capacity: int = _get_vault_capacity()
	var vault_items: Array[Dictionary] = _get_vault_items()
	var loadout_items: Array[Dictionary] = BaseManager.get_pending_loadout_items() if BaseManager != null else []
	var used: int = vault_items.size()

	var title := Label.new()
	title.text = "保险柜"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	var summary := Label.new()
	summary.text = "保险格: %d / %d （存入的物品跨局保留，死亡不丢失）" % [used, capacity]
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(summary)

	content.add_child(_make_hsep())

	# 已存入物品
	if vault_items.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "当前无存入物品"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(empty_lbl)
	else:
		var hdr := Label.new()
		hdr.text = "—— 已存入物品 ——"
		hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(hdr)
		for i in vault_items.size():
			content.add_child(_make_vault_item_row(i, vault_items[i]))

	content.add_child(_make_hsep())

	if loadout_items.is_empty():
		var loadout_empty := Label.new()
		loadout_empty.text = "下局带入: 无"
		loadout_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(loadout_empty)
	else:
		var loadout_hdr := Label.new()
		loadout_hdr.text = "—— 下局带入 ——"
		loadout_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(loadout_hdr)
		for i in loadout_items.size():
			content.add_child(_make_loadout_item_row(i, loadout_items[i]))

	content.add_child(_make_hsep())

	var vault_hint := Label.new()
	vault_hint.text = "撤离成功会把背包与保险格物品存回这里"
	vault_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(vault_hint)

	content.add_child(_make_hsep())

	var upgrade_lbl := Label.new()
	upgrade_lbl.text = "升级保险柜建筑可增加容量（当前 %d 格）" % capacity
	content.add_child(upgrade_lbl)

func _make_vault_item_row(index: int, item_dict: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 44)
	var hbox := HBoxContainer.new()
	panel.add_child(hbox)

	# 品质边框颜色（根据物品类型推断）
	var item_type: String = item_dict.get("type", "")
	var border_color: Color
	if item_type == "FateCard":
		var rarity_str: String = item_dict.get("rarity", "COMMON")
		var rarity_val: int = FateCard.CardRarity.get(rarity_str, -1)
		if rarity_val >= 0:
			border_color = FateCard.rarity_color(rarity_val as FateCard.CardRarity)
		else:
			border_color = Color.WHITE
	else:
		border_color = UIPalette.item_border_color(item_type)
	panel.add_theme_stylebox_override("panel", _make_rarity_border_style(border_color))

	var name_lbl := Label.new()
	name_lbl.text = item_dict.get("name", "?")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_lbl)

	var count_lbl := Label.new()
	count_lbl.text = "×%d" % item_dict.get("count", 1)
	hbox.add_child(count_lbl)

	var take_btn := Button.new()
	take_btn.text = "带入"
	take_btn.custom_minimum_size = Vector2(80, 32)
	take_btn.pressed.connect(_on_take_pressed.bind(index))
	var take_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.BORDER_FOCUS)
	UIStyleFactory.apply_button_style(take_btn, take_styles)
	hbox.add_child(take_btn)

	return panel

func _make_rarity_border_style(color: Color) -> StyleBoxFlat:
	# 委托给 UIStyleFactory（保留 3px 全边以维持原视觉）
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	style.border_color = color
	style.set_border_width_all(3)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _make_loadout_item_row(index: int, item_dict: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 40)
	var hbox := HBoxContainer.new()
	panel.add_child(hbox)

	var name_lbl := Label.new()
	name_lbl.text = item_dict.get("name", "?")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_lbl)

	var count_lbl := Label.new()
	count_lbl.text = "×%d" % item_dict.get("count", 1)
	hbox.add_child(count_lbl)

	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(80, 32)
	cancel_btn.pressed.connect(_on_cancel_loadout_pressed.bind(index))
	var cancel_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.HP_LOW)
	UIStyleFactory.apply_button_style(cancel_btn, cancel_styles)
	hbox.add_child(cancel_btn)
	return panel

func _make_deposit_row(slot_index: int, slot_data: Dictionary, used: int, capacity: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 44)
	var hbox := HBoxContainer.new()
	panel.add_child(hbox)

	var item: Dictionary = slot_data.get("item", {})
	var name_lbl := Label.new()
	name_lbl.text = "%s ×%d" % [item.get("name", "?"), slot_data.get("count", 1)]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_lbl)

	var deposit_btn := Button.new()
	deposit_btn.custom_minimum_size = Vector2(80, 32)
	var deposit_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.STATUS_OK)
	UIStyleFactory.apply_button_style(deposit_btn, deposit_styles)

	if used >= capacity:
		deposit_btn.disabled = true
		deposit_btn.text = "格满"
	else:
		deposit_btn.text = "存入"
		deposit_btn.pressed.connect(_on_deposit_pressed.bind(slot_index))

	hbox.add_child(deposit_btn)
	return panel

func _make_hsep() -> HSeparator:
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 6)
	return sep

func _on_deposit_pressed(slot_index: int) -> void:
	_update_status("局内背包存入将在撤离结算后处理")

func _on_take_pressed(vault_index: int) -> void:
	var vault_items: Array[Dictionary] = _get_vault_items()
	if vault_index < 0 or vault_index >= vault_items.size():
		_update_status("取出失败")
		return

	if BaseManager.stage_vault_item_for_loadout(vault_index):
		_update_status("已加入下局带入")
		_build_vault_view()
	else:
		_update_status("加入带入失败")

func _on_cancel_loadout_pressed(loadout_index: int) -> void:
	if BaseManager.remove_pending_loadout_item(loadout_index):
		_update_status("已取消带入")
		_build_vault_view()
	else:
		_update_status("取消失败")

func _update_status(msg: String) -> void:
	if status_label:
		status_label.text = msg

func _on_close_pressed() -> void:
	queue_free()
