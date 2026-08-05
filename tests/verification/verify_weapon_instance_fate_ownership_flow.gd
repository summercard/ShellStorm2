extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const PANEL_SCENE: PackedScene = preload("res://scenes/WeaponAssemblyTreePanel.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var player := PLAYER_SCENE.instantiate() as Player3D
	add_child(player)
	await get_tree().process_frame
	FateCardGameBridge.set_player(player)

	var initial := player.get_weapon_presentation_snapshot()
	var pistol_id := str(initial.get("weapon_instance_id", ""))
	_check(not pistol_id.is_empty(), "Starting gun has no persistent instance ID", failures)
	_check(int(initial.get("fate_slot_capacity", 0)) == 8, "Common gun does not expose 8 fate slots", failures)

	var attachment := BlueprintRegistry.create_assembly_node("attach_big_mag")
	var root := player.get_weapon_tree().get_root()
	_check(attachment != null and player.get_weapon_tree().mount(root, AssemblyNode.SlotType.MAGAZINE, attachment), "Cannot install replaceable attachment", failures)
	_check(int(player.get_weapon_presentation_snapshot().get("fate_slot_used", -1)) == 0, "Replaceable attachment consumed a fate slot", failures)

	for expected_slot in range(1, 9):
		var result := FateCardGameBridge.apply_card(FateCardPresets.overclock())
		_check(bool(result.get("success", false)), "Weapon fate card failed at slot %d" % expected_slot, failures)
		_check(int(result.get("slot_index", 0)) == expected_slot, "Weapon fate slot order is not linear at %d" % expected_slot, failures)
	var full_snapshot := player.get_weapon_presentation_snapshot()
	_check(int(full_snapshot.get("fate_slot_used", 0)) == 8, "Eight applied cards were not persisted on the gun", failures)
	var fire_rate_before_reject := float(player.get_weapon_snapshot().get("fire_rate", 0.0))
	var rejected := FateCardGameBridge.apply_card(FateCardPresets.overclock())
	_check(not bool(rejected.get("success", true)), "Ninth weapon fate card was accepted into a full gun", failures)
	_check("卡片未消耗" in str(rejected.get("message", "")), "Full-slot rejection lacks non-consumption feedback", failures)
	_check(is_equal_approx(float(player.get_weapon_snapshot().get("fire_rate", 0.0)), fire_rate_before_reject), "Rejected fate card still mutated the weapon", failures)

	var world_before := int(player.get_weapon_presentation_snapshot().get("fate_slot_used", -1))
	var world_result := FateCardGameBridge.apply_card(FateCardPresets.fate_extra_loot())
	var character_result := FateCardGameBridge.apply_card(FateCardPresets.fate_bless_dead())
	_check(bool(world_result.get("success", false)) and world_result.get("scope", "") == "WORLD", "World-scope card did not route to world state", failures)
	_check(bool(character_result.get("success", false)) and character_result.get("scope", "") == "CHARACTER", "Character-scope card did not route to character state", failures)
	_check(int(player.get_weapon_presentation_snapshot().get("fate_slot_used", -1)) == world_before, "Character/world card occupied a weapon fate slot", failures)

	var pistol_item := player.get_equipped_weapon_item()
	var serialized: Variant = JSON.parse_string(JSON.stringify(pistol_item))
	var restored := WeaponInstance.from_item(serialized as Dictionary)
	_check(restored != null and restored.weapon_instance_id == pistol_id, "JSON save/load changed the weapon instance ID", failures)
	_check(restored != null and restored.fate_upgrades.size() == 8, "JSON save/load lost fate slot order", failures)
	var restored_tree := restored.build_runtime_tree() if restored != null else null
	_check(restored_tree != null and restored_tree.get_root().slots.get(AssemblyNode.SlotType.MAGAZINE) != null, "JSON save/load lost the installed attachment", failures)
	if restored_tree != null:
		restored_tree.free()

	var inventory := InventoryModule.new(4)
	var shotgun := ItemRegistry.get_instance().get_item("weapon_shotgun")
	_check(inventory.add_item(shotgun, 1) == 1, "Cannot add a generated shotgun instance", failures)
	var shotgun_item := inventory.get_slot(0).get("item", {}) as Dictionary
	var shotgun_id := str(shotgun_item.get("weapon_instance_id", ""))
	_check(not shotgun_id.is_empty() and shotgun_id != pistol_id, "Two guns share an instance ID", failures)
	var equip_result := player.equip_weapon_item(shotgun_item)
	_check(bool(equip_result.get("success", false)), "Cannot equip a complete shotgun instance", failures)
	_check(player.get_equipped_weapon_instance_id() == shotgun_id, "Equipment slot does not own the selected shotgun instance", failures)
	_check(int(player.get_weapon_presentation_snapshot().get("fate_slot_used", -1)) == 0, "New shotgun inherited old pistol fate upgrades", failures)
	var old_item := equip_result.get("old_item", {}) as Dictionary
	_check(str(old_item.get("weapon_instance_id", "")) == pistol_id, "Old pistol identity was not returned by swap", failures)
	_check((old_item.get("fate_upgrades", []) as Array).size() == 8, "Old pistol fate build did not follow it into the bag", failures)
	var re_equip := player.equip_weapon_item(old_item)
	_check(bool(re_equip.get("success", false)) and player.get_equipped_weapon_instance_id() == pistol_id, "Stored pistol cannot restore its complete build", failures)
	_check(int(player.get_weapon_presentation_snapshot().get("fate_slot_used", 0)) == 8, "Re-equipped pistol lost fate slots", failures)

	var duplicate_inventory := InventoryModule.new(2)
	_check(duplicate_inventory.add_item(old_item, 1) == 1, "Cannot place weapon instance into inventory", failures)
	_check(duplicate_inventory.add_item(old_item, 1) == 0, "Inventory duplicated the same weapon instance ID", failures)
	var insurance := InsuranceModule.new(2)
	_check(insurance.insure_item_direct(old_item), "Cannot insure a complete weapon instance", failures)
	var insured := insurance.get_occupied_slots()[0].get("item", {}) as Dictionary
	_check(str(insured.get("weapon_instance_id", "")) == pistol_id and (insured.get("fate_upgrades", []) as Array).size() == 8, "Insurance transfer lost weapon identity or fate build", failures)
	var world_model := ItemModelFactory3D.create_model(old_item)
	add_child(world_model)
	await get_tree().process_frame
	_check(not world_model.find_children("InstalledMagazine", "MeshInstance3D", true, false).is_empty(), "Ground/inventory model does not show the stored attachment", failures)
	_check(world_model.find_children("FateRune*", "MeshInstance3D", true, false).size() == 8, "Ground/inventory model does not show permanent fate build marks", failures)

	var panel := PANEL_SCENE.instantiate() as WeaponAssemblyTreePanel
	add_child(panel)
	panel.set_weapon_tree(player.get_weapon_tree())
	panel.set_weapon_owner(player)
	panel.show_panel()
	await get_tree().process_frame
	var identity_label := panel.get("_identity_label") as Label
	var fate_label := panel.get("_fate_track_label") as Label
	_check(identity_label != null and pistol_id.right(6).to_upper() in identity_label.text, "Weapon page does not show the instance suffix", failures)
	_check(fate_label != null and "8/8" in fate_label.text and "🔒" in fate_label.text, "Weapon page does not show locked permanent fate slots", failures)

	if failures.is_empty():
		print("WEAPON_INSTANCE_FATE_OWNERSHIP_OK: unique identity, 8-slot irreversible fate build, scope routing, full-instance swap, persistence, insurance and weapon-page feedback pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _check(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)
