class_name InventoryUI
## 背包UI — 显示格子容量、保险格、物品拖放
## 支持独立Panel（InventoryUI.tscn）或内嵌Grid（GameUIManager.tscn内的VBox）

extends Control

signal item_clicked(slot_index: int, item: Dictionary)
signal item_to_insurance_requested(slot_index: int)
signal item_extraction_requested(slot_index: int)
signal inventory_changed()  ## 背包变化时发出（供 GameUIManager 绑定）

@export var inventory_capacity: int = 12
@export var insurance_capacity: int = 2

## 独立模式：是否使用自己创建的Panel；false时依赖父节点已有Grid
@export var standalone_mode: bool = true

var _inventory_module: Node = null
var _insurance_module: Node = null
var _slots: Array[Control] = []
var _insurance_slots: Array[Control] = []

## 独立模式的子节点（standalone_mode=true时由自己创建）
var inventory_panel: PanelContainer
var inventory_grid: GridContainer
var insurance_panel: PanelContainer
var insurance_grid: GridContainer
var capacity_label: Label
var insurance_label: Label

const SLOT_SIZE := 56
const SLOT_SCENE: PackedScene = preload("res://scenes/ItemSlot.tscn")

func _ready() -> void:
	if standalone_mode:
		_setup_standalone_panels()
	_build_inventory_grid()
	_build_insurance_grid()
	_set_panel_positions()
	_set_inventory_panel_visibility(false)

## 独立模式：创建自己的Panel和Grid层级
func _setup_standalone_panels() -> void:
	inventory_panel = PanelContainer.new()
	inventory_panel.name = "InventoryPanel"
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = Color(0.1, 0.12, 0.18, 0.95)
	style_box.set_border_width_all(1)
	style_box.set_border_color(Color(0.3, 0.35, 0.5, 0.8))
	style_box.set_corner_radius_all(6)
	inventory_panel.add_theme_stylebox_override("panel", style_box)
	add_child(inventory_panel)
	
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	inventory_panel.add_child(vbox)
	
	capacity_label = Label.new()
	capacity_label.name = "CapacityLabel"
	capacity_label.text = "背包 0/12"
	vbox.add_child(capacity_label)
	
	inventory_grid = GridContainer.new()
	inventory_grid.name = "InventoryGrid"
	inventory_grid.columns = 4
	vbox.add_child(inventory_grid)
	
	insurance_panel = PanelContainer.new()
	insurance_panel.name = "InsurancePanel"
	var ins_style := StyleBoxFlat.new()
	ins_style.bg_color = Color(0.12, 0.1, 0.15, 0.95)
	ins_style.set_border_width_all(1)
	ins_style.set_border_color(Color(0.5, 0.4, 0.2, 0.8))
	ins_style.set_corner_radius_all(6)
	insurance_panel.add_theme_stylebox_override("panel", ins_style)
	add_child(insurance_panel)
	
	var ins_vbox := VBoxContainer.new()
	ins_vbox.name = "VBox"
	insurance_panel.add_child(ins_vbox)
	
	insurance_label = Label.new()
	insurance_label.name = "InsuranceLabel"
	insurance_label.text = "保险格 0/2"
	ins_vbox.add_child(insurance_label)
	
	insurance_grid = GridContainer.new()
	insurance_grid.name = "InsuranceGrid"
	insurance_grid.columns = 2
	ins_vbox.add_child(insurance_grid)

## 绑定 inventory module
func set_inventory_module(module: Node) -> void:
	_inventory_module = module
	if _inventory_module.has_signal("inventory_changed"):
		_inventory_module.inventory_changed.connect(_on_inventory_changed)
	if _inventory_module.has_signal("capacity_changed"):
		_inventory_module.capacity_changed.connect(_on_capacity_changed)
	_refresh_inventory_ui()

func set_insurance_module(module: Node) -> void:
	_insurance_module = module
	if _insurance_module.has_signal("insurance_changed"):
		_insurance_module.insurance_changed.connect(_on_insurance_changed)
	_refresh_insurance_ui()

