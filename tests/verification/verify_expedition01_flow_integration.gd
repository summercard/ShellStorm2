extends Node
## 生产场景无头逻辑集成验证；不代表视听或新人体验实测。

const SCENE = preload("res://scenes/ExpeditionLevel01_3D.tscn")
var tower: TowerDescent3D
var failures: Array[String] = []
var checks := 0

class DeliveryProbe extends Dungeon3D:
	var delivered: Array = []
	var budget := 1
	func _deliver_ground_rewards(_room: DungeonRoom3D, grants: Array, _origin: Vector3, _context: String, _spread: bool = true, _delay: float = 0.0, _presentation: Dictionary = {}) -> Dictionary:
		if budget <= 0:
			return {"granted": [], "rejected": grants}
		budget -= 1
		delivered.append_array(grants.duplicate(true))
		return {"granted": grants, "rejected": []}
	func _queue_runtime_autosave(_reason: String) -> void:
		pass

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)

func _ready() -> void:
	var appdata := OS.get_environment("APPDATA").replace("\\", "/").to_lower()
	var localappdata := OS.get_environment("LOCALAPPDATA").replace("\\", "/").to_lower()
	check(appdata != localappdata and appdata.get_base_dir() == localappdata.get_base_dir(), "必须独立隔离 APPDATA/LOCALAPPDATA")
	check(appdata.ends_with("/appdata") and localappdata.ends_with("/localappdata") and (appdata.contains("/flow_integration/") or appdata.contains("/shellstorm-verification.")), "必须使用专项或标准套件隔离目录")
	if not failures.is_empty():
		finish()
		return
	BaseManager.data = BaseData.new()
	BaseManager.save_path = "user://flow_integration_profile_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	BaseManager.force_save_failure_for_test = false
	verify_partial_delivery()
	if "--partial-delivery-only" in OS.get_cmdline_user_args():
		finish()
		return
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	print("FLOW_INTEGRATION_BOOT_BEGIN")
	add_child(tower)
	print("FLOW_INTEGRATION_BOOT_ATTACHED rooms=%d" % tower._room_by_id.size())
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and not tower._expedition_bootstrap_failed:
		if tower._room_by_id.has("room_10") and tower._main_story_gameplay_started and not tower._expedition_loading_active:
			break
		await get_tree().process_frame
	var runtime_ready := tower._room_by_id.has("room_10") and tower._main_story_gameplay_started and not tower._expedition_bootstrap_failed
	check(runtime_ready, "正式13房初始化未就绪：rooms=%d gameplay=%s" % [tower._room_by_id.size(), tower._main_story_gameplay_started])
	if not runtime_ready:
		finish()
		return
	print("FLOW_INTEGRATION_RUNTIME_READY")
	tower.set_process(false)
	check(tower._clear_drop_plans.size() == 13, "新局没有冻结13房计划")
	for room_id in ["room_04", "room_06", "room_09", "room_10"]:
		var room := tower._room_by_id[room_id] as DungeonRoom3D
		var config := tower._build_room_encounter_config(room)
		check(config["duration_sec"] == 60.0 and config["completion"] == "clear" and config.get("deadline_behavior") == "close_dispatch_and_clear" and config.get("repeat_last_stage") == true, "%s 未接60秒循环clear" % room_id)
		check(config["preparation_sec"] == 0.0 and config["freeze_player_sec"] == 0.0 and config["stages"][0]["at_sec"] == 2.0, "%s 首批必须第2秒且不设准备/冻结" % room_id)
		check(config["max_alive"] == room.encounter["max_alive"], "%s 容量未透传" % room_id)
		check(config["intermission_sec"] == room.encounter["intermission_sec"], "%s 间歇未透传" % room_id)
		check(config["min_player_distance_m"] == 6.0, "%s 安全距离未透传" % room_id)
	var room03 := tower._room_by_id["room_03"] as DungeonRoom3D
	var compiled := tower._build_room_encounter_config(room03)
	for key in {"duration_sec": 60.0, "completion": "clear", "stage_advance": "clear", "preparation_sec": 0.0, "freeze_player_sec": 0.0, "intermission_sec": 0.0, "deadline_behavior": "close_dispatch_and_clear", "repeat_last_stage": true}:
		check(compiled.get(key) == room03.encounter.get(key), "03真实配置透传丢失：%s" % key)
	check(compiled["duration_sec"] == 60.0 and compiled["stages"][0]["at_sec"] == 2.0 and compiled["preparation_sec"] == 0.0 and compiled["freeze_player_sec"] == 0.0, "03必须fixed60、首批2秒且无准备/冻结")
	check(compiled["deadline_behavior"] == "close_dispatch_and_clear" and compiled["repeat_last_stage"] == true and compiled["intermission_sec"] == 0.0, "03截止/循环/零间歇配置错误")
	var second_fat_distance := 0.0
	for spec: Dictionary in compiled["stages"][1]["monsters"]:
		if spec.get("type") == "fat_zombie03":
			second_fat_distance = float(spec.get("min_player_distance_m", 0.0))
	check(second_fat_distance == 8.0, "03第二批胖子8m字段丢失")
	# 仅冻结自动处理；仍使用真实场景、Host、实体、存档、门与清房奖励链。
	tower.process_mode = Node.PROCESS_MODE_DISABLED
	await enter(room03)
	tower.force_open_edge_for_test("room_02", room03.room_id)
	var entry_leaf := room03.get_door_node_towards("room_02")
	check(entry_leaf != null and entry_leaf.is_open, "03封门前真实入口门必须已开")
	check(enemies(room03).is_empty() and not room03.cleared and not tower._room_is_sealed(room03.room_id), "03踩入口前不应刷怪/清房/封门")
	var port := room03.get_connection_port_by_id("A")
	var point: Array = port.get("position_m", [0.0, 0.0])
	var outward: Array = port.get("outward", [0.0, 0.0])
	var trigger := room03.encounter["trigger"] as Dictionary
	var inset := float(trigger["inset_m"]) + float(trigger["depth_m"]) * 0.5
	tower.player.global_position = room03.to_global(Vector3(float(point[0]) - float(outward[0]) * inset, 0.5, float(point[1]) - float(outward[1]) * inset))
	check(room03.match_door_entry_trigger(trigger, tower.player.global_position).get("port_id") == "A", "03真实入口A几何未命中")
	tower._tick_room_encounter_triggers(0.0)
	var id := str(tower._room_encounter_active.get(room03.room_id, ""))
	check(not id.is_empty() and tower._room_is_sealed(room03.room_id), "03入口触发未启动或封门")
	if id.is_empty():
		finish()
		return
	for target in room03.door_targets.values():
		var leaf := room03.get_door_node_towards(str(target))
		check(leaf != null and not leaf.is_open, "03封门未实际关闭门扇：%s" % str(target))
	tower._encounter_event_director.tick(0.0)
	check(enemies(room03).is_empty() and tower.get_encounter_event_snapshot(id).get("alert_remaining_sec") == 60.0, "03起点应无怪且总剩余60")
	tower._encounter_event_director.tick(1.99)
	check(enemies(room03).is_empty(), "03真实首批在1.99秒提前生成")
	var before_first := disk_round_trip(tower.build_runtime_save_snapshot())
	check(before_first["world_state"]["room_encounter_flow"]["active"].get(room03.room_id) == id, "03首批前active未保存")
	check(tower._restore_runtime_world_save_snapshot(before_first), "03首批前正式恢复失败")
	check(enemies(room03).is_empty() and is_equal_approx(float(tower.get_encounter_event_snapshot(id).get("elapsed", -1.0)), 1.99), "03首批前恢复重刷或重置时钟")
	tower._encounter_event_director.tick(0.01)
	check(enemies(room03).size() == 5, "03第2秒真实首批必须5只")
	var total := 0
	var peak := 0
	var persistent_ids := {}
	var kills_before := tower._kills
	for wave in 5:
		var batch := enemies(room03)
		var expected: int = [5, 7, 8, 8, 8][wave]
		check(batch.size() == expected, "03真实第%d批应%d只，实际%d" % [wave + 1, expected, batch.size()])
		total += batch.size()
		peak = maxi(peak, batch.size())
		for actor: Enemy3D in batch:
			check(not persistent_ids.has(actor.get_persistent_id()), "03末批循环重用真实实体身份")
			persistent_ids[actor.get_persistent_id()] = true
		if wave == 1:
			var fat_count := 0
			for actor: Enemy3D in batch:
				if actor.enemy_kind == "fat_zombie03":
					fat_count += 1
					check(Vector2(actor.global_position.x - tower.player.global_position.x, actor.global_position.z - tower.player.global_position.z).length() >= second_fat_distance, "03第二批胖子真实落点不足8m")
			check(fat_count == 1, "03第二批必须真实生成1只胖子")
		if wave in [1, 3]:
			var elapsed := float(tower.get_encounter_event_snapshot(id).get("elapsed", -1.0))
			var spawned := int(tower.get_encounter_event_snapshot(id).get("spawned", -1))
			var identities: Array = []
			for actor: Enemy3D in batch:
				identities.append(actor.get_persistent_id())
			identities.sort()
			var saved := disk_round_trip(tower.build_runtime_save_snapshot())
			check(tower._restore_runtime_world_save_snapshot(saved), "03在场/重复末批正式恢复失败")
			tower._encounter_event_director.tick(0.0)
			var restored_ids: Array = []
			for actor: Enemy3D in enemies(room03):
				restored_ids.append(actor.get_persistent_id())
			restored_ids.sort()
			check(restored_ids == identities and int(tower.get_encounter_event_snapshot(id).get("spawned", -1)) == spawned, "03恢复在场批次重发/换身份")
			check(is_equal_approx(float(tower.get_encounter_event_snapshot(id).get("elapsed", -1.0)), elapsed) and tower._room_encounter_active.get(room03.room_id) == id and tower._room_is_sealed(room03.room_id), "03恢复丢时钟/active/封门")
		print("FLOW_INTEGRATION_ROOM03_BATCH wave=%d live=%d total=%d" % [wave + 1, enemies(room03).size(), total])
		if wave == 4:
			break
		# clear_live只释放节点、不通知生产；此处每实体走一次正式击杀，不能再手动notify。
		var killed := enemies(room03)
		var kill_count := tower._kills
		for actor: Enemy3D in killed:
			tower._on_enemy_killed(actor, actor.get_enemy_data())
			actor.free()
		check(tower._kills == kill_count + killed.size() and enemies(room03).is_empty(), "03真实清批重复/漏记击杀")
		check(not room03.cleared and tower._room_is_sealed(room03.room_id), "03截止前清空不得清房解封")
		tower._encounter_event_director.tick(0.01)
	check(total == 36 and total > 20 and peak <= 8, "03真实循环应5/7/8/8/8累计36且峰值不超过8：%d/%d" % [total, peak])
	var pre_deadline := tower.get_encounter_event_snapshot(id)
	tower._encounter_event_director.tick(59.99 - float(pre_deadline.get("elapsed", 0.0)))
	check(not bool(tower.get_encounter_event_snapshot(id).get("dispatch_closed", true)), "03截止前不应关派发")
	tower._encounter_event_director.tick(0.01)
	var expired := tower.get_encounter_event_snapshot(id)
	check(expired.get("elapsed") == 60.0 and expired.get("dispatch_closed") == true and expired.get("alert_phase") == "cleanup", "03真实60秒未关闭派发进入cleanup")
	check(expired.get("status") == "active" and enemies(room03).size() == 8 and not room03.cleared and tower._room_is_sealed(room03.room_id), "03截止残怪未清不得完成/解封/删除实体")
	var cleanup := disk_round_trip(tower.build_runtime_save_snapshot())
	check(tower._restore_runtime_world_save_snapshot(cleanup), "03真实cleanup恢复失败")
	tower._encounter_event_director.tick(10.0)
	check(enemies(room03).size() == 8 and tower.get_encounter_event_snapshot(id).get("spawned") == total and tower.get_encounter_event_snapshot(id).get("status") == "active", "03截止恢复后重发或提前完成")
	for actor: Enemy3D in enemies(room03):
		tower._on_enemy_killed(actor, actor.get_enemy_data())
		actor.free()
	check(tower._kills == kills_before + total, "03总击杀数必须等于实际36实体且不重复")
	check(tower.get_encounter_event_snapshot(id).get("status") == "completed" and room03.cleared and not tower._room_is_sealed(room03.room_id), "03截止残怪清零后必须completed、真实清房并解封")
	check(int(tower._alive_by_room.get(room03.room_id, -1)) == 0 and enemies(room03).is_empty(), "03清房实体/存活账未归零")
	check(int(tower.get_encounter_event_snapshot(id).get("dropped", -1)) == 0, "03全部已实到批次不得被截止作废")
	await get_tree().process_frame
	tower._ensure_room_clear_drop(room03)
	var chest := room03.find_chest_by_id("drop_room_03")
	var chest_count := 0
	for candidate in get_tree().get_nodes_in_group("treasure_chest_3d"):
		if room03.is_ancestor_of(candidate) and not candidate.is_queued_for_deletion():
			chest_count += 1
	check(chest != null and chest_count == 1 and room03.get_persistent_detail_state("treasure_chests").size() == 1, "03清房必须真实实例化唯一奖励宝箱：%d" % chest_count)
	check(tower._clear_drop_settled.has(room03.room_id), "03清房奖励未结算")
	var settled := disk_round_trip(tower.build_runtime_save_snapshot())
	check(tower._restore_runtime_world_save_snapshot(settled), "03清房及箱子正式恢复失败")
	tower._encounter_event_director.tick(60.0)
	for _retry in 3:
		tower._ensure_room_clear_drop(room03)
	await get_tree().process_frame
	var restored_chest_count := 0
	for candidate in get_tree().get_nodes_in_group("treasure_chest_3d"):
		if room03.is_ancestor_of(candidate) and not candidate.is_queued_for_deletion():
			restored_chest_count += 1
	check(restored_chest_count == 1 and room03.find_chest_by_id("drop_room_03") != null and room03.get_persistent_detail_state("treasure_chests").size() == 1, "03恢复重复结算导致双箱或丢箱：%d" % restored_chest_count)
	check(room03.cleared and not tower._room_is_sealed(room03.room_id) and enemies(room03).is_empty(), "03终态恢复重封门/重刷")
	# Director恢复只保留active实例；完成事实归房间进度与fired账，不要求旧终态统计实例重建。
	check(tower.get_encounter_event_snapshot(id).is_empty() and not tower._room_encounter_active.has(room03.room_id) and tower._room_encounters_fired.has(room03.room_id), "03完成账恢复丢失或复活终态实例")
	print("FLOW_INTEGRATION_ROOM03_TIMED_DONE spawned=%d peak=%d kills=%d cleared=%s sealed=%s chest_count=%d restored_chest_count=%d failures=%d" % [total, peak, tower._kills - kills_before, room03.cleared, tower._room_is_sealed(room03.room_id), chest_count, restored_chest_count, failures.size()])
	if "--room03-timed-only" in OS.get_cmdline_user_args():
		finish()
		return
	await verify_event_handler_orders()
	await verify_box_queue()
	await verify_rewards()
	verify_production_run_identity()
	await verify_legacy_reward_migration()
	finish()

