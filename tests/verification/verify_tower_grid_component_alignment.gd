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
	for connector_value in (tower.get("_corridor_by_edge") as Dictionary).values():
		var connector := connector_value as Node3D
		if connector == null or bool(connector.get_meta("is_vertical_connector", false)):
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
	if horizontal_count != 42:
		failures.append("expected 42 horizontal component corridors, got %d" % horizontal_count)

	_validate_key_door(room_by_id, "facility", "west", Vector3(-15.0, -9.0, 2.5), failures)
	_validate_key_door(room_by_id, "facility", "east", Vector3(15.0, -9.0, 2.5), failures)
	_validate_key_door(room_by_id, "floor_01_entry", "east", Vector3(35.0, -18.0, 2.5), failures)
	_validate_key_door(room_by_id, "floor_01_entry", "north", Vector3(27.5, -18.0, -5.0), failures)
	_validate_key_door(room_by_id, "floor_01_hub", "south", Vector3(27.5, -18.0, -10.0), failures)

	var floor_stages := tower.get_tower_snapshot().get("floor_stages", []) as Array
	var expected_holes := [1, 1, 1, 1, 1, 0]
	for stage_value in floor_stages:
		var stage := stage_value as Dictionary
		var index := int(stage.get("floor_index", -1))
		if index < 0 or index >= expected_holes.size():
			continue
		var hole_count := (stage.get("stair_hole_sides", []) as Array).size()
		if hole_count != expected_holes[index]:
			failures.append("floor stage %d has %d stair holes; expected %d upper-floor holes" % [index, hole_count, expected_holes[index]])
		var expected_tiles := 2500 - hole_count * 18
		if int(stage.get("tile_count", -1)) != expected_tiles:
			failures.append("floor stage %d tile coverage is incomplete" % index)

	_validate_player_light_shadow_separation(tower.player, failures)
	_finish(failures)


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
		and str(root.get_meta("asset_id", "")) == "ENV-TOWER-WALL-DOOR-5M"
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
