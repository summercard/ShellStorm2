extends Node

func _ready() -> void:
	var failures: Array[String] = []
	await _verify_inventory_ui(failures)
	_finish(failures)

func _verify_inventory_ui(failures: Array[String]) -> void:
	var main_scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	if main_scene == null:
		failures.append("Main scene does not load")
		return
	var main := main_scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var mode: RoomGameMode = main.get_node_or_null("RoomGameMode") as RoomGameMode
	var ui: CanvasLayer = main.get_node_or_null("GameUIManager") as CanvasLayer
	if mode == null or ui == null or mode.inventory_module == null or mode.insurance_module == null:
		failures.append("Main did not create inventory, insurance, and UI")
		main.queue_free()
		return

	var weapon_panel := ui.get_node_or_null("GameHUD/EquippedWeaponPanel")
	var weapon_slot := (
		weapon_panel.find_child("EquippedWeaponSlot", true, false) if weapon_panel != null else null
	)
	if weapon_panel == null or weapon_slot == null:
		failures.append("Main HUD does not show equipped weapon slot")

	var medkit := ItemRegistry.get_instance().get_item("item_health_potion")
	mode.inventory_module.add_item(medkit, 1)
	await get_tree().process_frame
	var medkit_slot := _find_inventory_slot(mode.inventory_module, "item_health_potion")
	if medkit_slot < 0:
		failures.append("Could not seed inventory with medkit")
	else:
		ui.call("_on_slot_clicked", medkit_slot, true)
		await get_tree().process_frame
		if mode.insurance_module.get_used_slots() != 0:
			failures.append("Plain left-click moved item into insurance; it should only select")
		ui.call("_on_item_to_insurance_requested", medkit_slot)
		await get_tree().process_frame
		if mode.insurance_module.get_used_slots() != 1:
			failures.append("Shift-left-click did not move item into insurance")
		ui.call("_on_slot_clicked", 0, false)
		await get_tree().process_frame
		if mode.insurance_module.get_used_slots() != 0 or not mode.inventory_module.has_item("item_health_potion"):
			failures.append("Left-clicking insurance slot did not return item to backpack")

	var inventory_panel := ui.get_node_or_null("InventoryPanel") as Control
	var insurance_panel := ui.get_node_or_null("InsurancePanel") as Control
	if inventory_panel == null or insurance_panel == null:
		failures.append("Inventory/insurance panels are missing")
	else:
		var before := Vector2(inventory_panel.offset_left, inventory_panel.offset_top)
		ui.set("_dragging_inventory_panel", true)
		ui.set("_inventory_drag_start_panel", before)
		ui.set("_inventory_drag_start_insurance", Vector2(insurance_panel.offset_left, insurance_panel.offset_top))
		ui.call("_move_inventory_panel_pair", Vector2(28, 18))
		await get_tree().process_frame
		var after := Vector2(inventory_panel.offset_left, inventory_panel.offset_top)
		if after == before:
			failures.append("Inventory panel drag helper did not move the panel")

	main.queue_free()

func _find_inventory_slot(inventory: InventoryModule, item_id: String) -> int:
	for slot in inventory.get_occupied_slots():
		var item: Dictionary = slot.get("item", {})
		if item.get("id", "") == item_id:
			return int(slot.get("slot", -1))
	return -1

func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("INVENTORY_EQUIPMENT_UI_OK: equipped weapon slot, safe insurance roundtrip, and draggable backpack UI are available")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
