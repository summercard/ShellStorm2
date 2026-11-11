extends Node
## 直接消费正式远征数据，不覆盖encounter或编成；A/B分别在独立正式场景验证。

const SCENE = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const VALIDATOR = preload("res://src/map/LevelPlanValidator.gd")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _ready() -> void:
	var selected_port := "A"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			selected_port = argument.trim_prefix("--port=")
	check(selected_port in ["A", "B"], "入口参数必须为--port=A或--port=B")
	var appdata := OS.get_environment("APPDATA").replace("\\", "/").to_lower()
	check(appdata.contains("/flow_integration/") and appdata.ends_with("/appdata"), "必须使用启动前隔离APPDATA")
	verify_validator_alert_contract()
	var validation: Dictionary = VALIDATOR.validate_level("expedition_01")
	print("ENCOUNTER_PRODUCTION_VALIDATION ok=%s errors=%s" % [validation.get("ok", false), str(validation.get("errors", []))])
	var runtime_blockers: Array = []
	for error in validation.get("errors", []):
		# constrained文件中的示例版图重叠单列，不当运行时生成几何；正式生成器仍执行权威几何门禁。
		if not str(error).begins_with("room_overlap:"):
			runtime_blockers.append(error)
	check(runtime_blockers.is_empty(), "正式数据非示例几何门禁必须通过，不能用fixture绕过")
	if failures.is_empty():
		await verify_run(selected_port)
	print("ENCOUNTER_DOOR_PREPARATION_OK checks=%d failures=%d" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func verify_validator_alert_contract() -> void:
	var base := {"trigger":{"shape":"circle", "radius_m":6.0}, "duration_sec":0.0, "completion":"clear", "stage_advance":"clear", "stages":[{"monsters":[{"type":"melee_chaser", "count":1}]}]}
	check(VALIDATOR._validate_triggered_encounter(base, "alert_contract").is_empty(), "Validator旧缺字段仍合法")
	for style in ["red_eva", "subtle", "none"]:
		var valid := base.duplicate(true)
		valid.merge({"alert_style":style, "alert_text":"中".repeat(80), "alert_beep_interval_sec":0.25, "alert_pulse":false}, true)
		check(VALIDATOR._validate_triggered_encounter(valid, "alert_contract").is_empty(), "Validator合法四键:" + style)
	for mutation in [{"alert_style":1}, {"alert_style":"default"}, {"alert_text":false}, {"alert_text":"中".repeat(81)}, {"alert_beep_interval_sec":true}, {"alert_beep_interval_sec":"1"}, {"alert_beep_interval_sec":0.0}, {"alert_beep_interval_sec":INF}, {"alert_beep_interval_sec":2.01}, {"alert_pulse":1}]:
		var invalid := base.duplicate(true)
		invalid.merge(mutation, true)
		check(not VALIDATOR._validate_triggered_encounter(invalid, "alert_contract").is_empty(), "Validator严格拒绝:" + str(mutation))

func verify_run(port_id: String) -> void:
	var tower := SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	var deadline := Time.get_ticks_msec() + 100000
	while Time.get_ticks_msec() < deadline and not tower._expedition_bootstrap_failed:
		if tower._room_by_id.has("room_10") and tower._main_story_gameplay_started and not tower._expedition_loading_active:
			break
		await get_tree().process_frame
	var ready := tower._room_by_id.has("room_10") and not tower._expedition_loading_active and not tower._expedition_bootstrap_failed
	check(ready, "正式13房初始化:" + port_id)
	if ready:
		tower.set_process(false)
		tower.player.set_physics_process(false)
		tower.get_node("ActiveEnemies").process_mode = Node.PROCESS_MODE_DISABLED
		await verify_room(tower, port_id)
		if port_id == "A":
			await verify_ordinary_single_wave(tower)
	tower.queue_free()
	await get_tree().process_frame

func entry_position(room: DungeonRoom3D, port_id: String) -> Vector3:
	var port := room.get_connection_port_by_id(port_id)
	var p: Array = port.get("position_m", [0.0, 0.0])
	var n: Array = port.get("outward", [0.0, 0.0])
	var trigger: Dictionary = room.encounter.trigger
	var inset := float(trigger.inset_m) + float(trigger.depth_m) * 0.5
	return room.to_global(Vector3(float(p[0]) - float(n[0]) * inset, 0.5, float(p[1]) - float(n[1]) * inset))

func enemies(tower: TowerDescent3D, room_id: String) -> Array[Enemy3D]:
	var result: Array[Enemy3D] = []
	for enemy: Enemy3D in tower._enemy_nodes_by_room.get(room_id, []):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.ai_state != "dead":
			result.append(enemy)
	return result

func kill_wave(tower: TowerDescent3D, room: DungeonRoom3D) -> void:
	for enemy in enemies(tower, room.room_id):
		# 测试驱动真实击杀记账，不改Director的spawned/pending/stage_states。
		tower._on_enemy_killed(enemy, enemy.get_enemy_data())
		enemy.free()
	tower._enemy_nodes_by_room[room.room_id] = []

func verify_room(tower: TowerDescent3D, port_id: String) -> void:
	var room := tower._room_by_id["room_03"] as DungeonRoom3D
	var original_encounter := room.encounter.duplicate(true)
	check(str(room.encounter.trigger.shape) == "door_entries" and room.encounter.trigger.port_ids == ["A", "B"], "生产双入口配置:" + port_id)
	check(float(room.encounter.preparation_sec) == 3.0 and float(room.encounter.freeze_player_sec) == 1.0 and float(room.encounter.start_delay_sec) == 3.0, "生产03准备3秒/冻1秒/首波3秒")
	check(str(room.encounter.alert_style) == "red_eva" and str(room.encounter.remote_spawn_policy) == "opposite_entry", "生产03明确红警与远端策略")
	for key in ["room_04", "room_06", "room_09", "room_10"]:
		var other := tower._room_by_id[key] as DungeonRoom3D
		var expected_style := "red_eva" if key in ["room_06", "room_09"] else "subtle"
		check(str(other.encounter.alert_style) == expected_style and float(other.encounter.freeze_player_sec) == 0.0, "生产非03警报及不冻结:" + key)
	room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	tower.player.global_position = room.to_global(Vector3.ZERO)
	tower.force_enter_room_for_test(room.room_id)
	room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	await get_tree().physics_frame
	check(enemies(tower, room.room_id).is_empty() and not tower._room_encounters_fired.has(room.room_id), "进房未踩入口不刷怪不触发")
	for id in ["A", "B"]:
		check(room.match_door_entry_trigger(room.encounter.trigger, entry_position(room, id)).port_id == id, "真实几何入口命中:" + id)
	var sealed_at_start: Array = []
	var callback := func(snapshot: Dictionary): sealed_at_start.append(tower._room_is_sealed(str(snapshot.room_id)))
	tower.encounter_event_started.connect(callback)
	tower.player.global_position = entry_position(room, port_id)
	tower._tick_room_encounter_triggers(0.0)
	tower.encounter_event_started.disconnect(callback)
	var id := str(tower._room_encounter_active.get(room.room_id, ""))
	check(not id.is_empty() and sealed_at_start == [true], "先封门再启动:" + port_id)
	if id.is_empty():
		return
	var state := tower.get_encounter_event_snapshot(id)
	check(state.trigger_port_id == port_id and int(state.requested) == 20 and state.config.alert_style == "red_eva", "入口冻结/总20/alert配置透传")
	check(state.alert_phase == "preparation" and float(state.alert_remaining_sec) == 3.0, "准备投影存在")
	check(tower.player.input_locked and tower._scripted_input_hold_sources.has("encounter:" + id), "触发第一秒已实际锁玩家")
	tower._encounter_event_director.tick(0.9)
	check(tower.player.input_locked and int(tower.get_encounter_event_snapshot(id).spawned) == 0, "首0.9秒仍锁且无怪")
	var world := tower._build_runtime_world_save_snapshot()
	check((world.room_encounter_flow.active as Dictionary).get(room.room_id) == id and (world.room_encounter_flow.sealed as Dictionary).has(room.room_id), "正式Tower保存active/sealed")
	check(tower._restore_runtime_world_save_snapshot({"world_state":JSON.parse_string(JSON.stringify(world))}), "生产事件准备中正式路径恢复")
	check(is_equal_approx(float(tower.get_encounter_event_snapshot(id).preparation_remaining_sec), 2.1), "读档不重置准备")
	tower._encounter_event_director.tick(0.1)
	check(not tower._scripted_input_hold_sources.has("encounter:" + id) and not tower.player.input_locked, "首秒结束实际释放玩家且不等3秒")
	tower._encounter_event_director.tick(1.9)
	check(int(tower.get_encounter_event_snapshot(id).spawned) == 0 and enemies(tower, room.room_id).is_empty(), "准备2.9秒仍无怪")
	tower._encounter_event_director.tick(0.1)
	state = tower.get_encounter_event_snapshot(id)
	check(int(state.spawned) == 5 and enemies(tower, room.room_id).size() == 5, "正式首批恰好5只")
	check_wave_positions(tower, room, port_id, 6.0, false)
	var other_id := "B" if port_id == "A" else "A"
	var before_instances := tower._encounter_event_director.get_snapshot_rows().size()
	tower.player.global_position = entry_position(room, other_id)
	tower._tick_room_encounter_triggers(0.0)
	check(tower._encounter_event_director.get_snapshot_rows().size() == before_instances and str(tower._room_encounter_active.get(room.room_id, "")) == id, "两门共用once，另一门不新建事件")
	tower.player.global_position = entry_position(room, port_id)
	kill_wave(tower, room)
	state = tower.get_encounter_event_snapshot(id)
	check(state.alert_phase == "intermission" and float(state.alert_remaining_sec) == 3.0 and float(state.alert_total_sec) == 3.0, "首批清空3秒接敌间歇投影")
	check(not state.preparation_active and not tower.player.input_locked, "间歇不成为新准备不冻结")
	tower._encounter_event_director.tick(2.9)
	check(int(tower.get_encounter_event_snapshot(id).spawned) == 5 and not tower.player.input_locked, "间歇到点前无第二波且输入自由")
	tower._encounter_event_director.tick(0.1001)
	state = tower.get_encounter_event_snapshot(id)
	check(int(state.spawned) == 12 and enemies(tower, room.room_id).size() == 7, "正式第二批恰好7只")
	check_wave_positions(tower, room, port_id, 6.0, true)
	kill_wave(tower, room)
	check(float(tower.get_encounter_event_snapshot(id).alert_remaining_sec) == 3.0 and not tower.player.input_locked, "第二次间歇仍3秒且不冻结")
	tower._encounter_event_director.tick(3.0)
	state = tower.get_encounter_event_snapshot(id)
	check(int(state.spawned) == 20 and enemies(tower, room.room_id).size() == 8, "正式第三批8只累计20")
	check_wave_positions(tower, room, port_id, 6.0, false)
	kill_wave(tower, room)
	state = tower.get_encounter_event_snapshot(id)
	check(state.status == "completed" and int(state.spawned) == 20 and int(state.dropped) == 0 and int(state.pending) == 0, "正式总20不丢不重最终完成")
	check(room.cleared and not tower._room_is_sealed(room.room_id) and not tower._room_encounter_active.has(room.room_id), "末波完成立即清房解封")
	tower.player.global_position = entry_position(room, other_id)
	tower._tick_room_encounter_triggers(0.0)
	check(tower._encounter_event_director.get_snapshot_rows().size() == before_instances, "完成后另一入口仍不能重触发")
	check(room.encounter == original_encounter, "正式配置全程未被fixture改写")
	print("ENCOUNTER_PRODUCTION_PORT_OK port=%s spawned=%d dropped=%d" % [port_id, int(state.spawned), int(state.dropped)])

func check_wave_positions(tower: TowerDescent3D, room: DungeonRoom3D, port_id: String, minimum: float, fat_eight: bool) -> void:
	var port := room.get_connection_port_by_id(port_id)
	var n: Array = port.outward
	var inward := -Vector2(float(n[0]), float(n[1]))
	var fat_count := 0
	for enemy in enemies(tower, room.room_id):
		var local := room.to_local(enemy.global_position)
		check(Vector2(local.x, local.z).dot(inward) >= -0.01, "真实刷点在反入口半区:" + port_id)
		var distance := Vector2(enemy.global_position.x - tower.player.global_position.x, enemy.global_position.z - tower.player.global_position.z).length()
		check(distance >= minimum, "真实刷点至少6m")
		if fat_eight and enemy.enemy_kind == "fat_zombie03":
			fat_count += 1
			check(distance >= 8.0, "第二批胖子距玩家至少8m")
	if fat_eight:
		check(fat_count == 1, "第二批真实胖子恰好1只")

func verify_ordinary_single_wave(tower: TowerDescent3D) -> void:
	var bounds := {"room_01":[6,6], "room_02":[7,8], "room_05":[31,31], "room_07":[12,12], "room_08":[16,17]}
	for room_id in ["room_01", "room_02", "room_05", "room_07", "room_08"]:
		var room := tower._room_by_id[room_id] as DungeonRoom3D
		var original := room.encounter.duplicate(true)
		check(not room.encounter.has("trigger") and (room.encounter.stages as Array).size() == 1 and float(room.encounter.intermission_sec) == 0.0, "普通房正式数据只有一阶段:" + room_id)
		var expected := expected_box_count(tower, room)
		check(expected >= int(bounds[room_id][0]) and expected <= int(bounds[room_id][1]), "独立编成计数符合批准数量:" + room_id)
		# 正式入口走原盒子波次链，等待真实延迟与预约全部实到，不改编成或快进定时器。
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		tower.player.global_position = entry_position_for_ordinary(room)
		tower.force_enter_room_for_test(room.room_id)
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		var deadline := Time.get_ticks_msec() + 20000
		var signature := {}
		var delivered_ids := {}
		var duplicate_id := false
		var premature_clear := false
		while Time.get_ticks_msec() < deadline:
			var live := enemies(tower, room_id)
			for enemy in live:
				var persistent_id := enemy.get_persistent_id()
				duplicate_id = duplicate_id or delivered_ids.has(persistent_id)
				delivered_ids[persistent_id] = true
				signature[enemy.enemy_kind] = int(signature.get(enemy.enemy_kind, 0)) + 1
				check(Vector2(enemy.global_position.x - tower.player.global_position.x, enemy.global_position.z - tower.player.global_position.z).length() >= 6.0, "普通单波仍保持6m:" + room_id)
				# 释放真实实体占位，允许同一波原pending陆续实到，不改配置/队列/计时。
				tower._on_enemy_killed(enemy, enemy.get_enemy_data())
				enemy.free()
			tower._enemy_nodes_by_room[room_id] = []
			if room.cleared and delivered_ids.size() < expected:
				premature_clear = true
			if int(tower._room_wave_totals.get(room_id, 0)) > 0 and (tower._pending_delayed_spawns.get(room_id, []) as Array).is_empty() and tower._reserved_spawn_count(room_id) == 0:
				break
			await get_tree().process_frame
		check(int(tower._room_wave_totals.get(room_id, 0)) == 1 and (tower._room_wave_queues.get(room_id, []) as Array).is_empty(), "普通房实际只提交同一波:" + room_id)
		check(delivered_ids.size() == expected and not duplicate_id, "全部编成真实实到且身份不重:" + room_id)
		check(not premature_clear, "pending未实到不能提前清房:" + room_id)
		check((tower._pending_delayed_spawns.get(room_id, []) as Array).is_empty() and tower._reserved_spawn_count(room_id) == 0, "没有未实到预约:" + room_id)
		check(room.cleared and (tower._room_wave_queues.get(room_id, []) as Array).is_empty(), "普通房同波清完无追加第二波:" + room_id)
		check(room.encounter == original, "普通生产编成未被改写:" + room_id)
		print("ENCOUNTER_PRODUCTION_ORDINARY_RESULT room=%s wave_total=%d expected=%d delivered=%d signature=%s" % [room_id, int(tower._room_wave_totals.get(room_id, 0)), expected, delivered_ids.size(), str(signature)])

func expected_box_count(tower: TowerDescent3D, room: DungeonRoom3D) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = tower.run_seed ^ room.room_id.hash() ^ 0x424f5831
	var total := 0
	for index in room.spawn_placements.size():
		var placement := tower._box_placement_at(room.spawn_placements, index)
		var box := SpawnBoxCatalog.resolve_placement_box(placement)
		var bonus_used := false
		for spawn: Dictionary in box.get("spawns", []):
			var count := tower._roll_box_count(spawn, rng)
			if count > 0 and str(spawn.get("type", "")) not in ["elite", "boss"]:
				count *= maxi(1, int(placement.get("box_count_multiplier", 1)))
				if not bonus_used and int(placement.get("box_count_bonus", 0)) > 0:
					count += int(placement["box_count_bonus"])
					bonus_used = true
			total += count
	return total

func entry_position_for_ordinary(room: DungeonRoom3D) -> Vector3:
	var port := room.get_connection_port_by_id("A")
	var p: Array = port.get("position_m", [0.0, 0.0])
	var n: Array = port.get("outward", [0.0, 0.0])
	return room.to_global(Vector3(float(p[0]) - float(n[0]) * 3.5, 0.5, float(p[1]) - float(n[1]) * 3.5))
