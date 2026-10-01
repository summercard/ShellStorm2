extends Node

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_SCRIPT := preload("res://src/world3d/DungeonRoom3D.gd")
const BASE_RETURN_SCENE: PackedScene = preload("res://scenes/TowerDescent3D.tscn")
const RUN_SEED := 77001199
const PLAN_SEED_COUNT := 64
# 测试关卡99在 L1 设计源中登记的真实 ID，不是显示名 test_level_99。
const OTHER_LEVEL_ID := "99"
const OTHER_LEVEL_SOURCE := "res://source/art/whitebox/tower_zones/99/v001/data/level_plan.json"
const POSITION_EPSILON := 0.01


class InvalidPlanTower extends TowerDescent3D:
	func _regenerate_floor_plans_for_current_seed() -> void:
		_floor_plan_snapshots.clear()
		_floor_plan_snapshots[0] = {
			"valid": false,
			"rooms": [{"key": "entry", "id": "start"}],
			"validation_errors": ["probe_invalid_plan"],
		}


# 不覆写 _ready：真实执行 Tower/Dungeon 的入口分支与保险投影。
# 只把转场记成调用记录，并延后写盘激活；不靠 test_mode 跳过被测逻辑。
class BaseReturnReadyTower extends TowerDescent3D:
	var resume_calls: Array[Dictionary] = []
	var persistence_activation_calls := 0

	func _resume_expedition_runtime_scene(scene_path: String, request_id: int) -> void:
		resume_calls.append({"scene_path": scene_path, "request_id": request_id})

	func _activate_runtime_persistence() -> void:
		persistence_activation_calls += 1

	func _defer_gameplay_started() -> void:
		# 此探针不触发返城剧情及其跨局历史写盘。
		pass


var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	var previous_clock_running := GameTimeManager.clock_running
	GameTimeManager.clock_running = false
	_check_plan_rotation()
	await _check_invalid_plan_bootstrap()
	await _check_base_return_ready_contract()
	var old_plan := FloorPlanGenerator.generate_from_level_plan("expedition_01", 0, RUN_SEED, 0)
	var new_plan := FloorPlanGenerator.generate_from_level_plan("expedition_01", 0, RUN_SEED)
	_check(is_equal_approx(float(_plan_room(old_plan, "room_01").get("rotation_deg", -1.0)), 270.0), "旧版 room01 应由端口求解为 270°")
	_check(is_equal_approx(float(_plan_room(new_plan, "room_01").get("rotation_deg", -1.0)), 90.0), "北向版 room01 必须为 90°")
	var previous_static := bool(ROOM_SCRIPT.use_expedition_static_layout_scenes)
	var fresh: Dictionary = await _probe_runtime({}, 180, "NEW")
	# 快照只含 world_state；test_mode 不读真实档案、不自动恢复/持久化。
	var legacy: Dictionary = await _probe_runtime({"world_state": {
		"floor_layout_ids": {"0": str(old_plan.get("layout_id", ""))},
	}}, 0, "OLD_MISSING_ROTATION")
	var explicit_new: Dictionary = await _probe_runtime({"world_state": {
		"expedition_global_rotation_deg": 180,
		"floor_layout_ids": {"0": str(new_plan.get("layout_id", ""))},
	}}, 180, "NEW_CHECKPOINT")
	_check_runtime_rotation(legacy, fresh)
	_check(_same_value(fresh, explicit_new), "显式180检查点与空新局的运行时空间结果必须一致")
	ROOM_SCRIPT.use_expedition_static_layout_scenes = previous_static
	GameTimeManager.clock_running = previous_clock_running
	if failures.is_empty():
		print("EXPEDITION_CONNECTION_PORTS_OK checks=%d seeds=%d runtime_scenes=3 checkpoint_restore_cases=4" % [checks, PLAN_SEED_COUNT])
		get_tree().quit(0)
		return
	for failure in failures:
		print("FAIL %s" % failure)
	get_tree().quit(1)


func _probe_runtime(snapshot: Dictionary, rotation: int, label: String) -> Dictionary:
	var plan := FloorPlanGenerator.generate_from_level_plan("expedition_01", 0, RUN_SEED, rotation)
	ROOM_SCRIPT.use_expedition_static_layout_scenes = true
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	tower.set("_runtime_restore_snapshot", snapshot.duplicate(true))
	_check(int(tower.call("_expedition_rotation_for_checkpoint", snapshot)) == rotation, "%s 检查点朝向选择错误" % label)
	add_child(tower)
	var born := tower.player.global_position if tower.player != null else Vector3.INF
	for _index in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	_check(block != null, "运行时必须生成远征区块")
	var rooms := _collect_rooms(block)
	_check(rooms.size() == 13, "%s 运行时必须生成 13 间房" % label)
	var runtime_plan := (tower.get("_floor_plan_snapshots") as Dictionary).get(0, {}) as Dictionary
	_check(_same_value(runtime_plan, plan), "%s 运行时0层计划必须等于对应朝向生成结果" % label)
	_check(not bool(tower.get("_runtime_persistence_active")), "%s test_mode 禁止自动持久化" % label)
	var runtime := _check_runtime_records(tower, rooms, plan, born, rotation, label)
	_check_checkpoint_contract(tower, rooms, plan, rotation, label)
	var unique_doors := {}
	var checked_edges := {}
	for room_value in rooms.values():
		var room := room_value as DungeonRoom3D
		var port_root := room.find_child("ConnectionPorts", true, false) as Node3D
		_check(port_root != null, "%s 缺少 ConnectionPorts" % room.room_id)
		if port_root != null:
			_check(
				port_root.get_child_count() == room.connection_ports.size(),
				"%s 端口 Marker 数量不匹配" % room.room_id
			)
		for port_value in room.connection_ports:
			var port := port_value as Dictionary
			var port_id := str(port.get("port_id", ""))
			var target_id := str(port.get("target_room_id", ""))
			_check(not port_id.is_empty(), "%s 存在空端口编号" % room.room_id)
			if port_root != null:
				var marker := port_root.get_node_or_null("Port_%s" % port_id) as Marker3D
				_check(marker != null, "%s-%s 缺少 Marker3D" % [room.room_id, port_id])
				if marker != null:
					_check(marker.global_position.distance_to(_port_world(room, port)) <= POSITION_EPSILON, "%s-%s Marker必须匹配端口世界位置" % [room.room_id, port_id])
					var outward := _port_outward(port)
					_check(marker.global_basis.z.normalized().dot(Vector3(outward.x, 0.0, outward.y)) >= 0.999, "%s-%s Marker法线必须匹配端口" % [room.room_id, port_id])
			if target_id.is_empty():
				continue
			var edge := _edge_key(room.room_id, target_id)
			if checked_edges.has(edge):
				continue
			checked_edges[edge] = true
			var peer := rooms.get(target_id) as DungeonRoom3D
			_check(peer != null, "%s 指向不存在的房间 %s" % [room.room_id, target_id])
			if peer == null:
				continue
			var reciprocal := peer.get_connection_port_towards(room.room_id)
			_check(not reciprocal.is_empty(), "%s 缺少回指 %s 的端口" % [target_id, room.room_id])
			if reciprocal.is_empty():
				continue
			var a_world := _port_world(room, port)
			var b_world := _port_world(peer, reciprocal)
			_check(a_world.distance_to(b_world) <= 0.01, "%s 两端锚点未重合" % edge)
			_check(
				_port_outward(port).dot(_port_outward(reciprocal)) <= -0.999,
				"%s 两端朝外方向未相反" % edge
			)
			var a_side := str(port.get("side", ""))
			var b_side := str(reciprocal.get("side", ""))
			var a_door := room.get_door_node(a_side)
			var b_door := peer.get_door_node(b_side)
			_check(a_door != null and b_door != null, "%s 缺少运行时门" % edge)
			if a_door != null and b_door != null:
				_check(a_door == b_door, "%s 两端没有共享同一个 RoomDoor3D" % edge)
				unique_doors[a_door.get_instance_id()] = true
			_check(
				room.owns_door_endpoint(a_side) != peer.owns_door_endpoint(b_side),
				"%s 必须且只能有一个门实体所有者" % edge
			)
	_check(checked_edges.size() == 12, "主路必须形成 12 条连接边")
	_check(unique_doors.size() == 12, "12 条边必须恰好只有 12 个门实体")

	var room_01 := rooms.get("room_01") as DungeonRoom3D
	_check(room_01 != null, "缺少 room_01")
	if room_01 != null:
		var ports_by_id := {}
		for value in room_01.connection_ports:
			var port := value as Dictionary
			ports_by_id[str(port.get("port_id", ""))] = port
		_check(str((ports_by_id.get("A", {}) as Dictionary).get("target_room_id", "")) == "start", "room01-A 必须连接安全屋")
		_check(str((ports_by_id.get("B", {}) as Dictionary).get("target_room_id", "")) == "room_02", "room01-B 必须连接 room02")
		_check(str((ports_by_id.get("C", {}) as Dictionary).get("target_room_id", "x")).is_empty(), "room01-C 必须保持封闭")
		_check(str((ports_by_id.get("D", {}) as Dictionary).get("target_room_id", "x")).is_empty(), "room01-D 必须保持封闭")
		var art_root := room_01.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
		_check(art_root != null, "room01 缺少静态艺术根")
		if art_root != null:
			_check(art_root.get_node_or_null("ENV-EXPEDITION-L-CORRIDOR-WALL_X_05_REAR") != null, "room01-C 未用门洞必须有封墙")
			_check(art_root.get_node_or_null("ENV-EXPEDITION-L-CORRIDOR-WALL_X_35_REAR") != null, "room01-D 未用门洞必须有封墙")
			_check(art_root.get_node_or_null("ENV-EXPEDITION-L-CORRIDOR-WALL_Y_30_00") == null, "room01-A 非所有者不得保留重叠墙")

	tower.queue_free()
	await get_tree().process_frame
	return runtime


