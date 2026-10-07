extends SceneTree
## Run with isolated APPDATA, real renderer (not --headless), --script this file.
const BASE: String = "res://assets/art/environments/open_world/"
const PALETTE: String = "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
const BOUNDS_TOLERANCE: float = 0.01
const ROOT_SCALE_LIMIT: float = 100000.0
const DEFAULT_TOWERS: Array[String] = ["tower_02", "tower_03"]
var checks: int = 0
var failures: Array[String] = []
var stage: Node3D
var selected_tower: String = ""

func _initialize() -> void:
	selected_tower = _parse_tower_argument()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		check(false, "missing JSON: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		check(false, "invalid JSON object: " + path)
		return {}
	return parsed as Dictionary

func _parse_tower_argument() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size() - 1):
		if args[index] == "--tower":
			return args[index + 1]
	return ""

func _tower_list() -> Array[String]:
	var towers: Array[String] = []
	if selected_tower.is_empty():
		for tower_slug: String in DEFAULT_TOWERS:
			towers.append(tower_slug)
		return towers
	check(DEFAULT_TOWERS.has(selected_tower), "unsupported tower selector: " + selected_tower)
	if DEFAULT_TOWERS.has(selected_tower):
		towers.append(selected_tower)
	return towers

func mesh_bounds(node: Node3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	collect_meshes(node, meshes)
	var result: AABB = AABB()
	var first: bool = true
	for mesh: MeshInstance3D in meshes:
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		result = bounds if first else result.merge(bounds)
		first = false
	return result

func collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		collect_meshes(child, result)

func mesh_triangle_count(mesh: Mesh) -> int:
	var triangles: int = 0
	for surface_index: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var index_data: Variant = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX else null
		if index_data is PackedInt32Array:
			triangles += (index_data as PackedInt32Array).size() / 3
		elif index_data is PackedInt64Array:
			triangles += (index_data as PackedInt64Array).size() / 3
		elif index_data is PackedByteArray:
			triangles += (index_data as PackedByteArray).size() / 3
		else:
			var vertex_data: Variant = arrays[Mesh.ARRAY_VERTEX] if arrays.size() > Mesh.ARRAY_VERTEX else null
			if vertex_data is PackedVector3Array:
				triangles += (vertex_data as PackedVector3Array).size() / 3
			else:
				check(false, "unsupported mesh index/vertex buffer type")
	return triangles

func component_triangle_count(node: Node3D) -> int:
	var meshes: Array[MeshInstance3D] = []
	collect_meshes(node, meshes)
	var triangles: int = 0
	for mesh_instance: MeshInstance3D in meshes:
		if mesh_instance.mesh != null:
			triangles += mesh_triangle_count(mesh_instance.mesh)
	return triangles

func vector3_from_array(value: Variant) -> Vector3:
	var values: Array = value as Array
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func blender_bounds_to_godot(record: Dictionary) -> AABB:
	var bounds_value: Variant = record.get("bounds_blender", [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]])
	var bounds: Array = bounds_value as Array
	var low: Vector3 = vector3_from_array(bounds[0])
	var high: Vector3 = vector3_from_array(bounds[1])
	return AABB(Vector3(low.x, low.z, -high.y), Vector3(high.x - low.x, high.z - low.z, high.y - low.y))

func verify_materials(node: Node3D, component_slug: String) -> void:
	var meshes: Array[MeshInstance3D] = []
	collect_meshes(node, meshes)
	check(not meshes.is_empty(), "empty imported asset: " + component_slug)
	for mesh: MeshInstance3D in meshes:
		check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "shadow disabled: " + component_slug)
		if mesh.mesh == null:
			check(false, "mesh resource missing: " + component_slug)
			continue
		for surface_index: int in range(mesh.mesh.get_surface_count()):
			var material: Material = mesh.get_active_material(surface_index)
			check(material is BaseMaterial3D, "invalid PBR material: " + component_slug)
			if material is BaseMaterial3D:
				var base_material: BaseMaterial3D = material as BaseMaterial3D
				check(base_material.albedo_texture != null and base_material.albedo_texture.resource_path == PALETTE, "missing shared palette: " + component_slug)
				check(base_material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "palette filter not nearest: " + component_slug)

