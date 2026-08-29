extends Node
## 塔楼关卡组件坐标验收：房间边界、门墙、交互门、走廊和楼板洞共用 5m 网格。


func _ready() -> void:
	var failures: Array[String] = []
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	if not tower.generate_through_floor_for_test(95):
		failures.append("98—95结构验收准备失败")

	var generation := tower.get_generation_snapshot()
	var room_by_id := tower.get("_room_by_id") as Dictionary
	for record_value in generation.get("records", []):
		var record := record_value as Dictionary
		var id := str(record.get("id", ""))
		var position := record.get("position", Vector3.ZERO) as Vector3
		var dimensions := record.get("custom_dimensions", Vector2.ZERO) as Vector2
		if bool(record.get("grid_position_adjusted", false)):
			failures.append("%s authored position required runtime grid correction" % id)
		if not TowerGeometry3D.is_component_axis_aligned(position.x, dimensions.x):
			failures.append("%s X boundary is not on the 5m grid" % id)
		if not TowerGeometry3D.is_component_axis_aligned(position.z, dimensions.y):
			failures.append("%s Z boundary is not on the 5m grid" % id)
		var room := room_by_id.get(id) as DungeonRoom3D
		if room == null:
			failures.append("%s room instance is missing" % id)
			continue
		room.set_stream_state(1)
		for side in room.doors:
			_validate_room_door(room, side, failures)

	var horizontal_count := 0
	var vertical_count := 0
	var entry_hub_dynamic_corridor_verified := false
	for connector_value in (tower.get("_corridor_by_edge") as Dictionary).values():
		var connector := connector_value as Node3D
		if connector == null:
			continue
		if bool(connector.get_meta("is_vertical_connector", false)):
			vertical_count += 1
			_validate_stair_approach_wall_modules(connector, failures)
			continue
		horizontal_count += 1
		var tangent_error := float(connector.get_meta("door_tangent_error_m", INF))
		var start := connector.get_meta("start_door_position", Vector3.INF) as Vector3
		var end := connector.get_meta("end_door_position", Vector3.INF) as Vector3
		if tangent_error > 0.01:
			failures.append("%s horizontal door lanes differ by %.3fm" % [connector.name, tangent_error])
		var length := start.distance_to(end)
		if not is_equal_approx(length, snappedf(length, TowerGeometry3D.GRID_UNIT_M)):
			failures.append("%s corridor length %.3fm is not a 5m component multiple" % [connector.name, length])
		_validate_horizontal_corridor_modules(connector, start, end, failures)
		var endpoint_ids := [
			str(connector.get_meta("from_room_id", "")),
			str(connector.get_meta("to_room_id", "")),
		]
		if "floor_01_entry" in endpoint_ids and "floor_01_hub" in endpoint_ids:
			entry_hub_dynamic_corridor_verified = (
				is_equal_approx(length, 25.0)
				and int(connector.get_meta("floor_module_count", -1)) == 5
				and int(connector.get_meta("wall_module_count", -1)) == 10
			)
	if horizontal_count != 62:
		failures.append("expected 62 generated horizontal component corridors including Boss exit and airlock, got %d" % horizontal_count)
	if not entry_hub_dynamic_corridor_verified:
		failures.append("98F safe-room north corridor is not a complete 25m/5-module passage")
	if vertical_count <= 0:
		failures.append("tower generated no vertical connector for stair approach wall validation")

	_validate_key_door(room_by_id, "facility", "west", Vector3(-15.0, -9.0, 2.5), failures)
	_validate_key_door(room_by_id, "facility", "east", Vector3(15.0, -9.0, 2.5), failures)
	_validate_key_door(room_by_id, "floor_01_entry", "east", Vector3(35.0, -18.0, 2.5), failures)
	var entry98 := room_by_id.get("floor_01_entry") as DungeonRoom3D
	var hub98 := room_by_id.get("floor_01_hub") as DungeonRoom3D
	var hub_is_north := hub98.position.z < entry98.position.z
	var entry_hub_side := "north" if hub_is_north else "south"
	var hub_entry_side := "south" if hub_is_north else "north"
	var z_sign := -1.0 if hub_is_north else 1.0
	_validate_key_door(
		room_by_id,
		"floor_01_entry",
		entry_hub_side,
		Vector3(entry98.position.x, -18.0, entry98.position.z + z_sign * 7.5),
		failures
	)
	_validate_key_door(
		room_by_id,
		"floor_01_hub",
		hub_entry_side,
		Vector3(
			entry98.position.x,
			-18.0,
			hub98.position.z - z_sign * hub98.get_dimensions().y * 0.5
		),
		failures
	)

	var floor_stages := tower.get_tower_snapshot().get("floor_stages", []) as Array
	var expected_holes := [1, 1, 1, 1, 1, 1, 0]
	for stage_value in floor_stages:
		var stage := stage_value as Dictionary
		var index := int(stage.get("floor_index", -1))
		if index < 0 or index >= expected_holes.size():
			continue
		var hole_count := (stage.get("stair_hole_sides", []) as Array).size()
		if hole_count != expected_holes[index]:
			failures.append("floor stage %d has %d stair holes; expected %d upper-floor holes" % [index, hole_count, expected_holes[index]])
		var expected_tiles := 2500 - hole_count * 18
		if index == 0:
			expected_tiles = 18 * 16 - 18 - 36
			if (
				not bool(stage.get("base_99_100_atrium_enabled", false))
				or int(stage.get("base_99_100_atrium_tile_count", 0)) != 36
			):
				failures.append("100层缺少基地99/100层6×6贯通中庭")
		elif index == 1:
			# 99F通用可视地砖会避开基地正式地板，承重面仍完整保留。
			expected_tiles -= 36
		if int(stage.get("tile_count", -1)) != expected_tiles:
			failures.append("floor stage %d tile coverage is incomplete" % index)

	_validate_player_light_shadow_separation(tower.player, failures)
	_finish(failures)


