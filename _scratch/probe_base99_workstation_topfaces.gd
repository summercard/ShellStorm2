extends Node

const LAYOUT_PATH: String = "res://assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d.tscn"

func _ready() -> void:
	var packed: PackedScene = load(LAYOUT_PATH) as PackedScene
	var root: Node3D = packed.instantiate() as Node3D
	add_child(root)
	await get_tree().process_frame
	var node: Node3D = root.find_child("42_双屏电脑完整工位_资产包", true, false) as Node3D
	if node == null:
		push_error("TOPFACE_PROBE_FAIL")
		get_tree().quit(1)
		return
	for value in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = value as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var mesh: ArrayMesh = mesh_node.mesh as ArrayMesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			if arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays.size() > Mesh.ARRAY_NORMAL and arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count: int = indices.size() if not indices.is_empty() else verts.size()
			var printed: int = 0
			for start in range(0, count, 3):
				var ia: int = indices[start] if not indices.is_empty() else start
				var ib: int = indices[start + 1] if not indices.is_empty() else start + 1
				var ic: int = indices[start + 2] if not indices.is_empty() else start + 2
				var a: Vector3 = mesh_node.global_transform * verts[ia]
				var b: Vector3 = mesh_node.global_transform * verts[ib]
				var c: Vector3 = mesh_node.global_transform * verts[ic]
				var n: Vector3 = (b - a).cross(c - a).normalized()
				if n.y < 0.93:
					continue
				var min_y: float = minf(a.y, minf(b.y, c.y))
				if min_y < 6.5:
					continue
				var min_x: float = minf(a.x, minf(b.x, c.x))
				var max_x: float = maxf(a.x, maxf(b.x, c.x))
				var min_z: float = minf(a.z, minf(b.z, c.z))
				var max_z: float = maxf(a.z, maxf(b.z, c.z))
				print("TOPFACE mesh=%s surface=%d tri=%d y=%.5f center=%s x=[%.5f,%.5f] z=[%.5f,%.5f] normal=%s" % [mesh_node.name, s, start / 3, (a.y + b.y + c.y) / 3.0, _v((a + b + c) / 3.0), min_x, max_x, min_z, max_z, _v(n)])
				printed += 1
				if printed >= 120:
					break
	print("TOPFACE_PROBE_OK")
	get_tree().quit(0)

func _v(v: Vector3) -> String:
	return "(%.5f, %.5f, %.5f)" % [v.x, v.y, v.z]
