extends SceneTree

## Exports only Godot's native 100F shell as a Blender comparison reference.
## It deliberately excludes the rooftop facilities scene and every collider.

const OUTPUT_PATH := "res://assets/art/environments/rooftop_shelter_3d/references/godot_100f_native_rooftop_reference_v001.glb"


func _initialize() -> void:
	var rooftop := TowerFloorStage3D.new()
	rooftop.configure(0, "rooftop", ["west"])
	get_root().add_child(rooftop)
	await process_frame

	var reference := Node3D.new()
	reference.name = "Godot100FNativeRooftopReference"
	get_root().add_child(reference)
	_copy_floor_from_native_contract(
		rooftop.get_node_or_null("ImportedFloorTileGrid5M_A") as MultiMeshInstance3D,
		rooftop.get_node_or_null("ImportedFloorTileGrid5M_B") as MultiMeshInstance3D,
		reference
	)
	_copy_parapets_from_native_contract(
		rooftop.get_node_or_null("ImportedOuterParapetGrid5M") as MultiMeshInstance3D,
		reference
	)
	for node in rooftop.get_children():
		if node.name.begins_with("ParapetDoorWall_"):
			_copy_mesh_descendants(node, reference)

	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error := document.append_from_scene(reference, state)
	if append_error != OK:
		push_error("Godot 100F native rooftop reference could not be converted to GLTF: %s" % append_error)
		quit(1)
		return
	var write_error := document.write_to_filesystem(state, OUTPUT_PATH)
	if write_error != OK:
		push_error("Godot 100F native rooftop reference could not be written: %s" % write_error)
		quit(1)
		return
	print("GODOT_ROOFTOP_REFERENCE_EXPORTED: %s" % OUTPUT_PATH)
	quit(0)


func _append_mesh(target: Node3D, name: String, mesh: Mesh, material: Material, transform: Transform3D) -> void:
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.material_override = material
	target.add_child(instance)
	instance.transform = transform


func _copy_floor_from_native_contract(light: MultiMeshInstance3D, dark: MultiMeshInstance3D, target: Node3D) -> void:
	if light == null or dark == null or light.multimesh == null or dark.multimesh == null:
		push_error("Missing native 100F floor visuals")
		return
	var light_index := 0
	var dark_index := 0
	for z_index in range(16):
		for x_index in range(18):
			var in_atrium := x_index >= 7 and x_index < 13 and z_index >= 5 and z_index < 11
			var in_west_stair := x_index >= 1 and x_index < 4 and z_index >= 7 and z_index < 13
			if in_atrium or in_west_stair:
				continue
			var transform := Transform3D(Basis.IDENTITY, Vector3(-47.5 + x_index * 5.0, -0.15, -32.5 + z_index * 5.0))
			if (x_index + z_index) % 2 == 0:
				_append_mesh(target, "FloorLight_%03d" % light_index, light.multimesh.mesh, light.material_override, transform)
				light_index += 1
			else:
				_append_mesh(target, "FloorDark_%03d" % dark_index, dark.multimesh.mesh, dark.material_override, transform)
				dark_index += 1
	print("native_floor_tiles_exported=", light_index + dark_index)


func _copy_parapets_from_native_contract(source: MultiMeshInstance3D, target: Node3D) -> void:
	if source == null or source.multimesh == null:
		push_error("Missing native 100F parapet visual")
		return
	var index := 0
	for x_index in range(18):
		var x := -47.5 + x_index * 5.0
		_append_mesh(target, "Parapet_%03d" % index, source.multimesh.mesh, source.material_override, Transform3D(Basis.IDENTITY, Vector3(x, 0.375, -34.85)))
		index += 1
		_append_mesh(target, "Parapet_%03d" % index, source.multimesh.mesh, source.material_override, Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0.375, 44.85)))
		index += 1
	for z_index in range(16):
		var z := -32.5 + z_index * 5.0
		if absf(z - 15.0) > 5.0:
			_append_mesh(target, "Parapet_%03d" % index, source.multimesh.mesh, source.material_override, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-49.85, 0.375, z)))
			index += 1
		_append_mesh(target, "Parapet_%03d" % index, source.multimesh.mesh, source.material_override, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(39.85, 0.375, z)))
		index += 1
	print("native_parapets_exported=", index)


func _copy_mesh_descendants(source: Node, target: Node3D) -> void:
	if source is MeshInstance3D:
		var source_mesh := source as MeshInstance3D
		if source_mesh.mesh != null:
			var copy := MeshInstance3D.new()
			copy.name = "Door_%s" % source_mesh.name
			copy.mesh = source_mesh.mesh
			copy.material_override = source_mesh.material_override
			target.add_child(copy)
			copy.global_transform = source_mesh.global_transform
	for child in source.get_children():
		_copy_mesh_descendants(child, target)
