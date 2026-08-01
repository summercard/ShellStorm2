extends Node


func _ready() -> void:
	var failures: Array[String] = []
	var started := Time.get_ticks_usec()
	var scene := load("res://scenes/levels3d/IronFrontier3D.tscn") as PackedScene
	var dungeon := scene.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 4242
	add_child(dungeon)
	await get_tree().process_frame
	await get_tree().physics_frame
	var generation_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var generation := dungeon.get_generation_snapshot()
	var dimensions: Dictionary = generation.get("room_dimensions", {})
	if dimensions.get("small", Vector2.ZERO) != Vector2(22, 18):
		failures.append("SMALL room does not preserve enlarged parity scale")
	if dimensions.get("medium", Vector2.ZERO) != Vector2(32, 26):
		failures.append("MEDIUM room does not preserve enlarged parity scale")
	if dimensions.get("large", Vector2.ZERO) != Vector2(44, 34):
		failures.append("LARGE room does not preserve enlarged parity scale")
	if dimensions.get("arena", Vector2.ZERO) != Vector2(56, 42):
		failures.append("ARENA room is missing")

	var runtime := dungeon.get_runtime_snapshot()
	if int(runtime.get("keys", -1)) != 1 or int(runtime.get("open_edges", -1)) != 0:
		failures.append("Run must start with exactly one key and all edges locked")
	if int(runtime.get("active_rooms", -1)) != 1 or int(runtime.get("detailed_rooms", -1)) != 1:
		failures.append("Initial streaming must build only the current room")
	if int(runtime.get("active_lights", 99)) > 3:
		failures.append("Initial local light budget exceeded")
	var extraction_types := runtime.get("extraction_types", []) as Array
	if "STANDARD" not in extraction_types or "BOSS_KILL" not in extraction_types:
		failures.append("Fixed and boss conditional extraction points are not both present")

	var first_room_id := ""
	var second_room_id := ""
	for record in generation.get("records", []):
		if str(record.get("parent", "")) == "start":
			first_room_id = str(record.get("id", ""))
		if not first_room_id.is_empty() and str(record.get("parent", "")) == first_room_id and second_room_id.is_empty():
			second_room_id = str(record.get("id", ""))
	if first_room_id.is_empty() or not dungeon.try_open_room_door(first_room_id):
		failures.append("Initial key cannot open the first 3D room door")
	await get_tree().process_frame
	runtime = dungeon.get_runtime_snapshot()
	if int(runtime.get("keys", -1)) != 0 or int(runtime.get("open_edges", -1)) != 1:
		failures.append("Opening a door must consume one key and open one graph edge")
	if int(runtime.get("active_rooms", -1)) != 2:
		failures.append("Opened adjacent room was not streamed in")
	var minimap_snapshot := dungeon.minimap.get_snapshot()
	if int(minimap_snapshot.get("revealed_count", 0)) < 2 or int(minimap_snapshot.get("open_edge_count", 0)) != 1:
		failures.append("Minimap did not reveal the opened room and edge")
	dungeon.resolve_fate_choice_for_test()
	if bool(dungeon.get("_door_fate_active")):
		failures.append("Door fate selection cannot apply to the shared 3D weapon tree")

	dungeon.force_enter_room_for_test(first_room_id)
	await get_tree().process_frame
	var entered_room := _find_room(dungeon, first_room_id)
	dungeon.call("_on_room_key_collected", "test_guard")
	var keys_before_denied_open := int(dungeon.get_runtime_snapshot().get("keys", -1))
	if not second_room_id.is_empty() and dungeon.try_open_room_door(second_room_id):
		failures.append("Uncleared room incorrectly allowed door opening (first=%s second=%s current=%s type=%s cleared=%s edges=%s)" % [
			first_room_id, second_room_id,
			dungeon.get_runtime_snapshot().get("current_room_id", "?"),
			entered_room.room_type if entered_room != null else "?", entered_room.cleared if entered_room != null else false,
			dungeon.get_runtime_snapshot().get("edge_states", {}),
		])
	if int(dungeon.get_runtime_snapshot().get("keys", -1)) != keys_before_denied_open:
		failures.append("Denied door opening consumed a key")
	var enemies := get_tree().get_nodes_in_group("enemy_3d").filter(func(node): return dungeon.is_ancestor_of(node))
	for enemy in enemies:
		if enemy is Enemy3D and (enemy as Enemy3D).room_id == first_room_id:
			(enemy as Enemy3D).take_damage(999999, false, Vector3.FORWARD)
	await get_tree().process_frame
	var room := _find_room(dungeon, first_room_id)
	if room == null or not room.cleared:
		failures.append("Killing all enemies did not clear the room")
	var keys := get_tree().get_nodes_in_group("room_key_pickup_3d").filter(func(node): return room != null and room.is_ancestor_of(node))
	if keys.is_empty():
		failures.append("Cleared combat room did not drop a physical 3D key")
	if not second_room_id.is_empty() and not dungeon.try_open_room_door(second_room_id):
		failures.append("Cleared room plus key cannot open the next edge")

	_verify_inventory_and_insurance(dungeon, failures)
	_verify_weapon_tree(dungeon, failures)
	_verify_vision(dungeon, failures)
	await _verify_pools(dungeon, failures)
	_verify_loot_contract(failures)
	_verify_elite_and_boss_runtime(dungeon, failures)
	await _verify_multi_wave_room(dungeon, generation, failures)
	await _verify_extraction_interruption(dungeon, failures)

	var node_count := _count_nodes(dungeon)
	if node_count > 1900:
		failures.append("Streamed parity slice exceeds node budget: %d" % node_count)
	if generation_ms > 1500.0:
		failures.append("Initial streamed generation is too slow: %.1fms" % generation_ms)
	_finish(failures, generation_ms, node_count, dungeon.get_runtime_snapshot())


