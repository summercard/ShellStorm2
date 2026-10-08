extends SceneTree
## Skyline20 v006 只读 Godot 验收探针。
## 只加载本资产的 7 个 PackedScene 与私有整栋 root，不修改正式房间、账本或 tests。
## 输出：同目录 probe_skyline20_v006.json

const ASSET_ROOT := "res://assets/art/environments/open_world"
const SOURCE_ROOT := ASSET_ROOT + "/source/landscape_skyline20/v006"
const RUNTIME_ROOT := ASSET_ROOT + "/runtime/landscape_skyline20"
const ROOT_SCENE := RUNTIME_ROOT + "/env_landscape_skyline20_root_top3d.tscn"
const PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
const COMPONENT_SLUGS := [
	"floor_facade_module",
	"facade_hvac_unit",
	"roof_guardrail_kit",
	"roof_service_hut",
	"roof_hvac_bank",
	"roof_communications",
	"facade_billboard",
]
const EPSILON := 0.0001

var _pass := 0
var _fail := 0
var _messages: Array[String] = []
var _catalog: Dictionary = {}

func _initialize() -> void:
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()
		return
	var catalog := _read_json(SOURCE_ROOT + "/component_catalog.json")
	_catalog = catalog
	var instances := _read_json(SOURCE_ROOT + "/component_instances.json")
	var manifest := _read_json(RUNTIME_ROOT + "/asset_manifest.json")
	_expect(not catalog.is_empty(), "component_catalog.json 可读")
	_expect(not instances.is_empty(), "component_instances.json 可读")
	_expect(not manifest.is_empty(), "runtime asset_manifest.json 可读")
	if catalog.is_empty() or instances.is_empty() or manifest.is_empty():
		_finish()
		return

	_expect(str(catalog.get("schema", "")) == "shellstorm2.openworld.component_catalog", "catalog schema 正确")
	_expect(str(instances.get("schema", "")) == "shellstorm2.openworld.component_instances", "instances schema 正确")
	_expect(int(catalog.get("component_count", -1)) == COMPONENT_SLUGS.size(), "catalog 声明 7 个组件")
	_expect(int((instances.get("validation", {}) as Dictionary).get("instance_count", -1)) == 32, "instances 声明 32 个实例")

	var components: Dictionary = {}
	for value in catalog.get("components", []) as Array:
		var record := value as Dictionary
		components[str(record.get("slug", ""))] = record
	_expect(components.size() == COMPONENT_SLUGS.size(), "catalog 组件 slug 唯一且完整")

	var instance_rows: Dictionary = {}
	for value in instances.get("instances", []) as Array:
		var row := value as Dictionary
		instance_rows[str(row.get("instance_id", ""))] = row
	_expect(instance_rows.size() == 32, "实例 instance_id 唯一")

	var component_reports: Array = []
	for slug in COMPONENT_SLUGS:
		var record: Dictionary = components.get(slug, {})
		component_reports.append(_probe_component(slug, record))

	var root_report := _probe_root(instance_rows, components)
	var report := {
		"schema": "shellstorm2.openworld.godot_probe.v001",
		"asset_id": "ENV-OPENWORLD-LANDSCAPE-SKYLINE20",
		"version": "v006",
		"root_scene": ROOT_SCENE,
		"palette": PALETTE_PATH,
		"components": component_reports,
		"root": root_report,
		"pass": _pass,
		"fail": _fail,
		"status": "passed" if _fail == 0 else "failed",
		"messages": _messages,
	}
	var output_path := ProjectSettings.globalize_path(SOURCE_ROOT + "/qa/probe_skyline20_v006.json")
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		_fail += 1
		print("SKYLINE20_GODOT_PROBE_FAILED 无法写出 %s" % output_path)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	var qa := _read_json(SOURCE_ROOT + "/qa/qa_report.json")
	qa["godot_runtime_probe"] = {"status": report["status"], "pass": _pass, "fail": _fail, "report": SOURCE_ROOT + "/qa/probe_skyline20_v006.json"}
	qa["status"] = "GODOT_MACHINE_CHECKS_PASSED_VISUAL_REVIEW_PENDING" if _fail == 0 else "GODOT_MACHINE_CHECKS_FAILED"
	var qa_file := FileAccess.open(SOURCE_ROOT + "/qa/qa_report.json", FileAccess.WRITE)
	qa_file.store_string(JSON.stringify(qa, "  "))
	qa_file.close()
	_finish()

