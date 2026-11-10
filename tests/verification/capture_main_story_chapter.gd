extends "res://tests/verification/verify_main_story_performance.gd"
## 独立用户目录、原生 Forward+；只采样正式 JSON，不重写剧情镜头或演员状态。

var _chapter_code := ""
var _chapter_id := ""
var _scene_path := ""
var _script_data: Dictionary = {}
var _frames: Array[Dictionary] = []
var _trace: Array[Dictionary] = []
var _dialogue_seen: Dictionary = {}
var _capture_targets: Array[float] = []
var _captured_targets: Dictionary = {}
var _activation_frames: Dictionary = {}
var _began_ms := 0
var _duration := 0.0
var _boss: Enemy3D
var _initial_activation: Dictionary = {}
var _release_activation: Dictionary = {}
var _map_evidence: Dictionary = {}
var _end_state: Dictionary = {}
var _finish_reason := ""

func _run() -> void:
	_began_ms = Time.get_ticks_msec()
	_chapter_code = OS.get_environment("SHELLSTORM_MAIN_STORY_CHAPTER")
	if DisplayServer.get_name() == "headless" or _capture_dir.is_empty() or _chapter_code not in ["031", "032", "033"]:
		push_error("正式表演capture需要真实渲染器、工程外目录及031/032/033章节")
		get_tree().quit(2)
		return
	get_tree().create_timer(450.0).timeout.connect(_watchdog)
	_old_data = BaseManager.data
	_old_save_path = BaseManager.save_path
	BaseManager.data = BaseData.new()
	BaseManager.save_path = "user://chapter_capture.json"
	if _chapter_code == "033":
		BaseManager.data.main_story = {"schema_version": 1, "accepted": true, "keys": {KEY: {"state": "acquired"}}}
	var history := {"nar_opening_01": {"completed_count": 1}, "nar_opening_02": {"completed_count": 1}, "nar_opening_03": {"completed_count": 1}}
	if _chapter_code != "031":
		history[MainStoryChapter3D.BRIEFING_ID] = {"completed_count": 1}
	BaseManager.replace_narrative_history_for_test(history)
	NarrativeDirector.reset_for_test()
	NarrativeDirector.set_process(false)
	_chapter_id = {"031": MainStoryChapter3D.BRIEFING_ID, "032": MainStoryChapter3D.BOSS_ID, "033": MainStoryChapter3D.DEPOSIT_ID}[_chapter_code]
	_scene_path = "res://scenes/ExpeditionLevel01_3D.tscn" if _chapter_code == "032" else "res://scenes/TowerDescent3D.tscn"
	_script_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/narrative/" + _chapter_id + ".json"))
	for cue: Dictionary in _script_data.get("cues", []):
		if cue.get("do", "") in ["actor.say", "ui.subtitle"]:
			_capture_targets.append(float(cue.at) + 1.1)
	if _chapter_code == "033":
		_capture_targets.append_array([0.1, 4.6, 4.8, 5.0, 9.4, 9.6, 17.8])
	if _chapter_code == "031":
		_capture_targets.append_array([55.05, 55.2])
	if _chapter_code == "032":
		_capture_targets.append_array([0.5, 3.0, 12.0, 24.5])
	_capture_targets.sort()
	print("VISUAL_STAGE instantiate ", _scene_path)
	tower = (load(_scene_path) as PackedScene).instantiate() as Node3D
	tower.set("test_mode", true)
	tower.set("force_main_story_for_test", true)
	tower.set("run_seed_override", 77001199)
	var mounted := {"generated": false, "started": false}
	tower.connect("generation_completed", func(_snapshot: Dictionary) -> void: mounted.generated = true)
	tower.connect("gameplay_started", func(_room_id: String) -> void: mounted.started = true)
	add_child(tower)
	if not mounted.generated:
		await tower.generation_completed
	if not mounted.started:
		await tower.gameplay_started
	await get_tree().physics_frame
	print("VISUAL_STAGE gameplay_ready ms=", Time.get_ticks_msec() - _began_ms)
	# 只关闭控制器的自动触发；宿主位置权威、机位、流送和可见性照常更新。
	tower.set("_main_story_gameplay_started", false)
	controller = tower.call("get_main_story_controller") as Node
	check(controller != null, "正式场景主线控制器已装配")
	if controller == null:
		await _finish()
		return
	controller.set_process(false)
	NarrativeDirector.abort("capture_setup")
	NarrativeDirector.bind_dungeon_for_test(tower)
	DialogueUI.close()
	var player := tower.get("player") as Node3D
	player.set_physics_process(_chapter_code in ["031", "032"])
	if _chapter_code == "032":
		await _setup_boss(player)
	else:
		npc = tower.call("find_npc", "npc_base99_green") as Node3D
		check(npc != null, "真实绿苔已装配")
		if npc == null:
			await _finish()
			return
		var room := tower.call("get_main_story_room", "facility") as DungeonRoom3D
		room.ensure_shell_built()
		room.ensure_detail_built()
		player.global_position = npc.global_position + Vector3(0, 0, 3) if _chapter_code == "031" else tower.call("get_facility_spawn_point")
		tower.call("force_enter_room_for_test", "facility")
		tower.call("apply_narrative_light_state", "facility", true)
	tower.call("_update_floor_visibility_state")
	tower.call("_apply_indoor_camera_pose")
	var camera := player.get("camera") as Camera3D
	camera.make_current()
	await get_tree().process_frame
	await _save_frame("00_gameplay_pose", player)
	if _chapter_code == "032" and _boss == null:
		await _finish()
		return
	check(not BaseManager.has_narrative_completed(_chapter_id), "开始时本章历史未完成")
	NarrativeDirector.narrative_finished.connect(func(id: String, reason: String) -> void:
		if id == _chapter_id: _finish_reason = reason)
	check(NarrativeDirector.play(_chapter_id), "正式JSON开始逐帧演出")
	NarrativeDirector.set_process(true)
	var started := Time.get_ticks_msec()
	while NarrativeDirector.is_playing() and float(Time.get_ticks_msec() - started) / 1000.0 < 180.0:
		await get_tree().process_frame
		_duration = float(Time.get_ticks_msec() - started) / 1000.0
		var t := NarrativeDirector.active_time()
		var state: Dictionary = controller.call("get_snapshot")
		var line := DialogueUI.current_text() if DialogueUI.is_active() else ""
		var npc_line := _bark_text(npc)
		var player_line := _bark_text(player)
		for text in [line, npc_line, player_line]:
			if not text.is_empty(): _dialogue_seen[text] = true
		var activation: Dictionary = _boss.get_story_activation_snapshot() if is_instance_valid(_boss) else {}
		_trace.append({"wall": _duration, "t": t, "locked": NarrativeDirector.is_player_input_locked(), "player_locked": player.get("input_locked"), "camera_override": NarrativeDirector.is_camera_override_active(), "subtitle": line, "npc_line": npc_line, "player_line": player_line, "activation": activation})
		for target in _capture_targets:
			if t >= target and not _captured_targets.has(str(target)):
				_captured_targets[str(target)] = true
				if _chapter_code == "032" and is_equal_approx(target, 24.5):
					var listening: Vector3 = controller.call("resolve_anchor", "boss_listening")
					check(Vector2(player.global_position.x - listening.x, player.global_position.z - listening.z).length() < 0.25, "正式player.walk_to沿坡道到达听话点")
					check(not bool(activation.get("started", true)) and bool(activation.get("held", false)), "下坡阶段Boss门闩始终保持inactive")
				await _save_frame("t_%06.2f" % target, player)
		if is_instance_valid(_boss) and bool(activation.get("started", false)):
			var a := float(activation.get("elapsed", 0.0))
			for target in [0.1, 2.5, 4.5, 5.35, 5.45, 6.35]:
				if a >= target and not _activation_frames.has(str(target)):
					_activation_frames[str(target)] = true
					await _save_frame("activation_%04.2f" % target, player)
			if a >= 5.4 and _release_activation.is_empty() and not NarrativeDirector.is_player_input_locked():
				_release_activation = {"activation": activation.duplicate(true), "wall": _duration, "player_locked": player.get("input_locked"), "history_completed": BaseManager.has_narrative_completed(_chapter_id)}
	check(_duration < 180.0, "完整导演表演未卡住屏障")
	check(BaseManager.has_narrative_completed(_chapter_id), "正式剧情完整收口才写历史")
	check(not NarrativeDirector.is_player_input_locked() and not NarrativeDirector.is_camera_override_active(), "结束归还导演输入和相机")
	tower.call("refresh_player_input_lock")
	check(not bool(player.get("input_locked")), "正式宿主刷新后玩家输入已归还")
	check(NarrativeDirector.diagnostics().is_empty(), "正式导演无降级或指令错误")
	if _chapter_code == "031":
		var briefing_finish: Vector3 = controller.call("resolve_anchor", "briefing_finish")
		check(Vector2(player.global_position.x - briefing_finish.x, player.global_position.z - briefing_finish.z).length() < 0.25, "正式JSON步行到中央安全通道后还镜而非瞬移")
	if _chapter_code == "032":
		check(not _release_activation.is_empty(), "真实激活5.4秒后且6.4秒完成前观察到释控")
		check(not bool(_release_activation.get("history_completed", true)), "释控时未提前写历史")
		check(bool(_boss.get_story_activation_snapshot().get("completed", false)), "真实EnemyPhysics激活6.4秒完整结束")
	if _chapter_code == "033":
		check(MainStoryProgress.key_state(BaseManager.get_main_story_snapshot(), KEY) == "deposited", "正式演出安装事务已提交")
	_end_state = {"history_completed": BaseManager.has_narrative_completed(_chapter_id), "input_locked": NarrativeDirector.is_player_input_locked(), "camera_override": NarrativeDirector.is_camera_override_active(), "player_locked": player.get("input_locked"), "combat_enabled": player.get("combat_enabled"), "host_processing": tower.is_processing(), "host_physics_processing": tower.is_physics_processing(), "room_id": tower.call("get_current_room_id"), "controller": controller.call("get_snapshot"), "story": BaseManager.get_main_story_snapshot()}
	await _save_frame("98_returninput", player)
	await get_tree().create_timer(0.5).timeout
	await _save_frame("99_finished", player)
	if _chapter_code in ["031", "033"]:
		await _capture_map(player)
	await _finish()

