class_name InventoryUI
## 背包UI — 显示格子容量、保险格、物品拖放
## 支持独立 Panel（InventoryUI.tscn）或嵌入当前 3D HUD 的 Grid。

extends Control

signal item_clicked(slot_index: int, item: Dictionary)
signal item_to_insurance_requested(slot_index: int)
signal item_extraction_requested(slot_index: int)
signal item_dropped_to_world(item: Dictionary, count: int)
signal inventory_changed()  ## 背包变化时发出（供 3D HUD 绑定）
signal inventory_open_changed(opened: bool)
signal weapon_slot_equip_requested(source_slot_index: int, weapon_slot_index: int)
signal equipped_weapon_to_inventory_requested(weapon_slot_index: int, target_slot_index: int)
signal equipped_weapon_drop_requested(weapon_slot_index: int)
signal attachment_slot_install_requested(source_slot_index: int, weapon_slot_index: int, attachment_slot_type: int)
signal attachment_slot_remove_requested(weapon_slot_index: int, attachment_slot_type: int, target_slot_index: int)
signal quick_item_assignment_requested(quick_slot_index: int, item_id: String)
signal backpack_slot_equip_requested(source_slot_index: int)
signal equipped_backpack_to_inventory_requested(target_slot_index: int)
signal equipped_backpack_drop_requested()

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
var _backpack_owner: Node = null
var _slots: Array[Control] = []
var _insurance_slots: Array[Control] = []

## 独立模式的子节点（standalone_mode=true时由自己创建）
var inventory_panel: PanelContainer
var inventory_grid: GridContainer
var insurance_panel: PanelContainer
var insurance_grid: GridContainer
var inventory_shell: PanelContainer
var equipment_panel: PanelContainer
var equipment_weapon_slot: Control
var equipment_weapon_label: Label
var equipment_weapon_slots: Array[Control] = []
var equipment_weapon_labels: Array[Label] = []
var equipment_attachment_slots: Array = []
var equipment_backpack_slot: Control
var equipment_backpack_label: Label
var quick_item_slots: Array[Control] = []
var quick_item_ids: Array[String] = ["", ""]
var equipment_hp_bar: ProgressBar
var equipment_hp_label: Label
var equipment_fate_label: Label
var drop_zone: Control
var sort_button: Button
var capacity_label: Label
var insurance_label: Label
var backdrop: ColorRect
var slot_staging: Control
var item_hover_card: PanelContainer
var item_hover_title: Label
var item_hover_body: Label
var drag_status_panel: PanelContainer
var drag_status_label: Label
var _world_drop_handler: Callable
var _standalone_ui_built := false
var _drag_feedback_active := false
var _hovered_item_slot: Control = null

const SLOT_SIZE := 78
const BASE_INVENTORY_CAPACITY := 12
const SLOT_SCENE: PackedScene = preload("res://scenes/ItemSlot.tscn")
const ITEM_MODEL_ICON_SCENE: PackedScene = preload("res://assets/art/ui/inventory_3d/ui_item_model_icon_root_v001.tscn")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 350
	if not FateCardGameBridge.card_list_changed.is_connected(_refresh_run_fate_ui):
		FateCardGameBridge.card_list_changed.connect(_refresh_run_fate_ui)
	if standalone_mode:
		# 保留可交互物品格信号契约，完整战术背包则在首次打开时创建。
		_prepare_staged_inventory_slots()
		return
	_build_inventory_grid()
	_build_insurance_grid()
	_set_panel_positions()
	_set_inventory_panel_visibility(false)


func _ensure_standalone_ui() -> void:
	if not standalone_mode or _standalone_ui_built:
		return
	_setup_standalone_panels()
	_build_inventory_grid()
	_build_insurance_grid()
	_setup_interaction_feedback()
	UIStyleFactory.apply_tactical_tree(self)
	_set_panel_positions()
	_standalone_ui_built = true
	_set_inventory_panel_visibility(false)


func _process(_delta: float) -> void:
	if item_hover_card != null and item_hover_card.visible:
		_position_item_hover_card()
	# 没有可见的悬浮卡时让 _process 进入睡眠。
	if item_hover_card == null or not item_hover_card.visible:
		set_process(false)


func _prepare_staged_inventory_slots() -> void:
	if slot_staging != null:
		return
	slot_staging = Control.new()
	slot_staging.name = "InventorySlotStaging"
	slot_staging.visible = false
	slot_staging.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slot_staging)
	for i in inventory_capacity:
		var slot := _create_slot()
		slot.name = "InvSlot_%d" % i
		slot.set_meta("slot_kind", "inventory")
		slot_staging.add_child(slot)
		_slots.append(slot)
		_connect_slot_signals(slot, i, true)

