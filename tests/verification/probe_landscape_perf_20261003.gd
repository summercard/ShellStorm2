extends Node

var tower: TowerDescent3D
var foundation: Node3D
var city: Node3D
var clouds: VfxCloudSea3D
var old_city: MultiMeshInstance3D
var ground: MeshInstance3D
var out_dir := OS.get_environment("LANDSCAPE_PERF_OUTPUT")
var report: Dictionary = {"runs": [], "startup": {}}
var original_visibility: Dictionary = {}
var shadow_values: Dictionary = {}
var profile_supported := false
var viewport_timing_supported := false
var city_texture: ImageTexture

func _ready() -> void:
	_run.call_deferred()

func _process(_delta: float) -> void:
	Engine.max_fps = 0

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("性能测量禁止headless")
		get_tree().quit(2)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	RuntimePerformanceManager.set_verification_frame_budget_override(2147483647)
	Engine.max_fps = 0
	get_window().size = Vector2i(1280, 720)
	var start := Time.get_ticks_usec()
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	report["startup"]["scene_load_ms"] = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	tower = packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	report["startup"]["instantiate_ms"] = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	add_child(tower)
	report["startup"]["add_child_ready_ms"] = (Time.get_ticks_usec() - start) / 1000.0
	foundation = tower.get_node("Blocks/Rooftop/CrossTowerRoute/LandscapeFoundation")
	city = foundation.get_node("ProceduralCity500")
	while not city.get("binding_complete"):
		await get_tree().process_frame
	report["startup"]["ready_and_deferred_city_ms"] = (Time.get_ticks_usec() - start) / 1000.0
	clouds = tower.get_node("OutdoorClouds")
	old_city = tower.find_children("CityBuildingSilhouettes", "MultiMeshInstance3D", true, false)[0]
	ground = foundation.get_node("OpenWorldGroundPlane")
	city_texture = clouds.get("_procedural_city_texture")
	for child in foundation.get_children():
		if child is Node3D:
			original_visibility[child] = child.visible
		if child is GeometryInstance3D:
			shadow_values[child] = child.cast_shadow
	original_visibility[old_city] = old_city.visible
	original_visibility[clouds] = clouds.visible
	await _wait_seconds(2.0)
	tower.process_mode = Node.PROCESS_MODE_DISABLED
	clouds.process_mode = Node.PROCESS_MODE_ALWAYS
	GameTimeManager.process_mode = Node.PROCESS_MODE_DISABLED
	profile_supported = RenderingServer.has_method("set_frame_profiling_enabled")
	if profile_supported:
		RenderingServer.call("set_frame_profiling_enabled", true)
	viewport_timing_supported = RenderingServer.has_method("viewport_set_measure_render_time")
	if viewport_timing_supported:
		RenderingServer.call("viewport_set_measure_render_time", get_viewport().get_viewport_rid(), true)
	report["metadata"] = {"engine": Engine.get_version_info(), "display_server": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(), "adapter": RenderingServer.get_video_adapter_name(), "user_data_dir": OS.get_user_data_dir(), "appdata": OS.get_environment("APPDATA"), "seed": 990095, "city_seed": city.get("parameters")["seed"], "viewport_size": str(get_viewport().get_visible_rect().size), "window_size": str(get_window().size), "graphics": GraphicsSettingsManager.get_settings_snapshot(), "runtime_performance": RuntimePerformanceManager.get_snapshot(), "clouds": clouds.get_presentation_snapshot(), "new_city_count": city.get("placements").size(), "new_city_batches": city.get_child_count(), "old_city_count": old_city.multimesh.instance_count, "sampling_note": "冻结玩法与世界时钟以保持位置光照一致，云更新保留；keepout缓存不因隐藏几何减少；非历史版本对比", "profile_supported": profile_supported, "viewport_timing_supported": viewport_timing_supported}
	report["geometry"] = []
	for node in foundation.get_children():
		if node is GeometryInstance3D:
			report["geometry"].append(_geometry_info(node))
	for batch in city.get_children():
		report["geometry"].append(_geometry_info(batch))
	report["geometry"].append(_geometry_info(old_city))
	var cases: Array[String] = ["all", "hide_new_city", "hide_ground", "hide_foundations", "hide_cloud_draw", "hide_cloud_disabled", "hide_old_city", "hide_new_and_ground", "hide_all_landscape", "legacy_proxy", "city_keepout_off", "ground_shadows_off", "foundation_shadows_off", "hide_new_cloud_disabled"]
	if OS.get_environment("LANDSCAPE_PERF_SMOKE") == "1":
		cases = ["all", "city_keepout_off", "hide_cloud_disabled"]
	var repeats := 1 if OS.get_environment("LANDSCAPE_PERF_SMOKE") == "1" else 2
	var views: Array[String] = ["main", "tower3"]
	if OS.get_environment("LANDSCAPE_PERF_LIVE") == "1":
		views = ["main_live"]
	for view in views:
		tower.player.global_position = Vector3(-12, 0.05, -153.925626) if view == "tower3" else Vector3(0, 0.05, -30)
		tower.player.camera.make_current()
		if view == "main_live":
			tower.process_mode = Node.PROCESS_MODE_INHERIT
			tower.player.process_mode = Node.PROCESS_MODE_DISABLED
		for repeat in range(repeats):
			var order: Array = cases.duplicate()
			if view == "main_live":
				order.clear()
				order.append_array(["all", "city_keepout_off", "hide_cloud_disabled"])
			if repeat == 1:
				order.reverse()
			for case_name in order:
				_apply_case(case_name)
				print("PERF_BEGIN view=%s repeat=%d case=%s" % [view, repeat, case_name])
				await _wait_seconds(8.0)
				Engine.max_fps = 0
				var result: Dictionary = await _sample(6.0)
				result.merge({"view": view, "repeat": repeat, "case": case_name, "camera_transform": var_to_str(tower.player.camera.global_transform), "camera_far": tower.player.camera.far, "camera_fov": tower.player.camera.fov, "cloud_flow_start": 8.0, "clouds_processing": clouds.is_processing(), "cached_city_keepouts": clouds.get_procedural_city_exclusion_bounds().size(), "cached_geometry_keepouts": clouds.get_exclusion_bounds().size(), "atmosphere": tower._atmosphere.call("get_snapshot")})
				if repeat == 0 and case_name in ["all", "city_keepout_off", "hide_cloud_disabled", "legacy_proxy"]:
					await RenderingServer.frame_post_draw
					var image := get_viewport().get_texture().get_image()
					result["screenshot"] = view + "_" + case_name + ".png"
					image.save_png(out_dir.path_join(result["screenshot"]))
				report["runs"].append(result)
				_save()
				print("PERF_END view=%s repeat=%d case=%s frames=%d" % [view, repeat, case_name, result["samples"].size()])
	_apply_case("all")
	# 初始化扫描单独计时，不纳入帧率采样。
	var config := {"world_root": tower, "city_layout": tower._atmosphere.call("get_city_layout"), "main_tower_rect": TowerFloorStage3D.TOWER_SHELL_WORLD_RECT, "floor_99_y": -12.0, "enabled": true}
	report["initialization_microbench"] = {"cloud_configure_ms": [], "city_generate_ms": [], "city_keepout_texture_ms": [], "cloud_sync_materials_ms": [], "atmosphere_time_update_ms": []}
	for index in range(100):
		start = Time.get_ticks_usec()
		clouds.call("_sync_materials")
		report["initialization_microbench"]["cloud_sync_materials_ms"].append((Time.get_ticks_usec() - start) / 1000.0)
		start = Time.get_ticks_usec()
		tower._atmosphere.call("_apply_time_of_day")
		report["initialization_microbench"]["atmosphere_time_update_ms"].append((Time.get_ticks_usec() - start) / 1000.0)
	for index in range(3):
		start = Time.get_ticks_usec()
		clouds.configure(Color.WHITE, 1.0, config)
		report["initialization_microbench"]["cloud_configure_ms"].append((Time.get_ticks_usec() - start) / 1000.0)
		start = Time.get_ticks_usec()
		clouds.set_procedural_city_layout(city.get("placements"), city.get("parameters"))
		report["initialization_microbench"]["city_keepout_texture_ms"].append((Time.get_ticks_usec() - start) / 1000.0)
		var generator: Node3D = city.get_script().new()
		generator.set("parameters", city.get("parameters").duplicate(true))
		generator.set("keepouts", city.get("keepouts").duplicate(true))
		start = Time.get_ticks_usec()
		generator.call("_generate")
		report["initialization_microbench"]["city_generate_ms"].append((Time.get_ticks_usec() - start) / 1000.0)
		generator.free()
	_save()
	print("LANDSCAPE_PERF_COMPLETE")
	tower.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)

