extends SceneTree
## P0-2 acceptance for the L-corner visual wrapper and its standalone collision wrapper.

const LAYOUT := "res://assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d_v002.tscn"
const VISUAL_WRAPPER := "res://assets/art/environments/base_facility_3d/runtime/env_base99_corner_l_5m/env_base99_corner_l_5m_root_top3d_v003.tscn"
const COLLISION_WRAPPER := "res://assets/art/environments/base_facility_3d/runtime/env_base99_corner_l_5m/env_base99_corner_l_5m_root_top3d_v002.tscn"
const EXPECTED_POSITIONS := [
	Vector3(-15, 0, -15),
	Vector3(15, 0, -15),
	Vector3(-15, 0, 15),
	Vector3(15, 0, 15),
]


func _initialize() -> void:
	var errors: Array[String] = []
	var layout_scene := load(LAYOUT) as PackedScene
	if layout_scene == null:
		errors.append("LAYOUT_LOAD_FAILED")
	else:
		var layout := layout_scene.instantiate()
		var corners: Array[Node] = []
		_find_corner_instances(layout, corners)
		if corners.size() != 4:
			errors.append("CORNER_INSTANCE_COUNT %d" % corners.size())
		var positions := {}
		for corner in corners:
			positions[corner.position] = true
			if corner.scene_file_path != VISUAL_WRAPPER:
				errors.append("WRONG_WRAPPER %s -> %s" % [corner.name, corner.scene_file_path])
			if not bool(corner.get_meta("visual_only", false)):
				errors.append("MISSING_VISUAL_ONLY %s" % corner.name)
			if _count_static_bodies(corner) != 0:
				errors.append("COLLISION_IN_LAYOUT_WRAPPER %s" % corner.name)
			if corner.get_node_or_null("ImportedModel") == null:
				errors.append("MISSING_IMPORTED_MODEL %s" % corner.name)
		for expected in EXPECTED_POSITIONS:
			if not positions.has(expected):
				errors.append("MISSING_CORNER_POSITION %s" % expected)
		layout.free()
	var collision_scene := load(COLLISION_WRAPPER) as PackedScene
	if collision_scene == null:
		errors.append("COLLISION_WRAPPER_LOAD_FAILED")
	else:
		var collision_root := collision_scene.instantiate()
		if _count_static_bodies(collision_root) != 2:
			errors.append("COLLISION_WRAPPER_BODY_COUNT %d" % _count_static_bodies(collision_root))
		if _count_collision_shapes(collision_root) != 2:
			errors.append("COLLISION_WRAPPER_SHAPE_COUNT %d" % _count_collision_shapes(collision_root))
		collision_root.free()
	if errors.is_empty():
		print("BASE99_CORNER_WRAPPER_OK instances=4 visual_collision=0 standalone_collision=2")
		quit(0)
	else:
		for error in errors:
			push_error(error)
		print("BASE99_CORNER_WRAPPER_FAILED errors=%d" % errors.size())
		quit(1)


func _find_corner_instances(node: Node, result: Array[Node]) -> void:
	if node.get_meta("asset_id", "") == "ENV-TOWER-CORNER-L-5M":
		result.append(node)
	for child in node.get_children():
		_find_corner_instances(child, result)


func _count_static_bodies(node: Node) -> int:
	var count := 1 if node is StaticBody3D else 0
	for child in node.get_children():
		count += _count_static_bodies(child)
	return count


func _count_collision_shapes(node: Node) -> int:
	var count := 1 if node is CollisionShape3D else 0
	for child in node.get_children():
		count += _count_collision_shapes(child)
	return count
