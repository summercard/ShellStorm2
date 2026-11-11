extends Node
## Run via scripts/profile_expedition_events.py (isolated user data before Autoload).
## Wall samples start before the event. GPU timers may lag by several frames.

var tower: TowerDescent3D
var rows: Array = []
var events: Array = []
var report := {}
var previous := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")

func _run() -> void:
	var level := OS.get_environment("PROFILE_LEVEL")
	var isolation := OS.get_environment("PROFILE_ROOT").replace("\\", "/").to_lower()
	var actual := OS.get_user_data_dir().replace("\\", "/").to_lower()
	if isolation.is_empty() or not actual.begins_with(isolation + "/") or DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	var tree := get_tree()
	tree.current_scene = null
	LevelSelect.selected_seed = 41021
	GameEntryFlow.request_gameplay_entry(GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT)
	if not GameDesignConfig.select_expedition_level(level):
		tree.quit(2)
		return
	var start := Time.get_ticks_msec()
	tree.change_scene_to_file("res://scenes/ExpeditionLoadingScreen.tscn")
	var loading_limit := OS.get_environment("PROFILE_LOADING_TIMEOUT_MS").to_int()
	if loading_limit <= 0:
		loading_limit = 240000
	while Time.get_ticks_msec() - start < loading_limit:
		await tree.process_frame
		tower = tree.current_scene as TowerDescent3D
		if tower and tower.has_meta("loading_room_warm_report") and tower.can_process() and tower.player and tower.player.can_process():
			break
	if not tower or not tower.can_process() or not tower.player or not tower.player.can_process() or not tower.has_meta("loading_room_warm_report") or tower.get_expedition_level_id() != level:
		tree.quit(3)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RuntimePerformanceManager.set_verification_frame_budget_override(10000)
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	report = {"level":level, "seed":tower.run_seed, "loading_ms":Time.get_ticks_msec()-start,
		"godot":Engine.get_version_info().get("string"), "quality":RuntimePerformanceManager.quality_profile,
		"warm_a":tower.get_meta("loading_warmup_report"), "warm_b":tower.get_meta("loading_room_warm_report"),
		"gpu":RenderingServer.get_video_adapter_name(), "renderer":RenderingServer.get_current_rendering_method(),
		"viewport":str(get_viewport().get_visible_rect().size), "rooms":tower._room_by_id.keys(),
		"persistent":tower._runtime_persistence_active, "user_dir":actual,
		"memory_after_loading":_memory_sample(),
		"columns":["phase","wall_ms","render_cpu_ms","render_gpu_ms","draw_calls","draw_pipelines","mesh_pipelines","surface_pipelines","canvas_pipelines"]}
	for i in 30:
		await tree.process_frame
	previous = Time.get_ticks_usec()
	await _frames("idle", 120)
	var current := tower._current_room_id
	var visited := [current]
	var hit_count := 0
	var door_count := 0
	for step in 4:
		var next := ""
		for neighbor in tower._room_neighbors.get(current, []):
			if not neighbor in visited and tower._room_by_id.has(neighbor):
				next = str(neighbor)
				break
		if next.is_empty():
			break
		visited.append(next)
		var room := tower._room_by_id[next] as DungeonRoom3D
		var label := "open/" + next
		var begin := Time.get_ticks_usec()
		tower.force_open_edge_for_test(current, next)
		_event(label, begin, {"alive":tower._alive_by_room.get(next, 0)})
		door_count += 1
		await _frames(label, 15)
		label = "enter/" + next
		begin = Time.get_ticks_usec()
		var from := room.global_position + Vector3.UP * 4.0
		var ray := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 10.0, 1)
		ray.exclude = [tower.player.get_rid()]
		var hit := room.get_world_3d().direct_space_state.intersect_ray(ray)
		tower.player.global_position = (hit.get("position", room.global_position) as Vector3) + Vector3.UP * 0.15
		tower.player.velocity = Vector3.ZERO
		tower.force_enter_room_for_test(next)
		_event(label, begin)
		await _frames(label, 35)
		for value in tower._enemy_nodes_by_room.get(next, []):
			if hit_count >= 3:
				break
			if not is_instance_valid(value):
				continue
			var enemy := value as Enemy3D
			if enemy == null or enemy.current_hp <= 3:
				continue
			for i in 3:
				var shot := Projectile3D.new()
				shot.configure({"damage":1, "shooter":tower.player, "direction":Vector3.FORWARD})
				tower.add_child(shot)
				shot.global_position = enemy.global_position + Vector3(0, 0.7, 0.4)
				var timing := {}
				shot.hit_confirmed.connect(func(_target, _damage, _critical):
					timing["confirmed_usec"] = Time.get_ticks_usec())
				var hp := enemy.current_hp
				begin = Time.get_ticks_usec()
				shot._hit_target(enemy, {"normal":Vector3.BACK})
				label = "hit/" + str(i)
				_event(label, begin, {"hp_loss":hp-enemy.current_hp, "kind":enemy.enemy_kind,
					"through_damage_ms":(int(timing.get("confirmed_usec", begin))-begin)/1000.0})
				hit_count += 1
				await _frames(label, 15)
			# Component probes are separate from the three complete hit windows.
			for j in 3:
				_time_call("anchor", enemy.hit_effect_anchor.bind(enemy.global_position + Vector3.UP, Vector3.BACK))
				_time_call("aggro", enemy.notify_attacked_by.bind(tower.player))
				_time_call("flash", enemy.avatar.flash_hit)
				_time_call("health_bar", enemy._redraw_overhead_health_bar)
				_time_call("number", enemy._spawn_damage_number.bind(1, false))
				_time_call("sound", AudioManager.play_enemy_hit_sfx)
				_time_call("impact", VfxPool.acquire.bind(VfxPool3D.FX01_GOO_HIT, enemy.global_position, Color.WHITE, 1.0))
				await _frames("component_hit", 12)
			break
		current = next
		if step == 0:
			for i in 2:
				label = "chest/" + str(i)
				var slot := tower.get_node_or_null("RewardChestWarmVisuals/normal")
				var warm_model: Node = slot.get_child(0) if slot and slot.get_child_count() > 0 else null
				begin = Time.get_ticks_usec()
				var chest := room.spawn_runtime_chest({"id":"profile_%d" % i}, Vector2(i*2+1, 1))
				_event(label, begin, {"created":chest != null, "used_warm_model":is_instance_valid(warm_model) and warm_model.get_parent() == chest})
				await _frames(label, 40)
	if door_count > 0:
		var last_room := tower._room_by_id[current] as DungeonRoom3D
		for i in 3:
			_time_call("blockers", last_room._collect_spawn_blockers)
			_time_call("checkpoint", BaseManager.flush_runtime_checkpoint.bind("profile_sample"))
			await _frames("component_room", 12)
		await _sample_controlled_encounter(last_room)
	report["events"] = events
	report["samples"] = rows
	report["memory_after_route"] = _memory_sample()
	var file := FileAccess.open(OS.get_environment("PROFILE_OUTPUT"), FileAccess.WRITE)
	if file == null:
		tree.quit(4)
		return
	file.store_string(JSON.stringify(report))
	file.close()
	print("EXPEDITION_PROFILE level=", level, " doors=", door_count, " hits=", hit_count, " frames=", rows.size())
	tree.quit(0 if door_count > 0 else 5)

