extends Node
## Isolate APPDATA before launching. Exercises the actual mansion and durable profile.
const DIRECTOR = preload("res://src/enemy3d/RoamingEliteRunDirector.gd")
const LEVEL = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const ID := "elite_arms_taker"
var failures: Array[String] = []
var checks := 0
var tower: TowerDescent3D


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and message not in failures:
		failures.append(message)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	BaseManager.save_path = "user://roaming_elite_verification.json"
	BaseManager.data = BaseData.new()
	EliteRosterService.reset_roster_for_test()
	verify_plans()
	tower = LEVEL.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 20261104
	get_tree().root.add_child.call_deferred(tower)
	for frame in 1200:
		await get_tree().process_frame
		if tower._rooms.size() >= 10 and is_instance_valid(tower.player):
			break
	await get_tree().process_frame
	check(tower._flow_rules_active, "Actual mansion did not assemble its flow rules")
	get_tree().current_scene = tower
	tower.process_mode = Node.PROCESS_MODE_DISABLED
	for config in tower._map_fate_triggers._triggers:
		config.enabled = false
	tower._ensure_roaming_elite()
	check(not tower._roaming_elite.state.is_empty(), "Mansion did not enable roaming elite capability")
	if not tower._roaming_elite.state.is_empty():
		await verify_live_encounter()
	get_tree().current_scene = self
	BaseManager.force_save_failure_for_test = false
	BaseManager.unregister_runtime_checkpoint_provider(tower, false)
	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if failures.is_empty():
		print("ARMS_TAKER_ROAMING_OK checks=%d" % checks)
	else:
		for failure in failures:
			push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func verify_plans() -> void:
	var seen_limits := {}
	var rules := {"enabled": true, "elite_id": ID}
	for seed_value in 80:
		var director = DIRECTOR.new()
		director.configure(rules, seed_value, "plan_test", 12)
		var limit := int(director.state.appearance_limit)
		seen_limits[limit] = true
		check(limit >= 3 and limit <= 5 and int(director.state.next_visit) <= 5, "Plan target/first-five range failed")
		var actor := Enemy3D.new()
		actor.enemy_data = {"roaming_elite_session_id": director.state.session_id}
		actor.max_hp = 2000
		actor.current_hp = 2000
		for index in 12:
			var room_id := "room_%d" % index
			director.observe_room(room_id)
			var before: Dictionary = director.export_snapshot()
			director.observe_room(room_id)
			check(director.state == before, "Revisit changed deterministic plan")
			if not director.pending_in(room_id):
				continue
			var hp := int(director.state.hp)
			actor.max_hp = 9999
			actor.current_hp = 9999
			if hp == 0:
				actor.max_hp = 2000
				actor.current_hp = 2000
			director.bind_actor(actor)
			check(actor.max_hp == 2000 and actor.current_hp == (2000 if hp == 0 else hp), "Reappearance healed or rescaled HP")
			actor.current_hp -= 200
			actor._elite_encounter_damage_taken = 200
			director.stage_escape(actor)
			var restored = DIRECTOR.new()
			restored.configure(rules, seed_value, "plan_test", 12)
			check(restored.import_snapshot(director.export_snapshot()) and restored.state == director.state, "Between-appearance journal did not round-trip")
			director = restored
		check(int(director.state.appearances) == limit and director.state.status == "finished", "Plan did not reach target within room budget")
		if seed_value == 0:
			var valid: Dictionary = director.export_snapshot()
			var invalid := valid.duplicate(true)
			invalid.hp = int(invalid.max_hp) + 1
			check(not director.import_snapshot(invalid) and director.state == valid, "Invalid journal changed the live encounter")
		actor.free()
	check(seen_limits.size() == 3, "Seeds did not exercise 3, 4 and 5 appearances")


func members(room: DungeonRoom3D) -> Array:
	return tower._enemy_nodes_by_room.get(room.room_id, []) as Array


func find_roamer(room: DungeonRoom3D) -> Enemy3D:
	for value in members(room):
		if is_instance_valid(value) and tower._roaming_elite.owns(value.enemy_data):
			return value as Enemy3D
	return null


