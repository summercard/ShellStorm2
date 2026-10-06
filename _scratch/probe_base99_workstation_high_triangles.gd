extends Node

const LAYOUT_PATH: String = "res://assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d.tscn"

func _ready() -> void:
	var packed: PackedScene = load(LAYOUT_PATH) as PackedScene
	var root: Node3D = packed.instantiate() as Node3D
	add_child(root)
	await get_tree().process_frame
	var node: Node3D = root.find_child("42_双屏电脑完整工位_资产包", true, false) as Node3D
	for value in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = value as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var mesh: ArrayMesh = mi.mesh as ArrayMesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var rows: Array[Dictionary] = []
			var count: int = indices.size() if not indices.is_empty() else verts.size()
			for start in range(0, count, 3):
				var ia: int = indices[start] if not indices.is_empty() else start
				var ib: int = indices[start + 1] if not indices.is_empty() else start + 1
				var ic: int = indices[start + 2] if not indices.is_empty() else start + 2
				var a: Vector3 = mi.global_transform * verts[ia]
				var b: Vector3 = mi.global_transform * verts[ib]
				var c: Vector3 = mi.global_transform * verts[ic]
				var n: Vector3 = (b - a).cross(c - a).normalized()
				rows.append({"y": (a.y + b.y + c.y) / 3.0, "a": a, "b": b, "c": c, "n": n})
			rows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return float(left["y"]) > float(right["y"]))
			for i in mini(30, rows.size()):
				var r: Dictionary = rows[i]
				print("HIGH mesh=%s s=%d rank=%d y=%.5f center=%s normal=%s a=%s b=%s c=%s" % [mi.name, s, i, r["y"], _v((r["a"] + r["b"] + r["c"]) / 3.0), _v(r["n"]), _v(r["a"]), _v(r["b"]), _v(r["c"])])
	print("HIGH_TRIANGLE_PROBE_OK")
	get_tree().quit(0)

func _v(v: Vector3) -> String:
	return "(%.5f, %.5f, %.5f)" % [v.x, v.y, v.z]
