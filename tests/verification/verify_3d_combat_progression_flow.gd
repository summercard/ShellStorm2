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
	await _verify_ground_loot_scatter(dungeon, failures)
	dungeon.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("3D_COMBAT_PROGRESSION_FLOW_OK: balanced central light, near-player room keys, missing-key recovery, dedupe, pickup pop-spin feedback and ground-loot scatter/camera-facing labels pass")
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
		# 头顶名牌必须正对镜头（业主 2026-09-29：俯视镜头只看到纸片侧面，一个字读不到）。
		# 反向对照：把 `_label.billboard` 改回默认（BILLBOARD_DISABLED）这条必红。
		if not bool(key_snapshot.get("label_camera_billboard", false)):
			failures.append("Room key label is not billboarded toward the camera")
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
	var loot_size_snapshot := loot.get_model_snapshot()
	var expected_item_scale := (
		GroundLootPickup3D.LEGACY_ITEM_VISUAL_SCALE
		* GroundLootPickup3D.CURRENT_BASE_SIZE_MULTIPLIER
	)
	if not (loot_size_snapshot.get("visual_scale", Vector3.ZERO) as Vector3).is_equal_approx(Vector3.ONE * expected_item_scale):
		failures.append("Ground item did not migrate from the legacy visual scale to the current 70% baseline")
	# 名牌朝向 + 不吃深度遮挡：俯视相机下这才读得到（与敌人血条同一口径）。
	if not bool(loot_size_snapshot.get("label_camera_billboard", false)):
		failures.append("Ground loot label is not billboarded toward the camera")
	if not bool(loot_size_snapshot.get("label_no_depth_test", false)):
		failures.append("Ground loot label still takes depth occlusion from furniture and walls")
	if (loot_size_snapshot.get("label_text", "") as String).is_empty():
		failures.append("Ground loot label lost its item name text")
	var weapon_loot := GroundLootPickup3D.new()
	weapon_loot.configure({
		"id": "weapon_pistol",
		"name": "Test Pistol",
		"type": "weapon",
		"assembly_id": "bp_pistol",
	})
	dungeon.add_child(weapon_loot)
	await get_tree().process_frame
	var weapon_loot_snapshot := weapon_loot.get_model_snapshot()
	var expected_weapon_scale := (
		GroundLootPickup3D.LEGACY_WEAPON_VISUAL_SCALE
		* GroundLootPickup3D.CURRENT_BASE_SIZE_MULTIPLIER
	)
	if not (weapon_loot_snapshot.get("visual_scale", Vector3.ZERO) as Vector3).is_equal_approx(Vector3.ONE * expected_weapon_scale):
		failures.append("Dropped weapon did not migrate from the legacy visual scale to the current 70% baseline")
	weapon_loot.queue_free()
	# 新掉落必须在二次落地前锁住拾取；落完两次后才开放。
	var animated_loot := GroundLootPickup3D.new()
	animated_loot.configure(ItemRegistry.get_instance().get_item("item_health_potion"), Color(0.38, 0.88, 0.72))
	dungeon.add_child(animated_loot)
	await get_tree().process_frame
	animated_loot.begin_spawn_animation()
	await get_tree().create_timer(0.12).timeout
	var airborne_snapshot := animated_loot.get_model_snapshot()
	if not bool(airborne_snapshot.get("spawn_animating", false)) or bool(airborne_snapshot.get("pickup_unlocked", true)):
		failures.append("Ground loot becomes pickable before the two-bounce landing animation finishes")
	if animated_loot.is_pickup_available():
		failures.append("Ground loot reports pickup availability while the launch animation is still running")
	var airborne_y := float((airborne_snapshot.get("visual_world_position", Vector3.ZERO) as Vector3).y)
	if airborne_y <= animated_loot.global_position.y + 0.46:
		failures.append("Ground loot launch animation does not visibly rise above the landing height")
	await get_tree().create_timer(0.92).timeout
	await get_tree().process_frame
	var settled_snapshot := animated_loot.get_model_snapshot()
	if bool(settled_snapshot.get("spawn_animating", true)) or not bool(settled_snapshot.get("pickup_unlocked", false)):
		failures.append("Ground loot does not unlock pickup after the second bounce")
	animated_loot.queue_free()
	loot.accept_pickup(dungeon.player)
	var loot_after_accept := loot.get_model_snapshot()
	if not bool(loot_after_accept.get("collecting", false)):
		failures.append("Ground loot pickup did not enter the player-collection animation")
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


