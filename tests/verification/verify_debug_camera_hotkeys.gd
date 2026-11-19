extends Node
## 调试快捷键与真实 TowerDescent3D Owner 矩阵验证。
## Owner 只使用真实 PackedScene 的节点配置，替换根/玩家脚本以禁止生产 _ready、
## process 与 physics；不生成整关、不触碰生产存档。相机姿态仍由生产
## TowerDescent3D._apply_indoor_camera_pose 合成，输入则经过真实 Player3D._unhandled_input。

var camera_owner_checks := 0


class CameraTestOwner extends TowerDescent3D:
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)


class CameraTestPlayer extends Player3D:
	func _ready() -> void:
		set_physics_process(false)
		camera_feedback.configure(self)
		camera_feedback.set_physics_process(false)


func _ready() -> void:
	var failures: Array[String] = []
	if not _check_isolated_user_data_before_players(failures):
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
		return
	await _run_key_classification_checks(failures)
	await _run_offset_function_checks(failures)
	_run_camera_formula_checks(failures)
	await _run_camera_owner_checks(failures)
	if failures.is_empty():
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		print("CAMERA_OWNER_SCOPE_OK checks=%d" % camera_owner_checks)
		print("DEBUG_CAMERA_HOTKEYS_OK: ; zoom in / ' zoom out / [ yaw left / ] yaw right / F12 reset")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _check_isolated_user_data_before_players(failures: Array[String]) -> bool:
	var appdata := OS.get_environment("APPDATA").replace("\\", "/").trim_suffix("/")
	var user_root := OS.get_user_data_dir().replace("\\", "/")
	var isolated := not appdata.is_empty() and user_root.begins_with(appdata + "/")
	if not isolated:
		failures.append(
			"拒绝运行：SHELLSTORM_CAMERA_VERIFY_ISOLATED 必须为 1，且 user data 必须位于 APPDATA；got=%s" % user_root
		)
		return false
	var custom_name := str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	var suite_name := OS.get_environment("SHELLSTORM_VERIFICATION_USER_DIR_NAME")
	var named_isolation := bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)) \
		and not custom_name.is_empty() and user_root.ends_with("/" + custom_name)
	var authorized := OS.get_environment("SHELLSTORM_CAMERA_VERIFY_ISOLATED") == "1" \
		or (not suite_name.is_empty() and suite_name == custom_name)
	if not named_isolation or not authorized:
		failures.append("拒绝运行：必须在启动前配置独立custom_user_dir，且隔离标识与目录相符")
		return false
	print("ISOLATION_USER_DIR ", user_root)
	return true


## 验证 ; / ' / [ / ] / F12 的按键分类器返回 true，以及 9 / 0 / KEY_KP_ADD / SUBTRACT
## / 移动键 / 原 ASCII 路径 / 已改键的旧 R 不命中调试相机键。
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
		_make_key(KEY_F12),
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
		_make_key(KEY_R), # 2026-10-14 改键：R 已不再触发镜头复位
		_make_key(KEY_F12, true), # echo=true 应被早退
	]
	for key_event in must_skip:
		var kind := _classify_debug_camera_key(stub, key_event)
		if kind != "":
			failures.append(
				"非调试相机键被误判为 %s：physical_keycode=%d" % [kind, key_event.physical_keycode]
			)

	stub.queue_free()
	await get_tree().process_frame


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
	await get_tree().process_frame


