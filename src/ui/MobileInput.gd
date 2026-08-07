extends CanvasLayer

## 移动端虚拟输入。
##
## 作为 autoload 加载；_ready() 自动按平台决定是否启用：
## - 真机 Android / iOS / 移动平台 → enabled = true
## - 桌面 / 调试 → 默认隐藏，运行时按 F1 可切换可见（仅在编辑器中）
##
## 信号：
##   move_direction(direction: Vector2)  左摇杆移动；x = right, y = down
##   shoot_pressed / shoot_released       右摇杆按下 / 松开
##   face_direction(direction: Vector2)   合并面朝方向：右摇杆优先，否则用左摇杆
## v0.1：R/SHIFT/F/E 四位动作在 Dungeon3D 的 HUD 按钮上被点击，直接走 Input.parse_input_event 入口。

signal move_direction(direction: Vector2)
signal shoot_pressed
signal shoot_released
# 合并后的面朝方向：右摇杆优先，没有右摇杆时用左摇杆
signal face_direction(direction: Vector2)

@export var enabled: bool = false
@export var show_visual: bool = true

# 两枚固定圆心摇杆（屏幕左下 / 右下），命中区 = 可见圈 × 1.2
var _left_joystick_base: Vector2 = Vector2.ZERO
var _right_joystick_base: Vector2 = Vector2.ZERO
var _joystick_hit_radius: float = 60.0

# 左摇杆运行时数据
var _joystick_center: Vector2 = Vector2.ZERO
var _joystick_radius: float = 60.0
var _joystick_active: bool = false
var _joystick_knob: Vector2 = Vector2.ZERO
var _joystick_vector: Vector2 = Vector2.ZERO
var _joystick_touch_index: int = -1

# 右摇杆（按住 = 进入射击状态，拖动 = 瞄准方向）
var _aim_joystick_active: bool = false
var _aim_joystick_touch_index: int = -1
var _aim_joystick_center: Vector2 = Vector2.ZERO
var _aim_joystick_vector: Vector2 = Vector2.ZERO
# face_direction 缓存：避免重复 emit
var _face_direction: Vector2 = Vector2.ZERO


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
	# 左摇杆 base ring：固定位置、半透明底 + 描边 + knob
	_widget.draw_circle(_left_joystick_base, _joystick_radius, Color(1.0, 1.0, 1.0, 0.10))
	_widget.draw_arc(_left_joystick_base, _joystick_radius, 0, TAU, 32, Color(1.0, 1.0, 1.0, 0.18), 2.0)
	if _joystick_active:
		_widget.draw_circle(_left_joystick_base + _joystick_knob, _joystick_radius * 0.38, Color(1.0, 1.0, 1.0, 0.32))
	# 右摇杆 base ring：固定位置，激活时画 knob + 拖动方向
	_widget.draw_circle(_right_joystick_base, _joystick_radius, Color(0.4, 0.7, 1.0, 0.10))
	_widget.draw_arc(_right_joystick_base, _joystick_radius, 0, TAU, 32, Color(0.4, 0.7, 1.0, 0.32), 2.0)
	if _aim_joystick_active:
		var aim_dir := _aim_joystick_vector
		_widget.draw_circle(_right_joystick_base + aim_dir * _joystick_radius * 0.7, 16.0, Color(0.4, 0.7, 1.0, 0.32))
		if aim_dir.length() > 0.001:
			_widget.draw_line(_right_joystick_base, _right_joystick_base + aim_dir * _joystick_radius, Color(0.4, 0.7, 1.0, 0.85), 3.0)

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
	if _joystick_active or _aim_joystick_active or _active_touches.size() > 0:
		_widget.queue_redraw()


func _recalc_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size == Vector2.ZERO:
		return
	var radius := maxf(48.0, viewport_size.y * 0.10)
	_joystick_radius = radius
	_joystick_hit_radius = radius * 1.2
	_left_joystick_base = Vector2(viewport_size.x * 0.13, viewport_size.y * 0.78)
	_right_joystick_base = Vector2(viewport_size.x * 0.87, viewport_size.y * 0.78)
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
	elif index == _aim_joystick_touch_index:
		_update_aim_joystick(pos)


