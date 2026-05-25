extends Node


func _ready() -> void:
	var failures: Array[String] = []
	var mode := RoomGameMode.new()
	mode.map_seed = 424242
	add_child(mode)
	await get_tree().process_frame
	await get_tree().process_frame

	if mode.map_manager == null or mode.map_manager.get_graph() == null:
		_finish(["RoomGameMode did not generate a map"])
		return

	var graph: NodeGraph = mode.map_manager.get_graph()
	for node in graph.get_all_nodes():
		var expected_id := "F%02d-R%03d" % [node.room_data.floor, node.id]
		if node.room_data.room_id != expected_id:
			failures.append(
				"Room %d id is %s, expected %s" % [node.id, node.room_data.room_id, expected_id]
			)
		var room_instance: Node2D = mode.map_manager.get_instantiated_room(node.id)
		if room_instance == null:
			failures.append("Room %d was not instantiated" % node.id)
			continue
		var layout: Node = room_instance.get_node_or_null("RoomLayout")
		if layout == null:
			failures.append("Room %d has no RoomLayout" % node.id)
			continue
		var collision: StaticBody2D = layout.get_node_or_null("WallCollision") as StaticBody2D
		if collision == null or collision.get_child_count() < 4:
			failures.append("Room %d has no usable wall collision" % node.id)

	var player: Node2D = mode.player
	var current_id: int = mode.map_manager.get_current_room_id()
	var current_room: Node2D = mode.map_manager.get_instantiated_room(current_id)
	if player == null or current_room == null:
		failures.append("Player or current room missing")
	else:
		var current_data: RoomData = graph.get_node(current_id).room_data
		var current_rect := Rect2(
			current_room.global_position - current_data.size * 0.5, current_data.size
		)
		if not current_rect.has_point(player.global_position):
			failures.append("Player is not inside the active fixed room")
		var before_keys := int(mode.get("_room_key_count"))
		var key := Area2D.new()
		key.set_script(preload("res://src/game/RoomKeyPickup.gd"))
		key.position = Vector2(96, 0)
		current_room.add_child(key)
		key.call("setup", mode, current_id)
		await get_tree().physics_frame
		player.global_position = key.global_position
		await get_tree().physics_frame
		await get_tree().physics_frame
		await get_tree().process_frame
		if int(mode.get("_room_key_count")) <= before_keys:
			failures.append("Player overlap did not collect a spawned key pickup")

	var first_neighbor: int = -1
	if graph.get_neighbors(0).size() > 0:
		first_neighbor = int(graph.get_neighbors(0)[0])
	if first_neighbor >= 0:
		var before_count := 0
		var start_room: Node2D = mode.map_manager.get_instantiated_room(0)
		var start_layout: Node = start_room.get_node_or_null("RoomLayout")
		if start_layout != null:
			var before_collision: StaticBody2D = (
				start_layout.get_node_or_null("WallCollision") as StaticBody2D
			)
			if before_collision != null:
				before_count = before_collision.get_child_count()
		mode.map_manager.path_director.open_door(0, first_neighbor)
		mode._apply_open_doors_to_room(0)
		await get_tree().process_frame
		var open_count := 0
		if start_layout != null:
			var wall_collision: StaticBody2D = (
				start_layout.get_node_or_null("WallCollision") as StaticBody2D
			)
			if wall_collision != null:
				open_count = wall_collision.get_child_count()
		if open_count <= before_count:
			failures.append("Opening a door did not rebuild wall segments around an open aperture")

	var spawner := RoomWaveSpawner.new()
	add_child(spawner)
	var combat_id := _find_combat_room(graph)
	var combat_room: Node2D = mode.map_manager.get_instantiated_room(combat_id)
	if combat_room == null:
		failures.append("No combat room available for spawn validation")
	else:
		mode.player.global_position = combat_room.global_position + Vector2(430, 320)
		spawner.configure(
			[1],
			combat_room,
			mode.player,
			1,
			RoomData.FloorLevel.SHALLOW,
			mode,
			graph.get_node(combat_id).room_data.size
		)
		var safe_rect := Rect2(
			(
				combat_room.global_position
				- graph.get_node(combat_id).room_data.size * 0.5
				+ Vector2(120, 112)
			),
			graph.get_node(combat_id).room_data.size - Vector2(240, 224)
		)
		for i in range(32):
			var pos: Vector2 = spawner._get_spawn_position(mode.player.global_position)
			if not safe_rect.has_point(pos):
				failures.append("Enemy spawn position outside safe room bounds: %s" % pos)
				break

	_finish(failures)


func _find_combat_room(graph: NodeGraph) -> int:
	for node in graph.get_all_nodes():
		if node.room_data != null and node.room_data.is_combat():
			return node.id
	return 0


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print(
			"MAP_LAYOUT_FLOW_OK: fixed room ids, player placement, wall collision, and spawn bounds are coherent"
		)
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
