extends Node
## 天台女儿墙参考组件探针：实测导出 GLB 的包络、原点、色盘材质绑定与 L 角朝向。
## 纯诊断，不算门禁；输出 PROBE_* 行供与 asset_manifest.json 逐值比对。

const PARAPET_GLB := "res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_parapet_top3d.glb"
const CORNER_GLB := "res://assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_parapet_outer_top3d.glb"
## 高度不写字面量，直接取运行时的口径常量 —— 资产包络必须等于「脚本声明的女儿墙高度」，
## 这条正是「BLENDER 改了高度而 TowerFloorStage3D 没跟着改」会立刻爆红的哨兵。
## 2026-09-20 起该常量为 0.80m（方案A 平整墙板，含压顶总高）。
const EXPECTED := {
	"parapet": Vector3(5.0, TowerFloorStage3D.ROOFTOP_PARAPET_HEIGHT, 0.5),
	"outer_corner": Vector3(2.5, TowerFloorStage3D.ROOFTOP_PARAPET_HEIGHT, 2.5),
}


func _ready() -> void:
	_report("parapet", PARAPET_GLB)
	_report("outer_corner", CORNER_GLB)
	print("PROBE_ROOFTOP_PARAPET_DONE")
	get_tree().quit(0)


func _report(label: String, path: String) -> void:
	var scene: PackedScene = load(path)
	if scene == null:
		print("PROBE_FAIL %s cannot load %s" % [label, path])
		return
	var instance := scene.instantiate()
	add_child(instance)
	var mesh_instance := _find_mesh(instance)
	if mesh_instance == null:
		print("PROBE_FAIL %s has no MeshInstance3D" % label)
		remove_child(instance)
		instance.free()
		return
	var mesh := mesh_instance.mesh
	var aabb := mesh.get_aabb()
	var expected: Vector3 = EXPECTED[label]
	var size_ok := aabb.size.is_equal_approx(expected)
	print(
		"PROBE %s aabb_pos=%s aabb_size=%s expected=%s size_match=%s base_y=%.4f"
		% [label, aabb.position, aabb.size, expected, size_ok, aabb.position.y]
	)
	print("PROBE %s surface_count=%d" % [label, mesh.get_surface_count()])
	for index in range(mesh.get_surface_count()):
		var material := mesh.surface_get_material(index)
		var material_name := "<null>"
		var palette_bound := false
		if material is BaseMaterial3D:
			material_name = String(material.resource_name)
			palette_bound = (material as BaseMaterial3D).albedo_texture != null
		print(
			"PROBE %s surface=%d material=%s palette_texture_bound=%s"
			% [label, index, material_name, palette_bound]
		)
	_report_quadrants(label, mesh)
	remove_child(instance)
	instance.free()


func _report_quadrants(label: String, mesh: Mesh) -> void:
	var vertices := PackedVector3Array()
	for index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(index)
		vertices.append_array(arrays[Mesh.ARRAY_VERTEX])
	if vertices.is_empty():
		print("PROBE %s has no vertices" % label)
		return
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for point in vertices:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.z)
		max_z = maxf(max_z, point.z)
	var mid_x := (min_x + max_x) * 0.5
	var mid_z := (min_z + max_z) * 0.5
	var counts := {"-X-Z": 0, "-X+Z": 0, "+X-Z": 0, "+X+Z": 0}
	for point in vertices:
		var key := ("+X" if point.x >= mid_x else "-X") + ("+Z" if point.z >= mid_z else "-Z")
		counts[key] = int(counts[key]) + 1
	print(
		"PROBE %s xz_bounds=[%.3f,%.3f]~[%.3f,%.3f] quadrant_vertex_counts=%s"
		% [label, min_x, min_z, max_x, max_z, counts]
	)


func _find_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	for child in root.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
