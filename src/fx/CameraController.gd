extends Node
class_name CameraController

# CameraController — 视角控制（缩放 + 视野遮挡）
# 挂载在 Camera2D 同级节点下，响应鼠标滚轮和触屏捏合缩放

signal zoom_changed(zoom_level: float)

const MIN_ZOOM: float = 0.5
const MAX_ZOOM: float = 2.5
const ZOOM_STEP: float = 0.1
const ZOOM_SPEED: float = 8.0  # 平滑缩放速度

@onready var _camera: Camera2D = get_parent() as Camera2D
var _target_zoom: float = 1.0
var _current_zoom: float = 1.0

func _ready() -> void:
	if _camera == null:
		push_warning("[CameraController] Must be child of Camera2D")
		return
	_target_zoom = _camera.zoom.x
	_current_zoom = _camera.zoom.x

func _process(delta: float) -> void:
	# 平滑缩放到目标值
	if absf(_current_zoom - _target_zoom) > 0.001:
		_current_zoom = lerpf(_current_zoom, _target_zoom, ZOOM_SPEED * delta)
		var z := Vector2(_current_zoom, _current_zoom)
		_camera.zoom = z
		zoom_changed.emit(_current_zoom)

func _unhandled_input(event: InputEvent) -> void:
	if _camera == null:
		return
	
	# 鼠标滚轮缩放
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(-ZOOM_STEP)
	
	# 触屏捏合缩放
	if event is InputEventMagnifyGesture:
		var mg: InputEventMagnifyGesture = event
		var new_zoom := _target_zoom * mg.relative
		_set_zoom(new_zoom)
	
	# 键盘 +/- 缩放（辅助）
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			_zoom_by(ZOOM_STEP)
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			_zoom_by(-ZOOM_STEP)
		# R 键重置缩放
		elif event.keycode == KEY_R:
			_set_zoom(1.0)

func _zoom_by(delta: float) -> void:
	_set_zoom(_target_zoom + delta)

func _set_zoom(value: float) -> void:
	_target_zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)

func get_zoom() -> float:
	return _current_zoom