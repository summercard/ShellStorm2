extends Node

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 120034
	add_child(dungeon)
	for _frame in 5:
		await get_tree().process_frame
	var player := dungeon.player
	var inventory := dungeon.get_inventory_module()
	var ui := dungeon.get("_inventory_ui") as InventoryUI
	_expect(player != null and inventory != null and ui != null, "Dungeon combat UI did not initialize", failures)
	if player == null or inventory == null or ui == null:
		_finish(failures)
		return

	# Real input contract: I/Tab must toggle the tactical inventory exactly once,
	# and opening/closing must lock/unlock player control in the same frame chain.
	_expect(not ui.is_inventory_open(), "Inventory unexpectedly starts open", failures)
	await _press_key(KEY_I)
	_expect(ui.is_inventory_open(), "Physical I key did not open tactical inventory", failures)
	_expect(player.input_locked, "Opening inventory did not lock player input", failures)
	await _send_key_echo(KEY_I)
	_expect(ui.is_inventory_open(), "Held I key echo closed tactical inventory", failures)
	await _press_key(KEY_I)
	_expect(not ui.is_inventory_open(), "Second physical I key did not close tactical inventory", failures)
	_expect(not player.input_locked, "Closing inventory did not restore player input", failures)
	await _press_key(KEY_TAB)
	_expect(ui.is_inventory_open(), "Tab did not open tactical inventory", failures)
	await _press_key(KEY_TAB)
	_expect(not ui.is_inventory_open(), "Second Tab did not close tactical inventory", failures)

	# Two unique WeaponInstance slots; slot 2 is stowed on the avatar back.
	var primary_id := player.get_equipped_weapon_instance_id_for_slot(0)
	var shotgun := ItemRegistry.get_instance().get_item("weapon_shotgun")
	_expect(inventory.add_item(shotgun, 1) == 1, "Cannot seed secondary weapon", failures)
	var shotgun_slot := _find_slot(inventory, "weapon_shotgun")
	dungeon.call("_on_weapon_slot_equip_requested", shotgun_slot, 1)
	var secondary_id := player.get_equipped_weapon_instance_id_for_slot(1)
	_expect(not primary_id.is_empty() and not secondary_id.is_empty() and primary_id != secondary_id, "Primary/secondary weapon instances are not independent", failures)
	_expect(player.get_active_weapon_slot() == 0, "Equipping secondary weapon changed active slot", failures)
	var loadout := player.get_weapon_loadout_snapshot()
	_expect(bool(loadout.get("stowed_visible", false)), "Secondary weapon is not visible on avatar back", failures)
	_expect(int(loadout.get("stowed_slot", -1)) == 1, "Secondary weapon is not assigned to the right back socket", failures)
	_expect(str(loadout.get("stowed_socket_name", "")) == "StowedWeaponSocketSecondary", "Secondary weapon uses the wrong semantic back socket", failures)
	_expect((loadout.get("stowed_socket_position", Vector3.ZERO) as Vector3).x > 0.0, "Secondary weapon back socket is not on the avatar right", failures)
	_expect((loadout.get("stowed_muzzle_direction", Vector3.ZERO) as Vector3).dot(Vector3.DOWN) > 0.99, "Secondary weapon muzzle does not point down", failures)
	_expect(bool(dungeon.call("_select_weapon_slot", 1)), "Key-2 weapon switch contract failed", failures)
	_expect(player.get_active_weapon_slot() == 1 and str(player.get_weapon_snapshot().get("gun_id", "")) == "bp_shotgun", "Secondary weapon did not become the active runtime tree", failures)
	loadout = player.get_weapon_loadout_snapshot()
	_expect(int(loadout.get("stowed_slot", -1)) == 0, "Primary weapon is not assigned to the left back socket", failures)
	_expect(str(loadout.get("stowed_socket_name", "")) == "StowedWeaponSocketPrimary", "Primary weapon uses the wrong semantic back socket", failures)
	_expect((loadout.get("stowed_socket_position", Vector3.ZERO) as Vector3).x < 0.0, "Primary weapon back socket is not on the avatar left", failures)
	_expect((loadout.get("stowed_muzzle_direction", Vector3.ZERO) as Vector3).dot(Vector3.DOWN) > 0.99, "Primary weapon muzzle does not point down", failures)
	_expect(bool(dungeon.call("_select_weapon_slot", 0)), "Key-1 weapon switch contract failed", failures)
	_expect(player.get_equipped_weapon_instance_id_for_slot(1) == secondary_id, "Weapon switch rebuilt or lost secondary instance", failures)

	# Quick slots bind stable item IDs and consume only after a successful effect.
	var potion := ItemRegistry.get_instance().get_item("item_health_potion")
	_expect(inventory.add_item(potion, 2) == 2, "Cannot seed quick-use potion", failures)
	dungeon.call("_on_quick_item_assignment_requested", 0, "item_health_potion")
	player.current_hp = 40
	player.hp_changed.emit(player.current_hp, player.max_hp)
	var potion_before := inventory.get_item_count("item_health_potion")
	_expect(bool(dungeon.call("_use_quick_item", 0)), "Quick slot 3 did not use the bound potion", failures)
	_expect(player.current_hp > 40 and inventory.get_item_count("item_health_potion") == potion_before - 1, "Quick item effect/count transaction is not atomic", failures)
	ui.set_inventory_panel_open(true)
	await get_tree().process_frame
	_expect(ui.quick_item_slots.size() == 2 and (dungeon.get("_hud_quick_item_icons") as Array).size() == 2, "Inventory/HUD quick slots are incomplete", failures)
	ui.set_inventory_panel_open(false)

	# M opens a full-floor explored map while the tactical radar remains separate.
	dungeon.call("_toggle_full_map")
	await get_tree().process_frame
	var full_map := dungeon.get("_full_map_control") as DungeonMinimap3D
	_expect(full_map != null and bool(full_map.get_snapshot().get("full_map_mode", false)), "M full-floor map did not open in full map mode", failures)
	if full_map != null:
		_expect(int(full_map.get_snapshot().get("revealed_count", 0)) >= 1, "Full map lost explored-room state", failures)
	dungeon.call("_close_full_map")
	_expect(dungeon.get("_full_map_control") == null, "Full map did not close", failures)

	# A full weapon fate card requires a second click to convert to currency.
	var instance := player.get_equipped_weapon_instance()
	instance.fate_upgrades.clear()
	for index in range(instance.fate_slot_capacity):
		instance.fate_upgrades.append({
			"slot_index": index + 1,
			"stable_card_id": "verification_full_%02d" % index,
			"effect_version": 1,
		})
	_expect(dungeon.show_reference_fate_overlay_for_test(), "Cannot open reference fate selection", failures)
	var currency_before := GameManager.currency
	dungeon.call("_on_door_fate_selected", 0)
	_expect(bool(dungeon.get("_door_fate_active")) and GameManager.currency == currency_before, "First full-slot click converted without confirmation", failures)
	dungeon.call("_on_door_fate_selected", 0)
	_expect(not bool(dungeon.get("_door_fate_active")) and GameManager.currency > currency_before, "Second full-slot click did not convert card to currency", failures)
	_expect(dungeon.show_reference_fate_overlay_for_test(), "Cannot reopen fate selection for ESC contract", failures)
	dungeon.call("_cancel_door_fate_selection")
	_expect(not bool(dungeon.get("_door_fate_active")), "ESC fate cancellation contract did not close selection", failures)

	var weapon_panel := dungeon.get("_weapon_panel") as WeaponAssemblyTreePanel
	_expect(weapon_panel != null and is_equal_approx(weapon_panel.anchor_left, 0.5) and weapon_panel.position.x <= -250.0, "K weapon presentation page is not centered", failures)

	dungeon.queue_free()
	_finish(failures)


func _find_slot(inventory: InventoryModule, item_id: String) -> int:
	for entry in inventory.get_occupied_slots():
		if str((entry.get("item", {}) as Dictionary).get("id", "")) == item_id:
			return int(entry.get("slot", -1))
	return -1


func _press_key(keycode: Key) -> void:
	var pressed := InputEventKey.new()
	pressed.keycode = keycode
	pressed.physical_keycode = keycode
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await get_tree().process_frame
	var released := InputEventKey.new()
	released.keycode = keycode
	released.physical_keycode = keycode
	released.pressed = false
	Input.parse_input_event(released)
	await get_tree().process_frame


func _send_key_echo(keycode: Key) -> void:
	var repeated := InputEventKey.new()
	repeated.keycode = keycode
	repeated.physical_keycode = keycode
	repeated.pressed = true
	repeated.echo = true
	Input.parse_input_event(repeated)
	await get_tree().process_frame


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("DUAL_WEAPON_QUICK_MAP_FATE_OK: two weapon instances, back stow, 1/2 switch, quick 3/4 items, full map, ESC and full-slot currency conversion pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