func record_bounds_evidence(record: Dictionary, actual: AABB, reference_record: Dictionary) -> Dictionary:
	var expected: AABB = blender_bounds_to_godot(record)
	var position_delta: Vector3 = actual.position - expected.position
	var size_delta: Vector3 = actual.size - expected.size
	var bounds_ok: bool = position_delta.length() < BOUNDS_TOLERANCE and size_delta.length() < BOUNDS_TOLERANCE
	var slug: String = str(record.get("slug", ""))
	check(bounds_ok, "world bounds mismatch: %s actual=%s/%s expected=%s/%s delta=%s/%s" % [slug, actual.position, actual.size, expected.position, expected.size, position_delta, size_delta])
	var evidence: Dictionary = {
		"actual_position": [actual.position.x, actual.position.y, actual.position.z],
		"actual_size": [actual.size.x, actual.size.y, actual.size.z],
		"expected_position": [expected.position.x, expected.position.y, expected.position.z],
		"expected_size": [expected.size.x, expected.size.y, expected.size.z],
		"position_delta": [position_delta.x, position_delta.y, position_delta.z],
		"size_delta": [size_delta.x, size_delta.y, size_delta.z],
		"tolerance_m": BOUNDS_TOLERANCE,
		"pass": bounds_ok,
	}
	if not reference_record.is_empty():
		var current_anchor: Vector3 = vector3_from_array(record.get("anchor_blender", [0.0, 0.0, 0.0]))
		var reference_anchor: Vector3 = vector3_from_array(reference_record.get("anchor_blender", [0.0, 0.0, 0.0]))
		var reference_delta: Vector3 = current_anchor - reference_anchor
		var reference_ok: bool = reference_delta.length() < BOUNDS_TOLERANCE
		check(reference_ok, "tower03 v001 envelope origin changed: %s delta=%s" % [slug, reference_delta])
		evidence["reference_v001_envelope_origin"] = [reference_anchor.x, reference_anchor.y, reference_anchor.z]
		evidence["reference_origin_delta"] = [reference_delta.x, reference_delta.y, reference_delta.z]
		evidence["reference_origin_tolerance_m"] = BOUNDS_TOLERANCE
		evidence["reference_origin_pass"] = reference_ok
	return evidence

func verify_component(record: Dictionary, reference_record: Dictionary, source_manifest: Dictionary) -> Dictionary:
	var slug: String = str(record.get("slug", ""))
	var prefab_path: String = str(record.get("runtime_prefab", record.get("prefab", "")))
	var glb_path: String = str(record.get("stable_glb", record.get("glb", "")))
	var scene: PackedScene = load("res://" + prefab_path) as PackedScene
	check(scene != null, "component cannot load: " + slug)
	if scene == null:
		return {"slug": slug, "pass": false}
	var component: Node3D = scene.instantiate() as Node3D
	check(component != null, "component root is not Node3D: " + slug)
	if component == null:
		return {"slug": slug, "pass": false}
	stage.add_child(component)
	component.position = vector3_from_array(record.get("position_godot", [0.0, 0.0, 0.0]))
	check(component.scale.length() < ROOT_SCALE_LIMIT, "component root scale exceeds limit: " + slug)
	check(component.scale == Vector3.ONE, "component root scale changed: " + slug)
	verify_materials(component, slug)
	var actual: AABB = mesh_bounds(component)
	var bounds_evidence: Dictionary = record_bounds_evidence(record, actual, reference_record)
	var actual_triangles: int = component_triangle_count(component)
	var expected_triangles: int = int(record.get("triangle_count", -1))
	check(actual_triangles == expected_triangles, "triangle count mismatch: %s actual=%d expected=%d" % [slug, actual_triangles, expected_triangles])
	var version: String = str(record.get("version", source_manifest.get("version", "")))
	check(version == str(source_manifest.get("version", "")), "component metadata version mismatch in manifest: " + slug)
	var metadata_version: String = str(component.get_meta("asset_version", ""))
	check(metadata_version == version, "component metadata asset_version mismatch: " + slug)
	var glb_sha256: String = FileAccess.get_sha256("res://" + glb_path)
	check(glb_sha256 == str(record.get("glb_sha256", "")), "GLB SHA-256 mismatch: " + slug)
	var tscn_sha256: String = FileAccess.get_sha256("res://" + prefab_path)
	var derived_path: String = str(record.get("derived", source_manifest.get("derived", "")))
	var derived_sha256: String = str(record.get("derived_sha256", source_manifest.get("derived_sha256", "")))
	var source_path: String = str(record.get("source_blend", source_manifest.get("source", "")))
	var source_sha256: String = str(source_manifest.get("source_sha256", ""))
	var evidence: Dictionary = {
		"slug": slug,
		"asset_id": str(record.get("asset_id", "")),
		"version": version,
		"metadata_version": metadata_version,
		"derived": derived_path,
		"derived_sha256": derived_sha256,
		"source": source_path,
		"source_sha256": source_sha256,
		"glb": glb_path,
		"glb_sha256": glb_sha256,
		"tscn": prefab_path,
		"tscn_sha256": tscn_sha256,
		"actual_triangle_count": actual_triangles,
		"expected_triangle_count": expected_triangles,
		"triangle_delta": actual_triangles - expected_triangles,
		"bounds": bounds_evidence,
	}
	component.free()
	return evidence