func _verify_inventory_and_insurance(dungeon: Dungeon3D, failures: Array[String]) -> void:
	var inventory := dungeon.get_inventory_module()
	var insurance := dungeon.get_insurance_module()
	if inventory.get_capacity() != 12 or insurance.get_max_slots() != 2:
		failures.append("12-slot inventory / 2-slot insurance contract missing")
	var all_items := ItemRegistry.get_instance().get_all_items()
	var added_ids: Dictionary = {}
	for item in all_items:
		var item_id := str(item.get("id", ""))
		if item_id.is_empty() or added_ids.has(item_id):
			continue
		var single := item.duplicate(true)
		single["stack_max"] = 1
		if inventory.add_item(single, 1) > 0:
			added_ids[item_id] = true
		if inventory.get_used_slots() == 12:
			break
	if inventory.get_used_slots() != 12:
		failures.append("Inventory could not fill all 12 slots")
	var overflow := {"id": "parity_overflow", "name": "溢出测试", "stack_max": 1}
	if inventory.add_item(overflow, 1) != 0:
		failures.append("Full inventory accepted overflow loot")
	if not insurance.insure_item(inventory, 0) or insurance.get_used_slots() != 1:
		failures.append("Inventory item cannot move to insurance")
	var claimed := insurance.claim_item(0)
	if claimed.is_empty() or inventory.add_item(claimed, 1) != 1:
		failures.append("Insured item cannot return to inventory")


func _verify_weapon_tree(dungeon: Dungeon3D, failures: Array[String]) -> void:
	var tree := dungeon.player.get_weapon_tree()
	var root := tree.get_root()
	var existing := root.slots.get(AssemblyNode.SlotType.MUZZLE) as AssemblyNode
	if existing != null:
		tree.unmount(existing)
		existing.free()
	var attachment := BlueprintRegistry.create_assembly_node("attach_triple_muzzle")
	if attachment == null or not tree.mount(root, AssemblyNode.SlotType.MUZZLE, attachment):
		failures.append("Attachment cannot mount into the shared WeaponAssemblyTree")
		return
	var tree_count := int(tree.get_computed_stats().get("bullet_count", 0))
	var model_count := int(dungeon.player.get_weapon_snapshot().get("projectile_count", 0))
	if tree_count != model_count or tree_count < 3:
		failures.append("3D weapon model is not synchronized from assembly-tree attachment stats")


