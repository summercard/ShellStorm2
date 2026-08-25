class_name WardrobeMenu3D
extends CanvasLayer
## 基地衣柜全屏界面。中央保留实际 3D 角色，左右只放管理面板；
## 选择项调用 Player3D 现有外观 API，并立即进入同一份基地存档。

signal closed()
signal customization_committed(loadout: Dictionary)
signal camera_override_changed(active: bool)

const Catalog = preload("res://src/player3d/customization/AvatarCustomizationCatalog.gd")
const Persistence = preload("res://src/player3d/customization/AvatarCustomizationPersistence.gd")
const ITEM_ICON_SCENE := preload("res://assets/art/ui/inventory_3d/ui_item_model_icon_root_v001.tscn")
const AVATAR_PREVIEW_SCENE := preload("res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/chr_player_capsule01_bunny01_root_top3d_v008.tscn")
const CAMERA_CLOSEUP_LOCAL_POSITION := Vector3(0.0, 1.45, -3.15)
const CAMERA_CLOSEUP_FOV := 34.0
const PREVIEW_FILL_COLOR := Color(0.78, 0.92, 1.0)
const PREVIEW_FILL_ENERGY := 7.0
const PREVIEW_FILL_RANGE_M := 4.5
const PREVIEW_FILL_TARGET_HEIGHT_M := 0.88
const PREVIEW_FILL_FRONT_DISTANCE_M := 2.2
const PREVIEW_FILL_SIDE_OFFSET_M := 0.45
const PREVIEW_FILL_HEIGHT_OFFSET_M := 0.42
const PREVIEW_FACE_FILL_ENERGY := 2.0
const PREVIEW_FACE_FILL_RANGE_M := 2.4
const PRESENTATION_SOUTH_DIRECTION := Vector3(0.0, 0.0, 1.0)

