extends Node

const ROUTE_PATH := "res://assets/art/environments/open_world/runtime/cross_tower_route/env_cross_tower_route_root_top3d.tscn"
const FLOOR_PATH := "res://assets/art/environments/tower_descent_3d/runtime/floor_tile_5m/env_tower_floor_tile_5m_root_top3d.tscn"
var _points: Array[Vector3] = []
const FOUNDATION_SCENES := [
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/foundation_tower1_box.tscn",
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/foundation_tower2_box.tscn",
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/foundation_tower3_box.tscn",
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/foundation_skyline08_box.tscn",
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/ground_plane_box.tscn",
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/remote_tower2_a.tscn",
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/remote_tower2_b.tscn",
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/remote_tower3_a.tscn",
	"res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/remote_skyline08_a.tscn",
]

func _ready() -> void:
	call_deferred("_run")

func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _collect(node: Node, parent_transform: Transform3D, parent_visible: bool) -> void:
	var current := parent_transform
	var shown := parent_visible
	if node is Node3D:
		current = parent_transform * (node as Node3D).transform
		shown = parent_visible and (node as Node3D).visible
	if node is MeshInstance3D and shown:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			var box := mesh_node.mesh.get_aabb()
			for index in range(8):
				_points.append(current * box.get_endpoint(index))
	if node is MultiMeshInstance3D and shown:
		var batch := (node as MultiMeshInstance3D).multimesh
		if batch != null and batch.mesh != null:
			var box := batch.mesh.get_aabb()
			for instance_index in range(batch.instance_count):
				var instance_transform := current * batch.get_instance_transform(instance_index)
				for corner in range(8):
					_points.append(instance_transform * box.get_endpoint(corner))
	for child in node.get_children():
		_collect(child, current, shown)

func _bounds(node: Node, parent_transform := Transform3D.IDENTITY) -> Dictionary:
	_points.clear()
	_collect(node, parent_transform, true)
	if _points.is_empty():
		return {"mesh_bounds_found": false}
	var lo := _points[0]
	var hi := lo
	for point in _points:
		lo = lo.min(point)
		hi = hi.max(point)
	return {"min": _vector(lo), "max": _vector(hi), "size": _vector(hi - lo), "center": _vector((lo + hi) * 0.5), "mesh_bounds_found": true}

func _run() -> void:
	var packed := load(ROUTE_PATH) as PackedScene
	if packed == null:
		get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("完整壳体探针必须使用真实渲染器回读 MultiMesh")
		get_tree().quit(2)
		return
	var tower := (load("res://scenes/TowerDescent3D.tscn") as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	for frame in range(8):
		await get_tree().process_frame
	for floor_index in [2, 3, 4, 5]:
		if not tower.call("_commit_floor_bundle", floor_index, "landscape_geometry_probe"):
			push_error("完整楼层提交失败：%d" % floor_index)
			get_tree().quit(2)
			return
		await get_tree().process_frame
	tower.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().process_frame
	var route := tower.get_node("Blocks/Rooftop/CrossTowerRoute") as Node3D
	var report := {"engine": Engine.get_version_info(), "renderer": DisplayServer.get_name(), "route_path": ROUTE_PATH, "targets": {}, "bridge": {}, "city": [], "foundation": [], "independent_loads": [], "main_tower_stages": []}
	var shell_boxes: Array[AABB] = []
	for floor_index in tower._floor_stages:
		var stage := tower._floor_stages[floor_index] as Node3D
		stage.visible = true
		var entry := _bounds(stage, stage.get_parent().global_transform)
		entry["floor_index"] = floor_index
		entry["floor_number"] = stage.get_meta("floor_number", 100 - int(floor_index))
		report["main_tower_stages"].append(entry)
		if entry["mesh_bounds_found"]:
			var lo: Array = entry["min"]
			var hi: Array = entry["max"]
			shell_boxes.append(AABB(Vector3(lo[0], lo[1], lo[2]), Vector3(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])))
	var shell := shell_boxes[0]
	for box in shell_boxes:
		shell = shell.merge(box)
	report["targets"]["Tower1"] = {"min": _vector(shell.position), "max": _vector(shell.end), "size": _vector(shell.size), "mesh_bounds_found": true, "source": "实际提交楼层0至5及下一层入口壳体，真实渲染器逐Mesh/MultiMesh包络"}
	for target_name in ["Tower2", "Tower3", "Skyline08"]:
		var target := route.get_node(target_name) as Node3D
		var entry := _bounds(target, route.transform)
		entry["transform"] = var_to_str(target.transform)
		entry["position"] = _vector(target.position)
		report["targets"][target_name] = entry
	for child in route.get_node("Bridge").get_children():
		report["bridge"][str(child.name)] = _bounds(child, route.transform)
	var floor_packed := load(FLOOR_PATH) as PackedScene
	var floor_node := floor_packed.instantiate() as Node3D
	report["floor98_asset_local"] = _bounds(floor_node)
	floor_node.free()
	var atmosphere := TowerAtmosphere3D.new()
	var layout := atmosphere.build_city_layout()
	for placement in layout:
		var box: AABB = placement["transform"] * AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
		report["city"].append({"ring": placement["ring"], "index": placement["index"], "min": _vector(box.position), "max": _vector(box.end), "size": _vector(placement["size"]), "top_y": placement["top_y"], "transform": var_to_str(placement["transform"])})
	atmosphere.free()
	var foundation := route.get_node("LandscapeFoundation")
	for child in foundation.get_children():
		var entry := _bounds(child)
		entry["name"] = str(child.name)
		entry["position"] = _vector((child as Node3D).position)
		entry["metadata"] = {}
		for key in child.get_meta_list():
			entry["metadata"][str(key)] = child.get_meta(key)
		report["foundation"].append(entry)
	var foundation_packed := load(foundation.scene_file_path) as PackedScene
	var independent := foundation_packed.instantiate()
	report["independent_loads"].append({"path": foundation.scene_file_path, "loaded": independent != null})
	independent.free()
	for scene_path in FOUNDATION_SCENES:
		var component_packed := load(scene_path) as PackedScene
		var component := component_packed.instantiate() if component_packed != null else null
		report["independent_loads"].append({"path": scene_path, "loaded": component != null})
		if component != null:
			component.free()
	var output := OS.get_environment("LANDSCAPE_OUTPUT")
	if output.is_empty():
		push_error("必须显式设置 LANDSCAPE_OUTPUT，不能写入正式存档目录")
		route.free()
		get_tree().quit(2)
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("探针输出路径不可写")
		route.free()
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("LANDSCAPE_RUNTIME_DUMP_OK city=%d foundation=%d output=%s" % [layout.size(), foundation.get_child_count(), output])
	route.free()
	await get_tree().process_frame
	get_tree().quit(0)
