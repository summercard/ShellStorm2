extends Node
## 远征02专属镜头最小端到端验收：真实关卡、真实房间切换、真实 Camera3D。

const LEVEL_SCENE := "res://scenes/ExpeditionLevel02_3D.tscn"
const OUT_DIR := "user://expedition02_camera_profiles"
const WORK_DIR := "I:/工作项目/shellstrom2/ShellStorm2-work/camera"
const EPSILON := 0.001
const CORRIDOR_CAMERA_HEIGHT_M := 1.55
const TEE_CAMERA_HEIGHT_M := 1.55

var failures: Array[String] = []
var samples: Array[Dictionary] = []
var _saved_probe_camera_attributes: CameraAttributes = null


func _ready() -> void:
	var packed := load(LEVEL_SCENE) as PackedScene
	if packed == null:
		_fail("远征02场景加载失败")
		_finish()
		return
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await _settle(12)

	var rooms: Dictionary = tower.get("_room_by_id")
	var foyer := rooms.get("room_01") as DungeonRoom3D
	var corridor := rooms.get("room_02") as DungeonRoom3D
	var tee := rooms.get("room_13") as DungeonRoom3D
	_check(foyer != null and corridor != null and tee != null, "真实房间字典缺少 room_01/room_02/room_13")
	if foyer == null or corridor == null or tee == null:
		_finish()
		return

	_check(str(foyer.camera_profile.get("id", "")) == "foyer_high", "room_01 未接入 foyer_high")
	_check(str(corridor.camera_profile.get("id", "")) == "corridor_north", "room_02 未接入 corridor_north")
	_check(str(tee.camera_profile.get("id", "")) == "tee_west", "room_13 未接入 tee_west")
	_check(not (rooms.get("room_01") as DungeonRoom3D).camera_profile.is_empty(), "room_01 camera_profile 为空")

	_prepare_render_room(foyer)
	_prepare_render_room(corridor)
	_prepare_render_room(tee)
	_prepare_probe_camera_for_render(tower.player.camera)
	await _sample_room(tower, foyer, "room_01_start")
	var yaw_before := tower.player.global_rotation.y
	# 从 room_01 南侧内部沿真实端口方向向北移动，依靠 RoomTrigger.body_entered 提交 room_02。
	for step in range(21):
		var progress := float(step) / 20.0
		tower.player.global_position = Vector3(
			2.5,
			0.05,
			lerpf(31.0, 20.5, progress)
		)
		await _settle(1)
	var triggered_profile := str(tower.get_tower_snapshot().get("camera_profile_id", ""))
	_check(triggered_profile == "corridor_north", "room_01→room_02 真实端口步行未触发 corridor_north")
	var immediate := _sample(tower, "room_02_transition_start")
	_check(str(tower.get_tower_snapshot().get("camera_profile_id", "")) == "corridor_north", "room_02 进入后未切换 profile")
	_check(float(immediate.get("camera_height", 0.0)) > CORRIDOR_CAMERA_HEIGHT_M + EPSILON, "切换首帧硬切到目标高度")
	for frame_index in range(1, 76):
		await _settle(1)
		if frame_index % 5 == 0 or frame_index == 75:
			_sample(tower, "room_02_transition_%03d" % frame_index)
	var corridor_sample := _sample(tower, "room_02_settled")
	_check(absf(float(corridor_sample.get("camera_height", 0.0)) - CORRIDOR_CAMERA_HEIGHT_M) < 0.08, "room_02 最终高度未收敛到头部机位高度")
	if DisplayServer.get_name() != "headless":
		# 仅为构图证据设置测试角色姿态，不改正式角色朝向逻辑。
		# 暂停真实玩家物理输入更新，避免验收窗口中的鼠标射线覆盖候选 aim_yaw。
		tower.player.set_physics_process(false)
		# 运行时实测 270° 才是 room_02 的正后方背面姿态；
		# 只控制验收角色，不改正式玩家朝向逻辑，镜头仍保持世界 yaw=0°。
		tower.player.aim_yaw = deg_to_rad(270.0)
		await _settle(12)
		await _save_render(tower, "expedition02_camera_room02.png")
		tower.player.set_physics_process(true)
	_check(absf(float(corridor_sample.get("camera_yaw_deg", 999.0))) < 1.0, "room_02 朝向未保持固定世界方向")

	var direction_before := _camera_forward(tower.player.camera)
	tower.player.rotation.y += deg_to_rad(73.0)
	await _settle(20)
	var direction_after := _camera_forward(tower.player.camera)
	_check(direction_before.dot(direction_after) > 0.995, "镜头方向随玩家 yaw 转动")
	_check(absf(yaw_before - tower.player.rotation.y) > 0.5, "验收未实际改变玩家 yaw")
	# yaw 变化只用于数值反向验证；真实构图截图恢复正常玩家朝向。
	tower.player.rotation.y = yaw_before
	await _settle(3)

	# 继续沿 room_02→room_13 的真实北侧端口步行，验证第三个 profile 也由 RoomTrigger 提交。
	for step in range(26):
		var progress := float(step) / 25.0
		tower.player.global_position = Vector3(
			0.0,
			0.05,
			lerpf(20.5, -49.5, progress)
		)
		await _settle(1)
	_check(str(tower.get_tower_snapshot().get("camera_profile_id", "")) == "tee_west", "room_02→room_13 真实端口步行未触发 tee_west")
	var tee_start := _sample(tower, "room_13_transition_start")
	_check(str(tower.get_tower_snapshot().get("camera_profile_id", "")) == "tee_west", "room_13 未切换到第三个 profile")
	_check(absf(float(tee_start.get("camera_yaw_deg", 0.0))) < 18.0, "room_13 切换首帧已硬切方向")
	await _settle(75)
	var tee_sample := _sample(tower, "room_13_settled")
	_check(absf(float(tee_sample.get("camera_yaw_deg", 999.0)) - 18.0) < 1.0, "room_13 未收敛到18°固定方向")

	var snapshot := tower.get_tower_snapshot()
	_check(bool(snapshot.get("camera_collision_enabled", false)), "相机碰撞开关未保持开启")
	_check(str(snapshot.get("camera_collision_mode", "")).contains("lower_wall"), "墙体碰撞模式未保持")
	_check(str(snapshot.get("camera_stair_slab_mode", "")).contains("vertical_clamp"), "顶盖/楼板夹镜模式未保持")
	_write_reports()
	if DisplayServer.get_name() != "headless":
		# 运行时实测 18° 是 room_13 的正后方背面姿态；
		# 角色姿态仅用于验收截图，镜头目标方向仍由 room_13 profile 固定为18°。
		tower.player.set_physics_process(false)
		tower.player.aim_yaw = deg_to_rad(18.0)
		await _settle(12)
		await _save_render(tower, "expedition02_camera_room13.png")
		tower.player.set_physics_process(true)
	else:
		print("EXPEDITION02_CAMERA_RENDER_SKIPPED=headless")
	print("EXPEDITION02_CAMERA_PROFILE_SAMPLES=%d" % samples.size())
	_finish()


