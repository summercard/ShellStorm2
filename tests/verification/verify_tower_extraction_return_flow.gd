extends Node

const MANAGER_SCRIPT := preload("res://src/base/BaseManager.gd")
const TEST_PATH := "user://tower_extraction_return_probe.json"


func _ready() -> void:
	var failures: Array[String] = []
	await _verify_cleared_room_is_not_restored_when_door_opens(failures)
	await _verify_success_returns_inside_99f_with_items(failures)
	_verify_death_insurance_persists(failures)
	_verify_legacy_hidden_insurance_migrates(failures)
	await _verify_real_99f_spawn_restores_insurance_slots(failures)
	_cleanup()
	if failures.is_empty():
		print("TOWER_EXTRACTION_RETURN_OK: cleared rooms survive door streaming; extraction starts a fresh seeded route/minimap while retained ownership and death insurance return remain intact")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_cleared_room_is_not_restored_when_door_opens(failures: Array[String]) -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 937114
	add_child(tower)
	await get_tree().process_frame
	await get_tree().process_frame
	if not tower.generate_through_floor_for_test(98):
		failures.append("无法准备清房开门状态覆盖回归的98F")
		tower.queue_free()
		await get_tree().process_frame
		return
	var combat_room: DungeonRoom3D = null
	var target_room_id := ""
	for room_value in (tower.get("_rooms") as Array):
		var candidate := room_value as DungeonRoom3D
		if candidate == null or candidate.room_type not in Dungeon3D.HOSTILE_ROOM_TYPES:
			continue
		for target_value in candidate.door_targets.values():
			var target_id := str(target_value)
			if not target_id.is_empty():
				combat_room = candidate
				target_room_id = target_id
				break
		if combat_room != null:
			break
	if combat_room == null or target_room_id.is_empty():
		failures.append("98F没有可用于清房开门状态覆盖回归的战斗房/门")
		tower.queue_free()
		await get_tree().process_frame
		return
	tower.call("_on_room_entered", combat_room)
	for enemy_value in (tower.get("_enemy_nodes_by_room") as Dictionary).get(combat_room.room_id, []):
		var enemy := enemy_value as Enemy3D
		if enemy != null and is_instance_valid(enemy):
			enemy.free()
	(tower.get("_enemy_nodes_by_room") as Dictionary)[combat_room.room_id] = []
	(tower.get("_alive_by_room") as Dictionary)[combat_room.room_id] = 0
	combat_room.cleared = true
	combat_room.ensure_detail_built()
	var light_switch := combat_room.get("_light_switch") as RoomLightSwitch3D
	if light_switch == null:
		failures.append("清房开门回归房没有可控灯光")
	else:
		light_switch.set_light_on(true)
	# 模拟战斗中较早一次自动存档留下的旧快照。开门只应刷新流送，
	# 不得把这个旧快照重新写回仍处于 ACTIVE 的当前房。
	(tower.get("_segment_runtime_state") as Dictionary)[combat_room.room_id] = {
		"visited": true,
		"cleared": false,
		"room_light_on": false,
		"enemies": [],
		"ground_items": [],
		"room_keys": [],
		"containers": {},
		"alive_count": 7,
		"wave_queue": [],
		"wave_number": 1,
		"wave_total": 1,
	}
	tower.set("_room_key_count", 99)
	if not tower.try_open_room_door(target_room_id):
		failures.append("清房后无法开启下一扇门")
	if not combat_room.cleared:
		failures.append("开门流送把已清空房间覆盖回未清空状态")
	if light_switch != null and not light_switch.is_light_on():
		failures.append("开门流送把已开启的房间灯覆盖回关闭状态")
	if int((tower.get("_alive_by_room") as Dictionary).get(combat_room.room_id, -1)) != 0:
		failures.append("开门流送恢复了旧敌人计数")
	tower.queue_free()
	await get_tree().process_frame


