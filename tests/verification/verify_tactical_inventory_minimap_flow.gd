extends Node

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	for _frame in 5:
		await get_tree().process_frame

	var ui := dungeon.get("_inventory_ui") as InventoryUI
	var inventory := dungeon.get("_inventory") as InventoryModule
	_check(ui != null and inventory != null, "Formal dungeon did not create tactical inventory UI", failures)
	if ui == null or inventory == null:
		_finish(failures)
		return
	ui.set_inventory_panel_open(true)
	await get_tree().process_frame
	_check(ui.inventory_shell != null and ui.inventory_shell.visible, "Inventory shell is not visible", failures)
	_check(ui.equipment_panel != null, "Left character equipment panel is missing", failures)
	_check(ui.inventory_panel != null and ui.inventory_grid.columns == 6, "Right backpack grid is not orderly 6-column layout", failures)
	_check(ui.drop_zone != null and str(ui.drop_zone.get_meta("slot_kind", "")) == "drop", "World drop zone is missing", failures)
	_check(ui.sort_button != null, "Backpack sort button is missing", failures)
	_check(
		ui.equipment_weapon_slots.size() == 2
		and str(ui.equipment_weapon_slots[0].get_meta("slot_kind", "")) == "weapon_0"
		and str(ui.equipment_weapon_slots[1].get_meta("slot_kind", "")) == "weapon_1",
		"Main/secondary weapon equipment targets are missing", failures
	)
	_check(ui.quick_item_slots.size() == 2, "Two inventory quick-item targets are missing", failures)

	var hp_bar := dungeon.get_node("HUD/TopBar/Margin/HBox/HPBar") as ProgressBar
	var hp_fill := hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	_check(hp_fill != null and hp_fill.bg_color.r > 0.75 and hp_fill.bg_color.g < 0.25, "Main HUD health bar is not red", failures)
	var equipment_fill := ui.equipment_hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	_check(equipment_fill != null and equipment_fill.bg_color.r > 0.75 and equipment_fill.bg_color.g < 0.25, "Equipment panel health bar is not red", failures)

	var weapon_base := ItemRegistry.get_instance().get_item("weapon_rifle")
	var weapon := WeaponInstance.from_item(weapon_base)
	weapon.fate_upgrades = [
		{"slot_index": 1, "stable_card_id": "fate_overclock", "effect_version": 1},
		{"slot_index": 2, "stable_card_id": "fate_chain_lightning", "effect_version": 1},
	]
	var weapon_item := weapon.to_item_dictionary()
	_check(inventory.add_item(weapon_item, 1) == 1, "Cannot seed fate-built weapon into backpack", failures)
	var weapon_slot := inventory.find_weapon_instance_slot(weapon.weapon_instance_id)
	await get_tree().process_frame
	var weapon_slot_node := ui.get_node_or_null(
		"CharacterInventoryShell/@MarginContainer@*/InventoryColumns/InventoryPanel/VBox/InventoryGrid/InvSlot_%d" % weapon_slot
	)
	if weapon_slot_node == null and weapon_slot >= 0 and weapon_slot < ui._slots.size():
		weapon_slot_node = ui._slots[weapon_slot]
	_check(weapon_slot_node != null, "Weapon backpack slot UI is missing", failures)
	if weapon_slot_node != null:
		ui.call("_show_item_hover_card", weapon_item, 1)
		var hover_text := ui.item_hover_body.text if ui.item_hover_body != null else ""
		_check(ui.item_hover_card != null and ui.item_hover_card.visible, "Independent weapon hover card is not visible", failures)
		_check("权杖·二" in hover_text and "权杖·七" in hover_text, "Visible weapon hover card does not list installed tarot names", failures)
		for line in hover_text.split("\n"):
			if "｜" not in line:
				continue
			var summary := str(line).get_slice("｜", 1)
			_check(summary.length() <= 10, "Fate hover summary exceeds 10 characters: %s" % summary, failures)
		ui.call("_hide_item_hover_card")
		_check((weapon_slot_node as Control).has_signal("slot_drag_started") and (weapon_slot_node as Control).has_signal("slot_drag_finished"), "Inventory slot lacks visible drag lifecycle signals", failures)

	var original_id := str(weapon_item.get("weapon_instance_id", ""))
	ui.call("_on_slot_drop_received", weapon_slot, 11, "inventory", "inventory")
	_check(str((inventory.get_slot(11).get("item", {}) as Dictionary).get("weapon_instance_id", "")) == original_id, "Drag move rebuilt or lost weapon instance", failures)
	ui.sort_button.emit_signal("pressed")
	await get_tree().process_frame
	_check(str((inventory.get_slot(0).get("item", {}) as Dictionary).get("type", "")) == "weapon", "Backpack sorting did not place weapon category first", failures)

	var medkit := ItemRegistry.get_instance().get_item("item_health_potion")
	_check(inventory.add_item(medkit, 1) == 1, "Cannot seed droppable item", failures)
	var medkit_slot := _find_item_slot(inventory, "item_health_potion")
	var room := dungeon.get("_room_by_id").get("start") as DungeonRoom3D
	var pickups_before := room.find_children("*", "GroundLootPickup3D", true, false).size()
	_check(bool(ui.call("_drop_inventory_slot_to_world", medkit_slot)), "Dropping inventory item to world failed", failures)
	await get_tree().process_frame
	var pickups_after := room.find_children("*", "GroundLootPickup3D", true, false).size()
	_check(not inventory.has_item("item_health_potion") and pickups_after == pickups_before + 1, "Dropped item was not moved from backpack to current room", failures)

	var minimap := dungeon.get_node("HUD/DungeonMinimap3D") as DungeonMinimap3D
	minimap.set_current_room("start")
	minimap.set_player_state(Vector3.ZERO, Vector3.RIGHT)
	var player_before := minimap.get_player_screen_position()
	var start_before := minimap.get_room_screen_rect("start").get_center()
	minimap.set_player_state(Vector3(8.0, 0.0, 0.0), Vector3.RIGHT)
	var player_after := minimap.get_player_screen_position()
	var start_after := minimap.get_room_screen_rect("start").get_center()
	_check(player_after.is_equal_approx(player_before), "Minimap player marker is not fixed at radar center", failures)
	_check(start_after.x < start_before.x, "Minimap map does not move opposite to player movement", failures)
	minimap.set_enemy_positions([Vector3(3.0, 0.0, 2.0), Vector3(-4.0, 0.0, -2.0)])
	var map_snapshot := minimap.get_snapshot()
	_check(bool(map_snapshot.get("true_room_dimensions", false)), "Minimap snapshot does not declare true room dimensions", failures)
	_check(
		bool(map_snapshot.get("player_centered", false))
		and bool(map_snapshot.get("map_moves_with_player", false))
		and bool(map_snapshot.get("circular_content_clip", false))
		and not bool(map_snapshot.get("player_heading_line", true)),
		"Minimap is not player-centered/circular-clipped or still exposes the heading line", failures
	)
	_check(int(map_snapshot.get("enemy_marker_count", 0)) == 2, "Minimap does not expose enemy red-dot count", failures)
	var start_rect := minimap.get_room_screen_rect("start")
	var boss_rect := minimap.get_room_screen_rect("boss")
	_check(boss_rect.size.x > start_rect.size.x and boss_rect.size.y > start_rect.size.y, "Large room is not larger than medium room on minimap", failures)
	_check(absf(start_rect.size.x / maxf(1.0, start_rect.size.y) - 32.0 / 26.0) < 0.05, "Minimap distorts room width/height ratio", failures)

	dungeon.queue_free()
	_finish(failures)


func _find_item_slot(inventory: InventoryModule, item_id: String) -> int:
	for entry in inventory.get_occupied_slots():
		if str((entry.get("item", {}) as Dictionary).get("id", "")) == item_id:
			return int(entry.get("slot", -1))
	return -1


func _check(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("TACTICAL_INVENTORY_MINIMAP_OK: character equipment, explicit fate hover card, drag feedback contract, red HP, sort/drop, true room rectangles, player tracking and enemy dots pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