func _validate_stair_approach_wall_modules(
	connector: Node3D,
	failures: Array[String]
) -> void:
	var visual_count := 0
	var collision_count := 0
	for node_value in connector.find_children("*", "Node3D", true, false):
		var node := node_value as Node3D
		if node == null:
			continue
		if (
			str(node.get_meta("asset_id", "")) == "ENV-TOWER-WALL-SOLID-5M"
			and bool(node.get_meta("stair_approach_corridor", false))
		):
			visual_count += 1
			if (
				not bool(node.get_meta("uses_native_wall_visual_height", false))
				or str(node.get_meta("source_visual_version", "")) != "v002"
			):
				failures.append("%s stair approach wall does not use native v002 height" % node.name)
			var mesh_instance := _find_first_mesh_instance(node)
			if mesh_instance == null or mesh_instance.mesh == null:
				failures.append("%s stair approach wall has no visual mesh" % node.name)
				continue
			var world_bounds := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
			if not is_equal_approx(world_bounds.size.y, TowerGeometry3D.WALL_VISUAL_HEIGHT_M):
				failures.append("%s stair approach visual is not 8.9m high" % node.name)
			if not is_equal_approx(world_bounds.position.y, node.global_position.y):
				failures.append("%s stair approach visual bottom left the floor datum" % node.name)
			if (
				int(connector.get_meta("upper_floor_index", -1)) == 0
				and int(connector.get_meta("lower_floor_index", -1)) == 1
				and "Lower" in node.name
				and not is_equal_approx(world_bounds.end.y, -0.1)
			):
				failures.append("%s still shares Y=0 with the 100F floor" % node.name)
		if node is StaticBody3D and node.name.begins_with("StairApproachWall_"):
			var body := node as StaticBody3D
			if body.get_child_count() <= 0:
				continue
			var collision := body.get_child(0) as CollisionShape3D
			var shape := collision.shape as BoxShape3D if collision != null else null
			if shape != null:
				collision_count += 1
				if not is_equal_approx(shape.size.y, TowerGeometry3D.WALL_LOGICAL_HEIGHT_M):
					failures.append("%s stair approach collision is not 9m high" % node.name)
	if visual_count > 0 and collision_count <= 0:
		failures.append("%s stair approach lost its continuous 9m side-wall colliders" % connector.name)


