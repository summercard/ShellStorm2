class_name WardrobeMenu3D
extends CanvasLayer
## 基地衣柜全屏界面。中央保留实际 3D 角色，左右只放管理面板；
## 选择项调用 Player3D 现有外观 API，并立即进入同一份基地存档。

signal closed()
signal customization_committed(loadout: Dictionary)
signal camera_override_changed(active: bool)

const Catalog = preload("res://src/player3d/customization/AvatarCustomizationCatalog.gd")
const Persistence = preload("res://src/player3d/customization/AvatarCustomizationPersistence.gd")
const CAMERA_CLOSEUP_LOCAL_POSITION := Vector3(0.0, 1.45, -3.15)
const CAMERA_CLOSEUP_FOV := 34.0

var _player: Player3D = null
var _camera: Camera3D = null
var _saved_camera_transform := Transform3D.IDENTITY
var _saved_camera_fov := 43.0
var _previous_input_locked := false
var _camera_override_active := false
var _selected_slot := "body"
var _slot_buttons: Dictionary = {}
var _current_labels: Dictionary = {}
var _option_grid: GridContainer = null
var _options_title: Label = null
var _status_label: Label = null
var _closing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120
	_build_interface()
	call_deferred("_resolve_player")


func _process(delta: float) -> void:
	if not _camera_override_active or _player == null or _camera == null:
		return
	_camera.position = _camera.position.lerp(
		CAMERA_CLOSEUP_LOCAL_POSITION,
		clampf(delta * 12.0, 0.0, 1.0)
	)
	_camera.fov = lerpf(_camera.fov, CAMERA_CLOSEUP_FOV, clampf(delta * 10.0, 0.0, 1.0))
	_camera.look_at(_player.global_position + Vector3.UP * 0.70, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		request_close()


func _exit_tree() -> void:
	_restore_camera_and_input()


func set_player(player: Player3D) -> void:
	_player = player
	if is_node_ready():
		_begin_preview()


func request_close() -> void:
	if _closing:
		return
	_closing = true
	if _player != null and is_instance_valid(_player):
		Persistence.persist_from_player(_player)
	_restore_camera_and_input()
	closed.emit()
	queue_free()


func select_variant(slot_id: String, variant_id: String) -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if not _player.set_avatar_customization(slot_id, variant_id):
		return false
	var saved := Persistence.persist_from_player(_player)
	_status_label.text = "已保存到基地档案" if saved else "外观已应用；等待存档服务接线"
	_status_label.modulate = Color(0.50, 1.0, 0.76) if saved else Color(1.0, 0.74, 0.34)
	_refresh_current_loadout()
	_refresh_option_grid()
	customization_committed.emit(_player.get_avatar_customization())
	return true


func select_slot(slot_id: String) -> bool:
	if slot_id not in Catalog.SLOT_ORDER:
		return false
	_selected_slot = slot_id
	_refresh_category_buttons()
	_refresh_option_grid()
	return true


func get_wardrobe_snapshot() -> Dictionary:
	return {
		"selected_slot": _selected_slot,
		"slot_order": Catalog.SLOT_ORDER.duplicate(),
		"options": PlayerAvatar3D.CUSTOMIZATION_OPTIONS.duplicate(true),
		"loadout": _player.get_avatar_customization() if _player != null and is_instance_valid(_player) else {},
		"camera_override_active": _camera_override_active,
		"square_item_cells": true,
		"persistence_field": Persistence.PROFILE_FIELD,
	}


func is_camera_override_active() -> bool:
	return _camera_override_active


func _resolve_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player_3d") as Player3D
	if _player == null:
		_status_label.text = "未找到角色，衣柜暂不可用"
		_status_label.modulate = Color(1.0, 0.40, 0.32)
		return
	_begin_preview()


func _begin_preview() -> void:
	if _camera_override_active or _player == null or not is_instance_valid(_player):
		return
	Persistence.apply_saved_to_player(_player)
	_camera = _player.camera
	_previous_input_locked = _player.input_locked
	_player.set_input_locked(true)
	if _camera != null:
		_saved_camera_transform = _camera.transform
		_saved_camera_fov = _camera.fov
		_camera_override_active = true
		camera_override_changed.emit(true)
	_refresh_current_loadout()
	_refresh_category_buttons()
	_refresh_option_grid()
	_status_label.text = "外观只影响表现；碰撞、武器和角色状态保持不变"


func _restore_camera_and_input() -> void:
	if _camera_override_active and _camera != null and is_instance_valid(_camera):
		_camera.transform = _saved_camera_transform
		_camera.fov = _saved_camera_fov
	_camera_override_active = false
	camera_override_changed.emit(false)
	if _player != null and is_instance_valid(_player):
		_player.set_input_locked(_previous_input_locked)


func _build_interface() -> void:
	var root := Control.new()
	root.name = "WardrobeInterface"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var vignette := ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.005, 0.012, 0.018, 0.42)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)

	var header := PanelContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 28.0
	header.offset_top = 22.0
	header.offset_right = -28.0
	header.offset_bottom = 86.0
	header.add_theme_stylebox_override("panel", _panel_style(Color(0.16, 0.72, 0.86), Color(0.015, 0.045, 0.06, 0.94), 2))
	root.add_child(header)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 14)
	header.add_child(header_row)
	var title := Label.new()
	title.text = "基地衣柜  /  AVATAR LOADOUT"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.48, 0.94, 1.0))
	header_row.add_child(title)
	var close_button := Button.new()
	close_button.text = "保存并关闭  ESC"
	close_button.custom_minimum_size = Vector2(176, 44)
	close_button.pressed.connect(request_close)
	header_row.add_child(close_button)

	var left := PanelContainer.new()
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 28.0
	left.offset_top = 104.0
	left.offset_right = 330.0
	left.offset_bottom = -30.0
	left.add_theme_stylebox_override("panel", _panel_style(Color(0.12, 0.46, 0.58), Color(0.012, 0.030, 0.042, 0.94), 1))
	root.add_child(left)
	var current_box := VBoxContainer.new()
	current_box.add_theme_constant_override("separation", 10)
	left.add_child(current_box)
	var current_title := Label.new()
	current_title.text = "当前穿搭"
	current_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	current_title.add_theme_font_size_override("font_size", 21)
	current_title.add_theme_color_override("font_color", Color(0.44, 0.88, 0.98))
	current_box.add_child(current_title)
	for slot_id in Catalog.SLOT_ORDER:
		var row := PanelContainer.new()
		row.custom_minimum_size.y = 58.0
		row.add_theme_stylebox_override("panel", _panel_style(Color(0.10, 0.30, 0.38), Color(0.025, 0.060, 0.075, 0.90), 1))
		current_box.add_child(row)
		var label := Label.new()
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 16)
		row.add_child(label)
		_current_labels[slot_id] = label

	var center_hint := Label.new()
	center_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	center_hint.offset_left = -190.0
	center_hint.offset_top = -74.0
	center_hint.offset_right = 190.0
	center_hint.offset_bottom = -34.0
	center_hint.text = "实际角色预览 · 纯表现装配"
	center_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_hint.add_theme_color_override("font_color", Color(0.66, 0.88, 0.94))
	center_hint.add_theme_font_size_override("font_size", 16)
	root.add_child(center_hint)

	var right := PanelContainer.new()
	right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_left = -554.0
	right.offset_top = 104.0
	right.offset_right = -28.0
	right.offset_bottom = -30.0
	right.add_theme_stylebox_override("panel", _panel_style(Color(0.18, 0.62, 0.74), Color(0.012, 0.030, 0.042, 0.96), 1))
	root.add_child(right)
	var options_box := VBoxContainer.new()
	options_box.add_theme_constant_override("separation", 10)
	right.add_child(options_box)
	_options_title = Label.new()
	_options_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_options_title.add_theme_font_size_override("font_size", 21)
	_options_title.add_theme_color_override("font_color", Color(0.44, 0.92, 1.0))
	options_box.add_child(_options_title)
	var categories := GridContainer.new()
	categories.columns = 3
	categories.add_theme_constant_override("h_separation", 6)
	categories.add_theme_constant_override("v_separation", 6)
	options_box.add_child(categories)
	for slot_id in Catalog.SLOT_ORDER:
		var category := Button.new()
		category.text = Catalog.get_slot_label(slot_id)
		category.custom_minimum_size = Vector2(154, 42)
		category.pressed.connect(select_slot.bind(slot_id))
		categories.add_child(category)
		_slot_buttons[slot_id] = category
	var separator := HSeparator.new()
	options_box.add_child(separator)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	options_box.add_child(scroll)
	_option_grid = GridContainer.new()
	_option_grid.columns = 3
	_option_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option_grid.add_theme_constant_override("h_separation", 10)
	_option_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_option_grid)
	_status_label = Label.new()
	_status_label.custom_minimum_size.y = 48.0
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color(0.62, 0.82, 0.88))
	options_box.add_child(_status_label)

	UIStyleFactory.apply_tactical_tree(self)