func verify_live_encounter() -> void:
	var expected_limit := int(tower._roaming_elite.state.appearance_limit)
	var last_hp := 0
	var frozen_max := 0
	var appearances := 0
	var verified_authored_room := false
	for room: DungeonRoom3D in tower._rooms:
		if room.room_type not in tower._roaming_elite.rules.room_types or room.authored_layout_peaceful:
			continue
		tower.player.global_position = room.global_position + Vector3(0, 0.05, 0)
		tower._on_room_entered(room)
		tower._retry_roaming_elite()
		await get_tree().process_frame
		var elite := find_roamer(room)
		if elite == null:
			continue
		appearances += 1
		for other: Enemy3D in members(room):
			if other != elite:
				check(elite.global_position.distance_to(other.global_position) >= 2.0, "Roaming elite spawned inside an existing enemy")
		check(int(tower._roaming_elite.state.appearances) == appearances, "Live appearance count duplicated")
		if appearances == 1:
			frozen_max = elite.max_hp
			check(elite.max_hp > 1000, "20x initial HP did not reach real mansion actor")
		else:
			check(elite.max_hp == frozen_max and elite.current_hp == last_hp, "Real next-room spawn healed or multiplied HP")
		var normal_count := 0
		for enemy: Enemy3D in members(room).duplicate():
			if tower._counts_for_room_clear(enemy.enemy_data):
				normal_count += 1
		check(int(tower._alive_by_room.get(room.room_id, 0)) == normal_count + tower._reserved_spawn_count(room.room_id), "Elite contributed to room alive count")
		if not verified_authored_room and not room.spawn_placements.is_empty() and room.room_type in Dungeon3D.HOSTILE_ROOM_TYPES:
			check(normal_count == 0 and not room.cleared, "Ordinary room spawned before its seal delay")
			tower._capture_room_runtime_state(room.room_id)
			tower._restore_room_runtime_state(room.room_id)
			check(not tower._room_wave_totals.has(room.room_id), "Elite-only pre-wave snapshot became an established combat wave")
			await get_tree().create_timer(1.85).timeout
			check(tower._has_room_clear_actor(room.room_id), "Roamer suppressed the original authored wave after the seal delay")
			check(tower._room_is_sealed(room.room_id) and not room.cleared, "Original authored combat lost its door seal")
			check(find_roamer(room) == elite, "Original wave replaced the roaming elite")
			var ordinary: Enemy3D
			for member: Enemy3D in members(room):
				if tower._counts_for_room_clear(member.enemy_data):
					ordinary = member
					break
			if ordinary != null:
				var persistent_id := ordinary.get_persistent_id()
				ordinary.take_damage(1)
				var saved_hp := ordinary.current_hp
				tower._capture_room_runtime_state(room.room_id)
				tower._enemy_nodes_by_room[room.room_id] = [elite]
				for member in tower.get_node("ActiveEnemies").get_children():
					if member is Enemy3D and member.room_id == room.room_id and tower._counts_for_room_clear(member.enemy_data):
						member.free()
				tower._restore_room_runtime_state(room.room_id)
				var restored := false
				for member: Enemy3D in members(room):
					if member.get_persistent_id() == persistent_id and member.current_hp == saved_hp:
						restored = true
				check(restored and find_roamer(room) == elite, "Live roamer blocked ordinary combat snapshot restoration")
			verified_authored_room = true
		# A controlled single wave exercises the actual kill/clear/door callback.
		for enemy: Enemy3D in members(room).duplicate():
			if enemy != elite:
				enemy.free()
		tower._enemy_nodes_by_room[room.room_id] = [elite]
		tower._reserved_room_spawns.erase(room.room_id)
		tower._pending_delayed_spawns.erase(room.room_id)
		tower._room_spawn_blocked.erase(room.room_id)
		tower._alive_by_room[room.room_id] = 0
		room.cleared = false
		var normal: Array[Dictionary] = [{"enemy_type": "egt_bullet_kin", "hp": 20, "damage": 1}]
		check(tower._commit_room_waves(room, [normal, normal.duplicate(true)]), "Controlled room wave failed")
		for enemy: Enemy3D in members(room).duplicate():
			if enemy != elite:
				enemy._die()
		check(tower._wave_spawn_pending.has(room.room_id), "Elite blocked the next normal wave")
		var deadline := Time.get_ticks_msec() + 4500
		while int(tower._room_wave_numbers[room.room_id]) < 2 and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		check(int(tower._room_wave_numbers[room.room_id]) == 2, "Next normal wave did not arrive with elite present in %s (alive=%d, pending=%s, current=%s)" % [
			room.room_id, int(tower._alive_by_room.get(room.room_id, 0)), tower._wave_spawn_pending.has(room.room_id), tower._current_room_id,
		])
		for enemy: Enemy3D in members(room).duplicate():
			if enemy != elite:
				enemy._die()
		check(room.cleared and members(room).has(elite) and elite.current_hp > 0, "Normal clear did not unlock while elite remained")
		for direction in room.door_targets:
			var door: Node = room.get_door_node(str(direction))
			if door != null and not str(room.door_targets[direction]).is_empty():
				check(bool(door.get("openable")), "Elite kept a cleared mansion door locked")
		if appearances == 1:
			verify_rent(elite)
			verify_health_potion(elite)
			await verify_independent_queues(room)
			# Real streaming rebuild of an elite in an already cleared room.
			elite.take_damage(1)
			var damaged_hp := elite.current_hp
			var active_snapshot := tower.build_runtime_save_snapshot()
			tower._hibernate_room_entities(room.room_id)
			room.set_stream_state(DungeonRoom3D.STREAM_DATA_ONLY)
			tower._room_graph_runtime.erase_stream_state(room.room_id)
			await get_tree().process_frame
			tower._roaming_elite.state.clear()
			tower._restore_runtime_save_snapshot(active_snapshot)
			check(int(tower._roaming_elite.state.get("hp", 0)) == damaged_hp, "Active encounter world snapshot lost HP")
			tower.player.global_position = room.global_position + Vector3(0, 0.05, 0)
			tower._on_room_entered(room)
			elite = find_roamer(room)
			check(elite != null and elite.current_hp == damaged_hp and elite._elite_encounter_damage_taken == 1, "Cleared-room stream restore dropped/healed elite")
			if elite == null:
				return
		var threshold := int(ceil(elite.max_hp * 0.1))
		var needed := threshold - elite._elite_encounter_damage_taken
		elite.take_damage(needed - 1)
		check(not elite._elite_escape_active, "Elite retreated before 10 percent actual damage")
		elite.take_damage(1)
		check(elite._elite_escape_active, "Elite did not retreat at 10 percent damage")
		last_hp = elite.current_hp
		var journal: Dictionary = tower._roaming_elite.export_snapshot()
		var archive_before_escape := EliteRosterService.get_record(ID)
		var appearance_id := elite.get_persistent_id()
		var escape_xp := int((EliteRosterService.get_definition(ID).growth_profile.xp_rewards as Dictionary).get("escape", 0))
		BaseManager.force_save_failure_for_test = true
		check(not tower.commit_roaming_elite_escape(elite, {"room_id": room.room_id}), "Failed save accepted retreat")
		check(tower._roaming_elite.state == journal and members(room).has(elite), "Failed retreat save lost actor or journal")
		check(EliteRosterService.get_record(ID) == archive_before_escape, "撤退保存失败改变 XP 或 receipt")
		BaseManager.force_save_failure_for_test = false
		elite._complete_elite_escape()
		check(not members(room).has(elite), "Durable retreat retained old room actor")
		check(int(EliteRosterService.get_record(ID).escape_count) == (1 if appearances == expected_limit else 0), "Intermediate retreat grew cross-run archive")
		var escaped_record := EliteRosterService.get_record(ID)
		check(int(escaped_record.get("xp", 0)) == int(archive_before_escape.get("xp", 0)) + escape_xp, "每次 appearance 撤退未恰好增加一次 escape XP")
		check((escaped_record.get("xp_event_ids", []) as Array).has(appearance_id), "撤退 XP 未使用 appearance 稳定 ID")
		if appearances < expected_limit:
			EliteRosterService.commit_run_record(ID, tower._roaming_elite.export_snapshot(), tower.build_runtime_save_snapshot(), {
				"kind": "escape", "receipt_id": appearance_id, "xp_event_id": appearance_id,
			})
			check(EliteRosterService.get_record(ID) == escaped_record, "相同 escape receipt 重试重复计 XP 或改变档案")
		var stored := BaseManager.get_active_run_checkpoint()
		check((stored.get("world_state", {}) as Dictionary).get("roaming_elite", {}) == tower._roaming_elite.state, "Profile checkpoint lost encounter journal")
		await get_tree().process_frame
	check(verified_authored_room, "Fixture did not exercise a roaming appearance in an authored combat room")
	check(appearances == expected_limit and tower._roaming_elite.state.status == "finished", "Mansion did not deliver target appearances")
	# Reload from disk verifies profile receipts, checkpoint, and reservation retention.
	var before_record := EliteRosterService.get_record(ID)
	BaseManager.load_base()
	check(JSON.parse_string(JSON.stringify(EliteRosterService.get_record(ID))) == JSON.parse_string(JSON.stringify(before_record)), "Profile reload changed elite archive values")
	check(int((BaseManager.get_active_run_checkpoint().world_state.roaming_elite as Dictionary).hp) == last_hp, "Disk reload refilled encounter HP")
	print("ROAMING_LIVE appearances=%d max_hp=%d remaining_hp=%d" % [appearances, frozen_max, last_hp])
	await verify_player_killer_outcome()
	await verify_death_outcome()


