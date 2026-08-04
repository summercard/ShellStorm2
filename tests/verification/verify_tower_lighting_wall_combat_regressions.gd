extends Node
## 灯光分层、9m墙、南墙摄像机标记、隐藏连接器碰撞和刷怪软锁综合回归。

const TOWER_SCENE: PackedScene = preload("res://scenes/TowerDescent3D.tscn")
const HOSTILE_TYPES: Array[String] = [
	"COMBAT", "ELITE", "BOSS", "TRAP", "BASEMENT", "STORAGE", "SCAVENGE",
]


func _ready() -> void:
	var failures: Array[String] = []
	var tower := TOWER_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await _validate_light_layers(tower, failures)
	_validate_floor_materials(failures)
	_validate_wall_components(tower, failures)
	await _validate_close_wall_probes(tower, failures)
	_validate_stair_camera_walls(tower, failures)
	await _validate_internal_partition_camera_wall(tower, failures)
	_validate_hidden_connector_collisions(tower, failures)
	await _validate_target_room_airwall_clearance(tower, failures)
	await _validate_revealed_room_enemy_prewarm(failures)
	_validate_hostile_room_spawning(tower, failures)
	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("TOWER_LIGHTING_WALL_COMBAT_REGRESSIONS_OK: flashlight shadow stability, external avatar shadows, matte floors, 9m walls, visible collision parity and reveal-time hostile spawning pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _validate_light_layers(tower: TowerDescent3D, failures: Array[String]) -> void:
	var sun := tower.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if (
		sun == null
		or not sun.shadow_enabled
		or sun.light_cull_mask != 3
		or sun.shadow_caster_mask != 3
	):
		failures.append("Sun does not cast shadows onto both environment and avatar layers")
	elif sun.light_energy > 0.60:
		failures.append("Sun energy is still overexposed: %.2f" % sun.light_energy)
	var avatar_casters := 0
	for value in tower.player.avatar.find_children("*", "MeshInstance3D", true, false):
		var mesh := value as MeshInstance3D
		if mesh.layers == 2 and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			avatar_casters += 1
	if avatar_casters <= 0:
		failures.append("Avatar has no external-light shadow casters on render layer 2")
	var flashlight := tower.player.get_node_or_null("PlayerFlashlight3D") as PlayerFlashlight3D
	if flashlight == null:
		failures.append("Player three-light rig is missing")
		return
	flashlight.set_light_enabled(true)
	var beam := flashlight.get_node_or_null("FlashlightKit/ForwardBeam") as SpotLight3D
	var spill := flashlight.get_node_or_null("FlashlightKit/EnvironmentSpill") as OmniLight3D
	var fill := flashlight.get_node_or_null("FlashlightKit/AvatarFrontFill") as SpotLight3D
	if (
		beam == null
		or beam.light_cull_mask != 1
		or beam.shadow_caster_mask != 1
		or not beam.shadow_enabled
	):
		failures.append("Player forward beam is not an environment-only shadow light")
	if spill == null or spill.light_cull_mask != 1 or spill.shadow_enabled:
		failures.append("Player spill light can affect/self-shadow the avatar")
	if fill == null or fill.light_cull_mask != 2 or fill.shadow_enabled:
		failures.append("Player avatar fill is not an avatar-only no-shadow light")
	if (
		beam == null or beam.light_energy > 7.25
		or spill == null or spill.light_energy > 0.75
		or fill == null or fill.light_energy > 2.85
	):
		failures.append("Player flashlight exposure exceeds the accepted v0.1 energy budget")
	if (
		beam == null
		or beam.shadow_bias < 0.17
		or beam.shadow_normal_bias < 1.5
		or beam.shadow_blur < 1.1
	):
		failures.append("Player forward beam does not suppress far-wall shadow acne")
	if beam != null:
		for value in tower.player.find_children("*", "GeometryInstance3D", true, false):
			var geometry := value as GeometryInstance3D
			if (
				geometry.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				and (geometry.layers & beam.shadow_caster_mask) != 0
			):
				failures.append("Player presentation still enters the forward-beam shadow map: %s" % geometry.get_path())
	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	if facility == null or not is_instance_valid(facility):
		failures.append("Facility room is unavailable for room-light validation")
		return
	facility.set_stream_state(2)
	var room_lights := facility.get("_room_lights") as Array[WastelandLight3D]
	var shadow_room_light_found := false
	for light in room_lights:
		if light.failing:
			failures.append("Facility stable light is incorrectly configured as failing: %s" % light.name)
		if light.is_processing():
			failures.append("Facility stable light still runs brightness modulation: %s" % light.name)
		if (
			light != null
			and light.light_cull_mask == 3
			and light.cast_shadow
			and bool(light.get_snapshot().get("shadow_enabled", false))
			and int(light.get_snapshot().get("shadow_caster_mask", 0)) == 3
		):
			shadow_room_light_found = true
			break
	if not shadow_room_light_found:
		failures.append("Indoor lights cannot cast avatar shadows on render layer 2")
	var base_switch := facility.get_node_or_null("RoomLightSwitch3D") as RoomLightSwitch3D
	if base_switch == null:
		failures.append("Facility light switch is missing for relight validation")
		return
	if base_switch.is_light_on():
		base_switch.toggle_light()
	for light in room_lights:
		var lamp := light.get_node_or_null("LampLight") as OmniLight3D
		if lamp == null or not lamp.is_visible_in_tree() or lamp.light_energy > 0.001:
			failures.append("Facility light did not fully turn off: %s" % light.name)
	base_switch.toggle_light()
	await get_tree().process_frame
	await get_tree().create_timer(0.36).timeout
	for light in room_lights:
		var lamp := light.get_node_or_null("LampLight") as OmniLight3D
		if (
			lamp == null
			or not lamp.visible
			or not is_equal_approx(lamp.light_energy, light.energy)
			or lamp.omni_range < light.light_range * 0.99
			or light.is_processing()
			or (light.cast_shadow and not lamp.shadow_enabled)
		):
			failures.append(
				"Facility light did not restore stable floor illumination: %s (%.4f/%.4f)"
				% [light.name, lamp.light_energy if lamp != null else -1.0, light.energy]
			)
	var standard_beacon := facility.get_node_or_null("ExtractionBeacon3D") as ExtractionBeacon3D
	if standard_beacon != null:
		var beacon_snapshot := standard_beacon.get_snapshot()
		if (
			not bool(beacon_snapshot.get("idle_light_stable", false))
			or not is_equal_approx(float(beacon_snapshot.get("light_energy", 0.0)), 2.2)
		):
			failures.append("Facility idle extraction beacon still modulates floor illumination")


func _validate_floor_materials(failures: Array[String]) -> void:
	for path in [
		"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_override_top3d_v001.tres",
		"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_dark_top3d_v001.tres",
		"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_warm_a_v001.tres",
		"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_warm_b_v001.tres",
	]:
		var material := load(path) as StandardMaterial3D
		if material == null or material.metallic > 0.10 or material.roughness < 0.88:
			failures.append("Floor material remains too reflective: %s" % path)


func _validate_revealed_room_enemy_prewarm(
	failures: Array[String]
) -> void:
	# 使用独立塔楼实例，避免墙/门专项主动遍历房间后污染“首次开门”状态。
	var tower := TOWER_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	tower.force_open_edge_for_test("facility", "floor_01_entry")
	tower.force_enter_room_for_test("floor_01_entry")
	var hub := (tower.get("_room_by_id") as Dictionary).get(
		"floor_01_hub"
	) as DungeonRoom3D
	if hub == null:
		failures.append("98F hub is unavailable for reveal-time spawn validation")
		tower.queue_free()
		await get_tree().process_frame
		return
	var spawned_rooms := tower.get("_spawned_rooms") as Dictionary
	if spawned_rooms.has(hub.room_id):
		failures.append("98F hub spawned before its connecting door opened")
		tower.queue_free()
		await get_tree().process_frame
		return
	tower.force_open_edge_for_test("floor_01_entry", hub.room_id)
	await get_tree().process_frame
	var enemy_nodes := (tower.get("_enemy_nodes_by_room") as Dictionary).get(
		hub.room_id, []
	) as Array
	var alive := int((tower.get("_alive_by_room") as Dictionary).get(hub.room_id, 0))
	if not spawned_rooms.has(hub.room_id) or alive <= 0 or enemy_nodes.is_empty():
		failures.append("Opening the 98F hub door does not create its first enemy wave")
		tower.queue_free()
		await get_tree().process_frame
		return
	var instance_ids: Array[int] = []
	for value in enemy_nodes:
		var enemy := value as Enemy3D
		if enemy == null or not is_instance_valid(enemy):
			failures.append("Reveal-time enemy reference is invalid")
			continue
		instance_ids.append(enemy.get_instance_id())
		if enemy.process_mode == Node.PROCESS_MODE_DISABLED or enemy.is_runtime_ai_active():
			failures.append("Revealed-room enemy is not presentation-ready with paused AI")
	tower.force_enter_room_for_test(hub.room_id)
	await get_tree().process_frame
	var entered_nodes := (tower.get("_enemy_nodes_by_room") as Dictionary).get(
		hub.room_id, []
	) as Array
	if entered_nodes.size() != enemy_nodes.size():
		failures.append("Entering a revealed hostile room spawned a duplicate first wave")
	for value in entered_nodes:
		var enemy := value as Enemy3D
		if (
			enemy == null
			or enemy.get_instance_id() not in instance_ids
			or not enemy.is_runtime_ai_active()
		):
			failures.append(
				"Entering the revealed room did not activate the prewarmed enemy: "
				+ "id=%s retained=%s visible=%s process_mode=%s current=%s"
				% [
					enemy.get_instance_id() if enemy != null else -1,
					enemy != null and enemy.get_instance_id() in instance_ids,
					enemy.visible if enemy != null else false,
					enemy.process_mode if enemy != null else -1,
					str(tower.get("_current_room_id")),
				]
			)
			break
	tower.queue_free()
	await get_tree().process_frame


func _validate_wall_components(tower: TowerDescent3D, failures: Array[String]) -> void:
	var rooms := tower.get("_rooms") as Array[DungeonRoom3D]
	for room in rooms:
		if room == null or not is_instance_valid(room) or not room.tower_module_shell or room.size_class == "rooftop":
			continue
		room.set_stream_state(1)
		for value in room.find_children("*", "MeshInstance3D", true, false):
			var mesh := value as MeshInstance3D
			if not (
				mesh.name.begins_with("Imported_SolidWall5M_")
				or mesh.name in ["Wall_Long", "Wall_Short", "WallDoor_Left", "WallDoor_Right", "WallDoor_Lintel"]
			):
				continue
			var world_aabb := mesh.global_transform * mesh.get_aabb()
			var room_floor_y := room.global_position.y
			if world_aabb.position.y < room_floor_y - 0.02 or world_aabb.end.y > room_floor_y + 9.02:
				failures.append("Wall component exceeds the 0-9m floor envelope: %s" % mesh.get_path())
			elif world_aabb.size.y < 6.45 and "Lintel" not in mesh.name:
				failures.append("Wall component is not full-height: %s height=%.2f" % [mesh.get_path(), world_aabb.size.y])
			if not mesh.visible or mesh.transparency > 0.001:
				failures.append("Wall component is hidden or transparent: %s" % mesh.get_path())
			var wall_material := mesh.material_override as StandardMaterial3D
			if wall_material == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
				wall_material = mesh.get_active_material(0) as StandardMaterial3D
			if wall_material != null and (
				wall_material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
				or wall_material.albedo_color.a < 0.999
			):
				failures.append("Wall material is not fully opaque: %s" % mesh.get_path())
		for value in room.find_children("*", "StaticBody3D", true, false):
			var body := value as StaticBody3D
			var expectation := _camera_wall_expectation(body)
			if expectation == -1:
				continue
			var marked := bool(body.get_meta("camera_lower_wall", false))
			if expectation == 1 and not marked:
				failures.append("Horizontal shared wall is missing camera interaction: %s" % body.get_path())
			elif expectation == 0 and marked:
				failures.append("Non-horizontal wall has camera interaction enabled: %s" % body.get_path())
		for direction in ["north", "south"]:
			var horizontal_door := room.get_door_node(direction)
			var camera_door_proxies := room.find_children(
				"CameraOnlyDoorWall_%s_*" % direction.capitalize(),
				"StaticBody3D",
				true,
				false
			)
			if horizontal_door != null and camera_door_proxies.size() != 1:
				failures.append("Horizontal door wall is missing its camera-only opening proxy: %s/%s" % [room.room_id, direction])
			for proxy_value in camera_door_proxies:
				var proxy := proxy_value as StaticBody3D
				if (
					proxy.collision_layer != GameDesignConfig.COLLISION_LAYER_CAMERA_ONLY
					or proxy.collision_mask != 0
					or not bool(proxy.get_meta("camera_lower_wall", false))
				):
					failures.append("Door camera proxy can affect gameplay collision: %s" % proxy.get_path())


func _validate_hidden_connector_collisions(tower: TowerDescent3D, failures: Array[String]) -> void:
	for value in (tower.get("_corridor_by_edge") as Dictionary).values():
		var connector := value as Node3D
		if connector == null or connector.visible:
			continue
		for shape_value in connector.find_children("*", "CollisionShape3D", true, false):
			var shape := shape_value as CollisionShape3D
			if not shape.disabled:
				failures.append("Hidden connector retains a blocking collision: %s" % shape.get_path())
				return


func _validate_close_wall_probes(tower: TowerDescent3D, failures: Array[String]) -> void:
	for room in (tower.get("_rooms") as Array[DungeonRoom3D]):
		if room == null or not is_instance_valid(room) or not room.tower_module_shell or room.size_class == "rooftop":
			continue
		tower.force_enter_room_for_test(room.room_id)
		room.set_stream_state(1)
		var dimensions := room.get_dimensions()
		for direction in ["north", "south", "west", "east"]:
			var door := room.get_door_node(direction)
			if door != null:
				door.set_open(true, true)
		await get_tree().physics_frame
		var module_count := maxi(3, int(round(dimensions.x / TowerGeometry3D.GRID_UNIT_M)))
		for module_index in range(module_count):
			var probe_x := -dimensions.x * 0.5 + (float(module_index) + 0.5) * TowerGeometry3D.GRID_UNIT_M
			tower.player.global_position = room.global_position + Vector3(
				probe_x,
				0.05,
				dimensions.y * 0.5 - 0.50
			)
			tower.call("_update_camera_lower_wall_lift", 1.0)
			var snapshot := tower.get_tower_snapshot()
			var distance := float(snapshot.get("camera_lower_wall_distance_m", -1.0))
			if distance < 0.0 or distance > 0.60:
				failures.append("Open-door south wall probe missed in %s module %d: %.3fm" % [room.room_id, module_index, distance])
				break
			if bool(snapshot.get("camera_door_bypass_active", true)):
				failures.append("Open door globally bypasses camera walls in %s" % room.room_id)
				break
		for direction in ["north", "south", "west", "east"]:
			var door := room.get_door_node(direction)
			if door != null:
				door.set_open(false, true)


func _validate_stair_camera_walls(tower: TowerDescent3D, failures: Array[String]) -> void:
	for value in (tower.get("_corridor_by_edge") as Dictionary).values():
		var connector := value as Node3D
		if connector == null or not bool(connector.get_meta("is_vertical_connector", false)):
			continue
		var enclosure_count := 0
		var marked_enclosure_count := 0
		var south_z := -INF
		var marked_z := -INF
		for body_value in connector.find_children("*", "StaticBody3D", true, false):
			var body := body_value as StaticBody3D
			if body.name.begins_with("StairwellWall_"):
				failures.append("Legacy invisible stair enclosure box remains: %s" % body.get_path())
			if not bool(body.get_meta("stair_enclosure_collision", false)):
				continue
			enclosure_count += 1
			var visual := body.get_parent() as MeshInstance3D
			if visual == null or visual.mesh == null:
				failures.append("Stair enclosure collision has no matching visible mesh: %s" % body.get_path())
				continue
			var world_aabb := visual.global_transform * visual.get_aabb()
			if world_aabb.size.x > world_aabb.size.z:
				south_z = maxf(south_z, world_aabb.get_center().z)
				if bool(body.get_meta("camera_lower_wall", false)):
					marked_enclosure_count += 1
					marked_z = world_aabb.get_center().z
		if enclosure_count != 4:
			failures.append("Stairwell does not have four mesh-matched enclosure colliders: %s" % connector.name)
		if marked_enclosure_count != 1 or not is_equal_approx(marked_z, south_z):
			failures.append("Stairwell south visible wall is not the sole camera wall: %s" % connector.name)


func _validate_target_room_airwall_clearance(
	tower: TowerDescent3D,
	failures: Array[String]
) -> void:
	tower.force_open_edge_for_test("start", "facility")
	tower.force_enter_room_for_test("facility")
	await get_tree().physics_frame
	_validate_clear_lane(
		tower,
		Vector3(-14.0, -7.2, 2.5),
		Vector3(-14.0, -7.2, -9.4),
		"Base north lane still has an invisible blocker",
		failures
	)
	tower.force_open_edge_for_test("facility", "floor_01_entry")
	tower.force_enter_room_for_test("floor_01_entry")
	await get_tree().physics_frame
	_validate_clear_lane(
		tower,
		Vector3(34.0, -16.2, 2.5),
		Vector3(34.0, -16.2, 9.4),
		"Floor 98 safe-room south lane still has an invisible blocker",
		failures
	)


func _validate_clear_lane(
	tower: TowerDescent3D,
	from: Vector3,
	to: Vector3,
	failure: String,
	failures: Array[String]
) -> void:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.collide_with_areas = false
	if tower.player is CollisionObject3D:
		query.exclude = [(tower.player as CollisionObject3D).get_rid()]
	var hit := tower.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		failures.append("%s: %s" % [failure, (hit.get("collider") as Node).get_path()])


func _validate_internal_partition_camera_wall(
	tower: TowerDescent3D,
	failures: Array[String]
) -> void:
	var partition_room := DungeonRoom3D.new()
	partition_room.name = "InternalPartitionCameraFixture"
	partition_room.configure({
		"room_id": "camera_partition_fixture",
		"room_type": "COMBAT",
		"size_class": "floor",
		"seed": 1,
		"tower_module_shell": false,
	})
	partition_room.position = Vector3(400.0, 0.0, 400.0)
	tower.add_child(partition_room)
	partition_room.set_stream_state(1)
	await get_tree().process_frame
	await get_tree().physics_frame
	var marked_horizontal_bodies := 0
	for value in partition_room.find_children("PartitionHorizontalBody", "StaticBody3D", true, false):
		var body := value as StaticBody3D
		if bool(body.get_meta("camera_lower_wall", false)):
			marked_horizontal_bodies += 1
	if marked_horizontal_bodies != 2:
		failures.append("Interior horizontal partitions are not registered as camera walls")
	tower.player.global_position = partition_room.global_position + Vector3(-8.2, 0.05, 5.0)
	var distance := float(tower.call("_find_lower_camera_wall_distance"))
	if distance < 0.0:
		failures.append("Interior compartment south wall does not trigger the camera probe")
	partition_room.queue_free()
	await get_tree().process_frame


func _validate_hostile_room_spawning(tower: TowerDescent3D, failures: Array[String]) -> void:
	var representatives: Dictionary = {}
	for room in (tower.get("_rooms") as Array[DungeonRoom3D]):
		if room != null and is_instance_valid(room) and room.room_type in HOSTILE_TYPES and not representatives.has(room.room_type):
			representatives[room.room_type] = room
	for room_type in representatives:
		var room := representatives[room_type] as DungeonRoom3D
		if room == null or not is_instance_valid(room):
			failures.append("Hostile room representative was freed: %s" % room_type)
			continue
		room.set_stream_state(2)
		var spawned := true
		if not (tower.get("_spawned_rooms") as Dictionary).has(room.room_id):
			spawned = bool(tower.call("_prepare_revealed_hostile_room", room))
		var alive := int((tower.get("_alive_by_room") as Dictionary).get(room.room_id, 0))
		if not spawned or alive <= 0:
			failures.append("Hostile room type %s cannot spawn a first wave" % room_type)
	# 模拟旧版本残留：房间被记为访问过，但既没有活怪也没有待刷波次。
	var repair_room := representatives.get("COMBAT") as DungeonRoom3D
	if repair_room != null and is_instance_valid(repair_room):
		var repair_room_id := repair_room.room_id
		for value in (tower.get("_enemy_nodes_by_room") as Dictionary).get(repair_room_id, []):
			var enemy := value as Enemy3D
			if enemy != null:
				enemy.free()
		(tower.get("_enemy_nodes_by_room") as Dictionary)[repair_room_id] = []
		(tower.get("_room_wave_queues") as Dictionary)[repair_room_id] = []
		(tower.get("_alive_by_room") as Dictionary)[repair_room_id] = 7
		(tower.get("_spawned_rooms") as Dictionary)[repair_room_id] = true
		repair_room.cleared = false
		tower.call("_on_room_entered", repair_room)
		if int((tower.get("_alive_by_room") as Dictionary).get(repair_room_id, 0)) <= 0:
			failures.append("Visited hostile room with stale enemy state was not repaired")


func _ancestor_has_meta(node: Node, key: String, value: String) -> bool:
	var current := node
	while current != null:
		if str(current.get_meta(key, "")) == value:
			return true
		current = current.get_parent()
	return false


func _ancestor_meta(node: Node, key: String) -> String:
	var current := node
	while current != null:
		var value := str(current.get_meta(key, ""))
		if not value.is_empty():
			return value
		current = current.get_parent()
	return ""


func _camera_wall_expectation(body: StaticBody3D) -> int:
	if bool(body.get_meta("camera_only_door_wall", false)):
		return 1
	if body is RoomDoor3D:
		return 1 if (body as RoomDoor3D).direction in ["north", "south"] else 0
	var direction := _ancestor_meta(body, "tower_wall_direction")
	if not direction.is_empty():
		return 1 if direction in ["north", "south"] else 0
	var corner := _ancestor_meta(body, "tower_wall_corner")
	if not corner.is_empty():
		return 1 if (
			(corner == "SW" and body.name == "WallCollisionLong")
			or (corner == "SE" and body.name == "WallCollisionShort")
			or (corner == "NW" and body.name == "WallCollisionShort")
			or (corner == "NE" and body.name == "WallCollisionLong")
		) else 0
	if str(body.name).begins_with("TowerWallCollision_"):
		return 1 if ("North" in str(body.name) or "South" in str(body.name)) else 0
	return -1