func _setup_boss(player: Node3D) -> void:
	var room := tower.call("get_main_story_room", "boss") as DungeonRoom3D
	check(room != null, "真实远征01存在Boss房")
	if room == null: return
	room.ensure_shell_built()
	room.ensure_detail_built()
	room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	var door: Node3D
	for side in room.door_targets:
		door = room.get_door_node(str(side))
		if door != null: break
	var spawn := room.global_position + Vector3(5, 0.05, 5)
	if door != null:
		var inward := room.global_position - door.global_position
		inward.y = 0.0
		spawn = door.global_position + inward.normalized() * 3.0
		spawn.y = door.global_position.y + 0.13
	player.global_position = spawn
	tower.call("force_enter_room_for_test", room.room_id)
	await get_tree().physics_frame
	print("VISUAL_BOSS_ROOM ", JSON.stringify({"snapshot": room.get_room_snapshot(), "origin": str(room.global_position), "entry": str(spawn), "boss_anchor": str(room.boss_spawn_position_world()), "door": str(door.global_position) if door != null else ""}))
	var floor_query := PhysicsRayQueryParameters3D.create(spawn + Vector3.UP * 20.0, spawn + Vector3.DOWN * 20.0, 1)
	floor_query.collide_with_areas = false
	floor_query.exclude = [(player as CollisionObject3D).get_rid()]
	var floor_hit := tower.get_world_3d().direct_space_state.intersect_ray(floor_query)
	print("VISUAL_ENTRY_FLOOR ", floor_hit)
	check(not floor_hit.is_empty() and (floor_hit.get("normal", Vector3.ZERO) as Vector3).y > 0.7, "真实高平台入口有承重")
	if floor_hit.is_empty(): return
	spawn = (floor_hit.position as Vector3) + Vector3.UP * 0.05
	player.global_position = spawn
	tower.call("force_enter_room_for_test", room.room_id)
	await get_tree().physics_frame
	_boss = tower.call("get_main_story_boss") as Enemy3D
	print("VISUAL_BOSS_GEOMETRY ", JSON.stringify({"room": room.get_room_snapshot(), "entry": str(spawn), "boss_anchor": str(room.boss_spawn_position_world()), "label": str(tower.get("room_label").text), "door": str(door.global_position) if door != null else ""}))
	check(str(tower.call("get_current_room_id")) == room.room_id, "正式进房事务已同步Boss房归属")
	check(_boss != null, "真实显示器Boss存在")
	if _boss == null: return
	_initial_activation = _boss.get_story_activation_snapshot().duplicate(true)
	check(bool(_initial_activation.get("held", false)) and not bool(_initial_activation.get("started", true)) and not bool(_initial_activation.get("completed", true)), "Boss保持正常未激活起态")
	_boss.set_runtime_active(true)
	_boss.set_physics_process(true)
	await get_tree().physics_frame
	print("VISUAL_BOSS entry=", spawn, " boss=", _boss.global_position, " initial=", _initial_activation)

