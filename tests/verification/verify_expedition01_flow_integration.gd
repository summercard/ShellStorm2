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
	check(OS.get_environment("APPDATA").contains("flow_integration"), "必须隔离 APPDATA")
	check(OS.get_environment("LOCALAPPDATA").contains("flow_integration"), "必须隔离 LOCALAPPDATA")
	if not failures.is_empty():
		finish()
		return
	verify_partial_delivery()
	if "--partial-delivery-only" in OS.get_cmdline_user_args():
		finish()
		return
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	tower.set_process(false)
	check(tower._room_by_id.has("room_10"), "正式13房未启动，核对Validator")
	if not tower._room_by_id.has("room_10"):
		finish()
		return
	check(tower._clear_drop_plans.size() == 13, "新局没有冻结13房计划")
	for room_id in ["room_03", "room_04", "room_06", "room_09", "room_10"]:
		var room := tower._room_by_id[room_id] as DungeonRoom3D
		var config := tower._build_room_encounter_config(room)
		check(config["duration_sec"] == 0.0 and config["completion"] == "clear", "%s 未接有限clear" % room_id)
		check(config["max_alive"] == room.encounter["max_alive"], "%s 容量未透传" % room_id)
		check(config["intermission_sec"] == room.encounter["intermission_sec"], "%s 间歇未透传" % room_id)
		check(config["min_player_distance_m"] == 6.0, "%s 安全距离未透传" % room_id)
	var room03 := tower._room_by_id["room_03"] as DungeonRoom3D
	var compiled := tower._build_room_encounter_config(room03)
	check(compiled["stages"][0]["monsters"][0]["min_player_distance_m"] == 8.0, "首胖8m丢失")
	await enter(room03)
	var started := tower._start_room_encounter(room03)
	var id := str(started.get("instance_id", ""))
	check(bool(started.get("ok", false)), "03遭遇启动失败")
	tower._encounter_event_director.tick(1.0)
	check(enemies(room03).is_empty(), "准备期提前出怪")
	var preparation := disk_round_trip(tower.build_runtime_save_snapshot())
	check(preparation["world_state"]["room_encounter_flow"]["active"].has(room03.room_id), "准备期active未保存")
	tower._encounter_event_director.tick(0.6)
	check(enemies(room03).size() == 1, "首胖不是单只")
	for enemy: Enemy3D in enemies(room03):
		check(Vector2(enemy.global_position.x - tower.player.global_position.x, enemy.global_position.z - tower.player.global_position.z).length() >= 8.0, "首胖贴脸")
	clear_live(room03)
	tower._encounter_event_director.tick(0.0)
	tower._encounter_event_director.tick(0.7)
	var saved := disk_round_trip(tower.build_runtime_save_snapshot())
	var before := tower.get_encounter_event_snapshot(id)
	var remaining := float(before.get("intermission_remaining_sec", -1.0))
	check(remaining > 0.0, "间歇剩余未建立")
	check(tower._restore_runtime_world_save_snapshot(saved), "正式Tower恢复失败")
	check(tower._room_encounter_active.get(room03.room_id, "") == id, "恢复active丢失")
	check(tower._room_is_sealed(room03.room_id), "恢复封门丢失")
	check(is_equal_approx(float(tower.get_encounter_event_snapshot(id).get("intermission_remaining_sec", 0.0)), remaining), "恢复间歇重置")
	tower._encounter_event_director.tick(maxf(0.0, remaining - 0.1))
	check(enemies(room03).is_empty(), "恢复跳过间歇")
	tower._encounter_event_director.tick(0.2)
	check(enemies(room03).size() == 8, "第二波未按容量派发")
	var total := 1
	var peak := 0
	for _step in 18:
		peak = maxi(peak, enemies(room03).size())
		total += enemies(room03).size()
		clear_live(room03)
		tower._encounter_event_director.tick(0.0)
		tower._encounter_event_director.tick(3.1)
		if bool(tower.get_encounter_event_snapshot(id).get("terminal", false)):
			break
	check(int(tower.get_encounter_event_snapshot(id).get("spawned", 0)) == 20, "03有限编成丢怪/重刷")
	check(peak <= 8, "03超过同屏容量")
	check(room03.cleared and not tower._room_is_sealed(room03.room_id), "03清完未立即解封")
	check(int(tower.get_encounter_event_snapshot(id).get("dropped", -1)) == 0, "无截止clear作废怪物")
	var room09 := tower._room_by_id["room_09"] as DungeonRoom3D
	await enter(room09)
	var event_started := tower._start_room_encounter(room09)
	tower._resolved_event_rooms[room09.room_id] = true
	check(tower._room_has_pending_combat(room09), "EVENT准备期没有pending")
	tower._mark_room_cleared(room09, true)
	check(not room09.cleared, "EVENT终端提前清房")
	tower.cancel_encounter_event(str(event_started.get("instance_id", "")), "verification", true)
	await verify_box_queue()
	await verify_rewards()
	var legacy := disk_round_trip(tower.build_runtime_save_snapshot())
	legacy["world_state"].erase("clear_drop_plans")
	legacy["world_state"].erase("room_encounter_flow")
	check(tower._restore_runtime_world_save_snapshot(legacy), "旧档恢复拒绝")
	check(tower._clear_drop_plans.is_empty(), "旧档按新配置补造计划")
	finish()

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
	var candidate := room.choose_safe_spawn_position(Vector3.INF, 0.0)
	check(bool(candidate.get("ok", false)), "盒测试没有合法候选")
	if not bool(candidate.get("ok", false)):
		return
	var point: Vector3 = candidate["position"]
	tower.player.global_position = point
	var config := tower._make_box_enemy("melee_chaser", 1, 0, room)
	config["spawn_position"] = point
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
	check(tower._fate_economy.price_index_for_room("room_02") == 2, "02来源报价序号不正确")
	check(not tower._show_door_fate_choices("pickup", "flow_integration:unknown", {"source_room_id": "unknown"}), "未知来源没有拒绝offer")

func finish() -> void:
	if is_instance_valid(tower):
		tower.queue_free()
	await get_tree().process_frame
	for failure in failures:
		push_error(failure)
	print("FLOW_INTEGRATION_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
