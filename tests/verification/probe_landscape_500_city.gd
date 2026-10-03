extends "res://tests/verification/probe_open_world_landscape_foundation.gd"

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("城市验收必须真实renderer")
		get_tree().quit(2)
		return
	var tower := (load("res://scenes/TowerDescent3D.tscn") as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	for frame in range(12):
		await get_tree().process_frame
	var indices: Array = tower._floor_plan_snapshots.keys()
	indices.sort()
	for index in indices:
		tower.call("_commit_floor_bundle", index, "landscape_500_probe")
		await get_tree().process_frame
	for room in tower._room_by_id.values():
		room.ensure_shell_built()
	for frame in range(6):
		await get_tree().process_frame
	tower.process_mode = Node.PROCESS_MODE_DISABLED
	var route := tower.get_node("Blocks/Rooftop/CrossTowerRoute") as Node3D
	var foundation := route.get_node("LandscapeFoundation") as Node3D
	var generator := foundation.get_node("ProceduralCity500")
	var snapshot: Dictionary = generator.call("get_city_snapshot")
	var old_city := tower.find_children("CityBuildingSilhouettes", "MultiMeshInstance3D", true, false)[0] as MultiMeshInstance3D
	var report := {"renderer": DisplayServer.get_name(), "rendering_method": RenderingServer.get_current_rendering_method(), "engine": Engine.get_version_info(), "legacy": [], "new_buildings": [], "keepouts": [], "sectors": [], "targets": {}, "bridge": {}, "foundation": [], "parameters": snapshot["parameters"], "binding_complete": snapshot["binding_complete"]}
	for i in range(old_city.multimesh.instance_count):
		var transform := old_city.global_transform * old_city.multimesh.get_instance_transform(i)
		var box := transform * old_city.multimesh.mesh.get_aabb()
		report["legacy"].append({"index": i, "transform": var_to_str(transform), "min": _vector(box.position), "max": _vector(box.end)})
	for placement in snapshot["placements"]:
		var batch := generator.get_node(placement["batch"]) as MultiMeshInstance3D
		var transform := batch.global_transform * batch.multimesh.get_instance_transform(placement["instance"])
		var box := transform * batch.multimesh.mesh.get_aabb()
		report["new_buildings"].append({"batch": placement["batch"], "instance": placement["instance"], "grid": [placement["grid_x"], placement["grid_z"]], "sector": [placement["sector_x"], placement["sector_z"]], "min": _vector(box.position), "max": _vector(box.end), "actual_transform": var_to_str(transform), "planned_transform": var_to_str(placement["transform"]), "same_mesh": batch.multimesh.mesh == old_city.multimesh.mesh, "same_material": batch.multimesh.mesh.surface_get_material(0) == old_city.multimesh.mesh.surface_get_material(0), "visible_in_tree": batch.is_visible_in_tree(), "visibility_range_end": batch.visibility_range_end, "layers": batch.layers})
	for keepout in snapshot["keepouts"]:
		var rect: Rect2 = keepout["rect"]
		report["keepouts"].append({"name": keepout["name"], "kind": keepout["kind"], "min_xz": [rect.position.x, rect.position.y], "max_xz": [rect.end.x, rect.end.y]})
	for sector in snapshot["sectors"]:
		var legacy_count := 0
		for entry in report["legacy"]:
			var lo: Array = entry["min"]
			var hi: Array = entry["max"]
			var sx := int(((lo[0] + hi[0]) * 0.5 + 246.249687) / 100.0)
			var sz := int(((lo[2] + hi[2]) * 0.5 + 290.770721) / 100.0)
			if sx == sector["x"] and sz == sector["z"]:
				legacy_count += 1
		report["sectors"].append({"x": sector["x"], "z": sector["z"], "count": sector["members"].size(), "legacy_count": legacy_count, "total_city_count": sector["members"].size() + legacy_count, "candidates": sector["candidates"], "rejected": sector["rejected"]})
	for target in ["Tower2", "Tower3", "Skyline08"]:
		var node := route.get_node(target) as Node3D
		var entry := _bounds(node, node.get_parent().global_transform)
		entry["transform"] = var_to_str(node.transform)
		report["targets"][target] = entry
	for child in route.get_node("Bridge").get_children():
		var entry := _bounds(child, route.global_transform)
		entry["transform"] = var_to_str((child as Node3D).transform)
		report["bridge"][str(child.name)] = entry
	for child in foundation.get_children():
		if child is MeshInstance3D:
			var entry := _bounds(child, foundation.global_transform)
			entry["name"] = str(child.name)
			entry["transform"] = var_to_str((child as Node3D).transform)
			entry["same_city_material"] = (child as MeshInstance3D).material_override == old_city.multimesh.mesh.surface_get_material(0)
			report["foundation"].append(entry)
	report["main_tower_stages"] = []
	for index in tower._floor_stages:
		var stage := tower._floor_stages[index] as Node3D
		var stage_visible := stage.visible
		stage.visible = true
		var entry := _bounds(stage, stage.get_parent().global_transform)
		stage.visible = stage_visible
		entry["floor_index"] = index
		entry["transform"] = var_to_str(stage.transform)
		report["main_tower_stages"].append(entry)
	var visibility: Dictionary = {}
	for block in tower.get_node("Blocks").get_children():
		if block is Node3D:
			visibility[block] = block.visible
			block.visible = true
	for stage in tower._floor_stages.values():
		visibility[stage] = stage.visible
		stage.visible = true
	for room in tower._room_by_id.values():
		visibility[room] = room.visible
		room.visible = true
	route.visible = false
	report["targets"]["Tower1"] = _bounds(tower.get_node("Blocks"), tower.global_transform)
	route.visible = true
	for node in visibility:
		node.visible = visibility[node]
	var clouds := tower.get_node("OutdoorClouds") as VfxCloudSea3D
	report["clouds"] = clouds.get_presentation_snapshot()
	report["cloud_city_bounds"] = []
	for box in clouds.get_procedural_city_exclusion_bounds():
		report["cloud_city_bounds"].append({"min": _vector(box.position), "max": _vector(box.end)})
	report["cloud_fallback_bounds"] = []
	for box in clouds.get_fallback_bounds():
		report["cloud_fallback_bounds"].append({"min": _vector(box.position), "max": _vector(box.end)})
	var cloud_material := clouds.get_node("CloudSea").get_child(0).material_override as ShaderMaterial
	report["cloud_city_uniform_enabled"] = cloud_material.get_shader_parameter("procedural_city_enabled")
	var texture := cloud_material.get_shader_parameter("procedural_city_boxes") as Texture2D
	report["cloud_city_texture_size"] = [texture.get_width(), texture.get_height()] if texture != null else []
	report["cloud_city_texture_entries"] = []
	if texture != null:
		var image := texture.get_image()
		for placement in snapshot["placements"]:
			var gx: int = placement["grid_x"]
			var gz: int = placement["grid_z"]
			var footprint := image.get_pixel(gx, gz)
			var height := image.get_pixel(gx, gz + texture.get_width())
			report["cloud_city_texture_entries"].append({"min": [footprint.r, height.r, footprint.g], "max": [footprint.b, height.g, footprint.a], "enabled": height.b})
	report["batch_count"] = generator.get_child_count()
	report["independent_loads"] = []
	for scene_path in FOUNDATION_SCENES:
		var packed := load(scene_path) as PackedScene
		var instance := packed.instantiate() if packed != null else null
		report["independent_loads"].append({"path": scene_path, "loaded": instance != null})
		if instance != null:
			instance.free()
	var standalone := (load(foundation.scene_file_path) as PackedScene).instantiate() as Node3D
	report["independent_loads"].append({"path": foundation.scene_file_path, "loaded": standalone != null})
	standalone.free()
	report["landscape_collision_count"] = foundation.find_children("*", "CollisionObject3D", true, false).size() + foundation.find_children("*", "CollisionShape3D", true, false).size()
	var output := OS.get_environment("LANDSCAPE_OUTPUT")
	report["screenshots"] = await _capture_500(tower, output.get_base_dir()) if OS.get_environment("LANDSCAPE_CAPTURE") == "1" else []
	var repeated := generator.get_script().new() as Node3D
	foundation.add_child(repeated)
	for frame in range(3):
		await get_tree().process_frame
	var repeat_snapshot: Dictionary = repeated.call("get_city_snapshot")
	report["deterministic_repeat"] = snapshot["placements"] == repeat_snapshot["placements"]
	repeated.queue_free()
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("CITY500_RUNTIME_OK old=%d new=%d sectors=%d" % [report["legacy"].size(), report["new_buildings"].size(), report["sectors"].size()])
	tower.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)

