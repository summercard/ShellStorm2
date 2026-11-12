extends Node
## Run via scripts/profile_expedition_events.py (isolated user data before Autoload).
## Wall samples start before the event. GPU timers may lag by several frames.

var tower: Dungeon3D
var rows: Array = []
var events: Array = []
var report := {}
var previous := 0
var pre_draw_usec := 0
var post_draw_usec := 0
var last_physics_usec := 0

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
	var seed_text := OS.get_environment("PROFILE_SEED")
	var requested_seed := 41021 if seed_text.is_empty() else seed_text.to_int()
	LevelSelect.selected_seed = requested_seed
	var destination := ""
	var start := Time.get_ticks_msec()
	if OS.get_environment("PROFILE_GATE") == "1":
		tree.change_scene_to_file(GameDesignConfig.BASE_SCENE_3D)
		await tree.scene_changed
		for entrance: DungeonEntrance3D in tree.get_nodes_in_group("dungeon_entrance"):
			if entrance.entrance_id == level:
				destination = entrance.target_scene_path
				entrance.activated.emit(entrance)
				# BaseWorld handles the signal deferred and rolls a seed before scene change.
				await tree.scene_changed
				LevelSelect.selected_seed = requested_seed
				break
		if destination.is_empty():
			tree.quit(2)
			return
	else:
		GameEntryFlow.request_gameplay_entry(GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT)
		if not GameDesignConfig.select_expedition_level(level):
			tree.quit(2)
			return
		destination = GameDesignConfig.expedition_level_scene(level)
		tree.change_scene_to_file("res://scenes/ExpeditionLoadingScreen.tscn")
	var loading_limit := OS.get_environment("PROFILE_LOADING_TIMEOUT_MS").to_int()
	if loading_limit <= 0:
		loading_limit = 240000
	while Time.get_ticks_msec() - start < loading_limit:
		await tree.process_frame
		tower = tree.current_scene as Dungeon3D
		if tower and tower.has_meta("loading_room_warm_report") and tower.can_process() and tower.player and tower.player.can_process():
			break
	if not tower or not tower.can_process() or not tower.player or not tower.player.can_process() or not tower.has_meta("loading_room_warm_report") or tower.scene_file_path != destination or tower.run_seed != requested_seed:
		tree.quit(3)
		return
	# The entry ceremony may hold player input for several seconds after process resumes.
	var released := Time.get_ticks_msec()
	var playable_frames := 0
	while Time.get_ticks_msec() - released < 30000 and playable_frames < 3:
		await tree.process_frame
		if tower.player.can_process() and not tower.player.input_locked and not NarrativeDirector.is_playing() and not IrisTransition.is_covered():
			playable_frames += 1
		else:
			playable_frames = 0
	if playable_frames < 3:
		printerr("PROFILE_INPUT_NOT_RELEASED ", level)
		tree.quit(8)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RuntimePerformanceManager.set_verification_frame_budget_override(10000)
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	report = {"level":level, "seed":tower.run_seed, "loading_ms":released-start, "input_wait_ms":Time.get_ticks_msec()-released,
		"godot":Engine.get_version_info().get("string"), "quality":RuntimePerformanceManager.quality_profile,
		"warm_a":tower.get_meta("loading_warmup_report"), "warm_b":tower.get_meta("loading_room_warm_report"),
		"gpu":RenderingServer.get_video_adapter_name(), "renderer":RenderingServer.get_current_rendering_method(),
		"viewport":str(get_viewport().get_visible_rect().size), "rooms":tower._room_by_id.keys(),
		"destination":destination, "combat_enabled":tower.player.combat_enabled, "input_locked":tower.player.input_locked,
		"persistent":tower._runtime_persistence_active, "user_dir":actual,
		"memory_after_loading":_memory_sample(),
		"columns":["phase","wall_ms","render_cpu_ms","render_gpu_ms","draw_calls","draw_pipelines","mesh_pipelines","surface_pipelines","canvas_pipelines","nodes","resources","physics_ms","to_pre_draw_ms","draw_signal_span_ms","after_draw_ms","last_physics_offset_ms","navigation_ms"]}
	RenderingServer.frame_pre_draw.connect(func(): pre_draw_usec = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func(): post_draw_usec = Time.get_ticks_usec())
	tree.physics_frame.connect(func(): last_physics_usec = Time.get_ticks_usec())
	for i in 30:
		await tree.process_frame
	previous = Time.get_ticks_usec()
	await _frames("idle", 120)
	var current := tower._current_room_id
	var start_room := tower._room_by_id[current] as DungeonRoom3D
	var starting_position := tower.player.global_position
	var visited := [current]
	var trail: Array[String] = [current]
	var hit_count := 0
	var door_count := 0
	var room_limit := OS.get_environment("PROFILE_ROOMS").to_int()
	if room_limit <= 0:
		room_limit = 4
	var steps := 0
	while visited.size() <= room_limit:
		var next := ""
		for neighbor in tower._room_neighbors.get(current, []):
			if not neighbor in visited and tower._room_by_id.has(neighbor):
				next = str(neighbor)
				break
		var backtrack := next.is_empty()
		if backtrack:
			if trail.size() < 2:
				break
			trail.pop_back()
			next = trail.back()
		else:
			visited.append(next)
			trail.append(next)
		steps += 1
		var room := tower._room_by_id[next] as DungeonRoom3D
		var label := ("return_open/%s/" % steps if backtrack else "open/") + next
		var begin := Time.get_ticks_usec()
		tower.force_open_edge_for_test(current, next)
		_event(label, begin, {"alive":tower._alive_by_room.get(next, 0)})
		door_count += 1
		await _frames(label, 15)
		label = ("return_enter/%s/" % steps if backtrack else "enter/") + next
		begin = Time.get_ticks_usec()
		var from := room.global_position + Vector3.UP * 4.0
		var ray := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 10.0, 1)
		ray.exclude = [tower.player.get_rid()]
		var hit := room.get_world_3d().direct_space_state.intersect_ray(ray)
		tower.player.global_position = (hit.get("position", room.global_position) as Vector3) + Vector3.UP * 0.15
		tower.player.velocity = Vector3.ZERO
		tower.force_enter_room_for_test(next)
		var encounter := {"room":next, "room_type":room.room_type, "alive_at_entry":tower._alive_by_room.get(next, 0)}
		_event(label, begin, encounter)
		var observe_wave := not backtrack and not room.authored_layout_peaceful and room.room_type in Dungeon3D.HOSTILE_ROOM_TYPES
		await _frames(label, 35, 1.85 if observe_wave else 0.0)
		encounter["alive_after_window"] = tower._alive_by_room.get(next, 0)
		encounter["navigation_refreshes"] = room.get_meta("furnishing_navigation_refresh_count", 0)
		encounter["last_navigation_build_ms"] = room.get_meta("furnishing_navigation_build_ms", -1.0)
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
		if steps == 1:
			for i in 2:
				label = "chest/" + str(i)
				var slot := tower.get_node_or_null("RewardChestWarmVisuals/normal")
				var warm_stage := slot.get_node_or_null("ChestSpotlightStage") if slot else null
				var warm_model: Node = slot.get_child(0) if slot and slot.get_child_count() > 0 else null
				begin = Time.get_ticks_usec()
				var chest := room.spawn_runtime_chest({"id":"profile_%d" % i}, Vector2(i*2+1, 1))
				_event(label, begin, {"created":chest != null, "used_warm_stage":is_instance_valid(warm_stage) and warm_stage.get_parent() == chest, "used_warm_model":is_instance_valid(warm_model) and warm_model.get_parent() == chest})
				await _frames(label, 40, TreasureChest3D.CHEST_SPOTLIGHT_APPEAR_DURATION_S + 0.2)
	if door_count > 0:
		var last_room := tower._room_by_id[current] as DungeonRoom3D
		for i in 3:
			_time_call("blockers", last_room._collect_spawn_blockers)
			_time_call("checkpoint", BaseManager.flush_runtime_checkpoint.bind("profile_sample"))
			await _frames("component_room", 12)
		# Reuse the actual safe starting area so an unrelated live enemy cannot intercept the control shot.
		tower.player.global_position = starting_position
		tower.player.velocity = Vector3.ZERO
		tower.force_enter_room_for_test(start_room.room_id)
		await _frames("component_fixture_setup", 20)
		await _sample_controlled_encounter(start_room)
	report["visited"] = visited
	report["unused_elite_visuals"] = tower._warm_elite_holders.keys()
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
		var center := enemy.collision_shape.global_position
		var shot_origin := Vector3.ZERO
		var clear := false
		for angle_index in 8:
			var offset := Vector3.BACK.rotated(Vector3.UP, angle_index * TAU / 8.0) * 1.25
			var query := PhysicsRayQueryParameters3D.create(center + offset, center, 5)
			query.exclude = [tower.player.get_rid()]
			if room.get_world_3d().direct_space_state.intersect_ray(query).get("collider") == enemy:
				shot_origin = center + offset
				clear = true
				break
		outcome["clear_lane"] = clear
		if not clear:
			_event("fixture_no_shot_lane", Time.get_ticks_usec(), {"room":room.room_id, "enemy_layer":enemy.collision_layer, "position":str(center)})
			break
		var observer := func(target, _damage, _critical): outcome["confirmed"] = target == enemy
		begin = Time.get_ticks_usec()
		var shot := pool.acquire({"damage":1, "speed":22.0, "hostile":false, "critical":false,
			"target_group":"enemy_3d", "projectile_collision_mask":5,
			"direction":(center-shot_origin).normalized(), "shooter":tower.player}, shot_origin)
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

func _frames(label: String, count: int, minimum_game_seconds := 0.0) -> void:
	var rid := get_viewport().get_viewport_rid()
	var frame_count := 0
	var observed_seconds := 0.0
	while frame_count < count or observed_seconds < minimum_game_seconds:
		await get_tree().process_frame
		frame_count += 1
		observed_seconds += get_process_delta_time()
		var now := Time.get_ticks_usec()
		rows.append([label, (now-previous)/1000.0, RenderingServer.viewport_get_measured_render_time_cpu(rid),
			RenderingServer.viewport_get_measured_render_time_gpu(rid), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW), Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH),
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE), Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			(pre_draw_usec-previous)/1000.0 if pre_draw_usec >= previous else -1.0,
			(post_draw_usec-pre_draw_usec)/1000.0 if post_draw_usec >= pre_draw_usec and pre_draw_usec >= previous else -1.0,
			(now-post_draw_usec)/1000.0 if post_draw_usec >= previous else -1.0,
			(last_physics_usec-previous)/1000.0 if last_physics_usec >= previous else -1.0,
			Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0])
		previous = now
