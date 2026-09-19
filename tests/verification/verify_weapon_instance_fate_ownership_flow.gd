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
	var starting_gun_id := str(initial.get("weapon_instance_id", ""))
	_check(not starting_gun_id.is_empty(), "Starting gun has no persistent instance ID", failures)
	# 出厂枪的命运槽容量是**设计值**（当前 4；曾为 8），本场景不该把它写死：
	# 它验的是「整条命运链路能不能把**出厂枪的容量**用满并守住」，不是某一个具体数字。
	# 容量本身由专属门禁 verify_starting_weapon_contract 盯着。
	var fate_capacity := int(initial.get("fate_slot_capacity", 0))
	_check(fate_capacity >= 4, "Starting gun exposes too few fate slots to exercise ordering and rejection", failures)

	var attachment := BlueprintRegistry.create_assembly_node("attach_big_mag")
	var root := player.get_weapon_tree().get_root()
	_check(attachment != null and player.get_weapon_tree().mount(root, AssemblyNode.SlotType.MAGAZINE, attachment), "Cannot install replaceable attachment", failures)
	_check(int(player.get_weapon_presentation_snapshot().get("fate_slot_used", -1)) == 0, "Replaceable attachment consumed a fate slot", failures)

	for expected_slot in range(1, fate_capacity + 1):
		var result := FateCardGameBridge.apply_card(FateCardPresets.overclock())
		_check(bool(result.get("success", false)), "Weapon fate card failed at slot %d" % expected_slot, failures)
		_check(int(result.get("slot_index", 0)) == expected_slot, "Weapon fate slot order is not linear at %d" % expected_slot, failures)
	var full_snapshot := player.get_weapon_presentation_snapshot()
	_check(int(full_snapshot.get("fate_slot_used", 0)) == fate_capacity, "Applied cards were not persisted on the gun", failures)
	var fire_rate_before_reject := float(player.get_weapon_snapshot().get("fire_rate", 0.0))
	var rejected := FateCardGameBridge.apply_card(FateCardPresets.overclock())
	_check(not bool(rejected.get("success", true)), "Fate card was accepted into a full gun", failures)
	_check("卡片未消耗" in str(rejected.get("message", "")), "Full-slot rejection lacks non-consumption feedback", failures)
	_check(is_equal_approx(float(player.get_weapon_snapshot().get("fire_rate", 0.0)), fire_rate_before_reject), "Rejected fate card still mutated the weapon", failures)

	var world_before := int(player.get_weapon_presentation_snapshot().get("fate_slot_used", -1))
	var world_result := FateCardGameBridge.apply_card(FateCardPresets.fate_extra_loot())
	var character_result := FateCardGameBridge.apply_card(FateCardPresets.fate_bless_dead())
	_check(bool(world_result.get("success", false)) and world_result.get("scope", "") == "WORLD", "World-scope card did not route to world state", failures)
	_check(bool(character_result.get("success", false)) and character_result.get("scope", "") == "CHARACTER", "Character-scope card did not route to character state", failures)
	_check(int(player.get_weapon_presentation_snapshot().get("fate_slot_used", -1)) == world_before, "Character/world card occupied a weapon fate slot", failures)

	var starting_gun_item := player.get_equipped_weapon_item()
	var serialized: Variant = JSON.parse_string(JSON.stringify(starting_gun_item))
	var restored := WeaponInstance.from_item(serialized as Dictionary)
	_check(restored != null and restored.weapon_instance_id == starting_gun_id, "JSON save/load changed the weapon instance ID", failures)
	_check(restored != null and restored.fate_upgrades.size() == fate_capacity, "JSON save/load lost fate slot order", failures)
	var restored_tree := restored.build_runtime_tree() if restored != null else null
	_check(restored_tree != null and restored_tree.get_root().slots.get(AssemblyNode.SlotType.MAGAZINE) != null, "JSON save/load lost the installed attachment", failures)
	if restored_tree != null:
		restored_tree.free()

	var inventory := InventoryModule.new(4)
	var shotgun := ItemRegistry.get_instance().get_item("weapon_shotgun")
	_check(inventory.add_item(shotgun, 1) == 1, "Cannot add a generated shotgun instance", failures)
	var shotgun_item := inventory.get_slot(0).get("item", {}) as Dictionary
	var shotgun_id := str(shotgun_item.get("weapon_instance_id", ""))
	_check(not shotgun_id.is_empty() and shotgun_id != starting_gun_id, "Two guns share an instance ID", failures)
	var equip_result := player.equip_weapon_item(shotgun_item)
	_check(bool(equip_result.get("success", false)), "Cannot equip a complete shotgun instance", failures)
	_check(player.get_equipped_weapon_instance_id() == shotgun_id, "Equipment slot does not own the selected shotgun instance", failures)
	_check(int(player.get_weapon_presentation_snapshot().get("fate_slot_used", -1)) == 0, "New shotgun inherited the old starting gun's fate upgrades", failures)
	var old_item := equip_result.get("old_item", {}) as Dictionary
	_check(str(old_item.get("weapon_instance_id", "")) == starting_gun_id, "Old weapon identity was not returned by swap", failures)
	_check((old_item.get("fate_upgrades", []) as Array).size() == fate_capacity, "Old weapon fate build did not follow it into the bag", failures)
	var re_equip := player.equip_weapon_item(old_item)
	_check(bool(re_equip.get("success", false)) and player.get_equipped_weapon_instance_id() == starting_gun_id, "Stored weapon cannot restore its complete build", failures)
	_check(int(player.get_weapon_presentation_snapshot().get("fate_slot_used", 0)) == fate_capacity, "Re-equipped weapon lost fate slots", failures)

	var duplicate_inventory := InventoryModule.new(2)
	_check(duplicate_inventory.add_item(old_item, 1) == 1, "Cannot place weapon instance into inventory", failures)
	_check(duplicate_inventory.add_item(old_item, 1) == 0, "Inventory duplicated the same weapon instance ID", failures)
	var insurance := InsuranceModule.new(2)
	_check(insurance.insure_item_direct(old_item), "Cannot insure a complete weapon instance", failures)
	var insured := insurance.get_occupied_slots()[0].get("item", {}) as Dictionary
	_check(str(insured.get("weapon_instance_id", "")) == starting_gun_id and (insured.get("fate_upgrades", []) as Array).size() == fate_capacity, "Insurance transfer lost weapon identity or fate build", failures)
	var world_model := ItemModelFactory3D.create_model(old_item)
	add_child(world_model)
	await get_tree().process_frame
	_check(not world_model.find_children("InstalledMagazine", "MeshInstance3D", true, false).is_empty(), "Ground/inventory model does not show the stored attachment", failures)
	_check(world_model.find_children("FateRune*", "MeshInstance3D", true, false).size() == fate_capacity, "Ground/inventory model does not show permanent fate build marks", failures)

	var panel := PANEL_SCENE.instantiate() as WeaponAssemblyTreePanel
	add_child(panel)
	panel.set_weapon_tree(player.get_weapon_tree())
	panel.set_weapon_owner(player)
	panel.show_panel()
	await get_tree().process_frame
	var identity_label := panel.get("_identity_label") as Label
	var fate_label := panel.get("_fate_track_label") as Label
	_check(identity_label != null and starting_gun_id.right(6).to_upper() in identity_label.text, "Weapon page does not show the instance suffix", failures)
	_check(fate_label != null and ("%d/%d" % [fate_capacity, fate_capacity]) in fate_label.text and "🔒" in fate_label.text, "Weapon page does not show locked permanent fate slots", failures)

	if failures.is_empty():
		print("WEAPON_INSTANCE_FATE_OWNERSHIP_OK: unique identity, %d-slot irreversible fate build, scope routing, full-instance swap, persistence, insurance and weapon-page feedback pass" % fate_capacity)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _check(condition: bool, failure: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(failure)
