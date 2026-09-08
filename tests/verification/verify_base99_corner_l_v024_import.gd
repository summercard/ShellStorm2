extends SceneTree

const CORNER_SCENE := preload("res://assets/art/environments/base_facility_3d/runtime/env_base99_corner_l_5m/env_base99_corner_l_5m_root_top3d_v002.tscn")
const PALETTE := preload("res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png")
const DUNGEON_ROOM_SCRIPT := "res://src/world3d/DungeonRoom3D.gd"
const ART_LAYOUT_PATH := "res://assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d_v002.tscn"
const FLOOR_STAGE_SCRIPT := "res://src/world3d/TowerFloorStage3D.gd"

var failures: Array[String] = []

func _init() -> void:
	var root := CORNER_SCENE.instantiate() as Node3D
	get_root().add_child(root)
	_check(root != null, "corner wrapper instantiates")
	_check(root.get_meta("asset_id", "") == "ENV-TOWER-CORNER-L-5M", "stable asset id")
	_check(bool(root.get_meta("preserve_authored_palette", false)), "authored palette is protected from generic wall override")
	_check(root.get_node_or_null("ImportedModel") != null, "Blender visual is present")
	_check_collision(root, "CollisionLong", Vector3(5.0, 9.0, 0.3), Vector3(2.5, 4.5, 0.0))
	_check_collision(root, "CollisionShort", Vector3(0.3, 9.0, 5.0), Vector3(0.0, 4.5, -2.5))
	var mesh_count := 0
	var visual_bounds := AABB()
	var has_visual_bounds := false
	var long_rib_levels := {}
	var short_rib_levels := {}
	for mesh_instance in _mesh_nodes(root):
		mesh_count += 1
		var transformed_bounds := _transform_relative_to(mesh_instance, root) * mesh_instance.mesh.get_aabb()
		visual_bounds = visual_bounds.merge(transformed_bounds) if has_visual_bounds else transformed_bounds
		has_visual_bounds = true
		var material := mesh_instance.get_active_material(0) as BaseMaterial3D
		_check(material != null and material.albedo_texture == PALETTE, "shared palette is rebound on imported mesh")
		_check(material != null and material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "palette uses nearest filtering")
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
			for vertex in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
				if vertex.x > 0.20 and vertex.x < 4.80 and vertex.z < -0.09 and vertex.z > -0.16:
					long_rib_levels[snappedf(vertex.y, 0.001)] = true
				if vertex.x > 0.09 and vertex.x < 0.16 and vertex.z < -0.20 and vertex.z > -4.80:
					short_rib_levels[snappedf(vertex.y, 0.001)] = true
	_check(mesh_count > 0, "GLB contains visual mesh")
	_check(has_visual_bounds and visual_bounds.position.x < -0.09 and visual_bounds.end.x > 4.9, "Godot visual contains the full X arm")
	_check(has_visual_bounds and visual_bounds.position.z < -4.9 and visual_bounds.end.z > 0.09, "Godot visual contains the full -Z arm")
	_check(long_rib_levels.size() >= 10, "Godot visual retains all long-arm horizontal rib levels")
	_check(short_rib_levels.size() >= 10, "Godot visual retains all short-arm horizontal rib levels")
	var layout_text := FileAccess.get_file_as_string(ART_LAYOUT_PATH)
	for corner_name in ["V024西北L型转角墙_仅视觉", "V024东北L型转角墙_仅视觉", "V024西南L型转角墙_仅视觉", "V024东南L型转角墙_仅视觉"]:
		_check(layout_text.contains("[node name=\"" + corner_name + "\""), "active base art layout contains " + corner_name)
	var code := FileAccess.get_file_as_string(DUNGEON_ROOM_SCRIPT)
	_check(code.contains("BASE99_CORNER_L_PREFAB") and code.contains('BASE99_CORNER_L_PREFAB if room_type == "FACILITY" else TOWER_CORNER_L_PREFAB'), "only facility rooms select the base corner visual")
	_check(code.contains("preserve_authored_palette"), "runtime keeps authored material for this corner")
	_check(code.contains("_set_corner_visual_visible(module, false)"), "runtime keeps Facility corner module collision-only")
	var stage_code := FileAccess.get_file_as_string(FLOOR_STAGE_SCRIPT)
	_check(stage_code.contains("BASE99_CORNER_L_VISUAL"), "Base99 outer shell imports the corner GLB")
	_check(stage_code.contains("_install_base99_outer_corner_visuals"), "Base99 outer shell replaces four visible outer corners")
	_check(stage_code.contains("Base99OuterCorner_NW") and stage_code.contains("Base99OuterCorner_SE"), "all four outer corner instances are declared")
	root.free()
	if failures.is_empty():
		print("BASE99_CORNER_L_V024_IMPORT_OK: both L arms, horizontal ribs, palette, outer-shell routing, and collision contract retained")
		quit(0)
		return
	push_error("BASE99_CORNER_L_V024_IMPORT_FAILED: " + "; ".join(failures))
	quit(1)

func _check_collision(root: Node3D, name: String, expected_size: Vector3, expected_position: Vector3) -> void:
	var collision := root.find_child(name, true, false) as CollisionShape3D
	_check(collision != null, name + " exists")
	if collision == null:
		return
	_check(collision.position.is_equal_approx(expected_position), name + " transform")
	var shape := collision.shape as BoxShape3D
	_check(shape != null and shape.size.is_equal_approx(expected_size), name + " dimensions")

func _mesh_nodes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		result.append(root as MeshInstance3D)
	for child in root.get_children():
		result.append_array(_mesh_nodes(child))
	return result

func _transform_relative_to(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
