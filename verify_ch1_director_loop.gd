extends Node

const GROUND_ITEM_PICKUP_SCRIPT := preload("res://src/items/GroundItemPickup.gd")


func _ready() -> void:
	var failures: Array[String] = []
	await _verify_main_chapter_loop(failures)
	await _verify_bullet_wall_contract(failures)
	_finish(failures)


func _verify_main_chapter_loop(failures: Array[String]) -> void:
	GameManager.currency = 0
	GameManager.currency_changed.emit(GameManager.currency)
	var main_scene: PackedScene = load("res://scenes/Main.tscn") as PackedScene
	if main_scene == null:
		failures.append("Main scene does not load")
		return

	var main := main_scene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var mode: RoomGameMode = main.get_node_or_null("RoomGameMode") as RoomGameMode
	var ui: CanvasLayer = main.get_node_or_null("GameUIManager") as CanvasLayer
	if mode == null or ui == null or mode.inventory_module == null:
		failures.append("Main did not create RoomGameMode, UI, and inventory")
		main.queue_free()
		return

	var start_room := mode.map_manager.get_instantiated_room(0)
	var start_chest := _find_container(start_room)
	if start_chest == null:
		failures.append("Initial room has no searchable starter chest")
	else:
		start_chest.call("_try_open_container")
		await get_tree().process_frame
		if not mode.inventory_module.has_item("weapon_shotgun"):
			failures.append("Initial starter chest did not grant the shotgun weapon")

	var press_i := InputEventKey.new()
	press_i.keycode = KEY_I
	press_i.physical_keycode = KEY_I
	press_i.pressed = true
	ui._input(press_i)
	await get_tree().process_frame
	var inventory_panel := ui.get_node_or_null("InventoryPanel") as Control
	var weapon_panel := ui.get_node_or_null("WeaponAssemblyTreePanel") as Control
	if inventory_panel == null or not inventory_panel.visible:
		failures.append("Pressing I does not open the backpack")
	if weapon_panel == null or not weapon_panel.visible:
		failures.append("Pressing I does not surface the weapon assembly tree")

	var shotgun_slot := _find_inventory_slot(mode.inventory_module, "weapon_shotgun")
	if shotgun_slot < 0:
		failures.append("Shotgun weapon is not present in an operable inventory slot")
	else:
		var shotgun_count_before := mode.inventory_module.get_item_count("weapon_shotgun")
		ui.call("_on_slot_right_clicked", shotgun_slot, true)
		await get_tree().process_frame
		var root: AssemblyNode = mode.player.get_weapon_tree().get_root()
		if root == null or root.node_name != "GunBody_Shotgun":
			failures.append("Right-clicking shotgun did not switch the player's main weapon")
		if mode.inventory_module.get_item_count("weapon_shotgun") != shotgun_count_before - 1:
			failures.append("Equipping shotgun did not remove exactly one weapon from the backpack")
		if not mode.inventory_module.has_item("weapon_pistol"):
			failures.append("Equipping shotgun did not return the previous weapon to backpack")

	var neighbors := mode.map_manager.get_graph().get_neighbors(0)
	if neighbors.is_empty():
		failures.append("Initial room has no door to open")
	else:
		mode.try_open_room_door(int(neighbors[0]))
		await get_tree().process_frame
		await get_tree().process_frame
		var fate_panel := ui.get_node_or_null("FateCardPanel") as Control
		if fate_panel == null or not fate_panel.visible:
			failures.append("Opening the initial door no longer triggers fate card choice")
		elif fate_panel.find_child("FateModal", true, false) == null:
			failures.append("Fate card panel is visible but has no selectable modal")
		else:
			var before_damage: int = mode.player.get_weapon_tree().bullet_damage
			mode.call("_on_fate_card_button_pressed", FateCardPresets.armor_pierce())
			await get_tree().process_frame
			if mode.player.get_weapon_tree().bullet_damage <= before_damage:
				failures.append("Choosing a door fate upgrade did not increase live bullet damage")

	var before_currency := GameManager.currency
	var before_items := _inventory_item_count(mode.inventory_module)
	(
		mode
		. notify_enemy_killed(
			{
				"floor": 1,
				"is_elite": true,
				"currency_value": 13,
				"xp_value": 1,
				"last_position": mode.player.global_position + Vector2(180, 0),
				"loot_table": "combat_floor_1",
			}
		)
	)
	await get_tree().process_frame
	await get_tree().process_frame
	var orb := _find_soul_orb(mode)
	var item_pickup := _find_ground_item(mode)
	if orb == null:
		failures.append("Enemy kill did not spawn a soul orb on the ground")
	if item_pickup == null:
		failures.append("Rewarding enemy kill did not leave its item loot on the ground")
	if _inventory_item_count(mode.inventory_module) != before_items:
		failures.append(
			"Enemy item loot entered backpack immediately instead of waiting for pickup"
		)
	if GameManager.currency != before_currency:
		failures.append("Enemy soul reward was added instantly instead of waiting for pickup")
	if item_pickup != null:
		mode.player.global_position = item_pickup.global_position
		for i in range(4):
			await get_tree().process_frame
		if _inventory_item_count(mode.inventory_module) <= before_items:
			failures.append("Ground item loot was not collectable by approaching it")
	if orb != null:
		mode.player.global_position = orb.global_position
		for i in range(10):
			await get_tree().process_frame
		if GameManager.currency <= before_currency:
			failures.append("Soul orb was not collectable by walking over it")

	main.queue_free()


func _verify_bullet_wall_contract(failures: Array[String]) -> void:
	var bullet_scene: PackedScene = load("res://scenes/Bullet.tscn") as PackedScene
	var bullet: Area2D = bullet_scene.instantiate() as Area2D
	add_child(bullet)
	bullet.call("fire", Vector2.ZERO, Vector2.RIGHT, 0.0, 1, false)
	if (bullet.collision_mask & 1) == 0:
		failures.append("Player bullet collision mask does not include wall layer")
	var wall := StaticBody2D.new()
	add_child(wall)
	bullet.call("_on_body_entered", wall)
	await get_tree().process_frame
	if is_instance_valid(bullet) and not bullet.is_queued_for_deletion():
		failures.append("Player bullet does not despawn when hitting wall body")
	wall.queue_free()


func _find_container(root: Node) -> ContainerInteraction:
	if root == null:
		return null
	if root is ContainerInteraction:
		return root as ContainerInteraction
	for child in root.get_children():
		var found := _find_container(child)
		if found != null:
			return found
	return null


func _find_inventory_slot(inventory: InventoryModule, item_id: String) -> int:
	for slot in inventory.get_occupied_slots():
		var item: Dictionary = slot.get("item", {})
		if item.get("id", "") == item_id:
			return int(slot.get("slot", -1))
	return -1


func _find_soul_orb(root: Node) -> SoulOrb:
	for child in root.get_children():
		if child is SoulOrb:
			return child as SoulOrb
		var found := _find_soul_orb(child)
		if found != null:
			return found
	return null


func _find_ground_item(root: Node) -> Node2D:
	for child in root.get_children():
		if child.get_script() == GROUND_ITEM_PICKUP_SCRIPT:
			return child as Node2D
		var found: Node2D = _find_ground_item(child)
		if found != null:
			return found
	return null


func _inventory_item_count(inventory: InventoryModule) -> int:
	var total := 0
	for slot in inventory.get_occupied_slots():
		total += int(slot.get("count", 0))
	return total


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print(
			"CH1_DIRECTOR_LOOP_OK: starter shotgun, fate upgrade, ground loot pickup, guaranteed soul drop, and wall-blocked bullets are playable"
		)
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