func _verify_vision(dungeon: Dungeon3D, failures: Array[String]) -> void:
	var vision := dungeon.player.get_node_or_null("PlayerVision3D") as PlayerVision3D
	if vision == null:
		failures.append("PlayerVision3D is missing")
		return
	dungeon.player.global_position = Vector3(0, 0.05, 0)
	dungeon.player.aim_direction = Vector3(0, 0, -1)
	dungeon.player.aim_yaw = 0.0
	if not vision.is_position_visible(Vector3(0, 0.7, -8.0)):
		failures.append("Clear point inside the presentation cone is not visible")
	if vision.is_position_visible(Vector3(0, 0.7, -18.0)):
		failures.append("North wall failed to occlude a point behind it")
	var snapshot := vision.get_snapshot()
	if (
		not is_equal_approx(float(snapshot.get("gameplay_angle_degrees", 0.0)), 360.0)
		or float(snapshot.get("presentation_angle_degrees", 0.0)) <= 0.0
		or not bool(snapshot.get("wall_occlusion_enabled", false))
	):
		failures.append("360 gameplay / directional presentation vision contract missing")


func _verify_pools(dungeon: Dungeon3D, failures: Array[String]) -> void:
	var pool := dungeon.get_node("ProjectilePool3D") as ProjectilePool3D
	var config := {"direction": Vector3.FORWARD, "speed": 0.0, "damage": 1, "hostile": false, "tags": [], "color": Color.WHITE, "shooter": dungeon.player}
	var batch: Array[Projectile3D] = []
	for index in range(24):
		batch.append(pool.acquire(config, Vector3(index * 0.05, 4, 0)))
	for projectile in batch:
		projectile.call("_retire")
	await get_tree().process_frame
	var created_once := int(pool.get_snapshot().get("created", 0))
	batch.clear()
	for index in range(24):
		batch.append(pool.acquire(config, Vector3(index * 0.05, 4, 0)))
	var created_twice := int(pool.get_snapshot().get("created", 0))
	if created_once != created_twice:
		failures.append("Projectile pool allocated a second identical batch")
	for projectile in batch:
		projectile.call("_retire")


func _verify_loot_contract(failures: Array[String]) -> void:
	var injector := MonsterInjector.new()
	injector.set_seed(4242)
	var elite := injector.generate_enemies({"type": "elite", "floor": 2, "floor_level": RoomData.FloorLevel.MEDIUM})
	var boss := injector.generate_enemies({"type": "boss", "floor": 2, "floor_level": RoomData.FloorLevel.DEEP})
	var loot := LootModule.new()
	loot.set_seed(4242)
	if elite.is_empty() or loot.generate_enemy_loot(elite[0]).is_empty():
		failures.append("Elite 3D configuration does not use the original stable drop table")
	if boss.is_empty() or loot.generate_enemy_loot(boss[0]).is_empty():
		failures.append("Boss 3D configuration does not use the original stable drop table")


func _verify_elite_and_boss_runtime(dungeon: Dungeon3D, failures: Array[String]) -> void:
	var avatar_scene := load("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn") as PackedScene
	for modifier_id in ["Elite.Huge", "Elite.SpawnOnDeath", "Elite.Ricochet", "Elite.Parasite", "Elite.WeaponParasite", "Elite.BulletEater"]:
		var elite := avatar_scene.instantiate() as Enemy3D
		dungeon.get_node("ActiveEnemies").add_child(elite)
		elite.configure_from_enemy_data({
			"enemy_type": "shielded", "hp": 100, "max_hp": 100, "damage": 10, "speed": 60,
			"is_elite": true, "modifier_id_en": modifier_id, "modifier_data": MonsterInjector.ELITE_MODIFIERS.get("巨大化", {}),
		})
		var snapshot := elite.get_state_snapshot()
		if str(snapshot.get("elite_modifier_id", "")) != modifier_id:
			failures.append("Elite modifier missing from 3D runtime: %s" % modifier_id)
		if modifier_id == "Elite.BulletEater" and not elite.can_absorb_projectile([]):
			failures.append("BulletEater elite cannot absorb a 3D projectile")
		elite.queue_free()
	var boss_scene := load("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn") as PackedScene
	var boss := boss_scene.instantiate() as Enemy3D
	dungeon.get_node("ActiveEnemies").add_child(boss)
	boss.configure_from_enemy_data({"enemy_type": "boss", "hp": 300, "max_hp": 300, "damage": 20, "speed": 60})
	dungeon.call("_show_boss_hud", boss)
	var boss_panel := dungeon.get_node_or_null("HUD/BossHUD3D") as PanelContainer
	if boss_panel == null or not boss_panel.visible:
		failures.append("Boss 3D health/phase HUD did not appear")
	boss.take_damage(int(ceil(float(boss.max_hp) * 0.36)), false, Vector3.FORWARD)
	if boss.boss_phase < 2:
		failures.append("Boss did not enter phase 2 at the original health threshold")
	boss.take_damage(int(ceil(float(boss.max_hp) * 0.36)), false, Vector3.FORWARD)
	if boss.boss_phase < 3:
		failures.append("Boss did not enter phase 3 at the original health threshold")
	dungeon.call("_hide_boss_hud")
	boss.queue_free()


