extends Node
## 手柄输入适配层。
##
## 输出信号与 MobileInput 完全同构（move_direction / face_direction /
## shoot_pressed / shoot_released），因此 Player3D 复用同一条「虚拟输入源」
## 通路，不必为手柄另写一套瞄准或射击逻辑 —— 右手摇杆直接驱动
## `Player3D._get_mobile_face_direction()`，扳机直接驱动 `_mobile_shoot_active`。
##
## 与 MobileInput 的三点差异：
## 1. 不绘制任何虚拟控件：手柄是实体设备。
## 2. 摇杆全部回中时**不**发送 face_direction(Vector2.ZERO)。Player3D 一旦看到
##    面朝方向归零就会退回鼠标射线，手柄玩家一松右摇杆准星就会瞬间跳到鼠标位置。
##    这里改为保持最后一次方向（第三档），只有真正切回键鼠时才清零。
## 3. 按键映射在运行时注入 InputMap（见 GAMEPAD_ACTION_BINDINGS），不写进
##    project.godot：既避免手写序列化格式出错，也让「控制设置」里的手柄开关
##    能实时生效、可断言。
##
## 朝向来源三档（见 resolve_face_source）：
##   1. 右摇杆推过瞄准死区 → 用右摇杆方向（最高优先，边退边打照旧成立）
##   2. 否则左摇杆推过移动死区 → 用移动方向（**可关**，见 InputSettings 的
##      gamepad_left_stick_aim；与 MobileInput 的「右摇杆优先，否则用左摇杆」同构）
##   3. 否则保持上次方向（手柄独有的档位：触屏可以归零是因为触屏没有鼠标，
##      手柄归零会掉回鼠标射线）
##
## 键位（Xbox 标准布局，与主机端射击游戏惯例一致）：
##   左摇杆 移动 · 右摇杆 瞄准 · RT 射击 / 近战
##   A 交互 · B 冲刺 · X 换弹 · Y 探照灯
##   LB 主武器 · RB 副武器 · 十字键左 / 右 快捷物品 1 / 2
##   Select 背包 · 左摇杆按下 地图 · Start 暂停

signal move_direction(direction: Vector2)
signal face_direction(direction: Vector2)
signal shoot_pressed
signal shoot_released
signal gamepad_connected(device: int)
signal gamepad_disconnected(device: int)

## 运行时注入的手柄按键映射。key = project.godot 里已有的 input action。
const GAMEPAD_ACTION_BINDINGS := {
	"ui_accept": [JOY_BUTTON_A],
	"ui_cancel": [JOY_BUTTON_B],
	"interact": [JOY_BUTTON_A],
	"dash": [JOY_BUTTON_B],
	"reload": [JOY_BUTTON_X],
	"toggle_flashlight": [JOY_BUTTON_Y],
	"select_primary_weapon": [JOY_BUTTON_LEFT_SHOULDER],
	"select_secondary_weapon": [JOY_BUTTON_RIGHT_SHOULDER],
	"use_quick_item_1": [JOY_BUTTON_DPAD_LEFT],
	"use_quick_item_2": [JOY_BUTTON_DPAD_RIGHT],
	"ui_inventory": [JOY_BUTTON_BACK],
	"toggle_floor_map": [JOY_BUTTON_LEFT_STICK],
	"pause": [JOY_BUTTON_START],
}

## 扳机有效阈值：静息轴值不足以触发，避免手柄漂移导致自动开火。
const TRIGGER_THRESHOLD := 0.35
## 死区比较容差：摇杆轴是 float32（Vector2 分量），Vector2(0.2, 0).length() 会
## 略大于字面量 0.2。不留容差时「正好等于死区」会漏出一个 ~4e-9 的残值，
## 使「死区边界以内一律归零」这条契约在边界点上失效。
const DEADZONE_COMPARE_EPSILON := 1.0e-5
## 瞄准平滑基准速率（次/秒）：rate = BASE × (1 − smoothing)。
const AIM_SMOOTHING_BASE_RATE := 30.0

