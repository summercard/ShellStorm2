extends Node

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const TEST_PATH := "user://verify_expedition_resume_entry.json"
const RUN_SEED := 77001199
const MAX_WAIT_FRAMES := 180
const WATCHDOG_SECONDS := 90.0
const EXPECTED_TRANSITION_SECONDS := 1.15

var _original_save_path := ""
var _original_data: BaseData = null
var _original_clock_running := true
var _fixture: TowerDescent3D = null
var _expedition: TowerDescent3D = null
var _gameplay_started_count := 0
var _transition_finished_transform := Transform3D.IDENTITY
var _transition_finished_fov := 0.0
var _saw_transition_finished := false
var _finished := false


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("EXPEDITION_RESUME_ENTRY_SKIP: headless 明确跳过真实远征与真实 MainEntryScreen3D 装配，不计为通过")
		get_tree().quit(0)
		return
	get_tree().create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog_timeout)
	await _run_real_resume_verification()


func _run_real_resume_verification() -> void:
	var failures: Array[String] = []
	_original_save_path = BaseManager.save_path
	_original_data = BaseManager.data
	_original_clock_running = GameTimeManager.clock_running
	_cleanup_save()
	BaseManager.save_path = TEST_PATH
	BaseManager.data = BaseData.new()
	BaseManager.data.tutorial_completed = true
	GameTimeManager.set_clock_running(false)

	_fixture = await _spawn_fixture()
	if _fixture == null:
		failures.append("test_mode=true 远征 fixture 装配失败")
		await _finish(failures)
		return
	var combat_room := _first_combat_room(_fixture)
	if combat_room == null:
		failures.append("fixture 没有可用战斗房，无法构造 combat snapshot")
		await _finish(failures)
		return
	var combat_room_id := combat_room.room_id
	_prepare_fixture_loadout(_fixture)
	var combat_position := combat_room.global_position + Vector3(1.25, 0.05, -1.1)
	_fixture.player.global_position = combat_position
	_fixture.player.velocity = Vector3.ZERO
	# 用已清理战斗房记录进度，避免菜单不变性取样混入活敌人的移动。
	combat_room.cleared = true
	_fixture._spawned_rooms[combat_room_id] = true
	_fixture._current_room_id = ""
	_fixture._on_room_entered(combat_room)
	await get_tree().physics_frame
	var saved_snapshot: Dictionary = _fixture.build_runtime_save_snapshot()
	saved_snapshot["scope"] = "combat"
	saved_snapshot["current_room_id"] = combat_room_id
	saved_snapshot["player_position"] = [combat_position.x, combat_position.y, combat_position.z]
	saved_snapshot["runtime_map_id"] = "expedition_01"
	if not bool(saved_snapshot.get("valid", false)):
		failures.append("fixture build_runtime_save_snapshot 没有生成 valid snapshot")
	if str(saved_snapshot.get("current_room_id", "")) != combat_room_id:
		failures.append("fixture snapshot 的 current_room_id 不是战斗房：%s" % saved_snapshot)
	if not _position_array_matches(saved_snapshot.get("player_position", []), combat_position):
		failures.append("fixture snapshot 没有保留旧战斗房玩家坐标")
	var saved_world := saved_snapshot.get("world_state", {}) as Dictionary
	var saved_segments := saved_world.get("segment_runtime_state", {}) as Dictionary
	var saved_combat_state := saved_segments.get(combat_room_id, {}) as Dictionary
	if not bool(saved_combat_state.get("cleared", false)):
		failures.append("fixture snapshot 没有保存战斗房清理进度")
	if not BaseManager.set_active_run_checkpoint(saved_snapshot, "verify_expedition_resume_fixture"):
		failures.append("隔离 BaseManager 测试档写入 combat snapshot 失败")
	var expected_ownership := _ownership_signature(saved_snapshot)
	_fixture.queue_free()
	_fixture = null
	await get_tree().process_frame
	await get_tree().process_frame

	# 先登记 cold main，再经生产 helper 生成 runtime_restore 请求；远征实例本身保持生产模式。
	GameEntryFlow.request_main_entry(GameEntryFlow.REASON_COLD_START)
	var source_context: Dictionary = GameEntryFlow.consume_main_scene_entry()
	var source_before := source_context.duplicate(true)
	var restore_request_id: int = int(GameEntryFlow.request_runtime_restore_entry(source_context))
	if source_context != source_before:
		failures.append("远征续档测试的 runtime_restore helper 修改了 source context")
	if restore_request_id <= 0:
		failures.append("远征续档测试没有得到有效 runtime_restore request_id")
	_expedition = (load(EXPEDITION_SCENE) as PackedScene).instantiate() as TowerDescent3D
	if _expedition == null:
		failures.append("生产远征场景实例化失败")
		await _finish(failures)
		return
	_expedition.test_mode = false
	_expedition.gameplay_started.connect(_on_gameplay_started)
	add_child(_expedition)
	var restored := await _wait_for_real_menu_and_restore()
	if not restored:
		failures.append("限时等待内没有得到真实远征恢复与真实主页菜单")
	else:
		var restored_state := _state_signature(_expedition)
		_verify_restored_state(
			saved_snapshot,
			expected_ownership,
			combat_room_id,
			restored_state,
			failures,
		)
		var menu_baseline := restored_state.duplicate(true)
		_verify_presenting_menu(_expedition, menu_baseline, failures)
		await _verify_settings_and_start(_expedition, menu_baseline, failures)

	await _verify_gameplay_entry_without_menu(failures)
	await _finish(failures)


