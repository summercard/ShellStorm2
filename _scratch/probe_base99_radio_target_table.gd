extends Node

const LAYOUT_PATH: String = "res://assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d.tscn"
const RADIO_PATH: String = "res://assets/art/props/base_world_3d/runtime/base99_radio/prp_base99_radio_root_top3d.tscn"

func _ready() -> void:
	var layout_scene: PackedScene = load(LAYOUT_PATH) as PackedScene
	var radio_scene: PackedScene = load(RADIO_PATH) as PackedScene
	if layout_scene == null or radio_scene == null:
		push_error("TARGET_TABLE_PROBE_FAIL: formal layout or radio scene missing")
		get_tree().quit(1)
		return
	var layout: Node3D = layout_scene.instantiate() as Node3D
	add_child(layout)
	await get_tree().process_frame
	await get_tree().physics_frame
	var radio: Node3D = layout.find_child("99F床边桌独立收音机", true, false) as Node3D
	var nightstand: Node3D = layout.find_child("32_参考床头柜与生活物件_资产包", true, false) as Node3D
	var bed: Node3D = layout.find_child("31_参考床架床品与床下收纳_资产包", true, false) as Node3D
	print("TARGET_LAYOUT_ROOT name=%s children=%d" % [layout.name, layout.get_child_count()])
	_dump_node("RADIO_FORMAL", radio)
	_dump_node("NIGHTSTAND_TARGET", nightstand)
	_dump_node("BED_TARGET", bed)
	if nightstand != null:
		for value in nightstand.find_children("*", "MeshInstance3D", true, false):
			_dump_mesh("NIGHTSTAND_MESH", value as MeshInstance3D)
	if bed != null:
		for value in bed.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = value as MeshInstance3D
			var b: AABB = _world_bounds(mesh)
			if b.position.y >= 6.0 or b.end.y >= 6.0:
				_dump_mesh("BED_HIGH_MESH", mesh)
	print("NORTH_NEARBY_BEGIN")
	for value in layout.find_children("*", "Node3D", true, false):
		var node: Node3D = value as Node3D
		if node == null or node == radio or node == nightstand or node == bed:
			continue
		var bounds: AABB = _node_world_bounds(node)
		if bounds.size != Vector3.ZERO and bounds.position.z < -8.0 and bounds.end.z < -7.0 and bounds.position.y > 5.0:
			print("NEARBY name=%s parent=%s origin=%s bounds_pos=%s bounds_size=%s" % [node.name, node.get_parent().name, _v(node.global_position), _v(bounds.position), _v(bounds.size)])
	print("TARGET_TABLE_PROBE_OK")
	get_tree().quit(0)

func _dump_node(label: String, node: Node3D) -> void:
	if node == null:
		print("%s MISSING" % label)
		return
	var bounds: AABB = _node_world_bounds(node)
	print("%s name=%s parent=%s origin=%s yaw=%.4f bounds_pos=%s bounds_size=%s" % [label, node.name, node.get_parent().name, _v(node.global_position), node.global_rotation.y, _v(bounds.position), _v(bounds.size)])

func _dump_mesh(label: String, mesh: MeshInstance3D) -> void:
	if mesh == null or mesh.mesh == null:
		return
	var b: AABB = _world_bounds(mesh)
	print("%s path=%s name=%s origin=%s bounds_pos=%s bounds_size=%s" % [label, str(mesh.get_path()), mesh.name, _v(mesh.global_position), _v(b.position), _v(b.size)])

func _node_world_bounds(node: Node3D) -> AABB:
	var result: AABB = AABB()
	var found: bool = false
	for value in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = value as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var b: AABB = _world_bounds(mesh)
		result = b if not found else result.merge(b)
		found = true
	return result if found else AABB()

func _world_bounds(mesh: MeshInstance3D) -> AABB:
	var local: AABB = mesh.get_aabb()
	var result: AABB = AABB()
	var found: bool = false
	for index in 8:
		var point: Vector3 = mesh.global_transform * local.get_endpoint(index)
		result = AABB(point, Vector3.ZERO) if not found else result.expand(point)
		found = true
	return result

func _v(value: Vector3) -> String:
	return "(%.5f, %.5f, %.5f)" % [value.x, value.y, value.z]