func _check_invalid_plan_bootstrap() -> void:
	var previous_entry := GameEntryFlow.peek_pending_entry()
	var previous_request_id := int(GameEntryFlow.get("_next_request_id"))
	var previous_startup_consumed := bool(GameEntryFlow.get("_startup_entry_consumed"))
	var profile_before := BaseManager.get_profile_snapshot()
	var previous_static := bool(ROOM_SCRIPT.use_expedition_static_layout_scenes)
	ROOM_SCRIPT.use_expedition_static_layout_scenes = true
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	var completed_signals: Array = []
	tower.generation_completed.connect(func(_snapshot: Dictionary) -> void: completed_signals.append(true))
	var initial_player := tower.get_node("Player3D") as Player3D
	var initial_position := initial_player.position
	var invalid_source := InvalidPlanTower.new()
	var invalid_script: Script = invalid_source.get_script()
	invalid_source.free()
	tower.set_script(invalid_script)
	# 替换脚本会重置原场景导出属性；重新声明 fixture 的远征身份。
	tower.expedition_mode = true
	tower.expedition_run_id = "expedition_01"
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	for _index in range(4):
		await get_tree().process_frame
	_check((tower.get("_records") as Array).is_empty(), "invalid plan 启动必须保持0个房间 records")
	_check((tower.get("_rooms") as Array).is_empty(), "invalid plan 启动必须保持0个运行时房间")
	_check((tower.get("_generated_floor_indices") as Array).is_empty(), "invalid plan 启动不得提交任何 generated floor")
	var generated_rooms := tower.get_node_or_null("GeneratedRooms") as Node
	_check(generated_rooms != null and generated_rooms.get_child_count() == 0, "invalid plan 启动不得生成任何房间节点")
	_check(bool(tower.get("_expedition_bootstrap_failed")), "invalid plan 启动必须进入失败态")
	_check(completed_signals.is_empty(), "invalid plan 不得发出生成完成信号")
	_check(initial_player.position.is_equal_approx(initial_position), "invalid plan 不得执行玩家出生落位")
	_check(not bool(tower.get("_runtime_persistence_active")), "invalid plan 失败态不得启用 persistence")
	_check(tower.process_mode == Node.PROCESS_MODE_DISABLED, "invalid plan 失败态必须禁用关卡处理")
	var player := tower.player
	_check(player != null and player.input_locked, "invalid plan 失败态必须锁定玩家输入")
	_check(player != null and not player.combat_enabled, "invalid plan 失败态必须关闭玩家 combat")
	_check(tower.title_label != null and tower.title_label.text.contains("远征启动失败"), "invalid plan 失败态 UI 标题必须可见")
	_check(tower.status_label != null and tower.status_label.text.contains("请通过暂停界面退出"), "invalid plan 失败态 UI 必须提示可退出")
	_check(tower.title_label != null and tower.title_label.is_visible_in_tree(), "invalid plan 失败标题必须实际可见")
	_check(tower.status_label != null and tower.status_label.is_visible_in_tree(), "invalid plan 退出指引必须实际可见")
	var pause := tower.get_node_or_null("HUD/PauseOverlay") as PauseMenu3D
	_check(pause != null, "invalid plan 失败态必须保留暂停菜单返回入口")
	if pause != null:
		pause.set_paused(true)
		var availability := pause.get_return_to_base_availability()
		_check(bool(availability.get("available", false)), "invalid plan 失败态暂停菜单必须允许返回基地")
		_check(pause.return_to_base_button.visible and not pause.return_to_base_button.disabled, "invalid plan 失败态返回按钮必须可用")
		pause.set_paused(false)
	var return_result := tower.call("return_player_to_base_center_from_pause") as Dictionary
	_check(bool(return_result.get("success", false)), "invalid plan 失败态必须可返回基地")
	var pending_return := GameEntryFlow.peek_pending_entry()
	_check(int(pending_return.get("request_id", 0)) >= previous_request_id, "invalid plan 失败返城必须登记一次性入口请求")
	_check(str(pending_return.get("kind", "")) == GameEntryFlow.KIND_GAMEPLAY and str(pending_return.get("reason", "")) == GameEntryFlow.REASON_ABORT_RETURN_99F and str(pending_return.get("spawn_target", "")) == GameEntryFlow.SPAWN_BASE_99F, "invalid plan 失败返城必须声明gameplay/abort_return_99f/base_99f")
	_check(not bool(pending_return.get("show_main_entry", false)), "invalid plan 失败返城不得请求冷启动入口")
	_check(tower.return_scene_path == GameDesignConfig.MAIN_SCENE, "invalid plan 失败返城目标必须是正式99F主场景")
	_assert_runtime_state_unchanged(profile_before, BaseManager.get_profile_snapshot(), "invalid plan 失败返城不得结算或改写档案")
	tower.queue_free()
	await get_tree().process_frame
	GameEntryFlow.set("_pending_context", previous_entry)
	GameEntryFlow.set("_next_request_id", previous_request_id)
	GameEntryFlow.set("_startup_entry_consumed", previous_startup_consumed)
	ROOM_SCRIPT.use_expedition_static_layout_scenes = previous_static