var _player: Player3D = null
var _camera: Camera3D = null
var _saved_camera_transform := Transform3D.IDENTITY
var _saved_camera_fov := 43.0
var _saved_camera_top_level := false
var _previous_input_locked := false
var _saved_aim_yaw := 0.0
var _saved_visual_root_rotation := Vector3.ZERO
var _preview_front_direction := Vector3(0.0, 0.0, -1.0)
var _camera_override_active := false
var _preview_fill: OmniLight3D = null
var _preview_face_fill: OmniLight3D = null
var _gameplay_hud: CanvasLayer = null
var _gameplay_hud_was_visible := true
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
	var preview_position := _player.global_position + Vector3.UP * CAMERA_CLOSEUP_LOCAL_POSITION.y + _preview_front_direction * absf(CAMERA_CLOSEUP_LOCAL_POSITION.z)
	_camera.global_position = preview_position
	_camera.fov = lerpf(_camera.fov, CAMERA_CLOSEUP_FOV, clampf(delta * 10.0, 0.0, 1.0))
	_camera.look_at(_player.global_position + Vector3.UP * 0.70, Vector3.UP)
	_face_player_to_preview_camera()
	_sync_preview_fill()


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
	var fill_active := _preview_fill != null and is_instance_valid(_preview_fill)
	var face_fill_active := _preview_face_fill != null and is_instance_valid(_preview_face_fill)
	var fill_target := (
		_player.global_position + Vector3.UP * PREVIEW_FILL_TARGET_HEIGHT_M
		if _player != null and is_instance_valid(_player)
		else Vector3.ZERO
	)
	var fill_to_target := (
		fill_target - _preview_fill.global_position
		if fill_active
		else Vector3.ZERO
	)
	# OmniLight3D 没有方向锥体；只要在有效范围内即可覆盖目标。
	var fill_aim_alignment := 1.0 if fill_active else 0.0
	return {
		"selected_slot": _selected_slot,
		"slot_order": Catalog.SLOT_ORDER.duplicate(),
		"options": PlayerAvatar3D.CUSTOMIZATION_OPTIONS.duplicate(true),
		"loadout": _player.get_avatar_customization() if _player != null and is_instance_valid(_player) else {},
		"camera_override_active": _camera_override_active,
		"presentation_facing_south": _is_player_facing_south(),
		"camera_on_south_side": _is_camera_on_south_side(),
		"camera_south_dot": _camera_south_dot(),
		"preview_fill_active": fill_active,
		"preview_fill_visible": fill_active and _preview_fill.visible,
		"preview_fill_energy": _preview_fill.light_energy if fill_active else 0.0,
		"preview_fill_distance_to_target": fill_to_target.length() if fill_active else 0.0,
		"preview_fill_aim_alignment": fill_aim_alignment,
		"preview_fill_player_only": fill_active \
			and _preview_fill.light_cull_mask == GameDesignConfig.RENDER_LAYER_PLAYER,
		"preview_fill_shadow_enabled": fill_active and _preview_fill.shadow_enabled,
		"preview_face_fill_active": face_fill_active,
		"preview_face_fill_visible": face_fill_active and _preview_face_fill.visible,
		"preview_face_fill_energy": _preview_face_fill.light_energy if face_fill_active else 0.0,
		"preview_face_fill_player_only": face_fill_active \
			and _preview_face_fill.light_cull_mask == GameDesignConfig.RENDER_LAYER_PLAYER,
		"square_item_cells": true,
		"uses_3d_variant_icons": true,
		"category_buttons_on_left": true,
		"duplicate_right_categories": false,
		"right_panel_width": 392.0,
		"gameplay_hud_hidden": _gameplay_hud != null and not _gameplay_hud.visible,
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
	_hide_gameplay_hud()
	if _camera != null:
		_saved_camera_transform = _camera.transform
		_saved_camera_fov = _camera.fov
		_saved_camera_top_level = _camera.top_level
		_preview_front_direction = PRESENTATION_SOUTH_DIRECTION
		_saved_aim_yaw = _player.aim_yaw
		_saved_visual_root_rotation = _player.avatar.visual_root.rotation if _player.avatar != null and _player.avatar.visual_root != null else Vector3.ZERO
		_camera.top_level = true
		_camera.global_position = _player.global_position + Vector3.UP * CAMERA_CLOSEUP_LOCAL_POSITION.y + _preview_front_direction * absf(CAMERA_CLOSEUP_LOCAL_POSITION.z)
		_camera.look_at(_player.global_position + Vector3.UP * 0.70, Vector3.UP)
		_face_player_to_preview_camera()
		_camera_override_active = true
		_install_preview_fill()
		camera_override_changed.emit(true)
	_refresh_current_loadout()
	_refresh_category_buttons()
	_refresh_option_grid()
	_status_label.text = "外观只影响表现；碰撞、武器和角色状态保持不变"


func _restore_camera_and_input() -> void:
	_remove_preview_fill()
	_restore_gameplay_hud()
	if _camera_override_active and _camera != null and is_instance_valid(_camera):
		_camera.top_level = _saved_camera_top_level
		_camera.transform = _saved_camera_transform
		_camera.fov = _saved_camera_fov
	_camera_override_active = false
	camera_override_changed.emit(false)
	if _player != null and is_instance_valid(_player):
		_player.aim_yaw = _saved_aim_yaw
		if _player.avatar != null and _player.avatar.visual_root != null:
			_player.avatar.visual_root.rotation = _saved_visual_root_rotation
		_player.set_input_locked(_previous_input_locked)


func _face_player_to_preview_camera() -> void:
	if _player == null or _camera == null or _player.avatar == null:
		return
	var to_camera := _camera.global_position - _player.global_position
	to_camera.y = 0.0
	if to_camera.length_squared() <= 0.0001:
		return
	var yaw := atan2(-to_camera.x, -to_camera.z)
	_player.aim_yaw = yaw
	_player.avatar.visual_root.rotation.y = yaw


func _is_player_facing_south() -> bool:
	if _player == null or _player.avatar == null or _player.avatar.visual_root == null:
		return false
	var facing := -_player.avatar.visual_root.global_basis.z
	facing.y = 0.0
	return facing.length_squared() > 0.0001 and facing.normalized().dot(PRESENTATION_SOUTH_DIRECTION) >= 0.98


func _is_camera_on_south_side() -> bool:
	return _camera_south_dot() >= 0.98


func _camera_south_dot() -> float:
	if _player == null or _camera == null:
		return -1.0
	var offset := _camera.global_position - _player.global_position
	offset.y = 0.0
	return offset.normalized().dot(PRESENTATION_SOUTH_DIRECTION) if offset.length_squared() > 0.0001 else -1.0


func _install_preview_fill() -> void:
	_remove_preview_fill()
	if _player == null or not is_instance_valid(_player) or _camera == null or get_parent() == null:
		return
	_preview_fill = OmniLight3D.new()
	_preview_fill.name = "WardrobeCharacterFill"
	_preview_fill.light_color = PREVIEW_FILL_COLOR
	_preview_fill.light_energy = PREVIEW_FILL_ENERGY
	_preview_fill.light_indirect_energy = 0.0
	_preview_fill.omni_range = PREVIEW_FILL_RANGE_M
	_preview_fill.shadow_enabled = false
	_preview_fill.light_cull_mask = GameDesignConfig.RENDER_LAYER_PLAYER
	_preview_fill.shadow_caster_mask = GameDesignConfig.RENDER_LAYER_PLAYER
	_preview_fill.set_meta("wardrobe_preview_only", true)
	get_parent().add_child(_preview_fill)
	_preview_face_fill = OmniLight3D.new()
	_preview_face_fill.name = "WardrobeCharacterFaceFill"
	_preview_face_fill.light_color = Color(1.0, 0.86, 0.72)
	_preview_face_fill.light_energy = PREVIEW_FACE_FILL_ENERGY
	_preview_face_fill.light_indirect_energy = 0.0
	_preview_face_fill.omni_range = PREVIEW_FACE_FILL_RANGE_M
	_preview_face_fill.shadow_enabled = false
	_preview_face_fill.light_cull_mask = GameDesignConfig.RENDER_LAYER_PLAYER
	_preview_face_fill.shadow_caster_mask = GameDesignConfig.RENDER_LAYER_PLAYER
	_preview_face_fill.set_meta("wardrobe_face_preview_only", true)
	get_parent().add_child(_preview_face_fill)
	_sync_preview_fill()


func _remove_preview_fill() -> void:
	if _preview_fill != null and is_instance_valid(_preview_fill):
		_preview_fill.queue_free()
		_preview_fill = null
	if _preview_face_fill != null and is_instance_valid(_preview_face_fill):
		_preview_face_fill.queue_free()
		_preview_face_fill = null


func _sync_preview_fill() -> void:
	if _preview_fill == null or not is_instance_valid(_preview_fill) or _camera == null or _player == null:
		return
	# 衣柜专属近景灯固定在角色正面镜头侧，避免基地夜间环境光不足时角色变黑。
	var target := _player.global_position + Vector3.UP * PREVIEW_FILL_TARGET_HEIGHT_M
	var target_to_camera := _camera.global_position - target
	if target_to_camera.length_squared() <= 0.0001:
		target_to_camera = Vector3.BACK
	_preview_fill.global_position = (
		target
		+ target_to_camera.normalized() * minf(PREVIEW_FILL_FRONT_DISTANCE_M, 1.35)
		+ _camera.global_basis.x.normalized() * PREVIEW_FILL_SIDE_OFFSET_M
		+ Vector3.UP * PREVIEW_FILL_HEIGHT_OFFSET_M
	)
	if _preview_face_fill != null and is_instance_valid(_preview_face_fill):
		_preview_face_fill.global_position = target + target_to_camera.normalized() * 0.72 + Vector3.UP * 0.05


func _hide_gameplay_hud() -> void:
	if _gameplay_hud != null and is_instance_valid(_gameplay_hud):
		return
	var owner := get_parent()
	if owner == null:
		return
	_gameplay_hud = owner.get_node_or_null("HUD") as CanvasLayer
	if _gameplay_hud == null:
		return
	_gameplay_hud_was_visible = _gameplay_hud.visible
	_gameplay_hud.visible = false


func _restore_gameplay_hud() -> void:
	if _gameplay_hud != null and is_instance_valid(_gameplay_hud):
		_gameplay_hud.visible = _gameplay_hud_was_visible
	_gameplay_hud = null


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
		var category := Button.new()
		category.custom_minimum_size.y = 70.0
		category.alignment = HORIZONTAL_ALIGNMENT_LEFT
		category.add_theme_font_size_override("font_size", 16)
		category.pressed.connect(select_slot.bind(slot_id))
		current_box.add_child(category)
		_slot_buttons[slot_id] = category
		_current_labels[slot_id] = category

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
	right.offset_left = -420.0
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
	var separator := HSeparator.new()
	options_box.add_child(separator)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	options_box.add_child(scroll)
	_option_grid = GridContainer.new()
	_option_grid.columns = 2
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
		var button := _current_labels.get(slot_id) as Button
		if button != null:
			button.text = "  %s\n  %s" % [Catalog.get_slot_label(slot_id), Catalog.get_variant_label(variant_id)]
			button.add_theme_color_override("font_color", Catalog.get_variant_color(variant_id).lightened(0.28))


func _refresh_category_buttons() -> void:
	for slot_id in _slot_buttons:
		var button := _slot_buttons[slot_id] as Button
		var selected := str(slot_id) == _selected_slot
		button.disabled = selected
		button.modulate = Color(0.82, 1.0, 1.0) if selected else Color.WHITE
		button.add_theme_stylebox_override(
			"normal",
			_panel_style(
				Color(0.42, 0.94, 1.0) if selected else Color(0.10, 0.30, 0.38),
				Color(0.025, 0.080, 0.098, 0.96) if selected else Color(0.025, 0.060, 0.075, 0.90),
				2 if selected else 1
			)
		)
		button.add_theme_stylebox_override("disabled", button.get_theme_stylebox("normal"))


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
		cell.custom_minimum_size = Vector2(174, 174)
		cell.text = ""
		cell.tooltip_text = variant_id
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
		var content := VBoxContainer.new()
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 2)
		cell.add_child(content)
		var icon := ITEM_ICON_SCENE.instantiate() as ItemModelIcon3D
		icon.custom_minimum_size = Vector2(118, 124)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.configure_custom_model(
			_create_variant_preview.bind(_selected_slot, variant_id),
			"avatar_%s" % _selected_slot
		)
		content.add_child(icon)
		var label := Label.new()
		label.text = "%s %s" % ["●" if selected else "○", Catalog.get_variant_label(variant_id)]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(0.86, 0.96, 0.98))
		content.add_child(label)


func _create_variant_preview(slot_id: String, variant_id: String) -> Node3D:
	var avatar := AVATAR_PREVIEW_SCENE.instantiate() as PlayerAvatar3D
	if avatar == null:
		return null
	var loadout := PlayerAvatar3D.DEFAULT_CUSTOMIZATION.duplicate(true)
	loadout[slot_id] = variant_id
	avatar.set_customization(loadout)
	avatar.set_process(false)
	avatar.set_physics_process(false)
	return avatar


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
