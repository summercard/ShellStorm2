extends Node

const ROUTE_PATH := "res://assets/art/environments/open_world/runtime/cross_tower_route/env_cross_tower_route_root_top3d.tscn"
const FLOOR_PATH := "res://assets/art/environments/tower_descent_3d/runtime/floor_tile_5m/env_tower_floor_tile_5m_root_top3d.tscn"
var _points: Array[Vector3] = []
var _mesh_boxes: Array = []
const FOUNDATION_SCENES := [
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/foundation_tower1_box.tscn",
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/foundation_tower2_box.tscn",
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/foundation_tower3_box.tscn",
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/foundation_skyline08_box.tscn",
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/ground_plane_box.tscn",
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/remote_tower2_a.tscn",
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/remote_tower2_b.tscn",
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/remote_tower3_a.tscn",
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/remote_skyline08_a.tscn",
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/city_ring0_index2_extension.tscn",
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/city_ring0_index8_extension.tscn",
]

func _ready() -> void:
	call_deferred("_run")

func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _collect(node: Node, parent_transform: Transform3D, parent_visible: bool) -> void:
	var current := parent_transform
	var shown := parent_visible
	if node is Node3D:
		current = parent_transform * (node as Node3D).transform
		shown = parent_visible and (node as Node3D).visible
	if node is MeshInstance3D and shown:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			var box := mesh_node.mesh.get_aabb()
			var world_box := current * box
			_mesh_boxes.append({"path": str(node.get_path()) if node.is_inside_tree() else str(node.name), "min": _vector(world_box.position), "max": _vector(world_box.end)})
			for index in range(8):
				_points.append(current * box.get_endpoint(index))
	if node is MultiMeshInstance3D and shown:
		var batch := (node as MultiMeshInstance3D).multimesh
		if batch != null and batch.mesh != null:
			var box := batch.mesh.get_aabb()
			for instance_index in range(batch.instance_count):
				var instance_transform := current * batch.get_instance_transform(instance_index)
				for corner in range(8):
					_points.append(instance_transform * box.get_endpoint(corner))
	for child in node.get_children():
		_collect(child, current, shown)

func _bounds(node: Node, parent_transform := Transform3D.IDENTITY) -> Dictionary:
	_points.clear()
	_mesh_boxes.clear()
	_collect(node, parent_transform, true)
	if _points.is_empty():
		return {"mesh_bounds_found": false}
	var lo := _points[0]
	var hi := lo
	for point in _points:
		lo = lo.min(point)
		hi = hi.max(point)
	return {"min": _vector(lo), "max": _vector(hi), "size": _vector(hi - lo), "center": _vector((lo + hi) * 0.5), "mesh_bounds_found": true, "mesh_boxes": _mesh_boxes.duplicate(true)}