## 独立模式：创建自己的Panel和Grid层级
func _setup_standalone_panels() -> void:
	backdrop = ColorRect.new()
	backdrop.name = "InventoryBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.008, 0.012, 0.020, 0.72)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	inventory_shell = PanelContainer.new()
	inventory_shell.name = "CharacterInventoryShell"
	# 角色装备是核心管理界面，使用接近全屏的响应式区域，避免固定 1000x620
	# 在窄窗口中裁切武器配件、背包装备和快捷栏。
	inventory_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inventory_shell.offset_left = 14.0
	inventory_shell.offset_top = 14.0
	inventory_shell.offset_right = -14.0
	inventory_shell.offset_bottom = -14.0
	inventory_shell.custom_minimum_size = Vector2.ZERO
	inventory_shell.add_theme_stylebox_override(
		"panel", UIStyleFactory.make_panel_with_border(0, UIPalette.BORDER_NORMAL, 8, 2)
	)
	inventory_shell.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(inventory_shell)

	var shell_margin := MarginContainer.new()
	shell_margin.add_theme_constant_override("margin_left", 20)
	shell_margin.add_theme_constant_override("margin_top", 18)
	shell_margin.add_theme_constant_override("margin_right", 20)
	shell_margin.add_theme_constant_override("margin_bottom", 18)
	inventory_shell.add_child(shell_margin)
	var columns := HBoxContainer.new()
	columns.name = "InventoryColumns"
	columns.add_theme_constant_override("separation", 18)
	shell_margin.add_child(columns)

	equipment_panel = PanelContainer.new()
	equipment_panel.name = "CharacterEquipmentPanel"
	equipment_panel.custom_minimum_size = Vector2(420, 0)
	equipment_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equipment_panel.size_flags_stretch_ratio = 0.42
	equipment_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equipment_panel.add_theme_stylebox_override(
		"panel", UIStyleFactory.make_panel_with_border(1, Color(0.32, 0.50, 0.68), 7, 1)
	)
	columns.add_child(equipment_panel)
	var equipment_margin := MarginContainer.new()
	equipment_margin.add_theme_constant_override("margin_left", 12)
	equipment_margin.add_theme_constant_override("margin_top", 10)
	equipment_margin.add_theme_constant_override("margin_right", 12)
	equipment_margin.add_theme_constant_override("margin_bottom", 10)
	equipment_panel.add_child(equipment_margin)
	# 左侧装备栏内容用 ScrollContainer 兜底：fate 描述变长或字号变化时允许滚动而不是溢出 shell。
	var equipment_scroll := ScrollContainer.new()
	equipment_scroll.name = "EquipmentScroll"
	equipment_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	equipment_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	equipment_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	equipment_margin.add_child(equipment_scroll)
	var equipment_vbox := VBoxContainer.new()
	equipment_vbox.name = "EquipmentVBox"
	equipment_vbox.add_theme_constant_override("separation", 6)
	equipment_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equipment_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equipment_scroll.add_child(equipment_vbox)
	var equipment_title := Label.new()
	equipment_title.name = "CharacterEquipmentTitle"
	equipment_title.text = "角色装备"
	equipment_title.add_theme_font_size_override("font_size", 22)
	equipment_title.add_theme_color_override("font_color", Color(0.86, 0.94, 1.0))
	equipment_vbox.add_child(equipment_title)
	var attribute_label := Label.new()
	attribute_label.text = "当前作战属性"
	attribute_label.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	equipment_vbox.add_child(attribute_label)
	equipment_hp_label = Label.new()
	equipment_hp_label.name = "EquipmentHPLabel"
	equipment_hp_label.text = "生命 100 / 100"
	equipment_vbox.add_child(equipment_hp_label)
	equipment_hp_bar = ProgressBar.new()
	equipment_hp_bar.name = "EquipmentHPBar"
	equipment_hp_bar.custom_minimum_size = Vector2(0, 20)
	equipment_hp_bar.max_value = 100
	equipment_hp_bar.value = 100
	equipment_hp_bar.show_percentage = false
	equipment_hp_bar.add_theme_stylebox_override("background", UIStyleFactory.make_progress_fill(Color(0.12, 0.04, 0.05)))
	equipment_hp_bar.add_theme_stylebox_override("fill", UIStyleFactory.make_progress_fill(Color(0.90, 0.10, 0.12)))
	equipment_vbox.add_child(equipment_hp_bar)
	var weapon_title := Label.new()
	weapon_title.text = "武器栏 · 左主武器 / 右副武器"
	weapon_title.add_theme_color_override("font_color", UIPalette.TEXT_GOLD)
	equipment_vbox.add_child(weapon_title)
	var weapon_slots_row := HBoxContainer.new()
	weapon_slots_row.add_theme_constant_override("separation", 10)
	equipment_vbox.add_child(weapon_slots_row)
	for weapon_slot_index in range(2):
		var slot_box := VBoxContainer.new()
		slot_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		weapon_slots_row.add_child(slot_box)
		var slot_caption := Label.new()
		slot_caption.text = "[1] 主武器" if weapon_slot_index == 0 else "[2] 副武器"
		slot_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_caption.add_theme_font_size_override("font_size", 12)
		slot_box.add_child(slot_caption)
		var weapon_slot := _create_slot()
		weapon_slot.name = "MainWeaponEquipmentSlot" if weapon_slot_index == 0 else "SecondaryWeaponEquipmentSlot"
		weapon_slot.custom_minimum_size = Vector2(88, 88)
		weapon_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if weapon_slot.has_method("set_slot_index"):
			weapon_slot.call("set_slot_index", weapon_slot_index)
		weapon_slot.set_meta("slot_kind", "weapon_%d" % weapon_slot_index)
		weapon_slot.set_meta("weapon_slot_index", weapon_slot_index)
		_connect_slot_signals(weapon_slot, weapon_slot_index, false)
		slot_box.add_child(weapon_slot)
		equipment_weapon_slots.append(weapon_slot)
		var weapon_label := Label.new()
		weapon_label.name = "MainWeaponEquipmentLabel" if weapon_slot_index == 0 else "SecondaryWeaponEquipmentLabel"
		weapon_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		weapon_label.add_theme_font_size_override("font_size", 11)
		weapon_label.text = "未装备"
		slot_box.add_child(weapon_label)
		equipment_weapon_labels.append(weapon_label)
		var attachment_title := Label.new()
		attachment_title.text = "枪械配件 · 点击拆卸"
		attachment_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		attachment_title.add_theme_font_size_override("font_size", 10)
		attachment_title.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
		slot_box.add_child(attachment_title)
		var attachment_grid := GridContainer.new()
		attachment_grid.name = "WeaponAttachmentGrid_%d" % weapon_slot_index
		attachment_grid.columns = 3
		attachment_grid.add_theme_constant_override("h_separation", 4)
		attachment_grid.add_theme_constant_override("v_separation", 4)
		attachment_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot_box.add_child(attachment_grid)
		var weapon_attachment_slots: Array[Control] = []
		for attachment_slot_type in AssemblyNode.PUBLIC_ATTACHMENT_SLOTS:
			var attachment_slot := _create_slot()
			attachment_slot.name = "Weapon%dAttachment_%s" % [
				weapon_slot_index,
				AssemblyNode.get_attachment_slot_key(attachment_slot_type).capitalize(),
			]
			attachment_slot.custom_minimum_size = Vector2(40, 40)
			attachment_slot.set_meta("slot_kind", "attachment_%d_%d" % [weapon_slot_index, attachment_slot_type])
			attachment_slot.set_meta("weapon_slot_index", weapon_slot_index)
			attachment_slot.set_meta("attachment_slot_type", attachment_slot_type)
			attachment_slot.set_meta("accepted_subtype", _attachment_item_subtype(attachment_slot_type))
			if attachment_slot.has_method("set_slot_index"):
				attachment_slot.call("set_slot_index", attachment_slot_type)
			_connect_slot_signals(attachment_slot, attachment_slot_type, false)
			if attachment_slot.has_signal("slot_clicked"):
				attachment_slot.slot_clicked.connect(
					_on_attachment_slot_clicked.bind(weapon_slot_index, attachment_slot_type)
				)
			var abbreviation := Label.new()
			abbreviation.name = "AttachmentSlotCaption"
			abbreviation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			abbreviation.mouse_filter = Control.MOUSE_FILTER_IGNORE
			abbreviation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			abbreviation.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			abbreviation.add_theme_font_size_override("font_size", 9)
			abbreviation.text = AssemblyNode.get_attachment_slot_display_name(attachment_slot_type)
			attachment_slot.add_child(abbreviation)
			attachment_grid.add_child(attachment_slot)
			weapon_attachment_slots.append(attachment_slot)
		equipment_attachment_slots.append(weapon_attachment_slots)
	equipment_weapon_slot = equipment_weapon_slots[0]
	equipment_weapon_label = equipment_weapon_labels[0]
	# 装备栏加宽后，将背包装备与快捷栏并排，避免底部内容被纵向裁切。
	var equipment_support_row := HBoxContainer.new()
	equipment_support_row.name = "EquipmentSupportRow"
	equipment_support_row.add_theme_constant_override("separation", 18)
	equipment_support_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equipment_vbox.add_child(equipment_support_row)
	var backpack_section := VBoxContainer.new()
	backpack_section.name = "BackpackEquipmentSection"
	backpack_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	backpack_section.size_flags_stretch_ratio = 0.48
	equipment_support_row.add_child(backpack_section)
	var backpack_title := Label.new()
	backpack_title.text = "背包装备 · 提供额外物品格"
	backpack_title.add_theme_color_override("font_color", Color(0.52, 0.88, 1.0))
	backpack_title.add_theme_font_size_override("font_size", 12)
	backpack_section.add_child(backpack_title)
	var backpack_row := HBoxContainer.new()
	backpack_row.add_theme_constant_override("separation", 10)
	backpack_section.add_child(backpack_row)
	equipment_backpack_slot = _create_slot()
	equipment_backpack_slot.name = "BackpackEquipmentSlot"
	equipment_backpack_slot.custom_minimum_size = Vector2(76, 76)
	equipment_backpack_slot.set_meta("slot_kind", "backpack")
	if equipment_backpack_slot.has_method("set_slot_index"):
		equipment_backpack_slot.call("set_slot_index", 0)
	_connect_slot_signals(equipment_backpack_slot, 0, false)
	backpack_row.add_child(equipment_backpack_slot)
	equipment_backpack_label = Label.new()
	equipment_backpack_label.name = "BackpackEquipmentLabel"
	equipment_backpack_label.text = "未装备\n基础容量 12格"
	equipment_backpack_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	equipment_backpack_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	backpack_row.add_child(equipment_backpack_label)
	var quick_section := VBoxContainer.new()
	quick_section.name = "QuickItemEquipmentSection"
	quick_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quick_section.size_flags_stretch_ratio = 0.52
	equipment_support_row.add_child(quick_section)
	var quick_title := Label.new()
	quick_title.text = "物品快捷栏 · 从背包拖入"
	quick_title.add_theme_color_override("font_color", Color(0.44, 0.90, 0.76))
	quick_title.add_theme_font_size_override("font_size", 12)
	quick_section.add_child(quick_title)
	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 10)
	quick_section.add_child(quick_row)
	for quick_index in range(2):
		var quick_slot := _create_slot()
		quick_slot.name = "QuickItemSlot_%d" % quick_index
		quick_slot.custom_minimum_size = Vector2(66, 66)
		quick_slot.set_meta("slot_kind", "quick_%d" % quick_index)
		quick_slot.set_meta("drag_disabled", true)
		if quick_slot.has_method("set_slot_index"):
			quick_slot.call("set_slot_index", quick_index)
		_connect_slot_signals(quick_slot, quick_index, false)
		quick_row.add_child(quick_slot)
		quick_item_slots.append(quick_slot)
	var reserved := Label.new()
	reserved.text = "防具槽　— 未开放\n战术槽　— 未开放\n护符槽　— 未开放"
	reserved.add_theme_color_override("font_color", UIPalette.TEXT_DISABLED)
	reserved.add_theme_font_size_override("font_size", 13)
	equipment_vbox.add_child(reserved)
	equipment_fate_label = Label.new()
	equipment_fate_label.name = "RunFateStateLabel"
	equipment_fate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	equipment_fate_label.add_theme_font_size_override("font_size", 12)
	equipment_fate_label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.96))
	equipment_vbox.add_child(equipment_fate_label)
	_refresh_run_fate_ui()

	inventory_panel = PanelContainer.new()
	inventory_panel.name = "InventoryPanel"
	inventory_panel.add_theme_stylebox_override(
		"panel",
		UIStyleFactory.make_panel_with_border(1, UIPalette.BORDER_NORMAL, 6, 1),
	)
	inventory_panel.custom_minimum_size = Vector2(620, 0)
	inventory_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_panel.size_flags_stretch_ratio = 0.58
	inventory_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	columns.add_child(inventory_panel)

	var inventory_margin := MarginContainer.new()
	inventory_margin.add_theme_constant_override("margin_left", 14)
	inventory_margin.add_theme_constant_override("margin_top", 12)
	inventory_margin.add_theme_constant_override("margin_right", 14)
	inventory_margin.add_theme_constant_override("margin_bottom", 12)
	inventory_panel.add_child(inventory_margin)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	inventory_margin.add_child(vbox)
	var header := HBoxContainer.new()
	vbox.add_child(header)
	capacity_label = Label.new()
	capacity_label.name = "CapacityLabel"
	capacity_label.text = "背包容量 0/12"
	capacity_label.add_theme_font_size_override("font_size", 22)
	capacity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(capacity_label)
	sort_button = Button.new()
	sort_button.name = "SortButton"
	sort_button.text = "整理背包"
	UIStyleFactory.apply_button_style(sort_button, UIStyleFactory.make_button_style())
	sort_button.pressed.connect(_on_sort_pressed)
	header.add_child(sort_button)
	var shortcut_hint := Label.new()
	shortcut_hint.name = "ShortcutHint"
	shortcut_hint.text = "拖拽换位 · 枪械拖到左侧装备 · 拖出面板或拖到红区丢弃"
	shortcut_hint.add_theme_font_size_override("font_size", 12)
	shortcut_hint.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	vbox.add_child(shortcut_hint)

	inventory_grid = GridContainer.new()
	inventory_grid.name = "InventoryGrid"
	inventory_grid.columns = 6
	inventory_grid.add_theme_constant_override("h_separation", 8)
	inventory_grid.add_theme_constant_override("v_separation", 8)
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
	insurance_panel.custom_minimum_size = Vector2(0, 96)
	insurance_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(insurance_panel)
	
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

	drop_zone = _create_slot()
	drop_zone.name = "WorldDropZone"
	drop_zone.custom_minimum_size = Vector2(0, 62)
	if drop_zone.has_method("set_slot_index"):
		drop_zone.call("set_slot_index", -1)
	drop_zone.set_meta("slot_kind", "drop")
	var drop_count_label := drop_zone.get_node_or_null("CountLabel") as Label
	if drop_count_label != null:
		drop_count_label.visible = false
	drop_zone.add_theme_stylebox_override(
		"normal", UIStyleFactory.make_panel_with_border(2, Color(0.88, 0.16, 0.18), 5, 2)
	)
	_connect_slot_signals(drop_zone, -1, false)
	var drop_label := Label.new()
	drop_label.text = "丢弃到地面　拖到这里，或直接拖出装备界面"
	drop_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drop_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drop_label.add_theme_color_override("font_color", Color(1.0, 0.46, 0.42))
	drop_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_zone.add_child(drop_label)
	vbox.add_child(drop_zone)


