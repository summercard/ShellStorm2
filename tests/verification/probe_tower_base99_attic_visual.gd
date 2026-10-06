extends Node

const OUTPUT_DIR := "I:/工作项目/shellstrom2/ShellStorm2/outputs/base99_radio_v003"

func _ready() -> void:
	print("VISUAL_PROBE_START")
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990199
	add_child(tower)
	await _settle()
	var rooms := tower.get("_room_by_id") as Dictionary
	var facility_room := rooms.get("facility") as DungeonRoom3D
	if facility_room == null:
		get_tree().quit(1)
		return
	tower.player.global_position = facility_room.to_global(Vector3(0.0, 5.05, 0.0))
	tower.call("_refresh_physical_location_authority", true)
	await _settle()
	var camera := Camera3D.new()
	camera.name = "ProbeNativeCamera"
	camera.fov = 55.0
	tower.add_child(camera)
	camera.current = true
	await _settle()
	print("CAMERA_READY=%s viewport=%s" % [camera.global_position, get_viewport().get_visible_rect()])
	var radio := tower.find_child("99F床边桌独立收音机", true, false) as Base99Radio3D
	if radio == null:
		get_tree().quit(1)
		return
	await _capture(camera, Vector3(0.0, -4.9, -5.0), Vector3(0.0, 5.5, 5.5), "attic_full.png")
	var target := radio.global_position + Vector3(0.0, 0.32, 0.0)
	await _capture(camera, target, Vector3(1.8, 1.8, 3.0), "radio_off_closeup.png")
	for state in ["a", "b", "off"]:
		radio.set_radio_state(state)
		await _capture(camera, target, Vector3(1.8, 1.8, 3.0), "radio_%s_closeup.png" % state)
		print("RADIO_VISUAL_STATE=%s snapshot=%s" % [state, radio.get_state_snapshot()])
	_dump_materials(radio)
	tower.free()
	await get_tree().process_frame
	get_tree().quit(0)

func _dump_materials(radio: Node3D) -> void:
	for value in radio.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
		var mesh := value as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			print("RADIO_RUNTIME_MATERIAL mesh=%s role=%s roughness=%s metallic=%s emission_enabled=%s energy=%s palette=%s nearest=%s" % [mesh.name, material.resource_name, material.roughness, material.metallic, material.emission_enabled, material.emission_energy_multiplier, material.albedo_texture.resource_path if material.albedo_texture != null else "MISSING", material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST])

func _capture(camera: Camera3D, target: Vector3, offset: Vector3, filename: String) -> void:
	camera.global_position = target + offset
	camera.look_at(target, Vector3.UP)
	await _settle()
	var image := get_viewport().get_texture().get_image()
	var output_path := OUTPUT_DIR + "/" + filename
	var error := image.save_png(output_path)
	print("CAPTURE=%s path=%s err=%s size=%s camera=%s target=%s" % [filename, output_path, error, image.get_size(), camera.global_position, target])

func _settle() -> void:
	for i in 8:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.25).timeout
