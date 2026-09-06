extends Node


func _ready() -> void:
	var clock_snapshot := GameTimeManager.get_persistence_snapshot()
	GameTimeManager.set_clock_running(false)
	GameTimeManager.set_elapsed_game_seconds(5.0 * 3600.0, false)
	var tower := load("res://scenes/TowerDescent3D.tscn").instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	tower.player.set_physics_process(false)
	tower.force_enter_room_for_test("facility")
	var facility := (tower.get("_room_by_id") as Dictionary)["facility"] as DungeonRoom3D
	tower.player.global_position = facility.global_position + Vector3(0, 0.05, 0)
	facility.ensure_detail_built()
	var layout := tower.get("_facility_art_layout") as Node3D
	var lights := layout.find_children("PaletteLightSpill", "OmniLight3D", true, false)
	var snapshot := layout.call("get_presentation_snapshot") as Dictionary
	assert(int(snapshot.strong_fixtures) == 10)
	assert(int(snapshot.spill_lights) == 8)
	assert(lights.size() == 8, "Eight selected neon/lamp fixtures must have local colored spill")
	var enhanced := 0
	var strong := 0
	var seen_materials := {}
	for node in layout.find_children("*", "MeshInstance3D", true, false):
		var visual := node as MeshInstance3D
		for index in range(visual.mesh.get_surface_count() if visual.mesh != null else 0):
			var material := visual.get_active_material(index) as BaseMaterial3D
			if material == null or not material.resource_name.ends_with("HDR"):
				continue
			if seen_materials.has(material.get_instance_id()):
				continue
			seen_materials[material.get_instance_id()] = true
			var original := visual.mesh.surface_get_material(index) as BaseMaterial3D
			assert(material.emission_enabled)
			assert(
				material.emission_texture.resource_path
				== "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
			)
			assert(material.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY)
			if original != null:
				assert(material.emission_energy_multiplier >= original.emission_energy_multiplier)
			if material.resource_name.ends_with("_基地灯具HDR"):
				strong += 1
			enhanced += 1
	assert(strong >= 9)
	assert(enhanced == int(snapshot.enhanced_surfaces))
	assert(enhanced >= 38)
	layout.hide()
	for light in lights:
		assert(not light.is_visible_in_tree())
	layout.show()
	var gameplay_camera := get_viewport().get_camera_3d()
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.fov = 58
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/verification"))
	for light in lights:
		assert(not light.shadow_enabled and light.light_cull_mask == 1)
		assert(light.light_color != Color.WHITE)
		print("FIXTURE ", light.get_parent().name, " ", light.global_position, " ", light.light_color)
		var center: Vector3 = light.global_position
		# North-facing art is viewed from the room; west wall sign from the east.
		var offset := Vector3(0, 1.8, 5.0)
		if "STAY_CURIOUS" in str(light.get_parent().name):
			offset = Vector3(5.0, 1.8, 0)
		camera.global_position = center + offset
		camera.look_at(center)
		for frame in range(12):
			await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://outputs/verification/base_glow_%s.png" % light.get_parent().name)
			var overrides: Array = []
			for node in light.get_parent().find_children("*", "MeshInstance3D", true, false):
				var visual := node as MeshInstance3D
				for index in range(visual.mesh.get_surface_count() if visual.mesh != null else 0):
					var material := visual.get_surface_override_material(index)
					if material != null:
						overrides.append([visual, index, material])
						visual.set_surface_override_material(index, null)
			light.visible = false
			for frame in range(12):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://outputs/verification/base_glow_before_%s.png" % light.get_parent().name)
			for entry in overrides:
				entry[0].set_surface_override_material(entry[1], entry[2])
			light.visible = true
	var active_local_lights := 0
	for node in tower.find_children("*", "Light3D", true, false):
		if node is DirectionalLight3D:
			continue
		var local_light := node as Light3D
		if local_light.is_visible_in_tree():
			active_local_lights += 1
	assert(active_local_lights <= 14)
	gameplay_camera.make_current()
	for frame in range(12):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://outputs/verification/base_glow_gameplay.png")
	print("BASE_FIXTURE_GLOW_OK: 10 strong fixtures, 8 colored environment-only lights, %d active local lights; %d palette-preserving HDR surfaces" % [active_local_lights, enhanced])
	GameTimeManager.restore_from_persistence(clock_snapshot, false)
	tower.queue_free()
	await get_tree().process_frame
	get_tree().quit()
