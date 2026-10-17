class_name BaseVendingMenu
extends CanvasLayer
## 基地自动贩卖机：左侧无限固定货架，右侧出售随身背包/保险柜物品。

const ITEM_ICON_SCENE := preload("res://assets/art/ui/inventory_3d/ui_item_model_icon_root.tscn")

var _points_label: Label
var _capacity_label: Label
var _status_label: Label
var _buy_list: GridContainer
var _sell_list: GridContainer
var _inventory_module: InventoryModule
var _buy_title_label: Label
var _sell_board: GridInventoryBoard
var _sell_actions: VBoxContainer
var _sell_owner := "inventory"
var _sell_model: InventoryModule
var _selected_anchor := -1
var _source_tabs: Dictionary = {}
const STORAGE_BOARD := preload("res://src/ui/StorageBoardView.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_meta("ui_style_exempt", true)
	layer = 100
	_build_interface()
	_refresh()
	# 只做外观层：面板换棱镜线框（沿用 content_margin，格子尺寸不变）+ 文字色归一化。
	UIStyleFactory.prism_reskin_styleboxes(self)
	UIStyleFactory.prism_normalize_label_colors(self)
	# 手柄通路：十字键/摇杆导航与 A 键确认都需要一个「焦点持有者」，
	# 打开菜单时先抓焦点，否则手柄在子界面里没有入口。
	UiMenuFocus.ensure_focus(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()


func set_inventory_module(module: InventoryModule) -> void:
	_inventory_module = module
	if is_node_ready():
		_refresh()

func _build_interface() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 冷蓝压暗（棱镜）。
	backdrop.color = Color(UIPalette.PRISM_DIM.r, UIPalette.PRISM_DIM.g, UIPalette.PRISM_DIM.b, 0.46)
	add_child(backdrop)
	var columns := HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	columns.offset_left = 14
	columns.offset_top = 14
	columns.offset_right = -14
	columns.offset_bottom = -14
	columns.add_theme_constant_override("separation", 18)
	add_child(columns)
	var buy := _column(columns)
	var heading := HBoxContainer.new()
	buy.add_child(heading)
	_buy_title_label = Label.new()
	_buy_title_label.text = "贩卖机"
	UIStyleFactory.apply_prism_label(_buy_title_label, "value", 4, 22)
	_buy_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_buy_title_label)
	_points_label = Label.new()
	# 金币读数 = 琥珀语义色（与主 HUD 的余额同槽）。
	UIStyleFactory.apply_prism_label(_points_label, "warn", 2, 16)
	heading.add_child(_points_label)
	var buy_scroll := ScrollContainer.new()
	buy_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	buy_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	buy.add_child(buy_scroll)
	_buy_list = GridContainer.new()
	_buy_list.columns = 2
	_buy_list.add_theme_constant_override("h_separation", 8)
	_buy_list.add_theme_constant_override("v_separation", 8)
	buy_scroll.add_child(_buy_list)
	var center := Control.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(center)
	var sell := _column(columns)
	var tabs := HBoxContainer.new()
	sell.add_child(tabs)
	for source in ["inventory", "vault"]:
		var tab := Button.new()
		tab.text = "背包" if source == "inventory" else "仓库"
		tab.custom_minimum_size = Vector2(100, 36)
		_style_action(tab)
		tab.pressed.connect(func() -> void:
			_sell_owner = source
			_selected_anchor = -1
			_refresh())
		_source_tabs[source] = tab
		tabs.add_child(tab)
	_capacity_label = Label.new()
	UIStyleFactory.apply_prism_label(_capacity_label, "label", 2, 15)
	sell.add_child(_capacity_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sell.add_child(scroll)
	_sell_board = STORAGE_BOARD.new()
	scroll.add_child(_sell_board)
	_sell_board.slot_clicked.connect(_select_sell)
	_sell_actions = VBoxContainer.new()
	sell.add_child(_sell_actions)
	_status_label = Label.new()
	_status_label.custom_minimum_size.y = 42
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.text = "选择物品查看售价"
	UIStyleFactory.apply_prism_label(_status_label, "faint", 1, 13)
	sell.add_child(_status_label)
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "返回游戏    [Esc]"
	close.custom_minimum_size.y = 36
	_style_action(close)
	close.pressed.connect(queue_free)
	sell.add_child(close)

func _column(parent: HBoxContainer) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 428
	var style := UIStyleFactory.make_inventory_surface()
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	return box

## 行动钮：购买 = 实心近白主行动；出售 = 平红危险（不填充）。
## 一屏不加括号 —— 括号留给"唯一的那一个当前选框"。
func _style_action(button: Button) -> void:
	var role := "primary"
	if "出售" in button.text or "丢弃" in button.text or "删除" in button.text:
		role = "danger"
	UIStyleFactory.apply_prism_button(button, role, 2, 16, 2, "none")


func _refresh() -> void:
	for owner_key in _source_tabs:
		var tab: Button = _source_tabs[owner_key]
		var active: bool = owner_key == _sell_owner
		UIStyleFactory.apply_prism_button(tab, "primary" if active else "ghost", 2, 15, 2, "none")
	_points_label.text = "金币  %d" % BaseManager.get_extraction_points()
	_clear_children(_buy_list)
	for item in BaseManager.get_base_shop_goods():
		_buy_list.add_child(_make_buy_row(item))
	var owner := "loadout" if _sell_owner == "inventory" and _inventory_module == null else _sell_owner
	_sell_model = _inventory_module if owner == "inventory" else BaseManager.get_storage_grid(owner)
	_sell_board.present(_sell_model, owner)
	# Selecting and confirming a sale is explicit; dropping outside never sells.
	for cell in _sell_board.cells:
		cell.set_meta("drag_disabled", true)
	_capacity_label.text = "%s  %d/%d 格" % ["仓库" if owner == "vault" else "背包", _sell_model.get_used_area(), _sell_model.get_capacity()]
	_selected_anchor = -1
	_clear_children(_sell_actions)

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _select_sell(anchor: int) -> void:
	if _selected_anchor >= 0:
		_sell_board._set_item_hover(_selected_anchor, false)
	_selected_anchor = anchor
	_sell_board._set_item_hover(anchor, true)
	_clear_children(_sell_actions)
	var entry := _sell_model.get_slot(anchor)
	if entry.is_empty():
		return
	var item: Dictionary = entry.item.duplicate(true)
	item["count"] = int(entry.count)
	var owner := "loadout" if _sell_owner == "inventory" and _inventory_module == null else _sell_owner
	var index := anchor if owner == "inventory" else int(item.get("storage_source_index", -1))
	var name_label := Label.new()
	name_label.text = str(item.get("name", "物品")) + "  ×%d" % int(entry.count)
	name_label.add_theme_font_size_override("font_size", 18)
	_sell_actions.add_child(name_label)
	var button := Button.new()
	var price := BaseShopService.get_sell_price(item) * int(entry.count)
	button.text = "出售  +%d 金币" % price if price > 0 else "不收购"
	button.disabled = price <= 0
	button.custom_minimum_size.y = 40
	_style_action(button)
	button.pressed.connect(_on_sell_pressed.bind(str(item.get("item_instance_id", item.get("weapon_instance_id", ""))), item, owner, index, button))
	_sell_actions.add_child(button)

func _make_buy_row(item: Dictionary) -> PanelContainer:
	var row := _make_item_row(item)
	var box := row.get_meta("actions") as VBoxContainer
	var button := Button.new()
	button.text = "购买  ◈ %d" % int(item.get("base_buy_price", 0))
	button.custom_minimum_size = Vector2(0, 42)
	button.disabled = BaseManager.get_extraction_points() < int(item.get("base_buy_price", 0))
	if _inventory_module != null and _inventory_module.plan_purchase_add(item, 1).is_empty():
		button.disabled = true
		button.tooltip_text = "背包没有足够的连续空间"
	elif button.disabled:
		button.tooltip_text = "金币不足"
	button.pressed.connect(_on_buy_pressed.bind(str(item.get("id", ""))))
	_style_action(button)
	box.add_child(button)
	return row


func _make_sell_row(item: Dictionary, source_owner: String, source_index: int) -> PanelContainer:
	var source_name := "当前背包（与I键一致）" if source_owner == "inventory" else ("下局带入" if source_owner == "loadout" else "长期保险柜")
	var row := _make_item_row(item, source_name)
	var box := row.get_meta("actions") as VBoxContainer
	var price := BaseShopService.get_sell_price(item)
	var button := Button.new()
	var total_price := price * maxi(1, int(item.get("count", 1)))
	button.text = "出售  +◈ %d" % total_price if total_price > 0 else "不收购"
	button.custom_minimum_size = Vector2(0, 42)
	button.disabled = total_price <= 0
	var instance_id := str(item.get("item_instance_id", item.get("weapon_instance_id", "")))
	button.pressed.connect(_on_sell_pressed.bind(instance_id, item, source_owner, source_index, button))
	_style_action(button)
	box.add_child(button)
	return row


func _make_item_row(item: Dictionary, owner_label: String = "") -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "VendingItemCard"
	panel.custom_minimum_size = Vector2(194, 220)
	panel.add_theme_stylebox_override("panel", UIStyleFactory.make_inventory_surface(true))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	var icon := ITEM_ICON_SCENE.instantiate() as ItemModelIcon3D
	icon.custom_minimum_size = Vector2(96, 96)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.configure(item)
	box.add_child(icon)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(details)
	var name_label := Label.new()
	name_label.text = str(item.get("name", item.get("id", "未知物品")))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UIStyleFactory.apply_prism_label(name_label, "value", 2, 16)
	details.add_child(name_label)
	var type_label := Label.new()
	var stock_text := owner_label if not owner_label.is_empty() else ("∞ 无限库存" if str(item.get("base_stock_rule", "")) == "unlimited" else "物品")
	type_label.text = "%s · %s" % [_type_name(str(item.get("type", "item"))), stock_text]
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UIStyleFactory.apply_prism_label(type_label, "label", 3, 12)
	details.add_child(type_label)
	var description := Label.new()
	description.text = _item_summary(item)
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyleFactory.apply_prism_label(description, "faint", 1, 11)
	details.add_child(description)
	var actions := VBoxContainer.new()
	actions.name = "CardActions"
	actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(actions)
	panel.set_meta("actions", actions)
	return panel


func _item_summary(item: Dictionary) -> String:
	if str(item.get("type", "")) == "weapon":
		var instance_id := str(item.get("weapon_instance_id", ""))
		var upgrades: Variant = item.get("fate_upgrades", [])
		var used: int = upgrades.size() if upgrades is Array else 0
		if not instance_id.is_empty():
			return "命运 %d/%d" % [used, int(item.get("fate_slot_capacity", 8))]
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
		if AudioManager != null:
			AudioManager.play_sfx("merchant_purchase", -3.0)
		var item := result.get("item", {}) as Dictionary
		_status_label.text = "购买成功：%s 已进入%s%s。" % [
			str(item.get("name", item_id)),
			"背包" if _inventory_module != null else "下局带入",
			"（已合并堆叠）" if bool(result.get("merged", false)) else "",
		]
	else:
		if AudioManager != null:
			AudioManager.play_sfx("ui_error", -4.0)
		_status_label.text = "购买失败：%s" % str(result.get("reason", "未知原因"))
	_refresh()


func _on_sell_pressed(instance_id: String, item: Dictionary, source_owner: String, source_index: int, button: Button) -> void:
	if source_owner == "inventory":
		var current := _inventory_module.get_slot(source_index)
		var current_item: Dictionary = current.get("item", {})
		if current_item != item and (str(current_item.get("id", "")) != str(item.get("id", "")) or str(current_item.get("weapon_instance_id", "")) != str(item.get("weapon_instance_id", "")) or str(current_item.get("item_instance_id", "")) != str(item.get("item_instance_id", "")) or int(current.get("count", 0)) != int(item.get("count", 1))):
			_status_label.text = "物品已变化，请重新选择"
			_refresh()
			return

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
		if AudioManager != null:
			AudioManager.play_sfx("merchant_purchase", -3.0)
		_status_label.text = "出售成功：%s，获得 %d 金币。" % [str(item.get("name", "物品")), int(result.get("value", 0))]
	else:
		if AudioManager != null:
			AudioManager.play_sfx("ui_error", -4.0)
		_status_label.text = "出售失败：%s" % str(result.get("reason", "未知原因"))
	_refresh()


func _make_empty_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.y = 72
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIStyleFactory.apply_prism_label(label, "faint", 1, 15)
	return label


func _make_source_label(text: String) -> Label:
	var label := Label.new()
	label.text = "— %s —" % text
	label.custom_minimum_size.y = 30
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIStyleFactory.apply_prism_label(label, "label", 3, 14)
	return label


func _rarity_color(rarity: String) -> Color:
	return {
		"uncommon": Color(0.32, 0.88, 0.54),
		"rare": Color(0.26, 0.66, 1.0),
		"epic": Color(0.70, 0.36, 1.0),
		"legendary": Color(1.0, 0.58, 0.18),
	}.get(rarity, Color(0.42, 0.68, 0.74)) as Color


func _type_name(type_id: String) -> String:
	return {"weapon": "枪械", "equipment": "装备", "consumable": "消耗品"}.get(type_id, "物品")