func _run_camera_owner_checks(failures: Array[String]) -> void:
	var cases: Array[Dictionary] = [
		{"path": "res://scenes/TowerDescent3D.tscn", "expected_offset": 0.0, "level_id": "expedition_01", "expedition": false},
		{"path": "res://scenes/ExpeditionLevel01_3D.tscn", "expected_offset": 2.6, "level_id": "expedition_01", "expedition": true},
		{"path": "res://scenes/ExpeditionLevel02_3D.tscn", "expected_offset": 0.0, "level_id": "expedition_02", "expedition": true},
		{"path": "res://scenes/ExpeditionLevel03_3D.tscn", "expected_offset": 0.0, "level_id": "expedition_03", "expedition": true},
		{"path": "res://scenes/ExpeditionLevel99_3D.tscn", "expected_offset": 0.0, "level_id": "99", "expedition": true},
	]
	for case in cases:
		var owner: TowerDescent3D = await _instantiate_camera_owner(str(case["path"]), failures)
		if owner == null:
			continue
		var player := owner.get_node_or_null("Player3D") as Player3D
		_owner_check(player != null, failures, str(case["path"]) + " 缺少真实 Player3D")
		if player == null:
			owner.queue_free()
			await get_tree().process_frame
			continue
		owner.player = player
		owner.call("_update_camera_profile", 0.0)
		owner.set("_camera_trailing_current_m", float(owner.get("_camera_profile_trailing_current_m")))
		player.camera_feedback.configure(player)
		player.camera_feedback.world_pose_managed = false
		player.camera_feedback.look_offset = Vector3.ZERO
		_owner_check(is_zero_approx(player.get_debug_camera_trailing_offset_m()), failures, "固定机位不可预填Player临时偏移")
		player.reset_debug_camera_adjustments()
		var level_id := owner.get_expedition_level_id()
		_owner_check(level_id == str(case["level_id"]) and owner.is_expedition() == bool(case["expedition"]),
			failures, "真实场景身份与隔离矩阵不符")
		print("CAMERA_OWNER_ID path=%s expedition=%s run_id=%s plan_id=%s level_id=%s" % [
			str(case["path"]), owner.is_expedition(), owner.expedition_run_id,
			owner.expedition_plan_id, level_id
		])
		_owner_check(
			is_equal_approx(float(owner.call("_camera_default_distance_offset_m")), float(case["expected_offset"])),
			failures,
			str(case["path"]) + " _camera_default_distance_offset_m 身份矩阵错误"
		)
		owner.call("_apply_indoor_camera_pose")
		var base_position := player.camera.global_position
		var expected_offset := float(case["expected_offset"])
		var expected_position := _expected_default_camera_position(expected_offset)
		_owner_check(
			base_position.distance_to(expected_position) < 0.0001,
			failures,
			str(case["path"]) + " 真实 Owner 默认相机位置错误：got=%s expected=%s" % [base_position, expected_position]
		)
		_owner_check(
			player.camera_feedback.world_pose_managed,
			failures,
			str(case["path"]) + " 真实 Player camera_feedback 未进入 world pose 管理"
		)
		var focal := player.global_position + Vector3(0, 0.45, -0.75)
		_owner_check((-player.camera.global_basis.z).dot((focal - base_position).normalized()) > 0.99999,
			failures, "相机必须仍看向固定焦点")
		if str(case["path"]).ends_with("ExpeditionLevel01_3D.tscn"):
			await _verify_expedition01_input(owner, player, failures)
			await _verify_expedition01_avoidance(owner, player, failures)
			for room_id in ["02", "03", "06", "09", "10"]:
				await _verify_expedition01_ceiling(owner, player, room_id, failures)
		else:
			player._unhandled_input(_make_key(KEY_APOSTROPHE))
			player._unhandled_input(_make_key(KEY_F12))
			owner.call("_apply_indoor_camera_pose")
			_owner_check(player.camera.global_position.distance_to(expected_position) < 0.0001,
				failures, "其他关卡F12不得获得01固定偏移")
		if level_id == "expedition_02":
			_owner_check(
				bool(owner.call("_uses_expedition_camera_profiles")),
				failures,
				"远征02 真实身份未启用 profile 相机分支"
			)
			# 远征02 的真实 profile 分支也必须在已入树的 world 上完成约束查询。
			player.camera_feedback.look_offset = Vector3(0.1, 0.0, 0.0)
			owner.call("_apply_indoor_camera_pose")
			_owner_check(player.camera.global_position.is_finite(), failures, "远征02 world constrain query 后相机位置非法")
			player.camera_feedback.look_offset = Vector3.ZERO
			# 显式房间profile也不能被01的偏移污染；只推进生产profile读取，不造整关。
			var room := DungeonRoom3D.new()
			room.camera_profile = {"id": "camera_test_low", "height_m": 1.55, "trailing_m": 3.4}
			# 只读房间profile不需要入树，避免触发与相机无关的房间构建。
			owner.set("_room_by_id", {"camera_test_low": room})
			owner.set("_current_room_id", "camera_test_low")
			owner.call("_update_camera_profile", 10.0)
			owner.set("_camera_trailing_current_m", 3.4)
			owner.call("_apply_indoor_camera_pose")
			_owner_check(player.camera.global_position.distance_to(Vector3(0, 1.55, 3.4)) < 0.0001,
				failures, "远征02房间profile被01机位覆盖")
			owner.set("_room_by_id", {})
			owner.set("_current_room_id", "")
			room.free()
		if str(case["path"]).ends_with("ExpeditionLevel03_3D.tscn"):
			# 真实 flow Owner 尚未生成房间；显式打开 flow 分支，确认无房间时夹取早退，
			# 不把缺失房间误判为成功，也不让测试构造整关。
			owner.set("_flow_rules_active", true)
			owner.call("_apply_indoor_camera_pose")
			_owner_check(
				player.camera.global_position.distance_to(expected_position) < 0.0001,
				failures,
				"远征03 无房间时 flow 相机夹取未安全早退"
			)
		owner.queue_free()
		await get_tree().process_frame
		_owner_check(not is_instance_valid(owner), failures, str(case["path"]) + " Owner 清理失败")


