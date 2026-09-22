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

	# Quick slots own the moved item stack and consume only after a successful effect.
	var potion := ItemRegistry.get_instance().get_item("item_health_potion")
	_expect(inventory.add_item(potion, 2) == 2, "Cannot seed quick-use potion", failures)
	dungeon.call("_on_quick_item_assignment_requested", 0, "item_health_potion")
	var quick_inventory := dungeon.get("_quick_inventory") as InventoryModule
	_expect(
		quick_inventory != null
		and quick_inventory.get_item_count("item_health_potion") == 2
		and inventory.get_item_count("item_health_potion") == 0,
		"Quick assignment did not move the real stack out of backpack", failures
	)
	player.current_hp = 40
	player.hp_changed.emit(player.current_hp, player.max_hp)
	var potion_before := quick_inventory.get_item_count("item_health_potion")
	_expect(bool(dungeon.call("_use_quick_item", 0)), "Quick slot 3 did not use the bound potion", failures)
	_expect(player.current_hp > 40 and quick_inventory.get_item_count("item_health_potion") == potion_before - 1, "Quick item effect/count transaction is not atomic", failures)
	player.current_hp = player.max_hp
	player.hp_changed.emit(player.current_hp, player.max_hp)
	var potion_before_rejected_use := quick_inventory.get_item_count("item_health_potion")
	_expect(not bool(dungeon.call("_use_quick_item", 0)), "Full-health quick potion was incorrectly accepted", failures)
	_expect(
		quick_inventory.get_item_count("item_health_potion") == potion_before_rejected_use,
		"Rejected quick-item effect still consumed an item", failures
	)
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

	# 手柄可操控契约：命运卡三选一是**代码构造**的覆盖层，不在 UiMenuFocus 那批静态
	# 场景菜单里，因此它必须自己抓默认焦点 —— 否则手柄的十字键/左摇杆（ui_*）与 A 键
	# （ui_accept）都不会被派发，表现为「命运卡界面手柄完全不能操控」。
	# 焦点必须在翻转动画结束、卡片解除 disabled 之后才抓得到（禁用按钮不可聚焦）。
	await _wait_fate_cards_flipped(dungeon, failures)
	var fate_overlay := dungeon.get_node_or_null("HUD/DoorFateOverlay3D") as Control
	var focus_owner := get_viewport().gui_get_focus_owner()
	_expect(fate_overlay != null, "Fate overlay node is missing for the gamepad focus contract", failures)
	_expect(
		focus_owner != null,
		"Fate overlay has no gui focus owner: gamepad ui_left/right and ui_accept are never dispatched",
		failures
	)
	_expect(
		focus_owner != null and fate_overlay != null and fate_overlay.is_ancestor_of(focus_owner),
		"Fate overlay focus owner lives outside the overlay",
		failures
	)
	_expect(
		focus_owner != null and String(focus_owner.name).begins_with("FateChoiceCard_"),
		"Fate overlay focus owner is not one of the three tarot cards",
		failures
	)
	if focus_owner is Control:
		var focus_card := focus_owner as Control
		_expect(
			not focus_card.focus_neighbor_left.is_empty(),
			"Fate card has no left focus neighbour: gamepad cannot cycle between cards",
			failures
		)
		_expect(
			not focus_card.focus_neighbor_right.is_empty(),
			"Fate card has no right focus neighbour: gamepad cannot cycle between cards",
			failures
		)
	# 手柄 B 与键盘 ESC 共用 ui_cancel：合成该 action 必须能放弃。
	# 这条同时盯住「硬比 KEY_ESCAPE」——改成硬比后合成 action 不再命中，本条即红。
	var cancel_event := InputEventAction.new()
	cancel_event.action = "ui_cancel"
	cancel_event.pressed = true
	cancel_event.strength = 1.0
	Input.parse_input_event(cancel_event)
	Input.flush_buffered_events()
	await get_tree().process_frame
	_expect(
		not bool(dungeon.get("_door_fate_active")),
		"ui_cancel did not cancel the fate selection: gamepad B cannot dismiss the overlay",
		failures
	)

	# 函数级取消契约（键盘 ESC 与本条走同一入口，保留原断言）。
	_expect(dungeon.show_reference_fate_overlay_for_test(), "Cannot reopen fate selection for cancellation contract", failures)
	dungeon.call("_cancel_door_fate_selection")
	_expect(not bool(dungeon.get("_door_fate_active")), "ESC fate cancellation contract did not close selection", failures)

	_expect(dungeon.get("_weapon_panel") == null, "Hidden weapon presentation page was eagerly added to the fixed HUD shell", failures)
	await _press_key(KEY_K)
	var weapon_panel := dungeon.get("_weapon_panel") as WeaponAssemblyTreePanel
	var viewport_center := Vector2(dungeon.get_viewport().get_visible_rect().size) * 0.5
	_expect(
		weapon_panel != null
		and weapon_panel.visible
		and is_equal_approx(weapon_panel.anchor_left, 0.5)
		and weapon_panel.get_global_rect().get_center().distance_to(viewport_center) <= 1.0,
		"K weapon presentation page is not centered",
		failures
	)

	dungeon.queue_free()
	_finish(failures)


func _find_slot(inventory: InventoryModule, item_id: String) -> int:
	for entry in inventory.get_occupied_slots():
		if str((entry.get("item", {}) as Dictionary).get("id", "")) == item_id:
			return int(entry.get("slot", -1))
	return -1


## 等三张命运卡的翻转动画全部结束（等价于 `_finish_reference_tarot_flip` 已对每张执行）。
## 必须按**真实时间**轮询而不是固定帧数：headless 下 process 帧不做垂直同步，
## 固定帧数可能只累积极短的真实 delta，tween 根本走不完（带窗口跑时帧数才够用）。
func _wait_fate_cards_flipped(dungeon: Node, failures: Array[String]) -> void:
	var deadline_ms := 6000
	var elapsed_ms := 0
	while elapsed_ms < deadline_ms:
		var overlay := dungeon.get_node_or_null("HUD/DoorFateOverlay3D") as Control
		if overlay != null and _fate_cards_flipped(overlay):
			return
		await get_tree().create_timer(0.05).timeout
		elapsed_ms += 50
	failures.append("Fate cards did not finish flipping within %d ms" % deadline_ms)


## 三张卡是否都已翻面（可见面就绪且已解除 disabled）。
func _fate_cards_flipped(overlay: Control) -> bool:
	if overlay == null or not is_instance_valid(overlay):
		return false
	var cards := overlay.find_children("FateChoiceCard_*", "Button", true, false)
	if cards.size() != 3:
		return false
	for card_node in cards:
		var card := card_node as Button
		if card.disabled or not bool(card.get_meta("tarot_face_ready", false)):
			return false
	return true


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
		print("DUAL_WEAPON_QUICK_MAP_FATE_OK: two weapon instances, back stow, 1/2 switch, quick 3/4 items, full map, the fate overlay hands gamepad focus to a card with left/right neighbours and ui_cancel dismisses it, and full-slot currency conversion passes")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