func _check_base_return_ready_contract() -> void:
	var previous_data := BaseManager.data
	var previous_save_path := BaseManager.save_path
	var previous_save_failure := BaseManager.force_save_failure_for_test
	var previous_provider: WeakRef = BaseManager.get("_runtime_checkpoint_provider")
	var previous_dirty := bool(BaseManager.get("_runtime_checkpoint_dirty"))
	var previous_runtime_reason := str(BaseManager.get("_pending_runtime_reason"))
	var checkpoint_timer := BaseManager.get("_runtime_checkpoint_timer") as Timer
	var previous_timer_left := checkpoint_timer.time_left if checkpoint_timer != null else 0.0
	var previous_entry := GameEntryFlow.peek_pending_entry()
	var previous_startup_consumed := bool(GameEntryFlow.get("_startup_entry_consumed"))
	var previous_request_id := int(GameEntryFlow.get("_next_request_id"))
	var previous_currency := GameManager.currency
	var previous_static := bool(ROOM_SCRIPT.use_expedition_static_layout_scenes)
	if checkpoint_timer != null:
		checkpoint_timer.stop()
	BaseManager.set("_runtime_checkpoint_provider", null)
	BaseManager.set("_runtime_checkpoint_dirty", false)
	BaseManager.set("_pending_runtime_reason", "")
	# 新建内存档案，写盘强制失败；读取 revision 也改走独享的不存在路径。
	# 不创建该路径，不加载/修改用户 base_save.json 或其备份。
	var isolated_path := OS.get_cache_dir().path_join(
		"probe_expedition_return_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	_check(not FileAccess.file_exists(isolated_path) and not FileAccess.file_exists(isolated_path + ".bak"), "返城隔离路径必须不存在")
	BaseManager.save_path = isolated_path
	BaseManager.force_save_failure_for_test = true
	ROOM_SCRIPT.use_expedition_static_layout_scenes = false
	var checkpoint := RunPersistenceService.finalize_runtime_snapshot({
		"scope": "combat", "runtime_map_id": "expedition_01",
		"run_seed": RUN_SEED + 7, "run_id": "probe_failed_expedition_run",
		"current_room_id": "room_01", "current_floor_index": 0,
		"player_position": [900.0, 900.0, 900.0],
		"inventory_capacity": 12,
		"inventory_slots": [{"item": {"id": "probe_abort_carry", "type": "material", "item_instance_id": "probe_abort_owned"}, "count": 3, "slot": 0}],
		"insurance_capacity": 2,
		"insurance_slots": [{"item": {"id": "probe_stale_insurance", "type": "material", "item_instance_id": "probe_stale_owned"}, "count": 9, "insured_at": 11, "insurance_slot": 0}, {}],
		"world_state": {"schema": "tower_world_state_v1", "room_progress": {"room_01": {"cleared": true}}},
	})
	var pending: Array[Dictionary] = [{
		"item": {"id": "probe_pending_insurance", "type": "material", "item_instance_id": "probe_pending_owned"},
		"count": 2, "insured_at": 22, "insurance_slot": 1,
	}]
	await _probe_base_return_ready(checkpoint, [], GameEntryFlow.REASON_ABORT_RETURN_99F, GameEntryFlow.SPAWN_BASE_99F, false, "ABORT_NO_INSURANCE")
	await _probe_base_return_ready(checkpoint, pending, GameEntryFlow.REASON_ABORT_RETURN_99F, GameEntryFlow.SPAWN_BASE_99F, false, "ABORT_PENDING_INSURANCE")
	# 反向对照：普通恢复仍须路由；仅 reason 或仅 spawn_target 命中不足以抑制续局。
	await _probe_base_return_ready(checkpoint, [], GameEntryFlow.REASON_RUNTIME_RESTORE, GameEntryFlow.SPAWN_SAVED_PROGRESS, true, "NORMAL_RESUME")
	await _probe_base_return_ready(checkpoint, [], GameEntryFlow.REASON_ABORT_RETURN_99F, GameEntryFlow.SPAWN_SAVED_PROGRESS, true, "ABORT_REASON_ONLY")
	await _probe_base_return_ready(checkpoint, [], GameEntryFlow.REASON_SCENE_REENTRY, GameEntryFlow.SPAWN_BASE_99F, true, "BASE_TARGET_ONLY")
	# 复用同一内存档案/写盘禁用边界，但每例使用真实远征场景和全新 BaseData。
	await _probe_checkpoint_restore(0, "missing_id", false, "RESTORE_0_MISSING_ID")
	await _probe_checkpoint_restore(180, "bad_id", false, "RESTORE_180_BAD_ID")
	await _probe_checkpoint_restore(180, "bad_rotation", false, "RESTORE_180_BAD_ROTATION")
	await _probe_checkpoint_restore(180, "", true, "RESTORE_180_VALID")
	_check(not FileAccess.file_exists(isolated_path) and not FileAccess.file_exists(isolated_path + ".bak") and not FileAccess.file_exists(isolated_path + ".tmp"), "真实_ready返城探针不得写出任何存档文件")
	BaseManager.data = previous_data
	BaseManager.save_path = previous_save_path
	BaseManager.force_save_failure_for_test = previous_save_failure
	BaseManager.set("_runtime_checkpoint_provider", previous_provider)
	BaseManager.set("_runtime_checkpoint_dirty", previous_dirty)
	BaseManager.set("_pending_runtime_reason", previous_runtime_reason)
	if checkpoint_timer != null and previous_timer_left > 0.0:
		checkpoint_timer.start(previous_timer_left)
	GameEntryFlow.set("_pending_context", previous_entry)
	GameEntryFlow.set("_startup_entry_consumed", previous_startup_consumed)
	GameEntryFlow.set("_next_request_id", previous_request_id)
	GameManager.currency = previous_currency
	GameManager.currency_changed.emit(previous_currency)
	ROOM_SCRIPT.use_expedition_static_layout_scenes = previous_static
	print("EXPEDITION_BASE_RETURN_READY_CASES cases=5 test_mode=false persistence_commit=not_exercised")


func _probe_base_return_ready(
	checkpoint: Dictionary, pending: Array[Dictionary], reason: String,
	spawn_target: String, expects_resume: bool, label: String
) -> void:
	BaseManager.data = BaseData.new()
	BaseManager.data.active_run_snapshot = checkpoint.duplicate(true)
	BaseManager.data.pending_insurance_slots = pending.duplicate(true)
	var profile_before := BaseManager.get_profile_snapshot()
	var tower := BASE_RETURN_SCENE.instantiate() as TowerDescent3D
	var fixture_source := BaseReturnReadyTower.new()
	var fixture_script: Script = fixture_source.get_script()
	fixture_source.free()
	tower.set_script(fixture_script)
	var fixture := tower as BaseReturnReadyTower
	fixture.test_mode = false
	fixture.expedition_mode = false
	fixture.expedition_run_id = ""
	fixture.run_seed_override = RUN_SEED
	# 禁止帧间移动/交互；不阻止节点的真实 _ready 通知。
	fixture.process_mode = Node.PROCESS_MODE_DISABLED
	_check(not fixture.test_mode and not fixture.is_expedition(), "%s 必须进入非test_mode主场景入口分支" % label)
	var expected_scene := fixture.get_runtime_resume_scene_path(checkpoint)
	_check(expected_scene == "res://scenes/ExpeditionLevel01_3D.tscn", "%s combat检查点必须实际可续局，不能以空路由假绿" % label)
	var request_id := GameEntryFlow.request_gameplay_entry(reason, spawn_target)
	var completed_signals: Array = []
	fixture.generation_completed.connect(func(_snapshot: Dictionary) -> void: completed_signals.append(true))
	add_child(fixture)
	var context := fixture.get_entry_context_snapshot()
	_check(int(context.get("request_id", -1)) == request_id and str(context.get("reason", "")) == reason and str(context.get("spawn_target", "")) == spawn_target, "%s 真实_ready必须消费本用例入口意图" % label)
	for _index in range(2):
		await get_tree().process_frame
	if expects_resume:
		_check(fixture.resume_calls.size() == 1, "%s 必须触发一次续局路由" % label)
		if fixture.resume_calls.size() == 1:
			var routed := fixture.resume_calls[0]
			var resume_context := GameEntryFlow.peek_pending_entry()
			_check(str(routed.get("scene_path", "")) == expected_scene, "%s 必须路由回检查点所属远征" % label)
			_check(int(routed.get("request_id", 0)) > request_id and int(resume_context.get("request_id", -1)) == int(routed.get("request_id", 0)), "%s 必须登记真实的后续续局请求" % label)
			_check(str(resume_context.get("reason", "")) == GameEntryFlow.REASON_RUNTIME_RESTORE and str(resume_context.get("spawn_target", "")) == GameEntryFlow.SPAWN_SAVED_PROGRESS, "%s 续局入口必须声明runtime_restore/saved_progress" % label)
		_check(completed_signals.is_empty() and fixture.persistence_activation_calls == 0, "%s 续局必须在super生成与持久化前早退" % label)
		_check((fixture.get("_runtime_departure_carry_snapshot") as Dictionary).is_empty(), "%s 普通续局不得冒充返城携带交接" % label)
	else:
		_check(fixture.resume_calls.is_empty() and GameEntryFlow.peek_pending_entry().is_empty(), "%s 显式失败返城不得再次resume或登记续局请求" % label)
		_check(completed_signals.size() == 1 and fixture.persistence_activation_calls == 1, "%s 必须穿过super完成生成并请求激活，不能早退假绿" % label)
		_check(fixture.player != null and str(fixture.get("_current_room_id")) == "facility", "%s 真实_ready必须落99F基地房间" % label)
		if fixture.player != null:
			_check(fixture.player.global_position.distance_to(TowerDescent3D.FACILITY_LOGOUT_SPAWN) <= POSITION_EPSILON, "%s 不得恢复旧战斗坐标" % label)
		_check(fixture.run_seed == RUN_SEED and str(fixture.get("_run_id")) != str(checkpoint.get("run_id", "")), "%s 返城不得继承旧战斗seed/run_id" % label)
		for field in ["_runtime_restore_snapshot", "_runtime_base_restore_snapshot", "_runtime_carry_restore_snapshot"]:
			_check((fixture.get(field) as Dictionary).is_empty(), "%s 不得选择旧世界/基地/撤离恢复通道%s" % [label, field])
		var carry := fixture.get("_runtime_departure_carry_snapshot") as Dictionary
		var insurance := fixture.get("_insurance") as InsuranceModule
		_check(insurance != null, "%s 必须真实创建保险模块" % label)
		if pending.is_empty():
			_check(_same_value(carry, checkpoint), "%s 无pending保险时必须完整选择旧检查点所有权交接" % label)
			_check(not bool(fixture.get("_pending_insurance_return_restore")), "%s 无pending保险不得伪造死亡返还待提交态" % label)
			if fixture.player != null and insurance != null:
				var before_ownership := _read_runtime_state_without_capture(fixture)
				# 实测生产所有权恢复，但不调用写盘激活、不注册provider。
				fixture.call("_restore_carried_ownership", carry, false)
				var inventory := fixture.get("_inventory") as InventoryModule
				_check(inventory != null and _same_value(inventory.get_slot(0), (checkpoint.get("inventory_slots", []) as Array)[0]), "%s 返城携带物必须保留实例身份与数量" % label)
				_check(_same_value(insurance.get_slots_snapshot(), checkpoint.get("insurance_slots", [])), "%s 无pending保险时旧保险格所有权仍须保留" % label)
				_assert_runtime_state_unchanged(before_ownership, _read_runtime_state_without_capture(fixture), "%s 所有权交接不得改房间/世界/位置" % label)
		else:
			_check(carry.is_empty(), "%s pending保险存在时必须阻止旧combat携带快照覆盖" % label)
			_check(bool(fixture.get("_pending_insurance_return_restore")), "%s pending保险必须进入待原子提交态" % label)
			var inventory := fixture.get("_inventory") as InventoryModule
			_check(inventory != null and inventory.get_item_count("probe_abort_carry") == 0 and inventory.get_item_count("probe_pending_insurance") == 0, "%s 旧combat背包不得复活，pending保险不得复制进背包" % label)
			if insurance != null:
				var expected_slots: Array[Dictionary] = [{}, pending[0].duplicate(true)]
				_check(_same_value(insurance.get_slots_snapshot(), expected_slots), "%s pending保险必须保留原金色格索引/实例/数量/时间，且旧保险格不得复活" % label)
	_check(not bool(fixture.get("_runtime_persistence_active")), "%s 隔离探针不得激活自动持久化" % label)
	_assert_runtime_state_unchanged(profile_before, BaseManager.get_profile_snapshot(), "%s 入口选择及保险投影不得结算/清空原检查点或pending" % label)
	fixture.queue_free()
	await get_tree().process_frame
	GameEntryFlow.set("_pending_context", {})


func _probe_checkpoint_restore(rotation: int, fault: String, accepts_world: bool, label: String) -> void:
	BaseManager.data = BaseData.new()
	var profile_before := BaseManager.get_profile_snapshot()
	_check(not GameTimeManager.clock_running, "%s 全局时钟必须暂停" % label)
	_check(BaseManager.force_save_failure_for_test and BaseManager.get("_runtime_checkpoint_provider") == null, "%s 必须复用写盘禁用且无provider的隔离fixture" % label)
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	tower.process_mode = Node.PROCESS_MODE_DISABLED
	# 启动只选择布局朝向；不让 _ready 自动消费待测的完整快照。
	tower.set("_runtime_restore_snapshot", {"world_state": {"expedition_global_rotation_deg": rotation}})
	add_child(tower)
	for _index in range(2):
		await get_tree().process_frame
	var room_by_id := tower.get("_room_by_id") as Dictionary
	var start := room_by_id.get("start") as DungeonRoom3D
	var old_room := room_by_id.get("room_01") as DungeonRoom3D
	_check(tower.player != null and start != null and old_room != null, "%s 必须真实创建玩家、入口和旧房间" % label)
	if tower.player == null or start == null or old_room == null:
		tower.queue_free()
		await get_tree().process_frame
		return
	var plan := (tower.get("_floor_plan_snapshots") as Dictionary).get(0, {}) as Dictionary
	_check(int(plan.get("expedition_global_rotation_deg", -1)) == rotation, "%s 运行布局朝向必须正确" % label)
	var world := tower.call("_build_runtime_world_save_snapshot") as Dictionary
	var progress := {
		"visited": not old_room.visited, "cleared": not old_room.cleared,
		"spawned": true, "key_spawned": true, "key_unclaimed": false,
		"event_resolved": true, "event_combat": true,
	}
	(world["room_progress"] as Dictionary)["room_01"] = progress
	var ground_item := {"id": "probe_rejected_ground", "type": "material", "item_instance_id": label + ":ground"}
	var poison_position := old_room.global_position + Vector3.UP * 0.05
	var segment := {
		"visited": bool(progress["visited"]), "cleared": false,
		"room_light_on": not old_room.is_room_light_on(),
		"enemies": [{
			"persistent_id": label + ":enemy", "enemy_kind": "melee_chaser",
			"hp": 7, "max_hp": 11, "position": [poison_position.x, poison_position.y, poison_position.z],
			"enemy_data": {"enemy_type": "melee_chaser", "persistent_id": label + ":enemy", "floor": 1},
		}],
		"ground_items": [{"item_data": ground_item, "position": [poison_position.x, poison_position.y, poison_position.z]}],
		"room_keys": [{"room_id": "room_01", "position": [poison_position.x, poison_position.y, poison_position.z]}],
		"containers": {}, "alive_count": 1, "wave_established": true,
		"reserved_spawns": [], "wave_queue": [], "wave_number": 1, "wave_total": 1,
	}
	(world["segment_runtime_state"] as Dictionary)["room_01"] = segment
	(world["narrative_spawned_keys"] as Dictionary)[label + ":narrative_key"] = true
	var poisoned_edges := {}
	for edge in (tower.get("_open_edges") as Dictionary):
		poisoned_edges[edge] = not bool((tower.get("_open_edges") as Dictionary)[edge])
	poisoned_edges[_edge_key("start", "facility")] = false
	if accepts_world:
		# 正向只证明segment存储恢复；保持邻房关闭，避免混入额外实体流送事务。
		poisoned_edges[_edge_key("start", "room_01")] = false
	var potion := BaseShopService.ensure_item_instance((ItemRegistry.get_instance().get_item("item_health_potion") as Dictionary).duplicate(true))
	var insured := BaseShopService.ensure_item_instance((ItemRegistry.get_instance().get_item("item_health_potion") as Dictionary).duplicate(true))
	var quick := BaseShopService.ensure_item_instance((ItemRegistry.get_instance().get_item("item_battery_s") as Dictionary).duplicate(true))
	var backpack := BaseShopService.ensure_item_instance((ItemRegistry.get_instance().get_item("equipment_backpack_2") as Dictionary).duplicate(true))
	var weapon := BaseShopService.ensure_item_instance((ItemRegistry.get_instance().get_item("weapon_rifle") as Dictionary).duplicate(true))
	var secondary := BaseShopService.ensure_item_instance((ItemRegistry.get_instance().get_item("weapon_rifle") as Dictionary).duplicate(true))
	_check(not potion.is_empty() and not insured.is_empty() and not quick.is_empty() and not backpack.is_empty() and not weapon.is_empty() and not secondary.is_empty(), "%s 所有权样本必须来自真实注册表" % label)
	var inventory_slots: Array[Dictionary] = [{"item": potion, "count": 3, "slot": 0}]
	for _index in range(11):
		inventory_slots.append({})
	var merchant_stock := {
		"schema": "run_merchant_stock_v1",
		"stocks": {"probe_old_merchant": [{"offer_id": "probe_old_merchant:0", "item": {"id": "item_health_potion", "type": "consumable", "price": 17}}]},
	}
	var stock_validator := RunMerchantService.new()
	_check(stock_validator.restore_stock_snapshot(merchant_stock), "%s 旧货架必须是可恢复样本，不能靠无效数据假绿" % label)
	var saved_position := start.global_position + Vector3(1.0, 0.05, 1.0) if accepts_world else poison_position
	var snapshot := RunPersistenceService.finalize_runtime_snapshot({
		"scope": "combat", "runtime_map_id": "expedition_01", "run_seed": RUN_SEED,
		"run_id": label + ":run", "current_room_id": "room_01", "current_floor_index": 0,
		"player_position": [saved_position.x, saved_position.y, saved_position.z], "player_hp": 42,
		"inventory_capacity": 12, "inventory_slots": inventory_slots,
		"insurance_capacity": 2,
		"insurance_slots": [{"item": insured, "count": 2, "insured_at": 22, "insurance_slot": 0}, {}],
		"equipped_backpack_item": backpack, "equipped_weapon_items": [weapon, secondary], "active_weapon_slot": 1,
		"quick_item_slots": [{"item": quick, "count": 1, "slot": 0}, {}],
		"flashlight_module_id": "basic", "flashlight_charge_ratio": 0.37,
		# run_value 是魂余额的 HUD 镜像；currency_changed 会同步它，不能构造两个独立余额。
		"room_key_count": 4, "run_currency": 777, "run_value": 777, "kills": 5,
		"edge_states": poisoned_edges, "merchant_stock": merchant_stock,
		"trade_extraction_unlocked": true, "trade_extraction_room_id": "room_01",
		"world_state": world,
	})
	match fault:
		"missing_id":
			(snapshot["world_state"] as Dictionary)["floor_layout_ids"] = {}
		"bad_id":
			(snapshot["world_state"] as Dictionary)["floor_layout_ids"] = {"0": "probe_wrong_layout"}
		"bad_rotation":
			(snapshot["world_state"] as Dictionary)["expedition_global_rotation_deg"] = 0
	_check(bool(tower.call("_expedition_checkpoint_layout_matches", snapshot)) == accepts_world, "%s 样本必须命中预期布局门禁" % label)
	var original := snapshot.duplicate(true)
	var before := _read_runtime_state_without_capture(tower)
	var edges_before := (tower.get("_open_edges") as Dictionary).duplicate(true)
	var narrative_before := (tower.get("_narrative_spawned_keys") as Dictionary).duplicate(true)
	_check(not _same_value((before["dictionaries"] as Dictionary)["segment_runtime_state"], world["segment_runtime_state"]), "%s segment投毒必须区别于现场" % label)
	_check(not _same_value(edges_before, poisoned_edges), "%s edge投毒必须区别于现场" % label)
	_check(not bool(tower.get("_runtime_persistence_active")), "%s 恢复前persistence必须关闭" % label)
	var inventory_before := tower.get("_inventory") as InventoryModule
	_check(inventory_before != null and not _same_value(inventory_before.get_slots_snapshot(), original["inventory_slots"]), "%s 携带样本必须区别于初始背包，不能以未执行恢复假绿" % label)
	_check(not str(weapon.get("weapon_instance_id", "")).is_empty() and str(weapon.get("weapon_instance_id", "")) != str(secondary.get("weapon_instance_id", "")), "%s 主副武器必须是不同真实实例" % label)
	# 不替换任何 restore/ownership 函数，也不调用只测 world 的替代入口。
	tower.call("_restore_runtime_save_snapshot", snapshot)
	_check_checkpoint_ownership(tower, original, label)
	_assert_runtime_state_unchanged(original, snapshot, "%s 原快照及嵌套对象不可变" % label)
	_check(str(tower.get("_current_room_id")) == "start", "%s combat恢复必须落入口而非旧room_01" % label)
	var expected_position := saved_position if accepts_world else start.global_position + Vector3.UP * 0.05
	_check(tower.player.global_position.distance_to(expected_position) <= POSITION_EPSILON, "%s 必须遵守%s落点，不使用旧战斗位置" % [label, "有效入口坐标" if accepts_world else "拒绝后的入口安全点"])
	var expected_edges := poisoned_edges.duplicate(true) if accepts_world else edges_before.duplicate(true)
	expected_edges[_edge_key("start", "facility")] = true
	_assert_runtime_state_unchanged(expected_edges, tower.get("_open_edges") as Dictionary, "%s edge仅允许永久建筑边强制开启" % label)
	var merchant := tower.get("_merchant_service") as RunMerchantService
	_check(merchant != null and not bool(tower.get("_merchant_stock_restore_failed")), "%s 商人恢复不得靠样本格式失败假绿" % label)
	if merchant != null:
		var expected_stock := merchant_stock if accepts_world else {"schema": "run_merchant_stock_v1", "stocks": {}}
		_assert_runtime_state_unchanged(expected_stock, merchant.export_stock_snapshot(), "%s 商人货架%s" % [label, "正向恢复" if accepts_world else "不得回灌"])
	_check(bool(tower.get("_trade_extraction_unlocked")) == accepts_world, "%s trade解锁必须与世界接受结果一致" % label)
	_check(str(tower.get("_trade_extraction_room_id")) == ("room_01" if accepts_world else ""), "%s trade房间必须与世界接受结果一致" % label)
	_check((tower.get("_conditional_extractions") as Dictionary).has("TRADE") == accepts_world, "%s trade实体必须与世界接受结果一致" % label)
	if accepts_world:
		_check(old_room.visited == bool(progress["visited"]) and old_room.cleared == bool(progress["cleared"]), "%s 有效快照必须真实恢复room_01进度" % label)
		for field in ["_spawned_rooms", "_spawned_key_rooms", "_resolved_event_rooms", "_event_combat_rooms"]:
			_check((tower.get(field) as Dictionary).has("room_01"), "%s 有效快照必须恢复%s" % [label, field])
		_assert_runtime_state_unchanged(world["segment_runtime_state"] as Dictionary, tower.get("_segment_runtime_state") as Dictionary, "%s 有效快照必须恢复segment存储" % label)
		_assert_runtime_state_unchanged(world["narrative_spawned_keys"] as Dictionary, tower.get("_narrative_spawned_keys") as Dictionary, "%s 有效快照必须恢复叙事钥匙登记" % label)
	else:
		var after := _read_runtime_state_without_capture(tower)
		_assert_runtime_state_unchanged(before["rooms"] as Dictionary, after["rooms"] as Dictionary, "%s 房间身份、进度和详情不得回灌" % label)
		_assert_runtime_state_unchanged(before["dictionaries"] as Dictionary, after["dictionaries"] as Dictionary, "%s segment、生成/钥匙/事件标记与计划不得回灌" % label)
		_assert_runtime_state_unchanged((before["entities"] as Dictionary)["rooms"] as Dictionary, (after["entities"] as Dictionary)["rooms"] as Dictionary, "%s 现场enemy、掉落和地面钥匙不得替换或新增" % label)
		_assert_runtime_state_unchanged(narrative_before, tower.get("_narrative_spawned_keys") as Dictionary, "%s 叙事钥匙登记不得回灌" % label)
	_check(not bool(tower.get("_runtime_persistence_active")) and BaseManager.get("_runtime_checkpoint_provider") == null and not bool(BaseManager.get("_runtime_checkpoint_dirty")), "%s 真实恢复不得激活persistence、注册provider或排队写盘" % label)
	_assert_runtime_state_unchanged(profile_before, BaseManager.get_profile_snapshot(), "%s 内存档案不得被恢复链改写" % label)
	tower.queue_free()
	await get_tree().process_frame
	_assert_runtime_state_unchanged(profile_before, BaseManager.get_profile_snapshot(), "%s 场景卸载不得写回检查点" % label)
	_check(BaseManager.get("_runtime_checkpoint_provider") == null and not bool(BaseManager.get("_runtime_checkpoint_dirty")) and str(BaseManager.get("_pending_runtime_reason")).is_empty(), "%s 场景卸载后仍不得遗留provider或写盘请求" % label)
	_check(not GameTimeManager.clock_running, "%s 全局时钟必须仍暂停" % label)
	print("EXPEDITION_CHECKPOINT_RESTORE_CASE case=%s accepts_world=%s persistence=false" % [label, str(accepts_world)])


func _check_checkpoint_ownership(tower: TowerDescent3D, snapshot: Dictionary, label: String) -> void:
	var inventory := tower.get("_inventory") as InventoryModule
	var insurance := tower.get("_insurance") as InsuranceModule
	var quick := tower.get("_quick_inventory") as InventoryModule
	_check(inventory != null and insurance != null and quick != null, "%s 必须使用真实所有权模块" % label)
	if inventory != null:
		_check(inventory.get_capacity() == int(snapshot["inventory_capacity"]), "%s 背包容量必须恢复" % label)
		_check(_same_value(inventory.get_slots_snapshot(), snapshot["inventory_slots"]), "%s 整格背包必须保留实例/数量/空格，不能叠加保底物品" % label)
	if insurance != null:
		_check(_same_value(insurance.get_slots_snapshot(), snapshot["insurance_slots"]), "%s 保险格必须保留实例/数量/槽位/时间" % label)
	if quick != null:
		_check(_same_value(quick.get_slots_snapshot(), snapshot["quick_item_slots"]), "%s 快捷栏所有权必须恢复" % label)
	_check(_same_value(tower.player.get_equipped_backpack_item(), snapshot["equipped_backpack_item"]), "%s 装备背包实例必须恢复" % label)
	for slot_index in range(2):
		var expected := (snapshot["equipped_weapon_items"] as Array)[slot_index] as Dictionary
		var actual := tower.player.get_equipped_weapon_item_for_slot(slot_index)
		_check(not str(expected.get("weapon_instance_id", "")).is_empty() and str(actual.get("weapon_instance_id", "")) == str(expected.get("weapon_instance_id", "")), "%s 武器槽%d必须保留真实枪械实例" % [label, slot_index])
		_check(str(actual.get("item_instance_id", "")) == str(expected.get("item_instance_id", "")) and str(actual.get("id", "")) == str(expected.get("id", "")), "%s 武器槽%d必须保留物品身份" % [label, slot_index])
	_check(tower.player.get_active_weapon_slot() == int(snapshot["active_weapon_slot"]), "%s 激活武器槽必须恢复" % label)
	_check(tower.player.current_hp == int(snapshot["player_hp"]), "%s HP必须恢复" % label)
	var flashlight := tower.player.get_node_or_null("PlayerFlashlight3D")
	_check(flashlight != null and is_equal_approx(float(flashlight.call("get_charge_ratio")), float(snapshot["flashlight_charge_ratio"])), "%s 手电电量必须恢复" % label)
	_check(GameManager.currency == int(snapshot["run_currency"]) and int(tower.get("_room_key_count")) == int(snapshot["room_key_count"]), "%s 魂和携带钥匙必须恢复，区别于禁止回灌的地面钥匙" % label)
	_check(int(tower.get("_run_value")) == int(snapshot["run_value"]) and int(tower.get("_kills")) == int(snapshot["kills"]), "%s 携带价值和击杀统计必须恢复" % label)


func _read_runtime_state_without_capture(tower: TowerDescent3D) -> Dictionary:
	var room_by_id := tower.get("_room_by_id") as Dictionary
	var rooms: Dictionary = {}
	for room_id_value in room_by_id.keys():
		var room := room_by_id[room_id_value] as DungeonRoom3D
		if room == null or not is_instance_valid(room):
			rooms[str(room_id_value)] = {"instance_id": 0, "missing": true}
			continue
		rooms[str(room_id_value)] = {
			"instance_id": room.get_instance_id(),
			"visited": room.visited,
			"cleared": room.cleared,
			"room_light_on": room.is_room_light_on(),
			"snapshot": room.get_room_snapshot(),
		}
	return {
		"rooms": rooms,
		"entities": {
			"player": _read_player_state(tower),
			"rooms": _read_live_entity_state(tower, room_by_id),
		},
		"dictionaries": {
			"segment_runtime_state": (tower.get("_segment_runtime_state") as Dictionary).duplicate(true),
			"spawned_rooms": (tower.get("_spawned_rooms") as Dictionary).duplicate(true),
			"spawned_key_rooms": (tower.get("_spawned_key_rooms") as Dictionary).duplicate(true),
			"resolved_event_rooms": (tower.get("_resolved_event_rooms") as Dictionary).duplicate(true),
			"event_combat_rooms": (tower.get("_event_combat_rooms") as Dictionary).duplicate(true),
			"floor_plan_snapshots": (tower.get("_floor_plan_snapshots") as Dictionary).duplicate(true),
			"records": (tower.get("_records") as Array).duplicate(true),
			"generated_floor_indices": (tower.get("_generated_floor_indices") as Array).duplicate(true),
			"current_room_id": str(tower.get("_current_room_id")),
			"runtime_persistence_active": bool(tower.get("_runtime_persistence_active")),
		},
	}


func _read_player_state(tower: TowerDescent3D) -> Dictionary:
	var player := tower.player
	if player == null or not is_instance_valid(player):
		return {"missing": true}
	return {
		"instance_id": player.get_instance_id(),
		"position": player.global_position if player.is_inside_tree() else player.position,
		"velocity": player.velocity,
		"input_locked": player.input_locked,
		"combat_enabled": player.combat_enabled,
		"process_mode": player.process_mode,
	}


func _read_live_entity_state(tower: TowerDescent3D, room_by_id: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for room_id_value in room_by_id.keys():
		var room_id := str(room_id_value)
		var room := room_by_id[room_id_value] as DungeonRoom3D
		var room_state := {"enemies": [], "ground_loot": [], "room_keys": []}
		for value in (tower.get("_enemy_nodes_by_room") as Dictionary).get(room_id, []):
			if is_instance_valid(value) and value is Enemy3D:
				var enemy := value as Enemy3D
				(room_state["enemies"] as Array).append({
					"instance_id": enemy.get_instance_id(),
					"state": enemy.export_runtime_state(),
				})
		if room != null:
			for value in get_tree().get_nodes_in_group("ground_loot_3d"):
				if value is GroundLootPickup3D and room.is_ancestor_of(value):
					var loot := value as GroundLootPickup3D
					(room_state["ground_loot"] as Array).append({
						"instance_id": loot.get_instance_id(),
						"item_data": loot.item_data.duplicate(true),
						"position": loot.global_position,
						"queued_for_deletion": loot.is_queued_for_deletion(),
					})
			for value in get_tree().get_nodes_in_group("room_key_pickup_3d"):
				if value is RoomKeyPickup3D and room.is_ancestor_of(value):
					var key := value as RoomKeyPickup3D
					(room_state["room_keys"] as Array).append({
						"instance_id": key.get_instance_id(),
						"room_id": key.room_id,
						"position": key.global_position,
						"queued_for_deletion": key.is_queued_for_deletion(),
					})
		result[room_id] = room_state
	return result


func _assert_runtime_state_unchanged(before: Dictionary, after: Dictionary, label: String) -> void:
	var differences: Array[String] = []
	_collect_runtime_state_differences(before, after, "$", differences)
	if differences.is_empty():
		_check(true, "%s 状态保持不变" % label)
		return
	print("%s 状态差异字段: %s" % [label, "; ".join(differences)])
	_check(false, "%s 不得改变：%s" % [label, "; ".join(differences)])


func _collect_runtime_state_differences(a: Variant, b: Variant, path: String, differences: Array[String]) -> void:
	if a is Dictionary and b is Dictionary:
		var left := a as Dictionary
		var right := b as Dictionary
		for key in left.keys():
			var child_path := "%s.%s" % [path, str(key)]
			if not right.has(key):
				differences.append("%s 缺失(原=%s)" % [child_path, str(left[key])])
			else:
				_collect_runtime_state_differences(left[key], right[key], child_path, differences)
		for key in right.keys():
			if not left.has(key):
				differences.append("%s 新增(现=%s)" % ["%s.%s" % [path, str(key)], str(right[key])])
		return
	if a is Array and b is Array:
		var left := a as Array
		var right := b as Array
		if left.size() != right.size():
			differences.append("%s 长度 %d -> %d" % [path, left.size(), right.size()])
		for index in range(mini(left.size(), right.size())):
			_collect_runtime_state_differences(left[index], right[index], "%s[%d]" % [path, index], differences)
		return
	if not _same_value(a, b):
		differences.append("%s: %s -> %s" % [path, str(a), str(b)])


func _same_value(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		var left := a as Dictionary
		var right := b as Dictionary
		if left.size() != right.size():
			return false
		for key in left:
			if not right.has(key) or not _same_value(left[key], right[key]):
				return false
		return true
	if a is Array and b is Array:
		var left := a as Array
		var right := b as Array
		if left.size() != right.size():
			return false
		for index in range(left.size()):
			if not _same_value(left[index], right[index]):
				return false
		return true
	return a == b


func _opposite(side: String) -> String:
	return str({"north": "south", "south": "north", "east": "west", "west": "east"}.get(side, "INVALID"))


func _array_vec2(raw: Array) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1])) if raw.size() == 2 else Vector2.INF