func verify_event_handler_orders() -> void:
	var room := tower._room_by_id["room_09"] as DungeonRoom3D
	await enter(room)
	var outcomes := ["CURSE", "BLESSING", "TRADE", "GAMBLE", "REVEAL", "SUMMON"]
	for terminal_first in [false, true]:
		for outcome in outcomes.size():
			clear_live(room)
			tower._resolved_event_rooms.erase(room.room_id)
			tower._room_encounters_fired.erase(room.room_id)
			tower._room_encounter_active.erase(room.room_id)
			tower._room_enemy_damage_multipliers.erase(room.room_id)
			room.cleared = false
			var started := tower._start_room_encounter(room)
			var id := str(started.get("instance_id", ""))
			check(bool(started.get("ok", false)), "六结果遭遇启动失败")
			var event_seed := 0
			var probe := RandomNumberGenerator.new()
			while event_seed < 1000:
				probe.seed = event_seed
				if probe.randi_range(0, 5) == outcome:
					break
				event_seed += 1
			if terminal_first:
				interact_event(room, event_seed)
				if outcome == 0:
					check(is_equal_approx(float(tower._room_enemy_damage_multipliers.get(room.room_id, 1.0)), 1.15), "CURSE未保留后续波次15%伤害效果")
				check(not room.cleared and tower._room_has_pending_combat(room), "先终端提前清房：%s" % outcomes[outcome])
			var actual := 0
			for _batch in 24:
				tower._encounter_event_director.tick(2.6)
				var batch := enemies(room)
				actual += batch.size()
				check(batch.size() <= 12, "EVENT并发超过12")
				clear_live(room)
				tower._encounter_event_director.notify_enemy_departed(id, "killed")
				if bool(tower.get_encounter_event_snapshot(id).get("terminal", false)):
					break
			check(actual == 48 and int(tower.get_encounter_event_snapshot(id).get("spawned", 0)) == 48, "六结果改变48只编排：%s" % outcomes[outcome])
			if not terminal_first:
				check(not room.cleared and tower._room_is_sealed(room.room_id), "未结算终端就放行")
				interact_event(room, event_seed)
			check(room.cleared and not tower._room_is_sealed(room.room_id), "六结果未收口：%s terminal_first=%s" % [outcomes[outcome], terminal_first])
			check(enemies(room).is_empty(), "终端重刷已完成遭遇")
			var spawned := int(tower.get_encounter_event_snapshot(id).get("spawned", 0))
			interact_event(room, event_seed)
			check(int(tower.get_encounter_event_snapshot(id).get("spawned", 0)) == spawned and room.cleared, "重复交互重刷或撤销清房")
			print("FLOW_INTEGRATION_EVENT_HANDLER result=%s terminal_first=%s actual=%d" % [outcomes[outcome], terminal_first, actual])
			await get_tree().process_frame

