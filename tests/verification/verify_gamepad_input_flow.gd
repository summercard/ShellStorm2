extends Node
## 手柄操控验收：输入设置持久化与夹取、设备自动检测/锁定、运行时按键注入、
## 摇杆死区口径、朝向来源三档（右摇杆 → 左摇杆 → 保持上次）与滞回，
## 以及 ESC「操作设置」页的接线完整性。
##
## 手柄硬件在 headless 下不存在，因此这里全部用「合成事件 + 纯函数口径 +
## 合成摇杆轴值」验证：不依赖真实设备，也能把判定逻辑与界面接线钉死。

const PAUSE_SCENE: PackedScene = preload("res://assets/art/ui/pause_3d/ui_pause_overlay_screen.tscn")
const DUNGEON_SCRIPT := "res://src/world3d/Dungeon3D.gd"
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")

## 期望的手柄键位表：action → 手柄键。与 GamepadInput.GAMEPAD_ACTION_BINDINGS 对齐。
const EXPECTED_BINDINGS := {
	"ui_accept": JOY_BUTTON_A,
	"ui_cancel": JOY_BUTTON_B,
	"interact": JOY_BUTTON_A,
	"dash": JOY_BUTTON_B,
	"reload": JOY_BUTTON_X,
	"toggle_flashlight": JOY_BUTTON_Y,
	"select_primary_weapon": JOY_BUTTON_LEFT_SHOULDER,
	"select_secondary_weapon": JOY_BUTTON_RIGHT_SHOULDER,
	"use_quick_item_1": JOY_BUTTON_DPAD_LEFT,
	"use_quick_item_2": JOY_BUTTON_DPAD_RIGHT,
	"ui_inventory": JOY_BUTTON_BACK,
	"toggle_floor_map": JOY_BUTTON_LEFT_STICK,
	"pause": JOY_BUTTON_START,
}

## 只走 InputMap action 通路（不再硬比 keycode）的五个玩法动作。
const ACTION_CHANNEL_ACTIONS := [
	"toggle_floor_map",
	"select_primary_weapon",
	"select_secondary_weapon",
	"use_quick_item_1",
	"use_quick_item_2",
]

## 设施子界面的焦点锚点：这些 CanvasLayer 菜单由 BaseWorld3D._open_menu() 打开，
## 打开时并不 grab_focus()。没有焦点持有者时，十字键/摇杆导航（ui_up/down/left/right）
## 与 A 键确认（ui_accept）都无处落脚 —— 手柄在这些子界面里会完全失灵。
## 清单与 BaseFacilityCatalog 里 action_kind == ACTION_MENU 的 action_path 一一对应。
const FACILITY_MENU_SCENES := [
	"res://scenes/RogueMapSelectMenu.tscn",
	"res://scenes/WorkshopMenu.tscn",
	"res://scenes/VaultMenu.tscn",
	"res://scenes/MonsterArchiveMenu.tscn",
	"res://scenes/FateCardCollectionMenu.tscn",
	"res://scenes/BaseVendingMenu.tscn",
	"res://scenes/BaseRecoveryMenu.tscn",
	"res://scenes/ui/WardrobeMenu3D.tscn",
]


func _ready() -> void:
	var failures: Array[String] = []
	var original := InputSettings.get_settings_snapshot()
	_verify_autoloads(failures)
	_verify_settings_sanitize(failures)
	_verify_runtime_bindings(failures)
	_verify_deadzone_math(failures)
	_verify_face_source_tiers(failures)
	_verify_device_tracking(failures)
	_verify_action_channels(failures)
	_verify_menu_navigation(failures)
	_verify_face_case_sentinel(_verify_left_stick_face_flow(failures), failures)
	await _verify_submenu_focus_anchor(failures)
	await _verify_aim_projection(failures)
	await _verify_pause_controls_page(failures)
	for key in original.keys():
		InputSettings.set_value(str(key), original[key], true)
	_finish(failures)


func _verify_autoloads(failures: Array[String]) -> void:
	for singleton in ["InputSettings", "InputDevice", "GamepadInput"]:
		if get_node_or_null("/root/" + singleton) == null:
			failures.append("自动加载单例缺失：%s" % singleton)
	for method in ["get_settings_snapshot", "set_value", "get_device_mode", "is_gamepad_enabled"]:
		if not InputSettings.has_method(method):
			failures.append("InputSettings 缺少方法：%s" % method)
	for method in ["get_active_device", "has_connected_gamepad", "force_device"]:
		if not InputDevice.has_method(method):
			failures.append("InputDevice 缺少方法：%s" % method)
	for method in [
		"apply_radial_deadzone",
		"resolve_face_source",
		"set_test_stick_axes",
		"get_face_source",
		"get_face_direction",
		"is_aim_active",
		"rumble",
		"stop_rumble",
		"is_enabled",
	]:
		if not GamepadInput.has_method(method):
			failures.append("GamepadInput 缺少方法：%s" % method)
	if InputSettings.DEVICE_MODES.size() != 3:
		failures.append("操控方式没有提供自动/键鼠/手柄三种取值")


