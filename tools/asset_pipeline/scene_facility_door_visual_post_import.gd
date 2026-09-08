@tool
extends EditorScenePostImport
## Door-only palette import: protects the deep painted-metal look under the
## base camp's strong directional daylight without changing gameplay nodes.

const SHARED_PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"


func _post_import(scene: Node) -> Object:
	var palette := load(SHARED_PALETTE_PATH) as Texture2D
	if palette == null:
		push_error("SCENE_FACILITY_SHARED_PALETTE_MISSING: %s" % SHARED_PALETTE_PATH)
		return scene
	_apply_door_palette(scene, palette)
	return scene


func _apply_door_palette(root: Node, palette: Texture2D) -> void:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				var material := mesh.surface_get_material(surface_index) as BaseMaterial3D
				if material == null:
					continue
				material.albedo_texture = palette
				material.emission_texture = palette
				material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				material.texture_repeat = false
				# Blender's studio exposure keeps these palette cells deep. The game
				# has a 3.0-energy sunrise sun, so the structural metal needs a more
				# diffuse response to retain the authored deep graphite silhouette.
				match material.resource_name:
					"01_精工金属_紫色骨架":
						material.albedo_color = Color(0.48, 0.50, 0.55, 1.0)
						material.metallic = 0.34
						material.roughness = 0.55
					"02_细腻哑光_青绿大面":
						material.albedo_color = Color(0.56, 0.58, 0.63, 1.0)
						material.metallic = 0.03
						material.roughness = 0.76
					"03_清漆反光_紫粉点缀":
						material.albedo_color = Color(0.66, 0.64, 0.70, 1.0)
						material.metallic = 0.08
						material.roughness = 0.32
	for child in root.get_children():
		_apply_door_palette(child, palette)