func _bark_text(actor: Node3D) -> String:
	if not is_instance_valid(actor): return ""
	for bark in actor.find_children("*", "CharacterBark3D", true, false):
		if bark.is_speaking(): return bark.get_current_text()
	return ""

func _save_frame(label: String, player: Node3D) -> void:
	await RenderingServer.frame_post_draw
	var path := _capture_dir.path_join("chapter_" + _chapter_code + "_" + label + ".png")
	var error := get_viewport().get_texture().get_image().save_png(path)
	check(error == OK, "截图落盘：" + label)
	var camera := get_viewport().get_camera_3d()
	_frames.append({"path": path, "label": label, "wall_elapsed": _duration, "narrative_time": NarrativeDirector.active_time(), "camera": str(camera.global_transform), "player": str(player.global_position), "npc": str(npc.global_position) if is_instance_valid(npc) else "", "subtitle": DialogueUI.current_text() if DialogueUI.is_active() else "", "npc_line": _bark_text(npc), "player_line": _bark_text(player), "controller": controller.call("get_snapshot")})
	if label in ["00_gameplay_pose", "98_returninput", "99_finished"]:
		var hits := []
		for uv in [Vector2(0.5, 0.8), Vector2(0.5, 0.95), Vector2(0.3, 0.85), Vector2(0.7, 0.85)]:
			var screen: Vector2 = get_viewport().get_visible_rect().size * uv
			var origin := camera.project_ray_origin(screen)
			var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 30.0, 1)
			query.collide_with_areas = false
			var hit := tower.get_world_3d().direct_space_state.intersect_ray(query)
			hits.append({"uv": str(uv), "collider": str(hit.get("collider", "")), "path": str(hit.collider.get_path()) if hit.has("collider") else "", "position": str(hit.get("position", ""))})
		print("VISUAL_FOREGROUND ", label, " ", JSON.stringify(hits))
		if label == "99_finished" and _chapter_code == "031":
			var screen: Vector2 = get_viewport().get_visible_rect().size * Vector2(0.5, 0.85)
			var origin := camera.project_ray_origin(screen)
			var end := origin + camera.project_ray_normal(screen) * 15.0
			var visual_hits := []
			for mesh in tower.find_children("*", "MeshInstance3D", true, false):
				if mesh.is_visible_in_tree() and mesh.get_aabb().intersects_segment(mesh.to_local(origin), mesh.to_local(end)) != null:
					visual_hits.append({"path": str(mesh.get_path()), "aabb": str(mesh.global_transform * mesh.get_aabb())})
			print("VISUAL_MESH_FOREGROUND ", JSON.stringify(visual_hits))
	print("VISUAL_FRAME ", label, " wall=", _duration, " t=", NarrativeDirector.active_time())