func _geometry_info(node: GeometryInstance3D) -> Dictionary:
	var aabb: AABB = node.get_aabb()
	var entry := {"path": str(node.get_path()), "aabb": var_to_str(aabb), "world_aabb": var_to_str(node.global_transform * aabb), "cast_shadow": node.cast_shadow, "visibility_range_end": node.visibility_range_end, "layers": node.layers, "material_override": str(node.material_override)}
	if node is MultiMeshInstance3D:
		entry["instance_count"] = node.multimesh.instance_count
		entry["custom_aabb"] = var_to_str(node.multimesh.custom_aabb)
		entry["mesh_class"] = node.multimesh.mesh.get_class()
		entry["material"] = str(node.multimesh.mesh.surface_get_material(0))
	return entry

func _apply_case(case_name: String) -> void:
	for node in original_visibility:
		node.visible = original_visibility[node]
	for node in shadow_values:
		node.cast_shadow = shadow_values[node]
	clouds.process_mode = Node.PROCESS_MODE_ALWAYS
	clouds.set_process(true)
	clouds.set("_flow_time", 0.0)
	clouds.set("_procedural_city_texture", city_texture)
	clouds.call("_sync_materials")
	if case_name in ["hide_new_city", "hide_new_and_ground", "hide_all_landscape", "legacy_proxy", "hide_new_cloud_disabled"]:
		city.visible = false
	if case_name in ["hide_ground", "hide_new_and_ground", "hide_all_landscape", "legacy_proxy"]:
		ground.visible = false
	if case_name == "hide_foundations":
		for node in foundation.get_children():
			if "FoundationBox" in str(node.name):
				node.visible = false
	if case_name in ["hide_all_landscape", "legacy_proxy"]:
		for node in foundation.get_children():
			if node is Node3D:
				node.visible = false
	if case_name in ["hide_cloud_draw", "hide_cloud_disabled", "hide_new_cloud_disabled"]:
		clouds.visible = false
	if case_name in ["hide_cloud_disabled", "hide_new_cloud_disabled"]:
		clouds.process_mode = Node.PROCESS_MODE_DISABLED
	if case_name == "hide_old_city":
		old_city.visible = false
	if case_name in ["city_keepout_off", "legacy_proxy"]:
		clouds.set("_procedural_city_texture", null)
		clouds.call("_sync_materials")
	if case_name == "ground_shadows_off":
		ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if case_name == "foundation_shadows_off":
		for node in foundation.get_children():
			if "FoundationBox" in str(node.name):
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _wait_seconds(seconds: float) -> void:
	var until := Time.get_ticks_usec() + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < until:
		await get_tree().process_frame

