extends "res://tests/verification/probe_landscape_perf_20261003.gd"

# Diagnostic only: actual scene and player camera, deterministic bridge traversal.
# APPDATA must be isolated by the launcher before any Autoload starts.
func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.get_environment("BRIDGE_DIAGNOSTIC") != "1":
		get_tree().quit(2)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RuntimePerformanceManager.set_verification_frame_budget_override(2147483647)
	Engine.max_fps = 0
	var width := int(OS.get_environment("BRIDGE_WIDTH"))
	get_window().size = Vector2i(width, width * 9 / 16) if width > 0 else Vector2i(1280, 720)
	var start := Time.get_ticks_usec()
	tower = (load("res://scenes/TowerDescent3D.tscn") as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	foundation = tower.get_node("Blocks/Rooftop/CrossTowerRoute/LandscapeFoundation")
	city = foundation.get_node("ProceduralCity500")
	while not city.get("binding_complete"):
		await get_tree().process_frame
	clouds = tower.get_node("OutdoorClouds")
	old_city = tower.find_children("CityBuildingSilhouettes", "MultiMeshInstance3D", true, false)[0]
	ground = foundation.get_node("OpenWorldGroundPlane")
	report["startup_ms"] = (Time.get_ticks_usec() - start) / 1000.0
	GameTimeManager.process_mode = Node.PROCESS_MODE_DISABLED
	tower.player.process_mode = Node.PROCESS_MODE_DISABLED
	tower.player.global_position = Vector3(20, 0.05, -32.5)
	tower.player.camera.make_current()
	await _wait_seconds(3.0)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	report["metadata"] = {"adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "viewport": str(get_viewport().get_visible_rect().size), "user_data": OS.get_user_data_dir(), "clouds": clouds.get_presentation_snapshot(), "cache": clouds.get_procedural_city_cache_snapshot(), "city_count": city.get("placements").size(), "batches": city.get_child_count(), "camera": var_to_str(tower.player.camera.transform), "note": "Player translation scripted along actual bridge centerlines; input/move_and_slide disabled; gameplay and camera probes active except frozen cases; fixed world clock."}
	var cases: Array[String] = ["all_first", "all_repeat", "no_cloud", "no_landscape", "cloud_balanced", "frozen_all", "frozen_no_cloud"]
	var selected := OS.get_environment("BRIDGE_CASES")
	if not selected.is_empty():
		cases.clear()
		for value in selected.split(","):
			cases.append(value)
	for case_name in cases:
		clouds.visible = case_name not in ["no_cloud", "frozen_no_cloud"]
		foundation.visible = case_name != "no_landscape"
		old_city.visible = case_name != "no_landscape"
		clouds.apply_performance_quality("low" if case_name == "cloud_low" else "balanced" if case_name == "cloud_balanced" else "high")
		if case_name == "no_fallback_diagnostic":
			for volume in clouds.get_cloud_volumes():
				(volume["node"].material_override as ShaderMaterial).set_shader_parameter("fallback_count", 0)
		tower.process_mode = Node.PROCESS_MODE_DISABLED if case_name.begins_with("frozen") else Node.PROCESS_MODE_INHERIT
		clouds.process_mode = Node.PROCESS_MODE_ALWAYS
		tower.player.global_position = Vector3(20, 0.05, -32.5)
		await _wait_seconds(1.0)
		clouds.set("_flow_time", 0.0)
		print("BRIDGE_BEGIN ", case_name)
		var rows: Array = []
		var previous := Time.get_ticks_usec()
		var began := previous
		var shot := false
		while Time.get_ticks_usec() - began < 16000000:
			var distance := minf((Time.get_ticks_usec() - began) / 1000000.0 * 8.0, 128.0)
			tower.player.global_position = Vector3(20, 0.05, -32.5 - distance) if distance <= 64 else Vector3(20 - (distance - 64) * 0.5, 0.05, -96.5 - (distance - 64) * 0.8660254)
			tower.player.velocity = Vector3(0, 0, -8)
			await get_tree().process_frame
			var tick := Time.get_ticks_usec()
			rows.append([distance, (tick - previous) / 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()), RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), tower.player.global_position.x, tower.player.global_position.z])
			previous = tick
			if distance > 48 and not shot:
				shot = true
				# Capture outside the sample loop later; no readback stalls in timings.
		report["runs"].append({"case": case_name, "columns": ["distance_m", "frame_ms", "process_ms", "physics_ms", "render_cpu_ms", "gpu_ms", "drawcalls", "primitives", "nodes", "x", "z"], "samples": rows})
		_save()
		print("BRIDGE_END ", case_name, " frames=", rows.size())
	# Actual player camera screenshots at bridge positions, after timings.
	tower.process_mode = Node.PROCESS_MODE_DISABLED
	clouds.visible = true
	foundation.visible = true
	old_city.visible = true
	clouds.apply_performance_quality("high")
	for distance in [24.0, 48.0, 80.0, 112.0]:
		tower.player.global_position = Vector3(20, 0.05, -32.5 - distance) if distance <= 64 else Vector3(20 - (distance - 64) * 0.5, 0.05, -96.5 - (distance - 64) * 0.8660254)
		await _wait_seconds(0.4)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("bridge_%03d.png" % distance))
	_save()
	print("BRIDGE_COMPLETE")
	get_tree().quit(0)
