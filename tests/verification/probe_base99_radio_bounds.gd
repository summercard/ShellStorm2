extends Node

const NIGHTSTAND_PATH := "res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities/loft_nightstand/loft_nightstand_root_top3d.tscn"
const RADIO_PATH := "res://assets/art/props/base_world_3d/runtime/base99_radio/prp_base99_radio_root_top3d.tscn"

func _ready() -> void:
	var nightstand := (load(NIGHTSTAND_PATH) as PackedScene).instantiate()
	var radio := (load(RADIO_PATH) as PackedScene).instantiate()
	add_child(nightstand)
	radio.position = Vector3(-3.20, 7.25, -10.88)
	add_child(radio)
	await get_tree().process_frame
	print("NIGHTSTAND_ROOT %s" % str(nightstand.global_position))
	_dump_bounds("NIGHTSTAND", nightstand)
	_dump_bounds("RADIO_LOCAL", radio)
	for node in nightstand.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var bounds := _world_bounds(mesh)
		print("NIGHTSTAND_MESH %s %s" % [mesh.get_path(), str(bounds)])
	get_tree().quit(0)

func _dump_bounds(label: String, root: Node3D) -> void:
	var bounds := AABB()
	var found := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var candidate := _world_bounds(node as MeshInstance3D)
		if not found:
			bounds = candidate
			found = true
		else:
			bounds = bounds.merge(candidate)
	print("%s %s" % [label, str(bounds)])

func _world_bounds(mesh: MeshInstance3D) -> AABB:
	var local := mesh.get_aabb()
	var result := AABB()
	var found := false
	for index in 8:
		var point := mesh.global_transform * local.get_endpoint(index)
		if not found:
			result = AABB(point, Vector3.ZERO)
			found = true
		else:
			result = result.expand(point)
	return result