func verify_player_killer_outcome() -> void:
	tower._run_id += ":player_killer"
	tower._roaming_elite = DIRECTOR.new()
	tower._ensure_roaming_elite()
	tower._roaming_elite.state.next_visit = 1
	var room := tower._room_by_id[tower._current_room_id] as DungeonRoom3D
	tower._observe_roaming_elite_room(room)
	tower._retry_roaming_elite()
	var elite := find_roamer(room)
	check(elite != null, "Player-killer fixture did not spawn")
	if elite == null:
		return
	tower.player.notify_attacked_by(elite)
	tower._settle_player_killer_elite()
	check(tower._player_killer_elite_settled and tower._roaming_elite.state.status == "finished", "Player kill left a phantom active encounter")
	check(find_roamer(room) == null and room.cleared, "Player-killer elite did not leave independently")
	var record := EliteRosterService.get_record(ID)
	check(record.reserved_encounter_id == "" and int(record.history.killed_player_count) == 1, "Player kill did not persist one terminal settlement")
	check(BaseManager.get_active_run_checkpoint().world_state.roaming_elite.status == "finished", "Player-kill checkpoint retained active encounter")
	await get_tree().process_frame


func verify_death_outcome() -> void:
	# Fresh run identity, same persistent elite archive.
	tower._run_id += ":death_retry"
	tower._roaming_elite = DIRECTOR.new()
	tower._ensure_roaming_elite()
	tower._roaming_elite.state.next_visit = 1
	var room := tower._room_by_id[tower._current_room_id] as DungeonRoom3D
	tower._observe_roaming_elite_room(room)
	tower._retry_roaming_elite()
	var elite := find_roamer(room)
	check(elite != null, "Death retry fixture did not spawn")
	if elite == null:
		return
	var inventory: Array = []
	for index in 5:
		var item := ItemRegistry.get_instance().get_item("weapon_pistol").duplicate(true)
		item["weapon_instance_id"] = "defeat_weapon_%d" % index
		item["custom_marker"] = "defeat_half_probe"
		item["current_ammo"] = 3 + index
		item["durability"] = 41 + index
		item["attachments"] = {"probe": index}
		inventory.append({"item": item, "count": 1, "receipt_id": "defeat_receipt_%d" % index})
	var fixture_record := BaseManager.get_elite_archive_record(ID)
	fixture_record["stolen_items"] = inventory.duplicate(true)
	check(BaseManager.commit_elite_archive_record(ID, fixture_record, "defeat_inventory_fixture"), "战败库存 fixture 写入失败")
	var killed_before := tower._kills
	var pickups_before := get_tree().get_nodes_in_group("ground_loot_3d")
	var journal_before := tower._roaming_elite.export_snapshot()
	var archive_before := EliteRosterService.get_record(ID)
	var checkpoint_before := BaseManager.get_active_run_checkpoint()
	BaseManager.force_save_failure_for_test = true
	elite.take_damage(elite.current_hp + 1)
	check(elite._elite_defeat_active and elite.ai_state != "dead", "低血致死大伤害未优先进入战败 kneel")
	check(tower._roaming_elite.state.status == "active", "战败 kneel 前提前改变 roaming 状态")
	for _frame in 180:
		elite._physics_process(1.0 / 60.0)
	check(is_instance_valid(elite) and elite._elite_defeat_active, "保存失败时战败实体提前消失")
	check(get_tree().get_nodes_in_group("ground_loot_3d") == pickups_before, "失败掉落仍留在 group，污染同帧重试")
	check(EliteRosterService.get_record(ID) == archive_before and BaseManager.get_active_run_checkpoint() == checkpoint_before, "战败失败改变库存或持久 checkpoint")
	check(tower._roaming_elite.state.status == journal_before.status and members(room).has(elite), "战败失败未恢复 journal 或房间成员")
	BaseManager.force_save_failure_for_test = false
	for _frame in 180:
		if not is_instance_valid(elite):
			break
		elite._physics_process(1.0 / 60.0)
	await get_tree().process_frame
	var record := EliteRosterService.get_record(ID)
	check(record.state == "Defeated" and int(record.defeat_count) == 1, "战败重试未完成唯一结算")
	check(tower._roaming_elite.state.status == "defeated", "战败未写入独立 defeated roaming 状态")
	check(tower._kills == killed_before and room.cleared, "战败错误增加普通击杀归属或未清房")
	var dropped_items: Array = []
	for value in get_tree().get_nodes_in_group("ground_loot_3d"):
		if value is GroundLootPickup3D and not pickups_before.has(value) and value.item_data.get("custom_marker", "") == "defeat_half_probe":
			dropped_items.append(value.item_data.duplicate(true))
			check(value.visible and value.monitoring and value.is_processing(), "成功掉落未重新开放交互")
	check(dropped_items.size() == 3, "五条单件库存未按总量 ceil(5/2) 掉落三件")
	for index in mini(3, dropped_items.size()):
		var dropped := dropped_items[index] as Dictionary
		var original := inventory[index].item as Dictionary
		for key in ["weapon_instance_id", "current_ammo", "durability", "attachments"]:
			check(dropped.get(key) == original.get(key), "掉落顺序或武器 metadata 丢失：%s" % key)
	var expected_remaining := inventory.slice(3).duplicate(true)
	check(record.get("stolen_items", []) == expected_remaining, "未掉落库存未保持顺序及完整武器实例")
	var checkpoint := BaseManager.get_active_run_checkpoint()
	var segments := (checkpoint.get("world_state", {}) as Dictionary).get("segment_runtime_state", {}) as Dictionary
	var saved_items := (segments.get(room.room_id, {}) as Dictionary).get("ground_items", []) as Array
	var saved_drops := 0
	for value in saved_items:
		if (value.get("item_data", {}) as Dictionary).get("custom_marker", "") == "defeat_half_probe":
			saved_drops += 1
	check(saved_drops == 3, "事务 checkpoint 漏掉尚未开放的 pending pickups")
	await get_tree().process_frame
	tower._retry_roaming_elite()
	check(find_roamer(room) == null, "已战败收租人重新出现")