func _verify_settings_sanitize(failures: Array[String]) -> void:
	InputSettings.set_value("gamepad_move_deadzone", 99.0, false)
	if not is_equal_approx(InputSettings.get_move_deadzone(), InputSettings.DEADZONE_RANGE.y):
		failures.append("摇杆死区超上限没有被夹取")
	InputSettings.set_value("gamepad_move_deadzone", -3.0, false)
	if not is_equal_approx(InputSettings.get_move_deadzone(), InputSettings.DEADZONE_RANGE.x):
		failures.append("摇杆死区超下限没有被夹取")
	InputSettings.set_value("gamepad_left_stick_aim", 0.0, false)
	if InputSettings.is_left_stick_aim_enabled():
		failures.append("「左摇杆同控朝向」的数值 0 没有回落为 false")
	InputSettings.set_value("gamepad_left_stick_aim", 1.0, false)
	if not InputSettings.is_left_stick_aim_enabled():
		failures.append("「左摇杆同控朝向」的数值 1 没有回落为 true")
	InputSettings.set_value("gamepad_left_stick_aim", true, false)
	InputSettings.set_value("gamepad_aim_smoothing", 7.0, false)
	if not is_equal_approx(InputSettings.get_aim_smoothing(), InputSettings.AIM_SMOOTHING_RANGE.y):
		failures.append("瞄准平滑超上限没有被夹取")
	InputSettings.set_value("gamepad_aim_smoothing", -2.0, false)
	if not is_equal_approx(InputSettings.get_aim_smoothing(), InputSettings.AIM_SMOOTHING_RANGE.x):
		failures.append("瞄准平滑超下限没有被夹取")
	InputSettings.set_value("device_mode", "nonsense", false)
	if InputSettings.get_device_mode() != InputSettings.DEVICE_MODE_AUTO:
		failures.append("非法操控方式没有回落自动")
	if InputSettings.set_value("not_a_real_key", 1, false):
		failures.append("未知设置键没有被拒绝")
	InputSettings.set_value("device_mode", InputSettings.DEVICE_MODE_AUTO, false)
	InputSettings.set_value("gamepad_move_deadzone", InputSettings.DEFAULT_SETTINGS["gamepad_move_deadzone"], false)
	InputSettings.set_value("gamepad_aim_smoothing", InputSettings.DEFAULT_SETTINGS["gamepad_aim_smoothing"], false)
	InputSettings.set_value("gamepad_left_stick_aim", InputSettings.DEFAULT_SETTINGS["gamepad_left_stick_aim"], false)


func _verify_runtime_bindings(failures: Array[String]) -> void:
	InputSettings.set_value("gamepad_enabled", true, false)
	var summary := GamepadInput.get_binding_summary()
	if summary.size() != EXPECTED_BINDINGS.size():
		failures.append(
			"运行时手柄绑定条数不符：%d / 期望 %d" % [summary.size(), EXPECTED_BINDINGS.size()]
		)
	for action in EXPECTED_BINDINGS.keys():
		var action_name := str(action)
		if not InputMap.has_action(action_name):
			failures.append("InputMap 缺少动作：%s" % action_name)
			continue
		if not _has_joypad_button(action_name, int(EXPECTED_BINDINGS[action])):
			failures.append(
				"%s 没有注入手柄键位 %d" % [action_name, int(EXPECTED_BINDINGS[action])]
			)
	InputSettings.set_value("gamepad_enabled", false, false)
	for action in EXPECTED_BINDINGS.keys():
		if _has_joypad_button(str(action), int(EXPECTED_BINDINGS[action])):
			failures.append("关闭手柄后 %s 仍保留手柄键位" % str(action))
	InputSettings.set_value("gamepad_enabled", true, false)
	for action in EXPECTED_BINDINGS.keys():
		if not _has_joypad_button(str(action), int(EXPECTED_BINDINGS[action])):
			failures.append("重新开启手柄后 %s 没有恢复手柄键位" % str(action))


func _verify_deadzone_math(failures: Array[String]) -> void:
	if GamepadInput.apply_radial_deadzone(Vector2.ZERO, 0.2) != Vector2.ZERO:
		failures.append("摇杆归零没有被识别为死区")
	if GamepadInput.apply_radial_deadzone(Vector2(0.1, 0.0), 0.2) != Vector2.ZERO:
		failures.append("死区内的轻微漂移没有被压掉")
	if GamepadInput.apply_radial_deadzone(Vector2(0.2, 0.0), 0.2) != Vector2.ZERO:
		failures.append("正好等于死区的输入没有被压掉")
	var full := GamepadInput.apply_radial_deadzone(Vector2(1.0, 0.0), 0.2)
	if not full.is_equal_approx(Vector2(1.0, 0.0)):
		failures.append("摇杆推到底没有映射到满量程")
	var half := GamepadInput.apply_radial_deadzone(Vector2(0.6, 0.0), 0.2)
	if not is_equal_approx(half.x, 0.5) or not is_equal_approx(half.y, 0.0):
		failures.append("死区外没有按 (m−dz)/(1−dz) 重映射：%s" % str(half))
	var diagonal := GamepadInput.apply_radial_deadzone(Vector2(0.6, 0.8) * 0.5, 0.2)
	if not is_equal_approx(diagonal.length(), 0.375):
		failures.append("斜向推杆的幅度重映射不正确：%f" % diagonal.length())
	if not diagonal.normalized().is_equal_approx(Vector2(0.6, 0.8)):
		failures.append("死区重映射破坏了推杆方向")
	var previous := -1.0
	for step in 21:
		var magnitude := float(step) / 20.0
		var mapped := GamepadInput.apply_radial_deadzone(Vector2(magnitude, 0.0), 0.2).length()
		if mapped < previous - 0.0001:
			failures.append("死区重映射不是单调递增（%f → %f）" % [previous, mapped])
			break
		previous = mapped


