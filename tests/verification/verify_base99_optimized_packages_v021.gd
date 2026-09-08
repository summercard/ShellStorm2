extends Node

const LEDGER_PATH := "res://assets/art/environments/base_facility_3d/source/env_base99_optimized_packages_v021_import_manifest.json"
const LAYOUT_PATH := "res://assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d_v001.tscn"
const PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"


func _ready() -> void:
	var failures: Array[String] = []
	var ledger := _read_ledger(failures)
	if ledger.is_empty():
		_finish(failures)
		return
	_expect(str(ledger.get("version", "")) == "v021", "台账版本不是v021", failures)
	_expect(str(ledger.get("source_blend", "")).ends_with("base_facility_runtime_layout_hq_v021.blend"), "台账没有指向v021源Blend", failures)
	var packages: Array = ledger.get("packages", [])
	_expect(packages.size() == 30, "台账应登记30个资产包，实际为%d" % packages.size(), failures)
	var seen_runtime: Dictionary = {}
	var total_before := 0
	var total_after := 0
	var total_removed := 0
	for value in packages:
		var package: Dictionary = value
		var glb_path := "res://" + str(package.get("visual_glb", ""))
		_expect(ResourceLoader.exists(glb_path), "缺少GLB: %s" % glb_path, failures)
		if ResourceLoader.exists(glb_path):
			_validate_visual(glb_path, str(package.get("slug", "")), failures)
		var runtime_path := "res://" + str(package.get("runtime_scene", ""))
		if not seen_runtime.has(runtime_path):
			seen_runtime[runtime_path] = true
			_expect(ResourceLoader.exists(runtime_path), "缺少包装或总装配场景: %s" % runtime_path, failures)
		if int(package.get("triangles_after", 0)) > int(package.get("triangles_before", 0)):
			failures.append("优化后三角面增加: %s" % package.get("slug", ""))
		total_before += int(package.get("triangles_before", 0))
		total_after += int(package.get("triangles_after", 0))
		total_removed += int(package.get("downward_triangles_removed", 0))
	_expect(total_removed > 0 and total_after < total_before, "朝下删除或总三角面优化统计无效", failures)
	_validate_layout_refs(failures)
	if failures.is_empty():
		print("BASE99_OPTIMIZED_PACKAGES_V021_OK: 30 packages, %d -> %d triangles, %d downward triangles removed" % [total_before, total_after, total_removed])
	_finish(failures)


func _read_ledger(failures: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(LEDGER_PATH):
		failures.append("缺少v021导入台账")
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(LEDGER_PATH)) != OK:
		failures.append("v021导入台账JSON无效")
		return {}
	return json.data as Dictionary


func _validate_visual(path: String, slug: String, failures: Array[String]) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		failures.append("无法加载GLB: %s" % path)
		return
	var node := packed.instantiate()
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		failures.append("GLB没有网格: %s" % slug)
	for mesh_value in meshes:
		var mesh_instance := mesh_value as MeshInstance3D
		if mesh_instance.mesh == null:
			failures.append("GLB包含空网格: %s" % slug)
			continue
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface_index) as BaseMaterial3D
			if material == null:
				failures.append("GLB缺少标准材质: %s" % slug)
				continue
			if material.albedo_texture == null or material.albedo_texture.resource_path != PALETTE_PATH:
				failures.append("GLB没有共享色盘: %s" % slug)
			if material.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
				failures.append("GLB色盘未使用最近邻采样: %s" % slug)
	node.queue_free()


func _validate_layout_refs(failures: Array[String]) -> void:
	var text := FileAccess.get_file_as_string(LAYOUT_PATH)
	for required in [
		"env_base99_remaining_facilities_root_top3d_v002.tscn",
		"env_base99_wall_contents_root_top3d_v002.tscn",
		"env_base99_floor_visuals_root_top3d_v004.tscn",
	]:
		_expect(text.contains(required), "基地总装配没有使用新版引用: %s" % required, failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("BASE99_OPTIMIZED_PACKAGES_V021_FAIL: " + failure)
	get_tree().quit(1)