func _setup_interaction_feedback() -> void:
	item_hover_card = PanelContainer.new()
	item_hover_card.name = "ItemHoverCard"
	item_hover_card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	item_hover_card.custom_minimum_size = Vector2(350, 0)
	item_hover_card.size = Vector2(350, 180)
	item_hover_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_hover_card.z_index = 900
	item_hover_card.visible = false
	var hover_style := UIStyleFactory.make_panel_with_border(0, Color(0.28, 0.86, 1.0), 7, 2)
	hover_style.set_content_margin_all(12)
	item_hover_card.add_theme_stylebox_override("panel", hover_style)
	var hover_box := VBoxContainer.new()
	hover_box.add_theme_constant_override("separation", 6)
	item_hover_card.add_child(hover_box)
	item_hover_title = Label.new()
	item_hover_title.add_theme_font_size_override("font_size", 18)
	item_hover_title.add_theme_color_override("font_color", UIPalette.TEXT_GOLD)
	hover_box.add_child(item_hover_title)
	item_hover_body = Label.new()
	item_hover_body.custom_minimum_size = Vector2(326, 0)
	item_hover_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item_hover_body.add_theme_font_size_override("font_size", 13)
	item_hover_body.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	hover_box.add_child(item_hover_body)
	add_child(item_hover_card)

	drag_status_panel = PanelContainer.new()
	drag_status_panel.name = "DragStatusPanel"
	drag_status_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	drag_status_panel.position = Vector2(-230, 78)
	drag_status_panel.custom_minimum_size = Vector2(460, 54)
	drag_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_status_panel.z_index = 950
	drag_status_panel.visible = false
	var drag_style := UIStyleFactory.make_panel_with_border(0, Color(0.30, 0.88, 1.0), 6, 2)
	drag_style.set_content_margin_all(9)
	drag_status_panel.add_theme_stylebox_override("panel", drag_style)
	drag_status_label = Label.new()
	drag_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drag_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drag_status_label.add_theme_color_override("font_color", Color(0.70, 0.96, 1.0))
	drag_status_panel.add_child(drag_status_label)
	add_child(drag_status_panel)

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
	if _weapon_owner != null and is_instance_valid(_weapon_owner) and _weapon_owner.has_signal("hp_changed"):
		if _weapon_owner.hp_changed.is_connected(_on_owner_hp_changed):
			_weapon_owner.hp_changed.disconnect(_on_owner_hp_changed)
	_weapon_owner = owner
	if _weapon_owner != null and _weapon_owner.has_signal("weapon_instance_changed"):
		if not _weapon_owner.weapon_instance_changed.is_connected(_on_equipped_weapon_instance_changed):
			_weapon_owner.weapon_instance_changed.connect(_on_equipped_weapon_instance_changed)
	if _weapon_owner != null and _weapon_owner.has_signal("hp_changed"):
		if not _weapon_owner.hp_changed.is_connected(_on_owner_hp_changed):
			_weapon_owner.hp_changed.connect(_on_owner_hp_changed)
		_on_owner_hp_changed(
			int(_weapon_owner.get("current_hp")), int(_weapon_owner.get("max_hp"))
		)
	_refresh_equipment_ui()
	_refresh_inventory_ui()