func _half_turn(point: Vector3) -> Vector3:
	return Vector3(-point.x, point.y, -point.z)


func _angle_matches(actual: float, expected: float) -> bool:
	return absf(wrapf(actual - expected, -180.0, 180.0)) <= 0.01


func _without_geometry(room: Dictionary) -> Dictionary:
	var content := room.duplicate(true)
	for field in ["position", "rotation_deg", "connection_ports", "spawn_placements", "authored_layout_instances"]:
		content.erase(field)
	return content


func _check_plan_rotation() -> void:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(OTHER_LEVEL_SOURCE))
	_check(source is Dictionary, "测试关卡99必须能读取真实 L1")
	var other_id := str((source as Dictionary).get("level_id", "")) if source is Dictionary else ""
	_check(other_id == OTHER_LEVEL_ID, "测试关卡99真实 ID 必须为99，不得误测空计划")
	if other_id.is_empty():
		return
	var total_ports := 0
	var total_spawns := 0
	var total_art := 0
	for index in range(PLAN_SEED_COUNT):
		var seed_value := RUN_SEED + index
		var old_plan := FloorPlanGenerator.generate_from_level_plan("expedition_01", 0, seed_value, 0)
		var new_plan := FloorPlanGenerator.generate_from_level_plan("expedition_01", 0, seed_value, 180)
		var label := "seed=%d" % seed_value
		for plan in [old_plan, new_plan]:
			_check(not plan.is_empty() and bool(plan.get("valid", false)), "%s 新旧版都必须有效" % label)
			_check(not bool(plan.get("used_fallback", true)), "%s 新旧版都不得 fallback" % label)
			_check((plan.get("rooms", []) as Array).size() == 13, "%s 新旧版都必须13房" % label)
		_check(int(old_plan.get("expedition_global_rotation_deg", -1)) == 0, "%s 旧版朝向标记" % label)
		_check(int(new_plan.get("expedition_global_rotation_deg", -1)) == 180, "%s 新版朝向标记" % label)
		_check(not str(new_plan.get("layout_id", "")).is_empty() and str(new_plan.get("layout_id", "")) != str(old_plan.get("layout_id", "")), "%s 新旧 layout_id 必须不同" % label)
		_check(_same_value(new_plan, FloorPlanGenerator.generate_from_level_plan("expedition_01", 0, seed_value)), "%s 默认必须等于显式180" % label)
		_check(_same_value(old_plan, FloorPlanGenerator.generate_from_level_plan("expedition_01", 0, seed_value, 0)), "%s 旧版重复生成必须确定" % label)
		_check(_same_value(new_plan, FloorPlanGenerator.generate_from_level_plan("expedition_01", 0, seed_value, 180)), "%s 新版重复生成必须确定" % label)
		_check(str(new_plan.get("entry_side", "")) == _opposite(str(old_plan.get("entry_side", ""))), "%s entry_side 应翻转" % label)
		_check(str(new_plan.get("exit_side", "")) == _opposite(str(old_plan.get("exit_side", ""))), "%s exit_side 应翻转" % label)
		for field in ["main_path_keys", "reward_slots", "monster_drop_table", "area_budget", "room_size_catalog", "terminal_mode", "attempt_count"]:
			_check(_same_value(old_plan.get(field), new_plan.get(field)), "%s 顶层内容 %s 不得改变" % [label, field])
		var pivot := _plan_room(old_plan, "entry").get("position", Vector2.INF) as Vector2
		_check(pivot.is_finite(), "%s 入口旋转中心必须有效" % label)
		var entry_port := _named_record(_plan_room(new_plan, "entry").get("connection_ports", []) as Array, "target", "room_01")
		_check(not entry_port.is_empty() and str(entry_port.get("side", "")) == "north", "%s entry必须有指向room01的north端口" % label)
		_check((_plan_room(new_plan, "room_01").get("position", Vector2.INF) as Vector2).y < pivot.y, "%s room01必须位于entry北侧" % label)
		for old_value in old_plan.get("rooms", []):
			var old_room := old_value as Dictionary
			var key := str(old_room.get("key", ""))
			var new_room := _plan_room(new_plan, key)
			var room_label := "%s %s" % [label, key]
			_check(not new_room.is_empty(), "%s 新版不得丢房" % room_label)
			_check((new_room.get("position", Vector2.INF) as Vector2).distance_to(pivot * 2.0 - (old_room.get("position", Vector2.INF) as Vector2)) <= POSITION_EPSILON, "%s center必须绕entry刚体翻转" % room_label)
			_check(_angle_matches(float(new_room.get("rotation_deg", -999)), float(old_room.get("rotation_deg", 0)) + 180.0), "%s rotation必须增加180" % room_label)
			_check(_same_value(_without_geometry(old_room), _without_geometry(new_room)), "%s 房间尺寸/拓扑/内容必须不变" % room_label)
			var old_ports := old_room.get("connection_ports", []) as Array
			var new_ports := new_room.get("connection_ports", []) as Array
			_check(old_ports.size() == new_ports.size(), "%s 端口数必须不变" % room_label)
			var seen_ports := {}
			for value in old_ports:
				var port := value as Dictionary
				var peer := _named_record(new_ports, "port_id", str(port.get("port_id", "")))
				var port_id := str(port.get("port_id", ""))
				_check(not port_id.is_empty() and not seen_ports.has(port_id), "%s 端口ID必须唯一" % room_label)
				seen_ports[port_id] = true
				_check(not peer.is_empty(), "%s 端口ID必须稳定" % room_label)
				_check(_array_vec2(peer.get("position_m", []) as Array).distance_to(-_array_vec2(port.get("position_m", []) as Array)) <= POSITION_EPSILON, "%s 端口局部坐标必须翻转" % room_label)
				_check(_array_vec2(peer.get("outward", []) as Array).distance_to(-_array_vec2(port.get("outward", []) as Array)) <= 0.001, "%s 端口法线必须翻转" % room_label)
				_check(str(peer.get("side", "")) == _opposite(str(port.get("side", ""))), "%s 端口side必须翻转" % room_label)
				_check(is_equal_approx(float(peer.get("lane_m", INF)), -float(port.get("lane_m", 0))), "%s 端口lane必须翻转" % room_label)
				var old_content := port.duplicate(true)
				var new_content := peer.duplicate(true)
				for field in ["position_m", "outward", "side", "lane_m"]:
					old_content.erase(field)
					new_content.erase(field)
				_check(_same_value(old_content, new_content), "%s 端口连接内容必须不变" % room_label)
				if key == "entry" and str(port.get("target", "")) == "room_01":
					_check(str(port.get("side", "")) == "south" and str(peer.get("side", "")) == "north", "%s entry主路必须由south变north" % label)
				total_ports += 1
			var old_spawns := old_room.get("spawn_placements", []) as Array
			var new_spawns := new_room.get("spawn_placements", []) as Array
			_check(old_spawns.size() == new_spawns.size(), "%s 刷怪盒数量必须不变" % room_label)
			for placement_index in range(mini(old_spawns.size(), new_spawns.size())):
				var placement := old_spawns[placement_index] as Dictionary
				var peer := new_spawns[placement_index] as Dictionary
				_check(_array_vec2(peer.get("center_m", []) as Array).distance_to(-_array_vec2(placement.get("center_m", []) as Array)) <= POSITION_EPSILON, "%s 刷怪盒局部center必须翻转" % room_label)
				_check(_angle_matches(float(peer.get("rotation_deg", -999)), float(placement.get("rotation_deg", 0)) + 180), "%s 刷怪盒角度必须翻转" % room_label)
				var expected := placement.duplicate(true)
				expected["center_m"] = peer.get("center_m")
				expected["rotation_deg"] = peer.get("rotation_deg")
				_check(_same_value(expected, peer), "%s 刷怪盒ID/尺寸/内容必须不变" % room_label)
				total_spawns += 1
			total_art += _check_authored_rotation(old_room, new_room, room_label)
		var other_old := FloorPlanGenerator.generate_from_level_plan(other_id, 0, seed_value, 0)
		var other_new := FloorPlanGenerator.generate_from_level_plan(other_id, 0, seed_value, 180)
		_check(not other_old.is_empty() and bool(other_old.get("valid", false)) and str(other_old.get("level_id", "")) == OTHER_LEVEL_ID, "%s 测试关卡99不得空跑" % label)
		_check(_same_value(other_old, other_new) and _same_value(other_old, FloorPlanGenerator.generate_from_level_plan(other_id, 0, seed_value)), "%s 测试关卡99不得受朝向参数影响" % label)
	_check(total_ports > 0 and total_spawns > 0 and total_art > 0, "端口/刷怪盒/可匹配美术判据不得空跑")
	print("EXPEDITION_ROTATION_SAMPLES seeds=%d ports=%d spawns=%d authored=%d" % [PLAN_SEED_COUNT, total_ports, total_spawns, total_art])


