extends Node
## 独立副本「撤离信号塔」成功返航的所有权交接验收。
##
## 被盯住的契约（docs/v0.1/09_技术施工_存档结算与复活.md §5.1 离场语义表）：
##   远征关卡撤离（撤离信号塔）→ 背包、主副枪、装备背包、保险格全部保留 →
##   返回塔楼主场景 99F 基地（`return_scene_path`）。
## 这条路径曾走 `Dungeon3D._finish_run(true)` 的父类成功分支：携带物被复制进
## `BaseManager.data.extraction_loot`、运行检查点被清空、场景重载 ⇒ 玩家回 99F 时
## 身上复位成初始状态，而那张「撤离待领取栏」的唯一入口 BaseMenu 不在 99F 的
## 设施目录里，物品等于被封存。
##
## 三段断言：
##   ① 撤离结算不得改动携带物，快照必须是「带标记的所有权交接」且 extraction_loot 为空
##   ② 反向对照：同一条快照去掉标记后，99F 落点不得把物品装回
##   ③ 正向：带标记时，99F 落点必须按原实例装回背包 / 枪 / 装备背包 / 快捷栏 / 保险格

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel99_3D.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/TowerDescent3D.tscn")
const TEST_PATH := "user://expedition_extraction_carry_probe.json"


