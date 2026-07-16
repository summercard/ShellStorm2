extends Node


func _ready() -> void:
	var failures: Array[String] = []
	var main_scene_path := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene_path != "res://scenes/BaseWorld.tscn":
		failures.append("Project entry is not the editable BaseWorld scene")

	var base_scene := load("res://scenes/BaseWorld.tscn") as PackedScene
	if base_scene == null:
		failures.append("BaseWorld scene does not load")
		_finish(failures, 0)
		return

	LevelSelect.return_entrance_id = "spore_depths_gate"
	var base_world := base_scene.instantiate() as BaseWorld
	add_child(base_world)
	await get_tree().process_frame
	await get_tree().process_frame

	var node_count := _count_nodes(base_world)
	if node_count > 220:
		failures.append("BaseWorld first slice is unexpectedly heavy: %d nodes" % node_count)
	if base_world.get_facility_count() != 8:
		failures.append("BaseWorld does not expose seven lobby functions plus the training range")
	if base_world.player == null or base_world.player.combat_enabled:
		failures.append("BaseWorld player is missing or can shoot inside the hub")
	if base_world.camera.get_parent() != base_world.player:
		failures.append("BaseWorld camera does not follow the free-roaming player")
	if base_world.camera.limit_right < 7000:
		failures.append("BaseWorld does not include a continuous explorable wilderness")
	if base_world.get_dungeon_entrance_count() != 4:
		failures.append("BaseWorld does not expose four roadside dungeon entrances")
	var atmosphere := base_world.get_node_or_null("Atmosphere") as BaseWorldAtmosphere
	if atmosphere == null:
		failures.append("BaseWorld has no isolated apocalypse atmosphere layer")
	else:
		if atmosphere.get_sparse_light_count() < 8:
			failures.append("BaseWorld apocalypse pass has too few sparse navigation lights")
		if atmosphere.get_zone_light_colors().size() < 4:
			failures.append("BaseWorld dungeon districts do not have distinct light colors")
		if not atmosphere.has_screen_atmosphere():
			failures.append("BaseWorld has no non-interactive screen atmosphere overlay")
		var details := atmosphere.get_detail_counts()
		if int(details.get("cracks", 0)) < 24 or int(details.get("ruins", 0)) < 6:
			failures.append("BaseWorld apocalypse pass lacks road damage or ruin silhouettes")
		if int(details.get("wrecks", 0)) < 2 or int(details.get("barriers", 0)) < 2:
			failures.append("BaseWorld roadside story props are incomplete")
	var base_hud := base_world.get_node_or_null("HUD") as CanvasLayer
	if base_hud == null or base_hud.layer <= 5:
		failures.append("BaseWorld HUD is not protected above the screen atmosphere layer")

	var mission_room := base_world.get_node_or_null("Facilities/MissionOperations")
	var base_console := base_world.get_node_or_null("Facilities/BaseConsole")
	var training_range := base_world.get_node_or_null("Facilities/TrainingRange")
	if (
		mission_room == null
		or int(mission_room.get("activation_type")) != BaseFacility.ActivationType.SHOW_INFO
		or not str(mission_room.get("menu_scene_path")).is_empty()
	):
		failures.append("Mission room still bypasses wilderness dungeon entrances")
	if base_console == null or str(base_console.get("menu_scene_path")) != "res://scenes/BaseMenu.tscn":
		failures.append("Base management terminal does not preserve the current lobby functions")
	if (
		training_range == null
		or int(training_range.get("activation_type")) != BaseFacility.ActivationType.LOAD_SCENE
		or str(training_range.get("target_scene_path")) != "res://scenes/TrainingRange.tscn"
		or not ResourceLoader.exists(str(training_range.get("target_scene_path")), "PackedScene")
	):
		failures.append("Base training facility does not route to an independent training scene")

	var entrance_ids: Dictionary = {}
	for entrance in get_tree().get_nodes_in_group("dungeon_entrance"):
		if not base_world.is_ancestor_of(entrance):
			continue
		var entrance_id := str(entrance.get("entrance_id"))
		var map_path := str(entrance.get("target_scene_path"))
		if entrance_ids.has(entrance_id):
			failures.append("Two dungeon entrances share id %s" % entrance_id)
		entrance_ids[entrance_id] = true
		if not ResourceLoader.exists(map_path, "PackedScene"):
			failures.append("Dungeon entrance points to missing scene: %s" % map_path)

	var return_gate := base_world.get_node_or_null("DungeonEntrances/Dungeon03") as Node2D
	if return_gate == null or base_world.player.global_position.distance_to(
		return_gate.global_position + Vector2(0, 180)
	) > 1.0:
		failures.append("Returning from a dungeon does not restore the player outside its entrance")
	if not LevelSelect.return_entrance_id.is_empty():
		failures.append("Dungeon return entrance state is not consumed")

	if base_console != null:
		base_world.call("_on_facility_activated", base_console)
		await get_tree().process_frame
		var console_menu := base_world.get_active_menu()
		if console_menu == null or not console_menu is BaseMenu:
			failures.append("Base management terminal does not open the compatibility lobby")
		else:
			if not console_menu.overlay_mode or not console_menu.close_overlay_button.visible:
				failures.append("Compatibility lobby cannot return to the free-roaming base")
			if not console_menu.level_select_button.disabled:
				failures.append("Base management terminal still allows direct dungeon selection")
			console_menu.queue_free()
			await get_tree().process_frame

	if base_world.player.input_locked:
		failures.append("Closing a base facility menu leaves player movement locked")
	base_world.queue_free()
	await get_tree().process_frame
	_finish(failures, node_count)


func _count_nodes(root: Node) -> int:
	var count := 1
	for child in root.get_children():
		count += _count_nodes(child)
	return count


func _finish(failures: Array[String], node_count: int) -> void:
	if failures.is_empty():
		print("BASE_WORLD_FLOW_OK: fixed base and wilderness share one editable map, four roadside entrances route independent dungeons, and returns restore the correct doorway (nodes=%d)" % node_count)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
