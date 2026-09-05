extends Node
## 调试快捷键烟雾验证：只确认 ; / ' / [ / ] / R 五条路径让 Player3D 偏移
## 变量正确变化、边界生效、玩家朝向与运动控制不被污染。相机姿态合成
## 通过单独算子独立验证（不在本测试里实例化完整的 TowerDescent3D 以避免
## 触发场景生成的全部 _process 副作用）。
##
## 注：本测试不通过 _unhandled_input 入口触发原有 - / = 缩放快捷键与
## 小键盘 +/- ，因为这两个分支依赖 Player3D._ready 完成的 avatar / 碰撞体
## 子节点初始化（否则 adjust_debug_scale 会触碰 null 节点）。这两条路径的
## 回归由 Smoke 套件中 verify_player3d_avatar_bounds 覆盖。

func _ready() -> void:
	var failures: Array[String] = []
	_run_key_classification_checks(failures)
	_run_offset_function_checks(failures)
	_run_camera_formula_checks(failures)
	if failures.is_empty():
		print("DEBUG_CAMERA_HOTKEYS_OK: ; zoom in / ' zoom out / [ yaw left / ] yaw right / R reset")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


## 验证 ; / ' / [ / ] / R 的按键分类器返回 true，以及 9 / 0 / KEY_KP_ADD / SUBTRACT
## / 移动键 / 原 ASCII 路径不命中调试相机键。
func _run_key_classification_checks(failures: Array[String]) -> void:
	var stub_scene := load("res://scenes/Player3D.tscn") as PackedScene
	var stub := (stub_scene.instantiate() if stub_scene != null else null) as Player3D
	if stub == null:
		failures.append("Player3D.tscn 加载或实例化失败")
		return
	add_child(stub)
	await get_tree().process_frame

	var must_hit: Array = [
		_make_key(KEY_SEMICOLON),
		_make_key(KEY_APOSTROPHE),
		_make_key(KEY_BRACKETLEFT),
		_make_key(KEY_BRACKETRIGHT),
		_make_key(KEY_R),
	]
	for key_event in must_hit:
		var kind := _classify_debug_camera_key(stub, key_event)
		if kind == "":
			failures.append(
				"调试相机键未命中分类器：physical_keycode=%d" % key_event.physical_keycode
			)

	# 不应命中调试相机路径的键：9 / 0 与性能覆盖层 0 冲突、缩放 / 移动 / 跳跃 / 射击。
	var must_skip: Array = [
		_make_key(KEY_9),  # 保留作其它用途
		_make_key(KEY_0),  # PerformanceOverlay 用 0 切覆盖层
		_make_key(KEY_KP_9),
		_make_key(KEY_KP_0),
		_make_key(KEY_KP_ADD),
		_make_key(KEY_KP_SUBTRACT),
		_make_key(KEY_EQUAL),
		_make_key(KEY_MINUS),
		_make_key(KEY_W),
		_make_key(KEY_A),
		_make_key(KEY_S),
		_make_key(KEY_D),
		_make_key(KEY_SPACE),
		_make_key(KEY_E),
		_make_key(KEY_R, true), # echo=true 应被早退
	]
	for key_event in must_skip:
		var kind := _classify_debug_camera_key(stub, key_event)
		if kind != "":
			failures.append(
				"非调试相机键被误判为 %s：physical_keycode=%d" % [kind, key_event.physical_keycode]
			)

	stub.queue_free()


