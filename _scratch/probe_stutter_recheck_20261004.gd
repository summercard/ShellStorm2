extends Node

const OUTPUT := "res://outputs/stutter_recheck_20261004.json"
var tower: Node3D
var chunks: Node3D
var clouds: Node3D
var player: Node3D
var events: Array[Dictionary] = []
var sample_started := false
var start_usec := 0
var chunk_ids: Array[int] = []
var mesh_ids: Array[int] = []
var samples: Array[Dictionary] = []
var phases: Array[Dictionary] = []
var changes := 0
var phase_name := "boot"
var save_events: Array[Dictionary] = []
var last_revision := -1
var direct_save_ms: Array[float] = []
var save_breakdown: Array[Dictionary] = []

func _ready() -> void:
	_run.call_deferred()

func _event(node: Node, kind: String) -> void:
	if sample_started and (node == chunks or chunks.is_ancestor_of(node)):
		events.append({"time_ms": (Time.get_ticks_usec() - start_usec) / 1000.0, "kind": kind, "node": str(node.name)})

func _ids(root: Node, meshes: bool) -> Array[int]:
	var result: Array[int] = []
	var nodes := root.find_children("*", "MeshInstance3D", true, false) if meshes else root.get_children()
	for value in nodes:
		result.append(value.get_instance_id())
	return result

func _state() -> Dictionary:
	var room_transitions := 0
	var detail_count := 0
	var shell_count := 0
	var rooms: Array = tower.get("_rooms")
	for room in rooms:
		room_transitions += int(room.get("_stream_transition_count"))
		detail_count += int(bool(room.get("_detail_built")))
		shell_count += int(bool(room.get("_shell_built")))
	return {"room": str(tower.get("_current_room_id")), "room_count": rooms.size(), "shell_count": shell_count, "detail_count": detail_count, "stream_transitions": room_transitions, "floor_visibility_applies": int(tower.get("_floor_visibility_apply_count")), "resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)), "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "save_dirty": bool(BaseManager.get("_runtime_checkpoint_dirty")), "save_reason": str(BaseManager.get("_pending_runtime_reason")), "profile_revision": BaseManager.data.save_revision, "profile_reason": BaseManager.data.last_save_reason, "clock_flush_elapsed": GameTimeManager._profile_flush_elapsed, "player_position": str(player.global_position), "physical_location": tower.call("get_physical_location_snapshot")}

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	RuntimePerformanceManager.set_verification_frame_budget_override(60)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_window().size = Vector2i(1280, 720)
	print("ROOFTOP_PROBE loading")
	var t0 := Time.get_ticks_usec()
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var t1 := Time.get_ticks_usec()
	print("ROOFTOP_PROBE loaded_ms=", (t1 - t0) / 1000.0)
	tower = packed.instantiate() as Node3D
	tower.set("test_mode", true)
	tower.set("run_seed_override", 990095)
	var t2 := Time.get_ticks_usec()
	add_child(tower)
	var t3 := Time.get_ticks_usec()
	chunks = tower.get_node("Blocks/Rooftop/CrossTowerRoute/LandscapeFoundation/AuthoredCityChunks")
	clouds = tower.get_node("OutdoorClouds")
	player = tower.get("player") as Node3D
	player.set_physics_process(false)
	player.set("input_locked", true)
	var y := player.global_position.y
	get_tree().node_added.connect(func(node: Node): _event(node, "added"))
	get_tree().node_removed.connect(func(node: Node): _event(node, "removed"))
	chunk_ids = _ids(chunks, false)
	mesh_ids = _ids(chunks, true)
	for i in range(120):
		await get_tree().process_frame
	var camera := get_viewport().get_camera_3d()
	var initial_state := _state()
	start_usec = Time.get_ticks_usec()
	sample_started = true
	last_revision = BaseManager.data.save_revision
	var environments := tower.find_children("*", "WorldEnvironment", true, false)
	var env: Environment = (environments[0] as WorldEnvironment).environment
	var sdfgi_original := env.sdfgi_enabled
	var sequence := ["baseline_a", "periodic_save_suppressed_a", "no_cloud", "both_suppressed", "baseline_b", "periodic_save_suppressed_b"]
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	for phase: String in sequence:
		phase_name = phase
		chunks.visible = phase != "small_buildings_hidden"
		clouds.visible = phase not in ["no_cloud", "both_suppressed"]
		print("ROOFTOP_PROBE phase=", phase)
		env.sdfgi_enabled = sdfgi_original and phase != "sdfgi_disabled"
		GameTimeManager._profile_flush_elapsed = 0.0
		var initial := _state()
		var phase_start := Time.get_ticks_usec()
		var prev := phase_start
		var last_state := initial
		var local_samples: Array[float] = []
		var idx := 0
		while (Time.get_ticks_usec() - phase_start) < 12000000:
			if phase.begins_with("periodic_save_suppressed") or phase == "both_suppressed":
				GameTimeManager._profile_flush_elapsed = 0.0
			var elapsed := (Time.get_ticks_usec() - phase_start) / 1000000.0
			# Every phase repeats the same rooftop path; no doors, inventory or floor transitions.
			player.global_position = Vector3(sin(elapsed * 0.85) * 25.0, y, cos(elapsed * 0.85) * 20.0 + 5.0)
			player.set("velocity", Vector3(cos(elapsed * 0.85) * 21.25, 0, -sin(elapsed * 0.85) * 17.0))
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			var wall_ms := (now - prev) / 1000.0
			prev = now
			var revision := BaseManager.data.save_revision
			if revision != last_revision:
				save_events.append({"phase": phase, "time_ms": (now - start_usec) / 1000.0, "frame_ms": wall_ms, "revision": revision, "reason": BaseManager.data.last_save_reason, "previous_revision": last_revision})
				last_revision = revision
			# Exclude first second of each visibility toggle from steady state metrics.
			if elapsed > 1.0:
				local_samples.append(wall_ms)
				var entry := {"phase": phase, "process_frame": Engine.get_process_frames(), "physics_frame": Engine.get_physics_frames(), "time_ms": (now - start_usec) / 1000.0, "frame_ms": wall_ms, "gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()), "render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()), "cpu_process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, "cpu_physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)}
				if wall_ms > 25.0 or idx % 30 == 0:
					var state := _state()
					entry["state"] = state
					entry["state_changed"] = state != last_state
					last_state = state
				samples.append(entry)
			if idx % 120 == 0:
				if chunk_ids != _ids(chunks, false) or mesh_ids != _ids(chunks, true):
					changes += 1
			idx += 1
		local_samples.sort()
		var total := 0.0
		var over25 := 0
		var over50 := 0
		for value in local_samples:
			total += value
			over25 += int(value > 25.0)
			over50 += int(value > 50.0)
		phases.append({"name": phase, "frames": local_samples.size(), "mean_ms": total / maxf(1.0, local_samples.size()), "p95_ms": local_samples[int(local_samples.size() * 0.95)], "p99_ms": local_samples[int(local_samples.size() * 0.99)], "max_ms": local_samples.back(), "over25": over25, "over50": over50, "start_state": initial, "end_state": _state()})
	sample_started = false
	for i in range(5):
		var save_start := Time.get_ticks_usec()
		GameTimeManager.flush_to_profile("rooftop_probe_direct_timing")
		direct_save_ms.append((Time.get_ticks_usec() - save_start) / 1000.0)
		await get_tree().process_frame
	for i in range(8):
		save_breakdown.append(_measure_save_parts())
	var result := {"save_breakdown": save_breakdown, "cloud_snapshot": clouds.call("get_presentation_snapshot"), "cloud_cache": clouds.call("get_procedural_city_cache_snapshot"), "main_towers_only": clouds.get("main_towers_only"), "renderer": RenderingServer.get_current_rendering_method(), "resolution": [1280, 720], "max_fps": Engine.max_fps, "camera": str(camera.global_position), "user_data_dir": OS.get_user_data_dir(), "profile_save_path": ProjectSettings.globalize_path(BaseManager.save_path), "test_limitations": "外部APPDATA隔离真实档案，test_mode仅关闭局内检查点；玩家沿固定楼顶路径移动，不复刻用户存档、真实物理、交互或后台程序；帧时间含60fps限速，不代表无上限FPS",  "load_ms": (t1 - t0) / 1000.0, "instantiate_ms": (t2 - t1) / 1000.0, "enter_tree_ms": (t3 - t2) / 1000.0, "chunk_count": chunk_ids.size(), "building_mesh_count": mesh_ids.size(), "chunk_identity_changes": changes, "chunk_events": events, "save_events": save_events, "direct_save_ms": direct_save_ms, "initial_state": initial_state, "phases": phases, "samples": samples, "static_residency_passed": changes == 0 and events.is_empty() and chunk_ids.size() == 8 and mesh_ids.size() == 157}
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  ") + "\n")
	file.close()
	print("ROOFTOP_PROBE_STATIC_RESIDENCY ", result["static_residency_passed"])
	tower.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if result["static_residency_passed"] else 1)