func _run() -> void:
	var packed := load(ROUTE_PATH) as PackedScene
	if packed == null:
		get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("完整壳体探针必须使用真实渲染器回读 MultiMesh")
		get_tree().quit(2)
		return
	var tower := (load("res://scenes/TowerDescent3D.tscn") as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	for frame in range(8):
		await get_tree().process_frame
	var planned_indices: Array = tower._floor_plan_snapshots.keys()
	planned_indices.sort()
	for floor_index in planned_indices:
		if not tower.call("_commit_floor_bundle", floor_index, "landscape_geometry_probe"):
			push_error("完整楼层提交失败：%d" % floor_index)
			get_tree().quit(2)
			return
		await get_tree().process_frame
	tower.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().process_frame
	var route := tower.get_node("Blocks/Rooftop/CrossTowerRoute") as Node3D
	var report := {"engine": Engine.get_version_info(), "renderer": DisplayServer.get_name(), "route_path": ROUTE_PATH, "targets": {}, "bridge": {}, "city": [], "foundation": [], "independent_loads": [], "main_tower_stages": []}
	var shell_boxes: Array[AABB] = []
	for floor_index in tower._floor_stages:
		var stage := tower._floor_stages[floor_index] as Node3D
		stage.visible = true
		var entry := _bounds(stage, stage.get_parent().global_transform)
		entry["floor_index"] = floor_index
		entry["transform"] = var_to_str(stage.transform)
		entry["floor_number"] = stage.get_meta("floor_number", 100 - int(floor_index))
		report["main_tower_stages"].append(entry)
		if entry["mesh_bounds_found"]:
			var lo: Array = entry["min"]
			var hi: Array = entry["max"]
			shell_boxes.append(AABB(Vector3(lo[0], lo[1], lo[2]), Vector3(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])))
	var shell := shell_boxes[0]
	for box in shell_boxes:
		shell = shell.merge(box)
	report["targets"]["Tower1"] = {"min": _vector(shell.position), "max": _vector(shell.end), "size": _vector(shell.size), "mesh_bounds_found": true, "source": "当前正式计划内全部楼层已提交，真实渲染器逐Mesh/MultiMesh实测，不假造工程尚未启用的更深楼层"}
	for target_name in ["Tower2", "Tower3", "Skyline08"]:
		var target := route.get_node(target_name) as Node3D
		var entry := _bounds(target, route.transform)
		entry["transform"] = var_to_str(target.transform)
		entry["position"] = _vector(target.position)
		report["targets"][target_name] = entry
	for block in tower.get_node("Blocks").get_children():
		if block is Node3D:
			block.visible = true
	for room in tower._room_by_id.values():
		room.ensure_shell_built()
		room.visible = true
	route.visible = false
	report["targets"]["Tower1"] = _bounds(tower.get_node("Blocks"), tower.global_transform)
	report["targets"]["Tower1"]["source"] = "当前正式计划全部楼层；Blocks内实际可见结构（排除CrossTowerRoute），包含房间、楼梯及Mesh/MultiMesh"
	route.visible = true
	report["tower2_body"] = _bounds(route.get_node("Tower2/architecture"), route.get_node("Tower2").global_transform)
	report["skyline_body"] = _bounds(route.get_node("Skyline08/architecture"), route.get_node("Skyline08").global_transform)
	for child in route.get_node("Bridge").get_children():
		var entry := _bounds(child, route.global_transform)
		entry["transform"] = var_to_str((child as Node3D).transform)
		report["bridge"][str(child.name)] = entry
	var floor_packed := load(FLOOR_PATH) as PackedScene
	var floor_node := floor_packed.instantiate() as Node3D
	report["floor98_asset_local"] = _bounds(floor_node)
	floor_node.free()
	var atmosphere := TowerAtmosphere3D.new()
	var layout := atmosphere.build_city_layout()
	for placement in layout:
		var box: AABB = placement["transform"] * AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
		report["city"].append({"ring": placement["ring"], "index": placement["index"], "min": _vector(box.position), "max": _vector(box.end), "size": _vector(placement["size"]), "top_y": placement["top_y"], "transform": var_to_str(placement["transform"])})
	atmosphere.free()
	var foundation := route.get_node("LandscapeFoundation")
	for child in foundation.get_children():
		var entry := _bounds(child, foundation.global_transform)
		entry["name"] = str(child.name)
		entry["position"] = _vector((child as Node3D).position)
		entry["metadata"] = {}
		for key in child.get_meta_list():
			entry["metadata"][str(key)] = child.get_meta(key)
		report["foundation"].append(entry)
	var foundation_packed := load(foundation.scene_file_path) as PackedScene
	var independent := foundation_packed.instantiate()
	report["independent_loads"].append({"path": foundation.scene_file_path, "loaded": independent != null})
	independent.free()
	for scene_path in FOUNDATION_SCENES:
		var component_packed := load(scene_path) as PackedScene
		var component := component_packed.instantiate() if component_packed != null else null
		report["independent_loads"].append({"path": scene_path, "loaded": component != null})
		if component != null:
			component.free()
	var city_nodes := tower.find_children("CityBuildingSilhouettes", "MultiMeshInstance3D", true, false)
	if not city_nodes.is_empty():
		var city := city_nodes[0] as MultiMeshInstance3D
		report["city_runtime_instances"] = []
		for index in range(city.multimesh.instance_count):
			var transform := city.multimesh.get_instance_transform(index)
			var box := city.global_transform * transform * AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
			report["city_runtime_instances"].append({"index": index, "transform": var_to_str(transform), "min": _vector(box.position), "max": _vector(box.end)})
		for entry in report["foundation"]:
			var child := foundation.get_node(str(entry["name"]))
			entry["city_material_same_object"] = child is MeshInstance3D and (child as MeshInstance3D).material_override == city.multimesh.mesh.surface_get_material(0)
	report["landscape_collision_count"] = foundation.find_children("*", "CollisionObject3D", true, false).size() + foundation.find_children("*", "CollisionShape3D", true, false).size()
	var output := OS.get_environment("LANDSCAPE_OUTPUT")
	if output.is_empty():
		push_error("必须显式设置 LANDSCAPE_OUTPUT，不能写入正式存档目录")
		tower.queue_free()
		get_tree().quit(2)
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("探针输出路径不可写")
		tower.queue_free()
		get_tree().quit(2)
		return
	if OS.get_environment("LANDSCAPE_CAPTURE") == "1":
		report["screenshots"] = await _capture(tower, output.get_base_dir())
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("LANDSCAPE_RUNTIME_DUMP_OK city=%d foundation=%d output=%s" % [layout.size(), foundation.get_child_count(), output])
	tower.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)