func verify_independent_queues(room: DungeonRoom3D) -> void:
	var config := {"enemy_type": "melee_chaser", "is_elite": true, "elite_id": "elite_spore_devourer", "persistent_id": "independent_queue_probe"}
	tower._reserved_room_spawns[room.room_id] = [{"configs": [config]}]
	check(tower._reserved_spawn_count(room.room_id) == 0, "Reserved unique elite counted toward clear")
	tower._reserved_room_spawns.erase(room.room_id)
	tower._queue_delayed_spawn(room, config, room.global_position + Vector3(2, 0.05, 2), 0.05)
	check(tower._pending_delayed_spawn_count(room.room_id) == 0 and not tower._room_has_pending_combat(room), "Delayed unique elite blocked a cleared room")
	await get_tree().create_timer(0.1).timeout
	var found := false
	for enemy: Enemy3D in members(room).duplicate():
		if enemy.get_persistent_id() == "independent_queue_probe":
			found = true
			check(tower._claim_enemy_departure(enemy) and int(tower._alive_by_room[room.room_id]) == 0, "Independent elite departure decremented combat count")
			enemy.free()
	check(found and room.cleared, "Delayed unique elite did not spawn independently")


func potion_count(record: Dictionary) -> int:
	var count := 0
	for entry in record.get("stolen_items", []):
		if (entry.get("item", {}) as Dictionary).get("id", "") == "item_health_potion":
			count += int(entry.get("count", 0))
	return count