func _instantiate_camera_owner(path: String, failures: Array[String]) -> TowerDescent3D:
	var packed := load(path) as PackedScene
	if packed == null:
		failures.append("真实 Owner 场景加载失败：" + path)
		return null
	var owner: TowerDescent3D = packed.instantiate() as TowerDescent3D
	if owner == null:
		failures.append("真实 Owner 场景实例化失败：" + path)
		return null
	var player := owner.get_node_or_null("Player3D") as Player3D
	if player == null:
		failures.append("真实 Owner 场景没有 Player3D：" + path)
		owner.free()
		return null
	# 必须在入树前替换脚本；set_script 会重置导出属性，所以显式保留真实场景身份。
	# 不执行 TowerDescent3D/Dungeon3D 或 Player3D 的生产 _ready。
	var expedition_mode := owner.expedition_mode
	var run_id := owner.expedition_run_id
	var plan_id := owner.expedition_plan_id
	owner.set_script(CameraTestOwner)
	owner.expedition_mode = expedition_mode
	owner.expedition_run_id = run_id
	owner.expedition_plan_id = plan_id
	player.set_script(CameraTestPlayer)
	# 仅保留父类@onready要求的公共壳体；不让塔楼美术与其他业务节点抢跑。
	var blocks := owner.get_node_or_null("Blocks")
	if blocks != null:
		owner.remove_child(blocks)
		blocks.free()
	add_child(owner)
	await get_tree().process_frame
	return owner


func _verify_expedition01_input(owner: TowerDescent3D, player: Player3D, failures: Array[String]) -> void:
	var fixed_position := _expected_default_camera_position(2.6)
	player.reset_debug_camera_adjustments()
	owner.call("_apply_indoor_camera_pose")
	_owner_check(
		player.camera.global_position.distance_to(fixed_position) < 0.0001,
		failures,
		"远征01 F12 前新默认固定+2.6m位置错误"
	)
	_owner_check(
		fixed_position.distance_to(Vector3(0.0, 12.514413, 6.214302)) < 0.0001,
		failures,
		"远征01 +2.6m 预期位置不是 (0,12.514413,6.214302)"
	)
	for _index in range(5):
		player._unhandled_input(_make_key(KEY_APOSTROPHE))
	owner.call("_apply_indoor_camera_pose")
	var plus_one_position := _expected_default_camera_position(3.6)
	_owner_check(
		player.camera.global_position.distance_to(plus_one_position) < 0.0001,
		failures,
		"远征01 通过 Player3D._unhandled_input 连按5次 ' 未额外+1m"
	)
	player._unhandled_input(_make_key(KEY_F12))
	owner.call("_apply_indoor_camera_pose")
	_owner_check(is_zero_approx(player.get_debug_camera_trailing_offset_m()), failures, "F12 未清除 debug trailing")
	_owner_check(
		player.camera.global_position.distance_to(fixed_position) < 0.0001,
		failures,
		"远征01 F12 错误清除了生产固定+2.6m"
	)
	player._unhandled_input(_make_key(KEY_SEMICOLON))
	owner.call("_apply_indoor_camera_pose")
	var plus_point_eight_position := _expected_default_camera_position(2.4)
	_owner_check(
		player.camera.global_position.distance_to(plus_point_eight_position) < 0.0001,
		failures,
		"远征01 ; 后有效固定距离未为+2.4m"
	)
	var settled_position := player.camera.global_position
	for _frame in range(60):
		owner.call("_apply_indoor_camera_pose")
	_owner_check(
		player.camera.global_position.distance_to(settled_position) < 0.0001,
		failures,
		"连续帧重复应用导致相机距离累加"
	)