func _capture(tower: Node3D, directory: String) -> Array:
	var results: Array = []
	for ui in tower.find_children("*", "CanvasLayer", true, false):
		ui.visible = false
	var environment_node := tower.get_node("WorldEnvironment") as WorldEnvironment
	var environment := environment_node.environment
	environment.fog_enabled = false
	environment.volumetric_fog_enabled = false
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.32, 0.38, 0.44)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.77, 0.85)
	environment.ambient_light_energy = 0.8
	for city_root in tower.find_children("RooftopCityBelow", "Node3D", true, false):
		city_root.visible = true
	for city in tower.find_children("CityBuildingSilhouettes", "MultiMeshInstance3D", true, false):
		city.visible = true
		city.visibility_range_end = 0.0
		city.layers = 1
	var clouds := tower.get_node_or_null("OutdoorClouds") as Node3D
	if clouds != null:
		clouds.visible = false
	var light := tower.get_node("DirectionalLight3D") as DirectionalLight3D
	light.light_energy = 2.5
	light.rotation_degrees = Vector3(-55, -30, 0)
	var camera := Camera3D.new()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 1600.0
	camera.make_current()
	var views := [
		{"name": "overview", "position": Vector3(320, 255, 330), "target": Vector3(4, -48, -42), "size": 350.0},
		{"name": "tower2_ground", "position": Vector3(235, 115, 10), "target": Vector3(62, -62, -110), "size": 210.0},
		{"name": "tower3_skyline", "position": Vector3(-210, 95, -275), "target": Vector3(-30, -49, -148), "size": 225.0},
		{"name": "city_downward_extensions", "position": Vector3(165, -14, 90), "target": Vector3(17, -66, -37), "size": 150.0},
		{"name": "city_r0_i2_contact", "position": Vector3(-25, 20, -135), "target": Vector3(-25, -50, -58.75029), "size": 105.0},
		{"name": "city_r0_i8_contact", "position": Vector3(150, 20, -20), "target": Vector3(73.303024, -50, -20), "size": 105.0},
	]
	for view in views:
		var isolated: Node3D = null
		var contact_viewport: SubViewport = null
		if str(view["name"]).ends_with("contact"):
			contact_viewport = SubViewport.new()
			contact_viewport.size = Vector2i(1600, 1000)
			contact_viewport.own_world_3d = true
			contact_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(contact_viewport)
			isolated = Node3D.new()
			contact_viewport.add_child(isolated)
			var contact_environment := WorldEnvironment.new()
			contact_environment.environment = environment.duplicate() as Environment
			isolated.add_child(contact_environment)
			var contact_light := DirectionalLight3D.new()
			contact_light.light_energy = 2.5
			contact_light.rotation_degrees = Vector3(-55, -30, 0)
			isolated.add_child(contact_light)
			camera.reparent(isolated)
			camera.make_current()
			var city := tower.find_children("CityBuildingSilhouettes", "MultiMeshInstance3D", true, false)[0] as MultiMeshInstance3D
			var city_index := 2 if view["name"] == "city_r0_i2_contact" else 8
			var original := MeshInstance3D.new()
			original.mesh = city.multimesh.mesh
			original.transform = city.global_transform * city.multimesh.get_instance_transform(city_index)
			original.material_override = city.multimesh.mesh.surface_get_material(0)
			isolated.add_child(original)
			var source := tower.get_node("Blocks/Rooftop/CrossTowerRoute/LandscapeFoundation")
			for component_name in ["OpenWorldGroundPlane", "CityRing0Index%dExtension" % city_index]:
				var component := source.get_node(component_name) as MeshInstance3D
				var copy := MeshInstance3D.new()
				copy.mesh = component.mesh
				copy.material_override = component.material_override
				copy.transform = component.global_transform
				isolated.add_child(copy)
			tower.get_node("Blocks").visible = false
			for city_root in tower.find_children("RooftopCityBelow", "Node3D", true, false):
				city_root.visible = false
		camera.position = view["position"]
		camera.size = view["size"]
		camera.look_at(view["target"], Vector3.UP)
		for frame in range(6):
			environment.background_color = Color(0.32, 0.38, 0.44)
			environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			environment.ambient_light_color = Color(0.7, 0.77, 0.85)
			environment.ambient_light_energy = 0.8
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := contact_viewport.get_texture().get_image() if contact_viewport != null else get_viewport().get_texture().get_image()
		var path := directory.path_join(str(view["name"]) + ".png")
		var error := image.save_png(path)
		var framing: Array = []
		var landscape := tower.get_node("Blocks/Rooftop/CrossTowerRoute/LandscapeFoundation")
		for child in landscape.get_children():
			var center := (child as Node3D).global_position
			var screen := camera.unproject_position(center)
			var viewport_size := get_viewport().get_visible_rect().size
			framing.append({"name": str(child.name), "normalized_projection": [screen.x / viewport_size.x, screen.y / viewport_size.y], "in_frame": not camera.is_position_behind(center) and screen.x > viewport_size.x * 0.05 and screen.x < viewport_size.x * 0.95 and screen.y > viewport_size.y * 0.05 and screen.y < viewport_size.y * 0.95})
		results.append({"path": path, "save_error": error, "framing": framing, "camera_position": _vector(camera.position), "target": _vector(view["target"]), "orthographic_size": camera.size, "presentation": "独立结构验收机位；仅验收关闭雾云和HUD、提高环境亮度，正式场景不改"})
		print("LANDSCAPE_SCREENSHOT %s error=%d" % [path, error])
		if isolated != null:
			camera.reparent(self)
			camera.make_current()
			contact_viewport.queue_free()
			tower.get_node("Blocks").visible = true
			for city_root in tower.find_children("RooftopCityBelow", "Node3D", true, false):
				city_root.visible = true
			await get_tree().process_frame
	camera.queue_free()
	return results
