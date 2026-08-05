extends Node

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")
const OUTPUT_DIR := "res://outputs/verification"


func _ready() -> void:
	var capture_ok := true
	var interaction_ok := true
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	for _frame in 6:
		await get_tree().process_frame
	var ui := dungeon.get("_inventory_ui") as InventoryUI
	var inventory := dungeon.get("_inventory") as InventoryModule
	var weapon := WeaponInstance.from_item(ItemRegistry.get_instance().get_item("weapon_rifle"))
	weapon.fate_upgrades = [
		{"slot_index": 1, "stable_card_id": "fate_overclock", "effect_version": 1},
		{"slot_index": 2, "stable_card_id": "fate_chain_lightning", "effect_version": 1},
		{"slot_index": 3, "stable_card_id": "fate_fuse_fire", "effect_version": 1},
	]
	inventory.add_item(weapon.to_item_dictionary(), 1)
	inventory.add_item(ItemRegistry.get_instance().get_item("item_health_potion"), 2)
	inventory.add_item(ItemRegistry.get_instance().get_item("attach_big_mag"), 1)
	ui.set_inventory_panel_open(true)
	for _frame in 4:
		await get_tree().process_frame
	capture_ok = _capture("tactical_inventory_ui.png") and capture_ok

	var weapon_slot_index := inventory.find_weapon_instance_slot(weapon.weapon_instance_id)
	var weapon_slot := ui._slots[weapon_slot_index] as Control if weapon_slot_index >= 0 else null
	if weapon_slot == null:
		interaction_ok = false
	else:
		var hover_position := weapon_slot.global_position + weapon_slot.size * 0.5
		Input.warp_mouse(hover_position)
		_send_hover_motion(hover_position)
		await get_tree().process_frame
		await get_tree().process_frame
		var hover_visible := ui.item_hover_card != null and ui.item_hover_card.visible
		var hover_single := ui.find_children("ItemHoverCard", "PanelContainer", true, false).size() == 1
		var hover_clear := weapon_slot.tooltip_text.is_empty() and not ui.item_hover_card.get_global_rect().intersects(weapon_slot.get_global_rect())
		interaction_ok = hover_visible and hover_single and hover_clear
		capture_ok = _capture("tactical_weapon_hover.png") and capture_ok

		var target_index := 10
		var target_slot := ui._slots[target_index] as Control
		var target_position := target_slot.global_position + target_slot.size * 0.5
		_send_mouse_button(hover_position, true)
		await get_tree().process_frame
		_send_mouse_motion(hover_position.lerp(target_position, 0.5), target_position - hover_position)
		await get_tree().process_frame
		_send_mouse_motion(target_position, target_position - hover_position)
		await get_tree().process_frame
		var drag_visible := ui.drag_status_panel != null and ui.drag_status_panel.visible
		interaction_ok = interaction_ok and drag_visible
		capture_ok = _capture("tactical_inventory_drag.png") and capture_ok
		_send_mouse_button(target_position, false)
		await get_tree().process_frame
		await get_tree().process_frame
		var moved_item := inventory.get_slot(target_index).get("item", {}) as Dictionary
		var moved_ok := str(moved_item.get("weapon_instance_id", "")) == weapon.weapon_instance_id
		interaction_ok = interaction_ok and moved_ok

		var equipped_position := ui.equipment_weapon_slot.global_position + ui.equipment_weapon_slot.size * 0.5
		_send_mouse_button(target_position, true)
		await get_tree().process_frame
		_send_mouse_motion(target_position.lerp(equipped_position, 0.5), equipped_position - target_position)
		await get_tree().process_frame
		_send_mouse_motion(equipped_position, equipped_position - target_position)
		await get_tree().process_frame
		capture_ok = _capture("tactical_weapon_equip_drag.png") and capture_ok
		_send_mouse_button(equipped_position, false)
		await get_tree().process_frame
		await get_tree().process_frame
		var equip_ok := dungeon.player.get_equipped_weapon_instance_id() == weapon.weapon_instance_id
		interaction_ok = interaction_ok and equip_ok

		var unequip_target_index := 9
		var unequip_target_slot := ui._slots[unequip_target_index] as Control
		var unequip_start := ui.equipment_weapon_slot.global_position + ui.equipment_weapon_slot.size * 0.5
		var unequip_target := unequip_target_slot.global_position + unequip_target_slot.size * 0.5
		_send_mouse_button(unequip_start, true)
		await get_tree().process_frame
		_send_mouse_motion(unequip_start.lerp(unequip_target, 0.5), unequip_target - unequip_start)
		await get_tree().process_frame
		_send_mouse_motion(unequip_target, unequip_target - unequip_start)
		await get_tree().process_frame
		capture_ok = _capture("tactical_weapon_unequip_drag.png") and capture_ok
		_send_mouse_button(unequip_target, false)
		await get_tree().process_frame
		await get_tree().process_frame
		var unequipped_item := inventory.get_slot(unequip_target_index).get("item", {}) as Dictionary
		var unequip_ok := dungeon.player.get_equipped_weapon_instance_id().is_empty() and str(unequipped_item.get("weapon_instance_id", "")) == weapon.weapon_instance_id
		interaction_ok = interaction_ok and unequip_ok

		var discard_slot_index := _find_item_slot(inventory, "attach_big_mag")
		var discard_ok := discard_slot_index >= 0
		if discard_ok:
			var discard_slot := ui._slots[discard_slot_index] as Control
			var discard_start := discard_slot.global_position + discard_slot.size * 0.5
			var discard_target := ui.drop_zone.global_position + ui.drop_zone.size * 0.5
			var ground_before := get_tree().get_nodes_in_group("ground_loot_3d").size()
			_send_mouse_button(discard_start, true)
			await get_tree().process_frame
			_send_mouse_motion(discard_start.lerp(discard_target, 0.5), discard_target - discard_start)
			await get_tree().process_frame
			_send_mouse_motion(discard_target, discard_target - discard_start)
			await get_tree().process_frame
			capture_ok = _capture("tactical_item_discard_drag.png") and capture_ok
			_send_mouse_button(discard_target, false)
			await get_tree().process_frame
			await get_tree().process_frame
			discard_ok = not inventory.has_item("attach_big_mag") and get_tree().get_nodes_in_group("ground_loot_3d").size() == ground_before + 1
		interaction_ok = interaction_ok and discard_ok
		if not interaction_ok:
			print("TACTICAL_INTERACTION_DEBUG hover=%s single=%s clear=%s drag=%s move=%s equip=%s unequip=%s discard=%s source=%d target=%d" % [hover_visible, hover_single, hover_clear, drag_visible, moved_ok, equip_ok, unequip_ok, discard_ok, weapon_slot_index, target_index])

	ui.set_inventory_panel_open(false)
	dungeon.force_enter_room_for_test("main_01")
	for _frame in 8:
		await get_tree().process_frame
	capture_ok = _capture("tactical_minimap_hud.png") and capture_ok
	if not capture_ok or not interaction_ok:
		push_error("TACTICAL_INVENTORY_MINIMAP_VISUAL_FAIL: real hover/drag interaction or viewport capture failed")
		get_tree().quit(1)
		return
	print("TACTICAL_INVENTORY_MINIMAP_VISUAL_OK: single non-overlap hover card, slot move, weapon equip/unequip, world discard and minimap render pass")
	get_tree().quit(0)


func _capture(file_name: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return false
	return image.save_png("%s/%s" % [OUTPUT_DIR, file_name]) == OK


func _send_mouse_button(position: Vector2, pressed: bool) -> void:
	Input.warp_mouse(position)
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	Input.parse_input_event(event)


func _send_mouse_motion(position: Vector2, relative: Vector2) -> void:
	Input.warp_mouse(position)
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)


func _send_hover_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = Vector2.ZERO
	event.button_mask = 0
	Input.parse_input_event(event)


func _find_item_slot(inventory: InventoryModule, item_id: String) -> int:
	for entry in inventory.get_occupied_slots():
		if str((entry.get("item", {}) as Dictionary).get("id", "")) == item_id:
			return int(entry.get("slot", -1))
	return -1
