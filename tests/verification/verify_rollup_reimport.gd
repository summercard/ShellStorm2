extends SceneTree

func _init() -> void:
	call_deferred("verify")

func verify() -> void:
	var path := "res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities_v021/base_camp_rollup_main_door/base_camp_rollup_main_door_root_top3d_v002.tscn"
	var door := (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(door)
	var blocker := door.get_node("StaticCollision/DoorBlocker") as CollisionShape3D
	assert((blocker.shape as BoxShape3D).size.is_equal_approx(Vector3(6.44,2.92,0.91)))
	assert(blocker.position.is_equal_approx(Vector3(5.07,2.34,-4.385)))
	var meshes := door.find_children("*", "MeshInstance3D", true, false)
	assert(meshes.size() == 70)
	for node in meshes:
		var mesh := (node as MeshInstance3D).mesh
		for surface in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(surface) as BaseMaterial3D
			assert(mat != null and mat.albedo_texture != null)
			assert(mat.albedo_texture.resource_path == "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(9,5,-12)
	camera.look_at(Vector3(5.07,2.34,-4.385))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8
	camera.current = true
	var light := DirectionalLight3D.new()
	root.add_child(light)
	light.rotation_degrees = Vector3(-35,-25,0)
	light.light_energy = 1.2
	root.size = Vector2i(1000,700)
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var output := "res://outputs/verification/rollup_reimport_v024.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/verification"))
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output))
	print("ROLLUP_REIMPORT_OK: 70 meshes, shared palette, original collision; preview=" + output)
	quit()
