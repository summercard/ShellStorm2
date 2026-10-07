extends Node

const ROOT_SCENE_PATH: String = "res://assets/art/environments/open_world/runtime/tower_02/env_tower_02_root_top3d.tscn"
const MANIFEST_PATH: String = "res://assets/art/environments/open_world/runtime/tower_02/asset_manifest.json"

func _ready() -> void:
	var root_scene: PackedScene = load(ROOT_SCENE_PATH) as PackedScene
	assert(root_scene != null, "ROOT_SCENE_LOAD_FAILED")
	var root: Node = root_scene.instantiate()
	assert(root != null, "ROOT_SCENE_INSTANTIATE_FAILED")
	add_child(root)
	await get_tree().process_frame
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	var mesh_count: int = meshes.size()
	var triangles: int = 0
	var surfaces: int = 0
	for node: Node in meshes:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		assert(mesh_instance.mesh != null, "NULL_MESH:" + str(mesh_instance.get_path()))
		var mesh: Mesh = mesh_instance.mesh
		for surface_index: int in mesh.get_surface_count():
			surfaces += 1
			var arrays: Array = mesh.surface_get_arrays(surface_index)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
			if indices != null and indices.size() > 0:
				triangles += int(indices.size() / 3)
			else:
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				triangles += int(vertices.size() / 3)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH)) as Dictionary
	assert(manifest.get("version", "") == "v004", "MANIFEST_VERSION_MISMATCH")
	assert(manifest.get("runtime_integrated", false) == true, "MANIFEST_NOT_INTEGRATED")
	assert(mesh_count > 0, "NO_RUNTIME_MESHES")
	assert(triangles < 100000, "RUNTIME_TRIANGLE_BUDGET_FAILED:" + str(triangles))
	print("TOWER02_V004_RUNTIME_OK")
	print("ROOT_SCENE=" + ROOT_SCENE_PATH)
	print("COMPONENT_INSTANCE_ROOT_CHILDREN=" + str(root.get_child_count()))
	print("MESH_INSTANCES=" + str(mesh_count))
	print("SURFACES=" + str(surfaces))
	print("RUNTIME_TRIANGLES=" + str(triangles))
	print("MANIFEST_VERSION=" + str(manifest.get("version", "")))
	get_tree().quit(0)