func _find_first_mesh_instance(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		return root as MeshInstance3D
	for child in root.get_children():
		var found := _find_first_mesh_instance(child)
		if found != null:
			return found
	return null


func _validate_horizontal_corridor_modules(
	connector: Node3D,
	start: Vector3,
	end: Vector3,
	failures: Array[String]
) -> void:
	var length := start.distance_to(end)
	if length <= 0.05:
		if (
			int(connector.get_meta("module_count", -1)) != 0
			or int(connector.get_meta("floor_module_count", -1)) != 0
			or int(connector.get_meta("wall_module_count", -1)) != 0
		):
			failures.append("%s shared-wall connector created zero-length collision modules" % connector.name)
		return
	var expected_modules := maxi(
		1,
		int(round(length / TowerGeometry3D.GRID_UNIT_M))
	)
	var floor_batch: MultiMeshInstance3D = null
	var wall_batch: MultiMeshInstance3D = null
	var collision_bodies: Array[StaticBody3D] = []
	for child_value in connector.get_children():
		var child := child_value as Node3D
		if child == null:
			continue
		if child is MultiMeshInstance3D and bool(child.get_meta("horizontal_corridor_module_batch", false)):
			match str(child.get_meta("asset_id", "")):
				"ENV-TOWER-FLOOR-TILE-5M":
					floor_batch = child as MultiMeshInstance3D
				"ENV-TOWER-WALL-SOLID-5M":
					wall_batch = child as MultiMeshInstance3D
		if child is StaticBody3D and child.name.begins_with("CorridorWallCollision_"):
			collision_bodies.append(child as StaticBody3D)
	var floor_instance_count := (
		floor_batch.multimesh.instance_count
		if floor_batch != null and floor_batch.multimesh != null
		else -1
	)
	var wall_instance_count := (
		wall_batch.multimesh.instance_count
		if wall_batch != null and wall_batch.multimesh != null
		else -1
	)
	if (
		int(connector.get_meta("module_count", -1)) != expected_modules
		or int(connector.get_meta("floor_module_count", -1)) != expected_modules
		or int(connector.get_meta("wall_module_count", -1)) != expected_modules * 2
		or floor_instance_count != expected_modules
		or wall_instance_count != expected_modules * 2
		or not is_equal_approx(
			float(connector.get_meta("module_coverage_length_m", -1.0)),
			length
		)
	):
		failures.append(
			"%s %.1fm corridor visual coverage is not %d floors + %d walls" % [
				connector.name,
				length,
				expected_modules,
				expected_modules * 2,
			]
		)
	var along_x := absf(end.x - start.x) >= absf(end.z - start.z)
	var floor_origins := (
		floor_batch.get_meta("corridor_module_origins", PackedVector3Array())
		if floor_batch != null
		else PackedVector3Array()
	) as PackedVector3Array
	var wall_origins := (
		wall_batch.get_meta("corridor_module_origins", PackedVector3Array())
		if wall_batch != null
		else PackedVector3Array()
	) as PackedVector3Array
	if floor_origins.size() != expected_modules or wall_origins.size() != expected_modules * 2:
		failures.append("%s does not retain its generated module coordinates" % connector.name)
	for origin in floor_origins:
		if (
			not TowerGeometry3D.is_component_axis_aligned(origin.x, 5.0)
			or not TowerGeometry3D.is_component_axis_aligned(origin.z, 5.0)
		):
			failures.append("%s floor module is off the 5m grid: %s" % [connector.name, origin])
	for origin in wall_origins:
		var along_position := origin.x if along_x else origin.z
		if not TowerGeometry3D.is_component_axis_aligned(along_position, 5.0):
			failures.append("%s wall module is off the 5m lane: %s" % [connector.name, origin])
		var wall_aabb := (
			wall_batch.multimesh.mesh.get_aabb()
			if wall_batch != null
			and wall_batch.multimesh != null
			and wall_batch.multimesh.mesh != null
			else AABB()
		)
		var wall_visual_scale_y := (
			wall_batch.multimesh.get_instance_transform(0).basis.y.length()
			if wall_batch != null
			and wall_batch.multimesh != null
			and wall_batch.multimesh.instance_count > 0
			else 1.0
		)
		var wall_bottom_y := origin.y + wall_aabb.position.y * wall_visual_scale_y
		if not is_equal_approx(wall_bottom_y, start.y):
			failures.append(
				"%s wall module floats %.3fm above its floor" % [
					connector.name,
					wall_bottom_y - start.y,
				]
			)
		if not is_equal_approx(
			wall_aabb.size.y * wall_visual_scale_y,
			TowerGeometry3D.WALL_VISUAL_HEIGHT_M
		):
			failures.append("%s wall visual module is not 8.9m high" % connector.name)
	if collision_bodies.size() != 2:
		failures.append("%s must keep exactly two continuous side-wall colliders" % connector.name)
	for body in collision_bodies:
		var collision := body.get_child(0) as CollisionShape3D if body.get_child_count() > 0 else null
		var shape := collision.shape as BoxShape3D if collision != null else null
		var collision_length := (
			shape.size.x if shape != null and along_x
			else shape.size.z if shape != null
			else -1.0
		)
		if not is_equal_approx(collision_length, length):
			failures.append("%s visible modules and collision length differ" % connector.name)


func _validate_room_door(room: DungeonRoom3D, side: String, failures: Array[String]) -> void:
	var door := room.get_door_node(side)
	if door == null:
		failures.append("%s %s interaction door is missing" % [room.room_id, side])
		return
	var module := _find_door_wall_module(room, side)
	if module == null:
		failures.append("%s %s 5m door-wall component is missing" % [room.room_id, side])
		return
	if door.global_position.distance_to(module.global_position) > 0.01:
		failures.append("%s %s interaction door and mesh component differ by %.3fm" % [room.room_id, side, door.global_position.distance_to(module.global_position)])
	var perpendicular := door.global_position.z if side in ["north", "south"] else door.global_position.x
	var along := door.global_position.x if side in ["north", "south"] else door.global_position.z
	if not is_equal_approx(perpendicular, snappedf(perpendicular, TowerGeometry3D.GRID_UNIT_M)):
		failures.append("%s %s wall boundary is not on a 5m grid line" % [room.room_id, side])
	if not is_equal_approx(along, snappedf(along - 2.5, TowerGeometry3D.GRID_UNIT_M) + 2.5):
		failures.append("%s %s door center is not on a 5m tile center" % [room.room_id, side])


func _find_door_wall_module(root: Node, side: String) -> Node3D:
	if (
		root is Node3D
		and str(root.get_meta("asset_id", "")) in [
			"ENV-TOWER-WALL-DOOR-5M",
			"ENV-BASE99-WALL-DOOR-5X9",
		]
		and str(root.get_meta("tower_wall_direction", "")) == side
	):
		return root as Node3D
	for child in root.get_children():
		var found := _find_door_wall_module(child, side)
		if found != null:
			return found
	return null


func _validate_key_door(
	room_by_id: Dictionary,
	room_id: String,
	side: String,
	expected: Vector3,
	failures: Array[String]
) -> void:
	var room := room_by_id.get(room_id) as DungeonRoom3D
	var door := room.get_door_node(side) if room != null else null
	if door == null or door.global_position.distance_to(expected) > 0.01:
		failures.append("%s %s key door is at %s, expected %s" % [room_id, side, door.global_position if door != null else Vector3.INF, expected])


func _validate_player_light_shadow_separation(player: Player3D, failures: Array[String]) -> void:
	var caster_count := 0
	for mesh_value in player.avatar.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_value as MeshInstance3D
		if mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			caster_count += 1
	if player.weapon != null:
		for mesh_value in player.weapon.find_children("*", "MeshInstance3D", true, false):
			var mesh := mesh_value as MeshInstance3D
			if mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
				caster_count += 1
	if caster_count <= 0:
		failures.append("player/avatar/held weapon cannot cast shadows from sun or room lights")
	var flashlight := player.get_node_or_null("PlayerFlashlight3D") as PlayerFlashlight3D
	if flashlight == null:
		failures.append("player flashlight rig is missing")
		return
	var snapshot := flashlight.get_snapshot()
	if (
		int(snapshot.get("environment_light_cull_mask", 0)) != 1
		or int(snapshot.get("environment_shadow_caster_mask", 0)) != 1
		or int(snapshot.get("avatar_light_cull_mask", 0)) != 2
		or int(snapshot.get("shadow_light_count", 0)) != 1
		or not bool(snapshot.get("shadow_light_disabled_for_avatar", false))
	):
		failures.append("player-mounted three-light rig can still self-shadow the avatar")
	var beam := flashlight.get_node_or_null("FlashlightKit/ForwardBeam") as SpotLight3D
	if beam == null or beam.shadow_caster_mask != 1:
		failures.append("forward beam shadow map still includes the player render layer")


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("TOWER_GRID_COMPONENT_ALIGNMENT_OK: 5m bounds, real door meshes, corridors, floor coverage and per-light avatar shadow separation pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