func _verify_expedition01_avoidance(owner: TowerDescent3D, player: Player3D, failures: Array[String]) -> void:
	player.reset_debug_camera_adjustments()
	_owner_check(absf(float(owner.call("_camera_lower_wall_retract_trigger_m")) - 6.214302) < 0.0001,
		failures, "01收镜阈值必须覆盖新机位水平后移")
	# 墙内表面5.80m，位于上一版01阈值5.414与新阈值6.214之间；沿用旧阈值应漏报。
	var wall := _camera_test_box(Vector3(20, 20, 0.3), Vector3(0, 10, 5.95), "camera_lower_wall")
	owner.add_child(wall)
	await get_tree().physics_frame
	for frame in range(120):
		owner.call("_update_camera_lower_wall_lift", 1.0 / 60.0, true)
		owner.call("_apply_indoor_camera_pose")
	_owner_check(bool(owner.get("_camera_lower_wall_retract_active")), failures, "新机位墙通道必须触发收镜")
	_owner_check(player.camera.position.z < 5.80, failures, "收镜后不得再次固定拉远穿回墙后")
	wall.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	for frame in range(240):
		owner.call("_update_camera_lower_wall_lift", 1.0 / 60.0, true)
		owner.call("_apply_indoor_camera_pose")
	_owner_check(not bool(owner.get("_camera_lower_wall_retract_active")), failures, "移除墙后收镜必须自然解除")
	_owner_check(player.camera.position.distance_to(_expected_default_camera_position(2.6)) < 0.0001,
		failures, "墙体避障必须自然恢复01新默认")
	player.camera_feedback.reset()
	# 窄顶盖只覆盖新Z=6.214、不覆盖上一版5.414；下表面11.80高于上一版相机Y。
	var slab := _camera_test_box(Vector3(4, 0.2, 0.3), Vector3(0, 11.90, 6.214302), "camera_ceiling_occluder")
	owner.add_child(slab)
	await get_tree().physics_frame
	owner.call("_update_camera_stair_slab_drop", 1.0 / 60.0, true)
	owner.call("_apply_indoor_camera_pose")
	_owner_check(bool(owner.get("_camera_stair_slab_detected")), failures, "新高度与水平位置必须命中真实顶盖")
	_owner_check(player.camera.position.y <= 11.80 - 0.28 + 0.0001,
		failures, "避障后不得再追加固定拉远穿回楼板")
	_owner_check(absf(player.camera.position.z - 6.214302) < 0.0001,
		failures, "楼板下压保持新机位水平后移")
	slab.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	for frame in range(240):
		owner.call("_update_camera_stair_slab_drop", 1.0 / 60.0, true)
		owner.call("_apply_indoor_camera_pose")
	_owner_check(player.camera.position.distance_to(_expected_default_camera_position(2.6)) < 0.0001,
		failures, "解除避障后必须恢复01新默认")


func _verify_expedition01_ceiling(owner: TowerDescent3D, player: Player3D, room_id: String, failures: Array[String]) -> void:
	var layout_path := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/f00_room_%s_static_layout.tscn" % room_id
	var room_scene := load(layout_path) as PackedScene
	var layout := room_scene.instantiate() as Node3D
	owner.add_child(layout)
	owner.call("_apply_indoor_camera_pose")
	await get_tree().physics_frame
	await get_tree().physics_frame
	owner.call("_update_camera_occlusion_silhouette")
	_owner_check(not bool(owner.get("_player_occluded")), failures, "%s房默认机位在顶棚下，角色不应显示透视轮廓" % room_id)
	player.camera.global_position.y = player.global_position.y + 23.0
	owner.call("_update_camera_occlusion_silhouette")
	_owner_check(bool(owner.get("_player_occluded")), failures, "%s房机位移到顶棚上方后仍须检测真实遮挡" % room_id)
	layout.queue_free()
	await get_tree().process_frame
	owner.call("_apply_indoor_camera_pose")