func _sample(seconds: float) -> Dictionary:
	var rows: Array = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec() - start < seconds * 1000000.0:
		await get_tree().process_frame
		var tick := Time.get_ticks_usec()
		var cpu_ms := -1.0
		var gpu_ms := -1.0
		if viewport_timing_supported:
			cpu_ms = RenderingServer.call("viewport_get_measured_render_time_cpu", get_viewport().get_viewport_rid())
			gpu_ms = RenderingServer.call("viewport_get_measured_render_time_gpu", get_viewport().get_viewport_rid())
		rows.append([(tick - previous) / 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_FPS), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), cpu_ms, gpu_ms, Engine.max_fps, get_window().has_focus(), get_window().mode == Window.MODE_MINIMIZED])
		previous = tick
	var profile: Array = RenderingServer.call("get_frame_profile") if profile_supported else []
	return {"duration_s": (Time.get_ticks_usec() - start) / 1000000.0, "columns": ["frame_ms", "time_process_ms", "time_physics_ms", "engine_fps", "drawcalls", "primitives", "render_objects", "viewport_render_cpu_ms", "viewport_render_gpu_ms", "max_fps", "focused", "minimized"], "samples": rows, "frame_profile": profile, "node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "object_count": Performance.get_monitor(Performance.OBJECT_COUNT), "vsync": DisplayServer.window_get_vsync_mode()}

func _save() -> void:
	var file := FileAccess.open(out_dir.path_join("measurement.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
