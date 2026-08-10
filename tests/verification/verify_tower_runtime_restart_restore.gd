extends Node

const TEST_PATH := "user://tower_runtime_restart_probe.json"


func _ready() -> void:
	var failures: Array[String] = []
	var original_path: String = BaseManager.save_path
	var original_data: BaseData = BaseManager.data
	_cleanup()
	BaseManager.save_path = TEST_PATH
	BaseManager.data = BaseData.new()
	BaseManager.data.tutorial_completed = true

	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var first := scene.instantiate() as TowerDescent3D
	first.test_mode = false
	add_child(first)
	await get_tree().process_frame
	await get_tree().process_frame
	var start_room := (first.get("_room_by_id") as Dictionary).get("start") as DungeonRoom3D
	first.player.global_position = start_room.global_position + Vector3(0.0, 0.05, 0.0)
	first.call("_on_room_entered", start_room)
	await get_tree().physics_frame
	var inventory := first.get_inventory_module()
	inventory.clear_all()
	var backpack := ItemRegistry.get_instance().get_item("equipment_backpack_2")
	first.player.equip_backpack_item(backpack)
	inventory.set_capacity(14)
	inventory.add_item(ItemRegistry.get_instance().get_item("item_health_potion"), 2)
	first.player.clear_all_equipped_weapons()
	var pistol := ItemRegistry.get_instance().get_item("weapon_pistol")
	var shotgun := ItemRegistry.get_instance().get_item("weapon_shotgun")
	first.player.equip_weapon_item_to_slot(pistol, 0)
	first.player.equip_weapon_item_to_slot(shotgun, 1)
	first.player.switch_weapon_slot(1)
	var expected_main_id := first.player.get_equipped_weapon_instance_id_for_slot(0)
	var expected_side_id := first.player.get_equipped_weapon_instance_id_for_slot(1)
	first.get("_insurance").insure_item_direct(ItemRegistry.get_instance().get_item("item_battery_s"))
	var flashlight := first.player.get_node_or_null("PlayerFlashlight3D")
	flashlight.set_charge_ratio(0.37)
	if not BaseManager.flush_runtime_checkpoint("test_restart_boundary"):
		failures.append("场景级运行态快照写入失败")
	first.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# 丢弃内存中的 BaseData，再从磁盘读取，模拟完整进程重启。
	BaseManager.data = BaseData.new()
	BaseManager.load_base()
	var second := scene.instantiate() as TowerDescent3D
	second.test_mode = false
	add_child(second)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var restored_inventory := second.get_inventory_module()
	if restored_inventory.get_capacity() != 14 or restored_inventory.get_item_count("item_health_potion") != 2:
		failures.append("重建塔楼后背包容量、格位或堆叠没有恢复")
	if second.player.get_equipped_weapon_instance_id_for_slot(0) != expected_main_id:
		failures.append("主武器稳定实例 ID 没有跨重启恢复")
	if second.player.get_equipped_weapon_instance_id_for_slot(1) != expected_side_id:
		failures.append("副武器稳定实例 ID 没有跨重启恢复")
	if second.player.get_active_weapon_slot() != 1:
		failures.append("当前激活武器槽没有恢复")
	if str(second.player.get_equipped_backpack_item().get("id", "")) != "equipment_backpack_2":
		failures.append("已装备背包没有恢复")
	if second.get("_insurance").get_used_slots() != 1:
		failures.append("保险格没有随塔楼场景重建恢复")
	var restored_flashlight := second.player.get_node_or_null("PlayerFlashlight3D")
	if not is_equal_approx(restored_flashlight.get_charge_ratio(), 0.37):
		failures.append("手电电量没有恢复")

	second.queue_free()
	await get_tree().process_frame
	BaseManager.save_path = original_path
	BaseManager.data = original_data
	_cleanup()
	if failures.is_empty():
		print("TOWER_RUNTIME_RESTART_OK: inventory, equipment instances, insurance and flashlight survive scene/process restart")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _cleanup() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp", TEST_PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
