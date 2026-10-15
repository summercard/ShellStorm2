extends RefCounted
## Colored emission provides an icon shadow floor while retaining PBR shading.
## These overrides belong to the icon; world materials remain shared by items.

const MATERIAL_ROOT := "res://assets/art/items_weapons/shared/materials/"
const SHADOW_FILL_ENERGY := 0.45


static func apply(root: Node, cache: Dictionary) -> void:
	if root is MeshInstance3D:
		var mesh := root as MeshInstance3D
		if mesh.mesh != null:
			for surface in mesh.mesh.get_surface_count():
				var original := mesh.get_active_material(surface) as BaseMaterial3D
				if original == null or not original.resource_path.begins_with(MATERIAL_ROOT):
					continue
				var material := cache.get(original.resource_path) as BaseMaterial3D
				if material == null:
					material = original.duplicate() as BaseMaterial3D
					material.resource_name = original.resource_name + "_图标补光"
					material.emission_enabled = true
					material.emission = Color.WHITE
					material.emission_texture = original.albedo_texture
					material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
					material.emission_energy_multiplier = maxf(original.emission_energy_multiplier if original.emission_enabled else 0.0, SHADOW_FILL_ENERGY)
					material.set_meta("icon_shadow_fill", SHADOW_FILL_ENERGY)
					cache[original.resource_path] = material
				mesh.set_surface_override_material(surface, material)
	for child in root.get_children():
		apply(child, cache)