## 朝向来源三档取值。第 1 档右摇杆、第 2 档左摇杆、第 3 档保持上次方向。
const FACE_SOURCE_AIM := "aim"
const FACE_SOURCE_MOVE := "move"
const FACE_SOURCE_HOLD := "hold"
## 摇杆释放滞回系数：进入某一档要越过该档死区，退出只要求掉到
## 「死区 × 本系数」以下；两者之间是保持区，归属不变。
## 不做滞回时，摇杆静止在死区边界上会让「哪根摇杆拥有朝向」逐帧翻转 ——
## 表现为角色朝向在两档之间抖动，且每帧都往 face_direction 广播一次。
const STICK_HYSTERESIS_FACTOR := 0.7
## 摇杆标识（_read_stick_axes 的入参，也是验收注入合成轴值的键）。
const STICK_LEFT := "left"
const STICK_RIGHT := "right"

var _current_device := -1
var _move_direction := Vector2.ZERO
var _face_direction := Vector2.ZERO
var _aim_angle := 0.0
var _aim_valid := false
var _shoot_active := false
## 上一帧拥有朝向的档位，滞回判定要用。
var _face_source := FACE_SOURCE_HOLD
## 验收注入的合成摇杆轴值（键 = STICK_LEFT / STICK_RIGHT）。空 = 读真实设备。
var _test_stick_axes: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_action_bindings()
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if not InputSettings.settings_changed.is_connected(_on_input_settings_changed):
		InputSettings.settings_changed.connect(_on_input_settings_changed)
	if not InputDevice.active_device_changed.is_connected(_on_active_device_changed):
		InputDevice.active_device_changed.connect(_on_active_device_changed)
	set_process(is_enabled())


func _process(delta: float) -> void:
	if not is_enabled():
		_release_all()
		set_process(false)
		return
	var device := _resolve_device()
	if device < 0:
		_release_all()
		set_process(false)
		return
	_update_move(device)
	_update_aim(device, delta)
	_update_shoot(device)


## 手柄是否应当驱动玩法：关掉手柄开关、或锁定键鼠时为 false。
func is_enabled() -> bool:
	return (
		InputSettings.is_gamepad_enabled()
		and InputSettings.get_device_mode() != InputSettings.DEVICE_MODE_KEYBOARD_MOUSE
	)


func get_current_device() -> int:
	return _current_device


func get_binding_summary() -> Dictionary:
	return GAMEPAD_ACTION_BINDINGS.duplicate(true)


## 验收专用：注入左右摇杆的合成轴值，绕过真实硬件。
## headless 下 `Input.get_joy_axis()` 恒为 0，不注入就无法端到端驱动 _update_aim；
## 与 Player3D.set_test_move_direction 同一路数。传 null / 空字典恢复读真实设备。
func set_test_stick_axes(axes: Variant) -> void:
	if axes == null:
		_test_stick_axes = {}
		return
	_test_stick_axes = (axes as Dictionary).duplicate()


func get_face_source() -> String:
	return _face_source


## 当前广播出去的面朝方向（屏幕坐标）。验收读它判断档位切换后的实际朝向。
func get_face_direction() -> Vector2:
	return _face_direction


## 虚拟瞄准是否已接管朝向。为 false 时 Player3D 的 _mobile_face_active 也是 false，
## 面朝向实际来自鼠标射线 —— 纯手柄玩家只推左摇杆时这里必须能变 true。
func is_aim_active() -> bool:
	return _aim_valid