func set_backpack_owner(owner: Node) -> void:
	if _backpack_owner != null and is_instance_valid(_backpack_owner) and _backpack_owner.has_signal(
		"backpack_equipment_changed"
	):
		if _backpack_owner.backpack_equipment_changed.is_connected(_on_backpack_equipment_changed):
			_backpack_owner.backpack_equipment_changed.disconnect(_on_backpack_equipment_changed)
	_backpack_owner = owner
	if _backpack_owner != null and _backpack_owner.has_signal("backpack_equipment_changed"):
		if not _backpack_owner.backpack_equipment_changed.is_connected(_on_backpack_equipment_changed):
			_backpack_owner.backpack_equipment_changed.connect(_on_backpack_equipment_changed)
	_refresh_backpack_equipment_ui()


func set_world_drop_handler(handler: Callable) -> void:
	_world_drop_handler = handler


func set_quick_item_assignments(item_ids: Array[String]) -> void:
	for index in range(2):
		quick_item_ids[index] = item_ids[index] if index < item_ids.size() else ""
	_refresh_quick_item_ui()

## 显示/隐藏背包面板
func _set_inventory_panel_visibility(visible: bool) -> void:
	var was_visible := is_inventory_open()
	if backdrop:
		backdrop.visible = visible
	if inventory_shell:
		inventory_shell.visible = visible
	elif inventory_panel:
		inventory_panel.visible = visible
	# 物品悬浮卡位置更新只在背包打开且悬浮卡可见时才有意义。
	# 关闭背包后立即关掉 _process，避免全屏常驻每帧跑空函数。
	set_process(visible and item_hover_card != null and item_hover_card.visible)
	if visible and inventory_shell:
		# 战斗 HUD 会在背包之后动态创建。GUI 命中同样受同级节点顺序影响，
		# 因此打开时提升整个背包根节点，避免底部丢弃区被 HUD 抢走拖拽事件。
		move_to_front()
		inventory_shell.move_to_front()
	if was_visible != visible:
		inventory_open_changed.emit(visible)


func set_inventory_panel_open(opened: bool) -> void:
	if opened:
		_ensure_standalone_ui()
	_set_inventory_panel_visibility(opened)
	if opened:
		_refresh_inventory_ui()
		_refresh_insurance_ui()
		_refresh_equipment_ui()


func toggle_inventory_panel() -> void:
	set_inventory_panel_open(not is_inventory_open())


func is_inventory_open() -> bool:
	return (
		inventory_shell != null and inventory_shell.visible
		or inventory_shell == null and inventory_panel != null and inventory_panel.visible
	)

## 构建背包格子
func _build_inventory_grid() -> void:
	var target_capacity := (
		int(_inventory_module.get_capacity())
		if _inventory_module != null and _inventory_module.has_method("get_capacity")
		else inventory_capacity
	)
	inventory_capacity = target_capacity
	if _slots.size() == target_capacity:
		for slot in _slots:
			if slot.get_parent() != inventory_grid:
				slot.reparent(inventory_grid)
			_apply_inventory_slot_frame(slot, bool(slot.has_meta("slot_item")))
		return
	for slot in _slots:
		if slot != null and is_instance_valid(slot):
			slot.queue_free()
	_slots.clear()
	
	for i in target_capacity:
		var slot := _create_slot()
		slot.name = "InvSlot_%d" % i
		slot.set_meta("slot_kind", "inventory")
		slot.set_meta("backpack_bonus_slot", i >= BASE_INVENTORY_CAPACITY)
		inventory_grid.add_child(slot)
		_slots.append(slot)
		_connect_slot_signals(slot, i, true)
		_apply_inventory_slot_frame(slot, false)

## 构建保险格
func _build_insurance_grid() -> void:
	for child in insurance_grid.get_children():
		child.queue_free()
	_insurance_slots.clear()
	
	for i in insurance_capacity:
		var slot := _create_slot()
		slot.name = "InsSlot_%d" % i
		slot.set_meta("slot_kind", "insurance")
		insurance_grid.add_child(slot)
		_insurance_slots.append(slot)
		_connect_slot_signals(slot, i, false)