func _spawn_fixture() -> TowerDescent3D:
	var packed := load(EXPEDITION_SCENE) as PackedScene
	if packed == null:
		return null
	var tower := packed.instantiate() as TowerDescent3D
	if tower == null:
		return null
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	for _frame in 12:
		await get_tree().process_frame
	return tower


func _first_combat_room(tower: TowerDescent3D) -> DungeonRoom3D:
	for room_value in tower._room_by_id.values():
		var room := room_value as DungeonRoom3D
		if room != null and room.room_type == "COMBAT":
			return room
	return null


func _prepare_fixture_loadout(tower: TowerDescent3D) -> void:
	var inventory := tower.get_inventory_module()
	inventory.clear_all()
	inventory.set_capacity(14)
	inventory.add_item(ItemRegistry.get_instance().get_item("item_health_potion"), 2)
	inventory.add_item(ItemRegistry.get_instance().get_item("item_battery_l"), 1)
	tower.player.clear_all_equipped_weapons()
	tower.player.equip_weapon_item_to_slot(
		BaseShopService.ensure_item_instance(ItemRegistry.get_instance().get_item("weapon_pistol")), 0
	)
	tower.player.equip_weapon_item_to_slot(
		BaseShopService.ensure_item_instance(ItemRegistry.get_instance().get_item("weapon_shotgun")), 1
	)
	tower.player.switch_weapon_slot(1)
	tower.player.equip_backpack_item(
		BaseShopService.ensure_item_instance(ItemRegistry.get_instance().get_item("equipment_backpack_2"))
	)


func _wait_for_real_menu_and_restore() -> bool:
	for _frame in MAX_WAIT_FRAMES:
		await get_tree().process_frame
		if _expedition == null or not is_instance_valid(_expedition):
			return false
		var entry := _expedition.get("_main_entry_screen") as MainEntryScreen3D
		var start_room := _expedition._room_by_id.get("start") as DungeonRoom3D
		if (
			entry != null
			and is_instance_valid(entry)
			and bool(entry.get_entry_snapshot().get("presenting", false))
			and str(_expedition._current_room_id) == "start"
			and bool(_expedition.get("_runtime_persistence_active"))
			and start_room != null
			and _expedition.player.global_position.distance_to(
				start_room.global_position + Vector3.UP * 0.05
			) <= 0.15
		):
			return true
	return false


