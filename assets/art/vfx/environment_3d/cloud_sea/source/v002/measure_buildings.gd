extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func box_record(b: AABB) -> Dictionary:
	return {"min": vec(b.position), "max": vec(b.end), "size": vec(b.size)}

func transformed_box(b: AABB, xform: Transform3D) -> AABB:
	var result := AABB(xform * b.get_endpoint(0), Vector3.ZERO)
	for i in range(1, 8):
		result = result.expand(xform * b.get_endpoint(i))
	return result

func visible_meshes(node: Node, meshes: Array[Dictionary]) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			var b := transformed_box(mesh_node.mesh.get_aabb(), mesh_node.global_transform)
			meshes.append({"path": str(mesh_node.get_path()), "box": b})
	for child in node.get_children():
		visible_meshes(child, meshes)

func subtree_record(node: Node) -> Dictionary:
	var meshes: Array[Dictionary] = []
	visible_meshes(node, meshes)
	var union := AABB()
	var found := false
	var parts: Array[Dictionary] = []
	for rec in meshes:
		var b: AABB = rec["box"]
		union = union.merge(b) if found else b
		found = true
		var item := box_record(b)
		item["path"] = rec["path"]
		parts.append(item)
	var record := box_record(union)
	record["mesh_count"] = meshes.size()
	record["parts"] = parts
	return record

func run() -> void:
	var tower := load("res://scenes/TowerDescent3D.tscn").instantiate() as Node3D
	tower.set("test_mode", true)
	tower.set("run_seed_override", 990095)
	root.add_child(tower)
	for frame in range(12):
		await physics_frame
	var route := tower.get_node("Blocks/Rooftop/CrossTowerRoute")
	var atmosphere := tower.get_node("TowerAtmosphere3D")
	var city: Array[Dictionary] = []
	var unit_box := AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	for placement: Dictionary in atmosphere.call("get_city_layout"):
		var world_xform: Transform3D = atmosphere.global_transform * (placement["transform"] as Transform3D)
		var rec := box_record(transformed_box(unit_box, world_xform))
		rec["ring"] = placement["ring"]
		rec["index"] = placement["index"]
		rec["top_y"] = placement["top_y"]
		city.append(rec)
	var report := {
		"snapshot_scene_sha256": FileAccess.get_sha256("res://scenes/TowerDescent3D.tscn"),
		"snapshot_route_sha256": FileAccess.get_sha256("res://assets/art/environments/open_world/runtime/cross_tower_route/env_cross_tower_route_root_top3d.tscn"),
		"floor_height": 12.0,
		"floor_100_y": 0.0,
		"floor_99_y": -12.0,
		"main_tower": {"min": [-50.0, -100000.0, -35.0], "max": [50.0, 0.5, 45.0], "contract": "TowerFloorStage3D.TOWER_SHELL_WORLD_RECT; conservative occupied building volume below rooftop"},
		"tower2": subtree_record(route.get_node("Tower2")),
		"tower3": subtree_record(route.get_node("Tower3")),
		"route_bridge": subtree_record(route.get_node("Bridge")),
		"route_all": subtree_record(route),
		"main_base_art": subtree_record(tower.get("_facility_art_layout") as Node),
		"main_rooftop_room": subtree_record(tower.get_node("Blocks/Rooftop/start")),
		"city": city,
		"renderer": DisplayServer.get_name()
	}
	var file := FileAccess.open("res://assets/art/vfx/environment_3d/cloud_sea/source/v002/building_snapshot.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	for key in ["tower2", "tower3", "route_bridge", "main_base_art", "main_rooftop_room"]:
		var summary: Dictionary = report[key].duplicate()
		summary.erase("parts")
		print("CLOUD_BOUNDARY ", key, " ", JSON.stringify(summary))
	print("CLOUD_BOUNDARY city_count=", city.size())
	quit()