## 连接格子的点击信号
func _connect_slot_signals(slot: Control, idx: int, is_inventory: bool) -> void:
	if slot.has_method("set_slot_index"):
		slot.call("set_slot_index", idx)
	var kind := str(slot.get_meta("slot_kind", "inventory" if is_inventory else "insurance"))
	if kind in ["inventory", "insurance"] and slot.has_signal("slot_clicked"):
		slot.slot_clicked.connect(_on_slot_clicked.bind(is_inventory))
	if kind in ["inventory", "insurance"] and slot.has_signal("slot_right_clicked"):
		slot.slot_right_clicked.connect(_on_slot_right_clicked.bind(is_inventory))
	if slot.has_signal("slot_drop_received"):
		slot.slot_drop_received.connect(_on_slot_drop_received)
	if slot.has_signal("slot_drag_ended_outside"):
		slot.slot_drag_ended_outside.connect(_on_slot_drag_ended_outside)
	if slot.has_signal("slot_drag_started"):
		slot.slot_drag_started.connect(_on_slot_drag_started)
	if slot.has_signal("slot_drag_finished"):
		slot.slot_drag_finished.connect(_on_slot_drag_finished)
	if not slot.has_meta("inventory_hover_connected"):
		slot.mouse_entered.connect(_on_slot_mouse_entered.bind(slot))
		slot.mouse_exited.connect(_on_slot_mouse_exited.bind(slot))
		slot.set_meta("inventory_hover_connected", true)

func _create_slot() -> Control:
	var slot: Control
	if SLOT_SCENE != null:
		slot = SLOT_SCENE.instantiate() as Control
	else:
		slot = TextureRect.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	# 背景色：空格子深色，有物品稍亮
	slot.add_theme_stylebox_override("normal", UIStyleFactory.make_slot_style(false))

	# 悬停高亮
	slot.add_theme_stylebox_override("hover", UIStyleFactory.make_slot_style(true))

	return slot

## 设置面板位置（右上角）
func _set_panel_positions() -> void:
	if inventory_shell != null:
		return
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
	if _inventory_module == null or inventory_grid == null:
		return
	var cap: int = _inventory_module.get_capacity()
	if _slots.size() != cap:
		_build_inventory_grid()
	
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
	var bonus := maxi(0, cap - BASE_INVENTORY_CAPACITY)
	capacity_label.text = "背包容量 %d / %d　基础%d + 装备%d" % [
		used, cap, BASE_INVENTORY_CAPACITY, bonus,
	]

## 刷新保险格UI
func _refresh_insurance_ui() -> void:
	if _insurance_module == null or insurance_grid == null:
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
	var key_event := event as InputEventKey
	# A held I/Tab key emits echo events. Treating those as fresh actions can open
	# the inventory and immediately close it again before the player sees it.
	if key_event != null and key_event.echo:
		return
	var inventory_pressed := event.is_action_pressed("ui_inventory")
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
	slot.set_meta("drag_payload", {"item": item.duplicate(true), "count": count})
	slot.set_meta("slot_item", item.duplicate(true))
	slot.set_meta("slot_count", count)
	
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
	
	# 高亮边框表示有物品；装备背包提供的扩展格始终保留青绿色识别框。
	_apply_inventory_slot_frame(slot, true)
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
	else:
		pass
	# 正式界面只使用自定义详情卡，避免引擎默认 Tooltip 延迟出现后叠成两层。
	slot.tooltip_text = ""

## 清空格子
func _clear_slot(slot: Control) -> void:
	if slot is TextureRect:
		(slot as TextureRect).texture = null
	if slot.has_node("CountLabel"):
		var cl: Label = slot.get_node("CountLabel") as Label
		cl.visible = false
	if slot.has_meta("drag_payload"):
		slot.remove_meta("drag_payload")
	if slot.has_meta("slot_item"):
		slot.remove_meta("slot_item")
	if slot.has_meta("slot_count"):
		slot.remove_meta("slot_count")
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
	_apply_inventory_slot_frame(slot, false)


func _apply_inventory_slot_frame(slot: Control, filled: bool) -> void:
	if slot == null:
		return
	if not bool(slot.get_meta("backpack_bonus_slot", false)):
		slot.add_theme_stylebox_override(
			"normal",
			UIStyleFactory.make_slot_filled_style() if filled else UIStyleFactory.make_slot_style(false)
		)
		return
	var style := UIStyleFactory.make_panel_with_border(
		1 if filled else 0,
		Color(0.26, 0.92, 0.72) if filled else Color(0.18, 0.68, 0.58),
		4,
		2
	)
	style.bg_color = Color(0.035, 0.12, 0.12, 0.96) if filled else Color(0.018, 0.075, 0.078, 0.92)
	slot.add_theme_stylebox_override("normal", style)


func _item_glyph(item: Dictionary) -> String:
	if item.get("id", "") == "item_room_key":
		return "KEY"
	if item.get("type", "") == "equipment" and item.get("subtype", "") == "backpack":
		return "BAG"
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


func _weapon_hover_text(item: Dictionary) -> String:
	var instance_id := str(item.get("weapon_instance_id", ""))
	var upgrades: Variant = item.get("fate_upgrades", [])
	var upgrade_list: Array = upgrades if upgrades is Array else []
	var capacity := int(item.get("fate_slot_capacity", 8))
	var lines: Array[String] = [
		"%s　#%s" % [item.get("name", item.get("id", "武器")), instance_id.right(6).to_upper()],
		"★ 星星命运 %d/%d（永久）" % [upgrade_list.size(), capacity],
	]
	if upgrade_list.is_empty():
		lines.append("命运卡：尚未刻印")
	else:
		lines.append("已装星星命运：")
		for raw_upgrade in upgrade_list:
			if not raw_upgrade is Dictionary:
				continue
			var upgrade := raw_upgrade as Dictionary
			var stable_id := str(upgrade.get("stable_card_id", ""))
			var card := FateCardPresets.get_by_card_id(stable_id)
			if card != null and str(upgrade.get("orientation", "UPRIGHT")) == "REVERSED":
				card.set_orientation(FateCard.Orientation.REVERSED, float(upgrade.get("orientation_roll", 0.75)))
			var card_name := card.card_name if card != null else stable_id
			var summary := _fate_summary(card.short_description if card != null else "效果已刻印")
			var orientation_text := card.orientation_name() if card != null else str(upgrade.get("orientation", "UPRIGHT"))
			lines.append("%02d　★ %s·%s｜%s" % [
				int(upgrade.get("slot_index", lines.size() - 2)), card_name, orientation_text, summary,
			])
	lines.append("装配可更换，不占命运槽")
	var instance := WeaponInstance.from_item(item)
	if instance != null:
		var presentation := instance.get_presentation_snapshot()
		var installed: Array[String] = []
		for raw_entry in presentation.get("attachment_layout", []):
			if raw_entry is Dictionary and not str((raw_entry as Dictionary).get("installed_item_id", "")).is_empty():
				var attachment_item := ItemRegistry.get_instance().get_item(str((raw_entry as Dictionary).get("installed_item_id", "")))
				installed.append("%s:%s" % [(raw_entry as Dictionary).get("display_name", "配件"), attachment_item.get("name", "未知")])
		lines.append("枪械配件：%s" % ("无" if installed.is_empty() else " / ".join(installed)))
	lines.append("拖到左侧装备 · 拖到红区或面板外丢弃")
	return "\n".join(lines)


