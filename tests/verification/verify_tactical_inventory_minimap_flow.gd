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
	var insurance := dungeon.get("_insurance") as InsuranceModule
	var quick_inventory := dungeon.get("_quick_inventory") as InventoryModule
	_check(ui != null and inventory != null and insurance != null and quick_inventory != null, "Formal dungeon did not create tactical inventory/insurance/quick UI", failures)
	if ui == null or inventory == null or insurance == null or quick_inventory == null:
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
	_verify_ui_slot_index_contract(ui, failures)

	# 真实玩家存档的小型电池位于第二保险格。这里不直接调
	# Dungeon3D移动函数，而是使用真实ItemSlot保存的索引、
	# drag_payload、_can_drop_data和_drop_data信号链，防止UI索引错误再被绕过。
	var real_slot_battery := ItemRegistry.get_instance().get_item("item_battery_s")
	_check(inventory.add_item(real_slot_battery, 1) == 1, "Cannot seed real-slot battery", failures)
	var real_slot_source := _find_item_slot(inventory, "item_battery_s")
	_check(
		insurance.insure_item_to_slot(inventory, real_slot_source, 1),
		"Cannot seed small battery into insurance slot 1", failures
	)
	await get_tree().process_frame
	var real_slot_target := _find_empty_slot(inventory)
	_check(
		int(ui._insurance_slots[1].get("slot_index")) == 1,
		"Insurance slot 1 UI was rewritten to slot 0 during refresh", failures
	)
	_check(
		_drag_between_real_slots(ui._insurance_slots[1], ui._slots[real_slot_target]),
		"Real insurance-slot-1 drag is rejected by the backpack target", failures
	)
	_check(
		insurance.get_slots_snapshot()[1].is_empty()
		and str((inventory.get_slot(real_slot_target).get("item", {}) as Dictionary).get("id", "")) == "item_battery_s",
		"Small battery did not leave real insurance slot 1 for the selected backpack slot", failures
	)
	_check(
		_drag_between_real_slots(ui._slots[real_slot_target], ui._insurance_slots[1]),
		"Small battery could not be returned to real insurance slot 1", failures
	)
	ui._insurance_slots[1].emit_signal(
		"slot_right_clicked", int(ui._insurance_slots[1].get("slot_index"))
	)
	_check(
		insurance.get_slots_snapshot()[1].is_empty() and inventory.has_item("item_battery_s"),
		"Right-click on real insurance slot 1 did not return the small battery", failures
	)
	var real_slot_cleanup := _find_item_slot(inventory, "item_battery_s")
	if real_slot_cleanup >= 0:
		inventory.clear_slot(real_slot_cleanup)

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

	var insured_item := ItemRegistry.get_instance().get_item("item_battery_l")
	_check(inventory.add_item(insured_item, 1) == 1, "Cannot seed insurance drag item", failures)
	var insured_source_slot := _find_item_slot(inventory, "item_battery_l")
	await get_tree().process_frame
	var inventory_to_insurance := {
		"inventory_drag": true,
		"source_index": insured_source_slot,
		"source_kind": "inventory",
		"item": insured_item,
	}
	_check(
		insured_source_slot >= 0
		and not ui._insurance_slots.is_empty()
		and bool(ui._insurance_slots[0].call("_can_drop_data", Vector2.ZERO, inventory_to_insurance)),
		"Empty insurance slot rejects backpack drag", failures
	)
	_check(
		_drag_between_real_slots(ui._slots[insured_source_slot], ui._insurance_slots[0]),
		"Real backpack-to-insurance drag signal was rejected", failures
	)
	_check(insurance.has_item("item_battery_l") and not inventory.has_item("item_battery_l"), "Backpack drag did not transfer ownership into insurance", failures)

	var insurance_to_inventory := {
		"inventory_drag": true,
		"source_index": 0,
		"source_kind": "insurance",
		"item": insured_item,
	}
	var empty_inventory_slot := _find_empty_slot(inventory)
	_check(
		empty_inventory_slot >= 0
		and bool(ui._slots[empty_inventory_slot].call("_can_drop_data", Vector2.ZERO, insurance_to_inventory)),
		"Empty backpack slot rejects insurance-item return drag", failures
	)
	_check(
		_drag_between_real_slots(ui._insurance_slots[0], ui._slots[empty_inventory_slot]),
		"Real insurance-to-backpack drag signal was rejected", failures
	)
	_check(not insurance.has_item("item_battery_l") and inventory.has_item("item_battery_l"), "Insurance return drag lost or duplicated ownership", failures)

	var battery_slot := _find_item_slot(inventory, "item_battery_l")
	_check(insurance.insure_item(inventory, battery_slot), "Cannot return battery to insurance for world-drop routing", failures)
	var insured_battery_payload := {
		"inventory_drag": true,
		"source_index": 0,
		"source_kind": "insurance",
		"item": insured_item,
	}
	var insurance_drop_room := _get_current_room(dungeon)
	var insurance_pickups_before := insurance_drop_room.find_children("*", "GroundLootPickup3D", true, false).size()
	_check(
		bool(ui.drop_zone.call("_can_drop_data", Vector2.ZERO, insured_battery_payload)),
		"Insurance item is incorrectly blocked from the world-drop zone", failures
	)
	ui.call("_on_slot_drop_received", 0, -1, "insurance", "drop")
	await get_tree().process_frame
	var insurance_pickups_after := insurance_drop_room.find_children("*", "GroundLootPickup3D", true, false).size()
	_check(
		not insurance.has_item("item_battery_l") and insurance_pickups_after == insurance_pickups_before + 1,
		"Insurance item was not voluntarily moved into the current-room world drop", failures
	)

	var insured_weapon := ItemRegistry.get_instance().get_item("weapon_shotgun")
	_check(insurance.insure_item_direct(insured_weapon), "Cannot seed insured weapon for equipment routing", failures)
	var insured_weapon_entry := insurance.get_slots_snapshot()[0] as Dictionary
	var insured_weapon_item := insured_weapon_entry.get("item", {}) as Dictionary
	var insured_weapon_payload := {
		"inventory_drag": true,
		"source_index": 0,
		"source_kind": "insurance",
		"item": insured_weapon_item,
	}
	_check(
		bool(ui.equipment_weapon_slots[1].call("_can_drop_data", Vector2.ZERO, insured_weapon_payload)),
		"Compatible insured weapon is blocked from the equipment slot", failures
	)
	_check(
		_drag_between_real_slots(ui._insurance_slots[0], ui.equipment_weapon_slots[1]),
		"Real insurance-to-secondary-weapon drag signal was rejected", failures
	)
	var equipped_secondary := dungeon.player.get_equipped_weapon_instance_for_slot(1)
	_check(
		equipped_secondary != null
		and equipped_secondary.weapon_instance_id == str(insured_weapon_item.get("weapon_instance_id", ""))
		and insurance.get_used_slots() == 0,
		"Insured weapon did not move into the requested equipment slot", failures
	)

	var insured_quick_item := ItemRegistry.get_instance().get_item("item_health_potion")
	_check(insurance.insure_item_direct(insured_quick_item), "Cannot seed insured quick item", failures)
	var insured_quick_payload := {
		"inventory_drag": true,
		"source_index": 0,
		"source_kind": "insurance",
		"item": insured_quick_item,
	}
	_check(
		bool(ui.quick_item_slots[0].call("_can_drop_data", Vector2.ZERO, insured_quick_payload)),
		"Usable insured item is blocked from the quick slot", failures
	)
	_check(
		_drag_between_real_slots(ui._insurance_slots[0], ui.quick_item_slots[0]),
		"Real insurance-to-quick drag signal was rejected", failures
	)
	_check(
		str((quick_inventory.get_slot(0).get("item", {}) as Dictionary).get("id", "")) == "item_health_potion"
		and not inventory.has_item("item_health_potion")
		and str((dungeon.get("_quick_item_ids") as Array)[0]) == "item_health_potion"
		and insurance.get_used_slots() == 0,
		"Insured usable item did not move into the exact quick slot", failures
	)
	dungeon.player.current_hp = 40
	dungeon.player.hp_changed.emit(40, dungeon.player.max_hp)
	ui.quick_item_slots[0].emit_signal("slot_clicked", 0)
	_check(
		dungeon.player.current_hp > 40 and quick_inventory.get_slot(0).is_empty(),
		"Clicking the inventory quick slot did not apply and consume its real item", failures
	)

	var quick_return_item := ItemRegistry.get_instance().get_item("item_battery_s")
	_check(inventory.add_item(quick_return_item, 2) == 2, "Cannot seed quick return item", failures)
	var quick_return_source := _find_item_slot(inventory, "item_battery_s")
	_check(
		_drag_between_real_slots(ui._slots[quick_return_source], ui.quick_item_slots[1]),
		"Real backpack-to-quick drag signal was rejected", failures
	)
	_check(
		str((quick_inventory.get_slot(1).get("item", {}) as Dictionary).get("id", "")) == "item_battery_s"
		and int(quick_inventory.get_slot(1).get("count", 0)) == 2
		and not inventory.has_item("item_battery_s"),
		"Inventory item landed in the wrong quick slot or remained duplicated in backpack", failures
	)
	var quick_return_target := _find_empty_slot(inventory)
	var quick_return_payload := {
		"inventory_drag": true,
		"source_index": 1,
		"source_kind": "quick_1",
		"item": quick_return_item,
	}
	_check(
		bool(ui._slots[quick_return_target].call("_can_drop_data", Vector2.ZERO, quick_return_payload)),
		"Quick item cannot be dragged back to an empty backpack slot", failures
	)
	_check(
		_drag_between_real_slots(ui.quick_item_slots[1], ui._slots[quick_return_target]),
		"Real quick-to-backpack drag signal was rejected", failures
	)
	_check(
		quick_inventory.get_slot(1).is_empty()
		and str((inventory.get_slot(quick_return_target).get("item", {}) as Dictionary).get("id", "")) == "item_battery_s"
		and int(inventory.get_slot(quick_return_target).get("count", 0)) == 2,
		"Quick item did not return to the requested backpack position with its full count", failures
	)

	_check(
		_drag_between_real_slots(ui._slots[quick_return_target], ui.quick_item_slots[1]),
		"Real backpack-to-quick return drag signal was rejected", failures
	)
	var quick_to_insurance_payload := {
		"inventory_drag": true,
		"source_index": 1,
		"source_kind": "quick_1",
		"item": quick_return_item,
	}
	_check(
		bool(ui._insurance_slots[0].call("_can_drop_data", Vector2.ZERO, quick_to_insurance_payload)),
		"Quick item cannot move into an empty insurance slot", failures
	)
	_check(
		_drag_between_real_slots(ui.quick_item_slots[1], ui._insurance_slots[0]),
		"Real quick-to-insurance drag signal was rejected", failures
	)
	_check(
		quick_inventory.get_slot(1).is_empty()
		and insurance.has_item("item_battery_s"),
		"Quick item did not move into insurance with unique ownership", failures
	)
	_check(
		_drag_between_real_slots(ui._insurance_slots[0], ui.quick_item_slots[0]),
		"Real insurance-to-quick return drag signal was rejected", failures
	)
	var quick_drop_room := _get_current_room(dungeon)
	var quick_drop_before := quick_drop_room.find_children("*", "GroundLootPickup3D", true, false).size()
	_check(
		_drag_between_real_slots(ui.quick_item_slots[0], ui.drop_zone),
		"Real quick-to-world-drop signal was rejected", failures
	)
	var quick_drop_after := quick_drop_room.find_children("*", "GroundLootPickup3D", true, false).size()
	_check(
		quick_inventory.get_slot(0).is_empty()
		and not insurance.has_item("item_battery_s")
		and quick_drop_after == quick_drop_before + 1,
		"Quick item did not leave the slot and become a current-room drop", failures
	)

	var targeted_insurance_item := ItemRegistry.get_instance().get_item("item_cell_pack")
	_check(inventory.add_item(targeted_insurance_item, 1) == 1, "Cannot seed targeted insurance item", failures)
	var targeted_insurance_source := _find_item_slot(inventory, "item_cell_pack")
	_check(
		_drag_between_real_slots(ui._slots[targeted_insurance_source], ui._insurance_slots[1]),
		"Real backpack-to-exact-insurance-slot drag signal was rejected", failures
	)
	var targeted_insurance_snapshot := insurance.get_slots_snapshot()
	_check(
		targeted_insurance_snapshot[0].is_empty()
		and str(((targeted_insurance_snapshot[1] as Dictionary).get("item", {}) as Dictionary).get("id", "")) == "item_cell_pack",
		"Inventory item did not land in the exact insurance slot targeted by the drag", failures
	)
	var targeted_return_slot := _find_empty_slot(inventory)
	_check(
		_drag_between_real_slots(ui._insurance_slots[1], ui._slots[targeted_return_slot]),
		"Real insurance-slot-1 return drag signal was rejected", failures
	)

	# 前面已用全内容表填包，正式治疗药可能仍有另一堆；这里使用唯一探针物，
	# 避免“另一个同ID堆叠仍存在”被误判成世界丢弃没有移除来源格。
	var drop_probe := {
		"id": "test_tactical_drop_unique",
		"name": "丢弃唯一探针",
		"type": "resource",
		"stack_max": 1,
	}
	_check(inventory.add_item(drop_probe, 1) == 1, "Cannot seed droppable item", failures)
	var drop_probe_slot := _find_item_slot(inventory, "test_tactical_drop_unique")
	# 该场景会持续运行房间检测；前面的多轮拖拽与 process_frame 可能让玩家
	# 从初始房间边界切入相邻房间。世界丢弃的正式契约是落在“当前房间”，
	# 因此这里读取运行时当前房间，不能继续把测试目标写死为 start。
	var room := _get_current_room(dungeon)
	var pickups_before := room.find_children("*", "GroundLootPickup3D", true, false).size()
	var drop_probe_moved := bool(ui.call("_drop_inventory_slot_to_world", drop_probe_slot))
	_check(drop_probe_slot >= 0, "Droppable probe did not occupy a backpack slot", failures)
	_check(drop_probe_moved, "Dropping inventory item to world failed", failures)
	await get_tree().process_frame
	var pickups_after := room.find_children("*", "GroundLootPickup3D", true, false).size()
	_check(not inventory.has_item("test_tactical_drop_unique"), "Dropped item remained duplicated in backpack", failures)
	_check(
		pickups_after == pickups_before + 1,
		"Current-room pickup count did not increase after world drop (%d -> %d, room=%s)" % [
			pickups_before, pickups_after, str(dungeon.get("_current_room_id")),
		],
		failures
	)

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


