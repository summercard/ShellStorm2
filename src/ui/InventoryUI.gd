class_name InventoryUI
## 背包UI — 显示格子容量、保险格、物品拖放
## 支持独立Panel（InventoryUI.tscn）或内嵌Grid（GameUIManager.tscn内的VBox）

extends Control

signal item_clicked(slot_index: int, item: Dictionary)
signal item_to_insurance_requested(slot_index: int)
signal item_extraction_requested(slot_index: int)
signal inventory_changed()  ## 背包变化时发出（供 GameUIManager 绑定）
signal inventory_open_changed(opened: bool)

@export var inventory_capacity: int = 12
@export var insurance_capacity: int = 2

## 独立模式：是否使用自己创建的Panel；false时依赖父节点已有Grid
@export var standalone_mode: bool = true
@export var accept_tab_shortcut := false
@export var shortcut_enabled := true

# 两个运行模块均为 RefCounted；保留 Variant 也允许测试替身 Node 注入。
var _inventory_module = null
var _insurance_module = null
var _weapon_tree: WeaponAssemblyTree = null
var _weapon_owner: Node = null
var _slots: Array[Control] = []
var _insurance_slots: Array[Control] = []

## 独立模式的子节点（standalone_mode=true时由自己创建）
var inventory_panel: PanelContainer
var inventory_grid: GridContainer
var insurance_panel: PanelContainer
var insurance_grid: GridContainer
var capacity_label: Label
var insurance_label: Label
var backdrop: ColorRect

const SLOT_SIZE := 56
const SLOT_SCENE: PackedScene = preload("res://scenes/ItemSlot.tscn")
const ITEM_MODEL_ICON_SCENE: PackedScene = preload("res://assets/art/ui/inventory_3d/ui_item_model_icon_root_v001.tscn")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 350
	if standalone_mode:
		_setup_standalone_panels()
	_build_inventory_grid()
	_build_insurance_grid()
	_set_panel_positions()
	_set_inventory_panel_visibility(false)

## 独立模式：创建自己的Panel和Grid层级
func _setup_standalone_panels() -> void:
	backdrop = ColorRect.new()
	backdrop.name = "InventoryBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.01, 0.018, 0.026, 0.34)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	inventory_panel = PanelContainer.new()
	inventory_panel.name = "InventoryPanel"
	inventory_panel.add_theme_stylebox_override(
		"panel",
		UIStyleFactory.make_panel_with_border(1, UIPalette.BORDER_NORMAL, 6, 1),
	)
	inventory_panel.custom_minimum_size = Vector2(282, 214)
	inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(inventory_panel)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	inventory_panel.add_child(vbox)

	capacity_label = Label.new()
	capacity_label.name = "CapacityLabel"
	capacity_label.text = "背包 0/12"
	vbox.add_child(capacity_label)
	var shortcut_hint := Label.new()
	shortcut_hint.name = "ShortcutHint"
	shortcut_hint.text = "[I / Tab] 关闭 · 左键使用/装备 · 右键保险"
	shortcut_hint.add_theme_font_size_override("font_size", 12)
	shortcut_hint.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	vbox.add_child(shortcut_hint)

	inventory_grid = GridContainer.new()
	inventory_grid.name = "InventoryGrid"
	inventory_grid.columns = 4
	vbox.add_child(inventory_grid)

	insurance_panel = PanelContainer.new()
	insurance_panel.name = "InsurancePanel"
	# 保险格使用金色调，区别于普通背包
	var ins_style := StyleBoxFlat.new()
	ins_style.bg_color = UIPalette.BG_DARK
	ins_style.set_border_width_all(1)
	ins_style.set_border_color(UIPalette.TEXT_GOLD)
	ins_style.set_corner_radius_all(6)
	insurance_panel.add_theme_stylebox_override("panel", ins_style)
	insurance_panel.custom_minimum_size = Vector2(282, 92)
	insurance_panel.mouse_filter = Control.MOUSE_FILTER_STOP
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
func set_inventory_module(module) -> void:
	_inventory_module = module
	if _inventory_module.has_signal("inventory_changed"):
		_inventory_module.inventory_changed.connect(_on_inventory_changed)
	if _inventory_module.has_signal("capacity_changed"):
		_inventory_module.capacity_changed.connect(_on_capacity_changed)
	_refresh_inventory_ui()