func _touch_down(pos: Vector2, index: int) -> void:
	# 两枚固定摇杆：tap 命中区后把该摇杆归当前 touch index
	var which := _pick_joystick(pos)
	if which == 0:
		_joystick_touch_index = index
		_joystick_active = true
		_joystick_center = _left_joystick_base
		_joystick_knob = Vector2.ZERO
		_joystick_vector = Vector2.ZERO
		return
	if which == 1:
		# 右摇杆按下 = 进入射击状态 + 起始瞄准
		_aim_joystick_touch_index = index
		_aim_joystick_active = true
		_aim_joystick_center = _right_joystick_base
		_aim_joystick_vector = Vector2.ZERO
		shoot_pressed.emit()
		_emit_face_direction()
		return

func _touch_up(index: int) -> void:
	if index == _joystick_touch_index:
		_joystick_touch_index = -1
		_joystick_active = false
		_joystick_knob = Vector2.ZERO
		_joystick_vector = Vector2.ZERO
		# 看看还有没有别的触摸落在左摇杆命中区里，有就接管
		for other_index in _active_touches.keys():
			var other_pos: Vector2 = _active_touches[other_index]
			if _pick_joystick(other_pos) == 0:
				_joystick_touch_index = int(other_index)
				_joystick_center = _left_joystick_base
				_update_joystick(other_pos)
				return
		move_direction.emit(Vector2.ZERO)
		_emit_face_direction()
		_widget.queue_redraw()
		return
	if index == _aim_joystick_touch_index:
		# 右摇杆松开 = 退出射击状态 + 清空瞄准
		_aim_joystick_touch_index = -1
		_aim_joystick_active = false
		_aim_joystick_vector = Vector2.ZERO
		shoot_released.emit()
		_emit_face_direction()
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
	_emit_face_direction()


func _update_aim_joystick(touch_pos: Vector2) -> void:
	var delta := touch_pos - _right_joystick_base
	var dist: float = delta.length()
	if dist > _joystick_radius:
		delta = delta.normalized() * _joystick_radius
		dist = _joystick_radius
	var normalized := delta / _joystick_radius
	if normalized.length() < 0.15:
		_aim_joystick_vector = Vector2.ZERO
	else:
		_aim_joystick_vector = normalized.normalized() * ((normalized.length() - 0.15) / 0.85)
	_emit_face_direction()

func _emit_face_direction() -> void:
	# 右摇杆优先级最高：它一旦激活就用它的方向
	# 右摇杆空载时退回左摇杆（让移动和面朝一致）
	var face: Vector2 = Vector2.ZERO
	if _aim_joystick_active and _aim_joystick_vector.length_squared() > 0.0025:
		face = _aim_joystick_vector
	elif _joystick_active and _joystick_vector.length_squared() > 0.0025:
		face = _joystick_vector
	if face != _face_direction:
		_face_direction = face
		face_direction.emit(face)


# 编程切换：编辑器强制启用/禁用


func _pick_joystick(pos: Vector2) -> int:
	# 返回 0 = 左摇杆，1 = 右摇杆，-1 = 都不在。命中区 = base ± hit_radius。
	if pos.distance_to(_left_joystick_base) <= _joystick_hit_radius:
		return 0
	if pos.distance_to(_right_joystick_base) <= _joystick_hit_radius:
		return 1
	return -1

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
	var had_shoot := _aim_joystick_active
	_joystick_active = false
	_joystick_touch_index = -1
	_joystick_vector = Vector2.ZERO
	_joystick_knob = Vector2.ZERO
	_aim_joystick_active = false
	_aim_joystick_touch_index = -1
	_aim_joystick_vector = Vector2.ZERO
	_active_touches.clear()
	move_direction.emit(Vector2.ZERO)
	if had_shoot:
		shoot_released.emit()
	_face_direction = Vector2.ZERO
	face_direction.emit(Vector2.ZERO)
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
