extends SceneTree
## v007 私有资产机验；不修改正式房间、账本和 tests。
const SOURCE := "res://assets/art/environments/open_world/source/landscape_skyline20/v007"
const RUNTIME := "res://assets/art/environments/open_world/runtime/landscape_skyline20"
const ROOT_SCENE := RUNTIME + "/env_landscape_skyline20_root_top3d.tscn"
const PALETTE := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
const EPS := 0.001
var passes := 0
var failures := 0
var messages: Array[String] = []
var catalog: Dictionary
var reports: Array = []

func _initialize() -> void:
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()
		return
	catalog = _read(SOURCE + "/component_catalog.json")
	var data := _read(SOURCE + "/component_instances.json")
	var plan := _read(SOURCE + "/component_plan.json")
	var frozen := _read(SOURCE + "/qa/component_plan_frozen_before_mesh.json")
	_check(not catalog.is_empty() and not data.is_empty(), "清单存在")
	if catalog.is_empty() or data.is_empty():
		_finish()
		return
	_check(plan == frozen, "计划与网格前冻结证据完全一致")
	_check(str(plan.get("freeze_stage")) == "before_builder_and_mesh_creation", "计划时序正确")
	_check(str(catalog.get("version")) == "v007", "catalog版本正确")
	_check(str(catalog.get("schema")) == "shellstorm2.openworld.component_catalog", "catalog schema正确")
	_check(str(data.get("schema")) == "shellstorm2.openworld.component_instances", "实例schema正确")
	_check(FileAccess.get_sha256("res://" + str(catalog["source_blend"])) == str(catalog["source_sha256"]), "源文件实际哈希一致")
	_check(FileAccess.get_sha256("res://" + str(catalog["optimized_blend"])) == str(catalog["optimized_sha256"]), "优化文件实际哈希一致")
	var protection := _read(SOURCE + "/qa/protected_files.json")
	for key in protection.get("before", {}):
		_check(FileAccess.get_sha256("res://" + str(key)) == str(protection["before"][key]), "保护文件未变: " + str(key))
	var components: Dictionary = {}
	for entry in catalog["components"]:
		var record: Dictionary = entry
		var slug := str(record["slug"])
		_check(not components.has(slug), "组件slug唯一:" + slug)
		components[slug] = record
		_probe_component(record)
	_check(components.size() == 8 and components.size() <= 50, "八个活跃组件，预算合规")
	var hvac_dims: Array = components["roof_hvac_unit"]["bbox_m"]
	_check(absf(float(hvac_dims[0]) - 6) < EPS and absf(float(hvac_dims[1]) - 5) < EPS and float(hvac_dims[2]) >= 3 and float(hvac_dims[2]) <= 4, "HVAC真实尺寸6x5x3-4m")
	var tower_dims: Array = components["roof_truss_tower"]["bbox_m"]
	_check(float(tower_dims[2]) >= 7 and float(tower_dims[2]) <= 9, "tower真实高度7-9m")
	var dish_dims: Array = components["roof_satellite_dish"]["bbox_m"]
	_check(float(dish_dims[0]) >= 8 and float(dish_dims[0]) <= 10, "dish真实直径8-10m")
	var bill_dims: Array = components["facade_billboard"]["bbox_m"]
	_check(absf(float(bill_dims[0]) - 16) < EPS and absf(float(bill_dims[2]) - 30) < EPS, "广告真实竖幅16x30m")
	_check(not components.has("roof_hvac_bank") and not components.has("roof_communications"), "旧区域包不活跃")
	var rows: Dictionary = {}
	var counts: Dictionary = {}
	for value in data["instances"]:
		var row: Dictionary = value
		_check(not rows.has(row["instance_id"]), "实例ID唯一")
		rows[row["instance_id"]] = row
		var slug := str(row["slug"])
		counts[slug] = int(counts.get(slug, 0)) + 1
	_check(rows.size() == 37 and rows.size() == int(data["validation"]["instance_count"]), "37个实例")
	for definition in plan["definitions"]:
		_check(int(counts.get(definition["slug"], 0)) == int(definition["instance_count"]), "定义实例数与冻结计划一致")
	_check(int(counts.get("roof_hvac_unit", 0)) == 4, "四台独立HVAC实例")
	_check(int(counts.get("roof_truss_tower", 0)) == 2, "两座独立通信塔实例")
	_check(int(counts.get("roof_satellite_dish", 0)) == 1, "单独实心dish")
	_probe_root(rows, components)
	var file := FileAccess.open(SOURCE + "/qa/probe_skyline20_v007.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": "shellstorm2.openworld.godot_probe.v002", "version": "v007", "pass": passes, "fail": failures, "status": "passed" if failures == 0 else "failed", "components": reports, "messages": messages}, "  "))
	file.close()
	var qa := _read(SOURCE + "/qa/qa_report.json")
	qa["godot_runtime_probe"] = {"status": "passed" if failures == 0 else "failed", "pass": passes, "fail": failures}
	qa["status"] = "GODOT_MACHINE_CHECKS_PASSED_VISUAL_REVIEW_PENDING" if failures == 0 else "GODOT_MACHINE_CHECKS_FAILED"
	file = FileAccess.open(SOURCE + "/qa/qa_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(qa, "  "))
	file.close()
	_finish()

func _probe_component(record: Dictionary) -> void:
	var slug := str(record["slug"])
	_check(FileAccess.get_sha256("res://" + str(record["glb"])) == str(record["glb_sha256"]), slug + " GLB哈希")
	_check(int(record["glb_inspection"]["images"]) == 0 and int(record["glb_inspection"]["textures"]) == 0, slug + " GLB无图片纹理")
	var package := _read(RUNTIME + "/" + slug + "/asset_manifest.json")
	_check(str(package.get("source_sha256")) == str(catalog["source_sha256"]), slug + " 包源哈希")
	_check(str(package.get("component_id")) == str(record["component_id"]), slug + " 组件ID")
	_check(str(package.get("version")) == "v007", slug + " 包版本")
	var packed := load("res://" + str(record["prefab"])) as PackedScene
	_check(packed != null, slug + "独立可加载")
	if packed == null:
		return
	var node := packed.instantiate() as Node3D
	_check(node != null, slug + "独立可实例化")
	_check(_identity(node.transform), slug + "根恒等")
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	_check(meshes.size() == (record["source_objects"] as Array).size(), slug + "真实主体/可选自发光数量")
	var triangles := 0
	var union: AABB
	var started := false
	for value in meshes:
		var mesh := value as MeshInstance3D
		triangles += _triangles(mesh.mesh)
		var t := _relative(mesh, node)
		_check(_identity(t), slug + "Mesh到根全层级恒等")
		var box := t * mesh.get_aabb()
		union = union.merge(box) if started else box
		started = true
		_check(mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, slug + "真实投影")
		_check(mesh.mesh.get_surface_count() <= (1 if str(mesh.name).contains("自发光") else 3), slug + "表面预算")
		for surface in range(mesh.mesh.get_surface_count()):
			_material(mesh.get_active_material(surface), str(mesh.name).contains("自发光"))
	_check(triangles == int(record["triangles_after"]), slug + "Godot三角与Blender/GLB一致")
	var dims: Array = record["bbox_m"]
	_check(union.size.distance_to(Vector3(float(dims[0]), float(dims[2]), float(dims[1]))) < EPS, slug + "尺寸轴映射")
	_check(absf(union.position.y) < EPS and absf(union.get_center().x) < EPS and absf(union.get_center().z) < EPS, slug + "底部中心原点")
	reports.append({"slug": slug, "mesh_count": meshes.size(), "triangles": triangles, "aabb": _box(union)})
	node.free()

func _probe_root(rows: Dictionary, components: Dictionary) -> void:
	var packed := load(ROOT_SCENE) as PackedScene
	_check(packed != null, "私有root可加载")
	if packed == null:
		return
	var building := packed.instantiate() as Node3D
	_check(_identity(building.transform), "整栋根恒等")
	_check(building.get_child_count() == rows.size(), "整栋实例数守恒")
	var union: AABB
	var started := false
	var total := 0
	var roof_total := 0
	var equipment: Dictionary = {}
	var root_mesh_count := 0
	for value in building.get_children():
		var child := value as Node3D
		var name := str(child.name)
		_check(rows.has(name), "实例存在:" + name)
		if not rows.has(name):
			continue
		var row: Dictionary = rows[name]
		var slug := str(row["slug"])
		var angle := deg_to_rad(float(row["rotation_y_deg"]))
		_check(child.position.distance_to(_map(row["position_m"])) < EPS, name + "坐标映射")
		_check(absf(child.rotation.y - angle) < EPS, name + "旋转映射")
		_check(child.scale.distance_to(Vector3.ONE) < EPS, name + "单位缩放")
		_check(str(child.get_meta("asset_version", "")) == "v007", name + "实例版本")
		_check(str(child.get_meta("component_id", "")) == str(row["component_id"]), name + "实例组件ID")
		_check((child.position - child.basis * _map(row["geometry_offset_m"])).distance_to(_map(row["reference_position_m"])) < EPS, name + "offset补偿")
		var meshes := child.find_children("*", "MeshInstance3D", true, false)
		root_mesh_count += meshes.size()
		var triangles := 0
		var child_box: AABB
		var child_started := false
		for mesh_value in meshes:
			var mesh := mesh_value as MeshInstance3D
			triangles += _triangles(mesh.mesh)
			_check(_identity(_relative(mesh, child)), name + "组件内部恒等")
			var box := _relative(mesh, building) * mesh.get_aabb()
			child_box = child_box.merge(box) if child_started else box
			child_started = true
			union = union.merge(box) if started else box
			started = true
			for surface in range(mesh.mesh.get_surface_count()):
				_material(mesh.get_active_material(surface), str(mesh.name).contains("自发光"))
		_check(triangles == int(components[slug]["triangles_after"]), name + "实例三角一致")
		total += triangles
		if slug.begins_with("roof_"):
			roof_total += triangles
			if slug != "roof_guardrail_kit":
				equipment[name] = child_box
				_check(absf(child_box.position.y - 76.36) < EPS, name + "贴合屋面")
				_check(child_box.position.x >= -23.5 and child_box.end.x <= 23.5 and child_box.position.z >= -23.5 and child_box.end.z <= 23.5, name + "护栏净空")
		if slug == "facade_hvac_unit":
			_check((child.basis * Vector3.BACK).dot(Vector3(signf(child.position.x), 0, 0)) > .999, name + "空调朝外")
		if slug == "facade_billboard":
			_check(absf(child.position.x) >= 25 or absf(child.position.z) >= 25, name + "广告贴立面")
			_check(child_box.end.y < 76, name + "广告不遮屋顶")
	_check(total == int(catalog["runtime_triangle_budget"]["actual"]) and total <= 10000, "整栋三角预算")
	_check(float(roof_total) / total >= .45, "屋顶结构设备占比至少45%")
	_check(building.find_children("*", "CollisionObject3D", true, false).is_empty() and building.find_children("*", "CollisionShape3D", true, false).is_empty(), "无碰撞")
	var dims: Array = components["floor_facade_module"]["bbox_m"]
	_check(absf(float(dims[0]) - 50) < EPS and absf(float(dims[1]) - 50) < EPS, "主体50x50m")
	for index in range(1, 21):
		_check(rows.has("floor_%02d" % index), "楼层存在")
		var pos: Array = rows["floor_%02d" % index]["reference_position_m"]
		_check(absf(float(pos[2]) - (index - 1) * 3.8) < EPS, "20层3.8m层距，无底层")
	var names := equipment.keys()
	for i in range(names.size()):
		for j in range(i + 1, names.size()):
			var a: AABB = equipment[names[i]]
			var b: AABB = equipment[names[j]]
			var dx := maxf(maxf(b.position.x - a.end.x, a.position.x - b.end.x), 0)
			var dz := maxf(maxf(b.position.z - a.end.z, a.position.z - b.end.z), 0)
			_check(Vector2(dx, dz).length() >= .999, "设备包络间隔至少1m: %s/%s" % [names[i], names[j]])
	var bounds: Array = catalog["measured_assembly_bounds"]["bounds_local"]
	_check(union.position.distance_to(Vector3(float(bounds[0]), float(bounds[2]), -float(bounds[4]))) < EPS, "整栋包络最小值")
	_check(union.end.distance_to(Vector3(float(bounds[3]), float(bounds[5]), -float(bounds[1]))) < EPS, "整栋包络最大值")
	reports.append({"slug": "private_root", "triangles": total, "roof_triangles": roof_total, "roof_share": float(roof_total) / total, "child_count": building.get_child_count(), "mesh_count": root_mesh_count, "aabb": _box(union)})
	building.free()

func _material(material: Material, glow: bool) -> void:
	_check(material is BaseMaterial3D, "BaseMaterial3D")
	if not material is BaseMaterial3D:
		return
	var base := material as BaseMaterial3D
	_check(base.albedo_texture != null and base.albedo_texture.resource_path == PALETTE, "唯一公共palette")
	_check(base.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "最近邻")
	_check(not base.texture_repeat, "不重复")
	_check(base.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "不透明")
	_check(base.emission_enabled == glow, "主体与可选发光分离")
	if glow:
		_check(base.emission_energy_multiplier > 0 and base.emission_energy_multiplier <= 1.6, "柔和发光")
		_check(base.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY, "色盘发光相乘")

func _triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var indices = arrays[Mesh.ARRAY_INDEX]
		total += int(indices.size() / 3) if indices != null and indices.size() > 0 else int(arrays[Mesh.ARRAY_VERTEX].size() / 3)
	return total

func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result

func _capture() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child((load(ROOT_SCENE) as PackedScene).instantiate())
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.07, .09, .12)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .5
	stage.add_child(env)
	var key := DirectionalLight3D.new()
	stage.add_child(key)
	key.rotation_degrees = Vector3(-45, -35, 0)
	key.light_color = Color(1, .96, .90)
	key.light_energy = 1.0
	key.shadow_enabled = true
	var fill := DirectionalLight3D.new()
	stage.add_child(fill)
	fill.rotation_degrees = Vector3(-35, 140, 0)
	fill.light_energy = .8
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 500
	camera.current = true
	var capture_paths: Array = []
	for spec in [["full", Vector3(105, 105, 125), Vector3(0, 40, 0), 104.0], ["roof", Vector3(58, 116, 70), Vector3(0, 78, 0), 85.0]]:
		camera.position = spec[1]
		camera.size = spec[3]
		camera.look_at(spec[2])
		for index in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		var path := SOURCE + "/qa/godot_runtime_" + str(spec[0]) + ".png"
		var image := root.get_texture().get_image()
		var code := image.save_png(ProjectSettings.globalize_path(path))
		print("SKYLINE20_CAPTURE_RESULT %d %s" % [code, path])
		_check(code == OK, "原生截图保存")
		capture_paths.append(path)
	var file := FileAccess.open(SOURCE + "/qa/godot_capture.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"status": "passed" if failures == 0 else "failed", "native_viewport": true, "renderer": RenderingServer.get_video_adapter_name(), "paths": capture_paths}, "  "))
	file.close()
	stage.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _map(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[2]), -float(values[1]))
func _identity(t: Transform3D) -> bool:
	return t.origin.length() < EPS and t.basis.is_equal_approx(Basis.IDENTITY)
func _box(box: AABB) -> Dictionary:
	return {"position": [box.position.x, box.position.y, box.position.z], "size": [box.size.x, box.size.y, box.size.z]}
func _read(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value as Dictionary if value is Dictionary else {}
func _check(condition: bool, message: String) -> void:
	if condition:
		passes += 1
	else:
		failures += 1
		messages.append(message)
func _finish() -> void:
	print("SKYLINE20_GODOT_PROBE_%s pass=%d fail=%d" % ["OK" if failures == 0 else "FAILED", passes, failures])
	for message in messages:
		print(message)
	quit(0 if failures == 0 else 1)
