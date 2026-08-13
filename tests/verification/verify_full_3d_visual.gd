extends Node

const PREVIEW_PATH := "res://outputs/verification/dungeon_3d.png"
const LIGHT_ON_PREVIEW_PATH := "res://outputs/verification/dungeon_3d_light_on.png"
const INVENTORY_PREVIEW_PATH := "res://outputs/verification/inventory_3d.png"


func _ready() -> void:
	VerificationOutput.prepare()
	var failures: Array[String] = []
	var scene := load("res://scenes/levels3d/IronFrontier3D.tscn") as PackedScene
	var dungeon := scene.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 4242
	add_child(dungeon)
	await get_tree().process_frame
	dungeon.force_enter_room_for_test("main_01")
	for value in get_tree().get_nodes_in_group("dungeon_room_3d"):
		var room := value as DungeonRoom3D
		if room != null and dungeon.is_ancestor_of(room) and room.room_id == "main_01":
			dungeon.player.global_position = room.global_position + Vector3(0, 0.05, 2.0)
			break
	await get_tree().physics_frame
	await get_tree().create_timer(0.75).timeout
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		failures.append("Dungeon3D preview viewport is empty")
	elif image.save_png(PREVIEW_PATH) != OK:
		failures.append("Dungeon3D preview cannot be saved")
	var current_room := dungeon.get("_room_by_id").get("main_01") as DungeonRoom3D
	var switch := current_room.find_child("RoomLightSwitch3D", true, false) as RoomLightSwitch3D if current_room != null else null
	if switch == null or not switch.toggle_light():
		failures.append("Dungeon3D visual check cannot enable the central room light")
	else:
		await get_tree().create_timer(0.3).timeout
		var light_on_image := get_viewport().get_texture().get_image()
		if light_on_image == null or light_on_image.is_empty() or light_on_image.save_png(LIGHT_ON_PREVIEW_PATH) != OK:
			failures.append("Dungeon3D light-on preview cannot be saved")
	var inventory := dungeon.get_inventory_module()
	for item_id in ["weapon_shotgun", "mod_bullet_standard", "item_health_potion", "item_room_key", "item_beacon"]:
		inventory.add_item(ItemRegistry.get_instance().get_item(item_id), 1)
	var inventory_ui := dungeon.get_node_or_null("HUD/InventoryUI3D") as InventoryUI
	if inventory_ui == null:
		failures.append("Dungeon3D visual check has no inventory UI")
	else:
		inventory_ui.set_inventory_panel_open(true)
		await get_tree().process_frame
		await get_tree().create_timer(0.45).timeout
		var inventory_image := get_viewport().get_texture().get_image()
		if inventory_image == null or inventory_image.is_empty() or inventory_image.save_png(INVENTORY_PREVIEW_PATH) != OK:
			failures.append("3D inventory model preview cannot be saved")
		inventory_ui.set_inventory_panel_open(false)
	var snapshot := dungeon.get_generation_snapshot()
	if int(snapshot.get("room_count", 0)) < 10 or not bool(snapshot.get("has_extraction", false)):
		failures.append("Dungeon3D preview scene is not the full runtime")
	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("FULL_3D_VISUAL_OK: brighter real-flashlight entry, central-light-on and 3D inventory projection previews saved")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