func verify_tower(slug: String, stage_node: Node3D, report: Dictionary) -> void:
	var runtime_manifest_path: String = BASE + "runtime/" + slug + "/asset_manifest.json"
	var runtime_manifest: Dictionary = load_json(runtime_manifest_path)
	var version: String = str(runtime_manifest.get("version", ""))
	check(not version.is_empty(), "runtime manifest version missing: " + slug)
	var export_manifest_path: String = BASE + "source/" + slug + "/export/" + version + "/export_manifest.json"
	var manifest: Dictionary = load_json(export_manifest_path)
	var records_value: Variant = manifest.get("records", [])
	var records: Array = records_value as Array
	var reference_records: Dictionary = {}
	if slug == "tower_03":
		var reference_manifest: Dictionary = load_json(BASE + "source/tower_03/export/v001/export_manifest.json")
		var reference_values: Variant = reference_manifest.get("records", [])
		var reference_array: Array = reference_values as Array
		for reference_value: Variant in reference_array:
			var reference_record: Dictionary = reference_value as Dictionary
			reference_records[str(reference_record.get("slug", ""))] = reference_record
	var source_path: String = str(runtime_manifest.get("source", manifest.get("source", "")))
	var derived_path: String = str(runtime_manifest.get("derived", manifest.get("derived", "")))
	var source_sha256: String = str(runtime_manifest.get("source_sha256", manifest.get("source_sha256", "")))
	var derived_sha256: String = str(runtime_manifest.get("derived_sha256", manifest.get("derived_sha256", "")))
	check(not source_path.is_empty(), "source path missing: " + slug)
	check(FileAccess.get_sha256("res://" + source_path) == source_sha256, "source SHA-256 mismatch: " + slug)
	if not derived_path.is_empty():
		check(not derived_sha256.is_empty(), "derived SHA-256 missing: " + slug)
		check(FileAccess.get_sha256("res://" + derived_path) == derived_sha256, "derived SHA-256 mismatch: " + slug)
	var tower_scene_path: String = str(runtime_manifest.get("prefab", "assets/art/environments/open_world/runtime/" + slug + "/env_" + slug + "_root_top3d.tscn"))
	var tower_scene: PackedScene = load("res://" + tower_scene_path) as PackedScene
	check(tower_scene != null, "tower cannot load: " + slug)
	if tower_scene == null:
		return
	var tower: Node3D = tower_scene.instantiate() as Node3D
	check(tower != null, "tower root is not Node3D: " + slug)
	if tower == null:
		return
	stage_node.add_child(tower)
	check(tower.scale.length() < ROOT_SCALE_LIMIT, "tower root scale exceeds limit: " + slug)
	check(tower.scale == Vector3.ONE, "root scale changed: " + slug)
	check(str(tower.get_meta("asset_version", "")) == version, "tower metadata version mismatch: " + slug)
	var expected_component_count: int = int(runtime_manifest.get("component_count", records.size()))
	check(int(tower.get_meta("component_count", -1)) == expected_component_count, "tower metadata component_count mismatch: " + slug)
	if slug == "tower_03":
		check(version == str(manifest.get("version", "")), "tower03 runtime/export version mismatch")
		check(expected_component_count == 217, "tower03 manifest component_count is not 217")
	check(tower.find_children("*", "CollisionObject3D", true, false).is_empty(), "unexpected collision/logic: " + slug)
	var component_evidence: Array[Dictionary] = []
	for record_value: Variant in records:
		var record: Dictionary = record_value as Dictionary
		var component_slug: String = str(record.get("slug", ""))
		var reference_record: Dictionary = reference_records.get(component_slug, {}) as Dictionary
		component_evidence.append(verify_component(record, reference_record, runtime_manifest))
	if slug == "tower_02":
		check(tower.get_node("cranes").get_child_count() == 3, "three independent cranes missing")
		for crane_index: int in range(3):
			var crane_path: String = BASE + "runtime/tower_02/cranes/crane_%02d/env_tower_02_crane_%02d_root_top3d.tscn" % [crane_index, crane_index]
			var crane_scene: PackedScene = load(crane_path) as PackedScene
			check(crane_scene != null, "independent crane cannot load")
			if crane_scene != null:
				var crane: Node3D = crane_scene.instantiate() as Node3D
				stage_node.add_child(crane)
				var parts: Array[MeshInstance3D] = []
				collect_meshes(crane, parts)
				check(parts.size() == 7, "crane parts mismatch")
				crane.free()
	var root_triangles: int = component_triangle_count(tower)
	var expected_total: int = 0
	for record_value: Variant in records:
		var total_record: Dictionary = record_value as Dictionary
		expected_total += int(total_record.get("triangle_count", 0))
	check(root_triangles == expected_total, "tower root triangle count mismatch: %s actual=%d expected=%d" % [slug, root_triangles, expected_total])
	var bounds: AABB = mesh_bounds(tower)
	var report_tower: Dictionary = {
			"runtime_triangles": root_triangles,
			"expected_triangles": expected_total,
			"slug": slug,
			"version": version,
			"source": source_path,
			"source_sha256": source_sha256,
			"derived": derived_path,
			"derived_sha256": derived_sha256,
			"tscn": tower_scene_path,
			"tscn_sha256": FileAccess.get_sha256("res://" + tower_scene_path),
			"metadata_version": str(tower.get_meta("asset_version", "")),
			"metadata_component_count": int(tower.get_meta("component_count", -1)),
			"component_count": records.size(),
			"bounds_position": [bounds.position.x, bounds.position.y, bounds.position.z],
			"bounds_size": [bounds.size.x, bounds.size.y, bounds.size.z],
			"components": component_evidence,
		}
	var glb_hashes: Array[String] = []
	for evidence: Dictionary in component_evidence:
		glb_hashes.append(str(evidence.get("glb_sha256", "")))
	report_tower["glb_sha256"] = glb_hashes
	var towers_value: Variant = report.get("towers", [])
	var towers: Array = towers_value as Array
	towers.append(report_tower)
	report["towers"] = towers
	for view: String in ["whole", "roof"]:
		var center: Vector3 = bounds.get_center()
		var camera: Camera3D = stage_node.get_node("AcceptanceCamera") as Camera3D
		if view == "roof":
			center = Vector3(0.0, 85.0 if slug == "tower_02" else 43.0, 0.0)
			camera.size = 94.0 if slug == "tower_02" else 83.0
		else:
			camera.size = 180.0 if slug == "tower_02" else 108.0
		camera.position = center + Vector3(140.0, 135.0, 165.0)
		camera.look_at(center, Vector3.UP)
		for _frame: int in range(12):
			await process_frame
		root.msaa_3d = Viewport.MSAA_4X
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		check(not image.is_empty(), "real renderer image empty")
		var output: String = _image_output_path(slug, version, view)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		check(image.save_png(output) == OK, "screenshot save failed: " + output)
	tower.free()