## 朝向来源三档的口径（纯函数）。这套判定决定了「左摇杆到底算不算在控朝向」，
## 一旦有人把滞回拿掉或让关闭开关后仍返回 move，这里必须变红。
func _verify_face_source_tiers(failures: Array[String]) -> void:
	var aim_source := GamepadInput.FACE_SOURCE_AIM
	var move_source := GamepadInput.FACE_SOURCE_MOVE
	var hold_source := GamepadInput.FACE_SOURCE_HOLD
	var dz := 0.20
	var release := dz * GamepadInput.STICK_HYSTERESIS_FACTOR
	if not is_equal_approx(GamepadInput.STICK_HYSTERESIS_FACTOR, 0.7):
		failures.append("摇杆滞回系数被改动，边界口径与验收不一致")
	var unique_sources := {}
	for source in [aim_source, move_source, hold_source]:
		unique_sources[source] = true
	if unique_sources.size() != 3:
		failures.append("朝向来源三个档位的取值有重复，档位判定会混淆")

	var resolve := func(aim_mag: float, move_mag: float, enabled: bool, prev: String) -> String:
		return GamepadInput.resolve_face_source(aim_mag, move_mag, dz, dz, enabled, prev)

	# 1) 右摇杆越过死区 → 永远归右摇杆，与左摇杆无关。
	if resolve.call(0.5, 0.0, true, hold_source) != aim_source:
		failures.append("右摇杆推过死区没有夺得朝向")
	if resolve.call(0.5, 1.0, true, hold_source) != aim_source:
		failures.append("左摇杆推满时右摇杆失去最高优先（边退边打会失效）")
	# 2) 右摇杆回中 + 左摇杆越过移动死区 → 左摇杆接管。
	if resolve.call(0.0, 0.5, true, aim_source) != move_source:
		failures.append("右摇杆回中后左摇杆没有接管朝向")
	# 3) 关闭开关 → 任何右摇杆幅度都不返回 move。
	for move_mag in [0.0, 0.25, 1.0]:
		if resolve.call(0.0, move_mag, false, hold_source) == move_source:
			failures.append("关闭「左摇杆同控朝向」后仍返回左摇杆档（幅度 %f）" % move_mag)
	if resolve.call(1.0, 1.0, false, hold_source) != aim_source:
		failures.append("关闭左摇杆档后右摇杆也不管用了")
	# 4) 两档都够不着 → 保持上次（绝不归零，归零会让玩家掉回鼠标射线）。
	if resolve.call(0.0, 0.0, true, move_source) != hold_source:
		failures.append("两根摇杆都回中时没有保持上次方向")

	# 5) 滞回：进入要越过死区，退出只在掉到「死区 × 系数」以下才发生。
	if resolve.call(release + 0.001, 1.0, true, aim_source) != aim_source:
		failures.append("右摇杆在保持区内没有留住朝向（会在死区边界逐帧换档）")
	if resolve.call(release - 0.001, 1.0, true, aim_source) != move_source:
		failures.append("右摇杆掉到保持区以下后没有把朝向交给左摇杆")
	if resolve.call(release + 0.001, 0.0, true, hold_source) != hold_source:
		failures.append("未持有朝向时也走了保持区（滞回被当成进入阈值）")
	if resolve.call(release + 0.001, 1.0, true, hold_source) == aim_source:
		failures.append("上一帧没有持有朝向，仅靠保持区就夺走了朝向（摇杆静息会永久占住右摇杆档）")
	# 6) 边界点与 apply_radial_deadzone 共用容差：正好等于死区不算越过。
	if resolve.call(dz, 0.0, true, hold_source) != hold_source:
		failures.append("右摇杆幅度正好等于死区却算作越过了死区")
	if resolve.call(dz + GamepadInput.DEADZONE_COMPARE_EPSILON * 10.0, 0.0, true, hold_source) != aim_source:
		failures.append("右摇杆刚越过死区却没有夺得朝向")
	# 7) 升档 / 降档各只切一次，且两个切换点不重合 —— 不重合的宽度就是滞回，
	#    宽度为零时摇杆停在切换点上会让朝向逐帧在两档之间翻转。
	var up_switch := -1.0
	var became_aim := 0
	var previous_source := hold_source
	for index in 101:
		var aim_mag := float(index) / 100.0
		var source: String = resolve.call(aim_mag, 0.9, true, previous_source)
		if source == aim_source and previous_source != aim_source:
			became_aim += 1
			if up_switch < 0.0:
				up_switch = aim_mag
		previous_source = source
	if became_aim != 1:
		failures.append("右摇杆幅度上升时夺得朝向 %d 次（应当只有一次）" % became_aim)
	if up_switch < dz - 0.011:
		failures.append("右摇杆升档点 %.3f 明显低于死区 %.2f" % [up_switch, dz])
	if previous_source != aim_source:
		failures.append("右摇杆推满后档位不是右摇杆：%s" % previous_source)

	var down_switch := -1.0
	var left_aim := 0
	previous_source = aim_source
	for index in 101:
		var aim_mag := 1.0 - float(index) / 100.0
		var source: String = resolve.call(aim_mag, 0.9, true, previous_source)
		if source != aim_source and previous_source == aim_source:
			left_aim += 1
			if down_switch < 0.0:
				down_switch = aim_mag
		previous_source = source
	if left_aim != 1:
		failures.append("右摇杆幅度下降时交出朝向 %d 次（应当只有一次）" % left_aim)
	if previous_source != move_source:
		failures.append("右摇杆降档后没有交给左摇杆：%s" % previous_source)
	if down_switch > release + 0.011:
		failures.append("右摇杆降档点 %.3f 明显高于保持阈值 %.3f" % [down_switch, release])
	if down_switch >= up_switch:
		failures.append(
			"滞回没有产生宽度：升档点 %.3f 未高于降档点 %.3f" % [up_switch, down_switch])