func _ready() -> void:
	var failures: Array[String] = []
	var original_save_path: String = BaseManager.save_path
	var original_data: BaseData = BaseManager.data
	var original_force_failure: bool = BaseManager.force_save_failure_for_test
	_cleanup()
	BaseManager.save_path = TEST_PATH
	BaseManager.force_save_failure_for_test = false
	BaseManager.data = BaseData.new()

	var staged: Dictionary = await _stage_expedition_extraction(failures)
	if not staged.is_empty():
		await _stage_unmarked_snapshot_is_ignored(failures, staged["checkpoint"] as Dictionary)
		await _stage_base_restores_marked_carry(
			failures, staged["checkpoint"] as Dictionary, staged["carry"] as Dictionary
		)

	BaseManager.save_path = original_save_path
	BaseManager.data = original_data
	BaseManager.force_save_failure_for_test = original_force_failure
	_cleanup()
	if failures.is_empty():
		print(
			"EXPEDITION_EXTRACTION_CARRY_RETURN_OK: beacon extraction leaves inventory / "
			+ "both gun slots / equipped backpack / quick bar / insurance untouched and "
			+ "writes one marked ownership handoff with an empty extraction_loot; the 99F "
			+ "return scene restores that carry only while the marker is present"
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


## ① 独立副本成功撤离：携带物原地不动，交接快照带标记且不含待领取副本。
func _stage_expedition_extraction(failures: Array[String]) -> Dictionary:
	var expedition := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	expedition.test_mode = true
	expedition.force_extraction_settlement_for_test = true
	add_child(expedition)
	await get_tree().process_frame
	await get_tree().process_frame
	if not expedition.is_expedition():
		failures.append("测试关卡99没有以独立副本模式启动，无法验收撤离交接")
		expedition.queue_free()
		await get_tree().process_frame
		return {}
	var inventory := expedition.get_inventory_module()
	inventory.clear_all()
	inventory.add_item(ItemRegistry.get_instance().get_item("weapon_shotgun"), 1)
	inventory.add_item(ItemRegistry.get_instance().get_item("item_health_potion"), 2)
	inventory.add_item(ItemRegistry.get_instance().get_item("equipment_backpack_4"), 1)
	var backpack_slot := _find_slot(inventory, "equipment_backpack_4")
	if (
		backpack_slot < 0
		or not bool(expedition.call(
			"_equip_backpack_from_inventory",
			backpack_slot,
			inventory.get_slot(backpack_slot).get("item", {})
		))
	):
		failures.append("无法准备独立副本撤离的装备背包")
	expedition.call("_on_quick_item_assignment_requested", 0, "item_health_potion")
	# 快捷栏现在持有真实物品组；另放一组药水用于保险格验收。
	inventory.add_item(ItemRegistry.get_instance().get_item("item_health_potion"), 2)
	var insurance := expedition.get_insurance_module()
	var potion_slot := _find_slot(inventory, "item_health_potion")
	if potion_slot < 0 or not insurance.insure_item(inventory, potion_slot):
		failures.append("无法准备独立副本撤离的保险格物品")

	var carry := _capture_carry(expedition)
	for field in ["inventory_all", "weapon_ids", "backpack", "quick_slots", "insurance_all"]:
		if not _has_payload(carry[field]):
			failures.append("独立副本撤离验收的 %s 是空的，后续断言会假绿" % field)

	expedition.call("_finish_expedition_successful_extraction")
	await get_tree().process_frame

	if not _same_inventory_snapshot(carry["inventory_all"] as Array, inventory.get_slots_snapshot()):
		failures.append("独立副本成功撤离改变或清空了 I 键背包")
	if not _same_weapon_ids(carry["weapon_ids"] as Array, expedition):
		failures.append("独立副本成功撤离没有保留主副武器实例")
	if not _same_item_instance(
		carry["backpack"] as Dictionary, expedition.get_equipped_backpack_item()
	):
		failures.append("独立副本成功撤离改变或卸下了装备背包")
	if (expedition.get("_quick_item_ids") as Array) != (carry["quick_ids"] as Array):
		failures.append("独立副本成功撤离改变或清空了快捷栏索引")
	if (
		(expedition.get("_quick_inventory") as InventoryModule).get_slots_snapshot()
		!= (carry["quick_slots"] as Array)
	):
		failures.append("独立副本成功撤离改变了快捷栏真实物品、数量或位置")
	if not _same_inventory_snapshot(carry["insurance_all"] as Array, insurance.get_slots_snapshot()):
		failures.append("独立副本成功撤离改变或清空了保险格物品")

	if not BaseManager.data.extraction_loot.is_empty():
		failures.append(
			"独立副本成功撤离把携带物复制进了没有入口的撤离待领取栏：%d 件"
			% BaseManager.data.extraction_loot.size()
		)
	var snapshot := BaseManager.get_active_run_checkpoint().duplicate(true)
	if not bool(snapshot.get(Dungeon3D.SUCCESSFUL_EXTRACTION_CARRY_KEY, false)):
		failures.append("独立副本成功撤离没有写下带标记的所有权交接快照")
	if str(snapshot.get("scope", "")) != "base" or str(snapshot.get("current_room_id", "")) != "facility":
		failures.append(
			"独立副本成功撤离的交接快照没有声明 99F 基地落点：%s"
			% snapshot.get("current_room_id", "")
		)
	if not str(snapshot.get("runtime_map_id", "")).is_empty():
		failures.append("独立副本成功撤离的交接快照残留 runtime_map_id，玩家会被送回刚撤离的关卡")
	if not _same_inventory_snapshot(carry["inventory_all"] as Array, snapshot.get("inventory_slots", []) as Array):
		failures.append("独立副本成功撤离的交接快照没有带出完整背包")
	if not _same_inventory_snapshot(carry["insurance_all"] as Array, snapshot.get("insurance_slots", []) as Array):
		failures.append("独立副本成功撤离的交接快照没有带出保险格")
	var snapshot_weapon_ids: Array[String] = []
	for raw_weapon in (snapshot.get("equipped_weapon_items", []) as Array):
		if raw_weapon is Dictionary and not (raw_weapon as Dictionary).is_empty():
			snapshot_weapon_ids.append(_item_identity(raw_weapon as Dictionary))
	if snapshot_weapon_ids != (carry["weapon_ids"] as Array):
		failures.append("独立副本成功撤离的交接快照没有带出主副武器")

	expedition.queue_free()
	await get_tree().process_frame
	return {"carry": carry, "checkpoint": snapshot}


## ② 反向对照：同一条交接快照去掉标记后，99F 落点必须什么都不装。
func _stage_unmarked_snapshot_is_ignored(failures: Array[String], checkpoint: Dictionary) -> void:
	if checkpoint.is_empty():
		failures.append("反向对照拿不到交接快照")
		return
	var unmarked := checkpoint.duplicate(true)
	unmarked.erase(Dungeon3D.SUCCESSFUL_EXTRACTION_CARRY_KEY)
	if not BaseManager.set_active_run_checkpoint(unmarked, "probe_unmarked_carry"):
		failures.append("反向对照无法写入去标记快照")
		return
	var tower := TOWER_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = false
	add_child(tower)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var inventory := tower.get_inventory_module()
	# 99F 落点自带一包初始弹药，判据不能是「背包必须为空」，必须盯住
	# 「交接快照里那批物品一件都不许出现在落点」。
	var landed_ids := _slot_item_ids(inventory)
	for item_id in _snapshot_item_ids(checkpoint):
		if item_id in landed_ids:
			failures.append(
				"去掉交接标记后 99F 落点仍然按交接快照装回了 %s：%s"
				% [item_id, str(landed_ids)]
			)
	if not tower.get_equipped_backpack_item().is_empty():
		failures.append("去掉交接标记后 99F 落点仍然装上了装备背包")
	if not (tower.get("_quick_inventory") as InventoryModule).get_occupied_slots().is_empty():
		failures.append("去掉交接标记后 99F 落点仍然装了快捷栏物品")
	if not tower.get_insurance_module().get_occupied_slots().is_empty():
		failures.append("去掉交接标记后 99F 落点仍然装了保险格物品")
	tower.queue_free()
	await get_tree().process_frame


## ③ 正向：带标记的交接快照必须按原实例装回 99F 玩家。
func _stage_base_restores_marked_carry(
	failures: Array[String], checkpoint: Dictionary, carry: Dictionary
) -> void:
	if checkpoint.is_empty():
		failures.append("正向段拿不到交接快照")
		return
	var marked := checkpoint.duplicate(true)
	marked[Dungeon3D.SUCCESSFUL_EXTRACTION_CARRY_KEY] = true
	if not BaseManager.set_active_run_checkpoint(marked, "probe_marked_carry"):
		failures.append("正向段无法写回带标记的交接快照")
		return
	var tower := TOWER_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = false
	add_child(tower)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if not _same_inventory_snapshot(carry["inventory_all"] as Array, tower.get_inventory_module().get_slots_snapshot()):
		failures.append("99F 落点没有按原实例装回背包携带物")
	if not _same_item_instance(carry["backpack"] as Dictionary, tower.get_equipped_backpack_item()):
		failures.append("99F 落点没有装回装备背包")
	if not _same_weapon_ids(carry["weapon_ids"] as Array, tower):
		failures.append("99F 落点没有装回主副武器")
	if (
		(tower.get("_quick_inventory") as InventoryModule).get_slots_snapshot()
		!= (carry["quick_slots"] as Array)
	):
		failures.append("99F 落点没有装回快捷栏真实物品")
	if not _same_inventory_snapshot(carry["insurance_all"] as Array, tower.get_insurance_module().get_slots_snapshot()):
		failures.append("99F 落点没有装回保险格物品")
	# 交接只认所有权：落点世界必须是塔楼自己生成的，不能被关卡世界状态顶掉。
	if str(tower.get("_current_room_id")) != "facility":
		failures.append("99F 落点没有停在基地房间：%s" % str(tower.get("_current_room_id")))
	if tower.is_expedition():
		failures.append("99F 落点被错误地当成了独立副本场景")
	tower.queue_free()
	await get_tree().process_frame


func _capture_carry(scene: TowerDescent3D) -> Dictionary:
	var inventory := scene.get_inventory_module()
	var quick := scene.get("_quick_inventory") as InventoryModule
	var insurance := scene.get_insurance_module()
	var weapon_ids: Array[String] = []
	for slot_index in range(2):
		var weapon := scene.player.get_equipped_weapon_item_for_slot(slot_index)
		if not weapon.is_empty():
			weapon_ids.append(_item_identity(weapon))
	return {
		"inventory_all": inventory.get_slots_snapshot(),
		"weapon_ids": weapon_ids,
		"backpack": scene.get_equipped_backpack_item(),
		"quick_ids": (scene.get("_quick_item_ids") as Array).duplicate(),
		"quick_slots": quick.get_slots_snapshot(),
		"insurance_all": insurance.get_slots_snapshot(),
	}


func _has_payload(value: Variant) -> bool:
	if value is Array:
		for entry in value as Array:
			if typeof(entry) == TYPE_DICTIONARY:
				var item: Variant = (entry as Dictionary).get("item", {})
				if item is Dictionary and not (item as Dictionary).is_empty():
					return true
			elif not str(entry).is_empty():
				return true
		return false
	if value is Dictionary:
		return not (value as Dictionary).is_empty()
	return false


func _slot_item_ids(inventory: InventoryModule) -> Array[String]:
	var ids: Array[String] = []
	for entry in inventory.get_occupied_slots():
		ids.append(str((entry.get("item", {}) as Dictionary).get("id", "")))
	return ids


## 交接快照里出现过的全部物品 ID（背包 / 快捷栏 / 保险格 / 装备背包 / 主副枪）。
func _snapshot_item_ids(snapshot: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for key in ["inventory_slots", "quick_item_slots", "insurance_slots"]:
		for entry in (snapshot.get(key, []) as Array):
			if not entry is Dictionary:
				continue
			var item: Variant = (entry as Dictionary).get("item", {})
			if item is Dictionary and not (item as Dictionary).is_empty():
				ids.append(str((item as Dictionary).get("id", "")))
	var backpack: Variant = snapshot.get("equipped_backpack_item", {})
	if backpack is Dictionary and not (backpack as Dictionary).is_empty():
		ids.append(str((backpack as Dictionary).get("id", "")))
	for raw_weapon in (snapshot.get("equipped_weapon_items", []) as Array):
		if raw_weapon is Dictionary and not (raw_weapon as Dictionary).is_empty():
			ids.append(str((raw_weapon as Dictionary).get("id", "")))
	return ids


func _same_weapon_ids(before: Array, scene: TowerDescent3D) -> bool:
	var after: Array[String] = []
	for slot_index in range(2):
		var weapon := scene.player.get_equipped_weapon_item_for_slot(slot_index)
		if not weapon.is_empty():
			after.append(_item_identity(weapon))
	if before.size() != after.size():
		return false
	for index in before.size():
		if str(before[index]) != after[index]:
			return false
	return true


func _find_slot(inventory: InventoryModule, item_id: String) -> int:
	for entry in inventory.get_occupied_slots():
		if str((entry.get("item", {}) as Dictionary).get("id", "")) == item_id:
			return int(entry.get("slot", -1))
	return -1


## 逐格比对整份槽位快照（含空格）：位置、数量与物品身份三者都必须一致。
func _same_inventory_snapshot(before: Array, after: Array) -> bool:
	if before.size() != after.size():
		return false
	for index in before.size():
		var a := before[index] as Dictionary
		var b := after[index] as Dictionary
		var a_item := a.get("item", {}) as Dictionary
		var b_item := b.get("item", {}) as Dictionary
		if a_item.is_empty() != b_item.is_empty():
			return false
		if a_item.is_empty():
			continue
		if int(a.get("count", 0)) != int(b.get("count", 0)):
			return false
		if not _same_item_instance(a_item, b_item):
			return false
	return true


func _same_item_instance(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("id", "")) != str(b.get("id", "")):
		return false
	return _item_identity(a) == _item_identity(b)


func _item_identity(item: Dictionary) -> String:
	return str(item.get(
		"weapon_instance_id", item.get("item_instance_id", item.get("id", ""))
	))


func _cleanup() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", TEST_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