func _memory_sample() -> Dictionary:
	return {"engine_static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),
		"video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)}

func _event(label: String, begin: int, extra := {}) -> void:
	events.append({"phase":label,"sync_ms":(Time.get_ticks_usec()-begin)/1000.0,"details":extra})

## An additional isolated encounter after the measured route, including on peaceful routes.
func _sample_controlled_encounter(room: DungeonRoom3D) -> void:
	# Use an explicit supported world anchor even in halls that have no encounter slots.
	var origin := tower.player.global_position + Vector3(1.8, 2.5, 0)
	var ground_query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 8.0, 1)
	ground_query.exclude = [tower.player.get_rid()]
	var support := room.get_world_3d().direct_space_state.intersect_ray(ground_query)
	if support.is_empty():
		_event("fixture_no_support", Time.get_ticks_usec())
		return
	var configs: Array[Dictionary] = [{"enemy_type":"melee_chaser", "persistent_id":"profile_target",
		"narrative_spawned":true, "spawn_position":support.position + Vector3.UP * 0.05}]
	var begin := Time.get_ticks_usec()
	var spawned := tower._spawn_enemy_batch(room, configs, true)
	_event("fixture_spawn", begin, {"count":spawned,"room":room.room_id})
	await _frames("fixture_spawn", 24)
	if spawned != 1:
		return
	var enemies: Array = tower._enemy_nodes_by_room.get(room.room_id, [])
	if enemies.is_empty() or not is_instance_valid(enemies.back()):
		return
	var enemy := enemies.back() as Enemy3D
	var pool := get_tree().get_first_node_in_group("projectile_pool_3d") as ProjectilePool3D
	if enemy == null or pool == null:
		return
	for index in 3:
		if not is_instance_valid(enemy) or enemy.current_hp <= 1:
			break
		var label := "fixture_flight/%d" % index
		var outcome := {"confirmed":false, "hp_before":enemy.current_hp}
		var observer := func(target, _damage, _critical): outcome["confirmed"] = target == enemy
		begin = Time.get_ticks_usec()
		var shot := pool.acquire({"damage":1, "speed":22.0, "direction":Vector3.FORWARD, "shooter":tower.player},
			enemy.global_position + Vector3(0, 0.65, 0.85))
		shot.hit_confirmed.connect(observer)
		_event(label, begin, outcome)
		await _frames(label, 24)
		if is_instance_valid(shot) and shot.hit_confirmed.is_connected(observer):
			shot.hit_confirmed.disconnect(observer)
		if is_instance_valid(enemy):
			outcome["hp_after"] = enemy.current_hp

func _time_call(label: String, operation: Callable) -> void:
	var begin := Time.get_ticks_usec()
	operation.call()
	_event(label, begin)

func _frames(label: String, count: int) -> void:
	var rid := get_viewport().get_viewport_rid()
	for i in count:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		rows.append([label, (now-previous)/1000.0, RenderingServer.viewport_get_measured_render_time_cpu(rid),
			RenderingServer.viewport_get_measured_render_time_gpu(rid), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW), Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH),
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE), Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS)])
		previous = now
