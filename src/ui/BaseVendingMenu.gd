class_name BaseVendingMenu
extends CanvasLayer
## 基地自动贩卖机：左侧无限固定货架，右侧出售随身背包/保险柜物品。

const ITEM_ICON_SCENE := preload("res://assets/art/ui/inventory_3d/ui_item_model_icon_root_v001.tscn")

var _points_label: Label
var _capacity_label: Label
var _status_label: Label
var _buy_list: VBoxContainer
var _sell_list: VBoxContainer
var _inventory_module: InventoryModule
var _buy_title_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_build_interface()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		queue_free()


func set_inventory_module(module: InventoryModule) -> void:
	_inventory_module = module
	if is_node_ready():
		if _buy_title_label != null:
			_buy_title_label.text = "购买货物｜进入当前背包(I)"
		_status_label.text = "当前背包与I键使用同一数据源；购买、出售和保险柜转移会立即同步。"
		_refresh()


func _build_interface() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.005, 0.012, 0.018, 0.94)
	add_child(backdrop)

	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 64.0
	frame.offset_top = 42.0
	frame.offset_right = -64.0
	frame.offset_bottom = -42.0
	frame.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.82, 0.94), 3, Color(0.018, 0.045, 0.058, 0.98)))
	add_child(frame)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	frame.add_child(root)

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 64
	root.add_child(header)
	var title := Label.new()
	title.text = "基地自动贩卖机"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color(0.42, 0.94, 1.0))
	title.add_theme_font_size_override("font_size", 28)
	header.add_child(title)
	_points_label = Label.new()
	_points_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.28))
	_points_label.add_theme_font_size_override("font_size", 20)
	header.add_child(_points_label)
	_capacity_label = Label.new()
	_capacity_label.custom_minimum_size.x = 190
	_capacity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_capacity_label.add_theme_font_size_override("font_size", 18)
	header.add_child(_capacity_label)
	var close := Button.new()
	close.text = "关闭  ESC"
	close.custom_minimum_size = Vector2(126, 40)
	close.pressed.connect(queue_free)
	close.add_theme_stylebox_override("normal", _panel_style(Color(0.22, 0.56, 0.66), 1, Color(0.04, 0.10, 0.13)))
	header.add_child(close)

	var columns := HSplitContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.split_offset = 0
	root.add_child(columns)
	var buy_panel := _make_column("购买货物｜进入当前背包(I)" if _inventory_module != null else "购买货物｜进入下局带入", "∞ 无限库存 · 消耗品自动合并堆叠")
	_buy_list = buy_panel.get_meta("list") as VBoxContainer
	_buy_title_label = buy_panel.get_meta("title") as Label
	columns.add_child(buy_panel)
	var sell_panel := _make_column("出售物品｜随身背包 + 保险柜", "来源明确显示；枪械需二次确认")
	_sell_list = sell_panel.get_meta("list") as VBoxContainer
	columns.add_child(sell_panel)

	_status_label = Label.new()
	_status_label.custom_minimum_size.y = 38
	_status_label.text = "请选择商品。购买默认进入随身背包，空间不足时不会扣除基地币。"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color(0.68, 0.86, 0.92))
	_status_label.add_theme_stylebox_override("normal", _panel_style(Color(0.16, 0.48, 0.58), 1, Color(0.025, 0.065, 0.08)))
	root.add_child(_status_label)


func _make_column(title_text: String, hint_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 0)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.10, 0.42, 0.50), 1, Color(0.012, 0.030, 0.040, 0.96)))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color(0.38, 0.90, 0.98))
	box.add_child(title)
	var hint := Label.new()
	hint.text = hint_text
	hint.add_theme_color_override("font_color", Color(0.48, 0.65, 0.70))
	box.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 7)
	scroll.add_child(list)
	panel.set_meta("list", list)
	panel.set_meta("title", title)
	return panel