## 直接调用 Player3D 内部的 adjust / reset / get 函数，验证偏移与边界。
func _run_offset_function_checks(failures: Array[String]) -> void:
	var stub_scene := load("res://scenes/Player3D.tscn") as PackedScene
	var stub := (stub_scene.instantiate() if stub_scene != null else null) as Player3D
	if stub == null:
		failures.append("Player3D.tscn 加载或实例化失败")
		return
	add_child(stub)
	await get_tree().process_frame

	# 起步状态。
	if not is_equal_approx(stub.get_debug_camera_trailing_offset_m(), 0.0):
		failures.append("初始 trailing 偏移非 0")
	if not is_equal_approx(stub.get_debug_camera_yaw_offset_deg(), 0.0):
		failures.append("初始 yaw 偏移非 0")

	# adjust 步进：trailing。
	stub.adjust_debug_camera_trailing(-0.2)
	if not is_equal_approx(stub.get_debug_camera_trailing_offset_m(), -0.2):
		failures.append("adjust_debug_camera_trailing(-0.2) 未生效")
	stub.adjust_debug_camera_trailing(-0.2)
	if not is_equal_approx(stub.get_debug_camera_trailing_offset_m(), -0.4):
		failures.append("adjust_debug_camera_trailing(-0.2) 累加未生效")

	# trailing 上界：连按 ' 直至上限。
	for _index in range(80):
		stub.adjust_debug_camera_trailing(0.2)
	if stub.get_debug_camera_trailing_offset_m() > 8.0 + 1e-4:
		failures.append(
			"trailing 上界失效：%f" % stub.get_debug_camera_trailing_offset_m()
		)

	# trailing 下界：连按 ; 直至下限。
	stub.reset_debug_camera_adjustments()
	for _index in range(80):
		stub.adjust_debug_camera_trailing(-0.2)
	if stub.get_debug_camera_trailing_offset_m() < -8.0 - 1e-4:
		failures.append(
			"trailing 下界失效：%f" % stub.get_debug_camera_trailing_offset_m()
		)

	# yaw 上界 / 下界。
	stub.reset_debug_camera_adjustments()
	for _index in range(80):
		stub.adjust_debug_camera_yaw(5.0)
	if stub.get_debug_camera_yaw_offset_deg() > 75.0 + 1e-4:
		failures.append(
			"yaw 上界失效：%f" % stub.get_debug_camera_yaw_offset_deg()
		)
	stub.reset_debug_camera_adjustments()
	for _index in range(80):
		stub.adjust_debug_camera_yaw(-5.0)
	if stub.get_debug_camera_yaw_offset_deg() < -75.0 - 1e-4:
		failures.append(
			"yaw 下界失效：%f" % stub.get_debug_camera_yaw_offset_deg()
		)

	# reset 后回到 0。
	stub.adjust_debug_camera_trailing(-0.5)
	stub.adjust_debug_camera_yaw(10.0)
	stub.reset_debug_camera_adjustments()
	if not is_equal_approx(stub.get_debug_camera_trailing_offset_m(), 0.0):
		failures.append("reset 后 trailing 未归零")
	if not is_equal_approx(stub.get_debug_camera_yaw_offset_deg(), 0.0):
		failures.append("reset 后 yaw 未归零")

	# 玩家 yaw 完全未被改动。
	if not is_equal_approx(stub.rotation.y, 0.0):
		failures.append("调试相机 adjust 函数被误改玩家 yaw")

	stub.queue_free()