func set_insurance_module(module) -> void:
	_insurance_module = module
	if _insurance_module.has_signal("insurance_changed"):
		_insurance_module.insurance_changed.connect(_on_insurance_changed)
	_refresh_insurance_ui()


func set_weapon_tree(tree: WeaponAssemblyTree) -> void:
	if _weapon_tree != null and _weapon_tree.tree_changed.is_connected(_on_weapon_tree_changed):
		_weapon_tree.tree_changed.disconnect(_on_weapon_tree_changed)
	_weapon_tree = tree
	if _weapon_tree != null and not _weapon_tree.tree_changed.is_connected(_on_weapon_tree_changed):
		_weapon_tree.tree_changed.connect(_on_weapon_tree_changed)
	_refresh_inventory_ui()


func set_weapon_owner(owner: Node) -> void:
	if _weapon_owner != null and is_instance_valid(_weapon_owner) and _weapon_owner.has_signal(
		"weapon_instance_changed"
	):
		if _weapon_owner.weapon_instance_changed.is_connected(_on_equipped_weapon_instance_changed):
			_weapon_owner.weapon_instance_changed.disconnect(_on_equipped_weapon_instance_changed)
	_weapon_owner = owner
	if _weapon_owner != null and _weapon_owner.has_signal("weapon_instance_changed"):
		if not _weapon_owner.weapon_instance_changed.is_connected(_on_equipped_weapon_instance_changed):
			_weapon_owner.weapon_instance_changed.connect(_on_equipped_weapon_instance_changed)
	_refresh_inventory_ui()

## 显示/隐藏背包面板
func _set_inventory_panel_visibility(visible: bool) -> void:
	var was_visible := is_inventory_open()
	if backdrop:
		backdrop.visible = visible
	if inventory_panel:
		inventory_panel.visible = visible
	if insurance_panel:
		insurance_panel.visible = visible
	if visible and inventory_panel:
		inventory_panel.move_to_front()
		insurance_panel.move_to_front()
	if was_visible != visible:
		inventory_open_changed.emit(visible)


func set_inventory_panel_open(opened: bool) -> void:
	_set_inventory_panel_visibility(opened)
	if opened:
		_refresh_inventory_ui()
		_refresh_insurance_ui()


func toggle_inventory_panel() -> void:
	set_inventory_panel_open(not is_inventory_open())


func is_inventory_open() -> bool:
	return inventory_panel != null and inventory_panel.visible

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
func _connect_slot_signals(slot: Control, _idx: int, is_inventory: bool) -> void:
	if slot.has_signal("slot_clicked"):
		slot.slot_clicked.connect(_on_slot_clicked.bind(is_inventory))
	if slot.has_signal("slot_right_clicked"):
		slot.slot_right_clicked.connect(_on_slot_right_clicked.bind(is_inventory))

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
	slot.add_theme_stylebox_override("normal", UIStyleFactory.make_slot_style(false))

	# 悬停高亮
	slot.add_theme_stylebox_override("hover", UIStyleFactory.make_slot_style(true))

	return slot

## 设置面板位置（右上角）
func _set_panel_positions() -> void:
	inventory_panel.anchor_left = 1.0
	inventory_panel.anchor_right = 1.0
	inventory_panel.offset_left = -306
	inventory_panel.offset_right = -18
	inventory_panel.offset_top = 282
	inventory_panel.offset_bottom = 500
	
	insurance_panel.anchor_left = 1.0
	insurance_panel.anchor_right = 1.0
	insurance_panel.offset_left = -306
	insurance_panel.offset_right = -18
	insurance_panel.offset_top = 510
	insurance_panel.offset_bottom = 616

## 刷新背包UI
func _refresh_inventory_ui() -> void:
	if _inventory_module == null:
		return
	
	var occupied: Array[Dictionary] = _inventory_module.get_occupied_slots()
	var slot_data: Dictionary = {}
	for slot_info in occupied:
		var slot_index := int(slot_info.get("slot", slot_info.get("insurance_slot", -1)))
		if slot_index >= 0:
			slot_data[slot_index] = slot_info
	
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
	capacity_label.text = "背包 %d/%d" % [used, cap]