func _measure_save_parts() -> Dictionary:
	var row: Dictionary = {}
	var t := Time.get_ticks_usec()
	var disk := BaseManager._read_disk_revision()
	row["read_revision_ms"] = (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	GameTimeManager.flush_to_profile("recheck_full_save")
	row["full_flush_ms"] = (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	var payload := BaseManager.data._to_dict()
	row["snapshot_ms"] = (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	var envelope := ProfileSaveService.build_envelope(payload, BaseManager.data.save_revision, "recheck_parts")
	row["build_envelope_ms"] = (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	var checksum := ProfileSaveService.checksum_payload(payload)
	row["one_checksum_ms"] = (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	var encoded := JSON.stringify(envelope, "\t")
	row["stringify_ms"] = (Time.get_ticks_usec() - t) / 1000.0
	row["bytes"] = encoded.to_utf8_buffer().size()
	t = Time.get_ticks_usec()
	var success := AtomicJsonStore.save_dictionary("user://diagnostic_parts.json", envelope)
	row["atomic_write_ms"] = (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	var stored: Variant = AtomicJsonStore.load_dictionary("user://diagnostic_parts.json")
	row["read_parse_ms"] = (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	var unpacked := ProfileSaveService.unpack(stored)
	row["unpack_validate_ms"] = (Time.get_ticks_usec() - t) / 1000.0
	row["valid"] = success and bool(unpacked.get("success", false))
	row["disk_revision"] = disk
	row["checksum"] = checksum
	return row
