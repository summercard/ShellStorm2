class_name MerchantUI
## 商人和商品面板 — 显示商人出售的物品，玩家可购买
## 由 RoomGameMode 或 MerchantInteraction 在商人房激活时启用

extends Control

signal purchase_requested(item: Dictionary, slot_index: int)
signal merchant_closed()

@export var inventory_tier: int = 1
@export var shop_name: String = "流浪商人"

var _inventory_module: InventoryModule = null
var _currency: int = 0
var _slots: Array[Control] = []
var _items: Array[Dictionary] = []
var _affordable_style: StyleBoxFlat
var _unaffordable_style: StyleBoxFlat

const MAX_DISPLAY := 6

func _ready() -> void:
	_set_panel_styling()
	_build_shop_grid()
	_hide_panel()
	GameManager.currency_changed.connect(_on_currency_changed)

## 设置背包引用
func set_inventory(inventory: InventoryModule) -> void:
	_inventory_module = inventory

## 设置商人层级
func set_tier(tier: int) -> void:
	inventory_tier = tier

## 设置显示名称
func set_shop_name(name: String) -> void:
	shop_name = name

var _current_tween: Tween = null
var _tween_duration: float = 0.25

## 启用面板（商人房进入时调用）
func show_merchant(goods: Array[Dictionary]) -> void:
	_items = goods
	_build_shop_grid()
	_refresh_affordability()
	# 停止旧动画并显示面板（动画版本自动处理打断）
	_show_panel_animated()
	# 获取输入焦点以接收 Esc
	if has_node("CloseButton"):
		var btn: Button = $CloseButton as Button
		if btn:
			btn.focus_mode = Control.FOCUS_ALL

## 隐藏面板
func hide_merchant() -> void:
	_hide_panel_animated()
	merchant_closed.emit()

## 停止并清理当前 Tween（打断处理，防止新旧动画冲突）
func _kill_current_tween() -> void:
	if _current_tween != null and is_instance_valid(_current_tween):
		_current_tween.kill()
	_current_tween = null

## 带动画的显示面板
func _show_panel_animated() -> void:
	_kill_current_tween()
	visible = true
	modulate = Color(1, 1, 1, 0.0)
	_current_tween = create_tween()
	_current_tween.set_parallel(false)
	_current_tween.tween_property(self, "modulate:a", 1.0, _tween_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## 带动画的隐藏面板（淡出后触发 closed 信号）
func _hide_panel_animated() -> void:
	_kill_current_tween()
	_current_tween = create_tween()
	_current_tween.set_parallel(false)
	_current_tween.tween_property(self, "modulate:a", 0.0, _tween_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_current_tween.finished.connect(_on_hide_animation_finished)

func _on_hide_animation_finished() -> void:
	_current_tween = null
	# 确保面板完全隐藏
	visible = false

## 关闭按钮 + Esc 关闭
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if visible:
			hide_merchant()
			get_viewport().set_input_as_handled()

## 设置面板样式
func _set_panel_styling() -> void:
	var bg := UIStyleFactory.make_panel_with_border(0, UIPalette.TEXT_GOLD, 8, 2)
	bg.bg_color = UIPalette.BG_DEEPEST
	add_theme_stylebox_override("panel", bg)

	_affordable_style = StyleBoxFlat.new()
	_affordable_style.bg_color = UIPalette.BG_SLOT
	_affordable_style.set_border_width_all(1)
	_affordable_style.set_border_color(UIPalette.STATUS_OK)
	_affordable_style.set_corner_radius_all(4)

	_unaffordable_style = StyleBoxFlat.new()
	_unaffordable_style.bg_color = Color(0.18, 0.15, 0.15, 0.9)
	_unaffordable_style.set_border_width_all(1)
	_unaffordable_style.set_border_color(UIPalette.STATUS_NO)
	_unaffordable_style.set_corner_radius_all(4)

## 创建商品网格
func _build_shop_grid() -> void:
	# 清除旧格子
	for s in _slots:
		s.queue_free()
	_slots.clear()
	
	# 清除所有子节点（除了 CloseButton 如果存在）
	var to_remove: Array[Node] = []
	for ch in get_children():
		to_remove.append(ch)
	for ch in to_remove:
		remove_child(ch)
		ch.queue_free()
	
	# 主容器 VBox
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)
	
	# 标题行（标题 + 关闭按钮）
	var title_hbox := HBoxContainer.new()
	title_hbox.name = "TitleHBox"
	
	var title := Label.new()
	title.text = shop_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_hbox.add_child(title)
	
	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.pressed.connect(hide_merchant)
	var close_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.HP_LOW)
	UIStyleFactory.apply_button_style(close_btn, close_styles)
	title_hbox.add_child(close_btn)
	
	vbox.add_child(title_hbox)
	
	# 货币显示
	var currency_lbl := Label.new()
	currency_lbl.name = "CurrencyLabel"
	currency_lbl.text = "魂: %d" % GameManager.currency
	currency_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(currency_lbl)
	
	# 网格
	var grid := GridContainer.new()
	grid.name = "ShopGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)
	
	# 生成商品格子
	for i in range(min(MAX_DISPLAY, _items.size())):
		var item: Dictionary = _items[i]
		var slot := _create_shop_slot(item, i)
		grid.add_child(slot)
		_slots.append(slot)

