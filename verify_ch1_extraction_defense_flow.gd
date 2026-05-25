extends Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	var main_scene := load("res://scenes/Main.tscn") as PackedScene
	if main_scene == null:
		_finish(["Main scene does not load"])
		return
	var main := main_scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var mode := main.get_node_or_null("RoomGameMode") as RoomGameMode
	var ui := main.get_node_or_null("GameUIManager") as GameUIManager
	if mode == null or ui == null:
		_finish(["Main did not create room mode and UI"])
		return

	var graph: NodeGraph = mode.map_manager.get_graph()
	var extraction_id := _find_room_id(graph, RoomData.RoomType.EXTRACTION)
	var boss_id := _find_room_id(graph, RoomData.RoomType.BOSS)
	if extraction_id < 0:
		failures.append("Generated chapter map has no dedicated extraction room")
	if boss_id < 0:
		failures.append("Generated chapter map has no boss room")
	if extraction_id == boss_id:
		failures.append("Boss room is reused as the extraction room")
	if boss_id >= 0 and graph.get_node(boss_id).room_data.is_extraction():
		failures.append("Boss room is still classified as an extraction room")

	if extraction_id >= 0:
		var extraction_room := mode.map_manager.get_instantiated_room(extraction_id)
		mode.call("_set_room_revealed", extraction_id, true)
		mode.player.global_position = extraction_room.global_position
		mode.map_manager.enter_room(extraction_id)
		await get_tree().process_frame
		if mode.extraction_module.get_status() != ExtractionModule.ExtractionStatus.IDLE:
			failures.append("Entering extraction room starts countdown before operating the switch")
		if _has_center_container(extraction_room, extraction_room.global_position):
			failures.append(
				"Legacy extraction point is still rendered as a container over the switch"
			)
		if (
			not extraction_room.has_method("arm_switch")
			or not extraction_room.has_method("_try_use_switch")
		):
			failures.append("Extraction room has no usable extraction switch")
		else:
			extraction_room.call("_on_switch_body_entered", mode.player)
			if not bool(extraction_room.call("_try_use_switch")):
				failures.append("Operating extraction switch did not start extraction defense")
			await get_tree().process_frame
			await get_tree().process_frame
			if mode.extraction_module.get_status() != ExtractionModule.ExtractionStatus.COUNTDOWN:
				failures.append("Switch activation does not enter extraction countdown")
			if _count_enemies(extraction_room) < 1:
				failures.append("Extraction countdown does not immediately create pressure")
			var countdown_bar := ui.get_node_or_null("ExtractionPanel/VBox/CountdownBar") as Control
			if countdown_bar == null or not countdown_bar.visible:
				failures.append("Extraction defense does not show countdown UI")

			mode.extraction_module.update(5.0)
			mode.call("_update_extraction_defense")
			await get_tree().process_frame
			mode.set("_run_risk", 10)
			mode.extraction_module.update(5.0)
			mode.call("_update_extraction_defense")
			await get_tree().process_frame
			if not _has_elite(extraction_room):
				failures.append("Late extraction defense phase never produces an elite threat")

			mode.extraction_module.update(4.1)
			await get_tree().process_frame
			var success_panel := ui.get_node_or_null("ExtractionSuccessPanel") as Control
			if success_panel == null or not success_panel.visible:
				failures.append("Surviving extraction countdown does not show settlement panel")
			if not get_tree().paused or not Global.is_paused:
				failures.append(
					"Extraction settlement does not enter a consistent paused result state"
				)
			await get_tree().create_timer(0.5, true).timeout
			if success_panel != null and success_panel.modulate.a < 0.95:
				failures.append(
					"Extraction settlement remains visually frozen until pause is toggled"
				)
			if not mode.player.get("input_locked"):
				failures.append("Player remains controllable after successful extraction")
			if _count_enemies(extraction_room) > 0:
				failures.append("Extraction enemies remain active after the success settlement")
			var continue_button := (
				ui.get_node_or_null("ExtractionSuccessPanel/VBox/ContinueButton") as Button
			)
			if continue_button == null or continue_button.process_mode != Node.PROCESS_MODE_ALWAYS:
				failures.append(
					"Return-to-base button cannot process input while result screen pauses play"
				)

	Global.is_paused = false
	get_tree().paused = false
	_finish(failures)


func _find_room_id(graph: NodeGraph, room_type: RoomData.RoomType) -> int:
	for node in graph.get_all_nodes():
		if node.room_data.room_type == room_type:
			return node.id
	return -1


func _count_enemies(root: Node) -> int:
	var total := 0
	for child in root.get_children():
		if child.is_in_group("enemy"):
			total += 1
		total += _count_enemies(child)
	return total


func _has_elite(root: Node) -> bool:
	for child in root.get_children():
		if (
			child.is_in_group("enemy")
			and child.has_method("is_elite")
			and bool(child.call("is_elite"))
		):
			return true
		if _has_elite(child):
			return true
	return false


func _has_center_container(root: Node, center: Vector2) -> bool:
	for child in root.get_children():
		if (
			child is ContainerInteraction
			and (child as Node2D).global_position.distance_to(center) < 72.0
		):
			return true
		if _has_center_container(child, center):
			return true
	return false


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print(
			"CH1_EXTRACTION_DEFENSE_OK: dedicated extraction switch starts timed defense, elite pressure, and survival settlement"
		)
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
