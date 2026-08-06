extends CanvasLayer

## 移动端虚拟输入。
##
## 作为 autoload 加载；_ready() 自动按平台决定是否启用：
## - 真机 Android / iOS / 移动平台 → enabled = true
## - 桌面 / 调试 → 默认隐藏，运行时按 F1 可切换可见（仅在编辑器中）
##
## 信号：
##   move_direction(direction: Vector2)  摇杆移动；x = right, y = down
##   aim_direction(aim: Vector2)        右半屏拖动；x = right, y = down
##   aim_cancel()                       右半屏松手
##   shoot_pressed / shoot_released
## v0.1：R/SHIFT/F/E 四位动作在 Dungeon3D 的 HUD 按钮上被点击，直接走 Input.parse_input_event 入口，
## 不再由 MobileInput 发射信号。

signal move_direction(direction: Vector2)
signal aim_direction(aim: Vector2)
signal aim_cancel()
signal shoot_pressed
signal shoot_released

@export var enabled: bool = false
@export var show_visual: bool = true

# 区域比例（按视口）
var _joystick_zone_ratio := Rect2(0.0, 0.55, 0.45, 0.45)  # 左下半屏
var _action_zone_ratio := Rect2(0.55, 0.30, 0.45, 0.70)    # 右半屏

# 摇杆运行时数据
var _joystick_center: Vector2 = Vector2.ZERO
var _joystick_radius: float = 60.0
var _joystick_active: bool = false
var _joystick_knob: Vector2 = Vector2.ZERO
var _joystick_vector: Vector2 = Vector2.ZERO
var _joystick_touch_index: int = -1

# 瞄准运行时数据
var _aim_zone_touch_index: int = -1
var _aim_zone_start: Vector2 = Vector2.ZERO
var _aim_last_emitted: Vector2 = Vector2.ZERO

# 按钮布局：只留第一位需要持按的游戏拼护键 SHOOT。R / SHIFT / F / E 四位动作按钮
# 已被上位到 Dungeon3D 的 ActionKeyStrip，用户在主界面右下角点击即可触发对应的 input action。
var _shoot_pos: Vector2 = Vector2.ZERO
var _shoot_radius: float = 36.0

# 触摸状态
var _active_touches: Dictionary = {}

# 已被发射过的按钮（避免摇杆拖动时再次触发）
var _touched_buttons: Dictionary = {}

# 绘制与点击的真实节点（CanvasLayer 子 Control）
var _widget: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 128
	# 自适应：真机自动启用，编辑器默认关闭
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		enabled = true
	_put_widget()
	get_viewport().size_changed.connect(_recalc_layout)


func _put_widget() -> void:
	# 创建一个 Control 子节点专门负责绘制与触摸输入
	if _widget != null and is_instance_valid(_widget):
		return
	_widget = Control.new()
	_widget.name = "MobileInputWidget"
	_widget.process_mode = Node.PROCESS_MODE_ALWAYS
	_widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_widget.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_widget.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_widget.draw.connect(_widget_draw)
	add_child(_widget)
	_recalc_layout()


func _widget_draw() -> void:
	if not enabled or not show_visual or _widget == null:
		return
	var font := ThemeDB.fallback_font
	var base_color := Color(1.0, 1.0, 1.0, 0.10)
	var active_color := Color(1.0, 1.0, 1.0, 0.22)
	_widget.draw_circle(_joystick_center, _joystick_radius, base_color)
	_widget.draw_arc(_joystick_center, _joystick_radius, 0, TAU, 32, Color(1.0, 1.0, 1.0, 0.18), 2.0)
	_widget.draw_circle(_joystick_center + _joystick_knob, _joystick_radius * 0.38, active_color)
	if _aim_zone_touch_index >= 0:
		_widget.draw_arc(_aim_zone_start, 22.0, 0, TAU, 20, Color(0.4, 0.7, 1.0, 0.6), 2.5)
		var aim_dir := _aim_last_emitted
		if aim_dir.length() > 0.001:
			_widget.draw_line(_aim_zone_start, _aim_zone_start + aim_dir * 60.0, Color(0.4, 0.7, 1.0, 0.8), 3.0)
	# 只留主要射击按钮：SHOOT 。其他四位动作按钮已进入 HUD
	_draw_button_on(_widget, _shoot_pos, _shoot_radius, Color(1.0, 0.3, 0.3, 0.7), font, "SHOOT", 14)


func _draw_button_on(canvas: Control, center: Vector2, radius: float, ring: Color, font: Font, text: String, font_size: int) -> void:
	canvas.draw_circle(center, radius, Color(1.0, 1.0, 1.0, 0.10))
	canvas.draw_arc(center, radius, 0, TAU, 32, ring, 2.5)
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	canvas.draw_string(font, center - ts * 0.5 + Vector2(0, ts.y * 0.25), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.85))


func _input(event: InputEvent) -> void:
	if not enabled or _controls_blocked():
		return
	if event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)


func _process(_delta: float) -> void:
	if not enabled or _widget == null:
		return
	if _controls_blocked():
		_clear_input_state()
		return
	if _joystick_active or _aim_zone_touch_index >= 0 or _active_touches.size() > 0:
		_widget.queue_redraw()


