extends Node
## 必须由 Runner 在 Autoload 之前隔离 APPDATA/user://，不能直接用正式档启动。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const BASE_SCENE := preload("res://scenes/TowerDescent3D.tscn")
const KEY := MainStoryChapter3D.KEY_RARE_EARTH
const PHASE := TowerDescent3D.MAIN_STORY_EXTRACTION_KEY
var tower: TowerDescent3D
var failures: Array[String] = []
var checks := 0
var successes := 0
var failures_emitted := 0
var original_data: BaseData
var original_path := ""
var original_save_failure := false
var scene_resources: Array[Resource] = []


func check(ok: bool, message: String) -> void:
	checks += 1
	print("MAIN_STORY_INTEGRATION_CHECK ", checks, " ok=", ok, " ", message, " ms=", Time.get_ticks_msec())
	if not ok:
		failures.append(message)
		print("MAIN_STORY_INTEGRATION_FAIL ", message)


func _ready() -> void:
	if not OS.get_environment("SHELLSTORM_MAIN_STORY_ISOLATED").is_empty() and "main_story_integration" in ProjectSettings.globalize_path("user://"):
		await _run()
	else:
		push_error("主线集成验收拒绝启动：必须在 Autoload 前隔离并显式标记 user://")
		get_tree().quit(2)