func _refresh() -> void:
	_points_label.text = "购买货币｜基地币  ◈ %d" % BaseManager.get_extraction_points()
	_capacity_label.text = (
		"当前背包(I)  %d / %d" % [_inventory_module.get_used_slots(), _inventory_module.get_capacity()]
		if _inventory_module != null
		else "下局带入  %d / %d" % [BaseManager.get_pending_loadout_items().size(), BaseManager.get_pending_loadout_capacity()]
	)
	_clear_list(_buy_list)
	_clear_list(_sell_list)
	for item in BaseManager.get_base_shop_goods():
		_buy_list.add_child(_make_buy_row(item))
	var loadout_items := BaseManager.get_pending_loadout_items()
	var vault_items := BaseManager.get_vault_items()
	var runtime_entries: Array[Dictionary] = []
	if _inventory_module != null:
		runtime_entries = _inventory_module.get_occupied_slots()
	if runtime_entries.is_empty() and loadout_items.is_empty() and vault_items.is_empty():
		_sell_list.add_child(_make_empty_label("随身背包与保险柜暂无可出售物品"))
		return
	if _inventory_module != null and not runtime_entries.is_empty():
		_sell_list.add_child(_make_source_label("当前背包（与I键一致）"))
		for entry in runtime_entries:
			var runtime_item := (entry.get("item", {}) as Dictionary).duplicate(true)
			runtime_item["count"] = int(entry.get("count", 1))
			_sell_list.add_child(_make_sell_row(runtime_item, "inventory", int(entry.get("slot", -1))))
	elif not loadout_items.is_empty():
		_sell_list.add_child(_make_source_label("随身背包（下局带入）"))
		for index in loadout_items.size():
			_sell_list.add_child(_make_sell_row(loadout_items[index], "loadout", index))
	if not vault_items.is_empty():
		_sell_list.add_child(_make_source_label("长期保险柜"))
		for index in vault_items.size():
			_sell_list.add_child(_make_sell_row(vault_items[index], "vault", index))


func _clear_list(list: VBoxContainer) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


func _make_buy_row(item: Dictionary) -> PanelContainer:
	var row := _make_item_row(item)
	var box := row.get_child(0) as HBoxContainer
	var button := Button.new()
	button.text = "购买\n◈ %d" % int(item.get("base_buy_price", 0))
	button.custom_minimum_size = Vector2(106, 60)
	button.disabled = BaseManager.get_extraction_points() < int(item.get("base_buy_price", 0))
	button.pressed.connect(_on_buy_pressed.bind(str(item.get("id", ""))))
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.18, 0.72, 0.84), 2, Color(0.035, 0.16, 0.20)))
	box.add_child(button)
	return row


func _make_sell_row(item: Dictionary, source_owner: String, source_index: int) -> PanelContainer:
	var source_name := "当前背包(I)" if source_owner == "inventory" else ("下局带入" if source_owner == "loadout" else "长期保险柜")
	var row := _make_item_row(item, source_name)
	var box := row.get_child(0) as HBoxContainer
	var price := BaseShopService.get_sell_price(item)
	var button := Button.new()
	var total_price := price * maxi(1, int(item.get("count", 1)))
	button.text = "出售\n+◈ %d" % total_price if total_price > 0 else "不收购"
	button.custom_minimum_size = Vector2(106, 60)
	button.disabled = total_price <= 0
	var instance_id := str(item.get("item_instance_id", item.get("weapon_instance_id", "")))
	button.pressed.connect(_on_sell_pressed.bind(instance_id, item, source_owner, source_index, button))
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.94, 0.48, 0.18), 2, Color(0.20, 0.075, 0.035)))
	box.add_child(button)
	return row


func _make_item_row(item: Dictionary, owner_label: String = "") -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 94)
	panel.add_theme_stylebox_override("panel", _panel_style(_rarity_color(str(item.get("rarity", "common"))), 2, Color(0.025, 0.050, 0.062, 0.96)))
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var icon := ITEM_ICON_SCENE.instantiate() as ItemModelIcon3D
	icon.custom_minimum_size = Vector2(82, 82)
	icon.configure(item)
	box.add_child(icon)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(details)
	var name_label := Label.new()
	name_label.text = str(item.get("name", item.get("id", "未知物品")))
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(0.88, 0.96, 0.98))
	details.add_child(name_label)
	var type_label := Label.new()
	var stock_text := owner_label if not owner_label.is_empty() else ("∞ 无限库存" if str(item.get("base_stock_rule", "")) == "unlimited" else "物品")
	type_label.text = "%s · %s" % [_type_name(str(item.get("type", "item"))), stock_text]
	type_label.add_theme_color_override("font_color", Color(0.35, 0.78, 0.88))
	details.add_child(type_label)
	var description := Label.new()
	description.text = _item_summary(item)
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	description.add_theme_color_override("font_color", Color(0.58, 0.69, 0.73))
	details.add_child(description)
	return panel