func _refresh_current_loadout() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var loadout := _player.get_avatar_customization()
	for slot_id in Catalog.SLOT_ORDER:
		var variant_id := str(loadout.get(slot_id, ""))
		var label := _current_labels.get(slot_id) as Label
		if label != null:
			label.text = "  %s\n  %s" % [Catalog.get_slot_label(slot_id), Catalog.get_variant_label(variant_id)]
			label.add_theme_color_override("font_color", Catalog.get_variant_color(variant_id).lightened(0.28))


func _refresh_category_buttons() -> void:
	for slot_id in _slot_buttons:
		var button := _slot_buttons[slot_id] as Button
		button.disabled = str(slot_id) == _selected_slot
		button.modulate = Color(0.70, 1.0, 1.0) if button.disabled else Color.WHITE


func _refresh_option_grid() -> void:
	if _option_grid == null:
		return
	for child in _option_grid.get_children():
		_option_grid.remove_child(child)
		child.queue_free()
	_options_title.text = "%s配件" % Catalog.get_slot_label(_selected_slot)
	var current := ""
	if _player != null and is_instance_valid(_player):
		current = str(_player.get_avatar_customization().get(_selected_slot, ""))
	for variant_id in Catalog.get_options(_selected_slot):
		var cell := Button.new()
		cell.custom_minimum_size = Vector2(140, 140)
		cell.text = "%s\n%s" % ["●" if variant_id == current else "○", Catalog.get_variant_label(variant_id)]
		cell.tooltip_text = variant_id
		cell.add_theme_font_size_override("font_size", 15)
		var selected := variant_id == current
		cell.add_theme_stylebox_override(
			"normal",
			_panel_style(
				Color(0.46, 0.96, 1.0) if selected else Catalog.get_variant_color(variant_id).lightened(0.18),
				Catalog.get_variant_color(variant_id).darkened(0.48),
				3 if selected else 1
			)
		)
		cell.pressed.connect(select_variant.bind(_selected_slot, variant_id))
		_option_grid.add_child(cell)


func _panel_style(border: Color, background: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(5)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style