func _image_output_path(slug: String, version: String, view: String) -> String:
	if not selected_tower.is_empty():
		return "res://outputs/" + slug.replace("_", "") + "_" + version + "/" + view + ".png"
	return BASE + "runtime/" + slug + "/qa/" + view + ".png"

func _report_output_path(slug: String, version: String) -> String:
	if not selected_tower.is_empty():
		return "res://outputs/" + slug.replace("_", "") + "_" + version + "/godot_visual_acceptance.json"
	return BASE + "runtime/import_acceptance.json"

func run() -> void:
	root.size = Vector2i(1280, 960)
	var palette_import: ConfigFile = ConfigFile.new()
	check(palette_import.load(PALETTE + ".import") == OK, "palette import config missing")
	check(int(palette_import.get_value("params", "compress/mode", -1)) == 0, "palette compression must be lossless")
	check(not bool(palette_import.get_value("params", "mipmaps/generate", true)), "palette mipmaps must be disabled")
	stage = Node3D.new()
	root.add_child(stage)
	var env_node: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("519fe5")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c5ddff")
	env.ambient_light_energy = 0.65
	env_node.environment = env
	stage.add_child(env_node)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	stage.add_child(sun)
	var camera: Camera3D = Camera3D.new()
	camera.name = "AcceptanceCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 1000.0
	stage.add_child(camera)
	camera.current = true
	var report: Dictionary = {"towers": [], "mode": "single_tower" if not selected_tower.is_empty() else "full_coverage"}
	for slug: String in _tower_list():
		await verify_tower(slug, stage, report)
	report["checks"] = checks
	report["failures"] = failures
	report["renderer"] = RenderingServer.get_video_adapter_name()
	var output_version: String = ""
	var report_towers_value: Variant = report.get("towers", [])
	var report_towers: Array = report_towers_value as Array
	if not report_towers.is_empty():
		var first_tower: Dictionary = report_towers[0] as Dictionary
		output_version = str(first_tower.get("version", output_version))
	var output_slug: String = selected_tower if not selected_tower.is_empty() else "all"
	var output_path: String = _report_output_path(output_slug, output_version)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	else:
		check(false, "acceptance report cannot open: " + output_path)
	print("OPENWORLD_TOWERS_VERIFY_OK" if failures.is_empty() else "OPENWORLD_TOWERS_VERIFY_FAILED", " checks=", checks, " failures=", failures.size())
	stage.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
