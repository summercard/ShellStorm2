extends Node
## 活动输入设备判定。
##
## 只负责回答"现在是谁在操作"并广播变化：不读取任何玩法输入、不改动
## InputMap，因此键鼠、触屏、手柄三套通路可以各自独立维护。
##
## 判定依据是**真实输入事件**而不是"设备是否存在"：手柄一直插在机箱上、
## 玩家却全程用键鼠时，活动设备保持键鼠，界面提示不会莫名翻成手柄。

signal active_device_changed(device: String)

const DEVICE_KEYBOARD_MOUSE := "keyboard_mouse"
const DEVICE_GAMEPAD := "gamepad"
const DEVICE_TOUCH := "touch"

## 摇杆静止时仍会持续上报微小轴值；低于此阈值的事件不算"玩家在操作手柄"。
const JOY_ACTIVITY_THRESHOLD := 0.35
## 鼠标抖动同理：单帧位移小于此值不触发键鼠判定，避免磕到鼠标就切走。
const MOUSE_ACTIVITY_MIN_PIXELS := 6.0

var _active_device := DEVICE_KEYBOARD_MOUSE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if not InputSettings.settings_changed.is_connected(_on_input_settings_changed):
		InputSettings.settings_changed.connect(_on_input_settings_changed)
	_active_device = _initial_device()


func get_active_device() -> String:
	return _active_device


func is_gamepad_active() -> bool:
	return _active_device == DEVICE_GAMEPAD


func is_touch_active() -> bool:
	return _active_device == DEVICE_TOUCH


func has_connected_gamepad() -> bool:
	return not Input.get_connected_joypads().is_empty()


func get_active_gamepad_name() -> String:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return ""
	return Input.get_joy_name(int(pads[0]))


## 面板按钮等非输入事件驱动的入口：直接把活动设备钉到某一侧。
func force_device(device: String) -> void:
	if device not in [DEVICE_KEYBOARD_MOUSE, DEVICE_GAMEPAD, DEVICE_TOUCH]:
		return
	_set_active(device)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_mark(DEVICE_GAMEPAD)
	elif event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) >= JOY_ACTIVITY_THRESHOLD:
			_mark(DEVICE_GAMEPAD)
	elif event is InputEventKey:
		if (event as InputEventKey).pressed:
			_mark(DEVICE_KEYBOARD_MOUSE)
	elif event is InputEventMouseButton:
		if (event as InputEventMouseButton).pressed:
			_mark(DEVICE_KEYBOARD_MOUSE)
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() >= MOUSE_ACTIVITY_MIN_PIXELS:
			_mark(DEVICE_KEYBOARD_MOUSE)
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		_mark(DEVICE_TOUCH)


func _mark(device: String) -> void:
	if not _accepts(device):
		return
	_set_active(device)


func _accepts(device: String) -> bool:
	var mode := InputSettings.get_device_mode()
	if mode == InputSettings.DEVICE_MODE_GAMEPAD:
		return device == DEVICE_GAMEPAD
	if mode == InputSettings.DEVICE_MODE_KEYBOARD_MOUSE:
		# 触屏是平台固有输入，不参与"锁定键鼠"的排除。
		return device != DEVICE_GAMEPAD
	# 自动模式：手柄开关关闭时永不认定手柄。
	return device != DEVICE_GAMEPAD or InputSettings.is_gamepad_enabled()


func _set_active(device: String) -> void:
	if _active_device == device:
		return
	_active_device = device
	active_device_changed.emit(device)


func _initial_device() -> String:
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		return DEVICE_TOUCH
	if (
		InputSettings.get_device_mode() == InputSettings.DEVICE_MODE_GAMEPAD
		and has_connected_gamepad()
	):
		return DEVICE_GAMEPAD
	return DEVICE_KEYBOARD_MOUSE


func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if connected:
		return
	# 手柄拔掉后不能继续停留在手柄判定上，否则界面会一直显示手柄提示。
	if _active_device == DEVICE_GAMEPAD:
		_set_active(DEVICE_KEYBOARD_MOUSE)


func _on_input_settings_changed(_settings: Dictionary) -> void:
	var mode := InputSettings.get_device_mode()
	if mode == InputSettings.DEVICE_MODE_GAMEPAD:
		# 锁定手柄但没有可用手柄时回落键鼠，避免出现"提示写着手柄 A、
		# 玩家却只能按键盘"的死状态。
		if has_connected_gamepad():
			_set_active(DEVICE_GAMEPAD)
		else:
			_set_active(DEVICE_KEYBOARD_MOUSE)
		return
	if _active_device == DEVICE_GAMEPAD and not InputSettings.is_gamepad_enabled():
		_set_active(DEVICE_KEYBOARD_MOUSE)
