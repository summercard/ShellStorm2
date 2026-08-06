extends Node
## 复现玩家路径：I键背包已有两件物品，再打开99层保险柜和贩卖机。


func _ready() -> void:
	var failures: Array[String] = []
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	add_child(tower)
	await get_tree().process_frame
	await get_tree().process_frame
	var inventory := tower.get_inventory_module()
	inventory.clear_all()
	inventory.add_item(ItemRegistry.get_instance().get_item("weapon_pistol"), 1)
	inventory.add_item(ItemRegistry.get_instance().get_item("weapon_shotgun"), 1)
	if inventory.get_used_slots() != 2:
		failures.append("I键背包测试前置不是两件物品")

	tower.call("_open_facility_menu", "res://scenes/VaultMenu.tscn")
	await get_tree().process_frame
	var vault := tower.get("_active_facility_menu") as VaultMenu
	if vault == null or vault._inventory_module != inventory:
		failures.append("99层保险柜没有绑定I键InventoryModule实例")
	else:
		var visible_items := 0
		for slot in vault.find_children("*", "BaseStorageSlot", true, false):
			if slot is BaseStorageSlot and slot.owner_id == "inventory" and not slot.item.is_empty():
				visible_items += 1
		if visible_items != 2:
			failures.append("99层保险柜没有显示I键背包的两件物品")
		vault.queue_free()
		await get_tree().process_frame

	tower.call("_open_facility_menu", "res://scenes/BaseVendingMenu.tscn")
	await get_tree().process_frame
	var vending := tower.get("_active_facility_menu") as BaseVendingMenu
	if vending == null or vending._inventory_module != inventory:
		failures.append("99层贩卖机没有绑定I键InventoryModule实例")
	elif "2 / 12" not in vending._capacity_label.text:
		failures.append("99层贩卖机没有显示I键背包2/12")

	if failures.is_empty():
		print("TOWER_FACILITY_INVENTORY_BINDING_OK: I-key inventory identity and two visible items shared by vault and vending")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
