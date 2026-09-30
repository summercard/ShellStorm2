extends SceneTree
## Real-render evidence. Launcher must isolate APPDATA before Autoload startup.
var _benchmarks: Array[Dictionary] = []


func benchmark(clouds: Node3D, label: String, visible_clouds: bool, profile: String) -> void:
	clouds.visible = visible_clouds
	clouds.call("apply_performance_quality", profile)
	for _frame in range(25):
		await process_frame
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var calls: Array[float] = []
	for _frame in range(90):
		await process_frame
		await RenderingServer.frame_post_draw
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	gpu.sort()
	cpu.sort()
	calls.sort()
	var entry := {"label": label, "profile": profile, "clouds_enabled": visible_clouds,
		"gpu_median_ms": gpu[45], "gpu_p95_ms": gpu[85], "render_cpu_median_ms": cpu[45],
		"draw_calls_median": calls[45], "samples": 90}
	_benchmarks.append(entry)
	print("CLOUD_BENCHMARK ", entry)

func _initialize() -> void:
	call_deferred("run")


func capture(file_name: String) -> void:
	for _frame in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/outdoor_clouds/" + file_name)


func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://outputs/outdoor_clouds")
	root.size = Vector2i(1440, 900)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var tower := load("res://scenes/TowerDescent3D.tscn").instantiate() as Node3D
	tower.set("test_mode", true)
	tower.set("run_seed_override", 990095)
	root.add_child(tower)
	root.get_node("RuntimePerformanceManager").call("set_verification_frame_budget_override", 120)
	for _frame in range(20):
		await physics_frame
	var hud := tower.get_node("HUD") as CanvasLayer
	hud.hide()
	hud.process_mode = Node.PROCESS_MODE_DISABLED
	var time_manager := root.get_node("GameTimeManager")
	time_manager.call("set_clock_running", false)
	time_manager.call("set_elapsed_game_seconds", 19.0 * 3600.0, false)
	var clouds := tower.get_node("OutdoorClouds")
	clouds.set_process(false)
	clouds.call("apply_performance_quality", "high")
	var camera := Camera3D.new()
	tower.add_child(camera)
	camera.far = 900.0
	camera.fov = 58.0
	camera.current = true
	# The first capture uses the existing gameplay environment, unchanged.
	camera.position = Vector3(78, 37, 88)
	camera.look_at(Vector3(0, -18, -15))
	await capture("gameplay_environment.png")
	# Editor-style inspection uses a temporary environment copy so clearances are readable.
	var world_environment := tower.get_node("WorldEnvironment") as WorldEnvironment
	var inspection := world_environment.environment.duplicate() as Environment
	inspection.fog_enabled = false
	inspection.volumetric_fog_enabled = false
	inspection.glow_enabled = false
	inspection.adjustment_enabled = false
	inspection.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	inspection.tonemap_exposure = 1.0
	inspection.ambient_light_energy = 0.45
	world_environment.environment = inspection
	camera.position = Vector3(150, 105, 180)
	camera.look_at(Vector3(0, -20, -45))
	await capture("overview_t00.png")
	clouds.call("_process", 24.0)
	await capture("overview_t24.png")
	if not "--preview-only" in OS.get_cmdline_user_args():
		await benchmark(clouds, "overview_without_clouds_A", false, "high")
		await benchmark(clouds, "overview_clouds_high_A", true, "high")
		await benchmark(clouds, "overview_clouds_balanced", true, "balanced")
		await benchmark(clouds, "overview_clouds_low", true, "low")
		await benchmark(clouds, "overview_without_clouds_B", false, "high")
		await benchmark(clouds, "overview_clouds_high_B", true, "high")
	camera.position = Vector3(-130, 165, 95)
	camera.look_at(Vector3(0, -15, -90))
	await capture("bridge_and_towers.png")
	camera.position = Vector3(70, 15, 76)
	camera.look_at(Vector3(15, -20, 25))
	await capture("facade_clearance.png")
	camera.position = Vector3(-105, -2, 125)
	camera.look_at(Vector3(-45, -28, -10))
	await capture("cloud_top_oblique.png")
	if "--motion" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("res://outputs/outdoor_clouds/motion")
		for index in range(60):
			clouds.call("_process", 0.20)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://outputs/outdoor_clouds/motion/frame_%03d.png" % index)
			await process_frame
	# Ordinary player camera must also show the new clouds with the real environment.
	world_environment.environment = tower.get_node("TowerAtmosphere3D").get("_environment")
	var player := tower.get("player") as Node3D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = Vector3(48.0, 0.05, 39.0)
	if "--user-corner" in OS.get_cmdline_user_args():
		player.global_position = Vector3(-48.0, 0.05, -31.0)
		time_manager.call("set_elapsed_game_seconds", 17.7 * 3600.0, false)
		clouds.call("_process", 0.0)
	# Allow the parent camera-follow owner to settle before freezing its process.
	player.process_mode = Node.PROCESS_MODE_INHERIT
	for _frame in range(12):
		await physics_frame
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var player_camera := player.get("camera") as Camera3D
	player_camera.current = true
	clouds.visible = false
	await capture("player_without_clouds.png")
	clouds.visible = true
	await capture("player_rooftop.png")
	camera.current = true
	camera.position = Vector3(59, 8, 48)
	camera.look_at(Vector3(76, -36, 39))
	await capture("player_edge_lower_floors.png")
	var report := {"renderer": RenderingServer.get_current_rendering_method(), "device": RenderingServer.get_video_adapter_name(),
		"resolution": [1440, 900], "snapshot": clouds.call("get_presentation_snapshot"), "benchmarks": _benchmarks}
	var report_name := "performance.json" if not _benchmarks.is_empty() else "preview_snapshot.json"
	var file := FileAccess.open("res://outputs/outdoor_clouds/" + report_name, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	print("OUTDOOR_CLOUDS_RENDER ", clouds.call("get_presentation_snapshot"), " renderer=", RenderingServer.get_current_rendering_method())
	tower.queue_free()
	await process_frame
	quit()