func _capture_map(player: Node3D) -> void:
	var menu := (load("res://scenes/RogueMapSelectMenu.tscn") as PackedScene).instantiate() as RogueMapSelectMenu
	menu.set_player(player)
	menu.set_facility(tower.call("get_main_story_facility", "mission_operations") as BaseFacility3D)
	tower.add_child(menu)
	await get_tree().create_timer(5.1).timeout
	var states := {}
	var locked := 0
	for id in menu.LEVEL_IDS:
		states[id] = menu.entry_state(id)
		if states[id] == "locked": locked += 1
	_map_evidence = {"scene": "res://scenes/RogueMapSelectMenu.tscn", "fixture": false, "host_test_mode": true, "states": states, "installed_count": menu.call("_main_story_deposited_count")}
	check(menu.LEVEL_IDS.size() == 4, "正式地图四入口列出")
	if _chapter_code == "031":
		check(locked == 3 and states.get("expedition_01") == "open", "新档仅数据中心开放、三个入口红锁")
	else:
		check(states.get("expedition_03") == "open" and int(_map_evidence.installed_count) == 1, "真实安装后无限公馆开放且1/4")
	await _save_frame("map_" + ("0of4_three_locks" if _chapter_code == "031" else "1of4_mansion_open"), player)
	menu.queue_free()
	await get_tree().process_frame