func _run() -> void:
	original_data = BaseManager.data
	original_path = BaseManager.save_path
	original_save_failure = BaseManager.force_save_failure_for_test
	BaseManager.data = BaseData.new()
	BaseManager.save_path = "user://integration_%d.json" % Time.get_ticks_usec()
	BaseManager.force_save_failure_for_test = false
	NarrativeDirector.reset_for_test()
	NarrativeDirector.set_process(false)
	print("MAIN_STORY_INTEGRATION_BEGIN retain_real_scene_resources ms=", Time.get_ticks_msec())
	# 同一真实场景要装配两次；保留资源所有权，避免元数据查询后立即卸载并反复重读。
	_retain_real_scene_resources("res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01")
	print("MAIN_STORY_INTEGRATION_END retain_real_scene_resources count=", scene_resources.size(), " ms=", Time.get_ticks_msec())
	print("MAIN_STORY_INTEGRATION_BEGIN base_host")
	await _verify_base_host()
	print("MAIN_STORY_INTEGRATION_END base_host checks=", checks)
	_verify_profiles()
	print("MAIN_STORY_INTEGRATION_BEGIN expedition_instantiate")
	tower = SCENE.instantiate() as TowerDescent3D
	print("MAIN_STORY_INTEGRATION_END expedition_instantiate")
	tower.test_mode = true
	tower.force_main_story_for_test = true
	tower.run_seed_override = 77001199
	await _mount_real_scene(tower, "expedition")
	tower.set_process(false)
	tower.player.set_physics_process(false)
	var controller := tower.get_main_story_controller()
	check(controller != null and tower._main_story_host_ready, "正式远征01挂载并 setup controller")
	if controller == null:
		await _finish()
		return
	controller.set_process(false)
	check(tower._main_story_gameplay_started, "玩法开始事件已放行主线")
	tower._main_story_gameplay_started = false
	tower._sync_main_story_processing()
	check(not controller.is_processing(), "主菜单/读取页未释放时主线不处理")
	tower._main_story_gameplay_started = true
	for config in tower._map_fate_triggers._triggers:
		config.enabled = false
	var room := tower.get_main_story_room("boss") as DungeonRoom3D
	check(room != null, "正式计划有 Boss 房")
	if room == null:
		await _finish()
		return
	print("MAIN_STORY_INTEGRATION_BEGIN boss_room_build")
	room.ensure_shell_built()
	room.ensure_detail_built()
	print("MAIN_STORY_INTEGRATION_END boss_room_build")
	await get_tree().physics_frame
	tower._current_room_id = room.room_id
	tower.player.global_position = room.global_position + Vector3(5.0, 0.5, 5.0)
	tower._spawned_rooms[room.room_id] = true
	# 与正式进房同样启用 ACTIVE 流送，否则后续存档会按 DATA_ONLY 保留旧缓存。
	tower._update_room_streaming(room.room_id)
	print("MAIN_STORY_INTEGRATION_BEGIN enemy_gate")
	_verify_enemy_gate(room)
	print("MAIN_STORY_INTEGRATION_END enemy_gate checks=", checks)
	var config := {"id": "drop_boss", "chest_tier": "advanced", "mimic": true}
	var prepared := tower._prepare_story_boss_chest_config(room, config)
	check(not bool(prepared.get("mimic", true)), "首次首领箱禁拟态")
	var chest := room.spawn_runtime_chest(prepared, Vector2(3.0, 3.0))
	check(chest != null and room.chest_open_requested.is_connected(tower._on_chest_open_requested), "正式房间开箱信号接线")
	if chest == null:
		await _finish()
		return
	check(not bool(tower._story_chest_claim(room, chest).get("success", true)), "首领未败拒绝领取")
	var wrong := TreasureChest3D.new()
	wrong.configure({"id": "wrong_box", "chest_tier": "advanced"})
	check(not bool(tower._story_chest_claim(room, wrong).get("applicable", true)), "错箱不发主线钥匙")
	wrong.configure({"id": "drop_boss", "chest_tier": "normal"})
	check(not bool(tower._story_chest_claim(room, wrong).get("applicable", true)), "普通档Boss箱不发主线钥匙")
	tower.expedition_plan_id = "expedition_03"
	check(not bool(tower._story_chest_claim(room, chest).get("applicable", true)), "其他远征相同箱ID不发稀土钥匙")
	tower.expedition_plan_id = ""
	wrong.free()
	tower._boss_defeated_rooms[room.room_id] = true
	var before_story := BaseManager.get_main_story_snapshot()
	var before_checkpoint := BaseManager.get_active_run_checkpoint()
	var before_chests := room.get_persistent_detail_state("treasure_chests")
	var before_pending := room.get_pending_chest_grants()
	BaseManager.force_save_failure_for_test = true
	print("MAIN_STORY_EXPECTED_FAILURE_BEGIN claim_save")
	tower._on_chest_open_requested(room, chest)
	print("MAIN_STORY_EXPECTED_FAILURE_END claim_save")
	check(not chest.is_opened(), "领取保存失败不消耗箱子")
	check(room.get_pending_chest_grants() == before_pending, "领取失败撤销普通奖励 pending")
	check(room.get_persistent_detail_state("treasure_chests") == before_chests, "领取失败未改 opened 账")
	check(BaseManager.get_main_story_snapshot() == before_story and BaseManager.get_active_run_checkpoint() == before_checkpoint, "领取失败永久事实与 checkpoint 整体回滚")
	check(tower._main_story_auto_extraction.is_empty(), "领取失败不启动撤离")
	BaseManager.force_save_failure_for_test = false
	chest._player_in_range = true
	check(chest.perform_interaction(tower.player, {}), "真实交互信号触发首领箱领取")
	check(chest.is_opened(), "领取成功才 commit_opened")
	check(MainStoryProgress.key_state(BaseManager.get_main_story_snapshot(), KEY) == "acquired", "永久稀土钥匙已取得")
	var acquired_checkpoint := BaseManager.get_active_run_checkpoint()
	var frozen := ((acquired_checkpoint.get("world_state", {}) as Dictionary).get("segment_runtime_state", {}) as Dictionary).get(room.room_id, {}) as Dictionary
	check(bool((frozen.get("treasure_chests", {}) as Dictionary).get(chest.chest_id, {}).get("opened", false)), "领取同批存档含箱 opened")
	check(not (frozen.get("pending_chest_grants", {}) as Dictionary).get(chest.chest_id, {}).get("grants", []).is_empty(), "领取同批存档含普通奖励 pending，不丢物")
	check(bool(acquired_checkpoint.get(PHASE, {}).get("active", false)), "领取同批存档含撤离阶段")
	check(bool(tower._main_story_auto_extraction.get("active", false)), "实际取得后启动8秒倒计时")
	check(not tower.player.input_locked, "自动撤离不锁移动/战斗输入")
	check(bool(tower._prepare_story_boss_chest_config(room, config).get("mimic", false)), "已领取后普通拟态规则恢复")
	var revision := BaseManager.data.save_revision
	var duplicate := tower._story_chest_claim(room, chest)
	check(bool(duplicate.get("duplicate", false)) and BaseManager.data.save_revision == revision, "重复领取不写盘、不重发")
	var source := BaseManager.get_main_story_snapshot().get("keys", {}).get(KEY, {}).get("acquired_source", {}) as Dictionary
	check(bool(MainStoryProgress.validate_key_source(source).get("success", false)), "真实箱来源映射通过目录校验")
	check(str(source.get("runtime_chest_id", "")) == "drop_boss" and str(source.get("runtime_run_id", "")) == tower._run_id, "来源同时保留运行箱与行动身份")
	await get_tree().create_timer(chest.get_open_burst_delay() + 0.1, false).timeout
	check(room.get_pending_chest_grants().is_empty(), "普通奖励完成落地并清 pending")
	var ground_before := get_tree().get_nodes_in_group("ground_loot_3d").size()
	tower._on_chest_open_requested(room, chest)
	tower._resume_pending_chest_grants(room)
	check(get_tree().get_nodes_in_group("ground_loot_3d").size() == ground_before, "重复交互/补发不重复普通物资")
	print("MAIN_STORY_INTEGRATION_BEGIN snapshot_and_death checks=", checks, " ms=", Time.get_ticks_msec())
	_verify_snapshot_and_death()
	print("MAIN_STORY_INTEGRATION_END snapshot_and_death checks=", checks, " ms=", Time.get_ticks_msec())
	print("MAIN_STORY_INTEGRATION_BEGIN real_scene_reload")
	await _verify_real_scene_reload()
	print("MAIN_STORY_INTEGRATION_END real_scene_reload checks=", checks, " ms=", Time.get_ticks_msec())
	print("MAIN_STORY_INTEGRATION_BEGIN unique_settlement")
	_verify_unique_settlement()
	print("MAIN_STORY_INTEGRATION_END unique_settlement checks=", checks)
	await _finish()