func _probe_component(slug: String, record: Dictionary) -> Dictionary:
	_expect(FileAccess.get_sha256("res://" + str(record.get("glb", ""))) == str(record.get("glb_sha256", "")), "%s 实際GLB哈希与catalog一致" % slug)
	var package := _read_json(RUNTIME_ROOT + "/" + slug + "/asset_manifest.json")
	_expect(str(package.get("source_sha256", "")) == str(_catalog.get("source_sha256", "")), "%s 包清单源哈希一致" % slug)
	_expect(str(package.get("component_id", "")) == str(record.get("component_id", "")), "%s 包清单component_id一致" % slug)
	var prefab_path := str(record.get("prefab", ""))
	var glb_path := str(record.get("glb", ""))
	var packed_path := prefab_path if prefab_path.begins_with("res://") else "res://" + prefab_path
	var packed := load(packed_path) as PackedScene
	var instance := packed.instantiate() as Node3D if packed != null else null
	var report := {"slug": slug, "prefab": prefab_path, "glb": glb_path, "loaded": instance != null, "mesh_count": 0, "triangles": 0, "aabb": {}, "materials": [], "root_transform_identity": false}
	_expect(packed != null, "%s PackedScene 可加载" % slug)
	_expect(instance != null, "%s PackedScene 可实例化" % slug)
	if instance == null:
		return report
	var mesh_nodes := instance.find_children("*", "MeshInstance3D", true, false)
	report["mesh_count"] = mesh_nodes.size()
	_expect(mesh_nodes.size() >= 1, "%s 至少有一个 MeshInstance3D" % slug)
	var triangles := 0
	var union: AABB
	var have_aabb := false
	var material_paths: Array = []
	for node in mesh_nodes:
		var mesh_instance := node as MeshInstance3D
		triangles += _mesh_triangles(mesh_instance.mesh)
		var local_transform := _relative_transform(mesh_instance, instance)
		_expect(_transform_identity(local_transform), "%s Mesh 至 Prefab 根的完整变换恒等" % slug)
		var box := local_transform * mesh_instance.get_aabb()
		if not have_aabb:
			union = box
			have_aabb = true
		else:
			union = union.merge(box)
		for surface in range(mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 0):
			var material := mesh_instance.get_active_material(surface)
			var material_report := _material_report(material)
			material_paths.append(material_report)
			var is_glow := str(mesh_instance.name).contains("自发光")
			_expect(bool(material_report.get("emission", false)) == is_glow, "%s 主体与自发光材质分离" % slug)
		_expect(mesh_instance.mesh.get_surface_count() <= (1 if str(mesh_instance.name).contains("自发光") else 3), "%s 单网格表面预算" % slug)
	report["triangles"] = triangles
	report["materials"] = material_paths
	if have_aabb:
		report["aabb"] = _aabb_dict(union)
	var expected_triangles := int(record.get("triangles_after", -1))
	_expect(triangles == expected_triangles, "%s Godot 三角数 %d == catalog %d" % [slug, triangles, expected_triangles])
	var expected_bbox := record.get("bbox_m", []) as Array
	if have_aabb and expected_bbox.size() == 3:
		# Blender is Z-up (x,y,z); Godot import is Y-up (x,z,-y).
		_expect(_close(union.size.x, float(expected_bbox[0])) and _close(union.size.y, float(expected_bbox[2])) and _close(union.size.z, float(expected_bbox[1])), "%s Godot 局部 AABB 尺寸与 catalog 坐标映射一致" % slug)
	if have_aabb:
		_expect(absf(union.position.y) <= EPSILON and absf(union.get_center().x) <= EPSILON and absf(union.get_center().z) <= EPSILON, "%s 联合几何原点为底部中心" % slug)
	_expect(mesh_nodes.size() == 2, "%s 恰有主体和自发光两网格" % slug)
	var t := instance.transform
	report["root_transform_identity"] = _transform_identity(t)
	_expect(_transform_identity(t), "%s Prefab root transform 为 identity" % slug)
	instance.free()
	return report

