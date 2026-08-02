extends Node


func _ready() -> void:
	var failures: Array[String] = []
	var loot := LootModule.get_instance()
	loot.set_seed(17001)

	_verify_loot_loop(loot, failures)
	await _verify_main_scene_loop(failures)

	_finish(failures)


func _verify_loot_loop(loot: LootModule, failures: Array[String]) -> void:
	var combat_loot := loot.generate_loot("combat_floor_1", 8)
	if combat_loot.is_empty():
		failures.append("Chapter 1 combat loot table produces no items")
	if not _contains_type(combat_loot, ["module", "attachment"]):
		failures.append("Chapter 1 combat loot does not surface weapon modules or attachments")

	var scavenge_found_key := false
	var scavenge_found_weapon_part := false
	for i in range(24):
		var found := loot.generate_container_loot("crate", 1)
		scavenge_found_key = scavenge_found_key or _contains_id(found, "item_room_key")
		scavenge_found_weapon_part = (
			scavenge_found_weapon_part or _contains_type(found, ["module", "attachment"])
		)
	if not scavenge_found_key:
		failures.append(
			"Chapter 1 searchable containers did not produce a key over repeated checks"
		)
	if not scavenge_found_weapon_part:
		failures.append(
			"Chapter 1 searchable containers did not produce weapon parts over repeated checks"
		)

	var monster_found_key := false
	var monster_found_item := false
	var monster_found_no_item := false
	for i in range(40):
		var dropped := loot.generate_enemy_loot({"floor": 1, "loot_table": "combat_floor_1"})
		monster_found_key = monster_found_key or _contains_id(dropped, "item_room_key")
		monster_found_item = monster_found_item or _contains_non_currency(dropped)
		monster_found_no_item = monster_found_no_item or not _contains_non_currency(dropped)
	if not monster_found_key:
		failures.append("Chapter 1 monster drops did not produce a room key over repeated checks")
	if not monster_found_item:
		failures.append("Chapter 1 monster drops never produced usable loot")
	if not monster_found_no_item:
		failures.append(
			"Ordinary monsters always produced item loot instead of respecting drop chance"
		)


func _verify_main_scene_loop(failures: Array[String]) -> void:
	var main_scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	if main_scene == null:
		failures.append("Main scene does not load")
		return

	var main := main_scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var mode: RoomGameMode = main.get_node_or_null("RoomGameMode") as RoomGameMode
	var ui: CanvasLayer = main.get_node_or_null("GameUIManager") as CanvasLayer
	if mode == null or ui == null or mode.inventory_module == null:
		failures.append("Main scene did not create gameplay mode, UI, and inventory")
		main.queue_free()
		return

	var graph: NodeGraph = mode.map_manager.get_graph()
	var start_room: Node2D = mode.map_manager.get_instantiated_room(0)
	var neighbors: Array[int] = graph.get_neighbors(0)
	if start_room == null or neighbors.is_empty():
		failures.append("Initial room or its exit is missing")
	else:
		var door := start_room.get_node_or_null("DoorExit_%d" % int(neighbors[0]))
		if door == null:
			failures.append("Initial room door is not visible when the map is generated")
		elif mode.map_manager.path_director.are_connected(0, int(neighbors[0])):
			failures.append("Initial door starts open instead of waiting for a key")

	var attach_item := ItemRegistry.get_instance().get_item("attach_triple_muzzle")
	if attach_item.is_empty():
		failures.append("Test attachment item missing from registry")
	else:
		mode.inventory_module.add_item(attach_item, 1)
		await get_tree().process_frame
		var occupied := mode.inventory_module.get_occupied_slots()
		var slot_index := _find_slot_with_id(occupied, "attach_triple_muzzle")
		if slot_index < 0:
			failures.append("Attachment could not be placed in inventory")
		else:
			var slot_info := mode.inventory_module.get_slot(slot_index)
			var preview_slot := TextureRect.new()
			ui.call("_update_slot_with_item", preview_slot, slot_info)
			var glyph := preview_slot.get_node_or_null("ItemGlyph") as Label
			if preview_slot.texture == null:
				failures.append("Inventory item without art does not receive a generated icon")
			if glyph == null or glyph.text != "ATT":
				failures.append(
					"Inventory attachment slot does not show an operable weapon-part marker"
				)
			preview_slot.queue_free()

			_click_inventory_slot(ui, slot_index, MOUSE_BUTTON_LEFT)
			await get_tree().process_frame
			var root: AssemblyNode = mode.player.get_weapon_tree().get_root()
			if root == null or root.slots.get(AssemblyNode.SlotType.MUZZLE) == null:
				(
					failures
					. append(
						"Right-clicking an inventory attachment does not install it into the weapon tree"
					)
				)
			if mode.inventory_module.has_item("attach_triple_muzzle"):
				failures.append("Installed weapon part was not consumed from inventory")

	main.queue_free()
	await get_tree().process_frame


func _contains_id(items: Array[Dictionary], item_id: String) -> bool:
	for item in items:
		if item.get("id", "") == item_id:
			return true
	return false


func _contains_type(items: Array[Dictionary], types: Array[String]) -> bool:
	for item in items:
		if item.get("type", "") in types:
			return true
	return false


func _contains_non_currency(items: Array[Dictionary]) -> bool:
	for item in items:
		if not item.get("is_currency", false):
			return true
	return false


func _find_slot_with_id(slots: Array[Dictionary], item_id: String) -> int:
	for slot in slots:
		var item: Dictionary = slot.get("item", {})
		if item.get("id", "") == item_id:
			return int(slot.get("slot", -1))
	return -1


func _click_inventory_slot(ui: CanvasLayer, slot_index: int, button_index: MouseButton) -> void:
	var slot := ui.get_node_or_null("InventoryPanel/VBox/InventoryGrid/InvSlot_%d" % slot_index)
	if slot == null:
		return
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	slot.call("_on_gui_input", event)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print(
			"CH1_GAMEPLAY_LOOP_OK: visible doors, chance-based ground loot, key drops, inventory icons, and weapon assembly are playable"
		)
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