func _verify_success_returns_inside_99f_with_items(failures: Array[String]) -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 937115
	add_child(tower)
	await get_tree().process_frame
	await get_tree().process_frame
	if not tower.generate_through_floor_for_test(98):
		failures.append("无法准备成功撤离后的新战局路线回归")
	var previous_run_seed := int(tower.run_seed)
	var previous_layout_id := str(
		((tower.get("_floor_plan_snapshots") as Dictionary).get(2, {}) as Dictionary).get("layout_id", "")
	)
	var previous_combat_room_id := ""
	for room_id_value in (tower.get("_floor_room_ids") as Dictionary).get(2, []):
		var room_id := str(room_id_value)
		if room_id != "floor_01_entry":
			previous_combat_room_id = room_id
			break
	if not previous_combat_room_id.is_empty():
		tower.minimap.reveal_room(previous_combat_room_id)
		(tower.get("_segment_runtime_state") as Dictionary)[previous_combat_room_id] = {
			"visited": true, "cleared": true, "room_light_on": true,
			"enemies": [], "ground_items": [], "room_keys": [], "containers": {},
			"alive_count": 0, "wave_queue": [], "wave_number": 1, "wave_total": 1,
		}
	var inventory := tower.get_inventory_module()
	inventory.clear_all()
	inventory.add_item(ItemRegistry.get_instance().get_item("weapon_shotgun"), 1)
	inventory.add_item(ItemRegistry.get_instance().get_item("item_health_potion"), 2)
	inventory.add_item(ItemRegistry.get_instance().get_item("equipment_backpack_4"), 1)
	var backpack_slot := _find_slot(inventory, "equipment_backpack_4")
	if backpack_slot < 0 or not bool(tower.call("_equip_backpack_from_inventory", backpack_slot, inventory.get_slot(backpack_slot).get("item", {}))):
		failures.append("无法准备成功撤离装备背包")
	tower.call("_on_quick_item_assignment_requested", 0, "item_health_potion")
	# 快捷栏现在持有真实物品组；另放一组药水用于保险格验收。
	inventory.add_item(ItemRegistry.get_instance().get_item("item_health_potion"), 2)
	var insurance := tower.get_insurance_module()
	var potion_slot := _find_slot(inventory, "item_health_potion")
	if potion_slot < 0 or not insurance.insure_item(inventory, potion_slot):
		failures.append("无法准备保险格测试物品")
	var inventory_before := inventory.get_occupied_slots()
	var insured_before := insurance.get_all_insured_items()
	if insured_before.size() != 1 or int(insured_before[0].get("count", 0)) != 2:
		failures.append("保险格没有保留可堆叠物的完整数量")
	var backpack_before := tower.get_equipped_backpack_item()
	var quick_items_before := (tower.get("_quick_item_ids") as Array).duplicate()
	var quick_slots_before := (tower.get("_quick_inventory") as InventoryModule).get_slots_snapshot()
	var weapon_ids_before: Array[String] = []
	for slot_index in range(2):
		var weapon := tower.player.get_equipped_weapon_item_for_slot(slot_index)
		if not weapon.is_empty():
			weapon_ids_before.append(str(weapon.get("weapon_instance_id", "")))
	tower.call("_finish_run", true)
	await get_tree().process_frame
	if str(tower.get("_current_room_id")) != "facility":
		failures.append("成功撤离没有返回99层基地房间")
	var returned_facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	var returned_rooftop_door := tower.find_child("BaseRooftopTransitDoor", true, false) as RoomDoor3D
	var returned_west_door := returned_facility.get_door_node("west") if returned_facility != null else null
	var returned_east_door := returned_facility.get_door_node("east") if returned_facility != null else null
	if (
		returned_rooftop_door == null or returned_rooftop_door.is_open
		or returned_west_door == null or returned_west_door.is_open
		or returned_east_door == null or returned_east_door.is_open
	):
		failures.append("成功撤离返回基地后99F三扇门没有全部关闭")
	var returned_world := tower.get_tower_snapshot()
	if (
		(returned_world.get("generated_floor_indices", []) as Array) != [0]
		or int(returned_world.get("instantiated_room_count", -1)) != 3
		or int(returned_world.get("boss_descent_gate_count", -1)) != 0
		or int(returned_world.get("airlock_front_gate_count", -1)) != 0
		or str(tower.get("_active_airlock_room_id")) != ""
		or bool(tower.get("_initial_loop_gate_armed"))
		or bool(tower.get("_initial_loop_gate_sealed"))
	):
		failures.append("成功撤离后战局没有销毁并恢复为未激活的初始状态")
	if bool(tower.get("_completed")):
		failures.append("成功返航后仍处于锁死的行动完成状态")
	var next_layout_id := str(
		((tower.get("_floor_plan_snapshots") as Dictionary).get(2, {}) as Dictionary).get("layout_id", "")
	)
	if int(tower.run_seed) == previous_run_seed:
		failures.append("成功返航后新战局仍复用上一局run_seed")
	if next_layout_id.is_empty() or next_layout_id == previous_layout_id:
		failures.append("成功返航后98F仍复用上一局layout_id/路线")
	var minimap_snapshot := tower.minimap.get_snapshot()
	if (
		int(minimap_snapshot.get("revealed_count", -1)) != 1
		or str(minimap_snapshot.get("current_room_id", "")) != "facility"
	):
		failures.append("成功返航后小地图没有清除上一局探索路径：%s" % minimap_snapshot)
	if (
		not previous_combat_room_id.is_empty()
		and (tower.get("_segment_runtime_state") as Dictionary).has(previous_combat_room_id)
	):
		failures.append("成功返航后仍残留上一局战斗房运行快照")
	if tower.seed_label.text != "塔楼种子 %d" % int(tower.run_seed):
		failures.append("成功返航后HUD仍显示上一局种子")
	if not _same_inventory_instances(inventory_before, inventory.get_occupied_slots()):
		failures.append("成功撤离改变或清空了I键背包战利品")
	if not _same_insurance_instances(insured_before, insurance.get_all_insured_items()):
		failures.append("成功撤离改变或清空了保险格物品")
	if not _same_item_instance(backpack_before, tower.get_equipped_backpack_item()):
		failures.append("成功撤离改变或卸下了装备背包")
	if (tower.get("_quick_item_ids") as Array) != quick_items_before:
		failures.append("成功撤离改变或清空了3/4快捷栏索引")
	if (tower.get("_quick_inventory") as InventoryModule).get_slots_snapshot() != quick_slots_before:
		failures.append("成功撤离改变了快捷栏真实物品、数量或位置")
	var weapon_ids_after: Array[String] = []
	for slot_index in range(2):
		var weapon := tower.player.get_equipped_weapon_item_for_slot(slot_index)
		if not weapon.is_empty():
			weapon_ids_after.append(str(weapon.get("weapon_instance_id", "")))
	if weapon_ids_after != weapon_ids_before:
		failures.append("成功撤离没有保留主副武器实例")
	tower.queue_free()
	await get_tree().process_frame


