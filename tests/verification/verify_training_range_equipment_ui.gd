extends Node
## 靶场「完整装备界面 + 完整背包界面」验收。
##
## 靶场必须复用**外面局内同一套组件**（InventoryUI / WeaponAssemblyTreePanel），
## 而不是自建精简版 —— 测试环境的价值就在于布局、操作与实战逐块一致。
##
## 覆盖：两个面板存在且能打开、背包容量与外面一致、槽位往返事务（装/卸/丢）、
## 换枪后装备界面跟随新武器树、保险柜在靶场标注不可用、进出清空契约仍成立。

const OUTSIDE_BACKPACK_CAPACITY := 40


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	var scene := load("res://scenes/TrainingRange3D.tscn") as PackedScene
	if scene == null:
		_finish(["TrainingRange3D scene does not load"])
		return
	var training := scene.instantiate() as TrainingRange3D
	training.test_mode = true
	add_child(training)
	await get_tree().process_frame
	await get_tree().physics_frame

	_check_panels_exist(training, failures)
	await _check_backpack_opens(training, failures)
	_check_capacity_matches_outside(training, failures)
	await _check_slot_round_trip(training, failures)
	await _check_weapon_panel_tracks_tree(training, failures)
	_check_bullet_swap_locked(training, failures)
	await _check_drop_spawns_ground_loot(training, failures)
	if not training.is_base_data_unchanged():
		failures.append("equipment/backpack UI mutated BaseData")
	training.queue_free()
	await get_tree().process_frame
	_finish(failures)


func _check_panels_exist(training: TrainingRange3D, failures: Array[String]) -> void:
	var snapshot := training.get_training_snapshot()
	if not bool(snapshot.get("has_inventory_ui", false)):
		failures.append("training range has no InventoryUI (complete backpack interface)")
	if not bool(snapshot.get("has_weapon_panel", false)):
		failures.append("training range has no WeaponAssemblyTreePanel (complete equipment interface)")
	if not bool(snapshot.get("has_insurance", false)):
		failures.append("training range has no insurance module; the backpack layout would differ from outside")


func _check_backpack_opens(training: TrainingRange3D, failures: Array[String]) -> void:
	var ui := training.get("_inventory_ui") as InventoryUI
	if ui == null:
		return
	ui.set_inventory_panel_open(true)
	await get_tree().process_frame
	if not ui.is_inventory_open():
		failures.append("InventoryUI cannot be opened in the training range")
	# 保险柜区必须被标注为不可用（靶场没有撤离流程）。
	var label := ui.get("insurance_label") as Label
	if label == null:
		failures.append("InventoryUI has no insurance label to annotate")
	elif not label.text.contains("不可用"):
		failures.append("insurance area is not marked unavailable in the training range: %s" % label.text)
	ui.set_inventory_panel_open(false)
	await get_tree().process_frame


func _check_capacity_matches_outside(training: TrainingRange3D, failures: Array[String]) -> void:
	var inventory := training.get_inventory()
	if inventory == null:
		failures.append("training range has no backpack module")
		return
	if inventory.get_capacity() != OUTSIDE_BACKPACK_CAPACITY:
		failures.append(
			"backpack capacity %d does not match the outside run (%d); layout would not reflect combat"
			% [inventory.get_capacity(), OUTSIDE_BACKPACK_CAPACITY]
		)