func _verify_multi_wave_room(dungeon: Dungeon3D, generation: Dictionary, failures: Array[String]) -> void:
	var target_id := ""
	for record in generation.get("records", []):
		if str(record.get("type", "")) == "COMBAT" and int(record.get("index", 0)) >= 4:
			target_id = str(record.get("id", ""))
			break
	if target_id.is_empty():
		failures.append("Generated layout has no deep combat room for wave parity")
		return
	dungeon.force_enter_room_for_test(target_id)
	await get_tree().process_frame
	var before := dungeon.get_runtime_snapshot()
	if int((before.get("wave_totals", {}) as Dictionary).get(target_id, 1)) < 2:
		failures.append("Medium/deep combat room did not split into multiple 3D waves")
		return
	for value in get_tree().get_nodes_in_group("enemy_3d"):
		var enemy := value as Enemy3D
		if enemy != null and dungeon.is_ancestor_of(enemy) and enemy.room_id == target_id and enemy.ai_state != "dead":
			enemy.take_damage(999999, false, Vector3.FORWARD)
	var deadline := Time.get_ticks_msec() + 3200
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var wave_now := int(((dungeon.get_runtime_snapshot().get("wave_numbers", {}) as Dictionary).get(target_id, 1)))
		if wave_now >= 2:
			break
		for value in get_tree().get_nodes_in_group("enemy_3d"):
			var enemy := value as Enemy3D
			if enemy != null and dungeon.is_ancestor_of(enemy) and enemy.room_id == target_id and enemy.ai_state != "dead":
				enemy.take_damage(999999, false, Vector3.FORWARD)
	var after := dungeon.get_runtime_snapshot()
	if int((after.get("wave_numbers", {}) as Dictionary).get(target_id, 1)) < 2:
		failures.append("Clearing a wave did not schedule the next 3D reinforcement wave")


func _verify_extraction_interruption(dungeon: Dungeon3D, failures: Array[String]) -> void:
	if bool(dungeon.get("_door_fate_active")):
		dungeon.resolve_fate_choice_for_test()
		await get_tree().process_frame
	var beacon := dungeon.get("_standard_extraction") as ExtractionBeacon3D
	if beacon == null or not beacon.force_start_for_test():
		failures.append("Fixed extraction cannot begin its 3D countdown")
		return
	await get_tree().process_frame
	if dungeon.player.input_locked or not bool(dungeon.get_runtime_snapshot().get("extraction_defense_active", false)):
		failures.append("Extraction countdown did not preserve movement while starting defense")
	dungeon.player.is_invincible = false
	dungeon.player.take_damage(1, false, Vector3.ZERO)
	await get_tree().process_frame
	if dungeon.player.input_locked or not bool(dungeon.get_runtime_snapshot().get("extraction_defense_active", false)):
		failures.append("Taking damage interrupted the free-movement extraction countdown")
	var beacon_snapshot := beacon.get_snapshot()
	if not bool(beacon_snapshot.get("active", false)):
		failures.append("Taking damage cancelled the extraction beacon")


func _find_room(dungeon: Dungeon3D, room_id: String) -> DungeonRoom3D:
	for value in get_tree().get_nodes_in_group("dungeon_room_3d"):
		var room := value as DungeonRoom3D
		if room != null and dungeon.is_ancestor_of(room) and room.room_id == room_id:
			return room
	return null


func _count_nodes(root: Node) -> int:
	var count := 1
	for child in root.get_children():
		count += _count_nodes(child)
	return count


func _finish(failures: Array[String], generation_ms: float, node_count: int, runtime: Dictionary) -> void:
	if failures.is_empty():
		print("3D_PARITY_CORE_OK: room scale, locked keys/doors, clear reward, inventory/insurance, shared weapon tree, occluded vision, original loot tables and pools pass (generation_ms=%.1f nodes=%d runtime=%s)" % [generation_ms, node_count, runtime])
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