## 显示/隐藏背包面板
func _set_inventory_panel_visibility(visible: bool) -> void:
	if inventory_panel:
		inventory_panel.visible = visible
	if insurance_panel:
		insurance_panel.visible = visible

## 构建背包格子
func _build_inventory_grid() -> void:
	for child in inventory_grid.get_children():
		child.queue_free()
	_slots.clear()
	
	for i in inventory_capacity:
		var slot := _create_slot()
		slot.name = "InvSlot_%d" % i
		inventory_grid.add_child(slot)
		_slots.append(slot)
		_connect_slot_signals(slot, i, true)

## 构建保险格
func _build_insurance_grid() -> void:
	for child in insurance_grid.get_children():
		child.queue_free()
	_insurance_slots.clear()
	
	for i in insurance_capacity:
		var slot := _create_slot()
		slot.name = "InsSlot_%d" % i
		insurance_grid.add_child(slot)
		_insurance_slots.append(slot)
		_connect_slot_signals(slot, i, false)

## 连接格子的点击信号
func _connect_slot_signals(slot: Control, idx: int, is_inventory: bool) -> void:
	if slot.has_signal("slot_clicked"):
		slot.slot_clicked.connect(_on_slot_clicked.bind(idx, is_inventory))
	if slot.has_signal("slot_right_clicked"):
		slot.slot_right_clicked.connect(_on_slot_right_clicked.bind(idx, is_inventory))

func _create_slot() -> Control:
	var slot: Control
	if SLOT_SCENE != null:
		slot = SLOT_SCENE.instantiate() as Control
	else:
		slot = TextureRect.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	# 背景色：空格子深色，有物品稍亮
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = Color(0.12, 0.14, 0.18, 0.9)
	style_box.set_border_width_all(1)
	style_box.set_border_color(Color(0.3, 0.33, 0.4, 0.6))
	style_box.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("normal", style_box)
	
	# 悬停高亮
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.2, 0.25, 0.35, 0.9)
	hover_style.set_border_width_all(1)
	hover_style.set_border_color(Color(0.5, 0.6, 0.8, 0.8))
	hover_style.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("hover", hover_style)
	
	return slot

## 设置面板位置（右上角）
func _set_panel_positions() -> void:
	var vp_size := get_viewport_rect().size
	inventory_panel.anchor_left = 1.0
	inventory_panel.anchor_right = 1.0
	inventory_panel.offset_left = -220
	inventory_panel.offset_right = -10
	inventory_panel.offset_top = 10
	inventory_panel.offset_bottom = 10
	
	insurance_panel.anchor_left = 1.0
	insurance_panel.anchor_right = 1.0
	insurance_panel.offset_left = -120
	insurance_panel.offset_right = -10
	insurance_panel.offset_top = 200
	insurance_panel.offset_bottom = 200

## 刷新背包UI
func _refresh_inventory_ui() -> void:
	if _inventory_module == null:
		return
	
	var occupied: Array[Dictionary] = _inventory_module.get_occupied_slots()
	var slot_data: Dictionary = {}
	for slot_info in occupied:
		slot_data[slot_info["slot"]] = slot_info
	
	# 更新每个格子
	for i in _slots.size():
		var slot: TextureRect = _slots[i]
		if slot_data.has(i):
			_update_slot_with_item(slot, slot_data[i])
		else:
			_clear_slot(slot)
	
	# 更新容量标签
	var used: int = _inventory_module.get_used_slots()
	var cap: int = _inventory_module.get_capacity()
	capacity_label.text = "%d/%d" % [used, cap]

