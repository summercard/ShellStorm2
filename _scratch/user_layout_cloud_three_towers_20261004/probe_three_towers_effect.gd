extends Node

const OUTPUT_DIR := "res://outputs/open_world_chunk_layout_20261004/user_final/three_towers_effect"

var tower: Node
var clouds: Node
var report: Dictionary = {"views": [], "checks": [], "failures": []}

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	report["checks"].append({"ok": condition, "message": message})
	if not condition:
		report["failures"].append(message)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		report["failures"].append("真实渲染探针不能在headless运行")
		_save_report()
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	Engine.max_fps = 0
	get_window().size = Vector2i(1280, 720)
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	_check(packed != null, "正式场景必须加载")
	if packed == null:
		_save_report()
		get_tree().quit(2)
		return
	tower = packed.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", 990095)
	add_child(tower)
	for frame in range(180):
		await get_tree().process_frame
		if tower.get_node_or_null("OutdoorClouds") != null and tower.get_node_or_null("Blocks/Rooftop/CrossTowerRoute/LandscapeFoundation") != null:
			break
	clouds = tower.get_node_or_null("OutdoorClouds")
	_check(clouds != null, "OutdoorClouds必须存在")
	if clouds == null:
		_save_report()
		get_tree().quit(2)
		return
	await _warm_frames(30)
	_verify_layout()
	_verify_cloud_contract()
	clouds.set_process(false)
	clouds.set("_flow_time", 24.0)
	clouds.call("_sync_dynamic_materials")
	for layer in tower.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	var camera := Camera3D.new()
	tower.add_child(camera)
	camera.far = 520.0
	camera.fov = 58.0
	camera.make_current()
	var views := [
		{"name": "main_landscape", "position": Vector3(78, 37, 88), "target": Vector3(0, -35, -15)},
		{"name": "tower3_cloud_edge", "position": Vector3(-95, 18, -90), "target": Vector3(-12, -42, -153.925626)},
		{"name": "peripheral_chunks_cloud_overlap", "position": Vector3(-130, -8, -95), "target": Vector3(-110, -50, -150)}
	]
	for view: Dictionary in views:
		camera.position = view["position"]
		camera.look_at(view["target"], Vector3.UP)
		await _warm_frames(12)
		await RenderingServer.frame_post_draw
		var projected: Vector2 = camera.unproject_position(view["target"])
		_check(not camera.is_position_behind(view["target"]) and projected.x > 64 and projected.x < 1216 and projected.y > 36 and projected.y < 684, "取景目标在画面内部：" + str(view["name"]))
		var image := get_viewport().get_texture().get_image()
		var brightness_bins: Dictionary = {}
		for y in range(0, image.get_height(), 8):
			for x in range(0, image.get_width(), 8):
				var color := image.get_pixel(x, y)
				brightness_bins[int((color.r + color.g + color.b) / 3.0 * 63.0)] = true
		_check(brightness_bins.size() >= 8, "截图非空且至少8级亮度：" + str(view["name"]))
		var file_name := str(view["name"]) + ".png"
		var save_path := OUTPUT_DIR.path_join(file_name)
		var error := image.save_png(ProjectSettings.globalize_path(save_path))
		_check(error == OK, "截图保存成功：" + file_name)
		report["views"].append({"name": view["name"], "camera": view["position"], "target": view["target"], "screenshot": save_path, "resolution": [image.get_width(), image.get_height()]})
	var snapshot: Dictionary = clouds.call("get_presentation_snapshot")
	report["cloud_snapshot"] = snapshot
	report["cloud_clearance_scope"] = snapshot.get("clearance_scope", "")
	report["cloud_keepout_count"] = int(snapshot.get("keepout_count", -1))
	report["authored_chunk_policy"] = "8区块157栋只渲染，不上传云避让"
	report["legacy_procedural_city_policy"] = "ProceduralCity500未挂载；旧小楼不参与云避让"
	report["art_shader_policy"] = "保留原云材质参数、流动、密度与颜色；仅切换避让对象"
	report["source_sha256_end"] = FileAccess.get_sha256("res://scenes/open_world_layout_edit/open_world_chunk_layout_edit.tscn")
	_check(report.get("source_sha256_start", "") == report["source_sha256_end"], "用户摆位源在验证期间未变")
	_save_report()
	tower.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if report["failures"].is_empty() else 1)