func _verify_restored_state(
	saved_snapshot: Dictionary,
	expected_ownership: Dictionary,
	combat_room_id: String,
	restored: Dictionary,
	failures: Array[String],
) -> void:
	if str(restored.get("current_room_id", "")) != "start":
		failures.append("combat snapshot 恢复后没有落到 start 安全房")
	var start_room := _expedition._room_by_id.get("start") as DungeonRoom3D
	if start_room == null:
		failures.append("真实远征没有 start 安全房")
	else:
		var expected_position := start_room.global_position + Vector3.UP * 0.05
		if not _positions_equal(_vector_from_array(restored.get("player_position", [])), expected_position, 0.15):
			failures.append("combat snapshot 恢复后玩家没有落在 start 安全房中心")
	for key in ["inventory_slots", "equipped_weapon_items", "equipped_backpack_item", "run_id"]:
		if expected_ownership.get(key) != restored.get(key):
			failures.append("续档没有恢复 %s：expected=%s actual=%s" % [key, expected_ownership.get(key), restored.get(key)])
	var saved_world := saved_snapshot.get("world_state", {}) as Dictionary
	var saved_segments := saved_world.get("segment_runtime_state", {}) as Dictionary
	var saved_combat_state := saved_segments.get(combat_room_id, {}) as Dictionary
	var restored_segments := (restored.get("world_state", {}) as Dictionary).get("segment_runtime_state", {}) as Dictionary
	var restored_combat_state := restored_segments.get(combat_room_id, {}) as Dictionary
	if bool(saved_combat_state.get("cleared", false)) != bool(restored_combat_state.get("cleared", false)):
		failures.append("关卡进度没有恢复战斗房 cleared 状态")
	if str(saved_snapshot.get("run_id", "")) != str(restored.get("run_id", "")):
		failures.append("续档没有保留 run_id")


func _verify_presenting_menu(
	tower: TowerDescent3D, baseline: Dictionary, failures: Array[String]
) -> void:
	var entry := tower.get("_main_entry_screen") as MainEntryScreen3D
	if entry == null:
		failures.append("非 headless 真实路径没有安装 MainEntryScreen3D")
		return
	var entry_state := entry.get_entry_snapshot()
	if not bool(entry_state.get("presenting", false)):
		failures.append("真实 MainEntryScreen3D 没有处于 presenting")
	if not bool(entry_state.get("uses_live_player", false)):
		failures.append("主页菜单没有使用真实玩家")
	if not bool(entry_state.get("uses_gameplay_camera", false)):
		failures.append("主页菜单没有使用同一台 gameplay camera")
	if not is_equal_approx(float(entry_state.get("transition_duration_s", 0.0)), EXPECTED_TRANSITION_SECONDS):
		failures.append("真实主页运镜时长不是约 1.15s：%s" % entry_state.get("transition_duration_s"))
	if not bool(entry_state.get("gameplay_hud_hidden", false)) or tower.get_node("HUD").visible:
		failures.append("主页展示期间 HUD 没有隐藏")
	if not tower.player.input_locked:
		failures.append("主页展示期间玩家输入没有锁定")
	if _gameplay_started_count != 0:
		failures.append("主页展示期间 gameplay_started 不应触发：%d" % _gameplay_started_count)
	if entry.get_node_or_null("Screen/MenuPanel/Margin/Content/StartButton") == null:
		failures.append("真实主页缺少开始按钮")
	if entry.get_node_or_null("Screen/MenuPanel/Margin/Content/SettingsButton") == null:
		failures.append("真实主页缺少设置按钮")
	_compare_state(baseline, _state_signature(tower), "主页展示前后恢复状态", failures)


