class_name InventoryUI
## 背包UI — 显示格子容量、保险格、物品拖放
## 挂在 CanvasLayer 下

extends Control

signal item_clicked(slot_index: int, item: Dictionary)
signal item_to_insurance_requested(slot_index: int)
signal item_extraction_requested(slot_index: int)

@export var inventory_capacity: int = 12
@export var insurance_capacity: int = 2

var _inventory_module: Node = null
var _insurance_module: Node = null
var _slots: Array[TextureRect] = []
var _insurance_slots: Array[TextureRect] = []

@onready var inventory_panel: PanelContainer = $InventoryPanel
@onready var inventory_grid: GridContainer = $InventoryPanel/VBox/InventoryGrid
@onready var capacity_label: Label = $InventoryPanel/VBox/CapacityLabel
@onready var insurance_panel: PanelContainer = $InsurancePanel
@onready var insurance_grid: GridContainer = $InsurancePanel/VBox/InsuranceGrid
@onready var insurance_label: Label = $InsurancePanel/VBox/InsuranceLabel

const SLOT_SIZE := 56
const SLOT_SCENE := preload("res://src/ui/ItemSlot.tscn")

func _ready() -> void:
	_build_inventory_grid()
	_build_insurance_grid()
	_set_panel_positions()

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

func _create_slot() -> TextureRect:
	var slot := TextureRect.new()
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
		var slot: TextureRect = _insurance_slots[i]
		if slot_data.has(i):
			_update_slot_with_item(slot, slot_data[i])
		else:
			_clear_slot(slot)
	
	var used: int = occupied.size()
	insurance_label.text = "保险格 %d/%d" % [used, insurance_capacity]

## 用物品数据更新格子
func _update_slot_with_item(slot: TextureRect, slot_info: Dictionary) -> void:
	var item: Dictionary = slot_info.get("item", {})
	var item_id: String = item.get("id", "")
	var count: int = slot_info.get("count", 1)
	
	# 尝试加载物品图标
	var icon_path: String = item.get("icon", "")
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var tex := load(icon_path)
		slot.texture = tex
	else:
		slot.texture = null
	
	# 高亮边框表示有物品
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = Color(0.2, 0.22, 0.28, 0.95)
	style_box.set_border_width_all(2)
	style_box.set_border_color(Color(0.6, 0.7, 0.9, 0.7))
	style_box.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("normal", style_box)

## 清空格子
func _clear_slot(slot: TextureRect) -> void:
	slot.texture = null
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = Color(0.12, 0.14, 0.18, 0.9)
	style_box.set_border_width_all(1)
	style_box.set_border_color(Color(0.3, 0.33, 0.4, 0.6))
	style_box.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("normal", style_box)

## 信号回调
func _on_inventory_changed() -> void:
	_refresh_inventory_ui()

func _on_capacity_changed(current: int, maximum: int) -> void:
	_refresh_inventory_ui()

func _on_insurance_changed() -> void:
	_refresh_insurance_ui()

## 格子点击（用于后续扩展物品详情、拖放等）
func _on_slot_clicked(slot_index: int) -> void:
	# TODO: 物品详情弹窗、右键菜单
	pass