## 验证 _apply_indoor_camera_pose 的局部位置公式：相机位置 = focal_local +
## Basis(UP, yaw).rotated(unit_relative * relative_length)，其中
## unit_relative = default_relative / |default_relative|，relative_length =
## |default_relative| + trailing_offset_m，下界 0.20m 防止相机缩到焦点里。
func _run_camera_formula_checks(failures: Array[String]) -> void:
	var camera_height_m := 8.0
	var camera_look_height_m := 0.45
	var camera_look_ahead_m := 0.75
	var default_trailing := 2.77
	var default_relative := Vector3(
		0.0,
		camera_height_m - camera_look_height_m,
		default_trailing + camera_look_ahead_m
	)
	var default_magnitude := default_relative.length()
	var test_cases: Array = [
		{"trailing_offset": 0.0, "yaw_deg": 0.0, "lift": 0.0, "drop": 0.0},
		{"trailing_offset": -0.4, "yaw_deg": -10.0, "lift": 0.0, "drop": 0.0},
		{"trailing_offset": 1.0, "yaw_deg": 30.0, "lift": 0.3, "drop": 0.1},
	]
	for case_index in range(test_cases.size()):
		var case: Dictionary = test_cases[case_index]
		var relative_local := Vector3(
			0.0,
			camera_height_m + float(case["lift"]) - float(case["drop"]) - camera_look_height_m,
			default_trailing + camera_look_ahead_m
		)
		var local_magnitude := relative_local.length()
		if local_magnitude <= 0.0001:
			local_magnitude = 1.0
		var local_unit := relative_local / local_magnitude
		var trailing_offset_m := float(case["trailing_offset"])
		var local_length := maxf(local_magnitude + trailing_offset_m, 0.20)
		var pre_rotation := local_unit * local_length
		var rotated := pre_rotation
		var yaw_rad := deg_to_rad(float(case["yaw_deg"]))
		if not is_zero_approx(yaw_rad):
			rotated = Basis(Vector3.UP, yaw_rad) * rotated
		var focal_local := Vector3(0.0, camera_look_height_m, -camera_look_ahead_m)
		var actual_local_pos: Vector3 = focal_local + rotated

		# 预期：pre_rotation 长度 = local_length；旋转后长度不变。
		if absf(pre_rotation.length() - local_length) > 0.001:
			failures.append(
				"相机合成公式 case#%d pre_rotation 长度不一致：got=%f expected=%f" % [
					case_index, pre_rotation.length(), local_length
				]
			)
		if absf(rotated.length() - local_length) > 0.001:
			failures.append(
				"相机合成公式 case#%d 旋转后长度不一致：got=%f expected=%f" % [
					case_index, rotated.length(), local_length
				]
			)
		# 旋转后方向必须等于 Basis(UP, yaw) * pre_rotation 单位向量。
		if yaw_rad != 0.0:
			var expected_unit := Basis(Vector3.UP, yaw_rad) * local_unit
			var actual_unit := (rotated / rotated.length()) if rotated.length() > 1e-4 else local_unit
			if actual_unit.distance_to(expected_unit) > 0.001:
				failures.append(
					"相机合成公式 case#%d 旋转后单位方向不一致：got=%s expected=%s" % [
						case_index, actual_unit, expected_unit
					]
				)
		# 焦点位置一致性。
		if not actual_local_pos.is_equal_approx(focal_local + rotated):
			failures.append(
				"相机局部位置 case#%d 与焦点+向量不一致：%s" % [case_index, actual_local_pos]
			)
		# 默认（offset=0、yaw=0、lift=0、drop=0）应与原 TowerDescent3D 写的位置一致。
		if case_index == 0:
			var expected_zero := Vector3(0.0, 0.45, -0.75) + Vector3(
				0.0, camera_height_m - camera_look_height_m, default_trailing + camera_look_ahead_m
			)
			if actual_local_pos.distance_to(expected_zero) > 0.001:
				failures.append(
					"默认相机位置不一致：got=%s expected=%s" % [actual_local_pos, expected_zero]
				)


func _classify_debug_camera_key(stub: Node, event: InputEventKey) -> String:
	# 通过 _unhandled_input 不能直接调用，改为手敲同样的判定顺序：
	# 1) echo / pressed 早退
	if event == null or not event.pressed or event.echo:
		return ""
	# 2) 缩放键早退（保持与 _unhandled_input 一致）。
	if stub._is_debug_scale_up_key(event) or stub._is_debug_scale_down_key(event):
		return ""
	# 3) 调试相机键。
	if stub._is_debug_camera_zoom_in_key(event):
		return "zoom_in"
	if stub._is_debug_camera_zoom_out_key(event):
		return "zoom_out"
	if stub._is_debug_camera_yaw_left_key(event):
		return "yaw_left"
	if stub._is_debug_camera_yaw_right_key(event):
		return "yaw_right"
	if stub._is_debug_camera_reset_key(event):
		return "reset"
	return ""


func _make_key(physical_keycode: int, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.echo = echo
	event.physical_keycode = physical_keycode
	event.keycode = physical_keycode
	event.unicode = 0
	return event