func _verify_settings_and_start(
	tower: TowerDescent3D, baseline: Dictionary, failures: Array[String]
) -> void:
	var entry := tower.get("_main_entry_screen") as MainEntryScreen3D
	if entry == null:
		return
	var camera := tower.player.camera
	var gameplay_transform: Transform3D = entry.get("_gameplay_camera_transform")
	var gameplay_fov := float(entry.get("_gameplay_fov"))
	var gameplay_attributes := entry.get("_saved_camera_attributes") as CameraAttributes
	var start_button := entry.get_node("Screen/MenuPanel/Margin/Content/StartButton") as Button
	var settings_button := entry.get_node("Screen/MenuPanel/Margin/Content/SettingsButton") as Button
	if not entry.transition_finished.is_connected(_on_entry_transition_finished):
		entry.transition_finished.connect(_on_entry_transition_finished)
	settings_button.pressed.emit()
	await get_tree().process_frame
	var settings := entry.find_child("PauseOverlay", true, false) as PauseMenu3D
	if settings == null or not settings.is_pause_open():
		failures.append("settings 按钮 pressed 后没有打开真实设置覆盖层")
	else:
		settings.resume_button.pressed.emit()
		await get_tree().process_frame
		if not bool(entry.get_entry_snapshot().get("presenting", false)):
			failures.append("关闭设置后主页展示状态被错误结束")
	_compare_state(baseline, _state_signature(tower), "设置按钮操作后的状态", failures)
	if not tower.player.input_locked:
		failures.append("设置关闭后开始前玩家输入锁没有保持")
	var transition_started_msec := Time.get_ticks_msec()
	var transition_start_transform: Transform3D = camera.transform
	start_button.pressed.emit()
	var saw_transition := false
	var transition_elapsed_s := 0.0
	for frame_index in MAX_WAIT_FRAMES:
		await get_tree().process_frame
		var state := entry.get_entry_snapshot()
		if bool(state.get("transitioning", false)):
			saw_transition = true
			if frame_index > 3 and camera.transform.origin.distance_to(transition_start_transform.origin) <= 0.01:
				failures.append("真实主页过渡开始后 camera 没有发生运镜")
		if not bool(state.get("presenting", false)) and _gameplay_started_count > 0:
			transition_elapsed_s = float(Time.get_ticks_msec() - transition_started_msec) / 1000.0
			break
	if transition_elapsed_s <= 0.0:
		transition_elapsed_s = float(Time.get_ticks_msec() - transition_started_msec) / 1000.0
	# _finish_transition() 在 process 帧中把相机写回 gameplay 基准；随后真实远征的
	# _physics_process() 会按正式玩法镜头契约重算一次姿态。必须跨过这一物理帧再验，
	# 否则会在「菜单已归还、玩法镜头尚未接管」的帧间隙采样出假红。
	await get_tree().physics_frame
	await get_tree().process_frame
	if not saw_transition:
		failures.append("开始按钮 pressed 没有进入真实主页过渡")
	if transition_elapsed_s < 0.90 or transition_elapsed_s > 2.20:
		failures.append("真实主页过渡没有保持约 1.15s：%.3fs" % transition_elapsed_s)
	if _gameplay_started_count != 1:
		failures.append("真实主页过渡后 gameplay_started 应为 1，实际 %d" % _gameplay_started_count)
	if entry.is_camera_override_active():
		failures.append("真实主页过渡后 camera override 未归还")
	if camera != tower.player.camera:
		failures.append("主页前后没有保持同一台 camera")
	# transition_finished 在 MainEntryScreen3D._finish_transition() 写回 gameplay 基准后
	# 立即发出。这个时刻是菜单和玩法的明确所有权交接点；交接后下一物理帧
	# 允许正式玩法镜头按墙体/楼板探测结果做正常动态微调，不能再拿旧基准硬比。
	if (
		not _saw_transition_finished
		or not _transforms_equal(_transition_finished_transform, gameplay_transform, 0.001)
		or not is_equal_approx(_transition_finished_fov, gameplay_fov)
	):
		print("ENTRY_CAMERA_DIAGNOSTIC transition_finished_transform=%s" % _transition_finished_transform)
		print("ENTRY_CAMERA_DIAGNOSTIC transition_finished_fov=%.6f saw=%s" % [_transition_finished_fov, _saw_transition_finished])
		print("ENTRY_CAMERA_DIAGNOSTIC expected_transform=%s" % gameplay_transform)
		print("ENTRY_CAMERA_DIAGNOSTIC expected_fov=%.6f" % gameplay_fov)
		failures.append("主页过渡交接时 camera 没有回到 gameplay 姿态")
	if camera.attributes != gameplay_attributes:
		failures.append("主页过渡后 camera attributes 没有归还")
	if tower.player.input_locked:
		failures.append("主页过渡后玩家输入锁没有归还")
	if not tower.get_node("HUD").visible:
		failures.append("主页过渡后 HUD 没有归还")
	_compare_state(baseline, _state_signature(tower), "主页过渡后的状态", failures)


