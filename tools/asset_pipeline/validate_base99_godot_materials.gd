extends SceneTree
## Load every GLB referenced by Base99 runtime PackedScenes and verify that the
## imported Godot scene contains at most one material resource per canonical role.

const RUNTIME_ROOT := "res://assets/art/environments/base_facility_3d/runtime"
const CANONICAL := {
	&"01_精工金属_紫色骨架": true,
	&"02_细腻哑光_青绿大面": true,
	&"03_清漆反光_紫粉点缀": true,
	&"04_柔和自发光_UI灯光": true,
}


func _initialize() -> void:
	var paths := {}
	_collect_scene_references(RUNTIME_ROOT, paths)
	var errors: Array[String] = []
	for path in paths.keys():
		var packed := load(path) as PackedScene
		if packed == null:
			errors.append("LOAD_FAILED %s" % path)
			continue
		var root := packed.instantiate()
		var material_resources := {}
		_collect_materials(root, material_resources)
		var roles := {}
		for material_id in material_resources.keys():
			var role: StringName = material_resources[material_id]
			roles[role] = true
			if not CANONICAL.has(role):
				errors.append("NON_CANONICAL %s %s" % [path, role])
		if material_resources.size() > 4:
			errors.append("MATERIAL_BUDGET %s resources=%d" % [path, material_resources.size()])
		if roles.size() != material_resources.size():
			errors.append("DUPLICATE_ROLE_RESOURCES %s resources=%d roles=%d" % [path, material_resources.size(), roles.size()])
		root.free()
	if errors.is_empty():
		print("GODOT_BASE99_MATERIALS_OK scenes=%d" % paths.size())
		quit(0)
	else:
		for error in errors:
			push_error(error)
		print("GODOT_BASE99_MATERIALS_FAILED errors=%d" % errors.size())
		quit(1)


func _collect_scene_references(directory_path: String, paths: Dictionary) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	for filename in directory.get_files():
		if not filename.ends_with(".tscn"):
			continue
		var path := directory_path.path_join(filename)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		for part in file.get_as_text().split('path="res://'):
			var end := part.find('"')
			if end > 0:
				var resource_path := part.substr(0, end)
				if resource_path.ends_with(".glb"):
					paths["res://%s" % resource_path] = true
	for child in directory.get_directories():
		_collect_scene_references(directory_path.path_join(child), paths)


func _collect_materials(node: Node, materials: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				var material := mesh.surface_get_material(surface_index) as BaseMaterial3D
				if material != null:
					materials[material.get_instance_id()] = material.resource_name
	for child in node.get_children():
		_collect_materials(child, materials)
