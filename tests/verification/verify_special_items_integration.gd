extends Node
var failures: Array[String] = []
var checks := 0
var _persistent_edges := 0
func _ready() -> void:
	call_deferred("_run")
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("SPECIAL_ITEMS_INTEGRATION_FAIL: " + message)
func _right(down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = down
	event.position = Vector2(640, 430)
	event.global_position = event.position
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().physics_frame
func _run() -> void:
	var dungeon := preload("res://scenes/Dungeon3D.tscn").instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	for _frame in 8:
		await get_tree().physics_frame
	var inventory := dungeon.get_inventory_module()
	for definition: Dictionary in SpecialItemCatalog.definitions():
		inventory.add_item(definition, 3)
	var controller := dungeon.player.get_special_item_controller()
	controller.persistent_state_changed.connect(func() -> void: _persistent_edges += 1)
	var slot := -1
	for entry: Dictionary in inventory.get_occupied_slots():
		if str(entry.item.id) == SpecialItemCatalog.GRENADE:
			slot = int(entry.slot)
	dungeon._on_inventory_item_clicked(slot, {})
	_check(controller.item_id == SpecialItemCatalog.GRENADE, "actual inventory click equips")
	_check(dungeon._inventory_ui.special_equipment_slot.controller == controller, "actual equipment slot binds same owner")
	var hud := dungeon.get_node("HUD/ReferenceCombatHUD/SpecialItemHUD") as SpecialItemHUD
	_check(hud.controller == controller, "actual HUD binds same owner")
	await _right(true)
	for _frame in 6:
		await get_tree().physics_frame
	_check(inventory.get_item_count(SpecialItemCatalog.GRENADE) == 2, "real right press consumes once")
	_check(controller.world.projectiles.size() <= 1, "holding does not repeat throw")
	await _right(false)
	controller.cooldown_remaining = 0.0
	dungeon._inventory_ui.set_inventory_panel_open(true)
	await _right(true)
	_check(inventory.get_item_count(SpecialItemCatalog.GRENADE) == 2, "inventory modal blocks real right press")
	dungeon._inventory_ui.set_inventory_panel_open(false)
	await get_tree().physics_frame
	_check(inventory.get_item_count(SpecialItemCatalog.GRENADE) == 2, "closing modal while held does not throw")
	await _right(false)
	controller.equip(SpecialItemCatalog.GASOLINE)
	controller.restore_state({"item_id": SpecialItemCatalog.GASOLINE, "fuel_units": 17, "cooldown_remaining": 0.1})
	var snapshot := dungeon.build_runtime_save_snapshot()
	_check(str((snapshot.get("special_items", {}) as Dictionary).get("item_id", "")) == SpecialItemCatalog.GASOLINE, "formal runtime snapshot exports selection")
	controller.unequip()
	dungeon._restore_carried_ownership(snapshot, false)
	_check(controller.item_id == SpecialItemCatalog.GASOLINE and controller.fuel_units == 17, "formal restore keeps open bottle and selection")
	_check(inventory.get_item_count(SpecialItemCatalog.GASOLINE) == 3, "save restore does not duplicate or spend unopened bottles")
	_check(_persistent_edges >= 4, "equip/use/unequip publish persistence edges without cooldown frame spam")
	controller.pouring = true
	dungeon.player.set_input_locked(true)
	_check(not controller.pouring, "opening player input lock stops pour immediately")
	controller.pouring = true
	controller._notification(NOTIFICATION_PAUSED)
	_check(not controller.pouring, "tree pause cancels held pouring and requires a new press")
	controller.clear_world()
	_check(controller.world.oil.is_empty() and controller.world.fires.is_empty() and controller.world.projectiles.is_empty(), "scene/floor cleanup owns all temporary fields")
	dungeon.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if failures.is_empty():
		print("SPECIAL_ITEMS_INTEGRATION_OK: %d checks; actual inventory, HUD, mouse input, modal and runtime save" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)