func _verify_gameplay_entry_without_menu(failures: Array[String]) -> void:
	if _expedition != null and is_instance_valid(_expedition):
		BaseManager.unregister_runtime_checkpoint_provider(_expedition, false)
		_expedition.queue_free()
		_expedition = null
	await get_tree().process_frame
	await get_tree().process_frame
	BaseManager.clear_active_run_checkpoint("verify_clear_before_gameplay_entry")
	for reason in [
		GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT,
		GameEntryFlow.REASON_SCENE_REENTRY,
	]:
		_gameplay_started_count = 0
		GameEntryFlow.request_gameplay_entry(reason, GameEntryFlow.SPAWN_SAVED_PROGRESS)
		var packed := load(EXPEDITION_SCENE) as PackedScene
		var gameplay_tower := packed.instantiate() as TowerDescent3D
		gameplay_tower.test_mode = false
		gameplay_tower.run_seed_override = RUN_SEED
		gameplay_tower.gameplay_started.connect(_on_gameplay_started)
		add_child(gameplay_tower)
		for _frame in MAX_WAIT_FRAMES:
			await get_tree().process_frame
			if _gameplay_started_count > 0:
				break
		var entry := gameplay_tower.get("_main_entry_screen") as MainEntryScreen3D
		if entry != null:
			failures.append("%s gameplay 入口错误显示主页菜单" % reason)
		if _gameplay_started_count != 1:
			failures.append("%s gameplay_started 应为 1，实际 %d" % [reason, _gameplay_started_count])
		if gameplay_tower.player.input_locked:
			failures.append("%s gameplay 入口结束后玩家输入仍被锁定" % reason)
		BaseManager.unregister_runtime_checkpoint_provider(gameplay_tower, false)
		gameplay_tower.queue_free()
		await get_tree().process_frame


func _state_signature(tower: TowerDescent3D) -> Dictionary:
	var snapshot: Dictionary = tower.build_runtime_save_snapshot()
	var plan := tower._floor_plan_snapshots.get(tower.get_expedition_layer_index(), {}) as Dictionary
	var world_state := _stable_world_state(snapshot.get("world_state", {}))
	return {
		"current_room_id": str(snapshot.get("current_room_id", "")),
		"current_floor_index": int(snapshot.get("current_floor_index", -1)),
		"player_position": snapshot.get("player_position", []).duplicate(true),
		"inventory_slots": snapshot.get("inventory_slots", []).duplicate(true),
		"equipped_weapon_items": snapshot.get("equipped_weapon_items", []).duplicate(true),
		"equipped_backpack_item": (snapshot.get("equipped_backpack_item", {}) as Dictionary).duplicate(true),
		"world_state": world_state,
		"run_id": str(snapshot.get("run_id", "")),
		"layout_id": str(plan.get("layout_id", "")),
	}


func _stable_world_state(value: Variant) -> Dictionary:
	var world_state := (value as Dictionary).duplicate(true) if value is Dictionary else {}
	var segments := world_state.get("segment_runtime_state", {}) as Dictionary
	for room_id in segments.keys():
		var segment := segments[room_id] as Dictionary
		segment.erase("captured_at_msec")
		segments[room_id] = segment
	world_state["segment_runtime_state"] = segments
	return world_state