func _find_empty_slot(inventory: InventoryModule) -> int:
	for index in inventory.get_capacity():
		if inventory.get_slot(index).is_empty():
			return index
	return -1


func _verify_ui_slot_index_contract(ui: InventoryUI, failures: Array[String]) -> void:
	for index in ui._slots.size():
		_check(int(ui._slots[index].get("slot_index")) == index, "Backpack UI slot index mismatch at %d" % index, failures)
	for index in ui._insurance_slots.size():
		_check(int(ui._insurance_slots[index].get("slot_index")) == index, "Insurance UI slot index mismatch at %d" % index, failures)
	for index in ui.quick_item_slots.size():
		_check(int(ui.quick_item_slots[index].get("slot_index")) == index, "Quick UI slot index mismatch at %d" % index, failures)
	for index in ui.equipment_weapon_slots.size():
		_check(int(ui.equipment_weapon_slots[index].get("slot_index")) == index, "Weapon UI slot index mismatch at %d" % index, failures)
	_check(int(ui.equipment_backpack_slot.get("slot_index")) == 0, "Equipped-backpack UI slot index mismatch", failures)
	_check(int(ui.drop_zone.get("slot_index")) == -1, "World-drop UI target index mismatch", failures)
	for weapon_index in ui.equipment_attachment_slots.size():
		for attachment_slot in ui.equipment_attachment_slots[weapon_index]:
			_check(
				int((attachment_slot as Control).get("slot_index"))
				== int((attachment_slot as Control).get_meta("attachment_slot_type", -1)),
				"Attachment UI slot index mismatch for weapon %d" % weapon_index,
				failures
			)


func _drag_between_real_slots(source: Control, target: Control) -> bool:
	if (
		source == null
		or target == null
		or bool(source.get_meta("drag_disabled", false))
		or not source.has_meta("drag_payload")
	):
		return false
	var payload := (source.get_meta("drag_payload") as Dictionary).duplicate(true)
	payload["inventory_drag"] = true
	payload["source_index"] = int(source.get("slot_index"))
	payload["source_kind"] = str(source.get_meta("slot_kind", "inventory"))
	if not bool(target.call("_can_drop_data", Vector2.ZERO, payload)):
		return false
	target.call("_drop_data", Vector2.ZERO, payload)
	return true


func _get_current_room(dungeon: Dungeon3D) -> DungeonRoom3D:
	var current_room_id := str(dungeon.get("_current_room_id"))
	return (dungeon.get("_room_by_id") as Dictionary).get(current_room_id) as DungeonRoom3D


func _check(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("TACTICAL_INVENTORY_MINIMAP_OK: character equipment, free insurance move/equip/quick/drop routing, explicit fate hover card, drag feedback contract, red HP, sort/drop, true room rectangles, player tracking and enemy dots pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
