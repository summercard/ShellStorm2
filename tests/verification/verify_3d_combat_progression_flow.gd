extends Node

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 280731
	add_child(dungeon)
	await get_tree().process_frame
	await get_tree().physics_frame
	await _verify_room_light_key_recovery_and_pickups(dungeon, failures)
	dungeon.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("3D_COMBAT_PROGRESSION_FLOW_OK: balanced central light, near-player room keys, missing-key recovery, dedupe and pickup pop-spin feedback pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_room_light_key_recovery_and_pickups(dungeon: Dungeon3D, failures: Array[String]) -> void:
	var rooms_by_id := dungeon.get("_room_by_id") as Dictionary
	var target := _find_eligible_room(dungeon, rooms_by_id, true)
	if target == null:
		failures.append("Generated dungeon has no eligible room for key progression acceptance")
		return
	target.ensure_detail_built()
	await get_tree().process_frame
	var central_light := target.get("_central_light") as WastelandLight3D
	var expected_multiplier := 2.20 if target.size_class in ["large", "arena", "floor"] else 1.85
	if central_light == null or not is_equal_approx(central_light.energy, target.theme.fixture_energy * expected_multiplier):
		failures.append("Room central light does not use the reduced non-overexposed energy")

	dungeon.set("_current_room_id", target.room_id)
	dungeon.call("_update_room_streaming", target.room_id)
	var dimensions := target.get_dimensions()
	dungeon.player.global_position = target.to_global(Vector3(dimensions.x * 0.5 - 2.6, 0, dimensions.y * 0.22))
	target.cleared = true
	dungeon.call("_ensure_room_key_reward", target)
	await get_tree().process_frame
	var keys := _keys_in_room(target)
	if keys.size() != 1:
		failures.append("Cleared eligible room did not create exactly one key")
	else:
		var key := keys[0] as RoomKeyPickup3D
		var distance := dungeon.player.global_position.distance_to(key.global_position)
		var local := key.position
		if distance < 1.6 or distance > 3.6:
			failures.append("Room key is not spawned near the player after clear (distance=%.2f)" % distance)
		if absf(local.x) > dimensions.x * 0.5 - 2.0 or absf(local.z) > dimensions.y * 0.5 - 2.0:
			failures.append("Room key spawned outside the room safe boundary")
		dungeon.call("_ensure_room_key_reward", target)
		if _keys_in_room(target).size() != 1:
			failures.append("Repeated key reward check spawned a duplicate key")
		key.call("_on_body_entered", dungeon.player)
		var key_snapshot := key.get_pickup_snapshot()
		if not is_instance_valid(key) or not bool(key_snapshot.get("picked", false)) or key.is_queued_for_deletion():
			failures.append("Room key disappears in the pickup frame instead of playing pop-spin feedback")
		await get_tree().create_timer(0.42).timeout
		await get_tree().process_frame
		if is_instance_valid(key):
			failures.append("Room key pickup feedback does not recycle after its declared duration")

	var recovery_room := _find_other_eligible_room(dungeon, rooms_by_id, target.room_id)
	if recovery_room == null:
		failures.append("Generated dungeon has no second eligible room for missing-key recovery")
	else:
		recovery_room.cleared = true
		var spawned_rooms := dungeon.get("_spawned_rooms") as Dictionary
		var spawned_key_rooms := dungeon.get("_spawned_key_rooms") as Dictionary
		spawned_rooms[recovery_room.room_id] = true
		spawned_key_rooms.erase(recovery_room.room_id)
		dungeon.set("_current_room_id", recovery_room.room_id)
		dungeon.call("_on_room_entered", recovery_room)
		await get_tree().process_frame
		if _keys_in_room(recovery_room).size() != 1:
			failures.append("Returning to a cleared room does not recover a missing key reward")

	var loot := GroundLootPickup3D.new()
	loot.configure(ItemRegistry.get_instance().get_item("item_health_potion"), Color(0.38, 0.88, 0.72))
	dungeon.add_child(loot)
	await get_tree().process_frame
	loot.accept_pickup()
	var loot_snapshot := loot.get_model_snapshot()
	if not bool(loot_snapshot.get("accepted", false)) or loot.is_queued_for_deletion():
		failures.append("Ground loot disappears immediately instead of playing pickup feedback")
	await get_tree().create_timer(0.42).timeout
	await get_tree().process_frame
	if is_instance_valid(loot):
		failures.append("Ground-loot pickup feedback does not recycle after its declared duration")

	var runtime := dungeon.get_runtime_snapshot()
	if int(runtime.get("spawned_key_room_count", 0)) < 2:
		failures.append("Runtime diagnostics do not expose key reward coverage")


func _find_eligible_room(dungeon: Dungeon3D, rooms_by_id: Dictionary, prefer_large: bool) -> DungeonRoom3D:
	for record in dungeon.get_generation_snapshot().get("records", []):
		if str(record.get("type", "")) in ["START", "EXTRACTION"]:
			continue
		if prefer_large and str(record.get("size", "")) not in ["large", "arena"]:
			continue
		return rooms_by_id.get(str(record.get("id", ""))) as DungeonRoom3D
	if prefer_large:
		return _find_eligible_room(dungeon, rooms_by_id, false)
	return null


func _find_other_eligible_room(dungeon: Dungeon3D, rooms_by_id: Dictionary, excluded_id: String) -> DungeonRoom3D:
	for record in dungeon.get_generation_snapshot().get("records", []):
		var room_id := str(record.get("id", ""))
		if room_id == excluded_id or str(record.get("type", "")) in ["START", "EXTRACTION"]:
			continue
		return rooms_by_id.get(room_id) as DungeonRoom3D
	return null


func _keys_in_room(room: DungeonRoom3D) -> Array[Node]:
	var result: Array[Node] = []
	for child in room.get_children():
		if child is RoomKeyPickup3D:
			result.append(child)
	return result