## 三档朝向的端到端行为：直接驱动 GamepadInput._update_aim，
## 用合成轴值绕过真实硬件（headless 下没有手柄，Input.get_joy_axis 恒为 0）。
##
## 返回本用例实际推进的帧数与执行的断言数，供调用方做「没被静默截断」的哨兵 ——
## GDScript 的 SCRIPT ERROR 会把整个用例截断，症状只是后面的断言一条都没跑，
## 失败列表照样为空（见 .workbuddy/memory 2026-09-22 的 1115 事务）。
func _verify_left_stick_face_flow(failures: Array[String]) -> Dictionary:
	var was_processing := GamepadInput.is_processing()
	GamepadInput.set_process(false)
	var previous := {
		"gamepad_enabled": InputSettings.is_gamepad_enabled(),
		"device_mode": InputSettings.get_device_mode(),
		"gamepad_left_stick_aim": InputSettings.is_left_stick_aim_enabled(),
		"gamepad_aim_deadzone": InputSettings.get_aim_deadzone(),
		"gamepad_move_deadzone": InputSettings.get_move_deadzone(),
		"gamepad_aim_smoothing": InputSettings.get_aim_smoothing(),
	}
	InputSettings.set_value("gamepad_enabled", true, false)
	InputSettings.set_value("device_mode", InputSettings.DEVICE_MODE_AUTO, false)
	InputSettings.set_value("gamepad_left_stick_aim", true, false)
	InputSettings.set_value("gamepad_aim_deadzone", 0.20, false)
	InputSettings.set_value("gamepad_move_deadzone", 0.20, false)
	InputSettings.set_value("gamepad_aim_smoothing", 0.35, false)

	# 计数器必须是 Dictionary：GDScript 的 lambda 按值捕获，int 改了外面看不见。
	var counters := {"frames": 0, "checks": 0}
	var guard := func(condition: bool, message: String) -> void:
		counters["checks"] += 1
		if not condition:
			failures.append(message)
	var emitted: Array[Vector2] = []
	var on_face := func(direction: Vector2) -> void:
		emitted.append(direction)
	GamepadInput.face_direction.connect(on_face)
	var step := func(left: Vector2, right: Vector2, frames := 1) -> void:
		# InputSettings.set_value 会广播 settings_changed，autoload 的 _on_input_settings_changed
		# 顺手把 _process 打开；它一旦跑起来就会因为没有真实手柄而 _release_all()，
		# 把本用例刚要建立的档位状态清掉。每步压回去，让状态完全由用例自己推进。
		GamepadInput.set_process(false)
		GamepadInput.set_test_stick_axes({"left": left, "right": right})
		for _frame in frames:
			counters["frames"] += 1
			GamepadInput.call("_update_aim", 0, 1.0 / 60.0)
	var face_of := func() -> Vector2:
		return GamepadInput.get_face_direction()
	var reset := func() -> void:
		GamepadInput.call("_release_all")

	# A) 右摇杆夺得朝向：首次推杆直接对齐，不平滑（不平滑是既有契约）。
	reset.call()
	step.call(Vector2.ZERO, Vector2(1.0, 0.0))
	var first_face: Vector2 = face_of.call()
	guard.call(
		_angle_close(first_face, 0.0),
		"右摇杆推右没有把朝向右对齐：%s" % str(first_face))
	guard.call(
		GamepadInput.get_face_source() == GamepadInput.FACE_SOURCE_AIM,
		"右摇杆推杆后档位不是右摇杆：%s" % GamepadInput.get_face_source())

	# B) 松右摇杆 + 左摇杆推下 → 交给左摇杆，而且是**插值过去**的，不是瞬跳。
	#    （90° 的档位切换在第一帧只许走一小部分，否则就是「甩枪」。）
	step.call(Vector2(0.0, 1.0), Vector2.ZERO)
	var first_frame: Vector2 = face_of.call()
	var moved: float = absf(_angle_delta(Vector2(1.0, 0.0), first_frame))
	var remaining: float = absf(_angle_delta(first_frame, Vector2(0.0, 1.0)))
	guard.call(
		GamepadInput.get_face_source() == GamepadInput.FACE_SOURCE_MOVE,
		"右摇杆回中后左摇杆没有接管朝向")
	guard.call(moved > 0.0, "松右摇杆后朝向完全没动（左摇杆档没生效）")
	guard.call(
		moved <= deg_to_rad(45.0),
		"松右摇杆后朝向一帧内跳了 %.1f°，没有经过 aim 平滑（会甩枪）" % rad_to_deg(moved))
	guard.call(
		remaining < deg_to_rad(89.0),
		"朝向一帧就跳到了左摇杆方向，平滑没有生效")
	# 继续给足帧数，最终必须收敛到左摇杆方向（推下 = +y）。
	step.call(Vector2(0.0, 1.0), Vector2.ZERO, 60)
	var settled: Vector2 = face_of.call()
	guard.call(
		_angle_close(settled, PI * 0.5),
		"多帧之后朝向没有收敛到左摇杆方向：%s" % str(settled))

	# C) 边界震荡：右摇杆在死区上下摆动、左摇杆推满 → 档位必须锁死在右摇杆。
	reset.call()
	step.call(Vector2(1.0, 0.0), Vector2(0.5, 0.0))
	var oscillation_switched := false
	for index in 12:
		var aim_mag := 0.19 if index % 2 == 0 else 0.21
		step.call(Vector2(1.0, 0.0), Vector2(aim_mag, 0.0))
		if GamepadInput.get_face_source() != GamepadInput.FACE_SOURCE_AIM:
			oscillation_switched = true
			break
	guard.call(
		not oscillation_switched,
		"右摇杆在死区边界摆动时朝向档位被左摇杆抢走（滞回失效，会逐帧抖）")

	# D) 关闭开关：左摇杆推满也只保持上次方向，且一次都不广播。
	InputSettings.set_value("gamepad_left_stick_aim", false, false)
	reset.call()
	step.call(Vector2.ZERO, Vector2(1.0, 0.0))
	var held_before: Vector2 = face_of.call()
	emitted.clear()
	step.call(Vector2(0.0, 1.0), Vector2.ZERO, 8)
	guard.call(
		GamepadInput.get_face_source() == GamepadInput.FACE_SOURCE_HOLD,
		"关闭开关后档位不是保持档：%s" % GamepadInput.get_face_source())
	guard.call(
		face_of.call().is_equal_approx(held_before),
		"关闭开关后左摇杆仍然改动了朝向：%s → %s" % [str(held_before), str(face_of.call())])
	guard.call(
		emitted.is_empty(),
		"保持档广播了 face_direction（%d 次），会打断鼠标射线回落" % emitted.size())

	# E) 纯手柄新手：从没碰过右摇杆，只推左摇杆也必须激活虚拟瞄准。
	#    不激活时 Player3D 的 _mobile_face_active 恒为 false，朝向实际来自鼠标射线。
	InputSettings.set_value("gamepad_left_stick_aim", true, false)
	reset.call()
	guard.call(
		not GamepadInput.is_aim_active(),
		"重置后瞄准仍是有效状态，无法验证首次推杆")
	step.call(Vector2(1.0, 0.0), Vector2.ZERO)
	guard.call(
		GamepadInput.is_aim_active(),
		"只推左摇杆没有激活虚拟瞄准（朝向仍会来自鼠标射线）")
	var left_only_face: Vector2 = face_of.call()
	guard.call(
		_angle_close(left_only_face, 0.0),
		"只推左摇杆时朝向不是移动方向：%s" % str(left_only_face))

	# F) 交还控制权必须复位档位，否则切回键鼠再切回来会带着陈旧归属。
	reset.call()
	guard.call(
		GamepadInput.get_face_source() == GamepadInput.FACE_SOURCE_HOLD,
		"_release_all 没有复位朝向档位")

	GamepadInput.face_direction.disconnect(on_face)
	GamepadInput.set_test_stick_axes(null)
	for key in previous.keys():
		InputSettings.set_value(str(key), previous[key], false)
	GamepadInput.set_process(was_processing)
	print(
		"[samples] 三档朝向行为用例：_update_aim 步进 %d 帧，断言执行 %d 条"
		% [counters["frames"], counters["checks"]])
	return counters


