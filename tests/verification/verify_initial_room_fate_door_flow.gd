extends Node


func _ready() -> void:
	var failures: Array[String] = []
	var main_scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	if main_scene == null:
		_finish(["Main scene does not load"])
		return

	var main := main_scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var mode: RoomGameMode = main.get_node_or_null("RoomGameMode") as RoomGameMode
	var ui: CanvasLayer = main.get_node_or_null("GameUIManager") as CanvasLayer
	if mode == null or ui == null:
		_finish(["Main scene did not create RoomGameMode and GameUIManager"])
		return

	var graph: NodeGraph = mode.map_manager.get_graph()
	var start_node := graph.get_node(0)
	if start_node == null or start_node.room_data == null:
		_finish(["Start room data missing"])
		return

	if start_node.room_data.room_type != RoomData.RoomType.PLAYER_SPAWN:
		failures.append("Room 0 is not the initial spawn room")
	if start_node.room_data.size != Vector2(GridConstants.ROOM_PIXEL_WIDTH, GridConstants.ROOM_PIXEL_HEIGHT):
		failures.append("Initial room size does not match the physical room grid")
	if int(mode.get("_room_key_count")) != 1:
		failures.append("Initial room does not grant exactly one starting key")
	var start_room: Node2D = mode.map_manager.get_instantiated_room(0)
	if start_room == null or start_room.get_node_or_null("Visualizer") == null:
		failures.append("Initial room does not use a dedicated visualized scene")
	else:
		var floor_layer: TileMapLayer = start_room.get_node_or_null("FloorLayer") as TileMapLayer
		if floor_layer == null or floor_layer.get_used_cells().is_empty():
			failures.append("Initial room does not build its floor tiles")
		else:
			var world_background := main.get_node_or_null("WorldPlaceholder") as Node2D
			if world_background != null and floor_layer.z_index <= world_background.z_index:
				failures.append("Walkable floor is rendered underneath the black world background")
			if mode.player != null and floor_layer.z_index >= mode.player.z_index:
				failures.append("Walkable floor is rendered above the player")
			var floor_bounds := floor_layer.get_used_rect()
			if floor_bounds.position.x < -10 or floor_bounds.position.y < -10:
				failures.append("Initial room tile map is not centered on the room origin")
		var visualizer: Node = start_room.get_node_or_null("Visualizer")
		if visualizer.get("room_size") != Vector2(GridConstants.ROOM_PIXEL_WIDTH, GridConstants.ROOM_PIXEL_HEIGHT):
			failures.append("Initial room visualizer does not cover its full walkable bounds")

	var fate_panel: Control = ui.get_node_or_null("FateCardPanel") as Control
	if fate_panel == null:
		failures.append("FateCardPanel missing")
	elif fate_panel.visible:
		failures.append("Fate card panel appears before opening the initial door")
	await get_tree().create_timer(0.15).timeout
	var boss_panel: Control = ui.get_node_or_null("BossHPPanel") as Control
	if boss_panel != null and boss_panel.visible:
		failures.append("Boss HP appears before the player enters the boss room")

	var neighbors: Array[int] = graph.get_neighbors(0)
	if neighbors.is_empty():
		failures.append("Initial room has no exit")
		_finish(failures)
		return
	if neighbors.size() != 1:
		failures.append("Initial room should have exactly one exit")

	var target_id := int(neighbors[0])
	mode.try_open_room_door(target_id)
	await get_tree().process_frame
	await get_tree().process_frame

	if int(mode.get("_room_key_count")) != 0:
		failures.append("Opening the initial door did not spend the starting key")
	if not mode.map_manager.path_director.are_connected(0, target_id):
		failures.append("Initial door was not opened")
	if fate_panel == null or not fate_panel.visible:
		failures.append("Opening the initial door did not trigger fate card choice")
	else:
		var weapon_tree: WeaponAssemblyTree = mode.player.get_weapon_tree()
		var before_fire_rate: float = weapon_tree.fire_rate
		mode.call("_on_fate_card_button_pressed", FateCardPresets.overclock())
		await get_tree().process_frame
		if weapon_tree.fire_rate <= before_fire_rate:
			failures.append("Selecting overclock did not increase live weapon fire rate")
		if fate_panel.visible:
			failures.append("Successful fate choice did not close the choice panel")

	var onward_id := _find_unopened_exit(graph, mode, target_id, 0)
	if onward_id < 0:
		failures.append("First explored room has no unopened door to verify repeated fate choices")
	else:
		mode._cleared_room_ids[target_id] = true
		mode.call("_enter_room_by_id", target_id, 0)
		await get_tree().process_frame
		mode.collect_room_key(target_id)
		mode.try_open_room_door(onward_id)
		await get_tree().process_frame
		await get_tree().process_frame
		if fate_panel == null or not fate_panel.visible:
			failures.append("Opening a later door with a key did not trigger fate card choice")

	main.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	await get_tree().process_frame
	_finish(failures)


func _find_unopened_exit(
	graph: NodeGraph, mode: RoomGameMode, room_id: int, previous_id: int
) -> int:
	for neighbor_id in graph.get_neighbors(room_id):
		if neighbor_id == previous_id:
			continue
		if not mode.map_manager.path_director.are_connected(room_id, neighbor_id):
			return int(neighbor_id)
	return -1


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print(
			"INITIAL_ROOM_FATE_DOOR_OK: every keyed door triggers fate choice and selected upgrades change live weapon stats"
		)
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