func verify_health_potion(elite: Enemy3D) -> void:
	check(EliteRosterService.has_method("consume_elite_item"), "外部接口缺失：consume_elite_item，血瓶事务未验证")
	if not EliteRosterService.has_method("consume_elite_item"):
		return
	var original_hp := elite.current_hp
	var original_serial := elite._elite_healing_serial
	var original_record := BaseManager.get_elite_archive_record(ID)
	var potion := ItemRegistry.get_instance().get_item("item_health_potion")
	var heal_amount := int(potion.get("heal_amount", 0))
	check(heal_amount > 0, "ItemRegistry 血瓶未提供正治疗量")
	var fixture := original_record.duplicate(true)
	fixture["stolen_items"] = [{"item": potion.duplicate(true), "count": 3, "receipt_id": "healing_fixture"}]
	check(BaseManager.commit_elite_archive_record(ID, fixture, "healing_fixture"), "血瓶 fixture 写入失败")
	elite.current_hp = elite.max_hp
	var before := EliteRosterService.get_record(ID)
	check(not tower.try_use_arms_taker_health_potion(elite) and EliteRosterService.get_record(ID) == before, "满血消耗血瓶")
	elite.current_hp = elite.max_hp - 3
	for blocked in ["defeat", "escape", "phase"]:
		elite._elite_defeat_active = blocked == "defeat"
		elite._elite_escape_active = blocked == "escape"
		elite.arms_taker_combat.phase_intangible = blocked == "phase"
		check(not tower.try_use_arms_taker_health_potion(elite) and elite.current_hp == elite.max_hp - 3, "禁止状态仍使用血瓶：%s" % blocked)
	elite._elite_defeat_active = false
	elite._elite_escape_active = false
	elite.arms_taker_combat.phase_intangible = false
	var journal := tower._roaming_elite.export_snapshot()
	var runtime_rooms := tower._segment_runtime_state.duplicate(true)
	var checkpoint := BaseManager.get_active_run_checkpoint()
	BaseManager.force_save_failure_for_test = true
	check(not tower.try_use_arms_taker_health_potion(elite), "保存失败接受血瓶事务")
	check(elite.current_hp == elite.max_hp - 3 and elite._elite_healing_serial == original_serial, "血瓶失败未恢复 HP/serial")
	check(tower._roaming_elite.state == journal and tower._segment_runtime_state == runtime_rooms, "血瓶失败未恢复 journal/房间快照缓存")
	check(EliteRosterService.get_record(ID) == before and BaseManager.get_active_run_checkpoint() == checkpoint, "血瓶失败改变库存或 checkpoint")
	BaseManager.force_save_failure_for_test = false
	check(tower.try_use_arms_taker_health_potion(elite), "受伤收租人未成功使用血瓶")
	check(elite.current_hp == elite.max_hp and elite._elite_healing_serial == original_serial + 1, "血瓶未按实际缺血量治疗或 serial 错误")
	check(potion_count(EliteRosterService.get_record(ID)) == 2, "治疗未恰好消耗一瓶")
	var committed_checkpoint := BaseManager.get_active_run_checkpoint()
	var saved_journal := (committed_checkpoint.get("world_state", {}) as Dictionary).get("roaming_elite", {}) as Dictionary
	check(int(saved_journal.get("hp", -1)) == elite.current_hp, "治疗后 HP 未与消费原子写入 checkpoint")
	var transaction_id := "%s:healing:%d" % [elite.get_persistent_id(), elite._elite_healing_serial]
	var retry: Dictionary = EliteRosterService.call("consume_elite_item", ID, elite.elite_encounter_instance_id, "item_health_potion", 1, transaction_id, committed_checkpoint)
	check(bool(retry.get("already_committed", false)) and potion_count(EliteRosterService.get_record(ID)) == 2, "相同血瓶事务未幂等返回或重复消费")
	elite.current_hp = elite.max_hp - heal_amount * 2
	elite._elite_healing_cooldown = 0.0
	var original_disable_mode := elite.disable_mode
	elite.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	check(PhysicsServer3D.body_get_space(elite.get_rid()).is_valid(), "血瓶自动消费 tick 前 body 未进入物理空间")
	elite._physics_process(1.0 / 60.0)
	check(elite.current_hp == elite.max_hp - heal_amount and potion_count(EliteRosterService.get_record(ID)) == 1, "Enemy tick 未自动消费血瓶")
	var healed_hp := elite.current_hp
	check(PhysicsServer3D.body_get_space(elite.get_rid()).is_valid(), "血瓶节流 tick 前 body 未进入物理空间")
	elite._physics_process(1.0 / 60.0)
	elite.disable_mode = original_disable_mode
	check(elite.current_hp == healed_hp and elite._elite_healing_cooldown > 1.0 and potion_count(EliteRosterService.get_record(ID)) == 1, "治疗节流未阻止剩余血瓶连续消费")
	check(tower.try_use_arms_taker_health_potion(elite) and potion_count(EliteRosterService.get_record(ID)) == 0, "最后一瓶未消费")
	elite.current_hp -= 1
	check(not tower.try_use_arms_taker_health_potion(elite), "空血瓶库存仍可治疗")
	elite.current_hp = original_hp
	elite._elite_healing_serial = original_serial
	elite._elite_healing_cooldown = 0.0
	tower._roaming_elite.capture_actor(elite)
	check(BaseManager.commit_elite_and_runtime_checkpoint(ID, original_record, tower.build_runtime_save_snapshot(), "healing_fixture_restore"), "血瓶 fixture 恢复失败")