func _recalc_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size == Vector2.ZERO:
		return
	_shoot_pos = Vector2(viewport_size.x * 0.89, viewport_size.y * 0.78)
	_joystick_center = Vector2(viewport_size.x * 0.13, viewport_size.y * 0.78)
	_joystick_radius = maxf(48.0, viewport_size.y * 0.10)
	if _widget != null:
		_widget.queue_redraw()


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	var pos: Vector2 = event.position
	var index: int = event.index
	if event.pressed:
		_active_touches[index] = pos
		_touch_down(pos, index)
	else:
		_touch_up(index)
		_active_touches.erase(index)


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	var pos: Vector2 = event.position
	var index: int = event.index
	if not _active_touches.has(index):
		return
	_active_touches[index] = pos
	if index == _joystick_touch_index:
		_update_joystick(pos)
	elif index == _aim_zone_touch_index:
		_update_aim(pos)


func _touch_down(pos: Vector2, index: int) -> void:
	# 只有 SHOOT 按钮作为独立绘制的手按区。R / SHIFT / F / E 四位动作
	# 已移到 Dungeon3D 的 ActionKeyStrip，直接接入 Input.parse_input_event。
	if pos.distance_to(_shoot_pos) < _shoot_radius:
		_touched_buttons[index] = "shoot"
		shoot_pressed.emit()
		return
	# 左下半屏为摇杆
	if _is_in_joystick_zone(pos):
		_joystick_touch_index = index
		_joystick_active = true
		_joystick_center = pos
		_joystick_knob = Vector2.ZERO
		_joystick_vector = Vector2.ZERO
		return
	# 右半屏视为瞄准
	if _is_in_aim_zone(pos):
		_aim_zone_touch_index = index
		_aim_zone_start = pos
		_aim_last_emitted = Vector2.ZERO
		return


func _touch_up(index: int) -> void:
	if _touched_buttons.has(index):
		var btn: String = _touched_buttons[index]
		_touched_buttons.erase(index)
		if btn == "shoot":
			shoot_released.emit()
		return
	if index == _joystick_touch_index:
		_joystick_touch_index = -1
		_joystick_active = false
		_joystick_knob = Vector2.ZERO
		_joystick_vector = Vector2.ZERO
		# 检查是否还有别的在摇杆区
		for other_index in _active_touches.keys():
			var other_pos: Vector2 = _active_touches[other_index]
			if _is_in_joystick_zone(other_pos):
				_joystick_touch_index = int(other_index)
				_joystick_center = other_pos
				_update_joystick(other_pos)
				return
		move_direction.emit(Vector2.ZERO)
		_widget.queue_redraw()
		return
	if index == _aim_zone_touch_index:
		_aim_zone_touch_index = -1
		_aim_last_emitted = Vector2.ZERO
		aim_cancel.emit()
		_widget.queue_redraw()


func _update_joystick(touch_pos: Vector2) -> void:
	var delta := touch_pos - _joystick_center
	var dist: float = delta.length()
	if dist > _joystick_radius:
		delta = delta.normalized() * _joystick_radius
		dist = _joystick_radius
	_joystick_knob = delta
	var normalized := delta / _joystick_radius
	if normalized.length() < 0.15:
		_joystick_vector = Vector2.ZERO
	else:
		_joystick_vector = normalized.normalized() * ((normalized.length() - 0.15) / 0.85)
	move_direction.emit(_joystick_vector)


func _update_aim(touch_pos: Vector2) -> void:
	var delta := touch_pos - _aim_zone_start
	if delta.length() < 16.0:
		_aim_last_emitted = Vector2.ZERO
		aim_direction.emit(Vector2.ZERO)
		return
	_aim_last_emitted = delta.normalized()
	aim_direction.emit(_aim_last_emitted)


func _is_in_joystick_zone(pos: Vector2) -> bool:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size == Vector2.ZERO:
		return false
	return _joystick_zone_ratio.has_point(pos / viewport_size)


func _is_in_aim_zone(pos: Vector2) -> bool:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size == Vector2.ZERO:
		return false
	return _action_zone_ratio.has_point(pos / viewport_size)


# 编程切换：编辑器强制启用/禁用
func set_enabled(value: bool) -> void:
	enabled = value
	if not value:
		_clear_input_state()
	if _widget != null:
		_widget.queue_redraw()


func _controls_blocked() -> bool:
	if get_tree().paused:
		return true
	var player := get_tree().get_first_node_in_group("player_3d")
	return player != null and bool(player.get("input_locked"))


func _clear_input_state() -> void:
	var had_shoot := _touched_buttons.values().has("shoot")
	_joystick_active = false
	_joystick_touch_index = -1
	_joystick_vector = Vector2.ZERO
	_joystick_knob = Vector2.ZERO
	_aim_zone_touch_index = -1
	_aim_last_emitted = Vector2.ZERO
	_active_touches.clear()
	_touched_buttons.clear()
	move_direction.emit(Vector2.ZERO)
	aim_cancel.emit()
	if had_shoot:
		shoot_released.emit()
	if _widget != null:
		_widget.queue_redraw()


func _tap_action(action: StringName) -> void:
	var pressed := InputEventAction.new()
	pressed.action = action
	pressed.pressed = true
	Input.parse_input_event(pressed)
	var released := InputEventAction.new()
	released.action = action
	released.pressed = false
	Input.parse_input_event(released)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and enabled:
		_tap_action("pause")
