class_name VaultMenu
extends CanvasLayer
const BOARD_VIEW := preload("res://src/ui/StorageBoardView.gd")
var _inventory_module: InventoryModule
var _boards: Dictionary = {}
var _models: Dictionary = {}
var _headings: Dictionary = {}
var _drag_rotation := 0
var _dragging := false
var _cancelled := false
var _drag_data: Dictionary = {}
@onready var content: VBoxContainer = $Panel/VBox/Content
@onready var status_label: Label = $Panel/VBox/StatusLabel
@onready var close_button: Button = $Panel/VBox/CloseButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_meta("ui_style_exempt", true)
	$Background.color = Color(0.008, 0.012, 0.020, 0.12)
	$Panel.hide()
	var columns := HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	columns.offset_left = 14
	columns.offset_right = -14
	columns.offset_top = 14
	columns.offset_bottom = -14
	columns.add_theme_constant_override("separation", 18)
	add_child(columns)
	_add_column(columns, "vault", "仓库")
	var center := Control.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(center)
	_add_column(columns, "inventory" if _inventory_module != null else "loadout", "背包")
	close_button.pressed.connect(queue_free)
	_build_vault_view()
	status_label.text = ""
	UiMenuFocus.ensure_focus(self)

func set_inventory_module(module: InventoryModule) -> void:
	_inventory_module = module
	if is_node_ready():
		# The runtime attaches its inventory immediately after adding this scene.
		if _boards.has("loadout"):
			_boards["inventory"] = _boards["loadout"]
			_boards.erase("loadout")
			_headings["inventory"] = _headings["loadout"]
			_headings.erase("loadout")
		_build_vault_view()

func _add_column(parent: HBoxContainer, owner: String, title: String) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 428
	var surface := UIStyleFactory.make_inventory_surface()
	surface.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", surface)
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 20)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	_headings[owner] = label
	var sort := Button.new()
	sort.text = "整理"
	sort.custom_minimum_size = Vector2(70, 34)
	_style_button(sort)
	sort.pressed.connect(func() -> void: _sort("inventory" if owner == "loadout" and _inventory_module != null else owner))
	header.add_child(sort)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var board := BOARD_VIEW.new()
	board.name = "StorageGrid_" + owner
	_boards[owner] = board
	scroll.add_child(board)
	board.slot_clicked.connect(func(at: int) -> void: _transfer(board.slot_kind, at, _other(board.slot_kind)))
	board.slot_drop_received.connect(func(a: int, b: int, c: String, d: String) -> void: _transfer(c, a, d, b))
	board.slot_drag_started.connect(func(at: int, kind: String, item: Dictionary) -> void:
		_dragging = true
		_cancelled = false
		_drag_rotation = int(item.get("grid_rotation", 0))
		_drag_data = {"source_kind": kind, "source_index": at, "item": item})
	board.slot_drag_finished.connect(func(_a: int, _b: String, _c: bool) -> void:
		_dragging = false
		_cancelled = false
		for view in _boards.values(): view.clear_drag_preview())
	board.drop_validator = func(payload: Dictionary, anchor: int) -> bool: return _can_drop(board.slot_kind, payload, anchor)
	if owner != "vault":
		status_label.reparent(box)
		status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status_label.custom_minimum_size = Vector2(0, 48)
		status_label.add_theme_font_size_override("font_size", 13)
		close_button.reparent(box)
		close_button.custom_minimum_size = Vector2(0, 36)
		close_button.text = "返回游戏    [Esc]"
		_style_button(close_button)

func _style_button(button: Button) -> void:
	var style := UIStyleFactory.make_inventory_surface(true)
	style.bg_color = UIPalette.INVENTORY_ACTION
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = UIPalette.INVENTORY_SELECTED
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_color_override("font_color", Color(0.10, 0.20, 0.27))
	button.add_theme_color_override("font_hover_color", Color(0.10, 0.20, 0.27))
	button.add_theme_color_override("font_focus_color", Color(0.10, 0.20, 0.27))

func _build_vault_view() -> void:
	for owner in _boards:
		var module: InventoryModule = _inventory_module if owner == "inventory" else BaseManager.get_storage_grid(owner)
		_models[owner] = module
		_boards[owner].present(module, owner)
		_headings[owner].text = "%s  %d/%d 格" % ["仓库" if owner == "vault" else "背包", module.get_used_area(), module.get_capacity()]

func _other(owner: String) -> String:
	return ("inventory" if _inventory_module != null else "loadout") if owner == "vault" else "vault"

func _can_drop(owner: String, payload: Dictionary, anchor: int) -> bool:
	if _cancelled or not _models.has(owner) or anchor < 0:
		return false
	var source := str(payload.get("source_kind", ""))
	if not _models.has(source):
		return false
	var model := _models[owner] as InventoryModule
	if source == owner:
		return model.can_move_or_swap_slots(int(payload.get("source_index", -1)), anchor, _drag_rotation)
	var item: Dictionary = payload.get("item", {})
	return model.can_place_item_at(item, anchor, _drag_rotation)

func _transfer(owner: String, source_anchor: int, target: String, target_anchor: int = -1) -> void:
	if _cancelled or not _models.has(owner):
		return
	var model := _models[owner] as InventoryModule
	var entry := model.get_slot(source_anchor)
	if entry.is_empty():
		return
	var success := false
	var result: Dictionary = {}
	if owner == target:
		success = model.move_or_swap_slots(source_anchor, target_anchor, _drag_rotation) if owner == "inventory" else BaseManager.move_storage_grid_item(owner, source_anchor, target_anchor, _drag_rotation)
	else:
		var index := source_anchor if owner == "inventory" else int(entry.item.get("storage_source_index", -1))
		result = BaseManager.transfer_runtime_inventory_item(owner, index, _inventory_module, target_anchor, _drag_rotation if _dragging else -1) if _inventory_module != null else BaseManager.transfer_base_storage_item(owner, index, target, target_anchor, _drag_rotation if _dragging else -1)
		success = bool(result.get("success", false))
	_build_vault_view()
	status_label.text = "已移动 · " + str(entry.item.get("name", "物品")) if success else str(result.get("reason", "此处空间不足，物品保留原位"))

func _sort(owner: String) -> void:
	if owner == "inventory":
		_inventory_module.sort_items()
	else:
		BaseManager.move_storage_grid_item(owner, -1, -1, -1, true)
	_build_vault_view()

func _process(_delta: float) -> void:
	if not _dragging or _cancelled:
		return
	for owner in _boards:
		var board: Control = _boards[owner]
		var anchor: int = board.get_anchor_from_local_position(board.get_local_mouse_position())
		if anchor >= 0:
			board.set_grid_drag_preview(_drag_data.item, anchor, _drag_rotation, _can_drop(owner, _drag_data, anchor))
		else:
			board.clear_drag_preview()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if _dragging:
			_cancelled = true
			for view in _boards.values(): view.clear_drag_preview()
		else:
			queue_free()
		get_viewport().set_input_as_handled()
	elif _dragging and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_drag_rotation = (_drag_rotation + 1) % 4
		get_viewport().set_input_as_handled()
