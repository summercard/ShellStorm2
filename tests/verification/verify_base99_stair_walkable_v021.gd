extends Node

var failures: Array[String] = []

func _ready() -> void:
	var tower = load("res://scenes/TowerDescent3D.tscn").instantiate()
	tower.test_mode = true
	tower.run_seed_override = 990099
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	var facility = tower.get("_room_by_id").get("facility")
	if "--preview" in OS.get_cmdline_user_args():
		await screenshot(tower,facility)
		tower.queue_free()
		await get_tree().process_frame
		get_tree().quit()
		return
	var player = load("res://scenes/Player3D.tscn").instantiate()
	player.start_with_weapon = false
	add_child(player)
	player.global_position = facility.global_position + Vector3(-13.8, .1, -6.4)
	for frame in range(30): await get_tree().physics_frame
	var points = [Vector3(-13.8,3.045,-13.8),Vector3(-6.5,6.09,-13.8),Vector3(-4.0,6.09,-13.8)]
	for point in points:
		await travel(player, facility.global_position + point)
		if absf(player.global_position.y - facility.global_position.y - point.y) > .30:
			failures.append("Stair height mismatch at %s: %s" % [point,player.global_position-facility.global_position])
	player.set_test_move_direction(Vector3.ZERO)
	await screenshot(tower,facility)
	for point in [Vector3(-6.5,6.09,-13.8),Vector3(-13.8,3.045,-13.8),Vector3(-13.8,0,-6.4)]:
		await travel(player,facility.global_position+point)
	check_materials(facility)
	player.queue_free()
	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("BASE99_STAIR_WALKABLE_V021_OK: real Player3D ascends and descends both flights in formal base; emissive uses multiply")
	else:
		for message in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)

func travel(player, target: Vector3) -> void:
	for frame in range(420):
		var delta: Vector3 = target-player.global_position
		delta.y=0
		if delta.length() < .15:
			player.set_test_move_direction(Vector3.ZERO)
			return
		player.set_test_move_direction(delta.normalized())
		await get_tree().physics_frame
	failures.append("Cannot reach %s; stopped at %s" % [target, player.global_position])
	for index in player.get_slide_collision_count():
		var hit=player.get_slide_collision(index)
		print("STUCK_COLLIDER ",hit.get_collider().get_path()," point=",hit.get_position()," normal=",hit.get_normal())
	player.set_test_move_direction(Vector3.ZERO)

func check_materials(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		for index in node.mesh.get_surface_count():
			var material = node.mesh.surface_get_material(index)
			if material is BaseMaterial3D and material.emission_enabled and material.emission_texture:
				if material.emission_texture.resource_path.ends_with("设施低亮多巴胺色盘_10x10_512.png") and material.emission_operator != BaseMaterial3D.EMISSION_OP_MULTIPLY:
					failures.append("Palette emission adds white: "+node.name)
	for child in node.get_children(): check_materials(child)

func screenshot(tower,facility) -> void:
	if DisplayServer.get_name() == "headless": return
	for layer in tower.find_children("*","CanvasLayer",true,false): layer.visible=false
	var fill=DirectionalLight3D.new()
	fill.light_energy=1.8
	fill.rotation_degrees=Vector3(-60,-25,0)
	add_child(fill)
	var camera=Camera3D.new()
	add_child(camera)
	camera.global_position=facility.global_position+Vector3(-6,16,-3)
	camera.look_at(facility.global_position+Vector3(-10,3,-11))
	camera.current=true
	for frame in range(12): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://outputs/verification/base99_stair_repair/godot_stair.png")
	camera.queue_free()
	fill.queue_free()
