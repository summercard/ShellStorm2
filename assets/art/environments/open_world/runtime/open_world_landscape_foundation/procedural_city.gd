extends Node3D

@export_file("*.json") var parameters_path := "res://assets/art/environments/open_world/runtime/open_world_landscape_foundation/city_generation_parameters.json"
var placements: Array[Dictionary] = []
var keepouts: Array[Dictionary] = []
var sectors: Array[Dictionary] = []
var parameters: Dictionary = {}
var binding_complete := false

func _ready() -> void:
	_build.call_deferred()

func _build() -> void:
	parameters = JSON.parse_string(FileAccess.get_file_as_string(parameters_path))
	var cities := get_tree().root.find_children("CityBuildingSilhouettes", "MultiMeshInstance3D", true, false)
	if cities.is_empty():
		set_meta("binding_status", "独立预览无原城市；正式运行需现有城市网格")
		return
	var old_city := cities[0] as MultiMeshInstance3D
	var route := get_parent().get_parent() as Node3D
	var main: Array = parameters["main_tower_footprint"]
	keepouts.append({"name": "Tower1_body_and_foundation", "rect": Rect2(main[0], main[1], main[2], main[3]), "kind": "body"})
	for target in ["Tower2", "Tower3", "Skyline08"]:
		_collect_keepouts(route.get_node(target), target)
	_collect_keepouts(route.get_node("Bridge"), "Bridge")
	for child in get_parent().get_children():
		if child is MeshInstance3D and child.name != "OpenWorldGroundPlane":
			_add_keepout(child as MeshInstance3D, "landscape")
	# 原城市布局由生产表读取；此处不依赖无头MultiMesh回读。
	var atmosphere := old_city.get_parent().get_parent()
	var legacy: Array = atmosphere.call("get_city_layout")
	for i in range(old_city.multimesh.instance_count):
		var box: AABB = old_city.global_transform * legacy[i]["transform"] * old_city.multimesh.mesh.get_aabb()
		keepouts.append({"name": "legacy_%d" % i, "kind": "legacy", "rect": Rect2(box.position.x, box.position.z, box.size.x, box.size.z)})
	_generate()
	for sector in sectors:
		var members: Array = sector["members"]
		if members.is_empty():
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = old_city.multimesh.mesh
		multi.instance_count = members.size()
		var batch := MultiMeshInstance3D.new()
		batch.name = "Sector_%02d_%02d" % [sector["x"], sector["z"]]
		batch.multimesh = multi
		batch.cast_shadow = old_city.cast_shadow
		batch.visibility_range_end = float(parameters["visibility_range_end_m"])
		batch.visibility_range_end_margin = 40.0
		add_child(batch)
		for i in range(members.size()):
			var index: int = members[i]
			multi.set_instance_transform(i, global_transform.affine_inverse() * placements[index]["transform"])
			placements[index]["batch"] = str(batch.name)
			placements[index]["instance"] = i
	binding_complete = true
	set_meta("binding_status", "现有城市同一mesh/material对象；分区MultiMesh")
	var clouds := get_tree().root.find_children("OutdoorClouds", "Node3D", true, false)
	if not clouds.is_empty() and clouds[0].has_method("set_procedural_city_layout"):
		clouds[0].call("set_procedural_city_layout", placements, parameters)

func _collect_keepouts(node: Node, target: String) -> void:
	if node is MeshInstance3D:
		_add_keepout(node as MeshInstance3D, target)
	for child in node.get_children():
		_collect_keepouts(child, target)

func _add_keepout(node: MeshInstance3D, target: String) -> void:
	if node.mesh == null:
		return
	var box: AABB = node.global_transform * node.mesh.get_aabb()
	var path := str(node.get_path())
	var kind := "bridge" if target == "Bridge" else "landscape" if target == "landscape" else "crane" if "crane" in path.to_lower() or "塔吊" in path else "body"
	keepouts.append({"name": path, "kind": kind, "rect": Rect2(box.position.x, box.position.z, box.size.x, box.size.z)})

func _generate() -> void:
	var center: Array = parameters["center_xz"]
	var extent: float = parameters["extent_m"]
	var spacing: float = parameters["spacing_m"]
	var margin: float = parameters["edge_margin_m"]
	var clearance: float = parameters["keepout_clearance_m"]
	var minimum := Vector2(center[0] - extent * 0.5, center[1] - extent * 0.5)
	var grid := int(extent / spacing)
	var divisions: int = parameters["sector_divisions"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(parameters["seed"])
	for z in range(divisions):
		for x in range(divisions):
			sectors.append({"x": x, "z": z, "members": [], "candidates": 0, "rejected": 0})
	for gz in range(grid):
		for gx in range(grid):
			var width := rng.randf_range(parameters["width_m"][0], parameters["width_m"][1])
			var depth := rng.randf_range(parameters["depth_m"][0], parameters["depth_m"][1])
			var jitter: float = parameters["jitter_m"]
			var point := minimum + Vector2((gx + 0.5) * spacing, (gz + 0.5) * spacing) + Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
			var sx := mini(divisions - 1, int((point.x - minimum.x) / (extent / divisions)))
			var sz := mini(divisions - 1, int((point.y - minimum.y) / (extent / divisions)))
			var sector: Dictionary = sectors[sz * divisions + sx]
			sector["candidates"] += 1
			var rect := Rect2(point - Vector2(width, depth) * 0.5, Vector2(width, depth))
			var allowed := Rect2(minimum + Vector2.ONE * margin, Vector2.ONE * (extent - margin * 2.0)).encloses(rect)
			for keepout in keepouts:
				if rect.grow(clearance).intersects(keepout["rect"], true):
					allowed = false
					break
			# 每个格点最多一栋；最大足迹/抖动约束保证街道净宽，另作实例间精确拒绝。
			for previous in placements:
				if rect.grow(float(parameters["building_clearance_m"])).intersects(previous["rect"], true):
					allowed = false
					break
			var variation := rng.randf_range(-float(parameters["height_stagger_m"]), float(parameters["height_stagger_m"]))
			if not allowed:
				sector["rejected"] += 1
				continue
			var nearest := INF
			for keepout in keepouts:
				if keepout["kind"] in ["body", "landscape"]:
					var body: Rect2 = keepout["rect"]
					var offset := Vector2(maxf(maxf(body.position.x - point.x, point.x - body.end.x), 0), maxf(maxf(body.position.y - point.y, point.y - body.end.y), 0))
					nearest = minf(nearest, offset.length())
			var top_range: Array = parameters["top_height_range_y"]
			var top := clampf(lerpf(top_range[1], top_range[0], clampf(nearest / float(parameters["height_falloff_m"]), 0, 1)) + variation, top_range[0], top_range[1])
			var ground: float = parameters["ground_y"]
			var height := top - ground
			var transform := Transform3D(Basis.IDENTITY.scaled(Vector3(width, height, depth)), Vector3(point.x, (top + ground) * 0.5, point.y))
			sector["members"].append(placements.size())
			placements.append({"grid_x": gx, "grid_z": gz, "sector_x": sx, "sector_z": sz, "rect": rect, "top_y": top, "bottom_y": ground, "transform": transform})

func get_city_snapshot() -> Dictionary:
	return {"placements": placements.duplicate(true), "keepouts": keepouts.duplicate(true), "sectors": sectors.duplicate(true), "parameters": parameters.duplicate(true), "binding_complete": binding_complete}