func _verify_death_insurance_persists(failures: Array[String]) -> void:
	_cleanup()
	var manager := MANAGER_SCRIPT.new()
	manager.save_path = TEST_PATH
	manager.data = BaseData.new()
	var inventory := InventoryModule.new(4)
	var insurance := InsuranceModule.new(2)
	var insured_weapon := WeaponInstance.ensure_weapon_item(ItemRegistry.get_instance().get_item("weapon_pistol"))
	var insured_id := str(insured_weapon.get("weapon_instance_id", ""))
	inventory.add_item(insured_weapon, 1)
	if not insurance.insure_item(inventory, 0):
		failures.append("死亡保险测试无法存入保险格")
	inventory.add_item(ItemRegistry.get_instance().get_item("item_health_potion"), 3)
	var insured_stack_slot := _find_slot(inventory, "item_health_potion")
	if insured_stack_slot < 0 or not insurance.insure_item(inventory, insured_stack_slot):
		failures.append("死亡保险测试无法存入堆叠物")
	inventory.add_item(ItemRegistry.get_instance().get_item("weapon_shotgun"), 1)
	var settlement := DeathSettlementModule.new()
	settlement.set_loss_ratio(1.0)
	var result := settlement.process_death_settlement(inventory, insurance)
	var quick_inventory := InventoryModule.new(2)
	quick_inventory.add_item(ItemRegistry.get_instance().get_item("item_battery_l"), 2)
	var quick_result := settlement.process_death_settlement(quick_inventory, null)
	if (result.get("insurance_saved", []) as Array).size() != 2:
		failures.append("死亡结算没有判定保险格保留")
	if (result.get("dropped", []) as Array).size() != 1:
		failures.append("死亡结算没有区分未保险物品")
	if (quick_result.get("dropped", []) as Array).size() != 1 or quick_inventory.get_used_slots() != 0:
		failures.append("死亡结算没有把真实快捷槽按普通未保险携带物处理")
	var stored := manager.store_insurance_return_items(result.get("insurance_saved", []), "txn_death_insurance") as Dictionary
	if not bool(stored.get("success", false)) or manager.data.pending_insurance_slots.size() != 2:
		failures.append("死亡保险物没有写入专用基地保险格中转集合")
	elif not manager.data.extraction_loot.is_empty():
		failures.append("死亡保险物仍被错误混入撤离待领取战利品")
	else:
		var returned_weapon := _find_wrapped_item(manager.data.pending_insurance_slots, "weapon_pistol")
		var returned_stack := _find_wrapped_item(manager.data.pending_insurance_slots, "item_health_potion")
		if str(returned_weapon.get("weapon_instance_id", "")) != insured_id:
			failures.append("死亡保险返还丢失了原枪械实例ID")
		if int(returned_stack.get("count", 0)) != 3:
			failures.append("死亡保险返还丢失了堆叠数量")
		var checkpoint := {
			"valid": true,
			"schema": "runtime_player_state_v2",
			"checkpoint_id": "runtime_player_state_v2",
			"layout_id": "runtime_player_state_v2",
			"scope": "base",
			"insurance_capacity": 2,
			"insurance_slots": manager.get_pending_insurance_slots(),
		}
		manager.force_save_failure_for_test = true
		if manager.commit_pending_insurance_to_runtime(checkpoint):
			failures.append("保险中转在强制写盘失败时错误地报告交接成功")
		elif manager.data.pending_insurance_slots.size() != 2 or not manager.data.active_run_snapshot.is_empty():
			failures.append("保险中转写盘失败后没有完整回滚中转集合与运行快照")
		manager.force_save_failure_for_test = false
		if not manager.commit_pending_insurance_to_runtime(checkpoint):
			failures.append("保险中转集合无法与基地运行态检查点原子交接")
		elif not manager.data.pending_insurance_slots.is_empty():
			failures.append("基地检查点接管后仍残留保险中转副本")
		elif (manager.data.active_run_snapshot.get("insurance_slots", []) as Array).size() != 2:
			failures.append("基地检查点没有接管完整保险格快照")
	manager.free()