## —— 地面掉落的散布与名牌朝向（业主 2026-09-29）——
## 两条诉求各自对应一组判据：
## ① 「太集中」：半径必须逐件张开、最外件超过旧螺旋的 1.6 m 上限 ⇒ 曲线与范围都真变了；
## ② 「别掉进阻挡里」：真实生成的 6 件必须全部落在房间足迹内、且落点净空为真。
## 反向对照：把 `_loot_scatter_offset` 换回 `0.7 + index * 0.18`（旧螺旋）⇒ ① 必红；
## 把 `_resolve_loot_spawn_position` 换回直接 `_find_supported_spawn_position` ⇒ ② 仍有概率绿，
## 所以 ② 只作为「不回归」的护栏，不是本次改动的独立证据。
func _verify_ground_loot_scatter(dungeon: Dungeon3D, failures: Array[String]) -> void:
	var rooms_by_id := dungeon.get("_room_by_id") as Dictionary
	var room := _find_eligible_room(dungeon, rooms_by_id, true)
	if room == null:
		failures.append("Generated dungeon has no eligible room for ground-loot scatter acceptance")
		return
	var item_count := 6
	var scatter_radius := float(dungeon.call("_loot_scatter_max_radius", room, item_count))
	if scatter_radius < Dungeon3D.LOOT_SCATTER_MIN_RADIUS_M:
		failures.append("Loot scatter outer radius collapsed below the single-item floor (%.3f)" % scatter_radius)

	var previous_radius := -1.0
	var min_pair_distance := INF
	var radii: Array[float] = []
	for index in range(item_count):
		var offset := dungeon.call("_loot_scatter_offset", index, item_count, scatter_radius) as Vector3
		var radius := Vector2(offset.x, offset.z).length()
		radii.append(radius)
		if radius < Dungeon3D.LOOT_SCATTER_MIN_RADIUS_M - 0.001:
			failures.append("Loot scatter entry %d sits closer than the single-item radius (%.3f)" % [index, radius])
		if radius <= previous_radius:
			failures.append("Loot scatter radius curve is not strictly widening at entry %d (%.3f <= %.3f)" % [index, radius, previous_radius])
		previous_radius = radius
		for other_index in range(index):
			var other := dungeon.call("_loot_scatter_offset", other_index, item_count, scatter_radius) as Vector3
			min_pair_distance = minf(min_pair_distance, (offset - other).length())
	if radii[item_count - 1] < 1.8:
		failures.append("Loot scatter stays inside the old 1.6 m spiral (outermost=%.3f)" % radii[item_count - 1])
	if min_pair_distance < 0.5:
		failures.append("Loot scatter entries stack on each other (closest pair=%.3f m)" % min_pair_distance)

	# 真实落地：房间中心放 6 件，要求散开、不出房间足迹、且每件落点净空。
	room.cleared = true
	var dimensions := room.get_dimensions()
	var origin := room.to_global(Vector3(0.0, 0.08, 0.0))
	var batch: Array[Dictionary] = []
	for index in range(item_count):
		var item := (ItemRegistry.get_instance().get_item("item_health_potion") as Dictionary).duplicate(true)
		item["count"] = 1
		batch.append(item)
	var spawned := int(dungeon.call("_spawn_loot_items", room, batch, origin))
	await get_tree().process_frame
	if spawned != item_count:
		failures.append("Ground loot batch spawn returned %d/%d" % [spawned, item_count])
	var landings: Array[Vector3] = []
	for value in get_tree().get_nodes_in_group("ground_loot_3d"):
		if (
			value is GroundLootPickup3D
			and room.is_ancestor_of(value)
			and not (value as GroundLootPickup3D).is_queued_for_deletion()
		):
			landings.append((value as GroundLootPickup3D).global_position)
	if landings.size() != item_count:
		failures.append("Ground loot batch did not leave %d world pickups (got %d)" % [item_count, landings.size()])
	var farthest := 0.0
	for landing in landings:
		var local := room.to_local(landing)
		if absf(local.x) > dimensions.x * 0.5 - 0.5 or absf(local.z) > dimensions.y * 0.5 - 0.5:
			failures.append("Ground loot landed outside the room footprint at (%.2f, %.2f)" % [local.x, local.z])
		if not bool(dungeon.call("_is_loot_landing_clear", landing)):
			failures.append("Ground loot landed inside a blocker at (%.2f, %.2f)" % [local.x, local.z])
		farthest = maxf(farthest, Vector2(local.x, local.z).length())
	if farthest < 1.9:
		failures.append("Ground loot batch stayed concentrated in the world (farthest=%.3f m)" % farthest)


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