func _retain_real_scene_resources(directory: String) -> void:
	for file_name in DirAccess.get_files_at(directory):
		if file_name.ends_with(".tscn"):
			var path := directory.path_join(file_name)
			var resource := load(path) as PackedScene
			check(resource != null, "真实远征资源可加载：%s" % file_name)
			if resource != null:
				scene_resources.append(resource)


func _mount_real_scene(scene: TowerDescent3D, stage: String) -> void:
	var signals := {"generated": false, "gameplay_ready": false}
	# 信号可能在 add_child 内同步发出；先接线并记状态，不能盲等已发出的信号。
	scene.generation_completed.connect(func(_snapshot: Dictionary) -> void: signals["generated"] = true, CONNECT_ONE_SHOT)
	scene.gameplay_started.connect(func(_room_id: String) -> void: signals["gameplay_ready"] = true, CONNECT_ONE_SHOT)
	print("MAIN_STORY_INTEGRATION_BEGIN ", stage, "_add_child ms=", Time.get_ticks_msec())
	add_child(scene)
	print("MAIN_STORY_INTEGRATION_END ", stage, "_add_child ms=", Time.get_ticks_msec())
	if not signals["generated"]:
		await scene.generation_completed
	print("MAIN_STORY_INTEGRATION_END ", stage, "_generation_completed ms=", Time.get_ticks_msec())
	if not signals["gameplay_ready"]:
		await scene.gameplay_started
	check(scene._main_story_host_ready and scene._main_story_gameplay_started, "%s真实装配与玩法释放屏障已完成" % stage)
	await get_tree().physics_frame
	print("MAIN_STORY_INTEGRATION_END ", stage, "_scene_ready ms=", Time.get_ticks_msec())


func _verify_profiles() -> void:
	var probe := TowerDescent3D.new()
	probe.test_mode = true
	check(probe._main_story_run_profile() == "disabled", "既有 test_mode 默认隔离")
	probe.force_main_story_for_test = true
	check(probe._main_story_run_profile() == "base", "塔楼默认 base profile")
	probe.expedition_mode = true
	probe.expedition_run_id = "expedition_03"
	check(probe._main_story_run_profile() == "disabled", "远征03不播3.2")
	probe.expedition_run_id = "expedition_01"
	check(probe._main_story_run_profile() == "database", "唯一映射远征01到 database")
	probe.free()