func _named_record(records: Array, field: String, id: String) -> Dictionary:
	for value in records:
		var record := value as Dictionary
		if str(record.get(field, "")) == id:
			return record
	return {}


func _check_authored_rotation(old_room: Dictionary, new_room: Dictionary, label: String) -> int:
	var old_art := old_room.get("authored_layout_instances", []) as Array
	var new_art := new_room.get("authored_layout_instances", []) as Array
	_check(old_art.size() == new_art.size(), "%s 美术实例数量必须不变" % label)
	var matched := 0
	var eligible := 0
	var old_components := {}
	var new_components := {}
	for value in old_art:
		var component := str((value as Dictionary).get("component_id", ""))
		old_components[component] = int(old_components.get(component, 0)) + 1
	for value in new_art:
		var component := str((value as Dictionary).get("component_id", ""))
		new_components[component] = int(new_components.get(component, 0)) + 1
	_check(_same_value(old_components, new_components), "%s 所有美术组件内容及数量必须不变" % label)
	for value in old_art:
		var instance := value as Dictionary
		var name := str(instance.get("name", ""))
		# 通用壳体实例名编码世界方位/坐标，不是跨朝向稳定ID；稳定母版名全部核对。
		if name.begins_with("GenericShell_") or name.begins_with("FLOOR_") or name.begins_with("CORNER_") or name.begins_with("WALL_") or name.begins_with("DOORWALL_"):
			continue
		eligible += 1
		var peer := _named_record(new_art, "name", name)
		_check(not peer.is_empty(), "%s 稳定名美术 %s 不得丢失" % [label, name])
		if peer.is_empty():
			continue
		_check((peer.get("position", Vector3.INF) as Vector3).distance_to(_half_turn(instance.get("position", Vector3.INF) as Vector3)) <= POSITION_EPSILON, "%s 美术 %s 局部坐标必须刚体翻转" % [label, name])
		_check(_angle_matches(float(peer.get("rotation_y_deg", -999)), float(instance.get("rotation_y_deg", 0)) + 180), "%s 美术 %s 角度必须增加180" % [label, name])
		var expected := instance.duplicate(true)
		expected["position"] = peer.get("position")
		expected["rotation_y_deg"] = peer.get("rotation_y_deg")
		_check(_same_value(expected, peer), "%s 美术 %s 组件/缩放/内容必须不变" % [label, name])
		matched += 1
	_check(matched == eligible, "%s 所有稳定名美术实例必须被比较" % label)
	return matched


