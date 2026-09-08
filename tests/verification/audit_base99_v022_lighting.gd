extends SceneTree

const ROOT_SCENE := "res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities_v021/env_base99_remaining_facilities_root_top3d_v003.tscn"

func _init() -> void:
	var scene := load(ROOT_SCENE) as PackedScene
	var root := scene.instantiate()
	var imported_light_count := 0
	for node in root.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		imported_light_count += 1
		print("LIGHT_AUDIT name=", light.name, " type=", light.get_class(), " energy=", light.light_energy, " indirect=", light.light_indirect_energy, " color=", light.light_color, " range=", light.omni_range if light is OmniLight3D else -1.0)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null: continue
		for i in mesh_node.mesh.get_surface_count():
			var material := mesh_node.get_active_material(i) as StandardMaterial3D
			if material != null and material.emission_enabled and material.emission_energy_multiplier > 1.5:
				print("EMISSION_AUDIT name=", mesh_node.name, " material=", material.resource_name, " energy=", material.emission_energy_multiplier, " color=", material.emission)
	assert(imported_light_count == 0, "Updated facility GLBs must not contain DCC lights")
	print("BASE99_V022_LIGHT_AUDIT_OK imported_lights=0")
	root.free()
	quit()