func _verify_real_99f_spawn_restores_insurance_slots(failures: Array[String]) -> void:
	_cleanup()
	var original_path: String = BaseManager.save_path
	var original_data: BaseData = BaseManager.data
	BaseManager.save_path = TEST_PATH
	BaseManager.data = BaseData.new()
	BaseManager.data.tutorial_completed = true
	var staged_inventory := InventoryModule.new(4)
	var staged_insurance := InsuranceModule.new(2)
	staged_inventory.add_item(ItemRegistry.get_instance().get_item("item_health_potion"), 4)
	staged_inventory.add_item(ItemRegistry.get_instance().get_item("item_battery_l"), 2)
	if not staged_insurance.insure_item_to_slot(staged_inventory, 0, 0):
		failures.append("真实99F恢复测试无法准备保险格0")
	if not staged_insurance.insure_item_to_slot(staged_inventory, 1, 1):
		failures.append("真实99F恢复测试无法准备保险格1")
	var entries := staged_insurance.get_all_insured_items()
	if not bool(BaseManager.store_insurance_return_items(entries, "txn_real_99f_restore").get("success", false)):
		failures.append("真实99F恢复测试无法写入死亡保险中转")
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = false
	tower.run_seed_override = 937115
	add_child(tower)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var restored := tower.get_insurance_module().get_slots_snapshot()
	if restored.size() != 2:
		failures.append("死亡返回的真实99F场景没有创建两个保险格")
	else:
		if str(((restored[0] as Dictionary).get("item", {}) as Dictionary).get("id", "")) != "item_health_potion":
			failures.append("死亡返回99F后保险格0的原物品/原位置没有恢复")
		if int((restored[0] as Dictionary).get("count", 0)) != 4:
			failures.append("死亡返回99F后保险格堆叠数量没有恢复")
		if str(((restored[1] as Dictionary).get("item", {}) as Dictionary).get("id", "")) != "item_battery_l":
			failures.append("死亡返回99F后保险格1的原物品/原位置没有恢复")
	if not BaseManager.data.pending_insurance_slots.is_empty():
		failures.append("真实99F恢复后长期中转集合没有原子清空")
	var saved_slots := BaseManager.data.active_run_snapshot.get("insurance_slots", []) as Array
	if saved_slots.size() != 2 or (saved_slots[0] as Dictionary).is_empty() or (saved_slots[1] as Dictionary).is_empty():
		failures.append("真实99F恢复后的运行态检查点没有持久化两个保险格")
	tower.queue_free()
	await get_tree().process_frame
	BaseManager.save_path = original_path
	BaseManager.data = original_data
	_cleanup()