func _probe_root(instance_rows: Dictionary, components: Dictionary) -> Dictionary:
	var packed := load(ROOT_SCENE) as PackedScene
	var root := packed.instantiate() as Node3D if packed != null else null
	var report := {"loaded": root != null, "child_count": 0, "mesh_count": 0, "triangles": 0, "aabb": {}, "instances": [], "collision_nodes": 0}
	_expect(packed != null, "Skyline20 私有 root PackedScene 可加载")
	_expect(root != null, "Skyline20 私有 root 可实例化")
	if root == null:
		return report
	var children := root.get_children()
	report["child_count"] = children.size()
	_expect(children.size() == instance_rows.size(), "root 子实例数 %d == instances.json %d" % [children.size(), instance_rows.size()])
	var union: AABB
	var have_aabb := false
	var total_triangles := 0
	for child_value in children:
		var child := child_value as Node3D
		if child == null:
			continue
		var instance_id := str(child.name)
		var expected: Dictionary = instance_rows.get(instance_id, {})
		var pos := expected.get("position_m", []) as Array
		var expected_position := Vector3(float(pos[0]), float(pos[2]), -float(pos[1])) if pos.size() == 3 else Vector3.ZERO
		var rotation_deg := float(expected.get("rotation_y_deg", 0.0))
		var scale := expected.get("scale", [1.0, 1.0, 1.0]) as Array
		_expect(instance_rows.has(instance_id), "root 实例 %s 在 instances.json 中存在" % instance_id)
		_expect(child.position.distance_to(expected_position) <= EPSILON, "root 实例 %s 坐标映射正确" % instance_id)
		_expect(absf(child.rotation.y - deg_to_rad(rotation_deg)) <= EPSILON, "root 实例 %s 旋转映射正确" % instance_id)
		_expect(child.scale.distance_to(Vector3(float(scale[0]), float(scale[2]), float(scale[1]))) <= EPSILON, "root 实例 %s 缩放为单位/契约值" % instance_id)
		if str(expected.get("slug", "")) == "facade_hvac_unit":
			var outward := Vector3(signf(expected_position.x), 0, 0)
			_expect((child.basis * Vector3.BACK).dot(outward) > 0.999, "空调%s正面朝外" % instance_id)
		if str(expected.get("slug", "")) == "facade_billboard":
			_expect(absf(expected_position.x) >= 25 or absf(expected_position.z) >= 25, "广告%s位于立面" % instance_id)
		var offset: Array = expected.get("geometry_offset_m", [])
		var reference: Array = expected.get("reference_position_m", [])
		if offset.size() == 3 and reference.size() == 3:
			var reference_godot := Vector3(float(reference[0]), float(reference[2]), -float(reference[1]))
			var offset_godot := Vector3(float(offset[0]), float(offset[2]), -float(offset[1]))
			_expect((expected_position - child.basis * offset_godot).distance_to(reference_godot) <= EPSILON, "实例%s几何offset补偿保持参考摆位" % instance_id)
		var instance_mesh_nodes := child.find_children("*", "MeshInstance3D", true, false)
		var child_triangles := 0
		for node in instance_mesh_nodes:
			var mesh_instance := node as MeshInstance3D
			child_triangles += _mesh_triangles(mesh_instance.mesh)
			var box := _relative_transform(mesh_instance, root) * mesh_instance.get_aabb()
			if not have_aabb:
				union = box
				have_aabb = true
			else:
				union = union.merge(box)
		total_triangles += child_triangles
		report["instances"].append({"instance_id": instance_id, "slug": str(expected.get("slug", "")), "triangles": child_triangles, "position": _vector3_array(child.position), "rotation_y": child.rotation.y})
	report["mesh_count"] = root.find_children("*", "MeshInstance3D", true, false).size()
	report["triangles"] = total_triangles
	report["collision_nodes"] = root.find_children("*", "CollisionObject3D", true, false).size() + root.find_children("*", "CollisionShape3D", true, false).size()
	var expected_triangles := 0
	for row in instance_rows.values():
		expected_triangles += int((components[str(row["slug"])] as Dictionary)["triangles_after"])
	_expect(total_triangles == expected_triangles, "root 实际三角数与同一实例清单累计值一致")
	_expect(total_triangles <= 10000, "root 实例三角成本不超过10000")
	var floor_dims: Array = (components["floor_facade_module"] as Dictionary)["bbox_m"]
	_expect(_close(float(floor_dims[0]), 50.0) and _close(float(floor_dims[1]), 50.0), "主体结构 footprint 实测50x50m")
	var floor_count := 0
	for row in instance_rows.values():
		if str(row["slug"]) == "floor_facade_module":
			floor_count += 1
	_expect(floor_count == 20, "20层，无新增独立底层")
	for index in range(1, 20):
		var previous: Array = (instance_rows["floor_%02d" % index] as Dictionary)["reference_position_m"]
		var current: Array = (instance_rows["floor_%02d" % (index + 1)] as Dictionary)["reference_position_m"]
		_expect(_close(float(current[2]) - float(previous[2]), 3.8), "楼层%d层距3.8m" % (index + 1))
	_expect(report["collision_nodes"] == 0, "root 无碰撞节点")
	if have_aabb:
		report["aabb"] = _aabb_dict(union)
		var envelope: Array = (_catalog["measured_assembly_bounds"] as Dictionary)["bounds_local"]
		var expected_min := Vector3(float(envelope[0]), float(envelope[2]), -float(envelope[4]))
		var expected_max := Vector3(float(envelope[3]), float(envelope[5]), -float(envelope[1]))
		_expect(union.position.distance_to(expected_min) <= 0.001, "完整装配包络最小值与Blender实测轴映射一致")
		_expect(union.end.distance_to(expected_max) <= 0.001, "完整装配包络最大值与Blender实测轴映射一致")
	root.free()
	return report

