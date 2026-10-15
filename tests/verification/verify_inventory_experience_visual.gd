extends Node

var failures: Array[String] = []
var clicked := -1
var pointer := Vector2(640, 360)

func _ready() -> void:
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
	ui.item_clicked.connect(func(index: int, _item: Dictionary) -> void: clicked = index)
	# Disconnect gameplay's click action for the hit-test assertion only.
	for connection in ui.item_clicked.get_connections():
		var callback: Callable = connection.callable
		if callback.get_object() != self:
			ui.item_clicked.disconnect(callback)
	var board := ui.inventory_grid as Control
	var tail := board.global_position + Vector2(203, 87)
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
	var target := board.global_position + Vector2(29, 145)
	motion(target, true)
	await frames(3)
	check(ui._drag_feedback_active, "large item tail starts native drag")
	await capture("inventory_drag.png")
	mouse(target, false)
	await frames(8)
	check(not inventory.get_slot(12).is_empty(), "native drag places at row 3")
	var before := JSON.stringify(inventory.get_slots_snapshot())
	var start := board.global_position + Vector2(203, 203)
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
	motion(board.global_position + Vector2(29, 29), true)
	await frames(2)
	mouse(board.global_position + Vector2(29, 29), false)
	await frames(3)
	check(JSON.stringify(inventory.get_slots_snapshot()) == before, "Esc cancels rotated drag without mutation")
	# Full-width weapon hit area also reaches the real equipment transaction.
	var weapon_id := str((inventory.get_slot(12).get("item", {}) as Dictionary).get("weapon_instance_id", ""))
	await drag_between(board.global_position + Vector2(203, 203), ui.equipment_weapon_slots[1].get_global_rect().get_center())
	check(str((ui.equipment_weapon_slots[1].get_meta("slot_item", {}) as Dictionary).get("weapon_instance_id", "")) == weapon_id, "native drag equips secondary weapon")
	await drag_between(ui.equipment_weapon_slots[1].get_global_rect().get_center(), board.global_position + Vector2(29, 29))
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
	await drag_between(ui.quick_item_slots[0].get_global_rect().get_center(), board.global_position + board.call("get_cell_position", free_index) + Vector2(29, 29))
	check(inventory.get_item_count("item_health_potion") == 3, "native quick return preserves stack")
	await drag_between(ui._slots[free_index].get_global_rect().get_center(), ui._insurance_slots[1].get_global_rect().get_center())
	check(str((ui._insurance_slots[1].get_meta("slot_item", {}) as Dictionary).get("id", "")) == "item_health_potion", "native exact insurance slot")
	await drag_between(ui._insurance_slots[1].get_global_rect().get_center(), board.global_position + board.call("get_cell_position", free_index) + Vector2(29, 29))
	check(inventory.get_item_count("item_health_potion") == 3, "native insurance return preserves stack")
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
	for failure in failures:
		push_error(failure)
	print("INVENTORY_EXPERIENCE_VISUAL_%s checks=23" % ("OK" if failures.is_empty() else "FAIL"))
	get_tree().quit(0 if failures.is_empty() else 1)

func check(value: bool, label: String) -> void:
	print("CHECK %s %s" % [label, value])
	if not value:
		failures.append(label)

func frames(count: int) -> void:
	for i in count:
		Input.warp_mouse(pointer)
		await get_tree().process_frame

func capture(file: String) -> void:
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("INVENTORY_QA_OUTPUT")
	if output.is_empty():
		output = "user://inventory_qa"
	DirAccess.make_dir_recursive_absolute(output)
	check(get_viewport().get_texture().get_image().save_png(output.path_join(file)) == OK, file)

func motion(point: Vector2, held := false) -> void:
	pointer = point
	Input.warp_mouse(point)
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = Vector2(12, 0)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(event)

func mouse(point: Vector2, pressed: bool) -> void:
	pointer = point
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