## 槽位往返：军械库装枪 → 卸到背包 → 经背包界面装回武器槽。
## 这条链验证的是「背包界面真的驱动了装备」，而不只是画了格子。
func _check_slot_round_trip(training: TrainingRange3D, failures: Array[String]) -> void:
	var inventory := training.get_inventory()
	var player := training.player
	if inventory == null or player == null:
		return
	if not training.equip_combination_for_test("bp_rifle", "mod_bullet_standard"):
		failures.append("cannot equip a rifle to start the slot round trip")
		return
	if player.get_equipped_weapon_instance() == null:
		failures.append("equipping a rifle did not produce a weapon instance")
		return
	# 卸下到背包（外面同款事务：先卸，再写入空格，失败则回滚）。
	var unequipped: Dictionary = player.unequip_weapon_item_from_slot(0)
	if not bool(unequipped.get("success", false)):
		failures.append("unequip_weapon_item_from_slot failed: %s" % str(unequipped.get("reason", "")))
		return
	var weapon_item := unequipped.get("old_item", {}) as Dictionary
	if weapon_item.is_empty():
		failures.append("unequip returned no weapon item")
		return
	if not inventory.put_item_in_empty_slot(0, weapon_item, 1):
		failures.append("cannot place the unequipped weapon into the backpack")
		return
	# 经背包界面 handler 装回主武器槽。
	training.call("_on_weapon_slot_equip_requested", 0, 0)
	await get_tree().process_frame
	if player.get_equipped_weapon_instance() == null:
		failures.append("equipping from the backpack did not restore a weapon instance")
	if not inventory.get_slot(0).is_empty():
		failures.append("backpack slot was not consumed after equipping from it")


## 2026-10-19：手动更换总闸关闭，靶场背包也不能把子弹模块装到枪上。
## 军械库的弹药选择是另一条链（整枪重新装配），不在本用例的禁止范围内。
func _check_bullet_swap_locked(training: TrainingRange3D, failures: Array[String]) -> void:
	var inventory := training.get_inventory()
	var player := training.player
	if inventory == null or player == null:
		return
	var bullet_item := ItemRegistry.get_instance().get_item("mod_bullet_sticky")
	if bullet_item.is_empty():
		failures.append("cannot load mod_bullet_sticky to test the training-range lock")
		return
	inventory.add_item(bullet_item, 1)
	var source_index := -1
	for index in inventory.get_capacity():
		var slot := inventory.get_slot(index)
		if slot.is_empty():
			continue
		if str((slot.get("item", {}) as Dictionary).get("id", "")) == "mod_bullet_sticky":
			source_index = index
			break
	if source_index < 0:
		failures.append("cannot place a bullet module in the training-range backpack")
		return
	var before_id := str(player.get_equipped_bullet_item_for_slot(0).get("id", ""))
	training.call("_on_bullet_module_install_requested", source_index, 0)
	if str(player.get_equipped_bullet_item_for_slot(0).get("id", "")) != before_id:
		failures.append("training range still swaps bullet modules from the backpack")
	if _count_item(inventory, "mod_bullet_sticky") != 1:
		failures.append("training-range bullet module was consumed by the rejected swap")


func _count_item(inventory: InventoryModule, item_id: String) -> int:
	var total := 0
	for index in inventory.get_capacity():
		var slot := inventory.get_slot(index)
		if slot.is_empty():
			continue
		if str((slot.get("item", {}) as Dictionary).get("id", "")) == item_id:
			total += int(slot.get("count", 0))
	return total


## 换枪会整体替换 weapon_tree；装备界面必须跟着换，否则显示上一把枪的构筑。
func _check_weapon_panel_tracks_tree(training: TrainingRange3D, failures: Array[String]) -> void:
	if not training.equip_combination_for_test("bp_pistol", "mod_bullet_standard"):
		failures.append("cannot switch weapons to test the equipment panel binding")
		return
	await get_tree().process_frame
	if not bool(training.get_training_snapshot().get("weapon_panel_tracks_tree", false)):
		failures.append(
			"equipment panel still points at the previous weapon tree after switching guns"
		)


## 丢弃必须落在地上（可捡回），而不是静默消失。
func _check_drop_spawns_ground_loot(training: TrainingRange3D, failures: Array[String]) -> void:
	var drops := training.get_node_or_null("Drops") as Node3D
	if drops == null:
		failures.append("training range has no Drops container for ground loot")
		return
	var before := drops.get_child_count()
	training.call("_on_equipped_weapon_drop_requested", 0)
	await get_tree().process_frame
	if drops.get_child_count() <= before:
		failures.append("dropping an equipped weapon did not spawn ground loot")


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print(
			"TRAINING_RANGE_EQUIPMENT_UI_OK: InventoryUI and WeaponAssemblyTreePanel reused from the run, backpack capacity %d matches outside, slot round trip works, bullet swap locked, panel follows weapon tree, drop spawns ground loot, BaseData untouched"
			% OUTSIDE_BACKPACK_CAPACITY
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
