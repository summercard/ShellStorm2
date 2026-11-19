extends Control

## 宿主只负责候选和事务；这里仅管理上下分区及投影开闭。
const TRANSITION := preload("res://src/ui/weapon_build/WeaponHologramTransition.gd")
const BOARD_PATH := "res://assets/art/ui/weapon_build/weapon_build_board.tscn"
const PREVIEW_SLIDE := preload("res://src/ui/weapon_build/WeaponPreviewSlide.gd")
var row: HBoxContainer
var board: Control
var _owner: Node
var _prev_button: Button
var _next_button: Button
var _slide: PREVIEW_SLIDE
var _preview_locked := false
var _intro_progress := 0.0
var _intro: Tween
var _epoch := 0
var _settled := false
var _closing := false
var _moving := false
var _dialogue_reserved := false

func set_dialogue_reserved(reserved: bool) -> void:
	_dialogue_reserved = reserved
	_layout()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_meta("ui_prism_exempt", true)
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row = HBoxContainer.new()
	row.name = "FateCandidates"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 56)
	row.hide()
	add_child(row)
	board = (load(BOARD_PATH) as PackedScene).instantiate() as Control
	board.name = "WeaponBuildBoard"
	add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	board.call("set_compact", true)
	_prev_button = _make_page_button("‹")
	_prev_button.name = "PreviewPreviousWeapon"
	_prev_button.pressed.connect(func() -> void: _shift_preview(-1))
	add_child(_prev_button)
	_next_button = _make_page_button("›")
	_next_button.name = "PreviewNextWeapon"
	_next_button.pressed.connect(func() -> void: _shift_preview(1))
	add_child(_next_button)
	_slide = PREVIEW_SLIDE.new(self, _apply_board_pose, _show_preview_slot)
	resized.connect(_layout)
	_layout()

func set_player(player: Node) -> void:
	_owner = player
	return_to_purchase_target()
	board.call("set_weapon_owner", player)
	_update_preview_buttons()

func _make_page_button(symbol: String) -> Button:
	var button := Button.new()
	button.text = symbol
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 26)
	UIStyleFactory.apply_prism_button(button, "ghost", 0, 24, 1, "none")
	return button

func _weapon_item_for_slot(slot_index: int) -> Dictionary:
	if not is_instance_valid(_owner) or not _owner.has_method("get_equipped_weapon_item_for_slot"):
		return {}
	return _owner.call("get_equipped_weapon_item_for_slot", slot_index) as Dictionary

func _update_preview_buttons() -> void:
	var enabled := _settled and not _moving and not _closing and not _preview_locked and not _dialogue_reserved and not _weapon_item_for_slot(1 - _shown_slot()).is_empty()
	_prev_button.disabled = not enabled
	_next_button.disabled = not enabled

func _active_slot() -> int:
	return int(_owner.call("get_active_weapon_slot")) if is_instance_valid(_owner) and _owner.has_method("get_active_weapon_slot") else 0

func _shown_slot() -> int:
	var slot := int(board.call("get_preview_slot"))
	return slot if slot >= 0 else _active_slot()

func _shift_preview(direction: int) -> void:
	if _prev_button.disabled or not is_visible_in_tree():
		return
	var shown := _shown_slot()
	var target := 1 - (_slide.requested_slot if _slide.requested_slot >= 0 else shown)
	if not _weapon_item_for_slot(target).is_empty():
		_slide.request(target, shown, direction)

func _show_preview_slot(slot: int) -> void:
	var item := _weapon_item_for_slot(slot)
	if slot == _active_slot() or item.is_empty():
		board.call("clear_preview_item")
	else:
		board.call("set_preview_item", item, slot)
	_update_preview_buttons()

func set_purchase_in_progress(busy: bool) -> void:
	_preview_locked = busy
	_update_preview_buttons()

func return_to_purchase_target() -> void:
	_slide.reset()
	board.call("clear_preview_item")
	_update_preview_buttons()

func _board_destination() -> Vector2:
	if _dialogue_reserved:
		return Vector2((size.x - board.size.x * 0.68) * 0.5, size.y * 0.50)
	return Vector2(32, size.y * 0.51)

func _layout() -> void:
	if board == null:
		return
	row.position = Vector2(24, maxf(12, size.y * 0.025))
	row.size = Vector2(maxf(1, size.x - 48), 320)
	_prev_button.position = Vector2(8, size.y * 0.50 - 24)
	_prev_button.size = Vector2(44, 48)
	_next_button.position = Vector2(maxf(0, size.x - 52), size.y * 0.50 - 24)
	_next_button.size = Vector2(44, 48)
	_update_preview_buttons()
	board.size = Vector2(maxf(1, size.x - 64), maxf(1, size.y * 0.45 - 40))
	_apply_board_pose()

func _apply_board_pose() -> void:
	var center := Vector2(32, (size.y - board.size.y) * 0.5)
	var origin := center.lerp(_board_destination(), _intro_progress)
	if _settled and not _closing:
		board.scale = Vector2.ONE * lerpf(1.0, 0.68 if _dialogue_reserved else 1.0, _intro_progress)
	board.position = origin + Vector2(_slide.offset * (size.x + 8.0), 0.0)

func _set_intro_progress(value: float) -> void:
	_intro_progress = value
	_apply_board_pose()

func play_intro(reveal: Callable) -> void:
	_epoch += 1
	var epoch := _epoch
	_layout()
	_moving = true
	_intro = TRANSITION.open(board, _owner)
	_intro.finished.connect(func() -> void:
		if epoch != _epoch or _closing:
			return
		_settled = true
		_intro = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		var duration := 0.01 if bool(ProjectSettings.get_setting("accessibility/reduce_motion", false)) else 0.26
		_intro.tween_method(_set_intro_progress, 0.0, 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_intro.tween_callback(func() -> void:
			if epoch == _epoch and not _closing:
				_moving = false
				_layout()
				row.show()
				reveal.call()))

func play_close() -> void:
	if _closing:
		return
	_epoch += 1
	_closing = true
	_slide.reset()
	_update_preview_buttons()
	if _intro != null and _intro.is_valid():
		_intro.kill()
	row.hide()
	await TRANSITION.close(board, _owner).finished