## 判定本帧由哪根摇杆拥有朝向（纯函数，验收直接钉口径）。
## 返回 FACE_SOURCE_AIM / FACE_SOURCE_MOVE / FACE_SOURCE_HOLD。
##
## 进入某一档要越过该档死区；退出只要求掉到「死区 × STICK_HYSTERESIS_FACTOR」
## 以下 —— 两者之间是保持区，归属不变，避免摇杆停在死区边界上逐帧翻转。
## 滞回的判定优先级在「换档」之前：右摇杆还在保持区时，哪怕左摇杆已推满，
## 也仍然算右摇杆的（否则「战斗中松右摇杆」会立刻被移动方向抢走、松手甩枪）。
## 关闭「左摇杆同控朝向」时永远不会返回 FACE_SOURCE_MOVE。
func resolve_face_source(
	aim_magnitude: float,
	move_magnitude: float,
	aim_deadzone: float,
	move_deadzone: float,
	left_stick_aim_enabled: bool,
	previous_source: String
) -> String:
	if _magnitude_reaches(aim_magnitude, aim_deadzone):
		return FACE_SOURCE_AIM
	if (
		previous_source == FACE_SOURCE_AIM
		and _magnitude_reaches(aim_magnitude, aim_deadzone * STICK_HYSTERESIS_FACTOR)
	):
		return FACE_SOURCE_AIM
	if not left_stick_aim_enabled:
		return FACE_SOURCE_HOLD
	if _magnitude_reaches(move_magnitude, move_deadzone):
		return FACE_SOURCE_MOVE
	if (
		previous_source == FACE_SOURCE_MOVE
		and _magnitude_reaches(move_magnitude, move_deadzone * STICK_HYSTERESIS_FACTOR)
	):
		return FACE_SOURCE_MOVE
	return FACE_SOURCE_HOLD


## 幅度是否真的越过阈值。与 apply_radial_deadzone 共用同一容差常量，
## 避免「死区判零」与「档位判定」两处口径漂移出边界差。
func _magnitude_reaches(magnitude: float, threshold: float) -> bool:
	return magnitude > threshold + DEADZONE_COMPARE_EPSILON


## 径向死区 + 死区外重映射：刚越过死区时为 0、推到底为 1，避免跳变。
## 公开为方法，便于验收场景直接核对数值口径。
func apply_radial_deadzone(raw: Vector2, deadzone: float) -> Vector2:
	var magnitude := raw.length()
	if magnitude <= deadzone + DEADZONE_COMPARE_EPSILON or magnitude <= 0.0:
		return Vector2.ZERO
	var scaled: float = clampf(
		(magnitude - deadzone) / maxf(0.0001, 1.0 - deadzone),
		0.0,
		1.0
	)
	return raw / magnitude * scaled


func rumble(weak: float, strong: float, duration := 0.12) -> void:
	if not InputSettings.is_vibration_enabled():
		return
	var device := _resolve_device()
	if device < 0:
		return
	Input.start_joy_vibration(
		device,
		clampf(weak, 0.0, 1.0),
		clampf(strong, 0.0, 1.0),
		maxf(duration, 0.0)
	)


func stop_rumble() -> void:
	for device in Input.get_connected_joypads():
		Input.stop_joy_vibration(int(device))


func _resolve_device() -> int:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		_current_device = -1
		return -1
	if _current_device >= 0 and pads.has(_current_device):
		return _current_device
	_current_device = int(pads[0])
	return _current_device


func _update_move(device: int) -> void:
	var raw := _read_stick_axes(device, STICK_LEFT)
	var direction := apply_radial_deadzone(raw, InputSettings.get_move_deadzone())
	if direction.is_equal_approx(_move_direction):
		return
	_move_direction = direction
	move_direction.emit(direction)


## 读一根摇杆的原始轴值（x = 右为正、y = 下为正，与 MobileInput 同一坐标系）。
## 验收注入优先，其次才是真实设备。
func _read_stick_axes(device: int, stick: String) -> Vector2:
	if _test_stick_axes.has(stick):
		return _test_stick_axes[stick]
	if stick == STICK_RIGHT:
		return Vector2(
			Input.get_joy_axis(device, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)
		)
	return Vector2(
		Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
	)