func verify_rent(elite: Enemy3D) -> void:
	tower._inventory.clear_all()
	tower._quick_inventory.clear_all()
	var item := {"id": "item_ammo_pack", "name": "验证备弹", "stackable": true, "max_stack": 10, "custom_marker": "preserve_metadata"}
	tower._inventory.put_item_in_empty_slot(0, item, 3)
	GameManager.currency = 107
	check(tower.collect_elite_rent(elite, tower.player, "item"), "Item rent did not commit")
	check(tower._inventory.get_item_count("item_ammo_pack") == 2, "Item rent did not remove exactly one")
	var record := EliteRosterService.get_record(ID)
	check(record.stolen_items.size() == 1 and record.stolen_items[0].item.custom_marker == "preserve_metadata", "Own elite archive lost full stolen item")
	check(tower.collect_elite_rent(elite, tower.player, "currency") and GameManager.currency == 97, "Currency rent is not floor(10 percent)")
	check(int(EliteRosterService.get_record(ID).stolen_currency) == 10, "Stolen currency missing from elite archive")
	var slots := tower._inventory.get_slots_snapshot()
	var serial := elite._elite_confiscation_serial
	var archive := EliteRosterService.get_record(ID)
	BaseManager.force_save_failure_for_test = true
	check(not tower.collect_elite_rent(elite, tower.player, "item"), "Failed save accepted item rent")
	check(tower._inventory.get_slots_snapshot() == slots and elite._elite_confiscation_serial == serial, "Failed save did not restore item/receipt serial")
	check(not tower.collect_elite_rent(elite, tower.player, "currency") and GameManager.currency == 97, "Failed save did not refund currency")
	check(EliteRosterService.get_record(ID) == archive, "Failed rent changed elite archive")
	BaseManager.force_save_failure_for_test = false
	tower._inventory.clear_all()
	GameManager.currency = 1
	check(tower.collect_elite_rent(elite, tower.player, "currency") and GameManager.currency == 0, "Positive wallet minimum one failed")
	check(not tower.collect_elite_rent(elite, tower.player), "Empty wallet/inventory produced rent")
