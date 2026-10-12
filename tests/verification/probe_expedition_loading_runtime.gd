extends Node
## 真实读图链路回归：正常远征装配 + 统一返航，不使用 test_mode 绕过加载锁。
## 必须隔离 APPDATA；带窗口可生成实际读图与落地截图。

const LOADING_PATH := "res://scenes/ExpeditionLoadingScreen.tscn"
var _out_dir := OS.get_environment("SHELLSTORM_LOADING_PROBE_OUTPUT")
var _capture_shots := OS.get_environment("SHELLSTORM_LOADING_PROBE_SHOTS") == "1"
var _failures: Array[String] = []
var _records: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RuntimePerformanceManager.set_verification_frame_budget_override(60)
	if not _out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_out_dir)
	call_deferred("_run")

func _run() -> void:
	var tree := get_tree()
	# 自身跨 change_scene 保留，目标则必须由真实读取页安装。
	tree.current_scene = null
	GameEntryFlow.request_gameplay_entry(GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT)
	GameDesignConfig.select_expedition_level("expedition_01")
	await IrisTransition.iris_close()
	_check(IrisTransition.is_covered(), "入口收圈未完整覆盖")
	tree.change_scene_to_file(LOADING_PATH)
	await tree.scene_changed
	var screen := tree.current_scene as ExpeditionLoadingScreen
	await _observe_loading(screen, "entry")
	var tower := tree.current_scene as TowerDescent3D
	if tower == null or not tower.is_expedition():
		_check(false, "目标不是远征地图")
		_finish()
		return
	await _check_ground(tower, "entry", "start")
	# 走真实成功撤离事务：它先摘除检查点提供者并写携带交接，
	# 再进入共用返航。直接调视觉切换会在 unload 时额外保存整张旧地图，
	# 既制造一次非正式路径的停顿，也无法验收真实返航语义。
	tower._finish_run(true)
	await tree.scene_changed
	screen = tree.current_scene as ExpeditionLoadingScreen
	await _observe_loading(screen, "return")
	tower = tree.current_scene as TowerDescent3D
	if tower != null and not tower.is_expedition():
		await _check_ground(tower, "return", "facility")
	else:
		_check(false, "返航目标不是99F基地")
	_finish()

func _observe_loading(screen: ExpeditionLoadingScreen, label: String) -> void:
	if screen == null:
		_check(false, "%s 未经过读取页" % label)
		return
	var started: int = screen._loading_started_msec
	var deadline: int = Time.get_ticks_msec() + 60000
	var sampled := false
	var second_shot := false
	var stage := screen.get_node_or_null("Root/Content/BunnyStage") as Control
	if stage != null:
		_check(stage.size.is_equal_approx(Vector2(180, 200)), "兔子舞台未缩小50%")
		_check(screen._status_label.get_global_rect().end.x <= stage.get_global_rect().position.x, "读取文字与角色舞台重叠")
	var frozen_samples := 0
	var first_position := Vector3.ZERO
	var has_position := false
	var last_frame_msec := Time.get_ticks_msec()
	var frame_gaps: Array[int] = []
	var visible_frame_gaps: Array[int] = []
	var previous_content_visible := true
	var assembly_frames := 0
	while is_instance_valid(screen) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var now_msec := Time.get_ticks_msec()
		frame_gaps.append(now_msec - last_frame_msec)
		last_frame_msec = now_msec
		if not is_instance_valid(screen):
			break
		if previous_content_visible and screen._content.modulate.a > 0.99:
			visible_frame_gaps.append(frame_gaps.back())
		previous_content_visible = screen._content.modulate.a > 0.99
		var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
		if elapsed > 0.4 and elapsed < 1.98:
			_check(screen._content.modulate.a > 0.95, "%s 兔子/文字在2秒前淡出" % label)
		var target := get_tree().current_scene as TowerDescent3D
		if label == "entry" and target != null:
			if screen._content.modulate.a > 0.01:
				_check(not target.visible, "远征装配期间提前显示世界")
			_check(not target.player.can_process(), "远征装配期间玩家仍在处理")
			_check(target.player.input_locked, "远征加载期间输入锁被释放")
			if bool(target.get_meta("loading_bootstrap_pending", false)):
				assembly_frames += 1
				_check(not target._runtime_persistence_active, "地图装配完成前激活了持久化")
			# 初始化会设置正式出生点；只比较装配/所有权交接完成后的锁内位置。
			if bool(target.get_meta("loading_scene_ready", false)):
				if not has_position:
					first_position = target.player.global_position
					has_position = true
				_check(target.player.global_position.is_equal_approx(first_position), "远征就绪后的加载锁内玩家位置变化")
			frozen_samples += 1
		if elapsed >= 1.2 and not sampled:
			sampled = true
			if target != null and label == "entry":
				var entry_room := target._room_by_id.get("start") as DungeonRoom3D
				print("LOADING_SAMPLE entry visible=%s root_mode=%d player_mode=%d player=%s room=%s room_pos=%s collisions=%d" % [
					target.visible, target.process_mode, target.player.process_mode,
					target.player.global_position, entry_room != null, entry_room.global_position if entry_room != null else Vector3.ZERO,
					get_tree().get_nodes_in_group("dungeon_room_3d").size(),
				])
			await _shot(label + "_loading")
			last_frame_msec = Time.get_ticks_msec()
		if _capture_shots and sampled and not second_shot and elapsed >= 1.8:
			second_shot = true
			await _shot(label + "_loading_later")
			last_frame_msec = Time.get_ticks_msec()
	_check(not is_instance_valid(screen), "%s 读取页超时" % label)
	if label == "entry":
		_check(assembly_frames > 1, "远征装配未分帧推进")
	var seconds := float(Time.get_ticks_msec() - started) / 1000.0
	_check(seconds >= 2.0, "%s 读取页不足2秒：%.3f" % [label, seconds])
	if label == "entry":
		_check(frozen_samples > 0, "未采样到远征加载锁")
	var mid_shot := false
	var open_started := Time.get_ticks_msec()
	while float(IrisTransition.get("_radius")) < IrisTransition.HOLE_MAX - 0.001:
		await get_tree().process_frame
		var radius := float(IrisTransition.get("_radius"))
		if not mid_shot and radius > 0.15 and radius < 0.85:
			mid_shot = true
			await _shot(label + "_iris_open")
		if Time.get_ticks_msec() - open_started > 5000:
			_check(false, "%s 开圈超时" % label)
			break
	var open_seconds := float(Time.get_ticks_msec() - open_started) / 1000.0
	if DisplayServer.get_name() != "headless":
		_check(open_seconds >= IrisTransition.OPEN_SECONDS - 0.06, "%s 开圈动画被跳过" % label)
	_records.append({"phase": label, "loading_seconds": seconds, "open_seconds": open_seconds, "frozen_samples": frozen_samples, "assembly_frames": assembly_frames, "frame_gaps_ms": frame_gaps, "visible_frame_gaps_ms": visible_frame_gaps})
	print("LOADING_RUNTIME %s duration=%.3f open=%.3f frozen_samples=%d" % [label, seconds, open_seconds, frozen_samples])