func _fate_summary(text: String) -> String:
	var compact := text.replace(" ", "").replace("，", "").replace(",", "")
	return compact.left(10)


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
	_refresh_quick_item_ui()
	inventory_changed.emit()

func _on_capacity_changed(current: int, maximum: int) -> void:
	_refresh_inventory_ui()

func _on_insurance_changed() -> void:
	_refresh_insurance_ui()
	inventory_changed.emit()  ## 保险格变化也触发刷新通知


func _on_weapon_tree_changed() -> void:
	_refresh_inventory_ui()
	_refresh_equipment_ui()


func _on_equipped_weapon_instance_changed(_snapshot: Dictionary) -> void:
	_refresh_inventory_ui()
	_refresh_equipment_ui()


func _on_backpack_equipment_changed(_snapshot: Dictionary) -> void:
	_refresh_inventory_ui()
	_refresh_backpack_equipment_ui()


func _on_owner_hp_changed(current: int, maximum: int) -> void:
	if equipment_hp_bar != null:
		equipment_hp_bar.max_value = maxi(1, maximum)
		equipment_hp_bar.value = clampi(current, 0, maximum)
	if equipment_hp_label != null:
		equipment_hp_label.text = "生命 %d / %d" % [current, maximum]


func _refresh_equipment_ui() -> void:
	_refresh_run_fate_ui()
	_refresh_backpack_equipment_ui()
	if equipment_weapon_slots.is_empty() or _weapon_owner == null or not is_instance_valid(_weapon_owner):
		return
	var active_slot := int(_weapon_owner.call("get_active_weapon_slot")) if _weapon_owner.has_method("get_active_weapon_slot") else 0
	for weapon_slot_index in range(equipment_weapon_slots.size()):
		var slot := equipment_weapon_slots[weapon_slot_index]
		var item: Dictionary = {}
		if _weapon_owner.has_method("get_equipped_weapon_item_for_slot"):
			item = _weapon_owner.call("get_equipped_weapon_item_for_slot", weapon_slot_index) as Dictionary
		elif weapon_slot_index == 0 and _weapon_owner.has_method("get_equipped_weapon_item"):
			item = _weapon_owner.call("get_equipped_weapon_item") as Dictionary
		if item.is_empty():
			_clear_slot(slot)
			equipment_weapon_labels[weapon_slot_index].text = "%s未装备" % ("主武器" if weapon_slot_index == 0 else "副武器")
			_refresh_weapon_attachment_slots(weapon_slot_index, [])
			continue
		_update_slot_with_item(slot, {"item": item, "count": 1, "slot": weapon_slot_index})
		var instance_id := str(item.get("weapon_instance_id", ""))
		var upgrades: Variant = item.get("fate_upgrades", [])
		var used: int = upgrades.size() if upgrades is Array else 0
		equipment_weapon_labels[weapon_slot_index].text = "%s%s\n#%s · 命运%d/%d" % [
			"▶ " if weapon_slot_index == active_slot else "",
			item.get("name", "武器"), instance_id.right(6).to_upper(), used,
			int(item.get("fate_slot_capacity", 8)),
		]
		var layout: Array[Dictionary] = []
		if _weapon_owner.has_method("get_weapon_attachment_layout_for_slot"):
			layout = _weapon_owner.call("get_weapon_attachment_layout_for_slot", weapon_slot_index) as Array[Dictionary]
		_refresh_weapon_attachment_slots(weapon_slot_index, layout)
	_refresh_quick_item_ui()


func _refresh_weapon_attachment_slots(weapon_slot_index: int, layout: Array[Dictionary]) -> void:
	if weapon_slot_index < 0 or weapon_slot_index >= equipment_attachment_slots.size():
		return
	var by_type: Dictionary = {}
	for entry in layout:
		by_type[int(entry.get("slot_type", -1))] = entry
	var slots := equipment_attachment_slots[weapon_slot_index] as Array
	for slot in slots:
		var slot_type := int(slot.get_meta("attachment_slot_type", -1))
		var entry := by_type.get(slot_type, {}) as Dictionary
		var supported := bool(entry.get("supported", false))
		var item_id := str(entry.get("installed_item_id", ""))
		slot.set_meta("slot_disabled", not supported)
		slot.set_meta("drag_disabled", item_id.is_empty())
		var caption := slot.get_node_or_null("AttachmentSlotCaption") as Label
		if not supported:
			_clear_slot(slot)
			slot.set_meta("slot_disabled", true)
			slot.set_meta("drag_disabled", true)
			if caption != null:
				caption.visible = true
				caption.text = "×%s" % AssemblyNode.get_attachment_slot_display_name(slot_type)
				caption.add_theme_color_override("font_color", UIPalette.TEXT_DISABLED)
			_apply_attachment_slot_frame(slot, false, true)
			continue
		if item_id.is_empty():
			_clear_slot(slot)
			slot.set_meta("slot_disabled", false)
			slot.set_meta("drag_disabled", true)
			if caption != null:
				caption.visible = true
				caption.text = AssemblyNode.get_attachment_slot_display_name(slot_type)
				caption.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
			_apply_attachment_slot_frame(slot, false, false)
			continue
		var item := ItemRegistry.get_instance().get_item(item_id)
		_update_slot_with_item(slot, {"item": item, "count": 1, "slot": slot_type})
		slot.set_meta("slot_disabled", false)
		slot.set_meta("drag_disabled", false)
		if caption != null:
			caption.visible = false
		_apply_attachment_slot_frame(slot, true, false)


func _apply_attachment_slot_frame(slot: Control, filled: bool, disabled: bool) -> void:
	var border := UIPalette.TEXT_DISABLED if disabled else Color(0.22, 0.82, 0.72) if filled else Color(0.30, 0.48, 0.58)
	var style := UIStyleFactory.make_panel_with_border(0, border, 4, 1)
	style.bg_color = Color(0.018, 0.024, 0.030, 0.72) if disabled else Color(0.025, 0.075, 0.080, 0.94)
	slot.add_theme_stylebox_override("normal", style)


