extends SceneTree
## Dynamic dual-tower probe; filename retained for existing command compatibility.
const BASE: String = "res://assets/art/environments/open_world/"
const OUTPUT: String = "res://outputs/towers_restore_full_20261007/runtime_probe.json"
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func read_json(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(value is Dictionary, "invalid JSON: " + path)
	return value as Dictionary if value is Dictionary else {}

func collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		collect_meshes(child, meshes)

func triangle_count(node: Node) -> int:
	var meshes: Array[MeshInstance3D] = []
	collect_meshes(node, meshes)
	var total: int = 0
	for instance: MeshInstance3D in meshes:
		if instance.mesh == null:
			check(false, "missing mesh: " + str(instance.name))
			continue
		for surface: int in range(instance.mesh.get_surface_count()):
			check(instance.mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES, "non-triangle mesh surface")
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
			if indices is PackedInt32Array and not indices.is_empty():
				total += int(indices.size() / 3)
			elif vertices is PackedVector3Array:
				total += int(vertices.size() / 3)
	return total

func _initialize() -> void:
	call_deferred("run_probe")

func run_probe() -> void:
	var report: Dictionary = {"towers": [], "failures": []}
	for slug: String in ["tower_02", "tower_03"]:
		var manifest: Dictionary = read_json(BASE + "runtime/" + slug + "/asset_manifest.json")
		var version: String = str(manifest.get("version", ""))
		check(not version.is_empty(), "missing version: " + slug)
		var exported: Dictionary = read_json(BASE + "source/" + slug + "/export/" + version + "/export_manifest.json")
		check(version == str(exported.get("version", "")), "runtime/export version mismatch: " + slug)
		var records: Array = exported.get("records", []) as Array
		var expected: int = 0
		for record: Dictionary in records:
			expected += int(record.get("triangle_count", 0))
		var packed: PackedScene = load("res://" + str(manifest.get("prefab", ""))) as PackedScene
		check(packed != null, "cannot load root: " + slug)
		if packed == null:
			continue
		var tower: Node3D = packed.instantiate() as Node3D
		root.add_child(tower)
		var actual: int = triangle_count(tower)
		var meshes: Array[MeshInstance3D] = []
		collect_meshes(tower, meshes)
		check(actual == expected, "runtime triangle mismatch: %s actual=%d expected=%d" % [slug, actual, expected])
		check(str(tower.get_meta("asset_version", "")) == version, "root metadata version mismatch: " + slug)
		check(int(tower.get_meta("component_count", -1)) == records.size(), "root component count mismatch: " + slug)
		check(tower.scale == Vector3.ONE, "root scale changed: " + slug)
		check(tower.find_children("*", "CollisionObject3D", true, false).is_empty(), "visual root gained collision: " + slug)
		report["towers"].append({"slug": slug, "version": version, "runtime_triangles": actual, "expected_triangles": expected, "mesh_instances": meshes.size(), "component_count": records.size()})
		print("RUNTIME_TOWER slug=%s version=%s triangles=%d expected=%d meshes=%d" % [slug, version, actual, expected, meshes.size()])
		tower.free()
	var packed_route: PackedScene = load(BASE + "runtime/cross_tower_route/env_cross_tower_route_root_top3d.tscn") as PackedScene
	check(packed_route != null, "route cannot load")
	if packed_route != null:
		var route: Node = packed_route.instantiate()
		var collision_count: int = route.find_children("*", "CollisionObject3D", true, false).size()
		check(collision_count == 3, "route collision object contract changed")
		for slug: String in ["tower_02", "tower_03"]:
			var route_tower: Node = route.get_node("Tower2" if slug == "tower_02" else "Tower3")
			var manifest: Dictionary = read_json(BASE + "runtime/" + slug + "/asset_manifest.json")
			check(str(route_tower.get_meta("asset_version", "")) == str(manifest.get("version", "")), "route tower metadata mismatch: " + slug)
			var actual: int = triangle_count(route_tower)
			for tower_report: Dictionary in report["towers"]:
				if tower_report["slug"] == slug:
					check(actual == int(tower_report["runtime_triangles"]), "route tower triangle mismatch: " + slug)
					tower_report["route_triangles"] = actual
		report["route_collision_objects"] = collision_count
		route.free()
	report["failures"] = failures
	report["passed"] = failures.is_empty()
	var output: FileAccess = FileAccess.open(OUTPUT, FileAccess.WRITE)
	check(output != null, "cannot save probe report")
	if output != null:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	print("TOWERS_RUNTIME_PROBE_", "OK" if failures.is_empty() else "FAILED")
	quit(0 if failures.is_empty() else 1)
