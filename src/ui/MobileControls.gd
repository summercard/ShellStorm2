extends CanvasLayer

## 移动端控制组件
## 在手机平台上显示虚拟摇杆和按钮

signal move_direction(direction: Vector2)
signal shoot_pressed
signal dash_pressed
signal skill_pressed

@export var enabled: bool = true

# 摇杆区域
var _joystick_center: Vector2 = Vector2(100, 600)
var _joystick_radius: float = 60.0
var _joystick_active: bool = false
var _joystick_vector: Vector2 = Vector2.ZERO

# 按钮区域
var _shoot_pos := Vector2(1080, 560)
var _dash_pos := Vector2(960, 570)
var _skill_pos := Vector2(1080, 470)
var _button_radius: float = 35.0

# 触摸状态
var _active_touches: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if not enabled:
		return

	if event is InputEventScreenTouch:
		var touch_pos: Vector2 = event.position
		var touch_index: int = event.index

		if event.pressed:
			_active_touches[touch_index] = touch_pos
			_check_touch_down(touch_pos, touch_index)
		else:
			_check_touch_up(touch_index)
			_active_touches.erase(touch_index)

	elif event is InputEventScreenDrag:
		var touch_index: int = event.index
		if _active_touches.has(touch_index):
			_active_touches[touch_index] = event.position
			_update_joystick(event.position, touch_index)


func _check_touch_down(pos: Vector2, touch_index: int) -> void:
	# 检查射击按钮
	if pos.distance_to(_shoot_pos) < _button_radius:
		shoot_pressed.emit()
		return

	# 检查闪避按钮
	if pos.distance_to(_dash_pos) < 30.0:
		dash_pressed.emit()
		return

	# 检查技能按钮
	if pos.distance_to(_skill_pos) < _button_radius:
		skill_pressed.emit()
		return

	# 检查摇杆区域（左下角）
	if pos.x < 200 and pos.y > 500:
		_joystick_active = true
		_joystick_center = pos
		_joystick_vector = Vector2.ZERO


func _check_touch_up(touch_index: int) -> void:
	if _joystick_active:
		_joystick_active = false
		_joystick_vector = Vector2.ZERO
		move_direction.emit(Vector2.ZERO)


func _update_joystick(touch_pos: Vector2, touch_index: int) -> void:
	if not _joystick_active:
		return

	var delta := touch_pos - _joystick_center
	var dist := delta.length()

	if dist > _joystick_radius:
		delta = delta.normalized() * _joystick_radius
		dist = _joystick_radius

	# 归一化并应用死区
	var normalized := delta / _joystick_radius
	if normalized.length() < 0.15:
		_joystick_vector = Vector2.ZERO
	else:
		_joystick_vector = normalized.normalized() * ((normalized.length() - 0.15) / 0.85)

	move_direction.emit(_joystick_vector)


func _draw() -> void:
	if not enabled:
		return

	var base_color := Color(1.0, 1.0, 1.0, 0.12)
	var active_color := Color(1.0, 1.0, 1.0, 0.25)

	# 摇杆外圈
	draw_circle(_joystick_center, _joystick_radius, base_color)
	draw_arc(_joystick_center, _joystick_radius * 0.75, 0, TAU, 32, Color(1.0, 1.0, 1.0, 0.08), 2.0)

	# 摇杆内核
	var knob_pos := _joystick_center + _joystick_vector * _joystick_radius * 0.5
	draw_circle(knob_pos, _joystick_radius * 0.4, active_color)

	# 射击按钮
	draw_circle(_shoot_pos, 35.0, base_color)
	draw_arc(_shoot_pos, 35.0, 0, TAU, 32, Color(1.0, 0.3, 0.3, 0.4), 3.0)
	var font := ThemeDB.fallback_font
	draw_string(font, _shoot_pos + Vector2(-8, 6), "🔫", HORIZONTAL_ALIGNMENT_LEFT, 40, 24, Color(1.0, 1.0, 1.0, 0.7))

	# 闪避按钮
	draw_circle(_dash_pos, 25.0, base_color)
	draw_string(font, _dash_pos + Vector2(-6, 6), "⚡", HORIZONTAL_ALIGNMENT_LEFT, 30, 18, Color(1.0, 1.0, 0.3, 0.7))

	# 技能按钮
	draw_circle(_skill_pos, 35.0, base_color)
	draw_arc(_skill_pos, 35.0, 0, TAU, 32, Color(0.3, 0.5, 1.0, 0.4), 3.0)
	draw_string(font, _skill_pos + Vector2(-8, 6), "★", HORIZONTAL_ALIGNMENT_LEFT, 40, 24, Color(1.0, 1.0, 0.3, 0.7))


func _process(_delta: float) -> void:
	if _joystick_active or _active_touches.size() > 0:
		queue_redraw()