## 哨兵：用例被 SCRIPT ERROR 静默截断时失败列表是空的，只能靠「跑了多少」识破。
## ⚠️ 两个阈值故意贴紧当前实际值（85 帧 / 15 条）：少一条断言就算截断。
## 平时改动这个用例的断言条数或帧数时，必须同步更新这里的阈值。
func _verify_face_case_sentinel(counters: Variant, failures: Array[String]) -> void:
	var frames := 0
	var checks := 0
	if counters is Dictionary:
		frames = int((counters as Dictionary).get("frames", 0))
		checks = int((counters as Dictionary).get("checks", 0))
	if frames < 80:
		failures.append("三档朝向行为用例只步进了 %d 帧（应 ≥ 80），用例被截断" % frames)
	if checks < 15:
		failures.append("三档朝向行为用例只执行了 %d 条断言（应 ≥ 15），用例被截断" % checks)


func _angle_close(face: Vector2, radians: float) -> bool:
	return absf(_angle_delta(face, Vector2.from_angle(radians))) <= deg_to_rad(1.5)


func _angle_delta(from_face: Vector2, to_face: Vector2) -> float:
	if from_face.length_squared() <= 0.0001 or to_face.length_squared() <= 0.0001:
		return 0.0
	return wrapf(to_face.angle() - from_face.angle(), -PI, PI)



