extends Node
## 输入设备设置与持久化。
##
## 与 GraphicsSettingsManager 同构、互相独立：画面设置写在
## user://graphics_settings.cfg，本设置写在 user://input_settings.cfg，
## 复位游戏存档时两者都保留。
##
## device_mode 的三种取值决定 InputDeviceTracker 如何认定活动设备：
## - auto           跟随最近一次真实输入（插着手柄不操作也仍算键鼠）
## - keyboard_mouse 锁定键鼠，手柄事件不改变提示与判定
## - gamepad        锁定手柄；手柄未连接时回落键鼠，避免出现"提示写着
##                  手柄 A、玩家却只能按键盘"的死状态

signal settings_changed(settings: Dictionary)

const SAVE_PATH := "user://input_settings.cfg"
const SECTION := "input"

const DEVICE_MODE_AUTO := "auto"
const DEVICE_MODE_KEYBOARD_MOUSE := "keyboard_mouse"
const DEVICE_MODE_GAMEPAD := "gamepad"
const DEVICE_MODES := [DEVICE_MODE_AUTO, DEVICE_MODE_KEYBOARD_MOUSE, DEVICE_MODE_GAMEPAD]

const DEFAULT_SETTINGS := {
	"device_mode": DEVICE_MODE_AUTO,
	"gamepad_enabled": true,
	"gamepad_move_deadzone": 0.20,
	# 瞄准死区 0.20 → 0.12、平滑 0.35 → 0.15（2026-09-22 手感调整）：原值吃掉
	# 20% 行程、平滑时间常数约 60ms，玩家反馈「转向不够精确、无法瞄准」。
	# 幅度权威的响应曲线（见 GamepadInput.AIM_*_SPEED_SCALE）只在死区更小、
	# 基础平滑更低时才发挥得出「轻推精瞄」的效果 —— 否则轻推段仍被旧平滑拖住。
	"gamepad_aim_deadzone": 0.12,
	"gamepad_aim_smoothing": 0.15,
	"gamepad_left_stick_aim": false,
	"gamepad_aim_assist": true,
	"gamepad_vibration": true,
}

## 滑条范围与 sanitize 共用同一份常量，避免界面上下限和实际取值漂移。
const DEADZONE_RANGE := Vector2(0.05, 0.50)
const AIM_SMOOTHING_RANGE := Vector2(0.0, 0.90)
const FLOAT_SETTING_RANGES := {
	"gamepad_move_deadzone": DEADZONE_RANGE,
	"gamepad_aim_deadzone": DEADZONE_RANGE,
	"gamepad_aim_smoothing": AIM_SMOOTHING_RANGE,
}

var _settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()


func get_settings_snapshot() -> Dictionary:
	return _settings.duplicate(true)


func get_value(key: String, fallback: Variant = null) -> Variant:
	return _settings.get(key, fallback)


func get_device_mode() -> String:
	return str(_settings.get("device_mode", DEVICE_MODE_AUTO))


func is_gamepad_enabled() -> bool:
	return bool(_settings.get("gamepad_enabled", true))


func get_move_deadzone() -> float:
	return float(_settings.get("gamepad_move_deadzone", 0.20))


func get_aim_deadzone() -> float:
	return float(_settings.get("gamepad_aim_deadzone", 0.12))


func get_aim_smoothing() -> float:
	return float(_settings.get("gamepad_aim_smoothing", 0.15))


## 虚拟摇杆瞄准辅助（磁吸）是否开启。
## 开启后，瞄准方向会被视野内**已照亮**的敌人轻轻吸引（偏转有硬上限，见 AimAssist3D）。
## **出厂默认 true**：这是顶视角射击手柄操作的标准配件，且偏转受限不会抢控制。
func is_aim_assist_enabled() -> bool:
	return bool(_settings.get("gamepad_aim_assist", true))


## 左摇杆是否也参与控制朝向（右摇杆一动就抢回去）。
## 关掉后朝向只由右摇杆驱动，摇杆全部回中时保持最后方向。
## **出厂默认 false**（2026-09-22 业主实测：左摇杆同控朝向与右摇杆精确瞄准互相干扰，
## 改为「保留能力、默认关闭」，需要时在 ESC 操作设置页自行打开）。
func is_left_stick_aim_enabled() -> bool:
	return bool(_settings.get("gamepad_left_stick_aim", false))


func is_vibration_enabled() -> bool:
	return bool(_settings.get("gamepad_vibration", true))


func set_value(key: String, value: Variant, save := true) -> bool:
	if not DEFAULT_SETTINGS.has(key):
		return false
	var sanitized: Variant = _sanitize_value(key, value)
	if _settings.get(key) == sanitized:
		return true
	_settings[key] = sanitized
	if save:
		_save_settings()
	settings_changed.emit(get_settings_snapshot())
	return true


func restore_defaults() -> void:
	_settings = DEFAULT_SETTINGS.duplicate(true)
	_save_settings()
	settings_changed.emit(get_settings_snapshot())


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	for key in DEFAULT_SETTINGS.keys():
		if config.has_section_key(SECTION, key):
			_settings[key] = _sanitize_value(key, config.get_value(SECTION, key))


func _save_settings() -> void:
	var config := ConfigFile.new()
	for key in DEFAULT_SETTINGS.keys():
		config.set_value(SECTION, key, _settings[key])
	config.save(SAVE_PATH)


func _sanitize_value(key: String, value: Variant) -> Variant:
	if key == "device_mode":
		var mode := str(value)
		return mode if mode in DEVICE_MODES else DEVICE_MODE_AUTO
	if FLOAT_SETTING_RANGES.has(key):
		var bounds := FLOAT_SETTING_RANGES[key] as Vector2
		var number := float(value)
		if not is_finite(number):
			return DEFAULT_SETTINGS[key]
		var clamped: float = clampf(number, bounds.x, bounds.y)
		return clamped
	return bool(value)
