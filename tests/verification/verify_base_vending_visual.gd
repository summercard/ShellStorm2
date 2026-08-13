extends Node

const MACHINE_PREVIEW := "res://outputs/verification/base_vending_machine.png"
const MENU_PREVIEW := "res://outputs/verification/base_vending_menu.png"
const VAULT_PREVIEW := "res://outputs/verification/base_vault_grid.png"


func _ready() -> void:
	VerificationOutput.prepare()
	var failures: Array[String] = []
	var runtime_inventory := InventoryModule.new(12)
	runtime_inventory.add_item(ItemRegistry.get_instance().get_item("weapon_pistol"), 1)
	runtime_inventory.add_item(ItemRegistry.get_instance().get_item("weapon_shotgun"), 1)
	var scene := load("res://scenes/BaseWorld3D.tscn") as PackedScene
	var world := scene.instantiate() as BaseWorld3D
	add_child(world)
	await get_tree().process_frame
	var vending := world.get_node_or_null("Facilities/BaseVending") as BaseFacility3D
	if vending == null:
		failures.append("出口墙边自动贩卖机未实例化")
	else:
		if vending.position.distance_to(Vector3(2.4, 0, 7.7)) > 0.05:
			failures.append("自动贩卖机没有固定在基地出口侧墙边")
		world.player.global_position = vending.global_position + Vector3(0, 0, -3.2)
		await get_tree().process_frame
		await get_tree().create_timer(0.4).timeout
		var machine_image := get_viewport().get_texture().get_image()
		if machine_image == null or machine_image.is_empty() or machine_image.save_png(MACHINE_PREVIEW) != OK:
			failures.append("自动贩卖机3D预览保存失败")
		world.call("_on_facility_activated", vending)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.25).timeout
		var menu := world.get_active_menu() as BaseVendingMenu
		if menu == null or menu._buy_list.get_child_count() != 7:
			failures.append("自动贩卖机菜单未打开或货架不是7项")
		else:
			menu.set_inventory_module(runtime_inventory)
			await get_tree().process_frame
			var menu_image := get_viewport().get_texture().get_image()
			if menu_image == null or menu_image.is_empty() or menu_image.save_png(MENU_PREVIEW) != OK:
				failures.append("自动贩卖机菜单预览保存失败")
			menu.queue_free()
			await get_tree().process_frame
			var vault_scene := load("res://scenes/VaultMenu.tscn") as PackedScene
			var vault_menu := vault_scene.instantiate() as VaultMenu
			vault_menu.set_inventory_module(runtime_inventory)
			world.add_child(vault_menu)
			await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().create_timer(0.25).timeout
			if vault_menu.find_children("*", "BaseStorageSlot", true, false).size() < 14:
				failures.append("保险柜格子界面未完整生成")
			var vault_image := get_viewport().get_texture().get_image()
			if vault_image == null or vault_image.is_empty() or vault_image.save_png(VAULT_PREVIEW) != OK:
				failures.append("保险柜格子界面预览保存失败")
	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("BASE_VENDING_VISUAL_OK: vending machine, infinite-stock shop, and two-column vault grid previews saved")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