func _watchdog() -> void:
	failures.append("捕获超过450秒总预算；未完成项不通过")
	_write_report()
	get_tree().quit(3)

func _write_report() -> void:
	var file := FileAccess.open(_capture_dir.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"scene": _scene_path, "chapter": _chapter_id, "renderer": RenderingServer.get_current_rendering_method(), "rendering_driver": RenderingServer.get_current_rendering_driver_name(), "display_server": DisplayServer.get_name(), "adapter": RenderingServer.get_video_adapter_name(), "user_data_dir": OS.get_user_data_dir(), "fixture": true, "host_test_mode": true, "full_level_traversal": false, "fixture_scope": "只定位章节真实入场点；Boss正式进房生成、玩家沿正式JSON步行、宿主process/physics保持运行", "camera_setup": "TowerDescent3D._apply_indoor_camera_pose；此后仅正式JSON镜头", "duration": _duration, "total_wall_seconds": float(Time.get_ticks_msec() - _began_ms) / 1000.0, "finish_reason": _finish_reason, "checks": checks, "failures": failures, "unexpected_script_errors": [], "exit_code": null, "capture_frames": _frames, "end_state": _end_state, "initial_activation": _initial_activation, "release_activation": _release_activation, "map": _map_evidence, "dialogue_seen": _dialogue_seen.keys(), "director_diagnostics": NarrativeDirector.diagnostics(), "dispatch_log": NarrativeDirector.dispatch_log(), "visual_signoff": "待实际查看截图"}, "  "))
	var trace_file := FileAccess.open(_capture_dir.path_join("frame_trace.json"), FileAccess.WRITE)
	trace_file.store_string(JSON.stringify(_trace))

func _finish() -> void:
	_write_report()
	NarrativeDirector.abort("capture_cleanup")
	if is_instance_valid(tower): tower.queue_free()
	await get_tree().process_frame
	BaseManager.data = _old_data as BaseData
	BaseManager.save_path = _old_save_path
	print("MAIN_STORY_VISUAL_RESULT chapter=", _chapter_code, " checks=", checks, " failures=", failures, " duration=", _duration)
	get_tree().quit(0 if failures.is_empty() else 1)