## 刷新保险格UI
func _refresh_insurance_ui() -> void:
	if _insurance_module == null:
		return
	
	var occupied: Array[Dictionary] = []
	if _insurance_module.has_method("get_occupied_slots"):
		occupied = _insurance_module.get_occupied_slots()
	
	var slot_data: Dictionary = {}
	for slot_info in occupied:
		var slot_index := int(slot_info.get("slot", slot_info.get("insurance_slot", -1)))
		if slot_index >= 0:
			slot_data[slot_index] = slot_info
	
	for i in _insurance_slots.size():
		var slot: Control = _insurance_slots[i]
		if slot_data.has(i):
			_update_slot_with_item(slot, slot_data[i])
		else:
			_clear_slot(slot)
	
	var used: int = occupied.size()
	insurance_label.text = "保险格 %d/%d" % [used, insurance_capacity]

func _input(event: InputEvent) -> void:
	if not shortcut_enabled:
		return
	if get_tree().paused:
		return
	var inventory_pressed := event.is_action_pressed("ui_inventory")
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo:
		inventory_pressed = inventory_pressed or key_event.keycode == KEY_I or key_event.physical_keycode == KEY_I
		if accept_tab_shortcut:
			inventory_pressed = inventory_pressed or key_event.keycode == KEY_TAB
	if accept_tab_shortcut:
		inventory_pressed = inventory_pressed or event.is_action_pressed("ui_tab")
	if inventory_pressed:
		toggle_inventory_panel()
		get_viewport().set_input_as_handled()

## 用物品数据更新格子
func _update_slot_with_item(slot: Control, slot_info: Dictionary) -> void:
	var item: Dictionary = slot_info.get("item", {})
	var item_id: String = item.get("id", "")
	var count: int = slot_info.get("count", 1)
	
	if slot is TextureRect:
		(slot as TextureRect).texture = null
	var model_icon := _ensure_model_icon(slot)
	if model_icon != null:
		model_icon.configure(item)
	
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
	slot.add_theme_stylebox_override("normal", UIStyleFactory.make_slot_filled_style())
	var glyph := slot.get_node_or_null("ItemGlyph") as Label
	if glyph == null:
		glyph = Label.new()
		glyph.name = "ItemGlyph"
		glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", 13)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(glyph)
	glyph.visible = model_icon == null
	if glyph.visible:
		glyph.text = _item_glyph(item)
	var equipped_label := _ensure_equipped_label(slot)
	equipped_label.visible = _is_equipped_weapon(item)
	var build_label := _ensure_build_label(slot)
	build_label.visible = str(item.get("type", "")) == "weapon"
	if build_label.visible:
		var instance_id := str(item.get("weapon_instance_id", ""))
		var upgrades: Variant = item.get("fate_upgrades", [])
		var used: int = upgrades.size() if upgrades is Array else 0
		var capacity := int(item.get("fate_slot_capacity", 8))
		build_label.text = "%d/%d · #%s" % [used, capacity, instance_id.right(6).to_upper()]
		slot.tooltip_text = "%s #%s\n命运构筑 %d/%d（永久）\n%s\n左键装备完整实例 · 右键存保险" % [
			item.get("name", item_id), instance_id.right(6).to_upper(), used, capacity,
			item.get("description", ""),
		]
	else:
		slot.tooltip_text = "%s x%d\n%s\n左键使用/装备 · 右键存保险" % [
			item.get("name", item_id), count, item.get("description", "")
		]

## 清空格子
func _clear_slot(slot: Control) -> void:
	if slot is TextureRect:
		(slot as TextureRect).texture = null
	if slot.has_node("CountLabel"):
		var cl: Label = slot.get_node("CountLabel") as Label
		cl.visible = false
	var glyph := slot.get_node_or_null("ItemGlyph") as Label
	if glyph != null:
		glyph.visible = false
	var model_icon := slot.get_node_or_null("ItemModelIcon3D") as ItemModelIcon3D
	if model_icon != null:
		model_icon.clear_model()
	var equipped_label := slot.get_node_or_null("EquippedLabel") as Label
	if equipped_label != null:
		equipped_label.visible = false
	var build_label := slot.get_node_or_null("WeaponBuildLabel") as Label
	if build_label != null:
		build_label.visible = false
	slot.tooltip_text = ""
	slot.add_theme_stylebox_override("normal", UIStyleFactory.make_slot_style(false))