func _verify_device_tracking(failures: Array[String]) -> void:
	var previous_mode := InputSettings.get_device_mode()
	var previous_enabled := InputSettings.is_gamepad_enabled()
	var joy := InputEventJoypadButton.new()
	joy.device = 0
	joy.button_index = JOY_BUTTON_A
	joy.pressed = true

	InputSettings.set_value("gamepad_enabled", true, false)
	InputSettings.set_value("device_mode", InputSettings.DEVICE_MODE_AUTO, false)
	InputDevice.force_device(InputDevice.DEVICE_KEYBOARD_MOUSE)
	InputDevice.call("_input", joy)
	if InputDevice.get_active_device() != InputDevice.DEVICE_GAMEPAD:
		failures.append("自动模式下按手柄没有切换到手柄提示")

	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(24.0, 0.0)
	InputDevice.call("_input", motion)
	if InputDevice.get_active_device() != InputDevice.DEVICE_KEYBOARD_MOUSE:
		failures.append("移动鼠标没有切回键鼠提示")

	var micro := InputEventMouseMotion.new()
	micro.relative = Vector2(1.0, 0.0)
	InputDevice.call("_input", joy)
	InputDevice.call("_input", micro)
	if InputDevice.get_active_device() != InputDevice.DEVICE_GAMEPAD:
		failures.append("鼠标微小抖动不该夺走手柄判定")

	InputSettings.set_value("device_mode", InputSettings.DEVICE_MODE_KEYBOARD_MOUSE, false)
	InputDevice.force_device(InputDevice.DEVICE_KEYBOARD_MOUSE)
	InputDevice.call("_input", joy)
	if InputDevice.get_active_device() != InputDevice.DEVICE_KEYBOARD_MOUSE:
		failures.append("锁定键鼠后手柄事件仍然夺权")

	InputSettings.set_value("device_mode", InputSettings.DEVICE_MODE_GAMEPAD, false)
	if InputDevice.has_connected_gamepad():
		if InputDevice.get_active_device() != InputDevice.DEVICE_GAMEPAD:
			failures.append("锁定手柄且手柄在位时没有切到手柄")
	else:
		if InputDevice.get_active_device() != InputDevice.DEVICE_KEYBOARD_MOUSE:
			failures.append("锁定手柄但没有手柄时没有回落键鼠（会留下死状态）")

	InputSettings.set_value("device_mode", InputSettings.DEVICE_MODE_AUTO, false)
	InputSettings.set_value("gamepad_enabled", false, false)
	InputDevice.force_device(InputDevice.DEVICE_KEYBOARD_MOUSE)
	InputDevice.call("_input", joy)
	if InputDevice.get_active_device() != InputDevice.DEVICE_KEYBOARD_MOUSE:
		failures.append("手柄开关关闭后自动模式仍然认定手柄")

	InputSettings.set_value("device_mode", previous_mode, false)
	InputSettings.set_value("gamepad_enabled", previous_enabled, false)
	InputDevice.force_device(InputDevice.DEVICE_KEYBOARD_MOUSE)


func _verify_action_channels(failures: Array[String]) -> void:
	var script := load(DUNGEON_SCRIPT) as GDScript
	if script == null:
		failures.append("Dungeon3D 脚本无法加载，无法核对 action 通路")
		return
	var method_names: Array[String] = []
	for entry in script.get_script_method_list():
		method_names.append(str((entry as Dictionary).get("name", "")))
	if not method_names.has("_can_switch_weapon_slot"):
		failures.append("Dungeon3D 缺少 _can_switch_weapon_slot（M/1/2/3/4 的 action 通路不完整）")
	InputSettings.set_value("gamepad_enabled", true, false)
	for action in ACTION_CHANNEL_ACTIONS:
		if not InputMap.has_action(action):
			failures.append("InputMap 缺少动作：%s" % action)
			continue
		if not _has_key_binding(action):
			failures.append("%s 丢失了键盘绑定，改走 action 通路会直接失效" % action)
		if not _has_joypad_button(action, int(EXPECTED_BINDINGS[action])):
			failures.append("%s 没有手柄绑定，改走 action 通路会少一半输入" % action)


func _verify_menu_navigation(failures: Array[String]) -> void:
	# project.godot 的 [input] 段覆盖了 ui_accept / ui_cancel 的引擎默认值（只剩键盘），
	# 所以这两个的手柄键位必须由 GamepadInput 注入，否则手柄确认/返回是死的。
	# ui_up/down/left/right 没有被覆盖，仍带引擎默认的十字键与左摇杆轴绑定；
	# 这里钉住这条前提：一旦有人把 ui_* 也写进 project.godot，菜单导航会静默失效。
	for action in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		if not InputMap.has_action(action):
			failures.append("InputMap 缺少菜单导航动作：%s" % action)
			continue
		if not _has_joypad_direction(action):
			failures.append("%s 没有手柄方向绑定，手柄无法在菜单里导航" % action)
	if not _has_joypad_button("ui_accept", JOY_BUTTON_A):
		failures.append("ui_accept 没有手柄确认键，操作设置页无法用手柄改动")
	if not _has_joypad_button("ui_cancel", JOY_BUTTON_B):
		failures.append("ui_cancel 没有手柄返回键，操作设置页无法用手柄退出")


func _has_joypad_direction(action: String) -> bool:
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadButton or existing is InputEventJoypadMotion:
			return true
	return false


## 虚拟瞄准方向（右摇杆 / 移动端右摇杆共用同一条投影）。
## 口径：face_direction 是屏幕坐标，推右 = x+1、推上 = y−1；
## 经相机投影后应落在同侧，否则玩家会看到「推右往左瞄」。
func _verify_aim_projection(failures: Array[String]) -> void:
	var player := PLAYER_SCENE.instantiate() as Player3D
	if player == null:
		failures.append("Player3D 场景无法实例化，瞄准方向未核对")
		return
	add_child(player)
	await get_tree().process_frame
	var cam := player.camera
	if cam == null:
		failures.append("Player3D 没有相机，瞄准方向未核对")
		player.queue_free()
		return
	player.set("_mobile_face_active", true)
	for pitch in [-50.0, -65.0]:
		for yaw in [0.0, 90.0, 180.0, -90.0]:
			cam.rotation_degrees = Vector3(pitch, yaw, 0.0)
			var basis := cam.global_basis
			var cam_right := basis.x
			var cam_forward := -Vector3(basis.z.x, 0.0, basis.z.z).normalized()
			var label := "pitch=%.0f/yaw=%.0f" % [pitch, yaw]
			_expect_alignment(player, Vector2(1.0, 0.0), cam_right, 1.0,
				"推右应朝屏幕右", label, failures)
			_expect_alignment(player, Vector2(-1.0, 0.0), cam_right, -1.0,
				"推左应朝屏幕左", label, failures)
			_expect_alignment(player, Vector2(0.0, -1.0), cam_forward, 1.0,
				"推上应朝屏幕上方", label, failures)
			_expect_alignment(player, Vector2(0.0, 1.0), cam_forward, -1.0,
				"推下应朝屏幕下方", label, failures)
			# 反向对照：旧公式把前方逆时针转 90°，算出来的是「屏幕左」。
			# 一旦有人把 right_2d 改回逆时针，这里的点乘会反过来、断言立刻变红。
			var stale_forward := -Vector2(basis.z.x, basis.z.z).normalized()
			var stale_right := Vector2(stale_forward.y, -stale_forward.x)
			var stale_aim := stale_right * 1.0
			var stale_dir := Vector3(stale_aim.x, 0.0, stale_aim.y)
			if stale_dir.dot(cam_right) > 0.5:
				failures.append(
					"反向对照失效：旧的逆时针 right_2d 在 %s 下也指向屏幕右" % label
				)
	player.queue_free()
	await get_tree().process_frame