func _prepare_probe_camera_for_render(camera: Camera3D) -> void:
	if DisplayServer.get_name() == "headless" or camera == null:
		return
	_saved_probe_camera_attributes = camera.attributes
	camera.attributes = null
	print("EXPEDITION02_CAMERA_PROBE_DOF_DISABLED=true")


func _prepare_render_room(room: DungeonRoom3D) -> void:
	if DisplayServer.get_name() == "headless" or room == null:
		return
	room.ensure_shell_built()
	room.ensure_detail_built()
	var dimensions := room.get_dimensions()
	var light_count := maxi(2, ceili(maxf(dimensions.x, dimensions.y) / 18.0))
	for index in range(light_count):
		var light := OmniLight3D.new()
		light.name = "ProbeCameraLight_%02d" % index
		light.light_color = Color(0.78, 0.88, 1.0)
		light.light_energy = 4.0
		light.omni_range = maxf(18.0, maxf(dimensions.x, dimensions.y) * 0.72)
		var t := float(index + 1) / float(light_count + 1)
		var axis_length := maxf(dimensions.x, dimensions.y) - 4.0
		if dimensions.y > dimensions.x:
			light.position = Vector3(0.0, 2.2, lerpf(-axis_length * 0.5, axis_length * 0.5, t))
		else:
			light.position = Vector3(lerpf(-axis_length * 0.5, axis_length * 0.5, t), 2.2, 0.0)
		room.add_child(light)


func _sample_room(tower: TowerDescent3D, room: DungeonRoom3D, label: String) -> void:
	tower.force_enter_room_for_test(room.room_id)
	tower.player.global_position = room.global_position + Vector3(0.0, 0.05, 0.0)
	await _settle(75)
	_sample(tower, label)


