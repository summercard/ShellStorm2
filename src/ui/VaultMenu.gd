class_name VaultMenu
extends CanvasLayer
## 格子化基地仓储：左侧长期保险柜，右侧12格随身背包（下局带入）。

const STORAGE_SLOT := preload("res://src/ui/BaseStorageSlot.gd")

var _inventory_module: InventoryModule

@onready var content: VBoxContainer = $Panel/VBox/Content
@onready var status_label: Label = $Panel/VBox/StatusLabel
@onready var close_button: Button = $Panel/VBox/CloseButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	$Background.color = Color(0.008, 0.014, 0.020, 0.50)
	$Panel.add_theme_stylebox_override("panel", _column_style())
	$Panel/VBox/TitleLabel.add_theme_font_size_override("font_size", 24)
	$Panel/VBox/TitleLabel.add_theme_color_override("font_color", Color(0.46, 0.94, 1.0))
	close_button.pressed.connect(_on_close_pressed)
	var styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.BORDER_NORMAL)
	UIStyleFactory.apply_button_style(close_button, styles)
	_build_vault_view()
	UIStyleFactory.apply_tactical_tree(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		queue_free()


func set_inventory_module(module: InventoryModule) -> void:
	_inventory_module = module
	if is_node_ready():
		_build_vault_view()


func _build_vault_view() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	var vault_items := BaseManager.get_vault_items()
	var backpack_items := _get_backpack_slot_items()
	var backpack_capacity := _inventory_module.get_capacity() if _inventory_module != null else BaseManager.get_pending_loadout_capacity()
	var backpack_used := _inventory_module.get_used_slots() if _inventory_module != null else BaseManager.get_pending_loadout_items().size()
	var backpack_owner := "inventory" if _inventory_module != null else "loadout"
	var backpack_title := "当前背包（与I键一致）" if _inventory_module != null else "随身背包（下局带入）"
	var backpack_hint := "即时同步I键背包 · 容量随装备背包变化" if _inventory_module != null else "开局进入局内背包 · 固定12格"
	var guide := Label.new()
	guide.text = "单击物品自动移到另一侧；也可拖拽物品到另一栏任意格。右侧内容与I键背包使用同一数据源。" if _inventory_module != null else "单击或拖拽可准备下局带入物品；进入行动后将转为I键背包。"
	guide.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	guide.add_theme_color_override("font_color", Color(0.60, 0.82, 0.88))
	content.add_child(guide)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	content.add_child(columns)
	columns.add_child(_make_storage_column(
		"长期保险柜", "跨局保存 · 基础20格 · 不自动带入", "vault", _compact_to_slots(vault_items, BaseManager.get_vault_capacity()), vault_items.size(), BaseManager.get_vault_capacity(), 4
	))
	var arrow := Label.new()
	arrow.text = "⇄"
	arrow.custom_minimum_size.x = 44
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.add_theme_font_size_override("font_size", 30)
	arrow.add_theme_color_override("font_color", Color(0.28, 0.84, 0.94))
	columns.add_child(arrow)
	columns.add_child(_make_storage_column(
		backpack_title, backpack_hint, backpack_owner, backpack_items, backpack_used, backpack_capacity, 4
	))
	status_label.text = "当前：保险柜 %d/%d ｜ %s %d/%d" % [
		vault_items.size(), BaseManager.get_vault_capacity(),
		"当前背包" if _inventory_module != null else "下局带入", backpack_used, backpack_capacity,
	]
	UIStyleFactory.apply_tactical_tree(self)


func _make_storage_column(title_text: String, hint_text: String, owner: String, items: Array[Dictionary], used: int, capacity: int, columns_count: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _column_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := Label.new()
	title.text = "%s   %d / %d" % [title_text, used, capacity]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.42, 0.92, 1.0))
	box.add_child(title)
	var hint := Label.new()
	hint.text = hint_text
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.44, 0.64, 0.69))
	box.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = columns_count
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	for index in capacity:
		var slot := STORAGE_SLOT.new() as BaseStorageSlot
		var slot_item: Dictionary = items[index] if index < items.size() else {}
		slot.configure(owner, index if not slot_item.is_empty() else -1, slot_item, index)
		slot.item_clicked.connect(_on_slot_clicked)
		slot.item_drop_requested.connect(_on_item_drop_requested)
		grid.add_child(slot)
	return panel


func _on_slot_clicked(owner: String, source_index: int) -> void:
	var target := ("inventory" if _inventory_module != null else "loadout") if owner == "vault" else "vault"
	_transfer(owner, source_index, target, "点击")


func _on_item_drop_requested(source_owner: String, source_index: int, target_owner: String) -> void:
	_transfer(source_owner, source_index, target_owner, "拖拽")


func _transfer(source_owner: String, source_index: int, target_owner: String, method: String) -> void:
	var result: Dictionary
	if _inventory_module != null and (source_owner == "inventory" or target_owner == "inventory"):
		result = BaseManager.transfer_runtime_inventory_item(source_owner, source_index, _inventory_module)
	else:
		result = BaseManager.transfer_base_storage_item(source_owner, source_index, target_owner)
	if not bool(result.get("success", false)):
		status_label.text = "%s转移失败：%s" % [method, str(result.get("reason", "未知原因"))]
		return
	var item := result.get("item", {}) as Dictionary
	var target_name := "当前I键背包" if target_owner == "inventory" else ("下局带入" if target_owner == "loadout" else "长期保险柜")
	status_label.text = "%s成功：%s → %s%s" % [
		method, str(item.get("name", "物品")), target_name,
		"（已合并堆叠）" if bool(result.get("merged", false)) else "",
	]
	_build_vault_view()


func _get_backpack_slot_items() -> Array[Dictionary]:
	if _inventory_module == null:
		return _compact_to_slots(BaseManager.get_pending_loadout_items(), BaseManager.get_pending_loadout_capacity())
	var result: Array[Dictionary] = []
	for index in _inventory_module.get_capacity():
		var slot_data := _inventory_module.get_slot(index)
		if slot_data.is_empty():
			result.append({})
			continue
		var item := (slot_data.get("item", {}) as Dictionary).duplicate(true)
		item["count"] = int(slot_data.get("count", 1))
		result.append(item)
	return result


func _compact_to_slots(items: Array[Dictionary], capacity: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in capacity:
		result.append(items[index].duplicate(true) if index < items.size() else {})
	return result


func _column_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.030, 0.040, 0.50)
	style.border_color = Color(0.10, 0.44, 0.52)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _on_close_pressed() -> void:
	queue_free()