func _camera_test_box(size: Vector3, location: Vector3, tag: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 16
	body.collision_mask = 0
	body.set_meta(tag, true)
	body.position = location
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	return body


func _expected_default_camera_position(distance_offset_m: float) -> Vector3:
	var focal_local := Vector3(0.0, 0.45, -0.75)
	var default_relative := Vector3(0.0, 10.262659 - 0.45, 4.914455 + 0.75)
	return focal_local + default_relative.normalized() * (default_relative.length() + distance_offset_m)


func _owner_check(condition: bool, failures: Array[String], reason: String) -> void:
	camera_owner_checks += 1
	if not condition:
		failures.append(reason)


## 验证 _apply_indoor_camera_pose 的局部位置公式：相机位置 = focal_local +
## Basis(UP, yaw).rotated(unit_relative * relative_length)，其中
## unit_relative = default_relative / |default_relative|，relative_length =
## |default_relative| + trailing_offset_m，下界 0.20m 防止相机缩到焦点里。
func _run_camera_formula_checks(failures: Array[String]) -> void:
	var camera_height_m := 10.262659
	var camera_look_height_m := 0.45
	var camera_look_ahead_m := 0.75
	var default_trailing := 4.914455
	# 当前默认值必须严格等价于默认镜头的“历史固化链”，防止后续只凭近似画面手调
	# Y/Z 而改掉俯视角。链条（`;`/`'` 每次沿“相机→焦点”视线轴 0.20m；P 面板
	# 「镜头雾气 → 俯仰」每次绕焦点 5°）：
	#   v0.1 初始 (0, 8.0, 2.77)
	#     → `'` 拉远 15 次 ⇒ 2026-09-13 (0, 10.719009, 4.037671)
	#     → `;` 拉近 4 次  ⇒ 2026-10-09 (0, 9.993940, 3.699625)
	#     → `'` 拉远 4 次  ⇒ 回到 09-13 机位（半径回到 11.330240）
	#     → 「压低」1 次   ⇒ 2026-10-15 (0, 10.262659, 4.914455)，本组首次改变俯视角
	var look_pivot := Vector3(0.0, camera_look_height_m, -camera_look_ahead_m)
	var current_position := Vector3(0.0, camera_height_m, default_trailing)
	var current_relative := current_position - look_pivot
	# ① 半径溯源：前四步里只有 `;`/`'` 改变半径（绕焦点旋转不改半径），
	#    净效果 = v0.1 初始沿轴拉远 15 次。
	var origin_relative := Vector3(0.0, 8.0 - camera_look_height_m, 2.77 + camera_look_ahead_m)
	var expected_radius := origin_relative.length() + 15.0 * 0.20
	if absf(current_relative.length() - expected_radius) > 0.00001:
		failures.append(
			"默认镜头半径不等于 v0.1 初始沿轴净拉远15次：got=%.6f expected=%.6f"
			% [current_relative.length(), expected_radius]
		)
	# ② 往返恒等：10-09 机位按 `'` 拉远 4 次必须精确还原 09-13 机位。
	var ten_nine_relative := Vector3(
		0.0, 9.993940 - camera_look_height_m, 3.699625 + camera_look_ahead_m
	)
	var back_to_thirteen := (
		look_pivot + ten_nine_relative.normalized() * (ten_nine_relative.length() + 4.0 * 0.20)
	)
	if back_to_thirteen.distance_to(Vector3(0.0, 10.719009, 4.037671)) > 0.00001:
		failures.append("10-09 机位拉远4次未还原 09-13 机位：%s" % back_to_thirteen)
	# ③ 完整操作复现：09-13 机位在 P 面板按一次「压低」应等于当前默认值。
	var orbited := _orbit_point_about_pivot(back_to_thirteen, look_pivot, -5.0)
	if orbited.distance_to(current_position) > 0.00001:
		failures.append(
			"09-13 机位压低5°不等于当前默认值：got=%s expected=%s"
			% [orbited, current_position]
		)
	# ④ 俯角锚点：2026-10-15 首次由 65.003882° 变为 60.003882°。
	var polar_deg := rad_to_deg(atan2(
		current_relative.y,
		Vector2(current_relative.x, current_relative.z).length()
	))
	if absf(polar_deg - 60.003882) > 0.0001:
		failures.append("默认俯角不等于 60.003882°：%.6f" % polar_deg)
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


## 与 TowerDescent3D._orbit_point_about_pivot 逐行等价的本地副本：以 pivot 为圆心、
## 保持半径不变，把 point 绕水平轴转过 pitch_delta_deg（正=抬高、负=压低）。
## 这里刻意复制而非实例化 TowerDescent3D 去调用 —— 本测试全程不建场景（见文件头
## 「不实例化完整的 TowerDescent3D」），故接受这份影子实现；真源算子的任何改动
## 都必须同步到本函数。
func _orbit_point_about_pivot(point: Vector3, pivot: Vector3, pitch_delta_deg: float) -> Vector3:
	var offset := point - pivot
	var horizontal := Vector2(offset.x, offset.z)
	var horizontal_distance := horizontal.length()
	var radius := sqrt(offset.y * offset.y + horizontal_distance * horizontal_distance)
	if radius <= 0.0001 or horizontal_distance <= 0.0001:
		return point
	var polar := clampf(
		atan2(offset.y, horizontal_distance) + deg_to_rad(pitch_delta_deg),
		deg_to_rad(3.0),
		deg_to_rad(88.0)
	)
	var new_horizontal_distance := radius * cos(polar)
	var new_height := radius * sin(polar)
	var planar := horizontal.normalized()
	return pivot + Vector3(
		planar.x * new_horizontal_distance,
		new_height,
		planar.y * new_horizontal_distance
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