## 创建单个商品格子
func _create_shop_slot(item: Dictionary, slot_index: int) -> Control:
	# 用 PanelContainer 提供背景 + 边框
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _affordable_style.duplicate())
	
	# VBox 内含：图标占位 + 名称 + 价格
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var icon_placeholder := Label.new()
	icon_placeholder.text = "[icon]"
	icon_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(icon_placeholder)
	
	var name_lbl := Label.new()
	name_lbl.name = "NameLabel"
	name_lbl.text = item.get("name", "?")
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(name_lbl)
	
	var price_lbl := Label.new()
	price_lbl.name = "PriceLabel"
	price_lbl.text = "魂 %d" % item.get("price", 0)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(price_lbl)
	
	panel.add_child(vbox)
	
	# 连接 ItemSlot 风格的点击信号（PanelContainer 接收鼠标事件）
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_shop_slot_input.bind(slot_index))
	
	return panel

## 商品格子鼠标输入
func _on_shop_slot_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_slot_clicked(slot_index)

## 格子点击（购买）
func _on_slot_clicked(slot_index: int) -> void:
	if slot_index >= _items.size():
		return
	var item: Dictionary = _items[slot_index]
	var price: int = item.get("price", 0)
	if _inventory_module != null and not _inventory_module.has_space():
		print("[MerchantUI] 背包已满，无法购买: %s" % item.get("name", "?"))
		return
	if GameManager.spend_currency(price):
		if _inventory_module != null:
			_inventory_module.add_item(item.duplicate(), 1)
		purchase_requested.emit(item, slot_index)
		# 刷新可用性
		_refresh_affordability()
	else:
		print("[MerchantUI] 魂不足，无法购买: %s (需要 %d)" % [item.get("name", "?"), price])

## 货币变化刷新
func _on_currency_changed(amount: int) -> void:
	_currency = amount
	_refresh_affordability()
	var currency_lbl: Label = get_node_or_null("CurrencyLabel") as Label
	if currency_lbl:
		currency_lbl.text = "魂: %d" % amount

## 刷新商品可用性显示
func _refresh_affordability() -> void:
	for i in range(_slots.size()):
		if i >= _items.size():
			continue
		var item: Dictionary = _items[i]
		var price: int = item.get("price", 0)
		var affordable: bool = GameManager.currency >= price
		var slot: Control = _slots[i]
		# 找到 PanelContainer 并更新其背景样式
		var panel: PanelContainer = null
		if slot is PanelContainer:
			panel = slot
		elif slot is Control and slot.get_child_count() > 0 and slot.get_child(0) is PanelContainer:
			panel = slot.get_child(0) as PanelContainer
		
		if panel != null:
			var style: StyleBoxFlat
			if affordable:
				style = _affordable_style.duplicate()
				style.set_border_color(UIPalette.STATUS_OK)
			else:
				style = _unaffordable_style.duplicate()
				style.set_border_color(UIPalette.STATUS_NO)
			panel.add_theme_stylebox_override("panel", style)
		
		# 更新价格标签颜色
		var price_lbl: Label = null
		if slot.has_node("PriceLabel"):
			price_lbl = slot.get_node("PriceLabel") as Label
		elif slot.has_node("VBox/PriceLabel"):
			price_lbl = slot.get_node("VBox/PriceLabel") as Label
		if price_lbl != null:
			price_lbl.add_theme_color_override(
				"font_color",
				Color(0.3, 1.0, 0.3, 1.0) if affordable else UIPalette.HP_LOW,
			)

## 设置显示/隐藏（内部用，不再直接设置 visible_ratio）
func _set_panel_visibility(visible: bool) -> void:
	pass  # 已迁移到动画版本

func _hide_panel() -> void:
	# 旧方法保留，MerchantInteraction 内部使用
	modulate.a = 0.0
	visible = false