func interact_event(room: DungeonRoom3D, event_seed: int) -> void:
	var station := room.ensure_required_service_station()
	check(station != null, "正式终端缺失")
	if station == null:
		return
	tower._rng.seed = event_seed
	station._player_in_range = true
	check(station.perform_interaction(tower.player, {}), "正式终端交互拒绝")
	check(tower._resolved_event_rooms.has(room.room_id), "正式handler未登记事件结算")

func verify_partial_delivery() -> void:
	var host := DeliveryProbe.new()
	host.run_seed = 77001199
	host.visual_theme = DungeonTheme3D.new()
	var room := DungeonRoom3D.new()
	room.room_id = "flow_integration_delivery"
	add_child(room)
	var drop := {"kind": "none", "grants": [{"item_id": "item_ammo_pack", "count": 200}, {"item_id": "item_health_potion", "count": 1}], "additional_weapon": {"weapon_id": "weapon_rifle", "grade": "purple", "bullet_module_id": "mod_bullet_standard"}}
	host._apply_clear_drop(room, drop, "flow_integration_partial")
	check(host.delivered.size() == 1 and not host._clear_drop_settled.has(room.room_id), "部分失败提前结算或重复交付")
	var world := {}
	host._export_flow_integration_state(world)
	var restored := DeliveryProbe.new()
	restored.run_seed = host.run_seed
	restored.visual_theme = host.visual_theme
	restored._import_flow_integration_state(JSON.parse_string(JSON.stringify(world)))
	restored.budget = 10
	restored._apply_clear_drop(room, drop, "flow_integration_partial")
	check(restored.delivered.size() == 2 and restored._clear_drop_settled.has(room.room_id), "部分失败恢复未只补剩余物资")
	var first_weapon := restored.delivered.back() as Dictionary
	check(str(first_weapon["item"].get("drop_grade", "")) == "purple", "分账恢复追加枪不是紫品")
	restored._apply_clear_drop(room, drop, "flow_integration_partial")
	check(restored.delivered.size() == 2, "恢复后重复发枪")
	host.free()
	restored.free()
	room.free()