## 刷新保险格UI
func _refresh_insurance_ui() -> void:
	if _insurance_module == null:
		return
	
	var occupied: Array[Dictionary] = []
	if _insurance_module.has_method("get_occupied_slots"):
		occupied = _insurance_module.get_occupied_slots()
	
	var slot_data: Dictionary = {}
	for slot_info in occupied:
		slot_data[slot_info["slot"]] = slot_info
	
	for i in _insurance_slots.size():
		var slot: Control = _insurance_slots[i]
		if slot_data.has(i):
			_update_slot_with_item(slot, slot_data[i])
		else:
			_clear_slot(slot)
	
	var used: int = occupied.size()
	insurance_label.text = "保险格 %d/%d" % [used, insurance_capacity]

func _input(event: InputEvent) -> void:
	# Tab 键切换背包面板显示/隐藏
	if event.is_action_pressed("ui_tab"):
		var visible := not inventory_panel.visible if inventory_panel else false
		_set_inventory_panel_visibility(visible)

## 用物品数据更新格子
func _update_slot_with_item(slot: Control, slot_info: Dictionary) -> void:
	var item: Dictionary = slot_info.get("item", {})
	var item_id: String = item.get("id", "")
	var count: int = slot_info.get("count", 1)
	
	# 尝试加载物品图标
	var icon_path: String = item.get("icon", "")
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var tex: Texture2D = load(icon_path) as Texture2D
		if slot is TextureRect:
			(slot as TextureRect).texture = tex
	else:
		if slot is TextureRect:
			(slot as TextureRect).texture = null
	
	# 显示叠加数量标签（如果有 ItemSlot 子节点）
	if slot.has_method("set_slot_index"):
		slot.set_slot_index(slot_info.get("slot", 0))
	if slot.has_node("CountLabel"):
		var cl: Label = slot.get_node("CountLabel") as Label
		if count > 1:
			cl.text = "x%d" % count
			cl.visible = true
		else:
			cl.visible = false
	
	# 高亮边框表示有物品
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = Color(0.2, 0.22, 0.28, 0.95)
	style_box.set_border_width_all(2)
	style_box.set_border_color(Color(0.6, 0.7, 0.9, 0.7))
	style_box.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("normal", style_box)

## 清空格子
func _clear_slot(slot: Control) -> void:
	if slot is TextureRect:
		(slot as TextureRect).texture = null
	if slot.has_node("CountLabel"):
		var cl: Label = slot.get_node("CountLabel") as Label
		cl.visible = false
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = Color(0.12, 0.14, 0.18, 0.9)
	style_box.set_border_width_all(1)
	style_box.set_border_color(Color(0.3, 0.33, 0.4, 0.6))
	style_box.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("normal", style_box)

## 信号回调
func _on_inventory_changed() -> void:
	_refresh_inventory_ui()
	inventory_changed.emit()

func _on_capacity_changed(current: int, maximum: int) -> void:
	_refresh_inventory_ui()

func _on_insurance_changed() -> void:
	_refresh_insurance_ui()
	inventory_changed.emit()  ## 保险格变化也触发刷新通知

## 格子左键点击（显示物品操作菜单/存入保险）
func _on_slot_clicked(slot_index: int, is_inventory: bool) -> void:
	if is_inventory:
		item_clicked.emit(slot_index, {})
		# 存入保险格（如果保险有空间）
		if _insurance_module != null and _inventory_module != null:
			var slot_data: Dictionary = _inventory_module.get_slot(slot_index)
			if not slot_data.is_empty():
				item_to_insurance_requested.emit(slot_index)
	else:
		# 保险格右键取出
		item_clicked.emit(slot_index + 1000, {})  # 1000+ 表示保险格
		item_extraction_requested.emit(slot_index)

## 格子右键点击（存入保险格 / 取出保险物品）
func _on_slot_right_clicked(slot_index: int, is_inventory: bool) -> void:
	if is_inventory:
		# 背包物品右键 → 存入保险格
		if _insurance_module != null and _inventory_module != null:
			var slot_data: Dictionary = _inventory_module.get_slot(slot_index)
			if not slot_data.is_empty():
				item_to_insurance_requested.emit(slot_index)
	else:
		# 保险格右键 → 取出物品
		item_extraction_requested.emit(slot_index)