func _item_glyph(item: Dictionary) -> String:
	if item.get("id", "") == "item_room_key":
		return "KEY"
	if item.get("type", "") == "weapon" or item.get("subtype", "") == "gun_body":
		return "GUN"
	if item.get("subtype", "") == "bullet":
		return "BUL"
	if item.get("type", "") == "attachment":
		return "ATT"
	if item.get("type", "") == "blueprint":
		return "BP"
	if item.get("use_action", "") == "heal":
		return "HP"
	if item.get("use_action", "") == "refill_ammo":
		return "AM"
	if item.get("id", "") == "item_beacon":
		return "EXT"
	return "ITM"


func get_slot_model_snapshot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= _slots.size():
		return {}
	var icon := _slots[slot_index].get_node_or_null("ItemModelIcon3D") as ItemModelIcon3D
	return icon.get_snapshot() if icon != null else {}


func _ensure_model_icon(slot: Control) -> ItemModelIcon3D:
	var existing := slot.get_node_or_null("ItemModelIcon3D") as ItemModelIcon3D
	if existing != null:
		return existing
	if ITEM_MODEL_ICON_SCENE == null:
		return null
	var icon := ITEM_MODEL_ICON_SCENE.instantiate() as ItemModelIcon3D
	icon.name = "ItemModelIcon3D"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 4.0
	icon.offset_top = 4.0
	icon.offset_right = -4.0
	icon.offset_bottom = -4.0
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon)
	slot.move_child(icon, 0)
	return icon


func _ensure_equipped_label(slot: Control) -> Label:
	var existing := slot.get_node_or_null("EquippedLabel") as Label
	if existing != null:
		return existing
	var label := Label.new()
	label.name = "EquippedLabel"
	label.text = "已装备"
	label.position = Vector2(3, 2)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.24))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(label)
	return label


func _ensure_build_label(slot: Control) -> Label:
	var existing := slot.get_node_or_null("WeaponBuildLabel") as Label
	if existing != null:
		return existing
	var label := Label.new()
	label.name = "WeaponBuildLabel"
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -17.0
	label.offset_bottom = -1.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(0.40, 0.92, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(label)
	return label


func _is_equipped_weapon(item: Dictionary) -> bool:
	if _weapon_owner != null and is_instance_valid(_weapon_owner) and _weapon_owner.has_method(
		"get_equipped_weapon_instance_id"
	):
		var equipped_id := str(_weapon_owner.call("get_equipped_weapon_instance_id"))
		var item_instance_id := str(item.get("weapon_instance_id", ""))
		if not equipped_id.is_empty() and not item_instance_id.is_empty():
			return equipped_id == item_instance_id
	if _weapon_tree == null or _weapon_tree.get_root() == null:
		return false
	if str(item.get("type", "")) != "weapon":
		return false
	var root_name := _weapon_tree.get_root().node_name
	var assembly_id := str(item.get("assembly_id", ""))
	return assembly_id == str({
		"GunBody_Pistol": "bp_pistol", "GunBody_Shotgun": "bp_shotgun",
		"GunBody_Rifle": "bp_rifle", "GunBody_Machinegun": "bp_machinegun",
		"GunBody_Sniper": "bp_sniper", "GunBody_Launcher": "bp_launcher",
		"GunBody_Charge": "bp_charge",
	}.get(root_name, ""))

## 信号回调
func _on_inventory_changed() -> void:
	_refresh_inventory_ui()
	inventory_changed.emit()

func _on_capacity_changed(current: int, maximum: int) -> void:
	_refresh_inventory_ui()

func _on_insurance_changed() -> void:
	_refresh_insurance_ui()
	inventory_changed.emit()  ## 保险格变化也触发刷新通知


func _on_weapon_tree_changed() -> void:
	_refresh_inventory_ui()


func _on_equipped_weapon_instance_changed(_snapshot: Dictionary) -> void:
	_refresh_inventory_ui()

## 格子左键点击（显示物品操作菜单/存入保险）
func _on_slot_clicked(slot_index: int, is_inventory: bool) -> void:
	if is_inventory:
		item_clicked.emit(slot_index, {})
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