func _save_view(camera: Camera3D, name: String, directory: String, presentation: String) -> Dictionary:
	for frame in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := directory.path_join(name + ".png")
	var error := image.save_png(path)
	return {"name": name, "path": path, "save_error": error, "camera_transform": var_to_str(camera.global_transform), "camera_far": camera.far, "fov": camera.fov, "size": camera.size, "presentation": presentation}

func _capture_500(tower: TowerDescent3D, directory: String) -> Array:
	var results: Array = []
	var camera := tower.player.camera
	# 先拍原环境真实玩家机位；不改雾、云、裁剪、曝光或玩家相机姿态。
	for point in [Vector3(0, 0.05, -30), Vector3(-12, 0.05, -153.925626)]:
		tower.player.global_position = point
		camera.make_current()
		results.append(await _save_view(camera, "player_main_rooftop" if point.x == 0 else "player_tower3", directory, "实际玩家Camera3D和正式环境；仅测试传送到天台/塔3桥口，冻结模拟，不代表全部地表同时可见"))
	var environment := (tower.get_node("WorldEnvironment") as WorldEnvironment).environment
	var before := {"fog_enabled": environment.fog_enabled, "fog_density": environment.fog_density, "volumetric_fog_enabled": environment.volumetric_fog_enabled, "ambient_light_energy": environment.ambient_light_energy, "ambient_light_source": environment.ambient_light_source, "ambient_light_color": environment.ambient_light_color, "background_mode": environment.background_mode, "background_color": environment.background_color}
	var light := tower.get_node("DirectionalLight3D") as DirectionalLight3D
	var light_before := {"energy": light.light_energy, "rotation": light.rotation}
	var canvas_visibility: Dictionary = {}
	for ui in tower.find_children("*", "CanvasLayer", true, false):
		canvas_visibility[ui] = ui.visible
		ui.visible = false
	light.light_energy = 2.5
	light.rotation_degrees = Vector3(-55, -30, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.77, 0.85)
	var clouds := tower.get_node("OutdoorClouds") as Node3D
	var cloud_visible := clouds.visible
	environment.fog_enabled = false
	environment.volumetric_fog_enabled = false
	environment.ambient_light_energy = 0.8
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.32, 0.38, 0.44)
	clouds.visible = false
	var diagnostic := Camera3D.new()
	add_child(diagnostic)
	diagnostic.projection = Camera3D.PROJECTION_ORTHOGONAL
	diagnostic.far = 1600
	diagnostic.make_current()
	var batches := tower.find_children("*", "MultiMeshInstance3D", true, false)
	var ranges: Dictionary = {}
	for batch in batches:
		ranges[batch.get_instance_id()] = batch.visibility_range_end
		batch.visibility_range_end = 0.0
	for view in [{"name": "overview_500", "pos": Vector3(410, 470, 480), "target": Vector3(3.750313, -55, -40.770721), "size": 670.0}, {"name": "tower3_surroundings", "pos": Vector3(-245, 220, -420), "target": Vector3(-12, -50, -190), "size": 330.0}]:
		diagnostic.position = view["pos"]
		diagnostic.size = view["size"]
		diagnostic.look_at(view["target"], Vector3.UP)
		var entry := await _save_view(diagnostic, view["name"], directory, "诊断概览：暂时关雾/云与HUD、提高环境及太阳亮度并调整太阳角度、取消批次距离裁剪；结束逐项恢复，不写回正式环境；不是玩家视角")
		var projections: Array = []
		for x in [-246.249687, 253.750313]:
			for z in [-290.770721, 209.229279]:
				var point := Vector3(x, -80, z)
				var pixel := diagnostic.unproject_position(point)
				projections.append([pixel.x / 1600.0, pixel.y / 1000.0])
		entry["ground_corner_projections"] = projections
		results.append(entry)
	for batch in batches:
		batch.visibility_range_end = ranges[batch.get_instance_id()]
	for key in before:
		environment.set(key, before[key])
	clouds.visible = cloud_visible
	light.light_energy = light_before["energy"]
	light.rotation = light_before["rotation"]
	for ui in canvas_visibility:
		ui.visible = canvas_visibility[ui]
	diagnostic.queue_free()
	camera.make_current()
	return results