func _expect_alignment(
	player: Player3D,
	face: Vector2,
	reference: Vector3,
	sign: float,
	message: String,
	label: String,
	failures: Array[String]
) -> void:
	player.set("_mobile_face_direction", face)
	var aim := player.call("_get_mobile_face_direction") as Vector3
	if aim.length_squared() < 0.25:
		failures.append("%s（%s）没有给出瞄准方向" % [message, label])
		return
	if not aim.is_normalized():
		failures.append("%s（%s）的瞄准方向不是单位向量：%f" % [message, label, aim.length()])
	var dot := aim.dot(reference)
	if dot * sign <= 0.9:
		failures.append(
			"%s（%s）方向不对：与参考轴点乘 %+.3f（期望同号且接近 1）" % [message, label, dot]
		)

func _verify_pause_controls_page(failures: Array[String]) -> void:
	var pause := PAUSE_SCENE.instantiate() as PauseMenu3D
	if pause == null:
		failures.append("暂停覆盖层场景无法实例化")
		return
	add_child(pause)
	await get_tree().process_frame
	var main_page := pause.get_node_or_null("Center/Panel/Margin/MainPage") as Control
	var graphics_page := pause.get_node_or_null("Center/Panel/Margin/GraphicsPage") as Control
	var controls_page := pause.get_node_or_null("Center/Panel/Margin/ControlsPage") as Control
	var controls_button := pause.get_node_or_null("Center/Panel/Margin/MainPage/ControlsButton") as Button
	if main_page == null or graphics_page == null or controls_page == null or controls_button == null:
		failures.append("暂停菜单缺少操作设置入口或操作设置页")
		pause.queue_free()
		await get_tree().process_frame
		return
	if not main_page.visible or controls_page.visible or graphics_page.visible:
		failures.append("暂停菜单初始状态应停在主页")
	var mode_option := pause.get_node("Center/Panel/Margin/ControlsPage/DeviceRow/DeviceModeOption") as OptionButton
	var enabled_toggle := pause.get_node("Center/Panel/Margin/ControlsPage/GamepadEnabled") as CheckButton
	var vibration_toggle := pause.get_node("Center/Panel/Margin/ControlsPage/Vibration") as CheckButton
	var move_slider := pause.get_node("Center/Panel/Margin/ControlsPage/MoveDeadzoneRow/MoveDeadzoneSlider") as HSlider
	var move_value := pause.get_node("Center/Panel/Margin/ControlsPage/MoveDeadzoneRow/MoveDeadzoneValue") as Label
	var aim_slider := pause.get_node("Center/Panel/Margin/ControlsPage/AimDeadzoneRow/AimDeadzoneSlider") as HSlider
	var smoothing_slider := pause.get_node("Center/Panel/Margin/ControlsPage/AimSmoothingRow/AimSmoothingSlider") as HSlider
	var left_stick_aim_toggle := pause.get_node_or_null("Center/Panel/Margin/ControlsPage/LeftStickAim") as CheckButton
	var status := pause.get_node("Center/Panel/Margin/ControlsPage/Footer/Status") as Label
	var device_status := pause.get_node("Center/Panel/Margin/ControlsPage/Header/DeviceStatusLabel") as Label
	if mode_option.item_count != InputSettings.DEVICE_MODES.size():
		failures.append("操控方式下拉项数与设置项不一致")
	if not is_equal_approx(move_slider.min_value, InputSettings.DEADZONE_RANGE.x):
		failures.append("左摇杆死区滑条下限与设置常量不一致")
	if not is_equal_approx(move_slider.max_value, InputSettings.DEADZONE_RANGE.y):
		failures.append("左摇杆死区滑条上限与设置常量不一致")
	if not is_equal_approx(aim_slider.min_value, InputSettings.DEADZONE_RANGE.x):
		failures.append("右摇杆死区滑条下限与设置常量不一致")
	if not is_equal_approx(aim_slider.max_value, InputSettings.DEADZONE_RANGE.y):
		failures.append("右摇杆死区滑条上限与设置常量不一致")
	if not is_equal_approx(smoothing_slider.max_value, InputSettings.AIM_SMOOTHING_RANGE.y):
		failures.append("瞄准平滑滑条上限与设置常量不一致")
	if not device_status.text.begins_with("当前输入："):
		failures.append("操作设置页没有显示当前输入设备")
	if not enabled_toggle.button_pressed:
		failures.append("操作设置页没有同步手柄开关初值")
	if left_stick_aim_toggle == null:
		failures.append("操作设置页缺少「左摇杆同控朝向」开关")
	elif not left_stick_aim_toggle.button_pressed:
		failures.append("「左摇杆同控朝向」开关没有同步初值")

	# 界面 → 设置：每类控件都必须真的写进 InputSettings。
	enabled_toggle.button_pressed = false
	if InputSettings.is_gamepad_enabled():
		failures.append("关闭手柄开关没有写回设置")
	enabled_toggle.button_pressed = true
	if not InputSettings.is_gamepad_enabled():
		failures.append("重新开启手柄开关没有写回设置")
	vibration_toggle.button_pressed = false
	if InputSettings.is_vibration_enabled():
		failures.append("关闭手柄震动没有写回设置")
	vibration_toggle.button_pressed = true
	if not InputSettings.is_vibration_enabled():
		failures.append("重新开启手柄震动没有写回设置")
	if left_stick_aim_toggle != null:
		left_stick_aim_toggle.button_pressed = false
		if InputSettings.is_left_stick_aim_enabled():
			failures.append("关闭「左摇杆同控朝向」没有写回设置")
		if InputSettings.get_settings_snapshot().get("gamepad_left_stick_aim") != false:
			failures.append("「左摇杆同控朝向」没有落到持久化快照里")
		left_stick_aim_toggle.button_pressed = true
		if not InputSettings.is_left_stick_aim_enabled():
			failures.append("重新开启「左摇杆同控朝向」没有写回设置")
	move_slider.value = 0.33
	if not is_equal_approx(InputSettings.get_move_deadzone(), 0.33):
		failures.append("拖动左摇杆死区滑条没有写回设置")
	if move_value.text != "0.33":
		failures.append("左摇杆死区数值标签没有跟随滑条：%s" % move_value.text)
	aim_slider.value = 0.41
	if not is_equal_approx(InputSettings.get_aim_deadzone(), 0.41):
		failures.append("拖动右摇杆死区滑条没有写回设置")
	smoothing_slider.value = 0.12
	if not is_equal_approx(InputSettings.get_aim_smoothing(), 0.12):
		failures.append("拖动瞄准平滑滑条没有写回设置")
	mode_option.select(2)
	mode_option.item_selected.emit(2)
	if InputSettings.get_device_mode() != InputSettings.DEVICE_MODE_GAMEPAD:
		failures.append("选择「锁定手柄」没有写回设置")
	if status.text.is_empty():
		failures.append("操作设置页没有操作反馈文案")

	# 界面 → 设置 → 界面：外部改动后回头进入页面必须看到新值。
	InputSettings.set_value("gamepad_move_deadzone", 0.19, false)
	pause.set_paused(true)
	pause.call("_show_controls_page")
	if not controls_page.visible or main_page.visible or graphics_page.visible:
		failures.append("ESC 暂停菜单不能进入操作设置页")
	if not is_equal_approx(move_slider.value, 0.19):
		failures.append("重新进入操作设置页没有同步外部改动")
	if not pause.try_consume_pause_input() or controls_page.visible:
		failures.append("操作设置页按 ESC 不能返回暂停主页")
	if not main_page.visible:
		failures.append("从操作设置页返回后没有回到暂停主页")
	controls_button.pressed.emit()
	if not controls_page.visible:
		failures.append("点击「操作设置」按钮没有打开操作设置页")
	pause.call("_show_main_page")
	pause.set_paused(false)
	pause.queue_free()
	await get_tree().process_frame