func _attachment_item_subtype(slot_type: int) -> String:
	return str({
		AssemblyNode.SlotType.SCOPE: "scope",
		AssemblyNode.SlotType.MUZZLE: "muzzle",
		AssemblyNode.SlotType.MAGAZINE: "magazine",
		AssemblyNode.SlotType.STOCK: "stock",
		AssemblyNode.SlotType.TACTICAL: "external",
		AssemblyNode.SlotType.MUTATOR: "mutator",
	}.get(slot_type, ""))


func _on_attachment_slot_clicked(_slot_index: int, weapon_slot_index: int, attachment_slot_type: int) -> void:
	if weapon_slot_index >= equipment_attachment_slots.size():
		return
	var slots := equipment_attachment_slots[weapon_slot_index] as Array
	for slot in slots:
		if int(slot.get_meta("attachment_slot_type", -1)) == attachment_slot_type and slot.has_meta("slot_item"):
			attachment_slot_remove_requested.emit(weapon_slot_index, attachment_slot_type, -1)
			return


func _refresh_backpack_equipment_ui() -> void:
	if equipment_backpack_slot == null or equipment_backpack_label == null:
		return
	var item: Dictionary = {}
	if _backpack_owner != null and is_instance_valid(_backpack_owner) and _backpack_owner.has_method(
		"get_equipped_backpack_item"
	):
		item = _backpack_owner.call("get_equipped_backpack_item") as Dictionary
	if item.is_empty():
		_clear_slot(equipment_backpack_slot)
		equipment_backpack_label.text = "未装备\n基础容量 %d格" % BASE_INVENTORY_CAPACITY
		return
	_update_slot_with_item(equipment_backpack_slot, {"item": item, "count": 1, "slot": 0})
	equipment_backpack_label.text = "%s\n额外 +%d格" % [
		item.get("name", "背包"), int(item.get("extra_slots", 0)),
	]


func _refresh_quick_item_ui() -> void:
	if quick_item_slots.is_empty():
		return
	var registry := ItemRegistry.get_instance()
	for quick_index in range(quick_item_slots.size()):
		var item_id := quick_item_ids[quick_index]
		if item_id.is_empty():
			_clear_slot(quick_item_slots[quick_index])
			continue
		var item := registry.get_item(item_id)
		if item.is_empty() or str(item.get("use_action", "")).is_empty():
			quick_item_ids[quick_index] = ""
			_clear_slot(quick_item_slots[quick_index])
			continue
		var count: int = int(_inventory_module.get_item_count(item_id)) if _inventory_module != null else 0
		_update_slot_with_item(quick_item_slots[quick_index], {
			"item": item, "count": count, "slot": quick_index,
		})
		quick_item_slots[quick_index].set_meta("drag_disabled", true)


func _refresh_run_fate_ui() -> void:
	if equipment_fate_label == null:
		return
	var snapshot := FateCardGameBridge.get_scope_state_snapshot()
	var moon_cards := snapshot.get("character", []) as Array
	var sun_cards := snapshot.get("world", []) as Array
	var lines: Array[String] = [
		"☾ 月亮命运 %d张 · 角色本局" % moon_cards.size(),
	]
	lines.append_array(_format_run_fate_cards(moon_cards))
	lines.append("☀ 太阳命运 %d张 · 世界规则" % sun_cards.size())
	lines.append_array(_format_run_fate_cards(sun_cards))
	equipment_fate_label.text = "\n".join(lines)


func _format_run_fate_cards(cards: Array) -> Array[String]:
	if cards.is_empty():
		return ["  尚未获得"]
	var lines: Array[String] = []
	for index in range(mini(cards.size(), 4)):
		var card := cards[index] as Dictionary
		lines.append("  %s·%s｜%s" % [card.get("name", "未知"), card.get("orientation", "正位"), card.get("short_description", "")])
	if cards.size() > 4:
		lines.append("  另有 %d 张…" % (cards.size() - 4))
	return lines


func _on_sort_pressed() -> void:
	if _inventory_module == null or not _inventory_module.has_method("sort_items"):
		return
	_inventory_module.sort_items()
	_refresh_inventory_ui()


func _on_slot_mouse_entered(slot: Control) -> void:
	if _drag_feedback_active or slot == null or not slot.has_meta("slot_item"):
		return
	var item := slot.get_meta("slot_item") as Dictionary
	if item.is_empty():
		return
	_hovered_item_slot = slot
	_show_item_hover_card(item, int(slot.get_meta("slot_count", 1)))


func _on_slot_mouse_exited(slot: Control) -> void:
	if _hovered_item_slot != slot:
		return
	_hovered_item_slot = null
	call_deferred("_hide_item_hover_card_if_idle")


func _hide_item_hover_card_if_idle() -> void:
	if _hovered_item_slot == null and not _drag_feedback_active:
		_hide_item_hover_card()


func _show_item_hover_card(item: Dictionary, count: int = 1) -> void:
	if item_hover_card == null or item_hover_title == null or item_hover_body == null:
		return
	var item_name := str(item.get("name", item.get("id", "物品")))
	item_hover_title.text = "%s%s" % [item_name, " ×%d" % count if count > 1 else ""]
	if str(item.get("type", "")) == "weapon":
		item_hover_body.text = _weapon_hover_text(item)
	elif str(item.get("type", "")) == "equipment" and str(item.get("subtype", "")) == "backpack":
		item_hover_body.text = "背包装备 / %s\n装备后增加 %d 个物品格\n%s\n\n左键或拖入背包槽装备" % [
			item.get("rarity", "common"), int(item.get("extra_slots", 0)), item.get("description", ""),
		]
	else:
		item_hover_body.text = "%s / %s\n%s\n\n拖拽：换位或丢弃到地面" % [
			item.get("type", "物品"), item.get("rarity", "common"), item.get("description", ""),
		]
	var detail_lines := item_hover_body.text.count("\n") + 1
	var card_height := clampf(58.0 + detail_lines * 19.0, 132.0, 360.0)
	item_hover_card.custom_minimum_size = Vector2(350, card_height)
	item_hover_card.reset_size()
	item_hover_card.size = Vector2(350, card_height)
	item_hover_card.visible = true
	item_hover_card.move_to_front()
	# 悬浮卡可见后需要每帧跟随鼠标，恢复 _process。
	set_process(true)
	_position_item_hover_card()


func _hide_item_hover_card() -> void:
	if item_hover_card != null:
		item_hover_card.visible = false


func _position_item_hover_card() -> void:
	if item_hover_card == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var card_size := item_hover_card.size
	if card_size == Vector2.ZERO:
		card_size = item_hover_card.get_combined_minimum_size()
	var position := get_viewport().get_mouse_position() + Vector2(20, 18)
	if _hovered_item_slot != null and is_instance_valid(_hovered_item_slot):
		var hovered_rect := _hovered_item_slot.get_global_rect()
		position = Vector2(hovered_rect.end.x + 12.0, hovered_rect.position.y)
		if position.x + card_size.x > viewport_size.x - 8.0:
			position.x = hovered_rect.position.x - card_size.x - 12.0
	position.x = clampf(position.x, 8.0, maxf(8.0, viewport_size.x - card_size.x - 8.0))
	position.y = clampf(position.y, 8.0, maxf(8.0, viewport_size.y - card_size.y - 8.0))
	item_hover_card.global_position = position


