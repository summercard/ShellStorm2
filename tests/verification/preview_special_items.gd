extends Node
## Actual Dungeon HUD/inventory + vendor UI, followed by an isolated art/VFX showroom.
var _output := ""
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _capture(filename: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	if picture == null or picture.is_empty() or picture.save_png(_output.path_join(filename)) != OK:
		_failures.append("screenshot " + filename)

func _run() -> void:
	_output = OS.get_environment("SHELLSTORM_VERIFICATION_OUTPUT")
	if _output.is_empty():
		push_error("SPECIAL_ITEMS_PREVIEW requires external SHELLSTORM_VERIFICATION_OUTPUT")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	var dungeon := preload("res://scenes/Dungeon3D.tscn").instantiate() as Dungeon3D
	dungeon.test_mode = true
	add_child(dungeon)
	for _frame in 12:
		await get_tree().process_frame
	var inventory := dungeon.get_inventory_module()
	for definition: Dictionary in SpecialItemCatalog.definitions():
		inventory.add_item(definition, 3)
	var player := dungeon.player
	var controller := player.get_special_item_controller()
	controller.equip(SpecialItemCatalog.GRENADE)
	await _capture("special_items_hud.png")
	dungeon._inventory_ui.set_inventory_panel_open(true)
	for _frame in 6:
		await get_tree().process_frame
	await _capture("special_items_equipment.png")
	if dungeon._inventory_ui.special_equipment_slot == null:
		_failures.append("actual equipment slot not connected")
	dungeon._inventory_ui.set_inventory_panel_open(false)
	BaseManager.data.extraction_points = 1000
	var vendor := preload("res://scenes/BaseVendingMenu.tscn").instantiate() as BaseVendingMenu
	vendor.set_inventory_module(inventory)
	add_child(vendor)
	for _frame in 8:
		await get_tree().process_frame
	(vendor._buy_list.get_parent() as ScrollContainer).scroll_vertical = 10000
	await get_tree().process_frame
	await _capture("special_items_vending.png")
	if vendor._buy_list.get_child_count() != 10:
		_failures.append("vending does not show all ten products")
	vendor.queue_free()
	dungeon.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	# The showroom keeps the same imported meshes/effects, viewed at legible art scale.
	var studio := Node3D.new()
	add_child(studio)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("111b25")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("a7c8d8")
	environment.environment.ambient_light_energy = 0.65
	studio.add_child(environment)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-50, -25, 0)
	sunlight.light_energy = 1.8
	studio.add_child(sunlight)
	var camera := Camera3D.new()
	studio.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.0
	camera.position = Vector3(9, 10, 15)
	camera.look_at(Vector3(0, 0.4, 0))
	camera.current = true
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 20)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("26333d")
	ground_material.roughness = 0.8
	ground.material_override = ground_material
	studio.add_child(ground)
	for index in 3:
		var definition := SpecialItemCatalog.definitions()[index]
		var model := ItemModelFactory3D.create_model(definition)
		studio.add_child(model)
		model.position = Vector3(index * 4.5 - 4.5, 0.6, -1.6)
		model.scale = Vector3.ONE * 5.0
		var caption := Label3D.new()
		caption.text = str(definition.name)
		caption.font_size = 64
		caption.pixel_size = 0.008
		caption.position = Vector3(index * 4.5 - 4.5, 0.05, 1.0)
		caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		caption.no_depth_test = true
		studio.add_child(caption)
	var oil := VfxPool3D.create_unpooled(VfxPool3D.FX01_SPECIAL_OIL)
	studio.add_child(oil)
	oil.activate(Vector3(4.2, 0.02, 3.0), Color.WHITE, 1.3, {"duration": 20.0})
	var fire_world := SpecialItemWorld3D.new()
	studio.add_child(fire_world)
	fire_world.add_fire(Vector3(0, 0.02, 3.0), LampFirePatch3D.DEFAULT_RADIUS, 5.0, 6, null)
	var blast := VfxPool3D.create_unpooled(VfxPool3D.FX01_SPECIAL_BLAST)
	studio.add_child(blast)
	blast.activate(Vector3(-4.4, 0.02, 3.0), Color.WHITE, 1.5, {"duration": 20.0})
	blast._on_tick(5.0, 20.0)
	blast.set_process(false)
	for _frame in 20:
		await get_tree().process_frame
	await _capture("special_items_assets.png")
	studio.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("SPECIAL_ITEMS_VISUAL_OK: actual HUD, equipment, vending and imported asset frames")
	else:
		for failure in _failures:
			push_error(failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
