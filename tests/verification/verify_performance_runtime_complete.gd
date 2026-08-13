extends Node3D
## 性能运行时契约：质量档、失焦节能、空间索引、五态流送、状态回写/重建。

const DUNGEON_SCENE: PackedScene = preload("res://scenes/levels3d/AbyssArchive3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	_verify_focus_and_quality(failures)
	await _verify_registry_and_room_streaming(failures)
	await _verify_dynamic_entity_hibernation(failures)
	if failures.is_empty():
		print("PERFORMANCE_RUNTIME_COMPLETE_OK: 60/15 FPS focus/pause, quality profiles, spatial cleanup, five-state release/rebuild, enemy/loot persistence pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_focus_and_quality(failures: Array[String]) -> void:
	RuntimePerformanceManager.set_verification_frame_budget_override(0)
	RuntimePerformanceManager.simulate_focus_for_test(false)
	if Engine.max_fps != 15 or bool(RuntimePerformanceManager.get_snapshot().get("focused", true)):
		failures.append("Focus-out budget is not 15 FPS")
	RuntimePerformanceManager.simulate_focus_for_test(true)
	if Engine.max_fps != 60:
		failures.append("Focus-in budget did not restore 60 FPS")
	RuntimePerformanceManager.simulate_pause_for_test(true)
	if Engine.max_fps != 15 or not bool(RuntimePerformanceManager.get_snapshot().get("application_paused", false)):
		failures.append("Application pause budget is not 15 FPS")
	RuntimePerformanceManager.simulate_pause_for_test(false)
	if Engine.max_fps != 60:
		failures.append("Application resume budget did not restore 60 FPS")
	RuntimePerformanceManager.set_verification_frame_budget_override(60)
	RuntimePerformanceManager.simulate_focus_for_test(false)
	if Engine.max_fps != 60:
		failures.append("Explicit verification budget did not isolate a foreground renderer test")
	RuntimePerformanceManager.set_verification_frame_budget_override(0)
	RuntimePerformanceManager.simulate_focus_for_test(true)
	for profile in ["high", "balanced", "low"]:
		if not RuntimePerformanceManager.set_quality_profile(profile):
			failures.append("Quality profile rejected: %s" % profile)
		var expected_shadow_limit: int = int({"high": 3, "balanced": 2, "low": 1}[profile])
		if RuntimePerformanceManager.get_shadow_light_limit() != expected_shadow_limit:
			failures.append("Shadow-light budget drifted for %s" % profile)
	if RuntimePerformanceManager.set_quality_profile("invalid"):
		failures.append("Invalid quality profile was accepted")
	RuntimePerformanceManager.set_quality_profile("high")


func _verify_registry_and_room_streaming(failures: Array[String]) -> void:
	GameplaySpatialRegistry3D.clear_runtime_records()
	var probe := Node3D.new()
	probe.position = Vector3(4, 0, 4)
	add_child(probe)
	GameplaySpatialRegistry3D.register_node(probe, GameplaySpatialRegistry3D.KIND_CONNECTOR, "probe")
	if GameplaySpatialRegistry3D.query_radius(Vector3.ZERO, 8.0, [GameplaySpatialRegistry3D.KIND_CONNECTOR]).size() != 1:
		failures.append("Spatial radius query did not return its near connector")
	probe.queue_free()
	await get_tree().process_frame
	GameplaySpatialRegistry3D.prune_stale()
	if int(GameplaySpatialRegistry3D.get_snapshot().get("record_count", -1)) != 0:
		failures.append("Spatial registry retained a freed node")
	await _verify_freed_sun_cache(failures)

	var light := WastelandLight3D.new()
	light.configure(Color.WHITE, 4.0, 12.0, 20260813, true, false, "ceiling")
	add_child(light)
	await get_tree().process_frame
	RuntimePerformanceManager.set_quality_profile("high")
	light.set_runtime_active(true, false, false)
	if bool(light.get_snapshot().get("shadow_enabled", true)):
		failures.append("SHELL_READY light enabled a shadow without the runtime allowance")
	light.set_runtime_active(true, true, false)
	if not bool(light.get_snapshot().get("shadow_enabled", false)):
		failures.append("ACTIVE high-quality light did not enable its allowed shadow")
	RuntimePerformanceManager.set_quality_profile("low")
	if bool(light.get_snapshot().get("shadow_enabled", true)):
		failures.append("Low quality did not override the ACTIVE room shadow allowance")
	RuntimePerformanceManager.set_quality_profile("high")
	if not bool(light.get_snapshot().get("shadow_enabled", false)):
		failures.append("High quality did not restore the still-active room shadow allowance")
	light.queue_free()
	await get_tree().process_frame

	var room := DungeonRoom3D.new()
	room.configure({
		"room_id": "stream_contract",
		"room_type": "COMBAT",
		"size_class": "small",
		"seed": 20260813,
	})
	add_child(room)
	await get_tree().process_frame
	if room.get_stream_state() != DungeonRoom3D.STREAM_DATA_ONLY or room.get_room_snapshot().get("detail_built", true):
		failures.append("Room did not begin DATA_ONLY without runtime detail")
	room.set_stream_state(DungeonRoom3D.STREAM_PREFETCHING)
	await get_tree().process_frame
	if room.get_stream_state() != DungeonRoom3D.STREAM_SHELL_READY or not room.get_room_snapshot().get("shell_built", false):
		failures.append("PREFETCHING did not yield a SHELL_READY safety shell")
	room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	var active_snapshot := room.get_room_snapshot()
	var runtime_detail := room.get_node_or_null("RuntimeDetail")
	if not bool(active_snapshot.get("detail_built", false)) or runtime_detail == null:
		failures.append("ACTIVE room did not construct runtime detail")
	elif runtime_detail.find_child("RuntimeNavigationRegion3D", true, false) == null:
		failures.append("ACTIVE room did not construct its navigation surface")
	var active_nodes := _count_nodes(room)
	room.set_stream_state(DungeonRoom3D.STREAM_HIBERNATING)
	if not room.visible or room.process_mode != Node.PROCESS_MODE_DISABLED:
		failures.append("HIBERNATING room did not retain its visible shell while stopping logic")
	room.set_stream_state(DungeonRoom3D.STREAM_DATA_ONLY)
	await get_tree().process_frame
	var data_nodes := _count_nodes(room)
	if bool(room.get_room_snapshot().get("detail_built", true)) or room.get_node_or_null("RuntimeDetail") != null or data_nodes >= active_nodes:
		failures.append("DATA_ONLY did not release runtime detail nodes: %d -> %d" % [active_nodes, data_nodes])
	room.apply_runtime_detail_state({"room_light_on": true, "containers": {}})
	room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
	if not bool(room.get_room_snapshot().get("room_light_on", false)):
		failures.append("Room runtime light state did not restore after detail rebuild")
	room.queue_free()
	await get_tree().process_frame


func _verify_freed_sun_cache(failures: Array[String]) -> void:
	var receiver := CharacterBody3D.new()
	add_child(receiver)
	var sensor := EnemyIllumination3D.new()
	sensor.configure(receiver)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.4
	sun.light_cull_mask = EnemyIllumination3D.WORLD_RENDER_LAYER
	sun.add_to_group(EnemyIllumination3D.SUN_GROUP)
	add_child(sun)
	sensor.force_refresh(true)
	if int(sensor.get_snapshot().get("sun_light_count", 0)) != 1:
		failures.append("Illumination sensor did not cache its registered sun")
	sun.queue_free()
	await get_tree().process_frame
	# This intentionally evaluates before the one-second cache refresh. A freed
	# typed-array placeholder must be skipped instead of reaching a Light3D helper.
	var dark_candidate := sensor.find_nearby_dark_position(1.0, 4)
	if not dark_candidate.is_finite():
		failures.append("Freed sunlight cache produced an invalid dark-position result")
	sensor.force_refresh(true)
	if int(sensor.get_snapshot().get("sun_light_count", -1)) != 0:
		failures.append("Illumination sensor retained a freed sun after cache refresh")
	receiver.queue_free()
	await get_tree().process_frame


func _verify_dynamic_entity_hibernation(failures: Array[String]) -> void:
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 20260813
	add_child(dungeon)
	await get_tree().process_frame
	await get_tree().physics_frame
	var combat_room_id := ""
	for record in dungeon.get_generation_snapshot().get("records", []):
		if str(record.get("type", "")) in ["COMBAT", "ELITE", "TRAP"]:
			combat_room_id = str(record.get("id", ""))
			break
	if combat_room_id.is_empty():
		failures.append("Dynamic hibernation test could not find a hostile room")
		dungeon.queue_free()
		await get_tree().process_frame
		return
	dungeon.force_enter_room_for_test(combat_room_id)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var combat_room := (dungeon.get("_room_by_id") as Dictionary).get(combat_room_id) as DungeonRoom3D
	var live_enemies := _room_enemies(dungeon, combat_room_id)
	if live_enemies.is_empty():
		failures.append("Hostile room produced no enemy for hibernation")
	else:
		var enemy := live_enemies[0] as Enemy3D
		enemy.call("_navigation_direction", enemy.global_position + Vector3.RIGHT * 2.0, Vector3.RIGHT * 2.0)
		if not bool(enemy.get_state_snapshot().get("navigation_agent_ready", false)):
			failures.append("ACTIVE hostile room did not provide a NavigationAgent3D path surface")
		enemy.take_damage(7)
		var expected_hp := enemy.current_hp
		var expected_max_hp := enemy.max_hp
		var expected_damage := enemy.contact_damage
		var persistent_id := enemy.get_persistent_id()
		var item := ItemRegistry.get_instance().get_item("item_health_potion")
		var test_items: Array[Dictionary] = [item]
		dungeon.call("_spawn_loot_items", combat_room, test_items, combat_room.global_position)
		await get_tree().process_frame
		dungeon.force_enter_room_for_test("start")
		await get_tree().process_frame
		await get_tree().process_frame
		if not _room_enemies(dungeon, combat_room_id).is_empty():
			failures.append("DATA_ONLY room retained Enemy3D nodes")
		if _room_ground_items(dungeon, combat_room).size() != 0:
			failures.append("DATA_ONLY room retained GroundLootPickup3D nodes")
		var stored_rooms := (dungeon.get_segment_runtime_snapshot().get("rooms", {}) as Dictionary)
		var stored := stored_rooms.get(combat_room_id, {}) as Dictionary
		if (stored.get("enemies", []) as Array).size() != live_enemies.size() or (stored.get("ground_items", []) as Array).size() != 1:
			failures.append("DATA_ONLY room did not retain exact enemy/loot data")
		dungeon.force_enter_room_for_test(combat_room_id)
		await get_tree().process_frame
		var restored_enemies := _room_enemies(dungeon, combat_room_id)
		if restored_enemies.size() != live_enemies.size():
			failures.append("Reloaded room duplicated or lost enemies: %d -> %d" % [live_enemies.size(), restored_enemies.size()])
		else:
			var restored := restored_enemies.filter(
				func(value: Enemy3D) -> bool: return value.get_persistent_id() == persistent_id
			)
			if (
				restored.size() != 1
				or (restored[0] as Enemy3D).current_hp != expected_hp
				or (restored[0] as Enemy3D).max_hp != expected_max_hp
				or (restored[0] as Enemy3D).contact_damage != expected_damage
			):
				failures.append("Reloaded enemy did not preserve persistent ID, HP and damage")
		if _room_ground_items(dungeon, combat_room).size() != 1:
			failures.append("Reloaded room duplicated or lost its ground item")
		var serialized := JSON.stringify(dungeon.build_runtime_save_snapshot())
		var decoded: Variant = JSON.parse_string(serialized)
		if not decoded is Dictionary or not (decoded as Dictionary).get("world_state", {}) is Dictionary:
			failures.append("Segment runtime state is not JSON checkpoint-safe")
		else:
			var restored_dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
			restored_dungeon.test_mode = true
			restored_dungeon.run_seed_override = 20260813
			add_child(restored_dungeon)
			await get_tree().process_frame
			restored_dungeon.call("_restore_runtime_save_snapshot", decoded as Dictionary)
			await get_tree().process_frame
			var disk_restored := _room_enemies(restored_dungeon, combat_room_id).filter(
				func(value: Enemy3D) -> bool: return value.get_persistent_id() == persistent_id
			)
			if (
				disk_restored.size() != 1
				or (disk_restored[0] as Enemy3D).current_hp != expected_hp
				or (disk_restored[0] as Enemy3D).max_hp != expected_max_hp
				or (disk_restored[0] as Enemy3D).contact_damage != expected_damage
			):
				failures.append("JSON checkpoint restore did not preserve enemy ID, HP and damage")
			var restored_room := (restored_dungeon.get("_room_by_id") as Dictionary).get(combat_room_id) as DungeonRoom3D
			if _room_ground_items(restored_dungeon, restored_room).size() != 1:
				failures.append("JSON checkpoint restore did not preserve exact ground loot")
			restored_dungeon.queue_free()
			await get_tree().process_frame
	dungeon.queue_free()
	await get_tree().process_frame


func _room_enemies(dungeon: Dungeon3D, room_id: String) -> Array[Enemy3D]:
	var result: Array[Enemy3D] = []
	for value in get_tree().get_nodes_in_group("enemy_3d"):
		if value is Enemy3D and dungeon.is_ancestor_of(value) and (value as Enemy3D).room_id == room_id and not value.is_queued_for_deletion():
			result.append(value as Enemy3D)
	return result


func _room_ground_items(dungeon: Dungeon3D, room: DungeonRoom3D) -> Array[GroundLootPickup3D]:
	var result: Array[GroundLootPickup3D] = []
	for value in get_tree().get_nodes_in_group("ground_loot_3d"):
		if value is GroundLootPickup3D and dungeon.is_ancestor_of(value) and room.is_ancestor_of(value) and not value.is_queued_for_deletion():
			result.append(value as GroundLootPickup3D)
	return result


func _count_nodes(root: Node) -> int:
	var count := 1
	for child in root.get_children():
		count += _count_nodes(child)
	return count