func _on_slot_drag_started(source_index: int, source_kind: String, item: Dictionary) -> void:
	if source_kind != "inventory" and not source_kind.begins_with("weapon_") and not source_kind.begins_with("attachment_") and source_kind != "backpack":
		return
	_drag_feedback_active = true
	_hovered_item_slot = null
	_hide_item_hover_card()
	for index in _slots.size():
		if _slots[index].has_method("set_drag_feedback"):
			_slots[index].call("set_drag_feedback", true, source_kind == "inventory" and index == source_index, item, source_kind)
	for target in _equipment_drop_targets():
		if target != null and target.has_method("set_drag_feedback"):
			target.call("set_drag_feedback", true, (source_kind.begins_with("weapon_") or source_kind.begins_with("attachment_") or source_kind == "backpack") and str(target.get_meta("slot_kind", "")) == source_kind, item, source_kind)
	if drag_status_panel != null and drag_status_label != null:
		drag_status_label.text = (
			"正在卸下「%s」　蓝框入包 · 红框丢弃" % item.get("name", "武器")
			if source_kind.begins_with("weapon_") or source_kind.begins_with("attachment_") or source_kind == "backpack"
			else "正在拖拽「%s」　蓝框换位 · 绿框装备 · 红框丢弃" % item.get("name", "物品")
		)
		drag_status_panel.visible = true
		drag_status_panel.move_to_front()


func _on_slot_drag_finished(_source_index: int, _source_kind: String, _successful: bool) -> void:
	_drag_feedback_active = false
	for slot in _slots:
		if slot.has_method("set_drag_feedback"):
			slot.call("set_drag_feedback", false, false, {}, "inventory")
	for target in _equipment_drop_targets():
		if target != null and target.has_method("set_drag_feedback"):
			target.call("set_drag_feedback", false, false, {}, "inventory")
	if drag_status_panel != null:
		drag_status_panel.visible = false


func _on_slot_drop_received(
	source_index: int,
	target_index: int,
	source_kind: String,
	target_kind: String
) -> void:
	if (source_kind != "inventory" and not source_kind.begins_with("weapon_") and not source_kind.begins_with("attachment_") and source_kind != "backpack") or _inventory_module == null:
		return
	if source_kind.begins_with("attachment_"):
		if target_kind == "inventory":
			var parts := source_kind.split("_")
			if parts.size() >= 3:
				attachment_slot_remove_requested.emit(int(parts[1]), int(parts[2]), target_index)
		_refresh_inventory_ui()
		_refresh_equipment_ui()
		return
	if source_kind == "backpack":
		match target_kind:
			"inventory":
				equipped_backpack_to_inventory_requested.emit(target_index)
			"drop":
				equipped_backpack_drop_requested.emit()
		_refresh_inventory_ui()
		_refresh_backpack_equipment_ui()
		return
	if source_kind.begins_with("weapon_"):
		var weapon_slot_index := int(source_kind.trim_prefix("weapon_"))
		match target_kind:
			"inventory":
				equipped_weapon_to_inventory_requested.emit(weapon_slot_index, target_index)
			"drop":
				equipped_weapon_drop_requested.emit(weapon_slot_index)
		_refresh_inventory_ui()
		_refresh_equipment_ui()
		return
	match target_kind:
		"inventory":
			_inventory_module.move_or_swap_slots(source_index, target_index)
		"weapon_0", "weapon_1":
			var source: Dictionary = _inventory_module.get_slot(source_index)
			if not source.is_empty() and str((source.get("item", {}) as Dictionary).get("type", "")) == "weapon":
				weapon_slot_equip_requested.emit(source_index, int(target_kind.trim_prefix("weapon_")))
		_ when target_kind.begins_with("attachment_"):
			var source: Dictionary = _inventory_module.get_slot(source_index)
			var item := source.get("item", {}) as Dictionary
			var parts := target_kind.split("_")
			if str(item.get("type", "")) == "attachment" and parts.size() >= 3:
				attachment_slot_install_requested.emit(source_index, int(parts[1]), int(parts[2]))
		"backpack":
			var source: Dictionary = _inventory_module.get_slot(source_index)
			var item := source.get("item", {}) as Dictionary
			if str(item.get("type", "")) == "equipment" and str(item.get("subtype", "")) == "backpack":
				backpack_slot_equip_requested.emit(source_index)
		"quick_0", "quick_1":
			var source: Dictionary = _inventory_module.get_slot(source_index)
			var item := source.get("item", {}) as Dictionary
			if not item.is_empty() and not str(item.get("use_action", "")).is_empty():
				quick_item_assignment_requested.emit(int(target_kind.trim_prefix("quick_")), str(item.get("id", "")))
		"drop":
			_drop_inventory_slot_to_world(source_index)
	_refresh_inventory_ui()
	_refresh_equipment_ui()


func _on_slot_drag_ended_outside(source_index: int, source_kind: String) -> void:
	if (source_kind != "inventory" and not source_kind.begins_with("weapon_") and not source_kind.begins_with("attachment_") and source_kind != "backpack") or inventory_shell == null:
		return
	if inventory_shell.get_global_rect().has_point(get_viewport().get_mouse_position()):
		return
	if source_kind.begins_with("weapon_"):
		equipped_weapon_drop_requested.emit(int(source_kind.trim_prefix("weapon_")))
	elif source_kind.begins_with("attachment_"):
		return
	elif source_kind == "backpack":
		equipped_backpack_drop_requested.emit()
	else:
		_drop_inventory_slot_to_world(source_index)


func _equipment_drop_targets() -> Array[Control]:
	var targets: Array[Control] = []
	targets.append_array(equipment_weapon_slots)
	for weapon_slots in equipment_attachment_slots:
		for slot in weapon_slots:
			targets.append(slot as Control)
	if equipment_backpack_slot != null:
		targets.append(equipment_backpack_slot)
	targets.append_array(quick_item_slots)
	if drop_zone != null:
		targets.append(drop_zone)
	return targets


func _drop_inventory_slot_to_world(slot_index: int) -> bool:
	if _inventory_module == null or not _world_drop_handler.is_valid():
		return false
	var slot_data: Dictionary = _inventory_module.get_slot(slot_index)
	if slot_data.is_empty():
		return false
	var item := (slot_data.get("item", {}) as Dictionary).duplicate(true)
	var count := int(slot_data.get("count", 1))
	if not _inventory_module.remove_from_slot(slot_index, count):
		return false
	item["count"] = count
	var dropped := bool(_world_drop_handler.call(item, count))
	if not dropped:
		_inventory_module.add_item(item, count)
		return false
	item_dropped_to_world.emit(item, count)
	_refresh_inventory_ui()
	return true

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
