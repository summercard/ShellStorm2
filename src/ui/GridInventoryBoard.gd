class_name GridInventoryBoard
extends Control
## 棋盘式背包视图：背景是一个整体棋盘，物品按自身 grid_size 跨格绘制。
## 这里只负责呈现与格位索引，不写入 InventoryModule，也不处理装备位规则。

signal slot_clicked(slot_index: int)
signal slot_right_clicked(slot_index: int)
signal slot_drop_received(source_index: int, target_index: int, source_kind: String, target_kind: String)
signal slot_drag_ended_outside(source_index: int, source_kind: String)
signal slot_drag_started(source_index: int, source_kind: String, item: Dictionary)
signal slot_drag_finished(source_index: int, source_kind: String, successful: bool)

const ITEM_SLOT_SCENE: PackedScene = preload("res://scenes/ItemSlot.tscn")
const ITEM_MODEL_ICON_SCENE: PackedScene = preload("res://assets/art/ui/inventory_3d/ui_item_model_icon_root.tscn")
const CELL_SIZE := 58.0
# 连续棋盘：格子边缘直接相连，不制造独立卡片之间的缝隙。
const CELL_GAP := 0.0
const BOARD_PADDING := 0.0

var columns: int = 6
var capacity: int = 24
var cells: Array[Control] = []
var _item_visuals: Dictionary = {}
var drop_validator: Callable
var _preview_layer: Control
var _preview_item: Dictionary = {}
var _preview_anchor := -1
var _preview_rotation := 0
var _preview_valid := false
var _preview_visible := false

func configure(next_capacity: int, next_columns: int = 6) -> void:
	capacity = maxi(1, next_capacity)
	columns = maxi(1, next_columns)
	_rebuild_cells()

func get_cells() -> Array[Control]:
	return cells

func get_cell_position(index: int) -> Vector2:
	return Vector2(
		BOARD_PADDING + float(index % columns) * (CELL_SIZE + CELL_GAP),
		BOARD_PADDING + float(index / columns) * (CELL_SIZE + CELL_GAP)
	)

func get_cell_size() -> Vector2:
	return Vector2(CELL_SIZE, CELL_SIZE)

func get_anchor_from_local_position(local_position: Vector2) -> int:
	if columns <= 0:
		return -1
	var x := int(floor((local_position.x - BOARD_PADDING) / CELL_SIZE))
	var y := int(floor((local_position.y - BOARD_PADDING) / CELL_SIZE))
	if x < 0 or y < 0 or x >= columns:
		return -1
	var anchor := y * columns + x
	return anchor if anchor >= 0 and anchor < capacity else -1

func set_grid_drag_preview(item: Dictionary, anchor_index: int, rotation_quarters: int, valid: bool) -> void:
	if _preview_visible and _preview_anchor == anchor_index and _preview_rotation == rotation_quarters and _preview_valid == valid:
		return
	_preview_item = item.duplicate(true)
	_preview_anchor = anchor_index
	_preview_rotation = rotation_quarters
	_preview_valid = valid and anchor_index >= 0
	_preview_visible = true
	_update_preview_visual()

func clear_drag_preview() -> void:
	_preview_visible = false
	_preview_item.clear()
	_preview_anchor = -1
	if _preview_layer != null:
		_preview_layer.visible = false

func get_item_rect(anchor_index: int, item_size: Vector2i) -> Rect2:
	var origin := get_cell_position(anchor_index)
	return Rect2(
		origin,
		Vector2(
			float(item_size.x) * CELL_SIZE + float(maxi(0, item_size.x - 1)) * CELL_GAP,
			float(item_size.y) * CELL_SIZE + float(maxi(0, item_size.y - 1)) * CELL_GAP
		)
	)

