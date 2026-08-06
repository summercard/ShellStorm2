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
	var player := mode.get_player()
	if player != null:
		player.current_hp = maxi(1, player.max_hp - 25)
	await get_tree().process_frame
	var medkit_slot := _find_inventory_slot(mode.inventory_module, "item_health_potion")
	if medkit_slot < 0:
		failures.append("Could not seed inventory with medkit")
	else:
		var slot_node := ui.get_node_or_null("InventoryPanel/VBox/InventoryGrid/InvSlot_%d" % medkit_slot)
		if slot_node == null:
			failures.append("Inventory medkit slot is not wired as a clickable control")
		else:
			ui.call("_on_slot_mouse_entered", slot_node)
			await get_tree().process_frame
			var hover_card := ui.get("_item_hover_card") as Control
			if hover_card == null or not hover_card.visible:
				failures.append("Hovering an inventory item does not show the item info card")
			ui.call("_on_slot_mouse_exited", slot_node)
			var count_label := slot_node.get_node_or_null("CountLabel") as Control
			if count_label != null and count_label.mouse_filter != Control.MOUSE_FILTER_IGNORE:
				failures.append("Inventory count label intercepts clicks intended for its item slot")
			var pressed := InputEventMouseButton.new()
			pressed.button_index = MOUSE_BUTTON_LEFT
			pressed.pressed = true
			slot_node.call("_on_gui_input", pressed)
			var released := InputEventMouseButton.new()
			released.button_index = MOUSE_BUTTON_LEFT
			released.pressed = false
			slot_node.call("_on_gui_input", released)
		await get_tree().process_frame
		if mode.insurance_module.get_used_slots() != 0:
			failures.append("Plain left-click moved an actionable item into insurance")
		if mode.inventory_module.has_item("item_health_potion"):
			failures.append("Left-clicking a consumable item did not use it")
		mode.inventory_module.add_item(medkit, 1)
		await get_tree().process_frame
		medkit_slot = _find_inventory_slot(mode.inventory_module, "item_health_potion")
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
		inventory_panel.visible = true
		insurance_panel.visible = true
		if not ui.call("blocks_gameplay_input"):
			failures.append("Open inventory panels do not block gameplay input")
		player = mode.get_player()
		var weapon_controller := (
			player.get_node_or_null("WeaponController") if player != null else null
		)
		if weapon_controller == null:
			failures.append("Player weapon controller is missing")
		elif not weapon_controller.call("_is_gameplay_input_blocked"):
			failures.append("Weapon controller still accepts shooting while inventory is open")
		inventory_panel.visible = false
		insurance_panel.visible = false
		if ui.call("blocks_gameplay_input"):
			failures.append("Closed inventory panels still block gameplay input")
		var before := Vector2(inventory_panel.offset_left, inventory_panel.offset_top)
		ui.set("_dragging_inventory_panel", true)
		ui.set("_inventory_drag_start_panel", before)
		ui.set("_inventory_drag_start_insurance", Vector2(insurance_panel.offset_left, insurance_panel.offset_top))
		ui.call("_move_inventory_panel_pair", Vector2(28, 18))
		await get_tree().process_frame
		var after := Vector2(inventory_panel.offset_left, inventory_panel.offset_top)
		if after == before:
			failures.append("Inventory panel drag helper did not move the panel")

	var transition_fx := main.get_node_or_null("RoomTransitionFX")
	var curtain := (
		transition_fx.get_node_or_null("RoomTransitionCurtain") as Control
		if transition_fx != null
		else null
	)
	if curtain == null or curtain.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		failures.append("Room transition overlay blocks inventory mouse hover/clicks")
	var fog_layer := main.get_node_or_null("FogOfWarLayer")
	var fog_rect := (
		fog_layer.get_node_or_null("FogOfWar") as Control if fog_layer != null else null
	)
	if fog_rect == null or fog_rect.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		failures.append("Fog overlay blocks inventory mouse hover/clicks")

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