func _check_ground(tower: TowerDescent3D, label: String, room_id: String) -> void:
	var room := tower._room_by_id.get(room_id) as DungeonRoom3D
	_check(room != null, "%s 缺少目标房间" % label)
	if room == null:
		return
	_check(tower.visible, "%s 释放后世界没有恢复显示" % label)
	var min_y := INF
	var grounded := false
	for _i in 90:
		await get_tree().physics_frame
		min_y = minf(min_y, tower.player.global_position.y)
		grounded = grounded or tower.player.is_on_floor()
	_check(room.contains_world_position(tower.player.global_position), "%s 玩家不在目标房间：%s" % [label, tower.player.global_position])
	_check(min_y > room.global_position.y - 0.5, "%s 玩家掉出地板：min_y=%.3f" % [label, min_y])
	_check(grounded, "%s 玩家没有站稳地面" % label)
	var from := tower.player.global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0, 1)
	query.exclude = [tower.player.get_rid()]
	var hit := tower.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty(), "%s 玩家脚下无实体碰撞" % label)
	_records.append({"phase": label + "_ground", "player_position": str(tower.player.global_position), "min_y": min_y, "grounded": grounded, "floor_hit": str(hit.get("position", "none"))})
	print("LOADING_GROUND %s position=%s min_y=%.3f grounded=%s floor_hit=%s" % [label, tower.player.global_position, min_y, grounded, hit.get("position", "none")])
	await _shot(label + "_ground")

func _shot(label: String) -> void:
	if not _capture_shots or _out_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image != null:
		image.save_png(_out_dir + "/loading_runtime_" + label + ".png")

func _check(ok: bool, message: String) -> void:
	if not ok and message not in _failures:
		_failures.append(message)
		print("LOADING_RUNTIME_FAIL " + message)

func _finish() -> void:
	var report := {"records": _records, "failures": _failures, "ok": _failures.is_empty()}
	if not _out_dir.is_empty():
		var file := FileAccess.open(_out_dir + "/loading_runtime_result.json", FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
	RuntimePerformanceManager.set_verification_frame_budget_override(0)
	print("PROBE_OK expedition_loading_runtime" if _failures.is_empty() else "PROBE_FAILED expedition_loading_runtime")
	get_tree().quit(0 if _failures.is_empty() else 1)