func render_items(entries: Array) -> void:
	for visual in _item_visuals.values():
		if visual != null and is_instance_valid(visual):
			visual.queue_free()
	_item_visuals.clear()
	for cell in cells:
		cell.size = get_cell_size()
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.z_index = 0
	for entry_variant in entries:
		if not entry_variant is Dictionary:
			continue
		var entry := entry_variant as Dictionary
		var anchor := int(entry.get("slot", -1))
		var item := entry.get("item", {}) as Dictionary
		if anchor < 0 or item.is_empty():
			continue
		var size := ItemRegistry.grid_size_of(item)
		if int(entry.get("grid_rotation", 0)) % 2 == 1:
			size = Vector2i(size.y, size.x)
		var visual := Panel.new()
		visual.name = "GridItem_%d" % anchor
		visual.position = get_cell_position(anchor)
		visual.size = get_item_rect(anchor, size).size
		visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		visual.z_index = 4
		var style := StyleBoxFlat.new()
		style.bg_color = UIPalette.GRID_OCCUPIED
		style.border_color = _rarity_color(str(item.get("rarity", "common")))
		style.set_border_width_all(1)
		style.set_corner_radius_all(7)
		visual.add_theme_stylebox_override("panel", style)
		var icon := ITEM_MODEL_ICON_SCENE.instantiate() as Control
		if icon != null:
			icon.name = "ItemModelIcon3D"
			icon.set("icon_resolution", 384)
			icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			icon.offset_left = 4.0
			icon.offset_top = 4.0
			icon.offset_right = -4.0
			icon.offset_bottom = -20.0
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if icon.has_method("configure"):
				icon.call("configure", item)
			visual.add_child(icon)
		var title := Label.new()
		title.text = str(item.get("name", "物品"))
		title.position = Vector2(5, visual.size.y - 19)
		title.size = Vector2(maxf(10.0, visual.size.x - 10.0), 18)
		title.add_theme_font_size_override("font_size", 12)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0))
		title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
		title.add_theme_constant_override("shadow_offset_x", 1)
		title.add_theme_constant_override("shadow_offset_y", 1)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		visual.add_child(title)
		if size.x * size.y > 1:
			var dimensions := Label.new()
			dimensions.text = "%d×%d" % [size.x, size.y]
			dimensions.position = Vector2(visual.size.x - 34, visual.size.y - 19)
			dimensions.add_theme_font_size_override("font_size", 11)
			dimensions.add_theme_color_override("font_color", Color(0.70, 0.77, 0.82))
			dimensions.mouse_filter = Control.MOUSE_FILTER_IGNORE
			visual.add_child(dimensions)
			title.size.x -= 32
		var count := int(entry.get("count", 1))
		if count > 1:
			var count_label := Label.new()
			count_label.text = "x%d" % count
			count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			count_label.position = Vector2(-42, -visual.size.y + 3)
			count_label.size = Vector2(36, 18)
			count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			count_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.38))
			count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			visual.add_child(count_label)
		add_child(visual)
		_item_visuals[anchor] = visual
		var anchor_cell := cells[anchor] if anchor < cells.size() else null
		if anchor_cell != null:
			# One input surface spans the same rectangle as the visible item.
			anchor_cell.size = get_item_rect(anchor, size).size
			anchor_cell.z_index = 3
			var payload: Dictionary = anchor_cell.get_meta("drag_payload", {})
			if not payload.is_empty():
				payload["item"]["grid_rotation"] = int(entry.get("grid_rotation", 0))
			for y in size.y:
				for x in size.x:
					var covered := anchor + y * columns + x
					if covered != anchor and covered < cells.size():
						cells[covered].mouse_filter = Control.MOUSE_FILTER_IGNORE
			var icon_on_cell := anchor_cell.get_node_or_null("ItemModelIcon3D") as Control
			if icon_on_cell != null:
				icon_on_cell.visible = false
			var count_on_cell := anchor_cell.get_node_or_null("CountLabel") as Control
			if count_on_cell != null:
				count_on_cell.visible = false

func _update_preview_visual() -> void:
	if _preview_layer == null or not is_instance_valid(_preview_layer):
		_preview_layer = Control.new()
		_preview_layer.name = "GridDragPreviewLayer"
		_preview_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_preview_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_preview_layer.z_index = 20
		add_child(_preview_layer)
	for child in _preview_layer.get_children():
		child.queue_free()
	_preview_layer.visible = _preview_visible and _preview_anchor >= 0
	if not _preview_layer.visible:
		return
	var size := ItemRegistry.grid_size_of(_preview_item)
	if _preview_rotation % 2 == 1:
		size = Vector2i(size.y, size.x)
	var preview := Panel.new()
	preview.position = get_cell_position(_preview_anchor)
	preview.size = get_item_rect(_preview_anchor, size).size
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = UIPalette.GRID_PREVIEW_VALID if _preview_valid else UIPalette.GRID_PREVIEW_INVALID
	style.border_color = UIPalette.NEON_MINT if _preview_valid else UIPalette.DANGER_RED
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	preview.add_theme_stylebox_override("panel", style)
	_preview_layer.add_child(preview)

func _rebuild_cells() -> void:
	_preview_layer = null
	for child in get_children():
		child.queue_free()
	cells.clear()
	_item_visuals.clear()
	var rows := ceili(float(capacity) / float(columns))
	custom_minimum_size = Vector2(
		BOARD_PADDING * 2.0 + columns * CELL_SIZE + maxi(0, columns - 1) * CELL_GAP,
		BOARD_PADDING * 2.0 + rows * CELL_SIZE + maxi(0, rows - 1) * CELL_GAP
	)
	size = custom_minimum_size
	for index in capacity:
		var cell := ITEM_SLOT_SCENE.instantiate() as Control
		cell.name = "InvSlot_%d" % index
		cell.position = get_cell_position(index)
		cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
		cell.size = Vector2(CELL_SIZE, CELL_SIZE)
		cell.set_meta("slot_kind", "inventory")
		cell.set_meta("grid_board_cell", true)
		cell.set_meta("slot_index", index)
		cell.call("set_slot_index", index)
		add_child(cell)
		cells.append(cell)
		cell.mouse_entered.connect(_set_item_hover.bind(index, true))
		cell.mouse_exited.connect(_set_item_hover.bind(index, false))

func _rarity_color(rarity: String) -> Color:
	return {
		"legendary": Color(1.0, 0.50, 0.16),
		"epic": Color(0.78, 0.35, 1.0),
		"rare": Color(0.30, 0.68, 1.0),
		"uncommon": Color(0.30, 0.92, 0.66),
		"common": Color(0.58, 0.66, 0.75),
	}.get(rarity.to_lower(), Color(0.58, 0.66, 0.75))

func drop_anchor_at_mouse() -> int:
	return get_anchor_from_local_position(get_local_mouse_position())

func accepts_drop(data: Dictionary, local_position: Vector2) -> bool:
	var ok := drop_validator.is_valid() and bool(drop_validator.call(data, get_anchor_from_local_position(local_position)))
	return ok

func _set_item_hover(anchor: int, hovered: bool) -> void:
	var visual := _item_visuals.get(anchor) as Panel
	if not is_instance_valid(visual):
		return
	var style := visual.get_theme_stylebox("panel") as StyleBoxFlat
	style.set_border_width_all(2 if hovered else 1)
	style.border_color = UIPalette.INVENTORY_SELECTED if hovered else _rarity_color(str((cells[anchor].get_meta("slot_item", {}) as Dictionary).get("rarity", "common")))
