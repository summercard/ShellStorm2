extends Node

const DUNGEON_SCENE: PackedScene = preload("res://scenes/Dungeon3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var dungeon := DUNGEON_SCENE.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 240725
	add_child(dungeon)
	await get_tree().process_frame
	var inventory := dungeon.get_inventory_module()
	var tree := dungeon.player.get_weapon_tree()
	await _verify_real_slot_click_and_3d_icons(dungeon, inventory, tree, failures)
	_verify_weapon_swap_preserves_build(dungeon, inventory, tree, failures)
	_verify_module_swap_is_atomic(dungeon, inventory, tree, failures)
	_verify_blueprint_and_consumable_routing(dungeon, inventory, tree, failures)
	if failures.is_empty():
		print("3D_INVENTORY_WEAPON_FLOW_OK: real slot-click equip, shared 3D item projections, per-instance build ownership, atomic module swap and item routing pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_real_slot_click_and_3d_icons(
	dungeon: Dungeon3D,
	inventory: InventoryModule,
	tree: WeaponAssemblyTree,
	failures: Array[String]
) -> void:
	inventory.clear_all()
	var expected_kinds := {
		"weapon_shotgun": "weapon",
		"mod_bullet_standard": "bullet",
		"item_health_potion": "heal",
		"item_room_key": "key",
		"item_beacon": "beacon",
	}
	for item_id in expected_kinds.keys():
		var item := ItemRegistry.get_instance().get_item(item_id)
		if item.is_empty() or inventory.add_item(item, 1) <= 0:
			failures.append("Cannot prepare 3D inventory projection for %s" % item_id)
	var inventory_ui := dungeon.get_node_or_null("HUD/InventoryUI3D") as InventoryUI
	if inventory_ui == null:
		failures.append("InventoryUI3D is missing for real-click acceptance")
		return
	inventory_ui.set_inventory_panel_open(true)
	await get_tree().process_frame
	await get_tree().process_frame
	for item_id in expected_kinds.keys():
		var slot_index := _find_slot(inventory, item_id)
		var model_snapshot := inventory_ui.get_slot_model_snapshot(slot_index)
		if str(model_snapshot.get("model_kind", "")) != str(expected_kinds[item_id]):
			failures.append("Inventory item %s does not use its expected 3D model kind" % item_id)
		if int(model_snapshot.get("mesh_count", 0)) <= 0:
			failures.append("Inventory item %s has an empty 3D projection" % item_id)
		if model_snapshot.get("viewport_size", Vector2i.ZERO) != Vector2i(96, 96):
			failures.append("Inventory item %s does not render at the 96x96 projection budget" % item_id)
		if float(model_snapshot.get("camera_size", 99.0)) > 1.9:
			failures.append("Inventory item %s 3D model is too small to read at slot scale" % item_id)
		if (
			not bool(model_snapshot.get("update_once", false))
			or not bool(model_snapshot.get("uses_world_model_factory", false))
		):
			failures.append("Inventory item %s is not a one-shot projection of the shared world model" % item_id)

	var shotgun_slot := _find_slot(inventory, "weapon_shotgun")
	var slots: Array = inventory_ui.get("_slots")
	if shotgun_slot < 0 or shotgun_slot >= slots.size() or not slots[shotgun_slot] is ItemSlot:
		failures.append("Cannot resolve the actual shotgun ItemSlot for click acceptance")
	else:
		(slots[shotgun_slot] as ItemSlot).slot_clicked.emit(shotgun_slot)
		await get_tree().process_frame
		var root := tree.get_root()
		var weapon_snapshot := dungeon.player.get_weapon_snapshot()
		if root == null or root.node_name != "GunBody_Shotgun":
			failures.append("Actual ItemSlot left click did not equip the picked-up shotgun")
		if str(weapon_snapshot.get("gun_id", "")) != "bp_shotgun" or not bool(weapon_snapshot.get("has_model", false)):
			failures.append("Actual inventory click did not synchronize the equipped 3D gun model")
		if not inventory.has_item("weapon_pistol"):
			failures.append("Actual inventory click did not return the old pistol to the inventory")
	inventory_ui.set_inventory_panel_open(false)
	inventory.clear_all()
	if not dungeon.player.equip_weapon("bp_pistol", "mod_bullet_standard"):
		failures.append("Cannot reset the weapon tree after real-click acceptance")


func _verify_weapon_swap_preserves_build(
	dungeon: Dungeon3D,
	inventory: InventoryModule,
	tree: WeaponAssemblyTree,
	failures: Array[String]
) -> void:
	var old_root := tree.get_root()
	var desired := {
		AssemblyNode.SlotType.MUZZLE: "attach_triple_muzzle",
		AssemblyNode.SlotType.MAGAZINE: "attach_big_mag",
		AssemblyNode.SlotType.MOUNT: "attach_fan",
	}
	for slot_type in desired.keys():
		var node := BlueprintRegistry.create_assembly_node(desired[slot_type])
		if node == null or not tree.mount(old_root, int(slot_type), node):
			failures.append("Cannot prepare installed module %s for weapon-swap acceptance" % desired[slot_type])
	var expected_names: Dictionary = {}
	for slot_type in old_root.slots.keys():
		var installed := old_root.slots.get(slot_type) as AssemblyNode
		if installed != null:
			expected_names[slot_type] = installed.node_name
	var shotgun := ItemRegistry.get_instance().get_item("weapon_shotgun")
	inventory.add_item(shotgun, 1)
	var shotgun_slot_before := _find_slot(inventory, "weapon_shotgun")
	var shotgun_item_before := (inventory.get_slot(shotgun_slot_before).get("item", {}) as Dictionary)
	var shotgun_instance_id := str(shotgun_item_before.get("weapon_instance_id", ""))
	var shotgun_slot := _find_slot(inventory, "weapon_shotgun")
	dungeon.call("_on_inventory_item_clicked", shotgun_slot, {})
	var new_root := tree.get_root()
	if new_root == null or new_root.node_name != "GunBody_Shotgun":
		failures.append("Inventory weapon click did not equip the selected gun body")
	elif dungeon.player.get_equipped_weapon_instance_id() != shotgun_instance_id:
		failures.append("Inventory weapon click did not equip the selected unique instance")
	if not inventory.has_item("weapon_pistol"):
		failures.append("Switching gun body did not return the old weapon to inventory")
	else:
		var pistol_slot := _find_slot(inventory, "weapon_pistol")
		var pistol_item := inventory.get_slot(pistol_slot).get("item", {}) as Dictionary
		var pistol_instance := WeaponInstance.from_item(pistol_item)
		var stored_tree := pistol_instance.build_runtime_tree() if pistol_instance != null else null
		if stored_tree == null or stored_tree.get_root() == null:
			failures.append("Old weapon instance lost its stored assembly snapshot")
		else:
			for slot_type in expected_names.keys():
				var stored := stored_tree.get_root().slots.get(slot_type) as AssemblyNode
				if stored == null or stored.node_name != expected_names[slot_type]:
					failures.append("Old weapon instance lost installed module in slot %s" % slot_type)
			stored_tree.free()
	for slot_type in [AssemblyNode.SlotType.MUZZLE, AssemblyNode.SlotType.MAGAZINE, AssemblyNode.SlotType.MOUNT]:
		if new_root.slots.get(slot_type) != null:
			failures.append("New gun incorrectly inherited old gun module in slot %s" % slot_type)


func _verify_module_swap_is_atomic(
	dungeon: Dungeon3D,
	inventory: InventoryModule,
	tree: WeaponAssemblyTree,
	failures: Array[String]
) -> void:
	var root := tree.get_root()
	var old_bullet := root.slots.get(AssemblyNode.SlotType.BULLET) as AssemblyNode
	if old_bullet == null:
		failures.append("Weapon has no bullet module before swap")
		return
	var old_item_id := _module_item_id(old_bullet.node_name)
	var new_item_id := "mod_bullet_standard" if old_item_id != "mod_bullet_standard" else "mod_bullet_sticky"
	var new_item := ItemRegistry.get_instance().get_item(new_item_id)
	inventory.add_item(new_item, 1)
	var new_slot := _find_slot(inventory, new_item_id)
	dungeon.call("_on_inventory_item_clicked", new_slot, {})
	var installed := tree.get_root().slots.get(AssemblyNode.SlotType.BULLET) as AssemblyNode
	if installed == null or _module_item_id(installed.node_name) != new_item_id:
		failures.append("New bullet module was not installed from inventory")
	if old_item_id.is_empty() or not inventory.has_item(old_item_id):
		failures.append("Replaced bullet module was not returned to inventory")

	inventory.clear_all()
	var blocked_new_id := "mod_bullet_bounce" if new_item_id != "mod_bullet_bounce" else "mod_bullet_explosive"
	var blocked_item := ItemRegistry.get_instance().get_item(blocked_new_id)
	inventory.add_item(blocked_item, 2)
	for candidate in ItemRegistry.get_instance().get_all_items():
		if inventory.get_used_slots() >= inventory.get_capacity():
			break
		var candidate_id := str(candidate.get("id", ""))
		if candidate_id.is_empty() or inventory.has_item(candidate_id):
			continue
		inventory.add_item(candidate, 1)
	var before_name := (tree.get_root().slots.get(AssemblyNode.SlotType.BULLET) as AssemblyNode).node_name
	var blocked_slot := _find_slot(inventory, blocked_new_id)
	dungeon.call("_on_inventory_item_clicked", blocked_slot, {})
	var after_name := (tree.get_root().slots.get(AssemblyNode.SlotType.BULLET) as AssemblyNode).node_name
	if before_name != after_name:
		failures.append("Full-inventory module swap replaced the build without space for the old module")
	if inventory.get_item_count(blocked_new_id) != 2:
		failures.append("Rejected full-inventory module swap consumed the new module")


func _verify_blueprint_and_consumable_routing(
	dungeon: Dungeon3D,
	inventory: InventoryModule,
	tree: WeaponAssemblyTree,
	failures: Array[String]
) -> void:
	inventory.clear_all()
	var root_name := tree.get_root().node_name
	var dummy_blueprint := {
		"id": "acceptance_gun_blueprint",
		"name": "验收枪身蓝图",
		"type": "blueprint",
		"subtype": "gun_body",
		"stack_max": 1,
	}
	inventory.add_item(dummy_blueprint, 1)
	dungeon.call("_on_inventory_item_clicked", _find_slot(inventory, "acceptance_gun_blueprint"), {})
	if tree.get_root().node_name != root_name:
		failures.append("Gun-body blueprint fragment was incorrectly equipped as a physical weapon")
	if not inventory.has_item("acceptance_gun_blueprint"):
		failures.append("Non-usable blueprint fragment was incorrectly consumed")

	inventory.clear_all()
	dungeon.player.current_hp = dungeon.player.max_hp
	var potion := ItemRegistry.get_instance().get_item("item_health_potion")
	inventory.add_item(potion, 1)
	dungeon.call("_on_inventory_item_clicked", _find_slot(inventory, "item_health_potion"), {})
	if not inventory.has_item("item_health_potion"):
		failures.append("Healing consumable was wasted while player HP was already full")


func _find_slot(inventory: InventoryModule, item_id: String) -> int:
	for slot in inventory.get_occupied_slots():
		if str((slot.get("item", {}) as Dictionary).get("id", "")) == item_id:
			return int(slot.get("slot", -1))
	return -1


func _module_item_id(node_name: String) -> String:
	return str({
		"Bullet_Standard": "mod_bullet_standard",
		"Bullet_Sticky": "mod_bullet_sticky",
		"Bullet_Bounce": "mod_bullet_bounce",
		"Bullet_Piercing": "mod_bullet_piercing",
		"Bullet_Explosive": "mod_bullet_explosive",
		"Bullet_Homing": "mod_bullet_homing",
		"Bullet_Blackhole": "mod_bullet_blackhole",
		"Bullet_Balloon": "mod_bullet_balloon",
	}.get(node_name, ""))
