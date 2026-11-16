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
	_check(not bool(world_result.get("success", true)) and world_result.get("error", "") == "world_owner_unavailable", "缺少世界所有者时不得假成功", failures)
	_check(FateCardGameBridge.world_card_ids.is_empty(), "世界命令失败仍登记持卡", failures)
	var world_owner := preload("res://scenes/Dungeon3D.tscn").instantiate() as Dungeon3D
	world_owner.test_mode = true
	add_child(world_owner)
	FateCardGameBridge.set_player(player)
	world_result = FateCardGameBridge.apply_card(FateCardPresets.fate_extra_loot())
	_check(bool(world_result.get("success", false)) and int(world_owner.get_world_fate_snapshot().get("next_chest_extra", 0)) == 1, "世界效果没有恰好执行一次", failures)
	world_owner.queue_free()
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

	var shotgun := ItemRegistry.get_instance().get_item("weapon_shotgun")
	var shotgun_size := ItemRegistry.grid_size_of(shotgun)
	_check(str(shotgun.get("id", "")) == "weapon_shotgun" and str(shotgun.get("type", "")) == "weapon", "散弹枪注册模板缺失或不是武器", failures)
	_check(shotgun_size == Vector2i(4, 2), "散弹枪应保留当前4×2整枪足迹", failures)
	# 容量是固定8列棋盘的有效格数，不是整枪数量；按真实高度提供完整行。
	var inventory := InventoryModule.new(InventoryModule.GRID_COLUMNS * shotgun_size.y)
	_check(inventory.can_place_item_at(shotgun, 0), "散弹枪夹具没有足够的连续矩形空间", failures)
	_check(inventory.add_item(shotgun, 1) == 1, "Cannot add a generated shotgun instance", failures)
	var shotgun_item := inventory.get_slot(0).get("item", {}) as Dictionary
	_check(ItemRegistry.grid_size_of(shotgun_item) == shotgun_size and inventory.get_used_area() == shotgun_size.x * shotgun_size.y, "装入散弹枪未保留完整足迹或实际占格不符", failures)
	var shotgun_assembly := shotgun_item.get("assembly_snapshot", {}) as Dictionary
	var shotgun_slots := shotgun_assembly.get("slots", {}) as Dictionary
	_check(str(shotgun_assembly.get("node_name", "")) == "GunBody_Shotgun" and not (shotgun_slots.get(str(AssemblyNode.SlotType.BULLET), {}) as Dictionary).is_empty(), "生成散弹枪缺少真实枪身或弹药模块，不能归因于容量", failures)
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

	var old_size := ItemRegistry.grid_size_of(old_item)
	var starting_content_id := str(starting_gun_item.get("weapon_content_id", ""))
	var starting_definition := ItemRegistry.get_instance().get_item(starting_content_id)
	_check(not starting_definition.is_empty() and old_size == ItemRegistry.grid_size_of(starting_definition) and old_size == ItemRegistry.grid_size_of(starting_gun_item), "换回出厂枪未保留注册表真实足迹或换装前后尺寸不一致", failures)
	var duplicate_inventory := InventoryModule.new(InventoryModule.GRID_COLUMNS * old_size.y)
	_check(duplicate_inventory.can_place_item_at(old_item, 0), "实例保真夹具没有足够的连续矩形空间", failures)
	_check(duplicate_inventory.add_item(old_item, 1) == 1, "Cannot place weapon instance into inventory", failures)
	var stored_item := duplicate_inventory.get_slot(0).get("item", {}) as Dictionary
	_check(str(stored_item.get("weapon_instance_id", "")) == starting_gun_id and stored_item.get("fate_upgrades", []) == old_item.get("fate_upgrades", []) and stored_item.get("assembly_snapshot", {}) == old_item.get("assembly_snapshot", {}), "背包未保留完整武器实例、命运顺序或装配", failures)
	_check(ItemRegistry.grid_size_of(stored_item) == old_size and duplicate_inventory.get_used_area() == old_size.x * old_size.y, "背包出厂枪实际足迹不符", failures)
	# 第二把仍有合法矩形空位，拒绝必须来自实例去重，而非容量不足。
	_check(duplicate_inventory.can_place_item_at(old_item, old_size.x), "拒重复夹具没有为第二份实例保留合法空位", failures)
	var before_duplicate := duplicate_inventory.get_slots_snapshot()
	_check(duplicate_inventory.add_item(old_item, 1) == 0, "Inventory duplicated the same weapon instance ID", failures)
	_check(duplicate_inventory.get_slots_snapshot() == before_duplicate, "拒绝重复实例仍改变了背包", failures)
	var insurance := InsuranceModule.new(InventoryModule.GRID_COLUMNS * old_size.y)
	_check(insurance.can_place_item_at(old_item, 0), "保险夹具没有足够的连续矩形空间", failures)
	_check(insurance.insure_item_direct(old_item), "Cannot insure a complete weapon instance", failures)
	# 保留空数组保护以继续报告断言；装入失败仍必须判红。
	var insured_slots := insurance.get_occupied_slots()
	var insured := insured_slots[0].get("item", {}) as Dictionary if not insured_slots.is_empty() else {}
	_check(str(insured.get("weapon_instance_id", "")) == starting_gun_id and (insured.get("fate_upgrades", []) as Array).size() == fate_capacity, "Insurance transfer lost weapon identity or fate build", failures)
	_check(ItemRegistry.grid_size_of(insured) == old_size and insurance.get_max_slots() - insurance.get_free_slots() == old_size.x * old_size.y, "保险未保留整枪足迹或实际占格不符", failures)
	_check(insured.get("fate_upgrades", []) == old_item.get("fate_upgrades", []) and insured.get("assembly_snapshot", {}) == old_item.get("assembly_snapshot", {}), "保险未保留完整命运顺序或装配", failures)
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
	var board := panel.get_build_board()
	_check(board != null and board.is_visible_in_tree(), "武器页缺少可见的正式构建板", failures)
	if board != null:
		var presentation := board.call("get_presentation_snapshot") as Dictionary
		var identity := board.get("_identity") as Label
		_check(identity != null and identity.is_visible_in_tree() and starting_gun_id.right(6).to_upper() in identity.text, "正式构建板未显示实例后缀", failures)
		_check(str(presentation.get("weapon_instance_id", "")) == starting_gun_id, "构建板未绑定原枪实例", failures)
		_check(int(presentation.get("used", -1)) == fate_capacity and int(presentation.get("slot_count", -1)) == fate_capacity, "构建板未显示全部永久刻槽", failures)
		var cards := presentation.get("cards", []) as Array
		_check(cards.size() == fate_capacity and int(presentation.get("pending_slot", 0)) == -1, "构建板槽数或稳定态有误", failures)
		for index in cards.size():
			var entry := cards[index] as Dictionary
			_check(int(entry.get("slot_index", 0)) == index + 1 and bool(entry.get("occupied", false)) and not bool(entry.get("shows_back", true)) and not bool(entry.get("pending", true)), "永久槽 %d 未按顺序显示已刻印牌面" % (index + 1), failures)

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