func _mesh_triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices is PackedInt32Array or indices is PackedInt64Array:
			total += int(indices.size() / 3)
		else:
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			total += int(vertices.size() / 3) if vertices is PackedVector3Array else 0
	return total

func _material_report(material: Material) -> Dictionary:
	var result := {"class": material.get_class() if material != null else "", "resource_path": material.resource_path if material != null else "", "palette": false, "emission": false}
	_expect(material is BaseMaterial3D, "材质必须为可验收BaseMaterial3D")
	if material is BaseMaterial3D:
		var base := material as BaseMaterial3D
		result["texture_filter"] = base.texture_filter
		result["texture_repeat"] = base.texture_repeat
		result["emission_energy"] = base.emission_energy_multiplier
		_expect(base.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "色盘最近邻采样")
		_expect(not base.texture_repeat, "色盘不重复")
		_expect(base.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "无意外透明")
		if base.emission_enabled:
			_expect(base.emission_energy_multiplier > 0 and base.emission_energy_multiplier <= 1.6, "柔和自发光强度")
			_expect(base.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY, "发光与色盘相乘不泛白")
		var texture := base.albedo_texture
		result["albedo_texture"] = texture.resource_path if texture != null else ""
		result["palette"] = texture != null and (texture.resource_path == PALETTE_PATH or texture.resource_path.ends_with("/设施低亮多巴胺色盘_10x10_512.png"))
		result["emission"] = base.emission_enabled
		_expect(bool(result["palette"]), "材质绑定公共 palette")
	return result

func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != ancestor and current != null:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result

func _capture() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var packed := load(ROOT_SCENE) as PackedScene
	stage.add_child(packed.instantiate())
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.07, 0.09, 0.12)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.5
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.light_energy = 1.0
	light.shadow_enabled = true
	var fill := DirectionalLight3D.new()
	stage.add_child(fill)
	fill.rotation_degrees = Vector3(-35, 140, 0)
	fill.light_energy = 0.8
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 104.0
	camera.far = 500.0
	camera.position = Vector3(105, 105, 125)
	camera.look_at(Vector3(0, 40, 0))
	camera.current = true
	for index in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var output := ProjectSettings.globalize_path(SOURCE_ROOT + "/qa/godot_runtime_front.png")
	var code := image.save_png(output)
	print("SKYLINE20_CAPTURE_RESULT %d %s" % [code, output])
	stage.queue_free()
	await process_frame
	quit(0 if code == OK else 1)

func _aabb_dict(box: AABB) -> Dictionary:
	return {"position": _vector3_array(box.position), "size": _vector3_array(box.size), "end": _vector3_array(box.end)}

func _vector3_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _transform_identity(value: Transform3D) -> bool:
	return value.origin.length() <= EPSILON and value.basis.is_equal_approx(Basis.IDENTITY)

func _close(left: float, right: float) -> bool:
	return absf(left - right) <= 0.01

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}

func _expect(condition: bool, message: String) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		_messages.append(message)

func _finish() -> void:
	if _fail == 0:
		print("SKYLINE20_GODOT_PROBE_OK pass=%d fail=0" % _pass)
		quit(0)
	else:
		print("SKYLINE20_GODOT_PROBE_FAILED pass=%d fail=%d" % [_pass, _fail])
		for message in _messages:
			print("  - %s" % message)
		quit(1)