func _world_transform(node: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent != null:
		if parent is Node3D:
			result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result

func _mesh_bounds(root: Node) -> AABB:
	var result := AABB()
	var found := false
	var nodes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		nodes.append(root)
	for value in nodes:
		var mesh_node := value as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var box := VfxCloudSea3D._transformed_box(mesh_node.get_aabb(), _world_transform(mesh_node))
		result = result.merge(box) if found else box
		found = true
	return result

func _verify_layout() -> void:
	var source_path := "res://scenes/open_world_layout_edit/open_world_chunk_layout_edit.tscn"
	report["source_sha256_start"] = FileAccess.get_sha256(source_path)
	var source := (load(source_path) as PackedScene).instantiate()
	var foundation := tower.get_node("Blocks/Rooftop/CrossTowerRoute/LandscapeFoundation")
	var chunks := foundation.get_node("AuthoredCityChunks")
	_check(foundation.get_node_or_null("ProceduralCity500") == null, "正式景观不挂载旧200栋程序城")
	var chunk_count := 0
	var building_count := 0
	var mesh_count := 0
	var matching := true
	for child in source.get_children():
		if not child is Node3D or not child.has_meta("chunk_id"):
			continue
		chunk_count += 1
		var actual := chunks.get_node_or_null(NodePath(str(child.name))) as Node3D
		if actual == null:
			matching = false
			continue
		matching = matching and _world_transform(child).is_equal_approx(actual.global_transform)
		matching = matching and child.scene_file_path == actual.scene_file_path
		var buildings := child.get_node("buildings")
		building_count += buildings.get_child_count()
		for building in buildings.get_children():
			var actual_building := actual.get_node_or_null(NodePath("buildings/" + str(building.name))) as Node3D
			matching = matching and actual_building != null
			if actual_building != null:
				matching = matching and _world_transform(building).is_equal_approx(actual_building.global_transform)
		for value in child.find_children("*", "MeshInstance3D", true, false):
			mesh_count += 1
			var actual_mesh := actual.get_node_or_null(child.get_path_to(value)) as Node3D
			matching = matching and actual_mesh != null
			if actual_mesh != null:
				matching = matching and _world_transform(value).is_equal_approx(actual_mesh.global_transform)
	_check(chunk_count == 8 and chunks.get_child_count() == 8, "8个模板实例边界与名称一致")
	_check(building_count == 157 and mesh_count >= 157, "157栋楼逐楼及逐网格核对")
	_check(matching, "8个区块和全部楼体世界Transform与用户源一致")
	var source_ground := _mesh_bounds(source.get_node("open_world_ground_500x500"))
	var actual_ground := _mesh_bounds(foundation.get_node("OpenWorldGroundPlane"))
	_check(source_ground.position.is_equal_approx(actual_ground.position) and source_ground.size.is_equal_approx(actual_ground.size), "500x500地表实测世界包络一致")
	report["layout"] = {"chunks": chunk_count, "buildings": building_count, "meshes_compared": mesh_count, "ground_bounds": str(actual_ground), "world_transforms_match": matching, "north_overhang_m": maxf(0.0, actual_ground.position.z - _mesh_bounds(chunks).position.z)}
	source.free()

func _verify_cloud_contract() -> void:
	var route := tower.get_node("Blocks/Rooftop/CrossTowerRoute")
	var expected: Array[AABB] = [AABB(Vector3(-51.5, -100001.5, -36.5), Vector3(103, 200003, 83))]
	for target: String in ["Tower2", "Tower3"]:
		var box := _mesh_bounds(route.get_node(NodePath(target))).grow(1.5)
		var base := _mesh_bounds(route.get_node(NodePath("LandscapeFoundation/" + target + "FoundationBox"))).grow(1.5)
		expected.append(box.merge(base))
	var regions: Dictionary = clouds.get("_geometry_regions")
	_check(regions.size() == 3 and regions.has("main") and regions.has("route/Tower2") and regions.has("route/Tower3"), "区域身份严格只有三塔，不含小楼/SKYLINE/桥")
	_check(bool(clouds.get("main_towers_only")), "正式入口启用三塔模式")
	clouds.call("set_procedural_static_clearance_enabled", false)
	var empty_layout: Array[Dictionary] = []
	clouds.call("set_procedural_city_layout", empty_layout, {})
	_check((clouds.call("get_procedural_city_exclusion_bounds") as Array).is_empty(), "未来程序楼上传被三塔模式拒绝")
	for profile: String in ["low", "balanced", "high"]:
		clouds.call("apply_performance_quality", profile)
		var fallback: Array = clouds.call("get_fallback_bounds")
		var bounds_ok := fallback.size() == 3
		for wanted in expected:
			var found := false
			for box: AABB in fallback:
				found = found or (box.position.is_equal_approx(wanted.position) and box.size.is_equal_approx(wanted.size))
			bounds_ok = bounds_ok and found
		_check(bounds_ok, profile + ": GPU只收到三个正确世界包络")
		var materials_ok := true
		var volumes: Array = clouds.call("get_cloud_volumes")
		for volume: Dictionary in volumes:
			var material := (volume["node"] as MeshInstance3D).material_override as ShaderMaterial
			materials_ok = materials_ok and material != null
			if material == null:
				continue
			materials_ok = materials_ok and material.shader.resource_path == "res://src/vfx/CloudStaticClearance.gdshader"
			materials_ok = materials_ok and material.get_shader_parameter("legacy_building_distance_enabled") == false
			materials_ok = materials_ok and material.get_shader_parameter("procedural_city_enabled") == false
			materials_ok = materials_ok and material.get_shader_parameter("procedural_static_enabled") == false
			materials_ok = materials_ok and int(material.get_shader_parameter("fallback_count")) == 3
		_check(materials_ok and volumes.size() == 25, profile + ": 25份实际材质关闭旧距离场与小楼候选，禁用缓存不回退旧Shader")
	report["tower_fallback_bounds"] = []
	for box in expected:
		report["tower_fallback_bounds"].append({"min": str(box.position), "max": str(box.end)})

func _warm_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func _save_report() -> void:
	var path := OUTPUT_DIR.path_join("three_towers_effect_report.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  ") + "\n")
		file.close()
