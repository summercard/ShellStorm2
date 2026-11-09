extends "res://tests/verification/verify_main_story_performance.gd"
## 真实导演逐帧消费正式JSON；不跳cue、不伪造controller、不改镜头构图。
## SHELLSTORM_MAIN_STORY_CHAPTER=031/033；输出目录由外层workspace_paths创建。

func _run() -> void:
	if DisplayServer.get_name() == "headless" or _capture_dir.is_empty():
		push_error("正式表演capture需要真实渲染器和工程外输出目录")
		get_tree().quit(2)
		return
	if not NarrativeDirector.has_method("release_main_story_control") or not NarrativeDirector.has_method("restore_main_story_camera"):
		push_error("跨模块导演屏障/真实progress交还接口未接；拒绝冒充完整表演验收")
		get_tree().quit(2)
		return
	_old_data = BaseManager.data
	_old_save_path = BaseManager.save_path
	BaseManager.data = BaseData.new()
	BaseManager.save_path = "user://chapter_capture.json"
	var briefing := OS.get_environment("SHELLSTORM_MAIN_STORY_CHAPTER") == "031"
	if not briefing:
		BaseManager.data.main_story = {"schema_version": 1, "accepted": true, "keys": {KEY: {"state": "acquired"}}}
	BaseManager.replace_narrative_history_for_test({"nar_opening_01": {"completed_count": 1}, "nar_opening_02": {"completed_count": 1}, "nar_opening_03": {"completed_count": 1}})
	NarrativeDirector.reset_for_test()
	NarrativeDirector.set_process(false)
	tower = BASE_SCENE.instantiate() as Node3D
	tower.set("test_mode", true)
	tower.set("force_main_story_for_test", true)
	tower.set("run_seed_override", 77001199)
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	tower.set_process(false)
	controller = tower.call("get_main_story_controller") as Node
	controller.set_process(false)
	NarrativeDirector.abort("capture_setup")
	NarrativeDirector.bind_dungeon_for_test(tower)
	npc = tower.call("find_npc", "npc_base99_green") as Node3D
	var player := tower.get("player") as Node3D
	player.set_physics_process(false)
	player.global_position = (npc.global_position + Vector3(0, 0, 3)) if briefing else tower.call("get_facility_spawn_point")
	var room := tower.call("get_main_story_room", "facility") as Node3D
	room.call("ensure_shell_built")
	room.call("ensure_detail_built")
	tower.call("apply_narrative_light_state", "facility", true)
	tower.set("_current_room_id", "facility")
	var camera := player.get("camera") as Camera3D
	camera.global_position = player.global_position + Vector3(4, 8, 8)
	camera.look_at(player.global_position)
	var chapter := MainStoryChapter3D.BRIEFING_ID if briefing else MainStoryChapter3D.DEPOSIT_ID
	check(NarrativeDirector.play(chapter), "正式JSON开始逐帧演出")
	NarrativeDirector.set_process(true)
	var elapsed := 0.0
	var capture_accumulator := 0.0
	var frame_index := 0
	while NarrativeDirector.is_playing() and elapsed < 180.0:
		await get_tree().process_frame
		var delta := get_process_delta_time()
		elapsed += delta
		capture_accumulator += delta
		if capture_accumulator >= 0.35:
			capture_accumulator = 0.0
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_capture_dir.path_join("chapter_%s_%04d.png" % ["031" if briefing else "033", frame_index]))
			frame_index += 1
			samples.append({"real_elapsed": elapsed, "narrative_time": NarrativeDirector.active_time(), "npc": npc.global_position,
				"camera": camera.global_transform, "controller": controller.call("get_snapshot")})
	check(elapsed < 180.0, "完整导演表演未卡住屏障")
	check(BaseManager.has_narrative_completed(chapter), "正式剧情完整收口才写历史")
	check(not NarrativeDirector.is_player_input_locked() and not NarrativeDirector.is_camera_override_active(), "结束归还输入和相机")
	await _finish()