func _has_joypad_button(action: String, button: int) -> bool:
	for existing in InputMap.action_get_events(action):
		if (
			existing is InputEventJoypadButton
			and (existing as InputEventJoypadButton).button_index == button
		):
			return true
	return false


func _has_key_binding(action: String) -> bool:
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey:
			return true
	return false


## 每张设施菜单实例化后，必须已经有一个「在菜单内的焦点持有者」。
## 这是 headless 能验的最强口径：grab_focus() 不依赖 GUI 输入派发也会生效；
## 而「确认键真的触发按钮」必须带窗口跑（见 probe_menu_focus_activation.gd），
## headless 下合成事件不会走到按钮的 pressed。
func _verify_submenu_focus_anchor(failures: Array[String]) -> void:
	for path in FACILITY_MENU_SCENES:
		var scene := load(path) as PackedScene
		if scene == null:
			failures.append("设施菜单场景不存在：%s" % path)
			continue
		var menu := scene.instantiate()
		if not (menu is CanvasLayer):
			failures.append("设施菜单不是 CanvasLayer，_open_menu 会拒绝加载：%s" % path)
			menu.free()
			continue
		add_child(menu)
		# 等容器重排 + _ready 末尾的 grab_focus 生效。
		await get_tree().process_frame
		await get_tree().process_frame
		var owner := get_viewport().gui_get_focus_owner()
		if owner == null:
			failures.append(
				"设施菜单打开后没有焦点持有者，手柄在此界面失灵：%s" % path)
		elif not menu.is_ancestor_of(owner):
			failures.append(
				"设施菜单的焦点落到菜单之外：%s → %s" % [path, owner.get_path()])
		menu.queue_free()
		await get_tree().process_frame

func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print(
			"GAMEPAD_INPUT_FLOW_OK: input settings persist with clamping, 13 runtime joypad bindings toggle live, radial deadzone remap matches (m-dz)/(1-dz), device auto-detect/lock honours the mode, Dungeon3D M/1/2/3/4 ride input actions, the ESC controls page round-trips every control, virtual aim projects to the matching screen side, facing resolves right-stick > left-stick > keep-last with deadzone hysteresis and smoothed tier hand-off, and every facility menu opens with a focus anchor for gamepad navigation"
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