func _sample(tower: TowerDescent3D, label: String) -> Dictionary:
	var camera := tower.player.camera
	var snapshot: Dictionary = tower.get_tower_snapshot()
	var forward := _camera_forward(camera)
	var visual_root := tower.player.find_child("VisualRoot", true, false) as Node3D
	var avatar_forward := Vector3.ZERO
	if visual_root != null:
		avatar_forward = -visual_root.global_basis.z
		avatar_forward.y = 0.0
		avatar_forward = avatar_forward.normalized()
	var camera_from_player := camera.global_position - tower.player.global_position
	camera_from_player.y = 0.0
	camera_from_player = camera_from_player.normalized()
	var value := {
		"label": label,
		"profile": str(snapshot.get("camera_profile_id", "")),
		"camera_height": float(snapshot.get("camera_height_m", 0.0)),
		"camera_local": camera.position,
		"camera_world": camera.global_position,
		"camera_yaw_deg": rad_to_deg(atan2(-forward.x, -forward.z)),
		"camera_forward": forward,
		"avatar_forward": avatar_forward,
		"camera_from_player": camera_from_player,
		"camera_avatar_dot": camera_from_player.dot(avatar_forward),
		"player_yaw_deg": rad_to_deg(tower.player.rotation.y),
		"camera_trailing": float(snapshot.get("camera_trailing_current_m", 0.0)),
		"camera_collision_adjusted": bool(snapshot.get("camera_collision_adjusted", false)),
	}
	samples.append(value)
	print("CAMERA_SAMPLE %s %s" % [label, str(value)])
	return value


func _camera_forward(camera: Camera3D) -> Vector3:
	var result := -camera.global_basis.z
	result.y = 0.0
	return result.normalized()


func _write_reports() -> void:
	DirAccess.make_dir_recursive_absolute(WORK_DIR)
	var report_samples: Array[Dictionary] = []
	for value in samples:
		report_samples.append({
			"label": str(value.get("label", "")),
			"profile": str(value.get("profile", "")),
			"camera_height_m": float(value.get("camera_height", 0.0)),
			"camera_local": str(value.get("camera_local", Vector3.ZERO)),
			"camera_world": str(value.get("camera_world", Vector3.ZERO)),
			"camera_yaw_deg": float(value.get("camera_yaw_deg", 0.0)),
			"camera_forward": str(value.get("camera_forward", Vector3.ZERO)),
			"player_yaw_deg": float(value.get("player_yaw_deg", 0.0)),
			"camera_trailing_m": float(value.get("camera_trailing", 0.0)),
			"camera_collision_adjusted": bool(value.get("camera_collision_adjusted", false)),
		})
	var report := {
		"level_id": "expedition_02",
		"samples": report_samples,
		"failures": failures.duplicate(),
		"display_server": DisplayServer.get_name(),
	}
	var json_file: FileAccess = FileAccess.open(
		"%s/expedition02_camera_report.json" % WORK_DIR,
		FileAccess.WRITE
	)
	if json_file == null:
		_fail("无法创建相机 JSON 报告")
	else:
		json_file.store_string(JSON.stringify(report, "\\t"))
		json_file.close()
	var csv_file: FileAccess = FileAccess.open(
		"%s/expedition02_camera_samples.csv" % WORK_DIR,
		FileAccess.WRITE
	)
	if csv_file == null:
		_fail("无法创建相机 CSV 报告")
	else:
		csv_file.store_line("label,profile,camera_height_m,camera_yaw_deg,player_yaw_deg,camera_trailing_m,camera_collision_adjusted")
		for value in samples:
			csv_file.store_line(",".join([
				str(value.get("label", "")),
				str(value.get("profile", "")),
				str(value.get("camera_height", 0.0)),
				str(value.get("camera_yaw_deg", 0.0)),
				str(value.get("player_yaw_deg", 0.0)),
				str(value.get("camera_trailing", 0.0)),
				str(value.get("camera_collision_adjusted", false)),
			]))
		csv_file.close()
	print("EXPEDITION02_CAMERA_REPORT=%s" % WORK_DIR)


func _save_render(tower: TowerDescent3D, filename: String) -> void:
	for _index in range(3):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	await get_tree().create_timer(0.15).timeout
	var image := get_viewport().get_texture().get_image()
	var user_path := "%s/%s" % [OUT_DIR, filename]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var error := image.save_png(user_path)
	_check(error == OK, "真实视口截图保存失败：%s" % str(error))
	DirAccess.make_dir_recursive_absolute(WORK_DIR)
	var copy_path := "%s/%s" % [WORK_DIR, filename]
	var source := FileAccess.open(user_path, FileAccess.READ)
	var target := FileAccess.open(copy_path, FileAccess.WRITE)
	_check(source != null and target != null, "无法复制渲染验收图到 ShellStorm2-work")
	if source != null and target != null:
		target.store_buffer(source.get_buffer(source.get_length()))


func _settle(frames: int) -> void:
	for _index in range(frames):
		await get_tree().process_frame
		await get_tree().physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failures.append(message)
	push_error("[EXP02_CAMERA] %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("EXPEDITION02_CAMERA_PROFILE_VERIFY_OK")
	else:
		print("EXPEDITION02_CAMERA_PROFILE_VERIFY_FAIL count=%d" % failures.size())
		for failure in failures:
			print("  - %s" % failure)
	get_tree().quit(0 if failures.is_empty() else 1)