func enter(room: DungeonRoom3D) -> void:
	tower.player.current_hp = tower.player.max_hp
	room.ensure_shell_built()
	room.ensure_detail_built()
	tower.player.global_position = room.to_global(Vector3(0, 0.5, 0))
	tower.force_enter_room_for_test(room.room_id)
	await get_tree().physics_frame

func enemies(room: DungeonRoom3D) -> Array:
	var out: Array = []
	for enemy in tower._enemy_nodes_by_room.get(room.room_id, []):
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.ai_state != "dead":
			out.append(enemy)
	return out

func clear_live(room: DungeonRoom3D) -> void:
	for enemy in enemies(room):
		MonsterAIManager.unregister_enemy(enemy)
		enemy.free()
	tower._enemy_nodes_by_room[room.room_id] = []
	tower._alive_by_room[room.room_id] = tower._reserved_spawn_count(room.room_id)

func disk_round_trip(snapshot: Dictionary) -> Dictionary:
	var file := FileAccess.open("user://flow_integration_snapshot.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshot))
	file.close()
	return JSON.parse_string(FileAccess.get_file_as_string("user://flow_integration_snapshot.json")) as Dictionary

func verify_box_queue() -> void:
	var room := tower._room_by_id["room_01"] as DungeonRoom3D
	await enter(room)
	clear_live(room)
	# 两次请求共用冻结配置，玩家占住全部授权盒候选时只能留队列。
	var frozen_waves := tower._spawn_box_waves(room, 1, 0)
	check(not frozen_waves.is_empty(), "普通盒没有正式冻结编成")
	if frozen_waves.is_empty():
		return
	var config := (frozen_waves[0][0] as Dictionary).duplicate(true)
	var authorized: Array = config.get("spawn_safe_candidates", [])
	check(not authorized.is_empty(), "正式盒编成未保留授权候选")
	var candidate := room.choose_safe_spawn_position(Vector3.INF, 0.0, [], authorized)
	check(bool(candidate.get("ok", false)), "盒测试没有合法候选")
	if not bool(candidate.get("ok", false)):
		return
	var point: Vector3 = candidate["position"]
	tower.player.global_position = point
	config["spawn_position"] = point
	config["spawn_delay_sec"] = 0.0
	config["spawn_safe_candidates"] = [point]
	config["spawn_min_player_distance_m"] = 6.0
	config["persistent_id"] = "flow_integration:box_wait"
	var configs: Array[Dictionary] = [config]
	check(tower._spawn_enemy_batch(room, configs, true) == 1, "临时无点没有预约")
	check(enemies(room).is_empty(), "临时无点仍刷脚下")
	var requests := tower._pending_delayed_spawns[room.room_id] as Array
	check(not requests.is_empty(), "临时无点丢失队列")
	if requests.is_empty():
		return
	var serial := int(requests.back()["serial"])
	tower._on_delayed_spawn_timeout(room.room_id, serial)
	check(not requests.is_empty() and enemies(room).is_empty(), "到点未复验距离")
	tower.player.global_position = point + Vector3(12, 0, 0)
	tower._on_delayed_spawn_timeout(room.room_id, serial)
	check(enemies(room).size() == 1, "让出空间后未补发")
	if enemies(room).size() == 1:
		check(enemies(room)[0].global_position.is_equal_approx(point), "盒内候选被吸附/回退")
		check(enemies(room)[0].get_persistent_id() == "flow_integration:box_wait", "延迟怪重掷身份")
	clear_live(room)

func verify_rewards() -> void:
	var room := tower._room_by_id["room_07"] as DungeonRoom3D
	await enter(room)
	clear_live(room)
	room.cleared = true
	tower._ensure_room_clear_drop(room)
	check(tower._clear_drop_settled.has(room.room_id), "07追加奖励未完成")
	var ledger := tower._clear_drop_delivery.get(room.room_id, {}) as Dictionary
	for channel in ["chest", "grants", "additional_weapon", "item"]:
		check(bool(ledger.get("%s_done" % channel, false)), "07%s分账未完成" % channel)
	var pickups: Array = []
	for pickup in get_tree().get_nodes_in_group("ground_loot_3d"):
		if room.is_ancestor_of(pickup):
			pickups.append(pickup)
	var ammo := 0
	var potions := 0
	var guns := 0
	for pickup: GroundLootPickup3D in pickups:
		var item := pickup.item_data
		if str(item.get("id", "")) == "item_ammo_pack":
			ammo += int(item.get("count", 0))
		if str(item.get("id", "")) == "item_health_potion":
			potions += int(item.get("count", 0))
		if str(item.get("id", "")) == "weapon_rifle":
			guns += 1
			check(str(item.get("drop_grade", "")) == "purple", "07不是紫枪")
			check(str(item).contains("mod_bullet_standard"), "07不是标准弹")
	check(ammo == 200 and potions == 1 and guns == 1, "07小包/枪实际数量错误 %d/%d/%d" % [ammo, potions, guns])
	tower._ensure_room_clear_drop(room)
	var count := 0
	for pickup in get_tree().get_nodes_in_group("ground_loot_3d"):
		if room.is_ancestor_of(pickup):
			count += 1
	check(count == pickups.size(), "07重复结算双发")
	check(room.get_persistent_detail_state("treasure_chests").size() == 1, "07双箱")
	var reward_save := disk_round_trip(tower.build_runtime_save_snapshot())
	check(tower._restore_runtime_world_save_snapshot(reward_save), "07实际奖励读档失败")
	tower._ensure_room_clear_drop(room)
	var after_restore := 0
	for pickup in get_tree().get_nodes_in_group("ground_loot_3d"):
		if room.is_ancestor_of(pickup) and not pickup.is_queued_for_deletion():
			after_restore += 1
	check(after_restore == pickups.size() and room.get_persistent_detail_state("treasure_chests").size() == 1, "07读档后双箱/双枪/双小包")
	print("FLOW_INTEGRATION_ROOM07 ammo=%d potions=%d guns=%d pickups=%d" % [ammo, potions, guns, after_restore])
	check(tower._fate_economy.price_index_for_room("room_02") == 2, "02来源报价序号不正确")
	check(not tower._show_door_fate_choices("pickup", "flow_integration:unknown", {"source_room_id": "unknown"}), "未知来源没有拒绝offer")

func verify_production_run_identity() -> void:
	var room := tower._room_by_id["room_07"] as DungeonRoom3D
	var original_run := tower._run_id
	var original_delivery := tower._clear_drop_delivery.duplicate(true)
	var original_settled := tower._clear_drop_settled.duplicate(true)
	var inventory_before := tower._inventory.get_slots_snapshot().duplicate(true)
	var chest := TreasureChest3D.new()
	chest.configure({"id": "identity_production_chest", "chest_tier": "normal", "source_room_id": room.room_id, "guaranteed_items": [{"item_id": "weapon_rifle", "count": 1, "grade": "blue", "bullet_module_id": "mod_bullet_standard"}]})
	var drop := {"kind": "none", "additional_weapon": {"weapon_id": "weapon_rifle", "grade": "purple", "bullet_module_id": "mod_bullet_standard"}}
	var first_chest: Array = []
	var first_extra: Array = []
	var identities: Array = []
	for run_id in ["flow_identity_run_a", "flow_identity_run_b"]:
		tower._run_id = run_id
		var grants := tower._resolve_chest_grants(room, chest)
		check(grants == tower._resolve_chest_grants(room, chest), "生产箱同run重试奖励/身份改变")
		var chest_ids := weapon_identities(grants)
		check(chest_ids.size() == 1, "生产箱未生成保底枪")
		# 仅注入交付失败；解析仍走未覆盖的生产Dungeon._apply_clear_drop。
		var delivery_host := DeliveryProbe.new()
		delivery_host.run_seed = tower.run_seed
		delivery_host._run_id = tower._run_id
		delivery_host.visual_theme = tower.visual_theme
		delivery_host.budget = 0
		var detached := DungeonRoom3D.new()
		detached.room_id = "identity_production_extra"
		add_child(detached)
		delivery_host._apply_clear_drop(detached, drop, "identity_production_event")
		var ledger := delivery_host._clear_drop_delivery[detached.room_id] as Dictionary
		var pending := (ledger.get("additional_weapon_pending", []) as Array).duplicate(true)
		check(pending.size() == 1, "真实追加解析未保留pending")
		delivery_host._apply_clear_drop(detached, drop, "identity_production_event")
		check(ledger["additional_weapon_pending"] == pending, "追加枪同run失败重试重解析")
		var extra_ids := weapon_identities(pending)
		check(extra_ids.size() == 1, "真实追加解析未生成枪")
		identities.append([chest_ids, extra_ids])
		if run_id == "flow_identity_run_a":
			first_chest = grants.duplicate(true)
			first_extra = pending.duplicate(true)
		else:
			check(without_weapon_identity(first_chest) == without_weapon_identity(grants), "runID改变箱子随机流")
			check(without_weapon_identity(first_extra) == without_weapon_identity(pending), "runID改变追加枪随机流")
		# 即便宿主run身份变化，旧冻结pending也必须原样补发。
		delivery_host._run_id = "different_host_after_freeze"
		delivery_host._apply_clear_drop(detached, drop, "identity_production_event")
		check(ledger["additional_weapon_pending"] == pending, "旧追加pending因runID改变被重解析")
		delivery_host.free()
		detached.free()
	check(identities[0][0] != identities[1][0] and identities[0][1] != identities[1][1], "生产调用同seed跨run枪身份碰撞")
	var frozen_chest := TreasureChest3D.new()
	frozen_chest.configure({"id": "legacy_identity_explicit", "grants": first_chest})
	check(tower._resolve_chest_grants(room, frozen_chest) == first_chest, "旧明确grants被按新run解析")
	frozen_chest.free()
	var saved_pending := room.get_pending_chest_grants()
	room.set_pending_chest_grants("identity_old_pending", {"grants": first_chest, "status": "mimic_alive", "position": [0, 0, 0]})
	var snapshot := disk_round_trip(tower.build_runtime_save_snapshot())
	var restored := snapshot["world_state"]["segment_runtime_state"][room.room_id]["pending_chest_grants"]["identity_old_pending"]["grants"] as Array
	check(restored == JSON.parse_string(JSON.stringify(first_chest)), "正式保存旧箱pending被重新解析")
	check(weapon_identities(restored) == weapon_identities(first_chest), "正式保存旧箱pending换ID")
	room.apply_runtime_detail_state({"pending_chest_grants": saved_pending})
	var old_weapon := {}
	for grant: Dictionary in first_chest:
		var item := grant.get("item", {}) as Dictionary
		if str(item.get("type", "")) == "weapon":
			old_weapon = item
	check(tower._inventory.add_item(old_weapon, 1) == 1, "旧冻结枪入包失败")
	var inventory_frozen := disk_round_trip(tower.build_runtime_save_snapshot())["inventory_slots"] as Array
	var inventory_kept := false
	for slot_value in inventory_frozen:
		if slot_value is Dictionary:
			var item := (slot_value as Dictionary).get("item", {}) as Dictionary
			if str(item.get("weapon_instance_id", "")) == str(old_weapon.get("weapon_instance_id", "")):
				inventory_kept = true
	check(inventory_kept, "正式背包存档丢失旧枪身份")
	tower._inventory.restore_slots_snapshot(inventory_before)
	check(tower._inventory.get_slots_snapshot() == inventory_before, "身份接线改动既有背包")
	tower._run_id = original_run
	tower._clear_drop_delivery = original_delivery
	tower._clear_drop_settled = original_settled
	chest.free()
	print("FLOW_INTEGRATION_PRODUCTION_RUN_IDENTITY same_run_stable=true cross_run_distinct=true rng_unchanged=true frozen_unchanged=true")

func weapon_identities(grants: Array) -> Array:
	var ids: Array = []
	for grant: Dictionary in grants:
		var item := grant.get("item", {}) as Dictionary
		if str(item.get("type", "")) == "weapon":
			ids.append([item["weapon_instance_id"], item["created_transaction_id"]])
	return ids

func without_weapon_identity(grants: Array) -> Array:
	var result := grants.duplicate(true)
	for grant: Dictionary in result:
		var item := grant.get("item", {}) as Dictionary
		item.erase("weapon_instance_id")
		item.erase("created_transaction_id")
		var nested := item.get("weapon_instance", {}) as Dictionary
		nested.erase("weapon_instance_id")
		nested.erase("created_transaction_id")
	return result

func verify_legacy_reward_migration() -> void:
	var legacy := disk_round_trip(tower.build_runtime_save_snapshot())
	var world := legacy["world_state"] as Dictionary
	world.erase("clear_drop_plans")
	world.erase("clear_drop_config")
	world.erase("clear_drop_delivery")
	world.erase("clear_drop_settled")
	for room_id in world["segment_runtime_state"]:
		var saved_room := world["segment_runtime_state"][room_id] as Dictionary
		saved_room.erase("clear_drop_plan")
		for saved_chest: Dictionary in (saved_room.get("treasure_chests", {}) as Dictionary).values():
			var old_config := saved_chest.get("config", {}) as Dictionary
			old_config.erase("fate_card_chance")
			old_config.erase("fate_common_offer")
	for room_id in ["room_01", "room_02", "room_10", "boss"]:
		(world["segment_runtime_state"] as Dictionary).erase(room_id)
		world["room_progress"][room_id] = {"visited": false, "cleared": false}
	check(tower._restore_runtime_world_save_snapshot(legacy), "旧档迁移拒绝")
	var frozen := JSON.stringify(tower._clear_drop_plans)
	check(tower._clear_drop_plans.size() == 13, "旧档停发全部奖励")
	var guarantees := 0
	for room_id in tower._clear_drop_plans:
		var drop := tower._clear_drop_plans[room_id] as Dictionary
		check((drop.get("grants", []) as Array).is_empty() and (drop.get("additional_weapon", {}) as Dictionary).is_empty(), "旧档追加新小包或紫枪")
		var config := drop.get("chest", {}) as Dictionary
		check(not bool(config.get("fate_common_offer", false)), "旧档补新普通候选保底")
		if room_id != "boss":
			check(float(config.get("fate_card_chance", 0.3)) == 0.3, "旧箱改为必给命运凭据")
		for item: Dictionary in config.get("guaranteed_items", []):
			check(not item.has("bullet_module_id"), "旧首枪被强制标准弹")
			if str(item.get("item_id", "")).begins_with("weapon_"):
				guarantees += 1
	check(guarantees == 1, "历史首枪保底丢失")
	check(tower._restore_runtime_world_save_snapshot(legacy) and JSON.stringify(tower._clear_drop_plans) == frozen, "旧迁移重试重掷结果")
	var explicit_frozen := legacy.duplicate(true)
	explicit_frozen["world_state"]["segment_runtime_state"]["room_10"] = {"clear_drop_plan": {"kind": "chest", "chest": {"id": "drop_room_10", "chest_tier": "normal", "mimic": false, "quality": "epic"}, "grants": [], "additional_weapon": {}}}
	check(tower._restore_runtime_world_save_snapshot(explicit_frozen), "历史冻结计划恢复失败")
	check(tower._clear_drop_plans["room_10"]["chest"]["quality"] == "epic", "旧冻结箱被新配置覆盖")
	var settled := legacy.duplicate(true)
	settled["world_state"]["clear_drop_settled"] = {"room_10": true}
	check(tower._restore_runtime_world_save_snapshot(settled) and tower._clear_drop_settled.has("room_10"), "旧settled账被清掉")
	check(tower._restore_runtime_world_save_snapshot(legacy), "迁移矩阵恢复失败")
	var ordinary := tower._room_by_id["room_10"] as DungeonRoom3D
	await enter(ordinary)
	clear_live(ordinary)
	ordinary.cleared = true
	tower._ensure_room_clear_drop(ordinary)
	check(ordinary.find_chest_by_id("drop_room_10") != null, "旧未清普通房原箱缺失")
	var delivered := tower._clear_drop_delivery.get(ordinary.room_id, {}) as Dictionary
	check((delivered.get("grants_pending", []) as Array).is_empty() and (delivered.get("additional_weapon_pending", []) as Array).is_empty(), "旧普通房追加新奖励")
	var boss := tower._room_by_id["boss"] as DungeonRoom3D
	await enter(boss)
	tower.force_main_story_for_test = true
	BaseManager.data.main_story = MainStoryProgress.default_state()
	var boss_actor: Enemy3D = null
	for actor: Enemy3D in enemies(boss):
		if actor.enemy_kind == "boss":
			boss_actor = actor
			break
	check(boss_actor != null, "旧档正式Boss实体未生成")
	if boss_actor == null:
		return
	tower._on_enemy_killed(boss_actor, boss_actor.get_enemy_data())
	clear_live(boss)
	await get_tree().process_frame
	await get_tree().process_frame
	var chest := boss.find_chest_by_id("drop_boss")
	check(chest != null and chest.chest_tier == "advanced", "旧Boss阵亡不掉高级箱")
	if chest == null:
		return
	check(not chest.mimic, "旧首通Boss箱拟态吞钥匙")
	var story_before := BaseManager.get_main_story_snapshot()
	BaseManager.force_save_failure_for_test = true
	tower._on_chest_open_requested(boss, chest)
	check(not chest.is_opened() and BaseManager.get_main_story_snapshot() == story_before, "旧Boss领取失败未保留原箱/钥匙")
	BaseManager.force_save_failure_for_test = false
	chest._player_in_range = true
	check(chest.perform_interaction(tower.player, {}), "旧Boss真实开箱交互失败")
	check(chest.is_opened(), "旧Boss箱未提交已开")
	check(MainStoryProgress.key_state(BaseManager.get_main_story_snapshot(), MainStoryProgress.KEY_RARE_EARTH) == MainStoryProgress.STATE_ACQUIRED, "旧Boss主线钥匙链丢失")
	await get_tree().create_timer(chest.get_open_burst_delay() + 0.1, false).timeout
	var opened := disk_round_trip(tower.build_runtime_save_snapshot())
	(opened["world_state"] as Dictionary).erase("clear_drop_plans")
	check(tower._restore_runtime_world_save_snapshot(opened), "已开旧Boss箱恢复失败")
	tower._ensure_boss_chest_drop(boss.room_id)
	check(boss.find_chest_by_id("drop_boss") == chest and chest.is_opened() and boss.get_persistent_detail_state("treasure_chests").size() == 1, "旧已开Boss箱重刷")
	var revision := BaseManager.data.save_revision
	tower._on_chest_open_requested(boss, chest)
	check(BaseManager.data.save_revision == revision, "旧已领钥匙重复写盘发奖")
	check(tower._legacy_boss_reward_claimed(), "本局钥匙来源未识别为已领取")
	var key_record := BaseManager.data.main_story["keys"][MainStoryProgress.KEY_RARE_EARTH] as Dictionary
	key_record["acquired_source"]["runtime_run_id"] = "previous_run"
	check(not tower._legacy_boss_reward_claimed(), "前局已领钥匙错误取消本局Boss战利品")
	print("FLOW_INTEGRATION_LEGACY normal_chest=true opening_weapon=%d boss_key_acquired=true opened_no_respawn=true" % guarantees)

func finish() -> void:
	if is_instance_valid(tower):
		tower.queue_free()
	await get_tree().process_frame
	for failure in failures:
		push_error(failure)
	print("FLOW_INTEGRATION_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
