extends RefCounted
## Resolves authored scene roots for mesh-based visual effects.


static func collect(host: Node, roots: Array[NodePath], exclusions: Array[NodePath]) -> Dictionary[int, MeshInstance3D]:
	var meshes: Dictionary[int, MeshInstance3D] = {}
	if roots.is_empty():
		_collect_meshes(host.get_parent(), meshes)
	else:
		for path in roots:
			_collect_meshes(host.get_node_or_null(path), meshes)

	var excluded: Dictionary[int, MeshInstance3D] = {}
	for path in exclusions:
		_collect_meshes(host.get_node_or_null(path), excluded)
	for id in excluded:
		meshes.erase(id)
	return meshes


static func _collect_meshes(node: Node, meshes: Dictionary[int, MeshInstance3D]) -> void:
	if node == null:
		return
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		meshes[mesh.get_instance_id()] = mesh
	for child in node.get_children():
		_collect_meshes(child, meshes)
