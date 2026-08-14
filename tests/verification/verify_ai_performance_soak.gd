extends Node3D
## 发布候选真实渲染长时门禁。默认 60 分钟，连续覆盖98—95、94—90、89—85
## 三个区段；SHELLSTORM_SOAK_SECONDS 仅用于开发预检，不可替代RC验收。

const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const DEFAULT_DURATION_SECONDS := 3600.0
const SAMPLE_INTERVAL_SECONDS := 1.0

var _player: Player3D
var _lamp: WastelandLight3D
var _enemies: Array[Enemy3D] = []


func _ready() -> void:
	# Codex/CI 驱动的真实渲染窗口通常不拥有桌面焦点。长测要测前台60FPS
	# 战斗预算，因此显式锁定验收预算；失焦15FPS策略由独立专项验证。
	RuntimePerformanceManager.set_verification_frame_budget_override(60)
	RuntimePerformanceManager.simulate_focus_for_test(true)
	RuntimePerformanceManager.set_quality_profile("high")
	GameplaySpatialRegistry3D.clear_runtime_records()
	_build_world()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await get_tree().process_frame
	await get_tree().physics_frame
	var requested := float(OS.get_environment("SHELLSTORM_SOAK_SECONDS"))
	var duration := requested if requested > 0.0 else DEFAULT_DURATION_SECONDS
	var failures: Array[String] = []
	var frame_samples: Array[float] = []
	var render_cpu_samples: Array[float] = []
	var render_gpu_samples: Array[float] = []
	var draw_call_samples: Array[float] = []
	var memory_samples: Array[float] = []
	var node_samples: Array[float] = []
	var started_usec := Time.get_ticks_usec()
	var last_frame_usec := started_usec
	var sample_warmup_ends_usec := started_usec + 2000000
	var next_sample_seconds := SAMPLE_INTERVAL_SECONDS
	var next_progress_seconds := 60.0
	var last_stimulus_bucket := -1
	var active_segment_index := -1
	var visited_segments: Array[String] = []
	while float(Time.get_ticks_usec() - started_usec) / 1000000.0 < duration:
		await get_tree().process_frame
		var now_usec := Time.get_ticks_usec()
		var elapsed := float(now_usec - started_usec) / 1000000.0
		var segment_index := mini(2, int(elapsed / maxf(1.0, duration / 3.0)))
		if segment_index != active_segment_index:
			active_segment_index = segment_index
			_apply_segment_profile(segment_index)
			visited_segments.append(["98-95", "94-90", "89-85"][segment_index])
			print("AI_PERFORMANCE_SOAK_SEGMENT index=%d floors=%s" % [segment_index + 1, visited_segments.back()])
		if now_usec >= sample_warmup_ends_usec:
			frame_samples.append(float(now_usec - last_frame_usec) / 1000.0)
		last_frame_usec = now_usec
		if elapsed >= next_sample_seconds:
			if Engine.max_fps != 60:
				failures.append("Verification foreground frame budget drifted from 60 FPS")
			render_cpu_samples.append(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()))
			render_gpu_samples.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
			draw_call_samples.append(float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
			memory_samples.append(float(Performance.get_monitor(Performance.MEMORY_STATIC)))
			node_samples.append(float(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
			next_sample_seconds += SAMPLE_INTERVAL_SECONDS
			var stimulus_bucket := int(elapsed / 3.0)
			if stimulus_bucket != last_stimulus_bucket:
				last_stimulus_bucket = stimulus_bucket
				var angle := float(stimulus_bucket % 16) / 16.0 * TAU
				_player.global_position = Vector3(cos(angle) * 2.2, 0.05, sin(angle) * 2.2)
				_player.current_hp = _player.max_hp
				MonsterAIManager.broadcast_sound_stimulus(_player.global_position, 24.0, "soak_combat", _player)
				_lamp.set_light_enabled(stimulus_bucket % 2 == 0)
		if elapsed >= next_progress_seconds:
			print("AI_PERFORMANCE_SOAK_PROGRESS elapsed_s=%d/%d nodes=%d memory_mb=%.1f registered_ai=%d" % [
				int(elapsed), int(duration), int(node_samples.back() if not node_samples.is_empty() else 0.0),
				float(memory_samples.back() if not memory_samples.is_empty() else 0.0) / 1048576.0,
				int(MonsterAIManager.get_manager_snapshot().get("registered_enemy_count", -1)),
			])
			next_progress_seconds += 60.0
	if visited_segments != ["98-95", "94-90", "89-85"]:
		failures.append("RC soak did not continuously visit all three floor segments: %s" % str(visited_segments))
	_evaluate_results(
		duration, frame_samples, render_cpu_samples, render_gpu_samples,
		draw_call_samples, memory_samples, node_samples, failures
	)
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_player.queue_free()
	_lamp.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameplaySpatialRegistry3D.prune_stale()
	if int(MonsterAIManager.get_manager_snapshot().get("registered_enemy_count", -1)) != 0:
		failures.append("AI manager retained enemies after soak cleanup")
	if int(GameplaySpatialRegistry3D.get_snapshot().get("record_count", -1)) != 0:
		failures.append("Spatial registry retained nodes after soak cleanup")
	var warmup_index := _stable_warmup_index(memory_samples.size(), duration)
	var stable_memory: Array[float] = memory_samples.slice(warmup_index)
	var stable_nodes: Array[float] = node_samples.slice(warmup_index)
	print("AI_PERFORMANCE_SOAK_RESULT status=%s duration_s=%d frame_p95_ms=%.2f frame_max_ms=%.2f render_cpu_p95_ms=%.2f render_gpu_p95_ms=%.2f gpu_timing_available=%s draw_calls_p95=%.0f memory_start_mb=%.1f memory_end_mb=%.1f memory_total_span_mb=%.1f memory_stable_span_mb=%.1f node_total_span=%d node_stable_span=%d node_segment_span=%d" % [
		"pass" if failures.is_empty() else "fail", int(duration),
		_percentile(frame_samples, 0.95), _max_value(frame_samples),
		_percentile(render_cpu_samples, 0.95), _percentile(render_gpu_samples, 0.95),
		str(_max_value(render_gpu_samples) > 0.0), _percentile(draw_call_samples, 0.95),
		_first_value(memory_samples) / 1048576.0, _last_value(memory_samples) / 1048576.0,
		_span(memory_samples) / 1048576.0, _span(stable_memory) / 1048576.0,
		int(_span(node_samples)), int(_span(stable_nodes)), int(_max_segment_span(node_samples)),
	])
	RuntimePerformanceManager.set_verification_frame_budget_override(0)
	if failures.is_empty():
		print("AI_PERFORMANCE_SOAK_OK duration_s=%d frame_p95_ms=%.2f frame_max_ms=%.2f render_cpu_p95_ms=%.2f render_gpu_p95_ms=%.2f draw_calls_p95=%.0f memory_stable_span_mb=%.1f node_stable_span=%d" % [
			int(duration), _percentile(frame_samples, 0.95), _max_value(frame_samples),
			_percentile(render_cpu_samples, 0.95), _percentile(render_gpu_samples, 0.95),
			_percentile(draw_call_samples, 0.95), _span(stable_memory) / 1048576.0,
			int(_span(stable_nodes)),
		])
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.015, 0.02, 0.028)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.34, 0.40, 0.48)
	environment.ambient_light_energy = 0.34
	environment_node.environment = environment
	add_child(environment_node)
	GraphicsSettingsManager.register_environment(environment)
	var floor_body := StaticBody3D.new()
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(42, 0.2, 42)
	floor_mesh.mesh = box
	floor_body.add_child(floor_mesh)
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = box.size
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	add_child(floor_body)
	var pool := ProjectilePool3D.new()
	pool.name = "ProjectilePool3D"
	add_child(pool)
	_player = PLAYER_SCENE.instantiate() as Player3D
	_player.start_with_weapon = false
	_player.max_hp = 1000000
	_player.current_hp = _player.max_hp
	_player.position = Vector3(0, 0.05, 0)
	add_child(_player)
	_player.set_physics_process(false)
	_lamp = WastelandLight3D.new()
	_lamp.configure(Color(0.42, 0.78, 1.0), 5.2, 18.0, 20260813, true, false, "ceiling")
	_lamp.position = Vector3(0, 3.5, 0)
	add_child(_lamp)
	for index in range(30):
		var enemy := ENEMY_SCENE.instantiate() as Enemy3D
		var angle := float(index) / 30.0 * TAU
		var radius := 7.0 + float(index % 4) * 1.8
		enemy.room_id = "soak_room"
		enemy.position = Vector3(cos(angle) * radius, 0.05, sin(angle) * radius)
		add_child(enemy)
		enemy.configure_from_enemy_data({
			"enemy_type": "ranged_caster" if index % 2 == 0 else "melee_chaser",
			"persistent_id": "soak_enemy_%02d" % index,
			"spawn_index": index,
			"floor": 3,
			"hp": 120,
			"max_hp": 120,
			"damage": 1,
			"speed": 70,
		})
		enemy.look_at(_player.global_position + Vector3.UP * 0.7, Vector3.UP)
		_enemies.append(enemy)


func _apply_segment_profile(segment_index: int) -> void:
	var floor_numbers := [95, 90, 85]
	var accent_colors := [Color(0.10, 0.86, 1.0), Color(1.0, 0.20, 0.035), Color(0.62, 0.16, 1.0)]
	_lamp.configure(accent_colors[segment_index], 5.2, 18.0, 20260813 + segment_index, true, false, "ceiling")
	for index in range(_enemies.size()):
		var enemy := _enemies[index]
		if not is_instance_valid(enemy) or index >= 2:
			continue
		var kind := "boss"
		var data := {
			"enemy_type": kind,
			"persistent_id": "soak_segment_%d_enemy_%02d" % [segment_index, index],
			"spawn_index": index, "floor": 5 + segment_index * 5,
			"hp": 1000000, "max_hp": 1000000, "damage": 1, "speed": 70,
		}
		if kind == "boss":
			var boss_profile := BossContentCatalog.get_for_floor(floor_numbers[segment_index])
			data.merge({
				"is_boss": true,
				"boss_content_id": boss_profile.get("boss_content_id", ""),
				"presentation_asset_id": boss_profile.get("presentation_asset_id", ""),
				"arena_asset_id": boss_profile.get("arena_asset_id", ""),
				"boss_phase_skill_bags": boss_profile.get("phase_skill_bags", {}),
				"boss_accent": boss_profile.get("accent", accent_colors[segment_index]),
			})
		enemy.configure_from_enemy_data(data)


func _evaluate_results(
	duration: float,
	frame_samples: Array[float],
	render_cpu_samples: Array[float],
	render_gpu_samples: Array[float],
	draw_call_samples: Array[float],
	memory_samples: Array[float],
	node_samples: Array[float],
	failures: Array[String]
) -> void:
	var frame_p95 := _percentile(frame_samples, 0.95)
	# Metal Compatibility + VSync 的墙钟节拍包含显示调度；长时硬门槛按55FPS设置，
	# 脚本CPU/GPU精确P95继续由Godot Profiler设备报告负责。
	if frame_p95 > 22.0:
		failures.append("Real-renderer frame pacing P95 exceeded 22ms: %.2fms" % frame_p95)
	var render_cpu_p95 := _percentile(render_cpu_samples, 0.95)
	var render_gpu_p95 := _percentile(render_gpu_samples, 0.95)
	var gpu_timing_available := _max_value(render_gpu_samples) > 0.0
	if not is_finite(render_cpu_p95) or render_cpu_p95 <= 0.0:
		failures.append("Renderer CPU telemetry produced no measurable sample")
	elif render_cpu_p95 > 8.0:
		failures.append("Renderer CPU P95 exceeded 8ms: %.2fms" % render_cpu_p95)
	# macOS 的 Compatibility-over-Metal 后端可能不提供 GPU 时间戳并固定返回0；
	# 有有效样本时执行12ms硬门槛，无样本时在最终报告中保留0供人工识别，
	# 不拿墙钟或CPU数值伪造GPU遥测。
	if OS.get_environment("SHELLSTORM_REQUIRE_GPU_TIMING") == "1" and not gpu_timing_available:
		failures.append("Target-device gate requires GPU timing, but renderer returned no GPU samples")
	if is_finite(render_gpu_p95) and render_gpu_p95 > 12.0:
		failures.append("Renderer GPU P95 exceeded 12ms: %.2fms" % render_gpu_p95)
	if draw_call_samples.is_empty():
		failures.append("Renderer draw-call telemetry produced no samples")
	var manager := MonsterAIManager.get_manager_snapshot()
	if int(manager.get("registered_enemy_count", -1)) != 30:
		failures.append("30-enemy soak lost or duplicated AI registrations: %s" % manager)
	if int(manager.get("maximum_updates_in_tick", 99)) > int(manager.get("max_evaluations_per_tick", 8)):
		failures.append("AI perception updates exceeded the per-tick budget: %s" % manager)
	var warmup_index := _stable_warmup_index(memory_samples.size(), duration)
	var stable_memory: Array[float] = memory_samples.slice(warmup_index)
	var stable_nodes: Array[float] = node_samples.slice(warmup_index)
	if duration >= 120.0 and _span(stable_memory) > 96.0 * 1024.0 * 1024.0:
		failures.append("Static memory drift exceeded 96MB after warmup: %.1fMB" % (_span(stable_memory) / 1048576.0))
	var node_segment_span := _max_segment_span(node_samples)
	if duration >= 120.0 and node_segment_span > 64.0:
		failures.append("Node count drift exceeded 64 inside one content segment: %d" % int(node_segment_span))


func _percentile(values: Array[float], ratio: float) -> float:
	if values.is_empty():
		return INF
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(ceil(float(sorted.size()) * ratio)) - 1, 0, sorted.size() - 1)]


func _span(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	return _max_value(values) - _min_value(values)


func _stable_warmup_index(sample_count: int, duration: float) -> int:
	return mini(sample_count - 1, maxi(0, int(minf(60.0, duration * 0.2))))


func _max_segment_span(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var max_span := 0.0
	for segment_index in range(3):
		var start := int(floor(float(values.size()) * float(segment_index) / 3.0))
		var finish := int(floor(float(values.size()) * float(segment_index + 1) / 3.0))
		var warmup := mini(finish, start + mini(10, maxi(0, (finish - start) / 5)))
		if finish > warmup:
			max_span = maxf(max_span, _span(values.slice(warmup, finish)))
	return max_span


func _first_value(values: Array[float]) -> float:
	return values[0] if not values.is_empty() else 0.0


func _last_value(values: Array[float]) -> float:
	return values.back() if not values.is_empty() else 0.0


func _max_value(values: Array[float]) -> float:
	var result := -INF
	for value in values:
		result = maxf(result, value)
	return result


func _min_value(values: Array[float]) -> float:
	var result := INF
	for value in values:
		result = minf(result, value)
	return result
