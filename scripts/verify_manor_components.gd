extends SceneTree
## Standalone isolated-project verifier. No game autoload or formal scene writes.
var errors: Array[String] = []
var meshes := 0
var surfaces := 0
var palette_path := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
var records: Array = []
var replay_boxes: Array = []
var replay: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)

func inspect(node: Node, bounds: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		meshes += 1
		var box := mi.transform * mi.get_aabb()
		# Root and all imported mesh locals are identity, glTF axis conversion baked.
		bounds.append(box)
		for i in mi.mesh.get_surface_count():
			surfaces += 1
			var mat := mi.mesh.surface_get_material(i) as BaseMaterial3D
			check(mat != null, "missing material " + str(node.name))
			if mat != null:
				check(mat.albedo_texture != null, "missing palette " + str(node.name))
				if mat.albedo_texture != null:
					check(mat.albedo_texture.resource_path == palette_path, "wrong palette")
				check(mat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "palette sampling")
	for child in node.get_children():
		inspect(child, bounds)

func collect_world_bounds(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		replay_boxes.append(mi.global_transform * mi.get_aabb())
	for child in node.get_children():
		collect_world_bounds(child)

func run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://component_catalog.json"))
	var by_id := {}
	for entry: Dictionary in catalog.components:
		var path: String = "res://" + str(entry.prefab_path)
		var packed := load(path) as PackedScene
		check(packed != null, "load failed " + path)
		if packed == null:
			continue
		var instance := packed.instantiate() as Node3D
		check(instance != null, "instantiate failed")
		root.add_child(instance)
		check(instance.scale.is_equal_approx(Vector3.ONE), "root scale")
		check(str(instance.get_meta("asset_id")) == str(entry.component_id), "asset id")
		var bounds: Array = []
		inspect(instance, bounds)
		check(not bounds.is_empty(), "empty component")
		var combined: AABB = bounds[0]
		for b: AABB in bounds:
			combined = combined.merge(b)
		var bsize: Array = entry.bounds_size_m
		var expected := Vector3(float(bsize[0]), float(bsize[2]), float(bsize[1]))
		check(combined.size.distance_to(expected) < 0.015, "bounds " + str(entry.slug) + " " + str(combined.size) + " expected " + str(expected))
		check(absf(combined.position.y) < 0.015, "bottom origin " + str(entry.slug))
		check(absf(combined.get_center().x) < 0.015 and absf(combined.get_center().z) < 0.015, "center origin")
		if str(entry.slug) == "manor_wall_door":
			var body := instance.get_node("CollisionBody")
			check(body.get_child_count() == 2, "door pier collision count")
			for child in body.get_children():
				var shape := child as CollisionShape3D
				var box := shape.shape as BoxShape3D
				check(absf(shape.position.x) - box.size.x * 0.5 >= 1.099, "blocked doorway")
		by_id[str(entry.component_id)] = path
		records.append({"id": entry.component_id, "size": [combined.size.x, combined.size.y, combined.size.z], "loaded": true})
		instance.free()
	# Ephemeral replay used only to check coordinate conversion and render fidelity.
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://component_instances.json"))
	replay = Node3D.new()
	root.add_child(replay)
	for record: Dictionary in doc.instances:
		var node := (load(by_id[str(record.component_id)]) as PackedScene).instantiate() as Node3D
		replay.add_child(node)
		var p: Array = record.position_m
		node.position = Vector3(float(p[0]), float(p[2]), -float(p[1]))
		node.rotation.y = deg_to_rad(float(record.rotation_y_deg))
		check(node.scale == Vector3.ONE, "replay scale")
	collect_world_bounds(replay)
	var replay_box: AABB = replay_boxes[0]
	for box: AABB in replay_boxes:
		replay_box = replay_box.merge(box)
	check(absf(replay_box.position.x + 12.75) < 0.015 and absf(replay_box.size.x - 25.555) < 0.015, "reference footprint width")
	check(absf(replay_box.position.z + 10.25) < 0.015 and absf(replay_box.size.z - 20.5) < 0.015, "reference footprint depth")
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.035, 0.03, 0.025)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.65, 0.59, 0.49)
	environment.environment.ambient_light_energy = 0.7
	replay.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -25, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	replay.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 28.8
	replay.add_child(camera)
	camera.position = Vector3(0, 38, 8)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	for i in 6:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png("res://godot_replay.png")
		check(error == OK, "capture failed")
	var report := {"components": records.size(), "instances": doc.instances.size(), "mesh_instances": meshes, "surfaces": surfaces, "errors": errors, "ok": errors.is_empty(), "replay_bbox": {"position": [replay_box.position.x, replay_box.position.y, replay_box.position.z], "size": [replay_box.size.x, replay_box.size.y, replay_box.size.z]}}
	FileAccess.open("res://verification_report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("MANOR_COMPONENTS ", JSON.stringify(report))
	replay.free()
	quit(0 if errors.is_empty() else 1)
