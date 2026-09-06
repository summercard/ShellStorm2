extends Node

const SHARED_PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
const MINIMUM_GLB_COUNT := 44
const COMPONENT_ROOTS := [
	"res://assets/art/environments/base_facility_3d/components",
	"res://assets/art/props/base_world_3d/components",
]


func _ready() -> void:
	var failures: Array[String] = []
	var glbs: Array[String] = []
	for root in COMPONENT_ROOTS:
		_collect_glbs(root, glbs)
	_expect(glbs.size() >= MINIMUM_GLB_COUNT, "场景/设施GLB数量异常: %d" % glbs.size(), failures)
	var material_count := 0
	for path in glbs:
		var packed := load(path) as PackedScene
		_expect(packed != null, "GLB无法加载: %s" % path, failures)
		if packed == null:
			continue
		var instance := packed.instantiate()
		material_count += _validate_materials(instance, path, failures)
		instance.free()
	for root in COMPONENT_ROOTS:
		_validate_no_duplicate_png(root, failures)
	_expect(material_count > 0, "没有找到可验证的场景/设施材质", failures)
	if failures.is_empty():
		print("SCENE_FACILITY_SHARED_PALETTE_OK: glbs=%d materials=%d shared_texture=1" % [glbs.size(), material_count])
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _validate_materials(root: Node, asset_path: String, failures: Array[String]) -> int:
	var count := 0
	if root is MeshInstance3D:
		var mesh := (root as MeshInstance3D).mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				var material := mesh.surface_get_material(surface_index) as BaseMaterial3D
				if material == null:
					continue
				count += 1
				_expect(material.albedo_texture != null, "材质缺少公共色盘: %s" % asset_path, failures)
				if material.albedo_texture != null:
					_expect(material.albedo_texture.resource_path == SHARED_PALETTE_PATH, "材质仍指向模型私有贴图: %s -> %s" % [asset_path, material.albedo_texture.resource_path], failures)
				_expect(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "色盘不是最近邻采样: %s" % asset_path, failures)
	for child in root.get_children():
		count += _validate_materials(child, asset_path, failures)
	return count


func _collect_glbs(path: String, result: Array[String]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child := path.path_join(name)
			if directory.current_is_dir():
				_collect_glbs(child, result)
			elif name.ends_with(".glb"):
				result.append(child)
		name = directory.get_next()
	directory.list_dir_end()


func _validate_no_duplicate_png(path: String, failures: Array[String]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child := path.path_join(name)
			if directory.current_is_dir():
				_validate_no_duplicate_png(child, failures)
			elif name.ends_with(".png") and ("色盘" in name or "palette" in name.to_lower()):
				failures.append("组件目录仍有重复色盘: %s" % child)
		name = directory.get_next()
	directory.list_dir_end()


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
