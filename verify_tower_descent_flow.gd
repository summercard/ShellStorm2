extends Node


func _ready() -> void:
	var failures: Array[String] = []
	var main_scene_path := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene_path != "res://scenes/TowerDescent3D.tscn":
		failures.append("Project entry is not TowerDescent3D")

	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		failures.append("TowerDescent3D scene does not load")
		_finish(failures, 0)
		return
	var tower := scene.instantiate() as TowerDescent3D
	if tower == null:
		failures.append("TowerDescent3D root contract is missing")
		_finish(failures, 0)
		return
	tower.test_mode = true
	tower.run_seed_override = 4242
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	var generation := tower.get_generation_snapshot()
	var tower_snapshot := tower.get_tower_snapshot()
	if str(tower_snapshot.get("mode", "")) != "tower_descent":
		failures.append("Tower mode snapshot is missing")
	if int(tower_snapshot.get("combat_floor_count", 0)) != 5:
		failures.append("Tower must generate exactly five combat floors")
	if tower_snapshot.get("rooftop_dimensions", Vector2.ZERO) != Vector2(50.0, 50.0):
		failures.append("Rooftop is not 50x50m")
	if tower_snapshot.get("facility_dimensions", Vector2.ZERO) != Vector2(30.0, 30.0):
		failures.append("Facility floor is not 30x30m")
	for floor_record in tower_snapshot.get("combat_floors", []):
		if floor_record.get("dimensions", Vector2.ZERO) != Vector2(30.0, 30.0):
			failures.append("Combat floor %s is not 30x30m" % floor_record.get("id", "unknown"))
	if int(tower_snapshot.get("facility_count", 0)) != 7:
		failures.append("Facility floor does not expose seven existing base functions")
	if int(tower_snapshot.get("vertical_connector_count", 0)) != 6:
		failures.append("Roof/facility/five floors are not joined by six stairwells")
	var descent_sides: Array = tower_snapshot.get("descent_sides", [])
	if descent_sides.size() != 6 or str(descent_sides[0]) != "west":
		failures.append("First rooftop stair is not on the left/west edge")
	var heights: Array = tower_snapshot.get("floor_heights", [])
	if heights.size() != 7:
		failures.append("Tower does not expose seven physical height levels")
	else:
		for index in range(1, heights.size()):
			if not is_equal_approx(float(heights[index - 1]) - float(heights[index]), 6.0):
				failures.append("Tower floor height step is not 6m at index %d" % index)
	var stair_geometry := tower_snapshot.get("stair_geometry_m", {}) as Dictionary
	if (
		not is_equal_approx(float(stair_geometry.get("door_clear_width", 0.0)), 4.0)
		or not is_equal_approx(float(stair_geometry.get("passage_width", 0.0)), 4.0)
		or not is_equal_approx(float(stair_geometry.get("approach_outset", 0.0)), 3.0)
		or not is_equal_approx(float(stair_geometry.get("run_length", 0.0)), 10.0)
		or not is_equal_approx(float(stair_geometry.get("lane_center_spacing", 0.0)), 5.2)
		or not is_equal_approx(float(stair_geometry.get("floor_thickness", 0.0)), 0.24)
	):
		failures.append("Tower stair meter-unit contract is incomplete or inconsistent")

	var rooftop := tower.get("_room_by_id").get("start") as DungeonRoom3D
	if rooftop == null or _count_named_nodes(rooftop, "RooftopRail") < 12:
		failures.append("Rooftop perimeter railing is missing or incomplete")
	if rooftop == null or _count_named_nodes(rooftop, "RooftopExteriorWall") < 4:
		failures.append("Rooftop has no readable full-height exterior facade")
	if rooftop == null or not bool(rooftop.get_room_snapshot().get("support_collision_persistent", false)):
		failures.append("Active rooftop has no support collision")

	if not tower.try_open_room_door("facility"):
		failures.append("Cleared rooftop cannot open the first descent door")
	await get_tree().process_frame
	if not bool(tower.get("_door_fate_active")):
		failures.append("Opening a stairwell door does not trigger fate-card choice")
	tower.resolve_fate_choice_for_test(0)
	await get_tree().process_frame
	await get_tree().physics_frame
	if bool(tower.get("_door_fate_active")):
		failures.append("Door fate-card choice cannot be resolved")
	var first_connector: Node3D = null
	var connector_values: Array = (tower.get("_corridor_by_edge") as Dictionary).values()
	for connector_value in connector_values:
		var connector := connector_value as Node3D
		if connector == null:
			failures.append("Tower contains an invalid stairwell connector")
			continue
		var connector_points: Array = connector.get_meta("path_points", [])
		if connector_points.size() != 7:
			failures.append("%s is not the standard seven-node stair module" % connector.name)
			continue
		if (
			not is_equal_approx(float(connector.get_meta("passage_width", 0.0)), 4.0)
			or not is_equal_approx(float(connector.get_meta("approach_outset", 0.0)), 3.0)
			or not is_equal_approx(float(connector.get_meta("lane_spacing", 0.0)), 5.2)
			or not is_equal_approx(float(connector.get_meta("guard_end_clearance", 0.0)), 2.4)
		):
			failures.append("%s does not follow the shared meter-unit contract" % connector.name)
		if not is_equal_approx(
			(connector_points[0] as Vector3).distance_to(connector_points[1] as Vector3),
			3.0
		):
			failures.append("%s upper corridor does not meet the stair at a 3m approach" % connector.name)
		if not is_equal_approx(
			Vector2(
				(connector_points[1] as Vector3).x - (connector_points[2] as Vector3).x,
				(connector_points[1] as Vector3).z - (connector_points[2] as Vector3).z
			).length(),
			10.0
		):
			failures.append("%s first stair run is not the shared 10m displacement" % connector.name)
		if not is_equal_approx(
			(connector_points[2] as Vector3).distance_to(connector_points[3] as Vector3),
			5.2
		):
			failures.append("%s turn landing does not use the 5.2m lane spacing" % connector.name)
		if not is_equal_approx(
			(connector_points[4] as Vector3).distance_to(connector_points[5] as Vector3),
			5.2
		):
			failures.append("%s lower landing does not return exactly 5.2m" % connector.name)
		if not is_equal_approx(
			(connector_points[5] as Vector3).distance_to(connector_points[6] as Vector3),
			3.0
		):
			failures.append("%s lower corridor does not meet the door at a 3m approach" % connector.name)
		if str(connector.get_meta("from_room_id", "")) == "start":
			first_connector = connector
	if first_connector == null:
		failures.append("First physical stairwell connector is missing")
	else:
		var path_points: Array = first_connector.get_meta("path_points", [])
		if path_points.size() < 7:
			failures.append("First stairwell has no traversable switchback path")
		else:
			if float(first_connector.get_meta("lane_spacing", 0.0)) <= 3.8:
				failures.append("Switchback stair lanes overlap the 3.8m traversal width")
			if not is_equal_approx(float(first_connector.get_meta("passage_width", 0.0)), 4.0):
				failures.append("Door, corridor and stair do not share the 4.0m passage-width contract")
			if not is_equal_approx(float(first_connector.get_meta("approach_outset", 0.0)), 3.0):
				failures.append("Stair doorway does not use the 3.0m approach-platform offset")
			if float(first_connector.get_meta("guard_end_clearance", 0.0)) < 2.4:
				failures.append("Stair guards do not leave a full turning opening at both ends")
			if float(first_connector.get_meta("guard_height", 99.0)) > 1.05:
				failures.append("Stair guards are tall enough to obscure the player")
			var upper_door_point := path_points[0] as Vector3
			var lower_door_point := path_points[path_points.size() - 1] as Vector3
			if upper_door_point.distance_to(Vector3(-25.0, 0.0, 0.0)) > 0.05:
				failures.append("Rooftop down stair is not aligned to the west door axis")
			if lower_door_point.distance_to(Vector3(-15.0, -6.0, 0.0)) > 0.05:
				failures.append("Facility up stair is not aligned to the same west door axis")
			var entry_floor := first_connector.get_node_or_null("StairFloor_00Body") as StaticBody3D
			var entry_collision := _find_collision_shape(entry_floor)
			if entry_floor == null or entry_collision == null or not (entry_collision.shape is BoxShape3D):
				failures.append("Stair entry floor has no measurable collision surface")
			else:
				var entry_shape := entry_collision.shape as BoxShape3D
				var entry_top_y := entry_floor.position.y + entry_shape.size.y * 0.5
				if absf(entry_top_y - upper_door_point.y) > 0.01:
					failures.append("Corridor top surface is not flush with the rooftop floor")
			var sloped_segment_indices: Array[int] = []
			for point_index in range(path_points.size() - 1):
				if absf((path_points[point_index + 1] as Vector3).y - (path_points[point_index] as Vector3).y) > 0.05:
					sloped_segment_indices.append(point_index)
			if sloped_segment_indices.size() != 2:
				failures.append("Switchback stair does not expose exactly two separated sloped runs")
				sloped_segment_indices = [1, 3]
			var ramp_index := sloped_segment_indices[0]
			var ramp_start := path_points[ramp_index] as Vector3
			var ramp_end := path_points[ramp_index + 1] as Vector3
			var travel_direction := ramp_end - ramp_start
			travel_direction.y = 0.0
			travel_direction = travel_direction.normalized()
			tower.player.global_position = ramp_start + travel_direction * 0.35 + Vector3.UP * 0.05
			tower.player.set_test_move_direction(travel_direction)
			for _frame in range(95):
				await get_tree().physics_frame
			tower.player.set_test_move_direction(Vector3.ZERO)
			if tower.player.global_position.y > ramp_start.y - 1.8:
				failures.append("Player3D does not physically descend the stair slope (start=%.2f end=%.2f)" % [
					ramp_start.y,
					tower.player.global_position.y,
				])
			var lower_ramp_index := sloped_segment_indices[1]
			var lower_ramp_start := path_points[lower_ramp_index] as Vector3
			var lower_ramp_end := path_points[lower_ramp_index + 1] as Vector3
			tower.player.global_position = lower_ramp_start.lerp(lower_ramp_end, 0.62) + Vector3.UP * 0.05
			await get_tree().physics_frame
			await get_tree().process_frame
			if rooftop.visible:
				failures.append("Upper rooftop is not cut away while the player is below it in the stairwell")
			if _count_hidden_cutaway_meshes(first_connector) < 1:
				failures.append("Higher stair run still visually occludes the player on the lower run")
			var lower_travel_direction := lower_ramp_end - lower_ramp_start
			lower_travel_direction.y = 0.0
			lower_travel_direction = lower_travel_direction.normalized()
			tower.player.global_position = lower_ramp_start + lower_travel_direction * 0.35 + Vector3.UP * 0.05
			tower.player.set_test_move_direction(lower_travel_direction)
			for _frame in range(150):
				await get_tree().physics_frame
			tower.player.set_test_move_direction(Vector3.ZERO)
			if tower.player.global_position.y > lower_ramp_start.y - 1.8:
				failures.append("Player3D is blocked on the lower stair run (start=%.2f end=%.2f)" % [
					lower_ramp_start.y,
					tower.player.global_position.y,
				])
			var outward := first_connector.get_meta("outward", Vector3(-1, 0, 0)) as Vector3
			var tangent := Vector3(-outward.z, 0.0, outward.x)
			tower.player.global_position = upper_door_point - outward * 4.0 + Vector3.UP * 0.05
			await get_tree().physics_frame
			var traversal_ok := true
			for waypoint_index in range(path_points.size()):
				if not await _walk_player_to(tower.player, path_points[waypoint_index] as Vector3):
					failures.append("Player is blocked between rooftop door and stair waypoint %d" % waypoint_index)
					traversal_ok = false
					break
			if traversal_ok:
				var lower_inside := lower_door_point - outward * 5.5 + tangent * 5.0
				if not await _walk_player_to(tower.player, lower_inside):
					failures.append("Player crosses the stairs but cannot enter the lower-floor corridor")
				elif str(tower.get_tower_snapshot().get("current_room_id", "")) != "facility":
					failures.append("Door-to-door traversal does not enter the facility floor")

	var facility_floor := tower.get("_room_by_id").get("facility") as DungeonRoom3D
	tower.player.global_position = facility_floor.global_position + Vector3(0, 0.05, 0)
	tower.force_enter_room_for_test("facility")
	await get_tree().process_frame
	await get_tree().process_frame
	if rooftop.visible:
		failures.append("Upper rooftop remains rendered after descending to facility floor")
	if not bool(rooftop.get_room_snapshot().get("support_collision_persistent", false)):
		failures.append("Hidden rooftop lost its load-bearing floor collision")
	var facility_enemies := get_tree().get_nodes_in_group("enemy_3d").filter(
		func(node): return tower.is_ancestor_of(node) and (node as Enemy3D).room_id == "facility"
	)
	if not facility_enemies.is_empty():
		failures.append("Facility floor spawned enemies")
	if bool(tower.player.combat_enabled):
		failures.append("Facility safe floor still allows shooting")

	var base_console := facility_floor.get_node_or_null("BaseConsole") as BaseFacility3D
	if base_console == null:
		failures.append("Facility floor is missing base management terminal")
	else:
		tower.call("_on_facility_activated", base_console)
		await get_tree().process_frame
		if tower.get_active_facility_menu() == null or not tower.player.input_locked:
			failures.append("Facility overlay does not open or lock player input")
		elif not tower.try_close_modal_for_pause():
			failures.append("Facility overlay cannot close before pause")
		await get_tree().process_frame
		if tower.get_active_facility_menu() != null or tower.player.input_locked:
			failures.append("Closing facility overlay leaves modal/input state behind")

	tower.force_open_edge_for_test("facility", "floor_01")
	var floor_one := tower.get("_room_by_id").get("floor_01") as DungeonRoom3D
	tower.player.global_position = floor_one.global_position + Vector3(0, 0.05, 0)
	tower.force_enter_room_for_test("floor_01")
	await get_tree().process_frame
	await get_tree().physics_frame
	if facility_floor.visible:
		failures.append("Upper facility floor remains rendered on combat floor 1")
	if not bool(facility_floor.get_room_snapshot().get("support_collision_persistent", false)):
		failures.append("Hidden facility floor lost support collision")
	var floor_one_enemies := get_tree().get_nodes_in_group("enemy_3d").filter(
		func(node): return tower.is_ancestor_of(node) and (node as Enemy3D).room_id == "floor_01"
	)
	if floor_one_enemies.is_empty():
		failures.append("Combat floor 1 does not spawn monsters")
	for enemy_value in floor_one_enemies:
		var enemy := enemy_value as Enemy3D
		if absf(enemy.global_position.y - floor_one.global_position.y) > 0.2:
			failures.append("Combat-floor enemy uses the wrong global Y coordinate")
			break
	var has_closed_blocking_door := false
	for door_snapshot in floor_one.get_room_snapshot().get("door_snapshots", []):
		if not bool(door_snapshot.get("is_open", true)) and bool(door_snapshot.get("blocks_passage", false)):
			has_closed_blocking_door = true
	if not has_closed_blocking_door:
		failures.append("Unopened down-stair door does not block passage/vision")

	var ordered_ids := ["floor_02", "floor_03", "floor_04", "extraction"]
	var previous_id := "floor_01"
	for room_id in ordered_ids:
		tower.force_open_edge_for_test(previous_id, room_id)
		var room := tower.get("_room_by_id").get(room_id) as DungeonRoom3D
		tower.player.global_position = room.global_position + Vector3(0, 0.05, 0)
		tower.force_enter_room_for_test(room_id)
		await get_tree().process_frame
		await get_tree().physics_frame
		previous_id = room_id

	tower_snapshot = tower.get_tower_snapshot()
	if int(tower_snapshot.get("support_floor_count", 0)) != 7:
		failures.append("Fully visited tower does not retain all seven load-bearing floors")
	if int(tower_snapshot.get("rendered_floor_count", 99)) > 2:
		failures.append("Too many stacked floors remain rendered after descent")
	var runtime := tower.get_runtime_snapshot()
	if int(runtime.get("active_rooms", 0)) > 3:
		failures.append("Tower streaming activates more than current plus two stair neighbors")
	var boss_present := false
	for enemy_value in get_tree().get_nodes_in_group("enemy_3d"):
		var enemy := enemy_value as Enemy3D
		if enemy != null and tower.is_ancestor_of(enemy) and enemy.room_id == "extraction" and enemy.enemy_kind == "boss":
			boss_present = true
			if absf(enemy.global_position.y - (tower.get("_room_by_id").get("extraction") as DungeonRoom3D).global_position.y) > 0.2:
				failures.append("Final-floor Boss uses the wrong global Y coordinate")
	if not boss_present:
		failures.append("Fifth floor does not spawn a Boss")
	if not bool(generation.get("has_extraction", false)):
		failures.append("Fifth floor has no final extraction beacon")

	var node_count := _count_nodes(tower)
	if node_count > 3500:
		failures.append("Fully visited five-floor tower exceeds 3500-node budget: %d" % node_count)
	tower.queue_free()
	await get_tree().process_frame
	_finish(failures, node_count)


