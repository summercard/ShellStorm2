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
		BaseManager.force_save_failure_for_test = true
		check(not tower.commit_roaming_elite_escape(elite, {"room_id": room.room_id}), "Failed save accepted retreat")
		check(tower._roaming_elite.state == journal and members(room).has(elite), "Failed retreat save lost actor or journal")
		BaseManager.force_save_failure_for_test = false
		elite._complete_elite_escape()
		check(not members(room).has(elite), "Durable retreat retained old room actor")
		check(int(EliteRosterService.get_record(ID).escape_count) == (1 if appearances == expected_limit else 0), "Intermediate retreat grew cross-run archive")
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
	var killed_before := tower._kills
	BaseManager.force_save_failure_for_test = true
	elite.take_damage(elite.current_hp + 1)
	check(elite.ai_state == "dead" and tower._roaming_elite.state.status == "killed", "Lethal damage incorrectly started retreat")
	check(tower._roaming_elite.state.has("pending_outcome") and EliteRosterService.get_record(ID).state != "Killed", "Failed death save lost retry intent")
	BaseManager.force_save_failure_for_test = false
	var saved := tower.build_runtime_save_snapshot()
	check(tower._roaming_elite.import_snapshot(saved.world_state.roaming_elite), "Pending death did not round-trip")
	tower._commit_roaming_outcome()
	tower._commit_roaming_outcome()
	var record := EliteRosterService.get_record(ID)
	check(record.state == "Killed" and int(record.death_count) == 1 and not tower._roaming_elite.state.has("pending_outcome"), "Death retry did not settle once")
	check(tower._kills == killed_before + 1 and room.cleared, "Elite death duplicated kill or changed cleared room")
	tower._retry_roaming_elite()
	check(find_roamer(room) == null, "Killed elite reappeared")


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