func _verify_enemy_gate(room: DungeonRoom3D) -> void:
	var configs: Array[Dictionary] = [{"enemy_type": "boss", "boss_content_id": "boss_monitor002", "hp": 100, "max_hp": 100, "persistent_id": "integration_monitor"}]
	var count := tower._spawn_enemy_batch(room, configs, true, false, [room.global_position])
	check(count == 1, "正式生成链生成显示器")
	var boss := tower.get_main_story_boss() as Enemy3D
	check(boss != null, "controller public Boss 查询命中正式实体")
	if boss == null:
		return
	boss.set_physics_process(false)
	var activation := boss.get_story_activation_snapshot()
	check(bool(activation.get("held", false)) and not bool(activation.get("started", true)), "AI第一帧之前已配置主线门闩")
	NarrativeDirector.bind_dungeon_for_test(tower)
	tower.get_main_story_controller()._process(0.0)
	check(NarrativeDirector.active_id() == MainStoryChapter3D.BOSS_ID, "实际Boss房就绪自动触发3.2而非只提供死接口")
	print("MAIN_STORY_EXPECTED_FAILURE_BEGIN boss_trigger_abort")
	NarrativeDirector.abort("integration_trigger_checked")
	print("MAIN_STORY_EXPECTED_FAILURE_END boss_trigger_abort")
	tower._configure_story_enemy(boss)
	boss.monitor_combat.tick_activation(10.0)
	check(not bool(boss.get_story_activation_snapshot().get("started", true)), "近距离也不能抢先自动激活")
	boss.monitor_combat.activation_completed = true
	tower._configure_story_enemy(boss)
	check(not bool(boss.get_story_activation_snapshot().get("held", true)), "已完成激活不重新 hold")
	boss.monitor_combat.activation_completed = false
	BaseManager.replace_narrative_history_for_test({MainStoryChapter3D.BOSS_ID: {"completed_count": 1}})
	tower._configure_story_enemy(boss)
	check(not bool(boss.get_story_activation_snapshot().get("held", true)), "已播3.2的后续 Boss 正常激活")
	BaseManager.replace_narrative_history_for_test({})
	tower._enemy_nodes_by_room[room.room_id] = []
	tower._alive_by_room[room.room_id] = 0
	boss.queue_free()


func _verify_snapshot_and_death() -> void:
	get_tree().paused = true
	tower._tick_main_story_auto_extraction(2.0)
	check(is_equal_approx(float(tower._main_story_auto_extraction.get("remaining", -1.0)), 8.0), "暂停不推进自动撤离")
	get_tree().paused = false
	tower._tick_main_story_auto_extraction(2.0)
	var saved := tower.build_runtime_save_snapshot()
	check(is_equal_approx(float(saved.get(PHASE, {}).get("remaining", -1.0)), 6.0), "倒计时快照保留真实剩余秒数")
	check(BaseManager.set_active_run_checkpoint(saved, "integration_resume"), "存盘运行快照")
	BaseManager.load_base()
	tower._restore_main_story_extraction(BaseManager.get_active_run_checkpoint())
	check(is_equal_approx(float(tower._main_story_auto_extraction.get("remaining", -1.0)), 6.0), "磁盘重载延续而非重置8秒")
	var fresh := saved.duplicate(true)
	fresh.erase(PHASE)
	tower._restore_main_story_extraction(fresh)
	check(tower._main_story_auto_extraction.is_empty(), "长期 acquired 单独不触发新远征撤离")
	fresh = saved.duplicate(true)
	fresh["run_id"] = "another_run"
	tower._restore_main_story_extraction(fresh)
	check(tower._main_story_auto_extraction.is_empty(), "其他行动快照不触发撤离")
	tower._restore_main_story_extraction(saved)
	tower.player.current_hp = 0
	tower._tick_main_story_auto_extraction(10.0)
	check(not bool(tower._main_story_auto_extraction.get("active", true)) and not tower._completed, "倒计时死亡立即取消，不结算成功")
	check(MainStoryProgress.key_state(BaseManager.get_main_story_snapshot(), KEY) == "acquired", "死亡不撤销永久钥匙")
	tower.player.current_hp = tower.player.max_hp
	tower._restore_main_story_extraction(saved)