func _update_aim(device: int, delta: float) -> void:
	var aim_deadzone := InputSettings.get_aim_deadzone()
	var aim_raw := _read_stick_axes(device, STICK_RIGHT)
	var left_stick_aim := InputSettings.is_left_stick_aim_enabled()
	var move_deadzone := InputSettings.get_move_deadzone()
	# 关掉左摇杆档时不必读左摇杆，也保证 move_deadzone 不参与任何判定。
	var move_raw := _read_stick_axes(device, STICK_LEFT) if left_stick_aim else Vector2.ZERO
	var source := resolve_face_source(
		aim_raw.length(),
		move_raw.length(),
		aim_deadzone,
		move_deadzone,
		left_stick_aim,
		_face_source
	)
	_face_source = source
	if source == FACE_SOURCE_HOLD:
		# 三档都够不着：保持最后方向，不广播归零（见文件头第 2 条差异）。
		return
	var active_raw := aim_raw if source == FACE_SOURCE_AIM else move_raw
	var active_deadzone := aim_deadzone if source == FACE_SOURCE_AIM else move_deadzone
	var direction := apply_radial_deadzone(active_raw, active_deadzone)
	if direction.length_squared() <= 0.0001:
		# 滞回保持区：归属没变，但幅度还没重新爬过进入阈值。
		# 此时不重取角度 —— 边界上的方向本身就很抖，写进朝向只会抖得更明显。
		return
	var target_angle := direction.angle()
	if not _aim_valid:
		# 首次推杆不平滑，否则准星会从初始角一路扫过去。
		_aim_angle = target_angle
		_aim_valid = true
	else:
		# 换档也走同一条平滑：从右摇杆切到左摇杆时角度是插值过去的，不是瞬跳。
		var rate := AIM_SMOOTHING_BASE_RATE * (1.0 - InputSettings.get_aim_smoothing())
		var weight := 1.0 - exp(-maxf(rate, 0.01) * delta)
		_aim_angle = lerp_angle(_aim_angle, target_angle, clampf(weight, 0.0, 1.0))
	_face_direction = Vector2.from_angle(_aim_angle)
	face_direction.emit(_face_direction)


func _update_shoot(device: int) -> void:
	var active := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) >= TRIGGER_THRESHOLD
	if active == _shoot_active:
		return
	_shoot_active = active
	if active:
		shoot_pressed.emit()
	else:
		shoot_released.emit()


func _release_all() -> void:
	_face_source = FACE_SOURCE_HOLD
	if _move_direction != Vector2.ZERO:
		_move_direction = Vector2.ZERO
		move_direction.emit(Vector2.ZERO)
	if _shoot_active:
		_shoot_active = false
		shoot_released.emit()
	if _aim_valid:
		# 只有真正交还控制权时才把瞄准权还给鼠标射线。
		_aim_valid = false
		_face_direction = Vector2.ZERO
		face_direction.emit(Vector2.ZERO)


func _apply_action_bindings() -> void:
	var enabled := InputSettings.is_gamepad_enabled()
	for action in GAMEPAD_ACTION_BINDINGS.keys():
		var action_name := str(action)
		if not InputMap.has_action(action_name):
			continue
		for button in GAMEPAD_ACTION_BINDINGS[action]:
			var button_index := int(button)
			if enabled:
				_ensure_joypad_button_binding(action_name, button_index)
			else:
				_erase_joypad_button_binding(action_name, button_index)


func _ensure_joypad_button_binding(action: String, button_index: int) -> void:
	if _has_joypad_button_binding(action, button_index):
		return
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button_index
	event.pressed = false
	event.pressure = 0.0
	InputMap.action_add_event(action, event)


func _erase_joypad_button_binding(action: String, button_index: int) -> void:
	for existing in _joypad_button_bindings(action, button_index):
		InputMap.action_erase_event(action, existing)


func _has_joypad_button_binding(action: String, button_index: int) -> bool:
	return not _joypad_button_bindings(action, button_index).is_empty()


func _joypad_button_bindings(action: String, button_index: int) -> Array:
	var found: Array = []
	for existing in InputMap.action_get_events(action):
		if (
			existing is InputEventJoypadButton
			and (existing as InputEventJoypadButton).button_index == button_index
		):
			found.append(existing)
	return found


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_current_device = device
		set_process(is_enabled())
		gamepad_connected.emit(device)
		return
	if _current_device == device:
		_current_device = -1
	_release_all()
	set_process(is_enabled())
	gamepad_disconnected.emit(device)


func _on_input_settings_changed(_settings: Dictionary) -> void:
	_apply_action_bindings()
	set_process(is_enabled())
	if not is_enabled():
		_release_all()


func _on_active_device_changed(device: String) -> void:
	if device != InputDevice.DEVICE_GAMEPAD:
		# 控制权交回键鼠，立刻清空手柄侧状态。
		_release_all()
	set_process(is_enabled())