func _ownership_signature(snapshot: Dictionary) -> Dictionary:
	return {
		"inventory_slots": snapshot.get("inventory_slots", []).duplicate(true),
		"equipped_weapon_items": snapshot.get("equipped_weapon_items", []).duplicate(true),
		"equipped_backpack_item": (snapshot.get("equipped_backpack_item", {}) as Dictionary).duplicate(true),
		"run_id": str(snapshot.get("run_id", "")),
	}


func _compare_state(expected: Dictionary, actual: Dictionary, label: String, failures: Array[String]) -> void:
	for key in ["current_room_id", "current_floor_index", "inventory_slots", "equipped_weapon_items", "equipped_backpack_item", "world_state", "run_id", "layout_id"]:
		if expected.get(key) != actual.get(key):
			failures.append("%s 改变了 %s：expected=%s actual=%s" % [label, key, expected.get(key), actual.get(key)])
	var expected_position := _vector_from_array(expected.get("player_position", []))
	var actual_position := _vector_from_array(actual.get("player_position", []))
	if not _positions_equal(expected_position, actual_position, 0.12):
		failures.append("%s 改变了玩家位置：expected=%s actual=%s" % [label, expected_position, actual_position])


func _vector_from_array(value: Variant) -> Vector3:
	if not value is Array or (value as Array).size() < 3:
		return Vector3.INF
	return Vector3(float((value as Array)[0]), float((value as Array)[1]), float((value as Array)[2]))


func _position_array_matches(value: Variant, expected: Vector3) -> bool:
	return _positions_equal(_vector_from_array(value), expected, 0.01)


func _positions_equal(actual: Vector3, expected: Vector3, tolerance: float) -> bool:
	return actual.is_finite() and expected.is_finite() and actual.distance_to(expected) <= tolerance


func _transforms_equal(actual: Transform3D, expected: Transform3D, tolerance: float) -> bool:
	return (
		actual.origin.distance_to(expected.origin) <= tolerance
		and actual.basis.x.distance_to(expected.basis.x) <= tolerance
		and actual.basis.y.distance_to(expected.basis.y) <= tolerance
		and actual.basis.z.distance_to(expected.basis.z) <= tolerance
	)


func _on_gameplay_started(_room_id: String) -> void:
	_gameplay_started_count += 1


func _on_entry_transition_finished() -> void:
	if _expedition == null or not is_instance_valid(_expedition):
		return
	var camera := _expedition.player.camera
	_transition_finished_transform = camera.transform
	_transition_finished_fov = camera.fov
	_saw_transition_finished = true


func _finish(failures: Array[String]) -> void:
	if _finished:
		return
	_finished = true
	if _fixture != null and is_instance_valid(_fixture):
		_fixture.queue_free()
	if _expedition != null and is_instance_valid(_expedition):
		BaseManager.unregister_runtime_checkpoint_provider(_expedition, false)
		_expedition.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	BaseManager.save_path = _original_save_path
	BaseManager.data = _original_data
	GameTimeManager.set_clock_running(_original_clock_running)
	_cleanup_save()
	if failures.is_empty():
		print("EXPEDITION_RESUME_ENTRY_OK: real expedition restore, real MainEntryScreen3D settings/start transition, state invariants and gameplay-only entries")
	else:
		for failure in failures:
			push_error(failure)
	get_tree().quit(1 if not failures.is_empty() else 0)


func _on_watchdog_timeout() -> void:
	if _finished:
		return
	_finished = true
	push_error("远征续档真实场景专项超过 %.1fs 限时，判定失败而不是假绿" % WATCHDOG_SECONDS)
	if _fixture != null and is_instance_valid(_fixture):
		_fixture.queue_free()
	if _expedition != null and is_instance_valid(_expedition):
		BaseManager.unregister_runtime_checkpoint_provider(_expedition, false)
		_expedition.queue_free()
	BaseManager.save_path = _original_save_path
	BaseManager.data = _original_data
	GameTimeManager.set_clock_running(_original_clock_running)
	_cleanup_save()
	get_tree().quit(1)


func _cleanup_save() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", TEST_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