func _verify_real_scene_reload() -> void:
	var snapshot := tower.build_runtime_save_snapshot()
	check(BaseManager.set_active_run_checkpoint(snapshot, "integration_real_scene_reload"), "真实场景重建前提交磁盘检查点")
	BaseManager.data = BaseData.new()
	BaseManager.load_base()
	snapshot = BaseManager.get_active_run_checkpoint()
	check(str(snapshot.get("run_id", "")) == tower._run_id and bool(snapshot.get(PHASE, {}).get("active", false)), "丢弃内存存档后从磁盘读取同一行动与撤离阶段")
	var original_run := tower._run_id
	var restored := SCENE.instantiate() as TowerDescent3D
	restored.test_mode = true
	restored.force_main_story_for_test = true
	restored.run_seed_override = tower.run_seed
	await _mount_real_scene(restored, "reload")
	restored.set_process(false)
	restored.player.set_physics_process(false)
	restored.get_main_story_controller().set_process(false)
	restored._run_id = original_run
	restored._restore_runtime_save_snapshot(snapshot)
	check(bool(restored._main_story_auto_extraction.get("active", false)), "真实场景运行快照入口恢复撤离阶段")
	check(is_equal_approx(float(restored._main_story_auto_extraction.get("remaining", -1.0)), 6.0), "真实场景恢复剩余秒数，不重发钥匙")
	var room := restored.get_main_story_room("boss") as DungeonRoom3D
	restored._restore_room_runtime_state("boss")
	check(restored.is_room_boss_defeated("boss"), "读档保留首领已败事实，不复活奖励门槛")
	check(bool(room.get_persistent_detail_state("treasure_chests").get("drop_boss", {}).get("opened", false)), "读档房间账仍为已开")
	check(room.get_pending_chest_grants().is_empty(), "已落地奖励读档不重发pending")
	var abort_results: Array[bool] = []
	restored.run_completed.connect(func(success: bool, _summary: Dictionary) -> void: abort_results.append(success))
	restored._confirm_expedition_exit()
	restored._tick_main_story_auto_extraction(20.0)
	check(abort_results == [false] and not bool(restored._main_story_auto_extraction.get("active", true)), "主动弃局取消倒计时，只发布一次失败")
	check(MainStoryProgress.key_state(BaseManager.get_main_story_snapshot(), KEY) == "acquired", "弃局不撤销已落盘钥匙")
	GameEntryFlow.consume_main_scene_entry()
	restored.queue_free()
	await get_tree().process_frame
	NarrativeDirector.bind_dungeon_for_test(tower)


func _verify_unique_settlement() -> void:
	tower.force_extraction_settlement_for_test = true
	tower._expedition_entry_source = ExpeditionEntryContext.TOWER03
	tower.run_completed.connect(func(success: bool, _summary: Dictionary) -> void:
		if success: successes += 1
		else: failures_emitted += 1)
	var runs_before := BaseManager.data.total_runs
	tower._tick_main_story_auto_extraction(5.5)
	check(not tower._completed and successes == 0 and is_equal_approx(float(tower._main_story_auto_extraction.get("remaining", -1.0)), 0.5), "累计7.5秒尚不结算，8秒倒计时不提前成功")
	BaseManager.force_save_failure_for_test = true
	print("MAIN_STORY_EXPECTED_FAILURE_BEGIN settlement_save")
	tower._tick_main_story_auto_extraction(0.5)
	print("MAIN_STORY_EXPECTED_FAILURE_END settlement_save")
	check(not tower._completed and successes == 0 and BaseManager.data.total_runs == runs_before, "成功提交失败可重试，不先发布成功")
	check(not tower.player.input_locked, "成功提交失败后恢复可行动输入")
	check(tower._expedition_entry_source == ExpeditionEntryContext.TOWER03, "失败重试恢复原入口来源")
	var revision := BaseManager.data.save_revision
	tower._tick_main_story_auto_extraction(0.1)
	check(BaseManager.data.save_revision == revision and tower._main_story_extraction_retry > 0.0, "保存失败后限频重试，不每帧刷盘")
	BaseManager.force_save_failure_for_test = false
	tower._tick_main_story_auto_extraction(2.1)
	check(tower._completed and successes == 1, "正式 _finish_run(true) 成功且只发布一次")
	check(BaseManager.data.total_runs == runs_before + 1, "成功统计唯一")
	var returned := BaseManager.get_active_run_checkpoint()
	check(str(returned.get("scope", "")) == "base" and str(returned.get("current_room_id", "")) == "facility", "钥匙自动撤离强制返航99F")
	check(str(returned.get(ExpeditionEntryContext.RETURN_KEY, "")) == ExpeditionEntryContext.BASE, "主线返航写 BASE 来源，不沿用塔3")
	check(bool(returned.get(Dungeon3D.SUCCESSFUL_EXTRACTION_CARRY_KEY, false)) and not returned.has(PHASE), "返航交接保留携带物且清除撤离标记")
	tower._tick_main_story_auto_extraction(10.0)
	tower._finish_run(true)
	tower._finish_run(false)
	check(successes == 1 and failures_emitted == 0 and BaseManager.data.total_runs == runs_before + 1, "完成后死亡/重复调用不二次成功或失败结算")


