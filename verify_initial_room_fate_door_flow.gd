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
	if start_node.room_data.size != Vector2(448, 320):
		failures.append("Initial room is not the fixed small size")
	if int(mode.get("_room_key_count")) != 1:
		failures.append("Initial room does not grant exactly one starting key")

	var fate_panel: Control = ui.get_node_or_null("FateCardPanel") as Control
	if fate_panel == null:
		failures.append("FateCardPanel missing")
	elif fate_panel.visible:
		failures.append("Fate card panel appears before opening the initial door")

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
