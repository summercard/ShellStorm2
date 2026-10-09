extends Node3D
## 入口反馈与关闭时序的可测不变量探针。
##
## 与 verify_expedition_hologram_city 的分工：那份验收靠合成输入（Input.parse_input_event
## + await process_frame）驱动，在本机会因事件派发时序而整段连锁失败（改动前后同样如此），
## 无法用来判定本次改动。本探针改用「直接把事件喂给 _input」的确定性路径，逐条钉住
## 焦点与选中分离、悬停倍率、光标移开即复原、点击脉冲、边框流光相位、关闭当帧起播。
const MENU = preload("res://scenes/RogueMapSelectMenu.tscn")
const CITY_SCRIPT = preload("res://src/ui/HologramCity3D.gd")
const PLATFORM = preload("res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities/hologram_terminal_platform/hologram_terminal_platform_root_top3d.tscn")
var failures: Array[String] = []

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.001, 0.003, 0.012)
	environment.environment = env
	add_child(environment)
	var platform := PLATFORM.instantiate() as BaseFacility3D
	add_child(platform)
	platform.position = Vector3(12, -1176, 9)
	var anchor: Vector3 = platform.call("get_hologram_anchor")
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = anchor + Vector3(0, 8, 6)
	camera.look_at(anchor)
	camera.make_current()
	await get_tree().process_frame
	var menu := MENU.instantiate() as RogueMapSelectMenu
	menu.set_facility(platform)
	add_child(menu)
	await get_tree().create_timer(5.2).timeout
	_expect(menu._state == "active", "开场未在 5.2s 内完成")

	var city = menu._city
	# 1) 真实处理器路径：光标指到入口 → 焦点为它；移开到空白 → 焦点清空，选中项保留。
	var away_pos := Vector2(3, 3)
	_expect(menu._pick(away_pos) == -1, "空白取样点其实命中了对象，断言前提不成立")
	var onto_entry := InputEventMouseMotion.new()
	onto_entry.position = menu._camera.unproject_position(city.markers[0].global_position)
	menu._input(onto_entry)
	_expect(menu._focus == 0, "光标移到入口上未聚焦")
	_expect(menu._selection == 0, "光标移到入口上未同步选中")
	var onto_void := InputEventMouseMotion.new()
	onto_void.position = away_pos
	menu._input(onto_void)
	_expect(menu._focus == -1, "光标移开后焦点未清空")
	_expect(menu._selection == 0, "光标移开后选中项不应被清掉（Enter 仍要能确认）")

	# 2) 悬停倍率：焦点落定后收敛到 HOVER_SCALE，另一个保持静止。
	menu._focus = 0
	await get_tree().create_timer(0.7).timeout
	var hovered: float = city.markers[0].global_basis.get_scale().x
	var resting: float = city.markers[1].global_basis.get_scale().x
	_expect(resting > 0.0, "静止标记没有可见尺寸")
	_expect_near(hovered / resting, CITY_SCRIPT.HOVER_SCALE, 0.01, "悬停倍率不等于 HOVER_SCALE")

	# 3) 光标移开即复原：这是本次要求的核心，焦点清空后入口必须自己缩回去。
	menu._focus = -1
	await get_tree().create_timer(0.7).timeout
	_expect(city._hover[0] < 0.02, "光标移开后悬停强度未归零")
	_expect_near(city.markers[0].global_basis.get_scale().x / resting, 1.0, 0.01, "光标移开后未复原到静止尺寸")

	# 4) 点击脉冲：焦点 + 脉冲的峰值倍率 = HOVER_SCALE + PUNCH_SCALE，且会自行衰减回零。
	menu._focus = 0
	await get_tree().create_timer(0.7).timeout
	city.punch_marker(0)
	city.face_markers(menu._camera)
	_expect(is_equal_approx(city._punch[0], 1.0), "punch_marker 未把脉冲置满")
	_expect_near(city.markers[0].global_basis.get_scale().x / resting, CITY_SCRIPT.HOVER_SCALE + CITY_SCRIPT.PUNCH_SCALE, 0.01, "脉冲峰值倍率不等于 HOVER_SCALE + PUNCH_SCALE")
	await get_tree().create_timer(0.4).timeout
	_expect(is_equal_approx(city._punch[0], 0.0), "脉冲未在 0.4s 内衰减归零")

	# 5) 边框流光：四条边按周长首尾相接，起点为 0、占比合计为一整圈、相位顺时针递增。
	var offsets: Array[float] = []
	var span_total := 0.0
	for material in city.border_materials[0]:
		offsets.append(float(material.get_shader_parameter("flow_offset")))
		span_total += float(material.get_shader_parameter("arc_span"))
		_expect(float(material.get_shader_parameter("line_length")) > 0.0, "边框缺少线段长度")
	_expect(city.border_materials[0].size() == 4, "边框不是四条边")
	_expect(is_equal_approx(offsets[0], 0.0), "流光起点不在周长 0")
	_expect(is_equal_approx(span_total, 1.0), "四条边未覆盖整圈周长")
	var ascending := true
	for i in range(1, offsets.size()):
		if offsets[i] <= offsets[i - 1]:
			ascending = false
	_expect(ascending, "流光相位未沿边框递增")

	# 6) 关闭当帧起播：旧实现在按下后相机静止 1.62s、楼群静止 0.82s。
	var deploy_before: float = city.deployment
	var camera_before: Vector3 = menu._camera.global_transform.origin
	menu.request_close()
	_expect(menu._state == "closing", "request_close 未立即进入 closing")
	await get_tree().create_timer(0.06).timeout
	_expect(city.deployment < deploy_before, "关闭后楼群没有立刻开始收起")
	_expect(menu._camera.global_transform.origin.distance_to(camera_before) > 0.0, "关闭后镜头没有立刻开始位移")

	if failures.is_empty():
		print("HOLOGRAM_ENTRY_FEEDBACK_OK hover=%.2f punch=%.2f borders=4 focus_decoupled=true close_immediate=true" % [CITY_SCRIPT.HOVER_SCALE, CITY_SCRIPT.PUNCH_SCALE])
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	# 收敛式插值不会精确落在目标值上，比值断言必须给相对容差，否则测的是浮点而不是行为。
	if absf(actual - expected) > tolerance * maxf(1.0, absf(expected)):
		failures.append("%s（实测 %.5f，期望 %.5f）" % [message, actual, expected])