func _verify_base_host() -> void:
	print("MAIN_STORY_INTEGRATION_BEGIN base_instantiate")
	var base := BASE_SCENE.instantiate() as TowerDescent3D
	print("MAIN_STORY_INTEGRATION_END base_instantiate")
	base.test_mode = true
	base.force_main_story_for_test = true
	base.run_seed_override = 77001199
	await _mount_real_scene(base, "base")
	base.set_process(false)
	base.player.set_physics_process(false)
	var controller := base.get_main_story_controller()
	check(controller != null and base.find_npc("npc_base99_green") != null, "真实基地控制器与绿苔装配")
	if controller != null:
		controller.set_process(false)
	check(base.get_main_story_facility("mission_operations") != null, "真实设施按 facility_id 查询")
	check(base.resolve_main_story_anchor("mission_operations") is Vector3, "情报室锚点来自实际设施")
	check(base.resolve_main_story_anchor("key_slot_rare_earth") is Vector3, "钥匙槽位真实台座/前点可用")
	base.player.global_position = base.get_facility_spawn_point()
	check(base.resolve_main_story_anchor("player_front") is Vector3, "NPC接近点以玩家指向NPC并校验房内落点")
	check(base.find_base_rescue() != null, "基地救援先于3.3触发装配")
	if controller != null:
		base._current_room_id = "facility"
		BaseManager.replace_narrative_history_for_test({MainStoryChapter3D.BRIEFING_ID: {"completed_count": 1}})
		var previous_story := BaseManager.data.main_story.duplicate(true)
		BaseManager.data.main_story = {"schema_version": 1, "accepted": true, "keys": {KEY: {"state": "acquired"}}}
		var rescue := base.find_base_rescue()
		rescue._phase = Base99Rescue3D.Phase.CUTSCENE
		controller._process(0.0)
		check(not NarrativeDirector.is_playing(), "3.3等实际救援cutscene结束")
		rescue._phase = Base99Rescue3D.Phase.SKIPPED
		controller._process(0.0)
		check(NarrativeDirector.active_id() == MainStoryChapter3D.DEPOSIT_ID, "返航有钥匙且救援结束自动触发3.3")
		print("MAIN_STORY_EXPECTED_FAILURE_BEGIN rescue_gate_abort")
		NarrativeDirector.abort("integration_rescue_gate_checked")
		print("MAIN_STORY_EXPECTED_FAILURE_END rescue_gate_abort")
		BaseManager.data.main_story = previous_story
		BaseManager.replace_narrative_history_for_test({})
	base.queue_free()
	await get_tree().process_frame
	NarrativeDirector.reset_for_test()


func _finish() -> void:
	if is_instance_valid(tower):
		tower.queue_free()
	await get_tree().process_frame
	NarrativeDirector.reset_for_test()
	DialogueUI.close()
	scene_resources.clear()
	await get_tree().process_frame
	BaseManager.force_save_failure_for_test = original_save_failure
	BaseManager.save_path = original_path
	BaseManager.data = original_data
	print("MAIN_STORY_INTEGRATION_REPORT ", JSON.stringify({"checks": checks, "failures": failures, "expected_faults": ["claim_save", "settlement_save", "boss_trigger_abort", "rescue_gate_abort"], "rendered_acceptance": false}))
	if failures.is_empty():
		print("MAIN_STORY_INTEGRATION_OK")
	get_tree().quit(0 if failures.is_empty() else 1)