func _count_named_nodes(root: Node, prefix: String) -> int:
	var count := 1 if root.name.begins_with(prefix) else 0
	for child in root.get_children():
		count += _count_named_nodes(child, prefix)
	return count


func _count_nodes(root: Node) -> int:
	var count := 1
	for child in root.get_children():
		count += _count_nodes(child)
	return count


func _count_hidden_cutaway_meshes(root: Node) -> int:
	var count := 0
	if root is MeshInstance3D and root.has_meta("stair_cutaway_surface_y") and not (root as MeshInstance3D).visible:
		count += 1
	for child in root.get_children():
		count += _count_hidden_cutaway_meshes(child)
	return count


func _find_collision_shape(root: Node) -> CollisionShape3D:
	if root == null:
		return null
	for child in root.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null


func _walk_player_to(player: Player3D, target: Vector3) -> bool:
	var best_distance := INF
	var stalled_frames := 0
	for _frame in range(420):
		var offset := target - player.global_position
		var planar := Vector3(offset.x, 0.0, offset.z)
		var distance := planar.length()
		if distance <= 0.32:
			player.set_test_move_direction(Vector3.ZERO)
			await get_tree().physics_frame
			return true
		player.set_test_move_direction(planar.normalized())
		await get_tree().physics_frame
		if distance < best_distance - 0.015:
			best_distance = distance
			stalled_frames = 0
		else:
			stalled_frames += 1
		if stalled_frames >= 75:
			player.set_test_move_direction(Vector3.ZERO)
			return false
	player.set_test_move_direction(Vector3.ZERO)
	return false


func _finish(failures: Array[String], node_count: int) -> void:
	if failures.is_empty():
		print("TOWER_DESCENT_FLOW_OK: rooftop, facility floor, five combat floors, 4m unit-aligned door-to-door stairs, fate doors, support streaming, coordinates, boss and budget pass (nodes=%d)" % node_count)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