func _check_runtime_records(
	tower: TowerDescent3D, rooms: Dictionary, plan: Dictionary,
	born: Vector3, rotation: int, label: String
) -> Dictionary:
	var result := {"rooms": {}, "born": born, "safe_root": Transform3D.IDENTITY}
	var minimap_records := tower.minimap.get("_record_by_id") as Dictionary
	for value in plan.get("rooms", []):
		var spec := value as Dictionary
		var id := str(spec.get("id", ""))
		var room := rooms.get(id) as DungeonRoom3D
		_check(room != null, "%s %s 必须有运行时房间" % [label, id])
		if room == null:
			continue
		_check(room.basis.is_equal_approx(Basis.IDENTITY), "%s %s 房间root必须恒等，不能再叠加整房旋转" % [label, id])
		var planar := spec.get("position", Vector2.INF) as Vector2
		_check(room.global_position.distance_to(Vector3(planar.x, 0.0, planar.y)) <= POSITION_EPSILON, "%s %s 运行时中心必须匹配0层计划" % [label, id])
		var record := minimap_records.get(id, {}) as Dictionary
		_check(not record.is_empty(), "%s %s 小地图record不得缺失" % [label, id])
		_check((record.get("position", Vector3.INF) as Vector3).distance_to(room.global_position) <= POSITION_EPSILON, "%s %s 小地图中心必须与运行时一致" % [label, id])
		_check(_same_value(record.get("custom_dimensions"), room.get_dimensions()), "%s %s 小地图尺寸必须一致" % [label, id])
		_check(_angle_matches(float(record.get("rotation_deg", -999)), float(spec.get("rotation_deg", 0))), "%s %s 小地图角度必须一致" % [label, id])
		_check(str(record.get("floor_layout_id", "")) == str(plan.get("layout_id", "")), "%s %s 小地图布局指纹必须一致" % [label, id])
		_check(_same_value(record.get("door_targets"), room.door_targets) and _same_value(record.get("doors"), room.doors), "%s %s 小地图门向/拓扑必须一致" % [label, id])
		_check(_same_value(record.get("connection_ports"), room.connection_ports), "%s %s 小地图端口必须一致" % [label, id])
		var art_root := room.get_node_or_null("SafeRoomArtRoot" if id == "start" else "AuthoredLayoutArtRoot") as Node3D
		_check(art_root != null, "%s %s 必须有静态美术根" % [label, id])
		var pieces := {}
		if art_root != null:
			for child in art_root.get_children():
				var piece := child as Node3D
				if piece != null and not piece.scene_file_path.is_empty():
					pieces[str(piece.name)] = {"transform": art_root.transform * piece.transform, "source": piece.scene_file_path}
		(result["rooms"] as Dictionary)[id] = {
			"center": room.global_position, "basis": room.basis,
			"art_root": art_root.transform if art_root != null else Transform3D.IDENTITY,
			"pieces": pieces,
		}
	var start := rooms.get("start") as DungeonRoom3D
	_check(start != null, "%s 缺少安全屋" % label)
	if start == null:
		return result
	var front := "north" if rotation == 180 else "south"
	var rear := "east" if rotation == 180 else "west"
	_check(start.doors.size() == 2 and front in start.doors and rear in start.doors, "%s 安全屋实体门向必须匹配0/180" % label)
	_check(str(start.door_targets.get(front, "")) == "room_01", "%s 安全屋前门必须通room01" % label)
	var spawn_offset := Vector3(0.0, 0.05, -4.0 if rotation == 180 else 4.0)
	_check(born.distance_to(start.global_position + spawn_offset) <= POSITION_EPSILON, "%s 玩家首帧出生必须在安全屋朝前门4m" % label)
	_check(tower.player != null and start.contains_world_position(tower.player.global_position), "%s 物理稳定后玩家仍须在安全屋" % label)
	_check(str(tower.get("_current_room_id")) == "start", "%s 开局房间归属必须是start" % label)
	var art := start.get_node_or_null("SafeRoomArtRoot") as Node3D
	if art == null:
		art = start.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	_check(art != null, "%s 安全屋静态root必须存在" % label)
	if art == null:
		return result
	result["safe_root"] = art.transform
	var slots: Array[Transform3D] = []
	for child in art.get_children():
		var piece := child as Node3D
		if piece != null and (piece.scene_file_path.contains("wall_door") or piece.scene_file_path.contains("door_wall")):
			slots.append(art.transform * piece.transform)
	_check(slots.size() == start.connection_ports.size(), "%s 安全屋门墙槽数量必须匹配端口" % label)
	var used_slots := {}
	for value in start.connection_ports:
		var port := value as Dictionary
		var side := str(port.get("side", ""))
		var expected := _port_world(start, port)
		var raw := _array_vec2(port.get("outward", []) as Array)
		var outward := Vector3(raw.x, 0.0, raw.y).normalized()
		var matches := 0
		for index in range(slots.size()):
			var slot := slots[index]
			var normal := slot.basis.z.normalized()
			if normal.dot(slot.origin) < 0.0:
				normal = -normal
			if Vector2(slot.origin.x, slot.origin.z).distance_to(Vector2(start.to_local(expected).x, start.to_local(expected).z)) <= POSITION_EPSILON and normal.dot(outward) >= 0.999:
				matches += 1
				_check(not used_slots.has(index), "%s 安全屋门墙不得重复匹配" % label)
				used_slots[index] = true
		_check(matches == 1, "%s 安全屋%s端口必须唯一匹配实体门墙位置和法线" % [label, side])
		var door := start.get_door_node(side)
		_check(door != null, "%s 安全屋%s必须有运行时门" % [label, side])
		if door != null:
			_check(Vector2(door.global_position.x, door.global_position.z).distance_to(Vector2(expected.x, expected.z)) <= POSITION_EPSILON, "%s 安全屋%s门扇与端口必须重合" % [label, side])
	return result