func _item_summary(item: Dictionary) -> String:
	if str(item.get("type", "")) == "weapon":
		var instance_id := str(item.get("weapon_instance_id", ""))
		var upgrades: Variant = item.get("fate_upgrades", [])
		var used: int = upgrades.size() if upgrades is Array else 0
		if not instance_id.is_empty():
			return "实例 #%s · 命运 %d/%d · 完整装配随枪保存" % [instance_id.right(6).to_upper(), used, int(item.get("fate_slot_capacity", 8))]
		return "全新独立枪械 · 命运槽 0/%d" % int(item.get("fate_slot_capacity", 8))
	if str(item.get("subtype", "")) == "backpack":
		return "装备后增加 %d 个背包格" % int(item.get("extra_slots", 0))
	return str(item.get("description", "独立物品实例"))


func _on_buy_pressed(item_id: String) -> void:
	var result := (
		BaseManager.purchase_base_shop_item_to_inventory(item_id, _inventory_module, BaseShopService.generate_transaction_id("buy"))
		if _inventory_module != null
		else BaseManager.purchase_base_shop_item(item_id, BaseShopService.generate_transaction_id("buy"))
	) as Dictionary
	if bool(result.get("success", false)):
		var item := result.get("item", {}) as Dictionary
		_status_label.text = "购买成功：%s 已进入%s%s。" % [
			str(item.get("name", item_id)),
			"当前I键背包" if _inventory_module != null else "下局带入",
			"（已合并堆叠）" if bool(result.get("merged", false)) else "",
		]
	else:
		_status_label.text = "购买失败：%s" % str(result.get("reason", "未知原因"))
	_refresh()


func _on_sell_pressed(instance_id: String, item: Dictionary, source_owner: String, source_index: int, button: Button) -> void:
	if str(item.get("type", "")) == "weapon" and not bool(button.get_meta("confirm_sell", false)):
		button.set_meta("confirm_sell", true)
		button.text = "再次点击\n确认出售"
		_status_label.text = "确认出售完整枪械 #%s：命运升级与装配将永久离开。" % str(item.get("weapon_instance_id", "")).right(6).to_upper()
		return
	var result := (
		BaseManager.sell_runtime_inventory_item(_inventory_module, source_index, BaseShopService.generate_transaction_id("sell"))
		if source_owner == "inventory"
		else BaseManager.sell_base_shop_item(instance_id, BaseShopService.generate_transaction_id("sell"), source_owner)
	) as Dictionary
	if bool(result.get("success", false)):
		_status_label.text = "出售成功：%s，获得 %d 基地币。" % [str(item.get("name", "物品")), int(result.get("value", 0))]
	else:
		_status_label.text = "出售失败：%s" % str(result.get("reason", "未知原因"))
	_refresh()


func _make_empty_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.y = 72
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.42, 0.58, 0.64))
	return label


func _make_source_label(text: String) -> Label:
	var label := Label.new()
	label.text = "— %s —" % text
	label.custom_minimum_size.y = 30
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.42, 0.90, 0.98))
	return label


func _panel_style(border: Color, width: int, background: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _rarity_color(rarity: String) -> Color:
	return {
		"uncommon": Color(0.32, 0.88, 0.54),
		"rare": Color(0.26, 0.66, 1.0),
		"epic": Color(0.70, 0.36, 1.0),
		"legendary": Color(1.0, 0.58, 0.18),
	}.get(rarity, Color(0.42, 0.68, 0.74)) as Color


func _type_name(type_id: String) -> String:
	return {"weapon": "枪械", "equipment": "装备", "consumable": "消耗品"}.get(type_id, "物品")
