extends Node

const LAYOUT_PATH: String = "res://assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d.tscn"

func _ready() -> void:
	var packed: PackedScene = load(LAYOUT_PATH) as PackedScene
	var root: Node3D = packed.instantiate() as Node3D
	add_child(root)
	await get_tree().process_frame
	var node: Node3D = root.find_child("42_双屏电脑完整工位_资产包", true, false) as Node3D
	if node == null:
		push_error("WORKSTATION_SURFACE_PROBE_FAIL")
		get_tree().quit(1)
		return
	for value in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = value as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		print("MESH name=%s surfaces=%d" % [mesh_node.name, mesh_node.mesh.get_surface_count()])
		for s in mesh_node.mesh.get_surface_count():
			var arrays: Array = mesh_node.mesh.surface_get_arrays(s)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var b: AABB = AABB()
			var found: bool = false
			for v in verts:
				var p: Vector3 = mesh_node.global_transform * v
				b = AABB(p, Vector3.ZERO) if not found else b.expand(p)
				found = true
			if found:
				print("SURFACE mesh=%s index=%d center=%s pos=%s size=%s verts=%d" % [mesh_node.name, s, _v(b.get_center()), _v(b.position), _v(b.size), verts.size()])
	print("WORKSTATION_SURFACE_PROBE_OK")
	get_tree().quit(0)

func _v(v: Vector3) -> String:
	return "(%.5f, %.5f, %.5f)" % [v.x, v.y, v.z]