func _check_runtime_rotation(old: Dictionary, current: Dictionary) -> void:
	var old_rooms := old.get("rooms", {}) as Dictionary
	var new_rooms := current.get("rooms", {}) as Dictionary
	_check(old_rooms.size() == 13 and new_rooms.size() == 13, "新旧运行时刚体比较不得空跑")
	var pivot := (old_rooms.get("start", {}) as Dictionary).get("center", Vector3.INF) as Vector3
	var turn := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	for id in old_rooms:
		var a := old_rooms[id] as Dictionary
		var b := new_rooms.get(id, {}) as Dictionary
		_check((b.get("center", Vector3.INF) as Vector3).distance_to(pivot + _half_turn((a.get("center", Vector3.INF) as Vector3) - pivot)) <= POSITION_EPSILON, "%s 新旧运行时中心必须刚体翻转" % id)
		_check(_same_value(a.get("basis"), b.get("basis")), "%s 新旧房间root基底必须保持恒等" % id)
		_check((b.get("art_root", Transform3D.IDENTITY) as Transform3D).is_equal_approx(turn * (a.get("art_root", Transform3D.IDENTITY) as Transform3D)), "%s 静态美术根完整transform必须旋转180" % id)
		var old_pieces := a.get("pieces", {}) as Dictionary
		var new_pieces := b.get("pieces", {}) as Dictionary
		_check(not old_pieces.is_empty() and old_pieces.size() == new_pieces.size(), "%s 静态组件比较不得空跑或丢组件" % id)
		for name in old_pieces:
			var first := old_pieces[name] as Dictionary
			var second := new_pieces.get(name, {}) as Dictionary
			_check(str(first.get("source", "")) == str(second.get("source", "")), "%s %s 静态组件来源必须不变" % [id, name])
			_check((second.get("transform", Transform3D.IDENTITY) as Transform3D).is_equal_approx(turn * (first.get("transform", Transform3D.IDENTITY) as Transform3D)), "%s %s 静态组件完整局部transform必须刚体旋转" % [id, name])
	_check((current.get("safe_root", Transform3D.IDENTITY) as Transform3D).is_equal_approx(turn * (old.get("safe_root", Transform3D.IDENTITY) as Transform3D)), "安全屋静态root完整transform必须随新旧180翻转")
	_check((current.get("born", Vector3.INF) as Vector3).distance_to(pivot + _half_turn((old.get("born", Vector3.INF) as Vector3) - pivot)) <= POSITION_EPSILON, "新旧玩家出生位置必须刚体翻转")


