@tool
extends "res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"
## Manor rugs are woven fabric. Keep their shared PaletteUV colors and remove
## the metal/clearcoat highlights used by the source library's general roles.

func _post_import(scene: Node) -> Object:
	super._post_import(scene)
	_make_fabric_matte(scene, {})
	return scene

func _make_fabric_matte(node: Node, converted: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface in mesh.get_surface_count():
				var original := mesh.surface_get_material(surface) as BaseMaterial3D
				if original == null:
					continue
				var fabric := converted.get(original) as BaseMaterial3D
				if fabric == null:
					fabric = original.duplicate() as BaseMaterial3D
					fabric.resource_name = original.resource_name
					fabric.metallic = 0.0
					fabric.metallic_specular = 0.0
					fabric.roughness = 0.96
					fabric.clearcoat_enabled = false
					fabric.emission_enabled = false
					converted[original] = fabric
				mesh.surface_set_material(surface, fabric)
	for child in node.get_children():
		_make_fabric_matte(child, converted)