func _verify_legacy_hidden_insurance_migrates(failures: Array[String]) -> void:
	var manager := MANAGER_SCRIPT.new()
	manager.save_path = TEST_PATH
	manager.data = BaseData.new()
	manager.data.extraction_loot = [{
		"id": "item_health_potion",
		"name": "治疗药水",
		"count": 3,
		"returned_by_insurance": true,
		"insurance_slot": 1,
	}]
	if not bool(manager.call("_migrate_legacy_insurance_returns")):
		failures.append("1.7隐藏在撤离待领取栏中的保险物没有触发迁移")
	elif not manager.data.extraction_loot.is_empty():
		failures.append("1.7保险物迁移后仍残留在撤离待领取栏")
	elif manager.data.pending_insurance_slots.size() != 1:
		failures.append("1.7保险物没有迁入专用保险中转集合")
	else:
		var entry := manager.data.pending_insurance_slots[0] as Dictionary
		if int(entry.get("insurance_slot", -1)) != 1 or int(entry.get("count", 0)) != 3:
			failures.append("1.7保险物迁移丢失原保险格位置或堆叠数量")
	manager.free()


func _find_slot(inventory: InventoryModule, item_id: String) -> int:
	for entry in inventory.get_occupied_slots():
		if str((entry.get("item", {}) as Dictionary).get("id", "")) == item_id:
			return int(entry.get("slot", -1))
	return -1


func _find_owned_item(items: Array, item_id: String) -> Dictionary:
	for raw_item in items:
		if raw_item is Dictionary and str((raw_item as Dictionary).get("id", "")) == item_id:
			return (raw_item as Dictionary).duplicate(true)
	return {}


func _find_wrapped_item(entries: Array, item_id: String) -> Dictionary:
	for raw_entry in entries:
		if not raw_entry is Dictionary:
			continue
		var entry := raw_entry as Dictionary
		var item := (entry.get("item", {}) as Dictionary).duplicate(true)
		if str(item.get("id", "")) == item_id:
			item["count"] = int(entry.get("count", item.get("count", 1)))
			return item
	return {}


func _same_inventory_instances(before: Array[Dictionary], after: Array[Dictionary]) -> bool:
	if before.size() != after.size():
		return false
	for index in before.size():
		var a := before[index]
		var b := after[index]
		if int(a.get("slot", -1)) != int(b.get("slot", -1)) or int(a.get("count", 0)) != int(b.get("count", 0)):
			return false
		if not _same_item_instance(a.get("item", {}) as Dictionary, b.get("item", {}) as Dictionary):
			return false
	return true


func _same_insurance_instances(before: Array[Dictionary], after: Array[Dictionary]) -> bool:
	if before.size() != after.size():
		return false
	for index in before.size():
		if int(before[index].get("count", 0)) != int(after[index].get("count", 0)):
			return false
		var a_item := before[index].get("item", {}) as Dictionary
		var b_item := after[index].get("item", {}) as Dictionary
		if str(a_item.get("weapon_instance_id", a_item.get("item_instance_id", a_item.get("id", "")))) != str(b_item.get("weapon_instance_id", b_item.get("item_instance_id", b_item.get("id", "")))):
			return false
	return true


func _same_item_instance(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("id", "")) != str(b.get("id", "")):
		return false
	return str(a.get("weapon_instance_id", a.get("item_instance_id", ""))) == str(b.get("weapon_instance_id", b.get("item_instance_id", "")))


func _cleanup() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", TEST_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