func _check_checkpoint_contract(
	tower: TowerDescent3D, rooms: Dictionary, plan: Dictionary, rotation: int, label: String
) -> void:
	_check(int(tower.call("_expedition_rotation_for_checkpoint", {})) == 180, "%s 空新局选择180" % label)
	_check(int(tower.call("_expedition_rotation_for_checkpoint", {"world_state": {}})) == 0, "%s 缺字段旧档选择0" % label)
	for angle in [0, 180]:
		_check(int(tower.call("_expedition_rotation_for_checkpoint", {"world_state": {"expedition_global_rotation_deg": angle}})) == angle, "%s 显式朝向字段必须保留%d" % [label, angle])
	var state := tower.call("_build_runtime_world_save_snapshot") as Dictionary
	_check(state.has("expedition_global_rotation_deg") and int(state.get("expedition_global_rotation_deg", -1)) == rotation, "%s 保存必须带朝向字段" % label)
	_check(str((state.get("floor_layout_ids", {}) as Dictionary).get("0", "")) == str(plan.get("layout_id", "")), "%s 保存必须带0层指纹" % label)
	var good := {"world_state": state.duplicate(true)}
	_check(bool(tower.call("_expedition_checkpoint_layout_matches", good)), "%s 匹配的朝向和0层指纹必须接受" % label)
	var missing_rotation := good.duplicate(true)
	(missing_rotation["world_state"] as Dictionary).erase("expedition_global_rotation_deg")
	_check(bool(tower.call("_expedition_checkpoint_layout_matches", missing_rotation)) == (rotation == 0), "%s 缺朝向字段仅接受旧布局" % label)
	var missing_id := good.duplicate(true)
	(missing_id["world_state"] as Dictionary)["floor_layout_ids"] = {}
	_check(not bool(tower.call("_expedition_checkpoint_layout_matches", missing_id)), "%s 缺0层指纹必须拒绝世界恢复，不以旧朝向代替几何证明" % label)
	var bad_id := good.duplicate(true)
	(bad_id["world_state"] as Dictionary)["floor_layout_ids"] = {"0": "probe_wrong_layout", "2": str(plan.get("layout_id", ""))}
	var bad_rotation := good.duplicate(true)
	(bad_rotation["world_state"] as Dictionary)["expedition_global_rotation_deg"] = 180 - rotation
	var invalid_rotation := good.duplicate(true)
	(invalid_rotation["world_state"] as Dictionary)["expedition_global_rotation_deg"] = 90
	var wrong_layer := good.duplicate(true)
	(wrong_layer["world_state"] as Dictionary)["floor_layout_ids"] = {"0": "probe_wrong_layout", "99": str(plan.get("layout_id", ""))}
	var rejected: Array = [missing_id, bad_id, bad_rotation, invalid_rotation, wrong_layer]
	if rotation == 180:
		rejected.append(missing_rotation)
	for value in rejected:
		var bad := value as Dictionary
		var poisoned := {}
		for id in rooms:
			var room := rooms[id] as DungeonRoom3D
			poisoned[id] = {"visited": not room.visited, "cleared": not room.cleared, "spawned": true, "key_spawned": true, "event_resolved": true, "event_combat": true}
		(bad["world_state"] as Dictionary)["room_progress"] = poisoned
		_check(not bool(tower.call("_expedition_checkpoint_layout_matches", bad)), "%s 错误0层指纹/朝向必须被门禁拒绝" % label)
		var before := _read_runtime_state_without_capture(tower)
		_check(not bool(tower.call("_restore_runtime_world_save_snapshot", bad)), "%s 错误布局恢复必须返回false" % label)
		var after := _read_runtime_state_without_capture(tower)
		_assert_runtime_state_unchanged(before, after, "%s 拒绝快照" % label)
	_check(not bool(tower.get("_runtime_persistence_active")), "%s 检查点测试不得启动自动持久化" % label)


func _plan_room(plan: Dictionary, key: String) -> Dictionary:
	for value in plan.get("rooms", []):
		var room := value as Dictionary
		if str(room.get("key", "")) == key:
			return room
	return {}


func _collect_rooms(block: Node3D) -> Dictionary:
	var rooms := {}
	if block == null:
		return rooms
	for child in block.get_children():
		var room := child as DungeonRoom3D
		if room != null:
			rooms[room.room_id] = room
	return rooms


func _port_world(room: DungeonRoom3D, port: Dictionary) -> Vector3:
	var raw := port.get("position_m", []) as Array
	return room.to_global(Vector3(float(raw[0]), 0.0, float(raw[1])))


func _port_outward(port: Dictionary) -> Vector2:
	var raw := port.get("outward", []) as Array
	return Vector2(float(raw[0]), float(raw[1])).normalized()


func _edge_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
