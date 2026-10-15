extends Node

var failures: Array[String] = []
var clicked := -1
var pointer := Vector2(640, 360)
var checks := 0
var pointer_held := false

func _ready() -> void:
	get_window().position = Vector2i(100, 100)
	get_window().size = Vector2i(1280, 720)
	get_window().grab_focus()
	Input.use_accumulated_input = false
	var dungeon := preload("res://scenes/Dungeon3D.tscn").instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	await frames(12)
	var ui := dungeon.get("_inventory_ui") as InventoryUI
	var inventory := dungeon.get("_inventory") as InventoryModule
	inventory.restore_slots_snapshot([])
	inventory.set_capacity(24)
	inventory.add_item(ItemRegistry.get_instance().get_item("weapon_rifle"), 1)
	inventory.add_item(ItemRegistry.get_instance().get_item("item_health_potion"), 3)
	inventory.add_item(ItemRegistry.get_instance().get_item("weapon_pistol"), 1)
	ui.set_inventory_panel_open(true)
	await frames(30)
	check(ui.inventory_panel.position.x - ui.equipment_panel.get_rect().end.x >= 240, "central world gap")
	check(ui.inventory_panel.get_global_rect().end.x <= get_viewport().get_visible_rect().end.x, "right panel bounds")
	check(ui.close_button.get_global_rect().end.y <= get_viewport().get_visible_rect().end.y, "footer bounds")
	await capture("inventory_1280.png")
	if OS.get_environment("INVENTORY_QA_RENDER_ONLY") == "1":
		get_window().size = Vector2i(1920, 1080)
		await frames(15)
		await capture("inventory_1920.png")
		ui.set_inventory_panel_open(false)
		get_window().size = Vector2i(1280, 720)
		BaseManager.set_vault_items([ItemRegistry.get_instance().get_item("weapon_pistol"), ItemRegistry.get_instance().get_item("item_health_potion")])
		var storage := preload("res://scenes/VaultMenu.tscn").instantiate() as VaultMenu
		add_child(storage)
		storage.set_inventory_module(inventory)
		await frames(20)
		await capture("warehouse_1280.png")
		storage.queue_free()
		await frames(3)
		BaseManager.add_extraction_points(2000)
		var shop := preload("res://scenes/BaseVendingMenu.tscn").instantiate() as BaseVendingMenu
		add_child(shop)
		shop.set_inventory_module(inventory)
		shop._select_sell(4)
		await frames(20)
		await capture("vending_1280.png")
		print("INVENTORY_STORAGE_RENDER_OK")
		get_tree().quit(0)
		return
	ui.item_clicked.connect(func(index: int, _item: Dictionary) -> void: clicked = index)
	# Disconnect gameplay's click action for the hit-test assertion only.
	for connection in ui.item_clicked.get_connections():
		var callback: Callable = connection.callable
		if callback.get_object() != self:
			ui.item_clicked.disconnect(callback)
	var board := ui.inventory_grid as Control
	var tail := board.global_position + Vector2(175, 75)
	motion(tail)
	await frames(3)
	check(ui.item_hover_card.visible, "large item tail hover")
	mouse(tail, true)
	mouse(tail, false)
	await frames(2)
	check(clicked == 0, "large item tail click")
	mouse(tail, true)
	motion(tail + Vector2(12, 0), true)
	await frames(3)
	var target := board.global_position + Vector2(225, 75)
	motion(target, true)
	await frames(3)
	check(ui._drag_feedback_active, "large item tail starts native drag")
	await capture("inventory_drag.png")
	mouse(target, false)
	await frames(8)
	check(not inventory.get_slot(12).is_empty(), "native drag places at exact eight-column anchor")
	var before := JSON.stringify(inventory.get_slots_snapshot())
	var start := board.global_position + Vector2(375, 125)
	motion(start)
	await frames(2)
	mouse(start, true)
	motion(start + Vector2(12, 0), true)
	await frames(3)
	check(get_viewport().gui_is_dragging(), "second native drag active")
	key(KEY_R)
	await frames(2)
	check(ui._drag_rotation == 1, "R rotates ghost")
	key(KEY_ESCAPE)
	motion(board.global_position + Vector2(25, 25), true)
	await frames(2)
	mouse(board.global_position + Vector2(25, 25), false)
	await frames(3)
	check(JSON.stringify(inventory.get_slots_snapshot()) == before, "Esc cancels rotated drag without mutation")
	# Full-width weapon hit area also reaches the real equipment transaction.
	var weapon_id := str((inventory.get_slot(12).get("item", {}) as Dictionary).get("weapon_instance_id", ""))
	await drag_between(board.global_position + Vector2(375, 125), ui.equipment_weapon_slots[1].get_global_rect().get_center())
	check(str((ui.equipment_weapon_slots[1].get_meta("slot_item", {}) as Dictionary).get("weapon_instance_id", "")) == weapon_id, "native drag equips secondary weapon")
	await drag_between(ui.equipment_weapon_slots[1].get_global_rect().get_center(), board.global_position + Vector2(25, 25))
	check(inventory.find_weapon_instance_slot(weapon_id) == 0, "native drag unequips weapon to board")
	var before_sort := inventory.get_used_area()
	ui._on_sort_pressed()
	check(inventory.get_used_area() == before_sort and inventory.get_item_count("item_health_potion") == 3, "sort preserves area and stacks")
	var potion_slot := -1
	for entry in inventory.get_occupied_slots():
		if str(entry.item.id) == "item_health_potion":
			potion_slot = int(entry.slot)
	await drag_between(ui._slots[potion_slot].get_global_rect().get_center(), ui.quick_item_slots[0].get_global_rect().get_center())
	check(str((ui.quick_item_slots[0].get_meta("slot_item", {}) as Dictionary).get("id", "")) == "item_health_potion", "native quick assignment")
	var free_target := inventory.find_valid_placement(ItemRegistry.get_instance().get_item("item_health_potion"))
	var free_index := int(free_target.get("slot", -1))
	await drag_between(ui.quick_item_slots[0].get_global_rect().get_center(), board.global_position + board.call("get_cell_position", free_index) + Vector2(25, 25))
	check(inventory.get_item_count("item_health_potion") == 3, "native quick return preserves stack")
	await drag_between(ui._slots[free_index].get_global_rect().get_center(), ui._insurance_slots[1].get_global_rect().get_center())
	check(str((ui._insurance_slots[1].get_meta("slot_item", {}) as Dictionary).get("id", "")) == "item_health_potion", "native exact insurance slot")
	await drag_between(ui._insurance_slots[1].get_global_rect().get_center(), board.global_position + board.call("get_cell_position", free_index) + Vector2(25, 25))
	check(inventory.get_item_count("item_health_potion") == 3, "native insurance return preserves stack")
	check(ui.insurance_grid.columns == 8 and ui._insurance_slots.size() == 16, "insurance 8x2")
	check(ui.quick_item_slots[0].size == Vector2(50, 50), "quick slot shares grid size")
	check(absf(ui.inventory_panel.get_global_rect().position.y - (720 - ui.inventory_panel.get_global_rect().end.y)) <= 2, "equal vertical margins")
	check(dungeon.get("_inventory_close_button") == null, "single bottom close button")
	await drag_between(ui._slots[free_index].get_global_rect().get_center(), ui.drop_zone.get_global_rect().get_center())
	check(inventory.get_item_count("item_health_potion") == 0, "center world drop removes stack")
	inventory.set_capacity(72)
	await frames(8)
	ui.inventory_scroll.scroll_vertical = 300
	await frames(3)
	check(ui.inventory_scroll.scroll_vertical > 0, "expanded bag scrolls")
	check(ui.close_button.get_global_rect().end.y <= get_viewport().get_visible_rect().end.y, "expanded footer remains visible")
	inventory.set_capacity(24)
	ui.inventory_scroll.scroll_vertical = 0
	get_window().size = Vector2i(1920, 1080)
	await frames(20)
	await capture("inventory_1920.png")
	key(KEY_ESCAPE)
	await frames(2)
	check(not ui.is_inventory_open(), "Esc closes inventory")
	get_window().size = Vector2i(1280, 720)
	BaseManager.set_vault_items([])
	var vault := preload("res://scenes/VaultMenu.tscn").instantiate() as VaultMenu
	add_child(vault)
	vault.set_inventory_module(inventory)
	await frames(20)
	var warehouse_board: Control = vault._boards["vault"]
	var carried_board: Control = vault._boards["inventory"]
	var carried_rifle := inventory.find_weapon_instance_slot(weapon_id)
	await drag_between(carried_board.global_position + carried_board.get_cell_position(carried_rifle) + Vector2(175, 75), warehouse_board.global_position + Vector2(225, 25))
	check(inventory.find_weapon_instance_slot(weapon_id) == -1, "warehouse transfer removes source")
	var warehouse_model := BaseManager.get_storage_grid("vault")
	check(str(warehouse_model.get_slot(4).get("item", {}).get("weapon_instance_id", "")) == weapon_id, "warehouse drop preserves exact anchor")
	await drag_between(warehouse_board.global_position + Vector2(375, 75), warehouse_board.global_position + Vector2(25, 25))
	warehouse_model = BaseManager.get_storage_grid("vault")
	check(warehouse_model.find_weapon_instance_slot(weapon_id) == 0, "warehouse same-board placement persists")
	await capture("warehouse_1280.png")
	await drag_between(warehouse_board.global_position + Vector2(175, 75), carried_board.global_position + Vector2(225, 75))
	check(inventory.find_weapon_instance_slot(weapon_id) == 12, "warehouse return exact inventory anchor")
	check(BaseManager.get_vault_items().is_empty(), "warehouse transfer no duplicate")
	check(vault._boards["inventory"].columns == 8, "warehouse same eight-column board")
	vault.queue_free()
	await frames(3)
	BaseManager.add_extraction_points(2000)
	var vending := preload("res://scenes/BaseVendingMenu.tscn").instantiate() as BaseVendingMenu
	add_child(vending)
	vending.set_inventory_module(inventory)
	await frames(30)
	var close := vending.find_child("CloseButton", true, false) as Control
	check(close.get_global_rect().end.y <= 720 and close.is_visible_in_tree(), "vending close visible")
	var funds := BaseManager.get_extraction_points()
	vending._on_buy_pressed("item_health_potion")
	await frames(8)
	check(inventory.get_item_count("item_health_potion") == 1 and BaseManager.get_extraction_points() < funds, "vending purchase commits item and funds")
	var purchase_anchor := -1
	for entry in inventory.get_occupied_slots():
		if entry.item.id == "item_health_potion": purchase_anchor = int(entry.slot)
	vending._select_sell(purchase_anchor)
	await frames(3)
	await capture("vending_1280.png")
	var sell_button := vending._sell_actions.get_child(1) as Button
	var funds_before_sale := BaseManager.get_extraction_points()
	sell_button.pressed.emit()
	await frames(8)
	check(inventory.get_item_count("item_health_potion") == 0 and BaseManager.get_extraction_points() > funds_before_sale, "vending sale commits item and funds")
	vending._select_sell(12)
	await frames(2)
	if vending._sell_actions.get_child_count() > 1:
		var weapon_sell := vending._sell_actions.get_child(1) as Button
		weapon_sell.pressed.emit()
		check(inventory.find_weapon_instance_slot(weapon_id) == 12 and weapon_sell.get_meta("confirm_sell", false), "weapon sale requires second confirmation")
	else:
		check(false, "weapon sale selection exists")
	check(vending._sell_board.columns == 8, "vending same eight-column board")
	vending.queue_free()
	await frames(3)
	for failure in failures:
		push_error(failure)
	print("INVENTORY_EXPERIENCE_VISUAL_%s checks=%d" % ["OK" if failures.is_empty() else "FAIL", checks])
	get_tree().quit(0 if failures.is_empty() else 1)

func check(value: bool, label: String) -> void:
	checks += 1
	print("CHECK %s %s" % [label, value])
	if not value:
		failures.append(label)

func frames(count: int) -> void:
	for i in count:
		Input.warp_mouse(pointer)
		await get_tree().process_frame

func capture(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("INVENTORY_QA_OUTPUT")
	if output.is_empty():
		output = "user://inventory_qa"
	DirAccess.make_dir_recursive_absolute(output)
	check(get_viewport().get_texture().get_image().save_png(output.path_join(file)) == OK, file)

func motion(point: Vector2, held := false) -> void:
	pointer = point
	pointer_held = held
	Input.warp_mouse(point)
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = Vector2(12, 0)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(event)

func mouse(point: Vector2, pressed: bool) -> void:
	pointer = point
	pointer_held = pressed
	Input.warp_mouse(point)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	Input.parse_input_event(event)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventKey.new()
	event.keycode = code
	Input.parse_input_event(event)

func drag_between(start: Vector2, target: Vector2) -> void:
	motion(start)
	await frames(3)
	mouse(start, true)
	motion(start + Vector2(12, 0), true)
	await frames(3)
	motion(target, true)
	await frames(6)
	mouse(target, false)
	await frames(8)
